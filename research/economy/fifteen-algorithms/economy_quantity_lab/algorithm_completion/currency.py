"""Finite counterparty exchange; currency accounts live in the ONE cash map."""
from fractions import Fraction
from math import ceil
from cash import integer

def account(actor,currency):return actor if currency=='LOCAL' else actor+'@'+currency
def quote(world,foreign_quantity):
    cfg=world.case['currency'];q=integer(foreign_quantity,1)
    unit=cfg.get('monetary_unit',1)
    return ceil(Fraction(q*cfg['rate_numerator'],cfg['rate_denominator']*unit))*unit+cfg['fee']

def exchange(world,actor,quantity,event_id,fail_after=None):
    cfg=world.case['currency'];q=integer(quantity,1);dealer=cfg['dealer'];foreign=cfg['foreign']
    if event_id in world.paid_events:raise ValueError('duplicate exchange')
    if dealer not in world.households[actor].get('known_fx',[]):raise ValueError('unknown exchange counterparty')
    cost=quote(world,q);fee=cfg['fee'];principal=cost-fee
    legs=[(actor,dealer,principal),(account(dealer,foreign),account(actor,foreign),q)]
    if fee:legs.append((actor,cfg['fee_recipient'],fee))
    world.economics.cash.batch_pay(legs,fail_after=fail_after)
    world.paid_events.add(event_id);world.metrics['fx_events']+=1
    world.emit('fx_exchange',event_id=event_id,actor=actor,dealer=dealer,foreign=foreign,quantity=q,local_cost=cost,fee=fee,rate=[cfg['rate_numerator'],cfg['rate_denominator']],legs=legs)

def fund_purchase(world,actor,seller,good,quantity,fee):
    """Affordable quantity by finite budgets; no conversion if already funded."""
    cfg=world.case.get('currency');code=world.case.get('sale_currency',{}).get(seller+':'+good,'LOCAL')
    if not cfg or code=='LOCAL':return
    cash=world.economics.cash;price=world.economics.prices[(seller,good)]
    held=cash.accounts[account(actor,code)].available;dealer=cfg['dealer'];unit=cfg.get('monetary_unit',1)
    if dealer not in world.households[actor].get('known_fx',[]):return
    def needed(q):return ceil(Fraction(max(0,q*price-held),unit))*unit
    def feasible(q):
        need=needed(q)
        return need<=cash.accounts[account(dealer,code)].available and (quote(world,need) if need else 0)+q*fee<=cash.accounts[actor].available
    lo,hi=0,quantity
    while lo<hi:
        mid=(lo+hi+1)//2;world.metrics['fx_budget_checks']+=1
        if feasible(mid):lo=mid
        else:hi=mid-1
    required=needed(lo)
    if required:exchange(world,actor,required,f'fx:{world.day}:{actor}:{seller}:{good}:{world.sequence}')
