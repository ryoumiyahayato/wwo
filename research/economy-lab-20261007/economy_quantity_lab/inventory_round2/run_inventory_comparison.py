"""Run the requested A/B/C/D comparisons without copying quantity settlement."""
import argparse
from copy import deepcopy
import csv
import hashlib
import json
from pathlib import Path
import statistics
import sys
import time

HERE = Path(__file__).resolve().parent
ORIGINAL = HERE.parent
sys.path.insert(0, str(ORIGINAL))
from economy import Simulation, require
from inventory_policy import coverage_diagnostic, replenishment_target

DAYS = 600
RECOVERY_WINDOW = 20
LAST_WINDOW = 200


class PhaseObserver(Simulation):
    """Thin passive wrapper; step and all settlement remain in original Simulation."""
    def __init__(self, config, scenario):
        super().__init__(config, scenario)
        self.phase_rows = []
        self.phase = {}

    def capture(self, stage):
        self.phase[f"B_steel_{stage}"] = self.stock["B"]["steel"]
        self.phase[f"B_steel_pending_{stage}"] = self.balances("B_C")[0]

    def produce(self, plan):
        self.phase = {"day": self.day, "B_coal_before_production": self.stock["B"]["coal"],
                      "C_steel_before_production": self.stock["C"]["steel"]}
        self.capture("before_production")
        result = super().produce(plan)
        self.capture("after_production")
        return result

    def dispatch(self):
        self.capture("before_dispatch")  # Includes orders accepted after production.
        result = super().dispatch()
        self.capture("after_dispatch")
        self.phase_rows.append(dict(self.phase))
        return result


def fixture():
    return json.loads((ORIGINAL / "fixture.json").read_text(encoding="utf-8"))


def plans(config):
    machine = config["daily_terminal_demand"]
    steel = machine * config["production"]["C"]["steel_per_machine"]
    return {"A_B": steel * config["production"]["B"]["coal_per_steel"], "B_C": steel}


def make_case(base, case_id, group, treatment, policy="H0", lead=2, buffer=None,
              steel_target=40, recovery_capacity=100, baseline_id=None):
    config = deepcopy(base)
    config["days"] = DAYS
    config["routes"]["A_B"]["lead_time"] = lead
    config["production"]["B"]["steel_target"] = steel_target
    planned = plans(base)["A_B"]
    if policy == "H1":
        config["replenishment"]["B"]["target"] = replenishment_target(planned, lead, buffer)
    if treatment == "baseline":
        schedule = {}
    elif treatment == "shutdown":
        schedule = {"A_B": [{"first_day": 50, "last_day": DAYS, "capacity": 0}]}
    else:
        intervals = [{"first_day": 50, "last_day": 79, "capacity": 30}]
        if recovery_capacity != config["routes"]["A_B"]["capacity"]:
            intervals.append({"first_day": 80, "last_day": DAYS, "capacity": recovery_capacity})
        schedule = {"A_B": intervals}
    # Scenario knowledge stays in the runner/model transport layer, not policy/diagnostic.
    config["scenarios"] = {"experiment": schedule}
    return {"case_id": case_id, "group": group, "treatment": treatment, "policy": policy,
            "lead_days": lead, "buffer_days": buffer, "steel_target": steel_target,
            "coal_target": config["replenishment"]["B"]["target"],
            "planned_coal_per_day": planned, "recovery_capacity": recovery_capacity,
            "baseline_id": baseline_id, "config": config}


def all_cases(base):
    cases = []
    for target in (0, 40, 80):
        baseline = f"A_steel{target}_baseline"
        for treatment in ("baseline", "shock"):
            cases.append(make_case(base, f"A_steel{target}_{treatment}", "A", treatment,
                                   steel_target=target, baseline_id=baseline))
    for lead in (2, 4, 8):
        for policy, buffer in [("H0", None), ("H1", 0), ("H1", 2), ("H1", 4)]:
            name = f"B_L{lead}_{policy}" + (f"_b{buffer}" if buffer is not None else "")
            for treatment in ("baseline", "shock"):
                cases.append(make_case(base, f"{name}_{treatment}", "B", treatment,
                                       policy, lead, buffer, baseline_id=f"{name}_baseline"))
    cases.append(make_case(base, "C_shutdown_H0", "C", "shutdown",
                           baseline_id="B_L2_H0_baseline"))
    for capacity in (80, 100):
        cases.append(make_case(base, f"D_recover{capacity}_H0", "D", "shock",
                               recovery_capacity=capacity, baseline_id="B_L2_H0_baseline"))
    return cases


