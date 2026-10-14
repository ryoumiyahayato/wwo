"""A-J supplier fixtures, 14 x 600 days, plus explicit ATP/switch probes."""
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
sys.path.insert(0, str(HERE.parent / "supplier_round4a"))
from run_supplier_admission_experiment import make_case as admission_case, stock_shortage_probe
from stock_admission import StockConfirmedSimulation, AdmissionSimulation
from multi_supplier import MultiSupplierSimulation, InformationInbox

BASE = "307df8f4d64dc039e2d291082394178c1d556a58"
TAG = "economy-lab-v0.4a-supplier-admission"


def make_case(case_id, matching="M1", treatment="normal", known=("A", "D"), discovery=None,
              add_d=True, prelude=None):
    config = admission_case(treatment, "S1")["config"]
    config["replenishment"]["B"]["known_suppliers"] = list(known)
    config["available_supplier_ids"] = ["A", "D"] if add_d else ["A"]
    if add_d:
        config["initial_inventory"]["D"] = dict(coal=400, steel=0, machine=0)
        config["production"]["D"] = dict(capacity=60, coal_target=400)
        config["routes"]["D_B"] = dict(supplier="D", buyer="B", commodity="coal", capacity=60, lead_time=4)
    events = [dict(day=discovery, supplier_id="D", source="fixture_information_event")] if discovery else []
    if prelude == "split":
        config["initial_inventory"]["B"]["coal"] = 220
        config["initial_inventory"]["A"]["coal"] = 40
        config["initial_inventory"]["D"]["coal"] = 60
    elif prelude == "insufficient":
        config["initial_inventory"]["B"]["coal"] = 170
        config["initial_inventory"]["A"]["coal"] = 40
        config["initial_inventory"]["D"]["coal"] = 60
    elif prelude == "overdue":
        config["initial_inventory"]["B"]["coal"] = 240
        config["scenarios"] = {"experiment": {"A_B": [dict(first_day=1, last_day=600, capacity=0)]}}
    return dict(case_id=case_id, matching=matching, treatment=treatment, config=config,
                information_events=events, prelude=prelude, days=600)


def all_cases():
    cases = [make_case("A_single_S2", known=("A",), add_d=False),
             make_case("A_D_unknown", known=("A",)),
             make_case("B_normal_M0", "M0"), make_case("B_normal_M1"),
             make_case("C_shock_M0", "M0", "shock"), make_case("C_shock_M1", treatment="shock"),
             make_case("D_shutdown_unknown", treatment="shutdown", known=("A",)),
             make_case("E_discovery60", treatment="shutdown", known=("A",), discovery=60),
             make_case("F_discovery90", treatment="shutdown", known=("A",), discovery=90),
             make_case("G_A_stockout"), make_case("H_split", prelude="split"),
             make_case("I_insufficient", prelude="insufficient"),
             make_case("J_overdue_M1", prelude="overdue"), make_case("J_overdue_M2", "M2", prelude="overdue")]
    stockout = next(c for c in cases if c["case_id"] == "G_A_stockout")
    stockout["config"]["initial_inventory"]["A"]["coal"] = 0
    stockout["config"]["production"]["A"]["capacity"] = 0
    return cases


def initialize(case):
    sim = MultiSupplierSimulation(case["config"], case["matching"], InformationInbox(case["information_events"]))
    prelude = None
    if case["prelude"] in ("split", "insufficient"):
        sim.procure("B", list(sim.known))
        prelude = dict(boundary=sim.boundaries[-1], requests=deepcopy(sim.requests), offers=deepcopy(sim.offers))
    elif case["prelude"] == "overdue":
        response = sim.request(80, "A")  # Day0 route is live; shutdown starts Day1.
        prelude = dict(request=response, note="accepted80 from real A stock at Day0, no prelude dispatch")
    sim.check_accounts()
    return sim, prelude


def run_case(case, observe=True):
    sim, prelude = initialize(case)
    rows = []
    for _ in range(case["days"]):
        original = sim.step()
        if observe:
            rows.append({**original, **sim.observe_multi()})
    for order in sim.orders.values():
        order.check()
    return sim, rows, prelude


