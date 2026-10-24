"""Bake the R20 observer-space background. Python, Pillow and NumPy only.

Original WWO presentation art; no downloaded imagery or star catalogue.
The band and stars are illustrative, not astronomical positions.
Run from any directory. The runtime reads only the resulting PNG.
"""
from pathlib import Path

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 2048, 1152
OUTPUT = Path(__file__).resolve().parents[2] / "assets/maps/background/galactic_chart.png"
rng = np.random.default_rng(190020)


def smooth_field(columns, rows):
    values = rng.integers(0, 256, (rows, columns), dtype=np.uint8)
    return np.asarray(Image.fromarray(values).resize((WIDTH, HEIGHT), Image.Resampling.BICUBIC), dtype=np.float32) / 255


y, x = np.mgrid[0:HEIGHT, 0:WIDTH].astype(np.float32)
x = (x - WIDTH / 2) / HEIGHT
y = (y - HEIGHT / 2) / HEIGHT
across = y + x * 0.57 - 0.04
coarse = smooth_field(16, 10)
fine = smooth_field(80, 45)
band = np.exp(-np.square(across / 0.115))
halo = np.exp(-np.square(across / 0.25))
dust = np.exp(-np.square((across + (coarse - 0.5) * 0.09) / 0.025))
luminance = halo * 2.8 + band * (5.0 + coarse * 15.0 + fine * 3.0) * (1.0 - dust * 0.66)
rgb = np.empty((HEIGHT, WIDTH, 3), dtype=np.float32)
rgb[:] = [4.0, 9.0, 15.0]
rgb += luminance[..., None] * np.array([0.72, 0.79, 0.86])
rgb += np.exp(-((x * 0.65) ** 2 + (y * 0.9) ** 2))[..., None] * np.array([0.5, 1.0, 1.5])


def star(px, py, radius, brightness):
    extent = max(2, int(radius * 4))
    left, top = max(0, int(px) - extent), max(0, int(py) - extent)
    right, bottom = min(WIDTH, int(px) + extent + 2), min(HEIGHT, int(py) + extent + 2)
    sy, sx = np.mgrid[top:bottom, left:right]
    light = np.exp(-((sx - px) ** 2 + (sy - py) ** 2) / (2 * radius ** 2))
    tone = np.array([0.92, 0.94, 0.90]) if rng.random() < 0.25 else np.array([0.80, 0.88, 1.0])
    rgb[top:bottom, left:right] += light[..., None] * tone * brightness


for _ in range(1750):
    star(rng.uniform(0, WIDTH), rng.uniform(0, HEIGHT), rng.uniform(0.32, 0.62), rng.uniform(24, 102))
for _ in range(2700):
    px = rng.uniform(0, WIDTH)
    py = HEIGHT / 2 - (px - WIDTH / 2) * 0.57 + HEIGHT * (0.04 + rng.normal(0, 0.08))
    if 0 <= py < HEIGHT:
        star(px, py, rng.uniform(0.24, 0.42), rng.uniform(12, 42))
for _ in range(45):
    star(rng.uniform(0, WIDTH), rng.uniform(0, HEIGHT), rng.uniform(0.65, 1.0), rng.uniform(110, 190))

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
Image.fromarray(np.uint8(np.clip(rgb, 0, 255))).save(OUTPUT, optimize=True)
print(f"{OUTPUT}: {WIDTH} x {HEIGHT}, {OUTPUT.stat().st_size} bytes")
