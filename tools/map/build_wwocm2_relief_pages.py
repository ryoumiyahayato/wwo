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


def encode(asset, previous):
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
        stream = BytesIO()
        image.save(stream, "WEBP", lossless=True, quality=65, method=3, exact=True)
        payload = stream.getvalue()
    with Image.open(BytesIO(payload)) as image:
        if image.convert("RGBA").tobytes()[:size] != raw:
            raise ValueError(f"Lossless mip comparison failed for {source}")

    meta = dict(kind="relief-page", source=source, width=width, height=height, decoded_bytes=size)
    header = json.dumps(dict(meta=meta, blocks={"mips": [0, len(payload), "webp-rgba8-mips"]}),
                        separators=(",", ":")).encode("utf-8")
    result = b"WWOCM2\0\0" + struct.pack("<I", len(header)) + header + payload
    if len(result) >= len(original):
        return len(original), len(original), 0
    destination = OUTPUT / (Path(source).stem + ".wcm")
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
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        totals = list(pool.map(lambda asset: encode(asset, previous), assets.values()))
    before, after, converted = map(sum, zip(*totals))
    print(f"pages={len(assets)} converted={converted} original={before} installed={after} saved={before-after}")


if __name__ == "__main__":
    main()
