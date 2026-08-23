from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "wave1_gate", ROOT / "tools" / "validate_wave1_spatial_product.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class Wave1GateTests(unittest.TestCase):
    def test_repository_product_path_passes(self) -> None:
        self.assertEqual(MODULE.validate_product(ROOT), [])

    def test_capacity_call_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            clone = Path(temporary)
            for relative in (
                "project.godot", "scripts/formal/formal_world_application.gd",
                "scripts/formal/formal_world_menu.gd",
                "scripts/formal/product_spatial_projection.gd",
                *MODULE.SPATIAL_SOURCES,
            ):
                target = clone / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((ROOT / relative).read_bytes())
            projection = clone / MODULE.PROJECTION
            projection.write_text(
                projection.read_text(encoding="utf-8") + "\n# .reserve_capacity(\n",
                encoding="utf-8",
            )
            self.assertTrue(any("capacity API" in f for f in MODULE.validate_product(clone)))


if __name__ == "__main__":
    unittest.main()
