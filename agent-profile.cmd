@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: agent-profile.cmd — provider-neutral profiles for Windows cmd.exe.
:: Use `call agent-profile.cmd ...` when a command changes the caller env.

if defined AGENT_PROFILE_DATA_DIR (
    set "AP_DATA=%AGENT_PROFILE_DATA_DIR%"
) else (
    set "AP_DATA=%LOCALAPPDATA%\agent-profiles"
)

if /i "%~1"=="help" goto :help
if /i "%~1"=="-h" goto :help
if /i "%~1"=="--help" goto :help
if /i "%~1"=="internal-path" goto :internal_path

set "AP_COMMAND=%~1"
set "AP_PROVIDER=%~2"
if /i "%AP_COMMAND%"=="create" goto :dispatch
if /i "%AP_COMMAND%"=="copy" goto :dispatch
if /i "%AP_COMMAND%"=="list" goto :dispatch
if /i "%AP_COMMAND%"=="ls" goto :dispatch
if /i "%AP_COMMAND%"=="default" goto :dispatch
if /i "%AP_COMMAND%"=="use" goto :dispatch
if /i "%AP_COMMAND%"=="which" goto :dispatch
if /i "%AP_COMMAND%"=="restart" goto :dispatch
if /i "%AP_COMMAND%"=="delete" goto :dispatch
if /i "%AP_COMMAND%"=="status" goto :dispatch

:: Provider-first form: agent-profile.cmd antigravity copy hafez
set "AP_PROVIDER=%~1"
set "AP_COMMAND=%~2"
if not defined AP_COMMAND set "AP_COMMAND=status"
goto :dispatch

:dispatch
call :normalize_provider "%AP_PROVIDER%"
if errorlevel 1 exit /b 1
if /i "%AP_COMMAND%"=="create" goto :create
if /i "%AP_COMMAND%"=="copy" goto :copy
if /i "%AP_COMMAND%"=="list" goto :list
if /i "%AP_COMMAND%"=="ls" goto :list
if /i "%AP_COMMAND%"=="default" goto :default
if /i "%AP_COMMAND%"=="use" goto :use
if /i "%AP_COMMAND%"=="which" goto :which
if /i "%AP_COMMAND%"=="restart" goto :restart
if /i "%AP_COMMAND%"=="delete" goto :delete
if /i "%AP_COMMAND%"=="status" goto :status
echo agent-profile: unknown command '%AP_COMMAND%'. Run 'agent-profile.cmd help' for usage. >&2
exit /b 1

:normalize_provider
if /i "%~1"=="agy" (set "AP_PROVIDER=antigravity" & goto :eof)
if /i "%~1"=="antigravity" (set "AP_PROVIDER=antigravity" & goto :eof)
if /i "%~1"=="antigravity-cli" (set "AP_PROVIDER=antigravity" & goto :eof)
if /i "%~1"=="antigravity-gui" (set "AP_PROVIDER=antigravity" & goto :eof)
if /i "%~1"=="antigravity-ide" (set "AP_PROVIDER=antigravity" & goto :eof)
if /i "%~1"=="codex" (set "AP_PROVIDER=codex" & goto :eof)
echo agent-profile: unknown provider '%~1' (use antigravity or codex) >&2
exit /b 1

:validate_name
set "AP_NAME=%~1"
if not defined AP_NAME (
    echo agent-profile: profile name must not be empty >&2
    exit /b 1
)
if "!AP_NAME:~0,1!"=="." (
    echo agent-profile: invalid profile name '%AP_NAME%' >&2
    exit /b 1
)
echo !AP_NAME! | findstr /R "[/\\]" >nul 2>&1 && (
    echo agent-profile: invalid profile name '%AP_NAME%' >&2
    exit /b 1
)
echo !AP_NAME! | findstr /C:".." >nul 2>&1 && (
    echo agent-profile: invalid profile name '%AP_NAME%' >&2
    exit /b 1
)
echo !AP_NAME! | findstr /R "^[a-zA-Z0-9_-][a-zA-Z0-9_-]*$" >nul 2>&1 || (
    echo agent-profile: invalid profile name '%AP_NAME%' >&2
    exit /b 1
)
exit /b 0

