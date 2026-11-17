"""Pack local terrain close samples into a terrain-detail-v1.qdt resource."""

import argparse
import json
import os
from pathlib import Path, PureWindowsPath
import re
from shutil import copyfileobj
from struct import Struct

import ispc_texcomp
import numpy as np
from PIL import Image
import zstandard

from build_natural_terrain import COMPACT_STRENGTH, ENCODER, generation_disk_usage


HEADER = Struct("<8sI")
MAGIC = b"WWODTL01"
MAX_INDEX_BYTES = 131_072
MIP_COUNT = 4


def open_sample(path):
    image = Image.open(path, formats=["PNG"])
    if (image.mode != "RGBA" or image.n_frames != 1
            or any(size < 32 or size > 2048 or size % 32 for size in image.size)):
        image.close()
        raise ValueError(f"{path}: expected RGBA PNG with dimensions 32–2048 divisible by 32")
    return image


def read_manifest(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", path.stem):
        raise ValueError(f"{path}: invalid manifest or region ID")
    extent = data.get("extent")
    if (not isinstance(extent, list) or len(extent) != 4
            or any(type(value) not in (int, float) for value in extent)):
        raise ValueError(f"{path}: expected west, south, east, north")
    west, south, east, north = extent
    if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
        raise ValueError(f"{path}: invalid WGS84 extent")

    sources = data.get("sources")
    modern_reference = data.get("modern_reference")
    if (not isinstance(sources, list) or not sources
            or any(not isinstance(source, str) or not source.strip() for source in sources)
            or not isinstance(modern_reference, bool)):
        raise ValueError(f"{path}: expected sources and a modern_reference boolean")

    name = data.get("image")
    if not isinstance(name, str):
        raise ValueError(f"{path}: expected an image path relative to the manifest")
    relative = PureWindowsPath(name)
    if (relative.anchor or ".." in relative.parts or not relative.parts
            or any(":" in part or part.endswith((".", " ")) for part in relative.parts)
            or relative.suffix.lower() != ".png"):
        raise ValueError(f"{path}: unsafe image path")
    parent = path.parent.resolve(strict=True)
    image_path = parent.joinpath(*relative.parts).resolve(strict=True)
    if not image_path.is_relative_to(parent) or not image_path.is_file():
        raise ValueError(f"{path}: image must resolve to a file within the manifest directory")
    with open_sample(image_path) as image:
        size = list(image.size)
    return {
        "id": path.stem,
        "extent": list(map(float, extent)),
        "size": size,
        "offset": 0,
        "bytes": 0,
        "sources": sources,
        "modern_reference": modern_reference,
    }, image_path


def pack_region(image_path, size, compressor):
    with open_sample(image_path) as image:
        if list(image.size) != size:
            raise ValueError(f"{image_path}: image size changed during packing")
        pixels = np.asarray(image)
    blocks = bytearray()
    for level in range(MIP_COUNT):
        height, width = pixels.shape[:2]
        surface = ispc_texcomp.RGBASurface(pixels.tobytes(), width, height)
        blocks.extend(ispc_texcomp.compress_blocks_bc7(surface, ENCODER))
        if level + 1 < MIP_COUNT:
            texels = pixels.reshape(height // 2, 2, width // 2, 2, 4)
            sums = texels.sum(axis=(1, 3), dtype=np.uint16)
            pixels = ((sums + 2) // 4).astype(np.uint8)
    return compressor.compress(blocks)


def index_bytes(regions):
    index = json.dumps({"regions": regions}, ensure_ascii=False, allow_nan=False,
                       separators=(",", ":")).encode("utf-8")
    if len(index) > MAX_INDEX_BYTES:
        raise ValueError("Terrain-detail index exceeds 131072 bytes")
    return index


def write_package(output, manifests):
    if output.exists() or output.is_symlink():
        raise FileExistsError(f"Output already exists: {output}")
    samples = [read_manifest(path) for path in sorted(manifests, key=lambda path: path.stem)]
    regions = [entry for entry, _ in samples]
    if len({entry["id"] for entry in regions}) != len(regions):
        raise ValueError("Duplicate terrain-detail region ID")
    index_bytes(regions)
    raw_bytes = sum(width * height * 85 // 64 for width, height in
                    (entry["size"] for entry in regions))
    estimate = MAX_INDEX_BYTES + 2 * (raw_bytes + raw_bytes // 100 + 4096 * len(regions))
    compressor = zstandard.ZstdCompressor(level=COMPACT_STRENGTH)

    with generation_disk_usage(output, estimate) as (scratch, _):
        payload = scratch / "payload"
        with payload.open("wb") as sink:
            for entry, image_path in samples:
                packed = pack_region(image_path, entry["size"], compressor)
                entry["offset"] = sink.tell()
                entry["bytes"] = len(packed)
                sink.write(packed)

        index = index_bytes(regions)
        staged = scratch / "package.qdt"
        with staged.open("wb") as package, payload.open("rb") as source:
            package.write(HEADER.pack(MAGIC, len(index)))
            package.write(index)
            copyfileobj(source, package)
        os.link(staged, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("manifests", type=Path, nargs="+")
    args = parser.parse_args()
    try:
        write_package(args.output, args.manifests)
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
