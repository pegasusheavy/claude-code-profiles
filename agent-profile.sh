# agent-profile.sh — source this in .bashrc / .zshrc
#
# Provides provider-neutral profile management for Antigravity (agy + GUI)
# and Codex. The existing claude-profile.sh remains the Claude adapter.

_ap_die() {
    printf 'agent-profile: %s\n' "$1" >&2
}

_ap_is_msys() {
    case "${MSYSTEM:-}" in
        MINGW*|MSYS*|UCRT*|CLANG*) return 0 ;;
    esac
    return 1
}

_ap_data_dir() {
    if [ -n "${AGENT_PROFILE_DATA_DIR:-}" ]; then
        printf '%s\n' "$AGENT_PROFILE_DATA_DIR"
        return 0
    fi
    if _ap_is_msys && [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
        cygpath -u "${LOCALAPPDATA}/agent-profiles"
        return 0
    fi
    printf '%s\n' "${XDG_DATA_HOME:-${HOME}/.local/share}/agent-profiles"
}

_ap_validate_name() {
    case "$1" in
        "") _ap_die "profile name must not be empty"; return 1 ;;
        .*) _ap_die "invalid profile name '$1': must not start with '.'"; return 1 ;;
        *..*) _ap_die "invalid profile name '$1': must not contain '..'"; return 1 ;;
        */*) _ap_die "invalid profile name '$1': must not contain '/'"; return 1 ;;
        *\*) _ap_die "invalid profile name '$1': must not contain '\\'"; return 1 ;;
        *[!A-Za-z0-9_-]*) _ap_die "invalid profile name '$1': use only letters, digits, hyphens, underscores"; return 1 ;;
    esac
    return 0
}

_ap_provider() {
    case "$1" in
        agy|antigravity|antigravity-cli|antigravity-gui|antigravity-ide)
            printf 'antigravity\n'
            ;;
        codex)
            printf 'codex\n'
            ;;
        *)
            _ap_die "unknown provider '$1' (use antigravity or codex)"
            return 1
            ;;
    esac
}

_ap_provider_dir() {
    _ap_provider_dir_value="$(_ap_data_dir)/$1"
    printf '%s\n' "$_ap_provider_dir_value"
}

_ap_profile_dir() {
    _ap_validate_name "$2" || return 1
    _ap_profile_dir_value="$(_ap_provider_dir "$1")/$2"
    printf '%s\n' "$_ap_profile_dir_value"
}

_ap_default_file() {
    printf '%s/.default\n' "$(_ap_provider_dir "$1")"
}

_ap_active_name() {
    case "$1" in
        antigravity) printf '%s\n' "${AGENT_PROFILE_ANTIGRAVITY_ACTIVE:-}" ;;
        codex) printf '%s\n' "${AGENT_PROFILE_CODEX_ACTIVE:-}" ;;
    esac
}

# Resolves an existing profile into _ap_selected_dir. It deliberately emits
# no error so wrappers can pass through when profiles have not been configured.
_ap_selected_profile() {
    _ap_selected_provider="$1"
    _ap_selected_name=$(_ap_active_name "$_ap_selected_provider")
    _ap_selected_default_file=$(_ap_default_file "$_ap_selected_provider")
    if [ -z "$_ap_selected_name" ] && [ -f "$_ap_selected_default_file" ]; then
        _ap_selected_name=$(cat "$_ap_selected_default_file")
    fi
    [ -n "$_ap_selected_name" ] || return 1
    _ap_validate_name "$_ap_selected_name" >/dev/null 2>&1 || return 1
    _ap_selected_dir=$(_ap_profile_dir "$_ap_selected_provider" "$_ap_selected_name")
    [ -d "$_ap_selected_dir" ]
}

_ap_gui_source_dir() {
    if [ -n "${AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR:-}" ]; then
        [ -d "$AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR" ] && printf '%s\n' "$AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR"
        return 0
    fi
    case "$(uname -s 2>/dev/null)" in
        Darwin)
            for _ap_candidate in \
                "$HOME/Library/Application Support/Antigravity IDE" \
                "$HOME/Library/Application Support/Antigravity" \
                "$HOME/.gemini/antigravity-ide"; do
                if [ -d "$_ap_candidate" ]; then
                    printf '%s\n' "$_ap_candidate"
                    return 0
                fi
            done
            ;;
        *)
            for _ap_candidate in \
                "${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity IDE" \
                "${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity" \
                "$HOME/.gemini/antigravity-ide" \
                "$HOME/.antigravity-ide"; do
                if [ -d "$_ap_candidate" ]; then
                    printf '%s\n' "$_ap_candidate"
                    return 0
                fi
            done
            ;;
    esac
    return 0
}

_ap_copy_tree() {
    _ap_copy_source="$1"
    _ap_copy_destination="$2"
    mkdir -p "$_ap_copy_destination" || return 1
    cp -R "$_ap_copy_source"/. "$_ap_copy_destination"/ 2>/dev/null
}

# Chromium's singleton files are symlinks naming the host and pid that owned the
# source instance (SingletonLock -> <host>-<pid>) plus a socket under the source
# instance's temp dir. Copied into a new profile they can make Antigravity decide
# another instance already owns this user-data-dir and simply focus that window,
# which looks exactly like the profile failing to switch. They are pure runtime
# state, so drop them from every snapshot.
_ap_prune_gui_locks() {
    [ -d "$1" ] || return 0
    rm -f "$1/SingletonLock" "$1/SingletonCookie" "$1/SingletonSocket" 2>/dev/null
    return 0
}

_ap_snapshot_live() {
    _ap_snapshot_provider="$1"
    _ap_snapshot_destination="$2"
    mkdir -p "$_ap_snapshot_destination" || return 1
    case "$_ap_snapshot_provider" in
        antigravity)
            if [ -d "$HOME/.gemini" ]; then
                _ap_copy_tree "$HOME/.gemini" "$_ap_snapshot_destination/home/.gemini" || return 1
            fi
            _ap_snapshot_gui=$(_ap_gui_source_dir)
            if [ -n "$_ap_snapshot_gui" ] && [ -d "$_ap_snapshot_gui" ]; then
                _ap_copy_tree "$_ap_snapshot_gui" "$_ap_snapshot_destination/gui-user-data" || return 1
            fi
            ;;
        codex)
            _ap_snapshot_codex_home="${CODEX_HOME:-$HOME/.codex}"
            if [ -d "$_ap_snapshot_codex_home" ]; then
                _ap_copy_tree "$_ap_snapshot_codex_home" "$_ap_snapshot_destination" || return 1
            fi
            ;;
    esac
    return 0
}

_ap_copy_profile() {
    _ap_copy_provider="$1"
    _ap_copy_source="$2"
    _ap_copy_name="$3"
    _ap_copy_force="$4"
    _ap_copy_final_destination=$(_ap_profile_dir "$_ap_copy_provider" "$_ap_copy_name") || return 1
    _ap_copy_provider_root=$(_ap_provider_dir "$_ap_copy_provider")
    mkdir -p "$_ap_copy_provider_root" || {
        _ap_die "could not create profile directory '$_ap_copy_provider_root'"
        return 1
    }
    if [ -e "$_ap_copy_final_destination" ] || [ -L "$_ap_copy_final_destination" ]; then
        if [ "$_ap_copy_force" -ne 1 ]; then
            _ap_die "profile '$_ap_copy_name' already exists (use --force to replace it)"
            return 1
        fi
    fi

    _ap_copy_tmp="${_ap_copy_final_destination}.tmp.$$"
    rm -rf "$_ap_copy_tmp" 2>/dev/null
    mkdir -p "$_ap_copy_tmp" || {
        _ap_die "could not create temporary profile directory"
        return 1
    }
    if [ "$_ap_copy_source" = live ]; then
        _ap_snapshot_live "$_ap_copy_provider" "$_ap_copy_tmp"
    else
        _ap_validate_name "$_ap_copy_source" || {
            rm -rf "$_ap_copy_tmp"
            return 1
        }
        _ap_copy_source_dir=$(_ap_profile_dir "$_ap_copy_provider" "$_ap_copy_source")
        if [ ! -d "$_ap_copy_source_dir" ]; then
            _ap_die "source profile '$_ap_copy_source' does not exist"
            rm -rf "$_ap_copy_tmp"
            return 1
        fi
        _ap_copy_tree "$_ap_copy_source_dir" "$_ap_copy_tmp"
    fi
    if [ "$?" -ne 0 ]; then
        _ap_die "could not copy profile data"
        rm -rf "$_ap_copy_tmp"
        return 1
    fi
    _ap_prune_gui_locks "$_ap_copy_tmp/gui-user-data"
    if [ -e "$_ap_copy_final_destination" ] || [ -L "$_ap_copy_final_destination" ]; then
        rm -rf "$_ap_copy_final_destination" || {
            _ap_die "could not replace profile '$_ap_copy_name'"
            rm -rf "$_ap_copy_tmp"
            return 1
        }
    fi
    mv "$_ap_copy_tmp" "$_ap_copy_final_destination" || {
        _ap_die "could not finalize profile '$_ap_copy_name'"
        rm -rf "$_ap_copy_tmp"
        return 1
    }
    printf 'Copied %s profile to: %s\n' "$_ap_copy_provider" "$_ap_copy_name"
    if [ "$_ap_copy_source" = live ] && [ "$_ap_copy_provider" = antigravity ]; then
        printf 'Note: OS keyring credentials are not copied; keyring-backed login may remain shared.\n' >&2
    fi
    printf 'Profile directory: %s\n' "$_ap_copy_final_destination"
    return 0
}

_ap_set_active() {
    case "$1" in
        antigravity) export AGENT_PROFILE_ANTIGRAVITY_ACTIVE="$2" ;;
        codex) export AGENT_PROFILE_CODEX_ACTIVE="$2" ;;
    esac
}

_ap_get_default() {
    _ap_get_default_file=$(_ap_default_file "$1")
    if [ ! -f "$_ap_get_default_file" ]; then
        _ap_die "no default profile set for $1"
        return 1
    fi
    _ap_get_default_name=$(cat "$_ap_get_default_file")
    if [ -z "$_ap_get_default_name" ]; then
        _ap_die "default profile file is empty for $1"
        return 1
    fi
    printf '%s\n' "$_ap_get_default_name"
}

_ap_manager_list() {
    _ap_list_provider="$1"
    _ap_list_root=$(_ap_provider_dir "$_ap_list_provider")
    if [ ! -d "$_ap_list_root" ]; then
        printf 'No %s profiles found. Create one with: agent-profile create %s <name>\n' "$_ap_list_provider" "$_ap_list_provider"
        return 0
    fi
    _ap_list_default=""
    if [ -f "$_ap_list_root/.default" ]; then
        _ap_list_default=$(cat "$_ap_list_root/.default")
    fi
    _ap_list_active=$(_ap_active_name "$_ap_list_provider")
    _ap_list_found=0
    [ -n "$(ls "$_ap_list_root" 2>/dev/null)" ] || {
        printf 'No %s profiles found. Create one with: agent-profile create %s <name>\n' "$_ap_list_provider" "$_ap_list_provider"
        return 0
    }
    for _ap_entry in "$_ap_list_root"/*; do
        [ -d "$_ap_entry" ] || continue
        _ap_entry_name=${_ap_entry##*/}
        _ap_list_found=1
        _ap_status=""
        if [ "$_ap_entry_name" = "$_ap_list_default" ] && [ "$_ap_entry_name" = "$_ap_list_active" ]; then
            _ap_status=' (default, active)'
        elif [ "$_ap_entry_name" = "$_ap_list_default" ]; then
            _ap_status=' (default)'
        elif [ "$_ap_entry_name" = "$_ap_list_active" ]; then
            _ap_status=' (active)'
        fi
        printf '   %s%s\n' "$_ap_entry_name" "$_ap_status"
    done
    [ "$_ap_list_found" -eq 1 ] || printf 'No %s profiles found. Create one with: agent-profile create %s <name>\n' "$_ap_list_provider" "$_ap_list_provider"
}

