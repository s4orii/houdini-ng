[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'manifest/payload-arm32.sha256')
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepositoryRoot)
$selected = @(
    'system/lib/libhoudini.so',
    'system/bin/arm/linker'
)
$selected += Get-ChildItem -LiteralPath (Join-Path $root 'system/lib/arm') -File -Recurse |
    ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') }
$selected = $selected | Sort-Object -Unique

if ($selected.Count -lt 3) { throw 'ARM32 payload is unexpectedly empty.' }
foreach ($relative in $selected) {
    if ($relative -notmatch '^system/(lib/libhoudini\.so|bin/arm/linker|lib/arm/[A-Za-z0-9._/+@-]+)$' -or $relative.Contains('..')) {
        throw "Unsafe payload path: $relative"
    }
}

$lines = foreach ($relative in $selected) {
    $native = Join-Path $root ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $native -PathType Leaf)) { throw "Missing payload file: $relative" }
    $hash = (Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $relative"
}

$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
[IO.File]::WriteAllText($OutputPath, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Files = $lines.Count; Bytes = ($selected | ForEach-Object { (Get-Item -LiteralPath (Join-Path $root $_)).Length } | Measure-Object -Sum).Sum; Output = $OutputPath }
