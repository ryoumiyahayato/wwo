from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def replace_func(path: str, name: str, replacement: str) -> None:
    text = read(path)
    pattern = re.compile(rf"(?ms)^func {re.escape(name)}\b.*?(?=^func |\Z)")
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"{path}:{name}: expected one function, got {len(matches)}")
    start, end = matches[0].span()
    replacement = replacement.rstrip() + "\n\n\n"
    write(path, text[:start] + replacement + text[end:])


def patch_overlay() -> None:
    path = ROOT / "data/world_map/strategic_military_overlay.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    for profile in data.get("transport_profiles", []):
        for key in ("capacity_personnel", "supply_capacity_per_day", "reliability"):
            profile.pop(key, None)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def patch_map_adapter() -> None:
    path = "scripts/vnext/map/military_map_adapter.gd"
    text = read(path)
    text = text.replace(
        "## Link capacity in this adapter is the single total-capacity truth used by military logistics.",
        "## Spatial owns physical infrastructure and shared capacity; this adapter owns only Military semantics."
    )
    marker = "var city_overlays: Dictionary = {}\n"
    if "var spatial_world: VNextSpatialWorld" not in text:
        text = replace_once(text, marker, marker + "var spatial_world: VNextSpatialWorld = null\n", "spatial world field")
    write(path, text)

    replace_func(path, "load_existing_map", '''func load_existing_map(spatial_world_value: VNextSpatialWorld = null) -> bool:
\terrors.clear()
\t_clear_runtime_indexes()
\tspatial_world = spatial_world_value
\tif spatial_world == null or not spatial_world.is_valid():
\t\terrors.append("authoritative VNextSpatialWorld is required")
\t\treturn false
\tvar source := PrototypeV2Data.new()
\tif not source.load_all():
\t\terrors.append_array(source.errors)
\t\treturn false
\tif not _load_base_documents(source):
\t\treturn false
\tif not _load_overlay():
\t\treturn false
\t_build_network(source)
\tfor link_id: String in _sorted_string_keys(links):
\t\tif spatial_world.infrastructure_state(link_id).is_empty():
\t\t\terrors.append("Military topology link missing from Spatial: %s" % link_id)
\treturn errors.is_empty() and not cities.is_empty() and not links.is_empty()''')

    replace_func(path, "get_all_links", '''func get_all_links() -> Array[Dictionary]:
\tvar result: Array[Dictionary] = []
\tfor link_id: String in _sorted_string_keys(links):
\t\tresult.append(get_link(link_id))
\treturn result


func get_spatial_world() -> VNextSpatialWorld:
\treturn spatial_world


func get_spatial_capacity_summary(link_id: String) -> Dictionary:
\tif spatial_world == null or not spatial_world.is_valid():
\t\treturn {}
\treturn spatial_world.capacity_summary(link_id)''')

    replace_func(path, "get_link_transport_capacity_per_hour", '''func get_link_transport_capacity_per_hour(link_id: String) -> float:
\t# Compatibility query only. The value is read from authoritative Spatial state;
\t# Military never derives or mutates total physical capacity here.
\tif spatial_world == null or not spatial_world.is_valid():
\t\treturn 0.0
\tvar state: Dictionary = spatial_world.infrastructure_state(link_id)
\treturn maxf(0.0, float(state.get("effective_capacity", 0.0)))''')

    replace_func(path, "_add_link", '''func _add_link(
\tlink_id: String,
\tfrom_city_id: String,
\tto_city_id: String,
\tmode: String,
\tdistance_km: float,
\tprofile: Dictionary
) -> void:
\tif link_id.is_empty() or links.has(link_id):
\t\terrors.append("duplicate or empty transport link ID: %s" % link_id)
\t\treturn
\tvar terrain: Dictionary = get_region_terrain(get_region_id_for_city(to_city_id))
\tvar terrain_factor: float = clampf(float(terrain.get("movement_factor", 1.0)), 0.1, 2.0)
\tvar speed: float = maxf(float(profile.get("movement_speed_km_per_day", 1.0)), 1.0)
\tvar movement_hours: int = maxi(int(profile.get("minimum_movement_hours", 12)), ceili(distance_km / speed * 24.0 / terrain_factor))
\tvar link: Dictionary = {
\t\t"id": link_id,
\t\t"from_city_id": from_city_id,
\t\t"to_city_id": to_city_id,
\t\t"mode": mode,
\t\t"distance_km": maxf(0.1, distance_km),
\t\t"movement_hours": movement_hours,
\t}
\tlinks[link_id] = link
\tif not links_by_city.has(from_city_id):
\t\tlinks_by_city[from_city_id] = {}
\tif not links_by_city.has(to_city_id):
\t\tlinks_by_city[to_city_id] = {}
\t(links_by_city[from_city_id] as Dictionary)[link_id] = true
\t(links_by_city[to_city_id] as Dictionary)[link_id] = true''')

    replace_func(path, "_build_route_result", '''func _build_route_result(
\torigin_city_id: String,
\tdestination_city_id: String,
\tprevious_city: Dictionary,
\tprevious_link: Dictionary,
\tdistances: Dictionary
) -> Dictionary:
\tvar reversed_city_ids: Array[String] = []
\tvar reversed_link_ids: Array[String] = []
\tvar cursor: String = destination_city_id
\twhile true:
\t\treversed_city_ids.append(cursor)
\t\tif cursor == origin_city_id:
\t\t\tbreak
\t\tif not previous_city.has(cursor) or not previous_link.has(cursor):
\t\t\treturn _unreachable_route("路径回溯失败。")
\t\treversed_link_ids.append(str(previous_link[cursor]))
\t\tcursor = str(previous_city[cursor])
\treversed_city_ids.reverse()
\treversed_link_ids.reverse()
\tvar route_links: Array[Dictionary] = []
\tvar total_distance_km: float = 0.0
\tvar modes: Array[String] = []
\tfor link_id: String in reversed_link_ids:
\t\tvar link: Dictionary = get_link(link_id)
\t\troute_links.append(link)
\t\ttotal_distance_km += float(link.get("distance_km", 0.0))
\t\tvar mode: String = str(link.get("mode", ""))
\t\tif not modes.has(mode):
\t\t\tmodes.append(mode)
\tvar region_ids: Array[String] = []
\tfor city_id: String in reversed_city_ids:
\t\tvar region_id: String = get_region_id_for_city(city_id)
\t\tif not region_ids.has(region_id):
\t\t\tregion_ids.append(region_id)
\treturn {
\t\t"reachable": true,
\t\t"origin_city_id": origin_city_id,
\t\t"destination_city_id": destination_city_id,
\t\t"city_ids": reversed_city_ids,
\t\t"link_ids": reversed_link_ids,
\t\t"links": route_links,
\t\t"region_ids": region_ids,
\t\t"total_distance_km": total_distance_km,
\t\t"duration_hours": int(distances[destination_city_id]),
\t\t"mode_sequence": modes,
\t}''')


