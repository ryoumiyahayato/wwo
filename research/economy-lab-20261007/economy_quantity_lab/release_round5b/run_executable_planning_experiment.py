"""39x600-day release cases, actual partial-cancel race and dated interface probes."""
import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import sys
import time
import tracemalloc

from release_simulation import ExecutableSimulation
from planning_release import ReleaseBook,need_components
from run_demand_planning_experiment import make_case as old_case,probes as old_probes,write_json,write_csv
from demand_planning import Supply,Recipe,RecipeGraph
from stock_admission import SupplierOffer

HERE=Path(__file__).resolve().parent; ROOT=HERE.parent.parent
BASE="98ead27160fec2eecb545f3bc9f67e690e13bbf1"
TAG="economy-lab-v0.5-demand-planning"


def make_case(treatment="normal",policy="X0",horizon=10,days=600):
    case=old_case("normal" if treatment in ("stale","partial") else treatment,"P3",horizon,days)
    case.update(case_id=f"{treatment}_{policy}_H{horizon}",execution_policy=policy,prelude=None)
    if treatment in ("stale","partial"):
        case["prelude"]="ACCEPT_A_80_DAY0"
        case["config"]["scenarios"]={"experiment":{"A_B":[dict(first_day=1,last_day=600,capacity=0)]}}
        if treatment=="partial":
            case["config"]["scenarios"]["experiment"]["A_B"]=[dict(first_day=1,last_day=2,capacity=0),
                dict(first_day=3,last_day=3,capacity=30),dict(first_day=4,last_day=600,capacity=0)]
    return case


def all_cases():
    groups=[("A","normal",10),("B","wide",10),("C","wide",5),("D","wide",20),
            ("E","mixed_lead",10),("F","step_up",10),("G","step_down",10),("H","spike",10),
            ("I","insufficient",10),("J","factory_cap",10),("K","steel_cap",10),
            ("L","stale",10),("R","recovery",10)]
    cases=[]
    for letter,t,h in groups:
        for policy in ("X0","X1","X2"):
            case=make_case(t,policy,h); case["case_id"]=f"{letter}_{t}_{policy}_H{h}"; cases.append(case)
    return cases


def initialize(case):
    sim=ExecutableSimulation(case)
    if case.get("prelude"):
        response=sim.request(80,"A")
        assert response["accepted_quantity"]==80
        sim.check_accounts()
    return sim


def run_case(case,observe=True):
    sim=initialize(case); rows=[]
    for _ in range(case["days"]):
        physical=sim.step()
        sim.allocations_by_day[sim.day]=list(sim.coverage.allocations.values())
        if observe: rows.append({**physical,**sim.observe_search(),**sim.observe_planning(),**sim.observe_release()})
    for order in sim.orders.values(): order.check()
    return sim,rows


def quote(supplier,day,lead,quantity=100):
    return SupplierOffer(supplier,"coal",day,quantity,day,lead,day+lead,"INTERFACE_PUBLIC_QUOTE")


def partial_probe():
    sim,rows=run_case(make_case("partial","X2",days=12))
    records=[r for r in sim.cancel_history if r["order_id"]==1]
    confirmed=[r for r in records if r["state"]=="CANCEL_CONFIRMED"]
    replacements=[r for r in sim.release_requests if r["old_order_id"]==1 and r["action"]=="CONFIRMED_REPLACEMENT"]
    return dict(scope="12 actual inherited step/production/dispatch/receive days, no fabricated shipment",rows=rows,
                cancellation=records,confirmed=confirmed,replacements=replacements,
                original_order=dict(quantity=sim.orders[1].quantity,pending=sim.orders[1].pending_dispatch,
                                    transit=sim.orders[1].in_transit,delivered=sim.orders[1].delivered,cancelled=sim.orders[1].cancelled),
                original_order_events=[r for r in sim.events if r["order_id"]==1],
                max_quantity_residual=max(abs(r[g+"_residual"]) for r in rows for g in ("coal","steel","machine")),
                order_residual=sim.route_order_residuals["A_B"])


