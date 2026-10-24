"""Metadata/header-only terrain inventory. No raster inflation, downloads or hashes."""
import argparse
import collections
import configparser
import fnmatch
import json
import os
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[2]
CATALOGS = ['global_physical_relief', 'sampling_surface_r57', 'asian_surface_r51',
            'northern_surface_r52', 'canary_surface_r45']
BASES = {'euro_afro_russia_r57_base', 'greenland_r52_base', 'canary_r45_base',
         'asia_west_r51_base', 'asia_east_r51_base'}
REGIONS = [
    ('西欧／中欧', [-12, 35, 25, 61]), ('北欧／波罗的海', [-26, 54, 36, 80]),
    ('高加索', [36, 36, 52, 47]), ('欧洲俄罗斯', [25, 44, 70, 82]),
    ('西伯利亚', [60, 46, 150, 82]), ('中亚', [45, 34, 90, 56]),
    ('俄国远东', [120, 40, 192, 82]), ('亚洲其他地区', [60, -10, 180, 40]),
    ('阿拉伯半岛', [34, 12, 60, 33]), ('北非', [-18, 15, 40, 37]),
    ('撒哈拉以南非洲', [-18, -36, 52, 15]), ('北美', [-170, 7, -52, 73]),
    ('南美', [-82, -56, -34, 13]), ('大洋洲', [110, -50, 180, 0]),
    ('格陵兰', [-76, 58, -10, 86]), ('南极', [-180, -90, 180, -60]),
    ('北极86度以北', [-180, 86, 180, 90])]


def assets(document):
    for fact in document.get('evidence_catalog', {}).get('facts', []):
        yield from fact.get('value', {}).get('assets', [])


def ident(asset):
    return asset['id'].split(':', 1)[-1]


def intersects(a, b):
    if a[3] <= b[1] or a[1] >= b[3]:
        return False
    return any(a[2]+shift > b[0] and a[0]+shift < b[2] for shift in (-360, 0, 360))


def spacing(a):
    return abs(a.get('display_spacing_degrees', [0, 0])[1])*111195


def source(a):
    p = a.get('precision', {})
    cells = p.get('dem_cells', [])
    name = a.get('dem_source', '')
    if cells:
        # Rectangular cells can overlap and contain provider ocean gaps.
        # Do not report their summed area as surveyed land coverage.
        return 'mixed'
    if p.get('dem_extract_m_ns', 0):
        return 'GLO' if p['dem_extract_m_ns'] < 500 else 'ETOPO'
    if name.startswith('GLO90'):
        return 'mixed'
    return 'ETOPO' if name.startswith('ETOPO2022-60s') else 'unknown'


def inventory():
    docs = {}
    all_paths = set()
    for path in sorted((ROOT/'data/presentation').glob('*.json')):
        if 'surface_r' not in path.stem and path.stem != 'global_physical_relief':
            continue
        doc = json.loads(path.read_text(encoding='utf-8'))
        docs[path.stem] = list(assets(doc))
        all_paths.update(a['path'] for a in docs[path.stem])
    admitted = {}
    for name in CATALOGS:
        for a in docs[name]:
            admitted.setdefault(ident(a), a)
    replaced = {old for a in admitted.values() for old in a.get('surface_replaces', [])}
    bases = [a for key, a in admitted.items() if key in BASES]
    details = [a for key, a in admitted.items() if a.get('surface_role') == 'detail'
               and key not in replaced and any(intersects(a['core_bounds_lon_lat'], b['bounds_lon_lat']) for b in bases)]
    live = bases + details + list(docs['global_physical_relief'])
    extracts = {}
    for a in live:
        for kind in ('dem_cells', 'cover_cells'):
            for cell in a.get('precision', {}).get(kind, []):
                if cell.get('extract_path'):
                    extracts.setdefault(kind, set()).add(cell['extract_path'])
    extract_status = {kind: {'recorded_paths': len(items),
                            'present': sum((ROOT/p).is_file() for p in items)}
                      for kind, items in extracts.items()}
    failures = []
    paths = {a['path']: a for a in live}
    preset = configparser.ConfigParser(interpolation=None)
    preset.read(ROOT/'export_presets.cfg', encoding='utf-8')
    excluded = json.loads(preset['preset.3']['exclude_filter']).split(',')
    excluded_live = [p for p in paths if any(fnmatch.fnmatchcase(p.removeprefix('res://'), pattern) for pattern in excluded)]
    for name, a in paths.items():
        p = (ROOT/name.removeprefix('res://')).resolve()
        if not p.is_relative_to(ROOT/'assets/maps/relief') or not p.is_file():
            failures.append(name+': missing or outside relief root')
            continue
        if a['format'] == 'RGBA8_MIP_DEFLATE':
            with p.open('rb') as f:
                header = f.read(20)
            if len(header) != 20 or header[:5] != b'FRT42' or struct.unpack_from('<III', header, 8) != (int(a['width']), int(a['height']), int(a['decoded_bytes'])):
                failures.append(name+': header differs from catalogue')
    rows = []
    for name, bounds in REGIONS:
        matches = [a for a in details if intersects(a['core_bounds_lon_lat'], bounds)]
        b = [ident(a) for a in bases if intersects(a['bounds_lon_lat'], bounds)]
        count = collections.Counter(source(a) for a in matches)
        sizes = collections.Counter(int(a.get('surface_lod_degrees', 2)) for a in matches)
        steps = [spacing(a) for a in matches]
        covers = [a.get('precision', {}).get('cover_m_ns_max', 0) for a in matches]
        rows.append({'region': name, 'bounds': bounds, 'bases': b, 'counts': dict(count), 'lods': dict(sizes),
                     'output_m': [round(min(steps)), round(max(steps))] if steps else [],
                     'cover_recorded_m': sorted({round(x) for x in covers if x}),
                     'cover_unknown_assets': sum(x == 0 for x in covers)})
    return {'catalogue_paths': len(all_paths), 'reachable_ids': len(admitted), 'base_ids': [ident(a) for a in bases],
            'eligible_detail_ids': len(details), 'source_only_or_replaced_ids': len(replaced),
            'live_file_paths': len(paths), 'live_bytes': sum((ROOT/p.removeprefix('res://')).stat().st_size for p in paths if (ROOT/p.removeprefix('res://')).exists()),
            'max_decoded_bytes': max(a.get('decoded_bytes', 0) for a in live), 'header_errors': failures,
            'eligible_export_excluded': excluded_live, 'recorded_extract_paths': extract_status, 'regions': rows}


