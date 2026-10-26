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
TRAINING_ASSET = "wwo-native-training-models-v1.zip"
TRAINING_DEST = ROOT / "military_runtime/native"
TRAINING_RECEIPT = ROOT / "military_runtime/TRAINING_ASSETS.json"
TRAINING_MAX_SIZE = 4 * 1024 * 1024
TRAINING_FILES = {
    "assets/user_derived/models/user_heavy_mbt_aimable.glb": 604496,
    "assets/models/kestrel_scout.glb": 1744900,
    "assets/user_derived/models/user_rifleman_armed.glb": 213244,
    "assets/user_derived/models/user_rifleman_near.glb": 253632,
    "assets/artillery_shell/artillery_shell_lod0.glb": 15060,
    "assets/artillery_shell/artillery_shell_lod1.glb": 5808,
    "cedar/assets/tank_hull_dressing.glb": 10616,
    "cedar/assets/tank_turret_dressing.glb": 8172,
}


def install_terrain(source: Path | None) -> None:
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


def install_training(source: Path | None) -> None:
    """Install only the eight original GLBs; source-delivered JSON is never replaced."""
    receipt_bytes = TRAINING_RECEIPT.read_bytes()
    receipt = json.loads(receipt_bytes)
    rows = receipt.get("files", [])
    files = {item["relative_path"]: int(item["bytes"]) for item in rows}
    if (receipt.get("schema") != "wwo-native-training-models-v1"
            or receipt.get("source_archive_commit") != "3c48266b335cfa448953d26b9698abb6dd207a34"
            or receipt.get("package_filename") != TRAINING_ASSET
            or len(rows) != len(TRAINING_FILES) or files != TRAINING_FILES):
        raise SystemExit("Unexpected training source record or binary whitelist")
    if source is None:
        cache = ROOT / "local-artifacts/native-training-package"
        cache.mkdir(parents=True, exist_ok=True)
        source = cache / TRAINING_ASSET
        if not source.exists():
            subprocess.run(["gh", "release", "download", TAG, "--repo", REPO,
                            "--pattern", TRAINING_ASSET, "--dir", str(cache)], check=True)
    source = source.resolve(strict=True)
    if source.stat().st_size > TRAINING_MAX_SIZE:
        raise SystemExit("Training attachment exceeds the explicit 4 MiB ZIP budget")
    installed = reused = 0
    with zipfile.ZipFile(source) as package:
        entries = package.infolist()
        allowed = set(TRAINING_FILES) | {"TRAINING_ASSETS.json", "README.md"}
        names = {item.filename for item in entries}
        if (len(entries) != len(allowed) or names != allowed
                or any(item.is_dir() or item.flag_bits & 1 for item in entries)
                or sum(item.file_size for item in entries) > TRAINING_MAX_SIZE):
            raise SystemExit("Unexpected training paths, duplicates, encryption or decompressed size")
        # Source checkout line endings may differ; provenance is parsed JSON.
        # Original GLB payload comparisons below remain exact byte-for-byte.
        if json.loads(package.read("TRAINING_ASSETS.json")) != receipt:
            raise SystemExit("Training attachment provenance differs from source-delivered record")
        base = TRAINING_DEST.resolve()
        if not base.is_relative_to(ROOT.resolve()):
            raise SystemExit("Training destination escapes the project namespace")
        pending = []
        # Preflight the complete fixed set with direct bytes before any creation.
        # Package metadata is read-only; the nine native JSON files stay in source.
        for item in entries:
            if item.filename not in TRAINING_FILES:
                continue
            target = (base / item.filename).resolve()
            if not target.is_relative_to(base):
                raise SystemExit("Unsafe training archive path")
            if item.file_size != TRAINING_FILES[item.filename]:
                raise SystemExit(f"Original training byte count differs: {item.filename}")
            data = package.read(item)
            if target.exists():
                if target.read_bytes() != data:
                    raise SystemExit(f"Existing training file differs; not overwritten: {target}")
                reused += 1
                continue
            pending.append((target, data))
        for target, data in pending:
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                with target.open("xb") as output:
                    output.write(data)
            except FileExistsError:
                if target.read_bytes() != data:
                    raise SystemExit(f"Existing training file differs; not overwritten: {target}")
                reused += 1
            else:
                installed += 1
    print(f"Native training originals: {len(TRAINING_FILES)} ({sum(TRAINING_FILES.values()):,} bytes) at {TRAINING_DEST}")
    print(f"Installed: {installed}; reused byte-for-byte: {reused}; no existing files overwritten.")
    print("Original GLB bytes only. Native JSON remains source-delivered; formal world/save data is untouched.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--from-zip", type=Path, help="Use an already downloaded terrain resource attachment")
    parser.add_argument("--with-training", action="store_true",
                        help="Also install the original native training models from the same draft tag")
    parser.add_argument("--training-from-zip", type=Path,
                        help="Install native training models from a local ZIP; alone skips terrain download")
    args = parser.parse_args()
    # Existing no-argument / --from-zip usage retains exactly the terrain path.
    # A lone local training package must not cause an unrelated terrain download.
    training_only = args.training_from_zip is not None and args.from_zip is None and not args.with_training
    if not training_only:
        install_terrain(args.from_zip)
    if args.with_training or args.training_from_zip is not None:
        install_training(args.training_from_zip)


if __name__ == "__main__":
    main()
