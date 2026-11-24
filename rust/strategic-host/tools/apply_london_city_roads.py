"""Add dated OpenHistoricalMap roads to the existing London footprint pages.

Overpass extract: way["highway"]["start_date"](51.371,-0.371,51.638,0.104);out geom;
"""

import argparse
import json
import re
from math import cos, radians
from pathlib import Path

from PIL import Image, ImageDraw

from city_ground_pack import read_city_coverage, write_city_tile

PREFIX = "london-os-1890s-"
DATE = "1900-01-01"
DATE_PREFIX = re.compile(r"\d{4}(?:-\d{2}(?:-\d{2})?)?")
SURVEY = re.compile(r"OS 1:1056 \((?:1862-74,\s*)?1893-6\)")
MAIN_ROADS = {"trunk", "primary", "secondary", "tertiary"}
# Dated Thames crossings in the London OHM project. Westminster's line is
# aligned with the surviving 1862 bridge despite the entry's older start date.
CROSSINGS = {
    198525304,  # Battersea
    198530164,  # Albert
    198563793,  # Putney
    198563796,  # Hammersmith
    198568410,  # Westminster
    198571974,  # Tower
    198571975,  # London (1831)
    198576925,  # Vauxhall (1816)
    198582281,  # Blackfriars
    198582846,  # Waterloo (1817)
    198586037,  # Lambeth (1862)
    198586260,  # Southwark (1819)
}


def surveyed_roads(export):
    roads = []
    for feature in export["elements"]:
        tags = feature["tags"]
        start = tags.get("start_date", "")
        end = tags.get("end_date", "")
        if not DATE_PREFIX.fullmatch(start) or start > DATE or start in {"1900", "1900-01"}:
            continue
        if end and (not DATE_PREFIX.fullmatch(end) or end <= DATE):
            continue
        if tags.get("license") not in {None, "CC0", "CC0-1.0"}:
            continue
        crossing = feature["id"] in CROSSINGS
        source = tags.get("source", "")
        if not crossing and (not SURVEY.search(source) or "1947-63" in source):
            continue
        if tags.get("highway") in {"no", "proposed", "construction"}:
            continue
        if tags.get("tunnel") not in {None, "no", "building_passage"}:
            continue
        points = [(node["lon"], node["lat"]) for node in feature["geometry"]]
        if len(points) < 2:
            continue
        xs, ys = zip(*points)
        extent = min(xs), min(ys), max(xs), max(ys)
        major = crossing or tags.get("highway") in MAIN_ROADS
        roads.append((major, feature["id"], points, extent))
    return sorted(roads)


def road_coverage(size, bounds, roads):
    west, south, east, north = bounds
    samples = 3
    width = size * samples
    coverage = Image.new("L", (width, width))
    draw = ImageDraw.Draw(coverage)
    x_scale = width / (east - west)
    y_scale = width / (north - south)
    metres = 111195 * cos(radians((south + north) / 2)) / x_scale
    for major, _, points, (left, bottom, right, top) in roads:
        if left >= east or right <= west or bottom >= north or top <= south:
            continue
        xy = [((x - west) * x_scale, (north - y) * y_scale) for x, y in points]
        # Cartographic width. The source is a centre line survey.
        draw.line(xy, fill=255 if major else 196, width=max(1, round((22 if major else 9) / metres)),
                  joint="curve")
    return coverage.resize((size, size), Image.Resampling.BOX)


def build(source, folder):
    export = json.loads(source.read_bytes())
    roads = surveyed_roads(export)
    actual_crossings = {feature_id for _, feature_id, _, _ in roads} & CROSSINGS
    if not roads:
        raise ValueError("London source extract has no matching roads")
    path = folder / "catalogue.json"
    catalogue = json.loads(path.read_text(encoding="utf-8"))
    tiles = [tile for tile in catalogue["tiles"] if tile["path"].startswith(PREFIX)]
    if not tiles:
        raise ValueError("Build the existing London footprint pages first")
    for tile in tiles:
        width, height = tile["size"]
        if width != height:
            raise ValueError(f"Non-square London city page: {tile['path']}")
        destination = folder / tile["path"]
        footprint, _ = Image.frombytes("LA", (width, height), read_city_coverage(destination)).split()
        road = road_coverage(width, tile["bounds"], roads)
        write_city_tile(destination, width, Image.merge("LA", (footprint, road)).tobytes())
    catalogue["london_roads_1900"] = {
        "creator": "OpenHistoricalMap contributors",
        "source": "https://wiki.openstreetmap.org/wiki/OpenHistoricalMap/Projects/London",
        "license": "https://www.openhistoricalmap.org/copyright",
        "source_snapshot": export["osm3s"]["timestamp_osm_base"],
        "map_date": DATE,
        "selection": "Dated ways with an 1893–1896 Ordnance Survey source, plus selected dated Thames crossings.",
        "way_count": len(roads),
        "thames_crossing_way_ids": sorted(actual_crossings),
        "processing": "Display coverage of selected centre lines. Width is cartographic. Coverage is incomplete.",
    }
    catalogue["processing"] = "Building footprints rasterized to coverage. London roads have a separate source."
    path.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(roads)} ways, including {len(actual_crossings)} Thames crossings")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="OpenHistoricalMap Overpass JSON export with way geometry")
    parser.add_argument("folder", type=Path, help="Existing city-overlays directory")
    args = parser.parse_args()
    build(args.source, args.folder)
