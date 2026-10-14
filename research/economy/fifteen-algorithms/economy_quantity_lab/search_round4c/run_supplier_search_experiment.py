"""Eighteen 600-day search cases and indexed/multi-commodity/multi-buyer probes."""
import argparse
from copy import deepcopy
from dataclasses import asdict
import csv
import hashlib
import json
from pathlib import Path
import sys
import time
import tracemalloc

from supplier_directory import DirectoryEntry, SupplierDirectory, SearchKnowledge
from supplier_pool import generate_pool
from search_simulation import SearchSimulation, InformationInbox
from stock_admission import StockCommitments

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BASE = "be9dfd54999ff156e5881b501118a53f151d68c8"
TAG = "economy-lab-v0.4b-multi-supplier"


def make_case(treatment="normal", policy="Q0", count=10, case_id=None):
    config = generate_pool(count)
    events = []
    if treatment in ("insufficient", "local", "regional", "wide", "bad", "timing"):
        for entry in config["directory_entries"]:
            entry["discoverability_channel"] = "DIRECTORY" if entry["supplier_id"] in ("A", "D", "E") else "ARCHIVE_ONLY"
        if treatment != "timing":
            config["routes"]["A_B"]["capacity"] = 30
            config["routes"]["D_B"]["capacity"] = 30
        else:
            config["scenarios"] = {"experiment": {r: [dict(first_day=50, last_day=600, capacity=0)] for r in ("A_B", "D_B")}}
            if policy == "Q0":
                events = [dict(day=60, supplier_id="E", source="fixture_information_event")]
        entry_e = next(e for e in config["directory_entries"] if e["supplier_id"] == "E")
        zone = "Z0" if treatment in ("local", "bad", "timing") else "Z7" if treatment == "wide" else "Z1"
        lead = 8 if treatment == "wide" else 2 if zone == "Z0" else 4
        entry_e.update(search_zone=zone, nominal_lead_band=lead, advertised_capacity_band="up_to_100")
        config["production"]["E"]["capacity"] = 80
        config["routes"]["E_B"].update(capacity=100, lead_time=lead)
        if treatment in ("regional", "bad"):
            bad = "S003" if treatment == "regional" else "E"
            config["initial_inventory"][bad]["coal"] = 0
            config["production"][bad]["capacity"] = 0
            config["routes"][bad+"_B"]["capacity"] = 100
            bad_entry = next(e for e in config["directory_entries"] if e["supplier_id"] == bad)
            bad_entry.update(search_zone="Z0", nominal_lead_band=2, discoverability_channel="DIRECTORY")
            if treatment == "bad":
                good = next(e for e in config["directory_entries"] if e["supplier_id"] == "S003")
                good.update(search_zone="Z1", nominal_lead_band=4, discoverability_channel="DIRECTORY")
                config["production"]["S003"]["capacity"] = 80
                config["routes"]["S003_B"].update(capacity=100, lead_time=4)
    return dict(case_id=case_id or f"{treatment}_{policy}_{count}", treatment=treatment, policy=policy,
                config=config, information_events=events, result_limit=3, days=600)


def all_cases():
    cases = [make_case(t, q, case_id=f"{letter}_{t}_{q}")
             for letter, t in (("A", "normal"), ("B", "insufficient"), ("C", "local"),
                               ("D", "regional"), ("E", "wide"), ("F", "bad")) for q in ("Q0", "Q1")]
    cases += [make_case("normal", "Q0", n, f"{letter}_scale{n}") for letter, n in (("G", 10), ("H", 50), ("I", 200))]
    cases += [make_case("timing", q, case_id=f"J_timing_{q}") for q in ("Q0", "Q1")]
    cases += [make_case("normal", "Q0", 2, "K_two_supplier_off")]
    return cases


def run_case(case, observe=True):
    sim = SearchSimulation(case["config"], case["policy"], InformationInbox(case["information_events"]), case["result_limit"])
    rows = []
    for _ in range(case["days"]):
        base = sim.step()
        if observe: rows.append({**base, **sim.observe_search()})
    for order in sim.orders.values(): order.check()
    return sim, rows