def patch_service() -> None:
    path = "scripts/vnext/military/military_service.gd"
    text = read(path)
    text = text.replace(
        "## Strategic military operations over the existing world-map transport graph.",
        "## Strategic military operations over the existing world-map graph, consuming Spatial physical capacity."
    )
    write(path, text)

    replace_func(path, "advance_to_hour", '''func advance_to_hour(
\tstate: VNextMilitaryState,
\tmap: VNextMilitaryMapAdapter,
\ttarget_hour: int
) -> Dictionary:
\tif state == null or map == null or not state.is_valid(map):
\t\treturn _failure("军事状态无效。")
\tvar spatial: VNextSpatialWorld = map.get_spatial_world()
\tif spatial == null or not spatial.is_valid() or spatial.current_hour() != state.last_simulated_hour:
\t\treturn _failure("军事推进需要与当前边界同步的 Spatial authority。")
\tif target_hour < state.last_simulated_hour:
\t\treturn _failure("军事时间不能倒退。")
\tvar start_hour: int = state.last_simulated_hour
\tvar supply_report: Dictionary = {}
\tvar completed: Array[Dictionary] = []
\tvar battles: Array[Dictionary] = []
\twhile state.last_simulated_hour < target_hour:
\t\tvar hour: int = state.last_simulated_hour
\t\tvar tick: Dictionary = _advance_one_hour(state, map, hour)
\t\tif not bool(tick.get("success", false)):
\t\t\treturn _failure(str(tick.get("reason", "Spatial capacity window advance failed.")))
\t\t_merge_supply_report(supply_report, tick.get("supply", {}) as Dictionary)
\t\tfor raw_completion: Variant in tick.get("completed_actions", []) as Array:
\t\t\tif raw_completion is Dictionary:
\t\t\t\tcompleted.append((raw_completion as Dictionary).duplicate(true))
\t\tfor raw_battle: Variant in tick.get("battles", []) as Array:
\t\t\tif raw_battle is Dictionary:
\t\t\t\tbattles.append((raw_battle as Dictionary).duplicate(true))
\treturn {
\t\t"success": true,
\t\t"elapsed_hours": target_hour - start_hour,
\t\t"supply": supply_report,
\t\t"completed_actions": completed,
\t\t"battles": battles,
\t\t"last_simulated_hour": state.last_simulated_hour,
\t}''')

    replace_func(path, "get_link_capacity_view", '''func get_link_capacity_view(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, link_id: String) -> Dictionary:
\tif state == null or map == null or map.get_link(link_id).is_empty():
\t\treturn {}
\tvar summary: Dictionary = map.get_spatial_capacity_summary(link_id)
\tif summary.is_empty():
\t\treturn {}
\treturn {
\t\t"link_id": link_id,
\t\t"window_hour": state.capacity_window_hour,
\t\t"spatial_window_hour": int(summary.get("window_hour", -1)),
\t\t"capacity_per_hour": float(summary.get("effective_capacity", 0.0)),
\t\t"used_capacity": float(summary.get("used_capacity", 0.0)),
\t\t"available_capacity": float(summary.get("remaining_capacity", 0.0)),
\t\t"military_attributed_capacity": maxf(0.0, float(state.link_capacity_used.get(link_id, 0.0))),
\t\t"queue": (state.link_queues.get(link_id, []) as Array).duplicate(true),
\t}''')

    for func_name in ("_new_transport_action", "_new_supply_action"):
        text = read(path)
        pattern = re.compile(rf"(?ms)^func {re.escape(func_name)}\b.*?(?=^func |\Z)")
        match = pattern.search(text)
        if not match:
            raise RuntimeError(f"missing {func_name}")
        body = match.group(0)
        if '"spatial_request_id"' not in body:
            body = body.replace(
                '\t\t"reserved_link_id": "",\n',
                '\t\t"reserved_link_id": "",\n\t\t"spatial_request_id": "",\n',
                1,
            )
        write(path, text[:match.start()] + body + text[match.end():])

    replace_func(path, "_advance_one_hour", '''func _advance_one_hour(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, hour: int) -> Dictionary:
\tvar spatial: VNextSpatialWorld = map.get_spatial_world()
\tif spatial == null or not spatial.is_valid() or spatial.current_hour() != hour:
\t\treturn {"success": false, "reason": "Spatial capacity window is not synchronized."}
\tstate.begin_capacity_window(hour)

\tvar supply_context: Dictionary = _build_supply_context(state, map)
\t_create_supply_shipments(state, map, hour, supply_context)
\tvar requests: Array[Dictionary] = []
\t_collect_movement_requests(state, map, hour, requests)
\t_collect_supply_transport_requests(state, map, hour, requests)
\t_sort_capacity_requests(requests)

\t# PASS 2: submit every eligible Military demand before applying any progress.
\t# Reverse submission is deliberate: it proves correctness depends on Spatial's
\t# canonical final allocation rather than provisional insertion order.
\tvar submission_order: Array[Dictionary] = requests.duplicate(true)
\tsubmission_order.reverse()
\tfor request: Dictionary in submission_order:
\t\tvar spatial_request_id: String = _spatial_capacity_request_id(request, hour)
\t\trequest["spatial_request_id"] = spatial_request_id
\t\tvar result: Dictionary = spatial.request_capacity(
\t\t\tspatial_request_id,
\t\t\tstr(request.get("link_id", "")),
\t\t\thour,
\t\t\tfloat(request.get("requested_capacity", 0.0))
\t\t)
\t\tif not bool(result.get("accepted", false)):
\t\t\treturn {"success": false, "reason": "Spatial rejected Military capacity request: %s" % str(result.get("reason", "unknown"))}

\t# PASS 3: query final canonical allocations only after every request exists.
\tvar final_allocations: Dictionary = {}
\tfor request: Dictionary in requests:
\t\tvar action_id: String = str(request.get("request_id", ""))
\t\tvar spatial_request_id: String = _spatial_capacity_request_id(request, hour)
\t\trequest["spatial_request_id"] = spatial_request_id
\t\tvar result: Dictionary = spatial.reservation_result(
\t\t\tspatial_request_id, str(request.get("link_id", "")), hour
\t\t)
\t\tif not bool(result.get("accepted", false)):
\t\t\treturn {"success": false, "reason": "Spatial final reservation lookup failed."}
\t\tfinal_allocations[action_id] = maxf(0.0, float(result.get("allocated_capacity", 0.0)))

\t# PASS 4: Military records attribution and progresses actions from final results.
\tfor request: Dictionary in requests:
\t\tif str(request.get("request_kind", "")) == "movement":
\t\t\t_apply_movement_capacity_request(state, request, final_allocations, hour)
\t\telse:
\t\t\t_apply_supply_capacity_request(state, request, final_allocations, hour)

\tvar supply_report: Dictionary = _finalize_supply_hour(state, map, supply_context)
\tvar boundary_hour: int = hour + 1
\tstate.last_simulated_hour = boundary_hour
\tvar completed: Array[Dictionary] = []
\tvar battles: Array[Dictionary] = []
\t_advance_actions_at_boundary(state, map, boundary_hour, completed, battles)

\t# Closing the physical window is authoritative in Spatial. Military keeps only
\t# historical attribution; no closed Spatial reservation object is required.
\tif not spatial.advance_to_hour(boundary_hour):
\t\treturn {"success": false, "reason": "Spatial capacity window rollover failed."}
\t_clear_spatial_request_references(state)
\treturn {"success": true, "supply": supply_report, "completed_actions": completed, "battles": battles}''')

    replace_func(path, "_collect_movement_requests", '''func _collect_movement_requests(
\tstate: VNextMilitaryState,
\tmap: VNextMilitaryMapAdapter,
\thour: int,
\trequests: Array[Dictionary]
) -> void:
\tfor action_id: String in _sorted_dictionary_keys(state.active_actions):
\t\tvar action: Dictionary = state.active_actions[action_id] as Dictionary
\t\tvar kind: String = str(action.get("kind", ""))
\t\tif kind in ["defend", "supply"] or str(action.get("transport_state", "")) == "preparing":
\t\t\tcontinue
\t\tvar formation: VNextMilitaryFormation = state.get_formation(str(action.get("formation_id", "")))
\t\tif formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
\t\t\tcontinue
\t\tvar route: Dictionary = action.get("route", {}) as Dictionary
\t\tvar link_ids: Array = route.get("link_ids", []) as Array
\t\tvar edge_index: int = int(action.get("current_edge_index", -1))
\t\tif edge_index < 0 or edge_index >= link_ids.size():
\t\t\tcontinue
\t\tvar link_id: String = str(link_ids[edge_index])
\t\tvar can_enter: bool = map.can_enter_link(
\t\t\tlink_id, formation.current_city_id, str(action.get("destination_city_id", "")),
\t\t\tformation.country_id, state.region_controls, bool(action.get("allow_enemy_destination", false))
\t\t)
\t\tif not can_enter:
\t\t\t_cancel_active_spatial_request(map, action)
\t\t\taction["reserved_link_id"] = ""
\t\t\taction["spatial_request_id"] = ""
\t\t\taction["transport_state"] = "interrupted" if map.get_link_transport_capacity_per_hour(link_id) <= 0.0 else "blocked"
\t\t\tstate.active_actions[action_id] = action
\t\t\tcontinue
\t\tvar demand: float = maxf(0.0, float(action.get("edge_load_remaining", 0.0)))
\t\tif demand <= EPSILON:
\t\t\taction["reserved_link_id"] = ""
\t\t\taction["spatial_request_id"] = ""
\t\t\taction["transport_state"] = "moving"
\t\t\tstate.active_actions[action_id] = action
\t\t\tcontinue
\t\taction["transport_state"] = "waiting_capacity"
\t\taction["reserved_link_id"] = link_id
\t\tstate.active_actions[action_id] = action
\t\trequests.append({
\t\t\t"request_kind": "movement",
\t\t\t"request_hour": int(action.get("edge_request_hour", action.get("start_hour", hour))),
\t\t\t"request_id": action_id,
\t\t\t"formation_id": formation.formation_id,
\t\t\t"resource_id": "",
\t\t\t"link_id": link_id,
\t\t\t"requested_capacity": demand,
\t\t})''')

    replace_func(path, "_collect_supply_transport_requests", '''func _collect_supply_transport_requests(
\tstate: VNextMilitaryState,
\tmap: VNextMilitaryMapAdapter,
\thour: int,
\trequests: Array[Dictionary]
) -> void:
\tfor action_id: String in _sorted_dictionary_keys(state.active_actions):
\t\tvar action: Dictionary = state.active_actions[action_id] as Dictionary
\t\tif str(action.get("kind", "")) != "supply" or str(action.get("transport_state", "")) == "arrived":
\t\t\tcontinue
\t\tvar formation: VNextMilitaryFormation = state.get_formation(str(action.get("destination_formation_id", "")))
\t\tif formation == null or formation.formation_status != VNextMilitaryFormation.STATUS_ACTIVE:
\t\t\tcontinue
\t\tvar route: Dictionary = action.get("route", {}) as Dictionary
\t\tvar link_ids: Array = route.get("link_ids", []) as Array
\t\tvar edge_index: int = int(action.get("current_edge_index", -1))
\t\tif edge_index < 0 or edge_index >= link_ids.size():
\t\t\tcontinue
\t\tvar link_id: String = str(link_ids[edge_index])
\t\tvar can_enter: bool = map.can_enter_link(
\t\t\tlink_id, str(action.get("current_city_id", "")), str(action.get("destination_city_id", "")),
\t\t\tstr(action.get("owner_country_id", "")), state.region_controls, false
\t\t)
\t\tif not can_enter:
\t\t\t_cancel_active_spatial_request(map, action)
\t\t\taction["reserved_link_id"] = ""
\t\t\taction["spatial_request_id"] = ""
\t\t\taction["transport_state"] = "interrupted" if map.get_link_transport_capacity_per_hour(link_id) <= 0.0 else "blocked"
\t\t\tstate.active_actions[action_id] = action
\t\t\tcontinue
\t\tvar demand: float = maxf(0.0, float(action.get("edge_load_remaining", 0.0)))
\t\tif demand <= EPSILON:
\t\t\taction["reserved_link_id"] = ""
\t\t\taction["spatial_request_id"] = ""
\t\t\taction["transport_state"] = "moving"
\t\t\tstate.active_actions[action_id] = action
\t\t\tcontinue
\t\taction["transport_state"] = "waiting_capacity"
\t\taction["reserved_link_id"] = link_id
\t\tstate.active_actions[action_id] = action
\t\trequests.append({
\t\t\t"request_kind": "supply",
\t\t\t"request_hour": int(action.get("edge_request_hour", action.get("start_hour", hour))),
\t\t\t"request_id": action_id,
\t\t\t"formation_id": str(action.get("destination_formation_id", "")),
\t\t\t"resource_id": str(action.get("resource_id", "")),
\t\t\t"link_id": link_id,
\t\t\t"requested_capacity": demand,
\t\t})''')

    apply_template = '''func {name}(
\tstate: VNextMilitaryState,
\trequest: Dictionary,
\tfinal_allocations: Dictionary,
\thour: int
) -> void:
\tvar action_id: String = str(request.get("request_id", ""))
\tif not state.active_actions.has(action_id):
\t\treturn
\tvar action: Dictionary = state.active_actions[action_id] as Dictionary
{kind_guard}\tvar link_id: String = str(request.get("link_id", ""))
\tstate.queue_capacity_request(link_id, action_id)
\tvar remaining: float = maxf(0.0, float(action.get("edge_load_remaining", 0.0)))
\tvar allocation: float = minf(remaining, maxf(0.0, float(final_allocations.get(action_id, 0.0))))
\taction["spatial_request_id"] = str(request.get("spatial_request_id", ""))
\tif allocation > EPSILON:
\t\tstate.record_capacity_use(link_id, allocation)
\t\taction = state.active_actions[action_id] as Dictionary
\t\taction["spatial_request_id"] = str(request.get("spatial_request_id", ""))
\t\taction["capacity_window_hour"] = state.capacity_window_hour
\t\taction["capacity_link_id"] = link_id
\t\taction["capacity_used_this_window"] = allocation
\t\taction["edge_load_remaining"] = maxf(0.0, remaining - allocation)
\t\taction["transport_state"] = "moving"
\t\tif int(action.get("edge_started_hour", -1)) < 0:
\t\t\taction["edge_started_hour"] = hour
\telse:
\t\taction["transport_state"] = "waiting_capacity"
\tif float(action.get("edge_load_remaining", 0.0)) <= EPSILON:
\t\taction["reserved_link_id"] = ""
\tstate.active_actions[action_id] = action'''
    replace_func(path, "_apply_movement_capacity_request", apply_template.format(name="_apply_movement_capacity_request", kind_guard=""))
    replace_func(path, "_apply_supply_capacity_request", apply_template.format(
        name="_apply_supply_capacity_request",
        kind_guard='\tif str(action.get("kind", "")) != "supply":\n\t\treturn\n'
    ))

    # Insert helper functions immediately before the existing request sorter.
    text = read(path)
    marker = "func _sort_capacity_requests(requests: Array[Dictionary]) -> void:"
    helpers = '''func _spatial_capacity_request_id(request: Dictionary, window_hour: int) -> String:
\treturn "%016d|%016d|military|%s|%s" % [
\t\tint(request.get("request_hour", window_hour)), window_hour,
\t\tstr(request.get("request_id", "")), str(request.get("request_kind", "")),
\t]


func _cancel_active_spatial_request(map: VNextMilitaryMapAdapter, action: Dictionary) -> void:
\tvar spatial: VNextSpatialWorld = map.get_spatial_world() if map != null else null
\tvar request_id: String = str(action.get("spatial_request_id", ""))
\tvar link_id: String = str(action.get("capacity_link_id", action.get("reserved_link_id", "")))
\tvar window_hour: int = int(action.get("capacity_window_hour", -1))
\tif spatial != null and not request_id.is_empty() and not link_id.is_empty() and window_hour == spatial.current_hour():
\t\tspatial.cancel_capacity_request(request_id, link_id, window_hour)


func _clear_spatial_request_references(state: VNextMilitaryState) -> void:
\tfor action_id: String in _sorted_dictionary_keys(state.active_actions):
\t\tvar action: Dictionary = state.active_actions[action_id] as Dictionary
\t\taction["spatial_request_id"] = ""
\t\tstate.active_actions[action_id] = action


'''
    if "func _spatial_capacity_request_id" not in text:
        text = replace_once(text, marker, helpers + marker, "capacity helper insertion")
        write(path, text)


