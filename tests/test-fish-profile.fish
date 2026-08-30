#!/usr/bin/env fish

# Dependency-free Fish smoke tests for both profile adapters.

set -l script_dir (path dirname (status filename))
set -g test_root (mktemp -d /tmp/fish-profile-test.XXXXXX)
set -g home_dir "$test_root/home"
set -g data_dir "$test_root/data"
set -g bin_dir "$test_root/bin"
set -g gui_source "$test_root/gui-source"
set -g pass_count 0
set -g fail_count 0

mkdir -p "$home_dir/.gemini/antigravity-cli" "$gui_source/User" "$bin_dir"

# Captured before HOME is redirected into the sandbox: the macOS keychain tests
# need the caller's real login keychain directory, which is the thing the adapter
# links into a profile home.
set -g real_keychains "$HOME/Library/Keychains"

set -gx HOME $home_dir
set -gx XDG_DATA_HOME $data_dir
set -gx AGENT_PROFILE_DATA_DIR "$data_dir/agent-profiles"
set -gx PATH $bin_dir $PATH
set -gx AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR $gui_source
set -gx CLAUDE_PROFILE_NO_UPDATE_CHECK 1
set -gx CLAUDE_PROFILE_AUTO_QUIET 1

# Keep inherited session state from affecting the assertions.
for variable_name in CLAUDE_CONFIG_DIR CLAUDE_PROFILE_AUTO_SET AGENT_PROFILE_ANTIGRAVITY_ACTIVE AGENT_PROFILE_CODEX_ACTIVE __claude_profile_auto_off __claude_profile_auto_last_pwd
    set -e $variable_name 2>/dev/null
end

# Do not let an older globally installed adapter mask the files under test.
for function_name in agent-profile antigravity antigravity-ide agy codex agy-profile antigravity-profile codex-profile claude claude-profile
    functions -e $function_name 2>/dev/null
end

source "$script_dir/../agent-profile.fish"
source "$script_dir/../claude-profile.fish"

if not functions -q agent-profile; or not functions -q claude-profile
    printf 'required Fish profile functions are not defined\n' >&2
    rm -rf "$test_root"
    exit 1
end

function assert_file_contains
    set -l file $argv[1]
    set -l expected $argv[2]
    grep -Fqx -- "$expected" "$file"
end

# The app-bundle fallback launch detaches the GUI, so its log is not there the
# moment the wrapper returns. Poll for it instead of racing it.
function wait_for_file_line
    set -l file $argv[1]
    set -l expected $argv[2]
    set -l limit 100
    if set -q argv[3]
        set limit $argv[3]
    end
    set -l attempts 0
    while test $attempts -lt $limit
        if test -f "$file"; and assert_file_contains "$file" "$expected"
            return 0
        end
        sleep 0.05
        set attempts (math $attempts + 1)
    end
    return 1
end

# The GUI stub records the argv it received and the HOME it inherited, mirroring
# the agy stub. HOME is the knob that actually selects the Antigravity account
# (it resolves ~/.gemini), so the launch tests have to see it, not just the flags.
function write_gui_stub
    printf '%s\n' '#!/bin/sh' 'printf "GUI_ARGS=%s\\n" "$*" > "$AGENT_PROFILE_TEST_LOG"' 'env | grep "^HOME=" >> "$AGENT_PROFILE_TEST_LOG"' > "$bin_dir/antigravity"
    chmod +x "$bin_dir/antigravity"
end

# The keychain link only exists on macOS, and it needs a real login keychain
# directory to point at, so skip cleanly elsewhere the way the app-bundle tests do.
function macos_keychain_supported
    if test (uname -s 2>/dev/null) != Darwin
        return 1
    end
    test -d "$real_keychains"
end

