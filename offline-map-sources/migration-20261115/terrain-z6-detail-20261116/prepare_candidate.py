import importlib.util
import json
import os
from pathlib import Path

import numpy as np
import zstandard
from PIL import Image


STAGE = Path(__file__).resolve().parent
MIGRATION = STAGE.parent
BASE = MIGRATION / 'terrain-quality-20261115/recovered-candidate/worldcrs84quad-15s-v2'
Z7 = MIGRATION / 'terrain-z7-detail-20261116/candidate-final'
CANDIDATE = STAGE / os.environ.get('WWO_Z6_WORKING', 'candidate-final')
BEFORE = STAGE / 'baseline-with-z7'
SCRIPT = Path('D:/programs/WWO/wwo-character-integration/rust/strategic-host/tools/build_natural_terrain.py')
spec = importlib.util.spec_from_file_location('terrain', SCRIPT)
terrain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(terrain)


class ComparedZ6(terrain.LevelPack):
    def __init__(self, file, original):
        super().__init__(file, 6, terrain.COMPACT_VERSION)
        self.original = terrain.LevelPack(original, 6, terrain.COMPACT_VERSION)
        self.decode = zstandard.ZstdDecompressor()
        self.changed = 0
        self.corners = 0
        self.height_frames = 0
        self.before = self.row = None

    def at(self, x, y):
        ncolor, nheight = self.frame_sizes(x, y)
        color, height = self.file.read(ncolor), self.file.read(nheight)
        old_ncolor, old_nheight = self.original.frame_sizes(x, y)
        old_color = self.original.file.read(old_ncolor)
        old_height = self.original.file.read(old_nheight)
        if old_height != height:
            raise ValueError(f'Height frame changed at Z6/{x}/{y}')
        self.height_frames += 1
        tile = super().at(x, y)
        if color != old_color:
            dim = terrain.TILE + 2 * terrain.GUTTER
            alphas = [Image.frombytes('RGBA', (dim, dim), raw, 'bcn', (7, 'BC7')).getchannel('A').tobytes()
                      for raw in (self.decode.decompress(old_color, max_output_size=dim**2), tile[0].tobytes())]
            if alphas[0] != alphas[1]:
                raise ValueError(f'Water coverage changed at Z6/{x}/{y}')
            self.changed += 1
        if x == 0:
            self.before, self.row = self.row, []
        if self.before is not None:
            for dx in (-1, 1):
                neighbour = self.before[(x + dx) % self.nx]
                for current, previous, gutter in zip(tile, neighbour, (2, 8)):
                    column = slice(0, gutter) if dx < 0 else slice(-gutter, None)
                    other = slice(-gutter, None) if dx < 0 else slice(0, gutter)
                    if not np.array_equal(current[:gutter, column], previous[:, other]):
                        raise ValueError(f'Diagonal mismatch at Z6/{x}/{y} toward {dx}')
                self.corners += 1
        self.row.append(tuple(blocks[-gutter:, :].copy() for blocks, gutter in zip(tile, (2, 8))))
        return tile


with (CANDIDATE / '6.qpk').open('rb') as candidate, (BASE / '6.qpk').open('rb') as original, (BASE / '5.qpk').open('rb') as parent:
    compared = ComparedZ6(candidate, original)
    inventory = terrain.packed_edges(compared, terrain.LevelPack(parent, 5, terrain.COMPACT_VERSION))
    proof = dict(inventory, identical_compressed_height_frames=compared.height_frames,
                 decoded_alpha_exact_tiles=compared.height_frames, modified_color_frames=compared.changed,
                 diagonal_relationships=compared.corners)
print(json.dumps(proof), flush=True)
(STAGE / 'z6-global.json').write_text(json.dumps(proof, indent=2) + '\n', encoding='utf-8')


def assemble(directory, candidate):
    directory.mkdir(exist_ok=True)
    manifest = json.loads((Z7 / 'index.json').read_text(encoding='utf-8'))
    for level in range(8):
        name = f'{level}.qpk'
        if level != 6 or not candidate:
            os.link((Z7 if level == 7 else BASE) / name, directory / name)
    os.link(BASE / 'river-topology.u32', directory / 'river-topology.u32')
    if candidate:
        manifest['levels'][6] = inventory
        manifest['surface_revisions'] = {
            '6': {'level': 6, 'id': 'SCAR-ADD-7.13-z6-v1', 'source': manifest['surface_revision']['source'],
                  'epochs': 'modern reference; not the boundaries in 1900', 'raster': '2x2 in EPSG:3031',
                  'physical_water_coverage': 'identical decoded BC7 alpha to original Z6'},
            '7': manifest['surface_revision'],
        }
    (directory / 'index.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


if not (BEFORE / 'index.json').is_file():
    assemble(BEFORE, candidate=False)
assemble(CANDIDATE, candidate=True)
