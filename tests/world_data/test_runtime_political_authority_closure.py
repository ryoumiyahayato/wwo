from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
WORLD_BOOTSTRAP = SCRIPTS / "content" / "world_bootstrap.gd"
CATALOG = SCRIPTS / "formal" / "historical_political_evidence_catalog.gd"


class RuntimePoliticalAuthorityClosureTest(unittest.TestCase):
    def _gd_sources_containing(self, needle: str) -> list[Path]:
        return sorted(
            path.relative_to(ROOT)
            for path in SCRIPTS.rglob("*.gd")
            if needle in path.read_text(encoding="utf-8")
        )

    def test_existing_political_content_readers_are_explicit(self) -> None:
        self.assertEqual(
            self._gd_sources_containing("political_units_1900.json"),
            sorted([CATALOG.relative_to(ROOT), Path("scripts/content/evidence_loader.gd"), Path("scripts/content/historical_visual_resolver.gd")]),
        )
        self.assertEqual(
            self._gd_sources_containing("historical_political_entities_1900.json"),
            [],
        )

    def test_historical_evidence_constructors_stay_in_admission_boundaries(self) -> None:
        self.assertEqual(
            self._gd_sources_containing("HistoricalPoliticalEvidenceCatalog.new()"),
            sorted(
                [
                    WORLD_BOOTSTRAP.relative_to(ROOT),
                ]
            ),
        )
        self.assertEqual(
            self._gd_sources_containing("RuntimePoliticalEntityRegistry.new()"),
            [WORLD_BOOTSTRAP.relative_to(ROOT)],
        )

    def test_consumers_use_immutable_views(self) -> None:
        economy = (
            SCRIPTS / "world" / "formal_world_economy_state.gd"
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

    def test_formal_ui_receives_detached_inputs_after_bootstrap(self) -> None:
        application = (SCRIPTS / "formal" / "formal_world_application.gd").read_text(encoding="utf-8")
        self.assertLess(application.index("WorldBootstrap.new().build("), application.index("_install_world(built)"))
        presenter = (SCRIPTS / "presentation" / "formal_world_presenter.gd").read_text(encoding="utf-8")
        self.assertIn("FormalWorldPresenter.refresh_ui", application)
        self.assertIn("RuntimePoliticalEntityView.new(world.political_registry.snapshot())", presenter)
        self.assertIn("shell.person_page.refresh(person, place", presenter)
        self.assertNotIn("super._ready()", application)


if __name__ == "__main__":
    unittest.main()
