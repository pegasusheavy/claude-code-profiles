#!/usr/bin/env bash

# Dependency-free behavior tests for agent-profile.sh.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

# Captured before HOME is redirected into the sandbox: the macOS keychain tests
# need the caller's real login keychain directory, which is the thing the adapter
# links into a profile home.
REAL_KEYCHAINS="$HOME/Library/Keychains"

HOME="$TEST_ROOT/home"
XDG_DATA_HOME="$TEST_ROOT/data"
PATH="$TEST_ROOT/bin:$PATH"
export HOME XDG_DATA_HOME PATH
ORIGINAL_CODEX_HOME=${CODEX_HOME-}

mkdir -p "$HOME" "$TEST_ROOT/bin"

# The implementation is intentionally sourced after the test environment is
# prepared, just like a user's shell profile.
if [ -f "$SCRIPT_DIR/../agent-profile.sh" ]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/../agent-profile.sh"
fi

if ! command -v agent-profile >/dev/null 2>&1; then
    printf 'not ok - agent-profile command is defined\n'
    exit 1
fi

PASS=0
FAIL=0

fail() {
    printf 'not ok - %s\n' "$1"
    FAIL=$((FAIL + 1))
}

pass() {
    printf 'ok - %s\n' "$1"
    PASS=$((PASS + 1))
}

assert_file() {
    _assert_file_path=$1
    _assert_file_expected=$2
    if [ -f "$_assert_file_path" ] && [ "$(cat "$_assert_file_path")" = "$_assert_file_expected" ]; then
        return 0
    fi
    printf 'expected %s to contain %s\n' "$_assert_file_path" "$_assert_file_expected" >&2
    return 1
}

assert_contains() {
    _assert_contains_file=$1
    _assert_contains_text=$2
    grep -F -- "$_assert_contains_text" "$_assert_contains_file" >/dev/null 2>&1
}

# The app-bundle fallback launch detaches the GUI, so its log is not there the
# moment the wrapper returns. Poll for it instead of racing it.
wait_for_log() {
    _wait_log_file=$1
    _wait_log_text=$2
    _wait_log_limit=${3:-100}
    _wait_log_tries=0
    while [ "$_wait_log_tries" -lt "$_wait_log_limit" ]; do
        if [ -f "$_wait_log_file" ] && assert_contains "$_wait_log_file" "$_wait_log_text"; then
            return 0
        fi
        sleep 0.05
        _wait_log_tries=$((_wait_log_tries + 1))
    done
    return 1
}

# The GUI stub records the argv it received and the HOME it inherited, mirroring
# the agy stub. HOME is the knob that actually selects the Antigravity account
# (it resolves ~/.gemini), so the launch tests have to see it, not just the flags.
write_gui_stub() {
    printf '#!/bin/sh\nprintf "GUI_ARGS=%%s\\n" "$*" > "$AGENT_PROFILE_TEST_LOG"\nenv | grep "^HOME=" >> "$AGENT_PROFILE_TEST_LOG"\n' > "$TEST_ROOT/bin/antigravity"
    chmod +x "$TEST_ROOT/bin/antigravity"
}

# The keychain link only exists on macOS, and it needs a real login keychain
# directory to point at, so skip cleanly elsewhere the way the app-bundle tests do.
macos_keychain_supported() {
    [ "$(uname -s 2>/dev/null)" = Darwin ] || return 1
    [ -d "$REAL_KEYCHAINS" ]
}

# The adapter links whatever $HOME/Library/Keychains it finds, and this suite has
# redirected HOME into the sandbox -- so point the sandbox home's keychain
# directory at the caller's real one. macOS resolves the login keychain through
# both hops, which keeps the security(1) assertion honest without this test ever
# creating or writing anything inside the real keychain directory.
setup_sandbox_keychains() {
    macos_keychain_supported || return 1
    mkdir -p "$HOME/Library" || return 1
    [ -L "$HOME/Library/Keychains" ] && return 0
    ln -s "$REAL_KEYCHAINS" "$HOME/Library/Keychains"
}

