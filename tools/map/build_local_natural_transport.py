"""Bounded R11 map content, using acquired physical polygons and historical facts.

No domain place, ownership, transport capacity or land-use state is created.
Raw inputs remain outside exports. OSM-derived geometry remains separately
identified under ODbL; IGN-derived geometry uses Licence Ouverte 2.0.
"""
from pathlib import Path
import json
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'local-artifacts/local-natural-transport-r11'
OUT = ROOT / 'data/local'
sys.path.insert(0, str(ROOT / 'local-artifacts/historical-islands-admin-r5/python-libs'))
from shapely.geometry import shape, mapping, Polygon, LineString, box
from shapely.ops import polygonize, unary_union, triangulate

def read(path):
    return json.loads(path.read_text(encoding='utf8'))

def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')

def polygons(geometry):
    if geometry.geom_type == 'Polygon':
        yield geometry
    elif hasattr(geometry, 'geoms'):
        for part in geometry.geoms:
            yield from polygons(part)

def xy_geometry(geometry):
    # A source's water level is retained separately, never lost as a fake DEM.
    if geometry.geom_type == 'Polygon':
        return Polygon([p[:2] for p in geometry.exterior.coords],
                       [[p[:2] for p in ring.coords] for ring in geometry.interiors])
    return unary_union([xy_geometry(p) for p in polygons(geometry)])

def osm_polygons(filename, kind):
    tree = ET.parse(RAW / filename).getroot()
    nodes = {n.get('id'): (float(n.get('lon')), float(n.get('lat'))) for n in tree.findall('node')}
    ways = {w.get('id'): w for w in tree.findall('way')}
    def tags(element):
        return {t.get('k'): t.get('v') for t in element.findall('tag')}
    def coordinates(way):
        refs = [n.get('ref') for n in way.findall('nd')]
        return [nodes[r] for r in refs] if all(r in nodes for r in refs) else []
    def wanted(t):
        return (t.get('landuse') == 'forest' or t.get('natural') == 'wood') if kind == 'woodland' else (t.get('natural') == 'water' and t.get('water') == 'river')
    results = []
    for way in ways.values():
        if not wanted(tags(way)):
            continue
        coords = coordinates(way)
        if len(coords) >= 4 and coords[0] == coords[-1]:
            p = Polygon(coords)
            if p.is_valid: results.append((f'osm:way/{way.get("id")}', p))
    for relation in tree.findall('relation'):
        if not wanted(tags(relation)):
            continue
        rings = {'outer': [], 'inner': []}
        complete = True
        for member in relation.findall('member'):
            if member.get('type') != 'way': continue
            way = ways.get(member.get('ref'))
            coords = coordinates(way) if way is not None else []
            role = member.get('role') or 'outer'
            if len(coords) < 2 or role not in rings:
                complete = False
                break
            rings[role].append(LineString(coords))
        if not complete: continue
        outer = list(polygonize(rings['outer']))
        inner = list(polygonize(rings['inner']))
        if not outer: continue
        p = unary_union(outer).difference(unary_union(inner))
        if p.is_valid: results.append((f'osm:relation/{relation.get("id")}', p))
    return results

def source(id, title, publisher, locator, license):
    return dict(source_id=id, title=title, publisher=publisher, version='R11_2026-10-14',
                locator=locator, license=license,
                access_metadata={'source_type': 'PHYSICAL_REFERENCE',
                                 'historical_applicability': 'Modern reference only; not a 1900 survey.'})

IGN = source('ign_bdtopo_water_r11', 'BD TOPO V3 surface_hydrographique, bounded Seine subset',
             '© IGN', 'https://geoservices.ign.fr/bdtopo', 'Licence Ouverte 2.0')
OSM = source('osm_bounded_cover_r11', 'Bounded OpenStreetMap water / woodland polygons',
             '© OpenStreetMap contributors', 'https://www.openstreetmap.org/copyright', 'ODbL-1.0')

