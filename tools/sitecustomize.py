from __future__ import annotations

import subprocess
from pathlib import Path, PurePosixPath
from typing import Iterable

_AUDIT_INFRASTRUCTURE_PATHS = {
    "tools/sitecustomize.py",
    "tools/run_tracked_dependency_audit.py",
    "tests/tools/test_tracked_audit_inputs.py",
}


def normalize_audit_text_bytes(data: bytes) -> bytes:
    """Normalize audit text input line endings without changing repository files."""
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def iter_tracked_scan_files(root: Path, audit_module) -> Iterable[Path]:
    """Yield only Git-tracked audit inputs with platform-independent paths."""
    completed = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        check=True,
        capture_output=True,
    )
    tracked = completed.stdout.decode("utf-8").split("\0")
    for value in sorted(item for item in tracked if item):
        if value in _AUDIT_INFRASTRUCTURE_PATHS:
            continue
        relative = PurePosixPath(value)
        if any(part in audit_module.IGNORED_PARTS for part in relative.parts):
            continue
        path = root.joinpath(*relative.parts)
        if not path.is_file():
            continue
        if (
            path.suffix.lower() not in audit_module.SCAN_SUFFIXES
            and path.name not in {"project.godot", "export_presets.cfg"}
        ):
            continue
        yield path


try:
    import audit_formal_v23_dependencies as _formal_v23_audit
except ModuleNotFoundError:
    _formal_v23_audit = None

if _formal_v23_audit is not None:
    _raw_git_blob_sha = _formal_v23_audit.git_blob_sha

    def _normalized_audit_text_blob_sha(data: bytes) -> str:
        return _raw_git_blob_sha(normalize_audit_text_bytes(data))

    _formal_v23_audit.iter_scan_files = (
        lambda root: iter_tracked_scan_files(root, _formal_v23_audit)
    )
    _formal_v23_audit.git_blob_sha = _normalized_audit_text_blob_sha
