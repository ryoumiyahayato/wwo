"""Finite real pipe I/O samples; no simulation in this client."""
import argparse
import json
from pathlib import Path
import statistics
import time
from client import Connection, format_person


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args=parser.parse_args()
    rows=[]
    failures=[]
    for case in ["no_input", "input", "reads100", "pages", "company", "sleep10000"]:
        for sample in range(6):
            started=time.perf_counter()
            c=Connection(actor="company" if case=="company" else "squad",session="cost", measure=True, sleeping=10000 if case=="sleep10000" else 0)
            launch=time.perf_counter()-started
            try:
                c.text("advance 10");c.pump()
                if case!="no_input":
                    c.text("intent move " + ("blue_platoon" if case=="company" else "node_unit_000") + " advance B AB");c.pump()
                t=time.perf_counter();c.text("auto 1800 30");c.pump(auto=True);advance=time.perf_counter()-t
                reads=[]
                formatting=[]
                count=100 if case in {"reads100","sleep10000"} else 20 if case=="pages" else 1
                for _ in range(count):
                    t=time.perf_counter();result=c.text("look");reads.append(time.perf_counter()-t)
                    t=time.perf_counter();format_person(result);formatting.append(time.perf_counter()-t)
                    if case=="pages":
                        c.text("reports 0");c.text("events 0");c.text("receipts 0")
            finally:
                closed=c.close()
            if not closed or not closed["released"] or c.proc.returncode or any("SCRIPT ERROR" in s for s in c.raw_diagnostics):
                failures.append(f"{case}/{sample}")
            rows.append({"case":case,"sample":sample,"warmup":sample==0,"launch_and_admission_seconds":launch,
                         "read_count":count,"reads_io_seconds":sum(reads),"read_io_median_seconds":statistics.median(reads),
                         "format_seconds":sum(formatting),"auto_wall_seconds":advance,"host":closed,"client":c.costs,
                         "raw_diagnostics":c.raw_diagnostics})
        print("COST "+case,flush=True)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps({"warmups":1,"measured_samples":5,"rows":rows,"failures":failures,
        "scope":"real pipe; process launch includes engine startup; default diagnostic OFF; formatting excludes printing; input and advance costs overlap and must not be summed"},ensure_ascii=False,indent=2),encoding="utf-8")
    return 1 if failures else 0


if __name__=="__main__":
    raise SystemExit(main())
