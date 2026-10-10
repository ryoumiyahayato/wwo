"""Requested Windows process E2E. Uses the real text parser and framed host."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from client import Connection, ROOT, DEFAULT_GODOT, FRAME, parse

SUMMARY = {"checks": 0, "failures": [], "cases": [], "seeds": [71, 109, 347, 2027], "seed_status": "regression; not holdout"}


def check(value, label):
    SUMMARY["checks"] += 1
    if not value:
        SUMMARY["failures"].append(label)
        print("FAIL " + label, flush=True)


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def finish(c, folder):
    closed = c.close()
    check(c.proc.returncode == 0 and closed and closed["released"], folder.name + " actual child cleanup")
    check(not any("SCRIPT ERROR" in s or "Parse Error" in s for s in c.raw_diagnostics), folder.name + " no script fatal")
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "host_diagnostics.log").write_text("\n".join(c.raw_diagnostics), encoding="utf-8")
    proof = json.loads((folder / "debug_truth.json").read_text())
    check(proof["selected_script_disabled"], folder.name + " selected script disabled")
    check(proof.get("ledger_balanced", False), folder.name + " shared ledger balanced")
    return proof, closed


def demos(output):
    for seed in SUMMARY["seeds"]:
        for scene, actor, quota in [("S1", "squad", 31), ("S2", "platoon", 7), ("S3", "soldier", 1), ("S1", "company", 31)]:
            label = f"seed{seed}_{actor}"
            folder = output / "demos" / label
            script = ROOT / "experiments/war_resolver/interactive_observer/scripts" / (("company" if actor == "company" else scene) + ".txt")
            record = output / "inputs" / (label + ".json")
            command = [sys.executable, "-B", str(Path(__file__).with_name("client.py")), "--scene", scene, "--actor", actor,
                       "--seed", str(seed), "--session", "regression_" + actor, "--quota", str(quota), "--script", str(script),
                       "--json", "--record", str(record), "--diagnostic", str(folder)]
            started = time.perf_counter()
            result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=120)
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "person_visible.jsonl").write_bytes(result.stdout)
            (folder / "client_diagnostics.log").write_bytes(result.stderr)
            check(result.returncode == 0, label + " actual CLI return code")
            rows = [json.loads(s) for s in result.stdout.decode("utf-8").splitlines() if s.startswith("{")]
            check(rows[-1].get("program_exit", {}).get("released"), label + " actual world released")
            proof = json.loads((folder / "debug_truth.json").read_text())
            check(proof["ledger_balanced"] and proof["selected_script_disabled"], label + " ledger and binding")
            views = [s["person"] for s in rows if "person" in s]
            check(all(s["person_id"] == actor for s in views), label + " one fixed identity")
            check(all(s["view"] == "PERSON_VISIBLE" and len(s["reports"]["entries"]) <= 20 and len(s["events"]["records"]) <= 20 for s in views), label + " restricted bounded views")
            check(all(c["received_at"] <= s["time"] for s in views for c in s["reports"]["entries"]), label + " no report before delivery")
            reference = output / "reference" / label
            ref = subprocess.run([DEFAULT_GODOT, "--headless", "--path", str(ROOT), "--script",
                "res://experiments/war_resolver/interactive_observer/reference.gd", "--", str(record), str(reference)], capture_output=True, timeout=120)
            reference.mkdir(parents=True, exist_ok=True)
            (reference / "host_diagnostics.log").write_bytes(ref.stdout + ref.stderr)
            check(ref.returncode == 0 and b"SCRIPT ERROR" not in ref.stdout + ref.stderr, label + " headless reference ran")
            other = json.loads((reference / "debug_truth.json").read_text())
            check(proof["formal"] == other["formal"], label + " exact formal contract equals no-projection headless reference")
            facts = {}
            if scene == "S1":
                receipt = next(s["receipt"] for s in rows if "receipt" in s)
                check(receipt["received_at"] == 10 and receipt["delivery_time"] == 25 and receipt["status"] == "ISSUED_WAITING", label + " receipt is not execution")
                check(proof["formal"]["units"]["unit_000"]["distance_moved"] > 0, label + " input actually changes motion")
                facts = {"input": 10, "delivery": 25}
            if scene == "S2":
                before = next(s for s in views if s["time"] == 100)
                check(not any(c["fact_kind"] == "route" and c["claimed_value"].get("state") == "BLOCKED" for c in before["reports"]["entries"]), label + " broken bridge still unknown before report")
                after = next(s for s in views if s["time"] == 170)
                blocked = next(c for c in after["reports"]["entries"] if c["fact_kind"] == "route" and c["claimed_value"].get("state") == "BLOCKED")
                check(blocked["observed_at"] == 100 and blocked["received_at"] == 147, label + " observation and report delay retained")
                check(proof["formal"]["messages"]["old_authority"]["outcome"]["reason"] == "wrong_owner_or_layer", label + " delivery-time authority rejection retained")
                receipt = next(s["receipt"] for s in rows if "receipt" in s)
                check(receipt["received_at"] == 170 and receipt["delivery_time"] == 185, label + " later runtime detour goes through radio")
                check(proof["formal"]["units"]["unit_000"]["spatial"]["node"] == "D", label + " detour reaches actual destination")
                facts = {"bridge_damage": 60, "observation": blocked["observed_at"], "received": blocked["received_at"], "input": 170, "delivery": 185}
            if scene == "S3":
                early = next(s for s in views if s["time"] == 12)
                later = next(s for s in views if s["time"] == 18)
                check(early["personal"]["state"] == "ENTERING" and later["personal"]["state"] == "COVERED", label + " cover effect requires real traversal")
                check(later["own_receipts"][0]["status"] == "ACTION_FINISHED", label + " own finish feedback arrives")
                check(views[-1]["personal"]["health"] < 1, label + " real injury continues")
                check(any(s.get("error") == "command_id_conflict" for s in rows), label + " conflicting duplicate denied")
                facts = {"input": 10, "entered_at": later["own_receipts"][0]["personal_feedback"]["effective_time"], "final_health": views[-1]["personal"]["health"]}
            SUMMARY["cases"].append({"case": label, "elapsed_seconds": time.perf_counter()-started, "calls": proof["calls"], "facts": facts})
            print("DEMO " + label, flush=True)


def run_case(output, name, *, scene="S1", actor="squad", quota=31, seed=71, inputs=True, density=0, until=1800, bridge_clear=False):
    folder = output / "contrasts" / name
    c = Connection(scene=scene, actor=actor, seed=seed, session="compare_" + actor, quota=quota, diagnostic=folder, bridge_clear=bridge_clear)
    seen = []
    try:
        c.text("advance 10")
        c.pump()
        if density:
            for _ in range(100):
                row = c.text("look")
                if len(seen) < 2:
                    seen.append(row)
        if inputs:
            row = c.text("personal cover take_cover" if actor == "soldier" else "intent move node_unit_000 advance B AB")
            check(row.get("ok"), name + " parser accepted runtime input")
            c.pump()
        c.text("auto " + str(until) + " 30")
        c.pump(auto=True, query_every=density)
        final = c.text("look")
        seen.append(final)
        check(final["person"]["time"] == until and final["program"]["clock"] == "PAUSED", name + " finite AUTO stops")
    finally:
        proof, closed = finish(c, folder)
    write(folder / "person_visible.json", seen)
    write(folder / "program_exit.json", closed)
    return proof


def contrasts(output, long_run):
    for scene, actor in [("S1", "squad"), ("S3", "soldier")]:
        for seed in SUMMARY["seeds"]:
            base = run_case(output, f"{actor}_{seed}_noquery", scene=scene, actor=actor, seed=seed)
            sparse = run_case(output, f"{actor}_{seed}_sparse", scene=scene, actor=actor, seed=seed, density=17)
            dense = run_case(output, f"{actor}_{seed}_dense", scene=scene, actor=actor, seed=seed, density=1)
            check(base["formal"] == sparse["formal"] == dense["formal"], f"{actor}_{seed} dense sparse noquery exact formal equality")
            noinput = run_case(output, f"{actor}_{seed}_noinput", scene=scene, actor=actor, seed=seed, inputs=False)
            if actor == "squad":
                check(noinput["formal"]["units"]["unit_000"]["distance_moved"] == 0 < base["formal"]["units"]["unit_000"]["distance_moved"], f"{actor}_{seed} no hidden valid player script")
            else:
                a = noinput["formal"]["units"]["unit_000"]["gameplay_personnel"]["members"]["soldier"]
                b = base["formal"]["units"]["unit_000"]["gameplay_personnel"]["members"]["soldier"]
                check(0 < b["injury"] < a["injury"], f"{actor}_{seed} runtime cover changes same actual injury ledger")
            check(noinput["formal"]["units"]["unit_002"]["ammo_spent"] > 0, f"{actor}_{seed} other active combat runs without player")
    base = run_case(output, "quota_normal", quota=0)
    for q in (1, 7, 31):
        item = run_case(output, "quota_"+str(q), quota=q)
        check(base["formal"] == item["formal"], f"host normal and quota{q} exact formal equality")
    if long_run:
        base = run_case(output, "host24h_normal_noquery", quota=0, until=86400)
        for q in (1, 7, 31):
            item = run_case(output, f"host24h_quota{q}_reads", quota=q, density=97, until=86400)
            check(base["formal"] == item["formal"], f"24h query/quota{q} exact formal equality")
            SUMMARY["cases"].append({"case": f"host24h_quota{q}", "time": item["formal"]["time"], "calls": item["calls"], "persistent_host": item["persistent_host"]})


def protocol(output):
    folder = output / "protocol"
    c = Connection(quota=1, session="pending_test", diagnostic=folder)
    evidence = []
    try:
        initial = c.text("look")["person"]
        row = c.text("advance 100")
        check(row["status"] == "PENDING", "actual wire PENDING")
        check(c.text("look")["person"] == initial, "wire partial state hidden")
        check(c.text("intent retry node_unit_000 advance B AB")["error"] == "PENDING_RETRY_WHEN_READY", "wire no pending input queue")
        evidence.append(c.text("pause"))
        c.pump()
        row = c.text("intent retry node_unit_000 advance B AB")
        check(row["receipt"]["received_at"] == 100, "wire explicit retry not backfilled")
        c.pump()
        duplicate = c.text("intent retry node_unit_000 advance B AB")
        check(duplicate.get("duplicate"), "wire same command deduplicates")
        check(c.text("intent retry node_unit_000 hold A")["error"] == "command_id_conflict", "wire same id conflict")
        evidence.extend([row, duplicate])
        before = c.text("look")["person"]
        check(c.wire({"session": "old", "seq": c.seq+1, "op": "personal", "args": {"id": "bad", "action": "wait"}})["error"] == "wrong_session", "wire old session denied")
        check(c.wire({"session": c.sid, "seq": c.seq+1, "op": "look", "args": {}, "actor": "company"})["error"] == "invalid_envelope", "wire actor envelope denied")
        check(c.send("personal", {"id": "bad", "action": "wait", "rank": "general"})["error"] == "invalid_personal_shape", "wire rank spoof denied")
        check(c.send("advance", {"seconds": "30"}).get("error"), "wire illegal numeric type denied")
        for line in ["advance -1", "advance nan", "look actor", "personal z fly", "x"*2049, "intent z a advance B " + ",".join(["AB"]*65)]:
            check(not c.text(line).get("ok"), "text malformed or long denied: " + line[:30])
        check(c.wire(None)["error"] == "invalid_json_frame", "non-object frame denied")
        c.proc.stdin.write(b"{"+b"?"*(FRAME-1));c.proc.stdin.flush()
        check(c.receive()["error"] == "invalid_json_frame", "malformed fixed frame denied")
        after = c.text("look")["person"]
        check(before == after, "invalid wire frames cannot alter person world")
        for _ in range(100):
            c.text("reports");c.text("events");c.text("receipts")
        check(c.text("look")["person"] == after, "wire bounded paging preserves world and knowledge")
    finally:
        finish(c, folder)
    write(folder/"person_visible.json", evidence)
    # Same received Knowledge with different hidden bridge truth, actual processes.
    a = Connection(scene="S2", actor="platoon", session="hidden_same")
    b = Connection(scene="S2", actor="platoon", session="hidden_same", bridge_clear=True)
    try:
        for c in (a,b):
            c.text("advance 80");c.pump()
        check(a.text("look")["person"] == b.text("look")["person"], "actual processes equal lawful view despite hidden bridge")
        check(a.text("focus red_secret") == b.text("focus red_secret"), "actual unknown catalog errors do not disclose hidden truth")
        check(a.text("intent blind node_unit_000 advance D AB,bridge_BD") == b.text("intent blind node_unit_000 advance D AB,bridge_BD"), "actual provider admits the same received-knowledge intent despite hidden truth")
    finally:
        for c in (a,b):
            closed=c.close();check(closed and closed["released"], "counterfactual child stopped")
    # Explicit EOF while a bounded operation is pending.
    c = Connection(session="eof_pending", quota=1)
    c.text("advance 100")
    c.proc.stdin.close();c.proc.wait(timeout=20);c.reader.join(timeout=2)
    check(c.closed_record and c.closed_record["released"] and c.proc.returncode == 0, "PENDING EOF releases actual child")
    c.proc.stdout.close()


def remaining_actions(output):
    for kind, node, path in [("hold", "A", ""), ("withdraw", "C", "AC"), ("cancel", "-", "")]:
        folder=output/"actions"/kind
        c=Connection(session="action_"+kind, diagnostic=folder)
        try:
            c.text("advance 10");c.pump()
            row=c.text(f"intent action node_unit_000 {kind} {node} {path}")
            check(row["receipt"]["status"]=="ISSUED_WAITING", "real text "+kind+" issued")
            c.text("auto 1800 30");c.pump(auto=True)
            view=c.text("look")["person"]
            check(view["own_receipts"][0]["status"]=="DELIVERED_ACCEPTED", "real text "+kind+" delivery checks")
        finally:
            proof,closed=finish(c,folder)
        unit=proof["formal"]["units"]["unit_000"]
        mission=proof["formal"]["missions"][unit["mission_id"]]
        if kind=="cancel":
            check(mission["status"]=="cancelled", "text cancellation is real mission cancellation")
        elif kind=="withdraw":
            check(unit["spatial"]["node"]=="C" and mission["status"]=="complete", "text withdrawal actually reaches known destination")
        write(folder/"person_visible.json",view)
    folder=output/"actions"/"personal_wait"
    c=Connection(scene="S3",actor="soldier",session="personal_wait",diagnostic=folder)
    try:
        c.text("advance 10");c.pump();c.text("personal cover take_cover");c.pump()
        c.text("advance 30");c.pump()
        row=c.text("personal follow wait");c.pump()
        check(row["receipt"]["status"]=="ACTION_STARTED", "wait actually begins returning from cover")
        c.text("advance 10");c.pump()
        view=c.text("look")["person"]
        check(view["personal"]["state"]=="FOLLOWING" and view["own_receipts"][-1]["status"]=="ACTION_FINISHED", "return to group requires same real local traversal")
    finally:
        finish(c,folder)
    write(folder/"person_visible.json",view)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--long", action="store_true")
    args=parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    started=time.perf_counter()
    try:
        demos(args.output)
        protocol(args.output)
        remaining_actions(args.output)
        contrasts(args.output,args.long)
    except BaseException as error:
        SUMMARY["failures"].append(type(error).__name__+": "+str(error))
        raise
    finally:
        SUMMARY["elapsed_seconds"]=time.perf_counter()-started
        SUMMARY["passed"]=not SUMMARY["failures"]
        write(args.output/"SESSION_RESULTS.json", SUMMARY)
        print(json.dumps({"checks":SUMMARY["checks"],"failures":SUMMARY["failures"],"elapsed_seconds":SUMMARY["elapsed_seconds"]}),flush=True)
    return 0 if SUMMARY["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
