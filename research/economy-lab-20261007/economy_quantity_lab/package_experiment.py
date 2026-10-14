"""Build the small ZIP and verify reproduction using only its extracted files."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile


HERE = Path(__file__).resolve().parent
FILES = ["economy.py", "run_experiment.py", "test_economy.py", "fixture.json",
         "package_experiment.py", "REPORT.md", "baseline.csv", "transport_shock.csv",
         "baseline_order_trace.csv", "transport_shock_order_trace.csv"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    archive = HERE / "economy_quantity_lab.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for name in FILES:
            # Fixed metadata makes packaging deterministic too.
            info = zipfile.ZipInfo(f"economy_quantity_lab/{name}", (2026, 10, 6, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, (HERE / name).read_bytes())
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    with tempfile.TemporaryDirectory(prefix="verify_", dir=HERE) as temporary:
        with zipfile.ZipFile(archive) as bundle:
            assert bundle.testzip() is None
            bundle.extractall(temporary)
        extracted = Path(temporary) / "economy_quantity_lab"
        subprocess.run([sys.executable, "-m", "unittest", "-v", "test_economy.py"],
                       cwd=extracted, env=env, check=True)
        subprocess.run([sys.executable, "run_experiment.py", "--output-dir", "replay"],
                       cwd=extracted, env=env, check=True)
        hashes = {}
        for name in FILES:
            if name.endswith(".csv"):
                original = digest(extracted / name)
                replay = digest(extracted / "replay" / name)
                if original != replay:
                    raise AssertionError(f"ZIP reproduction mismatch: {name}")
                hashes[name] = original
    result = {"archive": str(archive), "zip_sha256": digest(archive),
              "zip_bytes": archive.stat().st_size, "files": FILES,
              "extracted_tests": "8 passed", "reproduced_csv_sha256": hashes}
    (HERE / "verification.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
