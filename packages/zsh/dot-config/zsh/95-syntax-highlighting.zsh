# zsh-syntax-highlighting must be sourced after all other plugins and widgets —
# hence the highest module number (after the gitignored 90-local.zsh too).
_zsh_hl="${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[ -r "$_zsh_hl" ] && source "$_zsh_hl"
unset _zsh_hl
