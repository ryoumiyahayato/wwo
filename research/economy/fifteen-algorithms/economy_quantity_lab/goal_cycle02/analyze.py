"""Offline pair analysis: observed shadow versus independently executed outcomes."""
from pathlib import Path
from collections import defaultdict
import json,argparse,hashlib
from causal_audit import records

def first_difference(a,b):
    for day in sorted(set(a)|set(b)):
        if a.get(day)!=b.get(day):return day
    return None

def observed(path):
    p=Path(path);orders={};decision=defaultdict(list);accepted=defaultdict(list);shipped=defaultdict(list);produced=defaultdict(list);terminal=defaultdict(list);arrivals=defaultdict(lambda:defaultdict(int));arrive_day=defaultdict(list);cargo={};updates=[];day_links={}
    for line in records(p/'causal.jsonl'):
        r=json.loads(line);day=r['day']
        if r['event']=='decision' and r['phase']=='MATCHING':
            intent=r['intent'];chosen=next(o for o in r['buyer_visible_information']['offers'] if o['supplier_id']==r['selected_supplier']);visible=r['buyer_visible_information']
            decision[day].append((r['buyer'],r['commodity'],r['round'],r['selected_supplier'],None if not intent else ([(l['need_id'],l['need_by_day'],l['quantity']) for l in intent['lines']],chosen['posted_price']<=visible['max_unit_price'],visible['available_cash']>=chosen['posted_price'])))
        if r['event']=='request' and r['request']['order_id']:
            q=r['request'];oid=q['order_id'];orders[oid]=dict(buyer=q['buyer_id'],seller=q['supplier_id'],good=q['commodity'],lines=[[l['need_id'],l['need_by_day'],q['accepted_lines'].get(l['need_id'],0)] for l in q['lines']]);accepted[day].append((q['buyer_id'],q['supplier_id'],q['commodity'],q['accepted_quantity'],[(l['need_id'],l['need_by_day'],q['accepted_lines'].get(l['need_id'],0)) for l in q['lines']]))
        if r['event']=='price_update':updates.append(r)
        if r['event']=='day_link':day_links[day]=r
    for line in records(p/'events.jsonl'):
        r=json.loads(line);day=r['day'];event=r['event'];q=r['quantity']
        if event=='dispatched':
            o=orders[r['order_id']];left=q;parts=[]
            for l in o['lines']:
                take=min(left,l[2]);l[2]-=take;left-=take
                if take:parts.append((l[0],l[1],take))
            assert left==0,'shipment exceeds accepted dated lines'
            cargo[r['shipment_id']]=dict(order=r['order_id'],parts=parts)
            shipped[day].append((o['buyer'],o['seller'],o['good'],q,parts))
        elif event=='arrived':
            c=cargo[r['shipment_id']];o=orders[r['order_id']]
            for need,date,take in c['parts']:arrivals[(day,o['buyer'],o['good'],need,date)][o['seller']]+=take
            arrive_day[day].append((o['buyer'],o['seller'],o['good'],q,c['parts']))
        elif event=='produced':produced[day].append((r['firm'],r['commodity'],q))
        elif event=='terminal':terminal[day].append((r['sink_id'],q))
    # All lists preserve real canonical execution ordering, independent of IDs.
    return dict(decision=dict(decision),accepted=dict(accepted),shipment=dict(shipped),arrival=dict(arrive_day),production=dict(produced),terminal=dict(terminal),arrivals=arrivals,updates=updates,day_links=day_links)

