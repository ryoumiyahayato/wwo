"""Execution invariants, not assertions that a candidate reduces backlog."""
import unittest
from copy import deepcopy
from fractions import Fraction

from planning_release import ReleaseBook,need_components
from release_simulation import ExecutableSimulation
from run_executable_planning_experiment import (make_case,initialize,run_case,quote,interface_probes,partial_probe)
from run_demand_planning_experiment import run_case as old_run
from demand_planning import Supply
from planning_simulation import PlanningSimulation


class ReleaseTests(unittest.TestCase):
    def book(self,qty=80,date=20,day=10,klass="PROJECTED"):
        b=ReleaseBook(); b.revise(day,[("B","coal",date,klass,qty,"OBSERVED")],10); return b

    def test_x0_full_round5_controls(self):
        controls=(("normal",10),("wide",5),("wide",10),("wide",20),("mixed_lead",10),
                  ("step_up",10),("step_down",10),("spike",10),("insufficient",10),
                  ("factory_cap",10),("steel_cap",10),("recovery",10))
        for treatment,horizon in controls:
            case=make_case(treatment,"X0",horizon)
            old,rows=old_run(case); new,current=run_case(case)
            self.assertEqual(new.rows,old.rows); self.assertEqual(new.events,old.events)
            self.assertEqual(new.requests,old.requests); self.assertEqual(new.offers,old.offers)
            self.assertEqual(new.plans,old.plans); self.assertEqual(new.requirements_by_day,old.requirements_by_day)
            self.assertEqual([{k:r[k] for k in rows[0]} for r in current],rows)

    def test_firm_projected_dates_separate(self):
        sim,rows=run_case(make_case(policy="X1",days=30))
        for day,snapshot in sim.release.execution_snapshots.items():
            for b in snapshot:
                self.assertEqual(b["requirement_class"],"FIRM" if b["need_by_day"]<day+10 else "PROJECTED")
            self.assertEqual(len({(b['producer'],b['commodity'],b['need_by_day']) for b in snapshot}),len(snapshot))

    def test_projected_not_production_plan(self):
        sim,_=run_case(make_case(policy="X1",days=30))
        self.assertTrue(any(b["requirement_class"]=="PROJECTED" for b in sim.release.snapshot()))
        self.assertTrue(all(p["production_day"]<p["plan_day"]+10 for p in sim.plans))
        self.assertTrue(all(p["demand_basis"]!="PROJECTED" for p in sim.plans))

    def test_tail_cannot_be_consumed_as_actual_production(self):
        b=self.book(date=10)
        with self.assertRaises(AssertionError): b.consume(10,{("B","coal"):80})

    def test_stable_bucket_id_across_decision_days(self):
        b=self.book(date=120,day=110); key=next(iter(b.active))
        b.revise(111,[("B","coal",120,"PROJECTED",80,"OBSERVED")],10)
        self.assertEqual(list(b.active),[key]); self.assertEqual(b.active[key].created_day,110)
        self.assertEqual(b.active[key].revision_delta,0)

    def test_promotion_is_one_execution_responsibility(self):
        b=self.book(date=120,day=110)
        b.revise(111,[("B","coal",120,"FIRM",80,"CURRENT_PLAN")],10)
        self.assertEqual(len(b.active),1); state=next(iter(b.active.values()))
        self.assertEqual(state.previous_qty,80); self.assertEqual(state.revision_delta,0)
        self.assertEqual(state.created_day,110)

    def test_revision_increase_only_delta(self):
        b=self.book(); lot=Supply("accepted","B","coal",80,20,"ACCEPTED_PENDING",1)
        b.reconcile(10,[lot]); b.revise(11,[("B","coal",20,"PROJECTED",100,"OBSERVED")],10); b.reconcile(11,[lot])
        self.assertEqual(next(iter(b.active.values())).revision_delta,20)
        self.assertEqual(b.ceiling_room(("B","coal"),0),20); self.assertEqual(b.gap(next(iter(b.active))),20)

    def test_revision_decrease_does_not_destroy_supply(self):
        b=self.book(); lot=Supply("accepted","B","coal",80,20,"ACCEPTED_PENDING",1)
        b.reconcile(10,[lot]); b.revise(11,[("B","coal",20,"PROJECTED",50,"OBSERVED")],10); b.reconcile(11,[lot])
        self.assertEqual(lot.quantity,80); self.assertEqual(b.exposure(("B","coal")),80)
        self.assertEqual(b.excess(("B","coal")),30); self.assertEqual(b.ceiling_room(("B","coal"),0),0)

    def test_release_by_current_offer(self):
        b=self.book(); b.reconcile(10,[])
        eligible=b.executable(10,("B","coal"),quote("A",10,10))
        self.assertEqual(eligible,[("B:coal:20:PROJECTED",80)])
        self.assertEqual(b.release_by_day[10][-1]["release_by_day"],10)

    def test_future_release_waits(self):
        b=self.book(date=21); b.reconcile(10,[])
        self.assertEqual(b.executable(10,("B","coal"),quote("A",10,10)),[])

    def test_release_rejects_future_quote(self):
        b=self.book(); b.reconcile(10,[])
        with self.assertRaises(ValueError): b.executable(10,("B","coal"),quote("A",11,9))

    def test_supply_arrival_date_is_required(self):
        b=self.book(date=20); b.reconcile(10,[Supply("late","B","coal",80,21,"IN_TRANSIT",1)])
        self.assertEqual(b.gap(next(iter(b.active))),80)

    def test_forward_reassign_late_lot(self):
        b=ReleaseBook(); b.revise(10,[("B","coal",20,"PROJECTED",80,"OBSERVED"),("B","coal",23,"PROJECTED",80,"OBSERVED")],10)
        b.reconcile(10,[Supply("lot","B","coal",80,20,"ACCEPTED_PENDING",1)])
        b.reconcile(11,[Supply("lot","B","coal",80,23,"IN_TRANSIT",1)])
        self.assertEqual(b.gap("B:coal:20:PROJECTED"),80)
        self.assertEqual(b.gap("B:coal:23:PROJECTED"),0)
        self.assertEqual(b.forward_events[-1]["new_need_by"],23)

    def test_unknown_interval_retains_live_lineage(self):
        b=ReleaseBook(); b.revise(10,[("B","coal",20,"PROJECTED",80,"OBSERVED"),("B","coal",23,"PROJECTED",80,"OBSERVED")],10)
        b.reconcile(10,[Supply("pending","B","coal",80,20,"ACCEPTED_PENDING",1)])
        b.reconcile(11,[Supply("pending","B","coal",80,None,"ACCEPTED_PENDING",1)])
        b.reconcile(12,[Supply("cargo","B","coal",80,23,"IN_TRANSIT",1)])
        self.assertEqual(b.forward_events[-1]["old_need_by"],20)
        self.assertEqual(b.forward_events[-1]["new_need_by"],23)

    def test_supply_not_double_allocated(self):
        b=ReleaseBook(); b.revise(10,[("B","coal",20,"PROJECTED",80,"OBSERVED"),("B","coal",21,"PROJECTED",80,"OBSERVED")],10)
        b.reconcile(10,[Supply("lot","B","coal",80,20,"IN_TRANSIT",1)])
        self.assertEqual(sum(a["quantity"] for a in b.allocations),80)

    def test_unallocated_exposure_still_blocks_duplicate_buy(self):
        b=self.book(); b.reconcile(10,[Supply("unknown","B","coal",80,None,"ACCEPTED_PENDING",1)])
        self.assertEqual(b.gap(next(iter(b.active))),80)
        self.assertEqual(b.unallocated[0]["quantity"],80); self.assertEqual(b.ceiling_room(("B","coal"),0),0)

    def test_split_order_lots_do_not_report_each_other_as_late(self):
        b=ReleaseBook(); b.revise(10,[("B","coal",20,"PROJECTED",30,"OBSERVED"),("B","coal",23,"PROJECTED",50,"OBSERVED")],10)
        lots=[Supply("pending:1","B","coal",50,20,"ACCEPTED_PENDING",1),Supply("cargo:1","B","coal",30,18,"IN_TRANSIT",1)]
        b.reconcile(10,lots); b.reconcile(11,lots)
        self.assertEqual(b.forward_events,[])

    def test_x1_never_automatically_cancels_stale(self):
        sim,_=run_case(make_case("stale","X1",days=60))
        self.assertEqual(sim.orders[1].pending_dispatch,80)
        self.assertEqual(sim.cancel_history,[])

    def test_x2_cancels_only_overdue_unallocated(self):
        sim,_=run_case(make_case("stale","X2",days=20))
        for event in sim.disposition_events:
            if event['event']=='STALE_CANCEL_REQUESTED':
                promise=sim.commitments[event['old_order_id']].promised_dispatch_by_day
                self.assertGreater(event['day'],promise)
                self.assertEqual(event['source'],'A'); self.assertEqual(event['timely_alternative'],'D')
                self.assertGreater(event['unallocated_quantity'],0)
        self.assertEqual(sim.orders[1].cancelled,80)

    def test_no_positive_alternative_no_cancel(self):
        c=make_case("stale","X2",days=20); c['config']['routes']['D_B']['capacity']=0
        sim,_=run_case(c); self.assertFalse(sim.cancel_history)

    def test_promised_pending_is_not_stale(self):
        sim,_=run_case(make_case("stale","X2",days=2)); self.assertFalse(sim.cancel_history)

    def test_replacement_only_after_confirmation(self):
        p=partial_probe(); confirm=p['confirmed'][0]
        self.assertEqual(confirm['request_day'],3); self.assertEqual(confirm['confirm_day'],4)
        self.assertTrue(p['replacements'])
        self.assertTrue(all(r['day']>=confirm['confirm_day'] for r in p['replacements']))

    def test_partial_dispatch_only_fifty_replaced(self):
        p=partial_probe(); self.assertEqual(p['confirmed'][0]['confirmed_cancel_qty'],50)
        self.assertEqual(p['confirmed'][0]['no_longer_cancellable_qty'],30)
        self.assertEqual(sum(r['accepted'] for r in p['replacements']),50)
        self.assertTrue(all(r['supplier']=='D' for r in p['replacements']))
        self.assertEqual(p['original_order'],dict(quantity=80,pending=0,transit=0,delivered=30,cancelled=50))

    def test_transit_never_cancellable(self):
        sim=initialize(make_case("stale","X2")); sim.dispatch(); sim.check_accounts()
        self.assertEqual(sim.orders[1].in_transit,80)
        with self.assertRaises(ValueError): sim.request_cancellation(1,1)
        self.assertEqual(sim.orders[1].cancelled,0)

    def test_delivered_never_cancellable(self):
        sim=initialize(make_case("stale","X2")); sim.dispatch(); sim.step(); sim.step()
        self.assertEqual(sim.orders[1].delivered,80)
        with self.assertRaises(ValueError): sim.request_cancellation(1,1)

    def test_safety_and_plan_do_not_sum_twice(self):
        self.assertEqual(need_components(80,120,200)['procurement_need_total'],120)
        self.assertEqual(need_components(120,80,200)['procurement_need_total'],120)
        self.assertEqual(need_components(120,0,200)['procurement_need_total'],0)
        self.assertEqual(need_components(80,120,30)['procurement_need_total'],30)

    def test_rolling_six_hundred_day_bucket_stability(self):
        sim,rows=run_case(make_case(policy="X1"))
        for snapshot in sim.release.execution_snapshots.values():
            self.assertEqual(len({b['requirement_bucket_id'] for b in snapshot}),len(snapshot))
            self.assertEqual(len({(b['producer'],b['commodity'],b['need_by_day']) for b in snapshot}),len(snapshot))
        self.assertTrue(all(r['active_firm_buckets']<=20 and r['active_projected_buckets']<=12 for r in rows))
        self.assertLessEqual(max(r['global_supply_position'] for r in rows),16*60*2)

    def test_lead_nine_ten_eleven_boundaries(self):
        p=interface_probes()['horizon_boundary']
        self.assertEqual([x['visibility'] for x in p],[19,20,21])
        self.assertEqual([x['released_bucket']['requirement_class'] for x in p],['FIRM','PROJECTED','PROJECTED'])

    def test_future_demand_prefix(self):
        for policy in ('X0','X1','X2'):
            a,ra=run_case(make_case('normal',policy,days=105)); b,rb=run_case(make_case('step_up',policy,days=105))
            self.assertEqual(ra[:99],rb[:99])
            self.assertEqual({d:r for d,r in a.release.execution_snapshots.items() if d<=99},{d:r for d,r in b.release.execution_snapshots.items() if d<=99})
            self.assertEqual([r for r in a.release.revisions if r['day']<=99],[r for r in b.release.revisions if r['day']<=99])
            self.assertEqual([r for r in a.events if r['day']<=99],[r for r in b.events if r['day']<=99])
            self.assert_prefix_records(a,b)

    def assert_prefix_records(self,a,b):
        for name in ('plans','release_requests','disposition_events','events','requests'):
            left=getattr(a,name); right=getattr(b,name)
            field='plan_day' if name=='plans' else 'request_day' if name=='requests' else 'day'
            self.assertEqual([r for r in left if r[field]<=99],[r for r in right if r[field]<=99],name)
        for name in ('execution_snapshots','reconciliation_by_day','release_by_day','revisions_by_day'):
            left=getattr(a.release,name); right=getattr(b.release,name)
            self.assertEqual({d:r for d,r in left.items() if d<=99},{d:r for d,r in right.items() if d<=99},name)

    def test_future_lead_and_capacity_prefix(self):
        for policy in ('X0','X1','X2'):
            normal=make_case(policy=policy,days=105); fork=deepcopy(normal)
            fork['lead_events']=[dict(day=100,routes={'A_B':8,'D_B':12})]
            fork['config']['scenarios']={'experiment':{'A_B':[dict(first_day=100,last_day=600,capacity=0)]}}
            a,ra=run_case(normal); b,rb=run_case(fork)
            self.assertEqual(ra[:99],rb[:99]); self.assertEqual([r for r in a.quote_trace if r['offer_day']<=99],[r for r in b.quote_trace if r['offer_day']<=99])
            self.assertEqual([r for r in a.disposition_events if r['day']<=99],[r for r in b.disposition_events if r['day']<=99])
            self.assert_prefix_records(a,b)

    def test_actual_shipments_keep_eta_after_route_change(self):
        c=make_case(policy='X1',days=20); c['lead_events']=[dict(day=5,routes={'A_B':8})]
        sim,_=run_case(c)
        for shipment in sim.shipments:
            if shipment.dispatch_day<5 and shipment.route=='A_B': self.assertEqual(shipment.arrival_day,shipment.dispatch_day+2)

    def test_physical_insufficiency_is_not_repaired(self):
        for policy in ('X0','X1','X2'):
            sim,rows=run_case(make_case('insufficient',policy,days=120))
            self.assertGreater(sim.backlog,0)
            self.assertLessEqual(sum(r['A_B_dispatch']+r['D_B_dispatch'] for r in rows),60*120)

    def test_capacity_bottleneck_does_not_buy_infinite_raw(self):
        for t in ('factory_cap','steel_cap'):
            for policy in ('X1','X2'):
                sim,rows=run_case(make_case(t,policy,days=150))
                self.assertGreater(sim.backlog,0)
                self.assertTrue(all(r['production_C']<=sim.config['production']['C']['capacity'] for r in rows))
                self.assertLessEqual(max(r['global_supply_position'] for r in rows),max(320,sim.visibility*sim.config['production']['B']['capacity']*2))

    def test_goods_and_order_accounts(self):
        for policy in ('X0','X1','X2'):
            sim,rows=run_case(make_case('wide',policy,days=150))
            self.assertTrue(all(r[g+'_residual']==0 for r in rows for g in ('coal','steel','machine')))
            self.assertTrue(all(v==0 for v in sim.route_order_residuals.values()))

    def test_repeat_determinism(self):
        c=make_case('wide','X2',days=100); a,ra=run_case(c); b,rb=run_case(c)
        self.assertEqual(ra,rb); self.assertEqual(a.release.revisions,b.release.revisions)
        self.assertEqual(a.release.execution_snapshots,b.release.execution_snapshots)

    def test_observer_world_equivalence(self):
        c=make_case('stale','X2',days=30); a,_=run_case(c); b,_=run_case(c,False)
        self.assertEqual(a.events,b.events); self.assertEqual(a.rows,b.rows)

    def test_five_stage_release_dates(self):
        p=interface_probes()['five_stage_mixed_lead']['requirements']
        self.assertEqual([r['required_qty'] for r in p],[6,12,24,48])
        self.assertEqual([r['release_by_day'] for r in p],[46,40,35,29])
        self.assertTrue(all(r['release_by_day']<=r['need_by_day'] for r in p))

    def test_branch_shared_and_multiple_sink_regression(self):
        p=interface_probes()['branching_shared_sink_regression']
        self.assertEqual(p['shared_input']['allocated'],10); self.assertEqual(p['multiple_sinks']['aggregate'],16)
        self.assertEqual(len(p['branching']['requirements']),2)

    def test_multiple_lead_allocations(self):
        p=interface_probes()['multiple_leads']['allocations']
        self.assertEqual([(r['lot_id'],r['need_by_day']) for r in p],[('A',12),('D',15),('E',19),('F',23)])
        self.assertTrue(all(r['available_by_day']<=r['need_by_day'] for r in p))

    def test_archive_not_scanned_for_daily_decisions(self):
        class ArchiveList(list):
            def __iter__(self): raise AssertionError('planning archive scan')
        class ArchiveDict(dict):
            def __iter__(self): raise AssertionError('order archive scan')
            def values(self): raise AssertionError('order archive scan')
            def items(self): raise AssertionError('order archive scan')
        sim=initialize(make_case('stale','X2',days=12))
        sim.orders=ArchiveDict(sim.orders); sim.shipments=ArchiveList(sim.shipments)
        sim.plans=ArchiveList(sim.plans); sim.demands=ArchiveList(sim.demands); sim.release.revisions=ArchiveList()
        for _ in range(12): sim.step()
        sim.check_accounts()

    def test_material_settlement_and_step_still_inherited(self):
        self.assertIs(ExecutableSimulation.step,PlanningSimulation.step)
        self.assertIs(ExecutableSimulation.dispatch,PlanningSimulation.dispatch)

    def test_tail_generation_does_not_change_physical_plan(self):
        a=initialize(make_case(policy='X0')); b=initialize(make_case(policy='X1'))
        for sim in (a,b): sim.day=1; sim.backlog=10; sim.observed_rate=Fraction(10)
        before=deepcopy((b.stock,b.cumulative,b.shipments))
        pa=a.production_plan(); pb=b.production_plan()
        self.assertEqual(pa,pb); self.assertEqual(before,(b.stock,b.cumulative,b.shipments))
        self.assertEqual(a.plans,b.plans)

    def test_unknown_eta_never_timely_even_far_tail(self):
        b=self.book(date=100); b.reconcile(10,[Supply('unpromised','B','coal',80,None,'ACCEPTED_PENDING',1)])
        self.assertEqual(b.gap(next(iter(b.active))),80); self.assertEqual(b.exposure(('B','coal')),80)

    def test_closed_supply_lineage_pruned_on_receipt(self):
        b=self.book(); b.reconcile(10,[Supply('cargo','B','coal',80,20,'IN_TRANSIT',1)])
        self.assertTrue(b.last_timely_lineage)
        b.reconcile(20,[Supply('stock','B','coal',80,20,'ON_HAND')])
        self.assertFalse(b.last_timely_lineage)

    def test_no_duplicate_absolute_date_class(self):
        b=ReleaseBook()
        with self.assertRaises(ValueError): b.revise(10,[('B','coal',20,'FIRM',80,'p'),('B','coal',20,'PROJECTED',80,'p')],10)


if __name__=='__main__': unittest.main()
