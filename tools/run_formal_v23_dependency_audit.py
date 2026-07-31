#!/usr/bin/env python3
from __future__ import annotations

from collections import deque

import generate_formal_v23_dependency_audit as generator


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


def main() -> int:
    generator.reverse_closure = _linear_reverse_closure
    return generator.main()


if __name__ == "__main__":
    raise SystemExit(main())
