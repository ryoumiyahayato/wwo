#!/usr/bin/env python3
"""Build Batch 4 admin1/economy coverage review queues without adding facts."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = ROOT / "data" / "staging" / "1900"
SCHEMA_PATH = ROOT / "data" / "staging" / "1900" / "batch4_coverage_review_queue.schema.json"
ADMIN1_PATH = ROOT / "data" / "world_map" / "historical" / "historical_admin1_1900.json"
ECONOMY_PATH = ROOT / "data" / "alpha" / "historical_economy_coverage_1900.json"
SNAPSHOT_DATE = "1900-03-12"
GENERATOR_VERSION = "batch4_20260812_v1"
QUEUE_NAME = "batch4_coverage_review_queue.json"
CORPUS_NAME = "batch4_deterministic_corpus.json"
MANIFEST_NAME = "batch4_manifest.json"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: Any) -> str:
    encoded = (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    path.write_bytes(encoded)
    return hashlib.sha256(encoded).hexdigest()


def build(output_dir: Path) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    admin1 = load_json(ADMIN1_PATH)
    economy = load_json(ECONOMY_PATH)
    admin1_sha = sha256_file(ADMIN1_PATH)
    economy_sha = sha256_file(ECONOMY_PATH)

    admin1_queue = []
    for index, record in enumerate(admin1["countries"]):
        entity_id = record["entity_id"]
        admin1_queue.append(
            {
                "queue_id": f"admin1:{entity_id}",
                "queue_type": "admin1_coverage_review",
                "source_path": "data/world_map/historical/historical_admin1_1900.json",
                "source_record_id": entity_id,
                "source_index": index,
                "source_sha256": admin1_sha,
                "candidate_status": "REVIEW_REQUIRED",
                "historical_fact": False,
                "runtime_authority": False,
                "required_evidence": ["dated_admin1_source_locator", "historical_unit_name_crosswalk", "boundary_or_geometry_evidence", "administrative_level_definition"],
                "source_record": record,
                "notes": "Copied from existing admin1 coverage; names and unit lists are a review input, not a promoted historical geometry or runtime fact.",
            }
        )

    economy_queue = []
    for index, record in enumerate(economy["countries"]):
        entity_id = record["entity_id"]
        for dimension in record["missing_dimensions"]:
            economy_queue.append(
                {
                    "queue_id": f"economy:{entity_id}:{dimension}",
                    "queue_type": "economy_dimension_review",
                    "source_path": "data/alpha/historical_economy_coverage_1900.json",
                    "source_record_id": entity_id,
                    "source_index": index,
                    "source_sha256": economy_sha,
                    "entity_id": entity_id,
                    "dimension": dimension,
                    "source_status": record["status"],
                    "candidate_status": "REVIEW_REQUIRED",
                    "historical_fact": False,
                    "runtime_authority": False,
                    "required_evidence": ["dated_primary_or_secondary_source_locator", "entity_crosswalk", "dimension_definition", "unit_and_reference_date", "bounds_or_uncertainty_method"],
                    "source_record": record,
                    "notes": "Generated from an existing missing-dimension declaration; no numeric value, estimate, coefficient, or runtime eligibility is created.",
                }
            )

    admin1_queue.sort(key=lambda item: item["queue_id"])
    economy_queue.sort(key=lambda item: item["queue_id"])
    summary = {
        "admin1_items": len(admin1_queue),
        "economy_items": len(economy_queue),
        "total_items": len(admin1_queue) + len(economy_queue),
        "admin1_unit_names": sum(len(record["units"]) for record in admin1["countries"]),
        "economy_dimensions": len(economy["dimensions"]),
        "source_file_counts": {
            "data/world_map/historical/historical_admin1_1900.json": len(admin1["countries"]),
            "data/alpha/historical_economy_coverage_1900.json": len(economy["countries"]),
        },
    }
    queue_payload = {
        "schema_id": "wwo_1900_batch4_coverage_review_queue_v1",
        "batch": 4,
        "snapshot_date": SNAPSHOT_DATE,
        "policy": {
            "historical_fact": False,
            "runtime_authority": False,
            "numeric_values": "none_added",
            "source_requirement": "Each queue item requires a dated source locator and explicit historical crosswalk before promotion.",
            "no_inference": True,
        },
        "summary": summary,
        "admin1_queue": admin1_queue,
        "economy_queue": economy_queue,
    }
    queue_path = output_dir / QUEUE_NAME
    queue_sha = write_json(queue_path, queue_payload)
    schema_sha = sha256_file(SCHEMA_PATH)
    corpus_payload = {
        "schema_id": "wwo_1900_source_pack_batch4_deterministic_corpus_v1",
        "batch": 4,
        "generator_version": GENERATOR_VERSION,
        "snapshot_date": SNAPSHOT_DATE,
        "input_digests": {"data/world_map/historical/historical_admin1_1900.json": admin1_sha, "data/alpha/historical_economy_coverage_1900.json": economy_sha},
        "expected_queue_sha256": queue_sha,
        "expected_schema_sha256": schema_sha,
        "expected_summary": summary,
        "policy": "Generated bytes must match across clean output directories; no timestamp or absolute path is permitted.",
    }
    corpus_path = output_dir / CORPUS_NAME
    corpus_sha = write_json(corpus_path, corpus_payload)
    manifest_payload = {
        "schema_id": "wwo_1900_source_pack_batch4_manifest_v1",
        "batch": 4,
        "snapshot_date": SNAPSHOT_DATE,
        "generator_version": GENERATOR_VERSION,
        "runtime_authority": False,
        "input_files": {"data/world_map/historical/historical_admin1_1900.json": admin1_sha, "data/alpha/historical_economy_coverage_1900.json": economy_sha},
        "outputs": {
            QUEUE_NAME: {"path": f"data/staging/1900/{QUEUE_NAME}", "sha256": queue_sha, "items": summary["total_items"]},
            "batch4_coverage_review_queue.schema.json": {"path": "data/staging/1900/batch4_coverage_review_queue.schema.json", "sha256": schema_sha},
            CORPUS_NAME: {"path": f"data/staging/1900/{CORPUS_NAME}", "sha256": corpus_sha},
        },
        "summary": summary,
        "protected_scope": {"authoritative_runtime_data_changed": False, "vnext_core_changed": False, "gameplay_balance_changed": False, "historical_fact_inferred": False, "numeric_values_added": False},
    }
    manifest_sha = write_json(output_dir / MANIFEST_NAME, manifest_payload)
    return {"ok": True, "queue_sha256": queue_sha, "corpus_sha256": corpus_sha, "manifest_sha256": manifest_sha, "schema_sha256": schema_sha, "summary": summary}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    result = build(parser.parse_args().output_dir.resolve())
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
