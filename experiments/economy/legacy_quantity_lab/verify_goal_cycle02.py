"""Verify existing complete Cycle02 evidence without rewriting any golden output.

For fresh execution, use the frozen runner twice, controls once, then this entry.
This verifier reconstructs facts, verifies every complete file/hash set, original
source continuity, and explicit causal/negative/observer boundaries.
"""
from pathlib import Path
import argparse,subprocess,sys,json,hashlib
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle02'))
from causal_audit import audit as causal_audit
sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle01'))
from offline_audit import audit as accounting_audit

def check(v,message):
    if not v:raise ValueError(message)

def hashes(path):
    return {p.relative_to(path).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(path.rglob('*')) if p.is_file() and p.name not in ('performance.json','execution.json','hash_manifest.json')}

def main():
    a=argparse.ArgumentParser(description=__doc__);a.add_argument('--evidence-root',type=Path,default=ROOT/'.local/cycle02');a.add_argument('--output',type=Path,required=True);x=a.parse_args();p=x.evidence_root
    if x.output.exists():a.error('New verification result path required')
    record=dict(status='FAIL')
    try:
        old=json.loads((ROOT/'GOAL_STATE.json').read_text())['current_code_digest']
        check(all(hashlib.sha256((ROOT/k).read_bytes()).hexdigest()==v for k,v in old.items()),'Cycle01 source changed')
        mp=ROOT/'experiments_manifest_cycle02_final.json'
        if not mp.exists():mp=ROOT/'experiments_manifest_cycle02.json'
        m=json.loads(mp.read_text());ids={s['case_id'] for s in m['cases']}
        results=[]
        for name in ('replay_a','replay_b'):
            d=p/name;e=json.loads((d/'execution.json').read_text());check(e['status']=='PASS','replay not complete '+name);check(set(e['completed'])==ids,'incomplete formal set '+name)
            fm=json.loads((d/'hash_manifest.json').read_text());check(fm['files']==hashes(d),'saved file/hash manifest mismatch '+name)
            for spec in m['cases']:
                c=d/spec['case_id'];initial=json.loads((c/'initial.json').read_text())['case']
                check(initial==spec['config'],'frozen case differs from executed input')
                check(accounting_audit(c)['status']=='PASS','offline dual audit fails');check(causal_audit(c)['status']=='PASS','causal audit fails')
            results.append(fm)
        check(results[0]==results[1],'independent process complete-file hashes differ')
        control=json.loads((p/'controls/checks.json').read_text());check(all(control[k]=='PASS' for k in ('observer_600','observer_3600','nominal_unit_N2','nominal_unit_N3','container_and_request_order')),'observer/unit/order control fails')
        corrupt=json.loads((p/'corruptions/results.json').read_text());check(len(corrupt)>=8 and all(c['status']=='PASS_EXPECTED_REJECTION' for c in corrupt),'negative probes incomplete')
        historical=list((p/'m0/full').glob('final-verification-*/verification.json'));check(len(historical)==1 and json.loads(historical[0].read_text())['status']=='PASS','historical/frozen verification not complete')
        record.update(status='PASS',cases_each=len(ids),days_each=sum(s['config']['days'] for s in m['cases']),audits_each=len(ids),independent_processes=2,matched_files=len(results[0]['files']),negative_probes=len(corrupt),control_cases=json.loads((p/'controls/execution.json').read_text())['cases'],source_continuity='PASS',causal_attribution='PASS',remote_CI='NOT_RUN; no publication authorized')
    except (ValueError,KeyError,OSError,AssertionError,StopIteration) as e:record['error']=str(e)
    x.output.parent.mkdir(parents=True,exist_ok=True);x.output.write_text(json.dumps(record,indent=2,sort_keys=True)+'\n');print(json.dumps(record,indent=2));return 0 if record['status']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())
