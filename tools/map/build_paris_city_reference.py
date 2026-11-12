"""Acquire one bounded Paris display reference; never a 1900 reconstruction.

Raw APUR/OSM responses remain outside res://. Reuses build_city_miniature.py
and save_city_meshes.gd for the same runtime meshes as London. Cached pages
are reused; no global download, invented buildings, heights or shore links.
"""
import argparse
import json
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import shapely
from shapely.geometry import LineString, Polygon, box, mapping, shape
from shapely.ops import polygonize, unary_union

APUR = 'https://carto2.apur.org/apur/rest/services/OPENDATA/EMPRISE_BATIE_PARIS/MapServer/0'
BOUNDS = [2.255, 48.815, 2.42, 48.91]
BACKGROUND = [2.0, 48.65, 2.70, 49.05]


def fetch(url, path, data=None):
    if not path.exists():
        request = urllib.request.Request(url, data=data, headers={'User-Agent': 'WWO bounded offline map reference'})
        with urllib.request.urlopen(request, timeout=100) as response:
            payload = response.read(32 * 1024 * 1024 + 1)
        if len(payload) > 32 * 1024 * 1024:
            raise ValueError('Single source response exceeds 32 MiB')
        doc = json.loads(payload)
        if 'error' in doc: raise ValueError(doc['error'])
        path.write_bytes(payload)
    return json.loads(path.read_text(encoding='utf-8'))


def osm_polygons(doc, bounds):
    elements = {(e['type'], e['id']): e for e in doc['elements']}
    nodes = {e['id']: (e['lon'], e['lat']) for e in doc['elements'] if e['type'] == 'node'}
    ways = {e['id']: e for e in doc['elements'] if e['type'] == 'way'}
    used = set()
    output = {'water': [], 'parks': []}
    window = box(*bounds)
    def kind(tags):
        if tags.get('natural') == 'water' or tags.get('waterway') == 'riverbank': return 'water'
        if tags.get('leisure') in ['park', 'garden']: return 'parks'
        return None
    for e in elements.values():
        category = kind(e.get('tags', {}))
        if not category or e['type'] != 'relation': continue
        rings = {}
        for role in ['outer', 'inner']:
            lines = []
            for m in e.get('members', []):
                if m['type'] != 'way' or m.get('role', '') != role or m['ref'] not in ways: continue
                w = ways[m['ref']]
                if any(n not in nodes for n in w['nodes']): continue
                lines.append(LineString([nodes[n] for n in w['nodes']]))
                used.add(m['ref'])
            rings[role] = unary_union(list(polygonize(unary_union(lines)))) if lines else Polygon()
        g = rings['outer'].difference(rings['inner'])
        if not g.is_valid: g = shapely.make_valid(g)
        if not g.is_empty: output[category].append(g.intersection(window))
    for e in ways.values():
        category = kind(e.get('tags', {}))
        ns = e.get('nodes', [])
        if not category or e['id'] in used or len(ns) < 4 or ns[0] != ns[-1] or any(n not in nodes for n in ns): continue
        g = shapely.make_valid(Polygon([nodes[n] for n in ns])).intersection(window)
        if not g.is_empty: output[category].append(g)
    return {k: unary_union(v) for k, v in output.items()}


