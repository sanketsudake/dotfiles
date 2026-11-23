{
  description = "sanketsudake dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Own CLIs, packaged as flakes in their own repos (they used to come from
    # the sanketsudake/tap Homebrew casks). Each follows this flake's nixpkgs
    # so there is exactly one nixpkgs in the closure.
    cc-proxy = {
      url = "github:sanketsudake/cc-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chrome-cdp-cli = {
      url = "github:sanketsudake/chrome-cdp-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    go-portless = {
      url = "github:sanketsudake/go-portless";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, nix-darwin, ... }:
    let
      # One host = one entry below. Shared config lives in nix/darwin and
      # nix/home; per-host overrides go in the extraModules list.
      mkDarwinHost =
        extraModules:
        nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = [ ./nix/darwin ] ++ extraModules;
        };

      mac = mkDarwinHost [ ];

      # Standalone Home Manager uses the same modules on macOS and Linux.
      mkHomeHost =
        pkgs: hostModule:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs; };
          modules = [
            ./nix/home
            hostModule
          ];
        };
    in
    {
      darwinConfigurations."Sankets-MacBook-Air" = mac;

      # Keys are <user>@<hostname>, as used by the Makefile.
      homeConfigurations."sanketsudake@Sankets-MacBook-Air" = mkHomeHost mac.pkgs {
        home.username = mac.config.system.primaryUser;
        home.homeDirectory = mac.config.users.users.${mac.config.system.primaryUser}.home;
      };
      homeConfigurations."chronin@chronin" =
        mkHomeHost nixpkgs.legacyPackages.x86_64-linux ./nix/hosts/omarchy.nix;

      # make home-switch uses the Home Manager CLI pinned by flake.lock.
      packages.aarch64-darwin.home-manager = inputs.home-manager.packages.aarch64-darwin.default;
      packages.x86_64-linux.home-manager = inputs.home-manager.packages.x86_64-linux.default;

      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-tree;
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