# Symlink-resolving realpath, without depending on realpath(1) or readlink -f.
resolved_dir() {
    (CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P)
}

assert_keychain_link() {
    _kc_link="$1/Library/Keychains"
    if [ ! -L "$_kc_link" ]; then
        printf 'expected %s to be a symlink into the login keychain directory\n' "$_kc_link" >&2
        return 1
    fi
    if [ ! -d "$_kc_link" ]; then
        printf 'expected %s to resolve to a directory, not dangle\n' "$_kc_link" >&2
        return 1
    fi
    if [ "$(resolved_dir "$_kc_link")" != "$(resolved_dir "$REAL_KEYCHAINS")" ]; then
        printf 'expected %s to resolve to %s, got %s\n' \
            "$_kc_link" "$(resolved_dir "$REAL_KEYCHAINS")" "$(resolved_dir "$_kc_link")" >&2
        return 1
    fi
    return 0
}

test_invalid_name_rejected() {
    if agent-profile create antigravity '../escape' >/dev/null 2>&1; then
        return 1
    fi
    [ ! -e "$XDG_DATA_HOME/agent-profiles/antigravity/../escape" ]
}

test_copy_live_antigravity() {
    mkdir -p "$HOME/.gemini/antigravity-cli" "$TEST_ROOT/gui-source/User"
    printf 'oauth-token' > "$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
    printf 'gui-settings' > "$TEST_ROOT/gui-source/User/settings.json"
    AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR="$TEST_ROOT/gui-source"
    export AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR

    agent-profile copy antigravity hafez >/dev/null 2>&1 || return 1
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/hafez/home/.gemini/antigravity-cli/antigravity-oauth-token" 'oauth-token' || return 1
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/hafez/gui-user-data/User/settings.json" 'gui-settings'
}

# Chromium's singleton symlinks name the host and pid of the instance that owned
# the source directory. Copied into a profile they make Antigravity focus the
# original window instead of opening the new profile, so a snapshot must drop them.
test_copy_prunes_gui_singleton_locks() {
    ln -s 'MacBook-Pro.local-77770' "$TEST_ROOT/gui-source/SingletonLock" || return 1
    ln -s '17350445988078770481' "$TEST_ROOT/gui-source/SingletonCookie" || return 1
    ln -s "$TEST_ROOT/missing-scoped-dir/SingletonSocket" "$TEST_ROOT/gui-source/SingletonSocket" || return 1

    agent-profile copy antigravity locked >/dev/null 2>&1 || return 1
    _copy_locks_dir="$XDG_DATA_HOME/agent-profiles/antigravity/locked/gui-user-data"
    assert_file "$_copy_locks_dir/User/settings.json" 'gui-settings' || return 1
    for _copy_locks_name in SingletonLock SingletonCookie SingletonSocket; do
        if [ -e "$_copy_locks_dir/$_copy_locks_name" ] || [ -L "$_copy_locks_dir/$_copy_locks_name" ]; then
            printf 'expected %s to be pruned from the snapshot\n' "$_copy_locks_dir/$_copy_locks_name" >&2
            return 1
        fi
    done
    return 0
}

test_copy_from_default_and_no_overwrite() {
    agent-profile create antigravity work >/dev/null 2>&1 || return 1
    printf 'work-marker' > "$XDG_DATA_HOME/agent-profiles/antigravity/work/marker"
    agent-profile default antigravity work >/dev/null 2>&1 || return 1
    agent-profile copy antigravity default copied >/dev/null 2>&1 || return 1
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/copied/marker" 'work-marker' || return 1

    printf 'keep-marker' > "$XDG_DATA_HOME/agent-profiles/antigravity/copied/marker"
    if agent-profile copy antigravity work copied >/dev/null 2>&1; then
        return 1
    fi
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/copied/marker" 'keep-marker' || return 1
    agent-profile copy antigravity work copied --force >/dev/null 2>&1 || return 1
    assert_file "$XDG_DATA_HOME/agent-profiles/antigravity/copied/marker" 'work-marker'
}

