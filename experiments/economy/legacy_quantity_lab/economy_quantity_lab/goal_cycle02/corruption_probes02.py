"""Six independently tampered log copies. Never edit source evidence."""
import argparse,json,sys
from pathlib import Path
from copy import deepcopy
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'goal_cycle01'))
from causal_audit import audit as causal_audit,records
from offline_audit import audit as accounting_audit
from observation import dump,canonical

def probes(source,output):
    source=Path(source);p=Path(output)
    if p.exists():raise ValueError('New output directory required')
    p.mkdir(parents=True)
    original=[json.loads(x) for x in records(source/'causal.jsonl')]
    events=[json.loads(x) for x in (source/'events.jsonl').open()]
    checks=[]
    def run(name,records,kind='causal'):
        path=p/(name+'.jsonl');path.write_text(''.join(canonical(x)+'\n' for x in records))
        try:
            result=causal_audit(source,path) if kind=='causal' else accounting_audit(source,path)
        except (ValueError,KeyError,StopIteration,AssertionError,TypeError) as e:result=dict(status='PASS_EXPECTED_REJECTION',error=str(e))
        else:raise AssertionError('Corruption was accepted: '+name)
        checks.append(dict(name=name,checker=kind,**result))
    bad=deepcopy(original)
    r=next(r for r in bad if r['event']=='decision' and any(any(a['timely'] for a in n['candidates']) for n in r['requirements']))
    n=next(n for n in r['requirements'] if any(a['timely'] for a in n['candidates']))
    n['need_by_day']=min(a['expected_arrival'] for a in n['candidates'])-1
    n['need_id']=f"{r['buyer']}:{r['commodity']}:{n['need_by_day']}"
    run('EARLIER_NEED_BY_UNCHANGED_TIMELY',bad)
    bad=deepcopy(original)
    req=next(r['request'] for r in bad if r['event']=='request' and r['request']['rejections']['PRICE_LIMIT']>0)
    req['rejections']['CASH']+=req['rejections']['PRICE_LIMIT'];req['rejections']['PRICE_LIMIT']=0
    run('PRICE_MISCLASSIFIED_AS_CASH',bad)
    bad=deepcopy(events)
    row=next(r for r in bad if r['event']=='payment')
    row['locked_price']+=1
    run('LOCKED_PRICE_PLUS_ONE',bad,'accounting')
    posted={}
    for r in original:
        if r['event']=='decision':
            for o in r['buyer_visible_information']['offers']:posted[(r['day'],o['supplier_id'],r['commodity'])]=o['posted_price']
    order_facts={r['order_id']:r for r in events if r['event']=='accepted'}
    bad=deepcopy(events)
    row=next(r for r in bad if r['event']=='payment' and posted.get((r['day'],order_facts[r['order_id']]['seller'],order_facts[r['order_id']]['commodity']),r['locked_price'])!=r['locked_price'])
    row['locked_price']=posted[(row['day'],order_facts[row['order_id']]['seller'],order_facts[row['order_id']]['commodity'])]
    run('LOCKED_PRICE_CHANGED_TO_REAL_LATEST_QUOTE',bad,'accounting')
    bad=deepcopy(original)
    r=next(r for r in bad if r['event']=='request' and r['request']['accepted_quantity']>0 and r['request']['lines'])
    r['request']['lines'][0]['need_by_day']=r['request']['expected_arrival_day']-1
    run('ACCEPTED_ORDER_LINE_EARLIER_NEED_BY',bad)
    bad=deepcopy(original)
    r=next(r for r in bad if r['event']=='price_update' and r['local']['information'])
    r['local']['information'].append(deepcopy(r['local']['information'][0]));r['local']['distinct_requests']+=1
    run('RETRY_COUNTED_AS_DISTINCT_NEED',bad)
    bad=deepcopy(events);del bad[next(i for i,r in enumerate(bad) if r['event']=='payment')]
    run('MISSING_ARRIVAL_PAYMENT',bad,'accounting')
    bad=deepcopy(original)
    r=next(r for r in bad if r['event']=='decision' and r['buyer_visible_information']['offers'])
    r['buyer_visible_information']['offers'][0]['supplier_id']='UNKNOWN_POISON'
    run('UNKNOWN_SUPPLIER_IN_SELECTABLE_SET',bad)
    dump(p/'results.json',checks);return checks

def main():
    a=argparse.ArgumentParser();a.add_argument('source',type=Path);a.add_argument('--output-dir',required=True,type=Path);x=a.parse_args();print(json.dumps(probes(x.source,x.output_dir),indent=2))
if __name__=='__main__':main()
