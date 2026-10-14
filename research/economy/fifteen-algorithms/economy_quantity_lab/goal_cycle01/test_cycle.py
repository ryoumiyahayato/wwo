"""Correctness and information tests; no candidate improvement assertion."""
from copy import deepcopy
import heapq,json,tempfile,unittest
from pathlib import Path
from dataclasses import asdict
from cycle_fixtures import make_case,large_network,monetary
from network_simulation import NetworkSimulation
from run_multi_firm_experiment import intent
from cash import CashAccounts
from pricing import LocalWindow,update_price
from observation import StreamObserver,authoritative,physical
from offline_audit import audit


def simulate(case):
    s=NetworkSimulation(case);s.run();return s


def admitted(s,buyer='B1',seller='A',good='coal',quantity=80):
    return s.admit_round([intent(s,buyer,seller,good,quantity)])[0]

class PaymentTests(unittest.TestCase):
    def sim(self,balances=None,mode='N1',days=30):
        c=make_case(mode=mode,days=days)
        if balances:c['economics']['balances'].update(balances)
        return NetworkSimulation(c)

    def test_integer_money_rejects_bool_float_negative_string(self):
        for value in (True,1.0,-1,'1',None):
            with self.assertRaises(ValueError):CashAccounts({'A':value})
        cash=CashAccounts({'A':1,'B':0})
        for value in (True,1.0,-1,'1',0):
            with self.assertRaises(ValueError):cash.reserve('A',value)

    def test_negative_zero_and_invalid_posted_prices(self):
        for price in (True,0,-1,1.0,'100'):
            c=make_case();c['economics']['prices']['A:coal']=price
            with self.assertRaises(ValueError):NetworkSimulation(c)

    def test_account_identity_and_reserved_inside_balance(self):
        s=self.sim();a=s.economics.cash.accounts['B1'];self.assertIs(s.firms['B1'].cash_account,a)
        before=a.balance;admitted(s,quantity=80)
        self.assertEqual((a.balance,a.reserved,a.available),(before,8000,before-8000))

    def test_quote_neither_cash_nor_inventory_reserves(self):
        s=self.sim();before=asdict(s.economics.cash.accounts['B1'])
        s.quote('B1','coal','A');s.quote('B2','coal','A')
        self.assertEqual(before,asdict(s.economics.cash.accounts['B1']));self.assertFalse(s.stock_commitments.entries)

    def test_cash_insufficient_partial_accept_stock_sufficient(self):
        s=self.sim({'B1':3000});r=admitted(s,quantity=80)
        self.assertEqual(r['accepted_quantity'],30);self.assertEqual(r['financially_uncovered_need'],50)
        self.assertEqual(s.economics.cash.accounts['B1'].reserved,3000);s.check_accounts()

    def test_same_round_two_sellers_share_real_cash(self):
        s=self.sim({'B1':5000});rs=s.admit_round([intent(s,'B1','A','coal',40),intent(s,'B1','D','coal',40)])
        self.assertEqual([r['accepted_quantity'] for r in rs],[40,10]);self.assertEqual(s.economics.cash.accounts['B1'].available,0)
        self.assertEqual(sum(r['financially_uncovered_need'] for r in rs),30);s.check_accounts()

    def test_same_buyer_two_inputs_share_cash(self):
        from firm_network import Route
        c=make_case(mode='N1');c['economics']['balances']['C1']=4500
        node=next(f for f in c['firms'] if f['firm_id']=='C1');node['knowledge']['coal']=['A'];node['input_targets']['coal']=20
        c['economics']['limits']['C1']['coal']=400;c['routes'].append(asdict(Route('A','C1','coal',100,2)))
        s=NetworkSimulation(c)
        rs=s.admit_round([intent(s,'C1','A','coal',30),intent(s,'C1','B1','steel',20)])
        self.assertEqual([r['accepted_quantity'] for r in rs],[30,5]);self.assertEqual(s.economics.cash.accounts['C1'].reserved,4500);s.check_accounts()

    def test_dispatch_does_not_pay(self):
        s=self.sim();r=admitted(s);a=s.economics.cash.accounts['B1'];before=a.balance
        s.dispatch();self.assertEqual((a.balance,a.reserved),(before,8000));s.check_accounts()

    def test_arrival_thirty_then_confirm_cancel_fifty(self):
        s=self.sim();s.config['routes']['A>B1:coal']['capacity']=30
        r=admitted(s);oid=r['order_id'];s.dispatch();s.day=2;s.receive()
        self.assertEqual(s.orders[oid].delivered,30);s.request_cancellation(oid,50)
        a=s.economics.cash.accounts['B1'];self.assertEqual(a.reserved,5000)
        s.day=3;s.confirm_cancellations();self.assertEqual(a.reserved,0);s.check_accounts()
        f=s.economics.financial[oid];self.assertEqual((f['original_value'],f['paid_value'],f['cancelled_value']),(8000,3000,5000))

    def test_waiting_cancel_dispatch_thirty_releases_only_fifty(self):
        s=self.sim();s.config['routes']['A>B1:coal']['capacity']=30
        r=admitted(s);oid=r['order_id'];s.request_cancellation(oid,80);self.assertEqual(s.economics.cash.accounts['B1'].reserved,8000)
        s.dispatch();s.day=1;s.confirm_cancellations();self.assertEqual(s.economics.cash.accounts['B1'].reserved,3000)
        s.day=2;s.receive();s.check_accounts();self.assertEqual(s.economics.cash.accounts['B1'].reserved,0)

    def test_old_order_price_locked(self):
        s=self.sim();r=admitted(s,quantity=30);s.economics.prices[('A','coal')]=250
        s.dispatch();s.day=2;s.receive();f=s.economics.financial[r['order_id']]
        self.assertEqual((f['locked_price'],f['paid_value']),(100,3000));s.check_accounts()

    def test_duplicate_arrival_scheduler_cannot_repay(self):
        s=self.sim();admitted(s,quantity=30);s.dispatch();cargo=s.shipments[0];s.day=2;s.receive()
        cash=deepcopy(s.economics.cash.accounts);stock=deepcopy(s.stock)
        heapq.heappush(s.arrivals,(cargo.arrival_day,cargo.id,cargo))
        with self.assertRaises(AssertionError):s.receive()
        self.assertEqual(cash,s.economics.cash.accounts);self.assertEqual(stock,s.stock)

    def test_each_transaction_stage_fully_rolls_back(self):
        for stage in ('stock','cash','slots','order'):
            with self.subTest(stage=stage):
                s=self.sim();s.economics.failpoint=stage
                before=deepcopy(authoritative(s));records=deepcopy(s.economics.records)
                with self.assertRaises(RuntimeError):admitted(s)
                self.assertEqual(before,authoritative(s));self.assertEqual(records,s.economics.records)
                self.assertFalse(s.orders);self.assertFalse(s.stock_commitments.entries)
                self.assertFalse(s.route_slots['A>B1:coal'].allocations);self.assertFalse(s.commitments)
                self.assertFalse(s.expected_arrival);self.assertFalse(s.events);self.assertFalse(s.commitment_events)
                self.assertFalse(s.dispatch_queues['A>B1:coal']);s.check_accounts()
                s.economics.failpoint=None;self.assertEqual(admitted(s)['order_id'],1)

    def test_terminal_insufficient_no_fictitious_revenue(self):
        s=self.sim({'external:T1':2000,'external:T2':0});s.step()
        self.assertEqual((s.sinks['T1']['delivered'],s.sinks['T2']['delivered']),(1,0))
        self.assertEqual(s.economics.cash.receipts['C1'],2000);self.assertEqual(s.economics.cash.receipts['C2'],0)
        self.assertEqual(s.stock['C1']['machine'],s.day_flow['C1']['machine']['produced']-1)
        self.assertEqual(s.stock['C2']['machine'],s.day_flow['C2']['machine']['produced']);s.check_accounts()

    def test_multi_firm_e2e_material_and_money(self):
        s=simulate(make_case(days=100,mode='N1'));s.check_accounts()
        self.assertEqual(s.cumulative['terminal_delivered'],1000);self.assertGreater(s.economics.closed['orders'],0)
        self.assertEqual(sum(a.balance for a in s.economics.cash.accounts.values()),sum(s.economics.cash.initial.values()))

