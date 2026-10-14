"""Windows text client. Only Godot owns war state; this client parses and pumps."""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
import uuid

FRAME = 8192
MAX_TEXT = 2048
ROOT = Path(__file__).resolve().parents[3]
DEFAULT_GODOT = r"D:\Tools\Godot-4.6.3\Godot_v4.6.3-stable_win64.exe"


def parse(line: str) -> tuple[str, dict]:
    """The same parser is used for keyboard, pipe, and scripted interaction."""
    if len(line) > MAX_TEXT:
        raise ValueError("text_capacity")
    words = line.strip().split()
    if not words:
        raise ValueError("empty_command")
    op, rest = words[0], words[1:]
    if op in {"save_runtime", "load_runtime"}:
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            raise ValueError("checkpoint_path_required")
        return op, {"path": parts[1].strip('"')}
    if op == "body":
        parts = line.strip().split(None, 2)
        if len(parts) != 3:
            raise ValueError("body_parameters_required")
        parameters = json.loads(parts[2])
        if not isinstance(parameters, dict):
            raise ValueError("body_parameters_must_be_object")
        return op, {"id": parts[1], "parameters": parameters}
    if op == "person_report" and len(rest) == 3:
        return op, {"id": rest[0], "person": rest[1], "recipient": rest[2]}
    if op == "combat_report" and len(rest) == 3:
        return op, {"id": rest[0], "observation": rest[1], "recipient": rest[2]}
    if op == "forward" and len(rest) == 3:
        return op, {"id": rest[0], "message": rest[1], "recipient": rest[2]}
    if op in {"task", "reserve", "air", "naval", "land", "operation", "tactics"}:
        parts = line.strip().split(None, 3)
        if len(parts) != 4:
            raise ValueError("task_parameters_required")
        parameters = json.loads(parts[3])
        if not isinstance(parameters, dict):
            raise ValueError("task_parameters_must_be_object")
        return op, {"id": parts[1], "target": parts[2], "parameters": parameters}
    if op in {"split_members", "merge_members", "detach_children", "coarsen", "propose_move", "propose_transport", "approve_move", "cancel_move", "accept_move", "redirect_move", "vacate_position", "appoint"}:
        parts = line.strip().split(None, 3)
        if len(parts) != 4:
            raise ValueError("member_adjustment_parameters_required")
        parameters = json.loads(parts[3])
        if not isinstance(parameters, dict):
            raise ValueError("member_adjustment_parameters_must_be_object")
        return op, {"id": parts[1], "delay": float(parts[2]), "parameters": parameters}
    if op == "transfer" and len(rest) == 5:
        return op, {"id": rest[0], "delay": float(rest[4]),
                    "parameters": {"person": rest[1], "source": rest[2], "destination": rest[3]}}
    if op in {"look", "status", "help", "pause", "quit"} and not rest:
        return op, {}
    if op in {"reports", "events", "receipts"} and len(rest) <= 1:
        return op, {"before": int(rest[0]) if rest else -1}
    if op == "focus" and len(rest) == 1:
        return op, {"subject": rest[0]}
    if op == "continue_as" and len(rest) == 1:
        return op, {"person": rest[0]}
    if op == "personal" and len(rest) == 2:
        return op, {"id": rest[0], "action": rest[1]}
    if op == "attach" and len(rest) == 5:
        return op, {"id": rest[0], "target": rest[1], "parent": rest[2],
                    "delay": float(rest[3]), "duration": float(rest[4])}
    if op == "revoke" and len(rest) == 3:
        return op, {"id": rest[0], "target": rest[1], "delay": float(rest[2])}
    if op == "intent" and len(rest) in {4, 5}:
        return op, {"id": rest[0], "target": rest[1], "intent": rest[2], "node": "" if rest[2] == "cancel" and rest[3] == "-" else rest[3],
                    "path": rest[4].split(",") if len(rest) == 5 else []}
    if op == "advance" and len(rest) == 1:
        value = float(rest[0])
        if not math.isfinite(value) or value < 0:
            raise ValueError("invalid_time")
        return op, {"seconds": value}
    if op == "auto" and len(rest) in {1, 2}:
        end, step = float(rest[0]), float(rest[1]) if len(rest) == 2 else 30.0
        if not math.isfinite(end) or not math.isfinite(step) or end < 0 or step <= 0:
            raise ValueError("invalid_auto_plan")
        return op, {"until": end, "step": step}
    if op in {"resume", "tick"} and len(rest) <= 1:
        return op, {"calls": int(rest[0]) if rest else 64}
    raise ValueError("unknown_command_or_arity")