def index_scale_probes():
    result = []
    for count in (10, 50, 200):
        config = generate_pool(count)
        directory = SupplierDirectory([DirectoryEntry(**e) for e in config["directory_entries"]])
        knowledge = SearchKnowledge("B", "coal", ("A", "D"))
        knowledge.issue(50, "LOCAL")  # Explicit interface probe, not a Q1 trigger during sufficient supply.
        assert not knowledge.deliver(50, directory)
        before = sorted(knowledge.known)
        delivered = knowledge.deliver(51, directory)
        result.append(dict(world_suppliers=count, build_visits=directory.build_visits,
                           bucket_count=len(directory.buckets), query_visits=directory.query_visits,
                           bucket_lookups=directory.bucket_lookups, result_count=len(delivered),
                           known_before_delivery=before, known_after_delivery=sorted(knowledge.known),
                           requests=[asdict(r) for r in knowledge.requests], events=knowledge.events,
                           query_audit=directory.query_audit))
    return result


def extensibility_probes():
    commodities = ("coal", "steel", "machine", "grain", "timber")
    entries = [DirectoryEntry(f"P{i:03d}", commodities[i % 5], f"Z{i % 10}", f"probe_place_{i}",
                              True, (2, 4, 6, 8)[i % 4], "coarse") for i in range(200)]
    directory = SupplierDirectory(entries)
    known = [e.supplier_id for e in entries if e.commodity == "coal"][:5]
    knowledge = SearchKnowledge("B", "coal", known)
    knowledge.issue(1, "LOCAL"); knowledge.deliver(2, directory)
    assert all(e.commodity == "coal" for e in directory.search("coal", "Z0", "WIDE", 5))
    mixed = dict(suppliers=200, commodities=list(commodities), zones=10, buyer_count=1,
                 active_commodity="coal", directory_only_other_commodities=list(commodities[1:]),
                 initially_known=known, known_after=sorted(knowledge.known), build_visits=directory.build_visits,
                 query_audit=directory.query_audit)
    directory3 = SupplierDirectory([DirectoryEntry(s, "coal", "Z0", "place_"+s, True, 2, "coarse") for s in ("A", "D", "E")])
    buyers = {"B1": SearchKnowledge("B1", "coal", ("A",)), "B2": SearchKnowledge("B2", "coal", ("D",))}
    buyers["B1"].issue(0, "LOCAL")
    assert buyers["B2"].pending is None and buyers["B2"].known == {"D"}
    buyers["B2"].issue(0, "LOCAL")
    for buyer in buyers.values(): buyer.deliver(1, directory3)
    stock = {"A": 100, "D": 60, "E": 0}
    book = StockCommitments()
    requests = []
    for order_id, buyer_id in enumerate(("B1", "B2"), 1):
        assert "A" in buyers[buyer_id].known
        accepted = min(80, book.uncommitted("A", "coal", stock["A"]))
        if accepted: book.reserve(order_id, "A", "coal", accepted, stock["A"])
        requests.append(dict(order_id=order_id, buyer=buyer_id, supplier="A", requested=80,
                             accepted=accepted, rejected=80-accepted))
    assert [r["accepted"] for r in requests] == [80, 20]
    book.check({supplier: {"coal": q} for supplier, q in stock.items()})
    two_buyers = dict(scope="interface-only, no second production chain or Simulation", buyer_count=2,
                      supplier_count=3, commodity="coal", stock=stock, shared_stock_committed=book.totals[("A", "coal")],
                      requests=requests, buyer_knowledge={b: sorted(k.known) for b, k in buyers.items()},
                      search_events={b: k.events for b, k in buyers.items()})
    return dict(index_scale=index_scale_probes(), mixed_commodity=mixed, multiple_buyers=two_buyers)


