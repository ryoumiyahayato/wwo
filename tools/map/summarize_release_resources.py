"""Summarize local Release probe evidence; never ships with the game."""
from pathlib import Path
import json
import statistics
import sys


def median(values):
    values = [float(x) for x in values if x is not None]
    return statistics.median(values) if values else None


def summarize(directory):
    root = Path(directory)
    results = json.loads((root / "results.json").read_text(encoding="utf8"))
    samples = [json.loads(line) for line in (root / "system.jsonl").read_text(encoding="utf-8-sig").splitlines() if line]
    stages = []
    for stage in results["stages"]:
        start = stage["start_sec"]
        finish = start + stage["duration_sec"]
        # The OS reader tags its sample with the latest 1 Hz in-app timestamp.
        # Discard transition edges for steady-state medians, retain raw evidence.
        trim = 5 if stage["duration_sec"] >= 30 else 0
        os_rows = [r for r in samples if r["stage"] == stage["name"] and start + trim <= r["t_sec"] <= finish - 1]
        game_rows = [r for r in results["rows"] if r["stage"] == stage["name"] and start + trim <= r["t_sec"] <= finish - 1]
        row = {"stage": stage["name"], "duration_s": stage["duration_sec"], "os_samples": len(os_rows), "app_samples": len(game_rows)}
        for name in ("cpu_pct", "process_gpu_pct", "nvidia_gpu_pct", "nvidia_power_w", "working_set", "private_bytes", "dedicated_gpu_bytes", "shared_gpu_bytes"):
            row[name] = median([r.get(name) for r in os_rows])
        for name in ("tracked_ram", "video_bytes", "buffer_bytes", "texture_bytes", "draw_calls", "primitives", "engine_fps", "last_submit_usec"):
            row[name] = median([r.get(name) for r in game_rows])
        row.update({key: stage[key] / 1000 for key in ("p50_usec", "p95_usec", "p99_usec", "max_usec")})
        row["fps_from_loop_median"] = 1000 / row["p50_usec"]
        if game_rows:
            first, last = game_rows[0], game_rows[-1]
            row["draw_frames_delta"] = last["frames_drawn"] - first["frames_drawn"]
            for counter in ("render_draw_count", "view_update_count", "cpu_projection_count"):
                if first.get(counter) is not None and last.get(counter) is not None:
                    row[counter + "_delta"] = last[counter] - first[counter]
            row["resident_lods"] = last["available_lods"]
            row["resident_payload_bytes"] = last["load_metrics"].get("resident_gpu_buffer_bytes")
            row["visible_places"] = last["places"]
            row["local"] = last["local"]
            row["load_metrics"] = last["load_metrics"]
        stages.append(row)
    summary = {"adapter": results["adapter"], "debug": results["debug"], "save_unchanged": results["save_unchanged"], "schema": results["schema"], "stages": stages, "transitions": results["transitions"]}
    (root / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf8")
    print("stage | CPU% | process GPU% | board W | WS MiB | render MiB | calls | p95 ms")
    for r in stages:
        def show(key, scale=1):
            return "n/a" if r.get(key) is None else f"{r[key] / scale:.2f}"
        print(" | ".join([r["stage"], show("cpu_pct"), show("process_gpu_pct"), show("nvidia_power_w"), show("working_set", 1048576), show("video_bytes", 1048576), show("draw_calls"), show("p95_usec")]))
    return summary


if __name__ == "__main__":
    for directory in sys.argv[1:]:
        summarize(directory)
