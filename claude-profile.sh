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

# --- Version tracking helpers ---

# Resolves the tool's own install directory (singular "claude-profile",
# distinct from the plural "claude-profiles" data directory). Mirrors
# _cp_data_dir's MSYS handling.
_cp_install_dir() {
    if _cp_is_msys && [ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1; then
        cygpath -u "${LOCALAPPDATA}/claude-profile"
        return 0
    fi
    printf '%s\n' "${XDG_DATA_HOME:-${HOME}/.local/share}/claude-profile"
}

# Reads the installed VERSION file; prints "unknown" if missing/empty.
_cp_installed_version() {
    _cp_ver_file="$(_cp_install_dir)/VERSION"
    if [ -f "$_cp_ver_file" ]; then
        _cp_ver=$(cat "$_cp_ver_file")
        if [ -n "$_cp_ver" ]; then
            printf '%s\n' "$_cp_ver"
            return 0
        fi
    fi
    printf 'unknown\n'
}

# Numeric MAJOR.MINOR.PATCH comparison. Usage: _cp_version_lt A B
# Returns 0 (true, shell success) if A < B, 1 (false) otherwise.
# "unknown" is always considered less than any real version, and equal to
# itself.
_cp_version_lt() {
    _cp_vlt_a="$1"
    _cp_vlt_b="$2"
    if [ "$_cp_vlt_a" = "unknown" ]; then
        [ "$_cp_vlt_b" = "unknown" ] && return 1
        return 0
    fi
    [ "$_cp_vlt_b" = "unknown" ] && return 1
    _cp_vlt_a1=$(printf '%s' "$_cp_vlt_a" | cut -d. -f1)
    _cp_vlt_a2=$(printf '%s' "$_cp_vlt_a" | cut -d. -f2)
    _cp_vlt_a3=$(printf '%s' "$_cp_vlt_a" | cut -d. -f3)
    _cp_vlt_b1=$(printf '%s' "$_cp_vlt_b" | cut -d. -f1)
    _cp_vlt_b2=$(printf '%s' "$_cp_vlt_b" | cut -d. -f2)
    _cp_vlt_b3=$(printf '%s' "$_cp_vlt_b" | cut -d. -f3)
    _cp_vlt_a1=${_cp_vlt_a1:-0}; _cp_vlt_a2=${_cp_vlt_a2:-0}; _cp_vlt_a3=${_cp_vlt_a3:-0}
    _cp_vlt_b1=${_cp_vlt_b1:-0}; _cp_vlt_b2=${_cp_vlt_b2:-0}; _cp_vlt_b3=${_cp_vlt_b3:-0}
    case "$_cp_vlt_a1" in ''|*[!0-9]*) _cp_vlt_a1=0 ;; esac
    case "$_cp_vlt_a2" in ''|*[!0-9]*) _cp_vlt_a2=0 ;; esac
    case "$_cp_vlt_a3" in ''|*[!0-9]*) _cp_vlt_a3=0 ;; esac
    case "$_cp_vlt_b1" in ''|*[!0-9]*) _cp_vlt_b1=0 ;; esac
    case "$_cp_vlt_b2" in ''|*[!0-9]*) _cp_vlt_b2=0 ;; esac
    case "$_cp_vlt_b3" in ''|*[!0-9]*) _cp_vlt_b3=0 ;; esac
    [ "$_cp_vlt_a1" -lt "$_cp_vlt_b1" ] && return 0
    [ "$_cp_vlt_a1" -gt "$_cp_vlt_b1" ] && return 1
    [ "$_cp_vlt_a2" -lt "$_cp_vlt_b2" ] && return 0
    [ "$_cp_vlt_a2" -gt "$_cp_vlt_b2" ] && return 1
    [ "$_cp_vlt_a3" -lt "$_cp_vlt_b3" ] && return 0
    return 1
}

# --- Passive update check ---

