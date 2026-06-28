# claude-profile

Manage multiple [Claude Code](https://code.claude.com) configuration profiles. Switch between work and personal accounts, different MCP server setups, or separate settings without logging in and out.

Each profile is a complete, isolated Claude Code configuration directory (settings, credentials, MCP servers, CLAUDE.md, history -- everything). Once configured, `claude` automatically uses your active profile -- no special launch command needed.

## Install

**Linux / macOS / WSL / Git Bash (MSYS2):**

```sh
curl -fsSL https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.sh | sh
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.ps1 | iex
```

The installer downloads the appropriate scripts and configures your shell. **Restart your shell** (or open a new terminal) after installing.

## Quick Start

```sh
# Create profiles
claude-profile create work
claude-profile create personal

# Set a default
claude-profile default work

# Just use claude — it automatically uses your default profile
claude
claude --resume
claude -p "explain this code"
```

## Commands

| Command | Description |
|---------|-------------|
| `claude-profile` | Show current profile status |
| `claude-profile use <name>` | Switch to a profile for this session |
| `claude-profile create <name>` | Create a new profile |
| `claude-profile list` | List all profiles |
| `claude-profile default [name]` | Get or set the default profile |
| `claude-profile delete <name>` | Delete a profile (with confirmation) |
| `claude-profile which [name]` | Show the config directory path |
| `claude-profile rename <old> <new>` | Rename a profile (follows default/active pointers) |
| `claude-profile clone <src> <dst>` | Duplicate a profile, including its config |
| `claude-profile exec <name> [--] [args]` | Run `claude` with a profile once, without switching |
| `claude-profile show [name]` | Print a profile's `settings.json` (default profile if omitted) |
| `claude-profile edit [name]` | Open a profile's `settings.json` in `$VISUAL`/`$EDITOR` |
| `claude-profile help` | Show help |

Tab-completion of subcommands and profile names is available in bash, zsh, and fish.

## How It Works

Claude Code supports a `CLAUDE_CONFIG_DIR` environment variable that redirects where it stores configuration and data. `claude-profile` provides a `claude()` shell function that wraps the real `claude` binary:

1. Before each invocation, the wrapper checks if a default profile exists and auto-sets `CLAUDE_CONFIG_DIR`.
2. If `CLAUDE_CONFIG_DIR` is already set (e.g., via `claude-profile use`), it is used as-is.
3. The real `claude` binary is then called with all your arguments.

This means you never need to think about profiles during normal use -- just run `claude` as you always have.

### Session Override

To temporarily use a different profile in the current shell session:

```sh
# Temporarily use a different profile
claude-profile use personal
claude                          # uses "personal" for this shell session
```

The override lasts until you close the shell or run `claude-profile use` again.

### Profile Storage

Profiles are stored in platform-appropriate locations:

| Platform | Location |
|----------|----------|
| Linux | `$XDG_DATA_HOME/claude-profiles/` (default: `~/.local/share/claude-profiles/`) |
| macOS | `$XDG_DATA_HOME/claude-profiles/` (default: `~/.local/share/claude-profiles/`) |
| Windows | `%LOCALAPPDATA%\claude-profiles\` |
| Git Bash / MSYS2 | `%LOCALAPPDATA%\claude-profiles\` (shared with cmd/PowerShell) |

Each profile directory is a complete Claude Code config directory. After creating a profile and launching Claude with it, Claude will populate it with `settings.json`, `.credentials.json`, and everything else it needs.

### Profile Names

Profile names can contain letters, digits, hyphens, and underscores. Examples: `work`, `personal`, `client-acme`, `side_project`.

## Platform Support

| Script | Platform | Shell |
|--------|----------|-------|
| `claude-profile.sh` | Linux, macOS, WSL, Git Bash / MSYS2 | bash, zsh (sourced) |
| `claude-profile.fish` | Linux, macOS, WSL | fish (sourced) |
| `claude-profile-init.ps1` | Windows, Linux, macOS | PowerShell 5.1+ / pwsh 6+ (dot-sourced) |
| `claude-profile.cmd` | Windows | cmd.exe (use with `call` prefix) |

### fish Support

fish is not POSIX-compatible, so it cannot source `claude-profile.sh`. `claude-profile.fish` is a native fish port with the same commands and the same on-disk profile layout, so profiles created from bash/zsh are visible in fish and vice versa. The installer detects fish and sources the fish version from `config.fish` automatically. (Git Bash / MSYS2 path handling is bash/zsh-only; fish is not available on those platforms.)

### Git Bash / MSYS2 Support

On Git Bash and other MSYS2-based shells on Windows, `claude-profile.sh` automatically detects the environment and:

- Stores profiles at `%LOCALAPPDATA%\claude-profiles\` (shared with cmd.exe and PowerShell implementations)
- Converts Unix-style paths to Windows-native paths via `cygpath -w` before passing them to the native `claude.exe` binary
- Uses the `MSYSTEM` environment variable for detection (`MINGW64`, `MINGW32`, `MSYS`, etc.)

This means Git Bash users share the same profile data with cmd.exe and PowerShell on the same machine — no duplication or conflicts.

## Manual Install

If you prefer not to use the install scripts:

**Linux / macOS:**

```sh
# Download
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile"
curl -fsSL https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/claude-profile.sh \
  -o "${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile/claude-profile.sh"

# Add to shell profile (.bashrc or .zshrc)
echo '. "${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile/claude-profile.sh"' >> ~/.bashrc
```

**fish:**

```fish
# Download
mkdir -p "$HOME/.local/share/claude-profile"
curl -fsSL https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/claude-profile.fish \
  -o "$HOME/.local/share/claude-profile/claude-profile.fish"

# Add to fish config
echo 'source "$HOME/.local/share/claude-profile/claude-profile.fish"' >> ~/.config/fish/config.fish
```

**Windows (PowerShell):**

```powershell
$dir = "$env:LOCALAPPDATA\claude-profile"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/claude-profile-init.ps1" -OutFile "$dir\claude-profile-init.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/claude-profile.cmd" -OutFile "$dir\claude-profile.cmd"
# Add to PowerShell profile
Add-Content -Path $PROFILE -Value ". '$dir\claude-profile-init.ps1'"
# Add to PATH for cmd.exe
$path = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($path -notlike "*$dir*") { [Environment]::SetEnvironmentVariable('Path', "$path;$dir", 'User') }
```

## License

MIT
