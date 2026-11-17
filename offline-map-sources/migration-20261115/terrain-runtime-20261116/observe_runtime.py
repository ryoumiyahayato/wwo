import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import time
import uuid

ROOT = Path(__file__).parent
DATA = Path("D:/programs/WWO/wwo/local-artifacts/strategic-map-phase4/natural-terrain-preview/data")
CANDIDATE = ROOT.parent / "terrain-quality-20261115/recovered-candidate/worldcrs84quad-15s-v2"
POINTS = {"alps": (11.25, 46.4), "tibet": (89, 33), "antimeridian": (179.85, -17.5),
          "north-pole": (179.8, 89.5), "south-pole": (179.8, -89.5)}


class Game:
    def __init__(self, args, folder):
        self.path = ROOT / folder
        self.path.mkdir()
        cmd = [str(ROOT / (args.exe + ".exe")), "--play" if args.formal else "--terrain-review",
               "--data", str(DATA), "--observe", str(self.path / "map.json")]
        if args.formal:
            cmd += ["--background", "--preferences", str(self.path / "preferences.json")]
        if not args.legacy:
            cmd += ["--terrain-candidate", str(CANDIDATE)]
        self.profile = "TerrainRT-" + uuid.uuid4().hex[:12]
        with (self.path / "stderr.txt").open("w", encoding="utf-8") as stderr:
            self.process = subprocess.Popen(cmd, env={**os.environ, "WWO_RUST_PROFILE": self.profile},
                                            stdout=stderr, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)

    def command(self, action="status", timeout=18, **fields):
        uid = uuid.uuid4().hex
        payload = {"id": uid, "action": action, **fields}
        temp = self.path / "pending.json"
        temp.write_text(json.dumps(payload), encoding="utf-8")
        deadline = time.monotonic() + timeout
        while True:
            try:
                temp.replace(self.path / "map.json")
                break
            except PermissionError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(.02)
        while time.monotonic() < deadline:
            try:
                data = json.loads((self.path / "map.response.json").read_text(encoding="utf-8"))
                if data["id"] == uid:
                    return data
            except (FileNotFoundError, PermissionError, json.JSONDecodeError):
                pass
            if self.process.poll() is not None:
                raise RuntimeError(f"game exited {self.process.returncode}: {self.path}")
            time.sleep(.025)
        raise TimeoutError(f"{action}: {self.path}")

    def ready(self, predicate, timeout=40):
        start = time.monotonic()
        state = None
        while time.monotonic()-start < timeout:
            try:
                state = self.command(timeout=3)["state"]
            except TimeoutError:
                continue
            if predicate(state):
                return state
        raise TimeoutError(f"{self.path}: {state}")

    def stop(self):
        if self.process.poll() is None:
            try:
                self.command("quit", timeout=3)
                self.process.wait(timeout=4)
            except (RuntimeError, TimeoutError, subprocess.TimeoutExpired):
                if self.process.poll() is None:
                    self.process.terminate()
                    self.process.wait(timeout=4)

    def save(self, name, data):
        (self.path / (name+".json")).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def ramps(values, steps):
    out = [values[0]]
    for left, right in zip(values, values[1:]):
        out.extend(left*(right/left)**(i/steps) for i in range(1, steps+1))
    return out


def replay(game, site, scales, label, establish_z4=False):
    lon, lat = POINTS[site]
    if establish_z4:
        game.command("focus", lon=lon, lat=lat, mpp=5200, value="north")
        game.ready(lambda s: s["terrain"]["selected_ready"] and s["terrain"]["target_level"] == 4)
    game.command("focus", lon=lon, lat=lat, mpp=scales[0], value="north")
    start = game.ready(lambda s: s["first_frame_ms"] is not None and s["terrain"]["selected_ready"]
                       and abs(s["mpp"]-scales[0]) < .001)
    if establish_z4:
        assert start["projection"] == "orthographic" and start["terrain"]["target_level"] == 4, start
    answer = game.command("zoom-replay", timeout=55, scales=scales, label=label)
    assert len(answer["extra"]["frames"]) == len(scales), answer.keys()
    game.save(label, {"start": start, "request": {"lon": lon, "lat": lat, "scales": scales},
                      "end": answer["state"], **answer["extra"]})
    print(label, len(scales), [(round(f["mpp"]), f["terrain"]["target_level"], f["terrain"]["view_max_level"],
                              f["terrain"]["required_detail_pages"], f["terrain"].get("viewport_detail_pages"))
                            for f in answer["extra"]["frames"] if math.isclose(f["mpp"], 6200, rel_tol=1e-8)][:3], flush=True)


