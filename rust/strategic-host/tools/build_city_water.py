"""Build the local Seine and Thames banks and streets from retained vector sources."""
from argparse import ArgumentParser
import json
import math
from pathlib import Path
import struct

from shapely import box, transform, union_all
from shapely.geometry import LinearRing, Polygon, shape
import zstandard

from apply_london_city_roads import CROSSINGS, DATE, DATE_PREFIX, surveyed_roads


SITES = (
    ((2.34, 48.855), (2.24, 48.80, 2.46, 48.915), "paris_reference/water.geojson"),
    ((-0.12, 51.506), (-0.32, 51.44, 0.14, 51.54), "london_1890s/thames-presentation-union.geojson"),
)
LONDON_ROAD_EXTENT = (-.371, 51.371, .104, 51.638)
METRES = 6371008.8 * math.pi / 180
BAND_HEIGHT = 32
ROAD_CELL = 64
ROAD_PAGE_METRES = 4096.
ROAD_PAGE_BYTES = 1024 * 1024
ROAD_SUPPORT_STEP = 16.
ROAD_SUPPORT_SIDE = 258
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


def pack_road_levels(words, values, roads, fine_cell, offsets, *, simplify=.8):
    fine = pack_road_cells(words, values, roads, fine_cell)
    for offset, (rank, cell_size, padding) in zip(offsets, ROAD_LEVELS, strict=True):
        words[offset] = pack_road_cells(words, values, roads, cell_size, minimum_rank=rank,
                                        padding=padding, simplify=simplify)
    return fine


def pack_water_bands(words, south, north, layers):
    rows = [[] for _ in range(math.ceil((north-south)/BAND_HEIGHT))]
    for shapes, flag in layers:
        for part in shapes:
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
    start = len(words)
    words.extend([0] * (2*len(rows)))
    for i, row in enumerate(rows):
        words[start+2*i:start+2*i+2] = [len(words), len(words)+len(row)]
        words.extend(row)
    return start, len(rows)


def pack_road_support(words, west, south, layers):
    from affine import Affine
    import numpy as np
    from rasterio.features import rasterize

    step, side = ROAD_SUPPORT_STEP, ROAD_SUPPORT_SIDE
    affine = Affine(step, 0, west-step, 0, step, south-step)
    grid = np.zeros((side, side), dtype=np.uint32)
    for channel, polygon in enumerate(layers):
        if polygon.is_empty:
            continue
        shapes = [(polygon, 48)]
        for inset, weight in ((12., 112), (24., 191), (36., 255)):
            interior = polygon.buffer(-inset)
            if not interior.is_empty:
                shapes.append((interior, weight))
        mask = rasterize(shapes, out_shape=(side, side), transform=affine, dtype="uint8")
        grid |= mask.astype(np.uint32) << (8*channel)
    words[12] = len(words)
    words.extend(grid.ravel().tolist())


