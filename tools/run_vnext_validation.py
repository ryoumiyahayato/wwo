#!/usr/bin/env python3
"""Unified vNext Godot validation runner."""

from __future__ import annotations

import argparse
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
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
DEFAULT_IMPORT_TIMEOUT_SECONDS = 300
DEFAULT_TEST_TIMEOUT_SECONDS = 300
DEFAULT_LONG_TEST_TIMEOUT_SECONDS = 1200
DEFAULT_HEARTBEAT_SECONDS = 60
LONG_TEST_SCRIPT = "res://tests/vnext/market_economy_long_term_test.gd"
VALIDATION_SUITES = ("all", "focused", "long-run")


class ValidationError(RuntimeError):
    """Raised when the validation setup is invalid."""


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: str
    stderr: str
    timed_out: bool = False
    elapsed_seconds: float = 0.0

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


def discover_test_scripts(root: Path, suite: str = "all") -> list[Path]:
    if suite not in VALIDATION_SUITES:
        raise ValidationError(
            f"unknown validation suite {suite!r}; expected one of {', '.join(VALIDATION_SUITES)}"
        )
    tests_root = root / "tests" / "vnext"
    if not tests_root.is_dir():
        raise ValidationError(f"vNext test directory does not exist: {tests_root}")

    discovered = [
        path
        for path in tests_root.rglob("*")
        if path.is_file() and path.name.endswith("_test.gd")
    ]
    discovered.sort(key=lambda path: path.relative_to(root).as_posix())
    long_test_name = Path(LONG_TEST_SCRIPT).name
    if suite == "focused":
        discovered = [path for path in discovered if path.name != long_test_name]
    elif suite == "long-run":
        discovered = [path for path in discovered if path.name == long_test_name]
    if not discovered:
        raise ValidationError(
            f"no vNext test scripts found for suite {suite!r} under tests/vnext"
        )
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
    if result.timed_out:
        reasons.append(f"process timed out after {result.elapsed_seconds:.1f}s")
    if result.returncode != 0:
        reasons.append(f"process exit code is {result.returncode}")
    reasons.extend(find_log_failure_reasons(result.log))
    if not has_success_summary(result.log):
        reasons.append("missing valid nonzero checks / 0 failures summary")
    return reasons


def evaluate_import_result(result: ProcessResult) -> list[str]:
    reasons: list[str] = []
    if result.timed_out:
        reasons.append(f"process timed out after {result.elapsed_seconds:.1f}s")
    if result.returncode != 0:
        reasons.append(f"process exit code is {result.returncode}")
    reasons.extend(find_log_failure_reasons(result.log))
    return reasons


def _positive_env_seconds(name: str, default: int) -> int:
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    try:
        value = int(raw_value)
    except ValueError as exc:
        raise ValidationError(f"{name} must be a positive integer, got {raw_value!r}") from exc
    if value <= 0:
        raise ValidationError(f"{name} must be a positive integer, got {value}")
    return value


def _command_timeout_seconds(command: Sequence[str]) -> int:
    if "--editor" in command:
        return _positive_env_seconds(
            "VNEXT_IMPORT_TIMEOUT_SECONDS", DEFAULT_IMPORT_TIMEOUT_SECONDS
        )
    if LONG_TEST_SCRIPT in command:
        return _positive_env_seconds(
            "VNEXT_LONG_TEST_TIMEOUT_SECONDS", DEFAULT_LONG_TEST_TIMEOUT_SECONDS
        )
    return _positive_env_seconds("VNEXT_TEST_TIMEOUT_SECONDS", DEFAULT_TEST_TIMEOUT_SECONDS)


def _command_label(command: Sequence[str]) -> str:
    if "--editor" in command:
        return "import/script scan"
    if "--script" in command:
        index = command.index("--script")
        if index + 1 < len(command):
            return command[index + 1]
    return Path(command[0]).name if command else "process"


def run_process(command: Sequence[str], root: Path) -> ProcessResult:
    timeout_seconds = _command_timeout_seconds(command)
    heartbeat_seconds = _positive_env_seconds(
        "VNEXT_HEARTBEAT_SECONDS", DEFAULT_HEARTBEAT_SECONDS
    )
    label = _command_label(command)
    print(f"[vnext] START {label} (timeout={timeout_seconds}s)", flush=True)

    started = time.monotonic()
    process = subprocess.Popen(
        list(command),
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    if process.stdout is None:
        process.kill()
        process.wait()
        raise ValidationError(f"failed to capture process output for {label}")

    output_queue: queue.Queue[str | None] = queue.Queue()

    def read_output() -> None:
        try:
            for line in process.stdout:
                output_queue.put(line)
        finally:
            output_queue.put(None)

    reader = threading.Thread(target=read_output, name="vnext-output-reader", daemon=True)
    reader.start()

    output_parts: list[str] = []
    stream_closed = False
    timed_out = False
    last_heartbeat = started
    while True:
        try:
            item = output_queue.get(timeout=0.25)
            if item is None:
                stream_closed = True
            else:
                output_parts.append(item)
                print(item, end="", flush=True)
        except queue.Empty:
            pass

        now = time.monotonic()
        elapsed = now - started
        if not timed_out and elapsed >= timeout_seconds:
            timed_out = True
            print(
                f"[vnext] TIMEOUT {label} after {elapsed:.1f}s; terminating process",
                flush=True,
            )
            process.kill()
        elif not timed_out and now - last_heartbeat >= heartbeat_seconds:
            print(f"[vnext] HEARTBEAT {label} elapsed={elapsed:.1f}s", flush=True)
            last_heartbeat = now

        if process.poll() is not None and stream_closed:
            break

    reader.join(timeout=5.0)
    returncode = process.wait()
    elapsed = time.monotonic() - started
    status = "TIMEOUT" if timed_out else ("PASS" if returncode == 0 else "FAIL")
    print(
        f"[vnext] END {label} status={status} exit={returncode} elapsed={elapsed:.1f}s",
        flush=True,
    )
    return ProcessResult(
        returncode=returncode,
        stdout="".join(output_parts),
        stderr="",
        timed_out=timed_out,
        elapsed_seconds=elapsed,
    )


def print_failure(test_label: str, result: ProcessResult, reasons: Sequence[str]) -> None:
    print("VNext validation failed")
    print(f"test: {test_label}")
    print(f"exit code: {result.returncode}")
    print("failure reasons:")
    for reason in reasons:
        print(f"- {reason}")
    print("related log:")
    print(result.log if result.log else "<no output>")


def run_validation(root: Path, godot: Path, suite: str = "all") -> int:
    tests = discover_test_scripts(root, suite)

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

    print(f"VNext validation ({suite}): {len(tests)} test scripts passed")
    return 0


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run all vNext Godot validation tests.")
    parser.add_argument("--root", required=True, help="repository root")
    parser.add_argument("--godot", required=True, help="Godot executable path or command")
    parser.add_argument(
        "--suite",
        choices=VALIDATION_SUITES,
        default="all",
        help="validation lane to run (all, focused, or long-run)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        root = normalize_root(args.root)
        godot = resolve_godot(args.godot)
        return run_validation(root, godot, args.suite)
    except ValidationError as exc:
        print(f"VNext validation setup failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
