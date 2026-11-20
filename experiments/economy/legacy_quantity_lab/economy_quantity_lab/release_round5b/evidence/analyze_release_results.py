"""Read complete generated evidence; emit compact causal and recovery observations."""
import argparse,csv,json
from pathlib import Path

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--reference-dir',type=Path,required=True);p.add_argument('--output',type=Path,required=True); a=p.parse_args()
 if a.output.exists(): p.error('new output file required')
 result={}; summaries=list(csv.DictReader((a.reference_dir/'summary.csv').open(encoding='utf-8')))
 for summary in summaries:
  name=summary['case_id']; dest=a.reference_dir/name; rows=list(csv.DictReader((dest/'daily.csv').open(encoding='utf-8')))
  def number(row,key): return float(row.get(key,0))
  def window_start(key,minimum=10,zero=False):
   return next((int(r['day']) for i,r in enumerate(rows) if int(r['day'])>=80 and len(rows[i:i+20])==20 and (all(number(x,key)==0 for x in rows[i:i+20]) if zero else sum(number(x,key) for x in rows[i:i+20])/20>=minimum)),None)
  details=dict(final={k:rows[-1][k] for k in ('B_coal_on_hand','C_steel_on_hand','C_machine_on_hand','total_live_pending','total_in_transit','B_C_pending_dispatch','B_C_in_transit','observed_daily_demand','unique_absolute_date_buckets')},
   days_with_exposure_block=sum(number(r,'B_timely_release_gap')>0 and number(r,'B_exposure_room')==0 for r in rows),
   late200_production_mean=sum(number(r,'production_C') for r in rows[-200:])/200,
   recovery_windows=dict(scope='20-day means production/delivery>=10; backlog all zero; independent start dates, never whole-chain recovery',production=window_start('production_C'),delivery=window_start('terminal_delivery'),backlog_clear=window_start('terminal_backlog',zero=True)),
   pre_shutdown_day49={k:rows[48][k] for k in ('B_coal_on_hand','C_steel_on_hand','C_machine_on_hand','global_supply_position','terminal_backlog')},
   recovery80plus=dict(max_machine_production=max(number(r,'production_C') for r in rows[79:]),days_above10=sum(number(r,'production_C')>10 for r in rows[79:]),coal_arrivals=sum(number(r,'A_B_arrival')+number(r,'D_B_arrival') for r in rows[79:])),
   transitions=[{k:r[k] for k in ('day','observed_daily_demand','terminal_backlog','production_C','terminal_delivery','coal_visible_requirement','steel_visible_requirement','coal_excess_exposure','steel_excess_exposure','global_supply_position')} for r in rows if int(r['day']) in (99,100,101,110,119,120,130,599,600)])
  if summary['policy']!='X0':
   release=json.loads((dest/'release_checks.json').read_text()); requests=json.loads((dest/'disposition.json').read_text())['requests']
   selected=[r for records in release.values() for r in records if r['supplier_id']=='E' and r['executable_qty']>0]
   details['first_E_projected_release']=next((r for r in selected if r['requirement_class']=='PROJECTED'),None)
   details['first_E_accepted']=next((r for r in requests if r['supplier']=='E' and r['accepted']>0),None)
   details['date_bounds_verified']=True
   allocated=0
   # Per-boundary supplies never exceed their own quantity and cover only timely dates.
   for boundary in json.loads((dest/'supply_reconciliation.json').read_text()).values():
    bylot={s['supply_id']:s for s in boundary['supplies']}; used={}
    for entry in boundary['allocations']:
     assert entry['available_by_day']<=entry['need_by_day'];used[entry['lot_id']]=used.get(entry['lot_id'],0)+entry['quantity'];allocated+=1
    assert all(q<=bylot[k]['quantity'] for k,q in used.items())
   details['allocation_records_verified']=allocated
  result[name]=details
 a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
if __name__=='__main__': main()
