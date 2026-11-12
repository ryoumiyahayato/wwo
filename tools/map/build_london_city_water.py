"""Small ODbL display derivative from two explicitly acquired Thames objects.

No download, global GIS work, terrain generation or simulation facts. Inputs are
the original OSM API JSON; clipped edges are exported separately from real banks.
Requires the same Shapely 2.1 used by the existing hydrography preparation tools.
"""
import argparse
import copy
import zlib
import json
import math
from pathlib import Path
from shapely import constrained_delaunay_triangles
from shapely.geometry import LineString, MultiLineString, box, shape, mapping, Point
from shapely.ops import polygonize, polygonize_full, transform, unary_union
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[2]
ANCHOR = (-.116, 51.506)
SX = 111195 * math.cos(math.radians(ANCHOR[1]))
SY = 111195
BOUNDS = (-.175, 51.478, -.045, 51.522)


def metres(x, y, z=None):
    return (x - ANCHOR[0]) * SX, (y - ANCHOR[1]) * SY


def degrees(p):
    return [round(p[0] / SX + ANCHOR[0], 7), round(p[1] / SY + ANCHOR[1], 7)]


def parts(geometry):
    return list(geometry.geoms) if hasattr(geometry, "geoms") else [geometry]


def read_water(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    nodes = {n["id"]: (n["lon"], n["lat"]) for n in data["elements"] if n["type"] == "node"}
    ways = {w["id"]: w for w in data["elements"] if w["type"] == "way"}
    relation = next(r for r in data["elements"] if r["type"] == "relation")
    rings = {}
    for role in ("outer", "inner"):
        lines = [LineString([nodes[n] for n in ways[m["ref"]]["nodes"]])
                 for m in relation["members"] if m["type"] == "way" and m["role"] == role]
        rings[role] = unary_union(list(polygonize(MultiLineString(lines)))) if lines else None
    water = rings["outer"]
    if rings["inner"] is not None: water = water.difference(rings["inner"])
    return transform(metres, water), {"relation": relation["id"], "version": relation["version"],
        "element_timestamp": relation["timestamp"], "url": f'https://api.openstreetmap.org/api/0.6/relation/{relation["id"]}/full.json'}


def build(inputs, output):
    waters, sources = zip(*(read_water(p) for p in inputs))
    original = unary_union(waters)
    window = transform(metres, box(*BOUNDS))
    water = original.intersection(window).simplify(1.5, preserve_topology=True)
    # Extract the original shores first: the clipping rectangle is never a bank.
    banks = original.boundary.intersection(window).simplify(1.5, preserve_topology=True)
    cuts = original.intersection(window.boundary)
    vertices, indices, lookup = [], [], {}
    def vertex(p):
        key = tuple(round(v, 3) for v in p)
        if key not in lookup:
            lookup[key] = len(vertices)
            vertices.append(degrees(p))
        return lookup[key]
    for polygon in parts(water):
        for triangle in parts(constrained_delaunay_triangles(polygon)):
            ring = list(triangle.exterior.coords)[:3]
            indices.extend(vertex(p) for p in ring)
    polygons = [{"outer": [degrees(p) for p in shape.exterior.coords],
                 "holes": [[degrees(p) for p in ring.coords] for ring in shape.interiors]} for shape in parts(water)]
    document = {"id": "london_central_thames_modern", "role": "PRESENTATION_MODERN_WATER_NOT_1900_BANKS",
        "sources": list(sources), "retrieved_date": "2026-10-29", "license": "ODbL-1.0",
        "attribution": "© OpenStreetMap contributors · https://www.openstreetmap.org/copyright",
        "bounds": list(BOUNDS), "simplification_tolerance_m": 1.5,
        "note": "Modern water reference. Original banks retained; window cuts are data limits, never banks. No historical land use or navigability inferred.",
        "polygons": polygons, "vertices": vertices, "indices": indices,
        "banks": [[degrees(p) for p in line.coords] for line in parts(banks) if line.geom_type == "LineString"],
        "data_limits": [[degrees(p) for p in line.coords] for line in parts(cuts) if line.geom_type == "LineString"]}
    output.write_text(json.dumps(document, separators=(",", ":")), encoding="utf-8")
    print(output, "bytes", output.stat().st_size, "vertices", len(vertices), "triangles", len(indices) // 3)


def regional_handoff(source_root):
    """Two existing medium shards only; shared physical/ink/water/coast source.

    Keep the old files. New derivatives are selected by the original index.
    The coastline convention is land-left. No closing inland connections.
    """
    target = ROOT / 'data/strategic/london_handoff_20261030'
    target.mkdir(exist_ok=True)
    index_path = ROOT / 'data/strategic/index.json'
    index = json.loads(index_path.read_text(encoding='utf8'))
    coastline = json.loads((source_root / 'estuary-coast-handoff.json').read_text(encoding='utf8'))
    if not coastline.get('wwo_acquisition', {}).get('complete'):
        raise ValueError('Incomplete acquired coast source')
    window = transform(metres, box(.18, 51.1, 1.6, 51.9))
    lines = [transform(metres, LineString([(p['lon'], p['lat']) for p in w['geometry']]))
             for w in coastline['elements'] if len(w.get('geometry', [])) > 1]
    polygons, cuts, dangles, invalid = polygonize_full(unary_union([window.boundary] + [g.intersection(window) for g in lines]))
    if cuts.length + dangles.length + invalid.length > .001:
        raise ValueError('Incomplete source coast: no inferred closing segments allowed')
    segments = [LineString([a, b]) for line in lines for a, b in zip(line.coords, list(line.coords)[1:]) if a != b]
    tree = STRtree(segments)
    land_parts = []
    for polygon in polygons.geoms:
        p = polygon.representative_point()
        segment = segments[int(tree.nearest(p))]
        a, b = segment.coords
        if (b[0]-a[0])*(p.y-a[1]) - (b[1]-a[1])*(p.x-a[0]) > 0:
            land_parts.append(polygon)
    coast_land = unary_union(land_parts).simplify(10, preserve_topology=True)
    def inverse(x, y, z=None): return x / SX + ANCHOR[0], y / SY + ANCHOR[1]
    sea = window.difference(coast_land)
    water_doc = json.loads((source_root / 'thames-presentation-union.geojson').read_text(encoding='utf8'))
    gap_doc = json.loads((source_root / 'estuary-gap-water.json').read_text(encoding='utf8'))
    gap_ways = [shape({'type':'Polygon','coordinates':[[(p['lon'],p['lat']) for p in way['geometry']]]})
                for way in gap_doc['elements'] if way['type']=='way' and way.get('tags',{}).get('water')=='river']
    river = transform(metres, unary_union([shape(water_doc['geometry'])]+gap_ways)).simplify(10, preserve_topology=True)
    pieces = [p for p in parts(river) if p.geom_type == 'Polygon']
    main = max(pieces, key=lambda p: p.area)
    river = unary_union([p for p in pieces if p.equals(main) or p.area >= 32*32])
    # No invented connector: reject a separated mouth rather than buffer it.
    if not main.intersects(sea): raise ValueError('Source river and source sea do not meet')
    query_window = transform(metres, box(-.84, 51.1, 1.6, 51.9))
    def geographic(g): return transform(inverse, g)
    def multi(g):
        return {'type': 'MultiPolygon', 'coordinates': [mapping(p)['coordinates'] for p in parts(g) if p.geom_type == 'Polygon' and p.area > 0]}
    def triangles(g):
        return [[list(map(list, t.exterior.coords))] for p in parts(g) if p.geom_type == 'Polygon'
                for t in parts(constrained_delaunay_triangles(p)) if t.area > 0]
    def packed(path, value):
        data = json.dumps(value, separators=(',', ':')).encode()
        path.write_bytes(zlib.compress(data, 9))
        return {'path': 'res://' + path.relative_to(ROOT).as_posix(), 'encoding': 'ZLIB_JSON_UTF8', 'bytes': path.stat().st_size, 'decoded_bytes': len(data)}
    # Existing exact draw-override mechanism suppresses only Thames inside the
    # sourced window. The original OS query geometry remains unchanged.
    hydro = json.loads((ROOT / 'data/strategic/british_hydro_overview_r43.json').read_text(encoding='utf8'))
    thames = next(f['value'] for f in hydro['evidence_catalog']['facts'] if f['value'].get('display_name') == 'River Thames')
    asset = thames['geometry_asset']['path'].removeprefix('res://')
    old_hydro = json.loads(zlib.decompress((ROOT / asset).read_bytes()))[thames['id']]
    old_line = transform(metres, shape(old_hydro['geometry']))
    retained = old_line.difference(query_window)
    replacement = [list(map(list, line.coords)) for line in parts(geographic(retained)) if line.geom_type == 'LineString' and len(line.coords) > 1]
    source_id = 'london_osm_coast_water_20261030'
    changed = []
    for parent in index['coast_regions']:
        for descriptor in parent['medium_regions']:
            id = descriptor['id']
            if id not in ['physical_1_4_mid_5_2', 'physical_2_4_mid_0_2']: continue
            # Always start from original derivatives, never compound a rerun.
            doc = json.loads((ROOT / f'data/strategic/{id}.json').read_text(encoding='utf8'))
            geometry = json.loads(zlib.decompress((ROOT / f'data/strategic/{id}.geom').read_bytes()))
            original_land = transform(metres, shape(geometry['land_reference:' + id]['geometry']))
            b = descriptor['bounds']; cell = transform(metres, box(b[0], b[2], b[1], b[3]))
            new_land = original_land.difference(window).union(coast_land.intersection(cell)).difference(river).intersection(cell)
            new_water = cell.difference(new_land)
            shore = new_land.boundary.difference(cell.boundary)
            for kind, g in [('land_reference', new_land), ('ocean_reference', new_water)]:
                geographic_shape = geographic(g)
                geometry[kind + ':' + id] = {'geometry': multi(geographic_shape), 'lod_geometry': {'medium': triangles(geographic_shape) if kind == 'land_reference' else []}}
            shores = [list(map(list, line.coords)) for line in parts(geographic(shore)) if line.geom_type == 'LineString']
            geometry['coast:' + id] = {'geometry': {'type': 'MultiLineString', 'coordinates': shores}, 'lod_geometry': {'medium': shores}}
            water_id = 'lake:london_thames_surface:' + id
            river_part = geographic(river.intersection(cell))
            geometry[water_id] = {'geometry': multi(river_part), 'lod_geometry': {'medium': multi(river_part)['coordinates']}}
            geometry[thames['id']] = {'geometry': old_hydro['geometry'], 'lod_geometry': {'coarse': replacement, 'medium': replacement}}
            geometry_asset = packed(target / (id + '.geom'), geometry)
            source = copy.deepcopy(doc['source_registry']['sources'][0])
            source.update(source_id=source_id, title='London and Thames estuary bounded OSM water/coast over original NE', publisher='OpenStreetMap contributors; Natural Earth outside acquired window', version='2026-10-30', locator='https://www.openstreetmap.org/copyright', license='ODbL-1.0')
            source['access_metadata'].update(source_date='2026-10-30', retrieved_on='2026-10-30', source_scale='Modern OSM mapped shore; 10m display simplification is not positional accuracy', scope='OSM coast [.18,1.6,51.1,51.9]; existing London OSM water [-.84,.33,51.2,51.8]. Original NE elsewhere.', data_transformation='Land-left polygonization; no source dangles; original island holes retained; paired land/water/coast, matching historical ink clipping; no historical ownership inferred', uncertainty='Modern source; historic reclamation, tidal levels, engineering and tributaries not reconstructed', source_assets=[{'file':'estuary-coast-handoff.json','bytes':(source_root/'estuary-coast-handoff.json').stat().st_size},{'file':'thames-presentation-union.geojson','bytes':(source_root/'thames-presentation-union.geojson').stat().st_size},{'file':'estuary-gap-water.json','bytes':(source_root/'estuary-gap-water.json').stat().st_size,'ways':[66997114,515944056]}])
            doc['source_registry']['sources'].append(source)
            template = copy.deepcopy(doc['evidence_catalog']['facts'][0])
            template.update(fact_id='strategic_spatial:' + water_id, subject_id=water_id, source_id=source_id, source_version=source['version'], source_locator=source['locator'], license=source['license'], methodology=source['access_metadata']['data_transformation'])
            template['value'] = {'id':water_id,'kind':'lake','water_class':'river_surface','display_name':'Thames modern water surface (polygon draw class)', 'source_type':'PHYSICAL_REFERENCE','presentation_lods':['medium'],'valid_from':'1900-01-01','valid_to':'1901-01-01','source_id':source_id,'source_date':'2026-10-30','confidence':.7,'geometry_asset':geometry_asset,'display_override_ids':[thames['id']]}
            for fact in doc['evidence_catalog']['facts']:
                fact.update(source_id=source_id, source_version=source['version'], source_locator=source['locator'], license=source['license'], methodology=source['access_metadata']['data_transformation'])
                fact['value'].update(source_id=source_id, source_date='2026-10-30', geometry_asset=geometry_asset)
            doc['evidence_catalog']['facts'].append(template)
            doc_path = target / (id + '.json'); doc_path.write_text(json.dumps(doc, separators=(',', ':')), encoding='utf8')
            ink = json.loads(zlib.decompress((ROOT / f'data/strategic/{id}.ink.geom').read_bytes()))
            clipped_triangles, refs = [], []
            neutral = ink['references'].index('') if '' in ink['references'] else len(ink['references'])
            if neutral == len(ink['references']): ink['references'].append('')
            covered = []
            land_geo = geographic(new_land); window_geo = geographic(query_window)
            for triangle, ref in zip(ink['triangles'], ink['indices']):
                p = shape({'type':'Polygon','coordinates':triangle})
                if not p.intersects(window_geo): clipped_triangles.append(triangle); refs.append(ref); continue
                piece = p.intersection(land_geo); covered.append(piece)
                t = triangles(piece); clipped_triangles.extend(t); refs.extend([ref]*len(t))
            added = land_geo.intersection(window_geo).difference(unary_union(covered))
            t = triangles(added); clipped_triangles.extend(t); refs.extend([neutral]*len(t))
            ink['triangles'] = clipped_triangles; ink['indices'] = refs
            descriptor.update(path='res://' + doc_path.relative_to(ROOT).as_posix(), bytes=doc_path.stat().st_size, ink_asset=packed(target/(id+'.ink.geom'),ink))
            descriptor.pop('compiled_asset', None)
            changed.append(id)
            print('regional handoff', id, 'river polygons', len(multi(river_part)['coordinates']), 'ink triangles', len(clipped_triangles), flush=True)
    index_path.write_text(json.dumps(index, separators=(',', ':')), encoding='utf8')
    print('compile only:', ','.join(changed), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs='*', type=Path)
    parser.add_argument('--region-handoff', type=Path, help='Existing London source directory; two bounded medium shards only')
    parser.add_argument("--output", type=Path, default=ROOT / "data/local/london_city_water.json")
    args = parser.parse_args()
    if args.region_handoff: regional_handoff(args.region_handoff)
    elif len(args.inputs) == 2: build(args.inputs, args.output)
    else: parser.error('Supply two existing water inputs or --region-handoff')
