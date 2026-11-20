"""Goal Cycle 01 correctness, complete historical economic regression, two replays.

Round6 provenance manifest contains source hashes. Its economic output golden
set remains immutable; authorized source differences are checked explicitly.
No historical expected output or invariant is changed.
"""
import argparse,hashlib,json,subprocess,sys,tempfile,time
from pathlib import Path
from verify_baseline import execute,write_record
from verify_round3 import output_hashes
ROOT=Path(__file__).resolve().parent;NEW=ROOT/'economy_quantity_lab/goal_cycle01';OLD=ROOT/'economy_quantity_lab/network_round6'


def validate_round6_provenance(actual_path):
    expected=json.loads((OLD/'evidence/manifest.json').read_text());actual=json.loads(Path(actual_path).read_text())
    expected_source=expected.pop('sources');actual_source=actual.pop('sources')
    if actual!=expected:raise RuntimeError('Round6 non-source manifest changed')
    changed={k:dict(old=expected_source.get(k),new=actual_source.get(k)) for k in set(expected_source)|set(actual_source) if expected_source.get(k)!=actual_source.get(k)}
    allowed={'economy_quantity_lab/network_round6/network_simulation.py'}
    if set(changed)!=allowed:raise RuntimeError('unexpected Round6 source delta '+str(changed))
    for key,value in actual_source.items():
        if hashlib.sha256((ROOT/key).read_bytes()).hexdigest()!=value:raise RuntimeError('manifest does not describe actual source '+key)
    return dict(status='PASS',changed_sources=changed,policy='Only explicitly authorized hook source differs. Original economic golden outputs/file set unchanged. Original strict verifier remains unchanged and reports this provenance delta.')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-dir',type=Path,default=ROOT/'.local/goal-cycle01');p.add_argument('--correctness-only',action='store_true');a=p.parse_args()
    parent=a.output_dir.resolve();parent.mkdir(parents=True,exist_ok=True);directory=Path(tempfile.mkdtemp(prefix='final-verification-',dir=parent))
    record=dict(status='FAIL',checks=[],run_directory=str(directory));start=time.perf_counter()
    try:
        execute('new_correctness_tests',NEW,['-m','unittest','discover','-s','.', '-p','test_cycle.py','-v'],directory,record,42)
        execute('log_corruptions',ROOT,[str(NEW/'corruption_probes.py'),'--output-dir',str(directory/'corruptions')],directory,record)
        if not a.correctness_only:
            for name in ('baseline','round3','round4a','round4b','round4c','round5','round5b'):
                args=[str(ROOT/f'verify_{name}.py'),'--output-dir',str(directory/'historical')]
                if name=='baseline':args.append('--strict-bytes')
                execute('historical_'+name,ROOT,args,directory,record)
            execute('historical_round6_tests',OLD,['-m','unittest','-v','test_multi_firm.py'],directory,record,50)
            execute('historical_round6_economics',ROOT,[str(OLD/'run_multi_firm_experiment.py'),'--output-dir',str(directory/'round6_economics'),'--execution-log',str(directory/'round6_execution.json')],directory,record)
            expected=json.loads((OLD/'evidence/hash_manifest.json').read_text())['files'];actual=output_hashes(directory/'round6_economics')
            if set(actual)!=set(expected) or any(actual[k]!=v for k,v in expected.items() if k!='manifest.json'):raise RuntimeError('Round6 economic golden hash/file-set mismatch')
            record['round6_source_delta']=validate_round6_provenance(directory/'round6_economics/manifest.json')
            record['round6_economic_files_matched']=len(actual)-1
            # Both complete official sets run in distinct subprocesses; never
            # reuse concatenated short runs as a 3600-day run.
            for replay in ('replay_a','replay_b'):
                execute(replay,ROOT,[str(NEW/'run_cycle.py'),'--output-dir',str(directory/replay)],directory,record)
            first=json.loads((directory/'replay_a/hash_manifest.json').read_text());second=json.loads((directory/'replay_b/hash_manifest.json').read_text())
            if first!=second:raise RuntimeError('complete formal economic hash/file set mismatch')
            record['formal_replays']=dict(cases_each=50,days_each=66000,matched_files=len(first['files']),economic_manifest_sha256=hashlib.sha256((directory/'replay_a/hash_manifest.json').read_bytes()).hexdigest())
        record['status']='PASS'
    except (RuntimeError,ValueError,OSError,KeyError) as e:record['error']=str(e)
    finally:
        record['elapsed_seconds']=time.perf_counter()-start;write_record(directory/'verification.json',record);print(json.dumps(record,indent=2),flush=True)
    return 0 if record['status']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())
