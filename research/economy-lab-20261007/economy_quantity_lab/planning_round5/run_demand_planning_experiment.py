"""52 deterministic 600-day planning cases; probes and immutable output manifests."""
import argparse
import csv
import hashlib
import json
from dataclasses import asdict
from pathlib import Path
import sys
import time
import tracemalloc

from planning_simulation import PlanningSimulation
from demand_planning import (Recipe, RecipeGraph, Demand, MaterialRequirement, Supply,
                             PlanningAllocations, aggregate_demand)
from run_supplier_search_experiment import make_case as search_case, write_csv, write_json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent.parent
BASE="366fe77704ee3d4ec9088ba1c544c46096289e40"
TAG="economy-lab-v0.4c-supplier-search"


def make_case(treatment="normal",planner="P0",horizon=10,days=600):
    case=search_case("wide" if treatment=="wide" else "normal","Q1" if treatment=="wide" else "Q0",10)
    case.update(case_id=f"{treatment}_{planner}_H{horizon}",treatment=treatment,planner=planner,
                horizon=horizon,days=days,demand_intervals=[[1,10000,10]])
    config=case["config"]
    if treatment=="step_up": case["demand_intervals"]=[[1,99,10],[100,10000,15]]
    elif treatment=="step_down": case["demand_intervals"]=[[1,99,15],[100,10000,5]]
    elif treatment=="spike": case["demand_intervals"]=[[1,99,10],[100,119,15],[120,10000,10]]
    elif treatment=="long_lead":
        config["routes"]["A_B"]["lead_time"]=8; config["routes"]["D_B"].update(capacity=0,lead_time=8)
    elif treatment=="mixed_lead":
        config["routes"]["A_B"].update(capacity=30,lead_time=2)
        config["routes"]["D_B"].update(capacity=100,lead_time=8)
        config["production"]["D"]["capacity"]=100
    elif treatment=="insufficient":
        config["routes"]["A_B"]["capacity"]=30; config["routes"]["D_B"]["capacity"]=30
        for supplier in config["available_supplier_ids"]:
            if supplier not in ("A","D"):
                config["routes"][supplier+"_B"]["capacity"]=0
    elif treatment in ("factory_cap","steel_cap"):
        # Explicit abundant finite physical pools, replenished by real extraction.
        for s in ("A","D"):
            config["initial_inventory"][s]["coal"]=100000
            config["production"][s].update(capacity=200,coal_target=100000)
            config["routes"][s+"_B"]["capacity"]=200
        config["production"]["C" if treatment=="factory_cap" else "B"]["capacity"]=8 if treatment=="factory_cap" else 30
    elif treatment=="recovery":
        config["routes"]["D_B"]["lead_time"]=2
        config["production"]["D"]["capacity"]=100
        config["routes"]["D_B"]["capacity"]=100
        config["scenarios"]={"experiment":{r:[dict(first_day=50,last_day=79,capacity=0)] for r in ("A_B","D_B")}}
    return case


def all_cases():
    treatments=("normal","step_up","step_down","spike","wide","long_lead","mixed_lead", "insufficient","factory_cap","steel_cap","recovery")
    cases=[make_case(t,p) for t in treatments for p in ("P0","P1","P2","P3")]
    cases += [make_case(t,p,h) for t in ("normal","wide") for p in ("P2","P3") for h in (5,20)]
    return cases


def run_case(case,observe=True):
    sim=PlanningSimulation(case); rows=[]
    for _ in range(case["days"]):
        row=sim.step()
        sim.allocations_by_day[sim.day]=list(sim.coverage.allocations.values())
        if observe: rows.append({**row,**sim.observe_search(),**sim.observe_planning()})
    for order in sim.orders.values(): order.check()
    return sim,rows


