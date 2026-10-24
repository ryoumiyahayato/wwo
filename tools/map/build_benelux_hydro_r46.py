"""Benelux water and a bounded 1905 Zuiderzee visual reference.

All polygon booleans, old-display clipping and water triangulation are offline.
The existing loader consumes admitted source geometry and prepared display data.
"""
import json,re,zlib,collections,sys
from pathlib import Path
import requests
from shapely.geometry import shape,box,Polygon,MultiLineString,mapping
from shapely.ops import transform,unary_union,linemerge
from shapely.strtree import STRtree
from pyproj import Transformer
import build_spain_hydro_r45 as acquisition

shared=acquisition.shared;ROOT=shared.ROOT
WORK=ROOT/'local-artifacts/benelux-surface-r46/hydro'
HISTORY=WORK.parent/'history'
BOUNDS=(2.2,49.2,7.6,54.2)
PRIMARY=re.compile(r'^(rijn|rhein|rhine|waal|nederrijn|lek\b|[iĳ]j?ssel|maas|meuse|merwede|scheld|escaut|westerschelde|oosterschelde|leie|lys\b|sambre|dijle|dyle|demer|ourthe|lesse|mosel|moselle|sauer|s[uû]re|our\b|alzette|nieuwe waterweg|nieuwe maas|oude maas|hollands)',re.I)
ENGINEERING=re.compile(r'kanaal|canal|kanal|vaart|gracht|drain|ditch|reservoir|greppel|sloot|havendok|schelde.rijnverbinding',re.I)
LATE_CHANNEL=re.compile(r'bergsche maas|^ijsselmeer$',re.I)
UNREVIEWED_LAKE=re.compile(r'ijsselmeer|amstelmeer|oostvaardersplassen|lepelaarsplassen|noorderplassen|bovenwater|bagger|grind|stausee|baldeneysee|harkortsee|hengsteysee|kemnader',re.I)
RD_TO_GEO=Transformer.from_crs(28992,4326,always_xy=True).transform


def history_water(display_window=(110000,470000,198000,590000), output_dir=None):
    HISTORY.mkdir(parents=True,exist_ok=True)
    path=HISTORY/'kust_1905.geojson'
    if not path.exists():
        r=requests.get('https://geo.rijkswaterstaat.nl/services/ogc/gdr/diepte_ijsselmeergebied/ows',params=dict(
            SERVICE='WFS',VERSION='2.0.0',REQUEST='GetFeature',OUTPUTFORMAT='application/json',TYPENAMES='kust_1905',srsName='EPSG:28992'),timeout=90)
        r.raise_for_status();path.write_bytes(r.content)
    doc=json.loads(path.read_text(encoding='utf8'))
    if len(doc['features'])!=int(doc['totalFeatures']):raise ValueError('Incomplete historical coast source')
    mainland=next(f for f in doc['features'] if f['properties']['opmerking']=='Kustlijn vaste land')
    line=max(shared.parts(shape(mainland['geometry']),'LineString'),key=lambda p:p.length)
    points=list(line.coords)
    # Computational closure is OUTSIDE the supported display window. It is
    # not presented as a historical coast or a dyke across the open sea.
    closure=points+[(points[-1][0],625000),(98000,625000),(98000,points[0][1]),points[0]]
    window=box(*display_window)
    from shapely.geometry import LineString
    if LineString(closure[len(points)-1:]).intersects(window):raise ValueError('Artificial frame entered supported window')
    water=Polygon(closure).intersection(window);islands=[];closures=[]
    for f in doc['features']:
        if f is mainland:continue
        for ring in shared.parts(shape(f['geometry']),'LineString'):
            if ring.is_closed:islands.append(Polygon(ring));continue
            # Named island perimeter endpoints, not unrelated line snapping.
            # Original endpoints remain; record the short explicit closure.
            if f['properties']['opmerking'] in ['Pampus','Ameland']:
                gap=__import__('math').dist(ring.coords[0],ring.coords[-1])
                if gap>4:raise ValueError('Island perimeter gap differs from reviewed source')
                islands.append(Polygon(ring));closures.append(dict(island=f['properties']['opmerking'],closing_segment_m=gap))
    water=water.difference(unary_union(islands))
    if not water.is_valid:raise ValueError('Historical water display polygon invalid')
    geographic=transform(RD_TO_GEO,water)
    destination=HISTORY if output_dir is None else Path(output_dir)
    destination.mkdir(parents=True,exist_ok=True)
    (destination/'water_reference.geojson').write_text(json.dumps(mapping(geographic)),encoding='utf8')
    (destination/'display_method.json').write_text(json.dumps(dict(source_year=1905,source_crs='EPSG:28992',
        display_window_rd=list(display_window),computational_closure_outside_window=True,
        island_endpoint_closures=closures,area_km2=water.area/1e6,
        uncertainty='1905 chart-derived wet/dry line is a near-1900 reference, not exact 1900 tide, depth or surveyed shore. No world land identity altered.'),indent=2),encoding='utf8')
    return transform(shared.TO_METRES,geographic)


