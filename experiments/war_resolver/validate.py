#!/usr/bin/env python3
"""Real pinned Godot import, fatal-log scans, replay, optional retained regressions.

No timing gates. Core simulation remains GDScript; this only orchestrates processes.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

VERSION = "4.6.3.stable.official.7d41c59c4"
FATAL = re.compile(r"(?im)^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Assertion failed|[1-9][0-9]* failures")
REGRESSIONS = [
    "tests/vnext/military_strategy_test.gd",
    "tests/vnext/military_r3_findings_test.gd",
    "tests/vnext/military_spatial_capacity_integration_test.gd",
    "tests/formal/formal_military_authorized_defend_integration_test.gd",
    "tests/formal/formal_exact_persistence_roundtrip_test.gd",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", default="builds/war-resolver")
    parser.add_argument("--regressions", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    executable = shutil.which(args.godot)
    if executable is None:
        print("NOT RUN — GODOT CLI UNAVAILABLE", file=sys.stderr)
        return 2
    output = (root / args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    # Avoid the sandbox's read-only default user directories; do not replace HOME.
    for name, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        destination = output / ".xdg" / folder
        destination.mkdir(parents=True, exist_ok=True)
        env[name] = str(destination)
    results: list[dict] = []

    def run(name: str, arguments: list[str], timeout: int = 300) -> str:
        command = [executable, *arguments]
        started = time.perf_counter()
        try:
            proc = subprocess.run(command, cwd=root, env=env, text=True, encoding="utf-8", errors="replace",
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
            log, code = proc.stdout, proc.returncode
        except subprocess.TimeoutExpired as exc:
            log, code = str(exc.stdout), -1
        log_path = output / (name + ".log")
        log_path.write_text(log, encoding="utf-8")
        passed = code == 0 and FATAL.search(log) is None
        results.append({"name": name, "command": command, "returncode": code, "passed": passed,
                        "wall_seconds": round(time.perf_counter() - started, 4), "log": str(log_path)})
        (output / "validation.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(f"{'PASS' if passed else 'FAIL'} {name}: exit={code}; log={log_path}", flush=True)
        if not passed:
            raise RuntimeError(log[-6000:])
        return log

    try:
        version = run("version", ["--version"]).strip()
        if version != VERSION:
            raise RuntimeError(f"Godot mismatch: expected {VERSION}, got {version}")
        run("import", ["--editor", "--headless", "--path", str(root), "--quit"])
        headless = ["--headless", "--path", str(root), "--script"]
        log = run("resolver-tests", [*headless, "res://experiments/war_resolver/tests.gd"])
        summary = re.search(r"War resolver: (\d+) checks, 0 failures", log)
        if summary is None or int(summary.group(1)) == 0:
            raise RuntimeError("Missing nonzero check count / zero failure summary")
        print(summary.group(0), flush=True)
        probe_a = run("replay-a", [*headless, "res://experiments/war_resolver/replay_probe.gd"])
        probe_b = run("replay-b", [*headless, "res://experiments/war_resolver/replay_probe.gd"])
        hash_a = re.findall(r"REPLAY_SHA256=([a-f0-9]{64})", probe_a)
        hash_b = re.findall(r"REPLAY_SHA256=([a-f0-9]{64})", probe_b)
        if len(hash_a) != 1 or hash_a != hash_b:
            raise RuntimeError("Fresh-process replay differs or missing hash")
        print("Fresh-process replay: " + hash_a[0], flush=True)
        log = run("benchmark", [*headless, "res://experiments/war_resolver/benchmark.gd"])
        records = [json.loads(line.split("=", 1)[1]) for line in log.splitlines() if line.startswith("BENCHMARK_JSON=")]
        if len(records) < 4:
            raise RuntimeError("Missing benchmark cases")
        (output / "benchmark.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
        for line in log.splitlines():
            if line.startswith("TRACE"):
                print(line, flush=True)
        if args.regressions:
            for script in REGRESSIONS:
                log = run(Path(script).stem, [*headless, "res://" + script], timeout=600)
                if re.search(r"\b[1-9][0-9]* checks, 0 failures", log) is None:
                    raise RuntimeError(f"Missing successful regression summary: {script}")
                print("\n".join(line for line in log.splitlines() if "checks, 0 failures" in line), flush=True)
    except (RuntimeError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"PASS: real Godot validation; evidence in {output}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
