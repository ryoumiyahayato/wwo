"""Place reconstructed buildings along mapped roads inside 1900 built-up areas."""

import argparse
import math
import struct
from collections import defaultdict
from pathlib import Path

import shapely
from shapely.geometry import Point, box, shape
from zstandard import ZstdCompressor

from build_city_models import PARIS_CENTER, RECORD, TILE, clean, features, read, rectangle, transform, transforms
from build_paris_city_ground import STREETS_GROUP
from build_city_water import METRES, encode, pack_road_cells

RADIUS = 16_000.
ROAD_CELL = 160


def variations(road, index, side):
    seed = (road * 3761 + index * 8191 + side * 9649) % 65521
    return ((seed * factor) % 65521 / 65521 for factor in (941, 1571, 3571, 7907))


def placements(sources):
    reference = sources / "paris_reference"
    ptm = sources / "paris_1900_ptm"
    forward, backward = transforms(PARIS_CENTER)
    region = Point(0, 0).buffer(RADIUS)
    land = reference / "ile-de-france-land-cover-1900.geojson"
    urban = clean(transform(features(land, lambda row: str(row["codzon"]) == "3"), forward))
    built = shapely.union_all([poly for poly in urban if region.intersects(poly)])
    boundary = built.boundary
    open_land = clean(transform(features(land, lambda row: str(row["codzon"]) != "3"), forward))
    water = clean(transform([shape(read(reference / "water.geojson")["geometry"])], forward))
    # Keep the entire existing street and block survey, including its open courtyards.
    central_survey = transform(box(*STREETS_GROUP), forward).buffer(8)
    versailles = Point(*forward.transform(2.1203, 48.8049)).buffer(690)
    roads = read(reference / "ile-de-france-routes-1900.geojson")["features"]
    road_shapes = transform(features(reference / "ile-de-france-routes-1900.geojson"), forward)
    outside = [poly for poly in [*open_land, *water] if region.intersects(poly)]
    streets = transform(features(ptm / "PTM_Paris1900_rues_epsg4326.geojson"), forward)
    guards = shapely.STRtree(shapely.get_parts(clean([
        *outside, central_survey, versailles,
        *shapely.buffer([line for line in road_shapes if region.intersects(line)], 4.5),
        *shapely.buffer(streets, 3.),
    ])))
    shapely.prepare(built)
    cells = defaultdict(list)
    roads = sorted(zip((row for row in roads if row["geometry"]), road_shapes, strict=True),
                   key=lambda road: int(road[0]["properties"]["objectid"]))
    for row, geometry in roads:
        if not geometry.intersects(region) or not geometry.intersects(built):
            continue
        road = int(row["properties"]["objectid"])
        for part, line in enumerate(shapely.get_parts(geometry)):
            if line.geom_type != "LineString" or line.length < 22:
                continue
            for i in range(math.floor((line.length - 8.) / 19.)):
                position = 8. + 19. * i
                point = line.interpolate(position)
                if not region.covers(point) or not built.covers(point):
                    continue
                before, after = line.interpolate(position - 4.), line.interpolate(position + 4.)
                angle = math.atan2(after.y - before.y, after.x - before.x)
                nx, ny = -math.sin(angle), math.cos(angle)
                for side in (-1, 1):
                    choice, form, setback, stature = variations(road, part * 193 + i, side)
                    for depth_limit, setback_base, density in [(0., 11., .92), (52., 34., .48)]:
                        x, y = point.x + nx * side * (setback_base + 4. * setback), point.y + ny * side * (setback_base + 4. * setback)
                        center = Point(x, y)
                        if not built.covers(center) or central_survey.covers(center):
                            continue
                        depth = boundary.distance(center)
                        survey_edge = min(1., max(0., (RADIUS - math.hypot(x, y)) / 1200.))
                        if depth < depth_limit or choice > density * min(1., .45 + depth / 44.) * survey_edge:
                            continue
                        width, length = 6. + form * 6., 6. + setback * 4.
                        plan = rectangle(x, y, angle, width, length)
                        if not built.covers(plan) or len(guards.query(plan, predicate="intersects")):
                            continue
                        cell = math.floor(x / 24.), math.floor(y / 24.)
                        if any(plan.distance(other) < 1.5 for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                               for other in cells.get((cell[0] + dx, cell[1] + dy), ())):
                            continue
                        cells[cell].append(plan)
                        lon, lat = backward.transform(x, y)
                        height = 5.5 + stature * 4. + min(2., depth / 65.)
                        yield x, y, lon, lat, angle, width, length, height, 3 if form < .55 else 4