test_agy_wrapper_isolates_home() {
    printf '#!/bin/sh\nenv | grep "^HOME=" > "$AGENT_PROFILE_TEST_LOG"\n' > "$TEST_ROOT/bin/agy"
    chmod +x "$TEST_ROOT/bin/agy"
    AGENT_PROFILE_TEST_LOG="$TEST_ROOT/agy.log"
    export AGENT_PROFILE_TEST_LOG

    agent-profile use antigravity copied >/dev/null 2>&1 || return 1
    agy --print >/dev/null 2>&1 || return 1
    assert_file "$AGENT_PROFILE_TEST_LOG" "HOME=$XDG_DATA_HOME/agent-profiles/antigravity/copied/home" || return 1
    [ "$HOME" = "$TEST_ROOT/home" ]
}

test_gui_macos_app_bundle_discovery() {
    [ "$(uname -s 2>/dev/null)" = Darwin ] || return 0
    [ -x /Applications/Antigravity.app/Contents/MacOS/Antigravity ] || return 0
    unset AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    _ap_discovered_gui=$(_ap_macos_gui_command) || return 1
    [ "$_ap_discovered_gui" = /Applications/Antigravity.app/Contents/MacOS/Antigravity ]
}

test_gui_macos_app_bundle_uses_new_instance_launcher() {
    [ "$(uname -s 2>/dev/null)" = Darwin ] || return 0
    [ -x /Applications/Antigravity.app/Contents/MacOS/Antigravity ] || return 0
    unset AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    _ap_gui_launcher=$(_ap_find_gui_command) || return 1
    [ "$_ap_gui_launcher" = app:/Applications/Antigravity.app ]
}

# The macOS app bundle is the configuration the profile-switch bug was reported
# in, and it shares no launch code with the PATH-command tests below: the bundle
# is started through open(1) -- or, where open(1) has no --env, the bundle binary
# itself -- instead of a command on PATH. Both helpers that decide this are
# ordinary sourced functions, so the test points the bundle locator at a fake
# bundle and forces the no---env fallback, which turns the launch into a plain
# exec of a stub that records its argv and its HOME.
test_gui_macos_app_bundle_launch_isolates_home() {
    _app_bundle="$TEST_ROOT/Fake-Antigravity.app"
    mkdir -p "$_app_bundle/Contents/MacOS" || return 1
    printf '#!/bin/sh\nprintf "GUI_ARGS=%%s\\n" "$*" > "$AGENT_PROFILE_TEST_LOG"\nenv | grep "^HOME=" >> "$AGENT_PROFILE_TEST_LOG"\n' > "$_app_bundle/Contents/MacOS/Antigravity"
    chmod +x "$_app_bundle/Contents/MacOS/Antigravity" || return 1

    _ap_macos_gui_app() { printf '%s\n' "$TEST_ROOT/Fake-Antigravity.app"; }
    # open(1) --env is what carries HOME into the bundle; forcing the fallback
    # branch makes the launch a direct exec this test can observe instead.
    _ap_open_supports_env() { return 1; }

    agent-profile create antigravity appmode >/dev/null 2>&1 || return 1
    agent-profile use antigravity appmode >/dev/null 2>&1 || return 1
    unset AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    _app_saved_path=$PATH
    _app_saved_log=${AGENT_PROFILE_TEST_LOG-}
    _app_log="$TEST_ROOT/gui-app.log"
    AGENT_PROFILE_TEST_LOG="$_app_log"
    # Nothing named antigravity may be on PATH, or the resolver takes the command
    # branch and the app-bundle contract goes untested.
    PATH=/usr/bin:/bin
    agent-profile restart antigravity >/dev/null 2>&1
    _app_restart_status=$?
    PATH=$_app_saved_path
    AGENT_PROFILE_TEST_LOG=$_app_saved_log
    # Hand the session back to the profile the PATH-mode tests below assert on.
    agent-profile use antigravity copied >/dev/null 2>&1 || return 1
    [ "$_app_restart_status" -eq 0 ] || return 1

    _app_home="$XDG_DATA_HOME/agent-profiles/antigravity/appmode/home"
    _app_data="$XDG_DATA_HOME/agent-profiles/antigravity/appmode/gui-user-data"
    if ! wait_for_log "$_app_log" "HOME=$_app_home"; then
        printf 'timed out waiting for the backgrounded app-bundle launch to write %s\n' "$_app_log" >&2
        return 1
    fi
    # HOME is what actually selects the Antigravity account, and the "=" spelling
    # is mandatory: the bundle is a plain Electron app whose Chromium parser
    # silently ignores the space-separated form.
    assert_contains "$_app_log" "GUI_ARGS=--user-data-dir=$_app_data" || return 1
    # --new-window is a VS Code flag and inert for the Electron bundle, so the
    # app-bundle restart must not inject it.
    if assert_contains "$_app_log" '--new-window'; then
        printf 'expected no --new-window in the app-bundle launch\n' >&2
        return 1
    fi
    # The launch also has to create both directories it points the GUI at.
    [ -d "$_app_home" ] || return 1
    [ -d "$_app_data" ]
}

