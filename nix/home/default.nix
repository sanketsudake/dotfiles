{
  # Never change after the first activation.
  home.stateVersion = "26.05";

  imports = [
    ./git.nix
    ./atuin.nix
    ./btop.nix
    ./gh.nix
    ./bin.nix
    ./zsh.nix
    ./packages.nix
  ];
}