def summarize(case, sim, rows):
    search_events = sim.knowledge.events
    completed = [e for e in search_events if e["event"].startswith("SEARCH_COMPLETED")]
    result = dict(case_id=case["case_id"], policy=case["policy"], days=len(rows),
                  world_suppliers=len(sim.world_ids), directory_build_visits=sim.directory.build_visits,
                  directory_indexed_suppliers=len(sim.directory.indexed_ids), directory_buckets=len(sim.directory.buckets),
                  initial_known=2, final_known=len(sim.known), search_requests=len(sim.knowledge.requests),
                  first_search_day=sim.knowledge.requests[0].requested_day if sim.knowledge.requests else None,
                  first_result_day=completed[0]["day"] if completed else None,
                  search_scopes="|".join(r.scope for r in sim.knowledge.requests),
                  no_result_searches=sum(e["event"] == "SEARCH_COMPLETED_NO_RESULTS" for e in search_events),
                  query_bucket_visits=sim.directory.query_visits, results_returned=sim.directory.results_returned,
                  directory_bucket_lookups=sim.directory.bucket_lookups,
                  matching_candidates=sim.candidate_scans, offers_queried=sim.offer_evaluations,
                  max_daily_matching=max(r["matching_candidate_visits_today"] for r in rows),
                  max_daily_offers=max(r["offers_queried_today"] for r in rows),
                  active_orders_peak=max(r["active_orders"] for r in rows), shipments=len(sim.shipments),
                  source_plan_visits=sim.source_plan_visits, world_account_route_visits=sim.account_route_visits,
                  world_export_route_visits=sim.world_export_route_visits,
                  final_open_need=sim.open_procurement_need(), final_backlog=sim.backlog,
                  backlog_peak=max(r["terminal_backlog"] for r in rows),
                  machine_days=sum(r["terminal_backlog"] for r in rows), terminal_delivery=sim.cumulative["terminal_delivered"],
                  last200_delivery_mean=sum(r["terminal_delivery"] for r in rows[-200:])/200,
                  total_coal_extraction=sum(sim.source_extraction.values()),
                  max_abs_quantity_residual=max(abs(r[g+"_residual"]) for r in rows for g in ("coal", "steel", "machine")),
                  max_abs_order_residual=max(abs(v) for v in sim.route_order_residuals.values()))
    rescue = "S003" if case["treatment"] == "bad" else "E"
    result["rescue_supplier"] = rescue if rescue in sim.server_routes else None
    for label, predicate, records, key in (
        ("discovery", lambda r:r["supplier_id"] == rescue, sim.discoveries, "day"),
        ("query", lambda r:r["supplier_id"] == rescue, sim.offers, "offer_day"),
        ("dispatch", lambda r:r["route"] == rescue+"_B" and r["event"] == "dispatched", sim.events, "day"),
        ("arrival", lambda r:r["route"] == rescue+"_B" and r["event"] == "arrived", sim.events, "day")):
        result["first_rescue_"+label] = next((r[key] for r in records if predicate(r)), None)
    result["rescue_accepted"] = sum(r["accepted_quantity"] for r in sim.requests if r["supplier_id"] == rescue)
    return result


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes((json.dumps(data, indent=2, ensure_ascii=False)+"\n").encode())


def write_csv(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)


def extension_gate(summaries, probes):
    checks = dict(world200=any(s["world_suppliers"] == 200 and s["days"] == 600 for s in summaries),
                  fixed_known_work=all(s["max_daily_matching"] <= 2 and s["offers_queried"] == 1198
                                      for s in summaries if s["case_id"] in ("G_scale10", "H_scale50", "I_scale200")),
                  search_changes_knowledge=any(s["policy"] == "Q1" and s["results_returned"] and s["final_known"] > 2 for s in summaries),
                  bounded_indexed_results=all(p["result_count"] <= 3 and p["bucket_lookups"] == 1 and p["query_visits"] <= 5 for p in probes["index_scale"]),
                  commodity_isolation=all(q["commodity"] == "coal" for q in probes["mixed_commodity"]["query_audit"]),
                  shared_two_buyer_stock=probes["multiple_buyers"]["shared_stock_committed"] == 100 and
                                         [r["accepted"] for r in probes["multiple_buyers"]["requests"]] == [80, 20],
                  quantity_order_accounts=all(s["max_abs_quantity_residual"] == s["max_abs_order_residual"] == 0 for s in summaries))
    if not all(checks.values()): raise AssertionError(f"EXTENSIBILITY_GATE FAIL: {checks}")
    return dict(EXTENSIBILITY_GATE="PASS", checks=checks,
                scope="expressiveness and tested interface bounds; latency/future isolation also verified by the test entry point, not economic validity")


