"""Write the two-channel city coverage used by WCM city pages."""

import json
import struct
import zlib


def write_city_tile(path, size, coverage):
    terrain = zlib.compress(bytes(size * size * 4))
    city = zlib.compress(coverage)
    metadata = json.dumps({
        "blocks": {"render/terrain": [0, len(terrain), None],
                   "render/city": [len(terrain), len(city), None]},
    }, separators=(",", ":")).encode()
    path.write_bytes(b"WWORGN1\0" + struct.pack("<I", len(metadata)) + metadata + terrain + city)
