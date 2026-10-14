"""One inherited physical world with explicit household and labor day phases."""
import bootstrap
from network_simulation import NetworkSimulation
from payment_policy import PaymentPolicy
from learning import LearningPolicy
from collections import defaultdict
from copy import deepcopy
from fractions import Fraction
from math import ceil
import time
import heapq
from dataclasses import replace
from stock_admission import TransportSlots
import credit
import currency
import assets

class ProgrammePolicy(PaymentPolicy):
    @classmethod
    def wrap(cls,old,config):
        p=object.__new__(cls);p.__dict__=old.__dict__
        p.config=deepcopy(config);p.mode=config['mode']
        if p.sim.case.get('currency'):p.cash.currency_by_account=p.sim.case['currency']['account_currencies']
        if p.mode=='N4_EXPERIMENTAL':
            p.refusal_ceiling={k:4*v for k,v in p.initial_prices.items()};p.window_accepts=defaultdict(int)
        return p
    def request_result(self,*args):
        if self.sim.transport:
            response,physical,financial,current=args
            route=self.sim.route_index[(response['buyer_id'],response['commodity'],response['supplier_id'])];path=self.sim.path_for(route)
            shared=min([physical]+[sum(x['remaining_slot'] for x in self.sim.shared_slots[e].quote(self.sim.day,self.sim.edges[e]['capacity']))+response['accepted_quantity'] for e in (path or ())]) if path else 0
            response['shared_transport_atp']=shared;args=(response,min(physical,shared),financial,current)
        super().request_result(*args)
        if self.mode=='N4_EXPERIMENTAL':
            r=args[0];self.window_accepts[(r['supplier_id'],r['commodity'])]+=r['accepted_quantity']
    def end_day(self):
        if self.mode=='N4_EXPERIMENTAL':LearningPolicy.end_day(self)
        else:super().end_day()

    def settlement_accounts(self,buyer,seller,good):
        code=self.sim.case.get('sale_currency',{}).get(seller+':'+good,'LOCAL')
        return currency.account(buyer,code),currency.account(seller,code)

    def limit(self,request,physical):
        s=self.sim
        if not s.transport:return super().limit(request,physical)
        route=s.route_index[(request['buyer_id'],request['commodity'],request['supplier_id'])];path=s.path_for(route)
        if path is None:return 0
        capacity=min([physical]+[sum(x['remaining_slot'] for x in s.shared_slots[e].quote(s.day,s.edges[e]['capacity'])) for e in path])
        price=self.prices[(request['supplier_id'],request['commodity'])];fee=sum(s.edges[e]['fee'] for e in path)
        if price>self.config['limits'][request['buyer_id']][request['commodity']]:return 0
        buyer=request['buyer_id'];cash_buyer,_=self.settlement_accounts(buyer,request['supplier_id'],request['commodity'])
        if cash_buyer==buyer:return min(capacity,self.cash.accounts[buyer].available//(price+fee))
        return min(capacity,self.cash.accounts[cash_buyer].available//price,self.cash.accounts[buyer].available//fee if fee else capacity)

    def accept(self,route,quantity,quote):
        s=self.sim
        if not s.transport:return super().accept(route,quantity,quote)
        path=s.path_for(route)
        if path is None:raise ValueError('no known feasible transport path')
        oid=len(s.orders)+1;buyer=s.routes[route].buyer_id;fee=sum(s.edges[e]['fee'] for e in path)
        originals={e:deepcopy(vars(s.shared_slots[e])) for e in path}
        before=self.cash.accounts[buyer].reserved
        try:
            for e in path:s.shared_slots[e].reserve(oid,quantity,s.shared_slots[e].quote(s.day,s.edges[e]['capacity']))
            if fee:self.cash.reserve(buyer,quantity*fee)
            order=super().accept(route,quantity,quote)
        except Exception:
            for e,v in originals.items():vars(s.shared_slots[e]).clear();vars(s.shared_slots[e]).update(v)
            self.cash.accounts[buyer].reserved=before
            raise
        s.order_paths[oid]=list(path);s.freight[oid]=dict(buyer=buyer,per_unit=fee,remaining=quantity*fee)
        s.emit('transport_reserved',order_id=oid,path=list(path),buyer=buyer,amount=quantity*fee,per_unit=fee)
        return order

    def check(self):
        extra=defaultdict(int)
        for f in self.sim.freight.values():extra[f['buyer']]+=f['remaining']
        for o in self.sim.asset_orders.values():
            if o['side']=='buy' and o['status']=='OPEN':extra[o['actor']]+=o['remaining']*o['limit']
        super().check(extra)

class ProgrammeWorld(NetworkSimulation):
    def __init__(self,case,writer=None):
        self.event_writer=writer;self.trace=[];self.sequence=0;self.phase='INITIAL'
        self.households={h['id']:deepcopy(h) for h in case['households']}
        self.jobs={j['id']:deepcopy(j) for j in case.get('jobs',[])}
        self.contracts={};self.wage_claims={};self.paid_events=set();self.worked={};self.absent=set()
        self.need_history=[];self.need_today={};self.cohort_hours=defaultdict(int);self.received_income=defaultdict(int)
        self.satisfaction=case['food_satisfaction'];self.information={};self.events_schedule=defaultdict(list)
        self.transport=bool(case.get('transport'));self.edges=deepcopy(case.get('transport',{}).get('edges',{}));self.path_options=case.get('transport',{}).get('paths',{})
        self.known_edges=case.get('transport',{}).get('known_edges',{});self.shared_slots={e:TransportSlots(2) for e in self.edges};self.edge_remaining={};self.order_paths={};self.journeys={};self.freight={};self.relations={}
        self.loans={}
        for e in case.get('events',[]):self.events_schedule[e['day']].append(deepcopy(e))
        initial=deepcopy(case)
        if initial['economics']['mode']=='N4_EXPERIMENTAL':initial['economics']['mode']='N3'
        super().__init__(initial);self.case=deepcopy(case)
        cash=self.economics.cash;self.economics=ProgrammePolicy.wrap(self.economics,case['economics'])
        assert self.economics.cash is cash
        self.economics.writer=self.economic_event
        assets.initialize(self)
        self.initial_snapshot=self.snapshot()
        self.emit('initial',state=self.initial_snapshot,fixture=case)

    def emit(self,event,**fields):
        if fields.pop('day',self.day)!=self.day:raise ValueError('event time differs from world clock')
        self.sequence+=1
        row=dict(seq=self.sequence,day=self.day,phase=self.phase,event=event,**deepcopy(fields))
        if self.event_writer:self.event_writer(row)
        else:self.trace.append(row)
        return row

    def economic_event(self,row):
        row=dict(row);row.pop('day',None);name=row.pop('event');self.emit(name,**row)

    def snapshot(self):
        value=dict(day=self.day,stock=deepcopy(self.stock),cash={k:dict(balance=a.balance,reserved=a.reserved) for k,a in self.economics.cash.accounts.items()},orders={str(k):dict(route=o.route,quantity=o.quantity,pending=o.pending_dispatch,delivered=o.delivered,cancelled=o.cancelled,shipments={str(sid):dict(quantity=s.quantity,arrival_day=s.arrival_day,dispatch_day=s.dispatch_day) for sid,s in o.active_shipments.items()}) for k,o in self.orders.items()},contracts=deepcopy(self.contracts),wage_claims=deepcopy(self.wage_claims),households=deepcopy(self.households),prices={':'.join(k):v for k,v in self.economics.prices.items()})
        if self.transport:value.update(freight={str(k):dict(v) for k,v in self.freight.items()},journeys={str(k):dict(v) for k,v in self.journeys.items()})
        if self.case.get('enable_relations'):value['relations']={'|'.join(k):dict(v) for k,v in self.relations.items()}
        if self.case.get('credit'):value['loans']=deepcopy(self.loans)
        if self.case.get('assets'):value.update(shares=deepcopy(self.shares),share_reserved=deepcopy(self.share_reserved),asset_orders=deepcopy(self.asset_orders))
        return value

    def transfer(self,event_id,buyer,seller,amount,reserved=False,**context):
        if event_id in self.paid_events:raise ValueError('duplicate cash event')
        self.economics.cash.pay(buyer,seller,amount,reserved=reserved)
        self.paid_events.add(event_id);self.emit('cash_transfer',event_id=event_id,buyer=buyer,seller=seller,amount=amount,**({'reserved_release':amount} if reserved else {}),**context)

    def messages(self):
        self.absent=set()
        for e in self.events_schedule.pop(self.day,[]):
            kind=e['kind']
            if kind=='job_message':
                if e['observed_day']>self.day:raise ValueError('future information')
                h=self.households[e['actor']];h['known_jobs']=sorted(set(h['known_jobs'])|{e['job']});self.information[(e['actor'],e['job'])]=dict(observed_day=e['observed_day'],received_day=self.day)
            elif kind=='job_close':
                self.jobs[e['job']]['positions']=0
                for hid in list(self.contracts):
                    if self.contracts[hid]['job']==e['job']:
                        self.emit('employment_end',actor=hid,job=e['job']);del self.contracts[hid]
            elif kind=='absence':self.absent.add(e['actor'])
            elif kind=='edge_capacity':self.edges[e['edge']]['capacity']=e['capacity']
            elif kind=='supplier_message':
                if e['observed_day']>self.day:raise ValueError('future supplier information')
                if (e['actor'],e['good'],e['seller']) not in self.route_index:raise ValueError('message without physical opportunity')
                self.firms[e['actor']].knowledge.setdefault(e['good'],set()).add(e['seller'])
            elif kind=='relation_invalid':self.relations.pop((e['actor'],e['good'],e['seller']),None)
            else:raise ValueError('unknown programme event '+kind)
            self.emit('message',spec=e)

    def path_for(self,route):
        r=self.routes[route];known=set(self.known_edges.get(r.buyer_id,self.edges))
        paths=[tuple(p) for p in self.path_options.get(route,[]) if p and all(e in known and self.edges[e]['capacity']>0 for e in p)]
        def connected(path):
            node=self.firms[r.seller_id].place_id
            for e in path:
                if self.edges[e]['from']!=node:return False
                node=self.edges[e]['to']
            return node==self.firms[r.buyer_id].place_id
        paths=[p for p in paths if connected(p)]
        return min(paths,key=lambda p:(sum(self.edges[e]['duration'] for e in p),sum(self.edges[e]['fee'] for e in p),p)) if paths else None

    def quote(self,buyer,good,seller,phase='MATCHING'):
        started=time.perf_counter()
        o=super().quote(buyer,good,seller,phase)
        self.timing['candidate_search_seconds']+=time.perf_counter()-started
        if not self.transport:return o
        route=self.route_index[(buyer,good,seller)];path=self.path_for(route)
        if path is None:return replace(o,max_acceptable_quantity=0)
        cap=min([o.max_acceptable_quantity]+[sum(x['remaining_slot'] for x in self.shared_slots[e].quote(self.day,self.edges[e]['capacity'])) for e in path])
        return replace(o,max_acceptable_quantity=cap,route_lead_time=sum(self.edges[e]['duration'] for e in path),expected_arrival_day=self.day+2+sum(self.edges[e]['duration'] for e in path))

    def dispatch_allowance(self,route,order,remaining):
        if not self.transport:return super().dispatch_allowance(route,order,remaining)
        return min([remaining]+[self.edge_remaining[e] for e in self.order_paths[order.id]])

    def dispatch_lead_time(self,route,order):
        if not self.transport:return super().dispatch_lead_time(route,order)
        return sum(self.edges[e]['duration'] for e in self.order_paths[order.id])

    def record_event(self,event,order,shipment=None,quantity=0):
        super().record_event(event,order,shipment,quantity)
        if event in ('dispatched','cancelled') and self.transport:
            path=self.order_paths[order.id]
            for e in path:
                self.shared_slots[e].release(order.id,quantity)
                if event=='dispatched':self.shared_slots[e].dispatched(self.day,quantity);self.edge_remaining[e]-=quantity
            f=self.freight[order.id];value=quantity*f['per_unit']
            if event=='cancelled':
                if value:self.economics.cash.release(f['buyer'],value);self.emit('freight_released',order_id=order.id,buyer=f['buyer'],amount=value)
            else:
                self.journeys[shipment.id]=dict(path=list(path),position=0,elapsed=0)
                self.emit('transport_departed',shipment_id=shipment.id,order_id=order.id,path=list(path),quantity=quantity)
                if value:self.transfer(f'freight:{shipment.id}',f['buyer'],self.case['transport']['carrier'],value,reserved=True,reason='freight',order_id=order.id,shipment_id=shipment.id)
            f['remaining']-=value
        if event=='arrived':
            r=self.routes[order.route]
            if self.transport:self.journeys.pop(shipment.id)
            if self.case.get('enable_relations'):
                key=(r.buyer_id,r.commodity,r.seller_id);self.relations[key]=dict(last_delivery_day=self.day)
                self.emit('relation_delivery',buyer=r.buyer_id,good=r.commodity,seller=r.seller_id,order_id=order.id)

    def receive(self):
        if self.transport:
            for _,_,cargo in sorted(self.arrivals,key=lambda row:row[2].id):
                j=self.journeys[cargo.id];edge=j['path'][j['position']];self.metrics['active_transport_visits']+=1
                if self.edge_remaining[edge]>=cargo.quantity:
                    self.edge_remaining[edge]-=cargo.quantity
                    j['elapsed']+=1
                    if j['elapsed']==self.edges[edge]['duration']:j['position']+=1;j['elapsed']=0
                if j['position']<len(j['path']):
                    if cargo.arrival_day<=self.day:
                        old=cargo.arrival_day;cargo.arrival_day=self.day+1;self.emit('transit_delay',shipment_id=cargo.id,old_arrival=old,new_arrival=cargo.arrival_day)
                self.emit('transport_position',shipment_id=cargo.id,position=j['position'],elapsed=j['elapsed'])
            self.arrivals=[(c.arrival_day,c.id,c) for _,_,c in self.arrivals];heapq.heapify(self.arrivals)
        return super().receive()

    def match_labor(self):
        slots={j['id']:j['positions'] for j in self.jobs.values()}
        for c in self.contracts.values():slots[c['job']]-=c['workers']
        for hid,h in sorted(self.households.items()):
            if hid in self.contracts:continue
            candidates=[]
            for jid in sorted(set(h['known_jobs'])):
                self.metrics['job_candidate_visits']+=1
                if jid not in self.jobs:continue
                j=self.jobs[jid];distance=0 if self.firms[hid].place_id==j['place'] else 2
                reason='SKILL' if h['skill']<j['skill'] else 'GEOGRAPHY' if distance>h['max_travel'] else 'NO_VACANCY' if slots[jid]<=0 else None
                self.emit('job_offer',actor=hid,job=jid,known=True,distance=distance,reason=reason,wage=j['wage_per_hour'])
                if reason is None:candidates.append(j)
            if not candidates:continue
            j=min(candidates,key=lambda x:(-x['wage_per_hour'],x['id']))
            workers=min(h['adults'],slots[j['id']])
            self.contracts[hid]=dict(job=j['id'],workers=workers);slots[j['id']]-=workers
            self.emit('employment',actor=hid,job=j['id'],workers=workers)

    def work_and_wages(self):
        self.worked=defaultdict(int)
        # Previously earned arrears remain enforceable; no automatic forgiveness.
        for claim_id,claim in sorted(self.wage_claims.items()):self.pay_claim(claim_id,claim)
        for hid,c in sorted(self.contracts.items()):
            h=self.households[hid];j=self.jobs[c['job']]
            hours=0 if hid in self.absent else c['workers']*min(h['hours_per_worker'],j['hours'])
            if not hours:continue
            work_id=f'work:{self.day}:{hid}'
            self.worked[j['employer']]+=hours;self.cohort_hours[hid]+=hours
            claim=dict(worker=hid,employer=j['employer'],hours=hours,amount=hours*j['wage_per_hour'],remaining=hours*j['wage_per_hour'],work_day=self.day,job=j['id'])
            if j.get('pay_delay',0):claim['due_day']=self.day+j['pay_delay']
            self.wage_claims[work_id]=claim
            self.emit('work',work_id=work_id,actor=hid,job=j['id'],employer=j['employer'],hours=hours,workers=c['workers'],wage_per_hour=j['wage_per_hour'])
            self.emit('wage_accrued',claim_id=work_id,**claim)
            self.pay_claim(work_id,claim)

    def pay_claim(self,claim_id,claim):
        if self.day<claim.get('due_day',claim['work_day']):return
        q=min(claim['remaining'],self.economics.cash.accounts[claim['employer']].available)
        if q:
            event_id=f'wage:{self.day}:{claim_id}:{claim["remaining"]}'
            self.transfer(event_id,claim['employer'],claim['worker'],q,reason='wage',claim_id=claim_id)
            claim['remaining']-=q;self.received_income[claim['worker']]+=q

    def production_plan(self):
        plan=super().production_plan()
        if self.case['enable_labor']:
            for fid in self.active_firms:
                hours=self.worked.get(fid,0)
                for recipe in sorted(self.firms[fid].recipes,key=lambda r:r.output_commodity):
                    key=fid+':'+recipe.output_commodity;per=self.case['labor_hours_per_output'][key]
                    q=min(plan[fid][recipe.output_commodity],hours//per);hours-=q*per
                    self.emit('production_plan',actor=fid,good=recipe.output_commodity,pre_labor=plan[fid][recipe.output_commodity],actual=q,available_hours=self.worked.get(fid,0),hours_used=q*per)
                    plan[fid][recipe.output_commodity]=q
        else:
            for fid,quantities in plan.items():
                for good,q in quantities.items():self.emit('production_plan',actor=fid,good=good,actual=q,pre_labor=q,hours_used=0)
        return plan

    def create_needs(self):
        self.need_today={}
        for hid,h in sorted(self.households.items()):
            needs=dict(food=h['members']*h['food_per_member'],optional_durable=max(0,h['members']*h['optional_durable_per_member']-self.stock[hid]['soap']))
            self.need_today[hid]=dict(day=self.day,actor=hid,required=needs['food'],consumed=0,unmet=needs['food'],wish=needs['optional_durable'])
            self.emit('needs',actor=hid,members=h['members'],current=needs['food'],wish=needs['optional_durable'])

    def household_position(self,hid):
        units=sum(self.stock[hid][g]*u for g,u in self.satisfaction.items())
        for good,u in self.satisfaction.items():
            for route in self.inbound[(hid,good)]:
                pending,transit=self.balances(route);units+=(pending+transit)*u
        return units

    def procurement_intent(self,buyer,good,offer,round_number):
        if buyer not in self.households:return super().procurement_intent(buyer,good,offer,round_number)
        h=self.households[buyer]
        if good in self.satisfaction:
            target=h['members']*h['food_per_member']*self.case['stock_horizon']
            units=max(0,target-self.household_position(buyer));q=ceil(Fraction(units,self.satisfaction[good]))
        else:
            exposure=self.stock[buyer][good]+sum(sum(self.balances(r)) for r in self.inbound[(buyer,good)])
            q=max(0,h['members']*h['optional_durable_per_member']-exposure)
        if not q:return None
        return dict(buyer_id=buyer,supplier_id=offer.supplier_id,commodity=good,requested_quantity=q,request_day=self.day,procurement_round=round_number,quoted_quantity=offer.max_acceptable_quantity,expected_arrival_day=offer.expected_arrival_day,lines=[dict(need_id=f'{buyer}:{"food" if good in self.satisfaction else good}:{offer.expected_arrival_day}',commodity=good,quantity=q,need_by_day=offer.expected_arrival_day)],procurement_need_id=f'{buyer}:{good}:{offer.expected_arrival_day}')

    def purchase_households(self):
        for hid,h in sorted(self.households.items()):
            offers=[]
            for good in self.satisfaction:
                if h['choice']=='fixed' and good!='bread':continue
                for seller in sorted(self.firms[hid].knowledge.get(good,set())):
                    o=self.quote(hid,good,seller)
                    path=self.path_for(self.route_index[(hid,good,seller)]) if self.transport else None
                    fee=sum(self.edges[e]['fee'] for e in (path or ()))
                    code=self.case.get('sale_currency',{}).get(seller+':'+good,'LOCAL')
                    local_price=o.posted_price if code=='LOCAL' else Fraction(o.posted_price*self.case['currency']['rate_numerator'],self.case['currency']['rate_denominator'])
                    if code!='LOCAL':
                        units=max(1,min(o.max_acceptable_quantity,ceil(Fraction(max(0,h['members']*h['food_per_member']*self.case['stock_horizon']-self.household_position(hid)),self.satisfaction[good]))))
                        if self.economics.cash.accounts[currency.account(hid,code)].available<units*o.posted_price:local_price+=Fraction(self.case['currency']['fee'],units)
                    offers.append((Fraction(local_price+fee,self.satisfaction[good]),o.expected_arrival_day,seller,good,o))
                    self.emit('visible_offer',actor=hid,seller=seller,good=good,price=o.posted_price,quantity=o.max_acceptable_quantity,eta=o.expected_arrival_day)
            def key(x):
                relation=self.relations.get((hid,x[3],x[2]))
                recent=self.case.get('enable_relations') and relation and self.day-relation['last_delivery_day']<=self.case.get('relation_ttl',6)
                return (0 if recent else 1,x[:4])
            for index,(_,_,seller,good,o) in enumerate(sorted(offers,key=key)):
                r=self.procurement_intent(hid,good,o,index)
                if r:
                    path=self.path_for(self.route_index[(hid,good,seller)]) if self.transport else ()
                    fee=sum(self.edges[e]['fee'] for e in (path or ()))
                    currency.fund_purchase(self,hid,seller,good,min(r['requested_quantity'],o.max_acceptable_quantity),fee)
                    self.emit('purchase_choice',actor=hid,seller=seller,good=good,need_id=r['procurement_need_id'],quantity=r['requested_quantity'],rule=h['choice'],available_cash=self.economics.cash.accounts[hid].available,**({'prior_delivery_day':self.relations.get((hid,good,seller),{}).get('last_delivery_day')} if self.case.get('enable_relations') else {}))
                    response=self.admit_round([r])[0];self.emit('request',**response)
            # Durable desire follows basic-food reservation; it does not create cash.
            for seller in sorted(self.firms[hid].knowledge.get('soap',set())):
                o=self.quote(hid,'soap',seller);r=self.procurement_intent(hid,'soap',o,len(offers))
                if r:self.emit('request',**self.admit_round([r])[0])

    def consume(self):
        for hid,h in sorted(self.households.items()):
            remaining=self.need_today[hid]['required'];consumed=0
            for good,unit in sorted(self.satisfaction.items()):
                q=min(self.stock[hid][good],ceil(Fraction(remaining,unit))) if remaining else 0
                if not q:continue
                self.stock[hid][good]-=q;self.add_flow(hid,good,'terminal',q)
                take=min(remaining,q*unit);remaining-=take;consumed+=take
                self.emit('household_consumed',actor=hid,good=good,quantity=q,satisfaction=take)
            self.need_today[hid].update(consumed=consumed,unmet=remaining)
            self.need_history.append(dict(self.need_today[hid]));self.emit('need_result',**self.need_today[hid])

    def step(self):
        t=time.perf_counter();self.day+=1;self.phase='MESSAGES';self.messages();assets.messages(self)
        prior_prices=dict(self.economics.prices);self.economics.begin_day()
        for spec in self.case['economics'].get('price_events',[]):
            if spec['day']==self.day:self.emit('posted_price_change',spec=spec,old=prior_prices[(spec['seller'],spec['commodity'])],new=self.economics.prices[(spec['seller'],spec['commodity'])])
        self.edge_remaining={e:v['capacity'] for e,v in self.edges.items()}
        self.day_flow={k:{g:dict(received=0,produced=0,consumed=0,dispatched=0,terminal=0) for g in self.goods} for k in self.stock}
        self.phase='ARRIVALS';part=time.perf_counter();self.receive();self.confirm_cancellations();self.update_local_observations();self.timing['physical_cash_settlement_seconds']+=time.perf_counter()-part
        self.phase='LABOR'
        if self.case['enable_labor']:
            part=time.perf_counter();self.match_labor();self.timing['labor_matching_seconds']+=time.perf_counter()-part
            part=time.perf_counter();self.work_and_wages();self.timing['labor_cash_settlement_seconds']+=time.perf_counter()-part
        part=time.perf_counter()
        if self.case.get('credit'):self.phase='CREDIT';credit.settle(self)
        if self.case.get('assets'):self.phase='ASSETS';assets.run_market(self)
        self.timing['credit_assets_seconds']+=time.perf_counter()-part
        self.phase='PRODUCTION';part=time.perf_counter();plan=self.production_plan();self.timing['production_policy_seconds']+=time.perf_counter()-part
        part=time.perf_counter();self.produce(plan);self.timing['physical_cash_settlement_seconds']+=time.perf_counter()-part
        self.phase='HOUSEHOLD_PURCHASE';part=time.perf_counter();self.create_needs();self.purchase_households();self.timing['household_choice_inclusive_seconds']+=time.perf_counter()-part
        self.phase='FIRM_PROCUREMENT';part=time.perf_counter();first=len(self.requests);self.procurement_boundary();self.timing['firm_planning_matching_inclusive_seconds']+=time.perf_counter()-part
        for r in self.requests[first:]:self.emit('request',**r)
        self.phase='DISPATCH';part=time.perf_counter();self.dispatch();self.timing['physical_cash_settlement_seconds']+=time.perf_counter()-part
        self.phase='CONSUMPTION';part=time.perf_counter();self.consume();self.timing['physical_cash_settlement_seconds']+=time.perf_counter()-part
        self.phase='CLOSE';before=len(self.economics.price_records);self.economics.end_day()
        for row in self.economics.price_records[before:]:self.emit('price_update',**row)
        part=time.perf_counter();self.check_accounts()
        if self.case.get('assets'):assets.check(self);assets.publish(self)
        self.metrics['active_order_peak']=max(self.metrics['active_order_peak'],sum(map(len,self.active_orders.values())))
        self.metrics['active_households']=len(self.households);self.metrics['active_producers']=len(self.active_firms);self.metrics['known_trading_edges']=sum(len(v) for n in self.firms.values() for v in n.knowledge.values());self.metrics['shared_edges']=len(self.edges)
        self.timing['total_seconds']+=time.perf_counter()-t
        self.emit('day_close',state=self.snapshot())
        self.timing['checks_snapshot_archive_inclusive_seconds']+=time.perf_counter()-part
        return dict(day=self.day,needs=deepcopy(self.need_today))
