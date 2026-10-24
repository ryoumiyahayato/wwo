#!/usr/bin/env python3
"""Deterministic detail overlay for existing Ridgevale C1. Never writes heights or GLBs.
Base assets are immutable copies of the previous candidate. No terrain generation,
new models, actors, traversal rules, or cover/foliage LOS mechanics are introduced.
"""
from pathlib import Path
import argparse, copy, hashlib, json, math
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'detail/base'
ID='ridgevale_existing_village_detail_v2'
SHA=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--verify-rebuild',action='store_true')
args=parser.parse_args()
DEST=ROOT/'review/detail_rebuild' if args.verify_rebuild else ROOT
OUT=DEST/'assets'; REVIEW=DEST/'review'
OUT.mkdir(parents=True,exist_ok=True); REVIEW.mkdir(parents=True,exist_ok=True)
m=json.loads((BASE/'map.json').read_text())
base_receipt=json.loads((BASE/'generation_receipt.json').read_text())
H=np.fromfile(ROOT/'assets/height_4m.f32',dtype='<f4').reshape(1251,1251)
assert SHA(ROOT/'assets/height_4m.f32')==base_receipt['generated_sha256']['height_4m.f32']
def sample(x,z):
    fx=np.clip((np.asarray(x,dtype=np.float64)+2500)/4,0,1249.999999)
    fz=np.clip((np.asarray(z,dtype=np.float64)+2500)/4,0,1249.999999)
    ix,iz=fx.astype(int),fz.astype(int);tx,tz=fx-ix,fz-iz
    return H[iz,ix]*(1-tx)*(1-tz)+H[iz,ix+1]*tx*(1-tz)+H[iz+1,ix]*(1-tx)*tz+H[iz+1,ix+1]*tx*tz
added=[];courts=[]
for side in [-1,1]:
    for j,z in enumerate([-35,95,225]):
        name=('west' if side<0 else 'east')+f'_{j}'
        walls=[(141.225,z-12.5,0),(145.675,z-12.5,0),(141.225,z+12.5,0),(145.675,z+12.5,0),(139,z-10.275,math.pi/2),(139,z+10.275,math.pi/2)]
        for k,(ax,wz,yaw) in enumerate(walls):
            x=side*ax
            # Embed the base at the lowest sampled footprint. No suspended wall ends.
            lx,lz=np.meshgrid(np.linspace(-2.225,2.225,19),np.linspace(-.29,.29,5))
            wx=x+math.cos(yaw)*lx+math.sin(yaw)*lz
            zz=wz-math.sin(yaw)*lx+math.cos(yaw)*lz
            ground=float(sample(x,wz)); low=float(np.min(sample(wx,zz)))
            added.append({'id':f'detail_wall_{name}_{k}','kind':'wall_4m','position':[x,ground,wz],
                          'yaw':yaw,'scale':1.0,'collision':'solid_wall','ground_offset_m':round(low-ground-.02,6),
                          'detail_group':name})
        courts.append({'id':name,'house_id':f'house_{(0 if side<0 else 6)+j*2:02d}',
                       'side':side,'center_z':z,'gate_x':side*139,'gate_width_m':16.1,
                       'apron_centerline':[[side*123,z],[side*139,z],[side*143,z]],
                       'apron_width_m':10.0,'role':'existing house courtyard approach, not an additional road'})
    for j,z in enumerate([30,160,285]):
        for k,(x,dz) in enumerate([(194,-10),(196,11)]):
            wx=side*x;wz=z+dz;index=j*2+k
            added.append({'id':f'detail_tree_{"west" if side<0 else "east"}_{index}',
                          'kind':f'tree_{(index+(1 if side>0 else 0))%3}',
                          'position':[wx,float(sample(wx,wz)),wz],
                          'yaw':round((index*1.618+side*.37)%math.tau,6),'scale':[.94,1.06][k],
                          'collision':'trunk','ground_offset_m':-.05,'detail_group':'outer_house_tree_pairs'})
