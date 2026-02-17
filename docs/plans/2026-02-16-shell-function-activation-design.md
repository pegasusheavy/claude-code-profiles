# Shell Function Activation Design

**Date:** 2026-02-16
**Status:** Approved (v2)

## Problem

`claude-profile use <name>` currently launches Claude Code directly via `exec claude`.
Users want to just run `claude` and have it automatically use the right profile — like
how `nvm` and `pyenv` transparently resolve the right version of `node` or `python`.

## Decision

Single-file shell function modeled after nvm. The file provides two functions:

1. **`claude()`** — transparent wrapper that auto-resolves the default profile and
   calls the real `claude` binary. Users never need to explicitly activate a profile.

2. **`claude-profile()`** — profile management (create, list, delete, default, which,
   help) plus optional session-level override via `use`.

## Architecture

```
User's shell (.bashrc/.zshrc / $PROFILE)
│
│  source claude-profile.sh       (POSIX)
│  . claude-profile-init.ps1      (PowerShell)
│
▼
claude()  ← transparent wrapper
│
├── CLAUDE_CONFIG_DIR already set?  → call real claude
│
└── not set, default profile exists?
    → export CLAUDE_CONFIG_DIR=<default profile path>
    → call real claude

claude-profile()  ← management + session override
│
├── (bare)         → show status (active profile, default, path)
├── use <name>     → set CLAUDE_CONFIG_DIR for this session
├── create <name>  → create profile directory
├── list / ls      → list profiles (marks default + active)
├── default [name] → get/set persistent default profile
├── which [name]   → print resolved config directory path
├── delete <name>  → interactive delete with confirmation
└── help           → usage text
```

## User Experience

```sh
# One-time setup
claude-profile create work
claude-profile default work

# Daily use — just run claude
claude                        # automatically uses "work" profile
claude --resume               # all args pass through transparently
claude -p "explain this"      # works exactly like normal

# Optional: temporary session override
claude-profile use personal   # sets CLAUDE_CONFIG_DIR for this shell
claude                        # uses "personal" until shell closes

# Check what's active
claude-profile                # shows status
```

## File Changes

### Replaced: `claude-profile` → `claude-profile.sh`

POSIX-compatible shell function file providing `claude()` and `claude-profile()`.

- Uses `return` (not `exit`) throughout
- No `set -e` (breaks sourced functions)
- `_cp_` variable prefix to minimize namespace pollution
- `claude()` wrapper: if CLAUDE_CONFIG_DIR unset, auto-resolve default, call real claude
- `claude-profile use` sets CLAUDE_CONFIG_DIR for session override
- Bare `claude-profile` shows status (active profile, default profile, config path)
- Same validation: `[A-Za-z0-9_-]+`, reject `.`, `/`, `\`, `..`

### Replaced: `claude-profile.ps1` → `claude-profile-init.ps1`

PowerShell function file providing same two functions.

### Modified: `claude-profile.cmd`

cmd cannot source functions. Script modified so:
- `cmd_use` / bare invocation set CLAUDE_CONFIG_DIR without launching claude
- Users run `call claude-profile.cmd use work` then `claude`
- cmd users don't get the transparent `claude` wrapper

## Behavioral Changes

| Before | After |
|--------|-------|
| `claude-profile` launches Claude with default profile | `claude-profile` shows status |
| `claude-profile use work --resume` launches Claude | `claude-profile use work` sets env var; extra args are an error |
| `claude` ignores profiles entirely | `claude` auto-resolves default profile transparently |
| Must remember to activate profile each session | Just run `claude`, it figures it out |

## Install Changes

- `install.sh`: downloads to `~/.claude-profile/`, auto-appends source line to .bashrc/.zshrc
- `install.ps1`: downloads, auto-appends dot-source to $PROFILE
- Both are idempotent (skip if source line exists)
