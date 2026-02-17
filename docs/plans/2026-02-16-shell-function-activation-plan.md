# Shell Function Activation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace standalone scripts with sourceable shell functions so `claude` transparently resolves the active/default profile — like nvm for Node versions.

**Architecture:** `claude-profile.sh` provides two shell functions: `claude()` (transparent wrapper that auto-resolves profiles) and `claude-profile()` (management + session override). PowerShell gets equivalent. cmd gets modified script (no transparent wrapper).

**Tech Stack:** POSIX sh, PowerShell 5.1+/pwsh 6+, Windows batch (cmd.exe)

---

### Task 1: Create `claude-profile.sh` (POSIX shell function file)

**Files:**
- Create: `claude-profile.sh`

This is the core deliverable. Replaces the old `claude-profile` script.

**Step 1: Write `claude-profile.sh`**

The file defines two functions: `claude()` and `claude-profile()`.

**`claude()` wrapper** — the key innovation:
- If `CLAUDE_CONFIG_DIR` is already set → skip (session override or already resolved)
- Else if a default profile exists → auto-set `CLAUDE_CONFIG_DIR`
- Call `command claude "$@"` to invoke the real binary

**`claude-profile()` function** — management:
- `use <name>` → validate, resolve, `export CLAUDE_CONFIG_DIR`, print confirmation. Rejects extra args.
- `create <name>` → validate, mkdir, print confirmation
- `list` / `ls` → list profiles, mark `(default)` and `(active)`
- `default [name]` → get or set the persistent default
- `which [name]` → print resolved config directory path
- `delete <name>` → interactive delete, unset CLAUDE_CONFIG_DIR if deleting active
- `help` → usage text
- bare invocation → show status: active profile name, default profile name, CLAUDE_CONFIG_DIR value

