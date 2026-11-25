"""Prepare the display surfaces and trees of two historically documented city parks."""
from argparse import ArgumentParser
import json
import math
from pathlib import Path
from random import Random
import struct
from xml.etree import ElementTree

import numpy as np
from PIL import Image, ImageDraw
from shapely import transform, union_all
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import polygonize
import zstandard


SIDE = 512
METRES_PER_PIXEL = 2
SPAN = SIDE * METRES_PER_PIXEL
METRES_PER_DEGREE = 6371008.8 * math.pi / 180


def load_objects(path):
    rows = json.loads(path.read_text(encoding="utf-8-sig"))["elements"]
    ways = {row["id"]: row for row in rows if row["type"] == "way"}
    nodes = {row["id"]: (row["lon"], row["lat"]) for row in rows if row["type"] == "node"}
    return ways, nodes


def osm_way(source, key):
    ways, nodes = source
    return Polygon([nodes[node] for node in ways[key]["nodes"]]).buffer(0)


def osm_lake(path):
    root = ElementTree.parse(path).getroot()
    nodes = {int(row.attrib["id"]): (float(row.attrib["lon"]), float(row.attrib["lat"]))
             for row in root.iter("node")}
    ways = {int(row.attrib["id"]): [nodes[int(nd.attrib["ref"])] for nd in row.findall("nd")]
            for row in root.iter("way")}
    relation = root.find('./relation[@id="276130"]')
    members = [(row.attrib["role"], LineString(ways[int(row.attrib["ref"])]))
               for row in relation.findall("member") if row.attrib["type"] == "way"]
    shores = union_all(list(polygonize([line for role, line in members if role == "outer"])))
    islands = union_all(list(polygonize([line for role, line in members if role == "inner"])))
    if shores.is_empty:
        raise ValueError("The St James's Park lake relation has no closed shore")
    return shores.difference(islands)


class Park:
    def __init__(self, anchor, seed):
        self.anchor = anchor
        self.scales = (METRES_PER_DEGREE * math.cos(math.radians(anchor[1])), METRES_PER_DEGREE)
        self.random = Random(seed)
        self.trees = []

    def local(self, geometry):
        by_axis = lambda x, y: ((x - self.anchor[0]) * self.scales[0],
                                (y - self.anchor[1]) * self.scales[1])
        return transform(geometry, by_axis, interleaved=False)

    def plant(self, x, y, lo, hi):
        radius = self.random.uniform(lo, hi)
        point = Point(x, y)
        if not self.lawn.covers(point) or self.lawn.boundary.distance(point) < radius * .52:
            return
        if any(math.hypot(x - east, y - north) < (radius + r) * .80 for east, north, r, _, _ in self.trees):
            return
        height = radius * self.random.uniform(1.66, 2.30)
        self.trees.append((x, y, radius, height, self.random.random()))

    def textures(self):
        crowns = union_all([Point(x, y).buffer(radius * .96, quad_segs=5) for x, y, radius, _, _ in self.trees])
        regions = [crowns.intersection(self.lawn), self.path, self.water, self.area]
        def paint(region):
            image = Image.new("L", (SIDE * 2, SIDE * 2))
            draw = ImageDraw.Draw(image)
            for polygon in getattr(region, "geoms", [region]):
                if polygon.is_empty or polygon.geom_type != "Polygon":
                    continue
                def pixels(ring):
                    return [((e + SPAN / 2), (n + SPAN / 2)) for e, n in ring.coords]
                draw.polygon(pixels(polygon.exterior), fill=255)
                for ring in polygon.interiors:
                    draw.polygon(pixels(ring), fill=0)
            return image.resize((SIDE, SIDE), Image.Resampling.BOX)

        bands = [paint(region) for region in regions]
        return Image.merge("RGBA", bands)


