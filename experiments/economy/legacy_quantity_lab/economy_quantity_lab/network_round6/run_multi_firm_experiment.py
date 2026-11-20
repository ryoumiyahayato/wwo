"""24 generic600-day networks, two legacy boundary controls and actual probes."""
import argparse
from collections import defaultdict
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import time
from network_simulation import NetworkSimulation,SingleChainCompatibility
from network_fixtures import make_network,compatibility_case,all_cases,BASE,TAG
from run_executable_planning_experiment import run_case as old_run
from run_supplier_search_experiment import write_json,write_csv

HERE=Path(__file__).resolve().parent;ROOT=HERE.parent.parent


def run_case(case):
    sim=NetworkSimulation(case)
    for _ in range(case['days']):sim.step()
    return sim


def intent(sim,buyer,seller,good,q,need_id=None):
    offer=sim.quote(buyer,good,seller)
    return dict(buyer_id=buyer,supplier_id=seller,commodity=good,requested_quantity=q,request_day=sim.day,
                procurement_round=0,quoted_quantity=offer.max_acceptable_quantity,expected_arrival_day=offer.expected_arrival_day,
                lines=[dict(need_id=need_id or f'{buyer}:{good}:PROBE',commodity=good,quantity=q,need_by_day=sim.day+4)])


def shared_probe(good='coal',policy='C0',partial=False):
    case=make_network(policy=policy,days=12)
    for firm in case['firms']:
        firm['capacities']={g:0 for g in firm['capacities']};firm['input_targets']={g:0 for g in firm['input_targets']}
    for stock in case['inventory'].values():
        for g in stock:stock[g]=0
    for sink in case['sinks']:sink['demand_intervals']=[[1,10000,0]]
    seller='A' if good=='coal' else 'B1';buyers=('B1','B2') if good=='coal' else ('C1','C2')
    case['inventory'][seller][good]=100
    for r in case['routes']:
        if r['seller_id']==seller and r['commodity']==good:
            route=f'{seller}>{r["buyer_id"]}:{good}'
            case['route_events'][route]=[dict(first_day=1,last_day=3,capacity=0)]
            if partial and r['buyer_id']==buyers[0]:case['route_events'][route]=[dict(first_day=1,last_day=2,capacity=0),dict(first_day=3,last_day=3,capacity=30)]
    class Probe(NetworkSimulation):
        def confirm_cancellations(self):
            super().confirm_cancellations()
            if self.day==4:
                self.confirm_snapshot=dict(entries=deepcopy(self.stock_commitments.entries),free=self.stock_commitments.uncommitted(seller,good,self.stock[seller][good]))
        def procurement_boundary(self):
            super().procurement_boundary()
            if self.day==3:self.request_cancellation(self.first_order,self.orders[self.first_order].pending_dispatch if partial else 20)
            if self.day==4:
                confirmed=next(r['confirmed_cancel_qty'] for r in self.cancel_history if r['state']=='CANCEL_CONFIRMED')
                self.replacement=self.admit_round([intent(self,buyers[0],seller,good,confirmed,'CONFIRMED_PROBE_REPLACEMENT')]) if confirmed else []
    sim=Probe(case);initial=[intent(sim,b,seller,good,80) for b in buyers]
    assert all(r['quoted_quantity']==100 for r in initial)
    responses=sim.admit_round(initial);sim.first_order=responses[0]['order_id'];other=responses[1]['order_id']
    initial_entries=deepcopy(sim.stock_commitments.entries)
    for _ in range(12):sim.step()
    snapshot=sim.confirm_snapshot
    assert snapshot['entries'][other][2]==initial_entries[other][2]
    original=sim.orders[sim.first_order]
    confirmed=next(r for r in sim.cancel_history if r['state']=='CANCEL_CONFIRMED')
    assert snapshot['free']==confirmed['confirmed_cancel_qty']
    assert sum(r['accepted_quantity'] for r in sim.replacement)==confirmed['confirmed_cancel_qty']
    assert not sim.cancelled_by_order_id.get(other,0)
    return dict(scope='12 actual common-world steps, original FIFO/receive and confirmed cancellation; no fabricated shipments',commodity=good,policy=policy,
                simultaneous_requests=initial,responses=responses,initial_stock_commitments=initial_entries,confirmation=snapshot,
                cancellations=sim.cancel_history,replacement=sim.replacement,first_order=dict(ordered=original.quantity,pending=original.pending_dispatch,
                    transit=original.in_transit,delivered=original.delivered,cancelled=original.cancelled),
                other_order=dict(ordered=sim.orders[other].quantity,delivered=sim.orders[other].delivered,cancelled=sim.orders[other].cancelled),
                order_events=sim.commitment_events,rows=sim.rows,flow_residual=max(abs(r['residual']) for r in sim.flow_rows),
                order_residual=max(map(abs,sim.route_order_residuals.values())))


