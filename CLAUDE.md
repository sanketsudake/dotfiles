# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

One repo for the whole machine:

- **macOS system** — a nix-darwin + home-manager flake (`flake.nix`, `nix/`): `nix/darwin/` declares macOS defaults and every Homebrew formula/cask/mas/vscode entry, `nix/home/` declares dotfile links and CLI packages. Dotfile sources live under `packages/` (stow-style `dot-` names, linked per-file by home-manager); tool manifests under `manifests/`; `bootstrap.sh` for new Macs; `macos/defaults.sh` is Helium-browser-only.
- **pi** (the `pi-mono` coding agent) — config lives under `packages/pi/` and is linked into `~/.pi` by home-manager (`nix/home/harness.nix`).
- **Devin CLI and GitHub Copilot CLI** — each CLI's user-editable config lives under `packages/devin/` and `packages/copilot/`, its global rules in the shared `packages/agents/AGENTS.md`, and both read the repo's `skills/` tree through one `~/.agents/skills` link (`nix/home/harness.nix`).
- **Claude Code** — a shared global `CLAUDE.md`, `skills/`, `commands/`, `rules/`, `scripts/`, and `agents/` are symlinked into `~/.claude-personal/` and `~/.claude-work/`.

There is no application to build/test/lint.
The `Makefile` is the primary interface; targets follow `<resource>-<action>` naming (`nix-switch`, `skills-fetch`).
`make nix-switch` is the apply verb for the declared system (build-only preview: `make nix-build`; rollback: `make nix-rollback`).
Two hard nix rules: flakes only see git-tracked files (`git add` new `.nix` files before building), and home-manager must never own a directory holding mutable files (manage files individually).

## Makefile targets

All targets follow a `<resource>-<action>` naming convention (e.g. `skills-link`, `skills-sync`), except the `install`/`uninstall` aggregates.

- `make install` — runs `nix-switch` (packages, dotfile links, harness links, macOS defaults in one generation), `skills-materialize` (reconstructs the gitignored vendored skill dirs from `sources.toml`), then `tools-install`.
  Safe to re-run. Harness links (`~/.claude-*`, `~/.pi`) are home-manager out-of-store symlinks defined in `nix/home/harness.nix`; a real file at a managed name must be moved aside by hand.
  Materialization needs network on a fresh clone; offline, already-present vendored skills are left as-is and missing ones are reported as skipped.
- `make uninstall` — reverses the above.
- `make skills-sync` — clones/pulls `github.com/badlogic/pi-skills` into `/tmp/pi-skills` and copies each skill dir into `./skills/`.
  Bulk vendoring of the badlogic set; local edits to files under those `skills/<upstream-name>/` dirs are overwritten on next sync.
  For single skills from arbitrary repos, use `skills-fetch` (see "Skill & agent source management" below).
- `make extensions-sync` — clones/pulls `github.com/badlogic/pi-mono` into `/tmp/pi-mono` and copies the whitelisted set (see `PI_EXTENSIONS` in the Makefile) from `packages/coding-agent/examples/extensions` into `./packages/pi/extensions/`.
  Same vendoring caveat applies.
- `make plugins-check` — diffs `manifests/claude-plugins.txt` (desired, user-scoped) against `<CLAUDE_CONFIG_DIR>/plugins/installed_plugins.json` for each profile, reporting missing/extra.
  Requires `jq`.
- `make plugins-sync` — same diff as `plugins-check` but emits the exact `/plugin install <name>` lines per profile, prefixed with the wrapper to enter (`pclaude` / `wclaude`).
  Copy-paste into a session in the right profile to close the drift.
  Installation itself stays manual — Claude Code has no headless `/plugin install`.

## Skill & agent source management

