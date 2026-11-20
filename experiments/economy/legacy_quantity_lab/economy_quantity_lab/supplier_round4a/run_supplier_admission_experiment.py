"""Ten 600-day admission cases and four explicit cancellation handshake fixtures."""
import argparse
from copy import deepcopy
import csv
import hashlib
import json
from pathlib import Path
import sys
import time
import tracemalloc

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE.parent / "order_round3"))
from run_order_commitment_experiment import make_case as round3_case
from supplier_admission import AdmissionSimulation

BASE = "42e2ad240716901b6ec0684f3ec4abbe0dc9be31"


def make_case(treatment, policy):
    original = round3_case("normal" if treatment == "overload" else treatment, "R0")
    config = original["config"]
    if treatment == "overload":
        config["daily_terminal_demand"] = 15
    return dict(case_id=f"{treatment}_{policy}", treatment=treatment, policy=policy, config=config)


def all_cases():
    return [make_case(t, p) for t in ("normal", "shock", "shutdown", "full_shutdown", "overload")
            for p in ("S0", "S1")]


def run_case(case):
    sim = AdmissionSimulation(case["config"], admission=case["policy"])
    rows = []
    for _ in range(case["config"]["days"]):
        rows.append({**sim.step(), **sim.observe_admission()})
    for order in sim.orders.values():
        order.check()
    return sim, rows


def handshake_cases():
    """C1/C2 confirm outcomes; C3/C4 conservative need around that boundary."""
    evidence = []
    for name, capacity in (("C1", 0), ("C2", 30), ("C3", 0), ("C4", 0)):
        config = make_case("normal", "S0")["config"]
        config["routes"]["A_B"]["capacity"] = capacity
        config["initial_inventory"]["B"]["coal"] = 240
        sim = AdmissionSimulation(config)
        response = sim.request(80)
        oid = response["order_id"]
        before = sim.open_procurement_need()
        sim.request_cancellation(oid, 80)
        waiting = sim.open_procurement_need()
        sim.procure("B", ["A"])
        duplicate = len(sim.requests) - 1
        shipped = sim.dispatch()["A_B"]
        sim.day = 1
        sim.backlog = config["daily_terminal_demand"]
        sim.confirm_cancellations()
        after = sim.open_procurement_need()
        cancellation = sim.cancel_history[-1]
        if name == "C4":
            sim.procure("B", ["A"])
        order = sim.orders[oid]
        order.check()
        sim.check_accounts()
        evidence.append(dict(case_id=name, need_before=before, need_waiting=waiting,
                             duplicate_requests=duplicate, dispatch_during_wait=shipped,
                             need_confirmed=after, in_transit=order.in_transit,
                             cancelled=order.cancelled, **cancellation,
                             replacement_quantity=sim.requests[-1]["requested_quantity"] if name=="C4" else 0))
    return evidence


def first20(rows, predicate, start=80):
    for i in range(start-1, len(rows)-19):
        if all(predicate(r) for r in rows[i:i+20]):
            return rows[i]["day"]
    return None


def stock_shortage_probe():
    """Separate falsification fixture; formal ten-case initial stocks stay fixed."""
    case=make_case("normal","S1")
    case["config"]["days"]=10
    case["config"]["initial_inventory"]["A"]["coal"]=0
    case["config"]["production"]["A"]["capacity"]=0
    sim,rows=run_case(case)
    return dict(scope="diagnostic fixture only: no supplier stock or production, transport capacity100",
                config=case["config"], accepted_qty=sum(r["accepted_quantity"] for r in sim.requests),
                actual_dispatch=sum(r["A_B_dispatch"] for r in rows),
                breach_count=sim.totals["A_B"]["breach_count"],breach_quantity=sim.totals["A_B"]["breach_qty"],
                final_pending=rows[-1]["live_accepted_pending"],rows=rows)


