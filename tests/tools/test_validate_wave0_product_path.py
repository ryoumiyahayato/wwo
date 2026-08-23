import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


TOOL_PATH = (
    Path(__file__).resolve().parents[2]
    / "tools"
    / "validate_wave0_product_path.py"
)
SPEC = importlib.util.spec_from_file_location("wave0_validator", TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class Wave0EvidenceValidatorTest(unittest.TestCase):
    def _manifest(self, head: str) -> dict:
        records = []
        owners = {label: {"status": "ACTIVE"} for label in VALIDATOR.REQUIRED_OWNER_LABELS}
        for screenshot_id, filename in VALIDATOR.REQUIRED_SCREENSHOTS.items():
            records.append(
                {
                    "screenshot_id": screenshot_id,
                    "filename": filename,
                    "HEAD": head,
                    "entry_scene": VALIDATOR.MENU_SCENE,
                    "runtime_scene": (
                        VALIDATOR.MENU_SCENE
                        if screenshot_id == "01_BOOT"
                        else VALIDATOR.PRODUCT_SCENE
                    ),
                    "actual_runtime_owners": owners,
                    "selected_country": (
                        "country_fra"
                        if screenshot_id
                        in {"03_COUNTRY", "04_LOCAL_GEOGRAPHY", "05_CITY"}
                        else ""
                    ),
                    "selected_region": "",
                    "selected_city": "",
                    "legacy_prototype_content_visible": False,
                    "synthetic_fixture": False,
                    "objectively_demonstrates": "observed current product state",
                    "formal_total_minutes": {
                        "09_TIME_BEFORE": 0,
                        "10_TIME_AFTER": 60,
                        "11_SAVE": 60,
                        "12_ADVANCE": 120,
                        "13_RESTORE": 60,
                    }.get(screenshot_id, 0),
                }
            )
        return {"screenshots": records}

    def _validate(self, document: dict, head: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = Path(directory) / "manifest.json"
            manifest_path.write_text(json.dumps(document), encoding="utf-8")
            return VALIDATOR.validate_manifest(
                manifest_path, head, require_files=False
            )

    def test_matching_default_product_metadata_passes(self) -> None:
        head = "a" * 40
        self.assertEqual(self._validate(self._manifest(head), head), [])

    def test_alternate_main_scene_is_rejected(self) -> None:
        head = "b" * 40
        manifest = self._manifest(head)
        manifest["screenshots"][1]["runtime_scene"] = (
            "res://scenes/demo/demo_world.tscn"
        )
        failures = self._validate(manifest, head)
        self.assertTrue(any("alternate" in failure for failure in failures))

    def test_mismatched_head_is_rejected(self) -> None:
        expected_head = "c" * 40
        manifest = self._manifest("d" * 40)
        failures = self._validate(manifest, expected_head)
        self.assertTrue(any("HEAD" in failure for failure in failures))

    def test_fixture_evidence_is_rejected(self) -> None:
        head = "e" * 40
        manifest = self._manifest(head)
        manifest["screenshots"][4]["synthetic_fixture"] = True
        failures = self._validate(manifest, head)
        self.assertTrue(any("synthetic fixture" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
