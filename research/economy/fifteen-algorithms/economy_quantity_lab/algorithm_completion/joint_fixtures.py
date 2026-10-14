"""NEW scoped joint fixtures. No changes to old experimental goldens."""
from copy import deepcopy
from programme_fixtures import living_case,GOODS

def joint_case(name='J_ALL15',days=30,split=True):
    c=living_case(days,labor=True,split=split);c['case_id']=name
    # Additional real population: one source worker and one foreign processor.
    for hid,employer,place,hours in [('FarmCrew','Farm','farm',4),('ForeignCrew','Baker2','east',2)]:
        c['firms'].append(dict(firm_id=hid,firm_type='HOUSEHOLD',place_id=place,recipes=[],capacities={},knowledge={'bread':['Baker2'],'beans':['Beaner'],'soap':[]},input_targets={},output_targets={}))
        c['inventory'][hid]={g:0 for g in GOODS};c['inventory'][hid]['bread']=2
        c['households'].append(dict(id=hid,members=1,adults=1,food_per_member=2,skill=1,max_travel=2,hours_per_worker=hours,known_jobs=['job-'+hid],known_lenders=[],known_fx=['FX'],choice='substitute',optional_durable_per_member=0))
        c['jobs'].append(dict(id='job-'+hid,employer=employer,place=place,positions=1,skill=1,hours=hours,wage_per_hour=1 if employer=='Farm' else 2))
        c['economics']['balances'][hid]=100;c['economics']['limits'][hid]={g:20 for g in GOODS}
        for seller,good in [('Baker2','bread'),('Beaner','beans')]:c['routes'].append(dict(seller_id=seller,buyer_id=hid,commodity=good,capacity=12,lead_time=2))
    for h in c['households']:
        if h['id'] in ('Ada','Household'):h.update(known_jobs=['job-beans'],known_lenders=['Lender'],known_fx=['FX']);c['economics']['balances'][h['id']]=0
    c['jobs'][0]['pay_delay']=5
    for fid in ('Transport','FX','Treasury','Lender','Founder'):
        c['firms'].append(dict(firm_id=fid,firm_type='INTERMEDIARY',place_id='west',recipes=[],capacities={},knowledge={},input_targets={},output_targets={}))
        c['inventory'][fid]={g:0 for g in GOODS};c['economics']['balances'][fid]=1000 if fid in ('FX','Lender') else 0;c['economics']['limits'][fid]={g:20 for g in GOODS}
    edges={}
    places=sorted({f['place_id'] for f in c['firms']})
    for origin in places:
        for dest in places:edges[origin+'~'+dest]=dict(**{'from':origin,'to':dest},duration=1 if origin==dest else 2,capacity=12,fee=1)
    paths={}
    fp={f['firm_id']:f['place_id'] for f in c['firms']}
    for r in c['routes']:paths[f'{r["seller_id"]}>{r["buyer_id"]}:{r["commodity"]}']=[[fp[r['seller_id']]+'~'+fp[r['buyer_id']]]]
    c['transport']=dict(edges=edges,paths=paths,carrier='Transport',known_edges={f['firm_id']:list(edges) for f in c['firms']})
    codes={k:'LOCAL' for k in c['economics']['balances']}
    for fid in ['FX','Baker2']+[h['id'] for h in c['households']]:
        key=fid+'@FOREIGN';c['economics']['balances'][key]=300 if fid=='FX' else 0;codes[key]='FOREIGN'
    c['currency']=dict(foreign='FOREIGN',dealer='FX',fee_recipient='Treasury',rate_numerator=2,rate_denominator=1,fee=1,monetary_unit=1,account_currencies=codes)
    c['sale_currency']={'Baker2:bread':'FOREIGN'};c['economics']['prices']['Baker2:bread']=1
    borrower='Ada' if split else 'Household'
    c['credit']=dict(agreements=[dict(id='joint-loan',lender='Lender',borrower=borrower,principal=24,interest=2,due_day=18,issue_day=1,requires_job=True)],adjustments=[])
    c['assets']=dict(issuers={'BEAN':'Beaner'},total_shares={'BEAN':10},holdings={'BEAN':{'Founder':10}},known_assets={'Founder':['BEAN'],'ForeignCrew':['BEAN']},message_delay=2,publication_interval=7,orders=[dict(id='joint-ask',actor='Founder',asset='BEAN',side='sell',day=1,quantity=6,limit=2),dict(id='joint-bid',actor='ForeignCrew',asset='BEAN',side='buy',day=3,last_day=20,quantity=2,limit=3,requires_public_receipts=True)],cancellations=[dict(day=22,order='joint-ask')],dividends=[dict(day=20,asset='BEAN',per_share=1,buffer=600),dict(day=28,asset='BEAN',per_share=1,buffer=600)])
    c['enable_relations']=True;c['relation_ttl']=6
    if split:
        next(f for f in c['firms'] if f['firm_id']=='Ada')['knowledge']={'bread':['Baker2'],'beans':[],'soap':[]}
        c['events']=[dict(day=7,kind='supplier_message',actor='Ada',good='beans',seller='Beaner',observed_day=2)]
    if name=='J_ALL15_N4':c['economics']['mode']='N4_EXPERIMENTAL'
    if name=='J2_joint_income':c['events']+= [dict(day=8,kind='job_close',job='job-beans')]
    if name=='J3_joint_shortage':
        for f in c['firms']:
            if f['recipes']:f['capacities']={g:0 for g in f['capacities']};c['inventory'][f['firm_id']]={g:0 for g in GOODS}
    if name=='J4_joint_substitute':next(f for f in c['firms'] if f['firm_id']=='Baker2')['capacities']['bread']=0;c['inventory']['Baker2'].update(bread=0,grain=0)
    if name=='J5_joint_logistics':c['events'] += [dict(day=10,kind='edge_capacity',edge='west~west',capacity=0),dict(day=16,kind='edge_capacity',edge='west~west',capacity=12)]
    if name=='J6_joint_information':
        next(h for h in c['households'] if h['id']=='Ada')['known_jobs']=[]
        c['events'] += [dict(day=6,kind='job_message',actor='Ada',job='job-beans',observed_day=1)]
    if name=='J7_no_credit':c['credit']['agreements']=[]
    if name=='J7_joint_default':c['events'] += [dict(day=2,kind='job_close',job='job-beans')]
    if name=='J8_no_fx':c['economics']['balances']['FX@FOREIGN']=0
    if name=='J9_no_asset':c['assets']['orders']=[];c['assets']['cancellations']=[]
    return c

