"""Build the local Seine and Thames banks and streets from retained vector sources."""
from argparse import ArgumentParser
import json
import math
from pathlib import Path
import struct

from shapely import box, transform, union_all
from shapely.geometry import LinearRing, Polygon, shape
import zstandard


SITES = (
    ((2.34, 48.855), (2.24, 48.80, 2.46, 48.915), "paris_reference/water.geojson"),
    ((-0.12, 51.506), (-0.32, 51.44, 0.14, 51.54), "london_1890s/thames-presentation-union.geojson"),
)
METRES = 6371008.8 * math.pi / 180
BAND_HEIGHT = 32
ROAD_CELL = 64


def curved_ring(ring, anchors):
    simplified = list(ring.simplify(0.20, preserve_topology=True).coords)[:-1]
    if len(simplified) <= 4:
        return ring
    points = []
    for i, corner in enumerate(simplified):
        previous = simplified[i-1]
        following = simplified[(i+1) % len(simplified)]
        if any(math.dist(corner, anchor) <= 24 for anchor in anchors):
            points.append(corner)
            continue

        def control(neighbour):
            ratio = min(0.24, 1.5 / max(0.001, math.dist(corner, neighbour)))
            return tuple(a + (b-a)*ratio for a, b in zip(corner, neighbour))

        entry, exit = control(previous), control(following)
        for t in (0., .25, .5, .75, 1.):
            points.append(tuple((1-t)**2*a + 2*(1-t)*t*b + t*t*c
                                for a, b, c in zip(entry, corner, exit)))
    replacement = LinearRing(points)
    if not replacement.is_simple or replacement.hausdorff_distance(ring) > 1.8:
        return ring
    return replacement


def redraw(part, anchors):
    candidate = Polygon(curved_ring(part.exterior, anchors),
                        [curved_ring(ring, anchors) for ring in part.interiors])
    if (candidate.is_valid and len(candidate.interiors) == len(part.interiors)
            and abs(candidate.area-part.area) <= max(2., part.area*.003)):
        return candidate
    return part


def encode(word, fmt):
    return struct.unpack("<I", struct.pack("<" + fmt, word))[0]


def sections(root, origin, extent, source):
    lon, lat = origin
    east = METRES*math.cos(math.radians(lat))
    project = lambda x, y: ((x-lon)*east, (y-lat)*METRES)
    sw = project(*extent[:2])
    ne = project(*extent[2:])
    limits = box(*sw, *ne)
    base = json.loads((root / source).read_text(encoding="utf-8-sig"))
    # The continuous main stem is the largest polygon in both retained unions.
    # Other hydrological records are still rendered by the QWG underlay.
    original = max(shape(base["geometry"]).geoms, key=lambda part: part.area)
    anchors = []
    if source.startswith("london"):
        bridges = json.loads((root / "london_1890s/ohm-dated-roads.json").read_text(encoding="utf-8-sig"))
        for record in bridges["elements"]:
            if record.get("tags", {}).get("bridge") and record.get("geometry"):
                anchors.extend(project(p["lon"], p["lat"]) for p in record["geometry"])
    else:
        roads = json.loads((root / "paris_1900_ptm/PTM_Paris1900_rues_epsg4326.geojson").read_text(encoding="utf-8-sig"))
        for record in roads["features"]:
            crossing = record["properties"].get("franchisst")
            if crossing and "pont" in str(crossing).lower():
                geometry = shape(record["geometry"])
                lines = geometry.geoms if geometry.geom_type == "MultiLineString" else [geometry]
                anchors.extend(project(*p[:2]) for line in lines for p in line.coords)
        # Historical island and bridge connections in the central source extents.
        anchors.extend(project(*ll) for ll in [(2.3418,48.8572),(2.3466,48.8540),
                                              (2.3514,48.8533),(2.3541,48.8530),
                                              (2.3580,48.8507),(2.3576,48.8540)])
    clipped = transform(original, project, interleaved=False).intersection(limits)
    drawn = [redraw(part, anchors) for part in getattr(clipped, "geoms", [clipped])
             if part.geom_type == "Polygon" and part.area > 0]
    return [lon, lat, east, METRES, *sw, *ne], drawn, limits