def generate(output, execution, measure_memory=False):
    output = output.resolve()
    if output.exists() or output == ROOT or output.is_relative_to(ROOT/"economy_quantity_lab") or output.is_relative_to(ROOT/"docs"):
        raise ValueError("new output directory outside source/evidence required")
    output.mkdir(parents=True)
    summaries, logs = [], []
    for case in all_cases():
        if measure_memory: tracemalloc.start()
        started = time.perf_counter(); sim, rows = run_case(case); seconds = time.perf_counter()-started
        peak = tracemalloc.get_traced_memory()[1] if measure_memory else None
        if measure_memory: tracemalloc.stop()
        summaries.append(summarize(case, sim, rows))
        directory = output/case["case_id"]
        write_json(directory/"config.json", case)
        write_json(directory/"directory.json", case["config"]["directory_entries"])
        write_csv(directory/"daily.csv", rows)
        write_json(directory/"search.json", dict(requests=[asdict(r) for r in sim.knowledge.requests],
                                                 events=sim.knowledge.events, query_audit=sim.directory.query_audit))
        write_json(directory/"offers.json", sim.offers); write_json(directory/"requests.json", sim.requests)
        write_csv(directory/"order_trace.csv", sim.commitment_events)
        write_json(directory/"discoveries.json", sim.discoveries); write_json(directory/"boundaries.json", sim.boundaries)
        sources = []
        for supplier in sim.world_ids:
            route = sim.server_routes[supplier]; pending, transit = sim.balances(route)
            sources.append(dict(supplier_id=supplier, initial_coal=case["config"]["initial_inventory"][supplier]["coal"],
                                extraction=sim.source_extraction[supplier], on_hand=sim.stock[supplier]["coal"],
                                stock_committed=sim.stock_commitments.totals.get((supplier, "coal"), 0),
                                pending=pending, in_transit=transit, **sim.totals[route]))
        write_csv(directory/"supplier_sources.csv", sources)
        logs.append(dict(case_id=case["case_id"], seconds=seconds, tracemalloc_peak_bytes=peak,
                         scope="construction, physical simulation, indexed observation and archives; excludes file export; not RSS"))
        print(case["case_id"], "600 days complete", flush=True)
    write_csv(output/"summary.csv", summaries)
    probes = extensibility_probes()
    write_json(output/"extensibility_probes.json", probes)
    write_json(output/"extension_gate.json", extension_gate(summaries, probes))
    paths = [HERE/n for n in ("supplier_directory.py", "supplier_pool.py", "search_simulation.py", "run_supplier_search_experiment.py", "test_supplier_search.py", "inputs/ROUND4C_REQUEST.md")]
    paths += [ROOT/n for n in ("economy_quantity_lab/economy.py", "economy_quantity_lab/fixture.json",
        "economy_quantity_lab/multi_round4b/stock_admission.py", "economy_quantity_lab/multi_round4b/multi_supplier.py",
        "economy_quantity_lab/multi_round4b/run_multi_supplier_experiment.py", "economy_quantity_lab/supplier_round4a/supplier_admission.py",
        "economy_quantity_lab/supplier_round4a/run_supplier_admission_experiment.py", "economy_quantity_lab/order_round3/commitment_adapter.py",
        "economy_quantity_lab/order_round3/order_commitment.py", "economy_quantity_lab/order_round3/run_order_commitment_experiment.py",
        "economy_quantity_lab/inventory_round2/inventory_policy.py", "economy_quantity_lab/inventory_round2/run_inventory_comparison.py")]
    write_json(output/"manifest.json", dict(base_commit=BASE, tag=TAG, cases=18, simulated_case_days=10800,
                                           extensibility_gate="PASS", source_hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}))
    write_json(execution, dict(python=sys.version, case_count=18, simulated_case_days=10800,
                              max_abs_quantity_residual=max(r["max_abs_quantity_residual"] for r in summaries),
                              max_abs_order_residual=max(r["max_abs_order_residual"] for r in summaries), runs=logs))
    print("Round4C complete: 18 x 600 days; indexed and extensibility probes completed", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True); parser.add_argument("--execution-log", type=Path, required=True)
    parser.add_argument("--measure-memory", action="store_true")
    args = parser.parse_args(); generate(args.output_dir, args.execution_log, args.measure_memory)
