"""Original metre-scale urban meshes for the already admitted R12 layouts.

Blender background only. No cadastral geometry, new facility ID or economy.
One vertex-colour material; no texture, lights, collision or animation.
"""
import json
import math
import struct
from pathlib import Path
import sys
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from build_settlement_modules import Parts, PALETTE, modules as old_modules

OUT = ROOT / 'assets/settlements/urban_landscape_r40.glb'
SOURCE = ROOT / 'tools/map/model_sources/r40'


def facade(p, width, depth, floors, bays, brick=False):
    """Relief windows, lintels, sill bands, entrances on both long facades."""
    for side in (-1, 1):
        y = side*(depth/2+0.04)
        for floor in range(floors):
            z = 2.0+floor*3.0
            for bay in range(bays):
                x = (bay-(bays-1)/2)*(width/(bays+0.5))
                p.box((x, y, z), (1.2, 0.10, 1.65), 'opening')
                p.box((x, y+side*0.08, z-0.91), (1.5, 0.22, 0.15), 'trim')
                if not brick:
                    for dx in (-0.70, 0.70):
                        p.box((x+dx, y, z), (0.13, 0.16, 1.9), 'trim')
            p.box((0, y, z+1.16), (width, 0.22, 0.18), 'trim')
        p.box((0, y+side*0.06, 1.6), (1.9, 0.25, 3.2), 'wood')
        p.box((0, y+side*0.20, 3.3), (2.3, 0.45, 0.24), 'trim')


def chimney(p, x, y, height, width=1.1):
    p.box((x, y, height-1), (width, width, 2.0), 'brick')
    p.box((x, y, height+0.15), (width+0.3, width+0.3, 0.3), 'trim')
    p.box((x, y, height+0.6), (width*0.65, width*0.65, 0.65), 'brick')


