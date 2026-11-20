"""Explicit monetary treatments on unchanged Round6 physical fixtures."""
from copy import deepcopy
from dataclasses import asdict
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'network_round6'))
from network_fixtures import make_network
from firm_network import Route

BASE_PRICE={'coal':100,'steel':300}

def large_network(days=600,reverse=False):
    base=make_network('normal','C1','S10',days)
    result=deepcopy(base);result.update(scale='S20',case_id='normal_C1_S20',firms=[],inventory={},routes=[],sinks=[])
    raw=['A','D']+[f'R{i}' for i in range(3,11)];steel=[f'B{i}' for i in range(1,21)];machine=[f'C{i}' for i in range(1,41)]
    groups=[([f['firm_id'] for f in base['firms'] if not f['knowledge']],raw),([f'B{i}' for i in range(1,11)],steel),([f'C{i}' for i in range(1,21)],machine)]
    originals={f['firm_id']:f for f in base['firms']}
    for group,(old_ids,new_ids) in enumerate(groups):
        for i,fid in enumerate(new_ids):
            old=old_ids[i%len(old_ids)];spec=deepcopy(originals[old]);spec['firm_id']=fid;spec['place_id']='place:'+fid
            # Recipe producer field is named producer in frozen schema.
            for recipe in spec['recipes']:
                recipe.pop('recipe_id',None)
                for k in ('producer','producer_id'):
                    if k in recipe:recipe[k]=fid
            if group:
                suppliers=raw if group==1 else steel;good='coal' if group==1 else 'steel'
                known=[suppliers[i%len(suppliers)],suppliers[(i+1)%len(suppliers)]];spec['knowledge']={good:known}
                for seller in known:result['routes'].append(asdict(Route(seller,fid,good,60 if good=='steel' or seller=='D' else 100,4 if seller=='D' else 2 if good=='coal' else 1)))
            result['firms'].append(spec);result['inventory'][fid]=deepcopy(base['inventory'][old])
            if group==2:result['sinks'].append(dict(sink_id=f'T{i+1}',firm_id=fid,commodity='machine',demand_intervals=[[1,10000,5]]))
    if reverse:result['firms'].reverse();result['routes'].reverse();result['sinks'].reverse();result['inventory']=dict(reversed(list(result['inventory'].items())))
    return result


def monetary(case,mode='N2',funding='nonbinding',factor=1,unit=1,feedback=True,observer=True):
    case=deepcopy(case)
    if mode=='N0':return case
    if mode not in ('N1','N2','N3'):raise ValueError('mode')
    prices={}
    for good,base in BASE_PRICE.items():
        ids=sorted(f['firm_id'] for f in case['firms'] if any(r['output_commodity']==good for r in f['recipes']))
        for i,fid in enumerate(ids):prices[f'{fid}:{good}']=(base if mode=='N1' or i%2==0 else base*9//10)*unit
    limits={f['firm_id']:{g:BASE_PRICE[g]*4*unit for g in f['knowledge']} for f in case['firms']}
    days=case['days'];balances={}
    # Same per-firm rule at every scale: all-capacity input consumption over
    # the experiment plus a 23-day exposure margin (H10 + max fixture lead8
    # + promise2 + three spare days), targets and initial input inventory.
    # Assumes zero sale revenue. No global firm count enters this bound.
    for f in case['firms']:
        daily=0
        for r in f['recipes']:
            for good,coefficient in r['inputs']:
                q=(f['capacities'][r['output_commodity']]*coefficient+r['output_quantity']-1)//r['output_quantity']
                daily+=q*BASE_PRICE[good]*4*unit
        margin=sum((case['inventory'][f['firm_id']][g]+f['input_targets'][g])*BASE_PRICE[g]*4*unit for g in f['knowledge'])
        balances[f['firm_id']]=((days+23)*daily+margin)*factor
    if funding=='finite':
        for f in case['firms']:
            qty_cost=0
            for r in f['recipes']:
                for good,coefficient in r['inputs']:qty_cost+=20*f['capacities'][r['output_commodity']]*coefficient*BASE_PRICE[good]*4*unit//r['output_quantity']
            qty_cost+=sum(case['inventory'][f['firm_id']][g]*BASE_PRICE[g]*4*unit for g in f['knowledge'])
            balances[f['firm_id']]=qty_cost*factor
    elif funding!='nonbinding':raise ValueError('funding')
    for sink in case['sinks']:
        maximum=max(i[2] for i in sink['demand_intervals'])
        balances['external:'+sink['sink_id']]=(days if funding=='nonbinding' else 20)*maximum*2000*unit*factor
    case['economics']=dict(mode=mode,prices=prices,limits=limits,balances=balances,tick=unit,
        terminal_prices={s['sink_id']:2000*unit for s in case['sinks']},feedback=feedback,price_observer=observer,funding=funding)
    case['case_id']=f'{case["treatment"]}_{case["scale"]}_{mode}_{funding}_{days}'
    return case


def make_case(treatment='normal',mode='N2',days=600,scale='S2',funding='nonbinding',**kwargs):
    reverse=kwargs.pop('reverse',False)
    case=large_network(days,reverse) if scale=='S20' else make_network(treatment,'C1',scale,days,reverse=reverse)
    return monetary(case,mode,funding,**kwargs)


def formal_cases():
    cases=[]
    for treatment in ('normal','coal_scarcity','steel_scarcity','asymmetric_demand','step_up','asymmetric_lead','recovery','shutdown'):
        for mode in ('N0','N1','N2','N3'):
            c=make_case(treatment,mode);c['suite']='main';cases.append(c)
    for treatment in ('normal','coal_scarcity','recovery'):
        for funding in ('nonbinding','finite'):
            for mode in ('N2','N3'):
                c=make_case(treatment,mode,3600,funding=funding);c['suite']='long';cases.append(c)
    for scale in ('S5','S10','S20'):
        for mode in ('N2','N3'):
            c=make_case(scale=scale,mode=mode);c['suite']='scale';cases.append(c)
    return cases