def local_diagnostic(simulation, route, planned):
    spec = simulation.config["routes"][route]
    orders = simulation.active_orders[route].values()
    pending = [{"ordered_day": o.day, "pending_dispatch": o.pending_dispatch} for o in orders]
    shipped = [{"quantity": s.quantity, "arrival_day": s.arrival_day}
               for o in simulation.active_orders[route].values() for s in o.active_shipments.values()]
    # No future capacity, shock dates, or future production crosses this interface.
    result = coverage_diagnostic(simulation.day, simulation.stock[spec["buyer"]][spec["commodity"]],
                                 pending, shipped, planned, spec["lead_time"])
    require(result["inventory_position"] == simulation.inventory_position(route), "diagnostic position")
    return {"route": route, **result}


def run_case(case, observe=True):
    config = deepcopy(case["config"])
    sim = (PhaseObserver if observe else Simulation)(config, "experiment")
    diagnostic_rows = []
    active_peak = 0
    normal_plan = plans(config)
    for _ in range(config["days"]):
        row = sim.step()  # Original step executes and checks all commodity/order accounts daily.
        for route in config["routes"]:
            active_peak = max(active_peak, sum(len(v) for v in sim.active_orders.values()))
            if observe:
                diagnostic_rows.append(local_diagnostic(sim, route, normal_plan[route]))
            require(row[f"{route}_dispatch"] <= row[f"{route}_capacity"], "transport capacity")
    for order in sim.orders.values():
        order.check()
    for shipment in sim.shipments:
        require(shipment.arrival_day == shipment.dispatch_day + config["routes"][shipment.route]["lead_time"],
                "shipment lead time")
        require(shipment.received_day is None or shipment.received_day == shipment.arrival_day,
                "shipment early/late arrival")
    return sim, diagnostic_rows, active_peak


def encode_cell(value):
    if value is None:
        return "null"
    if isinstance(value, (dict, list)):
        return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return value