def fact(feature, src, shard, historical=False):
    return dict(fact_id='local_spatial:'+feature['id'], domain='local_spatial_content',
                subject_id=feature['id'], value=feature, unit='display_geography',
                source_id=src['source_id'], source_version=src['version'], source_locator=src['locator'],
                observation_period={'from': '1900-01-01' if historical else '2026-10-14',
                                    'to': '1900-01-01' if historical else '2026-10-14'},
                spatial_scope={'kind': 'content_shard', 'id': shard},
                methodology='Bounded source geometry / factual transport record. No inferred ownership, hydraulic level, 1900 land use or unverified railway alignment.',
                confidence=0.8, lower_bound=None, upper_bound=None, license=src['license'],
                review_status='HISTORICAL_EVIDENCE' if historical else 'BOUNDED_ESTIMATE',
                generator='tools/map/build_local_natural_transport.py')

def point(id, name, coordinate, src, country, display_kind, note):
    return dict(id=id, kind='geographic_region', display_name=name, rank=1, max_mpp=1200,
                geometry={'type': 'Point', 'coordinates': coordinate},
                valid_from='1900-01-01', valid_to='9999-12-31', parent_country_id=country,
                source_id=src['source_id'], source_type='PHYSICAL_REFERENCE',
                source_reference=src['locator'], source_name_zh=src['publisher'],
                source_license=src['license'], display_kind=display_kind, note_zh=note)

def install_facts(doc, features, sources, historical=False):
    ids = {s['source_id'] for s in sources}
    doc['source_registry']['sources'] = [s for s in doc['source_registry']['sources'] if s['source_id'] not in ids]+sources
    feature_ids = {f['id'] for f in features}
    facts = doc['evidence_catalog']['facts']
    facts[:] = [f for f in facts if f['subject_id'] not in feature_ids]
    by_id = {s['source_id']: s for s in sources}
    facts.extend(fact(f, by_id[f['source_id']], doc['metadata']['shard_id'], historical) for f in features)

def grid_extent(surface):
    west, north, step = surface['west_cell_centre'], surface['north_cell_centre'], surface['step_degrees']
    return box(west, north-(surface['height']-1)*step,
               west+(surface['width']-1)*step, north)

def native_cover_triangles(geometry, surface):
    """Intersect source polygons with the actual native DEM triangle topology.

    Triangulation is used only for display and never written as a land identity.
    Hole / bank edges remain constrained; no point is added outside the polygon.
    """
    west, north, step = surface['west_cell_centre'], surface['north_cell_centre'], surface['step_degrees']
    triangles = []
    for row in range(surface['height']-1):
        for col in range(surface['width']-1):
            a=(west+col*step, north-row*step)
            b=(a[0]+step,a[1]); c=(a[0],a[1]-step); d=(b[0],c[1])
            for cell in [Polygon([a,c,b]), Polygon([b,c,d])]:
                if not cell.intersects(geometry): continue
                for polygon in polygons(cell.intersection(geometry)):
                    for tri in triangulate(polygon):
                        if not polygon.covers(tri): continue
                        triangles.append([[round(x,9),round(y,9)] for x,y in list(tri.exterior.coords)[:3]])
    return triangles

