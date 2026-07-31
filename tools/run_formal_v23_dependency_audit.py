#!/usr/bin/env python3
from __future__ import annotations

import faulthandler
import os
import threading
from collections import deque
from pathlib import Path

import generate_formal_v23_dependency_audit as generator

_DYNAMIC_INDEX: list[tuple[str, int, str]] | None = None
_ORIGINAL_BUILD_AUDIT = generator.build_audit
RUNNER_PATH = "tools/run_formal_v23_dependency_audit.py"


def _linear_bfs_paths(roots: set[str], nodes: dict) -> tuple[dict[str, list[str]], dict[str, int]]:
    paths: dict[str, list[str]] = {}
    distances: dict[str, int] = {}
    queue: deque[str] = deque()
    for root in sorted(roots):
        if root in nodes and root not in distances:
            paths[root] = [root]
            distances[root] = 0
            queue.append(root)
    while queue:
        current = queue.popleft()
        for target in sorted(nodes[current].references):
            if target in distances:
                continue
            distances[target] = distances[current] + 1
            paths[target] = paths[current] + [target]
            queue.append(target)
    return paths, distances


def _linear_reverse_closure(path: str, reverse: dict[str, set[str]]) -> set[str]:
    seen: set[str] = set()
    queued: set[str] = set(reverse.get(path, set()))
    queue: deque[str] = deque(sorted(queued))
    while queue:
        current = queue.popleft()
        queued.discard(current)
        if current in seen:
            continue
        seen.add(current)
        for parent in sorted(reverse.get(current, set())):
            if parent not in seen and parent not in queued:
                queued.add(parent)
                queue.append(parent)
    return seen


def _indexed_incoming_dynamic_sites(path: str, node, nodes: dict) -> list[str]:
    global _DYNAMIC_INDEX
    if _DYNAMIC_INDEX is None:
        index: list[tuple[str, int, str]] = []
        for caller_path, caller in sorted(nodes.items()):
            if caller_path.startswith("docs/") or caller_path in generator.EXCLUDED_PATHS:
                continue
            for number, line in enumerate(caller.text.splitlines(), 1):
                if generator.engine.DYNAMIC_RE.search(line):
                    index.append((caller_path, number, line))
        _DYNAMIC_INDEX = index
    terms = ["res://" + path, path, *node.class_names]
    return sorted({
        f"{caller_path}:{number}: {line.strip()[:240]}"
        for caller_path, number, line in _DYNAMIC_INDEX
        if any(term and term in line for term in terms)
    })


def _recount(audit: dict) -> None:
    entries = audit["candidates"]
    counts = audit["counts"]
    counts.update({
        "v23_related_production_files": sum(
            item["file_path"].startswith(generator.engine.PRODUCTION_PREFIXES) for item in entries
        ),
        "v23_related_test_files": sum(item["file_path"].startswith("tests/") for item in entries),
        "formal_direct_A": sum(item["classification"] == "A" for item in entries),
        "formal_indirect_B": sum(item["classification"] == "B" for item in entries),
        "alpha_fixture_C": sum(item["classification"] == "C" for item in entries),
        "ui_spike_D": sum(item["classification"] == "D" for item in entries),
        "compatibility_E": sum(item["classification"] == "E" for item in entries),
        "test_only_F": sum(item["classification"] == "F" for item in entries),
        "unused_G": sum(item["classification"] == "G" for item in entries),
        "uncertain_U": sum(item["classification"] == "U" for item in entries),
        "formal_runtime_transitive_paths": sum(item["formal_reachable"] for item in entries),
        "formal_save_dependencies": sum(item["formal_save_or_load"] for item in entries),
        "formal_long_term_dependencies": sum(item["formal_ten_year"] for item in entries),
        "candidate_total": len(entries),
    })


def _refine_audit(root: Path, audit: dict) -> dict:
    audit["candidates"] = [
        item for item in audit["candidates"] if item["file_path"] != RUNNER_PATH
    ]
    by_path = {item["file_path"]: item for item in audit["candidates"]}
    changed = True
    while changed:
        changed = False
        for item in audit["candidates"]:
            if item["classification"] != "U" or item["dynamic_loading_evidence"]:
                continue
            callers = sorted(set(item["direct_callers"] + item["indirect_callers"]))
            if callers and all(
                caller in by_path and by_path[caller]["classification"] in {"G", "U"}
                for caller in callers
            ):
                item["classification"] = "G"
                item["classification_label"] = generator.engine.CLASS_LABELS["G"]
                item["classification_reason"] = "仅由同一无入口候选簇调用，整个闭包没有外部根或动态加载证据"
                item["recommendation"] = generator.engine.RECOMMENDATIONS["G"]
                item["confidence"] = "high"
                changed = True

    workflow_text = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in sorted((root / ".github" / "workflows").glob("*"))
        if path.is_file()
    )
    for item in audit["special_checks"]["standalone_v23_entries"]:
        item["workflow_referenced"] = (
            item["path"] in workflow_text or "res://" + item["path"] in workflow_text
        )
    _recount(audit)
    return audit


def _refined_build_audit(root: Path) -> dict:
    return _refine_audit(root.resolve(), _ORIGINAL_BUILD_AUDIT(root))


def _hard_timeout() -> None:
    print("Formal V2.3 dependency generation exceeded 180 seconds.", flush=True)
    os._exit(124)


def main() -> int:
    generator.EXCLUDED_PATHS.add(RUNNER_PATH)
    generator.engine.bfs_paths = _linear_bfs_paths
    generator.reverse_closure = _linear_reverse_closure
    generator.incoming_dynamic_sites = _indexed_incoming_dynamic_sites
    generator.build_audit = _refined_build_audit
    faulthandler.dump_traceback_later(60, repeat=True)
    timer = threading.Timer(180, _hard_timeout)
    timer.daemon = True
    timer.start()
    try:
        return generator.main()
    finally:
        timer.cancel()
        faulthandler.cancel_dump_traceback_later()


if __name__ == "__main__":
    raise SystemExit(main())
