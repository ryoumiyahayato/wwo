from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"{label}: expected one match, got {text.count(old)}")
    return text.replace(old, new, 1)


def replace_func(path: str, name: str, body: str) -> None:
    text = read(path)
    pattern = re.compile(rf"(?ms)^(?:static )?func {re.escape(name)}\b.*?(?=^(?:static )?func |\Z)")
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"{path}:{name}: expected one function, got {len(matches)}")
    start, end = matches[0].span()
    write(path, text[:start] + body.rstrip() + "\n\n\n" + text[end:])


def patch_spatial_batch_api() -> None:
    path = "scripts/vnext/spatial/spatial_capacity_window.gd"
    text = read(path)
    if "func request_capacity_batch(" not in text:
        marker = "func reserve_capacity(\n"
        batch = '''func request_capacity_batch(request_values: Array[Dictionary]) -> Dictionary:
\tvar rejected: Dictionary = {
\t\t"success": false,
\t\t"accepted": false,
\t\t"reason": "",
\t\t"results": {},
\t}
\tif not _is_internal_state_valid():
\t\trejected["reason"] = "invalid_capacity_state"
\t\treturn rejected
\tif request_values.is_empty():
\t\trejected["reason"] = "empty_batch"
\t\treturn rejected

\t# Validate the complete batch into a candidate first. Nothing authoritative is
\t# mutated until every request is known to be structurally legal.
\tvar candidate_requests: Dictionary = {}
\tfor link_id: String in _catalog.link_ids():
\t\tcandidate_requests[link_id] = (_requests[link_id] as Dictionary).duplicate(true)
\tfor request_value: Dictionary in request_values:
\t\tif not _has_fields(request_value, ["request_id", "link_id", "window_hour", "demand"]):
\t\t\trejected["reason"] = "invalid_batch_request"
\t\t\treturn rejected
\t\tif typeof(request_value.get("request_id")) != TYPE_STRING or typeof(request_value.get("link_id")) != TYPE_STRING:
\t\t\trejected["reason"] = "invalid_batch_request"
\t\t\treturn rejected
\t\tvar request_id: String = str(request_value.get("request_id", ""))
\t\tvar link_id: String = str(request_value.get("link_id", ""))
\t\tvar window_hour: int = _parse_hour(request_value.get("window_hour"))
\t\tvar demand: float = _parse_positive_finite(request_value.get("demand"))
\t\tif not _is_valid_request_id(request_id):
\t\t\trejected["reason"] = "invalid_request_id"
\t\t\treturn rejected
\t\tif not _catalog.has_link(link_id):
\t\t\trejected["reason"] = "unknown_link"
\t\t\treturn rejected
\t\tif window_hour != _current_hour:
\t\t\trejected["reason"] = "wrong_window"
\t\t\treturn rejected
\t\tif demand <= 0.0:
\t\t\trejected["reason"] = "invalid_demand"
\t\t\treturn rejected
\t\tif _request_exists_in(candidate_requests, request_id):
\t\t\trejected["reason"] = "duplicate_request"
\t\t\treturn rejected
\t\t(candidate_requests[link_id] as Dictionary)[request_id] = {
\t\t\t"request_id": request_id,
\t\t\t"link_id": link_id,
\t\t\t"window_hour": window_hour,
\t\t\t"demand": _round_capacity(demand),
\t\t\t"allocated_capacity": 0.0,
\t\t}

\t# One authoritative canonical recomputation for the whole accepted batch.
\t# This has exactly the same sorted-request allocation semantics as submitting
\t# each request separately, without O(n^2) repeated recomputation.
\tvar previous_requests: Dictionary = _requests
\t_requests = candidate_requests
\t_recompute_allocations()
\tif not _is_internal_state_valid():
\t\t_requests = previous_requests
\t\trejected["reason"] = "invalid_capacity_state"
\t\treturn rejected
\tvar results: Dictionary = {}
\tfor request_value: Dictionary in request_values:
\t\tvar request_id: String = str(request_value.get("request_id", ""))
\t\tvar link_id: String = str(request_value.get("link_id", ""))
\t\tresults[request_id] = reservation_result(request_id, link_id, _current_hour)
\treturn {
\t\t"success": true,
\t\t"accepted": true,
\t\t"reason": "",
\t\t"results": results,
\t}


'''
        text = replace_once(text, marker, batch + marker, "Spatial batch API insertion")
        write(path, text)

    path = "scripts/vnext/spatial/spatial_world.gd"
    text = read(path)
    if "func request_capacity_batch(" not in text:
        marker = "func reserve_capacity(\n"
        wrapper = '''func request_capacity_batch(request_values: Array[Dictionary]) -> Dictionary:
\tif _capacity == null:
\t\treturn {"success": false, "accepted": false, "reason": "invalid_world", "results": {}}
\treturn _capacity.request_capacity_batch(request_values)


'''
        text = replace_once(text, marker, wrapper + marker, "Spatial world batch wrapper")
        write(path, text)


