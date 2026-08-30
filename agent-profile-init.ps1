# agent-profile-init.ps1 — dot-source this in $PROFILE
#
# Provides provider-neutral profile management for Antigravity (agy + GUI)
# and Codex. The existing claude-profile-init.ps1 remains the Claude adapter.

function Test-APWindows {
    return ($env:OS -eq 'Windows_NT' -or $PSVersionTable.PSEdition -eq 'Desktop')
}

function Get-APHome {
    if ((Test-APWindows) -and $env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    return $HOME
}

# $IsMacOS only exists in PowerShell 6+; Windows PowerShell 5.1 has no such
# variable, so it is read through Get-Variable rather than referenced bare.
# 5.1 is Windows-only anyway, which the Windows check settles before that read.
function Test-APMacOS {
    if (Test-APWindows) { return $false }
    $macOS = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $macOS) { return $false }
    return [bool]$macOS
}

# macOS resolves the default login keychain at $HOME/Library/Keychains, so a child
# whose HOME points at a profile has no keychain at all and Chromium (inside
# Antigravity) cannot store its "Antigravity Safe Storage" key -- the app then
# stops on a "Keychain Not Found" modal. Link the real keychain directory into the
# profile home so the child resolves the login keychain again. This costs no
# account isolation: the Google account lives in ~/.gemini files, while the
# keychain item is only Chromium's at-rest key for the local cookie store.
#
# macOS only. On Windows DPAPI is tied to the user account rather than HOME, and
# on Linux Chromium reaches the Secret Service over D-Bus, which HOME does not
# move -- neither platform gets this link.
function Add-APMacOSKeychainLink {
    param([string]$ProfileHome)
    if (-not (Test-APMacOS)) { return }
    try {
        # Get-APHome is the caller's real home: this adapter never mutates $env:.
        $realKeychains = Join-Path (Join-Path (Get-APHome) 'Library') 'Keychains'
        if (-not (Test-Path -LiteralPath $realKeychains -PathType Container)) { return }
        $libraryDir = Join-Path $ProfileHome 'Library'
        $linkPath = Join-Path $libraryDir 'Keychains'
        # Never disturb a real directory or an existing link the user put here --
        # including a dangling one, which Test-Path -PathType Container reports as
        # absent (it follows the link) while New-Item would still fail on it.
        # Get-Item -Force reports the entry itself, so it catches every case.
        if (Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue) { return }
        New-Item -ItemType Directory -Path $libraryDir -Force -ErrorAction Stop | Out-Null
        # Symlink creation needs no elevation on macOS.
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $realKeychains -ErrorAction Stop | Out-Null
    } catch {
        # Convenience only -- a failure here must never block a launch.
    }
}

function Get-APDataDir {
    if ($env:AGENT_PROFILE_DATA_DIR) { return $env:AGENT_PROFILE_DATA_DIR }
    if ((Test-APWindows) -and $env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'agent-profiles') }
    if ($env:XDG_DATA_HOME) { return (Join-Path $env:XDG_DATA_HOME 'agent-profiles') }
    $base = Join-Path (Get-APHome) '.local/share'
    return (Join-Path $base 'agent-profiles')
}

function Test-APProfileName {
    param([string]$Name)
    if (-not $Name -or $Name -notmatch '^[A-Za-z0-9_-]+$' -or $Name.StartsWith('.') -or $Name.Contains('..')) {
        throw "agent-profile: invalid profile name '$Name': use only letters, digits, hyphens, underscores"
    }
    return $true
}

function Get-APProvider {
    param([string]$Provider)
    switch ($Provider) {
        'agy' { return 'antigravity' }
        'antigravity' { return 'antigravity' }
        'antigravity-cli' { return 'antigravity' }
        'antigravity-gui' { return 'antigravity' }
        'antigravity-ide' { return 'antigravity' }
        'codex' { return 'codex' }
        default { throw "agent-profile: unknown provider '$Provider' (use antigravity or codex)" }
    }
}

