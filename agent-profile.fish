# agent-profile.fish — source this in ~/.config/fish/config.fish
#
# Native Fish adapter for Antigravity (agy + GUI) and Codex. The Bash/Zsh
# adapter is intentionally not sourced here because Fish has different syntax.

function _ap_fish_die
    printf 'agent-profile: %s\n' $argv[1] >&2
end

function _ap_fish_join
    string join / $argv
end

function _ap_fish_data_dir
    if set -q AGENT_PROFILE_DATA_DIR[1]; and test -n "$AGENT_PROFILE_DATA_DIR"
        printf '%s\n' "$AGENT_PROFILE_DATA_DIR"
    else if set -q MSYSTEM[1]; and test -n "$MSYSTEM"; and set -q LOCALAPPDATA[1]; and test -n "$LOCALAPPDATA"; and type -q cygpath
        command cygpath -u "$LOCALAPPDATA/agent-profiles"
    else if set -q XDG_DATA_HOME[1]; and test -n "$XDG_DATA_HOME"
        _ap_fish_join "$XDG_DATA_HOME" agent-profiles
    else
        _ap_fish_join "$HOME" .local share agent-profiles
    end
end

function _ap_fish_native_path
    if set -q MSYSTEM[1]; and test -n "$MSYSTEM"; and type -q cygpath
        command cygpath -w "$argv[1]"
    else
        printf '%s\n' "$argv[1]"
    end
end

function _ap_fish_validate_name
    set -l name $argv[1]
    if test (count $argv) -eq 0; or test -z "$name"
        _ap_fish_die 'profile name must not be empty'
        return 1
    end
    if string match -q -- '.*' "$name"; or string match -q -- '*..*' "$name"; or not string match -rq '^[A-Za-z0-9_-]+$' -- "$name"
        _ap_fish_die "invalid profile name '$name': use only letters, digits, hyphens, underscores"
        return 1
    end
    return 0
end

function _ap_fish_provider
    switch $argv[1]
        case agy antigravity antigravity-cli antigravity-gui antigravity-ide
            printf 'antigravity\n'
        case codex
            printf 'codex\n'
        case '*'
            _ap_fish_die "unknown provider '$argv[1]' (use antigravity or codex)"
            return 1
    end
end

function _ap_fish_provider_dir
    _ap_fish_join (_ap_fish_data_dir) $argv[1]
end

function _ap_fish_profile_dir
    _ap_fish_validate_name $argv[2] >/dev/null
    or return 1
    _ap_fish_join (_ap_fish_provider_dir $argv[1]) $argv[2]
end

function _ap_fish_default_name
    set -l file (_ap_fish_join (_ap_fish_provider_dir $argv[1]) .default)
    if not test -f "$file"
        _ap_fish_die "no default profile set for $argv[1]"
        return 1
    end
    set -l name (string collect < "$file" | string trim)
    _ap_fish_validate_name "$name" >/dev/null
    or return 1
    printf '%s\n' "$name"
end

function _ap_fish_active_name
    switch $argv[1]
        case antigravity
            if set -q AGENT_PROFILE_ANTIGRAVITY_ACTIVE[1]
                printf '%s\n' "$AGENT_PROFILE_ANTIGRAVITY_ACTIVE"
            end
        case codex
            if set -q AGENT_PROFILE_CODEX_ACTIVE[1]
                printf '%s\n' "$AGENT_PROFILE_CODEX_ACTIVE"
            end
    end
end

function _ap_fish_selected_profile
    set -l provider $argv[1]
    set -l name (_ap_fish_active_name $provider)
    if test -z "$name"
        set name (_ap_fish_default_name $provider 2>/dev/null)
    end
    if test -z "$name"
        return 1
    end
    _ap_fish_validate_name "$name" >/dev/null
    or return 1
    set -l profile (_ap_fish_profile_dir $provider $name)
    if test -d "$profile"
        printf '%s\n' "$profile"
        return 0
    end
    return 1
end