class ControlsTests(unittest.TestCase):
    def test_n1_original_physical_rows_orders_requests_equal_n0(self):
        for treatment in ('normal','coal_scarcity','recovery','asymmetric_lead'):
            a=simulate(make_case(treatment,'N0',100));b=simulate(make_case(treatment,'N1',100))
            self.assertEqual(a.rows,b.rows);self.assertEqual(a.events,b.events)
            keys=set(a.requests[0])
            self.assertEqual(a.requests,[{k:r[k] for k in keys} for r in b.requests])

    def test_nonbinding_more_cash_same_physical_path(self):
        a=simulate(make_case(days=100));b=simulate(make_case(days=100,factor=8))
        self.assertEqual(a.rows,b.rows);self.assertEqual(a.events,b.events)
        self.assertEqual(a.economics.rejections['CASH'],0);self.assertEqual(a.economics.rejections['TERMINAL_CASH'],0)

    def test_cheapest_equivalent_source_changes_route(self):
        a=simulate(make_case(days=20,mode='N1'));b=simulate(make_case(days=20,mode='N2'))
        def first(s):return next(r['supplier_id'] for r in s.requests if r['buyer_id']=='C1' and r['accepted_quantity'])
        self.assertEqual(first(a),'B1');self.assertEqual(first(b),'B2')

    def test_above_limit_rejected_need_not_disappeared(self):
        c=make_case(mode='N1');c['economics']['limits']['B1']['coal']=99;s=NetworkSimulation(c)
        r=admitted(s);self.assertEqual(r['accepted_quantity'],0);self.assertEqual(r['price_uncovered_need'],80);self.assertFalse(s.orders)
        s.run(20);self.assertGreater(s.firms['B1'].procurement['coal']['procurement_need_total'],0)

    def test_low_price_long_lead_not_timely(self):
        s=NetworkSimulation(make_case('asymmetric_lead',days=20));s.day=1
        n=s.firms['C1'];n.release.revise(1,[('C1','steel',4,'FIRM',20,'TEST')],10);s.reconcile_firm('C1')
        s.stock['C1']['steel']=0;s.reconcile_firm('C1')
        cheap=s.quote('C1','steel','B2');expensive=s.quote('C1','steel','B1')
        self.assertIsNone(s.procurement_intent('C1','steel',cheap,0));self.assertIsNotNone(s.procurement_intent('C1','steel',expensive,1))

    def test_remaining_cash_and_need_after_earlier_acceptance(self):
        s=simulate(make_case(days=30,mode='N2'))
        for day,rs in s.requests_by_day.items():
            seen={}
            for r in rs:
                key=(r['buyer_id'],r['commodity']);old=seen.get(key)
                if old:
                    previous={line['need_id']:line['quantity'] for line in old['lines']}
                    for line in r['lines']:
                        if line['need_id'] in previous:
                            self.assertLessEqual(line['quantity'],previous[line['need_id']]-old['accepted_lines'].get(line['need_id'],0))
                seen[key]=r

    def test_financial_uncovered_no_borrowing(self):
        c=make_case();c['economics']['balances']['B1']=0;s=NetworkSimulation(c)
        r=admitted(s);self.assertEqual(r['financially_uncovered_need'],80);self.assertEqual(r['accepted_quantity'],0)
        s.run(20);self.assertGreater(s.economics.rejections['CASH'],0)
        self.assertGreaterEqual(s.economics.cash.accounts['B1'].balance,0)

    def test_nominal_unit_scaling_physical_invariance(self):
        for mode in ('N2','N3'):
            a=simulate(make_case(days=100,mode=mode));b=simulate(make_case(days=100,mode=mode,unit=10))
            self.assertEqual(a.rows,b.rows);self.assertEqual(a.events,b.events)
            self.assertEqual({k:p*10 for k,p in a.economics.prices.items()},b.economics.prices)

    def test_reversed_firm_route_request_insertion(self):
        a=simulate(make_case(days=100,mode='N3'));b=simulate(make_case(days=100,mode='N3',reverse=True))
        self.assertEqual(a.rows,b.rows);self.assertEqual(a.requests,b.requests);self.assertEqual(authoritative(a),authoritative(b))
        c=NetworkSimulation(make_case());d=NetworkSimulation(make_case())
        req=[intent(c,x,'A','coal',80) for x in ('B1','B2')]
        self.assertEqual(c.admit_round(deepcopy(req)),d.admit_round(deepcopy(req[::-1])))

    def test_unknown_supplier_no_price_query(self):
        c=make_case()
        for f in c['firms']:
            if 'steel' in f['knowledge']:f['knowledge']['steel']=['B1']
        s=NetworkSimulation(c)
        class Guard(dict):
            def __getitem__(self,key):
                if key==('B2','steel'):raise AssertionError('unknown price read')
                return super().__getitem__(key)
        s.economics.prices=Guard(s.economics.prices)
        with self.assertRaises(ValueError):s.quote('C1','steel','B2')
        s.run(20);self.assertFalse(any(r['buyer_id']=='C1' and r['supplier_id']=='B2' for r in s.quotes))

    def test_future_demand_price_capacity_prefix(self):
        a=make_case(days=120,mode='N3');b=deepcopy(a)
        b['sinks'][0]['demand_intervals']=[[1,99,5],[100,10000,15]]
        b['capacity_events']=[dict(day=100,firm_id='B1',commodity='steel',capacity=0)]
        b['route_events']['A>B1:coal']=[dict(first_day=100,last_day=10000,capacity=0)]
        b['economics']['price_events']=[dict(day=100,seller='A',commodity='coal',price=400)]
        x=NetworkSimulation(a);y=NetworkSimulation(b)
        for _ in range(99):x.step();y.step()
        self.assertEqual(x.rows,y.rows);self.assertEqual(x.requests,y.requests);self.assertEqual(authoritative(x),authoritative(y))

    def test_feedback_disabled_degrades_to_fixed(self):
        a=simulate(make_case(days=100,mode='N2'));b=simulate(make_case(days=100,mode='N3',feedback=False))
        self.assertEqual(a.rows,b.rows);self.assertEqual(authoritative(a),authoritative(b))

    def test_finance_relief_cannot_remove_sink_topology_bottleneck(self):
        a=simulate(make_case('step_up','N2',150));b=simulate(make_case('step_up','N2',150,factor=10))
        self.assertEqual(a.rows,b.rows);self.assertGreater(a.sinks['T1']['backlog'],0);self.assertEqual(a.economics.rejections['CASH'],0)

