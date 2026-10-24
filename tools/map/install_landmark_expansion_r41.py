"""Install reviewed display references, using the existing R23 source/fact schema."""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NOTICE = '仅本机内部预览；模型作者与再分发权待确认，非1900精确复原。'


def main():
    specs = json.loads((ROOT/'tools/map/r41_landmark_expansion.json').read_text(encoding='utf8'))
    specs = [s for s in specs if s.get('admitted', True)]
    metrics = {m['key']: m for m in json.loads((ROOT/'tools/map/model_sources/r41/cloud_adaptations/model_counts.json').read_text(encoding='utf8'))}
    catalog = {e['number']: e for e in json.loads((ROOT/'docs/map/drive_landmark_catalog_r15.json').read_text(encoding='utf8'))['entries']}
    template = json.loads((ROOT/'data/local/internal_preview_r23/pont_du_gard.json').read_text(encoding='utf8'))
    dest = ROOT/'data/local/internal_preview_r41'
    dest.mkdir(parents=True, exist_ok=True)
    for spec in specs:
        key = spec['key']
        m, entry = metrics[key], catalog[spec['number']]
        id = 'landmark:'+key+'_reference'
        source_id = 'r41_'+key+'_display_reference'
        visual = copy.deepcopy(template['metadata']['landmark_visuals'][0])
        for field in ['model_metric_scale', 'model_origin_units', 'model_surface_indices']:
            visual.pop(field, None) # Offline asset is already metric and stripped.
        visual.update({
            'id': id, 'display_name': spec['name']+' · 内部示意', 'anchor_place_id': id,
            'anchor_name_zh': spec['name'], 'parent_country_id': spec['country'],
            'geometry': {'type': 'Point', 'coordinates': spec['point']},
            'existence_note_zh': spec['note'], 'historical_reference_zh': NOTICE+' '+spec['note'],
            'real_dimensions_note_zh': '按约定参考高度统一换算米制，横向保留原示意比例；不是1900测量或完整遗产区范围。',
            'dimensions_type': 'SCHEMATIC_METRES',
            'model_path': 'res://assets/landmarks/internal_preview_r41/'+key+'.glb',
            'model_height_m': m['height_m'], 'model_base_width_m': m['footprint_m'][0],
            'model_footprint_m': m['footprint_m'], 'model_lod_switch_mpp': 4,
            'model_admission_mpp': 12, 'model_max_mpp': 12,
            'source_id': source_id, 'source_date': '2026-10-18',
            'source_name_zh': '历史机构 / 用户二工云盘；位置参考另列',
            'source_reference': spec['history'], 'coordinate_source_reference': spec['locator'],
            'coordinate_notice_zh': '固定遗址或遗产区的现代代表位置，不是1900精测坐标；约250米定位限制。',
            'terrain_note_zh': '本站没有LOCAL DEM；使用原无DEM地标相对平面。演示地形、水面、草坪已剔除，不生成当地覆盖。',
            'model_source_url': entry['source_url'], 'resource_structure': m,
        })
        visual.pop('real_height_m', None)
        visual.pop('real_base_width_m', None)
        source = copy.deepcopy(template['source_registry']['sources'][0])
        source.update({'source_id': source_id, 'title': spec['name']+' historical display reference',
                       'version': 'R41_2026-10-18', 'locator': spec['history']})
        source['access_metadata'].update({'coordinate_reference': spec['locator'],
            'model_reference': entry['source_url'], 'historical_applicability': spec['note'],
            'additional_reference': spec.get('extra', ''), 'rights_notice': NOTICE})
        fact = copy.deepcopy(template['evidence_catalog']['facts'][0])
        fact.update({'fact_id': 'local_spatial:'+id, 'subject_id': id, 'value': visual,
            'source_id': source_id, 'source_version': 'R41_2026-10-18',
            'source_locator': spec['history'], 'generator': 'tools/map/install_landmark_expansion_r41.py'})
        fact['spatial_scope']['id'] = 'r41_'+key
        metadata = copy.deepcopy(template['metadata'])
        metadata.update({'shard_id': 'r41_'+key, 'anchor_place_id': id,
            'anchor_lon_lat': spec['point'], 'radius_km': 8,
            'landmark_visuals': [visual], 'terrain_note_zh': visual['terrain_note_zh']})
        doc = {'metadata': metadata, 'source_registry': {'schema_id': 'historical_source_registry_v2', 'sources': [source]},
               'evidence_catalog': {'schema_id': 'historical_fact_evidence_catalog_v2', 'facts': [fact]}}
        (dest/(key+'.json')).write_text(json.dumps(doc, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
    # Density is an art sampling parameter inside the unchanged R29 mask.
    p = ROOT/'data/local/zermatt_west_physical_reference.json'
    original = p.read_text(encoding='utf8')
    doc = json.loads(original)
    doc['metadata']['surface_presentation']['woodland_instances']['spacing_m'] = 50
    if p.read_text(encoding='utf8')!=original:
        raise RuntimeError('Concurrent source edit: '+str(p))
    p.write_text(json.dumps(doc, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')
    print('Installed', len(specs), 'internal display references; retained forest mask and instance cap')


if __name__=='__main__':
    main()