function Get-APProviderDir {
    param([string]$Provider)
    return (Join-Path (Get-APDataDir) $Provider)
}

function Get-APProfilePath {
    param([string]$Provider, [string]$Name)
    Test-APProfileName $Name | Out-Null
    return (Join-Path (Get-APProviderDir $Provider) $Name)
}

function Get-APDefaultFile {
    param([string]$Provider)
    return (Join-Path (Get-APProviderDir $Provider) '.default')
}

function Get-APActiveName {
    param([string]$Provider)
    if ($Provider -eq 'antigravity') { return $env:AGENT_PROFILE_ANTIGRAVITY_ACTIVE }
    if ($Provider -eq 'codex') { return $env:AGENT_PROFILE_CODEX_ACTIVE }
    return $null
}

function Set-APActiveName {
    param([string]$Provider, [string]$Name)
    if ($Provider -eq 'antigravity') {
        if ($Name) { $env:AGENT_PROFILE_ANTIGRAVITY_ACTIVE = $Name } else { Remove-Item Env:AGENT_PROFILE_ANTIGRAVITY_ACTIVE -ErrorAction SilentlyContinue }
    }
    if ($Provider -eq 'codex') {
        if ($Name) { $env:AGENT_PROFILE_CODEX_ACTIVE = $Name } else { Remove-Item Env:AGENT_PROFILE_CODEX_ACTIVE -ErrorAction SilentlyContinue }
    }
}

function Get-APDefaultName {
    param([string]$Provider)
    $file = Get-APDefaultFile $Provider
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "agent-profile: no default profile set for $Provider" }
    $name = (Get-Content -LiteralPath $file -Raw -ErrorAction Stop).Trim()
    if (-not $name) { throw "agent-profile: default profile file is empty for $Provider" }
    Test-APProfileName $name | Out-Null
    return $name
}

function Get-APSelectedProfile {
    param([string]$Provider)
    $name = Get-APActiveName $Provider
    if (-not $name) {
        try { $name = Get-APDefaultName $Provider } catch { return $null }
    }
    try { Test-APProfileName $name | Out-Null } catch { return $null }
    $path = Get-APProfilePath $Provider $name
    if (Test-Path -LiteralPath $path -PathType Container) { return $path }
    return $null
}

function Get-APGuiSourceDir {
    $homeDir = Get-APHome
    if ($env:AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR) {
        if (Test-Path -LiteralPath $env:AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR -PathType Container) { return $env:AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR }
        return $null
    }
    $configRoot = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $homeDir '.config' }
    $candidates = @()
    if ((Test-APWindows) -and $env:APPDATA) {
        $candidates += Join-Path $env:APPDATA 'Antigravity IDE'
        $candidates += Join-Path $env:APPDATA 'Antigravity'
    }
    $candidates += Join-Path (Join-Path $homeDir 'Library/Application Support') 'Antigravity IDE'
    $candidates += Join-Path (Join-Path $homeDir 'Library/Application Support') 'Antigravity'
    $candidates += Join-Path $configRoot 'Antigravity IDE'
    $candidates += Join-Path $configRoot 'Antigravity'
    $candidates += Join-Path $homeDir '.gemini/antigravity-ide'
    $candidates += Join-Path $homeDir '.antigravity-ide'
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
    return $null
}

function Copy-APTree {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
        # Copy-Item follows a link and copies what it points at, which cp -R does
        # not do. Left alone that would walk the profile's Library/Keychains link
        # and pull the real login keychain into the copy, and it throws outright on
        # a link whose target is gone -- Chromium's SingletonLock names a host and
        # pid rather than a real file. Reproduce the link itself instead, exactly
        # like cp -R, and skip it if this host will not create one (Windows needs
        # elevation or developer mode).
        $itemTarget = Join-Path $Destination $item.Name
        if ($item.LinkType) {
            if ($item.LinkTarget) {
                try {
                    New-Item -ItemType SymbolicLink -Path $itemTarget -Value $item.LinkTarget -Force -ErrorAction Stop | Out-Null
                } catch { }
            }
            continue
        }
        # Recurse rather than handing a directory to Copy-Item -Recurse, which
        # would dereference any link nested inside it and defeat the check above.
        if ($item.PSIsContainer) {
            Copy-APTree $item.FullName $itemTarget
            continue
        }
        Copy-Item -LiteralPath $item.FullName -Destination $itemTarget -Force -ErrorAction Stop
    }
}

