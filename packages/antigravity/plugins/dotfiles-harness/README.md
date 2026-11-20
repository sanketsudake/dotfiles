# Dotfiles AI Harness Plugin

Provides custom subagents, rules, and lifecycle safety hooks for Antigravity, managed by your personal dotfiles repository.

## Components

- **Rules**: Global conventions from `packages/agents/AGENTS.md` (ASD-STE100, sensitive data rules, git hygiene, SemBr, Helium browser).
- **Subagents**: `plan-reviewer`, `bulk-mechanic`, `pr-shepherd`, `skill-auditor`, `thermo-nuclear-review-subagent`, and `thermo-nuclear-code-quality-review-subagent`.
- **Safety Gate**: `PreToolUse` hook enforcing dangerous command blocks and protected path integrity.
