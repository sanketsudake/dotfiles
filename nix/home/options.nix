# Per-host knobs for the shared home modules. Defaults reproduce the Mac
# exactly; a host module (nix/hosts/*.nix) overrides what differs.
{ lib, ... }:
{
  options.dotfiles = {
    omarchy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Host runs Omarchy (Arch + Hyprland). Omarchy owns the btop theme and
        populates ~/.agents/skills itself, so those are linked around, not over.
      '';
    };
    claudeProfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        ".claude-personal"
        ".claude-work"
      ];
      description = "Claude Code config dirs (relative to $HOME) that get the harness links.";
    };
  };
}
