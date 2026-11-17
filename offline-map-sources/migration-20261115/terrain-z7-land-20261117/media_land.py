from pathlib import Path
import json
import statistics
import subprocess
import zipfile

import imageio_ffmpeg

stage = Path(__file__).resolve().parent
archive = stage / "archive"
archive.mkdir(exist_ok=True)
for label, name, video in (
    ("final-motion-before", "alps-wheel", "z7-land-material-alps-before.mp4"),
    ("final-motion-after", "alps-wheel", "z7-land-material-alps-after.mp4"),
    ("final-motion-after-cold", "polar-budget", "z7-land-material-polar-budget.mp4"),
):
    directory = stage / label
    rows = json.loads((directory / f"{name}.json").read_bytes())["frames"]
    images = sorted((directory / name).glob("*.rgba"))
    assert len(images) == len(rows), (label, name)
    with subprocess.Popen(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error",
         "-f", "rawvideo", "-pixel_format", "rgba", "-video_size", "1280x720", "-framerate", "20",
         "-i", "pipe:0", "-pix_fmt", "yuv420p", "-c:v", "libx264", "-threads", "2",
         "-crf", "19", "-movflags", "+faststart", str(archive / video)],
        stdin=subprocess.PIPE,
    ) as process:
        with process.stdin as pixels:
            for image in images:
                pixels.write(image.read_bytes())
        if process.wait():
            raise RuntimeError(video)
    terrain = [row["terrain"] for row in rows]
    times = sorted(b["ms"] - a["ms"] for a, b in zip(rows, rows[1:]))
    samples = [point["terrain"] for row in rows for point in row["samples"]["samples"] if point["terrain"]]
    print(label, name, len(rows),
          "viewport", max(row["viewport_detail_pages"] for row in terrain),
          "needs", max(row["required_detail_pages"] for row in terrain),
          "resident", max(row["resident_detail_pages"] for row in terrain),
          "missing", sum(point["missing_exact_page"] for point in samples),
          "p50/p95", round(statistics.median(times), 2), round(times[(len(times)*95-1)//100], 2))

with zipfile.ZipFile(archive / "z7-land-material-originals.zip", "w") as evidence:
    for group in ("pilot-before", "final-controls", "final-after", "final-after-rest", "final-motion-before",
                  "final-motion-after", "final-motion-before-cold", "final-motion-after-cold",
                  "native-before", "native-after"):
        for path in sorted((stage / group).iterdir()):
            if not path.is_file() or path.suffix not in (".png", ".json"):
                continue
            if path.name in ("preferences.json", "map.json", "map.response.json"):
                continue
            compression = zipfile.ZIP_DEFLATED if path.suffix == ".json" else zipfile.ZIP_STORED
            evidence.write(path, path.relative_to(stage), compress_type=compression)
