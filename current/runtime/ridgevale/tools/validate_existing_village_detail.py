#!/usr/bin/env python3
"""Independent overlay preservation, geometry, local slope, and budget checks."""
from pathlib import Path
import hashlib,json,math
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];PROJECT=ROOT.parent
BASE=ROOT/'detail/base';failures=[];checks=0
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def check(value,label):
 global checks
 checks+=1
 if not value:failures.append(label)
m=json.loads((ROOT/'assets/map.json').read_text());b=json.loads((BASE/'map.json').read_text());r=json.loads((ROOT/'review/detail_generation_receipt.json').read_text())
H=np.fromfile(ROOT/'assets/height_4m.f32',dtype='<f4').reshape(1251,1251)
def sample(x,z):
 fx=(np.asarray(x,dtype=float)+2500)/4;fz=(np.asarray(z,dtype=float)+2500)/4
 ix,iz=fx.astype(int),fz.astype(int);tx,tz=fx-ix,fz-iz
 return H[iz,ix]*(1-tx)*(1-tz)+H[iz,ix+1]*tx*(1-tz)+H[iz+1,ix]*(1-tx)*tz+H[iz+1,ix+1]*tx*tz
check(m['placements'][:117]==b['placements'],'all 117 original poses and semantic rows identical')
for key in ['roads','fields','height_grid','world_extent_m','protected_deployment_rectangle_xz','asset_statistics','colliders','source_id']:
 check(m[key]==b[key],'original '+key+' unchanged')
check(sha(ROOT/'assets/height_4m.f32')==r['height_preserved_sha256']==m['detail_overlay']['preserved_height_sha256'],'height bytes unchanged')
for name,value in r['base_sha256'].items():check(sha(BASE/name)==value,'base snapshot '+name)
for name,value in r['output_sha256'].items():check(sha(ROOT/'assets'/name)==value,'output hash '+name)
receipt=json.loads((BASE/'generation_receipt.json').read_text())
for name,value in receipt['reused_sha256'].items():check(sha(PROJECT/name)==value,'reused GLB unchanged '+name)
added=m['placements'][117:];stats={s['mesh']:s for s in m['asset_statistics']}
check(len(added)==69 and len(m['placements'])==186,'bounded 69 additions / 186 total')
check(sum(p['kind']=='wall_4m' for p in added)==52,'52 reused wall segments')
check(sum(p['kind'].startswith('tree') for p in added)==17,'17 reused trees')
check({p['kind'] for p in added}<=set(p['kind'] for p in b['placements']),'no new mesh types')
check(r['base_batches']==94 and r['final_batches']==113 and r['added_batches']==19,'19 additional existing cell/asset batches, 113 total')
def bounds(p):
 low,high=stats[p['kind']]['bounds'];pts=[];x,_,z=p['position'];yaw=p['yaw'];scale=p['scale']
 for lx in [low[0],high[0]]:
  for lz in [low[2],high[2]]:pts.append([x+(math.cos(yaw)*lx+math.sin(yaw)*lz)*scale,z+(-math.sin(yaw)*lx+math.cos(yaw)*lz)*scale])
 v=np.array(pts);return v.min(axis=0),v.max(axis=0)
road_samples=[]
for road in m['roads']:
 for p,q in zip(road['points'],road['points'][1:]):
  p=np.array(p);q=np.array(q);t=np.linspace(0,1,math.ceil(np.linalg.norm(q-p))+1)
  road_samples.append((p[None,:]+(q-p)[None,:]*t[:,None],road['width_m']/2+3))
min_clear=1e9;max_wall_spread=0
for p in added:
 lo,hi=bounds(p);xmin,zmin=lo;xmax,zmax=hi
 check(not(xmin<120 and xmax>-120 and zmin<340 and zmax>-180),'whole new mesh excludes deployment '+p['id'])
 check(130<=min(abs(xmin),abs(xmax)) and max(abs(xmin),abs(xmax))<=205 and -51<=zmin<=zmax<=302,'bounded village-only detail '+p['id'])
 for samples,keep in road_samples:
  d=np.maximum(np.maximum(lo-samples,samples-hi),0);distance=float(np.sqrt((d*d).sum(axis=1)).min())
  min_clear=min(min_clear,distance-keep);check(distance>keep,'major-road envelope clearance '+p['id'])
 if p['kind']=='wall_4m':
  x,z=np.meshgrid(np.linspace(xmin,xmax,21),np.linspace(zmin,zmax,21));ground=sample(x,z)
  bottom=p['position'][1]+p['ground_offset_m'];top=bottom+1.33
  check(bottom+.01<=float(ground.min())+.001,'wall bottom never floats '+p['id'])
  check(top-float(ground.max())>.95,'wall retains at least 0.95m above highest footprint '+p['id'])
  max_wall_spread=max(max_wall_spread,float(ground.max()-ground.min()))
  check(-.3<=p['ground_offset_m']<0,'bounded static grounding offset '+p['id'])
