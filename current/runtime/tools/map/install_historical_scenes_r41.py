"""Attach original models to existing admitted transport IDs, not world assets.

Bridge display locators are refined against already acquired modern water only.
No raw GIS, heights, transport relationships or historical point coordinates change.
Uses the project's existing Shapely installation; no downloads.
"""
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'local-artifacts/historical-islands-admin-r5/python-libs'))
sys.path.insert(0, str(ROOT/'local-artifacts/local-landscape-r4/python-libs'))
from shapely.geometry import Point, Polygon, LineString
from shapely.ops import unary_union

MODELS = {
    'transport_reference:pont_iena': {
        'file': 'pont_iena_r41', 'shard': 'paris_northern_france_1900',
        'footprint': [155, 19], 'height': 17.2, 'lod': 3.0,
        'source': 'https://www.paris.fr/pages/lifting-reussi-pour-les-cavaliers-du-pont-d-iena-27479',
        'extra_source': 'https://parigi2024.coni.it/it/gare/impianti/impianto/5:Pont_d%27Iena.html',
        'note': '五孔石拱、桥墩、栏杆与1853年骑马雕像的轮廓示意。采用拓宽前14米石桥主体，未做1937年35米桥面；1900年临时加宽的安装日期和细部未确认。模型不是精密复原。',
    },
    'transport_reference:westminster_bridge': {
        'file': 'westminster_bridge_r41', 'shard': 'london_westminster_1900',
        'footprint': [250, 27], 'height': 17.5, 'lod': 3.0,
        'source': 'https://historicengland.org.uk/listing/the-list/list-entry/1066172?section=official-listing',
        'note': '1862年七孔金属拱桥示意；花岗岩墩台、透空拱上构件、哥特式栏杆及灯柱。250×26米为本模型参考包络；分孔长度、涂色和桥头接合未作1900年精测复原。',
    },
    'transport_reference:paris_nord': {
        'file': 'gare_du_nord_r41', 'shard': 'paris_northern_france_1900',
        'footprint': [156, 112], 'height': 31, 'lod': 5.0, 'heading': 0,
        'source': 'https://www.garesetconnexions.sncf/fr/histoire-gare-du-nord',
        'extra_source': 'https://www.paris.fr/pages/sept-realisations-emblematiques-de-jacques-ignace-hittorff-l-architecte-de-la-gare-du-nord-22333',
        'note': 'Hittorff的1860年代站房形制示意：新古典立面、中央山花、拱窗、寓意雕像轮廓与铁玻璃大厅。156×112米为示意包络；不复原1900年轨道、站台数量和精确平面。此处在既有巴黎DEM以外，使用局部相对平面。',
    },
    'transport_reference:friedrichstrasse': {
        'file': 'friedrichstrasse_1882_r41', 'shard': 'berlin_transport_1900',
        'footprint': [114, 60], 'height': 24, 'lod': 5.0, 'heading': -10,
        'source': 'https://denkmaldatenbank.berlin.de/daobj.php?obj_dok_nr=09080415',
        'extra_source': 'https://commons.wikimedia.org/wiki/File:Holzstich_G._Heuer,_%C3%9Cbergang_am_Bahnhof_Friedrichstra%C3%9Fe,_1882.jpg',
        'note': '1882年Stadtbahn时期单厅铁玻璃拱顶、砖砌高架和入口的历史示意。114×60米为模型包络，非实测；不使用1919—1925年双厅改建形制，不制作未知轨道、站台数。柏林无LOCAL DEM，基座仅为相对平面。',
    },
}


def bridge_placement(doc, feature, model):
    surface = json.loads((ROOT/doc['metadata']['surface_reference_path'][6:]).read_text(encoding='utf8'))
    lon, lat = feature['geometry']['coordinates']
    east = 111320*math.cos(math.radians(lat))
    north = 111320
    def metric(p): return ((p[0]-lon)*east, (p[1]-lat)*north)
    def geo(p): return [round(lon+p[0]/east, 9), round(lat+p[1]/north, 9)]
    water = unary_union([Polygon([metric(p) for p in tri])
                         for cover in surface.get('cover_meshes', [])
                         if cover['kind']=='water_surface' for tri in cover['triangles']])
    local = water.intersection(Point(0, 0).buffer(300))
    if local.is_empty:
        raise ValueError('No acquired water reference at '+feature['id'])
    corners = list(local.minimum_rotated_rectangle.exterior.coords)
    edges = [(b[0]-a[0], b[1]-a[1]) for a, b in zip(corners, corners[1:])]
    tangent = max(edges, key=lambda p: p[0]**2+p[1]**2)
    norm = math.hypot(*tangent)
    # Across the local water reference; this is not a surveyed bridge bearing.
    dx, dy = -tangent[1]/norm, tangent[0]/norm
    cut = water.intersection(LineString([(-dx*600, -dy*600), (dx*600, dy*600)]))
    segments = [cut] if cut.geom_type=='LineString' else list(cut.geoms)
    segments = [s for s in segments if s.geom_type=='LineString' and s.length>10]
    segment = min(segments, key=lambda s: s.distance(Point(0, 0)))
    centre = segment.interpolate(.5, normalized=True)
    if centre.distance(Point(0, 0))>float(feature['coordinate_uncertainty_m']):
        raise ValueError('Refinement outside admitted locator uncertainty: '+feature['id'])
    centre_xy = (centre.x, centre.y)
    half_span = model['footprint'][0]/2
    return {
        'display_lon_lat': geo(centre_xy),
        'model_heading_degrees': round(math.degrees(math.atan2(dy, dx)), 4),
        'ground_samples_lon_lat': [geo((centre.x-dx*half_span, centre.y-dy*half_span)),
                                   geo((centre.x+dx*half_span, centre.y+dy*half_span))],
        'model_ground_datum_m': 12.0,
        'placement_offset_m': round(centre.distance(Point(0, 0)), 2),
        'modern_water_reference_piece_m': round(segment.length, 2),
        'placement_source_reference': surface.get('cover_note_zh', ''),
        'water_reference_sources': [{'source_id': c.get('source_id', ''),
                                     'url': c.get('source_reference', ''),
                                     'license': c.get('license', '')}
                                    for c in surface.get('cover_meshes', []) if c['kind']=='water_surface'],
        'placement_note_zh': '原地点坐标不变。模型显示中心及横河方向取自既有有限现代水域，位于原定位不确定性内；交线片段不是完整河宽。桥面按模型两端已有DEM较高值落位。未认定1900年河岸、水位或桥头精确接合；不新画水面。',
    }


