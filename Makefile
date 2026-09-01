.PHONY: apply check lint

# Scope a run while iterating: make apply TAGS=desktop
# Tags are machine, system, desktop, user; see playbook.yml.
TAGS ?= all

apply:
	ansible-playbook -K --tags $(TAGS) playbook.yml

check:
	ansible-playbook -K --check --diff --tags $(TAGS) playbook.yml

lint:
	yamllint .
	ansible-lint
	ansible-playbook --syntax-check playbook.yml
	shellcheck bootstrap.sh
