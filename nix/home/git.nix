# Linked from the stow package sources in place; NOT programs.git — it would
# generate ~/.config/git/config and fight dot-gitconfig.
{
  home.file = {
    ".gitconfig".source = ../../packages/git/dot-gitconfig;
    ".config/git/ignore".source = ../../packages/git/dot-config/git/ignore;
    ".config/git/config-personal".source = ../../packages/git/dot-config/git/config-personal;
    ".config/git/config-qwiet".source = ../../packages/git/dot-config/git/config-qwiet;
  };
}
