"""Correctness contracts, not assertions of favorable economic outcomes."""
from copy import deepcopy
import unittest
from run_supplier_admission_experiment import all_cases,make_case,run_case,handshake_cases,stock_shortage_probe
from supplier_admission import AdmissionSimulation,TransportSlots,Simulation,CommitmentSimulation


class AdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.results={c["case_id"]:run_case(c) for c in all_cases()}

    def sim(self,capacity=100,policy="S1",stock=240):
        config=make_case("normal",policy)["config"]
        config["routes"]["A_B"]["capacity"]=capacity
        config["initial_inventory"]["B"]["coal"]=stock
        return AdmissionSimulation(config,admission=policy)

    def test_01_S0_legacy_all_cases(self):
        for case in all_cases():
            if case["policy"]!="S0": continue
            legacy=CommitmentSimulation(case["config"],"experiment",policy="R0").run()
            sim,_=self.results[case["case_id"]]
            self.assertEqual(legacy.rows,sim.rows)
            self.assertEqual(legacy.events,sim.events)
            self.assertEqual(legacy.commitment_events,sim.commitment_events)

    def test_02_request_identity(self):
        for sim,rows in self.results.values():
            for r in sim.requests:
                self.assertEqual(r["requested_quantity"],r["accepted_quantity"]+r["rejected_quantity"])
            for r in rows:
                self.assertEqual(r["requested_qty"],r["accepted_qty"]+r["rejected_qty"])

    def test_03_rejection_creates_no_order(self):
        sim=self.sim(0)
        r=sim.request(80)
        self.assertIsNone(r["order_id"])
        self.assertEqual(sim.orders,{})
        self.assertEqual(sim.shipments,[])
        self.assertEqual(sim.balances("A_B"),(0,0))

    def test_04_partial_80_ATP50(self):
        sim=self.sim(50)
        old=sim.accept_order("A_B",100)
        sim.slots.reserve(old.id,100,sim.slots.quote(0,50))
        r=sim.request(80)
        self.assertEqual((r["ATP"],r["accepted_quantity"],r["rejected_quantity"]),(50,50,30))
        self.assertEqual(sim.orders[r["order_id"]].quantity,50)

    def test_05_partial_remainder_is_open_need(self):
        sim=self.sim(50,stock=140)
        old=sim.accept_order("A_B",100)
        sim.slots.reserve(old.id,100,sim.slots.quote(0,50))
        self.assertEqual(sim.open_procurement_need(),80)
        sim.request(80)
        self.assertEqual(sim.open_procurement_need(),30)

    def test_06_shared_slots_multiple_requests(self):
        sim=self.sim(50)
        responses=[sim.request(80) for _ in range(3)]
        self.assertEqual([r["accepted_quantity"] for r in responses],[80,70,0])
        self.assertEqual(dict(sim.slots.committed),{0:50,1:50,2:50})

    def test_07_slots_at_admission_never_oversell(self):
        for name,(sim,_) in self.results.items():
            if not name.endswith("S1"): continue
            for r in sim.requests:
                self.assertGreaterEqual(r["ATP"],0)
                for before,after in zip(r["slots_before"],r["slots_after"]):
                    # Capacity drops may invalidate prior promises. No newly
                    # reserved quantity may exceed the remaining current quote.
                    increment=after["committed_quantity"]-before["committed_quantity"]
                    self.assertGreaterEqual(increment,0)
                    self.assertLessEqual(increment,before["remaining_slot"])
                self.assertLessEqual(r["accepted_quantity"],r["ATP"])

    def test_08_shutdown_zero_capacity(self):
        sim,rows=self.results["shutdown_S1"]
        requests=[r for r in sim.requests if r["request_day"]>=50]
        self.assertTrue(requests)
        self.assertTrue(all(r["ATP"]==r["accepted_quantity"]==0 for r in requests))
        self.assertTrue(all(r["A_B_dispatch"]==0 for r in rows[49:]))
        self.assertTrue(all(r["production_B"]==r["production_C"]==r["A_B_arrival"]==0 for r in rows[99:]))

    def test_09_rejection_keeps_position(self):
        sim=self.sim(0)
        before=sim.inventory_position("A_B")
        sim.request(80)
        self.assertEqual(sim.inventory_position("A_B"),before)
        self.assertEqual(sim.open_procurement_need(),80)

    def test_10_acceptance_reduces_need(self):
        sim=self.sim()
        sim.request(50)
        self.assertEqual(sim.open_procurement_need(),30)

    def test_11_cancel_requested_is_only_state(self):
        sim=self.sim()
        oid=sim.request(80)["order_id"]
        position=sim.inventory_position("A_B")
        sim.request_cancellation(oid,80)
        self.assertEqual(sim.orders[oid].pending_dispatch,80)
        self.assertEqual(sim.orders[oid].cancelled,0)
        self.assertEqual(sim.inventory_position("A_B"),position)
        sim.confirm_cancellations()
        self.assertEqual(sim.orders[oid].cancelled,0)

    def test_12_confirm_pending_only(self):
        sim=self.sim(30)
        oid=sim.request(80)["order_id"]
        sim.request_cancellation(oid,80)
        sim.dispatch()
        self.assertEqual(sim.open_procurement_need(),0)
        sim.day=1
        sim.confirm_cancellations()
        order=sim.orders[oid]
        self.assertEqual((order.pending_dispatch,order.in_transit,order.cancelled),(0,30,50))
        self.assertEqual(sim.cancel_history[-1]["no_longer_cancellable_qty"],30)
        self.assertEqual(sim.open_procurement_need(),50)
        order.check()

    def test_13_in_transit_not_cancellable(self):
        sim=self.sim(100)
        oid=sim.request(80)["order_id"]
        sim.dispatch()
        with self.assertRaises(ValueError): sim.request_cancellation(oid,80)

    def test_14_delivered_not_cancellable(self):
        sim=self.sim(100)
        oid=sim.request(80)["order_id"]
        sim.dispatch(); sim.day=2; sim.receive()
        with self.assertRaises(ValueError): sim.request_cancellation(oid,80)

    def test_15_conservative_no_duplicate_replacement(self):
        cases=handshake_cases()
        self.assertTrue(all(c["need_waiting"]==c["duplicate_requests"]==0 for c in cases))
        self.assertEqual(cases[-1]["replacement_quantity"],80)
        self.assertEqual(cases[1]["need_confirmed"],50)

    def test_16_old_transit_dedup_on_receive(self):
        sim=self.sim(30)
        oid=sim.request(80)["order_id"]
        sim.request_cancellation(oid,80);sim.dispatch();sim.day=1;sim.confirm_cancellations()
        sim.request(50)
        self.assertEqual(sim.open_procurement_need(),0)
        sim.day=2;sim.receive()
        self.assertEqual(sim.open_procurement_need(),0)
        self.assertEqual(sim.stock["B"]["coal"],270)

    def test_17_all_material_and_order_accounts(self):
        for sim,rows in self.results.values():
            self.assertTrue(all(r[g+"_residual"]==0 for g in ("coal","steel","machine") for r in rows))
            self.assertTrue(all(r["order_residual"]==0 for r in rows))
            for order in sim.orders.values(): order.check()
            self.assertTrue(all(s.quantity>0 for s in sim.shipments))

    def test_18_confirmation_creates_no_material(self):
        sim=self.sim(0,policy="S0")
        oid=sim.request(80)["order_id"]
        sim.request_cancellation(oid,80)
        before=deepcopy(sim.stock)
        sim.day=1;sim.backlog=10;sim.confirm_cancellations()
        self.assertEqual(sim.stock,before)
        self.assertEqual(sim.shipments,[])
        self.assertTrue(all(v==0 for v in sim.check_accounts().values()))

    def test_19_future_prefix(self):
        for policy in ("S0","S1"):
            a=make_case("normal",policy);b=deepcopy(a)
            for case,lastcap in ((a,100),(b,0)):
                case["config"]["days"]=130
                case["config"]["scenarios"]={"experiment":{"A_B":[
                    dict(first_day=50,last_day=99,capacity=30),dict(first_day=100,last_day=130,capacity=lastcap)]}}
            results=[]
            for case in (a,b):
                sim=AdmissionSimulation(case["config"],admission=policy)
                rows=[]
                for _ in range(130):
                    rows.append({**sim.step(),**sim.observe_admission()})
                    if sim.day==60:
                        order=next(o for o in sim.active_orders["A_B"].values() if o.pending_dispatch)
                        sim.request_cancellation(order.id,order.pending_dispatch)
                self.assertTrue(sim.cancel_history)
                results.append((sim,rows))
            (left,lrows),(right,rrows)=results
            self.assertEqual(lrows[:99],rrows[:99])
            for field in ("requests","events","commitment_events","cancel_history"):
                key="request_day" if field=="requests" else "request_day" if field=="cancel_history" else "day"
                self.assertEqual([e for e in getattr(left,field) if e[key]<100],
                                 [e for e in getattr(right,field) if e[key]<100])

    def test_20_determinism(self):
        for case in all_cases():
            sim,rows=run_case(case);old,oldrows=self.results[case["case_id"]]
            self.assertEqual(rows,oldrows);self.assertEqual(sim.requests,old.requests)
            self.assertEqual(sim.commitment_events,old.commitment_events)

    def test_21_original_settlement_inherited(self):
        for name in ("step","dispatch","receive","produce","production_plan"):
            self.assertIs(getattr(AdmissionSimulation,name),getattr(Simulation,name))

    def test_22_expired_slots_do_not_delete_order(self):
        sim=self.sim(30)
        oid=sim.request(80)["order_id"]
        sim.day=3
        self.assertEqual(sim.slots.quote(3,30)[0]["committed_quantity"],0)
        self.assertEqual(sim.orders[oid].pending_dispatch,80)

    def test_23_cancel_invalid_and_monotone(self):
        sim=self.sim(0,policy="S0")
        oid=sim.request(80)["order_id"]
        for q in (0,-1,81,True,1.5):
            with self.assertRaises(ValueError): sim.request_cancellation(oid,q)
        sim.request_cancellation(oid,40)
        with self.assertRaises(ValueError): sim.request_cancellation(oid,1)
        with self.assertRaises(ValueError): sim.cancel_pending(oid,40)
        sim.day=1;sim.confirm_cancellations();sim.request_cancellation(oid,40)
        sim.day=2;sim.confirm_cancellations()
        self.assertEqual(sim.orders[oid].cancelled,80)

    def test_24_accepted_always_promised(self):
        for sim,_ in self.results.values():
            for r in sim.requests:
                self.assertEqual(r["accepted_quantity"],r["promised_quantity"])
                self.assertEqual(r["promised_dispatch_by_day"],r["acceptance_day"]+2 if r["accepted_quantity"] else None)

    def test_25_earliest_slot_and_used_capacity(self):
        sim=self.sim(50)
        oid=sim.request(80)["order_id"]
        self.assertEqual(sim.slots.allocations[oid],{0:50,1:30})
        sim.dispatch()
        quote=sim.slots.quote(0,50)
        self.assertEqual(quote[0]["remaining_slot"],0)
        self.assertEqual(sum(s["remaining_slot"] for s in quote),70)

    def test_26_all_shipped_before_confirmation(self):
        sim=self.sim(100)
        oid=sim.request(80)["order_id"]
        sim.request_cancellation(oid,80);sim.dispatch();sim.day=1;sim.confirm_cancellations()
        self.assertEqual(sim.orders[oid].cancelled,0)
        self.assertEqual(sim.cancel_history[-1]["no_longer_cancellable_qty"],80)
        self.assertEqual(sim.open_procurement_need(),0)

    def test_27_only_current_capacity_queried(self):
        class CurrentOnly(AdmissionSimulation):
            def capacity(self,route,day):
                if day!=self.day: raise AssertionError("future capacity read")
                return super().capacity(route,day)
        for policy in ("S0","S1"):
            case=make_case("full_shutdown",policy)
            CurrentOnly(case["config"],admission=policy).run(130)

    def test_28_partial_cancel_request_and_future_arrival(self):
        sim=self.sim(30)
        oid=sim.request(80)["order_id"]
        sim.request_cancellation(oid,40);sim.dispatch();sim.day=1;sim.confirm_cancellations()
        order=sim.orders[oid]
        self.assertEqual((order.pending_dispatch,order.in_transit,order.cancelled),(40,30,10))
        self.assertEqual(sim.open_procurement_need(),10)
        sim.request(10)
        self.assertEqual(sim.open_procurement_need(),0)
        sim.day=2;sim.receive()
        self.assertEqual(sim.open_procurement_need(),0)
        order.check()

    def test_29_transport_slots_do_not_manufacture_stock(self):
        probe=stock_shortage_probe()
        self.assertGreater(probe["accepted_qty"],0)
        self.assertEqual(probe["actual_dispatch"],0)
        self.assertGreater(probe["breach_count"],0)
        self.assertTrue(all(r[g+"_residual"]==0 for r in probe["rows"] for g in ("coal","steel","machine")))


if __name__=="__main__": unittest.main()
