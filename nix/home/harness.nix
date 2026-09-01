# AI-harness links (was `make harness-link` / stow): the Claude profiles and
# ~/.pi get out-of-store symlinks into the repo working tree, so vendored
# skills stay materialized/mutable and repo edits apply live.
# ~/.pi/agent and ~/.pi/extensions link per-file on purpose: pi writes state
# beside them, and a whole-dir link would let a tool write into the repo
# (same invariant as the $HOME dotfiles). prompts/skills are whole-dir links,
# matching the old stow folding.
{ config, lib, ... }:
let
  repo = "${config.home.homeDirectory}/personal/dotfiles";
  link = p: config.lib.file.mkOutOfStoreSymlink "${repo}/${p}";

  claudeEntries = [
    "CLAUDE.md"
    "commands"
    "rules"
    "scripts"
    "agents"
    "skills"
  ];
  claudeProfiles = [
    ".claude-personal"
    ".claude-work"
  ];
  claudeLinks = lib.listToAttrs (
    lib.concatMap (
      prof:
      map (e: {
        name = "${prof}/${e}";
        value.source = link "packages/claude/${e}";
      }) claudeEntries
    ) claudeProfiles
  );

  # Entry names come from the package dir itself, so a vendored addition is
  # picked up by the next switch without editing this file.
  piPerFile =
    dir:
    map (name: {
      name = ".pi/${dir}/${name}";
      value.source = link "packages/pi/${dir}/${name}";
    }) (builtins.attrNames (builtins.readDir (../../packages/pi + "/${dir}")));
  piLinks =
    lib.listToAttrs (piPerFile "agent" ++ piPerFile "extensions")
    // {
      ".pi/prompts".source = link "packages/pi/prompts";
      ".pi/skills".source = link "packages/pi/skills";
      ".pi/README.md".source = link "packages/pi/README.md";
    };
in
{
  home.file = claudeLinks // piLinks;
}
