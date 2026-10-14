"""Finite real-issuer shares with local limit orders and funded distributions."""
from copy import deepcopy
from collections import defaultdict
from cash import integer

def initialize(world):
    cfg=world.case.get('assets',{})
    world.shares=deepcopy(cfg.get('holdings',{}));world.share_reserved={a:{k:0 for k in h} for a,h in world.shares.items()}
    world.asset_orders={};world.financial_messages=defaultdict(list);world.public_financial={};world.asset_attempted=set()
    for asset,holders in world.shares.items():
        if asset not in cfg['issuers'] or any(k not in world.firms for k in holders):raise ValueError('share issuer/holder identity')
        if sum(integer(q) for q in holders.values())!=cfg['total_shares'][asset]:raise ValueError('finite share total')

def place(world,spec):
    oid=spec['id'];actor=spec['actor'];asset=spec['asset'];side=spec['side'];q=integer(spec['quantity'],1);p=integer(spec['limit'],1)
    if oid in world.asset_orders:raise ValueError('duplicate asset order')
    cfg=world.case['assets']
    if asset not in cfg['known_assets'].get(actor,[]):raise ValueError('unknown security')
    if spec.get('requires_public_receipts'):
        message=world.public_financial.get((actor,asset))
        if not message or message['observed_day']>world.day or message['received_day']>world.day or message['facts']['receipts']<=0:raise ValueError('no received company cashflow information')
    if side=='buy':world.economics.cash.reserve(actor,q*p)
    elif side=='sell':
        if q>world.shares[asset].get(actor,0)-world.share_reserved[asset].get(actor,0):raise ValueError('unowned/unavailable shares')
        world.share_reserved[asset][actor]=world.share_reserved[asset].get(actor,0)+q
    else:raise ValueError('asset side')
    world.asset_orders[oid]=dict(actor=actor,asset=asset,side=side,quantity=q,remaining=q,limit=p,status='OPEN')
    world.emit('asset_order',order_id=oid,**world.asset_orders[oid],information=deepcopy(world.public_financial.get((actor,asset))))

def cancel(world,oid):
    o=world.asset_orders[oid]
    if o['status']!='OPEN':raise ValueError('closed order cancellation')
    q=o['remaining']
    if o['side']=='buy':world.economics.cash.release(o['actor'],q*o['limit'])
    else:world.share_reserved[o['asset']][o['actor']]-=q
    o['remaining']=0;o['status']='CANCELLED';world.emit('asset_cancel',order_id=oid,quantity=q)

def trade(world,bid_id,ask_id,quantity,fail_after_cash=False,event_id=None):
    b=world.asset_orders[bid_id];a=world.asset_orders[ask_id];q=integer(quantity,1);asset=b['asset'];price=a['limit'];buyer=b['actor'];seller=a['actor']
    if b['side']!='buy' or a['side']!='sell' or asset!=a['asset'] or b['status']!='OPEN' or a['status']!='OPEN' or buyer==seller or price>b['limit'] or q>min(b['remaining'],a['remaining']):raise ValueError('nonexecutable asset pair')
    cash=world.economics.cash
    event_id=event_id or f'asset:{bid_id}:{ask_id}:{b["remaining"]}:{a["remaining"]}'
    if event_id in world.paid_events:raise ValueError('duplicate asset settlement event')
    if q>world.shares[asset].get(seller,0) or q>world.share_reserved[asset].get(seller,0) or q*b['limit']>cash.accounts[buyer].reserved:raise ValueError('asset resources changed')
    before={k:(cash.accounts[k].balance,cash.accounts[k].reserved,cash.payments[k],cash.receipts[k]) for k in (buyer,seller)}
    try:
        cash.pay(buyer,seller,q*price,reserved=True)
        if fail_after_cash:raise RuntimeError('injected asset delivery failure')
        if b['limit']>price:cash.release(buyer,q*(b['limit']-price))
    except Exception:
        for k,(balance,reserved,paid,received) in before.items():cash.accounts[k].balance=balance;cash.accounts[k].reserved=reserved;cash.payments[k]=paid;cash.receipts[k]=received
        raise
    world.shares[asset][seller]-=q;world.shares[asset][buyer]=world.shares[asset].get(buyer,0)+q;world.share_reserved[asset][seller]-=q
    for o in (a,b):
        o['remaining']-=q
        if not o['remaining']:o['status']='FILLED'
    world.metrics['asset_trades']+=1
    world.paid_events.add(event_id)
    world.emit('asset_trade',event_id=event_id,bid_id=bid_id,ask_id=ask_id,buyer=buyer,seller=seller,asset=asset,quantity=q,price=price,cash=q*price,reserved_release=q*b['limit'])