def patch_state_and_invariants() -> None:
    state_path = "scripts/vnext/military/military_state.gd"
    text = read(state_path)
    text = text.replace(
        "## Dynamic military state. Static geography and total link capacity remain in the map adapter.",
        "## Dynamic military state. Spatial owns physical infrastructure/capacity; this state keeps Military attribution only."
    )
    text = text.replace(
        "# Current one-hour transport ledger. The map owns total capacity; this state owns only use/queue facts.",
        "# Last closed Military transport window: diagnostic attribution only, never a physical budget or authority."
    )
    text = replace_once(
        text,
        "func restore(snapshot_value: Dictionary, map: VNextMilitaryMapAdapter = null) -> bool:",
        "func restore(snapshot_value: Dictionary, map: VNextMilitaryMapAdapter = null, spatial_world: VNextSpatialWorld = null) -> bool:",
        "Military restore signature",
    )
    text = replace_once(
        text,
        "if not candidate_state.is_valid(map) or not VNextMilitaryStateInvariants.validate(candidate_state, map):",
        "if not candidate_state.is_valid(map) or not VNextMilitaryStateInvariants.validate(candidate_state, map, spatial_world):",
        "Military restore combined validation",
    )
    write(state_path, text)

    inv_path = "scripts/vnext/military/military_state_invariants.gd"
    replace_func(inv_path, "validate", '''static func validate(
\tstate: VNextMilitaryState,
\tmap: VNextMilitaryMapAdapter,
\tspatial_world: VNextSpatialWorld = null
) -> bool:
\tif state == null:
\t\treturn false
\tif not _validate_action_lifecycles(state):
\t\treturn false
\tif not _validate_control_provenance(state, map):
\t\treturn false
\tif not _validate_transport_chronology(state):
\t\treturn false
\tif not _validate_capacity_ledger(state, map, spatial_world):
\t\treturn false
\treturn true''')

    replace_func(inv_path, "_validate_capacity_ledger", '''static func _validate_capacity_ledger(
\tstate: VNextMilitaryState,
\tmap: VNextMilitaryMapAdapter,
\tspatial_world: VNextSpatialWorld = null
) -> bool:
\tvar explained: Dictionary = {}
\tfor action_id: String in _sorted_dictionary_keys(state.active_actions):
\t\tvar action: Dictionary = state.active_actions[action_id] as Dictionary
\t\tif not _validate_capacity_record(state, map, spatial_world, action, true, explained):
\t\t\treturn false
\tfor record: Dictionary in state.completed_actions:
\t\tif not _validate_capacity_record(state, map, spatial_world, record, false, explained):
\t\t\treturn false
\n\tvar link_ids: Dictionary = {}
\tfor raw_link_id: Variant in state.link_capacity_used.keys():
\t\tlink_ids[str(raw_link_id)] = true
\tfor raw_link_id: Variant in explained.keys():
\t\tlink_ids[str(raw_link_id)] = true
\tfor link_id: String in _sorted_dictionary_keys(link_ids):
\t\tvar actual: float = float(state.link_capacity_used.get(link_id, 0.0))
\t\tvar expected: float = float(explained.get(link_id, 0.0))
\t\tif not is_finite(actual) or actual < 0.0 or absf(actual - expected) > EPSILON:
\t\t\treturn false
\t\tif map != null and map.get_link(link_id).is_empty():
\t\t\treturn false
\treturn true''')

    replace_func(inv_path, "_validate_capacity_record", '''static func _validate_capacity_record(
\tstate: VNextMilitaryState,
\tmap: VNextMilitaryMapAdapter,
\tspatial_world: VNextSpatialWorld,
\trecord: Dictionary,
\tis_active: bool,
\texplained: Dictionary
) -> bool:
\tvar window_hour: int = int(record.get("capacity_window_hour", -1))
\tvar link_id: String = str(record.get("capacity_link_id", ""))
\tvar used: float = float(record.get("capacity_used_this_window", 0.0))
\tvar spatial_request_id: String = str(record.get("spatial_request_id", ""))
\tif not is_finite(used) or used < 0.0 or window_hour < -1 or window_hour > state.capacity_window_hour:
\t\treturn false
\tif not spatial_request_id.is_empty():
\t\t# A persisted current reservation reference is legal only while Spatial still
\t\t# owns that exact current request. Closed historical attribution never needs it.
\t\tif spatial_world == null or window_hour != spatial_world.current_hour() or link_id.is_empty():
\t\t\treturn false
\t\tvar reservation: Dictionary = spatial_world.reservation_result(spatial_request_id, link_id, window_hour)
\t\tif not bool(reservation.get("accepted", false)):
\t\t\treturn false
\t\tif absf(float(reservation.get("allocated_capacity", -1.0)) - used) > EPSILON:
\t\t\treturn false
\tif used <= EPSILON:
\t\treturn link_id.is_empty() or not spatial_request_id.is_empty()
\tif link_id.is_empty() or map == null or map.get_link(link_id).is_empty():
\t\treturn false
\tif not _capacity_link_matches_record(record, link_id, is_active):
\t\treturn false
\tif window_hour == state.capacity_window_hour:
\t\texplained[link_id] = float(explained.get(link_id, 0.0)) + used
\treturn true''')


