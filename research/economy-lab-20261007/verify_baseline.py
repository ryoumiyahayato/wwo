"""Coordinate unchanged entrypoints and compare the imported evidence hashes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent
LAB = ROOT / "economy_quantity_lab"
ROUND2 = LAB / "inventory_round2"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_record(path, record):
    path.write_bytes((json.dumps(record, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def execute(name, cwd, args, run_dir, report, expected_tests=None):
    command = [sys.executable, *args]
    print(f"{name}: {command}", flush=True)
    started = time.perf_counter()
    result = subprocess.run(
        command, cwd=cwd, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"),
        capture_output=True, text=True, encoding="utf-8",
    )
    (run_dir / f"{name}.stdout.txt").write_bytes(result.stdout.encode("utf-8"))
    (run_dir / f"{name}.stderr.txt").write_bytes(result.stderr.encode("utf-8"))
    check = {
        "name": name, "command": command, "cwd": str(cwd),
        "exit_code": result.returncode, "elapsed_seconds": time.perf_counter() - started,
    }
    report["checks"].append(check)
    if result.returncode:
        print(result.stdout + result.stderr, file=sys.stderr)
        raise RuntimeError(f"{name} failed with exit code {result.returncode}")
    if expected_tests is not None:
        match = re.search(r"Ran (\d+) tests? in", result.stderr)
        if match is None or int(match.group(1)) != expected_tests:
            raise RuntimeError(f"{name}: expected exactly {expected_tests} baseline tests")
        check["test_count"] = expected_tests
    print(f"{name}: passed", flush=True)


def compare_outputs(expected_dir, replay_dir, names, report, strict_bytes):
    actual_names = {p.relative_to(replay_dir).as_posix() for p in replay_dir.rglob("*") if p.is_file()}
    if actual_names != set(names):
        raise RuntimeError(f"Output file set differs: {replay_dir}")
    for name in sorted(names):
        expected_path = expected_dir / name
        generated_path = replay_dir / name
        expected = expected_path.read_bytes()
        generated = generated_path.read_bytes()
        match = expected == generated
        entry = {
            "source_path": expected_path.relative_to(ROOT).as_posix(),
            "expected_sha256": sha(expected), "raw_sha256": sha(generated),
            "byte_for_byte": match,
        }
        report["outputs"].append(entry)
        if not match:
            # Only the existing runner's Windows JSON text-mode translation is allowed.
            # Raw output and its hash stay available; content differences still fail.
            normalized = generated.replace(b"\r\n", b"\n")
            compatible = (
                not strict_bytes and sys.platform == "win32" and generated_path.suffix == ".json"
                and normalized == expected
            )
            entry["windows_json_lf_compatible"] = compatible
            entry["lf_sha256"] = sha(normalized)
            if not compatible:
                raise RuntimeError(f"Output bytes differ: {entry['source_path']}")


def verify(run_dir, report, strict_bytes):
    manifest = json.loads((ROOT / "docs/source_manifest.json").read_text(encoding="utf-8"))
    report["baseline_id"] = manifest["baseline_id"]
    report["source_archive_sha256"] = manifest["archive_sha256"]
    for name, expected in manifest["files"].items():
        path = ROOT / name
        if not path.is_file() or sha(path.read_bytes()) != expected:
            raise RuntimeError(f"Imported source missing or changed: {name}")
    report["source_files_verified"] = len(manifest["files"])
    print(f"Baseline: {report['baseline_id']}; {report['source_files_verified']} source hashes passed", flush=True)

    execute("original_tests", LAB, ["-m", "unittest", "-v", "test_economy.py"], run_dir, report, 8)
    execute("round2_tests", ROUND2, ["-m", "unittest", "-v", "test_inventory_comparison.py"], run_dir, report, 9)
    execute("baseline_reproduction", LAB, ["run_experiment.py", "--output-dir", str(run_dir / "baseline")], run_dir, report)
    execute("round2_comparison", ROUND2, [
        "run_inventory_comparison.py", "--output-dir", str(run_dir / "round2"),
        "--execution-log", str(run_dir / "execution_log.json"),
    ], run_dir, report)

    baseline_names = [Path(n).name for n in manifest["files"] if Path(n).parent.as_posix() == "economy_quantity_lab" and n.endswith(".csv")]
    result_prefix = "economy_quantity_lab/inventory_round2/inventory_comparison_results/"
    round2_names = [n.removeprefix(result_prefix) for n in manifest["files"] if n.startswith(result_prefix)]
    compare_outputs(LAB, run_dir / "baseline", baseline_names, report, strict_bytes)
    compare_outputs(ROUND2 / "inventory_comparison_results", run_dir / "round2", round2_names, report, strict_bytes)

    execution = json.loads((run_dir / "execution_log.json").read_text(encoding="utf-8"))
    if execution["case_count"] != 33 or execution["simulated_case_days"] != 19800 or execution["max_abs_quantity_residual"] != 0:
        raise RuntimeError("Round2 execution metadata differs from the declared baseline")
    report["case_count"] = execution["case_count"]
    report["simulated_case_days"] = execution["simulated_case_days"]
    report["max_abs_quantity_residual"] = execution["max_abs_quantity_residual"]
    report["summary_sha256"] = sha((run_dir / "round2/summary.csv").read_bytes())
    report["period_summary_sha256"] = sha((run_dir / "round2/period_summary.csv").read_bytes())
    # Recheck the imported files after running all subprocesses.
    for name, expected in manifest["files"].items():
        if sha((ROOT / name).read_bytes()) != expected:
            raise RuntimeError(f"Imported source changed during verification: {name}")
    raw_matches = sum(entry["byte_for_byte"] for entry in report["outputs"])
    report["raw_matching_outputs"] = raw_matches
    report["windows_json_lf_matches"] = len(report["outputs"]) - raw_matches
    print(f"Outputs: {raw_matches}/{len(report['outputs'])} direct byte matches; "
          f"{report['windows_json_lf_matches']} Windows JSON LF-compatible matches", flush=True)
    print(f"summary SHA-256: {report['summary_sha256']}", flush=True)
    print(f"period_summary SHA-256: {report['period_summary_sha256']}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / ".local")
    parser.add_argument("--strict-bytes", action="store_true", help="Reject all output byte differences, including Windows JSON CRLF")
    args = parser.parse_args()
    output_parent = args.output_dir.resolve()
    if output_parent == ROOT or output_parent.is_relative_to(LAB) or output_parent.is_relative_to(ROOT / "docs"):
        parser.error("Choose an output directory outside imported sources and repository documentation")
    output_parent.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix="verification-", dir=output_parent))
    report = {
        "python": sys.version, "platform": platform.platform(), "strict_bytes": args.strict_bytes,
        "run_directory": str(run_dir), "status": "failed", "checks": [], "outputs": [],
    }
    print(f"Python: {sys.version}; evidence: {run_dir}", flush=True)
    started = time.perf_counter()
    try:
        verify(run_dir, report, args.strict_bytes)
        report["status"] = "passed"
        return 0
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        report["error"] = str(error)
        print(f"FAILED: {error}", file=sys.stderr, flush=True)
        return 1
    finally:
        report["elapsed_seconds"] = time.perf_counter() - started
        write_record(run_dir / "verification.json", report)
        print(f"Verification {report['status']}: {run_dir / 'verification.json'}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
