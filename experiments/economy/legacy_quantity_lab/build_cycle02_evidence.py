"""Read-only postprocessing; adds no runtime/fixture/candidate changes."""
from pathlib import Path
from collections import defaultdict
import json,sys,hashlib,argparse
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle01'))
sys.path.insert(0,str(ROOT/'economy_quantity_lab/goal_cycle02'))
from causal_audit import records
from observation import dump

def negative_control(root):
    p=Path(root).resolve();rows=[]
    for d in sorted(p.iterdir()):
        if not d.is_dir() or '_N3_' not in d.name or not (d/'summary.json').exists():continue
        n=p/d.name.replace('_N3_','_N4_EXPERIMENTAL_')
        if not (n/'summary.json').exists():continue
        a=json.loads((d/'summary.json').read_text());b=json.loads((n/'summary.json').read_text());learned=0;memory_block=0;original_clamp=0
        for line in records(n/'causal.jsonl'):
            r=json.loads(line)
            if r['event']!='price_update':continue
            v=r['result'];learned+=bool(v['ceiling_learned']);memory_block+=v['price']!=v['base_price'];original_clamp+=v['unclamped']!=v['base_price']
        no_price=(a['rejections'].get('PRICE_LIMIT',0)==0 and b['rejections'].get('PRICE_LIMIT',0)==0)
        identical=a['economic_sha256']==b['economic_sha256']
        if no_price:assert learned==0 and identical,'N4 altered zero-PRICE negative control'
        rows.append(dict(N3=d.name,N4=n.name,zero_PRICE_negative_control=no_price,learned_windows=learned,memory_target_price_blocks=memory_block,original_v1_floor_cap_blocks=original_clamp,authoritative_economic_hash_same=identical,note='N4 upper/lower_hit/unclamped are inherited v1 proposal flags, not claims that memory-constrained final quote reached original bound.'))
    return rows

def examples(root):
    p=Path(root).resolve();normal=p/'M4_normal_N3_L_NONBINDING_3600';equal=p/'M2_T_EQUAL_FEASIBLE_P_HETEROGENEOUS_R_PRICE_FIRST_600';source={};requests={};events={};final_buyers={x['firm_id'] for x in json.loads((equal/'initial.json').read_text())['case']['sinks']};first_dec=None;physical=None;cap=None;dated=[];unchanged=None;last_windows=[];own_plan=None
    for line in records(equal/'causal.jsonl'):
        r=json.loads(line)
        if r['event']=='decision' and r['phase']=='MATCHING' and r['round']==0 and r['buyer'] in final_buyers and first_dec is None:
            for n in r['requirements']:
                if n['matched_competitive'] and n['shadow_differs'] and r['intent'] and any(l['need_id']==n['need_id'] for l in r['intent']['lines']):first_dec=r;break
        if r['event']=='request':
            q=r['request'];requests[(r['day'],q['buyer_id'],q['supplier_id'],q['commodity'],q['procurement_round'])]=r
            if physical is None and q['rejections']['PHYSICAL']>0 and q['rejections']['PRICE_LIMIT']==0 and q['rejections']['CASH']==0:physical=r
        if first_dec and own_plan is None and r['event']=='own_plan' and r['day']==first_dec['day'] and r['firm']==first_dec['buyer']:own_plan=r
    assert first_dec
    q=requests[(first_dec['day'],first_dec['buyer'],first_dec['selected_supplier'],first_dec['commodity'],first_dec['round'])];oid=q['request']['order_id']
    chain=[]
    for line in records(equal/'events.jsonl'):
        r=json.loads(line)
        if r.get('order_id')==oid:chain.append(r)
    arrival_day=min(r['day'] for r in chain if r['event']=='arrived')
    pool_followup=[]
    for line in records(equal/'events.jsonl'):
        event=json.loads(line)
        if arrival_day<=event['day']<=arrival_day+2 and ((event['event'] in ('consumed','produced') and event['firm']==q['request']['buyer_id']) or (event['event']=='terminal' and event['seller']==q['request']['buyer_id'])):pool_followup.append(event)
    # The own plan precedes the decision; obtain it in a fresh read without simulation.
    own_plan=next(json.loads(l) for l in records(equal/'causal.jsonl') if json.loads(l)['event']=='own_plan' and json.loads(l)['day']==first_dec['day'] and json.loads(l)['firm']==first_dec['buyer'])
    for line in records(normal/'causal.jsonl'):
        r=json.loads(line)
        if r['event']=='price_update' and r['seller']=='D' and r['day']==609:cap=r
        if r['event']=='request' and r['day']==610 and r['request']['commodity']=='coal':dated.append(r)
        if r['event']=='decision' and r['day']==610 and r['buyer']=='B2' and r['commodity']=='coal' and r['selected_supplier']=='D' and r['phase']=='MATCHING':unchanged=r
        if r['day'] in (1000,3598,3599,3600) and r['event'] in ('request','price_update','day_link'):last_windows.append(r)
    return dict(price_changed_real_choice=dict(source=equal.relative_to(ROOT).as_posix(),own_plan=own_plan,observed_decision=first_dec,actual_request=q,actual_order_dispatch_arrival_payment=chain,subsequent_same_inventory_pool_consumption_production_terminal=pool_followup,scope='Material arrives in the buyer stock pool and supports recorded subsequent production/terminal deliveries. Fungible stock does not identify which exact delivered machine contains a particular cargo.'),physical_prior_to_price=dict(source=equal.relative_to(ROOT).as_posix(),actual_request=physical),first_D_cap=cap,date_separated_610=dict(classification='NO_MATCHED_COMPETITIVE_OPPORTUNITY',requests=dated),quote_change_without_eligible_choice_change=dict(actual_decision=unchanged,prior_D_quote=358,new_D_quote=360,explanation='For need616 on decision610, A ETA614 is timely but release612 is not due; only D ETA616 is executable. Changing358 to360 preserves eligibility and same-state selected supplier. This is a read-only local price-change shadow, not a rerun counterfactual.'),long_boundary_events=last_windows)

