#!/usr/bin/env python3
"""Independent static integrity tests; DOES NOT substitute for Godot runtime."""
import json,math,hashlib,re,sys
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
R=ROOT/'rivergate';assets=R/'assets';hpath=assets/'height_4m.f32'
checks={}
def must(name,cond):
 checks[name]=bool(cond)
 if not cond:print('FAIL',name,file=sys.stderr)

height=np.fromfile(hpath,dtype='<f4')
m=json.loads((assets/'map.json').read_text('utf-8'))
d=json.loads((assets/'hydrology.json').read_text('utf-8'))
N=1251
must('height_1251sq_4m',height.size==N*N)
must('height_all_finite',bool(np.isfinite(height).all()))
must('height_minmax_in_map_bounds',float(height.min())>=-50 and float(height.max())<350)
h=height.reshape(N,N)
def sample(x,z):
 fx=min(max((x+2500)/4,0),1249.999999);fz=min(max((z+2500)/4,0),1249.999999)
 i=int(fx);j=int(fz);u=fx-i;v=fz-j
 return float((1-v)*((1-u)*h[j,i]+u*h[j,i+1])+v*((1-u)*h[j+1,i]+u*h[j+1,i+1]))
def profile(z):
 p=(z+2500)/5;i=min(999,int(p));t=p-i
 a=d['profile'][i];b=d['profile'][i+1]
 return {k:a[k]*(1-t)+b[k]*t for k in ['x','half_width','water_y']}
bridge=d['bridge'];ford=d['ford']
must('unique_river_profile',len(d['profile'])==1001 and d['profile'][0]['z']==-2500 and d['profile'][-1]['z']==2500)
must('all_river_profile_finite',all(all(math.isfinite(p[k]) for k in ('x','half_width','water_y')) for p in d['profile']))
must('continuous_river_ribbon',all(abs(d['profile'][i+1]['x']-d['profile'][i]['x'])<5 for i in range(1000)))
asserted_deep=[-1700,-1200,-200,20,450,850,1400,2100]
for i,z in enumerate(asserted_deep):
 pp=profile(z);depth=pp['water_y']-sample(pp['x'],z)
 must(f'normal_river_depth_{i}',depth>2.8 and depth<6.0)
pp=profile(ford['center_z']);fd=pp['water_y']-sample(pp['x'],ford['center_z'])
must('real_shallow_ford_0p1_to_0p8m',0.10<fd<0.8)
must('ford_bank_slope_drivable',all((sample(pp['x']+side*(pp['half_width']+10),ford['center_z'])-pp['water_y'])<2 for side in (-1,1)))
cb=bridge['center_x'];cz=bridge['center_z'];span=bridge['half_span_m'];deck=bridge['deck_top_y']
must('bridge_crosses_true_water',d['profile'][int((cz+2500)/5)]['water_y']<deck-3)
must('bridge_ends_within_0p4m_ground',all(abs(deck-sample(cb+side*(span+1),cz))<0.4 for side in (-1,1)))
must('bridge_no_unsupported_height_ramp',all(abs(deck-sample(cb+side*(span+4),cz))<0.9 for side in (-1,1)))
must('spawn_on_dry_ground',sample(-6,-7)>profile(-7)['water_y']+3)
must('8_connected_roads',len(m['roads'])==8 and len(set(r['id'] for r in m['roads']))==8)
must('explicit_bridge_and_ford_crossing',{'bridge_crossing','ford_crossing'}<=set(r['id'] for r in m['roads']))
must('terrain_game_profile',m['schema']=='rivergate-map-v1' and d['schema']=='rivergate-hydrology-v1')
rows=m['placements'];must('placement_IDs_unique',len(rows)==len({row['id'] for row in rows}))
must('some_buildings',sum(row['kind'] in ['barn','house_0','house_1','house_2'] for row in rows)>=22)
must('terrain_props',sum(row['kind'].startswith('tree') for row in rows)>=200)
must('no_new_military_entities',m['semantics'].get('no_new_actors',False))
for row in rows:
 must('asset_'+row['kind'],(ROOT/'cedar/assets'/f'{row["kind"]}.glb').exists())
 must('collision_'+row['kind'],row['kind'] in m['colliders'])
 must('valid_placement_'+str(row['id']),all(math.isfinite(x) for x in row['position']))
for gd in R.rglob('*.gd'):
 code=gd.read_text('utf-8')
 for ref in re.findall(r'res://([\w./-]+\.(?:gdshader|gd|png|f32|json))',code):
  must('res_'+ref,(ROOT/ref).exists())
 must('gd_' + gd.name + '_no_merge_conflict', all(x not in code for x in ['<<<<<<<','>>>>>>>']))
must('river_switch_main', 'res://rivergate/terrain.gd' in (ROOT/'scripts/main.gd').read_text())
must('bridge_static_body', 'RivergateBridge_Deck_Collision' in (R/'world.gd').read_text() and 'collision_layer = 8' in (R/'world.gd').read_text())
must('water_separate_non_colliding', 'WaterSegment_' in (R/'water.gd').read_text() and 'StaticBody3D' not in (R/'water.gd').read_text())
must('main_original_person_identity', 'PLAYER_VEHICLE_ID' in (ROOT/'scripts/main.gd').read_text())
must('water_no_fake_damage', all(t not in (R/'water.gd').read_text() for t in ['health -=','ammo -=','apply_damage']))
report={'schema':'rivergate-static-check-v1','map_id':'rivergate_5km_b1','checks':len(checks),'passed':sum(checks.values()),'failed':[k for k,v in checks.items() if not v], 'asset_files':{'height_float32_bytes':hpath.stat().st_size,'river_profile_entries':len(d['profile']),'scenery_placements':len(rows),'road_count':len(m['roads'])},'terrain_height_minmax_m':[float(height.min()),float(height.max())],'river_depth_examples_m':{str(z):float(profile(z)['water_y']-sample(profile(z)['x'],z)) for z in asserted_deep},'ford_depth_m':fd,'bridge_deck_top_m':deck,'main_spawn_height_m':sample(-6,-7),'godot_import':'NOT_RUN','godot_driving':'NOT_RUN','android':'NOT_TESTED'}
(R/'review/static_validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='river_depth_examples_m'},ensure_ascii=False,indent=2))
raise SystemExit(0 if not report['failed'] else 1)
