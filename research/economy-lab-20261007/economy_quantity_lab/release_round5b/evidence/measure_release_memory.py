"""Optional two-case tracemalloc probe; compare generated daily CSV bytes."""
import argparse
import hashlib
from pathlib import Path
import sys
import time
import tracemalloc

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from run_executable_planning_experiment import make_case,run_case,write_csv,write_json,ROOT


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,required=True)
    parser.add_argument("--reference-dir",type=Path,required=True)
    args=parser.parse_args(); output=args.output_dir.resolve()
    if output.exists() or output.is_relative_to(ROOT/"economy_quantity_lab") or output.is_relative_to(ROOT/"docs"):
        parser.error("choose a new directory outside source/evidence")
    output.mkdir(parents=True); logs=[]
    for treatment,planner in (("normal","X1"),("wide","X2")):
        case=make_case(treatment,planner)
        tracemalloc.start(); started=time.perf_counter(); sim,rows=run_case(case)
        seconds=time.perf_counter()-started; peak=tracemalloc.get_traced_memory()[1]; tracemalloc.stop()
        path=output/(case["case_id"]+".csv"); write_csv(path,rows)
        prefix="A_" if treatment=="normal" else "B_"
        reference=args.reference_dir/(prefix+case["case_id"])/"daily.csv"
        assert path.read_bytes()==reference.read_bytes(),"memory instrumentation altered daily output"
        logs.append(dict(case_id=case["case_id"],seconds=seconds,peak_bytes=peak,
                         daily_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),daily_bytes_equal=True,
                         scope="fresh simulation/planning/indexes/archives and observations; excludes file export; tracemalloc allocation peak, not RSS"))
    write_json(output/"memory_log.json",logs)


if __name__=="__main__": main()