:provider_root
set "AP_ROOT=%AP_DATA%\%AP_PROVIDER%"
exit /b 0

:profile_path
call :provider_root
set "AP_PROFILE=%AP_ROOT%\%~1"
exit /b 0

:default_name
call :provider_root
if not exist "%AP_ROOT%\.default" exit /b 1
set /p AP_NAME=<"%AP_ROOT%\.default"
if not defined AP_NAME exit /b 1
exit /b 0

:selected_path
call :provider_root
set "AP_SELECTED_NAME="
set "AP_NAME="
if /i "%AP_PROVIDER%"=="antigravity" set "AP_SELECTED_NAME=%AGENT_PROFILE_ANTIGRAVITY_ACTIVE%"
if /i "%AP_PROVIDER%"=="codex" set "AP_SELECTED_NAME=%AGENT_PROFILE_CODEX_ACTIVE%"
if not defined AP_SELECTED_NAME call :default_name
if not defined AP_SELECTED_NAME exit /b 1
call :validate_name "%AP_SELECTED_NAME%"
if errorlevel 1 exit /b 1
call :profile_path "%AP_SELECTED_NAME%"
if not exist "%AP_PROFILE%\" exit /b 1
set "AP_SELECTED=%AP_PROFILE%"
exit /b 0

:internal_path
set "AP_PROVIDER=%~2"
call :normalize_provider "%AP_PROVIDER%"
if errorlevel 1 exit /b 1
if not "%~3"=="" (
    call :validate_name "%~3"
    if errorlevel 1 exit /b 1
    call :profile_path "%~3"
    if not exist "%AP_PROFILE%\" exit /b 1
    echo %AP_PROFILE%
    exit /b 0
)
call :selected_path
if errorlevel 1 exit /b 1
echo %AP_SELECTED%
exit /b 0

:help
echo Usage: call agent-profile.cmd ^<provider^> ^<command^> [args...]
echo        call agent-profile.cmd ^<command^> ^<provider^> [args...]
echo.
echo Providers:
echo   antigravity  Antigravity CLI ^(agy^) and GUI
echo   codex        OpenAI Codex CLI
echo.
echo Commands:
echo   create ^<provider^> ^<name^>                 Create an empty profile
echo   copy ^<provider^> ^<name^> [--force]         Copy current live data
echo   copy ^<provider^> ^<source^> ^<name^> [--force] Copy a managed profile
echo   list ^<provider^>                            List profiles
echo   default ^<provider^> [name]                  Get or set the default
echo   use ^<provider^> ^<name^>                    Select a profile for this cmd session
echo   which ^<provider^> [name]                    Print a profile directory
echo   restart ^<provider^> [args...]               Open a fresh Antigravity GUI window
echo   delete ^<provider^> ^<name^> [--force]       Delete a profile
echo.
echo Examples:
echo   call agent-profile.cmd copy antigravity hafez
echo   call agent-profile.cmd copy antigravity default hafez
echo   call agent-profile.cmd default antigravity hafez
exit /b 0

:create
if "%~3"=="" (
    echo agent-profile: usage: agent-profile create %AP_PROVIDER% ^<name^> >&2
    exit /b 1
)
if not "%~4"=="" (
    echo agent-profile: unexpected argument '%~4' >&2
    exit /b 1
)
call :validate_name "%~3"
if errorlevel 1 exit /b 1
call :profile_path "%~3"
if exist "%AP_PROFILE%\" (
    echo agent-profile: profile '%~3' already exists >&2
    exit /b 1
)
mkdir "%AP_PROFILE%" >nul 2>&1
if errorlevel 1 (
    echo agent-profile: could not create profile '%~3' >&2
    exit /b 1
)
echo Created %AP_PROVIDER% profile: %~3
echo Profile directory: %AP_PROFILE%
exit /b 0

