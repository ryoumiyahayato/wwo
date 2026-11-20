# Dated-request counterexample reproduction

This is an additional observational prefix, not a substituted long experiment.
Actual1000days, initialized with the official normal N3 nonbinding3600-day case.
Formal3600-day runs separately completed twice. No candidate revision.
Run from `/workspace/wwo-economy-lab`, choose a new output directory.

```python
from pathlib import Path
import sys, json, hashlib
sys.path.insert(0, str(Path('economy_quantity_lab/goal_cycle01').resolve()))
from cycle_fixtures import make_case
from network_simulation import NetworkSimulation
from observation import StreamObserver, canonical, dump
from offline_audit import audit

case = make_case('normal', 'N3', 3600)
sim = NetworkSimulation(case)
directory = Path('.local/goal-cycle01/dated-prefix-new')
observer = StreamObserver(sim, directory, 'compact')
selected = []
for _ in range(1000):
    sim.step()
    if 590 <= sim.day <= 630 or 990 <= sim.day <= 1000:
        for r in sim.requests.tail:
            if r['buyer_id'] in ('B1', 'B2') and r['commodity'] == 'coal':
                selected.append(dict(day=sim.day, buyer=r['buyer_id'],
                    seller=r['supplier_id'], requested=r['requested_quantity'],
                    accepted=r['accepted_quantity'], price=r['posted_price'],
                    eta=r['expected_arrival_day'], lines=r['lines'],
                    rejections=r['rejections'], known_prices={k:
                        sim.economics.prices[(k, 'coal')] for k in
                        sorted(sim.firms[r['buyer_id']].knowledge['coal'])}))
    observer.finish_day()
summary = observer.close()
assert audit(directory)['status'] == 'PASS'
dump(directory/'dated_requests.json', selected)
# Use the official first replay in the declared saved workspace:
source = Path('.local/goal-cycle01/final-verification-sze0jumd/replay_a') / case['case_id'] / 'daily.jsonl'
prefix = hashlib.sha256()
for line in source.read_text().splitlines():
    row = json.loads(line)
    if row['day'] > 1000:
        break
    for key in ('production', 'rejections', 'bound_hits'):
        row.pop(key)
    prefix.update((canonical(row)+'\n').encode())
assert prefix.hexdigest() == summary['economic_sha256']
```

The actual156 selected requests and matching hash/audit result are preserved in
`dated_requests.json` and `dated_request_diagnostic.json` next to this document.
At610, A49 releases need614 while D360 releases need616; this is not one same-date
offer comparison. The unchanged release rule can therefore sustain local pressure
and higher D prices even while cheaper A exists and service remains adequate.
