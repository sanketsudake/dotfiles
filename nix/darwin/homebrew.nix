# Curated package list (was ./Brewfile) — applied by `make nix-switch`, which
# runs brew bundle on the brewfile generated from these options.
# Re-curation flow: `make brew-dump` writes Brewfile.dump (gitignored); diff it
# against the generated brewfile (make brew-check prints its path) and promote
# keepers by hand. `go`/`npm` entries from the dump stay excluded (managed by
# go install / npm, not brew).
# cleanup = "none" until Phase 7: activation only installs, never removes.
{
  homebrew = {
    enable = true;

    onActivation = {
      # Removing an entry here uninstalls it on the next switch; promote any
      # ad-hoc `brew install` into this file before it gets swept.
      cleanup = "uninstall";
      autoUpdate = false;
      upgrade = false;
    };

    taps = [
      "sanketsudake/tap"
    ];

    brews = [
      # --- AI-harness prereqs ---
      "mas" # Mac App Store CLI (for the masApps below)

      # --- shell & everyday tools ---

      # --- modern CLI ---

      # --- languages & build ---

      # --- build deps (ad-hoc installs, adopted at the cleanup flip) ---
      "clang-format"
      "cmake"
      "gcc"
      "librsvg"
      "ninja"
      "pango"

      # --- containers & kubernetes ---

      # --- cloud & misc ---
      "herdr"
    ];

    casks = [
      # Previously direct-download apps, adopted into brew management.
      "1password"
      "claude"
      "devin-desktop"
      "google-chrome"
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
      { name = "sanketsudake/tap/cc-proxy"; trusted = true; }
      { name = "sanketsudake/tap/chrome-cdp"; trusted = true; }
      { name = "sanketsudake/tap/portless"; trusted = true; }
      { name = "sanketsudake/tap/cines"; trusted = true; }
    ];

    # App Store apps (need App Store sign-in on a new Mac).
    masApps = {
      "1Password for Safari" = 1569813296;
      "Numbers" = 361304891;
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
