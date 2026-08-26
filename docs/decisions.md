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

## Memory

32 GiB RAM, NVMe, fast CPU. Fedora's default is an 8 GiB zram device.
This config uses:

- zram: `ram / 2` (16 GiB), zstd. One device, no disk swap.
- sysctl: `vm.swappiness=180`, `vm.page-cluster=0`, watermark tuning.
  These are the kernel documentation values for swap on zram.
- zswap: left off. Fedora kernels do not enable it by default and it makes
  no sense in front of zram. No kernel argument is set, so no `grubby`
  task is needed.

Hibernation is not supported by this setup. Add a swap file if that ever
matters.

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

## Linting

`make lint` runs yamllint, ansible-lint (production profile), a playbook
syntax check and shellcheck. `.yamllint` is set to 80 columns and the
octal/comment rules ansible-lint requires.
