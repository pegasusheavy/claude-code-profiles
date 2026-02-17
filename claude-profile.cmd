@echo off
setlocal enabledelayedexpansion

:: --- Platform-aware data directory ---
:: Uses %LOCALAPPDATA%\claude-profiles on Windows
set "DATA_DIR=%LOCALAPPDATA%\claude-profiles"
set "DEFAULT_FILE=%DATA_DIR%\.default"

:: --- Dispatcher ---
:: No arguments: launch with default profile
if "%~1"=="" goto :cmd_launch_default

:: Command dispatch
if "%~1"=="create"  goto :dispatch_create
if "%~1"=="list"    goto :dispatch_list
if "%~1"=="ls"      goto :dispatch_list
if "%~1"=="default" goto :dispatch_default
if "%~1"=="which"   goto :dispatch_which
if "%~1"=="use"     goto :dispatch_use
if "%~1"=="delete"  goto :dispatch_delete
if "%~1"=="help"    goto :usage
if "%~1"=="-h"      goto :usage
if "%~1"=="--help"  goto :usage

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

:: --- Usage ---

:usage
echo Usage: claude-profile [command] [args...]
echo.
echo Commands:
echo     (no command)            Activate the default profile
echo     use ^<name^>              Activate the named profile
echo     create ^<name^>           Create a new profile
echo     list, ls                List all profiles
echo     default [name]          Get or set the default profile
echo     delete ^<name^>           Delete a profile
echo     which [name]            Show the resolved config directory path
echo     help, -h, --help        Show this help message
echo.
echo Use 'call claude-profile use ^<name^>' to set CLAUDE_CONFIG_DIR in the
echo current cmd session, then run 'claude' separately.
echo.
echo Examples:
echo     claude-profile create work
echo     claude-profile default work
echo     call claude-profile use work     # activates "work" profile
echo     claude                           # runs with "work" profile
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
:: Strip all valid characters; if anything remains, the name is invalid
set "_vn_check=!_vn_name!"
for %%c in (a b c d e f g h i j k l m n o p q r s t u v w x y z A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 0 1 2 3 4 5 6 7 8 9 - _) do (
    set "_vn_check=!_vn_check:%%c=!"
)
if not "!_vn_check!"=="" (
    echo claude-profile: invalid profile name '%_vn_name%': use only letters, digits, hyphens, underscores >&2
    exit /b 1
)

goto :eof

:: --- Commands ---

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
