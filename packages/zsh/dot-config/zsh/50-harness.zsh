# AI-harness shell functions (pclaude/wclaude/claude wrappers) from this
# repo's scripts/; skipped silently until the repo is cloned.
_harness_sh="${DOTFILES_DIR:-$HOME/personal/dotfiles}/scripts/claude-multi-account.sh"
[ -r "$_harness_sh" ] && source "$_harness_sh"
unset _harness_sh

pcodex() {
  command codex -c 'tui.status_line=["model-with-reasoning","project-name","git-branch","context-used","five-hour-limit","weekly-limit"]' "$@"
}
