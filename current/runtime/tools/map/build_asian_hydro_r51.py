"""R51 source water on existing optional hydro shards, Central Asia then Far East.

Natural Earth is a cartographic reference, not a 1900 river-bank survey. No
drainage inference, artificial width, formal ownership, or simulation input.
"""
from pathlib import Path
import json,sys,zlib,collections
import numpy as np
from pyproj import CRS,Transformer
from shapely.geometry import shape,box,Polygon
from shapely.ops import transform,unary_union
import build_british_hydro_r43 as shared
import build_siberian_hydro_r50 as sib

ROOT=shared.ROOT;WORK=ROOT/'local-artifacts/asian-surface-r51/hydro';OUT=ROOT/'data/strategic'
CA_DOMAIN=Polygon([(48,40),(50,36),(58,34),(66,34),(72,35),(78,36),(84,40),(92,46),(92,56),(44,56),(44,46)])
FE_DOMAIN=unary_union([box(114,40,180,78),box(-180,59,-168,78)])
CA_NAMES={'Ural','Syr  Darya','Naryn','Pamir','Panj','Amu  Darya','Ile','Künes','Atrek','Harirud','Zarafshon'}
FE_NAMES={'Herlen','Selemdzha','Nemor','Penzhina','Anadyr’','Kamchatka','Songhua','Zeya','Ingoda','Shilka',
 'Ussuri','Amur','Onon','Hailar','Nanweng','Amgun’','Chaor','Bikin','Kukhtuy','Argun’','Heilong Jiang',
 'Nen','Uda','Tumnin','Poronay','Palyavaam','Muling','Song’acha','Di’er Songhua','Tao’er','Erdao'}
PRIMARY={'Syr  Darya','Amu  Darya','Ural','Ile','Amur','Heilong Jiang','Ussuri','Shilka','Argun’','Songhua','Zeya','Anadyr’','Kamchatka'}
UNSUITABLE={1159126555:'modern South Aral remnant',1729983019:'modern Barsakelmes remnant',1729982865:'modern North Aral engineering/remnant',
 1159126775:'Sarygamysh modern irrigation expansion after1961',1159127033:'Aydar-Arnasay artificial flooding after1969',1159122817:'Songhua Hu / Fengman twentieth-century impoundment'}

def registry():
    src=sib.registry()[0];src['source_id']='ne_asian_hydro_r51';src['title']='Central Asia and Far East retained Natural Earth10m reference'
    hist=dict(source_id='ne_aral_late1950s_r51',title='Natural Earth historic Aral Sea, source date late1950s',publisher='Natural Earth contributors',version='v5.1.2:historic-layer5.0.0',license='PUBLIC_DOMAIN',locator='https://github.com/nvkelso/natural-earth-vector/blob/v5.1.2/geojson/ne_10m_lakes_historic.geojson',access_metadata=dict(horizontal_crs='EPSG:4326',scale='1:10,000,000 generalised cartography',source_date='late1950s, verbatim source attribute; not1900',ne_id=1159110427,licence_url='https://www.naturalearthdata.com/about/terms-of-use/',historical_applicability='Pre-collapse visual reference roughly55-59years after1900. No precise1900 level, shore, navigation, land area or sovereignty assertion. Source holes retained.'))
    return [src,hist]

def configure(stage):
    centre=(68,45) if stage=='central' else (160,60)
    metric=CRS.from_proj4(f'+proj=laea +lat_0={centre[1]} +lon_0={centre[0]} +datum=WGS84 +units=m +no_defs')
    shared.TO_METRES=Transformer.from_crs(4326,metric,always_xy=True).transform
    shared.TO_DEGREES=Transformer.from_crs(metric,4326,always_xy=True).transform

