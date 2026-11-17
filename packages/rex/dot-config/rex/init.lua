-- Rex configuration.
-- Docs: https://www.superlogical.com/rex/docs/customize/config
-- Validate: rex config check
-- Apply: rex config reload (make nix-switch runs it)
-- Split into more files with require("keys") etc. when this grows.

-- Panes
rex.bind("cmd+d", "pane.split", { direction = "right" })
rex.bind("cmd+shift+d", "pane.split", { direction = "down" })

-- Windows
rex.bind("cmd+shift+n", "window.new")
