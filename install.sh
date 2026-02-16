#!/bin/sh
set -e

# claude-code-profiles installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.sh | sh
#   wget -qO- https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.sh | sh
#
# Environment variables:
#   INSTALL_DIR  - Override the install directory (default: ~/.local/bin or /usr/local/bin)

REPO_BASE="https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main"
SCRIPT_NAME="claude-profile"

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
        curl) curl -fsSL "$_dl_url" -o "$_dl_dest" ;;
        wget) wget -qO "$_dl_dest" "$_dl_url" ;;
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
        *)
            PLATFORM="unknown"
            warn "Unrecognized platform: $_os (proceeding anyway)"
            ;;
    esac
}

# --- Determine install directory ---

determine_install_dir() {
    # Respect explicit override
    if [ -n "${INSTALL_DIR:-}" ]; then
        TARGET_DIR="$INSTALL_DIR"
        return
    fi

    # Prefer ~/.local/bin (user-local, no sudo needed)
    _local_bin="${HOME}/.local/bin"
    if [ -d "$_local_bin" ] && [ -w "$_local_bin" ]; then
        TARGET_DIR="$_local_bin"
        return
    fi

    # If ~/.local/bin doesn't exist but ~/.local does (or HOME is writable), create it
    if [ ! -d "$_local_bin" ]; then
        _local_parent="${HOME}/.local"
        if [ -d "$_local_parent" ] && [ -w "$_local_parent" ]; then
            mkdir -p "$_local_bin"
            TARGET_DIR="$_local_bin"
            return
        fi
        # ~/.local doesn't exist either; try creating the whole path
        if [ -w "$HOME" ]; then
            mkdir -p "$_local_bin"
            TARGET_DIR="$_local_bin"
            return
        fi
    fi

    # Fall back to /usr/local/bin (may need sudo)
    if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
        TARGET_DIR="/usr/local/bin"
        return
    fi

    # /usr/local/bin exists but isn't writable -- try with sudo
    if [ -d "/usr/local/bin" ] && command -v sudo >/dev/null 2>&1; then
        TARGET_DIR="/usr/local/bin"
        USE_SUDO=1
        return
    fi

    fail "Could not determine install directory. Set INSTALL_DIR and re-run."
}

# --- Check PATH ---

check_path() {
    case ":${PATH}:" in
        *":${TARGET_DIR}:"*)
            return 0
            ;;
    esac
    return 1
}

# --- Main ---

main() {
    USE_SUDO=0

    printf 'claude-code-profiles installer\n'
    printf '================================\n'

    step "Detecting platform..."
    detect_platform
    info "Platform: $PLATFORM"

    step "Detecting download tool..."
    detect_downloader
    info "Using: $DOWNLOAD_CMD"

    step "Determining install directory..."
    determine_install_dir
    if [ "$USE_SUDO" -eq 1 ]; then
        info "Install directory: $TARGET_DIR (will use sudo)"
    else
        info "Install directory: $TARGET_DIR"
    fi

    step "Downloading $SCRIPT_NAME..."
    _tmp_file="$(mktemp)"
    trap 'rm -f "$_tmp_file"' EXIT
    download_file "${REPO_BASE}/${SCRIPT_NAME}" "$_tmp_file" || fail "Download failed. Check your network connection."
    info "Downloaded successfully."

    step "Installing to ${TARGET_DIR}/${SCRIPT_NAME}..."
    if [ "$USE_SUDO" -eq 1 ]; then
        sudo cp "$_tmp_file" "${TARGET_DIR}/${SCRIPT_NAME}"
        sudo chmod +x "${TARGET_DIR}/${SCRIPT_NAME}"
    else
        cp "$_tmp_file" "${TARGET_DIR}/${SCRIPT_NAME}"
        chmod +x "${TARGET_DIR}/${SCRIPT_NAME}"
    fi
    info "Installed: ${TARGET_DIR}/${SCRIPT_NAME}"

    # PATH check
    if ! check_path; then
        step "PATH notice"
        warn "$TARGET_DIR is not in your PATH."
        info "Add it by appending one of the following to your shell profile:"
        info ""
        info "  For bash (~/.bashrc):    export PATH=\"${TARGET_DIR}:\$PATH\""
        info "  For zsh  (~/.zshrc):     export PATH=\"${TARGET_DIR}:\$PATH\""
        info "  For fish (~/.config/fish/config.fish):  fish_add_path ${TARGET_DIR}"
        info ""
        info "Then restart your shell or run:  export PATH=\"${TARGET_DIR}:\$PATH\""
    fi

    step "Done!"
    info ""
    info "Quick start:"
    info "  claude-profile create work     # Create a profile"
    info "  claude-profile default work    # Set it as default"
    info "  claude-profile                 # Launch Claude with the profile"
    info ""
    info "Run 'claude-profile help' for all commands."
    printf '\n'
}

main