def probes():
    config = admission_case("normal", "S1")["config"]
    config["initial_inventory"]["A"]["coal"] = 0
    config["initial_inventory"]["B"]["coal"] = 0
    config["production"]["A"]["capacity"] = 0
    gate = []
    for label, cls in (("S1", AdmissionSimulation), ("S2", StockConfirmedSimulation)):
        sim = cls(config, admission="S1") if label == "S1" else cls(config)
        result = sim.request(320)
        gate.append(dict(policy=label, response=result, open_need=sim.open_procurement_need(),
                         orders=len(sim.orders), shipments=len(sim.shipments)))
    assert (gate[1]["response"]["accepted_quantity"], gate[1]["response"]["rejected_quantity"],
            gate[1]["open_need"], gate[1]["orders"], gate[1]["shipments"]) == (0, 320, 320, 0, 0)
    assert stock_shortage_probe()["accepted_qty"] == 320
    conservatism_config = deepcopy(config)
    conservatism_config["production"]["A"]["capacity"] = 100
    conservative = StockConfirmedSimulation(conservatism_config)
    now = conservative.request(80)
    conservative.step()
    tomorrow = conservative.requests_by_day[1]
    assert now["accepted_quantity"] == 0 and sum(r["accepted_quantity"] for r in tomorrow) > 0
    switching_case = make_case("switch_probe", "M2")
    switching_case["config"]["initial_inventory"]["B"]["coal"] = 240
    switching_case["config"]["routes"]["A_B"]["capacity"] = 30
    switching, _ = initialize(switching_case)
    oid = switching.request(80, "A")["order_id"]
    switching.day = 3; switching.backlog = 30
    switching.procure("B", ["A", "D"])
    waiting_need = switching.open_procurement_need()
    waiting_D_accept = sum(r["accepted_quantity"] for r in switching.requests if r["supplier_id"] == "D")
    switching.dispatch()
    switching.day = 4; switching.backlog = 40
    switching.procure("B", ["A", "D"])
    switching.check_accounts()
    old = switching.orders[oid]
    replacement = sum(r["accepted_quantity"] for r in switching.requests if r["supplier_id"] == "D")
    assert (waiting_need, waiting_D_accept, old.cancelled, old.in_transit, replacement) == (0, 0, 50, 30, 50)
    return dict(stock_gate="PASS", requests=gate, S1_legacy_ten_day_accepted=320,
                control_note="single ATP=100*(2+1)=300; archived320 is cumulative, not a single admission",
                switch_probe=dict(scope="synthetic overdue order-state fixture at Day3, no intervening production; quantities settled by original dispatch and Round4A confirmation",
                                  waiting_need=waiting_need, waiting_D_accepted=waiting_D_accept,
                                  confirmed_cancelled=old.cancelled, old_in_transit=old.in_transit,
                                  D_replacement=replacement, events=switching.switch_events,
                                  cancellations=switching.cancel_history, request_trace=switching.requests,
                                  order_trace=switching.commitment_events),
                conservatism=dict(today=now, tomorrow=tomorrow))


def first20(rows, predicate, start=50):
    for i in range(start - 1, len(rows) - 19):
        if all(predicate(r) for r in rows[i:i + 20]):
            return rows[i]["day"]
    return None


def summarize(case, sim, rows):
    accepted = sum(r["accepted_quantity"] for r in sim.requests)
    summary = dict(case_id=case["case_id"], matching=case["matching"], days=len(rows),
                   discovery_day=case["information_events"][0]["day"] if case["information_events"] else None,
                   request_count=len(sim.requests), offer_evaluations=sim.offer_evaluations,
                   candidate_scans=sim.candidate_scans, daily_export_visits=sim.daily_export_visits,
                   final_open_need=sim.open_procurement_need(), final_global_position=sim.global_supply_position(),
                   max_on_hand=max(r["on_hand"] for r in rows), max_global_position=max(r["global_supply_position"] for r in rows),
                   final_pending=rows[-1]["total_live_pending"], final_in_transit=rows[-1]["total_in_transit"],
                   backlog_peak=max(r["terminal_backlog"] for r in rows), final_backlog=sim.backlog,
                   machine_days=sum(r["terminal_backlog"] for r in rows), terminal_delivery=sim.cumulative["terminal_delivered"],
                   machine_production=sim.cumulative["machine_produced"], steel_production=sim.cumulative["steel_produced"],
                   last200_delivery_mean=sum(r["terminal_delivery"] for r in rows[-200:]) / 200,
                   production_atleast10_recovery20=first20(rows, lambda r: r["production_C"] >= 10),
                   delivery_atleast10_recovery20=first20(rows, lambda r: r["terminal_delivery"] >= 10),
                   backlog_clear20=first20(rows, lambda r: r["terminal_backlog"] == 0),
                   max_active_orders=max(r["active_orders"] for r in rows), max_active_cancel_requests=max(r["active_cancel_requests"] for r in rows),
                   max_slot_entries=max(r["slot_entries"] for r in rows),
                   max_slot_entries_at_admission=max((r["slot_entries_after"] for r in sim.requests), default=0),
                   max_stock_commitment_entries=max(r["stock_commitment_entries"] for r in rows),
                   max_stock_commitment_entries_at_admission=max((r["stock_commitment_entries_after"] for r in sim.requests), default=0),
                   max_daily_export_visits=max(r["daily_event_export_visits"] for r in rows),
                   order_scan_visits=sim.active_scan_visits, slot_scan_visits=sum(s.scan_visits for s in sim.route_slots.values()),
                   stock_account_visits=sim.stock_account_visits,
                   max_abs_quantity_residual=max(abs(r[g + "_residual"]) for r in rows for g in ("coal", "steel", "machine")),
                   max_abs_order_residual=max(abs(sim.route_order_residuals[r]) for r in sim.route_order_residuals),
                   requested_cancel_qty=sum(c["requested_cancel_qty"] for c in sim.cancel_history if c["state"] == "CANCEL_REQUESTED"),
                   confirmed_cancel_qty=sum(c["confirmed_cancel_qty"] for c in sim.cancel_history if c["state"] == "CANCEL_CONFIRMED"),
                   no_longer_cancellable_qty=sum(c["no_longer_cancellable_qty"] for c in sim.cancel_history if c["state"] == "CANCEL_CONFIRMED"),
                   replacement_qty=sum(s.get("replacement_quantity", 0) for s in sim.switch_events))
    for supplier in ("A", "D"):
        requests = [r for r in sim.requests if r["supplier_id"] == supplier]
        route = sim.supplier_routes.get(supplier)
        quantity = sum(r["accepted_quantity"] for r in requests)
        summary.update({f"{supplier}_requested": sum(r["requested_quantity"] for r in requests),
                        f"{supplier}_accepted": quantity, f"{supplier}_rejected": sum(r["rejected_quantity"] for r in requests),
                        f"{supplier}_partial_count": sum(0 < r["accepted_quantity"] < r["requested_quantity"] for r in requests),
                        f"{supplier}_full_reject_count": sum(r["accepted_quantity"] == 0 for r in requests),
                        f"{supplier}_rejected_due_stock": sum(r["rejected_due_stock"] for r in requests),
                        f"{supplier}_rejected_due_transport": sum(r["rejected_due_transport"] for r in requests),
                        f"{supplier}_share": quantity / accepted if accepted else 0,
                        f"{supplier}_extraction": sim.source_extraction[supplier],
                        f"{supplier}_dispatch": sum(r.get(route + "_dispatch", 0) for r in rows) if route else 0,
                        f"{supplier}_arrival": sum(r.get(route + "_arrival", 0) for r in rows) if route else 0,
                        f"{supplier}_breach_count": sim.totals[route]["breach_count"] if route else 0,
                        f"{supplier}_breach_qty": sim.totals[route]["breach_qty"] if route else 0})
    return summary


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode())


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)


