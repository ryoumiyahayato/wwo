param(
    [string]$GodotPath = 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe',
    [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found: $GodotPath"
}

$logDirectory = Join-Path $ProjectPath 'builds\focused-tests'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$tests = @(
    @{ Name = '社会世界'; Script = 'res://tests/v2_3/v2_3_social_sandbox_test.gd'; Timeout = 220 },
    @{ Name = '社会行动闭环'; Script = 'res://tests/v2_3/v2_3_social_sandbox_completion_test.gd'; Timeout = 120 },
    @{ Name = '生活自理'; Script = 'res://tests/v2_3/v2_3_survival_autonomy_test.gd'; Timeout = 120 },
    @{ Name = '玩家界面与地图'; Script = 'res://tests/v2_3/v2_3_player_interface_test.gd'; Timeout = 120 },
    @{ Name = '保存与恢复'; Script = 'res://tests/v2_3/v2_3_save_load_test.gd'; Timeout = 120 },
    @{ Name = '长期性能'; Script = 'res://tests/v2_3/v2_3_performance_guard_test.gd'; Timeout = 180 }
)

function Invoke-FocusedTest {
    param([hashtable]$Test)
    $safeName = [regex]::Replace($Test.Name, '[^\p{L}\p{N}_-]', '_')
    $stdout = Join-Path $logDirectory "$safeName.stdout.log"
    $stderr = Join-Path $logDirectory "$safeName.stderr.log"
    $started = Get-Date
    Write-Host "`n开始：$($Test.Name)"
    $process = Start-Process `
        -FilePath $GodotPath `
        -ArgumentList @('--headless', '--path', $ProjectPath, '--script', $Test.Script) `
        -WorkingDirectory $ProjectPath `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -NoNewWindow `
        -PassThru
    $finished = $process.WaitForExit([int]$Test.Timeout * 1000)
    if (-not $finished) {
        $process.Kill($true)
        throw "$($Test.Name) 超过 $($Test.Timeout) 秒，已终止。日志：$stdout / $stderr"
    }
    $parts = @()
    if (Test-Path $stdout) { $parts += Get-Content $stdout -Encoding UTF8 }
    if (Test-Path $stderr) { $parts += Get-Content $stderr -Encoding UTF8 }
    $text = $parts -join "`n"
    if ($process.ExitCode -ne 0 -or $text -match '(?im)(SCRIPT ERROR|Parse Error|Assertion failed|[1-9][0-9]* failures)') {
        Write-Host "失败：$($Test.Name)"
        $parts | Select-Object -Last 100 | ForEach-Object { Write-Host $_ }
        throw "$($Test.Name) 未通过。完整日志：$stdout / $stderr"
    }
    $summary = $parts | Where-Object { $_ -match '(checks, 0 failures|performance:)' } | Select-Object -Last 2
    $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    $summary | ForEach-Object { Write-Host $_ }
    Write-Host "完成：$($Test.Name)（$elapsed 秒）"
}

Write-Host '导入并扫描脚本...'
& $GodotPath --editor --headless --path $ProjectPath --quit
if ($LASTEXITCODE -ne 0) {
    throw 'Godot 脚本导入失败。'
}
foreach ($test in $tests) {
    Invoke-FocusedTest -Test $test
}
Write-Host "`n全部定向测试完成。日志目录：$logDirectory"
