"""Candidate target and read-only conditional coverage using buyer-local facts."""


def _integer(value, name, minimum):
    if type(value) is not int or value < minimum:
        raise ValueError(f"{name} must be an integer >= {minimum}")


def replenishment_target(planned_daily_input, known_transit_days, buffer_days=2):
    """Units: units/day * (transit days + buffer days) = integer units.

    The plan is given externally, not inferred from constrained actual production.
    Known transit time excludes unscheduled supplier/transport queues.
    """
    _integer(planned_daily_input, "planned_daily_input", 0)
    _integer(known_transit_days, "known_transit_days", 1)
    _integer(buffer_days, "buffer_days", 0)
    return planned_daily_input * (known_transit_days + buffer_days)


def coverage_diagnostic(day, on_hand, pending_orders, dispatched_shipments,
                        planned_daily_input, known_transit_days, horizon_extra_days=2):
    """Pure snapshot diagnostic; no Simulation, scenario, or future capacity input.

    pending_orders: mappings with ordered_day and pending_dispatch.
    dispatched_shipments: mappings with quantity and arrival_day.
    Only already-dispatched shipments have ETAs. Negative projections are a
    conditional gap assuming NO future dispatch; they are not actual stock.
    """
    _integer(day, "day", 0)
    _integer(on_hand, "on_hand", 0)
    _integer(planned_daily_input, "planned_daily_input", 1)
    _integer(known_transit_days, "known_transit_days", 1)
    _integer(horizon_extra_days, "horizon_extra_days", 0)
    waiting = {}
    eta = {}
    for order in pending_orders:
        _integer(order["ordered_day"], "ordered_day", 0)
        _integer(order["pending_dispatch"], "pending_dispatch", 0)
        age = day - order["ordered_day"]
        if age < 0:
            raise ValueError("order date is in the future")
        if order["pending_dispatch"]:
            waiting[age] = waiting.get(age, 0) + order["pending_dispatch"]
    for shipment in dispatched_shipments:
        _integer(shipment["quantity"], "shipment quantity", 1)
        _integer(shipment["arrival_day"], "arrival_day", day + 1)
        arrival = shipment["arrival_day"]
        eta[arrival] = eta.get(arrival, 0) + shipment["quantity"]
    horizon = known_transit_days + horizon_extra_days
    balance = on_hand
    projection = {}
    first_gap = None
    covered_days = horizon
    for offset in range(1, horizon + 1):
        arrival_day = day + offset
        balance += eta.get(arrival_day, 0) - planned_daily_input
        projection[arrival_day] = balance
        if balance < 0 and first_gap is None:
            first_gap = arrival_day
            covered_days = offset - 1
    pending, transit = sum(waiting.values()), sum(eta.values())
    return {
        "day": day, "on_hand": on_hand, "pending_dispatch": pending,
        "in_transit": transit, "inventory_position": on_hand + pending + transit,
        "planned_daily_input": planned_daily_input, "known_transit_days": known_transit_days,
        "horizon_days": horizon, "on_hand_coverage_days": on_hand / planned_daily_input,
        "dispatched_eta_buckets": dict(sorted(eta.items())),
        "pending_wait_age_buckets": dict(sorted(waiting.items())),
        "oldest_pending_age_days": max(waiting, default=None),
        "conditional_projected_balance": projection,
        "conditional_first_shortfall_day": first_gap,
        "conditional_covered_days": covered_days,
        "conditional_covered_planned_units": covered_days * planned_daily_input,
        "conditional_net_units_by_horizon": on_hand + sum(
            q for arrival, q in eta.items() if arrival <= day + horizon),
    }
