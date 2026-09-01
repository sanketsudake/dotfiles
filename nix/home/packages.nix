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
  ];
}
