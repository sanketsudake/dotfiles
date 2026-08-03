# Guarded: only define aliases whose targets exist on this machine.
[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ] \
  && alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
[ -x "$HOME/chrome-doctor.sh" ] \
  && alias chrome-doctor="$HOME/chrome-doctor.sh"
if command -v kubecolor >/dev/null; then
  alias kubectl=kubecolor
  compdef kubecolor=kubectl 2>/dev/null
fi
command -v eza >/dev/null && alias ll='eza -l --git'
command -v lazygit >/dev/null && alias lg=lazygit
