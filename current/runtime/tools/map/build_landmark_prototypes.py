"""Create WWO's three 1900 landmark miniatures with the installed Blender.

Run: blender --background --factory-startup --python tools/map/build_landmark_prototypes.py
Only GLBs go into assets/landmarks. Renders, source blend and production notes
stay in local-artifacts. This does not install landmarks into the game.
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets" / "landmarks"
WORK = ROOT / "local-artifacts" / "landmark-prototypes-r1"

# A common palette, opaque metallic-roughness materials, no image textures.
PALETTE = {
    "iron": ((0.36, 0.27, 0.15), 0.32, 0.76),
    "stone": ((0.56, 0.48, 0.36), 0.0, 0.94),
    "limestone": ((0.73, 0.66, 0.52), 0.0, 0.91),
    "granite": ((0.44, 0.32, 0.25), 0.0, 0.96),
    "ink": ((0.065, 0.10, 0.13), 0.14, 0.81),
    "ivory": ((0.88, 0.85, 0.74), 0.0, 0.72),
}
SOURCES = {
    "eiffel_tower_1900": [
        {"title": "Gustave Eiffel, La tour Eiffel en 1900 (1902), p. 16",
         "url": "https://fr.wikisource.org/wiki/Page:Eiffel_-_La_tour_Eiffel_en_1900,_1902.djvu/40",
         "use": "Floors at 57.63, 115.73, 276.13 m; original crown at 300.51 m."},
        {"title": "Eiffel Tower official painting history",
         "url": "https://www.toureiffel.paris/en/the-monument/painting-eiffel-tower",
         "use": "1899 yellow gradients inform a muted ochre metal palette; not modern brown or modern antennae."},
    ],
    "giza_pyramids_1900": [
        {"title": "W. M. Flinders Petrie, The Pyramids and Temples of Gizeh (1883), chapters VI, VIII, X, XIII",
         "url": "https://www.petrieproject.com/book/the-pyramids-and-temples-of-gizeh",
         "use": "Approximate original casing bases and inclinations; centre offsets from section 92, inches converted to metres."},
        {"title": "Digital Giza, Petrie volume catalogue",
         "url": "https://giza.fas.harvard.edu/pubdocs/551/full/",
         "use": "Attribution of the 1883 survey."},
        {"title": "Egypt Ministry of Tourism and Antiquities, Khafre",
         "url": "https://egymonuments.gov.eg/monuments/pyramid-complex-of-khafre-khefren/",
         "use": "Limestone core and surviving light upper casing; the asset does not restore a complete ancient casing."},
    ],
    "westminster_clock_tower_1900": [
        {"title": "UK Parliament, facts and figures",
         "url": "https://www.parliament.uk/about/living-heritage/building/palace/big-ben/facts-figures/",
         "use": "About 96 m height, four 7 m clock dials."},
        {"title": "UK Parliament, Saving Big Ben",
         "url": "https://www.parliament.uk/about/living-heritage/building/palace/big-ben/elizabeth-tower-and-big-ben-conservation-works-2017-/all-your-questions-about-the-works-answered/",
         "use": "12 m square footprint and pre-1900 Gothic exterior."},
        {"title": "UK Parliament, original dial colour scheme",
         "url": "https://www.parliament.uk/mps-lords-and-offices/offices/commons/media-relations-group/news/elizabeth-tower-clock-dials-to-change-colour-following-repair-work/",
         "use": "Victorian blue/gold and white glass inform subdued dark-blue hands and ivory dial; not an exact 1900 paint reconstruction."},
    ],
}


class MeshParts:
    """Small mesh accumulator for these three assets, not a runtime component."""

    def __init__(self, name):
        self.name = name
        self.vertices = []
        self.faces = []
        self.face_materials = []

    def part(self, vertices, faces, material):
        offset = len(self.vertices)
        self.vertices.extend(tuple(v) for v in vertices)
        self.faces.extend(tuple(offset + i for i in f) for f in faces)
        self.face_materials.extend([material] * len(faces))

    def loft(self, rings, material, cap=True):
        count = len(rings[0])
        vertices = [v for ring in rings for v in ring]
        faces = []
        for level in range(len(rings) - 1):
            for j in range(count):
                k = (j + 1) % count
                faces.append((level * count + j, level * count + k,
                              (level + 1) * count + k, (level + 1) * count + j))
        if cap:
            faces += [tuple(reversed(range(count))),
                      tuple((len(rings) - 1) * count + j for j in range(count))]
        self.part(vertices, faces, material)

    def box(self, center, size, material):
        x, y, z = center
        w, d, h = size
        self.loft([square(x, y, z - h / 2, w, d),
                   square(x, y, z + h / 2, w, d)], material)

    def beam(self, start, end, thickness, material):
        a, b = Vector(start), Vector(end)
        direction = (b - a).normalized()
        ref = Vector((0, 0, 1)) if abs(direction.z) < 0.93 else Vector((0, 1, 0))
        u = direction.cross(ref).normalized()
        v = direction.cross(u).normalized()
        # Three-sided closed rods need eight triangles, not twelve per brace.
        rings = [[p + thickness * (u * math.cos(t) + v * math.sin(t))
                  for t in (0, 2 * math.pi / 3, 4 * math.pi / 3)] for p in (a, b)]
        self.loft(rings, material)

    def arc_rod(self, points, thickness, material):
        points = [Vector(p) for p in points]
        rings = []
        for i, p in enumerate(points):
            direction = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
            u = direction.cross(Vector((0, 0, 1))).normalized()
            v = direction.cross(u).normalized()
            rings.append([p + thickness * (u * math.cos(t) + v * math.sin(t))
                          for t in (0, 2 * math.pi / 3, 4 * math.pi / 3)])
        self.loft(rings, material)

    def square_ring(self, width, opening, z0, z1, material):
        rings = [square(0, 0, z0, width), square(0, 0, z1, width),
                 square(0, 0, z0, opening), square(0, 0, z1, opening)]
        faces = []
        for j in range(4):
            k = (j + 1) % 4
            faces += [(j, k, 4 + k, 4 + j), (8 + k, 8 + j, 12 + j, 12 + k),
                      (4 + j, 4 + k, 12 + k, 12 + j), (k, j, 8 + j, 8 + k)]
        self.part([v for ring in rings for v in ring], faces, material)

    def build(self):
        used = list(dict.fromkeys(self.face_materials))
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        for key in used:
            mesh.materials.append(MATERIALS[key])
        for polygon, key in zip(mesh.polygons, self.face_materials):
            polygon.material_index = used.index(key)
            polygon.use_smooth = False
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj["period"] = "1900; low-poly historical silhouette reference"
        obj["units"] = "metres; base origin; glTF Y-up"
        obj["geometry_note"] = "Authored miniature, not a measured survey or a world-state entity."
        return obj


def square(x, y, z, width, depth=None):
    depth = width if depth is None else depth
    return [(x - width / 2, y - depth / 2, z), (x + width / 2, y - depth / 2, z),
            (x + width / 2, y + depth / 2, z), (x - width / 2, y + depth / 2, z)]


def create_materials():
    result = {}
    for name, (color, metallic, roughness) in PALETTE.items():
        mat = bpy.data.materials.new("WWO_" + name)
        mat.diffuse_color = (*color, 1)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        result[name] = mat
    return result


def eiffel():
    mesh = MeshParts("eiffel_tower_1900")
    levels = [(0, 54, 10.5), (22, 43.5, 8.2), (57.63, 28, 6.0),
              (115.73, 13.4, 3.8), (165, 8.5, 2.7), (215, 5.2, 1.9), (276.13, 2.4, 1.2)]
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for sx, sy in corners:
        mesh.loft([square(sx * q, sy * q, z, width) for z, q, width in levels], "iron")
        mesh.box((sx * 54, sy * 54, 0.9), (15, 15, 1.8), "stone")
    for i in range(1, len(levels) - 1):
        za, qa, _ = levels[i]
        zb, qb, _ = levels[i + 1]
        for j in range(4):
            a, b = corners[j], corners[(j + 1) % 4]
            rod = 0.74 if i < 3 else 0.46
            mesh.beam((a[0] * qa, a[1] * qa, za), (b[0] * qb, b[1] * qb, zb), rod, "iron")
            mesh.beam((b[0] * qa, b[1] * qa, za), (a[0] * qb, a[1] * qb, zb), rod, "iron")
    for z, q, _ in levels[4:6]:
        for j in range(4):
            a, b = corners[j], corners[(j + 1) % 4]
            mesh.beam((a[0] * q, a[1] * q, z), (b[0] * q, b[1] * q, z), 0.65, "iron")
    # Six-segment curved arches, one on each side; no complete truss inventory.
    for face in range(4):
        points = []
        for i in range(7):
            t = i / 6
            x, z = (2 * t - 1) * 47.5, 6 + 33 * math.sin(math.pi * t)
            q = 54 + (43.5 - 54) * z / 22 if z <= 22 else 43.5 + (28 - 43.5) * (z - 22) / (57.63 - 22)
            p = Vector((x, -q, z))
            angle = face * math.pi / 2
            points.append((p.x * math.cos(angle) - p.y * math.sin(angle),
                           p.x * math.sin(angle) + p.y * math.cos(angle), p.z))
        mesh.arc_rod(points, 1.55, "iron")
    mesh.square_ring(69, 53, 55.7, 58.3, "iron")
    mesh.square_ring(40, 27, 114.3, 117.2, "iron")
    mesh.box((0, 0, 276.1), (10.5, 10.5, 2.0), "iron")
    mesh.box((0, 0, 282), (7.6, 7.6, 9.8), "iron")
    mesh.loft([square(0, 0, 286.9, 8.4), square(0, 0, 291, 4.6)], "iron")
    mesh.box((0, 0, 294), (3.8, 3.8, 6.0), "iron")
    mesh.loft([square(0, 0, 297, 4.8), square(0, 0, 300.51, 0.7)], "iron")
    return mesh.build(), [
        "Only representative braces, arches and platform rings; no individual rivets, stairs, lifts or internal rooms.",
        "Original 300.51 m crown represented without twentieth/twenty-first-century antenna additions.",
        "A single muted ochre metal material abstracts the five 1899 paint gradients.",
    ]


def giza():
    mesh = MeshParts("giza_pyramids_1900")
    # Petrie 1883 section 92: centre offsets in inches along near-cardinal axes.
    # +X east, +Y north. The second and third pyramids lie southwest of Khufu.
    pyramids = [
        ("Khufu", 0, 0, 9068.8 * 0.0254, 146.7, 138.5),
        ("Khafre", -13165.8 * 0.0254, -13931.6 * 0.0254, 8474.9 * 0.0254, 143.9, 136.4),
        ("Menkaure", -22616.0 * 0.0254, -29102.0 * 0.0254, 4153.6 * 0.0254, 65.5, 61.0),
    ]
    for name, x, y, base, original_height, remaining in pyramids:
        splits = [0, 18 if name == "Menkaure" else 32,
                  remaining * (0.73 if name == "Khafre" else 0.66), remaining]
        for i in range(3):
            z0, z1 = splits[i:i + 2]
            w0, w1 = base * (1 - z0 / original_height), base * (1 - z1 / original_height)
            material = "granite" if name == "Menkaure" and i == 0 else "stone"
            if name == "Khafre" and i == 2:
                material = "limestone"
            mesh.loft([square(x, y, z0, w0), square(x, y, z1, w1)], material, cap=False)
        mesh.part(square(x, y, 0, base), [(3, 2, 1, 0)], "stone")
        top_width = base * (1 - remaining / original_height)
        mesh.part(square(x, y, remaining, top_width), [(0, 1, 2, 3)],
                  "limestone" if name == "Khafre" else "stone")
    # A shared footprint-centre origin, all bottom vertices at z=0; no terrain mesh.
    xs, ys = [v[0] for v in mesh.vertices], [v[1] for v in mesh.vertices]
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    mesh.vertices = [(x - cx, y - cy, z) for x, y, z in mesh.vertices]
    return mesh.build(), [
        "Three principal pyramids only; no sphinx, temples, queens' pyramids, causeways or tourist structures.",
        "Truncated tops and a remaining Khafre casing cap indicate weathering; no individual stone blocks.",
        "Near-cardinal centre spacing follows the 1883 survey; slopes/heights are miniature approximations, not a measured 1900 surface.",
        "The plateau is flattened to a common placement plane; differing natural ground elevations are omitted.",
    ]


def tower():
    mesh = MeshParts("westminster_clock_tower_1900")
    mesh.loft([square(0, 0, z, w) for z, w in
               [(0, 12), (2, 12.4), (48, 12), (62, 12.4), (75, 11.3)]], "stone")
    for z, w, h in [(2, 13, 1.0), (18, 12.6, 0.7), (37, 12.6, 0.8),
                    (48, 13.1, 1.0), (62, 13.3, 1.2), (75, 13.2, 1.0)]:
        mesh.box((0, 0, z), (w, w, h), "limestone")
    for sx, sy in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
        mesh.box((sx * 5.8, sy * 5.8, 38), (0.85, 0.85, 74), "limestone")
        mesh.box((sx * 5.75, sy * 5.75, 77.1), (1.25, 1.25, 4.2), "limestone")
        mesh.loft([square(sx * 5.75, sy * 5.75, 79.2, 1.55),
                   square(sx * 5.75, sy * 5.75, 83.3, 0.15)], "limestone")

    def plane(face, x, z, offset=6.24):
        # A consistent outward normal and left-to-right basis for each clock face.
        angle = face * math.pi / 2
        return (x * math.cos(angle) + offset * math.sin(angle),
                x * math.sin(angle) - offset * math.cos(angle), z)

    def patch(face, coords, material, offset=6.24):
        mesh.part([plane(face, x, z, offset if offset is not None else
                         6.2 + (5.65 - 6.2) * (z - 62) / 13 + 0.025) for x, z in coords],
                  [tuple(range(len(coords)))], material)

    for face in range(4):
        for x in (-3.6, 3.6):
            # Two raised vertical strips, using closed narrow boxes.
            c = plane(face, x, 25.0, 6.0)
            size = (0.38, 0.30, 43.0) if face % 2 == 0 else (0.30, 0.38, 43.0)
            mesh.box(c, size, "limestone")
        for z in (26.0, 40.0, 68.0):
            for x in (-1.8, 1.8):
                h = 6.6 if z == 68 else 5.0
                patch(face, [(x - 0.62, z - h / 2), (x + 0.62, z - h / 2),
                             (x + 0.62, z + h / 2 - 0.9), (x, z + h / 2),
                             (x - 0.62, z + h / 2 - 0.9)], "ink", 6.28 if z < 62 else None)

        # Four 7 m ivory clock faces. No separate textures or hidden mechanisms.
        centre = 55.2
        circle = [(math.cos(i * math.tau / 16), math.sin(i * math.tau / 16)) for i in range(16)]
        vertices = [plane(face, 0, centre, 6.30)]
        vertices += [plane(face, x * 3.5, centre + y * 3.5, 6.30) for x, y in circle]
        mesh.part(vertices, [(0, i + 1, (i + 1) % 16 + 1) for i in range(16)], "ivory")
        rim = [plane(face, x * r, centre + y * r, 6.32) for r in (3.5, 3.86) for x, y in circle]
        mesh.part(rim, [(i, i + 16, (i + 1) % 16 + 16, (i + 1) % 16) for i in range(16)], "limestone")
        for i in range(12):
            angle = i * math.tau / 12
            r, w, length = 2.98, 0.10, 0.37 if i % 3 else 0.54
            u, v = Vector((math.sin(angle), math.cos(angle))), Vector((math.cos(angle), -math.sin(angle)))
            points = [u * t + v * s for t, s in [(r - length, -w), (r - length, w), (r, w), (r, -w)]]
            patch(face, [(p.x, centre + p.y) for p in points], "ink", 6.34)
        # Static illustrative hands, not a simulation clock: approximately 10:10.
        for angle, length, width in [(math.radians(-55), 1.9, 0.15), (math.radians(60), 2.75, 0.11)]:
            u, v = Vector((math.sin(angle), math.cos(angle))), Vector((math.cos(angle), -math.sin(angle)))
            points = [-v * width - u * 0.23, v * width - u * 0.23,
                      v * width + u * length, -v * width + u * length]
            patch(face, [(p.x, centre + p.y) for p in points], "ink", 6.37)
        hub = [(math.cos(i * math.tau / 6) * 0.22, centre + math.sin(i * math.tau / 6) * 0.22) for i in range(6)]
        patch(face, hub, "ink", 6.39)

    mesh.loft([square(0, 0, 75.5, 12.4), square(0, 0, 84.4, 5.4)], "ink")
    mesh.box((0, 0, 85.5), (5.4, 5.4, 2.2), "limestone")
    mesh.loft([square(0, 0, 86.6, 6.1), square(0, 0, 94.2, 0.9)], "ink")
    mesh.beam((0, 0, 94.2), (0, 0, 96.3), 0.18, "limestone")
    return mesh.build(), [
        "Clock Tower only; no Westminster Palace, interiors, bells or clock machinery.",
        "Four dials use geometry for indices and static hands; Roman lettering, inscriptions, heraldry and tracery are omitted.",
        "Gothic piers, pointed openings, four pinnacles and layered roof retained; proportions abstracted to a 12 m footprint and 96.3 m height.",
        "Muted Victorian colour references are not a claim to reproduce every 1900 paint layer.",
    ]


def export_model(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = ASSETS / (obj.name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True, use_active_scene=True,
        export_yup=True, export_apply=False, export_texcoords=False,
        export_normals=True, export_tangents=False, export_materials="EXPORT",
        export_animations=False, export_cameras=False, export_lights=False,
        export_extras=False, export_draco_mesh_compression_enable=False,
        export_use_gltfpack=False,
    )
    # Delivery figures come from the actual exported glTF index accessors.
    data = path.read_bytes()
    size, _ = struct.unpack_from("<II", data, 12)
    gltf = json.loads(data[20:20 + size])
    primitives = [p for m in gltf["meshes"] for p in m["primitives"]]
    triangles = sum(gltf["accessors"][p["indices"]]["count"] // 3 for p in primitives)
    return {"model": str(path.relative_to(ROOT)).replace("\\", "/"),
            "triangles": triangles, "bytes": len(data), "surfaces": len(primitives),
            "materials": [m["name"] for m in gltf.get("materials", [])],
            "textures": len(gltf.get("textures", [])),
            "dimensions_m": [round(v, 3) for v in obj.dimensions]}


def preview(obj):
    scene = bpy.data.scenes.new(obj.name + "_preview")
    scene.collection.objects.link(obj)
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    bounds = [obj.matrix_world @ Vector(v) for v in obj.bound_box]
    target = sum(bounds, Vector()) / 8
    span = max(obj.dimensions)
    direction = Vector((1.15, -1.65, 1.10)).normalized()
    camera = bpy.data.objects.new(obj.name + "_camera", bpy.data.cameras.new("PreviewCamera"))
    scene.collection.objects.link(camera)
    camera.location = target + direction * span * 3
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    inverse = camera.rotation_euler.to_matrix().transposed()
    projected = [inverse @ (p - target) for p in bounds]
    width = max(p.x for p in projected) - min(p.x for p in projected)
    height = max(p.y for p in projected) - min(p.y for p in projected)
    camera.data.ortho_scale = max(width, height) * 1.25
    camera.data.clip_end = span * 15
    scene.camera = camera
    world = bpy.data.worlds.new("NeutralStudio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.34, 0.35, 0.33, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.65
    scene.world = world
    floor_mesh = bpy.data.meshes.new("PreviewFloor")
    floor_mesh.from_pydata(square(0, 0, -max(span * 0.0002, 0.01), span * 200), [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("PreviewFloor", floor_mesh)
    scene.collection.objects.link(floor)
    mat = bpy.data.materials.new("PreviewNeutral")
    mat.diffuse_color = (0.21, 0.23, 0.22, 1)
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = mat.diffuse_color
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1
    floor_mesh.materials.append(mat)
    for name, position, energy, size, color in [
        ("SoftKey", (-1.3, -1.8, 2.4), 38, 1.4, (1.0, 0.94, 0.84)),
        ("SoftFill", (1.7, 0.8, 1.0), 12, 1.8, (0.84, 0.91, 1.0)),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = span * span * energy
        data.shape = "DISK"
        data.size = span * size
        data.color = color
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = target + Vector(position) * span
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = str(WORK / (obj.name + "_preview.png"))
    bpy.ops.render.render(write_still=True, scene=scene.name)
    return scene


def main():
    global MATERIALS
    ASSETS.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene.unit_settings.length_unit = "METERS"
    source_scene = bpy.context.scene
    source_scene.name = "WWO_Landmark_Source"
    bpy.context.preferences.filepaths.save_version = 0
    MATERIALS = create_materials()
    report = {"blender": bpy.app.binary_path, "blender_version": bpy.app.version_string,
              "units": "metres; Blender Z-up exported as glTF Y-up; origin on base plane",
              "authorship": "Original procedural meshes; source pages supply building facts only. No third-party model or image copied.",
              "palette": PALETTE, "models": []}
    first_preview = None
    for make in (eiffel, giza, tower):
        bpy.context.window.scene = source_scene
        obj, omissions = make()
        bpy.context.view_layer.update()
        item = export_model(obj)
        item["sources"] = SOURCES[obj.name]
        item["omissions"] = omissions
        item["preview"] = str((WORK / (obj.name + "_preview.png")).relative_to(ROOT)).replace("\\", "/")
        scene = preview(obj)
        if first_preview is None:
            first_preview = scene
        report["models"].append(item)
        print("WWO_ASSET " + json.dumps({k: item[k] for k in ("model", "triangles", "bytes", "surfaces", "textures")}), flush=True)
    report["total_model_bytes"] = sum(m["bytes"] for m in report["models"])
    report["runtime_notes"] = "No textures, animation, armature, lights or cameras in GLBs. Material palette shared by design, not by a new runtime service. Godot imports create their own mesh storage; GPU bytes are not inferred from file size. Not installed into WWO."
    (WORK / "landmarks.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if bpy.context.window is not None:
        bpy.context.window.scene = first_preview
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK / "landmark_prototypes.blend"))
    print("WWO_TOTAL_BYTES " + str(report["total_model_bytes"]), flush=True)


if __name__ == "__main__":
    main()
