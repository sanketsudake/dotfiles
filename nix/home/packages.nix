# CLI packages from nixpkgs (was homebrew brews), migrated in batches —
# see the Nix migration plan. Grouped to mirror the old Brewfile sections.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
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
    stow
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
    # rust stays in brew for now (rustup vs nixpkgs decision deferred);
    # nvm/node stays in brew (skill-vendoring tooling depends on it);
    # comby stays in brew (broken in nixpkgs on darwin).
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
    vcluster
    minio-client
    cloudflared
    hugo
  ];
}
