#!/usr/bin/env python3
"""Validate and fingerprint immutable territory-source acquisition evidence."""

from __future__ import annotations

import copy
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping


SCHEMA_ID = "territory_source_acquisition_record_v1"
STATUS_PINNED_AWAITING_BYTES = "PINNED_AWAITING_BYTES"
STATUS_ACQUIRED = "ACQUIRED"
STATUS_VERIFIED = "VERIFIED"
VERIFICATION_PENDING = "PENDING"
VERIFICATION_PASSED = "PASSED"
VERIFICATION_FAILED = "FAILED"

ACQUISITION_STATUSES = {
    STATUS_PINNED_AWAITING_BYTES,
    STATUS_ACQUIRED,
    STATUS_VERIFIED,
}
VERIFICATION_STATUSES = {
    VERIFICATION_PENDING,
    VERIFICATION_PASSED,
    VERIFICATION_FAILED,
}

REQUIRED_FIELDS = (
    "schema_id",
    "source_snapshot_id",
    "provider",
    "archive",
    "object_filename",
    "object_url",
    "snapshot_timestamp",
    "snapshot_kind",
    "advertised_size",
    "exact_byte_size",
    "published_checksum",
    "raw_sha256",
    "pbf_header_timestamp",
    "complete_planet_verified",
    "acquisition_status",
    "verification_status",
    "acquired_at",
    "acquisition_method",
    "verification_method",
    "notes",
    "record_fingerprint",
)

FINGERPRINT_FIELDS = (
    "source_snapshot_id",
    "provider",
    "archive",
    "object_filename",
    "object_url",
    "snapshot_timestamp",
    "snapshot_kind",
    "advertised_size",
    "exact_byte_size",
    "published_checksum",
    "raw_sha256",
    "pbf_header_timestamp",
    "complete_planet_verified",
    "acquisition_method",
    "verification_method",
)

