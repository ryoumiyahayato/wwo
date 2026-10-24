"""Configure R57 inputs only; export via tools/build_preview.ps1 build --version R57.

The unified entry registers the candidate and automatically retires obsolete
owned outputs. This script neither exports nor authorizes resource deletion.
"""
import json,re
from pathlib import Path
import build_surface_r57 as b

ROOT=b.ROOT
doc=b.read(ROOT/'data/presentation/sampling_surface_r57.json');aa=b.prev.assets(doc)
active={a['path'] for a in aa if a['surface_role'] in ['base','detail']}
outside=set()
for name in ['northern_surface_r52.json','asian_surface_r51.json']:
    for a in b.prev.assets(b.read(ROOT/'data/presentation'/name)):
        if a['surface_role'] not in ['base','detail']:continue
        w,s,e,n=a.get('core_bounds_lon_lat',a['bounds_lon_lat'])
        # All images whose entire core lies outside the shared admission domain
        # remain legal consumers of their original catalogue. Be conservative.
        if not (-28<=w<e<=76 and 10<=s<n<=86):outside.add(a['path'])
excluded=sorted({a['path'].removeprefix('res://') for a in aa if str(a['surface_role']).startswith('source_') and a['path'] not in active|outside and a['path'].startswith('res://assets/maps/relief/') and (ROOT/a['path'].removeprefix('res://')).exists()})
# MapRelief admits the northern/asian catalogues outside the shared domain;
# it no longer requests siberian_catalog. Preserve every actual successor
# consumer, including assets that the later catalogues reuse by path.
retired=b.prev.assets(b.read(ROOT/'data/presentation/siberian_surface_r50.json'))
excluded=sorted(set(excluded)|{a['path'].removeprefix('res://') for a in retired if a['path'] not in active|outside and a['path'].startswith('res://assets/maps/relief/') and (ROOT/a['path'].removeprefix('res://')).exists()})
excluded.append('data/presentation/sampling_surface_r56.json')
p=ROOT/'export_presets.cfg';text=p.read_text(encoding='utf8');start=text.index('[preset.3]');end=text.index('[preset.3.options]',start);section=text[start:end]
match=re.search(r'exclude_filter="([^"]*)"',section);filters=[s for s in match.group(1).split(',') if s not in excluded and not s.startswith('assets/maps/relief/') and s!='data/presentation/sampling_surface_r56.json']
section=section[:match.start()]+f'exclude_filter="{",".join(filters+excluded)}"'+section[match.end():]
section=re.sub(r'export_path="[^"]*"','export_path="builds/preview_2026-10-19_raster_r57/WWO_1900_Terrain_Raster_LOD_Integrity_R57_Preview.exe"',section)
p.write_text(text[:start]+section+text[end:],encoding='utf8')
p=ROOT/'project.godot';text=p.read_text(encoding='utf8');text=re.sub(r'config/build_label="[^"]*"','config/build_label="WWO R57 — Terrain Raster Artifacts and LOD Integrity Recovery"',text);text=re.sub(r'config/build_id="[^"]*"','config/build_id="wwo-r57-internal-raster-lod-integrity"',text);text=re.sub(r'config/build_sequence=\d+','config/build_sequence=57',text);p.write_text(text,encoding='utf8')
b.save(b.WORK/'export_scope.json',dict(excluded=excluded,excluded_file_bytes=sum((ROOT/v).stat().st_size for v in excluded),reason='Source-only predecessors not selected after shared admission. Other domains retain any active original consumers. Files kept on disk, prior EXEs untouched.',active_surface_paths=sorted(active),preserved_outside_paths=sorted(outside)))
print('R57 exact export exclusions',len(excluded),'bytes',sum((ROOT/v).stat().st_size for v in excluded))
