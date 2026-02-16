# claude-code-profiles installer for Windows/PowerShell
# Usage:
#   irm https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/install.ps1 | iex
#
# Environment variables:
#   INSTALL_DIR  - Override the install directory (default: $env:LOCALAPPDATA\Programs\claude-profile)

$ErrorActionPreference = 'Stop'

$RepoBase = 'https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main'
$Scripts = @('claude-profile.ps1', 'claude-profile.cmd')

function Write-Step($msg) { Write-Host "`n=> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "  $msg" }
function Write-Warn($msg) { Write-Host "  [warn] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) {
    Write-Host "  [error] $msg" -ForegroundColor Red
    throw $msg
}

# --- Determine install directory ---

function Get-InstallDir {
    if ($env:INSTALL_DIR) {
        return $env:INSTALL_DIR
    }
    $default = Join-Path $env:LOCALAPPDATA 'Programs\claude-profile'
    return $default
}

# --- Check if directory is on PATH (user scope) ---

function Test-OnPath($dir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { return $false }
    $paths = $userPath -split ';' | Where-Object { $_ -ne '' }
    foreach ($p in $paths) {
        if ($p.TrimEnd('\') -eq $dir.TrimEnd('\')) {
            return $true
        }
    }
    return $false
}

# --- Add directory to user PATH ---

function Add-ToUserPath($dir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) {
        $newPath = $dir
    } else {
        $newPath = "$userPath;$dir"
    }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    # Also update current session so it's immediately usable
    if ($env:Path -notlike "*$dir*") {
        $env:Path = "$dir;$env:Path"
    }
}

# --- Main ---

Write-Host 'claude-code-profiles installer' -ForegroundColor White
Write-Host '================================' -ForegroundColor White

Write-Step 'Determining install directory...'
$installDir = Get-InstallDir

if (Test-Path $installDir) {
    Write-Info "Install directory: $installDir (exists, updating in place)"
} else {
    Write-Info "Install directory: $installDir (creating)"
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

Write-Step 'Downloading scripts...'
foreach ($script in $Scripts) {
    $url = "$RepoBase/$script"
    $dest = Join-Path $installDir $script
    Write-Info "  $script -> $dest"
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    } catch {
        Write-Fail "Failed to download $script from $url : $_"
    }
}
Write-Info 'Downloaded successfully.'

Write-Step 'Checking PATH...'
if (Test-OnPath $installDir) {
    Write-Info "$installDir is already on your PATH."
} else {
    Write-Info "Adding $installDir to user PATH..."
    Add-ToUserPath $installDir
    Write-Info 'PATH updated. New terminal windows will pick this up automatically.'
}

# Create a convenience batch wrapper so 'claude-profile' works in cmd without extension
$wrapperCmd = Join-Path $installDir 'claude-profile.cmd'
if (Test-Path $wrapperCmd) {
    Write-Info 'claude-profile.cmd already present.'
}

# Create a convenience ps1 profile alias hint
Write-Step 'Done!'
Write-Info ''
Write-Info 'Quick start (PowerShell):'
Write-Info '  claude-profile.ps1 create work     # Create a profile'
Write-Info '  claude-profile.ps1 default work    # Set it as default'
Write-Info '  claude-profile.ps1                 # Launch Claude with the profile'
Write-Info ''
Write-Info 'Quick start (cmd.exe):'
Write-Info '  claude-profile create work'
Write-Info '  claude-profile default work'
Write-Info '  claude-profile'
Write-Info ''
Write-Info 'Tip: To use "claude-profile" in PowerShell without the .ps1 extension,'
Write-Info 'add an alias to your $PROFILE:'
Write-Info "  Set-Alias claude-profile '$wrapperCmd' "
Write-Info "  Or: Set-Alias claude-profile '$(Join-Path $installDir 'claude-profile.ps1')'"
Write-Info ''
Write-Host ''
