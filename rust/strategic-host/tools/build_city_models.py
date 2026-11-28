"""Pack established city models or generate cities from formal roster inputs."""

import argparse
import json
import math
import os
import re
import sqlite3
import struct
from collections import defaultdict
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory

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


def roster_city(city_id, roster=None):
    if roster is None:
        from city_landscape_roster import read_roster
        roster = read_roster()
    city = next((row for row in roster["candidates"] if row["city_id"] == city_id), None)
    if not city or not city.get("construction"):
        raise ValueError(f"City is outside the frozen construction roster: {city_id}")
    point = city.get("point")
    population = (city.get("selected_observation") or {}).get("population_value")
    if not point or len(point) != 2 or not (-180 <= point[0] <= 180 and -90 <= point[1] <= 90):
        raise ValueError(f"Missing WGS84 roster point for {city_id}")
    if type(population) is not int or population <= 0:
        raise ValueError(f"Missing roster population for {city_id}")
    return city


def roster_batch(batch, roster):
    if roster.get("status") != "frozen":
        raise ValueError("Batch generation requires the frozen construction roster")
    city_ids = [row["city_id"] for row in roster["candidates"] if row.get("batch") == batch]
    if not city_ids or len(city_ids) != len(set(city_ids)):
        raise ValueError(f"Frozen batch {batch} has missing or duplicate city IDs")
    return city_ids


def validate_batch_inputs(batch, city_ids, roster, transport_data):
    from build_procedural_city import official_inputs

    failures = []
    for city_id in city_ids:
        try:
            official_inputs(roster_city(city_id, roster), transport_data)
        except StopIteration:
            failures.append(f"{city_id}: Configured regional Kit was not found")
        except (ValueError, OSError, KeyError) as error:
            failures.append(f"{city_id}: {error}")
    if failures:
        details = "\n".join(failures)
        raise ValueError(f"Frozen batch {batch} has invalid or unbound procedural inputs for "
                         f"{len(failures)} of {len(city_ids)} cities. No output written.\n{details}")


class CityTerrain:
    def __init__(self, water, elevation):
        self.water = water
        self.relief = elevation

    def water_area(self, lon, lat):
        return self.water.area(lon, lat)

    def land_geometry(self, bounds):
        return self.water.land_geometry(bounds)

    def elevation(self, lon, lat):
        return self.relief.elevation(lon, lat)


@contextmanager
def open_city_terrain(terrain_root):
    from build_natural_terrain import PackedElevation, WaterGeometry, pack_path, PACK_MAX_LEVEL

    terrain_root = Path(terrain_root)
    with (terrain_root/"water-geometry.qwg").open("rb") as water, \
            pack_path(terrain_root, PACK_MAX_LEVEL).open("rb") as relief:
        yield CityTerrain(WaterGeometry(water), PackedElevation(relief))


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


def pack(output, key, source, attribution, rows, modern_format=False):
    tiles = defaultdict(list)
    tile_size = 512 if modern_format else TILE
    for x, y, lon, lat, angle, width, depth, height, module in rows:
        tiles[math.floor(x/tile_size),math.floor(y/tile_size)].append((lon,lat,angle,width,depth,height,module))
    compressor = ZstdCompressor(level=5)
    magic = b"WWOWCB02" if modern_format else b"WWOWCB01"
    entries = []

    def write_page(stem, records):
        name = f"{stem}.wcb"
        bounds = [min(r[0] for r in records), min(r[1] for r in records),
                  max(r[0] for r in records), max(r[1] for r in records)]
        payload = bytearray()
        for lon, lat, angle, width, depth, height, module in records:
            heading = (math.degrees(angle)+180.)%360.-180.
            payload += RECORD.pack(round(lon*1e6), round(lat*1e6), round(heading*100),
                                   round(width*10), round(depth*10), round(height*10), module, 0)
        (output/name).write_bytes(magic + struct.pack("<I", len(records)) + compressor.compress(payload))
        entries.append(dict(file=name, bounds=bounds, buildings=len(records)))

    for (x, y), records in sorted(tiles.items()):
        stem = f"{key}-{x}-{y}"
        # A local page spanning the seam must not be centered between ±180°.
        if modern_format and max(row[0] for row in records) - min(row[0] for row in records) > 180:
            write_page(f"{stem}-west", [row for row in records if row[0] < 0])
            write_page(f"{stem}-east", [row for row in records if row[0] >= 0])
        else:
            write_page(stem, records)
    print(f"{key}: {sum(entry['buildings'] for entry in entries):,} building placements in {len(entries)} tiles", flush=True)
    return dict(name=key.title(), source=source, attribution=attribution, tiles=entries)


