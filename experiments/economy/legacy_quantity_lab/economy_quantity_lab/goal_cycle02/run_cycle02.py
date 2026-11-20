"""Actual Cycle02 runs, streaming diagnosis and unchanged Cycle01 dual audit."""
from pathlib import Path
import sys,argparse,json,hashlib,time,resource,platform
from causal import CausalSimulation,CausalTrace,StreamObserver,dump,canonical
from offline_audit import audit
from causal_audit import audit as causal_audit
ROOT=Path(__file__).resolve().parents[2]

def digests():
    paths=sorted(list((ROOT/'economy_quantity_lab/goal_cycle02').glob('*.py'))+list((ROOT/'economy_quantity_lab/goal_cycle02_candidate').glob('*.py')))
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}

def run(case,path,observer='compact',trace=True):
    p=Path(path)
    if p.exists():raise ValueError('New run directory required')
    t=time.perf_counter()
    if case['economics']['mode']=='N4_EXPERIMENTAL':
        sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle02_candidate'))
        from learning import LearningSimulation
        s=LearningSimulation(case)
    else:s=CausalSimulation(case)
    o=StreamObserver(s,p,observer);c=CausalTrace(s,p,trace)
    machine_days=0
    for _ in range(case['days']):
        s.step();machine_days+=sum(v['machine'] for v in s.stock.values());c.finish_day();o.finish_day()
    metrics=deep=dict(s.metrics)
    timing=dict(s.timing);tr=c.close();summary=o.close()
    # Existing machine-day definition: integral of actual owned machine stock.
    # Daily delivered machine-use/installed capital is not modeled by this Lab.
    summary['machine_days_inventory']=machine_days
    summary['machine_days_scope']='End-of-day physical machine inventory summed over time; installed-use service not modeled.'
    summary['final_stock']=s.stock;summary['final_in_transit']=sum(s.balances(r)[1] for r in s.routes)
    summary['cash_receipts']=dict(s.economics.cash.receipts);summary['cash_payments']=dict(s.economics.cash.payments)
    summary['metrics']=metrics
    reconstruction=audit(p)
    if trace:dump(p/'causal_audit.json',causal_audit(p))
    if case['economics']['funding']=='nonbinding':
        assert s.economics.rejections['CASH']==0 and s.economics.rejections['TERMINAL_CASH']==0,'EXPERIMENT_DESIGN_DEFECT: funds bind'
    dump(p/'summary.json',summary);dump(p/'audit.json',reconstruction)
    perf=dict(elapsed_seconds=time.perf_counter()-t,timing=timing,**tr,process_rss_high_water_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*1024,serialized_bytes=sum(x.stat().st_size for x in p.rglob('*') if x.is_file()),note='RSS is process cumulative high-water; trace writes overlap callers; timings do not sum exclusively.')
    return summary,perf

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--manifest',type=Path,default=ROOT/'experiments_manifest_cycle02.json');ap.add_argument('--output-dir',type=Path,required=True);ap.add_argument('--observer',choices=['full','compact','off'],default='compact');ap.add_argument('--trace-off',action='store_true');ap.add_argument('--suite',default='all');a=ap.parse_args()
    if a.output_dir.exists():ap.error('New output directory required')
    a.output_dir.mkdir(parents=True);manifest=json.loads(a.manifest.read_text());source=digests();dump(a.output_dir/'config_manifest.json',dict(manifest=manifest,manifest_sha256=hashlib.sha256(a.manifest.read_bytes()).hexdigest(),code_hashes=source,observer=a.observer,trace=not a.trace_off))
    summaries=[];performances=[];completed=[];start=time.perf_counter()
    cases=[x for x in manifest['cases'] if a.suite=='all' or x['suite'] in a.suite.split(',')]
    try:
        for spec in cases:
            if spec['suite']=='held_out':
                gate=ROOT/'economy_quantity_lab/goal_cycle02/evidence/new_candidate_gate.json'
                if not gate.exists():
                    print('WAITING_FOR_CANDIDATE_GATE',flush=True)
                    while not gate.exists():time.sleep(5)
                decision=json.loads(gate.read_text())
                assert decision['NEW_PRICE_CANDIDATE_GATE'] in ('PASS','FAIL','INSUFFICIENT_EVIDENCE')
                if decision['NEW_PRICE_CANDIDATE_GATE']=='PASS':assert manifest.get('new_candidate')=='local-zero-accept-refusal-bound-v1','PASS requires separately frozen candidate manifest'
            case=spec['config'];s,p=run(case,a.output_dir/spec['case_id'],a.observer,not a.trace_off);summaries.append(s);performances.append(dict(case_id=spec['case_id'],**p));completed.append(spec['case_id'])
            dump(a.output_dir/'summary.json',summaries);dump(a.output_dir/'performance.json',performances)
            print(spec['case_id'],s['days'],s['delivered'],s['backlog'],'audit PASS',round(p['elapsed_seconds'],2),flush=True)
        assert source==digests(),'Code changed during official run'
        files={p.relative_to(a.output_dir).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(a.output_dir.rglob('*')) if p.is_file() and p.name not in ('performance.json','execution.json','hash_manifest.json')}
        dump(a.output_dir/'hash_manifest.json',dict(files=files))
        dump(a.output_dir/'execution.json',dict(status='PASS',cases=len(completed),simulated_days=sum(x['config']['days'] for x in cases),audits=len(completed),completed=completed,elapsed_seconds=time.perf_counter()-start,python=sys.version,platform=platform.platform(),code_hashes=source))
    except Exception as e:
        dump(a.output_dir/'execution.json',dict(status='FAIL',completed=completed,error=repr(e),code_hashes=source));raise
if __name__=='__main__':main()