_CP_REPO_API="${CLAUDE_PROFILE_UPDATE_API_BASE:-https://api.github.com/repos/quinnjr/claude-code-profiles}"
_CP_ASSET_BASE="${CLAUDE_PROFILE_UPDATE_ASSET_BASE:-https://github.com/quinnjr/claude-code-profiles/releases/download}"
_CP_UPDATE_INTERVAL="${CLAUDE_PROFILE_UPDATE_CHECK_INTERVAL:-86400}"
case "$_CP_UPDATE_INTERVAL" in ''|*[!0-9]*) _CP_UPDATE_INTERVAL=86400 ;; esac

# Extracts and validates a "vX.Y.Z" tag_name from a GitHub releases-API JSON
# response body. Prints the version WITHOUT the leading 'v' on success;
# prints nothing on failure (missing field or doesn't match X.Y.Z).
_cp_extract_tag_version() {
    _cp_etv_tag=$(printf '%s' "$1" | sed -n 's/.*"tag_name" *: *"\([^"]*\)".*/\1/p' | head -n1)
    _cp_etv_tag=${_cp_etv_tag#v}
    case "$_cp_etv_tag" in
        [0-9]*.[0-9]*.[0-9]*)
            case "$_cp_etv_tag" in
                *[!0-9.]*) return 1 ;;
            esac
            printf '%s\n' "$_cp_etv_tag"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Verifies a downloaded file's SHA-256 against a SHA256SUMS file. Usage:
# _cp_verify_checksum <file> <sums-file>. Requires $_cp_sha_cmd to be set by
# the caller (sha256sum or "shasum -a 256").
_cp_verify_checksum() {
    _cp_vc_file="$1"
    _cp_vc_sums="$2"
    _cp_vc_name=$(basename "$_cp_vc_file")
    _cp_vc_expected=$(grep -F " ${_cp_vc_name}" "$_cp_vc_sums" 2>/dev/null | awk '{print $1}' | head -n1)
    [ -n "$_cp_vc_expected" ] || return 1
    _cp_vc_actual=$($_cp_sha_cmd "$_cp_vc_file" | awk '{print $1}')
    [ "$_cp_vc_expected" = "$_cp_vc_actual" ]
}