# The test above forces the fallback branch, so it never reaches the line that
# actually runs on a current macOS. This one lets the real open(1) launch a
# hand-built bundle, putting `open -n --env HOME=...` itself under test.
test_gui_macos_app_bundle_open_env_launch() {
    [ "$(uname -s 2>/dev/null)" = Darwin ] || return 0
    # Where open(1) predates --env the adapter takes the fallback the test above
    # already covers, so there is nothing here to assert.
    /usr/bin/open --ap-probe-unsupported-option 2>&1 | grep -q -- '--env' || return 0

    _oe_bundle="$TEST_ROOT/OpenEnv-Antigravity.app"
    _oe_log="$TEST_ROOT/gui-open-env.log"
    rm -f "$_oe_log"
    mkdir -p "$_oe_bundle/Contents/MacOS" || return 1
    # LaunchServices needs a real Info.plist to launch the bundle at all, and
    # LSBackgroundOnly keeps the probe out of the Dock and away from focus.
    cat > "$_oe_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Antigravity</string>
<key>CFBundleIdentifier</key><string>local.agentprofile.openenvprobe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
    # open(1) hands the app only the environment it is told to, so the log path
    # is baked into the stub rather than read from AGENT_PROFILE_TEST_LOG.
    printf '#!/bin/sh\nprintf "GUI_ARGS=%%s\\n" "$*" > "%s"\nenv | grep "^HOME=" >> "%s"\n' "$_oe_log" "$_oe_log" > "$_oe_bundle/Contents/MacOS/Antigravity"
    chmod +x "$_oe_bundle/Contents/MacOS/Antigravity" || return 1

    _ap_macos_gui_app() { printf '%s\n' "$TEST_ROOT/OpenEnv-Antigravity.app"; }
    # The fallback test above pinned this to failure, and these are plain sourced
    # functions, so restore the real probe or open(1) is never reached at all.
    _ap_open_supports_env() { /usr/bin/open --ap-probe-unsupported-option 2>&1 | grep -q -- '--env'; }

    agent-profile create antigravity openenv >/dev/null 2>&1 || return 1
    agent-profile use antigravity openenv >/dev/null 2>&1 || return 1
    unset AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    _oe_saved_path=$PATH
    PATH=/usr/bin:/bin
    agent-profile restart antigravity >/dev/null 2>&1
    _oe_status=$?
    PATH=$_oe_saved_path
    # Hand the session back to the profile the PATH-mode tests below assert on.
    agent-profile use antigravity copied >/dev/null 2>&1 || return 1
    [ "$_oe_status" -eq 0 ] || return 1

    _oe_home="$XDG_DATA_HOME/agent-profiles/antigravity/openenv/home"
    _oe_data="$XDG_DATA_HOME/agent-profiles/antigravity/openenv/gui-user-data"
    # LaunchServices starts the app asynchronously, and a bundle it has never
    # seen takes longer than a detached exec, so allow more room than usual.
    if ! wait_for_log "$_oe_log" "HOME=$_oe_home" 300; then
        printf 'timed out waiting for the open(1) app-bundle launch to write %s\n' "$_oe_log" >&2
        return 1
    fi
    assert_contains "$_oe_log" "GUI_ARGS=--user-data-dir=$_oe_data" || return 1
    if assert_contains "$_oe_log" '--new-window'; then
        printf 'expected no --new-window in the open(1) app-bundle launch\n' >&2
        return 1
    fi
    return 0
}

