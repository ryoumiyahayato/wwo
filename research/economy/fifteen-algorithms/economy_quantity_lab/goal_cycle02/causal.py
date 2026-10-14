"""Read-only causal tracing composed on the single historical runtime.

No observer record is an input to procurement, planning, or pricing. All quote
objects are returned unchanged. World ATP/unknown-seller diagnostics are marked
separately from the offer objects that were actually queried by a buyer.
"""
from pathlib import Path
import sys,json,hashlib,time,gzip,io
from dataclasses import asdict
from copy import deepcopy
from collections import defaultdict
OLD=Path(__file__).resolve().parent.parent/'goal_cycle01'
sys.path.insert(0,str(OLD))
from cycle_fixtures import make_case
from network_simulation import NetworkSimulation
from payment_policy import PaymentPolicy
from multi_supplier import ranked_offers
from observation import StreamObserver,canonical,dump

REASONS={'UNKNOWN_SUPPLIER','LATE_FOR_REQUIREMENT','NO_PHYSICAL_ATP','PRICE_ABOVE_LIMIT','INSUFFICIENT_CASH','HIGHER_PRICE_THAN_ELIGIBLE_ALTERNATIVE','OLD_SORT_TIE_BREAK','OTHER_EXPLICIT_REASON'}

def legacy_key(o):return (o['expected_arrival_day'],-o['max_acceptable_quantity'],o['supplier_id'])
def price_key(o):return (o['posted_price'],*legacy_key(o))

class FactorialPolicy(PaymentPolicy):
    """Only the explicitly declared new R treatment overrides rank.

    N0/N1/N2/N3 historical definitions in Cycle01 are untouched. Quotes and
    feedback continue using the inherited implementation verbatim.
    """
    def rank(self,offers):
        axis=self.config.get('ranking_axis')
        if axis=='R_LEGACY':return ranked_offers(offers)
        if axis=='R_PRICE_FIRST':return sorted(offers,key=lambda o:(o.posted_price,o.expected_arrival_day,-o.max_acceptable_quantity,o.supplier_id))
        return super().rank(offers)

