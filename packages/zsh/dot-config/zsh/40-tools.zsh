# atuin — shell history sync/search.
command -v atuin >/dev/null && eval "$(atuin init zsh)"

# nvm — node version manager (also provides npx for harness-configs tooling).
_nvm_dir="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm"
export NVM_DIR="$HOME/.nvm"
[ -s "$_nvm_dir/nvm.sh" ] && \. "$_nvm_dir/nvm.sh"
[ -s "$_nvm_dir/etc/bash_completion.d/nvm" ] && \. "$_nvm_dir/etc/bash_completion.d/nvm"
unset _nvm_dir