def natural_content(shard_name, surface_name, water, woodland=()):
    doc, surface = read(OUT/shard_name), read(OUT/surface_name)
    extent = grid_extent(surface)
    covers=[]; features=[]
    for kind, entries, src, color_name in [('water_surface', water, IGN if shard_name.startswith('paris') else OSM,'水面'),
                                          ('woodland', woodland, OSM,'林地')]:
        for id, geometry, level in entries:
            clipped=geometry.intersection(extent)
            if clipped.is_empty: continue
            triangles=native_cover_triangles(clipped,surface)
            if not triangles: continue
            cover=dict(id=id, kind=kind, triangles=triangles, source_reference=src['locator'],
                       source_id=src['source_id'],source_date='2026-10-14',license=src['license'])
            if level is not None: cover['reference_elevation_m']=level
            covers.append(cover)
        if entries:
            geometry=unary_union([e[1] for e in entries])
            p=geometry.representative_point()
            region=doc['metadata']['shard_id']
            name={'paris_northern_france_1900':'塞纳河','london_westminster':'泰晤士河','giza_pyramids_1900':'尼罗河','zermatt_west_physical_reference':'采尔马特西侧'}[region]
            note=f'{name} · 现代{color_name}范围参考，2026-10-14取得。来源：{src["publisher"]}，{src["license"]}。不是1900年{color_name}分布或精密测绘；不改变政治或行政归属。'
            if kind=='water_surface': note+='水面只覆盖实际来源多边形。IGN水面保留源Z高程；无水位资料的OSM多边形贴合当前DTM，不表示实测水位或河道流动。'
            else: note+='林地仅作现代覆盖参考，使用一份贴地覆盖Mesh，不逐棵实例化树木。'
            reference=point('geographic_region:'+region+'_'+kind+'_r11',name+' · '+color_name+'参考',[p.x,p.y],src,
                            {'paris_northern_france_1900':'country_fra','london_westminster':'british_isles_1900',
                             'giza_pyramids_1900':'khedivate_of_egypt','zermatt_west_physical_reference':'swiss_confederation'}[region],
                            'physical_cover',note)
            # Publish the adapted OSM database as accessible plain game JSON.
            reference['reference_geometry']=mapping(geometry)
            features.append(reference)
            if kind=='water_surface':
                features.append(dict(id='water_surface:'+region+'_r11',kind=kind,display_name=name+' · 现代水面参考',
                                     geometry=mapping(geometry), source_id=src['source_id'],
                                     source_reference=src['locator'],source_type='PHYSICAL_REFERENCE',
                                     valid_from='1900-01-01',valid_to='9999-12-31',geometry_role='MODERN_WATER_POLYGON_NOT_1900_BANK'))
    surface['cover_meshes']=covers
    heights=[value for row in surface['height_rows_m'] for value in row]
    surface['height_min_m'],surface['height_max_m']=min(heights),max(heights)
    surface['cover_note_zh']='水面与林地来自现代物理范围；未推定1900年土地利用。来源及许可见每个cover记录。'
    install_facts(doc, features, [IGN,OSM] if shard_name.startswith('paris') else [OSM])
    doc['metadata']['natural_reference_note_zh']=surface['cover_note_zh']
    doc['metadata']['map_attribution_zh']='现代物理参考 · © IGN' if shard_name.startswith('paris') else '现代物理参考 · © OpenStreetMap contributors · ODbL'
    note=' 水面/林地仅按已取得的现代物理几何显示。'
    if note not in doc['metadata']['terrain_note_zh']: doc['metadata']['terrain_note_zh']+=note
    for visual in doc['metadata'].get('landmark_visuals',[]):
        visual['terrain_note_zh']=doc['metadata']['terrain_note_zh']
    write(OUT/shard_name,doc); write(OUT/surface_name,surface)
    print(shard_name,'covers',len(covers),'triangles',sum(len(c['triangles']) for c in covers),'references',len(features))

def historical_source(id, title, publisher, url):
    s=source(id,title,publisher,url,'CC0-1.0 for WWO factual compilation; linked source retains its own rights')
    s['access_metadata']={'source_type':'HISTORICAL_EVIDENCE','historical_applicability':'Confirmed existence by 1900-01-01; modern representative locator does not establish original building footprint or railway alignment.'}
    return s

