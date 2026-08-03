# dotfiles — agent guide

macOS dotfiles provisioned with GNU stow; the Makefile is the interface (no app to build or test).

## Layout

- `packages/` — every stow package, one directory per tool; only files here are ever stowed or committed.
- `Brewfile` — curated package list; `Brewfile.dump` (gitignored) is regenerated via `make brew-dump` for re-curation diffs only.
- `bootstrap.sh` — new-Mac entry point; idempotent, check-then-act steps.
- `macos/defaults.sh` — macOS `defaults` capture (phase 2).
- `scripts/doctor.sh` — health checks behind `make doctor`.

## Conventions

- Stow flags are fixed: `--dotfiles --no-folding` (see Makefile).
  `--no-folding` is a security invariant: `~/.config/<tool>` must stay a real directory so tools that write credentials beside their config (e.g. `gh`'s `hosts.yml`) never write into this repo.
- File names use the `dot-` prefix (`dot-zshrc` → `~/.zshrc`); requires stow ≥ 2.4.0.
- Makefile targets follow `<resource>-<action>` naming (`brew-install`, `stow-link`, `harness-install`), matching the sibling `harness-configs` repo.
- Never add packages for credential-bearing dirs: `gh/hosts.yml`, `gcloud`, `1Password`, `op`, `github-copilot`.
- The sibling repo `~/personal/harness-configs` owns all AI-harness config; this repo only bootstraps it (`make harness-install`) and sources its shell functions from `packages/zsh/dot-config/zsh/50-harness.zsh`.

## Adding a new tool config

1. `mkdir -p packages/<tool>/dot-config/<tool>` and copy the non-secret config file(s) in, using `dot-` names for anything dotted.
2. Add `<tool>` to `PACKAGES` in the Makefile.
3. `make stow-adopt`, then review `git diff` before committing.
