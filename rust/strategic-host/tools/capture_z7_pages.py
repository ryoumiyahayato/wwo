"""Collect Z7 page views through the Rust terrain-review observer."""
import argparse
from bisect import bisect_right
from functools import lru_cache
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import time
import uuid


WIDTH, HEIGHT = 1280, 720
COLS, ROWS, STEP = 256, 128, 360 / 256
BATCH = 8
EARTH = 6_371_008.8
HALF_DIAGONAL = math.hypot(WIDTH, HEIGHT) / 2
PREFETCH = 180
REVIEW_RADIUS_PX = 265
PREFETCH_RADIUS = HALF_DIAGONAL + PREFETCH
MAX_MPP = 610
POLAR_GOAL = 89.999
DELTA = math.radians(STEP / 2)
EPS = 1e-8


def bounds(x, y):
    west, north = -180 + x * STEP, 90 - y * STEP
    return west, north - STEP, west + STEP, north


def row_center(y):
    return 90 - (y + 0.5) * STEP


def radius(lat):
    lat = math.radians(lat)
    sine, cosine = math.sin(lat), math.cos(lat)
    corner_dots = [sine * math.sin(lat + d) + cosine * math.cos(lat + d) * math.cos(DELTA)
                   for d in (-DELTA, DELTA)]
    return math.acos(min(1, max(-1, min(corner_dots))))


ROWS_GEOMETRY = [(phi, math.sin(phi), math.cos(phi), radius(lat))
                 for lat in map(row_center, range(ROWS)) for phi in [math.radians(lat)]]
LONGITUDE_OFFSETS = [math.cos(math.radians(i * STEP)) for i in range(COLS)]


@lru_cache(maxsize=48)
def page_clearances(lat):
    """Angular center-to-bounding-cap clearance, as used by exact Z7 selection."""
    phi = math.radians(lat)
    angle = PREFETCH_RADIUS * MAX_MPP / EARTH
    sin_center, cos_center = math.sin(phi), math.cos(phi)
    clearances = []
    for row, sine, cosine, cap_radius in ROWS_GEOMETRY:
        if abs(row - phi) > angle + cap_radius:
            continue
        a, b = sine * sin_center, cosine * cos_center
        for offset in LONGITUDE_OFFSETS:
            clearance = math.acos(min(1, max(-1, a + b * offset))) - cap_radius
            if clearance <= angle:
                clearances.append(clearance)
    return sorted(clearances)


def scale_limit(lat, capacity):
    clearances = page_clearances(lat)
    if len(clearances) <= capacity:
        return MAX_MPP
    return max(0, 0.96 * clearances[capacity] * EARTH / PREFETCH_RADIUS)


def fit_band(lat, mpp, south, north, width=STEP):
    """Return a full-longitude latitude interval certified inside the viewport."""
    phi = math.radians(lat)
    a, b = math.sin(phi), math.cos(phi) * math.cos(math.radians(width / 2))
    threshold = math.cos(REVIEW_RADIUS_PX * mpp / EARTH)
    ratio = threshold / math.hypot(a, b)
    if ratio >= 1:
        return None
    pivot, extent = math.atan2(a, b), math.acos(ratio)
    lo = max(south, math.degrees(pivot - extent))
    hi = min(north, math.degrees(pivot + extent))
    return (lo, hi) if hi > lo else None


def combine(intervals):
    combined = []
    for south, north in sorted(tuple(interval) for interval in intervals if interval is not None):
        if combined and south <= combined[-1][1] + EPS:
            combined[-1] = (combined[-1][0], max(combined[-1][1], north))
        else:
            combined.append((south, north))
    return combined


def span(intervals):
    return sum(north - south for south, north in intervals)


def missing_intervals(covered, south, north):
    missing = []
    start = south
    for lo, hi in covered:
        if lo > start + EPS:
            missing.append((start, lo))
        start = max(start, hi)
    if north > start + EPS:
        missing.append((start, north))
    return missing


def page_view(lat, mpp, south, north):
    clearances = page_clearances(lat)
    return {
        'lat': lat,
        'mpp': mpp,
        'planned_full_longitude_latitude_band': fit_band(lat, mpp, south, north),
        'estimated_visible_pages': bisect_right(clearances, HALF_DIAGONAL * mpp / EARTH),
        'estimated_prefetch_pages': bisect_right(clearances, PREFETCH_RADIUS * mpp / EARTH),
    }


