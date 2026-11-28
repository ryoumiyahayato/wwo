"""Index the whole shoreline and capture its regions in the normal game."""
import argparse
from collections import Counter, defaultdict
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
                                   WATER_STEP, WaterGeometry, polygon_parts, shoreline_sources,
                                   water_pack_index, water_payload_cells)
from capture_z7_pages import (EARTH, WIDTH, HEIGHT, Observer, at_camera, bounds, dot, geographic,
                              png_size, read, vector, write)

CAPTURED_VIEWS = ('captured_review_pending', 'captured_with_water_fallback')
FALLBACK_COVERAGE = ('qpk_for_missing_qwg_pages', 'water_budget_unknown')


def shore_sections(source, ponds):
    levels = []
    sections = []
    edges = Counter()
    polar_closures = 0
    for level, geometry in shoreline_sources(source,ponds):
        for polygon in polygon_parts(geometry):
            for ring in (polygon.exterior, *polygon.interiors):
                points = np.asarray(ring.coords)
                if np.any(np.abs(np.diff(points[:, 0])) > 180):
                    raise ValueError('Patrol index requires dateline-split GSHHG')
                cuts = []
                if level == 5:
                    before, after = points[:-1], points[1:]
                    # The Antarctic ice-front parts close through the South Pole
                    # along meridians and on the bottom of the geographic grid.
                    at_pole = before[:,1] == -90
                    to_pole = after[:,1] == -90
                    along_meridian = before[:,0] == after[:,0]
                    cuts = np.flatnonzero((at_pole & to_pole) |
                                          ((at_pole | to_pole) & along_meridian)).tolist()
                    polar_closures += len(cuts)
                start = 0
                for end in (*cuts, len(points)-1):
                    # Short runs keep the geographic index local even for continents.
                    for i in range(start, end, 96):
                        part = points[i:min(i+96, end)+1]
                        if not np.any(np.diff(part, axis=0)):
                            continue
                        sections.append(LineString(part))
                        levels.append(level)
                        edges[level] += len(part)-1
                    start = end+1
    return STRtree(sections), np.asarray(levels), edges, polar_closures


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


def wide_view_fits(rect, mpp):
    west, south, east, north = rect
    half_lon, half_lat = (math.radians((east-west)/2), math.radians((north-south)/2))
    if half_lon > math.radians(3):
        return False
    angle = view_radius(rect)/EARTH
    correction = angle/math.sin(angle) if angle else 1.
    cosine = math.cos(math.radians(min(abs(south), abs(north)) if south*north>0 else 0))
    sine = abs(math.sin(math.radians((south+north)/2)))
    # Bounds for east and north components of the north-up spherical projection.
    scale = correction*EARTH/mpp
    return (cosine*math.sin(half_lon)*scale <= 475
            and (math.sin(half_lat)+cosine*sine*(1-math.cos(half_lon)))*scale <= 250)


def batch_near(args):
    plan = read(args.plan)
    bands = defaultdict(list)
    for view in plan['views']:
        if view['z'] == 7:
            west,south,east,north = view['rect']
            bands[south,north,east-west].append(view)
    groups = []
    for (south,north,_),views in bands.items():
        views.sort(key=lambda view: view['rect'][0])
        group = []
        for view in views:
            west,_,east,_ = view['rect']
            if group and (west != group[-1]['rect'][2] or not wide_view_fits(
                    (group[0]['rect'][0],south,east,north),
                    min(item['mpp'] for item in (*group,view)))):
                groups.append(group)
                group = []
            group.append(view)
        groups.append(group)
    result = []
    for group in groups:
        first = group[0]
        if len(group) == 1:
            result.append(first)
            continue
        west,south,_,north = first['rect']
        rect = (west,south,group[-1]['rect'][2],north)
        view = view_record(first['key']+'-batch',7,rect,
                           {level for item in group for level in item['gshhg_levels']},
                           sum(item['vertices'] for item in group),
                           sum(item['measured_water_cells'] for item in group))
        view['mpp'] = min(item['mpp'] for item in group)
        view['members'] = [item['key'] for item in group]
        result.append(view)
    plan['views'] = sorted(result,key=lambda view: (-view['lat'],view['lon']))
    write(args.output,plan)
    print(f"{sum(map(len,groups))} shoreline sections in {len(result)} Z7 views",flush=True)


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
    tree, levels, edges, polar_closures = shore_sections(args.shoreline,args.shoreline_ponds)
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
                          gshhg_edges=edges, gshhg_polar_closures=polar_closures, views=result))
    print(dict(sorted(Counter(view['z'] for view in result).items())), flush=True)


