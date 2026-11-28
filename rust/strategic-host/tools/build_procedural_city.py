"""Generate local city streets and plots using the formal terrain and transport inputs."""

import math
from functools import cache
from pathlib import Path

import shapely
from shapely.geometry import LineString, Point, box, mapping, shape

from build_city_models import read, roster_city, transform, transforms


ROOT = Path(__file__).resolve().parents[3]
BINDINGS = ROOT / "data/world_map/historical/city_landscape_1900/procedural-inputs.json"
KIT_FILE = ROOT / "assets/settlements/city-kits-1900.json"
DATE = "1900-01-01"
RELIEF_SPACING = 610.0
MAX_STREET_GRADE = 0.12
ROAD_CLIP_MARGIN = 0.05
GEOMETRY_TOLERANCE = 1e-6
ROLES = ("low_home", "street_row", "courtyard_home", "shop", "civic", "warehouse", "workshop",
         "transport_auxiliary")


def in_period(row):
    return row["valid_from"] <= DATE < row["valid_to"]


def official_inputs(city, transport_data):
    city_id = city["city_id"]
    binding = read(BINDINGS).get(city_id)
    if not binding or not binding.get("pilot"):
        raise ValueError(f"City is outside the current procedural pilot: {city_id}")
    kit = next(row for row in read(KIT_FILE) if row["id"] == binding["kit"])
    if "shard" not in binding:
        return kit, binding, [], [], {}
    shard = read(transport_data / binding["shard"])
    metadata = shard["metadata"]
    if (binding["place"] not in city["existing_place_ids"]
            or metadata["anchor_place_id"] != binding["place"] or not in_period(metadata)):
        raise ValueError(f"Formal transport shard does not match {city_id} in 1900")
    facts = {fact["subject_id"]: fact["value"] for fact in shard["evidence_catalog"]["facts"]}
    anchors, rail_corridors = [], {}
    for pair in binding.get("rail", []):
        station, corridor = (facts[name] for name in (pair["station"], pair["corridor"]))
        if (not in_period(station) or not in_period(corridor)
                or station.get("source_type") != "HISTORICAL_EVIDENCE"
                or station.get("transport_symbol") != "station"
                or station["geometry"]["type"] != "Point"
                or corridor.get("kind") != "rail"
                or binding["place"] not in corridor["places"]):
            raise ValueError(f"Invalid formal railway reference for {pair['station']}")
        geometry = shape(corridor["geometry"])
        if geometry.is_empty or geometry.geom_type not in {"LineString", "MultiLineString"}:
            raise ValueError(f"Invalid formal railway geometry for {pair['corridor']}")
        rail_corridors[pair["corridor"]] = geometry
        anchors.append({
            "mode": "rail",
            "station_id": pair["station"],
            "point": station["geometry"]["coordinates"],
            "coordinate_role": station["coordinate_role"],
            "coordinate_uncertainty_m": station["coordinate_uncertainty_m"],
            "station_source_id": station["source_id"],
            "corridor_id": pair["corridor"],
            "line_id": corridor["line_id"],
            "corridor_geometry_status": corridor["geometry_status"],
            "corridor_uncertainty_m": corridor["estimated_spatial_error_m"],
            "corridor_historical_source": corridor["historical_source"],
        })
    for mode in ("main_road", "port"):
        for node_id in binding.get(mode, []):
            node = facts[node_id]
            if (node["geometry"]["type"] != "Point" or not in_period(node)
                    or node.get("source_type") != "HISTORICAL_EVIDENCE"
                    or node.get("transport_symbol") != mode):
                raise ValueError(f"Invalid formal {mode} node for {city_id}: {node_id}")
            anchors.append({"mode": mode, "node_id": node_id, "point": node["geometry"]["coordinates"],
                            "source_id": node["source_id"]})
    return kit, binding, anchors, metadata.get("landmark_visuals", []), rail_corridors


def street_width(index):
    return 15.0 if index % 5 == 0 else 7.0