def patch_tests() -> None:
    # Old Military tests now construct one authoritative Spatial world and mutate
    # its infrastructure API rather than Military-local link capacity fields.
    for path in ("tests/vnext/military_strategy_test.gd", "tests/vnext/military_r3_findings_test.gd"):
        text = read(path)
        if "var spatial: VNextSpatialWorld" not in text:
            text = text.replace("var map: VNextMilitaryMapAdapter\n", "var map: VNextMilitaryMapAdapter\nvar spatial: VNextSpatialWorld\n", 1)
        old = "\tmap = VNextMilitaryMapAdapter.new()\n\t_check(map.load_existing_map(),"
        new = "\tspatial = VNextSpatialWorld.create_from_legacy_world_map()\n\t_check(spatial != null and spatial.is_valid(), \"authoritative Spatial world loads\")\n\tmap = VNextMilitaryMapAdapter.new()\n\t_check(map.load_existing_map(spatial),"
        if old not in text:
            raise RuntimeError(f"{path}: map setup pattern missing")
        text = text.replace(old, new, 1)
        write(path, text)

    path = "tests/vnext/military_strategy_test.gd"
    text = read(path)
    replacements = [
        (
            'var original_capacity := int((map.links[link_id] as Dictionary).get("capacity_personnel", 0))\n\t(map.links[link_id] as Dictionary)["capacity_personnel"] = 0',
            'var original_capacity := float(spatial.infrastructure_state(link_id).get("nominal_capacity", 0.0))\n\t_check(spatial.set_nominal_capacity(link_id, 0.0), "Spatial zero capacity fixture applies")'
        ),
        ('\t(map.links[link_id] as Dictionary)["capacity_personnel"] = original_capacity', '\t_check(spatial.set_nominal_capacity(link_id, original_capacity), "Spatial capacity fixture restores")'),
        (
            'var original_capacity := int((map.links[rail_link] as Dictionary).get("capacity_personnel", 0))\n\t(map.links[rail_link] as Dictionary)["capacity_personnel"] = 10',
            'var original_capacity := float(spatial.infrastructure_state(rail_link).get("nominal_capacity", 0.0))\n\t_check(spatial.set_nominal_capacity(rail_link, 10.0), "small Spatial capacity fixture applies")'
        ),
        ('\t(map.links[rail_link] as Dictionary)["capacity_personnel"] = original_capacity', '\t_check(spatial.set_nominal_capacity(rail_link, original_capacity), "small Spatial capacity fixture restores")'),
        (
            'var saved_capacity := int((map.links[zero_link] as Dictionary).get("capacity_personnel", 0))\n\t\tvar cargo_before := float(zero_shipment.get("cargo_amount_remaining", 0.0))\n\t\t(map.links[zero_link] as Dictionary)["capacity_personnel"] = 0',
            'var saved_capacity := float(spatial.infrastructure_state(zero_link).get("nominal_capacity", 0.0))\n\t\tvar cargo_before := float(zero_shipment.get("cargo_amount_remaining", 0.0))\n\t\t_check(spatial.set_infrastructure_status(zero_link, VNextInfrastructureLinkState.STATUS_INTERRUPTED), "authoritative Spatial interruption applies")'
        ),
        ('\t\t(map.links[zero_link] as Dictionary)["capacity_personnel"] = saved_capacity', '\t\t_check(spatial.set_nominal_capacity(zero_link, saved_capacity) and spatial.restore_infrastructure(zero_link), "authoritative Spatial capacity recovers")'),
    ]
    for old, new in replacements:
        if old not in text:
            raise RuntimeError(f"strategy capacity fixture pattern missing: {old[:60]}")
        text = text.replace(old, new, 1)
    write(path, text)

    path = "tests/vnext/military_r3_findings_test.gd"
    text = read(path)
    replacements = [
        (
            'var saved_capacity := int((map.links[link_id] as Dictionary).get("capacity_personnel", 0))\n\t(map.links[link_id] as Dictionary)["capacity_personnel"] = 40',
            'var saved_capacity := float(spatial.infrastructure_state(link_id).get("nominal_capacity", 0.0))\n\t_check(spatial.set_nominal_capacity(link_id, 40.0), "R3 Spatial capacity limit applies")'
        ),
        ('\t(map.links[link_id] as Dictionary)["capacity_personnel"] = saved_capacity', '\t_check(spatial.set_nominal_capacity(link_id, saved_capacity), "R3 Spatial capacity limit restores")'),
        (
            'saved[link_id] = {"movement_hours": int(link.get("movement_hours", 1)), "capacity_personnel": int(link.get("capacity_personnel", 0))}\n\t\tlink["movement_hours"] = maxi(2, int(link.get("movement_hours", 1)) * 3)\n\t\tlink["capacity_personnel"] = maxi(1, int(link.get("capacity_personnel", 0)) * 30)',
            'var nominal := float(spatial.infrastructure_state(link_id).get("nominal_capacity", 0.0))\n\t\tsaved[link_id] = {"movement_hours": int(link.get("movement_hours", 1)), "nominal_capacity": nominal}\n\t\tlink["movement_hours"] = maxi(2, int(link.get("movement_hours", 1)) * 3)\n\t\t_check(spatial.set_nominal_capacity(link_id, maxf(1.0, nominal * 30.0)), "R3 high Spatial capacity applies")'
        ),
        (
            '\t\t(map.links[link_id] as Dictionary)["movement_hours"] = int((saved[link_id] as Dictionary)["movement_hours"])\n\t\t(map.links[link_id] as Dictionary)["capacity_personnel"] = int((saved[link_id] as Dictionary)["capacity_personnel"])',
            '\t\t(map.links[link_id] as Dictionary)["movement_hours"] = int((saved[link_id] as Dictionary)["movement_hours"])\n\t\t_check(spatial.set_nominal_capacity(link_id, float((saved[link_id] as Dictionary)["nominal_capacity"])), "R3 high Spatial capacity restores")'
        ),
        (
            'var saved_capacity := int((map.links[link_id] as Dictionary).get("capacity_personnel", 0))\n\t(map.links[link_id] as Dictionary)["capacity_personnel"] = 0',
            'var saved_capacity := float(spatial.infrastructure_state(link_id).get("nominal_capacity", 0.0))\n\t_check(spatial.set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_INTERRUPTED), "R3 authoritative Spatial interruption applies")'
        ),
        ('\t(map.links[link_id] as Dictionary)["capacity_personnel"] = saved_capacity', '\t_check(spatial.set_nominal_capacity(link_id, saved_capacity) and spatial.restore_infrastructure(link_id), "R3 authoritative Spatial interruption recovers")'),
    ]
    for old, new in replacements:
        if old not in text:
            raise RuntimeError(f"R3 capacity fixture pattern missing: {old[:60]}")
        text = text.replace(old, new, 1)
    write(path, text)

    leftovers = []
    for path in ("tests/vnext/military_strategy_test.gd", "tests/vnext/military_r3_findings_test.gd"):
        text = read(path)
        if "capacity_personnel" in text:
            leftovers.append(path)
    if leftovers:
        raise RuntimeError(f"obsolete Military capacity fixture remains: {leftovers}")


