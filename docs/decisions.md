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
- Flatpak is used for end-user GUI apps that are large, third-party or
  independent of the GNOME release: Firefox, Thunderbird, LibreOffice,
  Boxes, Media Writer, Steam and the chat clients. GNOME's own small
  apps (Calculator, Clocks, Papers, Loupe, Text Editor, ...) stay as
  the Workstation RPMs: they are a few MB each, share the GTK stack the
  shell already needs, and the flatpak versions lose host hooks such
  as PDF thumbnails in Nautilus and `gnome-text-editor file` from a
  terminal. Moving them would add entries without removing anything
  worth removing.
- LibreOffice as `org.libreoffice.LibreOffice` is the one large win:
  `libreoffice-core` and its dependents (`unoconv`, the `libreoffice-*`
  subpackages) and the fonts and filter libraries only they need leave
  the host. Anything that needs headless conversion on the host is
  `flatpak run --command=soffice org.libreoffice.LibreOffice
  --convert-to ...`.
- Virtualisation is GNOME Boxes as a flatpak. It bundles its own qemu
  and a session libvirt, so `libvirt`, `virt-manager` and the `virt*d`
  sockets are gone from the host (2026-09). `qemu-kvm` stays for
  running qemu by hand; its `80-kvm.rules` also keeps `/dev/kvm` at
  mode 0666, which is all the flatpak needs. VM images live under
  `~/.var/app/org.gnome.Boxes`, so they are excluded from backups like
  all flatpak data; they are also plain CoW files, so a VM that writes
  heavily will fragment. If that is ever felt, `chattr +C` the images
  directory before creating VMs.
  Images from the old libvirt setup are left in place under
  `/var/lib/libvirt/images`; delete or import them by hand.
- Package removal: `clean_requirements_on_remove=True` is dnf5's
  default and is stated in `files/etc/dnf/libdnf5.conf.d/local.conf`.
  With it, `packages_absent` also drops the dependencies pulled in for
  those packages that nothing else needs. It only touches packages
  whose install reason is "Dependency" or "Weak dependency", never
  something installed by name or by a group. Leftovers from removals
  done by hand before this config are cleaned once with
  `dnf autoremove`; not automated, because autoremove acts on the
  whole system and would silently take a library someone is using.
- Thunderbird is the Fedora flatpak `net.thunderbird.Thunderbird`
  (remote `fedora`, branch `stable`), which follows Fedora's RPM and so
  the release (monthly) channel. Flathub's `org.mozilla.thunderbird` /
  `org.mozilla.thunderbird_esr` split (2026) was considered and skipped;
  the Fedora build updates with the distro and needs no extra remote.
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

## Automatic updates: download only

`dnf5-plugin-automatic` runs from `dnf5-automatic.timer` and is
configured in `/etc/dnf/automatic.conf` (overrides on top of
`/usr/share/dnf5/dnf5-plugins/automatic.conf`). This config sets
`download_updates = yes`, `apply_updates = no`, `reboot = never`.

**Why download but not install.** With `apply_updates = no` the RPMs
stay in `/var/cache/libdnf5` until the next successful transaction, so a
later `dnf upgrade` is a local, near-instant operation and the slow part
has already happened in the background. Nothing is swapped underneath a
running session: replacing files under a live GNOME or browser is what
produces the classic "restart required" breakage, and unattended kernel
or systemd upgrades on a desktop invite a reboot the owner did not ask
for. Installing stays a deliberate act. `reboot = never` is the default
and is set explicitly so it survives a change of upstream defaults.

**Why the timer is overridden.** The stock unit is
`OnCalendar=*-*-* 6:00` with an hour of randomized delay. This machine
is powered off at night, so that time never comes around and the job
would never run. The drop-in
`files/etc/systemd/system/dnf5-automatic.timer.d/desktop.conf` clears
`OnCalendar`, asks for `daily`, and sets `Persistent=true`. systemd then
stores the last run in `/var/lib/systemd/timers` and runs the missed job
after boot instead of waiting for the next calendar match.
`RandomizedDelaySec=30m` applies to catch-up runs too, which keeps the
download from starting on top of login. Net effect: one download run per
day, about half an hour into the first session of that day.

