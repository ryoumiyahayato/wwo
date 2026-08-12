"""Repository provenance-reference resolution for the 1900 staging pack."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


REFERENCE_RE = re.compile(r"^(?P<path>[^#\s]+)#(?P<fragment>[^\s]+)$")


def _load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def validate_repository_source_reference(
    root: Path,
    reference: Any,
    *,
    expected_record_id: str | None = None,
) -> list[str]:
    """Resolve tracked.json#collection.record[.field] references.

    The current source pack uses the units.<id> fragment form. The resolver
    rejects absolute paths, traversal, missing files, malformed fragments,
    and dangling IDs rather than treating them as citation-only strings.
    """

    errors: list[str] = []
    if not isinstance(reference, str):
        return ["source_reference must be a string"]
    match = REFERENCE_RE.fullmatch(reference)
    if match is None:
        return ["source_reference must contain a path and non-empty fragment"]
    relative_path = match.group("path")
    fragment = match.group("fragment")
    path = Path(relative_path)
    if path.is_absolute() or ".." in path.parts or ":" in relative_path:
        return ["source_reference path must be a repository-relative path"]
    target = (root / path).resolve()
    root_resolved = root.resolve()
    if root_resolved not in target.parents:
        return ["source_reference escapes the repository root"]
    if not target.is_file():
        return [f"source_reference file does not exist: {relative_path}"]
    try:
        document = _load(target)
    except (OSError, json.JSONDecodeError) as exc:
        return [f"source_reference file cannot be parsed: {exc}"]
    parts = fragment.split(".")
    if len(parts) < 2 or not parts[0] or not parts[1]:
        return ["source_reference fragment must use collection.record syntax"]
    collection, record_id = parts[0], parts[1]
    records = document.get(collection) if isinstance(document, dict) else None
    if not isinstance(records, list):
        return [f"source_reference collection is not a list: {collection}"]
    matches = [record for record in records if isinstance(record, dict) and record.get("id") == record_id]
    if len(matches) != 1:
        return [f"source_reference fragment does not resolve exactly once: {fragment}"]
    if expected_record_id is not None and record_id != expected_record_id:
        return [f"source_reference resolves to {record_id!r}, expected {expected_record_id!r}"]
    if len(parts) > 2 and parts[2] not in matches[0]:
        return [f"source_reference field does not exist: {'.'.join(parts[2:])}"]
    return errors
