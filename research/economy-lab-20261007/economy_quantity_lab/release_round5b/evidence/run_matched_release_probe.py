"""Reproduce the independent Wide release diagnostic with E learned on Day17."""
import argparse
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from run_executable_planning_experiment import make_case,run_case,summarize,write_json,ROOT


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,required=True)
    output=parser.parse_args().output.resolve()
    if output.exists() or output.is_relative_to(ROOT/"economy_quantity_lab") or output.is_relative_to(ROOT/"docs"):
        parser.error("choose a new file outside source/evidence")
    results=[]
    for policy in ("X0","X1","X2"):
        case=make_case("wide",policy)
        case["policy"]="Q0"
        case["information_events"]=[dict(day=17,supplier_id="E",source="matched_information_probe")]
        sim,rows=run_case(case)
        results.append(dict(scope="independent 600-day causal probe; passive E17/Q0 fixes information timing, physical Wide unchanged",
                            **summarize(case,sim,rows),discoveries=sim.discoveries))
    write_json(output,results)


if __name__=="__main__": main()
