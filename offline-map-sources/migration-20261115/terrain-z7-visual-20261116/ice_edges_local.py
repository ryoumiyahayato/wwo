from contextlib import ExitStack
from pathlib import Path
import json
import math
import runpy

import numpy as np
from PIL import Image
from pyproj import Transformer


STAGE = Path(__file__).resolve().parent
MIGRATION = STAGE.parent
Z7 = MIGRATION / 'terrain-z7-detail-20261116'
BASE = MIGRATION / 'terrain-quality-20261115/recovered-candidate/worldcrs84quad-15s-v2'
SOURCE = Z7 / 'scar-add-7.13-antarctic-surfaces.json'
HOST = MIGRATION.parents[1] / 'wwo-character-integration/rust/strategic-host'
STEP = 360 / (256 * 256)
EARTH = 6371008.8
ICE = np.array([215, 226, 229], dtype=np.float32)
PICKS = {
    'ross-shelf': [(700, 237), (713, 358), (898, 528)],
    'ross-front': [(902, 233), (925, 246), (947, 252), (976, 241)],
    'ronne-shelf': [(111, 379), (85, 492), (685, 116), (898, 9), (869, 20), (844, 30)],
    'amery-shelf': [(312, 394), (240, 540), (797, 248), (440, 154)],
}


def geographic(receipt, px, py):
    w, h = receipt['viewport']
    mpp = receipt['mpp']
    east, north, center = np.array(receipt['orientation'])
    x = (px + .5 - w / 2) * mpp / EARTH
    y = (h / 2 - py - .5) * mpp / EARTH
    r = math.hypot(x, y)
    a = r if receipt['projection'] == 'azimuthal_equidistant' else math.asin(r)
    v = (x * east + y * north) * (math.sin(a) / r if r else 1) + center * math.cos(a)
    return math.degrees(math.atan2(v[0], v[2])), math.degrees(math.atan2(v[1], math.hypot(v[0], v[2])))


def mode(byte):
    return (int(byte) & -int(byte)).bit_length() - 1


def source_records(n):
    floating, grounded = [], []
    for feature in json.loads(SOURCE.read_text('utf-8'))['features']:
        attrs = feature['attributes']
        category = attrs['surface']
        if category not in ('ice shelf','ice tongue','land','rumple'):
            continue
        points, offsets = [], []
        for ring in feature['geometry']['rings']:
            offsets.append(len(points))
            points.extend(ring)
        poly = n['shape'](n['shapefile'].Shape(shapeType=5,points=points,parts=offsets).__geo_interface__)
        if not poly.is_valid:
            poly = n['make_valid'](poly)
        (grounded if category in ('land','rumple') else floating).append((attrs,poly))
    return [(entries,n['STRtree']([poly for _,poly in entries])) for entries in (floating,grounded)]


def source_position(position, trees, polys):
    from shapely.geometry import Point

    point = Point(*position)
    description = {}
    for label, (entries, tree) in zip(('raw_floating','raw_grounded'),trees):
        record, polygon = entries[tree.nearest(point)]
        description[label] = dict(fid=record['FID'],kind=record['surface'],inside=polygon.covers(point),
                                  geometry_m=round(point.distance(polygon),1),
                                  edge_m=round(point.distance(polygon.boundary),1))
    shape = polys.geometries[polys.nearest(point)]
    description['combined'] = dict(inside=shape.covers(point),geometry_m=round(point.distance(shape),1))
    return description


def pixel_coverage(gx, gy, polygons, projection, subdivisions):
    from shapely import box, intersects_xy

    fractions = (np.arange(subdivisions)+.5)/subdivisions
    lon = ((gx+fractions) % 65536)*STEP-180
    lat = 90-(gy+fractions)*STEP
    east, north = projection.transform(*np.meshgrid(lon,lat))
    selected = polygons.geometries.take(polygons.query(box(east.min(),north.min(),east.max(),north.max())))
    inside = np.zeros((subdivisions,subdivisions),dtype=bool)
    for polygon in selected:
        inside |= intersects_xy(polygon,east,north)
    return float(inside.mean())


