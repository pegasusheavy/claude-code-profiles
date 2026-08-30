# claude-profile.fish — source this in ~/.config/fish/config.fish
#
# Native Fish adapter for Claude Code profiles. It uses the same on-disk
# layout as claude-profile.sh and keeps the session-changing commands native
# to Fish; the mature skill-pool and updater implementations are delegated to
# the POSIX adapter in a short-lived Bash process.

set -l __claude_profile_fish_file (status filename)
if not string match -q -- '/*' "$__claude_profile_fish_file"
    set __claude_profile_fish_file "$PWD/$__claude_profile_fish_file"
end
set -g __claude_profile_fish_source_dir (path dirname "$__claude_profile_fish_file")

function _cp_fish_die
    printf 'claude-profile: %s\n' $argv[1] >&2
end

function _cp_fish_join
    string join / $argv
end

function _cp_fish_data_dir
    if set -q XDG_DATA_HOME[1]; and test -n "$XDG_DATA_HOME"
        _cp_fish_join "$XDG_DATA_HOME" claude-profiles
    else
        _cp_fish_join "$HOME" .local share claude-profiles
    end
end

function _cp_fish_install_dir
    if set -q XDG_DATA_HOME[1]; and test -n "$XDG_DATA_HOME"
        _cp_fish_join "$XDG_DATA_HOME" claude-profile
    else
        _cp_fish_join "$HOME" .local share claude-profile
    end
end

function _cp_fish_validate_name
    set -l name $argv[1]
    set -l noun profile
    if set -q argv[2]
        set noun $argv[2]
    end
    if test (count $argv) -eq 0; or test -z "$name"
        _cp_fish_die "$noun name must not be empty"
        return 1
    end
    if string match -q -- '.*' "$name"
        _cp_fish_die "invalid $noun name '$name': must not start with '.'"
        return 1
    end
    if string match -q -- '*..*' "$name"
        _cp_fish_die "invalid $noun name '$name': must not contain '..'"
        return 1
    end
    if not string match -rq '^[A-Za-z0-9_-]+$' -- "$name"
        _cp_fish_die "invalid $noun name '$name': use only letters, digits, hyphens, underscores"
        return 1
    end
    if string match -qi -- skills "$name"; and test "$noun" = profile
        _cp_fish_die "profile name 'skills' is reserved for the skill pool"
        return 1
    end
    return 0
end

function _cp_fish_profile_dir
    _cp_fish_validate_name $argv[1] >/dev/null
    or return 1
    _cp_fish_join (_cp_fish_data_dir) $argv[1]
end

function _cp_fish_default_name
    set -l file (_cp_fish_join (_cp_fish_data_dir) .default)
    if not test -f "$file"
        return 1
    end
    set -l name (string collect < "$file" | string trim)
    _cp_fish_validate_name "$name" >/dev/null
    or return 1
    test -d (_cp_fish_profile_dir "$name")
    or return 1
    printf '%s\n' "$name"
end

function _cp_fish_active_name
    if set -q CLAUDE_CONFIG_DIR[1]; and test -n "$CLAUDE_CONFIG_DIR"
        set -l data (_cp_fish_data_dir)
        set -l prefix "$data/"
        if string match -q -- "$prefix*" "$CLAUDE_CONFIG_DIR"
            printf '%s\n' (path basename "$CLAUDE_CONFIG_DIR")
        end
    end
end

function _cp_fish_find_dotfile
    set -l directory $argv[1]
    if test -z "$directory"
        set directory "$PWD"
    end
    while true
        set -l candidate (_cp_fish_join "$directory" .claude-profile)
        if test -f "$candidate"
            printf '%s\n' "$candidate"
            return 0
        end
        if test "$directory" = /
            break
        end
        set -l parent (path dirname "$directory")
        if test "$parent" = "$directory"
            break
        end
        set directory "$parent"
    end
    return 1
end

function _cp_fish_read_dotfile
    set -l file $argv[1]
    while read -l line
        set line (string replace -r '\r$' '' -- "$line")
        set line (string trim -- "$line")
        if test -n "$line"; and not string match -q -- '#*' "$line"
            printf '%s\n' "$line"
            return 0
        end
    end < "$file"
    return 1
