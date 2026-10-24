"""Adapt existing admitted layouts and attach display-only terrain parameters.

No new place, building coordinate, administrative member or production fact.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODEL = 'res://assets/settlements/urban_landscape_r40.glb'


def main():
    for name in ['paris_northern_france_1900', 'london_westminster_1900',
                 'zermatt_west_physical_reference', 'giza_pyramids_1900']:
        path = ROOT / ('data/local/'+name+'.json')
        original = path.read_text(encoding='utf8')
        doc = json.loads(original)
        for fact in doc['evidence_catalog']['facts']:
            feature = fact.get('value', {})

            if isinstance(feature, dict) and feature.get('display_kind')=='transport_node':
                feature['transport_symbol'] = 'bridge' if feature['id'] in ['transport_reference:pont_iena','transport_reference:westminster_bridge'] else 'station'
            if not isinstance(feature, dict) or 'miniature_layout' not in feature:
                continue
            layout = feature['miniature_layout']
            layout['model_path'] = MODEL
            layout['lod_switch_mpp'] = 8.0
            layout['visual_revision'] = 'R40 original facades, dormers, rooflines, civic and warehouse detail'
            for i, placement in enumerate(layout['placements']):
                if placement['module'] in ['paris_mansard', 'paris_corner']:
                    placement['module'] = 'paris_corner' if i % 4 == 1 else 'paris_mansard'
                elif placement['module'] in ['london_terrace', 'london_gabled']:
                    placement['module'] = 'london_gabled' if i % 3 == 1 else 'london_terrace'
                elif name.startswith('paris') and placement['module'] == 'warehouse':
                    placement['module'] = 'sawtooth_workshop'
            # The new meshes stay inside the previously water-checked R12
            # ground footprint. Existing offsets, heading and scale stay intact.
            feature['note_zh'] = feature['note_zh'].split(' R40：')[0]+' R40：原创立面、屋顶与构件升级；原概念位置不变，不代表实测建筑或经营设施。'
        presentation = {'role': 'DISPLAY_ONLY_NOT_LAND_COVER_OR_SIMULATION',
                        'note_zh': '色调、等高线和参考树木仅用于显示；不写入土地、经济或军事状态。'}
        if name.startswith('zermatt'):
            presentation.update(woodland_instances={'max_instances': 96, 'spacing_m': 65.0, 'max_mpp': 12.0,
                'source': 'Existing modern OSM woodland mask R29; not 1900 forest density',
                'footprint_radius_m': 3.5})
        if name.startswith('giza'):
            presentation.update(palette={'low': '#9d9174', 'high': '#b9ab8b',
                'meaning': 'Warm cartographic stone/earth printing palette; no desert or geology classification'},
                contour_interval_m=10.0,
                contour_note_zh='现代Copernicus DSM的10米高程等值线；只覆盖原有西侧DSM，不延伸到金字塔基座。')
        doc['metadata']['surface_presentation'] = presentation
        attribution = {
            'paris_northern_france_1900': '现代 DEM · © IGN · 概念街区非逐栋史实',
            'london_westminster_1900': '现代 DTM · EA · 河线非1900河岸',
            'zermatt_west_physical_reference': '现代 DEM · © swisstopo · OSM林地非1900',
            'giza_pyramids_1900': '现代 DSM · Copernicus · 金字塔基座为平面',
        }
        doc['metadata']['map_attribution_zh'] = attribution[name]
        extra = '林地内的参考树木不表示1900年林木密度。' if name.startswith('zermatt') else '西侧DSM等高线不延伸到金字塔基座。' if name.startswith('giza') else '原创建筑细节沿用原概念布局，不是逐栋历史复原。'
        doc['metadata']['terrain_note_zh'] = doc['metadata']['terrain_note_zh'].split(' R40：')[0]+' R40：'+extra
        # An external writer must not be overwritten between read and write.
        if path.read_text(encoding='utf8') != original:
            raise RuntimeError('Concurrent source edit: '+str(path))
        path.write_text(json.dumps(doc, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf8')
        print(name, 'installed R40 visual adaptation', flush=True)


if __name__ == '__main__':
    main()
