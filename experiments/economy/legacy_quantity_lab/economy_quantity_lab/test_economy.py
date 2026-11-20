import csv
from copy import deepcopy
import json
from pathlib import Path
import unittest

from economy import Simulation


HERE = Path(__file__).parent
FIXTURE = json.loads((HERE / "fixture.json").read_text(encoding="utf-8"))


class QuantityTests(unittest.TestCase):
    def test_partial_dispatch_fifo_and_order_identity(self):
        config = deepcopy(FIXTURE)
        config["routes"]["A_B"]["capacity"] = 30
        sim = Simulation(config, "baseline")
        sim.day = 1
        first = sim.accept_order("A_B", 80)
        second = sim.accept_order("A_B", 20)
        for day, expected in [(1, (50, 30, 0)), (2, (20, 60, 0)), (3, (0, 50, 30))]:
            sim.day = day
            sim.receive()
            sim.dispatch()
            self.assertEqual((first.pending_dispatch, first.in_transit, first.delivered), expected)
            first.check()
            second.check()
        self.assertEqual(second.pending_dispatch, 10)
        self.assertEqual([s.quantity for s in sim.shipments if s.order_id == first.id], [30, 30, 20])
        for day in (4, 5):
            sim.day = day
            sim.receive()
            sim.dispatch()
        self.assertEqual(first.delivered, 80)
        self.assertEqual(second.delivered, 10)  # Final portion was sent on day 4.
        sim.day = 6
        sim.receive()
        self.assertEqual(second.delivered, 20)

    def test_arrival_delay_once_and_capacity_shock_does_not_reschedule(self):
        sim = Simulation(FIXTURE, "transport_shock")
        sim.day = 49
        order = sim.accept_order("A_B", 80)
        sim.dispatch()
        sim.day = 50
        self.assertEqual(sim.receive()["A_B"], 0)
        self.assertEqual(order.in_transit, 80)
        sim.day = 51
        self.assertEqual(sim.receive()["A_B"], 80)
        stock = sim.stock["B"]["coal"]
        self.assertEqual(sim.receive()["A_B"], 0)
        self.assertEqual(sim.stock["B"]["coal"], stock)
        self.assertEqual(order.delivered, 80)

    def test_insufficient_inputs_and_integer_remainders(self):
        config = deepcopy(FIXTURE)
        config["initial_inventory"]["B"]["coal"] = 5
        config["initial_inventory"]["B"]["steel"] = 0
        config["initial_inventory"]["C"]["steel"] = 7
        sim = Simulation(config, "baseline")
        row = sim.step()
        self.assertEqual((row["production_B"], row["production_C"]), (2, 1))
        self.assertEqual(row["B_coal_on_hand"], 1)
        self.assertEqual(row["C_steel_on_hand"], 3)
        self.assertEqual(row["terminal_backlog"], 9)
        self.assertEqual(sim.check_accounts(), dict(coal=0, steel=0, machine=0))

    def test_pending_and_transit_prevent_duplicate_replenishment(self):
        config = deepcopy(FIXTURE)
        config["initial_inventory"]["B"]["coal"] = 240
        config["routes"]["A_B"]["capacity"] = 30
        sim = Simulation(config, "baseline")
        sim.day = 1
        self.assertEqual(sim.procure("B", ["A"]), (80, 0))
        sim.dispatch()
        self.assertEqual(sim.balances("A_B"), (50, 30))
        self.assertEqual(sim.inventory_position("A_B"), 320)
        self.assertEqual(sim.procure("B", ["A"]), (0, 0))
        sim.day = 3
        sim.receive()
        self.assertEqual(sim.procure("B", ["A"]), (0, 0))
        self.assertEqual(len(sim.orders), 1)

    def test_empty_or_wrong_known_suppliers_record_failed_procurement(self):
        config = deepcopy(FIXTURE)
        config["initial_inventory"]["B"]["coal"] = 240
        config["replenishment"]["B"]["known_suppliers"] = []
        sim = Simulation(config, "baseline")
        row = sim.step()
        self.assertEqual(row["A_B_unprocured"], 80)
        self.assertEqual(row["A_B_new_order"], 0)
        self.assertFalse(sim.active_orders["A_B"])
        self.assertEqual(sim.procure("B", ["C"]), (0, 80))

    def test_in_transit_steel_does_not_trigger_production(self):
        sim = Simulation(FIXTURE, "baseline")
        sim.day = 1
        sim.accept_order("B_C", 40)
        sim.stock["B"]["steel"] = 80
        sim.dispatch()
        self.assertEqual(sim.balances("B_C"), (0, 40))
        self.assertEqual(sim.production_plan()["B"], 0)

    def test_no_instant_use_of_upstream_output(self):
        config = deepcopy(FIXTURE)
        config["initial_inventory"]["B"]["steel"] = 0
        config["initial_inventory"]["C"]["steel"] = 0
        sim = Simulation(config, "baseline")
        first, second = sim.step(), sim.step()
        self.assertEqual(first["production_B"], 40)
        self.assertEqual(first["B_C_dispatch"], 40)
        self.assertEqual(first["production_C"], 0)
        self.assertEqual(second["B_C_arrival"], 40)
        self.assertEqual(second["production_C"], 10)

    def test_every_day_accounts_and_repeatable_published_trajectories(self):
        for scenario in FIXTURE["scenarios"]:
            sim = Simulation(FIXTURE, scenario).run()
            repeated = Simulation(FIXTURE, scenario).run()
            self.assertEqual(sim.rows, repeated.rows)
            self.assertEqual(sim.events, repeated.events)
            self.assertEqual(len(sim.rows), 200)
            for row in sim.rows:
                self.assertTrue(all(row[f"{g}_residual"] == 0 for g in ("coal", "steel", "machine")))
                for route in FIXTURE["routes"]:
                    self.assertLessEqual(row[f"{route}_dispatch"], row[f"{route}_capacity"])
            for order in sim.orders.values():
                order.check()
            for shipment in sim.shipments:
                self.assertEqual(shipment.arrival_day - shipment.dispatch_day,
                                 FIXTURE["routes"][shipment.route]["lead_time"])
                if shipment.received_day is not None:
                    self.assertEqual(shipment.received_day, shipment.arrival_day)
            # When supplied outputs exist (including in the ZIP), compare every cell.
            for suffix, expected in [("", sim.rows), ("_order_trace", sim.events)]:
                path = HERE / f"{scenario}{suffix}.csv"
                if path.exists():
                    with path.open(newline="", encoding="utf-8") as stream:
                        actual = list(csv.DictReader(stream))
                    self.assertEqual(actual, [{k: str(v) for k, v in row.items()} for row in expected])


if __name__ == "__main__":
    unittest.main()
