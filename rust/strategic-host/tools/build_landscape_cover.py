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
CLASSES = (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100)
LAND_GROUPS = ((1, 10), (2,), (3,), (4,), (5,), (6,), (7,), (9, 11), (8,))


def worldcover(source):
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
    classes[list(CLASSES)] = np.arange(len(CLASSES), dtype=np.uint8)

    @lru_cache(maxsize=256)
    def load(path, samples_per_tile=SOURCE):
        with Image.open(path) as image:
            samples = np.asarray(image)
            if samples.shape != (samples_per_tile, samples_per_tile):
                raise ValueError(f"Unexpected WorldCover cache tile shape in {path}")
            return classes[samples]

    return tiles, load


def build(source, output):
    tiles, load = worldcover(source)

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


def aggregate(data, edges, axis):
    """Integrate the source cells over each destination cell, including partial pixels."""
    values = np.moveaxis(data, axis, 0)
    integral = np.concatenate((np.zeros_like(values[:1]), np.cumsum(values, axis=0)))
    left = edges.astype(np.int32)
    at_edge = integral[left] + (edges - left)[:, None] * values[left.clip(max=len(values) - 1)]
    result = np.diff(at_edge, axis=0) / np.diff(edges)[:, None]
    return np.moveaxis(result.astype(np.float32), 0, axis)


def cover_fractions(data, xe, ye):
    # Unknown source leaves the sum of observed fractions below one.
    return np.stack([aggregate(aggregate(np.isin(data, codes).astype(np.float32),
                                        xe, 1), ye, 0)
                     for codes in LAND_GROUPS], axis=2)