def registry():
    eu=shared.sources()[1].copy();eu.update(source_id='eu_hydro_benelux_r46',version='RiverNetworkDatabase-1.3:2006-2012:R46',title='Benelux modern photo-interpreted river and natural-water reference')
    eu['access_metadata']=dict(eu['access_metadata'],scope='Finite geographic Benelux and cross-border collar',
        persistence='HYP=1 and Strahler>=3; intermittent, ephemeral, dry and unknown excluded',
        interpretation='Current centre lines only; modern engineered mouths not automatically 1900 natural riverbanks.')
    coast=dict(source_id='rws_zuiderzee_coast_1905_r46',title='Kust 1905, digitised Zuiderzee chart wet/dry coastline',publisher='Rijkswaterstaat; original chart held by Rijksdienst voor het Cultureel Erfgoed',
        version='S. Mars chart revision 1905; RWS georeferenced digitisation as retrieved 2026-10-18',license='CC0-1.0',
        locator='https://data.overheid.nl/en/dataset/16571-kust-1905',access_metadata=dict(source_crs='EPSG:28992 RD, metres',
        source_epoch='Chart revised 1905, NOT 2021 catalogue validity or 1900 exact survey',
        vertical_datum='No elevation used. Coast is chart dry/wet boundary, not current water level or depth.',
        scale_and_accuracy='Not quantified in supplied vector metadata; georeferenced historical map, not cadastral shoreline.',
        metadata_id='130c9742-c782-46d1-b0fd-442317a42869',historical_applicability='Near-1900 visual reference only. Afsluitdijk and later polders absent; five-year chart/date difference remains.',
        production='Observed mainland shore and island perimeters; closure outside bounded display frame; original GIS retained. No political, topology, economy or ownership changes.'))
    return [eu,coast]