def ready(state, view, *, require_full_qwg=False):
    terrain = state.get('terrain')
    if not terrain or not terrain['selected_ready'] or state['mode'] != 'geographic':
        return False
    water_ready = (state['mpp'] >= 4200
                   or (terrain['water_geometry_view_resident'] == terrain['water_geometry_view_wanted']
                       and not terrain.get('water_geometry_handoff_active', False)
                       and (not require_full_qwg or terrain.get('water_geometry_view_missing_outside_budget') == 0)))
    return (terrain['water_geometry_buffer_bytes'] > 0 and water_ready
            and at_camera(state, view['lon'], view['lat'], view['mpp']))


def project_grid(lon, lat, orientation, mpp):
    lon, lat = np.broadcast_arrays(np.radians(lon), np.radians(lat))
    cosine = np.cos(lat)
    vectors = np.stack((np.sin(lon)*cosine, np.sin(lat), np.cos(lon)*cosine), axis=-1)
    east, north, up = (vectors @ np.asarray(orientation).T).T
    across = np.hypot(east, north)
    scale = np.arctan2(across, up)/np.maximum(across, 1e-15)*EARTH/mpp
    return np.stack((WIDTH/2+east*scale, HEIGHT/2-north*scale), axis=-1)


def clear_color_class(colors):
    r, g, b = colors.T
    blue = (b > g+4) & (g > r+11) & (r < .82*b)
    ground = (g > b+7) | (r > b+9)
    return np.select((blue, ground), (2, 1))