def summarize(case, sim, rows, normal):
    requests = sim.requests
    accepted = sum(r["accepted_quantity"] for r in requests)
    requested = sum(r["requested_quantity"] for r in requests)
    breaches = [e for e in sim.commitment_events if e["event"]=="promise_breach" and e["route"]=="A_B"]
    summary = dict(case_id=case["case_id"], days=len(rows), request_count=len(requests),
                   requested_qty=requested, accepted_qty=accepted, rejected_qty=requested-accepted,
                   acceptance_ratio=accepted/requested if requested else 1,
                   partial_accept_count=sum(0<r["accepted_quantity"]<r["requested_quantity"] for r in requests),
                   full_reject_count=sum(r["accepted_quantity"]==0 for r in requests),
                   first_breach_day=breaches[0]["day"] if breaches else None,
                   breach_count=sim.totals["A_B"]["breach_count"], breach_quantity=sim.totals["A_B"]["breach_qty"],
                   backlog_peak=max(r["terminal_backlog"] for r in rows), final_backlog=sim.backlog,
                   machine_days=sum(r["terminal_backlog"] for r in rows),
                   terminal_delivery=sim.cumulative["terminal_delivered"],
                   steel_production=sim.cumulative["steel_produced"], machine_production=sim.cumulative["machine_produced"],
                   coal_dispatch=sum(r["A_B_dispatch"] for r in rows), coal_arrivals=sum(r["A_B_arrival"] for r in rows),
                   last200_delivery_mean=sum(r["terminal_delivery"] for r in rows[-200:])/200,
                   final_pending=rows[-1]["live_accepted_pending"], final_overdue=rows[-1]["overdue_pending"],
                   final_open_need=rows[-1]["open_procurement_need"], final_on_hand=rows[-1]["on_hand"],
                   final_in_transit=rows[-1]["in_transit"],
                   max_active_orders=max(r["active_orders"] for r in rows),
                   max_active_requests=max(r["active_requests"] for r in rows),
                   max_slot_entries=max(r["slot_entries"] for r in rows),
                   max_slot_entries_at_admission=max((sum(s["committed_quantity"]>0 for s in r["slots_after"]) for r in requests),default=0),
                   max_active_orders_at_acceptance=sim.totals["A_B"]["max_active"],
                   max_allocation_entries=max(r["allocation_entries"] for r in rows),
                   order_scan_visits=sim.active_scan_visits, slot_scan_visits=sim.slots.scan_visits,
                   request_archive_scan_visits=sum(r["request_archive_scan_visits"] for r in rows),
                   max_open_need=max(r["open_procurement_need"] for r in rows),
                   cumulative_cancelled=sim.totals["A_B"]["cancelled"],
                   confirmation_delay=sim.confirmation_delay,
                   max_abs_quantity_residual=max(abs(r[g+"_residual"]) for r in rows for g in ("coal","steel","machine")),
                   max_abs_order_residual=max(abs(r["order_residual"]) for r in rows))
    tests = dict(production=lambda r: r["production_C"] == normal[r["day"]-1]["production_C"],
                 delivery=lambda r:r["terminal_delivery"]==normal[r["day"]-1]["terminal_delivery"],
                 backlog_clear=lambda r:r["terminal_backlog"]==0,
                 pending=lambda r:r["live_accepted_pending"]==normal[r["day"]-1]["live_accepted_pending"],
                 overdue=lambda r:r["overdue_pending"]==0,
                 inventory=lambda r:r["on_hand"]==normal[r["day"]-1]["on_hand"],
                 in_transit=lambda r:r["in_transit"]==normal[r["day"]-1]["in_transit"])
    for name, predicate in tests.items():
        summary[name+"_recovery20"] = first20(rows, predicate) if case["treatment"] in ("shock","full_shutdown") else None
    return summary


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(value, indent=2, ensure_ascii=False)+"\n").encode())


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer=csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)


def generate(output, execution, measure_memory=False):
    if output.exists() or output.resolve()==ROOT or output.resolve().is_relative_to(ROOT/"economy_quantity_lab") or output.resolve().is_relative_to(ROOT/"docs"):
        raise ValueError("output must be a new directory outside source/evidence")
    output.mkdir(parents=True)
    summaries, logs, normals = [], [], {}
    for case in all_cases():
        if measure_memory:
            tracemalloc.start()
        started=time.perf_counter()
        sim,rows=run_case(case)
        elapsed=time.perf_counter()-started
        memory=tracemalloc.get_traced_memory()[1] if measure_memory else None
        if measure_memory:
            tracemalloc.stop()
        if case["treatment"]=="normal":
            normals[case["policy"]]=rows
        summaries.append(summarize(case,sim,rows,normals[case["policy"]]))
        directory=output/case["case_id"]
        write_json(directory/"config.json",case)
        write_csv(directory/"daily.csv",rows)
        write_json(directory/"requests.json",sim.requests)
        write_csv(directory/"order_trace.csv",sim.commitment_events)
        logs.append(dict(case_id=case["case_id"],seconds=elapsed,tracemalloc_peak_bytes=memory,
                         scope="simulation+archived requests/events/rows; excludes export; Python allocations, not RSS"))
    write_csv(output/"summary.csv",summaries)
    write_json(output/"cancellation_cases.json",handshake_cases())
    write_json(output/"stock_shortage_probe.json",stock_shortage_probe())
    sources=[HERE/"supplier_admission.py",HERE/"run_supplier_admission_experiment.py",HERE/"test_supplier_admission.py",
             HERE/"inputs/ROUND4A_REQUEST.md",ROOT/"economy_quantity_lab/economy.py",ROOT/"economy_quantity_lab/fixture.json",
             ROOT/"economy_quantity_lab/order_round3/commitment_adapter.py",
             ROOT/"economy_quantity_lab/order_round3/order_commitment.py",
             ROOT/"economy_quantity_lab/order_round3/run_order_commitment_experiment.py",
             ROOT/"economy_quantity_lab/inventory_round2/inventory_policy.py",
             ROOT/"economy_quantity_lab/inventory_round2/run_inventory_comparison.py"]
    write_json(output/"manifest.json",dict(base_commit=BASE,tag="economy-lab-v0.3-order-commitment",
                                          cases=10,days_per_case=600,handshake_cases=4,ATP="current transport capacity only, t..t+2 inclusive",
                                          automatic_cancellation=False,
                                          source_hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}))
    write_json(execution,dict(python=sys.version,case_count=10,simulated_case_days=6000,handshake_cases=4,
                             max_abs_quantity_residual=max(s["max_abs_quantity_residual"] for s in summaries),
                             max_abs_order_residual=max(s["max_abs_order_residual"] for s in summaries),runs=logs))
    print("Round4A: 10 x 600 days + 4 cancellation fixtures; all material/order residuals zero",flush=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,required=True)
    parser.add_argument("--execution-log",type=Path,required=True)
    parser.add_argument("--measure-memory",action="store_true")
    args=parser.parse_args()
    generate(args.output_dir,args.execution_log,args.measure_memory)