function _ap_fish_gui_source_dir
    if set -q AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR[1]
        if test -d "$AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR"
            printf '%s\n' "$AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR"
        end
        return 0
    end
    set -l candidates
    switch (uname -s 2>/dev/null)
        case Darwin
            set candidates "$HOME/Library/Application Support/Antigravity IDE" "$HOME/Library/Application Support/Antigravity" "$HOME/.gemini/antigravity-ide"
        case '*'
            set -l config_root (_ap_fish_join "$HOME" .config)
            if set -q XDG_CONFIG_HOME[1]; and test -n "$XDG_CONFIG_HOME"
                set config_root "$XDG_CONFIG_HOME"
            end
            set candidates (_ap_fish_join "$config_root" 'Antigravity IDE') (_ap_fish_join "$config_root" Antigravity) (_ap_fish_join "$HOME" .gemini antigravity-ide) (_ap_fish_join "$HOME" .antigravity-ide)
    end
    for candidate in $candidates
        if test -d "$candidate"
            printf '%s\n' "$candidate"
            return 0
        end
    end
end

function _ap_fish_copy_tree
    set -l source $argv[1]
    set -l destination $argv[2]
    mkdir -p "$destination"
    or return 1
    command cp -R "$source/." "$destination/"
end

# Chromium's singleton files are symlinks naming the host and pid that owned the
# source instance (SingletonLock -> <host>-<pid>) plus a socket under that
# instance's temp dir. Copied into a new profile they can make Antigravity decide
# another instance already owns this user-data-dir and simply focus that window,
# which looks exactly like the profile failing to switch. They are pure runtime
# state, so drop them from every snapshot.
function _ap_fish_prune_gui_locks
    set -l target $argv[1]
    if not test -d "$target"
        return 0
    end
    command rm -f (_ap_fish_join "$target" SingletonLock) (_ap_fish_join "$target" SingletonCookie) (_ap_fish_join "$target" SingletonSocket) 2>/dev/null
    return 0
end

function _ap_fish_snapshot_live
    set -l provider $argv[1]
    set -l destination $argv[2]
    mkdir -p "$destination"
    or return 1
    switch $provider
        case antigravity
            if test -d "$HOME/.gemini"
                _ap_fish_copy_tree "$HOME/.gemini" (_ap_fish_join "$destination" home .gemini)
                or return 1
            end
            set -l gui (_ap_fish_gui_source_dir)
            if test -n "$gui"; and test -d "$gui"
                _ap_fish_copy_tree "$gui" (_ap_fish_join "$destination" gui-user-data)
                or return 1
            end
        case codex
            set -l codex_home "$HOME/.codex"
            if set -q CODEX_HOME[1]; and test -n "$CODEX_HOME"
                set codex_home "$CODEX_HOME"
            end
            if test -d "$codex_home"
                _ap_fish_copy_tree "$codex_home" "$destination"
                or return 1
            end
    end
end

function _ap_fish_copy_profile
    set -l provider $argv[1]
    set -l source $argv[2]
    set -l name $argv[3]
    set -l force $argv[4]
    set -l destination (_ap_fish_profile_dir $provider $name)
    or return 1
    set -l root (_ap_fish_provider_dir $provider)
    mkdir -p "$root"
    or begin
        _ap_fish_die "could not create profile directory '$root'"
        return 1
    end
    if test -e "$destination"; or test -L "$destination"
        if test "$force" != 1
            _ap_fish_die "profile '$name' already exists (use --force to replace it)"
            return 1
        end
    end
    set -l temporary "$destination.tmp.$fish_pid"
    command rm -rf "$temporary" 2>/dev/null
    mkdir -p "$temporary"
    or return 1
    set -l copy_status 0
    if test "$source" = live
        _ap_fish_snapshot_live $provider "$temporary"
        set copy_status $status
    else
        _ap_fish_validate_name "$source" >/dev/null
        or set copy_status 1
        if test $copy_status -eq 0
            set -l source_dir (_ap_fish_profile_dir $provider $source)
            if not test -d "$source_dir"
                _ap_fish_die "source profile '$source' does not exist"
                set copy_status 1
            else
                _ap_fish_copy_tree "$source_dir" "$temporary"
                set copy_status $status
            end
        end
    end
    if test $copy_status -ne 0
        _ap_fish_die 'could not copy profile data'
        command rm -rf "$temporary"
        return 1
    end
    _ap_fish_prune_gui_locks (_ap_fish_join "$temporary" gui-user-data)
    if test -e "$destination"; or test -L "$destination"
        command rm -rf "$destination"
        or begin
            _ap_fish_die "could not replace profile '$name'"
            command rm -rf "$temporary"
            return 1
        end
    end
    command mv "$temporary" "$destination"
    or begin
        _ap_fish_die "could not finalize profile '$name'"
        command rm -rf "$temporary"
        return 1
    end
    printf 'Copied %s profile to: %s\n' $provider $name
    if test "$source" = live; and test "$provider" = antigravity
        printf 'Note: OS keyring credentials are not copied; keyring-backed login may remain shared.\n' >&2
    end
    printf 'Profile directory: %s\n' "$destination"