def additional_views(mpp, south, north, capacity, close):
    """Generate overlapping in-page candidates for uncovered latitude bands."""
    goal_south, goal_north = max(south, -POLAR_GOAL), min(north, POLAR_GOAL)
    candidates = [south + STEP * (i + 0.5) / 64 for i in range(64)]
    if north == 90 or south == -90:
        sign = 1 if north == 90 else -1
        # Place the viewport's nearest edge just short of the pole.
        candidates.extend(sign * (90 - math.degrees((HEIGHT / 2 + 3) * mm / EARTH))
                          for mm in range(10, 100, 2))
    for lat in sorted(set(candidates)):
        if not south < lat < north:
            continue
        no_pole = math.radians(90 - abs(lat)) * EARTH / (HEIGHT / 2 + 2)
        limit = min(scale_limit(lat, capacity), no_pole, mpp if close else MAX_MPP)
        scale = math.floor(limit)
        if scale < 10:
            continue
        interval = fit_band(lat, scale, goal_south, goal_north)
        if interval is not None:
            yield lat, scale, interval

@lru_cache(maxsize=32)
def row_views(y, capacity):
    """Every page gets two centered scales and fills uncovered latitude bands."""
    _, south, _, north = bounds(0, y)
    center = row_center(y)
    nominal = 605 * math.sqrt((1 + math.cos(math.radians(center)) ** 2) / 2)
    regional = max(10, int(min(nominal, scale_limit(center, capacity)) / 5) * 5)
    close = max(10, round(regional * 0.55))
    result = {}
    for scope, mpp in [('regional', regional), ('close', close)]:
        primary = page_view(center, mpp, south, north)
        views = [primary]
        covered = combine([primary['planned_full_longitude_latitude_band']])
        if missing_intervals(covered, max(south, -POLAR_GOAL), min(north, POLAR_GOAL)):
            candidates = list(additional_views(mpp, south, north, capacity, scope == 'close'))
            while candidates:
                # The best next view adds the largest section of previously uncovered latitude.
                index = max(range(len(candidates)), key=lambda i: (
                    span(combine([*covered, candidates[i][2]])) - span(covered),
                    candidates[i][1],
                ))
                lat, scale, band = candidates.pop(index)
                merged = combine([*covered, band])
                if span(merged) - span(covered) < EPS:
                    break
                covered = merged
                views.append(page_view(lat, scale, south, north))
        result[scope] = {
            'views': views,
            'planned_uncovered_latitude_bands': missing_intervals(covered, south, north),
        }
    return result


def vector(lon, lat):
    lon, lat = map(math.radians, (lon, lat))
    cosine = math.cos(lat)
    return math.sin(lon) * cosine, math.sin(lat), math.cos(lon) * cosine


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def project(lon, lat, axes, mpp, pitch):
    xx, yy, zz = (dot(vector(lon, lat), axis) for axis in axes)
    transverse = math.hypot(xx, yy)
    correction = math.atan2(transverse, zz) / transverse if transverse else 1
    scale = EARTH / mpp * correction
    return WIDTH / 2 + xx * scale, HEIGHT / 2 - yy * scale * math.cos(pitch)


def geographic(x, y, axes, mpp, pitch):
    a = (x - WIDTH / 2) * mpp / EARTH
    b = (HEIGHT / 2 - y) * mpp / (EARTH * math.cos(pitch))
    delta = math.hypot(a, b)
    k = math.sin(delta) / delta if delta else 1
    vx, vy, vz = [(a * ex + b * ny) * k + rad * math.cos(delta)
                  for ex, ny, rad in zip(*axes)]
    return math.degrees(math.atan2(vx, vz)), math.degrees(math.asin(max(-1, min(1, vy))))


