from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "tests/vnext/military_strategy_test.gd"

text = PATH.read_text(encoding="utf-8")
old = '''func _test_attacker_annihilation() -> void:\n\tvar old_loss := float(map.battle_rules.get("defender_win_loss_rate", 0.18))\n\tmap.battle_rules["defender_win_loss_rate"] = 1.0\n\tvar state := _battle_state(1, 50000)\n'''
new = '''func _test_attacker_annihilation() -> void:\n\t# _battle_state() creates the isolated per-state Spatial/Military map context.\n\t# Apply the forced-loss fixture to that authoritative context, not the map\n\t# object from the previous test.\n\tvar state := _battle_state(1, 50000)\n\tvar old_loss := float(map.battle_rules.get("defender_win_loss_rate", 0.18))\n\tmap.battle_rules["defender_win_loss_rate"] = 1.0\n'''
if text.count(old) != 1:
    raise RuntimeError(f"attacker annihilation fixture block: expected one match, got {text.count(old)}")
PATH.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
print("PR58 attacker-annihilation isolated-map fixture corrected")
