# Claude Code Profile Manager - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a cross-platform script system for managing multiple Claude Code configuration profiles via `CLAUDE_CONFIG_DIR`.

**Architecture:** A single POSIX sh script (`claude-profile`) and a Windows cmd batch script (`claude-profile.cmd`) that manage named profile directories under `~/.claude/profiles/` and launch Claude Code with the appropriate `CLAUDE_CONFIG_DIR`. A `.default` file tracks the active default profile.

**Tech Stack:** POSIX sh (no bashisms), Windows cmd batch, PowerShell

**Design doc:** `docs/plans/2026-02-16-claude-profile-manager-design.md`

---

### Task 1: POSIX sh script - core infrastructure and `create` command

**Files:**
- Create: `claude-profile`

**Step 1: Write the script skeleton with constants and helpers**

```sh
#!/bin/sh
set -e

PROFILES_DIR="${HOME}/.claude/profiles"
DEFAULT_FILE="${PROFILES_DIR}/.default"

usage() {
    cat <<'EOF'
Usage: claude-profile [command] [args...]

Commands:
    (no command)            Launch Claude with the default profile
    use <name> [args...]    Launch Claude with the named profile
    create <name>           Create a new profile
    list                    List all profiles
    default [name]          Get or set the default profile
    delete <name>           Delete a profile
    which                   Show the resolved config directory path
    help                    Show this help message

EOF
}

die() {
    printf 'claude-profile: %s\n' "$1" >&2
    exit 1
}
```

**Step 2: Add the `create` subcommand**

```sh
cmd_create() {
    [ -z "$1" ] && die "usage: claude-profile create <name>"
    profile_dir="${PROFILES_DIR}/$1"
    if [ -d "$profile_dir" ]; then
        die "profile '$1' already exists"
    fi
    mkdir -p "$profile_dir"
    printf 'Created profile: %s\n' "$1"
    printf 'Config directory: %s\n' "$profile_dir"
}
```

**Step 3: Add the command dispatcher**

```sh
main() {
    case "${1:-}" in
        create)  shift; cmd_create "$@" ;;
        help|-h|--help) usage ;;
        *)       usage; exit 1 ;;
    esac
}

main "$@"
```

**Step 4: Make executable and verify `create` works**

Run:
```sh
chmod +x claude-profile
./claude-profile create testprofile
ls ~/.claude/profiles/testprofile
```
Expected: directory exists, success message printed.

Run:
```sh
./claude-profile create testprofile
```
Expected: error "profile 'testprofile' already exists"

**Step 5: Clean up test data and commit**

```sh
rm -rf ~/.claude/profiles/testprofile
git add claude-profile
git commit -m "feat: add claude-profile script skeleton with create command"
```

---

### Task 2: `list`, `default`, and `which` commands

**Files:**
- Modify: `claude-profile`

**Step 1: Add the `list` command**

Insert before the `main()` function:

```sh
cmd_list() {
    if [ ! -d "$PROFILES_DIR" ]; then
        printf 'No profiles found. Create one with: claude-profile create <name>\n'
        return
    fi
    default_name=""
    if [ -f "$DEFAULT_FILE" ]; then
        default_name=$(cat "$DEFAULT_FILE")
    fi
    found=0
    for entry in "$PROFILES_DIR"/*/; do
        [ -d "$entry" ] || continue
        name=$(basename "$entry")
        found=1
        if [ "$name" = "$default_name" ]; then
            printf '* %s (default)\n' "$name"
        else
            printf '  %s\n' "$name"
        fi
    done
    if [ "$found" -eq 0 ]; then
        printf 'No profiles found. Create one with: claude-profile create <name>\n'
    fi
}
```

**Step 2: Add the `default` command**

```sh
cmd_default() {
    if [ -z "${1:-}" ]; then
        # Show current default
        if [ -f "$DEFAULT_FILE" ]; then
            cat "$DEFAULT_FILE"
        else
            die "no default profile set. Set one with: claude-profile default <name>"
        fi
        return
    fi
    profile_dir="${PROFILES_DIR}/$1"
    if [ ! -d "$profile_dir" ]; then
        die "profile '$1' does not exist. Create it with: claude-profile create $1"
    fi
    mkdir -p "$PROFILES_DIR"
    printf '%s' "$1" > "$DEFAULT_FILE"
    printf 'Default profile set to: %s\n' "$1"
}
```

**Step 3: Add the `which` command**

