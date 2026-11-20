"""Opt-in planning hooks; all material settlement and daily stage order inherited."""
from collections import defaultdict
from dataclasses import asdict
from fractions import Fraction
from pathlib import Path
from math import ceil
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "search_round4c"))
from search_simulation import SearchSimulation, InformationInbox, ranked_offers
from demand_planning import (Demand, DemandHistory, Recipe, RecipeGraph, ProductionPlan,
                             MaterialRequirement, Supply, PlanningAllocations,
                             daily_schedule, procurement_components)


class CurrentDemandFeed:
    """World fixture service; planner receives only records already emitted today."""
    def __init__(self, intervals): self._intervals = tuple(intervals)
    def receive(self, day):
        quantity = next(q for first,last,q in self._intervals if first <= day <= last)
        return Demand("terminal", "machine", day, quantity)


class PlanningSimulation(SearchSimulation):
    def __init__(self, case):
        self.planner = case["planner"]
        if self.planner not in ("P0", "P1", "P2", "P3"): raise ValueError("unknown planner")
        self.horizon = case.get("horizon", 10)
        self.demand_feed = CurrentDemandFeed(case["demand_intervals"])
        self.demand_history = DemandHistory(20)
        self.actual_demand_total = 0
        self.current_demand = 0; self.observed_rate = Fraction(0)
        self.demands = []; self.plans = []; self.plans_by_day = defaultdict(list)
        self.requirements_by_day = defaultdict(list)
        self.allocations_by_day = {}
        self.plan_deviations = []; self.deviations_by_day = defaultdict(list)
        self.coverage = PlanningAllocations()
        self.planning_rows = {}; self.components = {}
        self.edge_visits = self.supply_visits = 0
        self.supply_by_commodity = {}
        self.expected_order_arrival = {}
        self.purchase_links = defaultdict(dict)
        self.links_by_order = defaultdict(dict)
        super().__init__(case["config"], case["policy"], InformationInbox(case["information_events"]), case["result_limit"])
        p = self.config["production"]
        self.graph = RecipeGraph([Recipe("C","machine",1,(("steel",p["C"]["steel_per_machine"]),)),
                                  Recipe("B","steel",1,(("coal",p["B"]["coal_per_steel"]),))])

    def receive(self):
        # Existing step has advanced day, then receives cargo, then adds demand.
        fact = self.demand_feed.receive(self.day)
        self.config["daily_terminal_demand"] = fact.quantity
        self.actual_demand_total += fact.quantity; self.current_demand = fact.quantity
        self.demands.append(asdict(fact)); self.observed_rate = self.demand_history.observe(self.day, [fact])
        return super().receive()

    def check_accounts(self):
        # Adapt only the old constant-demand identity to actual received totals.
        # Physical account formulas and all settlement remain the original engine.
        current = self.config["daily_terminal_demand"]
        self.config["daily_terminal_demand"] = Fraction(self.actual_demand_total,self.day) if self.day else current
        try: result = super().check_accounts()
        finally: self.config["daily_terminal_demand"] = current
        assert self.actual_demand_total == self.backlog+self.cumulative["terminal_delivered"]
        return result

    def record_event(self, event, order, shipment=None, quantity=0):
        super().record_event(event, order, shipment, quantity)
        if event == "accepted":
            commitment = self.commitments[order.id]
            deadline = commitment.promised_dispatch_by_day
            lead = self.config["routes"][order.route]["lead_time"]
            self.expected_order_arrival[order.id] = None if deadline is None else deadline+lead
        elif event in ("arrived", "cancelled"):
            remaining=quantity
            for rid,q in list(self.links_by_order[order.id].items()):
                released=min(q,remaining)
                self.links_by_order[order.id][rid]-=released
                self.purchase_links[rid][order.id]-=released
                if not self.links_by_order[order.id][rid]:
                    del self.links_by_order[order.id][rid]; del self.purchase_links[rid][order.id]
                remaining-=released
                if not remaining: break

    def supplies(self):
        # Read live active orders, never self.orders/self.shipments archives.
        result = [Supply("stock:B:coal","B","coal",self.stock["B"]["coal"],self.day,"ON_HAND"),
                  Supply("stock:C:steel","C","steel",self.stock["C"]["steel"],self.day,"ON_HAND")]
        routes = list(self.supplier_routes.values())+["B_C"]
        for route in routes:
            spec = self.config["routes"][route]
            for order in self.active_orders[route].values():
                self.supply_visits += 1
                if order.pending_dispatch:
                    eta = self.expected_order_arrival.get(order.id)
                    # A breached dispatch promise no longer asserts future timing.
                    promise = self.commitments[order.id].promised_dispatch_by_day
                    if promise is None or self.day > promise: eta = None
                    result.append(Supply(f"pending:{order.id}",spec["buyer"],spec["commodity"],order.pending_dispatch,eta,"ACCEPTED_PENDING",order.id))
                for shipment in order.active_shipments.values():
                    self.supply_visits += 1
                    result.append(Supply(f"cargo:{shipment.id}",spec["buyer"],spec["commodity"],shipment.quantity,shipment.arrival_day,"IN_TRANSIT",order.id))
        return result

    def reconcile(self):
        self.coverage.reconcile(self.day, self.today_requirements, self.supplies(), timed=self.planner=="P3")

    def production_plan(self):
        physical = super().production_plan()
        # Raw sources retain their original stock-target extraction policy. Their
        # plans are observable too, without inventing demand-aware supplier ATP.
        for producer in self.world_ids:
            rule=self.config["production"][producer]
            desired=max(0,rule["coal_target"]-self.stock[producer]["coal"])
            q=physical[producer]
            source_plan=ProductionPlan(f"{producer}:coal:{self.day}",producer,"coal",self.day,self.day,
                desired,q,"LEGACY_SOURCE_STOCK_TARGET",1,max(0,desired-q))
            self.plans.append(asdict(source_plan)); self.plans_by_day[self.day].append(asdict(source_plan))
        if self.planner == "P0":
            self.today_requirements = []
            for producer,good in (("B","steel"),("C","machine")):
                plan = ProductionPlan(f"{producer}:{good}:{self.day}",producer,good,self.day,self.day,
                                      physical[producer],physical[producer],"LEGACY_REPLENISHMENT",1,0)
                self.plans_by_day[self.day].append(asdict(plan)); self.plans.append(asdict(plan))
            return physical
        p = self.config["production"]
        horizon = 1 if self.planner == "P1" else self.horizon
        committed = max(0,self.backlog-self.stock["C"]["machine"])
        desired = committed if self.planner == "P1" else max(0,self.backlog+self.observed_rate*horizon-self.stock["C"]["machine"])
        c_schedule = daily_schedule(desired,p["C"]["capacity"],horizon)
        desired_c_schedule = daily_schedule(desired,ceil(desired),horizon)
        basis = "CURRENT_COMMITTED" if self.planner=="P1" else "TRAILING_20_DAY_RUN_RATE"
        plans = []
        c_requirements = []
        for i,q in enumerate(c_schedule):
            date = self.day+i; pid = f"C:machine:{date}"
            unconstrained = desired_c_schedule[i]
            plans.append(ProductionPlan(pid,"C","machine",self.day,date,unconstrained,q,basis,horizon,max(0,unconstrained-q)))
            gross = self.graph.materials("machine",q,p["C"]["capacity"],self.stock["C"])["gross"]
            for g,qty in gross.items():
                c_requirements.append(MaterialRequirement(f"C:{g}:{date}","C",g,qty,date,pid)); self.edge_visits += 1
        self.coverage.reconcile(self.day,c_requirements,self.supplies(),timed=self.planner=="P3")
        # B must cover both downstream planned gaps and its already accepted steel
        # obligations. MAX combines overlapping obligations, never adds them twice.
        steel_gap = self.coverage.gap_for("C","steel")
        steel_pending = self.balances("B_C")[0]
        desired_b = max(steel_gap, max(0,steel_pending+p["B"]["steel_target"]-self.stock["B"]["steel"]))
        b_schedule = daily_schedule(desired_b,p["B"]["capacity"],horizon)
        desired_b_schedule = daily_schedule(desired_b,desired_b,horizon)
        # Need-by shifts backward by the actual B->C lead. Past production cannot
        # be planned retrospectively; missed deadlines are recorded below.
        late_steel = 0
        due_b = defaultdict(int)
        for r in c_requirements:
            gap = self.coverage.gap(r.requirement_id)
            date = r.need_by_day-self.config["routes"]["B_C"]["lead_time"]
            if date < self.day: late_steel += gap
            due_b[max(self.day,date)] += gap
        operating_today = max(0,steel_pending+p["B"]["steel_target"]-self.stock["B"]["steel"])
        b_schedule[0] = min(p["B"]["capacity"],max(b_schedule[0],due_b[self.day],operating_today))
        requirements = list(c_requirements)
        for i,q in enumerate(b_schedule):
            date=self.day+i; pid=f"B:steel:{date}"
            unconstrained=max(desired_b_schedule[i],due_b[self.day],operating_today) if i==0 else desired_b_schedule[i]
            plans.append(ProductionPlan(pid,"B","steel",self.day,date,unconstrained,q,basis,horizon,max(0,unconstrained-q)))
            gross=self.graph.materials("steel",q,p["B"]["capacity"],self.stock["B"])["gross"]
            for g,qty in gross.items():
                requirements.append(MaterialRequirement(f"B:{g}:{date}","B",g,qty,date,pid)); self.edge_visits += 1
        self.today_requirements = requirements
        self.reconcile()
        for plan in plans:
            record=asdict(plan); self.plans.append(record); self.plans_by_day[self.day].append(record)
        self.requirements_by_day[self.day] = self.coverage.snapshot()
        # Desired outputs remain separate; actual feasible quantities are passed
        # into the inherited stock-debit/production engine exactly once.
        physical["C"] = self.graph.materials("machine",c_schedule[0],p["C"]["capacity"],self.stock["C"])["input_feasible"]
        physical["B"] = self.graph.materials("steel",b_schedule[0],p["B"]["capacity"],self.stock["B"])["input_feasible"]
        self.planning_rows[self.day] = dict(observed_daily_demand=float(self.observed_rate),
                observed_history_days=len(self.demand_history.days), committed_backlog_at_plan=self.backlog,
                unconstrained_machine_requirement=float(desired), machine_plan_total=sum(c_schedule),
                machine_capacity_shortfall=max(0,ceil(desired)-p["C"]["capacity"]*horizon),
                steel_plan_total=sum(b_schedule), steel_capacity_shortfall=max(0,desired_b-p["B"]["capacity"]*horizon),
                missed_upstream_steel_deadline=late_steel, planning_horizon=horizon)
        return physical

    def produce(self, physical):
        super().produce(physical)
        for plan in self.plans_by_day[self.day]:
            due = plan["production_day"] == self.day
            actual = physical[plan["producer_id"]] if due else 0
            if not due: reason="PLAN_NOT_DUE"
            elif plan["producer_id"] in self.supplier_state and not self.supplier_state[plan["producer_id"]]["active"]:
                reason="OTHER_EXPLICIT_FIXTURE_REASON"
            elif plan["unmet_planned_output"]: reason="CAPACITY_LIMIT"
            elif actual < plan["capacity_limited_output"]: reason="INPUT_SHORTAGE"
            elif not plan["capacity_limited_output"]: reason="NO_DEMAND"
            else: reason="MATCHED"
            record=dict(day=self.day,plan_id=plan["plan_id"],production_day=plan["production_day"],
                        producer_id=plan["producer_id"],planned_output=plan["capacity_limited_output"],
                        actual_output=actual,reason=reason,unmet_planned_output=max(0,plan["capacity_limited_output"]-actual) if due else 0)
            self.plan_deviations.append(record); self.deviations_by_day[self.day].append(record)
        if self.planner!="P0":
            p=self.config["production"]
            self.coverage.settle(self.day,{("B","coal"):physical["B"]*p["B"]["coal_per_steel"],
                                           ("C","steel"):physical["C"]*p["C"]["steel_per_machine"]})

    def need_components(self, buyer):
        commodity=self.config["replenishment"][buyer]["commodity"]
        position=self.global_supply_position() if buyer=="B" else self.inventory_position("B_C")
        safety=max(0,self.config["replenishment"][buyer]["target"]-position)
        timely_gap=self.coverage.gap_for(buyer,commodity) if self.planner!="P0" else 0
        gap=sum(self.purchase_gap(r) for r in self.coverage.active.values()
                if (r.producer_id,r.commodity)==(buyer,commodity)) if self.planner!="P0" else 0
        gross=sum(r.required_qty for r in self.coverage.active.values() if (r.producer_id,r.commodity)==(buyer,commodity))
        # Live accepted quantities whose old requirement expired remain real
        # procurement exposure. Rebinding them as an untimed reservation prevents
        # rolling dates from purchasing the same finite plan portfolio again.
        # This does NOT assert that they can cover an early requirement deadline.
        portfolio_gap=max(0,gross-position)
        result=procurement_components(safety,min(gap,portfolio_gap))
        result.update(timely_uncovered_plan_qty=timely_gap,live_portfolio_position=position,
                      active_gross_requirement=gross,untimed_or_unassigned_reservation=max(0,gap-portfolio_gap))
        return result

    def purchase_gap(self, r):
        # An accepted but now untimed allocation is a live procurement reservation,
        # NOT timely coverage. It cannot cause another purchase of the same ID.
        linked=self.purchase_links[r.requirement_id]
        covered_by_order=defaultdict(int)
        for allocation in self.coverage.by_requirement[r.requirement_id]:
            if allocation["order_id"] is not None: covered_by_order[allocation["order_id"]]+=allocation["quantity"]
        held=sum(max(0,q-covered_by_order[oid]) for oid,q in linked.items())
        return max(0,self.coverage.gap(r.requirement_id)-held)

    def link_purchase(self, order_id, buyer, eta, quantity):
        good=self.config["replenishment"][buyer]["commodity"]
        for r in sorted(self.coverage.active.values(),key=lambda r:(r.need_by_day,r.requirement_id)):
            if (r.producer_id,r.commodity)!=(buyer,good): continue
            if self.planner=="P3" and r.need_by_day<eta: continue
            q=min(quantity,self.purchase_gap(r))
            if q:
                self.purchase_links[r.requirement_id][order_id]=q
                self.links_by_order[order_id][r.requirement_id]=q
                quantity-=q
            if not quantity: break

    def open_procurement_need(self):
        return self.need_components("B")["procurement_need_total"] if self.planner!="P0" else super().open_procurement_need()

    def eligible_need(self, buyer, eta):
        components=self.need_components(buyer)
        if self.planner!="P3": return components["procurement_need_total"]
        good=self.config["replenishment"][buyer]["commodity"]
        gaps=sum(self.purchase_gap(r) for r in self.coverage.active.values()
                 if (r.producer_id,r.commodity)==(buyer,good) and r.need_by_day>=eta)
        return min(components["procurement_need_total"],max(components["procurement_need_safety"],gaps))

    def procure(self,buyer,known_candidates):
        if self.planner=="P0": return super().procure(buyer,known_candidates)
        if buyer=="C":
            self.reconcile(); self.components["C"]=self.need_components("C")
            quantity=self.eligible_need("C",self.day+2+self.config["routes"]["B_C"]["lead_time"])
            if quantity and "B" in known_candidates:
                eta=self.day+2+self.config["routes"]["B_C"]["lead_time"]
                order=self.accept_order("B_C",quantity); self.link_purchase(order.id,"C",eta,quantity)
                self.reconcile(); return quantity,0
            return 0,quantity
        before_visits=self.directory.query_visits; before_results=self.directory.results_returned
        self.receive_information(); self.confirm_cancellations(); self.reconcile()
        for route in self.supplier_routes.values():
            for oid,q in self.classification(route)["overdue_orders"]:
                if oid not in self.breached:
                    self.breached.add(oid); self.totals[route]["breach_count"]+=1; self.totals[route]["breach_qty"]+=q
                    self._record_commitment_event("promise_breach",self.orders[oid],q)
        initial=self.open_procurement_need(); self.components["B"]=self.need_components("B")
        considered=sorted(self.known) if initial else []
        self.candidate_scans+=len(considered)
        offers=ranked_offers([self.offer(s) for s in considered]); today=[]
        for offer in offers:
            q=min(initial-sum(r["accepted_quantity"] for r in today),self.eligible_need("B",offer.expected_arrival_day))
            if q<=0: continue
            response=self.request(q,offer.supplier_id); today.append(response)
            if response["accepted_quantity"]: self.link_purchase(response["order_id"],"B",offer.expected_arrival_day,response["accepted_quantity"])
            self.reconcile()
        accepted=sum(r["accepted_quantity"] for r in today); assert accepted<=initial
        remaining=self.open_procurement_need()
        self.knowledge.consider(self.day,remaining,sum(o.max_acceptable_quantity for o in offers)>=initial)
        boundary=dict(day=self.day,initial_open_need=initial,accepted=accepted,final_open_need=remaining,
                      considered_supplier_ids=considered,queried_supplier_ids=[o.supplier_id for o in offers],
                      known_supplier_ids=sorted(self.known),request_ids=[r["request_id"] for r in today])
        self.boundaries.append(boundary); self.boundary_by_day[self.day]=boundary
        self.directory_daily[self.day]=dict(query_bucket_visits=self.directory.query_visits-before_visits,
                                          results_returned=self.directory.results_returned-before_results)
        self.decision_need=initial
        return accepted,remaining

    def observe_planning(self):
        record=dict(planner=self.planner,current_terminal_orders=self.current_demand,
                    cumulative_terminal_orders=self.actual_demand_total,observed_daily_demand=float(self.observed_rate),
                    active_demand_records=len(self.demand_history.days),planning_horizon=self.horizon,
                    recipe_graph_nodes=self.graph.nodes,recipe_graph_edges=self.graph.edges,
                    requirement_edges_traversed=self.edge_visits,planning_supply_visits=self.supply_visits,
                    allocation_scan_visits=self.coverage.visits,production_plan_records=len(self.plans),
                    active_production_plans=len(self.plans_by_day[self.day]),
                    active_requirements=len(self.coverage.active),requirement_allocations=len(self.coverage.allocations),
                    coal_plan_gap=self.coverage.gap_for("B","coal"),steel_plan_gap=self.coverage.gap_for("C","steel"))
        record.update(self.planning_rows.get(self.day,{}))
        for buyer in ("B","C"):
            for key,value in self.components.get(buyer,self.need_components(buyer)).items(): record[buyer+"_"+key]=value
        return record
