#!/usr/bin/env python3
"""Thin process/provenance driver; all physics runs in pinned Godot GDScript."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
VERSION = "4.6.3.stable.official.7d41c59c4"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="/usr/local/bin/godot")
    parser.add_argument("--scenario", default="main")
    parser.add_argument("--seed", type=int, default=71)
    parser.add_argument("--seconds", type=float, default=1800.0)
    parser.add_argument("--quota", type=int, default=0)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    for key, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        directory = args.output.resolve() / ".xdg" / folder
        directory.mkdir(parents=True)
        env[key] = str(directory)
    engine_version = subprocess.check_output([args.godot, "--version"], text=True, env=env).strip()
    if engine_version != VERSION:
        raise RuntimeError(f"Pinned engine required, got {engine_version}")
    command = [args.godot, "--headless", "--path", str(ROOT), "--script", "res://experiments/war_resolver/continuity/run.gd", "--", "--scenario", args.scenario, "--seed", str(args.seed), "--seconds", str(args.seconds), "--quota", str(args.quota)]
    completed = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=1800)
    log = completed.stdout + completed.stderr
    (args.output / "godot.log").write_text(log, encoding="utf-8")
    official = (ROOT / "tools/run_validation.ps1").read_text(encoding="utf-8-sig")
    fatal = re.search(re.search(r"\$parseErrorPattern = '([^']+)'", official)[1], log)
    matches = re.findall(r"^WAR_CONTINUITY_RESULT_JSON=(.*)$", log, re.M)
    report = {"command": command, "exit": completed.returncode, "fatal": fatal[0] if fatal else None,
              "code_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "engine": engine_version, "source_digest": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT / "experiments/war_resolver").rglob("*") if p.suffix in [".gd", ".py"]},
              "complete": len(matches) == 1 and completed.returncode == 0 and fatal is None}
    if report["complete"]:
        result = json.loads(matches[0])
        (args.output / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        (args.output / "timeline.txt").write_text(result["timeline"]+"\n", encoding="utf-8")
        print(json.dumps({"time": result["game_time"], "ledger_balanced": result["ledger_balanced"], "trace_records": len(result["trace"]), "wall_ms": result["wall_ms"]}, ensure_ascii=False))
    (args.output / "provenance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    return 0 if report["complete"] else 1


if __name__ == "__main__":
    sys.exit(main())