```sh
resolve_profile_dir() {
    if [ -n "${1:-}" ]; then
        printf '%s/%s' "$PROFILES_DIR" "$1"
        return
    fi
    if [ ! -f "$DEFAULT_FILE" ]; then
        die "no default profile set. Use: claude-profile default <name>"
    fi
    name=$(cat "$DEFAULT_FILE")
    if [ ! -d "${PROFILES_DIR}/${name}" ]; then
        die "default profile '${name}' does not exist"
    fi
    printf '%s/%s' "$PROFILES_DIR" "$name"
}

cmd_which() {
    dir=$(resolve_profile_dir "${1:-}")
    printf '%s\n' "$dir"
}
```

**Step 4: Update the dispatcher**

```sh
main() {
    case "${1:-}" in
        create)  shift; cmd_create "$@" ;;
        list|ls) shift; cmd_list "$@" ;;
        default) shift; cmd_default "$@" ;;
        which)   shift; cmd_which "$@" ;;
        help|-h|--help) usage ;;
        *)       usage; exit 1 ;;
    esac
}
```

**Step 5: Verify**

Run:
```sh
./claude-profile create alpha
./claude-profile create beta
./claude-profile list
```
Expected:
```
  alpha
  beta
```

Run:
```sh
./claude-profile default alpha
./claude-profile list
```
Expected:
```
* alpha (default)
  beta
```

Run:
```sh
./claude-profile which
./claude-profile which beta
```
Expected: full paths printed.

**Step 6: Clean up and commit**

```sh
rm -rf ~/.claude/profiles/alpha ~/.claude/profiles/beta ~/.claude/profiles/.default
git add claude-profile
git commit -m "feat: add list, default, and which commands"
```

---

### Task 3: `use` command and no-args launcher

**Files:**
- Modify: `claude-profile`

**Step 1: Add the `use` command and default launcher**

```sh
cmd_use() {
    [ -z "${1:-}" ] && die "usage: claude-profile use <name> [claude args...]"
    name="$1"
    shift
    profile_dir="${PROFILES_DIR}/${name}"
    if [ ! -d "$profile_dir" ]; then
        die "profile '${name}' does not exist. Create it with: claude-profile create ${name}"
    fi
    export CLAUDE_CONFIG_DIR="$profile_dir"
    exec claude "$@"
}

cmd_launch_default() {
    dir=$(resolve_profile_dir)
    name=$(cat "$DEFAULT_FILE")
    export CLAUDE_CONFIG_DIR="$dir"
    exec claude "$@"
}
```

**Step 2: Update the dispatcher to handle no-args and passthrough args**

The dispatcher needs to handle:
- No args -> launch default
- First arg is a known subcommand -> dispatch
- First arg looks like a claude flag (starts with `-`) -> launch default with args
- Unknown first arg -> show help

```sh
main() {
    case "${1:-}" in
        "")      cmd_launch_default ;;
        use)     shift; cmd_use "$@" ;;
        create)  shift; cmd_create "$@" ;;
        list|ls) shift; cmd_list "$@" ;;
        default) shift; cmd_default "$@" ;;
        which)   shift; cmd_which "$@" ;;
        delete)  shift; cmd_delete "$@" ;;
        help|-h|--help) usage ;;
        -*)      cmd_launch_default "$@" ;;
        *)       usage; exit 1 ;;
    esac
}
```

**Step 3: Verify**

Run:
```sh
./claude-profile create testlaunch
./claude-profile default testlaunch
CLAUDE_CONFIG_DIR_CHECK=1 ./claude-profile which
```
Expected: prints path. (Full launch test requires `claude` on PATH.)

Run:
```sh
./claude-profile use testlaunch --version
```
Expected: launches `claude --version` with CLAUDE_CONFIG_DIR set (if claude is installed).

**Step 4: Clean up and commit**

```sh
rm -rf ~/.claude/profiles/testlaunch ~/.claude/profiles/.default
git add claude-profile
git commit -m "feat: add use command and default profile launcher"
```

---

### Task 4: `delete` command

**Files:**
- Modify: `claude-profile`

**Step 1: Add the `delete` command**

```sh
cmd_delete() {
    [ -z "${1:-}" ] && die "usage: claude-profile delete <name>"
    name="$1"
    profile_dir="${PROFILES_DIR}/${name}"
    if [ ! -d "$profile_dir" ]; then
        die "profile '${name}' does not exist"
    fi
    printf 'Delete profile "%s" and all its data? [y/N] ' "$name"
    read -r confirm
    case "$confirm" in
        [yY]|[yY][eE][sS])
            rm -rf "$profile_dir"
            # Clear default if it was this profile
            if [ -f "$DEFAULT_FILE" ]; then
                current_default=$(cat "$DEFAULT_FILE")
                if [ "$current_default" = "$name" ]; then
                    rm -f "$DEFAULT_FILE"
                    printf 'Cleared default profile (was "%s")\n' "$name"
                fi
            fi
            printf 'Deleted profile: %s\n' "$name"
            ;;
        *)
            printf 'Cancelled.\n'
            ;;
    esac
}
```

