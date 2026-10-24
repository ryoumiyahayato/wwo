"""Finite native R40/R41 comparison. Never reads the real user data directory.

The sole temporary setting beside each executable redirects user:// and the
entry scene. It is removed in finally. The external driver opens the real menu,
builds the normal world, pauses the clock, visits LOCALs, and leaves without save.
"""
from __future__ import annotations
import argparse, ctypes, ctypes.wintypes as w, json, os, pathlib, subprocess, threading, time

ROOT = pathlib.Path(__file__).resolve().parents[2]
ART = ROOT / "local-artifacts/r41_performance"
EXES = {
    "A": ROOT / "builds/preview_2026-10-18_geographic_world_r40/WWO_1900_Geographic_World_Presentation_R40_Preview.exe",
    "B": ROOT / "builds/preview_2026-10-18_historical_scenes_r41/WWO_1900_Historical_Landmarks_Environmental_Scenes_R41_Preview.exe",
}
K = ctypes.WinDLL("kernel32", use_last_error=True)
P = ctypes.WinDLL("psapi", use_last_error=True)
U = ctypes.WinDLL("user32", use_last_error=True)
U.GetForegroundWindow.restype = w.HWND
U.GetWindowThreadProcessId.argtypes = [w.HWND, ctypes.POINTER(w.DWORD)]
K.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
K.OpenProcess.restype = w.HANDLE
K.GetProcessTimes.argtypes = [w.HANDLE] + [ctypes.POINTER(w.FILETIME)] * 4
K.CloseHandle.argtypes = [w.HANDLE]

class Counters(ctypes.Structure):
    _fields_ = [("cb", w.DWORD), ("faults", w.DWORD)] + [(n, ctypes.c_size_t) for n in (
        "peak_working", "working", "peak_paged", "paged", "peak_nonpaged", "nonpaged", "pagefile", "peak_pagefile", "private")]

P.GetProcessMemoryInfo.argtypes = [w.HANDLE, ctypes.POINTER(Counters), w.DWORD]

def cpu_seconds(t: w.FILETIME):
    return ((t.dwHighDateTime << 32) + t.dwLowDateTime) / 10_000_000

def sample_process(process, directory, stop):
    handle = K.OpenProcess(0x0400 | 0x0010, False, process.pid)
    rows, previous = [], None
    try:
        while not stop.is_set() and process.poll() is None:
            row = {"unix": time.time()}
            foreground = w.DWORD()
            U.GetWindowThreadProcessId(U.GetForegroundWindow(), ctypes.byref(foreground))
            row["foreground"] = foreground.value == process.pid
            counters = Counters(); counters.cb = ctypes.sizeof(counters)
            if P.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
                row.update(working_bytes=counters.working, private_bytes=counters.private)
            born, ended, kernel, user = (w.FILETIME() for _ in range(4))
            if K.GetProcessTimes(handle, ctypes.byref(born), ctypes.byref(ended), ctypes.byref(kernel), ctypes.byref(user)):
                cpu = cpu_seconds(kernel) + cpu_seconds(user)
                row["cpu_seconds"] = cpu
                if previous:
                    row["cpu_one_core_percent"] = 100 * (cpu - previous[1]) / (row["unix"] - previous[0])
                    row["cpu_machine_percent"] = row["cpu_one_core_percent"] / os.cpu_count()
                previous = row["unix"], cpu
            rows.append(row)
            stop.wait(0.5)
    finally:
        K.CloseHandle(handle)
        (directory / "process.json").write_text(json.dumps(rows, indent=2), encoding="utf8")

def activate_window(target):
    found = []
    callback_type = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
    U.EnumWindows.argtypes = [callback_type, w.LPARAM]
    U.ShowWindow.argtypes = [w.HWND, ctypes.c_int]
    U.BringWindowToTop.argtypes = [w.HWND]
    U.SetForegroundWindow.argtypes = [w.HWND]
    def visit(hwnd, unused):
        owner = w.DWORD()
        U.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == target and U.IsWindowVisible(hwnd): found.append(hwnd)
        return True
    for _ in range(100):
        U.EnumWindows(callback_type(visit), 0)
        if found: break
        time.sleep(.05)
    if not found: return False
    hwnd = found[0]
    U.ShowWindow(hwnd, 9)
    U.BringWindowToTop(hwnd)
    U.SetForegroundWindow(hwnd)
    if U.GetForegroundWindow() != hwnd:
        # Connect the launch thread's input queue for this one activation only.
        thread = K.GetCurrentThreadId()
        foreground_thread = U.GetWindowThreadProcessId(U.GetForegroundWindow(), None)
        attached = U.AttachThreadInput(thread, foreground_thread, True)
        try:
            U.BringWindowToTop(hwnd)
            U.SetForegroundWindow(hwnd)
        finally:
            if attached: U.AttachThreadInput(thread, foreground_thread, False)
    return U.GetForegroundWindow() == hwnd