def patch_military_batch_submission() -> None:
    path = "scripts/vnext/military/military_service.gd"
    text = read(path)
    pattern = re.compile(r'(?ms)\t# PASS 2: submit every eligible Military demand before applying any progress\.\n.*?\t# PASS 3: query final canonical allocations only after every request exists\.\n')
    match = pattern.search(text)
    if not match:
        raise RuntimeError("Military PASS2 submission block not found")
    replacement = '''\t# PASS 2: submit every eligible Military demand as one transactional Spatial
\t# batch. Reverse construction is deliberate: final results must still follow
\t# Spatial canonical request ordering rather than caller insertion order.
\tvar submission_order: Array[Dictionary] = requests.duplicate(true)
\tsubmission_order.reverse()
\tvar spatial_batch: Array[Dictionary] = []
\tfor request: Dictionary in submission_order:
\t\tvar spatial_request_id: String = _spatial_capacity_request_id(request, hour)
\t\trequest["spatial_request_id"] = spatial_request_id
\t\tspatial_batch.append({
\t\t\t"request_id": spatial_request_id,
\t\t\t"link_id": str(request.get("link_id", "")),
\t\t\t"window_hour": hour,
\t\t\t"demand": float(request.get("requested_capacity", 0.0)),
\t\t})
\tif not spatial_batch.is_empty():
\t\tvar batch_result: Dictionary = spatial.request_capacity_batch(spatial_batch)
\t\tif not bool(batch_result.get("accepted", false)):
\t\t\treturn {"success": false, "reason": "Spatial rejected Military capacity batch: %s" % str(batch_result.get("reason", "unknown"))}

\t# PASS 3: query final canonical allocations only after every request exists.
'''
    text = text[:match.start()] + replacement + text[match.end():]
    write(path, text)


def patch_annihilation_release() -> None:
    path = "scripts/vnext/military/military_service.gd"
    text = read(path)
    # Release any current-window Spatial request before the existing R4 cleanup
    # erases the Military action. This does not move combat logic into Spatial.
    text = replace_once(
        text,
        "\t_cleanup_all_destroyed_formation_references(state, boundary_hour, completed)\n",
        "\t_cancel_destroyed_formation_spatial_requests(state, map)\n\t_cleanup_all_destroyed_formation_references(state, boundary_hour, completed)\n",
        "boundary annihilation Spatial release",
    )
    text = replace_once(
        text,
        "\tif attacker.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:\n\t\t_cleanup_destroyed_formation_references(state, attacker.formation_id, state.last_simulated_hour, completed, current_action_id)\n\tfor destroyed_formation_id: String in destroyed_defenders:\n\t\t_cleanup_destroyed_formation_references(state, destroyed_formation_id, state.last_simulated_hour, completed)\n",
        "\tif attacker.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:\n\t\t_cancel_spatial_requests_for_formation(state, map, attacker.formation_id, current_action_id)\n\t\t_cleanup_destroyed_formation_references(state, attacker.formation_id, state.last_simulated_hour, completed, current_action_id)\n\tfor destroyed_formation_id: String in destroyed_defenders:\n\t\t_cancel_spatial_requests_for_formation(state, map, destroyed_formation_id)\n\t\t_cleanup_destroyed_formation_references(state, destroyed_formation_id, state.last_simulated_hour, completed)\n",
        "combat annihilation Spatial release",
    )
    marker = "func _cleanup_all_destroyed_formation_references(state: VNextMilitaryState, boundary_hour: int, completed: Array[Dictionary]) -> void:"
    helpers = '''func _cancel_destroyed_formation_spatial_requests(
\tstate: VNextMilitaryState, map: VNextMilitaryMapAdapter
) -> void:
\tfor formation_id: String in state.get_sorted_formation_ids():
\t\tvar formation: VNextMilitaryFormation = state.get_formation(formation_id)
\t\tif formation != null and formation.formation_status == VNextMilitaryFormation.STATUS_DESTROYED:
\t\t\t_cancel_spatial_requests_for_formation(state, map, formation_id)


func _cancel_spatial_requests_for_formation(
\tstate: VNextMilitaryState,
\tmap: VNextMilitaryMapAdapter,
\tformation_id: String,
\tpreserve_action_id: String = ""
) -> void:
\tfor action_id: String in _sorted_dictionary_keys(state.active_actions):
\t\tif action_id == preserve_action_id or not state.active_actions.has(action_id):
\t\t\tcontinue
\t\tvar action: Dictionary = state.active_actions[action_id] as Dictionary
\t\tvar belongs_to_destroyed: bool = (
\t\t\t(str(action.get("kind", "")) == "supply" and str(action.get("destination_formation_id", "")) == formation_id)
\t\t\tor str(action.get("formation_id", "")) == formation_id
\t\t)
\t\tif not belongs_to_destroyed:
\t\t\tcontinue
\t\t_cancel_active_spatial_request(map, action)
\t\taction["spatial_request_id"] = ""
\t\tstate.active_actions[action_id] = action


'''
    if "func _cancel_destroyed_formation_spatial_requests(" not in text:
        text = replace_once(text, marker, helpers + marker, "annihilation helper insertion")
    write(path, text)


