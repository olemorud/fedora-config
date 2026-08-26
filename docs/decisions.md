# Decisions

Short notes on choices that are not obvious from the code.

## Packages

- `ansible.builtin.dnf5` instead of `dnf`: Fedora 41+ ships dnf5 only.
- RPM Fusion is enabled for `ffmpeg` and `mesa-va-drivers-freeworld`
  (hardware video decode on the RX 6800). Both replace Fedora packages,
  hence `allowerasing`. Everything else is Fedora or Flathub.
- No GPU driver packages: amdgpu and Mesa are in the base install.
  `steam-devices` is the only hardware-related extra (controller udev
  rules for the Steam flatpak).
- Flatpak is used for end-user GUI apps. virt-manager is an RPM because it
  needs libvirt on the host. Libvirt uses the modular `virt*d` sockets;
  `libvirtd.service` is deprecated.
- `vim-X11` provides `vimx`, the only Fedora vim build with `+clipboard`.
  It runs under XWayland. `alias vim=vimx` lives in the zsh aliases.
- The lint tools (`python3-ansible-lint`, `yamllint`, `ShellCheck`) are in
  the package list so `make lint` works on the managed machine.

## Memory: zswap + swap file, no zram

Fedora's default is an 8 GiB zram device and no disk swap. This config
replaces it with a 16 GiB Btrfs swap file behind zswap. Reasoning, from
the ground up:

**What swap is for.** Memory holds anonymous pages (heaps, stacks) and
file pages (page cache). Under pressure the kernel must evict something.
Without swap it can only drop file pages, so cold heap data of long-lived
processes (browser, IDE, VMs) stays pinned while the cache the active
work needs gets evicted and re-read. Swap gives cold anonymous pages
somewhere to go. This holds at 32 GiB too; it is about what is cold, not
how much RAM there is.

**zram** is a compressed RAM block device with swap on it. The kernel
treats it like any other disk. It has a hard capacity; when it fills, no
eviction happens. The only outcomes are OOM kill or spilling to a
lower-priority disk swap. The spill case is the trap: zram keeps whatever
was swapped out first (cold, boot-time data) and pushes the newer, hotter
pages to disk. This "LRU inversion" gets worse with uptime. zram also
lies to reclaim: a thin-provisioned device reports free slots that need
RAM the system no longer has, which has produced 20-30 minute hangs with
no OOM kill in production (Cloudflare, March 2026). Fedora's zram-only
default is coherent only together with systemd-oomd and no disk swap.

**zswap** is not a block device. It sits in the reclaim path in front of
real swap, compresses pages into a RAM pool, and when the pool fills (or
its shrinker decides pages are cold) writes the oldest ones to the backing
swap. Hot data stays in compressed RAM, cold data goes to disk, the
kernel decides continuously based on live pressure. Incompressible pages
are rejected straight to disk instead of wasting RAM. Under overload it
degrades to disk speed instead of hanging. Upstream MM maintainers are
steering everyone towards zswap and away from zram.

**This machine.** 32 GiB, one fast NVMe, Btrfs, a workload with VMs,
Steam and compiles. There is fast storage, so the "no disk" argument for
zram does not apply. The MM maintainers' summary: if in doubt use zswap,
and do not run zram next to disk swap. Hence:

- `zram-generator-defaults` removed (no zram device after reboot).
- 16 GiB swap file in its own Btrfs subvolume `/swap`, created with
  `btrfs filesystem mkswapfile` (NOCOW, preallocated). A nested subvolume
  keeps it out of root snapshots, which cannot include an active swap
  file. Btrfs swap files require a single-device filesystem.
- zswap enabled via `zswap.service` with the zstd compressor. Not on the
  kernel command line, because zstd is a module in the Fedora kernel and
  is not loadable when zswap initialises at boot; a command-line
  `zswap.compressor=zstd` silently falls back to lzo. Pool limit stays at
  the 20% default (6.4 GiB compressed, roughly 3x that in pages). The
  zswap shrinker is on by default in the Fedora kernel.
- `vm.swappiness=100`. Kernel docs: values above 100 are reasonable when
  swap is faster than the filesystem; 100 means equal cost. 60 assumes a
  slow disk.
- systemd-oomd stays on. With disk swap it kills only when swap is over
  90% used or pressure stays high for 20 s, which is what you want as a
  last line instead of a first one.