def items(stage):
    configure(stage);domain=CA_DOMAIN if stage=='central' else FE_DOMAIN;names=CA_NAMES if stage=='central' else FE_NAMES
    old=json.loads((ROOT/'local-artifacts/siberian-surface-r50/hydro/runtime_summary.json').read_text(encoding='utf8'))['objects']
    old_rivers={x['original_record'] for x in old if x['kind']=='river'};old_lakes={x['ne_id'] for x in old if x['kind']=='lake'}
    historic=json.loads((ROOT/'local-artifacts/asian-surface-r51/history/ne_10m_lakes_historic.geojson').read_text(encoding='utf8'))
    aral=shape(next(f['geometry'] for f in historic['features'] if f['properties'].get('ne_id')==1159110427))
    result=[];inventory=[];excluded=[];reused=[]
    for i,f in enumerate(json.loads(sib.RIVERS.read_text(encoding='utf8'))['features']):
        p=f['properties'];name=p.get('name') or '';g=shape(f['geometry'])
        if name not in names or not g.intersects(domain) or p['featurecla'] not in ['River','Lake Centerline']:continue
        g=g.intersection(domain)
        if i in old_rivers:
            reused.append(dict(kind='river',original_record=i,name=name))
            # R50 clipped river axes to its actual Siberian support. Reuse
            # that portion, not the entire source record beyond its domain.
            g=g.difference(sib.DOMAIN)
        if stage=='central':g=g.difference(aral)
        if g.is_empty:continue
        e=dict(id=f'river:asian_ne10m_record_{i}',kind='river',name=name,source='ne_asian_hydro_r51',geometry=transform(shared.TO_METRES,g),geometry_ll=g,main=name in PRIMARY or float(p.get('scalerank',9))<=7,rank=p.get('scalerank'),stroke_scale=1.35 if name in PRIMARY else 1.0 if float(p.get('scalerank',9))<=7 else .62,source_date='Natural Earth v5.1.2 composite',observation_period={'from':'1990-01-01','to':'2022-12-31'},source_notes=dict(original_record=i,rivernum=p['rivernum'],category=p['featurecla'],historical_channel='Unconfirmed where twentieth-century dams or irrigation changed the channel. No width or flow simulation.'))
        result.append(e);inventory.append(dict(id=e['id'],kind='river',name=name,original_record=i,category=p['featurecla'],main=e['main']))
    for i,f in enumerate(json.loads(sib.LAKES.read_text(encoding='utf8'))['features']):
        p=f['properties'];g=shape(f['geometry'])
        if not domain.contains(g.representative_point()):continue
        ident=p['ne_id'];reason='source Reservoir classification' if p['featurecla']=='Reservoir' else UNSUITABLE.get(ident,'')
        if reason:excluded.append(dict(ne_id=ident,name=p.get('name'),category=p['featurecla'],reason=reason));continue
        if p['featurecla'] not in ['Lake','Alkaline Lake']:continue
        if ident in old_lakes:reused.append(dict(kind='lake',ne_id=ident,name=p.get('name')));continue
        gm=transform(shared.TO_METRES,g)
        e=dict(id=f'lake:asian_ne10m_{ident}',kind='lake',name=p.get('name') or f'Natural Earth lake {ident}',source='ne_asian_hydro_r51',geometry=gm,main=float(p.get('scalerank',9))<=6,rank=p.get('scalerank'),source_date='Natural Earth v5.1.2 composite',observation_period={'from':'1990-01-01','to':'2022-12-31'},source_notes=dict(ne_id=ident,original_record=i,category=p['featurecla'],water_class='source_natural_lake_modern_extent',historical_water_level='Not reconstructed'))
        e['geometry_ll']=g
        result.append(e);inventory.append(dict(id=e['id'],kind='lake',name=e['name'],ne_id=ident,main=e['main']))
    if stage=='central':
        e=dict(id='lake:aral_late1950s_reference_r51',kind='lake',name='咸海：1950年代后期水面参考（非1900精测）',source='ne_aral_late1950s_r51',geometry=transform(shared.TO_METRES,aral),main=True,rank=3,source_date='late1950s',observation_period={'from':'1955-01-01','to':'1959-12-31'},source_notes=dict(ne_id=1159110427,source_date_literal='late 1950s',year_interval='Approximate interpretation of late1950s, not dated survey',historical_applicability='Pre-collapse reference only; not an exact1900 shoreline'))
        result.append(e);inventory.append(dict(id=e['id'],kind='historical_lake_reference',name=e['name'],main=True,source_holes=len(aral.interiors),bounds=list(aral.bounds)))
        e['geometry_ll']=aral
    return result,inventory,excluded,reused