:copy
set "AP_FORCE=0"
set "AP_COPY_SOURCE="
set "AP_COPY_NAME="
if /i "%~3"=="--force" goto :copy_usage
if /i "%~4"=="--force" set "AP_FORCE=1"
if /i "%~5"=="--force" set "AP_FORCE=1"
if not "%~5"=="" if not "%~5"=="--force" goto :copy_usage
if not "%~6"=="" goto :copy_usage
if not "%~4"=="" if /i not "%~4"=="--force" (
    set "AP_COPY_SOURCE=%~3"
    set "AP_COPY_NAME=%~4"
) else (
    set "AP_COPY_SOURCE=live"
    set "AP_COPY_NAME=%~3"
)
if not defined AP_COPY_NAME goto :copy_usage
call :validate_name "%AP_COPY_NAME%"
if errorlevel 1 exit /b 1
if /i "%AP_COPY_SOURCE%"=="default" (
    call :default_name
    if errorlevel 1 (
        echo agent-profile: no default profile set for %AP_PROVIDER% >&2
        exit /b 1
    )
    set "AP_COPY_SOURCE=%AP_NAME%"
)
call :profile_path "%AP_COPY_NAME%"
if exist "%AP_PROFILE%\" if "%AP_FORCE%"=="0" (
    echo agent-profile: profile '%AP_COPY_NAME%' already exists ^(use --force to replace it^) >&2
    exit /b 1
)
set "AP_DEST=%AP_PROFILE%"
call :provider_root
mkdir "%AP_ROOT%" >nul 2>&1
set "AP_TMP=%AP_DEST%.tmp.%RANDOM%"
if exist "%AP_TMP%\" rmdir /s /q "%AP_TMP%" >nul 2>&1
mkdir "%AP_TMP%" >nul 2>&1
if errorlevel 1 (
    echo agent-profile: could not create temporary profile directory >&2
    exit /b 1
)
if /i "%AP_COPY_SOURCE%"=="live" goto :copy_live
call :validate_name "%AP_COPY_SOURCE%"
if errorlevel 1 goto :copy_failed
call :profile_path "%AP_COPY_SOURCE%"
if not exist "%AP_PROFILE%\" (
    echo agent-profile: source profile '%AP_COPY_SOURCE%' does not exist >&2
    goto :copy_failed
)
xcopy "%AP_PROFILE%\*" "%AP_TMP%\" /E /I /H /Y >nul
if errorlevel 1 goto :copy_failed
goto :copy_finalize

:copy_live
if /i "%AP_PROVIDER%"=="antigravity" (
    if exist "%USERPROFILE%\.gemini\" xcopy "%USERPROFILE%\.gemini\*" "%AP_TMP%\home\.gemini\" /E /I /H /Y >nul
    if defined AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR (
        if exist "%AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR%\" xcopy "%AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR%\*" "%AP_TMP%\gui-user-data\" /E /I /H /Y >nul
    ) else if exist "%APPDATA%\Antigravity IDE\" (
        xcopy "%APPDATA%\Antigravity IDE\*" "%AP_TMP%\gui-user-data\" /E /I /H /Y >nul
    ) else if exist "%APPDATA%\Antigravity\" (
        xcopy "%APPDATA%\Antigravity\*" "%AP_TMP%\gui-user-data\" /E /I /H /Y >nul
    ) else if exist "%USERPROFILE%\.gemini\antigravity-ide\" (
        xcopy "%USERPROFILE%\.gemini\antigravity-ide\*" "%AP_TMP%\gui-user-data\" /E /I /H /Y >nul
    ) else if exist "%USERPROFILE%\.antigravity-ide\" (
        xcopy "%USERPROFILE%\.antigravity-ide\*" "%AP_TMP%\gui-user-data\" /E /I /H /Y >nul
    )
)
if /i "%AP_PROVIDER%"=="codex" (
    if defined CODEX_HOME (set "AP_CODEX_SOURCE=%CODEX_HOME%") else (set "AP_CODEX_SOURCE=%USERPROFILE%\.codex")
    if exist "%AP_CODEX_SOURCE%\" xcopy "%AP_CODEX_SOURCE%\*" "%AP_TMP%\" /E /I /H /Y >nul
)
goto :copy_finalize

:copy_finalize
call :prune_gui_locks "%AP_TMP%\gui-user-data"
if exist "%AP_DEST%\" rmdir /s /q "%AP_DEST%" >nul 2>&1
move /Y "%AP_TMP%" "%AP_DEST%" >nul 2>&1
if errorlevel 1 goto :copy_failed
echo Copied %AP_PROVIDER% profile to: %AP_COPY_NAME%
if /i "%AP_PROVIDER%"=="antigravity" if /i "%AP_COPY_SOURCE%"=="live" echo agent-profile: note: OS keyring credentials are not copied; keyring-backed login may remain shared. >&2
echo Profile directory: %AP_DEST%
exit /b 0

