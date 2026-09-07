# Atelier — build/run entry points.
# See TECHNICAL_PLAN.md for the milestone the current code is at.

.DEFAULT_GOAL := build
CONFIG ?= debug
APP := .build/Atelier.app

.PHONY: build
build: ## Compile the Atelier executable
	swift build $(if $(filter release,$(CONFIG)),-c release,)

.PHONY: bundle
bundle: build ## Assemble Atelier.app from the build product
	./Scripts/bundle.sh $(CONFIG)

.PHONY: run
run: bundle ## Build, bundle, and launch the app
	open $(APP)

.PHONY: install
install: bundle ## Symlink Atelier.app into /Applications (Spotlight / Dock launch)
	ln -sfn $(CURDIR)/$(APP) /Applications/Atelier.app
	@echo "linked: /Applications/Atelier.app -> $(APP)"

.PHONY: install-cli
install-cli: bundle ## Symlink the atelier CLI into ~/.local/bin
	mkdir -p $(HOME)/.local/bin
	ln -sf $(CURDIR)/$(APP)/Contents/MacOS/atelier-cli $(HOME)/.local/bin/atelier
	@echo "linked: ~/.local/bin/atelier"

.PHONY: clean
clean: ## Remove build artifacts
	swift package clean
	rm -rf $(APP)

.PHONY: help
help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'
