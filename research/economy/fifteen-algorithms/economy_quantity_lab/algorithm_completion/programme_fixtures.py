"""Explicit artificial food/household/labor fixtures, not historical renamed goods."""
from copy import deepcopy

GOODS=('grain','bread','beans','soap')

def recipe(fid,output,inputs=()):
    return dict(producer_id=fid,output_commodity=output,output_quantity=1,inputs=list(inputs))

def living_case(days=30, *, labor=False, choice='substitute', split=False):
    firms=[]
    specs=[('Farm','farm',{'grain':10},{'grain':40},{},[recipe('Farm','grain')]),
           ('Baker','west',{'bread':8,'soap':2},{'bread':14,'soap':4},{'grain':24},[recipe('Baker','bread',[('grain',2)]),recipe('Baker','soap',[('grain',1)])]),
           ('Baker2','east',{'bread':6},{'bread':12},{'grain':18},[recipe('Baker2','bread',[('grain',2)])]),
           ('Beaner','west',{'beans':8},{'beans':16},{},[recipe('Beaner','beans')])]
    for fid,place,capacity,output_targets,input_targets,recipes in specs:
        firms.append(dict(firm_id=fid,firm_type='PRODUCER',place_id=place,recipes=recipes,capacities=capacity,knowledge={g:['Farm'] for g in input_targets},input_targets=input_targets,output_targets=output_targets))
    household_specs=[('Ada',1,1),('Household',2,2)] if split else [('Household',3,3)]
    households=[]
    for hid,members,adults in household_specs:
        firms.append(dict(firm_id=hid,firm_type='HOUSEHOLD',place_id='west',recipes=[],capacities={},knowledge={'bread':['Baker','Baker2'],'beans':['Beaner'],'soap':['Baker']},input_targets={},output_targets={}))
        households.append(dict(id=hid,members=members,adults=adults,food_per_member=2,skill=1,max_travel=2,hours_per_worker=2,known_jobs=['job-beans','job-bread'],choice=choice,optional_durable_per_member=1))
    inventory={f['firm_id']:{g:0 for g in GOODS} for f in firms}
    inventory['Farm']['grain']=30;inventory['Baker'].update(grain=20,bread=12,soap=3);inventory['Baker2'].update(grain=12,bread=8);inventory['Beaner']['beans']=12
    for h in households:inventory[h['id']]['bread']=2*h['members']
    routes=[]
    for buyer in ('Baker','Baker2'):routes.append(dict(seller_id='Farm',buyer_id=buyer,commodity='grain',capacity=10,lead_time=1))
    for h in households:
        for seller,good in [('Baker','bread'),('Baker2','bread'),('Beaner','beans'),('Baker','soap')]:routes.append(dict(seller_id=seller,buyer_id=h['id'],commodity=good,capacity=12,lead_time=1 if seller!='Baker2' else 2))
    balances={f['firm_id']:1000 for f in firms}
    for h in households:balances[h['id']]=(0 if labor else 20)*h['members']
    prices={'Farm:grain':1,'Baker:bread':3,'Baker2:bread':4,'Beaner:beans':4,'Baker:soap':2}
    return dict(case_id='living',days=days,goods=list(GOODS),contention='C0',horizon=5,firms=firms,inventory=inventory,routes=routes,route_events={},sinks=[],households=households,enable_labor=labor,food_satisfaction={'bread':1,'beans':2},jobs=[dict(id='job-beans',employer='Beaner',place='west',positions=3,skill=1,hours=2,wage_per_hour=2),dict(id='job-bread',employer='Baker',place='west',positions=2,skill=1,hours=2,wage_per_hour=2)],labor_hours_per_output={'Farm:grain':1,'Baker:bread':1,'Baker:soap':1,'Baker2:bread':1,'Beaner:beans':1},economics=dict(mode='N2',balances=balances,prices=prices,limits={f['firm_id']:{g:20 for g in GOODS} for f in firms},terminal_prices={},tick=1,feedback=True),events=[],stock_horizon=4)

def scenario(name,days=30):
    c=living_case(days,labor=name not in ('B_substitute','B_fixed','B_income','B_price','B_unknown','B_shortage'))
    c['case_id']=name
    if name=='B_fixed':c['households'][0]['choice']='fixed'
    if name=='B_income':c['economics']['balances']['Household']=8
    if name=='B_price':c['economics']['prices']['Beaner:beans']=12
    if name=='B_unknown':c['firms'][-1]['knowledge']['beans']=[]
    if name in ('B_shortage','J3_shortage'):
        for f in c['firms']:
            if f['firm_id'] in ('Baker','Baker2','Beaner'):
                f['capacities']={g:0 for g in f['capacities']};c['inventory'][f['firm_id']].update(bread=0,beans=0)
    if name=='J2_income':c['events']=[dict(day=8,kind='job_close',job='job-beans'),dict(day=8,kind='job_close',job='job-bread')]
    if name=='C_unpaid':c['economics']['balances']['Beaner']=0;c['economics']['balances']['Baker']=0
    if name=='C_absent':c['events']=[dict(day=d,kind='absence',actor='Household') for d in range(3,days+1)]
    if name=='C_skill':c['households'][0]['skill']=0
    if name=='C_far':c['households'][0]['max_travel']=0;c['jobs'][0]['place']='east';c['jobs'][1]['place']='east'
    if name=='C_unknown':c['households'][0]['known_jobs']=[]
    if name=='J6_information':
        c['households'][0]['known_jobs']=[];c['events']=[dict(day=6,kind='job_message',actor='Household',job='job-beans',observed_day=1)]
    if name=='C_N4':c['economics']['mode']='N4_EXPERIMENTAL'
    return c

