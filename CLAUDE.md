# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Cross-platform scripts for managing multiple Claude Code configuration profiles via `CLAUDE_CONFIG_DIR`. Each profile is a complete, isolated config directory. Three equivalent implementations: POSIX sh, Windows cmd batch, and PowerShell.

## Architecture

All three scripts implement the same command interface (`create`, `list`, `default`, `which`, `use`, `delete`, `help`) with platform-appropriate idioms:

- **`claude-profile`** (POSIX sh) — reference implementation. Strict POSIX only: no `local`, no `[[ ]]`, no arrays, no bashisms. Uses `printf` over `echo`, underscore-prefixed variables (`_rp_name`) instead of `local`, `exec claude "$@"` to replace the process.
- **`claude-profile.cmd`** (Windows batch) — uses `goto :label` dispatch, `setlocal enabledelayedexpansion`, `endlocal & set` idiom to pass variables across scope boundaries. Known limitation: `cmd_use` can only pass 9 args to claude after `shift`.
- **`claude-profile.ps1`** (PowerShell 5.1+/pwsh 6+) — cross-platform. Uses `$args` manual parsing (not `param()`) to avoid conflicts with PowerShell parameter binding. Splatting (`@RemainingArgs`) for arg passthrough. `exit $LASTEXITCODE` instead of `exec`.

Profile data lives at `$XDG_DATA_HOME/claude-profiles/` (Linux/macOS, default `~/.local/share/claude-profiles/`) or `%LOCALAPPDATA%\claude-profiles\` (Windows). A `.default` file stores the default profile name as plain text without trailing newline.

## Validation Rules

Profile names must match `[A-Za-z0-9_-]+`. Reject: empty, starts with `.`, contains `/` or `\` or `..`. This prevents path traversal — all three scripts enforce this identically.

## Checking Scripts

```sh
shellcheck claude-profile            # Lint POSIX sh script
checkbashisms claude-profile         # Verify no bashisms
```

No build step. No test framework. Manual verification by running commands against real profiles.

## When Modifying

Any behavioral change must be applied to all three scripts (`claude-profile`, `claude-profile.cmd`, `claude-profile.ps1`) plus updated in `README.md`. The install scripts (`install.sh`, `install.ps1`) reference `https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/` for download URLs.