def plan_bounds(layout):
    # Unwrap about the city center. A wrapped result has west greater than east.
    origin = layout["wwo"]["origin"][0]
    west = south = math.inf
    east = north = -math.inf
    metres_per_degree = math.radians(1) * 6_371_008.8
    for feature in layout["features"]:
        properties = feature["properties"]
        if properties["kind"] not in {"road", "block"}:
            continue
        x, y = shapely.get_coordinates(shape(feature["geometry"])).T
        lon = (x - origin + 180) % 360 - 180
        low, high = float(y.min()), float(y.max())
        half_width = properties.get("width_m", 0) / 2
        lat_pad = half_width / metres_per_degree
        lon_pad = lat_pad / math.cos(math.radians(max(abs(low), abs(high))))
        west, east = min(west, float(lon.min()) - lon_pad), max(east, float(lon.max()) + lon_pad)
        south, north = min(south, low - lat_pad), max(north, high + lat_pad)
    if west == math.inf:
        return None
    south, north = max(-90., south), min(90., north)
    if east - west >= 360:
        return [-180., south, 180., north]
    return [(origin + west + 180) % 360 - 180, south, (origin + east + 180) % 360 - 180, north]


def generate_roster_city(output, city_id, terrain, transport_data, revision, roster=None):
    from build_procedural_city import build_city

    city = roster_city(city_id, roster)
    prefix = city_id.replace(":", "-")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", prefix):
        raise ValueError(f"Roster identifier cannot be used as a page name: {city_id}")
    layout, rows = build_city(city, terrain, transport_data)
    key = f"{prefix}-r{revision}"
    source = "Procedural 1900 city layout"
    entry = pack(output, key, source, "Formal roster, regional Kit, QWG and QPK.", rows, modern_format=True)
    if not entry["tiles"]:
        raise ValueError(f"No buildable plots for {city_id}")
    layout_file = f"{key}.geojson"
    (output/layout_file).write_text(json.dumps(layout, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    entry.update(id=city_id, name=city["name"], kit=layout["wwo"]["kit"], plan=layout_file, revision=revision,
                 plan_bounds=plan_bounds(layout), transport=layout["wwo"]["transport"],
                 reserves=layout["wwo"]["reserves"])
    return entry


@contextmanager
def lock_catalogue(output):
    with (output / ".catalogue.lock").open("a+b") as lock:
        lock.seek(0)
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        yield


def write_catalogue(pending, catalog, data):
    pending.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    pending.replace(catalog)


def publish_roster_cities(output, selected, terrain_root, transport_data, revision, roster=None):
    output.mkdir(parents=True, exist_ok=True)
    catalog = output / "catalogue.json"
    with TemporaryDirectory(prefix=".wwo-city-", dir=output) as folder:
        stage = Path(folder)
        with open_city_terrain(terrain_root) as terrain:
            entries = [generate_roster_city(stage, city_id, terrain, transport_data, revision, roster)
                       for city_id in dict.fromkeys(selected)]
        with lock_catalogue(output):
            previous = read(catalog) if catalog.is_file() else {"version": "wwo-city-models-v2", "cities": []}
            if previous["version"] not in {"wwo-city-models-v1", "wwo-city-models-v2"}:
                raise ValueError(f"Unsupported city model catalogue: {catalog}")
            updates = {row["id"]: row for row in entries}
            if any(row.get("id") in updates and row.get("revision", 0) > revision for row in previous["cities"]):
                raise ValueError("A newer revision is already in the catalogue")
            cities = [row for row in previous["cities"] if row.get("id") not in updates] + entries
            cities.sort(key=lambda row: row.get("id") or row["name"])
            sites = {site["id"]: site for site in previous.get("sites", [])}
            for entry in entries:
                city_id = entry["id"]
                sites[city_id] = {"id": city_id, "name": entry["name"], "point": roster_city(city_id, roster)["point"],
                                  "source": entry["source"]}
            assets = sorted(stage.iterdir())
            for asset in assets:
                target = output / asset.name
                if target.exists() and asset.read_bytes() != target.read_bytes():
                    raise ValueError(f"Page {asset.name} has changed. Increase --revision.")
            for asset in assets:
                target = output / asset.name
                if not target.exists():
                    asset.replace(target)
            data = {**previous, "version": "wwo-city-models-v2", "cities": cities,
                    "sites": [sites[city_id] for city_id in sorted(sites)]}
            write_catalogue(stage / "catalogue.json", catalog, data)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("sources", type=Path, help="Original survey sources, or formal data for --city-id or --batch")
    cli.add_argument("output", type=Path)
    selection = cli.add_mutually_exclusive_group()
    selection.add_argument("--city", choices=("london", "paris"), help="Update one legacy city in the output catalogue")
    selection.add_argument("--city-id", action="append", help="Generate a frozen roster city. Repeat within the current batch.")
    selection.add_argument("--batch", type=int, choices=(7, 8, 9), help="Generate every city in the frozen construction batch")
    cli.add_argument("--terrain", type=Path, help="Directory holding formal QWG and QPK assets")
    cli.add_argument("--revision", type=int, default=1, help="Positive procedural page revision")
    args = cli.parse_args()
    if args.city_id or args.batch is not None:
        if not args.terrain:
            cli.error(f"{'--batch' if args.batch is not None else '--city-id'} requires --terrain")
        if args.revision < 1:
            cli.error("--revision must be positive")
        try:
            selected = args.city_id
            roster = None
            if args.batch is not None:
                from city_landscape_roster import read_roster

                roster = read_roster()
                selected = roster_batch(args.batch, roster)
                validate_batch_inputs(args.batch, selected, roster, args.sources)
            publish_roster_cities(args.output, selected, args.terrain, args.sources, args.revision, roster)
        except (ValueError, OSError, KeyError) as error:
            cli.exit(1, f"{error}\n")
        cli.exit()
    args.output.mkdir(parents=True, exist_ok=args.city is not None)
    catalog = args.output/"catalogue.json"
    previous = read(catalog) if catalog.is_file() else {"version": "wwo-city-models-v1", "cities": []}
    cities = previous["cities"]
    if args.city in (None, "london"):
        cities = [city for city in cities if city["name"] != "London" or city.get("kit")]
        cities.append(pack(args.output, "london", "Surveyed 1891–1896 footprints. Roof form and height reconstructed.",
             "Petitpierre et al., https://doi.org/10.5281/zenodo.19497435 (CC BY 4.0). "
             "OpenHistoricalMap dated centerlines and OpenStreetMap park outlines (ODbL).",
             london(args.sources)))
    if args.city in (None, "paris"):
        cities = [city for city in cities if city["name"] != "Paris" or city.get("kit")]
        cities.append(pack(args.output, "paris", "Paris 1900 reconstructed streets and blocks. Individual buildings simulated.",
             "Paris Time Machine, https://doi.org/10.34847/nkl.cbf5ecd0 (ODbL 1.0). "
             "Institut Paris Region, land use c. 1900 (Licence Ouverte).",
             paris(args.sources)))
    write_catalogue(catalog.with_suffix(".tmp"), catalog, {**previous, "cities": cities})