# The adapter links whatever $HOME/Library/Keychains it finds, and this suite has
# redirected HOME into the sandbox -- so point the sandbox home's keychain
# directory at the caller's real one. macOS resolves the login keychain through
# both hops, which keeps the security(1) assertion honest without this test ever
# creating or writing anything inside the real keychain directory.
function setup_sandbox_keychains
    macos_keychain_supported
    or return 1
    mkdir -p "$HOME/Library"
    or return 1
    if test -L "$HOME/Library/Keychains"
        return 0
    end
    ln -s "$real_keychains" "$HOME/Library/Keychains"
end

# stat -L follows the link, so comparing device and inode asserts that the link
# really lands on the caller's keychain directory rather than merely spelling a
# path that looks like it.
function assert_keychain_link
    set -l link "$argv[1]/Library/Keychains"
    if not test -L "$link"
        printf 'expected %s to be a symlink into the login keychain directory\n' "$link" >&2
        return 1
    end
    if not test -d "$link"
        printf 'expected %s to resolve to a directory, not dangle\n' "$link" >&2
        return 1
    end
    set -l linked_id (command stat -L -f '%d:%i' "$link" 2>/dev/null)
    set -l real_id (command stat -L -f '%d:%i' "$real_keychains" 2>/dev/null)
    if test -z "$real_id"; or test "$linked_id" != "$real_id"
        printf 'expected %s to resolve to %s\n' "$link" "$real_keychains" >&2
        return 1
    end
    return 0
end

function pass_test
    set -g pass_count (math $pass_count + 1)
    printf 'ok - %s\n' $argv[1]
end

function fail_test
    set -g fail_count (math $fail_count + 1)
    printf 'not ok - %s\n' $argv[1]
end

function run_test
    set -l name $argv[1]
    $name
    if test $status -eq 0
        pass_test $name
    else
        fail_test $name
    end
end

function test_agent_live_copy_and_wrappers
    printf '%s' oauth-token > "$HOME/.gemini/antigravity-cli/token"
    printf '%s' gui-settings > "$gui_source/User/settings.json"
    agent-profile copy antigravity hafez >/dev/null
    or return 1
    test -f "$AGENT_PROFILE_DATA_DIR/antigravity/hafez/home/.gemini/antigravity-cli/token"
    or return 1
    printf '%s\n' '#!/bin/sh' 'env | grep "^HOME=" > "$AGENT_PROFILE_TEST_LOG"' > "$bin_dir/agy"
    chmod +x "$bin_dir/agy"
    set -gx AGENT_PROFILE_TEST_LOG "$test_root/agy.log"
    agent-profile default antigravity hafez >/dev/null
    agy >/dev/null
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$AGENT_PROFILE_DATA_DIR/antigravity/hafez/home"
end

# Chromium's singleton symlinks name the host and pid of the instance that owned
# the source directory. Copied into a profile they make Antigravity focus the
# original window instead of opening the new profile, so a snapshot must drop them.
function test_agent_copy_prunes_gui_singleton_locks
    ln -s MacBook-Pro.local-77770 "$gui_source/SingletonLock"
    or return 1
    ln -s 17350445988078770481 "$gui_source/SingletonCookie"
    or return 1
    ln -s "$test_root/missing-scoped-dir/SingletonSocket" "$gui_source/SingletonSocket"
    or return 1
    agent-profile copy antigravity locked >/dev/null
    or return 1
    set -l gui_data "$AGENT_PROFILE_DATA_DIR/antigravity/locked/gui-user-data"
    test -f "$gui_data/User/settings.json"
    or return 1
    for lock_name in SingletonLock SingletonCookie SingletonSocket
        if test -e "$gui_data/$lock_name"; or test -L "$gui_data/$lock_name"
            printf 'expected %s to be pruned from the snapshot\n' "$gui_data/$lock_name" >&2
            return 1
        end
    end
    return 0
end

