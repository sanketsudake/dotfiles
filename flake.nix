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
          modules = [
            ./nix/darwin
            inputs.home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit inputs; };
                backupFileExtension = "hm-backup";
                users.sanketsudake = import ./nix/home;
              };
            }
          ]
          ++ extraModules;
        };

      # Non-NixOS Linux hosts: standalone home-manager over the distro (no
      # system layer). Same shared nix/home tree; the host module sets the
      # user and the per-host dotfiles.* knobs.
      mkHomeHost =
        system: hostModule:
        inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit inputs; };
          modules = [
            ./nix/home
            hostModule
          ];
        };
    in
    {
      darwinConfigurations."Sankets-MacBook-Air" = mkDarwinHost [ ];

      # Key is <user>@<hostname>, which the Makefile derives on Linux.
      homeConfigurations."chronin@chronin" = mkHomeHost "x86_64-linux" ./nix/hosts/omarchy.nix;

      # The home-manager CLI pinned by flake.lock (make nix-switch runs it),
      # so a Linux host needs no separately installed home-manager.
      packages.x86_64-linux.home-manager = inputs.home-manager.packages.x86_64-linux.default;

      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-tree;
      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };
}
