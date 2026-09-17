# Omarchy (Arch + Hyprland) only — a no-op everywhere else. Ports the parts of
# Omarchy's bash rc chain (/usr/share/omarchy/default/bash/*) that matter to
# zsh: env bootstrap, editor/browser/man exports, mise, starship, eza aliases.
# zoxide and fzf are already initialized by 35-fzf.zsh / 40-tools.zsh.
[ -r /usr/share/omarchy/default/bash/env-bootstrap ] || return 0

# OMARCHY_PATH + mise shims + ~/.local/bin; POSIX sh, so source it as sh.
emulate sh -c '. /usr/share/omarchy/default/bash/env-bootstrap'

export EDITOR="${EDITOR:-omarchy-launch-editor --inline}"
export SUDO_EDITOR="$EDITOR"
# Shell-scoped on purpose (Omarchy's note): a session-wide BROWSER makes
# xdg-settings refuse to change the default browser.
export BROWSER="${BROWSER:-omarchy-launch-browser}"
export BAT_THEME=ansi
export MANROFFOPT="-c"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# mise owns Omarchy's claude/codex/gh CLIs; activating it puts those ahead of
# the nix profile. Node comes from nix: keep it out of mise (`mise rm -g node`)
# so both hosts run the same version.
command -v mise >/dev/null && eval "$(mise activate zsh)"
[[ -o interactive && "${TERM:-}" != dumb ]] && command -v starship >/dev/null \
  && eval "$(starship init zsh)"

if command -v eza >/dev/null; then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
fi

open() { xdg-open "$@" >/dev/null 2>&1 & }
