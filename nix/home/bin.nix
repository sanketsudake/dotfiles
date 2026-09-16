# coffee wraps macOS caffeinate; Omarchy has its own idle toggle.
{ config, lib, ... }:
{
  home.file = lib.mkIf (!config.dotfiles.omarchy) {
    ".local/bin/coffee" = {
      source = ../../packages/bin/dot-local/bin/coffee;
      executable = true;
    };
  };
}
