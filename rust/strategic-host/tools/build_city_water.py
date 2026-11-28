"""Build the existing Paris and London street index from retained road sources."""
from argparse import ArgumentParser
import json
import math
from pathlib import Path
import struct

from shapely import box, transform
from shapely.geometry import LinearRing, Polygon, shape
import zstandard

from apply_london_city_roads import CROSSINGS, DATE, DATE_PREFIX, surveyed_roads


SITES = (
    ((2.34, 48.855), (2.24, 48.80, 2.46, 48.915), "paris_reference/water.geojson"),
    ((-0.12, 51.506), (-0.32, 51.44, 0.14, 51.54), "london_1890s/thames-presentation-union.geojson"),
)
LONDON_ROAD_EXTENT = (-.371, 51.371, .104, 51.638)
METRES = 6371008.8 * math.pi / 180
ROAD_CELL = 64
# Pixel footprints at the end of each blend band, in metres.
ROAD_LEVELS = ((1, 128, 42.), (2, 256, 86.), (3, 384, 175.))


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


def projected_bounds(origin, extent):
    lon, lat = origin
    x_scale = METRES * math.cos(math.radians(lat))
    west, south, east, north = extent
    return [lon, lat, x_scale, METRES, (west-lon)*x_scale, (south-lat)*METRES,
            (east-lon)*x_scale, (north-lat)*METRES]


def sections(root, origin, extent, source):
    values = projected_bounds(origin, extent)
    lon, lat, x_scale, y_scale = values[:4]
    project = lambda x, y: ((x-lon)*x_scale, (y-lat)*y_scale)
    limits = box(*values[4:])
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
    return values, drawn, limits


def road_lines(root, london):
    if london:
        from shapely.geometry import LineString
        styles = {"trunk": (12, 3), "primary": (10, 3), "secondary": (8, 2), "tertiary": (6, 2),
                  "residential": (5.5, 1), "living_street": (5., 1), "unclassified": (5.5, 1),
                  "service": (2.8, 1), "pedestrian": (3.5, 1), "footway": (1.7, 0), "path": (1.3, 0),
                  "track": (2.5, 0), "bridleway": (2.2, 0), "steps": (1.3, 0), "stairs": (1.3, 0)}
        road_file = root / "london_1890s/ohm-dated-roads.json"
        export = json.loads(road_file.read_text(encoding="utf-8-sig"))
        surveyed = {feature_id for _, feature_id, _, _ in surveyed_roads(export)}
        for row in export["elements"]:
            tags, feature_id = row["tags"], row["id"]
            style = styles.get(tags.get("highway"))
            start, end = tags.get("start_date", ""), tags.get("end_date", "")
            if feature_id not in surveyed and (
                    style is None or not tags.get("source") or "Bing" in tags["source"]
                    or not DATE_PREFIX.fullmatch(start) or start > DATE or start in {"1900", "1900-01"}
                    or end and (not DATE_PREFIX.fullmatch(end) or end <= DATE)
                    or tags.get("license") not in {None, "CC0", "CC0-1.0"}
                    or tags.get("tunnel") not in {None, "no", "building_passage"}):
                continue
            points = [(node["lon"], node["lat"]) for node in row["geometry"]]
            if len(points) < 2:
                continue
            width, rank = style or (3.5, 1)
            surface = tags.get("surface")
            material = 0 if surface in {"unpaved", "earth", "dirt", "ground"} else 1 if surface in {
                "gravel", "fine_gravel", "compacted"} or rank == 0 else 2
            bridge = feature_id in surveyed and (
                feature_id in CROSSINGS or tags.get("bridge") not in (None, "no", "false", "0"))
            if bridge:
                width, rank = max(width, 7.), max(rank, 2)
            yield f"ohm:way:{feature_id}", LineString(points), width, material, bridge, rank
    else:
        road_file = root / "paris_1900_ptm/PTM_Paris1900_rues_epsg4326.geojson"
        for row in json.loads(road_file.read_text(encoding="utf-8-sig"))["features"]:
            fields = row["properties"]
            if fields.get("fictif") == "Oui" or not row.get("geometry"):
                continue
            width = float(fields.get("largeur") or 4)
            kind = (fields.get("typvoie") or "").casefold()
            bridge = fields.get("franchisst") == "Pont"
            major = bridge or kind in {"avenue", "boulevard", "quai", "pont", "route", "grande avenue"}
            path = kind in {"sentier", "passage", "ruelle", "galerie", "cour", "peristyle"}
            rank = 3 if major else 0 if path else 2 if width >= 12 else 1
            material = 0 if kind == "sentier" else 2 if width >= 5 or kind in {"rue", "quai", "pont"} else 1
            yield (f"ptm:road:{fields['id_ptm']}", shape(row["geometry"]),
                   min(width, 28.), material, bridge, rank)


