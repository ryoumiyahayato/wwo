"""Publish pictures and complete video from the collected Z6 Rust/wgpu frames."""
import argparse
from dataclasses import dataclass
import gzip
import json
from pathlib import Path, PureWindowsPath
import re
import shutil
import subprocess
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont


STAGE = Path(__file__).resolve().parent
FFMPEG = STAGE.parents[1] / 'python-libs/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
SHELVES = {
    'ross-shelf': '罗斯冰架内侧',
    'ronne-filchner-shelf': '龙尼—菲尔希纳冰架',
    'ross-shelf-front': '罗斯冰架外缘',
    'amery-shelf': '埃默里冰架',
    'antarctic-peninsula-west': '南极半岛西缘',
}
SURFACES = {
    'shelves-old-z6': '原版 Z6',
    'shelves-candidate-z6': '候选 Z6',
    'shelves-reference-z7': '已修 Z7',
}
FORMAL = {'geographic': '地理', 'political': '政治', 'economic': '经济', 'military': '军事'}
SPECIAL = {
    'alps-four-tile-corner': '阿尔卑斯山脉 · 四角',
    'wadden-coast': '瓦登海海岸 · 共享边',
    'bering-antimeridian': '白令海 · 反经线',
    'antimeridian-taveuni': '塔韦乌尼 · 岛弧',
    'north-pole': '北极点 · 海面',
    'south-pole': '南极点 · 冰面',
    'cascades-four-tile-corner': '喀斯喀特山脉 · 四角',
    'parana-floodplain': '巴拉那河 · 洪泛平原',
    'fezzan-dry-channels': '费赞 · 干旱区水道',
    'nile-delta': '尼罗河三角洲',
    'andes-altiplano': '安第斯高原与的的喀喀湖',
    'gobi': '戈壁 · 裸岩与沙漠',
    'greenland-ice-streams': '格陵兰冰面河线',
    'bosten-lake': '博斯腾湖东侧水系',
    'mascarene-seafloor': '马斯克林海台与条带',
    'tibet-snow-check': '羌塘高原积雪',
    'sahara-dry-channels': '撒哈拉断续水道',
}
CLIP_LABELS = {
    'ross-full-lod': '罗斯冰架',
    'ronne-shelf-wheel': '龙尼—菲尔希纳冰架',
    'alps-z6': '固定 Z6 · 阿尔卑斯',
    'coast-z6': '固定 Z6 · 瓦登海',
    'alps-oblique': '固定 Z6 · 阿尔卑斯倾斜',
    'slow-warm-z6': '暖缓存 · 慢速 Z5/Z6',
    'rapid-z6': '快速缩放 · Z5/Z6',
    'motion-z6': '缩放、平移、旋转 · 瓦登海',
    'date-z6': '反经线',
    'fast-jump-alps-corner': '阿尔卑斯 · 530→970 米／像素',
    'fast-jump-coast-corner': '瓦登海 · 530→970 米／像素',
    'threshold': 'Z6/Z7 · 临界倍率往返',
    'wheel-reversal': 'Z6/Z7 · 快速滚轮往返',
    'alps-cold': '冷缓存 · 阿尔卑斯',
    'overflow': '北极 · 超页预算',
}
FPS = 20
METRICS = ('mean_R', 'mean_G', 'mean_B', 'mean_luma',
           'mean_abs_horizontal_luma_gradient', 'mean_abs_vertical_luma_gradient')
UUID = re.compile(r'(?i)\b(?:[0-9a-f]{32}|[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})\b')
LOCAL_PATH = re.compile(r'''(?i)(?:[a-z]:[/\\]|\\\\)[^"'\r\n,;<>|]*''')
PROFILE = re.compile(r'Z[67]Detail-[0-9a-f]+', re.IGNORECASE)


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sanitize(value):
    if isinstance(value, dict):
        return {key: sanitize(item) for key, item in value.items()
                if key not in ('profile', 'folder')
                and not (key == 'id' and isinstance(item, str) and UUID.fullmatch(item))}
    if isinstance(value, list):
        return [sanitize(item) for item in value]
    if isinstance(value, str):
        value = LOCAL_PATH.sub(lambda m: PureWindowsPath(m.group()).name, value)
        return UUID.sub('[run id]', PROFILE.sub('[isolated profile]', value))
    return value


def require_file(path):
    if not path.is_file() or not path.stat().st_size:
        raise FileNotFoundError(path)
    return path


def still(folder, key):
    require_file(folder / (key + '.json'))
    return require_file(folder / (key + '.png'))


