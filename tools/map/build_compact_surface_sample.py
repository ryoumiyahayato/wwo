"""Finite A3 sample from explicitly captured existing surface consumers.

No acquisition, catalogue rewrite, deletion, resolution change or global rebuild.
The coefficients represent observed display colour, not measured heights/classes.
"""
import argparse
import json
from pathlib import Path
import struct
import zlib

import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def read_asset(asset):
    path = ROOT / asset['path'].removeprefix('res://')
    data = path.read_bytes()
    width, height, length = struct.unpack('<III', data[8:20])
    raw = zlib.decompress(data[20:])
    if data[:5] != b'FRT42' or len(raw) != length:
        raise ValueError('Invalid declared source: ' + str(path))
    return data, width, height, np.frombuffer(raw, dtype=np.uint8).reshape(-1, 4)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    if not out.is_relative_to(ROOT / 'local-artifacts'):
        raise ValueError('Sample outputs must remain outside formal assets')
    baseline = json.loads(args.baseline.read_text(encoding='utf-8'))
    assets = {}
    for case in baseline['cases']:
        for a in case['assets']:
            if a.get('format') == 'RGBA8_MIP_DEFLATE' and a.get('surface_encoding') in (5, 6):
                assets[a['id'].split(':', 1)[1]] = a
    if not assets:
        raise ValueError('No actual RGBA surface consumers in baseline')
    samples = []
    for a in assets.values():
        _, _, _, p = read_asset(a)
        stride = max(1, len(p) // 20000)
        samples.append(p[::stride, :3].astype(np.float64) / 255)
    basis = np.linalg.svd(np.concatenate(samples), full_matrices=False)[2][:2].T
    # One shared colour subspace for all pages/LODs in the finite sample.
    low = np.full(2, np.inf)
    high = np.full(2, -np.inf)
    for a in assets.values():
        _, _, _, p = read_asset(a)
        q = (p[:, :3].astype(np.float32) / 255) @ basis
        low = np.minimum(low, q.min(axis=0))
        high = np.maximum(high, q.max(axis=0))
    scale = np.maximum(high - low, 1e-9)
    out.mkdir(parents=True, exist_ok=True)
    overrides = {}
    stats = []
    optional = []
    for name, a in sorted(assets.items()):
        data, w, h, p = read_asset(a)
        rgb = p[:, :3].astype(np.float32) / 255
        q = rgb @ basis
        encoded = np.empty((len(p), 3), dtype=np.uint8)
        encoded[:, :2] = np.rint(np.clip((q - low) / scale, 0, 1) * 255)
        encoded[:, 2] = p[:, 3]  # Exact original support or independent DEM print.
        decoded = np.clip(((encoded[:, :2].astype(np.float32) / 255) * scale + low) @ basis.T, 0, 1)
        valid = p[:, 3] > (19 if a['surface_encoding'] == 6 else 0)
        error = (decoded[valid] - rgb[valid]) * 255
        path = out / (name + '.rgb.bin')
        raw = encoded.tobytes()
        path.write_bytes(b'FRC38\0\0\0' + struct.pack('<III', w, h, len(raw)) + zlib.compress(raw, 6))
        overrides[name] = dict(path='res://' + path.relative_to(ROOT).as_posix(), format='RGB8_MIP_DEFLATE',
                               decoded_bytes=len(raw), bytes=path.stat().st_size,
                               surface_encoding=7 if a['surface_encoding'] == 5 else 8)
        stats.append(dict(id=name, role=a.get('surface_role'), lod_degrees=a.get('surface_lod_degrees'),
                          source_bytes=len(data), candidate_bytes=path.stat().st_size,
                          source_decoded_bytes=p.size, candidate_decoded_bytes=len(raw),
                          colour_rmse_255=float(np.sqrt(np.mean(error ** 2))),
                          colour_p95_abs_255=float(np.quantile(np.abs(error), .95)),
                          colour_max_abs_255=float(np.max(np.abs(error))),
                          width=w, height=h, same_pixel_grid_and_all_mips=True))
        if a.get('surface_role') == 'detail' and a.get('surface_lod_degrees', 2) == 2:
            optional.append(dict(id=name, path=a['path'], bytes=len(data)))
    config = dict(a3_assets=overrides, b_pack_assets=optional,
                  colour_basis=dict(offset=(basis @ low).tolist(),
                                    axis0=(basis[:, 0] * scale[0]).tolist(),
                                    axis1=(basis[:, 1] * scale[1]).tolist()),
                  stats=stats, scope='Finite existing display data; not a height or land-class reconstruction')
    (out.parent / 'experiment.json').write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(pages=len(stats), source_bytes=sum(x['source_bytes'] for x in stats),
                         candidate_bytes=sum(x['candidate_bytes'] for x in stats), optional_pages=len(optional),
                         worst_page_p95_255=max(x['colour_p95_abs_255'] for x in stats),
                         colour_basis=config['colour_basis']), ensure_ascii=True))


if __name__ == '__main__':
    main()
