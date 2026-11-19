"""Pack the existing ESA WorldCover 2021 v200 class cache for Z6 and Z7."""

import argparse
from functools import lru_cache
from os import link
from pathlib import Path
from struct import pack
from tempfile import TemporaryDirectory

import numpy as np
from PIL import Image
from zstandard import ZstdCompressor


WIDTH, HEIGHT = 256, 128
CORE, GUTTER, SOURCE = 256, 4, 562
PAGE = CORE + 2 * GUTTER


def build(source, output):
    prefix = "v200/2021/map/ESA_WorldCover_10m_2021_v200_"
    tiles = {}
    for name in (source / "keys.txt").read_text().splitlines():
        if not name.startswith(prefix) or not name.endswith("_Map.tif"):
            raise ValueError(f"Expected WorldCover 2021 v200, got {name}")
        key = name.removeprefix(prefix).removesuffix("_Map.tif")
        lat = int(key[1:3]) * (-1 if key[0] == "S" else 1)
        lon = int(key[4:]) * (-1 if key[3] == "W" else 1)
        tiles[(87 - lat) // 3, (lon + 180) // 3] = source / f"{key}.png"

    classes = np.zeros(256, dtype=np.uint8)
    codes = (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100)
    classes[list(codes)] = np.arange(len(codes), dtype=np.uint8)

    @lru_cache(maxsize=256)
    def load(path):
        with Image.open(path) as image:
            samples = np.asarray(image)
            if samples.shape != (SOURCE, SOURCE):
                raise ValueError(f"Unexpected WorldCover cache tile shape in {path}")
            return classes[samples]

    def slices(page, pages, count, wrap):
        indices = (2 * (page * CORE + np.arange(-GUTTER, CORE + GUTTER)) + 1) * (count * SOURCE)
        indices //= 2 * pages * CORE
        indices = indices % (count * SOURCE) if wrap else indices.clip(0, count * SOURCE - 1)
        groups = indices // SOURCE
        return [(int(group), np.flatnonzero(groups == group), indices[groups == group] % SOURCE)
                for group in np.unique(groups)]

    compressor = ZstdCompressor(level=4)
    header = pack("<8sIII", b"WWOZ7LC2", WIDTH, HEIGHT, PAGE)
    levels = ((WIDTH//2, HEIGHT//2), (WIDTH, HEIGHT))
    count = sum(width*height for width, height in levels)
    offsets = []
    with output.open("xb") as stream:
        stream.write(header)
        stream.seek(8 * (count + 1), 1)
        for width, height in levels:
            columns = [slices(x, width, 120, True) for x in range(width)]
            for y in range(height):
                rows = slices(y, height, 60, False)
                for cols in columns:
                    offsets.append(stream.tell())
                    data = np.zeros((PAGE, PAGE), dtype=np.uint8)
                    for row, yy, ry in rows:
                        for col, xx, rx in cols:
                            if path := tiles.get((row, col)):
                                data[np.ix_(yy, xx)] = load(path)[np.ix_(ry, rx)]
                    if data.any():
                        stream.write(compressor.compress(data.tobytes()))
        offsets.append(stream.tell())
        stream.seek(len(header))
        stream.write(pack(f"<{len(offsets)}Q", *offsets))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worldcover_cache", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.output.exists():
        parser.error(f"Output already exists: {args.output}")
    with TemporaryDirectory(dir=args.output.parent, prefix="landscape-cover-") as temp:
        candidate = Path(temp) / args.output.name
        build(args.worldcover_cache, candidate)
        link(candidate, args.output)
