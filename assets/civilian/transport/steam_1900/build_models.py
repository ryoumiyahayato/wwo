"""Author the original low-poly steam-era transport kit with Python 3."""

import json
import math
import struct
from pathlib import Path


PALETTE = {
    "iron": "333a3d", "steel": "81878a", "black": "202829",
    "green": "2c554c", "brass": "be9d59", "maroon": "783d40",
    "cream": "ded1a7", "glass": "3d555c", "timber": "765e49",
    "ballast": "71716e", "brick": "9e614f", "stone": "b5a48b",
    "tile": "685558", "navy": "283746", "rust": "873e36",
    "white": "e7e3d5", "buff": "be8550", "coal": "29282a",
}

RAIL_GAUGE_M = 1.435
RAILHEAD_WIDTH_M = 0.08
RAIL_CENTER_M = (RAIL_GAUGE_M + RAILHEAD_WIDTH_M) / 2


def subtract(a, b):
    return tuple(x - y for x, y in zip(a, b))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def normal(a, b, c):
    x, y, z = subtract(b, a)
    u, v, w = subtract(c, a)
    return (y * w - z * v, z * u - x * w, x * v - y * u)


class Model:
    def __init__(self, near):
        self.near = near
        self.faces = {}

    def face(self, color, points, inside):
        # The inside point fixes winding, including when a profile changes axis.
        vector = normal(*points[:3])
        if dot(vector, subtract(inside, points[0])) > 0:
            points = tuple(reversed(points))
        triangles = self.faces.setdefault(color, [])
        for edge in range(1, len(points) - 1):
            triangle = (points[0], points[edge], points[edge + 1])
            vector = normal(*triangle)
            length = math.sqrt(dot(vector, vector))
            triangles.append((triangle, tuple(value / length for value in vector)))

    def loft(self, rings, colors):
        inside = tuple(sum(axis) / (len(rings) * len(rings[0]))
                       for axis in zip(*(point for ring in rings for point in ring)))
        self.face(colors[0], rings[0], inside)
        for lower, upper, color in zip(rings, rings[1:], colors):
            for i in range(len(lower)):
                j = (i + 1) % len(lower)
                self.face(color, (lower[i], lower[j], upper[j], upper[i]), inside)
        self.face(colors[-1], rings[-1], inside)

    def box(self, color, x, y, z, width, height, length):
        rings = [tuple((x + dx * width / 2, level, z + dz * length / 2)
                       for dx, dz in [(-1, -1), (1, -1), (1, 1), (-1, 1)])
                 for level in (y - height / 2, y + height / 2)]
        self.loft(rings, [color])

    def profile(self, color, z, length, cross_section):
        self.loft([tuple((x, y, end) for x, y in cross_section)
                   for end in (z - length / 2, z + length / 2)], [color])

    def tube(self, color, axis, x, y, z, length, radius, tip=None, sides=None, rake=0):
        segments = sides or (12 if self.near else 6)
        rings = []
        for end, size in [(-1, radius), (1, tip if tip is not None else radius)]:
            ring = []
            for step in range(segments):
                angle = math.tau * step / segments
                a, b, d = size * math.cos(angle), size * math.sin(angle), end * length / 2
                if axis == "x":
                    ring.append((x + d, y + a, z + b))
                elif axis == "y":
                    ring.append((x + a, y + d, z + b + end * rake / 2))
                else:
                    ring.append((x + a, y + b, z + d))
            rings.append(tuple(ring))
        self.loft(rings, [color])


def wheels(model, centers, radius):
    for z in centers:
        for x in (-RAIL_CENTER_M, RAIL_CENTER_M):
            model.tube("iron", "x", x, radius, z, 0.22, radius)
            if model.near:
                outside = x + math.copysign(0.117, x)
                model.tube("steel", "x", outside, radius, z, 0.025, radius * 0.82)
                model.tube("iron", "x", outside + math.copysign(0.04, x),
                           radius, z, 0.10, radius * 0.31)


