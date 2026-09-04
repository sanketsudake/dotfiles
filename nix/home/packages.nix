# CLI packages from nixpkgs (was homebrew brews), migrated in batches —
# see the Nix migration plan. Grouped to mirror the old Brewfile sections.
{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  # Own CLIs, built from the flake each repo now exposes. They used to be
  # sanketsudake/tap Homebrew casks (goreleaser-published binaries); nix builds
  # them from the pinned source instead. The inputs track each repo's default
  # branch, not its release tags, so `nix flake update <input>` moves to main
  # HEAD — which may sit ahead of the last tag. Pinning an input to a tag
  # becomes possible once a release carries flake.nix.
  home.packages = [
    inputs.cc-proxy.packages.${system}.default
    inputs.chrome-cdp-cli.packages.${system}.default
    inputs.go-portless.packages.${system}.default
  ]
  ++ (with pkgs; [
    # --- core CLI (batch 1) ---
    # GNU tools install unprefixed here (brew kept them g-prefixed/off-PATH
    # except grep/make), so sed/find/ls flip to GNU-by-default — deliberate,
    # matching the Brewfile's curated GNU set.
    bash
    coreutils
    findutils
    gnused
    gnugrep
    gnumake
    moreutils
    ripgrep
    tree
    wget

    # --- AI-harness prereqs ---
    jq
    gh

    # --- shell & everyday tools ---
    atuin
    btop
    git-lfs

    # --- modern CLI ---
    fzf
    zoxide
    eza
    bat
    fd
    delta
    yq-go
    jless
    glow
    dust
    lazygit

    # --- media/docs (batch 2) ---
    ffmpeg
    pandoc
    poppler
    qpdf

    # --- Go & build (batch 3) ---
    # comby was dropped entirely (broken in nixpkgs on darwin, unused).
    go
    golangci-lint
    gomplate
    goreleaser
    mage
    protobuf
    jdk
    maven
    sbt
    libpq
    uv
    pipx
    virtualenv
    python313
    rustup # toolchains live in ~/.rustup; run `rustup default stable` once
    nodejs # replaces nvm; npm -g installs go to ~/.npm-globals (NPM_CONFIG_PREFIX)

    # --- containers & kubernetes + cloud (batch 4) ---
    colima
    docker-client # brew's "docker" formula is the client too; engine runs in colima
    docker-buildx
    cosign
    kubernetes-helm
    k9s
    kind
    ko
    kustomize
    skaffold
    skopeo
    stern
    k6
    mkcert
    kubectx # kubectx + kubens; fuzzy pickers with fzf installed
    kubecolor # colorized kubectl output (aliased to kubectl)
    dive # layer-by-layer container image explorer
    trivy # CVE/misconfig scanner for images, IaC, clusters
    dyff # YAML-aware structural diff (helm/k8s manifests)
    viddy # modern watch with diff highlighting + time travel
    kubeconform # fast k8s manifest schema validation
    lazydocker
    minio-client
    cloudflared
    hugo

    # --- GUI apps (small tools where nixpkgs update lag is harmless;
    # the rest stay casks for timely self-updates) ---
    itsycal
    raycast # launcher + clipboard history + window snapping + extensions

    # --- go tools (was manifests/go-tools.txt; the unpackaged rest stays
    # there via make go-install) ---
    delve
    gopls
    gotools # goimports, stringer, deadcode, ...
    gotestsum
    go-mockery
    go-tools # staticcheck
    govulncheck
    go-licenses
    protoc-gen-go
    protoc-gen-go-grpc
  ]);
}