def interface_probes():
    boundary=[]
    for lead in (9,10,11):
        book=ReleaseBook(); day=100; horizon=10
        records=[("B","coal",date,"FIRM" if date<day+horizon else "PROJECTED",80,"OBSERVED_RATE")
                 for date in range(day,day+horizon+lead)]
        book.revise(day,records,lead); book.reconcile(day,[])
        eligible=book.executable(day,("B","coal"),quote("A",day,lead))
        assert len(eligible)==1 and book.active[eligible[0][0]].need_by_day==day+lead
        boundary.append(dict(conservative_lead=lead,production_horizon=horizon,visibility=horizon+lead,
                             released_bucket=book.active[eligible[0][0]].record(),release_day=day,checks=book.release_by_day[day]))
    book=ReleaseBook(); day=10
    book.revise(day,[("B","coal",day+d,"FIRM" if d<10 else "PROJECTED",20,"PROBE") for d in (2,5,9,13)],12)
    book.reconcile(day,[])
    selected=[]
    for supplier,lead in (("A",2),("D",4),("E",8),("F",12)):
        eligible=book.executable(day,("B","coal"),quote(supplier,day,lead),due_only=False)
        selected.append(dict(supplier=supplier,lead=lead,eligible_need_days=[book.active[k].need_by_day for k,_ in eligible]))
    lots=[Supply(s,"B","coal",20,day+d,"ACCEPTED_PENDING",i) for i,(s,d) in enumerate((('A',2),('D',4),('E',8),('F',12)),1)]
    book.reconcile(day,lots)
    assert all(book.gap(k)==0 for k in book.active)
    multiple=dict(scope="public quote/allocation interface only, not four new physical suppliers",selected=selected,allocations=book.allocations)
    revision=ReleaseBook(); record=("B","coal",25,"PROJECTED",80,"OBSERVED")
    revision.revise(10,[record],10); lot=Supply("accepted","B","coal",80,20,"ACCEPTED_PENDING",1)
    revision.reconcile(10,[lot]); revision.revise(11,[("B","coal",25,"PROJECTED",100,"OBSERVED")],10); revision.reconcile(11,[lot])
    increase=revision.active[record[0]+":coal:25:PROJECTED"].record()
    assert increase["revision_delta"]==20 and revision.ceiling_room(("B","coal"),0)==20
    revision.revise(12,[("B","coal",25,"PROJECTED",50,"OBSERVED")],10); revision.reconcile(12,[lot])
    assert revision.excess(("B","coal"))==30 and lot.quantity==80
    graph=RecipeGraph([Recipe(f"P{i}",f"g{i}",1,((f"g{i-1}",2),)) for i in range(1,5)])
    requirements,edges=graph.explode("g4",3,50,{f"P{i}":1000 for i in range(1,5)},dict(P1=2,P2=3,P3=4,P4=1))
    procurement_leads=dict(g3=3,g2=5,g1=7,g0=11)
    releases=[dict(**asdict(r),release_by_day=r.need_by_day-procurement_leads[r.commodity]) for r in requirements]
    assert [r["release_by_day"] for r in releases]==[46,40,35,29]
    return dict(horizon_boundary=boundary,multiple_leads=multiple,
                rolling_revision=dict(increase=increase,decrease=revision.snapshot(),supply_quantity=lot.quantity,excess=30),
                five_stage_mixed_lead=dict(requirements=releases,edges_traversed=edges),
                branching_shared_sink_regression=old_probes())


def summarize(case,sim,rows):
    recent=rows[-200:]; release=sim.release
    return dict(case_id=case["case_id"],policy=case["execution_policy"],production_horizon=case["horizon"],days=len(rows),
        final_backlog=sim.backlog,backlog_peak=max(r["terminal_backlog"] for r in rows),machine_days=sum(r["terminal_backlog"] for r in rows),
        last200_delivery_mean=sum(r["terminal_delivery"] for r in recent)/len(recent),
        coal_ordered=sum(sim.totals[r]["ordered"] for r in sim.server_routes.values()),
        coal_cancelled=sum(sim.totals[r]["cancelled"] for r in sim.server_routes.values()),
        final_coal_position=sim.global_supply_position(),max_coal_position=max(r["global_supply_position"] for r in rows),
        final_coal_pending=sim.coal_pending,final_coal_transit=sim.coal_transit,
        final_steel_position=sim.inventory_position("B_C"),max_steel_position=max(r["B_C_inventory_position"] for r in rows),
        max_B_coal=max(r["B_coal_on_hand"] for r in rows),max_C_steel=max(r["C_steel_on_hand"] for r in rows),max_C_machine=max(r["C_machine_on_hand"] for r in rows),
        final_visibility=sim.visibility,max_visibility=max(r["supply_visibility_horizon"] for r in rows),
        unique_buckets=len(release.first_seen),revision_count=len(release.revisions),
        active_firm_peak=max(r["active_firm_buckets"] for r in rows),active_projected_peak=max(r["active_projected_buckets"] for r in rows),
        release_checks=release.release_checks,allocation_candidates=release.allocation_candidates,forward_events=len(release.forward_events),
        max_unallocated=max(r["unallocated_exposure"] for r in rows),max_coal_excess=max(r["coal_excess_exposure"] for r in rows),
        max_steel_excess=max(r["steel_excess_exposure"] for r in rows),stale_checks=sim.cancel_scan_visits,
        cancellation_requests=sum(r["state"]=="CANCEL_REQUESTED" for r in sim.cancel_history),
        confirmed_cancelled=sum(r["confirmed_cancel_qty"] for r in sim.cancel_history if r["state"]=="CANCEL_CONFIRMED"),
        replacement_quantity=sum(r["accepted"] for r in sim.release_requests if r["action"]=="CONFIRMED_REPLACEMENT"),
        long_E_ordered=sim.totals.get("E_B",{}).get("ordered",0),offers_evaluated=sim.offer_evaluations,
        max_quantity_residual=max(abs(r[g+"_residual"]) for r in rows for g in ("coal","steel","machine")),
        max_order_residual=max(abs(v) for v in sim.route_order_residuals.values()),
        clear_after80=next((r["day"] for i,r in enumerate(rows) if r["day"]>=80 and len(rows[i:i+20])==20 and all(x["terminal_backlog"]==0 for x in rows[i:i+20])),None))


