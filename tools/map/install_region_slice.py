"""Install the versioned minimal military training art, not a game build.

Uses the existing authenticated WWO draft resource archive. No world/save data,
full military runtime, fingerprints, or global terrain downloads are involved.
Python 3 stdlib and the already authenticated GitHub CLI are sufficient.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets/terrain/region_slice"
ASSET = "wwo-region-slice-ridgevale-v1.zip"
TAG = "untagged-75a9dbc800223cbf8a18"
REPO = "ryoumiyahayato/wwo"
MAX_SIZE = 20 * 1024 * 1024


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--from-zip", type=Path, help="Use an already downloaded resource attachment")
    args = parser.parse_args()
    source = args.from_zip
    if source is None:
        cache = ROOT / "local-artifacts/region-resource-download"
        cache.mkdir(parents=True, exist_ok=True)
        source = cache / ASSET
        if not source.exists():
            subprocess.run(["gh", "release", "download", TAG, "--repo", REPO,
                            "--pattern", ASSET, "--dir", str(cache)], check=True)
    source = source.resolve(strict=True)
    if source.stat().st_size > MAX_SIZE:
        raise SystemExit("Resource attachment exceeds the explicit 20 MiB budget")
    installed = reused = 0
    with zipfile.ZipFile(source) as package:
        entries = package.infolist()
        if len(entries) > 64 or sum(item.file_size for item in entries) > MAX_SIZE:
            raise SystemExit("Unexpected resource scope or decompressed size")
        names = {item.filename for item in entries}
        if len(names) != len(entries) or any(item.is_dir() for item in entries):
            raise SystemExit("Attachment contains duplicate entries or directory records")
        if "RECOVERY_SOURCE.json" not in names:
            raise SystemExit("The original resource source record is missing")
        receipt = json.loads(package.read("RECOVERY_SOURCE.json"))
        # These are the original record's real top-level and files[] field names.
        if receipt.get("source_archive_commit") != "3c48266b335cfa448953d26b9698abb6dd207a34":
            raise SystemExit("Unexpected source archive version")
        files = {item["relative_path"]: int(item["bytes"]) for item in receipt["files"]}
        allowed = set(files) | {"README.md", "RECOVERY_SOURCE.json"}
        if names != allowed:
            raise SystemExit("Attachment contains unexpected or missing entries")
        base = DEST.resolve()
        pending = []
        # Read and compare all destinations before creating anything. No digests.
        for item in entries:
            target = (base / item.filename).resolve()
            if not target.is_relative_to(base):
                raise SystemExit("Unsafe archive path")
            if item.filename in files and item.file_size != files[item.filename]:
                raise SystemExit(f"Source byte count differs: {item.filename}")
            data = package.read(item)
            if target.exists():
                if target.read_bytes() != data:
                    raise SystemExit(f"Existing file differs; not overwritten: {target}")
                if item.filename in files:
                    reused += 1
                continue
            pending.append((item.filename, target, data))
        for name, target, data in pending:
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                # Exclusive creation also refuses a file appearing after comparison.
                with target.open("xb") as output:
                    output.write(data)
            except FileExistsError:
                if target.read_bytes() != data:
                    raise SystemExit(f"Existing file differs; not overwritten: {target}")
                if name in files:
                    reused += 1
            else:
                if name in files:
                    installed += 1
    print(f"Original assets: {len(files)} ({sum(files.values()):,} bytes) at {DEST}")
    print(f"Installed: {installed}; reused byte-for-byte: {reused}; no existing files overwritten.")
    print("Fictional training/observation assets for local terrain walking, not a full military runtime.")


if __name__ == "__main__":
    main()
