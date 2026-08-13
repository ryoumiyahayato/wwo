from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8", newline="\n")


def replace_func(path: str, name: str, body: str) -> None:
    text = read(path)
    pattern = re.compile(rf"(?ms)^(?:static )?func {re.escape(name)}\b.*?(?=^(?:static )?func |\Z)")
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise RuntimeError(f"{path}:{name}: expected one function, got {len(matches)}")
    start, end = matches[0].span()
    write(path, text[:start] + body.rstrip() + "\n\n\n" + text[end:])


def main() -> None:
    path = "scripts/vnext/spatial/spatial_capacity_window.gd"
    replace_func(path, "request_capacity_batch", '''func request_capacity_batch(request_values: Array[Dictionary]) -> Dictionary:
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

\tvar previous_requests: Dictionary = _requests
\t_requests = candidate_requests
\t_recompute_allocations()
\tif not _is_internal_state_valid():
\t\t_requests = previous_requests
\t\trejected["reason"] = "invalid_capacity_state"
\t\treturn rejected

\t# Build the response from one canonical calculation. Calling
\t# reservation_result() once per member would recursively recalculate the whole
\t# window and turn a batch into O(n^2) while producing identical values.
\tvar calculation: Dictionary = _calculate_allocations()
\tvar usage_by_link: Dictionary = calculation.get("usage", {})
\tvar results: Dictionary = {}
\tfor request_value: Dictionary in request_values:
\t\tvar request_id: String = str(request_value.get("request_id", ""))
\t\tvar link_id: String = str(request_value.get("link_id", ""))
\t\tvar request: Dictionary = (_requests[link_id] as Dictionary)[request_id]
\t\tvar demand: float = float(request.get("demand", 0.0))
\t\tvar allocated: float = float(request.get("allocated_capacity", 0.0))
\t\tvar result: Dictionary = _result_base(request_id, link_id, _current_hour, demand, allocated)
\t\tresult["success"] = true
\t\tresult["accepted"] = true
\t\tresult["status"] = _allocation_status(demand, allocated)
\t\tresult["remaining_capacity"] = float((usage_by_link.get(link_id, {}) as Dictionary).get("remaining_capacity", 0.0))
\t\tresults[request_id] = result
\treturn {"success": true, "accepted": true, "reason": "", "results": results}''')

    doc_path = "docs/vnext/spatial_infrastructure.md"
    doc = read(doc_path)
    old = "performs exactly one canonical allocation recomputation, and then exposes the same final reservation values"
    new = "performs one canonical allocation recomputation plus one linear response calculation, and then exposes the same final reservation values"
    if old in doc:
        doc = doc.replace(old, new, 1)
    write(doc_path, doc)
    print("Spatial batch response recomputation optimized successfully")


if __name__ == "__main__":
    main()
