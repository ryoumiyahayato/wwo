"""Bounded ordinary Godot window, real menu/world, isolated user://.

The explicitly selected economic-action route uses its own isolated save slots.

Reuses the R57 one-point probe. Does not build or unpack an executable.
"""
import argparse
import os
from pathlib import Path
import subprocess
import time
import ctypes
import json
import gzip
import contextlib
import sys

ROOT = Path(__file__).resolve().parents[2]


@contextlib.contextmanager
def resource_slot():
    """Share the preview manager's OS lock; wait for non-participating engines.

    Kernel ownership ends on process exit. A stale status file is never a lock.
    This small local protocol does not control other work lines.
    """
    import msvcrt
    status_path = ROOT / 'local-artifacts/r57-living-ui-2026-10-23/resource-state.json'
    status_path.parent.mkdir(parents=True, exist_ok=True)
    check = "Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(Godot|WWO|candidate).*\\.exe$' } | Select-Object ProcessId,CreationDate,CommandLine | ConvertTo-Json -Compress"
    started = subprocess.check_output(['powershell', '-NoProfile', '-Command',
        f'(Get-Process -Id {os.getpid()}).StartTime.ToUniversalTime().ToString("o")'], text=True).strip()
    state = {'pid': os.getpid(), 'process_start_utc': started, 'request': sys.argv[1:],
             'resources': ['Godot GUI', 'shared GPU measurement', 'candidate export/install', 'test configuration writes'],
             'lock': 'builds/.preview-manager.lock'}
    def publish(status, occupants=None):
        state.update(status=status, occupants=occupants or [], updated_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
        status_path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
    with (ROOT / 'builds/.preview-manager.lock').open('r+b') as lock:
        acquired = False
        try:
            while not acquired:
                lock.seek(0)
                try:
                    msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
                    acquired = True
                except OSError:
                    publish('WAITING')
                    print('WAITING: preview resource lock', flush=True)
                    time.sleep(2)
            while True:
                raw = subprocess.check_output(['powershell', '-NoProfile', '-Command', check], text=True).strip()
                occupants = json.loads(raw) if raw else []
                if isinstance(occupants, dict): occupants = [occupants]
                gpu = subprocess.check_output(['nvidia-smi', '--query-compute-apps=pid,process_name', '--format=csv,noheader,nounits'], text=True).strip()
                shared_host = []
                external_gpu = []
                for row in gpu.splitlines():
                    if not row.strip(): continue
                    sharing = '--functional-gpu-sharing' in sys.argv and 'performance' not in sys.argv
                    if sharing and 'OpenAI.Codex_' in row and row.rstrip().endswith('ChatGPT.exe'):
                        pid = int(row.split(',', 1)[0].strip())
                        command = subprocess.check_output(['powershell', '-NoProfile', '-Command',
                            f'(Get-CimInstance Win32_Process -Filter "ProcessId={pid}").CommandLine'], text=True)
                        if '--utility-sub-type=on_device_model.mojom.OnDeviceModelService' in command:
                            shared_host.append(row)
                            continue
                    external_gpu.append(row)
                state['shared_host_gpu_contexts'] = shared_host
                state['external_gpu_contexts'] = external_gpu
                # External GPU work affects timing comparability, not ownership
                # of this project's override or ability to check gameplay.
                if not occupants:
                    break
                publish('WAITING', occupants)
                print('WAITING: existing Godot/WWO process; no message or termination', flush=True)
                time.sleep(2)
            publish('RUNNING')
            yield
        finally:
            if acquired:
                lock.seek(0)
                msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
            publish('RELEASED')


def native_screenshot_review(args):
    """Finite source-only route; show the real HWND without activation."""
    import msvcrt
    import shutil
    region_review = args.terrain_region_review
    if args.local_continuity_review and (not args.terrain_a0_review or not args.terrain_a0_new_world):
        raise ValueError('Local continuity review requires the existing A0 new paused world route')
    a0_mode = args.terrain_a0_review
    current_pack = args.terrain_current_pack.resolve(strict=True) if args.terrain_current_pack else None
    if current_pack and (not a0_mode or not current_pack.is_relative_to(ROOT/'local-artifacts') or current_pack.suffix!='.pck'):
        raise ValueError('Current-pack review requires an explicit local PCK and existing A0 route')
    if region_review and a0_mode:
        raise ValueError('A0 texture paging and military terrain are separate routes')
    new_paused = bool(a0_mode and args.terrain_a0_new_world)
    if os.name != 'nt' or args.exe or (not region_review and not new_paused and not args.screenshot_save):
        raise ValueError('Native review requires Windows source and a paused save, or explicit A0 new-world route')
    source = args.screenshot_save.resolve(strict=True) if not region_review and not new_paused else None
    manifest = args.terrain_a0_manifest.resolve(strict=True) if a0_mode else None
    if manifest and not manifest.is_relative_to(ROOT):
        raise ValueError('A0 manifest must stay in the project')
    record_resources = region_review or bool(a0_mode)
    output = (args.output_dir or ROOT/'local-artifacts/native-screenshot').resolve()
    if not output.is_relative_to(ROOT/'local-artifacts'):
        raise ValueError('Observer output must stay in local-artifacts')
    output.mkdir(parents=True, exist_ok=True)
    (ROOT/'builds').mkdir(exist_ok=True)
    continuity_originals = {}
    with (ROOT/'builds/.preview-manager.lock').open('a+b') as lock:
        lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        try:
            if args.local_continuity_review:
                sys.path.insert(0, str(ROOT))
                from tools.build.preview import Manager
                busy = Manager(track=False).busy()
                if busy:
                    raise RuntimeError('Graphics resource guard remains occupied: ' + str(busy))
            occupied = subprocess.check_output(['powershell', '-NoProfile', '-Command',
                "Get-Process -Name 'Godot*','WWO*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id; exit 0"], text=True).strip()
            if occupied:
                raise RuntimeError('Existing game/editor left untouched: ' + occupied)
            if args.continuity_before_source:
                if not args.local_continuity_review:
                    raise ValueError('Frozen source applies only to the requested continuity comparison')
                frozen = args.continuity_before_source.resolve(strict=True)
                if not frozen.is_relative_to(ROOT/'local-artifacts'):
                    raise ValueError('Frozen source must stay under local-artifacts')
                files = ['scripts/presentation/map/local_spatial_lod.gd','scripts/presentation/map/region_view.gd',
                    'scripts/presentation/map/globe_renderer.gd','scripts/content/local_spatial_content.gd',
                    'scripts/content/local_spatial_loader.gd','shaders/presentation/map/local_terrain.gdshader',
                    'shaders/presentation/map/local_chart.gdshaderinc','data/local/zermatt_west_physical_reference.json',
                    'data/local/london_westminster_1900.json']
                for rel in files:
                    path = ROOT/rel
                    continuity_originals[path] = (path.read_bytes(), (frozen/rel).read_bytes())
                    recovery = output/'current-source'/rel
                    recovery.parent.mkdir(parents=True, exist_ok=True)
                    recovery.write_bytes(continuity_originals[path][0])
                for path, (current, before) in continuity_originals.items():
                    if path.read_bytes() != current:
                        raise RuntimeError('Source changed while preparing comparison: '+str(path))
                    path.write_bytes(before)
            user_name = ('WWO_Terrain_A0_' if a0_mode else 'WWO_R57_Visual_Region_' if region_review else 'WWO_Native_Screenshot_') + time.strftime('%Y%m%d_%H%M%S')
            user_dir = Path(os.environ['APPDATA'])/user_name
            user_dir.mkdir(exist_ok=False)
            if source is not None:
                shutil.copyfile(source, user_dir/'formal_world_1900_manual_1.json')
            # Godot --main-pack loads override.cfg beside that pack, not --path.
            config = (current_pack.parent if current_pack else ROOT)/'override.cfg'
            original = config.read_bytes() if config.exists() else None
            temporary = ('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+user_name+'"\n'
                '[display]\nwindow/size/no_focus=true\n[debug]\nfile_logging/max_log_files=2\n')
            temporary_bytes = temporary.encode('utf-8')
            process = None
            ownership = []
            resource_samples = []
            last_resource = 0.0
            previous_cpu = None
            previous_system = None
            gpu_sampling_available = None
            class PowerStatus(ctypes.Structure):
                _fields_ = [('ac',ctypes.c_ubyte),('flags',ctypes.c_ubyte),('percent',ctypes.c_ubyte),('saver',ctypes.c_ubyte),('life',ctypes.c_uint32),('full_life',ctypes.c_uint32)]
            def environment_sample(game_pid=None, game_cpu=None):
                nonlocal previous_system, gpu_sampling_available
                sample_began = time.monotonic()
                power = PowerStatus()
                ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(power))
                clocks = [ctypes.c_uint64() for _ in range(3)]
                ctypes.windll.kernel32.GetSystemTimes(*(ctypes.byref(value) for value in clocks))
                idle, kernel_time, user_time = [value.value/10000000 for value in clocks]
                total, busy = kernel_time+user_time, kernel_time+user_time-idle
                row = {'ms':round(time.time()*1000),'ac':power.ac,'battery_percent':power.percent,'battery_saver':power.saver}
                if previous_system is not None:
                    elapsed_total = total-previous_system[0]
                    row['whole_machine_cpu_percent'] = 100*(busy-previous_system[1])/elapsed_total if elapsed_total>0 else None
                    if game_cpu is not None and previous_system[2] is not None and elapsed_total>0:
                        row['external_machine_cpu_percent'] = max(0,100*((busy-previous_system[1])-(game_cpu-previous_system[2]))/elapsed_total)
                previous_system = (total,busy,game_cpu)
                # Read actual activity, not a blanket Blender-name exclusion.
                gpu_query = "$ErrorActionPreference='Stop'; Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine | Where-Object { $_.UtilizationPercentage -gt 0 } | Select-Object Name,UtilizationPercentage | ConvertTo-Json -Compress"
                row['gpu_engine_sample_available'] = False
                if gpu_sampling_available is not False:
                    try:
                        active = subprocess.run(['powershell','-NoProfile','-Command',gpu_query],capture_output=True,text=True,timeout=3)
                        engines = json.loads(active.stdout) if active.returncode==0 and active.stdout.strip() else []
                        if isinstance(engines,dict): engines=[engines]
                        row['gpu_engines'] = engines
                        row['external_gpu_engines'] = [value for value in engines if game_pid is None or not value.get('Name','').startswith(f'pid_{game_pid}_')]
                        row['gpu_engine_sample_available'] = active.returncode==0
                    except (subprocess.TimeoutExpired,ValueError):
                        pass
                    gpu_sampling_available = row['gpu_engine_sample_available']
                try:
                    gpu = subprocess.run(['nvidia-smi','--query-gpu=utilization.gpu,memory.used,power.draw,temperature.gpu','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=3)
                    row['whole_device_gpu_csv'] = gpu.stdout.strip() if gpu.returncode==0 else 'unavailable'
                except subprocess.TimeoutExpired:
                    row['whole_device_gpu_csv'] = 'unavailable'
                row['sample_wall_ms'] = round((time.monotonic()-sample_began)*1000,3)
                return row
            class MemoryCounters(ctypes.Structure):
                _fields_ = [('cb',ctypes.c_uint32),('faults',ctypes.c_uint32)] + [(name,ctypes.c_size_t) for name in ['peak_working','working','peak_paged','paged','peak_nonpaged','nonpaged','pagefile','peak_pagefile','private']]
            get_memory = ctypes.windll.psapi.GetProcessMemoryInfo
            get_memory.argtypes = [ctypes.c_void_p,ctypes.POINTER(MemoryCounters),ctypes.c_uint32]
            get_times = ctypes.windll.kernel32.GetProcessTimes
            get_times.argtypes = [ctypes.c_void_p] + [ctypes.POINTER(ctypes.c_uint64)]*4
            foreground = ctypes.windll.user32.GetForegroundWindow
            foreground.restype = ctypes.c_void_p
            foreground_pid = ctypes.windll.user32.GetWindowThreadProcessId
            foreground_pid.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
            def owner():
                pid = ctypes.c_ulong()
                foreground_pid(foreground(), ctypes.byref(pid))
                return pid.value
            initial_owner = owner()
            user32 = ctypes.windll.user32
            user32.ShowWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
            user32.IsWindowVisible.argtypes = [ctypes.c_void_p]
            user32.IsIconic.argtypes = [ctypes.c_void_p]
            user32.SetWindowPos.argtypes = [ctypes.c_void_p,ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_uint]
            hwnd = None
            state = None
            env = os.environ.copy()
            env['WWO_VISUAL_OUTPUT'] = output.as_posix()
            env['WWO_LOCAL_CONTINUITY_REVIEW'] = '1' if args.local_continuity_review else '0'
            env['WWO_LOCAL_CONTINUITY_CASES'] = args.places if args.local_continuity_review else ''
            env['WWO_VISUAL_USER_DIR'] = user_dir.as_posix()
            env['WWO_TERRAIN_A0_SOURCE_ROOT'] = ROOT.as_posix()
            env['WWO_VISUAL_MAIN_PACK'] = current_pack.as_posix() if current_pack else ''
            # Do not inherit filters/archive settings from unrelated observer runs.
            for name in ['WWO_VISUAL_NO_IMAGES','WWO_VISUAL_IMAGE_LABELS','WWO_VISUAL_RECORD_ARCHIVE','WWO_TERRAIN_AB','WWO_TERRAIN_A0','WWO_TERRAIN_A0_MANIFEST','WWO_TERRAIN_A0_NEW']:
                env.pop(name, None)
            if a0_mode:
                env['WWO_TERRAIN_A0'] = a0_mode
                env['WWO_TERRAIN_A0_MANIFEST'] = manifest.as_posix()
                env['WWO_TERRAIN_A0_NEW'] = '1' if new_paused else '0'
            environment_before = []
            if record_resources:
                environment_before.append(environment_sample())
                time.sleep(1)
                environment_before.append(environment_sample())
            try:
                config.write_bytes(temporary_bytes)
                with (output/'runtime.log').open('w', encoding='utf-8') as log:
                    startup = subprocess.STARTUPINFO()
                    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                    startup.wShowWindow = 0  # Initial SW_HIDE, then SW_SHOWNOACTIVATE below.
                    command = ['D:/Tools/Godot-4.6.3/Godot_v4.6.3-stable_win64.exe',
                        '--path',str(ROOT),'--resolution','1280x720','--position','30,30',
                        '--rendering-method','gl_compatibility','--audio-driver','Dummy',
                        '--log-file',str(output/'engine.log'),
                        '--script','res://tools/map/native_screenshot_boot.gd',
                        '--','--terrain-region-review' if region_review else '--native-screenshot-review']
                    if current_pack: command[1:1] = ['--main-pack',str(current_pack)]
                    if a0_mode: command.append('--terrain-a0-review')
                    process = subprocess.Popen(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,startupinfo=startup)
                    deadline = time.monotonic()+(420 if a0_mode else 240)
                    while process.poll() is None:
                        handle_file = output/'window-handle.json'
                        if hwnd is None and handle_file.exists():
                            try: handle = json.loads(handle_file.read_text(encoding='utf-8'))
                            except ValueError: handle = {}
                            if handle.get('pid') == process.pid:
                                hwnd = int(handle['hwnd'])
                                pid = ctypes.c_ulong()
                                foreground_pid(hwnd,ctypes.byref(pid))
                                if pid.value != process.pid:
                                    raise RuntimeError('Godot root HWND owner differs')
                                user32.ShowWindow(hwnd,4)
                                user32.SetWindowPos(hwnd,1,0,0,0,0,0x13)  # Bottom; NOACTIVATE/NOMOVE/NOSIZE.
                                state = 'visible'
                        request = output/'window-request.json'
                        if hwnd and request.exists():
                            try: requested = json.loads(request.read_text(encoding='utf-8'))['state']
                            except (ValueError, KeyError): requested = state
                            if requested != state and requested in ['visible','hidden','minimized']:
                                user32.ShowWindow(hwnd,{'visible':4,'hidden':0,'minimized':7}[requested])
                                state = requested
                                (output/'window-state.json').write_text(json.dumps({'state':state,
                                    'visible':bool(user32.IsWindowVisible(hwnd)), 'minimized':bool(user32.IsIconic(hwnd))}),encoding='utf-8')
                        ownership.append([round(time.time()*1000), owner(),state,
                            bool(user32.IsWindowVisible(hwnd)) if hwnd else None,
                            bool(user32.IsIconic(hwnd)) if hwnd else None])
                        now = time.monotonic()
                        if record_resources and now-last_resource >= 1:
                            times = [ctypes.c_uint64() for _ in range(4)]
                            get_times(int(process._handle),*(ctypes.byref(value) for value in times))
                            cpu = (times[2].value+times[3].value)/10000000
                            counters = MemoryCounters(); counters.cb=ctypes.sizeof(counters)
                            get_memory(int(process._handle),ctypes.byref(counters),counters.cb)
                            phase_file = output/'phase.json'
                            try: phase = json.loads(phase_file.read_text(encoding='utf-8')) if phase_file.exists() else {'phase':'preparation'}
                            except ValueError: phase = {'phase':'phase_write_in_progress'}
                            sample = {'ms':round(time.time()*1000),**phase,'working_bytes':counters.working,'peak_working_bytes':counters.peak_working,
                                'private_bytes':counters.private,'cpu_percent_one_core':100*(cpu-previous_cpu)/(now-last_resource) if previous_cpu is not None else None}
                            # The requested compact route keeps the cheap process
                            # CPU/working-set reads, but leaves external GPU/CIM
                            # queries outside the timed native interaction.
                            if len(resource_samples)%5 == 0 and not args.summary_only:
                                sample['environment'] = environment_sample(process.pid,cpu)
                            resource_samples.append(sample)
                            last_resource=now; previous_cpu=cpu
                        if time.monotonic()>deadline:
                            raise TimeoutError('Native review exceeded its finite deadline')
                        time.sleep(.1)
                if process.returncode or 'SCRIPT ERROR:' in (output/'runtime.log').read_text(encoding='utf-8'):
                    raise RuntimeError('Native review failed; inspect runtime.log')
            finally:
                if process and process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill(); process.wait(timeout=5)
                # Never overwrite an unrelated concurrent edit, even on failure.
                if config.read_bytes() == temporary_bytes:
                    if original is None: config.unlink()
                    else: config.write_bytes(original)
                else:
                    raise RuntimeError('Override changed concurrently; preserved it instead of restoring')
                if record_resources:
                    (output/'resource-samples.json').write_text(json.dumps(resource_samples,indent=2),encoding='utf-8')
                    environments = [row['environment'] for row in resource_samples if 'environment' in row]
                    gpu_busy = [any(float(item.get('UtilizationPercentage',0))>5 for item in row.get('external_gpu_engines',[])) for row in environments]
                    cpu_busy = [float(row.get('external_machine_cpu_percent',0))*(os.cpu_count() or 1)>50 for row in environments]
                    competing = any(a and b for a,b in zip(gpu_busy,gpu_busy[1:])) or any(a and b for a,b in zip(cpu_busy,cpu_busy[1:]))
                    known = bool(environments) and all(row.get('gpu_engine_sample_available',False) and row.get('ac')==1 and row.get('battery_saver')==0 for row in environment_before+environments)
                    (output/'process-summary.json').write_text(json.dumps({'mode':a0_mode,'new_world_paused_route':new_paused,
                        'peak_working_bytes':max((row['peak_working_bytes'] for row in resource_samples),default=None),
                        'peak_sampled_private_bytes':max((row['private_bytes'] for row in resource_samples),default=None),
                        'environment_before':environment_before,'external_gpu_queries_during_timing':not args.summary_only,'sustained_external_competition_observed':competing,
                        'timing_environment_status':'UNVERIFIED_COMPETING_OR_UNKNOWN' if competing or not known else 'NO_SUSTAINED_COMPETITION_OBSERVED_REVIEW_REQUIRED',
                        'notes':['No Blender-name busy inference, no other process terminated, no indefinite resource wait.',
                            'External CPU is whole-machine busy time minus this Godot process; includes OS and launcher.',
                            'GPU engine counters identify external PIDs; whole-device nvidia values include this game.',
                            'Fresh process is not a physical cold disk read; OS file cache was not flushed.']},indent=2),encoding='utf-8')
                (output/'window-ownership.json').write_text(json.dumps({'initial_foreground_pid':initial_owner,
                    'game_pid':process.pid if process else None,'samples':ownership,
                    'game_seen_foreground':any(row[1]==process.pid for row in ownership) if process else None,
                    'test_user_dir':str(user_dir)},indent=2),encoding='utf-8')
        finally:
            changed_sources = []
            for path, (current, before) in continuity_originals.items():
                if path.read_bytes() == before:
                    path.write_bytes(current)
                elif path.read_bytes() != current:
                    changed_sources.append(str(path))
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
            if changed_sources:
                raise RuntimeError('Concurrent source edits preserved; candidate copy is in current-source: '+str(changed_sources))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('label', choices=['before', 'after', 'candidate', 'comparison'])
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--native-screenshot-review', action='store_true', help='Finite no-focus source screenshots; preserves override.cfg and the supplied save')
    parser.add_argument('--terrain-region-review', action='store_true', help='Finite real menu to terrain and collision walking; no save is read or written')
    parser.add_argument('--terrain-a0-review', choices=['original','flat_webp'], help='Existing no-focus WORLD/REGION/LOCAL route using the same cold-start A0 hook')
    parser.add_argument('--terrain-current-pack', type=Path, help='Run the existing finite A0 route against this normal-export PCK as main pack, not an overlay')
    parser.add_argument('--terrain-a0-manifest', type=Path, default=ROOT/'local-artifacts/terrain-lossless-20261027/manifest.json', help='Existing schema1 batch manifest; only mapped files change codec')
    parser.add_argument('--terrain-a0-new-world', action='store_true', help='Explicit formal menu new-world route; require default paused clock, never save')
    parser.add_argument('--local-continuity-review', action='store_true', help='Requested seven fixed WORLD/REGION/LOCAL cameras through the existing paused-world route')
    parser.add_argument('--continuity-before-source', type=Path, help='Frozen pre-edit map sources for the same cameras; restored under the existing resource lock')
    parser.add_argument('--screenshot-save', type=Path, help='Existing paused save to copy read-only into a unique screenshot test directory')
    parser.add_argument('--ui-only', action='store_true')
    parser.add_argument('--water-only', action='store_true', help='Reuse the finite Benelux installation check without another image set')
    parser.add_argument('--stability', action='store_true', help='Finite 30-second fixed-view observations; no new game monitor')
    parser.add_argument('--places', default='', help='Optional comma-separated stability cases')
    parser.add_argument('--mpp', type=float, default=500, help='Common stability scale; does not change the game zoom limits')
    parser.add_argument('--output-dir', type=Path, help='Isolated finite comparison directory; preserve older observations')
    parser.add_argument('--terrain-batch', action='store_true', help='Include Petersburg source seams in the existing finite observer')
    parser.add_argument('--mode-review', action='store_true', help='Requested finite map-mode, grid and Russian scale comparisons')
    parser.add_argument('--admin-lines-off', action='store_true', help='Compare the old optional administrative-line state')
    parser.add_argument('--dynamic', action='store_true', help='Explicit short rendered-frame handoff recording, bounded to20MiB')
    parser.add_argument('--foundation-review', action='store_true', help='Finite continental foundation views using the same ordinary-window observer')
    parser.add_argument('--acceptance', choices=['startup','visual','features','dynamic','rapid-entry','repair','performance','economic','economic-action'], help='Finite candidate acceptance; diagnostic driver only')
    parser.add_argument('--native-case', choices=['feedback','regional','stratified'], help='Explicit existing formal new-world configuration in the isolated user directory')
    parser.add_argument('--resident-case', choices=['idle','participating','released'], help='Ordinary resident seven-day comparison; no NPC command injection')
    parser.add_argument('--employment-case', choices=['idle','occupied','opportunity','arrears'], help='Finite ordinary two-employer comparison')
    parser.add_argument('--living-ui', action='store_true', help='Normal player employment and living UI; one bounded user directory')
    parser.add_argument('--material-trade', action='store_true', help='Bounded ordinary firm-to-firm material trade; reuse development test directory and preserve day30 baseline')
    parser.add_argument('--resume-material', action='store_true', help='Load the material GUI checkpoint from isolated slot4')
    parser.add_argument('--recover-material-override', action='store_true', help='Recover only the exact interrupted material-test override after its owner identity ended')
    parser.add_argument('--functional-gpu-sharing', action='store_true', help='Explicit user choice: functional GUI may share with the Codex host model service; timing remains invalid')
    parser.add_argument('--continuous-days', type=int, choices=[30], help='Authorized idle ordinary Opening run; reuse living UI directory and isolated slot3')
    parser.add_argument('--resume-continuous', action='store_true', help='Continue the existing 30-day record from its real isolated slot3; never create a replacement world')
    parser.add_argument('--preview-only', action='store_true', help='Only inspect the ordinary UI before export')
    parser.add_argument('--domain-check', action='store_true', help='Existing finite employment/consumption test, no GUI claim')
    parser.add_argument('--domain-regression', action='store_true', help='Reuse the existing multi-employer checks after shared kernel changes')
    parser.add_argument('--single-employer', action='store_true', help='Retain the original generation18 Opening for compatibility')
    parser.add_argument('--summary-only', action='store_true', help='Keep compact existing run records; skip optional screenshots and memory series')
    parser.add_argument('--compact-record', action='store_true', help='Append existing result records into one compressed JSON file; requires summary-only')
    args = parser.parse_args()
    if args.terrain_a0_new_world and not args.terrain_a0_review:
        raise ValueError('--terrain-a0-new-world requires --terrain-a0-review')
    if args.native_screenshot_review or args.terrain_region_review or args.terrain_a0_review:
        native_screenshot_review(args)
        return
    if args.screenshot_save:
        raise ValueError('--screenshot-save requires --native-screenshot-review')
    if args.compact_record and not args.summary_only:
        raise ValueError('Compact records require summary-only')
    if args.continuous_days and (args.employment_case != 'idle' or not args.compact_record or args.acceptance != 'economic-action'):
        raise ValueError('30-day run requires idle employment, economic-action and compact records')
    if args.resume_continuous and not args.continuous_days:
        raise ValueError('Resume requires the existing continuous run')
    if (args.resume_material or args.recover_material_override) and not args.material_trade:
        raise ValueError('Material recovery requires the material route')
    if args.functional_gpu_sharing and args.acceptance == 'performance':
        raise ValueError('Functional GPU sharing cannot be used for comparable performance')
    output = ROOT / ('local-artifacts/r57_stability' if args.stability else 'local-artifacts/r57_visual_repair') / args.label
    if args.output_dir:
        output=args.output_dir.resolve()
        if not output.is_relative_to(ROOT/'local-artifacts'):raise ValueError('Observer output must stay in local-artifacts')
    output.mkdir(parents=True, exist_ok=True)
    executable = args.exe.resolve() if args.exe else Path('D:/Tools/Godot-4.6.3/Godot_v4.6.3-stable_win64.exe')
    folder = executable.parent if args.exe else ROOT
    config = folder / 'override.cfg'
    original_visual_config = config.read_bytes() if config.exists() and args.acceptance == 'visual' and not args.exe else None
    if config.exists() and original_visual_config is None and not args.recover_material_override:
        raise RuntimeError('Existing override left untouched: ' + str(config))
    scene = (output.parent if args.summary_only else output) / 'visual.tscn'
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="' +
                     (ROOT / 'tools/map/r57_visual_driver.gd').as_posix() +
                     '" id="1"]\n[node name="R57FiniteVisual" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
    user_dir_name = ('WWO_R57_Visual_Economic_Action_20261023' if args.native_case else
                     'WWO_R57_Visual_Ordinary_Consumption_20261023') if args.acceptance == 'economic-action' else 'WWO_R57_Visual_Repair'
    if args.summary_only:
        user_dir_name = 'WWO_R57_Visual_Residents_Regression_20261023_' + ('development' if args.native_case else 'player')
    if args.compact_record:
        user_dir_name = 'WWO_R57_Visual_Employment_Regression_20261023_' + ('development' if args.native_case else 'player')
    if args.resident_case:
        if args.acceptance != 'economic-action' or args.native_case:
            raise ValueError('Resident comparison requires the ordinary economic-action route')
        user_dir_name = 'WWO_R57_Visual_Residents_20261023_' + args.resident_case
        if args.compact_record:
            user_dir_name = 'WWO_R57_Visual_Employment_20261023_' + args.resident_case
    if args.compact_record:
        user_dir_name = 'WWO_R57_Visual_MultiEmployment_20261023_' + ('source_' if not args.exe else '') + (args.employment_case or ('compat_' + args.resident_case if args.resident_case else 'development' if args.native_case else 'player' if args.single_employer else 'performance_' + args.label))
    if args.living_ui:
        if args.native_case or args.employment_case or args.resident_case or args.single_employer: raise ValueError('Living UI uses the unchanged ordinary two-employer Opening')
        user_dir_name = 'WWO_R57_Visual_Living_UI_20261023'
    if args.continuous_days:
        user_dir_name = 'WWO_R57_Visual_Living_UI_20261023'
    if args.material_trade:
        user_dir_name = 'WWO_R57_Visual_MultiEmployment_20261023_development'
    override_text = '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_dir_name + '"\n' + \
                      'run/main_scene="' + scene.as_posix() + '"\n[display]\nwindow/size/viewport_width=1280\n' + \
                      'window/size/viewport_height=720\nwindow/size/window_width_override=1280\nwindow/size/window_height_override=720\n'
    if args.acceptance == 'startup':
        override_text += 'window/size/no_focus=true\n'
    if config.exists() and original_visual_config is None:
        records = json.loads(gzip.decompress((output.parent/'material-trade-runs.json.gz').read_bytes()))
        owner = records.get('material-interruption', {}).get('owner', {})
        if config.read_text(encoding='utf-8') != override_text or '--material-trade' not in owner.get('request', []):
            raise RuntimeError('Existing override ownership differs; retained')
        pid = int(owner['pid'])
        live_start = subprocess.check_output(['powershell', '-NoProfile', '-Command',
            f'$p=Get-CimInstance Win32_Process -Filter "ProcessId={pid}"; if ($p) {{(Get-Process -Id {pid}).StartTime.ToUniversalTime().ToString("o")}}; exit 0'], text=True).strip()
        if live_start == owner['process_start_utc']:
            raise RuntimeError('Interrupted owner still alive; override retained')
        config.unlink()  # Exact own configuration; OS lock and engine check already held.
        print('Recovered interrupted material override after owner identity ended', flush=True)
    config.write_text(override_text, encoding='utf-8')
    env = os.environ.copy()
    env['WWO_VISUAL_OUTPUT'] = output.as_posix()
    env['WWO_VISUAL_UI_ONLY'] = '1' if args.ui_only else '0'
    env['WWO_VISUAL_WATER_ONLY'] = '1' if args.water_only else '0'
    env['WWO_VISUAL_STABILITY'] = '1' if args.stability else '0'
    env['WWO_VISUAL_PLACES'] = args.places
    env['WWO_VISUAL_MPP'] = str(args.mpp)
    env['WWO_VISUAL_TERRAIN_BATCH'] = '1' if args.terrain_batch else '0'
    env['WWO_VISUAL_MODE_REVIEW'] = '1' if args.mode_review else '0'
    env['WWO_VISUAL_ADMIN_OFF'] = '1' if args.admin_lines_off else '0'
    env['WWO_VISUAL_DYNAMIC'] = '1' if args.dynamic else '0'
    env['WWO_VISUAL_FOUNDATION'] = '1' if args.foundation_review else '0'
    env['WWO_VISUAL_ACCEPTANCE'] = args.acceptance or ''
    env['WWO_RESIDENT_CASE'] = args.resident_case or ''
    env['WWO_EMPLOYMENT_CASE'] = args.employment_case or ''
    env['WWO_CONTINUOUS_DAYS'] = str(args.continuous_days or '')
    env['WWO_CONTINUOUS_RESUME'] = '1' if args.resume_continuous else '0'
    env['WWO_LIVING_UI'] = 'preview' if args.preview_only else 'play' if args.living_ui else ''
    env['WWO_MATERIAL_TRADE'] = '1' if args.material_trade else '0'
    env['WWO_MATERIAL_RESUME'] = '1' if args.resume_material else '0'
    env['WWO_VISUAL_NO_IMAGES'] = '1' if args.summary_only else '0'
    archive = output.parent / 'runs.json.gz' if args.compact_record else None
    if archive and args.material_trade: archive=archive.with_name('material-trade-runs.json.gz')
    env['WWO_VISUAL_RECORD_ARCHIVE'] = archive.as_posix() if archive else ''
    command = [str(executable)]
    if not args.exe:
        command += ['--path', str(ROOT)]
    command += ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--', '--r57-terrain-probe']
    if args.domain_check:
        if args.exe or not (args.living_ui or args.material_trade): raise ValueError('Domain check uses source and an existing isolated test directory')
        command += ['--native-material-trade' if args.material_trade and not args.domain_regression else '--native-multi-employer']
        command[1:1] = ['--headless', '--script', 'res://tests/formal/formal_personal_economy_test.gd']
    if args.native_case:
        command.append({'feedback':'--formal-economy-feedback','regional':'--formal-regional-economy','stratified':'--formal-stratified-economy'}[args.native_case])
    if args.single_employer: command.append('--formal-single-employer-opening')
    if args.employment_case in ['opportunity','arrears']: command.append('--formal-employment-' + args.employment_case)
    process = None
    memory = []
    environment = []
    try:
        log_path = output / 'runtime.log'
        with log_path.open('w', encoding='utf-8') as log:
            process = subprocess.Popen(command, cwd=folder, env=env, stdout=log, stderr=subprocess.STDOUT)
            began = time.monotonic()
            class MemoryCounters(ctypes.Structure):
                _fields_ = [('cb',ctypes.c_uint32),('faults',ctypes.c_uint32)] + [(name,ctypes.c_size_t) for name in ['peak_working','working','peak_paged','paged','peak_nonpaged','nonpaged','pagefile','peak_pagefile','private']]
            if os.name=='nt' and args.acceptance:
                get_memory=ctypes.windll.psapi.GetProcessMemoryInfo
                get_memory.argtypes=[ctypes.c_void_p,ctypes.POINTER(MemoryCounters),ctypes.c_uint32]
                class PowerStatus(ctypes.Structure):
                    _fields_=[('ac',ctypes.c_ubyte),('flags',ctypes.c_ubyte),('percent',ctypes.c_ubyte),('saver',ctypes.c_ubyte),('life',ctypes.c_uint32),('full_life',ctypes.c_uint32)]
                class ProcessEntry(ctypes.Structure):
                    _fields_=[('size',ctypes.c_uint32),('usage',ctypes.c_uint32),('pid',ctypes.c_uint32),('heap',ctypes.c_size_t),('module',ctypes.c_uint32),('threads',ctypes.c_uint32),('parent',ctypes.c_uint32),('priority',ctypes.c_long),('flags',ctypes.c_uint32),('name',ctypes.c_wchar*260)]
                kernel=ctypes.windll.kernel32
                kernel.CreateToolhelp32Snapshot.argtypes=[ctypes.c_uint32,ctypes.c_uint32]
                kernel.CreateToolhelp32Snapshot.restype=ctypes.c_void_p
                for method in [kernel.Process32FirstW,kernel.Process32NextW]:
                    method.argtypes=[ctypes.c_void_p,ctypes.POINTER(ProcessEntry)]
                kernel.CloseHandle.argtypes=[ctypes.c_void_p]
            deadline = time.monotonic() + (2400 if args.acceptance=='dynamic' else 900 if args.acceptance else 720 if args.stability or args.mode_review or args.dynamic or args.foundation_review else 210)
            while process.poll() is None:
                time.sleep(.5)
                if os.name=='nt' and args.acceptance and (not memory or time.monotonic()-began-memory[-1][0]/1000>=2):
                    counters=MemoryCounters();counters.cb=ctypes.sizeof(counters)
                    if get_memory(int(process._handle),ctypes.byref(counters),counters.cb):memory.append([round((time.monotonic()-began)*1000),counters.working,counters.private])
                    power=PowerStatus();kernel.GetSystemPowerStatus(ctypes.byref(power))
                    others=[];entry=ProcessEntry();entry.size=ctypes.sizeof(entry)
                    handle=kernel.CreateToolhelp32Snapshot(2,0)
                    try:
                        if handle==ctypes.c_void_p(-1).value:raise ctypes.WinError()
                        found=kernel.Process32FirstW(handle,ctypes.byref(entry))
                        while found:
                            if entry.pid!=process.pid and ('godot' in entry.name.lower() or entry.name.lower().startswith('wwo')):others.append([entry.pid,entry.name])
                            found=kernel.Process32NextW(handle,ctypes.byref(entry))
                    finally:
                        if handle!=ctypes.c_void_p(-1).value:kernel.CloseHandle(handle)
                    environment.append({'ms':round((time.monotonic()-began)*1000),'ac':power.ac,'percent':power.percent,'other_godot':others})
                    # A late external occupant invalidates timing, not gameplay.
                    # Do not interrupt this work line because another one starts.
                if log_path.stat().st_size > 128 * 1024 or 'SCRIPT ERROR:' in log_path.read_text(encoding='utf-8') or time.monotonic() > deadline:
                    raise RuntimeError('Finite run stopped: script error, log budget or deadline; inspect runtime.log')
            print('exit', process.returncode)
        print(log_path.read_text(encoding='utf-8')[-5000:])
        if process.returncode:
            raise RuntimeError('Godot finite capture failed')
    finally:
        if process and process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        if config.exists() and config.read_text(encoding='utf-8') != override_text:
            raise RuntimeError('Observer configuration changed by another writer; retained')
        if original_visual_config is not None:
            config.write_bytes(original_visual_config)
        else:
            config.unlink(missing_ok=True)
        if memory and args.summary_only:
            record = output / ('economic-action.json' if args.acceptance == 'economic-action' else args.acceptance + '.json')
            record_key = output.name + '/' + record.stem
            records = json.loads(gzip.decompress(archive.read_bytes()).decode('utf-8')) if archive and archive.is_file() else {}
            if record.is_file() or record_key in records:
                summary = records[record_key] if archive else json.loads(record.read_text(encoding='utf-8'))
                summary['process_summary'] = {'samples':len(memory),'peak_working_bytes':max(x[1] for x in memory),'peak_private_bytes':max(x[2] for x in memory),'ac_values':sorted(set(x['ac'] for x in environment)),'other_godot_seen':any(x['other_godot'] for x in environment),'functional_gpu_sharing':args.functional_gpu_sharing,'timing_environment_valid':not args.functional_gpu_sharing and all(not x['other_godot'] and x['ac']==1 for x in environment)}
                if archive:
                    records[record_key] = summary
                    archive.write_bytes(gzip.compress(json.dumps(records,ensure_ascii=False,separators=(',',':')).encode('utf-8')))
                else:
                    record.write_text(json.dumps(summary,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
        elif memory:
            (output/'process-memory.json').write_text(json.dumps({'pid':process.pid,'columns':['ms','working_set_bytes','private_bytes'],'samples':memory,'environment':environment,'note':'Actual candidate process including finite diagnostic buffers. Environment sampled every2s through Toolhelp/GetSystemPowerStatus; no GPU readback.'},separators=(',',':')),encoding='utf-8')


if __name__ == '__main__':
    if '--native-screenshot-review' in sys.argv or '--terrain-region-review' in sys.argv or '--terrain-a0-review' in sys.argv:
        main()
    else:
        with resource_slot():
            main()
