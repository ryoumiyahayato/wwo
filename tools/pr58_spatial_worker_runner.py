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

for helper_name in [
    "pr58_spatial_effective_capacity_query.py",
    "pr58_spatial_batch_extension.py",
    "pr58_spatial_batch_query_extension.py",
    "pr58_spatial_batch_result_optimization.py",
]:
    helper = Path(__file__).with_name(helper_name)
    runpy.run_path(str(helper), run_name="__main__")
