# atuin — shell history sync/search (binds Ctrl-R after fzf in 35-fzf.zsh).
command -v atuin >/dev/null && eval "$(atuin init zsh)"

# zoxide — frecency-ranked cd (z <dir>, zi interactive).
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# zsh-autosuggestions — ghost-text next-command suggestion, accept with right arrow.
_zsh_autosuggest="${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[ -r "$_zsh_autosuggest" ] && source "$_zsh_autosuggest"
unset _zsh_autosuggest

# nvm — node version manager (also provides npx for the skill-vendoring tooling).
_nvm_dir="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm"
export NVM_DIR="$HOME/.nvm"
[ -s "$_nvm_dir/nvm.sh" ] && \. "$_nvm_dir/nvm.sh"
[ -s "$_nvm_dir/etc/bash_completion.d/nvm" ] && \. "$_nvm_dir/etc/bash_completion.d/nvm"
unset _nvm_dir
