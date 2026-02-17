# shellcheck shell=sh
# claude-profile.sh — Source this in .bashrc / .zshrc
#
#   source "${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile/claude-profile.sh"
#
# Provides:
#   claude           — runs Claude Code with the active/default profile
#   claude-profile   — manage profiles (create, list, delete, default, use, which)

# --- Internal helpers ---

_cp_die() {
    printf 'claude-profile: %s\n' "$1" >&2
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

# --- claude() wrapper ---
# Auto-resolves the default profile before calling the real claude binary.
# If CLAUDE_CONFIG_DIR is already set (e.g. via 'claude-profile use'),
# it passes through without overriding.

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

# --- claude-profile() management function ---

# shellcheck disable=SC3033  # hyphenated function name works in bash/zsh
claude-profile() {
    _cp_data="${XDG_DATA_HOME:-${HOME}/.local/share}/claude-profiles"
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
            if [ -z "${1:-}" ]; then
                _cp_die "usage: claude-profile create <name>"
                return 1
            fi
            _cp_name="$1"
            _cp_validate_name "$_cp_name" || return 1
            _cp_dir="${_cp_data}/${_cp_name}"
            if [ -d "$_cp_dir" ]; then
                _cp_die "profile '${_cp_name}' already exists"
                return 1
            fi
            mkdir -p "$_cp_dir"
            printf 'Created profile: %s\n' "$_cp_name"
            printf 'Config directory: %s\n' "$_cp_dir"
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

        help|-h|--help)
            cat <<'HELPEOF'
Usage: claude-profile [command] [args...]

Commands:
    (no command)            Show current profile status
    use <name>              Switch session to the named profile
    create <name>           Create a new profile
    list, ls                List all profiles
    default [name]          Get or set the default profile
    which [name]            Show the resolved config directory path
    delete <name>           Delete a profile
    help, -h, --help        Show this help message

The claude command automatically uses the default profile. Use
'claude-profile use <name>' to override for the current session.

Examples:
    claude-profile create work
    claude-profile default work
    claude-profile use work
    claude                          # runs with "work" profile
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
