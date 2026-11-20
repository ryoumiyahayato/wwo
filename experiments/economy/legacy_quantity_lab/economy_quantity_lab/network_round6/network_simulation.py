"""Opt-in generic firm hooks on the existing order/FIFO/shipment authority.

The old single-terminal step and hardcoded production hook cannot iterate new
firms. This adapter supplies those orchestration/recipe/account hooks; it inherits
the physical receive, dispatch, acceptance and cancellation quantity operations.
There is one stock map and one arrivals heap, not a simulation per enterprise.
"""
from collections import defaultdict
from copy import deepcopy
from dataclasses import asdict
from fractions import Fraction
from math import ceil
import time

from firm_network import (FirmNode,Route,Recipe,Supply,local_plan,contention,need_components,
                         StockCommitments,TransportSlots,SupplierOffer,PurchaseRequest,ExecutableSimulation,Demand)
from commitment_adapter import CommitmentSimulation
from supplier_admission import AdmissionSimulation
from economy import Simulation,GOODS,require
from multi_supplier import ranked_offers


class NetworkSimulation(AdmissionSimulation):
    def __init__(self,case):
        self.case=deepcopy(case);self.contention_policy=case['contention'];self.horizon=case.get('horizon',10)
        self.firms={}
        for spec in case['firms']:
            node=FirmNode(spec['firm_id'],spec['firm_type'],spec['place_id'],
                          tuple(Recipe(**r) for r in spec['recipes']),dict(spec['capacities']),
                          spec['knowledge'],dict(spec['input_targets']),dict(spec['output_targets']),spec.get('active',True))
            if node.firm_id in self.firms:raise ValueError('duplicate firm ID')
            self.firms[node.firm_id]=node
        self.active_firms=tuple(sorted(k for k,n in self.firms.items() if n.active and n.recipes))
        routes=[Route(**r) for r in case['routes']]
        self.routes={r.route_id:r for r in sorted(routes,key=lambda r:r.route_id)}
        if len(self.routes)!=len(routes):raise ValueError('duplicate physical edge')
        self.route_index={(r.buyer_id,r.commodity,r.seller_id):k for k,r in self.routes.items()}
        self.inbound=defaultdict(list);self.outbound=defaultdict(list)
        for key,r in self.routes.items():
            self.inbound[(r.buyer_id,r.commodity)].append(key);self.outbound[(r.seller_id,r.commodity)].append(key)
        self.stock_commitments=StockCommitments();self.route_slots={r:TransportSlots(2) for r in self.routes}
        self.requests=[];self.requests_by_day=defaultdict(list);self.quotes=[];self.round_records=[]
        self.plans=[];self.firm_rows=[];self.flow_rows=[];self.sink_rows=[];self.route_rows=[];self.allocation_rows=[]
        self.customer_rows=[];self.current_quotes={};self.order_request={};self.live_visits=0
        self.cancel_requests={};self.cancel_history=[];self.confirmation_delay=1
        self.sinks={s['sink_id']:dict(s,backlog=0,received=0,delivered=0) for s in case['sinks']}
        self.initial_firm=deepcopy(case['inventory']);self.flow={k:{g:dict(received=0,produced=0,consumed=0,dispatched=0,terminal=0) for g in GOODS} for k in self.firms}
        self.day_flow={};self.expected_arrival={}
        self.metrics=defaultdict(int);self.metric_rows=[];self.timing=defaultdict(float)
        self.updates=defaultdict(list)
        for e in case.get('capacity_events',[]):self.updates[e['day']].append(e)
        self.knowledge_updates=defaultdict(list)
        for e in case.get('knowledge_events',[]):self.knowledge_updates[e['day']].append(e)
        config=dict(initial_inventory=case['inventory'],routes={k:r.engine_spec() for k,r in self.routes.items()},
                    scenarios={'network':case.get('route_events',{})},daily_terminal_demand=0,days=case['days'],
                    production={},replenishment={})
        CommitmentSimulation.__init__(self,config,'network',policy='R2',promise_window_days=2)
        for key,node in self.firms.items():node.inventories=self.stock[key]
        self.economics=None
        if case.get('economics'):
            from payment_policy import PaymentPolicy
            self.economics=PaymentPolicy(self,case['economics'])

    def add_flow(self,firm,good,field,quantity):
        self.flow[firm][good][field]+=quantity
        if self.day_flow:self.day_flow[firm][good][field]+=quantity
        if getattr(self,'economics',None) and field in ('produced','consumed') and quantity:
            self.economics.emit(field,firm=firm,commodity=good,quantity=quantity)

    def record_event(self,event,order,shipment=None,quantity=0):
        CommitmentSimulation.record_event(self,event,order,shipment,quantity)
        route=self.routes[order.route];seller=route.seller_id;buyer=route.buyer_id;good=route.commodity
        if event=='accepted':
            self.firms[seller].customer_pending[good]+=quantity
            self.expected_arrival[order.id]=self.day+2+route.lead_time
        elif event in ('dispatched','cancelled'):
            self.firms[seller].customer_pending[good]-=quantity
            self.route_slots[order.route].release(order.id,quantity)
            self.stock_commitments.release(order.id,quantity)
            if event=='dispatched':
                self.route_slots[order.route].dispatched(self.day,quantity)
                self.add_flow(seller,good,'dispatched',quantity)
        elif event=='arrived':self.add_flow(buyer,good,'received',quantity)
        if getattr(self,'economics',None):self.economics.order_event(event,order,shipment,quantity)

    def quote(self,buyer,good,seller,phase='MATCHING'):
        if seller not in self.firms[buyer].knowledge.get(good,set()):raise ValueError('unknown supplier query')
        route=self.route_index[(buyer,good,seller)];spec=self.routes[route]
        slots=self.route_slots[route].quote(self.day,self.capacity(route,self.day))
        transport=sum(s['remaining_slot'] for s in slots)
        free=self.stock_commitments.uncommitted(seller,good,self.stock[seller][good])
        offer=SupplierOffer(seller,good,self.day,min(transport,free),self.day+2,spec.lead_time,self.day+2+spec.lead_time)
        self.metrics['offer_queries']+=1;self.metrics['known_candidate_visits']+=1
        self.metrics[phase.lower()+'_offer_queries']+=1
        self.quotes.append(dict(day=self.day,buyer_id=buyer,phase=phase,**asdict(offer)))
        return self.economics.quote(offer) if self.economics else offer

    def supply_lots(self,buyer):
        node=self.firms[buyer];result=[]
        for good in node.input_targets:
            result.append(Supply(f'stock:{buyer}:{good}',buyer,good,self.stock[buyer][good],self.day,'ON_HAND'))
            for route in self.inbound[(buyer,good)]:
                for order in self.active_orders[route].values():
                    self.metrics['live_supply_visits']+=1
                    if order.pending_dispatch:
                        deadline=self.commitments[order.id].promised_dispatch_by_day
                        eta=self.expected_arrival[order.id] if deadline is not None and self.day<=deadline else None
                        result.append(Supply(f'pending:{order.id}',buyer,good,order.pending_dispatch,eta,'ACCEPTED_PENDING',order.id))
                    for cargo in order.active_shipments.values():
                        self.metrics['live_supply_visits']+=1
                        result.append(Supply(f'cargo:{cargo.id}',buyer,good,cargo.quantity,cargo.arrival_day,'IN_TRANSIT',order.id))
        return result

    def reconcile_firm(self,buyer):
        self.firms[buyer].release.reconcile(self.day,self.supply_lots(buyer))

    def receive(self): return Simulation.receive(self)

    def update_local_observations(self):
        for event in self.updates.pop(self.day,[]):
            self.firms[event['firm_id']].production_capacities[event['commodity']]=event['capacity']
        for event in self.knowledge_updates.pop(self.day,[]):
            buyer,good,seller=event['buyer'],event['commodity'],event['seller']
            if (buyer,good,seller) not in self.route_index:raise ValueError('information has no physical edge')
            self.firms[buyer].knowledge.setdefault(good,set()).add(seller)
        terminal=defaultdict(int)
        for sid in sorted(self.sinks):
            sink=self.sinks[sid]
            qty=next(q for first,last,q in sink['demand_intervals'] if first<=self.day<=last)
            sink['received']+=qty;sink['backlog']+=qty
            node=self.firms[sink['firm_id']];node.terminal_backlog[sink['commodity']]+=qty
            terminal[(sink['firm_id'],sink['commodity'])]+=qty
        for fid in self.active_firms:
            node=self.firms[fid]
            for recipe in node.recipes:
                good=recipe.output_commodity
                observed=node.customer_histories[good].advance(self.day,good)+terminal[(fid,good)]
                node.rates[good]=node.demand_histories[good].observe(self.day,[Demand(fid,good,self.day,observed)])
        self.backlog=sum(s['backlog'] for s in self.sinks.values())

    def production_plan(self):
        result={}
        for fid in self.active_firms:
            node=self.firms[fid];leads={}
            for good,known in sorted(node.knowledge.items()):
                offers=[self.quote(fid,good,seller,'VISIBILITY') for seller in sorted(known)]
                leads[good]=max((o.expected_arrival_day-self.day for o in offers),default=0)
            result[fid]=local_plan(node,self.day,self.horizon,leads)
            self.plans.extend(node.planning['plans']);self.reconcile_firm(fid)
            self.metrics['planning_firm_visits']+=1
        return result

    def produce(self,plan):
        # Generic recipe hook replaces only the old A/B/C-specific hook. All
        # actual quantities are pre-production feasible, then debited once here.
        for fid in self.active_firms:
            node=self.firms[fid];consumed=defaultdict(int);produced=defaultdict(int)
            for recipe in node.recipes:
                q=plan[fid][recipe.output_commodity]
                require(0<=q<=node.production_capacities[recipe.output_commodity],'firm capacity')
                produced[recipe.output_commodity]+=q
                for good,coefficient in recipe.inputs:consumed[good]+=ceil(Fraction(q*coefficient,recipe.output_quantity))
            for good,q in consumed.items():
                require(q<=self.stock[fid][good],'firm inputs');self.stock[fid][good]-=q
                self.add_flow(fid,good,'consumed',q)
            for good,q in produced.items():
                self.stock[fid][good]+=q;self.add_flow(fid,good,'produced',q)
                self.cumulative[dict(coal='coal_mined',steel='steel_produced',machine='machine_produced')[good]]+=q
            node.release.consume(self.day,{(fid,g):q for g,q in consumed.items()})
            self.reconcile_firm(fid);self.metrics['firm_settlement_visits']+=1

    def deliver_terminal(self):
        total=0
        for sid in sorted(self.sinks):
            s=self.sinks[sid];fid=s['firm_id'];good=s['commodity']
            q=min(s['backlog'],self.stock[fid][good])
            if self.economics:
                q=self.economics.terminal_quantity(s,q)
                self.economics.terminal_payment(s,q)
            s['backlog']-=q;s['delivered']+=q
            self.stock[fid][good]-=q;self.firms[fid].terminal_backlog[good]-=q
            self.add_flow(fid,good,'terminal',q);total+=q
            self.sink_rows.append(dict(day=self.day,sink_id=sid,firm_id=fid,commodity=good,
                                       received=s['received'],delivery=q,delivered=s['delivered'],backlog=s['backlog']))
        self.backlog=sum(s['backlog'] for s in self.sinks.values());self.cumulative['terminal_delivered']+=total
        return total

    def procurement_intent(self,buyer,good,offer,round_number):
        node=self.firms[buyer];book=node.release;pool=(buyer,good)
        gaps=book.executable(self.day,pool,offer)
        gap=sum(q for _,q in gaps);target=node.input_targets[good]
        components=need_components(max(0,target-book.exposure(pool)),gap,book.ceiling_room(pool,target))
        node.procurement[good]=dict(**components,real_exposure=book.exposure(pool),visible_exposure=book.visible(pool))
        quantity=components['procurement_need_total']
        if not quantity:return None
        lines=[];left=quantity
        for key,q in gaps:
            take=min(left,q)
            if take:lines.append(dict(need_id=f'{buyer}:{good}:{book.active[key].need_by_day}',source_bucket_id=key,
                                     commodity=good,quantity=take,need_by_day=book.active[key].need_by_day))
            left-=take
            if not left:break
        if left:lines.append(dict(need_id=f'{buyer}:{good}:SAFETY',commodity=good,quantity=left,need_by_day=offer.expected_arrival_day))
        return dict(buyer_id=buyer,supplier_id=offer.supplier_id,commodity=good,requested_quantity=quantity,
                    request_day=self.day,procurement_round=round_number,quoted_quantity=offer.max_acceptable_quantity,
                    expected_arrival_day=offer.expected_arrival_day,lines=lines,
                    procurement_need_id='|'.join(sorted(line['need_id'] for line in lines)))

    def admit_round(self,intents):
        # Canonical IDs are assigned to the simultaneous frame, not dict order.
        intents=sorted(intents,key=lambda r:(r['supplier_id'],r['commodity'],r['buyer_id']))
        groups=defaultdict(list)
        for offset,intent in enumerate(intents):
            if intent['supplier_id'] not in self.firms[intent['buyer_id']].knowledge.get(intent['commodity'],set()):raise ValueError('unknown supplier request')
            fact=PurchaseRequest(len(self.requests)+offset+1,intent['buyer_id'],intent['supplier_id'],intent['commodity'],intent['requested_quantity'],self.day)
            intent={**intent,**vars(fact)}
            groups[(intent['supplier_id'],intent['commodity'])].append(intent)
        responses=[]
        for (seller,good),group in sorted(groups.items()):
            free=self.stock_commitments.uncommitted(seller,good,self.stock[seller][good])
            limits={};quotes={}
            for request in group:
                route=self.route_index[(request['buyer_id'],good,seller)]
                quote=self.route_slots[route].quote(self.day,self.capacity(route,self.day));quotes[request['buyer_id']]=quote
                physical=sum(s['remaining_slot'] for s in quote)
                limits[request['buyer_id']]=self.economics.limit(request,physical) if self.economics else physical
            allocated=contention(group,free,self.contention_policy,limits)
            total_requested=sum(r['requested_quantity'] for r in group)
            self.round_records.append(dict(day=self.day,round=group[0]['procurement_round'],supplier=seller,commodity=good,
                available=free,total_requests=total_requested,policy=self.contention_policy,accepted_by_buyer=allocated,
                scarcity=total_requested>free or any(r['requested_quantity']>limits[r['buyer_id']] for r in group),
                unmet=total_requested-sum(allocated.values()),max_buyer_share=max(allocated.values(),default=0)/sum(allocated.values()) if sum(allocated.values()) else 0))
            self.metrics['contention_allocations']+=len(group)
            for request in sorted(group,key=lambda r:r['buyer_id']):
                buyer=request['buyer_id'];q=allocated[buyer];route=self.route_index[(buyer,good,seller)]
                onhand=self.stock[seller][good];current_free=self.stock_commitments.uncommitted(seller,good,onhand)
                slots=self.route_slots[route];current_quote=slots.quote(self.day,self.capacity(route,self.day))
                physical_cap=min(current_free,sum(s['remaining_slot'] for s in current_quote))
                current_need=request['requested_quantity']
                if self.economics and 'procurement_need_id' in request:
                    self.reconcile_firm(buyer)
                    fresh=self.procurement_intent(buyer,good,self.quote(buyer,good,seller,'RECHECK'),request['procurement_round'])
                    current_need=min(current_need,fresh['requested_quantity'] if fresh else 0)
                    q=min(q,current_need)
                financial_cap=self.economics.limit(request,physical_cap) if self.economics else physical_cap
                if self.economics:q=min(q,financial_cap)
                require(q<=min(current_free,sum(s['remaining_slot'] for s in current_quote)),'acceptance recheck')
                order=(self.economics.accept(route,q,current_quote) if self.economics else self.accept_order(route,q)) if q else None
                if order:
                    if not self.economics:
                        slots.reserve(order.id,q,current_quote);self.stock_commitments.reserve(order.id,seller,good,q,onhand)
                    self.order_request[order.id]=request['request_id']
                accepted_lines={};left=q
                for line in request['lines']:
                    take=min(left,line['quantity']);accepted_lines[line['need_id']]=take;left-=take
                response=dict(**request,accepted_quantity=q,rejected_quantity=request['requested_quantity']-q,
                    order_id=order.id if order else None,promised_dispatch_by_day=self.day+2 if order else None,
                    pool_available_at_round=free,uncommitted_at_acceptance=current_free,route_atp_at_acceptance=sum(s['remaining_slot'] for s in current_quote),
                    accepted_lines=accepted_lines)
                if self.economics:self.economics.request_result(response,physical_cap,financial_cap,current_need)
                self.requests.append(response);self.requests_by_day[self.day].append(response);responses.append(response)
                self.firms[seller].customer_histories[good].observe(self.day,buyer,request['lines'],accepted_lines)
                self.reconcile_firm(buyer)
        self.stock_commitments.check(self.stock)
        return responses

    def procurement_boundary(self):
        candidates={}
        for buyer in self.active_firms:
            node=self.firms[buyer];self.reconcile_firm(buyer)
            for good,known in sorted(node.knowledge.items()):
                offers=[self.quote(buyer,good,s,'MATCHING') for s in sorted(known)]
                candidates[(buyer,good)]=self.economics.rank(offers) if self.economics else ranked_offers(offers)
        maximum=max(map(len,candidates.values()),default=0)
        for round_number in range(maximum):
            intents=[]
            for (buyer,good),offers in sorted(candidates.items()):
                if round_number>=len(offers):continue
                intent=self.procurement_intent(buyer,good,offers[round_number],round_number)
                if intent:intents.append(intent)
            if intents:self.admit_round(intents)
            self.metrics['procurement_rounds']+=1
        self.metrics['max_rounds']=max(self.metrics['max_rounds'],maximum)

    def request_cancellation(self,order_id,quantity):
        order=self.orders[order_id]
        if type(quantity) is not int or not 0<quantity<=order.pending_dispatch or order_id in self.cancel_requests:raise ValueError('pending only')
        record=dict(order_id=order_id,state='CANCEL_REQUESTED',request_day=self.day,confirm_day=self.day+1,
            requested_cancel_qty=quantity,pending_at_request=order.pending_dispatch,confirmed_cancel_qty=0,
            no_longer_cancellable_qty=0,confirmation_delay=1)
        self.cancel_requests[order_id]=record;self.cancel_history.append(dict(record));return record

    def confirm_cancellations(self): return AdmissionSimulation.confirm_cancellations(self)

    def cancel_pending(self,order_id,quantity):raise ValueError('use confirmed cancellation handshake')

    def check_accounts(self):
        # Non-owning flow checks. No material update or decision is made here.
        transit=defaultdict(int);residuals={};pending_pool=defaultdict(int)
        for route,orders in self.active_orders.items():
            self.metrics['route_settlement_visits']+=1;spec=self.routes[route]
            for order in orders.values():
                order.check();pending_pool[(spec.seller_id,spec.commodity)]+=order.pending_dispatch
                for cargo in order.active_shipments.values():
                    require(cargo.dispatch_day<=self.day<cargo.arrival_day and cargo.received_day is None,'cargo interval')
                    transit[spec.commodity]+=cargo.quantity
        for fid in self.stock:
            self.metrics['world_ledger_firm_visits']+=1
            for good,stock in self.stock[fid].items():
                require(type(stock) is int and stock>=0,'negative/noninteger inventory')
                f=self.flow[fid][good]
                expected=self.initial_firm[fid][good]+f['received']+f['produced']-f['consumed']-f['dispatched']-f['terminal']
                require(stock==expected,'firm quantity residual')
        for good in GOODS:
            expected=self.initial[good]+sum(v[good]['produced']-v[good]['consumed']-v[good]['terminal'] for v in self.flow.values())
            residuals[good]=sum(s[good] for s in self.stock.values())+transit[good]-expected
            require(residuals[good]==0,'world quantity residual')
        for route,t in self.totals.items():
            p,tr=self.balances(route);res=t['ordered']-p-tr-t['delivered']-t['cancelled']
            self.route_order_residuals[route]=res;require(res==0,'route order identity')
        self.stock_commitments.check(self.stock)
        for pool,q in self.stock_commitments.totals.items():require(q==pending_pool[pool],'shared commitments equal pending')
        for fid,node in self.firms.items():
            for good,q in node.customer_pending.items():require(q==pending_pool[(fid,good)],'local customer order observation')
        for s in self.sinks.values():require(s['received']==s['delivered']+s['backlog'],'sink identity')
        if getattr(self,'economics',None):self.economics.check()
        return residuals

    def step(self):
        self.day+=1
        if self.economics:self.economics.begin_day()
        started=time.perf_counter()
        opening=deepcopy(self.stock)
        self.day_flow={k:{g:dict(received=0,produced=0,consumed=0,dispatched=0,terminal=0) for g in GOODS} for k in self.stock}
        arrivals=self.receive();self.confirm_cancellations();self.update_local_observations()
        self.timing['receive_observations_seconds']+=time.perf_counter()-started
        started=time.perf_counter();plan=self.production_plan()
        self.timing['planning_seconds']+=time.perf_counter()-started
        started=time.perf_counter();self.produce(plan);delivery=self.deliver_terminal()
        self.timing['production_delivery_seconds']+=time.perf_counter()-started
        started=time.perf_counter();self.procurement_boundary()
        self.timing['procurement_seconds']+=time.perf_counter()-started
        started=time.perf_counter();dispatched=self.dispatch()
        self.timing['dispatch_seconds']+=time.perf_counter()-started
        started=time.perf_counter();res=self.check_accounts()
        self.timing['account_seconds']+=time.perf_counter()-started
        started=time.perf_counter()
        self.metrics['active_order_peak']=max(self.metrics['active_order_peak'],sum(map(len,self.active_orders.values())))
        self.metrics['active_shipment_peak']=max(self.metrics['active_shipment_peak'],len(self.arrivals))
        for fid in sorted(self.firms):
            node=self.firms[fid]
            for good in GOODS:
                flow=self.day_flow[fid][good];residual=self.stock[fid][good]-(opening[fid][good]+flow['received']+flow['produced']-flow['consumed']-flow['dispatched']-flow['terminal'])
                require(residual==0,'daily firm flow')
                self.flow_rows.append(dict(day=self.day,firm_id=fid,commodity=good,opening=opening[fid][good],**flow,closing=self.stock[fid][good],residual=residual))
            if not node.active:continue
            for recipe in node.recipes:
                good=recipe.output_commodity;h=node.customer_histories[good]
                self.customer_rows.append(dict(day=self.day,supplier=fid,commodity=good,gross=h.gross,distinct_created=h.distinct_created,
                    distinct_unresolved=h.exposure(good),repeat_attempts=h.repeat_attempts,observed_rate=float(node.rates[good]),customer_pending=node.customer_pending[good]))
                self.firm_rows.append(dict(day=self.day,firm_id=fid,commodity=good,actual_output=plan[fid][good],
                    planned_output=next(p['planned_output'] for p in node.planning['plans'] if p['commodity']==good and p['production_day']==self.day),
                    stock=node.inventories[good],input_shortage=int(plan[fid][good]<next(p['planned_output'] for p in node.planning['plans'] if p['commodity']==good and p['production_day']==self.day))))
            for bucket in node.release.snapshot():self.allocation_rows.append(dict(day=self.day,firm_id=fid,**bucket))
        for rid in self.routes:
            pending,tr=self.balances(rid);r=self.routes[rid]
            self.route_rows.append(dict(day=self.day,route=rid,seller=r.seller_id,buyer=r.buyer_id,commodity=r.commodity,
                capacity=self.capacity(rid,self.day),arrived=arrivals[rid],dispatched=dispatched[rid],pending=pending,in_transit=tr,order_residual=self.route_order_residuals[rid]))
        row=dict(day=self.day,terminal_backlog=self.backlog,terminal_delivery=delivery,
                 coal_residual=res['coal'],steel_residual=res['steel'],machine_residual=res['machine'],
                 active_buckets=sum(len(n.release.active) for n in self.firms.values()),active_orders=sum(map(len,self.active_orders.values())),
                 active_shipments=len(self.arrivals),known_edges=sum(len(s) for n in self.firms.values() for s in n.knowledge.values()))
        row.update({f'{sid}_backlog':s['backlog'] for sid,s in sorted(self.sinks.items())})
        row.update({f'{fid}_{good}_stock':qty for fid in self.active_firms for good,qty in self.stock[fid].items()})
        self.rows.append(row);self.metric_rows.append(dict(day=self.day,**self.metrics,
            transport_slot_visits=sum(s.scan_visits for s in self.route_slots.values()),
            stock_commitment_entries=len(self.stock_commitments.entries),
            allocation_candidates=sum(n.release.allocation_candidates for n in self.firms.values()),
            archived_revisions=sum(len(n.release.revisions) for n in self.firms.values()),world_firms=len(self.firms),active_firms=len(self.active_firms)))
        if self.economics:
            price_started=time.perf_counter();self.economics.end_day()
            price_elapsed=time.perf_counter()-price_started
            self.timing['price_update_seconds']+=price_elapsed
            started+=price_elapsed
        self.timing['report_archive_seconds']+=time.perf_counter()-started
        return row


class SingleChainCompatibility(ExecutableSimulation):
    """Explicit old planning/admission boundary, same inherited world authority.

    FirmNode and Route are identity views over the old authority, not a second
    ledger. This control retains old steel S0 and old cross-firm planning solely
    to freeze the oracle; the formal network never uses either exception.
    """
    def __init__(self,case):
        super().__init__(case)
        self.firm_views={}
        for old,new,type_,good,inputs in (('A','A','RAW_SUPPLIER','coal',()),('B','B1','PROCESSOR','steel',(('coal',2),)),('C','C1','FINAL_PRODUCER','machine',(('steel',4),))):
            node=FirmNode(new,type_,new,(Recipe(new,good,1,inputs),),{good:self.config['production'][old]['capacity']},{},{},{})
            node.inventories=self.stock[old];self.firm_views[new]=node
        self.route_views={name:Route(dict(A='A',B='B1',C='C1').get(r['supplier'],r['supplier']),dict(B='B1',C='C1').get(r['buyer'],r['buyer']),r['commodity'],r['capacity'],r['lead_time']) for name,r in self.config['routes'].items()}
