$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "agent-profile-test-$PID"
$homeDir = Join-Path $testRoot 'home'
$dataDir = Join-Path $testRoot 'data'
$guiSource = Join-Path $testRoot 'gui-source'

$agyHomeDir = Join-Path (Join-Path $homeDir '.gemini') 'antigravity-cli'
New-Item -ItemType Directory -Path $homeDir, $dataDir, $agyHomeDir, (Join-Path $guiSource 'User') -Force | Out-Null
# Captured before HOME is redirected into the sandbox: the macOS keychain tests
# need the caller's real login keychain directory, which is the thing the adapter
# links into a profile home.
$realHome = if ($env:HOME) { $env:HOME } else { $HOME }
$realKeychains = Join-Path (Join-Path $realHome 'Library') 'Keychains'

$env:HOME = $homeDir
$env:USERPROFILE = $homeDir
$env:XDG_DATA_HOME = $dataDir
$env:AGENT_PROFILE_DATA_DIR = Join-Path $dataDir 'agent-profiles'
$env:AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR = $guiSource

# Keep inherited session state from affecting the assertions.
Remove-Item Env:AGENT_PROFILE_ANTIGRAVITY_ACTIVE -ErrorAction SilentlyContinue
Remove-Item Env:AGENT_PROFILE_CODEX_ACTIVE -ErrorAction SilentlyContinue

