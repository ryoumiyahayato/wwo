"""Generate the Rust game's embedded surface textures without source images."""

from pathlib import Path
from random import Random
from math import cos, sin, tau

from PIL import Image, ImageDraw


def gradient_field(seed, cells_x, cells_y):
    directions = (
        (1, 0), (0.7071, 0.7071), (0, 1), (-0.7071, 0.7071),
        (-1, 0), (-0.7071, -0.7071), (0, -1), (0.7071, -0.7071),
    )
    random = Random(seed)
    gradients = [random.choice(directions) for _ in range(cells_x * cells_y)]

    def dot(x, y, dx, dy):
        gx, gy = gradients[(y % cells_y) * cells_x + x % cells_x]
        return gx * dx + gy * dy

    def sample(u, v):
        x, y = (u % 1) * cells_x, (v % 1) * cells_y
        i, j = int(x), int(y)
        dx, dy = x - i, y - j
        sx = dx * dx * (3 - 2 * dx)
        sy = dy * dy * (3 - 2 * dy)
        top = dot(i, j, dx, dy) * (1 - sx) + dot(i + 1, j, dx - 1, dy) * sx
        bottom = dot(i, j + 1, dx, dy - 1) * (1 - sx) + dot(i + 1, j + 1, dx - 1, dy - 1) * sx
        return top * (1 - sy) + bottom * sy

    return sample


def field(seed, shape, detail, detail_ratio):
    broad = gradient_field(seed, *shape)
    fine = gradient_field(seed + 1, *detail)
    return lambda u, v: broad(u, v) + detail_ratio * fine(u, v)


def wave_packets(seed, crests, patches):
    crest = gradient_field(seed, *crests)
    bend = gradient_field(seed + 1, *patches)
    envelope = gradient_field(seed + 2, *patches)

    def sample(u, v):
        displacement = bend(u, v) * 1.8 / crests[1]
        strength = min(1, max(0, (envelope(u, v) + 0.18) * 2.2))
        return crest(u, v + displacement) * strength

    return sample


def surface(size, fields):
    def channel(u, v, sample, center, amplitude):
        return min(255, max(0, round(255 * (center + amplitude * sample(u, v)))))

    pixels = bytearray(
        channel((x + 0.5) / size, (y + 0.5) / size, *signal)
        for y in range(size)
        for x in range(size)
        for signal in fields
    )
    return Image.frombytes("RGBA", (size, size), bytes(pixels))


MATERIAL_SIZE = 128


def material_color(rgb, variation):
    return tuple(max(0, min(255, round(c * (1 + variation)))) for c in rgb)