class FeedbackTests(unittest.TestCase):
    def test_pure_signature_local_only(self):
        import inspect
        self.assertEqual(list(inspect.signature(update_price).parameters),['current','initial','tick','window'])
        w=LocalWindow(0,100,50,0,0,1);self.assertEqual(update_price(100,100,1,w)['price'],102)

    def test_no_actual_supply_cannot_create_goods(self):
        c=make_case(mode='N3',days=30)
        for f in c['firms']:
            for good in f['capacities']:f['capacities'][good]=0
        for stock in c['inventory'].values():
            for g in stock:stock[g]=0
        s=simulate(c);self.assertEqual(s.cumulative['terminal_delivered'],0);self.assertEqual(s.economics.prices,s.economics.initial_prices)

    def test_idle_stock_cannot_label_sustained_physical_shortage(self):
        r=update_price(100,100,1,LocalWindow(1000,10,500,0,0,1))
        self.assertEqual((r['price'],r['reason']),(98,'IDLE_STOCK'))

    def test_retries_do_not_inflate_local_signal(self):
        s=NetworkSimulation(make_case(mode='N3'));s.stock['A']['coal']=0
        for _ in range(10):admitted(s,quantity=50)
        w=s.economics.windows[('A','coal')]
        self.assertEqual(len(w['interest']),1);self.assertEqual(sum(v['PHYSICAL'] for v in w['interest'].values()),50)

    def test_no_new_information_hold(self):
        r=update_price(100,100,1,LocalWindow(0,20,200,0,0,0));self.assertEqual(r['price'],100)

    def test_cash_rejection_with_stock_not_mechanically_raise(self):
        r=update_price(100,100,1,LocalWindow(1,30,100,0,80,1));self.assertLess(r['price'],100)

    def test_step_clamp_tick_positive(self):
        for price in range(25,401):
            for w in (LocalWindow(0,1,2,0,0,1),LocalWindow(100,1,0,0,0,1)):
                r=update_price(price,100,1,w);self.assertGreaterEqual(r['price'],25);self.assertLessEqual(r['price'],400)
                self.assertLessEqual(abs(r['price']-price)*100,price*2)
        self.assertEqual(update_price(25,100,1,LocalWindow(100,1,0,0,0,1))['lower_hit'],True)

    def test_seven_day_update_next_day_and_old_order_lock(self):
        s=NetworkSimulation(make_case(mode='N3',days=20));initial=dict(s.economics.prices)
        for _ in range(7):s.step()
        self.assertEqual(s.economics.prices,initial);self.assertTrue(s.economics.pending_prices)
        locked={oid:f['locked_price'] for oid,f in s.economics.financial.items()};s.step()
        self.assertNotEqual(s.economics.prices,initial)
        self.assertTrue(all(s.economics.financial[oid]['locked_price']==p for oid,p in locked.items()))

    def test_price_observer_switch_cannot_change_behavior(self):
        a=simulate(make_case(mode='N3',days=100));b=simulate(make_case(mode='N3',days=100,observer=False))
        self.assertEqual(a.rows,b.rows);self.assertEqual(authoritative(a),authoritative(b));self.assertFalse(b.economics.price_records)

