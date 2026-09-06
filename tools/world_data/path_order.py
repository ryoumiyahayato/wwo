"""Cross-platform canonical ordering for repository-derived paths.

Canonical collation is the case-sensitive Unicode/code-point order of a
normalized relative POSIX path string.  The comparison never uses native
``Path`` ordering, filesystem enumeration order, host separators, casefold,
``os.name``, or platform-specific branches.  With this rule ``LICENSE.json``
sorts before ``countries/...`` because ``L`` precedes ``c`` by code point.

Callers pass the stable semantic root for the path set.  Repository scans
use the repository root; scans of an external generated-artifact directory
use that directory as the stable root.  Adding the same common prefix to
every path does not change this ordering.
"""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path


def canonical_relative_posix_path(path: Path, root: Path) -> str:
    """Return the normalized relative POSIX string used as the sort key."""
    return path.relative_to(root).as_posix()


def canonical_path_sort(paths: Iterable[Path], root: Path) -> list[Path]:
    """Materialize *paths* in the repository's one canonical path order."""
    return sorted(paths, key=lambda path: canonical_relative_posix_path(path, root))
