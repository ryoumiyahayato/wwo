#!/usr/bin/env python3
"""Validate Batch 3 candidate safety, source identity, inventory digests, and manifests."""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any

from json_schema_validator import validate_json_document


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "data" / "staging" / "1900"
SCHEMA_PATH = STAGING / "batch3_source_gap_candidates.schema.json"
RECORDS_PATH = STAGING / "batch3_source_gap_candidates.json"
INVENTORY_PATH = STAGING / "batch3_repository_inventory.json"
CORPUS_PATH = STAGING / "batch3_deterministic_corpus.json"
MANIFEST_PATH = STAGING / "batch3_manifest.json"
CANDIDATE_SOURCES = {
    "cities": ("data/world_map/cities.json", "cities"),
    "ports": ("data/world_map/ports.json", "ports"),
    "rail_segments": ("data/world_map/rail_segments.json", "segments"),
    "shipping_routes": ("data/world_map/shipping_routes.json", "routes"),
}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def add_error(errors: list[str], message: str) -> None:
    errors.append(message)


def validate() -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    schema = load_json(SCHEMA_PATH)
    payload = load_json(RECORDS_PATH)
    inventory = load_json(INVENTORY_PATH)
    corpus = load_json(CORPUS_PATH)
    manifest = load_json(MANIFEST_PATH)
    errors.extend(
        f"JSON Schema: {message}"
        for message in validate_json_document(payload, schema)
    )

    if schema.get("$id") != "wwo_1900_batch3_source_gap_candidates_v1":
        add_error(errors, "schema $id mismatch")
    if payload.get("schema_id") != "wwo_1900_batch3_source_gap_candidates_v1" or payload.get("batch") != 3:
        add_error(errors, "candidate payload schema or batch mismatch")
    policy = payload.get("policy", {})
    if policy.get("historical_fact") is not False or policy.get("runtime_authority") is not False or policy.get("no_inference") is not True:
        add_error(errors, "candidate policy allows facts, runtime authority, or inference")

    candidates = payload.get("candidates", [])
    candidate_ids = [candidate.get("candidate_id") for candidate in candidates]
    if len(candidate_ids) != len(set(candidate_ids)):
        add_error(errors, "duplicate candidate IDs")
    expected_category_counts = {"cities": 32, "ports": 8, "rail_segments": 9, "shipping_routes": 3}
    actual_category_counts = dict(sorted(Counter(candidate.get("category") for candidate in candidates).items()))
    if actual_category_counts != expected_category_counts:
        add_error(errors, f"candidate category counts mismatch: {actual_category_counts}")
    if len(candidates) != 52:
        add_error(errors, "candidate count is not 52")

    source_payloads: dict[str, tuple[dict[str, Any], str, list[dict[str, Any]]]] = {}
    expected_input_digests: dict[str, str] = {}
    for category, (relative_path, list_key) in CANDIDATE_SOURCES.items():
        path = ROOT / relative_path
        source_payload = load_json(path)
        digest = sha256_file(path)
        expected_input_digests[relative_path] = digest
        source_payloads[category] = (source_payload, digest, source_payload[list_key])
        candidates_for_category = [candidate for candidate in candidates if candidate.get("category") == category]
        if len(candidates_for_category) != len(source_payload[list_key]):
            add_error(errors, f"candidate count differs for {category}")
        for index, source_record in enumerate(source_payload[list_key]):
            source_id = source_record.get("id")
            matches = [candidate for candidate in candidates_for_category if candidate.get("source_record_id") == source_id]
            if len(matches) != 1:
                add_error(errors, f"{category}: expected one candidate for source ID {source_id}")
                continue
            candidate = matches[0]
            for key, expected in {
                "candidate_id": f"{category}:{source_id}",
                "source_path": relative_path,
                "source_record_id": source_id,
                "source_index": index,
                "source_sha256": digest,
                "candidate_status": "UNVERIFIED_FOR_1900",
                "historical_fact": False,
                "runtime_authority": False,
                "source_record": source_record,
            }.items():
                if candidate.get(key) != expected:
                    add_error(errors, f"{category}:{source_id}: field {key} differs from source")
            if not candidate.get("required_evidence"):
                add_error(errors, f"{category}:{source_id}: required_evidence is empty")
            if not candidate.get("notes", "").startswith("Copied from a current repository prototype"):
                add_error(errors, f"{category}:{source_id}: safety note missing")

    inventory_files = inventory.get("files", [])
    inventory_by_path = {item.get("path"): item for item in inventory_files}
    if len(inventory_by_path) != len(inventory_files):
        add_error(errors, "duplicate inventory paths")
    expected_inventory_paths = {
        "data/world_map/cities.json",
        "data/world_map/ports.json",
        "data/world_map/rail_segments.json",
        "data/world_map/shipping_routes.json",
        "data/world_map/countries.json",
        "data/world_map/regions.json",
        "data/world_map/historical/historical_admin1_1900.json",
        "data/alpha/historical_economy_coverage_1900.json",
        "data/alpha/historical_world_economy_1900.json",
        "data/alpha/historical_world_economy_1900/countries_compact.json",
        "data/alpha/historical_transport_network_1900/transport_compact.json",
        "data/alpha/commodity_market_1900.json",
        "data/alpha/economy_integration_1900.json",
    }
    if set(inventory_by_path) != expected_inventory_paths:
        add_error(errors, "inventory paths differ from the declared Batch 3 scope")
    for relative_path, item in inventory_by_path.items():
        path = ROOT / relative_path
        if not path.exists():
            add_error(errors, f"inventory input missing: {relative_path}")
            continue
        if item.get("sha256") != sha256_file(path):
            add_error(errors, f"inventory SHA-256 mismatch: {relative_path}")
        if item.get("source_class") != "canonical_reference" and item.get("promotion_status") != "REVIEW_REQUIRED":
            add_error(errors, f"inventory promotion guard missing: {relative_path}")
        if item.get("prototype_only") is True and item.get("source_class") not in {"current_prototype", "canonical_reference"}:
            add_error(errors, f"prototype classification mismatch: {relative_path}")

    if inventory.get("summary", {}).get("inventory_file_count") != len(expected_inventory_paths):
        add_error(errors, "inventory summary file count mismatch")
    if inventory.get("summary", {}).get("candidate_count") != len(candidates):
        add_error(errors, "inventory summary candidate count mismatch")

    all_input_digests = dict(corpus.get("input_digests", {}))
    for relative_path, digest in expected_input_digests.items():
        if all_input_digests.get(relative_path) != digest:
            add_error(errors, f"corpus candidate input digest mismatch: {relative_path}")
    for relative_path, item in inventory_by_path.items():
        if all_input_digests.get(relative_path) != item.get("sha256"):
            add_error(errors, f"corpus inventory input digest mismatch: {relative_path}")

    records_sha = sha256_file(RECORDS_PATH)
    inventory_sha = sha256_file(INVENTORY_PATH)
    corpus_sha = sha256_file(CORPUS_PATH)
    schema_sha = sha256_file(SCHEMA_PATH)
    if corpus.get("expected_records_sha256") != records_sha:
        add_error(errors, "corpus records SHA-256 mismatch")
    if corpus.get("expected_inventory_sha256") != inventory_sha:
        add_error(errors, "corpus inventory SHA-256 mismatch")
    if corpus.get("expected_schema_sha256") != schema_sha:
        add_error(errors, "corpus schema SHA-256 mismatch")
    if manifest.get("outputs", {}).get("batch3_source_gap_candidates.json", {}).get("sha256") != records_sha:
        add_error(errors, "manifest records SHA-256 mismatch")
    if manifest.get("outputs", {}).get("batch3_repository_inventory.json", {}).get("sha256") != inventory_sha:
        add_error(errors, "manifest inventory SHA-256 mismatch")
    if manifest.get("outputs", {}).get("batch3_deterministic_corpus.json", {}).get("sha256") != corpus_sha:
        add_error(errors, "manifest corpus SHA-256 mismatch")
    if manifest.get("outputs", {}).get("batch3_source_gap_candidates.schema.json", {}).get("sha256") != schema_sha:
        add_error(errors, "manifest schema SHA-256 mismatch")
    if manifest.get("runtime_authority") is not False or manifest.get("protected_scope", {}).get("historical_fact_inferred") is not False:
        add_error(errors, "manifest protected-scope guards are not false")

    output_text = "\n".join(path.read_text(encoding="utf-8") for path in [RECORDS_PATH, INVENTORY_PATH, CORPUS_PATH, MANIFEST_PATH])
    if str(ROOT).replace("\\", "/").lower() in output_text.replace("\\", "/").lower():
        add_error(errors, "generated output contains an absolute repository path")

    metrics = {
        "candidate_count": len(candidates),
        "category_counts": actual_category_counts,
        "inventory_file_count": len(inventory_files),
        "records_sha256": records_sha,
        "inventory_sha256": inventory_sha,
        "corpus_sha256": corpus_sha,
        "manifest_sha256": sha256_file(MANIFEST_PATH),
        "schema_sha256": schema_sha,
    }
    return errors, metrics


def main() -> int:
    errors, metrics = validate()
    print(json.dumps({"ok": not errors, "errors": errors, "metrics": metrics}, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
