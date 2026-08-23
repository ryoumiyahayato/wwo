#!/usr/bin/env python3
"""Targeted Wave 0 gates for WWO's actual Formal product path and evidence."""

from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any

MENU_SCENE = "res://scenes/formal/formal_world_menu.tscn"
PRODUCT_SCENE = "res://scenes/formal/formal_world_main.tscn"
APPLICATION_SCRIPT = "res://scripts/formal/formal_world_application.gd"
REQUIRED_SCREENSHOTS = {
    "01_BOOT": "01_boot.png",
    "02_WORLD": "02_world.png",
    "03_COUNTRY": "03_france_country.png",
    "04_LOCAL_GEOGRAPHY": "04_france_local.png",
    "05_CITY": "05_city_if_available.png",
    "06_POLITICS": "06_politics_actual_state.png",
    "07_MILITARY": "07_military_actual_state.png",
    "08_PRODUCT_PROVENANCE": "08_provenance.png",
    "09_TIME_BEFORE": "09_time_before.png",
    "10_TIME_AFTER": "10_time_after.png",
    "11_SAVE": "11_save.png",
    "12_ADVANCE": "12_advance.png",
    "13_RESTORE": "13_restore.png",
}
REQUIRED_OWNER_LABELS = {
    "PRODUCT ENTRY",
    "WORLD/POLITICAL OWNER",
    "TIME OWNER",
    "ECONOMY OWNER",
    "SPATIAL OWNER",
    "POPULATION OWNER",
    "ORGANIZATION OWNER",
    "POLITICS OWNER",
    "MILITARY OWNER",
    "PERSISTENCE OWNER",
}


def _text(project_root: Path, resource_path: str) -> str:
    path = project_root / resource_path.removeprefix("res://")
    return path.read_text(encoding="utf-8")


def _extends_path(source: str) -> str | None:
    match = re.search(r'^extends\s+"(res://[^"]+)"', source, re.MULTILINE)
    return match.group(1) if match else None


def _inheritance_chain(project_root: Path, first_script: str) -> list[str]:
    output: list[str] = []
    current: str | None = first_script
    while current is not None:
        if current in output:
            raise ValueError(f"inheritance cycle at {current}")
        output.append(current)
        current = _extends_path(_text(project_root, current))
    return output


def validate_product_path(project_root: Path) -> list[str]:
    failures: list[str] = []
    project_source = (project_root / "project.godot").read_text(encoding="utf-8")
    if f'run/main_scene="{MENU_SCENE}"' not in project_source:
        failures.append("project.godot does not point to the Formal menu")

    menu_source = _text(project_root, "res://scripts/formal/formal_world_menu.gd")
    if f'const WORLD_SCENE: String = "{PRODUCT_SCENE}"' not in menu_source:
        failures.append("Formal menu does not enter the actual Formal product scene")

    main_scene = _text(project_root, PRODUCT_SCENE)
    if f'path="{APPLICATION_SCRIPT}"' not in main_scene:
        failures.append("Formal product scene does not construct FormalWorldApplication")

    application_source = _text(project_root, APPLICATION_SCRIPT)
    required_boundaries = {
        "prototype document boundary": "product_runtime_gate.filter_document",
        "spike city quarantine": "func _install_spike_city_coverage()",
        "agenda event quarantine": "func _seed_world_events()",
        "legacy conflict quarantine": "func _load_historical_conflicts()",
        "modern Admin-1 quarantine": "func _load_world_admin1_data()",
        "neutral product session": 'active_character_key = "product_session"',
        "runtime-derived provenance": "ProductRuntimeProvenance.capture(_runtime_owner_specs())",
        "product gate report": "func product_integration_gate_report()",
    }
    for label, token in required_boundaries.items():
        if token not in application_source:
            failures.append(f"missing {label}")

    root_sources = "\n".join((project_source, menu_source, main_scene, application_source))
    forbidden_root_dependencies = {
        "test root": r"res://tests/",
        "fixture root": r"res://[^\"']*fixture",
        "demo main scene": r"res://[^\"']*demo[^\"']*\.tscn",
        "vNext product composition": r"res://scripts/vnext/",
    }
    for label, pattern in forbidden_root_dependencies.items():
        if re.search(pattern, root_sources, re.IGNORECASE):
            failures.append(f"normal product root contains forbidden {label} dependency")

    try:
        chain = _inheritance_chain(project_root, APPLICATION_SCRIPT)
    except (OSError, ValueError) as error:
        failures.append(f"cannot resolve actual inheritance chain: {error}")
        chain = []
    expected_parent = (
        "res://scripts/ui_spikes/holographic_workspace/"
        "holographic_workspace_historical_admin_runtime.gd"
    )
    expected_base = (
        "res://scripts/ui_spikes/holographic_workspace/"
        "holographic_workspace_runtime.gd"
    )
    if not chain or chain[1:2] != [expected_parent]:
        failures.append("FormalWorldApplication no longer has the audited composition parent")
    if expected_base not in chain:
        failures.append("actual Formal composition chain does not resolve to workspace runtime")

    gate_source = _text(project_root, "res://scripts/formal/product_runtime_gate.gd")
    for token in ("prototype_only", "prototype_notice", "modern_reference_only"):
        if token not in gate_source:
            failures.append(f"fail-closed document gate does not reject {token}")
    return failures


