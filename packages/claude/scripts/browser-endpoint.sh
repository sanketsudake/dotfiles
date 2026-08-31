#!/usr/bin/env bash
# Print the CDP browser WebSocket endpoint of the user's browser (Helium).
#
# Helium is a Chromium fork; its remote-debugging port file is its own, not
# Chrome's, so tools that default to Chrome's path fail with connection_failed.
# The port file appears only after the user enables the toggle at
# helium://inspect/#remote-debugging (no restart; tabs and logins survive).
# That toggle serves no /json discovery, so port-only attach (--cdp 9222,
# --auto-connect) times out; pass this endpoint explicitly instead.
#
# Usage:
#   EP="$("$CLAUDE_CONFIG_DIR"/scripts/browser-endpoint.sh)" || ask the user to enable the toggle
#   chrome-cdp daemon start --endpoint "$EP" --json
#   agent-browser --cdp "$EP" --pin-tab
#
# Exit 1 with a message on stderr when the port file is absent.
set -euo pipefail

PORT_FILE="${HELIUM_DEVTOOLS_PORT_FILE:-$HOME/Library/Application Support/net.imput.helium/DevToolsActivePort}"

if [ ! -s "$PORT_FILE" ]; then
  echo "browser-endpoint: no port file at $PORT_FILE" >&2
  echo "browser-endpoint: ask the user to enable helium://inspect/#remote-debugging" >&2
  exit 1
fi

port="$(head -1 "$PORT_FILE")"
path="$(sed -n 2p "$PORT_FILE")"
echo "ws://127.0.0.1:${port}${path}"
