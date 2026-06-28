# claude-profile.fish — Source this in ~/.config/fish/config.fish
#
#   source "$HOME/.local/share/claude-profile/claude-profile.fish"
#
# Native fish port of claude-profile.sh. Fish is NOT POSIX-compatible, so the
# .sh file cannot be sourced here — it fails at parse time. This file is the
# fish equivalent and shares the same on-disk profile layout, so profiles
# created from bash/zsh are visible here and vice versa.
#
# Provides:
#   claude           — runs Claude Code with the active/default profile
#   claude-profile   — manage profiles (use, create, list, default, which,
#                      delete, rename, clone, exec, show, edit)
#
# Supported on Linux, macOS, and WSL. (Fish does not run under Git Bash/MSYS,
# so the cygpath handling from the POSIX version is intentionally omitted.)

# --- Internal helpers ---

function _cp_die --description 'Print a claude-profile error to stderr'
    printf 'claude-profile: %s\n' "$argv[1]" >&2
end

# Resolves the profile data directory, matching the POSIX implementation's
# $XDG_DATA_HOME/claude-profiles (default ~/.local/share/claude-profiles).
function _cp_data_dir --description 'Resolve the claude-profile data directory'
    if set -q XDG_DATA_HOME; and test -n "$XDG_DATA_HOME"
        printf '%s\n' "$XDG_DATA_HOME/claude-profiles"
    else
        printf '%s\n' "$HOME/.local/share/claude-profiles"
    end
end

function _cp_validate_name --description 'Validate a profile name (mirrors the POSIX rules)'
    set -l name $argv[1]
    if test -z "$name"
        _cp_die "profile name must not be empty"
        return 1
    end
    if string match -rq '^\.' -- $name
        _cp_die "invalid profile name '$name': must not start with '.'"
        return 1
    end
    if string match -q '*..*' -- $name
        _cp_die "invalid profile name '$name': must not contain '..'"
        return 1
    end
    if string match -q '*/*' -- $name
        _cp_die "invalid profile name '$name': must not contain '/'"
        return 1
    end
    if string match -q '*\\\\*' -- $name
        _cp_die "invalid profile name '$name': must not contain '\\'"
        return 1
    end
    if string match -rq '[^A-Za-z0-9_-]' -- $name
        _cp_die "invalid profile name '$name': use only letters, digits, hyphens, underscores"
        return 1
    end
    return 0
end

# Resolves a profile name to its directory, erroring if it does not exist.
# Echoes the directory on success.
function _cp_require_profile --description 'Validate a name and require its directory to exist'
    set -l name $argv[1]
    _cp_validate_name "$name"; or return 1
    set -l dir (_cp_data_dir)/$name
    if not test -d "$dir"
        _cp_die "profile '$name' does not exist. Create it with: claude-profile create $name"
        return 1
    end
    printf '%s\n' "$dir"
end

# Derives the managed-profile name from CLAUDE_CONFIG_DIR, if it points inside
# the data directory. Echoes nothing when no managed profile is active.
function _cp_active_name --description 'Echo the active managed profile name, if any'
    set -q CLAUDE_CONFIG_DIR; or return 0
    test -n "$CLAUDE_CONFIG_DIR"; or return 0
    set -l data (_cp_data_dir)
    if string match -q "$data/*" -- $CLAUDE_CONFIG_DIR
        basename "$CLAUDE_CONFIG_DIR"
    end
end

# --- claude() wrapper ---
# Auto-resolves the default profile before calling the real claude binary.
# If CLAUDE_CONFIG_DIR is already set (e.g. via 'claude-profile use'), it
# passes through without overriding.

function claude --description 'Run Claude Code with the active/default profile'
    if not set -q CLAUDE_CONFIG_DIR; or test -z "$CLAUDE_CONFIG_DIR"
        set -l data (_cp_data_dir)
        set -l deffile "$data/.default"
        if test -f "$deffile"
            set -l name (cat "$deffile")
            if test -n "$name"; and test -d "$data/$name"
                set -gx CLAUDE_CONFIG_DIR "$data/$name"
            end
        end
    end
    command claude $argv
end

# --- claude-profile() management function ---