# Fetches, checksum-verifies, and atomically replaces claude-profile.sh (and
# the shared VERSION file) from the latest GitHub release. Exit status 0 on
# success, 1 on any failure — never leaves a partial install in place.
#
# NOTE: deliberately does NOT use `trap ... EXIT` for temp-dir cleanup.
# claude-profile.sh is sourced into a long-lived interactive shell, so a
# trap set here would persist for the rest of the shell session and fire
# at the wrong time. Cleanup is instead explicit at every return point,
# matching this file's existing "no set -e" / no-trap discipline.
_cp_do_update() {
    _cp_upd_force=0
    case "${1:-}" in
        --force) _cp_upd_force=1 ;;
        "") : ;;
        *) _cp_die "usage: claude-profile update [--force]"; return 1 ;;
    esac

    command -v curl >/dev/null 2>&1 || { _cp_die "update requires curl"; return 1; }
    if command -v sha256sum >/dev/null 2>&1; then
        _cp_sha_cmd="sha256sum"
    elif command -v shasum >/dev/null 2>&1; then
        _cp_sha_cmd="shasum -a 256"
    else
        _cp_die "update requires sha256sum or shasum"
        return 1
    fi

    _cp_upd_resp=$(curl -fsSL --connect-timeout 10 --max-time 30 "${_CP_REPO_API}/releases/latest" 2>/dev/null) || {
        _cp_die "update failed: could not reach GitHub"
        return 1
    }
    _cp_upd_latest=$(_cp_extract_tag_version "$_cp_upd_resp")
    if [ -z "$_cp_upd_latest" ]; then
        _cp_die "update failed: could not determine latest version"
        return 1
    fi
    _cp_upd_tag="v${_cp_upd_latest}"

    _cp_upd_installed=$(_cp_installed_version)
    if [ "$_cp_upd_force" -eq 0 ] && [ "$_cp_upd_installed" != "unknown" ] \
        && ! _cp_version_lt "$_cp_upd_installed" "$_cp_upd_latest"; then
        _cp_die "already up to date (v${_cp_upd_installed}); latest is v${_cp_upd_latest}"
        return 1
    fi

    _cp_upd_install="$(_cp_install_dir)"
    mkdir -p "$_cp_upd_install" || { _cp_die "update failed: could not create install directory"; return 1; }
    _cp_upd_tmpdir=$(mktemp -d "${_cp_upd_install}/.update.XXXXXX") || { _cp_die "update failed: could not create temp directory"; return 1; }
    _cp_upd_base="${_CP_ASSET_BASE}/${_cp_upd_tag}"

    if ! curl -fsSL --connect-timeout 10 --max-time 30 -o "${_cp_upd_tmpdir}/SHA256SUMS" "${_cp_upd_base}/SHA256SUMS" 2>/dev/null; then
        _cp_die "update failed: could not download checksums"
        rm -rf "$_cp_upd_tmpdir"
        return 1
    fi
    if ! curl -fsSL --connect-timeout 10 --max-time 30 -o "${_cp_upd_tmpdir}/VERSION" "${_cp_upd_base}/VERSION" 2>/dev/null; then
        _cp_die "update failed: could not download VERSION"
        rm -rf "$_cp_upd_tmpdir"
        return 1
    fi
    if ! curl -fsSL --connect-timeout 10 --max-time 60 -o "${_cp_upd_tmpdir}/claude-profile.sh" "${_cp_upd_base}/claude-profile.sh" 2>/dev/null; then
        _cp_die "update failed: could not download claude-profile.sh"
        rm -rf "$_cp_upd_tmpdir"
        return 1
    fi

    if ! _cp_verify_checksum "${_cp_upd_tmpdir}/VERSION" "${_cp_upd_tmpdir}/SHA256SUMS"; then
        _cp_die "update failed: VERSION checksum mismatch"
        rm -rf "$_cp_upd_tmpdir"
        return 1
    fi
    if ! _cp_verify_checksum "${_cp_upd_tmpdir}/claude-profile.sh" "${_cp_upd_tmpdir}/SHA256SUMS"; then
        _cp_die "update failed: claude-profile.sh checksum mismatch"
        rm -rf "$_cp_upd_tmpdir"
        return 1
    fi

    _cp_upd_downloaded_version=$(cat "${_cp_upd_tmpdir}/VERSION")
    if [ "$_cp_upd_downloaded_version" != "$_cp_upd_latest" ]; then
        _cp_die "update failed: downloaded VERSION (${_cp_upd_downloaded_version}) does not match release tag (${_cp_upd_latest})"
        rm -rf "$_cp_upd_tmpdir"
        return 1
    fi

    if ! mv -f "${_cp_upd_tmpdir}/claude-profile.sh" "${_cp_upd_install}/claude-profile.sh"; then
        _cp_die "update failed: could not replace claude-profile.sh"
        rm -rf "$_cp_upd_tmpdir"
        return 1
    fi
    if ! mv -f "${_cp_upd_tmpdir}/VERSION" "${_cp_upd_install}/VERSION"; then
        _cp_die "update failed: could not replace VERSION"
        rm -rf "$_cp_upd_tmpdir"
        return 1
    fi
    rm -rf "$_cp_upd_tmpdir"

    case "$_cp_upd_installed" in
        unknown) _cp_upd_installed_display="unknown" ;;
        *) _cp_upd_installed_display="v${_cp_upd_installed}" ;;
    esac
    printf 'Updating claude-profile.sh: %s -> v%s\n' "$_cp_upd_installed_display" "$_cp_upd_latest"
    printf "Done. Run 'source ~/.bashrc' (or restart your shell) to use the new version.\\n"
    return 0
}

