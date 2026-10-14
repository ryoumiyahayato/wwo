"""Knowledge latency, indexed bounded work, S2, quantity accounts and extension probes."""
from copy import deepcopy
from dataclasses import asdict, fields
import unittest
from supplier_directory import DirectoryEntry, SupplierDirectory, SearchKnowledge
from supplier_pool import generate_pool
from search_simulation import SearchSimulation, InformationInbox
from run_supplier_search_experiment import all_cases, make_case, run_case, extensibility_probes
from run_multi_supplier_experiment import make_case as old_case, run_case as old_run
from supplier_admission import Simulation


class SupplierSearchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.results = {c["case_id"]: run_case(c) for c in all_cases()}

    def test_01_unknown_offer_request_forbidden(self):
        sim = SearchSimulation(generate_pool(200))
        with self.assertRaises(ValueError): sim.offer("E")
        with self.assertRaises(ValueError): sim.request(80, "S199")

    def test_02_latency_pending_results_hidden(self):
        directory = SupplierDirectory([DirectoryEntry("E", "coal", "Z0", "p", True, 2, "coarse")])
        for scope, delay in (("LOCAL", 1), ("REGIONAL", 3), ("WIDE", 7)):
            buyer = SearchKnowledge("B", "coal", ("A",))
            buyer.issue(10, scope)
            for day in range(10, 10+delay):
                self.assertEqual(buyer.deliver(day, directory), [])
                self.assertEqual(buyer.known, {"A"})
                self.assertEqual(directory.query_visits, 0)
            self.assertEqual(buyer.deliver(10+delay, directory)[0].supplier_id, "E")
            self.assertEqual(buyer.known, {"A", "E"})
            directory.query_visits = 0

    def test_03_directory_contains_no_economic_state(self):
        names = {f.name for f in fields(DirectoryEntry)}
        self.assertFalse(names & {"stock", "ATP", "stock_commitment", "future_capacity", "orders", "production"})
        a = make_case("bad", "Q1"); b = deepcopy(a)
        b["config"]["initial_inventory"]["E"]["coal"] = 999
        b["config"]["production"]["E"]["capacity"] = 99
        b["config"]["routes"]["E_B"]["capacity"] = 0
        da = SupplierDirectory([DirectoryEntry(**e) for e in a["config"]["directory_entries"]])
        db = SupplierDirectory([DirectoryEntry(**e) for e in b["config"]["directory_entries"]])
        self.assertEqual(da.search("coal", "Z0", "LOCAL", 3, {"A", "D"}), db.search("coal", "Z0", "LOCAL", 3, {"A", "D"}))

    def test_04_limits_1_3_5(self):
        directory = SupplierDirectory([DirectoryEntry(f"S{i}", "coal", "Z0", f"p{i}", True, 2, "coarse") for i in range(10)])
        for limit in (1, 3, 5):
            self.assertEqual(len(directory.search("coal", "Z0", "WIDE", limit)), limit)
        for bad in (0, -1, True, 1.5):
            with self.assertRaises(ValueError): directory.search("coal", "Z0", "LOCAL", bad)

    def test_05_empty_search_complete_no_results(self):
        buyer = SearchKnowledge("B", "coal", ())
        buyer.consider(1, 80); buyer.deliver(2, SupplierDirectory([]))
        self.assertIsNone(buyer.pending)
        self.assertEqual(buyer.events[-1]["event"], "SEARCH_COMPLETED_NO_RESULTS")
        self.assertEqual(buyer.consider(2, 80).scope, "REGIONAL")

    def test_06_ordered_expansion_and_one_pending(self):
        sim, _ = self.results["E_wide_Q1"]
        self.assertEqual([r.scope for r in sim.knowledge.requests], ["LOCAL", "REGIONAL", "WIDE"])
        self.assertEqual([(r.requested_day, r.delivery_day) for r in sim.knowledge.requests], [(6, 7), (7, 10), (10, 17)])
        buyer = SearchKnowledge("B", "coal", ())
        self.assertIsNotNone(buyer.consider(1, 80))
        self.assertIsNone(buyer.consider(1, 80))
        self.assertIsNone(buyer.issue(1, "WIDE"))

    def test_07_cooldown_from_completion(self):
        buyer = SearchKnowledge("B", "coal", ())
        buyer.issue(1, "LOCAL"); buyer.deliver(2, SupplierDirectory([]))
        self.assertIsNone(buyer.issue(31, "LOCAL"))
        self.assertIsNotNone(buyer.issue(32, "LOCAL"))

    def test_08_normal_Q1_no_search(self):
        sim, rows = self.results["A_normal_Q1"]
        self.assertEqual(sim.knowledge.requests, [])
        self.assertEqual(rows, self.results["A_normal_Q0"][1])

    def test_09_fixed_known_matching_not_N(self):
        for name in ("G_scale10", "H_scale50", "I_scale200"):
            sim, rows = self.results[name]
            self.assertEqual(sim.candidate_scans, 1198)
            self.assertEqual(sim.offer_evaluations, 1198)
            self.assertTrue(all(r["known_supplier_count"] == 2 for r in rows))
            self.assertTrue(all(r["offers_queried_today"] <= 2 for r in rows))
            self.assertEqual(set(sim.supplier_routes), {"A", "D"})

    def test_10_indexed_query_relevant_bucket(self):
        probes = extensibility_probes()["index_scale"]
        self.assertEqual([r["build_visits"] for r in probes], [10, 50, 200])
        self.assertEqual([r["query_visits"] for r in probes], [2, 5, 4])
        self.assertTrue(all(r["bucket_lookups"] == 1 for r in probes))
        self.assertTrue(all(r["result_count"] <= 3 for r in probes))
        self.assertEqual(probes[-1]["query_audit"][0]["bucket_sizes"], [21])

    def test_11_empty_stock_found_but_S2_accepts_zero(self):
        sim, _ = self.results["F_bad_Q1"]
        self.assertIn("E", sim.known)
        offers = [o for o in sim.offers if o["supplier_id"] == "E"]
        self.assertTrue(offers)
        self.assertTrue(all(o["max_acceptable_quantity"] == 0 for o in offers))
        self.assertTrue(all(r["order_id"] is None and r["accepted_quantity"] == 0 for r in sim.requests if r["supplier_id"] == "E"))
        self.assertIn("S003", sim.known)

    def test_12_acceptance_never_exceeds_need_or_ATP(self):
        for sim, _ in self.results.values():
            self.assertTrue(all(b["accepted"] <= b["initial_open_need"] for b in sim.boundaries))
            for request in sim.requests:
                self.assertLessEqual(request["accepted_quantity"], request["stock_confirmed_atp"])
                self.assertEqual(request["requested_quantity"], request["accepted_quantity"]+request["rejected_quantity"])

    def test_13_global_incremental_balances_match_accounts(self):
        for sim, rows in self.results.values():
            p = t = 0
            for route in sim.server_routes.values():
                pending, transit = sim.balances(route); p += pending; t += transit
            self.assertEqual((p, t), (sim.coal_pending, sim.coal_transit))
            self.assertTrue(all(r["global_supply_position"] == r["B_coal_on_hand"]+r["total_in_transit"]+r["total_live_pending"] for r in rows))

    def test_14_all_material_order_and_source_identities(self):
        for sim, rows in self.results.values():
            self.assertTrue(all(r[g+"_residual"] == 0 for g in ("coal", "steel", "machine") for r in rows))
            self.assertEqual(sum(sim.source_extraction.values()), sim.cumulative["coal_mined"])
            self.assertTrue(all(r["coal_order_residual"] == 0 for r in rows))
            for order in sim.orders.values(): order.check()
            self.assertEqual(len(sim.source_extraction), len(sim.world_ids))

    def test_15_future_capacity_prefix99(self):
        a = make_case("local", "Q1"); b = deepcopy(a)
        b["config"]["scenarios"] = {"experiment": {"E_B": [dict(first_day=100, last_day=600, capacity=0)]}}
        self.check_prefix(a, b)

    def test_16_future_information_prefix99(self):
        a = make_case("normal", "Q0"); b = deepcopy(a)
        a["information_events"] = [dict(day=100, supplier_id="E", source="prefix_test")]
        self.check_prefix(a, b)

    def check_prefix(self, a, b):
        a["days"] = b["days"] = 130
        left, lr = run_case(a); right, rr = run_case(b)
        self.assertEqual(lr[:99], rr[:99])
        for attr, key in (("requests", "request_day"), ("offers", "offer_day"), ("events", "day")):
            self.assertEqual([r for r in getattr(left, attr) if r[key] < 100], [r for r in getattr(right, attr) if r[key] < 100])
        self.assertEqual([e for e in left.knowledge.events if e["day"] < 100], [e for e in right.knowledge.events if e["day"] < 100])

    def test_17_future_results_hidden_until_delivery(self):
        a = SearchKnowledge("B", "coal", ("A",)); b = SearchKnowledge("B", "coal", ("A",))
        a.issue(99, "LOCAL"); b.issue(99, "LOCAL")
        da = SupplierDirectory([DirectoryEntry("E", "coal", "Z0", "pE", True, 2, "coarse")])
        db = SupplierDirectory([DirectoryEntry("F", "coal", "Z0", "pF", True, 2, "coarse")])
        self.assertEqual(a.deliver(99, da), b.deliver(99, db))
        self.assertEqual(a.events, b.events); self.assertEqual(a.known, b.known)
        self.assertEqual(da.query_visits, 0); self.assertEqual(db.query_visits, 0)
        a.deliver(100, da); b.deliver(100, db)
        self.assertNotEqual(a.known, b.known)

    def test_18_stock_shared_two_buyer_probe(self):
        probe = extensibility_probes()["multiple_buyers"]
        self.assertEqual([r["accepted"] for r in probe["requests"]], [80, 20])
        self.assertEqual(probe["shared_stock_committed"], probe["stock"]["A"])
        self.assertNotEqual(probe["search_events"]["B1"][0]["search_id"], probe["search_events"]["B2"][0]["search_id"])

    def test_19_commodity_buckets_do_not_cross(self):
        probe = extensibility_probes()["mixed_commodity"]
        self.assertEqual(len(probe["commodities"]), 5)
        self.assertEqual(probe["build_visits"], 200)
        self.assertTrue(all(a["commodity"] == "coal" for a in probe["query_audit"]))
        for audit in probe["query_audit"]:
            self.assertTrue(all(int(s[1:]) % 5 == 0 for s in audit["inspected_ids"]))

    def test_20_old_two_supplier_M1_equivalence(self):
        for treatment, known, discovery in (("normal", ("A", "D"), None), ("shock", ("A", "D"), None), ("shutdown", ("A",), 60)):
            old = old_case("old", "M1", treatment, known, discovery)
            oracle, _, _ = old_run(old)
            config = deepcopy(old["config"])
            generated = generate_pool(2)
            for field in ("directory_entries", "supplier_routes", "supplier_state"):
                config[field] = generated[field]
            actual = SearchSimulation(config, "Q0", InformationInbox(old["information_events"]))
            actual.run(600)
            self.assertEqual(oracle.rows, actual.rows); self.assertEqual(oracle.events, actual.events)
            self.assertEqual(oracle.requests, actual.requests); self.assertEqual(oracle.offers, actual.offers)

    def test_21_replay_small_and_large(self):
        for name in ("C_local_Q1", "E_wide_Q1", "F_bad_Q1", "I_scale200"):
            case = next(c for c in all_cases() if c["case_id"] == name)
            sim, rows = run_case(case)
            old, oldrows = self.results[name]
            self.assertEqual(rows, oldrows); self.assertEqual(sim.requests, old.requests)
            self.assertEqual(sim.knowledge.events, old.knowledge.events)

    def test_22_observation_off_same_economy(self):
        for name in ("C_local_Q1", "I_scale200"):
            case = next(c for c in all_cases() if c["case_id"] == name)
            sim, _ = run_case(case, observe=False)
            old, _ = self.results[name]
            self.assertEqual(sim.rows, old.rows); self.assertEqual(sim.requests, old.requests)
            self.assertEqual(sim.events, old.events); self.assertEqual(sim.knowledge.events, old.knowledge.events)

    def test_23_original_step_FIFO_receive_reused(self):
        for method in ("step", "dispatch", "receive"):
            self.assertIs(getattr(SearchSimulation, method), getattr(Simulation, method))

    def test_24_no_future_capacity_queries(self):
        class CurrentOnly(SearchSimulation):
            def capacity(self, route, day):
                if day != self.day: raise AssertionError("future capacity queried")
                return super().capacity(route, day)
        case = make_case("wide", "Q1")
        CurrentOnly(case["config"], "Q1").run(120)

    def test_25_unknown_routes_not_mislabeled_as_orders(self):
        sim, rows = self.results["I_scale200"]
        self.assertTrue(all(r[supplier+"_B_new_order"] == 0 for supplier in sim.world_ids if supplier not in ("A", "D") for r in rows))

    def test_26_inactive_known_retained_zero_offer(self):
        config = generate_pool(10)
        config["replenishment"]["B"]["known_suppliers"] = ["A", "D", "E"]
        sim = SearchSimulation(config)
        self.assertGreater(sim.offer("E").max_acceptable_quantity, 0)
        sim.supplier_state["E"]["active"] = False
        self.assertEqual(sim.offer("E").max_acceptable_quantity, 0)
        self.assertEqual(sim.request(80, "E")["accepted_quantity"], 0)
        self.assertIn("E", sim.known)

    def test_27_no_search_for_sufficient_offers(self):
        buyer = SearchKnowledge("B", "coal", ())
        self.assertIsNone(buyer.consider(1, 80, offers_sufficient=True))
        self.assertIsNone(buyer.consider(1, 0))
        passive = SearchKnowledge("B", "coal", (), "Q0")
        self.assertIsNone(passive.consider(1, 320))

    def test_28_pool_determinism_and_unique_places(self):
        for n in (2, 10, 50, 200):
            a = generate_pool(n); self.assertEqual(a, generate_pool(n))
            self.assertEqual(len(a["available_supplier_ids"]), n)
            self.assertEqual(len({e["place_id"] for e in a["directory_entries"]}), n)

    def test_29_procurement_cannot_iterate_world_routes(self):
        class DirectLookupOnly(dict):
            def __iter__(self): raise AssertionError("global iteration")
            def items(self): raise AssertionError("global items")
            def values(self): raise AssertionError("global values")
        config = generate_pool(200)
        config["initial_inventory"]["B"]["coal"] = 0
        config["initial_inventory"]["C"]["steel"] = 0
        sim = SearchSimulation(config, "Q1")
        sim.config["routes"] = DirectLookupOnly(sim.config["routes"])
        sim.server_routes = DirectLookupOnly(sim.server_routes)
        sim.procure("B", ["A", "D"])
        sim.procure("C", ["B"])
        self.assertEqual(sim.candidate_scans, 2)
        self.assertEqual(sim.open_procurement_need(), 0)

    def test_30_query_cannot_iterate_directory_catalog(self):
        class CannotIterate(tuple):
            def __iter__(self): raise AssertionError("catalog scan during query")
        config = generate_pool(200)
        directory = SupplierDirectory([DirectoryEntry(**e) for e in config["directory_entries"]])
        directory.entries = CannotIterate(directory.entries)
        self.assertEqual(len(directory.search("coal", "Z0", "LOCAL", 3, {"A", "D"})), 3)

    def test_31_query_and_search_delivery_causal_order(self):
        for sim, _ in self.results.values():
            discovered = {s: 0 for s in ("A", "D")}
            for event in sim.discoveries:
                discovered.setdefault(event["supplier_id"], event["day"])
            self.assertTrue(all(o["offer_day"] >= discovered[o["supplier_id"]] for o in sim.offers))
            for request in sim.knowledge.requests:
                self.assertEqual(request.delivery_day, request.requested_day+sim.knowledge.latencies[request.scope])

    def test_32_initial_known_five_uses_only_five(self):
        config = generate_pool(200)
        config["initial_inventory"]["B"]["coal"] = 0
        known = ["A", "D", "E", "S003", "S004"]
        config["replenishment"]["B"]["known_suppliers"] = known
        sim = SearchSimulation(config)
        sim.procure("B", known)
        self.assertEqual(sim.candidate_scans, 5)
        self.assertEqual(set(sim.supplier_routes), set(known))
        self.assertEqual(sim.global_supply_position(), 320)


if __name__ == "__main__": unittest.main()
