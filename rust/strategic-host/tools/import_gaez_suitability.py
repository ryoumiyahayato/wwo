"""Install selected FAO–IIASA GAEZ v4 suitability rasters in a local runtime."""

import argparse
import io
import json
import math
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import zlib

from PIL import Image


REPOSITORY = Path(__file__).resolve().parents[3]
SOURCE = "https://gaez-v4-data.fao.org/data/res05/CRUTS32/Hist/6190L"
SIZE = (4320, 2160)
MAX_TIFF_BYTES = 2_000_000


def import_raster(output, sources, crop, scenario):
    filename = f"siL{scenario}0_{crop}.tif"
    target = output / f"{crop}-{scenario}.u8.z"
    if target.is_file():
        return filename, "existing"
    original = sources / filename if sources else None
    if original and original.is_file():
        with original.open("rb") as raster:
            tiff = raster.read(MAX_TIFF_BYTES + 1)
    else:
        response = subprocess.run(
            ["curl", "--silent", "--show-error", "--location", "--max-time", "35",
             "--retry", "2", "--max-filesize", str(MAX_TIFF_BYTES), "--write-out", "\n%{http_code}",
             f"{SOURCE}/{filename}"],
            capture_output=True, check=True,
        )
        tiff, status = response.stdout.rsplit(b"\n", 1)
        if status == b"404":
            return filename, "unavailable"
        if status != b"200":
            raise ValueError(f"{filename}: HTTP {status.decode('ascii')}")
    if len(tiff) > MAX_TIFF_BYTES:
        raise ValueError(f"{filename}: unexpected source size")
    with Image.open(io.BytesIO(tiff)) as raster:
        scale, origin, keys = (raster.tag_v2[i] for i in (33550, 33922, 34735))
        crs = {key: value for key, offset, count, value in zip(
            keys[4::4], keys[5::4], keys[6::4], keys[7::4]) if offset == 0 and count == 1}
        if (raster.size != SIZE or raster.mode not in ("P", "L") or
                origin[:5] != (0., 0., 0., -180., 90.) or
                not all(math.isclose(angle, 1 / 12) for angle in scale[:2]) or
                crs.get(2048) != 4326 or crs.get(1025) != 1):
            raise ValueError(f"{filename}: unexpected geometry, CRS, or pixel format")
        pixels = raster.tobytes()
        if max(pixels) > 9:
            raise ValueError(f"{filename}: unexpected suitability class")
    temporary = target.with_suffix(".partial")
    try:
        temporary.write_bytes(zlib.compress(pixels, level=6))
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    return filename, "installed"


def main():
    catalogue = json.loads((REPOSITORY / "data/resource-geography/gaez-crops.json").read_text("utf-8"))
    codes = [crop["code"] for crop in catalogue]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime_data", type=Path)
    parser.add_argument("--source-dir", type=Path, help="reuse previously obtained GAEZ GeoTIFFs")
    parser.add_argument("--crop", nargs="+", choices=codes, default=codes)
    parser.add_argument("--gravity-irrigation", action="store_true")
    args = parser.parse_args()
    output = args.runtime_data.resolve() / "resource-geography/gaez-v4"
    if output.is_relative_to(REPOSITORY):
        parser.error("install GAEZ files outside the source checkout")
    output.mkdir(parents=True, exist_ok=True)
    scenarios = ("r", "g") if args.gravity_irrigation else ("r",)
    jobs = [(output, args.source_dir, code, scenario) for code in dict.fromkeys(args.crop) for scenario in scenarios]
    with ThreadPoolExecutor(max_workers=4) as pool:
        for filename, state in pool.map(lambda job: import_raster(*job), jobs):
            print(f"{filename}: {state}", flush=True)


if __name__ == "__main__":
    main()