def spatial_case(name='D_shared',days=30):
    c=living_case(days,labor=True,split=True);c['case_id']=name
    c['firms'].append(dict(firm_id='Transport',firm_type='CARRIER',place_id='west',recipes=[],capacities={},knowledge={},input_targets={},output_targets={}))
    c['inventory']['Transport']={g:0 for g in GOODS};c['economics']['balances']['Transport']=0;c['economics']['limits']['Transport']={g:20 for g in GOODS}
    edges={'local':dict(**{'from':'west','to':'west'},capacity=5,duration=1,fee=1),'farm-road':dict(**{'from':'farm','to':'west'},capacity=6,duration=1,fee=1),'east-west':dict(**{'from':'east','to':'west'},capacity=3,duration=2,fee=1),'west-east':dict(**{'from':'west','to':'east'},capacity=3,duration=2,fee=1),'ferry':dict(**{'from':'east','to':'west'},capacity=2,duration=3,fee=2)}
    places={f['firm_id']:f['place_id'] for f in c['firms']};paths={}
    for r in c['routes']:
        origin,dest=places[r['seller_id']],places[r['buyer_id']]
        options=[['local']] if origin==dest=='west' else [['east-west'],['ferry']] if origin=='east' and dest=='west' else [['farm-road']] if dest=='west' else [['farm-road','west-east']]
        paths[f'{r["seller_id"]}>{r["buyer_id"]}:{r["commodity"]}']=options
    c['transport']=dict(edges=edges,paths=paths,carrier='Transport',known_edges={f['firm_id']:list(edges) for f in c['firms']})
    if name=='J5_interruption':c['events']=[dict(day=8,kind='edge_capacity',edge='local',capacity=0),dict(day=15,kind='edge_capacity',edge='local',capacity=5)]
    if name=='D_in_transit':
        c['events']=[dict(day=3,kind='edge_capacity',edge='east-west',capacity=0),dict(day=8,kind='edge_capacity',edge='east-west',capacity=3)]
        for f in c['firms']:
            if f['firm_type']=='HOUSEHOLD':f['knowledge']={'bread':['Baker2'],'beans':[],'soap':[]}
    if name=='D_alternative':
        c['events']=[dict(day=1,kind='edge_capacity',edge='east-west',capacity=0)];c['economics']['prices']['Beaner:beans']=30;c['economics']['prices']['Baker:bread']=30
    if name=='D_no_alternative':
        c=spatial_case('D_alternative',days);c['case_id']=name
        for hid in c['transport']['known_edges']:c['transport']['known_edges'][hid].remove('ferry')
    if name=='D_relation':
        c['enable_relations']=True;c['relation_ttl']=6
        c['economics']['price_events']=[dict(day=8,seller='Beaner',commodity='beans',price=12)]
    if name=='D_relation_off':c=spatial_case('D_relation',days);c['case_id']=name;c['enable_relations']=False
    if name=='D_supplier_info':
        for f in c['firms']:
            if f['firm_type']=='HOUSEHOLD':f['knowledge']['beans']=[]
        c['events']=[dict(day=7,kind='supplier_message',actor='Ada',good='beans',seller='Beaner',observed_day=2)]
    return c

def credit_case(name='E_credit',days=30):
    c=living_case(days,labor=True);c['case_id']=name
    for j in c['jobs']:j['pay_delay']=7
    c['firms'].append(dict(firm_id='Lender',firm_type='FUNDED_LENDER',place_id='west',recipes=[],capacities={},knowledge={},input_targets={},output_targets={}))
    c['inventory']['Lender']={g:0 for g in GOODS};c['economics']['balances']['Lender']=1000;c['economics']['limits']['Lender']={g:20 for g in GOODS}
    c['households'][0]['known_lenders']=['Lender']
    c['credit']=dict(agreements=[dict(id='loan-1',lender='Lender',borrower='Household',principal=72,interest=0,issue_day=1,due_day=18,requires_job=True)],adjustments=[])
    if name=='E_no_credit':c['credit']['agreements']=[]
    if name=='E_default':c['events']=[dict(day=2,kind='job_close',job='job-beans'),dict(day=2,kind='job_close',job='job-bread')]
    if name=='E_interest':c['credit']['agreements'][0]['interest']=6
    if name=='E_no_goods':
        for f in c['firms']:
            if f['firm_id'] in ('Baker','Baker2','Beaner'):f['capacities']={g:0 for g in f['capacities']};c['inventory'][f['firm_id']].update(bread=0,beans=0)
    if name=='E_unfunded':c['economics']['balances']['Lender']=0
    if name=='E_unknown':c['households'][0]['known_lenders']=[]
    return c