`scripts/resource-manager.sh` (wrapped by the `skills-*` and `agents-*` make targets) fetches individual **skills** or **agents** from any git repo at any subpath and tracks where each came from, so they can be updated later.
It is repo tooling and lives in top-level `scripts/`, not `packages/claude/scripts/` — it is not symlinked into the profiles.
`scripts/test-*.sh` and `scripts/test-*.py` are the repo's own regression tests (run by CI); `scripts/test-resource-manager.sh` round-trips a fetch → materialize → doctor → delete in a throwaway clone, `scripts/test-safety-guard-hook.py` is the table-driven test of the safety gate.
Hook scripts and repo tooling that parse JSON or do regex work are Python (stdlib only, 3.9+); shell stays for the thin wrappers around `make`/`git`.
Requires `git` and `jq`.

The tool takes a leading `--kind skill|agent`; the make targets supply it.
The two kinds differ in structure:

- A **skill** is a directory under `skills/` validated by a `SKILL.md`.
- An **agent** is a single `.md` file under `packages/claude/agents/`; its committed record is its `[[agent]]` entry in `sources.toml`.

They also differ in what gets committed, which turns on a resource's **provenance**:

- **Vendored** — fetched from an upstream repo (`repo != null`).
  We don't author it; this repo just tracks a pin.
- **Authored** — born in this repo (`repo: null`, e.g. `harvest-automation`, `debug-ci`); this repo is its only home.
  `update` and `delete` treat it as having no upstream.

**Every resource is recorded in the single committed manifest, `sources.toml`** — name-sorted `[[skill]]` and `[[agent]]` arrays of tables, read and written through `scripts/toml-manifest.py` (stdlib `tomllib`, python >= 3.11; the writer is deterministic, so diffs stay per-entry).
A vendored entry carries `{name, repo, subpath, ref, commit, category, description}`, where `commit` is the resolved SHA of `ref` and `category`/`description` are cached so the catalog and doctor render without materializing; an authored entry carries just `{name, category[, note]}`.

**Vendored skills are not committed.**
Each vendored skill's `skills/<name>/` dir — including its regenerated `.source.json` materialize marker — is **gitignored** (a managed block in `.gitignore`, rewritten by the tool) and **materialized** from the pinned `commit` by `make install`.
The manifest is the source of truth; the on-disk `.source.json` is a materialization artifact, not a committed record.

**Authored skills stay committed** as normal `skills/<name>/` dirs — they survive materialize and `skills-update-all` untouched.

**Agent `.md` files are always committed**, vendored or authored; only their source record lives in the manifest.
A resource with no manifest entry is reported `unmanaged`.

An optional `category` field on the manifest entry groups a resource in `list`/catalog output.
Skills are categorized this way rather than by folder because Claude Code and pi scan `skills/` only one level deep, so nesting skills into category subfolders would hide them.

Targets (each `skills-*` has an `agents-*` twin taking the same variables):

- `make skills-fetch REPO=owner/name SUBPATH=path/to/skill [REF=main] [NAME=…] [FORCE=1]` — shallow sparse-clone, validate the subpath, copy it into `skills/<NAME>/`; for a vendored skill it also upserts the `sources.toml` entry (pinned `commit` + cached `category`/`description`) and adds the `.gitignore` line, so the fetched dir lands untracked.
  Refuses to overwrite unless `FORCE=1`.
  A full GitHub URL also works: `URL='https://github.com/owner/name/tree/<ref>/<subpath>'`.
- `make skills-materialize [NAME=…] [FORCE=1]` — reconstruct the gitignored vendored skill dirs from the manifest pins (git-init + shallow fetch of the exact `commit` + sparse-checkout).
  Idempotent: skips a dir whose `.source.json` already records the pinned commit unless `FORCE=1`.
  A full run also **reconciles down**: a vendored dir that has fallen out of the manifest (e.g. a `skills-delete` that landed via `git pull` on another machine) is pruned, so the on-disk vendored set matches the manifest instead of leaving a deleted skill live in the profiles.
  Pruning is guarded to untracked dirs whose `.source.json` still names a `repo`, so a committed authored skill is never removed.
  `NAME=` materializes just that one and prunes nothing.
  `make install` runs this first; it never fails the build offline — unreachable skills are warned and skipped.
