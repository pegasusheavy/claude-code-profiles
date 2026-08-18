@echo off
setlocal enabledelayedexpansion

:: --- Platform-aware data directory ---
:: Uses %LOCALAPPDATA%\claude-profiles on Windows
set "DATA_DIR=%LOCALAPPDATA%\claude-profiles"
set "DEFAULT_FILE=%DATA_DIR%\.default"

:: --- Version tracking ---
set "_CP_INSTALL_DIR=%LOCALAPPDATA%\claude-profile"
set "_CP_VERSION_FILE=%_CP_INSTALL_DIR%\VERSION"
set "_CP_UPDATE_CACHE=%_CP_INSTALL_DIR%\.update-check"
set "_CP_REPO_API=https://api.github.com/repos/quinnjr/claude-code-profiles"
if defined CLAUDE_PROFILE_UPDATE_API_BASE set "_CP_REPO_API=%CLAUDE_PROFILE_UPDATE_API_BASE%"
set "_CP_ASSET_BASE=https://github.com/quinnjr/claude-code-profiles/releases/download"
if defined CLAUDE_PROFILE_UPDATE_ASSET_BASE set "_CP_ASSET_BASE=%CLAUDE_PROFILE_UPDATE_ASSET_BASE%"
set "_CP_UPDATE_INTERVAL=86400"
if defined CLAUDE_PROFILE_UPDATE_CHECK_INTERVAL set "_CP_UPDATE_INTERVAL=%CLAUDE_PROFILE_UPDATE_CHECK_INTERVAL%"
echo %_CP_UPDATE_INTERVAL%| findstr /R "^[0-9][0-9]*$" >nul 2>&1 || set "_CP_UPDATE_INTERVAL=86400"

:: --- Dispatcher ---
call :cp_update_check
:: No arguments: launch with default profile
if "%~1"=="" goto :cmd_launch_default

:: Command dispatch
if "%~1"=="create"  goto :dispatch_create
if "%~1"=="local"   goto :dispatch_local
if "%~1"=="list"    goto :dispatch_list
if "%~1"=="ls"      goto :dispatch_list
if "%~1"=="default" goto :dispatch_default
if "%~1"=="which"   goto :dispatch_which
if "%~1"=="use"     goto :dispatch_use
if "%~1"=="delete"  goto :dispatch_delete
if "%~1"=="help"    goto :usage
if "%~1"=="-h"      goto :usage
if "%~1"=="--help"  goto :usage
if "%~1"=="version" goto :dispatch_version
if "%~1"=="update"  goto :dispatch_update

:: Flags without a subcommand are not supported
set "_first=%~1"
if "!_first:~0,1!"=="-" (
    echo claude-profile: unknown command '%~1'. Run 'claude-profile help' for usage. >&2
    exit /b 1
)

:: Unknown command
echo claude-profile: unknown command '%~1'. Run 'claude-profile help' for usage. >&2
exit /b 1

:: --- Dispatch helpers (shift then jump) ---

:dispatch_create
shift
goto :cmd_create

:dispatch_local
shift
goto :cmd_local

:dispatch_list
shift
goto :cmd_list

:dispatch_default
shift
goto :cmd_default

:dispatch_which
shift
goto :cmd_which

:dispatch_use
shift
goto :cmd_use

:dispatch_delete
shift
goto :cmd_delete

:dispatch_version
shift
goto :cmd_version

:dispatch_update
shift
goto :cmd_update

:get_epoch
:: cmd has no native epoch-time support; PowerShell ships with every
:: supported Windows version, so shell out to it rather than reinventing
:: date arithmetic in batch.
set "_cp_epoch="
for /f %%e in ('powershell -NoProfile -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()" 2^>nul') do set "_cp_epoch=%%e"
if not defined _cp_epoch set "_cp_epoch=0"
goto :eof

:: extract_tag_version <raw findstr line containing "tag_name":"..."> ->
:: sets _cp_tag_version (without leading v) on success, leaves it undefined
:: on failure.
:extract_tag_version
set "_cp_tag_version="
set "_etv_line=%~1"
for /f "tokens=2 delims=:" %%v in ("!_etv_line!") do set "_etv_raw=%%v"
set "_etv_raw=!_etv_raw:"=!"
set "_etv_raw=!_etv_raw: =!"
set "_etv_raw=!_etv_raw:,=!"
if "!_etv_raw:~0,1!"=="v" set "_etv_raw=!_etv_raw:~1!"
echo !_etv_raw!| findstr /R "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
if not errorlevel 1 set "_cp_tag_version=!_etv_raw!"
goto :eof

