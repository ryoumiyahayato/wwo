# Windows局部入口与封存状态

候选未提交，完整门未运行。仅A1/soldier和A2/recipient的seed71进程对照完成。A3脚本24h尚未验证，G3自动测试已知因observer_ref字段中断。

```powershell
$AttachmentRoot = 'D:\programs\WWO\research\military\wwo-person-attachment-20261011T0010'
$AttachmentPython = 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$AttachmentClient = Join-Path $AttachmentRoot 'experiments\war_resolver\interactive_observer\client.py'
$AttachmentScripts = Join-Path $AttachmentRoot 'experiments\war_resolver\attachment_continuity\scripts'
& $AttachmentPython -B $AttachmentClient --scene A1 --actor soldier --seed 71 --session review_soldier --quota 1 --json --script (Join-Path $AttachmentScripts 'A1.txt')
& $AttachmentPython -B $AttachmentClient --scene A2 --actor recipient --seed 71 --session review_recipient --quota 7 --json --script (Join-Path $AttachmentScripts 'A2.txt')
```

已有文本语法：attach id target parent delay duration；revoke id target delay。只有当前有权人物可用；公司决策间隔300秒，delay最少1秒。手动等待暂停研究时钟；advance后drain续接PENDING。停止输入quit或关闭stdin，只清理本客户端所属子进程。

以下是实际存在的验证入口，本轮停止后未再执行。需另行续接授权和预算：

```powershell
& 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' --headless --path $AttachmentRoot --script res://experiments/war_resolver/attachment_continuity/tests.gd -- --all --long
& $AttachmentPython -B (Join-Path $AttachmentRoot 'experiments\war_resolver\attachment_continuity\e2e_tests.py') --output 'D:\programs\WWO\research\military\runs\attachment-resume-e2e' --long
& 'C:\Users\agcrf\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File (Join-Path $AttachmentRoot 'tools\run_validation.ps1') -GodotPath 'D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe' -ProjectPath $AttachmentRoot -PythonPath $AttachmentPython
```

默认人物入口不输出DEBUG_TRUTH。显式diagnostic参数才生成末尾审计。未启动后台循环；不进入下一周期。

