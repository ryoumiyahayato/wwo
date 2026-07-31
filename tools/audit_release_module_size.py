#!/usr/bin/env python3
"""Fail CI when this release's UI modules regress into oversized files/functions."""

from __future__ import annotations

import re
from pathlib import Path

MAX_FILE_LINES = 500
MAX_FUNCTION_LINES = 120
TARGETS = [
    Path("scripts/v2_3/v2_3_life_loop_menu.gd"),
    Path("scripts/v2_3/v2_3_player_interface.gd"),
    Path("scripts/v2_3/v2_3_minimal_hud_overlay.gd"),
    Path("scripts/v2_3/v2_3_minimal_hud_overlay_polish.gd"),
    Path("scripts/ui_spikes/holographic_workspace/holographic_workspace_release.gd"),
    Path("scripts/ui_spikes/holographic_workspace/holographic_workspace_release_probe.gd"),
    Path("tests/v2_3/v2_3_entry_hud_probe.gd"),
    Path("tests/v2_3/v2_3_entry_hud_capture.gd"),
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
                failures.append(f"function too long: {path}:{start} {name} ({length} > {MAX_FUNCTION_LINES})")
        for index, line in enumerate(lines, start=1):
            if line.rstrip("\t ") != line:
                failures.append(f"trailing whitespace: {path}:{index}")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"release module size audit passed: {len(TARGETS)} files, file <= {MAX_FILE_LINES}, function <= {MAX_FUNCTION_LINES}")


if __name__ == "__main__":
    main()