# test_agent_gui_macos_app_bundle_launch, which runs just before this, pins the
# probe to failure, so it never reaches the line that actually runs on a current
# macOS. This one lets the real open(1) launch a hand-built bundle, putting
# `open -n --env HOME=...` itself under test.
function test_agent_gui_macos_app_bundle_open_env_launch
    if test (uname -s 2>/dev/null) != Darwin
        return 0
    end
    # Where open(1) predates --env the adapter takes the fallback that
    # test_agent_gui_macos_app_bundle_launch already covers, so nothing to assert.
    if not /usr/bin/open --ap-probe-unsupported-option 2>&1 | string match -q -- '*--env*'
        return 0
    end

    set -g openenv_gui_app "$test_root/OpenEnv-Antigravity.app"
    set -l openenv_log "$test_root/gui-open-env.log"
    command rm -f "$openenv_log"
    mkdir -p "$openenv_gui_app/Contents/MacOS"
    or return 1
    # LaunchServices needs a real Info.plist to launch the bundle at all, and
    # LSBackgroundOnly keeps the probe out of the Dock and away from focus.
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
        '<plist version="1.0"><dict>' \
        '<key>CFBundleExecutable</key><string>Antigravity</string>' \
        '<key>CFBundleIdentifier</key><string>local.agentprofile.openenvprobe</string>' \
        '<key>CFBundlePackageType</key><string>APPL</string>' \
        '<key>LSBackgroundOnly</key><true/>' \
        '</dict></plist>' > "$openenv_gui_app/Contents/Info.plist"
    # open(1) hands the app only the environment it is told to, so the log path
    # is baked into the stub rather than read from AGENT_PROFILE_TEST_LOG.
    printf '%s\n' '#!/bin/sh' "printf \"GUI_ARGS=%s\\n\" \"\$*\" > \"$openenv_log\"" "env | grep \"^HOME=\" >> \"$openenv_log\"" > "$openenv_gui_app/Contents/MacOS/Antigravity"
    chmod +x "$openenv_gui_app/Contents/MacOS/Antigravity"
    or return 1

    function _ap_fish_macos_gui_app
        printf '%s\n' "$openenv_gui_app"
    end
    # The fallback test pinned this to failure and these are plain functions, so
    # restore the real probe or open(1) is never reached at all.
    function _ap_fish_open_supports_env
        /usr/bin/open --ap-probe-unsupported-option 2>&1 | string match -q -- '*--env*'
    end

    agent-profile create antigravity openenv >/dev/null
    or return 1
    agent-profile use antigravity openenv >/dev/null
    or return 1
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    set -l saved_path $PATH
    # Nothing named antigravity may be on PATH, or the launcher takes the command
    # branch and the app-bundle contract goes untested.
    set -gx PATH /usr/bin /bin
    agent-profile restart antigravity >/dev/null
    set -l restart_status $status
    set -gx PATH $saved_path
    # Hand the session back to the default profile the later tests assert on.
    set -e AGENT_PROFILE_ANTIGRAVITY_ACTIVE
    test $restart_status -eq 0
    or return 1

    set -l openenv_home "$AGENT_PROFILE_DATA_DIR/antigravity/openenv/home"
    set -l openenv_data "$AGENT_PROFILE_DATA_DIR/antigravity/openenv/gui-user-data"
    # LaunchServices starts the app asynchronously, and a bundle it has never
    # seen takes longer than a detached exec, so allow more room than usual.
    if not wait_for_file_line "$openenv_log" "HOME=$openenv_home" 300
        printf 'timed out waiting for the open(1) app-bundle launch to write %s\n' "$openenv_log" >&2
        return 1
    end
    assert_file_contains "$openenv_log" "GUI_ARGS=--user-data-dir=$openenv_data"
    or return 1
    if grep -Fq -- --new-window "$openenv_log"
        printf 'expected no --new-window in the open(1) app-bundle launch\n' >&2
        return 1
    end
    return 0
end

function test_agent_gui_launch_isolates_home
    write_gui_stub
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    antigravity >/dev/null
    or return 1
    # The "=" spelling is mandatory: Chromium's parser silently ignores the
    # space-separated form, which is how the profile switch used to be a no-op.
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "GUI_ARGS=--user-data-dir=$AGENT_PROFILE_DATA_DIR/antigravity/hafez/gui-user-data"
    or return 1
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$AGENT_PROFILE_DATA_DIR/antigravity/hafez/home"
end

