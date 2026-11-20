"""Firm-local planning and explicit scarcity rules. No world or peer plans here."""
from collections import defaultdict
from dataclasses import dataclass, field
from fractions import Fraction
from math import ceil
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'release_round5b'))
from release_simulation import ExecutableSimulation
from planning_release import ReleaseBook,need_components
from demand_planning import Recipe,RecipeGraph,Demand,DemandHistory,daily_schedule,Supply
from stock_admission import StockCommitments,SupplierOffer,TransportSlots,PurchaseRequest


@dataclass(frozen=True)
class Route:
    seller_id: str
    buyer_id: str
    commodity: str
    capacity: int
    lead_time: int

    @property
    def route_id(self): return f'{self.seller_id}>{self.buyer_id}:{self.commodity}'

    def engine_spec(self):
        return dict(supplier=self.seller_id,buyer=self.buyer_id,commodity=self.commodity,
                    capacity=self.capacity,lead_time=self.lead_time)


class CustomerRequestHistory:
    """Latest unresolved public attempts, distinct revisions, not gross-flow forecasts.

    Each seller knows only requests it actually received. An identity may be seen
    at multiple sellers; that is competing observed interest, not extra terminal
    demand. Already accepted portions are the seller's separate live obligations.
    """
    def __init__(self):
        self.active={}; self.seen_max={}; self.new_by_day=defaultdict(int)
        self.gross=0; self.distinct_created=0; self.repeat_attempts=0; self.visits=0

    def observe(self,day,buyer,lines,accepted_lines):
        accepted=dict(accepted_lines)
        for line in lines:
            key=(buyer,line['need_id']); quantity=line['quantity']; self.gross+=quantity
            old=self.seen_max.get(key,0)
            if key in self.seen_max: self.repeat_attempts+=1
            delta=max(0,quantity-old); self.distinct_created+=delta; self.new_by_day[day]+=delta
            self.seen_max[key]=max(old,quantity)
            self.active[key]=dict(commodity=line['commodity'],need_by_day=line['need_by_day'],
                                 unresolved=max(0,quantity-accepted.get(line['need_id'],0)),last_day=day)

    def advance(self,day,commodity):
        for key,value in list(self.active.items()):
            self.visits+=1
            if value['need_by_day']<day or not value['unresolved']: del self.active[key]
        return self.new_by_day.pop(day-1,0)

    def exposure(self,commodity):
        return sum(v['unresolved'] for v in self.active.values() if v['commodity']==commodity)


@dataclass
class FirmNode:
    firm_id: str
    firm_type: str
    place_id: str
    recipes: tuple
    production_capacities: dict
    knowledge: dict
    input_targets: dict
    output_targets: dict
    active: bool=True
    inventories: dict=field(default_factory=dict)
    planning: dict=field(default_factory=dict)
    procurement: dict=field(default_factory=dict)
    customer_pending: dict=field(default_factory=lambda:defaultdict(int))
    customer_histories: dict=field(default_factory=dict)
    demand_histories: dict=field(default_factory=dict)
    terminal_backlog: dict=field(default_factory=lambda:defaultdict(int))
    rates: dict=field(default_factory=dict)
    release: ReleaseBook=field(default_factory=ReleaseBook)
    graph: object=None

    def __post_init__(self):
        self.knowledge={g:set(ids) for g,ids in self.knowledge.items()}
        self.graph=RecipeGraph(list(self.recipes))
        for recipe in self.recipes:
            self.customer_histories[recipe.output_commodity]=CustomerRequestHistory()
            self.demand_histories[recipe.output_commodity]=DemandHistory(20)
            self.rates[recipe.output_commodity]=Fraction(0)


