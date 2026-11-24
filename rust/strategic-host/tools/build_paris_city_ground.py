"""Build the 1900 Paris-region built-up area and roads from Institut Paris Region exports."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

from city_ground_pack import write_city_tile

GROUP = (1.78, 48.59, 2.89, 49.15)
COLUMNS, ROWS = 5, 4
PIXELS, GUTTER, SAMPLES = 384, 8, 3
PREFIX = "paris-ipr-1900-"
CATALOGUE_BASE = "https://data.iledefrance.fr/explore/dataset/"
SOURCE = "Institut Paris Region / Carte de France vers 1900"


def features(path):
    return json.loads(path.read_text(encoding="utf-8"))["features"]


def coverage(land_use, roads):
    west, south, east, north = GROUP
    width, height = COLUMNS * PIXELS, ROWS * PIXELS
    draw_size = tuple((n + 2 * GUTTER) * SAMPLES for n in (width, height))

    def project(coords):
        return [((GUTTER + width * (x - west) / (east - west)) * SAMPLES,
                 (GUTTER + height * (north - y) / (north - south)) * SAMPLES)
                for x, y in coords]

    built = Image.new("L", draw_size)
    fill = ImageDraw.Draw(built)
    urban = [row for row in features(land_use) if str(row["properties"]["codzon"]) == "3"]
    for row in sorted(urban, key=lambda row: float(row["properties"]["st_areashape"]), reverse=True):
        geometry = row["geometry"]
        if not geometry:
            continue
        polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
        for shell, *holes in polygons:
            fill.polygon(project(shell), fill=255)
            for hole in holes:
                fill.polygon(project(hole), fill=0)

    streets = Image.new("L", draw_size)
    stroke = ImageDraw.Draw(streets)
    for row in features(roads):
        geometry = row["geometry"]
        if not geometry:
            continue
        lines = [geometry["coordinates"]] if geometry["type"] == "LineString" else geometry["coordinates"]
        for line in lines:
            # Fixed visual weight for mapped centre lines. The survey carries no road widths.
            stroke.line(project(line), fill=255, width=4, joint="curve")

    out_size = (width + 2 * GUTTER, height + 2 * GUTTER)
    return [band.resize(out_size, Image.Resampling.BOX) for band in (built, streets)]


def build(land_use, roads, output):
    path = output / "catalogue.json"
    catalogue = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"tiles": []}
    tiles = [tile for tile in catalogue["tiles"] if not tile["path"].startswith(PREFIX)]
    bands = coverage(land_use, roads)
    west, south, east, north = GROUP
    dx, dy = (east - west) / COLUMNS, (north - south) / ROWS
    gx, gy = dx * GUTTER / PIXELS, dy * GUTTER / PIXELS
    size = PIXELS + 2 * GUTTER
    output.mkdir(parents=True, exist_ok=True)
    for y in range(ROWS):
        for x in range(COLUMNS):
            col, row = x * PIXELS, y * PIXELS
            box = (col, row, col + size, row + size)
            urban, streets = (band.crop(box) for band in bands)
            if not urban.getbbox() and not streets.getbbox():
                continue
            left, top = west + x * dx, north - y * dy
            core = [left, top - dy, left + dx, top]
            bounds = [core[0] - gx, core[1] - gy, core[2] + gx, core[3] + gy]
            filename = f"{PREFIX}{x}-{y}.wcm"
            write_city_tile(output / filename, size, Image.merge("LA", (urban, streets)).tobytes())
            tiles.append(dict(path=filename, level=3, core=core, bounds=bounds, group=GROUP,
                              source=SOURCE, size=[size, size], cover=False, city=True,
                              city_area=True, ids=False))
    catalogue["tiles"] = tiles
    catalogue["paris_1900"] = {
        "creator": "Institut Paris Region",
        "land_use": CATALOGUE_BASE + "occupation-du-sol-en-5-postes-vers-1900-carte-de-france-type-1900-dile-de-franc1/",
        "roads": CATALOGUE_BASE + "reseau-routier-vers-1900-carte-de-france-type-1900-dile-de-france1/",
        "license": "Licence Ouverte",
        "scale": "1:50000",
        "processing": "Rasterized urban area class and published road centre lines. Line width is a display style.",
    }
    path.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("land_use", type=Path)
    parser.add_argument("roads", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.land_use, args.roads, args.output)