def scaling_case(scale=1,named=False,dormant=0,days=30):
    c=living_case(days,labor=True,split=False);base=deepcopy(c['households'][0]);base_firm=deepcopy(c['firms'][-1]);base_routes=[deepcopy(r) for r in c['routes'] if r['buyer_id']=='Household']
    c['firms']=c['firms'][:-1];c['households']=[];c['routes']=[r for r in c['routes'] if r['buyer_id']!='Household'];c['inventory'].pop('Household');c['economics']['balances'].pop('Household');c['economics']['limits'].pop('Household')
    for i in range(scale if named else 1):
        hid=('Person' if named else 'Cohort')+str(i);h=deepcopy(base);h['id']=hid;factor=1 if named else scale;h['members']*=factor;h['adults']*=factor;c['households'].append(h)
        f=deepcopy(base_firm);f['firm_id']=hid;c['firms'].append(f);c['inventory'][hid]={g:0 for g in GOODS};c['inventory'][hid]['bread']=2*h['members'];c['economics']['balances'][hid]=10*h['members'];c['economics']['limits'][hid]={g:20 for g in GOODS}
        for route in base_routes:r=deepcopy(route);r['buyer_id']=hid;r['capacity']*=factor;c['routes'].append(r)
    for f in c['firms']:
        if f['recipes']:f['capacities']={k:v*scale for k,v in f['capacities'].items()};f['input_targets']={k:v*scale for k,v in f['input_targets'].items()};f['output_targets']={k:v*scale for k,v in f['output_targets'].items()};c['economics']['balances'][f['firm_id']]*=scale;c['inventory'][f['firm_id']]={k:v*scale for k,v in c['inventory'][f['firm_id']].items()}
    for j in c['jobs']:j['positions']*=scale
    for i in range(dormant):
        hid='Dormant'+str(i);c['firms'].append(dict(firm_id=hid,firm_type='DORMANT',place_id='elsewhere',active=False,recipes=[],capacities={},knowledge={},input_targets={},output_targets={}));c['inventory'][hid]={g:0 for g in GOODS};c['economics']['balances'][hid]=1;c['economics']['limits'][hid]={g:20 for g in GOODS}
    c['case_id']=f'G_SCALE_{scale}_{"named" if named else "cohort"}_dormant{dormant}'
    return c

