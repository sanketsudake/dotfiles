SHELL := /bin/bash

STOW := stow
# --no-folding is a security invariant: ~/.config/<tool> must stay a real
# directory so tools that write credentials beside their config (gh's
# hosts.yml) never write into this repo. --dotfiles needs stow >= 2.4.0.
STOW_FLAGS := --dir=$(CURDIR)/packages --target=$(HOME) --dotfiles --no-folding --verbose=1
PACKAGES := zsh git atuin btop gh

BREWFILE := $(CURDIR)/Brewfile
HARNESS_DIR ?= $(abspath $(CURDIR)/../harness-configs)
HARNESS_REPO := git@github.com:sanketsudake/harness-configs.git

.PHONY: install uninstall doctor \
	brew-install brew-check brew-dump \
	stow-link stow-unlink stow-adopt \
	harness-clone harness-install \
	macos-apply

install: brew-install stow-link harness-install

uninstall: stow-unlink

brew-install:
	brew bundle --file=$(BREWFILE)

brew-check:
	brew bundle check --file=$(BREWFILE)

# Regenerate Brewfile.dump (gitignored) to diff against the curated Brewfile;
# never overwrites Brewfile itself.
brew-dump:
	brew bundle dump --file=$(CURDIR)/Brewfile.dump --describe --force
	@echo "wrote Brewfile.dump — diff against Brewfile to re-curate"

stow-link:
	$(STOW) $(STOW_FLAGS) --restow $(PACKAGES)

stow-unlink:
	$(STOW) $(STOW_FLAGS) --delete $(PACKAGES)

# Absorb pre-existing real files at target paths into the repo working tree.
stow-adopt:
	$(STOW) $(STOW_FLAGS) --adopt $(PACKAGES)
	@echo ""
	@echo "== adopted; repo state now =="
	@git status --short
	@echo ""
	@echo "!! REVIEW 'git diff' BEFORE COMMITTING — adopt replaces repo files with the live ones !!"

harness-clone:
	@test -d $(HARNESS_DIR) || git clone $(HARNESS_REPO) $(HARNESS_DIR)

harness-install: harness-clone
	$(MAKE) -C $(HARNESS_DIR) install

macos-apply:
	bash $(CURDIR)/macos/defaults.sh

doctor:
	bash $(CURDIR)/scripts/doctor.sh
