"""Four original reusable facility types. No historical placement is asserted.

Only the explicitly selected internal load configuration consumes this bundle.
"""
import json
from pathlib import Path
import struct
import sys
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from build_historical_landmarks_r41 import Parts, beam, arch, material, render_reference


def shed(name, far):
    p = Parts(name)
    p.box((0, 0, 4.5), (52, 18, 9), 'brick')
    p.gable(54, 20, 9, 13, 'slate')
    p.box((0, -11, .75), (54, 5, 1.5), 'stone')
    p.box((0, -11, 7), (54, 5, .35), 'slate')
    for x in (-21, -7, 7, 21):
        p.box((x, -9.1, 3.4), (6, .3, 5.2), 'wood')
        beam(p, (x, -13, 1.5), (x, -13, 6.8), .18, 'iron', 4)
        if not far:
            beam(p, (x-2.8, -9.3, 1), (x+2.8, -9.3, 5.8), .12, 'trim', 4)
    if not far:
        for x in range(-24, 25, 4):
            p.box((x, 9.1, 5.5), (2.2, .2, 2.5), 'glass')
        for x in (-16, 0, 16):
            p.box((x, 0, 13.4), (2.5, 2.5, .9), 'iron')
    return p


def workshop(name, far):
    p = Parts(name)
    p.box((0, 0, 5), (42, 26, 10), 'redbrick')
    p.gable(44, 28, 10, 15, 'slate')
    for x in (-11, 11):
        p.box((x, -13.1, 4), (8, .3, 8), 'opening')
        arch(p, x, -13.3, 8, 6, 2.3, .4, .6, 'trim', 5 if far else 12)
    p.box((0, 0, 15.4), (25, 4, 1.8), 'iron')
    if not far:
        for x in range(-18, 19, 6):
            p.box((x, 13.1, 5), (3, .2, 5.0), 'glass')
            p.box((x, 0, 16.5), (1.3, 1.3, 1.1), 'iron')
        for x in (-20, 20):
            p.box((x, 10, 9), (2, 2, 18), 'redbrick')
            p.box((x, 10, 18.3), (2.5, 2.5, .6), 'trim')
    return p


def granary(name, far):
    p = Parts(name)
    p.box((0, 0, 1), (34, 17, 2), 'stone')
    p.box((0, 0, 6), (34, 17, 10), 'wood')
    p.gable(36, 19, 11, 17, 'tile')
    for x in (-12, 0, 12):
        p.box((x, -8.6, 7), (3.4, .25, 4.5), 'opening')
        if not far:
            beam(p, (x-1.6, -8.9, 5), (x+1.6, -8.9, 9), .1, 'trim', 4)
    if not far:
        for x in range(-16, 17, 4):
            beam(p, (x, -8.7, 1), (x, -8.7, 10.5), .14, 'trim', 4)
        for i in range(10):
            p.box((-17-i*.32, -2, (10-i)*.55), (1, 2.8, .45), 'wood')
        p.box((0, 0, 17.2), (4, 4, 1.2), 'wood')
        p.gable(4.5, 4.5, 17.8, 19, 'tile')
    return p


def derrick(name, far):
    p = Parts(name)
    p.box((0, 0, .5), (9, 9, 1), 'stone')
    for y in (-2.8, 2.8):
        beam(p, (-3, y, .8), (0, 0, 17), .32, 'wood')
        beam(p, (3, y, .8), (0, 0, 17), .32, 'wood')
    beam(p, (0, 0, 14), (10, 0, 12), .28, 'wood')
    beam(p, (0, 0, 17), (10, 0, 12), .07, 'iron', 4)
    beam(p, (10, 0, 12), (10, 0, 3), .06, 'iron', 4)
    p.box((10, 0, 2), (2.8, 2.8, 2), 'limestone')
    p.box((0, 1.8, 2), (3, 2.5, 2), 'wood')
    if not far:
        beam(p, (-1.6, 1.8, 2.7), (1.6, 1.8, 2.7), .75, 'iron', 10)
        for z in (4, 8, 12):
            beam(p, (-2.5+z*.12, -2.4+z*.10, z), (2.5-z*.12, -2.4+z*.10, z), .15, 'wood', 4)
    return p


def editable_derrick_parts(mat):
    """Source-only rigid parts with useful pivots; the exported static bake stays one Mesh.

    No rig or animation is asserted. A later hoist can bind these parts without
    separating triangles out of the static runtime mesh.
    """
    collection = bpy.data.collections.new('SOURCE_ONLY_DerrickAssembly')
    bpy.context.scene.collection.children.link(collection)
    fixed = Parts('Derrick_FixedFrame')
    fixed.box((0, 0, .5), (9, 9, 1), 'stone')
    for y in (-2.8, 2.8):
        for x in (-3, 3):
            beam(fixed, (x, y, .8), (0, 0, 17), .32, 'wood')
    boom = Parts('Derrick_Boom_PivotAtMast')
    beam(boom, (0, 0, 0), (10, 0, -2), .28, 'wood')
    rope = Parts('Derrick_HoistCable_PivotAtTip')
    beam(rope, (0, 0, 0), (0, 0, -9), .06, 'iron', 4)
    load = Parts('Derrick_StoneLoad')
    load.box((0, 0, 0), (2.8, 2.8, 2), 'limestone')
    drum = Parts('Derrick_WinchDrum_AxleX')
    beam(drum, (-1.6, 0, 0), (1.6, 0, 0), .75, 'iron', 10)
    for part, pivot in [(fixed,(0,0,0)),(boom,(0,0,14)),(rope,(10,0,12)),
                        (load,(10,0,2)),(drum,(0,1.8,2.7))]:
        obj = part.make(mat)
        obj.location = pivot
        for owner in list(obj.users_collection): owner.objects.unlink(obj)
        collection.objects.link(obj)
    collection.hide_render = True
    collection.hide_viewport = True


def main():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.preferences.filepaths.save_version = 0
    mat = material()
    objects = []
    for name, build in [('rail_goods_shed', shed), ('engine_workshop', workshop),
                        ('farm_granary', granary), ('quarry_derrick', derrick)]:
        for far in (False, True):
            obj = build(name+('_far' if far else '_near'), far).make(mat)
            objects.append(obj)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    out = ROOT/'assets/landmarks/internal_preview_r41/shared_facilities.glb'
    bpy.ops.export_scene.gltf(filepath=str(out), export_format='GLB', use_selection=True,
        export_yup=True, export_texcoords=False, export_animations=False, export_cameras=False,
        export_lights=False, export_extras=False, export_use_gltfpack=False)
    editable_derrick_parts(mat) # Not part of the export selection or runtime load.
    source = ROOT/'tools/map/model_sources/r41/shared_facilities.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(source))
    raw = out.read_bytes()
    gltf = json.loads(raw[20:20+struct.unpack_from('<I', raw, 12)[0]])
    info = {'bytes': len(raw), 'materials': len(gltf.get('materials', [])), 'meshes': []}
    for m in gltf['meshes']:
        info['meshes'].append({'name': m['name'], 'surfaces': len(m['primitives']),
            'triangles': sum(gltf['accessors'][p['indices']]['count']//3 for p in m['primitives'])})
    (source.parent/'shared_facilities_counts.json').write_text(json.dumps(info, indent=2)+'\n', encoding='utf8')
    print('R41_FACILITIES '+json.dumps(info), flush=True)


if __name__=='__main__':
    main()