def regional_source(tiles, load, rows, cols, fine):
    span = (WIDTH // 2) * CORE * 4
    xe = cols * (120 * SOURCE / span)
    ye = rows * (60 * SOURCE / (span // 2))
    x0, x1 = int(np.floor(xe[0])), int(np.ceil(xe[-1]))
    y0, y1 = int(np.floor(ye[0])), int(np.ceil(ye[-1]))
    data = np.zeros((y1 - y0, x1 - x0), dtype=np.uint8)
    for y in range(y0 // SOURCE, (y1 - 1) // SOURCE + 1):
        for x in range(x0 // SOURCE, (x1 - 1) // SOURCE + 1):
            path = tiles.get((y, x % 120))
            if not path or not path.is_file():
                continue
            a, b = max(x0, x * SOURCE), min(x1, (x + 1) * SOURCE)
            c, d = max(y0, y * SOURCE), min(y1, (y + 1) * SOURCE)
            data[c - y0:d - y0, a - x0:b - x0] = load(path)[
                c - y * SOURCE:d - y * SOURCE, a - x * SOURCE:b - x * SOURCE]
    fractions = cover_fractions(data, xe - x0, ye - y0)
    for y in range(y0 // SOURCE, (y1 - 1) // SOURCE + 1):
        for x in range(x0 // SOURCE, (x1 - 1) // SOURCE + 1):
            path = fine.get((y, x % 120))
            if path:
                refine_source(fractions, load, fine, path, y, x, xe, ye)
    return fractions


def refine_source(fractions, load, fine, path, y, x, xe, ye):
    # Integrate the 16x COG overview of only the available regional tiles.
    # Exact partial footprints make neighbouring source tiles composable.
    width = 2250
    slices, inputs, footprints, confidence = [], [], [], []
    for edges, coord, neighbours in ((xe, x, ((y, (x-1) % 120), (y, (x+1) % 120))),
                                     (ye, y, ((y-1, x % 120), (y+1, x % 120)))):
        i = max(0, edges.searchsorted(coord * SOURCE, side="right") - 1)
        j = min(len(edges) - 1, edges.searchsorted((coord+1) * SOURCE, side="left"))
        edges = edges[i:j+1] - coord * SOURCE
        clipped = edges.clip(0, SOURCE)
        centres = (clipped[1:] + clipped[:-1]) * .5
        feather = np.ones(j-i)
        for neighbour, gap in zip(neighbours, (centres, SOURCE-centres)):
            if neighbour not in fine:
                t = (gap / 14).clip(0, 1)
                feather *= t*t*(3.-2.*t)
        slices.append(slice(i, j))
        inputs.append(clipped)
        footprints.append(np.diff(clipped) / np.diff(edges))
        confidence.append(feather)
    (xe, ye) = inputs
    scale = width / SOURCE
    sharp = load(path, width)
    coarse = load(path.with_name(path.name.replace("-overview", "")))
    # Apply only each source tile's weighted difference from the global
    # cache, so a partially covered sample retains its original remainder.
    high = cover_fractions(sharp, xe*scale, ye*scale)
    low = cover_fractions(coarse, xe, ye)
    mix_x = confidence[0]*footprints[0]
    mix_y = confidence[1]*footprints[1]
    fractions[slices[1], slices[0]] += (high-low) * (mix_y[:, None]*mix_x[None, :])[:, :, None]


def reconstruct(fractions):
    """Round sampling steps via conservative exchange along adjacent land cells."""
    mobile = [0, 1, 2, 3, 5, 6, 7]
    land = fractions[:, :, mobile]
    capacity = land.sum(axis=2)
    barrier = (fractions[:, :, 4] + fractions[:, :, 8]).clip(0, 1)
    # Retaining the input share anchors even single-cell copses. Water, built
    # land and unknown area never acquire terrestrial coverage from a neighbour.
    for _ in range(4):
        delta = np.zeros_like(land)
        mix = land / np.maximum(capacity[:, :, None], 1e-6)
        for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
            a = (slice(None, -1) if dy else slice(None),
                 slice(None, -1) if dx > 0 else slice(1, None) if dx < 0 else slice(None))
            b = (slice(1, None) if dy else slice(None),
                 slice(1, None) if dx > 0 else slice(None, -1) if dx < 0 else slice(None))
            edge = (1. - np.maximum(barrier[a], barrier[b])) ** 2
            flow = np.minimum(capacity[a], capacity[b]) * edge * (.048 if dy and dx else .078)
            exchange = (mix[b] - mix[a]) * flow[:, :, None]
            delta[a] += exchange
            delta[b] -= exchange
        land += delta
    fractions[:, :, mobile] = fractions[:, :, mobile] * .40 + land * .60
    round_woodland(fractions, inside=True)
    round_woodland(fractions, inside=False)
    return fractions


def round_woodland(fractions, inside):
    """Resolve isolated woods and clearings without fusing neighbouring components."""
    from scipy.ndimage import distance_transform_edt, find_objects, gaussian_filter, label

    open_land = [1, 2, 3, 7]  # shrub, grass, crop and damp ground
    forest = fractions[:, :, 0]
    available = forest + fractions[:, :, open_land].sum(axis=2)
    occupancy = forest / np.maximum(available, 1e-6)
    if not inside:
        occupancy = 1. - occupancy
    known = available >= .5
    core = (occupancy > .50) & known
    if not core.any():
        return
    labels, count = label(core, structure=np.ones((3, 3), dtype=np.uint8))
    sizes = np.bincount(labels.ravel(), minlength=count + 1)
    distance, nearest = distance_transform_edt(~core, return_indices=True)
    owner = labels[tuple(nearest)]
    # Normalized filtering keeps coast, urban surfaces and missing source out
    # of the guide. The area-preserving threshold has a narrow contour ramp.
    weight = gaussian_filter(available, 1.25)
    guide = gaussian_filter(occupancy * available, 1.25) / np.maximum(weight, 1e-6)
    for i, bounds in enumerate(find_objects(labels), start=1):
        if sizes[i] > 64:
            continue
        window = tuple(slice(max(0, s.start - 4), min(n, s.stop + 4))
                       for s, n in zip(bounds, core.shape))
        valid = (owner[window] == i) & (distance[window] <= 2.65) & known[window]
        if not valid.any():
            continue
        capacity = available[window][valid]
        ink = guide[window][valid]
        previous = forest[window][valid]
        area = (previous if inside else capacity - previous).sum(dtype=np.float64)
        low, high = -.13, 1.13
        for _ in range(17):
            cut = (low + high) * .5
            shape = ((ink - cut) / .24 + .5).clip(0, 1) * capacity
            if shape.sum(dtype=np.float64) > area:
                low = cut
            else:
                high = cut
        if not inside:
            shape = capacity - shape
        change = (shape - previous) * .76
        # Transfer the existing open classes back to the cells vacated by
        # forest, retaining their area as well as the component's wooded area.
        gain = change.clip(min=0)
        loss = (-change).clip(min=0)
        if min(gain.sum(), loss.sum()) <= .0001:
            continue
        cells = fractions[window][valid]
        outgoing = cells[:, open_land] * (gain / np.maximum(capacity - previous, 1e-6))[:, None]
        incoming = (loss / loss.sum())[:, None] * outgoing.sum(axis=0)
        cells[:, open_land] += incoming - outgoing
        cells[:, 0] = previous + outgoing.sum(axis=1) - incoming.sum(axis=1)
        fractions[window][valid] = cells


def pilot_pages():
    # Parent windows cover southern Britain, central France, the Jura and Alps.
    return {(x, y) for left, top, right, bottom in ((62, 12, 65, 14),
                                                    (63, 14, 66, 16),
                                                    (65, 15, 68, 16))
            for y in range(top, bottom) for x in range(left, right)}


def regional_build(source, output, parents, use_overviews):
    from scipy.ndimage import distance_transform_edt

    tiles, load = worldcover(source)
    overviews = {key: path.with_name(path.stem + "-overview.png") for key, path in tiles.items()}
    fine = {key: path for key, path in overviews.items() if use_overviews and path.is_file()}
    compressor = ZstdCompressor(level=12)
    records = []
    span = CORE * 4
    feather = 64
    halo = feather + GUTTER * 4 + 8
    channels = 10
    for x, y in sorted(parents):
        xx = np.arange(x * span - halo, (x + 1) * span + halo + 1)
        yy = np.arange(y * span - halo, (y + 1) * span + halo + 1)
        fractions = reconstruct(regional_source(tiles, load, yy, xx, fine))
        area = np.zeros(fractions.shape[:2], dtype=bool)
        for px, py in parents:
            area |= ((yy[:-1] // span == py)[:, None] & (xx[:-1] // span == px)[None, :])
        support = (distance_transform_edt(area) / feather).clip(0, 1).astype(np.float32)
        fractions = np.concatenate((fractions, support[:, :, None]), axis=2)
        for z, sx, sy in [(6, x, y)] + [(7, 2*x+dx, 2*y+dy) for dy in range(2) for dx in range(2)]:
            step = 4 if z == 6 else 2
            i = halo + (sx * CORE * step - x * span) - GUTTER * step
            j = halo + (sy * CORE * step - y * span) - GUTTER * step
            crop = fractions[j:j+PAGE*step, i:i+PAGE*step]
            page = crop.reshape(PAGE, step, PAGE, step, channels).mean(axis=(1, 3))
            # Cumulative rounding preserves the known sum to one byte and never
            # spends a fraction on a class with genuinely zero source coverage.
            cumulative = np.rint(page[:, :, :9].cumsum(axis=2).clip(0, 1) * 255).astype(np.uint8)
            coverage = np.diff(cumulative, axis=2, prepend=np.zeros_like(cumulative[:, :, :1]))
            support = np.rint(page[:, :, 9] * 255).astype(np.uint8)
            # Preserve the reconstructed forest shape one octave below the
            # material cell. The four child samples also give its parent mean.
            child = step // 2
            forest = crop[:, :, 0].reshape(PAGE, 2, child, PAGE, 2, child).mean(axis=(2, 5))
            forest = np.rint(forest.transpose(0, 2, 1, 3).reshape(PAGE, PAGE, 4) * 255).astype(np.uint8)
            layers = np.dstack((forest, coverage[:, :, 1:8], support))
            banks = np.ascontiguousarray(layers.reshape(PAGE, PAGE, 3, 4).transpose(0, 2, 1, 3))
            # Store the GPU row order and keep the source water share at the end.
            payload = banks.tobytes() + coverage[:, :, 8].tobytes()
            records.append((z, sx, sy, compressor.compress(payload)))
    with output.open("xb") as stream:
        stream.write(pack("<8sII", b"WWOREGC3", PAGE, len(records)))
        for z, x, y, frame in records:
            stream.write(pack("<BBHI", z, x, y, len(frame)))
            stream.write(frame)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worldcover_cache", type=Path)
    parser.add_argument("output", type=Path)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--regional-pilot", action="store_true", help="Build the three landscape study regions")
    modes.add_argument("--regional-parent", action="append", metavar="X/Y",
                       help="Build selected Z6 parents and their Z7 children")
    parser.add_argument("--regional-overviews", action="store_true",
                        help="Use locally cached <tile>-overview.png WorldCover COG overviews")
    args = parser.parse_args()
    if args.output.exists():
        parser.error(f"Output already exists: {args.output}")
    with TemporaryDirectory(dir=args.output.parent, prefix="landscape-cover-") as temp:
        candidate = Path(temp) / args.output.name
        if args.regional_pilot or args.regional_parent:
            parents = pilot_pages() if args.regional_pilot else {
                tuple(map(int, page.split("/"))) for page in args.regional_parent}
            if any(not 0 <= x < WIDTH // 2 or not 0 <= y < HEIGHT // 2 for x, y in parents):
                parser.error("Regional parents must be inside the Z6 grid")
            regional_build(args.worldcover_cache, candidate, parents, args.regional_overviews)
        else:
            build(args.worldcover_cache, candidate)
        link(candidate, args.output)