def geometry(tile_bounds, state, lon):
    """Describe the actual north-up azimuthal view returned with the PNG."""
    west, south, east, north = tile_bounds
    axes, mpp = state['orientation'], state['mpp']
    pitch = math.radians(state['pitch_degrees'])
    frame_edge = [(WIDTH * f / 16, y) for f in range(17) for y in (0, HEIGHT)]
    frame_edge += [(x, HEIGHT * f / 16) for f in range(1, 16) for x in (0, WIDTH)]
    geographic_edges = [geographic(x, y, axes, mpp, pitch) for x, y in frame_edge]
    lons_unwrapped = [lon + (lng - lon + 180) % 360 - 180 for lng, _ in geographic_edges]
    lats = [lat for _, lat in geographic_edges]
    tile_edge = [(west + (east - west) * f / 16, lat)
                 for f in range(17) for lat in (south, north)]
    tile_edge += [(x, south + (north - south) * f / 16)
                  for f in range(1, 16) for x in (west, east)]
    projected = [project(lng, lat, axes, mpp, pitch) for lng, lat in tile_edge]
    screenx, screeny = zip(*projected)
    measured = {
        'viewport_edge_geographic_envelope_approx': [
            min(lons_unwrapped), min(lats), max(lons_unwrapped), max(lats),
        ],
        'longitude_unwrapped_around': lon,
        'tile_projected_pixel_envelope_approx': [
            min(screenx), min(screeny), max(screenx), max(screeny),
        ],
        'tile_full_longitude_latitude_band': fit_band(state['center'][1], mpp, south, north),
        'review_radius_pixels': REVIEW_RADIUS_PX, 'scope': 'Covered bands stay within the central HUD-safe disk.',
    }
    return measured


def write(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n',
                    encoding='utf-8')
    temp.replace(path)


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


class Observer:
    def __init__(self, args, work):
        self.request = work / 'map.json'
        self.response = work / 'map.response.json'
        self.log = (work / 'observer.log').open('ab')
        command = [
            str(args.exe), '--terrain-review', '--terrain-level', '7',
            '--data', str(args.data), '--terrain-candidate', str(args.terrain_candidate),
            '--observe', str(self.request),
        ]
        try:
            self.process = subprocess.Popen(
                command, stdout=self.log, stderr=self.log,
                env={**os.environ, 'WWO_RUST_PROFILE': 'Z7PageReview-' + uuid.uuid4().hex[:12]},
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
            )
        except OSError:
            self.log.close()
            raise

    def ask(self, action, timeout=25, **parameters):
        request_id = uuid.uuid4().hex
        write(self.request, dict(id=request_id, action=action, **parameters))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError(f'Rust observer stopped, see {self.log.name}')
            try:
                response = read(self.response)
            except (OSError, ValueError):
                response = {}
            if response.get('id') == request_id:
                window = response['state']['window']
                if not window['offscreen'] or window['focused']:
                    raise RuntimeError('Expected an offscreen observer without focus')
                return response
            time.sleep(0.025)
        raise TimeoutError(f'Rust observer timed out on {action}')

    def read_at(self, lon, lat, mpp, timeout):
        camera = dict(lon=lon, lat=lat, mpp=mpp, value='north')
        focused = self.ask('focus', timeout=timeout, **camera)
        if abs(focused['state']['pitch_degrees']) >= 1e-6:
            self.ask('key', timeout=timeout, value='v')
            focused = self.ask('focus', timeout=timeout, **camera)
            if abs(focused['state']['pitch_degrees']) >= 1e-6:
                raise RuntimeError('Could not set the terrain-review camera to zero pitch')
        deadline = time.monotonic() + timeout
        reply = None
        while time.monotonic() < deadline:
            reply = self.ask('status', timeout=max(0.1, deadline - time.monotonic()))
            state = reply['state']
            terrain = state.get('terrain')
            if at_camera(state, lon, lat, mpp) and terrain and (
                    terrain['selected_ready'] or terrain['exact_view_over_capacity']):
                break
        return reply

    def __enter__(self):
        return self

    def __exit__(self, *_):
        if self.process.poll() is None:
            try:
                self.ask('quit', timeout=3)
            except (RuntimeError, TimeoutError, OSError):
                pass
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(timeout=5)
        self.log.close()


def at_camera(state, lon, lat, mpp):
    lng, phi = state['center']
    return ((abs(lat) == 90 or abs((lng - lon + 180) % 360 - 180) < 1e-6)
            and abs(phi - lat) < (1e-5 if abs(lat) == 90 else 1e-6)
            and abs(state['mpp'] - mpp) < 1e-6
            and state['projection'] == 'azimuthal_equidistant'
            and abs(state['pitch_degrees']) < 1e-6)


