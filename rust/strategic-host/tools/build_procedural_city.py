"""Generate local city streets and plots using the formal terrain and transport inputs."""

import math
from functools import cache
from pathlib import Path

import shapely
from shapely.geometry import LineString, Point, box, mapping

from build_city_models import read, roster_city, transform, transforms


ROOT = Path(__file__).resolve().parents[3]
BINDINGS = ROOT / "data/world_map/historical/city_landscape_1900/procedural-inputs.json"
KIT_FILE = ROOT / "assets/settlements/city-kits-1900.json"
DATE = "1900-01-01"
RELIEF_SPACING = 610.0
MAX_STREET_GRADE = 0.12
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
        return kit, binding, [], []
    shard = read(transport_data / binding["shard"])
    metadata = shard["metadata"]
    if (binding["place"] not in city["existing_place_ids"]
            or metadata["anchor_place_id"] != binding["place"] or not in_period(metadata)):
        raise ValueError(f"Formal transport shard does not match {city_id} in 1900")
    facts = {fact["subject_id"]: fact["value"] for fact in shard["evidence_catalog"]["facts"]}
    anchors = []
    for pair in binding.get("rail", []):
        station, corridor = (facts[name] for name in (pair["station"], pair["corridor"]))
        if (not in_period(station) or not in_period(corridor)
                or station.get("source_type") != "HISTORICAL_EVIDENCE"
                or station.get("transport_symbol") != "station"
                or station["geometry"]["type"] != "Point"
                or corridor.get("kind") != "rail"
                or binding["place"] not in corridor["places"]):
            raise ValueError(f"Invalid formal railway reference for {pair['station']}")
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
    return kit, binding, anchors, metadata.get("landmark_visuals", [])


def street_width(index):
    return 15.0 if index % 5 == 0 else 7.0


