"""Pack surveyed London footprints and reconstructed Paris building placements."""

import argparse
import json
import math
import sqlite3
import struct
from collections import defaultdict
from pathlib import Path

import numpy as np
import shapely
from pyproj import CRS, Transformer
from shapely import LineString, Polygon, STRtree
from shapely.geometry import shape
from shapely.ops import polygonize
from zstandard import ZstdCompressor

from build_london_city_ground import GROUP, buildings

TILE = 1024
RECORD = struct.Struct("<iihHHHBB")
LONDON_CENTER = (-0.125, 51.505)
PARIS_CENTER = (2.35, 48.855)
LONDON_PARKS = {
    "Kensington Gardens", "Greenwich Park", "Hyde Park", "Battersea Park", "The Green Park",
    "Clapham Common", "The Regent's Park", "Victoria Park", "Hampstead Heath",
}


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def transforms(center):
    lon, lat = center
    local = CRS.from_proj4(f"+proj=aeqd +lat_0={lat} +lon_0={lon} +ellps=WGS84 +units=m")
    return (Transformer.from_crs(4326, local, always_xy=True),
            Transformer.from_crs(local, 4326, always_xy=True))


def transform(geometries, crs):
    return shapely.transform(geometries, crs.transform, interleaved=False)


def features(path, accept=lambda _: True):
    return [shape(row["geometry"]) for row in read(path)["features"]
            if row["geometry"] and accept(row["properties"])]


def london_parks(path):
    elements = read(path)["elements"]
    nodes = {row["id"]: (row["lon"], row["lat"]) for row in elements if row["type"] == "node"}
    ways = {row["id"]: row for row in elements if row["type"] == "way"}

    def line(way):
        return LineString([nodes[node] for node in way["nodes"]])

    result = []
    for row in elements:
        if row.get("tags", {}).get("name") not in LONDON_PARKS:
            continue
        if row["type"] == "way":
            ring = line(row)
            if ring.is_ring:
                result.append(Polygon(ring))
        elif row["type"] == "relation":
            rings = [line(ways[member["ref"]]) for member in row["members"]
                     if member["type"] == "way" and member["role"] == "outer"]
            result.extend(polygonize(rings))
    return result


def london_streets(path):
    widths = {"trunk": 5., "primary": 4., "secondary": 3.5, "tertiary": 2.5,
              "residential": 1.8, "living_street": 1.8, "unclassified": 1.8, "service": 1.4}
    for row in read(path)["elements"]:
        tags = row.get("tags", {})
        width = widths.get(tags.get("highway"))
        points = row.get("geometry", [])
        start = str(tags.get("start_date", "")).split("-")[0]
        end = str(tags.get("end_date", "")).split("-")[0]
        if (width is None or len(points) < 2 or not start.isdecimal()
                or int(start) > 1900 or end.isdecimal() and int(end) <= 1900):
            continue
        yield LineString([(p["lon"], p["lat"]) for p in points]), width


def rectangle(x, y, angle, width, depth):
    east = np.array([math.cos(angle), math.sin(angle)]) * width / 2
    north = np.array([-math.sin(angle), math.cos(angle)]) * depth / 2
    center = np.array([x, y])
    return Polygon([center-east-north, center+east-north, center+east+north, center-east+north])


def orientation(row):
    a, b, c = np.asarray(row.exterior.coords)[:3]
    long_axis, short_axis = sorted((b-a, c-b), key=np.linalg.norm, reverse=True)
    return math.atan2(long_axis[1], long_axis[0]), np.linalg.norm(long_axis), np.linalg.norm(short_axis)


def clean(rows):
    rows = np.asarray(rows, dtype=object)
    rows = rows[~shapely.is_missing(rows) & ~shapely.is_empty(rows)]
    invalid = ~shapely.is_valid(rows)
    rows[invalid] = shapely.make_valid(rows[invalid])
    return rows


def exclusions(rows):
    return STRtree(clean(rows))


