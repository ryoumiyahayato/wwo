"""Independent recorded-fact date/price audit. Standard library, no runtime imports.

Not a second decision engine: checks logged comparisons and recorded lifecycle
links. Accounting separately remains the original Cycle01 offline_audit.py.
"""
from pathlib import Path
from collections import defaultdict
import json,argparse,hashlib,gzip

def records(path):
    p=Path(path)
    if not p.exists() and Path(str(p)+'.gz').exists():p=Path(str(p)+'.gz')
    with (gzip.open(p,'rt',encoding='utf-8') if p.suffix=='.gz' else p.open()) as handle:
        for line in handle:yield line

def check(v,msg):
    if not v:raise ValueError(msg)

def recorded_event_facts(p,initial):
    stock=json.loads(json.dumps(initial['stock']));pending=defaultdict(int);orders={};facts={};by_day=defaultdict(lambda:defaultdict(int));day=0
    def close(d):
        if d:facts[d]=dict(free={f'{a}:{b}':stock[a][b]-pending[(a,b)] for a,goods in stock.items() for b in goods},shipped=dict(by_day[d]))
    for line in records(p/'events.jsonl'):
        r=json.loads(line);d=r['day']
        if d!=day:close(day);day=d
        q=r['quantity'];event=r['event']
        if event=='accepted':
            orders[r['order_id']]=r;pending[(r['seller'],r['commodity'])]+=q
        elif event in ('dispatched','cancelled'):
            o=orders[r['order_id']];seller=o['seller'];good=o['commodity'];pending[(seller,good)]-=q
            if event=='dispatched':
                route=next(x for x in initial['case']['routes'] if f"{x['seller_id']}>{x['buyer_id']}:{x['commodity']}"==o['route'])
                check(r['arrival_day']==d+route['lead_time'],'dispatch arrival violates real lead')
                stock[seller][good]-=q;by_day[d][f'{seller}:{good}']+=q
        elif event=='arrived':
            o=orders[r['order_id']];stock[o['buyer']][o['commodity']]+=q
        elif event=='produced':stock[r['firm']][r['commodity']]+=q
        elif event=='consumed':stock[r['firm']][r['commodity']]-=q
        elif event=='terminal':stock[r['seller']][r['commodity']]-=q
    close(day)
    previous={f'{a}:{b}':q for a,goods in initial['stock'].items() for b,q in goods.items()}
    for d in range(1,initial['case']['days']+1):
        if d in facts:previous=facts[d]['free']
        else:facts[d]=dict(free=previous,shipped={})
    return facts

