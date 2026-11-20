"""Generate the Rust game's embedded surface textures without source images."""

from pathlib import Path
from random import Random

from PIL import Image


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


def surface(size, fields):
    def channel(u, v, sample, center, amplitude):
        return min(255, max(0, round(255 * (center + amplitude * sample(u, v)))))

    pixels = bytearray(
        channel((x + 0.5) / size, (y + 0.5) / size, *signal)
        for y in range(size)
        for x in range(size)
        for signal in fields
    )
    mode = "RGBA" if len(fields) == 4 else "LA"
    return Image.frombytes(mode, (size, size), bytes(pixels)).convert("RGBA")


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
        (field(47, (16, 13), (43, 29), 0.34), 0.73, 0.28),
    )
    surface(256, ocean).save(output / "ocean-material.png", optimize=True)


if __name__ == "__main__":
    build(Path(__file__).resolve().parents[1] / "src")
