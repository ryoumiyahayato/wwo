#!/usr/bin/env python3
"""Generate a ranked, mechanically safe provenance review backlog.

Every item is derived from existing manifest/matrix evidence.  The output is a
review queue, not an instruction to alter data, license text, or gameplay.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


DEFAULT_OUTPUT = "tests/provenance/provenance_review_backlog.json"
MANIFEST_RELATIVE = "docs/data_sources/provenance_manifest.json"
MATRIX_RELATIVE = "docs/data_sources/provenance_reference_matrix.json"
DYNAMIC_OUTPUT_UNRESOLVED = "DYNAMIC_OUTPUT_UNRESOLVED"

SEVERITY = {
    "SOURCE_MISSING": 100,
    "GENERATOR_UNKNOWN": 95,
    "BROKEN_REFERENCE": 90,
    "SOURCE_UNKNOWN": 80,
    "LICENSE_UNKNOWN": 70,
    "SOURCE_LOCATOR_MISSING": 65,
    "PROVENANCE_INCOMPLETE": 60,
    "OBSOLETE_OR_LEGACY_CANDIDATE": 55,
    "CANDIDATE_NOT_CANONICAL": 45,
    DYNAMIC_OUTPUT_UNRESOLVED: 40,
    "INTENTIONAL_TEST_FIXTURE": 5,
}
CATEGORY_BONUS = {
    "map_geometry_cache": 20,
    "map_or_geometry_data": 15,
    "historical_geometry": 15,
    "historical_data": 12,
    "historical_economy_or_transport": 12,
    "historical_flag_image": 8,
    "game_data": 8,
}


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def add_item(items: dict[str, dict[str, Any]], item: dict[str, Any]) -> None:
    key = item["key"]
    if key not in items:
        items[key] = item
        return
    existing = items[key]
    existing["evidence"] = sorted(set(existing["evidence"] + item["evidence"]))
    existing["issues"] = sorted(set(existing["issues"] + item["issues"]))
    existing["priority"] = max(existing["priority"], item["priority"])


def item_priority(issues: list[str], category: str = "", *, source_missing: bool = False) -> int:
    score = max((SEVERITY.get(issue, 0) for issue in issues), default=0)
    score += CATEGORY_BONUS.get(category, 0)
    if source_missing:
        score += 10
    return score


def build_backlog(root: Path, base_revision: str) -> dict[str, Any]:
    manifest = load_json(root / MANIFEST_RELATIVE)
    matrix = load_json(root / MATRIX_RELATIVE)
    items: dict[str, dict[str, Any]] = {}
    for entry in manifest.get("entries", []):
        if not isinstance(entry, dict):
            continue
        issues = sorted(entry.get("issues", []))
        actionable = [issue for issue in issues if issue not in {"LICENSE_UNKNOWN", "PROVENANCE_INCOMPLETE"}]
        if not actionable and not issues:
            continue
        category = str(entry.get("category", ""))
        key = f"file:{entry['path']}"
        add_item(
            items,
            {
                "key": key,
                "target_type": "file",
                "path": entry["path"],
                "priority": item_priority(issues, category),
                "issues": issues,
                "category": category,
                "action": "Review explicit repository evidence and document only confirmed source/license/generator facts.",
                "safety": "Do not infer a license, modify authoritative data, or regenerate a formal asset.",
                "evidence": sorted(entry.get("evidence", [])),
                "review_status": entry.get("review_status", "REVIEW_REQUIRED"),
            },
        )
    for unresolved in matrix.get("unresolved", []):
        if not isinstance(unresolved, dict):
            continue
        issue = str(unresolved.get("type", ""))
        if issue == "INTENTIONAL_TEST_FIXTURE":
            continue
        owner = unresolved.get("owner", unresolved.get("generator", ""))
        target = unresolved.get("target", unresolved.get("output", ""))
        key = f"matrix:{issue}:{owner}:{target}"
        action = (
            "Resolve only from an explicit constant/path expression or repository evidence; otherwise retain the dynamic output as unresolved."
            if issue == DYNAMIC_OUTPUT_UNRESOLVED
            else "Verify the reference against repository history or an explicit generator record; otherwise retain the sentinel and mark unresolved."
        )
        add_item(
            items,
            {
                "key": key,
                "target_type": "reference",
                "path": target,
                "owner": owner,
                "priority": item_priority([issue]),
                "issues": [issue],
                "category": "repository_reference",
                "action": action,
                "safety": "Review-only candidate. Do not create a replacement file or alter gameplay references automatically.",
                "evidence": sorted(unresolved.get("evidence", [])),
                "review_status": "REVIEW_REQUIRED",
            },
        )
    for edge in matrix.get("candidate_edges", []):
        if not isinstance(edge, dict):
            continue
        if edge.get("canonical_graph_match") is True and edge.get("issues") == ["CANDIDATE_NOT_CANONICAL"]:
            continue
        issues = sorted(edge.get("issues", []))
        key = f"edge:{edge.get('source')}:{edge.get('output')}:{','.join(edge.get('generator', []))}"
        add_item(
            items,
            {
                "key": key,
                "target_type": "dependency_edge",
                "path": edge.get("output"),
                "owner": edge.get("generator"),
                "priority": item_priority(issues, "", source_missing=edge.get("source") == "SOURCE_MISSING"),
                "issues": issues,
                "category": "candidate_dependency_edge",
                "action": "Compare the candidate edge with the canonical manifest graph and promote only with explicit evidence.",
                "safety": "Do not treat static path proximity as proof of derivation.",
                "evidence": sorted(edge.get("evidence", [])),
                "review_status": edge.get("review_status", "REVIEW_REQUIRED"),
            },
        )
    ranked = sorted(
        items.values(),
        key=lambda item: (-item["priority"], item["target_type"], item["path"], item["key"]),
    )
    for index, item in enumerate(ranked, start=1):
        item["rank"] = index
    return {
        "schema_version": 1,
        "backlog_kind": "wwo_provenance_review_backlog",
        "audit_batch": "BATCH_3",
        "audit_base_revision": base_revision,
        "source_manifest": MANIFEST_RELATIVE,
        "source_matrix": MATRIX_RELATIVE,
        "policy": {
            "mechanically_safe_only": True,
            "license_inference": False,
            "authoritative_data_modification": False,
            "automatic_asset_regeneration": False,
        },
        "summary": {
            "items": len(ranked),
            "top_priority": ranked[0]["priority"] if ranked else 0,
            "source_missing_items": sum("SOURCE_MISSING" in item["issues"] for item in ranked),
            "generator_unknown_items": sum("GENERATOR_UNKNOWN" in item["issues"] for item in ranked),
            "broken_reference_items": sum("BROKEN_REFERENCE" in item["issues"] for item in ranked),
        },
        "items": ranked,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, default=Path(DEFAULT_OUTPUT))
    parser.add_argument("--base-revision", default="HEAD")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    output = args.output if args.output.is_absolute() else root / args.output
    backlog = build_backlog(root, args.base_revision)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(backlog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(backlog["summary"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
