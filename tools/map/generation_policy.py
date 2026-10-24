"""CLI-only opt-in for old geographic producers. No asset reads or hashes."""
import json
from pathlib import Path
import sys


def require_inputs(root, paths, consumer):
    """Check declared local inputs before a producer can replace an asset.

    No name-based substitutions or automatic downloads. Metadata/precision
    validation remains the producer's responsibility after files are restored.
    """
    root = Path(root).resolve()
    missing = []
    for value in dict.fromkeys(str(p) for p in paths):
        path = Path(value.replace('\\', '/'))
        path = path if path.is_absolute() else root/path
        resolved = path.resolve()
        if not resolved.is_relative_to(root):
            raise ValueError(f'{consumer}: undeclared external input {value}')
        if not resolved.is_file():
            missing.append(value)
    if missing:
        short = '; '.join(missing[:4])
        raise FileNotFoundError(f'{consumer}: {len(missing)} declared inputs missing: {short}. No coarse replacement or download was started.')


def enter(root, catalog):
    explicit = "--rebuild" in sys.argv or any(v.startswith(("--refresh", "--acquire")) for v in sys.argv)
    if not explicit:
        path = Path(root) / "data/presentation" / catalog
        if not path.is_file():
            raise SystemExit("No catalogue: declare a bounded recipe and explicit --rebuild first")
        doc = json.loads(path.read_text(encoding="utf-8"))
        missing = 0
        for fact in doc.get("evidence_catalog", {}).get("facts", []):
            for a in fact.get("value", {}).get("assets", []):
                if a.get("surface_role") in {"base", "detail"} and not (Path(root) / a["path"].removeprefix("res://")).is_file():
                    missing += 1
        if missing:
            raise SystemExit(f"{missing} catalogue inputs missing; do not redownload/rebuild automatically")
        print("Existing catalogue retained; no preparation requested. Use an incremental build recipe for changed inputs.")
        raise SystemExit(0)
    budget = next((int(v.split("=", 1)[1]) for v in sys.argv if v.startswith("--temporary-budget-mib=")), None)
    if budget is None or budget < 0:
        raise SystemExit("Declare --temporary-budget-mib=N before preparation; no source was downloaded")
    if budget > 1024 and "--allow-large-preparation" not in sys.argv:
        raise SystemExit("Temporary estimate exceeds1GiB; separate explicit authorization is required")
