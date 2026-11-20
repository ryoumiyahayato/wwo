"""Seven intentional log corruptions in temporary copies; formal evidence untouched."""
from copy import deepcopy
from pathlib import Path
import json,tempfile
from cycle_fixtures import make_case
from network_simulation import NetworkSimulation
from run_multi_firm_experiment import intent
from observation import StreamObserver,canonical,dump
from offline_audit import audit


def trace(directory,kind):
    c=make_case(mode='N1',days=20)
    if kind!='normal':
        for sink in c['sinks']:sink['demand_intervals']=[[1,10000,0]]
    if kind=='double_reserve':c['economics']['balances']['B1']=8000
    s=NetworkSimulation(c);o=StreamObserver(s,directory,'full')
    if kind=='normal':
        for _ in range(20):s.step();o.finish_day()
    else:
        r=s.admit_round([intent(s,'B1','A','coal',80)])[0]
        if kind=='cancel':
            s.config['routes']['A>B1:coal']['capacity']=30
            s.request_cancellation(r['order_id'],80);s.dispatch();s.day=1;s.confirm_cancellations();s.day=2;s.receive()
        o.finish_day()
    o.close();audit(directory)
    return [json.loads(line) for line in (Path(directory)/'events.jsonl').read_text().splitlines()]


def probes(output):
    output=Path(output);output.mkdir(parents=True,exist_ok=True);results=[]
    with tempfile.TemporaryDirectory(prefix='corruptions-',dir=output) as temp:
        root=Path(temp);normal=trace(root/'normal','normal');cancel=trace(root/'cancel','cancel');reserve=trace(root/'reserve','double_reserve')
        cases=[]
        def mutate(name,source,directory,event,change):
            rows=deepcopy(source);i=next(i for i,r in enumerate(rows) if r['event']==event);change(rows,i)
            cases.append((name,rows,directory))
        mutate('duplicate_payment',normal,root/'normal','payment',lambda rows,i:rows.insert(i+1,dict(rows[i])))
        mutate('missing_seller_income',normal,root/'normal','payment',lambda rows,i:rows[i].update(seller_credit=0))
        mutate('arrival_above_dispatch',normal,root/'normal','arrived',lambda rows,i:rows[i].update(quantity=rows[i]['quantity']+1))
        mutate('cancel_in_transit',cancel,root/'cancel','cancelled',lambda rows,i:rows[i].update(quantity=80,released_value=8000))
        mutate('payment_new_quote',normal,root/'normal','payment',lambda rows,i:rows[i].update(locked_price=rows[i]['locked_price']+1,buyer_debit=rows[i]['quantity']*(rows[i]['locked_price']+1),seller_credit=rows[i]['quantity']*(rows[i]['locked_price']+1)))
        def extra_reserve(rows,i):
            r=dict(rows[i]);r.update(order_id=2,route='D>B1:coal',seller='D');rows.insert(i+1,r)
        mutate('same_balance_two_reservations',reserve,root/'reserve','accepted',extra_reserve)
        mutate('terminal_missing_cash',normal,root/'normal','terminal',lambda rows,i:rows[i].update(buyer_debit=0,seller_credit=0))
        for name,rows,directory in cases:
            corrupted=root/(name+'.jsonl');corrupted.write_text(''.join(canonical(r)+'\n' for r in rows))
            try:audit(directory,corrupted)
            except (ValueError,KeyError,TypeError,StopIteration) as e:results.append(dict(case=name,status='PASS_EXPECTED_REJECTION',error=str(e)))
            else:raise AssertionError('offline checker accepted corruption '+name)
    dump(output/'corruption_results.json',results)
    return results

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--output-dir',type=Path,required=True);a=p.parse_args();print(json.dumps(probes(a.output_dir),indent=2))
