.PHONY: apply check lint

apply:
	ansible-playbook -K playbook.yml

check:
	ansible-playbook -K --check --diff playbook.yml

lint:
	yamllint .
	ansible-lint
	ansible-playbook --syntax-check playbook.yml
	shellcheck bootstrap.sh
