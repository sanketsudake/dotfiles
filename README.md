# harness-configs

Portable AI coding-harness configs — shared skills, commands, rules, agents, and settings — provisioned from **one source of truth** across multiple [Claude Code](https://claude.com/claude-code) and [pi](https://github.com/badlogic/pi-mono) profiles.

A personal dotfiles-style repo, published so others can borrow the architecture.
Paths are hardcoded to one machine — adapt before adopting (see [Adopt it](#adopt-it)).

## Ideas worth stealing

- **One source of truth, many harnesses.**
  A single `skills/` tree feeds Claude Code *and* pi; edit once, every harness sees it immediately.
- **Two Claude profiles via `CLAUDE_CONFIG_DIR`.**
  `pclaude` / `wclaude` wrappers keep personal and work accounts isolated while sharing the same skills and rules.
- **Per-resource source tracking.**
  Each vendored skill is pinned in `skills/vendored.json` (repo, subpath, commit) and materialized on install — so an upstream update is one command and a bare clone stays reproducible.
- **Generated catalog, enforced by a doctor.**
  `skills/README.md` is generated from that metadata; `make skills-doctor` fails when anything drifts.
- **Guardrails as code, not hope.**
  Extensions for pi confirm before destructive actions, block dirty-repo commits, and protect paths; `plugins.txt` declares the plugin set and `make plugins-check` reports drift per profile.

## Layout

```
harness-configs/
├── Makefile        # primary interface — every <resource>-<action> target
├── CLAUDE.md       # guide for agents working IN this repo (full Makefile reference)
├── claude/         # Claude Code config, symlinked into both profiles
│   ├── CLAUDE.md   #   shared global user instructions
│   ├── commands/   #   slash commands
│   ├── agents/     #   subagents (+ .source.json sidecars)
│   ├── rules/      #   model routing, git hygiene, delegation
│   ├── scripts/    #   helper scripts (md formatter, statusline)
│   └── plugins.txt #   desired-state plugin list
├── skills/         # shared skills for Claude + pi — the source of truth
│   └── README.md   #   generated catalog — start here
├── suites/         # curated skill-suite landing pages
├── pi/             # pi agent config, stowed into ~/.pi
└── scripts/        # repo tooling (not symlinked into profiles)
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
git clone https://github.com/sanketsudake/harness-configs.git
cd harness-configs
# Before installing:
#   1. Edit CLAUDE_CONFIG_DIRS in the Makefile (your profiles)
#   2. Copy the pclaude/wclaude snippets from scripts/claude-multi-account.sh into your shell profile
#   3. Make claude/CLAUDE.md yours — it's opinionated
make install      # symlink claude/ + skills/ into profiles, stow pi/ into ~/.pi
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

## License

[Apache-2.0](LICENSE).
Vendored skills and extensions remain under their upstream licenses; see each resource's source metadata.
