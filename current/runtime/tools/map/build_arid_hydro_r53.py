"""Existing hydro shards: unknown-regime axes, explicit playas, Nile and canals.

No climate/name-based perennial or dry classification; no1900 reservoir banks.
"""
from pathlib import Path
import sys,json,collections,zlib
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'local-artifacts/gis-python'))
import fiona
from pyproj import CRS,Transformer
from shapely.geometry import shape,box,Polygon,Point
from shapely.ops import transform,unary_union,linemerge
import build_british_hydro_r43 as shared
import build_northern_hydro_r52 as northern
import build_siberian_hydro_r50 as sources

ROOT=shared.ROOT;WORK=ROOT/'local-artifacts/arid-surface-r53';OUT=ROOT/'data/strategic'
ARABIA=Polygon([(34,29),(36,32),(43,33),(48,31),(49,28),(52,26),(56.6,26),(60,24),(61,18),(54,12),(44,11),(38,17)])
AFRICA=Polygon([(-20,19),(-16,18),(28,18),(34,14),(37,16),(37,22),(36,28),(35.5,31.5),(33,33),(-6,37),(-16,32)])

def acquire():
    import requests,zipfile
    directory=WORK/'source';directory.mkdir(parents=True,exist_ok=True)
    for url,name,folder in [
        ('https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_playas.geojson','ne_10m_playas.geojson',None),
        ('https://data.hydrosheds.org/file/HydroRIVERS/HydroRIVERS_v10_af_shp.zip','HydroRIVERS_v10_af_shp.zip','hydrorivers_af'),
        ('https://data.hydrosheds.org/file/hydrolakes/HydroLAKES_polys_v10_shp.zip','HydroLAKES_polys_v10_shp.zip','hydrolakes')]:
        target=directory/name
        if not target.exists():
            temporary=target.with_suffix('.download')
            with requests.get(url,stream=True,timeout=120) as response:
                response.raise_for_status()
                with temporary.open('wb') as output:
                    for block in response.iter_content(1048576):output.write(block)
            temporary.replace(target)
        if folder and not (directory/folder).exists():
            with zipfile.ZipFile(target) as archive:archive.extractall(directory/folder)
        print('retained',name,target.stat().st_size,flush=True)
    # The original EU/Middle East HydroRIVERS archive is retained by R52.

def registry():
    old=northern.registry()
    ne=dict(old[0],source_id='ne_arid_hydro_r53',title='Natural Earth Nile axes, canal axes and explicit salt pan references')
    ne['access_metadata']=dict(ne.get('access_metadata',{}),categories='River/lake-centreline axes; explicit Playa=salt pan/intermittent lake, not permanent water. Desert label polygons are not used as land cover.',historical_canals='Suez existed1869; modern generalized single axis is not a1900 bank or width survey.',history_url='https://www.suezcanal.gov.eg/English/About/SuezCanal/Pages/CanalHistory.aspx')
    hyd=dict(old[1],source_id='hydrorivers_arid_r53',title='HydroRIVERS v1 Europe/Middle East and Africa clipped routed network',version='HydroRIVERS_v10_eu+af')
    hyd['access_metadata']=dict(hyd['access_metadata'],water_regime='Not present in source: all routed network axes retain unknown regime and neutral dashed ink. No name, discharge or dry climate inference.')
    lake=dict(hyd,source_id='hydrolakes_arid_r53',title='HydroLAKES v1 selected named natural lakes and lagoons',version='HydroLAKES_v10',license='CC-BY-4.0',locator='https://www.hydrosheds.org/products/hydrolakes')
    lake['access_metadata']=dict(horizontal_crs='EPSG:4326',vertical_datum='Not applicable to lake outline',sampling='Composite approximately1:100000 to1:1million; source IDs and lake type retained',source_epoch='HydroLAKES2016 composite, predominantlySRTM/SWBD2000 and source maps; not1900',attribution='Messager M.L. et al.(2016), Estimating the volume and age of water stored in global lakes using a geo-statistical approach, Nature Communications7:13603, https://doi.org/10.1038/ncomms13603',license_url='https://creativecommons.org/licenses/by/4.0/',distribution='Selected clipped/simplified WWO derivatives; original global database retained in research, not packaged')
    oasis=dict(source_id='unesco_siwa_point_r53',title='Siwa oasis representative coordinate, UNESCO oasis catalogue; FAO historical description',publisher='UNESCO World Heritage Centre; FAO GIAHS',version='UNESCO document160478; FAO Siwa GIAHS2016, accessed2026-10-19',license='Factual-coordinate-extraction-with-attribution',locator='https://whc.unesco.org/document/160478',access_metadata=dict(coordinate_original='29°11\'59.3"N 25°31\'18.7"E',horizontal_crs='Geographic coordinate; displayed as WGS84 approximation, survey datum/accuracy unstated',history='https://www.fao.org/giahs/around-the-world/detail/egypt-siwa-oasis/',use='Representative point only. No copied maps/images/text, polygon,1900 agricultural area, population or water-yield assertion.'))
    return [ne,hyd,lake,oasis]

