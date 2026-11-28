"""Read city features for a local scene from the map's existing data sources."""

import json
import math
import struct
from pathlib import Path

from shapely import box, intersects_xy, prepare, segmentize, transform
from shapely.geometry import MultiLineString, mapping
from zstandard import ZstdDecompressor

from build_city_models import RECORD, transforms
from build_city_water import SITES, prepared_roads, projected_bounds


BUILDING_NODES = ("london_gabled", "london_terrace", "paris_corner", "paris_mansard")


def _building_features(root, region):
    catalog = json.loads((root / "catalogue.json").read_text(encoding="utf-8-sig"))
    if catalog["version"] != "wwo-city-models-v1":
        raise ValueError("Unsupported city building catalogue")
    decoder = ZstdDecompressor()
    prepare(region)
    for city in catalog["cities"]:
        for tile in city["tiles"]:
            if not region.intersects(box(*tile["bounds"])):
                continue
            path = root / tile["file"]
            with path.open("rb") as source:
                header = source.read(12)
                count = tile["buildings"]
                if header != b"WWOWCB01" + struct.pack("<I", count) or not 1 <= count <= 12000:
                    raise ValueError(f"Invalid WCB page header in {path}")
                size = count * RECORD.size
                with decoder.stream_reader(source) as stream:
                    data = stream.read(size + 1)
                if len(data) != size:
                    raise ValueError(f"Invalid WCB page length in {path}")
            for lon, lat, heading, width, depth, height, kit, flags in RECORD.iter_unpack(data):
                xy = (lon / 1e6, lat / 1e6)
                if not intersects_xy(region, *xy):
                    continue
                if not 1 <= kit <= len(BUILDING_NODES) or flags != 0 or not all((width, depth, height)):
                    raise ValueError(f"Invalid WCB placement in {path}")
                yield {
                    "type": "Feature", "id": f"wcb:{city['name'].lower()}:{lon}:{lat}:{heading}",
                    "geometry": {"type": "Point", "coordinates": xy},
                    "properties": {"kind": "building", "node": BUILDING_NODES[kit-1],
                                   "heading_degrees": heading / 100, "width_m": width / 10,
                                   "depth_m": depth / 10, "height_m": height / 10,
                                   "roof_layer": 10, "wall_layer": 11, "source": city["source"]},
                }


def _road_features(sources, region):
    for index, (origin, extent) in enumerate(SITES):
        if not region.intersects(box(*extent)):
            continue
        values = projected_bounds(origin, extent)
        limits = box(*values[4:])
        lon, lat, east, north = values[:4]

        def to_geographic(x, y):
            return x / east + lon, y / north + lat

        for feature_id, lines, radius, material, bridge in prepared_roads(sources, limits, values, index == 1):
            road = transform(MultiLineString(lines), to_geographic, interleaved=False)
            if region.intersects(road):
                yield {"type": "Feature", "id": feature_id, "geometry": mapping(road),
                       "properties": {"kind": "road", "width_m": 2 * radius,
                                      "surface_layer": 7 + material, "bridge": bridge}}


def read_city_scene(sources: Path, buildings: Path, center: tuple[float, float], size_km: int) -> dict:
    """Return a CRS84 FeatureCollection for a square centred at (longitude, latitude).

    Features retain their identity and geometry across window sizes. Placements
    are selected by their centre and roads by intersection. Water comes from QWG.
    """
    if size_km not in (5, 25, 50):
        raise ValueError("Local scenes support 5, 25 or 50 km on each side")
    lon, lat = center
    if not all(map(math.isfinite, center)) or not -180 <= lon <= 180 or not -90 < lat < 90:
        raise ValueError("Expected a valid CRS84 centre")
    half = size_km * 500
    _, inverse = transforms(center)
    region = transform(segmentize(box(-half, -half, half, half), 500), inverse.transform, interleaved=False)
    if region.bounds[2] - region.bounds[0] > 180:
        # The current historical sources have no antimeridian or polar coverage.
        return _collection(center, size_km, [])
    features = list(_building_features(buildings, region))
    features.extend(_road_features(sources, region))
    return _collection(center, size_km, features)


def _collection(center, size_km, features):
    return {"type": "FeatureCollection", "coordinate_system": "OGC:CRS84", "center": center,
            "size_m": size_km * 1000, "model_library": "assets/settlements/urban_landscape_r40.glb",
            "material_atlas": "rust/strategic-host/src/surface-materials.png", "features": features}
