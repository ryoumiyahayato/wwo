#!/usr/bin/env python3
"""WWO Rivergate B1: deterministic, authored 5x5 km Godot collision terrain.
Actual 4-m heightfield, meandering river with graded bed and ford, two river banks,
bridge approaches, roads and coherent settlement. No commercial content.
Requires numpy scipy Pillow. Operates only inside this independent Rivergate copy.
"""
import json,math,hashlib
from pathlib import Path
import numpy as np
from scipy.ndimage import gaussian_filter
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets';OUT.mkdir(exist_ok=True)
SEED=20261020;rng=np.random.default_rng(SEED);N=1251;STEP=4.0
AX=np.linspace(-2500,2500,N,dtype=np.float32);X,Z=np.meshgrid(AX,AX)
BRIDGE_Z=220.0;FORD_Z=-790.0

def river_x(z):return -430+145*np.sin(z/650)+55*np.sin(z/275+0.4)
def river_w(z):return 24+5*np.sin(z/540-0.6)**2+4*np.sin(z/240+0.3)**2
def level(z):return 9.5-0.002*z

def smooth(t):
 t=np.clip(t,0,1);return t*t*(3-2*t)

# Morphology: valley proper (near river), successive terraces, continuous upland slopes.
C=river_x(Z);D=np.abs(X-C);W=river_w(Z);WL=level(Z)
near=smooth((D-W)/34.)
hills=62*smooth((D-125)/780)**1.55
peaks=np.zeros_like(X)
for px,pz,am,rx,rz in [(-1700,1280,105,470,620),(-1380,-980,155,450,580),(1250,1550,86,630,720),(1520,-1250,112,550,510),(-1100,250,42,290,360),(750,500,44,420,430)]:
 peaks+=am*np.exp(-((X-px)/rx)**2-((Z-pz)/rz)**2)
# Multi-scale, reproducible terrain irregularity rather than repeating sine-grid bands.
noise_rng=np.random.default_rng(SEED+831)
noise_a=gaussian_filter(noise_rng.standard_normal((N,N)).astype(np.float32),sigma=48)
noise_b=gaussian_filter(noise_rng.standard_normal((N,N)).astype(np.float32),sigma=16)
noise_c=gaussian_filter(noise_rng.standard_normal((N,N)).astype(np.float32),sigma=4)
noise=(4.0*noise_a/(float(noise_a.std())+1e-8)
       +1.3*noise_b/(float(noise_b.std())+1e-8)
       +0.19*noise_c/(float(noise_c.std())+1e-8))
# Peaks must NOT leak into the real riverbanks or into the drivable ford slopes.
peaks=peaks*smooth((D-W)/155)
bank=WL+0.2+5.2*near+hills+peaks+noise*smooth((D-W)/180)
# The water boundary meets the carved bank at water level; 4+ metre bed under normal river.
depth=4.25+0.25*np.sin(Z/225)
# A ford is an explicitly shallow corridor, never applied to the bridge.
ford_blend=np.exp(-((Z-FORD_Z)/45)**4)
depth=depth*(1-ford_blend)+0.28*ford_blend
# More gentle banks at the ford; actual height and physical collision are both changed.
ford_bank=WL+0.15+2.0*smooth((D-W)/65)+hills+peaks+noise*smooth((D-W)/180)
bank=bank*(1-ford_blend)+ford_bank*ford_blend
inner=smooth((D-(W-8.0))/8.0)
riverbed=WL-depth*(1-inner) - 0.015
H=np.where(D<W,riverbed,bank)

# Bridge endpoints meet graded ramps in the HEIGHTFIELD, not fake floating road texture.
BRIDGE_X=float(river_x(BRIDGE_Z)); BRIDGE_LEVEL=float(level(BRIDGE_Z))+5.3
BRIDGE_HALF_SPAN=float(river_w(BRIDGE_Z))+23.0; BRIDGE_WIDTH=12.0
# Across-water land remains a real riverbed; only approaches ramp upwards.
za=np.exp(-((Z-BRIDGE_Z)/12)**4)
absbx=np.abs(X-BRIDGE_X)
approach=(absbx>=BRIDGE_HALF_SPAN)&(absbx<=BRIDGE_HALF_SPAN+95)
alpha=(1-smooth((absbx-BRIDGE_HALF_SPAN)/95))*za
H=np.where(approach,H*(1-alpha)+BRIDGE_LEVEL*alpha,H)
# Prevent a 1m wheel step where the physical deck meets the sculpted terrain.
# Sculpted support uses the SAME baked heightfield as colliders.
seam_lift=np.exp(-((absbx-BRIDGE_HALF_SPAN)/13)**4)*np.exp(-((Z-BRIDGE_Z)/11)**4)
H=H*(1-seam_lift)+BRIDGE_LEVEL*seam_lift
H=np.asarray(H,dtype='<f4'); assert np.isfinite(H).all()
(OUT/'height_4m.f32').write_bytes(H.tobytes(order='C'))