def build_city(city, terrain, transport_data):
    kit, binding, anchors, landmarks = official_inputs(city, transport_data)
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
    extent = backward.transform_bounds(-radius, -radius, radius, radius)
    land = transform(terrain.land_geometry(extent), forward)
    shapely.prepare(land)

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

    def grade(x, y):
        # The QPK grid cannot resolve individual street grades.
        nx = round(x / RELIEF_SPACING) * RELIEF_SPACING
        ny = round(y / RELIEF_SPACING) * RELIEF_SPACING
        half = RELIEF_SPACING / 2.0
        return math.hypot(height(nx + half, ny) - height(nx - half, ny),
                          height(nx, ny + half) - height(nx, ny - half)) / RELIEF_SPACING

    features = []

    def feature(geometry, kind, **properties):
        features.append({"type": "Feature", "geometry": mapping(transform(geometry, backward)),
                         "properties": {"kind": kind, **properties}})

    cells, roads = {}, {}
    for i in range(-math.ceil(radius / spacing_x), math.ceil(radius / spacing_x)):
        for j in range(-math.ceil(radius / spacing_y), math.ceil(radius / spacing_y)):
            x, y = offset_x + i * spacing_x, offset_y + j * spacing_y
            cx, cy = x + spacing_x / 2, y + spacing_y / 2
            distance = math.hypot(cx, cy)
            half_diagonal = math.hypot(spacing_x, spacing_y) / 2
            if distance > radius or (peer and math.hypot(cx - peer[0], cy - peer[1]) < distance + half_diagonal):
                continue
            block = box(x, y, x + spacing_x, y + spacing_y)
            if not land.covers(block.buffer(7.5)) or guarded.intersects(block):
                continue
            slope = grade(cx, cy)
            if slope > MAX_STREET_GRADE:
                continue
            cells[i, j] = (block, distance, slope)
            corners = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            for first, second in zip(corners, corners[1:] + corners[:1]):
                edge = tuple(sorted((first, second)))
                roads[edge] = street_width(first[0] if first[0] == second[0] else first[1])

    if not cells:
        raise ValueError(f"No buildable QWG land and QPK relief for {city['city_id']}")
    def street_point(node):
        return offset_x + node[0] * spacing_x, offset_y + node[1] * spacing_y

    for (first, second), width in roads.items():
        line = LineString([street_point(first), street_point(second)])
        main_axis = first[1] == second[1] == 0
        feature(line, "road", width_m=width,
                role="layout_axis" if main_axis else "district" if width > 7 else "local")

    vertices = {vertex for pair in roads for vertex in pair}
    access_clearance = []
    for anchor in anchors:
        target = Point(*forward.transform(*anchor["point"]))
        usable_nodes = sorted(vertices, key=lambda node: (
            Point(street_point(node)).distance(target), node,
        ))
        anchor_id = anchor.get("station_id", anchor.get("node_id"))
        own_guard = guards.get(anchor_id)
        other_guards = shapely.union_all([guard for key, guard in guards.items() if key != anchor_id])
        anchor["access_status"] = "no_buildable_approach"
        for vertex in usable_nodes:
            node = Point(street_point(vertex))
            if node.distance(target) < 0.1:
                anchor["access_status"] = "at_generated_junction"
                break
            approach = LineString([node, target])
            if approach.length > 3 * max(spacing_x, spacing_y):
                break
            if own_guard is not None:
                approach = approach.difference(own_guard)
            if approach.is_empty or approach.geom_type != "LineString":
                continue
            clearance = approach.buffer(3.5, cap_style="flat")
            halfway = approach.interpolate(0.5, normalized=True)
            if (not land.covers(clearance) or other_guards.intersects(clearance)
                    or grade(halfway.x, halfway.y) > MAX_STREET_GRADE):
                continue
            access_clearance.append(clearance)
            feature(approach, "road", width_m=7.0, role="transport_approach", anchor_id=anchor_id)
            anchor["access_status"] = "simulated_approach"
            break
        feature(target, "transport_anchor", **anchor)

    clearance = shapely.union_all(access_clearance)
    shapely.prepare(clearance)
    edge = [cell for cell, (block, distance, slope) in cells.items()
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
        cells[cell][2], -cells[cell][0].distance(cells[industry][0]), cell,
    ))
    reserves = {industry: "reserved_industrial", military: "reserved_military"}

    def placements():
        for (i, j), (block, distance, slope) in cells.items():
            minx, miny, maxx, maxy = block.bounds
            left = minx + street_width(i) / 2
            right = maxx - street_width(i + 1) / 2
            bottom = miny + street_width(j) / 2
            top = maxy - street_width(j + 1) / 2
            parcel = box(left, bottom, right, top)
            if (i, j) in reserves:
                reserve = {"type": reserves[i, j], "availability": "unallocated",
                           "point": list(backward.transform(parcel.centroid.x, parcel.centroid.y)),
                           "heading_degrees": 90.0, "capacity_m2": round(parcel.area)}
                reserve_metadata.append(reserve)
                feature(parcel, "landuse", use=reserve["type"], coarse_grade=round(slope, 4),
                        **{key: value for key, value in reserve.items() if key != "type"})
                continue
            feature(parcel.difference(clearance) if clearance.intersects(parcel) else parcel,
                    "block", role="street_frontage", coarse_grade=round(slope, 4))
            maximum_depth = kit["depth_m"][1] + kit["setback_m"][1]
            court = box(left + maximum_depth, bottom + maximum_depth,
                        right - maximum_depth, top - maximum_depth)
            if not clearance.intersects(court):
                feature(court, "landuse", use="courtyard" if kit["court"] == "enclosed" else "rear_open_space")
            for side, (start, end, front, direction, horizontal, district) in enumerate((
                (left, right, bottom, 1, True, j % 5 == 0),
                (left, right, top, -1, True, (j + 1) % 5 == 0),
                (bottom + maximum_depth, top - maximum_depth, left, 1, False, i % 5 == 0),
                (bottom + maximum_depth, top - maximum_depth, right, -1, False, (i + 1) % 5 == 0),
            )):
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
                    if clearance.intersects(box(x - half_x, y - half_y, x + half_x, y + half_y)):
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
