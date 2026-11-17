"""Index the Z7 page review and optionally store one 8×8 batch of original PNGs."""
import argparse
import csv
import json
from pathlib import Path, PureWindowsPath
import re
import zipfile

from capture_z7_pages import (BATCH, COLS, HEIGHT, ROWS, WIDTH, bounds, combine,
                             missing_intervals, png_size, read, row_views)


SCOPES = ('regional', 'close')
STATUS_COLORS = {'PASS': '#87ca98', 'FAIL': '#f28574', 'SOURCE_UNCERTAIN': '#cbaaff',
                 'REVIEW_INCOMPLETE': '#bd93c8',
                 'PENDING': '#e5c687', 'NOT_RENDERED': '#9ba3ab'}
COLUMNS = (
    'ordinal', 'z', 'x', 'y', 'west_lon', 'south_lat', 'east_lon', 'north_lat',
    'center_lon', 'center_lat', 'capture_state', 'visual_status', 'reviewer',
    'manual_status', 'note', 'scope_captures_regional', 'scope_captures_close',
    'uncovered_regional_latitude_bands', 'uncovered_close_latitude_bands',
    'manifest_version', 'surface_revision', 'program_revision',
    'receipt', 'regional_pngs', 'close_pngs', 'pole_pngs', 'release_zip',
)
LAND_COLUMNS = ('review_region', 'land_class', 'land_fraction', 'land_focus_lon', 'land_focus_lat')


def page_reviews(files):
    reviews = {}
    for path in files:
        with path.open(newline='', encoding='utf-8-sig') as file:
            for row in csv.DictReader(file):
                ordinal = int(row['ordinal'])
                reviewer, note = row['reviewer'].strip(), row['note'].strip()
                status = row['status'].strip().upper()
                if ordinal in reviews or not 1 <= ordinal <= COLS * ROWS:
                    raise ValueError(f'{path.name}: duplicate or invalid ordinal {ordinal}')
                if not reviewer or not note or status not in ('PASS', 'FAIL', 'SOURCE_UNCERTAIN'):
                    raise ValueError(f'{path.name}: incomplete review for {ordinal}')
                reviews[ordinal] = dict(reviewer=reviewer, manual_status=status, note=note)
    return reviews


def confirmed(view, png, key=None):
    terrain = view.get('terrain', {})
    return (view.get('status') == 'captured_review_pending'
            and view.get('all_samples_pure_z7')
            and (key is None or view.get('center_is_requested_page'))
            and terrain.get('selection') == {'exact': 7}
            and terrain.get('draw_max_level') == 7 and terrain.get('selected_ready')
            and not terrain.get('exact_view_over_capacity')
            and png_size(png) == (WIDTH, HEIGHT))


def safe_resource(data):
    return {k: v for k, v in data.items() if k != 'candidate'}


def load_pole(root, pole, scope, resource):
    receipt = root / 'poles' / f'z7-pole-{pole}-{scope}.json'
    if not receipt.is_file():
        return None
    doc = read(receipt)
    png = receipt.with_suffix('.png')
    if (safe_resource(doc.get('resource', {})) == resource
            and doc.get('img') == png.name and confirmed(doc, png)
            and doc.get('coverage', {}).get('all_longitudes')):
        return png, receipt, doc['coverage']['inscribed_polar_latitude_band']
    return None