def polygonal(geometry):
    if geometry.geom_type in {"Polygon", "MultiPolygon"}:
        return geometry
    return shapely.union_all([part for part in shapely.get_parts(geometry)
                              if part.geom_type in {"Polygon", "MultiPolygon"}])


def maximum_covered_grade(footprint, cell_grade):
    """Include every relief cell that touches the footprint."""
    left, bottom, right, top = footprint.bounds
    spacing = RELIEF_SPACING
    columns = range(math.ceil(left / spacing - 0.5), math.floor(right / spacing + 0.5) + 1)
    rows = range(math.ceil(bottom / spacing - 0.5), math.floor(top / spacing + 0.5) + 1)
    half = spacing / 2.0
    return max(
        cell_grade(column, row)
        for column in columns
        for row in rows
        if footprint.intersects(box(column * spacing - half, row * spacing - half,
                                    column * spacing + half, row * spacing + half))
    )


def waterfront_blocks(candidates, wet, block_size, reference, count):
    """Select a connected dry block group at a substantial QWG water edge."""
    shore_water = shapely.union_all([part for part in shapely.get_parts(wet) if part.area >= block_size**2])
    if shore_water.is_empty:
        return []
    waterfront = shore_water.buffer(block_size)
    shapely.prepare(waterfront)
    shore = {cell: block for cell, block in candidates.items() if waterfront.intersects(block)}
    if not shore:
        return []

    def priority(cell):
        block = shore[cell]
        return block.distance(reference), block.distance(shore_water), cell

    connected = []
    bordering = {min(shore, key=priority)}
    while bordering and len(connected) < count:
        cell = min(bordering, key=priority)
        bordering.remove(cell)
        block = shore.pop(cell)
        coast = Point(shapely.shortest_line(block.representative_point(), shore_water).coords[-1])
        connected.append((cell, coast))
        i, j = cell
        bordering.update(near for near in ((i - 1, j), (i + 1, j), (i, j - 1), (i, j + 1))
                         if near in shore and block.intersection(shore[near]).length > GEOMETRY_TOLERANCE)
    return connected


def service_buildings(parcel, towards, role, obstacles, backward):
    """Place the existing Kit role along a service frontage inside the dry parcel."""
    center = parcel.centroid
    dx, dy = towards.x - center.x, towards.y - center.y
    horizontal = abs(dy) >= abs(dx)
    left, bottom, right, top = parcel.bounds
    if horizontal:
        start, end, near, far = (left, right, top, bottom) if dy >= 0 else (left, right, bottom, top)
        angle = 0.0 if dy >= 0 else math.pi
    else:
        start, end, near, far = (bottom, top, right, left) if dx >= 0 else (bottom, top, left, right)
        angle = -math.pi / 2 if dx >= 0 else math.pi / 2
    count = 1 if role == "transport_auxiliary" else 3
    plot_width = (end - start - 8.0) / count
    width = min(plot_width - 3.0, 32.0)
    depth = min(abs(near - far) - 16.0, 20.0 if count == 1 else 36.0)
    if min(width, depth) < 8.0:
        return
    setback = 12.0 if role == "transport_auxiliary" else 5.0
    across = near + math.copysign(depth / 2 + setback, far - near)
    for lot in range(count):
        along = start + 4.0 + (lot + 0.5) * plot_width
        x, y = (along, across) if horizontal else (across, along)
        half_x, half_y = (width / 2, depth / 2) if horizontal else (depth / 2, width / 2)
        footprint = box(x - half_x, y - half_y, x + half_x, y + half_y)
        if not parcel.covers(footprint) or obstacles.intersects(footprint):
            continue
        lon, lat = backward.transform(x, y)
        yield x, y, lon, lat, angle, width, depth, 6.4 if count == 1 else 8.0, ROLES.index(role) + 1


