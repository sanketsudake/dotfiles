# fzf keybindings + completion (Ctrl-T files, Alt-C cd, ** tab-completion).
# Numbered BEFORE 40-tools.zsh on purpose: fzf binds Ctrl-R here, then atuin
# (loaded later) rebinds it, so history search stays with atuin.
command -v fzf >/dev/null && eval "$(fzf --zsh)"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git 2>/dev/null || find . -type f'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
