"""Finite Spain hydrography, using the existing R43 native shard producer.

Photo-interpreted modern centre lines and natural water only. No guessed banks,
straight joins, reservoir-to-natural-lake conversion or transport facts.
"""
import json, re, collections, concurrent.futures as futures
import requests
from shapely.geometry import shape, box, MultiLineString
from shapely.ops import transform, linemerge, unary_union
from shapely.strtree import STRtree
import build_british_hydro_r43 as shared

ROOT=shared.ROOT
WORK=ROOT/'local-artifacts/spain-surface-r45/hydro'
REGIONS=[('spain',(-10.,35.5,5.,44.25)),('canary',(-19.,27.,-13.,30.))]
PRIMARY=re.compile(r'^(r[ií]o |r[ií]u |rio |river )?(ebro|duero|douro|tajo|tejo|tagus|guadiana|guadalquivir|mi[nñ]o|minho|j[uú]car|x[uú]quer|segura)',re.I)
# Spanish WFD names describe reaches "RÍO ... DESDE ... EMBALSE ...".
# A downstream landmark in that text does not turn the *river* into a canal.
# Reject the named object's type, not every engineering word in its context.
ENGINEERING=re.compile(r'^\s*(canal\b|can[aà]l\b|acequia\b|ac[eé]quia\b|s[eè]quia\b|drain\b|ditch\b|reservoir\b|embalse\b|barranc\w*\b|rambla\b|torrent\w*\b|bco\.|rbla\.)',re.I)


