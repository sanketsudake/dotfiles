# Guarded: only define aliases whose targets exist on this machine.
[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ] \
  && alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
[ -x "$HOME/chrome-doctor.sh" ] \
  && alias chrome-doctor="$HOME/chrome-doctor.sh"
# Both, not just kubecolor: it shells out to the real kubectl, so aliasing
# on kubecolor alone breaks every kubectl call on a machine without the
# client -- and breaks it invisibly. Without kubectl, kubecolor prints
# nothing at all on stdout or stderr and exits 255, and in the usual
# `kubectl get pods | head` the pipeline reports the exit status of head,
# so a missing binary reads as an empty cluster.
if command -v kubecolor >/dev/null && command -v kubectl >/dev/null; then
  alias kubectl=kubecolor
  compdef kubecolor=kubectl 2>/dev/null
fi
command -v eza >/dev/null && alias ll='eza -l --git'
command -v lazygit >/dev/null && alias lg=lazygit
command -v glow >/dev/null && alias md='glow -p'
