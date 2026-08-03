# dotfiles — agent guide

macOS dotfiles provisioned with GNU stow; the Makefile is the interface (no app to build or test).

## Layout

- `packages/` — every stow package, one directory per tool; only files here are ever stowed or committed.
- `Brewfile` — curated package list; `Brewfile.dump` (gitignored) is regenerated via `make brew-dump` for re-curation diffs only.
- `bootstrap.sh` — new-Mac entry point; idempotent, check-then-act steps.
- `macos/defaults.sh` — macOS `defaults` capture (phase 2).
- `scripts/doctor.sh` — health checks behind `make doctor`.

## Conventions

- Stow flags are fixed at `--dotfiles --no-folding` and must not be changed; both are security invariants, explained in README.md § "The stow model".
- File names use the `dot-` prefix (`dot-zshrc` → `~/.zshrc`); requires stow ≥ 2.4.0.
- Makefile targets follow `<resource>-<action>` naming (`brew-install`, `stow-link`, `harness-install`), matching the sibling `harness-configs` repo.
- Never add packages for credential-bearing dirs: `gh/hosts.yml`, `gcloud`, `1Password`, `op`, `github-copilot`.
- The sibling repo `~/personal/harness-configs` owns all AI-harness config; this repo only bootstraps it (`make harness-install`) and sources its shell functions from `packages/zsh/dot-config/zsh/50-harness.zsh`.

## Adding a new tool config

Follow the numbered recipe in README.md § "Adding a new tool config"; it is the canonical version.