def unpack(pack, x, y):
    blocks, z = pack.at(x, y)
    raw = blocks.tobytes()
    pixels = np.array(Image.frombytes('RGBA', (264, 264), raw, 'bcn', (7, 'BC7')))
    return pixels, z, np.frombuffer(raw, dtype=np.uint8).reshape(66, 66, 16)


def encode_proposal(n, old_bc7, original, rgb, amount):
    itc = n['ispc_texcomp']
    opaque = itc.BC7EncSettings.from_profile('fast')
    target = original.copy()
    target[..., :3] = rgb
    new_raw = itc.compress_blocks_bc7(itc.RGBASurface(target.tobytes(),264,264), n['ENCODER'])
    decoded = np.array(Image.frombytes('RGBA',(264,264),new_raw,'bcn',(7,'BC7')))
    alpha_mismatch = (target[...,3] != decoded[...,3]).reshape(66,4,66,4).any(axis=(1,3))
    updated = amount.reshape(66,4,66,4).any(axis=(1,3))
    proposed = old_bc7.copy()
    proposed[updated] = np.frombuffer(new_raw,dtype=np.uint8).reshape(66,66,16)[updated]
    for row, col in zip(*np.nonzero(updated & alpha_mismatch)):
        block = n['recolor_bc7_preserving_alpha'](old_bc7[row,col].tobytes(),
                                                 target[4*row:4*(row+1),4*col:4*(col+1)], opaque)
        proposed[row,col] = np.frombuffer(block, dtype=np.uint8)
    decoded = np.array(Image.frombytes('RGBA',(264,264),proposed.tobytes(),'bcn',(7,'BC7')))
    if not np.array_equal(decoded[...,3], original[...,3]):
        raise ValueError('Proposal failed to preserve original decoded alpha')
    return decoded


def describe_area(namespaces, old_pack, new_pack, x, y, polygons, proj):
    old, height, old_bc7 = unpack(old_pack, x, y)
    new, _, new_bc7 = unpack(new_pack, x, y)
    votes = namespaces['floating_ice_coverage'](polygons, proj, 256, 128, x, y)
    if votes is None:
        votes = np.zeros((264, 264), dtype=np.uint8)
    alpha = old[..., 3] / 255
    covered = votes / 4
    amount = alpha * covered
    base = old[..., :3].astype(float)
    current = new[..., :3].astype(float)
    legacy_target = np.rint(base+(ICE-base)*amount[..., None])
    depth = np.clip(-height.astype(float) / 5100, 0, 1)**.43
    ocean = 255 * (np.array([.17,.32,.38]) - depth[..., None] * np.array([.092,.128,.122]))
    water_color = np.where((alpha == 1)[..., None], base, ocean)
    corrected = np.rint(np.clip(base + (ICE-water_color)*amount[..., None], 0, 255))
    corrected_encoded = encode_proposal(namespaces, old_bc7, old, corrected, amount)
    mixed = (votes == 4) & (alpha > 0) & (alpha < 1)
    sample = dict(alpha_pixels_changed=int(np.count_nonzero(old[..., 3] != new[..., 3])),
                  alpha_max_delta=int(np.abs(old[...,3].astype(int)-new[...,3]).max()),
                  encoded_blocks_changed=int(np.any(old_bc7 != new_bc7, axis=2).sum()),
                  fully_covered_partial_alpha_pixels=int(mixed.sum()),
                  proposed_alpha_pixels_changed=int(np.count_nonzero(old[..., 3] != corrected_encoded[..., 3])))
    if mixed.any():
        pure_open = (votes == 0) & (alpha == 1)
        sample.update(current_vs_legacy_recipe_rgb_mae=float(np.abs(current[mixed]-legacy_target[mixed]).mean()),
                      corrected_vs_legacy_recipe_rgb_mae=float(np.abs(corrected[mixed]-legacy_target[mixed]).mean()),
                      current_vs_corrected_recipe_rgb_mae=float(np.abs(current[mixed]-corrected[mixed]).mean()),
                      proposed_vs_corrected_recipe_rgb_mae=float(np.abs(corrected_encoded[..., :3][mixed]-corrected[mixed]).mean()),
                      open_water_channel_mae=float(np.abs(corrected_encoded[..., :3][pure_open] - base[pure_open]).mean()) if pure_open.any() else None)
    return dict(old=old, new=new, legacy_target=legacy_target, corrected_rgb=corrected,
                corrected_encoded=corrected_encoded, old_bc7=old_bc7, new_bc7=new_bc7,
                votes=votes, height=height, sum=sample)