def probes():
    recipes=[Recipe(f"P{i}",f"g{i}",1,((f"g{i-1}",2),)) for i in range(1,5)]
    graph=RecipeGraph(recipes)
    records,edges=graph.explode("g4",3,20,{f"P{i}":1000 for i in range(1,5)}, {f"P{i}":1 for i in range(1,5)})
    assert [r.required_qty for r in records]==[6,12,24,48]
    branch=RecipeGraph([Recipe("factory","final",1,(("input_A",2),("input_B",3)))])
    branching,e=branch.explode("final",4,5,{"factory":100})
    assert {r.commodity:r.required_qty for r in branching}=={"input_A":8,"input_B":12}
    shared=RecipeGraph([Recipe("X","x",1,(("raw",2),)),Recipe("Y","y",1,(("raw",3),))])
    rx,_=shared.explode("x",4,5,{"X":10},path="sinkX"); ry,_=shared.explode("y",4,5,{"Y":10},path="sinkY")
    # Shared-input probe puts both producer requirements in one declared pool.
    requirements=[MaterialRequirement(r.requirement_id,"shared_pool",r.commodity,r.required_qty,r.need_by_day,r.source_plan_id) for r in rx+ry]
    book=PlanningAllocations(); book.reconcile(1,requirements,[Supply("pool","shared_pool","raw",10,1,"ON_HAND")])
    assert sum(a["quantity"] for a in book.allocations.values())==10
    records2=[Demand("sink1","final",1,7),Demand("sink2","final",1,9)]
    total=aggregate_demand(records2,"final")
    sink_reqs,_=branch.explode("final",total,5,{"factory":100})
    sink_book=PlanningAllocations(); sink_book.reconcile(1,sink_reqs,[Supply("a","factory","input_A",20,1,"ON_HAND"),Supply("b","factory","input_B",40,1,"ON_HAND")])
    return dict(five_stage=dict(commodities=5,production_edges=4,requirements=[asdict(r) for r in records],edges_traversed=edges),
                branching=dict(requirements=[asdict(r) for r in branching],edges_traversed=e),
                shared_input=dict(requirements=book.snapshot(),allocated=sum(a["quantity"] for a in book.allocations.values()),stock=10),
                multiple_sinks=dict(demands=[asdict(r) for r in records2],aggregate=total,requirements=sink_book.snapshot()))


