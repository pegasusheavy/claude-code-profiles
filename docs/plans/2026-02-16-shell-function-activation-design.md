# Shell Function Activation Design

**Date:** 2026-02-16
**Status:** Approved

## Problem

`claude-profile use <name>` currently launches Claude Code directly via `exec claude`.
Users want to activate a profile (set `CLAUDE_CONFIG_DIR`) and then invoke `claude`
separately with the regular command. A child process cannot modify its parent shell's
environment, so the current script-based approach cannot set env vars in the user's shell.

## Decision

Single-file shell function, modeled after nvm. The entire tool becomes a shell function
that users source in their shell profile. No separate management script.

## Architecture

```
User's shell (.bashrc/.zshrc / $PROFILE)
│
│  source claude-profile.sh       (POSIX)
│  . claude-profile-init.ps1      (PowerShell)
│  call claude-profile.cmd ...    (cmd — no function, script modified)
│
▼
claude-profile()  ← shell function, ALL commands handled here
│
├── use <name>     → validates name, resolves path
│                    → export CLAUDE_CONFIG_DIR=<resolved path>
│                    → prints "Switched to profile: <name>"
│
├── (bare)         → resolves default profile path
│                    → export CLAUDE_CONFIG_DIR=<resolved path>
│                    → prints "Switched to profile: <name> (default)"
│
├── create <name>  → creates profile directory
├── list / ls      → lists profiles, marks active + default
├── default [name] → get/set default profile
├── which [name]   → print resolved config directory path
├── delete <name>  → interactive delete with confirmation
└── help           → usage text
```

After activation, plain `claude` reads `CLAUDE_CONFIG_DIR` automatically.

## File Changes

### Replaced: `claude-profile` → `claude-profile.sh`

The POSIX sh script is replaced by a POSIX-compatible shell function file.

**Key differences from the old script:**
- Uses `return` (not `exit`) — `exit` would kill the user's shell.
- `die()` becomes a print-only helper; callers do `_cp_die "msg"; return 1`.
- No `set -e` (can't use it in functions sourced into interactive shells).
- No `exec claude` anywhere — `use` and bare invocation set env vars only.
- Same POSIX strictness: no `local`, no `[[ ]]`, no arrays, `printf` over `echo`.
- Same `_cp_` variable prefix convention (was `_rp_`, `_cc_`, etc.).
- `use` rejects extra arguments beyond the profile name (error).
- Same validation rules: `[A-Za-z0-9_-]+`, reject `.`, `/`, `\`, `..`.

### Replaced: `claude-profile.ps1` → `claude-profile-init.ps1`

The PowerShell script is replaced by a function file, dot-sourced in `$PROFILE`.

**Same approach:**
- Defines a `claude-profile` function with all commands.
- `use` and bare invocation set `$env:CLAUDE_CONFIG_DIR`.
- Uses `return` instead of `exit`.
- Same validation and profile resolution logic.

### Modified: `claude-profile.cmd`

cmd cannot source functions. The batch script stays but is modified:

- `cmd_use` and `cmd_launch_default` no longer launch `claude`.
- `cmd_use` sets `CLAUDE_CONFIG_DIR` via `endlocal & set` and prints confirmation.
- Bare invocation activates the default profile (sets env var).
- Flag passthrough (`-*` → launch claude) is removed.
- Users run `call claude-profile.cmd use work` (the `call` prefix is required
  for env var changes to persist in the caller's cmd session).

## Behavioral Changes

| Before | After |
|--------|-------|
| `claude-profile` launches Claude with default profile | `claude-profile` sets CLAUDE_CONFIG_DIR for default profile |
| `claude-profile use work --resume` launches Claude | `claude-profile use work` sets env var; extra args are an error |
| `claude-profile --resume` passes through to Claude | `claude-profile --resume` is an error (unknown command) |
| Script is standalone, no setup needed | Users source the function file in shell profile |
| `use` accepts extra args forwarded to claude | `use` takes exactly one arg (profile name) |

## Install Changes

### `install.sh`

- Downloads `claude-profile.sh` (replaces `claude-profile`).
- Detects user's shell (bash/zsh) and auto-appends source line to profile:
  - bash: `~/.bashrc`
  - zsh: `~/.zshrc`
- Prints instructions to restart shell or `source` the profile.
- If the source line already exists, skips (idempotent).

### `install.ps1`

- Downloads `claude-profile-init.ps1` (replaces `claude-profile.ps1`).
- Auto-appends dot-source line to `$PROFILE`.
- Creates `$PROFILE` if it doesn't exist.
- Prints instructions to restart PowerShell.

### README

- Updated setup instructions for each platform.
- New usage examples showing the activate-then-use workflow.
- Documents `call` prefix requirement for cmd users.