def acquire():
    WORK.mkdir(parents=True,exist_ok=True)
    def query(region,bounds,layer,where,name):
        path=WORK/(region+'_'+name+'.geojson')
        if path.exists(): return
        features=[]
        q=dict(f='geojson',where=where,geometry=','.join(map(str,bounds)),geometryType='esriGeometryEnvelope',inSR=4326,outSR=4326,
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
        else: raise ValueError('Hydro source pagination incomplete')
        path.write_text(json.dumps(dict(type='FeatureCollection',features=features)),encoding='utf8')
        print(region,name,len(features),flush=True)
    with futures.ThreadPoolExecutor(max_workers=3) as pool:
        jobs=[]
        for region,bounds in REGIONS:
            for layer in range(7,14):
                jobs.append(pool.submit(query,region,bounds,layer,'HYP = 1',f'rivers_{layer}'))
            jobs.append(pool.submit(query,region,bounds,2,"LKE_TYPE = 'N' AND AREA_GEO>=250000",'lakes'))
        for job in jobs: job.result()


def registry():
    source=shared.sources()[1].copy()
    source.update(source_id='eu_hydro_spain_r45',version='RiverNetworkDatabase-1.3:2006-2012:R45',
                  title='EU-Hydro modern Spain geographic river and natural lake reference')
    source['access_metadata']=dict(source['access_metadata'],
        geometry='Photo-interpreted River_Net_l, Strahler>=3, HYP=1 perennial only; natural N lakes >=0.25km². No reservoirs or guessed width.',
        persistence='HYP 2 intermittent, 3 ephemeral, 4 dry and unknown omitted. Names identifying the object itself as engineering or a dry channel also excluded; reach endpoints may mention modern dams.',
        scope='Mainland, Balearics and separate Canary bounded queries; transboundary named main rivers retained to geographic query edges, not clipped at political border.')
    return [source]


def features(region,bounds):
    raw=json.loads((ROOT/'data/world_map/historical/cshapes_1900_snapshot.json').read_text(encoding='utf8'))
    scope=shape(next(f for f in raw['features'] if f['gwcode']==230)['geometry']).intersection(box(*bounds)).buffer(.6)
    # Whole geographic cells preserve a nonpolitical collar. Primary cross-
    # border rivers additionally keep their genuine Portuguese downstream parts.
    geographic=unary_union([box(x,y,x+2,y+2) for x in range(-20,6,2) for y in range(26,46,2) if box(x,y,x+2,y+2).intersects(scope)])
    area=transform(shared.TO_METRES,geographic.intersection(box(*bounds)))
    query_area=transform(shared.TO_METRES,box(*bounds))
    groups=collections.defaultdict(list); source_ids=collections.defaultdict(list); stats=collections.Counter()
    for file in sorted(WORK.glob(region+'_rivers_*.geojson')):
        for f in json.loads(file.read_text(encoding='utf8'))['features']:
            p=f['properties']; name=(p.get('nameText') or p.get('nameTxtInt') or '').strip()
            if name in ['UNK','NA']: name=''
            if p.get('HYP')!=1: stats['excluded_persistence']+=1; continue
            if ENGINEERING.search(name): stats['excluded_engineering_or_dry_channel_name']+=1; continue
            rank=int(p['STRAHLER']); named_main=bool(PRIMARY.match(name)); primary=rank>=6 or named_main
            g=transform(shared.TO_METRES,shared.flat_geometry(f['geometry'])).intersection(query_area if named_main else area)
            lines=shared.parts(g,'LineString')
            if not lines: continue
            key=(name or 'unnamed',rank,primary)
            groups[key].extend(lines); source_ids[key].append(p['OBJECTID']); stats['river_source_parts']+=1
    result=[]
    for index,(key,lines) in enumerate(sorted(groups.items())):
        name,rank,primary=key
        g=linemerge(MultiLineString(lines)) if len(lines)>1 else lines[0]
        result.append(dict(id=f'river:{region}_r45_{index}',kind='river',name=name if name!='unnamed' else f'Unnamed modern watercourse order {rank}',
            geometry=g,main=primary,source='eu_hydro_spain_r45',rank=rank,
            stroke_scale=1.45 if rank>=8 else 1.20 if rank>=6 else .95 if primary else .55,
            source_notes=dict(source_object_ids=source_ids[key],hydrological_persistence=1,
                meaning='Source modern perennial classification, not a 1900 flow or riverbank claim. No missing endpoints joined.')))
    properties=[]; shapes=[]
    for f in json.loads((WORK/(region+'_lakes.geojson')).read_text(encoding='utf8'))['features']:
        p=f['properties']
        if p['LKE_TYPE']!='N': continue
        g=transform(shared.TO_METRES,shared.flat_geometry(f['geometry'])).intersection(area)
        if shared.parts(g,'Polygon'): properties.append(p); shapes.append(g)
    tree=STRtree(shapes)
    for index,g in enumerate(sorted(shared.parts(unary_union(shapes),'Polygon'),key=lambda p:p.bounds)):
        ids=[int(i) for i in tree.query(g) if g.intersection(shapes[int(i)]).area>.1]
        names=sorted({properties[i]['NAM'].strip() for i in ids if properties[i]['NAM']!='UNK'})
        result.append(dict(id=f'lake:{region}_r45_{index}',kind='lake',name=' / '.join(names) or 'Unnamed modern natural water reference',
            geometry=g,main=g.area>=4000000,source='eu_hydro_spain_r45',rank=None,
            source_notes=dict(source_object_ids=[properties[i]['OBJECTID'] for i in ids],source_lake_type='N',
                display_operation='Union of source natural water polygons, not legal water ownership. No R reservoir or U unknown class.')))
    stats['grouped_rivers']=len(groups); stats['water_components']=len(result)-len(groups)
    (WORK/(region+'_source_summary.json')).write_text(json.dumps(stats,indent=2),encoding='utf8')
    return result


if __name__=='__main__':
    acquire(); descriptors=[]; records=[]
    for region,bounds in REGIONS:
        items=features(region,bounds); w,s,e,n=bounds
        overview=shared.write_shard(region+'_hydro_overview_r45',[(v,v['geometry']) for v in items if v['main']],
            [w,e,s,n],True,registry(),'tools/map/build_spain_hydro_r45.py')
        if overview: descriptors.append(overview)
        for lat in range(int(s)//4*4,int(n)+1,4):
            for lon in range(int(w)//4*4,int(e)+1,4):
                b=[max(w,lon),min(e,lon+4),max(s,lat),min(n,lat+4)]
                if b[0]>=b[1] or b[2]>=b[3]: continue
                core=transform(shared.TO_METRES,box(b[0],b[2],b[1],b[3]))
                entries=[(v,v['geometry'].intersection(core)) for v in items if not v['main'] and v['geometry'].intersects(core)]
                d=shared.write_shard(f'{region}_hydro_{lat}_{lon:+d}_r45',entries,b,False,registry(),'tools/map/build_spain_hydro_r45.py')
                if d: d['max_mpp']=250.; descriptors.append(d)
        records.extend(dict(id=v['id'],kind=v['kind'],name=v['name'],main=v['main'],source=v['source'],order=v['rank']) for v in items)
    path=ROOT/'data/strategic/index.json'; index=json.loads(path.read_text(encoding='utf8'))
    index['hydro_regions']=[d for d in index.get('hydro_regions',[]) if not (str(d['id']).startswith(('spain_hydro_','canary_hydro_')) and str(d['id']).endswith('_r45'))]+descriptors
    path.write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    (WORK/'runtime_summary.json').write_text(json.dumps(dict(descriptors=descriptors,features=records),ensure_ascii=False,indent=2),encoding='utf8')
    print('Runtime shards',len(descriptors),'bytes',sum(d['bytes']+d['geometry_bytes'] for d in descriptors),flush=True)
