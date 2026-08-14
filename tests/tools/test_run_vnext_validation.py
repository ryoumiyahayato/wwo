#!/usr/bin/env python3
"""Self-tests for tools/run_vnext_validation.py."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest import mock


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RUNNER_PATH = REPOSITORY_ROOT / "tools" / "run_vnext_validation.py"


def load_runner() -> ModuleType:
    spec = importlib.util.spec_from_file_location("run_vnext_validation", RUNNER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load runner: {RUNNER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


runner = load_runner()


class DiscoverTests(unittest.TestCase):
    def test_discovers_only_vnext_test_suffix_and_sorts_relative_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            paths = [
                root / "tests" / "vnext" / "z_test.gd",
                root / "tests" / "vnext" / "nested" / "a_test.gd",
                root / "tests" / "vnext" / "not_a_test.txt",
                root / "tests" / "vnext" / "almost_test.gd.bak",
                root / "tests" / "other" / "ignored_test.gd",
            ]
            for path in paths:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("", encoding="utf-8")

            found = runner.discover_test_scripts(root)
            relative = [path.relative_to(root).as_posix() for path in found]

            self.assertEqual(
                relative,
                [
                    "tests/vnext/nested/a_test.gd",
                    "tests/vnext/z_test.gd",
                ],
            )

    def test_no_tests_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "tests" / "vnext").mkdir(parents=True)
            with self.assertRaisesRegex(runner.ValidationError, "no vNext test scripts"):
                runner.discover_test_scripts(root)

    def test_focused_and_long_run_suites_partition_the_long_test(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            for relative in (
                "tests/vnext/market_economy_long_term_test.gd",
                "tests/vnext/market_economy_test.gd",
                "tests/vnext/nested/a_test.gd",
            ):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("", encoding="utf-8")

            focused = [
                path.relative_to(root).as_posix()
                for path in runner.discover_test_scripts(root, "focused")
            ]
            long_run = [
                path.relative_to(root).as_posix()
                for path in runner.discover_test_scripts(root, "long-run")
            ]

            self.assertEqual(
                focused,
                [
                    "tests/vnext/market_economy_test.gd",
                    "tests/vnext/nested/a_test.gd",
                ],
            )
            self.assertEqual(
                long_run,
                ["tests/vnext/market_economy_long_term_test.gd"],
            )

    def test_unknown_suite_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "tests" / "vnext").mkdir(parents=True)
            with self.assertRaisesRegex(runner.ValidationError, "unknown validation suite"):
                runner.discover_test_scripts(root, "skipped")


class LogAnalysisTests(unittest.TestCase):
    def test_fatal_pattern_is_detected(self) -> None:
        reasons = runner.find_log_failure_reasons("SCRIPT ERROR: bad fixture")
        self.assertTrue(any("SCRIPT ERROR" in reason for reason in reasons))

    def test_nonzero_failures_are_detected(self) -> None:
        reasons = runner.find_log_failure_reasons("Example: 12 checks, 2 failures")
        self.assertTrue(any("nonzero failures" in reason for reason in reasons))

    def test_missing_success_summary_fails(self) -> None:
        result = runner.ProcessResult(0, "PASS: something", "")
        reasons = runner.evaluate_test_result(result)
        self.assertIn("missing valid nonzero checks / 0 failures summary", reasons)

    def test_zero_checks_is_not_a_success_summary(self) -> None:
        result = runner.ProcessResult(0, "Example: 0 checks, 0 failures", "")
        reasons = runner.evaluate_test_result(result)
        self.assertIn("missing valid nonzero checks / 0 failures summary", reasons)

    def test_valid_summary_passes(self) -> None:
        result = runner.ProcessResult(0, "Example: 7 checks, 0 failures", "")
        self.assertEqual(runner.evaluate_test_result(result), [])

    def test_nonzero_process_exit_code_fails(self) -> None:
        result = runner.ProcessResult(3, "Example: 7 checks, 0 failures", "")
        reasons = runner.evaluate_test_result(result)
        self.assertIn("process exit code is 3", reasons)

    def test_timeout_is_reported_explicitly(self) -> None:
        result = runner.ProcessResult(
            1,
            "Example: 7 checks, 0 failures",
            "",
            timed_out=True,
            elapsed_seconds=12.5,
        )
        reasons = runner.evaluate_test_result(result)
        self.assertIn("process timed out after 12.5s", reasons)


class TimeoutSelectionTests(unittest.TestCase):
    def test_long_term_test_has_separate_timeout_override(self) -> None:
        command = (
            "godot",
            "--script",
            runner.LONG_TEST_SCRIPT,
        )
        with mock.patch.dict(
            "os.environ",
            {"VNEXT_LONG_TEST_TIMEOUT_SECONDS": "777"},
            clear=False,
        ):
            self.assertEqual(runner._command_timeout_seconds(command), 777)

    def test_nonpositive_timeout_is_rejected(self) -> None:
        with mock.patch.dict(
            "os.environ",
            {"VNEXT_TEST_TIMEOUT_SECONDS": "0"},
            clear=False,
        ):
            with self.assertRaisesRegex(runner.ValidationError, "positive integer"):
                runner._command_timeout_seconds(("godot", "--script", "res://tests/vnext/example_test.gd"))


class ValidationFlowTests(unittest.TestCase):
    def test_import_runs_once_before_sorted_tests(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            for relative in (
                "tests/vnext/z_test.gd",
                "tests/vnext/nested/a_test.gd",
            ):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("", encoding="utf-8")

            calls = []

            def fake_run(command, command_root):
                calls.append(tuple(command))
                if "--editor" in command:
                    return runner.ProcessResult(0, "import ok", "")
                return runner.ProcessResult(0, "Example: 1 checks, 0 failures", "")

            with mock.patch.object(runner, "run_process", side_effect=fake_run):
                exit_code = runner.run_validation(root, Path("/fake/godot"))

            self.assertEqual(exit_code, 0)
            self.assertEqual(sum("--editor" in call for call in calls), 1)
            scripts = [
                call[call.index("--script") + 1]
                for call in calls
                if "--script" in call
            ]
            self.assertEqual(
                scripts,
                [
                    "res://tests/vnext/nested/a_test.gd",
                    "res://tests/vnext/z_test.gd",
                ],
            )


if __name__ == "__main__":
    unittest.main()