def run(label: str, screenshots: bool, foreground: bool):
    case = label[0]
    exe = EXES["A" if case == "A" else "B"]
    directory = ART / label
    if directory.exists():
        raise RuntimeError(f"Do not overwrite an existing measurement: {directory}")
    directory.mkdir(parents=True)
    cfg = exe.parent / "override.cfg"
    if cfg.exists():
        raise RuntimeError(f"Existing override left untouched: {cfg}")
    scene = ART / "performance_scene.tscn"
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="'+(ROOT / "tools/map/r41_performance_driver.gd").as_posix()+'" id="1"]\n[node name="R41FiniteComparison" type="Node"]\nscript = ExtResource("1")\n', encoding="utf8")
    cfg.write_text('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="WWO_R41_Perf_20261018_'+label+'"\nrun/main_scene="'+scene.as_posix()+'"\n[display]\nwindow/size/viewport_width=1250\nwindow/size/viewport_height=720\nwindow/size/window_width_override=1250\nwindow/size/window_height_override=720\nwindow/vsync/vsync_mode=1\n', encoding="utf8")
    env = os.environ.copy()
    env.update(WWO_PERF_OUTPUT=directory.as_posix(), WWO_PERF_CASE=case, WWO_PERF_SCREENSHOTS="1" if screenshots else "0")
    info = {"case": case, "label": label, "executable": str(exe), "start_unix": time.time(), "logical_cpus": os.cpu_count(), "resolution": [1250, 720], "game_clock": "paused", "save": "none"}
    process = None; gpu = None; sampler = None; stop = threading.Event()
    try:
        with (directory / "runtime.log").open("w", encoding="utf8") as log:
            process = subprocess.Popen([str(exe)], cwd=exe.parent, env=env, stdout=log, stderr=subprocess.STDOUT)
            info["pid"] = process.pid
            if foreground: info["foreground_activation"] = activate_window(process.pid)
            sampler = threading.Thread(target=sample_process, args=(process, directory, stop)); sampler.start()
            gpu = subprocess.Popen(["powershell", "-NoProfile", "-File", str(ROOT / "tools/map/r41_gpu_sample.ps1"), "-TargetProcess", str(process.pid), "-OutputFile", str(directory / "gpu.json")], creationflags=0x08000000, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            last = ""; last_report = time.monotonic()
            while process.poll() is None:
                try:
                    progress = json.loads((directory / "progress.json").read_text(encoding="utf8"))
                    key = str(progress.get("event")) + str(progress.get("details", {}).get("place", ""))
                    if key != last:
                        print(label, key, flush=True); last = key; last_report = time.monotonic()
                except (FileNotFoundError, json.JSONDecodeError): pass
                if time.time() - info["start_unix"] > 360:
                    info["timeout"] = True
                    process.terminate()
                    break
                if time.monotonic() - last_report > 40:
                    print(label, "waiting for current finite stage", flush=True); last_report = time.monotonic()
                time.sleep(0.5)
            info["exit_code"] = process.wait(timeout=15)
    finally:
        if process and process.poll() is None:
            process.terminate(); process.wait(timeout=15)
        stop.set()
        if sampler: sampler.join(timeout=10)
        if gpu:
            try: gpu.wait(timeout=8)
            except subprocess.TimeoutExpired: gpu.terminate()
        info["end_unix"] = time.time()
        (directory / "run.json").write_text(json.dumps(info, indent=2), encoding="utf8")
        # Preserve the exact finite-run settings in the excluded artifact folder.
        if cfg.exists(): cfg.replace(directory / "used_override.cfg")
    if info.get("exit_code") != 0 or not (directory / "frames.csv").exists():
        raise RuntimeError(f"{label} did not finish; inspect runtime.log")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("labels", nargs="+", help="A1 B1 C1 etc.; existing results are never overwritten")
    parser.add_argument("--screenshots", action="store_true")
    parser.add_argument("--foreground", action="store_true", help="One activation per native run; never repeatedly steals focus")
    args = parser.parse_args()
    for label in args.labels: run(label, args.screenshots, args.foreground)
