# macOS system preferences as code (was macos/defaults.sh; the Helium block
# and ~/Screenshots mkdir stay there — see that script's header).
# Only deliberately-changed settings are recorded — stock defaults are not
# restated, so Apple's defaults can evolve without this file fighting them.
{
  system.defaults = {
    NSGlobalDomain = {
      # Dark mode (fully applies to running apps after re-login).
      AppleInterfaceStyle = "Dark";

      # Fast key repeat (below the Settings UI minimum; re-login to fully apply);
      # holding a key repeats it instead of opening the accent picker.
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      ApplePressAndHoldEnabled = false;

      # Show all filename extensions.
      AppleShowAllExtensions = true;

      # Save and print dialogs open expanded; new documents save locally, not iCloud.
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      PMPrintingExpandedStateForPrint = true;
      PMPrintingExpandedStateForPrint2 = true;
      NSDocumentSaveNewDocumentsToCloud = false;

      # Tap to click, per-host mouse behavior (nix-darwin writes -currentHost).
      "com.apple.mouse.tapBehavior" = 1;
    };

    finder = {
      # List view in all Finder windows by default; path bar and status bar on;
      # no warning when changing a file extension.
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = false;
    };

    screencapture = {
      # Save to ~/Screenshots (dir created by macos/defaults.sh) without shadow.
      location = "/Users/sanketsudake/Screenshots";
      disable-shadow = true;
    };

    dock = {
      autohide = true;
      show-recents = false;
      mru-spaces = false;
    };

    # Tap to click (built-in + bluetooth trackpads).
    trackpad.Clicking = true;

    # No dedicated nix-darwin group for desktopservices: don't litter network
    # shares and USB volumes with .DS_Store files.
    CustomUserPreferences."com.apple.desktopservices" = {
      DSDontWriteNetworkStores = true;
      DSDontWriteUSBStores = true;
    };
  };
}
