"""Bounded R12 display compositions for existing Paris / London LOCAL shards.

Localities are sourced. Individual generic modules are explicitly abstract,
not a digitised 1900 cadastre. No random city, road, ownership or population.
The largest permitted display footprint is checked against the existing DEM
extent and acquired modern water triangles, not guessed historical river widths.
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/local'
WORK = ROOT / 'local-artifacts/settlement-miniatures-r12'
R = 6371008.8
MODULES = {'paris_mansard': (23, 13, 19.7), 'london_terrace': (24.5, 9.5, 12.3),
           'civic_hall': (25, 18, 13), 'rural_house': (11, 9, 6.9),
           'warehouse': (29, 16, 10), 'quay_platform': (30, 7, 2)}


def read(path):
    return json.loads(path.read_text(encoding='utf8'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')


def coordinate(anchor, east, north):
    """Same spherical azimuthal equidistant inverse as RegionProjection."""
    lon, lat = map(math.radians, anchor)
    distance = math.hypot(east, north)
    if distance == 0:
        return list(anchor)
    e = (math.cos(lon), 0, -math.sin(lon))
    n = (-math.sin(lon)*math.sin(lat), math.cos(lat), -math.cos(lon)*math.sin(lat))
    u = (math.cos(lat)*math.sin(lon), math.sin(lat), math.cos(lat)*math.cos(lon))
    a = distance/R
    p = [e[i]*east/distance*math.sin(a)+n[i]*north/distance*math.sin(a)+u[i]*math.cos(a) for i in range(3)]
    return [math.degrees(math.atan2(p[0], p[2])), math.degrees(math.asin(p[1]))]


def cross(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def inside(p, polygon):
    sign = [cross(polygon[i], polygon[(i+1) % len(polygon)], p) for i in range(len(polygon))]
    return min(sign) >= -1e-14 or max(sign) <= 1e-14


def overlaps(a, b):
    if any(max(p[axis] for p in a) < min(p[axis] for p in b) or
           max(p[axis] for p in b) < min(p[axis] for p in a) for axis in (0, 1)):
        return False
    if any(inside(p, b) for p in a) or any(inside(p, a) for p in b):
        return True
    for i, p in enumerate(a):
        q = a[(i+1) % len(a)]
        for j, r in enumerate(b):
            s = b[(j+1) % len(b)]
            if cross(p, q, r)*cross(p, q, s) < 0 and cross(r, s, p)*cross(r, s, q) < 0:
                return True
    return False


def safe_placements(anchor, candidates, surface, exclusions):
    west, top, step = surface['west_cell_centre'], surface['north_cell_centre'], surface['step_degrees']
    east = west+(surface['width']-1)*step
    bottom = top-(surface['height']-1)*step
    water = [triangle for cover in surface.get('cover_meshes', [])
             if cover['kind'] == 'water_surface' for triangle in cover['triangles']]
    accepted = []
    footprints = []
    for module, x, y, heading, scale in candidates:
        w, d, h = MODULES[module]
        # Display enlargement is capped at 3x. No amplified footprint crosses water.
        w, d = w*scale[0]*3+4, d*scale[2]*3+4
        a = math.radians(heading)
        footprint = [coordinate(anchor, x+dx*math.cos(a)-dy*math.sin(a),
                                y+dx*math.sin(a)+dy*math.cos(a))
                     for dx, dy in [(-w/2, -d/2), (w/2, -d/2), (w/2, d/2), (-w/2, d/2)]]
        if not all(west < p[0] < east and bottom < p[1] < top for p in footprint):
            continue
        if any(overlaps(footprint, triangle) for triangle in water):
            continue
        if any(overlaps(footprint, previous) for previous in footprints):
            continue
        centre = coordinate(anchor, x, y)
        if any(math.hypot(math.radians(centre[0]-q[0])*R*math.cos(math.radians(centre[1])),
                          math.radians(centre[1]-q[1])*R) < radius for q, radius in exclusions):
            continue
        accepted.append({'module': module, 'offset_m': [x, y], 'heading_degrees': heading,
                         'scale': scale})
        footprints.append(footprint)
    return accepted


def source(id, title, publisher, locator, year, note):
    return {'source_id': id, 'title': title, 'publisher': publisher,
            'version': 'R12_2026-10-14', 'locator': locator, 'license': 'CC0-1.0 (WWO original factual summary and abstract composition only)',
            'access_metadata': {'source_year': year, 'historical_applicability': '1900-01-01 locality reference; no measured building footprints',
                                'rights_note': note}}


PARIS = source('paris_locality_miniature_r12', 'Paris and its environs, 14th edition, Gros-Caillou / Champ-de-Mars',
    'Karl Baedeker, 1900', 'https://archive.org/details/14thedbaedparis00karl', 1900,
    'Public-domain 1900 publication. Existing original retained. Only facts and original conceptual geometry distributed; no map scan copied.')
LONDON = source('westminster_locality_miniature_r12', 'Westminster / Millbank late-Victorian locality reference',
    'Historic England / OS historical mapping cited by Westminster City Council',
    'https://historicengland.org.uk/listing/the-list/list-entry/1000845', '1894–1896 map; HE record written 2002, edited 2003',
    'Independent factual summary. No HE photographs, text, modern OS map or commercial Groundsure scan distributed. Council 2018 archaeological report consulted only.')


def install(filename, feature, src, candidates, exclusions=()):
    doc = read(OUT/filename)
    surface = read(ROOT / doc['metadata']['surface_reference_path'].removeprefix('res://'))
    anchor = feature['geometry']['coordinates']
    placements = safe_placements(anchor, candidates, surface, exclusions)
    feature['miniature_layout'] = {
        'anchor_place_id': doc['metadata']['anchor_place_id'],
        'model_path': 'res://assets/settlements/cabinet_building_modules.glb',
        'geometry_role': 'ABSTRACT_MINIATURE_COMPOSITION', 'max_mpp': 24,
        'scale_max': 3, 'target_height_px': 12, 'placements': placements,
        'placement_notice_zh': '通用体块的排列属于抽象微缩表现，不是1900年逐栋建筑坐标或产权。',
        'water_reference': 'Existing R11 modern water / DEM only; bank changes before/after 1900 are not resolved.'}
    feature.update(kind='geographic_region', rank=1, max_mpp=900,
                   valid_from='1900-01-01', valid_to='1901-01-01',
                   source_id=src['source_id'], source_type='BOUNDED_ESTIMATE', source_reference=src['locator'],
                   source_name_zh=src['publisher'], source_license=src['license'],
                   geometry_evidence_type='BOUNDED_HISTORICAL_LOCALITY',
                   coordinate_uncertainty_m=100)
    # This is the same admitted source/fact collection; not a second city state.
    sources = doc['source_registry']['sources']
    sources[:] = [s for s in sources if s['source_id'] != src['source_id']]+[src]
    facts = doc['evidence_catalog']['facts']
    facts[:] = [f for f in facts if f['subject_id'] != feature['id']]
    facts.append({'fact_id': 'local_spatial:'+feature['id'], 'domain': 'local_spatial_content',
                  'subject_id': feature['id'], 'value': feature, 'unit': 'display_geography',
                  'source_id': src['source_id'], 'source_version': src['version'], 'source_locator': src['locator'],
                  'observation_period': {'from': '1900-01-01', 'to': '1900-01-01'},
                  'spatial_scope': {'kind': 'content_shard', 'id': doc['metadata']['shard_id']},
                  'methodology': 'Sourced locality, original abstract miniature; maximum 3x footprints exclude acquired modern water and existing landmark locations. No cadastral claims.',
                  'confidence': 0.6, 'lower_bound': None, 'upper_bound': None,
                  'license': src['license'], 'review_status': 'BOUNDED_ESTIMATE',
                  'generator': 'tools/map/build_settlement_placements.py'})
    write(OUT/filename, doc)
    print(feature['id'], 'modules', len(placements))
    return {'id': feature['id'], 'anchor': anchor, 'modules': len(placements),
            'abstract_placement': True, 'source': src['locator']}


def main():
    report = []
    # Deliberate small compositions. Offsets are visual, never historical facts.
    paris = [('paris_mansard', x, y, -28, [1, 1, 1])
             for x in (-160, -60, 40, 140) for y in (-160, -50, 60, 170)]
    paris += [('civic_hall', 240, -50, -28, [1, 1, 1]),
              ('warehouse', 240, 70, -28, [1, 1, 1])]
    report.append(install('paris_northern_france_1900.json', {
        'id': 'geographic_region:paris_gros_caillou_miniature', 'display_name': '巴黎 · Gros-Caillou微缩街区',
        'display_kind': 'settlement_miniature', 'parent_country_id': 'country_fra',
        'geometry': {'type': 'Point', 'coordinates': [2.3020, 48.8587]},
        'note_zh': '1900年巴黎Gros-Caillou附近的概念性城市体块。Baedeker记录此地及相邻工业、展览区域；未取得可分发的逐栋1900年街区几何。这里不是精确街道、建筑用途或住房密度记录。'},
        PARIS, paris, [([2.2945, 48.858333], 210)]))
    london = [('london_terrace', x, y, -5, [1, 1, 1])
              for x in (-160, -60, 40, 140) for y in (-170, -60, 50, 160)]
    london.append(('civic_hall', 240, -60, -5, [1, 1, 1]))
    report.append(install('london_westminster_1900.json', {
        'id': 'geographic_region:westminster_miniature', 'display_name': '伦敦 · Westminster微缩街区',
        'display_kind': 'settlement_miniature', 'parent_country_id': 'british_isles_1900',
        'geometry': {'type': 'Point', 'coordinates': [-0.1311, 51.4972]},
        'note_zh': '威斯敏斯特西侧既有城市地域的概念性连排建筑组合。附近历史地图证实城市与河岸工业环境，但本组合不是历史街道或逐栋建筑重建，不复制议会宫或修道院。'},
        LONDON, london, [([-0.12457, 51.50067], 150), ([-0.1276, 51.4994], 160)]))
    # Narrow platforms remain on landward reference ground. The modern river
    # wall is not moved west to imitate the unembanked 1900 shore.
    wharf = [('quay_platform', 15, y, 80, [0.55, 1, 0.5]) for y in (5, 75)]
    wharf += [('warehouse', -55, y, -10, [0.65, 1, 0.8]) for y in (-65, 5, 75)]
    report.append(install('london_westminster_1900.json', {
        'id': 'geographic_region:millbank_wharves_1900', 'display_name': 'Millbank历史河岸码头区',
        'display_kind': 'historic_wharf', 'parent_country_id': 'british_isles_1900',
        'geometry': {'type': 'Point', 'coordinates': [-0.12475, 51.49635]},
        'note_zh': 'Victoria Tower Gardens南部在19世纪末仍有码头及工业设施，1909年后扩建公园。此点为约100米精度的历史地域代表位置；仓库与平台仅作微缩示意。现代岸墙不同于当时未筑堤的河岸，本轮不重建精确1900岸线，不创建港口企业、航运或设备能力。'},
        LONDON, wharf))
    WORK.mkdir(parents=True, exist_ok=True)
    write(WORK/'placements.json', report)


if __name__ == '__main__':
    main()
