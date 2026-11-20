"""Opt-in adapter around the unchanged quantity engine, with a cancellation sidecar.

No step/production/dispatch/arrival/material-account implementation is copied.
Only newly accepted order objects get a cancellation-aware invariant. The original
acceptance path creates IDs, queues and events before this representation adapter.
"""
from dataclasses import dataclass, field
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from economy import Order, Simulation, require
from order_commitment import (classify_pending, disposition_decisions, effective_supply_position,
                              make_commitment, order_residual, validate_cancellation)
from order_commitment import promise_status


@dataclass
class DispositionOrder(Order):
    cancellation_ledger: dict = field(default_factory=dict, repr=False)

    @property
    def cancelled(self):
        return self.cancellation_ledger.get(self.id, 0)

    def check(self):
        if not self.cancelled:
            return super().check()
        require(order_residual(self.quantity, self.pending_dispatch, self.in_transit,
                               self.delivered, self.cancelled) == 0,
                f"cancelled order identity: {self.id}")


class CommitmentSimulation(Simulation):
    def __init__(self, config, scenario, policy="R0", promise_window_days=2, observe=True):
        if policy not in ("R0", "R1", "R2"):
            raise ValueError("unknown policy")
        make_commitment(0, promise_window_days)
        self.policy, self.promise_window_days, self.observe = policy, promise_window_days, observe
        self.commitments = {}
        self.cancelled_by_order_id = {}
        self.breached = set()
        self.commitment_events = []
        self.decision_rows = []
        self.decision = {}
        self._decision_position = False
        self.active_scan_visits = 0
        self.route_order_residuals = {}
        self.totals = {r: {"ordered": 0, "delivered": 0, "cancelled": 0, "order_count": 0,
                          "breach_count": 0, "breach_qty": 0, "reorder_count": 0,
                          "max_queue": 0, "max_active": 0, "max_overdue": 0,
                          "cancelled_order_count": 0} for r in config["routes"]}
        super().__init__(config, scenario)

    def record_event(self, event, order, shipment=None, quantity=0):
        if event == "accepted":
            self.commitments[order.id] = make_commitment(self.day, self.promise_window_days)
            self.totals[order.route]["ordered"] += quantity
            self.totals[order.route]["order_count"] += 1
            self.totals[order.route]["max_queue"] = max(
                self.totals[order.route]["max_queue"], len(self.dispatch_queues[order.route]))
            self.totals[order.route]["max_active"] = max(
                self.totals[order.route]["max_active"], len(self.active_orders[order.route]))
        elif event == "arrived":
            self.totals[order.route]["delivered"] += quantity
        super().record_event(event, order, shipment, quantity)
        self._record_commitment_event(event, order, quantity, shipment)
        # The unchanged receive method retires orders when delivered == ordered.
        # A cancelled order instead closes at delivered + cancelled == ordered.
        if event == "arrived" and self.cancelled_by_order_id.get(order.id, 0):
            if not order.pending_dispatch and not order.in_transit:
                del self.active_orders[order.route][order.id]

    def _record_commitment_event(self, event, order, quantity=0, shipment=None):
        promise = self.commitments[order.id]
        self.commitment_events.append({
            "day": self.day, "event": event, "route": order.route, "order_id": order.id,
            "accepted_day": promise.accepted_day, "promise_window_days": promise.promise_window_days,
            "promised_dispatch_by_day": promise.promised_dispatch_by_day,
            "promise_status": promise_status(self.day, order.pending_dispatch, promise),
            "ordered_quantity": order.quantity, "quantity": quantity,
            "pending_dispatch": order.pending_dispatch, "in_transit": order.in_transit,
            "delivered": order.delivered, "cancelled": self.cancelled_by_order_id.get(order.id, 0),
            "shipment_id": shipment.id if shipment else None,
            "dispatch_day": shipment.dispatch_day if shipment else None,
            "arrival_day": shipment.arrival_day if shipment else None,
        })

    def accept_order(self, route, quantity):
        original = super().accept_order(route, quantity)
        # One representation change on acceptance; settlement stays inherited.
        order = DispositionOrder(**vars(original), cancellation_ledger=self.cancelled_by_order_id)
        self.orders[order.id] = order
        self.active_orders[route][order.id] = order
        require(self.dispatch_queues[route][-1] is original, "acceptance queue boundary")
        self.dispatch_queues[route][-1] = order
        return order

    def classification(self, route):
        orders = self.active_orders[route].values()
        self.active_scan_visits += len(self.active_orders[route])
        facts = [(o.id, o.pending_dispatch, self.commitments[o.id]) for o in orders]
        result = classify_pending(self.day, facts)
        self.totals[route]["max_overdue"] = max(self.totals[route]["max_overdue"], result["overdue_order_count"])
        return result

    def cancel_pending(self, order_id, quantity):
        if type(order_id) is not int or order_id not in self.orders:
            raise ValueError("unknown order id")
        if self.policy != "R2":
            raise ValueError("cancellation is only enabled in R2")
        order = self.orders[order_id]
        validate_cancellation(order.pending_dispatch, quantity)
        if not self.cancelled_by_order_id.get(order_id, 0):
            self.totals[order.route]["cancelled_order_count"] += 1
        order.pending_dispatch -= quantity
        self.cancelled_by_order_id[order_id] = self.cancelled_by_order_id.get(order_id, 0) + quantity
        self.totals[order.route]["cancelled"] += quantity
        if not order.pending_dispatch:
            self.dispatch_queues[order.route].remove(order)
            if not order.in_transit:
                del self.active_orders[order.route][order_id]
        self.record_event("cancelled", order, quantity=quantity)

    def inventory_position(self, route):
        if self._decision_position and route == "A_B" and self.policy == "R1":
            spec = self.config["routes"][route]
            _, transit = self.balances(route)
            return effective_supply_position(self.stock[spec["buyer"]][spec["commodity"]], transit,
                                             self.classification(route), self.policy)
        return super().inventory_position(route)

    def procure(self, buyer, known_candidates):
        # This fixture has one inbound chain per buyer. Only B coal is treated;
        # C steel retains its original procurement rule, with promises observed.
        route = "A_B" if buyer == "B" else "B_C"
        classified = self.classification(route)
        for order_id, quantity in classified["overdue_orders"]:
            if order_id not in self.breached:
                self.breached.add(order_id)
                self.totals[route]["breach_count"] += 1
                self.totals[route]["breach_qty"] += quantity
                self._record_commitment_event("promise_breach", self.orders[order_id], quantity)
        cancelled_today = 0
        if buyer == "B":
            self.decision = {"day": self.day, "pre_disposition_ledger_position": super().inventory_position(route),
                             "pre_disposition_overdue_pending": classified["overdue_pending_qty"],
                             "pre_disposition_overdue_order_count": classified["overdue_order_count"]}
            cancellations = disposition_decisions(classified, self.policy)
            for order_id, quantity in cancellations:
                self.cancel_pending(order_id, quantity)
                cancelled_today += quantity
            pending, transit = self.balances(route)
            classified = self.classification(route)
            self.decision.update(
                decision_ledger_position=self.stock["B"]["coal"] + pending + transit,
                decision_effective_position=effective_supply_position(self.stock["B"]["coal"], transit, classified, self.policy),
                cancelled_qty_today=cancelled_today,
                orders_cancelled_today=len(cancellations),
            )
            self.decision["replenishment_gap"] = max(0, self.config["replenishment"]["B"]["target"] - self.decision["decision_effective_position"])
        self._decision_position = buyer == "B"
        try:
            result = super().procure(buyer, known_candidates)
        finally:
            self._decision_position = False
        if buyer == "B":
            self.decision["new_order_qty_today"] = result[0]
            self.decision["reorder_count_today"] = int(cancelled_today > 0 and result[0] > 0)
            self.totals[route]["reorder_count"] += self.decision["reorder_count_today"]
        return result

    def observe_day(self, scan_visits_before=0):
        pending, transit = self.balances("A_B")
        classification = self.classification("A_B")
        totals = self.totals["A_B"]
        row = {**self.decision, "on_hand": self.stock["B"]["coal"], "in_transit": transit,
               "pending_dispatch": pending, "delivered": totals["delivered"], "cancelled": totals["cancelled"],
               "ledger_inventory_position": super().inventory_position("A_B"),
               "effective_supply_position": effective_supply_position(self.stock["B"]["coal"], transit, classification, self.policy),
               **{k: v for k, v in classification.items() if k != "overdue_orders"},
               "promise_breach_order_count": totals["breach_count"], "promise_breach_qty": totals["breach_qty"],
               "cumulative_ordered": totals["ordered"], "order_count": totals["order_count"],
               "reorder_count": totals["reorder_count"], "supplier_queue": len(self.dispatch_queues["A_B"]),
               "active_orders": len(self.active_orders["A_B"]), "active_scan_visits": self.active_scan_visits,
               "order_scan_visits_today": self.active_scan_visits - scan_visits_before,
               "cancelled_order_count": totals["cancelled_order_count"],
               "B_C_promise_breach_count": self.totals["B_C"]["breach_count"],
               "order_residual": self.route_order_residuals["A_B"]}
        self.decision_rows.append(row)
        return row

    def check_accounts(self):
        result = super().check_accounts()
        for route, totals in self.totals.items():
            pending, transit = self.balances(route)
            self.route_order_residuals[route] = order_residual(totals["ordered"], pending, transit,
                                                             totals["delivered"], totals["cancelled"])
            require(self.route_order_residuals[route] == 0,
                    f"route cancellation ledger identity: {route}")
        return result