class WaterProbes(WaterGeometry):
    def review(self, image, state, admitted, wide):
        # At wider scales the game mixes or replaces QWG with the base map.
        mpp = state['mpp']
        if not admitted or mpp > 2600 or state['viewport'] != [WIDTH,HEIGHT]:
            return {'status':'geometry_color_check_unavailable'}
        pixels = np.asarray(image)
        axes = state['orientation']
        compared = Counter()
        suspect = []
        horizontal = 440 if wide else 220
        for dy in range(-220,221,44):
            for dx in range(-horizontal,horizontal+1,44):
                if not wide and dx*dx+dy*dy > 250**2:
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

    def seams(self, image, state, rect):
        if state['viewport'] != [WIDTH, HEIGHT] or abs(state['pitch_degrees']) > 1e-5:
            return None
        w, s, e, n = rect
        axes, mpp = state['orientation'], state['mpp']
        colors = np.asarray(image.convert('RGB'), dtype=np.int16)
        step = WATER_STEP/WATER_GRID
        suspects = []
        # Compare both sides of each projected QWG cell edge. Ignore real shorelines
        # in the reference and look for a sustained color change across the same surface.
        for axis, low, high, start, end, origin in ((0,w,e,s,n,-180), (1,s,n,w,e,-90)):
            offset = np.array([4, 0] if axis == 0 else [0, 4])
            for index in range(math.ceil((low-origin)/step), math.floor((high-origin)/step)+1):
                edge = origin+index*step
                endpoints = (edge, [start, end]) if axis == 0 else ([start, end], edge)
                first, last = project_grid(*endpoints, axes, mpp)
                count = 1+min(512, math.ceil(np.linalg.norm(last-first)/7))
                along = np.linspace(start, end, count)
                line = (edge, along) if axis == 0 else (along, edge)
                points = np.rint(project_grid(*line, axes, mpp)).astype(int)
                x, y = points.T
                points = points[(x >= 150) & (x < 1130) & (y >= 92) & (y < 616)]
                left, right = points-offset, points+offset
                actual_left = clear_color_class(colors[left[:,1], left[:,0]])
                actual_right = clear_color_class(colors[right[:,1], right[:,0]])
                changed = (actual_left > 0) & (actual_right > 0) & (actual_left != actual_right)
                previous, run = -2, []
                for i in np.flatnonzero(changed):
                    px, py = left[i]+.5
                    qx, qy = right[i]+.5
                    left_water = self.area(*geographic(px, py, axes, mpp, 0)) > 1
                    right_water = self.area(*geographic(qx, qy, axes, mpp, 0)) > 1
                    if left_water != right_water:
                        continue
                    if i != previous+1:
                        run = []
                    run.append(points[i].tolist())
                    previous = i
                    if len(run) == 4:
                        suspects.append({'grid': 'lon' if axis == 0 else 'lat',
                                         'degree': edge, 'pixels': [run[0], run[-1]]})
        return suspects

    def separate_boundary_colors(self, diagnostics, state):
        suspects = diagnostics.get('suspect')
        if not suspects:
            return diagnostics
        axes, mpp = state['orientation'], state['mpp']
        stable, mixed = [], []
        for x, y, expected in suspects:
            expected_water = expected == 'expected_water'
            # The screenshot probe takes the median of these same 25 pixels.
            # A narrow island or channel can sit between the four outer probes.
            uniform = all((self.area(*geographic(x+dx+.5,y+dy+.5,axes,mpp,0)) > 1)
                          == expected_water for dx in range(-2,3) for dy in range(-2,3))
            (stable if uniform else mixed).append([x,y,expected])
        if not mixed:
            return diagnostics
        return {**diagnostics, 'suspect': stable, 'mixed_boundary': mixed,
                'status': 'check_suspect_pixels' if stable else 'source_boundary_in_probe'}


