"""WWO preview lifecycle. Standard library only; never starts the game.

Windows entry: tools/build_preview.ps1. No content hash audits or executable copying.
Unregistered files and source/research data are not disposable by default.
"""
from __future__ import annotations
import argparse
import contextlib
import ctypes
import json
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
POLICY = "tools/build/preview_policy.json"
REGISTRY = "builds/preview_registry.json"
PRESET = "Windows Desktop Internal Landmark Preview"
TERRAIN_MANIFEST = "tools/build/r68-relief.json"
STATES = {"CURRENT", "CANDIDATE", "ROLLBACK", "PROTECTED", "OBSOLETE"}
TAIL = 128 * 1024
LOG_BUDGET = 2 * 1024 * 1024
DIAGNOSTIC_BUDGET = 20 * 1024 * 1024
SOURCE_EXT = {".tif", ".tiff", ".shp", ".shx", ".dbf", ".prj", ".geojson", ".pdf", ".blend", ".gd", ".py", ".tscn", ".tres", ".uid"}
SOURCE_DIRS = {"source", "sources", "licenses", "licences", "dem", "cover", "trees", ".git", "revoked-r30"}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def same_write(path, text):
    """Small records only. Do not change mtimes on identical metadata."""
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("x", encoding="utf-8") as file:
        file.write(text)
    os.replace(temporary, path)
    return True


def record(st):
    return {"bytes": st.st_size, "mtime_ns": st.st_mtime_ns}


def walk(root):
    """Metadata only; do not descend through junctions or symbolic links."""
    if not root.exists():
        return
    stack = [root]
    while stack:
        directory = stack.pop()
        st = directory.lstat()
        if stat.S_ISLNK(st.st_mode) or getattr(st, "st_file_attributes", 0) & 0x400:
            continue
        with os.scandir(directory) as entries:
            for entry in entries:
                st = entry.stat(follow_symlinks=False)
                if entry.is_symlink() or getattr(st, "st_file_attributes", 0) & 0x400:
                    continue
                path = Path(entry.path)
                if stat.S_ISDIR(st.st_mode):
                    stack.append(path)
                elif stat.S_ISREG(st.st_mode):
                    yield path, st


def verify_exe(path):
    """Read PE/PCK headers and footer, not the complete PCK or its payload."""
    size = path.stat().st_size
    with path.open("rb") as f:
        dos = f.read(64)
        if len(dos) != 64 or dos[:2] != b"MZ":
            raise ValueError("Not a PE executable")
        offset = struct.unpack_from("<I", dos, 60)[0]
        if offset > size - 24:
            raise ValueError("PE header outside file")
        f.seek(offset)
        pe = f.read(6)
        if pe != b"PE\0\0\x64\x86":
            raise ValueError("Expected Windows x86-64 PE")
        f.seek(-12, 2)
        length, magic = struct.unpack("<Q4s", f.read(12))
        if magic != b"GDPC" or length <= 0 or length > size - 12:
            raise ValueError("Missing embedded Godot PCK footer")
        f.seek(size - 12 - length)
        if f.read(4) != b"GDPC":
            raise ValueError("Embedded PCK header mismatch")
    return {**record(path.stat()), "pe": "x86_64", "embedded_pck_bytes": length}


def pck_directory(path):
    """Read actual Godot 4.6 PCK entries, without computing content hashes.

    Accept an embedded preview or a standalone resource candidate. Offsets in
    returned entries are absolute filesystem offsets, not directory estimates.
    """
    path = Path(path)
    size = path.stat().st_size
    with path.open("rb") as file:
        signature = file.read(4)
        if signature == b"GDPC":
            start, length = 0, size
        else:
            file.seek(-12, 2)
            length, magic = struct.unpack("<Q4s", file.read(12))
            if magic != b"GDPC" or not 0 < length <= size - 12:
                raise ValueError("Missing embedded resource pack")
            start = size - 12 - length
        file.seek(start)
        header = file.read(40)
        magic, version, major, minor, patch, flags, base, directory = struct.unpack("<4sIIIIIQQ", header)
        if magic != b"GDPC" or version != 3 or flags & 1:
            raise ValueError("Expected unencrypted Godot 4.6 PCK v3")
        data_base = base + (start if flags & 2 else 0)
        file.seek(start + directory)
        count = struct.unpack("<I", file.read(4))[0]
        if count > 1000000:
            raise ValueError("Invalid PCK directory count")
        entries = []
        seen = set()
        for _ in range(count):
            name_length = struct.unpack("<I", file.read(4))[0]
            if not 0 < name_length < 65536:
                raise ValueError("Invalid PCK path length")
            name = file.read(name_length).rstrip(b"\0").decode("utf-8").removeprefix("res://")
            offset, byte_count = struct.unpack("<QQ", file.read(16))
            file.read(16)  # Container integrity field; no fingerprint calculation.
            entry_flags = struct.unpack("<I", file.read(4))[0]
            absolute = data_base + offset
            if name in seen or ".." in Path(name).parts or entry_flags or not start <= absolute <= absolute + byte_count <= start + length:
                raise ValueError("Invalid, duplicate or encrypted PCK entry: " + name)
            seen.add(name)
            entries.append({"path": name, "bytes": byte_count, "offset": absolute, "flags": entry_flags})
    return {"container": str(path), "container_bytes": size, "pck_start": start,
            "pck_bytes": length, "engine": [major, minor, patch], "files": entries}


def delete_file(path):
    """Skip files open without exclusive access. Never terminate a process."""
    if os.name != "nt":
        path.unlink()
        return
    from ctypes import wintypes
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.SetFileInformationByHandle.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
    # DELETE | FILE_READ_ATTRIBUTES; share=0; OPEN_EXISTING; OPEN_REPARSE_POINT.
    handle = kernel.CreateFileW(str(path), 0x10000 | 0x80, 0, None, 3, 0x200000, None)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        disposition = wintypes.BOOLEAN(1)
        if not kernel.SetFileInformationByHandle(handle, 4, ctypes.byref(disposition), ctypes.sizeof(disposition)):
            raise ctypes.WinError(ctypes.get_last_error())
    finally:
        kernel.CloseHandle(handle)


