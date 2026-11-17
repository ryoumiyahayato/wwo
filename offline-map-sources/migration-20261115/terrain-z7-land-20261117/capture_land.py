from pathlib import Path
import sys

stage = Path(__file__).resolve().parent
visual = stage.with_name("terrain-z7-visual-20261116")
detail = stage.with_name("terrain-z7-detail-20261116")
sys.path[:0] = [str(visual), str(detail)]
import capture_visual as visual_capture
import formal_local as formal
from capture_z7_pages import at_camera

visual_capture.cap.STAGE = stage
Host = visual_capture.Host
load = visual_capture.cap.data
save = visual_capture.cap.save
baseline = visual / "inland-water-final" / "candidate"
candidate = stage / "global-candidate"

fixed = {
    "erhai": (100.202, 25.8, 165),
    "erhai-basin": (100.202, 25.8, 390),
    "alps": (14.765625, 47.109375, 515),
    "alps-valley": (14.765625, 47.109375, 240),
    "amazon": (-60.02, -3.17, 280),
    "amazon-river": (-60.02, -3.17, 140),
    "namib": (15.41, -24.47, 285),
    "namib-dunes": (15.41, -24.47, 155),
    "alps-corner": (11.25, 46.40625, 250),
    "dateline": (179.75, -16.8, 330),
    "north-pole": (0, 90, 50),
    "south-pole": (0, -90, 50),
    "ross-front": visual_capture.cap.SHELVES["ross-front"],
    "vistula-outlet": (18.943, 54.335, 38),
    "prairie": (-101.9, 48.4, 420),
    "australia": (133.5, -23.6, 430),
}
# Retain the previously frozen random camera set for a same-camera comparison.
plan = load(detail / "z7-sample-plan.json")
random_views = {
    f"random-{i}-{scale}": (site["lon"], site["lat"], site[f"{scale}_mpp"])
    for i, site in enumerate(plan["random"], 1)
    for scale in ("regional", "close")
}

def stills():
    remaining = {name: pose for name, pose in (fixed | random_views).items()
                 if not (stage / "final-after" / f"{name}-samples.json").is_file()}
    for label, pack, cameras in (
        ("final-after-rest", candidate, remaining),
        ("final-controls", baseline, {key: view for key, view in fixed.items()
                                      if not (stage / "pilot-before" / f"{key}.png").is_file()} | random_views),
    ):
        with Host(label, pack, fixed=True) as host:
            for name, pose in cameras.items():
                if abs(pose[1]) == 90:
                    camera = dict(lon=pose[0], lat=pose[1], mpp=pose[2], value="north")
                    focused = host.talk("focus", **camera)["state"]
                    if abs(focused["pitch_degrees"]) >= 1e-6:
                        host.talk("key", value="v")
                        host.talk("focus", **camera)
                    for _ in range(180):
                        state = host.talk("status")["state"]
                        if at_camera(state, *pose) and state["terrain"]["selected_ready"]:
                            break
                    else:
                        raise TimeoutError((name, state))
                    row = host.snapshot(name)
                else:
                    row = host.still(name, pose)
                terrain = row["state"]["terrain"]
                assert terrain["selected_ready"] and terrain["z7_view_weight"] == 1, (name, terrain)
                row = host.talk("terrain-samples")
                for point in row["extra"]["samples"]:
                    sample = point["terrain"]
                    if sample:
                        assert not sample["missing_exact_page"], (name, point)
                save(host.directory / f"{name}-samples.json", row)

def dynamics():
    request = load(visual / "z7-lakes-dynamic-after" / "wakatipu-wheel.json")["request"]
    polar = load(visual / "motion-after" / "polar-budget.json")["request"]
    scales, moves = request["scales"], request["moves"]
    for label, pack in (("final-motion-before", baseline), ("final-motion-after", candidate)):
        with Host(label, pack, replay=True) as host:
            host.replay("alps-wheel", 11.25, 46.40625, scales, moves)
        with Host(label+"-cold", pack, replay=True) as host:
            host.replay("polar-budget", polar["lon"], polar["lat"], polar["scales"], polar["moves"], prewarm=False)

def native():
    for label, pack in (("native-before", baseline), ("native-after", candidate)):
        with Host(label, pack, native=True) as host:
            formal.sequence(host, False)
            host.talk("key", value="g")
            assert host.talk("status")["state"]["mode"] == "geographic"
            host.still("alps-native", fixed["alps"])

if __name__ == "__main__":
    for step in sys.argv[1:]:
        {"stills": stills, "dynamics": dynamics, "native": native}[step]()
