#!/usr/bin/env python3
"""Generate a compact deterministic regression corpus from the Batch 1 manifest.

The corpus lives outside the Batch 1 ``data/**``/``assets/**``/``docs/**``
scope, so it can pin the manifest hash without creating a self-referential
manifest.  It records evidence already present in the manifest; it does not
invent sources, licenses, or historical facts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
CORPUS_KIND = "wwo_provenance_regression_corpus"
MANIFEST_RELATIVE = "docs/data_sources/provenance_manifest.json"
DEFAULT_OUTPUT = "tests/provenance/provenance_regression_corpus.json"
SUMMARY_FIELDS = (
    "files_inventoried",
    "source_known",
    "source_unknown",
    "license_known",
    "license_unknown",
    "generated_assets",
    "broken_provenance_chains",
    "duplicate_hash_groups",
)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def build_corpus(root: Path, base_revision: str, manifest_path: Path | None = None) -> dict[str, Any]:
    manifest_path = manifest_path or root / MANIFEST_RELATIVE
    manifest = load_manifest(manifest_path)
    entries = manifest.get("entries", [])
    records = []
    for entry in entries:
        records.append(
            {
                "path": entry["path"],
                "file_type": entry["file_type"],
                "size_bytes": entry["size_bytes"],
                "sha256": entry["sha256"],
                "category": entry["category"],
                "kind": entry["kind"],
                "known_source": entry["known_source"],
                "license": entry["license"],
                "derived_from": sorted(entry["derived_from"]),
                "generator": sorted(entry["generator"]),
                "issues": sorted(entry.get("issues", [])),
            }
        )
    records.sort(key=lambda record: record["path"])
    external_source_ids = sorted(
        source["id"]
        for source in manifest.get("external_sources", [])
        if isinstance(source, dict) and isinstance(source.get("id"), str)
    )
    graph_edges = []
    graph = manifest.get("dependency_graph", {})
    for edge in graph.get("edges", []) if isinstance(graph, dict) else []:
        if not isinstance(edge, dict):
            continue
        graph_edges.append(
            {
                "source": edge.get("source"),
                "generator": sorted(edge.get("generator", [])),
                "output": edge.get("output"),
            }
        )
    graph_edges.sort(key=lambda edge: (edge["output"], edge["source"], edge["generator"]))
    summary = {
        field: manifest.get("summary", {}).get(field)
        for field in SUMMARY_FIELDS
    }
    return {
        "schema_version": SCHEMA_VERSION,
        "corpus_kind": CORPUS_KIND,
        "audit_batch": "BATCH_3",
        "audit_base_revision": base_revision,
        "source_manifest": MANIFEST_RELATIVE,
        "source_manifest_sha256": file_sha256(manifest_path),
        "source_manifest_summary": summary,
        "external_source_ids": external_source_ids,
        "dependency_graph_edges": graph_edges,
        "records": records,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--manifest", type=Path, default=Path(MANIFEST_RELATIVE))
    parser.add_argument("--output", type=Path, default=Path(DEFAULT_OUTPUT))
    parser.add_argument("--base-revision", default="HEAD")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    manifest_path = args.manifest if args.manifest.is_absolute() else root / args.manifest
    output = args.output if args.output.is_absolute() else root / args.output
    corpus = build_corpus(root, args.base_revision, manifest_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(corpus, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"records": len(corpus["records"]), "manifest_sha256": corpus["source_manifest_sha256"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
