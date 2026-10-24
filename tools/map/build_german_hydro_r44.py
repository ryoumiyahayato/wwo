"""R44 finite geographic hydrography using R43's existing shard producer.

Actual photo-interpreted EU-Hydro, not DEM drainage. Modern reference only.
"""
import json, re, zlib, collections, concurrent.futures as futures
from pathlib import Path
import requests
from shapely.geometry import shape, box, MultiLineString
from shapely.ops import transform, linemerge, unary_union
from shapely.strtree import STRtree
import build_british_hydro_r43 as shared

ROOT=shared.ROOT
WORK=ROOT/'local-artifacts/german-surface-r44/hydro'
BOUNDS=(5.,46.7,24.,56.3)
historical=json.loads((ROOT/'data/world_map/historical/cshapes_1900_snapshot.json').read_text(encoding='utf8'))
europe=shape(next(f for f in historical['features'] if f['gwcode']==255)['geometry']).intersection(box(0,40,30,65))
# History selects required geographic cells, never cuts at the political edge.
# An outer tile collar preserves neighbouring slopes/rivers without starting
# a nationwide Austrian, Dutch, Swiss or other country construction project.
geographic=unary_union([box(x,y,x+2,y+2) for x in range(4,24,2) for y in range(46,58,2) if box(x,y,x+2,y+2).intersects(europe.buffer(.5))]).intersection(box(*BOUNDS))
AREA=transform(shared.TO_METRES,geographic)
OUT=ROOT/'data/strategic'
PRIMARY=re.compile(r'^(rhein|rhine|main|mosel|moselle|neckar|ruhr|elbe|saale|havel|spree|weser|ems|oder|odra|donau|danube|isar|inn|lech|weichsel|wis[lł]a|vistula|pregel|pregol|nemun)',re.I)
ENGINEERING=re.compile(r'kanal|kanaal|canal|channel|graben|gräben|drain|ditch|dock|reservoir',re.I)


def acquire():
    WORK.mkdir(parents=True,exist_ok=True)
    def query(layer,where,name):
        path=WORK/name
        if path.exists(): return
        features=[]
        q=dict(f='geojson',where=where,geometry=','.join(map(str,BOUNDS)),geometryType='esriGeometryEnvelope',inSR=4326,outSR=4326,
               spatialRel='esriSpatialRelIntersects',outFields='*',resultRecordCount=1000,orderByFields='OBJECTID',returnGeometry='true')
        for offset in range(0,100000,1000):
            q['resultOffset']=offset
            for attempt in range(3):
                try:
                    r=requests.get(shared.SERVICE+str(layer)+'/query',params=q,timeout=120)
                    r.raise_for_status(); data=r.json()
                    if 'error' in data: raise ValueError(data['error'])
                    break
                except Exception:
                    if attempt==2: raise
            features.extend(data['features'])
            if not data.get('exceededTransferLimit',False): break
        else: raise ValueError('Bounded hydrography query did not finish')
        path.write_text(json.dumps(dict(type='FeatureCollection',features=features)),encoding='utf8')
        print(name,len(features),flush=True)
    with futures.ThreadPoolExecutor(max_workers=3) as pool:
        jobs=[pool.submit(query,layer,'1=1',f'eu_rivers_{layer}.geojson') for layer in range(8,14)]
        jobs.append(pool.submit(query,2,"LKE_TYPE = 'N' AND AREA_GEO>=250000",'eu_lakes.geojson'))
        jobs.append(pool.submit(query,2,"UPPER(NAM) LIKE '%CHIEM%' OR UPPER(NAM) LIKE '%STARN%'",'eu_reviewed_bavarian_lakes.geojson'))
        for job in jobs: job.result()
    ne=WORK/'ne_10m_rivers.geojson'
    if not ne.exists():
        r=requests.get('https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_rivers_lake_centerlines.geojson',timeout=120)
        r.raise_for_status(); ne.write_bytes(r.content)