def underframe(model, length, color="iron"):
    model.box(color, 0, 0.98, 0, 2.65, 0.30, length - 0.52)
    for sign in (-1, 1):
        model.box("black", 0, 0.98, sign * (length / 2 - 0.20), 1.08, 0.19, 0.40)
        if model.near:
            for x in (-0.86, 0.86):
                model.tube("steel", "z", x, 0.98, sign * (length / 2 - 0.18),
                           0.34, 0.14)


def locomotive(model):
    underframe(model, 12.8, "maroon")
    wheels(model, (-2.46, -0.80, 0.86), 0.78)
    wheels(model, (3.58, 4.62), 0.39)
    model.tube("green", "z", 0, 2.38, 0.67, 7.70, 1.10)
    model.tube("black", "z", 0, 2.38, 4.78, 1.48, 1.05)
    model.tube("black", "y", 0, 3.92, 4.79, 1.23, 0.35, 0.48)
    model.tube("green", "y", 0, 3.50, 1.65, 0.93, 0.47, 0.32)
    model.box("green", 0, 2.61, -3.92, 2.67, 2.85, 2.65)
    model.profile("black", -3.93, 2.95, [
        (-1.48, 3.88), (1.48, 3.88), (1.48, 4.03), (0.82, 4.20),
        (-0.82, 4.20), (-1.48, 4.03),
    ])
    model.profile("maroon", 5.58, 1.00, [(-1.28, 0.46), (1.28, 0.46),
                                         (1.28, 0.98), (-1.28, 0.98)])
    if model.near:
        for x in (-1.35, 1.35):
            model.box("brass", x, 3.33, -3.88, 0.04, 0.75, 1.54)
            model.box("glass", x * 1.02, 3.33, -3.88, 0.025, 0.61, 1.39)
        for x in (-0.91, 0.91):
            model.box("steel", x, 0.71, -0.80, 0.12, 0.16, 3.73)
        for z in (-1.85, 0.25, 2.67):
            model.tube("brass", "z", 0, 2.38, z, 0.08, 1.117)
        model.tube("brass", "z", 0, 2.38, 5.547, 0.12, 0.28)
        model.tube("cream", "z", 0, 3.01, 5.48, 0.26, 0.17)
        model.tube("steel", "y", 0, 4.54, 4.79, 0.10, 0.52)


def tender(model):
    underframe(model, 7.0, "maroon")
    wheels(model, (-2.25, 0, 2.25), 0.53)
    model.box("green", 0, 1.87, 0, 2.65, 1.50, 6.37)
    model.profile("coal", 0.50, 4.85, [
        (-1.18, 2.61), (1.18, 2.61), (0.77, 2.92), (-0.63, 3.09), (-0.98, 2.92),
    ])
    if model.near:
        for x in (-1.334, 1.334):
            model.box("brass", x, 1.77, 0, 0.02, 0.055, 5.57)
        model.box("steel", 0, 2.64, -2.30, 1.08, 0.11, 0.41)


def coach(model):
    underframe(model, 17.0)
    wheels(model, (-6.32, -4.64, 4.64, 6.32), 0.48)
    model.box("maroon", 0, 1.76, 0, 2.73, 1.30, 16.02)
    model.box("cream", 0, 2.73, 0, 2.73, 0.66, 16.02)
    model.profile("stone", 0, 16.53, [
        (-1.46, 3.05), (1.46, 3.05), (1.46, 3.18), (0.90, 3.48),
        (-0.90, 3.48), (-1.46, 3.18),
    ])
    windows = range(-6, 7) if model.near else (-5, 0, 5)
    for x in (-1.378, 1.378):
        for z in windows:
            model.box("glass", x, 2.75, z * 1.11, 0.025, 0.47,
                      0.69 if model.near else 3.95)
        if model.near:
            model.box("brass", x, 2.28, 0, 0.025, 0.055, 15.77)
    if model.near:
        for z in (-8.04, 8.04):
            model.box("black", 0, 1.80, z, 1.20, 0.14, 0.48)
            model.box("glass", 0, 2.60, z, 0.45, 0.62, 0.08)


