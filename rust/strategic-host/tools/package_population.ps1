[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $DataDirectory
)

$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$source = Join-Path $repository 'data/historical_population_1900'
$destination = Join-Path $DataDirectory 'historical_population_1900'
$manifestPath = Join-Path $source 'runtime-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
if ($manifest.format_version -ne 1 -or
    !$manifest.versions.Contains([string] $manifest.current_version) -or
    !$manifest.versions.Contains([string] $manifest.market_calibration_version)) {
    throw "Invalid population manifest: $manifestPath"
}

$assets = foreach ($version in $manifest.versions.Keys) {
    $entry = $manifest.versions[$version]
    if (!$entry.opening) {
        throw "Population v$version has no opening file."
    }
    foreach ($name in $entry.Values) {
        if ($name -cnotmatch '^[a-zA-Z0-9_][a-zA-Z0-9_.-]*\.json\z') {
            throw "Invalid population v$version asset name: $name"
        }
        Get-Item -LiteralPath (Join-Path $source $name)
    }
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
foreach ($asset in ($assets | Sort-Object Name -Unique)) {
    Copy-Item -LiteralPath $asset.FullName -Destination $destination
}
Copy-Item -LiteralPath $manifestPath -Destination $destination
