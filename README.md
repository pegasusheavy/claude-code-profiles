# claude-profile

Manage multiple [Claude Code](https://code.claude.com) configuration profiles. Switch between work and personal accounts, different MCP server setups, or separate settings without logging in and out.

Each profile is a complete, isolated Claude Code configuration directory (settings, credentials, MCP servers, CLAUDE.md, history -- everything).

## Install

**Linux / macOS / WSL:**

```sh
curl -fsSL https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.sh | sh
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.ps1 | iex
```

The installer downloads the appropriate scripts and adds them to your PATH.

## Quick Start

```sh
# Create profiles
claude-profile create work
claude-profile create personal

# Set a default
claude-profile default work

# Launch Claude with your default profile
claude-profile

# Or launch with a specific profile
claude-profile use personal
```

## Commands

| Command | Description |
|---------|-------------|
| `claude-profile` | Launch Claude with the default profile |
| `claude-profile use <name> [args...]` | Launch Claude with a named profile |
| `claude-profile create <name>` | Create a new profile |
| `claude-profile list` | List all profiles |
| `claude-profile default [name]` | Get or set the default profile |
| `claude-profile delete <name>` | Delete a profile (with confirmation) |
| `claude-profile which [name]` | Show the config directory path |
| `claude-profile help` | Show help |

Arguments after the profile name are passed through to Claude:

```sh
claude-profile use work --resume
claude-profile use work -p "explain this code"
```

Flags without a subcommand are passed to the default profile:

```sh
claude-profile --resume        # uses default profile
claude-profile --version
```

## How It Works

Claude Code supports a `CLAUDE_CONFIG_DIR` environment variable that redirects where it stores configuration and data. `claude-profile` manages named directories and sets this variable before launching Claude.

### Profile Storage

Profiles are stored in platform-appropriate locations:

| Platform | Location |
|----------|----------|
| Linux | `$XDG_DATA_HOME/claude-profiles/` (default: `~/.local/share/claude-profiles/`) |
| macOS | `$XDG_DATA_HOME/claude-profiles/` (default: `~/.local/share/claude-profiles/`) |
| Windows | `%LOCALAPPDATA%\claude-profiles\` |

Each profile directory is a complete Claude Code config directory. After creating a profile and launching Claude with it, Claude will populate it with `settings.json`, `.credentials.json`, and everything else it needs.

### Profile Names

Profile names can contain letters, digits, hyphens, and underscores. Examples: `work`, `personal`, `client-acme`, `side_project`.

## Platform Support

| Script | Platform | Shell |
|--------|----------|-------|
| `claude-profile` | Linux, macOS, WSL | Any POSIX sh |
| `claude-profile.cmd` | Windows | cmd.exe |
| `claude-profile.ps1` | Windows, Linux, macOS | PowerShell 5.1+ / pwsh 6+ |

## Manual Install

If you prefer not to use the install scripts:

**Linux / macOS:**

```sh
# Download
curl -fsSL https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/claude-profile -o ~/.local/bin/claude-profile
chmod +x ~/.local/bin/claude-profile
```

**Windows (PowerShell):**

```powershell
# Download both scripts
$dir = "$env:LOCALAPPDATA\Programs\claude-profile"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/claude-profile.ps1" -OutFile "$dir\claude-profile.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/claude-profile.cmd" -OutFile "$dir\claude-profile.cmd"
# Add to PATH (current user)
$path = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($path -notlike "*$dir*") {
    [Environment]::SetEnvironmentVariable('Path', "$path;$dir", 'User')
}
```

## License

MIT