def bounded_run(argv, cwd):
    """Drain stdout to a bounded tail in memory; never save a full export log."""
    process = subprocess.Popen(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    tail = bytearray()
    script_error = False
    try:
        while block := process.stdout.read(8192):
            script_error |= b"SCRIPT ERROR" in bytes(tail[-64:]) + block or b"Parse Error:" in bytes(tail[-64:]) + block
            tail.extend(block)
            if len(tail) > TAIL:
                del tail[:-TAIL]
        code = process.wait()
    except BaseException:
        process.terminate()  # Only this invocation's own child.
        process.wait()
        raise
    finally:
        process.stdout.close()
    return code or int(script_error), tail.decode("utf-8", errors="replace")


class Manager:
    def __init__(self, root=ROOT, run=bounded_run, track=True):
        self.root = root.absolute()
        if not (self.root / "project.godot").is_file():
            raise ValueError("WWO project marker missing")
        self.run = run
        self.policy = read_json(self.safe(POLICY))
        path = self.safe(REGISTRY)
        self.state = read_json(path) if path.exists() else {"schema": 1, "generation": 0, "builds": {}, "jobs": {}}
        self.tracked = set()
        if track and (self.root / ".git").exists():
            result = subprocess.run(["git", "ls-files", "-z"], cwd=self.root, capture_output=True, check=True)
            self.tracked = set(result.stdout.decode("utf-8").split("\0"))

    def safe(self, relative):
        relative = str(relative).replace("\\", "/")
        parts = relative.split("/")
        if not relative or Path(relative).is_absolute() or any(p in {"", ".", ".."} or ":" in p for p in parts):
            raise ValueError("Unsafe relative path: " + relative)
        target = self.root.joinpath(*parts)
        # Include root and every existing ancestor, before resolve follows links.
        for path in [self.root, *reversed(target.parents)][1:]:
            if path == self.root or self.root in path.parents:
                self.no_link(path)
        self.no_link(self.root)
        self.no_link(target)
        if not target.resolve().is_relative_to(self.root.resolve()):
            raise ValueError("Path leaves project: " + relative)
        return target

    @staticmethod
    def no_link(path):
        try:
            st = path.lstat()
        except FileNotFoundError:
            return
        if stat.S_ISLNK(st.st_mode) or getattr(st, "st_file_attributes", 0) & 0x400:
            raise ValueError("Reparse point rejected: " + str(path))

    @contextlib.contextmanager
    def lock(self):
        path = self.safe("builds/.preview-manager.lock")
        path.parent.mkdir(exist_ok=True)
        with path.open("a+b") as f:
            if f.tell() == 0:
                f.write(b"0")
                f.flush()
            f.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            try:
                yield
            finally:
                f.seek(0)
                if os.name == "nt":
                    msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    fcntl.flock(f, fcntl.LOCK_UN)

    def save(self):
        same_write(self.safe(REGISTRY), json.dumps(self.state, ensure_ascii=False, indent=2) + "\n")

    def protected(self, path):
        lower = path.lower()
        if re.search(r"(?:^|[_/\-])r(?:19|30)(?:[_/.\-]|$)", lower):
            return True
        for prefix in self.policy["protected_paths"]:
            if lower == prefix.lower().rstrip("/") or lower.startswith(prefix.lower().rstrip("/") + "/"):
                return True
        return any(b["state"] in {"CURRENT", "CANDIDATE", "ROLLBACK", "PROTECTED"} and path in b["files"] for b in self.state["builds"].values())

    def busy(self, project_only=False):
        if os.name != "nt":
            return []
        ps = "Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Godot|blender|python|WWO' } | Select-Object ProcessId,ExecutablePath,CommandLine,Name | ConvertTo-Json -Compress"
        command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command"]
        out = subprocess.run([*command, "$ErrorActionPreference='Stop'; " + ps], capture_output=True, text=True)
        if out.returncode:
            # Restricted Windows sessions may deny CIM. Without command lines,
            # treat every potential producer as active until it exits.
            fallback = ("Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -match 'Godot|blender|python|WWO' } "
                        "| Select-Object -ExpandProperty Id | ConvertTo-Json -Compress")
            listing = subprocess.run([*command, fallback], capture_output=True, text=True, check=True)
            ids = json.loads(listing.stdout) if listing.stdout.strip() else []
            return [pid for pid in (ids if isinstance(ids, list) else [ids]) if pid != os.getpid()]
        rows = json.loads(out.stdout) if out.stdout.strip() else []
        rows = rows if isinstance(rows, list) else [rows]
        found = []
        for p in rows:
            if p["ProcessId"] == os.getpid():
                continue
            cmd = (p.get("CommandLine") or "").lower().replace("\\", "/")
            exe = (p.get("ExecutablePath") or "").lower().replace("\\", "/")
            if str(self.root).lower().replace("\\", "/") in cmd or exe.startswith(str(self.root).lower().replace("\\", "/") + "/") or re.search(r"tools/map/(?:build_|visualize_|trace_)", cmd) or re.search(r"godot" if project_only else r"godot|blender", p.get("Name", ""), re.I):
                found.append(p["ProcessId"])
        return found

    def recover_attempt(self):
        attempt = self.state.get("attempt")
        if not attempt:
            return
        if self.busy():
            raise ValueError("Interrupted build outputs still have a possible producer")
        owned = {}
        for rel in attempt["paths"]:
            if not rel.startswith("builds/.preview-staging/" + attempt["version"] + "/candidate."):
                raise ValueError("Invalid interrupted attempt ownership")
            p = self.safe(rel)
            if p.is_file():
                owned[rel] = record(p.stat())
        cleaned = self.cleanup(True, only=owned)
        if cleaned["skipped"]:
            raise ValueError("Interrupted outputs could not be retired")
        self.state.pop("attempt", None)
        self.save()

    def cleanup(self, execute=False, only=None):
        result = {"dry_run": not execute, "deleted_files": 0, "deleted_bytes": 0, "eligible_bytes": 0, "protected_bytes": 0, "skipped": [], "removed": []}
        entries = {}
        if only is not None:
            entries.update(only)
        else:
            for b in self.state["builds"].values():
                if b["state"] == "OBSOLETE":
                    entries.update(b["files"])
            for path, meta in self.state.get("summaries", {}).items():
                version = Path(path).parent.name
                if self.state["builds"].get(version, {}).get("state") == "OBSOLETE":
                    entries[path] = meta
            for path, version in self.state.get("diagnostic_owners", {}).items():
                if self.state["builds"].get(version, {}).get("state") == "OBSOLETE" and path in self.state.get("diagnostics", {}):
                    entries[path] = self.state["diagnostics"][path]
            entries.update(self.state.get("temporary", {}))
        active = self.busy(project_only=True)
        for relative, expected in entries.items():
            try:
                path = self.safe(relative)
                if not path.exists():
                    continue
                st = path.stat()
                if self.protected(relative):
                    result["protected_bytes"] += st.st_size
                    raise ValueError("protected")
                if relative in self.tracked:
                    raise ValueError("Git tracked: requires reviewed source change")
                if not (relative.startswith("builds/") or relative.startswith("local-artifacts/")):
                    raise ValueError("Not an authorized generated directory")
                if path.suffix.lower() in SOURCE_EXT or any(x.lower() in SOURCE_DIRS for x in Path(relative).parts) or re.search(r"license|licence|third.party|source.and.usage", path.name, re.I):
                    raise ValueError("Source/permission/rebuild input")
                if not stat.S_ISREG(st.st_mode):
                    raise ValueError("Not a regular file")
                if active:
                    raise ValueError("WWO producer/process active: " + str(active))
                if record(st) != expected:
                    raise ValueError("Changed since ownership registration")
                result["eligible_bytes"] += st.st_size
                if execute:
                    self.safe(relative)  # Recheck canonical parents at deletion.
                    delete_file(path)
                    result["deleted_files"] += 1
                    result["deleted_bytes"] += st.st_size
                    result["removed"].append(relative)
            except (OSError, ValueError) as e:
                result["skipped"].append({"path": relative, "reason": str(e)})
        if execute:
            totals = self.state.setdefault("cleanup_totals", {"files": self.state.get("last_cleanup", {}).get("deleted_files", 0), "bytes": self.state.get("last_cleanup", {}).get("deleted_bytes", 0)})
            totals["files"] += result["deleted_files"]
            totals["bytes"] += result["deleted_bytes"]
            self.state["temporary"] = {p: v for p, v in self.state.get("temporary", {}).items() if self.safe(p).exists()}
            result["removed"] = result["removed"][:64]
            self.state["last_cleanup"] = result
            for relative in entries:
                parent = Path(relative).parent.as_posix()
                if not parent.startswith(("builds/preview_", "builds/.preview-staging/")):
                    continue
                if any(b["state"] != "OBSOLETE" and any(p.startswith(parent + "/") for p in b["files"]) for b in self.state["builds"].values()):
                    continue
                try:
                    if not self.protected(parent):
                        self.safe(parent).rmdir()  # Empty owned directory only.
                except (OSError, ValueError):
                    pass
            self.save()
        return result

    def adopt(self):
        """Explicit migration policy, not guessed acceptance from R numbers."""
        if self.state["builds"]:
            for version, seed in self.policy["seed_builds"].items():
                b = self.state["builds"].get(version, {})
                if b.get("state") != seed["state"] or b.get("path") != seed["path"] or record(self.safe(seed["path"]).stat()) != b["files"][seed["path"]]:
                    raise ValueError("Migration no longer matches current lifecycle; do not reseed")
                verify_exe(self.safe(seed["path"]))
        else:
            for version, seed in self.policy["seed_builds"].items():
                path = self.safe(seed["path"])
                info = verify_exe(path)
                self.state["builds"][version] = {"state": seed["state"], "path": seed["path"], "files": {seed["path"]: record(path.stat())}, "technical": info, "evidence": seed["evidence"], "accepted": False}
            for version, paths in self.policy["retired_files"].items():
                files = {p: record(self.safe(p).stat()) for p in paths if self.safe(p).is_file()}
                if files:
                    self.state["builds"][version] = {"state": "OBSOLETE", "files": files, "evidence": "Superseded ordinary preview notice; no game/source consumer. Existing report retained."}
        receipt = self.safe("builds/.preview-inputs.json")
        if not receipt.exists():
            inputs = self.input_metadata()
            for version, b in self.state["builds"].items():
                if b["state"] == "CANDIDATE" and all(v[1] <= b["technical"]["mtime_ns"] for v in inputs.values()):
                    same_write(receipt, json.dumps({"version": version, "inputs": inputs}, separators=(",", ":")))
                    b["input_basis"] = "Explicit user R57 baseline; all current path/size/mtime entries predate export. Metadata only, no content hash."
                    break
        self.save()
        return self.cleanup(True)

    def input_metadata(self):
        out = {}
        for name in ["scripts", "shaders", "scenes", "assets", "data", "military_runtime"]:
            for p, st in walk(self.root / name):
                out[p.relative_to(self.root).as_posix()] = [st.st_size, st.st_mtime_ns]
        # Godot's scan boundary changes the generated global-class catalogue.
        # Treat it as an input so an old candidate cannot bypass re-import.
        for name in ["project.godot", "export_presets.cfg", "local-artifacts/.gdignore",
                     "tools/build/preview.py", "tools/map/save_city_meshes.gd"]:
            st = self.safe(name).stat()
            out[name] = [st.st_size, st.st_mtime_ns]
        return out

    def note(self, version, outcome):
        # One overwritten summary per build; error tail is capped across stages.
        out = self.safe("local-artifacts/preview-manager/" + version + "/result.json")
        self.safe(out.relative_to(self.root).as_posix())
        same_write(out, json.dumps(outcome, ensure_ascii=False, indent=2) + "\n")
        self.state.setdefault("summaries", {})[out.relative_to(self.root).as_posix()] = record(out.stat())
        files = []
        for relative, expected in self.state["summaries"].items():
            path = self.safe(relative)
            if path.is_file() and record(path.stat()) == expected:
                files.append((path, path.stat()))
        files.sort(key=lambda v: v[1].st_mtime_ns, reverse=True)
        used = 0
        for p, st in files:
            used += st.st_size
            if used > LOG_BUDGET:
                # Only tool-owned summaries with no active candidate obligation.
                relative = p.relative_to(self.root).as_posix()
                if p.parent.name not in [v for v, b in self.state["builds"].items() if b["state"] != "OBSOLETE"]:
                    self.state.setdefault("temporary", {})[relative] = record(st)

    def recipes(self, recipe, allow_large):
        if not recipe:
            return
        doc = read_json(self.safe(recipe))
        for job in doc.get("jobs", []):
            if "temporary_estimate_bytes" not in job:
                raise ValueError("Every preparation job must declare its temporary write estimate")
            if job.get("temporary_estimate_bytes", 0) > 1024 ** 3 and not allow_large:
                raise ValueError("Preparation exceeds1GiB; explicit authorized --allow-large-preparation required")
            temps = job.get("temporary_outputs", [])
            diagnostics = job.get("diagnostic_outputs", [])
            paths = [*job["inputs"], *job["outputs"], *temps, *diagnostics]
            for p in paths:
                self.safe(p)
            for p in temps + diagnostics:
                if not p.startswith("local-artifacts/") or self.safe(p).suffix.lower() in SOURCE_EXT or any(x.lower() in SOURCE_DIRS for x in Path(p).parts):
                    raise ValueError("Temporary outputs must be exact regenerable research outputs, not source data")
            key = job["id"]
            inputs = {p: record(self.safe(p).stat()) for p in job["inputs"]}
            outputs = {p: record(self.safe(p).stat()) for p in job["outputs"] if self.safe(p).is_file()}
            previous = self.state["jobs"].get(key, {})
            if previous == {"argv": job["argv"], "inputs": inputs, "outputs": outputs} and len(outputs) == len(job["outputs"]):
                continue
            before = {p: record(self.safe(p).stat()) for p in temps + diagnostics if self.safe(p).exists()}
            caught = None
            code, tail = -1, ""
            try:
                code, tail = self.run(job["argv"], self.root)
            except BaseException as e:
                caught = e
            finally:
                # Never adopt a pre-existing unknown file as temporary garbage.
                for p in temps + diagnostics:
                    if p not in before and self.safe(p).is_file():
                        self.state.setdefault("temporary" if p in temps else "diagnostics", {})[p] = record(self.safe(p).stat())
                        if p in diagnostics and getattr(self, "_preparing_version", None):
                            self.state.setdefault("diagnostic_owners", {})[p] = self._preparing_version
                observed = sorted(self.state.get("diagnostics", {}).items(), key=lambda row: row[1]["mtime_ns"], reverse=True)
                used = 0
                for p, meta in observed:
                    used += meta["bytes"]
                    if used > DIAGNOSTIC_BUDGET:
                        self.state.setdefault("temporary", {})[p] = meta
                        self.state["diagnostics"].pop(p)
                self.save()
            if code or caught:
                owned = {p: v for p, v in self.state.get("temporary", {}).items() if p in temps + diagnostics}
                self.cleanup(True, only=owned)
                raise RuntimeError("Preparation failed: " + key + "\n" + str(caught or "") + tail[-TAIL:]) from caught
            outputs = {p: record(self.safe(p).stat()) for p in job["outputs"]}
            self.state["jobs"][key] = {"argv": job["argv"], "inputs": inputs, "outputs": outputs}
            self.save()

    def build(self, version, godot, recipe=None, allow_large=False, terrain_manifest=TERRAIN_MANIFEST, debug=False):
        if not re.fullmatch(r"R[1-9][0-9]*", version):
            raise ValueError("Version must be a readable R number")
        project = self.safe("project.godot").read_text(encoding="utf-8")
        if not re.search(r"^config/build_sequence=" + version[1:] + r"$", project, re.M):
            raise ValueError("Project build_sequence must match version; save metadata is not changed by this tool")
        if self.busy(project_only=True):
            raise ValueError("Another WWO process is active")
        self.recover_attempt()
        existing = self.state["builds"].get(version, {})
        if existing.get("state") in {"CURRENT", "ROLLBACK", "PROTECTED", "OBSOLETE"}:
            raise ValueError("Do not overwrite accepted/protected/retired builds; use a new monotonic version")
        active_versions = [int(v[1:]) for v in self.state["builds"] if re.fullmatch(r"R\d+", v)]
        if active_versions and int(version[1:]) < max(active_versions):
            raise ValueError("Version is not monotonic")
        self._preparing_version = version
        self.recipes(recipe, allow_large)
        terrain_path, terrain_recipe = self.prepare_terrain_export(terrain_manifest)
        inputs = self.input_metadata()
        inputs["terrain_export"] = {str(p): record(Path(p).stat()) for p in
                                    [terrain_path, *set(terrain_recipe["expected"].values()),
                                     self.safe("tools/build/terrain_export.gd"), self.safe("tools/build/plugin.cfg")]}

        previous_inputs_path = self.safe("builds/.preview-inputs.json")
        export_mode = "debug" if debug else "release"
        if existing and existing.get("state") == "CANDIDATE" and previous_inputs_path.exists() and read_json(previous_inputs_path) == {"version": version, "inputs": inputs, "mode": export_mode}:
            candidate = self.safe(existing["path"])
            if record(candidate.stat()) != existing["files"][existing["path"]]:
                raise ValueError("Candidate changed after ownership registration")
            verify_exe(candidate)
            result = {"version": version, "result": "unchanged: export/import skipped", "cleanup": self.cleanup(True)}
            self.note(version, result)
            self.save()
            return result
        self.state["generation"] += 1
        generation = self.state["generation"]
        self.save()
        staging = f"builds/.preview-staging/{version}/candidate.exe"
        stage = self.safe(staging)
        stage.parent.mkdir(parents=True, exist_ok=True)
        # An existing unknown file is not owned by this invocation.
        if stage.exists():
            raise ValueError("Unregistered staging file; inspect before retry")
        destination = existing.get("path", f"builds/preview_{version}/WWO_{version}_{'Debug' if debug else 'Preview'}.exe")
        self.safe(destination)
        if not existing and self.safe(destination).exists():
            raise ValueError("Unregistered destination exists")
        attempt_paths = [staging, staging[:-4] + ".tmp", staging[:-4] + ".pck", staging[:-4] + ".console.exe"]
        if any(self.safe(p).exists() for p in attempt_paths):
            raise ValueError("Unregistered staging sibling; inspect before retry")
        self.state["attempt"] = {"version": version, "generation": generation, "paths": attempt_paths}
        self.save()
        tail = ""
        try:
            code, tail = self.run([godot, "--headless", "--path", str(self.root), "--editor", "--import", "--quit"], self.root)
            if code:
                raise RuntimeError("Godot import failed")
            terrain_path, terrain_recipe = self.prepare_ground_export(godot, terrain_path, terrain_recipe)
            with self.terrain_export_environment(terrain_path, terrain_recipe):
                code, export_tail = self.run([godot, "--headless", "--path", str(self.root), "--export-debug" if debug else "--export-release", PRESET, str(stage)], self.root)
            tail = (tail + "\n" + export_tail)[-TAIL:]
            if code:
                raise RuntimeError("Godot export failed")
            technical = verify_exe(stage)
            self.verify_terrain_export(stage, terrain_recipe)
            if self.input_metadata() != {k:v for k,v in inputs.items() if k!="terrain_export"}:
                raise ValueError("Current runtime inputs changed during build; candidate is not coherent")
            if any(record(Path(p).stat()) != value for p, value in inputs["terrain_export"].items()):
                raise ValueError("Terrain export inputs changed during build")
            final = self.safe(destination)
            final.parent.mkdir(parents=True, exist_ok=True)
            if final.parent.stat().st_dev != stage.parent.stat().st_dev:
                raise ValueError("Publication must remain on the same volume")
            if final.exists() and record(final.stat()) != existing["files"].get(destination):
                raise ValueError("Candidate changed by another producer")
            os.replace(stage, final)  # Same volume; no full EXE copy or ZIP.
            for v, b in self.state["builds"].items():
                if v == version:
                    continue
                if b["state"] == "CURRENT":
                    b["state"] = "ROLLBACK"
                elif b["state"] == "CANDIDATE":
                    b["state"] = "OBSOLETE"
            self.state["builds"][version] = {"state": "CANDIDATE", "mode": export_mode, "path": destination, "files": {destination: record(final.stat())}, "technical": technical, "generation": generation, "accepted": False}
            leftover = {rel: record(self.safe(rel).stat()) for rel in attempt_paths if self.safe(rel).is_file()}
            self.state.setdefault("temporary", {}).update(leftover)
            self.state.pop("attempt", None)
            self.save()  # Register before any cleanup of older versions.
            same_write(previous_inputs_path, json.dumps({"version": version, "inputs": inputs, "mode": export_mode}, separators=(",", ":")))
            result = {"version": version, "generation": generation, "path": destination, "result": "technical export completed; player acceptance pending", "technical": technical, "warnings_or_tail": tail[-16384:]}
            self.note(version, result)
            self.save()
            result["cleanup"] = self.cleanup(True)
            self.note(version, result)
            self.save()
            return result
        except BaseException as e:
            # Only the exact outputs of this attempt. No old-preview cleanup.
            owned = {}
            for rel in [staging, staging[:-4] + ".tmp", staging[:-4] + ".pck", staging[:-4] + ".console.exe"]:
                p = self.safe(rel)
                if p.is_file():
                    owned[rel] = record(p.stat())
            self.state.setdefault("temporary", {}).update(owned)
            clean = self.cleanup(True, only=owned)
            self.state.pop("attempt", None)
            self.note(version, {"result": "failed", "generation": generation, "error": str(e)[-16384:], "error_tail": tail[-16384:], "cleanup": clean})
            self.save()
            raise

    def promote(self, version, acceptance):
        if not acceptance.strip():
            raise ValueError("Player acceptance statement required")
        b = self.state["builds"][version]
        if b["state"] == "CURRENT":
            return self.cleanup(True)
        if b["state"] != "CANDIDATE":
            raise ValueError("Only a candidate can be promoted")
        if record(self.safe(b["path"]).stat()) != b["files"][b["path"]]:
            raise ValueError("Candidate changed after technical validation")
        verify_exe(self.safe(b["path"]))
        for v, old in self.state["builds"].items():
            if v != version and old["state"] in {"ROLLBACK", "CURRENT"}:
                old["state"] = "OBSOLETE"
        b.update(state="CURRENT", accepted=True, acceptance=acceptance)
        self.save()
        return self.cleanup(True)

    def recover_relief_inputs(self, plan):
        """Recover the admitted bytes from the preserved Windows baseline."""
        archive = self.safe(plan["source_archive"])
        directory = pck_directory(archive)
        if (directory["container_bytes"], directory["pck_bytes"]) != (plan["archive_bytes"], plan["pck_bytes"]):
            raise ValueError("R67 recovery archive size does not match the versioned recipe")
        entries = {row["path"]: row for row in directory["files"]}
        output = self.safe("local-artifacts/preview-manager/r68-relief")
        manifest = {"files": [], "catalogues": plan["catalogues"]}
        compact_pages = {}
        with archive.open("rb") as packed:
            for path, source_bytes, size, width, height, decoded, compact, kind in plan["pages"]:
                source = self.safe(path)
                if not path.startswith("assets/maps/relief/") or source.stat().st_size != source_bytes:
                    raise ValueError("R68 relief source differs: " + path)
                candidate = source
                if kind == "RGBA8_MIP_FRA0":
                    entry = entries[path]
                    if entry["bytes"] != size:
                        raise ValueError("R67 relief entry size differs: " + path)
                    packed.seek(entry["offset"])
                    original = packed.read(size)
                    if original[:10] != b"FRA0\0\0\0\0\x01\x05" or struct.unpack_from("<III",original,12) != (width,height,decoded):
                        raise ValueError("R67 lossless relief header differs: " + path)
                    candidate = output / "fra0" / Path(path).name
                    self.write_payload(candidate, original)
                    if compact:
                        payload = original[28:]
                        meta = dict(kind="relief-page", source=path, width=width, height=height, decoded_bytes=decoded)
                        index = json.dumps(dict(meta=meta, blocks={"mips": [0, len(payload), "webp-rgba8-mips"]}),
                                           separators=(",", ":")).encode("utf-8")
                        page = output / "wwocm2" / (Path(path).stem + ".wcm")
                        self.write_payload(page, b"WWOCM2\0\0" + struct.pack("<I",len(index)) + index + payload)
                        compact_pages[path] = page
                asset = {"path": "res://"+path, "format": "RGBA8_MIP_DEFLATE", "width": width,
                         "height": height, "decoded_bytes": decoded}
                manifest["files"].append(dict(asset=asset, source_bytes=source_bytes, source_mtime_ns=source.stat().st_mtime_ns,
                                              chosen_format=kind, chosen_bytes=size, candidate_path=candidate.relative_to(self.root).as_posix(),
                                              full_rgba_mips_equal=True, transparent_rgb_equal=True))
        return manifest, compact_pages, output

    @staticmethod
    def write_payload(path, data):
        if path.is_file() and path.read_bytes() == data:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(data)
        os.replace(temporary, path)

    def prepare_terrain_export(self, manifest_path=TERRAIN_MANIFEST, legacy_map_storage=False):
        """Current catalogues, validated storage only. Never copy R59 game code."""
        manifest_path = self.safe(manifest_path)
        manifest = read_json(manifest_path)
        pinned = manifest.get("schema") == 2
        compact_pages = {}
        if pinned:
            retained = manifest["retained"]
            manifest, compact_pages, output = self.recover_relief_inputs(manifest)
        elif manifest_path.parent.is_relative_to(self.root / "local-artifacts"):
            output = manifest_path.parent
            baseline = read_json(output / "baseline-directory.json")
            retained = [e["path"] for e in baseline["files"] if e["path"].startswith("assets/maps/relief/")]
        else:
            raise ValueError("Terrain recipe must stay in local-artifacts")
        replacements, expected, seen = {}, {}, set()
        storage = {}
        forced = []
        # LOCAL height readers require the original encoded heights, even if a
        # colour catalogue references the same virtual path.
        for local_metadata in sorted((self.root / "data/local").glob("*.json")):
            context = read_json(local_metadata).get("metadata", {}).get("surface_presentation", {}).get("context_height_asset", {})
            if not context:
                continue
            local = context["path"].removeprefix("res://")
            dependency = self.safe(local)
            if context["format"] != "RGBA8_MIP_DEFLATE" or dependency.stat().st_size != context["bytes"]:
                raise ValueError("Original LOCAL height dependency unavailable: " + local)
            replacements[local] = expected[local] = str(dependency)
            if local not in forced:
                forced.append(local)
        rows = {r["asset"]["path"].removeprefix("res://"): r for r in manifest["files"]}
        for path, row in rows.items():
            source = self.safe(path)
            if record(source.stat()) != {"bytes": row["source_bytes"], "mtime_ns": row["source_mtime_ns"]}:
                raise ValueError("Original changed since lossless validation: " + path)
            if not row["full_rgba_mips_equal"] or not row["transparent_rgb_equal"]:
                raise ValueError("Unverified terrain storage: " + path)
            if path in forced:
                continue
            candidate = self.safe(row["candidate_path"]) if row["chosen_format"] == "RGBA8_MIP_FRA0" else source
            if candidate.stat().st_size != row["chosen_bytes"]:
                raise ValueError("Chosen terrain input changed: " + path)
            if candidate != source:
                storage[path] = {"format": row["chosen_format"], "bytes": row["chosen_bytes"]}
                page = compact_pages.get(path) if pinned else self.safe("assets/maps/compact/relief/" + Path(path).stem + ".wcm")
                if not legacy_map_storage and page is not None and page.is_file():
                    with page.open("rb") as file:
                        magic, length = struct.unpack("<8sI", file.read(12))
                        if magic != b"WWOCM2\0\0" or not 2 <= length <= 4096:
                            raise ValueError("Invalid WWOCM2 relief page: " + path)
                        index = json.loads(file.read(length))
                        payload = file.read()
                    asset = row["asset"]
                    meta = dict(kind="relief-page", source=path, width=asset["width"],
                                height=asset["height"], decoded_bytes=asset["decoded_bytes"])
                    prior = candidate.read_bytes()
                    if index != {"meta": meta, "blocks": {"mips": [0, len(payload), "webp-rgba8-mips"]}} or (
                        prior[:10] != b"FRA0\0\0\0\0\x01\x05" or prior[28:] != payload
                    ):
                        raise ValueError("WWOCM2 page differs from validated relief data: " + path)
                    candidate = page
                    storage[path] = {"format": "RGBA8_MIP_WWOCM2", "bytes": page.stat().st_size}
            expected[path] = str(candidate)
            if candidate != source: replacements[path] = str(candidate)
        for path in manifest["catalogues"]:
            document = read_json(self.safe(path))
            changed = False
            for fact in document["evidence_catalog"]["facts"]:
                for asset in fact["value"].get("assets", []):
                    virtual = asset["path"].removeprefix("res://")
                    row = rows.get(virtual)
                    if not row: continue
                    for key in ["format", "width", "height", "decoded_bytes"]:
                        if asset.get(key) != row["asset"].get(key):
                            raise ValueError("Current terrain storage contract changed: " + virtual + ":" + key)
                    seen.add(virtual)
                    if virtual in storage:
                        asset.update(storage[virtual])
                        changed = True
            if changed:
                target = output / ("metadata-legacy" if legacy_map_storage else "metadata-current") / path
                same_write(target, json.dumps(document, ensure_ascii=False, separators=(",", ":")))
                replacements[path] = expected[path] = str(target)
        if seen != set(rows):
            raise ValueError("Current catalogue no longer admits every chosen terrain path")
        if legacy_map_storage:
            original = self.safe("local-artifacts/map-task-a/original/data/strategic")
            old_files = sorted(original.glob("*"))
            if not any(p.suffix == ".display" for p in old_files) or not any(p.suffix == ".geom" for p in old_files):
                raise ValueError("Task A strategic rollback inputs are missing")
            for prior in old_files:
                virtual = "data/strategic/" + prior.name
                if prior.suffix not in {".display", ".geom", ".json"} or not self.safe(virtual).is_file():
                    raise ValueError("Unexpected strategic rollback input: " + virtual)
                replacements[virtual] = expected[virtual] = str(self.safe(prior.relative_to(self.root)))
        # Keep unchanged raw PNGs in the same payload inclusion verification.
        for path in retained:
            if path not in rows and path not in expected:
                source = self.safe(path)  # These PNG payloads intentionally use .bin paths.
                with source.open("rb") as file:
                    if file.read(8) != b"\x89PNG\r\n\x1a\n":
                        raise ValueError("Unexpected retained relief storage: " + path)
                expected[path] = str(source)
        mode = "legacy" if legacy_map_storage else "current"
        report = output / (mode + "-export-report.json")
        recipe = {"schema": 1, "replacements": replacements, "expected": expected,
                  "forced": forced, "report": str(report)}
        path = output / (mode + "-export-recipe.json")
        same_write(path, json.dumps(recipe, ensure_ascii=False, indent=2))
        return path, recipe

    def prepare_ground_export(self, godot, recipe_path, recipe):
        directory = "assets/settlements/europe_context"
        output = recipe_path.parent / "europe-ground"
        command = [godot, "--headless", "--path", str(self.root), "--script", "res://tools/map/save_city_meshes.gd",
                   "--", "--pack-ground", "res://" + directory, str(output)]
        code, tail = self.run(command, self.root)
        if code or "ERROR:" in tail:
            raise RuntimeError("European ground preparation failed: " + tail[-16384:])
        ground = read_json(output / "ground.json")
        recipe = {**recipe, "replacements": dict(recipe["replacements"]), "expected": dict(recipe["expected"])}
        for name in ground["tiles"]:
            if not re.fullmatch(r"context_(8|10)_\d+_\d+\.res", name):
                raise ValueError("Unexpected European ground tile: " + name)
            path = directory + "/" + name
            source = output / (Path(name).stem + ".ctm")
            if source.stat().st_size >= self.safe(path).stat().st_size:
                raise ValueError("European ground replacement must be smaller: " + path)
            recipe["replacements"][path] = recipe["expected"][path] = str(source)
        path = output.parent / "candidate-export-recipe.json"
        same_write(path, json.dumps(recipe, ensure_ascii=False, indent=2))
        return path, recipe

    @contextlib.contextmanager
    def terrain_export_environment(self, recipe_path, recipe):
        name = "WWO_TERRAIN_EXPORT_RECIPE"
        old = os.environ.get(name)
        same_write(Path(recipe["report"]), '{"complete":false}')
        os.environ[name] = str(recipe_path)
        try:
            yield
        finally:
            if old is None: os.environ.pop(name, None)
            else: os.environ[name] = old

    def verify_terrain_export(self, container, recipe):
        report = read_json(Path(recipe["report"]))
        if not report.get("complete") or set(report["included"]) != set(recipe["replacements"]):
            raise ValueError("Normal Godot terrain export hook was not completed")
        directory = pck_directory(container)
        entries = {e["path"]: e for e in directory["files"]}
        with Path(container).open("rb") as packed:
            for path, source in recipe["expected"].items():
                if path not in entries:
                    raise ValueError("Required terrain missing from normal export: " + path)
                entry = entries[path]
                packed.seek(entry["offset"])
                if packed.read(entry["bytes"]) != Path(source).read_bytes():
                    raise ValueError("Wrong or unreplaced normal export payload: " + path)
        return directory

    def pack_current_resources(self, manifest_path, godot, name, legacy_map_storage=False):
        """Same preset/hook as a normal preview, but PCK-only; no promotion."""
        # PCK-only export never deletes old outputs. An unrelated Blender
        # workbench is external load, not ownership of this project's files.
        if self.busy(project_only=True): raise ValueError("Another WWO process is active")
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", name): raise ValueError("Unsafe candidate name")
        recipe_path, recipe = self.prepare_terrain_export(manifest_path, legacy_map_storage)
        target = recipe_path.parent / (name + ".pck")
        if target.exists(): raise ValueError("Candidate already exists: " + str(target))
        if not legacy_map_storage:
            recipe_path, recipe = self.prepare_ground_export(godot, recipe_path, recipe)
        sources = {p: record(Path(p).stat()) for p in set(recipe["expected"].values())}
        runtime_inputs = self.input_metadata()
        with self.terrain_export_environment(recipe_path, recipe):
            code, tail = self.run([godot, "--headless", "--path", str(self.root), "--export-pack", PRESET, str(target)], self.root)
        if code or "ERROR:" in tail:
            raise RuntimeError("Current-source pack export failed: " + tail[-16384:])
        directory = self.verify_terrain_export(target, recipe)
        if self.input_metadata() != runtime_inputs:
            raise ValueError("Current runtime inputs changed during export; candidate is not coherent")
        if any(record(Path(p).stat()) != value for p, value in sources.items()):
            raise ValueError("Terrain inputs changed during export")
        same_write(target.with_name(name + "-directory.json"), json.dumps(directory, ensure_ascii=False, indent=2))
        result = {"container": str(target), "candidate_pck_bytes": directory["pck_bytes"],
                  "entries": len(directory["files"]), "terrain_payloads_verified": len(recipe["expected"]),
                  "current_source_normal_export": True, "frozen_R59_code_reused": False,
                  "legacy_map_storage": legacy_map_storage,
                  "executable_exported": False, "preview_or_release_promoted": False}
        same_write(target.with_name(name + "-pack-result.json"), json.dumps(result, ensure_ascii=False, indent=2))
        return result

    def pack_resources(self, manifest_path, godot, name):
        """Resource-only candidate operation: no EXE, promotion or cleanup."""
        manifest_path = self.safe(manifest_path)
        output = manifest_path.parent
        if not output.is_relative_to(self.root / "local-artifacts") or not re.fullmatch(r"[a-zA-Z0-9_-]+", name):
            raise ValueError("Pack candidates must stay in their declared local-artifacts recipe")
        manifest = read_json(manifest_path)
        verified = read_json(output / "godot-batch-decode.json")
        if len(verified) != len(manifest["files"]) or not all(row["full_bytes_equal"] for row in verified):
            raise ValueError("Complete native RGBA/Mip validation is required before packing")
        baseline = Path(manifest["baseline"])
        directory = pck_directory(baseline)
        if directory["container_bytes"] != manifest["baseline_bytes"]:
            raise ValueError("Frozen baseline changed")
        original = {row["path"]: row for row in directory["files"]}
        def baseline_bytes(path):
            entry = original[path]
            with baseline.open("rb") as file:
                file.seek(entry["offset"])
                return file.read(entry["bytes"])
        files = {row["asset"]["path"].removeprefix("res://"): row for row in manifest["files"]}
        replacements = {}
        for path, row in files.items():
            if row["source_bytes"] != original[path]["bytes"]:
                raise ValueError("Baseline entry size changed: " + path)
            if row["chosen_format"] == "RGBA8_MIP_FRA0":
                candidate = self.safe(row["candidate_path"])
                if candidate.stat().st_size != row["chosen_bytes"]:
                    raise ValueError("Candidate resource changed: " + path)
                replacements[path] = str(candidate)
        changed_catalogues = []
        for path in manifest["catalogues"]:
            document = json.loads(baseline_bytes(path))
            changed = False
            for fact in document["evidence_catalog"]["facts"]:
                for asset in fact["value"].get("assets", []):
                    row = files.get(asset["path"].removeprefix("res://"))
                    if row and row["chosen_format"] == "RGBA8_MIP_FRA0":
                        asset["format"] = row["chosen_format"]
                        asset["bytes"] = row["chosen_bytes"]
                        changed = True
            if changed:
                target = output / "metadata" / path
                same_write(target, json.dumps(document, ensure_ascii=False, separators=(",", ":")))
                replacements[path] = str(target)
                changed_catalogues.append(path)
        context = json.loads(baseline_bytes("data/local/zermatt_west_physical_reference.json"))["metadata"]["surface_presentation"]["context_height_asset"]
        local_path = context["path"].removeprefix("res://")
        if context["format"] != "RGBA8_MIP_DEFLATE":
            raise ValueError("LOCAL historical height encoding changed")
        additions = {}
        if local_path not in original:
            dependency = self.safe(local_path)
            if dependency.stat().st_size != context["bytes"]:
                raise ValueError("LOCAL original is unavailable")
            additions[local_path] = str(dependency)
        # Frozen R59 predates FRA0. Replace only this common storage loader;
        # leave every economic/military script in the baseline untouched.
        loader = "scripts/content/geography_loader.gd"
        additions[loader] = str(self.safe(loader))
        excluded = {loader + ".remap", loader.removesuffix(".gd") + ".gdc"}
        outputs = {"complete": str(output / (name + ".pck"))}
        for target in outputs.values():
            if Path(target).exists():
                raise ValueError("Candidate already exists; inspect it or select a new recipe name: " + target)
        entries = []
        for path in sorted((original.keys() - excluded) | additions.keys()):
            row = {"path": path}
            source = additions.get(path, replacements.get(path))
            if source:
                row["source"] = source
            entries.append(row)
        recipe = {"schema": 1, "baseline": str(baseline), "outputs": outputs,
                  "entries": entries, "note": "Complete replacement PCK, not an overlay; never distribute alongside unchanged embedded R59 and claim a size reduction."}
        recipe_path = output / (name + "-recipe.json")
        same_write(recipe_path, json.dumps(recipe, ensure_ascii=False, indent=2))
        code, tail = self.run([godot, "--headless", "--path", str(self.root), "--script",
                              "tools/map/inspect_export_r57.gd", "--", "--pack-recipe=" + str(recipe_path)], self.root)
        if code:
            raise RuntimeError("Resource candidate packaging failed: " + tail[-6000:])
        actual = pck_directory(outputs["complete"])
        present = {row["path"]: row for row in actual["files"]}
        if present.keys() != {row["path"] for row in entries}:
            raise ValueError("Actual pack path set differs from single-entry recipe")
        if any("local-artifacts" in path or ".flat_webp." in path for path in present):
            raise ValueError("Candidate aliases or work files leaked into actual pack")
        with Path(outputs["complete"]).open("rb") as file:
            for path, row in files.items():
                entry = present[path]
                if entry["bytes"] != row["chosen_bytes"]:
                    raise ValueError("Actual replacement length differs: " + path)
                file.seek(entry["offset"])
                if file.read(8) != (b"FRA0\0\0\0\0" if row["chosen_format"]=="RGBA8_MIP_FRA0" else b"FRT42\0\0\0"):
                    raise ValueError("Actual packed representation differs: " + path)
        unchanged = 0
        with baseline.open("rb") as old_file, Path(outputs["complete"]).open("rb") as new_file:
            for path in original.keys() - replacements.keys() - excluded - additions.keys():
                old_entry, new_entry = original[path], present[path]
                if old_entry["bytes"] != new_entry["bytes"]:
                    raise ValueError("Unchanged resource length differs: " + path)
                old_file.seek(old_entry["offset"])
                new_file.seek(new_entry["offset"])
                remaining = old_entry["bytes"]
                while remaining:
                    chunk = min(remaining, 1024*1024)
                    if old_file.read(chunk) != new_file.read(chunk):
                        raise ValueError("Frozen resource bytes changed: " + path)
                    remaining -= chunk
                unchanged += 1
        same_write(output / (name + "-directory.json"), json.dumps(actual, ensure_ascii=False, indent=2))
        report = {"unchanged_payloads_direct_byte_equal": unchanged, "baseline_pck_bytes": directory["pck_bytes"], "candidate_pck_bytes": actual["pck_bytes"],
                  "actual_net_saved_bytes": directory["pck_bytes"]-actual["pck_bytes"],
                  "baseline_entries": len(original), "candidate_entries": len(present),
                  "replacement_files": len(replacements)-len(changed_catalogues),
                  "catalogues_changed": changed_catalogues, "local_dependency_added": local_path if local_path in additions else None,
                  "local_dependency_bytes": context["bytes"] if local_path in additions else 0,
                  "new_and_old_double_entries": False, "paths_unique": True,
                  "outputs": outputs, "executable_exported": False, "preview_or_release_promoted": False,
                  "source_bytes_saved": manifest["summary"]["saved_bytes"],
                  "container_metadata_loader_local_delta": actual["pck_bytes"]-directory["pck_bytes"]+manifest["summary"]["saved_bytes"]}
        same_write(output / (name + "-pack-result.json"), json.dumps(report, ensure_ascii=False, indent=2))
        return report

    def resources(self):
        """Read catalogue metadata only. Offline/rebuild references block deletion."""
        paths = {}
        catalogs = sorted((self.root / "data/presentation").glob("*surface_r*.json"))
        catalogs += [self.safe("data/presentation/global_physical_relief.json")]
        for p in catalogs:
            doc = read_json(p)
            for fact in doc.get("evidence_catalog", {}).get("facts", []):
                for a in fact.get("value", {}).get("assets", []):
                    relative = a.get("path", "").removeprefix("res://")
                    if relative.startswith("assets/maps/relief/"):
                        paths.setdefault(relative, set()).add(p.name)
        # Geo loader's dynamic catalogue dispatch and producer decode paths
        # mean source_* is provenance, not a deletion approval.
        consumers = ["scripts/content/geography_loader.gd", "scripts/presentation/map/map_relief.gd", "scripts/content/strategic_spatial_loader.gd", "scripts/content/local_spatial_loader.gd", "scripts/presentation/map/region_view.gd", "scripts/presentation/map/globe_renderer.gd", "tools/map/build_surface_r56.py", "tools/map/build_surface_r57.py"]
        consumers += [p.relative_to(self.root).as_posix() for p in (self.root / "scenes/formal").glob("*.tscn")]
        text = "\n".join(self.safe(p).read_text(encoding="utf-8") for p in consumers)
        index = read_json(self.safe("data/strategic/index.json"))
        literal_paths = set(re.findall(r'res://[^\s"\'\)]+', text))
        preset = self.safe("export_presets.cfg").read_text(encoding="utf-8").split("[preset.3]", 1)[1].split("[preset.3.options]", 1)[0]
        excludes = [p for p in re.search(r'exclude_filter="([^"]*)"', preset)[1].split(",") if p.startswith("assets/maps/relief/") or p == "data/presentation/sampling_surface_r56.json"]
        excluded_bytes = sum(self.safe(p).stat().st_size for p in excludes if self.safe(p).is_file())
        count = total = 0
        for path, catalogs in paths.items():
            p = self.safe(path)
            if p.exists():
                count += 1
                total += p.stat().st_size
        return {"catalogued_existing_files": count, "catalogued_existing_bytes": total, "automatic_asset_deletion": False, "reason": "Dynamic catalogues and old BIN decode/rebuild consumers remain; source extracts are incomplete. Export exclusion alone is insufficient.", "reviewed_paths": consumers, "literal_runtime_paths": len(literal_paths), "dynamic_loader_present": "pack.replace" in text, "strategic_index": "data/strategic/index.json", "strategic_descriptor_groups": {k: len(v) for k, v in index.items() if isinstance(v, list)}, "export_exclusions": len(excludes), "export_exclusion_bytes_retained": excluded_bytes}

    def audit(self):
        groups = {}
        largest = []
        for prefix in ["builds", "local-artifacts", "assets/maps/relief", "data/presentation", "data/strategic", ".godot"]:
            for p, st in walk(self.root / prefix):
                path = p.relative_to(self.root).as_posix()
                group = "/".join(path.split("/")[:2]) if prefix in {"builds", "local-artifacts", ".godot"} else prefix
                row = groups.setdefault(group, {"bytes": 0, "files": 0})
                row["bytes"] += st.st_size
                row["files"] += 1
                largest.append((st.st_size, path))
        protected_bytes = sum(st.st_size for prefix in ["builds", "local-artifacts/revoked-r30"] for p, st in walk(self.root / prefix) if self.protected(p.relative_to(self.root).as_posix()))
        return {"groups": groups, "total_bytes": sum(g["bytes"] for g in groups.values()), "protected_bytes": protected_bytes, "largest": sorted(largest, reverse=True)[:12]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ["audit", "status", "resources"]:
        sub.add_parser(name)
    for name in ["adopt", "cleanup"]:
        p = sub.add_parser(name)
        p.add_argument("--execute", action="store_true", help="Without this flag, no deletion")
    p = sub.add_parser("build")
    p.add_argument("--version", required=True)
    p.add_argument("--godot", default=os.environ.get("WWO_GODOT", "D:/Tools/Godot-4.6.3/Godot_v4.6.3-stable_win64_console.exe"))
    p.add_argument("--recipe")
    p.add_argument("--terrain-manifest", default=TERRAIN_MANIFEST)
    p.add_argument("--allow-large-preparation", action="store_true")
    p.add_argument("--debug", action="store_true", help="Use the Godot debug export template with the existing candidate lifecycle")
    p = sub.add_parser("pack-resources", help="PCK candidates only; use --current to export current code through the normal preview preset")
    p.add_argument("--current", action="store_true", help="Normal Godot current-source export, not frozen R59 substitution")
    p.add_argument("--legacy-map-storage", action="store_true", help="With --current, use validated FRA0 pages and Task A strategic rollback data")
    p.add_argument("--manifest")
    p.add_argument("--name", default="terrain-slim")
    p.add_argument("--godot", default=os.environ.get("WWO_GODOT", "D:/Tools/Godot-4.6.3/Godot_v4.6.3-stable_win64.exe"))
    p = sub.add_parser("promote")
    p.add_argument("version")
    p.add_argument("--acceptance", required=True)
    p.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    if args.command == "pack-resources" and args.legacy_map_storage and not args.current:
        parser.error("--legacy-map-storage requires --current")
    if args.command == "pack-resources" and not args.current and not args.manifest:
        parser.error("frozen resource packs require --manifest")
    m = Manager(track=args.command != "pack-resources")
    with m.lock():
        if args.command == "pack-resources" and args.current:
            result = m.pack_current_resources(args.manifest or TERRAIN_MANIFEST, args.godot, args.name, args.legacy_map_storage)
        elif args.command == "pack-resources": result = m.pack_resources(args.manifest, args.godot, args.name)
        elif args.command == "audit": result = m.audit()
        elif args.command == "resources": result = m.resources()
        elif args.command == "status": result = {**m.state, "protected_paths": m.policy["protected_paths"]}
        elif args.command == "adopt": result = m.adopt() if args.execute else {"migration": m.policy, "dry_run": True}
        elif args.command == "cleanup":
            if args.execute: m.recover_attempt()
            result = m.cleanup(args.execute)
        elif args.command == "promote": result = m.promote(args.version, args.acceptance) if args.execute else {"dry_run": True, "promote": args.version, "acceptance": args.acceptance}
        else: result = m.build(args.version, args.godot, args.recipe, args.allow_large_preparation, args.terrain_manifest, args.debug)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