def currency_case(name='F_trade',days=30):
    c=spatial_case('D_in_transit',days);c['case_id']=name;c['events']=[]
    c['jobs'][0].update(employer='Baker2',place='east')
    for h in c['households']:h['known_jobs']=['job-beans']
    for h in c['households']:h['known_fx']=['FX']
    for fid in ('FX','Treasury'):
        c['firms'].append(dict(firm_id=fid,firm_type='INTERMEDIARY',place_id='west',recipes=[],capacities={},knowledge={},input_targets={},output_targets={}))
        c['inventory'][fid]={g:0 for g in GOODS};c['economics']['balances'][fid]=1000 if fid=='FX' else 0;c['economics']['limits'][fid]={g:20 for g in GOODS}
    # Foreign balances are account keys of the same named actors, not wallets.
    codes={k:'LOCAL' for k in c['economics']['balances']}
    for fid in ['FX','Baker2']+[h['id'] for h in c['households']]:
        key=fid+'@FOREIGN';c['economics']['balances'][key]=200 if fid=='FX' else 0;codes[key]='FOREIGN'
    c['currency']=dict(foreign='FOREIGN',dealer='FX',fee_recipient='Treasury',rate_numerator=2,rate_denominator=1,fee=1,monetary_unit=1,account_currencies=codes)
    c['sale_currency']={'Baker2:bread':'FOREIGN'};c['economics']['prices']['Baker2:bread']=1
    if name=='F_no_fx':c['economics']['balances']['FX@FOREIGN']=0
    if name=='F_unknown_fx':
        for h in c['households']:h['known_fx']=[]
    if name=='F_closed':c['events']=[dict(day=1,kind='edge_capacity',edge='east-west',capacity=0),dict(day=1,kind='edge_capacity',edge='ferry',capacity=0)]
    if name=='F_info':
        for f in c['firms']:
            if f['firm_type']=='HOUSEHOLD':f['knowledge']['bread']=[]
        c['events']=[dict(day=7,kind='supplier_message',actor='Ada',good='bread',seller='Baker2',observed_day=2)]
    if name=='F_units_10':
        for k in c['economics']['balances']:c['economics']['balances'][k]*=10
        for k in c['economics']['prices']:c['economics']['prices'][k]*=10
        for limits in c['economics']['limits'].values():
            for k in limits:limits[k]*=10
        for j in c['jobs']:j['wage_per_hour']*=10
        for e in c['transport']['edges'].values():e['fee']*=10
        c['currency']['fee']*=10;c['currency']['monetary_unit']=10;c['economics']['tick']*=10
    return c

def asset_case(name='F_asset',days=30):
    c=spatial_case('D_shared',days);c['case_id']=name
    for h in c['households']:c['economics']['balances'][h['id']]=100*h['members']
    c['jobs'][0]['wage_per_hour']=1
    for h in c['households']:h['known_jobs']=['job-beans']
    for f in c['firms']:
        if f['firm_type']=='HOUSEHOLD':f['knowledge']={'beans':['Beaner'],'bread':[],'soap':[]}
    c['firms'].append(dict(firm_id='Founder',firm_type='INVESTOR',place_id='west',recipes=[],capacities={},knowledge={},input_targets={},output_targets={}))
    c['inventory']['Founder']={g:0 for g in GOODS};c['economics']['balances']['Founder']=0;c['economics']['limits']['Founder']={g:20 for g in GOODS}
    c['assets']=dict(issuers={'BEAN':'Beaner'},total_shares={'BEAN':10},holdings={'BEAN':{'Founder':10}},known_assets={'Founder':['BEAN'],'Ada':['BEAN']},message_delay=2,publication_interval=7,orders=[dict(id='ask-1',actor='Founder',asset='BEAN',side='sell',day=1,quantity=6,limit=2),dict(id='bid-1',actor='Ada',asset='BEAN',side='buy',day=3,last_day=12,quantity=4,limit=3,requires_public_receipts=True)],cancellations=[dict(day=18,order='ask-1')],dividends=[dict(day=15,asset='BEAN',per_share=1,buffer=800),dict(day=25,asset='BEAN',per_share=1,buffer=800)])
    if name=='F_asset_off':c['assets']['orders']=[];c['assets']['cancellations']=[]
    if name=='F_asset_low_liquidity':
        for h in c['households']:c['economics']['balances'][h['id']]=40*h['members']
    if name=='F_asset_no_info':c['assets']['message_delay']=40
    if name=='F_asset_no_funds':c['economics']['balances']['Ada']=0;c['jobs'][0]['wage_per_hour']=0
    if name=='F_asset_no_cashflow':
        for f in c['firms']:
            if f['firm_type']=='HOUSEHOLD':f['knowledge']['beans']=[]
    return c