def png_size(path):
    try:
        with path.open('rb') as file:
            header = file.read(24)
            file.seek(-12, os.SEEK_END)
            end = file.read(12)
        if end != bytes.fromhex('0000000049454e44ae426082'):
            return None
        if len(header) == 24 and header[:8] == b'\x89PNG\r\n\x1a\n' and header[12:16] == b'IHDR':
            return struct.unpack('>II', header[16:24])
    except OSError:
        pass
    return None


def assess(response, key, lon, lat, mpp, png):
    state = response['state']
    terrain = state.get('terrain') or {}
    trace = (response.get('extra') or {}).get('terrain_samples') or {}
    samples = trace.get('samples', [])
    point = next((point.get('terrain') for point in samples if point['name'] == 'center'), None) or {}
    pure_z7 = len(samples) == 9 and all(
        sample.get('terrain') and not sample['terrain']['missing_exact_page']
        and len(sample['terrain']['contributors']) == 1
        and sample['terrain']['contributors'][0][0][0] == 7
        and abs(sample['terrain']['contributors'][0][1] - 1.0) < EPS
        for sample in samples
    )
    requested_page = (None if key is None else point.get('target') == key
                      and point.get('contributors') == [[key, 1.0]])
    valid = (at_camera(state, lon, lat, mpp) and state['viewport'] == [WIDTH, HEIGHT]
             and terrain.get('selection') == {'exact': 7} and terrain.get('draw_max_level') == 7
             and terrain.get('selected_ready') and not terrain.get('exact_view_over_capacity')
             and png_size(png) == (WIDTH, HEIGHT) and pure_z7 and (key is None or requested_page))
    return valid, dict(
        observed_camera={'lon_lat': state['center'], 'mpp': state['mpp'], 'size': state['viewport'],
                         'projection': state['projection'], 'pitch_degrees': state['pitch_degrees']},
        terrain=terrain, submitted_page_table_samples=trace,
        render_context={'gpu': state.get('gpu'), 'window': state.get('window'),
                        'orientation': state.get('orientation')},
        center_is_requested_page=requested_page, all_samples_pure_z7=pure_z7,
    )


def capture(host, args, work, key, tile_bounds, lon, planned, label):
    lat, mpp = planned['lat'], planned['mpp']
    png = work / (label + '.png')
    report = dict(planned=planned, requested_lon=lon, status='capture_incomplete',
                  visual_review='pending', img=None, attempts=0)
    for attempt in range(args.attempts):
        report['attempts'] = attempt + 1
        try:
            reply = host.read_at(lon, lat, mpp, args.timeout)
            if reply is not None and at_camera(reply['state'], lon, lat, mpp):
                report['last_pre_capture_terrain'] = reply['state'].get('terrain')
                previous_image = png.stat().st_mtime_ns if png.is_file() else None
                captured = host.ask('capture', timeout=args.timeout, label=label)
                deadline = time.monotonic() + min(4, args.timeout)
                while time.monotonic() < deadline:
                    if png_size(png) == (WIDTH, HEIGHT) and png.stat().st_mtime_ns != previous_image:
                        break
                    time.sleep(0.025)
                else:
                    raise TimeoutError('PNG did not finish writing to its IEND chunk')
                valid, observations = assess(captured, key, lon, lat, mpp, png)
                report.update(observations)
                report['img'] = png.name
                if at_camera(captured['state'], lon, lat, mpp):
                    if tile_bounds is None:
                        cap = math.degrees(REVIEW_RADIUS_PX * mpp / EARTH)
                        report['coverage'] = {
                            'all_longitudes': True,
                            'inscribed_polar_latitude_band': [90 - cap, 90] if lat > 0 else [-90, -90 + cap],
                            'pole': 'north' if lat > 0 else 'south',
                        }
                    else:
                        report['coverage'] = geometry(tile_bounds, captured['state'], lon)
                if valid:
                    report['status'] = 'captured_review_pending'
                    report.pop('capture_error', None)
                    break
        except TimeoutError as error:
            report['capture_error'] = str(error)
    if report['img'] is None:
        report['status'] = 'capture_failed'
    return report