class CausalSimulation(NetworkSimulation):
    def __init__(self,case):
        super().__init__(case)
        if case.get('economics',{}).get('ranking_axis'):
            self.economics=FactorialPolicy(self,case['economics'])
        self.trace=None;self.matching={};self.boundary_frame=0;self.sequence=0
        self.quote_phases={};self.reverse_requests=case.get('reverse_requests',False)

    def quote(self,buyer,good,seller,phase='MATCHING'):
        offer=super().quote(buyer,good,seller,phase)
        if self.trace:
            self.quote_phases[id(offer)]=phase
            if phase=='MATCHING':self.matching.setdefault((buyer,good),{})[seller]=asdict(offer)
        return offer

    def production_plan(self):
        plan=super().production_plan()
        if self.trace:
            for fid in self.active_firms:
                n=self.firms[fid]
                self.trace.emit('own_plan',day=self.day,firm=fid,terminal_backlog=dict(n.terminal_backlog),customer_pending=dict(n.customer_pending),observed_rates={g:str(v) for g,v in n.rates.items()},plans=n.planning['plans'],requirements=n.release.snapshot(),allocations=list(n.release.allocations),actual=plan[fid])
        return plan

    def procurement_boundary(self):
        if self.trace:self.matching={};self.quote_phases={};self.boundary_frame+=1
        return super().procurement_boundary()

    def procurement_intent(self,buyer,good,offer,round_number):
        result=super().procurement_intent(buyer,good,offer,round_number)
        if self.trace:
            self.sequence+=1
            n=self.firms[buyer];book=n.release;pool=(buyer,good)
            requirements=[dict(bucket_id=b.bucket_id,need_id=f'{buyer}:{good}:{b.need_by_day}',need_by_day=b.need_by_day,quantity=b.quantity,gap=book.gap(b.bucket_id),requirement_class=b.requirement_class,created_day=b.created_day) for b in sorted(book.active.values(),key=lambda b:(b.need_by_day,b.bucket_id)) if b.pool==pool]
            # MATCHING snapshots were queried by the real boundary, not by trace.
            visible=list(deepcopy(self.matching.get(pool,{})).values())
            if not visible:visible=[asdict(offer)] # explicit test/admission calls
            candidates=[]
            for o in deepcopy(visible):
                seller=o['supplier_id'];rid=self.route_index[(buyer,good,seller)]
                free=self.stock_commitments.uncommitted(seller,good,self.stock[seller][good])
                slots=self.route_slots[rid].quote(self.day,self.capacity(rid,self.day))
                slot=sum(x['remaining_slot'] for x in slots)
                o['world_diagnostic']=dict(stock_atp=free,transport_available=slot,current_atp=min(free,slot))
                candidates.append(o)
            cash=self.economics.cash.accounts[buyer].available
            limit=self.economics.config['limits'][buyer][good]
            per_need=[]
            for need in requirements:
                assessments=[]
                for o in candidates:
                    eta=o['expected_arrival_day'];release=need['need_by_day']-(eta-self.day)
                    timely=eta<=need['need_by_day'];due=release<=self.day
                    reasons=[]
                    if not timely:reasons.append('LATE_FOR_REQUIREMENT')
                    if not due:reasons.append('OTHER_EXPLICIT_REASON:RELEASE_NOT_DUE')
                    if o['max_acceptable_quantity']<=0:reasons.append('NO_PHYSICAL_ATP')
                    if o['posted_price']>limit:reasons.append('PRICE_ABOVE_LIMIT')
                    if cash<o['posted_price']:reasons.append('INSUFFICIENT_CASH')
                    assessments.append(dict(supplier=o['supplier_id'],expected_arrival=eta,release_day=release,timely=timely,release_due=due,posted_price=o['posted_price'],quoted_quantity=o['max_acceptable_quantity'],current_atp=o['world_diagnostic']['current_atp'],constraints=reasons,eligible=not reasons and need['gap']>0))
                eligible=[a for a in assessments if a['eligible']]
                elig_ids={a['supplier'] for a in eligible}
                usable=[o for o in candidates if o['supplier_id'] in elig_ids]
                old=min(usable,key=legacy_key)['supplier_id'] if usable else None
                price=min(usable,key=price_key)['supplier_id'] if usable else None
                for a in assessments:
                    if a['eligible'] and a['supplier']!=price:
                        best=next(x for x in assessments if x['supplier']==price)
                        a['constraints'].append('HIGHER_PRICE_THAN_ELIGIBLE_ALTERNATIVE' if a['posted_price']>best['posted_price'] else 'OLD_SORT_TIE_BREAK')
                per_need.append(dict(**need,candidates=assessments,shadow_legacy=old,shadow_price_first=price,matched_competitive=len(usable)>=2 and len({o['posted_price'] for o in usable})>=2,shadow_differs=old!=price))
            unknown=[f for f,node in sorted(self.firms.items()) if f not in n.knowledge.get(good,set()) and any(r.output_commodity==good for r in node.recipes)]
            self.trace.emit('decision',day=self.day,decision_id=self.sequence,boundary=self.boundary_frame,buyer=buyer,commodity=good,round=round_number,phase=self.quote_phases.get(id(offer),'EXPLICIT'),selected_supplier=offer.supplier_id,known=sorted(n.knowledge.get(good,set())),queried=sorted(self.matching.get(pool,{})),buyer_visible_information=dict(offers=visible,available_cash=cash,max_unit_price=limit,procurement_gap=n.procurement.get(good,{})),world_diagnostic=dict(current_resources={o['supplier_id']:o['world_diagnostic'] for o in candidates},unknown_suppliers=[dict(supplier=f,reason='UNKNOWN_SUPPLIER') for f in unknown]),requirements=per_need,intent=deepcopy(result),scope='SHADOW_SAME_STATE_ONLY')
        return result

    def admit_round(self,intents):
        result=super().admit_round(list(reversed(intents)) if self.reverse_requests else intents)
        if self.trace:
            for r in result:self.trace.emit('request',day=self.day,request=deepcopy(r),locked_price=r.get('posted_price') if r.get('order_id') else None)
        return result

