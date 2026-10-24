"""Original historical reference models. Run with Blender --background --python.

Sources, limits and placement live in assets/landmarks/R41_SOURCE_AND_USAGE.md.
Metres, Blender Z up; bridge long axis X. No downloaded geometry or textures.
Two explicit meshes per model, one shared vertex-colour material per GLB.
"""
import json
import math
from pathlib import Path
import struct
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from build_settlement_modules import Parts, PALETTE

SOURCE = ROOT / 'tools/map/model_sources/r41'
OUT = ROOT / 'assets/landmarks'
PALETTE.update({
    'limestone': (0.69, 0.65, 0.55, 1), 'granite': (0.49, 0.51, 0.48, 1),
    'iron': (0.16, 0.27, 0.24, 1), 'glass': (0.27, 0.38, 0.39, 1),
    'gilt': (0.62, 0.50, 0.26, 1), 'redbrick': (0.47, 0.29, 0.22, 1),
    'paving': (0.36, 0.36, 0.33, 1),
})


def beam(p, a, b, radius, color, sides=6):
    a, b = Vector(a), Vector(b)
    direction = (b-a).normalized()
    u = direction.cross(Vector((0, 0, 1)))
    if u.length < .01:
        u = direction.cross(Vector((0, 1, 0)))
    u.normalize()
    v = direction.cross(u)
    vs = [tuple(point + radius*(u*math.cos(i*math.tau/sides) +
                                v*math.sin(i*math.tau/sides)))
          for point in (a, b) for i in range(sides)]
    fs = [tuple(reversed(range(sides))), tuple(range(sides, sides*2))]
    fs += [(i, (i+1) % sides, (i+1) % sides+sides, i+sides)
           for i in range(sides)]
    p.add(vs, fs, color)


def arch(p, cx, y, span, spring, rise, thickness, depth, color, steps):
    """Open segmental arch vault / iron rib, with radial thickness."""
    # Elliptical reference profile. It is not a claim of surveyed voussoirs.
    inner = [(cx-span/2*math.cos(i*math.pi/steps),
              spring+rise*math.sin(i*math.pi/steps)) for i in range(steps+1)]
    outer = [(cx-(span/2+thickness)*math.cos(i*math.pi/steps),
              spring+(rise+thickness)*math.sin(i*math.pi/steps)) for i in range(steps+1)]
    for i in range(steps):
        vs = [(x, yy, z) for yy in (y-depth/2, y+depth/2)
              for x, z in (inner[i], inner[i+1], outer[i+1], outer[i])]
        p.add(vs, [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1),
                   (3, 2, 6, 7), (0, 3, 7, 4), (1, 5, 6, 2)], color)


def arch_spandrel(p, cx, y, span, spring, rise, top, depth, color, steps):
    for i in range(steps):
        a, b = i*math.pi/steps, (i+1)*math.pi/steps
        x0, x1 = cx-span/2*math.cos(a), cx-span/2*math.cos(b)
        z0, z1 = spring+rise*math.sin(a), spring+rise*math.sin(b)
        vs = [(x0, yy, z0) for yy in (y-depth/2, y+depth/2)]
        vs += [(x1, yy, z1) for yy in (y-depth/2, y+depth/2)]
        vs += [(x1, yy, top) for yy in (y-depth/2, y+depth/2)]
        vs += [(x0, yy, top) for yy in (y-depth/2, y+depth/2)]
        p.add(vs, [(0, 2, 4, 6), (7, 5, 3, 1), (0, 1, 3, 2),
                   (6, 4, 5, 7), (0, 6, 7, 1), (2, 3, 5, 4)], color)