def write_integration_test() -> None:
    content = r'''extends SceneTree

var checks := 0
var failures := 0
var service := VNextMilitaryService.new()

func _initialize() -> void:
\t_run.call_deferred()

func _run() -> void:
\t_test_two_phase_movement_contention()
\t_test_supply_shared_spatial_capacity()
\t_test_interruption_history_recovery_snapshot()
\t_test_corrupt_spatial_reference_rejected()
\t_test_large_vs_hourly()
\t_test_authority_boundary_source()
\tprint("VNext Military/Spatial capacity integration: %d checks, %d failures" % [checks, failures])
\tquit(1 if failures > 0 or checks <= 0 else 0)

func _fixture() -> Dictionary:
\tvar spatial := VNextSpatialWorld.create_from_legacy_world_map()
\tvar map := VNextMilitaryMapAdapter.new()
\t_check(spatial != null and spatial.is_valid(), "fixture Spatial world loads")
\t_check(map.load_existing_map(spatial), "fixture Military adapter consumes Spatial")
\tvar state := VNextMilitaryState.new()
\t_check(state.initialize(map), "fixture Military state initializes")
\treturn {"spatial": spatial, "map": map, "state": state}

func _add(state: VNextMilitaryState, map: VNextMilitaryMapAdapter, id: String, city: String, personnel: int) -> void:
\t_check(service.create_formation(
\t\tstate, map, id, "country_fra", city, personnel,
\t\t{"equipment_factor": 0.0}, 0.9, 0.9, 0.9,
\t\t{"food": 2400.0, "ammunition": 240.0, "equipment": 48.0, "transport_capacity": 24.0}
\t), "formation created: %s" % id)

func _rail_link(map: VNextMilitaryMapAdapter, state: VNextMilitaryState) -> String:
\tvar route := map.find_route("paris", "rouen", ["rail"], "country_fra", state.region_controls, false)
\tvar ids: Array = route.get("link_ids", []) as Array
\treturn "" if ids.is_empty() else str(ids[0])

func _test_two_phase_movement_contention() -> void:
\tvar f := _fixture()
\tvar spatial: VNextSpatialWorld = f["spatial"]
\tvar map: VNextMilitaryMapAdapter = f["map"]
\tvar state: VNextMilitaryState = f["state"]
\tvar link_id := _rail_link(map, state)
\t_check(not link_id.is_empty(), "contention rail link exists")
\t_check(spatial.set_nominal_capacity(link_id, 100.0), "contention capacity set in Spatial")
\t_add(state, map, "formation:spatial_a", "paris", 1000)
\t_add(state, map, "formation:spatial_b", "paris", 1000)
\tvar first := service.move(state, map, "formation:spatial_a", "rouen", 0)
\tvar second := service.move(state, map, "formation:spatial_b", "rouen", 0)
\t_check(bool(first.get("success", false)) and bool(second.get("success", false)), "two movement demands accepted by Military")
\t_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "two-phase contention hour advances")
\tvar first_action: Dictionary = state.active_actions.get(str(first.get("action_id", "")), {}) as Dictionary
\tvar second_action: Dictionary = state.active_actions.get(str(second.get("action_id", "")), {}) as Dictionary
\tvar a := float(first_action.get("capacity_used_this_window", 0.0))
\tvar b := float(second_action.get("capacity_used_this_window", 0.0))
\t_check(a > b and a + b <= 100.0001, "final canonical allocation, not provisional reverse submission, drives progress")
\t_check(is_equal_approx(float(state.link_capacity_used.get(link_id, 0.0)), a + b), "Military ledger is derived attribution")
\t_check(spatial.current_hour() == 1 and spatial.used_capacity(link_id) == 0.0, "Spatial rolled physical window and owns current usage")

func _test_supply_shared_spatial_capacity() -> void:
\tvar f := _fixture()
\tvar spatial: VNextSpatialWorld = f["spatial"]
\tvar map: VNextMilitaryMapAdapter = f["map"]
\tvar state: VNextMilitaryState = f["state"]
\tvar link_id := _rail_link(map, state)
\t_check(spatial.set_nominal_capacity(link_id, 120.0), "shared supply capacity set in Spatial")
\t_add(state, map, "formation:spatial_mover", "paris", 800)
\t_add(state, map, "formation:spatial_supply", "rouen", 800)
\t_check(service.set_supply_input(state, map, "paris_basin", {"food": 240000.0, "ammunition": 24000.0, "equipment": 4800.0, "transport_capacity": 2400.0}), "remote supply source configured")
\tvar move := service.move(state, map, "formation:spatial_mover", "rouen", 0)
\t_check(bool(move.get("success", false)), "movement demand issued")
\t_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "movement plus supply Spatial hour advances")
\tvar queue: Array = state.link_queues.get(link_id, []) as Array
\tvar saw_supply := false
\tfor action_id: Variant in queue:
\t\tvar action: Dictionary = state.active_actions.get(str(action_id), {}) as Dictionary
\t\tif str(action.get("kind", "")) == "supply":
\t\t\tsaw_supply = true
\t_check(queue.has(move.get("action_id", "")) and saw_supply, "movement and rolling supply submit into one Spatial-backed window")
\t_check(float(state.link_capacity_used.get(link_id, 0.0)) <= 120.0001, "movement plus supply attribution is bounded by one Spatial capacity")

func _test_interruption_history_recovery_snapshot() -> void:
\tvar f := _fixture()
\tvar spatial: VNextSpatialWorld = f["spatial"]
\tvar map: VNextMilitaryMapAdapter = f["map"]
\tvar state: VNextMilitaryState = f["state"]
\tvar link_id := _rail_link(map, state)
\t_check(spatial.set_nominal_capacity(link_id, 150.0), "interruption capacity configured")
\t_add(state, map, "formation:spatial_interrupt", "paris", 1200)
\tvar move := service.move(state, map, "formation:spatial_interrupt", "rouen", 0)
\t_check(bool(service.advance_to_hour(state, map, 1).get("success", false)), "warm movement hour advances")
\tvar action_id := str(move.get("action_id", ""))
\tvar before: Dictionary = state.active_actions[action_id] as Dictionary
\tvar historical_used := float(before.get("capacity_used_this_window", 0.0))
\tvar remaining_before := float(before.get("edge_load_remaining", 0.0))
\t_check(historical_used > 0.0, "warm hour leaves historical Military attribution")
\t_check(spatial.set_infrastructure_status(link_id, VNextInfrastructureLinkState.STATUS_INTERRUPTED), "Spatial physical interruption applies")
\t_check(VNextMilitaryStateInvariants.validate(state, map, spatial), "closed historical attribution survives later Spatial capacity change")
\t_check(bool(service.advance_to_hour(state, map, 2).get("success", false)), "zero-capacity next hour advances normally")
\tvar interrupted: Dictionary = state.active_actions[action_id] as Dictionary
\t_check(str(interrupted.get("transport_state", "")) == "interrupted", "zero Spatial capacity interrupts Military action")
\t_check(is_equal_approx(float(interrupted.get("edge_load_remaining", -1.0)), remaining_before), "zero Spatial capacity makes no movement progress")
\t_check(str(interrupted.get("spatial_request_id", "")).is_empty(), "closed/interrupted action retains no stale Spatial reservation")
\n\tvar military_snapshot := state.snapshot()
\tvar spatial_snapshot := spatial.snapshot()
\tvar restored_spatial := VNextSpatialWorld.create_from_legacy_world_map()
\t_check(restored_spatial.restore(spatial_snapshot), "interrupted Spatial snapshot restores")
\tvar restored_map := VNextMilitaryMapAdapter.new()
\t_check(restored_map.load_existing_map(restored_spatial), "restored Military adapter attaches restored Spatial")
\tvar restored_state := VNextMilitaryState.new()
\t_check(restored_state.restore(military_snapshot, restored_map, restored_spatial), "interrupted Military snapshot restores transactionally")
\t_check(spatial.restore_infrastructure(link_id) and restored_spatial.restore_infrastructure(link_id), "both Spatial worlds recover capacity")
\t_check(bool(service.advance_to_hour(state, map, 3).get("success", false)), "continuous action resumes after recovery")
\t_check(bool(service.advance_to_hour(restored_state, restored_map, 3).get("success", false)), "restored action resumes after recovery")
\t_check(state.snapshot() == restored_state.snapshot(), "interrupted snapshot continuation is deterministic")
\t_check(spatial.snapshot() == restored_spatial.snapshot(), "Spatial continuation is deterministic")

func _test_corrupt_spatial_reference_rejected() -> void:
\tvar f := _fixture()
\tvar spatial: VNextSpatialWorld = f["spatial"]
\tvar map: VNextMilitaryMapAdapter = f["map"]
\tvar state: VNextMilitaryState = f["state"]
\t_add(state, map, "formation:spatial_corrupt", "paris", 800)
\tvar move := service.move(state, map, "formation:spatial_corrupt", "rouen", 0)
\t_check(bool(move.get("success", false)) and bool(service.advance_to_hour(state, map, 1).get("success", false)), "corruption fixture advances")
\tvar corrupted := state.snapshot().duplicate(true)
\tvar actions: Array = corrupted.get("active_actions", []) as Array
\tif not actions.is_empty():
\t\t(actions[0] as Dictionary)["spatial_request_id"] = "not-a-real-spatial-request"
\tvar target := VNextMilitaryState.new()
\t_check(not target.restore(corrupted, map, spatial), "stale/current Spatial reservation reference is rejected")

func _test_large_vs_hourly() -> void:
\tvar big := _fixture()
\tvar sliced := _fixture()
\tvar big_state: VNextMilitaryState = big["state"]
\tvar sliced_state: VNextMilitaryState = sliced["state"]
\t_add(big_state, big["map"], "formation:spatial_partition", "paris", 600)
\t_add(sliced_state, sliced["map"], "formation:spatial_partition", "paris", 600)
\t_check(bool(service.move(big_state, big["map"], "formation:spatial_partition", "marseille", 0).get("success", false)), "large partition move issued")
\t_check(bool(service.move(sliced_state, sliced["map"], "formation:spatial_partition", "marseille", 0).get("success", false)), "sliced partition move issued")
\t_check(bool(service.advance_to_hour(big_state, big["map"], 48).get("success", false)), "large Spatial/Military advance succeeds")
\tvar sliced_ok := true
\tfor hour: int in range(1, 49):
\t\tif not bool(service.advance_to_hour(sliced_state, sliced["map"], hour).get("success", false)):
\t\t\tsliced_ok = false
\t\t\tbreak
\t_check(sliced_ok, "hourly Spatial/Military advance succeeds")
\t_check(big_state.snapshot() == sliced_state.snapshot(), "large versus hourly Military state is identical")
\t_check((big["spatial"] as VNextSpatialWorld).snapshot() == (sliced["spatial"] as VNextSpatialWorld).snapshot(), "large versus hourly Spatial state is identical")

func _test_authority_boundary_source() -> void:
\tvar adapter_source := FileAccess.get_file_as_string("res://scripts/vnext/map/military_map_adapter.gd")
\tvar service_source := FileAccess.get_file_as_string("res://scripts/vnext/military/military_service.gd")
\tvar overlay := FileAccess.get_file_as_string("res://data/world_map/strategic_military_overlay.json")
\t_check(not overlay.contains("capacity_personnel") and not overlay.contains("supply_capacity_per_day") and not overlay.contains("\\\"reliability\\\""), "Military overlay no longer defines physical capacity")
\t_check(adapter_source.contains("spatial_world.infrastructure_state") and service_source.contains("spatial.request_capacity"), "Military consumes Spatial physical authority")
\t_check(not service_source.contains("var budgets: Dictionary"), "Military-local physical budget removed")

func _check(condition: bool, label: String) -> void:
\tchecks += 1
\tif not condition:
\t\tfailures += 1
\t\tpush_error("FAIL: %s" % label)
'''
    write("tests/vnext/military_spatial_capacity_integration_test.gd", content.replace("\\t", "\t"))