def pair(a,b,x=None,y=None):
    x=observed(a) if x is None else x;y=observed(b) if y is None else y;sa=json.loads((Path(a)/'summary.json').read_text());sb=json.loads((Path(b)/'summary.json').read_text())
    first={name:first_difference(x[name],y[name]) for name in ('decision','accepted','shipment','arrival','production','terminal')}
    changed_arrivals=sum(dict(x['arrivals'].get(k,{}))!=dict(y['arrivals'].get(k,{})) for k in set(x['arrivals'])|set(y['arrivals']))
    buyer_x=defaultdict(int);buyer_y=defaultdict(int)
    for key,v in x['arrivals'].items():buyer_x[key[:3]]+=sum(v.values())
    for key,v in y['arrivals'].items():buyer_y[key[:3]]+=sum(v.values())
    quantity_changed=sum(buyer_x.get(k,0)!=buyer_y.get(k,0) for k in set(buyer_x)|set(buyer_y))
    quantity_abs_diff=sum(abs(buyer_x.get(k,0)-buyer_y.get(k,0)) for k in set(buyer_x)|set(buyer_y))
    physical_delta=sb['delivered']-sa['delivered']
    return dict(left=sa['case_id'],right=sb['case_id'],first_divergence=first,real_dated_arrival_source_buckets_different=changed_arrivals,buyer_actual_arrival_date_quantity_buckets_different=quantity_changed,buyer_actual_arrival_quantity_absolute_difference=quantity_abs_diff,arrival_bucket_scope='Union of actual arrival-day/buyer/good/need-id/need-by buckets compared by supplier quantity. Long-run trajectories progressively diverge; not independent same-state interventions at every date.',deliveries_delta=physical_delta,backlog_delta=sb['backlog']-sa['backlog'],by_sink_deliveries_delta={k:sb['sinks'][k]['delivered']-sa['sinks'][k]['delivered'] for k in sa['sinks']},physical_hash_same=sa['physical_sha256']==sb['physical_sha256'],classification='IMPROVED' if physical_delta>0 else 'DEGRADED' if physical_delta<0 else 'UNCHANGED_TOTAL',service_distribution_changed=sa['sinks']!=sb['sinks'])

def analyze(root,output):
    p=Path(root);cases=[d for d in sorted(p.iterdir()) if d.is_dir() and (d/'summary.json').exists()];summaries={d.name:json.loads((d/'summary.json').read_text()) for d in cases};pairs=[];cache={d.name:observed(d) for d in cases}
    def contrast(a,b,axis):
        value=pair(p/a,p/b,cache[a],cache[b]);value['comparison_axis']=axis;pairs.append(value)
    for d in cases:
        n=d.name
        if '_N2_' in n and n.replace('_N2_','_N3_') in summaries:contrast(n,n.replace('_N2_','_N3_'),'N2_vs_N3')
        if '_N3_' in n and n.replace('_N3_','_N4_EXPERIMENTAL_') in summaries:contrast(n,n.replace('_N3_','_N4_EXPERIMENTAL_'),'N3_vs_N4')
        if n.startswith('M2'):
            for old,new,axis in (('_R_LEGACY_','_R_PRICE_FIRST_','R'),('_P_UNIFORM_','_P_HETEROGENEOUS_','P'),('_T_EQUAL_FEASIBLE_','_T_MIXED_LEAD_','T')):
                if old in n and n.replace(old,new) in summaries:contrast(n,n.replace(old,new),axis)
    info={}
    for d in cases:
        c=json.loads((d/'causal_audit.json').read_text());s=summaries[d.name];o=cache[d.name]
        pricefirst=next((r for r in o['updates'] if r['seller']=='D' and r['result'] and r['result']['upper_hit']),None)
        u=o['updates'];day_cache=o['day_links']
        info[d.name]=dict(causal=c,first_D_upper_hit=pricefirst,update_directions={k:sum((r.get('direction') or ('UP' if r['pending_price']>r['local']['old_price'] else 'DOWN' if r['pending_price']<r['local']['old_price'] else 'HOLD'))==k for r in u) for k in ('UP','DOWN','HOLD')},tick_blocked=sum(bool(r.get('tick_blocked')) for r in u),clamp_blocked=sum(bool(r.get('clamp_blocked')) for r in u),cache_samples={str(day):{k:day_cache[day][k] for k in ('customer_identity_cache','release_identity_cache','active_buckets')} for day in (1,100,600,1000,3600) if day in day_cache})
    out=dict(cases=len(cases),days=sum(s['days'] for s in summaries.values()),pairs=pairs,case_diagnostics=info,definitions=dict(same_state_shadow='Read-only observed ranking difference at a real matching snapshot, not an executed counterfactual.',strong_price_sensitive='First actual round of price-first policy; same dated need, >=2 positive current timely executable payable different-price offers; shadow policies differ; chosen price-first line subsequently accepted.',linked_arrivals='Actual arrivals of those strong accepted orders. Does not by itself prove different arrival than a counterfactual.',different_actual_arrivals='Compared independently executed same-initial-state pairs by actual shipment/request line allocation.'))
    Path(output).write_text(json.dumps(out,indent=2,sort_keys=True)+'\n');return out

def main():
    a=argparse.ArgumentParser();a.add_argument('root',type=Path);a.add_argument('--output',required=True,type=Path);x=a.parse_args();v=analyze(x.root,x.output);print(json.dumps(dict(cases=v['cases'],days=v['days'],pairs=len(v['pairs']))))
if __name__=='__main__':main()