def replicated_case(copies=4,days=30):
    """Disjoint local known networks inside ONE authority, shared edges per region."""
    c=living_case(days,labor=True);c['case_id']=f'G_REGION_COPIES_{copies}'
    for key in ('firms','households','routes','jobs'):c[key]=[]
    for key in ('inventory','labor_hours_per_output'):c[key]={}
    for key in ('balances','prices','limits'):c['economics'][key]={}
    edges={};paths={};known_edges={}
    for i in range(copies):
        p=f'R{i}/';a=living_case(days,labor=True)
        for f in a['firms']:
            old=f['firm_id'];f['firm_id']=p+old;f['place_id']=p+f['place_id'];f['knowledge']={g:[p+s for s in sellers] for g,sellers in f['knowledge'].items()}
            for r in f['recipes']:r['producer_id']=p+r['producer_id']
            c['firms'].append(f);c['inventory'][p+old]=a['inventory'][old];c['economics']['balances'][p+old]=a['economics']['balances'][old];c['economics']['limits'][p+old]=a['economics']['limits'][old]
        for h in a['households']:h['id']=p+h['id'];h['known_jobs']=[p+j for j in h['known_jobs']];c['households'].append(h)
        for j in a['jobs']:j['id']=p+j['id'];j['employer']=p+j['employer'];j['place']=p+j['place'];c['jobs'].append(j)
        for key,v in a['economics']['prices'].items():c['economics']['prices'][p+key]=v
        for key,v in a['labor_hours_per_output'].items():c['labor_hours_per_output'][p+key]=v
        for origin in ('farm','west','east'):
            for dest in ('farm','west','east'):edges[p+origin+'~'+dest]=dict(**{'from':p+origin,'to':p+dest},capacity=12,duration=1 if origin==dest else 2,fee=1)
        place={f['firm_id']:f['place_id'] for f in c['firms']}
        for r in a['routes']:
            r['seller_id']=p+r['seller_id'];r['buyer_id']=p+r['buyer_id'];c['routes'].append(r)
            paths[f'{r["seller_id"]}>{r["buyer_id"]}:{r["commodity"]}']=[[place[r['seller_id']]+'~'+place[r['buyer_id']].split('/')[1]]]
        for f in a['firms']:known_edges[f['firm_id']]=[e for e in edges if e.startswith(p)]
    c['firms'].append(dict(firm_id='Carrier',firm_type='CARRIER',place_id='service',recipes=[],capacities={},knowledge={},input_targets={},output_targets={}))
    c['inventory']['Carrier']={g:0 for g in GOODS};c['economics']['balances']['Carrier']=0;c['economics']['limits']['Carrier']={g:20 for g in GOODS}
    c['transport']=dict(edges=edges,paths=paths,known_edges=known_edges,carrier='Carrier')
    return c
