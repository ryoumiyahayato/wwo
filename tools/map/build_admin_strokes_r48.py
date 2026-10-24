"""Unique French lower-administration display edges; original GIS untouched.

Exact geometric subtraction only: one deterministic owner per shared edge.
Parent edges remain owned by the higher level. Selection uses the same strokes;
original polygons continue to own picking, identity and membership.
"""
import collections
import json
from pathlib import Path
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union, linemerge
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[2]
HISTORY = ROOT/'data/world_map/historical'
OUT = ROOT/'data/presentation/admin_display_r48'


def read(path):
    return json.loads(path.read_text(encoding='utf8'))


def lines(geometry):
    if geometry.geom_type == 'LineString':
        return [geometry] if geometry.length else []
    return [line for g in getattr(geometry, 'geoms', []) for line in lines(g)]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    lower = read(HISTORY/'france_lower_1900_index.json')['features']
    departments = read(HISTORY/'france_department_boundaries_1900.json')['features']
    rows = sorted(departments+lower, key=lambda r: (r.get('level',1),r['id']))
    boundaries = []
    for row in rows:
        doc = read(ROOT/row['detail_path'][6:])
        polygons = [Polygon(p[0],p[1:]) for p in doc['local_polygons']]
        if any(not p.is_valid for p in polygons):
            raise ValueError('Invalid original polygon: '+row['id'])
        boundaries.append(unary_union(polygons).boundary)
    tree = STRtree(boundaries)
    counts = collections.defaultdict(lambda: dict(units=0,input_m=0.,unique_m=0.,segments=0))
    for index, (row, boundary) in enumerate(zip(rows,boundaries)):
        level = row.get('level',1)
        if level == 1:
            continue  # R40 still owns department strokes.
        neighbors = [boundaries[int(j)] for j in tree.query(boundary) if int(j)<index]
        unique = boundary.difference(unary_union(neighbors)) if neighbors else boundary
        parts = lines(unique)
        unique = unary_union(parts)
        if unique.geom_type == 'MultiLineString':
            unique = linemerge(unique)
        lods = {}
        for lod, tolerance in [('coarse',120.),('detail',0.)]:
            result = unique.simplify(tolerance)
            lods[lod] = [[[round(x,3),round(y,3)] for x,y in p.coords] for p in lines(result)]
        doc = dict(schema_id='historical_unique_admin_display_r48',id=row['id'],
                   source_geometry_paths={lod:row[lod+'_path'] for lod in lods},display_lines=lods,
                   role='EXACT_SHARED_EDGE_OWNERSHIP_ONLY_PICKING_AND_MEMBERSHIP_UNCHANGED')
        (OUT/(row['id'].split(':',1)[1]+'.json')).write_text(json.dumps(doc,separators=(',',':'))+'\n',encoding='utf8')
        stats = counts[level]
        stats['units'] += 1
        stats['input_m'] += boundary.length
        stats['unique_m'] += unique.length
        stats['segments'] += sum(len(p)-1 for p in lods['detail'])
    manifest = dict(generator='tools/map/build_admin_strokes_r48.py',source='TRF-GIS existing 1900 annual references, CC BY 4.0',
                    ownership='Higher level, then stable ID; exact common segments only. No snapping or new political clipping.',
                    counts=dict(counts))
    (OUT/'README.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
    print(json.dumps(manifest['counts']),flush=True)


if __name__ == '__main__':
    main()