def build_city(city, terrain, transport_data):
    kit, binding, anchors, landmarks, rail_corridors = official_inputs(city, transport_data)
    forward, backward = transforms(city["point"])
    peer = forward.transform(*roster_city(binding["peer"])["point"]) if "peer" in binding else None
    formal_roads = [anchor for anchor in anchors if anchor["mode"] == "main_road"]
    main_road = min(formal_roads, key=lambda anchor: math.hypot(*forward.transform(*anchor["point"])),
                    default=None)
    axis_origin = main_road["point"] if main_road else city["point"]
    offset_x, offset_y = forward.transform(*axis_origin)
    missing = [mode for mode in ("rail", "port", "main_road") if not any(row["mode"] == mode for row in anchors)]
    population = city["selected_observation"]["population_value"]
    # Population sizes the reconstruction. It does not supply a surveyed urban boundary.
    radius = 1_000.0 * math.sqrt(population / (18_000.0 * math.pi))
    spacing_x = 2 * kit["depth_m"][1] + 7 * kit["frontage_m"][1]
    spacing_y = 2 * kit["depth_m"][1] + 6 * kit["frontage_m"][1]
    block_size = max(spacing_x, spacing_y)
    shore_margin = radius + 2.0 * block_size
    extent = backward.transform_bounds(-shore_margin, -shore_margin, shore_margin, shore_margin)
    shoreline_land = terrain.land_geometry(extent)
    city_extent = backward.transform_bounds(-radius, -radius, radius, radius)
    land = transform(shoreline_land.intersection(box(*city_extent)), forward)
    shapely.prepare(land)
    dry_blocks = land.buffer(-7.5)
    # Leave a margin when clipping centerlines, then check the actual full-width strip.
    dry_streets = {width: land.buffer(-width / 2 - ROAD_CLIP_MARGIN) for width in (7.0, 15.0)}
    # The search window is inside the QWG query. Its artificial edge cannot be a shore.
    water_window = radius + block_size
    wet = box(-water_window, -water_window, water_window, water_window).difference(
        transform(shoreline_land, forward))

    guards = {}
    for landmark in landmarks:
        if in_period(landmark) and landmark.get("model_footprint_m"):
            point = landmark.get("display_lon_lat", landmark["geometry"]["coordinates"])
            center = Point(*forward.transform(*point))
            guards[landmark["id"]] = center.buffer(math.hypot(*landmark["model_footprint_m"]) / 2.0)
    guarded = shapely.union_all(list(guards.values()))
    shapely.prepare(guarded)

    @cache
    def height(x, y):
        return terrain.elevation(*backward.transform(x, y))

    @cache
    def cell_grade(column, row):
        # The QPK grid cannot resolve individual street grades.
        nx = column * RELIEF_SPACING
        ny = row * RELIEF_SPACING
        half = RELIEF_SPACING / 2.0
        return math.hypot(height(nx + half, ny) - height(nx - half, ny),
                          height(nx, ny + half) - height(nx, ny - half)) / RELIEF_SPACING

    features = []

    def feature(geometry, kind, **properties):
        features.append({"type": "Feature", "geometry": mapping(transform(geometry, backward)),
                         "properties": {"kind": kind, **properties}})

    def street_point(node):
        return offset_x + node[0] * spacing_x, offset_y + node[1] * spacing_y

    def parcel_bounds(i, j):
        x, y = street_point((i, j))
        right, top = street_point((i + 1, j + 1))
        return (x + street_width(i) / 2, y + street_width(j) / 2,
                right - street_width(i + 1) / 2, top - street_width(j + 1) / 2)

    cells, roads = {}, {}
    for i in range(-math.ceil(radius / spacing_x), math.ceil(radius / spacing_x)):
        for j in range(-math.ceil(radius / spacing_y), math.ceil(radius / spacing_y)):
            x, y = offset_x + i * spacing_x, offset_y + j * spacing_y
            cx, cy = x + spacing_x / 2, y + spacing_y / 2
            distance = math.hypot(cx, cy)
            half_diagonal = math.hypot(spacing_x, spacing_y) / 2
            if distance > radius or (peer and math.hypot(cx - peer[0], cy - peer[1]) < distance + half_diagonal):
                continue
            block = box(x, y, *street_point((i + 1, j + 1)))
            footprint = block.buffer(7.5)
            if not land.covers(footprint):
                block = polygonal(block.intersection(dry_blocks))
                if block.is_empty:
                    continue
                footprint = block.buffer(7.5)
            if guarded.intersects(block):
                continue
            slope = maximum_covered_grade(footprint, cell_grade)
            if slope > MAX_STREET_GRADE:
                continue
            parcel = polygonal(block.intersection(box(*parcel_bounds(i, j))))
            if parcel.is_empty:
                continue
            cells[i, j] = (block, parcel, distance, slope)
            corners = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            for first, second in zip(corners, corners[1:] + corners[:1]):
                edge = tuple(sorted((first, second)))
                roads[edge] = street_width(first[0] if first[0] == second[0] else first[1])

    if not cells:
        raise ValueError(f"No buildable QWG land and QPK relief for {city['city_id']}")

    street_segments = {}
    for (first, second), width in roads.items():
        line = LineString([street_point(first), street_point(second)])
        main_axis = first[1] == second[1] == 0
        full_width = line.buffer(width / 2, cap_style="flat")
        pieces = [line] if land.covers(full_width) else shapely.get_parts(line.intersection(dry_streets[width]))
        segments = []
        for piece in pieces:
            if piece.geom_type != "LineString" or piece.length <= ROAD_CLIP_MARGIN:
                continue
            full_width = piece.buffer(width / 2, cap_style="flat")
            if (not land.covers(full_width) or guarded.intersects(full_width)
                    or maximum_covered_grade(full_width, cell_grade) > MAX_STREET_GRADE):
                continue
            feature(piece, "road", width_m=width,
                    role="layout_axis" if main_axis else "district" if width > 7 else "local")
            segments.append(piece)
        street_segments[first, second] = segments

    access_clearance = []
    connected_rail = {}
    for anchor in anchors:
        target = Point(*forward.transform(*anchor["point"]))
        candidates = set()
        for segments in street_segments.values():
            for segment in segments:
                if segment.distance(target) <= 3 * block_size:
                    candidates.update((segment.coords[0], segment.coords[-1],
                                       segment.interpolate(segment.project(target)).coords[0]))
        usable_nodes = sorted(candidates, key=lambda point: (Point(point).distance(target), point))
        anchor_id = anchor.get("station_id", anchor.get("node_id"))
        own_guard = guards.get(anchor_id)
        other_guards = shapely.union_all([guard for key, guard in guards.items() if key != anchor_id])
        anchor["access_status"] = "no_buildable_approach"
        for point in usable_nodes:
            node = Point(point)
            if node.distance(target) <= GEOMETRY_TOLERANCE:
                anchor["access_status"] = "at_generated_junction"
                break
            approach = LineString([node, target])
            if approach.length > 3 * block_size:
                break
            if own_guard is not None:
                approach = approach.difference(own_guard)
            if (approach.is_empty or approach.geom_type != "LineString"
                    or approach.distance(node) > GEOMETRY_TOLERANCE):
                continue
            clearance = approach.buffer(3.5, cap_style="flat")
            if (not land.covers(clearance) or other_guards.intersects(clearance)
                    or maximum_covered_grade(clearance, cell_grade) > MAX_STREET_GRADE):
                continue
            access_clearance.append(clearance)
            feature(approach, "road", width_m=7.0, role="transport_approach", anchor_id=anchor_id)
            anchor["access_status"] = "simulated_approach"
            break
        feature(target, "transport_anchor", **anchor)
        if anchor["mode"] == "rail" and anchor["access_status"] != "no_buildable_approach":
            connected_rail[anchor_id] = target

    local_corridors = {key: transform(geometry, forward) for key, geometry in rail_corridors.items()}
    # A display clearance around the bounded reference, with its source uncertainty retained.
    rail_clearance = [line.buffer(12.0) for line in local_corridors.values()]
    clearance = shapely.union_all([*access_clearance, *rail_clearance])
    shapely.prepare(clearance)
    edge = [cell for cell, (block, _, distance, _) in cells.items()
            if distance >= radius * 0.83 and not clearance.intersects(block)]
    if len(edge) < 2:
        raise ValueError(f"No separate buildable industrial and military reserves for {city['city_id']}")
    industry_points = [Point(*forward.transform(*anchor["point"])) for anchor in anchors
                       if anchor["mode"] in {"rail", "port"}]
    if not industry_points:
        industry_points = [Point(offset_x - radius, offset_y)]
    industry = min(edge, key=lambda cell: min(
        cells[cell][0].distance(point) for point in industry_points
    ))
    military = min((cell for cell in edge if cell != industry), key=lambda cell: (
        cells[cell][3], -cells[cell][0].distance(cells[industry][0]), cell,
    ))
    reserves = {industry: "reserved_industrial", military: "reserved_military"}

    service = {}
    available = {cell: block for cell, (block, _, _, _) in cells.items()
                 if cell not in reserves and not clearance.intersects(block)}
    formal_port = min((anchor for anchor in anchors if anchor["mode"] == "port"),
                      key=lambda anchor: math.hypot(*forward.transform(*anchor["point"])), default=None)
    shore_reference = Point(*forward.transform(*formal_port["point"])) if formal_port else Point(offset_x, offset_y)
    shore_source = {"kind": "qwg_shore",
                    "guidance": "formal_port_reference" if formal_port else
                    "formal_main_road_node" if main_road else "frozen_city_point_axis"}
    if formal_port or main_road:
        shore_source["node_id"] = (formal_port or main_road)["node_id"]
    for cell, coast in waterfront_blocks(available, wet, block_size,
                                         shore_reference, min(6, 1 + math.ceil(math.sqrt(population / 100_000)))):
        service[cell] = ("waterfront_storage", "warehouse", coast, shore_source)

    for anchor in anchors:
        if anchor["mode"] != "rail":
            continue
        station_id, corridor_id = anchor["station_id"], anchor["corridor_id"]
        corridor = local_corridors[corridor_id]
        station = connected_rail.get(station_id)
        if station is not None:
            front = min((cell for cell in available if cell not in service
                         and available[cell].distance(station) <= block_size),
                        key=lambda cell: (available[cell].distance(station), cell), default=None)
            if front is not None:
                source = {"kind": "formal_rail_station_reference", "station_id": station_id,
                          "uncertainty_m": anchor["coordinate_uncertainty_m"]}
                service[front] = ("station_forecourt", "transport_auxiliary", station, source)
        industry_blocks = sorted((cell for cell in available if cell not in service
                                  and available[cell].distance(corridor) <= 2 * block_size),
                                 key=lambda cell: (available[cell].distance(corridor),
                                                   available[cell].distance(Point(offset_x, offset_y)), cell))
        for cell in industry_blocks[:2]:
            toward = Point(shapely.shortest_line(available[cell].centroid, corridor).coords[-1])
            source = {"kind": "formal_rail_corridor_reference", "corridor_id": corridor_id,
                      "uncertainty_m": anchor["corridor_uncertainty_m"]}
            service[cell] = ("rail_industry", "workshop", toward, source)

    def placements():
        for (i, j), (block, parcel, distance, slope) in cells.items():
            left, bottom, right, top = parcel_bounds(i, j)
            if (i, j) in reserves:
                point = parcel.representative_point()
                reserve = {"type": reserves[i, j], "availability": "unallocated",
                           "point": list(backward.transform(point.x, point.y)),
                           "heading_degrees": 90.0, "capacity_m2": round(parcel.area)}
                reserve_metadata.append(reserve)
                feature(parcel, "landuse", use=reserve["type"], coarse_grade=round(slope, 4),
                        **{key: value for key, value in reserve.items() if key != "type"})
                continue
            if (i, j) in service:
                use, role, towards, source = service[i, j]
                rows = list(service_buildings(parcel, towards, role, clearance, backward))
                if rows:
                    feature(parcel, "landuse", use=use, source=source, status="simulated_layout",
                            coarse_grade=round(slope, 4))
                    yield from rows
                    continue
            if clearance.intersects(parcel):
                parcel = polygonal(parcel.difference(clearance))
                if parcel.is_empty:
                    continue
            shapely.prepare(parcel)
            feature(parcel, "block", role="street_frontage", coarse_grade=round(slope, 4))
            maximum_depth = kit["depth_m"][1] + kit["setback_m"][1]
            court = box(left + maximum_depth, bottom + maximum_depth,
                        right - maximum_depth, top - maximum_depth)
            court = polygonal(parcel.intersection(court))
            if not court.is_empty:
                feature(court, "landuse", use="courtyard" if kit["court"] == "enclosed" else "rear_open_space")
            for side, (edge, start, end, front, direction, horizontal, district) in enumerate((
                (((i, j), (i + 1, j)), left, right, bottom, 1, True, j % 5 == 0),
                (((i, j + 1), (i + 1, j + 1)), left, right, top, -1, True, (j + 1) % 5 == 0),
                (((i, j), (i, j + 1)), bottom + maximum_depth, top - maximum_depth, left, 1, False, i % 5 == 0),
                (((i + 1, j), (i + 1, j + 1)), bottom + maximum_depth, top - maximum_depth, right, -1, False, (i + 1) % 5 == 0),
            )):
                segments = street_segments.get(edge, [])
                if not segments:
                    continue
                street_x, street_y = street_point(edge[0])
                frontage_min, frontage_max = kit["frontage_m"]
                target = (frontage_min + frontage_max) / 2
                count = max(1, round((end - start) / target))
                frontage = (end - start) / count
                for lot in range(count):
                    along = start + (lot + 0.5) * frontage
                    variation = ((i * 7 + j * 11 + side * 5 + lot * 3) % 17) / 16
                    depth = kit["depth_m"][0] + variation * (kit["depth_m"][1] - kit["depth_m"][0])
                    setback = kit["setback_m"][0] + variation * (kit["setback_m"][1] - kit["setback_m"][0])
                    inward = front + direction * (setback + depth / 2)
                    x, y = (along, inward) if horizontal else (inward, along)
                    width = min(frontage_max, frontage - 0.2)
                    half_x, half_y = (width / 2, depth / 2) if horizontal else (depth / 2, width / 2)
                    footprint = box(x - half_x, y - half_y, x + half_x, y + half_y)
                    if not parcel.covers(footprint) or clearance.intersects(footprint):
                        continue
                    access = Point(along, street_y) if horizontal else Point(street_x, along)
                    if (not any(segment.distance(access) <= GEOMETRY_TOLERANCE for segment in segments)
                            or not block.covers(LineString([access.coords[0], (x, y)]))):
                        continue
                    floor_count = kit["storeys"][0] + (i + j + side + lot) % (
                        kit["storeys"][1] - kit["storeys"][0] + 1)
                    lon, lat = backward.transform(x, y)
                    if district and lot % 3 == 0:
                        role = "shop"
                    elif distance > radius * 0.8 and variation < 0.5:
                        role = "low_home"
                    elif kit["court"] in {"enclosed", "passage"} and lot % 3 == 1:
                        role = "courtyard_home"
                    else:
                        role = "street_row"
                    if horizontal:
                        angle = math.pi if direction > 0 else 0.0
                    else:
                        angle = direction * math.pi / 2
                    yield x, y, lon, lat, angle, width, depth, floor_count * 3.2, ROLES.index(role) + 1

    reserve_metadata = []
    transport = {
        "shard": binding.get("shard"), "anchors": anchors, "missing": missing,
        "layout_fallback": {"kind": "formal_main_road_node" if main_road else "frozen_city_point_axis",
                            "point": axis_origin, "node_id": main_road["node_id"] if main_road else None,
                            "point_surface": "land" if terrain.water_area(*axis_origin) == 1 else "water",
                            "for_modes": [mode for mode in missing if mode in {"rail", "port"}]},
    }
    metadata = {
        "city_id": city["city_id"], "name": city["name"], "origin": city["point"],
        "population": city["selected_observation"], "kit": kit["id"], "transport": transport,
        "reserves": reserve_metadata, "adjacent_city": binding.get("peer"),
        "method": "Simulated circa-1900 layout. Land comes from QWG. Grades use coarse QPK elevation.",
    }
    return {"type": "FeatureCollection", "wwo": metadata, "features": features}, placements()
