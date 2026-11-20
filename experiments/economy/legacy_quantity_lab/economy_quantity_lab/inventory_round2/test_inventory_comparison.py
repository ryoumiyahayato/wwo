from copy import deepcopy
import hashlib
import json
from pathlib import Path
import unittest

from inventory_policy import coverage_diagnostic, replenishment_target
from run_inventory_comparison import (Simulation, all_cases, fixture, local_diagnostic,
                                      make_case, run_case, first_window)


class InventoryComparisonTests(unittest.TestCase):
    def test_target_units_default_and_parameter_boundaries(self):
        self.assertEqual(replenishment_target(80, 2), 320)
        self.assertEqual(replenishment_target(80, 8, 2), 800)
        self.assertEqual(replenishment_target(80, 4, 0), 320)
        self.assertEqual(replenishment_target(0, 2, 2), 0)
        for values in [(-1, 2, 2), (80, 0, 2), (80, 2, -1), (80.0, 2, 2),
                       (True, 2, 2), (80, 2.5, 2), (80, 2, "2")]:
            with self.assertRaises(ValueError):
                replenishment_target(*values)

    def test_H1_L2_b2_equals_H0_and_preserved_original(self):
        base = fixture()
        for treatment, old_scenario in [("baseline", "baseline"), ("shock", "transport_shock")]:
            h0 = make_case(base, "h0", "B", treatment)
            h1 = make_case(base, "h1", "B", treatment, "H1", 2, 2)
            sim0, diag0, _ = run_case(h0)
            sim1, diag1, _ = run_case(h1)
            original = Simulation(base, old_scenario).run()
            self.assertEqual(sim0.rows, sim1.rows)
            self.assertEqual(sim0.events, sim1.events)
            self.assertEqual(diag0, diag1)
            self.assertEqual(sim0.rows[:200], original.rows)

    def test_pending_and_transit_keep_procurement_deduplicated(self):
        config = deepcopy(fixture())
        config["initial_inventory"]["B"]["coal"] = 240
        config["routes"]["A_B"]["capacity"] = 30
        sim = Simulation(config, "baseline")
        sim.day = 1
        self.assertEqual(sim.procure("B", ["A"]), (80, 0))
        sim.dispatch()
        diag = local_diagnostic(sim, "A_B", 80)
        self.assertEqual((diag["pending_dispatch"], diag["in_transit"]), (50, 30))
        self.assertEqual(diag["inventory_position"], 320)
        self.assertEqual(diag["pending_wait_age_buckets"], {0: 50})
        self.assertEqual(diag["dispatched_eta_buckets"], {3: 30})
        self.assertEqual(sim.procure("B", ["A"]), (0, 0))
        self.assertEqual(len(sim.orders), 1)

    def test_pending_has_no_fabricated_ETA_and_diagnostic_is_read_only(self):
        pending = [{"ordered_day": 50, "pending_dispatch": 320}]
        shipments = []
        unchanged = deepcopy((pending, shipments))
        diag = coverage_diagnostic(100, 0, pending, shipments, 80, 2)
        self.assertEqual(diag["inventory_position"], 320)
        self.assertEqual(diag["dispatched_eta_buckets"], {})
        self.assertEqual(diag["pending_wait_age_buckets"], {50: 320})
        self.assertEqual(diag["conditional_first_shortfall_day"], 101)
        self.assertEqual(diag["conditional_projected_balance"], {101: -80, 102: -160, 103: -240, 104: -320})
        self.assertEqual((pending, shipments), unchanged)
        covered = coverage_diagnostic(10, 160, [], [{"arrival_day": 11, "quantity": 80},
                                                   {"arrival_day": 12, "quantity": 80}], 80, 2)
        self.assertIsNone(covered["conditional_first_shortfall_day"])
        self.assertEqual(covered["conditional_covered_days"], 4)
        with self.assertRaises(ValueError):
            coverage_diagnostic(10, 0, [], [{"arrival_day": 10, "quantity": 80}], 80, 2)

    def test_observation_toggle_preserves_all_33_quantity_trajectories(self):
        for case in all_cases(fixture()):
            with self.subTest(case=case["case_id"]):
                observed, _, _ = run_case(case, observe=True)
                unobserved, diagnostics, _ = run_case(case, observe=False)
                self.assertEqual(observed.rows, unobserved.rows)
                self.assertEqual(observed.events, unobserved.events)
                self.assertEqual(diagnostics, [])

    def test_unknown_future_capacity_does_not_change_prefix(self):
        base = fixture()
        case = make_case(base, "future_a", "B", "baseline", "H1", 8, 2)
        case["config"]["days"] = 140
        alternate = deepcopy(case)
        alternate["config"]["scenarios"]["experiment"] = {
            "A_B": [{"first_day": 100, "last_day": 140, "capacity": 0}]}
        sim_a, diag_a, _ = run_case(case)
        sim_b, diag_b, _ = run_case(alternate)
        self.assertEqual(sim_a.rows[:99], sim_b.rows[:99])
        self.assertEqual(diag_a[:198], diag_b[:198])
        self.assertNotEqual(sim_a.rows[99:], sim_b.rows[99:])
        self.assertEqual(replenishment_target(80, 8, 2), replenishment_target(80, 8, 2))

    def test_case_matrix_changes_only_authorized_parameters(self):
        base = fixture()
        cases = all_cases(base)
        self.assertEqual(len(cases), 33)
        self.assertEqual(len({c["case_id"] for c in cases}), 33)
        for case in cases:
            config = case["config"]
            self.assertEqual(config["initial_inventory"], base["initial_inventory"])
            self.assertEqual(config["replenishment"]["C"], base["replenishment"]["C"])
            self.assertEqual(config["production"]["A"], base["production"]["A"])
            self.assertEqual(config["production"]["C"], base["production"]["C"])
            self.assertEqual(config["daily_terminal_demand"], base["daily_terminal_demand"])
            self.assertEqual(config["routes"]["B_C"], base["routes"]["B_C"])
            self.assertEqual(config["production"]["B"]["coal_per_steel"], 2)
            self.assertEqual(config["production"]["B"]["capacity"], 60)
            self.assertEqual(config["days"], 600)
            if case["group"] != "A":
                self.assertEqual(config["production"]["B"]["steel_target"], base["production"]["B"]["steel_target"])

    def test_recovery_requires_full_20_day_window(self):
        rows = [{"day": d, "ok": d == 80 or 90 <= d <= 110} for d in range(1, 121)]
        self.assertEqual(first_window(rows, lambda r: r["ok"], 80), 90)
        self.assertIsNone(first_window(rows[:108], lambda r: r["ok"], 80))

    def test_preserved_baseline_provenance_hashes(self):
        here = Path(__file__).parent
        provenance = json.loads((here / "provenance.json").read_text(encoding="utf-8"))
        for name in ("economy.py", "fixture.json", "run_experiment.py", "test_economy.py", "REPORT.md",
                     "baseline.csv", "transport_shock.csv", "baseline_order_trace.csv", "transport_shock_order_trace.csv"):
            self.assertEqual(hashlib.sha256((here.parent / name).read_bytes()).hexdigest(),
                             provenance["original_file_sha256"][name])


if __name__ == "__main__":
    unittest.main()
