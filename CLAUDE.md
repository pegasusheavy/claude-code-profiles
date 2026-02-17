# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Cross-platform shell functions for managing multiple Claude Code configuration profiles via `CLAUDE_CONFIG_DIR`. Each profile is a complete, isolated config directory. A transparent `claude()` wrapper auto-resolves the active profile so users just run `claude` normally.

Three equivalent implementations: POSIX sh (sourced), PowerShell (dot-sourced), and Windows cmd batch.

## Architecture

The POSIX and PowerShell implementations are sourceable function files (not standalone scripts). They each define two functions: `claude()` (transparent wrapper) and `claude-profile()` (management). The cmd batch script is standalone since cmd lacks a function-sourcing mechanism.

- **`claude-profile.sh`** (POSIX sh) — reference implementation. Sourced in `.bashrc`/`.zshrc`. Provides `claude()` wrapper that auto-resolves the default profile before calling the real binary via `command claude`. Provides `claude-profile()` for management commands. Strict POSIX only: no `local`, no `[[ ]]`, no arrays, no bashisms. Uses `printf` over `echo`, `_cp_`-prefixed variables, `return` (not `exit` — runs in user's shell).
- **`claude-profile-init.ps1`** (PowerShell 5.1+/pwsh 6+) — cross-platform. Dot-sourced in `$PROFILE`. Same two-function model. Uses `$args` manual parsing (not `param()`) to avoid conflicts with PowerShell parameter binding. `Get-Command -CommandType Application` to find the real `claude` binary past the function.
- **`claude-profile.cmd`** (Windows batch) — standalone script. Uses `goto :label` dispatch, `setlocal enabledelayedexpansion`, `endlocal & set` idiom to leak `CLAUDE_CONFIG_DIR` to the caller. No transparent `claude` wrapper (cmd limitation). Users run `call claude-profile.cmd use <name>` then `claude` separately.

Profile data lives at `$XDG_DATA_HOME/claude-profiles/` (Linux/macOS, default `~/.local/share/claude-profiles/`) or `%LOCALAPPDATA%\claude-profiles\` (Windows). A `.default` file stores the default profile name as plain text without trailing newline.

The tool itself is installed at `$XDG_DATA_HOME/claude-profile/` (Linux/macOS) or `%LOCALAPPDATA%\claude-profile\` (Windows) — note the singular form, distinct from the plural `claude-profiles/` data directory.

## Command Interface

All three implementations share the same command interface:

| Command | Description |
|---------|-------------|
| `claude-profile` | Show current profile status (active + default) |
| `claude-profile use <name>` | Switch to a profile for the current session |
| `claude-profile create <name>` | Create a new profile |
| `claude-profile list` | List all profiles (marks default and active) |
| `claude-profile default [name]` | Get or set the default profile |
| `claude-profile which [name]` | Show the resolved config directory path |
| `claude-profile delete <name>` | Delete a profile (with confirmation) |
| `claude-profile help` | Show help |

## Validation Rules

Profile names must match `[A-Za-z0-9_-]+`. Reject: empty, starts with `.`, contains `/` or `\` or `..`. This prevents path traversal — all three implementations enforce this identically.

## Checking Scripts

```sh
shellcheck claude-profile.sh         # Lint POSIX sh function file
checkbashisms claude-profile.sh      # Verify no bashisms (hyphenated function name is expected)
```

No build step. No test framework. Manual verification by running commands against real profiles.

## Branching Model

This project uses git-flow. Branch types:

- **`main`** — stable, release-ready. Never commit directly; merge via PR only.
- **`develop`** — integration branch for next release. Feature branches merge here.
- **`feature/*`** — new features and non-trivial changes. Branch from `develop`, merge back to `develop`.
- **`release/*`** — release prep (version bumps, changelog). Branch from `develop`, merge to both `main` and `develop`.
- **`hotfix/*`** — urgent fixes for production. Branch from `main`, merge to both `main` and `develop`.

Use `git worktree` (via `.worktrees/`) for parallel branch work.

## When Modifying

Any behavioral change must be applied to all three implementations (`claude-profile.sh`, `claude-profile.cmd`, `claude-profile-init.ps1`) plus updated in `README.md`. The install scripts (`install.sh`, `install.ps1`) reference `https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/` for download URLs.