def summarize(root, receipt, x, y, review, archived_batches, land_info=None):
    ordinal = 1 + y * COLS + x
    west, south, east, north = bounds(x, y)
    data = dict.fromkeys(COLUMNS, '')
    data.update(ordinal=ordinal, z=7, x=x, y=y, west_lon=west, south_lat=south,
                east_lon=east, north_lat=north, center_lon=(west + east)/2,
                center_lat=(south + north)/2, capture_state='NOT_ATTEMPTED',
                visual_status='NOT_RENDERED', **review)
    if land_info is not None:
        land = land_info(x, y)
        lon, lat = land.get('land_focus') or ('', '')
        data.update(review_region='', land_class=land['land_class'],
                    land_fraction=land['land_fraction'], land_focus_lon=lon, land_focus_lat=lat)
    if receipt is None:
        return data, None, []

    doc = read(receipt)
    if doc.get('ordinal') != ordinal or doc.get('page') != [7, x, y]:
        raise ValueError(f'Page coordinates disagree with receipt: {receipt.name}')
    header = read(receipt.parent / 'batch.json')
    resource = safe_resource(doc['resource'])
    if safe_resource(header['resource']) != resource:
        raise ValueError(f'Page resource disagrees with batch: {receipt.name}')
    data.update(manifest_version=resource.get('version', ''),
                surface_revision=resource.get('surface_revision', ''),
                program_revision=resource.get('program_revision', ''),
                receipt=receipt.relative_to(root).as_posix())
    if land_info is not None:
        data['review_region'] = doc.get('review_region', '')

    archive_paths = [(receipt, True)]
    both_complete, any_png, valid_png, thumbnail = True, False, False, None
    poles = []
    for scope, plan in row_views(y, header['detail_capacity']).items():
        views = doc['scopes'].get(scope, {}).get('views', {})
        intervals, images, valid = [], [], 0
        views_expected = [f'{i:02}' for i, _ in enumerate(plan['views'])]
        if doc.get('land', {}).get('land_focus_added'):
            views_expected.insert(0, 'land')
        for suffix in views_expected:
            label = f'z7-y{y:03}-x{x:03}-{scope}-{suffix}'
            view = views.get(label, {})
            png = receipt.parent / (label + '.png')
            if view.get('img') != png.name or png_size(png) != (WIDTH, HEIGHT):
                continue
            any_png = True
            images.append(png.relative_to(root).as_posix())
            archive_paths.append((png, False))
            if scope == 'regional' and thumbnail is None:
                thumbnail = png
            if confirmed(view, png, [7, x, y]):
                valid += 1
                valid_png = True
                intervals.append(view['coverage']['tile_full_longitude_latitude_band'])
        missing = missing_intervals(combine(intervals), south, north)
        if missing and y in (0, ROWS - 1):
            pole = load_pole(root, 'north' if y == 0 else 'south', scope, resource)
            if pole:
                image, record, band = pole
                clipped = max(south, band[0]), min(north, band[1])
                if clipped[1] > clipped[0]:
                    intervals.append(clipped)
                    poles.append(image.relative_to(root).as_posix())
                    archive_paths.extend(((image, False), (record, True)))
                    missing = missing_intervals(combine(intervals), south, north)
        complete = valid == len(views_expected) and not missing
        both_complete = both_complete and complete
        data[f'scope_captures_{scope}'] = f'{valid}/{len(views_expected)}'
        data[f'uncovered_{scope}_latitude_bands'] = json.dumps(missing, separators=(',', ':'))
        data[f'{scope}_pngs'] = ';'.join(images)
    data['pole_pngs'] = ';'.join(poles)

    if any_png:
        data['capture_state'] = 'COMPLETE' if both_complete else 'PARTIAL'
        if valid_png:
            data['visual_status'] = 'PENDING'
        status = review.get('manual_status')
        if status:
            data['visual_status'] = 'REVIEW_INCOMPLETE'
            if (valid_png and status in ('FAIL', 'SOURCE_UNCERTAIN')) or (status == 'PASS' and both_complete):
                data['visual_status'] = status
    else:
        data['capture_state'] = 'ATTEMPTED_NO_IMAGE'
    data['release_zip'] = archived_batches.get(receipt.parent.name, '')
    return data, thumbnail, archive_paths