def features(historical):
    area=transform(shared.TO_METRES,box(*BOUNDS));groups=collections.defaultdict(list);ids=collections.defaultdict(list);stats=collections.Counter()
    for file in sorted(WORK.glob('benelux_rivers_*.geojson')):
        for f in json.loads(file.read_text(encoding='utf8'))['features']:
            p=f['properties'];name=(p.get('nameText') or p.get('nameTxtInt') or '').strip()
            if name in ['UNK','NA']:name=''
            if ENGINEERING.search(name):stats['engineering_names_excluded']+=1;continue
            if LATE_CHANNEL.search(name):stats['late_channel_or_modern_lake_axis_excluded']+=1;continue
            rank=int(p['STRAHLER']);main=rank>=6 or bool(PRIMARY.match(name))
            g=transform(shared.TO_METRES,shared.flat_geometry(f['geometry'])).intersection(area)
            # Current reclaimed-land drainage is not shown through the old bay.
            g=g.difference(historical)
            parts=shared.parts(g,'LineString')
            if not parts:continue
            key=(name or 'unnamed',rank,main);groups[key].extend(parts);ids[key].append(p['OBJECTID']);stats['river_source_parts']+=1
    result=[]
    for index,(key,lines) in enumerate(sorted(groups.items())):
        name,rank,main=key;g=linemerge(MultiLineString(lines)) if len(lines)>1 else lines[0]
        result.append(dict(id=f'river:benelux_r46_{index}',kind='river',name=name if name!='unnamed' else f'Unnamed modern source network order {rank}',geometry=g,
            main=main,source='eu_hydro_benelux_r46',rank=rank,stroke_scale=1.40 if rank>=8 else 1.15 if rank>=6 else .90 if main else .50,
            source_notes=dict(source_object_ids=ids[key],hydrological_persistence=1,
                qualification='Modern centre line, not historical width. Estuary works may postdate 1900. Display excludes the separate historical sea reference.')))
    shapes=[];properties=[]
    for f in json.loads((WORK/'benelux_lakes.geojson').read_text(encoding='utf8'))['features']:
        p=f['properties']
        if UNREVIEWED_LAKE.search(p['NAM']):stats['modern_or_possible_artificial_lakes_not_admitted']+=1;continue
        g=transform(shared.TO_METRES,shared.flat_geometry(f['geometry'])).intersection(area).difference(historical)
        if shared.parts(g,'Polygon'):shapes.append(g);properties.append(p)
    tree=STRtree(shapes)
    for index,g in enumerate(sorted(shared.parts(unary_union(shapes),'Polygon'),key=lambda p:p.bounds)):
        ii=[int(i) for i in tree.query(g) if g.intersection(shapes[int(i)]).area>.1]
        names=sorted({properties[i]['NAM'].strip() for i in ii if properties[i]['NAM']!='UNK'})
        result.append(dict(id=f'lake:benelux_r46_{index}',kind='lake',name=' / '.join(names) or 'Unnamed modern natural water reference',geometry=g,
            main=g.area>=4000000,source='eu_hydro_benelux_r46',rank=None,source_notes=dict(source_object_ids=[properties[i]['OBJECTID'] for i in ii],source_lake_type='N',
                qualification='Modern natural-water classification, not 1900 water identity; old Zuiderzee kept separate.')))
    stats['river_display_groups']=len(groups);stats['natural_water_components']=len(result)-len(groups)
    result.append(dict(id='lake:zuiderzee_near1900_reference_r46',kind='lake',name='须德海：1905岸线的近1900海湾显示参考',geometry=historical,main=True,
        source='rws_zuiderzee_coast_1905_r46',rank=None,source_date='1905 chart revision',observation_period={'from':'1905-01-01','to':'1905-12-31'},
        source_notes=dict(water_class='historical_sea_reference',historical_reference_year=1905,
            qualification='Display primitive is a water polygon, NOT a freshwater lake. No exact 1900 shore, tide, legal land or economic-area assertion. Chart-based offshore display frame is not a shore.')))
    (WORK/'source_summary.json').write_text(json.dumps(stats,indent=2),encoding='utf8')
    return result