_ap_has_gui_data_arg() {
    for _ap_gui_arg in "$@"; do
        case "$_ap_gui_arg" in
            --user-data-dir|--user-data-dir=*) return 0 ;;
        esac
    done
    return 1
}

_ap_has_new_window_arg() {
    for _ap_window_arg in "$@"; do
        [ "$_ap_window_arg" = --new-window ] && return 0
    done
    return 1
}

_ap_native_path() {
    if _ap_is_msys && command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1" 2>/dev/null
    else
        printf '%s\n' "$1"
    fi
}

_ap_macos_gui_app() {
    [ "$(uname -s 2>/dev/null)" = Darwin ] || return 1
    for _ap_gui_app in \
        "/Applications/Antigravity.app" \
        "${HOME}/Applications/Antigravity.app"; do
        _ap_gui_app_binary="${_ap_gui_app}/Contents/MacOS/Antigravity"
        if [ -x "$_ap_gui_app_binary" ]; then
            printf '%s\n' "$_ap_gui_app"
            return 0
        fi
    done
    return 1
}

_ap_macos_gui_command() {
    _ap_gui_app=$(_ap_macos_gui_app) || return 1
    printf '%s/Contents/MacOS/Antigravity\n' "$_ap_gui_app"
}

_ap_find_path_command() {
    _ap_find_name=$1
    _ap_find_old_ifs=$IFS
    IFS=:
    for _ap_find_dir in ${PATH:-}; do
        [ -n "$_ap_find_dir" ] || _ap_find_dir=.
        if [ -f "$_ap_find_dir/$_ap_find_name" ] && [ -x "$_ap_find_dir/$_ap_find_name" ]; then
            IFS=$_ap_find_old_ifs
            printf '%s\n' "$_ap_find_name"
            return 0
        fi
    done
    IFS=$_ap_find_old_ifs
    return 1
}

