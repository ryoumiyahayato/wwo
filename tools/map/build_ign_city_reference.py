"""Acquire a bounded modern IGN city reference, reusing the city producer.

Raw pages stay outside res://. No demolished buildings, historical heights or
1900 shorelines are inferred from the present-day survey.
"""
import argparse
import json
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import shapely
from shapely.geometry import shape, mapping, box
from shapely.ops import unary_union
from build_paris_city_reference import fetch, osm_polygons

BUILDINGS = [1.065, 49.42, 1.135, 49.46]
BACKGROUND = [.98, 49.35, 1.22, 49.52]
WFS = 'https://data.geopf.fr/wfs/ows'


def acquire(root, buildings_bounds=BUILDINGS, buildings_only=False, extend_source=None, background_bounds=BACKGROUND, anchor=(1.0993,49.4431), city_name='Rouen', raw_budget_mib=160, water_only=False):
    root.mkdir(parents=True, exist_ok=True)
    def layer(name, bounds, limit):
        q = {'service':'WFS','version':'2.0.0','request':'GetFeature',
             'typenames':'BDTOPO_V3:'+name,'outputFormat':'application/json',
             'srsName':'EPSG:4326','bbox':f'{bounds[1]},{bounds[0]},{bounds[3]},{bounds[2]},urn:ogc:def:crs:EPSG::4326',
             'count':1000,'sortBy':'cleabs'}
        def page(offset):
            scope = '_'.join(map(str,bounds))
            doc = fetch(WFS+'?'+urllib.parse.urlencode(dict(q,startIndex=offset)), root/f'{name}-{scope}-{offset:06d}.geojson')
            print(name,offset,len(doc['features']),flush=True)
            return doc
        first = page(0)
        count = int(first['numberMatched'])
        if count>limit: raise ValueError('Bounded source feature budget exceeded')
        rows = first['features']
        with ThreadPoolExecutor(max_workers=1) as pool:
            for doc in pool.map(page,range(1000,count,1000)): rows.extend(doc['features'])
        if len(rows)!=count or len({f['id'] for f in rows})!=count: raise ValueError('Incomplete source pages')
        return rows
    buildings = [] if water_only else layer('batiment',buildings_bounds,110000)
    if not water_only:
        (root/'buildings.geojson').write_text(json.dumps({'type':'FeatureCollection','features':buildings},separators=(',',':')),encoding='utf-8')
    if buildings_only:
        if extend_source is not None:
            previous=json.loads((extend_source/'buildings.geojson').read_text(encoding='utf-8'))
            previous['features'].extend(buildings)
            (root/'combined-buildings.geojson').write_text(json.dumps(previous,separators=(',',':')),encoding='utf-8')
            structure=json.loads((extend_source/'structure.json').read_text(encoding='utf-8'))
            a=structure['source_bounds']; b=buildings_bounds
            structure['source_bounds']=[min(a[0],b[0]),min(a[1],b[1]),max(a[2],b[2]),max(a[3],b[3])]
            (root/'structure.json').write_text(json.dumps(structure,separators=(',',':')),encoding='utf-8')
        (root/'source.json').write_text(json.dumps({'bounds':buildings_bounds,'building_features':len(buildings),
            'source':{'publisher':'IGN BD TOPO','url':WFS,'layer':'BDTOPO_V3:batiment','license':'Etalab-Open-Licence-2.0','basis':'MODERN_REFERENCE_NOT_1900'},
            'raw_bytes':sum(p.stat().st_size for p in root.iterdir() if p.is_file())},indent=2)+'\n',encoding='utf-8')
        print('IGN building source complete',len(buildings),flush=True)
        return
    waters = layer('surface_hydrographique',background_bounds,12000)
    water = unary_union([shapely.make_valid(shapely.force_2d(shape(f['geometry']))) for f in waters]).intersection(box(*background_bounds))
    coastal_natures = ['Estuaire', 'Retenue-bassin portuaire']
    coastal_water = unary_union([shapely.make_valid(shapely.force_2d(shape(f['geometry']))) for f in waters
                                if f['properties'].get('nature') in coastal_natures]).intersection(box(*background_bounds))
    source = {'publisher':'IGN BD TOPO','url':WFS,'license':'Etalab-Open-Licence-2.0','basis':'MODERN_REFERENCE_NOT_1900'}
    (root/'water.geojson').write_text(json.dumps({'geometry':mapping(water),'camera_background_bounds':background_bounds,
        'coastal_water_geometry':mapping(coastal_water),'coastal_water_natures':coastal_natures,
        'role':'MODERN_PHYSICAL_WATER_REFERENCE_NOT_HISTORICAL','sources':[dict(source,layer='BDTOPO_V3:surface_hydrographique')]},separators=(',',':')),encoding='utf-8')
    if water_only:
        provenance=json.loads((root/'source.json').read_text(encoding='utf-8'))
        provenance.update(water_bounds=background_bounds,water_features=len(waters))
        provenance['raw_bytes']=sum(p.stat().st_size for p in root.iterdir() if p.is_file())
        if provenance['raw_bytes']>raw_budget_mib*1024*1024:raise ValueError('Raw reference storage budget exceeded')
        (root/'source.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print(city_name,'water source complete',len(waters),flush=True)
        return
    # Keep this optional source separate from the building/water survey.
    s,w,n,e = buildings_bounds[1],buildings_bounds[0],buildings_bounds[3],buildings_bounds[2]
    query = f'[out:json][timeout:45];nwr["leisure"~"^(park|garden)$"]({s},{w},{n},{e});(._;>;);out meta;'
    parks = []
    park_sources = []
    try:
        doc = fetch('https://overpass-api.de/api/interpreter',root/'osm-parks.json',urllib.parse.urlencode({'data':query}).encode())
        if doc.get('remark'): raise ValueError(doc['remark'])
        geometry = osm_polygons(doc,buildings_bounds)['parks']
        parks = [{'geometry':mapping(p)} for p in shapely.get_parts(geometry) if p.geom_type=='Polygon']
        park_sources = [{'publisher':'OpenStreetMap contributors','url':'https://www.openstreetmap.org/copyright','license':'ODbL-1.0'}]
    except (OSError,ValueError) as error:
        print('Park reference unavailable; not inferred:',error,flush=True)
    structure = {'anchor':list(anchor),'source_bounds':buildings_bounds,'routes':[],'bridges':[],
        'open_spaces':parks,'open_spaces_basis':'MODERN_REFERENCE_NOT_1900' if park_sources else 'NOT_ACQUIRED',
        'open_spaces_sources':park_sources,'geometry_basis':'MODERN_REFERENCE_NOT_1900_RECONSTRUCTION'}
    (root/'structure.json').write_text(json.dumps(structure,separators=(',',':')),encoding='utf-8')
    provenance = {'bounds':buildings_bounds,'water_bounds':background_bounds,'anchor':list(anchor),'city_name':city_name,'building_count':len(buildings),'water_features':len(waters),
        'sources':[dict(source,layer='BDTOPO_V3:batiment'),dict(source,layer='BDTOPO_V3:surface_hydrographique')]+park_sources,
        'limits':['Modern shapes; no 1900 reconstruction.','Display heights are assumptions.','No road, collision or military qualification.'],
        'raw_bytes':sum(p.stat().st_size for p in root.iterdir() if p.is_file())}
    provenance['raw_budget_mib']=raw_budget_mib
    if provenance['raw_bytes']>raw_budget_mib*1024*1024: raise ValueError('Raw reference storage budget exceeded')
    (root/'source.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(city_name,'source complete',len(buildings),'buildings',len(waters),'water features',len(parks),'park parts',flush=True)


if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root',type=Path,required=True)
    parser.add_argument('--bounds',type=float,nargs=4,default=BUILDINGS)
    parser.add_argument('--buildings-only',action='store_true',help='Reuse existing water/park references without downloading them again.')
    parser.add_argument('--water-only',action='store_true',help='Acquire only the declared water window; preserve existing building and park sources.')
    parser.add_argument('--extend-source-root',type=Path,help='Combine with a previously acquired city source; overlapping footprints share one raster mask.')
    parser.add_argument('--background-bounds',type=float,nargs=4,default=BACKGROUND)
    parser.add_argument('--anchor',type=float,nargs=2,default=(1.0993,49.4431))
    parser.add_argument('--name',default='Rouen')
    parser.add_argument('--raw-budget-mib',type=int,default=160)
    args=parser.parse_args()
    if args.water_only and args.buildings_only:parser.error('Choose only one incremental source mode')
    acquire(args.source_root,args.bounds,args.buildings_only,args.extend_source_root,args.background_bounds,args.anchor,args.name,args.raw_budget_mib,args.water_only)