# Chromium's singleton files name the host and pid that owned the source instance
# (SingletonLock -> <host>-<pid>) plus a socket under that instance's temp dir.
# Copied into a new profile they can make Antigravity decide another instance
# already owns this user-data-dir and simply focus that window, which looks exactly
# like the profile failing to switch. They are pure runtime state, so drop them
# from every snapshot. Removal is attempted unguarded because these are normally
# links rather than regular files, and a live SingletonSocket may not be either.
function Remove-APGuiLocks {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($name in @('SingletonLock', 'SingletonCookie', 'SingletonSocket')) {
        Remove-Item -LiteralPath (Join-Path $Path $name) -Force -ErrorAction SilentlyContinue
    }
}

function Copy-APLiveSnapshot {
    param([string]$Provider, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    if ($Provider -eq 'antigravity') {
        $gemini = Join-Path (Get-APHome) '.gemini'
        if (Test-Path -LiteralPath $gemini -PathType Container) { Copy-APTree $gemini (Join-Path $Destination 'home/.gemini') }
        $gui = Get-APGuiSourceDir
        if ($gui) { Copy-APTree $gui (Join-Path $Destination 'gui-user-data') }
    }
    if ($Provider -eq 'codex') {
        $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path (Get-APHome) '.codex' }
        if (Test-Path -LiteralPath $codexHome -PathType Container) { Copy-APTree $codexHome $Destination }
    }
}

function Copy-APProfile {
    param([string]$Provider, [string]$Source, [string]$Name, [switch]$Force)
    $destination = Get-APProfilePath $Provider $Name
    if (Test-Path -LiteralPath $destination) {
        if (-not $Force) { throw "agent-profile: profile '$Name' already exists (use --force to replace it)" }
    }
    $providerDir = Get-APProviderDir $Provider
    New-Item -ItemType Directory -Path $providerDir -Force | Out-Null
    $temp = "$destination.tmp.$PID"
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        if ($Source -eq 'live') {
            Copy-APLiveSnapshot $Provider $temp
        } else {
            Test-APProfileName $Source | Out-Null
            $sourcePath = Get-APProfilePath $Provider $Source
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) { throw "agent-profile: source profile '$Source' does not exist" }
            Copy-APTree $sourcePath $temp
        }
        Remove-APGuiLocks (Join-Path $temp 'gui-user-data')
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
        Move-Item -LiteralPath $temp -Destination $destination -Force
    } catch {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
    Write-Output "Copied $Provider profile to: $Name"
    if ($Source -eq 'live' -and $Provider -eq 'antigravity') { Write-Warning 'OS keyring credentials are not copied; keyring-backed login may remain shared.' }
    Write-Output "Profile directory: $destination"
}

function Resolve-APExecutable {
    param([string]$Command)
    $resolved = Get-Command -Name $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $resolved) { throw "agent-profile: executable '$Command' was not found" }
    return $resolved.Source
}