def generate(output,execution,measure_memory=False):
    output=output.resolve()
    if output.exists() or output==ROOT or output.is_relative_to(ROOT/"economy_quantity_lab") or output.is_relative_to(ROOT/"docs"):
        raise ValueError("new output directory outside source/evidence required")
    output.mkdir(parents=True); summaries=[]; logs=[]
    for case in all_cases():
        if measure_memory: tracemalloc.start()
        started=time.perf_counter(); sim,rows=run_case(case); seconds=time.perf_counter()-started
        peak=tracemalloc.get_traced_memory()[1] if measure_memory else None
        if measure_memory: tracemalloc.stop()
        summaries.append(summarize(case,sim,rows)); dest=output/case["case_id"]
        write_json(dest/"config.json",case); write_csv(dest/"daily.csv",rows)
        write_csv(dest/"firm_plans.csv",sim.plans); write_csv(dest/"actual_deviations.csv",sim.plan_deviations)
        write_json(dest/"buckets.json",sim.release.execution_snapshots)
        write_json(dest/"supply_reconciliation.json",sim.release.reconciliation_by_day)
        write_json(dest/"quote_trace.json",sim.quote_trace)
        write_json(dest/"revisions.json",sim.release.revisions); write_json(dest/"release_checks.json",dict(sim.release.release_by_day))
        write_json(dest/"forward_reassignments.json",sim.release.forward_events); write_json(dest/"expired_firm.json",sim.release.expired)
        write_json(dest/"disposition.json",dict(events=sim.disposition_events,cancellation=sim.cancel_history,requests=sim.release_requests))
        write_json(dest/"requests.json",sim.requests); write_json(dest/"offers.json",sim.offers)
        write_csv(dest/"order_trace.csv",sim.commitment_events)
        write_json(dest/"search.json",dict(events=sim.knowledge.events,discoveries=sim.discoveries))
        logs.append(dict(case_id=case["case_id"],seconds=seconds,tracemalloc_peak_bytes=peak,scope="construction/simulation/planning/reconciliation/archives; excludes file export; not RSS"))
        print(case["case_id"],"backlog",sim.backlog,"cancelled",summaries[-1]["confirmed_cancelled"],"seconds",round(seconds,3),flush=True)
    probes=interface_probes(); partial=partial_probe()
    write_csv(output/"summary.csv",summaries); write_json(output/"interface_probes.json",probes)
    write_json(output/"partial_dispatch_probe.json",partial)
    checks=dict(accounts=all(s["max_quantity_residual"]==s["max_order_residual"]==0 for s in summaries),
                active_bucket_bounds=all(s["active_firm_peak"]<=2*s["production_horizon"] and s["active_projected_peak"]<=2*(s["max_visibility"]-s["production_horizon"]) for s in summaries),
                cases=len(summaries)==39,
                partial_cancel=partial["original_order"]["cancelled"]==50 and partial["original_order"]["delivered"]==30,
                confirmed_replacement=sum(r["accepted"] for r in partial["replacements"])==50,
                boundary_release=[r["released_bucket"]["requirement_class"] for r in probes["horizon_boundary"]]==["FIRM","PROJECTED","PROJECTED"],
                long_lead_release=all(s["long_E_ordered"]>0 for s in summaries if s["case_id"].startswith(("B_","C_")) and s["policy"]!="X0"))
    if not all(checks.values()): raise AssertionError(checks)
    write_json(output/"execution_gate.json",dict(EXECUTABLE_PLANNING_GATE="PASS",checks=checks,scope="paired with correctness entry point; expression and tested semantics, not economic validity"))
    sources=list(HERE.glob("*.py"))+[HERE/"inputs/ROUND5B_REQUEST.md",HERE.parent/"economy.py"]
    for folder in ("order_round3","supplier_round4a","multi_round4b","search_round4c","planning_round5"):
        sources+=list((HERE.parent/folder).glob("*.py"))
    write_json(output/"manifest.json",dict(base=BASE,tag=TAG,cases=39,case_days=23400,
        sources={str(p.relative_to(ROOT)).replace("\\","/"):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(sources))}))
    write_json(execution,dict(base=BASE,python=sys.version,case_count=39,case_days=23400,
        max_quantity_residual=max(s["max_quantity_residual"] for s in summaries),max_order_residual=max(s["max_order_residual"] for s in summaries),
        cases=logs,total_seconds=sum(l["seconds"] for l in logs)))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,required=True); parser.add_argument("--execution-log",type=Path,required=True)
    parser.add_argument("--measure-memory",action="store_true")
    args=parser.parse_args(); generate(args.output_dir,args.execution_log,args.measure_memory)