:copy_failed
if exist "%AP_TMP%\" rmdir /s /q "%AP_TMP%" >nul 2>&1
echo agent-profile: could not copy profile data >&2
exit /b 1

:copy_usage
echo agent-profile: usage: agent-profile copy %AP_PROVIDER% [source] ^<name^> [--force] >&2
exit /b 1

:: Chromium's singleton files name the host and pid that owned the source
:: instance (SingletonLock points at "host-pid") plus a socket under that
:: instance's temp dir. Copied into a new profile they can make Antigravity
:: decide another instance already owns this user-data-dir and simply focus
:: that window, which looks exactly like the profile failing to switch. They
:: are pure runtime state, so drop them from every snapshot.
:prune_gui_locks
if not exist "%~1\" exit /b 0
del /f /q "%~1\SingletonLock" >nul 2>&1
del /f /q "%~1\SingletonCookie" >nul 2>&1
del /f /q "%~1\SingletonSocket" >nul 2>&1
exit /b 0

:list
if not "%~3"=="" (
    echo agent-profile: usage: agent-profile list %AP_PROVIDER% >&2
    exit /b 1
)
call :provider_root
if not exist "%AP_ROOT%\" (
    echo No %AP_PROVIDER% profiles found. Create one with: agent-profile.cmd create %AP_PROVIDER% ^<name^>
    exit /b 0
)
set "AP_DEFAULT="
if exist "%AP_ROOT%\.default" set /p AP_DEFAULT=<"%AP_ROOT%\.default"
set "AP_FOUND=0"
for /d %%D in ("%AP_ROOT%\*") do (
    set "AP_FOUND=1"
    set "AP_ENTRY=%%~nxD"
    set "AP_STATUS="
    if /i "!AP_ENTRY!"=="!AP_DEFAULT!" set "AP_STATUS= (default)"
    if /i "!AP_ENTRY!"=="%AGENT_PROFILE_ANTIGRAVITY_ACTIVE%" if /i "!AP_PROVIDER!"=="antigravity" set "AP_STATUS= (active)"
    if /i "!AP_ENTRY!"=="%AGENT_PROFILE_CODEX_ACTIVE%" if /i "!AP_PROVIDER!"=="codex" set "AP_STATUS= (active)"
    echo    !AP_ENTRY!!AP_STATUS!
)
if "%AP_FOUND%"=="0" echo No %AP_PROVIDER% profiles found. Create one with: agent-profile.cmd create %AP_PROVIDER% ^<name^>
exit /b 0

:default
if "%~3"=="" (
    call :default_name
    if errorlevel 1 (
        echo agent-profile: no default profile set for %AP_PROVIDER% >&2
        exit /b 1
    )
    echo %AP_NAME%
    exit /b 0
)
if not "%~4"=="" (
    echo agent-profile: usage: agent-profile default %AP_PROVIDER% [name] >&2
    exit /b 1
)
call :validate_name "%~3"
if errorlevel 1 exit /b 1
call :profile_path "%~3"
if not exist "%AP_PROFILE%\" (
    echo agent-profile: profile '%~3' does not exist >&2
    exit /b 1
)
call :provider_root
mkdir "%AP_ROOT%" >nul 2>&1
>"%AP_ROOT%\.default" <nul set /p "=%~3"
echo Default %AP_PROVIDER% profile set to: %~3
exit /b 0

:use
if "%~3"=="" (
    echo agent-profile: usage: agent-profile use %AP_PROVIDER% ^<name^> >&2
    exit /b 1
)
if not "%~4"=="" (
    echo agent-profile: usage: agent-profile use %AP_PROVIDER% ^<name^> >&2
    exit /b 1
)
call :validate_name "%~3"
if errorlevel 1 exit /b 1
call :profile_path "%~3"
if not exist "%AP_PROFILE%\" (
    echo agent-profile: profile '%~3' does not exist >&2
    exit /b 1
)
if /i "%AP_PROVIDER%"=="antigravity" (endlocal & set "AGENT_PROFILE_ANTIGRAVITY_ACTIVE=%~3" & echo Switched to antigravity profile: %~3) else (endlocal & set "AGENT_PROFILE_CODEX_ACTIVE=%~3" & echo Switched to codex profile: %~3)
exit /b 0