function ConvertTo-APCommandLineArgument {
    param([string]$Argument)
    if ($Argument -notmatch '[\s"]') { return $Argument }
    return '"' + ($Argument -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Start-APProcess {
    param([string]$FilePath, [string[]]$Arguments, [hashtable]$Environment)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    foreach ($key in $Environment.Keys) { $psi.EnvironmentVariables[$key] = [string]$Environment[$key] }
    $argumentListProperty = $psi.PSObject.Properties['ArgumentList']
    if ($argumentListProperty) {
        foreach ($argument in @($Arguments)) { [void]$psi.ArgumentList.Add([string]$argument) }
    } else {
        $psi.Arguments = (@($Arguments) | ForEach-Object { ConvertTo-APCommandLineArgument $_ }) -join ' '
    }
    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) { throw "agent-profile: could not start '$FilePath'" }
    $process.WaitForExit()
    return $process.ExitCode
}

function Test-APGuiDataArg {
    param([string[]]$Arguments)
    foreach ($argument in @($Arguments)) {
        if ($argument -eq '--user-data-dir' -or $argument.StartsWith('--user-data-dir=')) { return $true }
    }
    return $false
}

function Test-APNewWindowArg {
    param([string[]]$Arguments)
    foreach ($argument in @($Arguments)) {
        if ($argument -eq '--new-window') { return $true }
    }
    return $false
}

function Get-APHelp {
    @'
Usage: agent-profile <provider> <command> [args...]
       agent-profile <command> <provider> [args...]

Providers:
  antigravity  Antigravity CLI (agy) and GUI (antigravity/antigravity-ide)
  codex        OpenAI Codex CLI

Commands:
  create <provider> <name>                  Create an empty profile
  copy <provider> <name> [--force]          Copy current live data
  copy <provider> <source> <name> [--force] Copy a managed profile
  list <provider>                           List profiles
  default <provider> [name]                 Get or set the default
  use <provider> <name>                     Select a profile for this shell
  which <provider> [name]                   Print a profile directory
  restart <provider> [args...]              Open a fresh Antigravity GUI window
  delete <provider> <name> [--force]        Delete a profile

Examples:
  agent-profile copy antigravity hafez
  agent-profile copy antigravity default hafez
  agent-profile default antigravity hafez
'@ | Write-Output
}

function agent-profile {
    $inputArgs = @($args)
    if ($inputArgs.Count -eq 0 -or $inputArgs[0] -in @('help', '-h', '--help')) { Get-APHelp; return }
    $commands = @('create', 'copy', 'list', 'ls', 'default', 'use', 'which', 'restart', 'delete', 'status')
    if ($inputArgs[0] -in $commands) {
        $command = $inputArgs[0]
        if ($inputArgs.Count -lt 2) { throw 'agent-profile: missing provider' }
        $provider = Get-APProvider $inputArgs[1]
        $start = 2
    } else {
        $provider = Get-APProvider $inputArgs[0]
        $command = if ($inputArgs.Count -ge 2) { $inputArgs[1] } else { 'status' }
        $start = 2
    }
    $commandArgs = @()
    if ($start -lt $inputArgs.Count) { $commandArgs = @($inputArgs[$start..($inputArgs.Count - 1)]) }

    switch ($command) {
        'status' {
            $default = $null
            try { $default = Get-APDefaultName $provider } catch {}
            $active = Get-APActiveName $provider
            $selected = Get-APSelectedProfile $provider
            Write-Output "Provider: $provider"
            Write-Output "Default: $(if ($default) { $default } else { '<none>' })"
            Write-Output "Active: $(if ($active) { $active } else { '<default>' })"
            if ($selected) { Write-Output "Path: $selected" }
        }
        'create' {
            if ($commandArgs.Count -ne 1) { throw "agent-profile: usage: agent-profile create $provider <name>" }
            $path = Get-APProfilePath $provider $commandArgs[0]
            if (Test-Path -LiteralPath $path) { throw "agent-profile: profile '$($commandArgs[0])' already exists" }
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Output "Created $provider profile: $($commandArgs[0])"
            Write-Output "Profile directory: $path"
        }
        'copy' {
            $force = $false
            $copyArgs = @($commandArgs | Where-Object { $_ -ne '--force' })
            if ($commandArgs -contains '--force') { $force = $true }
            if ($copyArgs.Count -eq 1) { $source = 'live'; $name = $copyArgs[0] }
            elseif ($copyArgs.Count -eq 2) { $source = $copyArgs[0]; $name = $copyArgs[1]; if ($source -eq 'default') { $source = Get-APDefaultName $provider } }
            else { throw "agent-profile: usage: agent-profile copy $provider [source] <name> [--force]" }
            Copy-APProfile $provider $source $name -Force:$force
        }
        'list' { if ($commandArgs.Count -ne 0) { throw "agent-profile: usage: agent-profile list $provider" }; $root = Get-APProviderDir $provider; if (-not (Test-Path -LiteralPath $root)) { Write-Output "No $provider profiles found. Create one with: agent-profile create $provider <name>"; return }; $default = $null; try { $default = Get-APDefaultName $provider } catch {}; $active = Get-APActiveName $provider; $profiles = @(Get-ChildItem -LiteralPath $root -Directory -Force); if ($profiles.Count -eq 0) { Write-Output "No $provider profiles found. Create one with: agent-profile create $provider <name>"; return }; foreach ($profile in $profiles) { $status = if ($profile.Name -eq $default -and $profile.Name -eq $active) { ' (default, active)' } elseif ($profile.Name -eq $default) { ' (default)' } elseif ($profile.Name -eq $active) { ' (active)' } else { '' }; Write-Output "   $($profile.Name)$status" } }
        'ls' { agent-profile list $provider @commandArgs }
        'default' { if ($commandArgs.Count -eq 0) { Get-APDefaultName $provider; return }; if ($commandArgs.Count -ne 1) { throw "agent-profile: usage: agent-profile default $provider [name]" }; $path = Get-APProfilePath $provider $commandArgs[0]; if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "agent-profile: profile '$($commandArgs[0])' does not exist" }; $root = Get-APProviderDir $provider; New-Item -ItemType Directory -Path $root -Force | Out-Null; Set-Content -LiteralPath (Join-Path $root '.default') -Value $commandArgs[0]; Write-Output "Default $provider profile set to: $($commandArgs[0])" }
        'use' { if ($commandArgs.Count -ne 1) { throw "agent-profile: usage: agent-profile use $provider <name>" }; $path = Get-APProfilePath $provider $commandArgs[0]; if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "agent-profile: profile '$($commandArgs[0])' does not exist" }; Set-APActiveName $provider $commandArgs[0]; Write-Output "Switched to $provider profile: $($commandArgs[0])" }
        'which' { if ($commandArgs.Count -gt 1) { throw "agent-profile: usage: agent-profile which $provider [name]" }; if ($commandArgs.Count -eq 1) { $path = Get-APProfilePath $provider $commandArgs[0]; if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "agent-profile: profile '$($commandArgs[0])' does not exist" } } else { $path = Get-APSelectedProfile $provider; if (-not $path) { throw "agent-profile: no active or default profile set for $provider" } }; Write-Output $path }
        'restart' { if ($provider -ne 'antigravity') { throw 'agent-profile: restart is only supported for antigravity' }; Invoke-APGuiRestart $commandArgs | Out-Null }
        'delete' { $deleteForce = $commandArgs -contains '--force'; $names = @($commandArgs | Where-Object { $_ -ne '--force' }); if ($names.Count -ne 1) { throw "agent-profile: usage: agent-profile delete $provider <name> [--force]" }; $path = Get-APProfilePath $provider $names[0]; if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "agent-profile: profile '$($names[0])' does not exist" }; if (-not $deleteForce) { $answer = Read-Host "Delete $provider profile '$($names[0])' and all its data? [y/N]"; if ($answer -notmatch '^(?i:y|yes)$') { Write-Output 'Cancelled.'; return } }; Remove-Item -LiteralPath $path -Recurse -Force; $root = Get-APProviderDir $provider; if ((Test-Path -LiteralPath (Join-Path $root '.default')) -and (Get-APDefaultName $provider) -eq $names[0]) { Remove-Item -LiteralPath (Join-Path $root '.default') -Force }; if ((Get-APActiveName $provider) -eq $names[0]) { Set-APActiveName $provider '' }; Write-Output "Deleted $provider profile: $($names[0])" }
        default { throw "agent-profile: unknown command '$command'. Run 'agent-profile help' for usage." }
    }
}