def registry():
    eu=shared.sources()[1].copy()
    eu['source_id']='eu_hydro_german_r44'; eu['version']='RiverNetworkDatabase-1.3:2006-2012:R44'
    eu['access_metadata']=dict(eu['access_metadata'],geometry='Photo-interpreted River_Net_l Strahler>=4, natural lake polygons N >=0.25km²; finite geographic German European scope and collars')
    eu['title']='EU-Hydro modern rivers and natural lakes, German European geographic reference'
    ne=dict(source_id='natural_earth_hydro_r44',title='Natural Earth v5.1.2 retained global river remainders',publisher='Natural Earth',
      version='5.1.2:R44',license='Public Domain',locator='https://www.naturalearthdata.com/about/terms-of-use/',
      access_metadata=dict(source_date='2022 source edition, mixed observation dates',source_crs='EPSG:4326',
       observation_epoch_unknown=True,
       geometry='Existing 1:50M strategic source remainders. The 1:10M source was evaluated but contributes no runtime record in this build.',
       historical_applicability='Modern generalized physical reference, not historical channel banks or engineering'))
    return [eu,ne]


def entry(ident,kind,name,g,main,source,rank=None,**extra):
    return dict(id=ident,kind=kind,name=name,geometry=g,main=main,source=source,rank=rank,**extra)


def features():
    groups=collections.defaultdict(list); records=collections.Counter(); labels={}; unknown=collections.Counter()
    for file in sorted(WORK.glob('eu_rivers_*.geojson')):
        for f in json.loads(file.read_text(encoding='utf8'))['features']:
            p=f['properties']; name=p.get('nameText') or p.get('nameTxtInt') or ''
            if name in ['UNK','NA']: name=''
            if ENGINEERING.search(name): continue
            rank=int(p['STRAHLER']); primary=rank>=6 or bool(PRIMARY.match(name))
            # Grouping retains disconnected source parts, never draws joins.
            key=(name if name else 'unnamed',rank,primary)
            g=transform(shared.TO_METRES,shared.flat_geometry(f['geometry'])).intersection(AREA)
            groups[key].extend(shared.parts(g,'LineString')); records['EU river source parts']+=1
            if not name: unknown[rank]+=1
    result=[]
    for index,((name,rank,primary),lines) in enumerate(sorted(groups.items())):
        if not lines: continue
        g=linemerge(MultiLineString(lines)) if len(lines)>1 else lines[0]
        result.append(entry(f'river:german_r44_{index}','river',name if name!='unnamed' else f'Unnamed source network order {rank}',g,primary,'eu_hydro_german_r44',rank,
           stroke_scale=1.45 if rank>=8 else 1.20 if rank>=6 else .95 if primary else .65))
    lake_sources=[]; lake_shapes=[]
    candidates=json.loads((WORK/'eu_lakes.geojson').read_text(encoding='utf8'))['features']
    candidates+=json.loads((WORK/'eu_reviewed_bavarian_lakes.geojson').read_text(encoding='utf8'))['features']
    for f in candidates:
        p=f['properties']; g=transform(shared.TO_METRES,shared.flat_geometry(f['geometry'])).intersection(AREA)
        if not shared.parts(g,'Polygon'): continue
        if p['LKE_TYPE']!='N' and p['OBJECTID'] not in [45865,45876]: continue
        lake_sources.append(p); lake_shapes.append(g)
    lakes=[]; tree=STRtree(lake_shapes)
    # Dissolve only physical source water, retaining source IDs and names.
    # This removes overlapping/adjacent reporting subdivisions, not legal borders.
    for index,g in enumerate(sorted(shared.parts(unary_union(lake_shapes),'Polygon'),key=lambda p:p.bounds)):
        ids=[int(i) for i in tree.query(g) if g.intersection(lake_shapes[int(i)]).area>.1]
        names=sorted({lake_sources[i]['NAM'].strip() for i in ids if lake_sources[i]['NAM']!='UNK'})
        notes=dict(source_object_ids=[lake_sources[i]['OBJECTID'] for i in ids],
          display_operation='Union of actual water polygons; no decision on sovereignty or national lake sectors')
        if any(lake_sources[i]['OBJECTID'] in [45865,45876] for i in ids):
            notes['reviewed_natural_status']='https://www.lfu.bayern.de/wasser/seen_in_bayern/index.htm'
            notes['source_type_note']='EU-Hydro U retained as original; natural status independently confirmed by LfU Bayern'
        lakes.append(entry(f'lake:german_r44_{index}','lake',' / '.join(names) if names else 'Source natural lake',g,g.area>=4000000,'eu_hydro_german_r44',source_notes=notes))
    result.extend(lakes)
    # Add only actual NE River records in the eastern gap, not arbitrary
    # inferred drainage or lake-centre connectors. Keep their original scale.
    eastern=transform(shared.TO_METRES,box(19.1,53.8,23.3,55.8))
    for index,f in enumerate(json.loads((WORK/'ne_10m_rivers.geojson').read_text(encoding='utf8'))['features']):
        p=f['properties']; name=p.get('name') or ''
        if p.get('featurecla')!='River' or not re.search('pregel|pregol|neman|nemun',name,re.I): continue
        if re.search('neman|nemun',name,re.I) and any(re.search('neman|nemun',e['name'],re.I) for e in result if e['kind']=='river'):
            continue # Finer source exists; do not draw a second generalized axis.
        g=transform(shared.TO_METRES,shape(f['geometry'])).intersection(eastern)
        if not shared.parts(g,'LineString'): continue
        result.append(entry(f'river:german_r44_ne_{index}','river',name,g,True,'natural_earth_hydro_r44',source_date='2022 edition; survey epoch unknown',observation_period={'from':'0001-01-01','to':'9999-12-31'}))
    # The coarser legacy Rhine/Danube must not be drawn on top of new axes.
    # Keep their real outside-scope geometry so an optional display upgrade
    # does not erase the downstream Danube or the Dutch Rhine reference.
    legacy=json.loads(zlib.decompress((OUT/'europe.geom').read_bytes()))
    replaced=[]; remainder=[]
    for ident in ['river:rhine','river:danube']:
        g=transform(shared.TO_METRES,shape(legacy[ident]['geometry']))
        remainder.extend(shared.parts(g.difference(AREA),'LineString')); replaced.append(ident)
    if any('bodensee' in e['name'].lower() or 'constance' in e['name'].lower() for e in lakes): replaced.append('lake:bodensee')
    result.append(entry('river:german_r44_legacy_remainders','river','Retained existing Rhine / Danube outside detailed scope',
       MultiLineString(remainder),True,'natural_earth_hydro_r44',source_date='existing Natural Earth v5.1.2',
       observation_period={'from':'0001-01-01','to':'9999-12-31'},display_replaces=replaced))
    (WORK/'source_summary.json').write_text(json.dumps(dict(records=records,unknown_names_by_order=unknown,
       grouped_rivers=len(result)-len(lakes),lakes=len(lakes),replaces_display_ids=replaced),indent=2),encoding='utf8')
    return result


