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


def patch_capacity_query() -> None:
    path = "scripts/vnext/spatial/spatial_capacity_window.gd"
    text = read(path)
    if "func reservation_results_batch(" not in text:
        marker = "func capacity_summary(link_id: String) -> Dictionary:\n"
        func = '''func reservation_results_batch(request_values: Array[Dictionary]) -> Dictionary:
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
\tvar calculation: Dictionary = _calculate_allocations()
\tvar usage_by_link: Dictionary = calculation.get("usage", {})
\tvar results: Dictionary = {}
\tfor request_value: Dictionary in request_values:
\t\tif not _has_fields(request_value, ["request_id", "link_id", "window_hour"]):
\t\t\trejected["reason"] = "invalid_batch_request"
\t\t\treturn rejected
\t\tvar request_id: String = str(request_value.get("request_id", ""))
\t\tvar link_id: String = str(request_value.get("link_id", ""))
\t\tvar window_hour: int = _parse_hour(request_value.get("window_hour"))
\t\tif window_hour != _current_hour:
\t\t\trejected["reason"] = "wrong_window"
\t\t\treturn rejected
\t\tif not _requests.has(link_id) or not (_requests[link_id] as Dictionary).has(request_id):
\t\t\trejected["reason"] = "unknown_request"
\t\t\treturn rejected
\t\tvar request: Dictionary = (_requests[link_id] as Dictionary)[request_id]
\t\tvar demand: float = float(request.get("demand", 0.0))
\t\tvar allocated: float = float(request.get("allocated_capacity", 0.0))
\t\tvar result: Dictionary = _result_base(request_id, link_id, window_hour, demand, allocated)
\t\tresult["success"] = true
\t\tresult["accepted"] = true
\t\tresult["status"] = _allocation_status(demand, allocated)
\t\tresult["remaining_capacity"] = float((usage_by_link.get(link_id, {}) as Dictionary).get("remaining_capacity", 0.0))
\t\tresults[request_id] = result
\treturn {"success": true, "accepted": true, "reason": "", "results": results}


'''
        text = replace_once(text, marker, func + marker, "batch final query insertion")
        write(path, text)

    path = "scripts/vnext/spatial/spatial_world.gd"
    text = read(path)
    if "func reservation_results_batch(" not in text:
        marker = "func capacity_summary(link_id: String) -> Dictionary:\n"
        wrapper = '''func reservation_results_batch(request_values: Array[Dictionary]) -> Dictionary:
\tif _capacity == null:
\t\treturn {"success": false, "accepted": false, "reason": "invalid_world", "results": {}}
\treturn _capacity.reservation_results_batch(request_values)


'''
        text = replace_once(text, marker, wrapper + marker, "world batch final query wrapper")
        write(path, text)


def patch_service_final_query() -> None:
    path = "scripts/vnext/military/military_service.gd"
    text = read(path)
    pattern = re.compile(r'(?ms)\t# PASS 3: query final canonical allocations only after every request exists\.\n.*?\t# PASS 4: Military records attribution and progresses actions from final results\.\n')
    match = pattern.search(text)
    if not match:
        raise RuntimeError("Military PASS3 query block not found")
    replacement = '''\t# PASS 3: query every final reservation result only after the full batch exists.
\t# The batch query is read-only and performs one canonical calculation for the
\t# complete result set; it is equivalent to final reservation_result() calls.
\tvar final_query: Dictionary = spatial.reservation_results_batch(spatial_batch) if not spatial_batch.is_empty() else {"accepted": true, "results": {}}
\tif not bool(final_query.get("accepted", false)):
\t\treturn {"success": false, "reason": "Spatial final reservation batch lookup failed."}
\tvar final_results: Dictionary = final_query.get("results", {}) as Dictionary
\tvar final_allocations: Dictionary = {}
\tfor request: Dictionary in requests:
\t\tvar action_id: String = str(request.get("request_id", ""))
\t\tvar spatial_request_id: String = _spatial_capacity_request_id(request, hour)
\t\trequest["spatial_request_id"] = spatial_request_id
\t\tvar result: Dictionary = final_results.get(spatial_request_id, {}) as Dictionary
\t\tif not bool(result.get("accepted", false)):
\t\t\treturn {"success": false, "reason": "Spatial final reservation lookup failed."}
\t\tfinal_allocations[action_id] = maxf(0.0, float(result.get("allocated_capacity", 0.0)))

\t# PASS 4: Military records attribution and progresses actions from final results.
'''
    write(path, text[:match.start()] + replacement + text[match.end():])


def patch_tests_docs() -> None:
    path = "tests/vnext/spatial_infrastructure_test.gd"
    text = read(path)
    needle = '\t_check(second.request_capacity_batch(forward_batch).get("accepted", false), "forward batch is accepted transactionally")\n'
    insert = needle + '\tvar final_batch: Dictionary = first.reservation_results_batch(reverse_batch)\n\t_check(final_batch.get("accepted", false), "batch final reservation query is accepted")\n\t_equal(((final_batch.get("results", {}) as Dictionary).get("request_a", {}) as Dictionary).get("allocated_capacity"), 60.0, "batch final query preserves canonical allocation")\n'
    if "batch final reservation query is accepted" not in text:
        text = replace_once(text, needle, insert, "Spatial final batch query regression")
        write(path, text)

    path = "docs/vnext/spatial_infrastructure.md"
    text = read(path)
    text = text.replace(
        "performs exactly one canonical allocation recomputation, and then exposes the same `reservation_result()` values as individual requests.",
        "performs exactly one canonical allocation recomputation, and then exposes the same final reservation values through `reservation_results_batch()` or individual `reservation_result()` queries."
    )
    write(path, text)

    path = "tests/vnext/military_spatial_capacity_integration_test.gd"
    text = read(path)
    text = text.replace(
        'service_source.contains("spatial.request_capacity_batch") and service_source.contains("spatial.reservation_result")',
        'service_source.contains("spatial.request_capacity_batch") and service_source.contains("spatial.reservation_results_batch")'
    )
    write(path, text)


def main() -> None:
    patch_capacity_query()
    patch_service_final_query()
    patch_tests_docs()
    print("PR58 batch final Spatial reservation query applied successfully")


if __name__ == "__main__":
    main()
