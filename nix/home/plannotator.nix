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
    # Safe defaults live in a binary wrapper, so the hook and the /plannotator-*
    # skills get them however Claude Code was started, not only from zsh.
    # --set-default: a value already in the environment still wins.
    #   BROWSER=Helium  -> `open -a Helium <url>`; also skips Glimpse
    #   SHARE=disabled  -> no share links to share.plannotator.ai / paste service
    #   REMOTE=0        -> always bind 127.0.0.1; the server has no auth (#956)
    #   AI=disabled     -> no Ask AI / review agents shelling out to `claude`
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    installPhase = ''
      install -Dm755 $src $out/bin/plannotator
      wrapProgram $out/bin/plannotator \
        --set-default PLANNOTATOR_BROWSER Helium \
        --set-default PLANNOTATOR_SHARE disabled \
        --set-default PLANNOTATOR_REMOTE 0 \
        --set-default PLANNOTATOR_AI disabled
    '';
    meta.platforms = [ "aarch64-darwin" ];
  };
in
{
  home.packages = [ plannotator ];
}
