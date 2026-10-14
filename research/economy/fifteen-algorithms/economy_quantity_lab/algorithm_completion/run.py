"""Single new-case runner; deterministic trace and fresh paths, no run on import."""
import argparse,gzip,hashlib,io,json,os,sys,time,subprocess,tracemalloc
from pathlib import Path
from programme_fixtures import scenario
from world import ProgrammeWorld

def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False)
def dump(p,v):p.write_text(json.dumps(v,sort_keys=True,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

def run(case,out):
    out=Path(out);out.mkdir(parents=True,exist_ok=False)
    root=Path(__file__).resolve().parents[2];start=time.perf_counter();digest=hashlib.sha256();events=0
    sources={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/'economy_quantity_lab/algorithm_completion').glob('*.py')}
    for name in ('economy_quantity_lab/economy.py','economy_quantity_lab/network_round6/network_simulation.py','economy_quantity_lab/goal_cycle01/payment_policy.py','economy_quantity_lab/goal_cycle01/cash.py'):
        sources[name]=hashlib.sha256((root/name).read_bytes()).hexdigest()
    receipt=dict(status='RUNNING',pid=os.getpid(),python=sys.executable,head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),source_hashes=sources,case_sha256=hashlib.sha256(canonical(case).encode()).hexdigest(),days_requested=case['days'])
    dump(out/'fixture.json',case);dump(out/'execution.json',receipt)
    tracemalloc.start()
    with (out/'events.jsonl.gz').open('xb') as raw, gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0,compresslevel=6) as gz:
        def writer(row):
            nonlocal events
            block=(canonical(row)+'\n').encode();gz.write(block);digest.update(block);events+=1
            if raw.tell()>64*1024*1024:raise RuntimeError('Per-case evidence byte cap')
        try:
            s=ProgrammeWorld(case,writer)
            for _ in range(case['days']):s.step()
            dump(out/'final.json',s.snapshot())
            summary=dict(case_id=case['case_id'],days=s.day,needs=sum(n['required'] for n in s.need_history),consumed=sum(n['consumed'] for n in s.need_history),unmet=sum(n['unmet'] for n in s.need_history),per_household={h:dict(needs=sum(n['required'] for n in s.need_history if n['actor']==h),consumed=sum(n['consumed'] for n in s.need_history if n['actor']==h),income=s.received_income[h],work_hours=s.cohort_hours[h],cash=s.economics.cash.accounts[h].balance,arrears=sum(c['remaining'] for c in s.wage_claims.values() if c['worker']==h)) for h in s.households},accepted_orders=len(s.orders),metrics=dict(s.metrics),trace_events=events,economic_sha256=digest.hexdigest())
            dump(out/'summary.json',summary);receipt.update(status='PASS',days_completed=s.day,economic_sha256=digest.hexdigest(),events=events)
        except Exception as e:
            receipt.update(status='FAIL',error=repr(e),events=events);raise
        finally:
            _,peak=tracemalloc.get_traced_memory();tracemalloc.stop();receipt.update(elapsed_seconds=time.perf_counter()-start,python_tracemalloc_peak_bytes=peak,phase_timings=dict(s.timing) if 's' in locals() else {});dump(out/'execution.json',receipt)
    return summary

def main():
    p=argparse.ArgumentParser();p.add_argument('--case');p.add_argument('--fixture',type=Path);p.add_argument('--days',type=int,default=30);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
    c=json.loads(a.fixture.read_text(encoding='utf-8')) if a.fixture else scenario(a.case,a.days)
    print(canonical(run(c,a.output)))
if __name__=='__main__':main()