def pier(p, x, width, depth, height, color, pointed=True):
    p.box((x, 0, height/2), (width, depth, height), color)
    p.box((x, 0, height-.4), (width+.5, depth+.5, .8), 'trim')
    if pointed:
        for side in (-1, 1):
            y = side*depth/2
            vs = [(x-width/2, y, 0), (x+width/2, y, 0),
                  (x, y+side*2, 0), (x-width/2, y, height-.8),
                  (x+width/2, y, height-.8), (x, y+side*2, height-2)]
            p.add(vs, [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3),
                       (1, 2, 5, 4), (2, 0, 3, 5)], color)


def equestrian(p, x, y, facing):
    # Four small silhouettes on documented 1853 plinths, not replicas of sculptures.
    p.box((x, y, 13.0), (2.4, 2.5, 2.0), 'limestone')
    beam(p, (x, y-.8, 15.0), (x, y+.8, 15.1), .6, 'limestone')
    for dx in (-.35, .35):
        for dy in (-.65, .65):
            beam(p, (x+dx, y+dy, 15), (x+dx, y+dy, 14), .13, 'limestone', 4)
    beam(p, (x, y+.7*facing, 15.1), (x, y+1.1*facing, 16), .28, 'limestone')
    beam(p, (x, y, 15.3), (x, y, 16.5), .30, 'limestone')
    p.box((x, y, 16.8), (.52, .52, .55), 'limestone')


def iena(far=False):
    p = Parts('Far' if far else 'Near')
    length, width, deck = 155.0, 14.0, 12.0
    for i in range(5):
        cx = (i-2)*30.0
        arch(p, cx, 0, 28, 2.0, 7.1, .85, width, 'limestone', 8 if far else 22)
        for y in (-width/2+.25, width/2-.25):
            arch_spandrel(p, cx, y, 28, 2, 8.0, deck-.5, .5,
                          'stone', 8 if far else 22)
        if not far:
            # Alternating face blocks emphasize the vault, without stone nodes.
            for j in range(13):
                t = (j+.5)*math.pi/13
                x, z = cx-14.4*math.cos(t), 2+7.55*math.sin(t)
                p.box((x, -7.04, z), (.28, .12, .45), 'trim')
                p.box((x, 7.04, z), (.28, .12, .45), 'trim')
    for x in (-45, -15, 15, 45):
        pier(p, x, 2.2, width, 4.0, 'stone')
    for x in (-75, 75):
        pier(p, x, 5, width+2, deck, 'stone', False)
    p.box((0, 0, deck-.35), (length, width, .7), 'paving')
    for side in (-1, 1):
        p.box((0, side*6.6, deck+.25), (length, .9, .5), 'limestone')
        p.box((0, side*6.6, deck+1.2), (length, .85, .26), 'trim')
        for x in range(-75, 76, 10 if far else 3):
            p.box((x, side*6.6, deck+.8), (.55, .65, 1), 'stone')
    if not far:
        for x in (-73, 73):
            for side in (-1, 1):
                equestrian(p, x, side*8.2, -1 if x>0 else 1)
    return p