def messages(world):
    for m in world.financial_messages.pop(world.day,[]):
        world.public_financial[(m['recipient'],m['asset'])]=deepcopy(m)
        world.emit('financial_message',message=m)

def run_market(world):
    cfg=world.case['assets']
    for spec in cfg['orders']:
        if spec['id'] in world.asset_attempted or not spec['day']<=world.day<=spec.get('last_day',spec['day']):continue
        world.metrics['asset_candidate_visits']+=1
        if spec.get('requires_public_receipts'):
            m=world.public_financial.get((spec['actor'],spec['asset']))
            if not m or m['facts']['receipts']<=0:continue
        world.asset_attempted.add(spec['id'])
        try:place(world,spec)
        except ValueError as error:world.emit('asset_rejected',order_id=spec['id'],reason=str(error))
    for c in cfg.get('cancellations',[]):
        if c['day']==world.day and c['order'] in world.asset_orders and world.asset_orders[c['order']]['status']=='OPEN':cancel(world,c['order'])
    for bid_id,b in sorted(world.asset_orders.items()):
        if b['side']!='buy' or b['status']!='OPEN':continue
        for ask_id,a in sorted(world.asset_orders.items(),key=lambda x:(x[1]['limit'],x[0])):
            world.metrics['asset_matching_visits']+=1
            if b['status']!='OPEN':break
            if a['side']=='sell' and a['status']=='OPEN' and a['asset']==b['asset'] and a['actor']!=b['actor'] and a['limit']<=b['limit']:trade(world,bid_id,ask_id,min(b['remaining'],a['remaining']))
    for spec in cfg.get('dividends',[]):
        if spec['day']!=world.day:continue
        asset=spec['asset'];issuer=cfg['issuers'][asset];cash=world.economics.cash
        event_id=f'dividend:{world.day}:{asset}'
        if event_id in world.paid_events:raise ValueError('duplicate dividend event')
        obligations=sum(c['remaining'] for c in world.wage_claims.values() if c['employer']==issuer)+sum(l['remaining'] for l in world.loans.values() if l['borrower']==issuer)
        surplus=max(0,min(cash.accounts[issuer].available-spec['buffer']-obligations,cash.receipts[issuer]-cash.payments[issuer]))
        per=min(spec['per_share'],surplus//cfg['total_shares'][asset])
        if not per:world.emit('dividend_unavailable',asset=asset,surplus=surplus);continue
        payments={holder:quantity*per for holder,quantity in world.shares[asset].items() if quantity and holder!=issuer}
        cash.batch_pay([(issuer,holder,q) for holder,q in sorted(payments.items())])
        world.paid_events.add(event_id);world.metrics['dividend_events']+=1;world.emit('asset_dividend',event_id=event_id,asset=asset,issuer=issuer,per_share=per,payments=payments,surplus=surplus)

def publish(world):
    cfg=world.case['assets']
    if world.day%cfg.get('publication_interval',7)!=1:return
    for asset,issuer in sorted(cfg['issuers'].items()):
        cash=world.economics.cash
        facts=dict(available=cash.accounts[issuer].available,receipts=cash.receipts[issuer],payments=cash.payments[issuer])
        world.emit('financial_publication',asset=asset,issuer=issuer,observed_day=world.day,facts=facts)
        for actor,known in cfg['known_assets'].items():
            if asset in known:world.financial_messages[world.day+cfg['message_delay']].append(dict(asset=asset,recipient=actor,observed_day=world.day,received_day=world.day+cfg['message_delay'],facts=deepcopy(facts)))

def check(world):
    for asset,h in world.shares.items():
        assert sum(h.values())==world.case['assets']['total_shares'][asset],'share total'
        for holder,q in h.items():
            reserved=world.share_reserved[asset].get(holder,0)
            assert 0<=reserved<=q,'share bounds'
            assert reserved==sum(o['remaining'] for o in world.asset_orders.values() if o['side']=='sell' and o['status']=='OPEN' and o['asset']==asset and o['actor']==holder),'share reservation orders'
