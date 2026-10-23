{
  # Never change after the first switch; it pins state-migration behavior.
  system.stateVersion = 6;

  # Required by homebrew.* and user-scoped system.defaults.
  system.primaryUser = "sanketsudake";

  # home-manager derives home.homeDirectory from this.
  users.users.sanketsudake.home = "/Users/sanketsudake";

  nixpkgs.hostPlatform = "aarch64-darwin";

  # Unfree packages allowed by name only — add here deliberately.
  # allowUnfreePackages (nixpkgs 24.11+) is the name-based list form and merges
  # additively, so a later module can allow one more without restating these.
  nixpkgs.config.allowUnfreePackages = [ "raycast" ];

  # Determinate Nix manages the nix installation itself.
  # Delete this line if switching to the official installer.
  nix.enable = false;
}
