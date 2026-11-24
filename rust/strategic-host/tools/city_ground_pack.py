"""Write the two-channel city coverage used by WCM city pages."""

import json
import struct
import zlib


def read_city_coverage(path):
    raw = path.read_bytes()
    if raw[:8] != b"WWORGN1\0":
        raise ValueError(f"Unexpected city page format: {path}")
    header_size, = struct.unpack_from("<I", raw, 8)
    payload = 12 + header_size
    header = json.loads(raw[12:payload])
    offset, length, _ = header["blocks"]["render/city"]
    return zlib.decompress(raw[payload + offset:payload + offset + length])


def write_city_tile(path, size, coverage):
    terrain = zlib.compress(bytes(size * size * 4))
    city = zlib.compress(coverage)
    metadata = json.dumps({
        "blocks": {"render/terrain": [0, len(terrain), None],
                   "render/city": [len(terrain), len(city), None]},
    }, separators=(",", ":")).encode()
    path.write_bytes(b"WWORGN1\0" + struct.pack("<I", len(metadata)) + metadata + terrain + city)
