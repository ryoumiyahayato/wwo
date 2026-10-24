"""Make one repeatable printing grain. No geographic or land-cover content."""
from pathlib import Path
import random
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def main():
    rng = random.Random(1900)
    size = 128
    # Neutral micro-grain only. Wrapping samples provide a seamless tile.
    source = [rng.random() for _ in range(size * size)]
    pixels = []
    for y in range(size):
        for x in range(size):
            centre = source[y * size + x]
            neighbours = sum(source[((y + dy) % size) * size + (x + dx) % size]
                             for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))) / 4
            pixels.append(round(255 * (0.5 + (centre * 0.7 + neighbours * 0.3 - 0.5) * 0.65)))
    output = ROOT / 'assets/maps/materials/survey_grain.png'
    output.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new('L', (size, size))
    image.putdata(pixels)
    image.save(output, optimize=True)
    print(f'{output}: {output.stat().st_size} bytes; {size}x{size}; original WWO visual material')


if __name__ == '__main__':
    main()
