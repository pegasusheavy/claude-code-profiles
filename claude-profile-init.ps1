# claude-profile-init.ps1 — Dot-source this in your $PROFILE
#
#   . "${env:LOCALAPPDATA}\claude-profile\claude-profile-init.ps1"    (Windows)
#   . "${XDG_DATA_HOME:-$HOME/.local/share}/claude-profile/claude-profile-init.ps1"  (Linux/macOS)
#
# Provides:
#   claude           — runs Claude Code with the active/default profile
#   claude-profile   — manage profiles (create, list, delete, default, use, which)

# --- claude wrapper ---
# Auto-resolves the default profile before calling the real claude binary.
# If CLAUDE_CONFIG_DIR is already set (e.g. via 'claude-profile use'),
# it passes through without overriding.

function claude {
    if (-not $env:CLAUDE_CONFIG_DIR) {
        if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) {
            $DataDir = Join-Path $env:LOCALAPPDATA 'claude-profiles'
        } else {
            if ($env:XDG_DATA_HOME) {
                $DataDir = Join-Path $env:XDG_DATA_HOME 'claude-profiles'
            } else {
                $DataDir = Join-Path $HOME '.local' 'share' 'claude-profiles'
            }
        }
        $DefaultFile = Join-Path $DataDir '.default'
        if (Test-Path $DefaultFile) {
            $Name = (Get-Content $DefaultFile -Raw).Trim()
            $ProfilePath = Join-Path $DataDir $Name
            if ($Name -and (Test-Path $ProfilePath -PathType Container)) {
                $env:CLAUDE_CONFIG_DIR = $ProfilePath
            }
        }
    }
    $ClaudePath = (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue |
                   Select-Object -First 1).Source
    if (-not $ClaudePath) {
        $host.UI.WriteErrorLine("claude-profile: 'claude' binary not found in PATH")
        return
    }
    & $ClaudePath @args
}

# --- claude-profile management function ---

