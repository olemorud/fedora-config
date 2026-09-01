# Handover

State of the project as of 2026-09-01, for whoever picks it up next
(including a future AI session). Read `README.md` first; this file is the
context that does not belong there.

## What this is

An Ansible playbook, run locally, that takes a fresh Fedora Workstation
to a usable state and can be re-run at any time to converge it. One
machine: Ryzen 7 5700X3D, RX 6800, 32 GiB, one 960 GB NVMe, Btrfs,
Fedora 44, GNOME 50 on Wayland. Owner's GitHub is `olemorud`; the repo
is `github.com/olemorud/fedora-config`.

It is a desktop, not a server: powered off at night, booted when it is
used. Anything scheduled has to catch up after boot rather than fire at
a fixed hour, and nothing may reboot the machine on its own.

## Conventions the owner cares about

- Lean. No roles, no inventory, one vars file, plain task files. Do not
  add structure until a file is hard to read.
- Concise. README and commit messages short. Verbose AI-style writing
  goes in `docs/` only. No em-dashes, 80-column text and code.
- No sycophancy in replies.
- Every task idempotent; `make lint` must pass before commit.
- Commits are authored as the owner (name and email in
  `files/home/.gitconfig`), which is intentional.
- Working exchange format is a `.tar.gz` of the repo including `.git`.
  Always build on the copy the owner uploads, not on an older one;
  history has been rewritten once already and hashes diverged.

## Layout, beyond the README

- `vars.yml` is the only file that should need editing for routine
  changes: packages, packages to remove, flatpaks, services, dconf
  keys, `locale`. `machine.yml` holds hardware-sized values
  (`swap_size`, `bees_db_size`) and hardware-only package lists;
  `tasks/machine.yml` holds hardware workarounds, gated on facts.
- `tasks/system.yml` runs with `become`; `tasks/user.yml` never does.
- `files/etc/` mirrors `/etc`; `files/home/` is copied as a tree into
  `$HOME` by a single task, so adding a dotfile is a file drop.
- `docs/decisions.md` explains the non-obvious choices with sources.
  `docs/dotfiles.md` lists every fix made when vendoring the dotfiles.

## Decisions already made (do not relitigate without reading decisions.md)

- zswap in front of a 16 GiB Btrfs swap file, zram removed. Researched
  properly; the owner was sceptical of the first zram-only version and
  was right.
- Btrfs compression zstd:3 (researched, seamless on this hardware),
  bees for dedup, uv with reflinks for Python venvs. No recursive
  defrag ever: it unshares extents.
- zswap is enabled by `zswap.service`, not a kernel argument, because
  zstd is a module in the Fedora kernel.
- Locale `en_DK.UTF-8` (24 h, ISO dates). `en_IE` noted as the
  dd/mm alternative. Confirmed present on the machine; it comes prebuilt
  in `glibc-langpack-en`, so there is no locale generation step. `locale
  -a` prints `en_DK.utf8`, so grepping for `en_DK.UTF-8` finds nothing
  even when all is well.
- Flatpak for large or third-party GUI apps; GNOME's small core apps
  stay RPM on purpose (see decisions.md). LibreOffice and Media Writer
  moved to flatpak 2026-09.
- Virtualisation is the Boxes flatpak plus `qemu-kvm` on the host for
  manual use. libvirt and virt-manager were removed at the owner's
  request (2026-09); do not bring them back.
- The remove task carries `allowerasing: true` and `autoremove: true`;
  the dnf5 module needs both to behave like `dnf remove`. See
  decisions.md before touching either.
- `vim-X11` for `vimx` (+clipboard); `vim` is aliased to it in zsh.
- No vim plugins at all, by request.
- Updates are downloaded automatically and never installed:
  `dnf5-plugin-automatic` with `apply_updates = no`, `reboot = never`.
  The timer drop-in replaces the stock 06:00 schedule with `daily` plus
  `Persistent=true`, so the run happens on the first boot of the day.
- Suspend fix: `fix-suspend.service` disables GPP0 wakeup at boot
  (Gigabyte B550 ACPI firmware bug), in `tasks/machine.yml`.
- Machine-specific config split into `machine.yml` (vars) and
  `tasks/machine.yml` (fact-gated workarounds); see decisions.md.
