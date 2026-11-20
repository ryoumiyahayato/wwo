"""Deterministic quantity model. No CSV, game runtime, or financial mechanisms."""
from collections import deque
from copy import deepcopy
from dataclasses import dataclass, field
import heapq


GOODS = ("coal", "steel", "machine")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


@dataclass
class Shipment:
    id: int
    order_id: int
    route: str
    quantity: int
    dispatch_day: int
    arrival_day: int
    received_day: int | None = None


@dataclass
class Order:
    id: int
    route: str
    day: int
    quantity: int
    pending_dispatch: int
    delivered: int = 0
    active_shipments: dict = field(default_factory=dict)

    @property
    def in_transit(self):
        return sum(s.quantity for s in self.active_shipments.values())

    def check(self):
        require(min(self.pending_dispatch, self.delivered, self.in_transit) >= 0,
                f"negative order balance: {self.id}")
        require(self.quantity == self.pending_dispatch + self.in_transit + self.delivered,
                f"order identity: {self.id}")


class Simulation:
    def __init__(self, config, scenario):
        self.config = deepcopy(config)
        self.scenario = scenario
        self.stock = deepcopy(config["initial_inventory"])
        self.initial = {g: sum(v[g] for v in self.stock.values()) for g in GOODS}
        self.day = 0
        self.backlog = 0
        self.cumulative = dict(coal_mined=0, steel_produced=0,
                               machine_produced=0, terminal_delivered=0)
        self.orders = {}  # Archive is used for export, never to update daily totals.
        self.shipments = []
        self.active_orders = {r: {} for r in config["routes"]}
        self.dispatch_queues = {r: deque() for r in config["routes"]}
        self.arrivals = []  # Heap contains only undelivered shipments.
        self.events = []
        self.rows = []
        self.check_accounts()

    def capacity(self, route, day):
        capacity = self.config["routes"][route]["capacity"]
        for interval in self.config["scenarios"][self.scenario].get(route, []):
            if interval["first_day"] <= day <= interval["last_day"]:
                capacity = interval["capacity"]
        return capacity

    def balances(self, route):
        orders = self.active_orders[route].values()
        pending = transit = 0
        for order in orders:
            pending += order.pending_dispatch
            transit += order.in_transit
        return pending, transit

    def inventory_position(self, route):
        r = self.config["routes"][route]
        pending, transit = self.balances(route)
        return self.stock[r["buyer"]][r["commodity"]] + pending + transit

    def record_event(self, event, order, shipment=None, quantity=0):
        order.check()
        self.events.append({
            "day": self.day, "event": event, "route": order.route,
            "order_id": order.id, "ordered_day": order.day,
            "ordered_quantity": order.quantity,
            "shipment_id": shipment.id if shipment else "",
            "quantity": quantity,
            "dispatch_day": shipment.dispatch_day if shipment else "",
            "arrival_day": shipment.arrival_day if shipment else "",
            "pending_dispatch": order.pending_dispatch,
            "in_transit": order.in_transit, "delivered": order.delivered,
        })

    def accept_order(self, route, quantity):
        require(isinstance(quantity, int) and quantity > 0, "invalid order")
        order = Order(len(self.orders) + 1, route, self.day, quantity, quantity)
        self.orders[order.id] = order
        self.active_orders[route][order.id] = order
        self.dispatch_queues[route].append(order)
        self.record_event("accepted", order, quantity=quantity)
        return order

    def procure(self, buyer, known_candidates):
        """Only the supplied known list is considered; no entity scan for sellers."""
        rule = self.config["replenishment"][buyer]
        routes = self.config["routes"]
        inbound = [name for name, r in routes.items()
                   if r["buyer"] == buyer and r["commodity"] == rule["commodity"]]
        require(len(inbound) == 1, "fixture needs exactly one inbound route")
        route = inbound[0]
        quantity = max(0, rule["target"] - self.inventory_position(route))
        if not quantity:
            return 0, 0
        # This fixture tests candidate scope, not multi-supplier matching.
        for candidate in known_candidates:
            if candidate == routes[route]["supplier"]:
                self.accept_order(route, quantity)
                return quantity, 0
        return 0, quantity

    def receive(self):
        arrived = {r: 0 for r in self.config["routes"]}
        while self.arrivals and self.arrivals[0][0] <= self.day:
            _, _, shipment = heapq.heappop(self.arrivals)
            require(shipment.arrival_day == self.day, "late/early arrival scheduler")
            require(shipment.received_day is None, "duplicate arrival")
            require(shipment.arrival_day > shipment.dispatch_day, "same-day arrival")
            order = self.active_orders[shipment.route][shipment.order_id]
            require(order.active_shipments.pop(shipment.id) is shipment,
                    "missing active shipment")
            r = self.config["routes"][shipment.route]
            self.stock[r["buyer"]][r["commodity"]] += shipment.quantity
            order.delivered += shipment.quantity
            shipment.received_day = self.day
            arrived[shipment.route] += shipment.quantity
            self.record_event("arrived", order, shipment, shipment.quantity)
            if order.delivered == order.quantity:
                del self.active_orders[shipment.route][order.id]
        return arrived

    def production_plan(self):
        p = self.config["production"]
        steel_pending = sum(self.balances(r)[0] for r, spec in self.config["routes"].items()
                            if spec["supplier"] == "B" and spec["commodity"] == "steel")
        desired_b = max(0, p["B"]["steel_target"] + steel_pending - self.stock["B"]["steel"])
        desired_c = max(0, self.backlog - self.stock["C"]["machine"])
        return {
            "A": min(p["A"]["capacity"], max(0, p["A"]["coal_target"] - self.stock["A"]["coal"])),
            "B": min(p["B"]["capacity"], self.stock["B"]["coal"] // p["B"]["coal_per_steel"], desired_b),
            "C": min(p["C"]["capacity"], self.stock["C"]["steel"] // p["C"]["steel_per_machine"], desired_c),
        }

    def produce(self, plan):
        p = self.config["production"]
        for site, quantity in plan.items():
            require(0 <= quantity <= p[site]["capacity"], "production capacity")
        coal_input = p["B"]["coal_per_steel"] * plan["B"]
        steel_input = p["C"]["steel_per_machine"] * plan["C"]
        require(coal_input <= self.stock["B"]["coal"], "insufficient coal")
        require(steel_input <= self.stock["C"]["steel"], "insufficient steel")
        self.stock["A"]["coal"] += plan["A"]
        self.stock["B"]["coal"] -= coal_input
        self.stock["B"]["steel"] += plan["B"]
        self.stock["C"]["steel"] -= steel_input
        self.stock["C"]["machine"] += plan["C"]
        self.cumulative["coal_mined"] += plan["A"]
        self.cumulative["steel_produced"] += plan["B"]
        self.cumulative["machine_produced"] += plan["C"]

    def dispatch(self):
        dispatched = {}
        for route, r in self.config["routes"].items():
            remaining = self.capacity(route, self.day)
            require(remaining >= 0 and r["lead_time"] >= 1, "invalid transport config")
            before = self.stock[r["supplier"]][r["commodity"]]
            total = 0
            queue = self.dispatch_queues[route]
            while queue and remaining and self.stock[r["supplier"]][r["commodity"]]:
                order = queue[0]
                order.check()
                quantity = min(order.pending_dispatch, remaining,
                               self.stock[r["supplier"]][r["commodity"]])
                shipment = Shipment(len(self.shipments) + 1, order.id, route, quantity,
                                    self.day, self.day + r["lead_time"])
                self.stock[r["supplier"]][r["commodity"]] -= quantity
                order.pending_dispatch -= quantity
                order.active_shipments[shipment.id] = shipment
                self.shipments.append(shipment)
                heapq.heappush(self.arrivals, (shipment.arrival_day, shipment.id, shipment))
                remaining -= quantity
                total += quantity
                self.record_event("dispatched", order, shipment, quantity)
                if order.pending_dispatch == 0:
                    queue.popleft()
            require(total <= self.capacity(route, self.day), "dispatch capacity")
            require(before - self.stock[r["supplier"]][r["commodity"]] == total,
                    "dispatch debit differs from shipment quantity")
            dispatched[route] = total
        return dispatched

    def check_accounts(self):
        require(self.backlog >= 0, "negative terminal backlog")
        require(all(isinstance(q, int) and q >= 0 for stock in self.stock.values()
                    for q in stock.values()), "negative/noninteger stock")
        transit = {g: 0 for g in GOODS}
        for route, orders in self.active_orders.items():
            for order in orders.values():
                order.check()
                for shipment in order.active_shipments.values():
                    require(shipment.quantity > 0 and shipment.received_day is None,
                            "invalid active shipment")
                    require(shipment.dispatch_day <= self.day < shipment.arrival_day,
                            "active shipment outside transit interval")
                    transit[self.config["routes"][route]["commodity"]] += shipment.quantity
        p, c = self.config["production"], self.cumulative
        expected = {
            "coal": self.initial["coal"] + c["coal_mined"] - p["B"]["coal_per_steel"] * c["steel_produced"],
            "steel": self.initial["steel"] + c["steel_produced"] - p["C"]["steel_per_machine"] * c["machine_produced"],
            "machine": self.initial["machine"] + c["machine_produced"] - c["terminal_delivered"],
        }
        residuals = {g: sum(s[g] for s in self.stock.values()) + transit[g] - expected[g]
                     for g in GOODS}
        require(all(v == 0 for v in residuals.values()), f"quantity residual: {residuals}")
        require(self.day * self.config["daily_terminal_demand"] ==
                self.backlog + c["terminal_delivered"], "terminal order identity")
        return residuals

    def step(self):
        self.day += 1
        arrivals = self.receive()
        self.backlog += self.config["daily_terminal_demand"]
        plan = self.production_plan()  # All plans use the same pre-production state.
        self.produce(plan)
        delivered = min(self.stock["C"]["machine"], self.backlog)
        self.stock["C"]["machine"] -= delivered
        self.backlog -= delivered
        self.cumulative["terminal_delivered"] += delivered
        new_orders, failed = {}, {}
        for buyer, rule in self.config["replenishment"].items():
            new_orders[buyer], failed[buyer] = self.procure(buyer, rule["known_suppliers"])
        dispatched = self.dispatch()
        residuals = self.check_accounts()
        row = {"day": self.day}
        for site, stock in self.stock.items():
            row.update({f"{site}_{good}_on_hand": stock[good] for good in GOODS})
        row.update({f"production_{site}": plan[site] for site in plan})
        for route, r in self.config["routes"].items():
            pending, transit = self.balances(route)
            row.update({f"{route}_capacity": self.capacity(route, self.day),
                        f"{route}_dispatch": dispatched[route], f"{route}_arrival": arrivals[route],
                        f"{route}_pending_dispatch": pending, f"{route}_in_transit": transit,
                        f"{route}_new_order": new_orders[r["buyer"]],
                        f"{route}_unprocured": failed[r["buyer"]],
                        f"{route}_inventory_position": self.inventory_position(route)})
        row.update(terminal_backlog=self.backlog, terminal_delivery=delivered)
        row.update({f"cumulative_{k}": v for k, v in self.cumulative.items()})
        row.update({f"{g}_residual": residuals[g] for g in GOODS})
        self.rows.append(row)
        return row

    def run(self, days=None):
        for _ in range(self.config["days"] if days is None else days):
            self.step()
        return self