def build(sources, output):
    pages = defaultdict(list)
    for x, y, *row in placements(sources):
        pages[math.floor(x / TILE), math.floor(y / TILE)].append(row)
    compressor = ZstdCompressor(level=12)
    pack = bytearray(b"WWOFRNG1" + struct.pack("<I", len(pages)))
    for _, rows in sorted(pages.items()):
        points = [(round(lon * 1e6), round(lat * 1e6)) for lon, lat, *_ in rows]
        xs, ys = zip(*points, strict=True)
        body = bytearray()
        for (_, _, angle, width, length, height, module), (lon, lat) in zip(rows, points, strict=True):
            heading = (math.degrees(angle) + 180.) % 360. - 180.
            body += RECORD.pack(lon, lat, round(heading * 100), round(width * 10),
                                round(length * 10), round(height * 10), module, 0)
        payload = b"WWOWCB01" + struct.pack("<I", len(rows)) + compressor.compress(body)
        pack += struct.pack("<4iII", min(xs), min(ys), max(xs), max(ys), len(rows), len(payload)) + payload
    output.write_bytes(pack)
    print(f"Paris fringe: {sum(map(len, pages.values())):,} placements in {len(pages)} pages, {len(pack):,} bytes")


def write_roads(sources, output):
    lon, lat = PARIS_CENTER
    east = METRES * math.cos(math.radians(lat))
    project = lambda x, y: ((x - lon) * east, (y - lat) * METRES)
    region = Point(0, 0).buffer(RADIUS)
    core = shapely.transform(box(*STREETS_GROUP), project, interleaved=False)
    limits = region.difference(core.buffer(20.))
    reference = sources / "paris_reference"
    land = reference / "ile-de-france-land-cover-1900.geojson"
    urban = shapely.transform(features(land, lambda row: str(row["codzon"]) == "3"), project, interleaved=False)
    built = shapely.union_all([poly for poly in clean(urban) if region.intersects(poly)])

    def road_sections():
        for row in read(reference / "ile-de-france-routes-1900.geojson")["features"]:
            if not row["geometry"]:
                continue
            road = shapely.transform(shape(row["geometry"]), project, interleaved=False)
            if not limits.intersects(road):
                continue
            # Surveyed centrelines have display widths. Water crossings keep the map's existing bridges.
            road = road.intersection(limits)
            for geometry, radius, surface in [(road.intersection(built), 3.5, 1), (road.difference(built), 2.4, 0)]:
                lines = [part.simplify(1.2) for part in shapely.get_parts(geometry) if part.geom_type == "LineString"]
                if lines:
                    yield row["properties"]["objectid"], lines, radius, surface, False

    values = [lon, lat, east, METRES, -RADIUS, -RADIUS, RADIUS, RADIUS]
    words = [*(encode(value, "f") for value in values), ROAD_CELL]
    pack_road_cells(words, values, road_sections(), ROAD_CELL)
    payload = struct.pack(f"<{len(words)}I", *words)
    output.write_bytes(ZstdCompressor(level=12).compress(payload))


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("sources", type=Path)
    cli.add_argument("output", type=Path)
    cli.add_argument("road_output", type=Path)
    args = cli.parse_args()
    build(args.sources, args.output)
    write_roads(args.sources, args.road_output)