def write(name,entries,bounds,overview):
    return shared.write_shard(name,entries,bounds,overview,registry(),'tools/map/build_german_hydro_r44.py')


if __name__=='__main__':
    acquire(); items=features(); descriptors=[]
    # Its geographic bounds trigger only near Germany. Its legacy remainders
    # are shown only while this detailed replacement is active.
    descriptors.append(write('german_hydro_overview_r44',[(e,e['geometry']) for e in items if e['main']],[5,24,46.7,56.3],True))
    minor=[e for e in items if not e['main']]
    for lat in range(46,58,4):
        for lon in range(4,24,4):
            bounds=[max(5,lon),min(24,lon+4),max(46.7,lat),min(56.3,lat+4)]
            if bounds[0]>=bounds[1] or bounds[2]>=bounds[3]: continue
            core=transform(shared.TO_METRES,box(bounds[0],bounds[2],bounds[1],bounds[3]))
            entries=[(e,e['geometry'].intersection(core)) for e in minor if e['geometry'].intersects(core)]
            descriptor=write(f'german_hydro_{lat}_{lon:+d}_r44',entries,bounds,False)
            if descriptor:
                descriptor['max_mpp']=250.0
                descriptors.append(descriptor)
    index_path=OUT/'index.json'; index=json.loads(index_path.read_text(encoding='utf8'))
    index['hydro_regions']=[d for d in index.get('hydro_regions',[]) if not str(d['id']).startswith('german_hydro_')]+descriptors
    index_path.write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    summary=dict(descriptors=descriptors,features=[dict(id=e['id'],kind=e['kind'],name=e['name'],main=e['main'],source=e['source'],order=e['rank']) for e in items])
    (WORK/'runtime_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
    print('Runtime shards',len(descriptors),'bytes',sum(d['bytes']+d['geometry_bytes'] for d in descriptors),flush=True)