Size: 16 GiB is half of RAM, large enough that zswap always has room to
write back, small on a 960 GB disk. Hibernation would need swap larger
than used RAM and Fedora blocks it under Secure Boot lockdown anyway.

Data written back to the swap file lands on disk. If the disk is not
LUKS encrypted, that is a change from zram, which never touched disk.

Sources: Chris Down, "Debunking zswap and zram myths" (2026-03-24) and
"In defence of swap" (2018); kernel admin-guide `mm/zswap` and
`sysctl/vm`; Fedora kernel config for f44 (`CONFIG_ZSWAP=y`,
`CONFIG_ZSWAP_DEFAULT_ON` unset, `CONFIG_ZSWAP_SHRINKER_DEFAULT_ON=y`,
`CONFIG_CRYPTO_ZSTD=m`); Fedora change "SwapOnZRAM"; btrfs-progs
Swapfile documentation.

## Locale

`en_DK.UTF-8`: English messages, 24-hour clock, ISO 8601 dates
(2026-08-26), metric, A4, Monday first. `LANG` is set system-wide in
`/etc/locale.conf` and the GNOME region key (`org.gnome.system.locale
region`) is set so the session formats match without a trip through
Settings. `clock-format` is pinned to 24h since GNOME derives it from
the locale only on first login.

If dd/mm/yyyy matters more than ISO, `en_IE.UTF-8` is the closest glibc
locale (`%d/%m/%y`, 24-hour, no AM/PM); `en_GB` has the same date but
defines an AM/PM format so GNOME may pick 12h. Change `locale` in
`vars.yml`. Takes effect at next login.

## Btrfs compression: zstd:3

Fedora mounts `/` and `/home` with `compress=zstd:1`. This config raises
it to `zstd:3`, the btrfs default. Reasoning:

**How it works.** Compression is a mount option, applied to new writes
only; existing extents are untouched until rewritten. The option is
filesystem-wide, so remounting `/` also covers `/home`. Without
`compress-force`, btrfs tries the first 128 KiB of each file and gives
up on files that do not shrink, so already-compressed data (game assets,
media, archives, wheels) costs almost nothing at any level. Decompression
speed is the same at every zstd level; only writes pay for the level.

**Numbers.** From the btrfs maintainers' own benchmark for the fast-level
patch (Daniel Vacek, kernel 6.13, Jan 2025), compressed size relative to
original, level 1 vs 3: binaries 41% vs 39%, docs 39% vs 37%, enwik9 38%
vs 35%, Linux source 19% vs 18%. Wall time to copy the 1.4 GB source
tarball: 1.88 s vs 1.97 s, and identical after sync. Level 4 jumps to
2.17 s for 1 MB gained; the curve is steep from there. Level 3 is the
knee: 5-8% less space for about 5% more compression time. Nick Terrell's
original 2017 numbers show the same shape (ratio 2.57 vs 2.71 at 260 vs
174 MB/s per core, on a 2017 laptop core in a VM).

**Why Fedora picked 1.** The change proposal benchmarked with
`/dev/urandom` and `/dev/zero`. David Sterba (btrfs maintainer, April
2025) called that evaluation flawed and said he does not see zstd:1
clearly winning against zstd:3, with read and write runtimes roughly the
same.

**This machine.** Eight cores at 4+ GHz do in-kernel zstd:3 at a few
hundred MB/s per core, and btrfs compresses in parallel, so the ceiling
is far above anything a desktop writes sustained. Level 3 is seamless
here. What would not be seamless: recompressing existing data with
`btrfs filesystem defragment -r -czstd`, because defragmentation
unshares extents and undoes reflinks and dedup. That is deliberately not
done; the old data converts as it gets rewritten by updates.

Sources: btrfs docs `Compression`; Vacek, "btrfs: zstd: enable negative
compression levels mount option" (patch and thread, linux-btrfs, Jan-Feb
2025); Sterba, reply to "set default zstd compression level to 1 when
SSD detected" (April 2025); Terrell, "btrfs: Add zstd support" (2017);
Fedora change "BtrfsTransparentCompression".

## Deduplication: bees, and uv for venvs

Python venvs are full copies of every package. Two things stop that
from eating the disk:

- `uv` installs from one global cache and, with `link-mode = "clone"`
  in `~/.config/uv/uv.toml`, links packages into venvs as Btrfs
  reflinks. Every venv shares extents with the cache from the moment it
  is created. uv's Linux default is hardlinks, which share space too but
  make an edit inside one venv change the cached file; reflinks do not.
- `bees` deduplicates continuously at block level by following the
  filesystem's own change log, so it also catches pip-made venvs, git
  worktrees, container layers and whatever else repeats. It runs as
  `beesd@<uuid>.service` on the filesystem holding `/` and `/home`,
  with a 512 MiB mlocked hash table (bees docs: 128 MiB per TB of
  unique data, 2-4x that on a compressed filesystem) and four worker
  threads at idle I/O and nice 19. It skips nodatacow files, so the swap
  file and libvirt images are untouched. The first full scan takes
  hours; after that it keeps up incrementally. It runs at `--verbose 4`
  (warnings and errors); the default of 8 logs every crawl and dedupe
  and floods the journal. Levels are 0 (silent) to 8 (all), mapping to
  syslog priorities (bees docs, options.html).

`duperemove` was dropped as redundant. `compsize <path>` shows what
compression and sharing are actually saving.

## Ansible

- No inventory file; `ansible.cfg` silences the implicit-localhost warning.
- `community.general` comes from the Fedora package rather than Galaxy so a
  fresh install works offline from the distro mirror.
- Home files are copied as a tree from `files/home/`. Adding a file means
  dropping it in the right place; no task change needed.
- `ansible_facts['user_dir']` is the running user's home. Everything under
  `tasks/user.yml` runs without `become`.
- dconf values are GVariant strings, so quoting in `vars.yml` matters:
  `"'flat'"` is a string, `"true"` is a boolean.

## Machine-specific vs machine-independent split

Two mechanisms, chosen so that a second machine never requires
restructuring:

- `machine.yml` holds values sized to the hardware (swap, bees db) and
  hardware-only packages. It is loaded after `vars.yml`, so on a key
  collision the machine value wins. Ansible does not merge lists across
  vars files, so machine packages are separate lists
  (`packages_machine`, `packages_freeworld_machine`) that the install
  tasks concatenate. This avoids `hash_behaviour=merge`, which is
  global, deprecated in spirit and a well-known footgun.
- `tasks/machine.yml` holds hardware workarounds. Every block is gated
  on facts (`ansible_facts['board_name']` etc.), never on file layout,
  so running the playbook on the wrong machine is a no-op rather than
  a misconfiguration. It is imported first, so its `flush_handlers`
  only ever flushes its own notifications.

No inventory, no host_vars, no roles; that machinery pays off with a
fleet, not with one desktop and maybe a second machine one day.

## Suspend: Gigabyte B550 GPP0 wakeup bug

The B550I AORUS PRO AX (and most other Gigabyte B550/B650 boards)
ships with a firmware bug: the GPP0 PCIe bridge (to the NVMe) is left
enabled as an ACPI wakeup source. The result is that `systemctl
suspend` completes and the machine wakes up immediately.

The fix is to toggle GPP0 off in `/proc/acpi/wakeup` at every boot.
`/proc/acpi/wakeup` is not a normal file; every write toggles the
named device, so the service checks `grep "GPP0.*enabled"` first and
only writes when needed.

`fix-suspend.service` is a oneshot unit that runs at
`multi-user.target`, matching the pattern of `zswap.service`. The
install and enable tasks are gated on `ansible_facts['board_name']`
so they only apply to the B550I AORUS PRO AX; a different machine
gets no unit file and no service. To confirm the issue is GPP0, run:

    cat /proc/acpi/wakeup | grep GPP0

If it says `*enabled`, the bug is present. After the service runs it
should say `*disabled`.

Sources: ArchWiki "Wakeup triggers"; artemis.sh "Fix Linux
Suspend/Sleep in Gigabyte B550i Aorus Pro AX" (2023-04-09);
pliszko.com "Fixing instant wake from suspend on Gigabyte
motherboards" (2025-07-31).

## Linting

`make lint` runs yamllint, ansible-lint (production profile), a playbook
syntax check and shellcheck. `.yamllint` is set to 80 columns and the
octal/comment rules ansible-lint requires.
