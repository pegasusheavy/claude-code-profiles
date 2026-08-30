#!/bin/sh
set -e

# claude-code-profiles installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.sh | sh
#   wget -qO- https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.sh | sh

REPO_BASE="https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main"

# --- Helpers ---

info() {
    printf '  %s\n' "$1"
}

step() {
    printf '\n=> %s\n' "$1"
}

warn() {
    printf '  [warn] %s\n' "$1" >&2
}

fail() {
    printf '  [error] %s\n' "$1" >&2
    exit 1
}

# --- Detect download tool ---

DOWNLOAD_CMD=""

detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOAD_CMD="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOAD_CMD="wget"
    else
        fail "Neither curl nor wget found. Please install one and re-run."
    fi
}

# Download a URL to a file: download_file <url> <dest>
download_file() {
    _dl_url="$1"
    _dl_dest="$2"
    case "$DOWNLOAD_CMD" in
        curl) curl -fsSL --connect-timeout 10 --max-time 60 "$_dl_url" -o "$_dl_dest" ;;
        wget) wget -qO "$_dl_dest" --timeout=60 "$_dl_url" ;;
    esac
}

# --- Detect platform ---

detect_platform() {
    _os="$(uname -s)"
    case "$_os" in
        Linux)
            if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
            else
                PLATFORM="linux"
            fi
            ;;
        Darwin)
            PLATFORM="macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM="gitbash"
            ;;
        *)
            # Some MSYS2 builds report a non-standard uname; fall back to MSYSTEM.
            if [ -n "${MSYSTEM:-}" ]; then
                PLATFORM="gitbash"
            else
                PLATFORM="unknown"
                warn "Unrecognized platform: $_os (proceeding anyway)"
            fi
            ;;
    esac
}

# --- Main ---

main() {
    printf 'claude-code-profiles installer\n'
    printf '================================\n'

    step "Detecting platform..."
    detect_platform
    info "Platform: $PLATFORM"

    step "Detecting download tool..."
    detect_downloader
    info "Using: $DOWNLOAD_CMD"

    INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile"

    step "Creating install directory..."
    mkdir -p "$INSTALL_DIR"
    info "Install directory: $INSTALL_DIR"

    step "Downloading claude-profile.sh..."
    _tmp_file="$(mktemp)"
    trap 'rm -f "$_tmp_file"' EXIT
    download_file "${REPO_BASE}/claude-profile.sh" "$_tmp_file" || fail "Download failed. Check your network connection."
    info "Downloaded successfully."

    step "Installing to ${INSTALL_DIR}/claude-profile.sh..."
    cp "$_tmp_file" "${INSTALL_DIR}/claude-profile.sh"
    chmod +r "${INSTALL_DIR}/claude-profile.sh"
    rm -f "$_tmp_file"
    info "Installed: ${INSTALL_DIR}/claude-profile.sh"

    step "Downloading agent-profile.sh..."
    _tmp_file="$(mktemp)"
    download_file "${REPO_BASE}/agent-profile.sh" "$_tmp_file" || fail "Download failed. Check your network connection."
    cp "$_tmp_file" "${INSTALL_DIR}/agent-profile.sh"
    chmod +r "${INSTALL_DIR}/agent-profile.sh"
    rm -f "$_tmp_file"
    info "Installed: ${INSTALL_DIR}/agent-profile.sh"

    step "Downloading claude-profile.fish..."
    _tmp_file="$(mktemp)"
    download_file "${REPO_BASE}/claude-profile.fish" "$_tmp_file" || fail "Download failed. Check your network connection."
    cp "$_tmp_file" "${INSTALL_DIR}/claude-profile.fish"
    chmod +r "${INSTALL_DIR}/claude-profile.fish"
    rm -f "$_tmp_file"
    info "Installed: ${INSTALL_DIR}/claude-profile.fish"

    step "Downloading agent-profile.fish..."
    _tmp_file="$(mktemp)"
    download_file "${REPO_BASE}/agent-profile.fish" "$_tmp_file" || fail "Download failed. Check your network connection."
    cp "$_tmp_file" "${INSTALL_DIR}/agent-profile.fish"
    chmod +r "${INSTALL_DIR}/agent-profile.fish"
    rm -f "$_tmp_file"
    info "Installed: ${INSTALL_DIR}/agent-profile.fish"

    step "Downloading VERSION..."
    if download_file "${REPO_BASE}/VERSION" "${INSTALL_DIR}/VERSION"; then
        info "Installed: ${INSTALL_DIR}/VERSION"
    else
        warn "Could not download VERSION file. Update notifications will show 'unknown' until the next successful 'claude-profile update'."
    fi

    # Detect shell profile and auto-append source line
    step "Configuring shell..."
    _shell_name=$(basename "${SHELL:-/bin/sh}")
    case "$_shell_name" in
        zsh)  _profile_file="${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) _profile_file="${HOME}/.bashrc" ;;
        fish)
            _profile_file="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
            _claude_source_marker='claude-profile.fish'
            _agent_source_marker='agent-profile.fish'
            _source_line="source '${INSTALL_DIR}/claude-profile.fish'"
            _agent_source_line="source '${INSTALL_DIR}/agent-profile.fish'"
            ;;
        *)    _profile_file="" ;;
    esac

    if [ -z "${_source_line:-}" ]; then
        # Single quotes are intentional: the expression must expand in the
        # user's shell at login, not during installation.
        # shellcheck disable=SC2016
        _source_line='. "${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile/claude-profile.sh"'
        _agent_source_line='. "${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile/agent-profile.sh"'
        _claude_source_marker='claude-profile.sh'
        _agent_source_marker='agent-profile.sh'
    fi

    if [ -n "$_profile_file" ]; then
        mkdir -p "$(dirname "$_profile_file")"
        # Idempotent: check if already present
        if [ -f "$_profile_file" ] && grep -qF "$_claude_source_marker" "$_profile_file" 2>/dev/null; then
            info "Source line already in $_profile_file"
        else
            printf '\n# claude-profile: manage Claude Code configuration profiles\n%s\n' "$_source_line" >> "$_profile_file"
            info "Added source line to $_profile_file"
        fi
    else
        info "Could not detect shell profile. Add this to your shell profile manually:"
        info "  $_source_line"
    fi

    if [ -n "$_profile_file" ]; then
        if [ -f "$_profile_file" ] && grep -qF "$_agent_source_marker" "$_profile_file" 2>/dev/null; then
            info "Agent profile source line already in $_profile_file"
        else
            printf '\n# agent-profile: manage Antigravity and Codex profiles\n%s\n' "$_agent_source_line" >> "$_profile_file"
            info "Added agent profile source line to $_profile_file"
        fi
    else
        info "  $_agent_source_line"
    fi

    step "Done!"
    info ""
    info "Restart your shell (or run: source $_profile_file) then:"
    info ""
    info "  claude-profile create work     # Create a profile"
    info "  claude-profile default work    # Set it as default"
    info "  claude                         # Runs with the active profile"
    info ""
    info "  agent-profile copy antigravity hafez  # Snapshot the current Antigravity login"
    info "  agent-profile default antigravity hafez"
    info "  agy                               # Runs with the active Antigravity profile"
    info ""
    info "Run 'claude-profile help' for all commands."
    printf '\n'
}

main
