.DEFAULT_GOAL := help

define PRINT_HELP_PYSCRIPT
import re, sys

for line in sys.stdin:
    match = re.match(r'^([a-zA-Z_-]+):.*?## (.*)$$', line)
    if match:
        target, help = match.groups()
        print("%-40s %s" % (target, help))
endef
export PRINT_HELP_PYSCRIPT
TEST_REGION="us-west-2"
TEST_ROLE="arn:aws:iam::303467602807:role/jumphost-tester"

help: install-hooks
	@python -c "$$PRINT_HELP_PYSCRIPT" < Makefile

.PHONY: install-hooks
install-hooks:  ## Install repo hooks
	@echo "Checking and installing hooks"
	@test -d .git/hooks || (echo "Looks like you are not in a Git repo" ; exit 1)
	@test -L .git/hooks/pre-commit || ln -fs ../../hooks/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit

.PHONY: lint
lint:  ## Run code style checks
	terraform fmt --check -recursive

.PHONY: test
test:  ## Run tests on the module
	pytest -xvvs tests/test_module.py

.PHONY: test-keep
test-keep:  ## Run a test and keep resources
	pytest -xvvs \
		--aws-region=${TEST_REGION} \
		--test-role-arn=${TEST_ROLE} \
		--keep-after \
		-k subnet_private_ids \
		tests/test_module.py

.PHONY: test-clean
test-clean:  ## Run a test and destroy resources
	pytest -xvvs \
		--aws-region=${TEST_REGION} \
		--test-role-arn=${TEST_ROLE} \
		-k subnet_private_ids \
		tests/test_module.py

.PHONY: test-migration
test-migration:  ## Run a migration test
	pytest -xvvs \
		--aws-region=${TEST_REGION} \
		--test-role-arn=${TEST_ROLE} \
		--keep-after \
		tests/test_migration.py

.PHONY: test-migration-clean
test-migration-clean:  ## Remove the migration test resources
	@if [ -d test_data/jumphost-2.9 ]; then \
		cd test_data/jumphost-2.9 && terraform destroy; \
	else \
		echo "Directory test_data/jumphost-2.9 does not exist"; \
	fi
	@if [ -d "$$(python -c 'import pytest_infrahouse; print(pytest_infrahouse.__path__[0])')/data/service-network/" ]; then \
		cd "$$(python -c 'import pytest_infrahouse; print(pytest_infrahouse.__path__[0])')/data/service-network/" && terraform destroy; \
	else \
		echo "Directory for service-network does not exist"; \
	fi
.PHONY: bootstrap
bootstrap: ## bootstrap the development environment
	pip install -U "pip ~= 23.1"
	pip install -U "setuptools ~= 68.0"
	pip install -r requirements.txt

.PHONY: clean
clean: ## clean the repo from cruft
	rm -rf .pytest_cache
	find . -name '.terraform' -exec rm -fr {} +

.PHONY: fmt
fmt: format

.PHONY: format
format:  ## Use terraform fmt to format all files in the repo
	@echo "Formatting terraform files"
	terraform fmt -recursive
	black tests

define BROWSER_PYSCRIPT
import os, webbrowser, sys

from urllib.request import pathname2url

webbrowser.open("file://" + pathname2url(os.path.abspath(sys.argv[1])))
endef
export BROWSER_PYSCRIPT

BROWSER := python -c "$$BROWSER_PYSCRIPT"

.PHONY: docs
docs: ## generate Sphinx HTML documentation, including API docs
	$(MAKE) -C docs clean
	$(MAKE) -C docs html
	$(BROWSER) docs/_build/html/index.html