def prepared_roads(root, limits, values, london, *, classified=False):
    lon, lat, x_scale, y_scale = values[:4]
    project = lambda x, y: ((x-lon)*x_scale, (y-lat)*y_scale)
    for feature_id, geometry, full_width, material, bridge, rank in road_lines(root, london):
        clipped = transform(geometry, project, interleaved=False).intersection(limits)
        lines = [part.simplify(.28) for part in getattr(clipped, "geoms", [clipped])
                 if part.geom_type == "LineString" and not part.is_empty]
        if lines:
            road = (feature_id, lines, max(.85, full_width*.5), material, bridge)
            yield (*road, rank) if classified else road


def pack_road_cells(words, values, roads, cell_size, *, minimum_rank=0, padding=12., simplify=0.):
    west, south, east, north = values[4:]
    width, height = math.ceil((east-west)/cell_size), math.ceil((north-south)/cell_size)
    index = len(words)
    words.extend([width, height] + [0]*(2*width*height))
    cells = {}
    for _, lines, radius, material, bridge, rank in roads:
        if rank < minimum_rank:
            continue
        for part in lines:
            points = list(part.simplify(simplify).coords if simplify else part.coords)
            for a, b in zip(points, points[1:]):
                count = max(1, math.ceil(math.dist(a, b)/cell_size))
                for i in range(count):
                    u, v = (tuple(x+(y-x)*t/count for x,y in zip(a,b)) for t in (i,i+1))
                    reach = radius + padding
                    lo = [max(0, math.floor((min(x,y)-reach-base)/cell_size))
                          for x,y,base in zip(u,v,(west,south))]
                    hi = [min(n-1, math.floor((max(x,y)+reach-base)/cell_size))
                          for x,y,base,n in zip(u,v,(west,south),(width,height))]
                    segment = [*(encode(c, "f") for c in (*u,*v,radius)), material | (4 if bridge else 0) | (rank << 3)]
                    for y in range(lo[1],hi[1]+1):
                        for x in range(lo[0],hi[0]+1):
                            cells.setdefault(y*width+x, []).extend(segment)
    for cell, entries in cells.items():
        at = index+2+cell*2
        words[at:at+2] = [len(words),len(words)+len(entries)]
        words.extend(entries)
    return index


def pack_road_levels(words, values, roads, fine_cell, offsets):
    fine = pack_road_cells(words, values, roads, fine_cell)
    for offset, (rank, cell_size, padding) in zip(offsets, ROAD_LEVELS, strict=True):
        words[offset] = pack_road_cells(words, values, roads, cell_size, minimum_rank=rank,
                                        padding=padding, simplify=.8)
    return fine


def write(root, output):
    words = [0] * 29
    for index, (origin, extent, _) in enumerate(SITES):
        values = projected_bounds(origin, extent)
        # Older readers clamp to the last band. One empty band lets them fall back to QWG.
        start = len(words)
        words[index*10:(index+1)*10] = [*(encode(v, "f") for v in values), start, 1]
        words.extend((start+2, start+2))
        if index == 1:
            values = projected_bounds(origin, LONDON_ROAD_EXTENT)
            words[28] = len(words)
            words.extend(encode(v, "f") for v in values)
        valid = box(*values[4:])
        roads = list(prepared_roads(root, valid, values, index == 1, classified=True))
        words[20+index] = pack_road_levels(words, values, roads, ROAD_CELL, range(22+index*3, 25+index*3))
    payload = struct.pack(f"<{len(words)}I", *words)
    output.write_bytes(zstandard.ZstdCompressor(level=9).compress(payload))


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("sources", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    write(args.sources, args.output)
