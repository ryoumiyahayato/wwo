from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The post-PR62 fixture isolates one Spatial/Military map context per state.
# Apply the forced attacker-loss rule after that context exists, otherwise the
# override lands on the previous test's map and is silently discarded.
strategy_path = ROOT / "tests/vnext/military_strategy_test.gd"
text = strategy_path.read_text(encoding="utf-8")
old = '''func _test_attacker_annihilation() -> void:\n\tvar old_loss := float(map.battle_rules.get("defender_win_loss_rate", 0.18))\n\tmap.battle_rules["defender_win_loss_rate"] = 1.0\n\tvar state := _battle_state(1, 50000)\n'''
new = '''func _test_attacker_annihilation() -> void:\n\t# _battle_state() creates the isolated per-state Spatial/Military map context.\n\t# Apply the forced-loss fixture to that authoritative context, not the map\n\t# object from the previous test.\n\tvar state := _battle_state(1, 50000)\n\tvar old_loss := float(map.battle_rules.get("defender_win_loss_rate", 0.18))\n\tmap.battle_rules["defender_win_loss_rate"] = 1.0\n'''
if text.count(old) != 1:
    raise RuntimeError(f"attacker annihilation fixture block: expected one match, got {text.count(old)}")
strategy_path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
print("PR58 attacker-annihilation isolated-map fixture corrected")

# The integration-test generator is intentionally a Python raw string. One
# blank line was accidentally written as the literal two characters `\\n`;
# after tab expansion that leaves an illegal backslash in GDScript source.
# Repair only that generator artifact; assertions and runtime code are unchanged.
integration_path = ROOT / "tests/vnext/military_spatial_capacity_integration_test.gd"
integration = integration_path.read_text(encoding="utf-8")
syntax_old = "\\n\tvar military_snapshot := state.snapshot()"
syntax_new = "\n\tvar military_snapshot := state.snapshot()"
if integration.count(syntax_old) != 1:
    raise RuntimeError(f"integration-test literal newline: expected one match, got {integration.count(syntax_old)}")
integration_path.write_text(integration.replace(syntax_old, syntax_new, 1), encoding="utf-8", newline="\n")
print("PR58 post-PR62 integration-test literal newline corrected")