def westminster(far=False):
    p = Parts('Far' if far else 'Near')
    length, width, deck = 250.0, 26.0, 12.0
    spans = [29, 32, 34, 36, 34, 32, 29]
    cursor = -length/2+3
    for i, span in enumerate(spans):
        cx = cursor+span/2
        rise = 5.5+(.5 if i in (2, 3, 4) else 0)
        for y in (-width/2+.6, width/2-.6) if far else (-12.4, -6, 0, 6, 12.4):
            arch(p, cx, y, span, 2, rise, .5, .6, 'iron', 8 if far else 20)
            if not far:
                for j in range(1, 12):
                    t = j*math.pi/12
                    x, z = cx-span/2*math.cos(t), 2+(rise+.5)*math.sin(t)
                    beam(p, (x, y, z), (x, y, deck-.5), .13, 'iron', 4)
                for dx in (-span*.32, span*.32):
                    p.box((cx+dx, y, 10.1), (1.2, .7, 1.5), 'gilt')
        cursor += span+3
        if i<6:
            pier(p, cursor-1.5, 3, width, 5.2, 'granite')
    p.box((0, 0, deck-.4), (length, width, .8), 'paving')
    for x in (-124, 124):
        pier(p, x, 4, width, 11.5, 'granite', False)
    for side in (-1, 1):
        y = side*12.6
        for z in (deck+.15, deck+1.5):
            p.box((0, y, z), (length, .23, .22), 'iron')
        for x in range(-123, 124, 6 if far else 2):
            p.box((x, y, deck+.85), (.17, .22, 1.25), 'iron')
            if not far:
                beam(p, (x-.85, y, deck+.25), (x, y, deck+1.25), .065, 'iron', 4)
                beam(p, (x, y, deck+1.25), (x+.85, y, deck+.25), .065, 'iron', 4)
        if not far:
            for x in (-121, -86, -51, -16, 19, 54, 89, 121):
                p.box((x, y, deck+.9), (.65, .65, 1.8), 'iron')
                beam(p, (x, y, deck+1.8), (x, y, deck+4.0), .13, 'iron')
                for dx, h in ((-.65, 3.6), (0, 4.4), (.65, 3.6)):
                    beam(p, (x, y, deck+3), (x+dx, y, deck+h), .09, 'iron', 4)
                    beam(p, (x+dx, y, deck+h), (x+dx, y, deck+h+.65), .26, 'trim', 8)
                    p.box((x+dx, y, deck+h+.8), (.18, .18, .3), 'gilt')
    return p


def pediment(p, x, y, width, base, rise, depth, color):
    vs = [(x+dx, yy, z) for yy in (y-depth/2, y+depth/2)
          for dx, z in ((-width/2, base), (width/2, base), (0, base+rise))]
    p.add(vs, [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1),
               (1, 4, 5, 2), (2, 5, 3, 0)], color)


def arched_window(p, x, y, width, bottom, spring, top, far):
    p.box((x, y, (bottom+spring)/2), (width, .18, spring-bottom), 'glass')
    steps = 5 if far else 12
    vs = [(x, y, spring)]
    vs += [(x-width/2*math.cos(i*math.pi/steps), y,
            spring+(top-spring)*math.sin(i*math.pi/steps)) for i in range(steps+1)]
    p.add(vs, [(0, i+1, i+2) for i in range(steps)], 'glass')
    if not far:
        arch(p, x, y-.12, width, spring, top-spring, .22, .25, 'trim', 12)
        for dx in (-width*.25, 0, width*.25):
            p.box((x+dx, y-.2, (bottom+spring)/2), (.14, .18, spring-bottom), 'iron')
        p.box((x, y-.2, spring), (width, .18, .18), 'iron')


def hall_roof(p, cx, length, width, eaves, rise, far, color='slate'):
    # Barrel hall along Y, iron ribs / glass strips; opaque to avoid sorting costs.
    steps = 8 if far else 18
    for j in range(steps):
        a, b = j*math.pi/steps, (j+1)*math.pi/steps
        vs = [(cx-width/2*math.cos(t), y, eaves+rise*math.sin(t))
              for y in (-length/2, length/2) for t in (a, b)]
        p.add(vs, [(0, 1, 3, 2)], color if j % 3 else 'glass')
    if not far:
        for y in (-length/2, -length*.3, -length*.1, length*.1, length*.3, length/2):
            arch(p, cx, y, width, eaves, rise, .15, .25, 'iron', steps)


