#!/usr/bin/env python3
"""Build Ridgevale C1's original dry heightfield and semantic surface textures.
Reuses Cedar GLBs, collision descriptions, detail maps and shader READ-ONLY.
Requires Python 3, numpy, scipy, Pillow. Writes only ridgevale/assets and review.
Coordinates: metres, +Y up, row-major Z then X, little-endian float32.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, zoom

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--verify-rebuild", action="store_true", help="Build a second copy under ridgevale/review/rebuild_check without touching live assets")
args = parser.parse_args()
DEST = ROOT / "review/rebuild_check" if args.verify_rebuild else ROOT
OUT = DEST / "assets"
REVIEW = DEST / "review"
SEED = 20261020
N, STEP, ORIGIN = 1251, 4.0, -2500.0
SOURCE_ID = "ridgevale_5km_c1_20261020"
rng = np.random.default_rng(SEED)
OUT.mkdir(parents=True,exist_ok=True)
REVIEW.mkdir(parents=True,exist_ok=True)
cedar = json.loads((PROJECT / "cedar/assets/map.json").read_text())

roads = [
    {"id": "central_saddle", "width_m": 10.0,
     "points": [[0,-400],[0,-240],[0,-80],[0,100],[0,240],[0,400]],
     "profile_y": [8,9,13,20,17,11]},
    {"id": "west_flank", "width_m": 8.5,
     "points": [[0,-400],[-190,-345],[-315,-190],[-345,15],[-330,225],[-180,350],[0,400]],
     "profile_y": [8,14,23,28,24,17,11]},
    {"id": "east_flank", "width_m": 8.5,
     "points": [[0,-400],[195,-345],[325,-190],[355,20],[335,225],[185,350],[0,400]],
     "profile_y": [8,15,24,30,25,17,11]},
]
# No new scenery overlaps the existing deployment slots, covers or initial routes.
protected = [-120.0, -180.0, 120.0, 340.0]
buildings = []
for side in [-1, 1]:
    for j, z in enumerate([-35, 30, 95, 160, 225, 285]):
        i = len(buildings)
        x = side * (153 if j % 2 == 0 else 180)
        buildings.append({"id": f"house_{i:02d}", "kind": f"house_{i%3}",
                          "position": [x, 0, z], "yaw": 0.0 if side < 0 else math.pi,
                          "scale": 1.0, "collision": "solid_building"})
buildings.append({"id": "village_barn", "kind": "barn", "position": [-210,0,-110],
                  "yaw": 0.0, "scale": 1.0, "collision": "solid_building"})
fields = [(-245,-240,90,100,0), (242,-255,100,88,1), (-235,305,80,70,2),
          (235,300,75,74,0), (-66,-290,92,88,1), (65,345,70,60,2)]

def smooth01(v):
    v = np.clip(v, 0.0, 1.0)
    return v*v*(3.0-2.0*v)


def road_projection(x, z, road):
    shape = np.broadcast(x,z).shape
    distance = np.full(shape, 1e9, dtype=np.float32)
    target = np.zeros(shape, dtype=np.float32)
    for j, ((ax,az),(bx,bz)) in enumerate(zip(road["points"], road["points"][1:])):
        vx, vz = bx-ax, bz-az
        t = np.clip(((x-ax)*vx+(z-az)*vz)/(vx*vx+vz*vz), 0.0, 1.0)
        d = np.hypot(x-(ax+t*vx), z-(az+t*vz))
        use = d < distance
        target = np.where(use, road["profile_y"][j]*(1-t)+road["profile_y"][j+1]*t, target)
        distance = np.minimum(distance,d)
    return distance, target


def road_distance(x, z):
    return np.minimum.reduce([road_projection(x,z,r)[0] for r in roads])


def base_height(x,z):
    far = 10 + 5*np.sin(x/670)*np.cos(z/820) + 4*np.sin(z/900)
    for cx,cz,a,rx,rz in [(1200,950,125,650,510),(-1300,800,150,560,700),
                          (1400,-1250,170,680,580),(-1250,-1350,120,660,600),
                          (120,1800,110,750,550)]:
        far += a*np.exp(-(((x-cx)/rx)**2+((z-cz)/rz)**2))
    # Two dry rounded ridges with a lower saddle through the middle.
    local = 8 + 62*np.exp(-(((x+222)/108)**2+((z-80)/225)**2))
    local += 75*np.exp(-(((x-225)/115)**2+((z-90)/230)**2))
    local += 12*np.exp(-((x/190)**2+((z-90)/195)**2))
    blend = smooth01((np.hypot(x,z)-450)/450)
    h = local*(1-blend)+far*blend
    # Preserve the full battle footprint as a gently graded open saddle.
    corridor = smooth01((340-np.abs(x))/230) * smooth01((z+225)/45) * smooth01((345-z)/45)
    safe = 8 + 10*np.exp(-((z-95)/210)**2) + .002*x + .004*z
    return h*(1-corridor)+safe*corridor

axis = np.linspace(ORIGIN,-ORIGIN,N,dtype=np.float32)
X,Z = np.meshgrid(axis,axis)
H = base_height(X,Z).astype(np.float32)
# A continuous baked grading skirt means the road has no second collision owner.
# Main road is last so shared junctions have one deterministic surface.
for road in roads[1:]+roads[:1]:
    distance,target = road_projection(X,Z,road)
    weight = 1.0-smooth01((distance-road["width_m"]*.5-3.0)/23.0)
    H = H*(1-weight)+target*weight


def sample(x,z):
    fx = np.clip((np.asarray(x,dtype=np.float64)+2500)/4,0,N-1.000001)
    fz = np.clip((np.asarray(z,dtype=np.float64)+2500)/4,0,N-1.000001)
    ix,iz = fx.astype(int),fz.astype(int)
    tx,tz = fx-ix,fz-iz
    return H[iz,ix]*(1-tx)*(1-tz)+H[iz,ix+1]*tx*(1-tz)+H[iz+1,ix]*(1-tx)*tz+H[iz+1,ix+1]*tx*tz

# Solid shells have a flat footprint and a soft graded yard, never hidden terrain boxes.
for b in buildings:
    x,_,z = b["position"]
    y = float(sample(x,z))
    sx,sz = (12,16) if b["kind"] == "barn" else (10,12)
    w = 1-smooth01((np.maximum(np.abs(X-x)/sx,np.abs(Z-z)/sz)-1.0)/1.8)
    H = H*(1-w)+y*w
H = np.asarray(H,dtype="<f4")
H.tofile(OUT / "height_4m.f32")
for b in buildings:
    x,_,z = b["position"]
    b["position"][1] = float(sample(x,z))

# Procedural new land-color and control images using Cedar's coordinate/semantic contract.
S = 2048
a = np.linspace(-2500,2500,S,dtype=np.float32)
xx,zz = np.meshgrid(a,a)
noise = zoom(gaussian_filter(rng.random((256,256)),2.2),(8,8),order=1)[:S,:S]
noise = (noise-noise.mean()) / max(noise.std(),1e-9)
color = np.zeros((S,S,3),np.float32)
color[:] = [.48,.445,.30]
color += noise[:,:,None]*np.array([.020,.019,.012])
field_mask = np.zeros((S,S),np.float32)
for cx,cz,w,h,k in fields:
    m = (np.abs(xx-cx)<w*.5)&(np.abs(zz-cz)<h*.5)
    color[m] = np.asarray([[.58,.51,.32],[.455,.37,.255],[.52,.49,.335]][k])+noise[m,None]*.008
    field_mask[m] = (k+1)/3
rd = np.zeros_like(xx)
for road in roads:
    d,_ = road_projection(xx,zz,road)
    rd = np.maximum(rd,1-smooth01((d-road["width_m"]*.5)/2.5))
yards = np.zeros_like(rd)
for b in buildings:
    x,_,z = b["position"]
    sx,sz = (14,19) if b["kind"] == "barn" else (13,15)
    yards = np.maximum(yards,1-smooth01((np.maximum(abs(xx-x)/sx,abs(zz-z)/sz)-.8)/.55))
soil = np.maximum(rd,yards*.82)
color = color*(1-soil[:,:,None])+np.array([.48,.44,.34])*soil[:,:,None]
hs = sample(xx,zz)
gz,gx = np.gradient(hs,5000/(S-1))
rock = np.clip((np.hypot(gx,gz)-.30)/.40,0,.78)
color = color*(1-rock[:,:,None])+np.array([.52,.50,.43])*rock[:,:,None]
Image.fromarray(np.uint8(np.clip(color*255,0,255))).save(OUT/"land_color.png",optimize=True)
Image.fromarray(np.uint8(np.clip(np.stack([soil,field_mask,rock],axis=2)*255,0,255))).save(OUT/"land_control.png",optimize=True)

placements = list(buildings)

def clear_location(x,z,margin=7):
    if protected[0]-margin < x < protected[2]+margin and protected[1]-margin < z < protected[3]+margin:
        return False
    if float(road_distance(np.array(x),np.array(z))) < 13+margin:
        return False
    if any(abs(x-b["position"][0])<22+margin and abs(z-b["position"][2])<25+margin for b in buildings):
        return False
    if any(abs(x-p["position"][0])<margin+4 and abs(z-p["position"][2])<margin+4 for p in placements):
        return False
    return True

# Partial garden stone boundaries. Open ends and 16m+ gaps never form a closed road gate.
for side in [-1,1]:
    for group,z in enumerate([-73,72,208,322]):
        for j in range(6):
            x = side*(143+j*4.4)
            if not clear_location(x,z,1):
                continue
            placements.append({"id": f"wall_{side}_{group}_{j}", "kind":"wall_4m",
                               "position":[x,float(sample(x,z)),z], "yaw":0.0,
                               "scale":1.0,"collision":"solid_wall"})
# Sparse loose copses, not a forest screen. Keep outskirts open for the flanks.
for kind,count in [("tree",60),("rock",32)]:
    accepted = 0
    for attempt in range(12000):
        if accepted == count:
            break
        x,z = float(rng.uniform(-385,385)),float(rng.uniform(-370,370))
        margin = 8 if kind == "tree" else 5
        if not clear_location(x,z,margin):
            continue
        if kind == "tree" and any(abs(x-cx)<w*.5+3 and abs(z-cz)<h*.5+3 for cx,cz,w,h,k in fields):
            continue
        placements.append({"id":f"{kind}_{accepted:03d}","kind":f"{kind}_{accepted%3}",
                           "position":[x,float(sample(x,z)),z],"yaw":float(rng.uniform(0,math.tau)),
                           "scale":float(rng.uniform(.82,1.14) if kind=="tree" else rng.uniform(.75,1.35)),
                           "collision":"trunk" if kind=="tree" else "rock"})
        accepted += 1
    assert accepted == count, (kind,accepted)

used = sorted({p["kind"] for p in placements})
manifest = {
    "schema":"ridgevale-map-c1", "source_id":SOURCE_ID,"seed":SEED,
    "height_grid":{"n":N,"step_m":STEP,"origin_xz":[ORIGIN,ORIGIN],
                   "encoding":"little-endian-float32-row-major-zx","file":"height_4m.f32"},
    "world_extent_m":[5000,5000],"detailed_content_extent_m":[-400,-400,400,400],
    "protected_deployment_rectangle_xz":protected,
    "roads":roads,"fields":fields,"placements":placements,
    "colliders":{k:cedar["colliders"][k] for k in used},
    "asset_statistics":[s for s in cedar["asset_statistics"] if s["mesh"] in used],
    "asset_source":"res://cedar/assets/",
    "semantics":{"theme":"dry saddle village, no river or bridge", "houses":12,"barns":1,
                 "static_buildings":"solid opaque shells; not enterable or destructible",
                 "roads":"painted and baked graded terrain, no independent mesh or collider",
                 "terrain_owner":"modules/terrain_damage/streamed_battle_terrain.gd",
                 "no_actors_added":True,"combat_or_ai_changed":False,
                 "lod":"share existing imported Cedar Mesh resources, preserving their actual index LODs"}}
(OUT/"map.json").write_text(json.dumps(manifest,ensure_ascii=False,separators=(",",":"))+"\n")

route_receipts = []
for road in roads:
    max_grade, max_cross_grade = 0.0,0.0
    for p,q in zip(road["points"],road["points"][1:]):
        p,q=np.array(p),np.array(q)
        length=np.linalg.norm(q-p)
        t=np.linspace(0,1,math.ceil(length/2)+1)
        pts=p[None,:]+(q-p)[None,:]*t[:,None]
        forward=(q-p)/length
        side=np.array([-forward[1],forward[0]])
        y=sample(pts[:,0],pts[:,1])
        max_grade=max(max_grade,float(np.max(np.abs(np.diff(y)))/(length/(len(t)-1))))
        lo=pts-side*road["width_m"]*.5
        hi=pts+side*road["width_m"]*.5
        max_cross_grade=max(max_cross_grade,float(np.max(np.abs(sample(lo[:,0],lo[:,1])-sample(hi[:,0],hi[:,1])))/road["width_m"]))
    route_receipts.append({"id":road["id"],"max_longitudinal_grade":max_grade,"max_cross_grade":max_cross_grade})
    assert max_grade < .16 and max_cross_grade < .16, route_receipts[-1]
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
receipt = {"source_id":SOURCE_ID,"seed":SEED,"height_shape":[N,N],"height_bytes":H.nbytes,
           "height_min":float(H.min()),"height_max":float(H.max()),"finite":bool(np.isfinite(H).all()),
           "placements":len(placements),"counts":{k:sum(p["kind"].startswith(k) for p in placements) for k in ["house","barn","wall","tree","rock"]},
           "routes":route_receipts,"generated_sha256":{p.name:sha(p) for p in sorted(OUT.iterdir()) if p.suffix in [".f32",".png",".json"]},
           "reused_sha256":{f"cedar/assets/{k}.glb":sha(PROJECT/f"cedar/assets/{k}.glb") for k in used},
           "engine_tested_by_generator":False,"gui_tested_by_generator":False,"android_tested":False}
(REVIEW/"generation_receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
print(json.dumps(receipt,indent=2))