def capture_view(host, view, scratch, directory, probes):
    camera = dict(lon=view['lon'],lat=view['lat'],mpp=view['mpp'],value='north')
    state = host.ask('focus',**camera)['state']
    if abs(state['pitch_degrees']) > 1e-6:
        host.ask('key',value='v')
        state = host.ask('focus',**camera)['state']
    deadline = time.monotonic()+6
    while not ready(state, view) and time.monotonic() < deadline:
        state = host.ask('status')['state']
    label = view['key']
    img = scratch/f'{label}.png'
    frame = host.ask('capture', label=label, value='terrain-samples')
    # The focus acknowledgement can still describe the previously drawn page table.
    # Retry against a rendered frame after the new selections settle.
    if not ready(frame['state'], view) and time.monotonic() < deadline:
        state = frame['state']
        while not ready(state, view) and time.monotonic() < deadline:
            state = host.ask('status')['state']
        img.unlink(missing_ok=True)
        frame = host.ask('capture', label=label, value='terrain-samples')
    if png_size(img) != tuple(frame['state']['viewport']):
        raise OSError('Missing patrol capture from game')
    state = frame['state']
    terrain = state['terrain']
    sample = frame['extra']['terrain_samples']['samples'][0]['terrain']
    contributors = sample['contributors']
    level_confirmed = (terrain['target_level'] == view['z'] and
                       sum(weight for page,weight in contributors if page and page[0] == view['z']) >= .99)
    wide = 'members' in view
    rect_covered = ((wide_view_fits(view['rect'],state['mpp']) and state['viewport'] == [WIDTH,HEIGHT])
                    if wide else (view_radius(view['rect']) <= 265*state['mpp']
                                  and min(state['viewport']) >= 2*265))
    admitted = ready(state,view)
    mpp = state['mpp']
    budget_gap = terrain.get('water_geometry_view_missing_outside_budget')
    if mpp >= 4200:
        water_coverage = 'qpk_at_scale'
    elif budget_gap is None:
        water_coverage = 'water_budget_unknown'
    elif budget_gap or terrain['water_geometry_view_resident'] != terrain['water_geometry_view_wanted']:
        water_coverage = 'qpk_for_missing_qwg_pages'
    else:
        water_coverage = 'qwg' if mpp <= 2600 else 'qpk_qwg_scale_mix'
    with Image.open(img) as image:
        image = image.convert('RGB')
        diagnostics = probes.review(image,state,admitted and water_coverage == 'qwg',wide)
        image.save(directory/f'{label}.jpg', quality=82)
    img.unlink()
    status = 'capture_has_fallback_or_gap'
    if admitted and rect_covered and level_confirmed:
        status = ('captured_review_pending' if ready(state,view,require_full_qwg=True)
                  else 'captured_with_water_fallback')
    return dict(key=label, image=f'{label}.jpg', state=state,
                samples=frame['extra']['terrain_samples']['samples'],
                rect_covered=admitted and rect_covered, level_confirmed=level_confirmed,
                water_coverage=water_coverage,
                color_probes=diagnostics,
                status=status)


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
        with log.open(encoding='utf-8') as records:
            for line in records:
                record = json.loads(line)
                received[record['key']] = record['status'],record['image']
    views = [view for view in plan['views']
             if (args.z is None or view['z'] in args.z)
             and (args.key is None or view['key'] in args.key)
             and (view['key'] not in received or
                  received[view['key']][0] not in CAPTURED_VIEWS or
                  not (args.output/received[view['key']][1]).is_file())]
    if not views:
        return
    # PNGs live only until the corresponding persistent review image is written.
    with TemporaryDirectory(dir=args.output,prefix='capture-') as temporary:
        scratch = Path(temporary)
        with (Observer(args,scratch,play=True,log_path=args.output/'game.log') as host,
              log.open('a',encoding='utf-8') as output, qwg.open('rb') as source):
            probes = WaterProbes(source)
            host.ask('state',timeout=65,refresh=True)
            host.ask('click',x=200,y=257)
            host.ask('click',x=1190,y=666)
            deadline = time.monotonic()+18
            while not host.ask('status')['state']['session']:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Could not enter the normal game world')
            host.ask('key',value='g')
            for i,view in enumerate(views[:args.limit],1):
                try:
                    record = capture_view(host,view,scratch,args.output,probes)
                except (OSError, TimeoutError) as error:
                    record = dict(key=view['key'],image=None,status='capture_failed',error=str(error))
                output.write(json.dumps(record,ensure_ascii=False,separators=(',',':'))+'\n')
                output.flush()
                if i == 1 or i%50 == 0 or record['status'] == 'capture_failed':
                    print(i,view['key'],record['status'],flush=True)