def gare_nord(far=False):
    p = Parts('Far' if far else 'Near')
    # Approximate reference envelope, not a surveyed 1900 building footprint.
    p.box((0, -38, 9), (150, 24, 18), 'limestone')
    for x, w, h in ((-60, 27, 21), (0, 64, 25), (60, 27, 21)):
        p.box((x, -39, h/2), (w, 26, h), 'limestone')
        p.box((x, -39, h+.3), (w+1, 27, .6), 'trim')
        pediment(p, x, -52.3, w, h+.6, 5 if x==0 else 3, 1.4, 'limestone')
    for x in (-23, -11.5, 0, 11.5, 23):
        arched_window(p, x, -52.8, 7, 4, 15.5, 20.5, far)
    for x in (-66, -56, -44, 44, 56, 66):
        arched_window(p, x, -52.6, 4.8, 3, 11, 14.5, far)
    for x in (-37, 37):
        arched_window(p, x, -50.2, 5, 3, 10.5, 13.0, far)
    for x in (-73, -48, -32, -17.3, -5.75, 5.75, 17.3, 32, 48, 73):
        p.box((x, -53, 12), (1.6, 1.4, 22), 'trim')
        if not far:
            p.box((x, -53.2, 2), (2, 1.6, 1), 'stone')
            p.box((x, -53.2, 22), (2.2, 1.6, .9), 'trim')
    for z in (2.5, 16.5, 23.5):
        p.box((0, -53.1, z), (150, .75, .6), 'trim')
    p.box((0, -54.3, .4), (154, 4, .8), 'stone')
    if not far:
        # Abstract city allegory silhouettes. No claim of exact sculpture copies.
        for i in range(23):
            x = (i-11)*6.4
            z = 26 if abs(x)<32 else 22
            p.box((x, -51, z), (1.3, 1.4, 1.4), 'stone')
            beam(p, (x, -51, z+.6), (x, -51, z+2.0), .38, 'limestone')
            p.box((x, -51, z+2.4), (.7, .7, .8), 'limestone')
    # A bounded iron/glass hall behind the facade, without invented rails/platforms.
    p.box((0, 8, 7), (120, 82, 14), 'limestone')
    for x in (-30, 30):
        hall_roof(p, x, 82, 58, 14, 10, far)
    return p


def friedrich(far=False):
    p = Parts('Far' if far else 'Near')
    # 1882 single-hall reference, not Brodfuehrer's later twin Tudor-arch hall.
    for x in (-44, -22, 0, 22, 44):
        arch(p, x, 0, 18, 1.5, 5.3, .8, 30, 'redbrick', 6 if far else 14)
        for y in (-14.8, 14.8):
            arch_spandrel(p, x, y, 18, 1.5, 6.2, 10.2, .6,
                          'redbrick', 6 if far else 14)
    for x in (-55, -33, -11, 11, 33, 55):
        pier(p, x, 4, 30, 9.8, 'redbrick', False)
    p.box((0, 0, 10.3), (114, 32, .6), 'granite')
    # hall_roof is long along Y; rotate its parts into the east/west railway axis.
    roof = Parts('roof')
    hall_roof(roof, 0, 110, 28, 15, 8.5, far, 'glass')
    roof.vertices = [(y, -x, z) for x, y, z in roof.vertices]
    p.add(roof.vertices, roof.faces, 'glass')
    # Reapply per-face colors after accumulator insertion.
    p.colors[-len(roof.faces):] = roof.colors
    for side in (-1, 1):
        y = side*14
        p.box((0, y, 12.7), (110, .8, 4.8), 'redbrick')
        for x in range(-50, 51, 10 if far else 5):
            p.box((x, y, 14), (.35, .6, 7), 'iron')
            if not far:
                p.box((x+1.8, y+side*.5, 12.7), (2.7, .15, 2.5), 'glass')
    for x in (-56, 56):
        p.box((x, 0, 12.2), (1.2, 30, 3.2), 'redbrick')
        # Gable end glazed opening, no modern station name or later hall outline.
        window = Parts('window')
        arched_window(window, 0, 0, 25, 12, 15, 23, far)
        window.vertices = [(x+vy, -vx, vz) for vx, vy, vz in window.vertices]
        p.add(window.vertices, window.faces, 'glass')
        p.colors[-len(window.faces):] = window.colors
    p.box((0, -22, 4.5), (24, 14, 9), 'redbrick')
    pediment(p, 0, -29.2, 25, 9, 3, .8, 'trim')
    for x in (-7, 0, 7):
        arched_window(p, x, -29.6, 3.5, .5, 5.5, 7.8, far)
    return p


