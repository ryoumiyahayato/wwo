"""Correctness contracts; no assertion that a candidate improves service."""
import unittest
from copy import deepcopy
from dataclasses import asdict
from fractions import Fraction
from pathlib import Path
import sys

from demand_planning import *
from planning_simulation import PlanningSimulation
from run_demand_planning_experiment import make_case,run_case,probes
from run_supplier_search_experiment import make_case as old_case,run_case as old_run
from search_simulation import SearchSimulation


class PlanningTests(unittest.TestCase):
    def req(self,rid="r",quantity=10,date=3,producer="B",commodity="coal"):
        return MaterialRequirement(rid,producer,commodity,quantity,date,"plan")

    def test_p0_legacy_round4c(self):
        for treatment in ("normal","wide","insufficient"):
            current=make_case(treatment,"P0",days=120); old=old_case(treatment,"Q1" if treatment=="wide" else "Q0",10)
            old["days"]=120
            if treatment=="insufficient": old["config"]=deepcopy(current["config"])
            new,_=run_case(current); legacy,_=old_run(old)
            self.assertEqual(new.rows,legacy.rows); self.assertEqual(new.events,legacy.events)
            self.assertEqual(new.requests,legacy.requests); self.assertEqual(new.offers,legacy.offers)
            self.assertEqual(new.knowledge.events,legacy.knowledge.events)

    def test_p0_wide_600_exact_failure(self):
        new,_=run_case(make_case("wide","P0"))
        self.assertEqual(new.backlog,1282)  # Frozen control, not a candidate benefit test.

    def test_demand_fact_immutable(self):
        fact=Demand("sink","machine",1,10)
        history=DemandHistory(); history.observe(1,[fact])
        self.assertEqual(asdict(fact),dict(sink_id="sink",commodity="machine",received_day=1,quantity=10))
        with self.assertRaises(Exception): fact.quantity=0

    def test_plan_does_not_create_material(self):
        sim=PlanningSimulation(make_case(planner="P3")); sim.day=1; sim.backlog=10
        before=deepcopy((sim.stock,sim.cumulative,sim.shipments,sim.orders))
        sim.production_plan()
        self.assertEqual(before,(sim.stock,sim.cumulative,sim.shipments,sim.orders))

    def test_requirement_is_information(self):
        sim=PlanningSimulation(make_case(planner="P3")); before=deepcopy(sim.stock)
        r=self.req(); PlanningAllocations().reconcile(1,[r],[Supply("stock","B","coal",10,1,"ON_HAND")])
        self.assertEqual(sim.stock,before)

    def test_recipe_conversion(self):
        graph=RecipeGraph([Recipe("C","machine",2,(("steel",8),))])
        result=graph.materials("machine",5,15,{"steel":12})
        self.assertEqual(result["gross"],{"steel":20}); self.assertEqual(result["input_feasible"],3)

    def test_capacity_limit(self):
        graph=RecipeGraph([Recipe("C","machine",1,(("steel",4),))])
        result=graph.materials("machine",1000,15,{"steel":10000})
        self.assertEqual(result["constrained"],15); self.assertEqual(result["gross"],{"steel":60})
        self.assertEqual(sum(daily_schedule(1000,15,10)),150)

    def test_rounding_is_not_capacity_shortfall(self):
        sim=PlanningSimulation(make_case(planner="P2")); sim.day=1; sim.backlog=5
        sim.observed_rate=Fraction(10); sim.production_plan()
        c=[p for p in sim.plans if p["producer_id"]=="C"]
        self.assertEqual(sum(p["desired_output_qty"] for p in c),105)
        self.assertTrue(all(p["unmet_planned_output"]==0 for p in c))

    def test_p1_only_current_committed(self):
        sim=PlanningSimulation(make_case(planner="P1")); sim.day=1; sim.backlog=50
        sim.production_plan()
        c=next(r for r in sim.plans if r["producer_id"]=="C")
        self.assertEqual(c["capacity_limited_output"],15); self.assertEqual(c["planning_horizon"],1)

    def test_every_producer_has_a_daily_plan_record(self):
        for policy in ("P0","P1","P2","P3"):
            sim,_=run_case(make_case(planner=policy,days=2))
            for day in (1,2):
                due=[p for p in sim.plans_by_day[day] if p["production_day"]==day]
                self.assertEqual({p["producer_id"] for p in due},set(sim.config["production"]))
                self.assertEqual(len(due),len(sim.config["production"]))

    def test_p2_cold_start_actual_days(self):
        history=DemandHistory(20)
        self.assertEqual(history.observe(1,[Demand("s","g",1,7)]),7)
        self.assertEqual(history.observe(2,[Demand("s","g",2,11)]),9)
        self.assertEqual(len(history.days),2)

    def test_trailing_window_and_future_rejection(self):
        h=DemandHistory(20)
        for day in range(1,21): h.observe(day,[Demand("s","g",day,10)])
        self.assertEqual(h.observe(21,[Demand("s","g",21,15)]),Fraction(205,20))
        with self.assertRaises(ValueError): h.observe(22,[Demand("s","g",23,15)])
        with self.assertRaises(ValueError): h.observe(21,[])

    def test_eta_respected(self):
        book=PlanningAllocations(); r=self.req(date=3)
        gaps=book.reconcile(1,[r],[Supply("cargo","B","coal",10,4,"IN_TRANSIT")])
        self.assertEqual(gaps["r"],10)
        book.reconcile(1,[r],[Supply("cargo","B","coal",10,3,"IN_TRANSIT")])
        self.assertEqual(book.gap("r"),0)

    def test_long_cargo_cannot_cover_short_requirement(self):
        book=PlanningAllocations()
        reqs=[self.req("short",10,3),self.req("long",10,9)]
        book.reconcile(1,reqs,[Supply("lead8","B","coal",10,9,"IN_TRANSIT")])
        self.assertEqual((book.gap("short"),book.gap("long")),(10,0))

    def test_unknown_pending_eta_not_timely(self):
        b=PlanningAllocations(); b.reconcile(1,[self.req(date=99)],[Supply("pending","B","coal",10,None,"ACCEPTED_PENDING",1)])
        self.assertEqual(b.gap("r"),10)

    def test_scheduled_supply_before_is_not_total_position(self):
        supplies=[Supply("stock","B","coal",40,1,"ON_HAND"),Supply("short","B","coal",80,3,"IN_TRANSIT"),
                  Supply("long","B","coal",200,9,"IN_TRANSIT"),Supply("unknown","B","coal",50,None,"ACCEPTED_PENDING",1)]
        self.assertEqual(scheduled_supply_before(3,supplies,"B","coal"),120)
        self.assertEqual(scheduled_supply_before(9,supplies,"B","coal"),320)

    def test_cancelled_coverage_release(self):
        b=PlanningAllocations(); r=self.req()
        b.reconcile(1,[r],[Supply("pending","B","coal",10,3,"ACCEPTED_PENDING",1)])
        b.reconcile(2,[r],[])
        self.assertEqual(b.gap("r"),10); self.assertEqual(b.events_by_day[2][0]["released_quantity"],10)

    def test_receipt_changes_pipeline_to_stock(self):
        b=PlanningAllocations(); r=self.req()
        b.reconcile(1,[r],[Supply("cargo","B","coal",10,3,"IN_TRANSIT",1)])
        b.reconcile(3,[r],[Supply("stock","B","coal",10,3,"ON_HAND")])
        self.assertEqual(b.gap("r"),0); self.assertEqual(b.by_requirement["r"][0]["kind"],"ON_HAND")

    def test_transit_not_double_allocated(self):
        b=PlanningAllocations(); b.reconcile(1,[self.req("a"),self.req("b")],[Supply("cargo","B","coal",10,2,"IN_TRANSIT",1)])
        self.assertEqual(sum(a["quantity"] for a in b.allocations.values()),10)
        self.assertEqual(sum(b.gap(r) for r in ("a","b")),10)

    def test_stable_requirement_not_bought_twice(self):
        sim=PlanningSimulation(make_case(planner="P3")); sim.day=1
        r=self.req(date=10); sim.today_requirements=[r]; sim.reconcile()
        # No on-hand coverage for this explicit test requirement.
        sim.stock["B"]["coal"]=0; sim.reconcile()
        response=sim.request(10,"A"); sim.link_purchase(response["order_id"],"B",5,10); sim.reconcile()
        self.assertEqual(sim.purchase_gap(r),0)
        sim.day=4; sim.reconcile()  # Dispatch promise breached: no timely coverage.
        self.assertEqual(sim.coverage.gap("r"),10); self.assertEqual(sim.purchase_gap(r),0)

    def test_confirmed_cancel_releases_purchase_link(self):
        sim=PlanningSimulation(make_case(planner="P3")); sim.day=1; sim.stock["B"]["coal"]=0
        r=self.req(date=10); sim.today_requirements=[r]; sim.reconcile()
        response=sim.request(10,"A"); oid=response["order_id"]
        sim.link_purchase(oid,"B",5,10); sim.reconcile(); sim.request_cancellation(oid,10)
        self.assertEqual(sim.purchase_gap(r),0)
        sim.day=2; sim.confirm_cancellations(); sim.reconcile()
        self.assertEqual(sim.purchase_gap(r),10); self.assertEqual(sim.orders[oid].cancelled,10)

    def test_safety_and_plan_union(self):
        self.assertEqual(procurement_components(80,120),dict(procurement_need_safety=80,procurement_need_plan=40,procurement_need_total=120,uncovered_plan_qty=120))
        self.assertEqual(procurement_components(120,80)["procurement_need_total"],120)

    def test_plan_actual_independent(self):
        case=make_case(planner="P2",days=3); case["config"]["initial_inventory"]["C"]["steel"]=0
        sim,_=run_case(case)
        first=next(d for d in sim.plan_deviations if d["day"]==1 and d["producer_id"]=="C" and d["production_day"]==1)
        self.assertGreater(first["planned_output"],0); self.assertEqual(first["actual_output"],0)
        self.assertEqual(first["reason"],"INPUT_SHORTAGE")

    def test_insufficient_physical_supply(self):
        for p in ("P0","P1","P2","P3"):
            sim,rows=run_case(make_case("insufficient",p,days=150))
            self.assertLessEqual(sum(r["A_B_dispatch"]+r["D_B_dispatch"] for r in rows),150*60)
            self.assertLessEqual(sim.cumulative["machine_produced"],(sim.initial["coal"]+sim.cumulative["coal_mined"])/8+sim.initial["steel"]/4)
            self.assertGreater(sim.backlog,0)

    def test_factory_bottleneck_bounded_requirements(self):
        for p in ("P1","P2","P3"):
            sim,rows=run_case(make_case("factory_cap",p,days=150))
            self.assertLessEqual(max(r["production_C"] for r in rows),8)
            self.assertLessEqual(max(r["machine_plan_total"] for r in rows),8*(1 if p=="P1" else 10))
            self.assertGreater(sim.backlog,0)
            self.assertLessEqual(max(r["global_supply_position"] for r in rows),10*60*2+320)

    def test_intermediate_bottleneck_bounds_raw(self):
        for p in ("P1","P2","P3"):
            sim,rows=run_case(make_case("steel_cap",p,days=150))
            self.assertLessEqual(max(r["production_B"] for r in rows),30)
            self.assertLessEqual(max(r["steel_plan_total"] for r in rows),30*(1 if p=="P1" else 10))
            self.assertLessEqual(max(r["global_supply_position"] for r in rows),10*30*2+320)

    def test_rolling_plan_does_not_rebuy_expired_accepted_exposure(self):
        for treatment in ("wide","steel_cap","insufficient"):
            sim,rows=run_case(make_case(treatment,"P3",days=600))
            # A derived horizon/capacity bound, not an arbitrary order throttle.
            c_bound=max(sim.config["replenishment"]["C"]["target"],10*15*4)
            self.assertLessEqual(max(r["B_C_inventory_position"] for r in rows),c_bound)
            self.assertLessEqual(max(r["global_supply_position"] for r in rows),max(320,10*sim.config["production"]["B"]["capacity"]*2))

    def test_five_stage_graph(self): self.assertEqual([r["required_qty"] for r in probes()["five_stage"]["requirements"]],[6,12,24,48])
    def test_branching_graph(self): self.assertEqual(len(probes()["branching"]["requirements"]),2)
    def test_shared_input(self): self.assertEqual(probes()["shared_input"]["allocated"],10)
    def test_multiple_sinks(self): self.assertEqual(probes()["multiple_sinks"]["aggregate"],16)

    def test_future_demand_prefix_equivalence(self):
        for p in ("P0","P1","P2","P3"):
            a,ra=run_case(make_case("normal",p,days=105)); b,rb=run_case(make_case("step_up",p,days=105))
            self.assertEqual(ra[:99],rb[:99])
            for field in ("plans","plan_deviations","events","requests"):
                key="request_day" if field=="requests" else "plan_day" if field=="plans" else "day"
                self.assertEqual([r for r in getattr(a,field) if r[key]<=99],[r for r in getattr(b,field) if r[key]<=99])
            self.assertEqual({d:r for d,r in a.requirements_by_day.items() if d<=99},{d:r for d,r in b.requirements_by_day.items() if d<=99})

    def test_quantity_and_order_accounts(self):
        for p in ("P0","P1","P2","P3"):
            sim,rows=run_case(make_case("mixed_lead",p,days=100))
            self.assertTrue(all(r[g+"_residual"]==0 for r in rows for g in ("coal","steel","machine")))
            self.assertTrue(all(v==0 for v in sim.route_order_residuals.values()))

    def test_repeat_deterministic(self):
        case=make_case("wide","P3",days=100); a,ra=run_case(case); b,rb=run_case(case)
        self.assertEqual(ra,rb); self.assertEqual(a.plans,b.plans); self.assertEqual(a.coverage.history,b.coverage.history)

    def test_observer_does_not_affect_world(self):
        case=make_case("mixed_lead","P3",days=100); a,_=run_case(case); b,_=run_case(case,False)
        self.assertEqual(a.events,b.events); self.assertEqual(a.rows,b.rows)

    def test_original_stage_and_settlement_inherited(self):
        for method in ("step","dispatch","receive"):
            if method=="receive": continue  # Only current-demand fixture injection wraps receive.
            self.assertIs(getattr(PlanningSimulation,method),getattr(SearchSimulation,method))
        self.assertIs(PlanningSimulation.produce.__globals__["SearchSimulation"].produce,SearchSimulation.produce)

    def test_expired_requirement_does_not_destroy_stock(self):
        b=PlanningAllocations(); b.reconcile(1,[self.req(quantity=10,date=1)],[Supply("s","B","coal",10,1,"ON_HAND")])
        b.settle(1,{("B","coal"):4}); self.assertEqual(b.history[0]["expired_unfulfilled"],6)
        self.assertEqual(b.history[0]["consumed"],4)
        b.reconcile(2,[self.req(quantity=10,date=1)],[]); self.assertFalse(b.active)

    def test_planning_does_not_scan_archives(self):
        class NoIteration(dict):
            def __iter__(self): raise AssertionError("archive scan")
            def values(self): raise AssertionError("archive scan")
            def items(self): raise AssertionError("archive scan")
        sim=PlanningSimulation(make_case(planner="P3")); sim.orders=NoIteration(sim.orders)
        sim.day=1; sim.backlog=10; sim.production_plan()

    def test_graph_rejects_cycles(self):
        with self.assertRaises(ValueError): RecipeGraph([Recipe("a","x",1,(("y",1),)),Recipe("b","y",1,(("x",1),))])

    def test_requirement_dates_follow_recipe_stage_boundary(self):
        graph=RecipeGraph([Recipe("C","machine",1,(("steel",4),)),Recipe("B","steel",1,(("coal",2),))])
        records,_=graph.explode("machine",10,8,{"B":60,"C":15},{"C":0,"B":2})
        self.assertEqual([(r.commodity,r.need_by_day) for r in records],[("steel",8),("coal",6)])


if __name__=="__main__": unittest.main()
