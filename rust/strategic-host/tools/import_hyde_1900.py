"""Extract only the HYDE 3.2.1 1900 land-use bands and the land-area grid."""
from argparse import ArgumentParser
from array import array
from contextlib import contextmanager
from compression import zstd
import io
from pathlib import Path
import re
import struct
import subprocess
import sys
from tempfile import TemporaryDirectory
from urllib.request import Request, urlopen
from zipfile import ZipFile

DATASTATION = "https://archaeology.datastations.nl/api/access/datafile/"
BANDS = (
    "cropland", "grazing", "pasture", "rangeland", "conv_rangeland",
    "tot_irri", "tot_rainfed", "tot_rice", "ir_rice", "rf_rice",
)
COLS, ROWS = 4320, 2160
BUDGET = 56 * 1024 * 1024


class RemoteZip(io.RawIOBase):
    """Seek using validated HTTP ranges; never download the complete archive."""

    def __init__(self, file_id):
        request = Request(DATASTATION + str(file_id), headers={"Range": "bytes=-1"})
        with urlopen(request, timeout=25) as response:
            span = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", response.headers.get("Content-Range", ""))
            if response.status != 206 or not span or int(span[1]) != int(span[3]) - 1 or span[1] != span[2]:
                raise OSError("Archive HTTP ranges are unavailable")
            self.url = response.url
            self.size = int(span[3])
        self.position = 0
        self.transferred = 1

    def readable(self):
        return True

    def seekable(self):
        return True

    def readinto(self, buffer):
        data = self.read(len(buffer))
        buffer[:len(data)] = data
        return len(data)

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        self.position = (0, self.position, self.size)[whence] + offset
        return self.position

    def read(self, count=-1):
        count = self.size - self.position if count < 0 else min(count, self.size - self.position)
        if count <= 0:
            return b""
        if self.transferred + count > BUDGET:
            raise OSError("HYDE transfer budget exceeded")
        start = self.position
        end = start + count - 1
        request = Request(self.url, headers={"Range": f"bytes={start}-{end}"})
        with urlopen(request, timeout=40) as response:
            expected = f"bytes {start}-{end}/{self.size}"
            if response.status != 206 or response.headers.get("Content-Range") != expected:
                raise OSError("Archive returned a different byte range")
            data = response.read(count)
        if len(data) != count:
            raise OSError("Archive range is incomplete")
        self.position += count
        self.transferred += count
        return data


@contextmanager
def open_member(archive, member, seven_zip):
    entry = archive.getinfo(member)
    if entry.compress_type != 9:
        with archive.open(entry) as stream:
            yield stream
        return
    # Deflate64 is not supported by zipfile. Preserve the compression method,
    # lengths and CRC in a one-entry ZIP so 7-Zip can verify while extracting.
    if entry.flag_bits != 0:
        raise ValueError(f"Unsupported flags on Deflate64 member {member}")
    archive.fp.seek(entry.header_offset)
    header = archive.fp.read(30)
    if header[:4] != b"PK\x03\x04":
        raise ValueError(f"Bad local ZIP header in {member}")
    name_len, extra_len = struct.unpack_from("<HH", header, 26)
    archive.fp.seek(name_len + extra_len, io.SEEK_CUR)
    data = archive.fp.read(entry.compress_size)
    if len(data) != entry.compress_size:
        raise OSError(f"Incomplete archive member {member}")
    name = b"band.asc"
    sizes = (entry.CRC, entry.compress_size, entry.file_size)
    local = struct.pack("<4s5H3I2H", b"PK\x03\x04", 21, 0, 9, 0, 0, *sizes, len(name), 0) + name
    central = struct.pack("<4s6H3I5H2I", b"PK\x01\x02", 21, 21, 0, 9, 0, 0, *sizes,
                          len(name), 0, 0, 0, 0, 0, 0) + name
    end = struct.pack("<4s4H2IH", b"PK\x05\x06", 0, 0, 1, 1, len(central), len(local) + len(data), 0)
    with TemporaryDirectory() as directory:
        capsule = Path(directory) / "band.zip"
        with capsule.open("wb") as output:
            for section in (local, data, central, end):
                output.write(section)
        with subprocess.Popen([seven_zip, "x", "-so", str(capsule)], stdout=subprocess.PIPE) as decoder:
            try:
                yield decoder.stdout
                if decoder.wait():
                    raise OSError(f"Deflate64 extraction failed for {member}")
            finally:
                if decoder.poll() is None:
                    decoder.kill()


def convert(archive, member, output, seven_zip):
    if output.is_file():
        return
    part = output.with_suffix(".partial")
    try:
        with open_member(archive, member, seven_zip) as source, zstd.open(part, "wb", level=7) as dest:
            header = dict(line.decode().lower().split() for line in (source.readline() for _ in range(6)))
            if (int(header["ncols"]), int(header["nrows"])) != (COLS, ROWS) or (
                float(header["xllcorner"]), float(header["yllcorner"])
            ) != (-180, -90) or abs(float(header["cellsize"]) - 1 / 12) > 1e-7:
                raise ValueError(f"Unexpected source grid in {member}")
            unknown = float(header["nodata_value"])
            known = 0
            hectares = 0.
            for _ in range(ROWS):
                values = array("f", (x * 100 if x != unknown else -1 for x in map(float, source.readline().split())))
                if len(values) != COLS or any(x < 0 and x != -1 for x in values):
                    raise ValueError(f"Invalid area row in {member}")
                known += sum(x >= 0 for x in values)
                hectares += sum(x for x in values if x > 0)
                if sys.byteorder != "little":
                    values.byteswap()
                dest.write(values.tobytes())
            if source.read().strip():
                raise ValueError(f"Unexpected trailing values in {member}")
        part.replace(output)
        print(f"{output.name}: {known:,} cells; {hectares:,.0f} ha", flush=True)
    finally:
        part.unlink(missing_ok=True)


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--supplement", type=Path)
    parser.add_argument("--seven-zip", default="7z")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    groups = (
        (args.supplement, 5490327, (("land_area", "general_files/maxln_cr.asc"),)),
        (args.baseline, 5490328, ((band, f"baseline/asc/1900AD_lu/{band}1900AD.asc") for band in BANDS)),
    )
    for local, file_id, members in groups:
        source = local or io.BufferedReader(RemoteZip(file_id), buffer_size=1024 * 1024)
        with ZipFile(source) as archive:
            for band, member in members:
                convert(archive, member, args.output / f"{band}.f32.zst", args.seven_zip)


if __name__ == "__main__":
    main()