def gpu_sample(game):
    pid = game.process.pid
    cmd = (f"$p=Get-Process -Id {pid}; "
           f"$gpu=Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory "
           f"-Filter \"Name LIKE 'pid_{pid}_%'\"; "
           "[pscustomobject]@{cpu=$p.CPU;working=$p.WorkingSet64;private=$p.PrivateMemorySize64;"
           "gpu=@($gpu | Select-Object Name,DedicatedUsage,SharedUsage)} | ConvertTo-Json -Compress -Depth 4")
    cmd = cmd.replace('\"', '"')
    done = subprocess.run(["pwsh", "-NoProfile", "-NonInteractive", "-Command", cmd],
                          check=True, capture_output=True, encoding="utf-8")
    return json.loads(done.stdout)


def formal(game, captures):
    home = game.ready(lambda s: s["first_frame_ms"] is not None and s["lobby"] and s["lobby"]["ready"])
    assert home["window"]["background"] and not home["window"]["focused"], home["window"]
    game.command("key", value="Enter")
    game.ready(lambda s: s["lobby"] and s["lobby"]["selection_ready"])
    game.command("key", value="Enter")
    start = game.ready(lambda s: s["session"] and s["session"]["player"] and s["terrain"], timeout=55)
    assert start["session"]["paused"], start["session"]
    modes = {}
    w, h = start["viewport"]
    lon, lat = POINTS["alps"]
    for mode in ("geographic", "political", "economic", "military"):
        if mode == "military":
            game.command("click", x=w/2, y=h-50)
            game.command("click", x=w/2, y=h-min(78, max(52, .056*w))-87.5)
        else:
            game.command("key", value=mode[0])
        reached = game.ready(lambda s: s["mode"] == mode, timeout=7)
        print("formal", mode, reached["viewport"], reached["window"], flush=True)
        game.command("focus", lon=lon, lat=lat, mpp=5200, value="north")
        stable = game.ready(lambda s: s["terrain"]["selected_ready"] and abs(s["mpp"]-5200)<.01)
        game.command("timing")
        if mode == "geographic":
            time.sleep(2.5)
            fixed = game.command("timing")["extra"]
            game.command("timing")
        else:
            fixed = None
        observed = []
        for amount in [-0.887, 0.887, 3.0, 3.0, 3.0, -3.0, -3.0, -3.0, -0.887, 0.887]*2:
            moment = game.command("wheel", x=w/2, y=h/2, steps=amount)["state"]
            observed.append({k: moment[k] for k in ("mode","mpp","terrain","window")})
        final_samples = game.command("timing")
        # Sample the actual WDDM process allocation at the end of a common motion path.
        memory = gpu_sample(game)
        if captures and mode != "geographic":
            game.command("focus", lon=2.35, lat=48.86, mpp=1900, value="north")
            game.ready(lambda s: s["terrain"]["selected_ready"])
            game.command("capture", label=mode)
            png = game.path / (mode+".png")
            for _ in range(80):
                if png.exists():
                    with png.open("rb") as f:
                        if png.stat().st_size>12:
                            f.seek(-12, 2)
                            if f.read(12)==b"\x00\x00\x00\x00IEND\xaeB`\x82":
                                break
                time.sleep(.06)
        assert all(not x["window"]["focused"] for x in observed), observed
        modes[mode] = {"stable": stable, "zoom": observed, "timing": final_samples["extra"],
                       "end": final_samples["state"], "fixed": fixed, "memory": memory}
        game.save("formal", {"profile":game.profile, "home":home, "start":start, "modes":modes})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("exe")
    parser.add_argument("folder")
    parser.add_argument("--formal", action="store_true")
    parser.add_argument("--legacy", action="store_true")
    parser.add_argument("--captures", action="store_true")
    parser.add_argument("--alps-only", action="store_true")
    args = parser.parse_args()
    app = Game(args, args.folder)
    try:
        if args.formal:
            formal(app, args.captures)
        else:
            repeat = ramps([5750,6200],4)[1:]+[6200]*4+ramps([6200,5750],4)[1:]+[5750]*4
            replay(app, "alps", [5750]*6+repeat*4+[6200]*16, "alps-z4-budget", establish_z4=True)
            if not args.alps_only:
                for site in POINTS:
                    path=[28500, 3000, 360, 1450, 530, 4700, 6200, 11000, 28500]
                    replay(app,site,ramps(path,8)+[28500]*8,site+"-rapid")
    finally:
        app.stop()