def structural_probes():
    case=make_network(policy='C1',days=100)
    normal=run_case(case);reverse=run_case(make_network(policy='C1',days=100,reverse=True));sleep=run_case(make_network(policy='C1',days=100,sleeping=100))
    assert normal.rows==reverse.rows==sleep.rows
    assert normal.requests==reverse.requests==sleep.requests
    assert normal.quotes==reverse.quotes==sleep.quotes
    assert normal.metrics['offer_queries']==sleep.metrics['offer_queries']
    return dict(scope='actual100-day shared network worlds; reversal and100 sleeping firms, not matching-only mocks',days=100,
                outcome_equal=True,requests_equal=True,quotes_equal=True,
                normal_metrics=dict(normal.metrics),sleeping_metrics=dict(sleep.metrics),normal_firms=len(normal.firms),sleeping_firms=len(sleep.firms))


def summarize(case,sim):
    by_buyer=defaultdict(int);by_sink={k:s['backlog'] for k,s in sim.sinks.items()}
    coal_buyer=defaultdict(int);steel_buyer=defaultdict(int)
    for r in sim.requests:
        (coal_buyer if r['commodity']=='coal' else steel_buyer)[r['buyer_id']]+=r['accepted_quantity']
    degree=sum(len(k) for n in sim.firms.values() for k in n.knowledge.values())
    raw_exposure={fid:sim.firms[fid].release.exposure((fid,'coal')) for fid in sim.active_firms if 'coal' in sim.firms[fid].input_targets}
    recent=sim.rows[-200:]
    return dict(case_id=case['case_id'],policy=case['contention'],scale=case['scale'],days=sim.day,world_firms=len(sim.firms),
        active_firms=len(sim.active_firms),producers=sum(bool(n.recipes) for n in sim.firms.values()),buyers=sum(bool(n.knowledge) for n in sim.firms.values()),
        sellers=len({r.seller_id for r in sim.routes.values()}),routes=len(sim.routes),known_edges=degree,
        final_backlog=sim.backlog,backlog_by_sink=json.dumps(by_sink,sort_keys=True),total_delivery=sim.cumulative['terminal_delivered'],
        backlog_peak=max(r['terminal_backlog'] for r in sim.rows),machine_days=sum(r['terminal_backlog'] for r in sim.rows),
        last200_delivery_mean=sum(r['terminal_delivery'] for r in recent)/len(recent),
        coal_accepted_by_buyer=json.dumps(dict(coal_buyer),sort_keys=True),steel_accepted_by_buyer=json.dumps(dict(steel_buyer),sort_keys=True),
        coal_produced=sim.cumulative['coal_mined'],steel_produced=sim.cumulative['steel_produced'],machine_produced=sim.cumulative['machine_produced'],
        gross_requests=sum(r['requested_quantity'] for r in sim.requests),accepted=sum(r['accepted_quantity'] for r in sim.requests),rejected=sum(r['rejected_quantity'] for r in sim.requests),
        scarcity_rounds=sum(r['scarcity'] for r in sim.round_records),
        max_coal_buyer_share=max(coal_buyer.values(),default=0)/sum(coal_buyer.values()) if sum(coal_buyer.values()) else 0,
        max_steel_buyer_share=max(steel_buyer.values(),default=0)/sum(steel_buyer.values()) if sum(steel_buyer.values()) else 0,
        final_raw_exposure=json.dumps(raw_exposure,sort_keys=True),
        max_quantity_residual=max(abs(r[g+'_residual']) for r in sim.rows for g in ('coal','steel','machine')),
        max_firm_residual=max(abs(r['residual']) for r in sim.flow_rows),max_order_residual=max(map(abs,sim.route_order_residuals.values())),
        offer_queries=sim.metrics['offer_queries'],known_candidate_visits=sim.metrics['known_candidate_visits'],
        planning_firm_visits=sim.metrics['planning_firm_visits'],allocation_candidates=sum(n.release.allocation_candidates for n in sim.firms.values()),
        live_supply_visits=sim.metrics['live_supply_visits'],firm_settlement_visits=sim.metrics['firm_settlement_visits'],
        route_settlement_visits=sim.metrics['route_settlement_visits'],world_ledger_firm_visits=sim.metrics['world_ledger_firm_visits'],
        procurement_rounds=sim.metrics['procurement_rounds'],max_rounds=sim.metrics['max_rounds'],contention_allocations=sim.metrics['contention_allocations'],
        active_orders_peak=sim.metrics['active_order_peak'],active_shipments_peak=sim.metrics['active_shipment_peak'],
        archived_revisions=sum(len(n.release.revisions) for n in sim.firms.values()),
        backlog_clear20_after80=next((r['day'] for i,r in enumerate(sim.rows) if r['day']>=80 and len(sim.rows[i:i+20])==20 and all(x['terminal_backlog']==0 for x in sim.rows[i:i+20])),None))