_ap_find_gui_command() {
    _ap_gui_command="${AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND:-}"
    if [ -n "$_ap_gui_command" ]; then
        printf '%s\n' "$_ap_gui_command"
        return 0
    fi
    if _ap_find_path_command antigravity-ide >/dev/null 2>&1; then
        printf '%s\n' antigravity-ide
        return 0
    fi
    if _ap_find_path_command antigravity >/dev/null 2>&1; then
        printf '%s\n' antigravity
        return 0
    fi
    _ap_gui_app=$(_ap_macos_gui_app) || return 1
    printf 'app:%s\n' "$_ap_gui_app"
}

# macOS finds the login keychain at $HOME/Library/Keychains, so a redirected HOME
# leaves the child with no keychain at all -- Chromium then cannot store its
# "Antigravity Safe Storage" key and macOS puts up "A keychain cannot be found to
# store antigravity". Point the profile at the real keychain instead. That key
# only encrypts the local cookie store at rest; the account itself lives in
# ~/.gemini, which stays per-profile, so sharing it costs no isolation.
_ap_link_macos_keychains() {
    [ "$(uname -s 2>/dev/null)" = Darwin ] || return 0
    [ -d "$HOME/Library/Keychains" ] || return 0
    # Never disturb a real directory or an existing link the user put here.
    if [ -e "$1/Library/Keychains" ] || [ -L "$1/Library/Keychains" ]; then
        return 0
    fi
    mkdir -p "$1/Library" 2>/dev/null || return 0
    ln -s "$HOME/Library/Keychains" "$1/Library/Keychains" 2>/dev/null
    return 0
}

