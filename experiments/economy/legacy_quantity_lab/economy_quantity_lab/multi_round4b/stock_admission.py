"""S2: current stock and shared transport slots, with no production forecast."""
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "supplier_round4a"))
from supplier_admission import AdmissionSimulation, TransportSlots, PurchaseRequest, integer


@dataclass(frozen=True)
class SupplierOffer:
    supplier_id: str
    commodity: str
    offer_day: int
    max_acceptable_quantity: int
    promised_dispatch_by_day: int
    route_lead_time: int
    expected_arrival_day: int
    supply_basis: str = "STOCK_CONFIRMED"


class StockCommitments:
    """One stock pool per supplier/commodity, shared across requests and routes."""
    def __init__(self):
        self.totals = defaultdict(int)
        self.entries = {}

    def uncommitted(self, supplier, commodity, on_hand):
        integer(on_hand)
        return max(0, on_hand - self.totals[(supplier, commodity)])

    def reserve(self, order_id, supplier, commodity, quantity, on_hand):
        integer(quantity, 1)
        if order_id in self.entries or quantity > self.uncommitted(supplier, commodity, on_hand):
            raise ValueError("stock overcommit or duplicate reservation")
        self.entries[order_id] = [supplier, commodity, quantity]
        self.totals[(supplier, commodity)] += quantity

    def release(self, order_id, quantity):
        if order_id not in self.entries or not 0 < quantity <= self.entries[order_id][2]:
            raise ValueError("release exceeds stock commitment")
        supplier, commodity, _ = self.entries[order_id]
        self.entries[order_id][2] -= quantity
        self.totals[(supplier, commodity)] -= quantity
        if not self.entries[order_id][2]:
            del self.entries[order_id]

    def check(self, stocks):
        for (supplier, commodity), quantity in self.totals.items():
            assert 0 <= quantity <= stocks[supplier][commodity], "stock commitment exceeds current stock"


class StockConfirmedSimulation(AdmissionSimulation):
    """Single-supplier S2 gate and common admission seam for the later adapter."""
    def __init__(self, config, scenario="experiment"):
        self.stock_commitments = StockCommitments()
        self.requests_by_day = defaultdict(list)
        self.cancel_by_day = defaultdict(list)
        self.offer_evaluations = 0
        self.stock_account_visits = 0
        super().__init__(config, scenario, admission="S1")
        self.route_slots = {"A_B": self.slots}
        self.supplier_routes = {"A": "A_B"}

    def offer(self, supplier_id):
        route = self.supplier_routes[supplier_id]
        spec = self.config["routes"][route]
        self.offer_evaluations += 1
        quote = self.route_slots[route].quote(self.day, self.capacity(route, self.day))
        transport = sum(s["remaining_slot"] for s in quote)
        free = self.stock_commitments.uncommitted(supplier_id, spec["commodity"], self.stock[supplier_id][spec["commodity"]])
        return SupplierOffer(supplier_id, spec["commodity"], self.day, min(transport, free),
                             self.day + 2, spec["lead_time"], self.day + 2 + spec["lead_time"])

    def request(self, quantity, supplier_id="A"):
        integer(quantity, 1)
        route = self.supplier_routes[supplier_id]
        spec = self.config["routes"][route]
        slots = self.route_slots[route]
        quote = slots.quote(self.day, self.capacity(route, self.day))
        transport = sum(s["remaining_slot"] for s in quote)
        on_hand = self.stock[supplier_id][spec["commodity"]]
        free = self.stock_commitments.uncommitted(supplier_id, spec["commodity"], on_hand)
        accepted = min(quantity, transport, free)
        request = PurchaseRequest(len(self.requests) + 1, spec["buyer"], supplier_id,
                                  spec["commodity"], quantity, self.day)
        order = self.accept_order(route, accepted) if accepted else None
        if order:
            slots.reserve(order.id, accepted, quote)
            self.stock_commitments.reserve(order.id, supplier_id, spec["commodity"], accepted, on_hand)
        response = {**vars(request), "accepted_quantity": accepted, "rejected_quantity": quantity - accepted,
                    "acceptance_day": self.day, "order_id": order.id if order else None,
                    "rejection_reason": "STOCK_OR_TRANSPORT_ATP" if accepted < quantity else None,
                    "promised_dispatch_by_day": self.day + 2 if order else None,
                    "promised_quantity": accepted, "supply_basis": "STOCK_CONFIRMED",
                    "transport_atp": transport, "uncommitted_sellable_stock": free,
                    "stock_confirmed_atp": min(transport, free), "stock_on_hand": on_hand,
                    "rejected_due_transport": max(0, quantity - transport),
                    "rejected_due_stock": min(quantity, transport) - accepted,
                    "stock_committed_after": self.stock_commitments.totals[(supplier_id, spec["commodity"])],
                    "stock_commitment_entries_after": len(self.stock_commitments.entries),
                    "slot_entries_after": sum(len(s.committed) for s in self.route_slots.values()),
                    "slots_before": quote, "slots_after": slots.quote(self.day, self.capacity(route, self.day))}
        assert quantity == accepted + response["rejected_quantity"]
        self.requests.append(response)
        self.requests_by_day[self.day].append(response)
        self.stock_commitments.check(self.stock)
        return response

    def record_event(self, event, order, shipment=None, quantity=0):
        super().record_event(event, order, shipment, quantity)
        if order.route in getattr(self, "route_slots", {}) and event in ("dispatched", "cancelled"):
            if order.route != "A_B":
                slots = self.route_slots[order.route]
                slots.release(order.id, quantity)
                if event == "dispatched":
                    slots.dispatched(self.day, quantity)
            self.stock_commitments.release(order.id, quantity)
            self.stock_commitments.check(self.stock)

    def request_cancellation(self, order_id, quantity):
        # Reuse the exact Round4A state/quantity semantics for the primary route.
        record = super().request_cancellation(order_id, quantity)
        self.cancel_by_day[self.day].append(dict(record))
        return record

    def confirm_cancellations(self):
        first = len(self.cancel_history)
        super().confirm_cancellations()
        for record in self.cancel_history[first:]:
            self.cancel_by_day[self.day].append(dict(record))

    def check_accounts(self):
        result = super().check_accounts()
        self.stock_commitments.check(self.stock)
        self.stock_account_visits += len(self.stock_commitments.totals)
        for (supplier, commodity), quantity in self.stock_commitments.totals.items():
            routes = [r for r in getattr(self, "route_slots", {})
                      if self.config["routes"][r]["supplier"] == supplier and self.config["routes"][r]["commodity"] == commodity]
            assert quantity == sum(self.balances(r)[0] for r in routes), "stock commitment differs from live pending"
        for oid, (_, _, quantity) in self.stock_commitments.entries.items():
            self.stock_account_visits += 1
            assert quantity == self.orders[oid].pending_dispatch
        return result
