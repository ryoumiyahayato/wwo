#!/usr/bin/env python3
"""Run all retained experiments, Task 4, then Task 5 on the real pinned engine."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time

VERSION='4.6.3.stable.official.7d41c59c4'
BASE='f80cc6ce0752a53f6a6dabc7913db45a7735046c'
FATAL=re.compile(r'(?im)^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Assertion failed|[1-9][0-9]* failures')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[3]
    out=Path(args.output).resolve(); out.mkdir(parents=True,exist_ok=True)
    steps=[]
    def digest():
        paths=sorted(p for p in (root/'experiments/war_resolver').rglob('*') if p.suffix in ['.gd','.py'])
        return {p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    sources=digest()
    def run(name,cmd,timeout=1800):
        start=time.perf_counter()
        p=subprocess.run(cmd,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
        text=p.stdout.decode('utf-8',errors='replace'); (out/f'{name}.log').write_text(text,encoding='utf-8')
        passed=p.returncode==0 and FATAL.search(text) is None
        steps.append(dict(name=name,passed=passed,exit=p.returncode,command=cmd,wall_seconds=time.perf_counter()-start))
        (out/'validation.json').write_text(json.dumps(steps,indent=2),encoding='utf-8')
        print(('PASS ' if passed else 'FAIL ')+name,flush=True)
        if not passed: raise RuntimeError(text[-6000:])
        return text
    try:
        version=run('version',[args.godot,'--version']).strip()
        if version!=VERSION: raise RuntimeError('Pinned version mismatch')
        run('predecessors',[sys.executable,'-B','experiments/war_resolver/aggregation/validate.py',
            '--godot',args.godot,'--output',str(out/'predecessors')],timeout=3600)
        inherited=json.loads((out/'predecessors/evidence.json').read_text())
        expected={'replay-a':('REPLAY_SHA256','3c369000cbf20ed19fb53d20dde0f47fea9f025a5c1ee32a010cc332b0d92904'),
          'role-replay-a':('ROLE_REPLAY_SHA256','60d41290019b0efeaa7e21bee3201461a912cff8bfb838642cfe8ae6ef83b3e3'),
          'sandbox-replay-a':('SANDBOX_REPLAY_SHA256','a079c498616d72209811861d72fad70ccab5dd6ea3c13bceedcaed3ad8882390')}
        hashes={}
        for name,(prefix,value) in expected.items():
            log=(out/'predecessors/retained'/f'{name}.log').read_text()
            if re.findall(prefix+r'=([a-f0-9]{64})',log)!=[value]: raise RuntimeError(name+' changed')
            hashes[name]=value
        if inherited['replay_sha256']!='73c47a49ca73e026227324581975b1315b9386183a21da022827d30e37a646f3':
            raise RuntimeError('Unbound Task 4 replay changed')
        headless=[args.godot,'--headless','--path',str(root),'--script']
        log=run('tests',headless+['res://experiments/war_resolver/structure/tests.gd'])
        match=re.search(r'Task5 structure: (\d+) checks, 0 failures',log)
        if not match or int(match[1])==0: raise RuntimeError('Missing successful checks')
        tests=[json.loads(line.split('=',1)[1]) for line in log.splitlines() if line.startswith('TASK5_EVIDENCE_JSON=')]
        replay=[]
        for name in ['replay-a','replay-b']:
            log=run(name,headless+['res://experiments/war_resolver/structure/replay_probe.gd'])
            values=re.findall(r'TASK5_REPLAY_SHA256=([a-f0-9]{64})',log)
            if len(values)!=1: raise RuntimeError('Missing replay hash')
            replay+=values
        if replay[0]!=replay[1]: raise RuntimeError('Fresh-process replay mismatch')
        log=run('benchmark',headless+['res://experiments/war_resolver/structure/benchmark.gd'])
        benches=[json.loads(line.split('=',1)[1]) for line in log.splitlines() if line.startswith('TASK5_BENCHMARK_JSON=')]
        if len(tests)!=1 or len(benches)!=6: raise RuntimeError('Incomplete evidence')
        indexed={b['case']:b for b in benches}
        a=indexed['40_aggregate_one_attachment']; b=indexed['40_aggregate_sleeping_attachment']
        for key in ['structure_work','lod_work','combat_work','active_sides']:
            if a[key]!=b[key]: raise RuntimeError('Sleeping work/outcomes changed: '+key)
        if sources!=digest(): raise RuntimeError('Source changed during validation')
        evidence=dict(version=version,base=BASE,validation_head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
            source_digest=sources,checks=int(match[1]),failures=0,replay_sha256=replay[0],tests=tests[0],benchmark=benches,
            retained_hashes=hashes,task4_replay_sha256=inherited['replay_sha256'],task4_checks=inherited['checks'])
        (out/'evidence.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
        print(f'PASS Task5: {match[1]} checks; replay={replay[0]}',flush=True)
    except (RuntimeError,OSError,subprocess.TimeoutExpired) as exc:
        print(str(exc),file=sys.stderr); return 1
    return 0

if __name__=='__main__': raise SystemExit(main())