:: version_lt <a> <b> -> errorlevel 0 if a<b, 1 otherwise.
:: "unknown" is always < any real version, and equal to itself.
:version_lt
set "_vlt_a=%~1"
set "_vlt_b=%~2"
if "!_vlt_a!"=="unknown" (
    if "!_vlt_b!"=="unknown" (exit /b 1) else (exit /b 0)
)
if "!_vlt_b!"=="unknown" exit /b 1
for /f "tokens=1-3 delims=." %%x in ("!_vlt_a!") do (set "_vlt_a1=%%x" & set "_vlt_a2=%%y" & set "_vlt_a3=%%z")
for /f "tokens=1-3 delims=." %%x in ("!_vlt_b!") do (set "_vlt_b1=%%x" & set "_vlt_b2=%%y" & set "_vlt_b3=%%z")
if !_vlt_a1! lss !_vlt_b1! exit /b 0
if !_vlt_a1! gtr !_vlt_b1! exit /b 1
if !_vlt_a2! lss !_vlt_b2! exit /b 0
if !_vlt_a2! gtr !_vlt_b2! exit /b 1
if !_vlt_a3! lss !_vlt_b3! exit /b 0
exit /b 1

:: Rate-limited stderr diagnostic for persistent local cache-file I/O
:: failures (permissions, disk full) -- distinct from transient network
:: failures, which stay silent by design in :cp_update_check. Best-effort:
:: uses a separate marker file so a broken .update-check write doesn't
:: also block this diagnostic; if even the marker can't be written, this
:: degrades to printing every invocation rather than staying silent
:: forever (never worse than the bug being fixed).
::
:: Deliberately reuses _CP_UPDATE_INTERVAL (default 86400s) as a rolling
:: window approximating "at most once per calendar day" -- not a literal
:: calendar-day boundary, and coupled to the same user-tunable
:: CLAUDE_PROFILE_UPDATE_CHECK_INTERVAL override that governs the update
:: check's own polling frequency. This is an accepted simplification, not
:: a separate config knob (matches the sh/ps1 implementations' tradeoff).
::
:: Called from inside :write_update_cache (not from its callers) so the
:: epoch it already received as %~1 is reused directly instead of a
:: second `call :get_epoch` (a second powershell.exe spawn) -- this also
:: means every current and future caller of :write_update_cache gets this
:: diagnostic for free, with no risk of a call site forgetting to check
:: the errorlevel.
:: Usage: call :warn_cache_write_failure <epoch>
:warn_cache_write_failure
set "_wcf_now=%~1"
set "_wcf_marker=%_CP_INSTALL_DIR%\.update-check-diag"
set "_wcf_last=0"
if exist "!_wcf_marker!" set /p _wcf_last=<"!_wcf_marker!"
echo !_wcf_last!| findstr /R "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 set "_wcf_last=0"
set /a _wcf_elapsed=_wcf_now-_wcf_last
if !_wcf_elapsed! geq !_CP_UPDATE_INTERVAL! (
    echo claude-profile: warning: could not write update-check cache in %_CP_INSTALL_DIR% -- update notifications may not work until this is fixed >&2
    set "_wcf_tmp=!_wcf_marker!.tmp.%RANDOM%"
    2>nul >"!_wcf_tmp!" echo !_wcf_now!
    if exist "!_wcf_tmp!" (
        move /y "!_wcf_tmp!" "!_wcf_marker!" >nul 2>&1
        if errorlevel 1 del /f /q "!_wcf_tmp!" >nul 2>&1
    )
)
goto :eof

:: write_update_cache <epoch> <version> <notified> — atomic via temp+rename.
:: Signals success/failure via errorlevel (exit /b 0/1) so callers can
:: detect persistent local cache I/O failures; on failure it also invokes
:: the rate-limited diagnostic above itself, so callers don't need to.
:write_update_cache
if not exist "%_CP_INSTALL_DIR%" mkdir "%_CP_INSTALL_DIR%" >nul 2>&1
set "_wuc_tmp=%_CP_UPDATE_CACHE%.tmp.%RANDOM%"
(
    echo %~1
    echo %~2
    echo %~3
) 2>nul >"!_wuc_tmp!"
if not exist "!_wuc_tmp!" (
    call :warn_cache_write_failure "%~1"
    exit /b 1
)
:: A disk-full failure mid-write can leave a truncated-but-existing temp
:: file, which `if exist` alone can't detect. Read back the third line
:: and confirm it matches what we tried to write, catching truncation
:: before it gets moved into place as the real cache file.
set "_wuc_verify="
set "_wuc_line=0"
for /f "usebackq delims=" %%L in ("!_wuc_tmp!") do (
    set /a _wuc_line+=1
    if "!_wuc_line!"=="3" set "_wuc_verify=%%L"
)
if not "!_wuc_verify!"=="%~3" (
    del /f /q "!_wuc_tmp!" >nul 2>&1
    call :warn_cache_write_failure "%~1"
    exit /b 1
)
move /y "!_wuc_tmp!" "%_CP_UPDATE_CACHE%" >nul 2>&1
if errorlevel 1 (
    del /f /q "!_wuc_tmp!" >nul 2>&1
    call :warn_cache_write_failure "%~1"
    exit /b 1
)
exit /b 0

:cp_update_check
if defined CLAUDE_PROFILE_NO_UPDATE_CHECK goto :eof
where curl >nul 2>&1
if errorlevel 1 goto :eof

set "_cpu_ts=0"
set "_cpu_ver=unknown"
set "_cpu_notified=0"
if exist "%_CP_UPDATE_CACHE%" (
    set "_cpu_line=0"
    for /f "usebackq delims=" %%L in ("%_CP_UPDATE_CACHE%") do (
        set /a _cpu_line+=1
        if "!_cpu_line!"=="1" set "_cpu_ts=%%L"
        if "!_cpu_line!"=="2" set "_cpu_ver=%%L"
        if "!_cpu_line!"=="3" set "_cpu_notified=%%L"
    )
)

call :get_epoch
set /a _cpu_elapsed=_cp_epoch-_cpu_ts

if !_cpu_elapsed! geq !_CP_UPDATE_INTERVAL! (
    set "_cpu_resp_file=%TEMP%\cp-release-%RANDOM%.json"
    curl -fsSL --connect-timeout 3 --max-time 3 -o "!_cpu_resp_file!" "%_CP_REPO_API%/releases/latest" >nul 2>&1
    set "_cpu_new_ver=!_cpu_ver!"
    if exist "!_cpu_resp_file!" (
        set "_cpu_tagline="
        for /f "usebackq delims=" %%T in (`findstr /R "\"tag_name\"" "!_cpu_resp_file!"`) do set "_cpu_tagline=%%T"
        del /f /q "!_cpu_resp_file!" >nul 2>&1
        if defined _cpu_tagline (
            call :extract_tag_version "!_cpu_tagline!"
            if defined _cp_tag_version set "_cpu_new_ver=!_cp_tag_version!"
        )
    )
    if not "!_cpu_new_ver!"=="!_cpu_ver!" (
        call :write_update_cache "!_cp_epoch!" "!_cpu_new_ver!" "0"
        set "_cpu_ver=!_cpu_new_ver!"
        set "_cpu_notified=0"
    ) else (
        call :write_update_cache "!_cp_epoch!" "!_cpu_ver!" "!_cpu_notified!"
    )
)

if "!_cpu_notified!"=="0" if not "!_cpu_ver!"=="unknown" (
    set "_cpu_installed=unknown"
    if exist "%_CP_VERSION_FILE%" set /p _cpu_installed=<"%_CP_VERSION_FILE%"
    if "!_cpu_installed!"=="" set "_cpu_installed=unknown"
    if not "!_cpu_installed!"=="unknown" (
        echo !_cpu_installed!| findstr /R "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
        if errorlevel 1 set "_cpu_installed=unknown"
    )
    call :version_lt "!_cpu_installed!" "!_cpu_ver!"
    if not errorlevel 1 (
        set "_cpu_installed_display=v!_cpu_installed!"
        if "!_cpu_installed!"=="unknown" set "_cpu_installed_display=unknown"
        echo A new claude-profile version is available ^(!_cpu_installed_display! -^> v!_cpu_ver!^). Run 'claude-profile update' to upgrade. >&2
        call :write_update_cache "!_cp_epoch!" "!_cpu_ver!" "1"
    )
)
goto :eof

:: --- Usage ---

:usage
echo Usage: claude-profile [command] [args...]
echo.
echo Commands:
echo     (no command)            Activate the .claude-profile or default profile
echo     use ^<name^>              Activate the named profile
echo     create ^<name^>           Create a new profile
echo     list, ls                List all profiles
echo     default [name]          Get or set the default profile
echo     local [name]            Show, set (.claude-profile), or --remove the
echo                             directory-local profile for this directory
echo     delete ^<name^>           Delete a profile
echo     which [name]            Show the resolved config directory path
echo     version                 Show the installed version
echo     update [--force]        Update to the latest release
echo     help, -h, --help        Show this help message
echo.
echo Use 'call claude-profile use ^<name^>' to set CLAUDE_CONFIG_DIR in the
echo current cmd session, then run 'claude' separately.
echo.
echo A directory containing a .claude-profile file (holding a profile name)
echo is preferred over the default profile by a bare 'call claude-profile'.
echo cmd.exe has no cd hook, so this resolves at invocation time rather than
echo automatically on cd as it does in the sh and PowerShell versions.
echo.
echo Examples:
echo     claude-profile create work
echo     claude-profile default work
echo     call claude-profile use work     # activates "work" profile
echo     claude                           # runs with "work" profile
echo     claude-profile local work        # write .claude-profile here
echo     call claude-profile              # activates "work" from .claude-profile
exit /b 0

:: --- Validate name ---
:: Expects profile name in %_vn_name%
:: Returns errorlevel 1 on failure

:validate_name

:: Check empty
if "%_vn_name%"=="" (
    echo claude-profile: profile name must not be empty >&2
    exit /b 1
)

:: Check starts with dot
if "!_vn_name:~0,1!"=="." (
    echo claude-profile: invalid profile name '%_vn_name%': must not contain '/' or start with '.' >&2
    exit /b 1
)

:: Check for path traversal and slashes (/  \  ..)
:: We use findstr with regex mode for reliable matching
echo !_vn_name! | findstr /R "[/\\]" >nul 2>&1 && (
    echo claude-profile: invalid profile name '%_vn_name%': must not contain '/' or start with '.' >&2
    exit /b 1
)
echo !_vn_name! | findstr /C:".." >nul 2>&1 && (
    echo claude-profile: invalid profile name '%_vn_name%': must not contain '/' or start with '.' >&2
    exit /b 1
)

:: Check only valid characters (letters, digits, hyphens, underscores)
echo !_vn_name!| findstr /R "^[a-zA-Z0-9_-][a-zA-Z0-9_-]*$" >nul 2>&1 || (
    echo claude-profile: invalid profile name '%_vn_name%': use only letters, digits, hyphens, underscores >&2
    exit /b 1
)

goto :eof

:: --- Directory-local profile (.claude-profile) ---
::
:: A directory may contain a `.claude-profile` file whose first non-empty,
:: non-comment line names a profile. cmd.exe has no cd hook and no way to
:: install a transparent `claude` wrapper, so unlike the sh and PowerShell
:: implementations this cannot switch on cd. Instead, a bare
:: `call claude-profile.cmd` resolves the nearest .claude-profile walking up
:: from the current directory and prefers it over the default profile.

:: Sets _fd_result to the nearest .claude-profile at or above %CD%, or leaves
:: it empty when none is found.
:find_dotfile
set "_fd_result="
set "_fd_dir=%CD%"
:find_dotfile_loop
if exist "!_fd_dir!\.claude-profile" (
    set "_fd_result=!_fd_dir!\.claude-profile"
    goto :eof
)
set "_fd_parent="
for %%p in ("!_fd_dir!\..") do set "_fd_parent=%%~fp"
if not defined _fd_parent goto :eof
if /i "!_fd_parent!"=="!_fd_dir!" goto :eof
set "_fd_dir=!_fd_parent!"
goto :find_dotfile_loop

:: Captures a literal CR into _CP_CR. `for /f` leaves the CR attached to each
:: token when reading a CRLF file, which would otherwise make an otherwise
:: valid profile name fail validation. Resolved lazily (only :read_dotfile
:: needs it) so the common command paths don't pay for the copy.
:capture_cr
if defined _CP_CR goto :eof
for /f %%a in ('copy /Z "%~f0" nul') do set "_CP_CR=%%a"
goto :eof

:: read_dotfile <path> -> sets _rd_name to the first non-empty, non-comment
:: line, with surrounding whitespace and any trailing CR stripped.
:read_dotfile
call :capture_cr
set "_rd_name="
for /f "usebackq eol=# tokens=* delims=	 " %%L in ("%~1") do (
    if not defined _rd_name set "_rd_name=%%L"
)
if not defined _rd_name goto :eof
:read_dotfile_trim
if not defined _rd_name goto :eof
if "!_rd_name:~-1!"==" "       (set "_rd_name=!_rd_name:~0,-1!" & goto :read_dotfile_trim)
if "!_rd_name:~-1!"=="	"      (set "_rd_name=!_rd_name:~0,-1!" & goto :read_dotfile_trim)
if "!_rd_name:~-1!"=="!_CP_CR!" (set "_rd_name=!_rd_name:~0,-1!" & goto :read_dotfile_trim)
goto :eof

:: Resolves the directory-local profile into _dl_name / _dl_file, or leaves
:: _dl_name empty. Reports (to stderr) a dotfile that names something
:: unusable, so a typo isn't silently ignored.
:resolve_dotfile_profile
set "_dl_name="
set "_dl_file="
call :find_dotfile
if not defined _fd_result goto :eof
set "_dl_file=!_fd_result!"
call :read_dotfile "!_dl_file!"
if not defined _rd_name (
    echo claude-profile: ignoring !_dl_file!: no profile name in file >&2
    goto :eof
)
set "_vn_name=!_rd_name!"
call :validate_name >nul 2>&1
if errorlevel 1 (
    echo claude-profile: ignoring !_dl_file!: invalid profile name '!_rd_name!' >&2
    goto :eof
)
if not exist "%DATA_DIR%\!_rd_name!\" (
    echo claude-profile: ignoring !_dl_file!: profile '!_rd_name!' does not exist >&2
    goto :eof
)
set "_dl_name=!_rd_name!"
goto :eof

