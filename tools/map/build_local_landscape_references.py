"""Bounded LOCAL references from acquired IGN/EA/swisstopo/Copernicus inputs.

Offline conversion only. No simulated place, land, ownership or land use is made.
Raw inputs and Python dependencies stay under local-artifacts/local-landscape-r4.
"""
from pathlib import Path
import json, math, sys

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'local-artifacts/local-landscape-r4'
sys.path.insert(0, str(RAW / 'python-libs'))
import numpy as np
from PIL import Image
from pyproj import Transformer

OUT = ROOT / 'data/local'
def read(path): return json.loads(path.read_text(encoding='utf8'))
def write(name, value):
    p = OUT / name
    p.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')
    print(name, p.stat().st_size)

def surface(name, anchor, width, height, step, sampler, source):
    west, north = anchor[0]-(width-1)*step/2, anchor[1]+(height-1)*step/2
    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            value = float(sampler(west+x*step, north-y*step))
            if not math.isfinite(value) or value < -1000: raise ValueError('Missing acquired elevation; no replacement height: '+name)
            row.append(round(value, 2))
        rows.append(row)
    d = dict(schema_id='local_native_height_reference_r1', horizontal_crs='EPSG:4326',
             anchor_lon_lat=anchor, width=width, height=height, west_cell_centre=west,
             north_cell_centre=north, step_degrees=step, height_rows_m=rows,
             display_min_mpp=0, display_max_mpp=120, **source)
    write(name, d)
    return d

def raster_sampler(path, crs, origin=None, step=None):
    image = Image.open(path)
    values = np.asarray(image, dtype=np.float32).copy()
    if origin is None:
        affine = image.tag_v2.get(34264)
        if affine:
            origin, step = (affine[3], affine[7]), (affine[0], -affine[5])
        else:
            tie, scale = image.tag_v2[33922], image.tag_v2[33550]
            origin, step = (tie[3], tie[4]), (scale[0], scale[1])
    image.close()
    transform = Transformer.from_crs(4326, crs, always_xy=True)
    def sample(lon, lat):
        e, n = transform.transform(lon, lat)
        x, y = int((e-origin[0])/step[0]), int((origin[1]-n)/step[1])
        if not (0<=x<values.shape[1] and 0<=y<values.shape[0]): raise ValueError('Outside acquired raster')
        return values[y, x]
    return sample

def source(id, title, publisher, version, license, locator):
    return dict(source_id=id, title=title, publisher=publisher, version=version, license=license,
                locator=locator, access_metadata={'source_type':'PHYSICAL_REFERENCE', 'historical_applicability':'Modern physical reference only; not a 1900 survey, vegetation, streets or authority.'})

def fact(feature, src, shard, period=None):
    if period is None:
        period=('2019-01-01','2019-12-31') if src['version']=='2019' else ('1859-01-01','1900-12-31') if src['source_id']=='uk_parliament_clock_tower' else ('2026-10-13','2026-10-13')
    return dict(fact_id='local_spatial:'+feature['id'], domain='local_spatial_content', subject_id=feature['id'],
                value=feature, unit='display_geography', source_id=src['source_id'], source_version=src['version'],
                source_locator=src['locator'], observation_period={'from':period[0],'to':period[1]},
                spatial_scope={'kind':'content_shard','id':shard}, methodology='Bounded acquired geometry; display reference only; no historical ownership, transport, forest or population inference.',
                confidence=0.8, lower_bound=None, upper_bound=None, license=src['license'],
                review_status='BOUNDED_ESTIMATE', generator='tools/map/build_local_landscape_references.py')

def point(id, name, kind, coords, src):
    return dict(id=id, display_name=name, kind=kind, rank=0, geometry={'type':'Point','coordinates':coords},
                source_id=src['source_id'], source_type='PHYSICAL_REFERENCE', source_reference=src['locator'],
                source_name_zh=src['publisher'], valid_from='1900-01-01', valid_to='9999-12-31')

# Existing Natural Earth centreline observations, clipped without inventing widths.
RIVER_SOURCE = source('ne_local_river_reference_5_0_0','Natural Earth 1:10m river centreline reference',
                      'Natural Earth', '5.0.0', 'PUBLIC_DOMAIN', 'https://www.naturalearthdata.com/downloads/10m-physical-vectors/10m-rivers-lake-centerlines/')