def configure(stage):
    shared.OUT=OUT
    lon,lat=(48,23) if stage=='arabia' else (15,28)
    crs=CRS.from_proj4(f'+proj=laea +lat_0={lat} +lon_0={lon} +datum=WGS84 +units=m')
    shared.TO_METRES=Transformer.from_crs(4326,crs,always_xy=True).transform
    shared.TO_DEGREES=Transformer.from_crs(crs,4326,always_xy=True).transform

def routed(stage,domain):
    folder=ROOT/'local-artifacts/caucasus-nordic-r52/source/hydrorivers_eu' if stage=='arabia' else WORK/'source/hydrorivers_af'
    shp=next(folder.rglob('*.shp'));groups=collections.defaultdict(list);records=collections.defaultdict(list)
    with fiona.open(shp) as src:
        for f in src.filter(bbox=domain.bounds):
            p=dict(f.properties)
            if p['ORD_STRA']<4:continue
            # Nile and both delta branches have one explicit NE axis owner.
            # HydroRIVERS single-flow topology must not overwrite bifurcations.
            if stage=='africa' and p['MAIN_RIV'] in [10047863,10050558]:continue
            g=shape(f.geometry).intersection(domain)
            if g.is_empty:continue
            main=p['ORD_STRA']>=6;stroke=1.0 if main else .65;key=(p['MAIN_RIV'],main,stroke)
            groups[key].append(g);records[key].append(dict(hyriv_id=p['HYRIV_ID'],next_down=p['NEXT_DOWN'],order=p['ORD_STRA']))
    if stage=='arabia':
        # Peninsula basins only. The actual source outlet, not a country or
        # inferred dry climate, prevents parallel Tigris/Euphrates axes.
        basin_ids=sorted({k[0] for k in groups});keep=set()
        with fiona.open(shp) as src:
            for f in src.filter(where='HYRIV_ID IN ('+','.join(map(str,basin_ids))+')'):
                if domain.contains(shape(f.geometry).representative_point()):keep.add(f.properties['HYRIV_ID'])
        groups={k:v for k,v in groups.items() if k[0] in keep}
    result=[]
    for key,geoms in sorted(groups.items()):
        basin,main,stroke=key;g=unary_union(geoms)
        if g.geom_type=='MultiLineString':g=linemerge(g)
        result.append(dict(id=f'river:arid_r53_{stage}_{basin}_{int(stroke*100)}',kind='river',name=f'HydroRIVERS {basin} (regime unknown)',source='hydrorivers_arid_r53',geometry_ll=g,main=main,rank=5 if main else 8,stroke_scale=stroke,water_line_style='unknown',source_date='HydroRIVERS v1 modern routed reference',observation_period={'from':'1970-01-01','to':'2013-12-31'},source_notes=dict(main_riv=basin,original_reaches=records[key],water_regime='unknown; source has no perennial/intermittent field',historical_applicability='Not1900 surveyed channel banks; no arbitrary river width or dry-valley assertion')))
    return result

