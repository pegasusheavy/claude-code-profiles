@echo off
setlocal EnableExtensions DisableDelayedExpansion

:: codex.cmd — launch the Codex CLI with the selected profile.
::
:: CODEX_HOME is what selects the profile; the profile directory itself is the
:: Codex home (it has no home\ or gui-user-data\ subdirectory).
::
:: Delayed expansion is deliberately off: nothing here needs it, and leaving it
:: on would eat a '!' inside a user argument once the launch moved inside the
:: setlocal scope.

set "CODEX_EXE="
for /f "delims=" %%E in ('where codex.exe 2^>nul') do if not defined CODEX_EXE set "CODEX_EXE=%%E"
if not defined CODEX_EXE set "CODEX_EXE=codex.exe"
set "CODEX_PROFILE="
for /f "delims=" %%P in ('call "%~dp0agent-profile.cmd" internal-path codex 2^>nul') do if not defined CODEX_PROFILE set "CODEX_PROFILE=%%P"

:: No profile selected: launch exactly as the user typed it, untouched.
if not defined CODEX_PROFILE goto :launch

:: Launched from inside this setlocal scope so the child inherits CODEX_HOME
:: while the caller's cmd session keeps its own. The `endlocal & set
:: "CODEX_HOME=..."` idiom used before had to leak it into that session
:: permanently, which silently repointed every later codex run in the window.
set "CODEX_HOME=%CODEX_PROFILE%"

:launch
"%CODEX_EXE%" %*
exit /b %ERRORLEVEL%