**Critical constraints (POSIX, sourced context):**
- All `exit` → `return` (exit kills the user's shell)
- No `set -e` (breaks in sourced functions)
- No `local`, no `[[ ]]`, no arrays, `printf` over `echo`
- `_cp_` variable prefix to minimize namespace pollution
- Helper `_cp_die()` prints error; callers do `_cp_die "msg"; return 1`

```sh
# claude-profile.sh — Source this in .bashrc / .zshrc
#
#   source ~/.claude-profile/claude-profile.sh
#
# Provides:
#   claude           — runs Claude Code with the active/default profile
#   claude-profile   — manage profiles (create, list, delete, default, use, which)

# --- claude wrapper ---
# Transparently resolves the active profile before calling the real claude binary.
# If CLAUDE_CONFIG_DIR is already set (e.g. via "claude-profile use"), it's used as-is.
# Otherwise, the default profile (if any) is auto-activated.

claude() {
    if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
        _cp_data="${XDG_DATA_HOME:-${HOME}/.local/share}/claude-profiles"
        _cp_def="${_cp_data}/.default"
        if [ -f "$_cp_def" ]; then
            _cp_name=$(cat "$_cp_def")
            if [ -n "$_cp_name" ] && [ -d "${_cp_data}/${_cp_name}" ]; then
                export CLAUDE_CONFIG_DIR="${_cp_data}/${_cp_name}"
            fi
        fi
    fi
    command claude "$@"
}

# --- claude-profile function ---
# Profile management and session-level override.

claude-profile() {
    _cp_data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/claude-profiles"
    _cp_default_file="${_cp_data_dir}/.default"

    _cp_die() {
        printf 'claude-profile: %s\n' "$1" >&2
    }

    _cp_usage() {
        cat <<'USAGE'
Usage: claude-profile [command] [args...]

Commands:
    (no command)            Show active profile status
    use <name>              Activate a profile for this session
    create <name>           Create a new profile
    list, ls                List all profiles
    default [name]          Get or set the default profile
    delete <name>           Delete a profile
    which [name]            Show the resolved config directory path
    help, -h, --help        Show this help message

The claude command automatically uses the default profile. Use
'claude-profile use <name>' to override for the current session.

Examples:
    claude-profile create work
    claude-profile default work
    claude                       # automatically uses "work" profile
    claude-profile use personal  # override for this session
    claude                       # uses "personal" until shell closes
USAGE
    }

    _cp_validate_name() {
        case "$1" in
            "")       _cp_die "profile name must not be empty"; return 1 ;;
            ..|.*|*/*|*\\*) _cp_die "invalid profile name '$1': must not contain '/' or '\\' or start with '.'"; return 1 ;;
        esac
        case "$1" in
            *[!A-Za-z0-9_-]*) _cp_die "invalid profile name '$1': use only letters, digits, hyphens, underscores"; return 1 ;;
        esac
    }

    _cp_resolve_profile_dir() {
        if [ -n "${1:-}" ]; then
            _cp_rp_name="$1"
        else
            if [ ! -f "$_cp_default_file" ]; then
                _cp_die "no default profile set. Use: claude-profile default <name>"
                return 1
            fi
            _cp_rp_name=$(cat "$_cp_default_file")
            if [ -z "$_cp_rp_name" ]; then
                _cp_die "default profile file is empty. Set one with: claude-profile default <name>"
                return 1
            fi
        fi
        _cp_rp_dir="${_cp_data_dir}/${_cp_rp_name}"
        if [ ! -d "$_cp_rp_dir" ]; then
            _cp_die "profile '${_cp_rp_name}' does not exist. Create it with: claude-profile create ${_cp_rp_name}"
            return 1
        fi
        printf '%s' "$_cp_rp_dir"
    }

    case "${1:-}" in
        use)
            if [ -z "${2:-}" ]; then
                _cp_die "usage: claude-profile use <name>"
                return 1
            fi
            if [ -n "${3:-}" ]; then
                _cp_die "'use' takes exactly one argument (profile name)"
                return 1
            fi
            _cp_validate_name "$2" || return 1
            _cp_dir=$(_cp_resolve_profile_dir "$2") || return 1
            export CLAUDE_CONFIG_DIR="$_cp_dir"
            printf 'Switched to profile: %s\n' "$2"
            ;;
        create)
            shift
            if [ -z "${1:-}" ]; then
                _cp_die "usage: claude-profile create <name>"
                return 1
            fi
            _cp_validate_name "$1" || return 1
            _cp_cc_dir="${_cp_data_dir}/$1"
            if [ -d "$_cp_cc_dir" ]; then
                _cp_die "profile '$1' already exists"
                return 1
            fi
            mkdir -p "$_cp_cc_dir"
            printf 'Created profile: %s\n' "$1"
            printf 'Config directory: %s\n' "$_cp_cc_dir"
            ;;
        list|ls)
            if [ ! -d "$_cp_data_dir" ]; then
                printf 'No profiles found. Create one with: claude-profile create <name>\n'
                return
            fi
            _cp_cl_default=""
            if [ -f "$_cp_default_file" ]; then
                _cp_cl_default=$(cat "$_cp_default_file")
            fi
            _cp_cl_found=0
            for _cp_cl_entry in "$_cp_data_dir"/*/; do
                [ -d "$_cp_cl_entry" ] || continue
                _cp_cl_name=$(basename "$_cp_cl_entry")
                _cp_cl_found=1
                _cp_is_default=0
                _cp_is_active=0
                [ "$_cp_cl_name" = "$_cp_cl_default" ] && _cp_is_default=1
                [ "${CLAUDE_CONFIG_DIR:-}" = "${_cp_data_dir}/${_cp_cl_name}" ] && _cp_is_active=1
                if [ "$_cp_is_default" -eq 1 ] && [ "$_cp_is_active" -eq 1 ]; then
                    printf '* %s (default, active)\n' "$_cp_cl_name"
                elif [ "$_cp_is_default" -eq 1 ]; then
                    printf '* %s (default)\n' "$_cp_cl_name"
                elif [ "$_cp_is_active" -eq 1 ]; then
                    printf '> %s (active)\n' "$_cp_cl_name"
                else
                    printf '  %s\n' "$_cp_cl_name"
                fi
            done
            if [ "$_cp_cl_found" -eq 0 ]; then
                printf 'No profiles found. Create one with: claude-profile create <name>\n'
            fi
            ;;
        default)
            shift
            if [ -z "${1:-}" ]; then
                if [ -f "$_cp_default_file" ]; then
                    cat "$_cp_default_file"
                    printf '\n'
                else
                    _cp_die "no default profile set. Set one with: claude-profile default <name>"
                    return 1
                fi
                return
            fi
            _cp_validate_name "$1" || return 1
            _cp_cd_dir="${_cp_data_dir}/$1"
            if [ ! -d "$_cp_cd_dir" ]; then
                _cp_die "profile '$1' does not exist. Create it with: claude-profile create $1"
                return 1
            fi
            mkdir -p "$_cp_data_dir"
            printf '%s' "$1" > "$_cp_default_file"
            printf 'Default profile set to: %s\n' "$1"
            ;;
        which)
            shift
            _cp_cw_dir=$(_cp_resolve_profile_dir "${1:-}") || return 1
            printf '%s\n' "$_cp_cw_dir"
            ;;
        delete)
            shift
            if [ -z "${1:-}" ]; then
                _cp_die "usage: claude-profile delete <name>"
                return 1
            fi
            _cp_cdel_name="$1"
            _cp_validate_name "$_cp_cdel_name" || return 1
            _cp_cdel_dir="${_cp_data_dir}/${_cp_cdel_name}"
            if [ ! -d "$_cp_cdel_dir" ]; then
                _cp_die "profile '${_cp_cdel_name}' does not exist"
                return 1
            fi
            printf 'Delete profile "%s" and all its data? [y/N] ' "$_cp_cdel_name"
            read -r _cp_cdel_confirm
            case "$_cp_cdel_confirm" in
                [yY]|[yY][eE][sS])
                    rm -rf "$_cp_cdel_dir"
                    printf 'Deleted profile: %s\n' "$_cp_cdel_name"
                    if [ -f "$_cp_default_file" ]; then
                        _cp_cdel_current=$(cat "$_cp_default_file")
                        if [ "$_cp_cdel_current" = "$_cp_cdel_name" ]; then
                            rm -f "$_cp_default_file"
                            printf 'Cleared default profile (was "%s")\n' "$_cp_cdel_name"
                        fi
                    fi
                    if [ "${CLAUDE_CONFIG_DIR:-}" = "$_cp_cdel_dir" ]; then
                        unset CLAUDE_CONFIG_DIR
                        printf 'Deactivated profile (was active)\n'
                    fi
                    ;;
                *)
                    printf 'Cancelled.\n'
                    ;;
            esac
            ;;
        help|-h|--help)
            _cp_usage
            ;;
        "")
            # Status: show active profile and default
            _cp_status_default=""
            if [ -f "$_cp_default_file" ]; then
                _cp_status_default=$(cat "$_cp_default_file")
            fi
            if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
                _cp_status_active=$(basename "$CLAUDE_CONFIG_DIR")
                printf 'Active profile: %s\n' "$_cp_status_active"
                printf 'Config directory: %s\n' "$CLAUDE_CONFIG_DIR"
            else
                printf 'No active profile\n'
            fi
            if [ -n "$_cp_status_default" ]; then
                printf 'Default profile: %s\n' "$_cp_status_default"
            else
                printf 'No default profile set\n'
            fi
            ;;
        *)
            _cp_die "unknown command '$1'. Run 'claude-profile help' for usage."
            return 1
            ;;
    esac
}
```

**Step 2: Run shellcheck**

Run: `shellcheck claude-profile.sh`
Expected: Clean or only informational notices.

**Step 3: Manual smoke test**

```sh
source claude-profile.sh

# Create and set default
claude-profile create test-smoke
claude-profile default test-smoke

# Test status
claude-profile
# Expected: "No active profile" + "Default profile: test-smoke"

# Test claude wrapper (it will try to run claude binary)
echo $CLAUDE_CONFIG_DIR   # should be empty
type claude               # should show "claude is a function"
# Running 'claude --version' would auto-set CLAUDE_CONFIG_DIR
# (only test if claude is installed)

# Test use
claude-profile use test-smoke
echo $CLAUDE_CONFIG_DIR
# Expected: path ending in /claude-profiles/test-smoke

# Test status again
claude-profile
# Expected: "Active profile: test-smoke" + "Default profile: test-smoke"

# Test use with extra args
claude-profile use test-smoke --resume
# Expected: error about extra args

# Cleanup
claude-profile delete test-smoke
# answer y
```

**Step 4: Commit**

```
git add claude-profile.sh
git commit -m "feat: add claude-profile.sh with transparent claude wrapper

Replace the exec-based launcher with a sourceable shell function file
that provides two functions:

1. claude() — transparent wrapper that auto-resolves the default
   profile before calling the real claude binary. Users just run
   'claude' and it picks up the right config automatically.

2. claude-profile() — profile management (create, list, delete,
   default, which, help) plus session-level override via 'use'.

Modeled after nvm: source once in shell profile, then the wrapped
command transparently handles version/profile resolution.

Key design decisions:
- return instead of exit (runs in user's shell)
- No set -e (breaks in sourced functions)
- _cp_ variable prefix to minimize namespace pollution
- list marks both default and active profiles
- delete unsets CLAUDE_CONFIG_DIR if deleting active profile
- Bare invocation shows status (active + default)"
```

---

### Task 2: Create `claude-profile-init.ps1` (PowerShell function file)

**Files:**
- Create: `claude-profile-init.ps1`

PowerShell equivalent. Provides `claude` and `claude-profile` functions.

**Step 1: Write `claude-profile-init.ps1`**

Same logic, PowerShell idioms. The `claude` function wraps the real binary:

```powershell
# claude-profile-init.ps1 — Dot-source this in your $PROFILE
#
#   . ~/.claude-profile/claude-profile-init.ps1
#
# Provides:
#   claude           — runs Claude Code with the active/default profile
#   claude-profile   — manage profiles

function claude {
    if (-not $env:CLAUDE_CONFIG_DIR) {
        if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) {
            $DataDir = Join-Path $env:LOCALAPPDATA 'claude-profiles'
        } else {
            if ($env:XDG_DATA_HOME) {
                $DataDir = Join-Path $env:XDG_DATA_HOME 'claude-profiles'
            } else {
                $DataDir = Join-Path $HOME '.local' 'share' 'claude-profiles'
            }
        }
        $DefaultFile = Join-Path $DataDir '.default'
        if (Test-Path $DefaultFile) {
            $Name = (Get-Content $DefaultFile -Raw).Trim()
            $ProfilePath = Join-Path $DataDir $Name
            if ($Name -and (Test-Path $ProfilePath -PathType Container)) {
                $env:CLAUDE_CONFIG_DIR = $ProfilePath
            }
        }
    }
    $ClaudePath = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $ClaudePath) {
        $host.UI.WriteErrorLine("claude-profile: 'claude' binary not found in PATH")
        return
    }
    & $ClaudePath @args
}

function claude-profile {
    # ... (full implementation matching POSIX version)
    # Same commands: use, create, list, default, which, delete, help, bare=status
    # Uses return instead of exit
    # Uses $env:CLAUDE_CONFIG_DIR instead of export
}
```

Full `claude-profile` function follows same structure as Task 1's POSIX version, using PowerShell idioms (same as the existing `claude-profile.ps1` but with `return` instead of `exit` and status for bare invocation).

**Step 2: Commit**

```
git add claude-profile-init.ps1
git commit -m "feat: add claude-profile-init.ps1 with transparent claude wrapper

PowerShell equivalent of claude-profile.sh. Provides claude and
claude-profile functions. Users dot-source this in $PROFILE for
transparent profile resolution when running claude."
```

---

### Task 3: Modify `claude-profile.cmd` (remove claude launch)

**Files:**
- Modify: `claude-profile.cmd`

cmd cannot source functions, so no transparent `claude` wrapper. Modify the script so `use` and bare invocation set `CLAUDE_CONFIG_DIR` without launching claude.

**Step 1: Modify `cmd_use` (lines 225-245)**

Remove `claude %1 %2 ...` launch. Keep `endlocal & set "CLAUDE_CONFIG_DIR=..."`. Reject extra args. Print confirmation.

Replace lines 225-245 with:

```batch
:cmd_use
if "%~1"=="" (
    echo claude-profile: usage: claude-profile use ^<name^> >&2
    exit /b 1
)
if not "%~2"=="" (
    echo claude-profile: 'use' takes exactly one argument (profile name^) >&2
    exit /b 1
)
set "_cu_name=%~1"
set "_rp_name=!_cu_name!"
set "_rp_dir=%DATA_DIR%\!_rp_name!"
if not exist "!_rp_dir!\" (
    echo claude-profile: profile '!_rp_name!' does not exist. Create it with: claude-profile create !_rp_name! >&2
    exit /b 1
)
endlocal & set "CLAUDE_CONFIG_DIR=%_rp_dir%"
echo Switched to profile: %~1
exit /b 0
```

**Step 2: Modify `cmd_launch_default` (lines 283-304)**

Remove `claude %*` launch. Set env var, print confirmation.

Replace with:

```batch
:cmd_launch_default
if not exist "%DEFAULT_FILE%" (
    echo claude-profile: no default profile set. Use: claude-profile default ^<name^> >&2
    exit /b 1
)
set /p _rp_name=<"%DEFAULT_FILE%"
if "!_rp_name!"=="" (
    echo claude-profile: default profile file is empty. Set one with: claude-profile default ^<name^> >&2
    exit /b 1
)
set "_rp_dir=%DATA_DIR%\!_rp_name!"
if not exist "!_rp_dir!\" (
    echo claude-profile: profile '!_rp_name!' does not exist. Create it with: claude-profile create !_rp_name! >&2
    exit /b 1
)
endlocal & set "CLAUDE_CONFIG_DIR=%_rp_dir%"
echo Switched to profile: %_rp_name% (default)
exit /b 0
```

**Step 3: Remove flag passthrough (lines 25-28)**

Replace the flag passthrough block with an error:

```batch
set "_first=%~1"
if "!_first:~0,1!"=="-" (
    echo claude-profile: unknown command '%~1'. Run 'claude-profile help' for usage. >&2
    exit /b 1
)
```

**Step 4: Update usage text**

Replace "Launch Claude with..." → "Activate..." throughout. Update examples.

**Step 5: Commit**

```
git add claude-profile.cmd
git commit -m "feat(cmd): set env var instead of launching claude

Modify cmd_use and cmd_launch_default to set CLAUDE_CONFIG_DIR
without launching claude. Users run 'call claude-profile.cmd use
work' then 'claude' separately. Remove flag passthrough. Update
usage text for activation model."
```

---

### Task 4: Update `install.sh`

**Files:**
- Modify: `install.sh`

Download `claude-profile.sh` to `~/.claude-profile/`, auto-append source line to shell profile.

**Step 1: Rewrite install.sh**

Key changes:
- Install target: `~/.claude-profile/claude-profile.sh` (not `~/.local/bin/`)
- Remove `determine_install_dir`, `check_path`, `USE_SUDO`, PATH logic
- Add shell profile detection and auto-append
- Update quick start message

The download, platform detection, and download tool detection stay the same.

New install flow:
1. Detect platform + downloader (unchanged)
2. `mkdir -p ~/.claude-profile`
3. Download `claude-profile.sh` to `~/.claude-profile/`
4. Detect shell (`$SHELL`), find profile file (.bashrc / .zshrc)
5. If source line not present, append it
6. Print success + quick start

**Step 2: Commit**

```
git add install.sh
git commit -m "feat(install): source-based setup with auto shell config

Rewrite installer for the shell function model. Downloads
claude-profile.sh to ~/.claude-profile/ and auto-appends the source
line to .bashrc or .zshrc. Removes PATH-based installation since
the file is sourced, not executed.

Idempotent: skips if source line already present."
```

---

### Task 5: Update `install.ps1`

**Files:**
- Modify: `install.ps1`

Download `claude-profile-init.ps1` and `claude-profile.cmd`, auto-append dot-source to `$PROFILE`.

**Step 1: Rewrite install.ps1**

Key changes:
- Download `claude-profile-init.ps1` (not `claude-profile.ps1`)
- Keep `claude-profile.cmd` download
- Auto-append dot-source line to `$PROFILE`
- Create `$PROFILE` if it doesn't exist
- Update quick start message

**Step 2: Commit**

```
git add install.ps1
git commit -m "feat(install): PowerShell source-based setup

Download claude-profile-init.ps1 and claude-profile.cmd. Auto-append
dot-source line to $PROFILE. Create profile file if needed.
Idempotent: skips if already present."
```

---

### Task 6: Remove old script files

**Files:**
- Delete: `claude-profile` (replaced by `claude-profile.sh`)
- Delete: `claude-profile.ps1` (replaced by `claude-profile-init.ps1`)

**Step 1: Remove files**

```sh
git rm claude-profile claude-profile.ps1
```

**Step 2: Commit**

```
git rm claude-profile claude-profile.ps1
git commit -m "chore: remove old standalone launcher scripts

Replaced by claude-profile.sh and claude-profile-init.ps1 which are
sourceable function files. The old scripts used exec to launch claude
directly; the new functions set CLAUDE_CONFIG_DIR and let the user
invoke claude separately."
```

---

### Task 7: Update README.md

**Files:**
- Modify: `README.md`

Complete rewrite to document the new transparent wrapper model.

**Step 1: Rewrite README.md**

Key sections:
- Header: same intro but mention transparent profile resolution
- Install: same one-liner but note about shell restart
- Quick Start: create, default, then just `claude`
- Commands: updated table (no "Launch", add "Show status")
- How It Works: explain the `claude()` wrapper + `CLAUDE_CONFIG_DIR`
- Session Override: document `claude-profile use`
- Profile Storage: same
- Platform Support: updated filenames
- Manual Install: updated for new files + source line

**Step 2: Commit**

```
git add README.md
git commit -m "docs: rewrite README for transparent profile resolution

Document the new workflow: install, create a profile, set default,
then just run 'claude'. The claude wrapper auto-resolves the profile.
Remove launch-based examples and arg passthrough docs. Add session
override and status command documentation."
```

---

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update CLAUDE.md**

Key changes:
- Architecture: update filenames, describe function model
- `claude-profile.sh` — reference implementation. Strict POSIX. Provides `claude()` wrapper and `claude-profile()` management function. Sourced, not executed.
- `claude-profile-init.ps1` — PowerShell equivalent. Dot-sourced.
- `claude-profile.cmd` — modified: sets env var without launching claude
- Update command interface: remove "Launch", add "Show status"
- Update "Checking Scripts" for new filename
- Update "When Modifying": list new filenames

**Step 2: Commit**

```
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for function-based architecture

Reflect new file names and transparent wrapper model. The scripts
are now sourced function files, not standalone executables. Update
architecture notes, command descriptions, and modification guidelines."
```