def wagon(model):
    underframe(model, 8.0)
    wheels(model, (-2.33, 2.33), 0.48)
    model.box("timber", 0, 2.01, 0, 2.65, 1.75, 7.36)
    model.profile("iron", 0, 7.60, [
        (-1.40, 2.85), (1.40, 2.85), (1.40, 2.97), (0, 3.18), (-1.40, 2.97),
    ])
    for x in (-1.35, 1.35):
        model.box("maroon", x, 2.01, 0, 0.055, 1.58, 1.82)
        if model.near:
            for z in (-3.45, -2.23, -0.92, 0.92, 2.23, 3.45):
                model.box("iron", x * 1.02, 2.01, z, 0.055, 1.75, 0.09)
            model.box("steel", x * 1.029, 1.89, 0.60, 0.06, 0.09, 0.16)


def track(model):
    model.profile("ballast", 0, 12, [(-1.52, 0), (1.52, 0), (1.29, 0.09), (-1.29, 0.09)])
    sleepers = range(-9, 10) if model.near else range(-4, 5)
    for i in sleepers:
        model.box("timber", 0, 0.12, i * (0.62 if model.near else 1.31),
                  2.53, 0.09, 0.22 if model.near else 0.37)
    for x in (-RAIL_CENTER_M, RAIL_CENTER_M):
        model.box("steel", x, 0.20, 0, RAILHEAD_WIDTH_M, 0.08, 12)
        if model.near:
            model.box("iron", x, 0.1675, 0, 0.17, 0.025, 12)


def station(model):
    model.box("stone", 0, 0.24, 0, 9.0, 0.48, 19.3)
    model.box("brick", 0, 2.85, 0, 8.60, 5.05, 18.94)
    model.profile("tile", 0, 19.55, [
        (-4.66, 5.22), (4.66, 5.22), (4.66, 5.47), (0, 8.05), (-4.66, 5.47),
    ])
    model.box("brick", 2.25, 6.88, -4.87, 0.85, 2.10, 0.95)
    model.box("stone", 2.25, 8.00, -4.87, 1.01, 0.20, 1.11)
    for x in (-4.33, 4.33):
        model.box("timber", x, 1.28, 0, 0.075, 2.56, 1.62)
        for z in (-7.22, -4.91, -2.48, 2.48, 4.91, 7.22):
            model.box("glass", x, 2.59, z, 0.08, 1.68, 1.21)
            if model.near:
                model.box("stone", x * 1.018, 1.72, z, 0.14, 0.16, 1.55)
                model.box("timber", x * 1.016, 2.59, z, 0.07, 1.68, 0.08)
        if model.near:
            model.box("stone", x, 4.82, 0, 0.21, 0.18, 19.00)
    if model.near:
        for z in (-9.50, 9.50):
            model.box("glass", 0, 3.43, z, 1.29, 1.41, 0.10)


def platform(model):
    model.box("brick", 0, 0.34, 0, 4.30, 0.68, 18.0)
    model.box("stone", 0, 0.765, 0, 4.46, 0.17, 18.0)
    model.profile("tile", 0, 16.0, [
        (-2.05, 3.71), (2.05, 3.71), (2.05, 3.83), (0, 4.52), (-2.05, 3.83),
    ])
    for x in (-1.57, 1.57):
        for z in (-6.8, -2.27, 2.27, 6.8):
            model.box("green", x, 2.33, z, 0.16, 3.04, 0.16)
            if model.near:
                model.box("stone", x, 0.97, z, 0.31, 0.24, 0.31)
    if model.near:
        for z in (-4.82, 4.82):
            model.box("timber", 0, 1.24, z, 0.54, 0.13, 2.21)
            for offset in (-0.84, 0.84):
                model.box("iron", 0, 1.02, z + offset, 0.40, 0.34, 0.11)


