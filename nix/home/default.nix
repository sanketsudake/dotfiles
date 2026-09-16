{
  # Never change after the first activation.
  home.stateVersion = "26.05";

  imports = [
    ./options.nix
    ./git.nix
    ./atuin.nix
    ./btop.nix
    ./gh.nix
    ./bin.nix
    ./zsh.nix
    ./packages.nix
    ./plannotator.nix
    ./harness.nix
  ];
}