function test_agent_gui_restart
    write_gui_stub
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    agent-profile restart antigravity >/dev/null
    or return 1
    # --new-window is a VS Code flag, so it is only injected in PATH-command mode.
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "GUI_ARGS=--user-data-dir=$AGENT_PROFILE_DATA_DIR/antigravity/hafez/gui-user-data --new-window"
    or return 1
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$AGENT_PROFILE_DATA_DIR/antigravity/hafez/home"
end

function test_agent_gui_macos_app_bundle_discovery
    test (uname -s) = Darwin
    or return 0
    test -x /Applications/Antigravity.app/Contents/MacOS/Antigravity
    or return 0
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    set -l discovered (_ap_fish_macos_gui_command)
    test "$discovered" = /Applications/Antigravity.app/Contents/MacOS/Antigravity
end

function test_agent_gui_macos_app_bundle_uses_new_instance_launcher
    test (uname -s) = Darwin
    or return 0
    test -x /Applications/Antigravity.app/Contents/MacOS/Antigravity
    or return 0
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    set -l discovered (_ap_fish_gui_launcher)
    test "$discovered" = app:/Applications/Antigravity.app
end

# The macOS app bundle is the configuration the profile-switch bug was reported
# in, and it shares no launch code with the PATH-command tests: the bundle is
# started through open(1) -- or, where open(1) has no --env, the bundle binary
# itself -- instead of a command on PATH. Both helpers that decide this are
# ordinary functions, so the test points the bundle locator at a fake bundle and
# forces the no---env fallback, which turns the launch into a plain exec of a
# stub that records its argv and its HOME.
function test_agent_gui_macos_app_bundle_launch
    set -g fake_gui_app "$test_root/Fake-Antigravity.app"
    mkdir -p "$fake_gui_app/Contents/MacOS"
    printf '%s\n' '#!/bin/sh' 'printf "GUI_ARGS=%s\\n" "$*" > "$AGENT_PROFILE_TEST_LOG"' 'env | grep "^HOME=" >> "$AGENT_PROFILE_TEST_LOG"' > "$fake_gui_app/Contents/MacOS/Antigravity"
    chmod +x "$fake_gui_app/Contents/MacOS/Antigravity"
    or return 1

    function _ap_fish_macos_gui_app
        printf '%s\n' "$fake_gui_app"
    end
    # open(1) --env is what carries HOME into the bundle; forcing the fallback
    # branch makes the launch a direct exec this test can observe instead.
    function _ap_fish_open_supports_env
        return 1
    end

    agent-profile create antigravity appmode >/dev/null
    or return 1
    agent-profile use antigravity appmode >/dev/null
    or return 1
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    set -l saved_path $PATH
    set -l saved_log $AGENT_PROFILE_TEST_LOG
    set -l app_log "$test_root/gui-app.log"
    set -gx AGENT_PROFILE_TEST_LOG "$app_log"
    # Nothing named antigravity may be on PATH, or the launcher takes the command
    # branch and the app-bundle contract goes untested.
    set -gx PATH /usr/bin /bin
    agent-profile restart antigravity >/dev/null
    set -l restart_status $status
    set -gx PATH $saved_path
    set -gx AGENT_PROFILE_TEST_LOG $saved_log
    # Hand the session back to the default profile the later tests assert on.
    set -e AGENT_PROFILE_ANTIGRAVITY_ACTIVE
    test $restart_status -eq 0
    or return 1

    set -l app_home "$AGENT_PROFILE_DATA_DIR/antigravity/appmode/home"
    set -l app_data "$AGENT_PROFILE_DATA_DIR/antigravity/appmode/gui-user-data"
    if not wait_for_file_line "$app_log" "HOME=$app_home"
        printf 'timed out waiting for the backgrounded app-bundle launch to write %s\n' "$app_log" >&2
        return 1
    end
    # HOME is what actually selects the Antigravity account, and the "=" spelling
    # is mandatory: the bundle is a plain Electron app whose Chromium parser
    # silently ignores the space-separated form.
    assert_file_contains "$app_log" "GUI_ARGS=--user-data-dir=$app_data"
    or return 1
    # --new-window is a VS Code flag and inert for the Electron bundle, so the
    # app-bundle restart must not inject it.
    if grep -Fq -- --new-window "$app_log"
        printf 'expected no --new-window in the app-bundle launch\n' >&2
        return 1
    end
    # The launch also has to create both directories it points the GUI at.
    test -d "$app_home"
    or return 1
    test -d "$app_data"