end

function _ap_fish_has_data_arg
    for argument in $argv
        if test "$argument" = --user-data-dir; or string match -q -- '--user-data-dir=*' "$argument"
            return 0
        end
    end
    return 1
end

function _ap_fish_has_new_window_arg
    for argument in $argv
        if test "$argument" = --new-window
            return 0
        end
    end
    return 1
end

function _ap_fish_macos_gui_app
    switch (uname -s 2>/dev/null)
        case Darwin
        case '*'
            return 1
    end
    for app_path in /Applications/Antigravity.app "$HOME/Applications/Antigravity.app"
        set -l app_binary "$app_path/Contents/MacOS/Antigravity"
        if test -x "$app_binary"
            printf '%s\n' "$app_path"
            return 0
        end
    end
    return 1
end

function _ap_fish_macos_gui_command
    set -l app_path (_ap_fish_macos_gui_app)
    if test -n "$app_path"
        printf '%s/Contents/MacOS/Antigravity\n' "$app_path"
        return 0
    end
    return 1
end

# macOS finds the login keychain at $HOME/Library/Keychains, so a redirected HOME
# leaves the child with no keychain at all -- Chromium then cannot store its
# "Antigravity Safe Storage" key and macOS puts up "A keychain cannot be found to
# store antigravity". Point the profile at the real keychain instead. That key
# only encrypts the local cookie store at rest; the account itself lives in
# ~/.gemini, which stays per-profile, so sharing it costs no isolation.
function _ap_fish_link_macos_keychains
    set -l child_home $argv[1]
    if test (uname -s 2>/dev/null) != Darwin
        return 0
    end
    if not test -d "$HOME/Library/Keychains"
        return 0
    end
    set -l link_path (_ap_fish_join "$child_home" Library Keychains)
    # Never disturb a real directory or an existing link the user put here.
    if test -e "$link_path"; or test -L "$link_path"
        return 0
    end
    mkdir -p (_ap_fish_join "$child_home" Library) 2>/dev/null
    or return 0
    ln -s "$HOME/Library/Keychains" "$link_path" 2>/dev/null
    return 0
end

function _ap_fish_launch_cli
    set -l provider $argv[1]
    set -l launch_command $argv[2]
    set -l launch_args $argv[3..-1]
    set -l profile (_ap_fish_selected_profile $provider 2>/dev/null)
    if test $status -ne 0
        command $launch_command $launch_args
        return $status
    end
    mkdir -p (_ap_fish_join "$profile" home) 2>/dev/null
    _ap_fish_link_macos_keychains (_ap_fish_join "$profile" home)
    set -l child_home (_ap_fish_native_path (_ap_fish_join "$profile" home))
    if set -q MSYSTEM[1]; and test -n "$MSYSTEM"
        env HOME="$child_home" USERPROFILE="$child_home" $launch_command $launch_args
    else
        env HOME="$child_home" $launch_command $launch_args
    end
end

function _ap_fish_gui_launcher
    if set -q AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND[1]; and test -n "$AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND"
        printf '%s\n' "$AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND"
        return 0
    end
    set -l gui_path (command -s antigravity-ide)
    if test -n "$gui_path"
        printf '%s\n' "$gui_path"
        return 0
    end
    set gui_path (command -s antigravity)
    if test -n "$gui_path"
        printf '%s\n' "$gui_path"
        return 0
    end
    set -l gui_app (_ap_fish_macos_gui_app)
    if test -n "$gui_app"
        printf 'app:%s\n' "$gui_app"
        return 0
    end
    _ap_fish_die 'could not find antigravity GUI; set AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND'
    return 127
end

function _ap_fish_gui_command
    set -l gui_launcher (_ap_fish_gui_launcher)
    or return $status
    if string match -q -- 'app:*' "$gui_launcher"
        printf '%s/Contents/MacOS/Antigravity\n' (string replace 'app:' '' "$gui_launcher")
    else
        printf '%s\n' "$gui_launcher"
    end
end

