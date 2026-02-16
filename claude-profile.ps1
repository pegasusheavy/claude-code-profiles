#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

# --- Platform-aware data directory ---
# Uses XDG_DATA_HOME on Linux/macOS, falls back to ~/.local/share
# On Windows, uses LOCALAPPDATA\claude-profiles
# On macOS, XDG is still respected if set; otherwise uses ~/.local/share
# (We don't use ~/Library/Application Support because this script targets
#  terminal users who expect Unix conventions)

if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) {
    $DataDir = Join-Path $env:LOCALAPPDATA 'claude-profiles'
} else {
    # Linux or macOS (PowerShell 6+)
    if ($env:XDG_DATA_HOME) {
        $DataDir = Join-Path $env:XDG_DATA_HOME 'claude-profiles'
    } else {
        $DataDir = Join-Path $HOME '.local' 'share' 'claude-profiles'
    }
}
$DefaultFile = Join-Path $DataDir '.default'

# --- Helper functions ---

function Write-Die {
    param([string]$Message)
    $host.UI.WriteErrorLine("claude-profile: $Message")
    exit 1
}

function Show-Usage {
    Write-Host @"
Usage: claude-profile [command] [args...]

Commands:
    (no command)            Launch Claude with the default profile
    use <name> [args...]    Launch Claude with the named profile
    create <name>           Create a new profile
    list, ls                List all profiles
    default [name]          Get or set the default profile
    delete <name>           Delete a profile
    which [name]            Show the resolved config directory path
    help, -h, --help        Show this help message

When invoked with no command (or with flags like -p, --verbose, etc.),
claude-profile launches Claude using the default profile, passing all
arguments through.

Examples:
    claude-profile create work
    claude-profile default work
    claude-profile                  # launches claude with "work" profile
    claude-profile use work -p      # launches claude -p with "work" profile
    claude-profile --resume         # launches claude --resume with default
"@
}

function Assert-ValidName {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) {
        Write-Die 'profile name must not be empty'
    }
    if ($Name.StartsWith('.')) {
        Write-Die "invalid profile name '$Name': must not contain '/' or start with '.'"
    }
    if ($Name.Contains('/') -or $Name.Contains('\') -or $Name.Contains('..')) {
        Write-Die "invalid profile name '$Name': must not contain '/' or start with '.'"
    }
    if ($Name -notmatch '^[A-Za-z0-9_-]+$') {
        Write-Die "invalid profile name '$Name': use only letters, digits, hyphens, underscores"
    }
}

function Resolve-ProfileDir {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) {
        if (-not (Test-Path $DefaultFile)) {
            Write-Die 'no default profile set. Use: claude-profile default <name>'
        }
        $Name = (Get-Content $DefaultFile -Raw).Trim()
        if ([string]::IsNullOrEmpty($Name)) {
            Write-Die 'default profile file is empty. Set one with: claude-profile default <name>'
        }
    }
    $ProfilePath = Join-Path $DataDir $Name
    if (-not (Test-Path $ProfilePath -PathType Container)) {
        Write-Die "profile '$Name' does not exist. Create it with: claude-profile create $Name"
    }
    return $ProfilePath
}

# --- Commands ---

function Invoke-Create {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) {
        Write-Die 'usage: claude-profile create <name>'
    }
    Assert-ValidName $Name
    $ProfilePath = Join-Path $DataDir $Name
    if (Test-Path $ProfilePath -PathType Container) {
        Write-Die "profile '$Name' already exists"
    }
    New-Item -ItemType Directory -Path $ProfilePath -Force | Out-Null
    Write-Host "Created profile: $Name"
    Write-Host "Config directory: $ProfilePath"
}

function Invoke-List {
    if (-not (Test-Path $DataDir -PathType Container)) {
        Write-Host 'No profiles found. Create one with: claude-profile create <name>'
        return
    }
    $Default = ''
    if (Test-Path $DefaultFile) {
        $Default = (Get-Content $DefaultFile -Raw).Trim()
    }
    $Entries = Get-ChildItem -Path $DataDir -Directory -ErrorAction SilentlyContinue
    if (-not $Entries -or $Entries.Count -eq 0) {
        Write-Host 'No profiles found. Create one with: claude-profile create <name>'
        return
    }
    foreach ($Entry in $Entries) {
        if ($Entry.Name -eq $Default) {
            Write-Host "* $($Entry.Name) (default)"
        } else {
            Write-Host "  $($Entry.Name)"
        }
    }
}

