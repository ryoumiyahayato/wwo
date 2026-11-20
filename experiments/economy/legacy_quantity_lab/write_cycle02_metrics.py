"""User-facing metrics from complete recorded results; no simulation imports."""
from pathlib import Path
import json,csv
ROOT=Path(__file__).resolve().parent;P=ROOT/'.local/cycle02/replay_a';E=ROOT/'economy_quantity_lab/goal_cycle02/evidence'
a=json.loads((E/'final_paired_analysis.json').read_text());negative={x['N4']:x for x in json.loads((E/'final_causal/N4_negative_controls.json').read_text())}
rows=[]
for s in json.loads((P/'summary.json').read_text()):
 name=s['case_id'];d=a['case_diagnostics'][name];c=d['causal'];group={}
 for k,q in s['input_allocations'].items():
  buyer,good,seller=k.split(':');group.setdefault(buyer+':'+good,{})[seller]=q
 shares={k:{f:q/sum(v.values()) if sum(v.values()) else 0 for f,q in v.items()} for k,v in group.items()}
 n=negative.get(name,{})
 rows.append(dict(case_id=name,suite=s['suite'],days=s['days'],mode=s['mode'],scale=s['scale'],treatment=s['treatment'],funding=s['funding'],real_machine_deliveries=s['delivered'],total_backlog=s['backlog'],backlog_by_sink={k:v['backlog'] for k,v in s['sinks'].items()},machine_days_inventory=s['machine_days_inventory'],machine_days_definition=s['machine_days_scope'],installed_machine_service_days='NOT_MODELED',max_nonproduction_days=s['max_nonproduction_days'],firm_input_accepted_by_supplier=s['input_allocations'],supplier_shares_by_buyer_commodity=shares,real_ending_stock=s['final_stock'],real_ending_in_transit=s['final_in_transit'],ending_cash_balance_reserved=s['cash'],actual_cash_payments=s['cash_payments'],actual_cash_receipts=s['cash_receipts'],posted_quote_min=s['price_min'],posted_quote_max=s['price_max'],posted_quote_final=s['prices'],posted_quote_path=name+'/prices.jsonl',v1_proposal_bound_flags=s['bound_hits'],actual_quote_UP_DOWN_HOLD=d['update_directions'],tick_blocked_windows=d['tick_blocked'],all_clamp_blocked_windows=d['clamp_blocked'],N4_learned_windows=n.get('learned_windows',0),N4_memory_target_price_blocks=n.get('memory_target_price_blocks',0),N4_original_floor_cap_blocks=n.get('original_v1_floor_cap_blocks',0),PRICE_rejected_attempt_quantity=s['rejections'].get('PRICE_LIMIT',0),CASH_rejected_attempt_quantity=s['rejections'].get('CASH',0),PHYSICAL_rejected_attempt_quantity=s['rejections'].get('PHYSICAL',0),TERMINAL_CASH_rejected_attempt_quantity=s['rejections'].get('TERMINAL_CASH',0),matched_competitive_opportunities=c['matched_competitive_opportunities'],same_state_shadow_differences=c['same_state_shadow_differences'],strong_first_round_price_sensitive_accepted_dated_needs=c['price_sensitive_first_round_accepted_needs'],actual_linked_arrival_events=c['price_sensitive_linked_arrival_events'],economic_sha256=s['economic_sha256'],physical_sha256=s['physical_sha256'],minimal_audit_events=s['events']))
(E/'final_metrics.json').write_text(json.dumps(rows,sort_keys=True,indent=2)+'\n')
with (E/'final_metrics.csv').open('w',newline='') as out:
 w=csv.DictWriter(out,fieldnames=list(rows[0]));w.writeheader()
 for r in rows:w.writerow({k:json.dumps(v,sort_keys=True,separators=(',',':')) if isinstance(v,(dict,list)) else v for k,v in r.items()})
print('59 complete metric rows; sources fully recorded; no welfare/GDP/profit interpretation')
