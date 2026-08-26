# Handover

State of the project as of 2026-08-26, for whoever picks it up next
(including a future AI session). Read `README.md` first; this file is the
context that does not belong there.

## What this is

An Ansible playbook, run locally, that takes a fresh Fedora Workstation
to a usable state and can be re-run at any time to converge it. One
machine: Ryzen 7 5700X3D, RX 6800, 32 GiB, one 960 GB NVMe, Btrfs,
Fedora 44, GNOME 50 on Wayland. Owner's GitHub is `olemorud`; the repo
is `github.com/olemorud/fedora-config`.

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
  changes: packages, packages to remove, flatpaks, services, groups,
  dconf keys, `locale`, `swap_size`.
- `tasks/system.yml` runs with `become`; `tasks/user.yml` never does.
- `files/etc/` mirrors `/etc`; `files/home/` is copied as a tree into
  `$HOME` by a single task, so adding a dotfile is a file drop.
- `docs/decisions.md` explains the non-obvious choices with sources.
  `docs/dotfiles.md` lists every fix made when vendoring the dotfiles.

## Decisions already made (do not relitigate without reading decisions.md)

- zswap in front of a 16 GiB Btrfs swap file, zram removed. Researched
  properly; the owner was sceptical of the first zram-only version and
  was right.
- zswap is enabled by `zswap.service`, not a kernel argument, because
  zstd is a module in the Fedora kernel.
- Locale `en_DK.UTF-8` (24 h, ISO dates). `en_IE` noted as the
  dd/mm alternative.
- Flatpak for GUI apps; virt-manager as RPM with modular libvirt
  sockets.
- `vim-X11` for `vimx` (+clipboard); `vim` is aliased to it in zsh.
- No vim plugins at all, by request.
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

## Open items

1. Steam flatpak still reported missing uinput permissions after the
   first fix. The current fix (`cbaf5f1`) checks
   `udevadm info /dev/uinput` for the `uaccess` tag and triggers only
   when missing. The owner has not yet confirmed whether this resolved
   it. If not, ask for the output of the four commands listed in the
   chat (rpm -q, grep uinput on the rules file, udevadm info TAGS,
   getfacl) and the `loginctl` seat.
2. `make check` on a fresh machine fails at "Enable services" because
   check mode does not create the unit files first. Known, accepted;
   could be softened with `ignore_errors: "{{ ansible_check_mode }}"`.
3. First run after the zswap change needs a reboot to drop zram fully.
   README says so.
4. The disk is assumed unencrypted or the owner has not said. zswap
   writes cold pages to the swap file; if that matters, LUKS or an
   encrypted swap via `/etc/crypttab` is the next step.
5. Hibernation is unsupported by design.

## How to make a change

```
edit vars.yml or a task file
make lint
make check          # dry run with diff, expect the known failure above
make apply
git commit
```

Then tar it up including `.git` and hand it back.
