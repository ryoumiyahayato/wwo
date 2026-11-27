"""Pack historical city-model pages from survey footprints and local plans."""

import argparse
import json
import math
import re
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
ROOT = Path(__file__).resolve().parents[3]
HISTORICAL = ROOT / "data/world_map/historical/city_landscape_1900"
ROLES = ("low_home", "street_row", "courtyard_home", "shop", "civic", "warehouse", "workshop",
         "transport_auxiliary")
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


def planned_site(path, city_id):
    """Return source-constrained placements in a stable metric frame."""
    plan = read(path)
    meta = plan["wwo"]
    if plan["type"] != "FeatureCollection" or meta["city_id"] != city_id:
        raise ValueError("Expected a GeoJSON FeatureCollection for the requested city")
    site = next(row for row in read(HISTORICAL / "batch6-sites.json")["sites"] if row["city_id"] == city_id)
    all_kits = {row["id"]: row for row in read(ROOT / "assets/settlements/city-kits-1900.json")}
    kit = all_kits[site["profile"]]
    source_notes = {row["id"]: row for row in meta["sources"]}
    forward, backward = transforms(meta["origin"])
    if len(source_notes) != len(meta["sources"]) or not source_notes:
        raise ValueError("Site source IDs must be unique")
    for row in source_notes.values():
        if not all(row.get(k) for k in ("url", "licence", "date", "precision")):
            raise ValueError("Site sources require URL, licence, date and precision")

    geometry = defaultdict(list)
    ids = set()
    for row in plan["features"]:
        props = row["properties"]
        key = str(row["id"])
        kind = props["kind"]
        if key in ids or props["source"] not in source_notes:
            raise ValueError(f"Duplicate or unsourced feature {key}")
        for field in ("use_reference", "form_reference", "bridge_reference"):
            if field in props and props[field] not in source_notes:
                raise ValueError(f"Unknown {field} for {key}")
        ids.add(key)
        if kind not in ("coverage", "road", "building", "water", "water_surface", "known_dry",
                        "park", "yard", "rail", "steep", "zone"):
            raise ValueError(f"Unknown site geometry {kind}")
        geom = transform(shape(row["geometry"]), forward)
        if geom.is_empty or not geom.is_valid or not all(math.isfinite(v) for v in geom.bounds):
            raise ValueError(f"Invalid geometry for {key}")
        expected = ("LineString", "MultiLineString") if kind == "road" else ("Polygon", "MultiPolygon")
        if geom.geom_type not in expected:
            raise ValueError(f"Invalid {kind} geometry type for {key}")
        geometry[kind].append((key, geom, props))
    for group in geometry.values():
        group.sort(key=lambda row: row[0])
    if not geometry["coverage"]:
        raise ValueError("Site requires a historical plan coverage boundary")
    coverage = shapely.union_all([geom for _, geom, _ in geometry["coverage"]])
    shapely.prepare(coverage)
    blockers = [geom for kind in ("water", "water_surface", "park", "yard", "rail", "steep")
                for _, geom, _ in geometry[kind]]
    for _, geom, props in geometry["road"]:
        width = float(props["width_m"])
        if not 1. <= width <= 80.:
            raise ValueError("Invalid road width")
        blockers.append(geom.buffer(width * 0.5))
    obstacles = exclusions(blockers)
    footprints = exclusions([geom for _, geom, _ in geometry["building"]])
    # The bucket grid is only a spatial index for accepted parcels.
    occupied = defaultdict(list)

    def cells(geom):
        left, bottom, right, top = (math.floor(value / 48) for value in geom.bounds)
        return [(x, y) for x in range(left, right + 1) for y in range(bottom, top + 1)]

    def placement(x, y, angle, width, depth, height, role, limit, inferred):
        lot = rectangle(x, y, angle, width, depth)
        if not coverage.covers(lot) or not limit.covers(lot) or not clear_of(obstacles, lot):
            return None
        if inferred and not clear_of(footprints, lot):
            return None
        bins = cells(lot)
        if any(lot.intersection(other).area > 0.05 for cell in bins for other in occupied[cell]
               if lot.intersects(other)):
            return None
        lon, lat = backward.transform(x, y)
        if not (-180 <= lon <= 180 and -90 <= lat <= 90 and 0 < height <= 320):
            raise ValueError("Building anchor or height outside supported range")
        for cell in bins:
            occupied[cell].append(lot)
        return x, y, lon, lat, angle, width, depth, height, ROLES.index(role) + 1

    rows = []
    provenance = []
    def record(row, key, props, origin):
        rows.append(row)
        lon, lat = row[2:4]
        provenance.append({
            "id": f"{city_id}/{key}/{round(lon*1e6)}/{round(lat*1e6)}",
            "anchor_e6": [round(lon*1e6), round(lat*1e6)],
            "role": ROLES[row[-1]-1],
            "origin": origin,
            "feature": key,
            "source": props["source"],
            **{field: props[field] for field in ("use_reference", "form_reference") if field in props},
        })

    for key, geom, props in geometry["building"]:
        role = props.get("role", "street_row")
        for part in shapely.get_parts(geom):
            angle, width, depth = orientation(part.minimum_rotated_rectangle)
            center = part.minimum_rotated_rectangle.centroid
            for scale in (0.96, 0.80, 0.64, 0.48):
                if depth*scale < 2.:
                    break
                height = float(props.get("height_m", kit["storeys"][0]*3.2))
                row = placement(center.x, center.y, angle, width*scale, depth*scale, height, role, part, False)
                if row:
                    record(row, key, props, "historical_footprint")
                    break

    # Inference is limited to expressly mapped use polygons and their streets.
    roads = [(line, props) for _, geom, props in geometry["road"] for line in shapely.get_parts(geom)]
    road_tree = STRtree([line for line, _ in roads])
    for key, zone, props in geometry["zone"]:
        role = props["role"]
        gap = float(props["gap_m"])
        if not 0. <= gap <= 50.:
            raise ValueError("Invalid parcel spacing")
        ranges = []
        for field, minimum, maximum in (("frontage_m", 2., 160.), ("depth_m", 2., 160.),
                                         ("setback_m", 0., 60.), ("storeys", 1., 30.)):
            low, high = map(float, props.get(field, kit[field]))
            if not minimum <= low <= high <= maximum:
                raise ValueError(f"Invalid parcel range for {field}")
            ranges.append((low, high))
        max_frontage, max_depth, max_setback = (high for _, high in ranges[:3])
        shapely.prepare(zone)
        reach = 40. + max_setback + math.hypot(max_frontage, max_depth) * 0.5 + 0.4
        for index in sorted(road_tree.query(zone.buffer(reach))):
            line, road = roads[index]
            if line.length < 8.:
                continue
            for side in (-1, 1):
                distance = 0.
                while distance < line.length:
                    point = line.interpolate(distance)
                    pattern = (round(point.x*10)*31 + round(point.y*10)*17 + side) % 97 / 96
                    width, depth, setback, storeys = (low + pattern*(high-low) for low, high in ranges)
                    midpoint = distance + width*0.5
                    distance += width + gap
                    if midpoint + width*0.5 > line.length:
                        break
                    at = line.interpolate(midpoint)
                    before, after = line.interpolate(midpoint-width*0.45), line.interpolate(midpoint+width*0.45)
                    heading = math.atan2(after.y-before.y, after.x-before.x)
                    offset = road["width_m"]*0.5 + setback + depth*0.5 + 0.4
                    x, y = at.x-side*math.sin(heading)*offset, at.y+side*math.cos(heading)*offset
                    facing = heading if side > 0 else heading+math.pi
                    row = placement(x, y, facing, width, depth, round(storeys)*3.2, role, zone, True)
                    if row:
                        record(row, key, props, "inferred_parcel")
    if not rows:
        raise ValueError("No source-constrained placements in the requested site")
    return meta, kit["id"], sorted(rows), sorted(provenance, key=lambda rec: rec["id"])


