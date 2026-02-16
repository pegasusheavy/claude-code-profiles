# Claude Code Profile Manager - Design

## Problem

Claude Code stores all configuration in `~/.claude/`. Users with multiple accounts (work vs personal) must `claude logout` / `claude login` repeatedly. The `CLAUDE_CONFIG_DIR` env var exists but requires manual management.

## Solution

Cross-platform scripts (`claude-profile` for POSIX sh, `claude-profile.cmd` for Windows cmd, `claude-profile.ps1` for PowerShell) that manage named profile directories and launch Claude Code with the appropriate `CLAUDE_CONFIG_DIR`.

## Profile Storage

```
~/.claude/profiles/
  .default                 # Plain text: name of the default profile
  work/                    # Complete Claude config directory
  personal/                # Complete Claude config directory
```

Each profile directory is a full, independent Claude Code config directory (settings, credentials, MCP servers, CLAUDE.md, history, caches - everything).

## Commands

| Command | Description |
|---------|-------------|
| `claude-profile` | Launch Claude with the default profile |
| `claude-profile use <name> [args...]` | Launch Claude with named profile, passing extra args |
| `claude-profile create <name>` | Create empty profile directory |
| `claude-profile list` | List profiles, marking the default with `*` |
| `claude-profile default` | Show current default profile |
| `claude-profile default <name>` | Set default profile |
| `claude-profile delete <name>` | Delete a profile (with confirmation) |
| `claude-profile which` | Show resolved config dir path |

## Mechanism

1. `claude-profile use work` sets `CLAUDE_CONFIG_DIR=$HOME/.claude/profiles/work` and execs `claude` with remaining args
2. `claude-profile` (no args) reads `.default` file, resolves profile name, does the same
3. `create` runs `mkdir -p` on the profile directory
4. Windows `.cmd` uses `set` and batch equivalents
5. PowerShell `.ps1` uses `$env:CLAUDE_CONFIG_DIR` and works cross-platform

## Edge Cases

- No default set: error with guidance to set one
- Profile doesn't exist: error with suggestion to create
- Deleting the default profile: clears the default
- `claude` not found: error message

## Files

```
claude-code-profiles/
  claude-profile           # POSIX sh script (Linux/macOS/WSL)
  claude-profile.cmd       # Windows cmd batch script
  claude-profile.ps1       # PowerShell script (cross-platform)
  README.md                # Usage documentation
```

## Design Decisions

- **Full directory isolation**: each profile is a complete `~/.claude` equivalent, avoiding partial-swap complexity and the known credential isolation bugs
- **Direct launcher**: `claude-profile use <name>` directly launches Claude, no session-level env setup needed
- **Configurable default**: a `.default` file stores the default profile name; running without args uses it
- **Single script per platform**: one `.sh`, one `.cmd`, and one `.ps1` file for easy sharing
- **Stored inside `~/.claude/`**: profiles live at `~/.claude/profiles/` to keep everything together