def references(stage,domain):
    result=[];excluded=[]
    for i,f in enumerate(json.loads((WORK/'source/ne_10m_playas.geojson').read_text(encoding='utf8'))['features']):
        p=f['properties'];g=shape(f['geometry'])
        if not domain.contains(g.representative_point()):continue
        result.append(dict(id=f'lake:arid_playa_r53_{p["ne_id"]}',kind='lake',water_class='playa_reference',name=p['name'] or 'Source salt pan / intermittent lake',geometry_ll=g,source='ne_arid_hydro_r53',main=True,rank=p['scalerank'],source_date='Natural Earth v5.1.2 composite',observation_period={'from':'1990-01-01','to':'2022-12-31'},source_notes=dict(ne_id=p['ne_id'],category='Playa',water_regime='Salt pan/intermittent lake; neutral basin ink, no permanent blue water. No1900 seasonal level recovered.')))
    for f in json.loads(sources.LAKES.read_text(encoding='utf8'))['features']:
        p=f['properties'];g=shape(f['geometry'])
        if domain.intersects(g) and p['featurecla']=='Reservoir':excluded.append(dict(ne_id=p['ne_id'],name=p['name'],category='Reservoir',decision='No1900 natural lake surface'))
    if stage=='africa':
        raw=json.loads(sources.RIVERS.read_text(encoding='utf8'))['features']
        africa_doc=json.loads((OUT/'africa.json').read_text(encoding='utf8'))
        old=next(f['value'] for f in africa_doc['evidence_catalog']['facts'] if f['value']['id']=='river:nile')
        packed=json.loads(zlib.decompress((ROOT/old['geometry_asset']['path'][6:]).read_bytes()))
        remainder=shape(packed['river:nile']['geometry']).difference(domain)
        axes=[shape(f['geometry']).intersection(domain) for f in raw if f['properties']['name']=='Nile']
        g=unary_union([remainder]+axes)
        result.append(dict(id='river:arid_nile_r53',kind='river',name='Nile (modern axis reference)',geometry_ll=g,source='ne_arid_hydro_r53',main=True,rank=1,water_line_style='perennial',stroke_scale=1.2,display_replaces=['river:nile'],source_date='Natural Earth v5.1.2',observation_period={'from':'1990-01-01','to':'2022-12-31'},source_notes=dict(rivernum=4,source_records=[i for i,f in enumerate(raw) if f['properties']['name']=='Nile'],outside_domain='Original river:nile source geometry retained, no lost southern remainder',reservoir_crossing='Lake Centerline is only a modern generalized axis through Nasser; not1900 channel banks, reservoir footprint or recovered flooded-valley DEM.')))
        for name in ['Rosetta Branch','Damietta Branch','Suez Canal']:
            ids=[i for i,f in enumerate(raw) if f['properties']['name']==name]
            g=unary_union([shape(raw[i]['geometry']) for i in ids])
            if g.is_empty:continue
            canal='Canal' in name
            result.append(dict(id='river:arid_ne_r53_'+str(ids[0]),kind='river',name=name,geometry_ll=g,source='ne_arid_hydro_r53',main=True,rank=1 if not canal else 6,water_line_style='canal' if canal else 'perennial',stroke_scale=1.0 if not canal else .85,source_date='Natural Earth v5.1.2 generalized axis',observation_period={'from':'1990-01-01','to':'2022-12-31'},source_notes=dict(original_records=ids,source_class='Artificial canal' if canal else 'River branch',historical_applicability='Pre1900 canal existence separately documented; modern axis only, no1900 width, bypasses, traffic or transport assertion.' if canal else 'Modern branch axis; no1900 bank survey',history_url='https://www.suezcanal.gov.eg/English/About/SuezCanal/Pages/CanalHistory.aspx' if canal else None)))
    return result,excluded

def selected_lakes():
    shp=next((WORK/'source/hydrolakes').rglob('*.shp'));result=[]
    # Selection requires containing the specified geographic anchor AND natural
    # source classification. No nearest-lake guessing or reservoir rebadging.
    anchors={'Burullus':(30.85,31.48),'Manzala':(32.03,31.25),'Qarun':(30.62,29.47),'Maryut':(29.88,31.10),'Bardawil':(33.14,31.10),'Great Bitter Lake':(32.43,30.32)}
    with fiona.open(shp) as src:
        for name,xy in anchors.items():
            for f in src.filter(bbox=(xy[0]-.01,xy[1]-.01,xy[0]+.01,xy[1]+.01)):
                p=dict(f.properties);g=shape(f.geometry)
                if not g.contains(Point(xy)) or int(p['Lake_type'])!=1:continue
                result.append(dict(id=f'lake:arid_hydrolakes_r53_{p["Hylak_id"]}',kind='lake',name=(name+' (source component)' if not p.get('Lake_name') else name),geometry_ll=g,source='hydrolakes_arid_r53',main=True,rank=5,source_date='HydroLAKES v1.0 composite2016',observation_period={'from':'1990-01-01','to':'2016-12-31'},source_notes=dict(hylak_id=p['Hylak_id'],source_attributes=p,identity_anchor=xy,historical_applicability='Modern natural lake/lagoon reference; no1900 shore, reclamation or water-level reconstruction')))
    return result

