# atuin — shell history sync/search.
command -v atuin >/dev/null && eval "$(atuin init zsh)"

# nvm — node version manager (also provides npx for harness-configs tooling).
export NVM_DIR="$HOME/.nvm"
[ -s "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/nvm.sh" ] && \. "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/nvm.sh"
[ -s "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/etc/bash_completion.d/nvm" ] && \. "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/etc/bash_completion.d/nvm"