function claude-profile --description 'Manage Claude Code profiles'
    set -l data (_cp_data_dir)
    set -l default_file "$data/.default"
    set -l cmd $argv[1]
    # Remaining args after the subcommand.
    set -l rest $argv[2..-1]

    switch "$cmd"
        case use
            set -l name $rest[1]
            if test -z "$name"
                _cp_die "usage: claude-profile use <name>"
                return 1
            end
            if test (count $rest) -gt 1
                _cp_die "unexpected argument after profile name: '$rest[2]'"
                return 1
            end
            set -l dir (_cp_require_profile "$name"); or return 1
            set -gx CLAUDE_CONFIG_DIR "$dir"
            printf 'Switched to profile: %s\n' "$name"

        case create
            set -l do_init 0
            set -l name ""
            for arg in $rest
                switch "$arg"
                    case --init
                        set do_init 1
                    case '-*'
                        _cp_die "unknown option '$arg'"
                        return 1
                    case '*'
                        if test -n "$name"
                            _cp_die "unexpected argument '$arg'"
                            return 1
                        end
                        set name "$arg"
                end
            end
            if test -z "$name"
                _cp_die "usage: claude-profile create [--init] <name>"
                return 1
            end
            _cp_validate_name "$name"; or return 1
            set -l dir "$data/$name"
            if test -d "$dir"
                _cp_die "profile '$name' already exists"
                return 1
            end
            mkdir -p "$dir"; or return 1
            printf 'Created profile: %s\n' "$name"
            printf 'Config directory: %s\n' "$dir"
            if test "$do_init" -eq 1
                set -l settings "$dir/settings.json"
                _cp_write_skeleton "$settings"
                printf 'Config skeleton written to: %s\n' "$settings"
                printf 'Tip: remove "ANTHROPIC_BASE_URL" if using the default Anthropic endpoint.\n'
                if set -q VISUAL; and test -n "$VISUAL"
                    eval $VISUAL "$settings"
                else if set -q EDITOR; and test -n "$EDITOR"
                    eval $EDITOR "$settings"
                end
            end

        case list ls
            if not test -d "$data"
                printf 'No profiles found. Create one with: claude-profile create <name>\n'
                return 0
            end
            set -l cur_default ""
            if test -f "$default_file"
                set cur_default (cat "$default_file")
            end
            set -l active (_cp_active_name)
            set -l found 0
            for entry in "$data"/*/
                test -d "$entry"; or continue
                set -l name (basename "$entry")
                set found 1
                set -l is_default 0
                set -l is_active 0
                test "$name" = "$cur_default"; and set is_default 1
                test "$name" = "$active"; and set is_active 1
                if test "$is_default" -eq 1; and test "$is_active" -eq 1
                    printf '>* %s (default, active)\n' "$name"
                else if test "$is_default" -eq 1
                    printf ' * %s (default)\n' "$name"
                else if test "$is_active" -eq 1
                    printf '>  %s (active)\n' "$name"
                else
                    printf '   %s\n' "$name"
                end
            end
            if test "$found" -eq 0
                printf 'No profiles found. Create one with: claude-profile create <name>\n'
            end

        case default
            set -l name $rest[1]
            if test -z "$name"
                if test -f "$default_file"
                    set -l cur (cat "$default_file")
                    if test -n "$cur"
                        printf '%s\n' "$cur"
                    else
                        _cp_die "default profile file is empty. Set one with: claude-profile default <name>"
                        return 1
                    end
                else
                    _cp_die "no default profile set. Set one with: claude-profile default <name>"
                    return 1
                end
                return 0
            end
            _cp_require_profile "$name" >/dev/null; or return 1
            mkdir -p "$data"; or return 1
            printf '%s' "$name" >"$default_file"
            printf 'Default profile set to: %s\n' "$name"

        case which
            set -l name $rest[1]
            if test -n "$name"
                set -l dir (_cp_require_profile "$name"); or return 1
                printf '%s\n' "$dir"
            else
                if not test -f "$default_file"
                    _cp_die "no default profile set. Use: claude-profile default <name>"
                    return 1
                end
                set -l cur (cat "$default_file")
                if test -z "$cur"
                    _cp_die "default profile file is empty. Set one with: claude-profile default <name>"
                    return 1
                end
                set -l dir (_cp_require_profile "$cur"); or return 1
                printf '%s\n' "$dir"
            end

        case delete rm
            set -l name $rest[1]
            if test -z "$name"
                _cp_die "usage: claude-profile delete <name>"
                return 1
            end
            _cp_validate_name "$name"; or return 1
            set -l dir "$data/$name"
            if not test -d "$dir"
                _cp_die "profile '$name' does not exist"
                return 1
            end
            read -l -P "Delete profile \"$name\" and all its data? [y/N] " confirm
            switch "$confirm"
                case y Y yes YES Yes
                    rm -rf "$dir"
                    printf 'Deleted profile: %s\n' "$name"
                    if test -f "$default_file"
                        set -l cur (cat "$default_file")
                        if test "$cur" = "$name"
                            rm -f "$default_file"
                            printf 'Cleared default profile (was "%s")\n' "$name"
                        end
                    end
                    if set -q CLAUDE_CONFIG_DIR; and test "$CLAUDE_CONFIG_DIR" = "$dir"
                        set -e CLAUDE_CONFIG_DIR
                        printf 'Cleared active profile (was "%s")\n' "$name"
                    end
                case '*'
                    printf 'Cancelled.\n'
            end

        case rename mv
            set -l old $rest[1]
            set -l new $rest[2]
            if test -z "$old"; or test -z "$new"
                _cp_die "usage: claude-profile rename <old> <new>"
                return 1
            end
            if test (count $rest) -gt 2
                _cp_die "unexpected argument: '$rest[3]'"
                return 1
            end
            set -l old_dir (_cp_require_profile "$old"); or return 1
            _cp_validate_name "$new"; or return 1
            set -l new_dir "$data/$new"
            if test -d "$new_dir"
                _cp_die "profile '$new' already exists"
                return 1
            end
            mv "$old_dir" "$new_dir"; or return 1
            printf 'Renamed profile: %s -> %s\n' "$old" "$new"
            # Follow the rename through default and active pointers.
            if test -f "$default_file"; and test (cat "$default_file") = "$old"
                printf '%s' "$new" >"$default_file"
                printf 'Updated default profile to: %s\n' "$new"
            end
            if set -q CLAUDE_CONFIG_DIR; and test "$CLAUDE_CONFIG_DIR" = "$old_dir"
                set -gx CLAUDE_CONFIG_DIR "$new_dir"
                printf 'Updated active profile to: %s\n' "$new"
            end

        case clone copy cp
            set -l src $rest[1]
            set -l dst $rest[2]
            if test -z "$src"; or test -z "$dst"
                _cp_die "usage: claude-profile clone <source> <dest>"
                return 1
            end
            if test (count $rest) -gt 2
                _cp_die "unexpected argument: '$rest[3]'"
                return 1
            end
            set -l src_dir (_cp_require_profile "$src"); or return 1
            _cp_validate_name "$dst"; or return 1
            set -l dst_dir "$data/$dst"
            if test -d "$dst_dir"
                _cp_die "profile '$dst' already exists"
                return 1
            end
            cp -R "$src_dir" "$dst_dir"; or return 1
            printf 'Cloned profile: %s -> %s\n' "$src" "$dst"
            printf 'Config directory: %s\n' "$dst_dir"

        case exec run
            set -l name $rest[1]
            if test -z "$name"
                _cp_die "usage: claude-profile exec <name> [--] [claude args...]"
                return 1
            end
            set -l dir (_cp_require_profile "$name"); or return 1
            set -l fwd $rest[2..-1]
            # Allow an optional -- separator before the claude args.
            if test (count $fwd) -gt 0; and test "$fwd[1]" = "--"
                set fwd $fwd[2..-1]
            end
            # `env` invokes the real binary (not this wrapper) with the profile
            # set for this one command only — the session env is untouched.
            env CLAUDE_CONFIG_DIR="$dir" claude $fwd

        case show cat
            set -l name $rest[1]
            if test -z "$name"
                if not test -f "$default_file"
                    _cp_die "usage: claude-profile show <name> (no default profile set)"
                    return 1
                end
                set name (cat "$default_file")
            end
            set -l dir (_cp_require_profile "$name"); or return 1
            set -l settings "$dir/settings.json"
            if not test -f "$settings"
                _cp_die "profile '$name' has no settings.json. Create one with: claude-profile create --init $name"
                return 1
            end
            cat "$settings"

        case edit
            set -l name $rest[1]
            if test -z "$name"
                if not test -f "$default_file"
                    _cp_die "usage: claude-profile edit <name> (no default profile set)"
                    return 1
                end
                set name (cat "$default_file")
            end
            set -l dir (_cp_require_profile "$name"); or return 1
            set -l settings "$dir/settings.json"
            if not test -f "$settings"
                _cp_write_skeleton "$settings"
                printf 'Created config skeleton: %s\n' "$settings"
            end
            if set -q VISUAL; and test -n "$VISUAL"
                eval $VISUAL "$settings"
            else if set -q EDITOR; and test -n "$EDITOR"
                eval $EDITOR "$settings"
            else
                _cp_die "no \$VISUAL or \$EDITOR set; settings file is at: $settings"
                return 1
            end

        case help -h --help
            _cp_help

        case ""
            # Bare invocation: show status.
            set -l active (_cp_active_name)
            if test -n "$active"
                printf 'Active profile: %s\n' "$active"
                printf 'Config directory: %s\n' "$CLAUDE_CONFIG_DIR"
            else if set -q CLAUDE_CONFIG_DIR; and test -n "$CLAUDE_CONFIG_DIR"
                printf 'Active config directory: %s (not a managed profile)\n' "$CLAUDE_CONFIG_DIR"
            else
                printf 'No active profile\n'
            end
            set -l cur_default ""
            if test -f "$default_file"
                set cur_default (cat "$default_file")
            end
            if test -n "$cur_default"
                printf 'Default profile: %s\n' "$cur_default"
            else
                printf 'No default profile set\n'
            end

        case '*'
            _cp_die "unknown command '$cmd'. Run 'claude-profile help' for usage."
            return 1
    end
end

function _cp_write_skeleton --description 'Write a settings.json skeleton to the given path'
    printf '%s\n' '{
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
}' >"$argv[1]"
end

function _cp_help --description 'Print claude-profile usage'
    printf '%s\n' 'Usage: claude-profile [command] [args...]

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
    show [name]             Print a profile'\''s settings.json (default profile if omitted)
    edit [name]             Open a profile'\''s settings.json in $VISUAL/$EDITOR
    help, -h, --help        Show this help message

The claude command automatically uses the default profile. Use
'\''claude-profile use <name>'\'' to override for the current session.

Examples:
    claude-profile create --init work
    claude-profile default work
    claude-profile use work
    claude                          # runs with "work" profile
    claude-profile exec personal -- --version
    claude-profile clone work work-experiment'
end

# --- Completions ---

function __cp_complete_profiles --description 'List profile names for completion'
    set -l data (_cp_data_dir)
    test -d "$data"; or return 0
    for entry in "$data"/*/
        test -d "$entry"; or continue
        basename "$entry"
    end