end

function test_codex_live_copy_and_wrapper
    mkdir -p "$HOME/.codex"
    printf '%s' codex-token > "$HOME/.codex/auth.json"
    agent-profile copy codex codexwork >/dev/null
    or return 1
    test -f "$AGENT_PROFILE_DATA_DIR/codex/codexwork/auth.json"
    or return 1
    printf '%s\n' '#!/bin/sh' 'env | grep "^CODEX_HOME=" > "$AGENT_PROFILE_TEST_LOG"' > "$bin_dir/codex"
    chmod +x "$bin_dir/codex"
    set -gx AGENT_PROFILE_TEST_LOG "$test_root/codex.log"
    agent-profile default codex codexwork >/dev/null
    codex >/dev/null
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "CODEX_HOME=$AGENT_PROFILE_DATA_DIR/codex/codexwork"
end

function test_claude_wrapper
    claude-profile create work >/dev/null
    or return 1
    claude-profile default work >/dev/null
    or return 1
    printf '%s\n' '#!/bin/sh' 'env | grep "^CLAUDE_CONFIG_DIR=" > "$CLAUDE_PROFILE_TEST_LOG"' > "$bin_dir/claude"
    chmod +x "$bin_dir/claude"
    set -gx CLAUDE_PROFILE_TEST_LOG "$test_root/claude.log"
    claude >/dev/null
    assert_file_contains "$CLAUDE_PROFILE_TEST_LOG" "CLAUDE_CONFIG_DIR=$XDG_DATA_HOME/claude-profiles/work"
end

function test_claude_create_init_and_status
    claude-profile create --init initialized >/dev/null
    or return 1
    test -s "$XDG_DATA_HOME/claude-profiles/initialized/settings.json"
    or return 1
    claude-profile list | grep -Fq initialized
    or return 1
    claude-profile version | grep -Fqx 1.3.0
end

function test_claude_directory_local_switching
    set -l project_dir "$test_root/project"
    mkdir -p "$project_dir"
    cd "$project_dir"
    claude-profile local work >/dev/null
    or return 1
    set -e CLAUDE_CONFIG_DIR
    set -e CLAUDE_PROFILE_AUTO_SET
    claude-profile auto on >/dev/null
    or return 1
    test "$CLAUDE_CONFIG_DIR" = "$XDG_DATA_HOME/claude-profiles/work"
    or return 1
    claude-profile auto status | grep -Fq 'Auto-switching: enabled'
    or return 1
    cd "$test_root"
    not set -q CLAUDE_CONFIG_DIR
end

function test_claude_skill_pool_backend
    set -l skill_dir "$test_root/skill-source"
    mkdir -p "$skill_dir"
    printf '%s\n' '# demo skill' > "$skill_dir/SKILL.md"
    claude-profile skills register demo "$skill_dir" >/dev/null
    or return 1
    test -L "$XDG_DATA_HOME/claude-profiles/skills/demo"
    or return 1
    claude-profile skills add demo work >/dev/null
    or return 1
    test -L "$XDG_DATA_HOME/claude-profiles/work/skills/demo"
    or return 1
end