def material():
    mat = bpy.data.materials.new('R41 opaque vertex masonry metal glass')
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    shader = mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    color = mat.node_tree.nodes.new('ShaderNodeVertexColor')
    color.layer_name = 'Col'
    output = mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
    mat.node_tree.links.new(color.outputs['Color'], shader.inputs['Base Color'])
    mat.node_tree.links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    shader.inputs['Roughness'].default_value = .82
    shader.inputs['Specular IOR Level'].default_value = .23
    mat.use_backface_culling = False
    return mat


def render_reference(name, near):
    """Optional modelling view; never starts the Godot game."""
    scene = bpy.context.scene
    bounds = [Vector(v) for v in near.bound_box]
    span = max(max(v[i] for v in bounds)-min(v[i] for v in bounds) for i in range(3))
    target = sum(bounds, Vector())/len(bounds)
    data = bpy.data.cameras.new('Modelling view')
    camera = bpy.data.objects.new('Modelling view', data)
    scene.collection.objects.link(camera)
    camera.location = target+Vector((.85, -1.3, .7))*span
    camera.rotation_euler = (target-camera.location).to_track_quat('-Z', 'Y').to_euler()
    data.type = 'ORTHO'
    bpy.context.view_layer.update()
    projected = [camera.matrix_world.inverted() @ v for v in bounds]
    px = max(v.x for v in projected)-min(v.x for v in projected)
    py = max(v.y for v in projected)-min(v.y for v in projected)
    data.ortho_scale = max(px, py*1000/600)*1.15
    scene.camera = camera
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.color_type = 'VERTEX'
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 600
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(ROOT/'local-artifacts'/('r41_'+name+'.png'))
    bpy.ops.render.render(write_still=True)


def main():
    SOURCE.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    stats = []
    for name, build in [('pont_iena_r41', iena), ('westminster_bridge_r41', westminster),
                        ('gare_du_nord_r41', gare_nord), ('friedrichstrasse_1882_r41', friedrich)]:
        # Hidden far-LOD objects are not selected by select_all. Remove every
        # old object so later exports retain the exact Near/Far node names.
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.context.scene.unit_settings.system = 'METRIC'
        bpy.context.scene.unit_settings.scale_length = 1
        mat = material()
        near, far = build(False).make(mat), build(True).make(mat)
        for obj, lod in ((near, 'Near'), (far, 'Far')):
            obj.name = lod
            obj.data.name = name+'_'+lod
            obj['role'] = 'Original historical reference; not surveyed reconstruction'
        bpy.ops.object.select_all(action='DESELECT')
        for obj in (near, far):
            obj.select_set(True)
        bpy.context.view_layer.objects.active = near
        path = OUT/(name+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
            export_yup=True, export_texcoords=False, export_normals=True,
            export_tangents=False, export_animations=False, export_cameras=False,
            export_lights=False, export_extras=False, export_use_gltfpack=False)
        far.hide_set(True)
        far.hide_render = True
        if '--render' in sys.argv:
            render_reference(name, near)
        bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
        raw = path.read_bytes()
        size = struct.unpack_from('<I', raw, 12)[0]
        gltf = json.loads(raw[20:20+size])
        info = {'file': str(path.relative_to(ROOT)), 'bytes': len(raw),
                'materials': len(gltf.get('materials', [])), 'meshes': []}
        for mesh in gltf['meshes']:
            info['meshes'].append({'name': mesh['name'], 'triangles': sum(
                gltf['accessors'][prim['indices']]['count']//3 for prim in mesh['primitives'])})
        stats.append(info)
    (SOURCE/'model_counts.json').write_text(json.dumps(stats, indent=2)+'\n', encoding='utf8')
    print('R41_MODELS '+json.dumps(stats), flush=True)


if __name__ == '__main__':
    main()
