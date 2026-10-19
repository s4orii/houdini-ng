[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $failures.Add($Message) }
}

$manifestPath = Join-Path $root 'manifest/payload-arm32.sha256'
Assert-True (Test-Path -LiteralPath $manifestPath) 'Manifest is missing.'
if (Test-Path -LiteralPath $manifestPath) {
    $lines = Get-Content -LiteralPath $manifestPath
    Assert-True ($lines.Count -ge 300) "Manifest contains too few files: $($lines.Count)"
    Assert-True (($lines | Where-Object { $_ -match 'system/bin/houdini(?:64)?$|system/lib64/|system/bin/arm64/' }).Count -eq 0) 'Manifest includes forbidden ARM64/direct-exec paths.'
    Assert-True (($lines | Where-Object { $_ -match 'build\.prop$' }).Count -eq 0) 'Manifest includes a property file.'
    Assert-True (($lines | Where-Object { $_ -notmatch '^[0-9a-f]{64}  system/(lib/libhoudini\.so|bin/arm/linker|lib/arm/[A-Za-z0-9._/+@-]+)$' }).Count -eq 0) 'Manifest contains an invalid line.'
}

$generator = Join-Path $root 'tools/New-Arm32Manifest.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("houdini-manifest-{0}.sha256" -f [guid]::NewGuid())
try {
    & $generator -RepositoryRoot $root -OutputPath $temporary | Out-Null
    Assert-True ((Get-FileHash $manifestPath).Hash -eq (Get-FileHash $temporary).Hash) 'Manifest generation is not deterministic.'
} finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
}

$installer = Join-Path $root 'Install-Houdini.ps1'
$tokens = $null; $parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True ($parseErrors.Count -eq 0) ("Installer has PowerShell parse errors: " + ($parseErrors.Message -join '; '))

foreach ($scriptName in 'apply-arm32.sh','verify-arm32.sh','rollback-arm32.sh') {
    $content = Get-Content -Raw -LiteralPath (Join-Path $root "device/$scriptName")
    Assert-True ($content.Contains('set -eu')) "$scriptName is not fail-closed."
    Assert-True (-not $content.Contains('build.prop')) "$scriptName edits build.prop."
}

$apply = Get-Content -Raw -LiteralPath (Join-Path $root 'device/apply-arm32.sh')
Assert-True ($apply.Contains('mount -o remount,ro /')) 'Apply script does not remount root read-only.'
Assert-True ($apply.Contains('unmanaged collision')) 'Apply script does not reject collisions.'
$rollback = Get-Content -Raw -LiteralPath (Join-Path $root 'device/rollback-arm32.sh')
Assert-True ($rollback.Contains('rollback drift')) 'Rollback does not stop on drift.'

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host "PASS: $($lines.Count) payload entries; manifest deterministic; installer/scripts satisfy static safety checks."
