"""Generic coal-source extension with bounded knowledge and indexed search.

No step, FIFO or receipt implementation is copied. All world-source loops below
are physical production/accounting; procurement only visits known IDs.
"""
from collections import defaultdict
from copy import deepcopy
from dataclasses import asdict
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "multi_round4b"))
from multi_supplier import MultiSupplierSimulation, InformationInbox, ranked_offers
from stock_admission import StockConfirmedSimulation, TransportSlots
from supplier_directory import DirectoryEntry, SupplierDirectory, SearchKnowledge


class SearchSimulation(MultiSupplierSimulation):
    def __init__(self, config, policy="Q0", information=None, result_limit=3):
        self.world_ids = tuple(config["available_supplier_ids"])
        self.server_routes = dict(config["supplier_routes"])
        self.supplier_state = deepcopy(config["supplier_state"])
        self.coal_pending = self.coal_transit = 0
        self.source_plan_visits = self.account_route_visits = self.world_export_route_visits = 0
        self.source_events_by_day = defaultdict(list)
        self.directory = SupplierDirectory([DirectoryEntry(**e) for e in config["directory_entries"]])
        initial_known = config["replenishment"]["B"]["known_suppliers"]
        initial = deepcopy(config)
        initial["replenishment"]["B"]["known_suppliers"] = [s for s in initial_known if s in ("A", "D")]
        super().__init__(initial, "M1", information)
        self.config["replenishment"]["B"]["known_suppliers"] = list(initial_known)
        self.knowledge = SearchKnowledge("B", "coal", initial_known, policy, result_limit)
        self.known = self.knowledge.known
        self.supplier_routes = {}
        existing_slots = self.route_slots
        self.route_slots = {}
        for supplier in sorted(self.known):
            route = self.server_routes[supplier]
            self.supplier_routes[supplier] = route
            self.route_slots[route] = existing_slots.get(route, TransportSlots(2))
        for supplier in self.world_ids:
            self.source_extraction.setdefault(supplier, 0)
        self.extra_sources = tuple(s for s in self.world_ids if s not in ("A", "D"))
        self.directory_daily = {}

    def capacity(self, route, day):
        capacity = super().capacity(route, day)
        spec = self.config["routes"][route]
        state = self.supplier_state.get(spec["supplier"])
        if state and (not state["active"] or not state["route_available"]):
            return 0
        return capacity

    def production_plan(self):
        plan = super().production_plan()
        for supplier in ("A", "D"):
            if not self.supplier_state[supplier]["active"]:
                plan[supplier] = 0
        for supplier in self.extra_sources:
            rule = self.config["production"][supplier]
            plan[supplier] = min(rule["capacity"], max(0, rule["coal_target"] - self.stock[supplier]["coal"])) if self.supplier_state[supplier]["active"] else 0
        self.source_plan_visits += len(self.world_ids)
        return plan

    def produce(self, plan):
        super().produce(plan)  # Existing A/B/C and D settlement executed exactly once.
        for supplier in self.extra_sources:
            quantity = plan[supplier]
            self.stock[supplier]["coal"] += quantity
            self.cumulative["coal_mined"] += quantity
            self.source_extraction[supplier] += quantity
        for supplier in self.world_ids:
            if plan[supplier]:
                self.source_events_by_day[self.day].append(dict(supplier_id=supplier, quantity=plan[supplier]))

    def record_event(self, event, order, shipment=None, quantity=0):
        super().record_event(event, order, shipment, quantity)
        spec = self.config["routes"][order.route]
        if spec["buyer"] == "B" and spec["commodity"] == "coal":
            if event == "accepted": self.coal_pending += quantity
            elif event == "dispatched":
                self.coal_pending -= quantity
                self.coal_transit += quantity
            elif event == "arrived": self.coal_transit -= quantity
            elif event == "cancelled": self.coal_pending -= quantity

    def global_supply_position(self):
        # No world/catalog scan in decision-time inventory deduplication.
        return self.stock["B"]["coal"] + self.coal_pending + self.coal_transit

    def check_accounts(self):
        residuals = super().check_accounts()
        # Full-world accounting is intentionally separate from decision work.
        pending = transit = 0
        for route in self.server_routes.values():
            p, t = self.balances(route)
            pending += p; transit += t
        self.account_route_visits += len(self.server_routes)
        assert (pending, transit) == (self.coal_pending, self.coal_transit)
        return residuals

    def learn(self, supplier, source):
        if supplier not in self.server_routes:
            raise ValueError("directory result has no physical supplier route")
        self.known.add(supplier)
        if supplier not in self.supplier_routes:
            route = self.server_routes[supplier]
            self.supplier_routes[supplier] = route
            self.route_slots[route] = TransportSlots(2)
        record = dict(day=self.day, event="SUPPLIER_DISCOVERED", supplier_id=supplier, source=source)
        self.discoveries.append(record)
        self.discovery_by_day[self.day].append(record)

    def receive_information(self):
        for event in self.information.deliver(self.day):
            self.learn(event["supplier_id"], event["source"])
        for entry in self.knowledge.deliver(self.day, self.directory):
            self.learn(entry.supplier_id, "bounded_directory_result")

    def procure(self, buyer, known_candidates):
        if buyer != "B":
            # Original procurement finds inbound routes by walking every route.
            # This fixture's C steel route is explicit; resolve it directly while
            # preserving its legacy target, known-candidate rule and acceptance.
            if buyer != "C": raise ValueError("only the existing B/C chain is supported")
            route = "B_C"
            classified = self.classification(route)
            for oid, quantity in classified["overdue_orders"]:
                if oid not in self.breached:
                    self.breached.add(oid)
                    self.totals[route]["breach_count"] += 1
                    self.totals[route]["breach_qty"] += quantity
                    self._record_commitment_event("promise_breach", self.orders[oid], quantity)
            quantity = max(0, self.config["replenishment"]["C"]["target"]-self.inventory_position(route))
            if quantity and self.config["routes"][route]["supplier"] in known_candidates:
                self.accept_order(route, quantity)
                return quantity, 0
            return 0, quantity
        before_visits = self.directory.query_visits
        before_results = self.directory.results_returned
        self.receive_information()
        self.confirm_cancellations()
        for route in self.supplier_routes.values():  # Activated known routes only.
            classified = self.classification(route)
            for oid, quantity in classified["overdue_orders"]:
                if oid not in self.breached:
                    self.breached.add(oid)
                    self.totals[route]["breach_count"] += 1
                    self.totals[route]["breach_qty"] += quantity
                    self._record_commitment_event("promise_breach", self.orders[oid], quantity)
        initial_need = self.open_procurement_need()
        considered = sorted(self.known) if initial_need else []
        self.candidate_scans += len(considered)
        offers = ranked_offers([self.offer(s) for s in considered])
        remaining = initial_need
        today = []
        for offer in offers:
            if not remaining: break
            response = self.request(remaining, offer.supplier_id)
            today.append(response)
            remaining -= response["accepted_quantity"]
        accepted = sum(r["accepted_quantity"] for r in today)
        assert accepted <= initial_need
        self.knowledge.consider(self.day, remaining, sum(o.max_acceptable_quantity for o in offers) >= initial_need)
        boundary = dict(day=self.day, initial_open_need=initial_need, accepted=accepted,
                        final_open_need=self.open_procurement_need(), considered_supplier_ids=considered,
                        queried_supplier_ids=[o.supplier_id for o in offers], known_supplier_ids=sorted(self.known),
                        request_ids=[r["request_id"] for r in today])
        self.boundaries.append(boundary); self.boundary_by_day[self.day] = boundary
        self.directory_daily[self.day] = dict(query_bucket_visits=self.directory.query_visits-before_visits,
                                             results_returned=self.directory.results_returned-before_results)
        self.decision_need = initial_need
        return accepted, remaining

    def observe_search(self):
        requests = self.requests_by_day.get(self.day, [])
        offers = self.offers_by_day.get(self.day, [])
        information = self.discovery_by_day.get(self.day, [])
        search_events = self.knowledge.events_by_day.get(self.day, [])
        visits = sum(map(len, (requests, offers, information, search_events)))
        self.daily_export_visits += visits
        boundary = self.boundary_by_day[self.day]
        row = dict(world_supplier_count=len(self.world_ids), directory_indexed_suppliers=len(self.directory.indexed_ids),
                   discoverable_supplier_count=len(self.directory.indexed_ids),
                   directory_build_visits=self.directory.build_visits, directory_buckets=len(self.directory.buckets),
                   known_supplier_count=len(self.known), known_supplier_ids="|".join(sorted(self.known)),
                   matching_candidate_visits_today=len(boundary["considered_supplier_ids"]),
                   offers_queried_today=len(offers), queried_supplier_ids="|".join(o["supplier_id"] for o in offers),
                   candidate_visits=self.candidate_scans, offer_evaluations=self.offer_evaluations,
                   active_searches=int(self.knowledge.pending is not None), search_request_count=len(self.knowledge.requests),
                   query_bucket_visits=self.directory.query_visits, results_returned=self.directory.results_returned,
                   query_bucket_visits_today=self.directory_daily[self.day]["query_bucket_visits"],
                   search_results_today=self.directory_daily[self.day]["results_returned"],
                   discovery_count=len(information), global_supply_position=self.global_supply_position(),
                   open_need=self.open_procurement_need(), on_hand=self.stock["B"]["coal"],
                   total_live_pending=self.coal_pending, total_in_transit=self.coal_transit,
                   active_orders=sum(len(self.active_orders[r]) for r in self.supplier_routes.values()),
                   active_requests=0, active_cancel_requests=len(self.cancel_requests),
                   stock_commitment_entries=len(self.stock_commitments.entries),
                   slot_entries=sum(len(s.committed) for s in self.route_slots.values()),
                   daily_export_visits=visits, cumulative_daily_export_visits=self.daily_export_visits,
                   source_plan_visits=self.source_plan_visits, world_account_route_visits=self.account_route_visits,
                   cumulative_A_extraction=self.source_extraction["A"], cumulative_D_extraction=self.source_extraction["D"],
                   coal_order_residual=sum(self.route_order_residuals[r] for r in self.supplier_routes.values()))
        # The old row repeats B's aggregate on every world route. Export must
        # correct even unknown routes to zero; this O(N) labeling is not matching.
        by_supplier = defaultdict(list)
        for request in requests:
            by_supplier[request["supplier_id"]].append(request)
        for supplier, route in self.server_routes.items():
            rr = by_supplier.get(supplier, ())
            row[route+"_new_order"] = sum(r["accepted_quantity"] for r in rr)
            row[route+"_unprocured"] = sum(r["rejected_quantity"] for r in rr)
        self.world_export_route_visits += len(self.server_routes)
        row["world_export_route_visits"] = self.world_export_route_visits
        return row
