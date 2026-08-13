#!/usr/bin/env python3
"""Build the Batch 1 code-resolution crosswalk and deterministic corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "data" / "staging" / "1900"
HISTORICAL_PATH = REPO_ROOT / "data" / "world_map" / "historical_political_entities_1900.json"
COUNTRIES_PATH = REPO_ROOT / "data" / "world_map" / "countries.json"
SCHEMA_PATH = DEFAULT_OUTPUT_DIR / "canonical_crosswalk.schema.json"
SNAPSHOT_DATE = "1900-03-12"
SOURCE_ID = "src-repository-existing-1900"
SOURCE_PATHS = [
    "data/world_map/historical_political_entities_1900.json",
    "data/world_map/countries.json",
]
GENERATOR_VERSION = "batch1_20260812_v2"
OUTPUT_NAME = "canonical_crosswalk.json"
MANIFEST_NAME = "batch1_manifest.json"
CORPUS_NAME = "batch1_deterministic_corpus.json"
CODE_RESOLUTION_OVERRIDES = {
    "ESH": ["country_sah"],
    "PSE": ["country_psx"],
}
AMBIGUOUS_ENTITY_IDS = {
    "austria_hungary",
    "congo_free_state",
    "arabian_polities",
    "somali_territories_1900",
    "south_africa_war_zone",
}


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


def _ordered_unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def build_crosswalk(entities: list[dict[str, Any]], countries: list[dict[str, Any]]) -> dict[str, Any]:
    by_code: dict[str, list[str]] = {}
    for country in countries:
        code = country.get("data_code")
        country_id = country.get("id")
        if isinstance(code, str) and isinstance(country_id, str):
            by_code.setdefault(code, []).append(country_id)

    records: list[dict[str, Any]] = []
    for entity in entities:
        entity_id = entity["id"]
        member_codes = list(entity.get("members", []))
        core_codes = list(entity.get("core_members", []))
        resolved_ids = _ordered_unique(
            country_id
            for code in member_codes
            for country_id in CODE_RESOLUTION_OVERRIDES.get(code, by_code.get(code, []))
        )
        all_members_resolved = bool(member_codes) and all(
            code in by_code or code in CODE_RESOLUTION_OVERRIDES for code in member_codes
        )
        if entity_id in AMBIGUOUS_ENTITY_IDS:
            code_status = "AMBIGUOUS"
            classification_status = "AMBIGUOUS"
            reason = "Existing source classification is fragmented, contested, personal-union, or otherwise unsafe to collapse; current IDs are reference resolutions only."
        elif len(member_codes) == 1 and len(resolved_ids) == 1:
            code_status = "EXACT"
            classification_status = "EXACT_CODE"
            reason = "The single member code resolves to one current catalog ID. This is exact code resolution only; historical identity and successor relation remain unverified."
        elif all_members_resolved and len(resolved_ids) > 1:
            code_status = "MULTI_MATCH"
            classification_status = "LIKELY_COMPOSITE"
            reason = "All member codes resolve to a current catalog ID set. The historical aggregate is not collapsed into one current entity; identity and control remain unverified."
        elif not resolved_ids:
            code_status = "NO_MATCH"
            classification_status = "NO_MATCH"
            reason = "No current catalog ID resolves from the supplied member codes."
        else:
            code_status = "AMBIGUOUS"
            classification_status = "AMBIGUOUS"
            reason = "Current code resolution is incomplete or non-unique, so no historical identity or successor relation is inferred."
        records.append(
            {
                "historical_entity_id": entity_id,
                "member_codes": member_codes,
                "core_member_codes": core_codes,
                "canonical_entity_ids": resolved_ids,
                "code_resolution_status": code_status,
                "resolved_current_id": resolved_ids[0] if code_status == "EXACT" else None,
                "resolved_current_ids": resolved_ids,
                "classification_status": classification_status,
                "historical_identity_status": "UNVERIFIED",
                "historical_identity_evidence": None,
                "successor_relation_status": "UNVERIFIED",
                "successor_evidence": None,
                "automatic_authoritative_candidate": False,
                "mapping_reason": reason,
                "source_id": SOURCE_ID,
                "source_paths": SOURCE_PATHS,
            }
        )

    code_counts = Counter(record["code_resolution_status"] for record in records)
    classification_counts = Counter(record["classification_status"] for record in records)
    identity_counts = Counter(record["historical_identity_status"] for record in records)
    successor_counts = Counter(record["successor_relation_status"] for record in records)
    return {
        "schema_id": "wwo_1900_canonical_crosswalk_v2",
        "snapshot_date": SNAPSHOT_DATE,
        "scope": "All 61 aggregate historical entities in data/world_map/historical_political_entities_1900.json",
        "classification_policy": {
            "code_resolution": "Member codes resolve only to current catalog IDs; no names or normalized names create authority.",
            "historical_identity": "Code resolution is not proof that a 1900 historical entity is the current catalog entity.",
            "successor_relation": "Successor or sovereignty relations require explicit date-scoped entity-specific evidence.",
            "automatic_authority": "False unless an allowed identity/successor evidence object supplies source, fragment, date scope, and target entity.",
        },
        "summary": {
            "code_resolution": {key: code_counts.get(key, 0) for key in ("EXACT", "MULTI_MATCH", "AMBIGUOUS", "NO_MATCH")},
            "classification": {key: classification_counts.get(key, 0) for key in ("EXACT_CODE", "LIKELY_COMPOSITE", "AMBIGUOUS", "NO_MATCH")},
            "historical_identity": dict(sorted(identity_counts.items())),
            "successor_relation": dict(sorted(successor_counts.items())),
            "automatic_authoritative_candidate_count": sum(record["automatic_authoritative_candidate"] for record in records),
        },
        "records": records,
    }


def build(output_dir: Path) -> dict[str, Any]:
    historical = load_json(HISTORICAL_PATH)
    countries = load_json(COUNTRIES_PATH)
    crosswalk = build_crosswalk(historical["entities"], countries["countries"])
    if len(crosswalk["records"]) != 61:
        raise ValueError("historical aggregate entity count changed; refusing to generate a partial crosswalk")
    output_dir.mkdir(parents=True, exist_ok=True)
    crosswalk_sha = write_json(output_dir / OUTPUT_NAME, crosswalk)
    schema_sha = sha256_file(SCHEMA_PATH)
    corpus = {
        "schema_id": "wwo_1900_source_pack_batch1_deterministic_corpus_v2",
        "batch": 1,
        "generator_version": GENERATOR_VERSION,
        "snapshot_date": SNAPSHOT_DATE,
        "input_files": {
            "data/world_map/historical_political_entities_1900.json": sha256_file(HISTORICAL_PATH),
            "data/world_map/countries.json": sha256_file(COUNTRIES_PATH),
        },
        "expected_crosswalk_sha256": crosswalk_sha,
        "expected_schema_sha256": schema_sha,
        "expected_summary": crosswalk["summary"],
        "comparison_outputs": [OUTPUT_NAME, MANIFEST_NAME, CORPUS_NAME],
        "policy": "Generated bytes must be identical across clean output directories; no timestamp or absolute path is permitted.",
    }
    corpus_sha = write_json(output_dir / CORPUS_NAME, corpus)
    manifest = {
        "schema_id": "wwo_1900_source_pack_batch1_manifest_v2",
        "batch": 1,
        "snapshot_date": SNAPSHOT_DATE,
        "generator_version": GENERATOR_VERSION,
        "runtime_authority": False,
        "input_files": corpus["input_files"],
        "outputs": {
            OUTPUT_NAME: {"path": f"data/staging/1900/{OUTPUT_NAME}", "sha256": crosswalk_sha, "records": len(crosswalk["records"])},
            "canonical_crosswalk.schema.json": {"path": "data/staging/1900/canonical_crosswalk.schema.json", "sha256": schema_sha},
            CORPUS_NAME: {"path": f"data/staging/1900/{CORPUS_NAME}", "sha256": corpus_sha},
        },
        "summary": crosswalk["summary"],
        "protected_scope": {
            "authoritative_runtime_data_changed": False,
            "historical_identity_inferred": False,
            "successor_relation_inferred": False,
            "automatic_authority_candidates": 0,
        },
    }
    manifest_sha = write_json(output_dir / MANIFEST_NAME, manifest)
    return {"crosswalk_sha256": crosswalk_sha, "schema_sha256": schema_sha, "corpus_sha256": corpus_sha, "manifest_sha256": manifest_sha, "summary": crosswalk["summary"]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    result = build(parser.parse_args().output_dir.resolve())
    print(json.dumps({"ok": True, **result}, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