:: --- Commands ---

:cmd_local
if "%~1"=="" goto :cmd_local_show
if /i "%~1"=="--remove" goto :cmd_local_remove
if /i "%~1"=="--clear"  goto :cmd_local_remove
set "_first=%~1"
if "!_first:~0,1!"=="-" (
    echo claude-profile: unknown option '%~1' >&2
    exit /b 1
)
if not "%~2"=="" (
    echo claude-profile: unexpected argument after profile name: '%~2' >&2
    exit /b 1
)
set "_vn_name=%~1"
call :validate_name
if errorlevel 1 exit /b 1
if not exist "%DATA_DIR%\%~1\" (
    echo claude-profile: profile '%~1' does not exist. Create it with: claude-profile create %~1 >&2
    exit /b 1
)
>"%CD%\.claude-profile" echo %~1
if not exist "%CD%\.claude-profile" (
    echo claude-profile: could not write %CD%\.claude-profile >&2
    exit /b 1
)
echo Wrote %CD%\.claude-profile ^(profile: %~1^)
echo Run 'call claude-profile.cmd' here to activate it.
exit /b 0

:cmd_local_show
call :resolve_dotfile_profile
if not defined _dl_file (
    echo claude-profile: no .claude-profile found in this directory or any parent >&2
    exit /b 1
)
echo !_dl_file!
if defined _dl_name (
    echo Profile: !_dl_name!
) else (
    exit /b 1
)
exit /b 0