test_codex_wrapper_sets_codex_home() {
    mkdir -p "$HOME/.codex"
    printf 'model = "gpt-test"\n' > "$HOME/.codex/config.toml"
    agent-profile copy codex hafez >/dev/null 2>&1 || return 1
    agent-profile default codex hafez >/dev/null 2>&1 || return 1
    printf '#!/bin/sh\nenv | grep "^CODEX_HOME=" > "$AGENT_PROFILE_TEST_LOG"\n' > "$TEST_ROOT/bin/codex"
    chmod +x "$TEST_ROOT/bin/codex"
    codex >/dev/null 2>&1 || return 1
    assert_file "$AGENT_PROFILE_TEST_LOG" "CODEX_HOME=$XDG_DATA_HOME/agent-profiles/codex/hafez" || return 1
    [ "${CODEX_HOME-}" = "$ORIGINAL_CODEX_HOME" ]
}

test_gui_wrapper_injects_user_data_dir() {
    write_gui_stub
    AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND=antigravity
    export AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    antigravity --new-window >/dev/null 2>&1 || return 1
    # The "=" spelling is mandatory: Chromium's parser silently ignores the
    # space-separated form, which is how the profile switch used to be a no-op.
    assert_contains "$AGENT_PROFILE_TEST_LOG" "GUI_ARGS=--user-data-dir=$XDG_DATA_HOME/agent-profiles/antigravity/copied/gui-user-data --new-window" || return 1
    assert_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$XDG_DATA_HOME/agent-profiles/antigravity/copied/home" || return 1
    # The launch also has to create both directories it points the GUI at.
    [ -d "$XDG_DATA_HOME/agent-profiles/antigravity/copied/home" ] || return 1
    [ -d "$XDG_DATA_HOME/agent-profiles/antigravity/copied/gui-user-data" ] || return 1

    # An explicit --user-data-dir wins: no flag is injected, but HOME still is.
    antigravity --user-data-dir /tmp/custom-gui >/dev/null 2>&1 || return 1
    assert_contains "$AGENT_PROFILE_TEST_LOG" 'GUI_ARGS=--user-data-dir /tmp/custom-gui' || return 1
    if assert_contains "$AGENT_PROFILE_TEST_LOG" '--user-data-dir='; then
        printf 'expected no injected --user-data-dir when the user supplied one\n' >&2
        return 1
    fi
    assert_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$XDG_DATA_HOME/agent-profiles/antigravity/copied/home"
}

test_gui_restart_opens_fresh_profile_window() {
    agent-profile restart antigravity >/dev/null 2>&1 || return 1
    # --new-window is a VS Code flag, so it is only injected in PATH-command mode.
    assert_contains "$AGENT_PROFILE_TEST_LOG" "GUI_ARGS=--user-data-dir=$XDG_DATA_HOME/agent-profiles/antigravity/copied/gui-user-data --new-window" || return 1
    assert_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$XDG_DATA_HOME/agent-profiles/antigravity/copied/home"
}

