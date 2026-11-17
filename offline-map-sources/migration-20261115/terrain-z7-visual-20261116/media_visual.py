from pathlib import Path
import gzip
import json
import shutil
import subprocess
import sys
import zipfile

from PIL import Image, ImageDraw
from capture_visual import cases, work

assets=work/"media"
archive=work/"archive"
assets.mkdir(exist_ok=True)
archive.mkdir(exist_ok=True)
stills=("before-original","before-pr152","after-refined")
for name in cases:
    paths=[work/version/(name+".png") for version in stills]
    assert all(path.is_file() for path in paths), name
    output=Image.new("RGB",(1536,310), "#11191c")
    draw=ImageDraw.Draw(output)
    for col,(path,version) in enumerate(zip(paths,stills)):
        with Image.open(path) as picture:
            output.paste(picture.convert("RGB").resize((512,288),Image.Resampling.LANCZOS),(512*col,22))
        draw.text((512*col+8,4),f"{name} | {version} | {cases[name][2]} m/px",fill="#e5eef2")
    output.save(assets/(name+".jpg"),quality=91,optimize=True)

if "--stills-only" in sys.argv:
    raise SystemExit

with zipfile.ZipFile(archive/"z7-visual-site-png.zip","w",compression=zipfile.ZIP_STORED) as zip_file:
    for version in stills:
        for name in cases:
            for extension in ("png","json"):
                source=work/version/(name+"."+extension)
                zip_file.write(source,source.relative_to(work))
    for source in sorted((work/"page-results/poles").iterdir()):
        if source.suffix in (".png", ".json"):
            zip_file.write(source, Path("poles") / source.name)

player=work.parents[1]/"python-libs/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
paths=[]
for group in ("motion-after","motion-cold","motion-after-fixed","motion-before","motion-before-fixed"):
    folder=work/group
    for path in sorted(folder.glob("*.json")):
        if (folder/path.stem).is_dir():
            paths.append(path)
with gzip.open(archive/"z7-visual-motion.json.gz","wt",encoding="utf-8",compresslevel=5) as file:
    json.dump({str(path.relative_to(work)):json.loads(path.read_text(encoding="utf-8"))
               for path in paths},file,separators=(",",":"))
for group,name in (("motion-after","alps-530-970"),("motion-after","ross-front"),
                   ("motion-after","polar-budget"),("motion-after","dateline"),
                   ("motion-after-fixed","ross-ice-corner"),
                   ("motion-after","zoom-pan-rotate"),("motion-cold","cold-alps"),
                   ("motion-before","alps-530-970"),("motion-before","ross-front")):
    folder=work/group/name
    suffix = "-pr152" if group == "motion-before" else ""
    frames=sorted(folder.glob("*.rgba"))
    assert frames,name
    row=json.loads((folder.parent/(name+".json")).read_text(encoding="utf-8"))
    assert len(row["frames"])==len(frames),(name,len(row["frames"]),len(frames))
    with subprocess.Popen([str(player),"-y","-loglevel","error","-f","rawvideo",
                           "-pixel_format","rgba","-video_size","1280x720","-framerate","20",
                           "-i","pipe:0","-pix_fmt","yuv420p","-c:v","libx264","-threads","2",
                           "-crf","19","-movflags","+faststart",str(archive/f"z7-visual-{name}{suffix}.mp4")],
                           stdin=subprocess.PIPE) as process:
        for frame in frames:
            data=frame.read_bytes()
            assert len(data)==1280*720*4,(name,frame,len(data))
            process.stdin.write(data)
        process.stdin.close()
        if process.wait():
            raise RuntimeError(name)
for filename in ("ice-edges-local.json","ice-cutoff-local.json","source-points-local.json","z7-visual-global.json"):
    shutil.copyfile(work/filename,archive/(filename if filename.startswith("z7-") else f"z7-visual-{filename}"))
shutil.copyfile(work/"ice-gpu-points-local.json",archive/"z7-visual-ice-gpu-points-local.json")
shutil.copyfile(work/"candidate/index.json",archive/"z7-visual-index.json")