# open(1) has supported --env for many releases, but fall back gracefully if this
# macOS predates it. An unrecognized option makes open print its usage and exit
# without launching anything, so probing this way has no side effects.
function _ap_fish_open_supports_env
    /usr/bin/open --ap-probe-unsupported-option 2>&1 | string match -q -- '*--env*'
end

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
function _ap_fish_launch_gui_run
    set -l launch_mode $argv[1]
    set -l launch_target $argv[2]
    set -l launch_home $argv[3]
    set -l launch_args $argv[4..-1]
    if test "$launch_mode" != app
        if set -q MSYSTEM[1]; and test -n "$MSYSTEM"
            env HOME="$launch_home" USERPROFILE="$launch_home" $launch_target $launch_args
        else
            env HOME="$launch_home" $launch_target $launch_args
        end
        return $status
    end
    if _ap_fish_open_supports_env
        command /usr/bin/open -n --env HOME="$launch_home" -a "$launch_target" --args $launch_args
        return $status
    end
    set -l gui_bin (_ap_fish_macos_gui_command)
    or return 127
    # Without --env the binary has to be run directly; background and disown it so
    # it outlives this shell instead of being killed when the shell exits.
    env HOME="$launch_home" $gui_bin $launch_args >/dev/null 2>&1 &
    disown
    return 0
end

function _ap_fish_launch_gui
    set -l gui_launcher (_ap_fish_gui_launcher)
    or return $status
    set -l launch_mode command
    set -l launch_target "$gui_launcher"
    if string match -q -- 'app:*' "$gui_launcher"
        set launch_mode app
        set launch_target (string replace 'app:' '' "$gui_launcher")
    end
    set -l launch_args $argv
    set -l profile (_ap_fish_selected_profile antigravity 2>/dev/null)
    if test $status -ne 0
        if test "$launch_mode" = app
            command /usr/bin/open -n -a "$launch_target" --args $launch_args
        else
            command $launch_target $launch_args
        end
        return $status
    end
    mkdir -p (_ap_fish_join "$profile" home) (_ap_fish_join "$profile" gui-user-data) 2>/dev/null
    _ap_fish_link_macos_keychains (_ap_fish_join "$profile" home)
    set -l launch_home (_ap_fish_native_path (_ap_fish_join "$profile" home))
    if not _ap_fish_has_data_arg $launch_args
        # The "=" form is required: the app bundle is a plain Electron app whose
        # Chromium parser only understands --switch=value and silently ignores the
        # space-separated spelling. A VS Code derived antigravity-ide accepts it too.
        set -l gui_data (_ap_fish_native_path (_ap_fish_join "$profile" gui-user-data))
        set launch_args "--user-data-dir=$gui_data" $launch_args
    end
    _ap_fish_launch_gui_run "$launch_mode" "$launch_target" "$launch_home" $launch_args
end

# The app bundle takes no --new-window -- that is a VS Code flag and is inert
# here; a separate HOME plus a separate user-data-dir is what lets another
# profile open alongside the running one. Keep injecting it for a VS Code derived
# antigravity-ide on PATH, where it is the real new-window mechanism.
function _ap_fish_restart_gui
    set -l launch_args $argv
    set -l gui_launcher (_ap_fish_gui_launcher)
    or return $status
    if not string match -q -- 'app:*' "$gui_launcher"
        if not _ap_fish_has_new_window_arg $launch_args
            set launch_args --new-window $launch_args
        end
    end
    _ap_fish_launch_gui $launch_args
end

function _ap_fish_agent_help
    printf '%s\n' \
        'Usage: agent-profile <provider> <command> [args...]' \
        '       agent-profile <command> <provider> [args...]' \
        '' \
        'Providers:' \
        '  antigravity  Antigravity CLI (agy) and GUI' \
        '  codex        OpenAI Codex CLI' \
        '' \
        'Commands:' \
        '  create <provider> <name>                  Create an empty profile' \
        '  copy <provider> <name> [--force]          Copy current live data' \
        '  copy <provider> <source> <name> [--force] Copy a managed profile' \
        '  list <provider>                           List profiles' \
        '  default <provider> [name]                 Get or set the default' \
        '  use <provider> <name>                     Select a profile for this shell' \
        '  which <provider> [name]                   Print a profile directory' \
        '  restart <provider> [args...]              Open a fresh Antigravity GUI window' \
        '  delete <provider> <name> [--force]        Delete a profile' \
        '' \
        'Aliases: agy-profile, antigravity-profile, codex-profile'
end

