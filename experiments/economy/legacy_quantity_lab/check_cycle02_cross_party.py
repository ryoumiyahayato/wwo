"""Tenth negative: swap equal-value/date orders across two real buyer requests."""
from pathlib import Path
import sys,json,importlib.util,hashlib
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle02'))
from causal_audit import audit,records
SOURCE=ROOT/'.local/cycle02/replay_a/M2_T_EQUAL_FEASIBLE_P_HETEROGENEOUS_R_PRICE_FIRST_600'
OUT=ROOT/'.local/cycle02/corruptions/SWAPPED_ORDER_PARTIES.jsonl'
if OUT.exists():raise ValueError('Preserve original negative evidence')
rows=[];selected=None
for line in records(SOURCE/'causal.jsonl'):
 r=json.loads(line)
 if r['event']=='request' and r['request']['accepted_quantity']>0:
  q=r['request']
  for old in rows:
   if (old['request_day'],old['accepted_quantity'],old['posted_price'])==(q['request_day'],q['accepted_quantity'],q['posted_price']) and old['buyer_id']!=q['buyer_id']:selected=(old,q);break
  if selected:break
  rows.append(q)
assert selected
first,second=selected;swap={first['request_id']:second['order_id'],second['request_id']:first['order_id']}
with OUT.open('w') as target:
 for line in records(SOURCE/'causal.jsonl'):
  r=json.loads(line)
  if r['event']=='request' and r['request']['request_id'] in swap:
   r['request']['order_id']=swap[r['request']['request_id']];target.write(json.dumps(r,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n')
  else:target.write(line)
spec=importlib.util.spec_from_file_location('causal_execution_v3',ROOT/'.local/cycle02/audit_versions/causal_audit_v3.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
old_result=old.audit(SOURCE,OUT);assert old_result['status']=='PASS'
try:audit(SOURCE,OUT)
except ValueError as error:proof=dict(name='SWAPPED_ORDER_IDS_SAME_DATE_QUANTITY_PRICE_DIFFERENT_BUYER',status='PASS_EXPECTED_REJECTION',checker='causal_v4',error=str(error),old_execution_checker_status='PASS',swap=swap,source=SOURCE.relative_to(ROOT).as_posix(),checker_sha256=hashlib.sha256((ROOT/'economy_quantity_lab/goal_cycle02/causal_audit.py').read_bytes()).hexdigest())
else:raise AssertionError('Cross-party order association accepted')
p=ROOT/'.local/cycle02/corruptions/results.json';result=json.loads(p.read_text());assert len(result)==9;result.append(proof);p.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps(proof,indent=2))