:cmd_local_remove
if not exist "%CD%\.claude-profile" (
    echo claude-profile: no .claude-profile in the current directory >&2
    exit /b 1
)
del /f /q "%CD%\.claude-profile" >nul 2>&1
if exist "%CD%\.claude-profile" (
    echo claude-profile: could not remove %CD%\.claude-profile >&2
    exit /b 1
)
echo Removed %CD%\.claude-profile
exit /b 0

:cmd_create
if "%~1"=="" (
    echo claude-profile: usage: claude-profile create ^<name^> >&2
    exit /b 1
)
set "_vn_name=%~1"
call :validate_name
if errorlevel 1 exit /b 1

set "_cc_dir=%DATA_DIR%\%~1"
if exist "%_cc_dir%\" (
    echo claude-profile: profile '%~1' already exists >&2
    exit /b 1
)
mkdir "%_cc_dir%"
echo Created profile: %~1
echo Config directory: %_cc_dir%
exit /b 0

:cmd_list
if not exist "%DATA_DIR%\" (
    echo No profiles found. Create one with: claude-profile create ^<name^>
    exit /b 0
)

set "_cl_default="
if exist "%DEFAULT_FILE%" (
    set /p _cl_default=<"%DEFAULT_FILE%"
)

set "_cl_found=0"
for /d %%d in ("%DATA_DIR%\*") do (
    set "_cl_found=1"
    set "_cl_name=%%~nxd"
    if "!_cl_name!"=="!_cl_default!" (
        echo * !_cl_name! (default^)
    ) else (
        echo   !_cl_name!
    )
)

