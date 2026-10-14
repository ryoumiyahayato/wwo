"""Run the Round3 tests and reproduce all frozen Round3 output hashes twice.

Run verify_baseline.py as well; the CI workflow explicitly coordinates both.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import sys
import tempfile
import time

from verify_baseline import execute, write_record

ROOT = Path(__file__).resolve().parent
ROUND3 = ROOT / "economy_quantity_lab/order_round3"


def output_hashes(directory):
    return {p.relative_to(directory).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(directory.rglob("*")) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / ".local")
    args = parser.parse_args()
    parent = args.output_dir.resolve()
    if parent == ROOT or parent.is_relative_to(ROOT / "economy_quantity_lab") or parent.is_relative_to(ROOT / "docs"):
        parser.error("Choose a directory outside source and archived evidence")
    parent.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="round3-verification-", dir=parent))
    record = {"python": sys.version, "platform": platform.platform(), "status": "failed", "checks": [],
              "run_directory": str(run_dir), "experiment_id": "order-commitment-round3"}
    started = time.perf_counter()
    try:
        expected = json.loads((ROUND3 / "evidence/hash_manifest.json").read_text(encoding="utf-8"))["files"]
        # Tests include old scenario equivalence, both cancellation identities,
        # FIFO, no-promise fallback, future-prefix isolation and negative supply.
        execute("round3_tests", ROUND3, ["-m", "unittest", "-v", "test_order_commitment.py"], run_dir, record, 18)
        for name in ("replay_a", "replay_b"):
            execute(name, ROOT, [
                str(ROUND3 / "run_order_commitment_experiment.py"), "--output-dir", str(run_dir / name),
                "--execution-log", str(run_dir / f"{name}_execution.json"),
            ], run_dir, record)
            actual = output_hashes(run_dir / name)
            if actual != expected:
                changed = sorted(k for k in set(actual) | set(expected) if actual.get(k) != expected.get(k))
                raise RuntimeError(f"Round3 byte/hash reproduction differs: {changed}")
            log = json.loads((run_dir / f"{name}_execution.json").read_text(encoding="utf-8"))
            if (log["case_count"], log["simulated_case_days"], log["max_abs_quantity_residual"], log["max_abs_order_residual"]) != (14, 8400, 0, 0):
                raise RuntimeError("Round3 execution metadata differs")
            record[name] = {"files_reproduced": len(actual), "summary_sha256": actual["summary.csv"],
                            "case_count": log["case_count"], "simulated_case_days": log["simulated_case_days"]}
            print(f"{name}: {len(actual)} files reproduced directly byte-for-byte; summary SHA-256 {actual['summary.csv']}", flush=True)
        record["status"] = "passed"
        return 0
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        record["error"] = str(error)
        print(f"FAILED: {error}", file=sys.stderr)
        return 1
    finally:
        record["elapsed_seconds"] = time.perf_counter() - started
        write_record(run_dir / "verification.json", record)
        print(f"Round3 verification {record['status']}: {run_dir / 'verification.json'}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
