from __future__ import annotations

import runpy
from pathlib import Path

bootstrap = Path(__file__).with_name("pr58_spatial_worker_bootstrap.py")
text = bootstrap.read_text(encoding="utf-8")
old = '    pattern = re.compile(rf"(?ms)^func {re.escape(name)}\\\\b.*?(?=^func |\\\\Z)")'
new = '    pattern = re.compile(rf"(?ms)^func {re.escape(name)}\\b.*?(?=^func |\\Z)")'
if old not in text:
    raise RuntimeError("bootstrap matcher line not found")
bootstrap.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
runpy.run_path(str(bootstrap), run_name="__main__")

fast_query = Path(__file__).with_name("pr58_spatial_effective_capacity_query.py")
runpy.run_path(str(fast_query), run_name="__main__")
