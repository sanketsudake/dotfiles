# Plannotator (github.com/backnotprop/plannotator): plan/code review UI that
# Claude Code's plannotator plugin hook calls as a bare `plannotator`.
# Not in nixpkgs; install.sh is avoided (it writes skills into the symlinked
# skills/ tree and configures other agents). Bump version + hash deliberately,
# together with the REF of the vendored plannotator-* skills.
{ pkgs, ... }:
let
  version = "0.27.14";
  plannotator = pkgs.stdenvNoCC.mkDerivation {
    pname = "plannotator";
    inherit version;
    src = pkgs.fetchurl {
      url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-darwin-arm64";
      hash = "sha256-Hp9w9FTTkwKPLW/hLaiqq5MbNZH9NBqtNCgP8ZgepNA=";
    };
    dontUnpack = true;
    # Bun single-file executable: strip would corrupt the embedded payload;
    # skip fixup too, so the installed bytes match the release asset.
    dontStrip = true;
    dontFixup = true;
    installPhase = "install -Dm755 $src $out/bin/plannotator";
    meta.platforms = [ "aarch64-darwin" ];
  };
in
{
  home.packages = [ plannotator ];
}