**Step 2: Verify**

Run:
```sh
./claude-profile create deleteme
./claude-profile default deleteme
echo "y" | ./claude-profile delete deleteme
./claude-profile list
./claude-profile default
```
Expected: profile deleted, default cleared, list shows no profiles, default shows error.

**Step 3: Commit**

```sh
git add claude-profile
git commit -m "feat: add delete command with confirmation and default cleanup"
```

---

### Task 5: Windows cmd script

**Files:**
- Create: `claude-profile.cmd`

**Step 1: Write the full Windows cmd script**

The cmd script mirrors all functionality from the sh script using batch syntax.

Key differences from sh:
- Uses `%USERPROFILE%` instead of `$HOME`
- Uses `set` instead of `export`
- Uses `if exist` / `if not exist` instead of `[ -d ]`
- Uses `for /d` instead of shell glob for directory listing
- Uses `type` instead of `cat`
- Uses `goto` labels instead of functions (cmd limitation)

Write the complete `claude-profile.cmd` with all commands: use, create, list, default, delete, which, help.

**Step 2: Verify on Windows or review for correctness**

If on Linux, review the script for cmd syntax correctness. Key things to check:
- `%~dp0` for script directory
- `%USERPROFILE%` for home
- `enabledelayedexpansion` where needed
- Proper `goto :eof` for returns
- `%errorlevel%` checks

**Step 3: Commit**

```sh
git add claude-profile.cmd
git commit -m "feat: add Windows cmd equivalent of claude-profile"
```

---

### Task 5.5: PowerShell script

**Files:**
- Create: `claude-profile.ps1`

**Step 1: Write the full PowerShell script**

The PowerShell script mirrors all functionality from the sh script. PowerShell works on Windows, Linux, and macOS (pwsh).

Key differences from sh:
- Uses `$env:USERPROFILE` (Windows) or `$env:HOME` (Linux/macOS) — detect with `$IsWindows`/`$IsLinux`/`$IsMacOS` or fall back to `[Environment]::GetFolderPath('UserProfile')`
- Uses `$env:CLAUDE_CONFIG_DIR` for env var
- Uses `param()` block and switch statement for subcommand dispatch
- Uses `Test-Path`, `New-Item`, `Remove-Item`, `Get-Content`, `Set-Content`
- Uses `& claude @args` for launching with arg passthrough
- Supports `-Force` flag on delete to skip confirmation

Write the complete `claude-profile.ps1` with all commands: use, create, list, default, delete, which, help.

**Step 2: Verify or review for correctness**

Test basic operations if pwsh is available:
```powershell
pwsh ./claude-profile.ps1 create testps
pwsh ./claude-profile.ps1 list
pwsh ./claude-profile.ps1 default testps
pwsh ./claude-profile.ps1 which
```

**Step 3: Commit**

```sh
git add claude-profile.ps1
git commit -m "feat: add PowerShell equivalent of claude-profile"
```

---

### Task 6: README

**Files:**
- Create: `README.md`

**Step 1: Write README with installation, usage, and examples**

Cover:
- What this is (one paragraph)
- Installation (copy scripts to PATH, or clone and add to PATH)
- Quick start (create profile, set default, launch)
- Full command reference
- How it works (CLAUDE_CONFIG_DIR)
- Platform support notes (sh: Linux/macOS/WSL, cmd: Windows)

**Step 2: Commit**

```sh
git add README.md
git commit -m "docs: add README with installation and usage guide"
```

---

### Task 7: Final verification

**Step 1: Full end-to-end test**

```sh
# Create two profiles
./claude-profile create work
./claude-profile create personal

# List them
./claude-profile list

# Set default
./claude-profile default work
./claude-profile list

# Check which
./claude-profile which
./claude-profile which personal

# Launch with profile (just --version to verify it works)
./claude-profile use work --version
./claude-profile --version  # should use default

# Delete
echo "y" | ./claude-profile delete personal
./claude-profile list

# Clean up
echo "y" | ./claude-profile delete work
```

**Step 2: Clean up test profiles and final commit if needed**

```sh
rm -rf ~/.claude/profiles/.default
```
