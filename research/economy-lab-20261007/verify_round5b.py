"""Executable release contracts plus two byte-exact complete 39-case replays.

Run all six historical verification entry points as well.
"""
import argparse
import json
from pathlib import Path
import platform
import sys
import tempfile
import time
from verify_baseline import execute, write_record
from verify_round3 import output_hashes

ROOT=Path(__file__).resolve().parent
ROUND=ROOT/"economy_quantity_lab/release_round5b"


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,default=ROOT/".local")
    parent=parser.parse_args().output_dir.resolve()
    if parent==ROOT or parent.is_relative_to(ROOT/"economy_quantity_lab") or parent.is_relative_to(ROOT/"docs"):
        parser.error("choose a directory outside source/evidence")
    parent.mkdir(parents=True,exist_ok=True)
    directory=Path(tempfile.mkdtemp(prefix="round5b-verification-",dir=parent))
    record=dict(python=sys.version,platform=platform.platform(),status="failed",checks=[],run_directory=str(directory))
    started=time.perf_counter()
    try:
        expected=json.loads((ROUND/"evidence/hash_manifest.json").read_text(encoding="utf-8"))["files"]
        execute("round5b_tests",ROUND,["-m","unittest","-v","test_planning_release.py"],directory,record,45)
        for name in ("replay_a","replay_b"):
            execute(name,ROOT,[str(ROUND/"run_executable_planning_experiment.py"),"--output-dir",str(directory/name),
                              "--execution-log",str(directory/(name+"_execution.json"))],directory,record)
            actual=output_hashes(directory/name)
            if actual!=expected:
                changed=sorted(k for k in set(actual)|set(expected) if actual.get(k)!=expected.get(k))
                raise RuntimeError(f"Round5B byte/file-set mismatch: {changed}")
            log=json.loads((directory/(name+"_execution.json")).read_text(encoding="utf-8"))
            if (log["case_count"],log["case_days"],log["max_quantity_residual"],log["max_order_residual"])!=(39,23400,0,0):
                raise RuntimeError("execution metadata mismatch")
            gate=json.loads((directory/name/"execution_gate.json").read_text(encoding="utf-8"))
            if gate["EXECUTABLE_PLANNING_GATE"]!="PASS" or not all(gate["checks"].values()):
                raise RuntimeError("executable planning gate failed")
            record[name]=dict(files_reproduced=len(actual),summary_sha256=actual["summary.csv"],cases=39,days=23400,
                              EXECUTABLE_PLANNING_GATE="PASS")
            print(f"{name}: {len(actual)} files directly byte-identical; summary {actual['summary.csv']}",flush=True)
        record["status"]="passed"; return 0
    except (OSError,RuntimeError,ValueError,KeyError) as error:
        record["error"]=str(error); print(f"FAILED: {error}",file=sys.stderr); return 1
    finally:
        record["elapsed_seconds"]=time.perf_counter()-started
        write_record(directory/"verification.json",record)
        print(f"Round5B verification {record['status']}: {directory/'verification.json'}",flush=True)


if __name__=="__main__": sys.exit(main())
