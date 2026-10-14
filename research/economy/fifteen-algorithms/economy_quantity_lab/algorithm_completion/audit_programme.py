"""Independent reconstruction of new recorded facts. NO runtime/strategy imports."""
import argparse,gzip,json,hashlib
from collections import defaultdict
from copy import deepcopy
from fractions import Fraction
from math import ceil
from pathlib import Path

def check(v,msg):
    if not v:raise ValueError(msg)
def integer(v,positive=False):
    check(type(v) is int and v>=(1 if positive else 0),'integer/quantity domain');return v
def records(p):
    with gzip.open(p,'rt',encoding='utf-8') as f:
        for line in f:yield json.loads(line)

def audit(rows):
    rows=iter(rows);initial=next(rows);check(initial['seq']==1 and initial['event']=='initial' and initial['day']==0,'initial record')
    fixture=initial['fixture'];state=initial['state'];stock=deepcopy(state['stock']);cash=deepcopy(state['cash']);starting=deepcopy(cash)
    check(stock==fixture['inventory'] and cash=={k:dict(balance=v,reserved=0) for k,v in fixture['economics']['balances'].items()},'initial authoritative identity')
    currency_codes=fixture.get('currency',{}).get('account_currencies',{k:'LOCAL' for k in cash})
    households={h['id']:deepcopy(h) for h in fixture['households']};firms={f['firm_id']:f for f in fixture['firms']};jobs={j['id']:deepcopy(j) for j in fixture.get('jobs',[])}
    knowledge={f['firm_id']:{g:set(ids) for g,ids in f['knowledge'].items()} for f in fixture['firms']}
    routes={f'{r["seller_id"]}>{r["buyer_id"]}:{r["commodity"]}':r for r in fixture['routes']}
    prices={tuple(k.split(':')):v for k,v in fixture['economics']['prices'].items()};pending_prices={}
    orders={};cargo={};contracts={};claims={};work_ids=set();transfers=set();seq=1;day=0;events=1
    edges=deepcopy(fixture.get('transport',{}).get('edges',{}));freight={};paths={};journeys={};edge_used=defaultdict(int);relations={};delivered_today=set();positions_seen=set()
    loans={}
    cfg_assets=fixture.get('assets',{});shares=deepcopy(cfg_assets.get('holdings',{}));share_reserved={a:{k:0 for k in h} for a,h in shares.items()};asset_orders={};publications={};financial_known={};cash_received=defaultdict(int);cash_paid=defaultdict(int)
    labor_hours=defaultdict(int);labor_used=defaultdict(int);worker_hours=defaultdict(int);produced=defaultdict(int);consumed=defaultdict(int);plans={};need={};satisfied=defaultdict(int);need_totals=defaultdict(int);consumption_totals=defaultdict(int)
    def money_bounds():
        check(all(type(v['balance']) is int and type(v['reserved']) is int and 0<=v['reserved']<=v['balance'] for v in cash.values()),'cash bounds')
        for code in set(currency_codes.values()):check(sum(v['balance'] for k,v in cash.items() if currency_codes[k]==code)==sum(v['balance'] for k,v in starting.items() if currency_codes[k]==code),'per-currency conservation')
    for r in rows:
        events+=1;seq+=1;check(r['seq']==seq,'duplicate/missing event sequence');d=integer(r['day']);check(day<=d<=day+1,'world time order')
        if d!=day:
            check(d==day+1,'skipped day');day=d;labor_hours.clear();labor_used.clear();worker_hours.clear();produced.clear();consumed.clear();plans.clear();need.clear();satisfied.clear()
            prices.update(pending_prices);pending_prices.clear();edge_used.clear();delivered_today.clear();positions_seen.clear()
        e=r['event']
        prior_cash={k:v['balance'] for k,v in cash.items()}
        if e=='message':
            spec=r['spec'];check(spec['day']==day,'message early delivery')
            check(spec in fixture['events'],'unscheduled information intervention')
            if spec['kind']=='job_message':
                check(spec['observed_day']<=day,'future information');h=households[spec['actor']];h['known_jobs']=sorted(set(h['known_jobs'])|{spec['job']})
            elif spec['kind']=='job_close':jobs[spec['job']]['positions']=0
            elif spec['kind']=='edge_capacity':edges[spec['edge']]['capacity']=spec['capacity']
            elif spec['kind']=='supplier_message':
                check(spec['observed_day']<=day,'future supplier information');knowledge[spec['actor']].setdefault(spec['good'],set()).add(spec['seller'])
            elif spec['kind']=='relation_invalid':relations.pop('|'.join((spec['actor'],spec['good'],spec['seller'])),None)
            elif spec['kind']!='absence':raise ValueError('unknown message')
        elif e=='posted_price_change':
            s=r['spec'];key=(s['seller'],s['commodity']);check(s in fixture['economics'].get('price_events',[]) and s['day']==day and r['old']==prices[key] and r['new']==s['price'],'posted-price event provenance');prices[key]=integer(r['new'],True)
        elif e=='job_offer':
            check(r['job'] in households[r['actor']]['known_jobs'],'unknown job offer')
        elif e=='employment':
            h=households[r['actor']];j=jobs[r['job']];workers=integer(r['workers'],True)
            check(r['actor'] not in contracts and r['job'] in h['known_jobs'],'unknown/duplicate employment')
            distance=0 if firms[r['actor']]['place_id']==j['place'] else 2
            check(h['skill']>=j['skill'] and distance<=h['max_travel'],'job eligibility')
            check(workers<=h['adults'] and workers+sum(c['workers'] for c in contracts.values() if c['job']==r['job'])<=j['positions'],'vacancy oversubscribed')
            contracts[r['actor']]=dict(job=r['job'],workers=workers)
        elif e=='employment_end':
            check(contracts[r['actor']]['job']==r['job'],'employment end identity');del contracts[r['actor']]
        elif e=='work':
            wid=r['work_id'];h=households[r['actor']];j=jobs[r['job']];q=integer(r['hours'],True)
            check(wid not in work_ids and r['actor'] in contracts,'duplicate/uncontracted work');work_ids.add(wid)
            c=contracts[r['actor']];check(c['job']==r['job'] and c['workers']==r['workers'] and r['employer']==j['employer'] and r['wage_per_hour']==j['wage_per_hour'],'work contract attribution')
            worker_hours[r['actor']]+=q;check(worker_hours[r['actor']]<=c['workers']*min(h['hours_per_worker'],j['hours']),'labor time duplicated')
            check(not any(x['day']==day and x['kind']=='absence' and x['actor']==r['actor'] for x in fixture['events']),'work during absence')
            labor_hours[r['employer']]+=q
        elif e=='wage_accrued':
            check(r['claim_id'] in work_ids and r['claim_id'] not in claims,'wage without unique work')
            j=jobs[r['job']];check(r['amount']==r['remaining']==r['hours']*j['wage_per_hour'],'wage amount')
            claims[r['claim_id']]={k:r[k] for k in ('worker','employer','hours','amount','remaining','work_day','job')}
            if 'due_day' in r:check(r['due_day']==r['work_day']+j.get('pay_delay',0),'wage maturity');claims[r['claim_id']]['due_day']=r['due_day']
        elif e=='cash_transfer':
            check(r['event_id'] not in transfers,'duplicate payment');transfers.add(r['event_id']);q=integer(r['amount'],True)
            buyer=r['buyer'];seller=r['seller'];released=r.get('reserved_release',0);check(buyer!=seller and q<=(cash[buyer]['reserved'] if released else cash[buyer]['balance']-cash[buyer]['reserved']),'unfunded transfer')
            check(currency_codes[buyer]==currency_codes[seller],'currency payment mismatch')
            if r['reason']=='wage':
                check(r['claim_id'] in claims,'unearned wage');c=claims[r['claim_id']]
                check((buyer,seller)==(c['employer'],c['worker']) and q<=c['remaining'],'wage parties/duplicate settlement');c['remaining']-=q
                check(day>=c.get('due_day',c['work_day']),'future wages spent')
            elif r['reason']=='freight':
                f=freight[r['order_id']];check(seller==fixture['transport']['carrier'] and buyer==f['buyer'] and released==q and q<=f['remaining'],'freight funds/parties');f['remaining']-=q;cash[buyer]['reserved']-=q
            elif r['reason']=='loan_repayment':
                loan=loans[r['loan_id']];check((buyer,seller)==(loan['borrower'],loan['lender']) and q<=loan['remaining'],'debt repayment parties/amount');loan['repaid']+=q;loan['remaining']-=q;loan['creditor_carrying_value']=min(loan['creditor_carrying_value'],loan['remaining'])
                if not loan['remaining']:loan['status']='SETTLED'
            else:raise ValueError('unrecognized cashflow reason')
            cash[buyer]['balance']-=q;cash[seller]['balance']+=q
        elif e=='loan_issued':
            lid=r['loan_id'];check(lid not in loans,'duplicate credit');spec=next(x for x in fixture['credit']['agreements'] if x['id']==lid)
            check(spec['issue_day']==day and r['principal']==spec['principal'] and r['interest']==spec.get('interest',0) and r['due_day']==spec['due_day'],'loan agreement facts')
            check((r['lender'],r['borrower'])==(spec['lender'],spec['borrower']) and r['remaining']==r['principal']+r['interest'],'paired creditor/debtor')
            check(r['lender'] in households[r['borrower']].get('known_lenders',[]) and (not spec.get('requires_job',True) or r['borrower'] in contracts),'loan knowledge/employment eligibility')
            q=integer(r['principal'],True);check(q<=cash[r['lender']]['balance']-cash[r['lender']]['reserved'],'unfunded lending');cash[r['lender']]['balance']-=q;cash[r['borrower']]['balance']+=q
            loans[lid]={k:r[k] for k in ('lender','borrower','principal','interest','due_day','repaid','remaining','creditor_carrying_value','status')}
        elif e=='loan_overdue':
            loan=loans[r['loan_id']];check(day>=loan['due_day'] and r['remaining']==loan['remaining']>0,'default boundary');loan['status']='OVERDUE'
        elif e=='loan_impaired':
            check(dict(day=day,loan=r['loan_id'],kind='impair',amount=r['amount']) in fixture['credit']['adjustments'],'impairment authorization')
            loan=loans[r['loan_id']];q=integer(r['amount'],True);check(q<=loan['creditor_carrying_value'],'creditor carrying value');loan['creditor_carrying_value']-=q
        elif e=='loan_forgiven':
            check(dict(day=day,loan=r['loan_id'],kind='forgive',amount=r['amount']) in fixture['credit']['adjustments'],'debt release authorization')
            loan=loans[r['loan_id']];q=integer(r['amount'],True);check((r['lender'],r['borrower'])==(loan['lender'],loan['borrower']) and q<=loan['remaining'],'paired debt release');loan['remaining']-=q;loan['creditor_carrying_value']=min(loan['creditor_carrying_value'],loan['remaining'])
            if not loan['remaining']:loan['status']='SETTLED'
        elif e=='loan_rejected':pass
        elif e=='fx_exchange':
            cfg=fixture['currency'];actor=r['actor'];foreign=cfg['foreign'];dealer=cfg['dealer'];q=integer(r['quantity'],True)
            check(r['event_id'] not in transfers and dealer in households[actor].get('known_fx',[]),'duplicate/unknown FX');transfers.add(r['event_id'])
            unit=cfg.get('monetary_unit',1);principal=ceil(Fraction(q*cfg['rate_numerator'],cfg['rate_denominator']*unit))*unit;fee=cfg['fee']
            expected=[[actor,dealer,principal],[dealer+'@'+foreign,actor+'@'+foreign,q]]+([[actor,cfg['fee_recipient'],fee]] if fee else [])
            check(r['dealer']==dealer and r['foreign']==foreign and r['rate']==[cfg['rate_numerator'],cfg['rate_denominator']] and r['local_cost']==principal+fee and r['fee']==fee and [list(x) for x in r['legs']]==expected,'atomic exchange legs/rate/fee')
            debits=defaultdict(int)
            for buyer,seller,amount in expected:check(currency_codes[buyer]==currency_codes[seller],'FX leg denomination');debits[buyer]+=amount
            check(all(q<=cash[k]['balance']-cash[k]['reserved'] for k,q in debits.items()),'unfunded FX batch')
            for buyer,seller,amount in expected:cash[buyer]['balance']-=amount;cash[seller]['balance']+=amount
        elif e=='financial_publication':
            asset=r['asset'];issuer=cfg_assets['issuers'][asset]
            check(r['issuer']==issuer and r['observed_day']==day and r['facts']==dict(available=cash[issuer]['balance']-cash[issuer]['reserved'],receipts=cash_received[issuer],payments=cash_paid[issuer]),'financial fact provenance')
            publications[(asset,day)]=deepcopy(r['facts'])
        elif e=='financial_message':
            m=r['message'];key=(m['asset'],m['observed_day'])
            check(key in publications and m['facts']==publications[key] and m['observed_day']+cfg_assets['message_delay']==m['received_day']==day and m['asset'] in cfg_assets['known_assets'].get(m['recipient'],[]),'financial information timing/source')
            financial_known[(m['recipient'],m['asset'])]=deepcopy(m)
        elif e=='asset_order':
            oid=r['order_id'];actor=r['actor'];asset=r['asset'];q=integer(r['quantity'],True);limit=integer(r['limit'],True);side=r['side'];spec=next(x for x in cfg_assets['orders'] if x['id']==oid)
            check(oid not in asset_orders and asset in cfg_assets['known_assets'].get(actor,[]) and spec['day']<=day<=spec.get('last_day',spec['day']),'unknown/duplicate/timing asset order')
            check((actor,asset,q,limit,side)==(spec['actor'],spec['asset'],spec['quantity'],spec['limit'],spec['side']) and r['remaining']==q and r['status']=='OPEN','asset order facts')
            m=financial_known.get((actor,asset));check(r['information']==m,'asset information frontier')
            if spec.get('requires_public_receipts'):check(m and m['facts']['receipts']>0,'future/absent company information')
            if side=='buy':check(q*limit<=cash[actor]['balance']-cash[actor]['reserved'],'double-used asset cash');cash[actor]['reserved']+=q*limit
            elif side=='sell':check(q<=shares[asset].get(actor,0)-share_reserved[asset].get(actor,0),'unowned shares sold');share_reserved[asset][actor]=share_reserved[asset].get(actor,0)+q
            else:raise ValueError('asset side')
            asset_orders[oid]={k:r[k] for k in ('actor','asset','side','quantity','remaining','limit','status')}
        elif e=='asset_cancel':
            o=asset_orders[r['order_id']];q=r['quantity'];check(o['status']=='OPEN' and q==o['remaining'],'asset cancel closed/quantity')
            check(dict(day=day,order=r['order_id']) in cfg_assets.get('cancellations',[]),'unscheduled cancellation')
            if o['side']=='buy':cash[o['actor']]['reserved']-=q*o['limit']
            else:share_reserved[o['asset']][o['actor']]-=q
            o['remaining']=0;o['status']='CANCELLED'
        elif e=='asset_trade':
            check(r['event_id'] not in transfers,'duplicate asset settlement event');transfers.add(r['event_id'])
            b=asset_orders[r['bid_id']];a=asset_orders[r['ask_id']];q=integer(r['quantity'],True);buyer=r['buyer'];seller=r['seller'];asset=r['asset'];price=r['price']
            check(b['status']==a['status']=='OPEN' and b['side']=='buy' and a['side']=='sell' and b['actor']==buyer and a['actor']==seller and buyer!=seller and b['asset']==a['asset']==asset and price==a['limit']<=b['limit'],'asset pair/locked limits')
            check(q<=min(b['remaining'],a['remaining'],shares[asset].get(seller,0),share_reserved[asset].get(seller,0)),'resale of unavailable shares')
            value=q*price;release=q*b['limit'];check(r['cash']==value and r['reserved_release']==release and release<=cash[buyer]['reserved'],'asset delivery funds')
            cash[buyer]['balance']-=value;cash[buyer]['reserved']-=release;cash[seller]['balance']+=value;shares[asset][seller]-=q;shares[asset][buyer]=shares[asset].get(buyer,0)+q;share_reserved[asset][seller]-=q
            for o in (b,a):
                o['remaining']-=q
                if not o['remaining']:o['status']='FILLED'
        elif e=='asset_dividend':
            check(r['event_id'] not in transfers,'duplicate dividend event');transfers.add(r['event_id'])
            asset=r['asset'];issuer=cfg_assets['issuers'][asset];spec=next(x for x in cfg_assets['dividends'] if x['day']==day and x['asset']==asset)
            obligations=sum(c['remaining'] for c in claims.values() if c['employer']==issuer)+sum(l['remaining'] for l in loans.values() if l['borrower']==issuer)
            surplus=max(0,min(cash[issuer]['balance']-cash[issuer]['reserved']-spec['buffer']-obligations,cash_received[issuer]-cash_paid[issuer]));per=integer(r['per_share'],True)
            check(r['issuer']==issuer and r['surplus']==surplus and per<=spec['per_share'] and per*cfg_assets['total_shares'][asset]<=surplus,'unfunded issuer distribution')
            payments={k:q*per for k,q in shares[asset].items() if q and k!=issuer};check(r['payments']==payments,'shareholder dividends')
            for holder,q in payments.items():cash[issuer]['balance']-=q;cash[holder]['balance']+=q
        elif e in ('asset_rejected','dividend_unavailable'):pass
        elif e=='production_plan':
            key=(r['actor'],r['good']);check(key not in plans,'duplicate production command');plans[key]=integer(r['actual'])
            check(r['actual']<=firms[r['actor']]['capacities'][r['good']],'production capacity')
            if fixture['enable_labor']:
                used=r['actual']*fixture['labor_hours_per_output'][r['actor']+':'+r['good']]
                check(used==r['hours_used'],'labor unit attribution');labor_used[r['actor']]+=used;check(labor_used[r['actor']]<=labor_hours[r['actor']],'production without labor')
        elif e in ('produced','consumed'):
            q=integer(r['quantity'],True);fid=r['firm'];g=r['commodity']
            if e=='produced':produced[(fid,g)]+=q;stock[fid][g]+=q;check(produced[(fid,g)]==plans[(fid,g)],'actual output differs from command')
            else:check(q<=stock[fid][g],'input shortage');stock[fid][g]-=q;consumed[(fid,g)]+=q
        elif e=='needs':
            hid=r['actor'];check(hid not in need and r['members']==households[hid]['members'],'population/need duplicate')
            expected=r['members']*households[hid]['food_per_member'];check(r['current']==expected,'need disappeared with budget');need[hid]=expected;need_totals[hid]+=expected
        elif e=='visible_offer':
            check(r['seller'] in knowledge[r['actor']].get(r['good'],set()),'unknown goods offer')
            check(r['price']==prices[(r['seller'],r['good'])],'quote changed/early price information')
            check(r['eta']>day,'impossible same-day delivery')
        elif e=='purchase_choice':
            check(r['seller'] in knowledge[r['actor']].get(r['good'],set()),'unknown purchase choice')
        elif e=='accepted':
            oid=integer(r['order_id'],True);q=integer(r['quantity'],True);price=integer(r['locked_price'],True);check(oid not in orders,'duplicate accepted order')
            route=routes[r['route']];buyer=r['buyer'];seller=r['seller'];g=r['commodity']
            check((buyer,seller,g)==(route['buyer_id'],route['seller_id'],route['commodity']),'route parties')
            check(seller in knowledge[buyer].get(g,set()) and price==prices[(seller,g)],'unknown/stale acceptance quote')
            code=fixture.get('sale_currency',{}).get(seller+':'+g,'LOCAL');cb=buyer if code=='LOCAL' else buyer+'@'+code;cs=seller if code=='LOCAL' else seller+'@'+code
            check(r.get('cash_buyer',buyer)==cb and r.get('cash_seller',seller)==cs and currency_codes[cb]==currency_codes[cs]==code,'sale settlement denomination')
            committed=sum(o['pending'] for o in orders.values() if o['seller']==seller and o['good']==g)
            value=q*price;check(value==r['reserved_value'] and value<=cash[cb]['balance']-cash[cb]['reserved'],'unfunded goods commitment')
            check(q<=stock[seller][g]-committed,'shared stock oversold');cash[cb]['reserved']+=value
            orders[oid]=dict(route=r['route'],buyer=buyer,seller=seller,cash_buyer=cb,cash_seller=cs,good=g,price=price,quantity=q,pending=q,delivered=0,cancelled=0,shipments={})
        elif e=='request':
            check(r['supplier_id'] in knowledge[r['buyer_id']].get(r['commodity'],set()),'unknown request')
            check(r['requested_quantity']==r['accepted_quantity']+r['rejected_quantity'],'request quantity partition')
            if r['order_id']:
                o=orders[r['order_id']];check((o['buyer'],o['seller'],o['good'],o['quantity'])==(r['buyer_id'],r['supplier_id'],r['commodity'],r['accepted_quantity']),'request/order attribution')
        elif e=='transport_reserved':
            oid=r['order_id'];o=orders[oid];check(oid not in paths,'transport reservation duplicate');paths[oid]=r['path']
            known=fixture['transport']['known_edges'].get(o['buyer'],list(edges));check(all(e in known for e in r['path']),'unknown path')
            node=firms[o['seller']]['place_id']
            for edge in r['path']:check(edges[edge]['from']==node,'disconnected path');node=edges[edge]['to']
            check(node==firms[o['buyer']]['place_id'],'path destination')
            fee=sum(edges[e]['fee'] for e in r['path']);check(r['per_unit']==fee and r['amount']==fee*o['quantity'],'freight amount')
            cash[o['buyer']]['reserved']+=r['amount'];freight[oid]=dict(buyer=o['buyer'],per_unit=fee,remaining=r['amount'])
        elif e=='transport_departed':
            o=orders[r['order_id']];check(r['path']==paths[r['order_id']],'cargo path identity')
            for edge in r['path']:edge_used[edge]+=r['quantity'];check(edge_used[edge]<=edges[edge]['capacity'],'shared edge capacity exceeded')
            check(r['shipment_id'] in cargo,'journey without cargo');journeys[r['shipment_id']]=dict(path=r['path'],position=0,elapsed=0)
        elif e=='transport_position':
            sid=r['shipment_id'];check(sid not in positions_seen and sid in journeys,'duplicate/unowned movement');positions_seen.add(sid);j=journeys[sid];edge=edges[j['path'][j['position']]]
            edge_id=j['path'][j['position']]
            if edge['capacity']-edge_used[edge_id]>=cargo[sid]['quantity']:
                edge_used[edge_id]+=cargo[sid]['quantity']
                j['elapsed']+=1
                if j['elapsed']==edge['duration']:j['position']+=1;j['elapsed']=0
            check((r['position'],r['elapsed'])==(j['position'],j['elapsed']),'transport position/time')
        elif e=='transit_delay':
            c=cargo[r['shipment_id']];check(c['arrival_day']==r['old_arrival'] and r['new_arrival']==day+1,'delay scheduler identity');c['arrival_day']=r['new_arrival'];orders[c['order']]['shipments'][str(r['shipment_id'])]['arrival_day']=r['new_arrival']
        elif e=='freight_released':
            f=freight[r['order_id']];check(r['buyer']==f['buyer'] and r['amount']<=f['remaining'],'freight release');f['remaining']-=r['amount'];cash[f['buyer']]['reserved']-=r['amount']
        elif e=='relation_delivery':
            oid=r['order_id'];o=orders[oid];check(oid in delivered_today and (r['buyer'],r['seller'],r['good'])==(o['buyer'],o['seller'],o['good']),'invented cooperation history');relations['|'.join((r['buyer'],r['good'],r['seller']))]=dict(last_delivery_day=day)
        elif e=='dispatched':
            o=orders[r['order_id']];q=integer(r['quantity'],True);sid=integer(r['shipment_id'],True)
            check(sid not in cargo and q<=o['pending'] and q<=stock[o['seller']][o['good']],'duplicate/unbacked dispatch')
            check(r['arrival_day']>day,'transport time')
            stock[o['seller']][o['good']]-=q;o['pending']-=q
            fact=dict(quantity=q,arrival_day=r['arrival_day'],dispatch_day=day);o['shipments'][str(sid)]=fact;cargo[sid]=dict(order=r['order_id'],**fact)
        elif e=='arrived':
            sid=r['shipment_id'];check(sid in cargo,'duplicate/unshipped arrival');c=cargo.pop(sid);o=orders[r['order_id']]
            check(c['order']==r['order_id'] and c['quantity']==r['quantity'] and c['arrival_day']==day,'early/misaddressed arrival')
            del o['shipments'][str(sid)];o['delivered']+=r['quantity'];stock[o['buyer']][o['good']]+=r['quantity'];delivered_today.add(r['order_id'])
            if edges:check(journeys[sid]['position']==len(journeys[sid]['path']),'arrival before path completed');del journeys[sid]
        elif e=='payment':
            o=orders[r['order_id']];sid=r['shipment_id'];key=('goods',sid);check(key not in transfers and sid not in cargo,'duplicate/payment before arrival');transfers.add(key)
            check((r['buyer'],r['seller'],r['locked_price'])==(o['buyer'],o['seller'],o['price']),'locked price/payment parties')
            cb=o['cash_buyer'];cs=o['cash_seller'];check(r.get('cash_buyer',r['buyer'])==cb and r.get('cash_seller',r['seller'])==cs,'payment denomination')
            q=r['quantity']*o['price'];check(q==r['buyer_debit']==r['seller_credit']==r['reserved_release'] and q<=cash[cb]['reserved'],'goods payment amount')
            cash[cb]['balance']-=q;cash[cb]['reserved']-=q;cash[cs]['balance']+=q
        elif e=='cancelled':
            o=orders[r['order_id']];q=r['quantity'];check(0<q<=o['pending'],'cancel dispatched cargo');o['pending']-=q;o['cancelled']+=q;cash[o['cash_buyer']]['reserved']-=q*o['price']
        elif e=='household_consumed':
            hid=r['actor'];g=r['good'];q=integer(r['quantity'],True);check(hid in need and q<=stock[hid][g],'consumption before ownership/arrival')
            check(r['satisfaction']==min(need[hid]-satisfied[hid],q*fixture['food_satisfaction'][g]),'consumption service units')
            stock[hid][g]-=q;satisfied[hid]+=r['satisfaction'];consumption_totals[hid]+=r['satisfaction']
        elif e=='need_result':
            check(r['required']==need[r['actor']] and r['consumed']==satisfied[r['actor']] and r['unmet']==r['required']-r['consumed'],'need/consumption/unmet identity')
        elif e=='price_update':
            check(r['effective_day']==day+1,'price effective time');pending_prices[(r['seller'],r['commodity'])]=integer(r['price'],True)
        elif e=='day_close':
            expected_inputs=defaultdict(int)
            for fid,spec in firms.items():
                for recipe in spec['recipes']:
                    q=produced[(fid,recipe['output_commodity'])]
                    for material,coef in recipe['inputs']:expected_inputs[(fid,material)]+=ceil(Fraction(q*coef,recipe['output_quantity']))
            check({k:v for k,v in expected_inputs.items() if v}=={k:v for k,v in consumed.items() if v},'recipe conversion quantities')
            observed=r['state'];check(stock==observed['stock'],'reconstructed stock');check(cash==observed['cash'],'reconstructed cash/reserved');check(contracts==observed['contracts'],'labor contracts');check(claims==observed['wage_claims'],'paired wage obligations')
            reconstructed={str(k):{name:o[name] for name in ('route','quantity','pending','delivered','cancelled','shipments')} for k,o in orders.items()}
            check(reconstructed==observed['orders'],'order/shipment ownership')
            if edges:check({str(k):v for k,v in freight.items()}==observed['freight'],'freight obligations');check({str(k):v for k,v in journeys.items()}==observed['journeys'],'cargo position ownership')
            if fixture.get('enable_relations'):check(relations==observed['relations'],'relation observation facts')
            if fixture.get('credit'):check(loans==observed['loans'],'paired debt/creditor asset reconstruction')
            if cfg_assets:
                check(shares==observed['shares'] and share_reserved==observed['share_reserved'] and asset_orders==observed['asset_orders'],'security ownership/reservation/order reconstruction')
                for asset,h in shares.items():
                    check(sum(h.values())==cfg_assets['total_shares'][asset],'finite share total')
                    for holder,q in h.items():check(0<=share_reserved[asset].get(holder,0)<=q,'share reservation bounds')
        else:raise ValueError('unrecognized event '+e)
        for k,v in cash.items():
            delta=v['balance']-prior_cash[k]
            if delta>0:cash_received[k]+=delta
            elif delta<0:cash_paid[k]-=delta
        money_bounds();check(all(type(q) is int and q>=0 for s in stock.values() for q in s.values()),'negative/noninteger stock')
    check(day==fixture['days'],'incomplete trajectory')
    return dict(status='PASS_CURRENT_ORIGINAL_TRACE',days=day,events=events,orders=len(orders),needs=dict(need_totals),consumed=dict(consumption_totals),wage_outstanding=sum(c['remaining'] for c in claims.values()),wage_matured_unpaid=sum(c['remaining'] for c in claims.values() if c.get('due_day',c['work_day'])<=day),scope='Independent stock, cash/reservation, recipe, order/shipment, labor/time, wage, need/consumption, knowledge, credit, each currency, finite shares, orders and dividends. Pricing formula uses frozen source applicability, not independently re-proved. Not economic optimality/realism.')

def main():
    p=argparse.ArgumentParser();p.add_argument('events',type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
    check(not a.output.exists(),'fresh audit output required')
    try:result=audit(records(a.events));code=0
    except (ValueError,KeyError,AssertionError,TypeError,StopIteration) as error:result=dict(status='FAIL',error=str(error));code=1
    result['input_sha256']=hashlib.sha256(a.events.read_bytes()).hexdigest();a.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n',encoding='utf-8');print(json.dumps(result));raise SystemExit(code)
if __name__=='__main__':main()
