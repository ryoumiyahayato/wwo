"""Live native WWO preview while Codex edits the actual project sources.

Run: python tools/dev/preview.py --godot PATH_TO_GODOT
No export, shared override, external repository sync, or domain simulation here.
"""
from __future__ import annotations

import argparse
from collections import OrderedDict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import subprocess
import threading
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
import uuid
import socket

ROOT = Path(__file__).resolve().parents[2]


def write_json(path: Path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False), encoding="utf-8")
    temporary.replace(path)


class Preview:
    def __init__(self, args):
        self.args = args
        self.folder = ROOT / "local-artifacts" / f"dev-preview-{args.port}"
        self.folder.mkdir(parents=True, exist_ok=True)
        self.control = self.folder / "control.json"
        self.response = self.folder / "control.json.response.json"
        self.resume = self.folder / "resume.json"
        self.token = secrets.token_urlsafe(24)
        self.lock = threading.RLock()
        self.process = None
        self.instance = ""
        self.log = None
        self.inflight = None
        self.results = OrderedDict()
        self.events = deque(maxlen=40)
        self.native = {}
        self.error = ""
        self.changed = set()
        self.auto_restart = not args.snapshot
        self.generation = 0
        self.applied_generation = 0
        self.loading_generation = 0
        self.last_change = 0.0
        self.stopping = threading.Event()
        self.files = self.scan()

    def event(self, message):
        self.events.append({"time": time.strftime("%H:%M:%S"), "message": message})

    def alive(self):
        return self.process is not None and self.process.poll() is None

    def scan(self):
        # Bounded development inputs. Never walk the repository, imported cache,
        # historical output, raw GIS or another work line.
        paths = []
        for relative in ("scripts/presentation/map", "scripts/presentation/ui", "scenes/presentation", "data/presentation/localization",
                         "shaders/presentation", "assets/settlements/london_1890s", "assets/settlements/paris_reference", "assets/settlements/rouen_reference", "assets/settlements/lyon_reference", "assets/settlements/le_havre_reference"):
            paths.extend(p for p in (ROOT / relative).rglob("*")
                         if p.suffix in {".gd", ".gdshader", ".gdshaderinc", ".tscn", ".json", ".res"})
        for relative in ("scripts/formal/formal_world_application.gd", "scripts/formal/formal_world_menu.gd",
                         "scripts/presentation/formal_world_presenter.gd",
                         "scripts/simulation/simulation_step.gd", "scripts/actions/livelihood_action.gd",
                         "scripts/content/economy_development_config.gd", "scripts/content/strategic_spatial_loader.gd",
                         "data/presentation/economic_structure_1900.json",
                         "data/world_map/historical/major_state_profiles_1900.json",
                         "data/local/paris_city_reference.json", "data/local/london_city_overview.json", "data/local/rouen_city_reference.json", "data/local/lyon_city_reference.json",
                         "data/local/france_settlement_context.json", "data/local/le_havre_city_reference.json", "assets/settlements/france_context/index.json",
                         "data/local/british_settlement_context.json", "assets/settlements/british_context/index.json",
                         "data/local/iberian_settlement_context.json", "assets/settlements/iberian_context/index.json",
                         "data/local/germany_settlement_context.json", "assets/settlements/germany_context/index.json",
                         "data/local/europe_settlement_context.json", "assets/settlements/europe_context/index.json"):
            paths.append(ROOT / relative)
        paths.extend((ROOT / "scripts/world").glob("economy_*.gd"))
        for relative in ("scripts/content/world_bootstrap.gd", "scripts/content/economy_network_development.gd",
                         "scripts/world/formal_ledger_state.gd", "scripts/world/formal_personal_economy_state.gd",
                         "scripts/world/stock_lots.gd", "scripts/content/formal_economic_opening.gd"):
            paths.append(ROOT / relative)
        paths.extend((ROOT / "military_runtime/native").rglob("*.gd"))
        paths.extend((ROOT / "data/strategic/london_handoff_20261030").glob("*"))
        result = {}
        for path in paths:
            try:
                stat = path.stat()
                result[str(path)] = (stat.st_mtime_ns, stat.st_size)
            except FileNotFoundError:
                pass
        return result

    def exchange(self, payload, timeout=20):
        # One in-flight file command. A timeout never silently permits another
        # command to overwrite an action whose outcome remains unknown.
        if not self.alive():
            raise RuntimeError("原生预览未运行")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                ready = json.loads(self.control.with_name(self.control.name + ".ready.json").read_text())
            except (OSError, ValueError):
                ready = {}
            if ready.get("instance") == self.instance:
                break
            if not self.alive():
                raise RuntimeError("原生进程在就绪前退出；查看引擎日志")
            self.stopping.wait(.03)
        else:
            raise RuntimeError("原生接口尚未就绪；未提交请求")
        if self.inflight:
            try:
                previous = json.loads(self.response.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                previous = {}
            if previous.get("id") != self.inflight:
                raise RuntimeError("上一请求尚未完成；未重发或覆盖")
            self.inflight = None
        identifier = secrets.token_urlsafe(12)
        write_json(self.control, {**payload, "id": identifier})
        # A failed atomic replace never submitted the command. Only hold an
        # uncertain outcome after its command file has actually been published.
        self.inflight = identifier
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                value = json.loads(self.response.read_text(encoding="utf-8"))
                if value.get("id") == identifier:
                    self.inflight = None
                    return value.get("dev", value)
            except (OSError, ValueError):
                pass
            if not self.alive():
                raise RuntimeError("原生进程已退出；查看引擎日志")
            self.stopping.wait(.03)
        raise RuntimeError("原生请求超时；结果未知，未自动重试")

    def command(self, op, **parameters):
        # Checkpoints use formal encoding, temporary-save restore validation
        # and atomic commit. A slow valid save must not lose its restart reply.
        return self.exchange({"action": "dev", "op": op, **parameters},
                             timeout=60 if op == "checkpoint" else 20)

    def start(self):
        if self.alive():
            return {"ok": True}
        if self.log:
            self.log.close()
        self.log = (self.folder / "engine.log").open("w", encoding="utf-8")
        environment = os.environ.copy()
        self.instance = secrets.token_urlsafe(12)
        environment["WWO_DEV_INSTANCE"] = self.instance
        isolated = self.folder / "appdata"
        isolated.mkdir(exist_ok=True)
        environment["APPDATA"] = str(isolated)
        environment["LOCALAPPDATA"] = str(isolated)
        environment["XDG_DATA_HOME"] = str(isolated)
        environment["XDG_CONFIG_HOME"] = str(isolated)
        environment["XDG_CACHE_HOME"] = str(isolated)
        environment["WWO_DEV_USER_ROOT"] = isolated.as_posix()
        environment["WWO_DEV_RESUME"] = str(self.resume)
        command = [str(self.args.godot)]
        if not self.args.snapshot:
            command += ["--path", str(ROOT), "--script", "res://tools/map/native_screenshot_boot.gd"]
        command += ["--audio-driver", "Dummy", "--max-fps", "30", "--log-file", str(self.folder / "godot.log"), "--position", "60,70", "--",
                   "--dev-preview", f"--observe-file={self.control}"]
        if self.args.background:
            command.append("--dev-background")
        if self.args.opening_scenarios:
            command.append("--opening-scenarios")
        self.inflight = None
        self.native = {}
        self.process = subprocess.Popen(command, cwd=ROOT, env=environment,
            stdout=self.log, stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        self.changed.clear()
        self.loading_generation = self.generation
        self.event("已打开当前源码的实际游戏窗口")
        return {"ok": True}

    def restart(self):
        result = self.command("checkpoint")
        if not result.get("ok"):
            return result
        write_json(self.resume, result if result.get("resume") else {})
        self.exchange({"action": "quit"})
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": "原进程尚未退出；未启动第二个实例"}
        self.start()
        self.changed.clear()
        self.loading_generation = self.generation
        self.event("检查点已保存；正在从原菜单恢复，保持暂停。新规则仅影响后续")
        return {"ok": True}

    def action(self, identifier, operation, data):
        with self.lock:
            if identifier in self.results:
                previous, result = self.results[identifier]
                if previous != (operation, data):
                    raise ValueError("请求ID已用于不同内容")
                return result
            # Retain uncertain outcomes so a repeated HTTP request cannot
            # execute a clock step twice after a lost response.
            self.results[identifier] = ((operation, data), {"ok": False, "error": "OUTCOME_UNKNOWN"})
            while len(self.results) > 64:
                self.results.popitem(last=False)
            if operation == "start":
                result = self.start()
            elif operation == "show":
                self.args.background = False
                self.start()
                result = self.command("window", background=False)
            elif operation == "restart":
                result = self.restart()
            elif operation == "stop":
                result = self.command("checkpoint")
                if result.get("ok"):
                    write_json(self.resume, result if result.get("resume") else {})
                    result = self.exchange({"action": "quit"})
                    self.process.wait(timeout=5)
                    self.native = {}
            elif operation == "auto":
                self.auto_restart = bool(data.get("enabled")) and not self.args.snapshot
                result = {"ok": True}
            elif operation in {"native_click", "native_wheel", "native_drag"}:
                x, y = float(data["x"]), float(data["y"])
                if not 0 <= x <= 16384 or not 0 <= y <= 16384:
                    raise ValueError("原生视口坐标无效")
                command = {"action": "click", "x": x, "y": y}
                if operation == "native_wheel":
                    command.update(action="wheel", button=4 if bool(data.get("up", True)) else 5)
                elif operation == "native_drag":
                    end_x, end_y = float(data["to_x"]), float(data["to_y"])
                    if not 0 <= end_x <= 16384 or not 0 <= end_y <= 16384:
                        raise ValueError("原生视口坐标无效")
                    command.update(action="drag", to_x=end_x, to_y=end_y, frames=max(1,min(180,int(data.get("frames",30)))))
                result = self.exchange(command)
                result["ok"] = True
            elif operation == "capture":
                result = self.exchange({"action": "capture", "label": "development-preview"}, timeout=40)
                result["ok"] = bool(result.get("capture", {}).get("ok"))
            elif operation == "timing":
                result = self.exchange({"action":"timing"})
            elif operation in {"controls", "select", "economy", "pause", "step", "military_open", "military_close",
                               "military_pause", "military_resume", "military_status"}:
                result = self.command(operation, **data)
            else:
                raise ValueError("不支持的操作")
            self.results[identifier] = ((operation, data), result)
            while len(self.results) > 64:
                self.results.popitem(last=False)
            if not result.get("ok", True):
                self.event(str(result.get("error", "请求未完成")))
            return result

    def state(self):
        with self.lock:
            tail = ""
            path = self.folder / "engine.log"
            if path.exists():
                with path.open("rb") as stream:
                    stream.seek(max(0, path.stat().st_size - 6000))
                    tail = stream.read().decode("utf-8", errors="replace")
            return {"running": self.alive(), "pid": self.process.pid if self.alive() else None,
                "exit_code": self.process.poll() if self.process and not self.alive() else None,
                "native": self.native, "error": self.error, "events": list(self.events),
                "changed": sorted(self.changed), "generation": self.generation,
                "applied_generation": self.applied_generation, "auto": self.auto_restart,
                "source": str(self.args.godot) if self.args.snapshot else str(ROOT),
                "runtime_mode": "EXE_SNAPSHOT" if self.args.snapshot else "CURRENT_SOURCE", "log": tail}

    def watch(self):
        while not self.stopping.wait(1):
            if not self.lock.acquire(blocking=False):
                continue
            try:
                current = self.scan()
                modified = {path for path in current.keys() | self.files.keys()
                            if current.get(path) != self.files.get(path)}
                self.files = current
                source_changes = modified
                if source_changes:
                    self.changed.update(str(Path(path).relative_to(ROOT)) for path in source_changes)
                    self.generation += 1
                    self.last_change = time.monotonic()
                    self.event(f"检测到{len(source_changes)}项修改；等待稳定保存")
                if not self.alive():
                    continue
                try:
                    ready = json.loads(self.control.with_name(self.control.name + ".ready.json").read_text())
                except (OSError, ValueError):
                    ready = {}
                if ready.get("instance") != self.instance:
                    continue
                # A change in core rules or military code is never silently
                # applied to the history of a running simulation.
                display_profiles = {"data/local/london_city_overview.json", "data/local/paris_city_reference.json", "data/local/rouen_city_reference.json", "data/local/lyon_city_reference.json", "data/local/le_havre_city_reference.json", "data/local/france_settlement_context.json", "data/local/british_settlement_context.json", "data/local/iberian_settlement_context.json", "data/local/germany_settlement_context.json", "data/local/europe_settlement_context.json"}
                automatic = all(path.replace("\\", "/") in display_profiles or path.replace("\\", "/").startswith(("scripts/presentation/", "shaders/presentation/",
                    "scenes/presentation/", "assets/settlements/", "data/strategic/", "data/presentation/")) for path in self.changed)
                if self.changed and self.auto_restart and automatic and time.monotonic()-self.last_change > 1:
                    result = self.restart()
                    if not result.get("ok"):
                        self.auto_restart = False
                        self.error = str(result.get("error"))
                    continue
                status = self.command("status")
                self.native = status.get("state", {})
                if self.native.get("ready") and not self.native.get("restore_pending") and not self.native.get("map", {}).get("pending"):
                    self.applied_generation = self.loading_generation
                self.error = "" if status.get("ok") else str(status)
            except Exception as exc:
                self.error = str(exc)
            finally:
                self.lock.release()

    def close(self):
        with self.lock:
            if self.alive():
                try:
                    saved = self.command("checkpoint")
                    if saved.get("ok"):
                        write_json(self.resume, saved if saved.get("resume") else {})
                    else:
                        print("退出前未创建新检查点：" + str(saved.get("error")), flush=True)
                    self.exchange({"action": "quit"}, timeout=3)
                    self.process.wait(timeout=4)
                except (RuntimeError, subprocess.TimeoutExpired):
                    if os.name == "nt":
                        subprocess.run(["taskkill", "/PID", str(self.process.pid), "/T", "/F"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            creationflags=subprocess.CREATE_NO_WINDOW, check=False)
                    else:
                        self.process.terminate()
                    self.process.wait(timeout=5)
            self.stopping.set()
            if self.log:
                self.log.close()


class LocalPreviewServer(ThreadingHTTPServer):
    allow_reuse_address = False

    def server_bind(self):
        # Windows SO_REUSEADDR can let two helpers bind the same port and
        # race on the same native command/save paths. Claim it exclusively.
        if os.name == "nt":
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, status, value, content="application/json; charset=utf-8"):
        body = json.dumps(value, ensure_ascii=False, allow_nan=False).encode() if not isinstance(value, bytes) else value
        self.send_response(status)
        self.send_header("Content-Type", content)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; object-src 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def same_host(self):
        expected = f"127.0.0.1:{self.server.server_port}"
        if self.headers.get("Host") != expected:
            raise PermissionError("仅允许本机127.0.0.1入口")
        if self.headers.get("Origin", f"http://{expected}") != f"http://{expected}":
            raise PermissionError("请求来源不匹配")

    def do_GET(self):
        try:
            self.same_host()
            path = urlsplit(self.path).path
            preview = self.server.preview
            if path == "/api/session":
                return self.reply(200, {"token": preview.token})
            if path == "/api/state":
                return self.reply(200, preview.state())
            self.reply(404, {"message": "预览显示在原生游戏窗口；此端口仅供开发进程通信。"})
        except PermissionError as exc:
            self.reply(403, {"error": str(exc)})

    def do_POST(self):
        try:
            self.same_host()
            if self.path != "/api/control":
                return self.reply(404, {"error": "not found"})
            if not secrets.compare_digest(self.headers.get("X-WWO-Preview", ""), self.server.preview.token):
                raise PermissionError("开发会话令牌无效")
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 65536:
                raise ValueError("请求体长度无效")
            data = json.loads(self.rfile.read(size))
            identifier = data.get("id", "")
            if not isinstance(identifier, str) or not 8 <= len(identifier) <= 100:
                raise ValueError("请求ID无效")
            result = self.server.preview.action(identifier, data["op"], data.get("data", {}))
            self.reply(200, result)
        except PermissionError as exc:
            self.reply(403, {"ok": False, "error": str(exc)})
        except (ValueError, KeyError, TypeError) as exc:
            self.reply(400, {"ok": False, "error": str(exc)})
        except Exception as exc:
            self.reply(409, {"ok": False, "error": str(exc)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8791)
    parser.add_argument("--background", action="store_true", help="Existing offscreen observer; no focus or desktop cursor input")
    parser.add_argument("--snapshot", action="store_true", help="Run the supplied debug EXE without --path; source auto-reload remains disabled")
    parser.add_argument("--opening-scenarios", action="store_true", help="Expose the optional developer scenario in country selection")
    args = parser.parse_args()
    if not args.godot.is_file() or not 1024 <= args.port <= 65535:
        parser.error("需要有效Godot路径与1024—65535端口")
    try:
        server = LocalPreviewServer(("127.0.0.1", args.port), Handler)
    except OSError:
        # A user reopening the native preview reuses its existing process.
        # Never create a second game or silently send commands to another app.
        endpoint = f"http://127.0.0.1:{args.port}"
        state = json.load(urlopen(endpoint+"/api/state", timeout=3))
        expected = str(args.godot) if args.snapshot else str(ROOT)
        if state.get("source") != expected:
            raise RuntimeError("端口由其他预览占用；未启动第二个实例")
        session = json.load(urlopen(endpoint+"/api/session", timeout=3))
        request = Request(endpoint+"/api/control", data=json.dumps({"id":str(uuid.uuid4()),
            "op":"start" if args.background else "show", "data":{}}).encode(),
            headers={"Content-Type":"application/json", "X-WWO-Preview":session["token"]})
        result = json.load(urlopen(request, timeout=30))
        if not result.get("ok"):
            raise RuntimeError(str(result.get("error", "无法显示原预览窗口")))
        print("已复用现有原生预览窗口。", flush=True)
        return
    preview = Preview(args)
    server.preview = preview
    worker = threading.Thread(target=preview.watch, daemon=True)
    worker.start()
    preview.start()
    print("WWO统一Debug EXE已启动（当前导出快照）。Ctrl+C结束预览。" if args.snapshot else
          "WWO实际游戏窗口已启动。直接向Codex描述修改，源码保存后同步更新。Ctrl+C结束预览。", flush=True)
    try:
        server.serve_forever(poll_interval=.3)
    except KeyboardInterrupt:
        pass
    finally:
        preview.close()
        server.server_close()


if __name__ == "__main__":
    main()