def summarize(case,sim,rows):
    recent=rows[-200:]
    due=[d for d in sim.plan_deviations if d["production_day"]==d["day"]]
    return dict(case_id=case["case_id"],planner=case["planner"],horizon=case["horizon"],days=len(rows),
                final_backlog=sim.backlog,backlog_peak=max(r["terminal_backlog"] for r in rows),
                machine_days=sum(r["terminal_backlog"] for r in rows),terminal_delivery=sim.cumulative["terminal_delivered"],
                last200_delivery_mean=sum(r["terminal_delivery"] for r in recent)/len(recent),
                last200_coal_need_zero_backlog_days=sum(r["B_procurement_need_total"]==0 and r["terminal_backlog"]>0 for r in recent),
                cumulative_coal_ordered=sum(sim.totals[r]["ordered"] for r in sim.server_routes.values()),
                cumulative_coal_arrivals=sum(sim.totals[r]["delivered"] for r in sim.server_routes.values()),
                final_coal_position=sim.global_supply_position(),max_coal_position=max(r["global_supply_position"] for r in rows),
                final_B_coal=sim.stock["B"]["coal"],max_B_coal=max(r["B_coal_on_hand"] for r in rows),
                final_C_steel=sim.stock["C"]["steel"],max_C_steel=max(r["C_steel_on_hand"] for r in rows),
                final_C_machine=sim.stock["C"]["machine"],max_C_machine=max(r["C_machine_on_hand"] for r in rows),
                planned_due_steel=sum(d["planned_output"] for d in due if d["producer_id"]=="B"),
                actual_due_steel=sum(d["actual_output"] for d in due if d["producer_id"]=="B"),
                planned_due_machine=sum(d["planned_output"] for d in due if d["producer_id"]=="C"),
                actual_due_machine=sum(d["actual_output"] for d in due if d["producer_id"]=="C"),
                input_shortage_days=sum(d["reason"]=="INPUT_SHORTAGE" for d in due),
                capacity_limit_records=sum(d["reason"]=="CAPACITY_LIMIT" for d in due),
                expired_unfulfilled=sum(r["expired_unfulfilled"] for r in sim.coverage.history),
                plan_records=len(sim.plans),requirement_records=sum(len(v) for v in sim.requirements_by_day.values()),
                propagated_plan_records=sum(p["producer_id"] in ("B","C") for p in sim.plans),
                max_active_requirements=max(r["active_requirements"] for r in rows),max_allocations=max(r["requirement_allocations"] for r in rows),
                edge_visits=sim.edge_visits,allocation_visits=sim.coverage.visits,supply_visits=sim.supply_visits,
                procurement_requests=len(sim.requests),max_active_demand_records=max(r["active_demand_records"] for r in rows),
                max_quantity_residual=max(abs(r[g+"_residual"]) for r in rows for g in ("coal","steel","machine")),
                max_order_residual=max(abs(v) for v in sim.route_order_residuals.values()),
                first_backlog_clear_after80=next((r["day"] for i,r in enumerate(rows) if r["day"]>=80 and len(rows[i:i+20])==20 and all(x["terminal_backlog"]==0 for x in rows[i:i+20])),None))


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
        summary=summarize(case,sim,rows); summaries.append(summary)
        dest=output/case["case_id"]
        write_json(dest/"config.json",case); write_csv(dest/"daily.csv",rows)
        write_csv(dest/"plans.csv",sim.plans); write_csv(dest/"deviations.csv",sim.plan_deviations)
        write_csv(dest/"demand.csv",sim.demands)
        write_json(dest/"requirements.json",sim.requirements_by_day)
        write_json(dest/"settled_requirements.json",sim.coverage.history)
        write_json(dest/"coverage_events.json",dict(sim.coverage.events_by_day))
        write_json(dest/"final_allocations.json",list(sim.coverage.allocations.values()))
        write_json(dest/"allocations_by_day.json",sim.allocations_by_day)
        write_json(dest/"purchase_links.json",dict(sim.purchase_links))
        write_json(dest/"requests.json",sim.requests); write_json(dest/"offers.json",sim.offers)
        write_csv(dest/"order_trace.csv",sim.commitment_events)
        write_json(dest/"search.json",dict(events=sim.knowledge.events,discoveries=sim.discoveries))
        logs.append(dict(case_id=case["case_id"],seconds=seconds,tracemalloc_peak_bytes=peak,
                         scope="construction/simulation/planning/observation/archive; excludes file export; not RSS"))
        print(case["case_id"],"backlog",summary["final_backlog"],"seconds",round(seconds,3),flush=True)
    write_csv(output/"summary.csv",summaries); write_json(output/"probes.json",probes())
    checks=dict(accounts=all(s["max_quantity_residual"]==s["max_order_residual"]==0 for s in summaries),
                bounded_active_requirements=all(s["max_active_requirements"]<=2*s["horizon"] for s in summaries),
                all_cases=len(summaries)==52,
                probes=True)
    if not all(checks.values()): raise AssertionError(f"planning experiment gate failed: {checks}")
    write_json(output/"planning_gate.json",dict(PLANNING_EXTENSIBILITY_GATE="PASS",checks=checks,
               scope="full PASS additionally requires correctness test entry point; performance is not economic validation"))
    sources=list(HERE.glob("*.py"))+[HERE/"inputs/ROUND5_REQUEST.md"]
    sources += [ROOT/"economy_quantity_lab/economy.py"]
    for directory in ("order_round3","supplier_round4a","multi_round4b","search_round4c"):
        sources += list((HERE.parent/directory).glob("*.py"))
    write_json(output/"manifest.json",dict(base=BASE,tag=TAG,cases=52,days=31200,
        sources={str(p.relative_to(ROOT)).replace("\\","/"):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(sources))}))
    write_json(execution,dict(base=BASE,python=sys.version,case_count=len(summaries),simulated_case_days=sum(s["days"] for s in summaries),
        max_quantity_residual=max(s["max_quantity_residual"] for s in summaries),max_order_residual=max(s["max_order_residual"] for s in summaries),
        cases=logs,total_seconds=sum(r["seconds"] for r in logs)))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,required=True); parser.add_argument("--execution-log",type=Path,required=True)
    parser.add_argument("--measure-memory",action="store_true")
    args=parser.parse_args(); generate(args.output_dir,args.execution_log,args.measure_memory)
