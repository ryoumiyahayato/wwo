"""Shared-authority invariants; no assertion that C1 improves service."""
import unittest
from copy import deepcopy
from itertools import permutations
from firm_network import contention,CustomerRequestHistory,local_plan,StockCommitments
from network_simulation import NetworkSimulation,SingleChainCompatibility
from network_fixtures import make_network,compatibility_case
from run_multi_firm_experiment import run_case,intent,shared_probe
from run_executable_planning_experiment import run_case as old_run
from economy import Simulation
from commitment_adapter import CommitmentSimulation


class NetworkTests(unittest.TestCase):
    def requests(self,a=80,b=80):
        return [dict(buyer_id=buyer,requested_quantity=q,request_day=1,procurement_round=0,request_id=i) for i,(buyer,q) in enumerate((('B1',a),('B2',b)),1)]

    def test_single_chain_legacy_boundary_full_oracles(self):
        for policy in ('X0','X1'):
            case=compatibility_case(policy);old,_=old_run(case);new=SingleChainCompatibility(case)
            for _ in range(600):
                new.step();new.allocations_by_day[new.day]=list(new.coverage.allocations.values())
                new.observe_search();new.observe_planning();new.observe_release()
            self.assertEqual(old.rows,new.rows);self.assertEqual(old.events,new.events);self.assertEqual(old.requests,new.requests)
            self.assertEqual(old.plans,new.plans);self.assertEqual(old.release.execution_snapshots,new.release.execution_snapshots)
            self.assertIs(new.firm_views['B1'].inventories,new.stock['B'])

    def test_generic_recipe_hook_matches_old_physical_production(self):
        case=compatibility_case();old=SingleChainCompatibility(case);new=NetworkSimulation(make_network(scale='S1'))
        old.produce({'A':100,'B':40,'C':10,**{f:0 for f in old.world_ids if f!='A'}})
        new.produce({'A':{'coal':100},'B1':{'steel':40},'C1':{'machine':10}})
        for left,right in (('A','A'),('B','B1'),('C','C1')):self.assertEqual(old.stock[left],new.stock[right])
        self.assertEqual(old.cumulative,new.cumulative)

    def test_one_inventory_authority_and_independent_firms(self):
        sim=NetworkSimulation(make_network())
        self.assertIs(sim.firms['B1'].inventories,sim.stock['B1'])
        self.assertIsNot(sim.stock['B1'],sim.stock['B2'])
        old=sim.stock['B2']['coal'];sim.stock['B1']['coal']-=1;self.assertEqual(sim.stock['B2']['coal'],old)

    def test_route_explicit_seller_buyer_commodity(self):
        sim=NetworkSimulation(make_network())
        r=sim.routes['B2>C1:steel'];self.assertEqual((r.seller_id,r.buyer_id,r.commodity),('B2','C1','steel'))
        r=sim.routes['D>B1:coal'];self.assertEqual((r.seller_id,r.buyer_id,r.commodity),('D','B1','coal'))

    def test_common_fifo_and_order_authority_inherited(self):
        self.assertIs(NetworkSimulation.dispatch,Simulation.dispatch)
        self.assertIs(NetworkSimulation.accept_order,CommitmentSimulation.accept_order)
        self.assertIsInstance(NetworkSimulation(make_network()).stock_commitments,StockCommitments)

    def test_single_coal_buyer_degenerates_s2(self):
        sim=NetworkSimulation(make_network());sim.stock['A']['coal']=37
        r=sim.admit_round([intent(sim,'B1','A','coal',80)])[0]
        self.assertEqual(r['accepted_quantity'],37);self.assertEqual(r['rejected_quantity'],43)

    def test_single_steel_buyer_degenerates_s2(self):
        sim=NetworkSimulation(make_network());sim.stock['B1']['steel']=37
        r=sim.admit_round([intent(sim,'C1','B1','steel',80)])[0]
        self.assertEqual(r['accepted_quantity'],37);self.assertEqual(r['rejected_quantity'],43)

    def test_shared_coal_pool_not_sold_twice(self):
        for policy,quantities in (('C0',[80,20]),('C1',[50,50])):
            sim=NetworkSimulation(make_network(policy=policy));sim.stock['A']['coal']=100
            r=sim.admit_round([intent(sim,b,'A','coal',80) for b in ('B1','B2')])
            self.assertEqual([x['accepted_quantity'] for x in r],quantities)
            self.assertEqual(sim.stock_commitments.totals[('A','coal')],100)

    def test_shared_steel_pool_not_sold_twice(self):
        sim=NetworkSimulation(make_network(policy='C1'));sim.stock['B1']['steel']=100
        r=sim.admit_round([intent(sim,b,'B1','steel',80) for b in ('C1','C2')])
        self.assertEqual([x['accepted_quantity'] for x in r],[50,50])

    def test_quotes_are_not_reservations(self):
        sim=NetworkSimulation(make_network());sim.stock['A']['coal']=100
        self.assertEqual([sim.quote(b,'coal','A').max_acceptable_quantity for b in ('B1','B2')],[100,100])
        self.assertFalse(sim.stock_commitments.entries)

    def test_admission_rechecks_after_an_earlier_round(self):
        sim=NetworkSimulation(make_network());sim.stock['A']['coal']=100
        first=intent(sim,'B1','A','coal',80);second=intent(sim,'B2','A','coal',80)
        sim.admit_round([first]);r=sim.admit_round([second])[0]
        self.assertEqual(second['quoted_quantity'],100);self.assertEqual(r['accepted_quantity'],20)

    def test_c0_reverse_input_preserves_stable_policy(self):
        req=self.requests();self.assertEqual(contention(req,100,'C0'),contention(req[::-1],100,'C0'))
        self.assertEqual(contention(req,100,'C0'),dict(B1=80,B2=20))

    def test_c1_permutations_preserve_pro_rata(self):
        req=self.requests(83,31)
        for order in permutations(req):self.assertEqual(contention(list(order),77,'C1'),contention(req,77,'C1'))

    def test_largest_remainder_conserves_one_unit(self):
        self.assertEqual(contention(self.requests(1,1),1,'C1'),dict(B1=1,B2=0))

    def test_allocation_total_and_individual_caps(self):
        for policy in ('C0','C1'):
            for available in range(0,121):
                r=contention(self.requests(80,30),available,policy)
                self.assertLessEqual(sum(r.values()),available);self.assertLessEqual(r['B1'],80);self.assertLessEqual(r['B2'],30)

    def test_pro_rata_route_atp_caps_and_redistributes(self):
        r=contention(self.requests(),100,'C1',dict(B1=20,B2=80));self.assertEqual(r,dict(B1=20,B2=80))

    def test_single_buyer_c0_c1_same_atp(self):
        req=self.requests()[:1]
        self.assertEqual(contention(req,70,'C0',{'B1':40}),{'B1':40});self.assertEqual(contention(req,70,'C1',{'B1':40}),{'B1':40})

    def test_residual_uses_next_supplier_only(self):
        sim=run_case(make_network(days=30))
        for day in range(1,31):
            by_buyer={}
            for r in sim.requests_by_day[day]:
                key=(r['buyer_id'],r['commodity']);previous=by_buyer.get(key)
                if previous:self.assertNotEqual(previous['supplier_id'],r['supplier_id'])
                by_buyer[key]=r
        self.assertTrue(any(r['procurement_round']==1 for r in sim.requests))

    def test_daily_rounds_bounded_by_known_candidates(self):
        sim=run_case(make_network(days=50));self.assertLessEqual(sim.metrics['max_rounds'],2)
        self.assertTrue(all(r['procurement_round']<len(sim.firms[r['buyer_id']].knowledge[r['commodity']]) for r in sim.requests))

    def test_planning_states_independent(self):
        sim=NetworkSimulation(make_network());self.assertIsNot(sim.firms['B1'].release,sim.firms['B2'].release)
        self.assertIsNot(sim.firms['C1'].planning,sim.firms['C2'].planning)

    def test_histories_independent(self):
        sim=NetworkSimulation(make_network());self.assertIsNot(sim.firms['C1'].demand_histories['machine'],sim.firms['C2'].demand_histories['machine'])

    def test_unknown_supplier_query_is_rejected(self):
        sim=NetworkSimulation(make_network());sim.firms['C2'].knowledge['steel'].remove('B2')
        with self.assertRaises(ValueError):sim.quote('C2','steel','B2')
        with self.assertRaises(ValueError):sim.admit_round([dict(buyer_id='C2',supplier_id='B2',commodity='steel')])

    def test_buyer_specific_knowledge_no_registry_leak(self):
        case=make_network(days=30)
        next(f for f in case['firms'] if f['firm_id']=='C2')['knowledge']['steel']=['B1']
        sim=run_case(case)
        self.assertTrue(any(r['buyer_id']=='C1' and r['supplier_id']=='B2' for r in sim.quotes))
        self.assertFalse(any(r['buyer_id']=='C2' and r['supplier_id']=='B2' for r in sim.quotes))

    def test_rejected_request_is_observed_at_actual_supplier(self):
        sim=NetworkSimulation(make_network());sim.stock['B1']['steel']=0
        r=sim.admit_round([intent(sim,'C1','B1','steel',50)])[0]
        self.assertEqual(r['accepted_quantity'],0);self.assertEqual(sim.firms['B1'].customer_histories['steel'].gross,50)
        self.assertEqual(sim.firms['B2'].customer_histories['steel'].gross,0)

    def test_repeat_fifty_ten_times_is_not_five_hundred_distinct(self):
        h=CustomerRequestHistory();line=dict(need_id='same',commodity='steel',quantity=50,need_by_day=100)
        for day in range(1,11):h.observe(day,'C1',[line],{})
        self.assertEqual(h.gross,500);self.assertEqual(h.distinct_created,50);self.assertEqual(h.exposure('steel'),50)

    def test_supplier_revision_only_positive_delta(self):
        h=CustomerRequestHistory();line=dict(need_id='same',commodity='steel',quantity=80,need_by_day=100)
        h.observe(1,'C1',[line],{});h.observe(2,'C1',[dict(line,quantity=100)],{})
        self.assertEqual(h.distinct_created,100);self.assertEqual(h.new_by_day[2],20)

    def test_local_planner_has_no_peer_plan_or_backlog_channel(self):
        sim=NetworkSimulation(make_network());node=sim.firms['B1'];before=local_plan(node,0,10,{'coal':6})
        class Forbidden:
            def __getattribute__(self,name):raise AssertionError('peer plan read')
        sim.firms['C1'].planning=Forbidden();sim.firms['C1'].terminal_backlog=Forbidden()
        after=local_plan(node,0,10,{'coal':6});self.assertEqual(before,after)

    def test_request_facts_propagate_at_next_local_boundary(self):
        sim=NetworkSimulation(make_network());sim.day=1
        self.assertEqual(sim.firms['B1'].rates['steel'],0)
        sim.admit_round([intent(sim,'C1','B1','steel',20)])
        self.assertEqual(sim.firms['B1'].rates['steel'],0)
        sim.day=2
        # Histories normally observe every day; initialize prior zero day here.
        sim.firms['B1'].demand_histories['steel'].observe(1,[])
        h=sim.firms['B1'].customer_histories['steel'];observed=h.advance(2,'steel')
        self.assertEqual(observed,20)

    def test_firm_flow_residuals_all_zero(self):
        sim=run_case(make_network(days=100));self.assertTrue(all(r['residual']==0 for r in sim.flow_rows))

    def test_network_goods_residuals_all_zero(self):
        sim=run_case(make_network('coal_scarcity','C1',days=100))
        self.assertTrue(all(r[g+'_residual']==0 for r in sim.rows for g in ('coal','steel','machine')))

    def test_order_invariants_each_route(self):
        sim=run_case(make_network(days=100));self.assertTrue(all(r['order_residual']==0 for r in sim.route_rows))
        for order in sim.orders.values():order.check()

    def test_confirmed_cancel_releases_only_selected_buyer(self):
        for good in ('coal','steel'):
            p=shared_probe(good,'C1');self.assertEqual(p['first_order']['cancelled'],20);self.assertEqual(p['other_order']['cancelled'],0)
            self.assertEqual(p['other_order']['delivered'],50)

    def test_partial_old_transit_is_preserved(self):
        p=shared_probe('coal','C0',True)
        self.assertEqual(p['first_order'],dict(ordered=80,pending=0,transit=0,delivered=30,cancelled=50))
        self.assertEqual(p['cancellations'][-1]['no_longer_cancellable_qty'],30)
        self.assertEqual(sum(r['accepted_quantity'] for r in p['replacement']),50)

    def test_intermediate_partial_delivered_not_cancelled(self):
        p=shared_probe('steel','C1',True);self.assertEqual(p['first_order']['delivered'],30);self.assertEqual(p['first_order']['cancelled'],20)

    def test_live_transit_cannot_cancel(self):
        sim=NetworkSimulation(make_network());r=sim.admit_round([intent(sim,'B1','A','coal',20)])[0];sim.dispatch()
        self.assertEqual(sim.orders[r['order_id']].in_transit,20)
        with self.assertRaises(ValueError):sim.request_cancellation(r['order_id'],1)

    def test_unconfirmed_cancel_does_not_release_shared_stock(self):
        sim=NetworkSimulation(make_network());sim.stock['A']['coal']=100
        r=sim.admit_round([intent(sim,b,'A','coal',80) for b in ('B1','B2')])
        sim.request_cancellation(r[0]['order_id'],20)
        self.assertEqual(sim.stock_commitments.totals[('A','coal')],100)
        self.assertEqual(sim.admit_round([intent(sim,'B2','A','coal',1)])[0]['accepted_quantity'],0)

    def test_delivered_cannot_cancel(self):
        sim=NetworkSimulation(make_network());r=sim.admit_round([intent(sim,'B1','A','coal',20)])[0];sim.dispatch();sim.day=2;sim.receive()
        self.assertEqual(sim.orders[r['order_id']].delivered,20)
        with self.assertRaises(ValueError):sim.request_cancellation(r['order_id'],1)

    def test_bottleneck_caps_raw_exposure(self):
        sim=run_case(make_network('bottleneck','C1',days=150))
        for fid in ('B1','B2'):
            node=sim.firms[fid];self.assertLessEqual(node.release.exposure((fid,'coal')),max(160,node.release.visible((fid,'coal'))))
        self.assertGreater(sim.backlog,0)

    def assert_prefix(self,a,b):
        self.assertEqual(a.rows[:99],b.rows[:99])
        for name,field in (('plans','day'),('requests','request_day'),('commitment_events','day'),('quotes','day'),('customer_rows','day')):
            self.assertEqual([r for r in getattr(a,name) if r[field]<=99],[r for r in getattr(b,name) if r[field]<=99],name)

    def test_future_demand_ninety_nine_day_prefix(self):
        for policy in ('C0','C1'):
            self.assert_prefix(run_case(make_network(policy=policy,days=105)),run_case(make_network('step_up',policy,days=105)))

    def test_future_firm_shutdown_prefix(self):
        for policy in ('C0','C1'):
            self.assert_prefix(run_case(make_network(policy=policy,days=105)),run_case(make_network('shutdown',policy,days=105)))

    def test_future_route_capacity_prefix(self):
        a=make_network(policy='C1',days=105);b=deepcopy(a)
        b['route_events']={'A>B1:coal':[dict(first_day=100,last_day=600,capacity=0)]}
        self.assert_prefix(run_case(a),run_case(b))

    def test_sleeping_firms_outcome_and_matching_unchanged(self):
        for policy in ('C0','C1'):
            a=run_case(make_network(policy=policy,days=100));b=run_case(make_network(policy=policy,days=100,sleeping=100))
            self.assertEqual(a.rows,b.rows);self.assertEqual(a.requests,b.requests);self.assertEqual(a.quotes,b.quotes)
            self.assertEqual(a.metrics['offer_queries'],b.metrics['offer_queries']);self.assertGreater(b.metrics['world_ledger_firm_visits'],a.metrics['world_ledger_firm_visits'])

    def test_firm_insertion_order_invariance(self):
        for policy in ('C0','C1'):
            a=run_case(make_network('coal_scarcity',policy,days=100));b=run_case(make_network('coal_scarcity',policy,days=100,reverse=True))
            self.assertEqual(a.rows,b.rows);self.assertEqual(a.requests,b.requests);self.assertEqual(a.commitment_events,b.commitment_events)

    def test_bounded_degree_scale_no_all_pairs_queries(self):
        for scale in ('S1','S2','S5','S10'):
            sim=run_case(make_network(policy='C1',scale=scale,days=10))
            edges=sum(len(s) for n in sim.firms.values() for s in n.knowledge.values())
            self.assertLessEqual(max(len(s) for n in sim.firms.values() for s in n.knowledge.values()),2)
            self.assertEqual(sim.metrics['offer_queries'],2*edges*10)

    def test_decision_does_not_scan_archived_orders_or_plans(self):
        class NoIterList(list):
            def __iter__(self):raise AssertionError('archive scan')
        class NoIterDict(dict):
            def __iter__(self):raise AssertionError('archive scan')
            def values(self):raise AssertionError('archive scan')
            def items(self):raise AssertionError('archive scan')
        sim=NetworkSimulation(make_network())
        sim.orders=NoIterDict(sim.orders);sim.requests=NoIterList(sim.requests);sim.shipments=NoIterList(sim.shipments);sim.plans=NoIterList(sim.plans)
        for node in sim.firms.values():
            node.release.revisions=NoIterList()
            for history in node.customer_histories.values():history.seen_max=NoIterDict()
        for _ in range(12):sim.step()
        sim.check_accounts()

    def test_firm_type_is_not_algorithm_branch(self):
        a=make_network(days=50);b=deepcopy(a)
        for n in b['firms']:n['firm_type']='RENAMED_DIAGNOSTIC_TYPE'
        self.assertEqual(run_case(a).rows,run_case(b).rows)

    def test_preproduction_inputs_not_same_day_upstream_output(self):
        c=make_network(days=1)
        for stock in c['inventory'].values():stock['steel']=0
        sim=run_case(c);self.assertTrue(all(r['actual_output']==0 for r in sim.firm_rows if r['commodity']=='machine'))

    def test_supplier_capacity_loss_does_not_delete_orders(self):
        sim=run_case(make_network('shutdown','C1',days=150))
        self.assertGreater(sim.backlog,0)
        self.assertFalse(sim.cancelled_by_order_id)
        self.assertTrue(all(r['actual_output']==0 for r in sim.firm_rows if r['firm_id']=='B1' and r['day']>=100))

    def test_deterministic_generator(self):
        self.assertEqual(make_network(scale='S10'),make_network(scale='S10'))

    def test_repeat_replay_same_orders_and_materials(self):
        case=make_network('asymmetric_lead','C1',days=80);a=run_case(case);b=run_case(case)
        self.assertEqual(a.rows,b.rows);self.assertEqual(a.requests,b.requests);self.assertEqual(a.flow_rows,b.flow_rows)


if __name__=='__main__':unittest.main()
