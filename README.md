# Fedora Workstation Configuration

## Purpose

Keep the configuration of this Fedora Workstation reproducible, idempotent
and maintainable, in a pragmatic manner.

## Scope

In scope:

- System packages (dnf, COPR, RPM Fusion)
- GUI applications (Flatpak)
- System configuration (`/etc`, systemd units, firewalld, dnf settings)
- System tuning (sysctl, kernel modules, udev rules, boot parameters)
- Selected desktop settings (dconf)
- User-level files that matter (shell config, git config)

Out of scope:

- Dotfile managers, container toolboxes and other tooling
- Byte-identical machines
- Secrets (handled manually, referenced by path only)

## Tools

- **Ansible** (`ansible-core`), run locally against `localhost`
- **Flatpak** with Flathub, managed through the Ansible `flatpak` module
- **Git** for the repository

## Principles

- Everything is a task in the playbook; nothing is done by hand twice.
- Every task must be safe to run again. Prefer modules over `command`.
- Target is "fresh install to usable in under 30 minutes", not perfection.
- Pin nothing unless it actually breaks.
- Keep the tree flat. Plain task files, no roles, one vars file.
- Adapt to each Fedora release; expect small fixes twice a year.

## Layout

```
.
|-- bootstrap.sh     # installs git + ansible, clones, runs playbook
|-- playbook.yml     # includes the task files below, in order
|-- vars.yml         # packages, copr repos, flatpaks, dconf settings
|-- tasks/
|   |-- system.yml   # repos, packages, services, /etc
|   |-- desktop.yml  # flatpaks, dconf
|   `-- user.yml     # shell, git, user files
`-- files/           # config files copied verbatim
```

No inventory file; the playbook targets `localhost` with a local connection.
Split a task file only when it becomes hard to read.

## Usage

```
# First time on a fresh install
curl -fsSL <repo-raw-url>/bootstrap.sh | bash

# Afterwards
ansible-playbook -K playbook.yml
```

## Maintenance

- Run the playbook after every change and commit only when it passes.
- Run it once after each Fedora upgrade and fix what broke.
- Review the package lists occasionally and remove what is unused.