SOURCE_ID_PATTERN = re.compile(r"^territory_source:[a-z0-9_-]+$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
PLANET_FILENAME_PATTERN = re.compile(
    r"^planet-(?P<yy>\d{2})(?P<month>\d{2})(?P<day>\d{2})_"
    r"(?P<hour>\d{2})(?P<minute>\d{2})\.osm\.pbf$"
)


def canonical_json_bytes(value: Mapping[str, Any]) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def record_fingerprint(record: Mapping[str, Any]) -> str:
    stable = {field: record.get(field) for field in FINGERPRINT_FIELDS}
    return hashlib.sha256(canonical_json_bytes(stable)).hexdigest()


def load_acquisition_record(path: Path) -> dict[str, Any]:
    """Return a fresh detached record; no mutable process-global cache is kept."""
    loaded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(loaded, dict):
        raise ValueError("acquisition record must be a JSON object")
    return copy.deepcopy(loaded)


def _parse_timestamp(value: Any, field_name: str, errors: list[str]) -> datetime | None:
    if not isinstance(value, str) or not value:
        errors.append(f"{field_name}: required UTC timestamp is missing")
        return None
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        errors.append(f"{field_name}: expected YYYY-MM-DDTHH:MM:SSZ")
        return None
    return parsed.replace(tzinfo=timezone.utc)


def _filename_timestamp(filename: Any, errors: list[str]) -> datetime | None:
    if not isinstance(filename, str):
        errors.append("object_filename: expected string")
        return None
    match = PLANET_FILENAME_PATTERN.fullmatch(filename)
    if match is None:
        errors.append("object_filename: expected planet-YYMMDD_HHMM.osm.pbf")
        return None
    try:
        return datetime(
            2000 + int(match.group("yy")),
            int(match.group("month")),
            int(match.group("day")),
            int(match.group("hour")),
            int(match.group("minute")),
            tzinfo=timezone.utc,
        )
    except ValueError:
        errors.append("object_filename: encoded timestamp is invalid")
        return None


def validate_record(record: Mapping[str, Any]) -> list[str]:
    errors: list[str] = []
    for field in REQUIRED_FIELDS:
        if field not in record:
            errors.append(f"{field}: required field missing")
    if errors:
        return errors

    if record.get("schema_id") != SCHEMA_ID:
        errors.append(f"schema_id: expected {SCHEMA_ID}")

    source_id = record.get("source_snapshot_id")
    if not isinstance(source_id, str) or SOURCE_ID_PATTERN.fullmatch(source_id) is None:
        errors.append("source_snapshot_id: expected territory_source:<lowercase_stable_id>")

    for field in (
        "provider",
        "archive",
        "object_filename",
        "object_url",
        "snapshot_timestamp",
        "snapshot_kind",
        "advertised_size",
        "acquisition_method",
        "verification_method",
    ):
        value = record.get(field)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{field}: required non-empty string")

    filename = record.get("object_filename")
    object_url = record.get("object_url")
    if isinstance(filename, str) and isinstance(object_url, str) and not object_url.endswith("/" + filename):
        errors.append("object_url: must resolve the exact object_filename")

    snapshot_timestamp = _parse_timestamp(record.get("snapshot_timestamp"), "snapshot_timestamp", errors)
    filename_timestamp = _filename_timestamp(filename, errors)
    if snapshot_timestamp is not None and filename_timestamp is not None and snapshot_timestamp != filename_timestamp:
        errors.append("snapshot_timestamp: does not match timestamp encoded in object_filename")

    exact_byte_size = record.get("exact_byte_size")
    if exact_byte_size is not None and (
        isinstance(exact_byte_size, bool)
        or not isinstance(exact_byte_size, int)
        or exact_byte_size <= 0
    ):
        errors.append("exact_byte_size: expected null or positive integer")

    published_checksum = record.get("published_checksum")
    if not isinstance(published_checksum, str):
        errors.append("published_checksum: expected string")

    raw_sha256 = record.get("raw_sha256")
    if not isinstance(raw_sha256, str):
        errors.append("raw_sha256: expected string")
    elif raw_sha256 and SHA256_PATTERN.fullmatch(raw_sha256) is None:
        errors.append("raw_sha256: expected lowercase 64-character SHA-256")

    pbf_header_timestamp_raw = record.get("pbf_header_timestamp")
    pbf_header_timestamp: datetime | None = None
    if not isinstance(pbf_header_timestamp_raw, str):
        errors.append("pbf_header_timestamp: expected string")
    elif pbf_header_timestamp_raw:
        pbf_header_timestamp = _parse_timestamp(
            pbf_header_timestamp_raw,
            "pbf_header_timestamp",
            errors,
        )

    complete_planet_verified = record.get("complete_planet_verified")
    if complete_planet_verified is not None and not isinstance(complete_planet_verified, bool):
        errors.append("complete_planet_verified: expected null or boolean")

    acquisition_status = record.get("acquisition_status")
    if acquisition_status not in ACQUISITION_STATUSES:
        errors.append("acquisition_status: unsupported value")
    verification_status = record.get("verification_status")
    if verification_status not in VERIFICATION_STATUSES:
        errors.append("verification_status: unsupported value")

    acquired_at_raw = record.get("acquired_at")
    if not isinstance(acquired_at_raw, str):
        errors.append("acquired_at: expected string")
    elif acquired_at_raw:
        _parse_timestamp(acquired_at_raw, "acquired_at", errors)

    notes = record.get("notes")
    if not isinstance(notes, str):
        errors.append("notes: expected string")

    if snapshot_timestamp is not None and pbf_header_timestamp is not None:
        delta = snapshot_timestamp - pbf_header_timestamp
        if delta.total_seconds() < 0 or delta.total_seconds() > 24 * 60 * 60:
            errors.append(
                "pbf_header_timestamp: must not be later than the pinned snapshot timestamp "
                "or more than 24 hours earlier"
            )

    verified_state_requested = (
        acquisition_status == STATUS_VERIFIED
        or verification_status == VERIFICATION_PASSED
    )
    if verified_state_requested:
        if acquisition_status != STATUS_VERIFIED or verification_status != VERIFICATION_PASSED:
            errors.append("verified state: acquisition_status=VERIFIED and verification_status=PASSED must agree")
        if not isinstance(exact_byte_size, int) or isinstance(exact_byte_size, bool) or exact_byte_size <= 0:
            errors.append("verified state: exact_byte_size is required")
        if not isinstance(raw_sha256, str) or SHA256_PATTERN.fullmatch(raw_sha256) is None:
            errors.append("verified state: valid raw_sha256 is required")
        if pbf_header_timestamp is None:
            errors.append("verified state: pbf_header_timestamp is required")
        if complete_planet_verified is not True:
            errors.append("verified state: complete_planet_verified must be true")
        if not isinstance(acquired_at_raw, str) or not acquired_at_raw:
            errors.append("verified state: acquired_at is required")

    fingerprint = record.get("record_fingerprint")
    if not isinstance(fingerprint, str) or SHA256_PATTERN.fullmatch(fingerprint) is None:
        errors.append("record_fingerprint: expected lowercase 64-character SHA-256")
    else:
        expected_fingerprint = record_fingerprint(record)
        if fingerprint != expected_fingerprint:
            errors.append("record_fingerprint: does not match stable verification fields")

    return errors
