"""Build independently readable WWOCM2 pages from admitted relief assets."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
import json
from pathlib import Path
import struct
import zlib

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/maps/compact/relief"


def webp(image):
    stream = BytesIO()
    image.save(stream, "WEBP", lossless=True, quality=65, method=3, exact=True)
    return stream.getvalue()


def regenerate_mips(raw, width, height):
    import numpy as np

    offset = width * height * 4
    prior = np.frombuffer(raw, dtype=np.uint8, count=offset).reshape(height, width, 4)
    base = webp(Image.fromarray(prior))
    with Image.open(BytesIO(base)) as decoded:
        if decoded.convert("RGBA").tobytes() != raw[:offset]:
            raise ValueError("Lossless base comparison failed")
    corrections = bytearray()
    while width != 1 or height != 1:
        w, h = max(1, width // 2), max(1, height // 2)
        # Godot's RGBA8 mip filter averages the top-left 2x2 samples and
        # repeats the sole row/column when a dimension has reached one.
        rows = np.minimum(np.arange(h * 2), height - 1)
        columns = np.minimum(np.arange(w * 2), width - 1)
        samples = prior[np.ix_(rows, columns)].astype(np.uint16)
        predicted = ((samples[::2, ::2] + samples[1::2, ::2] +
                      samples[::2, 1::2] + samples[1::2, 1::2] + 2) // 4).astype(np.uint8)
        count = w * h * 4
        actual = np.frombuffer(raw, dtype=np.uint8, count=count, offset=offset).reshape(h, w, 4)
        delta = (actual - predicted).ravel()
        positions = np.flatnonzero(delta)
        gaps = np.diff(positions, prepend=-1)
        if np.any(gaps > 0xFFFFFF):
            raise ValueError("Mip correction gap exceeds the page index range")
        words = (gaps.astype(np.uint32) << 8) | delta[positions]
        corrections.extend(struct.pack("<I", len(words)))
        corrections.extend(words.astype("<u4", copy=False).tobytes())
        prior = actual
        width, height = w, h
        offset += count
    if offset != len(raw):
        raise ValueError("Unexpected mip-chain length")
    packed = zlib.compress(corrections, 6)
    return base + packed, {
        "base": [0, len(base), "webp-rgba8-base"],
        "mip_corrections": [len(base), len(packed), "zlib-sparse-box-rgba8", len(corrections)],
    }


def encode(asset, previous, output=OUTPUT, predict_mips=False):
    source = asset["path"].removeprefix("res://")
    original = (ROOT / source).read_bytes()
    width, height, size = struct.unpack_from("<III", original, 8)
    if original[:8] != b"FRT42\0\0\0" or (width, height, size) != (
        asset["width"], asset["height"], asset["decoded_bytes"]
    ):
        raise ValueError(f"Invalid relief source {source}")
    raw = zlib.decompress(original[20:])
    if len(raw) != size:
        raise ValueError(f"Invalid mip length for {source}")

    reference = previous.get(asset["path"])
    if reference and reference["chosen_format"] == "RGBA8_MIP_FRA0":
        encoded = (ROOT / reference["candidate_path"]).read_bytes()
        if encoded[:10] != b"FRA0\0\0\0\0\x01\x05":
            raise ValueError(f"Expected a lossless WebP reference for {source}")
        payload = encoded[28:]
    else:
        flat_height = (size + 4 * width - 1) // (4 * width)
        image = Image.frombytes("RGBA", (width, flat_height), raw.ljust(width * flat_height * 4, b"\0"))
        payload = webp(image)
    with Image.open(BytesIO(payload)) as image:
        if image.convert("RGBA").tobytes()[:size] != raw:
            raise ValueError(f"Lossless mip comparison failed for {source}")

    meta = dict(kind="relief-page", source=source, width=width, height=height, decoded_bytes=size)
    def package(data, blocks):
        header = json.dumps(dict(meta=meta, blocks=blocks), separators=(",", ":")).encode("utf-8")
        return b"WWOCM2\0\0" + struct.pack("<I", len(header)) + header + data

    result = package(payload, {"mips": [0, len(payload), "webp-rgba8-mips"]})
    if predict_mips and (width != 1 or height != 1):
        predicted = package(*regenerate_mips(raw, width, height))
        if len(predicted) < len(result):
            result = predicted
    if len(result) >= len(original):
        return len(original), len(original), 0
    destination = output / (Path(source).stem + ".wcm")
    temporary = destination.with_suffix(".tmp")
    temporary.write_bytes(result)
    temporary.replace(destination)
    return len(original), len(result), 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalogue", type=Path, required=True)
    parser.add_argument("--prefix", action="append", required=True)
    parser.add_argument("--fra0-manifest", type=Path)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--regenerate-mips", action="store_true", help="Store the base level and exact corrections to native box mips when smaller")
    args = parser.parse_args()
    doc = json.loads(args.catalogue.read_text(encoding="utf-8"))
    assets = {}
    for fact in doc["evidence_catalog"]["facts"]:
        for asset in fact["value"].get("assets", []):
            if asset["format"] == "RGBA8_MIP_DEFLATE" and Path(asset["path"]).name.startswith(tuple(args.prefix)):
                assets[asset["path"]] = asset
    if not assets:
        parser.error("No admitted pages match the requested prefixes")
    previous = {}
    if args.fra0_manifest is not None:
        manifest = json.loads(args.fra0_manifest.read_text(encoding="utf-8"))
        previous = {row["asset"]["path"]: row for row in manifest["files"]}
    args.output.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        totals = list(pool.map(lambda asset: encode(asset, previous, args.output, args.regenerate_mips), assets.values()))
    before, after, converted = map(sum, zip(*totals))
    print(f"pages={len(assets)} converted={converted} original={before} installed={after} saved={before-after}")


if __name__ == "__main__":
    main()
