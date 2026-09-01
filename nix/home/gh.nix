# Only config.yml is managed; hosts.yml is gh-written auth state and must
# stay out of home-manager (same reason the harness dirs stay on stow).
{
  home.file.".config/gh/config.yml".source = ../../packages/gh/dot-config/gh/config.yml;
}
