"""Reblock existing Godot map resources without changing the serialized data."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import ctypes
import json
from pathlib import Path
import re
import shutil
import struct
import zlib


HEADER = struct.Struct("<4sIII")
ZSTD = 2
DEFLATE = 1
BLOCK_SIZE = 64 * 1024
MAX_DECODED = 96 * 1024 * 1024
COORDINATES = "@geometry.coordinates"


class Zstd:
    def __init__(self, library):
        self.lib = ctypes.CDLL(str(library))
        functions = (
            ("ZSTD_compressBound", [ctypes.c_size_t]),
            ("ZSTD_compress", [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]),
            ("ZSTD_decompress", [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]),
        )
        for name, args in functions:
            function = getattr(self.lib, name)
            function.argtypes = args
            function.restype = ctypes.c_size_t

    def compress(self, raw):
        buffer = ctypes.create_string_buffer(self.lib.ZSTD_compressBound(len(raw)))
        length = self.lib.ZSTD_compress(buffer, len(buffer), raw, len(raw), 9)
        if length > len(buffer):
            raise ValueError("Zstandard compression failed")
        return buffer.raw[:length]

    def decompress(self, data, size):
        buffer = ctypes.create_string_buffer(size)
        if self.lib.ZSTD_decompress(buffer, size, data, len(data)) != size:
            raise ValueError("Zstandard block length mismatch")
        return buffer.raw


def unpack(data, codec):
    magic, mode, block_size, raw_size = HEADER.unpack_from(data)
    if magic not in (b"RSCC", b"GCPF") or data[-4:] != magic:
        raise ValueError("Expected a Godot compressed map resource")
    if mode not in (ZSTD, DEFLATE) or not 0 < block_size <= MAX_DECODED or not 0 < raw_size <= MAX_DECODED:
        raise ValueError("Invalid map resource block header")
    count = raw_size // block_size + 1
    sizes = struct.unpack_from(f"<{count}I", data, HEADER.size)
    offset = HEADER.size + 4 * count
    if offset + sum(sizes) != len(data) - 4:
        raise ValueError("Invalid compressed block table")
    raw = bytearray()
    for index, size in enumerate(sizes):
        payload = data[offset:offset + size]
        expected = min(block_size, raw_size - index * block_size)
        block = codec.decompress(payload, expected) if mode == ZSTD else zlib.decompress(payload)
        if len(block) != expected:
            raise ValueError("Invalid decoded block size")
        raw.extend(block)
        offset += size
    return raw


def reblock(original, codec):
    raw = unpack(original, codec)
    # Larger native blocks share the same dictionary across more triangles.
    block_size = min(BLOCK_SIZE, len(raw) + 1)
    blocks = [codec.compress(bytes(raw[i:i + block_size])) for i in range(0, len(raw) + 1, block_size)]
    magic = original[:4]
    result = HEADER.pack(magic, ZSTD, block_size, len(raw)) + struct.pack(
        f"<{len(blocks)}I", *(len(block) for block in blocks)
    ) + b"".join(blocks) + magic
    if unpack(result, codec) != raw:
        raise ValueError("Serialized resource bytes changed")
    return result, len(raw)


def compact_geometry(geometries):
    for entry in geometries.values():
        coordinates = entry["geometry"].get("coordinates")
        for lod, display in entry["lod_geometry"].items():
            if isinstance(display, list) and display and display == coordinates:
                # The serialized comparison also preserves signs and numeric spelling.
                if json.dumps(display) == json.dumps(coordinates):
                    entry["lod_geometry"][lod] = COORDINATES


def repack_geometry(original):
    decoded = zlib.decompress(original)
    geometries = json.loads(decoded)
    compact_geometry(geometries)
    raw = json.dumps(geometries, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    if COORDINATES.encode() not in raw or len(raw) >= len(decoded):
        return original, len(decoded)
    return zlib.compress(raw, 9), len(raw)


def write_replacement(source, target, result, backup):
    if backup is not None and not backup.exists():
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, backup)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_bytes(result)
    temporary.replace(target)


def repack(source, target, codec, backup=None):
    original = source.read_bytes()
    result, decoded = repack_geometry(original) if source.suffix == ".geom" else reblock(original, codec)
    if len(result) >= len(original):
        return len(original), len(original), decoded
    write_replacement(source, target, result, backup)
    if source.suffix == ".geom" and source == target:
        document = source.with_suffix(".json")
        prior = document.read_bytes()
        reference = re.compile(
            rb'("path":\s*"res://data/strategic/' + re.escape(source.name.encode()) +
            rb'",\s*"encoding":\s*"ZLIB_JSON_UTF8",\s*"bytes":\s*)\d+(,\s*"decoded_bytes":\s*)\d+'
        )
        updated = reference.sub(lambda match: match[1] + str(len(result)).encode() + match[2] + str(decoded).encode(), prior)
        if prior != updated:
            write_replacement(document, document, updated, backup.with_suffix(".json"))
    return len(original), len(result), decoded


def update_display_sizes(root, backup):
    index = root / "data/strategic/index.json"
    original = index.read_bytes()
    entry = re.compile(rb'"compiled_asset"\s*:\s*\{[^{}]*\}')
    path_field = re.compile(rb'"path"\s*:\s*"res://(data/strategic/[^"]+\.display)"')
    sizes = []

    def replace_entry(match):
        descriptor = match[0]
        path = path_field.search(descriptor)
        if path is None:
            return descriptor
        resource = root / path[1].decode()
        if not resource.is_file():
            return descriptor
        size = resource.stat().st_size
        sizes.append(size)
        return re.sub(rb'("bytes"\s*:\s*)\d+', lambda m: m[1] + str(size).encode(), descriptor)

    updated = entry.sub(replace_entry, original)
    query_bytes = (root / "data/strategic/historical_reference_1900.display").stat().st_size
    summary = re.compile(rb'"prepared_political_display"\s*:\s*\{[^{}]*\}')

    def replace_summary(match):
        result = re.sub(rb'("bytes"\s*:\s*)\d+', lambda m: m[1] + str(sum(sizes)).encode(), match[0])
        return re.sub(rb'("historical_query_bytes"\s*:\s*)\d+', lambda m: m[1] + str(query_bytes).encode(), result)

    updated = summary.sub(replace_summary, updated)
    if updated != original:
        write_replacement(index, index, updated, backup / index.relative_to(root))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zstd-library", type=Path, required=True)
    parser.add_argument("--pattern", action="append", required=True, help="Resource glob relative to the project")
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument("--output", type=Path, help="Write smaller candidates here, preserving project-relative paths")
    destination.add_argument("--backup", type=Path, help="Replace originals, keeping the old files here")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.output is not None and args.output.resolve() == root:
        parser.error("Use --backup for an in-place replacement")
    codec = Zstd(args.zstd_library.resolve())
    files = sorted({path for pattern in args.pattern for path in root.glob(pattern) if path.is_file()})
    if not files:
        parser.error("No resources matched")

    def convert(source):
        relative = source.relative_to(root)
        if source.suffix == ".geom" and (source.name.endswith(".ink.geom") or not source.name.startswith("physical_")):
            return (0, 0, 0)
        if source.suffix not in (".res", ".display", ".geom") or not relative.is_relative_to(("assets/settlements" if source.suffix == ".res" else "data/strategic")):
            raise ValueError(f"Outside the supported map resource paths: {relative}")
        target = args.output / relative if args.output is not None else source
        backup = args.backup / relative if args.backup is not None else None
        return repack(source, target, codec, backup)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        before = after = decoded = smaller = 0
        for old_bytes, new_bytes, decoded_bytes in pool.map(convert, files):
            before += old_bytes
            after += new_bytes
            decoded += decoded_bytes
            smaller += old_bytes > new_bytes
    if args.backup is not None and any(path.suffix == ".display" for path in files):
        update_display_sizes(root, args.backup)
    print(f"files={len(files)} smaller={smaller} before={before} after={after} saved={before-after} decoded={decoded}")


if __name__ == "__main__":
    main()
