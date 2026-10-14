"""Coarse indexed information and delayed bounded knowledge acquisition."""
from collections import defaultdict
from dataclasses import dataclass, asdict
import heapq

SCOPES = ("LOCAL", "REGIONAL", "WIDE")
LATENCIES = {"LOCAL": 1, "REGIONAL": 3, "WIDE": 7}


def positive_integer(value):
    if type(value) is not int or value < 1:
        raise ValueError("expected positive integer")
    return value


@dataclass(frozen=True)
class DirectoryEntry:
    supplier_id: str
    commodity: str
    search_zone: str
    place_id: str
    route_available: bool
    nominal_lead_band: int
    advertised_capacity_band: str
    active: bool = True
    discoverability_channel: str = "DIRECTORY"


class SupplierDirectory:
    """O(N) insertion at build; queries merge only pre-sorted eligible buckets.

    No supplier object, stock, ATP, order queue or future schedule is accepted.
    Directory eligibility is static coarse information, not current offer truth.
    """
    def __init__(self, entries, regional_zones=None):
        self.entries = tuple(entries)
        self.regional_zones = regional_zones or {"Z0": ("Z0", "Z1", "Z2")}
        self.buckets = defaultdict(list)
        self.build_visits = 0
        self.indexed_ids = set()
        self.bucket_lookups = 0
        self.query_visits = 0
        self.results_returned = 0
        self.query_audit = []
        ids = set()
        for entry in self.entries:
            self.build_visits += 1
            if entry.supplier_id in ids:
                raise ValueError("duplicate directory supplier")
            ids.add(entry.supplier_id)
            if entry.active and entry.route_available and entry.discoverability_channel == "DIRECTORY":
                self.buckets[(entry.commodity, entry.search_zone)].append(entry)
                self.buckets[(entry.commodity, "*")].append(entry)
                self.indexed_ids.add(entry.supplier_id)
        for bucket in self.buckets.values():
            bucket.sort(key=lambda e: (e.nominal_lead_band, e.supplier_id))

    def search(self, commodity, origin_zone, scope, result_limit=3, exclude=frozenset()):
        positive_integer(result_limit)
        if scope not in SCOPES:
            raise ValueError("invalid scope")
        zones = (origin_zone,) if scope == "LOCAL" else self.regional_zones.get(origin_zone, (origin_zone,)) if scope == "REGIONAL" else ("*",)
        zones = tuple(dict.fromkeys(zones))
        buckets = [self.buckets.get((commodity, zone), ()) for zone in zones]
        self.bucket_lookups += len(buckets)
        inspected, results = [], []
        for entry in heapq.merge(*buckets, key=lambda e: (e.nominal_lead_band, e.supplier_id)):
            self.query_visits += 1
            inspected.append(entry.supplier_id)
            if entry.supplier_id not in exclude:
                results.append(entry)
                if len(results) == result_limit:
                    break
        self.results_returned += len(results)
        self.query_audit.append(dict(commodity=commodity, scope=scope, zones=list(zones),
                                     bucket_sizes=[len(b) for b in buckets], inspected_ids=inspected,
                                     result_ids=[e.supplier_id for e in results]))
        return results


@dataclass
class SearchRequest:
    search_id: str
    buyer: str
    commodity: str
    scope: str
    requested_day: int
    delivery_day: int
    result_limit: int
    status: str = "PENDING"


class SearchKnowledge:
    """Independent buyer+commodity state; one active request and persistent knowledge."""
    def __init__(self, buyer, commodity, known, policy="Q1", result_limit=3, cooldown=30, latencies=None):
        if policy not in ("Q0", "Q1"):
            raise ValueError("unknown discovery policy")
        self.buyer, self.commodity, self.policy = buyer, commodity, policy
        self.known = set(known)
        self.result_limit = positive_integer(result_limit)
        self.cooldown = positive_integer(cooldown)
        self.latencies = dict(LATENCIES if latencies is None else latencies)
        for scope in SCOPES:
            positive_integer(self.latencies[scope])
        self.pending = None
        self.requests = []
        self.events = []
        self.events_by_day = defaultdict(list)
        self.completed = {}
        self.next_scope = 0

    def log(self, day, event, **facts):
        record = dict(day=day, event=event, buyer=self.buyer, commodity=self.commodity, **facts)
        self.events.append(record)
        self.events_by_day[day].append(record)
        return record

    def issue(self, day, scope):
        if type(day) is not int or day < 0 or scope not in SCOPES:
            raise ValueError("invalid search request")
        if self.pending or day - self.completed.get(scope, -self.cooldown) < self.cooldown:
            return None
        request = SearchRequest(f"{self.buyer}-{self.commodity}-{len(self.requests)+1:04d}",
                                self.buyer, self.commodity, scope, day, day+self.latencies[scope], self.result_limit)
        self.pending = request
        self.requests.append(request)
        self.log(day, "SEARCH_REQUESTED", **{k: v for k, v in asdict(request).items() if k not in ("buyer", "commodity")})
        return request

    def consider(self, day, open_need, offers_sufficient=False):
        if self.policy != "Q1" or open_need <= 0 or offers_sufficient or self.pending:
            return None
        return self.issue(day, SCOPES[self.next_scope])

    def deliver(self, day, directory, origin_zone="Z0"):
        if not self.pending or day < self.pending.delivery_day:
            return []
        request = self.pending
        # The information service consults today's directory at delivery, not
        # future economic state or a result prematurely exposed to the buyer.
        results = directory.search(self.commodity, origin_zone, request.scope, request.result_limit, self.known)
        request.status = "COMPLETED" if results else "COMPLETED_NO_RESULTS"
        self.completed[request.scope] = day
        self.next_scope = (SCOPES.index(request.scope)+1) % len(SCOPES)
        self.pending = None
        self.log(day, "SEARCH_COMPLETED" if results else "SEARCH_COMPLETED_NO_RESULTS",
                 search_id=request.search_id, scope=request.scope, requested_day=request.requested_day,
                 delivery_day=day, result_limit=request.result_limit, results=[asdict(e) for e in results])
        self.known.update(e.supplier_id for e in results)
        return results
