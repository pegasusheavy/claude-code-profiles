@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: antigravity.cmd — launch the Antigravity GUI with the selected profile.
::
:: HOME/USERPROFILE is the knob that actually switches profiles: Antigravity
:: resolves its real state (account, credentials, conversations, agent data)
:: from os.homedir()\.gemini, and on Windows Node's os.homedir() reads
:: USERPROFILE. A run that only overrides --user-data-dir keeps loading the
:: original profile. --user-data-dir is still passed because it moves
:: Chromium's own user data -- most importantly the singleton lock -- which is
:: what lets two profiles run at the same time.

set "GUI_EXE=%AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND%"
if not defined GUI_EXE for /f "delims=" %%E in ('where antigravity-ide.exe 2^>nul') do if not defined GUI_EXE set "GUI_EXE=%%E"
if not defined GUI_EXE for /f "delims=" %%E in ('where antigravity.exe 2^>nul') do if not defined GUI_EXE set "GUI_EXE=%%E"
if not defined GUI_EXE (
    echo agent-profile: could not find antigravity GUI; set AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND >&2
    exit /b 127
)
set "GUI_PROFILE="
for /f "delims=" %%P in ('call "%~dp0agent-profile.cmd" internal-path antigravity 2^>nul') do if not defined GUI_PROFILE set "GUI_PROFILE=%%P"
set "HAS_DATA_ARG=0"
for %%A in (%*) do (
    set "GUI_ARG=%%~A"
    if /i "!GUI_ARG!"=="--user-data-dir" set "HAS_DATA_ARG=1"
    if /i "!GUI_ARG:~0,16!"=="--user-data-dir=" set "HAS_DATA_ARG=1"
)

:: Delayed expansion was only needed to scan the arguments. Everything below
:: runs with it off so a '!' inside a user argument -- or inside a resolved
:: path -- is not eaten by the second expansion pass. Both scopes are popped
:: by the implicit endlocal when this script exits.
setlocal DisableDelayedExpansion

:: No profile selected: launch exactly as the user typed it, untouched.
if not defined GUI_PROFILE goto :launch_plain

set "GUI_HOME=%GUI_PROFILE%\home"
set "GUI_DATA=%GUI_PROFILE%\gui-user-data"
if not exist "%GUI_HOME%\" mkdir "%GUI_HOME%" >nul 2>&1
if not exist "%GUI_DATA%\" mkdir "%GUI_DATA%" >nul 2>&1

:: The GUI is launched from inside this setlocal scope, so the child inherits
:: the profile HOME while the caller's cmd session keeps its own. The
:: `endlocal & set "HOME=..."` idiom would have had to leak both variables into
:: that session permanently instead.
set "HOME=%GUI_HOME%"
set "USERPROFILE=%GUI_HOME%"

:: An explicit --user-data-dir from the user wins: inject no flag, but still
:: hand the child the profile HOME.
if "%HAS_DATA_ARG%"=="1" goto :launch_plain

:: The "=" form is required: Antigravity is a plain Electron app whose Chromium
:: parser only understands --switch=value and silently ignores the
:: space-separated spelling. A VS Code derived antigravity-ide accepts it too.
:: The whole argument is quoted so a profile path containing spaces still
:: arrives as a single argv entry.
"%GUI_EXE%" "--user-data-dir=%GUI_DATA%" %*
exit /b %ERRORLEVEL%

:launch_plain
"%GUI_EXE%" %*
exit /b %ERRORLEVEL%
