#!/usr/bin/env python3
"""Read-only static/data validation; emits only ridgevale/review/static_contract.json."""
from pathlib import Path
import hashlib,json,math
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT.parent
failures=[]
checks=0
def check(ok,label):
    global checks
    checks+=1
    if not ok: failures.append(label)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((ROOT/'assets/map.json').read_text())
receipt=json.loads((ROOT/'review/generation_receipt.json').read_text())
h=np.fromfile(ROOT/'assets/height_4m.f32',dtype='<f4')
check(h.size==1251*1251,'1251 square grid')
check(np.isfinite(h).all(),'all heights finite')
check(manifest['height_grid']['step_m']==4 and manifest['world_extent_m']==[5000,5000],'5km/4m contract')
check(manifest['source_id']=='ridgevale_5km_c1_20261020','unique source identity')
for name,expected in receipt['generated_sha256'].items():
    check(sha(ROOT/'assets'/name)==expected,'generated data sha256 '+name)
for path,expected in receipt['reused_sha256'].items():
    check(sha(PROJECT/path)==expected,'reused original unchanged '+path)
for name in ['land_color','land_control']:
    image=Image.open(ROOT/'assets'/f'{name}.png')
    check(image.size==(2048,2048) and image.mode=='RGB','texture format '+name)
used={p['kind'] for p in manifest['placements']}
detail = manifest.get('detail_overlay', {}).get('id') == 'ridgevale_existing_village_detail_v2'
check(len(manifest['placements'])==(186 if detail else 117),'placement count')
check(sum(p['kind'].startswith('house') for p in manifest['placements'])==12,'12 houses')
check(sum(p['kind']=='barn' for p in manifest['placements'])==1,'1 barn')
check(len({p['id'] for p in manifest['placements']})==len(manifest['placements']),'unique IDs')
stats={s['mesh']:s for s in manifest['asset_statistics']}
min_boundary_clearance=math.inf
for p in manifest['placements']:
    x,y,z=p['position']
    check(all(math.isfinite(v) for v in [x,y,z,p['yaw'],p['scale']]),'finite pose '+p['id'])
    check(-400<=x<=400 and -400<=z<=400,'authored footprint '+p['id'])
    check(p['kind'] in manifest['colliders'] and p['kind'] in stats,'mesh+collider contract '+p['id'])
    low,high=stats[p['kind']]['bounds']
    # Test the conservative whole-render-mesh AABB footprint, not only centers/trunks.
    corners=[]
    for lx in [low[0],high[0]]:
        for lz in [low[2],high[2]]:
            lx*=p['scale'];lz*=p['scale']
            corners.append((x+math.cos(p['yaw'])*lx+math.sin(p['yaw'])*lz,
                            z-math.sin(p['yaw'])*lx+math.cos(p['yaw'])*lz))
    xmin,xmax=min(c[0] for c in corners),max(c[0] for c in corners)
    zmin,zmax=min(c[1] for c in corners),max(c[1] for c in corners)
    protected=manifest['protected_deployment_rectangle_xz']
    overlaps=(xmin<protected[2] and xmax>protected[0] and zmin<protected[3] and zmax>protected[1])
    check(not overlaps,'entire scenery footprint outside protected deployment '+p['id'])
for route in receipt['routes']:
    check(route['max_longitudinal_grade']<.16,'graded route '+route['id'])
    check(route['max_cross_grade']<.16,'graded route crossfall '+route['id'])
for path in ['heightfield.gd','terrain.gd','world.gd']:
    s=(ROOT/path).read_text()
    check('rivergate' not in s.lower(),'independent dry source '+path)
terrain=(ROOT/'terrain.gd').read_text()
check(terrain.startswith('extends "res://modules/terrain_damage/streamed_battle_terrain.gd"'),'original streaming owner retained')
check('func sample_height(' not in terrain,'no secondary support override')
world=(ROOT/'world.gd').read_text()
check('res://cedar/assets/' in world and 'mesh_node.mesh' in world,'reuse existing imported mesh preserving LOD')
check('func _build_bridge' not in world and 'water.gd' not in world,'no bridge/water')
check('Support.fit(host,tank,true)' in (ROOT/'tests/test_ridgevale_native.gd').read_text(),'native test uses production rigid support')
report={'test':'ridgevale_static_contract','ok':not failures,'checks':checks,'failures':failures,
        'scope':'Static numerical and conservative AABB checks only. Not GUI, native physics, gameplay or FPS evidence.'}
(ROOT/'review/static_contract.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
raise SystemExit(0 if not failures else 1)