def markdown(data):
    lines = ['| 地理区域／核查矩形 | 相交概览 | 2°／8°／16°候选记录数 | GLO／混合／ETOPO／未知来源数 | 输出NS间距m | WC已记录采样m；未知资产数 |',
             '|---|---|---:|---:|---:|---|']
    for row in data['regions']:
        c, n = row['counts'], row['lods']
        lines.append('| '+row['region']+' '+str(row['bounds'])+' | '+(', '.join(row['bases']) or '仅全球region')+' | '+
                     '/'.join(str(n.get(x, 0)) for x in (2, 8, 16))+' | '+
                     '/'.join(str(c.get(x, 0)) for x in ('GLO', 'mixed', 'ETOPO', 'unknown'))+' | '+
                     str(row['output_m'])+' | '+str(row['cover_recorded_m'])+'；'+str(row['cover_unknown_assets'])+' |')
    return '\n'.join(lines)


def source_inventory():
    """Offline path/consumer record; not a second runtime source registry."""
    admitted = {}
    for name in CATALOGS:
        for a in assets(json.loads((ROOT/'data/presentation'/f'{name}.json').read_text(encoding='utf-8'))):
            admitted.setdefault(ident(a), a)
    replaced = {old for a in admitted.values() for old in a.get('surface_replaces', [])}
    bases = [a for k, a in admitted.items() if k in BASES]
    live = [a for k, a in admitted.items() if k in BASES or k not in replaced and a.get('surface_role') == 'detail'
            and any(intersects(a['core_bounds_lon_lat'], b['bounds_lon_lat']) for b in bases)]
    consumers, refs, occurrences = [], {}, collections.Counter()
    for a in live:
        cells = [(kind, c) for kind in ('dem_cells', 'cover_cells') for c in a.get('precision', {}).get(kind, [])]
        if not cells:
            continue
        owner = len(consumers)
        consumers.append({'id': ident(a), 'path': a['path'], 'present': (ROOT/a['path'].removeprefix('res://')).is_file()})
        for kind, cell in cells:
            path = cell['extract_path'].replace('\\', '/')
            row = refs.setdefault((kind, path), {'path': path, 'kind': kind, 'consumers': set(), 'specs': []})
            if cell.get('provider_key'):
                row['provider_key'] = cell['provider_key']
                row['provider_url'] = cell['provider_url']
            row['consumers'].add(owner)
            spec = {k: cell[k] for k in ('bounds', 'm', 'shape', 'meaning') if k in cell}
            if spec not in row['specs']:
                row['specs'].append(spec)
            occurrences[kind] += 1
    filenames, archives, rasters, scanned, skipped = {}, [], [], 0, []
    root = ROOT/'local-artifacts'
    for base, directories, files in os.walk(root, followlinks=False):
        for name in directories[:]:
            p = Path(base)/name
            if p.is_symlink() or p.is_junction():
                directories.remove(name)
                skipped.append(p.relative_to(ROOT).as_posix())
        for name in files:
            p = Path(base)/name
            if p.is_symlink():
                continue
            scanned += 1
            filenames.setdefault(name, []).append(p)
            if p.suffix.lower() in ('.zip', '.7z', '.tar', '.tgz', '.gz', '.zst'):
                archives.append(p.relative_to(ROOT).as_posix())
            if p.suffix.lower() in ('.tif', '.tiff', '.vrt', '.hgt', '.asc', '.img', '.nc', '.npy', '.npz'):
                rasters.append(p.relative_to(ROOT).as_posix())
    lists = [p for names in filenames.values() for p in names if p.suffix == '.txt' and ('keys' in p.stem or p.name == 'copdem_tileList.txt')]
    keys = {'dem_cells': set(), 'cover_cells': set()}
    for p in lists:
        text = p.read_text(encoding='utf-8', errors='replace')
        keys['dem_cells'].update(re.findall(r'Copernicus_DSM_COG_30_[NS]\d{2}_00_[EW]\d{3}_00_DEM', text))
        keys['cover_cells'].update(re.findall(r'ESA_WorldCover_10m_2021_v200_[NS]\d{2}[EW]\d{3}_Map.tif', text))
    objects, object_ids, rows = [], {}, []
    for (kind, path), row in sorted(refs.items()):
        if row.get('provider_key'):
            key, url = row['provider_key'], row['provider_url']
        else:
            y, x = map(int, Path(path).stem.split('_'))
            ns, ew = ('N' if y >= 0 else 'S'), ('E' if x >= 0 else 'W')
        if not row.get('provider_key') and kind == 'dem_cells':
            key = f'Copernicus_DSM_COG_30_{ns}{abs(y):02d}_00_{ew}{abs(x):03d}_00_DEM'
            url = f'https://copernicus-dem-90m.s3.amazonaws.com/{key}/{key}.tif'
        elif not row.get('provider_key'):
            key = f'ESA_WorldCover_10m_2021_v200_{ns}{abs(y):02d}{ew}{abs(x):03d}_Map.tif'
            url = f'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/{key}'
        identity = (kind, key)
        if identity not in object_ids:
            object_ids[identity] = len(objects)
            objects.append({'kind': kind, 'key': key, 'url': url, 'in_retained_provider_list': key in keys[kind]})
        row['object'] = object_ids[identity]
        row['consumers'] = sorted(row['consumers'])
        # Search hits are candidates only. A matching name never establishes
        # affine/NoData/product identity or authorizes a producer substitution.
        hits = filenames.get(Path(path).name, [])
        row['candidate_paths'] = [p.relative_to(ROOT).as_posix() for p in hits]
        row['recorded_path_present'] = (ROOT/path).is_file()
        row['old_parent_root_present'] = (ROOT.parent/path).is_file()
        row['local_status'] = 'UNVERIFIED_CANDIDATE' if hits or row['recorded_path_present'] else 'C'
        row['recovery_plan'] = 'D' if key in keys[kind] else 'E'
        rows.append(row)
    return {'schema': 'r57_offline_source_audit_1', 'scope': 'Current selector-eligible precision cells; names/metadata only, no raster inflation or hashes',
            'scan': {'root': root.as_posix(), 'files': scanned, 'skipped_links': skipped, 'archives': archives, 'raster_candidates': rasters,
                     'provider_lists': [p.relative_to(ROOT).as_posix() for p in lists]},
            'summary': {'occurrences': dict(occurrences), 'unique_recorded_paths': len(rows), 'logical_provider_objects': len(objects),
                        'located_verified_files': 0, 'candidate_paths': sum(len(r['candidate_paths']) for r in rows),
                        'source_version_id_retained': False}, 'consumers': consumers, 'objects': objects, 'references': rows}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--sources', action='store_true', help='Deduplicate source paths, provider objects and formal consumers; no downloads')
    parser.add_argument('--output', type=Path, help='One overwriteable offline JSON record; does not modify catalogues')
    args = parser.parse_args()
    d = source_inventory() if args.sources else inventory()
    if args.output:
        target = args.output.resolve()
        if not target.is_relative_to((ROOT/'local-artifacts').resolve()):
            parser.error('Audit output must stay in local-artifacts')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(d, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf-8')
        print(json.dumps(d['summary'] if args.sources else {'written': str(target)}, ensure_ascii=False))
    else:
        print(json.dumps(d, ensure_ascii=False, indent=2) if args.json or args.sources else markdown(d))
