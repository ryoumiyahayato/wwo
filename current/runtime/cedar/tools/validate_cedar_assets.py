#!/usr/bin/env python3
"""Static geometry/data audit only. This does NOT compile or execute Godot.
Requires numpy, Pillow, trimesh. Optional --baseline path for byte comparisons.
"""
from __future__ import annotations
import argparse, collections, hashlib, json, math, re, struct, sys
from pathlib import Path
import numpy as np
from PIL import Image
import trimesh

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'cedar' / 'assets'

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--out', type=Path, default=ROOT/'cedar/review/static_checks.json')
    opts = parser.parse_args()
    checks: list[dict] = []
    def check(name: str, condition: bool, detail=None):
        checks.append({'name': name, 'ok': bool(condition), 'detail': detail})
    data = json.loads((ASSETS/'map.json').read_text())
    grid = np.fromfile(ASSETS/'height_4m.f32', '<f4')
    check('height_byte_count', grid.size == 1251**2)
    check('finite_height_values', np.isfinite(grid).all())
    grid=grid.reshape(1251,1251)
    check('height_enclosed_by_new_world_bounds', grid.min() >= -200 and grid.max() <= 400, [float(grid.min()),float(grid.max())])
    def sample(x, z):
        fx=np.clip((np.asarray(x)+2500)/4,0,1249.999999)
        fz=np.clip((np.asarray(z)+2500)/4,0,1249.999999)
        ix=fx.astype(np.int64); iz=fz.astype(np.int64); a=fx-ix; b=fz-iz
        return grid[iz,ix]*(1-a)*(1-b)+grid[iz,ix+1]*a*(1-b)+grid[iz+1,ix]*(1-a)*b+grid[iz+1,ix+1]*a*b
    ids = [p['id'] for p in data['placements']]
    check('unique_static_ids', len(ids)==len(set(ids)), len(ids))
    check('declared_extent', data['world_extent_m']==[5000,5000])
    counts=collections.Counter(p['kind'] for p in data['placements'])
    check('expected_placement_count',len(ids)==370,dict(counts))
    check('collider_reference_for_every_placement',all(p['kind'] in data['colliders'] for p in data['placements']))
    check('no_new_prop_origin_inside_preserved_deployment_corridor',all(not(-100<p['position'][0]<80 and -160<p['position'][2]<290) for p in data['placements']))
    check('all_placement_values_finite',all(np.isfinite([*p['position'],p['yaw'],p['scale']]).all() and p['scale']>0 for p in data['placements']))
    stats=[]
    for entry in data['asset_statistics']:
        path=ASSETS/(entry['mesh']+'.glb');raw=path.read_bytes()
        magic,ver,size=struct.unpack_from('<4sII',raw,0)
        check('glb_header_'+entry['mesh'],magic==b'glTF' and ver==2 and size==len(raw))
        ln,typ=struct.unpack_from('<II',raw,12);desc=json.loads(raw[20:20+ln])
        check('self_contained_'+entry['mesh'],all('uri' not in b for b in desc.get('buffers',[])) and all('uri' not in t for t in desc.get('images',[])))
        scene=trimesh.load(path,force='scene')
        meshes=list(scene.geometry.values()); triangles=sum(len(m.faces) for m in meshes)
        check('finite_valid_geometry_'+entry['mesh'],bool(meshes) and all(np.isfinite(m.vertices).all() and len(m.faces)>0 and m.faces.min()>=0 and m.faces.max()<len(m.vertices) for m in meshes))
        check('recorded_triangle_count_'+entry['mesh'],triangles==entry['triangles'],triangles)
        stats.append({'asset':path.name,'triangles':triangles,'bytes':len(raw),'sha256':digest(path),'surfaces':sum(len(m['primitives']) for m in desc['meshes'])})
    for name,wh in [('land_color.png',(2048,2048)),('land_control.png',(2048,2048)),('grass_detail.png',(512,512)),('soil_detail.png',(512,512)),('stone_detail.png',(512,512))]:
        with Image.open(ASSETS/name) as im:check('texture_'+name,im.size==wh)
    for kind,spec in data['colliders'].items():
        condition=spec['shape'] in ('box','compound','cylinder','convex_visual')
        for box in spec.get('boxes',[]):condition &= all(float(v)>0 for v in box['size']) and np.isfinite(box['center']).all()
        for convex in spec.get('convex',[]):condition &= len(convex)>=4 and np.isfinite(convex).all()
        if spec['shape']=='cylinder':condition &= spec['radius']>0 and spec['height']>0
        check('collider_descriptor_'+kind,condition)
    # Source-level and numerical checks are not a replacement for physical ray tests.
    gd=(ROOT/'cedar/terrain.gd').read_text()
    check('detailed_mesh_uses_inherited_grid', 'super._make_mesh(ox, oz, cells, step, true)' in gd)
    check('separate_map_source_id','source_id = "cedar_valley_20261019_v1"' in gd)
    road_metrics=[]
    for idx,line in enumerate(data['roads']):
        distances=[];grades=[]
        for a,b in zip(line,line[1:]):
            a=np.array(a);b=np.array(b);length=np.linalg.norm(b-a)
            t=np.linspace(0,1,max(2,math.ceil(length/2)+1));p=a+(b-a)*t[:,None]
            y=sample(p[:,0],p[:,1]); grades.extend((np.abs(np.diff(y))/(length/(len(t)-1))).tolist());distances.append(length)
        road_metrics.append({'road':idx,'polyline_length_m':sum(distances),'maximum_sampled_grade':max(grades),'note':'Numerical source-height audit; NOT actual vehicle driving.'})
    check('roads_finite',all(np.isfinite([v['polyline_length_m'],v['maximum_sampled_grade']]).all() for v in road_metrics))
    changed=[];core=[]
    if opts.baseline:
        for path in sorted((ROOT/'scripts').rglob('*.gd'))+sorted((ROOT/'modules').rglob('*.gd')):
            rel=path.relative_to(ROOT);base=opts.baseline/rel
            if base.exists():
                equal=path.read_bytes()==base.read_bytes();core.append({'path':str(rel),'same':equal})
                if not equal:changed.append(str(rel))
        allowed={'scripts/main.gd','scripts/smoke_cloud.gd','modules/ai_armor/vehicle_damage_feedback.gd'}
        check('existing_runtime_change_allowlist',set(changed)<=allowed,changed)
        for rel in ['scripts/mobile_battle.gd','scripts/combat_effects.gd','scripts/vehicle_contact_resolver.gd','modules/vehicle_ammo/vehicle_ammo.gd','modules/vehicle_ammo/ammo_config.gd','modules/vehicle_fire_control/gunner_intent.gd','modules/infantry_ai/infantry_host.gd','modules/infantry_ai/infantry_actor.gd','modules/vehicle_crew/vehicle_crew_host.gd','modules/terrain_damage/streamed_battle_terrain.gd']:
            check('unchanged_'+rel,(ROOT/rel).read_bytes()==(opts.baseline/rel).read_bytes())
    result={'status':'STATIC_PASS' if all(c['ok'] for c in checks) else 'STATIC_FAIL','check_count':len(checks),'checks':checks,'asset_statistics':stats,'road_metrics':road_metrics,'existing_runtime_comparison':core,'engine_compile':'NOT_RUN','engine_render':'NOT_RUN','physics_runtime':'NOT_RUN','android':'NOT_TESTED','apk':'NOT_BUILT'}
    opts.out.parent.mkdir(parents=True,exist_ok=True);opts.out.write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print(json.dumps({'status':result['status'],'checks':len(checks),'failed':[c for c in checks if not c['ok']], 'roads':road_metrics},ensure_ascii=False,indent=2))
    return 0 if result['status']=='STATIC_PASS' else 1
if __name__=='__main__':sys.exit(main())