# Redirecting HOME is what switches the Antigravity profile, and on macOS it is
# also what loses the login keychain: the OS resolves the default keychain at
# $HOME/Library/Keychains, so the child had none and Chromium stopped on
# "A keychain cannot be found to store 'antigravity'". The launch has to link the
# real keychain directory into the profile home.
test_gui_launch_links_macos_keychain() {
    macos_keychain_supported || return 0
    setup_sandbox_keychains || return 1
    write_gui_stub
    AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND=antigravity
    export AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    AGENT_PROFILE_TEST_LOG="$TEST_ROOT/gui-keychain.log"
    agent-profile create antigravity keychain-gui >/dev/null 2>&1 || return 1
    agent-profile use antigravity keychain-gui >/dev/null 2>&1 || return 1

    _kc_gui_home="$XDG_DATA_HOME/agent-profiles/antigravity/keychain-gui/home"
    # Guard the premise: the link must be the launch's doing, not create's.
    if [ -e "$_kc_gui_home/Library/Keychains" ] || [ -L "$_kc_gui_home/Library/Keychains" ]; then
        printf 'expected no keychain entry in %s before the launch\n' "$_kc_gui_home" >&2
        return 1
    fi

    antigravity >/dev/null 2>&1 || return 1
    assert_contains "$AGENT_PROFILE_TEST_LOG" "HOME=$_kc_gui_home" || return 1
    assert_keychain_link "$_kc_gui_home"
}

# The agy CLI redirects HOME through its own code path, so it loses the keychain
# for the same reason and has to link it back the same way.
test_agy_launch_links_macos_keychain() {
    macos_keychain_supported || return 0
    setup_sandbox_keychains || return 1
    printf '#!/bin/sh\nenv | grep "^HOME=" > "$AGENT_PROFILE_TEST_LOG"\n' > "$TEST_ROOT/bin/agy"
    chmod +x "$TEST_ROOT/bin/agy"
    AGENT_PROFILE_TEST_LOG="$TEST_ROOT/agy-keychain.log"
    agent-profile create antigravity keychain-cli >/dev/null 2>&1 || return 1
    agent-profile use antigravity keychain-cli >/dev/null 2>&1 || return 1

    _kc_cli_home="$XDG_DATA_HOME/agent-profiles/antigravity/keychain-cli/home"
    if [ -e "$_kc_cli_home/Library/Keychains" ] || [ -L "$_kc_cli_home/Library/Keychains" ]; then
        printf 'expected no keychain entry in %s before the launch\n' "$_kc_cli_home" >&2
        return 1
    fi

    agy --print >/dev/null 2>&1 || return 1
    assert_file "$AGENT_PROFILE_TEST_LOG" "HOME=$_kc_cli_home" || return 1
    assert_keychain_link "$_kc_cli_home"
}

# Whatever the user already put at <profile>/home/Library/Keychains wins: a real
# directory is never replaced by a link, and a link they made is never retargeted
# -- including a dangling one, which an -e test alone would miss.
test_launch_keeps_existing_keychain_entry() {
    macos_keychain_supported || return 0
    setup_sandbox_keychains || return 1
    write_gui_stub
    AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND=antigravity
    export AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    AGENT_PROFILE_TEST_LOG="$TEST_ROOT/gui-keychain-keep.log"

    agent-profile create antigravity keychain-keep >/dev/null 2>&1 || return 1
    _kc_keep_home="$XDG_DATA_HOME/agent-profiles/antigravity/keychain-keep/home"
    mkdir -p "$_kc_keep_home/Library/Keychains" || return 1
    printf 'do-not-clobber' > "$_kc_keep_home/Library/Keychains/marker"
    agent-profile use antigravity keychain-keep >/dev/null 2>&1 || return 1
    antigravity >/dev/null 2>&1 || return 1
    if [ -L "$_kc_keep_home/Library/Keychains" ]; then
        printf 'expected the real directory at %s to survive, not become a link\n' "$_kc_keep_home/Library/Keychains" >&2
        return 1
    fi
    [ -d "$_kc_keep_home/Library/Keychains" ] || return 1
    assert_file "$_kc_keep_home/Library/Keychains/marker" 'do-not-clobber' || return 1

    agent-profile create antigravity keychain-dangle >/dev/null 2>&1 || return 1
    _kc_dangle_home="$XDG_DATA_HOME/agent-profiles/antigravity/keychain-dangle/home"
    mkdir -p "$_kc_dangle_home/Library" || return 1
    ln -s "$TEST_ROOT/no-such-keychain-dir" "$_kc_dangle_home/Library/Keychains" || return 1
    agent-profile use antigravity keychain-dangle >/dev/null 2>&1 || return 1
    antigravity >/dev/null 2>&1 || return 1
    [ -L "$_kc_dangle_home/Library/Keychains" ] || return 1
    [ "$(readlink "$_kc_dangle_home/Library/Keychains")" = "$TEST_ROOT/no-such-keychain-dir" ]
}