def write_csv(path, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows({k: encode_cell(v) for k, v in row.items()} for row in rows)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")


def first_window(rows, test, start, window=RECOVERY_WINDOW):
    count = 0
    for row in rows:
        if row["day"] < start:
            continue
        count = count + 1 if test(row) else 0
        if count == window:
            return row["day"] - window + 1
    return None


def statistics_for(rows, diagnostic_rows):
    result = {}
    for key in ("production_A", "production_B", "production_C", "terminal_delivery"):
        values = [r[key] for r in rows]
        result.update({f"{key}_mean": statistics.mean(values), f"{key}_min": min(values),
                       f"{key}_max": max(values)})
    for key in ("A_coal_on_hand", "A_steel_on_hand", "A_machine_on_hand", "B_coal_on_hand",
                "B_steel_on_hand", "B_machine_on_hand", "C_coal_on_hand", "C_steel_on_hand",
                "C_machine_on_hand", "A_B_pending_dispatch", "A_B_in_transit", "A_B_dispatch",
                "B_C_pending_dispatch", "B_C_in_transit", "B_C_dispatch"):
        result[f"{key}_mean"] = statistics.mean(r[key] for r in rows)
    peak = max(r["terminal_backlog"] for r in rows)
    result.update(backlog_peak=peak, backlog_peak_first_day=next(r["day"] for r in rows if r["terminal_backlog"] == peak),
                  backlog_first_positive_day=next((r["day"] for r in rows if r["terminal_backlog"] > 0), None),
                  backlog_final=rows[-1]["terminal_backlog"],
                  backlog_machine_days=sum(r["terminal_backlog"] for r in rows),
                  max_abs_quantity_residual=max(abs(r[f"{g}_residual"]) for r in rows for g in ("coal", "steel", "machine")))
    for route in ("A_B", "B_C"):
        diag = [r for r in diagnostic_rows if r["route"] == route]
        result[f"{route}_conditional_gap_days"] = sum(r["conditional_first_shortfall_day"] is not None for r in diag)
        result[f"{route}_on_hand_coverage_mean"] = statistics.mean(r["on_hand_coverage_days"] for r in diag)
        result[f"{route}_conditional_covered_days_mean"] = statistics.mean(r["conditional_covered_days"] for r in diag)
        result[f"{route}_oldest_pending_age_max"] = max((r["oldest_pending_age_days"] or 0 for r in diag), default=0)
    return result


def recovery_metrics(case, rows, baseline):
    keys = ("production_B", "production_C", "terminal_delivery")
    normal_demand = case["config"]["daily_terminal_demand"]
    result = {f"first_{key}_below_paired_baseline_day": next(
        (r["day"] for r, b in zip(rows, baseline) if r["day"] >= 50 and r[key] < b[key]), None) for key in keys}
    result.update({f"first_{key}_zero_after50_day": next((r["day"] for r in rows if r["day"] >= 50 and r[key] == 0), None)
                   for key in ("production_B", "production_C")})
    tests = {
        "flow_at_least_baseline_20_day": lambda r: all(r[k] >= baseline[r["day"] - 1][k] for k in keys),
        "flow_equal_baseline_20_day": lambda r: all(r[k] == baseline[r["day"] - 1][k] for k in keys),
        "normal_delivery_at_least10_20_day": lambda r: r["terminal_delivery"] >= normal_demand and r["production_C"] >= normal_demand,
        "terminal_backlog_zero_20_day": lambda r: r["terminal_backlog"] == 0,
        "terminal_backlog_equal_baseline_20_day": lambda r: r["terminal_backlog"] == baseline[r["day"] - 1]["terminal_backlog"],
    }
    for key in keys:
        tests[f"{key}_at_least_baseline_20_day"] = lambda r, key=key: r[key] >= baseline[r["day"] - 1][key]
        tests[f"{key}_equal_baseline_20_day"] = lambda r, key=key: r[key] == baseline[r["day"] - 1][key]
    for name, comparison_keys in {
        "coal_pending_equal_baseline_20_day": ["A_B_pending_dispatch"],
        "steel_pending_equal_baseline_20_day": ["B_C_pending_dispatch"],
        "B_coal_on_hand_equal_baseline_20_day": ["B_coal_on_hand"],
        "C_steel_on_hand_equal_baseline_20_day": ["C_steel_on_hand"],
        "coal_in_transit_equal_baseline_20_day": ["A_B_in_transit"],
        "steel_in_transit_equal_baseline_20_day": ["B_C_in_transit"],
        "all_on_hand_equal_baseline_20_day": [k for k in rows[0] if k.endswith("_on_hand")],
    }.items():
        tests[name] = lambda r, comparison_keys=comparison_keys: all(
            r[k] == baseline[r["day"] - 1][k] for k in comparison_keys)
    for name, test in tests.items():
        # A continuing shutdown has no recovery phase; do not label incidental matches as recovery.
        day = first_window(rows, test, 80) if case["treatment"] == "shock" else None
        result[name] = day
        result[name.replace("_20_day", "_last_nonmatch_day")] = max(
            (r["day"] for r in rows if r["day"] >= 80 and not test(r)), default=None)
    return result


def event_evidence(sim):
    selected = set()
    # A bounded set of complete order lifecycles, selected from the finished event archive once.
    dispatch_counts = {}
    for event in sim.events:
        if event["event"] == "dispatched":
            dispatch_counts[event["order_id"]] = dispatch_counts.get(event["order_id"], 0) + 1
    for route in sim.config["routes"]:
        orders = [o for o in sim.orders.values() if o.route == route]
        for threshold in (1, 50, 80):
            order = next((o for o in orders if o.day >= threshold), None)
            if order:
                selected.add(order.id)
        partial = next((o for o in orders if dispatch_counts.get(o.id, 0) > 1), None)
        if partial:
            selected.add(partial.id)
        selected.update(list(sim.active_orders[route])[:3])
    return [event for event in sim.events if event["order_id"] in selected]


def periods(case):
    if case["treatment"] == "shutdown":
        return [("startup", 1, 49), ("continuing_shutdown", 50, 600), ("last200", 401, 600)]
    prefix = "reference_" if case["treatment"] == "baseline" else ""
    return [("startup", 1, 49), (prefix + "shock_window", 50, 79),
            (prefix + "recovery_window", 80, 600), ("last200", 401, 600)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=HERE / "inventory_comparison_results")
    parser.add_argument("--execution-log", type=Path, default=None)
    args = parser.parse_args()
    started = time.perf_counter()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    base = fixture()
    cases = all_cases(base)
    completed = {}
    metadata = []
    for case in cases:
        directory = args.output_dir / case["case_id"]
        directory.mkdir(parents=True, exist_ok=True)
        sim, diagnostics, active_peak = run_case(case)
        daily = [{**row, **phase} for row, phase in zip(sim.rows, sim.phase_rows)]
        write_json(directory / "config.json", case)
        write_csv(directory / "daily.csv", daily)
        write_csv(directory / "diagnostics.csv", diagnostics)
        write_csv(directory / "event_evidence.csv", event_evidence(sim))
        completed[case["case_id"]] = {"sim": sim, "diagnostics": diagnostics, "active_peak": active_peak}
        metadata.append({k: v for k, v in case.items() if k != "config"})
    summary, period_rows = [], []
    for case in cases:
        run = completed[case["case_id"]]
        rows, diag = run["sim"].rows, run["diagnostics"]
        header = {k: v for k, v in case.items() if k != "config"}
        record = {**header, "days": DAYS, "last_window_days": LAST_WINDOW, "recovery_window_days": RECOVERY_WINDOW,
                  "active_orders_peak": run["active_peak"],
                  **{f"last200_{k}": v for k, v in statistics_for(rows[-LAST_WINDOW:], [d for d in diag if d["day"] >= 401]).items()},
                  **{f"all600_{k}": v for k, v in statistics_for(rows, diag).items()}}
        pair = completed[case["baseline_id"]]["sim"].rows
        record.update(recovery_metrics(case, rows, pair))
        summary.append(record)
        for period, first, last in periods(case):
            period_rows.append({"case_id": case["case_id"], "period": period, "first_day": first, "last_day": last,
                                **statistics_for(rows[first - 1:last], [d for d in diag if first <= d["day"] <= last])})
    write_csv(args.output_dir / "summary.csv", summary)
    write_csv(args.output_dir / "period_summary.csv", period_rows)
    write_json(args.output_dir / "manifest.json", {
        "days": DAYS, "recovery_window_days": RECOVERY_WINDOW,
        "diagnostic_horizon": "known_transit_days + 2; no future dispatch assumed",
        "all_requested_cases_run_independently": True, "case_count": len(cases), "cases": metadata,
        "source_sha256": {name: hashlib.sha256((ORIGINAL / name).read_bytes()).hexdigest()
                          for name in ("economy.py", "fixture.json")},
        "new_source_sha256": {name: hashlib.sha256((HERE / name).read_bytes()).hexdigest()
                              for name in ("inventory_policy.py", "run_inventory_comparison.py")}})
    elapsed = time.perf_counter() - started
    log = {"case_count": len(cases), "simulated_case_days": len(cases) * DAYS,
           "elapsed_seconds": elapsed, "python": sys.version,
           "actual_run_ids": [case["case_id"] for case in cases],
           "max_abs_quantity_residual": max(r["all600_max_abs_quantity_residual"] for r in summary)}
    if args.execution_log:
        write_json(args.execution_log, log)  # Timing kept outside deterministic result tree.
    print(json.dumps(log, indent=2))


if __name__ == "__main__":
    main()
