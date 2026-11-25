"""Build 1900 Paris ground from Institut Paris Region and Paris Time Machine."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from city_ground_pack import write_city_tile

GROUP = (1.78, 48.59, 2.89, 49.15)
COLUMNS, ROWS = 5, 4
PIXELS, GUTTER, SAMPLES = 384, 8, 3
PREFIX = "paris-ipr-1900-"
CATALOGUE_BASE = "https://data.iledefrance.fr/explore/dataset/"
SOURCE = "Institut Paris Region / Carte de France vers 1900"
STREETS_GROUP = (2.251, 48.815, 2.417, 48.903)
STREETS_GRID = (4, 4)
STREETS_PREFIX = "paris-ptm-1900-"
STREETS_SOURCE = "Paris Time Machine / historical street reconstruction c. 1900"
BLOCKS_PREFIX = "paris-ptm-blocks-1900-"
BLOCKS_SOURCE = "Paris Time Machine / historical built block reconstruction c. 1900"


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


def street_coverage(roads):
    west, south, east, north = STREETS_GROUP
    width, height = (dim * PIXELS for dim in STREETS_GRID)
    size = (width + 2 * GUTTER, height + 2 * GUTTER)
    bands = [Image.new("L", tuple(dim * SAMPLES for dim in size)) for _ in range(2)]
    major, local = map(ImageDraw.Draw, bands)
    for row in features(roads):
        geometry = row["geometry"]
        if not geometry:
            continue
        kind = (row["properties"].get("typvoie") or "").casefold()
        arterial = kind in {"avenue", "boulevard", "quai", "pont", "place"}
        lines = [geometry["coordinates"]] if geometry["type"] == "LineString" else geometry["coordinates"]
        for line in lines:
            points = [((GUTTER + width * (x - west) / (east - west)) * SAMPLES,
                       (GUTTER + height * (north - y) / (north - south)) * SAMPLES)
                      for x, y, *_ in line]
            (major if arterial else local).line(points, fill=255, width=6 if arterial else 3, joint="curve")
    return [band.resize(size, Image.Resampling.BOX) for band in bands]


def block_coverage(blocks, land_use):
    west, south, east, north = STREETS_GROUP
    width, height = (dim * PIXELS for dim in STREETS_GRID)
    size = (width + 2 * GUTTER, height + 2 * GUTTER)
    draw_size = tuple(dim * SAMPLES for dim in size)

    def project(coords):
        return [((GUTTER + width * (x - west) / (east - west)) * SAMPLES,
                 (GUTTER + height * (north - y) / (north - south)) * SAMPLES)
                for x, y, *_ in coords]

    def mask(rows):
        result = Image.new("L", draw_size)
        draw = ImageDraw.Draw(result)
        for row in rows:
            geometry = row["geometry"]
            if not geometry or geometry["type"] not in {"Polygon", "MultiPolygon"}:
                continue
            polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
            for shell, *holes in polygons:
                points = project(shell)
                xs, ys = zip(*points)
                if max(xs) < 0 or min(xs) >= draw_size[0] or max(ys) < 0 or min(ys) >= draw_size[1]:
                    continue
                draw.polygon(points, fill=255)
                for hole in holes:
                    draw.polygon(project(hole), fill=0)
        return result

    built = mask(row for row in features(blocks) if row["properties"].get("Bati_nonBati") == "Bâti")
    exclusions = mask(row for row in features(land_use) if str(row["properties"].get("codzon")) in {"1", "2", "4"})
    built = ImageChops.subtract(built, exclusions).resize(size, Image.Resampling.BOX)
    return [built, built.filter(ImageFilter.MinFilter(5))]


def write_tiles(output, bands, group, grid, prefix, source, **style):
    west, south, east, north = group
    columns, rows = grid
    dx, dy = (east - west) / columns, (north - south) / rows
    gx, gy = dx * GUTTER / PIXELS, dy * GUTTER / PIXELS
    size = PIXELS + 2 * GUTTER
    output.mkdir(parents=True, exist_ok=True)
    for y in range(rows):
        for x in range(columns):
            col, row = x * PIXELS, y * PIXELS
            box = (col, row, col + size, row + size)
            first, second = (band.crop(box) for band in bands)
            if not first.getbbox() and not second.getbbox():
                continue
            left, top = west + x * dx, north - y * dy
            core = [left, top - dy, left + dx, top]
            bounds = [core[0] - gx, core[1] - gy, core[2] + gx, core[3] + gy]
            filename = f"{prefix}{x}-{y}.wcm"
            write_city_tile(output / filename, size, Image.merge("LA", (first, second)).tobytes())
            yield dict(path=filename, level=3, core=core, bounds=bounds, group=group,
                       source=source, size=[size, size], cover=False, city=True, **style, ids=False)


def build(land_use, roads, output, detailed_streets=None, blocks=None):
    path = output / "catalogue.json"
    catalogue = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"tiles": []}
    tiles = [tile for tile in catalogue["tiles"] if not tile["path"].startswith(PREFIX)]
    tiles.extend(write_tiles(output, coverage(land_use, roads), GROUP, (COLUMNS, ROWS),
                             PREFIX, SOURCE, city_area=True))
    if detailed_streets is not None:
        tiles = [tile for tile in tiles if not tile["path"].startswith(STREETS_PREFIX)]
        tiles.extend(write_tiles(output, street_coverage(detailed_streets), STREETS_GROUP, STREETS_GRID,
                                 STREETS_PREFIX, STREETS_SOURCE, city_streets=True))
        catalogue["paris_streets_1900"] = {
            "creator": "Paris Time Machine",
            "source": "https://doi.org/10.34847/nkl.cbf5ecd0",
            "license": "ODbL 1.0",
            "processing": "Rasterized reconstructed street centre lines. Display widths based on street type.",
        }
    if blocks is not None:
        tiles = [tile for tile in tiles if not tile["path"].startswith(BLOCKS_PREFIX)]
        tiles.extend(write_tiles(output, block_coverage(blocks, land_use), STREETS_GROUP, STREETS_GRID,
                                 BLOCKS_PREFIX, BLOCKS_SOURCE, city_blocks=True))
        catalogue["paris_blocks_1900"] = {
            "creator": "Paris Time Machine",
            "source": "https://doi.org/10.34847/nkl.cbf5ecd0",
            "license": "ODbL 1.0",
            "processing": "Reconstructed built blocks with historical non-built land use excluded. Interior shading is a display style.",
        }
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
    parser.add_argument("--detailed-streets", type=Path)
    parser.add_argument("--blocks", type=Path)
    args = parser.parse_args()
    build(args.land_use, args.roads, args.output, args.detailed_streets, args.blocks)