def transport():
    srcs={
      'nord':historical_source('sncf_nord_history_r11','Gare du Nord historical record','SNCF Gares & Connexions','https://www.garesetconnexions.sncf/fr/histoire-gare-du-nord'),
      'lazare':historical_source('sncf_lazare_history_r11','Gare Saint-Lazare historical record','SNCF Patrimoine','https://patrimoine.sncf.com/2025/04/25/la-gare-de-paris-saint-lazare-entre-histoire-art-et-modernite/'),
      'iena':historical_source('paris_iena_history_r11','Pont d’Iéna historical record','Ville de Paris','https://www.paris.fr/pages/lifting-reussi-pour-les-cavaliers-du-pont-d-iena-27479'),
      'waterloo':historical_source('tfl_waterloo_city_history_r11','Research Guide 29: Waterloo & City Railway','TfL Corporate Archives','https://tfl.gov.uk/cdn/static/cms/documents/research-guide-no-29-brief-history-of-the-waterloo-and-city-line.pdf'),
      'charing':historical_source('nr_charing_history_r11','History of Charing Cross station','Network Rail','https://www.networkrail.co.uk/who-we-are/our-history/iconic-infrastructure/the-history-of-charing-cross-station/'),
      'westminster':historical_source('london_bridge_history_r11','Westminster Bridge historical record','London Museum','https://www.londonmuseum.org.uk/collections/london-stories/westminster-bridge/'),
      'friedrich':historical_source('berlin_friedrich_history_r11','Denkmaldatenbank object 09080415','Land Berlin','https://denkmaldatenbank.berlin.de/daobj.php?obj_dok_nr=09080415'),
      'alexander':historical_source('berlin_alexander_history_r11','Stadtbahn / Alexanderplatz historical record','Land Berlin','https://denkmaldatenbank.berlin.de/daobj.php?obj_dok_nr=09066667')}
    rows=[
      ('paris_northern_france_1900.json','nord','paris_nord','巴黎北站',[2.3553,48.8809],'country_fra','1846年旧站、1860年代扩建。仅保留车站存在与代表位置，未恢复1900年站场、道岔或所有权。'),
      ('paris_northern_france_1900.json','lazare','paris_saint_lazare','巴黎圣拉扎尔站',[2.3246,48.8766],'country_fra','1837年始设；当前地点代表后续19世纪末站址，不把1837年临时木站放在同一点。未取得完整历史线位。'),
      ('paris_northern_france_1900.json','iena','pont_iena','耶拿桥',[2.2929,48.8598],'country_fra','1806—1813年建造。只表示桥梁位置和存在，不套用1937年拓宽后的桥面几何。'),
      ('london_westminster_1900.json','waterloo','waterloo_city','Waterloo · 滑铁卢站',[-.1137,51.5033],'british_isles_1900','1898年Waterloo & City已连接Waterloo与City。City直到1940年才改名Bank；本记录不提前改名。仅存连接关系，不画未经定位的隧道。'),
      ('london_westminster_1900.json','waterloo','city_1898','City · 城市站',[-.0889,51.5134],'british_isles_1900','1898年Waterloo & City终点，1900年仍叫City。现代Bank代表定位不等于1898年站台范围。'),
      ('london_westminster_1900.json','charing','charing_cross','Charing Cross · 查令十字站',[-.1248,51.5080],'british_isles_1900','1864-01-11开放，史料确认连接London Bridge。未取得本轮可分发、完成配准的1900年精确线路。'),
      ('london_westminster_1900.json','westminster','westminster_bridge','威斯敏斯特桥',[-.1218,51.5009],'british_isles_1900','现有桥1862年开放；只记录历史桥梁与固定代表位置，不建立道路通行、桥梁资产或运输能力。'),
      ('berlin_transport_1900.json','friedrich','friedrichstrasse','Friedrichstraße · 腓特烈大街站',[13.3880,52.5200],'german_empire','1878—1882年建造，1882年Stadtbahn车站。没有套用1919—1925年新站厅，也不提前加入后来的地铁。'),
      ('berlin_transport_1900.json','alexander','alexanderplatz','Alexanderplatz · 亚历山大广场站',[13.4110,52.5218],'german_empire','1882年Stadtbahn已存在并经Alexanderplatz。仅保留历史连接关系；1900年尚未建立后来的地铁换乘站。')]
    by_shard={}
    for filename,key,slug,name,coordinate,country,note in rows:
        src=srcs[key]
        f=point('transport_reference:'+slug,name,coordinate,src,country,'transport_node',note+' 坐标是现代代表位置，约100—250米定位不确定性，不是1900年站台或桥面实测。')
        f.update(source_type='HISTORICAL_EVIDENCE',historical_reference_date='1900-01-01',
                 coordinate_role='MODERN_REPRESENTATIVE_LOCATOR',coordinate_uncertainty_m=250,
                 transport_evidence_class='C_EXISTENCE_AND_LOCATION')
        if slug in ['waterloo_city','city_1898']:
            f['transport_evidence_class']='B_HISTORICAL_CONNECTION_ONLY'
            f['historical_connection_ids']=['transport_reference:city_1898' if slug=='waterloo_city' else 'transport_reference:waterloo_city']
        if slug in ['friedrichstrasse','alexanderplatz']:
            f['transport_evidence_class']='B_HISTORICAL_CONNECTION_ONLY'
            f['historical_connection_ids']=['transport_reference:alexanderplatz' if slug=='friedrichstrasse' else 'transport_reference:friedrichstrasse']
            f['connection_kind']='SAME_STADTBAHN_LINE_NOT_DIRECT_NEIGHBOUR_CLAIM'
        by_shard.setdefault(filename,[]).append(f)
    for filename,features in by_shard.items():
        if (OUT/filename).exists(): doc=read(OUT/filename)
        else:
            doc={'metadata':dict(schema_id='local_spatial_content_r1',shard_id='berlin_transport_1900',anchor_place_id='place:berlin',
                                 anchor_lon_lat=[13.388,52.5219],radius_km=20,valid_from='1900-01-01',valid_to='9999-12-31',
                                 local_enabled=False,status='HISTORICAL_TRANSPORT_POINTS_ONLY',landmark_visuals=[],
                                 data_gaps=['No terrain shard or georeferenced 1900 track / road alignment.']),
                 'source_registry':{'schema_id':'historical_source_registry_v2','sources':[]},
                 'evidence_catalog':{'schema_id':'historical_fact_evidence_catalog_v2','facts':[]}}
        used={f['source_id'] for f in features}
        install_facts(doc,features,[s for s in srcs.values() if s['source_id'] in used],True)
        write(OUT/filename,doc)
        print(filename,'transport points',len(features))

