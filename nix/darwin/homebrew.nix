# Curated package list (was ./Brewfile) — applied by `make nix-switch`, which
# runs brew bundle on the brewfile generated from these options.
# Re-curation flow: `make brew-dump` writes Brewfile.dump (gitignored); diff it
# against the generated brewfile (make brew-check prints its path) and promote
# keepers by hand. `go`/`npm` entries from the dump stay excluded (managed by
# go install / nvm, not brew).
# cleanup = "none" until Phase 7: activation only installs, never removes.
{
  homebrew = {
    enable = true;

    onActivation = {
      cleanup = "none";
      autoUpdate = false;
      upgrade = false;
    };

    taps = [
      { name = "jesseduffield/lazydocker"; trusted = true; }
      { name = "loft-sh/tap"; trusted = true; }
      { name = "minio/stable"; trusted = true; }
      { name = "openclaw/tap"; trusted = true; }
      "sanketsudake/tap"
    ];

    brews = [
      # --- core CLI ---
      "bash"
      "coreutils"
      "findutils"
      "gnu-sed"
      "grep"
      "make"
      "moreutils"
      "ripgrep"
      "tree"
      "wget"

      # --- AI-harness prereqs (stow, jq, gh, node-via-nvm, python) ---
      "stow" # dotfiles + harness symlink manager (needs >= 2.4.0)
      "jq"
      "gh"
      "nvm" # provides node/npx for skill-vendoring tooling
      "python@3.13"
      "mas" # Mac App Store CLI (for the masApps below)

      # --- shell & everyday tools ---
      "atuin"
      "btop"
      "ffmpeg"
      "pandoc"
      "poppler"
      "qpdf" # pdfunlock()
      "git-lfs"

      # --- modern CLI ---
      "fzf" # fuzzy pickers + Ctrl-T/Alt-C (Ctrl-R stays with atuin)
      "zoxide" # frecency-ranked cd (z <dir>)
      "eza" # ls with git status column (ll alias)
      "bat" # syntax-highlighted cat with git gutter
      "fd" # gitignore-aware find
      "git-delta" # readable side-by-side git diffs (wired in gitconfig)
      "yq" # jq for YAML/TOML/XML
      "jless" # interactive JSON pager
      "glow" # markdown renderer/pager for the terminal
      "dust" # visual du
      "lazygit" # git TUI (same author as lazydocker)

      # --- languages & build ---
      "go"
      "golangci-lint"
      "gomplate"
      "goreleaser"
      "mage"
      "rust"
      "openjdk"
      "maven"
      "sbt"
      "protobuf"
      "pipx"
      "uv"
      "virtualenv"
      "libpq"
      "comby"

      # --- containers & kubernetes ---
      "colima"
      "docker"
      "docker-buildx"
      "cosign"
      "helm"
      "k9s"
      "kind"
      "ko"
      "kustomize"
      "skaffold"
      "skopeo"
      "stern"
      "k6"
      "mkcert"
      "kubectx" # kubectx + kubens; fuzzy pickers with fzf installed
      "kubecolor" # colorized kubectl output (aliased to kubectl)
      "dive" # layer-by-layer container image explorer
      "trivy" # CVE/misconfig scanner for images, IaC, clusters
      "dyff" # YAML-aware structural diff (helm/k8s manifests)
      "viddy" # modern watch with diff highlighting + time travel
      "kubeconform" # fast k8s manifest schema validation
      "jesseduffield/lazydocker/lazydocker"
      "loft-sh/tap/vcluster"
      "minio/stable/mc"

      # --- cloud & misc ---
      "cloudflared"
      "hugo"
      "agent-browser"
      "herdr"
      "openclaw/tap/gitcrawl"
    ];

    casks = [
      # Previously direct-download apps, adopted into brew management.
      "1password"
      "claude"
      "devin-desktop"
      "google-chrome"
      "openvpn-connect"
      "tailscale-app"
      "wispr-flow"

      "1password-cli"
      "claude-code@latest"
      "copilot-cli"
      "devin-cli"
      "ghostty"
      "helium-browser" # Chromium-based; to replace google-chrome eventually
      "itsycal"
      "obsidian"
      "raycast" # launcher + clipboard history + window snapping + extensions
      "slack"
      "visual-studio-code"
      "zoom"
      { name = "sanketsudake/tap/cc-proxy"; trusted = true; }
      { name = "sanketsudake/tap/chrome-cdp"; trusted = true; }
      { name = "sanketsudake/tap/portless"; trusted = true; }
    ];

    # App Store apps (need App Store sign-in on a new Mac).
    masApps = {
      "1Password for Safari" = 1569813296;
      "Numbers" = 361304891;
      "Okta Verify" = 490179405;
    };

    vscode = [
      "adpyke.vscode-sql-formatter"
      "anthropic.claude-code"
      "davidanson.vscode-markdownlint"
      "docker.docker"
      "drblury.protobuf-vsc"
      "eamodio.gitlens"
      "foxundermoon.shell-format"
      "github.github-vscode-theme"
      "github.vscode-github-actions"
      "golang.go"
      "mechatroner.rainbow-csv"
      "ms-azuretools.vscode-containers"
      "ms-python.debugpy"
      "ms-python.python"
      "ms-python.vscode-pylance"
      "ms-python.vscode-python-envs"
      "ms-vscode.makefile-tools"
      "ms-vscode.vscode-speech"
      "oracle.oracle-java"
      "redhat.vscode-yaml"
      "scala-lang.scala"
      "shd101wyy.markdown-preview-enhanced"
      "vscjava.vscode-java-debug"
      "vscjava.vscode-java-dependency"
      "vscjava.vscode-maven"
    ];
  };
}