end

function _cp_fish_pool_skills
    set -l pool (_cp_fish_join (_cp_fish_data_dir) skills)
    for entry in "$pool"/*
        if test -d "$entry"; or test -L "$entry"
            printf '%s\n' (path basename "$entry")
        end
    end
end

function _cp_fish_manifest_skills
    set -l file $argv[1]
    while read -l line
        set line (string replace -r '\r$' '' -- "$line")
        set line (string trim -- "$line")
        if test -n "$line"; and not string match -q -- '#*' "$line"; and _cp_fish_validate_name "$line" skill >/dev/null 2>&1
            printf '%s\n' "$line"
        end
    end < "$file"
end

function _cp_fish_auto_notice
    if not set -q CLAUDE_PROFILE_AUTO_QUIET[1]
        printf 'claude-profile: %s\n' $argv[1] >&2
    end
end

function _cp_fish_auto_switch
    if set -q CLAUDE_PROFILE_NO_AUTO_SWITCH[1]
        return 0
    end
    if set -q __claude_profile_auto_off[1]; and test "$__claude_profile_auto_off" = 1
        return 0
    end
    if set -q __claude_profile_auto_last_pwd[1]; and test "$PWD" = "$__claude_profile_auto_last_pwd"
        return 0
    end
    set -g __claude_profile_auto_last_pwd "$PWD"

    # An explicit environment value or `claude-profile use` pins the session.
    if set -q CLAUDE_CONFIG_DIR[1]; and test -n "$CLAUDE_CONFIG_DIR"
        if not set -q CLAUDE_PROFILE_AUTO_SET[1]; or test "$CLAUDE_CONFIG_DIR" != "$CLAUDE_PROFILE_AUTO_SET"
            return 0
        end
    end

    set -l dotfile (_cp_fish_find_dotfile "$PWD")
    set -l dot_status $status
    set -l dotname
    if test $dot_status -eq 0
        set dotname (_cp_fish_read_dotfile "$dotfile")
    end

    if test -z "$dotname"
        if set -q CLAUDE_PROFILE_AUTO_SET[1]
            set -e CLAUDE_CONFIG_DIR
            set -e CLAUDE_PROFILE_AUTO_SET
            _cp_fish_auto_notice 'directory profile cleared; using the default profile'
        end
        if test -n "$dotfile"
            _cp_fish_die "ignoring $dotfile: no profile name in file"
        end
        return 0
    end

    if not _cp_fish_validate_name "$dotname" >/dev/null 2>&1
        _cp_fish_die "ignoring $dotfile: invalid profile name '$dotname'"
        return 1
    end
    set -l profile (_cp_fish_profile_dir "$dotname")
    if not test -d "$profile"
        _cp_fish_die "ignoring $dotfile: profile '$dotname' does not exist"
        return 1
    end
    if set -q CLAUDE_CONFIG_DIR[1]; and test "$CLAUDE_CONFIG_DIR" = "$profile"
        set -gx CLAUDE_PROFILE_AUTO_SET "$profile"
        return 0
    end
    set -gx CLAUDE_CONFIG_DIR "$profile"
    set -gx CLAUDE_PROFILE_AUTO_SET "$profile"
    _cp_fish_auto_notice "switched to profile '$dotname' (from $dotfile)"
end

function __claude_profile_fish_pwd_changed --on-variable PWD
    _cp_fish_auto_switch
end

function _cp_fish_backend
    if not type -q bash
        _cp_fish_die 'this command requires bash; install bash or run it from a POSIX shell'
        return 127
    end
    set -l script (_cp_fish_join "$__claude_profile_fish_source_dir" claude-profile.sh)
    if not test -f "$script"
        _cp_fish_die "POSIX adapter not found at '$script'"
        return 1
    end
    command bash -c 'script=$1; shift; . "$script"; claude-profile "$@"' fish "$script" $argv
end

function _cp_fish_update_check
    if set -q CLAUDE_PROFILE_NO_UPDATE_CHECK[1]
        return 0
    end
    # Keep passive checks non-blocking from the user's perspective: the POSIX
    # implementation already has the cache, timeout, and failure semantics.
    set -l script (_cp_fish_join "$__claude_profile_fish_source_dir" claude-profile.sh)
    if type -q bash; and test -f "$script"
        command bash -c 'script=$1; . "$script"; _cp_update_check' fish "$script" >/dev/null 2>&1
    end
end

function claude
    _cp_fish_update_check
    _cp_fish_auto_switch
    if not set -q CLAUDE_CONFIG_DIR[1]; or test -z "$CLAUDE_CONFIG_DIR"
        set -l default (_cp_fish_default_name)
        if test -n "$default"
            set -gx CLAUDE_CONFIG_DIR (_cp_fish_profile_dir "$default")
            set -gx CLAUDE_PROFILE_AUTO_SET "$CLAUDE_CONFIG_DIR"
        end
    end
    set -l claude_bin (command -s claude)
    if test -z "$claude_bin"
        _cp_fish_die 'could not find claude on PATH'
        return 127
    end
    command "$claude_bin" $argv
end

function _cp_fish_write_skeleton
    set -l file $argv[1]
    printf '%s\n' \
        '{' \
        '  "env": {' \
        '    "ANTHROPIC_API_KEY": "YOUR_API_KEY_HERE",' \
        '    "ANTHROPIC_BASE_URL": "https://YOUR_ENDPOINT_HERE",' \
        '    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "0"' \
        '  },' \
        '  "model": "claude-sonnet-4-6",' \
        '  "advisorModel": "claude-opus-4-8",' \
        '  "fallbackModel": ["claude-haiku-4-5"],' \
        '  "effortLevel": "high",' \
        '  "alwaysThinkingEnabled": false,' \
        '  "permissions": {' \
        '    "allow": [],' \
        '    "deny": []' \
        '  },' \
        '  "autoMemoryEnabled": true,' \
        '  "autoCompactEnabled": true,' \
        '  "fileCheckpointingEnabled": true,' \
        '  "cleanupPeriodDays": 30,' \
        '  "language": "english",' \
        '  "editorMode": "normal",' \
        '  "preferredNotifChannel": "auto"' \
        '}' > "$file"
end

function _cp_fish_status
    set -l data (_cp_fish_data_dir)
    set -l active (_cp_fish_active_name)
    set -l default (_cp_fish_default_name 2>/dev/null)
    if test -n "$active"
        if set -q CLAUDE_PROFILE_AUTO_SET[1]; and test -n "$CLAUDE_CONFIG_DIR"
            printf 'Active profile: %s (directory-local)\n' "$active"
        else
            printf 'Active profile: %s\n' "$active"
        end
        printf 'Config directory: %s\n' "$CLAUDE_CONFIG_DIR"
    else if set -q CLAUDE_CONFIG_DIR[1]; and test -n "$CLAUDE_CONFIG_DIR"
        printf 'Active config directory: %s (not a managed profile)\n' "$CLAUDE_CONFIG_DIR"
    else
        printf 'No active profile\n'
    end
    if test -n "$default"
        printf 'Default profile: %s\n' "$default"
    else
        printf 'No default profile set\n'
    end
    set -l skill_profile "$active"
    if test -z "$skill_profile"
        set skill_profile "$default"
    end
    set -l skill_pool (_cp_fish_join "$data" skills)
    if test -d "$skill_pool"; and test -n "$skill_profile"; and test -d (_cp_fish_profile_dir "$skill_profile")
        set -l pool_count (count (_cp_fish_pool_skills))
        set -l skill_file (_cp_fish_join "$data" "$skill_profile" skills.conf)
        if test -f "$skill_file"
            set -l selected_count (count (_cp_fish_manifest_skills "$skill_file"))
            printf 'Skills: %s of %s pool skills (filtered)\n' "$selected_count" "$pool_count"
        else
            printf 'Skills: all pool skills (%s)\n' "$pool_count"
        end
    end
end

function _cp_fish_help
    printf '%s\n' \
        'Usage: claude-profile [command] [args...]' \
        '' \
        'Commands:' \
        '  (no command)            Show current profile status' \
        '  use <name>              Switch session to a named profile (pins it)' \
        '  create [--init] <name>  Create a profile' \
        '  list, ls                List all profiles' \
        '  default [name]          Get or set the default profile' \
        '  local [name]            Show or set .claude-profile for this directory' \
        '  auto [on|off|status]    Control directory-local auto-switching' \
        '  which [name]            Show a resolved config directory path' \
        '  skills ...              Manage the shared skill pool' \
        '  version                 Show the installed version' \
        '  update [--force]        Update the installed adapter' \
        '  delete <name>           Delete a profile' \
        '  help                    Show this help message' \
        '' \
        'Fish uses the same profile directories as the POSIX adapter. Source' \
        'claude-profile.fish from ~/.config/fish/config.fish.'
end

function claude-profile
    set -l command status
    set -l args $argv
    if test (count $args) -gt 0
        set command $args[1]
        set args $args[2..-1]
    end
    set command (string lower -- "$command")
    set -l data (_cp_fish_data_dir)

    switch $command
        case help -h --help
            _cp_fish_help
        case status
            if test (count $args) -gt 0
                _cp_fish_die "unexpected argument '$args[1]'"
                return 1
            end
            _cp_fish_status
        case use
            if test (count $args) -ne 1
                _cp_fish_die 'usage: claude-profile use <name>'
                return 1
            end
            _cp_fish_validate_name "$args[1]" >/dev/null
            or return 1
            set -l profile (_cp_fish_profile_dir "$args[1]")
            if not test -d "$profile"
                _cp_fish_die "profile '$args[1]' does not exist. Create it with: claude-profile create $args[1]"
                return 1
            end
            set -gx CLAUDE_CONFIG_DIR "$profile"
            set -e CLAUDE_PROFILE_AUTO_SET
            set -g __claude_profile_auto_last_pwd "$PWD"
            printf 'Switched to profile: %s\n' "$args[1]"
        case auto
            set -l mode status
            if test (count $args) -gt 0
                set mode (string lower -- "$args[1]")
            end
            switch $mode
                case on
                    set -e __claude_profile_auto_off
                    set -e CLAUDE_CONFIG_DIR
                    set -e CLAUDE_PROFILE_AUTO_SET
                    set -g __claude_profile_auto_last_pwd ''
                    _cp_fish_auto_switch
                    printf 'Directory-local auto-switching enabled.\n'
                case off
                    set -g __claude_profile_auto_off 1
                    printf 'Directory-local auto-switching disabled for this session.\n'
                case status
                    if set -q CLAUDE_PROFILE_NO_AUTO_SWITCH[1]
                        printf 'Auto-switching: disabled (CLAUDE_PROFILE_NO_AUTO_SWITCH is set)\n'
                    else if set -q __claude_profile_auto_off[1]; and test "$__claude_profile_auto_off" = 1
                        printf 'Auto-switching: disabled for this session\n'
                    else if set -q CLAUDE_CONFIG_DIR[1]; and test -n "$CLAUDE_CONFIG_DIR"; and not set -q CLAUDE_PROFILE_AUTO_SET[1]
                        printf 'Auto-switching: pinned (an explicit profile is active)\n'
                        printf "Run 'claude-profile auto on' to resume auto-switching.\n"
                    else
                        printf 'Auto-switching: enabled\n'
                    end
                    set -l dotfile (_cp_fish_find_dotfile "$PWD")
                    if test $status -eq 0
                        set -l dotname (_cp_fish_read_dotfile "$dotfile")
                        printf 'Directory profile: %s (%s)\n' (test -n "$dotname"; and printf '%s' "$dotname"; or printf '<empty>') "$dotfile"
                    else
                        printf 'Directory profile: none in scope\n'
                    end
                case '*'
                    _cp_fish_die 'usage: claude-profile auto [on|off|status]'
                    return 1
            end
        case local
            if test (count $args) -eq 0
                set -l dotfile (_cp_fish_find_dotfile "$PWD")
                if test $status -ne 0
                    _cp_fish_die 'no .claude-profile found in this directory or any parent'
                    return 1
                end
                set -l dotname (_cp_fish_read_dotfile "$dotfile")
                printf '%s\n' "$dotfile"
                printf 'Profile: %s\n' (test -n "$dotname"; and printf '%s' "$dotname"; or printf '<empty>')
            else if test "$args[1]" = --remove; or test "$args[1]" = --clear
                if test (count $args) -ne 1; or not test -f .claude-profile
                    _cp_fish_die 'no .claude-profile in the current directory'
                    return 1
                end
                command rm -f .claude-profile
                or return 1
                printf 'Removed %s\n' (_cp_fish_join "$PWD" .claude-profile)
                set -g __claude_profile_auto_last_pwd ''
                _cp_fish_auto_switch
            else
                if test (count $args) -ne 1
                    _cp_fish_die 'usage: claude-profile local [name|--remove]'
                    return 1
                end
                _cp_fish_validate_name "$args[1]" >/dev/null
                or return 1
                if not test -d (_cp_fish_profile_dir "$args[1]")
                    _cp_fish_die "profile '$args[1]' does not exist. Create it with: claude-profile create $args[1]"
                    return 1
                end
                printf '%s\n' "$args[1]" > .claude-profile
                or return 1
                printf 'Wrote %s (profile: %s)\n' (_cp_fish_join "$PWD" .claude-profile) "$args[1]"
                set -g __claude_profile_auto_last_pwd ''
                _cp_fish_auto_switch
            end
        case create
            set -l name
            set -l do_init 0
            for argument in $args
                switch $argument
                    case --init
                        set do_init 1
                    case '-*'
                        _cp_fish_die "unknown option '$argument'"
                        return 1
                    case '*'
                        if test -n "$name"
                            _cp_fish_die "unexpected argument '$argument'"
                            return 1
                        end
                        set name "$argument"
                end
            end
            if test -z "$name"
                _cp_fish_die 'usage: claude-profile create [--init] <name>'
                return 1
            end
            _cp_fish_validate_name "$name" >/dev/null
            or return 1
            set -l profile (_cp_fish_profile_dir "$name")
            if test -e "$profile"
                _cp_fish_die "profile '$name' already exists"
                return 1
            end
            mkdir -p "$profile"
            or return 1
            printf 'Created profile: %s\n' "$name"
            printf 'Config directory: %s\n' "$profile"
            if test -d (_cp_fish_join "$data" skills)
                _cp_fish_backend skills sync "$name" >/dev/null
                or return 1
            end
            if test $do_init -eq 1
                _cp_fish_write_skeleton (_cp_fish_join "$profile" settings.json)
                or return 1
                printf 'Config skeleton written to: %s\n' (_cp_fish_join "$profile" settings.json)
                printf 'Tip: remove "ANTHROPIC_BASE_URL" if using the default Anthropic endpoint.\n'
            end
        case list ls
            if test (count $args) -ne 0
                _cp_fish_die 'usage: claude-profile list'
                return 1
            end
            if not test -d "$data"
                printf 'No profiles found. Create one with: claude-profile create <name>\n'
                return 0
            end
            set -l default (_cp_fish_default_name 2>/dev/null)
            set -l active (_cp_fish_active_name)
            set -l found 0
            for entry in "$data"/*
                if not test -d "$entry"; or test (path basename "$entry") = skills
                    continue
                end
                set found 1
                set -l name (path basename "$entry")
                set -l marker '   '
                if test "$name" = "$default"; and test "$name" = "$active"
                    set marker '>* '
                else if test "$name" = "$default"
                    set marker ' * '
                else if test "$name" = "$active"
                    set marker '>  '
                end
                set -l suffix
                set -l skill_file (_cp_fish_join "$entry" skills.conf)
                if test -f "$skill_file"
                    set -l pool_count (count (_cp_fish_pool_skills))
                    set -l selected_count (count (_cp_fish_manifest_skills "$skill_file"))
                    set suffix " [skills: $selected_count/$pool_count]"
                end
                printf '%s%s%s\n' "$marker" "$name" "$suffix"
            end
            if test $found -eq 0
                printf 'No profiles found. Create one with: claude-profile create <name>\n'
            end
        case default
            if test (count $args) -eq 0
                set -l default (_cp_fish_default_name)
                if test -z "$default"
                    _cp_fish_die 'no default profile set. Set one with: claude-profile default <name>'
                    return 1
                end
                printf '%s\n' "$default"
                return 0
            end
            if test (count $args) -ne 1
                _cp_fish_die 'usage: claude-profile default [name]'
                return 1
            end
            _cp_fish_validate_name "$args[1]" >/dev/null
            or return 1
            set -l profile (_cp_fish_profile_dir "$args[1]")
            if not test -d "$profile"
                _cp_fish_die "profile '$args[1]' does not exist. Create it with: claude-profile create $args[1]"
                return 1
            end
            mkdir -p "$data"
            printf '%s' "$args[1]" > (_cp_fish_join "$data" .default)
            or return 1
            printf 'Default profile set to: %s\n' "$args[1]"
        case which
            if test (count $args) -gt 1
                _cp_fish_die 'usage: claude-profile which [name]'
                return 1
            end
            if test (count $args) -eq 1
                _cp_fish_validate_name "$args[1]" >/dev/null
                or return 1
                set -l profile (_cp_fish_profile_dir "$args[1]")
            else
                set -l default (_cp_fish_default_name)
                if test -z "$default"
                    _cp_fish_die 'no default profile set. Use: claude-profile default <name>'
                    return 1
                end
                set -l profile (_cp_fish_profile_dir "$default")
            end
            if not test -d "$profile"
                _cp_fish_die "profile does not exist"
                return 1
            end
            printf '%s\n' "$profile"
        case delete
            set -l force 0
            set -l name
            for argument in $args
                if test "$argument" = --force
                    set force 1
                else if test -n "$name"
                    _cp_fish_die "unexpected argument '$argument'"
                    return 1
                else
                    set name "$argument"
                end
            end
            if test -z "$name"
                _cp_fish_die 'usage: claude-profile delete <name> [--force]'
                return 1
            end
            _cp_fish_validate_name "$name" >/dev/null
            or return 1
            set -l profile (_cp_fish_profile_dir "$name")
            if not test -d "$profile"
                _cp_fish_die "profile '$name' does not exist"
                return 1
            end
            if test $force -eq 0
                read --prompt-str "Delete profile '$name' and all its data? [y/N] " confirmation
                if test $status -ne 0; or not string match -qi -r '^(y|yes)$' -- "$confirmation"
                    printf 'Cancelled.\n'
                    return 0
                end
            end
            command rm -rf "$profile"
            or return 1
            set -l default_file (_cp_fish_join "$data" .default)
            if test -f "$default_file"; and test (string collect < "$default_file" | string trim) = "$name"
                command rm -f "$default_file"
            end
            if test "$CLAUDE_CONFIG_DIR" = "$profile"
                set -e CLAUDE_CONFIG_DIR
                set -e CLAUDE_PROFILE_AUTO_SET
            end
            printf 'Deleted profile: %s\n' "$name"
        case skills
            _cp_fish_backend skills $args
        case version
            if test (count $args) -ne 0
                _cp_fish_die 'usage: claude-profile version'
                return 1
            end
            set -l version_file (_cp_fish_join (_cp_fish_install_dir) VERSION)
            if not test -s "$version_file"
                set version_file (_cp_fish_join "$__claude_profile_fish_source_dir" VERSION)
            end
            if test -s "$version_file"
                string trim < "$version_file"
            else
                printf 'unknown\n'
            end
        case update
            _cp_fish_backend update $args
        case '*'
            _cp_fish_die "unknown command '$command'. Run 'claude-profile help' for usage."
            return 1
    end
end

function __claude_profile_fish_complete_profiles
    set -l data (_cp_fish_data_dir)
    for entry in "$data"/*
        if test -d "$entry"; and test (path basename "$entry") != skills
            printf '%s\n' (path basename "$entry")
        end
    end
end

complete -c claude-profile -f -n '__fish_use_subcommand' -a 'use create list ls default local auto which skills version update delete help'
complete -c claude-profile -f -n '__fish_seen_subcommand_from use default which local delete' -a '(__claude_profile_fish_complete_profiles)'

_cp_fish_auto_switch
