"""Pure demand/recipe planning and a non-owning, time-aware coverage sidecar."""
from collections import deque, defaultdict
from dataclasses import dataclass, asdict
from fractions import Fraction
from math import ceil


@dataclass(frozen=True)
class Demand:
    sink_id: str
    commodity: str
    received_day: int
    quantity: int


class DemandHistory:
    def __init__(self, window=20):
        if window < 1: raise ValueError("positive window required")
        self.window = window
        self.days = deque()
        self.total = 0
        self.last_day = 0

    def observe(self, day, records):
        if day != self.last_day + 1: raise ValueError("observe each actual day exactly once")
        if any(r.received_day != day or r.quantity < 0 for r in records):
            raise ValueError("only current received demand is a fact")
        quantity = sum(r.quantity for r in records)
        self.days.append((day, quantity)); self.total += quantity; self.last_day = day
        while len(self.days) > self.window: self.total -= self.days.popleft()[1]
        return Fraction(self.total, len(self.days))


def aggregate_demand(records, commodity):
    return sum(r.quantity for r in records if r.commodity == commodity)


@dataclass(frozen=True)
class Recipe:
    producer_id: str
    output_commodity: str
    output_quantity: int
    inputs: tuple  # (commodity, quantity) pairs


class RecipeGraph:
    def __init__(self, recipes):
        self.recipes = {r.output_commodity: r for r in recipes}
        if len(self.recipes) != len(recipes): raise ValueError("ambiguous output recipe")
        for recipe in recipes:
            if recipe.output_quantity <= 0 or any(q <= 0 for _, q in recipe.inputs):
                raise ValueError("positive recipe coefficients required")
        for commodity in self.recipes: self._validate(commodity, set())
        self.nodes = len(set(self.recipes) | {g for r in recipes for g, _ in r.inputs})
        self.edges = sum(len(r.inputs) for r in recipes)

    def _validate(self, commodity, path):
        if commodity in path: raise ValueError("cyclic recipe graph")
        if commodity in self.recipes:
            for material, _ in self.recipes[commodity].inputs:
                self._validate(material, path | {commodity})

    def materials(self, output, quantity, capacity, current_inputs):
        """Gross requirements depend on recipe, never on current input shortage."""
        if min(quantity, capacity) < 0: raise ValueError("negative plan")
        recipe = self.recipes[output]
        constrained = min(quantity, capacity)
        gross = {g: ceil(Fraction(constrained * q, recipe.output_quantity)) for g, q in recipe.inputs}
        feasible = min([constrained] + [current_inputs.get(g, 0) * recipe.output_quantity // q for g, q in recipe.inputs])
        return dict(desired=quantity, constrained=constrained, capacity_shortfall=quantity-constrained,
                    gross=gross, input_feasible=feasible)

    def explode(self, commodity, quantity, day, capacities, lead_days=None, path="root"):
        """Interface propagation; intermediate production is bounded before recursion."""
        if commodity not in self.recipes: return [], 0
        recipe = self.recipes[commodity]
        result = self.materials(commodity, quantity, capacities.get(recipe.producer_id, quantity), {})
        records, traversed = [], 0
        for material, q in result["gross"].items():
            need_day = day - (lead_days or {}).get(recipe.producer_id, 0)
            rid = f"{path}/{recipe.producer_id}:{material}:{need_day}"
            records.append(MaterialRequirement(rid, recipe.producer_id, material, q, need_day, path))
            children, edges = self.explode(material, q, need_day, capacities, lead_days, rid)
            records.extend(children); traversed += 1 + edges
        return records, traversed


@dataclass(frozen=True)
class ProductionPlan:
    plan_id: str
    producer_id: str
    commodity: str
    plan_day: int  # Decision date; ID belongs to absolute production date.
    production_day: int
    desired_output_qty: int
    capacity_limited_output: int
    demand_basis: str
    planning_horizon: int
    unmet_planned_output: int


@dataclass(frozen=True)
class MaterialRequirement:
    requirement_id: str
    producer_id: str
    commodity: str
    required_qty: int
    need_by_day: int
    source_plan_id: str


@dataclass(frozen=True)
class Supply:
    supply_id: str
    producer_id: str
    commodity: str
    quantity: int
    available_day: int | None
    kind: str
    order_id: int | None = None


def daily_schedule(total, capacity, horizon):
    """Even deterministic integer spreading; no future schedule is an input."""
    remaining = min(ceil(total), capacity * horizon)
    result = []
    for i in range(horizon):
        q = min(capacity, ceil(Fraction(remaining, horizon-i)))
        result.append(q); remaining -= q
    return result


def procurement_components(safety_gap, plan_gap):
    """Shared units satisfy both conditions: union, not sum of overlapping gaps."""
    safety = max(0, ceil(safety_gap))
    incremental_plan = max(0, ceil(plan_gap)-safety)
    return dict(procurement_need_safety=safety, procurement_need_plan=incremental_plan,
                procurement_need_total=safety+incremental_plan, uncovered_plan_qty=max(0, ceil(plan_gap)))


def scheduled_supply_before(day, supplies, producer, commodity):
    return sum(s.quantity for s in supplies if (s.producer_id,s.commodity)==(producer,commodity)
               and s.available_day is not None and s.available_day<=day)


class PlanningAllocations:
    """Reconciled active-date reservations, never an ownership/material ledger.

    Reconstruction uses only live supply and active requirements. Confirmed cancel
    removes supply, dispatch replaces pending with cargo, and receipt replaces
    cargo with on-hand. Expired requirements move to an archive exactly once.
    """
    def __init__(self):
        self.active = {}
        self.allocations = {}
        self.by_requirement = defaultdict(list)
        self.by_supply = defaultdict(list)
        self.history = []
        self.events_by_day = defaultdict(list)
        self.visits = 0
        self.consumed = defaultdict(int)
        self.closed = set()

    def reconcile(self, day, requirements, supplies, timed=True):
        requirements = list(requirements); supplies = list(supplies)
        if len({r.requirement_id for r in requirements}) != len(requirements):
            raise ValueError("duplicate requirement IDs")
        if len({s.supply_id for s in supplies}) != len(supplies): raise ValueError("duplicate supply IDs")
        if any(s.quantity < 0 for s in supplies): raise ValueError("negative supply")
        previous = self.allocations
        self.active = {r.requirement_id: r for r in requirements if r.requirement_id not in self.closed}
        self.allocations = {}; self.by_requirement = defaultdict(list); self.by_supply = defaultdict(list)
        remaining = {s.supply_id: s.quantity for s in supplies}
        ordered = sorted(supplies, key=lambda s:(s.available_day is None, s.available_day or 0, s.supply_id))
        for r in sorted(self.active.values(), key=lambda r:(r.need_by_day, r.requirement_id)):
            need = max(0, r.required_qty-self.consumed[r.requirement_id])
            for s in ordered:
                self.visits += 1
                if not need: break
                if (s.producer_id, s.commodity) != (r.producer_id, r.commodity): continue
                if timed and (s.available_day is None or s.available_day > r.need_by_day): continue
                q = min(need, remaining[s.supply_id])
                if not q: continue
                key = (r.requirement_id, s.supply_id)
                record = dict(requirement_id=r.requirement_id, supply_id=s.supply_id, quantity=q,
                              kind=s.kind, available_day=s.available_day, order_id=s.order_id)
                self.allocations[key] = record
                self.by_requirement[r.requirement_id].append(record); self.by_supply[s.supply_id].append(record)
                remaining[s.supply_id] -= q; need -= q
        for key, old in previous.items():
            new = self.allocations.get(key, {})
            if old["quantity"] > new.get("quantity", 0):
                event = dict(day=day, event="COVERAGE_RELEASED", **old,
                             released_quantity=old["quantity"]-new.get("quantity", 0))
                self.events_by_day[day].append(event)
        return {r.requirement_id:self.gap(r.requirement_id) for r in self.active.values()}

    def gap(self, rid):
        r = self.active[rid]
        return max(0, r.required_qty-self.consumed[rid]-sum(a["quantity"] for a in self.by_requirement[rid]))

    def gap_for(self, producer, commodity):
        return sum(self.gap(r.requirement_id) for r in self.active.values()
                   if (r.producer_id,r.commodity)==(producer,commodity))

    def settle(self, day, actual_inputs):
        remaining = dict(actual_inputs)
        for rid, r in list(self.active.items()):
            if r.need_by_day > day: continue
            key = (r.producer_id,r.commodity)
            used = min(r.required_qty, remaining.get(key,0))
            remaining[key] = remaining.get(key,0)-used
            self.consumed[rid] += used
            self.history.append(dict(day=day, **asdict(r), allocated=sum(a["quantity"] for a in self.by_requirement[rid]),
                                     consumed=used, expired_unfulfilled=r.required_qty-used))
            self.closed.add(rid); del self.active[rid]
        return remaining

    def snapshot(self):
        return [dict(**asdict(r), allocated=sum(a["quantity"] for a in self.by_requirement[r.requirement_id]),
                     uncovered=self.gap(r.requirement_id)) for r in self.active.values()]