class StreamingTests(unittest.TestCase):
    def test_scale_does_not_increase_per_firm_funding(self):
        small=make_case(scale='S10');large=make_case(scale='S20')
        for key,value in small['economics']['balances'].items():
            self.assertEqual(value,large['economics']['balances'][key])

    def test_generated_stale_same_day_need_rechecked_at_acceptance(self):
        c=make_case(mode='N1');c['inventory']['C1']['steel']=0
        s=NetworkSimulation(c);s.day=1
        s.firms['C1'].release.revise(1,[('C1','steel',4,'FIRM',20,'TEST')],3);s.reconcile_firm('C1')
        attempts=[s.procurement_intent('C1','steel',s.quote('C1','steel',seller),0) for seller in ('B1','B2')]
        result=s.admit_round(attempts)
        self.assertEqual([r['accepted_quantity'] for r in result],[20,0])
        self.assertGreater(result[1]['rejections']['STALE_NEED'],0);s.check_accounts()

    def test_full_compact_off_authority_identical(self):
        summaries=[]
        with tempfile.TemporaryDirectory() as tmp:
            for mode in ('full','compact','off'):
                s=NetworkSimulation(make_case(mode='N3',days=100));o=StreamObserver(s,Path(tmp)/mode,mode)
                for _ in range(100):s.step();o.finish_day()
                result=o.close();summaries.append(result);self.assertEqual(audit(Path(tmp)/mode)['status'],'PASS')
                if mode!='full':self.assertFalse(s.plans.tail);self.assertLess(dict.__len__(s.orders),50)
        self.assertEqual(len({r['economic_sha256'] for r in summaries}),1)
        self.assertEqual(len({r['physical_sha256'] for r in summaries}),1)

    def test_s20_bounded_degree_same_firm_parameters(self):
        c=large_network(20);self.assertEqual(len(c['firms']),70);self.assertEqual(len(c['routes']),120)
        self.assertTrue(all(len(ids)<=2 for f in c['firms'] for ids in f['knowledge'].values()))
        s=simulate(monetary(c,'N3'));s.check_accounts();self.assertEqual(s.economics.rejections['CASH'],0)

if __name__=='__main__':unittest.main()

class OfflineCorruptionTests(unittest.TestCase):
    def test_seven_log_corruptions_rejected(self):
        from corruption_probes import probes
        with tempfile.TemporaryDirectory() as directory:
            results=probes(directory)
            self.assertEqual(len(results),7)
            self.assertTrue(all(r['status']=='PASS_EXPECTED_REJECTION' for r in results))
