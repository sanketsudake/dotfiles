# coffee wraps macOS caffeinate; Omarchy has its own idle toggle.
{ config, lib, ... }:
{
  home.file = {
    ".local/bin/browser-endpoint" = {
      source = ../../packages/claude/scripts/browser-endpoint.sh;
      executable = true;
    };
  }
  // lib.optionalAttrs (!config.dotfiles.omarchy) {
    ".local/bin/coffee" = {
      source = ../../packages/bin/dot-local/bin/coffee;
      executable = true;
    };
  };
}
