"""Supplier knowledge, stock/slot accounting, allocation and conservative switching."""
from copy import deepcopy
from dataclasses import asdict
import unittest
from multi_supplier import MultiSupplierSimulation, InformationInbox, ranked_offers
from stock_admission import StockConfirmedSimulation, StockCommitments, SupplierOffer
from supplier_admission import Simulation
from run_multi_supplier_experiment import all_cases, make_case, run_case, initialize, probes


class MultiSupplierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.results = {case["case_id"]: run_case(case) for case in all_cases()}

    def sim(self, matching="M1", stock_a=400, stock_d=400, stock_b=240, known=("A", "D")):
        case = make_case("test", matching, known=known)
        for supplier, quantity in (("A", stock_a), ("D", stock_d), ("B", stock_b)):
            case["config"]["initial_inventory"][supplier]["coal"] = quantity
        return initialize(case)[0]

    def test_01_stock_zero_gate(self):
        result = probes()
        self.assertEqual(result["stock_gate"], "PASS")
        self.assertEqual(result["requests"][0]["response"]["accepted_quantity"], 300)
        self.assertEqual(result["requests"][1]["response"]["accepted_quantity"], 0)
        self.assertEqual(result["requests"][1]["open_need"], 320)
        self.assertEqual(result["requests"][1]["orders"], 0)

    def test_02_unknown_query_and_request_rejected(self):
        sim = self.sim(known=("A",))
        with self.assertRaises(ValueError): sim.offer("D")
        with self.assertRaises(ValueError): sim.request(80, "D")
        self.assertEqual(sim.requests, [])

    def test_03_unknown_world_single_supplier_equivalence(self):
        base, base_rows, _ = self.results["A_single_S2"]
        world, world_rows, _ = self.results["A_D_unknown"]
        for left, right in zip(base.rows, world.rows):
            self.assertEqual(left, {k: right[k] for k in left})
        self.assertEqual(base.requests, world.requests)
        self.assertEqual(base.offers, world.offers)
        self.assertEqual(base.events, world.events)
        self.assertEqual(base.stock_commitments.entries, world.stock_commitments.entries)

    def test_04_discovery_prefix59_and89(self):
        unknown, urows, _ = self.results["D_shutdown_unknown"]
        for name, prefix in (("E_discovery60", 59), ("F_discovery90", 89)):
            sim, rows, _ = self.results[name]
            self.assertEqual(urows[:prefix], rows[:prefix])
            for attr, day_key in (("offers", "offer_day"), ("requests", "request_day"), ("events", "day")):
                self.assertEqual([e for e in getattr(unknown, attr) if e[day_key] <= prefix],
                                 [e for e in getattr(sim, attr) if e[day_key] <= prefix])

    def test_05_current_stock_atp_and_request_identity(self):
        for sim, _, _ in self.results.values():
            for request in sim.requests:
                self.assertLessEqual(request["accepted_quantity"], request["uncommitted_sellable_stock"])
                self.assertLessEqual(request["accepted_quantity"], request["transport_atp"])
                self.assertEqual(request["requested_quantity"], request["accepted_quantity"] + request["rejected_quantity"])
                self.assertEqual(request["rejected_quantity"], request["rejected_due_stock"] + request["rejected_due_transport"])

    def test_06_same_stock_not_twice_promised(self):
        sim = self.sim(stock_a=100)
        results = [sim.request(80, "A") for _ in range(3)]
        self.assertEqual([r["accepted_quantity"] for r in results], [80, 20, 0])
        self.assertEqual(sim.stock["A"]["coal"], 100)
        self.assertEqual(sim.stock_commitments.totals[("A", "coal")], 100)
        self.assertEqual(sim.shipments, [])

    def test_07_shared_pool_across_buyer_labels(self):
        book = StockCommitments()
        book.reserve(1, "A", "coal", 60, 100)  # buyer1 order
        with self.assertRaises(ValueError): book.reserve(2, "A", "coal", 60, 100)  # buyer2 order
        book.reserve(2, "A", "coal", 40, 100)
        self.assertEqual(book.uncommitted("A", "coal", 100), 0)

    def test_08_transport_slots_shared_not_oversold(self):
        for sim, _, _ in self.results.values():
            for request in sim.requests:
                for before, after in zip(request["slots_before"], request["slots_after"]):
                    self.assertLessEqual(after["committed_quantity"] - before["committed_quantity"], before["remaining_slot"])
                    self.assertGreaterEqual(after["remaining_slot"], 0)

    def test_09_dispatch_releases_only_actual_stock(self):
        sim = self.sim()
        sim.config["routes"]["A_B"]["capacity"] = 30
        oid = sim.request(80)["order_id"]
        sim.dispatch()
        self.assertEqual(sim.stock["A"]["coal"], 370)
        self.assertEqual(sim.stock_commitments.entries[oid][2], 50)
        self.assertEqual(sim.orders[oid].in_transit, 30)

    def test_10_rejection_creates_no_order(self):
        sim = self.sim(stock_a=0)
        response = sim.request(80, "A")
        self.assertIsNone(response["order_id"])
        self.assertEqual(sim.orders, {})
        self.assertEqual(sim.open_procurement_need(), 80)

    def test_11_later_request_only_remaining_need(self):
        for name, need in (("H_split", 100), ("I_insufficient", 150)):
            _, _, prelude = self.results[name]
            a, d = prelude["requests"]
            self.assertEqual(a["requested_quantity"], need)
            self.assertEqual(a["accepted_quantity"], 40)
            self.assertEqual(d["requested_quantity"], need - 40)
            self.assertEqual(d["accepted_quantity"], 60)

    def test_12_accepted_sum_cannot_exceed_need(self):
        for sim, _, _ in self.results.values():
            for boundary in sim.boundaries:
                self.assertLessEqual(boundary["accepted"], boundary["initial_open_need"])

    def test_13_global_pending_and_transit_dedup(self):
        sim = self.sim(stock_b=220)
        sim.request(40, "A"); sim.request(60, "D")
        self.assertEqual(sim.open_procurement_need(), 0)
        self.assertEqual(sim.global_supply_position(), 320)
        sim.dispatch()
        self.assertEqual(sim.open_procurement_need(), 0)
        sim.day = 2; sim.receive()
        self.assertEqual(sim.global_supply_position(), 320)
        self.assertEqual(sim.open_procurement_need(), 0)
        sim.day = 4; sim.receive()
        self.assertEqual(sim.stock["B"]["coal"], 320)
        self.assertEqual(sim.global_supply_position(), 320)

    def test_14_expired_promise_still_commits_stock(self):
        sim = self.sim(stock_a=80)
        oid = sim.request(80, "A")["order_id"]
        sim.day = 3
        self.assertEqual(sim.offer("A").max_acceptable_quantity, 0)
        self.assertEqual(sim.stock_commitments.entries[oid][2], 80)

    def switching_fixture(self, ship=30):
        sim = self.sim(matching="M2")
        sim.config["routes"]["A_B"]["capacity"] = 30
        oid = sim.request(80, "A")["order_id"]
        sim.day = 3; sim.backlog = 30
        sim.procure("B", ["A", "D"])
        self.assertEqual(sim.open_procurement_need(), 0)
        self.assertEqual(sum(r["accepted_quantity"] for r in sim.requests if r["supplier_id"] == "D"), 0)
        sim.config["routes"]["A_B"]["capacity"] = ship
        sim.dispatch()
        sim.day = 4; sim.backlog = 40
        sim.procure("B", ["A", "D"])
        sim.check_accounts()
        return sim, oid

    def test_15_cancel_waiting_never_duplicate(self):
        sim, oid = self.switching_fixture(0)
        self.assertEqual(sim.orders[oid].cancelled, 80)
        replacements = [r for r in sim.requests if r["supplier_id"] == "D"]
        self.assertEqual(len(replacements), 1)
        self.assertEqual(replacements[0]["request_day"], 4)
        self.assertEqual(replacements[0]["accepted_quantity"], 80)

    def test_16_switch_partial_dispatch30_only_replace50(self):
        sim, oid = self.switching_fixture(30)
        self.assertEqual((sim.orders[oid].cancelled, sim.orders[oid].in_transit), (50, 30))
        self.assertEqual([r["accepted_quantity"] for r in sim.requests if r["supplier_id"] == "D"], [50])
        self.assertEqual(sim.global_supply_position(), 320)
        sim.day = 5; sim.receive()
        self.assertEqual(sim.open_procurement_need(), 0)

    def test_17_in_transit_and_delivered_never_cancel(self):
        sim = self.sim()
        oid = sim.request(80, "A")["order_id"]
        sim.dispatch()
        with self.assertRaises(ValueError): sim.request_cancellation(oid, 80)
        sim.day = 2; sim.receive()
        with self.assertRaises(ValueError): sim.request_cancellation(oid, 80)

    def test_18_no_cancel_without_known_positive_alternative(self):
        for known, stock_d in ((("A",), 400), (("A", "D"), 0)):
            sim = self.sim(matching="M2", known=known, stock_d=stock_d)
            sim.request(80); sim.day = 3
            sim.procure("B", list(known))
            self.assertEqual(sim.cancel_history, [])

    def test_19_coal_A_D_source_and_material_identities(self):
        for sim, rows, _ in self.results.values():
            self.assertEqual(sim.cumulative["coal_mined"], sum(sim.source_extraction.values()))
            self.assertEqual(sim.source_extraction["D"], sum(r.get("production_D", 0) for r in rows))
            self.assertTrue(all(r[g + "_residual"] == 0 for r in rows for g in ("coal", "steel", "machine")))
            self.assertEqual(sim.initial["coal"], sum(v["coal"] for v in sim.config["initial_inventory"].values()))

    def test_20_order_and_stock_account_identities(self):
        for sim, rows, _ in self.results.values():
            for order in sim.orders.values(): order.check()
            for supplier, route in sim.supplier_routes.items():
                self.assertEqual(sim.stock_commitments.totals[(supplier, "coal")], sim.balances(route)[0])
                self.assertTrue(all(r[supplier + "_order_residual"] == 0 for r in rows))
                self.assertTrue(all(r[supplier + "_stock_committed"] <= r[supplier + "_coal_on_hand"] for r in rows))

    def test_21_M0_single_S2_oracle(self):
        for treatment in ("normal", "shock", "shutdown", "full_shutdown"):
            case = make_case("oracle", "M0", treatment, known=("A",), add_d=False)
            actual, _, _ = run_case(case)
            oracle = StockConfirmedSimulation(case["config"]).run(600)
            self.assertEqual(oracle.rows, actual.rows)
            self.assertEqual(oracle.events, actual.events)
            self.assertEqual(oracle.requests, actual.requests)

    def test_22_future_discovery_prefix99(self):
        a = make_case("prefix", known=("A",), treatment="shutdown", discovery=100)
        b = deepcopy(a); b["information_events"] = []
        self.check_prefix(a, b)

    def test_23_future_D_capacity_prefix99(self):
        a = make_case("prefix", treatment="shock"); b = deepcopy(a)
        b["config"]["scenarios"]["experiment"]["D_B"] = [dict(first_day=100, last_day=600, capacity=0)]
        self.check_prefix(a, b)

    def check_prefix(self, a, b):
        a["days"] = b["days"] = 130
        left, lrows, _ = run_case(a); right, rrows, _ = run_case(b)
        self.assertEqual(lrows[:99], rrows[:99])
        for attr, key in (("requests", "request_day"), ("offers", "offer_day"), ("events", "day"), ("switch_events", "day")):
            self.assertEqual([r for r in getattr(left, attr) if r[key] < 100], [r for r in getattr(right, attr) if r[key] < 100])

    def test_24_no_future_capacity_query(self):
        class CurrentOnly(MultiSupplierSimulation):
            def capacity(self, route, day):
                if day != self.day: raise AssertionError("future capacity query")
                return super().capacity(route, day)
        case = make_case("current_only", treatment="shock")
        CurrentOnly(case["config"]).run(130)

    def test_25_matching_offer_only_deterministic_sort(self):
        def offer(supplier, quantity, eta): return SupplierOffer(supplier, "coal", 1, quantity, 3, eta - 3, eta)
        candidates = [offer("D", 60, 7), offer("Z", 70, 5), offer("A", 70, 5), offer("B", 40, 5)]
        self.assertEqual([o.supplier_id for o in ranked_offers(candidates)], ["A", "Z", "B", "D"])
        self.assertFalse(any(k in asdict(candidates[0]) for k in ("price", "money", "stock", "production")))

    def test_26_replay_all_cases(self):
        for case in all_cases():
            sim, rows, prelude = run_case(case)
            old, oldrows, oldprelude = self.results[case["case_id"]]
            self.assertEqual(rows, oldrows); self.assertEqual(prelude, oldprelude)
            self.assertEqual(sim.requests, old.requests); self.assertEqual(sim.offers, old.offers)
            self.assertEqual(sim.switch_events, old.switch_events)

    def test_27_observer_off_does_not_change_world(self):
        for case in all_cases():
            sim, _, _ = run_case(case, observe=False)
            old, _, _ = self.results[case["case_id"]]
            self.assertEqual(sim.rows, old.rows); self.assertEqual(sim.events, old.events)
            self.assertEqual(sim.requests, old.requests); self.assertEqual(sim.offers, old.offers)

    def test_28_original_step_receive_FIFO_inherited(self):
        for method in ("step", "receive", "dispatch"):
            self.assertIs(getattr(MultiSupplierSimulation, method), getattr(Simulation, method))

    def test_29_indexed_daily_export_not_history_scan(self):
        sim, rows, _ = self.results["D_shutdown_unknown"]
        self.assertGreater(len(sim.requests), 500)
        self.assertEqual(rows[99]["daily_event_export_visits"], rows[599]["daily_event_export_visits"])
        self.assertLessEqual(rows[599]["daily_event_export_visits"], 4)

    def test_30_D_actual_lead_time_and_source(self):
        sim, _, _ = self.results["E_discovery60"]
        shipments = [s for s in sim.shipments if s.route == "D_B"]
        self.assertTrue(shipments)
        self.assertTrue(all(s.arrival_day == s.dispatch_day + 4 for s in shipments))
        self.assertTrue(all(s.dispatch_day >= 60 for s in shipments))
        self.assertTrue(all(s.quantity > 0 for s in shipments))

    def test_31_M1_keeps_live_old_orders(self):
        sim, _, prelude = self.results["J_overdue_M1"]
        order = sim.orders[prelude["request"]["order_id"]]
        self.assertEqual(order.pending_dispatch, 80)
        self.assertEqual(order.cancelled, 0)
        self.assertEqual(sim.cancel_history, [])

    def test_32_D_cancel_handshake_is_symmetric(self):
        sim = self.sim()
        sim.config["routes"]["D_B"]["capacity"] = 30
        oid = sim.request(80, "D")["order_id"]
        sim.request_cancellation(oid, 80); sim.dispatch(); sim.day = 1; sim.confirm_cancellations()
        order = sim.orders[oid]
        self.assertEqual((order.cancelled, order.in_transit), (50, 30))
        self.assertEqual(sim.stock_commitments.totals[("D", "coal")], 0)

    def test_33_stock_only_conservatism_explicit(self):
        probe = probes()["conservatism"]
        self.assertEqual(probe["today"]["accepted_quantity"], 0)
        self.assertGreater(sum(r["accepted_quantity"] for r in probe["tomorrow"]), 0)


if __name__ == "__main__": unittest.main()