def around(area, x, y, tx, ty):
    out = []
    for yy in range(max(0, ty-1), min(264, ty+2)):
        for xx in range(max(0, tx-1), min(264, tx+2)):
            layer = {k: np.atleast_1d(area[k][yy,xx]).astype(int).tolist()
                     for k in ('old','new','legacy_target','corrected_rgb','corrected_encoded','votes','height')}
            for k in ('old_bc7','new_bc7'):
                layer[k+'_mode'] = mode(area[k][yy//4,xx//4,0])
            out.append(dict(xy=[xx,yy], global_xy=[256*x-4+xx,256*y-4+yy], **layer))
    return out


def main():
    n = runpy.run_path(str(HOST / 'tools/build_natural_terrain.py'))
    polygons = n['ice_shelf_polygons'](SOURCE)
    raw_shapes = source_records(n)
    proj = Transformer.from_crs(4326, 3031, always_xy=True)
    report, tiles = {}, {}
    with ExitStack() as stack:
        old, new = [n['LevelPack'](stack.enter_context((p / '7.qpk').open('rb')), 7, n['COMPACT_VERSION'])
                    for p in (BASE, Z7 / 'candidate-final')]
        for name, positions in PICKS.items():
            receipt = json.loads((Z7 / 'final-stills' / f'{name}.json').read_text('utf-8'))['state']
            screen = Image.open(Z7 / 'final-stills' / f'{name}.png')
            snapshots = []
            for px,py in positions:
                lon, lat = geographic(receipt, px, py)
                gx, gy = int((lon+180)/STEP), int((90-lat)/STEP)
                x, tx = divmod(gx, 256)
                y, ty = divmod(gy, 256)
                if (x,y) not in tiles:
                    tiles[x,y] = describe_area(n, old, new, x, y, polygons, proj)
                texels = around(tiles[x,y],x,y,tx+4,ty+4)
                for item in texels:
                    mx,my = item['global_xy']
                    item['coverage_integral'] = [pixel_coverage(mx,my,polygons,proj,grid) for grid in (2,4,32)]
                snapshots.append(dict(screen_xy=[px,py], screen_rgb=screen.getpixel((px,py)),
                                      geographic=[lon,lat], tile=[7,x,y], texel=[tx+4,ty+4],
                                      source_position=source_position(proj.transform(lon,lat),raw_shapes,polygons),
                                      nearby=texels))
            report[name] = snapshots
    output = dict(tiles={f'7/{x}/{y}': t['sum'] for (x,y), t in tiles.items()}, samples=report)
    (STAGE / 'ice-edges-local.json').write_text(json.dumps(output, indent=2), encoding='utf-8')
    for name, snapshots in report.items():
        for sample in snapshots:
            print(name, sample['screen_xy'], sample['screen_rgb'], sample['tile'],
                  sample['texel'], [round(k,5) for k in sample['geographic']],sample['source_position'])
            center = next(p for p in sample['nearby'] if p['xy']==sample['texel'])
            print('  ', center['coverage_integral'],center['old'],center['new'],center['corrected_encoded'])
    for name, snapshots in report.items():
        pixels = {tuple(p['global_xy']):p['coverage_integral'] for s in snapshots for p in s['nearby']}
        mixed = np.array([v for v in pixels.values() if 0 < v[-1] < 1])
        if mixed.size:
            error = np.abs(mixed[:,:2]-mixed[:,2:])
            print(name,'edge cells',len(mixed),'coverage MAE for 2x2,4x4',error.mean(axis=0),
                  'improved',int((error[:,1]<error[:,0]).sum()),'worsened',int((error[:,1]>error[:,0]).sum()))


if __name__ == '__main__':
    main()
