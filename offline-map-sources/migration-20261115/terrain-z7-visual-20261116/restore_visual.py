import importlib.util
from pathlib import Path
import gzip

root=Path(__file__).resolve().parent
previous=root.with_name("terrain-z6-detail-20261116")/"review_release.py"
spec=importlib.util.spec_from_file_location("release",previous)
release=importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
release.restored=root/"restored-release"
release.restored.mkdir(exist_ok=True)
release.qpk_samples("z7-visual-7.qpk",root/"candidate/7.qpk",
                    [(0,0),(93,15),(129,40),(171,76),(180,113),(1,119),(94,121),(11,123),(255,127)])
for local in sorted((root/"archive").glob("z7-visual-*")):
    if local.name.endswith(".qpk") or local.name not in release.assets:
        continue
    payload=release.get(local.name)
    assert payload==local.read_bytes(),local.name
    print("restored",local.name,len(payload),flush=True)
source=release.get("z7-detail-scar-add-7.13.json.gz")
(release.restored/"scar-add.json").write_bytes(gzip.decompress(source))
print("restored SCAR ADD input",len(source),flush=True)