_ap_launch_cli() {
    _ap_launch_provider="$1"
    _ap_launch_command="$2"
    shift 2
    if ! _ap_selected_profile "$_ap_launch_provider"; then
        command "$_ap_launch_command" "$@"
        return $?
    fi
    mkdir -p "$_ap_selected_dir/home" 2>/dev/null
    _ap_link_macos_keychains "$_ap_selected_dir/home"
    _ap_child_home=$(_ap_native_path "$_ap_selected_dir/home")
    if _ap_is_msys; then
        env HOME="$_ap_child_home" USERPROFILE="$_ap_child_home" "$_ap_launch_command" "$@"
    else
        env HOME="$_ap_child_home" "$_ap_launch_command" "$@"
    fi
}

# open(1) has supported --env for many releases, but fall back gracefully if this
# macOS predates it. An unrecognized option makes open print its usage and exit
# without launching anything, so probing this way has no side effects.
_ap_open_supports_env() {
    /usr/bin/open --ap-probe-unsupported-option 2>&1 | grep -q -- '--env'
}

# Launches the GUI with the selected profile's HOME in its environment.
#
# HOME is the knob that actually switches profiles: Antigravity resolves its real
# state (account, conversations, agent data) from os.homedir()/.gemini, so a run
# that only overrides --user-data-dir keeps loading the original profile.
# --user-data-dir is still passed because it moves Chromium's own user data --
# most importantly the singleton lock -- which is what lets two profiles run at
# the same time.
#
# On macOS the bundle goes through open(1) rather than exec'ing Contents/MacOS
# directly: --env carries HOME in, -n forces a separate instance, and
# LaunchServices reparents the app to launchd so it survives the shell and keeps
# normal Dock and activation behaviour.
_ap_launch_gui_run() {
    if [ "$_ap_gui_mode" != app ]; then
        if _ap_is_msys; then
            env HOME="$_ap_gui_home" USERPROFILE="$_ap_gui_home" "$_ap_gui_command" "$@"
        else
            env HOME="$_ap_gui_home" "$_ap_gui_command" "$@"
        fi
        return $?
    fi
    if _ap_open_supports_env; then
        command /usr/bin/open -n --env HOME="$_ap_gui_home" -a "$_ap_gui_app" --args "$@"
        return $?
    fi
    _ap_gui_bin=$(_ap_macos_gui_command) || return 127
    # Without --env the binary has to be exec'd directly. The subshell backgrounds
    # and orphans it so it outlives the shell without joining the job table, which
    # zsh would otherwise SIGHUP on exit.
    ( env HOME="$_ap_gui_home" "$_ap_gui_bin" "$@" >/dev/null 2>&1 </dev/null & )
}