if "!_cl_found!"=="0" (
    echo No profiles found. Create one with: claude-profile create ^<name^>
)
exit /b 0

:cmd_default
if "%~1"=="" (
    if exist "%DEFAULT_FILE%" (
        type "%DEFAULT_FILE%"
        echo.
        exit /b 0
    ) else (
        echo claude-profile: no default profile set. Set one with: claude-profile default ^<name^> >&2
        exit /b 1
    )
)

set "_vn_name=%~1"
call :validate_name
if errorlevel 1 exit /b 1

set "_cd_dir=%DATA_DIR%\%~1"
if not exist "%_cd_dir%\" (
    echo claude-profile: profile '%~1' does not exist. Create it with: claude-profile create %~1 >&2
    exit /b 1
)
if not exist "%DATA_DIR%\" mkdir "%DATA_DIR%"
:: Write profile name without trailing newline (cmd echo always adds one, but set /p reads the first line)
>"%DEFAULT_FILE%" (echo|set /p="%~1")
echo Default profile set to: %~1
exit /b 0

:cmd_version
set "_cv_installed=unknown"
if exist "%_CP_VERSION_FILE%" set /p _cv_installed=<"%_CP_VERSION_FILE%"
if "!_cv_installed!"=="" set "_cv_installed=unknown"
echo !_cv_installed!
exit /b 0

