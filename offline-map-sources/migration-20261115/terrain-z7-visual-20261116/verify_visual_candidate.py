import importlib.util
import json
import os
from pathlib import Path
import numpy as np
from PIL import Image
from zstandard import ZstdDecompressor

stage = Path(__file__).resolve().parent
migration = stage.parent
original = migration/"terrain-quality-20261115/recovered-candidate/worldcrs84quad-15s-v2"
z6 = migration/"terrain-z6-detail-20261116/candidate-z6-v2"
previous = migration/"terrain-z7-detail-20261116/candidate-final"
candidate = stage/"candidate"
source = migration.parents[1]/"wwo-character-integration/rust/strategic-host/tools/build_natural_terrain.py"
spec = importlib.util.spec_from_file_location("terrain", source)
terrain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(terrain)
coverage_changes = []
changed_vs_previous = []
original_edits = []
checked = 0
decode = ZstdDecompressor()
dim = terrain.TILE+2*terrain.GUTTER

def alpha(frame):
    pixels = decode.decompress(frame, max_output_size=dim**2)
    return Image.frombytes("RGBA", (dim,dim), pixels, "bcn", (7,"BC7")).getchannel("A").tobytes()

def record(pack,x,y):
    ncolor,nheight = pack.frame_sizes(x,y)
    return pack.file.read(ncolor),pack.file.read(nheight)

class Compared(terrain.LevelPack):
    def at(self,x,y):
        global checked
        color,height = record(self,x,y)
        oldc,oldh = record(base,x,y)
        priorc,_ = record(prior,x,y)
        if height != oldh:
            raise ValueError(f"Changed height frame: 7/{x}/{y}")
        if color != oldc:
            if alpha(color) != alpha(oldc):
                raise ValueError(f"Changed decoded water coverage: 7/{x}/{y}")
            original_edits.append((x,y))
        if color != priorc:
            changed_vs_previous.append((x,y))
        if priorc != oldc and alpha(priorc) != alpha(oldc):
            coverage_changes.append((x,y))
        checked += 1
        return super().at(x,y)

with (candidate/"7.qpk").open("rb") as result, (original/"7.qpk").open("rb") as raw, (previous/"7.qpk").open("rb") as before, (z6/"6.qpk").open("rb") as parent:
    base = terrain.LevelPack(raw,7,terrain.COMPACT_VERSION)
    prior = terrain.LevelPack(before,7,terrain.COMPACT_VERSION)
    inventory = terrain.packed_edges(Compared(result,7,terrain.COMPACT_VERSION),terrain.LevelPack(parent,6,terrain.COMPACT_VERSION))
proof = dict(inventory, identical_compressed_height_frames=checked,
             decoded_alpha_exact_tiles=checked, modified_color_frames=len(original_edits),
             pr152_coverage_change_tiles=len(coverage_changes), changed_vs_pr152=len(changed_vs_previous),
             modified_z7_xy=original_edits, changed_vs_pr152_xy=changed_vs_previous)
(stage/"z7-visual-global.json").write_text(json.dumps(proof, separators=(",",":"))+"\n",encoding="utf-8")
for folder, selected in ((candidate, candidate), (stage/"before-with-z6", previous)):
    folder.mkdir(exist_ok=True)
    for name in [f"{level}.qpk" for level in range(7)]+["river-topology.u32"]:
        os.link(z6/name, folder/name)
    if selected != candidate:
        os.link(selected/"7.qpk", folder/"7.qpk")
    index = json.loads((z6/"index.json").read_text(encoding="utf-8"))
    if selected == candidate:
        index["levels"][7] = inventory
        index["surface_revisions"]["7"].update(
            id="SCAR-ADD-7.13-z7-v3", raster="4x4 EPSG:3031 subpixel coverage",
            edge_rgb="replace the original ocean contribution; preserve exact decoded BC7 alpha",
            grounding_reconciliation_metres=15_000, epochs="modern reference")
        index["surface_revision"]=index["surface_revisions"]["7"]
    (folder/"index.json").write_text(json.dumps(index, indent=2, ensure_ascii=False)+"\n",encoding="utf-8")
print({k:v for k,v in proof.items() if not isinstance(v,list)},flush=True)
