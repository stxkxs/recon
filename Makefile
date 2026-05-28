# Makefile for recond - Infrastructure reconnaissance toolkit

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Project paths
PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
LIBDIR := $(PREFIX)/lib/recond
ETCDIR := $(PREFIX)/etc/recond

# Project files
BIN := bin/recond
LIBS := $(wildcard lib/core/*.sh) $(wildcard lib/modules/*.sh) $(wildcard lib/batch/*.sh)
ETC := etc/recond.yaml.example etc/subdomains.txt

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

.PHONY: help
help: ## Show this help message
	@echo -e "$(BLUE)recond$(NC) - Infrastructure Reconnaissance Toolkit"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2}'

.PHONY: install
install: ## Install recond to system (PREFIX=/usr/local)
	@echo -e "$(BLUE)Installing recond...$(NC)"
	@mkdir -p $(BINDIR)
	@mkdir -p $(LIBDIR)/core
	@mkdir -p $(LIBDIR)/modules
	@mkdir -p $(LIBDIR)/batch
	@mkdir -p $(ETCDIR)
	@# Install main binary
	@install -m 755 bin/recond $(BINDIR)/recond
	@# Update library path in binary
	@sed -i.bak 's|PROJECT_ROOT="$$(cd "$${SCRIPT_DIR}/.." && pwd)"|PROJECT_ROOT="$(PREFIX)/lib/recond"|' $(BINDIR)/recond
	@sed -i.bak 's|$${PROJECT_ROOT}/lib|$(LIBDIR)|g' $(BINDIR)/recond
	@rm -f $(BINDIR)/recond.bak
	@# Install libraries
	@install -m 644 lib/core/*.sh $(LIBDIR)/core/
	@install -m 644 lib/modules/*.sh $(LIBDIR)/modules/
	@install -m 644 lib/batch/*.sh $(LIBDIR)/batch/
	@# Install config files
	@install -m 644 etc/recond.yaml.example $(ETCDIR)/
	@install -m 644 etc/subdomains.txt $(ETCDIR)/
	@echo -e "$(GREEN)Installation complete!$(NC)"
	@echo "  Binary: $(BINDIR)/recond"
	@echo "  Libraries: $(LIBDIR)/"
	@echo "  Config: $(ETCDIR)/"

.PHONY: uninstall
uninstall: ## Remove recond from system
	@echo -e "$(BLUE)Uninstalling recond...$(NC)"
	@rm -f $(BINDIR)/recond
	@rm -rf $(LIBDIR)
	@rm -rf $(ETCDIR)
	@echo -e "$(GREEN)Uninstallation complete!$(NC)"

.PHONY: install-local
install-local: ## Install to ~/.local (user installation)
	@$(MAKE) install PREFIX=$(HOME)/.local

.PHONY: uninstall-local
uninstall-local: ## Remove from ~/.local
	@$(MAKE) uninstall PREFIX=$(HOME)/.local

.PHONY: test
test: ## Run all tests
	@echo -e "$(BLUE)Running tests...$(NC)"
	@if [ -d tests ]; then \
		for test in tests/test_*.sh; do \
			if [ -f "$$test" ]; then \
				echo -e "\n$(YELLOW)Running $$test$(NC)"; \
				bash "$$test" || exit 1; \
			fi \
		done; \
		echo -e "\n$(GREEN)All tests passed!$(NC)"; \
	else \
		echo -e "$(YELLOW)No tests found$(NC)"; \
	fi

.PHONY: test-quick
test-quick: ## Run quick unit tests only
	@echo -e "$(BLUE)Running quick tests...$(NC)"
	@if [ -f tests/test_input.sh ]; then bash tests/test_input.sh; fi
	@if [ -f tests/test_output.sh ]; then bash tests/test_output.sh; fi

.PHONY: lint
lint: ## Run shellcheck on all scripts
	@echo -e "$(BLUE)Running shellcheck...$(NC)"
	@if command -v shellcheck &>/dev/null; then \
		shellcheck -x bin/recond $(LIBS) 2>&1 || true; \
		echo -e "$(GREEN)Lint complete$(NC)"; \
	else \
		echo -e "$(YELLOW)shellcheck not installed, skipping$(NC)"; \
	fi

.PHONY: check-deps
check-deps: ## Check for required dependencies
	@echo -e "$(BLUE)Checking dependencies...$(NC)"
	@missing=""; \
	for cmd in bash dig curl openssl whois jq; do \
		if ! command -v $$cmd &>/dev/null; then \
			missing="$$missing $$cmd"; \
		else \
			echo -e "  $(GREEN)✓$(NC) $$cmd"; \
		fi \
	done; \
	for cmd in yq timeout flock gum nc; do \
		if command -v $$cmd &>/dev/null; then \
			echo -e "  $(GREEN)✓$(NC) $$cmd (optional)"; \
		else \
			echo -e "  $(YELLOW)○$(NC) $$cmd (optional)"; \
		fi \
	done; \
	if [ -n "$$missing" ]; then \
		echo -e "\n$(YELLOW)Missing required:$$missing$(NC)"; \
		exit 1; \
	else \
		echo -e "\n$(GREEN)All required dependencies installed$(NC)"; \
	fi

.PHONY: docker-build
docker-build: ## Build Docker image
	@echo -e "$(BLUE)Building Docker image...$(NC)"
	@docker build -t recond:latest -f docker/Dockerfile .
	@echo -e "$(GREEN)Docker image built: recond:latest$(NC)"

.PHONY: docker-run
docker-run: ## Run recond in Docker (usage: make docker-run ARGS="example.com")
	@docker run --rm -it recond:latest $(ARGS)

.PHONY: clean
clean: ## Clean temporary files
	@echo -e "$(BLUE)Cleaning...$(NC)"
	@rm -rf results/
	@rm -f *.json
	@echo -e "$(GREEN)Clean complete$(NC)"

.PHONY: demo
demo: ## Run a demo scan against example.com
	@echo -e "$(BLUE)Running demo scan...$(NC)"
	@./bin/recond --modules dns,http example.com

.PHONY: demo-json
demo-json: ## Run a demo scan with JSON output
	@echo -e "$(BLUE)Running demo scan (JSON)...$(NC)"
	@./bin/recond --json --modules dns example.com | jq .

.PHONY: version
version: ## Show version
	@./bin/recond --version

.PHONY: release
release: lint test ## Prepare for release (lint + test)
	@echo -e "$(GREEN)Release checks passed!$(NC)"