function test_fish_validation_and_no_overwrite
    if agent-profile create antigravity bad/name >/dev/null 2>&1
        return 1
    end
    if claude-profile create .hidden >/dev/null 2>&1
        return 1
    end
    printf '%s' keep > "$AGENT_PROFILE_DATA_DIR/codex/codexwork/auth.json"
    if agent-profile copy codex codexwork >/dev/null 2>&1
        return 1
    end
    assert_file_contains "$AGENT_PROFILE_DATA_DIR/codex/codexwork/auth.json" keep
end

# Redirecting HOME is what switches the Antigravity profile, and on macOS it is
# also what loses the login keychain: the OS resolves the default keychain at
# $HOME/Library/Keychains, so the child had none and Chromium stopped on
# "A keychain cannot be found to store 'antigravity'". The launch has to link the
# real keychain directory into the profile home.
function test_agent_gui_launch_links_macos_keychain
    macos_keychain_supported
    or return 0
    setup_sandbox_keychains
    or return 1
    write_gui_stub
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    set -gx AGENT_PROFILE_TEST_LOG "$test_root/gui-keychain.log"
    agent-profile create antigravity keychain-gui >/dev/null
    or return 1
    agent-profile use antigravity keychain-gui >/dev/null
    or return 1

    set -l gui_home "$AGENT_PROFILE_DATA_DIR/antigravity/keychain-gui/home"
    # Guard the premise: the link must be the launch's doing, not create's.
    if test -e "$gui_home/Library/Keychains"; or test -L "$gui_home/Library/Keychains"
        printf 'expected no keychain entry in %s before the launch\n' "$gui_home" >&2
        return 1
    end

    antigravity >/dev/null
    or return 1
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$gui_home"
    or return 1
    assert_keychain_link "$gui_home"
end

# The agy CLI redirects HOME through its own code path, so it loses the keychain
# for the same reason and has to link it back the same way.
function test_agent_agy_launch_links_macos_keychain
    macos_keychain_supported
    or return 0
    setup_sandbox_keychains
    or return 1
    printf '%s\n' '#!/bin/sh' 'env | grep "^HOME=" > "$AGENT_PROFILE_TEST_LOG"' > "$bin_dir/agy"
    chmod +x "$bin_dir/agy"
    set -gx AGENT_PROFILE_TEST_LOG "$test_root/agy-keychain.log"
    agent-profile create antigravity keychain-cli >/dev/null
    or return 1
    agent-profile use antigravity keychain-cli >/dev/null
    or return 1

    set -l cli_home "$AGENT_PROFILE_DATA_DIR/antigravity/keychain-cli/home"
    if test -e "$cli_home/Library/Keychains"; or test -L "$cli_home/Library/Keychains"
        printf 'expected no keychain entry in %s before the launch\n' "$cli_home" >&2
        return 1
    end

    agy --print >/dev/null
    or return 1
    assert_file_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$cli_home"
    or return 1
    assert_keychain_link "$cli_home"
end

# Whatever the user already put at <profile>/home/Library/Keychains wins: a real
# directory is never replaced by a link, and a link they made is never retargeted
# -- including a dangling one, which an -e test alone would miss.
function test_agent_launch_keeps_existing_keychain_entry
    macos_keychain_supported
    or return 0
    setup_sandbox_keychains
    or return 1
    write_gui_stub
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    set -gx AGENT_PROFILE_TEST_LOG "$test_root/gui-keychain-keep.log"

    agent-profile create antigravity keychain-keep >/dev/null
    or return 1
    set -l keep_home "$AGENT_PROFILE_DATA_DIR/antigravity/keychain-keep/home"
    mkdir -p "$keep_home/Library/Keychains"
    or return 1
    printf '%s' do-not-clobber > "$keep_home/Library/Keychains/marker"
    agent-profile use antigravity keychain-keep >/dev/null
    or return 1
    antigravity >/dev/null
    or return 1
    if test -L "$keep_home/Library/Keychains"
        printf 'expected the real directory at %s to survive, not become a link\n' "$keep_home/Library/Keychains" >&2
        return 1
    end
    test -d "$keep_home/Library/Keychains"
    or return 1
    assert_file_contains "$keep_home/Library/Keychains/marker" do-not-clobber
    or return 1

    agent-profile create antigravity keychain-dangle >/dev/null
    or return 1
    set -l dangle_home "$AGENT_PROFILE_DATA_DIR/antigravity/keychain-dangle/home"
    mkdir -p "$dangle_home/Library"
    or return 1
    ln -s "$test_root/no-such-keychain-dir" "$dangle_home/Library/Keychains"
    or return 1
    agent-profile use antigravity keychain-dangle >/dev/null
    or return 1
    antigravity >/dev/null
    or return 1
    test -L "$dangle_home/Library/Keychains"
    or return 1
    test (command readlink "$dangle_home/Library/Keychains") = "$test_root/no-such-keychain-dir"
