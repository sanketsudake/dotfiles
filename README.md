# dotfiles

One repo for the whole machine: macOS dotfiles (GNU stow packages, a curated Brewfile, a one-shot bootstrap) **and** portable AI coding-harness configs — shared skills, commands, rules, agents, and settings — provisioned from **one source of truth** across multiple [Claude Code](https://claude.com/claude-code) and [pi](https://github.com/badlogic/pi-mono) profiles.

A personal repo, published so others can borrow the architecture.
Paths are hardcoded to one machine — adapt before adopting (see [Adopt it](#adopt-it)).

## New Mac quick start

```sh
curl -fsSL https://raw.githubusercontent.com/sanketsudake/dotfiles/main/bootstrap.sh -o /tmp/bootstrap.sh
bash /tmp/bootstrap.sh
```

The script is idempotent: Xcode CLT and Homebrew if missing, clone to `~/personal/dotfiles`, `brew bundle`, stow links (pre-existing files are moved to a timestamped `~/.dotfiles-backup-*` dir), harness links, and `make doctor`.
Afterwards run the printed manual steps (`gh auth login`, `atuin login`, `git lfs install`) and open a new terminal.
On an existing machine, clone the repo and run `make install`.

## Ideas worth stealing

- **One source of truth, many harnesses.**
  A single `skills/` tree feeds Claude Code *and* pi; edit once, every harness sees it immediately.
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
├── Brewfile        # curated brew formulae, casks, mas apps, VS Code extensions
├── manifests/      # non-brew tools: go-tools.txt, npm-globals.txt, pipx-tools.txt
├── macos/          # deliberately-changed macOS defaults (make macos-apply)
├── packages/       # stow packages for $HOME (zsh, git, atuin, btop, gh, bin)
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
├── pi/             # pi agent config, stowed into ~/.pi
└── scripts/        # repo tooling (doctor, drift, resource manager — not symlinked)
```

`make install` symlinks `skills/` and `claude/*` into both Claude profiles and `~/.pi`, and stows `pi/` — safe to re-run.
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

Prerequisites: `git`, [GNU `stow`](https://www.gnu.org/software/stow/), `jq` (plus `gh` / `python3` / `npx` for the skills that use them).

```sh
git clone https://github.com/sanketsudake/dotfiles.git
cd dotfiles
# Before installing:
#   1. Edit CLAUDE_CONFIG_DIRS in the Makefile (your profiles)
#   2. Copy the pclaude/wclaude snippets from scripts/claude-multi-account.sh into your shell profile
#   3. Make claude/CLAUDE.md yours — it's opinionated
#   4. Review Brewfile, manifests/, and packages/ — they describe one person's machine
make install      # brew bundle, stow $HOME packages, link claude/ + skills/ into profiles, stow pi/
make skills-list  # see each skill's source and status
```

`make uninstall` reverses it.

## Working with it

Everyday targets — `CLAUDE.md` carries the full `<resource>-<action>` reference, and every `skills-*` target has an `agents-*` twin.

| Target | Does |
|--------|------|
| `install` / `uninstall` | Link/stow everything into the profiles, or reverse it. |
| `skills-find` / `skills-add` | Discover skills on [skills.sh](https://www.skills.sh/) and vendor them. |
| `skills-catalog` / `skills-doctor` | Regenerate the catalog / validate every skill and its freshness. |
| `skills-update[-all]` | Re-fetch vendored skills whose upstream moved. |
| `plugins-check` / `plugins-sync` | Report plugin drift per profile / emit the `/plugin install` lines. |

Two gotchas: vendored `skills/` and `pi/extensions/` are overwritten on re-sync — diverge intentionally and note it durably; and use `SUBPATH=`, never `PATH=`, on fetch targets (the latter clobbers the shell `PATH`).
Plugin installation stays manual per profile — Claude Code has no headless `/plugin install`.

## Machine setup

| Target | Does |
|--------|------|
| `install` | `brew-install` + `stow-link` + harness links + `tools-install` |
| `tools-install` | `go-install` + `npm-install` + `pipx-install` from `manifests/` |
| `brew-install` / `brew-check` | Apply / verify the Brewfile |
| `brew-dump` | Regenerate gitignored `Brewfile.dump` to diff against the curated Brewfile |
| `cask-adopt` | Take over apps installed outside brew (pkg casks prompt for sudo) |
| `stow-link` / `stow-unlink` | Create / remove the `$HOME` symlinks (idempotent) |
| `stow-adopt` | Absorb pre-existing real files into the working tree; always review `git diff` after |
| `macos-apply` | Run `macos/defaults.sh` |
| `doctor` | Run all health checks |
| `drift` | Report divergence between recorded config and the live system, both directions |
| `raycast-export` | Open Raycast's encrypted settings export; save the file privately (never committed) |

### The stow model

Home packages are stowed from `packages/` into `$HOME` with `--dotfiles --no-folding` (stow ≥ 2.4.0, enforced by `doctor`).
`--dotfiles` maps `dot-zshrc` → `~/.zshrc`, so no hidden files exist in the repo.
`--no-folding` is a security invariant: it links individual files instead of whole directories, so `~/.config/<tool>` stays a real directory and credential files written beside managed configs (e.g. `gh`'s `hosts.yml`) can never land in the repo.
Never add packages for credential-bearing dirs (`gcloud`, `1Password`, `op`, `github-copilot`).
These flags apply to the `$HOME` packages only; the harness targets (`~/.claude-*`, `~/.pi`) link whole directories on purpose.

zsh follows the same drop-in idea: `~/.zshrc` is a thin loader sourcing `~/.config/zsh/*.zsh` in `NN-` prefix order, and machine-local uncommitted overrides go in `~/.config/zsh/90-local.zsh` (gitignored; see `90-local.zsh.example`).

### Adding a new tool config

1. `mkdir -p packages/<tool>/dot-config/<tool>` and copy the non-secret config file(s) in, using `dot-` names for anything dotted.
2. Add `<tool>` to `HOME_PACKAGES` in the Makefile.
3. `make stow-adopt`, review `git diff`, then commit.

### Secrets policy

Nothing outside `packages/` is ever stowed into `$HOME`, and no package references a credential-bearing file.
`.gitignore` blocks secret-like filenames as a second layer, and `make doctor` fails on secret-pattern filenames, credential-looking content in tracked files, or a `~/.config` dir that has become a symlink.
`stow-adopt` imports live machine files into tracked paths, so always review `git diff` before committing after it.

## License

[Apache-2.0](LICENSE).
Vendored skills and extensions remain under their upstream licenses; see each resource's source metadata.