def main():
    ign=read(RAW/'paris_topo_water.json')
    water=[]
    for f in ign['features']:
        if not f['properties'].get('nature','').startswith('Ecoulement'): continue
        original=shape(f['geometry'])
        levels=[p[2] for poly in polygons(original) for p in poly.exterior.coords if len(p)>2 and -100<p[2]<500]
        # Only a constant source elevation can be represented as a water level.
        level=levels[0] if levels and max(levels)-min(levels)<.01 else None
        water.append((f['properties']['cleabs'],xy_geometry(original),level))
    natural_content('paris_northern_france_1900.json','paris_surface_rge_alti.json',water)
    london=[(id,g,None) for id,g in osm_polygons('london_water_relation.xml','water_surface')]
    # Clip downloaded source relation to the actual acquired local grid.
    london_extent=grid_extent(read(OUT/'london_surface_ea_dtm.json'))
    london=[(id,g.intersection(london_extent),level) for id,g,level in london if g.intersects(london_extent)]
    natural_content('london_westminster_1900.json','london_surface_ea_dtm.json',london)
    wood=[(id,g,None) for id,g in osm_polygons('zermatt_wood_relation.xml','woodland')]
    wood.extend((id,g,None) for id,g in osm_polygons('zermatt_osm.xml','woodland') if id.startswith('osm:way/'))
    extent=grid_extent(read(OUT/'zermatt_west_surface_swissalti3d.json'))
    wood=[(id,g.intersection(extent),level) for id,g,level in wood if g.intersects(extent)]
    if wood:
        wood=[('osm:zermatt_woodland_union_r11',unary_union([g for _,g,_ in wood]),None)]
    natural_content('zermatt_west_physical_reference.json','zermatt_west_surface_swissalti3d.json',[],wood)
    nile=[(id,g,None) for id,g in osm_polygons('giza_water_relation.xml','water_surface')]
    extent=box(31.158,29.966,31.226,30.005)
    nile=[(id,g.intersection(extent),level) for id,g,level in nile if g.intersects(extent)]
    # Nile lies outside the admitted desert DSM. Keep actual water polygons on
    # the regional chart; do not synthesize a Nile-valley height raster.
    natural_content('giza_pyramids_1900.json','giza_west_surface_copdem.json',nile)
    transport()

if __name__=='__main__':
    main()