def patch_spatial_tests() -> None:
    path = "tests/vnext/spatial_infrastructure_test.gd"
    text = read(path)
    call = "\t_test_deterministic_request_permutation()\n"
    if "\t_test_batch_capacity_submission()\n" not in text:
        text = replace_once(text, call, call + "\t_test_batch_capacity_submission()\n", "Spatial batch test call")
    marker = "func _test_territorial_mutation_and_projection() -> void:"
    if "func _test_batch_capacity_submission()" not in text:
        test = '''func _test_batch_capacity_submission() -> void:
\tvar first := _world()
\tvar second := _world()
\tif first == null or second == null:
\t\treturn
\t_check(first.set_nominal_capacity("rail_paris_lille", 100), "batch fixture configures first capacity")
\t_check(second.set_nominal_capacity("rail_paris_lille", 100), "batch fixture configures second capacity")
\tvar reverse_batch: Array[Dictionary] = [
\t\t{"request_id": "request_b", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 60.0},
\t\t{"request_id": "request_a", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 60.0},
\t]
\tvar forward_batch: Array[Dictionary] = [
\t\t{"request_id": "request_a", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 60.0},
\t\t{"request_id": "request_b", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 60.0},
\t]
\t_check(first.request_capacity_batch(reverse_batch).get("accepted", false), "reverse batch is accepted transactionally")
\t_check(second.request_capacity_batch(forward_batch).get("accepted", false), "forward batch is accepted transactionally")
\t_equal(first.reservation_result("request_a", "rail_paris_lille", 0).get("allocated_capacity"), 60.0, "batch canonical lower ID gets first allocation")
\t_equal(first.reservation_result("request_b", "rail_paris_lille", 0).get("allocated_capacity"), 40.0, "batch canonical higher ID gets partial allocation")
\t_equal(first.capacity_summary("rail_paris_lille"), second.capacity_summary("rail_paris_lille"), "batch insertion permutations have identical final allocation")
\tvar before_invalid := first.snapshot()
\tvar invalid_batch: Array[Dictionary] = [
\t\t{"request_id": "request_c", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 10.0},
\t\t{"request_id": "request_c", "link_id": "rail_paris_lille", "window_hour": 0, "demand": 10.0},
\t]
\t_check(not first.request_capacity_batch(invalid_batch).get("accepted", false), "duplicate batch request is rejected")
\t_equal(first.snapshot(), before_invalid, "rejected batch leaves Spatial window unchanged")


'''
        text = replace_once(text, marker, test + marker, "Spatial batch test insertion")
    write(path, text)


def patch_docs_and_integration_assertions() -> None:
    path = "docs/vnext/spatial_infrastructure.md"
    text = read(path)
    paragraph = '''\n### Transactional batch submission\n\n`request_capacity_batch()` is the minimal shared-contract extension for domains that may submit many same-window requests. It validates the complete batch before mutation, inserts the accepted requests transactionally, performs exactly one canonical allocation recomputation, and then exposes the same `reservation_result()` values as individual requests. Request-ID sorting, effective-capacity bounds, zero-capacity behavior, rollover, snapshot and restore semantics are unchanged. The batch API exists to avoid repeated O(n²) reallocations when persistent Military logistics creates many simultaneous requests; it does not grant Military any capacity authority.\n'''
    if "### Transactional batch submission" not in text:
        anchor = "## Territorial facts\n"
        text = replace_once(text, anchor, paragraph + "\n" + anchor, "Spatial batch docs")
        write(path, text)

    path = "tests/vnext/military_spatial_capacity_integration_test.gd"
    text = read(path)
    text = text.replace(
        'adapter_source.contains("spatial_world.infrastructure_state") and service_source.contains("spatial.request_capacity")',
        'adapter_source.contains("spatial_world.infrastructure_state") and service_source.contains("spatial.request_capacity_batch") and service_source.contains("spatial.reservation_result")',
    )
    if 'service_source.contains("_cancel_spatial_requests_for_formation")' not in text:
        needle = '\t_check(not service_source.contains("var budgets: Dictionary"), "Military-local physical budget removed")\n'
        repl = needle + '\t_check(service_source.contains("_cancel_spatial_requests_for_formation") and service_source.contains("cancel_capacity_request"), "annihilation cleanup releases current Spatial requests")\n'
        text = replace_once(text, needle, repl, "annihilation source regression")
    write(path, text)


def main() -> None:
    patch_spatial_batch_api()
    patch_military_batch_submission()
    patch_annihilation_release()
    patch_spatial_tests()
    patch_docs_and_integration_assertions()
    print("PR58 minimal Spatial batch extension applied successfully")


if __name__ == "__main__":
    main()
