# Plannotator (github.com/backnotprop/plannotator): plan/code review UI that
# Claude Code's plannotator plugin hook calls as a bare `plannotator`.
# Not in nixpkgs; install.sh is avoided (it writes skills into the symlinked
# skills/ tree and configures other agents). Bump version + every hash
# deliberately, together with the REF of the vendored plannotator-* skills.
{ lib, pkgs, ... }:
let
  version = "0.27.15";
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  # Release asset per nix system; the hash is the asset's .sha256 in SRI form.
  assets = {
    aarch64-darwin = {
      name = "plannotator-darwin-arm64";
      hash = "sha256-8z4RRFH9GWv/xGqiF0kvxyT+FYKM6GAHYJz+vAitUwQ=";
    };
    x86_64-linux = {
      name = "plannotator-linux-x64";
      hash = "sha256-79sz9OCqFNZufwNYdzoRzEb1tfwiVwnW6sTZ6Nllo1U=";
    };
  };
  asset = assets.${pkgs.stdenv.hostPlatform.system};
  plannotator = pkgs.stdenvNoCC.mkDerivation {
    pname = "plannotator";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/${asset.name}";
      inherit (asset) hash;
    };
    dontUnpack = true;
    # Bun single-file executable: strip would corrupt the embedded payload;
    # skip fixup too, so the installed bytes match the release asset.
    dontStrip = true;
    dontFixup = true;
    # Safe defaults live in a binary wrapper, so the hook and the /plannotator-*
    # skills get them however Claude Code was started, not only from zsh.
    # --set-default: a value already in the environment still wins.
    #   BROWSER=Helium  -> `open -a Helium <url>`; also skips Glimpse (macOS
    #                      only; Linux falls back to xdg-open)
    #   SHARE=disabled  -> no share links to share.plannotator.ai / paste service
    #   REMOTE=0        -> always bind 127.0.0.1; the server has no auth (#956)
    #   AI=disabled     -> no Ask AI / review agents shelling out to `claude`
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    # Plain strings, not ''-blocks: each ''-block strips its own indentation,
    # which would change the Mac's script bytes (and its drv) for no reason.
    installPhase = lib.concatStrings [
      "install -Dm755 $src $out/bin/plannotator\n"
      "wrapProgram $out/bin/plannotator \\\n"
      (lib.optionalString isDarwin "  --set-default PLANNOTATOR_BROWSER Helium \\\n")
      "  --set-default PLANNOTATOR_SHARE disabled \\\n"
      "  --set-default PLANNOTATOR_REMOTE 0 \\\n"
      "  --set-default PLANNOTATOR_AI disabled\n"
    ];
    meta.platforms = builtins.attrNames assets;
  };
in
{
  home.packages = [ plannotator ];
}
