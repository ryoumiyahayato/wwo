"""Four supply treatments x three policies, plus two explicit no-promise controls."""
import argparse
from copy import deepcopy
import csv
import hashlib
import json
from pathlib import Path
import statistics
import sys
import time
import tracemalloc

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE.parent / "inventory_round2"))
from run_inventory_comparison import first_window, fixture, plans, recovery_metrics
from inventory_policy import replenishment_target
from commitment_adapter import CommitmentSimulation

DAYS = 600
WINDOW = 20
BASELINE_COMMIT = "60278ee7f1703ef5aec6cb7933a2bcf6073e1038"
BASELINE_TAG = "economy-lab-v0.2-baseline"


def make_case(treatment, policy, promise_window_days=2, case_id=None):
    config = deepcopy(fixture())
    config["days"] = DAYS
    config["replenishment"]["B"]["target"] = replenishment_target(plans(config)["A_B"], 2, 2)
    schedule = {}
    if treatment in ("shock", "full_shutdown"):
        schedule = {"A_B": [{"first_day": 50, "last_day": 79,
                              "capacity": 30 if treatment == "shock" else 0}]}
    elif treatment == "shutdown":
        schedule = {"A_B": [{"first_day": 50, "last_day": DAYS, "capacity": 0}]}
    elif treatment != "normal":
        raise ValueError("unknown treatment")
    config["scenarios"] = {"experiment": schedule}
    return {"case_id": case_id or f"{treatment}_{policy}", "treatment": treatment,
            "policy": policy, "promise_window_days": promise_window_days,
            "baseline_id": f"normal_{policy}", "config": config}


def all_cases():
    cases = [make_case(t, p) for t in ("normal", "shock", "shutdown", "full_shutdown")
             for p in ("R0", "R1", "R2")]
    cases += [make_case(t, "R1", None, f"no_promise_{t}_R1") for t in ("shock", "shutdown")]
    return cases


def run_case(case, observe=True):
    sim = CommitmentSimulation(case["config"], "experiment", case["policy"],
                               case["promise_window_days"], observe)
    rows = []
    previous_cancelled = 0
    for _ in range(case["config"]["days"]):
        scans_before = sim.active_scan_visits
        original = sim.step()  # The sole, unchanged settlement path.
        current = sim.totals["A_B"]["cancelled"]
        if current < previous_cancelled:
            raise AssertionError("cancellation counter decreased")
        previous_cancelled = current
        if observe:
            rows.append({**original, **sim.observe_day(scans_before)})
    for order in sim.orders.values():
        order.check()
    for shipment in sim.shipments:
        if shipment.arrival_day != shipment.dispatch_day + sim.config["routes"][shipment.route]["lead_time"]:
            raise AssertionError("shipment timing differs from original route")
        if shipment.received_day is not None and shipment.received_day != shipment.arrival_day:
            raise AssertionError("early/late receipt")
    return sim, rows


def recovery(case, rows, baseline):
    kind = "baseline" if case["treatment"] == "normal" else "shutdown" if case["treatment"] == "shutdown" else "shock"
    result = recovery_metrics({**case, "treatment": kind}, rows, baseline)
    tests = {
        "overdue_zero_20_day": lambda r: r["overdue_pending_qty"] == 0,
        "pending_equal_baseline_20_day": lambda r: r["pending_dispatch"] == baseline[r["day"] - 1]["pending_dispatch"],
        "effective_equal_baseline_20_day": lambda r: r["effective_supply_position"] == baseline[r["day"] - 1]["effective_supply_position"],
    }
    for name, predicate in tests.items():
        result[name] = first_window(rows, predicate, 80, WINDOW) if kind == "shock" else None
        result[name.replace("_20_day", "_last_nonmatch_day")] = max(
            (r["day"] for r in rows if r["day"] >= 80 and not predicate(r)), default=None)
    return result