# The assertion that ties this to the reported bug. security(1) resolves the
# default keychain exactly the way the GUI does, so run the real one: without the
# link a redirected HOME has no default keychain at all, and with the link the
# launch created it finds the login keychain again.
test_macos_keychain_link_restores_default_keychain() {
    macos_keychain_supported || return 0
    command -v security >/dev/null 2>&1 || return 0
    setup_sandbox_keychains || return 1

    # The state the bug was reported in: a profile home with no keychain link.
    _kc_bare_home="$TEST_ROOT/keychainless-home"
    mkdir -p "$_kc_bare_home" || return 1
    if _kc_bare_out=$(env HOME="$_kc_bare_home" security default-keychain 2>&1); then
        printf 'expected security default-keychain to fail under a keychain-less HOME, got: %s\n' "$_kc_bare_out" >&2
        return 1
    fi
    case "$_kc_bare_out" in
        *'A default keychain could not be found'*) ;;
        *)
            printf 'expected the missing-keychain diagnostic, got: %s\n' "$_kc_bare_out" >&2
            return 1
            ;;
    esac

    write_gui_stub
    AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND=antigravity
    export AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND
    AGENT_PROFILE_TEST_LOG="$TEST_ROOT/gui-keychain-security.log"
    agent-profile create antigravity keychain-security >/dev/null 2>&1 || return 1
    agent-profile use antigravity keychain-security >/dev/null 2>&1 || return 1
    _kc_sec_home="$XDG_DATA_HOME/agent-profiles/antigravity/keychain-security/home"
    antigravity >/dev/null 2>&1 || return 1
    assert_keychain_link "$_kc_sec_home" || return 1

    if ! _kc_sec_out=$(env HOME="$_kc_sec_home" security default-keychain 2>&1); then
        printf 'expected security default-keychain to succeed under the linked profile home, got: %s\n' "$_kc_sec_out" >&2
        return 1
    fi
    case "$_kc_sec_out" in
        *login.keychain*) return 0 ;;
        *)
            printf 'expected the login keychain to be resolved, got: %s\n' "$_kc_sec_out" >&2
            return 1
            ;;
    esac
}

run_test() {
    _test_name=$1
    if "$@"; then
        pass "$_test_name"
    else
        fail "$_test_name"
    fi
}

run_test test_invalid_name_rejected
run_test test_copy_live_antigravity
run_test test_copy_prunes_gui_singleton_locks
run_test test_copy_from_default_and_no_overwrite
run_test test_agy_wrapper_isolates_home
# The app-bundle discovery tests must stay ahead of every test that installs a
# bin/antigravity stub, or the resolver returns the stub instead of the bundle.
run_test test_gui_macos_app_bundle_discovery
run_test test_gui_macos_app_bundle_uses_new_instance_launcher
run_test test_gui_macos_app_bundle_launch_isolates_home
run_test test_gui_macos_app_bundle_open_env_launch
run_test test_codex_wrapper_sets_codex_home
run_test test_gui_wrapper_injects_user_data_dir
run_test test_gui_restart_opens_fresh_profile_window
# The keychain tests select profiles of their own and leave them selected, so
# they run after every test that asserts on the session profile.
run_test test_gui_launch_links_macos_keychain
run_test test_agy_launch_links_macos_keychain
run_test test_launch_keeps_existing_keychain_entry
run_test test_macos_keychain_link_restores_default_keychain

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