def choose_formal(run):
    matches = []
    for before in STAGE.glob('formal-before-*'):
        candidate = before.name.removeprefix('formal-before-')
        if run and run != candidate:
            continue
        after = STAGE / ('formal-after-' + candidate)
        try:
            for path in (before, after):
                report = require_file(path / 'formal.json')
                if set(read(report)['modes']) != set(FORMAL):
                    raise ValueError(f'incomplete modes in {report}')
                for name in FORMAL:
                    still(path, name)
        except (FileNotFoundError, ValueError) as exc:
            if run:
                raise ValueError(f'incomplete paired formal run {run}') from exc
            continue
        matches.append(((after / 'formal.json').stat().st_mtime_ns, candidate, before, after))
    if not matches:
        raise FileNotFoundError('A complete paired formal-before/after run was not found')
    _, _, before, after = max(matches)
    return {'formal-before': before, 'formal-after': after}


def open_stills(stills_from, coverage_from, formal):
    root = STAGE / stills_from
    coverage = STAGE / coverage_from / 'coverage-z6' if coverage_from else root / 'coverage-z6'
    plan = read(STAGE / 'z6-sample-plan.json')
    groups = {surface: {name: still(root / surface, name) for name in SHELVES}
              for surface in SURFACES}
    scopes = {f"{row['id']}-{view}": still(coverage, f"{row['id']}-{view}")
              for row in plan['random'] for view in ('regional', 'close')}
    cases = {name: still(coverage, name) for name in SPECIAL}
    groups['coverage-z6'] = scopes | cases
    groups.update({name: {mode: still(path, mode) for mode in FORMAL}
                   for name, path in formal.items()})
    return plan, groups


def font(size):
    return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', size)


def image(path):
    with Image.open(path) as source:
        return source.convert('RGB')


