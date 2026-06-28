# shellcheck shell=sh
# claude-profile.sh — Source this in .bashrc / .zshrc
#
#   source "${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile/claude-profile.sh"
#
# Provides:
#   claude           — runs Claude Code with the active/default profile
#   claude-profile   — manage profiles (create, list, delete, default, use, which)
#
# Supports POSIX shells on Linux, macOS, WSL, and Git Bash / MSYS2 on Windows.
# On Git Bash the data directory is anchored at %LOCALAPPDATA% so profiles are
# shared with the cmd.exe and PowerShell implementations on the same machine.

# --- Internal helpers ---

_cp_die() {
    printf 'claude-profile: %s\n' "$1" >&2
}

# Detects MSYS-family environments (Git Bash, MSYS2, Cygwin shipped with
# MSYSTEM set). Used to decide whether to convert paths via cygpath.
_cp_is_msys() {
    case "${MSYSTEM:-}" in
        MINGW*|MSYS*|UCRT*|CLANG*) return 0 ;;
    esac
    return 1
}

# Resolves the profile data directory. On MSYS-family shells, anchors at
# %LOCALAPPDATA%/claude-profiles (matching the cmd.exe and PowerShell
# implementations) so profiles are shared across shells on the same machine.
# Falls back to $XDG_DATA_HOME/claude-profiles on every other platform.
_cp_data_dir() {
    if _cp_is_msys && [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
        cygpath -u "${LOCALAPPDATA}/claude-profiles"
        return 0
    fi
    printf '%s\n' "${XDG_DATA_HOME:-${HOME}/.local/share}/claude-profiles"
}

_cp_validate_name() {
    case "$1" in
        "")
            _cp_die "profile name must not be empty"
            return 1
            ;;
        .*)
            _cp_die "invalid profile name '$1': must not start with '.'"
            return 1
            ;;
        *..*)
            _cp_die "invalid profile name '$1': must not contain '..'"
            return 1
            ;;
        */*)
            _cp_die "invalid profile name '$1': must not contain '/'"
            return 1
            ;;
        *\\*)
            _cp_die "invalid profile name '$1': must not contain '\\'"
            return 1
            ;;
    esac
    case "$1" in
        *[!A-Za-z0-9_-]*)
            _cp_die "invalid profile name '$1': use only letters, digits, hyphens, underscores"
            return 1
            ;;
    esac
}

# Writes a settings.json skeleton to the path given as $1.
_cp_write_skeleton() {
    cat > "$1" <<'SETTINGSEOF'
{
  "env": {
    "ANTHROPIC_API_KEY": "YOUR_API_KEY_HERE",
    "ANTHROPIC_BASE_URL": "https://YOUR_ENDPOINT_HERE",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "0"
  },
  "model": "claude-sonnet-4-6",
  "advisorModel": "claude-opus-4-8",
  "fallbackModel": ["claude-haiku-4-5"],
  "effortLevel": "high",
  "alwaysThinkingEnabled": false,
  "permissions": {
    "allow": [],
    "deny": []
  },
  "autoMemoryEnabled": true,
  "autoCompactEnabled": true,
  "fileCheckpointingEnabled": true,
  "cleanupPeriodDays": 30,
  "language": "english",
  "editorMode": "normal",
  "preferredNotifChannel": "auto"
}
SETTINGSEOF
}

# Opens path $1 in $VISUAL or $EDITOR, if either is set. Returns 1 with a
# diagnostic if neither is available.
_cp_open_editor() {
    if [ -n "${VISUAL:-}" ]; then
        "${VISUAL}" "$1"
    elif [ -n "${EDITOR:-}" ]; then
        "${EDITOR}" "$1"
    else
        _cp_die "no \$VISUAL or \$EDITOR set; settings file is at: $1"
        return 1
    fi
}

# --- claude() wrapper ---
# Auto-resolves the default profile before calling the real claude binary.
# If CLAUDE_CONFIG_DIR is already set (e.g. via 'claude-profile use'),
# it passes through without overriding.

claude() {
    if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
        _cp_data=$(_cp_data_dir)
        _cp_def="${_cp_data}/.default"
        if [ -f "$_cp_def" ]; then
            _cp_name=$(cat "$_cp_def")
            if [ -n "$_cp_name" ] && [ -d "${_cp_data}/${_cp_name}" ]; then
                export CLAUDE_CONFIG_DIR="${_cp_data}/${_cp_name}"
            fi
        fi
    fi
    # Native claude.exe on Windows expects backslash paths; convert MSYS paths
    # for the subprocess only, leaving the shell-side value untouched so
    # internal commands (list, status) still match against the unix form.
    # Fail loudly if cygpath is missing or conversion fails, because silently
    # passing a /c/Users/... path to claude.exe causes it to create a new
    # config dir at an unexpected location instead of honoring the profile.
    if _cp_is_msys && [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
        if ! command -v cygpath >/dev/null 2>&1; then
            _cp_die "cygpath not found on PATH; required on Git Bash / MSYS2 to convert CLAUDE_CONFIG_DIR for claude.exe"
            return 127
        fi
        _cp_native=$(cygpath -w "$CLAUDE_CONFIG_DIR" 2>/dev/null) || _cp_native=""
        if [ -z "$_cp_native" ]; then
            _cp_die "failed to convert CLAUDE_CONFIG_DIR '$CLAUDE_CONFIG_DIR' to a Windows path via cygpath -w"
            return 1
        fi
        CLAUDE_CONFIG_DIR="$_cp_native" command claude "$@"
        return $?
    fi
    command claude "$@"
}

# --- claude-profile() management function ---

# shellcheck disable=SC3033  # hyphenated function name works in bash/zsh
claude-profile() {
    _cp_data=$(_cp_data_dir)
    _cp_default_file="${_cp_data}/.default"

    case "${1:-}" in
        use)
            shift
            if [ -z "${1:-}" ]; then
                _cp_die "usage: claude-profile use <name>"
                return 1
            fi
            _cp_name="$1"
            shift
            if [ -n "${1:-}" ]; then
                _cp_die "unexpected argument after profile name: '$1'"
                return 1
            fi
            _cp_validate_name "$_cp_name" || return 1
            _cp_dir="${_cp_data}/${_cp_name}"
            if [ ! -d "$_cp_dir" ]; then
                _cp_die "profile '${_cp_name}' does not exist. Create it with: claude-profile create ${_cp_name}"
                return 1
            fi
            export CLAUDE_CONFIG_DIR="$_cp_dir"
            printf 'Switched to profile: %s\n' "$_cp_name"
            ;;

        create)
            shift
            _cp_do_init=0
            _cp_name=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --init) _cp_do_init=1 ;;
                    -*)
                        _cp_die "unknown option '$1'"
                        return 1
                        ;;
                    *)
                        if [ -n "$_cp_name" ]; then
                            _cp_die "unexpected argument '$1'"
                            return 1
                        fi
                        _cp_name="$1"
                        ;;
                esac
                shift
            done
            if [ -z "$_cp_name" ]; then
                _cp_die "usage: claude-profile create [--init] <name>"
                return 1
            fi
            _cp_validate_name "$_cp_name" || return 1
            _cp_dir="${_cp_data}/${_cp_name}"
            if [ -d "$_cp_dir" ]; then
                _cp_die "profile '${_cp_name}' already exists"
                return 1
            fi
            mkdir -p "$_cp_dir"
            printf 'Created profile: %s\n' "$_cp_name"
            printf 'Config directory: %s\n' "$_cp_dir"
            if [ "$_cp_do_init" -eq 1 ]; then
                _cp_settings="${_cp_dir}/settings.json"
                _cp_write_skeleton "$_cp_settings"
                printf 'Config skeleton written to: %s\n' "$_cp_settings"
                printf 'Tip: remove "ANTHROPIC_BASE_URL" if using the default Anthropic endpoint.\n'
                if [ -n "${VISUAL:-}" ] || [ -n "${EDITOR:-}" ]; then
                    _cp_open_editor "$_cp_settings"
                fi
            fi
            ;;

        list|ls)
            if [ ! -d "$_cp_data" ]; then
                printf 'No profiles found. Create one with: claude-profile create <name>\n'
                return 0
            fi
            _cp_cur_default=""
            if [ -f "$_cp_default_file" ]; then
                _cp_cur_default=$(cat "$_cp_default_file")
            fi
            # Derive active profile name from CLAUDE_CONFIG_DIR
            _cp_active=""
            if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
                case "$CLAUDE_CONFIG_DIR" in
                    "${_cp_data}"/*)
                        _cp_active=$(basename "$CLAUDE_CONFIG_DIR")
                        ;;
                esac
            fi
            _cp_found=0
            for _cp_entry in "$_cp_data"/*/; do
                [ -d "$_cp_entry" ] || continue
                _cp_entry_name=$(basename "$_cp_entry")
                _cp_found=1
                _cp_is_default=0
                _cp_is_active=0
                if [ "$_cp_entry_name" = "$_cp_cur_default" ]; then
                    _cp_is_default=1
                fi
                if [ "$_cp_entry_name" = "$_cp_active" ]; then
                    _cp_is_active=1
                fi
                if [ "$_cp_is_default" -eq 1 ] && [ "$_cp_is_active" -eq 1 ]; then
                    printf '>* %s (default, active)\n' "$_cp_entry_name"
                elif [ "$_cp_is_default" -eq 1 ]; then
                    printf ' * %s (default)\n' "$_cp_entry_name"
                elif [ "$_cp_is_active" -eq 1 ]; then
                    printf '>  %s (active)\n' "$_cp_entry_name"
                else
                    printf '   %s\n' "$_cp_entry_name"
                fi
            done
            if [ "$_cp_found" -eq 0 ]; then
                printf 'No profiles found. Create one with: claude-profile create <name>\n'
            fi
            ;;

        default)
            shift
            if [ -z "${1:-}" ]; then
                if [ -f "$_cp_default_file" ]; then
                    _cp_name=$(cat "$_cp_default_file")
                    if [ -n "$_cp_name" ]; then
                        printf '%s\n' "$_cp_name"
                    else
                        _cp_die "default profile file is empty. Set one with: claude-profile default <name>"
                        return 1
                    fi
                else
                    _cp_die "no default profile set. Set one with: claude-profile default <name>"
                    return 1
                fi
                return 0
            fi
            _cp_name="$1"
            _cp_validate_name "$_cp_name" || return 1
            _cp_dir="${_cp_data}/${_cp_name}"
            if [ ! -d "$_cp_dir" ]; then
                _cp_die "profile '${_cp_name}' does not exist. Create it with: claude-profile create ${_cp_name}"
                return 1
            fi
            mkdir -p "$_cp_data"
            printf '%s' "$_cp_name" > "$_cp_default_file"
            printf 'Default profile set to: %s\n' "$_cp_name"
            ;;

        which)
            shift
            if [ -n "${1:-}" ]; then
                _cp_name="$1"
                _cp_validate_name "$_cp_name" || return 1
                _cp_dir="${_cp_data}/${_cp_name}"
                if [ ! -d "$_cp_dir" ]; then
                    _cp_die "profile '${_cp_name}' does not exist. Create it with: claude-profile create ${_cp_name}"
                    return 1
                fi
                printf '%s\n' "$_cp_dir"
            else
                if [ ! -f "$_cp_default_file" ]; then
                    _cp_die "no default profile set. Use: claude-profile default <name>"
                    return 1
                fi
                _cp_name=$(cat "$_cp_default_file")
                if [ -z "$_cp_name" ]; then
                    _cp_die "default profile file is empty. Set one with: claude-profile default <name>"
                    return 1
                fi
                _cp_dir="${_cp_data}/${_cp_name}"
                if [ ! -d "$_cp_dir" ]; then
                    _cp_die "profile '${_cp_name}' does not exist. Create it with: claude-profile create ${_cp_name}"
                    return 1
                fi
                printf '%s\n' "$_cp_dir"
            fi
            ;;

        delete)
            shift
            if [ -z "${1:-}" ]; then
                _cp_die "usage: claude-profile delete <name>"
                return 1
            fi
            _cp_name="$1"
            _cp_validate_name "$_cp_name" || return 1
            _cp_dir="${_cp_data}/${_cp_name}"
            if [ ! -d "$_cp_dir" ]; then
                _cp_die "profile '${_cp_name}' does not exist"
                return 1
            fi
            printf 'Delete profile "%s" and all its data? [y/N] ' "$_cp_name"
            read -r _cp_confirm
            case "$_cp_confirm" in
                [yY]|[yY][eE][sS])
                    rm -rf "$_cp_dir"
                    printf 'Deleted profile: %s\n' "$_cp_name"
                    # Clear default if the deleted profile was the default
                    if [ -f "$_cp_default_file" ]; then
                        _cp_cur_default=$(cat "$_cp_default_file")
                        if [ "$_cp_cur_default" = "$_cp_name" ]; then
                            rm -f "$_cp_default_file"
                            printf 'Cleared default profile (was "%s")\n' "$_cp_name"
                        fi
                    fi
                    # Unset CLAUDE_CONFIG_DIR if the deleted profile was active
                    if [ "${CLAUDE_CONFIG_DIR:-}" = "$_cp_dir" ]; then
                        unset CLAUDE_CONFIG_DIR
                        printf 'Cleared active profile (was "%s")\n' "$_cp_name"
                    fi
                    ;;
                *)
                    printf 'Cancelled.\n'
                    ;;
            esac
            ;;

        rename|mv)
            shift
            _cp_old="${1:-}"
            _cp_new="${2:-}"
            if [ -z "$_cp_old" ] || [ -z "$_cp_new" ]; then
                _cp_die "usage: claude-profile rename <old> <new>"
                return 1
            fi
            if [ -n "${3:-}" ]; then
                _cp_die "unexpected argument: '$3'"
                return 1
            fi
            _cp_validate_name "$_cp_old" || return 1
            _cp_validate_name "$_cp_new" || return 1
            _cp_old_dir="${_cp_data}/${_cp_old}"
            _cp_new_dir="${_cp_data}/${_cp_new}"
            if [ ! -d "$_cp_old_dir" ]; then
                _cp_die "profile '${_cp_old}' does not exist"
                return 1
            fi
            if [ -d "$_cp_new_dir" ]; then
                _cp_die "profile '${_cp_new}' already exists"
                return 1
            fi
            mv "$_cp_old_dir" "$_cp_new_dir" || return 1
            printf 'Renamed profile: %s -> %s\n' "$_cp_old" "$_cp_new"
            # Follow the rename through default and active pointers.
            if [ -f "$_cp_default_file" ]; then
                _cp_cur_default=$(cat "$_cp_default_file")
                if [ "$_cp_cur_default" = "$_cp_old" ]; then
                    printf '%s' "$_cp_new" > "$_cp_default_file"
                    printf 'Updated default profile to: %s\n' "$_cp_new"
                fi
            fi
            if [ "${CLAUDE_CONFIG_DIR:-}" = "$_cp_old_dir" ]; then
                export CLAUDE_CONFIG_DIR="$_cp_new_dir"
                printf 'Updated active profile to: %s\n' "$_cp_new"
            fi
            ;;

        clone|copy|cp)
            shift
            _cp_src="${1:-}"
            _cp_dst="${2:-}"
            if [ -z "$_cp_src" ] || [ -z "$_cp_dst" ]; then
                _cp_die "usage: claude-profile clone <source> <dest>"
                return 1
            fi
            if [ -n "${3:-}" ]; then
                _cp_die "unexpected argument: '$3'"
                return 1
            fi
            _cp_validate_name "$_cp_src" || return 1
            _cp_validate_name "$_cp_dst" || return 1
            _cp_src_dir="${_cp_data}/${_cp_src}"
            _cp_dst_dir="${_cp_data}/${_cp_dst}"
            if [ ! -d "$_cp_src_dir" ]; then
                _cp_die "profile '${_cp_src}' does not exist"
                return 1
            fi
            if [ -d "$_cp_dst_dir" ]; then
                _cp_die "profile '${_cp_dst}' already exists"
                return 1
            fi
            cp -R "$_cp_src_dir" "$_cp_dst_dir" || return 1
            printf 'Cloned profile: %s -> %s\n' "$_cp_src" "$_cp_dst"
            printf 'Config directory: %s\n' "$_cp_dst_dir"
            ;;

        exec|run)
            shift
            _cp_name="${1:-}"
            if [ -z "$_cp_name" ]; then
                _cp_die "usage: claude-profile exec <name> [--] [claude args...]"
                return 1
            fi
            shift
            _cp_validate_name "$_cp_name" || return 1
            _cp_dir="${_cp_data}/${_cp_name}"
            if [ ! -d "$_cp_dir" ]; then
                _cp_die "profile '${_cp_name}' does not exist. Create it with: claude-profile create ${_cp_name}"
                return 1
            fi
            # Allow an optional -- separator before the forwarded claude args.
            if [ "${1:-}" = "--" ]; then
                shift
            fi
            # Run the real binary with the profile set for this one command only;
            # the session environment is left untouched.
            CLAUDE_CONFIG_DIR="$_cp_dir" command claude "$@"
            ;;

        show|cat)
            shift
            _cp_name="${1:-}"
            if [ -z "$_cp_name" ]; then
                if [ ! -f "$_cp_default_file" ]; then
                    _cp_die "usage: claude-profile show <name> (no default profile set)"
                    return 1
                fi
                _cp_name=$(cat "$_cp_default_file")
            fi
            _cp_validate_name "$_cp_name" || return 1
            _cp_dir="${_cp_data}/${_cp_name}"
            if [ ! -d "$_cp_dir" ]; then
                _cp_die "profile '${_cp_name}' does not exist. Create it with: claude-profile create ${_cp_name}"
                return 1
            fi
            _cp_settings="${_cp_dir}/settings.json"
            if [ ! -f "$_cp_settings" ]; then
                _cp_die "profile '${_cp_name}' has no settings.json. Create one with: claude-profile create --init ${_cp_name}"
                return 1
            fi
            cat "$_cp_settings"
            ;;

        edit)
            shift
            _cp_name="${1:-}"
            if [ -z "$_cp_name" ]; then
                if [ ! -f "$_cp_default_file" ]; then
                    _cp_die "usage: claude-profile edit <name> (no default profile set)"
                    return 1
                fi
                _cp_name=$(cat "$_cp_default_file")
            fi
            _cp_validate_name "$_cp_name" || return 1
            _cp_dir="${_cp_data}/${_cp_name}"
            if [ ! -d "$_cp_dir" ]; then
                _cp_die "profile '${_cp_name}' does not exist. Create it with: claude-profile create ${_cp_name}"
                return 1
            fi
            _cp_settings="${_cp_dir}/settings.json"
            if [ ! -f "$_cp_settings" ]; then
                _cp_write_skeleton "$_cp_settings"
                printf 'Created config skeleton: %s\n' "$_cp_settings"
            fi
            _cp_open_editor "$_cp_settings"
            ;;

        help|-h|--help)
            cat <<'HELPEOF'