# Pixel-locality check: no changed major-road pixels or original deployment pixels.
axis=np.linspace(-2500,2500,2048);X,Z=np.meshgrid(axis,axis)
protected=(abs(X)<=120)&(Z>=-180)&(Z<=340)
changed_pixels={}
for name in ['land_color','land_control']:
 old=np.array(Image.open(BASE/(name+'.png')));new=np.array(Image.open(ROOT/'assets'/(name+'.png')))
 changed=np.any(old!=new,axis=2);changed_pixels[name]=int(changed.sum())
 check(not changed[protected].any(),'no protected-deployment texture change '+name)
 allowed=(abs(X)>=122)&(abs(X)<=205)&(Z>=-48)&(Z<=307)
 check(not changed[~allowed].any(),'surface changes limited to village strips '+name)
 for road in m['roads']:
  for a,c in zip(road['points'],road['points'][1:]):
   vx,vz=c[0]-a[0],c[1]-a[1];t=np.clip(((X-a[0])*vx+(Z-a[1])*vz)/(vx*vx+vz*vz),0,1)
   road_mask=np.hypot(X-(a[0]+t*vx),Z-(a[1]+t*vz))<=road['width_m']/2+3
   check(not changed[road_mask].any(),'no major-road repaint '+name+' '+road['id'])
node_walls=[p for p in added if p.get('detail_group')=='west_courtyard_complete']
node_trees=[p for p in added if p.get('detail_group')=='west_courtyard_grove']
check(len(node_walls)==22 and len(node_trees)==5,'one composed west node has 22 walls and 5 trees')
check(m['placements'][2]==b['placements'][2],'representative original house remains on original pad')
east=sorted([p['position'][2] for p in node_walls if abs(p['position'][0]+138.25)<.01])
check(abs((east[2]-2.225)-(east[1]+2.225)-17.8)<1e-6,'actual east main gate collider gap is 17.8m')
north=[p for p in node_walls if abs(p['position'][2]-112.8)<.01]
last_north_end=max(p['position'][0]+2.225 for p in north)
check(abs((-138.25-.29)-last_north_end-8.61)<1e-6,'actual northeast clear collider gap is 8.61m')
profiles=[]
for c in m['detail_overlay']['courtyards']:
 maxgrade=0;crossgrade=0
 for z in [c['center_z']-5,c['center_z'],c['center_z']+5]:
  xs=np.arange(123,143.501,.25)*c['side'];ys=sample(xs,z)
  maxgrade=max(maxgrade,float(np.abs(np.diff(ys)).max()/.25))
 xs=np.arange(123,143.501,.25)*c['side']
 crossgrade=float(np.abs(sample(xs,c['center_z']-5)-sample(xs,c['center_z']+5)).max()/10)
 check(maxgrade<.34,'existing yard approach max longitudinal grade under 34% '+c['id'])
 check(crossgrade<.07,'existing yard approach crossgrade under 7% '+c['id'])
 check(c['gate_width_m']==(17.8 if c['id']=='west_1' else 16.1) and c['apron_width_m']==10,'broad existing pad access '+c['id'])
 profiles.append({'id':c['id'],'max_longitudinal_grade':maxgrade,'max_cross_grade':crossgrade,'gate_width_m':c['gate_width_m'],'tested_apron_width_m':10})
report={'test':'ridgevale_existing_detail_static','ok':not failures,'checks':checks,'failures':failures,'courtyard_profiles':profiles,
        'minimum_new_prop_major_road_envelope_clearance_m':min_clear,'max_new_wall_ground_spread_m':max_wall_spread,
        'changed_surface_pixels':changed_pixels,'budget':{'placements':186,'added':69,'batches':113,'additional_batches':19},
        'scope':'Numerical geometry/surface proof; native physics, GPU image, driving and AI require separate evidence.'}
(ROOT/'review/detail_static_contract.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
raise SystemExit(0 if not failures else 1)