def sheet(path, rows, width=612):
    height = width * 9 // 16
    band = 36
    pane = Image.new('RGB', (width * max(map(len, rows)), (height + band) * len(rows)), (23, 28, 36))
    draw = ImageDraw.Draw(pane)
    text_font = font(17)
    for r, row in enumerate(rows):
        for c, (graphic, label) in enumerate(row):
            picture = graphic if isinstance(graphic, Image.Image) else image(graphic)
            left, top = c * width, r * (height + band)
            picture.thumbnail((width, height), Image.Resampling.LANCZOS)
            pane.paste(picture, (left + (width - picture.width)//2, top + band + (height - picture.height)//2))
            draw.text((left + 10, top + 5), label, font=text_font, fill=(245, 246, 249))
    pane.save(path, quality=88, optimize=True)


def chunks(rows, width):
    return [rows[i:i+width] for i in range(0, len(rows), width)]


def publish_stills(out, release, plan, groups):
    ros_names = ('ross-shelf-old-z6.png', 'ross-shelf-candidate-z6.png', 'ross-shelf-reference-z7.png')
    for source, label in zip(SURFACES, ros_names, strict=True):
        shutil.copyfile(groups[source]['ross-shelf'], out / label)
    sheet(out / 'shelves.jpg',
          [[(groups[surface][name], f'{site} · {variant}') for surface, variant in SURFACES.items()]
           for name, site in SHELVES.items()], 500)

    coverage = groups['coverage-z6']
    continents = [[(coverage[f"{row['id']}-{view}"],
                    f"{row['continent']} · {label} · {row[view+'_mpp']} 米／像素")
                   for view, label in [('regional', '区域'), ('close', '近景')]]
                  for row in plan['random']]
    sheet(out / 'continents.jpg', continents[:4], 560)
    sheet(out / 'continents-south.jpg', continents[4:], 560)

    questions = {'fezzan-dry-channels', 'greenland-ice-streams', 'bosten-lake',
                 'mascarene-seafloor', 'tibet-snow-check', 'sahara-dry-channels'}
    for file, choose in [('landforms.jpg', False), ('source-questions.jpg', True)]:
        selected = [(coverage[name], label) for name, label in SPECIAL.items()
                    if (name in questions) == choose]
        sheet(out / file, chunks(selected, 3), 464)

    formal = groups['formal-after']
    sheet(out / 'formal.jpg', chunks([(formal[key], f'后台正式 Rust · {label}')
                                      for key, label in FORMAL.items()], 2), 620)
    with zipfile.ZipFile(release / 'z6-detail-stills.zip', 'w', zipfile.ZIP_STORED) as archive:
        for group, pictures in groups.items():
            for file in pictures.values():
                archive.write(file, f'{group}/{file.name}')


@dataclass
class Clip:
    key: str
    receipt: dict
    frames: list
    size: tuple


def load_clip(folder, name):
    path = require_file(folder / f'{name}.json')
    receipt = read(path)
    width, height = receipt['start']['viewport']
    frames = [p for p in sorted((folder / name).glob('*.rgba')) if p.is_file()]
    count = len(receipt['frames'])
    if not count or len(frames) != count:
        raise ValueError(f'{folder.name}/{name}: {len(frames)} images for {count} recorded frames')
    for i, p in enumerate(frames):
        if p.stem != f'{i:04}' or p.stat().st_size != width * height * 4:
            raise ValueError(f'{folder.name}/{name}: invalid or missing raw frame {i}')
    return Clip(f'{folder.name}/{name}', receipt, frames, (width, height))


def load_video_sets(shelves_root, lod_root, fixed_root):
    def set_of(root, group, names):
        return [[load_clip(root / group, name)] for name in names]

    comparisons = [
        [load_clip(shelves_root / f'shelves-{label}-z6{suffix}', name) for label in ('old', 'candidate')]
        for suffix, name in [('', 'ross-full-lod'), ('-ronne', 'ronne-shelf-wheel')]
    ]
    for before, after in comparisons:
        if before.receipt['request'] != after.receipt['request'] or len(before.frames) != len(after.frames):
            raise ValueError(f'Comparison directions have different recorded inputs: {before.key}, {after.key}')
    wheel = set_of(lod_root, 'auto-warm', ('slow-warm-z6', 'rapid-z6', 'motion-z6', 'date-z6',
                                'fast-jump-alps-corner', 'fast-jump-coast-corner',
                                'threshold', 'wheel-reversal'))
    wheel += set_of(lod_root, 'auto-cold', ('alps-cold',)) + set_of(lod_root, 'auto-over-budget', ('overflow',))
    fixed = set_of(fixed_root, 'fixed-z6', ('alps-z6', 'coast-z6', 'date-z6', 'alps-oblique'))
    return {'z6-detail-shelves.mp4': comparisons, 'z6-detail-wheel.mp4': wheel,
            'z6-detail-fixed.mp4': fixed}


def raster_stats(raw, size):
    width, height = size
    colors = np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 4)[24:-24, 24:-24, :3]
    # Player-visible changes include normal-range RGB and approximate luminance gradients.
    luminance = (colors[..., 0].astype(np.float32) * .2126
                 + colors[..., 1] * .7152 + colors[..., 2] * .0722)
    metrics = (*colors.mean((0, 1)), luminance.mean(),
               np.abs(np.diff(luminance, axis=1)).mean(), np.abs(np.diff(luminance, axis=0)).mean())
    return [round(float(value), 3) for value in metrics]


def png_frame(raw, size):
    return Image.frombytes('RGBA', size, raw).convert('RGB')


def prepare_clip_meta(clip):
    receipt = sanitize(clip.receipt)
    receipt['raster_metrics'] = dict(columns=METRICS, inset_pixels=24, values=[])
    return receipt


def playback(path, segments, clip_meta):
    compare = len(segments[0]) == 2
    width, height = 1280, (360 if compare else 720) + 36
    if any(clip.size != (1280, 720) for segment in segments for clip in segment):
        raise ValueError(f'Unexpected viewport for {path.name}')
    cmd = [str(FFMPEG), '-hide_banner', '-loglevel', 'error', '-n', '-f', 'rawvideo',
           '-pix_fmt', 'rgb24', '-s', f'{width}x{height}', '-r', str(FPS), '-i', '-',
           '-vf', 'format=yuv420p', '-c:v', 'libx264', '-preset', 'fast', '-crf', '20',
           '-threads', '2', '-movflags', '+faststart', str(path)]
    kept = []
    text_font = font(16)
    start = 0
    with subprocess.Popen(cmd, stdin=subprocess.PIPE) as encoder:
        for segment in segments:
            count = len(segment[0].frames)
            kept.append({'clips': [clip.key for clip in segment],
                         'first_output_frame_zero_based': start, 'frame_count': count})
            for clip in segment:
                clip_meta[clip.key] = prepare_clip_meta(clip)
            for index in range(count):
                pane = Image.new('RGB', (width, height), (23, 28, 36))
                draw = ImageDraw.Draw(pane)
                for column, clip in enumerate(segment):
                    raw = clip.frames[index].read_bytes()
                    content = png_frame(raw, clip.size)
                    state = clip.receipt['frames'][index]
                    lmax = state['terrain']['draw_max_level']
                    clip_meta[clip.key]['raster_metrics']['values'].append(raster_stats(raw, clip.size))
                    name = clip.key.split('/')[-1]
                    place = CLIP_LABELS.get(name, name)
                    kind = ('原 Z6' if column == 0 else '候选 Z6') if compare else None
                    if compare:
                        content = content.resize((640, 360), Image.Resampling.LANCZOS)
                    left = 640 * column
                    draw.text((left + 9, 5), ' · '.join(filter(None, (
                        place, kind, f'实绘最高 Z{lmax}', f'{state["mpp"]:.0f} 米／像素',
                        f'{index+1}/{count}',
                    ))), font=text_font, fill='white')
                    pane.paste(content, (left, 36))
                encoder.stdin.write(pane.tobytes())
            start += count
        encoder.stdin.close()
        if encoder.wait():
            raise RuntimeError(f'ffmpeg failed: {path.name}')
    return kept


def publish_motion(out, release, sets, plan, pictures, formal, stills_origin, coverage_origin):
    baseline, candidate = sets['z6-detail-shelves.mp4'][0]
    rows = []
    for n in (0, 39, 45, 100):
        row = []
        for clip, tag in [(baseline, '原 Z6'), (candidate, '候选 Z6')]:
            state = clip.receipt['frames'][n]
            label = f'{tag} · 帧 {n+1} · {state["mpp"]:.0f} 米／像素 · 实绘最高 Z{state["terrain"]["draw_max_level"]}'
            row.append((png_frame(clip.frames[n].read_bytes(), clip.size), label))
        rows.append(row)
    sheet(out / 'antarctic-lod.jpg', rows, 600)

    clips = {}
    videos = {name: {'playback_fps': FPS, 'segments': playback(release / name, sets[name], clips)}
              for name in sets}
    stills = {}
    for group, files in pictures.items():
        for name, path in files.items():
            receipt = sanitize(read(path.with_suffix('.json')))
            if 'png' in receipt.get('extra', {}):
                receipt['extra']['png'] = f'{group}/{path.name}'
            stills[f'{group}/{name}'] = receipt
    formal_results = {key: sanitize(read(folder / 'formal.json')) for key, folder in formal.items()}
    metadata = dict(
        capture_sources={'ice_shelf_stills': stills_origin, 'coverage_stills': coverage_origin},
        replay_elapsed_ms_note='The per-frame ms value is elapsed in the offscreen replay with readback. '
                               'Use the formal presentation intervals for live frame-time measurement.',
        sampling_plan=sanitize(plan), stills=stills, frame_clips=clips,
        videos=videos, formal=formal_results,
    )
    with gzip.open(release / 'z6-detail-frames.json.gz', 'wt', encoding='utf-8') as file:
        json.dump(metadata, file, ensure_ascii=False, separators=(',', ':'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stills-from',
                        default='capture-stills-final' if (STAGE / 'capture-stills-final').is_dir()
                        else 'capture-stills-all')
    parser.add_argument('--coverage-from', help='Explicit source if equivalent coverage stills are reused.')
    parser.add_argument('--motion-from', help='One directory with all three motion suites.')
    for suite in ('shelves', 'lod', 'fixed'):
        parser.add_argument(f'--{suite}-motion-from', help=f'Recorded directory for the {suite} suite.')
    parser.add_argument('--formal-run', help='Paired before/after run suffix. Defaults to the latest complete pair.')
    parser.add_argument('--output', default='media', help='Local output directory name inside the stage.')
    parser.add_argument('--only-stills', action='store_true')
    args = parser.parse_args()
    if Path(args.output).name != args.output or args.output in ('.', '..'):
        parser.error('output must be one local directory name')

    formal = choose_formal(args.formal_run)
    plan, pictures = open_stills(args.stills_from, args.coverage_from, formal)
    if not args.only_stills:
        require_file(FFMPEG)
        all_motion = STAGE / 'capture-motion-all'
        roots = []
        for suite in ('shelves', 'lod', 'fixed'):
            override = getattr(args, f'{suite}_motion_from') or args.motion_from
            default = all_motion if all_motion.is_dir() else STAGE / f'capture-motion-{suite}'
            roots.append(STAGE / override if override else default)
        videos = load_video_sets(*roots)
    output = STAGE / args.output
    if output.exists():
        parser.error(f'output exists: {output}; choose a new --output')
    out = output / 'terrain-z6-detail'
    release = output / 'release'
    out.mkdir(parents=True)
    release.mkdir()
    publish_stills(out, release, plan, pictures)
    if not args.only_stills:
        publish_motion(out, release, videos, plan, pictures, formal,
                       args.stills_from, args.coverage_from or args.stills_from)


if __name__ == '__main__':
    main()
