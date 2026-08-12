#!/usr/bin/env python3
"""Validate the deterministic Batch 3 provenance regression corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools.provenance import generate_regression_corpus  # noqa: E402


REQUIRED_RECORD_FIELDS = {
    "path",
    "file_type",
    "size_bytes",
    "sha256",
    "category",
    "kind",
    "known_source",
    "license",
    "derived_from",
    "generator",
    "issues",
}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_corpus(corpus: dict[str, Any], root: Path) -> dict[str, Any]:
    findings: list[dict[str, str]] = []

    def error(code: str, path: str, message: str) -> None:
        findings.append({"severity": "ERROR", "code": code, "path": path, "message": message})

    def warning(code: str, path: str, message: str) -> None:
        findings.append({"severity": "WARNING", "code": code, "path": path, "message": message})

    if corpus.get("schema_version") != 1:
        error("CORPUS_SCHEMA", "", "schema_version must be 1")
    if corpus.get("corpus_kind") != generate_regression_corpus.CORPUS_KIND:
        error("CORPUS_SCHEMA", "", "corpus_kind is not recognized")
    if corpus.get("audit_batch") != "BATCH_3":
        error("CORPUS_SCHEMA", "", "audit_batch must be BATCH_3")
    manifest_path = root / generate_regression_corpus.MANIFEST_RELATIVE
    if corpus.get("source_manifest") != generate_regression_corpus.MANIFEST_RELATIVE:
        error("CORPUS_SCHEMA", "source_manifest", "source_manifest must point to the Batch 1 manifest")
    if not manifest_path.is_file():
        error("SOURCE_MISSING", str(manifest_path), "source manifest is missing")
        return {"valid": False, "errors": len(findings), "warnings": 0, "findings": findings}
    current_manifest_hash = file_sha256(manifest_path)
    if corpus.get("source_manifest_sha256") != current_manifest_hash:
        error("HASH_MISMATCH", "source_manifest", "corpus source manifest hash differs from filesystem")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        error("MANIFEST_SYNTAX", str(manifest_path), str(exc))
        return {"valid": False, "errors": len(findings), "warnings": 0, "findings": findings}

    entries = manifest.get("entries", [])
    records = corpus.get("records")
    if not isinstance(records, list):
        error("CORPUS_SYNTAX", "records", "records must be a list")
        records = []
    paths = [record.get("path") for record in records if isinstance(record, dict)]
    if paths != sorted(paths):
        error("CORPUS_ORDER", "records", "records must be sorted by path")
    if len(paths) != len(set(paths)):
        error("DUPLICATE_PATH", "records", "record paths must be unique")
    if len(records) != len(entries):
        error("RECORD_COUNT_MISMATCH", "records", "corpus record count differs from manifest")
    manifest_by_path = {
        entry.get("path"): entry
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }
    for index, record in enumerate(records):
        label = f"records[{index}]"
        if not isinstance(record, dict):
            error("CORPUS_SYNTAX", label, "record must be an object")
            continue
        missing = sorted(REQUIRED_RECORD_FIELDS - set(record))
        if missing:
            error("MISSING_REQUIRED_FIELD", label, ", ".join(missing))
            continue
        path = record["path"]
        entry = manifest_by_path.get(path)
        if entry is None:
            error("BROKEN_RECORD", str(path), "corpus record is absent from manifest")
            continue
        for field in REQUIRED_RECORD_FIELDS - {"issues", "derived_from", "generator"}:
            if record[field] != entry[field]:
                error("RECORD_MISMATCH", str(path), f"field {field} differs from manifest")
        for field in ("issues", "derived_from", "generator"):
            if sorted(record[field]) != sorted(entry.get(field, [])):
                error("RECORD_MISMATCH", str(path), f"field {field} differs from manifest")
        if record["license"] in {"LICENSE_UNKNOWN", "MIXED_EXPLICIT_AND_UNKNOWN"}:
            warning("LICENSE_UNKNOWN", str(path), "corpus preserves an unknown license warning")

    expected_summary = {
        field: manifest.get("summary", {}).get(field)
        for field in generate_regression_corpus.SUMMARY_FIELDS
    }
    if corpus.get("source_manifest_summary") != expected_summary:
        error("SUMMARY_MISMATCH", "source_manifest_summary", "corpus summary differs from manifest")
    expected_sources = sorted(
        source["id"]
        for source in manifest.get("external_sources", [])
        if isinstance(source, dict) and isinstance(source.get("id"), str)
    )
    if corpus.get("external_source_ids") != expected_sources:
        error("SOURCE_ID_MISMATCH", "external_source_ids", "external source ids differ from manifest")
    errors = sum(item["severity"] == "ERROR" for item in findings)
    warnings = sum(item["severity"] == "WARNING" for item in findings)
    return {"valid": errors == 0, "errors": errors, "warnings": warnings, "findings": findings}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    path = args.corpus if args.corpus.is_absolute() else root / args.corpus
    try:
        corpus = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(json.dumps({"valid": False, "errors": 1, "warnings": 0, "findings": [{"severity": "ERROR", "code": "CORPUS_SYNTAX", "path": str(path), "message": str(exc)}]}, ensure_ascii=False))
        return 1
    result = validate_corpus(corpus, root)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