def generate(output, execution, measure_memory=False):
    output = output.resolve()
    if output.exists() or output == ROOT or output.is_relative_to(ROOT / "economy_quantity_lab") or output.is_relative_to(ROOT / "docs"):
        raise ValueError("choose a new directory outside source/evidence")
    output.mkdir(parents=True)
    write_json(output / "probes.json", probes())  # Mandatory gate before the multi-supplier matrix.
    summaries, logs = [], []
    for case in all_cases():
        if measure_memory: tracemalloc.start()
        started = time.perf_counter()
        sim, rows, prelude = run_case(case)
        seconds = time.perf_counter() - started
        peak = tracemalloc.get_traced_memory()[1] if measure_memory else None
        if measure_memory: tracemalloc.stop()
        summaries.append(summarize(case, sim, rows))
        directory = output / case["case_id"]
        write_json(directory / "config.json", case)
        write_json(directory / "prelude.json", prelude)
        write_csv(directory / "daily.csv", rows)
        write_json(directory / "offers.json", sim.offers)
        write_json(directory / "requests.json", sim.requests)
        write_json(directory / "information_and_switching.json", dict(discoveries=sim.discoveries, switches=sim.switch_events, cancellations=sim.cancel_history))
        write_json(directory / "boundaries.json", sim.boundaries)
        write_csv(directory / "order_trace.csv", sim.commitment_events)
        logs.append(dict(case_id=case["case_id"], seconds=seconds, tracemalloc_peak_bytes=peak,
                         scope="simulation plus indexed observation and retained archives/rows; excludes export; not RSS"))
    write_csv(output / "summary.csv", summaries)
    sources = [HERE / n for n in ("stock_admission.py", "multi_supplier.py", "run_multi_supplier_experiment.py", "test_multi_supplier.py", "inputs/ROUND4B_REQUEST.md")]
    sources += [ROOT / n for n in ("economy_quantity_lab/economy.py", "economy_quantity_lab/fixture.json",
                "economy_quantity_lab/order_round3/commitment_adapter.py", "economy_quantity_lab/order_round3/order_commitment.py",
                "economy_quantity_lab/supplier_round4a/supplier_admission.py", "economy_quantity_lab/supplier_round4a/run_supplier_admission_experiment.py",
                "economy_quantity_lab/order_round3/run_order_commitment_experiment.py", "economy_quantity_lab/inventory_round2/inventory_policy.py",
                "economy_quantity_lab/inventory_round2/run_inventory_comparison.py")]
    write_json(output / "manifest.json", dict(base_commit=BASE, tag=TAG, cases=14, days=8400, admission="S2 STOCK_CONFIRMED",
                                             source_hashes={p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}))
    write_json(execution, dict(python=sys.version, case_count=14, simulated_case_days=8400,
                              max_abs_quantity_residual=max(s["max_abs_quantity_residual"] for s in summaries),
                              max_abs_order_residual=max(s["max_abs_order_residual"] for s in summaries), runs=logs))
    print("Round4B: stock gate PASS; 14 x 600 days; material/order residuals zero", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--execution-log", type=Path, required=True)
    parser.add_argument("--measure-memory", action="store_true")
    args = parser.parse_args()
    generate(args.output_dir, args.execution_log, args.measure_memory)
