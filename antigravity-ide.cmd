@echo off
:: antigravity-ide.cmd — alias for antigravity.cmd. The profile-aware launch
:: (profile HOME/USERPROFILE plus the equals-form --user-data-dir) lives there.
call "%~dp0antigravity.cmd" %*
exit /b %ERRORLEVEL%
