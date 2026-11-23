# Not on Omarchy: Rex runs on the Mac only.
# Rex does not watch the file — `make home-switch` calls `rex config reload`
# (see the rex-reload make target).
{ config, lib, ... }:
{
  home.file = lib.mkIf (!config.dotfiles.omarchy) {
    ".config/rex/init.lua".source = ../../packages/rex/dot-config/rex/init.lua;
  };
}
