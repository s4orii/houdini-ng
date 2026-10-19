[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]{2,5}$')][string]$Serial,
    [ValidateSet('Inspect','Install','Verify','Rollback')][string]$Action = 'Inspect',
    [string]$StateRoot = (Join-Path $PSScriptRoot 'state')
)

$ErrorActionPreference = 'Stop'
$KnownAbiScriptHash = '7f6776bea6d53d789ab5ff38b3f2a515e2b007403d07f35d270daab6a215f8f8'
$KnownAbiRcHash = '47d88b5d5ef2e2f0523bb933cd1553c9fddbea4144ccaf82923c0465ffca276b'
$Manifest = Join-Path $PSScriptRoot 'manifest/payload-arm32.sha256'
$DeviceDir = Join-Path $PSScriptRoot 'device'
$SafeSerial = $Serial.Replace(':','_').Replace('.','_')
$RunState = Join-Path ([IO.Path]::GetFullPath($StateRoot)) $SafeSerial
$HostJournal = Join-Path $RunState 'journal.json'

function Invoke-Adb {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "adb failed ($LASTEXITCODE): $($output -join "`n")" }
    return ($output -join "`n").Trim()
}

function Get-RemoteHash([string]$FixedPath) {
    $line = Invoke-Adb -Arguments @('shell','sha256sum',$FixedPath)
    return ($line -split '\s+')[0].ToLowerInvariant()
}