def independent_v1(current,initial,tick,free,shipped,physical,price,cash,info):
    lower=((initial+4*tick-1)//(4*tick))*tick;upper=4*initial
    step=(current*2//100//tick)*tick;direction=0;reason='HOLD'
    if info==0:reason='NO_NEW_INFORMATION'
    elif free>=2*max(shipped,1):direction=-1;reason='IDLE_STOCK'
    elif (price or cash) and free:direction=-1;reason='ECONOMIC_REFUSAL'
    elif physical and shipped and free<shipped:direction=1;reason='OBSERVED_PHYSICAL_PRESSURE'
    proposed=current+direction*step
    return dict(price=max(lower,min(upper,proposed)),reason=reason,unclamped=proposed,lower_hit=proposed<=lower,upper_hit=proposed>=upper,step=step)

def audit(path,causal_path=None):
    p=Path(path);initial=json.loads((p/'initial.json').read_text());case=initial['case']
    known={f['firm_id']:{g:set(ids) for g,ids in f['knowledge'].items()} for f in case['firms']}
    routes={(r['buyer_id'],r['commodity'],r['seller_id']):r for r in case['routes']}
    accepted={};requests={};seen_requests=set();decisions={};updates=[];day_links=0;opportunities=set();shadow_changes=set();actual_choice=set();retry_need=set();unique_need=set();plans={};counts=defaultdict(int)
    latest_day=0;decision_keys=set();event_facts=recorded_event_facts(p,initial);windows=defaultdict(lambda:dict(information=set(),interest={},accepted=0));expected_prices=dict(case['economics']['prices']);pending_prices={};strong_attempts={};strong_accepted=set();sensitive_orders=set();ceilings={k:4*v for k,v in case['economics']['prices'].items()}
    for line in records(causal_path or p/'causal.jsonl'):
        r=json.loads(line);d=r['day'];check(d>=latest_day,'nonmonotonic causal day')
        if d!=latest_day:
            plans.clear();decisions.clear();expected_prices.update(pending_prices);pending_prices.clear()
            for e in case['economics'].get('price_events',[]):
                if e['day']==d:expected_prices[f"{e['seller']}:{e['commodity']}"]=e['price']
        latest_day=d
        if r['event']=='own_plan':
            plans[(d,r['firm'])]={n['requirement_bucket_id']:n for n in r['requirements']}
        elif r['event']=='decision':
            buyer=r['buyer'];good=r['commodity'];kset=set(known[buyer].get(good,set()))
            for e in case.get('knowledge_events',[]):
                if e['day']<=d and e['buyer']==buyer and e['commodity']==good:kset.add(e['seller'])
            check(set(r['known'])==kset,'known set includes future/unknown supplier')
            check(set(r['queried'])<=kset,'unknown supplier queried')
            offers={o['supplier_id']:o for o in r['buyer_visible_information']['offers']}
            check(set(offers)<=kset,'unknown offer in buyer selectable set')
            for sid,o in offers.items():
                check('world_diagnostic' not in o,'world truth leaked into buyer-visible snapshot')
                route=routes[(buyer,good,sid)]
                check(o['offer_day']==d and o['expected_arrival_day']==d+2+route['lead_time'],'quote date inconsistency')
                check(type(o['posted_price']) is int and o['posted_price']>0,'invalid posted price')
                check(o['posted_price']==expected_prices[f'{sid}:{good}'],'next-day posted price differs from independently reconstructed update')
            limit=r['buyer_visible_information']['max_unit_price'];cash=r['buyer_visible_information']['available_cash']
            check(limit==case['economics']['limits'][buyer][good],'buyer max price not fixed')
            for n in r['requirements']:
                check(n['need_id']==f"{buyer}:{good}:{n['need_by_day']}",'need identity/date mismatch')
                usable=[]
                for a in n['candidates']:
                    check(a['supplier'] in offers,'candidate absent from queried visible offers');o=offers[a['supplier']]
                    eta=o['expected_arrival_day'];release=n['need_by_day']-(eta-d)
                    timely=eta<=n['need_by_day'];due=release<=d
                    check((a['expected_arrival'],a['release_day'],a['timely'],a['release_due'],a['posted_price'])==(eta,release,timely,due,o['posted_price']),'need-by/timely/release mismatch')
                    constraints=set(a['constraints'])
                    for test,name in ((not timely,'LATE_FOR_REQUIREMENT'),(not due,'OTHER_EXPLICIT_REASON:RELEASE_NOT_DUE'),(o['max_acceptable_quantity']<=0,'NO_PHYSICAL_ATP'),(o['posted_price']>limit,'PRICE_ABOVE_LIMIT'),(cash<o['posted_price'],'INSUFFICIENT_CASH')):
                        check((name in constraints)==test,'binding constraint mislabeled '+name)
                    eligible=timely and due and o['max_acceptable_quantity']>0 and o['posted_price']<=limit and cash>=o['posted_price'] and n['gap']>0
                    check(a['eligible']==eligible,'eligibility differs from actual visible constraints')
                    if eligible:usable.append(o)
                    counts['candidate_'+('eligible' if eligible else 'ineligible')]+=1
                    for reason in constraints:counts[reason]+=1
                old=min(usable,key=lambda o:(o['expected_arrival_day'],-o['max_acceptable_quantity'],o['supplier_id']))['supplier_id'] if usable else None
                price=min(usable,key=lambda o:(o['posted_price'],o['expected_arrival_day'],-o['max_acceptable_quantity'],o['supplier_id']))['supplier_id'] if usable else None
                check((n['shadow_legacy'],n['shadow_price_first'])==(old,price),'shadow rank does not match same-state offers')
                match=len(usable)>=2 and len({o['posted_price'] for o in usable})>=2
                check(n['matched_competitive']==match and n['shadow_differs']==(old!=price),'matched/shadow label inconsistent')
                key=(d,r['boundary'],buyer,good,n['need_id'],n['need_by_day'])
                if r['phase']=='MATCHING':
                    # Strict count requires world ATP still positive too. This
                    # diagnostic is not inserted into BUYER_VISIBLE_INFORMATION.
                    real=[a for a in n['candidates'] if a['eligible'] and a['current_atp']>0]
                    if match and len(real)>=2 and len({a['posted_price'] for a in real})>=2:opportunities.add(key)
                    if old!=price:shadow_changes.add(key)
                    intent=r['intent']
                    if old!=price and intent and r['selected_supplier']==price and any(x['need_id']==n['need_id'] and x['need_by_day']==n['need_by_day'] for x in intent['lines']):
                        actual_choice.add(key)
                        rule=case['economics'].get('ranking_axis','R_PRICE_FIRST' if case['economics']['mode'] in ('N2','N3','N4_EXPERIMENTAL') else 'R_LEGACY')
                        if rule=='R_PRICE_FIRST' and r['round']==0 and key in opportunities:strong_attempts[(d,buyer,good,n['need_id'],n['need_by_day'],r['selected_supplier'])]=key
            decision_keys.add((d,buyer,good,r['selected_supplier'],r['round']))
            decisions[(d,buyer,good,r['selected_supplier'],r['round'])]=r
        elif r['event']=='request':
            req=r['request'];buyer=req['buyer_id'];good=req['commodity'];seller=req['supplier_id'];key=(d,buyer,good,seller,req['procurement_round'])
            check(key in decisions,'request lacks observed decision');dec=decisions[key]
            check(req['request_id'] not in seen_requests,'duplicate request id');seen_requests.add(req['request_id'])
            check(all(type(req[k]) is int and req[k]>=0 for k in ('requested_quantity','accepted_quantity','rejected_quantity')),'invalid request/accept/reject quantity type')
            check(req['accepted_quantity']+req['rejected_quantity']==req['requested_quantity'],'request acceptance/rejection partition')
            check(sum(x['quantity'] for x in req['lines'])==req['requested_quantity'],'request lines do not sum')
            requested_per_need=defaultdict(int);dates_per_need=defaultdict(set)
            for line in req['lines']:
                check(type(line['quantity']) is int and line['quantity']>0,'invalid requested line quantity')
                check(line['commodity']==good,'line commodity differs from request')
                requested_per_need[line['need_id']]+=line['quantity'];dates_per_need[line['need_id']].add(line['need_by_day'])
            check(set(req['accepted_lines'])==set(requested_per_need),'accepted need keys differ from actual request lines')
            check(all(len(dates)==1 for dates in dates_per_need.values()),'one need identity spans inconsistent dates in request')
            check(all(type(q) is int and 0<=q<=requested_per_need[need] for need,q in req['accepted_lines'].items()),'accepted line exceeds requested need quantity')
            expected_lines=defaultdict(int);remaining_accept=req['accepted_quantity']
            for line in req['lines']:
                take=min(remaining_accept,line['quantity']);remaining_accept-=take;expected_lines[line['need_id']]+=take
            check(dict(expected_lines)==req['accepted_lines'] and remaining_accept==0,'accepted dated-line allocation differs from committed request prefix')
            check(sum(req['accepted_lines'].values())==req['accepted_quantity'],'accepted lines do not sum')
            route=routes[(buyer,good,seller)];eta=d+2+route['lead_time']
            check(req['expected_arrival_day']==eta,'request ETA differs from actual route')
            price=req['posted_price'];limit=case['economics']['limits'][buyer][good]
            check(price==next(o['posted_price'] for o in dec['buyer_visible_information']['offers'] if o['supplier_id']==seller),'request changed quote within boundary')
            physical_cap=min(req['uncommitted_at_acceptance'],req['route_atp_at_acceptance']);cash=dec['buyer_visible_information']['available_cash']
            financial_cap=min(physical_cap,cash//price) if price<=limit else 0
            economic=min(req['rejected_quantity'],max(0,min(req['requested_quantity'],physical_cap)-financial_cap))
            check(req['rejections']['PRICE_LIMIT']==(economic if price>limit else 0),'PRICE rejection mislabeled')
            check(req['rejections']['CASH']==(economic if price<=limit else 0),'CASH rejection mislabeled')
            check(sum(req['rejections'].values())==req['rejected_quantity'],'rejection quantity accounting')
            for x in req['lines']:
                ident=(buyer,x['need_id']);is_new=ident not in unique_need
                if not is_new:retry_need.add(ident)
                unique_need.add(ident)
                check(x['need_id']==f"{buyer}:{good}:SAFETY" or x['need_id']==f"{buyer}:{good}:{x['need_by_day']}",'line stable ID/date mismatch')
                check(x['need_by_day']>=eta,'request released against late offer')
                if x.get('source_bucket_id'):
                    check(x['source_bucket_id'] in plans[(d,buyer)],'material requirement lacks own production plan')
                    bucket=plans[(d,buyer)][x['source_bucket_id']]
                    check((bucket['producer'],bucket['commodity'],bucket['need_by_day'])==(buyer,good,x['need_by_day']),'accepted line source bucket/date differs from actual own requirement')
            w=windows[(seller,good)];w['accepted']+=req['accepted_quantity'];left=req['accepted_quantity'];reasons=dict(req['rejections'])
            for x in req['lines']:
                take=min(left,x['quantity']);left-=take;rem=x['quantity']-take;ident=(buyer,x['need_id']);w['information'].add(ident)
                state=w['interest'].setdefault(ident,dict(date=x['need_by_day'],PHYSICAL=0,PRICE_LIMIT=0,CASH=0));state['date']=max(state['date'],x['need_by_day'])
                for name in ('PHYSICAL','PRICE_LIMIT','CASH'):
                    part=min(rem,reasons[name]);state[name]=max(state[name],part);rem-=part;reasons[name]-=part
                k=(d,buyer,good,x['need_id'],x['need_by_day'],seller)
                if req['accepted_lines'].get(x['need_id'],0)>0 and k in strong_attempts:
                    strong_accepted.add(strong_attempts[k]);sensitive_orders.add(req['order_id'])
            if req['order_id']:
                check(req['accepted_quantity']>0 and price<=limit,'accepted illegal request')
                check(r['locked_price']==price,'locked price changed from quote')
                accepted[req['order_id']]=dict(req)
            requests[req['request_id']]=dict(req)
        elif r['event']=='price_update':
            v=r['local'];out=r['result'];check(v['window_start']==d-6 and v['window_end']==d,'local window time leak')
            check(len(v['information'])==v['distinct_requests'] and len({tuple(x) for x in v['information']})==len(v['information']),'retry counted as distinct new information')
            check(len({(x['buyer'],x['need_id']) for x in v['interests']})==len(v['interests']),'same need retry counted as independent demand')
            w=windows[(r['seller'],r['commodity'])]
            expected_information=sorted([list(k) for k in w['information']]);check(v['information']==expected_information,'price information cannot reconstruct from real requests')
            expected_interests=[dict(buyer=k[0],need_id=k[1],**state) for k,state in sorted(w['interest'].items())]
            check(v['interests']==expected_interests,'price window identities/rejection maxima cannot reconstruct from actual requests')
            key=f"{r['seller']}:{r['commodity']}"
            shipped=sum(event_facts.get(day,{}).get('shipped',{}).get(key,0) for day in range(d-6,d+1))
            free=event_facts[d]['free'][key]
            check(v['shipped']==shipped and v['free_stock']==free,'price local supply cannot reconstruct from events')
            if 'accepted_quantity' in v:check(v['accepted_quantity']==w['accepted'],'window accepted quantity differs from real requests')
            active=[x for x in v['interests'] if x['date']>=d]
            check(v['old_price']==expected_prices[key],'price old value differs from reconstructed posted path')
            expected=independent_v1(expected_prices[key],case['economics']['prices'][key],case['economics']['tick'],free,shipped,*(sum(x[name] for x in active) for name in ('PHYSICAL','PRICE_LIMIT','CASH')),len(w['information']))
            if case['economics']['mode']=='N4_EXPERIMENTAL':
                current=expected_prices[key];tick=case['economics']['tick'];low=((case['economics']['prices'][key]+4*tick-1)//(4*tick))*tick;high=4*case['economics']['prices'][key];ceiling=ceilings[key];before_ceiling=ceiling
                info=len(w['information']);price_refused=sum(x['PRICE_LIMIT'] for x in active);cash_refused=sum(x['CASH'] for x in active);base=dict(expected)
                enabled=case['economics'].get('candidate_enabled',True)
                if enabled and info:
                    if price_refused and w['accepted']==0 and free>0 and cash_refused==0:ceiling=max(low,min(ceiling,current-tick))
                    candidate_price=max(low,current-base['step'],min(high,current+base['step'],base['price'],ceiling))
                else:candidate_price=base['price'] if not enabled else current
                expected.update(price=candidate_price,base_reason=base['reason'],base_price=base['price'],refusal_ceiling=ceiling,ceiling_learned=ceiling<before_ceiling,candidate='local-zero-accept-refusal-bound-v1')
                if candidate_price!=base['price']:expected['reason']='LEARNED_REFUSAL_BOUND'
                ceilings[key]=ceiling
                check(out['accepted_quantity']==w['accepted'],'candidate reads false accepted-window signal')
            check(r['pending_price']==expected['price'],'price formula/rounding/clamp mismatch')
            pending_prices[key]=expected['price'];windows[(r['seller'],r['commodity'])]=dict(information=set(),interest={},accepted=0)
            if out:
                for field,value in expected.items():check(out[field]==value,'v1 result differs from independently reconstructed '+field)
                check(out['day']==d and out['effective_day']==d+1 and out['old_price']==v['old_price'],'price applied on wrong date')
                for name,key in (('physical_unmet','PHYSICAL'),('price_refused','PRICE_LIMIT'),('cash_refused','CASH')):check(out[name]==sum(x[key] for x in active),'window signal cannot reconstruct '+name)
                check(out['shipped']==v['shipped'] and out['free_stock']==v['free_stock'] and out['information_count']==len(v['information']),'local facts differ from feedback input')
                check(out['price']==r['pending_price'],'pending price differs')
            updates.append(r)
        elif r['event']=='day_link':day_links+=1
        else:raise ValueError('unrecognized causal event')
    check(day_links==case['days'],'daily linkage count incomplete')
    event_accepted={};arrival_count=0;sensitive_arrivals=0
    for line in records(p/'events.jsonl'):
        e=json.loads(line)
        if e['event']=='accepted':
            oid=e['order_id'];check(oid in accepted,'accepted order lacks dated request');q=accepted[oid]
            check((e['buyer'],e['seller'],e['commodity'],e['route'])==(q['buyer_id'],q['supplier_id'],q['commodity'],f"{q['supplier_id']}>{q['buyer_id']}:{q['commodity']}"),'accepted event parties/route differ from dated request')
            check(e['day']==q['request_day'] and e['quantity']==q['accepted_quantity'] and e['locked_price']==q['posted_price'],'accept/request lock or quantity mismatch');event_accepted[oid]=e
        elif e['event']=='arrived':
            check(e['order_id'] in accepted,'arrival lacks dated request');arrival_count+=1
            if e['order_id'] in sensitive_orders:sensitive_arrivals+=1
    check(set(event_accepted)==set(accepted),'request order set differs from cash ledger')
    return dict(status='PASS',decisions=len(decision_keys),requests=len(requests),linked_orders=len(accepted),linked_arrivals=arrival_count,price_updates=len(updates),distinct_need_identities=len(unique_need),retried_need_identities=len(retry_need),matched_competitive_opportunities=len(opportunities),same_state_shadow_differences=len(shadow_changes),shadow_price_selected_attempts_any_rule=len(actual_choice),price_sensitive_first_round_accepted_needs=len(strong_accepted),price_sensitive_linked_arrival_events=sensitive_arrivals,constraints=dict(counts),scope='Strict matched uses positive current world ATP as offline qualification; shadows only queried buyer-visible snapshot. Actual distinct arrival differences require independently executed paired trajectories.')

def main():
    a=argparse.ArgumentParser();a.add_argument('path',type=Path);a.add_argument('--causal',type=Path);x=a.parse_args()
    try:print(json.dumps(audit(x.path,x.causal),sort_keys=True));return 0
    except (ValueError,KeyError,AssertionError,StopIteration,TypeError) as e:print(json.dumps(dict(status='FAIL',error=str(e))));return 1
if __name__=='__main__':raise SystemExit(main())
