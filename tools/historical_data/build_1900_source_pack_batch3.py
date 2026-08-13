#!/usr/bin/env python3
"""Build Batch 3 source-gap candidates and repository digest inventory."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = ROOT / "data" / "staging" / "1900"
SCHEMA_PATH = ROOT / "data" / "staging" / "1900" / "batch3_source_gap_candidates.schema.json"
SNAPSHOT_DATE = "1900-03-12"
GENERATOR_VERSION = "batch3_20260812_v1"
RECORDS_NAME = "batch3_source_gap_candidates.json"
INVENTORY_NAME = "batch3_repository_inventory.json"
CORPUS_NAME = "batch3_deterministic_corpus.json"
MANIFEST_NAME = "batch3_manifest.json"

CANDIDATE_SOURCES = [
    {
        "category": "cities",
        "path": "data/world_map/cities.json",
        "list_key": "cities",
        "required_evidence": ["historical_identity_and_date", "source_locator", "historical_parent_crosswalk", "historical_role_or_population"],
    },
    {
        "category": "ports",
        "path": "data/world_map/ports.json",
        "list_key": "ports",
        "required_evidence": ["historical_port_identity_and_date", "source_locator", "historical_owner_crosswalk", "historical_city_crosswalk"],
    },
    {
        "category": "rail_segments",
        "path": "data/world_map/rail_segments.json",
        "list_key": "segments",
        "required_evidence": ["historical_line_existence_and_date", "source_locator", "historical_endpoint_crosswalk", "operator_or_ownership_evidence"],
    },
    {
        "category": "shipping_routes",
        "path": "data/world_map/shipping_routes.json",
        "list_key": "routes",
        "required_evidence": ["historical_route_existence_and_date", "source_locator", "historical_port_crosswalk", "route_semantics_evidence"],
    },
]

INVENTORY_SOURCES = [
    ("data/world_map/cities.json", "current_prototype", "Current city records; not historical facts."),
    ("data/world_map/ports.json", "current_prototype", "Current port records; not historical facts."),
    ("data/world_map/rail_segments.json", "current_prototype", "Current rail prototype; not historical facts."),
    ("data/world_map/shipping_routes.json", "current_prototype", "Current shipping prototype; not historical facts."),
    ("data/world_map/countries.json", "canonical_reference", "Current canonical IDs used only for reference and crosswalk gaps."),
    ("data/world_map/regions.json", "canonical_reference", "Current region IDs used only for reference and crosswalk gaps."),
    ("data/world_map/historical/historical_admin1_1900.json", "historical_input", "Existing dated admin1 coverage; promotion remains separate."),
    ("data/alpha/historical_economy_coverage_1900.json", "historical_input", "Existing historical economy coverage policy and gaps."),
    ("data/alpha/historical_world_economy_1900.json", "estimated_historical_fixture", "Existing bounded estimates; no new numeric facts added."),
    ("data/alpha/historical_world_economy_1900/countries_compact.json", "estimated_historical_fixture", "Existing compact estimated economy rows; no new numeric facts added."),
    ("data/alpha/historical_transport_network_1900/transport_compact.json", "estimated_historical_fixture", "Existing compact estimated transport rows; no new route facts added."),
    ("data/alpha/commodity_market_1900.json", "historical_fixture", "Existing commodity fixture; outside this source-gap candidate batch."),
    ("data/alpha/economy_integration_1900.json", "historical_fixture", "Existing economy integration fixture; outside this source-gap candidate batch."),
]


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def write_json(path: Path, value: Any) -> str:
    encoded = (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    path.write_bytes(encoded)
    return sha256_bytes(encoded)


def list_counts(value: dict[str, Any]) -> dict[str, int]:
    return {key: len(item) for key, item in value.items() if isinstance(item, list)}


def build(output_dir: Path) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    candidates: list[dict[str, Any]] = []
    source_file_counts: Counter[str] = Counter()
    candidate_input_digests: dict[str, str] = {}

    for config in CANDIDATE_SOURCES:
        path = ROOT / config["path"]
        payload = load_json(path)
        source_bytes = path.read_bytes()
        source_sha = sha256_bytes(source_bytes)
        records = payload[config["list_key"]]
        candidate_input_digests[config["path"]] = source_sha
        source_file_counts[config["path"]] = len(records)
        for index, record in enumerate(records):
            record_id = record["id"]
            candidates.append(
                {
                    "candidate_id": f"{config['category']}:{record_id}",
                    "category": config["category"],
                    "source_path": config["path"],
                    "source_record_id": record_id,
                    "source_index": index,
                    "source_sha256": source_sha,
                    "candidate_status": "UNVERIFIED_FOR_1900",
                    "historical_fact": False,
                    "runtime_authority": False,
                    "required_evidence": config["required_evidence"],
                    "source_record": record,
                    "notes": "Copied from a current repository prototype; this candidate is not a 1900 historical fact and is not eligible for runtime promotion without the required evidence.",
                }
            )

    candidates.sort(key=lambda item: item["candidate_id"])
    inventory: list[dict[str, Any]] = []
    inventory_digests: dict[str, str] = {}
    for path_text, source_class, purpose in INVENTORY_SOURCES:
        path = ROOT / path_text
        payload = load_json(path)
        raw = path.read_bytes()
        digest = sha256_bytes(raw)
        inventory_digests[path_text] = digest
        inventory.append(
            {
                "path": path_text,
                "sha256": digest,
                "schema_id": payload.get("schema_id"),
                "schema_version": payload.get("schema_version"),
                "prototype_only": payload.get("prototype_only"),
                "source_class": source_class,
                "promotion_status": "REVIEW_REQUIRED" if source_class != "canonical_reference" else "REFERENCE_ONLY",
                "purpose": purpose,
                "top_level_list_counts": list_counts(payload),
                "top_level_keys": sorted(payload.keys()),
            }
        )
    inventory.sort(key=lambda item: item["path"])

    category_counts = dict(sorted(Counter(candidate["category"] for candidate in candidates).items()))
    records_payload = {
        "schema_id": "wwo_1900_batch3_source_gap_candidates_v1",
        "batch": 3,
        "snapshot_date": SNAPSHOT_DATE,
        "policy": {
            "historical_fact": False,
            "runtime_authority": False,
            "source_requirement": "Every candidate requires an external or repository source locator and a dated historical crosswalk before promotion.",
            "no_inference": True,
        },
        "summary": {
            "candidate_count": len(candidates),
            "category_counts": category_counts,
            "source_file_counts": dict(sorted(source_file_counts.items())),
        },
        "candidates": candidates,
    }
    inventory_payload = {
        "schema_id": "wwo_1900_batch3_repository_inventory_v1",
        "batch": 3,
        "snapshot_date": SNAPSHOT_DATE,
        "policy": {
            "runtime_authority": False,
            "prototype_records_are_not_historical_facts": True,
            "estimated_fixtures_are_not_promoted": True,
            "inventory_is_digest_only": True,
        },
        "summary": {
            "inventory_file_count": len(inventory),
            "candidate_source_file_count": len(CANDIDATE_SOURCES),
            "candidate_count": len(candidates),
        },
        "files": inventory,
    }
    records_path = output_dir / RECORDS_NAME
    inventory_path = output_dir / INVENTORY_NAME
    records_sha = write_json(records_path, records_payload)
    inventory_sha = write_json(inventory_path, inventory_payload)
    schema_sha = sha256_file(SCHEMA_PATH)

    corpus_payload = {
        "schema_id": "wwo_1900_source_pack_batch3_deterministic_corpus_v1",
        "batch": 3,
        "generator_version": GENERATOR_VERSION,
        "snapshot_date": SNAPSHOT_DATE,
        "input_digests": dict(sorted({**candidate_input_digests, **inventory_digests}.items())),
        "expected_records_sha256": records_sha,
        "expected_inventory_sha256": inventory_sha,
        "expected_schema_sha256": schema_sha,
        "expected_candidate_count": len(candidates),
        "expected_inventory_file_count": len(inventory),
        "comparison_outputs": [RECORDS_NAME, INVENTORY_NAME, MANIFEST_NAME, CORPUS_NAME],
        "policy": "Generated bytes must be identical across clean output directories; no timestamp or absolute path is permitted.",
    }
    corpus_path = output_dir / CORPUS_NAME
    corpus_sha = write_json(corpus_path, corpus_payload)
    manifest_payload = {
        "schema_id": "wwo_1900_source_pack_batch3_manifest_v1",
        "batch": 3,
        "snapshot_date": SNAPSHOT_DATE,
        "generator_version": GENERATOR_VERSION,
        "runtime_authority": False,
        "input_files": dict(sorted({**candidate_input_digests, **inventory_digests}.items())),
        "outputs": {
            RECORDS_NAME: {"path": f"data/staging/1900/{RECORDS_NAME}", "sha256": records_sha, "candidates": len(candidates)},
            INVENTORY_NAME: {"path": f"data/staging/1900/{INVENTORY_NAME}", "sha256": inventory_sha, "files": len(inventory)},
            "batch3_source_gap_candidates.schema.json": {"path": "data/staging/1900/batch3_source_gap_candidates.schema.json", "sha256": schema_sha},
            CORPUS_NAME: {"path": f"data/staging/1900/{CORPUS_NAME}", "sha256": corpus_sha},
        },
        "summary": {
            "candidate_count": len(candidates),
            "category_counts": category_counts,
            "inventory_file_count": len(inventory),
        },
        "protected_scope": {
            "authoritative_runtime_data_changed": False,
            "vnext_core_changed": False,
            "gameplay_balance_changed": False,
            "historical_fact_inferred": False,
        },
    }
    manifest_path = output_dir / MANIFEST_NAME
    manifest_sha = write_json(manifest_path, manifest_payload)
    return {
        "records_sha256": records_sha,
        "inventory_sha256": inventory_sha,
        "corpus_sha256": corpus_sha,
        "manifest_sha256": manifest_sha,
        "candidate_count": len(candidates),
        "inventory_file_count": len(inventory),
        "category_counts": category_counts,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    args = parser.parse_args()
    result = build(args.output_dir.resolve())
    print(json.dumps({"ok": True, **result}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
