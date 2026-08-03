# dotfiles

macOS dotfiles managed with GNU stow, a curated Brewfile, and a one-shot bootstrap for new machines.
Pairs with the sibling [harness-configs](https://github.com/sanketsudake/harness-configs) repo, which owns all AI coding-harness config; `make harness-install` clones it and runs its installer.

## New Mac quick start

```sh
curl -fsSL https://raw.githubusercontent.com/sanketsudake/dotfiles/main/bootstrap.sh -o /tmp/bootstrap.sh
bash /tmp/bootstrap.sh
```

The script is idempotent: Xcode CLT and Homebrew if missing, clone to `~/personal/dotfiles`, `brew bundle`, stow links (pre-existing files are moved to a timestamped `~/.dotfiles-backup-*` dir), harness-configs, and `make doctor`.
Afterwards run the printed manual steps (`gh auth login`, `atuin login`, `git lfs install`) and open a new terminal.
On an existing machine, clone the repo and run `make install`.

## Layout

| Path | Purpose |
|---|---|
| `packages/` | Stow packages, one directory per tool; only files here are ever stowed or committed |
| `Brewfile` | Curated brew formulae, casks, App Store apps (mas), and VS Code extensions |
| `manifests/` | Non-brew tools: `go-tools.txt`, `npm-globals.txt`, `pipx-tools.txt` |
| `bootstrap.sh` | New-Mac entry point |
| `macos/defaults.sh` | Deliberately-changed macOS settings, applied via `make macos-apply` |
| `scripts/doctor.sh` | Health checks behind `make doctor` |

## Make targets

| Target | Does |
|---|---|
| `install` | `brew-install` + `stow-link` + `tools-install` + `harness-install` |
| `tools-install` | `go-install` + `npm-install` + `pipx-install` from `manifests/` |
| `cask-adopt` | Take over apps installed outside brew (pkg casks prompt for sudo) |
| `uninstall` | Remove the stow symlinks |
| `brew-install` / `brew-check` | Apply / verify the Brewfile |
| `brew-dump` | Regenerate gitignored `Brewfile.dump` to diff against the curated Brewfile |
| `stow-link` / `stow-unlink` | Create / remove symlinks (idempotent) |
| `stow-adopt` | Absorb pre-existing real files into the working tree; always review `git diff` after |
| `harness-install` | Clone harness-configs if missing, then run its `make install` |
| `macos-apply` | Run `macos/defaults.sh` |
| `doctor` | Run all health checks |
| `drift` | Report divergence between recorded config and the live system, both directions, with the reconcile command per finding |
| `raycast-export` | Open Raycast's encrypted settings export; save the file privately (never committed — `*.rayconfig` is gitignored) |

## The stow model

Packages are stowed from `packages/` into `$HOME` with `--dotfiles --no-folding` (stow ≥ 2.4.0, enforced by `doctor`).
`--dotfiles` maps `dot-zshrc` → `~/.zshrc`, so no hidden files exist in the repo.
`--no-folding` is a security invariant: it links individual files instead of whole directories, so `~/.config/<tool>` stays a real directory and credential files written beside managed configs (e.g. `gh`'s `hosts.yml`) can never land in the repo.
Never add packages for credential-bearing dirs (`gcloud`, `1Password`, `op`, `github-copilot`).

zsh follows the same drop-in idea: `~/.zshrc` is a thin loader sourcing `~/.config/zsh/*.zsh` in `NN-` prefix order, and machine-local uncommitted overrides go in `~/.config/zsh/90-local.zsh` (gitignored; see `90-local.zsh.example`).

## Adding a new tool config

1. `mkdir -p packages/<tool>/dot-config/<tool>` and copy the non-secret config file(s) in, using `dot-` names for anything dotted.
2. Add `<tool>` to `PACKAGES` in the Makefile.
3. `make stow-adopt`, review `git diff`, then commit.

## Secrets policy

Nothing outside `packages/` is ever stowed, and no package references a credential-bearing file.
`.gitignore` blocks secret-like filenames as a second layer, and `make doctor` fails on secret-pattern filenames, credential-looking content in tracked files, or a `~/.config` dir that has become a symlink.
`stow-adopt` imports live machine files into tracked paths, so always review `git diff` before committing after it.
