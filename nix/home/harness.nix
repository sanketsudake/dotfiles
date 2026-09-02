# AI-harness links (was `make harness-link` / stow): the Claude profiles, ~/.pi,
# Devin CLI and Copilot CLI get out-of-store symlinks into the repo working
# tree, so vendored skills stay materialized/mutable and repo edits apply live.
# ~/.pi/agent, ~/.pi/extensions and the Devin/Copilot agent dirs link per-file
# on purpose: those tools write state beside them, and a whole-dir link would
# let a tool write into the repo (same invariant as the $HOME dotfiles).
# prompts/skills are whole-dir links, matching the old stow folding.
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

  # Devin CLI and Copilot CLI both read personal skills from ~/.agents/skills,
  # so one link serves both — never link their per-tool skills dirs too, or a
  # skill is discovered twice.
  agentNames = map (lib.removeSuffix ".md") (
    builtins.attrNames (lib.filterAttrs (n: _: lib.hasSuffix ".md" n) (
      builtins.readDir ../../packages/claude/agents
    ))
  );
  # Devin takes Claude's agent format as-is; Copilot wants the same file under
  # a `<name>.agent.md` name, hence the per-file rename here.
  devinAgentLinks = lib.listToAttrs (
    map (n: {
      name = ".config/devin/agents/${n}.md";
      value.source = link "packages/claude/agents/${n}.md";
    }) agentNames
  );
  copilotAgentLinks = lib.listToAttrs (
    map (n: {
      name = ".copilot/agents/${n}.agent.md";
      value.source = link "packages/claude/agents/${n}.md";
    }) agentNames
  );
  # Only the user-editable config of each CLI is managed. ~/.copilot/config.json
  # (login state), and both herdr-installed hook scripts, stay local files.
  cliLinks = {
    ".agents/skills".source = link "skills";
    ".config/devin/config.json".source = link "packages/devin/config.json";
    ".config/devin/AGENTS.md".source = link "packages/agents/AGENTS.md";
    ".copilot/settings.json".source = link "packages/copilot/settings.json";
    ".copilot/copilot-instructions.md".source = link "packages/agents/AGENTS.md";
  };
in
{
  home.file = claudeLinks // piLinks // devinAgentLinks // copilotAgentLinks // cliLinks;
}