:which
if not "%~4"=="" (
    echo agent-profile: usage: agent-profile which %AP_PROVIDER% [name] >&2
    exit /b 1
)
if not "%~3"=="" (
    call :validate_name "%~3"
    if errorlevel 1 exit /b 1
    call :profile_path "%~3"
    if not exist "%AP_PROFILE%\" (
        echo agent-profile: profile '%~3' does not exist >&2
        exit /b 1
    )
    echo %AP_PROFILE%
    exit /b 0
)
call :selected_path
if errorlevel 1 (
    echo agent-profile: no active or default profile set for %AP_PROVIDER% >&2
    exit /b 1
)
echo %AP_SELECTED%
exit /b 0

:restart
if /i not "%AP_PROVIDER%"=="antigravity" (
    echo agent-profile: restart is only supported for antigravity >&2
    exit /b 1
)
:: --new-window is a VS Code flag and is inert for a plain Electron build, but
:: on Windows the GUI is always reached as a PATH executable -- there is no
:: macOS app-bundle mode here -- so it is injected unless the user already
:: passed it. What actually lets a second profile open alongside a running one
:: is the separate HOME plus the separate user-data-dir antigravity.cmd sets.
set "AP_NEW_WINDOW=--new-window"
for %%A in (%3 %4 %5 %6 %7 %8 %9) do if /i "%%~A"=="--new-window" set "AP_NEW_WINDOW="
if defined AP_NEW_WINDOW (
    call "%~dp0antigravity.cmd" --new-window %3 %4 %5 %6 %7 %8 %9
) else (
    call "%~dp0antigravity.cmd" %3 %4 %5 %6 %7 %8 %9
)
exit /b %ERRORLEVEL%

:status
if not "%~3"=="" (
    echo agent-profile: usage: agent-profile status %AP_PROVIDER% >&2
    exit /b 1
)
call :default_name
if errorlevel 1 set "AP_NAME=<none>"
echo Provider: %AP_PROVIDER%
echo Default: %AP_NAME%
if /i "%AP_PROVIDER%"=="antigravity" (if defined AGENT_PROFILE_ANTIGRAVITY_ACTIVE (echo Active: %AGENT_PROFILE_ANTIGRAVITY_ACTIVE%) else echo Active: ^<default^>)
if /i "%AP_PROVIDER%"=="codex" (if defined AGENT_PROFILE_CODEX_ACTIVE (echo Active: %AGENT_PROFILE_CODEX_ACTIVE%) else echo Active: ^<default^>)
exit /b 0

:delete
if "%~3"=="" goto :delete_usage
set "AP_DELETE_FORCE=0"
if /i "%~4"=="--force" set "AP_DELETE_FORCE=1"
if not "%~4"=="" if not "%~4"=="--force" goto :delete_usage
if not "%~5"=="" goto :delete_usage
call :validate_name "%~3"
if errorlevel 1 exit /b 1
call :profile_path "%~3"
if not exist "%AP_PROFILE%\" (
    echo agent-profile: profile '%~3' does not exist >&2
    exit /b 1
)
if "%AP_DELETE_FORCE%"=="0" (
    set /p "AP_CONFIRM=Delete %AP_PROVIDER% profile '%~3' and all its data? [y/N] "
    if /i not "!AP_CONFIRM!"=="y" if /i not "!AP_CONFIRM!"=="yes" (echo Cancelled. & exit /b 0)
)
rmdir /s /q "%AP_PROFILE%" >nul 2>&1
call :provider_root
if exist "%AP_ROOT%\.default" (
    set /p AP_DEFAULT=<"%AP_ROOT%\.default"
    if /i "!AP_DEFAULT!"=="%~3" del /f /q "%AP_ROOT%\.default" >nul 2>&1
)
echo Deleted %AP_PROVIDER% profile: %~3
exit /b 0

:delete_usage
echo agent-profile: usage: agent-profile delete %AP_PROVIDER% ^<name^> [--force] >&2
exit /b 1