:verify_checksum
:: verify_checksum <file> <sums-file> -> errorlevel 0 on match, 1 otherwise
set "_vc_file=%~1"
set "_vc_sums=%~2"
for %%F in ("!_vc_file!") do set "_vc_name=%%~nxF"
set "_vc_actual="
for /f "skip=1 tokens=* delims=" %%h in ('certutil -hashfile "!_vc_file!" SHA256 2^>nul') do (
    if not defined _vc_actual (
        echo %%h | findstr /R "^[0-9A-Fa-f][0-9A-Fa-f]*$" >nul 2>&1
        if not errorlevel 1 set "_vc_actual=%%h"
    )
)
set "_vc_expected="
for /f "usebackq delims=" %%L in ("!_vc_sums!") do (
    echo %%L | findstr /C:"!_vc_name!" >nul 2>&1
    if not errorlevel 1 (
        for /f "tokens=1" %%h in ("%%L") do set "_vc_expected=%%h"
    )
)
if not defined _vc_expected exit /b 1
if not defined _vc_actual exit /b 1
if /i "!_vc_expected!"=="!_vc_actual!" (exit /b 0) else (exit /b 1)

:cmd_update
set "_cu_force=0"
if /i "%~1"=="--force" set "_cu_force=1"

where curl >nul 2>&1
if errorlevel 1 (
    echo claude-profile: update requires curl >&2
    exit /b 1
)

set "_cu_resp=%TEMP%\cp-update-release-%RANDOM%.json"
curl -fsSL --connect-timeout 10 --max-time 30 -o "!_cu_resp!" "%_CP_REPO_API%/releases/latest" >nul 2>&1
if not exist "!_cu_resp!" (
    echo claude-profile: update failed: could not reach GitHub >&2
    exit /b 1
)
set "_cu_tagline="
for /f "usebackq delims=" %%T in (`findstr /R "\"tag_name\"" "!_cu_resp!"`) do set "_cu_tagline=%%T"
del /f /q "!_cu_resp!" >nul 2>&1
if not defined _cu_tagline (
    echo claude-profile: update failed: could not determine latest version >&2
    exit /b 1
)
call :extract_tag_version "!_cu_tagline!"
if not defined _cp_tag_version (
    echo claude-profile: update failed: could not determine latest version >&2
    exit /b 1
)
set "_cu_latest=!_cp_tag_version!"
set "_cu_tag=v!_cu_latest!"