def paint_material(name, color, seed):
    size = MATERIAL_SIZE
    random = Random(seed)
    wash = field(seed, (5, 6), (19, 23), 0.37)
    tile = Image.new("RGB", (size, size))
    tile.putdata([
        material_color(color, wash(x / size, y / size) * 0.21)
        for y in range(size) for x in range(size)
    ])
    draw = ImageDraw.Draw(tile)

    def line(points, variation, width=1):
        paint = material_color(color, variation)
        for dy in (-size, 0, size):
            for dx in (-size, 0, size):
                draw.line([(x + dx, y + dy) for x, y in points], fill=paint, width=width)

    def stone(x, y, radius, variation):
        points = []
        for j in range(6):
            angle = j * tau / 6
            r = radius * random.uniform(0.68, 1.18)
            points.append((x + cos(angle) * r, y + sin(angle) * r * 0.77))
        line(points + points[:1], variation - 0.13)
        paint = material_color(color, variation)
        for dy in (-size, 0, size):
            for dx in (-size, 0, size):
                draw.polygon([(px + dx, py + dy) for px, py in points], fill=paint)
        line(points[3:6], variation + 0.085)

    if name in ("grass", "woodland", "soil", "snow", "gravel", "rock"):
        count, low, high = {
            "grass": (385, 1.1, 3.2),
            "woodland": (178, 2.1, 5.2),
            "soil": (151, 0.8, 2.3),
            "snow": (82, 0.8, 3.3),
            "gravel": (635, 0.7, 2.8),
            "rock": (87, 3.0, 11.0),
        }[name]
        for _ in range(count):
            x, y = random.randrange(size), random.randrange(size)
            scale = random.uniform(low, high)
            shade = random.uniform(-0.17, 0.18)
            if name == "grass":
                line([(x, y), (x + scale * .5, y - scale), (x + scale, y - scale * 1.7)], shade)
            else:
                stone(x, y, scale, shade * (0.40 if name == "snow" else 1.0))
    elif name in ("field", "sand", "dirt road"):
        bend = gradient_field(seed + 341, 3, 4)
        gap = {"field": 8, "sand": 16, "dirt road": 32}[name]
        width = {"field": 3, "sand": 2, "dirt road": 5}[name]
        for y in range(0, size, gap):
            ridge = [(x, y + bend(x / size, y / size) * gap * .42) for x in range(0, size + 1, 2)]
            line(ridge, -.14, width)
            line([(x, y + width) for x, y in ridge], .10, max(1, width - 1))
        for _ in range(180):
            stone(random.randrange(size), random.randrange(size), random.uniform(.55, 1.4),
                  random.uniform(-.08, .095))
    else:
        width, height = {"setts": (16, 8), "roof": (16, 16), "wall": (32, 16)}[name]
        for j, y in enumerate(range(0, size, height)):
            for x in range(0, size, width):
                x += (j % 2) * width // 2
                shade = random.uniform(-.12, .12)
                for dy in (-size, 0, size):
                    for dx in (-size, 0, size):
                        a, b = x + dx, y + dy
                        draw.rectangle((a, b, a + width - 1, b + height - 1), fill=material_color(color, shade - .19))
                        draw.rounded_rectangle((a + 1, b + 1, a + width - 2, b + height - 2), radius=2,
                                               fill=material_color(color, shade))
                        draw.line((a + 3, b + 2, a + width - 4, b + 2), fill=material_color(color, shade + .10))
    return tile


def build_materials(output):
    # Layer order is shared by globe.wgsl and landmark.wgsl.
    materials = (
        ("grass", (112, 125, 82)), ("soil", (140, 117, 92)), ("field", (134, 129, 86)),
        ("woodland", (76, 100, 68)), ("rock", (132, 127, 116)), ("sand", (185, 156, 111)),
        ("snow", (217, 225, 226)), ("dirt road", (154, 134, 107)), ("gravel", (146, 140, 125)),
        ("setts", (135, 132, 124)), ("roof", (149, 135, 125)), ("wall", (173, 157, 136)),
    )
    tiles = Image.new("RGB", (MATERIAL_SIZE, MATERIAL_SIZE * len(materials)))
    for layer, (name, color) in enumerate(materials):
        tiles.paste(paint_material(name, color, 197 + layer * 107), (0, layer * MATERIAL_SIZE))
    tiles.convert("RGBA").save(output / "surface-materials.png", optimize=True)


def build(output):
    # Canopy, sward, rock and sediment are scalar channels, including alpha.
    land = (
        (field(11, (9, 12), (28, 33), 0.36), 0.5, 0.77),
        (field(19, (8, 15), (27, 45), 0.46), 0.5, 0.67),
        (field(23, (12, 9), (46, 32), 0.41), 0.5, 0.91),
        (field(31, (11, 18), (37, 67), 0.47), 0.5, 0.61),
    )
    surface(256, land).save(output / "land-material.png", optimize=True)

    # Match the shader's existing neutral open-water level and ice modulation.
    ocean = (
        (field(41, (9, 5), (24, 13), 0.28), 0.28, 0.21),
        (wave_packets(61, (4, 17), (7, 6)), 0.5, 0.92),
        (wave_packets(71, (8, 29), (9, 11)), 0.5, 1.18),
        (field(47, (16, 13), (43, 29), 0.34), 0.73, 0.28),
    )
    surface(256, ocean).save(output / "ocean-material.png", optimize=True)
    build_materials(output)


if __name__ == "__main__":
    build(Path(__file__).resolve().parents[1] / "src")