def summarize(case, sim, rows, baseline):
    totals = sim.totals["A_B"]
    breaches = [e for e in sim.commitment_events if e["route"] == "A_B" and e["event"] == "promise_breach"]
    peak = max(r["terminal_backlog"] for r in rows)
    record = {k: v for k, v in case.items() if k != "config"}
    record.update(
        days=len(rows), coal_target=case["config"]["replenishment"]["B"]["target"],
        first_promise_breach_day=breaches[0]["day"] if breaches else None,
        promise_breach_order_count=totals["breach_count"], promise_breach_qty=totals["breach_qty"],
        total_ordered=totals["ordered"], cumulative_cancelled=totals["cancelled"], order_count=totals["order_count"],
        reorder_count=totals["reorder_count"], max_supplier_queue=totals["max_queue"], max_active_orders=totals["max_active"],
        max_overdue_orders=totals["max_overdue"], cancelled_order_count=totals["cancelled_order_count"],
        final_pending=rows[-1]["pending_dispatch"], final_overdue=rows[-1]["overdue_pending_qty"],
        max_overdue=max(r["overdue_pending_qty"] for r in rows),
        max_oldest_overdue_days=max(r["oldest_overdue_days"] for r in rows),
        max_new_order_qty=max(r["new_order_qty_today"] for r in rows),
        backlog_peak=peak, backlog_peak_day=next(r["day"] for r in rows if r["terminal_backlog"] == peak),
        backlog_final=rows[-1]["terminal_backlog"], machine_days=sum(r["terminal_backlog"] for r in rows),
        terminal_delivered=sim.cumulative["terminal_delivered"],
        last200_delivery_mean=statistics.mean(r["terminal_delivery"] for r in rows[-200:]),
        last200_delivery_min=min(r["terminal_delivery"] for r in rows[-200:]),
        last200_delivery_max=max(r["terminal_delivery"] for r in rows[-200:]),
        final_on_hand=rows[-1]["on_hand"], final_in_transit=rows[-1]["in_transit"],
        final_ledger_position=rows[-1]["ledger_inventory_position"], final_effective_position=rows[-1]["effective_supply_position"],
        max_on_hand_after80=max(r["on_hand"] for r in rows if r["day"] >= 80),
        max_ledger_above_target_after80=max(max(0, r["ledger_inventory_position"] - 320) for r in rows if r["day"] >= 80),
        on_hand_above_normal_days_after80=sum(r["on_hand"] > baseline[r["day"] - 1]["on_hand"] for r in rows if r["day"] >= 80),
        active_scan_visits=sim.active_scan_visits,
        max_order_scan_visits_per_day=max(r["order_scan_visits_today"] for r in rows),
        max_abs_quantity_residual=max(abs(r[f"{good}_residual"]) for r in rows for good in ("coal", "steel", "machine")),
        max_abs_order_residual=max(abs(r["order_residual"]) for r in rows),
    )
    record.update(recovery(case, rows, baseline))
    return record


def period_summaries(case, rows):
    periods = [("startup", 1, 49), ("shock_or_reference", 50, 79),
               ("continuing_shutdown" if case["treatment"] == "shutdown" else "recovery_or_reference", 80, 600),
               ("last200", 401, 600)]
    result = []
    for name, first, last in periods:
        window = rows[first - 1:last]
        result.append({"case_id": case["case_id"], "period": name, "first_day": first, "last_day": last,
                       "production_B_mean": statistics.mean(r["production_B"] for r in window),
                       "production_C_mean": statistics.mean(r["production_C"] for r in window),
                       "terminal_delivery_mean": statistics.mean(r["terminal_delivery"] for r in window),
                       "new_order_qty": sum(r["new_order_qty_today"] for r in window),
                       "cancelled_qty": sum(r["cancelled_qty_today"] for r in window),
                       "pending_mean": statistics.mean(r["pending_dispatch"] for r in window),
                       "overdue_mean": statistics.mean(r["overdue_pending_qty"] for r in window),
                       "queue_max": max(r["supplier_queue"] for r in window),
                       "machine_days": sum(r["terminal_backlog"] for r in window),
                       "final_backlog": window[-1]["terminal_backlog"]})
    return result


def event_evidence(sim):
    selected = set()
    for route in sim.config["routes"]:
        orders = [o for o in sim.orders.values() if o.route == route]
        for day in (1, 50, 80):
            order = next((o for o in orders if o.day >= day), None)
            if order:
                selected.add(order.id)
        for kind in ("promise_breach", "cancelled"):
            event = next((e for e in sim.commitment_events if e["route"] == route and e["event"] == kind), None)
            if event:
                selected.add(event["order_id"])
        selected.update(list(sim.active_orders[route])[:2])
    return [e for e in sim.commitment_events if e["order_id"] in selected]


