"""Aggregate native ESA WorldCover 2021 into material fractions on the Z7 grid."""

import argparse
import json
import math
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.warp import reproject
from rasterio.windows import bounds, Window

from build_natural_terrain import LAND_COVER_CODES, PACK_MAX_LEVEL, TILE, generation_disk_usage
from build_terrain_close_samples import window


WIDTH = 2*TILE << PACK_MAX_LEVEL
STEP = 360/WIDTH
TRANSFORM = from_origin(-180,90,STEP,STEP)


def complete_cells(extent):
    west,south,east,north = extent
    if not (-180 <= west < east <= 180 and -90 <= south < north <= 90):
        raise ValueError("Expected west south east north in WGS84. Split antimeridian windows.")
    first_col = math.ceil((west+180)/STEP)
    last_col = math.floor((east+180)/STEP)
    first_row = math.ceil((90-north)/STEP)
    last_row = math.floor((90-south)/STEP)
    if last_col <= first_col or last_row <= first_row:
        raise ValueError("Window contains no complete Z7 pixels")
    return Window(first_col,first_row,last_col-first_col,last_row-first_row)


def area_fractions(source, target):
    extent = bounds(target,TRANSFORM)
    actual = source.bounds
    if (source.crs is None or source.crs.to_epsg() != 4326 or source.count != 1
            or source.dtypes != ("uint8",) or source.transform.b or source.transform.d
            or not (0. < source.transform.a <= 1/10000 and 0. < -source.transform.e <= 1/10000)
            or not (actual.left <= extent[0] and actual.bottom <= extent[1]
                    and actual.right >= extent[2] and actual.top >= extent[3])):
        raise ValueError("Expected native WorldCover pixels covering the complete WGS84 window")
    region = window(source,extent)
    codes = source.read(1,window=region,masked=True)
    shape = (int(target.height),int(target.width))
    fractions = np.zeros((len(LAND_COVER_CODES),*shape),np.uint8)
    valid = np.zeros(shape,np.float32)
    fields = dict(src_transform=source.window_transform(region),src_crs=source.crs,
                  dst_transform=rasterio.windows.transform(target,TRANSFORM),dst_crs=source.crs,
                  resampling=Resampling.average)
    for channel, code in enumerate(LAND_COVER_CODES[1:],1):
        amount = np.zeros(shape,np.float32)
        mask = (codes == code).filled(False)
        reproject(mask.astype(np.uint8),amount,**fields)
        valid += amount
        fractions[channel] = np.rint(amount*255).astype(np.uint8)
    # A missing source pixel does not establish a land category. Leave cells
    # containing missing coverage on the existing material recipe.
    fractions[:,valid<.999] = 0
    return fractions


def write_fractions(output, sources, open_source=rasterio.open):
    windows = [(location,complete_cells(extent)) for location,extent in sources]
    for index, (_, a) in enumerate(windows):
        if any(rasterio.windows.intersect(a,b) for _,b in windows[:index]):
            raise ValueError("Fraction windows overlap. Mosaic the source or use disjoint windows.")
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"), rasterio.open(
            output,"w",driver="GTiff",width=WIDTH,height=WIDTH//2,count=len(LAND_COVER_CODES),
            dtype="uint8",crs="EPSG:4326",transform=TRANSFORM,tiled=True,
            compress="deflate",BIGTIFF="YES",SPARSE_OK="TRUE") as target:
        target.descriptions = tuple(map(str,LAND_COVER_CODES))
        provenance = []
        for location, region in windows:
            with open_source(location) as source:
                for y in range(int(region.row_off),int(region.row_off+region.height),64):
                    for x in range(int(region.col_off),int(region.col_off+region.width),96):
                        block = Window(x,y,min(96,region.col_off+region.width-x),
                                       min(64,region.row_off+region.height-y))
                        target.write(area_fractions(source,block),window=block)
            actual = bounds(region,TRANSFORM)
            print(location,actual,flush=True)
            provenance.append({"source": Path(location).name,"bounds": actual})
        target.update_tags(product="ESA WorldCover 2021 v200",reference_period="modern",
                           cell_coverage=json.dumps(provenance,ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--source",nargs=5,action="append",required=True,
                        metavar=("NATIVE_TIFF","WEST","SOUTH","EAST","NORTH"))
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists")
    sources = [(location,tuple(map(float,extent))) for location,*extent in args.source]
    cells = [complete_cells(extent) for _,extent in sources]
    # Eight-bit class proportions are written incrementally, with sparse coverage.
    estimate = 16_000_000 + sum(int(rect.width*rect.height) for rect in cells)*len(LAND_COVER_CODES)
    with generation_disk_usage(args.output,estimate) as (scratch,_):
        staged = scratch/args.output.name
        write_fractions(staged,sources)
        staged.rename(args.output)


if __name__ == "__main__":
    main()
