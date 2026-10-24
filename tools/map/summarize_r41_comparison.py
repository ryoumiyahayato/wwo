"""Summarize only the explicitly authorized finite R41 native measurements."""
import csv, json, math, statistics
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "local-artifacts/r41_performance"
LABELS = ["A1", "A2", "A3", "B2", "B3", "B4", "C1", "C2", "C3", "AF1", "BF1", "CF1"]

def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def quantile(values, p):
    values = sorted(values)
    x = (len(values)-1)*p
    i = int(x)
    return values[i] + (values[min(i+1,len(values)-1)]-values[i])*(x-i)

def distribution(values):
    if not values: return None
    return {"samples":len(values),"median":statistics.median(values),"p95":quantile(values,.95),"p99":quantile(values,.99),"maximum":max(values)}

def timing(events, start, end, place=None):
    subset = [e for e in events if place is None or e["details"].get("place")==place]
    starts = [e for e in subset if e["event"]==start]
    ends = [e for e in subset if e["event"]==end]
    return (ends[0]["ticks_us"]-starts[0]["ticks_us"])/1e6 if starts and ends else None

def main():
    runs, pooled = {}, {case:defaultdict(list) for case in ["A","B","C","AF","BF","CF"]}
    for label in LABELS:
        directory = ART / label
        if not (directory/"events.json").exists(): continue
        events = read(directory/"events.json")
        process, gpu, run = read(directory/"process.json"), read(directory/"gpu.json"), read(directory/"run.json")
        if isinstance(gpu,dict): gpu = [gpu]
        event_by_name = {e["event"]:e for e in events}
        row = {"exit_code":run["exit_code"],"duration":run["end_unix"]-run["start_unix"],"exe_to_menu":event_by_name["menu_usable"]["unix"]-run["start_unix"],
               "selection_first":timing(events,"start_clicked","sphere_first_visible"),"selection_complete":timing(events,"start_clicked","political_interactive"),
               "enter_world":timing(events,"enter_clicked","world_usable"),"first_region_publish":timing(events,"first_region_requested","first_region_canvas_visible"),
               "foreground_sample_percent":100*sum(x["foreground"] for x in process)/len(process),"stages":[],"local":{},"phases":{},"process":{},"gpu":{}}
        stages = [e for e in events if e["event"]=="selection_stage"]
        for i,e in enumerate(stages[:-1]): row["stages"].append([e["details"]["stage"],(stages[i+1]["ticks_us"]-e["ticks_us"])/1e6])
        for e in events:
            if e["event"]=="local_ready":
                name = e["details"]["place"]
                row["local"][name] = {"ready_seconds":timing(events,"local_requested","local_ready",name),"first_model_seconds":timing(events,"local_requested","local_first_model",name),"resources":e["details"]["resources"]}
        frame_groups = defaultdict(list)
        previous_phase = ""
        with (directory/"frames.csv").open(encoding="utf8",newline="") as handle:
            for frame in csv.DictReader(handle):
                phase = frame["phase"]
                value = float(frame["frame_interval_ms"])
                if value>0 and phase!="capture_excluded" and previous_phase!="capture_excluded":
                    frame_groups[phase].append(value)
                    pooled[label[:2] if "F" in label else label[0]][phase].append(value)
                previous_phase = phase
        row["phases"] = {k:distribution(v) for k,v in frame_groups.items()}
        for key in ["working_bytes","private_bytes","cpu_machine_percent","cpu_one_core_percent"]:
            row["process"][key] = distribution([x[key] for x in process if key in x])
        for key in ["dedicated_bytes","shared_bytes","gpu_3d_busiest_percent"]:
            row["gpu"][key] = distribution([x[key] for x in gpu if x.get(key) is not None])
        row["checkpoints"] = {}
        for e in events:
            if e["event"]=="snapshot" or e["event"]=="political_interactive":
                name = e["details"].get("label",e["event"])
                nearby = [x for x in process if abs(x["unix"]-e["unix"])<=1.0]
                row["checkpoints"][name] = {"resources":e["details"],"process":min(nearby,key=lambda x:abs(x["unix"]-e["unix"])) if nearby else None}
        row["simulation"] = event_by_name["simulation_unchanged"]["details"]
        row["script_error_count"] = (directory/"runtime.log").read_text(encoding="utf8").count("SCRIPT ERROR:")
        runs[label] = row
    result = {"runs":runs,"pooled_frames":{case:{phase:distribution(values) for phase,values in phases.items()} for case,phases in pooled.items()}}
    (ART/"summary.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf8")
    for label,row in runs.items():
        print(label,"menu",round(row["exe_to_menu"],3),"selection",round(row["selection_complete"],3),"world",round(row["enter_world"],3),"foreground",round(row["foreground_sample_percent"],1),"errors",row["script_error_count"])
    for case,phases in result["pooled_frames"].items():
        for phase in ["world_rotation","world_region_zoom","paris_pan","london_pan","zermatt_pan","giza_pan","paris_revisit_pan"]:
            print(case,phase,phases.get(phase))

if __name__=="__main__": main()
