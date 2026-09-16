# Omarchy-only desktop tweaks. Omarchy owns ~/.config/hypr, so only its
# personal-override files are linked, one per file, and out of store: an
# `omarchy-refresh-hyprland` writes through the link and shows up as a git diff.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  repo = "${config.home.homeDirectory}/personal/dotfiles";
in
lib.mkIf config.dotfiles.omarchy {
  home.file.".config/hypr/input.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${repo}/packages/hypr/dot-config/hypr/input.lua";

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
