"""Pre-registered Cycle02 fixtures; no post-evaluation tuning."""
from copy import deepcopy
import hashlib,json
from causal import make_case,canonical
from cycle_fixtures import monetary


def limits(case,kind='L_NONBINDING',asymmetric=False):
    e=case['economics'];unit=e['tick']
    for f,goods in e['limits'].items():
        for good in goods:
            v=400 if good=='coal' else 1200
            if kind=='L_BINDING':v=110 if good=='coal' else 330
            if asymmetric:v=(95 if f.endswith('1') else 135) if good=='coal' else (275 if f.endswith('1') else 325)
            goods[good]=v*unit
    return case


def factorial(p,r,t,days=600):
    c=make_case('normal','N2',days)
    if t=='T_EQUAL_FEASIBLE':
        for route in c['routes']:
            if route['commodity']=='coal':route['lead_time']=2
    if p=='P_UNIFORM':
        c['economics']['prices']={k:100 if k.endswith(':coal') else 300 for k in c['economics']['prices']}
    c['economics']['ranking_axis']=r
    c['axes']=dict(P=p,R=r,T=t)
    c['case_id']=f'M2_{t}_{p}_{r}_{days}'
    return c


def core(treatment,mode,limit_kind,days=600,scale='S2'):
    c=limits(make_case(treatment,mode,days,scale),limit_kind)
    c['axes']=dict(L=limit_kind)
    c['case_id']=f'{"M4" if days==3600 else "M3"}_{treatment}_{mode}_{limit_kind}_{days}'
    return c


def holdout(kind,mode,days=600):
    if kind=='mixed_date_competition':
        c=make_case('normal',mode,days)
        a=deepcopy(next(f for f in c['firms'] if f['firm_id']=='A'));a['firm_id']='E';a['place_id']='place:E';a['capacities']['coal']=75
        for r in a['recipes']:r['producer_id']='E'
        c['firms'].append(a);c['inventory']['E']=dict(coal=375,steel=0,machine=0)
        for f in c['firms']:
            if 'coal' in f['knowledge']:
                f['knowledge']['coal'].append('E')
                c['routes'].append(dict(seller_id='E',buyer_id=f['firm_id'],commodity='coal',capacity=80,lead_time=2))
        for route in c['routes']:
            if route['seller_id']=='D':route['lead_time']=5
        c=monetary(c,mode);c['economics']['prices']['E:coal']=95
        c=limits(c,'L_BINDING')
    elif kind=='asymmetric_limits_scarcity':
        c=make_case('normal',mode,days,'S5')
        for f in c['firms']:
            if f['firm_type']=='RAW_SUPPLIER':f['capacities']['coal']=35 if f['firm_id']=='D' else 55
        c=limits(c,'L_BINDING',asymmetric=True)
        for sink in c['sinks']:sink['demand_intervals']=[[1,10000,6 if sink['sink_id'].endswith('1') else 5]]
    else:raise ValueError(kind)
    c['case_id']=f'H_{kind}_{mode}_{days}'
    return c


def spec(c,suite):
    c['suite']=suite
    return dict(case_id=c['case_id'],suite=suite,config_sha256=hashlib.sha256(canonical(c).encode()).hexdigest(),config=c)


def formal_manifest():
    cases=[]
    for t in ('T_EQUAL_FEASIBLE','T_MIXED_LEAD'):
        for p in ('P_UNIFORM','P_HETEROGENEOUS'):
            for r in ('R_LEGACY','R_PRICE_FIRST'):cases.append(spec(factorial(p,r,t),'main_evaluation'))
    for days,suite in ((600,'main_evaluation'),(3600,'long_evaluation')):
        for treatment in ('normal','coal_scarcity','recovery'):
            for mode in ('N2','N3'):
                for l in ('L_NONBINDING','L_BINDING'):cases.append(spec(core(treatment,mode,l,days),suite))
    for funding in ('ENOUGH','LOW_BUYER_CASH','LOW_TERMINAL_CASH'):
        c=make_case('normal','N2',600);c['case_id']='CASH_'+funding+'_600'
        if funding!='ENOUGH':
            c['economics']['funding']='explicit_cash_constraint'
            for f in c['firms']:
                if f['knowledge'] and funding=='LOW_BUYER_CASH':c['economics']['balances'][f['firm_id']]=0
            if funding=='LOW_TERMINAL_CASH':
                for sink in c['sinks']:c['economics']['balances']['external:'+sink['sink_id']]=2000
        cases.append(spec(c,'diagnostic'))
    for scale in ('S5','S10'):
        for mode in ('N2','N3'):
            c=make_case('normal',mode,600,scale);c['case_id']=f'SCALE_{scale}_{mode}_600';cases.append(spec(c,'scale_evaluation'))
    for kind in ('mixed_date_competition','asymmetric_limits_scarcity'):
        for mode in ('N2','N3'):cases.append(spec(unseen_holdout(kind,mode),'held_out'))
    return dict(version='cycle02-frozen-v1',candidate='local-window-v1 UNCHANGED; N4 not assumed',created_utc=None,source_head='93633b4321dc288bd14b064350cc7fb053529bae',limits_disclosure='Coal110/steel330 binding limits informed by Cycle01 historical price ranges, not a blind retest of Cycle01. Holdouts not used for tuning.',development={'purpose':'prove existence of matched equal-ETA opportunity and read-only diagnosis; separate counts','cases':[]},cases=cases)


def unseen_holdout(kind,mode,days=600):
    # Original20-day prefix test exposed v1 fixture families. These v2 parameter
    # configurations are frozen separately without any simulated prefix. Changes
    # reserve new dates/budgets, not selections based on model performance.
    c=holdout(kind,mode,days)
    if kind=='mixed_date_competition':
        for f in c['firms']:
            if f['firm_id']=='E':f['capacities']['coal']=70
        c['inventory']['E']['coal']=410
        for r in c['routes']:
            if r['seller_id']=='D':r['lead_time']=6
        c['sinks'][0]['demand_intervals']=[[1,10000,6]]
        c['sinks'][1]['demand_intervals']=[[1,10000,4]]
    else:
        for f in c['firms']:
            if f['firm_type']=='RAW_SUPPLIER':f['capacities']['coal']=40 if f['firm_id']=='D' else 50
        for fid,goods in c['economics']['limits'].items():
            for good in goods:goods[good]=(99 if fid.endswith('1') else 145) if good=='coal' else (280 if fid.endswith('1') else 335)
        for sink in c['sinks']:sink['demand_intervals']=[[1,10000,6 if sink['sink_id'].endswith('1') else 4]]
    c['case_id']=f'H2_{kind}_{mode}_{days}'
    c['holdout_status']='UNRUN_V2; v1 had20-day correctness-test exposure and is development only'
    return c
