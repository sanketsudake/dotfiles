{
  # Never change after the first switch; it pins state-migration behavior.
  system.stateVersion = 6;

  # Required by homebrew.* and user-scoped system.defaults.
  system.primaryUser = "sanketsudake";

  # home-manager derives home.homeDirectory from this.
  users.users.sanketsudake.home = "/Users/sanketsudake";

  nixpkgs.hostPlatform = "aarch64-darwin";

  # Determinate Nix manages the nix installation itself.
  # Delete this line if switching to the official installer.
  nix.enable = false;
}
