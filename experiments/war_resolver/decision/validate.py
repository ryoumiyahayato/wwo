#!/usr/bin/env python3
"""Pinned, sequential Tasks 1-8, retained regressions, unified suite and audit.

All entry points and old tolerances are retained. Milliseconds are observations.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

VERSION = '4.6.3.stable.official.7d41c59c4'
BASE = '4145a123b583a6a43c9777d24aff4288248aa924'
EXPECTED = {
    'resolver': '3c369000cbf20ed19fb53d20dde0f47fea9f025a5c1ee32a010cc332b0d92904',
    'roles': '60d41290019b0efeaa7e21bee3201461a912cff8bfb838642cfe8ae6ef83b3e3',
    'sandbox': 'a079c498616d72209811861d72fad70ccab5dd6ea3c13bceedcaed3ad8882390',
    'task4': '73c47a49ca73e026227324581975b1315b9386183a21da022827d30e37a646f3',
    'task5': 'c2da3bc13475afb8540ccae93d49b7ce8a5ba072f7c2c4e768ad6f0f7cded664',
    'task6': '0245979431dca576e2194e884011572d632a1bcdc7c22cc3cd2eea4fb99698f1',
    'task7': '3528e2eafc4a4945750cb21451a1855db0fd4200ec76809970414c7d8ba9b17e',
}
FATAL = re.compile(r'(?im)^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Assertion failed|[1-9][0-9]* failures')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    env['GIT_OPTIONAL_LOCKS'] = '0'
    steps, hashes, checks, benches = [], {}, {}, {}

    def git(*arguments):
        return subprocess.check_output(['git', *arguments], cwd=root, env=env, text=True, encoding='utf-8').strip()

    def digest():
        paths = sorted(p for p in (root/'experiments/war_resolver').rglob('*') if p.suffix in ['.gd', '.py'])
        return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

    sources = digest()
    (out/'source-before.json').write_text(json.dumps(sources, indent=2), encoding='utf-8')

    def run(name, command, timeout=1800, unified=False):
        start = time.perf_counter()
        p = subprocess.run(command, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        text = p.stdout.decode('utf-8', errors='replace')
        code = p.returncode
        (out/f'{name}.log').write_text(text, encoding='utf-8')
        # The unchanged official suite explicitly permits this retained fixture
        # shutdown diagnostic. Preserve it in the raw log and record occurrences.
        allowed = re.findall(r'(?m)^ERROR: 41 resources still in use at exit.*$', text) if unified else []
        scanned = re.sub(r'(?m)^ERROR: 41 resources still in use at exit.*$', '', text) if unified else text
        passed = code == 0 and FATAL.search(scanned) is None
        steps.append(dict(name=name, passed=passed, exit=code, command=command,
                          wall_seconds=time.perf_counter()-start,
                          retained_shutdown_diagnostics=len(allowed)))
        (out/'validation.json').write_text(json.dumps(steps, indent=2), encoding='utf-8')
        print(('PASS ' if passed else 'FAIL ')+name, flush=True)
        if not passed:
            raise RuntimeError(text[-7000:])
        return text

    def records(text, prefix, count):
        result = [json.loads(line.split('=', 1)[1]) for line in text.splitlines() if line.startswith(prefix+'=')]
        if len(result) != count:
            raise RuntimeError(f'Incomplete {prefix}: {len(result)} != {count}')
        return result

    def count(text, prefix):
        result = re.findall(re.escape(prefix)+r': (\d+) checks, 0 failures', text)
        if len(result) != 1 or int(result[0]) == 0:
            raise RuntimeError('Missing nonzero checks: '+prefix)
        return int(result[0])

    try:
        if git('branch', '--show-current') != 'experiment/military-decision-contract-v0-20261007':
            raise RuntimeError('Not the dedicated Task 8 branch')
        chain = ['622b260bc641036c23efbf6345a548485ac6c475', '524b669214469e4b343830afef8f4ef8768ec225',
                 '4c52ec37082d27c0d7b99359cfb165ae36878f15', '3e80a827f457cf0b3bf146ca765fb6adeb41b57a',
                 'f80cc6ce0752a53f6a6dabc7913db45a7735046c', '1373c5b8d8255d860a08d6c778d1ec91fedad4a7', '15f9f652ba9c2016f3851ff03379684c13c6ba6f', BASE, git('rev-parse', 'HEAD')]
        for a, b in zip(chain, chain[1:]):
            if subprocess.run(['git', 'merge-base', '--is-ancestor', a, b], cwd=root, env=env).returncode:
                raise RuntimeError('STACK INVALID')
        protected = ['experiments/war_resolver/tests.gd', 'experiments/war_resolver/role_tests.gd',
                     'experiments/war_resolver/sandbox', 'experiments/war_resolver/aggregation/tests.gd',
                     'experiments/war_resolver/structure/tests.gd', 'experiments/war_resolver/logistics', 'experiments/war_resolver/information/tests.gd', 'experiments/war_resolver/information/replay_probe.gd', 'experiments/war_resolver/information/benchmark.gd', 'experiments/war_resolver/information/fixtures.gd', 'experiments/war_resolver/information/validate.py', 'scripts', 'scenes', 'data', 'tests', 'tools', 'project.godot']
        if git('diff', '--name-only', BASE, '--', *protected):
            raise RuntimeError('Protected predecessor tests or production files changed')
        if run('version', [args.godot, '--version']).strip() != VERSION:
            raise RuntimeError('Pinned Godot version mismatch')
        legacy = out/'retained-experiments'
        run('tasks1_2_3', [sys.executable, '-B', 'experiments/war_resolver/validate.py', '--godot', args.godot, '--output', str(legacy)], timeout=1800)
        for key, name, prefix in [('resolver', 'replay-a', 'REPLAY_SHA256'), ('roles', 'role-replay-a', 'ROLE_REPLAY_SHA256'), ('sandbox', 'sandbox-replay-a', 'SANDBOX_REPLAY_SHA256')]:
            text = (legacy/f'{name}.log').read_text(encoding='utf-8')
            if re.findall(prefix+r'=([a-f0-9]{64})', text) != [EXPECTED[key]]:
                raise RuntimeError('Retained replay changed: '+key)
            hashes[key] = EXPECTED[key]
        for key, name, prefix in [('resolver', 'resolver-tests', 'War resolver'), ('roles', 'role-tests', 'Role overrides'), ('sandbox', 'sandbox-tests', 'War sandbox')]:
            checks[key] = count((legacy/f'{name}.log').read_text(encoding='utf-8'), prefix)
        tests = {}
        headless = [args.godot, '--headless', '--path', str(root), '--script']
        for key, folder, number, prefix, bench_count in [('task4', 'aggregation', 4, 'Task4 aggregation', 10), ('task5', 'structure', 5, 'Task5 structure', 6), ('task6', 'logistics', 6, 'Task6 logistics', 9), ('task7', 'information', 7, 'Task7 information', 10), ('task8', 'decision', 8, 'Task8 decision', 10)]:
            text = run(key+'_tests', headless+[f'res://experiments/war_resolver/{folder}/tests.gd'])
            checks[key] = count(text, prefix)
            tests[key] = records(text, f'TASK{number}_EVIDENCE_JSON', 1)[0]
            replay = []
            for suffix in ['a', 'b']:
                text = run(key+'_replay_'+suffix, headless+[f'res://experiments/war_resolver/{folder}/replay_probe.gd'])
                values = re.findall(f'TASK{number}_REPLAY_SHA256=([a-f0-9]{{64}})', text)
                if len(values) != 1:
                    raise RuntimeError('Missing replay: '+key)
                replay += values
            if replay[0] != replay[1] or key in EXPECTED and replay[0] != EXPECTED[key]:
                raise RuntimeError('Replay changed: '+key)
            hashes[key] = replay[0]
            text = run(key+'_benchmark', headless+[f'res://experiments/war_resolver/{folder}/benchmark.gd'])
            benches[key] = records(text, f'TASK{number}_BENCHMARK_JSON', bench_count)
        indexed = {row['case']: row for row in benches['task4']}
        for a, b in [('40_formation', '40_formation_sleeping'), ('100_sparse', '100_sparse_sleeping')]:
            if indexed[a]['resolution_work'] != indexed[b]['resolution_work'] or indexed[a]['summary']['sides'] != indexed[b]['summary']['sides']:
                raise RuntimeError('Task 4 sleeping model regressed')
        indexed = {row['case']: row for row in benches['task5']}
        for key in ['structure_work', 'lod_work', 'combat_work', 'active_sides']:
            if indexed['40_aggregate_one_attachment'][key] != indexed['40_aggregate_sleeping_attachment'][key]:
                raise RuntimeError('Task 5 sleeping model regressed: '+key)
        indexed = {row['case']: row for row in benches['task6']}
        for key in ['logistics_work', 'lod_work', 'combat_work', 'active_stocks', 'active_sides']:
            if indexed['40_formation'][key] != indexed['40_formation_sleeping'][key]:
                raise RuntimeError('Task 6 sleeping model regressed: '+key)
        for name in ['40_formation', '100_formation']:
            if indexed[name]['logistics_work']['leaves_materialized_for_logistics'] != 0 or indexed[name]['lod_work']['leaf_records_materialized'] != 0:
                raise RuntimeError('Formation receipt materialized leaves')
        if indexed['100_specific_leaf']['logistics_work']['leaves_materialized_for_logistics'] != 1:
            raise RuntimeError('Specific receipt was not minimal')
        if indexed['1000_future']['logistics_work']['deliveries_processed'] != 3 or indexed['1000_future']['logistics_work']['future_deliveries_examined'] != 0:
            raise RuntimeError('Future deliveries scanned')
        indexed = {row['case']: row for row in benches['task7']}
        for key in ['information_work', 'lod_work', 'combat_work', 'active_stocks', 'active_sides']:
            if indexed['delayed_report'][key] != indexed['40_sleeping_report'][key]:
                raise RuntimeError('Task 7 sleeping model regressed: '+key)
        for name in ['100_formation_report', '100_leaf_report']:
            if indexed[name]['information_work']['leaves_materialized_for_information'] != 0 or indexed[name]['lod_work']['leaf_records_materialized'] != 0:
                raise RuntimeError('Observations materialized leaves')
        pending = indexed['1000_pending_3_due']
        if pending['information_work']['messages_delivered'] != 3 or pending['information_work']['future_messages_examined'] != 0 or pending['pending_reports'] != 997:
            raise RuntimeError('Future message work regressed')
        indexed = {row['case']: row for row in benches['task8']}
        for key in ['decision_work', 'combat_work', 'lod_work', 'stocks', 'active_sides']:
            if indexed['delayed_command'][key] != indexed['40_sleeping_decision'][key]:
                raise RuntimeError('Task 8 sleeping model regressed: '+key)
        for row in indexed.values():
            if row['decision_work']['world_truth_reads_for_decision'] != 0 or row['decision_work']['future_persons_examined'] != 0 or not row['parity']:
                raise RuntimeError('Decision information/performance boundary regressed')
        few = indexed['1000_persons_3_due']
        if few['decision_work']['persons_examined'] != 3 or few['decision_work']['decision_events_processed'] != 3 or few['pending_events'] != 997:
            raise RuntimeError('Future person scan or missing opportunities')
        if indexed['100_aggregate_commander']['lod_work']['leaf_records_materialized'] != 0:
            raise RuntimeError('Macro commander context materialized leaves')
        spec = importlib.util.spec_from_file_location('retained', root/'experiments/war_resolver/validate.py')
        retained = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(retained)
        regression_checks = {}
        for script in retained.REGRESSIONS:
            text = run(Path(script).stem, headless+['res://'+script], timeout=900)
            summaries = re.findall(r'\b([1-9][0-9]*) checks, 0 failures', text)
            if not summaries:
                raise RuntimeError('Missing regression summary: '+script)
            regression_checks[script] = list(map(int, summaries))
        text = run('unified', ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(root/'tools/run_validation.ps1'),
                              '-GodotPath', args.godot, '-ProjectPath', str(root), '-PythonPath', sys.executable], timeout=3600, unified=True)
        if 'Formal hemisphere world, long-term balance and retained service validation passed.' not in text:
            raise RuntimeError('Missing unified completion')
        unified_checks = sum(map(int, re.findall(r'\b([0-9]+) checks, 0 failures', text)))
        text = run('codex_audit', headless+['res://tests/codex_audit_regression.gd'])
        audit = re.findall(r'CODEX AUDIT REGRESSION PASSED: (\d+) checks', text)
        if audit != ['31'] or len(re.findall(r'(?m)^\[PASS\]', text)) != 31 or '[FAIL]' in text:
            raise RuntimeError('Missing audit summary')
        if sources != digest():
            raise RuntimeError('Code changed during validation')
        evidence = dict(version=VERSION, base=BASE, precommit_head=chain[-1], source_digest=sources,
                        checks=checks, failures=0, hashes=hashes, tests=tests, benchmark=benches,
                        retained_regression_checks=regression_checks, unified_godot_checks=unified_checks,
                        audit_checks=int(audit[0]), steps=steps,
                        production_integration='NONE', human_visual_acceptance='NOT REQUIRED / NOT RUN')
        (out/'evidence.json').write_text(json.dumps(evidence, indent=2)+'\n', encoding='utf-8')
        print('PASS Task8 frozen full validation: '+json.dumps(checks)+' replay='+hashes['task8'], flush=True)
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