# Reads the update-check cache file into _cp_cache_ts / _cp_cache_ver /
# _cp_cache_notified globals. Defaults (0 / unknown / 0) on missing or
# unparseable cache — treated identically, per design, so a corrupted file
# self-heals on the next successful write instead of erroring.
_cp_read_update_cache() {
    _cp_cache_ts=0
    _cp_cache_ver="unknown"
    _cp_cache_notified=0
    _cp_cache_file="$(_cp_install_dir)/.update-check"
    [ -f "$_cp_cache_file" ] || return 0
    _cp_line_n=0
    while IFS= read -r _cp_field; do
        _cp_line_n=$((_cp_line_n + 1))
        case "$_cp_line_n" in
            1) case "$_cp_field" in *[!0-9]*|'') ;; *) _cp_cache_ts="$_cp_field" ;; esac ;;
            2) [ -n "$_cp_field" ] && _cp_cache_ver="$_cp_field" ;;
            3) case "$_cp_field" in 0|1) _cp_cache_notified="$_cp_field" ;; esac ;;
        esac
        [ "$_cp_line_n" -ge 3 ] && break
    done < "$_cp_cache_file"
    return 0
}

# Writes a single value to a file atomically (temp file + rename).
# Usage: _cp_atomic_write FILE VALUE
_cp_atomic_write() {
    _cp_aw_tmp="${1}.tmp.$$"
    { printf '%s\n' "$2" > "$_cp_aw_tmp"; } 2>/dev/null || { rm -f "$_cp_aw_tmp" 2>/dev/null; return 1; }
    mv -f "$_cp_aw_tmp" "$1" 2>/dev/null || { rm -f "$_cp_aw_tmp" 2>/dev/null; return 1; }
    return 0
}

# Rate-limited stderr diagnostic for persistent local cache-file I/O
# failures (permissions, disk full) -- distinct from transient network
# failures, which stay silent by design per _cp_update_check. Best-effort:
# uses a separate marker file so a broken .update-check write doesn't also
# block this diagnostic; if even the marker can't be written, this
# degrades to printing every invocation rather than staying silent forever
# (never worse than the bug being fixed).
#
# Deliberately reuses _CP_UPDATE_INTERVAL (default 86400s) as a rolling
# window approximating the design's "at most once per calendar day" --
# not a literal calendar-day boundary, and coupled to the same
# user-tunable CLAUDE_PROFILE_UPDATE_CHECK_INTERVAL override that governs
# the update check's own polling frequency. Lowering that interval (e.g.
# for testing) also shortens this diagnostic's rate limit; this is an
# accepted simplification, not a separate config knob.
#
# Called from inside _cp_write_update_cache (not from its callers) so the
# already-resolved install dir and epoch are reused rather than
# re-resolved — this also means every current and future caller of
# _cp_write_update_cache gets this diagnostic for free, with no risk of a
# call site forgetting to check the write's return value.
# Usage: _cp_warn_cache_write_failure DIR EPOCH
_cp_warn_cache_write_failure() {
    _cp_wcf_dir="$1"
    _cp_wcf_now="$2"
    _cp_wcf_marker="${_cp_wcf_dir}/.update-check-diag"
    _cp_wcf_last=0
    if [ -f "$_cp_wcf_marker" ]; then
        _cp_wcf_read=$(cat "$_cp_wcf_marker" 2>/dev/null)
        case "$_cp_wcf_read" in ''|*[!0-9]*) ;; *) _cp_wcf_last="$_cp_wcf_read" ;; esac
    fi
    if [ $((_cp_wcf_now - _cp_wcf_last)) -ge "$_CP_UPDATE_INTERVAL" ]; then
        printf 'claude-profile: warning: could not write update-check cache in %s -- update notifications may not work until this is fixed\n' "$_cp_wcf_dir" >&2
        _cp_atomic_write "$_cp_wcf_marker" "$_cp_wcf_now"
    fi
    return 0
}

# Writes the cache atomically (temp file + rename), so concurrent
# invocations can't torn-write it. Usage: _cp_write_update_cache TS VER NOTIFIED
_cp_write_update_cache() {
    _cp_wuc_dir="$(_cp_install_dir)"
    mkdir -p "$_cp_wuc_dir" 2>/dev/null || { _cp_warn_cache_write_failure "$_cp_wuc_dir" "$1"; return 1; }
    _cp_wuc_file="${_cp_wuc_dir}/.update-check"
    _cp_wuc_tmp="${_cp_wuc_file}.tmp.$$"
    if ! printf '%s\n%s\n%s\n' "$1" "$2" "$3" > "$_cp_wuc_tmp" 2>/dev/null; then
        rm -f "$_cp_wuc_tmp" 2>/dev/null
        _cp_warn_cache_write_failure "$_cp_wuc_dir" "$1"
        return 1
    fi
    mv -f "$_cp_wuc_tmp" "$_cp_wuc_file" 2>/dev/null || {
        rm -f "$_cp_wuc_tmp" 2>/dev/null
        _cp_warn_cache_write_failure "$_cp_wuc_dir" "$1"
        return 1
    }
    return 0
}

