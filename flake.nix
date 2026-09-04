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
    in
    {
      darwinConfigurations."Sankets-MacBook-Air" = mkDarwinHost [ ];

      formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-rfc-style;
    };
}
