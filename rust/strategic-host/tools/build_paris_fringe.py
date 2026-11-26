"""Place reconstructed buildings along mapped roads inside 1900 built-up areas."""

import argparse
import math
import struct
from collections import defaultdict
from pathlib import Path

import shapely
from shapely.geometry import Point, box, shape
from shapely.ops import substring
from zstandard import ZstdCompressor

from build_city_models import PARIS_CENTER, RECORD, TILE, clean, features, read, rectangle, transform, transforms
from build_paris_city_ground import GROUP, STREETS_GROUP
from build_city_water import METRES, encode, pack_road_levels

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


def route_ranks(lines):
    # IPR has no road class. Follow mutual straight continuations through
    # junctions to display routes by their reach, including through villages.
    endpoints = defaultdict(list)
    for index, line in enumerate(lines):
        points = list(line.coords)
        for side, start, next_point in [(0, points[0], points[1]), (1, points[-1], points[-2])]:
            length = math.dist(start, next_point)
            if length > .01:
                key = tuple(round(value / 3.) for value in start)
                direction = tuple((b - a) / length for a, b in zip(start, next_point))
                endpoints[key].append((index, side, direction))
    continuations = {}
    for group in endpoints.values():
        for index, side, tangent in group:
            best = -.78
            for other, other_side, direction in group:
                alignment = sum(a * b for a, b in zip(tangent, direction))
                if index != other and alignment < best:
                    best = alignment
                    continuations[index, side] = (other, other_side)
    ranks = [0] * len(lines)
    for index in range(len(lines)):
        if ranks[index]:
            continue
        route = {index}
        pending = [index]
        while pending:
            current = pending.pop()
            for side in (0, 1):
                end = (current, side)
                other = continuations.get(end)
                if other is not None and continuations.get(other) == end and other[0] not in route:
                    route.add(other[0])
                    pending.append(other[0])
        reach = sum(lines[i].length for i in route)
        rank = 3 if reach >= 5200. else 2 if reach >= 1500. else 1
        for i in route:
            ranks[i] = rank
    return ranks


def write_roads(sources, output):
    lon, lat = PARIS_CENTER
    east = METRES * math.cos(math.radians(lat))
    project = lambda x, y: ((x - lon) * east, (y - lat) * METRES)
    region = shapely.transform(box(*GROUP), project, interleaved=False)
    core = shapely.transform(box(*STREETS_GROUP), project, interleaved=False)
    limits = region.difference(core.buffer(20.))
    reference = sources / "paris_reference"
    land = reference / "ile-de-france-land-cover-1900.geojson"
    urban = shapely.transform(features(land, lambda row: str(row["codzon"]) == "3"), project, interleaved=False)
    built = shapely.union_all([poly for poly in clean(urban) if region.intersects(poly)])
    water = shapely.transform(features(land, lambda row: str(row["codzon"]) == "1"), project, interleaved=False)
    water_polygons = shapely.get_parts(clean(water))
    water_index = shapely.STRtree(water_polygons)

    source_lines = [part for row in read(reference / "ile-de-france-routes-1900.geojson")["features"]
                    if row["geometry"] for part in shapely.get_parts(shape(row["geometry"]))
                    if part.geom_type == "LineString" and not part.is_empty]
    projected = shapely.transform(source_lines, project, interleaved=False)

    def crossing_sections(road):
        # A source line continuing across two dry banks supports a visual
        # crossing over narrow water. Never join two separate road records.
        hits = water_index.query(road, predicate="intersects")
        if not len(hits):
            return
        wet = shapely.union_all(water_polygons[hits])
        for run in shapely.get_parts(road.intersection(wet)):
            if run.geom_type != "LineString" or not 3. <= run.length <= 48.:
                continue
            a, b = sorted(road.project(Point(p)) for p in [run.coords[0], run.coords[-1]])
            if a < 9. or b > road.length-9. or b-a > 50.:
                continue
            banks = [substring(road, a-9., a-.4), substring(road, b+.4, b+9.)]
            if any(wet.intersects(bank) for bank in banks):
                continue
            yield substring(road, a-2., b+2.)

    def road_sections():
        for index, (road, rank) in enumerate(zip(projected, route_ranks(projected), strict=True)):
            if not limits.intersects(road):
                continue
            road = road.intersection(limits)
            for geometry, radius, surface in [(road.intersection(built), 3.5, 1), (road.difference(built), 2.4, 0)]:
                lines = [part.simplify(1.2) for part in shapely.get_parts(geometry) if part.geom_type == "LineString"]
                if lines:
                    yield index, lines, radius, surface, False, rank
            bridges = [crossing for part in shapely.get_parts(road) if part.geom_type == "LineString"
                       for crossing in crossing_sections(part)]
            if bridges:
                yield index, bridges, 3.0, 1, True, max(rank, 2)

    # Keep the original 160 m cell lattice in the existing Paris outskirts.
    west, south, xmax, ymax = region.bounds
    values = [lon, lat, east, METRES, math.floor(west/ROAD_CELL)*ROAD_CELL,
              math.floor(south/ROAD_CELL)*ROAD_CELL, xmax, ymax]
    words = [*(encode(value, "f") for value in values), ROAD_CELL, 0, 0, 0]
    pack_road_levels(words, values, list(road_sections()), ROAD_CELL, range(9, 12))
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
