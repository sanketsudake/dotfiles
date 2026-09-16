# Omarchy-only desktop tweaks. Omarchy owns ~/.config/hypr, so only its
# personal-override files are linked, one per file. The link points into the
# store, not the working tree: Hyprland reloads on every change, and a git
# checkout that briefly removes the repo file would load Omarchy's defaults
# with a "module 'hypr.input' not found" error. Edits apply on nix-switch.
{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.dotfiles.omarchy {
  home.file.".config/hypr/input.lua".source = ../../packages/hypr/dot-config/hypr/input.lua;

  # Caps Lock / Num Lock OSD (packages/omarchy/lock-keys-osd.sh).
  systemd.user.services.lock-keys-osd = {
    Unit = {
      Description = "Show an OSD when Caps Lock or Num Lock changes";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.bash}/bin/bash ${../../packages/omarchy/lock-keys-osd.sh}";
      # omarchy-osd and its jq/omarchy-shell come from the distro, not nix.
      Environment = [ "PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin" ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