def acquire(root):
    root.mkdir(parents=True, exist_ok=True)
    fetch(APUR+'?f=json', root/'apur-layer.json')
    query = {'where': '1=1', 'geometry': ','.join(map(str, BOUNDS)), 'geometryType': 'esriGeometryEnvelope',
             'inSR': 4326, 'spatialRel': 'esriSpatialRelIntersects', 'f': 'json', 'returnCountOnly': 'true'}
    count = fetch(APUR+'/query?'+urllib.parse.urlencode(query), root/'apur-count.json')['count']
    query.pop('returnCountOnly')
    query.update(f='geojson', outSR=4326, outFields='OBJECTID,an_const,c_perconst',
                 returnGeometry='true', geometryPrecision=7, orderByFields='OBJECTID', resultRecordCount=3000)
    def page(offset):
        q = dict(query, resultOffset=offset)
        d = fetch(APUR+'/query?'+urllib.parse.urlencode(q), root/f'apur-{offset:06d}.geojson')
        print('APUR', offset, len(d['features']), flush=True)
        return d['features']
    features = [f for rows in ThreadPoolExecutor(max_workers=2).map(page, range(0, count, 3000)) for f in rows]
    if len(features) != count or len({f['properties']['OBJECTID'] for f in features}) != count:
        raise ValueError('APUR page count or source IDs disagree')
    footprints = root/'buildings.geojson'
    footprints.write_text(json.dumps({'type':'FeatureCollection','features':features},separators=(',',':')),encoding='utf-8')
    s,w,n,e = BOUNDS[1],BOUNDS[0],BOUNDS[3],BOUNDS[2]
    area = f'({s},{w},{n},{e})'
    q = f'[out:json][timeout:90];(nwr["natural"="water"]{area};nwr["waterway"="riverbank"]{area};nwr["leisure"~"^(park|garden)$"]{area};);(._;>;);out meta;'
    central = fetch('https://overpass-api.de/api/interpreter',root/'osm-context.json',urllib.parse.urlencode({'data':q}).encode())
    context = osm_polygons(central, BACKGROUND)
    # The official French surface layer supplies continuous polygon coverage
    # beyond the centre. Do not widen centre lines or join missing endpoints.
    hydro_url = 'https://data.geopf.fr/wfs/ows'
    hydro_query = {'service':'WFS','version':'2.0.0','request':'GetFeature',
                   'typenames':'BDTOPO_V3:surface_hydrographique','outputFormat':'application/json',
                   'srsName':'EPSG:4326','bbox':f'{BACKGROUND[1]},{BACKGROUND[0]},{BACKGROUND[3]},{BACKGROUND[2]},urn:ogc:def:crs:EPSG::4326',
                   'count':1000,'sortBy':'cleabs'}
    hydro = []
    offset = 0
    while True:
        page = fetch(hydro_url+'?'+urllib.parse.urlencode(dict(hydro_query,startIndex=offset)),root/f'ign-water-{offset:06d}.geojson')
        hydro.extend(page['features'])
        print('IGN water',offset,len(page['features']),flush=True)
        offset += len(page['features'])
        if offset >= int(page['numberMatched']): break
        if not page['features']: raise ValueError('Incomplete IGN pagination')
    if len({f['id'] for f in hydro}) != len(hydro): raise ValueError('Duplicate IGN source IDs')
    context['water'] = unary_union([shapely.make_valid(shapely.force_2d(shape(f['geometry']))) for f in hydro]).intersection(box(*BACKGROUND))
    if context['water'].is_empty: raise ValueError('No acquired water polygons')
    sources = [{'publisher':'APUR','url':APUR,'license':'ODbL-1.0','role':'MODERN_BUILDING_FOOTPRINT_REFERENCE_NOT_1900'},
               {'publisher':'OpenStreetMap contributors','url':'https://www.openstreetmap.org/copyright','license':'ODbL-1.0','role':'MODERN_PARK_REFERENCE'},
               {'publisher':'IGN BD TOPO','url':hydro_url,'layer':'BDTOPO_V3:surface_hydrographique','license':'Etalab-Open-Licence-2.0','role':'MODERN_WATER_POLYGON_REFERENCE'}]
    water = {'geometry':mapping(context['water']), 'camera_background_bounds':BACKGROUND,
             'role':'MODERN_PHYSICAL_WATER_REFERENCE_NOT_HISTORICAL','sources':sources[2:]}
    (root/'water.geojson').write_text(json.dumps(water,separators=(',',':')),encoding='utf-8')
    parks = [mapping(p) for p in shapely.get_parts(context['parks']) if p.geom_type=='Polygon']
    structure = {'anchor':[2.3522,48.8566], 'source_bounds':BOUNDS, 'routes':[], 'bridges':[],
                 'open_spaces':[{'geometry':p} for p in parks],
                 'open_spaces_basis':'MODERN_PARK_REFERENCE_NOT_1900', 'open_spaces_sources':[sources[1]],
                 'geometry_basis':'MODERN_REFERENCE_NOT_1900_RECONSTRUCTION'}
    (root/'structure.json').write_text(json.dumps(structure,separators=(',',':')),encoding='utf-8')
    provenance = {'retrieved_utc':datetime.now(timezone.utc).isoformat(), 'bounds':BOUNDS, 'building_count':count,
                  'sources':sources, 'raw_bytes':sum(p.stat().st_size for p in root.iterdir() if p.is_file()),
                  'limits':['Current footprints; dates are incomplete. No demolished buildings reconstructed.',
                            'No 1900 shoreline or park extent claimed. Heights are display assumptions.']}
    (root/'source.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Source complete', count, 'raw bytes', provenance['raw_bytes'], flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,required=True)
    acquire(parser.parse_args().source_root)