def clear_of(tree, footprint):
    return not len(tree.query(footprint, predicate="intersects"))


def london(sources):
    folder = sources / "london_1890s"
    forward, backward = transforms(LONDON_CENTER)
    water = shape(read(folder / "thames-presentation-union.geojson")["geometry"])
    roads = london_streets(folder / "ohm-dated-roads.json")
    excluded = list(transform([water, *london_parks(folder / "parks-boundaries.json")], forward))
    excluded += [transform(line, forward).buffer(width) for line, width in roads]
    excluded += [shapely.Point(*forward.transform(-0.12463, 51.50077)).buffer(13.)]
    blocked = exclusions(excluded)
    mercator = Transformer.from_crs(4326, 3857, always_xy=True)
    project = Transformer.from_crs(3857, forward.target_crs, always_xy=True)
    source = folder / "london_buildings_1891-96_corr_v1.gpkg"
    west, south, east, north = GROUP
    with sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True) as database:
        for column in range(12):
            left = west + (east-west)*column/12
            right = west + (east-west)*(column+1)/12
            extent = mercator.transform_bounds(left, south, right, north)
            rows = clean(transform(buildings(database, extent), project))
            area = shapely.area(rows)
            rows = rows[(area >= 10.) & (area <= 25_000.)]
            centers = shapely.get_x(shapely.centroid(rows))
            rows = rows[(centers >= project.transform(extent[0], extent[1])[0] - 40.)
                        & (centers < project.transform(extent[2], extent[1])[0] + 40.)]
            for row, envelope in zip(rows, shapely.minimum_rotated_rectangle(rows)):
                if envelope.geom_type != "Polygon":
                    continue
                center = envelope.centroid
                lon, lat = backward.transform(center.x, center.y)
                if not left <= lon < right or not south <= lat <= north:
                    continue
                angle, width, depth = orientation(envelope)
                if depth < 2.8 or width < 4.0:
                    continue
                # Keep the model inside the recorded walls, including corners and courtyards.
                for scale in (0.93, 0.75, 0.55, 0.38):
                    w, d = width*scale, depth*scale
                    if d < 2.6:
                        break
                    plan = rectangle(center.x, center.y, angle, w, d)
                    if row.covers(plan) and clear_of(blocked, plan):
                        height = 6.0 + min(9., depth*0.38)
                        module = 1 if width/depth < 1.55 else 2
                        yield center.x, center.y, lon, lat, angle, w, d, height, module
                        break
            print(f"London sector {column+1}/12", flush=True)


def paris(sources):
    folder = sources / "paris_1900_ptm"
    reference = sources / "paris_reference"
    forward, backward = transforms(PARIS_CENTER)
    blocks = features(folder / "PTM_Paris1900_ilots_epsg4326.geojson",
                      lambda p: p.get("Bati_nonBati") == "Bâti")
    roads = features(folder / "PTM_Paris1900_rues_epsg4326.geojson")
    water = shape(read(reference / "water.geojson")["geometry"])
    unbuilt = features(reference / "ile-de-france-land-cover-1900.geojson",
                       lambda p: p.get("codzon") in ("1", "2", "4"))
    guard = [shapely.Point(*forward.transform(*point)).buffer(size) for point, size in [
        ((2.2945, 48.8583), 83.), ((2.3553, 48.8809), 110.),
    ]]
    excluded = [*shapely.get_parts(transform(water, forward)), *guard]
    excluded.extend(shapely.buffer(transform(roads, forward), 2.4))
    for area in transform(unbuilt, forward):
        excluded.extend(shapely.get_parts(area))
    blocked = exclusions(excluded)
    for row in clean(transform(blocks, forward)):
        for block in shapely.get_parts(row):
            if block.geom_type != "Polygon" or block.area < 90.:
                continue
            envelope = block.minimum_rotated_rectangle
            angle, width, depth = orientation(envelope)
            fill = block.buffer(-2.6)
            if fill.is_empty:
                continue
            shapely.prepare(fill)
            edge = block.boundary
            center = envelope.centroid
            across = max(1, round(width/12.))
            along = max(1, round(depth/12.))
            dx, dy = width/across, depth/along
            cos, sin = math.cos(angle), math.sin(angle)
            cx, cy = center.x, center.y
            for col in range(across):
                u = (col+0.5)*dx-width/2
                v = (np.arange(along)+0.5)*dy-depth/2
                xx, yy = cx+cos*u-sin*v, cy+sin*u+cos*v
                distances = shapely.distance(edge, shapely.points(xx, yy))
                for index in np.flatnonzero(distances <= 34.):
                    x, y = xx[index], yy[index]
                    w, d = min(17.,dx*.95), min(17.,dy*.96)
                    for scale in (1., .78, .57):
                        plan = rectangle(x, y, angle, w*scale, d*scale)
                        if fill.covers(plan) and clear_of(blocked, plan):
                            lon, lat = backward.transform(x,y)
                            height = 11. + (col*5+index*3) % 7
                            yield x, y, lon, lat, angle, w*scale, d*scale, height, 3 if (col+index)%7==0 else 4
                            break


