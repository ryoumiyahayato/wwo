#!/usr/bin/env python3
from __future__ import annotations

import re

import audit_variable_state as audit

# GDScript permits inferred member declarations with `:=`. The original scanner
# accepted only `=`, which omitted service references and mutable containers.
audit.MEMBER_RE = re.compile(
    r"^(?P<mods>(?:(?:static\s+)|(?:@\w+(?:\([^)]*\))?\s+))*)"
    r"(?P<kind>var|const)\s+"
    r"(?P<name>[A-Za-z_]\w*)"
    r"(?:\s*:\s*(?P<type>[^=:]+?))?"
    r"(?:\s*(?::=|=)\s*(?P<init>.*))?$"
)

if __name__ == "__main__":
    audit.main()