def generate(output,execution):
    output=output.resolve()
    if output.exists() or output.is_relative_to(ROOT/'economy_quantity_lab') or output.is_relative_to(ROOT/'docs') or output==ROOT:raise ValueError('new directory outside source/evidence required')
    output.mkdir(parents=True);summaries=[];logs=[]
    # Stage25 gate is executed before the larger network matrix.
    for policy in ('X0','X1'):
        case=compatibility_case(policy);sim=SingleChainCompatibility(case);oracle,oracle_rows=old_run(case)
        for _ in range(600):
            sim.step();sim.allocations_by_day[sim.day]=list(sim.coverage.allocations.values())
            sim.observe_search();sim.observe_planning();sim.observe_release()
        assert sim.rows==oracle.rows and sim.requests==oracle.requests and sim.events==oracle.events
        dest=output/case['case_id'];write_json(dest/'config.json',case);write_csv(dest/'daily.csv',sim.rows)
        write_json(dest/'oracle_equivalence.json',dict(policy=policy,days=600,physical_equal=True,requests_equal=True,events_equal=True,
            boundary='Explicit old S0 steel and old planning boundary; FirmNode inventories are identity views, no extra world. Formal networks remove these exceptions.'))
    for case in all_cases():
        started=time.perf_counter();sim=run_case(case);seconds=time.perf_counter()-started
        summary=summarize(case,sim);summaries.append(summary);dest=output/case['case_id'];export_started=time.perf_counter()
        write_json(dest/'config.json',case);write_csv(dest/'daily.csv',sim.rows);write_csv(dest/'firm_output.csv',sim.firm_rows)
        write_csv(dest/'firm_flows.csv',sim.flow_rows);write_csv(dest/'sinks.csv',sim.sink_rows);write_csv(dest/'routes.csv',sim.route_rows)
        write_csv(dest/'plans.csv',sim.plans);write_csv(dest/'buckets.csv',sim.allocation_rows);write_csv(dest/'customer_observations.csv',sim.customer_rows)
        write_json(dest/'requests.json',sim.requests);write_json(dest/'quotes.json',sim.quotes);write_json(dest/'contention.json',sim.round_records)
        write_csv(dest/'order_trace.csv',sim.commitment_events);write_csv(dest/'performance.csv',sim.metric_rows)
        write_json(dest/'final_exposure.json',{fid:dict(inventories=node.inventories,allocations=node.release.allocations,
            unallocated=node.release.unallocated,procurement=node.procurement) for fid,node in sorted(sim.firms.items())})
        logs.append(dict(case_id=case['case_id'],seconds=seconds,phase_seconds=dict(sim.timing),export_seconds=time.perf_counter()-export_started,
                         serialized_output_bytes=sum(f.stat().st_size for f in dest.iterdir()),
                         scope='construction/world/planning/settlement/observation archives, export separately; not SLA'))
        print(case['case_id'],'backlog',sim.backlog,'seconds',round(seconds,3),flush=True)
        del sim
    write_csv(output/'summary.csv',summaries)
    probes={f'{good}_{policy}':shared_probe(good,policy) for good in ('coal','steel') for policy in ('C0','C1')}
    probes['partial_coal_C0']=shared_probe('coal','C0',True);probes['partial_steel_C1']=shared_probe('steel','C1',True)
    write_json(output/'shared_commitment_probes.json',probes);write_json(output/'structural_probes.json',structural_probes())
    checks=dict(accounts=all(r['max_quantity_residual']==r['max_firm_residual']==r['max_order_residual']==0 for r in summaries),
                S5_600=sum(r['scale']=='S5' and r['days']==600 for r in summaries)==2,S10_600=sum(r['scale']=='S10' and r['days']==600 for r in summaries)==2,
                bounded_known_degree=all(r['max_rounds']<=2 for r in summaries),cases=len(summaries)==24,
                shared_probe=all(r['flow_residual']==r['order_residual']==0 for r in probes.values()))
    assert all(checks.values()),checks
    write_json(output/'network_gate.json',dict(NETWORK_EXTENSIBILITY_GATE='PASS',checks=checks,scope='requires correctness entry point too; tested structural extension, not economic realism or formal adoption'))
    sources=list(HERE.glob('*.py'))+[HERE/'inputs/ROUND6_REQUEST.md',HERE.parent/'economy.py']
    for folder in ('order_round3','supplier_round4a','multi_round4b','search_round4c','planning_round5','release_round5b'):sources+=list((HERE.parent/folder).glob('*.py'))
    write_json(output/'manifest.json',dict(base=BASE,tag=TAG,network_cases=24,network_days=14400,compatibility_cases=2,
        sources={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(sources))}))
    write_json(execution,dict(python=sys.version,base=BASE,network_cases=24,network_days=14400,compatibility_cases=2,compatibility_days=1200,
        max_quantity_residual=max(r['max_quantity_residual'] for r in summaries),max_firm_residual=max(r['max_firm_residual'] for r in summaries),
        max_order_residual=max(r['max_order_residual'] for r in summaries),cases=logs,total_seconds=sum(r['seconds'] for r in logs)))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-dir',type=Path,required=True);p.add_argument('--execution-log',type=Path,required=True)
    args=p.parse_args();generate(args.output_dir,args.execution_log)
