# Omarchy laptop (Arch Linux, x86_64): standalone home-manager on top of the
# distro. Nix owns user CLI tools and dotfile links only; pacman/yay and
# Omarchy keep the desktop, drivers, docker, and the login shell
# (manifests/arch-packages.txt).
{
  home.username = "chronin";
  home.homeDirectory = "/home/chronin";

  # Non-NixOS glue: XDG_DATA_DIRS, session vars, terminfo for nix binaries.
  targets.genericLinux.enable = true;

  dotfiles = {
    omarchy = true;
    claudeProfiles = [ ".claude-personal" ];
  };
}