# Runs the passive update check, rate-limited to once per
# CLAUDE_PROFILE_UPDATE_CHECK_INTERVAL seconds (default 24h). Prints a
# one-line stderr notice the first time a newer version is seen. Every
# failure path is a silent no-op — this must never block or break claude().
_cp_update_check() {
    [ -n "${CLAUDE_PROFILE_NO_UPDATE_CHECK:-}" ] && return 0
    command -v curl >/dev/null 2>&1 || return 0

    _cp_read_update_cache

    _cp_now=$(date +%s 2>/dev/null) || return 0
    case "$_cp_now" in ''|*[!0-9]*) return 0 ;; esac
    _cp_elapsed=$((_cp_now - _cp_cache_ts))

    if [ "$_cp_elapsed" -ge "$_CP_UPDATE_INTERVAL" ]; then
        _cp_resp=$(curl -fsSL --connect-timeout 3 --max-time 3 "${_CP_REPO_API}/releases/latest" 2>/dev/null)
        _cp_new_ver="$_cp_cache_ver"
        if [ -n "$_cp_resp" ]; then
            _cp_extracted=$(_cp_extract_tag_version "$_cp_resp")
            [ -n "$_cp_extracted" ] && _cp_new_ver="$_cp_extracted"
        fi
        if [ "$_cp_new_ver" != "$_cp_cache_ver" ]; then
            _cp_write_update_cache "$_cp_now" "$_cp_new_ver" 0
            _cp_cache_ver="$_cp_new_ver"
            _cp_cache_notified=0
        else
            _cp_write_update_cache "$_cp_now" "$_cp_cache_ver" "$_cp_cache_notified"
        fi
    fi

    if [ "$_cp_cache_notified" = "0" ] && [ "$_cp_cache_ver" != "unknown" ]; then
        _cp_installed=$(_cp_installed_version)
        if _cp_version_lt "$_cp_installed" "$_cp_cache_ver"; then
            case "$_cp_installed" in
                unknown) _cp_installed_display="unknown" ;;
                *) _cp_installed_display="v${_cp_installed}" ;;
            esac
            printf "A new claude-profile version is available (%s -> v%s). Run 'claude-profile update' to upgrade.\\n" \
                "$_cp_installed_display" "$_cp_cache_ver" >&2
            _cp_write_update_cache "$_cp_now" "$_cp_cache_ver" 1
        fi
    fi
    return 0
}

# --- Directory-local profile (.claude-profile) auto-switching ---
#
# A directory may contain a `.claude-profile` file whose first non-empty,
# non-comment line names a profile. Entering that directory (or any
# descendant) switches CLAUDE_CONFIG_DIR to it; leaving reverts to the
# default. Explicit `claude-profile use <name>` pins the session and
# suppresses auto-switching until `claude-profile auto on`.
#
# Environment knobs:
#   CLAUDE_PROFILE_NO_AUTO_SWITCH=1   disable auto-switching entirely
#   CLAUDE_PROFILE_AUTO_QUIET=1       switch silently (no stderr notices)
#
# CLAUDE_PROFILE_AUTO_SET is exported so nested shells know the current
# CLAUDE_CONFIG_DIR came from auto-switching (and may be re-managed) rather
# than from an explicit `use`.

_CP_DOTFILE=".claude-profile"
_CP_CR=$(printf '\r')

_cp_auto_notice() {
    [ -n "${CLAUDE_PROFILE_AUTO_QUIET:-}" ] && return 0
    printf 'claude-profile: %s\n' "$1" >&2
    return 0
}

