from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tools.map_preprocessing.pipeline import (
    build_crosswalk,
    build_inventory,
    geometry_qa,
    mask_qa,
    process_cutout,
    read_png_rgba,
    stable_hash,
    validate_manifest,
    write_png_rgba,
)


def _solid_pixels(width: int, height: int, color: tuple[int, int, int, int]) -> bytes:
    return bytes(color) * (width * height)


def _mask_pixels(width: int, height: int, opaque: set[tuple[int, int]]) -> bytes:
    pixels = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            value = 255 if (x, y) in opaque else 0
            index = (y * width + x) * 4
            pixels[index : index + 4] = bytes((value, value, value, value))
    return bytes(pixels)


class MapPreprocessingTests(unittest.TestCase):
    def test_inventory_records_png_dimensions_alpha_and_hash(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "assets" / "sample.png"
            write_png_rgba(image, 3, 2, _solid_pixels(3, 2, (10, 20, 30, 255)))
            inventory = build_inventory(root)
            self.assertEqual(inventory["summary"]["raster_count"], 1)
            record = inventory["files"][0]
            self.assertEqual(record["dimensions"], [3, 2])
            self.assertEqual(record["alpha_availability"], "present")
            self.assertEqual(len(record["sha256"]), 64)

    def test_geometry_qa_reports_self_intersection_without_rewriting_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "data" / "world_map" / "world_coastlines.json"
            source.parent.mkdir(parents=True)
            payload = {
                "features": [
                    {
                        "id": "bowtie",
                        "polygons": [{"outer": [[0, 0], [2, 2], [0, 2], [2, 0]]}],
                    }
                ]
            }
            source.write_text(json.dumps(payload), encoding="utf-8")
            before = source.read_bytes()
            report = geometry_qa(root)
            after = source.read_bytes()
            self.assertEqual(before, after)
            self.assertGreaterEqual(report["summary"]["error_count"], 1)
            self.assertIn("self_intersection", {item["code"] for item in report["findings"]})

    def test_mask_qa_detects_hole_and_disconnected_fragments(self) -> None:
        width = height = 7
        opaque = {(x, y) for y in range(2, 5) for x in range(2, 5)} - {(3, 3)}
        opaque.add((0, 0))
        report = mask_qa(width, height, [index in {y * width + x for x, y in opaque} for index in range(width * height)], "test-mask")
        codes = {item["code"] for item in report["findings"]}
        self.assertIn("suspicious_holes", codes)
        self.assertIn("disconnected_fragments", codes)

    def test_cutout_replay_is_byte_deterministic_and_preserves_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.png"
            mask = root / "mask.png"
            source_pixels = bytearray(_solid_pixels(4, 3, (80, 100, 120, 255)))
            source_before = bytes(source_pixels)
            write_png_rgba(source, 4, 3, source_pixels)
            write_png_rgba(mask, 4, 3, _mask_pixels(4, 3, {(1, 1), (2, 1)}))
            first = process_cutout(root, source, "sample/entity", root / "candidate-a", mask_path=mask, padding=1)
            second = process_cutout(root, source, "sample/entity", root / "candidate-b", mask_path=mask, padding=1)
            self.assertEqual(first, second)
            self.assertEqual(validate_manifest(first), [])
            for name in ("sample_entity.png", "sample_entity.mask.png", "sample_entity.preview.png", "sample_entity.manifest.json"):
                self.assertEqual((root / "candidate-a" / name).read_bytes(), (root / "candidate-b" / name).read_bytes())
            self.assertEqual(read_png_rgba(source)[2], source_before)
            self.assertEqual(stable_hash(first), stable_hash(second))
            self.assertEqual(first["crop_bbox"], [0, 0, 4, 3])
            self.assertTrue(first["processing_parameters"]["original_preserved"])

    def test_geometry_source_rasterizes_to_mask(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.png"
            geometry = root / "geometry.json"
            write_png_rgba(source, 4, 4, _solid_pixels(4, 4, (90, 110, 130, 255)))
            geometry.write_text(
                json.dumps({"features": [{"id": "poly", "polygons": [{"outer": [[1, 1], [3, 1], [3, 3], [1, 3]]}]}]}),
                encoding="utf-8",
            )
            manifest = process_cutout(root, source, "geometry/entity", root / "candidate", geometry_file=geometry, geometry_id="poly")
            self.assertEqual(manifest["mask_bbox"], [1, 1, 2, 2])
            self.assertEqual(validate_manifest(manifest), [])
            self.assertIn("geometry.json#poly", manifest["mask_source"])

    def test_real_repository_crosswalk_has_source_backed_country_and_history_links(self) -> None:
        repository_root = Path(__file__).resolve().parents[2]
        crosswalk = build_crosswalk(repository_root)
        summary = crosswalk["summary"]
        self.assertEqual(summary["current_country_geometry_resolved"], 177)
        self.assertEqual(summary["historical_unit_geometry_resolved"], 151)
        self.assertEqual(summary["candidate_masks_generated"], 0)
        self.assertGreater(summary["entity_count"], 500)

    def test_manifest_schema_is_valid_json(self) -> None:
        schema_path = Path(__file__).resolve().parents[2] / "tools" / "map_preprocessing" / "manifest.schema.json"
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        self.assertEqual(schema["$defs"]["bbox"]["maxItems"], 4)
        self.assertEqual(schema["properties"]["schema_version"]["const"], 1)


if __name__ == "__main__":
    unittest.main()
