from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise RuntimeError(f"{label}: expected one match, got {text.count(old)}")
    return text.replace(old, new, 1)


def main() -> None:
    path = "scripts/vnext/spatial/spatial_world.gd"
    text = read(path)
    if "func effective_capacity(link_id: String) -> float:" not in text:
        marker = "func infrastructure_state(link_id: String) -> Dictionary:\n"
        helper = '''func effective_capacity(link_id: String) -> float:
\t# Allocation-independent physical query for routing/access consumers. This
\t# reads the authoritative InfrastructureLinkState directly and never creates
\t# a second capacity ledger.
\tvar state: VNextInfrastructureLinkState = _state_for_link(link_id)
\treturn 0.0 if state == null else state.effective_capacity()


'''
        text = replace_once(text, marker, helper + marker, "Spatial effective capacity query")
        write(path, text)

    path = "scripts/vnext/map/military_map_adapter.gd"
    text = read(path)
    old = '''func get_link_transport_capacity_per_hour(link_id: String) -> float:
\t# Compatibility query only. The value is read from authoritative Spatial state;
\t# Military never derives or mutates total physical capacity here.
\tif spatial_world == null or not spatial_world.is_valid():
\t\treturn 0.0
\tvar state: Dictionary = spatial_world.infrastructure_state(link_id)
\treturn maxf(0.0, float(state.get("effective_capacity", 0.0)))'''
    new = '''func get_link_transport_capacity_per_hour(link_id: String) -> float:
\t# Compatibility query only. The value is read directly from authoritative
\t# Spatial InfrastructureLinkState and never from a Military-owned budget.
\tif spatial_world == null or not spatial_world.is_valid():
\t\treturn 0.0
\treturn maxf(0.0, spatial_world.effective_capacity(link_id))'''
    text = replace_once(text, old, new, "Military direct effective capacity query")
    write(path, text)

    path = "tests/vnext/spatial_infrastructure_test.gd"
    text = read(path)
    needle = '\t_equal(world.infrastructure_state(link_id).get("effective_capacity"), 100.0, "operational effective capacity equals nominal")\n'
    if "direct effective-capacity query matches authoritative state" not in text:
        text = replace_once(
            text,
            needle,
            needle + '\t_equal(world.effective_capacity(link_id), 100.0, "direct effective-capacity query matches authoritative state")\n',
            "Spatial effective capacity regression",
        )
        write(path, text)

    path = "docs/vnext/spatial_infrastructure.md"
    text = read(path)
    if "`effective_capacity(link_id)`" not in text:
        anchor = "`capacity_summary()` exposes\n"
        replacement = "`effective_capacity(link_id)` exposes the authoritative physical capacity without evaluating current reservations, for routing/access checks that do not need allocation state. `capacity_summary()` exposes\n"
        text = replace_once(text, anchor, replacement, "Spatial effective query docs")
        write(path, text)

    print("Direct Spatial effective-capacity query applied successfully")


if __name__ == "__main__":
    main()