def old_display_overrides(bounds,overview):
    # Prepare only the OLD draw arrays. Query geometry and immutable originals
    # remain untouched. No GIS difference or triangulation runs on mouse input.
    cut=box(bounds[0],bounds[2],bounds[1],bounds[3]);overrides={}
    paths=[ROOT/'data/strategic/german_hydro_overview_r44.json'] if overview else list((ROOT/'data/strategic').glob('german_hydro_*_r44.json'))
    if overview:paths.append(ROOT/'data/strategic/europe.json')
    for path in paths:
        if not overview and 'overview' in path.name:continue
        doc=json.loads(path.read_text(encoding='utf8'));geometry=json.loads(zlib.decompress(path.with_suffix('.geom').read_bytes()))
        for fact in doc['evidence_catalog']['facts']:
            f=fact['value'];ident=f['id']
            if f['kind'] not in ['river','lake'] or ident not in geometry:continue
            if path.name=='europe.json' and ident!='river:rhine':continue
            original=geometry[ident];g=shape(original['geometry'])
            if not g.intersects(cut):continue
            data={}
            for lod,raw in original['lod_geometry'].items():
                if f['kind']=='river':
                    reduced=shape(dict(type='MultiLineString',coordinates=raw)).difference(cut)
                    data[lod]=[list(map(list,line.coords)) for line in shared.parts(reduced,'LineString')]
                else:
                    # Existing fixed lake triangles, retain their holes by
                    # constrained retriangulation only in this offline producer.
                    from shapely import constrained_delaunay_triangles
                    pieces=[]
                    for polygon in raw:
                        triangle=Polygon(polygon[0],polygon[1:])
                        for part in shared.parts(triangle.difference(cut),'Polygon'):
                            pieces.extend([[list(map(list,t.exterior.coords))] for t in constrained_delaunay_triangles(part).geoms])
                    data[lod]=pieces
            overrides[ident]=dict(geometry={},lod_geometry=data)
    return overrides


def write(name,entries,bounds,overview):
    d=shared.write_shard(name,entries,bounds,overview,registry(),'tools/map/build_benelux_hydro_r46.py')
    if not d:return None
    path=ROOT/d['path'][6:];doc=json.loads(path.read_text(encoding='utf8'));geo_path=path.with_suffix('.geom');geo=json.loads(zlib.decompress(geo_path.read_bytes()))
    overrides=old_display_overrides(bounds,overview)
    first=doc['evidence_catalog']['facts'][0]['value'];first['display_override_ids']=list(overrides)
    geo.update(overrides)
    for fact in doc['evidence_catalog']['facts']:
        f=fact['value']
        if f['source_id']=='rws_zuiderzee_coast_1905_r46':
            f.update(water_class='historical_sea_reference',geometry_role='HISTORICAL_NEAR1900_SEA_REFERENCE_SOURCE1905',
                uncertainty='1905 mapped wet/dry boundary, five years after start date. Visual reference only; no change to legal land or topology.')
    geo_path.write_bytes(zlib.compress(json.dumps(geo,separators=(',',':')).encode(),6))
    path.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    d.update(bytes=path.stat().st_size,geometry_bytes=geo_path.stat().st_size,display_overrides=len(overrides))
    return d


if __name__=='__main__':
    acquisition.WORK=WORK;acquisition.REGIONS=[('benelux',BOUNDS)];acquisition.acquire()
    historical=history_water();items=features(historical);descriptors=[]
    descriptors.append(write('benelux_hydro_overview_r46',[(e,e['geometry']) for e in items if e['main']],[2.2,7.6,49.2,54.2],True))
    for lat in [48,52]:
        for lon in [0,4]:
            b=[max(2.2,lon),min(7.6,lon+4),max(49.2,lat),min(54.2,lat+4)]
            core=transform(shared.TO_METRES,box(b[0],b[2],b[1],b[3]))
            entries=[(e,e['geometry'].intersection(core)) for e in items if not e['main'] and e['geometry'].intersects(core)]
            d=write(f'benelux_hydro_{lat}_{lon:+d}_r46',entries,b,False)
            if d:d['max_mpp']=250.;descriptors.append(d)
    p=ROOT/'data/strategic/index.json';idx=json.loads(p.read_text(encoding='utf8'))
    idx['hydro_regions']=[d for d in idx.get('hydro_regions',[]) if not d['id'].startswith('benelux_hydro_')]+descriptors
    p.write_text(json.dumps(idx,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    summary=dict(descriptors=descriptors,features=[dict(id=e['id'],kind=e['kind'],name=e['name'],main=e['main'],source=e['source'],order=e['rank']) for e in items])
    (WORK/'runtime_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
    print('Runtime shards',len(descriptors),'bytes',sum(d['bytes']+d['geometry_bytes'] for d in descriptors),flush=True)