- Iteration time: tag-scoped runs (`make apply TAGS=desktop`), an hour
  of fact caching, a trimmed `gather_subset`, and a stat guard so RPM
  Fusion does not start dnf for nothing. `profile_tasks` prints the ten
  slowest tasks after every run; tune from those numbers, not by guess.
  See decisions.md for what was deliberately left alone.
- Removed from scope by the owner: chezmoi, toolbx/distrobox, any
  dotfile manager.

## What has been verified and what has not

Verified in a container:

- `make lint` (yamllint, ansible-lint production profile, syntax check,
  shellcheck) passes on every commit.
- `tasks/user.yml` ran for real against a scratch home and was
  idempotent on the second run.
- zsh files pass `zsh -n` and load interactively; `.vimrc` loads with
  no messages and the colorscheme resolves.
- Swap and unit tasks render in `--check` mode up to the point where
  the container lacks systemd.
- `bootstrap.sh` works both piped and from a checkout (with `dnf` and
  `ansible-playbook` stubbed).

Not verified, because it needs the real machine:

- Everything under `become` on Fedora: dnf5 module, RPM Fusion install
  from URL, `allowerasing` replacing `ffmpeg-free` and `mesa-va-drivers`,
  removal of `zram-generator-defaults` (nothing is known to require it,
  but dnf will say so if something does).
- `btrfs filesystem mkswapfile` and the swap unit on the real layout.
- The dconf task needs a session bus; run the playbook from a terminal
  inside GNOME, not a tty.
- The udev trigger for `/dev/uinput` (see below).
- bees: config rendering was checked; the service itself, the initial
  scan and its RAM/CPU footprint have not been observed.
- The fstab edit and remount for zstd:3 (regexp tested on a Fedora-style
  fstab, idempotent on the second pass).
- `fix-suspend.service`: confirm GPP0 is the wakeup source on this
  board and that suspend stays asleep after the service runs.
- The dnf5-automatic timer. Check the schedule took with
  `systemctl show dnf5-automatic.timer -p Persistent -p TimersCalendar`
  and, after a day or two, `journalctl -u dnf5-automatic.service`.
  `dnf5 automatic --no-installupdates` runs it by hand.
- The RPM Fusion stat guard, on a machine that does not have the repos
  yet. It has only been exercised in the already-installed direction.
- The 2026-09 removals (`libreoffice-core`, `gnome-boxes`, `libvirt`,
  `virt-manager`, `mediawriter`). Expect a transaction of
  several hundred packages; read the `make check` diff first. The
  Boxes flatpak has not been started on this machine; if it cannot
  create a VM, check `ls -l /dev/kvm` (expect `crw-rw-rw-`).

## Open items

1. Steam flatpak still reported missing uinput permissions after the
   first fix. The current fix (`cbaf5f1`) checks
   `udevadm info /dev/uinput` for the `uaccess` tag and triggers only
   when missing. The owner has not yet confirmed whether this resolved
   it. If not, ask for the output of the four commands listed in the
   chat (rpm -q, grep uinput on the rules file, udevadm info TAGS,
   getfacl) and the `loginctl` seat.
2. Resolved. `make check` used to fail at "Enable services" because
   check mode installs nothing, so the units do not exist yet. The
   enable tasks now carry the same guard as the suspend fix in
   `tasks/machine.yml`: skip when running in check mode and the task
   that would have created the unit reported a change.
3. First run after the zswap change needs a reboot to drop zram fully.
   README says so.
4. The disk is assumed unencrypted or the owner has not said. zswap
   writes cold pages to the swap file; if that matters, LUKS or an
   encrypted swap via `/etc/crypttab` is the next step.
5. Hibernation is unsupported by design.
6. GNOME Software downloads updates in the background as well, into
   PackageKit's cache rather than dnf's, so the same payload can be
   fetched twice. `/org/gnome/software/download-updates` set to `false`
   stops it, at the cost of background flatpak updates. Left at the
   default until the duplication is actually seen.
7. Downloaded packages sit in `/var/cache/libdnf5` until the next
   successful transaction. Harmless on a 960 GB disk, but it is the
   reason not to raise the timer frequency.

## How to make a change

```
edit vars.yml or a task file
make lint
make check TAGS=system   # dry run with diff, scoped while iterating
make apply TAGS=system
make apply               # full pass before committing
git commit
```

Then tar it up including `.git` and hand it back.