def write(name,pairs,bounds,overview):
    entries=[(dict(e,geometry=transform(shared.TO_METRES,g)),transform(shared.TO_METRES,g)) for e,g in pairs if not g.is_empty]
    d=shared.write_shard(name,entries,bounds,overview,registry(),'tools/map/build_arid_hydro_r53.py')
    if not d:return None
    doc=json.loads((OUT/(name+'.json')).read_text(encoding='utf8'))
    lookup={e['id']+':'+name:e for e,g in pairs}
    for fact in doc['evidence_catalog']['facts']:
        feature=fact['value'];e=lookup[feature['id']]
        for key in ['water_line_style','water_class']:
            if key in e:feature[key]=e[key]
        if e.get('water_class')=='playa_reference':feature['geometry_role']='SOURCED_SALT_PAN_INTERMITTENT_BASIN_DISPLAY_NOT_PERMANENT_WATER'
    if name=='arid_hydro_sahara_overview_r53':
        src=registry()[-1];ident='geographic_reference:siwa_oasis_r53'
        feature=dict(id=ident,kind='settlement',display_name='锡瓦绿洲·位置参考',source_id=src['source_id'],source_type='PHYSICAL_REFERENCE',source_date='UNESCO document160478 contemporary coordinate; FAO2016 history',valid_from='1900-01-01',valid_to='9999-12-31',confidence=.7,geometry=dict(type='Point',coordinates=[25+31/60+18.7/3600,29+11/60+59.3/3600]),geometry_role='GEOGRAPHIC_OASIS_REPRESENTATIVE_POINT_NOT_FORMAL_SETTLEMENT',rank=7,max_mpp=1000.,map_symbol='settlement',source_name_zh='UNESCO绿洲目录坐标；FAO锡瓦绿洲历史说明',source_reference=src['locator'],uncertainty='绿洲代表点；基准与测绘误差未给。无1900年面积、现代农业范围或人口断言。')
        doc['evidence_catalog']['facts'].append(dict(fact_id='strategic_spatial:'+ident,domain='strategic_spatial_content',subject_id=ident,value=feature,unit='display_geography',source_id=src['source_id'],source_version=src['version'],source_locator=src['locator'],observation_period={'from':'2016-01-01','to':'2026-10-19'},spatial_scope=dict(kind='content_shard',id=name),methodology='Published DMS representative point only; no buffer or oasis-area inference. Existing genericR47 symbol, no world settlement created.',confidence=.7,lower_bound=None,upper_bound=None,license=src['license'],review_status='APPROXIMATE',generator='tools/map/build_arid_hydro_r53.py'))
        d['feature_count']+=1;d['counts']['settlement']=1
    p=OUT/(name+'.json');p.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':')),encoding='utf8');d['bytes']=p.stat().st_size;return d

def build(stage):
    configure(stage);domain=ARABIA if stage=='arabia' else AFRICA
    river=routed(stage,domain);refs,excluded=references(stage,domain)
    if stage=='africa':refs.extend(selected_lakes())
    items=river+refs;descriptors=[]
    # Coarse source groups are geographically partitioned; river remainder is
    # wholly owned by its Nile overview rather than cut by a new clipping box.
    frames=[('arabia',[34,62,10,34])] if stage=='arabia' else [('maghreb',[-20,12,18,38]),('sahara',[12,28,18,36]),('nile',[28,38,14,34])]
    for region,b in frames:
        core=box(b[0],b[2],b[1],b[3]);pairs=[]
        for e in items:
            g=e['geometry_ll']
            if not e['main'] or not g.intersects(core):continue
            pairs.append((e,g if e['id']=='river:arid_nile_r53' else g.intersection(core)))
        d=write(f'arid_hydro_{region}_overview_r53',pairs,b,True)
        if d:descriptors.append(d)
        for y in range(b[2]//4*4,b[3],4):
            for x in range(b[0]//4*4,b[1],4):
                frame=[max(x,b[0]),min(x+4,b[1]),max(y,b[2]),min(y+4,b[3])];cut=box(frame[0],frame[2],frame[1],frame[3])
                pairs=[(e,e['geometry_ll'].intersection(cut)) for e in items if not e['main'] and e['geometry_ll'].intersects(cut)]
                d=write(f'arid_hydro_{region}_{y}_{x:+d}_r53',pairs,frame,False) if pairs else None
                if d:d['max_mpp']=500.;descriptors.append(d)
    p=OUT/'index.json';idx=json.loads(p.read_text(encoding='utf8'));prefix='arid_hydro_arabia_' if stage=='arabia' else ('arid_hydro_maghreb_','arid_hydro_sahara_','arid_hydro_nile_')
    idx['hydro_regions']=[v for v in idx.get('hydro_regions',[]) if not v['id'].startswith(prefix)]+descriptors
    p.write_text(json.dumps(idx,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    result=dict(stage=stage,shards=descriptors,bytes=sum(d['bytes']+d['geometry_bytes'] for d in descriptors),river_groups=len(river),original_reaches=sum(len(e['source_notes']['original_reaches']) for e in river),references=[dict(id=e['id'],name=e['name'],kind=e['kind'],water_class=e.get('water_class'),water_line_style=e.get('water_line_style'),source_notes=e['source_notes']) for e in refs],excluded_reservoirs=excluded)
    (WORK/f'{stage}_hydro_summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8');print(stage,'shards',len(descriptors),'river groups',len(river),'reaches',result['original_reaches'],'references',len(refs),'bytes',result['bytes'],flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8')
    if sys.argv[1]=='acquire':acquire()
    else:build(sys.argv[1])
