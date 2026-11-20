"""Explicit diagnostic controls, separate from the43 formal configurations."""
from pathlib import Path
import argparse,json,hashlib,sys,time
from copy import deepcopy
from run_cycle02 import run
from fixtures import core,factorial,spec
from causal import dump,canonical

def rename(c,mapping):
    c=deepcopy(c)
    for f in c['firms']:
        old=f['firm_id'];f['firm_id']=mapping.get(old,old);f['place_id']='place:'+f['firm_id']
        for r in f['recipes']:r['producer_id']=f['firm_id']
        for good,ids in f['knowledge'].items():f['knowledge'][good]=[mapping.get(x,x) for x in ids]
    c['inventory']={mapping.get(k,k):v for k,v in c['inventory'].items()}
    for r in c['routes']:r['seller_id']=mapping.get(r['seller_id'],r['seller_id']);r['buyer_id']=mapping.get(r['buyer_id'],r['buyer_id'])
    for s in c['sinks']:s['firm_id']=mapping.get(s['firm_id'],s['firm_id'])
    e=c['economics'];e['balances']={mapping.get(k,k):v for k,v in e['balances'].items()};e['limits']={mapping.get(k,k):v for k,v in e['limits'].items()}
    e['prices']={mapping.get(k.split(':')[0],k.split(':')[0])+':'+k.split(':')[1]:v for k,v in e['prices'].items()}
    return c

def controls():
    runs=[]
    for days,modes in ((600,('full','compact','off')),(3600,('compact','off'))):
        for observer in modes:
            c=core('normal','N3','L_NONBINDING',days);c['case_id']=f'OBS_{days}_{observer}';runs.append((c,observer,False))
    for mode in ('N2','N3'):
        for unit in (1,10):
            c=core('normal',mode,'L_NONBINDING',600)
            e=c['economics'];e['prices']={k:v*unit for k,v in e['prices'].items()};e['limits']={k:{g:v*unit for g,v in goods.items()} for k,goods in e['limits'].items()};e['balances']={k:v*unit for k,v in e['balances'].items()};e['terminal_prices']={k:v*unit for k,v in e['terminal_prices'].items()};e['tick']*=unit
            c['case_id']=f'UNIT_{mode}_{unit}';runs.append((c,'compact',False))
    for variant in ('normal','reverse_containers','stable_relabel'):
        c=factorial('P_UNIFORM','R_LEGACY','T_EQUAL_FEASIBLE',600)
        if variant=='reverse_containers':c['firms'].reverse();c['routes'].reverse();c['sinks'].reverse();c['inventory']=dict(reversed(list(c['inventory'].items())));c['reverse_requests']=True
        if variant=='stable_relabel':c=rename(c,{'A':'Y','D':'X','B1':'Z1','B2':'A1','C1':'Z2','C2':'A2'})
        c['case_id']='ORDER_'+variant;runs.append((c,'compact',True))
    return runs

def main():
    a=argparse.ArgumentParser();a.add_argument('--output-dir',type=Path,required=True);x=a.parse_args();p=x.output_dir
    if p.exists():a.error('New output directory required')
    p.mkdir(parents=True);configs=controls();dump(p/'frozen_controls.json',[dict(case=c,observer=o,trace=t,sha256=hashlib.sha256(canonical(c).encode()).hexdigest()) for c,o,t in configs]);summ=[];perf=[]
    for c,o,t in configs:
        s,v=run(c,p/c['case_id'],o,t);summ.append(s);perf.append(dict(case_id=c['case_id'],**v));print(c['case_id'],s['physical_sha256'],flush=True)
    by={s['case_id']:s for s in summ}
    checks={}
    for d in (600,3600):
        xs=[s for s in summ if s['case_id'].startswith('OBS_'+str(d))];assert len({s['economic_sha256'] for s in xs})==1;assert len({s['physical_sha256'] for s in xs})==1;checks['observer_'+str(d)]='PASS'
    for m in ('N2','N3'):
        a=by[f'UNIT_{m}_1'];b=by[f'UNIT_{m}_10'];assert a['physical_sha256']==b['physical_sha256'];assert {k:v*10 for k,v in a['prices'].items()}==b['prices'];checks['nominal_unit_'+m]='PASS'
    assert by['ORDER_normal']['economic_sha256']==by['ORDER_reverse_containers']['economic_sha256'];checks['container_and_request_order']='PASS'
    checks['stable_ID_relabel']=dict(status='EXECUTED_POLICY_SENSITIVITY',deliveries=[by['ORDER_'+v]['delivered'] for v in ('normal','stable_relabel')],sinks=[by['ORDER_'+v]['sinks'] for v in ('normal','stable_relabel')],note='ID tie-break is policy. Renamed identities are mapped back for service totals; difference is not implementation nondeterminism.')
    dump(p/'summary.json',summ);dump(p/'performance.json',perf);dump(p/'checks.json',checks);dump(p/'execution.json',dict(status='PASS',cases=len(configs),days=sum(c['days'] for c,o,t in configs),audits=len(configs)))
if __name__=='__main__':main()