# Shared water-source curve, every 5m. Runtime interpolates this exact array for water geometry.
zs=np.arange(-2500,2501,5,dtype=float)
profile=[{'z':round(float(z),3),'x':round(float(river_x(z)),5),'half_width':round(float(river_w(z)),5),'water_y':round(float(level(z)),5)} for z in zs]
meta={'schema':'rivergate-hydrology-v1','world_m':[5000,5000],'height_grid':{'n':N,'step_m':STEP,'origin_m':-2500,'file':'height_4m.f32'},'profile':profile,'bridge':{'id':'bridge_road_01','center_x':BRIDGE_X,'center_z':BRIDGE_Z,'deck_top_y':BRIDGE_LEVEL,'half_span_m':BRIDGE_HALF_SPAN,'width_m':BRIDGE_WIDTH,'collision_layer':8},'ford':{'id':'ford_road_01','center_z':FORD_Z,'nominal_depth_m':0.28,'width_transition_m':45},'notes':'Water is a visual surface over true carved ground, not a drivable invisible slab. Bridge is a separate solid elevated road.'}
(OUT/'hydrology.json').write_text(json.dumps(meta,ensure_ascii=False,separators=(',',':')),encoding='utf-8')

# Bilinear approx of same 4m field; stored world objects are assigned to actual support samples at load time.
def sample(x,z):
 fx=np.clip((np.asarray(x,dtype=float)+2500)/STEP,0,N-1.000001);fz=np.clip((np.asarray(z,dtype=float)+2500)/STEP,0,N-1.000001)
 ix=np.floor(fx).astype(np.intp);iz=np.floor(fz).astype(np.intp);a=fx-ix;b=fz-iz
 return (1-a)*(1-b)*H[iz,ix]+a*(1-b)*H[iz,ix+1]+(1-a)*b*H[iz+1,ix]+a*b*H[iz+1,ix+1]

# Roads: fully connected over bridge and ford, no unsupported additional river crossings.
def west(z):return float(river_x(z)-river_w(z)-105)
def east(z):return float(river_x(z)+river_w(z)+105)
roads=[
 {'id':'main_east_valley','type':'gravel','width_m':8.5,'points':[(east(z),float(z)) for z in np.linspace(-2250,2230,55)]},
 {'id':'main_west_valley','type':'dirt','width_m':7.0,'points':[(west(z),float(z)) for z in np.linspace(-2100,2170,54)]},
 {'id':'bridge_crossing','type':'stone','width_m':10.0,'points':[(BRIDGE_X+d,BRIDGE_Z) for d in np.linspace(-210,210,43)]},
 {'id':'ford_crossing','type':'gravel','width_m':8.5,'points':[(float(river_x(FORD_Z))+d,FORD_Z) for d in np.linspace(-210,210,43)]},
 {'id':'village_connector','type':'dirt','width_m':7.0,'points':[(east(220),220),(120,270),(240,350),(360,460),(500,700)]},
 {'id':'old_farm_road','type':'dirt','width_m':5.5,'points':[(east(-920),-920),(-130,-650),(35,-380),(90,-120),(120,270)]},
 {'id':'west_ridge_route','type':'track','width_m':6.0,'points':[(west(220),220),(-700,380),(-850,550),(-1040,900),(-1220,1160)]},
 {'id':'quarry_spur','type':'track','width_m':5.5,'points':[(east(700),700),(380,850),(610,1040),(730,1180)]},
]

def segdist(xx,zz,points):
 dd=np.full(np.broadcast(xx,zz).shape,np.inf,dtype=float)
 for (ax,az),(bx,bz) in zip(points,points[1:]):
  vx=bx-ax;vz=bz-az;l=vx*vx+vz*vz
  if l<.001:continue
  t=np.clip(((xx-ax)*vx+(zz-az)*vz)/l,0,1)
  dd=np.minimum(dd,np.hypot(xx-(ax+t*vx),zz-(az+t*vz)))
 return dd

# Make route grades drivable: trim short-wavelength noise on the selected paths only.
# The bridge is raised separately, so we do not flatten its river channel.
for road in roads:
 dist=segdist(X,Z,road['points']);mask=smooth((road['width_m']*.5+14-dist)/14)
 if road['id']=='bridge_crossing':mask*=((np.abs(X-BRIDGE_X)>BRIDGE_HALF_SPAN) | (np.abs(Z-BRIDGE_Z)>9))
 # light low-pass of existing terrain, not arbitrary constant elevation
 low=gaussian_filter(H.astype(np.float32),sigma=2.0)
 H=(H*(1-mask*.65)+low*(mask*.65)).astype('<f4')
(OUT/'height_4m.f32').write_bytes(H.tobytes(order='C'))