def hull(model, length, beam, draft, deck):
    # The rings retain the same bow, stern and waterline at both detail levels.
    sections = [(-0.50, 0.20), (-0.44, 0.73), (-0.32, 0.97), (-0.15, 1.0),
                (0.17, 1.0), (0.32, 0.82), (0.45, 0.34), (0.50, 0.0)]
    if not model.near:
        sections = [sections[i] for i in (0, 1, 2, 4, 6, 7)]
    half = [(width * beam / 2, z * length) for z, width in sections]
    outline = half + [(-x, z) for x, z in reversed(half[:-1])]
    rings = [tuple((x * width, y, z * scale) for x, z in outline)
             for y, width, scale in [(-draft, 0.61, 0.92), (-draft * 0.21, 0.93, 0.97),
                                      (0.18, 0.97, 0.99), (deck, 1, 1)]]
    model.loft(rings, ["rust", "rust", "navy"])
    # A smaller deck veneer exposes the hull edge.
    model.loft([tuple((x * 0.93, y, z * 0.96) for x, z in outline)
                for y in (deck, deck + 0.08)], ["timber"])


def funnel(model, z, y, radius, height):
    model.tube("buff", "y", 0, y + height / 2, z, height, radius, radius * 0.89,
               rake=-height * 0.12)
    model.tube("black", "y", 0, y + height, z - height * 0.063, height * 0.16,
               radius * 0.94, rake=-height * 0.02)


def mast(model, z, y, height, cargo_derrick=False):
    model.tube("timber", "y", 0, y + height / 2, z, height, 0.31, 0.15,
               sides=6, rake=-height * 0.07)
    if cargo_derrick:
        model.tube("timber", "y", 0.48, y + height * 0.34, z - 2.22,
                   height * 0.60, 0.18, 0.13, sides=6, rake=4.15)


def liner(model):
    hull(model, 150.0, 17.6, 5.6, 7.6)
    model.box("white", 0, 9.60, -1.6, 14.7, 4.1, 90.0)
    model.box("cream", 0, 12.58, -1.6, 13.8, 1.88, 70.0)
    model.box("white", 0, 13.49, 27.8, 15.5, 2.44, 9.4)
    model.box("glass", 0, 14.02, 32.54, 11.4, 0.88, 0.13)
    for z in (-15.8, 10.8):
        funnel(model, z, 13.4, 2.05, 9.2)
    for z in (-53.5, 54.2):
        mast(model, z, 7.6, 17.6)
    if model.near:
        for x in (-7.4, 7.4):
            for z in range(-42, 43, 6):
                model.box("glass", x, 9.92, z, 0.13, 0.59, 1.04)
            for z in (-25.5, -13.6, -1.7, 10.2):
                model.box("white", x, 12.41, z, 1.7, 0.73, 7.7)
                model.box("timber", x, 12.80, z, 1.35, 0.12, 6.9)


def freighter(model):
    hull(model, 86.0, 12.0, 4.0, 4.4)
    model.box("white", 0, 6.12, -3.43, 9.2, 3.43, 15.1)
    model.box("timber", 0, 8.58, 0, 7.45, 1.62, 5.85)
    model.box("glass", 0, 8.68, 2.98, 5.64, 0.70, 0.13)
    funnel(model, -7.63, 7.78, 1.44, 5.45)
    for z in (-24.5, 22.5):
        model.box("maroon", 0, 4.87, z - 3.3, 6.6, 0.94, 13.3)
        mast(model, z + 4.7, 4.4, 12.0, model.near)
    if model.near:
        for z in (-30.5, -28, -25.5, 16.8, 19.3, 21.8):
            model.box("timber", 0, 5.37, z, 6.18, 0.09, 0.19)
        for x in (-4.63, 4.63):
            model.box("glass", x, 6.68, -1.6, 0.10, 0.64, 5.2)


def paddle_steamer(model):
    hull(model, 47.0, 7.7, 1.5, 2.25)
    model.box("white", 0, 3.36, 0, 6.65, 2.23, 26.8)
    model.box("cream", 0, 5.22, 7.12, 4.5, 1.41, 5.9)
    model.box("glass", 0, 5.34, 10.12, 3.68, 0.52, 0.13)
    funnel(model, 0.91, 4.44, 0.90, 5.05)
    for x in (-4.10, 4.10):
        model.tube("buff", "x", x, 1.53, 0, 1.18, 2.11)
        model.box("white", x, 2.20, 0, 1.43, 2.24, 4.45)
        if model.near:
            model.tube("maroon", "x", x * 1.18, 2.20, 0, 0.09, 0.69)
    mast(model, 17.6, 2.33, 6.96)
    windows = range(-11, 12, 2) if model.near else (-8, 8)
    for x in (-3.35, 3.35):
        for z in windows:
            model.box("glass", x, 3.54, z, 0.085, 0.66, 1.05 if model.near else 5.91)