- `make agents-fetch REPO=owner/name SUBPATH=path/to/agent.md [REF=main] [NAME=…] [FORCE=1]` — same, but the subpath is a `.md` file (NAME defaults to its basename minus `.md`), copied into `packages/claude/agents/<NAME>.md`.
  Accepts a `/blob/` URL too.
  `fetch` also takes an optional `CATEGORY=…` to tag the manifest entry on the way in.
- `make skills-list` / `make agents-list` — every resource with its status (`remote`/`local`/`unmanaged`) and source, grouped under a `<category> (<count>)` header (uncategorized last-ish, sorted).
- `make skills-category NAME=… CATEGORY=…` / `make agents-category NAME=… CATEGORY=…` — set/replace a resource's category on its `sources.toml` entry (creating a minimal authored entry if none exists).
  Use kebab-case slugs that match the README's domain groups.
- `make skills-update NAME=…` / `make agents-update NAME=…` — re-resolve the recorded `ref`; if the upstream commit moved, pin the new commit and re-copy, else report up to date (prints `old→new`, preserving `category`).
  For a vendored skill this re-materializes the dir and rewrites its `sources.toml` entry (refreshing the cached `description`); for an agent it re-copies the `.md` and rewrites the entry.
  Skips `local`/authored and `unmanaged`.
- `make skills-update-all` / `make agents-update-all` — update every remote resource of that kind.
- `make skills-delete NAME=… [YES=1]` / `make agents-delete NAME=… [YES=1]` — remove the resource and its `sources.toml` entry; for a vendored skill this also drops its `.gitignore` line.
  Prompts unless `YES=1`.
- `make skills-catalog [CHECK=1]` — regenerate the standalone catalog at `skills/README.md` (category-grouped tables).
  Every skill's `category` comes from `sources.toml`; vendored descriptions are cached there too, while authored ones come from `SKILL.md` frontmatter (first sentence, truncated) — so the catalog regenerates correctly even on a bare checkout where the vendored dirs aren't materialized.
  The main `README.md` just links to it.
  Run it after adding, removing, or recategorizing a skill; `CHECK=1` only verifies (exit 1 if stale).
