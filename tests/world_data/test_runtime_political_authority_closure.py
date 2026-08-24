from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
FORMAL_SIMULATION = SCRIPTS / "formal" / "formal_world_simulation.gd"
CATALOG = SCRIPTS / "formal" / "historical_political_evidence_catalog.gd"


class RuntimePoliticalAuthorityClosureTest(unittest.TestCase):
    def _gd_sources_containing(self, needle: str) -> list[Path]:
        return sorted(
            path.relative_to(ROOT)
            for path in SCRIPTS.rglob("*.gd")
            if needle in path.read_text(encoding="utf-8")
        )

    def test_only_catalog_names_the_dated_political_source(self) -> None:
        self.assertEqual(
            self._gd_sources_containing("political_units_1900.json"),
            [CATALOG.relative_to(ROOT)],
        )
        self.assertEqual(
            self._gd_sources_containing("historical_political_entities_1900.json"),
            [],
        )

    def test_formal_simulation_is_the_only_runtime_owner_constructor(self) -> None:
        self.assertEqual(
            self._gd_sources_containing("HistoricalPoliticalEvidenceCatalog.new()"),
            [FORMAL_SIMULATION.relative_to(ROOT)],
        )
        self.assertEqual(
            self._gd_sources_containing("RuntimePoliticalEntityRegistry.new()"),
            [FORMAL_SIMULATION.relative_to(ROOT)],
        )

    def test_consumers_use_immutable_views(self) -> None:
        economy = (
            SCRIPTS / "formal" / "formal_world_economy_service.gd"
        ).read_text(encoding="utf-8")
        projection = (
            SCRIPTS / "formal" / "current_world_political_projection.gd"
        ).read_text(encoding="utf-8")
        application = (
            SCRIPTS / "formal" / "formal_world_application.gd"
        ).read_text(encoding="utf-8")
        self.assertIn("RuntimePoliticalEntityView", economy)
        self.assertNotIn("RuntimePoliticalEntityRegistry", economy)
        self.assertIn("RuntimePoliticalEntityView", projection)
        self.assertIn("HistoricalPoliticalEvidenceView", projection)
        self.assertNotIn("compatibility_controller_id", projection)
        self.assertNotIn("controller_id", application)
        self.assertNotIn("控制方", application)

    def test_formal_ui_receives_catalog_data_before_parent_ready(self) -> None:
        application = (
            SCRIPTS / "formal" / "formal_world_application.gd"
        ).read_text(encoding="utf-8")
        initialize_at = application.index("formal_simulation.initialize()")
        inject_at = application.index("historical_political_evidence_units()")
        parent_ready_at = application.index("super._ready()")
        self.assertLess(initialize_at, inject_at)
        self.assertLess(inject_at, parent_ready_at)


if __name__ == "__main__":
    unittest.main()