def main():
    sys.stdout.reconfigure(encoding='utf8')
    for shard in sorted({m['shard'] for m in MODELS.values()}):
        path = ROOT/'data/local'/(shard+'.json')
        original = path.read_text(encoding='utf8')
        doc = json.loads(original)
        features = {f['value']['id']: f['value'] for f in doc['evidence_catalog']['facts']}
        visuals = doc['metadata'].setdefault('landmark_visuals', [])
        ids = {i for i, m in MODELS.items() if m['shard']==shard}
        visuals[:] = [v for v in visuals if v['id'] not in ids]
        for id in sorted(ids):
            model, feature = MODELS[id], features[id]
            source_id = model['file']+'_original_model'
            source = {'source_id': source_id, 'title': 'WWO original historical reference: '+model['file'],
                      'publisher': 'WWO original geometry; historical basis linked', 'version': 'R41_2026-10-18',
                      'license': 'Original WWO mesh; factual references only; no third-party media copied',
                      'locator': model['source'], 'access_metadata': {
                          'source_type': 'HISTORICAL_EVIDENCE',
                          'historical_applicability': model['note'],
                          'additional_locator': model.get('extra_source', '')}}
            sources = doc['source_registry']['sources']
            sources[:] = [s for s in sources if s['source_id']!=source_id]
            sources.append(source)
            visual = {
                'id': id, 'kind': 'landmark', 'display_name': feature['display_name'], 'rank': 1,
                'anchor_place_id': id, 'local_anchor_id': doc['metadata']['anchor_place_id'],
                'parent_country_id': feature['parent_country_id'], 'geometry': feature['geometry'],
                'valid_from': feature['valid_from'], 'valid_to': feature['valid_to'],
                'existence_confirmed_on': '1900-01-01', 'model_reference_year': 1900,
                'model_path': 'res://assets/landmarks/'+model['file']+'.glb',
                'model_height_m': model['height'], 'model_base_width_m': model['footprint'][0],
                'model_footprint_m': model['footprint'], 'model_heading_degrees': model.get('heading', 0),
                'model_max_mpp': 16, 'model_admission_mpp': 12,
                'symbol_max_mpp': 1200, 'model_lod_switch_mpp': model['lod'],
                'display_scale_max': 1, 'display_width_max_px': 520,
                'source_id': source_id, 'source_reference': model['source'],
                'model_note_zh': model['note'],
            }
            if 'bridge' in id or 'iena' in id:
                placement = bridge_placement(doc, feature, model)
                visual.update(placement)
                feature['model_placement_note_zh'] = placement['placement_note_zh']
                print(id, json.dumps(placement, ensure_ascii=False))
            feature['model_note_zh'] = model['note']+' 位置沿用原地点ID及约100—250米代表定位；不产生运输能力或经济资产。'
            feature['model_source_reference'] = model['source']
            visuals.append(visual)
        if shard=='berlin_transport_1900':
            doc['metadata']['local_enabled'] = True
            doc['metadata']['local_min_mpp'] = 2
            doc['metadata']['status'] = 'HISTORICAL_TRANSPORT_POINTS_WITH_BOUNDED_MODEL'
            doc['metadata']['terrain_note_zh'] = '柏林无已接入LOCAL DEM；站房使用原有无DEM地标相对平面，不创建地形。'
        if path.read_text(encoding='utf8')!=original:
            raise RuntimeError('Concurrent source edit: '+str(path))
        path.write_text(json.dumps(doc, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')
        print(shard, 'attached', len(ids), 'models to existing IDs')


if __name__ == '__main__':
    main()
