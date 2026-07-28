from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_PATHS = [
    ".github/workflows/alpha-commodity-economy.yml",
    ".github/workflows/cleanup-completed-agent-branches.yml",
]


def main() -> None:
    for path in WORKFLOW_PATHS:
        subprocess.run(
            ["git", "checkout", "HEAD", "--", path],
            cwd=ROOT,
            check=True,
        )
    print("workflow files restored; connector will apply governance changes separately")


if __name__ == "__main__":
    main()