def actual_coverage(views, south, north):
    intervals = combine(report['coverage']['tile_full_longitude_latitude_band']
                        for report in views.values() if report['status'] == 'captured_review_pending')
    return {
        'confirmed_geometric_latitude_bands': intervals,
        'uncovered_latitude_bands': missing_intervals(intervals, south, north),
        'geometric_scope': 'The bands span the full tile longitude. Images and nine sampled '
                           'GPU submission points remain subject to visual review.',
    }


def page(host, args, work, resource, x, y, capacity):
    key = [7, x, y]
    tile_bounds = bounds(x, y)
    west, south, east, north = tile_bounds
    lon = (west + east) / 2
    file = work / f'z7-y{y:03}-x{x:03}.json'
    current = (read(file) if file.exists() else
               dict(resource=resource, page=key, ordinal=1 + y * COLS + x,
                    lon_lat_bounds=tile_bounds, lon_lat_points={
                        'northwest': [west, north], 'northeast': [east, north],
                        'southwest': [west, south], 'southeast': [east, south],
                        'center': [lon, (south + north) / 2],
                    }, scopes={}))
    for scope, details in row_views(y, capacity).items():
        part = current['scopes'].setdefault(scope, dict(views={}))
        part['planned_uncovered_latitude_bands'] = details['planned_uncovered_latitude_bands']
        for order, planned in enumerate(details['views']):
            label = f'z7-y{y:03}-x{x:03}-{scope}-{order:02}'
            saved = part['views'].get(label)
            if (saved and saved['status'] == 'captured_review_pending'
                    and png_size(work / saved['img']) == (WIDTH, HEIGHT)):
                continue
            part['views'][label] = capture(host, args, work, key, tile_bounds, lon, planned, label)
            part['coverage'] = actual_coverage(part['views'], south, north)
            write(file, current)
    print(f'Z7/{x}/{y}', {name: [r['status'] for r in part['views'].values()]
                          for name, part in current['scopes'].items()}, flush=True)


