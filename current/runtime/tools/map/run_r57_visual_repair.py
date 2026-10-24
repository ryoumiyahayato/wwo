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

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('label', choices=['before', 'after', 'candidate', 'comparison'])
    parser.add_argument('--exe', type=Path)
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
    parser.add_argument('--single-employer', action='store_true', help='Retain the original generation18 Opening for compatibility')
    parser.add_argument('--summary-only', action='store_true', help='Keep compact existing run records; skip optional screenshots and memory series')
    parser.add_argument('--compact-record', action='store_true', help='Append existing result records into one compressed JSON file; requires summary-only')
    args = parser.parse_args()
    if args.compact_record and not args.summary_only:
        raise ValueError('Compact records require summary-only')
    output = ROOT / ('local-artifacts/r57_stability' if args.stability else 'local-artifacts/r57_visual_repair') / args.label
    if args.output_dir:
        output=args.output_dir.resolve()
        if not output.is_relative_to(ROOT/'local-artifacts'):raise ValueError('Observer output must stay in local-artifacts')
    output.mkdir(parents=True, exist_ok=True)
    executable = args.exe.resolve() if args.exe else Path('D:/Tools/Godot-4.6.3/Godot_v4.6.3-stable_win64.exe')
    folder = executable.parent if args.exe else ROOT
    config = folder / 'override.cfg'
    if config.exists():
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
    config.write_text('[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_dir_name + '"\n'
                      'run/main_scene="' + scene.as_posix() + '"\n[display]\nwindow/size/viewport_width=1280\n'
                      'window/size/viewport_height=720\nwindow/size/window_width_override=1280\nwindow/size/window_height_override=720\n', encoding='utf-8')
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
    env['WWO_VISUAL_NO_IMAGES'] = '1' if args.summary_only else '0'
    archive = output.parent / 'runs.json.gz' if args.compact_record else None
    env['WWO_VISUAL_RECORD_ARCHIVE'] = archive.as_posix() if archive else ''
    command = [str(executable)]
    if not args.exe:
        command += ['--path', str(ROOT)]
    command += ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--', '--r57-terrain-probe']
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
                    if args.acceptance in ['performance','economic-action'] and (others or power.ac!=1):
                        raise RuntimeError('Comparable timing stopped: another Godot process or AC power change; only owned EXE will exit')
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
        config.unlink(missing_ok=True)
        if memory and args.summary_only:
            record = output / ('economic-action.json' if args.acceptance == 'economic-action' else args.acceptance + '.json')
            record_key = output.name + '/' + record.stem
            records = json.loads(gzip.decompress(archive.read_bytes()).decode('utf-8')) if archive and archive.is_file() else {}
            if record.is_file() or record_key in records:
                summary = records[record_key] if archive else json.loads(record.read_text(encoding='utf-8'))
                summary['process_summary'] = {'samples':len(memory),'peak_working_bytes':max(x[1] for x in memory),'peak_private_bytes':max(x[2] for x in memory),'ac_values':sorted(set(x['ac'] for x in environment)),'other_godot_seen':any(x['other_godot'] for x in environment)}
                if archive:
                    records[record_key] = summary
                    archive.write_bytes(gzip.compress(json.dumps(records,ensure_ascii=False,separators=(',',':')).encode('utf-8')))
                else:
                    record.write_text(json.dumps(summary,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
        elif memory:
            (output/'process-memory.json').write_text(json.dumps({'pid':process.pid,'columns':['ms','working_set_bytes','private_bytes'],'samples':memory,'environment':environment,'note':'Actual candidate process including finite diagnostic buffers. Environment sampled every2s through Toolhelp/GetSystemPowerStatus; no GPU readback.'},separators=(',',':')),encoding='utf-8')


if __name__ == '__main__':
    main()
