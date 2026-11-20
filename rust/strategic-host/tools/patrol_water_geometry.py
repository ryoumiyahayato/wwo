"""Index the whole shoreline and capture its regions in the normal game."""
import argparse
from collections import Counter
from functools import lru_cache
import json
import math
from pathlib import Path
from tempfile import TemporaryDirectory
import time

import numpy as np
from PIL import Image
from shapely.geometry import LineString, box
from shapely.strtree import STRtree

from build_natural_terrain import (WATER_COLUMNS, WATER_GRID, WATER_ROWS,
                                   WATER_STEP, WATER_QUANTIZATION, polygon_parts, shoreline_sources,
                                   water_class, water_pack_index, water_payload_cells)
from capture_z7_pages import (EARTH, WIDTH, HEIGHT, Observer, at_camera, bounds, dot, geographic,
                              png_size, read, vector, write)


def shore_sections(source, ponds):
    levels = []
    sections = []
    edges = Counter()
    for level, geometry in shoreline_sources(source,ponds):
        for polygon in polygon_parts(geometry):
            for ring in (polygon.exterior, *polygon.interiors):
                points = np.asarray(ring.coords)
                if np.any(np.abs(np.diff(points[:, 0])) > 180):
                    raise ValueError('Patrol index requires dateline-split GSHHG')
                # Short runs keep the geographic index local even for continents.
                for i in range(0, len(points)-1, 96):
                    part = points[i:i+97]
                    if not np.any(np.diff(part, axis=0)):
                        continue
                    sections.append(LineString(part))
                    levels.append(level)
                    edges[level] += len(part)-1
    return STRtree(sections), np.asarray(levels), edges


