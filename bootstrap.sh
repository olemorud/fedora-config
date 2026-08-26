#!/bin/bash
# Fresh install to configured machine. Safe to run again.
set -euo pipefail

REPO="${REPO:-https://github.com/olemorud/fedora-config.git}"
DIR="${DIR:-$HOME/fedora-config}"

sudo dnf install -y git ansible-core ansible-collection-community-general

if [ ! -d "$DIR/.git" ]; then
    git clone "$REPO" "$DIR"
fi

cd "$DIR"
ansible-playbook -K playbook.yml
