#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import sitecustomize  # noqa: F401  # installs the Git-tracked input adapter
import run_formal_v23_dependency_audit as audit_runner


if __name__ == "__main__":
    raise SystemExit(audit_runner.main())
