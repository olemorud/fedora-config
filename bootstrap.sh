#!/bin/bash
# Fresh install to configured machine. Safe to run again.
#
# Two ways to run it:
#   curl -fsSL <repo-raw-url>/bootstrap.sh | bash   # clones, then runs
#   ./bootstrap.sh                                  # from a checkout
set -euo pipefail

REPO="${REPO:-https://github.com/olemorud/fedora-config.git}"

# Run from the checkout this script lives in, if it is one.
here="$(dirname "${BASH_SOURCE[0]:-}")"
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -d "$here/.git" ]; then
    DIR="$(cd "$here" && pwd)"
else
    DIR="${DIR:-$HOME/fedora-config}"
fi

echo "==> Installing git and ansible"
sudo dnf install -y git ansible-core ansible-collection-community-general

if [ ! -d "$DIR/.git" ]; then
    echo "==> Cloning $REPO to $DIR"
    git clone "$REPO" "$DIR"
fi

echo "==> Running playbook in $DIR"
cd "$DIR"
ansible-playbook -K playbook.yml