# A single representative court receives the full composition pass. Other nodes
# retain v1 exactly: no global scattering and no house or heightfield edits.
added=[p for p in added if p.get('detail_group')!='west_1']
west_walls=[]
# Continuous west edge (visible from the agreed west inspection camera).
for i in range(8):west_walls.append((-165.2,79.425+i*4.45+(.15 if i==0 else -.15 if i==7 else 0),math.pi/2))
# Full south boundary plus a north boundary ending before the 8.61 m clear exit.
for i in range(6):west_walls.append((-162.725+i*4.45,77.2,0))
for i in range(4):west_walls.append((-162.725+i*4.45,112.8,0))
# Two paired returns on the east leave a 17.8 m main opening.
for wz in [79.425,83.875,106.125,110.575]:west_walls.append((-138.25,wz,math.pi/2))
for k,(x,z,yaw) in enumerate(west_walls):
    lx,lz=np.meshgrid(np.linspace(-2.225,2.225,25),np.linspace(-.29,.29,7))
    wx=x+math.cos(yaw)*lx+math.sin(yaw)*lz;zz=z-math.sin(yaw)*lx+math.cos(yaw)*lz
    ground=float(sample(x,z));low=float(np.min(sample(wx,zz)))
    added.append({'id':f'detail_wall_west_court_{k:02d}','kind':'wall_4m','position':[x,ground,z],
                  'yaw':yaw,'scale':1.0,'collision':'solid_wall','ground_offset_m':round(low-ground-.02,6),
                  'detail_group':'west_courtyard_complete'})
for k,(x,z,scale) in enumerate([(-172,85,.95),(-172.5,105,1.02),(-177,118,1.08),(-168,124,.97),(-158,124,.90)]):
    added.append({'id':f'detail_tree_west_court_{k}','kind':f'tree_{k%3}',
                  'position':[x,float(sample(x,z)),z],'yaw':round((k*1.83+.2)%math.tau,6),'scale':scale,
                  'collision':'trunk','ground_offset_m':-.05,'detail_group':'west_courtyard_grove'})
for court in courts:
    if court['id']=='west_1':
        court['gate_x']=-138.25;court['gate_width_m']=17.8
        court['enclosure_xz']=[-165.2,77.2,-138.25,112.8]
        court['north_exit_clear_width_m']=8.61
        court['circulation_points_xz']=[[-142.5,118],[-142.5,110],[-142.5,95],[-142.5,81.5],[-153,81.5],[-161.5,81.5],[-161.5,95],[-161.5,108.5],[-153,108.5],[-142.5,108.5]]
assert len(added)==69
m['placements']+=added
m['detail_overlay']={'id':ID,'base_placements':117,'added_placements':69,'added_walls':52,'added_trees':17,
                    'total_placements':186,'courtyards':courts,
                    'representative_node':{'house_id':'house_02','wall_segments':22,'trees':5,'house_moved':False,
                                           'enclosure_xz':[-165.2,77.2,-138.25,112.8],
                                           'main_gate_clear_width_m':17.8,'north_exit_clear_width_m':8.61},
                    'preserved_height_sha256':base_receipt['generated_sha256']['height_4m.f32'],
                    'surface_scope':'localized courtyards/tree beds, with one fully composed west court; no major road repaint',
                    'foliage_semantics':'visual canopy only; existing trunk-cylinder collision, no foliage LOS claim'}
(OUT/'map.json').write_text(json.dumps(m,ensure_ascii=False,separators=(',',':'))+'\n')
# Use original RGB bytes everywhere outside a small explicit overlay footprint.
color=np.array(Image.open(BASE/'land_color.png')).copy();control=np.array(Image.open(BASE/'land_control.png')).copy()
axis=np.linspace(-2500,2500,2048);X,Z=np.meshgrid(axis,axis)
mask=np.zeros((2048,2048),dtype=np.float64)
for court in courts:
    ax=X*court['side']; dz=abs(Z-court['center_z'])
    # Firm courtyard apron, softly blended into the original pad and saddle edge.
    yard=np.clip((ax-128)/3,0,1)*np.clip((149-ax)/3,0,1)*np.clip((11-dz)/3,0,1)
    approach=np.clip((ax-122)/3,0,1)*np.clip((140-ax)/3,0,1)*np.clip((6-dz)/2,0,1)
    mask=np.maximum(mask,np.maximum(yard,approach)*.90)
