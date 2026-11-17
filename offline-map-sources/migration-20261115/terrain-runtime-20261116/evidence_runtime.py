import json
from pathlib import Path
import subprocess
import sys

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).parent
W, H = 1280, 720
SITES = ("alps", "tibet", "antimeridian", "north-pole", "south-pole")


def read(run, name):
    return json.loads((ROOT / run / (name+".json")).read_text(encoding="utf-8"))


def frame(run, name, index):
    path = ROOT / run / name / f"{index:04}.rgba"
    return np.fromfile(path, dtype="u1").reshape(H, W, 4)[..., :3]


def range_values(values):
    out = []
    for value in values:
        if not out or out[-1] != value:
            out.append(value)
    return out


def report(run, name):
    series = read(run, name)
    frames = series["frames"]
    old, old_row = None, None
    previous_transition = []
    exact_black_around_center = 0
    diagnostic = 0
    repeated_at_same_zoom = []
    for idx, row in enumerate(frames):
        img = frame(run, name, idx)
        diagnostic += int(np.count_nonzero((img[...,0]==255)&(img[...,1]==0)&(img[...,2]==255)))
        crop = img[100:585, 200:1080]
        if row["mpp"] <= 6500.:
            exact_black_around_center = max(exact_black_around_center, int(np.count_nonzero(np.all(crop==0, axis=2))))
        if old is not None and abs(old_row["mpp"]-row["mpp"]) < .01:
            delta = np.abs(crop.astype("int16")-old)
            repeated_at_same_zoom.append((idx+1, round(float(np.mean(np.max(delta, axis=2)>18))*100, 2)))
        old, old_row = crop.astype("int16"), row
        terrain = row["terrain"]
        curr_transition = [terrain["target_level"], terrain["view_max_level"]]
        if not previous_transition or previous_transition[-1][1:]!=curr_transition:
            previous_transition.append([idx+1, *curr_transition])
    return {
        "frames": len(frames), "duration_s": round(frames[-1]["ms"]/1000, 2),
        "camera": series["request"], "target_view_changes": previous_transition,
        "max_black_pixels_map_roi_at_mpp_le_6500": exact_black_around_center,
        "magenta_pixels_whole_sequence": diagnostic,
        "same_camera_large_change_pct_for_top_frames": sorted(repeated_at_same_zoom, key=lambda item: -item[1])[:6],
        "points_6200": [
            {"frame": idx+1, "target":row["terrain"]["target_level"],"view_max":row["terrain"]["view_max_level"],
             "required":row["terrain"]["required_detail_pages"],"viewport":row["terrain"].get("viewport_detail_pages"),
             "drawn_center":row["samples"]["samples"][0]["terrain"]["contributors"]}
            for idx,row in enumerate(frames) if abs(row["mpp"]-6200)<.01],
    }


def label(draw, start_x, row, tag, i, total):
    t = row["terrain"]
    vis = t.get("viewport_detail_pages")
    center = row["samples"]["samples"][0]["terrain"]
    level = "+".join(f"Z{k[0]} {w:.0%}" for k,w in center["contributors"]) if center else "-"
    caption = f"{tag}   {i+1:03d}/{total:03d}   {row['mpp']:.0f} m/px   target Z{t['target_level']}   view Z{t['view_max_level']}   center {level}"
    draw.text((start_x+12, H+7), caption, fill="white")
    caption = f"viewport {vis if vis is not None else '-'}   incl. prefetch {t['required_detail_pages']}   selected {t['wanted_detail_pages']}/{t['detail_capacity']}"
    draw.text((start_x+12,H+23), caption, fill="#a8cbde")


def encode(output, clips, paired):
    width = W*2 if paired else W
    call = [imageio_ffmpeg.get_ffmpeg_exe(),"-v","error","-y","-f","rawvideo","-pixel_format","rgb24",
            "-video_size",f"{width}x{H+46}","-framerate","30","-i","-","-an","-c:v","libx264","-threads","2",
            "-crf","20","-preset","veryfast","-pix_fmt","yuv420p","-movflags","+faststart"]
    if paired:
        call += ["-vf","scale=1920:-2"]
    proc = subprocess.Popen(call + [str(ROOT / output)], stdin=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        for clip in clips:
            series = [(run,name,tag,read(run,name)["frames"]) for run,name,tag in clip]
            for i in range(len(series[0][3])):
                image = Image.new("RGB",(width,H+46),"#15202b")
                draw = ImageDraw.Draw(image)
                for side,(run,name,tag,frames) in enumerate(series):
                    image.paste(Image.fromarray(frame(run,name,i)),(side*W,0))
                    label(draw,side*W,frames[i],tag,i,len(frames))
                proc.stdin.write(image.tobytes())
    finally:
        proc.stdin.close()
    if proc.wait():
        raise RuntimeError(output)


if __name__=="__main__":
    before, after = "before-orthographic", "after"
    name = "alps-z4-budget"
    records = {"before":{name:report(before,name)}, "after":{
        key:report(after,key) for key in [name]+[site+"-rapid" for site in SITES]}}
    (ROOT/"terrain-runtime-zoom.json").write_text(json.dumps(records,indent=2),encoding="utf-8")
    if "--encode" in sys.argv:
        encode("terrain-runtime-z4.mp4", [[(before,name,"PR #142"),(after,name,"Viewport priority")]], True)
        encode("terrain-runtime-rapid.mp4", [[(after,site+"-rapid",site)] for site in SITES], False)
