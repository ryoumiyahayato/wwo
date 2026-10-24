"""Blender adaptation of eight explicitly selected R15 files. No source overwrite."""
import json
import math
from pathlib import Path
import struct
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from build_historical_landmarks_r41 import render_reference

OUT = ROOT/'assets/landmarks/internal_preview_r41'
SOURCE = ROOT/'tools/map/model_sources/r41/cloud_adaptations'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    SOURCE.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    catalog = {x['number']: x for x in json.loads((ROOT/'docs/map/drive_landmark_catalog_r15.json').read_text(encoding='utf8'))['entries']}
    counts = []
    for spec in json.loads((ROOT/'tools/map/r41_landmark_expansion.json').read_text(encoding='utf8')):
        if not spec.get('admitted', True): continue
        entry = catalog[spec['number']]
        original = ROOT/'local-artifacts/r41_extension/originals'/entry['file_name']
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.ops.import_scene.gltf(filepath=str(original))
        near = next(o for o in bpy.context.scene.objects if o.type=='MESH')
        # Keep reviewed monument materials only, not the generator's backdrop.
        mesh = near.data
        retained = [p for p in mesh.polygons if p.material_index in spec['keep']]
        used_vertices = sorted({i for p in retained for i in p.vertices})
        remap = {old: new for new, old in enumerate(used_vertices)}
        vertices = [mesh.vertices[i].co.copy() for i in used_vertices]
        replacement = bpy.data.meshes.new('Reviewed monument')
        replacement.from_pydata(vertices, [], [tuple(remap[i] for i in p.vertices) for p in retained])
        for m in mesh.materials:
            replacement.materials.append(m)
        for dest, source in zip(replacement.polygons, retained):
            dest.material_index = source.material_index
        near.data = replacement
        used = set(i for p in replacement.polygons for i in p.vertices)
        lo = Vector(tuple(min(replacement.vertices[i].co[a] for i in used) for a in range(3)))
        hi = Vector(tuple(max(replacement.vertices[i].co[a] for i in used) for a in range(3)))
        # Imported glTF is Blender Z-up. Uniform height conversion preserves the
        # original schematic proportions; it does not claim measured footprints.
        scale = spec['height']/(hi.z-lo.z)
        origin = Vector(((lo.x+hi.x)/2, (lo.y+hi.y)/2, lo.z))
        for v in replacement.vertices:
            v.co = (v.co-origin)*scale
        near.name = 'Near'
        near.data.name = spec['key']+'_Near'
        # Drop unused material slots; no media or external dependencies are added.
        bpy.context.view_layer.objects.active = near
        bpy.ops.object.material_slot_remove_unused()
        near.select_set(True)
        far = near.copy()
        far.data = near.data.copy()
        far.name = 'Far'
        far.data.name = spec['key']+'_Far'
        bpy.context.scene.collection.objects.link(far)
        bpy.context.view_layer.objects.active = far
        modifier = far.modifiers.new('Far silhouette', 'DECIMATE')
        modifier.ratio = .55
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        bpy.ops.object.select_all(action='DESELECT')
        near.select_set(True)
        far.select_set(True)
        path = OUT/(spec['key']+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
            export_yup=True, export_animations=False, export_cameras=False, export_lights=False,
            export_extras=False, export_use_gltfpack=False)
        far.hide_render = True
        far.hide_set(True)
        if '--render' in sys.argv:
            # Workbench material colours, as these originals have no vertex colours.
            render_reference('cloud_'+spec['key'], near)
        bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(spec['key']+'.blend')))
        raw = path.read_bytes()
        gltf = json.loads(raw[20:20+struct.unpack_from('<I', raw, 12)[0]])
        dimensions = (hi-lo)*scale
        info = {'key': spec['key'], 'drive_id': entry['file_id'], 'original_file': entry['file_name'],
                'original_bytes': original.stat().st_size, 'adapted_bytes': len(raw),
                'original_triangles': entry['structure']['triangles'],
                'original_vertices': entry['structure']['primitive_vertices_sum'],
                'original_materials': entry['structure']['materials'],
                'kept_source_materials': spec['keep'], 'materials': len(gltf.get('materials', [])),
                'textures': len(gltf.get('textures', [])),
                'footprint_m': [dimensions.x, dimensions.y], 'height_m': dimensions.z,
                'uniform_scale': scale, 'meshes': []}
        for m in gltf['meshes']:
            info['meshes'].append({'name': m['name'], 'surfaces': len(m['primitives']),
                'vertices': sum(gltf['accessors'][p['attributes']['POSITION']]['count'] for p in m['primitives']),
                'triangles': sum(gltf['accessors'][p['indices']]['count']//3 for p in m['primitives'])})
        counts.append(info)
    (SOURCE/'model_counts.json').write_text(json.dumps(counts, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
    print('R41_ADAPTED '+json.dumps(counts), flush=True)


if __name__=='__main__':
    main()
