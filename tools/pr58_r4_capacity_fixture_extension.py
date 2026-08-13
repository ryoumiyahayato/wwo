from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch(path: str, label: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    call = f'\t_check(state_map.load_existing_map(state_spatial), "{label} fixture adapter attaches Spatial world")\n'
    if call not in text:
        raise RuntimeError(f"{path}: fixture adapter call missing")
    if "_configure_r4_spatial_capacity_baseline(state_spatial, state_map)" not in text:
        text = text.replace(call, call + "\t_configure_r4_spatial_capacity_baseline(state_spatial, state_map)\n", 1)
    if "func _configure_r4_spatial_capacity_baseline(" not in text:
        marker = "func _check(condition: bool, label: String) -> void:"
        helper = '''func _configure_r4_spatial_capacity_baseline(
\tstate_spatial: VNextSpatialWorld, state_map: VNextMilitaryMapAdapter
) -> void:
\t# Preserve the exact pre-PR62 R4 physical-throughput fixture values while
\t# routing them through Spatial authority. This is test data, not production
\t# Military capacity authority.
\tfor link: Dictionary in state_map.get_all_links():
\t\tvar mode: String = str(link.get("mode", ""))
\t\tvar personnel_capacity: float = 0.0
\t\tvar reliability: float = 0.0
\t\tmatch mode:
\t\t\t"road":
\t\t\t\tpersonnel_capacity = 8000.0
\t\t\t\treliability = 0.82
\t\t\t"rail":
\t\t\t\tpersonnel_capacity = 24000.0
\t\t\t\treliability = 0.96
\t\t\t"shipping":
\t\t\t\tpersonnel_capacity = 50000.0
\t\t\t\treliability = 0.78
\t\tvar movement_hours: float = maxf(1.0, float(link.get("movement_hours", 1.0)))
\t\tvar per_hour: float = personnel_capacity * reliability / movement_hours
\t\tif per_hour > 0.0:
\t\t\t_check(state_spatial.set_nominal_capacity(str(link.get("id", "")), per_hour), "R4 capacity fixture is owned by Spatial")


'''
        if marker not in text:
            raise RuntimeError(f"{path}: _check marker missing")
        text = text.replace(marker, helper + marker, 1)
    p.write_text(text, encoding="utf-8", newline="\n")


patch("tests/vnext/military_strategy_test.gd", "Military")
patch("tests/vnext/military_r3_findings_test.gd", "R3")
print("R4 Spatial capacity test baseline configured")
