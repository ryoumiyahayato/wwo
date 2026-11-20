"""Buyer-local commitment facts and explicit disposition; no scenario access."""
from dataclasses import dataclass


def integer(value, name, minimum=0):
    if type(value) is not int or value < minimum:
        raise ValueError(f"{name} must be an integer >= {minimum}")


@dataclass(frozen=True)
class Commitment:
    accepted_day: int
    promise_window_days: int | None
    promised_dispatch_by_day: int | None


def make_commitment(accepted_day, promise_window_days=2):
    integer(accepted_day, "accepted_day")
    if promise_window_days is not None:
        integer(promise_window_days, "promise_window_days")
    return Commitment(accepted_day, promise_window_days,
                      None if promise_window_days is None else accepted_day + promise_window_days)


def promise_status(day, pending_quantity, commitment):
    """Derived status of the still-pending part, never a fabricated cargo ETA."""
    integer(day, "day")
    integer(pending_quantity, "pending quantity")
    if commitment.accepted_day > day:
        raise ValueError("future acceptance fact")
    if not pending_quantity:
        return "NO_PENDING"
    deadline = commitment.promised_dispatch_by_day
    if deadline is None:
        return "UNPROMISED"
    if day > deadline:
        return "OVERDUE"
    return "DUE" if day == deadline else "PROMISED"


def classify_pending(day, pending_facts):
    """Facts are (order_id, pending quantity, immutable explicit commitment).

    The deadline day remains due through its final dispatch opportunity. Unpromised
    balances never become overdue by age. Already dispatched cargo is absent here.
    """
    integer(day, "day")
    promised = unpromised = overdue = oldest = 0
    overdue_orders = []
    due_count = promised_count = unpromised_count = 0
    for order_id, quantity, commitment in pending_facts:
        integer(order_id, "order_id", 1)
        integer(quantity, "pending quantity")
        status = promise_status(day, quantity, commitment)
        if not quantity:
            continue
        deadline = commitment.promised_dispatch_by_day
        if status == "UNPROMISED":
            unpromised += quantity
            unpromised_count += 1
        elif status == "OVERDUE":
            overdue += quantity
            oldest = max(oldest, day - deadline)
            overdue_orders.append((order_id, quantity))
        else:
            promised += quantity
            promised_count += 1
            due_count += int(status == "DUE")
    return {"pending_promised_qty": promised, "pending_unpromised_qty": unpromised,
            "overdue_pending_qty": overdue, "oldest_overdue_days": oldest,
            "overdue_order_count": len(overdue_orders), "due_order_count": due_count,
            "promised_order_count": promised_count, "unpromised_order_count": unpromised_count,
            "overdue_orders": tuple(overdue_orders)}


def effective_supply_position(on_hand, in_transit, classification, policy):
    integer(on_hand, "on_hand")
    integer(in_transit, "in_transit")
    if policy not in ("R0", "R1", "R2"):
        raise ValueError("unknown policy")
    pending = classification["pending_promised_qty"] + classification["pending_unpromised_qty"]
    if policy != "R1":
        pending += classification["overdue_pending_qty"]
    return on_hand + in_transit + pending


def disposition_decisions(classification, policy):
    if policy not in ("R0", "R1", "R2"):
        raise ValueError("unknown policy")
    return classification["overdue_orders"] if policy == "R2" else ()


def validate_cancellation(pending, quantity):
    integer(pending, "pending")
    integer(quantity, "cancellation quantity", 1)
    if quantity > pending:
        raise ValueError("cancellation exceeds pending; dispatched/delivered cargo cannot be cancelled")


def order_residual(ordered, pending, in_transit, delivered, cancelled):
    for name, value in (("ordered", ordered), ("pending", pending), ("in_transit", in_transit),
                        ("delivered", delivered), ("cancelled", cancelled)):
        integer(value, name)
    return ordered - pending - in_transit - delivered - cancelled