def detailed(material):
    result = []
    for name, variant in [('paris_mansard', 0), ('paris_corner', 1)]:
        p = Parts(name)
        p.box((0, 0, 7), (22, 12, 14), 'stone')
        for z in (0.4, 3.4, 13.9): p.box((0, 0, z), (22.8, 12.6, 0.40), 'trim')
        p.loft([(14.1, 23, 13), (17.1, 18.5, 8.5), (18.1, 16, 6)], 'slate')
        facade(p, 22, 12, 4, 6)
        for x in (-8, -4, 0, 4, 8):
            for side in (-1, 1):
                p.box((x, side*5.1, 16), (1.6, 1.5, 1.8), 'trim')
                p.box((x, side*5.87, 16), (0.9, 0.12, 1.15), 'opening')
                # Individual dormer caps instead of one undifferentiated roof.
                p.box((x, side*5.1, 17.0), (1.9, 1.8, 0.22), 'slate')
        for x in (-7, 7): chimney(p, x, 1.5, 18.8)
        if variant:
            for side in (-1, 1):
                p.box((side*10.9, 0, 7.4), (0.6, 5, 6.8), 'trim')
                for z in (5, 8, 11): p.box((side*11.24, 0, z), (0.14, 1.2, 1.8), 'opening')
        result.append(p.make(material))

    for name, variant in [('london_terrace', 0), ('london_gabled', 1)]:
        p = Parts(name)
        p.box((0, 0, 4.5), (24, 9, 9), 'brick')
        p.gable(24.5, 9.5, 9, 11.2, 'slate')
        facade(p, 24, 9, 3, 8, True)
        for x in (-9, -3, 3, 9):
            p.box((x, -4.65, 0.22), (2.2, 0.8, 0.44), 'stone')
            chimney(p, x, 0, 11.4)
            if variant:
                # Street-facing small gables, within the original footprint.
                p.add([(x-1.4,-4.74,9),(x+1.4,-4.74,9),(x,-4.74,11.1)], [(0,1,2)], 'brick')
        result.append(p.make(material))

    p = Parts('civic_hall')
    p.box((0,0,5), (24,15,10), 'stone')
    p.loft([(10,25,16),(13,19,10)], 'slate')
    facade(p,24,15,3,7)
    p.box((0,-8.1,0.8),(8,2.8,1.6),'trim')
    for x in (-3,-1,1,3): p.box((x,-8.2,4.8),(0.5,0.5,6.4),'trim')
    start = len(p.vertices)
    p.gable(8,2.5,8,10,'stone')
    p.vertices[start:] = [(x,y-7.5,z) for x,y,z in p.vertices[start:]]
    p.box((0,0,14),(4,4,2),'stone')
    p.loft([(15,4.4,4.4),(16.2,2,2)],'slate')
    result.append(p.make(material))

    p = Parts('warehouse')
    p.box((0,0,3.5),(28,15,7),'brick')
    p.gable(29,16,7,10,'slate')
    for x in (-10,-5,0,5,10):
        for side in (-1,1):
            p.box((x,side*7.56,2.3),(2.5,0.15,4.3),'wood')
            p.box((x,side*7.61,5.8),(1.7,0.12,1.1),'opening')
            p.box((x+1.7,side*7.55,3.6),(0.30,0.3,7.2),'trim')
    p.box((0,-7.9,7),(3,0.2,0.35),'wood')
    result.append(p.make(material))

    p = Parts('sawtooth_workshop')
    p.box((0,0,3.5),(28,15,7),'brick')
    # Three northlight roof pitches. No active smoke or invented machinery.
    for y in (-5,0,5):
        p.add([(-14,y-2.5,7),(14,y-2.5,7),(14,y+2.5,9.2),(-14,y+2.5,9.2)],[(0,1,2,3)],'slate')
        p.box((0,y+2.44,8.1),(27.5,0.12,1.7),'opening')
    for x in (-9,-3,3,9): p.box((x,-7.57,3.3),(3.4,0.16,3.4),'opening')
    p.box((11,5,10),(1.7,1.7,20),'brick')
    p.box((11,5,20.1),(2.2,2.2,0.6),'trim')
    result.append(p.make(material))

    p = Parts('quay_platform')
    p.box((0,0,0.55),(30,7,1.1),'stone')
    p.box((0,-2,1.17),(28,2,0.16),'wood')
    for x in range(-14,15,2):
        p.box((x,3.42,0.7),(0.06,0.08,0.7),'opening')
    for x in (-12,0,12):
        p.box((x,2.4,1.5),(0.4,0.4,0.8),'opening')
        p.box((x,2.4,1.85),(1.0,0.4,0.2),'opening')
    result.append(p.make(material))
    return result


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    SOURCE.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.context.scene.unit_settings.scale_length=1
    bpy.context.preferences.filepaths.save_version=0
    material=bpy.data.materials.new('WWO_R40_shared_masonry')
    material.use_nodes=True
    nodes=material.node_tree.nodes
    principled=nodes.get('Principled BSDF')
    principled.inputs['Roughness'].default_value=0.94
    principled.inputs['Specular IOR Level'].default_value=0.12
    colour=nodes.new('ShaderNodeVertexColor');colour.layer_name='Col'
    material.node_tree.links.new(colour.outputs['Color'],principled.inputs['Base Color'])
    detailed_objects=detailed(material)
    far=[]
    for obj in old_modules(material):
        if obj.name=='rural_house': bpy.data.objects.remove(obj,do_unlink=True);continue
        name=obj.name.split('.')[0]
        obj.name=name+'_far';obj.data.name=obj.name
        far.append(obj)
    # Detailed variants share their family's simple silhouette at a distance.
    for name,base in [('paris_corner','paris_mansard'),('london_gabled','london_terrace'),('sawtooth_workshop','warehouse')]:
        source=next(o for o in far if o.name==base+'_far')
        obj=bpy.data.objects.new(name+'_far',source.data)
        bpy.context.scene.collection.objects.link(obj);far.append(obj)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in detailed_objects+far: obj.select_set(True)
    bpy.context.view_layer.objects.active=detailed_objects[0]
    bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',use_selection=True,
        export_yup=True,export_texcoords=False,export_normals=True,export_tangents=False,
        export_animations=False,export_cameras=False,export_lights=False,export_extras=False)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'urban_landscape_r40.blend'))
    raw=OUT.read_bytes();length=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+length]);accessors=doc['accessors']
    description={'generator':'tools/map/build_landscape_modules_r40.py','license':'CC0-1.0; original WWO procedural geometry',
       'units':'metres; original R12 maximum ground footprints retained; glTF Y up',
       'meaning':'Abstract 19th-century style modules, not measured Paris or London buildings; no economic facility identity.',
       'file_bytes':len(raw),'materials':len(doc.get('materials',[])),'textures':len(doc.get('textures',[])),
       'meshes':[{'name':m['name'],'triangles':sum(accessors[p['indices']]['count']//3 for p in m['primitives'])} for m in doc['meshes']]}
    (SOURCE/'README.json').write_text(json.dumps(description,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('WWO_R40_URBAN '+json.dumps(description),flush=True)


if __name__=='__main__':main()
