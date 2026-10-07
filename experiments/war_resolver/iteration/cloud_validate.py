#!/usr/bin/env python3
"""Linux equivalent steps, retaining original scripts, exit rules and fatal matchers.

This is not execution of tools/run_validation.ps1. No simulation is implemented here.
Baselines record actual platform hashes, never adopt Windows hashes as Linux goldens.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = "c4731a33177660b83c6490f41fe42dcbe7cfa7bb"
VERSION = "4.6.3.stable.official.7d41c59c4"
EXPERIMENT_FATAL = re.compile(r"(?im)^ERROR:|SCRIPT ERROR|Parse Error|Failed to load script|Assertion failed|[1-9][0-9]* failures")
TASKS = [
    ("resolver", "tests.gd", "replay_probe.gd", "REPLAY_SHA256", "benchmark.gd", "War resolver"),
    ("roles", "role_tests.gd", "role_replay_probe.gd", "ROLE_REPLAY_SHA256", None, "Role overrides"),
    ("sandbox", "sandbox/tests.gd", "sandbox/observation_probe.gd", "SANDBOX_REPLAY_SHA256", None, "War sandbox"),
    *[(f"task{i}", f"{folder}/tests.gd", f"{folder}/replay_probe.gd", f"TASK{i}_REPLAY_SHA256", f"{folder}/benchmark.gd", f"Task{i} {label}")
      for i, folder, label in [(4, "aggregation", "aggregation"), (5, "structure", "structure"), (6, "logistics", "logistics"), (7, "information", "information"), (8, "decision", "decision")]],
]
REGRESSIONS = [
    "tests/vnext/military_strategy_test.gd", "tests/vnext/military_r3_findings_test.gd",
    "tests/vnext/military_spatial_capacity_integration_test.gd",
    "tests/formal/formal_military_authorized_defend_integration_test.gd",
    "tests/formal/formal_exact_persistence_roundtrip_test.gd",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/usr/local/bin/godot")
    parser.add_argument("--output", required=True)
    parser.add_argument("--mode", choices=["baseline", "final", "affected"], default="baseline")
    parser.add_argument("--baseline-evidence", type=Path)
    parser.add_argument("--script", action="append", default=[])
    args = parser.parse_args()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    executable = shutil.which(args.godot)
    if not executable:
        raise RuntimeError("GODOT_UNAVAILABLE")
    env = os.environ.copy()
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    for key, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        directory = output / ".xdg" / folder
        directory.mkdir(parents=True)
        env[key] = str(directory)
    official = (ROOT / "tools/run_validation.ps1").read_text(encoding="utf-8")
    official_fatal = re.compile(re.search(r"\$parseErrorPattern = '([^']+)'", official)[1])
    steps, checks, hashes = [], {}, {}
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    digest = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in (ROOT / "experiments/war_resolver").rglob("*") if p.suffix in [".gd", ".py"]}
    report = dict(mode=args.mode, source_head=head, frozen_base=BASE, version=VERSION,
                  source_digest=digest, platform=sys.platform, python=sys.version,
                  steps=steps, checks=checks, hashes=hashes, known_baseline_failure=[],
                  official_powershell="NOT RUN; equivalent steps", complete=False)

    def save():
        (output / "evidence.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def run(name, command, timeout=1800, unified=False):
        started = time.perf_counter()
        try:
            proc = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
            log, code = proc.stdout.decode("utf-8", errors="replace"), proc.returncode
        except subprocess.TimeoutExpired as exc:
            raw = exc.stdout or b""
            log, code = raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else raw, -1
        (output / f"{name}.log").write_text(log, encoding="utf-8")
        fatal = (official_fatal if unified else EXPERIMENT_FATAL).search(log)
        passed = code == 0 and not fatal
        row = dict(name=name, command=command, exit=code, passed=passed,
                   wall_seconds=round(time.perf_counter() - started, 5),
                   fatal=fatal.group(0) if fatal else None,
                   log=f"{name}.log", log_sha256=hashlib.sha256(log.encode()).hexdigest(),
                   retained_shutdown_diagnostics=len(re.findall(r"(?m)^ERROR: \d+ resources still in use at exit", log)))
        steps.append(row)
        save()
        print(f"{'PASS' if passed else 'FAIL'} {name}: exit={code}; {row['wall_seconds']}s", flush=True)
        return log

    def gd(name, script, timeout=1800, unified=False):
        return run(name, [executable, "--headless", "--path", str(ROOT), "--script", "res://" + script], timeout, unified)

    def pair(name, script, prefix, unified=False, timeout=1800):
        values = []
        for suffix in ["a", "b"]:
            log = gd(name + "_" + suffix, script, timeout, unified)
            match = re.findall(r"(?m)^" + re.escape(prefix) + r"=([0-9a-f]{64})$", log)
            values.append(match)
        valid = len(values[0]) == 1 and values[0] == values[1]
        hashes[name] = values[0][0] if valid else None
        if not valid:
            report.setdefault("contract_failures", []).append(f"{name}: incomplete/different fresh-process replay")
        save()

    if args.mode == "baseline" and head != BASE:
        raise RuntimeError("Baseline must run on frozen code HEAD")
    version = run("version", [executable, "--version"], 30).strip()
    if version != VERSION or not steps[-1]["passed"]:
        raise RuntimeError("PINNED_VERSION_MISMATCH")
    run("import", [executable, "--headless", "--editor", "--path", str(ROOT), "--quit"], 180, True)
    if not steps[-1]["passed"]:
        raise RuntimeError("IMPORT_BLOCKED")
    if args.mode != "affected":
        for name, test, replay, prefix, benchmark, summary in TASKS:
            log = gd(name + "_tests", "experiments/war_resolver/" + test)
            match = re.findall(re.escape(summary) + r": ([1-9][0-9]*) checks, 0 failures", log)
            checks[name] = int(match[0]) if len(match) == 1 else None
            if checks[name] is None:
                report.setdefault("contract_failures", []).append(name + ": missing success summary")
            pair(name, "experiments/war_resolver/" + replay, prefix)
            if benchmark:
                gd(name + "_benchmark", "experiments/war_resolver/" + benchmark)
        run("sandbox_scene", [executable, "--headless", "--path", str(ROOT), "res://experiments/war_resolver/sandbox/sandbox.tscn", "--quit-after", "5"])
        for script in REGRESSIONS:
            name = Path(script).stem
            log = gd(name, script, 900)
            summaries = re.findall(r"\b([1-9][0-9]*) checks, 0 failures", log)
            checks[name] = list(map(int, summaries))
            if not summaries:
                report.setdefault("contract_failures", []).append(name + ": missing success summary")

        # Same Python commands and unchanged original Godot scripts as the official runner.
        for script in ["tools/audit_1900_commodity_economy.py", "tools/audit_1900_economy_integration.py", "tools/audit_1900_world_economy_compact.py", "tools/provenance/generate_historical_provenance.py"]:
            run(Path(script).stem, [sys.executable, "-B", script, *(["--check"] if "provenance" in script else [])], 120, True)
        run("world_data", [sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests/world_data", "-p", "test_*.py", "-v"], 120, True)
        definitions = re.findall(r"@\{ Name = '([^']+)'; Script = '([^']+)'(?:; TimeoutSeconds = (\d+))? \}", official)
        if len(definitions) != 33:
            raise RuntimeError(f"Official step extraction incomplete: {len(definitions)}")
        for name, script, timeout in definitions:
            gd("unified_" + Path(script).stem, script.removeprefix("res://"), int(timeout or 120), True)
        for name, script, prefix, timeout in [
            ("formal_political", "runtime_political_snapshot_probe.gd", "RUNTIME_POLITICAL_SNAPSHOT_SHA256", 120),
            ("formal_market", "formal_world_market_snapshot_probe.gd", "FORMAL_MARKET_SNAPSHOT_SHA256", 120),
            ("formal_economic", "formal_world_economic_snapshot_probe.gd", "FORMAL_ECONOMIC_SNAPSHOT_SHA256", 180),
            ("formal_fingerprint", "formal_world_fingerprint_probe.gd", "FORMAL_WORLD_FINGERPRINT_SHA256", 180),
        ]:
            pair(name, "tests/formal/" + script, prefix, True, timeout)
        run("formal_startup", [executable, "--headless", "--path", str(ROOT), "--quit-after", "5"], 30, True)
        log = gd("codex_audit", "tests/codex_audit_regression.gd")
        if re.findall(r"CODEX AUDIT REGRESSION PASSED: (\d+) checks", log) != ["31"]:
            report.setdefault("contract_failures", []).append("audit: missing 31-check completion")
        # Independent repeat on the frozen baseline; never classify a new failure by old reports.
        if args.mode == "baseline":
            gd("baseline_golden_independent", "tests/formal/formal_world_economy_golden_test.gd", 240, True)
            original = (output / "unified_formal_world_economy_golden_test.log").read_text()
            repeat = (output / "baseline_golden_independent.log").read_text()
            expected = ["24519f5dc2d191d7d5bac67437e35e6d4c4e734700f5c9915ee1df620abdfdcf", "241451cb8ce5a69d62a5105c0b0808fe16fbdc4ca1f0cb79ade3ffde780c56fd"]
            if all(value in original and value in repeat for value in expected) and "2 failures" in original and "2 failures" in repeat:
                report["known_baseline_failure"] = ["unified_formal_world_economy_golden_test", "baseline_golden_independent"]
                report["baseline_golden_actual_hashes"] = expected
    for script in args.script:
        gd("new_" + Path(script).stem, script)
    if args.baseline_evidence:
        baseline = json.loads(args.baseline_evidence.read_text())
        for key, value in hashes.items():
            if baseline["hashes"].get(key) != value:
                report.setdefault("contract_failures", []).append("Same-platform retained hash changed: " + key)
        for name in baseline["known_baseline_failure"]:
            if name == "baseline_golden_independent":
                continue
            old = (args.baseline_evidence.parent / f"{name}.log").read_text()
            new = (output / f"{name}.log").read_text()
            if all(value in new for value in baseline["baseline_golden_actual_hashes"]) and re.findall(r"^\[FAIL\].*$", old, re.M) == re.findall(r"^\[FAIL\].*$", new, re.M):
                report["known_baseline_failure"].append(name)
            else:
                report.setdefault("contract_failures", []).append("Baseline failure changed: " + name)
    if any(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != value for name, value in digest.items()):
        report.setdefault("contract_failures", []).append("Sources changed during validation")
    report["complete"] = True
    report["new_failed_steps"] = [row["name"] for row in steps if not row["passed"] and row["name"] not in report["known_baseline_failure"]]
    report["gate_passed_excluding_disclosed_baseline_failure"] = not report["new_failed_steps"] and not report.get("contract_failures")
    save()
    print(json.dumps({key: report.get(key) for key in ["complete", "checks", "hashes", "known_baseline_failure", "new_failed_steps", "contract_failures", "gate_passed_excluding_disclosed_baseline_failure"]}, ensure_ascii=False), flush=True)
    return 0 if report["gate_passed_excluding_disclosed_baseline_failure"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
