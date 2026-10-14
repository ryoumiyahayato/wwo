"""Portable package, original preservation, clean entrypoint and byte replay checks."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
import time
import zipfile

HERE = Path(__file__).resolve().parent
ORIGINAL = HERE.parent
BASE_FILES = ["economy.py", "fixture.json", "test_economy.py", "run_experiment.py",
              "package_experiment.py", "REPORT.md", "baseline.csv", "transport_shock.csv",
              "baseline_order_trace.csv", "transport_shock_order_trace.csv"]
ROUND_FILES = ["inventory_policy.py", "run_inventory_comparison.py", "test_inventory_comparison.py",
               "package_inventory_comparison.py", "INVENTORY_COMPARISON_REPORT.md", "provenance.json",
               "input_access.json", "execution_log.json"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def preserved_originals():
    provenance = json.loads((HERE / "provenance.json").read_text(encoding="utf-8"))
    for name, expected in provenance["original_file_sha256"].items():
        # Prior upload receipts/archive are provenance, not runtime dependencies.
        # Verify them whenever present in the source executor; the portable bundle
        # includes the ten required baseline files, whose hashes are mandatory.
        if not (ORIGINAL / name).exists() and name in (
                "delivery.json", "verification.json", "economy_quantity_lab.zip"):
            continue
        if sha(ORIGINAL / name) != expected:
            raise AssertionError(f"protected original changed: {name}")
    return provenance


def execute(command, cwd, env, checks, name):
    started = time.perf_counter()
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    checks.append({"name": name, "command": ["python3", *command[1:]], "exit_code": result.returncode,
                   "elapsed_seconds": time.perf_counter() - started,
                   "stdout": result.stdout, "stderr": result.stderr})
    if result.returncode:
        raise RuntimeError(f"{name} failed: {result.stdout}\n{result.stderr}")
    print(f"{name}: passed")


def compare_tree(expected, replay):
    files = sorted(p.relative_to(expected) for p in expected.rglob("*") if p.is_file())
    reproduced = sorted(p.relative_to(replay) for p in replay.rglob("*") if p.is_file())
    if files != reproduced:
        raise AssertionError("replay output file set differs")
    result = {}
    for name in files:
        actual, regenerated = sha(expected / name), sha(replay / name)
        if actual != regenerated:
            raise AssertionError(f"reproduction mismatch: {name}")
        result[str(name)] = actual
    return result


def main():
    started = time.perf_counter()
    provenance = preserved_originals()
    archive = HERE / "inventory_comparison_round2.zip"
    payload = [(f"economy_quantity_lab/{name}", ORIGINAL / name) for name in BASE_FILES]
    payload += [(f"economy_quantity_lab/inventory_round2/{name}", HERE / name) for name in ROUND_FILES]
    for subtree in ("inputs", "inventory_comparison_results"):
        payload += [(f"economy_quantity_lab/inventory_round2/{p.relative_to(HERE).as_posix()}", p)
                    for p in sorted((HERE / subtree).rglob("*")) if p.is_file()]
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for name, path in payload:
            info = zipfile.ZipInfo(name, (2026, 10, 7, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, path.read_bytes())
    checks = []
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    with tempfile.TemporaryDirectory(prefix="clean_verify_", dir=HERE) as temporary:
        with zipfile.ZipFile(archive) as bundle:
            if bundle.testzip() is not None:
                raise AssertionError("ZIP CRC check")
            names = set()
            for entry in bundle.infolist():
                path = PurePosixPath(entry.filename)
                if path.is_absolute() or ".." in path.parts or "\\" in entry.filename or entry.filename in names:
                    raise AssertionError("unsafe/duplicate ZIP path")
                if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise AssertionError("ZIP symlink")
                names.add(entry.filename)
            bundle.extractall(temporary)
        extracted = Path(temporary) / "economy_quantity_lab"
        round_dir = extracted / "inventory_round2"
        for name in BASE_FILES:
            if sha(extracted / name) != provenance["original_file_sha256"][name]:
                raise AssertionError(f"packaged original hash: {name}")
        execute([sys.executable, "-m", "unittest", "-v", "test_economy.py"], extracted, env, checks, "original 8 checks")
        execute([sys.executable, "run_experiment.py", "--output-dir", "replay200"], extracted, env, checks, "original entrypoint")
        original_replay_hashes = {}
        for name in BASE_FILES:
            if name.endswith(".csv"):
                if sha(extracted / name) != sha(extracted / "replay200" / name):
                    raise AssertionError(f"original CSV mismatch: {name}")
                original_replay_hashes[name] = sha(extracted / name)
        execute([sys.executable, "-m", "unittest", "-v", "test_inventory_comparison.py"],
                round_dir, env, checks, "new 9 checks")
        execute([sys.executable, "run_inventory_comparison.py", "--output-dir", "replay600"],
                round_dir, env, checks, "all 33 clean-entrypoint runs")
        reproduction = compare_tree(round_dir / "inventory_comparison_results", round_dir / "replay600")
    preserved_originals()
    verification = {"archive": str(archive), "zip_bytes": archive.stat().st_size, "zip_sha256": sha(archive),
                    "payload_file_count": len(payload), "protected_originals_preserved": True,
                    "original_csv_sha256": original_replay_hashes,
                    "reproduced_result_sha256": reproduction, "checks": checks,
                    "elapsed_seconds": time.perf_counter() - started}
    (HERE / "package_verification.json").write_text(json.dumps(verification, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in verification.items() if k not in ("checks", "reproduced_result_sha256")}, indent=2))
    print(f"All {len(reproduction)} result files reproduced byte-for-byte.")


if __name__ == "__main__":
    main()
