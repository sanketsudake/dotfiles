# Guarded: only define aliases whose targets exist on this machine.
[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ] \
  && alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
[ -x "$HOME/chrome-doctor.sh" ] \
  && alias chrome-doctor="$HOME/chrome-doctor.sh"