function agent-profile
    set -l input $argv
    if test (count $input) -eq 0; or contains -- $input[1] help -h --help
        _ap_fish_agent_help
        return 0
    end
    set -l commands create copy list ls default use which restart delete status
    set -l command
    set -l provider_arg
    set -l command_args
    if contains -- $input[1] $commands
        set command $input[1]
        if test (count $input) -lt 2
            _ap_fish_die 'missing provider'
            return 1
        end
        set provider_arg $input[2]
        set command_args $input[3..-1]
    else
        set provider_arg $input[1]
        if test (count $input) -gt 1
            set command $input[2]
            set command_args $input[3..-1]
        else
            set command status
        end
    end
    set -l provider (_ap_fish_provider $provider_arg)
    or return 1
    switch $command
        case status
            set -l default_name (_ap_fish_default_name $provider 2>/dev/null)
            set -l active_name (_ap_fish_active_name $provider)
            set -l selected (_ap_fish_selected_profile $provider 2>/dev/null)
            printf 'Provider: %s\n' $provider
            printf 'Default: %s\n' (test -n "$default_name"; and printf '%s' "$default_name"; or printf '<none>')
            printf 'Active: %s\n' (test -n "$active_name"; and printf '%s' "$active_name"; or printf '<default>')
            test -n "$selected"; and printf 'Path: %s\n' "$selected"
        case create
            if test (count $command_args) -ne 1
                _ap_fish_die "usage: agent-profile create $provider <name>"
                return 1
            end
            _ap_fish_validate_name $command_args[1] >/dev/null
            or return 1
            set -l path (_ap_fish_profile_dir $provider $command_args[1])
            if test -e "$path"
                _ap_fish_die "profile '$command_args[1]' already exists"
                return 1
            end
            mkdir -p "$path"
            or return 1
            printf 'Created %s profile: %s\n' $provider $command_args[1]
            printf 'Profile directory: %s\n' "$path"
        case copy
            set -l force 0
            set -l positional
            for argument in $command_args
                switch $argument
                    case --force
                        set force 1
                    case '-*'
                        _ap_fish_die "unknown option '$argument'"
                        return 1
                    case '*'
                        set positional $positional $argument
                end
            end
            set -l source
            set -l name
            if test (count $positional) -eq 1
                set source live
                set name $positional[1]
            else if test (count $positional) -eq 2
                set source $positional[1]
                set name $positional[2]
                if test "$source" = default
                    set source (_ap_fish_default_name $provider)
                    or return 1
                end
            else
                _ap_fish_die "usage: agent-profile copy $provider [source] <name> [--force]"
                return 1
            end
            _ap_fish_validate_name "$name" >/dev/null
            or return 1
            _ap_fish_copy_profile $provider $source $name $force
        case list ls
            if test (count $command_args) -ne 0
                _ap_fish_die "usage: agent-profile list $provider"
                return 1
            end
            set -l root (_ap_fish_provider_dir $provider)
            if not test -d "$root"
                printf 'No %s profiles found. Create one with: agent-profile create %s <name>\n' $provider $provider
                return 0
            end
            set -l default_name (_ap_fish_default_name $provider 2>/dev/null)
            set -l active_name (_ap_fish_active_name $provider)
            set -l found 0
            for entry in "$root"/*
                if not test -d "$entry"
                    continue
                end
                set found 1
                set -l entry_name (path basename "$entry")
                set -l suffix
                if test "$entry_name" = "$default_name"; and test "$entry_name" = "$active_name"
                    set suffix ' (default, active)'
                else if test "$entry_name" = "$default_name"
                    set suffix ' (default)'
                else if test "$entry_name" = "$active_name"
                    set suffix ' (active)'
                end
                printf '   %s%s\n' $entry_name "$suffix"
            end
            if test $found -eq 0
                printf 'No %s profiles found. Create one with: agent-profile create %s <name>\n' $provider $provider
            end
        case default
            if test (count $command_args) -eq 0
                _ap_fish_default_name $provider
                return $status
            end
            if test (count $command_args) -ne 1
                _ap_fish_die "usage: agent-profile default $provider [name]"
                return 1
            end
            _ap_fish_validate_name $command_args[1] >/dev/null
            or return 1
            set -l path (_ap_fish_profile_dir $provider $command_args[1])
            if not test -d "$path"
                _ap_fish_die "profile '$command_args[1]' does not exist"
                return 1
            end
            set -l root (_ap_fish_provider_dir $provider)
            mkdir -p "$root"
            or return 1
            printf '%s' $command_args[1] > (_ap_fish_join "$root" .default)
            printf 'Default %s profile set to: %s\n' $provider $command_args[1]
        case use
            if test (count $command_args) -ne 1
                _ap_fish_die "usage: agent-profile use $provider <name>"
                return 1
            end
            _ap_fish_validate_name $command_args[1] >/dev/null
            or return 1
            set -l path (_ap_fish_profile_dir $provider $command_args[1])
            if not test -d "$path"
                _ap_fish_die "profile '$command_args[1]' does not exist"
                return 1
            end
            if test "$provider" = antigravity
                set -gx AGENT_PROFILE_ANTIGRAVITY_ACTIVE $command_args[1]
            else
                set -gx AGENT_PROFILE_CODEX_ACTIVE $command_args[1]
            end
            printf 'Switched to %s profile: %s\n' $provider $command_args[1]
        case which
            if test (count $command_args) -gt 1
                _ap_fish_die "usage: agent-profile which $provider [name]"
                return 1
            end
            # Declared out here on purpose: `set -l` inside an if/else block is
            # scoped to that block, so assigning it there leaves $path empty below.
            set -l path
            if test (count $command_args) -eq 1
                _ap_fish_validate_name $command_args[1] >/dev/null
                or return 1
                set path (_ap_fish_profile_dir $provider $command_args[1])
            else
                set path (_ap_fish_selected_profile $provider)
                or begin
                    _ap_fish_die "no active or default profile set for $provider"
                    return 1
                end
            end
            test -d "$path"
            or begin
                _ap_fish_die "profile '$command_args[1]' does not exist"
                return 1
            end
            printf '%s\n' "$path"
        case restart
            if test "$provider" != antigravity
                _ap_fish_die 'restart is only supported for antigravity'
                return 1
            end
            _ap_fish_restart_gui $command_args
        case delete
            set -l force 0
            set -l names
            for argument in $command_args
                if test "$argument" = --force
                    set force 1
                else
                    set names $names $argument
                end
            end
            if test (count $names) -ne 1
                _ap_fish_die "usage: agent-profile delete $provider <name> [--force]"
                return 1
            end
            _ap_fish_validate_name $names[1] >/dev/null
            or return 1
            set -l path (_ap_fish_profile_dir $provider $names[1])
            if not test -d "$path"
                _ap_fish_die "profile '$names[1]' does not exist"
                return 1
            end
            if test $force -ne 1
                read --prompt-str "Delete $provider profile '$names[1]' and all its data? [y/N] " confirmation
                if test $status -ne 0; or not string match -qi -r '^(y|yes)$' -- "$confirmation"
                    printf 'Cancelled.\n'
                    return 0
                end
            end
            command rm -rf "$path"
            or return 1
            set -l root (_ap_fish_provider_dir $provider)
            set -l default_file (_ap_fish_join "$root" .default)
            if test -f "$default_file"; and test (string collect < "$default_file" | string trim) = "$names[1]"
                command rm -f "$default_file"
            end
            printf 'Deleted %s profile: %s\n' $provider $names[1]
        case '*'
            _ap_fish_die "unknown command '$command'. Run 'agent-profile help' for usage."
            return 1
    end
end

function agy
    _ap_fish_launch_cli antigravity (set -q AGENT_PROFILE_AGY_COMMAND[1]; and printf '%s' "$AGENT_PROFILE_AGY_COMMAND"; or printf 'agy') $argv
end

function antigravity
    _ap_fish_launch_gui $argv
end

function antigravity-ide
    _ap_fish_launch_gui $argv
end

function codex
    set -l launch_command codex
    if set -q AGENT_PROFILE_CODEX_COMMAND[1]; and test -n "$AGENT_PROFILE_CODEX_COMMAND"
        set launch_command "$AGENT_PROFILE_CODEX_COMMAND"
    end
    set -l profile (_ap_fish_selected_profile codex 2>/dev/null)
    if test $status -ne 0
        command $launch_command $argv
        return $status
    end
    set -l native_profile (_ap_fish_native_path "$profile")
    env CODEX_HOME="$native_profile" $launch_command $argv
end

function agy-profile
    agent-profile antigravity $argv
end

function antigravity-profile
    agent-profile antigravity $argv
end

function codex-profile
    agent-profile codex $argv
end
