"""Finite KB fixtures for the preview lifecycle; no Godot/game/large outputs."""
import ctypes
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import preview


def exe(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    data = bytearray(512)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 60, 128)
    data[128:134] = b"PE\0\0\x64\x86"
    pck = b"GDPC" + b"\0" * 24
    path.write_bytes(data + pck + struct.pack("<Q4s", len(pck), b"GDPC"))


class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="wwo-preview-kb-")
        self.root = Path(self.temp.name)
        (self.root / "project.godot").write_text('config/build_sequence=57\n', encoding="utf-8")
        (self.root / "export_presets.cfg").write_text("fixture", encoding="utf-8")
        p = self.root / preview.POLICY
        p.parent.mkdir(parents=True)
        p.write_text(json.dumps({"protected_paths": ["builds/windows"], "seed_builds": {}, "retired_files": {}}), encoding="utf-8")
        self.m = preview.Manager(self.root)
        self.m.busy = lambda: []

    def tearDown(self):
        self.temp.cleanup()

    def seed(self, version, state):
        rel = f"builds/preview_{version}/{version}.exe"
        p = self.root / rel
        exe(p)
        self.m.state["builds"][version] = {"state": state, "path": rel, "files": {rel: preview.record(p.stat())}}
        return p

    def test_failure_only_retires_own_output(self):
        old = self.seed("R56", "ROLLBACK")
        candidate = self.seed("R57", "CANDIDATE")
        def run(argv, cwd):
            if "--export-release" in argv:
                Path(argv[-1]).write_bytes(b"failed")
                Path(argv[-1]).with_suffix(".tmp").write_bytes(b"tmp")
                return 1, "known failure"
            return 0, ""
        self.m.run = run
        with self.assertRaises(RuntimeError):
            self.m.build("R57", "fixture")
        self.assertTrue(old.exists() and candidate.exists())
        self.assertEqual(list((self.root / "builds/.preview-staging/R57").glob("*")), [])

    def test_export_register_cleanup_and_unchanged(self):
        old = self.seed("R56", "ROLLBACK")
        obsolete = self.seed("R50", "OBSOLETE")
        calls = []
        def run(argv, cwd):
            calls.append(argv)
            if "--export-release" in argv:
                exe(Path(argv[-1]))
            return 0, "fixture engine, not actual Godot"
        self.m.run = run
        r = self.m.build("R57", "fixture")
        self.assertEqual(self.m.state["builds"]["R57"]["state"], "CANDIDATE")
        self.assertTrue(old.exists())
        self.assertFalse(obsolete.exists())
        self.assertEqual(len(calls), 2)
        self.m.build("R57", "fixture")
        self.assertEqual(len(calls), 2)  # No unnecessary import/export.
        r = self.m.promote("R57", "fixture player acceptance, not real R57")
        self.assertFalse(old.exists())
        self.assertEqual(r["deleted_files"], 1)
        self.assertEqual(self.m.promote("R57", "same fixture")["deleted_files"], 0)

    def test_protected_changed_tracked_busy_and_dry(self):
        protected = self.seed("R56", "ROLLBACK")
        old = self.seed("R50", "OBSOLETE")
        self.assertEqual(self.m.cleanup()["deleted_files"], 0)
        self.assertTrue(old.exists())
        self.m.tracked.add(str(old.relative_to(self.root)).replace("\\", "/"))
        self.assertTrue(self.m.cleanup(True)["skipped"])
        self.m.tracked.clear()
        self.m.busy = lambda: [123]
        self.assertTrue(self.m.cleanup(True)["skipped"])
        self.m.busy = lambda: []
        old.write_bytes(b"other producer changed it")
        self.assertIn("Changed", self.m.cleanup(True)["skipped"][0]["reason"])
        own = {str(protected.relative_to(self.root)).replace("\\", "/"): preview.record(protected.stat())}
        self.assertIn("protected", self.m.cleanup(True, only=own)["skipped"][0]["reason"])

    def test_bad_paths_and_sources(self):
        for rel in ["../outside", "C:/outside", ".git/index", "assets/test.bin", "local-artifacts/source/raw.tif"]:
            if rel in ["../outside", "C:/outside"]:
                with self.assertRaises(ValueError):
                    self.m.safe(rel)
                continue
            path = self.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"do not delete")
            result = self.m.cleanup(True, only={rel: preview.record(path.stat())})
            self.assertTrue(result["skipped"])
            self.assertTrue(path.exists())

    def test_junction_or_symlink(self):
        target = self.root / "external"
        target.mkdir()
        (target / "keep.txt").write_text("keep")
        link = self.root / "builds/link"
        link.parent.mkdir()
        if os.name == "nt":
            subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", f"New-Item -ItemType Junction -Path '{link}' -Target '{target}' | Out-Null"], check=True)
        else:
            link.symlink_to(target, target_is_directory=True)
        try:
            with self.assertRaises(ValueError):
                self.m.safe("builds/link/keep.txt")
            self.assertTrue((target / "keep.txt").exists())
        finally:
            os.rmdir(link) if os.name == "nt" else link.unlink()

    @unittest.skipUnless(os.name == "nt", "Windows file-sharing case")
    def test_occupied_file(self):
        p = self.seed("R50", "OBSOLETE")
        from ctypes import wintypes
        k = ctypes.WinDLL("kernel32", use_last_error=True)
        k.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        k.CreateFileW.restype = wintypes.HANDLE
        k.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = k.CreateFileW(str(p), 0x80000000, 0, None, 3, 0, None)
        self.assertNotEqual(handle, wintypes.HANDLE(-1).value)
        try:
            result = self.m.cleanup(True)
            self.assertEqual(result["deleted_files"], 0)
            self.assertTrue(result["skipped"])
            self.assertTrue(p.exists())
        finally:
            k.CloseHandle(handle)
        self.assertEqual(self.m.cleanup(True)["deleted_files"], 1)
        self.assertEqual(self.m.cleanup(True)["deleted_files"], 0)

    def test_invalid_pack_and_budget(self):
        p = self.root / "fake.exe"
        p.write_bytes(b"bad")
        with self.assertRaises(ValueError):
            preview.verify_exe(p)
        recipe = self.root / "recipe.json"
        recipe.write_text(json.dumps({"jobs": [{"id": "too-large", "temporary_estimate_bytes": 2 * 1024 ** 3}]}))
        with self.assertRaises(ValueError):
            self.m.recipes("recipe.json", False)

    def test_interrupted_attempt_recovery(self):
        rel = "builds/.preview-staging/R57/candidate.tmp"
        p = self.root / rel
        p.parent.mkdir(parents=True)
        p.write_bytes(b"owned partial")
        self.m.state["attempt"] = {"version": "R57", "paths": [rel]}
        self.m.recover_attempt()
        self.assertFalse(p.exists())
        self.assertNotIn("attempt", self.m.state)

    def test_corrupt_success_does_not_replace_candidate(self):
        old = self.seed("R56", "ROLLBACK")
        candidate = self.seed("R57", "CANDIDATE")
        before = candidate.stat().st_mtime_ns
        def run(argv, cwd):
            if "--export-release" in argv:
                Path(argv[-1]).write_bytes(b"exit zero, invalid executable")
            return 0, ""
        self.m.run = run
        with self.assertRaises(ValueError):
            self.m.build("R57", "fixture")
        self.assertTrue(old.exists())
        self.assertEqual(candidate.stat().st_mtime_ns, before)

    def test_recipe_incremental_and_failed_temporary(self):
        inp = self.root / "input.txt"
        inp.write_text("input")
        recipe = self.root / "recipe.json"
        job = {"id": "small", "argv": ["fixture"], "inputs": ["input.txt"], "outputs": ["output.bin"], "temporary_estimate_bytes": 128, "temporary_outputs": ["local-artifacts/fixture/cache.tmp"]}
        recipe.write_text(json.dumps({"jobs": [job]}))
        calls = []
        def run(argv, cwd):
            calls.append(1)
            (self.root / "output.bin").write_bytes(b"official fixture output")
            p = self.root / "local-artifacts/fixture/cache.tmp"
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(b"reproducible")
            return 0, ""
        self.m.run = run
        self.m.recipes("recipe.json", False)
        self.m.cleanup(True)
        self.m.recipes("recipe.json", False)
        self.assertEqual(len(calls), 1)
        inp.write_text("changed input")
        def failed(argv, cwd):
            (self.root / "local-artifacts/fixture/cache.tmp").write_bytes(b"failed")
            raise OSError("producer failure")
        self.m.run = failed
        with self.assertRaises(RuntimeError):
            self.m.recipes("recipe.json", False)
        self.assertFalse((self.root / "local-artifacts/fixture/cache.tmp").exists())
        self.assertTrue((self.root / "output.bin").exists())

    def test_owned_summary_retires_on_promotion(self):
        self.seed("R56", "ROLLBACK")
        self.seed("R57", "CANDIDATE")
        self.m.note("R56", {"result": "fixture summary"})
        self.m.promote("R57", "fixture, not real acceptance")
        self.assertFalse((self.root / "local-artifacts/preview-manager/R56/result.json").exists())

    def test_running_process_prevents_clean(self):
        p = self.seed("R50", "OBSOLETE")
        self.m.busy = lambda: [987]
        self.assertEqual(self.m.cleanup(True)["deleted_files"], 0)
        self.assertTrue(p.exists())

    def test_lock_excludes_second_manager(self):
        with self.m.lock():
            other = preview.Manager(self.root)
            with self.assertRaises(OSError):
                with other.lock():
                    self.fail("Second writer acquired the build lock")

    def test_diagnostic_budget_with_byte_fixtures(self):
        job = {"id": "diag", "argv": ["fixture"], "inputs": [], "outputs": ["output.bin"], "temporary_estimate_bytes": 128, "diagnostic_outputs": ["local-artifacts/diag/a.json", "local-artifacts/diag/b.json"]}
        (self.root / "recipe.json").write_text(json.dumps({"jobs": [job]}))
        def run(argv, cwd):
            (self.root / "output.bin").write_bytes(b"output")
            folder = self.root / "local-artifacts/diag"
            folder.mkdir(parents=True)
            (folder / "a.json").write_bytes(b"a" * 40)
            (folder / "b.json").write_bytes(b"b" * 40)
            return 0, ""
        self.m.run = run
        with patch.object(preview, "DIAGNOSTIC_BUDGET", 64):
            self.m.recipes("recipe.json", False)
        self.assertEqual(self.m.cleanup(True)["deleted_files"], 1)
        self.assertEqual(sum(p.stat().st_size for p in (self.root / "local-artifacts/diag").iterdir()), 40)

    def test_log_budget_and_bounded_process_output(self):
        self.seed("R50", "OBSOLETE")
        with patch.object(preview, "LOG_BUDGET", 64):
            self.m.note("R50", {"tail": "x" * 128})
        self.assertTrue(self.m.state["temporary"])
        self.m.cleanup(True)
        self.assertFalse((self.root / "local-artifacts/preview-manager/R50/result.json").exists())
        with patch.object(preview, "TAIL", 64):
            code, tail = preview.bounded_run([sys.executable, "-c", "print('x'*4096)"], self.root)
        self.assertEqual(code, 0)
        self.assertLessEqual(len(tail.encode()), 64)

    def test_unknown_files_are_not_adopted_as_garbage(self):
        unknown = self.root / "local-artifacts/preview-manager/other-ai/file.json"
        unknown.parent.mkdir(parents=True)
        unknown.write_bytes(b"u" * 256)
        self.seed("R50", "OBSOLETE")
        with patch.object(preview, "LOG_BUDGET", 64):
            self.m.note("R50", {"result": "owned"})
        self.m.cleanup(True)
        self.assertTrue(unknown.exists())
        sibling = self.root / "builds/.preview-staging/R57/candidate.tmp"
        sibling.parent.mkdir(parents=True)
        sibling.write_bytes(b"unknown producer")
        with self.assertRaises(ValueError):
            self.m.build("R57", "fixture")
        self.assertTrue(sibling.exists())

    def test_bootstrap_metadata_receipt_and_no_state_reset(self):
        seeds = {}
        for v, state in [("R56", "ROLLBACK"), ("R57", "CANDIDATE")]:
            rel = f"builds/preview_{v}/{v}.exe"
            exe(self.root / rel)
            seeds[v] = {"state": state, "path": rel, "evidence": "KB fixture"}
        self.m.policy["seed_builds"] = seeds
        self.m.adopt()
        self.assertTrue((self.root / "builds/.preview-inputs.json").exists())
        self.assertEqual(self.m.adopt()["deleted_files"], 0)
        self.m.promote("R57", "fixture player")
        with self.assertRaises((ValueError, FileNotFoundError)):
            self.m.adopt()
        self.assertEqual(self.m.state["builds"]["R57"]["state"], "CURRENT")

    def test_changed_candidate_not_reused(self):
        self.seed("R56", "ROLLBACK")
        def run(argv, cwd):
            if "--export-release" in argv:
                exe(Path(argv[-1]))
            return 0, ""
        self.m.run = run
        self.m.build("R57", "fixture")
        path = self.root / self.m.state["builds"]["R57"]["path"]
        st = path.stat()
        os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 1000000))
        with self.assertRaises(ValueError):
            self.m.build("R57", "fixture")
        self.assertTrue(path.exists())


if __name__ == "__main__":
    unittest.main()