def batches(x, y, count):
    columns = COLS // BATCH
    start = y // BATCH * columns + x // BATCH
    for index in range(start, min(ROWS // BATCH * columns, start + count)):
        yy, xx = divmod(index, columns)
        yield xx * BATCH, yy * BATCH


def load_resource(path):
    manifest = read(path / 'index.json')
    level = manifest['levels'][7]
    expected = (7, COLS, ROWS, COLS * ROWS)
    if (manifest['version'] != 'worldcrs84quad-15s-v2'
            or manifest['tile_matrix_set'] != 'WorldCRS84Quad'
            or tuple(level[key] for key in ('z', 'width', 'height', 'tiles')) != expected):
        raise ValueError('Expected the Z7 WorldCRS84Quad candidate index')
    if (path / '7.qpk').stat().st_size != level['bytes']:
        raise ValueError('Candidate Z7 index and QPK byte counts differ')
    return {
        'version': manifest['version'], 'surface_revision': manifest.get('surface_revision'),
        'z7_qpk_bytes': level['bytes'], 'candidate': str(path),
    }


def terrain_capacity(host, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        reply = host.ask('status', timeout=max(.1, deadline - time.monotonic()))
        state = reply['state']
        terrain = state.get('terrain')
        if terrain is None:
            continue
        if terrain.get('selection') != {'exact': 7}:
            raise RuntimeError('Rust observer did not open an exact Z7 terrain')
        if state['viewport'] != [WIDTH, HEIGHT]:
            raise RuntimeError('The observer viewport differs from the planned 1280×720')
        return terrain['detail_capacity']
    raise TimeoutError('Rust observer did not initialize a terrain renderer')


def write_header(path, header):
    if path.exists() and read(path) != header:
        raise RuntimeError(f'Capture settings changed, use a separate output: {path.parent}')
    write(path, header)


def run_batch(args, resource, x, y):
    work = args.out / f'batch-y{y:03}-x{x:03}'
    work.mkdir(parents=True, exist_ok=True)
    with Observer(args, work) as host:
        capacity = terrain_capacity(host, args.timeout)
        write_header(work / 'batch.json',
                     dict(resource=resource, bounds_xy=[x, y, x + BATCH, y + BATCH],
                          viewport=[WIDTH, HEIGHT], safe_review_radius_pixels=REVIEW_RADIUS_PX, order='Y then X', detail_capacity=capacity))
        for yy in range(y, y + BATCH):
            for xx in range(x, x + BATCH):
                page(host, args, work, resource, xx, yy, capacity)


def pole_views(capacity):
    planned = {}
    for name, lat in [('north', 90), ('south', -90)]:
        regional = max(10, int(min(90, scale_limit(lat, capacity))))
        planned[name] = {}
        for scope, mpp in [('regional', regional), ('close', max(10, round(regional * 0.55)))]:
            view = page_view(lat, mpp, lat, lat)
            view.pop('planned_full_longitude_latitude_band')
            planned[name][scope] = view
    return planned


def capture_poles(args, resource):
    work = args.out / 'poles'
    work.mkdir(parents=True, exist_ok=True)
    with Observer(args, work) as host:
        capacity = terrain_capacity(host, args.timeout)
        write_header(work / 'poles.json',
                     dict(resource=resource, longitude_meaning='Orientation is arbitrary at a pole',
                          viewport=[WIDTH, HEIGHT], safe_review_radius_pixels=REVIEW_RADIUS_PX, detail_capacity=capacity))
        for pole, views in pole_views(capacity).items():
            for scope, view in views.items():
                label = f'z7-pole-{pole}-{scope}'
                receipt = work / (label + '.json')
                saved = read(receipt) if receipt.is_file() else {}
                if saved.get('status') == 'captured_review_pending' and png_size(work / saved['img']) == (WIDTH, HEIGHT):
                    continue
                if view['estimated_prefetch_pages'] > capacity:
                    saved = dict(planned=view, status='capture_not_run_budget', detail_capacity=capacity)
                else:
                    saved = capture(host, args, work, None, None, 0, view, label)
                write(receipt, dict(resource=resource, **saved))
                print(label, saved['status'], flush=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path)
    parser.add_argument('--data', type=Path)
    parser.add_argument('--terrain-candidate', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--program-revision', help='Build provenance supplied by the operator.')
    parser.add_argument('--batch-x', type=int, default=0, help='First block X, aligned to eight.')
    parser.add_argument('--batch-y', type=int, default=0, help='First block Y, aligned to eight.')
    parser.add_argument('--batches', type=int, default=1)
    parser.add_argument('--timeout', type=float, default=25)
    parser.add_argument('--attempts', type=int, choices=range(1, 4), default=2)
    parser.add_argument('--poles', action='store_true', help='Capture exact north and south polar views separately.')
    parser.add_argument('--plan', action='store_true', help='Show geometric camera counts without launching Rust.')
    args = parser.parse_args()
    if (not 0 <= args.batch_x < COLS or not 0 <= args.batch_y < ROWS
            or args.batch_x % BATCH or args.batch_y % BATCH or args.batches < 1
            or args.timeout <= 0):
        parser.error('Bad 8×8 batch coordinates, batch count or timeout')
    pending = batches(args.batch_x, args.batch_y, args.batches)
    if args.plan and args.poles:
        print(json.dumps(dict(capacity_assumed=256, pole_views=pole_views(256)), ensure_ascii=False))
        return
    if args.plan:
        for x, y in pending:
            report = {yy: row_views(yy, 256) for yy in range(y, y + BATCH)}
            print(json.dumps(dict(batch_xy=[x, y], capacity_assumed=256, review_radius_pixels=REVIEW_RADIUS_PX,
                                  rows=report,
                                  captures=BATCH * sum(len(part['views']) for scopes in report.values()
                                                       for part in scopes.values())),
                             ensure_ascii=False))
        return

    for parameter in ('exe', 'data', 'terrain_candidate', 'out'):
        path = getattr(args, parameter)
        if path is None:
            parser.error(f'--{parameter.replace("_", "-")} is required for capture')
        setattr(args, parameter, path.resolve())
    resource = load_resource(args.terrain_candidate)
    if args.program_revision:
        resource['program_revision'] = args.program_revision
    if args.poles:
        capture_poles(args, resource)
        return
    for x, y in pending:
        run_batch(args, resource, x, y)


if __name__ == '__main__':
    main()
