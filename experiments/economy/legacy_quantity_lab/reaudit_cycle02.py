"""Final v4 independent read-only re-audit of all completed formal archives."""
from pathlib import Path
import sys,json,hashlib,datetime,time
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle01'))
from offline_audit import audit as accounts
sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle02'))
from causal_audit import audit as causal
P=ROOT/'.local/cycle02';OUT=P/'final_reaudit_v4'
if OUT.exists():raise ValueError('New final audit directory required')
OUT.mkdir();sha=hashlib.sha256((ROOT/'economy_quantity_lab/goal_cycle02/causal_audit.py').read_bytes()).hexdigest();m=json.loads((ROOT/'experiments_manifest_cycle02_final.json').read_text());result=[];start=time.perf_counter()
for replay in ('replay_a','replay_b'):
 for spec in m['cases']:
  p=P/replay/spec['case_id'];a=accounts(p);c=causal(p)
  assert a==json.loads((p/'audit.json').read_text()),'accounting recheck differs from saved facts'
  assert c==json.loads((p/'causal_audit.json').read_text()),'new stronger audit changed actual count or fails saved facts'
  row=dict(replay=replay,case_id=spec['case_id'],accounts=a,causal=c,checker_version='v4-post-execution',causal_checker_sha256=sha)
  result.append(row);(OUT/(replay+'_'+spec['case_id']+'.json')).write_text(json.dumps(row,sort_keys=True,indent=2)+'\n')
  (OUT/'progress.json').write_text(json.dumps(dict(completed=len(result),total=118,last_case=spec['case_id']))+'\n')
 assert len([x for x in result if x['replay']==replay])==59
negative=[];default_source=P/'replay_a/M3_coal_scarcity_N3_L_BINDING_600'
for proof in json.loads((P/'corruptions/results.json').read_text()):
 name=proof['name'];kind=proof['checker'];source=ROOT/proof['source'] if proof.get('source') else default_source
 file=P/'corruptions'/({'GHOST_ACCEPTED_NEED_WITH_CONSERVED_TOTAL':'GHOST_ACCEPTED_NEED.jsonl','SWAPPED_ORDER_IDS_SAME_DATE_QUANTITY_PRICE_DIFFERENT_BUYER':'SWAPPED_ORDER_PARTIES.jsonl'}.get(name,name+'.jsonl'))
 try:
  (causal if kind.startswith('causal') else accounts)(source,file)
 except (ValueError,KeyError,AssertionError,TypeError,StopIteration) as e:negative.append(dict(name=name,status='PASS_EXPECTED_REJECTION',error=str(e)))
 else:raise AssertionError('Final audit accepted negative '+name)
assert len(negative)==10
assert sha==hashlib.sha256((ROOT/'economy_quantity_lab/goal_cycle02/causal_audit.py').read_bytes()).hexdigest(),'checker changed during final re-audit'
r=dict(status='PASS',formal_cases_reaudited=118,independent_accounting_rechecks=118,independent_causal_rechecks=118,negative_logs_reaudited=len(negative),negative=negative,causal_checker_version='v4-post-execution',causal_checker_sha256=sha,execution_source_commit='710dac38d82a4d48609e88c9f974a927e9b6c686',runtime_rerun=False,utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),elapsed_seconds=time.perf_counter()-start)
(OUT/'verification.json').write_text(json.dumps(r,sort_keys=True,indent=2)+'\n');print(json.dumps(r,indent=2))