def planned_road_pages(plan):
    """Encode bounded display pages from the same CRS84 road features as the city plan."""
    lon, lat = plan["wwo"]["origin"]
    x_scale, y_scale = METRES * math.cos(math.radians(lat)), METRES
    if x_scale < 100.:
        raise ValueError("Road plan origin is too close to a pole")
    width = ROAD_PAGE_METRES
    sources = []
    pages = {}
    water = {}
    support = {}
    road_geometry = {}
    def project(feature):
        return transform(shape(feature["geometry"]), lambda x, y: ((x-lon)*x_scale, (y-lat)*y_scale),
                         interleaved=False)

    for feature in sorted(plan["features"], key=lambda row: row["id"]):
        props = feature["properties"]
        if props["kind"] == "road_coverage":
            categories, state = props.get("categories"), props.get("coverage_state")
            if (type(categories) is not int or categories not in (1, 2, 3)
                or state not in ("mapped_network", "confirmed_empty") or not props.get("coverage_basis")):
                raise ValueError(f"Road coverage needs categories, state and evidence for {feature['id']}")
            support[feature["id"]] = (categories, state, project(feature), props["source"])
            sources.append(feature)
            continue
        if props["kind"] in ("water_surface", "known_dry"):
            flag = 2 if props["kind"] == "known_dry" else {"river": 1, "coast": 4}.get(props.get("basin"))
            if flag is None:
                raise ValueError(f"Invalid historical basin for {feature['id']}")
            geom = project(feature)
            sources.append(dict(id=feature["id"], geometry=feature["geometry"], properties=props))
            west, south, east, north = geom.bounds
            for x in range(math.floor(west/width), math.ceil(east/width)):
                for y in range(math.floor(south/width), math.ceil(north/width)):
                    clipped = geom.intersection(box(x*width,y*width,(x+1)*width,(y+1)*width))
                    if clipped.area > 0.:
                        water.setdefault((x,y), []).append((feature["id"], flag, clipped))
            continue
        if props["kind"] != "road":
            continue
        category = props.get("display_rank", 1)
        surface = props.get("display_surface", "gravel")
        surface_index = {"dirt": 0, "gravel": 1, "setts": 2}.get(surface)
        if type(category) is not int or not 0 <= category <= 3 or surface_index is None:
            raise ValueError(f"Invalid road style for {feature['id']}")
        bridge = bool(props.get("bridge_reference"))
        year = props.get("source_year")
        if type(year) is not int or not all(props.get(k) for k in ("width_basis", "surface_basis")):
            raise ValueError(f"Road alignment, width and surface need a dated record for {feature['id']}")
        geom = project(feature)
        road_geometry[feature["id"]] = (1 if category < 2 else 2, geom, props["source"])
        source = dict(id=feature["id"], geometry=feature["geometry"], properties=props)
        sources.append(source)
        west, south, east, north = geom.bounds
        radius = float(props["width_m"]) / 2
        apron = ROAD_LEVELS[-1][2] + radius
        for x in range(math.floor((west-apron)/width), math.floor((east+apron)/width)+1):
            for y in range(math.floor((south-apron)/width), math.floor((north+apron)/width)+1):
                clipping = box(x*width, y*width, (x+1)*width, (y+1)*width).buffer(apron, quad_segs=1)
                clipped = geom.intersection(clipping)
                lines = [part for part in getattr(clipped, "geoms", [clipped]) if part.geom_type == "LineString" and part.length > 0.]
                if lines:
                    pages.setdefault((x, y), []).append((feature["id"], lines, radius, surface_index, bridge, category))

    support_pages = {}
    for key, (categories, state, geom, source) in support.items():
        for category in (1, 2):
            if not categories & category:
                continue
            intersections = [mapped_source for mask, line, mapped_source in road_geometry.values()
                             if mask & category and line.intersection(geom).length > 0.5]
            if state == "confirmed_empty" and intersections:
                raise ValueError(f"Road contradicts confirmed empty coverage {key}")
            if state == "mapped_network" and source not in intersections:
                raise ValueError(f"Covered road network lacks a route from the coverage source: {key}")
        west, south, east, north = geom.bounds
        margin = ROAD_SUPPORT_STEP
        west, south, east, north = west-margin, south-margin, east+margin, north+margin
        for x in range(math.floor(west/width), math.ceil(east/width)):
            for y in range(math.floor(south/width), math.ceil(north/width)):
                extent = box(x*width-margin, y*width-margin, (x+1)*width+margin, (y+1)*width+margin)
                if not geom.intersects(extent):
                    continue
                local_categories = categories
                if state == "mapped_network":
                    mapped = 0
                    for road in pages.get((x, y), []):
                        mask, line, mapped_source = road_geometry[road[0]]
                        if mapped_source == source and line.intersects(geom):
                            mapped |= mask
                    local_categories &= mapped
                if local_categories:
                    support_pages.setdefault((x, y), {})[key] = local_categories
    packed = []
    cells = [(x, y, False) for x, y in pages.keys() | support_pages.keys()] + [(x, y, True) for x, y in water]
    for x, y, wet_page in sorted(cells):
        west, south, east, north = x*width, y*width, (x+1)*width, (y+1)*width
        values = [lon, lat, x_scale, y_scale, west, south, east, north]
        roads = [] if wet_page else pages.get((x, y), [])
        wet = water[x, y] if wet_page else []
        support_ids = [] if wet_page else sorted(support_pages.get((x, y), []))
        words = [*(encode(v, "f") for v in values), 0, 0, 0, 0]
        if wet_page:
            words.append(0)
            layers = []
            for flag in (1, 2, 4):
                merged = union_all([geom for _, kind, geom in wet if kind == flag])
                layers.append(([part for part in getattr(merged, "geoms", [merged])
                                if part.geom_type == "Polygon" and not part.is_empty], flag))
            start, height = pack_water_bands(words, south, north, layers)
            for i in range(height):
                a, b = words[start+2*i:start+2*i+2]
                if b-a > 5*192:
                    raise ValueError(f"City shoreline band exceeds 192 edges in {x},{y}")
            words[12] = start
        else:
            if support_ids:
                words.extend([0, 0])
            if roads:
                words[8] = pack_road_levels(words, values, roads, ROAD_CELL, (9, 10, 11), simplify=0.)
            if support_ids:
                # The margin preserves the same samples on both sides of a page seam.
                margin = ROAD_SUPPORT_STEP + 36.
                extent = box(west-margin, south-margin, east+margin, north+margin)
                layers = [union_all([support[key][2].intersection(extent)
                                     for key, categories in support_pages[x, y].items()
                                     if support[key][1] == state and categories & category])
                          for state in ("mapped_network", "confirmed_empty") for category in (1, 2)]
                pack_road_support(words, west, south, layers)
        if len(words)*4 > ROAD_PAGE_BYTES:
            raise ValueError(f"Road page {x},{y} exceeds {ROAD_PAGE_BYTES} bytes")
        bounds = [lon+west/x_scale, lat+south/y_scale, lon+east/x_scale, lat+north/y_scale]
        if not -180. <= bounds[0] < bounds[2] <= 180. or not -90. <= bounds[1] < bounds[3] <= 90.:
            raise ValueError(f"Road page {x},{y} crosses a world seam")
        payload = struct.pack(f"<{len(words)}I", *words)
        packed.append((x, y, bounds, payload, sorted({r[0] for r in roads}), sorted({r[0] for r in wet}), support_ids))
    return sources, packed