def report(args):
    plan = read(args.plan)
    latest = {}
    for directory in (args.output, *args.include):
        log = directory/'patrol.jsonl'
        if not log.exists():
            continue
        with log.open(encoding='utf-8') as records:
            for line in records:
                if not line.endswith('\n'):
                    break
                record = json.loads(line)
                if (record['status'] == 'captured_review_pending'
                        and record.get('water_coverage') in FALLBACK_COVERAGE):
                    record['status'] = 'captured_with_water_fallback'
                key = record['key']
                image = record['image']
                path = directory/image if image is not None else None
                previous = latest.get(key)
                if (previous is not None and previous[0]['status'] in CAPTURED_VIEWS
                        and previous[1] is not None and previous[1].is_file()
                        and (record['status'] not in CAPTURED_VIEWS or path is None or not path.is_file())):
                    continue
                latest[key] = record, path
    counts = {z: Counter() for z in (4,5,6,7)}
    flagged = []
    qwg = Path(plan['qwg'])
    if qwg.is_file():
        with qwg.open('rb') as source:
            water = WaterProbes(source)
            for record, _ in latest.values():
                diagnostics = record.get('color_probes', {})
                if diagnostics.get('suspect'):
                    record['color_probes'] = water.separate_boundary_colors(diagnostics, record['state'])
    for view in plan['views']:
        if args.z is not None and view['z'] not in args.z:
            continue
        key = view['key']
        level = counts[view['z']]
        members = len(view['members']) if 'members' in view else 1
        level['planned'] += 1
        level['planned_regions'] += members
        capture = latest.get(key)
        if capture is None:
            level['not_captured'] += 1
            continue
        record, image = capture
        if image is None or not image.is_file():
            level['missing_image'] += 1
            continue
        level[record['status']] += 1
        if record['status'] in CAPTURED_VIEWS:
            level['regions_in_view'] += members
        diagnostics = record.get('color_probes', {})
        coverage = record.get('water_coverage')
        if (record['status'] != 'captured_review_pending' or diagnostics.get('suspect')
                or diagnostics.get('mixed_boundary')
                or coverage in FALLBACK_COVERAGE):
            flagged.append(dict(view=view, image=str(image), status=record['status'],
                                water_coverage=coverage,color_probes=diagnostics))
        if diagnostics.get('status'):
            level[diagnostics['status']] += 1
        if coverage:
            level[coverage] += 1
    result = dict(counts=counts, flagged=flagged)
    if args.inspect_seams:
        result['seam_flags'] = []
        with qwg.open('rb') as source:
            probes = WaterProbes(source)
            for view in plan['views']:
                z = view['z']
                if args.z is not None and z not in args.z:
                    continue
                capture = latest.get(view['key'])
                if capture is None:
                    continue
                record, image_path = capture
                if (record['status'] not in CAPTURED_VIEWS or image_path is None
                        or not image_path.is_file()):
                    continue
                with Image.open(image_path) as image:
                    suspects = probes.seams(image, record['state'], view['rect'])
                if suspects is None:
                    continue
                counts[z]['seam_screens_checked'] += 1
                if suspects:
                    counts[z]['suspect_seam_screens'] += 1
                    result['seam_flags'].append(dict(view=view,image=str(image_path),seams=suspects))
    if args.report_file:
        write(args.report_file,result)
    print(json.dumps(counts,ensure_ascii=False,indent=2))


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(required=True)
    index = commands.add_parser('index')
    for argument in ('shoreline','qwg','plan'):
        index.add_argument(argument,type=Path)
    index.add_argument('--shoreline-ponds',type=Path)
    index.set_defaults(run=build_plan)
    near = commands.add_parser('batch-near', help='Group adjacent Z7 regions at their original ground scale')
    near.add_argument('plan',type=Path)
    near.add_argument('output',type=Path)
    near.set_defaults(run=batch_near)
    capture = commands.add_parser('capture')
    for argument in ('exe','plan','output'):
        capture.add_argument(argument,type=Path)
    capture.add_argument('--data',type=Path)
    capture.add_argument('--terrain-candidate',type=Path)
    capture.add_argument('--profile',default='WWO-ShorelinePatrol')
    capture.add_argument('--limit',type=int)
    capture.add_argument('--z',type=int,choices=(4,5,6,7),action='append')
    capture.add_argument('--key',action='append',help='Capture a specific view key, repeat for several views')
    capture.set_defaults(run=patrol)
    summary = commands.add_parser('report', help='Count captured views and list gaps or suspect colors')
    summary.add_argument('plan',type=Path)
    summary.add_argument('output',type=Path)
    summary.add_argument('--report-file',type=Path)
    summary.add_argument('--z',type=int,choices=(4,5,6,7),action='append')
    summary.add_argument('--include',type=Path,action='append',default=[],
                         help='Read receipts from another patrol batch')
    summary.add_argument('--inspect-seams',action='store_true',
                         help='Look for sustained water/land color changes along QWG cell edges')
    summary.set_defaults(run=report)
    args = cli.parse_args()
    args.run(args)


if __name__ == '__main__':
    main()
