# AGENTS.md

This file provides repository-level guidance to AI coding agents (Antigravity, Devin, Copilot) when working with code in this repository.

## Repository Overview

Personal dotfiles for macOS and Linux (Omarchy):
- Nix-darwin + Home Manager flake (`flake.nix`, `nix/`).
- Dotfile sources live under `packages/` (stow-style `dot-` names, linked per-file by home-manager).
- AI harness configurations live in `packages/` (`claude`, `antigravity`, `devin`, `copilot`, `pi`, `agents`); Codex uses the shared agents rules and skills.
- Curated AI skills live in `skills/` (managed via `make skills-*` and `sources.toml`).
- Tool manifests live under `manifests/`.

## Key Rules & Workflows

1. **Declarative First**: All package, dotfile, and harness configurations are declared in `packages/` and `nix/home/harness.nix`.
2. **Apply System**: Run `make nix-switch` to build and activate changes (dry-run preview: `make nix-build`).
3. **Health Checks**: Always run `make doctor` (or `./scripts/doctor.sh`) and `make preflight` to verify integrity.
4. **Git Discipline**: Never `git add -A` or `git add .`; stage paths explicitly.
5. **No Secrets**: Never commit `.env` or credentials.
6. **Prose**: Write markdown with Semantic Line Breaks (SemBr).