Usage: claude-profile [command] [args...]

Commands:
    (no command)            Show current profile status
    use <name>              Switch session to the named profile
    create [--init] <name>  Create a new profile (--init writes a settings.json skeleton)
    list, ls                List all profiles
    default [name]          Get or set the default profile
    which [name]            Show the resolved config directory path
    delete <name>           Delete a profile
    rename <old> <new>      Rename a profile (follows default/active pointers)
    clone <src> <dst>       Duplicate a profile, including its config
    exec <name> [--] [args] Run claude with a profile once, without switching
    show [name]             Print a profile's settings.json (default if omitted)
    edit [name]             Open a profile's settings.json in $VISUAL/$EDITOR
    help, -h, --help        Show this help message

The claude command automatically uses the default profile. Use
'claude-profile use <name>' to override for the current session.

Examples:
    claude-profile create --init work
    claude-profile default work
    claude-profile use work
    claude                          # runs with "work" profile
    claude-profile exec personal -- --version
    claude-profile clone work work-experiment
    claude-profile                  # shows active/default status
HELPEOF
            ;;

        "")
            # Bare invocation: show status
            _cp_active=""
            if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
                case "$CLAUDE_CONFIG_DIR" in
                    "${_cp_data}"/*)
                        _cp_active=$(basename "$CLAUDE_CONFIG_DIR")
                        ;;
                esac
            fi
            if [ -n "$_cp_active" ]; then
                printf 'Active profile: %s\n' "$_cp_active"
                printf 'Config directory: %s\n' "$CLAUDE_CONFIG_DIR"
            elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
                printf 'Active config directory: %s (not a managed profile)\n' "$CLAUDE_CONFIG_DIR"
            else
                printf 'No active profile\n'
            fi
            _cp_cur_default=""
            if [ -f "$_cp_default_file" ]; then
                _cp_cur_default=$(cat "$_cp_default_file")
            fi
            if [ -n "$_cp_cur_default" ]; then
                printf 'Default profile: %s\n' "$_cp_cur_default"
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

# --- Completions (bash / zsh) ---
# Registered only on interactive shells that provide programmable completion.
# Lists subcommands at the first argument and profile names for subcommands
# that take one. Fish completions live in claude-profile.fish.

_cp_list_profiles() {
    _cp_comp_data=$(_cp_data_dir)
    [ -d "$_cp_comp_data" ] || return 0
    for _cp_comp_entry in "$_cp_comp_data"/*/; do
        [ -d "$_cp_comp_entry" ] || continue
        basename "$_cp_comp_entry"
    done
}