class Connection:
    def __init__(self, *, scene="S1", seed=71, actor="squad", session=None, quota=31,
                 godot=DEFAULT_GODOT, root=ROOT, diagnostic=None, measure=False,
                 sleeping=0, bridge_clear=False, capture=False,
                 second_vessel_role="opponent", supply_responses=None, autonomy_mode="events", battlefield_actions=None):
        self.sid = session or ("local_" + uuid.uuid4().hex[:16])
        self.seq = 0
        self.capture = capture
        self.packets = []
        self.responses: queue.Queue = queue.Queue(maxsize=4)
        self.raw_diagnostics: list[str] = []
        self.diagnostic_bytes = 0
        self.diagnostic_dropped = 0
        self.closed_record = None
        self.last_program = {}
        self.costs = {"io_seconds": 0.0, "format_seconds": 0.0}
        cmd = [str(godot), "--headless", "--path", str(root), "--script",
               ("res://experiments/war_resolver/attachment_continuity/server.gd"
                if scene.startswith("A") else "res://experiments/war_resolver/interactive_observer/server.gd"), "--",
               f"--scene={scene}", f"--seed={seed}", f"--actor={actor}",
               f"--session={self.sid}", f"--quota={quota}", f"--sleeping={sleeping}",
               f"--measure={str(measure).lower()}", f"--bridge_clear={str(bridge_clear).lower()}",
               f"--second_vessel_role={second_vessel_role}", f"--autonomy_mode={autonomy_mode}",
               "--supply_responses=" + json.dumps(supply_responses or {}, ensure_ascii=False),
               "--battlefield_actions=" + json.dumps(battlefield_actions or {}, ensure_ascii=False)]
        if diagnostic:
            cmd.append(f"--diagnostic={Path(diagnostic).resolve()}")
        self.proc = subprocess.Popen(cmd, cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT,
                                     creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()
        try:
            self.start = self.receive(20)
            if not self.start.get("started"):
                raise RuntimeError("host_start_failed")
        except BaseException:
            self.abort()
            raise

    def _read(self):
        try:
            while line := self.proc.stdout.readline(524289):
                if len(line) > 524288:
                    self.responses.put(RuntimeError("response_capacity"))
                    break
                text = line.decode("utf-8", errors="replace").strip()
                if text.startswith("PERSON_BOUND="):
                    self.responses.put(json.loads(text.split("=", 1)[1]))
                elif text.startswith("PERSON_BOUND_CLOSED="):
                    self.closed_record = json.loads(text.split("=", 1)[1])
                else:
                    if self.diagnostic_bytes + len(line) <= 65536:
                        self.raw_diagnostics.append(text)
                        self.diagnostic_bytes += len(line)
                    else:
                        self.diagnostic_dropped += len(line)
        except BaseException as error:
            self.responses.put(error)
        finally:
            self.responses.put(None)

    def receive(self, timeout=20):
        result = self.responses.get(timeout=timeout)
        if isinstance(result, BaseException):
            raise result
        if result is None:
            raise RuntimeError("host_eof")
        if "program" in result:
            self.last_program = result["program"]
        return result

    def wire(self, packet):
        data = json.dumps(packet, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("utf-8")
        if len(data) >= FRAME:
            raise ValueError("frame_capacity")
        if self.capture:
            if len(self.packets) >= 4096:
                raise RuntimeError("input_record_capacity")
            self.packets.append(packet)
        started = time.perf_counter()
        self.proc.stdin.write(data + b" " * (FRAME - len(data)))
        self.proc.stdin.flush()
        response = self.receive()
        self.costs["io_seconds"] += time.perf_counter() - started
        return response

    def send(self, op, args=None):
        next_seq = self.seq + 1
        response = self.wire({"session": self.sid, "seq": next_seq, "op": op, "args": args or {}})
        if response.get("seq") == next_seq:
            self.seq = next_seq
        return response

    def text(self, line):
        try:
            op, args = parse(line)
        except (ValueError, OverflowError) as error:
            return {"ok": False, "layer": "PROGRAM_STATUS", "error": str(error)}
        try:
            return self.send(op, args)
        except ValueError as error:
            return {"ok": False, "layer": "PROGRAM_STATUS", "error": str(error)}

    def pump(self, *, auto=False, query_every=0, callback=None):
        """A fixed host plan. Reads cannot choose a target or an integration step."""
        for index in range(1000000):
            pending = self.last_program.get("pending", False)
            automatic = self.last_program.get("clock") == "AUTO"
            if not pending and not automatic:
                return
            row = self.send("tick" if auto and automatic else "resume", {"calls": 64})
            if not row.get("ok"):
                raise RuntimeError("bounded_pump_blocked")
            if query_every and (index + 1) % query_every == 0:
                observed = self.send("look")
                if callback:
                    callback(observed)
        raise RuntimeError("client_pump_capacity")

    def close(self):
        if self.proc.poll() is None:
            if not self.last_program.get("closed"):
                try:
                    self.send("quit")
                except (OSError, RuntimeError, queue.Empty):
                    pass
            try:
                self.proc.stdin.close()
            except OSError:
                pass
            try:
                self.proc.wait(timeout=20)
            except subprocess.TimeoutExpired:
                self.abort()
                raise RuntimeError("host_exit_timeout")
        self.reader.join(timeout=2)
        self.proc.stdout.close()
        return self.closed_record

    def abort(self):
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait(timeout=5)
        if self.proc.stdin:
            try:
                self.proc.stdin.close()
            except OSError:
                pass


def format_person(row):
    if not row.get("ok"):
        return "程序反馈：" + str(row.get("error", "unknown"))
    lines = []
    program = row.get("program", {})
    if program:
        lines.append(f"研究时钟 {program['clock']}；PENDING={program['pending']}；已提交{program['last_committed_time']:.3f}秒。")
    view = row.get("person")
    if view:
        lines.append(f"当前控制人物 {view['person_id']}（永久军职 {view['role']}）。")
        position = view.get("current_position")
        if position:
            if position["has_position"]:
                lines.append(f"当前指挥岗位：{position['formation_id']} / {position['role']}；代理={position['acting']}。")
            else:
                lines.append("当前指挥岗位：无。")
            lines.append("行政归属：" + str(position["membership_ref"]))
        for node, office in view.get("authority", {}).get("positions", {}).items():
            lines.append(f"范围内岗位 {node}：{office['person'] or '空缺'}；代理={office['acting']}。")
        body = view["personal"]
        if "health" in body:
            lines.append(f"本人状态 {body['state']}；伤病能力余量{body['health']:.6f}；伤病量{body['injury']:.6f}。")
            lines.append("生命状态：" + str(body.get("life_state", "UNKNOWN")))
            if body.get("bleeding"):
                lines.append("持续出血：" + ("是" if body["bleeding"]["active"] else "已稳定"))
            if body.get("treatment"):
                lines.append("医疗状态：" + str(body["treatment"]["status"]))
            if body.get("transport_ref"):
                lines.append(f"转运 {body['transport_ref']}：{body.get('transport_status', '')}；搬运者 {body.get('carrier_ref', '')}。")
            lines.append(("能力份额持有单位：" if body.get("command_post") else "所属行动小组：") + str(body["unit_ref"]))
            lines.append("当前随组对象：" + (str(body.get("following_ref", body["unit_ref"])) if body["state"] == "FOLLOWING" else "尚未随组"))
            if body.get("weapon"):
                weapon = body["weapon"]
                lines.append(f"武器 {weapon['profile']['role']}：{weapon['status']} / {weapon['mode']}；准备弹药{weapon['ready']:.3f}；已消耗{weapon['spent']:.3f}。")
        else:
            lines.append("本人伤病能力：未知。")
        lines.append("可尝试：" + ", ".join(view["attemptable"]))
        for asset in view.get("air_assets", []):
            lines.append(f"航空器 {asset['asset_ref']}：{asset['status']}；位置{asset['xy']}，高度{asset['altitude_km']:.3f}km；燃料{asset['fuel']:.3f}，载荷{asset['load']:.3f}。")
        for vessel in view.get("vessels", []):
            lines.append(f"舰艇 {vessel['vessel_ref']}：{vessel['status']}；位置{vessel['xy']}；燃料{vessel['fuel']:.3f}，弹药{vessel['ammunition']:.3f}，舰体{vessel['integrity']:.3f}。")
        for transport in view.get("land_transports", []):
            lines.append(f"陆运 {transport['transport_ref']}：{transport['status']}；已报告位置{transport.get('xy', [])}；承运单位{transport['carrier_ref']}；交接点{transport['target_node']}。")
        for purpose in view.get("operations", []):
            label = purpose.get("task_ref", "目的")
            lines.append(f"作战 {purpose['operation_ref']} / {label}：{purpose['status']}；收到{purpose['learned_at']:.3f}秒。")
        for move in view.get("movements", []):
            lines.append(f"调动 {move['id']}：{move['status']}；约定地点{move['meeting']}；同行单位{move['physical_unit']}；{move['reason']}。")
        for candidate in view.get("continuity_candidates", []):
            lines.append(f"可接续人物 {candidate['person_ref']}；已有联系 {candidate['basis']}。")
        for claim in view["reports"]["entries"]:
            lines.append(f"报告 {claim['message_id']} / {claim['fact_kind']} / {claim['subject_ref']}：观察{claim['observed_at']:.3f}秒，收到{claim['received_at']:.3f}秒；" + json.dumps(claim['claimed_value'], ensure_ascii=False))
        for receipt in view["own_receipts"]:
            lines.append(f"本人输入 {receipt['id']}：{receipt['status']}；受理时刻{receipt['received_at']:.3f}秒。")
            if receipt.get("reason"):
                lines.append("处理结果：" + str(receipt["reason"]))
            if receipt.get("movement_ref"):
                lines.append("调动引用：" + str(receipt["movement_ref"]))
    elif "receipt" in row:
        receipt = row["receipt"]
        lines.append(f"本人输入 {receipt['id']}：{receipt['status']}。重复={row.get('duplicate', False)}。")
        if receipt.get("reason"):
            lines.append("处理结果：" + str(receipt["reason"]))
        if receipt.get("movement_ref"):
            lines.append("调动引用：" + str(receipt["movement_ref"]))
    elif "page" in row:
        lines.append(json.dumps(row["page"], ensure_ascii=False))
    elif "commands" in row:
        lines.extend(row["commands"])
    elif "status" in row:
        lines.append("程序反馈：" + row["status"])
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", choices=["S1", "S2", "S3", "A1", "A2", "A3"], default="S1")
    parser.add_argument("--seed", type=int, default=71)
    parser.add_argument("--actor", choices=["squad", "platoon", "soldier", "scout", "company", "recipient", "red_commander"])
    parser.add_argument("--session")
    parser.add_argument("--quota", type=int, choices=[0, 1, 7, 31], default=31)
    parser.add_argument("--godot", default=DEFAULT_GODOT)
    parser.add_argument("--script", type=Path)
    parser.add_argument("--json", action="store_true", help="Same restricted responses, machine-readable")
    parser.add_argument("--diagnostic", type=Path, help="Separate explicit DEBUG_TRUTH research output")
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--record", type=Path, help="Bounded research input record; no world truth")
    parser.add_argument("--auto-look-every", type=int, default=0)
    parser.add_argument("--sleeping", type=int, choices=range(10001), default=0)
    parser.add_argument("--bridge-clear", action="store_true", help="Research-only construction counterfactual for S2")
    parser.add_argument("--second-vessel-role", choices=["opponent", "escort"], default="opponent")
    parser.add_argument("--autonomy-mode", choices=["events", "prototype"], default="events")
    parser.add_argument("--supply-responses", type=json.loads, default={}, help="Finite NPC reactions to received sea/supply reports, by person ID")
    parser.add_argument("--battlefield-actions", type=json.loads, default={}, help="Explicit existing weapon shares, gun crews, engineering capabilities and construction sites")
    args = parser.parse_args(argv)
    actor = args.actor or {"S1": "squad", "S2": "platoon", "S3": "soldier", "A1": "soldier", "A2": "recipient", "A3": "company"}[args.scene]
    connection = Connection(scene=args.scene, seed=args.seed, actor=actor, session=args.session, quota=args.quota,
                            godot=args.godot, diagnostic=args.diagnostic, measure=args.measure,
                            sleeping=args.sleeping, bridge_clear=args.bridge_clear, capture=bool(args.record),
                            second_vessel_role=args.second_vessel_role, supply_responses=args.supply_responses, autonomy_mode=args.autonomy_mode, battlefield_actions=args.battlefield_actions)
    count = 0

    def emit(row):
        nonlocal count
        count += 1
        if count > 4096:
            raise RuntimeError("client_output_capacity")
        started = time.perf_counter()
        print(json.dumps(row, ensure_ascii=False) if args.json else format_person(row), flush=True)
        connection.costs["format_seconds"] += time.perf_counter() - started

    exit_code = 0
    try:
        emit(connection.start)
        stream = args.script.open("r", encoding="utf-8") if args.script else sys.stdin
        keyboard = stream.isatty() and os.name == "nt"
        buffer = ""
        until = time.monotonic() + 3600
        for _ in range(1000000):
            if time.monotonic() > until:
                raise RuntimeError("client_wall_time_limit")
            if keyboard and connection.last_program.get("clock") == "AUTO":
                import msvcrt
                line = None
                while msvcrt.kbhit():
                    char = msvcrt.getwch()
                    if char == "\r":
                        print()
                        line, buffer = buffer, ""
                        break
                    if char == "\b":
                        buffer = buffer[:-1]
                    elif char.isprintable():
                        buffer += char
                    if len(buffer) > MAX_TEXT:
                        buffer = ""
                        emit({"ok": False, "layer": "PROGRAM_STATUS", "error": "text_capacity"})
                if line is None:
                    result = connection.send("tick", {"calls": 64})
                    if not result.get("ok"):
                        emit(result)
                        break
                    if connection.last_program.get("clock") != "AUTO":
                        emit(result)
                    continue
            else:
                if keyboard:
                    print("wwo> ", end="", flush=True)
                line = stream.readline(MAX_TEXT + 2)
                if not line:
                    break
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if len(line) > MAX_TEXT + 1:
                emit({"ok": False, "layer": "PROGRAM_STATUS", "error": "text_capacity"})
                exit_code = 2
                break
            if line.strip() == "drain":
                connection.pump(auto=False)
                emit(connection.send("status"))
                continue
            result = connection.text(line)
            emit(result)
            if connection.last_program.get("closed"):
                break
            if not keyboard and connection.last_program.get("clock") == "AUTO":
                connection.pump(auto=True, query_every=args.auto_look_every, callback=emit)
                emit(connection.send("status"))
        if args.script:
            stream.close()
    except (RuntimeError, queue.Empty, BrokenPipeError) as error:
        emit({"ok": False, "layer": "PROGRAM_STATUS", "error": str(error)})
        exit_code = 1
    finally:
        closed = connection.close()
        if args.json:
            print(json.dumps({"program_exit": closed, "client_costs": connection.costs}), flush=True)
        elif closed:
            print("研究会话已退出；资源释放=" + str(closed["released"]), flush=True)
        if connection.proc.returncode or not closed or not closed.get("released"):
            exit_code = 1
        if any("SCRIPT ERROR" in line for line in connection.raw_diagnostics):
            exit_code = 1
        if args.diagnostic:
            args.diagnostic.mkdir(parents=True, exist_ok=True)
            (args.diagnostic / "host_diagnostics.log").write_text("\n".join(connection.raw_diagnostics), encoding="utf-8")
        if args.record:
            args.record.parent.mkdir(parents=True, exist_ok=True)
            args.record.write_text(json.dumps({"scene": args.scene, "actor": actor, "seed": args.seed, "session": connection.sid,
                "quota": args.quota, "sleeping": args.sleeping, "bridge_clear": args.bridge_clear, "packets": connection.packets}, ensure_ascii=False), encoding="utf-8")
    return exit_code


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