def write_json(path, value):
    path.write_bytes((json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8"))


def write_csv(path, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows({k: "null" if v is None else v for k, v in row.items()} for row in rows)


def generate(output_dir, measure_memory=False):
    output_dir.mkdir(parents=True, exist_ok=False)
    started = time.perf_counter()
    cases = all_cases()
    completed, execution = {}, []
    for case in cases:
        if measure_memory:
            tracemalloc.start()
        start = time.perf_counter()
        sim, rows = run_case(case)
        completed[case["case_id"]] = (sim, rows)
        elapsed = time.perf_counter() - start
        retained, peak = tracemalloc.get_traced_memory() if measure_memory else (None, None)
        if measure_memory:
            tracemalloc.stop()
        execution.append({"case_id": case["case_id"], "elapsed_seconds": elapsed,
                          "tracemalloc_retained_bytes": retained, "tracemalloc_peak_bytes": peak,
                          "active_scan_visits": sim.active_scan_visits,
                          "max_active_orders": sim.totals["A_B"]["max_active"],
                          "max_supplier_queue": sim.totals["A_B"]["max_queue"]})
    summary, periods = [], []
    for case in cases:
        sim, rows = completed[case["case_id"]]
        directory = output_dir / case["case_id"]
        directory.mkdir()
        write_json(directory / "config.json", case)
        write_csv(directory / "daily.csv", rows)
        write_csv(directory / "order_trace.csv", sim.commitment_events)
        write_csv(directory / "event_evidence.csv", event_evidence(sim))
        summary.append(summarize(case, sim, rows, completed[case["baseline_id"]][1]))
        periods.extend(period_summaries(case, rows))
    write_csv(output_dir / "summary.csv", summary)
    write_csv(output_dir / "period_summary.csv", periods)
    sources = [HERE.parent / "economy.py", HERE.parent / "fixture.json",
               HERE.parent / "inventory_round2/inventory_policy.py",
               HERE.parent / "inventory_round2/run_inventory_comparison.py",
               HERE / "order_commitment.py", HERE / "commitment_adapter.py", Path(__file__),
               HERE / "test_order_commitment.py", HERE / "inputs/ROUND3_REQUEST.md"]
    write_json(output_dir / "manifest.json", {
        "baseline_commit": BASELINE_COMMIT, "baseline_tag": BASELINE_TAG,
        "cases": [{k: v for k, v in c.items() if k != "config"} for c in cases],
        "case_count": len(cases), "days_per_case": DAYS, "simulated_case_days": len(cases) * DAYS,
        "recovery_window_days": WINDOW, "treated_route": "A_B", "no_promise_fallback": "legacy pending",
        "disposition_boundary": "B procurement, after production and before original dispatch",
        "breach_metric": "cumulative unique orders and pending quantity at first overdue procurement boundary",
        "source_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
    })
    files = {p.relative_to(output_dir).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(output_dir.rglob("*")) if p.is_file()}
    log = {"python": sys.version, "case_count": len(cases), "simulated_case_days": len(cases) * DAYS,
           "memory_measurement": "per-case Python allocations during run_case; excludes prebuilt input cases; not process RSS" if measure_memory else None,
           "elapsed_seconds": time.perf_counter() - started, "cases": execution,
           "max_abs_quantity_residual": max(r["max_abs_quantity_residual"] for r in summary),
           "max_abs_order_residual": max(r["max_abs_order_residual"] for r in summary)}
    return files, log


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True, help="A new directory outside imported evidence")
    parser.add_argument("--execution-log", type=Path)
    parser.add_argument("--measure-memory", action="store_true", help="Record per-case Python allocation peaks outside deterministic outputs")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output.is_relative_to(HERE.parent) or output == ROOT or output.is_relative_to(ROOT / "docs"):
        parser.error("Full outputs belong in .local/ or artifacts/, outside source/evidence")
    _, log = generate(output, args.measure_memory)
    if args.execution_log:
        write_json(args.execution_log, log)
    print(json.dumps(log, indent=2))


if __name__ == "__main__":
    main()