class CausalTrace:
    def __init__(self,sim,path,enabled=True):
        self.sim=sim;self.path=Path(path);self.file=None;self.raw_file=None;self.count=0;self.seconds=0
        if enabled:
            self.path.mkdir(parents=True,exist_ok=True);self.raw_file=(self.path/'causal.jsonl.gz').open('wb');self.file=io.TextIOWrapper(gzip.GzipFile(filename='',fileobj=self.raw_file,mode='wb',compresslevel=1,mtime=0),encoding='utf-8',newline='\n');sim.trace=self
        self.window_accepted=defaultdict(int)
        self.original_end=sim.economics.end_day
        if enabled:sim.economics.end_day=self.end_day

    def emit(self,event,**fields):
        if not self.file:return
        if event=='request':
            q=fields['request'];self.window_accepted[(q['supplier_id'],q['commodity'])]+=q['accepted_quantity']
        t=time.perf_counter();self.file.write(canonical(dict(event=event,**fields))+'\n');self.count+=1;self.seconds+=time.perf_counter()-t

    def end_day(self):
        s=self.sim;e=s.economics
        if e.mode in ('N3','N4_EXPERIMENTAL') and e.config.get('feedback',True) and s.day%7==0:
            before={}
            for (seller,good),w in sorted(e.windows.items()):
                interests=[dict(buyer=k[0],need_id=k[1],**deepcopy(v)) for k,v in sorted(w['interest'].items())]
                before[(seller,good)]=dict(window_start=s.day-6,window_end=s.day,accepted_quantity=self.window_accepted[(seller,good)],free_stock=s.stock_commitments.uncommitted(seller,good,s.stock[seller][good]),shipped=w['shipped'],information=sorted([list(k) for k in w['information']]),distinct_requests=len(w['information']),distinct_unresolved=sum(any(v[r] for r in ('PHYSICAL','PRICE_LIMIT','CASH')) and v['date']>=s.day for v in w['interest'].values()),interests=interests,old_price=e.prices[(seller,good)])
            self.original_end()
            for (seller,good),v in before.items():
                result=next((r for r in reversed(e.price_records) if r['day']==s.day and r['seller']==seller and r['commodity']==good),None)
                self.emit('price_update',day=s.day,seller=seller,commodity=good,local=v,result=deepcopy(result),pending_price=e.pending_prices[s.day+1][(seller,good)],direction='UP' if e.pending_prices[s.day+1][(seller,good)]>v['old_price'] else 'DOWN' if e.pending_prices[s.day+1][(seller,good)]<v['old_price'] else 'HOLD',tick_blocked=bool(result and result['step']==0 and result['reason'] not in ('HOLD','NO_NEW_INFORMATION')),clamp_blocked=bool(result and result['unclamped']!=result['price']))
            self.window_accepted.clear()
        else:self.original_end()

    def finish_day(self):
        s=self.sim
        self.emit('day_link',day=s.day,sinks={sid:dict(firm=v['firm_id'],received=v['received'],delivered=v['delivered'],backlog=v['backlog']) for sid,v in sorted(s.sinks.items())},production={f:dict(s.firms[f].planning.get('actual',{})) for f in s.active_firms},customer_identity_cache=sum(len(h.seen_max) for n in s.firms.values() for h in n.customer_histories.values()),release_identity_cache=sum(len(n.release.first_seen)+len(n.release.absolute_seen) for n in s.firms.values()),active_buckets=sum(len(n.release.active) for n in s.firms.values()))

    def close(self):
        if self.file:self.file.close()
        if self.raw_file:self.raw_file.close()
        self.sim.trace=None
        self.sim.economics.end_day=self.original_end
        return dict(records=self.count,trace_write_seconds=self.seconds)