- `make context-budget [CHECK=1] [TOP=N]` — estimate the always-loaded context this repo injects into every Claude Code session (shared `packages/claude/CLAUDE.md` + `rules/*.md`, every skill's name+description, every agent's and command's name+description; tokens ≈ chars/4, no API call), per segment and in total, plus the N heaviest skill descriptions.
  `CHECK=1` exits 1 when the total exceeds `CONTEXT_BUDGET_TOKENS` (Makefile default 12000; `skills-doctor` enforces the same cap, so CI and the commit gate catch growth).
  Raise the cap deliberately in the Makefile — the diff is the alert.
  Plugin/marketplace skills live outside this repo and are not counted.
- `make skills-scan [NAME=…] [LLM=1] [SHOW=1] [REPORT=file] [FAIL_AT=50]` — security-scan skills with [NVIDIA SkillSpector](https://github.com/NVIDIA/skillspector) via `scripts/skills-scan.py` (prompt injection, exfiltration, privilege escalation, supply chain, excessive agency, dangerous code, …).
  Every skill by default (authored + materialized vendored), exported minus `__pycache__`/`.pyc`/`bin/` so only what would be installed is scanned; static analysis by default, `LLM=1` adds the semantic pass through the local `claude` CLI.
  Fails on any residual HIGH/CRITICAL finding or a risk score ≥ `FAIL_AT`.
  Accepted findings live in `skills/.security/skillspector/` — `_global.json` for every skill, `<name>.json` per skill — as SkillSpector baseline glob rules, each with a `reason`; `SHOW=1` lists what they suppress.
  `skills-fetch` and `skills-update` run the same scan on the staged skill **before** installing it and refuse on failure (`SKILLS_SCAN=0` installs unscanned, logged); when `skillspector` is not installed the gate warns and lets the install through.
  Install: `make skillspector-install` — pinned to `SKILLSPECTOR_REF` in the Makefile (the release the baselines were reviewed against); bump it deliberately and re-review `skills/.security/skillspector/`.
  `skills-delete` also removes the skill's baseline, and `skills-doctor` flags a baseline that names no skill.
- `make skills-doctor` / `make agents-doctor` — validate every resource: for skills, the manifest is valid TOML (required fields on vendored entries, no duplicate names, every vendored dir gitignored), each authored dir has a `SKILL.md` + a `sources.toml` entry with `category`, an authored skill's optional `evals/evals.json` (golden tasks in the skill-creator shape `{skill_name, evals: [{id, name, prompt, expected_output, files}]}`, grown by `harvest-automation`'s `apply evals`) is well-formed, and no dir is a stale vendored orphan (a `.source.json` naming a `repo` with no manifest entry — `skills-materialize` prunes these), plus `skills/README.md` is current and the always-loaded context is under `CONTEXT_BUDGET_TOKENS` (see `context-budget`); for agents, markdown present with non-empty frontmatter `name`/`description` and a `sources.toml` entry carrying a `category`.
  Exit 1 on any issue.
- `make suites-catalog [CHECK=1]` — regenerate (or verify) the generated blocks in `suites/*/README.md` and the Suites index in `README.md` (see "Skill suites").
- `make preflight` / `make lint` / `make test` — the pre-flight gate (both doctors + lint), the syntax pass alone (`bash -n`, `py_compile`), and the repo's own regression tests (`scripts/test-*.{sh,py}`); the commit-gate hook and CI call these same targets.

Note: the make variable is `SUBPATH`, not `PATH` — `PATH=` on a make command line would clobber the shell `PATH` inside recipes and break `git`/`jq`.

## Skill suites

A **suite** is a curated, ordered set of skills with a shareable landing page — pure metadata + docs, the flat `skills/` tree is untouched.

- `suites/<name>/suite.json` — `{"title", "tagline"?, "skills": [ordered skill names]}`; membership lives here, never in `sources.toml`.
- `suites/<name>/README.md` — hand-written narrative; the region between `<!-- suite-skills:begin/end -->` markers (skill table + skills.sh install command) is generated.
- The main `README.md`'s `<!-- suites:begin/end -->` region (the Suites index) is generated too; `skills/README.md` remains owned by `skills-catalog` alone.
- `make suites-catalog [CHECK=1]` regenerates (or verifies) all generated regions; `make skills-doctor` includes the check.
- To add a suite: create the dir with `suite.json` + a README containing the markers, then run `make suites-catalog`.

## skills.sh discovery + fetch (the `skills` CLI)

`scripts/skills-vendor.sh` (wrapped by `skills-find` / `skills-add`) is a thin front-end onto the vercel-labs [`skills`](https://github.com/vercel-labs/skills) CLI — the [skills.sh](https://www.skills.sh/) ecosystem — for **discovering** skills the repo doesn't already track and **fetching** them into `skills/`.
Requires `npx` (Node.js) and `jq`; it also relies on `resource-manager.sh`.

- `make skills-find [Q=query] [OWNER=org]` — `npx skills find`; prints ranked skills.sh hits as `owner/repo@skill`.
- `make skills-add SOURCE=owner/repo [SKILL='a b'] [ALL=1] [REF=…] [CATEGORY=…] [FORCE=1]` — fetch + vendor.
  `SOURCE` accepts the `owner/repo@skill` form `skills-find` prints (paste it verbatim); the `@skill` suffix is peeled into a selected skill.
  `CATEGORY=` tags every skill fetched in the call (it flows through to the `sources.toml` entry).

The integration is deliberately **hybrid**, not a replacement for `resource-manager.sh`.
`skills-vendor.sh` uses the CLI only as a *resolver/fetcher*: it runs `skills add … --copy` into a throwaway staging dir, reads the CLI's project `skills-lock.json` (per skill: `source`, `sourceType`, `skillPath`), then re-vendors each through `resource-manager.sh fetch`.
So a CLI-fetched skill is recorded in `sources.toml` and gitignored/materialized **exactly like any other vendored skill**, and `skills-list` / `skills-update` / `skills-delete` plus the Makefile symlinks keep working unchanged — no second update mechanism, no CLI lockfile committed to the repo.

Why not let the `skills` CLI own installation directly (its `add`/`update`/`experimental_install`):

- Its agent→path map is fixed (`claude-code` → `~/.claude/skills`); it ignores `CLAUDE_CONFIG_DIR`, so it can't target the two profiles (`~/.claude-personal`, `~/.claude-work`) — which our single symlinked `skills/` tree already serves.
- It manages skills only, not the `packages/claude/agents/` subagents (`resource-manager.sh --kind agent` still owns those).
- It installs into per-agent dirs from its own canonical copy; this repo's reproducibility comes from the pinned `sources.toml` manifest (materialized deterministically from each recorded `commit`), so our vendoring pipeline stays the backbone.

## Architecture notes that are easy to miss

- **Two Claude profiles via `CLAUDE_CONFIG_DIR`.**
  `scripts/claude-multi-account.sh` is documentation (shell-function snippets to copy into `~/.zprofile`), not something that runs.
  The `pclaude`/`wclaude` wrappers set `CLAUDE_CONFIG_DIR` to `~/.claude-personal` or `~/.claude-work`.
  Both dirs share the same `CLAUDE.md` and `skills/` via symlinks maintained by the Makefile — changes to `packages/claude/CLAUDE.md` or `skills/` immediately apply to both profiles.
- **`packages/claude/CLAUDE.md` is the shared global user CLAUDE.md**, not this file.
  It gets symlinked to `~/.claude-personal/CLAUDE.md` and `~/.claude-work/CLAUDE.md` by `claude-md-link`.
  Keep it minimal and profile-agnostic.
- **`packages/pi/` is linked per-file into `~/.pi`** by `nix/home/harness.nix` (`agent/`, `extensions/` per-file; `prompts`, `skills` whole-dir).
  Entry names come from the package dirs at eval time, so a vendored addition is picked up by the next `make nix-switch`.
  That means `packages/pi/agent/settings.json`, `packages/pi/extensions/*.ts`, and `packages/pi/prompts/` are the live files the agent reads — edits here take effect immediately in `~/.pi/...`.
  
- **Devin CLI and Copilot CLI share the repo's skills and agents** (`nix/home/harness.nix`).
  `~/.agents/skills` is the one personal-skills path both CLIs read, so it links to `skills/` and their per-tool skills dirs are deliberately left unlinked (a second link would make every skill discovered twice).
  Every `packages/claude/agents/*.md` links into `~/.config/devin/agents/<name>.md` (Devin takes the Claude agent format as-is) and `~/.copilot/agents/<name>.agent.md` (Copilot needs that suffix) — one source file, two names, derived from the dir at eval time like the pi links.
  Of each CLI's own config only the user-editable file is managed: `~/.config/devin/config.json` and `~/.copilot/settings.json`.
  Both are live out-of-store links, so a write by the tool (Devin records `shell.setup_complete`; herdr rewrites its hook block on reinstall) lands in the repo as a visible `git diff`, or replaces the link with a real file if the tool writes by temp+rename (`make doctor` flags that) — review either rather than reverting blindly.
  **Never manage** `~/.copilot/config.json` (login state) or either `herdr-agent-state.sh` (herdr-installed, its header says a reinstall overwrites it).
  To check what each CLI really loaded (not just that the link exists), see README.md § "Verifying what each CLI actually loaded": `devin doctor` / `devin skills list` / `devin rules list`, and for Copilot a `--log-level debug` run.
  Copilot's skills dir is gated by the account feature flag `SKILLS_INSTRUCTIONS`, `false` today — the `~/.agents/skills` link is in place but idle on that side; Devin reads it now.
  `packages/agents/AGENTS.md` is the shared global rules file for these two CLIs (linked as `~/.config/devin/AGENTS.md` and `~/.copilot/copilot-instructions.md`); keep it harness-neutral — `packages/claude/CLAUDE.md` stays Claude-only because it uses `$CLAUDE_CONFIG_DIR` paths.
- **`packages/pi/extensions/subagent/` is a directory extension** (listed without `.ts` suffix in `PI_EXTENSIONS`); the rest are single-file TS extensions.
  Adding a new upstream extension requires editing `PI_EXTENSIONS` in the Makefile.
- **`skills/` is the single source of truth** for skills across pi, both Claude profiles, Devin CLI, and Copilot CLI.
  The `claude` and `pi` packages each carry a committed `skills -> ../../skills` symlink, so the harness links expose the tree at `~/.pi/skills`, `~/.claude-personal/skills`, `~/.claude-work/skills`; `~/.agents/skills` links straight to `skills/` and serves Devin and Copilot.
  What's *committed* under it, though, is only the authored skill dirs (their source records live in `sources.toml`); vendored skill dirs are gitignored and materialized into place (see the manifest model above), so the symlinked tree the tools read is authored-committed + vendored-materialized.
- **`packages/claude/commands/`, `packages/claude/rules/`, `packages/claude/scripts/`, and `packages/claude/agents/`** are the single source of truth for user-scoped slash commands, rules, helper scripts, and subagents across both Claude profiles.
`commands-link` / `rules-link` / `scripts-link` / `agents-link` symlink them into `~/.claude-personal/` and `~/.claude-work/` (not into `~/.pi/` — pi doesn't consume these; pi has its own vendored `packages/pi/extensions/subagent/agents/`).
Rules and docs reference scripts via `$CLAUDE_CONFIG_DIR/scripts/...` so the path resolves correctly under either profile.
`packages/claude/scripts/` currently holds `agent-routing-hook.sh` (the `PreToolUse` routing hook referenced by `rules/model-routing.md`),
`safety-guard-hook.py` (a `PreToolUse` deny/ask gate on `Bash` and `Edit|Write` — the Claude-side twin of pi's `permission-gate.ts` + `protected-paths.ts`, referenced by `rules/git-hygiene.md`),
`usage-log-hook.py` + `usage-report.py` (`SubagentStop`/`Stop`/`SessionEnd` telemetry into `$CLAUDE_CONFIG_DIR/usage.jsonl` and its aggregator, also referenced by `rules/model-routing.md`; `make usage-report` runs the aggregator for every profile),
`browser-endpoint.sh` (prints the CDP endpoint of the user's browser, referenced by `packages/claude/CLAUDE.md`),
and `statusline-command.sh` (a `statusLine` hook script).
No hook among them is wired by default; a profile must opt in via its own `settings.json`, which is not tracked in this repo — each hook script's header carries its wiring snippet.
`browser-endpoint.sh` is a plain helper instead: it is invoked by path and needs no wiring.
Agents are single `.md` files fetched and tracked by `resource-manager.sh` (see "Skill & agent source management").
- **`plugins.txt` is desired-state only.**
  Installation is manual per-profile; the Makefile only reports drift.
  Lines are `<name>@<marketplace>`; blanks and `#` comments are ignored.
- **Several `.gitignore`'d paths live in the tree but are not checked in.**
  The vendored skill dirs (a managed block in `.gitignore`, one `/skills/<name>/` line each — rewritten by `resource-manager.sh`) are materialized from `sources.toml`, so after a fresh clone they're absent until `make install` (or `make skills-materialize`) reconstructs them.
  `docs/superpowers/` holds local-only design artifacts (brainstorming specs, implementation plans).
  `skills/bin/` holds the `parakeet-cpp-transcribe` binary the `transcribe` skill downloads at runtime — under the symlinked profiles its `../bin` resolves back into the repo, so it's ignored to keep the blob out of git.
  Don't expect any of these to be present after a fresh clone.

## Conventions when editing

- Keep skills atomic, easy to maintain, and reusable/composable.
  Each skill should do one well-scoped thing so it can be invoked on its own or chained with others, rather than bundling several unrelated workflows.
  Prefer extracting shared logic into a script the skill calls over duplicating it across skills, and keep `SKILL.md` focused enough that another skill (or the model) can lean on it without inheriting unrelated behavior.
  When a skill needs another skill, reference it by name as a soft dependency instead of copying its contents.
- Treat vendored skill dirs and `packages/pi/extensions/` as read-only upstream copies — for vendored skills the dir is gitignored and `make skills-materialize`/`skills-update` overwrites it wholesale from the pinned commit, so local edits there are lost with no trace.
  If you genuinely need to diverge from a vendored skill, **reclassify it as authored**: restore the committed dir, strip the `repo`/`subpath`/`ref`/`commit` fields from its `sources.toml` entry (keep `category`, add a `note` recording the fork point), and drop its `.gitignore` line — then it's committed and safe to edit.
  This is a temporary state, not a destination: `itr-india` was forked this way, the divergence was contributed back upstream, and once it merged the skill was re-vendored (`make skills-fetch … FORCE=1` + `git rm -r --cached`) so it tracks a pin again.
  Prefer that round trip over holding a permanent fork.
- The committed record for every resource is its `sources.toml` entry, not the on-disk `.source.json` (a gitignored marker regenerated on materialize); change a resource's source by re-fetching/updating, which rewrites the entry.
  Fetch/update rewrite an entry wholesale, so a hand-added field other than the known ones does not persist.
  Authored resources (no `repo` in their entry) survive `skills-update-all` / `agents-update-all` untouched.
- When adding a new profile, update `CLAUDE_CONFIG_DIRS` (Makefile line 9) — it drives both the CLAUDE.md and skills symlink loops.

## Skill authoring addenda

- Authored skills carry `license: Apache-2.0` in `SKILL.md` frontmatter, matching the repo's top-level `LICENSE` — not MIT.
- Before committing a new or changed skill, run `make skills-scan NAME=<skill>`; fix real findings, and accept a false positive only with a reason in `skills/.security/skillspector/<skill>.json`.
- Before committing any change, run the pre-flight gate: `make preflight` (both doctors — which cover the catalog, suites, and the context budget — plus `bash -n`/`py_compile` over every script) and `make test` (every `scripts/test-*.{sh,py}`).
  The gate is defined once in the Makefile and enforced twice: `.claude/settings.json` wires `scripts/precommit-gate-hook.sh` as a project-scoped `PreToolUse` hook that blocks any `git commit` while `make preflight` fails, and `.github/workflows/checks.yml` runs `make preflight`, `make test`, and the SkillSpector scan on push and PR.

## Dotfiles conventions

- `$HOME` dotfiles are linked per-file by home-manager (`nix/home/*.nix` pointing at `packages/` sources) — the per-file discipline is a security invariant, explained in README.md § "The nix model"; never point `home.file` at a whole directory.
  The harness links (`~/.claude-*`, `~/.pi`, `~/.agents`, `~/.config/devin`, `~/.copilot`) are home-manager out-of-store symlinks (`nix/home/harness.nix`) so the linked content stays mutable; `~/.pi/agent`, `~/.pi/extensions`, and the Devin/Copilot agent dirs link per-file because those tools write state beside them.
- File names in `packages/` use the `dot-` prefix (`dot-zshrc` → `~/.zshrc`), mapped by the `home.file` entries in `nix/home/`.
- Never add packages for credential-bearing dirs or files: `gh/hosts.yml`, `gcloud`, `1Password`, `op`, `github-copilot`, `~/.copilot/config.json`.
- `nix/darwin/homebrew.nix` is the curated brew list (`cleanup = "uninstall"`: an undeclared install is removed on the next switch — promote keepers first); `Brewfile.dump` (gitignored) is regenerated via `make brew-dump` for re-curation diffs only. CLI packages come from nixpkgs via `nix/home/packages.nix`.
- `bootstrap.sh` is the new-Mac entry point; keep it idempotent, check-then-act.
- To add a new tool config, follow the numbered recipe in README.md § "Adding a new tool config"; it is the canonical version.