def write(name,entries,bounds,overview):
    d=shared.write_shard(name,entries,bounds,overview,registry(),'tools/map/build_asian_hydro_r51.py')
    if not d:return None
    path=OUT/(name+'.json');doc=json.loads(path.read_text(encoding='utf8'))
    for fact in doc['evidence_catalog']['facts']:
        f=fact['value']
        if f['source_id']=='ne_aral_late1950s_r51':
            f.update(water_class='historical_lake_reference',geometry_role='HISTORICAL_PRECOLLAPSE_LAKE_REFERENCE_SOURCE_LATE1950S',uncertainty='Not1900 shoreline; source date late1950s. Legal land, ownership and query topology unchanged.')
            fact['methodology']='Actual historic Aral polygon; source late1950s; metric display simplification and constrained triangles retain islands. No1900 interpolation.'
    path.write_text(json.dumps(doc,ensure_ascii=False,separators=(',',':')),encoding='utf8');d['bytes']=path.stat().st_size
    return d

def build(stage):
    WORK.mkdir(parents=True,exist_ok=True);features,inventory,excluded,reused=items(stage);descriptors=[]
    # Normalised, independent geographic halves for date-line demand. Whole
    # source features are not joined across +/-180 in lon/lat geometry.
    regions=[('central', [44,92,30,56])] if stage=='central' else [('far_east',[114,180,40,78]),('chukchi_west',[-180,-168,59,78])]
    for region,b in regions:
        cut=box(b[0],b[2],b[1],b[3])
        inverse=Transformer.from_crs(CRS.from_proj4(f'+proj=laea +lat_0={45 if stage=="central" else 60} +lon_0={68 if stage=="central" else 160} +datum=WGS84 +units=m +no_defs'),4326,always_xy=True).transform
        def degrees(x,y):
            lon,lat=inverse(x,y);a=np.asarray(lon)
            a=a+360*np.round(((b[0]+b[1])*.5-a)/360)
            a=np.clip(a,-180,180)
            return (float(a),lat) if a.ndim==0 else (a,lat)
        shared.TO_DEGREES=degrees
        # Clip source coordinates before metric processing. A four-corner
        # projected rectangle is not an exact meridian/parallel footprint.
        major=[(e,transform(shared.TO_METRES,e['geometry_ll'].intersection(cut))) for e in features if e['main'] and e['geometry_ll'].intersects(cut)]
        d=write(f'asian_hydro_{region}_overview_r51',major,b,True)
        if d:descriptors.append(d)
        for yy in range((b[2]//4)*4,b[3],4):
            for xx in range((b[0]//4)*4,b[1],4):
                core=box(max(xx,b[0]),max(yy,b[2]),min(xx+4,b[1]),min(yy+4,b[3]))
                entries=[(e,transform(shared.TO_METRES,e['geometry_ll'].intersection(core))) for e in features if not e['main'] and e['geometry_ll'].intersects(core)]
                d=write(f'asian_hydro_{region}_{yy}_{xx:+d}_r51',entries,[max(xx,b[0]),min(xx+4,b[1]),max(yy,b[2]),min(yy+4,b[3])],False) if entries else None
                if d:d['max_mpp']=500.;descriptors.append(d)
    index_path=OUT/'index.json';idx=json.loads(index_path.read_text(encoding='utf8'))
    prefixes=['asian_hydro_central_'] if stage=='central' else ['asian_hydro_far_east_','asian_hydro_chukchi_west_']
    idx['hydro_regions']=[d for d in idx.get('hydro_regions',[]) if not any(d['id'].startswith(p) for p in prefixes)]+descriptors
    # R50 retained whole natural lakes south of its nominal 46N frame (e.g.
    # Balkhash). Demand the actual source extent instead of duplicating them.
    overview=next(d for d in idx['hydro_regions'] if d['id']=='siberian_hydro_overview_r50')
    geo=json.loads(zlib.decompress((ROOT/overview['path'][6:]).with_suffix('.geom').read_bytes()))
    bounds=[shape(v['geometry']).bounds for v in geo.values() if v.get('geometry')]
    overview['bounds']=[min(b[0] for b in bounds),max(b[2] for b in bounds),min(b[1] for b in bounds),max(b[3] for b in bounds)]
    index_path.write_text(json.dumps(idx,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    summary=dict(counts=dict(collections.Counter(e['kind'] for e in inventory)),objects=inventory,reused_r50=reused,excluded=excluded,descriptors=descriptors,bytes=sum(d['bytes']+d['geometry_bytes'] for d in descriptors))
    (WORK/f'{stage}_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8');print(stage,summary['counts'],'reused',len(reused),'shards',len(descriptors),'bytes',summary['bytes'],flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8');build(sys.argv[1])
