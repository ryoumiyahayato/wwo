from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"


def source(path: str) -> str:
    return (SCRIPTS / path).read_text(encoding="utf-8-sig")


class FormalApplicationArchitectureTest(unittest.TestCase):
    def test_application_coordinates_without_domain_implementation(self) -> None:
        app = source("formal/formal_world_application.gd")
        for forbidden in (
            "FileAccess", "JSON", "encode(", "decode(", "write_verified(",
            "settle_hour_range(", "review_settled_day(", "advance_to_hour(",
            "load_current(", "snapshot(", "polity_summary(", "world_summary(",
            "read_only_snapshot(", "register_organization(", "set_controller(",
        ):
            self.assertNotIn(forbidden, app)
        functions = re.findall(r"^func (\w+)", app, re.M)
        self.assertTrue(all(name.startswith("_") for name in functions))
        self.assertFalse(any(re.search(r"(?:query|get_world|summary|fingerprint)", name) for name in functions))
        fields = re.findall(r"(?m)^(?:@onready )?var (\w+)", app)
        self.assertEqual(set(fields), {
            "historical_content", "_world", "_simulation_step", "_persistence", "_map_dirty",
            "map_renderer", "map_controller", "main_shell", "time_control",
        })

    def test_world_and_build_result_have_distinct_field_only_roles(self) -> None:
        world = source("world/world_state.gd")
        built = source("world/world_build_result.gd")
        self.assertNotRegex(world, r"(?m)^(?:static )?func ")
        self.assertNotRegex(built, r"(?m)^(?:static )?func ")
        self.assertIn("var world: WorldState", built)
        self.assertNotIn("var game_clock:", built)
        self.assertNotIn("WorldBuildResult", world)
        self.assertNotIn("var _total_minutes", world)
        self.assertNotIn("Dictionary", world)

    def test_core_dependency_closure_excludes_presentation(self) -> None:
        classes = {}
        sources = {}
        for path in SCRIPTS.rglob("*.gd"):
            text = path.read_text(encoding="utf-8-sig")
            sources[path] = text
            match = re.search(r"(?m)^class_name (\w+)", text)
            if match:
                classes[match[1]] = path
        pending = [classes[name] for name in (
            "WorldState", "WorldBootstrap", "GameClock", "SimulationStep", "FormalPersistence"
        )]
        seen = set()
        while pending:
            path = pending.pop()
            if path in seen:
                continue
            seen.add(path)
            text = sources[path]
            relative = path.relative_to(SCRIPTS).as_posix()
            self.assertFalse(relative.startswith("presentation/"), relative)
            self.assertNotIn("scenes/formal/", text, relative)
            # Class references include typed members, constructors and static calls.
            text = re.sub(r"##?[^\n]*", "", text)
            names = set(re.findall(r"\b[A-Z][A-Za-z0-9_]*\b", text)) & classes.keys()
            pending.extend(classes[name] for name in names if classes[name] not in seen)
            # Include unnamed scripts reached through preload/load or path inheritance.
            for referenced in re.findall(r"res://([^\"\s]+\.gd)\b", text):
                dependency = ROOT / referenced
                self.assertIn(dependency, sources, referenced)
                if dependency not in seen:
                    pending.append(dependency)
        self.assertNotIn(classes["FormalWorldApplication"], seen)

    def test_presenter_has_no_retained_world_or_domain_writes(self) -> None:
        presenter = source("presentation/formal_world_presenter.gd")
        self.assertNotRegex(presenter, r"(?m)^var ")
        self.assertNotIn("WorldBuildResult", presenter)
        for path in (SCRIPTS / "presentation").rglob("*.gd"):
            self.assertNotIn("WorldBuildResult", path.read_text(encoding="utf-8-sig"), str(path))
        for mutation in ("set_controller(", "register_organization(", "advance_minutes(", "restore(", "materialize("):
            self.assertNotIn(mutation, presenter)

    def test_retired_monolith_cannot_return(self) -> None:
        retired = "FormalWorld" + "Simulation"
        old_path = "formal_world_" + "simulation.gd"
        self.assertFalse((SCRIPTS / "formal" / old_path).exists())
        for path in SCRIPTS.rglob("*.gd"):
            text = path.read_text(encoding="utf-8-sig")
            self.assertNotIn(retired, text, str(path))
            self.assertNotIn(old_path, text, str(path))

    def test_presentation_cannot_read_or_resolve_historical_files(self) -> None:
        for path in (SCRIPTS / "presentation").rglob("*.gd"):
            text = path.read_text(encoding="utf-8-sig")
            for forbidden in ("HistoricalLoader", "GeographyLoader", "AdministrativeLoader",
                              "EvidenceLoader", "HistoricalVisualResolver", "ContentDocument",
                              "FileAccess", "JSON.parse", "res://data/"):
                self.assertNotIn(forbidden, text, str(path))
            self.assertNotRegex(text, r"(?m)^var .*WorldState", str(path))

    def test_detached_content_has_no_world_loader_or_ui_dependencies(self) -> None:
        for filename in ("map_geometry_content.gd", "resolved_map_content.gd", "world_page_content.gd"):
            text = source("content/" + filename)
            for forbidden in ("FileAccess", "JSON", "HistoricalLoader", "WorldState",
                              "MainShell", "GlobeProjection", "ResourceLoader", "load("):
                self.assertNotIn(forbidden, text, filename)
            self.assertIn("duplicate", text, filename)
        loader = source("content/historical_loader.gd")
        for forbidden in ("MainShell", "GlobeRenderer", "GlobeController", "GlobeProjection", "WorldState"):
            self.assertNotIn(forbidden, loader)
        self.assertIn("resolve_map(time: Dictionary, current_units: Array[Dictionary])", loader)
        bootstrap = source("content/world_bootstrap.gd")
        self.assertNotIn("resolve_map(", bootstrap)
        self.assertNotIn("resolve_world_page(", bootstrap)


    def test_world_holds_economy_state_only(self) -> None:
        world = source("world/world_state.gd")
        self.assertIn("var economy_state: FormalWorldEconomyState", world)
        self.assertNotIn("FormalWorldEconomySimulation", world)
        state = source("world/formal_world_economy_state.gd")
        for algorithm in ("settle_hour_range", "_settle_country", "_schedule_shortage_shipments",
                          "_daily_demand_for", "_production_factor_for_capabilities"):
            self.assertNotIn("func " + algorithm + "(", state)
        self.assertNotIn("FormalWorldEconomySimulation", state)

    def test_step_delegates_economy_computation(self) -> None:
        step = source("simulation/simulation_step.gd")
        self.assertIn("var _economy: FormalWorldEconomySimulation", step)
        self.assertIn("_economy.settle_hour_range(", step)
        self.assertIn("_economy_state.read_only_country_observation_snapshot()", step)
        for algorithm in ("_settle_country(", "_daily_demand_for(", "_deliver_shipments("):
            self.assertNotIn(algorithm, step)
        simulation = source("simulation/formal_world_economy_simulation.gd")
        self.assertIn("var _state: FormalWorldEconomyState", simulation)
        self.assertNotIn("get_persistent_state(", simulation)
        self.assertNotIn("restore_persistent_state(", simulation)

    def test_persistence_saves_economy_state_without_algorithms(self) -> None:
        persistence = source("persistence/formal_persistence.gd")
        self.assertIn("_economy_state.get_persistent_state()", persistence)
        self.assertIn("r.world.economy_state.restore_persistent_state", persistence)
        self.assertNotIn("FormalWorldEconomySimulation", persistence)
        self.assertNotIn("settle_hour_range(", persistence)
        self.assertIn('SCHEMA_ID: String = "formal_world_simulation_v15"', persistence)

    def test_economy_readers_do_not_depend_on_computation(self) -> None:
        presenter = source("presentation/formal_world_presenter.gd")
        self.assertIn("world.economy_state.read_only_presentation_snapshot()", presenter)
        self.assertNotIn("world.economy_state.read_only_snapshot()", presenter)
        for filename in ("presentation/formal_world_presenter.gd", "presentation/ui/economy_view.gd",
                         "formal/formal_world_economy_view.gd"):
            text = source(filename)
            self.assertNotIn("FormalWorldEconomySimulation", text)
            self.assertNotIn("settle_hour_range(", text)

    def test_bootstrap_builds_both_economy_components(self) -> None:
        bootstrap = source("content/world_bootstrap.gd")
        self.assertIn("r.world.economy_state = FormalWorldEconomyState.new()", bootstrap)
        self.assertIn("FormalWorldEconomySimulation.new(r.world.economy_state)", bootstrap)
        self.assertIn("r.economy_simulation.initialize_state()", bootstrap)
        self.assertNotIn("_daily_demand_for(", bootstrap)
        self.assertNotIn("_settle_country(", source("formal/formal_world_application.gd"))

    def test_retired_economy_service_has_no_production_references(self) -> None:
        retired = "FormalWorldEconomy" + "Service"
        old_path = "formal_world_economy_" + "service.gd"
        self.assertFalse((SCRIPTS / "formal" / old_path).exists())
        for path in SCRIPTS.rglob("*.gd"):
            text = path.read_text(encoding="utf-8-sig")
            self.assertNotIn(retired, text, str(path))
            self.assertNotIn(old_path, text, str(path))
            self.assertNotIn("economy_service", text, str(path))


if __name__ == "__main__":
    unittest.main()
