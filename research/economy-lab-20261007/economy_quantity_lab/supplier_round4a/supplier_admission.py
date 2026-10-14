"""Transport-only admission and confirmed cancellation; settlement stays inherited."""
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "order_round3"))
from commitment_adapter import CommitmentSimulation
from economy import Simulation


def integer(value, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError("expected nonnegative integer")
    return value


@dataclass(frozen=True)
class PurchaseRequest:
    request_id: int
    buyer_id: str
    supplier_id: str
    commodity: str
    requested_quantity: int
    request_day: int


class TransportSlots:
    """Current-capacity quotes, shared reservations, earliest day first.

    Capacity changes never rewrite old promises. Existing occupancy greater than
    a new quote yields zero remaining on that day. Expired reservations cease to
    occupy the prospective window; their orders remain real and may breach.
    """
    def __init__(self, horizon=2):
        self.horizon = integer(horizon)
        self.committed = defaultdict(int)
        self.allocations = {}
        self.scan_visits = 0
        self.used_today = defaultdict(int)

    def quote(self, day, capacity):
        integer(day); integer(capacity)
        for old in list(self.committed):
            self.scan_visits += 1
            if old < day:
                del self.committed[old]
        result = []
        for slot in range(day, day + self.horizon + 1):
            self.scan_visits += 1
            committed = self.committed.get(slot, 0)
            dispatched = self.used_today.get(slot, 0)
            result.append(dict(day=slot, slot_capacity=capacity, committed_quantity=committed,
                               dispatched_quantity=dispatched,
                               remaining_slot=max(0, capacity - committed - dispatched)))
        return result

    def dispatched(self, day, quantity):
        self.used_today = defaultdict(int, {day: self.used_today.get(day, 0) + quantity})

    def reserve(self, order_id, quantity, quote):
        integer(quantity, 1)
        if quantity > sum(s["remaining_slot"] for s in quote):
            raise ValueError("ATP exceeded")
        allocation = {}
        remaining = quantity
        for slot in quote:
            q = min(remaining, slot["remaining_slot"])
            if q:
                allocation[slot["day"]] = q
                self.committed[slot["day"]] += q
                assert self.committed[slot["day"]] <= slot["slot_capacity"]
                remaining -= q
        assert remaining == 0
        self.allocations[order_id] = allocation

    def release(self, order_id, quantity):
        allocation = self.allocations.get(order_id, {})
        for day in list(allocation):
            self.scan_visits += 1
            q = min(quantity, allocation[day])
            allocation[day] -= q
            if day in self.committed:
                self.committed[day] -= q
                if not self.committed[day]:
                    del self.committed[day]
            quantity -= q
            if not allocation[day]:
                del allocation[day]
        if not allocation:
            self.allocations.pop(order_id, None)


class AdmissionSimulation(CommitmentSimulation):
    def __init__(self, config, scenario="experiment", admission="S0", confirmation_delay=1):
        if admission not in ("S0", "S1"):
            raise ValueError("unknown admission policy")
        self.admission = admission
        self.confirmation_delay = integer(confirmation_delay, 1)
        self.slots = TransportSlots(2)
        self.requests = []
        self.cancel_requests = {}
        self.cancel_history = []
        self.decision_need = 0
        # R2 supplies the cancellation-aware Order representation, while this
        # adapter replaces its immediate-disposition procurement hook entirely.
        super().__init__(config, scenario, policy="R2", promise_window_days=2)

    def open_procurement_need(self):
        return max(0, self.config["replenishment"]["B"]["target"] -
                   Simulation.inventory_position(self, "A_B"))

    def request(self, quantity):
        integer(quantity, 1)
        spec = self.config["routes"]["A_B"]
        request = PurchaseRequest(len(self.requests) + 1, spec["buyer"], spec["supplier"],
                                  spec["commodity"], quantity, self.day)
        quote = self.slots.quote(self.day, self.capacity("A_B", self.day))
        atp = sum(s["remaining_slot"] for s in quote)
        accepted = quantity if self.admission == "S0" else min(quantity, atp)
        order = self.accept_order("A_B", accepted) if accepted else None
        if order and self.admission == "S1":
            self.slots.reserve(order.id, accepted, quote)
        response = {**vars(request), "accepted_quantity": accepted,
                    "rejected_quantity": quantity - accepted, "acceptance_day": self.day,
                    "rejection_reason": "TRANSPORT_ATP" if accepted < quantity else None,
                    "promised_dispatch_by_day": self.day + 2 if order else None,
                    "promised_quantity": accepted, "order_id": order.id if order else None,
                    "ATP": atp, "slots_before": quote,
                    "slots_after": self.slots.quote(self.day, self.capacity("A_B", self.day))}
        assert quantity == accepted + response["rejected_quantity"]
        self.requests.append(response)
        return response

    def record_event(self, event, order, shipment=None, quantity=0):
        super().record_event(event, order, shipment, quantity)
        if order.route == "A_B" and event in ("dispatched", "cancelled"):
            self.slots.release(order.id, quantity)
            if event == "dispatched":
                self.slots.dispatched(self.day, quantity)

    def cancel_pending(self, order_id, quantity):
        raise ValueError("use request_cancellation; immediate cancellation is disabled")

    def request_cancellation(self, order_id, quantity):
        integer(order_id, 1); integer(quantity, 1)
        order = self.orders[order_id]
        if order.route != "A_B" or quantity > order.pending_dispatch or order_id in self.cancel_requests:
            raise ValueError("invalid or duplicate cancellation request")
        record = dict(order_id=order_id, state="CANCEL_REQUESTED", request_day=self.day,
                      confirm_day=self.day + self.confirmation_delay, requested_cancel_qty=quantity,
                      pending_at_request=order.pending_dispatch,
                      confirmed_cancel_qty=0, no_longer_cancellable_qty=0,
                      confirmation_delay=self.confirmation_delay)
        self.cancel_requests[order_id] = record
        self.cancel_history.append(dict(record))
        return record

    def confirm_cancellations(self):
        for order_id, record in list(self.cancel_requests.items()):
            if self.day < record["confirm_day"]:
                continue
            order = self.orders[order_id]
            # Requested units are the front of the pending balance. Shipments
            # in the waiting interval consume that cancellable request first.
            sent = record["pending_at_request"] - order.pending_dispatch
            unavailable = min(record["requested_cancel_qty"], sent)
            confirmed = record["requested_cancel_qty"] - unavailable
            assert 0 <= confirmed <= order.pending_dispatch
            if confirmed:
                super().cancel_pending(order_id, confirmed)
            record.update(state="CANCEL_CONFIRMED", confirmed_cancel_qty=confirmed,
                          no_longer_cancellable_qty=unavailable)
            self.cancel_history.append(dict(record))
            del self.cancel_requests[order_id]

    def procure(self, buyer, known_candidates):
        if buyer == "B":
            self.confirm_cancellations()
        route = "A_B" if buyer == "B" else "B_C"
        classified = self.classification(route)
        for oid, qty in classified["overdue_orders"]:
            if oid not in self.breached:
                self.breached.add(oid)
                self.totals[route]["breach_count"] += 1
                self.totals[route]["breach_qty"] += qty
                self._record_commitment_event("promise_breach", self.orders[oid], qty)
        if buyer != "B":
            return Simulation.procure(self, buyer, known_candidates)
        self.decision_need = self.open_procurement_need()
        if not self.decision_need:
            return 0, 0
        if self.config["routes"]["A_B"]["supplier"] not in known_candidates:
            return 0, self.decision_need
        result = self.request(self.decision_need)
        return result["accepted_quantity"], result["rejected_quantity"]

    def observe_admission(self):
        pending, transit = self.balances("A_B")
        classification = self.classification("A_B")
        quote = self.slots.quote(self.day, self.capacity("A_B", self.day))
        today = [r for r in self.requests if r["request_day"] == self.day]
        # Deliberately count this archival scan, rather than claiming active-only cost.
        requested = sum(r["requested_quantity"] for r in today)
        accepted = sum(r["accepted_quantity"] for r in today)
        totals = self.totals["A_B"]
        cancels = [c for c in self.cancel_history if c["confirm_day"] == self.day and c["state"] == "CANCEL_CONFIRMED"]
        return dict(decision_open_need=self.decision_need, open_procurement_need=self.open_procurement_need(),
                    on_hand=self.stock["B"]["coal"], live_accepted_pending=pending, in_transit=transit,
                    ledger_inventory_position=Simulation.inventory_position(self, "A_B"),
                    requested_qty=requested, accepted_qty=accepted, rejected_qty=requested-accepted,
                    request_count=len(today), ATP=sum(s["remaining_slot"] for s in quote),
                    total_slot_capacity=sum(s["slot_capacity"] for s in quote),
                    committed_quantity=sum(s["committed_quantity"] for s in quote),
                    remaining_slot=sum(s["remaining_slot"] for s in quote),
                    promised_quantity=totals["ordered"], ordered=totals["ordered"],
                    delivered=totals["delivered"], cancelled=totals["cancelled"],
                    breach_count=totals["breach_count"], breach_quantity=totals["breach_qty"],
                    overdue_pending=classification["overdue_pending_qty"],
                    active_requests=0, active_cancel_requests=len(self.cancel_requests), active_orders=len(self.active_orders["A_B"]),
                    slot_entries=len(self.slots.committed), allocation_entries=len(self.slots.allocations),
                    order_scan_visits=self.active_scan_visits, slot_scan_visits=self.slots.scan_visits,
                    request_archive_scan_visits=len(self.requests), cancellation_scan_visits=len(self.cancel_history),
                    cancel_requested_qty=sum(c["requested_cancel_qty"] for c in self.cancel_history if c["state"]=="CANCEL_REQUESTED" and c["request_day"]==self.day),
                    confirmed_cancel_qty=sum(c["confirmed_cancel_qty"] for c in cancels),
                    no_longer_cancellable_qty=sum(c["no_longer_cancellable_qty"] for c in cancels),
                    confirmation_delay=self.confirmation_delay,
                    order_residual=self.route_order_residuals["A_B"])
