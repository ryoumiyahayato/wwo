#!/usr/bin/env python3
"""Focused tests for pinned territory-source acquisition evidence."""

from __future__ import annotations

import copy
import importlib.util
import sys
import unittest
from pathlib import Path
from types import ModuleType


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
TOOL_PATH = REPOSITORY_ROOT / "tools" / "world_data" / "territory_source_acquisition.py"
RECORD_PATH = (
    REPOSITORY_ROOT
    / "data"
    / "source_acquisition"
    / "territory"
    / "openhistoricalmap_planet_2026_09_08_0001.json"
)


def load_tool() -> ModuleType:
    spec = importlib.util.spec_from_file_location("wwo_territory_source_acquisition", TOOL_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load acquisition tool: {TOOL_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


acquisition = load_tool()


class TerritorySourceAcquisitionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.record = acquisition.load_acquisition_record(RECORD_PATH)

    def _refresh_fingerprint(self, record: dict) -> None:
        record["record_fingerprint"] = acquisition.record_fingerprint(record)

    def test_initial_pinned_record_is_valid_and_pending(self) -> None:
        self.assertEqual(acquisition.validate_record(self.record), [])
        self.assertEqual(
            self.record["source_snapshot_id"],
            "territory_source:openhistoricalmap_planet_2026_09_08_0001",
        )
        self.assertEqual(self.record["acquisition_status"], "PINNED_AWAITING_BYTES")
        self.assertEqual(self.record["verification_status"], "PENDING")
        self.assertEqual(self.record["raw_sha256"], "")
        self.assertIsNone(self.record["exact_byte_size"])
        self.assertEqual(self.record["pbf_header_timestamp"], "")
        self.assertIsNone(self.record["complete_planet_verified"])

    def test_required_source_identity_fields_are_enforced(self) -> None:
        for field in ("source_snapshot_id", "provider", "object_filename", "object_url", "snapshot_timestamp"):
            with self.subTest(field=field):
                malformed = copy.deepcopy(self.record)
                malformed.pop(field)
                errors = acquisition.validate_record(malformed)
                self.assertTrue(any(error.startswith(f"{field}:") for error in errors), errors)

    def test_malformed_sha256_is_rejected(self) -> None:
        malformed = copy.deepcopy(self.record)
        malformed["raw_sha256"] = "abc123"
        self._refresh_fingerprint(malformed)
        errors = acquisition.validate_record(malformed)
        self.assertIn("raw_sha256: expected lowercase 64-character SHA-256", errors)

    def test_inconsistent_timestamps_are_rejected(self) -> None:
        malformed = copy.deepcopy(self.record)
        malformed["snapshot_timestamp"] = "2026-09-09T00:01:00Z"
        self._refresh_fingerprint(malformed)
        errors = acquisition.validate_record(malformed)
        self.assertIn(
            "snapshot_timestamp: does not match timestamp encoded in object_filename",
            errors,
        )

        header_mismatch = copy.deepcopy(self.record)
        header_mismatch["pbf_header_timestamp"] = "2026-09-09T00:01:00Z"
        self._refresh_fingerprint(header_mismatch)
        errors = acquisition.validate_record(header_mismatch)
        self.assertTrue(any(error.startswith("pbf_header_timestamp: must not be later") for error in errors), errors)

    def test_verified_state_requires_byte_evidence(self) -> None:
        malformed = copy.deepcopy(self.record)
        malformed["acquisition_status"] = "VERIFIED"
        malformed["verification_status"] = "PASSED"
        self._refresh_fingerprint(malformed)
        errors = acquisition.validate_record(malformed)
        self.assertIn("verified state: exact_byte_size is required", errors)
        self.assertIn("verified state: valid raw_sha256 is required", errors)
        self.assertIn("verified state: pbf_header_timestamp is required", errors)
        self.assertIn("verified state: complete_planet_verified must be true", errors)
        self.assertIn("verified state: acquired_at is required", errors)

        verified = copy.deepcopy(self.record)
        verified.update(
            {
                "exact_byte_size": 1234567890,
                "raw_sha256": "1" * 64,
                "pbf_header_timestamp": "2026-09-08T00:00:00Z",
                "complete_planet_verified": True,
                "acquisition_status": "VERIFIED",
                "verification_status": "PASSED",
                "acquired_at": "2026-09-24T09:30:00Z",
            }
        )
        self._refresh_fingerprint(verified)
        self.assertEqual(acquisition.validate_record(verified), [])

    def test_record_fingerprint_is_deterministic_and_excludes_acquisition_clock(self) -> None:
        fingerprint = acquisition.record_fingerprint(self.record)
        self.assertEqual(fingerprint, self.record["record_fingerprint"])
        reversed_record = dict(reversed(list(self.record.items())))
        self.assertEqual(acquisition.record_fingerprint(reversed_record), fingerprint)

        clock_changed = copy.deepcopy(self.record)
        clock_changed["acquired_at"] = "2026-09-24T09:30:00Z"
        self.assertEqual(acquisition.record_fingerprint(clock_changed), fingerprint)

        evidence_changed = copy.deepcopy(self.record)
        evidence_changed["exact_byte_size"] = 1
        self.assertNotEqual(acquisition.record_fingerprint(evidence_changed), fingerprint)

    def test_loader_returns_detached_records(self) -> None:
        first = acquisition.load_acquisition_record(RECORD_PATH)
        second = acquisition.load_acquisition_record(RECORD_PATH)
        first["provider"] = "MUTATED"
        self.assertEqual(second["provider"], "OpenHistoricalMap")
        self.assertEqual(
            acquisition.load_acquisition_record(RECORD_PATH)["provider"],
            "OpenHistoricalMap",
        )


if __name__ == "__main__":
    unittest.main()
