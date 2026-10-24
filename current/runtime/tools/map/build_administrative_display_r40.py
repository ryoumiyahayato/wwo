"""Display-only internal strokes; original polygons and memberships stay intact.

Uses the existing French annual GIS and German registered SVG references.
The CShapes snapshot is a display envelope, not an administrative authority.
No snapping, buffering, invented connections, or polygon replacement.
"""
import json
import sys
import zlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'local-artifacts/historical-islands-admin-r5/python-libs'),
                str(ROOT / 'local-artifacts/local-landscape-r4/python-libs')]
from pyproj import Transformer
from shapely.geometry import Polygon, LineString, shape
from shapely.ops import unary_union, transform, linemerge

OUT = ROOT / 'data/presentation/admin_display_r40'


def read(path):
    return json.loads(path.read_text(encoding='utf8'))


def lines(value):
    if value.geom_type == 'LineString':
        return [value] if value.length > 0 else []
    return [line for child in getattr(value, 'geoms', []) for line in lines(child)]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    history = ROOT / 'data/world_map/historical'
    snapshot = read(history / 'cshapes_1900_snapshot.json')
    # Use the exact R27 partition consumed by R37 display and R39 borders,
    # including paint priority and unknown slivers, not overlapping source boxes.
    fragments = {'gw_220': [], 'gw_255': []}
    strategic = read(ROOT / 'data/strategic/index.json')
    for descriptor in strategic['coast_regions']:
        asset = ROOT / descriptor['ink_asset']['path'].removeprefix('res://')
        ink = json.loads(zlib.decompress(asset.read_bytes()))
        for triangle, index in zip(ink['triangles'], ink['indices'], strict=True):
            ref = ink['references'][index]
            if ref in fragments:
                fragments[ref].append(Polygon(triangle[0], triangle[1:]))
    political = {id: unary_union(parts) for id, parts in fragments.items()}
    if any(not g.is_valid for g in political.values()):
        raise ValueError('Invalid admitted political partition')
    project = Transformer.from_crs(4326, 2154, always_xy=True)

    def local(x, y, z=None):
        east, north = project.transform(x, y)
        try:
            return [a-648000 for a in east], [a-6862000 for a in north]
        except TypeError:
            return east-648000, north-6862000

    counts = {}
    entries = []
    for key, index_name, source_id in [
        ('france', 'france_department_boundaries_1900.json', 'gw_220'),
        ('germany', 'german_administration_1900_index.json', 'gw_255'),
    ]:
        index = read(history / index_name)
        descriptors = sorted(index['features'], key=lambda f: (f.get('level', 1), f['id']))
        documents = {f['id']: read(ROOT / f['detail_path'].removeprefix('res://')) for f in descriptors}
        polygons = {id: unary_union([Polygon(part[0], part[1:]) for part in doc['local_polygons']])
                    for id, doc in documents.items()} if key == 'france' else {}
        if any(not g.is_valid for g in polygons.values()):
            raise ValueError('Invalid original reference geometry; do not repair the source silently')
        envelope = transform(local, political[source_id])
        # France has no precomputed internal strokes. Remove its own catalogue
        # outer edge exactly. Germany already has catalogue parent-edge removal.
        perimeter = unary_union(list(polygons.values())).boundary if key == 'france' else None
        used = LineString()
        before = after = 0.0
        segments = 0
        for descriptor in descriptors:
            id = descriptor['id']
            document = documents[id]
            if 'display_lines' in document:
                original = unary_union([LineString(p) for p in document['display_lines'] if len(p) >= 2])
            else:
                original = polygons[id].boundary.difference(perimeter)
            before += original.length
            # This only clips a known historical entity's internal display ink.
            # It does not infer membership from physical coast or a modern state.
            clipped = unary_union(lines(original.intersection(envelope)))
            unique = unary_union(lines(clipped.difference(used)))
            if not unique.is_empty:
                used = unary_union([used, unique])
            after += unique.length
            for lod, tolerance in [('coarse', 1500.0 if key=='france' else 1000.0), ('detail', 0.0)]:
                # Clip after simplification too: chords cannot extend outside
                # the historical display envelope. There is no edge snapping.
                result = unary_union(lines(unique.simplify(tolerance).intersection(envelope)))
                if result.geom_type == 'MultiLineString':
                    result = linemerge(result)
                paths = [[[round(x, 3), round(y, 3)] for x, y in line.coords] for line in lines(result)]
                filename = id.removeprefix('administrative_region:')+'_'+lod+'.json'
                value = {'schema_id': 'historical_internal_admin_display_r40', 'id': id, 'lod': lod,
                         'source_geometry_path': descriptor[lod+'_path'],
                         'political_display_reference': source_id, 'reference_date': '1900-03-12',
                         'display_lines': paths,
                         'role': 'INTERNAL_STROKES_ONLY_ORIGINAL_PICKING_AND_MEMBERSHIP_UNCHANGED'}
                (OUT / filename).write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')
                if lod == 'detail':
                    segments += sum(len(p)-1 for p in paths)
            entries.append(id)
        counts[key] = {'units': len(descriptors), 'input_internal_length_m': round(before, 2),
                       'output_unique_internal_length_m': round(after, 2), 'detail_segments': segments}
    manifest = {'schema_id': 'admin_display_r40_manifest', 'generator': 'tools/map/build_administrative_display_r40.py',
                'source_indices': ['france_department_boundaries_1900.json', 'german_administration_1900_index.json'],
                'political_source': 'R27 existing coarse ink unions, same as R39 country display edges',
                'political_snapshot': 'data/world_map/historical/cshapes_1900_snapshot.json',
                'selection': 'Selected units use the same unique internal strokes; no restored duplicate national outer ring.',
                'limitations_zh': '德国SVG配准与法国年度GIS仍非同源；越界内部显示线取历史政治显示包络交集。未移动顶点、改原始多边形或正式成员。比利时没有已准入的独立历史行政GIS，本轮不补造。',
                'units': entries, 'counts': counts}
    (OUT / 'README.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
    print(json.dumps(counts), flush=True)


if __name__ == '__main__':
    main()