def road_lines(root, london):
    if london:
        from shapely.geometry import LineString
        widths = {"trunk": 10, "primary": 8, "secondary": 7, "tertiary": 5,
                  "residential": 3.6, "living_street": 3.6, "unclassified": 3.6, "service": 2.8}
        road_file = root / "london_1890s/ohm-dated-roads.json"
        for row in json.loads(road_file.read_text(encoding="utf-8-sig"))["elements"]:
            tags = row.get("tags", {})
            start = str(tags.get("start_date", "")).split("-")[0]
            end = str(tags.get("end_date", "")).split("-")[0]
            width = widths.get(tags.get("highway"))
            points = row.get("geometry", [])
            if (width is None or len(points) < 2 or not start.isdecimal() or int(start) > 1900
                    or end.isdecimal() and int(end) <= 1900):
                continue
            material = 0 if tags.get("surface") == "unpaved" else 2 if width >= 5 else 1
            yield LineString([(p["lon"], p["lat"]) for p in points]), width, material, bool(tags.get("bridge"))
    else:
        road_file = root / "paris_1900_ptm/PTM_Paris1900_rues_epsg4326.geojson"
        for row in json.loads(road_file.read_text(encoding="utf-8-sig"))["features"]:
            fields = row["properties"]
            if fields.get("fictif") == "Oui" or not row.get("geometry"):
                continue
            width = float(fields.get("largeur") or 4)
            material = 2 if width >= 5 or fields.get("typvoie") in ("rue", "quai", "pont") else 1
            yield shape(row["geometry"]), min(width, 28.), material, fields.get("franchisst") == "Pont"


def pack_roads(root, words, limits, values, london):
    lon, lat, x_scale, y_scale, west, south, east, north = values
    width, height = math.ceil((east-west)/ROAD_CELL), math.ceil((north-south)/ROAD_CELL)
    index = len(words)
    words.extend([width, height] + [0]*(2*width*height))
    cells = {}
    project = lambda x, y: ((x-lon)*x_scale, (y-lat)*y_scale)
    for geometry, full_width, material, bridge in road_lines(root, london):
        clipped = transform(geometry, project, interleaved=False).intersection(limits)
        radius = max(0.85, full_width*.5)
        for part in getattr(clipped, "geoms", [clipped]):
            if part.geom_type != "LineString":
                continue
            points = list(part.simplify(.28).coords)
            for a, b in zip(points, points[1:]):
                count = max(1, math.ceil(math.dist(a, b)/ROAD_CELL))
                for i in range(count):
                    u, v = (tuple(x+(y-x)*t/count for x,y in zip(a,b)) for t in (i,i+1))
                    lo = [max(0, math.floor((min(x,y)-r-base)/ROAD_CELL))
                          for x,y,base,r in zip(u,v,(west,south),(radius+12,)*2)]
                    hi = [min(n-1, math.floor((max(x,y)+r-base)/ROAD_CELL))
                          for x,y,base,r,n in zip(u,v,(west,south),(radius+12,)*2,(width,height))]
                    segment = [*(encode(c, "f") for c in (*u,*v,radius)), material | (4 if bridge else 0)]
                    for y in range(lo[1],hi[1]+1):
                        for x in range(lo[0],hi[0]+1):
                            cells.setdefault(y*width+x, []).extend(segment)
    for cell, entries in cells.items():
        at = index+2+cell*2
        words[at:at+2] = [len(words),len(words)+len(entries)]
        words.extend(entries)
    return index


def write(root, output):
    words = [0] * (len(SITES)*11)
    for index, (origin, extent, source) in enumerate(SITES):
        values, shapes, valid = sections(root, origin, extent, source)
        west, south, east, north = values[4:]
        rows = [[] for _ in range(math.ceil((north-south)/BAND_HEIGHT))]

        def add_rings(parts, flag):
            for part in parts:
                for ring in [part.exterior, *part.interiors]:
                    points = list(ring.coords)
                    for a, b in zip(points, points[1:]):
                        if a[1] == b[1]:
                            continue
                        a, b = sorted((a, b), key=lambda p:p[1])
                        lo = max(0, math.floor((a[1]-south)/BAND_HEIGHT))
                        hi = min(len(rows)-1, math.floor((b[1]-south)/BAND_HEIGHT))
                        edge = [*(encode(v, "f") for v in (*a, *b)), flag]
                        for row in rows[lo:hi+1]:
                            row.extend(edge)

        add_rings(shapes, 1)
        # Limit dry overrides to the near-bank corridor. Other lakes, canals
        # and the riparian land use continue to come from the global layers.
        corridor = union_all(shapes).buffer(45, quad_segs=2).intersection(valid).simplify(1.0, preserve_topology=True)
        add_rings([p for p in getattr(corridor, "geoms", [corridor]) if p.geom_type == "Polygon"], 2)
        start = len(words)
        words[index*10:(index+1)*10] = [*(encode(v, "f") for v in values), start, len(rows)]
        words.extend([0] * (2*len(rows)))
        for i, row in enumerate(rows):
            words[start+2*i:start+2*i+2] = [len(words), len(words)+len(row)]
            words.extend(row)
        print(f"{source}: {len(shapes)} water polygons, {sum(len(p.interiors) for p in shapes)} interior rings")
        words[20+index] = pack_roads(root,words,valid,values,index==1)
    payload = struct.pack(f"<{len(words)}I", *words)
    output.write_bytes(zstandard.ZstdCompressor(level=9).compress(payload))


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("sources", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    write(args.sources, args.output)