def _git_head(project_root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=project_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    return struct.unpack(">II", header[16:24])


def validate_manifest(
    manifest_path: Path, expected_head: str, require_files: bool = True
) -> list[str]:
    failures: list[str] = []
    try:
        document = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read screenshot manifest: {error}"]
    records = document.get("screenshots", [])
    if not isinstance(records, list):
        return ["manifest screenshots must be an array"]
    by_id = {
        str(record.get("screenshot_id", "")): record
        for record in records
        if isinstance(record, dict)
    }
    missing = set(REQUIRED_SCREENSHOTS) - set(by_id)
    extra = set(by_id) - set(REQUIRED_SCREENSHOTS)
    if missing:
        failures.append("missing screenshot ids: " + ", ".join(sorted(missing)))
    if extra:
        failures.append("unexpected screenshot ids: " + ", ".join(sorted(extra)))

    for screenshot_id, expected_filename in REQUIRED_SCREENSHOTS.items():
        record = by_id.get(screenshot_id)
        if record is None:
            continue
        if str(record.get("HEAD", "")) != expected_head:
            failures.append(f"{screenshot_id}: HEAD does not match audited runtime")
        if str(record.get("entry_scene", "")) != MENU_SCENE:
            failures.append(f"{screenshot_id}: evidence did not use default entry")
        expected_runtime = MENU_SCENE if screenshot_id == "01_BOOT" else PRODUCT_SCENE
        if str(record.get("runtime_scene", "")) != expected_runtime:
            failures.append(f"{screenshot_id}: alternate or unexpected runtime scene")
        if bool(record.get("synthetic_fixture", True)):
            failures.append(f"{screenshot_id}: synthetic fixture is not allowed")
        if bool(record.get("legacy_prototype_content_visible", True)):
            failures.append(f"{screenshot_id}: legacy/prototype presentation is visible")
        if str(record.get("filename", "")) != expected_filename:
            failures.append(f"{screenshot_id}: observational filename mismatch")
        owners = record.get("actual_runtime_owners", {})
        if not isinstance(owners, dict):
            failures.append(f"{screenshot_id}: actual_runtime_owners is missing")
        else:
            absent_owners = REQUIRED_OWNER_LABELS - set(owners)
            if absent_owners:
                failures.append(
                    f"{screenshot_id}: missing runtime owners "
                    + ", ".join(sorted(absent_owners))
                )
        if not str(record.get("objectively_demonstrates", "")).strip():
            failures.append(f"{screenshot_id}: objective observation is missing")
        if require_files:
            image_path = manifest_path.parent / expected_filename
            try:
                if image_path.stat().st_size < 10_000:
                    failures.append(f"{screenshot_id}: screenshot file is unexpectedly small")
                if _png_dimensions(image_path) != (1280, 720):
                    failures.append(f"{screenshot_id}: screenshot is not the 1280x720 product client")
            except (OSError, ValueError) as error:
                failures.append(f"{screenshot_id}: invalid screenshot file: {error}")

    for screenshot_id in ("03_COUNTRY", "04_LOCAL_GEOGRAPHY", "05_CITY"):
        if screenshot_id in by_id and str(by_id[screenshot_id].get("selected_country", "")) != "country_fra":
            failures.append(f"{screenshot_id}: expected observational France selection")
    if "04_LOCAL_GEOGRAPHY" in by_id and str(by_id["04_LOCAL_GEOGRAPHY"].get("selected_region", "")):
        failures.append("04_LOCAL_GEOGRAPHY: unsupported region identity was selected")
    if "05_CITY" in by_id and str(by_id["05_CITY"].get("selected_city", "")):
        failures.append("05_CITY: unsupported city identity was selected")

    def minutes(screenshot_id: str) -> int | None:
        value: Any = by_id.get(screenshot_id, {}).get("formal_total_minutes")
        return value if isinstance(value, int) else None

    before, after = minutes("09_TIME_BEFORE"), minutes("10_TIME_AFTER")
    if before is None or after is None or after <= before:
        failures.append("09/10: manifest does not prove forward Formal time")
    saved, advanced, restored = (
        minutes("11_SAVE"),
        minutes("12_ADVANCE"),
        minutes("13_RESTORE"),
    )
    if saved is None or advanced is None or restored is None:
        failures.append("11/12/13: save/advance/restore times are incomplete")
    elif not (advanced > saved and restored == saved):
        failures.append("11/12/13: manifest does not prove narrow save restoration")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument("--manifest", type=Path)
    arguments = parser.parse_args()
    project_root = arguments.project_root.resolve()
    failures = validate_product_path(project_root)
    if arguments.manifest is not None:
        failures.extend(
            validate_manifest(arguments.manifest.resolve(), _git_head(project_root))
        )
    if failures:
        for failure in failures:
            print("FAIL:", failure)
        return 1
    print("Wave 0 product path gate: PASS")
    if arguments.manifest is not None:
        print("Wave 0 screenshot provenance gate: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