def river_cells(kind, payload):
    if kind:
        return []
    step = WATER_STEP/WATER_GRID
    cells = water_payload_cells(kind, payload)
    return [(i % WATER_GRID*step, i // WATER_GRID*step)
            for i, cell in enumerate(cells)
            if not isinstance(cell, int) and any((band[:, 2] >= 16).any() for band in cell[1])]


def view_radius(rect):
    w, s, e, n = rect
    center = vector((w+e)/2, (s+n)/2)
    return EARTH*max(math.acos(max(-1., min(1., dot(center, vector(lon, lat)))))
                     for lon in (w, e) for lat in (s, n))


def view_record(key, z, rect, levels, vertices, observed):
    w, s, e, n = rect
    lat = (s+n)/2
    projected = math.pi*EARTH/256*math.hypot(1, math.cos(math.radians(lat)))/math.sqrt(2)
    mpp = projected/2**z if z < 7 else max(25, view_radius(rect)/237)
    return dict(key=key, z=z, rect=rect, lon=(w+e)/2, lat=lat, mpp=mpp,
                gshhg_levels=sorted(levels), vertices=vertices, measured_water_cells=observed)


def near_views(key, rect, fragments, river_rects, depth=0):
    w, s, e, n = rect
    window = box(*rect)
    fragments = [(level, line.intersection(window)) for level, line in fragments]
    fragments = [(level, line) for level, line in fragments if line.length > 0]
    river_rects = [river for river in river_rects if river.intersection(window).area > 0]
    if not fragments and not river_rects:
        return
    lengths = [line.length for _, line in fragments]
    vertices = sum(len(_line.coords) for _, line in fragments for _line in line_parts(line))
    complex_shore = vertices > (400, 650, 1400)[min(depth, 2)] or sum(lengths) > (n-s)*(3+4*depth)
    dense_channels = depth == 0 and len(river_rects) > 24
    if depth < 3 and (complex_shore or dense_channels):
        mx, my = (w+e)/2, (s+n)/2
        for i, part in enumerate(((w,s,mx,my),(mx,s,e,my),(w,my,mx,n),(mx,my,e,n))):
            yield from near_views(key+str(i), part, fragments, river_rects, depth+1)
        return
    yield view_record(key, 7, rect, {level for level, _ in fragments}, vertices, len(river_rects))


def line_parts(line):
    if line.geom_type == 'LineString':
        yield line
    elif hasattr(line, 'geoms'):
        for part in line.geoms:
            yield from line_parts(part)


def build_plan(args):
    tree, levels, edges = shore_sections(args.shoreline,args.shoreline_ponds)
    coarse = {}
    near = []
    with args.qwg.open('rb') as source:
        offsets, classes = water_pack_index(source)
        for y in range(WATER_ROWS):
            for x in range(WATER_COLUMNS):
                rect = bounds(x,y)
                page = y*WATER_COLUMNS+x
                start, end = map(int, offsets[page:page+2])
                source.seek(start)
                observed = river_cells(classes[page], source.read(end-start))
                w,s,_,_ = rect
                step = WATER_STEP/WATER_GRID
                river_rects = [box(w+dx,s+dy,w+dx+step,s+dy+step) for dx,dy in observed]
                fragments = [(int(levels[i]), tree.geometries[i])
                             for i in tree.query(box(*rect), predicate='intersects')]
                views = list(near_views(f'7-{x}-{y}-', rect, fragments, river_rects))
                if not views:
                    continue
                near.extend(views)
                for z in (4,5,6):
                    shift = 7-z
                    key = (z,x >> shift,y >> shift)
                    covered = coarse.setdefault(key, [set(),0,0])
                    for view in views:
                        covered[0].update(view['gshhg_levels'])
                    covered[1] += sum(view['vertices'] for view in views)
                    covered[2] += len(observed)
    result = []
    for (z,x,y), (covered,vertices,observed) in sorted(coarse.items()):
        step = 360/(2 << z)
        west,north = -180+x*step,90-y*step
        result.append(view_record(f'{z}-{x}-{y}',z,(west,north-step,west+step,north),
                                  covered,vertices,observed))
    result.extend(near)
    write(args.plan, dict(shoreline=str(args.shoreline.resolve()), qwg=str(args.qwg.resolve()),
                          shoreline_ponds=str(args.shoreline_ponds.resolve()) if args.shoreline_ponds else None,
                          gshhg_edges=edges, views=result))
    print(dict(sorted(Counter(view['z'] for view in result).items())), flush=True)


def ready(state, view):
    terrain = state.get('terrain')
    if not terrain or not terrain['selected_ready'] or state['mode'] != 'geographic':
        return False
    return (terrain['water_geometry_buffer_bytes'] > 0
            and terrain['water_geometry_view_resident'] == terrain['water_geometry_view_wanted']
            and at_camera(state, view['lon'], view['lat'], view['mpp']))


class WaterProbes:
    def __init__(self, source):
        self.source = source
        self.offsets, self.classes = water_pack_index(source)

    @lru_cache(maxsize=32)
    def page(self, number):
        start, end = map(int, self.offsets[number:number+2])
        self.source.seek(start)
        return water_payload_cells(self.classes[number],self.source.read(end-start))

    def area(self, lon, lat):
        x = ((lon+180) % 360)/WATER_STEP
        y = min(np.nextafter(float(WATER_ROWS),0), (90-lat)/WATER_STEP)
        page_x, page_y = int(x), int(y)
        local_x = x-page_x
        local_y = min(np.nextafter(1.,0.), 1-(y-page_y))
        cx, cy = int(local_x*WATER_GRID), int(local_y*WATER_GRID)
        cell = self.page(page_y*WATER_COLUMNS+page_x)[cy*WATER_GRID+cx]
        if isinstance(cell,int):
            return cell
        bits,bands = cell
        edges = bands[int(local_y*64) % 8]
        px,py = local_x*WATER_QUANTIZATION, local_y*WATER_QUANTIZATION
        for a,b,flag in edges.tolist():
            ay,by = a >> 16,b >> 16
            if ay <= py < by:
                ax,bx = a & 65535,b & 65535
                if px < ax+(bx-ax)*(py-ay)/(by-ay):
                    bits ^= flag
        return water_class(bits)

    def review(self, image, state, admitted):
        # At wider scales the game mixes or replaces QWG with the base map.
        mpp = state['mpp']
        if not admitted or mpp > 2600 or state['viewport'] != [WIDTH,HEIGHT]:
            return {'status':'geometry_color_check_unavailable'}
        pixels = np.asarray(image)
        axes = state['orientation']
        compared = Counter()
        suspect = []
        for dy in range(-220,221,44):
            for dx in range(-220,221,44):
                if dx*dx+dy*dy > 250**2:
                    continue
                x,y = WIDTH//2+dx,HEIGHT//2+dy
                ll = geographic(x+.5,y+.5,axes,mpp,0)
                water = self.area(*ll) > 1
                offsets = ((x-3,y),(x+3,y),(x,y-3),(x,y+3))
                if any((self.area(*geographic(a+.5,b+.5,axes,mpp,0)) > 1) != water
                       for a,b in offsets):
                    continue
                r,g,b = np.median(pixels[y-2:y+3,x-2:x+3,:3],axis=(0,1))
                # Only classify clear blue water and clear green/earth land.
                # Snow, ice, muted tints and other colors need visual review.
                blue = b > g+4 and g > r+12
                ground = g > b+8 or r > b+10
                compared['stable_probes'] += 1
                if not blue and not ground:
                    compared['ambiguous_color'] += 1
                elif (water and ground) or (not water and blue):
                    suspect.append([x,y,'expected_water' if water else 'expected_land'])
        return dict(status='check_suspect_pixels' if suspect else 'no_clear_sample_mismatch',
                    counts=compared,suspect=suspect)


def capture_view(host, view, scratch, directory, probes):
    host.ask('focus', lon=view['lon'], lat=view['lat'], mpp=view['mpp'], value='north')
    deadline = time.monotonic()+6
    state = host.ask('status')['state']
    while not ready(state, view) and time.monotonic() < deadline:
        state = host.ask('status')['state']
    frame = host.ask('capture', label='patrol', value='terrain-samples')
    img = scratch/'patrol.png'
    if png_size(img) != tuple(frame['state']['viewport']):
        raise RuntimeError('Missing patrol capture from game')
    state = frame['state']
    terrain = state['terrain']
    sample = frame['extra']['terrain_samples']['samples'][0]['terrain']
    contributors = sample['contributors']
    level_confirmed = (terrain['target_level'] == view['z'] and
                       sum(weight for page,weight in contributors if page and page[0] == view['z']) >= .99)
    rect_covered = (view_radius(view['rect']) <= 265*state['mpp']
                    and min(state['viewport']) >= 2*265)
    admitted = ready(state,view)
    label = view['key']
    with Image.open(img) as image:
        image = image.convert('RGB')
        diagnostics = probes.review(image,state,admitted)
        image.save(directory/f'{label}.jpg', quality=82)
    img.unlink()
    return dict(key=label, image=f'{label}.jpg', state=state,
                samples=frame['extra']['terrain_samples']['samples'],
                rect_covered=admitted and rect_covered, level_confirmed=level_confirmed,
                color_probes=diagnostics,
                status=('captured_review_pending' if admitted and rect_covered and level_confirmed
                        else 'capture_has_fallback_or_gap'))


def patrol(args):
    plan = read(args.plan)
    data = args.data if args.data is not None else args.exe.resolve().parent/'data'
    terrain = args.terrain_candidate if args.terrain_candidate is not None else data/'worldcrs84quad-15s-v2-hydrology'
    qwg = terrain/'water-geometry.qwg'
    if not qwg.samefile(plan['qwg']):
        raise ValueError('The game and patrol index must use the same QWG')
    args.output.mkdir(parents=True,exist_ok=True)
    log = args.output/'patrol.jsonl'
    binding = args.output/'run.json'
    files = [args.exe.resolve(), args.plan.resolve(), qwg.resolve()]
    inventory = {}
    for path in files:
        details = path.stat()
        inventory[str(path)] = [details.st_size, details.st_mtime_ns]
    if binding.exists():
        if read(binding) != inventory:
            raise ValueError('Use a new output directory when the game or patrol input changes')
    elif log.exists() and log.stat().st_size:
        raise ValueError('Existing patrol receipts are missing their game and input records')
    else:
        write(binding, inventory)
    received = {}
    if log.exists():
        for line in log.read_text(encoding='utf-8').splitlines():
            record = json.loads(line)
            received[record['key']] = record
    views = [view for view in plan['views']
             if (args.z is None or view['z'] == args.z)
             and (view['key'] not in received or
                  received[view['key']]['status'] != 'captured_review_pending' or
                  not (args.output/received[view['key']]['image']).is_file())]
    if not views:
        return
    # PNGs live only until the corresponding persistent review image is written.
    with TemporaryDirectory(dir=args.output,prefix='capture-') as temporary:
        scratch = Path(temporary)
        with Observer(args,scratch,play=True) as host, log.open('a',encoding='utf-8') as output, qwg.open('rb') as source:
            probes = WaterProbes(source)
            host.ask('state',timeout=65,refresh=True)
            host.ask('click',x=200,y=257)
            host.ask('click',x=1190,y=666)
            deadline = time.monotonic()+18
            while not host.ask('status')['state']['session']:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Could not enter the normal game world')
            host.ask('key',value='g')
            if abs(host.ask('status')['state']['pitch_degrees']) > 1e-6:
                host.ask('key',value='v')
            for i,view in enumerate(views[:args.limit],1):
                record = capture_view(host,view,scratch,args.output,probes)
                output.write(json.dumps(record,ensure_ascii=False,separators=(',',':'))+'\n')
                output.flush()
                if i == 1 or i%50 == 0:
                    print(i,view['key'],record['status'],flush=True)


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(required=True)
    index = commands.add_parser('index')
    for argument in ('shoreline','qwg','plan'):
        index.add_argument(argument,type=Path)
    index.add_argument('--shoreline-ponds',type=Path)
    index.set_defaults(run=build_plan)
    capture = commands.add_parser('capture')
    for argument in ('exe','plan','output'):
        capture.add_argument(argument,type=Path)
    capture.add_argument('--data',type=Path)
    capture.add_argument('--terrain-candidate',type=Path)
    capture.add_argument('--profile',default='WWO-ShorelinePatrol')
    capture.add_argument('--limit',type=int)
    capture.add_argument('--z',type=int,choices=(4,5,6,7))
    capture.set_defaults(run=patrol)
    args = cli.parse_args()
    args.run(args)


if __name__ == '__main__':
    main()