def pack(output, key, source, attribution, rows):
    tiles = defaultdict(list)
    for x, y, lon, lat, angle, width, depth, height, module in rows:
        tiles[math.floor(x/TILE),math.floor(y/TILE)].append((lon,lat,angle,width,depth,height,module))
    compressor = ZstdCompressor(level=5)
    entries = []
    for (x, y), records in sorted(tiles.items()):
        name = f"{key}-{x}-{y}.wcb"
        bounds = [min(r[0] for r in records), min(r[1] for r in records),
                  max(r[0] for r in records), max(r[1] for r in records)]
        payload = bytearray()
        for lon, lat, angle, width, depth, height, module in records:
            heading = (math.degrees(angle)+180.)%360.-180.
            payload += RECORD.pack(round(lon*1e6), round(lat*1e6), round(heading*100),
                                   round(width*10), round(depth*10), round(height*10), module, 0)
        (output/name).write_bytes(b"WWOWCB01" + struct.pack("<I", len(records)) + compressor.compress(payload))
        entries.append(dict(file=name, bounds=bounds, buildings=len(records)))
    print(f"{key}: {sum(len(r) for r in tiles.values()):,} building placements in {len(tiles)} tiles", flush=True)
    return dict(name=key.title(), source=source, attribution=attribution, tiles=entries)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("sources", type=Path)
    cli.add_argument("output", type=Path)
    cli.add_argument("--city", choices=("london", "paris"), help="Update one city in the output catalogue")
    args = cli.parse_args()
    args.output.mkdir(parents=True, exist_ok=args.city is not None)
    catalog = args.output/"catalogue.json"
    cities = read(catalog)["cities"] if catalog.is_file() else []
    if args.city in (None, "london"):
        cities = [city for city in cities if city["name"] != "London"]
        cities.append(pack(args.output, "london", "Surveyed 1891–1896 footprints. Roof form and height reconstructed.",
             "Petitpierre et al., https://doi.org/10.5281/zenodo.19497435 (CC BY 4.0). "
             "OpenHistoricalMap dated centerlines and OpenStreetMap park outlines (ODbL).",
             london(args.sources)))
    if args.city in (None, "paris"):
        cities = [city for city in cities if city["name"] != "Paris"]
        cities.append(pack(args.output, "paris", "Paris 1900 reconstructed streets and blocks. Individual buildings simulated.",
             "Paris Time Machine, https://doi.org/10.34847/nkl.cbf5ecd0 (ODbL 1.0). "
             "Institut Paris Region, land use c. 1900 (Licence Ouverte).",
             paris(args.sources)))
    pending = catalog.with_suffix(".tmp")
    pending.write_text(
        json.dumps(dict(version="wwo-city-models-v1", cities=cities), ensure_ascii=False, indent=2),
        encoding="utf-8")
    pending.replace(catalog)