active=mask>0
soil=np.array([133.,119.,89.])
color[active]=np.rint(color[active]*(1-mask[active,None])+soil*mask[active,None]).astype(np.uint8)
control[:,:,0][active]=np.maximum(control[:,:,0][active],np.rint(mask[active]*235).astype(np.uint8))
control[:,:,1][active]=np.rint(control[:,:,1][active]*(1-mask[active])).astype(np.uint8)
# Broad, restrained grass/soil beds tie each tree pair to its existing house.
for side in [-1,1]:
    for z in [30,160,285]:
        oval=((X-side*195)/8.0)**2+((Z-(z+.5))/19.0)**2
        bed=np.clip((1.1-oval)/.35,0,1)*.30
        active=bed>0
        color[active]=np.rint(color[active]*(1-bed[active,None])+np.array([115.,111.,67.])*bed[active,None]).astype(np.uint8)
# Complete west court: a readable compacted-earth interior and grass edge,
# leaving a broad east entrance and a northeast circulation exit. Terrain unchanged.
def rect_mask(xmin,zmin,xmax,zmax,feather=1.0):
    return np.clip(np.minimum.reduce([X-xmin,xmax-X,Z-zmin,zmax-Z])/feather,0,1)
outer=rect_mask(-167.8,74.5,-135.4,115.5,1.6)
inner=rect_mask(-164.6,77.55,-138.6,112.45,.8)
edge=np.maximum(outer-inner,0)*.85
active=edge>0
color[active]=np.rint(color[active]*(1-edge[active,None])+np.array([88.,96.,58.])*edge[active,None]).astype(np.uint8)
# A darker neutral-brown yard contrasts with the original yellow grass in-engine.
yard=inner*.94
entry=rect_mask(-142,89,-122,101,1.2)*.86
north_exit=rect_mask(-147,108,-138.6,119,1.0)*.88
surf=np.maximum.reduce([yard,entry,north_exit]);active=surf>0
color[active]=np.rint(color[active]*(1-surf[active,None])+np.array([105.,98.,84.])*surf[active,None]).astype(np.uint8)
control[:,:,0][active]=np.maximum(control[:,:,0][active],np.rint(surf[active]*255).astype(np.uint8))
control[:,:,1][active]=np.rint(control[:,:,1][active]*(1-surf[active])).astype(np.uint8)
# Grouped tree-bed connects visually to the rear/north enclosure rather than
# duplicating isolated circles. No hedge geometry or foliage collision claim.
grove=np.maximum(np.clip(1-((X+173)/8)**2-((Z-104)/25)**2,0,1),np.clip(1-((X+165)/13)**2-((Z-122)/8)**2,0,1))*.65
active=grove>0
color[active]=np.rint(color[active]*(1-grove[active,None])+np.array([91.,102.,58.])*grove[active,None]).astype(np.uint8)
for name,data in [('land_color',color),('land_control',control)]:
    Image.fromarray(data).save(OUT/(name+'.png'),optimize=True)
receipt=copy.deepcopy(base_receipt)
receipt['detail_overlay']=ID
receipt['placements']=186
receipt['counts']={k:sum(p['kind'].startswith(k) for p in m['placements']) for k in ['house','barn','wall','tree','rock']}
for name in ['map.json','land_color.png','land_control.png']:receipt['generated_sha256'][name]=SHA(OUT/name)
(REVIEW/'generation_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
def batch_keys(rows):return {f"{p['kind']}_{math.floor(p['position'][0]/100)}_{math.floor(p['position'][2]/100)}" for p in rows}
a=batch_keys(m['placements'][:117]);b=batch_keys(m['placements'])
detail={'id':ID,'base_sha256':{p.name:SHA(p) for p in sorted(BASE.iterdir()) if p.name in ['map.json','land_color.png','land_control.png','generation_receipt.json']},
        'output_sha256':{p.name:SHA(p) for p in sorted(OUT.iterdir()) if p.name in ['map.json','land_color.png','land_control.png']},
        'height_preserved_sha256':SHA(ROOT/'assets/height_4m.f32'),
        'base_placements':117,'added_placements':69,'total_placements':186,
        'base_batches':len(a),'final_batches':len(b),'added_batches':len(b)-len(a),
        'added_full_detail_triangles':52*252+17*1116,'new_mesh_types':0,
        'ground_offset_range_m':[min(p['ground_offset_m'] for p in added),max(p['ground_offset_m'] for p in added)],
        'native_tested_by_generator':False,'gui_tested_by_generator':False}
(REVIEW/'detail_generation_receipt.json').write_text(json.dumps(detail,indent=2)+'\n')
print(json.dumps(detail,indent=2))