def local_plan(node,day,horizon,lead_by_good):
    """Only own inventory, capacities, observed requests/orders and public lead enter."""
    visibility=horizon+max(lead_by_good.values(),default=0)
    records=[]; plans=[]; actual={}; available=dict(node.inventories)
    for recipe in sorted(node.recipes,key=lambda r:r.output_commodity):
        good=recipe.output_commodity; capacity=node.production_capacities[good]
        if not recipe.inputs:
            schedule=[min(capacity,max(0,node.output_targets.get(good,0)-available[good]))]+[0]*(horizon-1)
        else:
            obligations=node.customer_pending[good]+node.customer_histories[good].exposure(good)+node.terminal_backlog[good]
            total=max(0,obligations+node.rates[good]*horizon+node.output_targets.get(good,0)-available[good])
            schedule=daily_schedule(total,capacity,horizon)
        today=schedule[0]
        for material,coefficient in recipe.inputs:
            today=min(today,available[material]*recipe.output_quantity//coefficient)
        actual[good]=today
        for material,coefficient in recipe.inputs:
            available[material]-=ceil(Fraction(today*coefficient,recipe.output_quantity))
        for offset,qty in enumerate(schedule):
            date=day+offset
            plans.append(dict(day=day,firm_id=node.firm_id,commodity=good,production_day=date,
                              planned_output=qty,capacity=capacity,actual_output=today if offset==0 else None,
                              basis='OWN_OBSERVED_REQUESTS_ORDERS_AND_DEMAND',requirement_class='FIRM'))
            for material,q in node.graph.materials(good,qty,capacity,{})['gross'].items():
                records.append((node.firm_id,material,date,'FIRM',q,'OWN_FIRM_PLAN'))
        residual=max(0,obligations-sum(schedule)) if recipe.inputs else 0
        projected=min(capacity,ceil(node.rates[good]+Fraction(residual,horizon)))
        for date in range(day+horizon,day+visibility):
            for material,q in node.graph.materials(good,projected,capacity,{})['gross'].items():
                records.append((node.firm_id,material,date,'PROJECTED',q,'OWN_TRAILING_OBSERVATIONS'))
    # Several own recipes may share an input: one physical date/class responsibility.
    aggregated={}
    for producer,good,date,klass,q,basis in records:
        key=(producer,good,date,klass);aggregated[key]=aggregated.get(key,0)+q
    records=[(*key,q,'OWN_RECIPE_AGGREGATE') for key,q in aggregated.items()]
    node.release.revise(day,records,max(lead_by_good.values(),default=0))
    node.planning=dict(horizon=horizon,visibility=visibility,plans=plans,actual=actual)
    return actual


def contention(requests,available,policy,route_limits=None):
    """One request per buyer in this supplier/commodity round; integer conserved."""
    if policy not in ('C0','C1') or type(available) is not int or available<0: raise ValueError('invalid allocation')
    if len({r['buyer_id'] for r in requests})!=len(requests): raise ValueError('aggregate buyer attempts first')
    limits=route_limits or {}; result={r['buyer_id']:0 for r in requests}
    wanted={r['buyer_id']:r['requested_quantity'] for r in requests}
    if any(type(q) is not int or q<0 for q in wanted.values()): raise ValueError('invalid requested quantity')
    caps={b:min(q,limits.get(b,q)) for b,q in wanted.items()}
    if policy=='C0':
        for r in sorted(requests,key=lambda r:(r['request_day'],r['procurement_round'],r['buyer_id'],r['request_id'])):
            b=r['buyer_id'];q=min(available,caps[b]);result[b]=q;available-=q
    else:
        left=min(available,sum(caps.values())); eligible={b for b in wanted if caps[b]}
        while left and eligible:
            weights={b:wanted[b]-result[b] for b in eligible};total=sum(weights.values())
            exact={b:Fraction(left*weights[b],total) for b in eligible}
            quota={b:min(caps[b]-result[b],exact[b].numerator//exact[b].denominator) for b in eligible}
            consumed=sum(quota.values())
            for b,q in quota.items():result[b]+=q
            left-=consumed
            for b in sorted(eligible,key=lambda b:(-(exact[b]-int(exact[b])),b)):
                if left and result[b]<caps[b]:result[b]+=1;left-=1
            eligible={b for b in eligible if result[b]<caps[b]}
    assert sum(result.values())<=available if policy=='C1' else True
    assert all(0<=result[b]<=wanted[b] for b in result)
    return result