set "_cu_installed=unknown"
if exist "%_CP_VERSION_FILE%" set /p _cu_installed=<"%_CP_VERSION_FILE%"
if "!_cu_installed!"=="" set "_cu_installed=unknown"
:: Proactive fix (learned from Task 7's cp_update_check fix, commit 0d89002):
:: validate the locally-installed VERSION file's content is a real X.Y.Z
:: triplet before feeding it into version_lt, since a truncated/hand-edited
:: file would otherwise silently mis-compare (version_lt's undefined-segment
:: bug, also fixed in Task 7) instead of honestly falling back to "unknown".
if not "!_cu_installed!"=="unknown" (
    echo !_cu_installed!| findstr /R "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
    if errorlevel 1 set "_cu_installed=unknown"
)

if "!_cu_force!"=="0" if not "!_cu_installed!"=="unknown" (
    call :version_lt "!_cu_installed!" "!_cu_latest!"
    if errorlevel 1 (
        echo claude-profile: already up to date ^(v!_cu_installed!^); latest is v!_cu_latest! >&2
        exit /b 1
    )
)

:: Proactive fix (learned from Task 8/9's same-filesystem-tmpdir fix):
:: create the install directory FIRST, then create the temp directory
:: INSIDE it (not under %TEMP%), so the later `move` calls are guaranteed
:: same-volume, atomic renames rather than a possible cross-volume
:: copy+delete.
if not exist "%_CP_INSTALL_DIR%" mkdir "%_CP_INSTALL_DIR%" >nul 2>&1
set "_cu_tmpdir=%_CP_INSTALL_DIR%\.update-%RANDOM%"
mkdir "!_cu_tmpdir!" >nul 2>&1
if not exist "!_cu_tmpdir!\" (
    echo claude-profile: update failed: could not create temp directory >&2
    exit /b 1
)

set "_cu_asset_base=%_CP_ASSET_BASE%/!_cu_tag!"
curl -fsSL --connect-timeout 10 --max-time 30 -o "!_cu_tmpdir!\SHA256SUMS" "!_cu_asset_base!/SHA256SUMS" >nul 2>&1
curl -fsSL --connect-timeout 10 --max-time 30 -o "!_cu_tmpdir!\VERSION" "!_cu_asset_base!/VERSION" >nul 2>&1
curl -fsSL --connect-timeout 10 --max-time 60 -o "!_cu_tmpdir!\claude-profile.cmd" "!_cu_asset_base!/claude-profile.cmd" >nul 2>&1

if not exist "!_cu_tmpdir!\SHA256SUMS" (
    echo claude-profile: update failed: could not download checksums >&2
    goto :update_fail_cleanup
)
if not exist "!_cu_tmpdir!\VERSION" (
    echo claude-profile: update failed: could not download VERSION >&2
    goto :update_fail_cleanup
)
if not exist "!_cu_tmpdir!\claude-profile.cmd" (
    echo claude-profile: update failed: could not download claude-profile.cmd >&2
    goto :update_fail_cleanup
)

call :verify_checksum "!_cu_tmpdir!\VERSION" "!_cu_tmpdir!\SHA256SUMS"
if errorlevel 1 (
    echo claude-profile: update failed: VERSION checksum mismatch >&2
    goto :update_fail_cleanup
)
call :verify_checksum "!_cu_tmpdir!\claude-profile.cmd" "!_cu_tmpdir!\SHA256SUMS"
if errorlevel 1 (
    echo claude-profile: update failed: claude-profile.cmd checksum mismatch >&2
    goto :update_fail_cleanup
)

set "_cu_downloaded_version="
set /p _cu_downloaded_version=<"!_cu_tmpdir!\VERSION"
if not "!_cu_downloaded_version!"=="!_cu_latest!" (
    echo claude-profile: update failed: downloaded VERSION ^(!_cu_downloaded_version!^) does not match release tag ^(!_cu_latest!^) >&2
    goto :update_fail_cleanup
)

:: Proactive fix (learned from Task 8's unchecked-second-mv fix, commit
:: 8cf1fca): both moves are now checked; a failure on either one cleans
:: up and reports an error rather than silently reporting success.
move /y "!_cu_tmpdir!\claude-profile.cmd" "%_CP_INSTALL_DIR%\claude-profile.cmd" >nul 2>&1
if errorlevel 1 (
    echo claude-profile: update failed: could not replace claude-profile.cmd >&2
    goto :update_fail_cleanup
)
move /y "!_cu_tmpdir!\VERSION" "%_CP_VERSION_FILE%" >nul 2>&1
if errorlevel 1 (
    echo claude-profile: update failed: could not replace VERSION >&2
    goto :update_fail_cleanup
)
rd /s /q "!_cu_tmpdir!" >nul 2>&1

set "_cu_installed_display=v!_cu_installed!"
if "!_cu_installed!"=="unknown" set "_cu_installed_display=unknown"
echo Updating claude-profile.cmd: !_cu_installed_display! -^> v!_cu_latest!
echo Done. Open a new cmd window ^(or re-run 'call claude-profile.cmd'^) to use the new version.
exit /b 0

:update_fail_cleanup
if exist "!_cu_tmpdir!" rd /s /q "!_cu_tmpdir!" >nul 2>&1
exit /b 1

:cmd_which
:: Resolve profile dir for optional name argument
set "_rp_name=%~1"
if "!_rp_name!"=="" (
    if not exist "%DEFAULT_FILE%" (
        echo claude-profile: no default profile set. Use: claude-profile default ^<name^> >&2
        exit /b 1
    )
    set /p _rp_name=<"%DEFAULT_FILE%"
    if "!_rp_name!"=="" (
        echo claude-profile: default profile file is empty. Set one with: claude-profile default ^<name^> >&2
        exit /b 1
    )
)
set "_rp_dir=%DATA_DIR%\!_rp_name!"
if not exist "!_rp_dir!\" (
    echo claude-profile: profile '!_rp_name!' does not exist. Create it with: claude-profile create !_rp_name! >&2
    exit /b 1
)
echo !_rp_dir!
exit /b 0