function Invoke-Default {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) {
        if (Test-Path $DefaultFile) {
            $Current = (Get-Content $DefaultFile -Raw).Trim()
            Write-Host $Current
        } else {
            Write-Die 'no default profile set. Set one with: claude-profile default <name>'
        }
        return
    }
    Assert-ValidName $Name
    $ProfilePath = Join-Path $DataDir $Name
    if (-not (Test-Path $ProfilePath -PathType Container)) {
        Write-Die "profile '$Name' does not exist. Create it with: claude-profile create $Name"
    }
    if (-not (Test-Path $DataDir -PathType Container)) {
        New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($DefaultFile, $Name)
    Write-Host "Default profile set to: $Name"
}

function Invoke-Which {
    param([string]$Name)
    $Dir = Resolve-ProfileDir $Name
    Write-Host $Dir
}

function Invoke-Use {
    param([string]$Name, [string[]]$RemainingArgs)
    if ([string]::IsNullOrEmpty($Name)) {
        Write-Die 'usage: claude-profile use <name> [claude args...]'
    }
    $Dir = Resolve-ProfileDir $Name
    $env:CLAUDE_CONFIG_DIR = $Dir
    if ($RemainingArgs -and $RemainingArgs.Count -gt 0) {
        & claude @RemainingArgs
    } else {
        & claude
    }
    exit $LASTEXITCODE
}

function Invoke-Delete {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) {
        Write-Die 'usage: claude-profile delete <name>'
    }
    Assert-ValidName $Name
    $ProfilePath = Join-Path $DataDir $Name
    if (-not (Test-Path $ProfilePath -PathType Container)) {
        Write-Die "profile '$Name' does not exist"
    }
    $Confirm = Read-Host "Delete profile `"$Name`" and all its data? [y/N]"
    if ($Confirm -match '^[yY]([eE][sS])?$') {
        Remove-Item -Path $ProfilePath -Recurse -Force
        Write-Host "Deleted profile: $Name"
        if (Test-Path $DefaultFile) {
            $Current = (Get-Content $DefaultFile -Raw).Trim()
            if ($Current -eq $Name) {
                Remove-Item -Path $DefaultFile -Force
                Write-Host "Cleared default profile (was `"$Name`")"
            }
        }
    } else {
        Write-Host 'Cancelled.'
    }
}

function Invoke-LaunchDefault {
    param([string[]]$PassthroughArgs)
    $Dir = Resolve-ProfileDir
    $env:CLAUDE_CONFIG_DIR = $Dir
    if ($PassthroughArgs -and $PassthroughArgs.Count -gt 0) {
        & claude @PassthroughArgs
    } else {
        & claude
    }
    exit $LASTEXITCODE
}

# --- Dispatcher ---
# Parse $args manually: first positional arg is the command, rest depends on context.

$Command = if ($args.Count -gt 0) { $args[0] } else { $null }
$Rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

switch ($Command) {
    $null {
        Invoke-LaunchDefault
        break
    }
    'create' {
        $ProfileName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
        Invoke-Create $ProfileName
        break
    }
    { $_ -eq 'list' -or $_ -eq 'ls' } {
        Invoke-List
        break
    }
    'default' {
        $ProfileName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
        Invoke-Default $ProfileName
        break
    }
    'which' {
        $ProfileName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
        Invoke-Which $ProfileName
        break
    }
    'use' {
        $ProfileName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
        $UseRest = if ($Rest.Count -gt 1) { $Rest[1..($Rest.Count - 1)] } else { @() }
        Invoke-Use $ProfileName $UseRest
        break
    }
    'delete' {
        $ProfileName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
        Invoke-Delete $ProfileName
        break
    }
    { $_ -eq 'help' -or $_ -eq '-h' -or $_ -eq '--help' } {
        Show-Usage
        break
    }
    { $_.StartsWith('-') } {
        # Flag passthrough: all args go to claude with default profile
        Invoke-LaunchDefault $args
        break
    }
    default {
        Write-Die "unknown command '$Command'. Run 'claude-profile help' for usage."
    }
}
