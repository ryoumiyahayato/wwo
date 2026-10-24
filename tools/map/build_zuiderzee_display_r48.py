"""Move only the display frame into open water; retain all R46/source files."""
import json
import zlib
from pathlib import Path
from shapely import constrained_delaunay_triangles
from shapely.geometry import mapping
from shapely.ops import transform
import build_benelux_hydro_r46 as original

ROOT = Path(__file__).resolve().parents[2]


def main():
    # The former northern edge cut Vlieland; the eastern edge cut the source
    # coast near the IJssel mouth. No source shoreline vertex is moved.
    water = original.history_water((110000,470000,199000,592000), ROOT/'local-artifacts/terrain-recovery-r48/history')
    geographic = transform(original.shared.TO_DEGREES,water.simplify(80,preserve_topology=True))
    faces = transform(original.shared.TO_DEGREES,constrained_delaunay_triangles(water.simplify(80,preserve_topology=True)))
    triangles = [[list(map(list,t.exterior.coords))] for t in faces.geoms]
    folder = ROOT/'data/strategic'
    document = json.loads((folder/'benelux_hydro_overview_r46.json').read_text(encoding='utf8'))
    geometry = json.loads(zlib.decompress((folder/'benelux_hydro_overview_r46.geom').read_bytes()))
    target = 'res://data/strategic/benelux_hydro_overview_r48.geom'
    for fact in document['evidence_catalog']['facts']:
        feature = fact['value']
        feature['geometry_asset']['path'] = target
        if feature.get('water_class') != 'historical_sea_reference':
            continue
        ident = feature['id']
        # The strategic lake protocol is MultiPolygon even for one body.
        # A Polygon changes nesting and makes both prepared LODs inadmissible.
        query = mapping(geographic)
        if query['type'] == 'Polygon':
            query = dict(type='MultiPolygon', coordinates=[query['coordinates']])
        geometry[ident] = dict(geometry=query,lod_geometry=dict(coarse=triangles,medium=triangles))
        feature['display_frame_revision'] = 'R48: original 1905 coast; RD frame [110000,470000,199000,592000]'
        fact['generator'] = 'tools/map/build_zuiderzee_display_r48.py'
        fact['methodology'] += ' R48 relocates only the clipping frame off physical land; original shore and island coordinates preserved.'
    jp = folder/'benelux_hydro_overview_r48.json'
    gp = folder/'benelux_hydro_overview_r48.geom'
    jp.write_text(json.dumps(document,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    gp.write_bytes(zlib.compress(json.dumps(geometry,separators=(',',':')).encode(),6))
    index_path = folder/'index.json'
    index = json.loads(index_path.read_text(encoding='utf8'))
    for row in index['hydro_regions']:
        if row['id']=='benelux_hydro_overview_r46':
            row.update(path='res://data/strategic/'+jp.name,bytes=jp.stat().st_size,geometry_bytes=gp.stat().st_size)
    index_path.write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    print('Historical sea display:',len(triangles),'triangles;',jp.stat().st_size+gp.stat().st_size,'bytes; stable IDs unchanged')


if __name__ == '__main__':
    main()