# Sets _cp_dotfile to the nearest .claude-profile at or above directory $1,
# or empty when none is found. Deliberately uses only parameter expansion
# (no dirname/basename subprocesses): this runs on every shell prompt under
# bash's PROMPT_COMMAND, so a fork per path component would be felt.
_cp_find_dotfile() {
    _cp_dotfile=""
    _cp_fd_dir="$1"
    while :; do
        [ -n "$_cp_fd_dir" ] || _cp_fd_dir="/"
        if [ -f "${_cp_fd_dir%/}/${_CP_DOTFILE}" ]; then
            _cp_dotfile="${_cp_fd_dir%/}/${_CP_DOTFILE}"
            return 0
        fi
        [ "$_cp_fd_dir" = "/" ] && break
        _cp_fd_dir="${_cp_fd_dir%/*}"
    done
    return 1
}

# Sets _cp_dotname to the first non-empty, non-comment line of file $1,
# with surrounding whitespace and any trailing CR stripped (so a file
# authored on Windows and used from WSL/Git Bash still resolves).
_cp_read_dotfile() {
    _cp_dotname=""
    while IFS= read -r _cp_rd_line || [ -n "$_cp_rd_line" ]; do
        _cp_rd_line="${_cp_rd_line%"$_CP_CR"}"
        while :; do
            case "$_cp_rd_line" in
                " "*|"	"*) _cp_rd_line="${_cp_rd_line#?}" ;;
                *" "|*"	") _cp_rd_line="${_cp_rd_line%?}" ;;
                *) break ;;
            esac
        done
        case "$_cp_rd_line" in
            ''|'#'*) continue ;;
        esac
        _cp_dotname="$_cp_rd_line"
        return 0
    done < "$1"
    return 1
}

