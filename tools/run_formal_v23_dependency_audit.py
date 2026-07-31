#!/usr/bin/env python3
from __future__ import annotations

import faulthandler
import os
import threading
from collections import deque

import generate_formal_v23_dependency_audit as generator


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


def _hard_timeout() -> None:
    print("Formal V2.3 dependency generation exceeded 180 seconds.", flush=True)
    os._exit(124)


def main() -> int:
    generator.engine.bfs_paths = _linear_bfs_paths
    generator.reverse_closure = _linear_reverse_closure
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
