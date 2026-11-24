"""Extract the 1900 LUH2 v2h fractions using bounded HTTP range requests."""

import argparse
import io
import re
from pathlib import Path
from urllib.request import Request, urlopen

import h5py
import numpy as np
import zstandard


STATES = "https://luh.umd.edu/LUH2/LUH2_v2h/states.nc"
LAYERS = {
    "agricultural_land": ("c3ann", "c3per", "c4ann", "c4per", "c3nfx"),
    "forest": ("primf", "secdf"),
    "pasture": ("pastr",),
}
TRANSFER_LIMIT = 64 * 1024 * 1024


class RangedFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        self.offset = 0
        self.transferred = 0
        self.size = self.fetch(0, 1)[1]

    def fetch(self, offset, length):
        if self.transferred + length > TRANSFER_LIMIT:
            raise OSError("LUH2 range transfer exceeded 64 MiB")
        request = Request(self.url, headers={"Range": f"bytes={offset}-{offset + length - 1}"})
        with urlopen(request, timeout=25) as response:
            span = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", response.headers.get("Content-Range", ""))
            if response.status != 206 or not span or tuple(map(int, span.groups()[:2])) != (offset, offset + length - 1):
                raise OSError("LUH2 server did not honor the requested byte range")
            data = response.read(length)
        if len(data) != length:
            raise OSError("incomplete LUH2 byte range")
        self.transferred += length
        return data, int(span[3])

    def seek(self, offset, whence=io.SEEK_SET):
        self.offset = {io.SEEK_SET: 0, io.SEEK_CUR: self.offset, io.SEEK_END: self.size}[whence] + offset
        return self.offset

    def tell(self):
        return self.offset

    def readinto(self, buffer):
        length = min(len(buffer), self.size - self.offset)
        if length <= 0:
            return 0
        buffer[:length] = self.fetch(self.offset, length)[0]
        self.offset += length
        return length


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--states", help="Reuse an existing LUH2 v2h states.nc instead of fetching ranges")
    args = parser.parse_args()
    source = args.states or RangedFile(STATES)
    args.output.mkdir(parents=True, exist_ok=True)
    with h5py.File(source, "r") as states:
        time = states["time"]
        units = time.attrs["units"]
        if isinstance(units, bytes):
            units = units.decode("ascii")
        assert units.startswith("years since 0850") or units.startswith("years since 850"), units
        index, = np.flatnonzero(time[:] == 1050)
        lat, lon = states["lat"][:], states["lon"][:]
        assert np.allclose(lat, np.arange(89.875, -90, -0.25)), lat
        assert np.allclose(lon, np.arange(-179.875, 180, 0.25)), lon
        for layer, variables in LAYERS.items():
            slices = np.stack([states[var][index] for var in variables])
            known = np.all(np.isfinite(slices) & (slices >= 0) & (slices <= 1), axis=0)
            fraction = np.where(known[None, :, :], slices, 0).sum(axis=0)
            assert np.all(fraction <= 1.0001), layer
            values = np.where(known, np.rint(fraction.clip(0, 1) * 10000), 65535).astype("<u2")
            (args.output / f"{layer}.u16.zst").write_bytes(zstandard.ZstdCompressor(level=9).compress(values.tobytes()))
            print(layer, values.shape, int(known.sum()), int((known & (values > 0)).sum()), flush=True)
    if isinstance(source, RangedFile):
        print(f"Transferred {source.transferred:,} bytes of the LUH2 series.")


if __name__ == "__main__":
    main()
