#!/usr/bin/env python3
"""Compare Batch 4 generator outputs across clean directories."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "tools" / "historical_data" / "build_1900_source_pack_batch4.py"
COMMITTED = ROOT / "data" / "staging" / "1900"
OUTPUTS = ["batch4_coverage_review_queue.json", "batch4_deterministic_corpus.json", "batch4_manifest.json"]


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="wwo-1900-batch4-a-") as first_name, tempfile.TemporaryDirectory(prefix="wwo-1900-batch4-b-") as second_name:
        first = Path(first_name)
        second = Path(second_name)
        for output in (first, second):
            result = subprocess.run([sys.executable, str(GENERATOR), "--output-dir", str(output)], cwd=ROOT, capture_output=True, text=True, check=False)
            if result.returncode != 0:
                raise RuntimeError(f"Batch 4 generator failed: {result.stdout}\n{result.stderr}")
        for name in OUTPUTS:
            first_bytes = (first / name).read_bytes()
            second_bytes = (second / name).read_bytes()
            committed_bytes = (COMMITTED / name).read_bytes()
            if first_bytes != second_bytes:
                raise RuntimeError(f"non-deterministic Batch 4 output: {name}")
            if first_bytes != committed_bytes:
                raise RuntimeError(f"committed Batch 4 output differs from clean generation: {name}")
    corpus = json.loads((COMMITTED / "batch4_deterministic_corpus.json").read_text(encoding="utf-8"))
    print(json.dumps({"ok": True, "outputs_compared": OUTPUTS, "expected_queue_sha256": corpus["expected_queue_sha256"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
