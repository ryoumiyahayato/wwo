"""Streaming replay of recorded facts. Standard library only; no runtime imports.

This is an accounting reconstruction, not another economic decision engine or
third-party certification. Every rejected/tampered trace fails with a nonzero exit.
"""
from collections import defaultdict
from fractions import Fraction
from math import ceil
import argparse,json
from pathlib import Path


def check(condition,message):
    if not condition:raise ValueError(message)

def integer(v,minimum=0):
    check(type(v) is int and v>=minimum,'invalid integer event field');return v


def audit(directory,events_path=None):
    p=Path(directory);initial=json.loads((p/'initial.json').read_text());final=json.loads((p/'final.json').read_text())
    stock=initial['stock'];original_world={g:sum(v[g] for v in stock.values()) for g in ('coal','steel','machine')}
    balances=dict(initial['cash']);reserved={k:0 for k in balances};initial_money=sum(balances.values())
    orders={};shipments={};await_payment={};flows=defaultdict(lambda:defaultdict(int));terminals=defaultdict(int)
    pending_pool=defaultdict(int);order_count=0;shipment_count=0
    route_totals=defaultdict(lambda:dict(ordered=0,delivered=0,cancelled=0,order_count=0))
    produced=defaultdict(int);consumed=defaultdict(int);world_produced=defaultdict(int);world_consumed=defaultdict(int);world_terminal=defaultdict(int)
    day=-1;count=0;closed=dict(orders=0,value=0,paid=0,cancelled=0)
    def cash_bounds():
        check(all(0<=reserved[k]<=balances[k] for k in balances),'cash/reservation overcommit')
        check(sum(balances.values())==initial_money,'total cash drift')
    def finish_day():
        expected=defaultdict(int)
        for (firm,good),q in produced.items():
            recipes=[r for r in initial['recipes'][firm] if r['output']==good]
            check(len(recipes)==1,'ambiguous recorded recipe')
            for g,c in recipes[0]['inputs']:expected[(firm,g)]+=ceil(Fraction(q*c,recipes[0]['output_quantity']))
        check(dict(expected)=={k:v for k,v in consumed.items() if v},'production recipe mismatch')
        check(not await_payment,'arrival without matching payment')
        produced.clear();consumed.clear()
    with Path(events_path or p/'events.jsonl').open() as f:
        for line in f:
            r=json.loads(line);count+=1;d=integer(r['day']);check(d>=day,'nonmonotonic days')
            if d!=day:
                if day>=0:finish_day()
                day=d
            event=r['event'];q=integer(r.get('quantity',0),1)
            if event=='accepted':
                oid=integer(r['order_id'],1);check(oid==order_count+1,'duplicate/noncanonical order ID');order_count+=1;price=integer(r['locked_price'],1)
                value=q*price;check(r['reserved_value']==value,'accept reservation price')
                buyer=r['buyer'];seller=r['seller'];good=r['commodity']
                route=next(x for x in initial['case']['routes'] if f'{x["seller_id"]}>{x["buyer_id"]}:{x["commodity"]}'==r['route'])
                check((buyer,seller,good)==(route['buyer_id'],route['seller_id'],route['commodity']),'order addresses differ from route')
                check(price<=initial['case']['economics']['limits'][buyer][good],'accepted over limit')
                check(value<=balances[buyer]-reserved[buyer],'same balance reserved twice')
                pending=pending_pool[(seller,good)]
                check(q<=stock[seller][good]-pending,'inventory commitment overbook')
                pending_pool[(seller,good)]+=q
                route_totals[r['route']]['ordered']+=q;route_totals[r['route']]['order_count']+=1
                reserved[buyer]+=value
                orders[oid]=dict(route=r['route'],buyer=buyer,seller=seller,good=good,price=price,original=q,pending=q,transit=0,delivered=0,cancelled=0,paid=0,reserved=value,cancelled_value=0)
            elif event=='dispatched':
                o=orders[r['order_id']];sid=integer(r['shipment_id'],1)
                check(sid==shipment_count+1,'duplicate/noncanonical shipment');shipment_count+=1;check(q<=o['pending'],'dispatch above pending')
                check(stock[o['seller']][o['good']]>=q,'dispatch inventory unavailable')
                o['pending']-=q;o['transit']+=q;stock[o['seller']][o['good']]-=q;flows[(o['seller'],o['good'])]['dispatched']+=q
                pending_pool[(o['seller'],o['good'])]-=q
                shipments[sid]=dict(order_id=r['order_id'],quantity=q,arrived=False,arrival_day=r['arrival_day'])
            elif event=='arrived':
                sid=r['shipment_id'];cargo=shipments[sid];o=orders[r['order_id']]
                check(not cargo['arrived'] and cargo['order_id']==r['order_id'] and cargo['quantity']==q and cargo['arrival_day']==d,'arrival exceeds/differs from dispatch')
                check(q<=o['transit'],'arrival above transit');cargo['arrived']=True;o['transit']-=q;o['delivered']+=q
                stock[o['buyer']][o['good']]+=q;flows[(o['buyer'],o['good'])]['received']+=q;await_payment[sid]=r
                route_totals[o['route']]['delivered']+=q
            elif event=='payment':
                sid=r['shipment_id'];o=orders[r['order_id']]
                check(sid in await_payment,'duplicate/unmatched payment');arrival=await_payment.pop(sid)
                check(arrival['quantity']==q and arrival['order_id']==r['order_id'],'payment arrival mismatch')
                value=q*o['price'];check(r['locked_price']==o['price'],'payment uses changed quote')
                check(r['buyer']==o['buyer'] and r['seller']==o['seller'],'payment parties')
                check(r['buyer_debit']==r['seller_credit']==r['reserved_release']==value,'buyer/seller payment mismatch')
                check(value<=o['reserved'],'order payment above reservation')
                balances[o['buyer']]-=value;balances[o['seller']]+=value;reserved[o['buyer']]-=value;o['reserved']-=value;o['paid']+=value
                del shipments[sid]
            elif event=='cancelled':
                o=orders[r['order_id']];check(q<=o['pending'],'cancel includes in-transit quantity')
                value=q*o['price'];check(r['released_value']==value,'cancellation locked price')
                o['pending']-=q;o['cancelled']+=q;o['cancelled_value']+=value;o['reserved']-=value;reserved[o['buyer']]-=value
                pending_pool[(o['seller'],o['good'])]-=q
                route_totals[o['route']]['cancelled']+=q
            elif event in ('produced','consumed'):
                firm=r['firm'];good=r['commodity'];delta=q if event=='produced' else -q
                stock[firm][good]+=delta;check(stock[firm][good]>=0,'consumption exceeds stock')
                (produced if event=='produced' else consumed)[(firm,good)]+=q
                (world_produced if event=='produced' else world_consumed)[good]+=q;flows[(firm,good)][event]+=q
            elif event=='terminal':
                sid=r['sink_id'];seller=r['seller'];buyer=r['buyer'];good=r['commodity'];price=integer(r['locked_price'],1);value=q*price
                sink=next(x for x in initial['case']['sinks'] if x['sink_id']==sid)
                check((seller,buyer,good)==(sink['firm_id'],'external:'+sid,sink['commodity']),'terminal parties')
                check(price==initial['case']['economics']['terminal_prices'][sid],'terminal fixture price')
                check(r['buyer_debit']==r['seller_credit']==value,'terminal delivery lacks cash transfer')
                check(stock[seller][good]>=q and balances[buyer]-reserved[buyer]>=value,'terminal commodity/funds atomicity')
                stock[seller][good]-=q;balances[buyer]-=value;balances[seller]+=value;terminals[sid]+=q;world_terminal[good]+=q;flows[(seller,good)]['terminal']+=q
            else:raise ValueError('unknown audit event '+event)
            if event in ('payment','cancelled') and not o['reserved']:
                check(o['original']==o['delivered']+o['cancelled'] and not o['pending'] and not o['transit'],'closed order quantity identity')
                check(o['original']*o['price']==o['paid']+o['cancelled_value'],'closed order financial identity')
                closed['orders']+=1;closed['value']+=o['original']*o['price'];closed['paid']+=o['paid'];closed['cancelled']+=o['cancelled_value']
                del orders[r['order_id']]
            cash_bounds()
    if day>=0:finish_day()
    check(stock==final['stock'],'reconstructed firm commodity state differs from ending state')
    check({k:dict(balance=v,reserved=reserved[k]) for k,v in balances.items()}==final['cash'],'reconstructed ending cash differs')
    for sid,sink in final['sinks'].items():
        check(terminals[sid]==sink['delivered'],'terminal delivery count')
        check(sink['received']==sink['delivered']+sink['backlog'],'sink identity')
        fixture=next(x for x in initial['case']['sinks'] if x['sink_id']==sid)
        demand=sum(max(0,min(final['day'],last)-max(1,first)+1)*qty for first,last,qty in fixture['demand_intervals'])
        check(sink['received']==demand,'sink received demand differs from fixture')
    open_runtime={o['id']:o for o in final['open_orders']}
    reconstructed_reserved=defaultdict(int)
    for oid,o in orders.items():
        check(o['original']==o['pending']+o['transit']+o['delivered']+o['cancelled'],'offline order quantity identity')
        check(o['original']*o['price']==o['paid']+o['reserved']+o['cancelled_value'],'offline order financial identity')
        reconstructed_reserved[o['buyer']]+=o['reserved']
        if o['reserved']:
            check(oid in open_runtime,'open order missing from ending state');r=open_runtime[oid]
            check((r['quantity'],r['pending'],r['delivered'],r['cancelled'])==(o['original'],o['pending'],o['delivered'],o['cancelled']),'ending order quantity differs')
            actual_cargo={c['id']:c['quantity'] for c in r['shipments']}
            reconstructed_cargo={sid:c['quantity'] for sid,c in shipments.items() if c['order_id']==oid}
            check(actual_cargo==reconstructed_cargo,'ending cargo differs from dispatch/arrival reconstruction')
            rf=final['financial'][str(oid)]
            check(rf['locked_price']==o['price'] and rf['reserved_value']==o['reserved'] and rf['paid_value']==o['paid'] and rf['cancelled_value']==o['cancelled_value'],'ending financial order differs')
    check(dict(closed)==final['closed_financial'],'closed order aggregate differs')
    check(all(reserved[k]==reconstructed_reserved[k] for k in balances),'reserved not equal open orders')
    check(set(open_runtime)==set(orders),'ending active order set differs')
    for route,r in final['routes'].items():
        check(all(r[k]==v for k,v in route_totals[route].items()),'route cumulative order identity differs')
        check(r['pending']==sum(o['pending'] for o in orders.values() if o['route']==route),'route ending pending differs')
        check(r['transit']==sum(o['transit'] for o in orders.values() if o['route']==route),'route ending transit differs')
    for g in ('coal','steel','machine'):
        original=original_world[g]
        transit=sum(c['quantity'] for c in shipments.values() if not c['arrived'] and orders[c['order_id']]['good']==g)
        check(sum(v[g] for v in stock.values())+transit==original+world_produced[g]-world_consumed[g]-world_terminal[g],'offline world commodity identity')
    return dict(status='PASS',events=count,orders=order_count,shipments=shipment_count,total_money=initial_money,live_orders=len(orders),
        checks=['cash transfers','reservation','locked price','order lifecycle','firm commodity flows','recipes','world commodities','terminal delivery/payment'])


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory',type=Path);parser.add_argument('--events',type=Path);a=parser.parse_args()
    try:print(json.dumps(audit(a.directory,a.events),sort_keys=True));return 0
    except (ValueError,KeyError,TypeError,StopIteration,AssertionError) as e:print(json.dumps(dict(status='FAIL',error=str(e))));return 1
if __name__=='__main__':raise SystemExit(main())
