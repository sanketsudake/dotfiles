# AI-harness shell functions (pclaude/wclaude/claude wrappers) from the sibling
# harness-configs repo; skipped silently until that repo is cloned (make harness-install).
_harness_sh="${HARNESS_DIR:-$HOME/personal/harness-configs}/scripts/claude-multi-account.sh"
[ -r "$_harness_sh" ] && source "$_harness_sh"
unset _harness_sh