# Resolves and applies the directory-local profile for $PWD. Safe to call
# repeatedly: it short-circuits when the directory hasn't changed, which
# also rate-limits the warnings below to once per directory entry rather
# than once per prompt.
_cp_auto_switch() {
    [ -n "${CLAUDE_PROFILE_NO_AUTO_SWITCH:-}" ] && return 0
    [ "${_CP_AUTO_OFF:-0}" = "1" ] && return 0
    [ "${PWD:-}" = "${_CP_AUTO_LAST_PWD:-}" ] && return 0
    _CP_AUTO_LAST_PWD="${PWD:-}"

    # An explicitly-chosen profile (claude-profile use, or a CLAUDE_CONFIG_DIR
    # inherited from outside) wins over any .claude-profile file.
    if [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ "$CLAUDE_CONFIG_DIR" != "${CLAUDE_PROFILE_AUTO_SET:-}" ]; then
        return 0
    fi

    _cp_dotname=""
    if _cp_find_dotfile "${PWD:-}"; then
        _cp_read_dotfile "$_cp_dotfile"
    fi

    if [ -z "$_cp_dotname" ]; then
        if [ -n "${CLAUDE_PROFILE_AUTO_SET:-}" ]; then
            unset CLAUDE_CONFIG_DIR
            unset CLAUDE_PROFILE_AUTO_SET
            _cp_auto_notice "directory profile cleared; using the default profile"
        fi
        [ -n "$_cp_dotfile" ] && _cp_die "ignoring ${_cp_dotfile}: no profile name in file"
        return 0
    fi

    case "$_cp_dotname" in
        .*|*..*|*/*|*\\*|*[!A-Za-z0-9_-]*)
            _cp_die "ignoring ${_cp_dotfile}: invalid profile name '${_cp_dotname}'"
            return 1
            ;;
    esac

    [ -n "${_CP_DATA_CACHE:-}" ] || _CP_DATA_CACHE=$(_cp_data_dir)
    _cp_as_dir="${_CP_DATA_CACHE}/${_cp_dotname}"
    if [ ! -d "$_cp_as_dir" ]; then
        _cp_die "ignoring ${_cp_dotfile}: profile '${_cp_dotname}' does not exist"
        return 1
    fi

    if [ "${CLAUDE_CONFIG_DIR:-}" = "$_cp_as_dir" ]; then
        export CLAUDE_PROFILE_AUTO_SET="$_cp_as_dir"
        return 0
    fi
    export CLAUDE_CONFIG_DIR="$_cp_as_dir"
    export CLAUDE_PROFILE_AUTO_SET="$_cp_as_dir"
    _cp_auto_notice "switched to profile '${_cp_dotname}' (from ${_cp_dotfile})"
    return 0
}

# Registers _cp_auto_switch with whatever directory-change mechanism the
# running shell offers. zsh has a real chpwd hook; bash only has
# PROMPT_COMMAND; everything else (dash, ash, ksh) gets a cd wrapper, which
# covers the common case even though it misses pushd/popd.
if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _cp_auto_switch
elif [ -n "${BASH_VERSION:-}" ]; then
    case "${PROMPT_COMMAND:-}" in
        *_cp_auto_switch*) : ;;
        '') PROMPT_COMMAND="_cp_auto_switch" ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND%;};_cp_auto_switch" ;;
    esac
else
    # `command cd` bypasses this function, so re-sourcing can't recurse.
    # eval keeps the definition out of zsh's parser, which would otherwise
    # alias-expand `cd` at source time and abort with a parse error.
    eval 'cd() {
        command cd "$@" || return $?
        _cp_auto_switch
    }'
fi

# Resolve once at source time so a shell started inside a .claude-profile
# tree is already on the right profile.
_cp_auto_switch

# --- claude() wrapper ---
# Auto-resolves the default profile before calling the real claude binary.
# If CLAUDE_CONFIG_DIR is already set (e.g. via 'claude-profile use'),
# it passes through without overriding.

claude() {
    _cp_update_check
    # Covers shells whose cd we couldn't hook (and directory changes made by
    # something other than cd) — resolving here is cheap and idempotent.
    _cp_auto_switch
    if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
        _cp_data=$(_cp_data_dir)
        _cp_def="${_cp_data}/.default"
        if [ -f "$_cp_def" ]; then
            _cp_name=$(cat "$_cp_def")
            if [ -n "$_cp_name" ] && [ -d "${_cp_data}/${_cp_name}" ]; then
                export CLAUDE_CONFIG_DIR="${_cp_data}/${_cp_name}"
                # Mark it auto-managed, not an explicit pin: without this, the
                # first `claude` run would freeze the session on the default
                # profile and later .claude-profile directories would be
                # ignored.
                export CLAUDE_PROFILE_AUTO_SET="$CLAUDE_CONFIG_DIR"
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
            # Dropping the auto-set marker pins the session: subsequent
            # directory changes will no longer override this choice.
            unset CLAUDE_PROFILE_AUTO_SET
            printf 'Switched to profile: %s\n' "$_cp_name"
            ;;

        auto)
            shift
            case "${1:-}" in
                on)
                    unset _CP_AUTO_OFF
                    unset CLAUDE_CONFIG_DIR
                    unset CLAUDE_PROFILE_AUTO_SET
                    _CP_AUTO_LAST_PWD=""
                    _cp_auto_switch
                    printf 'Directory-local auto-switching enabled.\n'
                    ;;
                off)
                    _CP_AUTO_OFF=1
                    printf 'Directory-local auto-switching disabled for this session.\n'
                    ;;
                ""|status)
                    if [ -n "${CLAUDE_PROFILE_NO_AUTO_SWITCH:-}" ]; then
                        printf 'Auto-switching: disabled (CLAUDE_PROFILE_NO_AUTO_SWITCH is set)\n'
                    elif [ "${_CP_AUTO_OFF:-0}" = "1" ]; then
                        printf 'Auto-switching: disabled for this session\n'
                    elif [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ "$CLAUDE_CONFIG_DIR" != "${CLAUDE_PROFILE_AUTO_SET:-}" ]; then
                        printf 'Auto-switching: pinned (an explicit profile is active)\n'
                        printf "Run 'claude-profile auto on' to resume auto-switching.\\n"
                    else
                        printf 'Auto-switching: enabled\n'
                    fi
                    if _cp_find_dotfile "${PWD:-}"; then
                        _cp_read_dotfile "$_cp_dotfile"
                        printf 'Directory profile: %s (%s)\n' "${_cp_dotname:-<empty>}" "$_cp_dotfile"
                    else
                        printf 'Directory profile: none in scope\n'
                    fi
                    ;;
                *)
                    _cp_die "usage: claude-profile auto [on|off|status]"
                    return 1
                    ;;
            esac
            ;;

        local)
            shift
            case "${1:-}" in
                "")
                    if _cp_find_dotfile "${PWD:-}"; then
                        _cp_read_dotfile "$_cp_dotfile"
                        printf '%s\n' "$_cp_dotfile"
                        printf 'Profile: %s\n' "${_cp_dotname:-<empty>}"
                    else
                        _cp_die "no ${_CP_DOTFILE} found in this directory or any parent"
                        return 1
                    fi
                    ;;
                --remove|--clear)
                    if [ ! -f "./${_CP_DOTFILE}" ]; then
                        _cp_die "no ${_CP_DOTFILE} in the current directory"
                        return 1
                    fi
                    rm -f "./${_CP_DOTFILE}" || return 1
                    printf 'Removed %s\n' "${PWD}/${_CP_DOTFILE}"
                    _CP_AUTO_LAST_PWD=""
                    _cp_auto_switch
                    ;;
                -*)
                    _cp_die "unknown option '$1'"
                    return 1
                    ;;
                *)
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
                    printf '%s\n' "$_cp_name" > "./${_CP_DOTFILE}" || return 1
                    printf 'Wrote %s (profile: %s)\n' "${PWD}/${_CP_DOTFILE}" "$_cp_name"
                    _CP_AUTO_LAST_PWD=""
                    _cp_auto_switch
                    ;;
            esac
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
                cat > "$_cp_settings" <<'SETTINGSEOF'
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
                printf 'Config skeleton written to: %s\n' "$_cp_settings"
                printf 'Tip: remove "ANTHROPIC_BASE_URL" if using the default Anthropic endpoint.\n'
                if [ -n "${VISUAL:-}" ]; then
                    "${VISUAL}" "$_cp_settings"
                elif [ -n "${EDITOR:-}" ]; then
                    "${EDITOR}" "$_cp_settings"
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

        version)
            _cp_installed_version
            ;;

        update)
            shift
            _cp_do_update "${1:-}"
            ;;

        help|-h|--help)
            cat <<'HELPEOF'
Usage: claude-profile [command] [args...]

Commands:
    (no command)            Show current profile status
    use <name>              Switch session to the named profile (pins it)
    create [--init] <name>  Create a new profile (--init writes a settings.json skeleton)
    list, ls                List all profiles
    default [name]          Get or set the default profile
    local [name]            Show, set (.claude-profile), or --remove the
                            directory-local profile for the current directory
    auto [on|off|status]    Control directory-local auto-switching
    which [name]            Show the resolved config directory path
    version                 Show the installed version
    update [--force]        Update to the latest release
    delete <name>           Delete a profile
    help, -h, --help        Show this help message

The claude command automatically uses the default profile. Use
'claude-profile use <name>' to override for the current session.

A directory containing a .claude-profile file (holding a profile name)
switches the shell to that profile on cd, and reverts on leaving. An
explicit 'claude-profile use' pins the session and wins over any
.claude-profile until 'claude-profile auto on'. Set
CLAUDE_PROFILE_NO_AUTO_SWITCH=1 to disable, CLAUDE_PROFILE_AUTO_QUIET=1
to switch silently.

Examples:
    claude-profile create work
    claude-profile create --init work
    claude-profile default work
    claude-profile use work
    claude                          # runs with "work" profile
    claude-profile                  # shows active/default status
    claude-profile local work       # pin this directory tree to "work"
    claude-profile local --remove   # drop the directory-local profile
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
                if [ "${CLAUDE_CONFIG_DIR:-}" = "${CLAUDE_PROFILE_AUTO_SET:-}" ] && _cp_find_dotfile "${PWD:-}"; then
                    printf 'Active profile: %s (from %s)\n' "$_cp_active" "$_cp_dotfile"
                else
                    printf 'Active profile: %s\n' "$_cp_active"
                fi
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