function Assert-Target {
    $state = (& adb -s $Serial get-state 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { throw "Target is not ready: $Serial ($state)" }
    if ((Invoke-Adb -Arguments @('shell','id','-u')) -ne '0') { throw 'Genymotion root shell is required.' }
    if ((Invoke-Adb -Arguments @('shell','getprop','ro.build.version.sdk')) -ne '30') { throw 'Only Android 11/API 30 is supported.' }
    if ((Invoke-Adb -Arguments @('shell','getprop','ro.product.device')) -ne 'vbox86p') { throw 'Target is not the expected Genymotion vbox86p image.' }
    if ((Get-RemoteHash '/vendor/bin/init.genymotion.abi.sh') -ne $KnownAbiScriptHash) { throw 'Unknown Genymotion ABI initializer; refusing mutation.' }
    if ((Get-RemoteHash '/vendor/etc/init/hw/init.vbox86.rc') -ne $KnownAbiRcHash) { throw 'Unknown Genymotion init RC; refusing mutation.' }
}

function Test-LocalManifest {
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw 'Generate manifest/payload-arm32.sha256 first.' }
    $count = 0
    foreach ($line in Get-Content -LiteralPath $Manifest) {
        if ($line -notmatch '^([0-9a-f]{64})  (system/(?:lib/libhoudini\.so|bin/arm/linker|lib/arm/[A-Za-z0-9._/+@-]+))$') { throw "Invalid manifest line: $line" }
        $relative = $Matches[2]
        $local = Join-Path $PSScriptRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if ((Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Matches[1]) { throw "Local hash mismatch: $relative" }
        $count++
    }
    if ($count -lt 300) { throw "Manifest count is unexpectedly low: $count" }
    return $count
}

function Write-HostJournal([string]$Phase) {
    New-Item -ItemType Directory -Force -Path $RunState | Out-Null
    $record = [ordered]@{
        schema = 1; serial = $Serial; phase = $Phase
        manifestSha256 = (Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash.ToLowerInvariant()
        updatedUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($HostJournal, ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

function Wait-Android {
    & adb -s $Serial wait-for-device | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        if ((Invoke-Adb -Arguments @('shell','getprop','sys.boot_completed')) -eq '1') { return }
        Start-Sleep -Seconds 2
    }
    throw 'Android did not complete boot within 60 seconds.'
}

function Invoke-Inspect {
    Assert-Target
    [pscustomobject]@{
        serial = $Serial
        api = Invoke-Adb -Arguments @('shell','getprop','ro.build.version.sdk')
        abiList = Invoke-Adb -Arguments @('shell','getprop','ro.product.cpu.abilist')
        nativeBridge = Invoke-Adb -Arguments @('shell','getprop','ro.dalvik.vm.native.bridge')
        rootMount = Invoke-Adb -Arguments @('shell','mount')
        abiInitializerSha256 = Get-RemoteHash '/vendor/bin/init.genymotion.abi.sh'
    }
}

$null = Get-Command adb -ErrorAction Stop
$null = Test-LocalManifest

switch ($Action) {
    'Inspect' { Invoke-Inspect | ConvertTo-Json -Depth 3; break }
    'Install' {
        Assert-Target
        if (Test-Path -LiteralPath $HostJournal) {
            $existing = Get-Content -Raw -LiteralPath $HostJournal | ConvertFrom-Json
            $manifestHash = (Get-FileHash -LiteralPath $Manifest -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($existing.serial -eq $Serial -and $existing.phase -eq 'verified' -and $existing.manifestSha256 -eq $manifestHash) {
                $verified = Invoke-Adb -Arguments @('shell','/data/local/tmp/houdini-nextgen/verify-arm32.sh')
                [pscustomobject]@{ apply = 'already_compliant_managed'; verify = ($verified -split "`n")[-1]; serial = $Serial } | ConvertTo-Json
                break
            }
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot 'dist') | Out-Null
        $archive = Join-Path $PSScriptRoot 'dist/payload-arm32.tar'
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
        & tar -cf $archive -C $PSScriptRoot system/lib/libhoudini.so system/bin/arm/linker system/lib/arm
        if ($LASTEXITCODE -ne 0) { throw 'Unable to build ARM32 staging archive.' }
        Write-HostJournal 'staging'
        Invoke-Adb -Arguments @('shell','mkdir','-p','/data/local/tmp/houdini-nextgen') | Out-Null
        Invoke-Adb -Arguments @('push',$archive,'/data/local/tmp/houdini-nextgen/payload-arm32.tar') | Out-Null
        Invoke-Adb -Arguments @('push',$Manifest,'/data/local/tmp/houdini-nextgen/payload-arm32.sha256') | Out-Null
        Invoke-Adb -Arguments @('push',(Join-Path $DeviceDir 'apply-arm32.sh'),'/data/local/tmp/houdini-nextgen/apply-arm32.sh') | Out-Null
        Invoke-Adb -Arguments @('push',(Join-Path $DeviceDir 'verify-arm32.sh'),'/data/local/tmp/houdini-nextgen/verify-arm32.sh') | Out-Null
        Invoke-Adb -Arguments @('push',(Join-Path $DeviceDir 'rollback-arm32.sh'),'/data/local/tmp/houdini-nextgen/rollback-arm32.sh') | Out-Null
        Invoke-Adb -Arguments @('shell','chmod','0755','/data/local/tmp/houdini-nextgen/apply-arm32.sh','/data/local/tmp/houdini-nextgen/verify-arm32.sh','/data/local/tmp/houdini-nextgen/rollback-arm32.sh') | Out-Null
        $apply = Invoke-Adb -Arguments @('shell','/data/local/tmp/houdini-nextgen/apply-arm32.sh')
        Write-HostJournal 'verify_pending'
        Invoke-Adb -Arguments @('reboot') | Out-Null
        Wait-Android
        $verify = Invoke-Adb -Arguments @('shell','/data/local/tmp/houdini-nextgen/verify-arm32.sh')
        Write-HostJournal 'verified'
        [pscustomobject]@{ apply = $apply; verify = ($verify -split "`n")[-1]; serial = $Serial } | ConvertTo-Json
        break
    }
    'Verify' {
        Assert-Target
        if (-not (Test-Path -LiteralPath $HostJournal)) { throw 'Host ownership journal is missing; state is unmanaged.' }
        $journal = Get-Content -Raw -LiteralPath $HostJournal | ConvertFrom-Json
        if ($journal.serial -ne $Serial) { throw 'Host journal belongs to another device.' }
        Invoke-Adb -Arguments @('shell','/data/local/tmp/houdini-nextgen/verify-arm32.sh')
        break
    }
    'Rollback' {
        Assert-Target
        if (-not (Test-Path -LiteralPath $HostJournal)) { throw 'Refusing rollback without host ownership journal.' }
        Invoke-Adb -Arguments @('shell','/data/local/tmp/houdini-nextgen/rollback-arm32.sh')
        Write-HostJournal 'rolled_back'
        break
    }
}
