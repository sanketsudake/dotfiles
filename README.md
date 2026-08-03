# dotfiles

macOS dotfiles managed with GNU stow, a curated Brewfile, and a one-shot bootstrap for new machines.
Pairs with the sibling [harness-configs](https://github.com/sanketsudake/harness-configs) repo, which owns all AI coding-harness config.

## New Mac quick start

```sh
curl -fsSL https://raw.githubusercontent.com/sanketsudake/dotfiles/master/bootstrap.sh -o /tmp/bootstrap.sh
bash /tmp/bootstrap.sh
```

Download-then-run (rather than `curl | bash`) matters: casks can prompt for sudo, and a piped bash shares stdin with the script.
The script is idempotent: it installs Xcode CLT and Homebrew if missing, clones this repo to `~/personal/dotfiles`, runs `brew bundle`, moves any pre-existing real files at managed paths to a timestamped `~/.dotfiles-backup-*` dir, stows the packages, clones and installs harness-configs as a sibling, and finishes with `make doctor`.
Afterwards run the printed manual steps (`gh auth login`, `atuin login`, `git lfs install`, and for work remotes the `gh-qwiet` SSH host alias in `~/.ssh/config`) and open a new terminal.

On an existing machine, clone the repo and run `make install`.

## Layout

| Path | Purpose |
|---|---|
| `packages/` | Stow packages, one directory per tool; only files here are ever stowed or committed |
| `Brewfile` | Curated brew formulae, casks, and VS Code extensions |
| `bootstrap.sh` | New-Mac entry point |
| `macos/defaults.sh` | macOS `defaults` capture (phase 2, empty placeholder) |
| `scripts/doctor.sh` | Health checks behind `make doctor` |

## Make targets

| Target | Does |
|---|---|
| `install` | `brew-install` + `stow-link` + `harness-install` |
| `uninstall` | Remove the stow symlinks |
| `brew-install` / `brew-check` | Apply / verify the Brewfile |
| `brew-dump` | Regenerate `Brewfile.dump` (gitignored) to diff against the curated Brewfile |
| `stow-link` / `stow-unlink` | Create / remove symlinks (`--restow` makes link idempotent) |
| `stow-adopt` | Absorb pre-existing real files into the working tree; always review `git diff` after |
| `harness-install` | Clone harness-configs if missing, then run its `make install` |
| `macos-apply` | Run `macos/defaults.sh` |
| `doctor` | Run all health checks |

## The stow model

Packages live under `packages/` and are stowed with `--dotfiles --no-folding` into `$HOME`.
`--dotfiles` maps `dot-zshrc` → `~/.zshrc`, so no hidden files exist in the repo (requires stow ≥ 2.4.0, enforced by `doctor`).
`--no-folding` is a security invariant, not a style choice: it links individual files instead of whole directories, so `~/.config/<tool>` stays a real directory.
That is what keeps `gh`'s `hosts.yml` (OAuth tokens) a plain local file that can never land in the repo — only `config.yml` is managed.
Never add packages for credential-bearing dirs (`gcloud`, `1Password`, `op`, `github-copilot`).

## zsh structure

`~/.zshrc` is a thin loader that sources `~/.config/zsh/*.zsh` in `NN-` prefix order.
Adding shell config means dropping a new numbered file into `packages/zsh/dot-config/zsh/` — no editing of `.zshrc` itself.
`~/.zprofile` only sets up `brew shellenv` (guarded for Apple Silicon and Intel paths).
Machine-local, uncommitted overrides go in `~/.config/zsh/90-local.zsh` (gitignored; see `90-local.zsh.example`).

## Multi-identity git

`packages/git/dot-gitconfig` selects identity by remote URL via `includeIf "hasconfig:remote.*.url:..."` blocks.
Personal repos get `~/.config/git/config-personal` (gmail); ShiftLeftSecurity/Harness remotes get `~/.config/git/config-qwiet`.
The work email in `config-qwiet` is an identity, not a credential, and is committed intentionally.
ShiftLeftSecurity remotes are additionally rewritten through a `gh-qwiet` SSH host alias, which must exist in `~/.ssh/config` (kept out of this repo; see the bootstrap manual steps).

## harness-configs integration

The two repos are siblings: this repo lives at `~/personal/dotfiles`, harness-configs at `~/personal/harness-configs` (override with `HARNESS_DIR=`).
`make harness-install` clones it if missing and runs its idempotent `make install`.
`packages/zsh/dot-config/zsh/50-harness.zsh` sources its `claude-multi-account.sh`, so the `pclaude`/`wclaude` wrappers exist in every interactive shell with no manual profile editing.
The Brewfile carries its prerequisites (`stow`, `jq`, `gh`, `nvm` for node/npx, `python@3.13`).

## Adding a new tool config

1. `mkdir -p packages/<tool>/dot-config/<tool>` and copy the non-secret config file(s) in, using `dot-` names for anything dotted.
2. Add `<tool>` to `PACKAGES` in the Makefile.
3. `make stow-adopt`, review `git diff`, then commit.

## Secrets policy

Nothing outside `packages/` is ever stowed, and no package references a credential-bearing file.
`.gitignore` blocks `hosts.yml`, `.env*`, keys, and token-like names as a second layer (note it cannot protect already-tracked paths).
`make doctor` fails if any tracked filename matches a secret pattern, if tracked file content looks credential-like (token/key/password assignments, private-key blocks), or if a `~/.config` dir has become a symlink.
After `make stow-adopt`, always review `git diff` before committing — adopt imports live machine files into tracked paths, which is exactly how a stray exported token could enter the repo.
Review `git diff --cached` before every commit regardless.

## macOS defaults (phase 2)

`macos/defaults.sh` is the landing spot for `defaults write` capture (Dock, Finder, keyboard, trackpad, screenshots), applied via `make macos-apply`.
It is currently an intentional no-op.
