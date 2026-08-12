from __future__ import annotations

import re
import runpy
from pathlib import Path

worker = Path(__file__).with_name("pr58_spatial_capacity_integration_worker.py")
text = worker.read_text(encoding="utf-8")
old = 'pattern = re.compile(rf"(?ms)^func {re.escape(name)}\\b.*?(?=^func |\\Z)")'
new = 'pattern = re.compile(rf"(?ms)^(?:static )?func {re.escape(name)}\\b.*?(?=^(?:static )?func |\\Z)")'
if old not in text:
    raise RuntimeError("worker function-boundary pattern not found")
worker.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
runpy.run_path(str(worker), run_name="__main__")

ROOT = Path(__file__).resolve().parents[1]


def replace_func(path: Path, name: str, body: str) -> None:
    source = path.read_text(encoding="utf-8")
    pattern = re.compile(rf"(?ms)^func {re.escape(name)}\\b.*?(?=^func |\\Z)")
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise RuntimeError(f"{path}:{name}: expected one function, got {len(matches)}")
    start, end = matches[0].span()
    path.write_text(source[:start] + body.rstrip() + "\n\n\n" + source[end:], encoding="utf-8", newline="\n")


def add_context_registry(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    marker = "var spatial: VNextSpatialWorld\n"
    if "var _state_contexts: Dictionary" not in source:
        if marker not in source:
            raise RuntimeError(f"{path}: Spatial field marker missing")
        source = source.replace(marker, marker + "var _state_contexts: Dictionary = {}\n", 1)
    path.write_text(source, encoding="utf-8", newline="\n")


strategy = ROOT / "tests/vnext/military_strategy_test.gd"
add_context_registry(strategy)
replace_func(strategy, "_new_state", '''func _new_state() -> VNextMilitaryState:
\tvar state_spatial := VNextSpatialWorld.create_from_legacy_world_map()
\t_check(state_spatial != null and state_spatial.is_valid(), "Military fixture Spatial world initializes")
\tvar state_map := VNextMilitaryMapAdapter.new()
\t_check(state_map.load_existing_map(state_spatial), "Military fixture adapter attaches Spatial world")
\tspatial = state_spatial
\tmap = state_map
\tvar state := VNextMilitaryState.new()
\t_check(state.initialize(state_map), "military state initializes")
\t_state_contexts[state.get_instance_id()] = {"spatial": state_spatial, "map": state_map}
\treturn state''')
replace_func(strategy, "_advance", '''func _advance(state: VNextMilitaryState, target_hour: int) -> bool:
\treturn bool(_advance_result(state, target_hour).get("success", false))


func _advance_result(state: VNextMilitaryState, target_hour: int) -> Dictionary:
\tvar context: Dictionary = _context_for_state(state)
\tvar state_spatial: VNextSpatialWorld = context.get("spatial") as VNextSpatialWorld
\tvar state_map: VNextMilitaryMapAdapter = context.get("map") as VNextMilitaryMapAdapter
\tif state_spatial.current_hour() < state.last_simulated_hour:
\t\tif not state_spatial.advance_to_hour(state.last_simulated_hour):
\t\t\treturn {"success": false}
\treturn service.advance_to_hour(state, state_map, target_hour)


func _context_for_state(state: VNextMilitaryState) -> Dictionary:
\tvar key: int = state.get_instance_id()
\tif _state_contexts.has(key):
\t\treturn _state_contexts[key] as Dictionary
\tvar state_spatial := VNextSpatialWorld.create_from_legacy_world_map()
\tif state_spatial == null or not state_spatial.is_valid():
\t\treturn {}
\tif not state_spatial.advance_to_hour(state.last_simulated_hour):
\t\treturn {}
\tvar state_map := VNextMilitaryMapAdapter.new()
\tif not state_map.load_existing_map(state_spatial):
\t\treturn {}
\tvar context := {"spatial": state_spatial, "map": state_map}
\t_state_contexts[key] = context
\treturn context''')
strategy_text = strategy.read_text(encoding="utf-8")
strategy_text = strategy_text.replace(
    "var settlement := service.advance_to_hour(completion, map, completion.last_simulated_hour + 1)",
    "var settlement := _advance_result(completion, completion.last_simulated_hour + 1)",
)
strategy.write_text(strategy_text, encoding="utf-8", newline="\n")

r3 = ROOT / "tests/vnext/military_r3_findings_test.gd"
add_context_registry(r3)
replace_func(r3, "_new_state", '''func _new_state() -> VNextMilitaryState:
\tvar state_spatial := VNextSpatialWorld.create_from_legacy_world_map()
\t_check(state_spatial != null and state_spatial.is_valid(), "R3 fixture Spatial world initializes")
\tvar state_map := VNextMilitaryMapAdapter.new()
\t_check(state_map.load_existing_map(state_spatial), "R3 fixture adapter attaches Spatial world")
\tspatial = state_spatial
\tmap = state_map
\tvar state := VNextMilitaryState.new()
\t_check(state.initialize(state_map), "R3 military state initializes")
\t_state_contexts[state.get_instance_id()] = {"spatial": state_spatial, "map": state_map}
\treturn state''')
replace_func(r3, "_advance_one", '''func _advance_one(state: VNextMilitaryState) -> bool:
\treturn bool(_advance_result(state, state.last_simulated_hour + 1).get("success", false))


func _advance_result(state: VNextMilitaryState, target_hour: int) -> Dictionary:
\tvar context: Dictionary = _context_for_state(state)
\tif context.is_empty():
\t\treturn {"success": false}
\tvar state_spatial: VNextSpatialWorld = context.get("spatial") as VNextSpatialWorld
\tvar state_map: VNextMilitaryMapAdapter = context.get("map") as VNextMilitaryMapAdapter
\tif state_spatial.current_hour() < state.last_simulated_hour:
\t\tif not state_spatial.advance_to_hour(state.last_simulated_hour):
\t\t\treturn {"success": false}
\treturn service.advance_to_hour(state, state_map, target_hour)


func _context_for_state(state: VNextMilitaryState) -> Dictionary:
\tvar key: int = state.get_instance_id()
\tif _state_contexts.has(key):
\t\treturn _state_contexts[key] as Dictionary
\tvar state_spatial := VNextSpatialWorld.create_from_legacy_world_map()
\tif state_spatial == null or not state_spatial.is_valid():
\t\treturn {}
\tif not state_spatial.advance_to_hour(state.last_simulated_hour):
\t\treturn {}
\tvar state_map := VNextMilitaryMapAdapter.new()
\tif not state_map.load_existing_map(state_spatial):
\t\treturn {}
\tvar context := {"spatial": state_spatial, "map": state_map}
\t_state_contexts[key] = context
\treturn context''')

# The long-latency fixture intentionally changes route timing and physical
# capacity before running. With per-state Spatial contexts those changes must
# target the state's own adapter/Spatial world rather than a previous fixture.
replace_func(r3, "_test_long_latency_high_capacity", '''func _test_long_latency_high_capacity() -> void:
\tvar state := _remote("formation:r3_latency", "marseille", 1000, _abundant())
\tvar context: Dictionary = _context_for_state(state)
\tvar state_map: VNextMilitaryMapAdapter = context.get("map") as VNextMilitaryMapAdapter
\tvar state_spatial: VNextSpatialWorld = context.get("spatial") as VNextSpatialWorld
\tmap = state_map
\tspatial = state_spatial
\tvar saved: Dictionary = {}
\tfor link_id: String in state_map.links.keys():
\t\tvar link: Dictionary = state_map.links[link_id] as Dictionary
\t\tvar nominal := float(state_spatial.infrastructure_state(link_id).get("nominal_capacity", 0.0))
\t\tsaved[link_id] = {"movement_hours": int(link.get("movement_hours", 1)), "nominal_capacity": nominal}
\t\tlink["movement_hours"] = maxi(2, int(link.get("movement_hours", 1)) * 3)
\t\t_check(state_spatial.set_nominal_capacity(link_id, maxf(1.0, nominal * 30.0)), "R3 high Spatial capacity applies")
\tvar route := state_map.find_route("paris", "marseille", [], "country_fra", state.region_controls, false)
\tvar transit := int(route.get("duration_hours", 0))
\tvar max_food := 0
\tvar delivered := 0.0
\tvar demand := 0.0
\tvar horizon := mini(1400, transit * 3 + 48)
\tfor _hour: int in range(horizon):
\t\tvar result := _advance_result(state, state.last_simulated_hour + 1)
\t\t_check(bool(result.get("success", false)), "long-latency high-capacity hour advances")
\t\tmax_food = maxi(max_food, _supply_count(state, "formation:r3_latency", "food"))
\t\tif state.last_simulated_hour > transit * 2:
\t\t\tvar row: Dictionary = (result.get("supply", {}) as Dictionary).get("formation:r3_latency", {}) as Dictionary
\t\t\tdelivered += float((row.get("delivered", {}) as Dictionary).get("food", 0.0))
\t\t\tdemand += float((row.get("demand", {}) as Dictionary).get("food", 0.0))
\t_check(transit > 0 and max_food >= 3, "long latency increases in-transit inventory")
\t_check(demand > 0.0 and delivered / demand > 0.75, "high capacity preserves steady throughput despite long latency")
\tfor link_id: String in saved.keys():
\t\t(state_map.links[link_id] as Dictionary)["movement_hours"] = int((saved[link_id] as Dictionary)["movement_hours"])
\t\t_check(state_spatial.set_nominal_capacity(link_id, float((saved[link_id] as Dictionary)["nominal_capacity"])), "R3 high Spatial capacity restores")''')

r3_text = r3.read_text(encoding="utf-8")
r3_text = r3_text.replace(
    "var result := service.advance_to_hour(state, map, state.last_simulated_hour + 1)",
    "var result := _advance_result(state, state.last_simulated_hour + 1)",
)
r3_text = r3_text.replace(
    "bool(service.advance_to_hour(continuous, map, target).get(\"success\", false))",
    "bool(_advance_result(continuous, target).get(\"success\", false))",
)
r3_text = r3_text.replace(
    "bool(service.advance_to_hour(restored, map, target).get(\"success\", false))",
    "bool(_advance_result(restored, target).get(\"success\", false))",
)
r3_text = r3_text.replace(
    "bool(service.advance_to_hour(big, map, 160).get(\"success\", false))",
    "bool(_advance_result(big, 160).get(\"success\", false))",
)
r3_text = r3_text.replace(
    "bool(service.advance_to_hour(teleport_state, map, 1).get(\"success\", false))",
    "bool(_advance_result(teleport_state, 1).get(\"success\", false))",
)
r3.write_text(r3_text, encoding="utf-8", newline="\n")

print("PR58 test Spatial contexts isolated successfully")
