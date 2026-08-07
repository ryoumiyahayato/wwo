#!/usr/bin/env python3
"""Unified vNext Godot validation runner."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


FATAL_PATTERNS = (
    re.compile(r"SCRIPT ERROR", re.IGNORECASE),
    re.compile(r"Parse Error", re.IGNORECASE),
    re.compile(r"Failed to load script", re.IGNORECASE),
    re.compile(r"Could not resolve class", re.IGNORECASE),
    re.compile(r"Could not find type", re.IGNORECASE),
    re.compile(r"Assertion failed", re.IGNORECASE),
)
NONZERO_FAILURES_PATTERN = re.compile(r"\b([1-9][0-9]*)\s+failures?\b", re.IGNORECASE)
SUCCESS_SUMMARY_PATTERN = re.compile(
    r"\b([1-9][0-9]*)\s+checks?,\s*0\s+failures?\b",
    re.IGNORECASE,
)


class ValidationError(RuntimeError):
    """Raised when the validation setup is invalid."""


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: str
    stderr: str

    @property
    def log(self) -> str:
        parts = []
        if self.stdout:
            parts.append(self.stdout.rstrip())
        if self.stderr:
            parts.append(self.stderr.rstrip())
        return "\n".join(parts)


def normalize_root(root_value: str) -> Path:
    root = Path(root_value).expanduser().resolve()
    if not root.is_dir():
        raise ValidationError(f"repository root does not exist: {root}")
    return root


def resolve_godot(godot_value: str) -> Path:
    candidate = Path(godot_value).expanduser()
    has_path_hint = candidate.is_absolute() or candidate.parent != Path(".")
    if has_path_hint:
        executable = candidate.resolve()
        if not executable.is_file():
            raise ValidationError(f"Godot executable does not exist: {executable}")
        return executable

    located = shutil.which(godot_value)
    if located is None:
        raise ValidationError(f"Godot executable does not exist or is not on PATH: {godot_value}")
    return Path(located).resolve()


def discover_test_scripts(root: Path) -> list[Path]:
    tests_root = root / "tests" / "vnext"
    if not tests_root.is_dir():
        raise ValidationError(f"vNext test directory does not exist: {tests_root}")

    discovered = [
        path
        for path in tests_root.rglob("*")
        if path.is_file() and path.name.endswith("_test.gd")
    ]
    discovered.sort(key=lambda path: path.relative_to(root).as_posix())
    if not discovered:
        raise ValidationError("no vNext test scripts found under tests/vnext")
    return discovered


def find_log_failure_reasons(log: str) -> list[str]:
    reasons: list[str] = []
    for pattern in FATAL_PATTERNS:
        if pattern.search(log):
            reasons.append(f"fatal log pattern: {pattern.pattern}")
    failure_match = NONZERO_FAILURES_PATTERN.search(log)
    if failure_match:
        reasons.append(f"log reports nonzero failures: {failure_match.group(0)}")
    return reasons


def has_success_summary(log: str) -> bool:
    return SUCCESS_SUMMARY_PATTERN.search(log) is not None


def evaluate_test_result(result: ProcessResult) -> list[str]:
    reasons: list[str] = []
    if result.returncode != 0:
        reasons.append(f"process exit code is {result.returncode}")
    reasons.extend(find_log_failure_reasons(result.log))
    if not has_success_summary(result.log):
        reasons.append("missing valid nonzero checks / 0 failures summary")
    return reasons


def evaluate_import_result(result: ProcessResult) -> list[str]:
    reasons: list[str] = []
    if result.returncode != 0:
        reasons.append(f"process exit code is {result.returncode}")
    reasons.extend(find_log_failure_reasons(result.log))
    return reasons


def run_process(command: Sequence[str], root: Path) -> ProcessResult:
    completed = subprocess.run(
        list(command),
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return ProcessResult(completed.returncode, completed.stdout, completed.stderr)


def print_failure(test_label: str, result: ProcessResult, reasons: Sequence[str]) -> None:
    print("VNext validation failed")
    print(f"test: {test_label}")
    print(f"exit code: {result.returncode}")
    print("failure reasons:")
    for reason in reasons:
        print(f"- {reason}")
    print("related log:")
    print(result.log if result.log else "<no output>")


def run_validation(root: Path, godot: Path) -> int:
    tests = discover_test_scripts(root)

    import_command = (
        str(godot),
        "--headless",
        "--audio-driver",
        "Dummy",
        "--editor",
        "--path",
        str(root),
        "--quit-after",
        "4",
    )
    import_result = run_process(import_command, root)
    import_reasons = evaluate_import_result(import_result)
    if import_reasons:
        print_failure("<import/script scan>", import_result, import_reasons)
        return 1

    for test_path in tests:
        relative = test_path.relative_to(root).as_posix()
        test_command = (
            str(godot),
            "--headless",
            "--audio-driver",
            "Dummy",
            "--path",
            str(root),
            "--script",
            f"res://{relative}",
        )
        result = run_process(test_command, root)
        reasons = evaluate_test_result(result)
        if reasons:
            print_failure(relative, result, reasons)
            return 1

    print(f"VNext validation: {len(tests)} test scripts passed")
    return 0


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run all vNext Godot validation tests.")
    parser.add_argument("--root", required=True, help="repository root")
    parser.add_argument("--godot", required=True, help="Godot executable path or command")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        root = normalize_root(args.root)
        godot = resolve_godot(args.godot)
        return run_validation(root, godot)
    except ValidationError as exc:
        print(f"VNext validation setup failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