def write_sheet(output, cells, x0, y0):
    from PIL import Image, ImageDraw, ImageFont

    width, height = 170, 133
    image = Image.new('RGB', (width*BATCH, height*BATCH), '#131921')
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()
    for i, (row, path) in enumerate(cells):
        y, x = divmod(i, BATCH)
        left, top = x*width, y*height
        if path:
            with Image.open(path) as source:
                thumb = source.convert('RGB')
                thumb.thumbnail((width - 8, 92), Image.Resampling.LANCZOS)
                image.paste(thumb, (left+(width-thumb.width)//2, top+19))
        else:
            draw.rectangle((left + 4, top + 19, left + width - 4, top + 109), fill='#202831')
        status = row['visual_status']
        label = f"#{row['ordinal']} 7/{x0+x}/{y0+y} {status}"
        draw.text((left + 5, top + 3), label, font=font, fill=STATUS_COLORS[status])
        center = f"{row['center_lon']:+.3f}°, {row['center_lat']:+.3f}°"
        draw.text((left + 5, top + 113), center, font=font, fill='#d8e0e8')
    image.save(output, quality=86, optimize=True)


def public_receipt(value):
    if isinstance(value, dict):
        return {key: public_receipt(item) for key, item in value.items() if key != 'candidate'}
    if isinstance(value, list):
        return [public_receipt(item) for item in value]
    if isinstance(value, str) and re.match(r'^(?:[A-Za-z]:[/\\]|\\\\)', value):
        return PureWindowsPath(value).name
    return value


def zip_batch(output, root, files):
    pending = output.with_suffix('.zip.tmp')
    with zipfile.ZipFile(pending, 'x', compression=zipfile.ZIP_STORED) as archive:
        for path, is_receipt in sorted(set(files)):
            arcname = path.relative_to(root).as_posix()
            if is_receipt:
                value = public_receipt(read(path))
                archive.writestr(arcname, json.dumps(value, ensure_ascii=False, separators=(',', ':')))
            else:
                archive.write(path, arcname)
    pending.rename(output)


def scan_receipts(root):
    pages = {}
    for path in root.glob('batch-y*-x*/z7-y*-x*.json'):
        _, yy, xx = path.stem.split('-')
        y, x = int(yy[1:]), int(xx[1:])
        if not (0 <= y < ROWS and 0 <= x < COLS):
            raise ValueError(f'Invalid page name {path.name}')
        if (x, y) in pages:
            raise ValueError(f'Duplicate page receipt {path.name}')
        origin = f'batch-y{y // BATCH * BATCH:03}-x{x // BATCH * BATCH:03}'
        if not re.fullmatch(re.escape(origin) + r'(?:-[a-z0-9]+(?:-[a-z0-9]+)*)?', path.parent.name):
            raise ValueError(f'{path.name} is placed in the wrong batch')
        pages[x, y] = path
    return pages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--captures', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--review', type=Path, action='append', default=[],
                        help='UTF-8 CSV with ordinal,reviewer,status,note. Repeat for non-overlapping reviews.')
    parser.add_argument('--batch-x', type=int, default=0)
    parser.add_argument('--batch-y', type=int, default=0)
    parser.add_argument('--review-region', help='Region suffix for the selected batch, for example europe.')
    parser.add_argument('--natural-earth', type=Path,
                        help='Directory of the generator’s Natural Earth physical ZIPs.')
    parser.add_argument('--zip', action='store_true',
                        help='Also write one ZIP_STORED archive of this 8×8 batch and its pole evidence.')
    args = parser.parse_args()
    x0, y0 = args.batch_x, args.batch_y
    if x0 % BATCH or y0 % BATCH or not (0 <= x0 < COLS and 0 <= y0 < ROWS):
        parser.error('Batch origin must be a valid X,Y multiple of eight')
    if not args.captures.is_dir():
        parser.error('Capture directory does not exist')
    batch = f'batch-y{y0:03}-x{x0:03}'
    if args.review_region:
        if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', args.review_region) or not args.natural_earth:
            parser.error('--review-region requires a lowercase slug and --natural-earth')
        batch += '-' + args.review_region
    land_info = None
    if args.natural_earth:
        from capture_z7_pages import load_land_geometry
        land_info = load_land_geometry(args.natural_earth)
    archive = f'z7-visual-{batch}.zip' if args.zip else ''
    paths = scan_receipts(args.captures)
    reviews = page_reviews(args.review)
    args.out.mkdir(parents=True, exist_ok=True)
    if archive and (args.out / archive).exists():
        parser.error('That batch archive already exists. Use a separate output.')
    archived_batches = {path.stem.removeprefix('z7-visual-'): path.name
                        for path in args.out.glob('z7-visual-batch-y*-x*.zip')}
    if archive:
        archived_batches[batch] = archive
    files, cells = [], []
    index = args.out / 'z7-visual-global-pages.csv'
    pending = index.with_suffix('.csv.tmp')
    with pending.open('w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, COLUMNS + (LAND_COLUMNS if land_info is not None else ()))
        writer.writeheader()
        for y in range(ROWS):
            for x in range(COLS):
                ordinal = 1 + y * COLS + x
                path = paths.get((x, y))
                row, thumb, originals = summarize(args.captures, path, x, y,
                                                   reviews.get(ordinal, {}), archived_batches, land_info)
                writer.writerow(row)
                if x0 <= x < x0 + BATCH and y0 <= y < y0 + BATCH:
                    in_batch = path is not None and path.parent.name == batch
                    cells.append((row, thumb if in_batch else None))
                    if in_batch:
                        files.extend(originals)
    write_sheet(args.out / f'z7-visual-{batch}.jpg', cells, x0, y0)
    if archive:
        if not any(not is_receipt for _, is_receipt in files):
            parser.error('The selected batch has no complete images to archive')
        files.append((args.captures / batch / 'batch.json', True))
        zip_batch(args.out / archive, args.captures, files)
    pending.replace(index)


if __name__ == '__main__':
    main()