try {
    . (Join-Path $scriptRoot 'agent-profile-init.ps1')

    $script:assertionCount = 0
    function Assert-True([bool]$Condition, [string]$Message) {
        $script:assertionCount++
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }

    Set-Content -LiteralPath (Join-Path $agyHomeDir 'token') -Value 'oauth-token'
    Set-Content -LiteralPath (Join-Path (Join-Path $guiSource 'User') 'settings.json') -Value 'gui-settings'
    agent-profile copy antigravity hafez | Out-Null
    $hafezDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'hafez'
    Assert-True (Test-Path (Join-Path (Join-Path (Join-Path (Join-Path $hafezDir 'home') '.gemini') 'antigravity-cli') 'token')) 'copies live Antigravity CLI data'
    Assert-True (Test-Path (Join-Path (Join-Path (Join-Path $hafezDir 'gui-user-data') 'User') 'settings.json')) 'copies live GUI data'

    # Chromium's singleton entries name the host and pid of the instance that
    # owned the source directory. Copied into a profile they make Antigravity
    # focus the original window instead of opening the new profile, so a snapshot
    # must drop them -- and getting there must survive SingletonLock, whose
    # target deliberately does not exist.
    $singletonNames = @('SingletonLock', 'SingletonCookie', 'SingletonSocket')
    if (Test-APWindows) {
        # Symlinks need elevation or developer mode on Windows; plain files still
        # cover the prune itself.
        foreach ($name in $singletonNames) { Set-Content -LiteralPath (Join-Path $guiSource $name) -Value 'lock' }
    } else {
        # SingletonLock dangles by design, which is what used to abort the whole
        # copy: Copy-Item copies a link by value and cannot read a missing target.
        New-Item -ItemType SymbolicLink -Path (Join-Path $guiSource 'SingletonLock') -Value 'MacBook-Pro.local-77770' | Out-Null
        # The other two resolve, so the copy really does reproduce them into the
        # snapshot and the prune really does have to take them back out.
        Set-Content -LiteralPath (Join-Path $testRoot 'singleton-socket-target') -Value 'socket'
        Set-Content -LiteralPath (Join-Path $guiSource 'SingletonCookie') -Value '17350445988078770481'
        New-Item -ItemType SymbolicLink -Path (Join-Path $guiSource 'SingletonSocket') -Value (Join-Path $testRoot 'singleton-socket-target') | Out-Null
    }
    agent-profile copy antigravity locked | Out-Null
    $lockedGuiDir = Join-Path (Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'locked') 'gui-user-data'
    Assert-True (Test-Path (Join-Path (Join-Path $lockedGuiDir 'User') 'settings.json')) 'snapshots GUI data past a dangling singleton link'
    $leftoverLocks = @(Get-ChildItem -LiteralPath $lockedGuiDir -Force | Where-Object { $singletonNames -contains $_.Name })
    Assert-True ($leftoverLocks.Count -eq 0) 'prunes the Chromium singleton locks from a snapshot'

    agent-profile create antigravity work | Out-Null
    $workDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'work'
    Set-Content -LiteralPath (Join-Path $workDir 'marker') -Value 'work'
    agent-profile default antigravity work | Out-Null
    agent-profile copy antigravity default copied | Out-Null
    $copiedDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'copied'
    Assert-True ((Get-Content (Join-Path $copiedDir 'marker') -Raw).Trim() -eq 'work') 'copies from the persisted default'
    Assert-True ((agent-profile which antigravity copied) -like '*antigravity*copied') 'resolves a named profile'

    # The seam is Start-APProcess rather than Invoke-APGui: Invoke-APGui is the
    # function that builds the launch, so stubbing it would assert nothing about
    # the flag spelling or the child environment. Start-APProcess receives both
    # the finished argv and the environment handed to the GUI process.
    $guiStub = if (Test-APWindows) { Join-Path $testRoot 'antigravity-stub.cmd' } else { Join-Path $testRoot 'antigravity-stub' }
    if (Test-APWindows) {
        Set-Content -LiteralPath $guiStub -Value '@echo off'
    } else {
        Set-Content -LiteralPath $guiStub -Value "#!/bin/sh`nexit 0"
        & /bin/chmod '+x' $guiStub
    }
    $env:AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND = $guiStub

    $script:capturedGuiArgs = @()
    $script:capturedGuiEnvironment = @{}
    function Start-APProcess {
        param([string]$FilePath, [string[]]$Arguments, [hashtable]$Environment)
        $script:capturedGuiArgs = @($Arguments)
        $script:capturedGuiEnvironment = $Environment
        return 0
    }

    agent-profile use antigravity copied | Out-Null
    $copiedHome = Join-Path $copiedDir 'home'
    $copiedGuiData = Join-Path $copiedDir 'gui-user-data'

    antigravity | Out-Null
    # The "=" spelling is mandatory: the Antigravity app is a plain Electron app
    # whose Chromium parser silently ignores the space-separated form, which is
    # how the profile switch used to be a no-op.
    Assert-True ($script:capturedGuiArgs -contains "--user-data-dir=$copiedGuiData") 'GUI launch injects the equals-form --user-data-dir'
    # HOME is the knob that actually selects the Antigravity account: the app
    # resolves its real state from os.homedir()/.gemini.
    Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $copiedHome) 'GUI launch puts the profile HOME in the child environment'
    if (Test-APWindows) {
        Assert-True ($script:capturedGuiEnvironment['USERPROFILE'] -eq $copiedHome) 'GUI launch also sets USERPROFILE on Windows'
    }
    # The launch also has to create both directories it points the GUI at.
    Assert-True (Test-Path -LiteralPath $copiedHome -PathType Container) 'GUI launch creates the profile home directory'
    Assert-True (Test-Path -LiteralPath $copiedGuiData -PathType Container) 'GUI launch creates the profile GUI data directory'

    agent-profile restart antigravity | Out-Null
    Assert-True ($script:capturedGuiArgs -contains '--new-window') 'restart requests a fresh GUI window'
    Assert-True ($script:capturedGuiArgs -contains "--user-data-dir=$copiedGuiData") 'restart keeps the equals-form --user-data-dir'
    Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $copiedHome) 'restart puts the profile HOME in the child environment'

    # The agy CLI shares the same child-HOME mechanism, and both shell suites
    # assert it, so cover it here too now that the seam exposes the environment.
    $env:AGENT_PROFILE_AGY_COMMAND = $guiStub
    agy | Out-Null
    Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $copiedHome) 'agy puts the profile HOME in the child environment'
    if (Test-APWindows) {
        Assert-True ($script:capturedGuiEnvironment['USERPROFILE'] -eq $copiedHome) 'agy also sets USERPROFILE on Windows'
    }

    # An explicit --user-data-dir wins: no flag is injected, but HOME still is.
    antigravity --user-data-dir /tmp/custom-gui | Out-Null
    $injected = @($script:capturedGuiArgs | Where-Object { $_ -like '--user-data-dir=*' })
    Assert-True ($injected.Count -eq 0) 'a user supplied --user-data-dir suppresses the injected one'
    Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $copiedHome) 'a user supplied --user-data-dir still gets the profile HOME'

    $overwriteFailed = $false
    try { agent-profile copy antigravity work copied | Out-Null } catch { $overwriteFailed = $true }
    Assert-True $overwriteFailed 'refuses overwrite without --force'

    # With no profile selected the wrapper must stay transparent: no injected
    # flag and no child environment at all.
    Remove-Item Env:AGENT_PROFILE_ANTIGRAVITY_ACTIVE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') '.default') -Force
    antigravity --foo | Out-Null
    Assert-True ((@($script:capturedGuiArgs) -join ' ') -eq '--foo') 'an unselected provider passes argv through untouched'
    Assert-True ($script:capturedGuiEnvironment.Count -eq 0) 'an unselected provider sets no child environment'

    # macOS resolves the default login keychain at $HOME/Library/Keychains, so the
    # redirected HOME that switches the Antigravity profile also leaves the child
    # with no keychain at all and Chromium stops on "A keychain cannot be found to
    # store 'antigravity'". Both launch paths have to link the real keychain
    # directory into the profile home. macOS only, exactly like the adapter, so
    # skip cleanly elsewhere.
    if ((Test-APMacOS) -and (Test-Path -LiteralPath $realKeychains -PathType Container)) {
        # The adapter links whatever <real home>/Library/Keychains it finds, and
        # this suite redirected HOME into the sandbox -- so point the sandbox
        # home's keychain directory at the caller's real one. macOS resolves the
        # login keychain through both hops, which keeps the security(1) assertion
        # honest without this test ever creating or writing anything inside the
        # real keychain directory.
        $sandboxLibrary = Join-Path $homeDir 'Library'
        New-Item -ItemType Directory -Path $sandboxLibrary -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $sandboxLibrary 'Keychains') -Value $realKeychains | Out-Null

        function Get-APKeychainPath([string]$ProfileHome) {
            return (Join-Path (Join-Path $ProfileHome 'Library') 'Keychains')
        }
        # stat -L follows the link, so device+inode identifies the directory the
        # link really lands on rather than the path it happens to spell.
        function Test-APKeychainLink([string]$ProfileHome) {
            $link = Get-APKeychainPath $ProfileHome
            $entry = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
            if (-not $entry -or $entry.LinkType -ne 'SymbolicLink') { return $false }
            if (-not (Test-Path -LiteralPath $link -PathType Container)) { return $false }
            $linkedId = (& /usr/bin/stat -L -f '%d:%i' $link)
            $realId = (& /usr/bin/stat -L -f '%d:%i' $realKeychains)
            return ($realId -and $linkedId -eq $realId)
        }
        # PowerShell 7.3+ can turn a non-zero native exit into a terminating error
        # when $ErrorActionPreference is Stop, and observing that failure is the
        # whole point of the baseline probe, so it is relaxed for the call itself.
        function Invoke-APDefaultKeychain([string]$KeychainHome) {
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $output = (& /usr/bin/env "HOME=$KeychainHome" /usr/bin/security default-keychain 2>&1 | Out-String)
                return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
            } finally { $ErrorActionPreference = $previousPreference }
        }

        $antigravityDir = Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity'

        agent-profile create antigravity keychain-gui | Out-Null
        agent-profile use antigravity keychain-gui | Out-Null
        $keychainGuiHome = Join-Path (Join-Path $antigravityDir 'keychain-gui') 'home'
        # Guard the premise: the link must be the launch's doing, not create's.
        Assert-True (-not (Get-Item -LiteralPath (Get-APKeychainPath $keychainGuiHome) -Force -ErrorAction SilentlyContinue)) 'a fresh profile has no keychain entry before a launch'
        antigravity | Out-Null
        Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $keychainGuiHome) 'the keychain-linking GUI launch is the one that redirects HOME'
        Assert-True (Test-APKeychainLink $keychainGuiHome) 'GUI launch links the macOS login keychain into the profile home'

        # The agy CLI redirects HOME through its own code path, so it loses the
        # keychain for the same reason and has to link it back the same way.
        agent-profile create antigravity keychain-cli | Out-Null
        agent-profile use antigravity keychain-cli | Out-Null
        $keychainCliHome = Join-Path (Join-Path $antigravityDir 'keychain-cli') 'home'
        Assert-True (-not (Get-Item -LiteralPath (Get-APKeychainPath $keychainCliHome) -Force -ErrorAction SilentlyContinue)) 'a fresh profile has no keychain entry before an agy launch'
        agy | Out-Null
        Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $keychainCliHome) 'the keychain-linking agy launch is the one that redirects HOME'
        Assert-True (Test-APKeychainLink $keychainCliHome) 'agy launch links the macOS login keychain into the profile home'

        # Whatever the user already put at <profile>/home/Library/Keychains wins:
        # a real directory is never replaced by a link.
        agent-profile create antigravity keychain-keep | Out-Null
        $keychainKeepHome = Join-Path (Join-Path $antigravityDir 'keychain-keep') 'home'
        $keptKeychains = Get-APKeychainPath $keychainKeepHome
        New-Item -ItemType Directory -Path $keptKeychains -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $keptKeychains 'marker') -Value 'do-not-clobber'
        agent-profile use antigravity keychain-keep | Out-Null
        antigravity | Out-Null
        $keptEntry = Get-Item -LiteralPath $keptKeychains -Force
        Assert-True ($keptEntry.LinkType -ne 'SymbolicLink') 'an existing keychain directory is not replaced by a link'
        Assert-True ((Get-Content (Join-Path $keptKeychains 'marker') -Raw).Trim() -eq 'do-not-clobber') 'an existing keychain directory keeps its contents'

        # ...and a link the user made is never retargeted, including a dangling
        # one, which a plain Test-Path would report as absent.
        agent-profile create antigravity keychain-dangle | Out-Null
        $keychainDangleHome = Join-Path (Join-Path $antigravityDir 'keychain-dangle') 'home'
        $dangleTarget = Join-Path $testRoot 'no-such-keychain-dir'
        New-Item -ItemType Directory -Path (Join-Path $keychainDangleHome 'Library') -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path (Get-APKeychainPath $keychainDangleHome) -Value $dangleTarget | Out-Null
        agent-profile use antigravity keychain-dangle | Out-Null
        antigravity | Out-Null
        $dangleEntry = Get-Item -LiteralPath (Get-APKeychainPath $keychainDangleHome) -Force
        Assert-True ($dangleEntry.Target -eq $dangleTarget) 'a dangling keychain link the user made is left alone'

        # The assertion that ties this to the reported bug. security(1) resolves
        # the default keychain exactly the way the GUI does, so run the real one:
        # without the link a redirected HOME has no default keychain at all, and
        # with the link the launch created it finds the login keychain again.
        $bareHome = Join-Path $testRoot 'keychainless-home'
        New-Item -ItemType Directory -Path $bareHome -Force | Out-Null
        $bareProbe = Invoke-APDefaultKeychain $bareHome
        Assert-True ($bareProbe.ExitCode -ne 0) 'security(1) fails under a profile home with no keychain link'
        Assert-True ($bareProbe.Output -match 'A default keychain could not be found') 'the unlinked failure is the one users reported'

        agent-profile create antigravity keychain-security | Out-Null
        agent-profile use antigravity keychain-security | Out-Null
        $keychainSecurityHome = Join-Path (Join-Path $antigravityDir 'keychain-security') 'home'
        antigravity | Out-Null
        Assert-True (Test-APKeychainLink $keychainSecurityHome) 'the security probe runs against a profile home the launch linked'
        $linkedProbe = Invoke-APDefaultKeychain $keychainSecurityHome
        Assert-True ($linkedProbe.ExitCode -eq 0) 'security(1) resolves a default keychain through the link the launch created'
        Assert-True ($linkedProbe.Output -match 'login\.keychain') 'the resolved default keychain is the real login keychain'

        # Copy-Item follows a link and copies what it points at, so once a profile
        # holds a keychain link, copying that profile would pull the real login
        # keychain into the copy. The tree copy has to reproduce the link instead.
        agent-profile copy antigravity keychain-security keychain-copied | Out-Null
        $copiedKeychainHome = Join-Path (Join-Path $antigravityDir 'keychain-copied') 'home'
        $copiedKeychainEntry = Get-Item -LiteralPath (Get-APKeychainPath $copiedKeychainHome) -Force -ErrorAction SilentlyContinue
        Assert-True ($null -ne $copiedKeychainEntry -and $copiedKeychainEntry.LinkType -eq 'SymbolicLink') 'copying a profile reproduces the keychain link instead of following it'
        $copiedKeychainFiles = @(Get-ChildItem -LiteralPath (Join-Path $antigravityDir 'keychain-copied') -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.keychain-db' })
        Assert-True ($copiedKeychainFiles.Count -eq 0) 'copying a profile never writes real keychain files into it'
    } else {
        Write-Output 'skipped: macOS keychain link assertions (not macOS, or no login keychain directory)'
    }

    Write-Output "$script:assertionCount assertions passed, 0 failed"
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
