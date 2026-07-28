from pathlib import Path


def replace_once(path: Path, old: str, new: str, description: str) -> bool:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return False
    if old not in text:
        raise SystemExit(f"{description} anchor not found")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return True


interaction_path = Path(
    "scripts/ui_spikes/holographic_workspace/holographic_workspace_interaction_probe.gd"
)
interaction_old = '''workspace.set("selected_country_id", "russian_empire")
\tworkspace.call("_focus_selected_country")
\tvar russian_territories: Array = (workspace.get("_history_territories_by_entity") as Dictionary).get("russian_empire", []) as Array
\tif not _require(russian_territories.size() >= 10, "俄罗斯帝国没有保留多辖区结构"):
\t\treturn
\tworkspace.call("_return_to_global_world")'''
interaction_new = '''workspace.set("selected_country_id", "russian_empire")
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
replace_once(
    interaction_path,
    interaction_old,
    interaction_new,
    "interaction probe Russia assertion",
)

admin_probe_path = Path(
    "scripts/ui_spikes/holographic_workspace/holographic_workspace_admin1_probe.gd"
)
admin_old = '''\tvar russian_territories: Array = (workspace.get("_history_territories_by_entity") as Dictionary).get("russian_empire", []) as Array
\tif not _require(russian_territories.size() >= 12, "俄罗斯帝国没有聚合足够的辖区"):
\t\treturn
'''
admin_new = '''\tvar russian_territories: Array = (workspace.get("_history_territories_by_entity") as Dictionary).get("russian_empire", []) as Array
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
'''
replace_once(
    admin_probe_path,
    admin_old,
    admin_new,
    "admin1 probe Russia assertion",
)

runtime_path = Path(
    "scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd"
)
runtime_text = runtime_path.read_text(encoding="utf-8")
runtime_method = '''func _legacy_navigation_key(entity_id: String, gwcode: int) -> String:
\tvar profile := _major_state_profile_by_entity.get(entity_id, {}) as Dictionary
\tfor alias_value: Variant in (profile.get("aliases", []) as Array):
\t\tvar alias := str(alias_value).strip_edges().to_upper()
\t\tif alias.length() == 3:
\t\t\treturn alias
\treturn super._legacy_navigation_key(entity_id, gwcode)


'''
if runtime_method not in runtime_text:
    anchor = "func _home_historical_entity_id() -> String:\n"
    if anchor not in runtime_text:
        raise SystemExit("generic navigation-key insertion anchor not found")
    runtime_path.write_text(
        runtime_text.replace(anchor, runtime_method + anchor, 1),
        encoding="utf-8",
    )
