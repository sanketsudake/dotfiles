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
  inherit (config.dotfiles) claudeProfiles omarchy;

  # On Omarchy, skills/ is linked per skill into dirs that stay real: Omarchy
  # seeds ~/.agents/skills with its own skills, and a whole-dir link would hide
  # them and let omarchy-update write its symlinks into the repo. Names come
  # from sources.toml, which lists every skill; the gitignored vendored dirs
  # are invisible to the flake, their manifest entries are not. A new skill
  # appears after the next switch. The Mac keeps whole-dir links.
  skillNames = map (s: s.name) (builtins.fromTOML (builtins.readFile ../../sources.toml)).skill;
  omarchySkills = [
    "omarchy"
    "diagnose-crash"
  ];
  skillEntryLinks =
    dir:
    lib.listToAttrs (
      map (n: {
        name = "${dir}/${n}";
        value.source = link "skills/${n}";
      }) skillNames
      ++ map (n: {
        name = "${dir}/${n}";
        value.source = config.lib.file.mkOutOfStoreSymlink "/usr/share/omarchy/default/agents/skills/${n}";
      }) omarchySkills
    );

  claudeLinks = lib.listToAttrs (
    lib.concatMap (
      prof:
      map (e: {
        name = "${prof}/${e}";
        value.source = link "packages/claude/${e}";
      }) (if omarchy then lib.remove "skills" claudeEntries else claudeEntries)
    ) claudeProfiles
  )
  // lib.optionalAttrs omarchy (
    lib.mergeAttrsList (map (prof: skillEntryLinks "${prof}/skills") claudeProfiles)
  );

  # Entry names come from the package dir itself, so a vendored addition is
  # picked up by the next switch without editing this file.
  piPerFile =
    dir:
    map (name: {
      name = ".pi/${dir}/${name}";
      value.source = link "packages/pi/${dir}/${name}";
    }) (builtins.attrNames (builtins.readDir (../../packages/pi + "/${dir}")));
  piLinks = lib.listToAttrs (piPerFile "agent" ++ piPerFile "extensions") // {
    ".pi/prompts".source = link "packages/pi/prompts";
    ".pi/skills".source = link "packages/pi/skills";
    ".pi/README.md".source = link "packages/pi/README.md";
  };

  # Devin reads personal skills from ~/.agents/skills. Copilot 0.0.417 does not
  # scan that path yet (its /skills list names ~/.copilot/skills, ~/.claude/skills
  # and the two project dirs), so it gets its own link to the same tree. The two
  # links never collide: each CLI reads only its own path, so no skill is
  # discovered twice.
  agentNames = map (lib.removeSuffix ".md") (
    builtins.attrNames (
      lib.filterAttrs (n: _: lib.hasSuffix ".md" n) (builtins.readDir ../../packages/claude/agents)
    )
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
    ".copilot/skills".source = link "skills";
    ".config/devin/config.json".source = link "packages/devin/config.json";
    ".config/devin/AGENTS.md".source = link "packages/agents/AGENTS.md";
    ".copilot/settings.json".source = link "packages/copilot/settings.json";
    ".copilot/copilot-instructions.md".source = link "packages/agents/AGENTS.md";
  };
  agentsSkillLinks =
    if omarchy then skillEntryLinks ".agents/skills" else { ".agents/skills".source = link "skills"; };
in
{
  home.file =
    claudeLinks // piLinks // devinAgentLinks // copilotAgentLinks // cliLinks // agentsSkillLinks;
}
