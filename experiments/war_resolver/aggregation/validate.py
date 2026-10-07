#!/usr/bin/env python3
"""Pinned real-engine retained validation first, then Task 4 correctness/evidence.

Absolute wall time is recorded, never a CI gate. No network dependency.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

FATAL = re.compile(r'(?im)^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Assertion failed|[1-9][0-9]* failures')
VERSION = '4.6.3.stable.official.7d41c59c4'

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--retained-evidence', help='Reuse a just-completed retained run only if source digest matches')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    results = []
    def run(name, command, timeout=1200):
        started = time.perf_counter()
        proc = subprocess.run(command, cwd=root, text=True, encoding='utf-8', errors='replace',
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        (out/f'{name}.log').write_text(proc.stdout, encoding='utf-8')
        passed = proc.returncode == 0 and FATAL.search(proc.stdout) is None
        results.append(dict(name=name, command=command, exit=proc.returncode, passed=passed,
                            wall_seconds=time.perf_counter()-started))
        (out/'validation.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
        print(('PASS ' if passed else 'FAIL ')+name, flush=True)
        if not passed:
            raise RuntimeError(proc.stdout[-5000:])
        return proc.stdout
    try:
        version = run('version', [args.godot, '--version']).strip()
        if version != VERSION: raise RuntimeError('Pinned Godot version mismatch')
        # Retained source fingerprint is captured by the caller after validation;
        # caching never silently replaces a run against changed predecessors.
        names=['battle_state.gd','resolver.gd','role_overrides.gd']
        def source_digest():
            paths=[root/'experiments/war_resolver'/n for n in names]
            paths += sorted((root/'experiments/war_resolver/aggregation').glob('*.gd'))
            return {str(p.relative_to(root)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
        digest=source_digest()
        if args.retained_evidence:
            retained=Path(args.retained_evidence)
            cached=json.loads((retained/'source-digest.json').read_text())
            legacy_prefix='experiments/war_resolver/aggregation/'
            previous={k:v for k,v in cached.items() if not k.startswith(legacy_prefix)}
            current={k:v for k,v in digest.items() if not k.startswith(legacy_prefix)}
            changed=subprocess.check_output(['git','diff','--name-only','3e80a827f457cf0b3bf146ca765fb6adeb41b57a','--',
                'experiments/war_resolver','scripts','tests','scenes','data','project.godot',
                ':(exclude)experiments/war_resolver/aggregation'],cwd=root,text=True).splitlines()
            if previous != current or set(changed)-set(current):
                raise RuntimeError('Retained source changed; rerun required')
            steps=json.loads((retained/'validation.json').read_text())
            if len(steps)!=18 or not all(s['passed'] and s['returncode']==0 for s in steps):
                raise RuntimeError('Retained evidence incomplete or failed')
        else:
            retained=out/'retained'
            run('retained', [sys.executable,'-B','experiments/war_resolver/validate.py','--godot',args.godot,
                             '--output',str(retained),'--regressions'], timeout=3600)
            (retained/'source-digest.json').write_text(json.dumps(digest,indent=2))
        run('import', [args.godot,'--headless','--editor','--path',str(root),'--quit'])
        prefix=[args.godot,'--headless','--path',str(root),'--script']
        log=run('tests',prefix+['res://experiments/war_resolver/aggregation/tests.gd'])
        count=re.search(r'Task4 aggregation: (\d+) checks, 0 failures',log)
        if not count or int(count[1])==0: raise RuntimeError('Missing successful check summary')
        evidence=[json.loads(l.split('=',1)[1]) for l in log.splitlines() if l.startswith('TASK4_EVIDENCE_JSON=')]
        if len(evidence)!=1: raise RuntimeError('Missing test evidence')
        hashes=[]
        for name in ['replay-a','replay-b']:
            probe=run(name,prefix+['res://experiments/war_resolver/aggregation/replay_probe.gd'])
            match=re.search(r'TASK4_REPLAY_SHA256=([a-f0-9]{64})',probe)
            if not match: raise RuntimeError('Missing replay hash')
            hashes.append(match[1])
        if hashes[0]!=hashes[1]: raise RuntimeError('Fresh-process replay differs')
        log=run('benchmark',prefix+['res://experiments/war_resolver/aggregation/benchmark.gd'])
        benchmark=[json.loads(l.split('=',1)[1]) for l in log.splitlines() if l.startswith('TASK4_BENCHMARK_JSON=')]
        if len(benchmark)!=10: raise RuntimeError('Incomplete benchmark')
        if source_digest()!=digest: raise RuntimeError('Sources changed during validation; rerun against a frozen source set')
        indexed={x['case']:x for x in benchmark}
        for a,b in [('40_formation','40_formation_sleeping'),('100_sparse','100_sparse_sleeping')]:
            if indexed[a]['resolution_work']!=indexed[b]['resolution_work'] or indexed[a]['summary']['sides']!=indexed[b]['summary']['sides']:
                raise RuntimeError('Sleeping-world work/outcome regression')
        head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
        bundle=dict(version=VERSION, base='3e80a827f457cf0b3bf146ca765fb6adeb41b57a',
                    precommit_head=head, source_digest=digest, checks=int(count[1]), failures=0,
                    replay_sha256=hashes[0], retained=str(retained), tests=evidence[0], benchmark=benchmark)
        (out/'evidence.json').write_text(json.dumps(bundle,indent=2),encoding='utf-8')
        print(f'PASS Task4: {count[1]} checks; replay={hashes[0]}; evidence={out}',flush=True)
    except (RuntimeError,OSError,subprocess.TimeoutExpired) as exc:
        print(str(exc),file=sys.stderr)
        return 1
    return 0

if __name__=='__main__':
    raise SystemExit(main())