end

# The assertion that ties this to the reported bug. security(1) resolves the
# default keychain exactly the way the GUI does, so run the real one: without the
# link a redirected HOME has no default keychain at all, and with the link the
# launch created it finds the login keychain again.
function test_agent_macos_keychain_link_restores_default_keychain
    macos_keychain_supported
    or return 0
    if not command -q security
        return 0
    end
    setup_sandbox_keychains
    or return 1

    # The state the bug was reported in: a profile home with no keychain link.
    set -l bare_home "$test_root/keychainless-home"
    mkdir -p "$bare_home"
    or return 1
    set -l bare_output (env HOME="$bare_home" security default-keychain 2>&1)
    if test $status -eq 0
        printf 'expected security default-keychain to fail under a keychain-less HOME, got: %s\n' "$bare_output" >&2
        return 1
    end
    if not string match -q -- '*A default keychain could not be found*' "$bare_output"
        printf 'expected the missing-keychain diagnostic, got: %s\n' "$bare_output" >&2
        return 1
    end

    write_gui_stub
    set -e AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    set -gx AGENT_PROFILE_TEST_LOG "$test_root/gui-keychain-security.log"
    agent-profile create antigravity keychain-security >/dev/null
    or return 1
    agent-profile use antigravity keychain-security >/dev/null
    or return 1
    set -l secure_home "$AGENT_PROFILE_DATA_DIR/antigravity/keychain-security/home"
    antigravity >/dev/null
    or return 1
    assert_keychain_link "$secure_home"
    or return 1

    set -l linked_output (env HOME="$secure_home" security default-keychain 2>&1)
    if test $status -ne 0
        printf 'expected security default-keychain to succeed under the linked profile home, got: %s\n' "$linked_output" >&2
        return 1
    end
    if not string match -q -- '*login.keychain*' "$linked_output"
        printf 'expected the login keychain to be resolved, got: %s\n' "$linked_output" >&2
        return 1
    end
    return 0
end

run_test test_agent_live_copy_and_wrappers
run_test test_agent_copy_prunes_gui_singleton_locks
# The app-bundle discovery tests must stay ahead of every test that installs a
# bin/antigravity stub, or the resolver returns the stub instead of the bundle.
run_test test_agent_gui_macos_app_bundle_discovery
run_test test_agent_gui_macos_app_bundle_uses_new_instance_launcher
run_test test_agent_gui_macos_app_bundle_launch
run_test test_agent_gui_macos_app_bundle_open_env_launch
run_test test_agent_gui_launch_isolates_home
run_test test_agent_gui_restart
run_test test_codex_live_copy_and_wrapper
run_test test_claude_wrapper
run_test test_claude_create_init_and_status
run_test test_claude_directory_local_switching
run_test test_claude_skill_pool_backend
run_test test_fish_validation_and_no_overwrite
# The keychain tests select profiles of their own and leave them selected, so
# they run after every test that asserts on the session profile.
run_test test_agent_gui_launch_links_macos_keychain
run_test test_agent_agy_launch_links_macos_keychain
run_test test_agent_launch_keeps_existing_keychain_entry
run_test test_agent_macos_keychain_link_restores_default_keychain

printf '\n%d passed, %d failed\n' $pass_count $fail_count
rm -rf "$test_root"
test $fail_count -eq 0
