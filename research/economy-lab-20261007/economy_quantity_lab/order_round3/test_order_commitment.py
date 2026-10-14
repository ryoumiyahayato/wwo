"""Correctness constraints, not assertions that a candidate must be beneficial."""
from copy import deepcopy
import csv
from pathlib import Path
import sys
import unittest

from commitment_adapter import CommitmentSimulation
from order_commitment import (classify_pending, disposition_decisions, effective_supply_position,
                              make_commitment, order_residual, validate_cancellation)
from order_commitment import promise_status
from run_order_commitment_experiment import all_cases, make_case, run_case
from economy import Simulation
from run_inventory_comparison import all_cases as round2_cases, fixture


class OrderCommitmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = all_cases()
        cls.completed = {c["case_id"]: run_case(c) for c in cls.cases}

    def test_explicit_promise_due_and_overdue_boundary(self):
        promise = make_commitment(50, 2)
        self.assertEqual(promise.promised_dispatch_by_day, 52)
        due = classify_pending(52, [(1, 80, promise)])
        self.assertEqual(due["pending_promised_qty"], 80)
        self.assertEqual(due["overdue_pending_qty"], 0)
        overdue = classify_pending(53, [(1, 80, promise)])
        self.assertEqual(overdue["overdue_pending_qty"], 80)
        self.assertEqual(overdue["oldest_overdue_days"], 1)
        self.assertEqual(make_commitment(50, 0).promised_dispatch_by_day, 50)

    def test_per_order_status_is_explicit_and_derived_from_pending_only(self):
        c = make_commitment(50)
        self.assertEqual([promise_status(d, 20, c) for d in (50, 52, 53)], ["PROMISED", "DUE", "OVERDUE"])
        self.assertEqual(promise_status(53, 0, c), "NO_PENDING")
        self.assertEqual(promise_status(600, 80, make_commitment(50, None)), "UNPROMISED")
        sim, _ = self.completed["shock_R2"]
        self.assertTrue(all(e["promise_status"] == "OVERDUE" for e in sim.commitment_events if e["event"] == "promise_breach"))

    def test_decision_gap_cancellation_counts_and_scan_metrics(self):
        for case_id, (sim, rows) in self.completed.items():
            self.assertEqual(sum(r["order_scan_visits_today"] for r in rows), sim.active_scan_visits)
            self.assertEqual(sim.totals["A_B"]["cancelled_order_count"],
                             len([o for o in sim.orders.values() if o.route == "A_B" and o.cancelled]))
            for row in rows:
                self.assertEqual(row["replenishment_gap"], max(0, 320 - row["decision_effective_position"]))
                self.assertEqual(row["new_order_qty_today"], row["replenishment_gap"])
                self.assertLessEqual(row["overdue_order_count"], row["active_orders"])

    def test_only_remaining_pending_can_be_overdue(self):
        snapshot = classify_pending(53, [(1, 20, make_commitment(50, 2)),
                                        (2, 0, make_commitment(50, 2))])
        self.assertEqual(snapshot["overdue_orders"], ((1, 20),))
        self.assertEqual(snapshot["overdue_pending_qty"], 20)

    def test_no_promise_has_no_inferred_deadline(self):
        classified = classify_pending(600, [(1, 320, make_commitment(1, None))])
        self.assertEqual(classified["overdue_pending_qty"], 0)
        self.assertEqual(classified["pending_unpromised_qty"], 320)
        self.assertEqual(effective_supply_position(0, 0, classified, "R1"), 320)
        self.assertEqual(disposition_decisions(classified, "R2"), ())

    def test_R1_filters_decision_without_editing_pending_facts(self):
        facts = [(1, 80, make_commitment(1)), (2, 40, make_commitment(5)),
                 (3, 20, make_commitment(1, None))]
        original = deepcopy(facts)
        classified = classify_pending(5, facts)
        self.assertEqual(effective_supply_position(10, 30, classified, "R0"), 180)
        self.assertEqual(effective_supply_position(10, 30, classified, "R1"), 100)
        self.assertEqual(facts, original)
        self.assertEqual(disposition_decisions(classified, "R1"), ())
        sim, _ = self.completed["shutdown_R1"]
        self.assertEqual(sim.totals["A_B"]["cancelled"], 0)
        self.assertTrue(all(o.quantity == o.pending_dispatch + o.in_transit + o.delivered for o in sim.orders.values()))

    def test_R2_partial_cancellation_does_not_touch_cargo(self):
        case = make_case("normal", "R2")
        sim = CommitmentSimulation(case["config"], "experiment", "R2")
        order = sim.accept_order("A_B", 150)
        sim.dispatch()
        self.assertEqual((order.pending_dispatch, order.in_transit), (50, 100))
        before = deepcopy((sim.shipments, sim.stock, sim.arrivals))
        with self.assertRaises(ValueError):
            sim.cancel_pending(order.id, 51)
        sim.cancel_pending(order.id, 50)
        self.assertEqual(before, (sim.shipments, sim.stock, sim.arrivals))
        self.assertEqual((order.quantity, order.pending_dispatch, order.in_transit, order.cancelled), (150, 0, 100, 50))
        order.check()
        with self.assertRaises(ValueError):
            sim.cancel_pending(order.id, 1)

    def test_R2_reorder_goes_to_FIFO_tail_with_fresh_id(self):
        case = make_case("normal", "R2")
        sim = CommitmentSimulation(case["config"], "experiment", "R2")
        first = sim.accept_order("A_B", 150)
        second = sim.accept_order("A_B", 80)
        sim.dispatch()
        sim.cancel_pending(first.id, 50)
        replacement = sim.accept_order("A_B", 50)
        self.assertGreater(replacement.id, second.id)
        self.assertEqual([o.id for o in sim.dispatch_queues["A_B"]], [second.id, replacement.id])
        sim.step()
        ids = [s.order_id for s in sim.shipments if s.route == "A_B" and s.dispatch_day == 1]
        self.assertEqual(ids, [second.id, replacement.id])

    def test_cancelled_in_transit_order_retires_only_after_arrival(self):
        case = make_case("normal", "R2")
        sim = CommitmentSimulation(case["config"], "experiment", "R2")
        order = sim.accept_order("A_B", 150)
        sim.dispatch()
        sim.cancel_pending(order.id, 50)
        sim.step()
        self.assertIn(order.id, sim.active_orders["A_B"])
        sim.step()
        self.assertNotIn(order.id, sim.active_orders["A_B"])
        self.assertEqual((order.delivered, order.cancelled), (100, 50))
        with self.assertRaises(ValueError):
            sim.cancel_pending(order.id, 1)
        order.check()

    def test_one_inherited_material_settlement_path(self):
        for name in ("step", "receive", "production_plan", "produce", "dispatch"):
            self.assertIs(getattr(CommitmentSimulation, name), getattr(Simulation, name))

    def test_R0_replays_published_round2_corresponding_scenarios(self):
        names = {"normal_R0": "B_L2_H1_b2_baseline", "shock_R0": "B_L2_H1_b2_shock",
                 "shutdown_R0": "C_shutdown_H0"}
        source = Path(__file__).resolve().parent.parent / "inventory_round2/inventory_comparison_results"
        for case_id, name in names.items():
            sim, _ = self.completed[case_id]
            with (source / name / "daily.csv").open(encoding="utf-8", newline="") as stream:
                published = list(csv.DictReader(stream))
            self.assertEqual(len(sim.rows), len(published))
            self.assertEqual([{k: str(v) for k, v in row.items()} for row in sim.rows],
                             [{k: row[k] for k in sim.rows[0]} for row in published])
        case = make_case("full_shutdown", "R0")
        original = Simulation(case["config"], "experiment").run()
        adapted, _ = self.completed["full_shutdown_R0"]
        self.assertEqual((original.rows, original.events), (adapted.rows, adapted.events))

    def test_R0_disabled_disposition_preserves_all_33_round2_trajectories(self):
        for old in round2_cases(fixture()):
            case = {**old, "policy": "R0", "promise_window_days": 2}
            sim, _ = run_case(case, observe=False)
            original = Simulation(old["config"], "experiment").run()
            self.assertEqual((sim.rows, sim.events), (original.rows, original.events), old["case_id"])

    def test_daily_orders_materials_and_final_indexes_all_14_cases(self):
        self.assertEqual(len(self.completed), 14)
        for case_id, (sim, rows) in self.completed.items():
            self.assertEqual(len(rows), 600)
            previous = 0
            for row in rows:
                self.assertEqual(order_residual(row["cumulative_ordered"], row["pending_dispatch"], row["in_transit"],
                                                row["delivered"], row["cancelled"]), 0, case_id)
                self.assertEqual(row["order_residual"], 0)
                self.assertGreaterEqual(row["cancelled"], previous)
                previous = row["cancelled"]
                self.assertTrue(all(row[f"{g}_residual"] == 0 for g in ("coal", "steel", "machine")))
                self.assertLessEqual(row["A_B_dispatch"], row["A_B_capacity"])
            for route in sim.config["routes"]:
                orders = [o for o in sim.orders.values() if o.route == route]
                self.assertEqual(sum(o.quantity for o in orders), sim.totals[route]["ordered"])
                self.assertEqual(sum(o.delivered for o in orders), sim.totals[route]["delivered"])
                self.assertEqual(sum(o.cancelled for o in orders), sim.totals[route]["cancelled"])
                queued = [o.id for o in sim.dispatch_queues[route]]
                self.assertEqual(len(queued), len(set(queued)))
                self.assertEqual(set(queued), {o.id for o in sim.active_orders[route].values() if o.pending_dispatch})
                for order in orders:
                    self.assertEqual(order.id in sim.active_orders[route], bool(order.pending_dispatch or order.in_transit))
                    order.check()

    def test_shutdown_cannot_create_supply_for_R1_or_R2(self):
        reference = self.completed["shutdown_R0"][0]
        for policy in ("R1", "R2"):
            sim, rows = self.completed[f"shutdown_{policy}"]
            self.assertTrue(all(s.dispatch_day < 50 for s in sim.shipments if s.route == "A_B"))
            self.assertEqual([(r["production_B"], r["production_C"], r["terminal_delivery"]) for r in sim.rows],
                             [(r["production_B"], r["production_C"], r["terminal_delivery"]) for r in reference.rows])
            self.assertTrue(all(r["production_B"] == r["production_C"] == r["A_B_arrival"] == 0 for r in rows[59:]))

    def test_no_promise_controls_use_explicit_legacy_fallback(self):
        for treatment in ("shock", "shutdown"):
            sim, rows = self.completed[f"no_promise_{treatment}_R1"]
            original = self.completed[f"{treatment}_R0"][0]
            self.assertEqual((sim.rows, sim.events), (original.rows, original.events))
            self.assertTrue(all(c.promised_dispatch_by_day is None for c in sim.commitments.values()))
            self.assertTrue(all(r["overdue_pending_qty"] == r["promise_breach_order_count"] == 0 for r in rows))

    def test_future_information_prefix_equivalence_all_policies(self):
        for policy in ("R0", "R1", "R2"):
            a = make_case("shutdown", policy)
            b = deepcopy(a)
            a["config"]["days"] = b["config"]["days"] = 110
            b["config"]["scenarios"]["experiment"]["A_B"][0]["last_day"] = 99
            x, xr = run_case(a)
            y, yr = run_case(b)
            self.assertEqual(xr[:99], yr[:99])
            self.assertEqual([e for e in x.commitment_events if e["day"] < 100],
                             [e for e in y.commitment_events if e["day"] < 100])
            self.assertEqual([e for e in x.events if e["day"] < 100], [e for e in y.events if e["day"] < 100])

    def test_observer_switch_and_repeat_are_deterministic(self):
        for policy in ("R0", "R1", "R2"):
            case = make_case("full_shutdown", policy)
            sim, rows = self.completed[case["case_id"]]
            repeated, repeated_rows = run_case(case)
            silent, _ = run_case(case, observe=False)
            self.assertEqual(rows, repeated_rows)
            self.assertEqual((sim.rows, sim.events, sim.commitment_events),
                             (silent.rows, silent.events, silent.commitment_events))

    def test_invalid_facts_and_cancellations_fail_without_mutation(self):
        for value in (-1, 1.5, True, "2"):
            with self.assertRaises(ValueError):
                make_commitment(1, value)
            with self.assertRaises(ValueError):
                validate_cancellation(80, value)
        with self.assertRaises(ValueError):
            classify_pending(1, [(1, 80, make_commitment(2))])
        sim = CommitmentSimulation(make_case("normal", "R1")["config"], "experiment", "R1")
        order = sim.accept_order("A_B", 80)
        with self.assertRaises(ValueError):
            sim.cancel_pending(order.id, 80)
        self.assertEqual(order.pending_dispatch, 80)


if __name__ == "__main__":
    unittest.main()