function agy {
    $command = if ($env:AGENT_PROFILE_AGY_COMMAND) { $env:AGENT_PROFILE_AGY_COMMAND } else { 'agy' }
    $profile = Get-APSelectedProfile 'antigravity'
    $environment = @{}
    if ($profile) {
        $childHome = Join-Path $profile 'home'
        New-Item -ItemType Directory -Path $childHome -Force | Out-Null
        Add-APMacOSKeychainLink $childHome
        $environment['HOME'] = $childHome
        if (Test-APWindows) { $environment['USERPROFILE'] = $childHome }
    }
    return (Start-APProcess (Resolve-APExecutable $command) @($args) $environment)
}

# HOME (USERPROFILE on Windows) is the knob that actually switches profiles:
# Antigravity resolves its real state -- account, credentials, conversations --
# from os.homedir()/.gemini, so a run that only overrides --user-data-dir keeps
# loading the original profile. Node reads USERPROFILE for os.homedir() on
# Windows and HOME elsewhere, so both are set for the child, exactly as agy does.
# --user-data-dir is still passed because it moves Chromium's own user data --
# most importantly the singleton lock -- which is what lets two profiles run at
# the same time.
function Invoke-APGui {
    param([string[]]$Arguments)
    $command = if ($env:AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND) { $env:AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND } else { $null }
    if (-not $command) {
        $commandInfo = Get-Command antigravity-ide -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $commandInfo) { $commandInfo = Get-Command antigravity -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if (-not $commandInfo) { throw 'agent-profile: could not find antigravity GUI; set AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND' }
        $command = $commandInfo.Source
    }
    $profile = Get-APSelectedProfile 'antigravity'
    $finalArgs = @($Arguments)
    $environment = @{}
    if ($profile) {
        $childHome = Join-Path $profile 'home'
        $guiDataDir = Join-Path $profile 'gui-user-data'
        New-Item -ItemType Directory -Path $childHome -Force | Out-Null
        New-Item -ItemType Directory -Path $guiDataDir -Force | Out-Null
        Add-APMacOSKeychainLink $childHome
        $environment['HOME'] = $childHome
        if (Test-APWindows) { $environment['USERPROFILE'] = $childHome }
        # The "=" form is required: the Antigravity app is a plain Electron app whose
        # Chromium parser only understands --switch=value and silently ignores the
        # space-separated spelling. A VS Code derived antigravity-ide accepts it too.
        if (-not (Test-APGuiDataArg $finalArgs)) { $finalArgs = @("--user-data-dir=$guiDataDir") + $finalArgs }
    }
    return (Start-APProcess (Resolve-APExecutable $command) $finalArgs $environment)
}