:cmd_use
if "%~1"=="" (
    echo claude-profile: usage: claude-profile use ^<name^> >&2
    exit /b 1
)
if not "%~2"=="" (
    echo claude-profile: 'use' takes exactly one argument (profile name) >&2
    exit /b 1
)

:: Resolve profile dir
set "_rp_name=%~1"
set "_rp_dir=%DATA_DIR%\!_rp_name!"
if not exist "!_rp_dir!\" (
    echo claude-profile: profile '!_rp_name!' does not exist. Create it with: claude-profile create !_rp_name! >&2
    exit /b 1
)

:: Set CLAUDE_CONFIG_DIR for the calling session (requires 'call' prefix)
endlocal & set "CLAUDE_CONFIG_DIR=%_rp_dir%" & echo Switched to profile: %_rp_name%
exit /b 0

:cmd_delete
if "%~1"=="" (
    echo claude-profile: usage: claude-profile delete ^<name^> >&2
    exit /b 1
)
set "_cdel_name=%~1"
set "_vn_name=!_cdel_name!"
call :validate_name
if errorlevel 1 exit /b 1

set "_cdel_dir=%DATA_DIR%\!_cdel_name!"
if not exist "!_cdel_dir!\" (
    echo claude-profile: profile '!_cdel_name!' does not exist >&2
    exit /b 1
)

set "_cdel_prompt=Delete profile "!_cdel_name!" and all its data? [y/N] "
set /p _cdel_confirm=!_cdel_prompt!
if /i "!_cdel_confirm!"=="y" goto :do_delete
if /i "!_cdel_confirm!"=="yes" goto :do_delete
echo Cancelled.
exit /b 0

:do_delete
rmdir /s /q "!_cdel_dir!"
echo Deleted profile: !_cdel_name!

if exist "%DEFAULT_FILE%" (
    set /p _cdel_current=<"%DEFAULT_FILE%"
    if "!_cdel_current!"=="!_cdel_name!" (
        del /f "%DEFAULT_FILE%" >nul 2>&1
        echo Cleared default profile (was "!_cdel_name!"^)
    )
)
exit /b 0

:cmd_launch_default
:: A .claude-profile in this directory (or any parent) wins over the default.
call :resolve_dotfile_profile
if defined _dl_name goto :launch_dotfile

:: Resolve default profile
if not exist "%DEFAULT_FILE%" (
    echo claude-profile: no default profile set. Use: claude-profile default ^<name^> >&2
    exit /b 1
)
set /p _rp_name=<"%DEFAULT_FILE%"
if "!_rp_name!"=="" (
    echo claude-profile: default profile file is empty. Set one with: claude-profile default ^<name^> >&2
    exit /b 1
)
set "_rp_dir=%DATA_DIR%\!_rp_name!"
if not exist "!_rp_dir!\" (
    echo claude-profile: profile '!_rp_name!' does not exist. Create it with: claude-profile create !_rp_name! >&2
    exit /b 1
)

:: Set CLAUDE_CONFIG_DIR for the calling session (requires 'call' prefix)
endlocal & set "CLAUDE_CONFIG_DIR=%_rp_dir%" & echo Switched to profile: %_rp_name% (default)
exit /b 0

:launch_dotfile
:: Kept out of the `if defined` block above: `endlocal & set VAR=%...%`
:: relies on percent-expansion happening after the preceding set lines have
:: run, which a parenthesised block would break.
set "_rp_name=%_dl_name%"
set "_rp_dir=%DATA_DIR%\%_dl_name%"
set "_rp_src=%_dl_file%"
endlocal & set "CLAUDE_CONFIG_DIR=%_rp_dir%" & echo Switched to profile: %_rp_name% (from %_rp_src%)
exit /b 0
