"""Real fixed-person Windows text sessions on the existing framed client."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "interactive_observer"))
from client import Connection, ROOT, DEFAULT_GODOT

REPORT = {"checks": 0, "failures": [], "cases": [], "seeds": [71, 109, 347, 2027],
          "seed_status": "existing regression seeds; not holdout"}

def check(value, name):
    REPORT["checks"] += 1
    if not value:
        REPORT["failures"].append(name)
        print("FAIL " + name, flush=True)

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf8")

def close(c, folder):
    closed = c.close()
    check(c.proc.returncode == 0 and closed and closed["released"], folder.name + " child/world released")
    check(not any("SCRIPT ERROR" in s or "Parse Error" in s or "ERROR:" in s for s in c.raw_diagnostics), folder.name + " no runtime error")
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "host.log").write_text("\n".join(c.raw_diagnostics), encoding="utf8")
    return json.loads((folder / "debug_truth.json").read_text("utf8")), closed

def demos(output):
    cases = [("A1", "soldier", "A1", 1), ("A2", "recipient", "A2", 7),
             ("A2", "platoon", "A2_old", 31), ("A2", "soldier", "A2_soldier", 31),
             ("A3", "company", "A3", 31)]
    for seed in REPORT["seeds"]:
        for scene, actor, script, quota in cases:
            label = f"seed{seed}_{script}_{actor}"
            folder = output / "demos" / label
            record = output / "inputs" / (label + ".json")
            cmd = [sys.executable, "-B", str(HERE.parent / "interactive_observer/client.py"),
                   "--scene", scene, "--seed", str(seed), "--actor", actor, "--session", "demo_" + actor,
                   "--quota", str(quota), "--json", "--script", str(HERE / "scripts" / (script + ".txt")),
                   "--record", str(record), "--diagnostic", str(folder)]
            started = time.perf_counter()
            result = subprocess.run(cmd, cwd=ROOT, capture_output=True, timeout=180)
            folder.mkdir(parents=True, exist_ok=True)
            (folder / "person_visible.jsonl").write_bytes(result.stdout)
            (folder / "client.log").write_bytes(result.stderr)
            check(result.returncode == 0, label + " actual CLI passed")
            rows = [json.loads(line) for line in result.stdout.decode("utf8").splitlines() if line.startswith("{")]
            check(bool(rows) and rows[-1].get("program_exit", {}).get("released"), label + " cleanup")
            views = [r["person"] for r in rows if "person" in r]
            check(all(v["person_id"] == actor and v["view"] == "PERSON_VISIBLE" for v in views), label + " fixed identity restricted view")
            check(all(len(v["reports"]["entries"]) <= 20 and len(v["events"]["records"]) <= 20 for v in views), label + " bounded pages")
            check(all(claim["received_at"] <= v["time"] for v in views for claim in v["reports"]["entries"]), label + " no pre-delivery knowledge")
            proof = json.loads((folder / "debug_truth.json").read_text("utf8"))
            check(proof["ledger_balanced"] and proof["selected_script_disabled"], label + " ledger and preset disabled")
            formal = proof["formal"]
            check(formal["participant_bindings"] == {"soldier": "unit_000"}, label + " stable true membership")
            check(proof["materializations"] == 0 and formal["lod_groups"] == 2, label + " detailed leaf unrelated proxies")
            reference = output / "reference" / label
            ref = subprocess.run([DEFAULT_GODOT, "--headless", "--path", str(ROOT), "--script",
                    "res://experiments/war_resolver/interactive_observer/reference.gd", "--", str(record), str(reference)],
                    capture_output=True, timeout=180)
            reference.mkdir(parents=True, exist_ok=True)
            (reference / "host.log").write_bytes(ref.stdout + ref.stderr)
            check(ref.returncode == 0 and b"SCRIPT ERROR" not in ref.stdout + ref.stderr, label + " no-projection reference ran")
            other = json.loads((reference / "debug_truth.json").read_text("utf8"))
            check(formal == other["formal"], label + " identical input formal equals no-projection kernel")
            if scene == "A1":
                early = next(v for v in views if v["time"] == 12)
                later = next(v for v in views if v["time"] == 18)
                check(early["personal"]["state"] == "ENTERING" and later["personal"]["state"] == "COVERED", label + " original action continues")
                check(early["authority"]["relation"]["effective_parent"] == "blue_destination", label + " attachment during action")
                check(views[-1]["authority"]["relation"]["effective_parent"] == "blue_platoon", label + " expiry same session")
                check(views[-1]["personal"]["health"] < 1 and len(formal["personal_actions"]) == 2, label + " real injury without restarting actions")
            elif scene == "A2":
                old_id = "input_live_demo_platoon_old_order" if actor == "platoon" else "old_inflight_command"
                check(formal["messages"][old_id]["status"] == "REJECTED" and formal["messages"][old_id]["outcome"]["reason"] == "wrong_owner_or_layer", label + " old issued order loses delivery authority")
                shipment = formal["supply_receipts"]["finite_allocation"]
                check(shipment["status"] == "RECEIVED" and shipment["receipt_time"] == 300 and shipment["recipient_ref"] == "unit_000", label + " stable unit shipment single receipt")
                if actor == "recipient":
                    at5 = next(v for v in views if v["time"] == 5)
                    check("node_unit_000" in at5["known_targets"] and not at5["reports"]["entries"], label + " authority without old truth")
                    command = formal["messages"]["input_live_demo_recipient_new_order"]
                    check(command["sent_at"] == 170 and command["processed_at"] == 185 and command["status"] == "EXECUTED", label + " lawful new delayed order")
                    check(any(c["received_at"] >= 232 and c["source_ref"] == "local" for v in views for c in v["reports"]["entries"]), label + " new outcome arrives from actual report")
                if actor == "platoon":
                    at5 = next(v for v in views if v["time"] == 5)
                    check("node_unit_000" not in at5["known_targets"], label + " old cached authority invalidated")
                    check(any(c["received_at"] == 47 and c["observer_ref"] == "squad" for v in views for c in v["reports"]["entries"]), label + " old concrete recipient retained")
            else:
                history = formal["relationships"]
                check(len(history) == 13 and any(r["outcome"].get("kind") == "revoke" for r in history), label + " six attaches actual revoke and expiries")
                check(any(r["outcome"].get("kind") == "stale_expiry_noop" for r in history), label + " stale expiry after new attachment")
                check(views[-1]["time"] == 86400 and len(views[-1]["own_receipts"]) == 7, label + " 24h original ID history retained")
            REPORT["cases"].append({"case": label, "elapsed_seconds": time.perf_counter() - started, "calls": proof["calls"],
                                    "materializations": proof["materializations"], "formal_match": formal == other["formal"]})
            print("DEMO " + label, flush=True)

def controlled(output, name, *, seed=71, quota=31, end=3600, density=0, actor="soldier", sleeping=0):
    folder = output / "controlled" / name
    c = Connection(scene="A3", actor=actor, seed=seed, session="controlled_" + actor, quota=quota,
                   diagnostic=folder, sleeping=sleeping, capture=True)
    seen = []
    try:
        c.text(f"auto {end} 300")
        c.pump(auto=True, query_every=density, callback=lambda row: seen.append(row["person"]))
        check(c.last_program["last_committed_time"] == end, name + " no-input AUTO end")
        c.send("look")
    finally:
        proof, closed = close(c, folder)
    check(proof["ledger_balanced"] and proof["formal"]["attachments"] == {}, name + " six pairs restore and conserve")
    check(len(proof["formal"]["relationships"]) == 12, name + " no duplicate structure")
    check(proof["formal"]["participant_bindings"] == {"soldier": "unit_000"} and proof["materializations"] == 0, name + " no membership reconstruction")
    write(folder / "inputs.json", {"scene": "A3", "seed": seed, "actor": actor, "session": c.sid, "quota": quota, "sleeping": sleeping, "packets": c.packets})
    write(folder / "person_pages.json", seen[:20])
    REPORT["cases"].append({"case": name, "end": end, "calls": proof["calls"], "packet_count": len(c.packets), "query_density": density})
    return proof

def protocol(output):
    folder = output / "protocol"
    c = Connection(scene="A2", actor="company", session="protocol", quota=1, diagnostic=folder)
    try:
        first = c.text("attach a node_unit_000 blue_destination 5 100")
        c.pump()
        check(first["ok"] and c.send("receipts")["page"]["records"][0]["status"] == "STRUCTURE_SCHEDULED", "received differs from applied")
        check(c.text("attach a node_unit_000 blue_destination 5 100")["duplicate"], "same request ID")
        check(not c.text("attach a node_unit_000 blue_destination 6 100")["ok"], "conflict ID")
        old = c.send("look")["person"]
        row = c.text("advance 6")
        check(row["program"]["pending"], "actual kernel pending")
        check(c.send("look")["person"] == old, "pending old committed view")
        check(not c.text("revoke r node_unit_000 1")["ok"], "pending retry denied")
        c.pump()
        check(c.send("receipts")["page"]["records"][0]["status"] == "STRUCTURE_APPLIED", "ready applied receipt")
        check(not c.wire({"session": "old", "seq": c.seq + 1, "op": "attach", "args": {}})["ok"], "old session denied")
        check(not c.send("attach", {"id": "actor", "target": "node_unit_000", "parent": "blue_destination", "delay": 1, "duration": 20, "actor": "recipient"})["ok"], "cannot switch actor")
        check(not c.text("attach invalid node_unit_000 blue_destination -1 5")["ok"], "past delay denied")
        check(not c.text("attach invalid node_unit_000 blue_destination 1 nan")["ok"], "nonfinite denied")
        c.text("advance 294")
        c.pump()
        row = c.text("attach b node_unit_000 blue_destination 5 500")
        c.pump()
        check(row["ok"], "ready legal retry")
        c.text("advance 300")
        c.pump()
        row = c.text("revoke r node_unit_000 5")
        c.pump()
        check(row["ok"], "same fixed actor revoke")
        c.text("advance 5")
        c.pump()
        check(any(r["id"] == "r" and r["status"] == "STRUCTURE_REVOKED" for r in c.send("receipts")["page"]["records"]), "real revoke receipt")
        # Pure pages/focus/look have the same committed boundary and no receipt reset.
        time_before = c.last_program["last_committed_time"]
        for _ in range(20):
            c.text("look")
            c.text("reports")
            c.text("events")
            c.text("receipts")
            c.text("focus blue_destination")
        check(c.last_program["last_committed_time"] == time_before, "pure reads no clock advance")
    finally:
        proof, closed = close(c, folder)
    check(proof["formal"]["attachments"] == {} and proof["ledger_balanced"], "protocol final conserved restored")
    other = output / "ordinary_negative"
    c = Connection(scene="A2", actor="soldier", session="ordinary", quota=31, diagnostic=other)
    try:
        check(c.text("attach forbidden node_unit_000 blue_destination 5 20")["ok"], "ordinary attempt receipt")
        c.pump()
        check(c.send("receipts")["page"]["records"][0]["status"] == "INPUT_REJECTED", "ordinary person cannot use structural authority")
        check(c.start["person"]["person_id"] == "soldier", "new parent never takes client actor")
    finally:
        close(c, other)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--long", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    try:
        demos(args.output)
        protocol(args.output)
        sparse = controlled(args.output, "sparse")
        dense = controlled(args.output, "dense", density=1)
        check(sparse["formal"] == dense["formal"], "query density exact formal")
        large = controlled(args.output, "sleep10000", sleeping=10000, density=1)
        check(large["reader_work"]["unit_table_scans"] == 0 and large["reader_work"]["materializations"] == 0, "ten thousand unrelated areas no query scan/materialization")
        if args.long:
            for seed in (71, 109):
                reference = None
                for quota in (0, 1, 7, 31):
                    proof = controlled(args.output, f"long{seed}_q{quota}", seed=seed, quota=quota, end=86400)
                    if reference is None:
                        reference = proof["formal"]
                    else:
                        check(proof["formal"] == reference, "24h normal/quota exact " + str(seed) + "/" + str(quota))
    except BaseException as error:
        REPORT["failures"].append(type(error).__name__ + ": " + str(error))
        raise
    finally:
        REPORT["passed"] = not REPORT["failures"]
        write(args.output / "E2E_RESULTS.json", REPORT)
    print(json.dumps({"checks": REPORT["checks"], "failures": REPORT["failures"], "passed": REPORT["passed"]}), flush=True)
    return 0 if REPORT["passed"] else 1

if __name__ == "__main__":
    raise SystemExit(main())
