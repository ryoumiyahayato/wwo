from pathlib import Path

path = Path("scripts/ui_spikes/holographic_workspace/holographic_workspace_interaction_probe.gd")
text = path.read_text(encoding="utf-8")
old = '''workspace.set("selected_country_id", "russian_empire")
\tworkspace.call("_focus_selected_country")
\tvar russian_territories: Array = (workspace.get("_history_territories_by_entity") as Dictionary).get("russian_empire", []) as Array
\tif not _require(russian_territories.size() >= 10, "俄罗斯帝国没有保留多辖区结构"):
\t\treturn
\tworkspace.call("_return_to_global_world")'''
new = '''workspace.set("selected_country_id", "russian_empire")
\tworkspace.call("_focus_selected_country")
\tvar russian_territories: Array = (workspace.get("_history_territories_by_entity") as Dictionary).get("russian_empire", []) as Array
\tif not _require(
\t\trussian_territories.size() == 1
\t\tand str((russian_territories[0] as Dictionary).get("iso_a3", "")) == "RUS",
\t\t"俄罗斯帝国本土没有保持为CShapes历史政治核心"
\t):
\t\treturn
\tvar dated_units: Array = (workspace.get("_dated_units_document") as Dictionary).get("units", []) as Array
\tvar russian_protected_units := 0
\tfor unit_value: Variant in dated_units:
\t\tvar unit := unit_value as Dictionary
\t\tif str(unit.get("controller_id", "")) == "russian_empire":
\t\t\trussian_protected_units += 1
\tif not _require(russian_protected_units >= 2, "俄罗斯保护国没有作为独立历史政治单元保留"):
\t\treturn
\tworkspace.call("_return_to_global_world")'''
if new in text:
    raise SystemExit(0)
if old not in text:
    raise SystemExit("outdated Russia assertion block not found")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
