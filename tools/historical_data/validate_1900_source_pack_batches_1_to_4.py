#!/usr/bin/env python3
"""Aggregate focused source-pack validation for Batches 1 through 4."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
REPORT_PATH = ROOT / "data" / "staging" / "1900" / "batch4_qa_report.json"


def run(script: Path, args: list[str]) -> dict[str, Any]:
    completed = subprocess.run([sys.executable, str(script), *args], cwd=ROOT, capture_output=True, text=True, check=False)
    result: dict[str, Any] = {"script": script.relative_to(ROOT).as_posix(), "args": args, "exit_code": completed.returncode}
    try:
        result["output"] = json.loads(completed.stdout)
    except json.JSONDecodeError:
        result["output"] = {"raw_stdout": completed.stdout.strip(), "raw_stderr": completed.stderr.strip()}
    if completed.stderr.strip():
        result["stderr"] = completed.stderr.strip()
    return result


def main() -> int:
    checks = [
        run(ROOT / "tools" / "historical_data" / "validate_1900_source_pack.py", ["--quiet"]),
        run(ROOT / "tools" / "historical_data" / "validate_1900_source_pack_r1.py", ["--quiet"]),
        run(ROOT / "tools" / "historical_data" / "validate_1900_source_pack_schemas.py", ["--quiet"]),
        run(ROOT / "tools" / "historical_data" / "validate_1900_source_pack_batch2.py", []),
        run(ROOT / "tools" / "historical_data" / "validate_1900_source_pack_batch3.py", []),
        run(ROOT / "tools" / "historical_data" / "validate_1900_source_pack_batch4.py", []),
        run(ROOT / "tools" / "historical_data" / "test_1900_source_pack_batch1_determinism.py", []),
        run(ROOT / "tools" / "historical_data" / "test_1900_source_pack_batch2_determinism.py", []),
        run(ROOT / "tools" / "historical_data" / "test_1900_source_pack_batch3_determinism.py", []),
        run(ROOT / "tools" / "historical_data" / "test_1900_source_pack_batch4_determinism.py", []),
        run(ROOT / "tools" / "historical_data" / "test_1900_source_pack_schema_negative.py", []),
        run(ROOT / "tools" / "historical_data" / "test_1900_source_pack_r1.py", []),
    ]
    overall_ok = all(check["exit_code"] == 0 and check.get("output", {}).get("ok") is True for check in checks)
    report = {
        "schema_id": "wwo_1900_source_pack_batches_1_to_4_qa_report_v2",
        "batches": [1, 2, 3, 4],
        "checks": checks,
        "overall_ok": overall_ok,
        "policy": {"runtime_authority": False, "no_gameplay_balance": True, "determinism_requires_byte_identical_outputs": True},
    }
    REPORT_PATH.write_bytes((json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8"))
    print(json.dumps({"ok": overall_ok, "report": REPORT_PATH.relative_to(ROOT).as_posix(), "checks": len(checks)}, sort_keys=True))
    return 0 if overall_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