# Texture maps sampled from the same river/road/landcover. Emissive river is separate geometry.
T=1024; t_axis=np.linspace(-2500,2500,T,dtype=np.float32);TX,TZ=np.meshgrid(t_axis,t_axis)
TD=np.abs(TX-river_x(TZ));TW=river_w(TZ)
road_dist=np.full((T,T),np.inf,dtype=float)
for road in roads:road_dist=np.minimum(road_dist,segdist(TX,TZ,road['points'])/(road['width_m']*.55))
Htex=sample(TX,TZ)
shape=np.clip((TD-TW)/70,0,1)
farforest=(np.sin(TX/180)+np.cos(TZ/230)+np.sin((TX+TZ)/105)*.6)>0.82
rn=np.random.default_rng(SEED).normal(0,7,(T,T))
cols=np.zeros((T,T,3),dtype=np.float32)
cols[:]=[104,124,78]
cols+=np.where(farforest[...,None],np.array([[-10,11,-4]],dtype=float),0)
cols+=np.where((Htex>105)[...,None],np.array([[13,10,0]]),0)
cols+=np.where((Htex>170)[...,None],np.array([[24,24,21]]),0)
cols+=np.where((TD<TW+24)[...,None],np.array([[20,13,-5]]),0)
cols+=np.where((road_dist<1)[...,None],np.array([[42,30,7]],dtype=float),0)
cols+=rn[...,None]*.32
c=np.uint8(np.clip(cols,0,255));Image.fromarray(c,'RGB').save(OUT/'land_color.png')
control=np.zeros((T,T,3),dtype=np.uint8)
control[:,:,0]=np.uint8(np.clip((1-shape)*120+(road_dist<1)*240,0,255))
control[:,:,1]=np.uint8((Htex<125)*45)
control[:,:,2]=np.uint8(np.clip((Htex-70)/140*255,0,255))
Image.fromarray(control,'RGB').save(OUT/'land_control.png')

# Settlements are on dry banks at small offsets from genuine roads, with preserved spawning bubble.
places=[]
for name,zz,side,count in [('east_village',300,1,16),('west_hamlet',415,-1,8),('southern_farm',-1140,1,5),('north_works',1030,1,5)]:
 bankx=east(zz) if side==1 else west(zz)
 for i in range(count):
  row=i//4;col=i%4
  x=bankx+side*(44+row*25)+(-1)**col*6
  z=zz+(col-1.5)*34
  if abs(x)<85 and abs(z)<210:continue
  places.append({'id':f'{name}_{i:02d}','kind':'house_'+str(i%3) if (i%5)!=0 else 'barn','position':[round(x,2),0.,round(z,2)],'yaw':round(0.13*(i%5),4),'scale':1.0,'location':name})
# Obstacles on banks, sparsely near routes / spawn; reused cedar GLB files.
for i in range(240):
 xx=float(rng.uniform(-1800,1500));zz=float(rng.uniform(-1700,1700));dd=float(abs(xx-river_x(zz)))
 if dd<float(river_w(zz))+18:continue
 if abs(xx)<120 and abs(zz)<230:continue
 if any(math.hypot(xx-p['position'][0],zz-p['position'][2])<22 for p in places):continue
 if any(float(segdist(xx,zz,road['points']))<road['width_m']+8 for road in roads):continue
 places.append({'id':f'pine_{i:03d}','kind':'tree_'+str(i%3),'position':[round(xx,2),0.,round(zz,2)],'yaw':round(float(rng.uniform(0,2*math.pi)),5),'scale':round(float(rng.uniform(.8,1.4)),3),'location':'forest_bank'})
for i in range(44):
 xx=float(rng.uniform(-1600,1350));zz=float(rng.uniform(-1400,1450));dd=float(abs(xx-river_x(zz)))
 if dd<float(river_w(zz))+6 or abs(xx)<95 and abs(zz)<210:continue
 if any(float(segdist(xx,zz,road['points']))<road['width_m']+4 for road in roads):continue
 places.append({'id':f'rock_{i:02d}','kind':'rock_'+str(i%3),'position':[round(xx,2),0.,round(zz,2)],'yaw':round(float(rng.uniform(0,2*math.pi)),5),'scale':round(float(rng.uniform(1,2.7)),3),'location':'ridge'})
# World spots contain original heights for offline lookups; runtime samples same terrain.
for p in places:p['position'][1]=round(float(sample(p['position'][0],p['position'][2])),4)

cedar_colliders=json.loads((ROOT.parent/'cedar/assets/map.json').read_text('utf-8'))['colliders']
manifest={'schema':'rivergate-map-v1','map_id':'rivergate_5km_b1','world_extent_m':[5000,5000],'seed':SEED,'hydrology_file':'hydrology.json','roads':roads,'placements':places,'colliders':cedar_colliders,'semantics':{'riverbed':'true depressed heightfield, normal water depth >4m','water':'visual surface only; no fake collision platform or assumed buoyancy','ford':'real shallow riverbed (approx 0.28m) and gentler banks','bridge':'separate drivable collision deck, road top is used in support sampling','road':'terrain-conforming display strip; underlying ground remains support','settlements':'static collision envelopes; no new combat or AI units','no_new_actors':True}}
(OUT/'map.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
print('height m',float(H.min()),float(H.max()),'start m',float(sample(-6,-7)),'river x0',float(river_x(0)), 'bridge',BRIDGE_X,BRIDGE_LEVEL,BRIDGE_HALF_SPAN,'placements',len(places))
print('output bytes',sum(p.stat().st_size for p in OUT.iterdir() if p.is_file()))