def patch_docs() -> None:
    path = "docs/vnext/military_strategy.md"
    text = read(path)
    section = '''\n## Post-PR62 Spatial physical-capacity boundary\n\n`VNextSpatialWorld` is the sole authority for physical infrastructure status, nominal/effective link capacity, and the active per-link/per-hour shared allocation window. Military owns only transport demand, Military access/controller eligibility, action progress, and current/historical allocation attribution.\n\nFor every hour Military first collects all eligible movement and rolling-supply demand without applying progress. It then submits all requests to the current Spatial window, queries every final `reservation_result()` after the full request set exists, and only then applies progress. This two-phase submit/query/apply rule is required because Spatial canonical ordering may reallocate an earlier provisional result after a later request is inserted. Movement and supply therefore contend inside one physical Spatial budget, leaving the same authority available for future Economy demand.\n\nSpatial reservations are window-scoped. At the boundary Spatial rolls to the next hour and clears active requests; Military clears transient Spatial request references but retains bounded historical attribution (`capacity_window_hour`, `capacity_link_id`, `capacity_used_this_window`). Closed legal attribution is never compared retroactively with a later changed Spatial capacity. If current Spatial effective capacity is zero, the Military action remains persistent and becomes interrupted without movement/cargo progress; restoration permits a deterministic new-window request with the same Military action identity.\n\nMilitary snapshots persist formations, actions, shipment state, progress, and Military attribution only. Spatial snapshots persist infrastructure and the authoritative physical capacity window. Combined restore is candidate-first: any persisted non-empty current Spatial request reference must resolve to the same Spatial link/window/allocation, while closed historical attribution does not require an old Spatial reservation object. No service locator, duplicate world map, or Military-owned physical budget is introduced.\n'''
    if "## Post-PR62 Spatial physical-capacity boundary" not in text:
        text = text.rstrip() + "\n" + section
    text = text.replace("single total-capacity truth", "Military attribution view")
    write(path, text)


def authority_static_checks() -> None:
    adapter = read("scripts/vnext/map/military_map_adapter.gd")
    service = read("scripts/vnext/military/military_service.gd")
    overlay = read("data/world_map/strategic_military_overlay.json")
    forbidden_overlay = ["capacity_personnel", "supply_capacity_per_day", '"reliability"']
    for token in forbidden_overlay:
        if token in overlay:
            raise RuntimeError(f"overlay still contains physical authority field {token}")
    if "var budgets: Dictionary" in service:
        raise RuntimeError("Military-local physical budget remains")
    if "spatial.request_capacity" not in service or "spatial.reservation_result" not in service:
        raise RuntimeError("two-phase Spatial allocation calls missing")
    if "spatial_world.infrastructure_state" not in adapter:
        raise RuntimeError("map adapter does not query Spatial physical state")


def main() -> None:
    patch_overlay()
    patch_map_adapter()
    patch_service()
    patch_state_and_invariants()
    patch_tests()
    write_integration_test()
    patch_docs()
    authority_static_checks()
    print("PR58 Spatial capacity integration patch applied successfully")


if __name__ == "__main__":
    main()
