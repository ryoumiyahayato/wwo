"""Siberian display hydrography from retained Natural Earth 10m originals.

Offline producer for the existing optional StrategicSpatialLoader contract.
No inferred drainage, historical bank reconstruction, width, or world facts.
"""
from pathlib import Path
import json,sys,zlib,collections
from pyproj import CRS,Transformer
from shapely.geometry import shape,box,Polygon
from shapely.ops import transform,unary_union
import build_british_hydro_r43 as shared

ROOT=shared.ROOT
WORK=ROOT/'local-artifacts/siberian-surface-r50/hydro'
RIVERS=ROOT/'local-artifacts/geographic-foundation-r1/source/ne_10m_rivers_lake_centerlines.geojson'
LAKES=ROOT/'local-artifacts/global-strategic-r1/source/ne_10m_lakes.geojson'
DOMAIN=unary_union([box(54,46,118,84),
 Polygon([(110,50),(116,50),(124,53),(132,57),(144,62),(156,62),(156,82),(110,82)]),
 box(148,61,176,82)])
# Metric processing only; the exported geometry remains the common WGS84 grid.
METRIC=CRS.from_proj4('+proj=laea +lat_0=65 +lon_0=110 +datum=WGS84 +units=m +no_defs')
shared.TO_METRES=Transformer.from_crs(4326,METRIC,always_xy=True).transform
shared.TO_DEGREES=Transformer.from_crs(METRIC,4326,always_xy=True).transform
OUT=ROOT/'data/strategic'
EXCLUDE_RIVERS={'Belaya','Usa','Ural','Pechora','Vychegda','Kama','Chusovaya','Vishera',
 'Herlen','Selemdzha','Nemor','Penzhina','Anadyr’','Kamchatka','Songhua','Zeya','Ingoda',
 'Shilka','Ussuri','Amur','Onon','Hailar','Nanweng','Amgun’','Chaor','Bikin','Kukhtuy',
 'Argun’','Heilong Jiang','Nen','Uda','Tumnin','Poronay','Palyavaam'}
MAIN={'Ob','Malaya Ob','Irtysh','Ertis','Ertix','Tobol','Ishim','Esil','Tom’','Chulym',
 'Bol’shoy Yugan','Vasyugan','Yenisey','Verkhniy Yenisey','Malyy Yenisey','Bol’shoy Yenisey',
 'Angara','Lower Tunguska','Podkamennaya Tunguska','Lena','Aldan','Vilyuy','Olëkma',
 'Vitim','Selenga','Yana','Indigirka','Kolyma','Kheta','Kotuy','Khatanga','Pyasina',
 'Anabar','Olenëk','Trofimovskaya Protoka','Tumatskaya Protoka','Bykovskaya Protoka','Olenekskaya Protoka'}

def registry():
    return [dict(source_id='ne_siberian_hydro_r50',title='Natural Earth 1:10m rivers and lakes, retained v5.1.2 release',
      publisher='Natural Earth contributors',version='v5.1.2-release:rivers-layer-5.0.0',license='PUBLIC_DOMAIN',
      locator='https://github.com/nvkelso/natural-earth-vector/tree/v5.1.2/geojson',
      access_metadata=dict(source_date='2022 release; observations composite, not a dated survey',horizontal_crs='EPSG:4326',
       scale='1:10,000,000 cartographic, NOT 10 metres',vertical_datum='Not applicable to 2D water geometry',
       licence_url='https://www.naturalearthdata.com/about/terms-of-use/',
       geometry='Source River and Lake Centerline; Lake and Alkaline Lake polygons. Reservoir polygons excluded.',
       historical_applicability='Modern generalised reference. River axes through regulated reaches are not reconstructed 1900 channels. Natural lake levels, deltas and banks may differ.'))]

