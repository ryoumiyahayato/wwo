"""Independent execution sidecar on frozen Round5 P3; no new settlement engine."""
from collections import defaultdict
from dataclasses import asdict
from math import ceil
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent.parent/"planning_round5"))
from planning_simulation import PlanningSimulation, ranked_offers
from stock_admission import SupplierOffer
from planning_release import ReleaseBook,need_components


class ExecutableSimulation(PlanningSimulation):
    def __init__(self,case):
        self.execution_policy=case["execution_policy"]
        if self.execution_policy not in ("X0","X1","X2"): raise ValueError("unknown execution policy")
        self.release=ReleaseBook(); self.visibility=case["horizon"]
        self.quote_phase="MATCHING"; self.quote_trace=[]
        self._produced_day=-1; self.tail_backlog=0
        self.cancel_intents={}; self.release_tickets=[]; self.disposition_events=[]
        self.disposition_by_day=defaultdict(list); self.cancel_scan_visits=0
        self.original_requirement_dates={}; self.release_requests=[]
        self.current_quotes=[]; self.lead_events={r["day"]:r for r in case.get("lead_events",[])}
        super().__init__(case)

    def receive(self):
        # World fixture emits only today's route change; historical promises and
        # existing shipment ETA remain immutable. Planner cannot read this feed.
        event=self.lead_events.pop(self.day,None)
        if event:
            for route,lead in event["routes"].items(): self.config["routes"][route]["lead_time"]=lead
        return super().receive()

    def offer(self,supplier_id):
        offer=super().offer(supplier_id)
        if self.execution_policy!="X0":
            self.offers[-1]["phase"]=self.quote_phase
            self.quote_trace.append(dict(phase=self.quote_phase,**asdict(offer)))
        return offer

    def steel_quote(self):
        route=self.config["routes"]["B_C"]
        # C retains legacy accepted-order admission. The quote's timing is the
        # existing explicit promise; stale disposition uses only free current B
        # stock, not a forecast of future steel production.
        free=max(0,self.stock["B"]["steel"]-self.balances("B_C")[0])
        return SupplierOffer("B","steel",self.day,min(free,3*self.capacity("B_C",self.day)),
                             self.day+2,route["lead_time"],self.day+2+route["lead_time"],"CURRENT_STEEL_STOCK")

    def build_execution(self,quotes):
        conservative=max([q.expected_arrival_day-self.day for q in quotes]+[2+self.config["routes"]["B_C"]["lead_time"]])
        self.visibility=self.horizon+conservative
        records=[(r.producer_id,r.commodity,r.need_by_day,"FIRM",r.required_qty,"ROUND5_P3_FIRM")
                 for r in self.today_requirements if r.need_by_day>=self.day and
                 not (self._produced_day==self.day and r.need_by_day<=self.day)]
        p=self.config["production"]
        firm_machine=sum(r["capacity_limited_output"] for r in self.plans_by_day[self.day] if r["producer_id"]=="C")
        residual_backlog=max(0,self.tail_backlog-firm_machine)
        projected_machine=min(p["C"]["capacity"],ceil(self.observed_rate+residual_backlog/self.horizon))
        steel=self.graph.materials("machine",projected_machine,p["C"]["capacity"],{})["gross"]["steel"]
        projected_steel=min(p["B"]["capacity"],steel)
        coal=self.graph.materials("steel",projected_steel,p["B"]["capacity"],{})["gross"]["coal"]
        for date in range(self.day+self.horizon,self.day+self.visibility):
            for producer,commodity,qty in (("B","coal",coal),("C","steel",steel)):
                records.append((producer,commodity,date,"PROJECTED",qty,"OBSERVED_RATE_AND_UNCOVERED_BACKLOG_CAPACITY_BOUNDED"))
        self.release.revise(self.day,records,conservative)
        self.release.reconcile(self.day,self.supplies())

    def production_plan(self):
        physical=super().production_plan()
        if self.execution_policy!="X0":
            self.tail_backlog=self.backlog
            self.quote_phase="VISIBILITY_LEAD"
            quotes=[self.offer(s) for s in sorted(self.known)]
            self.quote_phase="MATCHING"; self.build_execution(quotes)
        return physical

    def produce(self,physical):
        super().produce(physical)
        if self.execution_policy!="X0":
            p=self.config["production"]
            self.release.consume(self.day,{("B","coal"):physical["B"]*p["B"]["coal_per_steel"],
                                           ("C","steel"):physical["C"]*p["C"]["steel_per_machine"]})
            self._produced_day=self.day
            self.release.reconcile(self.day,self.supplies())

    def record_event(self,event,order,shipment=None,quantity=0):
        super().record_event(event,order,shipment,quantity)
        if event=="accepted": self.original_requirement_dates[order.id]=self.expected_order_arrival.get(order.id)

    def log_disposition(self,**fields):
        event=dict(day=self.day,**fields)
        self.disposition_events.append(event); self.disposition_by_day[self.day].append(event)

    def request_cancellation(self,order_id,quantity):
        if self.execution_policy=="X0": return super().request_cancellation(order_id,quantity)
        order=self.orders[order_id]
        if type(quantity) is not int or quantity<=0 or quantity>order.pending_dispatch or order_id in self.cancel_requests:
            raise ValueError("only uncancelled live pending may be requested")
        if order.route not in self.supplier_routes.values() and order.route!="B_C": raise ValueError("unknown inbound route")
        record=dict(order_id=order_id,state="CANCEL_REQUESTED",request_day=self.day,
                    confirm_day=self.day+self.confirmation_delay,requested_cancel_qty=quantity,
                    pending_at_request=order.pending_dispatch,confirmed_cancel_qty=0,
                    no_longer_cancellable_qty=0,confirmation_delay=self.confirmation_delay)
        self.cancel_requests[order_id]=record; self.cancel_history.append(dict(record))
        self.cancel_by_day[self.day].append(dict(record))
        return record

    def confirm_cancellations(self):
        first=len(self.cancel_history)
        super().confirm_cancellations()  # Exact old partial-dispatch confirmation.
        if self.execution_policy=="X0": return
        for record in self.cancel_history[first:]:
            if record["state"]!="CANCEL_CONFIRMED": continue
            intent=self.cancel_intents.pop(record["order_id"],None)
            if intent:
                q=record["confirmed_cancel_qty"]
                if q:
                    self.release_tickets.append(dict(old_order_id=record["order_id"],pool=intent["pool"],
                        source=intent["source"],confirmed_quantity=q,remaining=q))
                self.log_disposition(event="EXPOSURE_RELEASE_CONFIRMED",old_order_id=record["order_id"],
                    confirmed_quantity=q,in_transit_preserved=record["no_longer_cancellable_qty"])

    def reserved(self):
        result=defaultdict(int)
        for intent in self.cancel_intents.values():
            for key,q in intent["reserved_buckets"].items():
                if key in self.release.active: result[key]+=q
        return result

    def find_stale(self,buyer,offers):
        if self.execution_policy!="X2": return
        pool=(buyer,self.config["replenishment"][buyer]["commodity"])
        for lot in list(self.release.unallocated):
            self.cancel_scan_visits+=1
            if (lot["producer"],lot["commodity"])!=pool or lot["kind"]!="ACCEPTED_PENDING": continue
            oid=lot["order_id"]; order=self.orders[oid]
            promise=self.commitments[oid].promised_dispatch_by_day
            if not order.pending_dispatch or (promise is not None and self.day<=promise) or oid in self.cancel_requests: continue
            if self.release.by_lot[lot["lot_id"]]: continue  # Could forward-cover visible demand.
            source=self.config["routes"][order.route]["supplier"]
            # Conservatively disposition toward a distinct already-known source;
            # FIFO and offer ranking are unchanged, and no new supplier is added.
            alternatives=[o for o in offers if o.supplier_id!=source and o.max_acceptable_quantity>0]
            for offer in alternatives:
                gaps=self.release.executable(self.day,pool,offer,self.reserved(),due_only=False)
                available=sum(q for _,q in gaps)
                q=min(lot["quantity"],order.pending_dispatch)
                hypothetical_room=max(0,max(self.config["replenishment"][buyer]["target"],self.release.visible(pool))-self.release.exposure(pool)+q)
                prospective=min(q,offer.max_acceptable_quantity,available,hypothetical_room)
                if not prospective: continue
                reservation={}; left=prospective
                for key,gap in gaps:
                    take=min(left,gap); reservation[key]=take; left-=take
                    if not left: break
                self.request_cancellation(oid,q)
                self.cancel_intents[oid]=dict(pool=pool,source=source,reserved_buckets=reservation,quantity=q)
                self.log_disposition(event="STALE_CANCEL_REQUESTED",old_order_id=oid,pending=q,
                    source=source,timely_alternative=offer.supplier_id,alternative_arrival=offer.expected_arrival_day,
                    unallocated_quantity=lot["quantity"],original_requirement_day=self.original_requirement_dates.get(oid))
                break

    def current_need(self,buyer,offers=None):
        pool=(buyer,self.config["replenishment"][buyer]["commodity"])
        offers=offers if offers is not None else self.current_quotes
        union={}
        for offer in offers:
            for key,q in self.release.executable(self.day,pool,offer,self.reserved(),record=False): union[key]=max(q,union.get(key,0))
        target=self.config["replenishment"][buyer]["target"]
        result=need_components(max(0,target-self.release.exposure(pool)),sum(union.values()),self.release.ceiling_room(pool,target))
        result.update(visible_requirement_exposure=self.release.visible(pool),existing_real_supply_exposure=self.release.exposure(pool),
                      excess_supply_exposure=self.release.excess(pool))
        return result

    def open_procurement_need(self):
        if self.execution_policy=="X0": return super().open_procurement_need()
        return self.current_need("B")["procurement_need_total"]

    def execute_buy(self,buyer,offer,quantity,action,old_order_id=None):
        pool=(buyer,self.config["replenishment"][buyer]["commodity"])
        before=self.release.exposure(pool)
        if buyer=="B":
            response=self.request(quantity,offer.supplier_id); accepted=response["accepted_quantity"]; oid=response["order_id"]
        else:
            order=self.accept_order("B_C",quantity); accepted=quantity; oid=order.id
        record=dict(day=self.day,buyer=buyer,supplier=offer.supplier_id,requested=quantity,accepted=accepted,
                    order_id=oid,action=action,old_order_id=old_order_id,offer_arrival=offer.expected_arrival_day,
                    exposure_before=before,visible_requirement_exposure=self.release.visible(pool))
        self.release_requests.append(record)
        self.release.reconcile(self.day,self.supplies())
        assert self.release.exposure(pool)-before==accepted
        assert self.release.exposure(pool)<=max(self.config["replenishment"][buyer]["target"],self.release.visible(pool))
        if action=="CONFIRMED_REPLACEMENT": self.log_disposition(event="REPLACEMENT_ACCEPTED",**{k:v for k,v in record.items() if k!="day"})
        return accepted

    def procure(self,buyer,known_candidates):
        if self.execution_policy=="X0": return super().procure(buyer,known_candidates)
        if buyer=="B":
            before_visits=self.directory.query_visits; before_results=self.directory.results_returned
            self.receive_information(); self.confirm_cancellations()
            offers=ranked_offers([self.offer(s) for s in sorted(self.known)])
            self.current_quotes=offers; self.build_execution(offers)
            for route in self.supplier_routes.values():
                for oid,q in self.classification(route)["overdue_orders"]:
                    if oid not in self.breached:
                        self.breached.add(oid); self.totals[route]["breach_count"]+=1; self.totals[route]["breach_qty"]+=q
                        self._record_commitment_event("promise_breach",self.orders[oid],q)
        else:
            offers=[self.steel_quote()] if "B" in known_candidates else []
            self.release.reconcile(self.day,self.supplies())
        pool=(buyer,self.config["replenishment"][buyer]["commodity"])
        initial=self.current_need(buyer,offers); self.components[buyer]=initial
        self.find_stale(buyer,offers)
        accepted=0
        for ticket in self.release_tickets:
            if ticket["pool"]!=pool or not ticket["remaining"]: continue
            for offer in offers:
                if offer.supplier_id==ticket["source"]: continue
                gaps=self.release.executable(self.day,pool,offer,self.reserved())
                q=min(ticket["remaining"],sum(n for _,n in gaps),self.release.ceiling_room(pool,self.config["replenishment"][buyer]["target"]))
                if q>0:
                    got=self.execute_buy(buyer,offer,q,"CONFIRMED_REPLACEMENT",ticket["old_order_id"])
                    ticket["remaining"]-=got; accepted+=got
                    assert ticket["remaining"]>=0
        self.release_tickets=[t for t in self.release_tickets if t["remaining"]]
        for offer in offers:
            gaps=self.release.executable(self.day,pool,offer,self.reserved())
            release_gap=sum(n for _,n in gaps)
            target=self.config["replenishment"][buyer]["target"]
            safety_gap=max(0,target-self.release.exposure(pool))
            q=need_components(safety_gap,release_gap,self.release.ceiling_room(pool,target))["procurement_need_total"]
            if q>0: accepted+=self.execute_buy(buyer,offer,q,"NEW_RELEASE")
        remaining=self.current_need(buyer,offers)["procurement_need_total"]
        if buyer=="B":
            considered=sorted(self.known); self.candidate_scans+=len(considered)
            self.knowledge.consider(self.day,remaining,sum(o.max_acceptable_quantity for o in offers)>=initial["procurement_need_total"])
            boundary=dict(day=self.day,initial_open_need=initial["procurement_need_total"],accepted=accepted,
                final_open_need=remaining,considered_supplier_ids=considered,queried_supplier_ids=[o.supplier_id for o in offers],
                known_supplier_ids=sorted(self.known),request_ids=[r["request_id"] for r in self.requests_by_day.get(self.day,[])])
            self.boundaries.append(boundary); self.boundary_by_day[self.day]=boundary
            self.directory_daily[self.day]=dict(query_bucket_visits=self.directory.query_visits-before_visits,
                                              results_returned=self.directory.results_returned-before_results)
            self.decision_need=initial["procurement_need_total"]
        return accepted,remaining

    def observe_release(self):
        firm=sum(b.requirement_class=="FIRM" for b in self.release.active.values())
        projected=sum(b.requirement_class=="PROJECTED" for b in self.release.active.values())
        row=dict(execution_policy=self.execution_policy,production_horizon=self.horizon,supply_visibility_horizon=self.visibility,
            active_firm_buckets=firm,active_projected_buckets=projected,unique_bucket_count=len(self.release.first_seen),
            unique_absolute_date_buckets=len(self.release.absolute_seen),
            revision_count=len(self.release.revisions),release_checks=self.release.release_checks,
            allocation_candidates=self.release.allocation_candidates,forward_reassignments=len(self.release.forward_events),
            unallocated_exposure=sum(l["quantity"] for l in self.release.unallocated),stale_cancellation_checks=self.cancel_scan_visits,
            cancellation_intents=len(self.cancel_intents),replacement_tickets=len(self.release_tickets),
            coal_unallocated_exposure=sum(l["quantity"] for l in self.release.unallocated if l["producer"]=="B"),
            coal_excess_exposure=self.release.excess(("B","coal")),steel_excess_exposure=self.release.excess(("C","steel")),
            coal_visible_requirement=self.release.visible(("B","coal")),steel_visible_requirement=self.release.visible(("C","steel")))
        self.release.execution_snapshots[self.day]=self.release.snapshot()
        self.release.reconciliation_by_day[self.day]=dict(
            boundary="last procurement reconciliation, before inherited dispatch",
            supplies=[asdict(s) for s in self.release.supplies.values()],
            allocations=[dict(a) for a in self.release.allocations],
            unallocated=[dict(a) for a in self.release.unallocated])
        return row
