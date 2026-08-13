param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$failurePattern = '(?im)(^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Could not resolve class|Invalid call|Loaded resource as image file, this will not work on export|Failed loading resource|Resource file not found|[1-9][0-9]* failures)'

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wwo-export-smoke-" + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporaryRoot
$exportPath = Join-Path $temporaryRoot 'wwo-player-visible-smoke.exe'

function Invoke-GodotProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    Write-Host "`n=== $Name ==="
    $quotedArguments = @(
        $Arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }
    ) -join ' '
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = $quotedArguments
    $startInfo.WorkingDirectory = $ProjectPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "$Name could not start" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) { $process.Kill() }
    $process.WaitForExit()
    $text = $stdoutTask.Result + $stderrTask.Result
    if (-not [string]::IsNullOrWhiteSpace($text)) { Write-Host $text.TrimEnd() }
    if (-not $finished) { throw "$Name timed out after $TimeoutSeconds seconds" }
    if ($process.ExitCode -ne 0) { throw "$Name failed with exit code $($process.ExitCode)" }
    if ($text -match $failurePattern) { throw "$Name emitted a player-critical script or resource failure" }
}

try {
    Invoke-GodotProcess -Name 'Clean import' -Executable $GodotPath -Arguments @(
        '--editor', '--headless', '--path', $ProjectPath, '--quit'
    )
    Invoke-GodotProcess -Name 'Export resource contract' -Executable $GodotPath -Arguments @(
        '--headless', '--path', $ProjectPath,
        '--script', 'res://tests/formal/formal_world_export_resource_smoke.gd'
    )
    Invoke-GodotProcess -Name 'Windows release export' -Executable $GodotPath -Arguments @(
        '--headless', '--path', $ProjectPath,
        '--export-release', 'Windows Desktop', $exportPath
    )
    if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) {
        throw "Windows release export did not create $exportPath"
    }
    Invoke-GodotProcess -Name 'Packaged player baseline journey' -Executable $exportPath -Arguments @(
        '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility',
        '--', '--wwo-player-baseline-probe'
    )
    Write-Host "`nWindows export resource contract and packaged player journey passed."
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (
        $resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith('wwo-export-smoke-')
    ) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
