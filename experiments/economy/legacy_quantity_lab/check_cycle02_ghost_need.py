"""Ninth exact negative proof: conserved quantity assigned to an unknown need."""
from pathlib import Path
import sys,json,importlib.util,hashlib
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle02'))
from causal_audit import audit,records
SOURCE=ROOT/'.local/cycle02/replay_a/M2_T_EQUAL_FEASIBLE_P_HETEROGENEOUS_R_PRICE_FIRST_600'
OUT=ROOT/'.local/cycle02/corruptions/GHOST_ACCEPTED_NEED.jsonl'
if OUT.exists():raise ValueError('Do not overwrite a preserved negative trace')
changed=None
with OUT.open('w') as target:
    for line in records(SOURCE/'causal.jsonl'):
        r=json.loads(line)
        if changed is None and r['event']=='request' and r['request']['accepted_quantity']>0:
            changed=dict(day=r['day'],order_id=r['request']['order_id'],original=dict(r['request']['accepted_lines']),quantity=r['request']['accepted_quantity'])
            r['request']['accepted_lines']={'GHOST_NEED':r['request']['accepted_quantity']}
            target.write(json.dumps(r,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n')
        else:target.write(line)
spec=importlib.util.spec_from_file_location('causal_execution_v3',ROOT/'.local/cycle02/audit_versions/causal_audit_v3.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
old_result=old.audit(SOURCE,OUT)
assert old_result['status']=='PASS','Historical audit hole was not reproduced'
try:audit(SOURCE,OUT)
except ValueError as error:proof=dict(name='GHOST_ACCEPTED_NEED_WITH_CONSERVED_TOTAL',status='PASS_EXPECTED_REJECTION',checker='causal_v4',error=str(error),exact_change=changed,old_execution_checker_status=old_result['status'],old_strong_count=old_result['price_sensitive_first_round_accepted_needs'],current_checker_sha256=hashlib.sha256((ROOT/'economy_quantity_lab/goal_cycle02/causal_audit.py').read_bytes()).hexdigest(),source=SOURCE.relative_to(ROOT).as_posix())
else:raise AssertionError('Ghost need was accepted by final checker')
p=ROOT/'.local/cycle02/corruptions/results.json';r=json.loads(p.read_text());assert len(r)==8;r.append(proof);p.write_text(json.dumps(r,indent=2,sort_keys=True)+'\n')
print(json.dumps(proof,indent=2))
