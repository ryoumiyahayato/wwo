from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

from tools.map_preprocessing import pipeline


def solid(width: int, height: int, rgba: tuple[int, int, int, int]) -> bytes:
    return bytes(rgba) * (width * height)


def gray_mask(width: int, height: int, opaque: set[tuple[int, int]]) -> bytes:
    result = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            value = 255 if (x, y) in opaque else 0
            index = (y * width + x) * 4
            result[index : index + 4] = bytes((value, value, value, value))
    return bytes(result)
def rgb_png(width: int, height: int, color: tuple[int, int, int]) -> bytes:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', __import__('zlib').crc32(kind + payload) & 0xffffffff)
    raw = b''.join(b'\x00' + bytes(color) * width for _ in range(height))
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    return pipeline.PNG_SIGNATURE + chunk(b'IHDR', ihdr) + chunk(b'IDAT', __import__('zlib').compress(raw, 9)) + chunk(b'IEND', b'')


class R1SafetyTests(unittest.TestCase):
    def test_output_root_containment_rejects_dangerous_paths_and_accepts_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            valid = root / "artifacts" / "map-preprocessing" / "candidates"
            self.assertEqual(pipeline.validate_candidate_output_dir(root, valid), valid.resolve())
            for dangerous in (root / "data" / "world_map", root, root / ".git", root / ".." / "outside", Path(temporary).parent / "outside-absolute"):
                with self.assertRaises(ValueError):
                    pipeline.validate_candidate_output_dir(root, dangerous)

    def test_input_output_alias_is_rejected_before_write_and_mask_is_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.png"
            mask = root / "artifacts" / "map-preprocessing" / "alias" / (pipeline._entity_output_stem("entity/alias") + ".mask.png")
            mask.parent.mkdir(parents=True)
            pipeline.write_png_rgba(source, 3, 3, solid(3, 3, (20, 30, 40, 255)))
            pipeline.write_png_rgba(mask, 3, 3, gray_mask(3, 3, {(1, 1)}))
            before = mask.read_bytes()
            with self.assertRaises(ValueError):
                pipeline.process_cutout(root, source, "entity/alias", mask.parent, mask_path=mask, mask_mode="grayscale")
            self.assertEqual(mask.read_bytes(), before)

    def test_sanitized_ids_have_traceable_collision_safe_names(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.png"
            mask = root / "mask.png"
            pipeline.write_png_rgba(source, 2, 2, solid(2, 2, (10, 20, 30, 255)))
            pipeline.write_png_rgba(mask, 2, 2, gray_mask(2, 2, {(0, 0)}))
            first = pipeline.process_cutout(root, source, "a/b", root / "artifacts/map-preprocessing/a", mask_path=mask, mask_mode="grayscale")
            second = pipeline.process_cutout(root, source, "a_b", root / "artifacts/map-preprocessing/b", mask_path=mask, mask_mode="grayscale")
            self.assertNotEqual(first["output_file"], second["output_file"])
            self.assertEqual(first["entity_id"], "a/b")
            self.assertEqual(second["entity_id"], "a_b")

    def test_list_geometry_and_malformed_points_are_fail_closed(self) -> None:
        list_geometry = [{"id": "list-poly", "outer": [[0, 0], [3, 0], [3, 3], [0, 3]]}]
        polygons = pipeline.extract_polygons(list_geometry)
        self.assertEqual(len(polygons), 1)
        for bad_ring in ([[0], [1, 1], [2, 2]], [[0, 0], [1, "bad"], [2, 2]], [[0, 0], [float("nan"), 1], [2, 2]], [[0, 0], [1, 1, 2], [2, 2]]):
            with self.assertRaises(ValueError):
                pipeline._rasterize_polygons([{"outer": bad_ring}], 8, 8)

    def test_coordinate_contract_requires_mapping_for_wgs84(self) -> None:
        polygon = [{"outer": [[0, 0], [2, 0], [2, 2], [0, 2]]}]
        self.assertTrue(any(pipeline._rasterize_polygons(polygon, 8, 8)))
        with self.assertRaises(ValueError):
            pipeline._rasterize_polygons(polygon, 8, 8, coordinate_space="WGS84")
        with self.assertRaises(ValueError):
            pipeline._rasterize_polygons(polygon, 8, 8, source_bounds=[0, 0, 0, 2], coordinate_space="WGS84")
        self.assertTrue(any(pipeline._rasterize_polygons(polygon, 8, 8, source_bounds=[0, 0, 2, 2], coordinate_space="WGS84")))

    def test_manifest_validator_rejects_non_object_and_missing_references(self) -> None:
        self.assertEqual(pipeline.validate_manifest([]), ['manifest.object'])
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = {'schema_version': 1, 'generator_version': '1.1.0', 'entity_id': 'missing', 'source_file': 'missing.png', 'source_hash': '0' * 64, 'source_dimensions': [1, 1], 'mask_hash': '0' * 64, 'output_hash': '0' * 64, 'preview_hash': '0' * 64, 'crop_bbox': [0, 0, 1, 1], 'mask_bbox': [0, 0, 1, 1], 'canvas_size': [1, 1], 'output_size': [1, 1], 'output_file': 'missing.png', 'mask_file': 'missing.mask.png', 'preview_file': 'missing.preview.png', 'coordinate_contract': {'space': 'PIXEL', 'mapping': 'direct_canvas_pixels', 'y_axis': 'down'}, 'processing_parameters': {'resampling': 'nearest_neighbor', 'alpha_mode': 'source_alpha_intersect_mask', 'mask_mode': 'grayscale', 'mask_input_alpha_availability': 'absent', 'padding': 0, 'mask_resampled': False, 'mask_resampling': 'none', 'original_preserved': True}, 'input_mask_file': 'missing-mask.png', 'input_mask_hash': '0' * 64, 'input_mask_dimensions': [1, 1]}
            errors = pipeline.validate_manifest(manifest, root, root / 'artifacts/map-preprocessing/candidate')
            self.assertIn('source_file.missing', errors)
            self.assertIn('input_mask_file.missing', errors)
    def test_manifest_validator_checks_actual_files_and_corruption(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.png"
            mask = root / "mask.png"
            output = root / "artifacts/map-preprocessing/manifest"
            pipeline.write_png_rgba(source, 3, 3, solid(3, 3, (10, 20, 30, 255)))
            pipeline.write_png_rgba(mask, 3, 3, gray_mask(3, 3, {(1, 1)}))
            manifest = pipeline.process_cutout(root, source, "manifest/entity", output, mask_path=mask, mask_mode="grayscale")
            self.assertEqual(pipeline.validate_manifest(manifest, root, output), [])
            manifest["mask_hash"] = "0" * 64
            self.assertIn("mask_hash.actual", pipeline.validate_manifest(manifest, root, output))
            manifest["mask_hash"] = pipeline._file_hash(output / manifest["mask_file"])
            manifest["crop_bbox"] = [0, 0, 99, 99]
            self.assertIn("crop_bbox", pipeline.validate_manifest(manifest))

    def test_multipolygon_hole_matches_any_outer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "data/world_map/world_coastlines.json"
            source.parent.mkdir(parents=True)
            source.write_text(json.dumps({"features": [{"id": "multi", "polygons": [{"outer": [[0, 0], [2, 0], [2, 2], [0, 2]]}, {"outer": [[10, 10], [20, 10], [20, 20], [10, 20]], "holes": [[[12, 12], [14, 12], [14, 14], [12, 14]]]}]}]}), encoding="utf-8")
            codes = {item["code"] for item in pipeline.geometry_qa(root)["findings"]}
            self.assertNotIn("hole_outside_outer", codes)

    def test_antimeridian_is_reported_not_cartesian_guessed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "data/world_map/world_coastlines.json"
            source.parent.mkdir(parents=True)
            source.write_text(json.dumps({"coordinate_system": "WGS84 longitude/latitude", "features": [{"id": "wrap", "polygons": [{"outer": [[179, 10], [-179, 10], [-179, 20], [179, 20]]}]}]}), encoding="utf-8")
            findings = pipeline.geometry_qa(root)["findings"]
            self.assertIn("antimeridian_wrap_unsupported", {item["code"] for item in findings})

    def test_duplicate_provider_resolution_is_ambiguous(self) -> None:
        first = {"id": "one"}
        second = {"id": "two"}
        self.assertEqual(pipeline.resolve_unique_provider([first])[1], "RESOLVED")
        self.assertEqual(pipeline.resolve_unique_provider([first, second])[1], "AMBIGUOUS")

    def test_mask_dimension_requires_explicit_resample_and_records_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.png"
            mask = root / "mask.png"
            pipeline.write_png_rgba(source, 4, 4, solid(4, 4, (10, 20, 30, 255)))
            pipeline.write_png_rgba(mask, 2, 2, gray_mask(2, 2, {(0, 0)}))
            with self.assertRaises(ValueError):
                pipeline.process_cutout(root, source, "dims", root / "artifacts/map-preprocessing/no", mask_path=mask, mask_mode="grayscale")
            manifest = pipeline.process_cutout(root, source, "dims", root / "artifacts/map-preprocessing/yes", mask_path=mask, mask_mode="grayscale", allow_mask_resample=True)
            self.assertTrue(manifest["processing_parameters"]["mask_resampled"])
            self.assertEqual(manifest["input_mask_dimensions"], [2, 2])

    def test_manifest_validator_rejects_alpha_semantics_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source.png'
            mask = root / 'mask.png'
            output = root / 'artifacts/map-preprocessing/alpha'
            pipeline.write_png_rgba(source, 2, 2, solid(2, 2, (10, 20, 30, 255)))
            mask.write_bytes(rgb_png(2, 2, (255, 255, 255)))
            with self.assertRaises(ValueError):
                pipeline.process_cutout(root, source, 'alpha/entity', output, mask_path=mask, mask_mode='alpha')

    def test_mask_mode_is_explicit(self) -> None:
        with self.assertRaises(ValueError):
            pipeline._mask_from_rgba(1, 1, bytes((255, 255, 255, 255)), None)
        self.assertEqual(pipeline._mask_from_rgba(1, 1, bytes((0, 0, 0, 10)), "alpha"), [True])
        with self.assertRaises(ValueError):
            pipeline._mask_from_rgba(1, 1, bytes((255, 0, 0, 255)), "grayscale")

    def test_png_tRNS_is_explicitly_unsupported_and_inventory_continues(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bad = root / 'assets/transparency.png'
            bad.parent.mkdir(parents=True)
            def chunk(kind: bytes, payload: bytes) -> bytes:
                import struct
                import zlib
                return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff)
            ihdr = struct.pack('>IIBBBBB', 1, 1, 8, 0, 0, 0, 0)
            scanline = bytes((0, 255))
            bad.write_bytes(pipeline.PNG_SIGNATURE + chunk(b'IHDR', ihdr) + chunk(b'tRNS', b'\xff\xff') + chunk(b'IDAT', __import__('zlib').compress(scanline, 9)) + chunk(b'IEND', b''))
            with self.assertRaises(ValueError):
                pipeline.read_png_rgba(bad)
            inventory = pipeline.build_inventory(root)
            self.assertIn('parse_error', inventory['files'][0]['details'])
    def test_malformed_png_is_inventory_finding_not_abort(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bad = root / "assets/bad.png"
            bad.parent.mkdir(parents=True)
            bad.write_bytes(pipeline.PNG_SIGNATURE + b"\x00\x00\x00\x20IHDR")
            inventory = pipeline.build_inventory(root)
            self.assertEqual(len(inventory["files"]), 1)
            self.assertIn("parse_error", inventory["files"][0]["details"])

    def test_repository_crosswalk_counts_and_no_source_status(self) -> None:
        repository_root = Path(__file__).resolve().parents[2]
        inventory = pipeline.build_inventory(repository_root)
        self.assertEqual(inventory["summary"]["asset_count"], 273)
        crosswalk = pipeline.build_crosswalk(repository_root, inventory)
        self.assertEqual(crosswalk["summary"]["entity_count"], 560)
        self.assertEqual(crosswalk["summary"]["current_country_geometry_resolved"], 177)
        self.assertEqual(crosswalk["summary"]["historical_unit_geometry_resolved"], 151)
        self.assertEqual(crosswalk["summary"]["candidate_masks_generated"], 0)
        self.assertEqual(crosswalk["summary"]["candidate_mask_block_reason"], "BLOCKED_NO_SOURCE_MAP_ASSET")

    def test_cutout_replay_is_byte_deterministic_and_preserves_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.png"
            mask = root / "mask.png"
            pipeline.write_png_rgba(source, 4, 3, solid(4, 3, (80, 100, 120, 255)))
            pipeline.write_png_rgba(mask, 4, 3, gray_mask(4, 3, {(1, 1), (2, 1)}))
            source_before = source.read_bytes()
            mask_before = mask.read_bytes()
            first = pipeline.process_cutout(root, source, "sample/entity", root / "artifacts/map-preprocessing/replay-a", mask_path=mask, mask_mode="grayscale", padding=1)
            second = pipeline.process_cutout(root, source, "sample/entity", root / "artifacts/map-preprocessing/replay-b", mask_path=mask, mask_mode="grayscale", padding=1)
            self.assertEqual(first, second)
            self.assertEqual(pipeline.validate_manifest(first, root, root / 'artifacts/map-preprocessing/replay-a'), [])
            first_files = {path.name: path.read_bytes() for path in (root / 'artifacts/map-preprocessing/replay-a').iterdir() if path.is_file()}
            second_files = {path.name: path.read_bytes() for path in (root / 'artifacts/map-preprocessing/replay-b').iterdir() if path.is_file()}
            self.assertEqual(first_files, second_files)
            self.assertEqual(source.read_bytes(), source_before)
            self.assertEqual(mask.read_bytes(), mask_before)
    def test_manifest_schema_matches_published_required_fields(self) -> None:
        schema_path = Path(__file__).resolve().parents[2] / "tools" / "map_preprocessing" / "manifest.schema.json"
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        required = set(schema["required"])
        self.assertTrue({"source_dimensions", "mask_hash", "output_hash", "preview_hash", "coordinate_contract", "processing_parameters"}.issubset(required))
        self.assertEqual(schema["$defs"]["bbox"]["prefixItems"][2]["minimum"], 1)
    def test_declared_wgs84_geometry_requires_wgs84_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source.png'
            geometry = root / 'geometry.json'
            pipeline.write_png_rgba(source, 4, 4, solid(4, 4, (90, 110, 130, 255)))
            geometry.write_text(json.dumps({'coordinate_system': 'WGS84 longitude/latitude', 'features': [{'id': 'geo', 'polygons': [{'outer': [[0, 0], [2, 0], [2, 2], [0, 2]]}]}]}), encoding='utf-8')
            with self.assertRaises(ValueError):
                pipeline.process_cutout(root, source, 'geo/entity', root / 'artifacts/map-preprocessing/geo-pixel', geometry_file=geometry, geometry_id='geo')
            manifest = pipeline.process_cutout(root, source, 'geo/entity', root / 'artifacts/map-preprocessing/geo-wgs84', geometry_file=geometry, geometry_id='geo', coordinate_space='WGS84', source_bounds=[0, 0, 2, 2])
            self.assertEqual(manifest['coordinate_contract']['space'], 'WGS84')
    def test_geometry_process_accepts_top_level_list_shape(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source.png'
            geometry = root / 'regions.json'
            pipeline.write_png_rgba(source, 4, 4, solid(4, 4, (90, 110, 130, 255)))
            geometry.write_text(json.dumps([{'id': 'list-poly', 'outer': [[1, 1], [3, 1], [3, 3], [1, 3]]}]), encoding='utf-8')
            manifest = pipeline.process_cutout(root, source, 'list/entity', root / 'artifacts/map-preprocessing/list', geometry_file=geometry, geometry_id='list-poly')
            self.assertEqual(manifest['mask_bbox'], [1, 1, 2, 2])
            self.assertEqual(manifest['processing_parameters']['mask_mode'], 'geometry')

    def test_geometry_qa_reports_malformed_first_point_without_rewriting_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'data/world_map/world_coastlines.json'
            source.parent.mkdir(parents=True)
            source.write_text(json.dumps({'features': [{'id': 'bad', 'polygons': [{'outer': [[0], [1, 1], [2, 2], [0, 0]]}]}]}), encoding='utf-8')
            before = source.read_bytes()
            report = pipeline.geometry_qa(root)
            self.assertIn('malformed_ring', {item['code'] for item in report['findings']})
            self.assertEqual(source.read_bytes(), before)

    def test_mask_qa_reports_empty_full_hole_and_fragments_with_severity(self) -> None:
        width = height = 7
        opaque = {(x, y) for y in range(2, 5) for x in range(2, 5)} - {(3, 3)}
        opaque.add((0, 0))
        report = pipeline.mask_qa(width, height, [index in {y * width + x for x, y in opaque} for index in range(width * height)], 'test-mask')
        codes = {item['code'] for item in report['findings']}
        self.assertIn('suspicious_holes', codes)
        self.assertIn('disconnected_fragments', codes)
        self.assertNotIn('empty_mask', codes)
    def test_dynamic_source_status_does_not_hardcode_blocked(self) -> None:
        inventory = {"files": [{"path": "approved.geojson", "category": "vector", "coordinate_convention": "WGS84", "source_provenance": {"license": "CC-BY"}}]}
        status = pipeline.candidate_source_status(inventory)
        self.assertEqual(status["status"], "available")
        self.assertEqual(status["sources"], ["approved.geojson"])


if __name__ == "__main__":
    unittest.main()