end

complete -c claude-profile -f
complete -c claude-profile -n __fish_use_subcommand -a use -d 'Switch session to a profile'
complete -c claude-profile -n __fish_use_subcommand -a create -d 'Create a new profile'
complete -c claude-profile -n __fish_use_subcommand -a 'list ls' -d 'List all profiles'
complete -c claude-profile -n __fish_use_subcommand -a default -d 'Get or set the default profile'
complete -c claude-profile -n __fish_use_subcommand -a which -d 'Show a profile config directory'
complete -c claude-profile -n __fish_use_subcommand -a 'delete rm' -d 'Delete a profile'
complete -c claude-profile -n __fish_use_subcommand -a 'rename mv' -d 'Rename a profile'
complete -c claude-profile -n __fish_use_subcommand -a 'clone copy cp' -d 'Duplicate a profile'
complete -c claude-profile -n __fish_use_subcommand -a 'exec run' -d 'Run claude with a profile once'
complete -c claude-profile -n __fish_use_subcommand -a 'show cat' -d 'Print a profile settings.json'
complete -c claude-profile -n __fish_use_subcommand -a edit -d 'Edit a profile settings.json'
complete -c claude-profile -n __fish_use_subcommand -a help -d 'Show help'
complete -c claude-profile -n '__fish_seen_subcommand_from use default which delete rm rename mv clone copy cp exec run show cat edit' -a '(__cp_complete_profiles)'
complete -c claude-profile -n '__fish_seen_subcommand_from create' -l init -d 'Write a settings.json skeleton'