`random_sleep` stays 0 because the systemd delay already covers it, and
`network_online_timeout` is raised from 60 to 300 s because the run
usually starts while NetworkManager is still settling after boot.

Not done: GNOME Software also refreshes and downloads in the background,
into PackageKit's cache rather than dnf's, so the same payload can be
fetched twice. Turning that off is one dconf key,
`/org/gnome/software/download-updates`, but it also stops background
fetching of flatpak updates. Left at the default until the duplication
is actually observed.

Sources: dnf5 `automatic.8` (config file format, `[commands]` and
`[emitters]` sections); `systemd.timer(5)` on `Persistent` and
`RandomizedDelaySec`.

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

**Availability.** `glibc-langpack-en` ships `en_DK` prebuilt, along with
the other 18 English territories, so nothing has to be generated.
Verified on the machine: `locale -a` lists `en_DK`, `en_DK.iso88591` and
`en_DK.utf8`. Fedora Workstation does not install `glibc-all-langpacks`,
so a locale outside the installed langpacks would not exist at all and
`LANG` would fall back to C.UTF-8; that would need `glibc-locale-source`
and a `localedef` run, which is deliberately not in the playbook while
the locale stays an English one.

Note that `locale -a` prints the normalized name. Grepping for the
configured string finds nothing even when everything is correct:

    locale -a | grep -i en_dk        # en_DK, en_DK.iso88591, en_DK.utf8
    locale -a | grep en_DK.UTF-8     # nothing, always

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
  file is untouched. The first full scan takes
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

## Iteration time

A full run is dominated by things that are no-ops once the machine is
configured. What was done about it, cheapest first:

- **Scope the run.** The play is tagged `machine`, `system`, `desktop`,
  `user`, and the Makefile takes a `TAGS` variable, so editing a dconf
  key means `make apply TAGS=desktop` instead of a full pass. This is
  the largest win by far and costs nothing.
- **Cache facts.** `gathering = smart` with the `jsonfile` cache in
  `~/.cache/ansible/facts` and a one-hour timeout. The second run in a
  session has no "Gathering Facts" task at all. One hour is chosen so
  the cache cannot go stale across days without anyone noticing; delete
  the directory after changing disks or hardware.
- **Gather less.** `gather_subset: [min, hardware]`. The playbook reads
  `distribution_major_version` and the user facts (from `min`) and
  `mounts` and `board_name` (from `hardware`). Network, virtual and the
  ssh key subsets are not read by anything.
- **Do not start dnf when there is nothing to do.** Enabling RPM Fusion
  was two dnf transactions on every run, each of which loads the repo
  metadata before concluding the release package is already installed.
  A `stat` on `/etc/yum.repos.d/rpmfusion-{free,nonfree}.repo` decides
  whether to run them at all.
- **Measure.** `ansible.posix.profile_tasks` is enabled, so every run
  ends with its ten slowest tasks. The remaining candidates are the
  three dnf tasks (install, freeworld, remove), which each pay for a
  metadata load, and the flatpak tasks. Both were left alone: the dnf
  split exists because only the freeworld list may use `allowerasing`,
  and neither has been shown to be the bottleneck yet. Look at the
  numbers before cutting further.

Not done, deliberately: mitogen (extra tooling, out of scope),
`install_weak_deps = False` (changes what gets installed, not just how
fast), and merging the dnf tasks (see above).

## Linting

`make lint` runs yamllint, ansible-lint (production profile), a playbook
syntax check and shellcheck. `.yamllint` is set to 80 columns and the
octal/comment rules ansible-lint requires. `make lint TAGS=...` is not
a thing; lint always covers the whole tree.
