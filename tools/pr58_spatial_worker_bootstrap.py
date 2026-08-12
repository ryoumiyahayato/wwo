from __future__ import annotations

import runpy
from pathlib import Path

worker = Path(__file__).with_name("pr58_spatial_capacity_integration_worker.py")
text = worker.read_text(encoding="utf-8")
old = 'pattern = re.compile(rf"(?ms)^func {re.escape(name)}\\b.*?(?=^func |\\Z)")'
new = 'pattern = re.compile(rf"(?ms)^(?:static )?func {re.escape(name)}\\b.*?(?=^(?:static )?func |\\Z)")'
if old not in text:
    raise RuntimeError("worker function-boundary pattern not found")
worker.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
runpy.run_path(str(worker), run_name="__main__")
