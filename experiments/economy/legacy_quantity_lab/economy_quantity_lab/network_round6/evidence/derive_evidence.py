"""Read frozen output archives; no model decisions or quantity mutations.

Usage: python .../derive_evidence.py --results .local/round6-release
"""
import argparse
from collections import defaultdict
import csv
import hashlib
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def rows(path):
    with path.open(encoding='utf-8', newline='') as stream:
        yield from csv.DictReader(stream)


def save(name, value):
    (HERE / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')


def derive(results):
    analysis = {}
    edges = []
    for summary in rows(results / 'summary.csv'):
        case_id = summary['case_id']; directory = results / case_id
        daily = list(rows(directory / 'daily.csv'))
        route_by_day = defaultdict(list)
        for row in rows(directory / 'routes.csv'):
            route_by_day[int(row['day'])].append(row)
        requests = read_json(directory / 'requests.json')
        request_by_day = defaultdict(list)
        buyer_requests = defaultdict(lambda: dict(requested=0, accepted=0, rejected=0, attempts=0))
        for request in requests:
            request_by_day[request['request_day']].append(request)
            key = request['buyer_id'] + ':' + request['commodity']
            for field in ('requested', 'accepted', 'rejected'):
                buyer_requests[key][field] += request[field + '_quantity']
            buyer_requests[key]['attempts'] += 1
        exposure_peak = defaultdict(int); stock_peak = defaultdict(int)
        visible_peak = defaultdict(int); current_visible = defaultdict(int)
        for row in rows(directory / 'buckets.csv'):
            key = (int(row['day']), row['firm_id'], row['commodity'])
            current_visible[key] += int(row['quantity'])
        for (_, firm, good), quantity in current_visible.items():
            visible_peak[firm + ':' + good] = max(visible_peak[firm + ':' + good], quantity)
        del current_visible
        config = read_json(directory / 'config.json')
        input_targets = {firm['firm_id']: firm['input_targets'] for firm in config['firms'] if firm['active']}
        continuity = defaultdict(lambda: dict(output=0, positive_days=0, zero_days_after100=0, last200_output=0))
        for row in rows(directory / 'firm_output.csv'):
            quantity = int(row['actual_output']); day = int(row['day'])
            value = continuity[row['firm_id'] + ':' + row['commodity']]
            value['output'] += quantity; value['positive_days'] += quantity > 0
            value['zero_days_after100'] += day >= 100 and quantity == 0
            if day > 400: value['last200_output'] += quantity
        for row in daily:
            day = int(row['day']); routes = route_by_day[day]; frame = request_by_day[day]
            edge = lambda r: (r['supplier_id'], r['buyer_id'], r['commodity'])
            edges.append(dict(case_id=case_id, day=day, known_edges=int(row['known_edges']),
                request_edges=len({edge(r) for r in frame if r['requested_quantity'] > 0}),
                accepted_edges=len({edge(r) for r in frame if r['accepted_quantity'] > 0}),
                shipment_edges=sum(int(r['dispatched']) > 0 for r in routes),
                active_edges=sum(int(r['pending']) + int(r['in_transit']) > 0 for r in routes)))
            for firm, goods in input_targets.items():
                for good in goods:
                    stock = int(row[firm + '_' + good + '_stock'])
                    quantity = stock + sum(int(r['pending']) + int(r['in_transit']) for r in routes if r['buyer'] == firm and r['commodity'] == good)
                    key = firm + ':' + good
                    stock_peak[key] = max(stock_peak[key], stock)
                    exposure_peak[key] = max(exposure_peak[key], quantity)
        windows = []
        for day in (49, 50, 79, 80, 99, 100, 101, 110, 200, 400, 600):
            frame = daily[day - 1]
            windows.append(dict(day=day, backlog=int(frame['terminal_backlog']), delivery=int(frame['terminal_delivery']),
                coal_exposure={firm: int(frame[firm + '_coal_stock']) + sum(int(r['pending']) + int(r['in_transit']) for r in route_by_day[day] if r['buyer'] == firm and r['commodity'] == 'coal') for firm, goods in input_targets.items() if 'coal' in goods},
                routes=route_by_day[day], requests=request_by_day[day]))
        clear = lambda field, value: next((int(r['day']) for i,r in enumerate(daily) if int(r['day']) >= 80 and len(daily[i:i+20]) == 20 and all(int(x[field]) >= value for x in daily[i:i+20])), None)
        analysis[case_id] = dict(summary=summary, buyer_requests=dict(buyer_requests), firm_continuity=dict(continuity),
            peak_real_input_exposure=dict(exposure_peak), peak_input_stock=dict(stock_peak), peak_visible_requirements=dict(visible_peak),
            delivery10_20day_start_after80=clear('terminal_delivery',10), selected_boundaries=windows,
            final_exposure=read_json(directory / 'final_exposure.json'),
            last_performance=list(rows(directory / 'performance.csv'))[-1])
    save('network_analysis.json', dict(scope='Postprocessing end-of-day facts; active edge means accepted pending or in-transit, shipment edge means positive dispatch today. Gross request quantities count retries and are not new final consumption. Peak exposure=owned input+accepted pending+transit; no timing claims.', cases=analysis))
    with (HERE / 'edge_work.csv').open('w',encoding='utf-8',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(edges[0]),lineterminator='\n');writer.writeheader();writer.writerows(edges)
    files = {p.relative_to(results).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(results.rglob('*')) if p.is_file()}
    assert len(files) == 371
    save('hash_manifest.json', dict(algorithm='sha256', files=files, policy='Exact UTF-8/LF output bytes AND file set; timing logs outside comparison. Historical output policies unchanged.'))
    for name in ('summary.csv','manifest.json','network_gate.json','shared_commitment_probes.json','structural_probes.json'):
        (HERE / name).write_bytes((results / name).read_bytes())


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--results',type=Path,required=True)
    derive(parser.parse_args().results.resolve())