def tuileries(root):
    park = Park((2.32667, 48.86365), 1873)
    source = load_objects(root / "paris_reference/osm-context.json")
    park.area = park.local(osm_way(source, 53820452)).simplify(.8)
    # The Grand Bassin Octogonal and Grand Bassin Rond establish Le Nôtre's axis.
    pools = [park.local(osm_way(source, key)) for key in (54188993, 14037695, 54201241, 54201242)]
    start, end = (np.array(pool.centroid.coords[0]) for pool in pools[:2])
    along = (end - start) / np.linalg.norm(end - start)
    cross = np.array([-along[1], along[0]])

    def coord(east, north):
        return tuple(start + east * along + north * cross)

    def beds(x0, x1, y0, y1):
        return Polygon([coord(x0, y0), coord(x1, y0), coord(x1, y1), coord(x0, y1)])

    # The Octogone is an open forecourt. The wooded Grand Couvert separates it
    # from the formal parterres. The exact beds and tree spacing are scenery.
    lawns = []
    for sign in (-1, 1):
        for first, last, half in ((67, 126, 91), (137, 195, 98), (207, 267, 94),
                                  (282, 329, 77), (345, 392, 80), (404, 485, 81)):
            for inner, outer in ((13, 48), (58, half)):
                lawns.append(beds(first, last, sign * inner, sign * outer).buffer(-1.5).buffer(1.5))
    park.water = union_all(pools).intersection(park.area)
    park.lawn = union_all(lawns).intersection(park.area).difference(park.water.buffer(6.))
    terrace = park.area.difference(park.area.buffer(-17.)).difference(park.water)
    park.lawn = park.lawn.union(terrace.intersection(beds(18, 506, -115, 115)).buffer(0))
    park.lawn = park.lawn.difference(park.water.buffer(4.))
    park.path = park.area.difference(park.lawn.union(park.water))
    for distance in range(75, 271, 14):
        for row in (-86, -69, -41, -22, 22, 41, 69, 86):
            x, y = coord(distance, row)
            park.plant(x, y, 4.0, 7.3)
    for distance in range(294, 473, 22):
        for row in (-71, 71):
            park.plant(*coord(distance, row), 3.7, 5.3)
    return park


def st_james(root):
    park = Park((-.1344, 51.50308), 1827)
    area = load_objects(root / "london_1890s/park-st-james-boundary.json")
    park.area = park.local(osm_way(area, 374960368)).simplify(.8)
    park.water = park.local(osm_lake(root / "london_1890s/park-st-james-lake-reference.osm")).intersection(park.area)
    routes = root / "london_1890s/ohm-dated-roads.json"
    paths = [park.local(LineString([(p["lon"], p["lat"]) for p in row["geometry"]]))
             for row in json.loads(routes.read_text(encoding="utf-8-sig"))["elements"]
             if row["id"] in (198579978, 198579979, 198579980) and row["type"] == "way"]
    park.path = union_all([line.buffer(2.3, quad_segs=4) for line in paths]).intersection(park.area)
    park.path = park.path.difference(park.water)
    park.lawn = park.area.difference(park.path.buffer(1.8).union(park.water.buffer(2.5)))
    # Alternate planted reaches and open views along Nash's dated walks.
    for path in paths:
        for at in range(12, int(path.length) - 7, 13):
            if (at // 84) % 3 == 1:
                continue
            a, b = path.interpolate(at - 3), path.interpolate(at + 3)
            angle = math.atan2(b.y - a.y, b.x - a.x) + math.pi / 2
            p = path.interpolate(at)
            for side in (-1, 1):
                offset = park.random.uniform(5., 16.) * side
                park.plant(p.x + math.cos(angle) * offset, p.y + math.sin(angle) * offset, 4.0, 8.0)
    for _ in range(165):
        x = park.random.uniform(*park.area.bounds[::2])
        y = park.random.uniform(*park.area.bounds[1::2])
        p = Point(x, y)
        if 4. < park.area.boundary.distance(p) < 24. or (x > 140. and p.distance(park.water) < 45.):
            park.plant(x, y, 4.3, 8.1)
    return park


def save(path, parks):
    words_per_header = 8
    header = bytearray(4 * (1 + len(parks) * words_per_header))
    payload = bytearray()
    struct.pack_into("<I", header, 0, len(parks))
    for i, park in enumerate(parks):
        # All mips use area averages. Filter channels independently with alpha
        # stored as park coverage, so PIL never interprets it as bitmap alpha.
        offset = (len(header) + len(payload)) // 4
        channels = park.textures().split()
        for side in (SIDE >> n for n in range(SIDE.bit_length())):
            filtered = [band.resize((side, side), Image.Resampling.BOX) for band in channels]
            payload.extend(Image.merge("RGBA", filtered).tobytes())
        trees = (len(header) + len(payload)) // 4
        payload.extend(b"".join(struct.pack("<5f", *tree) for tree in park.trees))
        scales = tuple(scale / SPAN for scale in park.scales)
        struct.pack_into("<4f4I", header, 4 * (1 + i * words_per_header),
                         *park.anchor, *scales, SIDE, offset, trees, len(park.trees))
        print(park.anchor, len(park.trees), round(park.area.area), "sq m")
    path.write_bytes(zstandard.ZstdCompressor(level=14).compress(header + payload))


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("sources", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    save(args.output, (tuileries(args.sources), st_james(args.sources)))


if __name__ == "__main__":
    main()