function claude-profile {
    $ErrorActionPreference = 'Stop'

    # --- Platform-aware data directory ---
    if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) {
        $DataDir = Join-Path $env:LOCALAPPDATA 'claude-profiles'
    } else {
        if ($env:XDG_DATA_HOME) {
            $DataDir = Join-Path $env:XDG_DATA_HOME 'claude-profiles'
        } else {
            $DataDir = Join-Path $HOME '.local' 'share' 'claude-profiles'
        }
    }
    $DefaultFile = Join-Path $DataDir '.default'

    # --- Parse $args manually ---
    $Command = if ($args.Count -gt 0) { $args[0] } else { $null }
    $Rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

    # --- Helpers (nested functions, scoped to claude-profile) ---

    function _cp_die {
        param([string]$Message)
        $host.UI.WriteErrorLine("claude-profile: $Message")
    }

    function _cp_validate_name {
        param([string]$Name)
        if ([string]::IsNullOrEmpty($Name)) {
            _cp_die 'profile name must not be empty'
            return $false
        }
        if ($Name.StartsWith('.')) {
            _cp_die "invalid profile name '$Name': must not start with '.'"
            return $false
        }
        if ($Name.Contains('..')) {
            _cp_die "invalid profile name '$Name': must not contain '..'"
            return $false
        }
        if ($Name.Contains('/')) {
            _cp_die "invalid profile name '$Name': must not contain '/'"
            return $false
        }
        if ($Name.Contains('\')) {
            _cp_die "invalid profile name '$Name': must not contain '\'"
            return $false
        }
        if ($Name -notmatch '^[A-Za-z0-9_-]+$') {
            _cp_die "invalid profile name '$Name': use only letters, digits, hyphens, underscores"
            return $false
        }
        return $true
    }

    # --- Command dispatch ---

    switch ($Command) {
        'use' {
            $ArgName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
            if ([string]::IsNullOrEmpty($ArgName)) {
                _cp_die 'usage: claude-profile use <name>'
                return
            }
            if ($Rest.Count -gt 1) {
                _cp_die "unexpected argument after profile name: '$($Rest[1])'"
                return
            }
            if (-not (_cp_validate_name $ArgName)) { return }
            $ProfileDir = Join-Path $DataDir $ArgName
            if (-not (Test-Path $ProfileDir -PathType Container)) {
                _cp_die "profile '$ArgName' does not exist. Create it with: claude-profile create $ArgName"
                return
            }
            $env:CLAUDE_CONFIG_DIR = $ProfileDir
            Write-Host "Switched to profile: $ArgName"
        }

        'create' {
            $ArgName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
            if ([string]::IsNullOrEmpty($ArgName)) {
                _cp_die 'usage: claude-profile create <name>'
                return
            }
            if (-not (_cp_validate_name $ArgName)) { return }
            $ProfileDir = Join-Path $DataDir $ArgName
            if (Test-Path $ProfileDir -PathType Container) {
                _cp_die "profile '$ArgName' already exists"
                return
            }
            New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
            Write-Host "Created profile: $ArgName"
            Write-Host "Config directory: $ProfileDir"
        }

        { $_ -eq 'list' -or $_ -eq 'ls' } {
            if (-not (Test-Path $DataDir -PathType Container)) {
                Write-Host 'No profiles found. Create one with: claude-profile create <name>'
                return
            }
            $CurDefault = ''
            if (Test-Path $DefaultFile) {
                $CurDefault = (Get-Content $DefaultFile -Raw).Trim()
            }
            # Derive active profile name from CLAUDE_CONFIG_DIR
            $Active = ''
            if ($env:CLAUDE_CONFIG_DIR) {
                $Normalized = $env:CLAUDE_CONFIG_DIR.Replace('\', '/')
                $NormalizedData = $DataDir.Replace('\', '/')
                if ($Normalized.StartsWith("$NormalizedData/")) {
                    $Active = Split-Path $env:CLAUDE_CONFIG_DIR -Leaf
                }
            }
            $Entries = Get-ChildItem -Path $DataDir -Directory -ErrorAction SilentlyContinue
            if (-not $Entries -or $Entries.Count -eq 0) {
                Write-Host 'No profiles found. Create one with: claude-profile create <name>'
                return
            }
            foreach ($Entry in $Entries) {
                $IsDefault = ($Entry.Name -eq $CurDefault)
                $IsActive = ($Entry.Name -eq $Active)
                if ($IsDefault -and $IsActive) {
                    Write-Host ">* $($Entry.Name) (default, active)"
                } elseif ($IsDefault) {
                    Write-Host " * $($Entry.Name) (default)"
                } elseif ($IsActive) {
                    Write-Host ">  $($Entry.Name) (active)"
                } else {
                    Write-Host "   $($Entry.Name)"
                }
            }
        }

        'default' {
            $ArgName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
            if ([string]::IsNullOrEmpty($ArgName)) {
                # Get default
                if (Test-Path $DefaultFile) {
                    $CurDefault = (Get-Content $DefaultFile -Raw).Trim()
                    if ($CurDefault) {
                        Write-Host $CurDefault
                    } else {
                        _cp_die 'default profile file is empty. Set one with: claude-profile default <name>'
                        return
                    }
                } else {
                    _cp_die 'no default profile set. Set one with: claude-profile default <name>'
                    return
                }
                return
            }
            # Set default
            if (-not (_cp_validate_name $ArgName)) { return }
            $ProfileDir = Join-Path $DataDir $ArgName
            if (-not (Test-Path $ProfileDir -PathType Container)) {
                _cp_die "profile '$ArgName' does not exist. Create it with: claude-profile create $ArgName"
                return
            }
            if (-not (Test-Path $DataDir -PathType Container)) {
                New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllText($DefaultFile, $ArgName)
            Write-Host "Default profile set to: $ArgName"
        }

        'which' {
            $ArgName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
            if (-not [string]::IsNullOrEmpty($ArgName)) {
                # Named profile
                if (-not (_cp_validate_name $ArgName)) { return }
                $ProfileDir = Join-Path $DataDir $ArgName
                if (-not (Test-Path $ProfileDir -PathType Container)) {
                    _cp_die "profile '$ArgName' does not exist. Create it with: claude-profile create $ArgName"
                    return
                }
                Write-Host $ProfileDir
            } else {
                # Resolve default
                if (-not (Test-Path $DefaultFile)) {
                    _cp_die 'no default profile set. Use: claude-profile default <name>'
                    return
                }
                $CurDefault = (Get-Content $DefaultFile -Raw).Trim()
                if ([string]::IsNullOrEmpty($CurDefault)) {
                    _cp_die 'default profile file is empty. Set one with: claude-profile default <name>'
                    return
                }
                $ProfileDir = Join-Path $DataDir $CurDefault
                if (-not (Test-Path $ProfileDir -PathType Container)) {
                    _cp_die "profile '$CurDefault' does not exist. Create it with: claude-profile create $CurDefault"
                    return
                }
                Write-Host $ProfileDir
            }
        }

        'delete' {
            $ArgName = if ($Rest.Count -gt 0) { $Rest[0] } else { $null }
            if ([string]::IsNullOrEmpty($ArgName)) {
                _cp_die 'usage: claude-profile delete <name>'
                return
            }
            if (-not (_cp_validate_name $ArgName)) { return }
            $ProfileDir = Join-Path $DataDir $ArgName
            if (-not (Test-Path $ProfileDir -PathType Container)) {
                _cp_die "profile '$ArgName' does not exist"
                return
            }
            $Confirm = Read-Host "Delete profile `"$ArgName`" and all its data? [y/N]"
            if ($Confirm -match '^[yY]([eE][sS])?$') {
                Remove-Item -Path $ProfileDir -Recurse -Force
                Write-Host "Deleted profile: $ArgName"
                # Clear default if the deleted profile was the default
                if (Test-Path $DefaultFile) {
                    $CurDefault = (Get-Content $DefaultFile -Raw).Trim()
                    if ($CurDefault -eq $ArgName) {
                        Remove-Item -Path $DefaultFile -Force
                        Write-Host "Cleared default profile (was `"$ArgName`")"
                    }
                }
                # Unset CLAUDE_CONFIG_DIR if the deleted profile was active
                if ($env:CLAUDE_CONFIG_DIR -eq $ProfileDir) {
                    Remove-Item Env:\CLAUDE_CONFIG_DIR
                    Write-Host "Cleared active profile (was `"$ArgName`")"
                }
            } else {
                Write-Host 'Cancelled.'
            }
        }

        { $_ -eq 'help' -or $_ -eq '-h' -or $_ -eq '--help' } {
            Write-Host @"
Usage: claude-profile [command] [args...]

Commands:
    (no command)            Show current profile status
    use <name>              Switch session to the named profile
    create <name>           Create a new profile
    list, ls                List all profiles
    default [name]          Get or set the default profile
    which [name]            Show the resolved config directory path
    delete <name>           Delete a profile
    help, -h, --help        Show this help message

The claude command automatically uses the default profile. Use
'claude-profile use <name>' to override for the current session.

Examples:
    claude-profile create work
    claude-profile default work
    claude-profile use work
    claude                          # runs with "work" profile
    claude-profile                  # shows active/default status
"@
        }

        $null {
            # Bare invocation: show status
            $Active = ''
            if ($env:CLAUDE_CONFIG_DIR) {
                $Normalized = $env:CLAUDE_CONFIG_DIR.Replace('\', '/')
                $NormalizedData = $DataDir.Replace('\', '/')
                if ($Normalized.StartsWith("$NormalizedData/")) {
                    $Active = Split-Path $env:CLAUDE_CONFIG_DIR -Leaf
                }
            }
            if ($Active) {
                Write-Host "Active profile: $Active"
                Write-Host "Config directory: $env:CLAUDE_CONFIG_DIR"
            } elseif ($env:CLAUDE_CONFIG_DIR) {
                Write-Host "Active config directory: $env:CLAUDE_CONFIG_DIR (not a managed profile)"
            } else {
                Write-Host 'No active profile'
            }
            $CurDefault = ''
            if (Test-Path $DefaultFile) {
                $CurDefault = (Get-Content $DefaultFile -Raw).Trim()
            }
            if ($CurDefault) {
                Write-Host "Default profile: $CurDefault"
            } else {
                Write-Host 'No default profile set'
            }
        }

        default {
            _cp_die "unknown command '$Command'. Run 'claude-profile help' for usage."
            return
        }
    }
}