_cp_complete() {
    # shellcheck disable=SC2034  # COMPREPLY is consumed by the completion system
    _cp_cmds="use create list ls default which delete rename mv clone copy cp exec run show cat edit help"
    if [ "${COMP_CWORD:-0}" -eq 1 ]; then
        COMPREPLY=$(compgen -W "$_cp_cmds" -- "${COMP_WORDS[COMP_CWORD]}")
        # shellcheck disable=SC2206
        COMPREPLY=($COMPREPLY)
        return 0
    fi
    case "${COMP_WORDS[1]}" in
        use|default|which|delete|rename|mv|clone|copy|cp|exec|run|show|cat|edit)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "$(_cp_list_profiles)" -- "${COMP_WORDS[COMP_CWORD]}"))
            ;;
        create)
            # shellcheck disable=SC2207
            COMPREPLY=($(compgen -W "--init" -- "${COMP_WORDS[COMP_CWORD]}"))
            ;;
        *)
            COMPREPLY=()
            ;;
    esac
}

if [ -n "${BASH_VERSION:-}" ]; then
    complete -F _cp_complete claude-profile 2>/dev/null
elif [ -n "${ZSH_VERSION:-}" ]; then
    # Enable bash-style completion in zsh, then register.
    autoload -U +X bashcompinit 2>/dev/null && bashcompinit 2>/dev/null
    complete -F _cp_complete claude-profile 2>/dev/null
fi