def write(root, output):
    words = [0] * 29
    for index, (origin, extent, source) in enumerate(SITES):
        values, shapes, valid = sections(root, origin, extent, source)
        west, south, east, north = values[4:]
        # Limit dry overrides to the near-bank corridor. Other lakes, canals
        # and the riparian land use continue to come from the global layers.
        corridor = union_all(shapes).buffer(45, quad_segs=2).intersection(valid).simplify(1.0, preserve_topology=True)
        dry = [p for p in getattr(corridor, "geoms", [corridor]) if p.geom_type == "Polygon"]
        start, height = pack_water_bands(words, south, north, [(shapes, 1), (dry, 2)])
        words[index*10:(index+1)*10] = [*(encode(v, "f") for v in values), start, height]
        print(f"{source}: {len(shapes)} water polygons, {sum(len(p.interiors) for p in shapes)} interior rings")
        if index == 1:
            # The dated street survey extends beyond the Thames bank redraw.
            lon, lat, x_scale, y_scale = values[:4]
            left, bottom, right, top = LONDON_ROAD_EXTENT
            valid = box((left-lon)*x_scale, (bottom-lat)*y_scale,
                        (right-lon)*x_scale, (top-lat)*y_scale)
            values = [*values[:4], *valid.bounds]
            words[28] = len(words)
            words.extend(encode(v, "f") for v in values)
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
