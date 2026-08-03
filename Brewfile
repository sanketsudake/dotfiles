# Curated package list — installed via `make brew-install` (brew bundle).
# Re-curation flow: `make brew-dump` writes Brewfile.dump (gitignored); diff it
# against this file and promote keepers by hand. The dump is the menu, not the
# Brewfile. `go`/`npm` entries from the dump are intentionally excluded (managed
# by go install / nvm, not brew).

# --- taps -------------------------------------------------------------------
tap "jesseduffield/lazydocker", trusted: true
tap "loft-sh/tap", trusted: true
tap "minio/stable", trusted: true
tap "openclaw/tap", trusted: true
tap "sanketsudake/tap"

# --- core CLI ---------------------------------------------------------------
brew "bash"
brew "coreutils"
brew "findutils"
brew "gnu-sed"
brew "grep"
brew "make"
brew "moreutils"
brew "ripgrep"
brew "tree"
brew "wget"

# --- harness-configs prereqs (stow, jq, gh, node-via-nvm, python) -----------
brew "stow"        # dotfiles + harness-configs symlink manager (needs >= 2.4.0)
brew "jq"
brew "gh"
brew "nvm"         # provides node/npx for harness-configs skill tooling
brew "python@3.13"
brew "mas"         # Mac App Store CLI (for the mas entries below)

# --- shell & everyday tools --------------------------------------------------
brew "atuin"
brew "btop"
brew "ffmpeg"
brew "pandoc"
brew "poppler"
brew "qpdf"        # pdfunlock()
brew "git-lfs"
brew "zsh-autosuggestions"     # ghost-text next-command suggestion from history
brew "zsh-syntax-highlighting" # invalid commands go red before you hit enter

# --- modern CLI --------------------------------------------------------------
brew "fzf"         # fuzzy pickers + Ctrl-T/Alt-C (Ctrl-R stays with atuin)
brew "zoxide"      # frecency-ranked cd (z <dir>)
brew "eza"         # ls with git status column (ll alias)
brew "bat"         # syntax-highlighted cat with git gutter
brew "fd"          # gitignore-aware find
brew "git-delta"   # readable side-by-side git diffs (wired in gitconfig)
brew "yq"          # jq for YAML/TOML/XML
brew "jless"       # interactive JSON pager
brew "dust"        # visual du
brew "lazygit"     # git TUI (same author as lazydocker)

# --- languages & build -------------------------------------------------------
brew "go"
brew "golangci-lint"
brew "gomplate"
brew "goreleaser"
brew "mage"
brew "rust"
brew "openjdk"
brew "maven"
brew "sbt"
brew "protobuf"
brew "pipx"
brew "uv"
brew "virtualenv"
brew "libpq"
brew "comby"

# --- containers & kubernetes -------------------------------------------------
brew "colima"
brew "docker"
brew "docker-buildx"
brew "cosign"
brew "helm"
brew "k9s"
brew "kind"
brew "ko"
brew "kustomize"
brew "skaffold"
brew "skopeo"
brew "stern"
brew "k6"
brew "mkcert"
brew "kubectx"     # kubectx + kubens; fuzzy pickers with fzf installed
brew "kubecolor"   # colorized kubectl output (aliased to kubectl)
brew "dive"        # layer-by-layer container image explorer
brew "trivy"       # CVE/misconfig scanner for images, IaC, clusters
brew "dyff"        # YAML-aware structural diff (helm/k8s manifests)
brew "viddy"       # modern watch with diff highlighting + time travel
brew "kubeconform" # fast k8s manifest schema validation
brew "jesseduffield/lazydocker/lazydocker"
brew "loft-sh/tap/vcluster"
brew "minio/stable/mc"

# --- cloud & misc ------------------------------------------------------------
brew "awscli"
brew "okta-awscli"
brew "cloudflared"
brew "codecov-cli"
brew "semgrep"
brew "hugo"
brew "agent-browser"
brew "herdr"
brew "openclaw/tap/gitcrawl"

# --- casks -------------------------------------------------------------------
# Previously direct-download apps, adopted into brew management (make cask-adopt).
cask "1password"
cask "claude"
cask "devin-desktop"
cask "google-chrome"
cask "openvpn-connect"
cask "tailscale-app"
cask "wispr-flow"

cask "1password-cli"
cask "claude-code@latest"
cask "copilot-cli"
cask "devin-cli"
cask "dbeaver-community"
cask "gcloud-cli"
cask "ghostty"
cask "insomnia"
cask "itsycal"
cask "obsidian"
cask "postman"
cask "raycast"     # launcher + clipboard history + window snapping + extensions
cask "slack"
cask "visual-studio-code"
cask "zoom"
cask "sanketsudake/tap/cc-proxy", trusted: true
cask "sanketsudake/tap/chrome-cdp", trusted: true
cask "sanketsudake/tap/portless", trusted: true

# --- App Store apps (need App Store sign-in on a new Mac) --------------------
mas "1Password for Safari", id: 1569813296
mas "Numbers", id: 361304891
mas "Okta Verify", id: 490179405

# --- vscode extensions -------------------------------------------------------
vscode "adpyke.vscode-sql-formatter"
vscode "anthropic.claude-code"
vscode "davidanson.vscode-markdownlint"
vscode "docker.docker"
vscode "drblury.protobuf-vsc"
vscode "eamodio.gitlens"
vscode "foxundermoon.shell-format"
vscode "github.github-vscode-theme"
vscode "github.vscode-github-actions"
vscode "golang.go"
vscode "mechatroner.rainbow-csv"
vscode "ms-azuretools.vscode-containers"
vscode "ms-python.debugpy"
vscode "ms-python.python"
vscode "ms-python.vscode-pylance"
vscode "ms-python.vscode-python-envs"
vscode "ms-vscode.makefile-tools"
vscode "ms-vscode.vscode-speech"
vscode "oracle.oracle-java"
vscode "redhat.vscode-yaml"
vscode "scala-lang.scala"
vscode "shd101wyy.markdown-preview-enhanced"
vscode "shiftleft.shiftleft-core"
vscode "vscjava.vscode-java-debug"
vscode "vscjava.vscode-java-dependency"
vscode "vscjava.vscode-maven"
