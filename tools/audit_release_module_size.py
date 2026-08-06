#!/usr/bin/env python3
"""Fail CI when the formal hemisphere UI regresses into oversized modules."""

from __future__ import annotations

import re
from pathlib import Path

MAX_FILE_LINES = 600
MAX_FUNCTION_LINES = 140
TARGETS = [
    Path("scripts/formal/formal_world_menu.gd"),
    Path("scripts/formal/formal_world_application.gd"),
    Path("scripts/ui_spikes/holographic_workspace/holographic_workspace_release.gd"),
    Path("scripts/ui_spikes/holographic_workspace/holographic_workspace_release_probe.gd"),
    Path("tests/formal/formal_world_integration_test.gd"),
    Path("tests/formal/formal_world_ui_capture.gd"),
]


def function_ranges(lines: list[str]) -> list[tuple[str, int, int]]:
    starts: list[tuple[str, int]] = []
    pattern = re.compile(r"^func\s+([A-Za-z0-9_]+)\s*\(")
    for index, line in enumerate(lines, start=1):
        match = pattern.match(line)
        if match:
            starts.append((match.group(1), index))
    output: list[tuple[str, int, int]] = []
    for index, (name, start) in enumerate(starts):
        end = starts[index + 1][1] - 1 if index + 1 < len(starts) else len(lines)
        output.append((name, start, end))
    return output


def main() -> None:
    failures: list[str] = []
    for path in TARGETS:
        if not path.is_file():
            failures.append(f"missing: {path}")
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        if len(lines) > MAX_FILE_LINES:
            failures.append(f"file too long: {path} ({len(lines)} > {MAX_FILE_LINES})")
        for name, start, end in function_ranges(lines):
            length = end - start + 1
            if length > MAX_FUNCTION_LINES:
                failures.append(
                    f"function too long: {path}:{start} {name} "
                    f"({length} > {MAX_FUNCTION_LINES})"
                )
        for index, line in enumerate(lines, start=1):
            if line.rstrip("\t ") != line:
                failures.append(f"trailing whitespace: {path}:{index}")
    if failures:
        raise SystemExit("\n".join(failures))
    print(
        f"formal release module audit passed: {len(TARGETS)} files, "
        f"file <= {MAX_FILE_LINES}, function <= {MAX_FUNCTION_LINES}"
    )


if __name__ == "__main__":
    main()
