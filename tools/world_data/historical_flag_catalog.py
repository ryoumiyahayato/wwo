"""Strict, read-only access to the formal 1900 historical flag catalog.

The repository contains many JSON objects below ``data/world_map``.  A record
with an ``asset_path`` is not automatically a flag record: callers must load
the one declared historical flag catalog and validate its schema first.  The
catalog also permits a small set of object/reference wrappers so a resource
path cannot disappear merely because a producer adds a supported envelope.
"""

from __future__ import annotations

import json
from collections.abc import Iterator, Mapping
from pathlib import Path
from typing import Any


FLAG_REGISTRY_RELATIVE = "data/world_map/historical/flags_1900.json"
FLAG_ASSET_PREFIX = "res://assets/historical_flags/1900/"
SUPPORTED_REFERENCE_KEYS = frozenset(
    {
        "data",
        "entry",
        "entries",
        "item",
        "items",
        "object",
        "objects",
        "payload",
        "record",
        "records",
        "reference",
        "references",
        "resource",
        "resources",
        "value",
    }
)
REQUIRED_RECORD_KEYS = (
    "id",
    "render_mode",
    "flag_type",
    "valid_from",
    "valid_to",
    "ratio",
)


def _walk_supported(value: Any) -> Iterator[Mapping[str, Any]]:
    if isinstance(value, Mapping):
        yield value
        for key, child in value.items():
            if str(key) in SUPPORTED_REFERENCE_KEYS:
                yield from _walk_supported(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_supported(child)


def is_historical_flag_record(value: Any) -> bool:
    return isinstance(value, Mapping) and all(key in value for key in REQUIRED_RECORD_KEYS) and bool(
        str(value.get("id", ""))
    )


def resource_path_for_record(record: Mapping[str, Any]) -> str:
    for node in _walk_supported(record):
        for key in ("asset_path", "resource_path"):
            value = node.get(key)
            if isinstance(value, str) and value:
                return value
    return ""


def validate_historical_flag_catalog(document: Any) -> tuple[dict[str, Mapping[str, Any]], list[str]]:
    errors: list[str] = []
    if not isinstance(document, Mapping):
        return {}, ["catalog root must be an object"]
    if document.get("schema_version") != 1:
        errors.append("schema_version must be 1")
    if document.get("snapshot_date") != "1900-03-12":
        errors.append("snapshot_date must be 1900-03-12")
    policy = document.get("policy")
    if not isinstance(policy, Mapping) or policy.get("source_asset_required_for_rendered_flag") is not True:
        errors.append("policy.source_asset_required_for_rendered_flag must be true")

    raw_records = document.get("records")
    if not isinstance(raw_records, Mapping):
        return {}, [*errors, "records must be an object"]

    records: dict[str, Mapping[str, Any]] = {}
    for entry_key, raw_record in raw_records.items():
        entry_id = str(entry_key)
        candidates = [node for node in _walk_supported(raw_record) if is_historical_flag_record(node)]
        if not candidates:
            errors.append(f"records.{entry_id} does not contain a supported historical flag record")
            continue
        if len(candidates) != 1:
            errors.append(f"records.{entry_id} contains {len(candidates)} historical flag records")
            continue
        record = candidates[0]
        record_id = str(record.get("id", ""))
        if record_id != entry_id:
            errors.append(f"records.{entry_id}.id must equal its catalog key")
            continue
        if record_id in records:
            errors.append(f"duplicate historical flag id: {record_id}")
            continue
        records[record_id] = record

    record_count = document.get("record_count")
    if not isinstance(record_count, int) or isinstance(record_count, bool) or record_count != len(records):
        errors.append("record_count must equal the validated historical flag record count")
    return records, sorted(set(errors))


def load_historical_flag_catalog(repository_root: Path) -> tuple[dict[str, Any], dict[str, Mapping[str, Any]], list[str]]:
    path = repository_root / Path(FLAG_REGISTRY_RELATIVE)
    document = json.loads(path.read_text(encoding="utf-8"))
    records, errors = validate_historical_flag_catalog(document)
    return dict(document) if isinstance(document, Mapping) else {}, records, errors


def source_asset_records(records: Mapping[str, Mapping[str, Any]]) -> dict[str, Mapping[str, Any]]:
    return {
        record_id: record
        for record_id, record in records.items()
        if record.get("render_mode") == "source_asset"
        and resource_path_for_record(record).startswith(FLAG_ASSET_PREFIX)
    }
