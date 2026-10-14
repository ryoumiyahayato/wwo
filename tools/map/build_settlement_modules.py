"""Blender background generation of six shared R12 miniature modules.

Original generic silhouettes, not measured replicas or historical buildings.
One GLB carries six independent named meshes and one vertex-colour material.
"""
from pathlib import Path
import json
import math
import struct
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ASSET = ROOT / 'assets/settlements/cabinet_building_modules.glb'
WORK = ROOT / 'local-artifacts/settlement-miniatures-r12'
PALETTE = {
    'stone': (0.57, 0.52, 0.43, 1), 'brick': (0.41, 0.27, 0.22, 1),
    'slate': (0.21, 0.25, 0.27, 1), 'tile': (0.39, 0.26, 0.20, 1),
    'trim': (0.70, 0.64, 0.52, 1), 'wood': (0.32, 0.27, 0.20, 1),
    'opening': (0.16, 0.19, 0.20, 1),
}


class Parts:
    def __init__(self, name):
        self.name, self.vertices, self.faces, self.colors = name, [], [], []

    def add(self, vertices, faces, color):
        start = len(self.vertices)
        self.vertices.extend(vertices)
        self.faces.extend(tuple(start+i for i in face) for face in faces)
        self.colors.extend([PALETTE[color]] * len(faces))

    def loft(self, levels, color):
        rings = [[(-w/2, -d/2, z), (w/2, -d/2, z),
                  (w/2, d/2, z), (-w/2, d/2, z)] for z, w, d in levels]
        faces = [(3, 2, 1, 0)]
        for n in range(len(rings)-1):
            for i in range(4):
                j = (i+1) % 4
                faces.append((n*4+i, n*4+j, (n+1)*4+j, (n+1)*4+i))
        faces.append(tuple((len(rings)-1)*4+i for i in range(4)))
        self.add([v for ring in rings for v in ring], faces, color)

    def box(self, center, size, color):
        x, y, z = center
        w, d, h = size
        vertices = [(x+sx*w/2, y+sy*d/2, z+sz*h/2)
                    for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
        self.add(vertices, [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
                            (1, 3, 7, 5), (3, 2, 6, 7), (2, 0, 4, 6)], color)

    def gable(self, width, depth, eaves, ridge, color):
        w, d = width/2, depth/2
        vertices = [(-w, -d, eaves), (w, -d, eaves), (w, d, eaves),
                    (-w, d, eaves), (-w, 0, ridge), (w, 0, ridge)]
        self.add(vertices, [(0, 1, 5, 4), (4, 5, 2, 3),
                            (0, 4, 3), (1, 2, 5), (3, 2, 1, 0)], color)

    def make(self, material):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.materials.append(material)
        mesh.update()
        colour = mesh.color_attributes.new(name='Col', type='BYTE_COLOR', domain='CORNER')
        for face, rgba in zip(mesh.polygons, self.colors):
            face.use_smooth = False
            for loop in face.loop_indices:
                colour.data[loop].color = rgba
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def modules(material):
    objects = []
    # Modest French urban massing; no replica facade or invented named building.
    p = Parts('paris_mansard')
    p.box((0, 0, 7), (22, 12, 14), 'stone')
    p.box((0, 0, 13.9), (23, 13, 0.45), 'trim')
    p.loft([(14.1, 23, 13), (17.2, 18.5, 8.5), (18.1, 16, 6)], 'slate')
    for x in (-6, 6):
        p.box((x, -4.5, 16), (1.8, 1.2, 1.5), 'trim')
        p.box((x, -5.13, 16), (0.8, 0.05, 0.8), 'opening')
    p.box((6, 2, 18.7), (1.2, 1.2, 2.0), 'stone')
    objects.append(p.make(material))
    # British row-house massing, shallow roof and connected chimney rhythm.
    p = Parts('london_terrace')
    p.box((0, 0, 4.5), (24, 9, 9), 'brick')
    p.gable(24.5, 9.5, 9, 11.2, 'slate')
    p.box((0, -4.55, 3.5), (24, 0.3, 0.25), 'trim')
    for x in (-9, -3, 3, 9):
        p.box((x, 0, 11.3), (1.4, 1.1, 2), 'brick')
        p.box((x, -4.56, 1.4), (1.0, 0.1, 2.8), 'opening')
    objects.append(p.make(material))
    p = Parts('rural_house')
    p.box((0, 0, 2), (10, 8, 4), 'stone')
    p.gable(11, 9, 4, 6, 'tile')
    p.box((2.8, 1, 6), (1, 1, 1.8), 'stone')
    objects.append(p.make(material))
    p = Parts('civic_hall')
    p.box((0, 0, 5), (24, 15, 10), 'stone')
    p.loft([(10, 25, 16), (13, 19, 10)], 'slate')
    p.box((0, -8.0, 1.0), (8, 3, 2), 'trim')
    for x in (-3, 3):
        p.box((x, -8.6, 4.5), (0.8, 0.8, 7), 'trim')
    p.gable(9, 3, 8, 10, 'stone')
    objects.append(p.make(material))
    p = Parts('warehouse')
    p.box((0, 0, 3.5), (28, 15, 7), 'brick')
    p.gable(29, 16, 7, 10, 'slate')
    for x in (-8, 8):
        p.box((x, -7.52, 2), (4, 0.06, 4), 'opening')
    objects.append(p.make(material))
    # Generic landward wharf platform, not a surveyed Victorian quay wall.
    p = Parts('quay_platform')
    p.box((0, 0, 0.6), (30, 7, 1.2), 'stone')
    p.box((0, -2, 1.28), (28, 2, 0.16), 'wood')
    for x in (-12, 0, 12):
        p.box((x, 2.7, 1.6), (0.8, 0.8, 0.8), 'opening')
    objects.append(p.make(material))
    return objects


def main():
    ASSET.parent.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.unit_settings.scale_length = 1
    bpy.context.preferences.filepaths.save_version = 0
    material = bpy.data.materials.new('Cabinet muted masonry')
    material.use_nodes = True
    material.node_tree.nodes.clear()
    principled = material.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    output = material.node_tree.nodes.new('ShaderNodeOutputMaterial')
    material.node_tree.links.new(principled.outputs['BSDF'], output.inputs['Surface'])
    principled.inputs['Roughness'].default_value = 0.94
    principled.inputs['Specular IOR Level'].default_value = 0.15
    colour = material.node_tree.nodes.new('ShaderNodeVertexColor')
    colour.layer_name = 'Col'
    material.node_tree.links.new(colour.outputs['Color'], principled.inputs['Base Color'])
    objects = modules(material)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=str(ASSET), export_format='GLB', use_selection=True,
        export_yup=True, export_texcoords=False, export_normals=True,
        export_tangents=False, export_animations=False, export_cameras=False,
        export_lights=False, export_extras=False, export_use_gltfpack=False)
    raw = ASSET.read_bytes()
    length = struct.unpack_from('<I', raw, 12)[0]
    gltf = json.loads(raw[20:20+length])
    report = {'blender': bpy.app.binary_path, 'version': bpy.app.version_string,
              'asset': str(ASSET.relative_to(ROOT)), 'bytes': len(raw),
              'materials': len(gltf.get('materials', [])), 'textures': len(gltf.get('textures', [])),
              'units': 'metres; base origin; Blender Z-up to glTF Y-up', 'modules': []}
    for mesh in gltf['meshes']:
        tris = sum(gltf['accessors'][p['indices']]['count']//3 for p in mesh['primitives'])
        report['modules'].append({'name': mesh['name'], 'triangles': tris,
                                  'surfaces': len(mesh['primitives'])})
    (WORK/'modules.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf8')
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'cabinet_building_modules.blend'))
    print('WWO_MODULES '+json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
