"""Reproducible main/long/scale matrix with stream archives and offline audit."""
from pathlib import Path
import argparse,hashlib,json,platform,resource,sys,time,gc
from cycle_fixtures import formal_cases,make_case
from network_simulation import NetworkSimulation
from observation import StreamObserver,dump,canonical
from offline_audit import audit

ROOT=Path(__file__).resolve().parents[2]


def code_digest():
    paths=list((ROOT/'economy_quantity_lab/goal_cycle01').glob('*.py'))+[ROOT/'economy_quantity_lab/network_round6/network_simulation.py',ROOT/'experiments_manifest.json',ROOT/'verify_goal_cycle01.py']
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def run_case(case,directory,mode='compact'):
    t=time.perf_counter();s=NetworkSimulation(case);o=StreamObserver(s,directory,mode)
    for _ in range(case['days']):s.step();o.finish_day()
    summary=o.close();elapsed=time.perf_counter()-t;t=time.perf_counter()
    reconstruction=audit(directory) if s.economics else dict(status='NOT_APPLICABLE',reason='N0 retains original quantity checks; no payment trace')
    audit_seconds=time.perf_counter()-t
    if s.economics and case['economics']['funding']=='nonbinding':
        assert not s.economics.rejections['CASH'] and not s.economics.rejections['TERMINAL_CASH'],'declared nonbinding cash actually binds'
    t=s.timing
    costs=dict(planning_reconcile_seconds=t['planning_seconds'],
        known_edge_quote_allocation_seconds=t['procurement_seconds']+t.get('price_update_seconds',0),
        material_order_cash_settlement_seconds=t['receive_observations_seconds']+t['production_delivery_seconds']+t['dispatch_seconds']+t['account_seconds'],
        logging_metrics_archive_export_seconds=t['report_archive_seconds']+o.log_seconds,
        elapsed_seconds=elapsed,offline_audit_seconds=audit_seconds,
        process_rss_high_water_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss*1024,
        python_gc_tracked_objects_end=len(gc.get_objects()),serialized_bytes=sum(p.stat().st_size for p in Path(directory).rglob('*') if p.is_file()),
        note='Linux ru_maxrss actual process high-water across preceding cases; not per-case isolated RSS. Hook timing includes reconcile in production/procurement; streaming event write time overlaps settlement. Categories are attribution, not additive exclusive CPU spans.')
    dump(Path(directory)/'summary.json',summary);dump(Path(directory)/'audit.json',reconstruction)
    return summary,costs,reconstruction


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--suite',choices=['all','main','long','scale','smoke'],default='all');parser.add_argument('--observer',choices=['compact','full','off'],default='compact');a=parser.parse_args()
    output=a.output_dir.resolve()
    if output.exists():parser.error('new output directory required; completed evidence is never overwritten')
    if output==ROOT or output.is_relative_to(ROOT/'economy_quantity_lab') or output.is_relative_to(ROOT/'docs'):parser.error('output outside source required')
    output.mkdir(parents=True);digests=code_digest();manifest=json.loads((ROOT/'experiments_manifest.json').read_text());dump(output/'config_manifest.json',dict(manifest=manifest,code_hashes=digests,python=sys.version))
    cases=formal_cases() if a.suite!='smoke' else [make_case(scale=scale,mode=mode,days=20) for scale in ('S5','S10','S20') for mode in ('N2','N3')]
    if a.suite not in ('all','smoke'):cases=[c for c in cases if c['suite']==a.suite]
    summaries=[];costs=[];audits=[];started=time.perf_counter()
    try:
        for case in cases:
            summary,cost,reconstruction=run_case(case,output/case['case_id'],a.observer)
            summaries.append(summary);costs.append(dict(case_id=case['case_id'],**cost));audits.append(dict(case_id=case['case_id'],**reconstruction))
            dump(output/'summary.json',summaries);dump(output/'performance.json',costs);dump(output/'audits.json',audits)
            print(case['case_id'],'delivery',summary['delivered'],'backlog',summary['backlog'],'audit',reconstruction['status'],round(cost['elapsed_seconds'],2),flush=True)
        for treatment in {s['treatment'] for s in summaries if s['suite']=='main'}:
            controls=[s for s in summaries if s['suite']=='main' and s['treatment']==treatment and s['mode'] in ('N0','N1')]
            assert len({s['physical_sha256'] for s in controls})==1,'N0/N1 physical control fails'
        assert digests==code_digest(),'code changed during formal experiment; evidence not reusable'
        economic_files={p.relative_to(output).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.rglob('*')) if p.is_file() and p.name not in ('performance.json','execution.json','hash_manifest.json')}
        dump(output/'hash_manifest.json',dict(files=economic_files))
        dump(output/'execution.json',dict(status='PASS',cases=len(cases),days=sum(c['days'] for c in cases),audit_pass=sum(r['status']=='PASS' for r in audits),elapsed_seconds=time.perf_counter()-started,python=sys.version,platform=platform.platform(),code_hashes=digests,observer=a.observer))
    except Exception as e:
        dump(output/'execution.json',dict(status='FAIL',completed_cases=len(summaries),error=repr(e),code_hashes=digests));raise

if __name__=='__main__':main()