MODELS = {
    "steam_locomotive": locomotive, "coal_tender": tender,
    "passenger_coach": coach, "box_wagon": wagon, "straight_track": track,
    "station_building": station, "station_platform": platform,
    "passenger_steamship": liner, "cargo_steamship": freighter,
    "coastal_paddle_steamer": paddle_steamer,
}


def color_factor(hex_code):
    srgb = [int(hex_code[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb] + [1]


def build():
    doc = {
        "asset": {"version": "2.0", "generator": "WWO Steam Transport"},
        "scene": 0, "scenes": [], "nodes": [], "meshes": [],
        "bufferViews": [], "accessors": [],
        "materials": [{"name": color, "pbrMetallicRoughness": {
            "baseColorFactor": color_factor(value), "metallicFactor": 0,
            "roughnessFactor": 0.85}}
            for color, value in PALETTE.items()],
    }
    material_ids = {name: index for index, name in enumerate(PALETTE)}
    binary = bytearray()

    def view(data, target, stride=None):
        binary.extend(b"\0" * (-len(binary) % 4))
        entry = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(data), "target": target}
        if stride is not None:
            entry["byteStride"] = stride
        key = len(doc["bufferViews"])
        doc["bufferViews"].append(entry)
        binary.extend(data)
        return key

    def accessor(view_id, dtype, size, count, **attributes):
        key = len(doc["accessors"])
        doc["accessors"].append({"bufferView": view_id, "componentType": dtype,
                                 "type": size, "count": count, **attributes})
        return key

    for name, shape in MODELS.items():
        for lod in ("near", "far"):
            model = Model(lod == "near")
            shape(model)
            key = f"{name}_{lod}"
            node = len(doc["nodes"])
            doc["scenes"].append({"name": key, "nodes": [node]})
            doc["nodes"].append({"name": key, "mesh": node})
            primitives = []
            for color, triangles in model.faces.items():
                vertices = {}
                indices = []
                for points, direction in triangles:
                    for point in points:
                        vertex = tuple(round(value, 7) for value in (*point, *direction))
                        indices.append(vertices.setdefault(vertex, len(vertices)))
                positions = list(zip(*vertices))[:3]
                vertex_data = b"".join(struct.pack("<6f", *vertex) for vertex in vertices)
                index_data = struct.pack(f"<{len(indices)}H", *indices)
                vb = view(vertex_data, 34962, 24)
                ib = view(index_data, 34963)
                pos = accessor(vb, 5126, "VEC3", len(vertices),
                               min=[min(axis) for axis in positions],
                               max=[max(axis) for axis in positions])
                norms = accessor(vb, 5126, "VEC3", len(vertices), byteOffset=12)
                idx = accessor(ib, 5123, "SCALAR", len(indices))
                primitives.append({"attributes": {"POSITION": pos, "NORMAL": norms},
                                   "indices": idx, "material": material_ids[color]})
            doc["meshes"].append({"name": key, "primitives": primitives})
            print(f"{key:26} {sum(map(len, model.faces.values())):4} triangles")

    doc["buffers"] = [{"byteLength": len(binary)}]
    meta = json.dumps(doc, separators=(",", ":")).encode()
    meta += b" " * (-len(meta) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    total = 28 + len(meta) + len(binary)
    output = Path(__file__).with_name("steam_1900.glb")
    with output.open("wb") as handle:
        handle.write(struct.pack("<4sII", b"glTF", 2, total))
        handle.write(struct.pack("<I4s", len(meta), b"JSON"))
        handle.write(meta)
        handle.write(struct.pack("<I4s", len(binary), b"BIN\0"))
        handle.write(binary)
    print(f"{output.name}: {total} bytes")


if __name__ == "__main__":
    build()
