# Curated package list — installed via `make brew-install` (brew bundle).
# Re-curation flow: `make brew-dump` writes Brewfile.dump (gitignored); diff it
# against this file and promote keepers by hand. The dump is the menu, not the
# Brewfile. `go`/`npm` entries from the dump are intentionally excluded (managed
# by go install / nvm, not brew).

# --- taps -------------------------------------------------------------------
tap "atlassian/acli"
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

# --- shell & everyday tools --------------------------------------------------
brew "atuin"
brew "btop"
brew "ffmpeg"
brew "pandoc"
brew "poppler"
brew "qpdf"        # pdfunlock()
brew "git-lfs"

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
cask "slack"
cask "visual-studio-code"
cask "zoom"
cask "sanketsudake/tap/cc-proxy", trusted: true
cask "sanketsudake/tap/chrome-cdp", trusted: true
cask "sanketsudake/tap/portless", trusted: true

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