def write_revisioned(path, data):
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError(f"Page {path.name} has changed; increment the site revision")
        return
    temporary = path.with_suffix(".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)


def pack(output, key, source, attribution, rows, modern_format=False):
    tiles = defaultdict(list)
    tile_size = 512 if modern_format else TILE
    for x, y, lon, lat, angle, width, depth, height, module in rows:
        tiles[math.floor(x/tile_size),math.floor(y/tile_size)].append((lon,lat,angle,width,depth,height,module))
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
        magic = b"WWOWCB02" if modern_format else b"WWOWCB01"
        data = magic + struct.pack("<I", len(records)) + compressor.compress(payload)
        path = output/name
        if modern_format:
            write_revisioned(path, data)
        else:
            temporary = path.with_suffix(".tmp")
            temporary.write_bytes(data)
            temporary.replace(path)
        entries.append(dict(file=name, bounds=bounds, buildings=len(records)))
    print(f"{key}: {sum(len(r) for r in tiles.values()):,} building placements in {len(tiles)} tiles", flush=True)
    return dict(name=key.title(), source=source, attribution=attribution, tiles=entries)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("sources", type=Path)
    cli.add_argument("output", type=Path)
    cli.add_argument("--city", choices=("london", "paris"), help="Update one city in the output catalogue")
    cli.add_argument("--site", help="Update one frozen city using a local CRS84 plan")
    cli.add_argument("--with-roads", action="store_true", help="Pack candidate display roads from the same plan")
    args = cli.parse_args()
    if args.city and args.site:
        cli.error("--city and --site select different inputs")
    if args.with_roads and not args.site:
        cli.error("--with-roads requires --site")
    args.output.mkdir(parents=True, exist_ok=args.city is not None or args.site is not None)
    catalog = args.output/"catalogue.json"
    previous = read(catalog) if catalog.is_file() else {"version": "wwo-city-models-v1", "cities": []}
    cities = previous["cities"]
    version = previous["version"]
    if args.site:
        meta, kit, rows, provenance = planned_site(args.sources, args.site)
        key, revision = meta["key"], meta["revision"]
        if not re.fullmatch("[a-z0-9]+(?:-[a-z0-9]+)*", key) or type(revision) is not int or revision < 1:
            raise ValueError("Invalid site key or revision")
        current = next((city for city in cities if city.get("id") == args.site), None)
        if current and current.get("revision", 0) > revision:
            raise ValueError("A newer site revision is already in the catalogue")
        directory_key = f"{key}-r{revision}"
        entries = pack(args.output, directory_key, meta["method"],
                       " · ".join(f'{r["url"]} ({r["licence"]})' for r in meta["sources"]), rows, True)
        origins = f"{directory_key}.origins.json.zst"
        provenance_json = json.dumps(provenance, ensure_ascii=False, separators=(",", ":"))
        write_revisioned(args.output/origins, ZstdCompressor(level=5).compress(provenance_json.encode("utf-8")))
        entry = dict(entries, id=args.site, name=meta["name"], kit=kit, revision=revision,
                     placement_origins=origins, source_records=meta["sources"])
        if current and current.get("revision") == revision and "road_pages" in current:
            entry.update(road_pages=current["road_pages"], road_origins=current["road_origins"])
        if args.with_roads:
            from build_city_water import planned_road_pages

            plan = read(args.sources)
            records, pages = planned_road_pages(plan)
            if not pages:
                raise ValueError("No sourced roads in the requested site")
            road_entries = []
            compressor = ZstdCompressor(level=5)
            for x, y, bounds, payload, parents, water_parents in pages:
                layer = "water" if water_parents else "road"
                validity = meta.get(f"{layer}_validity", {})
                start, end = validity.get("start"), validity.get("end")
                if not (type(start) is int and type(end) is int and 1 <= start < end <= 9999):
                    raise ValueError(f"{layer} pages require start and end years with end exclusive")
                suffix = "-water" if water_parents else ""
                name = f"{directory_key}-{x}-{y}{suffix}.wcr"
                header = (b"WWOCRD02" if water_parents else b"WWOCRD01") + struct.pack("<I", len(payload))
                write_revisioned(args.output/name, header + compressor.compress(payload))
                tile = dict(file=name, bounds=bounds, bytes=len(payload), features=len(parents), years=[start, end])
                if water_parents:
                    tile["water_features"] = len(water_parents)
                road_entries.append(tile)
            road_origins = f"{directory_key}.roads.json.zst"
            road_notes = dict(roads=[r for r in records if r["properties"]["kind"] == "road"],
                              pages={tile["file"]: page[4] for tile, page in zip(road_entries, pages) if page[4]})
            if any(page[5] for page in pages):
                road_notes["water"] = [r for r in records if r["properties"]["kind"] != "road"]
                road_notes["water_pages"] = {tile["file"]: page[5] for tile, page in zip(road_entries, pages) if page[5]}
            write_revisioned(args.output/road_origins, compressor.compress(
                json.dumps(road_notes, ensure_ascii=False, separators=(",", ":")).encode("utf-8")))
            entry.update(road_pages=road_entries, road_origins=road_origins)
        if current:
            cities[cities.index(current)] = entry
        else:
            cities.append(entry)
        version = "wwo-city-models-v2"
    if not args.site and args.city in (None, "london"):
        cities = [city for city in cities if city["name"] != "London"]
        cities.append(pack(args.output, "london", "Surveyed 1891–1896 footprints. Roof form and height reconstructed.",
             "Petitpierre et al., https://doi.org/10.5281/zenodo.19497435 (CC BY 4.0). "
             "OpenHistoricalMap dated centerlines and OpenStreetMap park outlines (ODbL).",
             london(args.sources)))
    if not args.site and args.city in (None, "paris"):
        cities = [city for city in cities if city["name"] != "Paris"]
        cities.append(pack(args.output, "paris", "Paris 1900 reconstructed streets and blocks. Individual buildings simulated.",
             "Paris Time Machine, https://doi.org/10.34847/nkl.cbf5ecd0 (ODbL 1.0). "
             "Institut Paris Region, land use c. 1900 (Licence Ouverte).",
             paris(args.sources)))
    catalogue_text = json.dumps(dict(version=version, cities=cities), ensure_ascii=False, indent=2)
    if not catalog.exists() or catalog.read_text(encoding="utf-8") != catalogue_text:
        pending = catalog.with_suffix(".tmp")
        pending.write_text(catalogue_text, encoding="utf-8")
        pending.replace(catalog)