RIVERS = read(ROOT/'local-artifacts/geographic-foundation-r1/source/ne_10m_rivers_lake_centerlines.geojson')['features']
def clip_segment(a, b, bounds):
    lo, hi = 0.0, 1.0
    dx, dy = b[0]-a[0], b[1]-a[1]
    for p, q in [(-dx,a[0]-bounds[0]),(dx,bounds[2]-a[0]),(-dy,a[1]-bounds[1]),(dy,bounds[3]-a[1])]:
        if p==0:
            if q<0: return None
        elif p<0: lo=max(lo,q/p)
        else: hi=min(hi,q/p)
        if lo>hi: return None
    if lo==hi: return None
    return [[round(a[0]+dx*t,7),round(a[1]+dy*t,7)] for t in [lo,hi]]

def rivers(name, bounds, shard):
    features = []
    for raw in RIVERS:
        if name.lower() not in str(raw['properties'].get('name','')).lower(): continue
        g=raw['geometry']; lines=[g['coordinates']] if g['type']=='LineString' else g['coordinates'] if g['type']=='MultiLineString' else []
        for line in lines:
            runs=[]; current=[]
            for a,b in zip(line,line[1:]):
                pair=clip_segment(a,b,bounds)
                if pair is None:
                    if len(current)>1: runs.append(current)
                    current=[]; continue
                if current and current[-1]==pair[0]: current.append(pair[1])
                else:
                    if len(current)>1: runs.append(current)
                    current=pair
            if len(current)>1: runs.append(current)
            for run in runs:
                features.append(dict(id=f'river:{shard}_{len(features)}', kind='river', display_name=name,
                  geometry={'type':'LineString','coordinates':run}, source_id=RIVER_SOURCE['source_id'],
                  source_type='PHYSICAL_REFERENCE', source_reference=RIVER_SOURCE['locator'],
                  valid_from='1900-01-01', valid_to='9999-12-31',
                  geometry_role='MODERN_GENERALIZED_CENTRELINE_NOT_WATER_SURFACE',
                  note_zh='现代概化河流中心线；不代表1900年河岸、宽度或完整水面。'))
    return features

def shard(name, id, anchor_id, anchor, radius, features, sources, surface_path, visuals=()):
    metadata=dict(schema_id='local_spatial_content_r1', shard_id=id, anchor_place_id=anchor_id,
      anchor_lon_lat=anchor, radius_km=radius, valid_from='1900-01-01', valid_to='9999-12-31',
      status='MODERN_PHYSICAL_REFERENCE_WITH_FIXED_HISTORICAL_ANCHORS',
      surface_reference_path='res://data/local/'+surface_path, local_min_mpp=2,
      landmark_visuals=list(visuals),
      terrain_note_zh='现代地表参考。高程、河流中心线不证明1900年街区、林地或河岸。',
      data_gaps=['No georeferenced 1900 road/rail alignment, forest polygons or built-up extent.', 'No water-surface polygon: existing centreline symbols only.'])
    source_by_id={s['source_id']:s for s in sources}
    write(name, dict(metadata=metadata, source_registry={'schema_id':'historical_source_registry_v2','sources':sources},
                    evidence_catalog={'schema_id':'historical_fact_evidence_catalog_v2','facts':[fact(f,source_by_id[f['source_id']],id) for f in features]}))

