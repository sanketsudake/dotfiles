# AI-harness links (was `make harness-link` / stow): the Claude profiles, ~/.pi,
# Devin CLI, Copilot CLI, Codex, and Antigravity get out-of-store symlinks into the repo working
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
  ];
  inherit (config.dotfiles) claudeProfiles omarchy;

  # Keep discovery roots separate from the source tree. Claude writes synced
  # skills beside these links, and Omarchy seeds its own entries there.
  # Manifest names are available even before vendored files are materialized.
  skillNames = map (s: s.name) (lib.importTOML ../../sources.toml).skill;
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
      ++ lib.optionals omarchy (map (n: {
        name = "${dir}/${n}";
        value.source = config.lib.file.mkOutOfStoreSymlink "/usr/share/omarchy/default/agents/skills/${n}";
      }) omarchySkills)
    );

  claudeLinks =
    lib.listToAttrs (
      lib.concatMap (
        prof:
        map (e: {
          name = "${prof}/${e}";
          value.source = link "packages/claude/${e}";
        }) claudeEntries
      ) claudeProfiles
    )
    // lib.mergeAttrsList (map (prof: skillEntryLinks "${prof}/skills") claudeProfiles);

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
    ".pi/README.md".source = link "packages/pi/README.md";
  };

  # Devin and Codex read personal skills from ~/.agents/skills. Copilot 0.0.417 does not
  # scan that path yet (its /skills list names ~/.copilot/skills, ~/.claude/skills
  # and the two project dirs), so it gets its own link to the same tree. The two
  # discovery roots are kept separate so each harness can manage local entries.
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
  # Codex's config.toml and auth.json stay local: Codex writes trust and other
  # mutable settings to config.toml, which may also contain credentials.
  cliLinks = {
    ".config/devin/config.json".source = link "packages/devin/config.json";
    ".config/devin/AGENTS.md".source = link "packages/agents/AGENTS.md";
    ".codex/AGENTS.md".source = link "packages/agents/AGENTS.md";
    ".copilot/settings.json".source = link "packages/copilot/settings.json";
    ".copilot/copilot-instructions.md".source = link "packages/agents/AGENTS.md";
  };
  sharedSkillRoots = [ ".agents/skills" ".copilot/skills" ".pi/skills" ];
  agentsSkillLinks = lib.mergeAttrsList (map skillEntryLinks sharedSkillRoots);
  managedSkillRoots = sharedSkillRoots ++ map (prof: "${prof}/skills") claudeProfiles;
  # Antigravity discovers skills from a JSON manifest, so that file is generated
  # with an absolute path instead of tracking a per-machine copy in the repo.
  # The plugin is a whole-dir link on purpose: hooks and subagents are read-only
  # there, and the CLI keeps its own state in PLUGIN_DATA, not beside them.
  antigravityLinks = {
    ".gemini/config/skills.json".text = builtins.toJSON {
      entries = [ { path = "${config.home.homeDirectory}/.agents/skills"; } ];
    };
    ".gemini/config/plugins/dotfiles-harness".source =
      link "packages/antigravity/plugins/dotfiles-harness";
    ".gemini/antigravity-cli/statusline.py".source = link "packages/antigravity/scripts/statusline.py";
  };
in
{
  # Retire legacy directory links before Home Manager checks the child paths.
  # Only unlink our old links. Their source contents, including synced data,
  # stay in the working tree.
  home.activation.migrateSharedSkillRoots = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    for root in ${lib.escapeShellArgs managedSkillRoots}; do
      target="$HOME/$root"
      if [[ -L "$target" && "$(realpath "$target")" == ${lib.escapeShellArg "${repo}/skills"} ]]; then
        run unlink "$target"
      fi
    done
  '';

  home.file =
    claudeLinks
    // piLinks
    // devinAgentLinks
    // copilotAgentLinks
    // cliLinks
    // agentsSkillLinks
    // antigravityLinks;
}
