@echo off
setlocal EnableExtensions DisableDelayedExpansion

:: agy.cmd — launch the Antigravity CLI with the selected profile.
::
:: HOME/USERPROFILE is what selects the profile: agy resolves its state from
:: os.homedir()\.gemini, and on Windows Node's os.homedir() reads USERPROFILE.
::
:: Delayed expansion is deliberately off: nothing here needs it, and leaving it
:: on would eat a '!' inside a user argument once the launch moved inside the
:: setlocal scope.

set "AGY_EXE="
for /f "delims=" %%E in ('where agy.exe 2^>nul') do if not defined AGY_EXE set "AGY_EXE=%%E"
if not defined AGY_EXE set "AGY_EXE=agy.exe"
set "AGY_PROFILE="
for /f "delims=" %%P in ('call "%~dp0agent-profile.cmd" internal-path antigravity 2^>nul') do if not defined AGY_PROFILE set "AGY_PROFILE=%%P"

:: No profile selected: launch exactly as the user typed it, untouched.
if not defined AGY_PROFILE goto :launch

set "AGY_HOME=%AGY_PROFILE%\home"
:: Launched from inside this setlocal scope so the child inherits the profile
:: HOME while the caller's cmd session keeps its own. The `endlocal & set
:: "HOME=..."` idiom used before had to leak both variables into that session
:: permanently, which silently repointed every later tool in the window.
set "HOME=%AGY_HOME%"
set "USERPROFILE=%AGY_HOME%"

:launch
"%AGY_EXE%" %*
exit /b %ERRORLEVEL%