_ap_launch_gui() {
    _ap_gui_launcher=$(_ap_find_gui_command)
    if [ -z "$_ap_gui_launcher" ]; then
        _ap_die "could not find antigravity GUI; set AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND"
        return 127
    fi
    _ap_gui_mode=command
    case "$_ap_gui_launcher" in
        app:*)
            _ap_gui_mode=app
            _ap_gui_app=${_ap_gui_launcher#app:}
            ;;
        *)
            _ap_gui_command=$_ap_gui_launcher
            ;;
    esac
    if ! _ap_selected_profile antigravity; then
        if [ "$_ap_gui_mode" = app ]; then
            command /usr/bin/open -n -a "$_ap_gui_app" --args "$@"
        else
            command "$_ap_gui_command" "$@"
        fi
        return $?
    fi
    mkdir -p "$_ap_selected_dir/home" "$_ap_selected_dir/gui-user-data" 2>/dev/null
    _ap_link_macos_keychains "$_ap_selected_dir/home"
    _ap_gui_home=$(_ap_native_path "$_ap_selected_dir/home")
    _ap_gui_data_dir=$(_ap_native_path "$_ap_selected_dir/gui-user-data")
    if _ap_has_gui_data_arg "$@"; then
        _ap_launch_gui_run "$@"
    else
        # The "=" form is required: the app bundle is a plain Electron app whose
        # Chromium parser only understands --switch=value and silently ignores the
        # space-separated spelling. A VS Code derived antigravity-ide accepts it too.
        _ap_launch_gui_run --user-data-dir="$_ap_gui_data_dir" "$@"
    fi
}

# The app bundle takes no --new-window -- that is a VS Code flag and is inert
# here; a separate HOME plus a separate user-data-dir is what lets another
# profile open alongside the running one. Keep injecting it for a VS Code derived
# antigravity-ide on PATH, where it is the real new-window mechanism.
_ap_restart_gui() {
    _ap_restart_launcher=$(_ap_find_gui_command)
    case "$_ap_restart_launcher" in
        app:*)
            _ap_launch_gui "$@"
            ;;
        *)
            if _ap_has_new_window_arg "$@"; then
                _ap_launch_gui "$@"
            else
                _ap_launch_gui --new-window "$@"
            fi
            ;;
    esac
}

_ap_help() {
    cat <<'HELP'
Usage: agent-profile <provider> <command> [args...]
       agent-profile <command> <provider> [args...]

Providers:
  antigravity  Antigravity CLI (agy) and GUI (antigravity/antigravity-ide)
  codex        OpenAI Codex CLI

Commands:
  create <provider> <name>                 Create an empty profile
  copy <provider> <name> [--force]         Copy current live data
  copy <provider> <source> <name> [--force] Copy a managed profile
  list <provider>                          List profiles
  default <provider> [name]                Get or set the default
  use <provider> <name>                    Select a profile for this shell
  which <provider> [name]                  Print a profile directory
  restart <provider> [args...]             Open a fresh Antigravity GUI window
  delete <provider> <name> [--force]       Delete a profile

Aliases: agy-profile, antigravity-profile, codex-profile

Examples:
  agent-profile copy antigravity hafez
  agent-profile copy antigravity default hafez
  agent-profile default antigravity hafez
  agent-profile use codex work
HELP
}

