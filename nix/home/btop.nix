# Not on Omarchy: its btop.conf sets color_theme = "current", which its theme
# switcher repoints — a linked repo copy would pin the Mac's theme.
{ config, lib, ... }:
{
  home.file = lib.mkIf (!config.dotfiles.omarchy) {
    ".config/btop/btop.conf".source = ../../packages/btop/dot-config/btop/btop.conf;
  };
}
