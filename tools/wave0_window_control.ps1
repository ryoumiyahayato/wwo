param(
    [Parameter(Mandatory = $true)][int]$TargetProcessId,
    [Parameter(Mandatory = $true)]
    [ValidateSet('Capture', 'Key', 'Click')]
    [string]$Action,
    [string]$OutputPath = '',
    [string]$Key = '',
    [int]$ClientX = 0,
    [int]$ClientY = 0
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class Wave0Native {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
'@

function Get-TargetWindow {
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $process = Get-Process -Id $TargetProcessId -ErrorAction Stop
        $process.Refresh()
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $process.MainWindowHandle
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Process $TargetProcessId has no main window."
}

function Set-TargetForeground([IntPtr]$WindowHandle) {
    [Wave0Native]::ShowWindow($WindowHandle, 9) | Out-Null
    [Wave0Native]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [Wave0Native]::SetForegroundWindow($WindowHandle) | Out-Null
    [Wave0Native]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 120
}

function Send-VirtualKey([IntPtr]$WindowHandle, [uint16]$VirtualKey) {
    Set-TargetForeground $WindowHandle
    $down = New-Object Wave0Native+INPUT
    $down.type = 1
    $downKey = New-Object Wave0Native+KEYBDINPUT
    $downKey.wVk = $VirtualKey
    $downUnion = New-Object Wave0Native+InputUnion
    $downUnion.ki = $downKey
    $down.U = $downUnion
    $up = New-Object Wave0Native+INPUT
    $up.type = 1
    $upKey = New-Object Wave0Native+KEYBDINPUT
    $upKey.wVk = $VirtualKey
    $upKey.dwFlags = 2
    $upUnion = New-Object Wave0Native+InputUnion
    $upUnion.ki = $upKey
    $up.U = $upUnion
    $inputs = [Wave0Native+INPUT[]]@($down, $up)
    $sent = [Wave0Native]::SendInput(
        [uint32]$inputs.Length,
        $inputs,
        [Runtime.InteropServices.Marshal]::SizeOf([type][Wave0Native+INPUT])
    )
    if ($sent -ne 2) { throw "SendInput sent $sent of 2 key events." }
}

function Send-ClientClick([IntPtr]$WindowHandle, [int]$X, [int]$Y) {
    Set-TargetForeground $WindowHandle
    $point = New-Object Wave0Native+POINT
    $point.X = $X
    $point.Y = $Y
    if (-not [Wave0Native]::ClientToScreen($WindowHandle, [ref]$point)) {
        throw 'ClientToScreen failed.'
    }
    if (-not [Wave0Native]::SetCursorPos($point.X, $point.Y)) {
        throw 'SetCursorPos failed.'
    }
    $down = New-Object Wave0Native+INPUT
    $down.type = 0
    $downMouse = New-Object Wave0Native+MOUSEINPUT
    $downMouse.dwFlags = 0x0002
    $downUnion = New-Object Wave0Native+InputUnion
    $downUnion.mi = $downMouse
    $down.U = $downUnion
    $up = New-Object Wave0Native+INPUT
    $up.type = 0
    $upMouse = New-Object Wave0Native+MOUSEINPUT
    $upMouse.dwFlags = 0x0004
    $upUnion = New-Object Wave0Native+InputUnion
    $upUnion.mi = $upMouse
    $up.U = $upUnion
    $inputs = [Wave0Native+INPUT[]]@($down, $up)
    $sent = [Wave0Native]::SendInput(
        [uint32]$inputs.Length,
        $inputs,
        [Runtime.InteropServices.Marshal]::SizeOf([type][Wave0Native+INPUT])
    )
    if ($sent -ne 2) { throw "SendInput sent $sent of 2 mouse events." }
}

function Save-ClientCapture([IntPtr]$WindowHandle, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'OutputPath is required.' }
    $windowRect = New-Object Wave0Native+RECT
    $clientRect = New-Object Wave0Native+RECT
    if (-not [Wave0Native]::GetWindowRect($WindowHandle, [ref]$windowRect)) {
        throw 'GetWindowRect failed.'
    }
    if (-not [Wave0Native]::GetClientRect($WindowHandle, [ref]$clientRect)) {
        throw 'GetClientRect failed.'
    }
    $clientOrigin = New-Object Wave0Native+POINT
    if (-not [Wave0Native]::ClientToScreen($WindowHandle, [ref]$clientOrigin)) {
        throw 'ClientToScreen failed.'
    }
    $windowWidth = $windowRect.Right - $windowRect.Left
    $windowHeight = $windowRect.Bottom - $windowRect.Top
    $clientWidth = $clientRect.Right - $clientRect.Left
    $clientHeight = $clientRect.Bottom - $clientRect.Top
    $bitmap = New-Object Drawing.Bitmap($windowWidth, $windowHeight)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $device = $graphics.GetHdc()
    try {
        if (-not [Wave0Native]::PrintWindow($WindowHandle, $device, 2)) {
            throw 'PrintWindow failed.'
        }
    }
    finally {
        $graphics.ReleaseHdc($device)
        $graphics.Dispose()
    }
    $crop = New-Object Drawing.Rectangle(
        ($clientOrigin.X - $windowRect.Left),
        ($clientOrigin.Y - $windowRect.Top),
        $clientWidth,
        $clientHeight
    )
    $clientBitmap = $bitmap.Clone($crop, $bitmap.PixelFormat)
    $bitmap.Dispose()
    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    try {
        $clientBitmap.Save($fullPath, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $clientBitmap.Dispose()
    }
    Write-Output $fullPath
}

$windowHandle = Get-TargetWindow
switch ($Action) {
    'Capture' { Save-ClientCapture $windowHandle $OutputPath }
    'Click' { Send-ClientClick $windowHandle $ClientX $ClientY }
    'Key' {
        $keyMap = @{
            'ENTER' = 0x0D; 'ESCAPE' = 0x1B; 'F5' = 0x74; 'F9' = 0x78;
            'F12' = 0x7B; 'C' = 0x43; 'M' = 0x4D; 'O' = 0x4F; 'P' = 0x50
        }
        $normalizedKey = $Key.ToUpperInvariant()
        if (-not $keyMap.ContainsKey($normalizedKey)) {
            throw "Unsupported key: $Key"
        }
        Send-VirtualKey $windowHandle ([uint16]$keyMap[$normalizedKey])
    }
}