def normalized_ID_control(control_root):
    p=Path(control_root);mapping={'Y':'A','X':'D','Z1':'B1','A1':'B2','Z2':'C1','A2':'C2'}
    def key(k):
        if '>' in k:
            seller,rest=k.split('>');buyer,good=rest.split(':');return mapping.get(seller,seller)+'>'+mapping.get(buyer,buyer)+':'+good
        if ':' in k:
            firm,rest=k.split(':',1);return mapping.get(firm,firm)+':'+rest
        return mapping.get(k,k)
    def normalize(x):
        if isinstance(x,dict):return {key(k):normalize(v) for k,v in x.items()}
        if isinstance(x,list):return [normalize(v) for v in x]
        return x
    first_quantity=None;first_production=None;first_cash=None
    with (p/'ORDER_normal/daily.jsonl').open() as a,(p/'ORDER_stable_relabel/daily.jsonl').open() as b:
        for la,lb in zip(a,b):
            x=json.loads(la);y=normalize(json.loads(lb));day=x['day']
            if first_quantity is None and any(x[k]!=y[k] for k in ('stock','routes','sinks','cumulative')):first_quantity=day
            if first_production is None and x['production']!=y['production']:first_production=day
            if first_cash is None and x['cash']!=y['cash']:first_cash=day
    return dict(mapping_back=mapping,first_identity_normalized_quantity_difference=first_quantity,first_identity_normalized_production_difference=first_production,first_identity_normalized_cash_difference=first_cash,classification='POLICY_STABLE_ID_TIE_BREAK_SENSITIVITY' if first_quantity is not None else 'NO_PHYSICAL_SENSITIVITY_OBSERVED',note='Original identities are restored before comparison. Raw hashes with changed names alone are not evidence of tie-break sensitivity. Both final sink deliveries remain unchanged.')

def main():
    a=argparse.ArgumentParser();a.add_argument('--root',type=Path,default=ROOT/'.local/cycle02/replay_a');a.add_argument('--output-dir',required=True,type=Path);x=a.parse_args();x.output_dir.mkdir(parents=True,exist_ok=True)
    dump(x.output_dir/'identity_normalized_controls.json',normalized_ID_control(x.root.parent/'controls'));dump(x.output_dir/'decision_chain_examples.json',examples(x.root));dump(x.output_dir/'N4_negative_controls.json',negative_control(x.root));print('Decision chain and candidate negative controls saved')
if __name__=='__main__':main()