# shellcheck disable=SC3033  # hyphenated function names are valid in bash/zsh
agent-profile() {
    if [ "$#" -eq 0 ]; then
        _ap_help
        return 0
    fi
    case "$1" in
        help|-h|--help)
            _ap_help
            return 0
            ;;
        create|copy|list|ls|default|use|which|restart|delete|status)
            _ap_command="$1"
            shift
            _ap_provider_arg="${1:-}"
            [ -n "$_ap_provider_arg" ] || { _ap_die "missing provider"; return 1; }
            shift
            ;;
        *)
            _ap_provider_arg="$1"
            shift
            _ap_command="${1:-status}"
            [ "$#" -gt 0 ] && shift
            ;;
    esac
    _ap_provider_name=$(_ap_provider "$_ap_provider_arg") || return 1

    case "$_ap_command" in
        status)
            _ap_status_default=$(_ap_get_default "$_ap_provider_name" 2>/dev/null || true)
            _ap_status_active=$(_ap_active_name "$_ap_provider_name")
            _ap_status_path=""
            if _ap_selected_profile "$_ap_provider_name"; then
                _ap_status_path="$_ap_selected_dir"
            fi
            printf 'Provider: %s\n' "$_ap_provider_name"
            printf 'Default: %s\n' "${_ap_status_default:-<none>}"
            printf 'Active: %s\n' "${_ap_status_active:-<default>}"
            [ -n "$_ap_status_path" ] && printf 'Path: %s\n' "$_ap_status_path"
            ;;
        create)
            _ap_name="${1:-}"
            [ "$#" -eq 1 ] || { _ap_die "usage: agent-profile create $_ap_provider_name <name>"; return 1; }
            _ap_validate_name "$_ap_name" || return 1
            _ap_dir=$(_ap_profile_dir "$_ap_provider_name" "$_ap_name")
            [ ! -e "$_ap_dir" ] || { _ap_die "profile '$_ap_name' already exists"; return 1; }
            mkdir -p "$_ap_dir" || { _ap_die "could not create profile '$_ap_name'"; return 1; }
            printf 'Created %s profile: %s\n' "$_ap_provider_name" "$_ap_name"
            printf 'Profile directory: %s\n' "$_ap_dir"
            ;;
        copy)
            _ap_copy_force=0
            _ap_copy_count=0
            _ap_copy_arg1=""
            _ap_copy_arg2=""
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --force) _ap_copy_force=1 ;;
                    -* ) _ap_die "unknown option '$1'"; return 1 ;;
                    *)
                        _ap_copy_count=$((_ap_copy_count + 1))
                        if [ "$_ap_copy_count" -eq 1 ]; then _ap_copy_arg1="$1"; else _ap_copy_arg2="$1"; fi
                        ;;
                esac
                shift
            done
            if [ "$_ap_copy_count" -eq 1 ]; then
                _ap_copy_source=live
                _ap_copy_name="$_ap_copy_arg1"
            elif [ "$_ap_copy_count" -eq 2 ]; then
                _ap_copy_source="$_ap_copy_arg1"
                _ap_copy_name="$_ap_copy_arg2"
                [ "$_ap_copy_source" = default ] && _ap_copy_source=$(_ap_get_default "$_ap_provider_name") || :
            else
                _ap_die "usage: agent-profile copy $_ap_provider_name [source] <name> [--force]"
                return 1
            fi
            _ap_validate_name "$_ap_copy_name" || return 1
            _ap_copy_profile "$_ap_provider_name" "$_ap_copy_source" "$_ap_copy_name" "$_ap_copy_force"
            ;;
        list|ls)
            [ "$#" -eq 0 ] || { _ap_die "usage: agent-profile list $_ap_provider_name"; return 1; }
            _ap_manager_list "$_ap_provider_name"
            ;;
        default)
            if [ "$#" -eq 0 ]; then
                _ap_get_default "$_ap_provider_name"
                return $?
            fi
            [ "$#" -eq 1 ] || { _ap_die "usage: agent-profile default $_ap_provider_name [name]"; return 1; }
            _ap_validate_name "$1" || return 1
            _ap_dir=$(_ap_profile_dir "$_ap_provider_name" "$1")
            [ -d "$_ap_dir" ] || { _ap_die "profile '$1' does not exist"; return 1; }
            _ap_root=$(_ap_provider_dir "$_ap_provider_name")
            mkdir -p "$_ap_root" || return 1
            printf '%s' "$1" > "$_ap_root/.default" || return 1
            printf 'Default %s profile set to: %s\n' "$_ap_provider_name" "$1"
            ;;
        use)
            [ "$#" -eq 1 ] || { _ap_die "usage: agent-profile use $_ap_provider_name <name>"; return 1; }
            _ap_validate_name "$1" || return 1
            _ap_dir=$(_ap_profile_dir "$_ap_provider_name" "$1")
            [ -d "$_ap_dir" ] || { _ap_die "profile '$1' does not exist"; return 1; }
            _ap_set_active "$_ap_provider_name" "$1"
            printf 'Switched to %s profile: %s\n' "$_ap_provider_name" "$1"
            ;;
        which)
            [ "$#" -le 1 ] || { _ap_die "usage: agent-profile which $_ap_provider_name [name]"; return 1; }
            if [ "$#" -eq 1 ]; then
                _ap_validate_name "$1" || return 1
                _ap_dir=$(_ap_profile_dir "$_ap_provider_name" "$1")
                [ -d "$_ap_dir" ] || { _ap_die "profile '$1' does not exist"; return 1; }
                printf '%s\n' "$_ap_dir"
            else
                _ap_selected_profile "$_ap_provider_name" || { _ap_die "no active or default profile set for $_ap_provider_name"; return 1; }
                printf '%s\n' "$_ap_selected_dir"
            fi
            ;;
        restart)
            [ "$_ap_provider_name" = antigravity ] || { _ap_die "restart is only supported for antigravity"; return 1; }
            _ap_restart_gui "$@"
            ;;
        delete)
            _ap_delete_force=0
            _ap_delete_name="${1:-}"
            if [ "${2:-}" = --force ]; then _ap_delete_force=1; fi
            [ -n "$_ap_delete_name" ] && { [ "$#" -eq 1 ] || [ "$#" -eq 2 ] && [ "${2:-}" = --force ]; } || {
                _ap_die "usage: agent-profile delete $_ap_provider_name <name> [--force]"
                return 1
            }
            _ap_validate_name "$_ap_delete_name" || return 1
            _ap_dir=$(_ap_profile_dir "$_ap_provider_name" "$_ap_delete_name")
            [ -d "$_ap_dir" ] || { _ap_die "profile '$_ap_delete_name' does not exist"; return 1; }
            if [ "$_ap_delete_force" -ne 1 ]; then
                printf 'Delete %s profile "%s" and all its data? [y/N] ' "$_ap_provider_name" "$_ap_delete_name"
                read -r _ap_confirm || return 1
                case "$_ap_confirm" in [yY]|[yY][eE][sS]) : ;; *) printf 'Cancelled.\n'; return 0 ;; esac
            fi
            rm -rf "$_ap_dir" || return 1
            _ap_root=$(_ap_provider_dir "$_ap_provider_name")
            if [ -f "$_ap_root/.default" ] && [ "$(cat "$_ap_root/.default")" = "$_ap_delete_name" ]; then rm -f "$_ap_root/.default"; fi
            if [ "$(_ap_active_name "$_ap_provider_name")" = "$_ap_delete_name" ]; then _ap_set_active "$_ap_provider_name" ""; fi
            printf 'Deleted %s profile: %s\n' "$_ap_provider_name" "$_ap_delete_name"
            ;;
        *)
            _ap_die "unknown command '$_ap_command'. Run 'agent-profile help' for usage."
            return 1
            ;;
    esac
}

agy() {
    _ap_launch_cli antigravity "${AGENT_PROFILE_AGY_COMMAND:-agy}" "$@"
}

antigravity() {
    _ap_launch_gui "$@"
}

antigravity-ide() {
    _ap_launch_gui "$@"
}

codex() {
    if ! _ap_selected_profile codex; then
        command "${AGENT_PROFILE_CODEX_COMMAND:-codex}" "$@"
        return $?
    fi
    _ap_codex_home=$(_ap_native_path "$_ap_selected_dir")
    env CODEX_HOME="$_ap_codex_home" "${AGENT_PROFILE_CODEX_COMMAND:-codex}" "$@"
}

agy-profile() {
    agent-profile antigravity "$@"
}

antigravity-profile() {
    agent-profile antigravity "$@"
}

codex-profile() {
    agent-profile codex "$@"
}
