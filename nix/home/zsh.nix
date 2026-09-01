# NOT programs.zsh — it would generate its own .zshrc and destroy the
# thin-loader design (.zshrc sources ~/.config/zsh/NN-*.zsh in order).
# Each module is linked individually so ~/.config/zsh stays a REAL directory:
# the gitignored machine-local slot lives there as a plain file
# (~/.config/zsh/90-local.zsh, see 90-local.zsh.example).
{ pkgs, ... }:
{
  home.file = {
    ".zshrc".source = ../../packages/zsh/dot-zshrc;
    # brew shellenv stays — Homebrew is permanent for casks/taps.
    ".zprofile".source = ../../packages/zsh/dot-zprofile;

    ".config/zsh/00-env.zsh".source = ../../packages/zsh/dot-config/zsh/00-env.zsh;
    ".config/zsh/10-path.zsh".source = ../../packages/zsh/dot-config/zsh/10-path.zsh;
    ".config/zsh/20-aliases.zsh".source = ../../packages/zsh/dot-config/zsh/20-aliases.zsh;
    ".config/zsh/30-functions.zsh".source = ../../packages/zsh/dot-config/zsh/30-functions.zsh;
    ".config/zsh/35-fzf.zsh".source = ../../packages/zsh/dot-config/zsh/35-fzf.zsh;
    ".config/zsh/40-tools.zsh".source = ../../packages/zsh/dot-config/zsh/40-tools.zsh;
    ".config/zsh/50-harness.zsh".source = ../../packages/zsh/dot-config/zsh/50-harness.zsh;
    ".config/zsh/90-local.zsh.example".source = ../../packages/zsh/dot-config/zsh/90-local.zsh.example;
    ".config/zsh/95-syntax-highlighting.zsh".source = ../../packages/zsh/dot-config/zsh/95-syntax-highlighting.zsh;

    # Nix-store plugin sources replace the Homebrew share/ paths (the brew
    # lines in 40/95 are [ -r ]-guarded, so they go inert when those formulas
    # are removed). NN ordering keeps the invariant: syntax highlighting last.
    ".config/zsh/41-nix-autosuggestions.zsh".text = ''
      source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    '';
    ".config/zsh/96-nix-syntax-highlighting.zsh".text = ''
      source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    '';
  };
}
