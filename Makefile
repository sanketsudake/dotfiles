SHELL := /bin/bash

STOW := stow
# Flags are a security invariant, not a style choice — see "The stow model" in README.md.
STOW_FLAGS := --dir=$(CURDIR)/packages --target=$(HOME) --dotfiles --no-folding --verbose=1
PACKAGES := zsh git atuin btop gh

BREWFILE := $(CURDIR)/Brewfile
HARNESS_DIR ?= $(abspath $(CURDIR)/../harness-configs)
HARNESS_REPO := git@github.com:sanketsudake/harness-configs.git
HARNESS_REPO_HTTPS := https://github.com/sanketsudake/harness-configs.git

MANIFESTS := $(CURDIR)/manifests

.PHONY: install uninstall doctor \
	brew-install brew-check brew-dump cask-adopt \
	go-install npm-install pipx-install tools-install \
	stow-link stow-unlink stow-adopt \
	harness-clone harness-install \
	macos-apply drift raycast-export

install: brew-install stow-link tools-install harness-install

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

# Take over apps that were installed outside brew (pkg-based casks prompt for sudo).
cask-adopt:
	brew install --cask --adopt 1password claude devin-desktop google-chrome \
		openvpn-connect tailscale-app wispr-flow

tools-install: go-install npm-install pipx-install

# Installs each module from manifests/go-tools.txt; lines without @version get @latest.
go-install:
	@command -v go >/dev/null || { echo "go not found — run: make brew-install"; exit 1; }
	@grep -vE '^[[:space:]]*#|^[[:space:]]*$$' $(MANIFESTS)/go-tools.txt | while read -r mod; do \
		case "$$mod" in *@*) ;; *) mod="$$mod@latest" ;; esac; \
		echo "go install $$mod"; \
		go install "$$mod"; \
	done

npm-install:
	@command -v npm >/dev/null || { echo "npm not found — run: nvm install --lts"; exit 1; }
	@grep -vE '^[[:space:]]*#|^[[:space:]]*$$' $(MANIFESTS)/npm-globals.txt | xargs npm install -g

pipx-install:
	@command -v pipx >/dev/null || { echo "pipx not found — run: make brew-install"; exit 1; }
	@grep -vE '^[[:space:]]*#|^[[:space:]]*$$' $(MANIFESTS)/pipx-tools.txt | while read -r pkg; do \
		pipx install "$$pkg"; \
	done

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

# SSH first; fall back to https for machines without GitHub keys yet. The
# fallback bypasses the global gitconfig because dot-gitconfig rewrites
# https://github.com/ to SSH, which would defeat it.
harness-clone:
	@test -d $(HARNESS_DIR) || git clone $(HARNESS_REPO) $(HARNESS_DIR) 2>/dev/null \
		|| GIT_CONFIG_GLOBAL=/dev/null git clone $(HARNESS_REPO_HTTPS) $(HARNESS_DIR)

harness-install: harness-clone
	$(MAKE) -C $(HARNESS_DIR) install

macos-apply:
	bash $(CURDIR)/macos/defaults.sh

doctor:
	bash $(CURDIR)/scripts/doctor.sh

drift:
	bash $(CURDIR)/scripts/drift.sh

# Raycast keeps settings in an encrypted local DB (extension configs can hold
# API tokens), so its own encrypted export is the backup mechanism — never this
# repo (*.rayconfig is gitignored). Opens the export dialog; save the file to a
# private location (iCloud Drive / 1Password). Restore on a new Mac via
# Raycast Settings -> Advanced -> Import.
raycast-export:
	open "raycast://extensions/raycast/raycast/export-settings-data"
