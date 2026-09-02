# dotfiles

One repo for the whole machine: a Nix-declared macOS setup (nix-darwin + home-manager flake, Homebrew for casks, a one-shot bootstrap) **and** portable AI coding-harness configs — shared skills, commands, rules, agents, and settings — provisioned from **one source of truth** across multiple [Claude Code](https://claude.com/claude-code) profiles, [pi](https://github.com/badlogic/pi-mono), [Devin CLI](https://docs.devin.ai/cli/), and [GitHub Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli).

A personal repo, published so others can borrow the architecture.
Paths are hardcoded to one machine — adapt before adopting (see [Adopt it](#adopt-it)).

## New Mac quick start

```sh
curl -fsSL https://raw.githubusercontent.com/sanketsudake/dotfiles/main/bootstrap.sh -o /tmp/bootstrap.sh
bash /tmp/bootstrap.sh
```

The script is idempotent: Xcode CLT, Homebrew, and Determinate Nix if missing, clone to `~/personal/dotfiles`, one `darwin-rebuild switch` (packages, dotfile links, macOS defaults; pre-existing files are moved to a timestamped `~/.dotfiles-backup-*` dir), harness links, tools, and `make doctor`.
Afterwards run the printed manual steps (`gh auth login`, `atuin login`, `git lfs install`) and open a new terminal.
On an existing machine, clone the repo and run `make install`.

## Ideas worth stealing

- **One source of truth, many harnesses.**
  A single `skills/` tree feeds Claude Code, pi, Devin CLI, and Copilot CLI; edit once, every harness sees it immediately.
  Devin and Copilot both read `~/.agents/skills`, so one link covers both; the same `agents/*.md` files link into each CLI under the name it expects.
- **Two Claude profiles via `CLAUDE_CONFIG_DIR`.**
  `pclaude` / `wclaude` wrappers keep personal and work accounts isolated while sharing the same skills and rules.
- **Per-resource source tracking.**
  Every skill and agent source lives in one `sources.toml` manifest; vendored skills are pinned there (repo, subpath, commit) and materialized on install — so an upstream update is one command and a bare clone stays reproducible.
- **Generated catalog, enforced by a doctor.**
  `skills/README.md` is generated from that metadata; `make skills-doctor` fails when anything drifts.
- **Guardrails as code, not hope.**
  Extensions for pi confirm before destructive actions, block dirty-repo commits, and protect paths;
  a `PreToolUse` safety hook does the same for Claude Code (deny/ask on dangerous shell, secrets, and VCS internals);
  `plugins.txt` declares the plugin set and `make plugins-check` reports drift per profile.
- **Skills are scanned before they land.**
  `make skills-scan` runs [NVIDIA SkillSpector](https://github.com/NVIDIA/skillspector) over every skill, `skills-fetch`/`skills-update` refuse a skill that fails, and accepted findings carry a reason in `skills/.security/skillspector/`.
- **Measured, not assumed.**
  `make context-budget` reports the always-loaded context per session (capped by the doctor), and a `SubagentStop`/`Stop` telemetry hook plus `make usage-report` show spend by agent type × model and cache-hit ratio.
  CI runs the doctor, catalog, script tests, and the security scan on every push.

## Layout

```
dotfiles/
├── Makefile        # primary interface — every <resource>-<action> target
├── CLAUDE.md       # guide for agents working IN this repo (full Makefile reference)
├── bootstrap.sh    # new-Mac entry point
├── flake.nix       # nix entry point; flake.lock pins nixpkgs/nix-darwin/home-manager
├── nix/            # darwin/ system config (defaults, homebrew) + home/ user env
├── manifests/      # non-brew tools: go-tools.txt, npm-globals.txt, pipx-tools.txt
├── macos/          # deliberately-changed macOS defaults (make macos-apply)
├── packages/       # dotfile sources for $HOME (zsh, git, atuin, btop, gh, bin), linked by home-manager
│   ├── agents/     #   AGENTS.md — global rules shared by Devin CLI + Copilot CLI
│   ├── devin/      #   Devin CLI config.json
│   └── copilot/    #   Copilot CLI settings.json
├── claude/         # Claude Code config, symlinked into both profiles
│   ├── CLAUDE.md   #   shared global user instructions
│   ├── commands/   #   slash commands
│   ├── agents/     #   subagents
│   ├── rules/      #   model routing, git hygiene, delegation
│   ├── scripts/    #   hooks (routing, safety guard, usage telemetry) + statusline
│   └── plugins.txt #   desired-state plugin list
├── skills/         # shared skills for Claude + pi — the source of truth
│   ├── README.md   #   generated catalog — start here
│   └── .security/  #   SkillSpector baselines (accepted findings, with reasons)
├── suites/         # curated skill-suite landing pages
├── pi/             # pi agent config, linked into ~/.pi
└── scripts/        # repo tooling (doctor, drift, resource manager — not symlinked)
```

`make install` links `skills/` and `claude/*` into both Claude profiles, `pi/` into `~/.pi`, and the shared skills, agents, and configs into Devin CLI and Copilot CLI (home-manager out-of-store symlinks) — safe to re-run.
Because everything is symlinked, one edit here applies to every profile and both harnesses at once.

## What's inside

**Skills** — **[browse the catalog](skills/README.md)** (grouped by category, generated from each skill's metadata).
Most are authored here; the rest are vendored from [pi-skills](https://github.com/badlogic/pi-skills), [cursor-team-kit](https://github.com/cursor/plugins), [anthropics/skills](https://github.com/anthropics/skills), and the [skills.sh](https://www.skills.sh/) ecosystem — each linked to its upstream source at a pinned commit.

<!-- suites:begin -->
**Suites** — curated skill sets with their own landing pages:

- **[Go CI Health](suites/go-ci-health/)** — Keep a Go repo’s CI green, fast, and secure
- **[Agent-Maintained Hugo Site](suites/hugo-site/)** — Write, illustrate, verify, optimize, and measure a Hugo blog with an agent
- **[OSS Maintainer Copilot](suites/oss-maintainer/)** — Backlog triage, CodeQL remediation, and security advisories for repos you maintain
- **[PR Shepherding](suites/pr-shepherding/)** — Get a pull request from pushed to merged: clean diff, green CI, resolved reviews
- **[Second Brain](suites/second-brain/)** — An Obsidian knowledge base your agent maintains for you
<!-- suites:end -->

**Agents**

| Agent | Purpose |
|-------|---------|
| `plan-reviewer` | Pre-execution plan review against the actual codebase; APPROVE/REVISE with evidence. |
| `bulk-mechanic` | Haiku executor for mechanical, judgment-free batches. |
| `pr-shepherd` | Drives the push → CI → bot-review loop to green. |
| `skill-auditor` | Audits a skill directory against this repo's conventions. |

**Rules**

| Rule | Governs |
|------|---------|
| `model-routing.md` | Cheapest reliable model tier per task, and effort calibration. |
| `git-hygiene.md` | Staging, commit, and push discipline. |
| `delegation.md` | When to hand work to the agents above instead of doing it inline. |

Plus the shared `CLAUDE.md` (secrets hygiene, semantic-line-break markdown per [sembr.org](https://sembr.org/)), the `/history` command, helper scripts, and pi guardrail extensions vendored from [pi-mono](https://github.com/badlogic/pi-mono).

## Adopt it

Prerequisites: `git`, `jq` (plus `gh` / `python3` / `npx` for the skills that use them).

```sh
git clone https://github.com/sanketsudake/dotfiles.git
cd dotfiles
# Before installing:
#   1. Edit CLAUDE_CONFIG_DIRS in the Makefile (your profiles)
#   2. Copy the pclaude/wclaude snippets from scripts/claude-multi-account.sh into your shell profile
#   3. Make claude/CLAUDE.md yours — it's opinionated
#   4. Review nix/, manifests/, and packages/ — they describe one person's machine
make install      # nix-switch (packages + dotfiles + defaults + harness links) + skills-materialize + tools
make skills-list  # see each skill's source and status
```

`make uninstall` reverses it.

## Working with it

Everyday targets — `CLAUDE.md` carries the full `<resource>-<action>` reference, and every `skills-*` target has an `agents-*` twin.

| Target | Does |
|--------|------|
| `install` / `uninstall` | Apply the declared system and links, or reverse it. |
| `skills-find` / `skills-add` | Discover skills on [skills.sh](https://www.skills.sh/) and vendor them. |
| `skills-catalog` / `skills-doctor` | Regenerate the catalog / validate every skill and its freshness. |
| `skills-update[-all]` | Re-fetch vendored skills whose upstream moved. |
| `plugins-check` / `plugins-sync` | Report plugin drift per profile / emit the `/plugin install` lines. |

Two gotchas: vendored `skills/` and `pi/extensions/` are overwritten on re-sync — diverge intentionally and note it durably; and use `SUBPATH=`, never `PATH=`, on fetch targets (the latter clobbers the shell `PATH`).
Plugin installation stays manual per profile — Claude Code has no headless `/plugin install`.

## Machine setup

| Target | Does |
|--------|------|
| `install` | `nix-switch` + harness links + `tools-install` |
| `nix-switch` / `nix-build` | Apply the whole declared system / build-only preview |
| `nix-check` / `nix-fmt` | Flake check + statix lint / format the nix files |
| `nix-update` | Bump `flake.lock`; review the diff like a Brewfile re-curation |
| `nix-rollback` | Switch back to the previous system generation |
| `tools-install` | `go-install` + `npm-install` + `pipx-install` from `manifests/` |
| `brew-check` | Verify installed brew state against the nix-generated brewfile |
| `brew-dump` | Regenerate gitignored `Brewfile.dump` to diff against `nix/darwin/homebrew.nix` |
| `cask-adopt` | Take over apps installed outside brew (pkg casks prompt for sudo) |
| `macos-apply` | Run `macos/defaults.sh` (Helium-only; system defaults live in nix) |
| `doctor` | Run all health checks |
| `drift` | Report divergence between recorded config and the live system, both directions |
| `raycast-export` | Open Raycast's encrypted settings export; save the file privately (never committed) |

### The nix model

The machine is declared once and applied with `make nix-switch`:
`flake.nix` pins nixpkgs, nix-darwin, and home-manager in `flake.lock`,
`nix/darwin/` declares the system (macOS defaults, and every brew/cask/mas/vscode entry via the homebrew module),
and `nix/home/` declares the user environment (dotfile links and CLI packages).
Dotfile sources stay in `packages/` with their `dot-` names;
home-manager links each file individually into `$HOME`,
so `~/.config/<tool>` stays a real directory and credential files written beside managed configs
(e.g. `gh`'s `hosts.yml`) can never land in the repo — the old `--no-folding` invariant, kept.
Never declare files from credential-bearing dirs (`gcloud`, `1Password`, `op`, `github-copilot`) or credential-bearing files (`gh/hosts.yml`, `~/.copilot/config.json`).
Every switch is a numbered generation; `make nix-rollback` returns to the previous one.
Homebrew remains for casks/taps/mas (declared in `nix/darwin/homebrew.nix`, applied by the same switch,
`cleanup = "uninstall"`: an undeclared install is removed on the next switch — promote keepers first).

Two rules with no exceptions:
flakes only see git-tracked files, so `git add` new `.nix` files before building;
and never let home-manager own a directory that holds mutable files.

### Harness links

The harness targets (`~/.claude-*`, `~/.pi`, `~/.agents`, `~/.config/devin`, `~/.copilot`) are home-manager **out-of-store** symlinks into the repo working tree (`nix/home/harness.nix`) —
the linked content stays mutable, so vendored skills materialize in place and repo edits apply live.
`~/.pi/agent`, `~/.pi/extensions`, and the Devin/Copilot agent dirs link per-file on purpose: those tools write state beside them,
and a whole-dir link would let a tool write into the repo.

Devin CLI and Copilot CLI both read personal skills from `~/.agents/skills`, so one link serves both.
The subagents in `packages/claude/agents/` link into `~/.config/devin/agents/<name>.md` and `~/.copilot/agents/<name>.agent.md` — same file, two names.
Global always-on rules come from `packages/agents/AGENTS.md`, linked as `~/.config/devin/AGENTS.md` and `~/.copilot/copilot-instructions.md`.
Of each CLI's own config, only the user-editable file is managed (`~/.config/devin/config.json`, `~/.copilot/settings.json`);
`~/.copilot/config.json` holds login state and the two `herdr-agent-state.sh` hook scripts are installed by herdr, so all three stay local files.

#### Verifying what each CLI actually loaded

`make doctor` checks that the links resolve into the repo; these commands check that the tools *use* them.

| Check | Devin CLI | Copilot CLI |
| --- | --- | --- |
| Subagents | `devin doctor` — lists the loaded profiles and warns on unknown frontmatter keys | `copilot --agent <name> -p 'reply OK'` — the run header names the agent |
| Skills | `devin skills list` — each skill with its `~/personal/dotfiles/skills/...` path | not yet active on this account (see below) |
| Global rules | `devin rules list` — `AGENTS [Standard] always-on` | `copilot -s -p '…answer from your instructions only…'` — it answers from `copilot-instructions.md` |
| Own config | read at `~/.config/devin/config.json` (`--config` overrides it) | `/settings` in an interactive session |

Copilot loads its skills dir behind an account feature flag.
To read the flag: `copilot --log-level debug --log-dir /tmp/cop -p 'hi'`, then `grep SKILLS_INSTRUCTIONS /tmp/cop/*.log`.
On this account it is `false` today, so the `~/.agents/skills` link is in place but idle;
the 0.0.417 binary already carries the path, and Devin reads the same link now.
The same debug log is the ground truth for the other two:
it warns per agent file on an unknown frontmatter key (`effort` is Claude-only, and both CLIs ignore it),
and Copilot maps `model: haiku` to `claude-haiku-4.5`.

zsh keeps its drop-in idea: `~/.zshrc` is a thin loader sourcing `~/.config/zsh/*.zsh` in `NN-` prefix order,
and machine-local uncommitted overrides go in `~/.config/zsh/90-local.zsh`
(a plain untracked file; see `90-local.zsh.example`).

### Adding a new tool config

1. `mkdir -p packages/<tool>/dot-config/<tool>` and copy the non-secret config file(s) in, using `dot-` names for anything dotted.
2. Add a `home.file` entry for each file in a new `nix/home/<tool>.nix`, import it from `nix/home/default.nix`, and add `<tool>` to `HM_PACKAGES` in the Makefile (drives doctor's link checks).
3. `git add` the new files, `make nix-switch`, review, then commit.

### Secrets policy

Nothing outside `packages/` is ever linked into `$HOME`, and no package references a credential-bearing file.
`.gitignore` blocks secret-like filenames as a second layer, and `make doctor` fails on secret-pattern filenames, credential-looking content in tracked files, or a `~/.config` dir that has become a symlink.
Nothing imports live machine files automatically any more; copy configs into `packages/` by hand and review `git diff` before committing.

## License

[Apache-2.0](LICENSE).
Vendored skills and extensions remain under their upstream licenses; see each resource's source metadata.