def main():
    # IGN high-resolution source is queried at a bounded 33x50m display grid.
    samples=read(RAW/'paris_rge_alti.json')['elevations']
    if len(samples)!=63*63: raise ValueError('Incomplete IGN response')
    index={(round(x['lon'],7),round(x['lat'],7)):x['z'] for x in samples}
    surface('paris_surface_rge_alti.json',[2.2945,48.858333],63,63,.00045,
      lambda lon,lat:index[(round(lon,7),round(lat,7))],
      dict(source_id='ign_rge_alti_wld',source_reference='https://data.geopf.fr/altimetrie/resources/ign_rge_alti_wld',
      license='Licence Ouverte 2.0', attribution='© IGN — RGE ALTI', vertical_datum='IGN69; metres in mainland France',
      source_epoch='Current IGN service, retrieved 2026-10-13; measurement accuracy varies by underlying source',
    source_resolution_note='RGE ALTI product nominal grid 1m; API pyramid resolution not specified by the returned static resource metadata. Accuracy varies by source.', display_spacing_m_approx=[33,50], terrain_note_zh='IGN RGE ALTI 现代裸地参考，约33×50米显示采样；接口未给出本范围测量精度，不证明1900年街道、河岸或塔基高程。'))
    paris=read(OUT/'paris_northern_france_1900.json')
    paris['metadata']['surface_reference_path']='res://data/local/paris_surface_rge_alti.json'
    paris['metadata']['local_min_mpp']=2
    paris['metadata']['terrain_note_zh']='IGN RGE ALTI 现代物理地表，约33×50米显示采样；不作为1900年城市地貌证明。'
    for visual in paris['metadata'].get('landmark_visuals',[]):
        visual['terrain_note_zh']=paris['metadata']['terrain_note_zh']
    write('paris_northern_france_1900.json',paris)

    ea_url='https://www.data.gov.uk/dataset/01b3ee39-da3f-47b6-83da-dc98e73a461f/lidar-composite-digital-terrain-model-dtm-1m'
    london_surface=surface('london_surface_ea_dtm.json',[-.1246,51.5007],63,63,.00035,
      raster_sampler(RAW/'london_dtm.tif',27700), dict(source_id='ea_dtm_2022',source_reference=ea_url,
      license='Open Government Licence v3.0',attribution='© Environment Agency copyright and/or database right 2022. All rights reserved.',
      vertical_datum='OS Newlyn; source EPSG:27700 transformed to WGS84',source_epoch='Composite 2022, surveys 2000–2022; not 1900',
      source_resolution_m=1,display_spacing_m_approx=[24,39],terrain_note_zh='环境署现代1米DTM，约24×39米显示采样；无1900年河岸及街区复原。'))
    uk=source('uk_parliament_clock_tower','Clock Tower historical form and fixed-monument location','UK Parliament; fixed modern locator Wikidata Q41225','1900-model-reference','Original WWO model; factual reference only','https://www.parliament.uk/about/living-heritage/building/palace/big-ben/facts-figures/')
    london=point('place:london','伦敦','settlement',[-.1276,51.5072],uk)
    london['parent_country_id']='british_isles_1900'
    visual=point('landmark:westminster_clock_tower_1900','威斯敏斯特钟楼','landmark',[-.12457,51.50067],uk)
    visual.update(anchor_place_id='place:london',anchor_name_zh='伦敦 · 威斯敏斯特',parent_country_id='british_isles_1900',
       existence_confirmed_on='1900-01-01',existence_note_zh='1859年已建成；1900年度模型形制不等于后来重新测绘。',
       reference_year=1900,model_reference_year=1900,real_height_m=96.3,real_base_width_m=12,
       model_path='res://assets/landmarks/westminster_clock_tower_1900.glb',model_height_m=96.3,model_base_width_m=13,
       model_heading_degrees=0,symbol_kind='clock_tower',symbol_max_mpp=1800,model_max_mpp=110,
       display_height_min_px=60,display_height_max_px=90,display_width_max_px=65,display_scale_max=100,
       source_date='1859–1900',source_type='HISTORICAL_EVIDENCE',source_name_zh='英国议会 / 现代固定建筑定位',
       historical_reference_zh='1900年的Clock Tower。仅钟楼，不含整座宫殿、内部机械或现代附加设施。',
       real_dimensions_note_zh='议会资料约96米高、12米主体基座；低模尺寸为表现参考。',
       coordinate_source_reference='https://www.wikidata.org/wiki/Q41225',
       coordinate_notice_zh='现代固定建筑定位约东经−0.12457°、北纬51.50067°；不声称1900年测绘精度。')
    thames=rivers('Thames',[-.142,51.482,-.108,51.52],'london_westminster')
    shard('london_westminster_1900.json','london_westminster','place:london',[-.1246,51.5007],15,
          [london,visual]+thames,[uk,RIVER_SOURCE],'london_surface_ea_dtm.json',[visual])

    # Three adjacent 1km swisstopo tiles; retain real mountain relief, no forest inference.
    swiss_samplers=[raster_sampler(RAW/f'swissalti3d_2019_2620-{n}_2_2056_5728.tif',2056) for n in [1094,1095,1096]]
    def swiss_sample(lon,lat):
        for sampler in swiss_samplers:
            try:return sampler(lon,lat)
            except ValueError:pass
        raise ValueError('Outside acquired Swiss tiles')
    swiss_url='https://www.swisstopo.admin.ch/en/height-model-swissalti3d'
    swiss=surface('zermatt_west_surface_swissalti3d.json',[7.703304,46.010743],33,63,.00025,swiss_sample,
       dict(source_id='swissalti3d_2019',source_reference=swiss_url,license='swisstopo OGD terms of use',attribution='©swisstopo',
       source_epoch='2019 tile edition; modern physical reference',vertical_datum='LN02 EPSG:5728; source horizontal EPSG:2056',
       source_resolution_m=2,display_spacing_m_approx=[19,28],low_color='#606351',high_color='#969184',
       terrain_note_zh='采尔马特西侧山地：swissALTI3D 2019版2米裸地数据，约19×28米显示采样。现代地表，不是1900年冰川、林地或建成区。'))
    ss=source('swissalti3d_2019','swissALTI3D, 2019 bounded tiles','©swisstopo','2019','swisstopo OGD terms of use',swiss_url)
    location=point('geographic_region:zermatt_west_reference','瑞士阿尔卑斯 · 采尔马特西侧山地','geographic_region',[7.703304,46.010743],ss)
    location.update(note_zh=swiss['terrain_note_zh'],coordinate_reference='https://webgis.zermatt.ch/')
    shard('zermatt_west_physical_reference.json','zermatt_west_physical_reference',location['id'],[7.703304,46.010743],8,[location],[ss],'zermatt_west_surface_swissalti3d.json')

    # DSM used only west of the monuments; do not turn pyramid/urban tops into bare ground.
    cop_url='https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM'
    surface('giza_west_surface_copdem.json',[31.1135,29.976122],57,57,.0003,
      raster_sampler(RAW/'giza_copdem_native_tile.tif',4326,(31,30),(1/3600,1/3600)),
      dict(source_id='cop_dem_glo30_2021',source_reference=cop_url,license='Copernicus WorldDEM-30 public licence',
      attribution='produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved',
      source_epoch='2021 public release; TanDEM-X 2011–2015 and infill; modern DSM',vertical_datum='EGM2008; metres',
      source_resolution_m=30,display_spacing_m_approx=[29,33],low_color='#8e8061',high_color='#aaa080',
      terrain_note_zh='金字塔西侧有限地表为Copernicus约30米现代DSM，不是裸地DEM。金字塔基座范围未采用此DSM，继续使用平面；不将现代建筑高度作为1900年地形。'))
    giza=read(OUT/'giza_pyramids_1900.json')
    giza['metadata'].update(surface_reference_path='res://data/local/giza_west_surface_copdem.json',local_min_mpp=2,
      terrain_note_zh='金字塔西侧现代DSM参考；地标基座仍用平面，尼罗河仅有概化中心线。')
    nile=rivers('Nile',[31.16,29.89,31.265,30.075],'giza_pyramids_1900')
    cities=read(ROOT/'local-artifacts/global-strategic-r1/source/ne_10m_populated_places_simple.geojson')['features']
    cairo=next(f for f in cities if f['properties'].get('name')=='Cairo' and f['properties'].get('adm0name')=='Egypt')
    city_source=source('ne_cairo_position_reference','Natural Earth populated place representative point', 'Natural Earth',
      'cached-modern-reference', 'PUBLIC_DOMAIN', 'https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-populated-places/')
    cairo_point=point('geographic_region:cairo_position_reference','开罗 · 位置参考','geographic_region',cairo['geometry']['coordinates'],city_source)
    cairo_point.update(rank=1,parent_country_id='khedivate_of_egypt',
      note_zh='开罗的现代代表点，用于说明它与吉萨、尼罗河的地理关系。不表示1900年建成区、街道或城市范围。')
    source_ids={RIVER_SOURCE['source_id'],city_source['source_id']}
    giza['source_registry']['sources']=[s for s in giza['source_registry']['sources'] if s['source_id'] not in source_ids]+[RIVER_SOURCE,city_source]
    giza['evidence_catalog']['facts']=[f for f in giza['evidence_catalog']['facts'] if f['source_id'] not in source_ids]+[fact(f,RIVER_SOURCE,'giza_pyramids_1900') for f in nile]+[fact(cairo_point,city_source,'giza_pyramids_1900')]
    for visual in giza['metadata']['landmark_visuals']:
        visual['terrain_note_zh']=giza['metadata']['terrain_note_zh']
    write('giza_pyramids_1900.json',giza)
    print('River centreline fragments:',len(thames),len(nile))

if __name__=='__main__':main()
