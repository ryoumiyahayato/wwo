"""Bounded offer matching on known IDs; original FIFO, receive and step remain."""
from collections import defaultdict
from dataclasses import asdict
from stock_admission import StockConfirmedSimulation, TransportSlots, integer


def ranked_offers(offers):
    """Pure buyer decision: only public offers enter this function."""
    return sorted(offers, key=lambda offer: (offer.expected_arrival_day,
                                           -offer.max_acceptable_quantity, offer.supplier_id))


class InformationInbox:
    """External deterministic information fixture. Only today's events are delivered."""
    def __init__(self, events):
        self.by_day = defaultdict(list)
        for event in events:
            self.by_day[event["day"]].append(dict(event))

    def deliver(self, day):
        return self.by_day.pop(day, [])


class MultiSupplierSimulation(StockConfirmedSimulation):
    def __init__(self, config, matching="M1", information=None):
        if matching not in ("M0", "M1", "M2"):
            raise ValueError("unknown matching policy")
        self.matching = matching
        self.known = set(config["replenishment"]["B"]["known_suppliers"])
        self.available = tuple(config.get("available_supplier_ids", ["A"]))
        self.source_extraction = {"A": 0, "D": 0}
        self.information = information or InformationInbox([])
        self.discoveries = []
        self.discovery_by_day = defaultdict(list)
        self.offers = []
        self.offers_by_day = defaultdict(list)
        self.boundaries = []
        self.boundary_by_day = {}
        self.switch_intents = {}
        self.replacement_tickets = []
        self.switch_events = []
        self.switch_by_day = defaultdict(list)
        self.candidate_scans = 0
        self.daily_export_visits = 0
        super().__init__(config)
        if "D_B" in config["routes"]:
            self.route_slots["D_B"] = TransportSlots(2)
            self.supplier_routes["D"] = "D_B"
        if not self.known.issubset(self.supplier_routes):
            raise ValueError("unknown fixture route for known supplier")

    def production_plan(self):
        plan = super().production_plan()
        if "D" in self.config["production"]:
            rule = self.config["production"]["D"]
            plan["D"] = min(rule["capacity"], max(0, rule["coal_target"] - self.stock["D"]["coal"]))
        return plan

    def produce(self, plan):
        # Original A/B/C recipes and debits are executed once by the old engine.
        super().produce(plan)
        quantity = plan.get("D", 0)
        if "D" in plan:
            self.stock["D"]["coal"] += quantity
            self.cumulative["coal_mined"] += quantity
        self.source_extraction["A"] += plan["A"]
        self.source_extraction["D"] += quantity

    def check_accounts(self):
        residuals = super().check_accounts()
        assert self.cumulative["coal_mined"] == sum(self.source_extraction.values()), "coal source mismatch"
        return residuals

    def global_supply_position(self):
        return self.stock["B"]["coal"] + sum(sum(self.balances(route)) for route in self.supplier_routes.values())

    def open_procurement_need(self):
        return max(0, self.config["replenishment"]["B"]["target"] - self.global_supply_position())

    def offer(self, supplier_id):
        if supplier_id not in self.known:
            raise ValueError("cannot query unknown supplier")
        offer = super().offer(supplier_id)
        row = asdict(offer)
        self.offers.append(row)
        self.offers_by_day[self.day].append(row)
        return offer

    def request(self, quantity, supplier_id="A"):
        if supplier_id not in self.known:
            raise ValueError("cannot request unknown supplier")
        return super().request(quantity, supplier_id)

    def receive_information(self):
        for event in self.information.deliver(self.day):
            if event["supplier_id"] not in self.supplier_routes:
                raise ValueError("discovery has no fixture route")
            self.known.add(event["supplier_id"])
            record = dict(day=self.day, event="SUPPLIER_DISCOVERED", supplier_id=event["supplier_id"],
                          source=event["source"])
            self.discoveries.append(record)
            self.discovery_by_day[self.day].append(record)

    def request_cancellation(self, order_id, quantity):
        if self.orders[order_id].route == "A_B":
            return super().request_cancellation(order_id, quantity)
        integer(order_id, 1); integer(quantity, 1)
        order = self.orders[order_id]
        if order.route != "D_B" or quantity > order.pending_dispatch or order_id in self.cancel_requests:
            raise ValueError("invalid or duplicate cancellation request")
        # Only the route validation is extended; confirmation is the unchanged
        # Round4A handshake, which already settles the actual order's route.
        record = dict(order_id=order_id, state="CANCEL_REQUESTED", request_day=self.day,
                      confirm_day=self.day + self.confirmation_delay, requested_cancel_qty=quantity,
                      pending_at_request=order.pending_dispatch, confirmed_cancel_qty=0,
                      no_longer_cancellable_qty=0, confirmation_delay=self.confirmation_delay)
        self.cancel_requests[order_id] = record
        self.cancel_history.append(dict(record))
        self.cancel_by_day[self.day].append(dict(record))
        return record

    def log_switch(self, **record):
        row = dict(day=self.day, **record)
        self.switch_events.append(row)
        self.switch_by_day[self.day].append(row)

    def confirm_cancellations(self):
        first = len(self.cancel_history)
        super().confirm_cancellations()
        for cancellation in self.cancel_history[first:]:
            intent = self.switch_intents.pop(cancellation["order_id"], None)
            if intent:
                quantity = cancellation["confirmed_cancel_qty"]
                if quantity:
                    self.replacement_tickets.append(dict(order_id=cancellation["order_id"],
                                                         source=intent["source"], remaining=quantity))
                self.log_switch(event="SWITCH_CONFIRMED", source_supplier=intent["source"],
                                old_order_id=cancellation["order_id"], confirmed_quantity=quantity,
                                no_longer_cancellable_qty=cancellation["no_longer_cancellable_qty"])

    def procure(self, buyer, known_candidates):
        if buyer != "B":
            return super().procure(buyer, known_candidates)
        self.receive_information()
        self.confirm_cancellations()
        overdue = []
        for supplier, route in self.supplier_routes.items():
            classified = self.classification(route)
            for oid, quantity in classified["overdue_orders"]:
                overdue.append((supplier, oid, quantity))
                if oid not in self.breached:
                    self.breached.add(oid)
                    self.totals[route]["breach_count"] += 1
                    self.totals[route]["breach_qty"] += quantity
                    self._record_commitment_event("promise_breach", self.orders[oid], quantity)
        initial_need = self.open_procurement_need()
        first_request = len(self.requests)
        considered = sorted(self.known & {"A"}) if self.matching == "M0" else sorted(self.known)
        if not initial_need and not (self.matching == "M2" and overdue):
            considered = []
        self.candidate_scans += len(considered)
        offers = ranked_offers([self.offer(supplier) for supplier in considered])
        if self.matching == "M2":
            for source, oid, quantity in overdue:
                alternatives = [o for o in offers if o.supplier_id != source and o.max_acceptable_quantity > 0]
                if alternatives and oid not in self.cancel_requests:
                    self.request_cancellation(oid, quantity)
                    self.switch_intents[oid] = dict(source=source)
                    self.log_switch(event="SWITCH_REQUESTED", source_supplier=source, old_order_id=oid,
                                    requested_quantity=quantity, prospective_supplier=alternatives[0].supplier_id)
            for ticket in self.replacement_tickets:
                quantity = min(ticket["remaining"], self.open_procurement_need())
                for offer in offers:
                    if not quantity or offer.supplier_id == ticket["source"]:
                        continue
                    result = self.request(quantity, offer.supplier_id)
                    accepted = result["accepted_quantity"]
                    ticket["remaining"] -= accepted
                    quantity -= accepted
                    if accepted:
                        self.log_switch(event="REPLACEMENT_ACCEPTED", source_supplier=ticket["source"],
                                        old_order_id=ticket["order_id"], replacement_supplier=offer.supplier_id,
                                        replacement_order_id=result["order_id"], replacement_quantity=accepted)
            self.replacement_tickets = [t for t in self.replacement_tickets if t["remaining"]]
        # Confirmed switch quantities remain directed away from their source;
        # unavailable alternatives leave real open need, not a fabricated order.
        held = sum(t["remaining"] for t in self.replacement_tickets)
        remaining = max(0, self.open_procurement_need() - held)
        for offer in offers:
            if not remaining:
                break
            result = self.request(remaining, offer.supplier_id)
            remaining -= result["accepted_quantity"]
        today = self.requests[first_request:]
        accepted = sum(r["accepted_quantity"] for r in today)
        assert accepted <= initial_need, "multi-supplier duplicate procurement"
        boundary = dict(day=self.day, initial_open_need=initial_need, accepted=accepted,
                        final_open_need=self.open_procurement_need(), considered_supplier_ids=considered,
                        queried_supplier_ids=[o.supplier_id for o in offers], known_supplier_ids=sorted(self.known),
                        request_ids=[r["request_id"] for r in today])
        self.boundaries.append(boundary)
        self.boundary_by_day[self.day] = boundary
        self.decision_need = initial_need
        return accepted, self.open_procurement_need()

    def observe_multi(self):
        # No historical request/offer/cancellation scans for daily export.
        requests = self.requests_by_day.get(self.day, [])
        offers = self.offers_by_day.get(self.day, [])
        cancels = self.cancel_by_day.get(self.day, [])
        discoveries = self.discovery_by_day.get(self.day, [])
        switches = self.switch_by_day.get(self.day, [])
        visits = sum(map(len, (requests, offers, cancels, discoveries, switches)))
        self.daily_export_visits += visits
        pending = transit = 0
        row = dict(global_supply_position=self.global_supply_position(), open_need=self.open_procurement_need(),
                   on_hand=self.stock["B"]["coal"], available_supplier_count=len(self.available),
                   available_supplier_ids="|".join(self.available), known_supplier_count=len(self.known),
                   known_supplier_ids="|".join(sorted(self.known)),
                   considered_supplier_count=len(self.boundary_by_day.get(self.day, {}).get("considered_supplier_ids", [])),
                   queried_supplier_ids="|".join(o["supplier_id"] for o in offers),
                   discovery_count=len(discoveries), offer_evaluations=self.offer_evaluations,
                   candidate_scans=self.candidate_scans, daily_event_export_visits=visits,
                   cumulative_daily_event_export_visits=self.daily_export_visits,
                   active_requests=0, active_cancel_requests=len(self.cancel_requests),
                   stock_commitment_entries=len(self.stock_commitments.entries),
                   active_orders=sum(len(self.active_orders[r]) for r in self.supplier_routes.values()),
                   slot_entries=sum(len(slots.committed) for slots in self.route_slots.values()),
                   cumulative_A_extraction=self.source_extraction["A"], cumulative_D_extraction=self.source_extraction["D"],
                   cancel_requested_qty=sum(c["requested_cancel_qty"] for c in cancels if c["state"] == "CANCEL_REQUESTED"),
                   cancel_confirmed_qty=sum(c["confirmed_cancel_qty"] for c in cancels if c["state"] == "CANCEL_CONFIRMED"),
                   no_longer_cancellable_qty=sum(c["no_longer_cancellable_qty"] for c in cancels if c["state"] == "CANCEL_CONFIRMED"),
                   replacement_qty=sum(s.get("replacement_quantity", 0) for s in switches),
                   switch_waiting_need=sum(t["remaining"] for t in self.replacement_tickets))
        for supplier, route in self.supplier_routes.items():
            p, t = self.balances(route)
            pending += p; transit += t
            request_rows = [r for r in requests if r["supplier_id"] == supplier]
            offer_rows = [o for o in offers if o["supplier_id"] == supplier]
            quote = self.route_slots[route].quote(self.day, self.capacity(route, self.day))
            committed = self.stock_commitments.totals[(supplier, "coal")]
            free = self.stock_commitments.uncommitted(supplier, "coal", self.stock[supplier]["coal"])
            transport = sum(s["remaining_slot"] for s in quote)
            row.update({f"{supplier}_transport_atp": transport, f"{supplier}_stock_confirmed_atp": min(transport, free),
                        f"{supplier}_stock_committed": committed, f"{supplier}_uncommitted_stock": free,
                        f"{supplier}_requested": sum(r["requested_quantity"] for r in request_rows),
                        f"{supplier}_accepted": sum(r["accepted_quantity"] for r in request_rows),
                        f"{supplier}_rejected": sum(r["rejected_quantity"] for r in request_rows),
                        f"{supplier}_partial_accept_count": sum(0 < r["accepted_quantity"] < r["requested_quantity"] for r in request_rows),
                        f"{supplier}_full_reject_count": sum(r["accepted_quantity"] == 0 for r in request_rows),
                        f"{supplier}_offer_max": offer_rows[-1]["max_acceptable_quantity"] if offer_rows else None,
                        f"{supplier}_promised_dispatch": offer_rows[-1]["promised_dispatch_by_day"] if offer_rows else None,
                        f"{supplier}_expected_arrival": offer_rows[-1]["expected_arrival_day"] if offer_rows else None,
                        f"{supplier}_overdue": self.classification(route)["overdue_pending_qty"],
                        f"{supplier}_cumulative_ordered": self.totals[route]["ordered"],
                        f"{supplier}_order_residual": self.route_order_residuals[route],
                        # The original row repeats a buyer's aggregate new_order
                        # for each inbound route; fix only these export labels.
                        f"{route}_new_order": sum(r["accepted_quantity"] for r in request_rows),
                        f"{route}_unprocured": sum(r["rejected_quantity"] for r in request_rows)})
        row.update(total_live_pending=pending, total_in_transit=transit,
                   stock_account_visits=self.stock_account_visits,
                   order_scan_visits=self.active_scan_visits,
                   slot_scan_visits=sum(s.scan_visits for s in self.route_slots.values()))
        return row