def read_features():
    lakes_doc=json.loads(LAKES.read_text(encoding='utf8'));items=[];excluded=[];inventory=[]
    baikal=next(shape(f['geometry']) for f in lakes_doc['features'] if f['properties'].get('ne_id')==1159113127)
    for i,f in enumerate(json.loads(RIVERS.read_text(encoding='utf8'))['features']):
        p=f['properties'];g=shape(f['geometry']);name=p.get('name') or ''
        if not name or name in EXCLUDE_RIVERS or not g.intersects(DOMAIN):continue
        if p['featurecla'] not in ['River','Lake Centerline']:continue
        # Preserve only actual source segments. Never synthesize a lake axis,
        # a connection between names, or a historical channel from this cut.
        g=g.intersection(DOMAIN).difference(baikal)
        if g.is_empty:continue
        ident=f'river:siberian_ne10m_record_{i}'
        e=dict(id=ident,kind='river',name=name,geometry=transform(shared.TO_METRES,g),
          main=name in MAIN or float(p.get('scalerank',9))<=7,source='ne_siberian_hydro_r50',
          rank=p.get('scalerank'),source_date='Natural Earth v5.1.2 composite',
          observation_period={'from':'1990-01-01','to':'2022-12-31'},
          source_notes=dict(original_record=i,rivernum=p.get('rivernum'),source_category=p['featurecla'],
           epoch_qualification='Broad composite catalogue interval, not exact observation dates',
           water_class='modern_generalised_axis',historical_channel='Unconfirmed where modern regulation changed the course'))
        e['stroke_scale']=(1.35 if name in {'Ob','Yenisey','Lena','Irtysh','Ertis','Ertix'}
          else 1.0 if e['main'] else .62)
        # Optional validated package replaces only the old draw object. The
        # original source/query geometry remains in its immutable source file.
        if i==184:e['display_replaces']=['river:ob']
        if i==203:e['display_replaces']=['river:lena']
        items.append(e);inventory.append(dict(id=ident,name=name,kind='river',original_record=i,rivernum=p.get('rivernum'),category=p['featurecla'],main=e['main']))
    for i,f in enumerate(lakes_doc['features']):
        p=f['properties'];g=shape(f['geometry'])
        if not g.intersects(DOMAIN):continue
        if p['featurecla'] not in ['Lake','Alkaline Lake']:
            excluded.append(dict(ne_id=p['ne_id'],name=p.get('name'),category=p['featurecla']));continue
        # Whole source lake, including holes. A scope collar is not a bank.
        if not DOMAIN.contains(g.representative_point()):continue
        gm=transform(shared.TO_METRES,g)
        e=dict(id=f'lake:siberian_ne10m_{p["ne_id"]}',kind='lake',name=p.get('name') or f'Natural Earth lake {p["ne_id"]}',geometry=gm,
          main=float(p.get('scalerank',9))<=6 or p['ne_id'] in [1159115303,1159115317,1159117165,1159119709],
          source='ne_siberian_hydro_r50',rank=p.get('scalerank'),source_date='Natural Earth v5.1.2 composite',
          observation_period={'from':'1990-01-01','to':'2022-12-31'},source_notes=dict(original_record=i,ne_id=p['ne_id'],
           source_category=p['featurecla'],water_class='natural_lake_modern_extent',historical_water_level='Not reconstructed'))
        if p['ne_id']==1159113127:e['display_replaces']=['lake:lakebaikal']
        items.append(e);inventory.append(dict(id=e['id'],name=e['name'],kind='lake',ne_id=p['ne_id'],main=e['main'],area_km2=gm.area/1e6))
    return items,inventory,excluded

def build():
    WORK.mkdir(parents=True,exist_ok=True);items,inventory,excluded=read_features();descriptors=[]
    descriptors.append(shared.write_shard('siberian_hydro_overview_r50',[(e,e['geometry']) for e in items if e['main']],
      [54,176,46,84],True,registry(),'tools/map/build_siberian_hydro_r50.py'))
    minor=[e for e in items if not e['main']]
    for lat in range(44,84,4):
        for lon in range(52,176,4):
            b=[lon,lon+4,lat,lat+4];core=transform(shared.TO_METRES,box(lon,lat,lon+4,lat+4))
            entries=[(e,e['geometry'].intersection(core)) for e in minor if e['geometry'].intersects(core)]
            if not entries:continue
            d=shared.write_shard(f'siberian_hydro_{lat}_{lon:+d}_r50',entries,b,False,registry(),'tools/map/build_siberian_hydro_r50.py')
            if d:d['max_mpp']=500.;descriptors.append(d)
    index_path=OUT/'index.json';index=json.loads(index_path.read_text(encoding='utf8'))
    index['hydro_regions']=[d for d in index.get('hydro_regions',[]) if not d['id'].startswith('siberian_hydro_')]+descriptors
    index_path.write_text(json.dumps(index,ensure_ascii=False,separators=(',',':')),encoding='utf8')
    summary=dict(descriptors=descriptors,objects=inventory,excluded_source_water=excluded,
      counts=dict(collections.Counter(e['kind'] for e in items)),bytes=sum(d['bytes']+d['geometry_bytes'] for d in descriptors),
      gaps=['Ket, Abakan and Barguzin are not identified in the retained 10m source; no fabricated connectors.',
       'No dated 1900 bank or northern delta geometry acquired; modern generalised reference only.',
       'Sayano-Shushenskoye, Boguchany and Kolyma reservoir polygons are absent from this source selection; no historical water surface reconstructed.'])
    (WORK/'runtime_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
    print('Siberian hydro',summary['counts'],'shards',len(descriptors),'bytes',summary['bytes'],'excluded',len(excluded),flush=True)

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf8');build()