# --new-window is a VS Code flag and is inert for the plain Electron app bundle;
# there a separate HOME plus a separate user-data-dir is what opens another
# profile alongside the running one. This adapter only ever launches a PATH
# executable -- Resolve-APExecutable rejects a macOS .app directory and no bundle
# discovery exists here -- so the flag is always the real new-window mechanism.
function Invoke-APGuiRestart {
    param([string[]]$Arguments)
    $finalArgs = @($Arguments)
    if (-not (Test-APNewWindowArg $finalArgs)) { $finalArgs = @('--new-window') + $finalArgs }
    return (Invoke-APGui $finalArgs)
}

function antigravity { return (Invoke-APGui @($args)) }
function antigravity-ide { return (Invoke-APGui @($args)) }
function codex {
    $command = if ($env:AGENT_PROFILE_CODEX_COMMAND) { $env:AGENT_PROFILE_CODEX_COMMAND } else { 'codex' }
    $profile = Get-APSelectedProfile 'codex'
    $environment = @{}
    if ($profile) { $environment['CODEX_HOME'] = $profile }
    return (Start-APProcess (Resolve-APExecutable $command) @($args) $environment)
}

function agy-profile { agent-profile antigravity @args }
function antigravity-profile { agent-profile antigravity @args }
function codex-profile { agent-profile codex @args }
