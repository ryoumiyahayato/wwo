"""Deterministic, bounded-degree networks. Parameters are scenario inputs."""
from copy import deepcopy
from dataclasses import asdict
from firm_network import Route,Recipe
from run_executable_planning_experiment import make_case as old_case

BASE='48b280a37be8f5fd72f0c277f4ae435e675efa1f'
TAG='economy-lab-v0.5b-executable-planning'


def firm(fid,output,capacity,inputs,known=None,targets=None,initial=None):
    inputs=tuple(inputs)
    return dict(firm_id=fid,firm_type='RAW_SUPPLIER' if not inputs else 'PROCESSOR' if output=='steel' else 'FINAL_PRODUCER',
        place_id=f'place:{fid}',recipes=[asdict(Recipe(fid,output,1,inputs))],capacities={output:capacity},
        knowledge=known or {},input_targets=targets or {},output_targets={output:400 if not inputs else 20 if output=='steel' else 0},
        active=True),dict(coal=0,steel=0,machine=0,**(initial or {})) if not initial else {g:initial.get(g,0) for g in ('coal','steel','machine')}


def make_network(treatment='normal',policy='C0',scale='S2',days=600,sleeping=0,reverse=False):
    sizes={'S1':(1,1,1),'S2':(2,2,2),'S5':(3,5,10),'S10':(5,10,20)}
    raw_count,steel_count,machine_count=sizes[scale]
    raw_ids=['A','D'][:raw_count]+[f'R{i+1}' for i in range(2,raw_count)]
    steel_ids=[f'B{i+1}' for i in range(steel_count)];machine_ids=[f'C{i+1}' for i in range(machine_count)]
    single=scale=='S1';scarce=treatment in ('coal_scarcity','asymmetric_demand')
    if scarce:raw_ids=['A']
    firms=[];inventory={};routes=[];sinks=[]
    def add(spec,stock):firms.append(spec);inventory[spec['firm_id']]=stock
    for i,fid in enumerate(raw_ids):
        cap=(80 if treatment=='coal_scarcity' else 60) if scarce else 100 if i%2==0 else 60
        add(*firm(fid,'coal',cap,(),initial={'coal':400}))
    for i,fid in enumerate(steel_ids):
        known=[raw_ids[i%len(raw_ids)],raw_ids[(i+1)%len(raw_ids)]];known=list(dict.fromkeys(known))
        capacity=60 if single else 30
        if treatment in ('steel_scarcity','bottleneck'):capacity=15 if treatment=='steel_scarcity' else 10
        if treatment=='asymmetric_lead':capacity=15 if i==0 else 45
        spec,stock=firm(fid,'steel',capacity,(('coal',2),),{'coal':known},{'coal':320 if single else 160},dict(coal=320 if single else 160,steel=40 if single else 20))
        if single:spec['output_targets']['steel']=40
        add(spec,stock)
        for seller in known:
            routes.append(asdict(Route(seller,fid,'coal',100 if seller!='D' else 60,2 if seller!='D' else 4)))
    for i,fid in enumerate(machine_ids):
        known=list(dict.fromkeys([steel_ids[i%len(steel_ids)],steel_ids[(i+1)%len(steel_ids)]]))
        add(*firm(fid,'machine',15 if single else 8,(('steel',4),),{'steel':known},{'steel':100 if single else 50},{'steel':120 if single else 60}))
        for seller in known:
            lead=1 if treatment!='asymmetric_lead' or seller=='B1' else 8
            routes.append(asdict(Route(seller,fid,'steel',60,lead)))
        qty=10 if single else 8 if treatment=='coal_scarcity' else (8 if i==0 else 2) if treatment=='asymmetric_demand' else 5
        intervals=[[1,10000,qty]]
        if treatment=='step_up' and i==0:intervals=[[1,99,5],[100,10000,10]]
        sinks.append(dict(sink_id=f'T{i+1}',firm_id=fid,commodity='machine',demand_intervals=intervals))
    capacity_events=[];route_events={}
    if treatment=='shutdown':capacity_events=[dict(day=100,firm_id='B1',commodity='steel',capacity=0)]
    if treatment=='recovery':route_events['A>B1:coal']=[dict(first_day=50,last_day=79,capacity=0)]
    for i in range(sleeping):
        fid=f'Z{i:03d}'
        firms.append(dict(firm_id=fid,firm_type='IRRELEVANT',place_id=f'z:{i}',recipes=[],capacities={},knowledge={},input_targets={},output_targets={},active=False))
        inventory[fid]=dict(coal=1,steel=1,machine=1)
    if reverse:firms.reverse();routes.reverse();inventory=dict(reversed(list(inventory.items())));sinks.reverse()
    return dict(case_id=f'{treatment}_{policy}_{scale}',treatment=treatment,contention=policy,scale=scale,days=days,horizon=10,
                firms=firms,routes=routes,inventory=inventory,sinks=sinks,capacity_events=capacity_events,route_events=route_events,
                scope='All coal and steel S2; local observed requests/orders only. Scarcity C/D/E explicitly T1=T2=8 to sustain120-coal planned capacity; normal default5+5.')


def compatibility_case(policy='X1',days=600):
    case=old_case('normal',policy,days=days)
    # Old search/physical layout expects D and the directory cells. They are
    # sleeping storage in this control, not active extra suppliers.
    case['policy']='Q0';case['config']['replenishment']['B']['known_suppliers']=['A']
    for fid in case['config']['available_supplier_ids']:
        if fid=='A':continue
        case['config']['supplier_state'][fid]['active']=False
        case['config']['production'][fid]['capacity']=0
        case['config']['initial_inventory'][fid]['coal']=0
    case['case_id']=f'A_compatibility_{policy}'
    return case


def all_cases():
    cases=[]
    for letter,treatment in (('B','normal'),('C_DE','coal_scarcity'),('F','steel_scarcity'),('G','shutdown'),
                            ('H','asymmetric_lead'),('I','asymmetric_demand'),('J','step_up'),('K','recovery'),('M','bottleneck')):
        for policy in ('C0','C1'):
            case=make_network(treatment,policy);case['case_id']=f'{letter}_{case["case_id"]}';cases.append(case)
    for scale in ('S1','S5','S10'):
        for policy in ('C0','C1'):
            case=make_network('normal',policy,scale);case['case_id']=f'{scale}_{policy}';cases.append(case)
    return cases
