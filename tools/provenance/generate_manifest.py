#!/usr/bin/env python3
"""Generate the deterministic WWO data and asset provenance manifest.

The scanner is deliberately conservative. It records provenance that is
explicitly present in repository data, documentation, and generator scripts;
it never turns a filename or a familiar dataset name into a guessed license.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
MANIFEST_RELATIVE = "docs/data_sources/provenance_manifest.json"
SCOPE_ROOTS = ("data/", "assets/", "docs/")

SOURCE_UNKNOWN = "SOURCE_UNKNOWN"
LICENSE_UNKNOWN = "LICENSE_UNKNOWN"
GENERATOR_UNKNOWN = "GENERATOR_UNKNOWN"
PROVENANCE_INCOMPLETE = "PROVENANCE_INCOMPLETE"
SOURCE_MISSING = "SOURCE_MISSING"
LICENSE_NOT_APPLICABLE = "NOT_APPLICABLE"

FLAG_REGISTRY = "data/world_map/historical/flags_1900.json"
FLAG_ATTRIBUTION = "data/world_map/historical/FLAG_ASSET_ATTRIBUTION.md"
FLAG_GENERATOR = "tools/historical_data/build_1900_flag_registry_fast.py"
CSHAPES_SNAPSHOT = "data/world_map/historical/cshapes_1900_snapshot.json"
CSHAPES_ATTRIBUTION = "data/world_map/historical/CShapes-2.0-ATTRIBUTION.md"
CSHAPES_GENERATOR = "tools/historical_data/build_cshapes_1900_snapshot.py"
ENTITY_GENERATOR = "tools/historical_data/build_1900_entity_registry.py"
CITY_GENERATOR = "tools/world_map/generate_city_shards.py"
ECONOMY_GENERATOR = "tools/build_1900_world_economy_estimates.py"
COMPACT_GENERATOR = "tools/compact_1900_world_economy_estimates.py"

MIME_TYPES = {
    ".gd": "text/x-gdscript",
    ".json": "application/json",
    ".md": "text/markdown",
    ".png": "image/png",
    ".py": "text/x-python",
}


def normalize_path(value: str) -> str:
    return value.replace("\\", "/").removeprefix("./")


def strip_resource_prefix(value: str) -> str:
    return normalize_path(value).removeprefix("res://")


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def unique(values: Iterable[str]) -> list[str]:
    return sorted({value for value in values if value})


def aggregate_text(values: Iterable[str], unknown: str = SOURCE_UNKNOWN) -> str:
    clean = unique(value for value in values if value and value != unknown)
    if not clean:
        return unknown
    return "; ".join(clean)


def aggregate_license(values: Iterable[str]) -> str:
    clean = unique(value for value in values if value and value != LICENSE_UNKNOWN)
    has_unknown = any(not value or value == LICENSE_UNKNOWN for value in values)
    if not clean:
        return LICENSE_UNKNOWN
    if has_unknown:
        return "MIXED_EXPLICIT_AND_UNKNOWN"
    if len(clean) == 1:
        return clean[0]
    return "MIXED_EXPLICIT_LICENSES"


def source_ref(source_id: str) -> str:
    return "external:declared:" + source_id


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def tracked_files(root: Path) -> list[str]:
    committed = subprocess.run(
        ["git", "-C", str(root), "ls-tree", "-r", "--name-only", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    staged = subprocess.run(
        ["git", "-C", str(root), "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        check=True,
        capture_output=True,
        text=True,
    )
    staged_paths = [
        normalize_path(item)
        for item in staged.stdout.splitlines()
        if normalize_path(item).startswith("docs/data_sources/")
    ]
    paths = [*committed.stdout.splitlines(), *staged_paths]
    return sorted(
        path
        for path in {normalize_path(item) for item in paths if item}
        if path != MANIFEST_RELATIVE and path.startswith(SCOPE_ROOTS)
    )


def file_type(path: str) -> str:
    suffix = Path(path).suffix.lower()
    return MIME_TYPES.get(suffix, "application/octet-stream")


class SourceCatalog:
    def __init__(self) -> None:
        self._items: dict[str, dict[str, Any]] = {}

    def add(
        self,
        source_id: str,
        name: str,
        *,
        locators: Iterable[str] = (),
        author_institution: str = SOURCE_UNKNOWN,
        license_name: str = LICENSE_UNKNOWN,
        license_locators: Iterable[str] = (),
        evidence: Iterable[str] = (),
    ) -> str:
        item = self._items.setdefault(
            source_id,
            {
                "id": source_id,
                "name": name or SOURCE_UNKNOWN,
                "source_locator": [],
                "author_institution": SOURCE_UNKNOWN,
                "license": LICENSE_UNKNOWN,
                "license_locator": [],
                "evidence": [],
            },
        )
        if name and item["name"] == SOURCE_UNKNOWN:
            item["name"] = name
        elif name and item["name"] != name and name not in item["name"].split("; "):
            item["name"] = aggregate_text([item["name"], name])
        item["source_locator"] = unique([*item["source_locator"], *locators])
        item["license_locator"] = unique([*item["license_locator"], *license_locators])
        item["evidence"] = unique([*item["evidence"], *evidence])
        authors = [item["author_institution"], author_institution]
        item["author_institution"] = aggregate_text(authors)
        if item["license"] == LICENSE_UNKNOWN:
            item["license"] = license_name or LICENSE_UNKNOWN
        elif license_name and license_name != LICENSE_UNKNOWN:
            item["license"] = aggregate_license([item["license"], license_name])
        return source_id

    def values(self) -> list[dict[str, Any]]:
        return [self._items[key] for key in sorted(self._items)]


def make_entry(root: Path, relative: str) -> dict[str, Any]:
    path = root / Path(relative)
    return {
        "path": relative,
        "file_type": file_type(relative),
        "size_bytes": path.stat().st_size,
        "sha256": file_sha256(path),
        "category": "unknown",
        "kind": "unknown",
        "known_source": SOURCE_UNKNOWN,
        "source_locator": [],
        "author_institution": SOURCE_UNKNOWN,
        "license": LICENSE_UNKNOWN,
        "license_locator": [],
        "derived_from": [],
        "generator": GENERATOR_UNKNOWN,
        "confidence": "low",
        "review_status": "REVIEW_REQUIRED",
        "issues": [],
        "evidence": [],
        "notes": [],
    }


def add_issue(entry: dict[str, Any], issue: str) -> None:
    if issue not in entry["issues"]:
        entry["issues"].append(issue)


def set_details(
    entry: dict[str, Any],
    *,
    category: str,
    kind: str,
    known_source: str = SOURCE_UNKNOWN,
    source_locator: Iterable[str] = (),
    author_institution: str = SOURCE_UNKNOWN,
    license_name: str = LICENSE_UNKNOWN,
    license_locator: Iterable[str] = (),
    derived_from: Iterable[str] = (),
    generator: Iterable[str] | str = GENERATOR_UNKNOWN,
    confidence: str = "low",
    evidence: Iterable[str] = (),
    notes: Iterable[str] = (),
) -> None:
    entry["category"] = category
    entry["kind"] = kind
    entry["known_source"] = known_source
    entry["source_locator"] = unique(source_locator)
    entry["author_institution"] = author_institution or SOURCE_UNKNOWN
    entry["license"] = license_name or LICENSE_UNKNOWN
    entry["license_locator"] = unique(license_locator)
    entry["derived_from"] = unique(derived_from)
    raw_generators = [str(value) for value in as_list(generator) if str(value)]
    resolved_generators: list[str] = []
    sentinel_seen = False
    for raw in raw_generators:
        if raw in {GENERATOR_UNKNOWN, SOURCE_UNKNOWN}:
            sentinel_seen = True
            continue
        candidate = strip_resource_prefix(raw)
        if (Path(entry["path"]).anchor or candidate.startswith("/")):
            add_issue(entry, "CONTRADICTORY_PROVENANCE")
            entry["notes"].append(f"Generator is not repository-relative: {raw}")
            continue
        resolved_generators.append(candidate)
    if not resolved_generators:
        entry["generator"] = GENERATOR_UNKNOWN
        for raw in raw_generators:
            if raw not in {GENERATOR_UNKNOWN, SOURCE_UNKNOWN}:
                entry["notes"].append(f"Declared generator not found: {raw}")
    else:
        entry["generator"] = unique(resolved_generators)
        if sentinel_seen:
            add_issue(entry, "CONTRADICTORY_PROVENANCE")
            entry["notes"].append("Generator evidence mixes a sentinel with a concrete path.")
    entry["confidence"] = confidence
    entry["evidence"] = unique(evidence)
    entry["notes"] = unique([*entry["notes"], *notes])


def finalize_entry(entry: dict[str, Any]) -> None:
    if entry["known_source"] == SOURCE_UNKNOWN:
        add_issue(entry, "SOURCE_UNKNOWN")
    elif not entry["source_locator"] and entry["category"] not in {
        "documentation",
        "repository_placeholder",
        "project_visual_asset",
    }:
        add_issue(entry, "SOURCE_LOCATOR_MISSING")

    if entry["license"] in {LICENSE_UNKNOWN, "MIXED_EXPLICIT_AND_UNKNOWN"}:
        add_issue(entry, "LICENSE_UNKNOWN")

    if entry["kind"] == "generated":
        if entry["generator"] == GENERATOR_UNKNOWN:
            add_issue(entry, GENERATOR_UNKNOWN)
        if not entry["derived_from"]:
            add_issue(entry, SOURCE_MISSING)

    if entry["issues"]:
        add_issue(entry, PROVENANCE_INCOMPLETE)
        if entry["review_status"] == "REVIEWED":
            entry["review_status"] = "REVIEW_REQUIRED"
    entry["issues"] = sorted(entry["issues"])
    entry["notes"] = sorted(set(entry["notes"]))
    entry["evidence"] = sorted(set(entry["evidence"]))


def url_values(raw: dict[str, Any]) -> list[str]:
    values: list[str] = []
    for key, value in raw.items():
        if not isinstance(value, str) or not value.strip():
            continue
        lowered = key.lower()
        if "license" in lowered:
            continue
        if lowered.endswith("url") or lowered.endswith("_url") or lowered in {
            "upstream",
            "download_root",
            "source_page",
            "source_asset",
            "source_rendered_png",
        }:
            values.append(value.strip())
    return unique(values)


def source_rows(document: Any) -> list[dict[str, Any]]:
    if not isinstance(document, dict):
        return []
    rows: list[dict[str, Any]] = []
    for key in ("source_manifest", "source_groups"):
        value = document.get(key)
        if isinstance(value, list):
            rows.extend(item for item in value if isinstance(item, dict))
    value = document.get("source")
    if isinstance(value, dict):
        rows.append(value)
    elif isinstance(value, str) and value.strip():
        rows.append({"name": value.strip()})
    return rows


def declare_sources(
    catalog: SourceCatalog,
    rows: Iterable[dict[str, Any]],
    *,
    evidence: str,
) -> dict[str, Any]:
    names: list[str] = []
    locators: list[str] = []
    authors: list[str] = []
    licenses: list[str] = []
    license_locators: list[str] = []
    refs: list[str] = []
    for row in rows:
        source_id = str(row.get("source_id") or row.get("id") or row.get("dataset") or row.get("name") or row.get("title") or "").strip()
        name = str(row.get("title") or row.get("name") or row.get("dataset") or source_id).strip()
        if not source_id:
            source_id = name
        if not source_id:
            continue
        ref = source_ref(source_id)
        row_locators = url_values(row)
        row_license = str(row.get("license") or LICENSE_UNKNOWN).strip()
        row_author = str(row.get("author") or row.get("institution") or row.get("creator") or SOURCE_UNKNOWN).strip()
        catalog.add(
            ref,
            name,
            locators=row_locators,
            author_institution=row_author,
            license_name=row_license,
            license_locators=[str(row["license_url"])] if row.get("license_url") else (),
            evidence=[f"{evidence}:{source_id}"],
        )
        names.append(name)
        refs.append(ref)
        locators.extend(row_locators)
        authors.append(row_author)
        licenses.append(row_license)
        if row.get("license_url"):
            license_locators.append(str(row["license_url"]))
    return {
        "known_source": aggregate_text(names),
        "source_locator": unique(locators),
        "author_institution": aggregate_text(authors),
        "license": aggregate_license(licenses),
        "license_locator": unique(license_locators),
        "derived_from": unique(refs),
    }


def load_literal_sources(root: Path) -> list[dict[str, Any]]:
    path = root / ECONOMY_GENERATOR
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    except (OSError, SyntaxError):
        return []
    for node in tree.body:
        targets: list[ast.expr] = []
        if isinstance(node, ast.Assign):
            targets = node.targets
        elif isinstance(node, ast.AnnAssign):
            targets = [node.target]
        if any(isinstance(target, ast.Name) and target.id == "SOURCES" for target in targets):
            try:
                value = ast.literal_eval(node.value)
            except (ValueError, TypeError):
                return []
            return [item for item in value if isinstance(item, dict)]
    return []


def category_for(relative: str) -> str:
    if relative.endswith("/.gitkeep") or Path(relative).name == ".gitkeep":
        return "repository_placeholder"
    if relative.startswith("docs/"):
        return "documentation"
    if relative.startswith("assets/historical_flags/"):
        return "historical_flag_image"
    if relative.startswith("assets/"):
        return "project_visual_asset"
    if relative.startswith("data/world_map/city_detail/"):
        return "modern_city_geography"
    if "historical" in relative or "1900" in relative:
        if "economy" in relative or "transport" in relative or "commodity" in relative:
            return "historical_economy_or_transport"
        return "historical_data"
    filename = Path(relative).name.lower()
    if any(token in filename for token in ("map", "geometry", "coastline", "regions", "ports", "rail", "road", "shipping")):
        return "map_or_geometry_data"
    if relative.startswith("data/alpha/"):
        return "simulation_or_calibration_data"
    if relative.startswith("data/"):
        return "game_data"
    return "unknown"


def apply_city_provenance(
    entry: dict[str, Any],
    *,
    evidence: str,
) -> None:
    geonames_rows = [
        {"source_id": "geonames:cities5000.zip", "name": "GeoNames cities5000.zip", "download_root": "https://download.geonames.org/export/dump/", "license": "Creative Commons Attribution 4.0", "license_url": "https://creativecommons.org/licenses/by/4.0/"},
        {"source_id": "geonames:FR.zip", "name": "GeoNames FR.zip", "download_root": "https://download.geonames.org/export/dump/", "license": "Creative Commons Attribution 4.0", "license_url": "https://creativecommons.org/licenses/by/4.0/"},
        {"source_id": "geonames:countryInfo.txt", "name": "GeoNames countryInfo.txt", "download_root": "https://download.geonames.org/export/dump/", "license": "Creative Commons Attribution 4.0", "license_url": "https://creativecommons.org/licenses/by/4.0/"},
    ]
    info = declare_sources(_CATALOG, geonames_rows, evidence=evidence)
    set_details(
        entry,
        category="modern_city_geography",
        kind="generated",
        known_source="GeoNames",
        source_locator=["https://download.geonames.org/export/dump/"],
        author_institution="GeoNames",
        license_name="Creative Commons Attribution 4.0",
        license_locator=["https://creativecommons.org/licenses/by/4.0/"],
        derived_from=info["derived_from"],
        generator=CITY_GENERATOR,
        confidence="high",
        evidence=[evidence, "data/world_map/city_detail/LICENSE.json:source", "data/world_map/city_detail/index.json:source"],
        notes=["Modern reference only; the repository policy excludes this dataset from 1900 historical reconstruction."],
    )


def apply_natural_earth_provenance(
    entry: dict[str, Any],
    document: dict[str, Any],
    *,
    source_id: str,
    evidence: str,
) -> None:
    source = document.get("source", {})
    if not isinstance(source, dict):
        source = {}
    dataset = str(source.get("dataset") or source_id)
    locator = str(source.get("upstream_url") or source.get("upstream") or "")
    license_name = str(source.get("license") or LICENSE_UNKNOWN)
    _CATALOG.add(
        source_id,
        dataset,
        locators=[locator] if locator else (),
        license_name=license_name,
        license_locators=[str(source["terms_url"])] if source.get("terms_url") else (),
        evidence=[evidence + ":source"],
    )
    set_details(
        entry,
        category="map_or_geometry_data",
        kind="generated",
        known_source=dataset,
        source_locator=[locator] if locator else (),
        license_name=license_name,
        license_locator=[str(source["terms_url"])] if source.get("terms_url") else (),
        derived_from=[source_id],
        generator=GENERATOR_UNKNOWN,
        confidence="high",
        evidence=[evidence + ":source"],
        notes=["Imported or transformed Natural Earth geometry is modern reference geometry, not a 1900 boundary source."],
    )


def apply_flag_asset_provenance(entry: dict[str, Any], record: dict[str, Any]) -> None:
    flag_id = str(record.get("id") or Path(entry["path"]).stem)
    ref = f"external:wikimedia:flag:{flag_id}"
    source_title = str(record.get("source_title") or SOURCE_UNKNOWN)
    source_page = str(record.get("source_page") or "")
    source_asset = str(record.get("source_asset") or "")
    rendered = str(record.get("source_rendered_png") or "")
    source_license = str(record.get("source_license") or LICENSE_UNKNOWN)
    artist = str(record.get("source_artist") or SOURCE_UNKNOWN)
    _CATALOG.add(
        ref,
        source_title,
        locators=[source_page, source_asset, rendered],
        author_institution=artist,
        license_name=source_license,
        evidence=[f"{FLAG_REGISTRY}:records.{flag_id}"],
    )
    notes: list[str] = []
    if any(token in artist.lower() for token in ("assumed", "unknown", "see source page")):
        notes.append("Source record qualifies or does not machine-resolve the artist; retain for manual review.")
    set_details(
        entry,
        category="historical_flag_image",
        kind="generated",
        known_source=f"Wikimedia Commons — {source_title}",
        source_locator=[source_page, source_asset, rendered],
        author_institution=artist,
        license_name=source_license,
        derived_from=[ref],
        generator=FLAG_GENERATOR,
        confidence=str(record.get("confidence") or "medium"),
        evidence=[f"{FLAG_REGISTRY}:records.{flag_id}", FLAG_ATTRIBUTION],
        notes=notes + ["Runtime PNG is a normalized derivative; the cited per-file source license remains controlling."],
    )
    registry_hash = str(record.get("asset_sha256") or "")
    if registry_hash and registry_hash != entry["sha256"]:
        add_issue(entry, "ASSET_REGISTRY_HASH_MISMATCH")
        add_issue(entry, "CONTRADICTORY_PROVENANCE")


def apply_historical_provenance(
    entry: dict[str, Any],
    document: Any,
    *,
    root: Path,
) -> bool:
    relative = entry["path"]
    if relative == CSHAPES_SNAPSHOT and isinstance(document, dict):
        source = document.get("source", {}) if isinstance(document.get("source"), dict) else {}
        _CATALOG.add(
            "external:cshapes:geojson",
            "CShapes 2.0",
            locators=[str(source.get("source_page") or ""), str(source.get("download_url") or "")],
            author_institution="ETH Zurich International Conflict Research / Schvitz et al.",
            license_name=str(source.get("license") or LICENSE_UNKNOWN),
            evidence=[f"{relative}:source", CSHAPES_ATTRIBUTION],
        )
        set_details(
            entry,
            category="historical_geometry",
            kind="generated",
            known_source="CShapes 2.0",
            source_locator=[str(source.get("source_page") or ""), str(source.get("download_url") or "")],
            author_institution="ETH Zurich International Conflict Research / Schvitz et al.",
            license_name=str(source.get("license") or LICENSE_UNKNOWN),
            derived_from=["external:cshapes:geojson"],
            generator=CSHAPES_GENERATOR,
            confidence="high",
            evidence=[f"{relative}:source", CSHAPES_ATTRIBUTION],
            notes=["Transformed 1900-03-12 snapshot; isolated third-party provider with a non-commercial license boundary."],
        )
        return True
    if relative == CSHAPES_ATTRIBUTION:
        set_details(
            entry,
            category="provenance_documentation",
            kind="generated",
            known_source="CShapes 2.0",
            source_locator=["https://icr.ethz.ch/data/cshapes/"],
            author_institution="ETH Zurich International Conflict Research / Schvitz et al.",
            license_name="CC BY-NC-SA 4.0",
            derived_from=[CSHAPES_SNAPSHOT, "external:cshapes:geojson"],
            generator=CSHAPES_GENERATOR,
            confidence="high",
            evidence=[relative],
            notes=["Repository attribution boundary for the transformed CShapes snapshot."],
        )
        return True
    if relative == "data/world_map/historical/political_units_1900.json":
        set_details(
            entry,
            category="historical_registry",
            kind="generated",
            known_source="CShapes 2.0",
            source_locator=["https://icr.ethz.ch/data/cshapes/"],
            author_institution="ETH Zurich International Conflict Research / Schvitz et al.",
            license_name="CC BY-NC-SA 4.0",
            derived_from=[CSHAPES_SNAPSHOT],
            generator=ENTITY_GENERATOR,
            confidence="high",
            evidence=[relative, CSHAPES_SNAPSHOT + ":features"],
            notes=["Political-unit registry preserves each active CShapes unit and adds project relationship metadata."],
        )
        return True
    if relative == FLAG_REGISTRY and isinstance(document, dict):
        records = document.get("records", {})
        source_records = [
            record for record in records.values()
            if isinstance(record, dict) and record.get("render_mode") == "source_asset"
        ]
        refs: list[str] = ["data/world_map/historical/political_units_1900.json"]
        names: list[str] = []
        locators: list[str] = []
        licenses: list[str] = []
        for record in source_records:
            flag_id = str(record.get("id") or "")
            ref = f"external:wikimedia:flag:{flag_id}"
            refs.append(ref)
            names.append(str(record.get("source_title") or "Wikimedia Commons"))
            locators.extend([str(record.get(key) or "") for key in ("source_page", "source_asset", "source_rendered_png")])
            licenses.append(str(record.get("source_license") or LICENSE_UNKNOWN))
        set_details(
            entry,
            category="historical_registry",
            kind="generated",
            known_source="Wikimedia Commons (per registry records)",
            source_locator=locators,
            author_institution="Wikimedia Commons contributors (per record)",
            license_name=aggregate_license(licenses),
            derived_from=refs,
            generator=FLAG_GENERATOR,
            confidence="high",
            evidence=[relative, FLAG_ATTRIBUTION, "data/world_map/historical/political_units_1900.json"],
            notes=["Registry contains 60 source-backed flag records plus a documented neutral absence record."],
        )
        return True
    if relative == FLAG_ATTRIBUTION:
        flag_document = load_json(root / FLAG_REGISTRY)
        source_records = []
        if isinstance(flag_document, dict):
            source_records = [
                record for record in flag_document.get("records", {}).values()
                if isinstance(record, dict) and record.get("render_mode") == "source_asset"
            ]
        refs = [FLAG_REGISTRY]
        licenses = [str(record.get("source_license") or LICENSE_UNKNOWN) for record in source_records]
        locators = [str(record.get("source_page") or "") for record in source_records]
        refs.extend(f"external:wikimedia:flag:{record.get('id', '')}" for record in source_records)
        set_details(
            entry,
            category="provenance_documentation",
            kind="generated",
            known_source="Wikimedia Commons (per registry records)",
            source_locator=locators,
            author_institution="Wikimedia Commons contributors (per record)",
            license_name=aggregate_license(licenses),
            derived_from=refs,
            generator=FLAG_GENERATOR,
            confidence="high",
            evidence=[FLAG_REGISTRY, relative],
            notes=["Generated attribution table; per-file source license remains controlling."],
        )
        return True
    if relative == "data/world_map/historical/historical_admin1_1900.json":
        set_details(
            entry,
            category="historical_administrative_data",
            kind="source",
            known_source=SOURCE_UNKNOWN,
            license_name=LICENSE_UNKNOWN,
            confidence="low",
            evidence=[relative + ":source_basis"],
            notes=["Historical names and source_basis are present, but no external citation, locator, license, or geometry source is recorded."],
        )
        return True
    if relative == "data/world_map/historical/major_state_profiles_1900.json":
        set_details(
            entry,
            category="historical_state_profiles",
            kind="source",
            known_source=SOURCE_UNKNOWN,
            license_name=LICENSE_UNKNOWN,
            confidence="low",
            evidence=[relative + ":profiles"],
            notes=["Curated observer profiles have no external citation or source locator in the file."],
        )
        return True
    if relative == "data/world_map/historical/major_economy_polity_crosswalk_1900.json":
        set_details(
            entry,
            category="historical_crosswalk",
            kind="source",
            known_source=SOURCE_UNKNOWN,
            license_name=LICENSE_UNKNOWN,
            confidence="low",
            evidence=[relative + ":policy", relative + ":records"],
            notes=["Crosswalk policy is explicit, but the source basis and citation for each mapping are not recorded."],
        )
        return True
    if relative == "data/world_map/historical_political_entities_1900.json":
        set_details(
            entry,
            category="historical_legacy_registry",
            kind="source",
            known_source=SOURCE_UNKNOWN,
            license_name=LICENSE_UNKNOWN,
            confidence="low",
            evidence=[relative + ":prototype_only", relative + ":approximation_notice"],
            notes=["61-entity prototype registry coexists with the current 151-unit CShapes registry; retain until explicitly deprecated."],
        )
        add_issue(entry, "OBSOLETE_OR_LEGACY_CANDIDATE")
        return True
    return False


def apply_economy_provenance(
    entry: dict[str, Any],
    document: Any,
    *,
    root: Path,
    economy_sources: list[dict[str, Any]],
) -> bool:
    relative = entry["path"]
    if relative == "data/alpha/historical_world_economy_1900.json" and isinstance(document, dict):
        info = declare_sources(_CATALOG, source_rows(document), evidence=relative)
        set_details(
            entry,
            category="historical_economy_or_transport",
            kind="generated",
            known_source=info["known_source"],
            source_locator=info["source_locator"],
            author_institution=info["author_institution"],
            license_name=info["license"],
            license_locator=info["license_locator"],
            derived_from=info["derived_from"],
            generator=ECONOMY_GENERATOR,
            confidence="medium",
            evidence=[relative + ":source_manifest", ECONOMY_GENERATOR + ":SOURCES"],
            notes=["Bounded gameplay calibration estimates; not a claim of one unified historical census."],
        )
        return True
    if relative == "data/alpha/commodity_market_1900.json" and isinstance(document, dict):
        info = declare_sources(_CATALOG, source_rows(document), evidence=relative)
        set_details(
            entry,
            category="historical_economy_or_transport",
            kind="generated",
            known_source=info["known_source"],
            source_locator=info["source_locator"],
            author_institution=info["author_institution"],
            license_name=info["license"],
            license_locator=info["license_locator"],
            derived_from=info["derived_from"],
            generator=GENERATOR_UNKNOWN,
            confidence="medium",
            evidence=[relative + ":source_groups"],
            notes=["Source groups are named, but no source locator, explicit license, or local generator is recorded."],
        )
        return True
    if relative == "data/alpha/historical_household_budgets_1900.json" and isinstance(document, dict):
        rows = [row for row in economy_sources if row.get("source_id") == "bls_1901_family_budget"]
        info = declare_sources(_CATALOG, rows, evidence=ECONOMY_GENERATOR + ":SOURCES")
        info["derived_from"] = unique([*info["derived_from"], source_ref("bls_1901_family_budget")])
        set_details(
            entry,
            category="historical_economy_or_transport",
            kind="generated",
            known_source="US Commissioner of Labor 1901 family budgets",
            source_locator=info["source_locator"],
            author_institution=info["author_institution"],
            license_name=info["license"],
            license_locator=info["license_locator"],
            derived_from=info["derived_from"],
            generator=ECONOMY_GENERATOR,
            confidence="medium",
            evidence=[relative + ":observed_anchor", ECONOMY_GENERATOR + ":BUDGETS"],
            notes=["Household templates use a 1901 US working-family anchor plus bounded interpolation."],
        )
        return True
    if relative == "data/alpha/historical_transport_network_1900.json" and isinstance(document, dict):
        info = declare_sources(_CATALOG, economy_sources, evidence=ECONOMY_GENERATOR + ":SOURCES")
        set_details(
            entry,
            category="historical_economy_or_transport",
            kind="generated",
            known_source=info["known_source"],
            source_locator=info["source_locator"],
            author_institution=info["author_institution"],
            license_name=info["license"],
            license_locator=info["license_locator"],
            derived_from=info["derived_from"],
            generator=ECONOMY_GENERATOR,
            confidence="medium",
            evidence=[relative, ECONOMY_GENERATOR + ":SEA", ECONOMY_GENERATOR + ":RIVERS"],
            notes=["Country-and-gateway transport skeleton; not exact historical track or river geometry."],
        )
        return True
    if relative == "data/alpha/historical_world_economy_1900/countries_compact.json":
        parent = load_json(root / "data/alpha/historical_world_economy_1900.json")
        info = declare_sources(_CATALOG, source_rows(parent), evidence="data/alpha/historical_world_economy_1900.json")
        set_details(
            entry,
            category="historical_economy_or_transport",
            kind="generated",
            known_source=info["known_source"],
            source_locator=info["source_locator"],
            author_institution=info["author_institution"],
            license_name=info["license"],
            license_locator=info["license_locator"],
            derived_from=["data/alpha/historical_world_economy_1900.json"],
            generator=COMPACT_GENERATOR,
            confidence="medium",
            evidence=[entry["path"], "data/alpha/historical_world_economy_1900.json:compact_country_table_path"],
            notes=["Compact runtime derivative; source manifest is inherited from the verbose economy estimate."],
        )
        return True
    if relative == "data/alpha/historical_transport_network_1900/transport_compact.json":
        parent = load_json(root / "data/alpha/historical_transport_network_1900.json")
        info = declare_sources(_CATALOG, economy_sources, evidence=ECONOMY_GENERATOR + ":SOURCES")
        set_details(
            entry,
            category="historical_economy_or_transport",
            kind="generated",
            known_source=info["known_source"],
            source_locator=info["source_locator"],
            author_institution=info["author_institution"],
            license_name=info["license"],
            license_locator=info["license_locator"],
            derived_from=["data/alpha/historical_transport_network_1900.json"],
            generator=COMPACT_GENERATOR,
            confidence="medium",
            evidence=[entry["path"], "data/alpha/historical_transport_network_1900.json:compact_table_path"],
            notes=["Compact runtime derivative; source identities inherit the verbose transport estimate."],
        )
        return True
    return False


def apply_generic_provenance(
    entry: dict[str, Any],
    document: Any,
    *,
    root: Path,
) -> None:
    relative = entry["path"]
    rows = source_rows(document)
    generated_by: list[str] = []
    if isinstance(document, dict) and document.get("generated_by"):
        generated_by = [str(document["generated_by"])]
    if rows:
        info = declare_sources(_CATALOG, rows, evidence=relative)
        kind = "generated" if generated_by or isinstance(document.get("source"), (dict, list)) else "source"
        set_details(
            entry,
            category=category_for(relative),
            kind=kind,
            known_source=info["known_source"],
            source_locator=info["source_locator"],
            author_institution=info["author_institution"],
            license_name=info["license"],
            license_locator=info["license_locator"],
            derived_from=info["derived_from"],
            generator=generated_by or GENERATOR_UNKNOWN,
            confidence="high" if info["source_locator"] and info["license"] not in {LICENSE_UNKNOWN, "MIXED_EXPLICIT_AND_UNKNOWN"} else "medium",
            evidence=[relative + ":source"],
            notes=["Explicit source metadata was found in the repository file."],
        )
        return
    if generated_by:
        declared = strip_resource_prefix(generated_by[0])
        set_details(
            entry,
            category=category_for(relative),
            kind="generated",
            generator=declared,
            confidence="low",
            evidence=[relative + ":generated_by"],
            notes=["A generated_by field exists, but no source relationship is recorded."],
        )
        return
    set_details(
        entry,
        category=category_for(relative),
        kind="unknown",
        confidence="low",
        evidence=[],
        notes=["No explicit source, license, derived-from relationship, or generator was found."],
    )


def build_manifest(root: Path, base_revision: str = "UNSPECIFIED") -> dict[str, Any]:
    global _CATALOG
    _CATALOG = SourceCatalog()
    economy_sources = load_literal_sources(root)
    flag_document = load_json(root / FLAG_REGISTRY)
    flag_records: dict[str, dict[str, Any]] = {}
    if isinstance(flag_document, dict):
        for record in flag_document.get("records", {}).values():
            if isinstance(record, dict) and record.get("asset_path"):
                asset_path = strip_resource_prefix(str(record["asset_path"]))
                flag_records[asset_path] = record

    entries: list[dict[str, Any]] = []
    for relative in tracked_files(root):
        entry = make_entry(root, relative)
        path = root / Path(relative)
        if relative.endswith("/.gitkeep") or Path(relative).name == ".gitkeep":
            set_details(
                entry,
                category="repository_placeholder",
                kind="source",
                known_source="WWO repository structure",
                license_name=LICENSE_NOT_APPLICABLE,
                generator=GENERATOR_UNKNOWN,
                confidence="high",
                evidence=[relative],
                notes=["Empty directory placeholder; no content license applies."],
            )
            entry["review_status"] = "REVIEWED_NOT_APPLICABLE"
        elif relative.startswith("docs/"):
            set_details(
                entry,
                category="documentation",
                kind="source",
                known_source="WWO repository documentation",
                license_name=LICENSE_UNKNOWN,
                generator=GENERATOR_UNKNOWN,
                confidence="medium",
                evidence=[relative],
                notes=["Documentation is inventoried for citation and ownership review; no document license is inferred."],
            )
        elif relative.startswith("assets/historical_flags/1900/") and relative.endswith(".png"):
            record = flag_records.get(relative)
            if record is None:
                set_details(
                    entry,
                    category="historical_flag_image",
                    kind="unknown",
                    confidence="low",
                    evidence=[FLAG_REGISTRY],
                    notes=["PNG is not linked to a record in flags_1900.json."],
                )
                add_issue(entry, "BROKEN_DERIVED_FROM")
            else:
                apply_flag_asset_provenance(entry, record)
        elif relative == "assets/prototype_v2/README.md":
            set_details(
                entry,
                category="project_visual_asset",
                kind="source",
                known_source="WWO repository-authored prototype visual assets",
                license_name=LICENSE_UNKNOWN,
                confidence="medium",
                evidence=[relative],
                notes=["README explicitly states that the prototype assets are programmatically drawn in this repository and import no external asset."],
            )
        elif relative.startswith("data/world_map/city_detail/") and relative.endswith(".json"):
            apply_city_provenance(entry, evidence=relative)
        elif relative in {
            "data/world_map/world_coastlines.json",
            "data/world_map/world_admin1.json",
            "data/world_map/regions.json",
        }:
            document = load_json(path)
            source_id = {
                "data/world_map/world_coastlines.json": "external:natural-earth:admin0",
                "data/world_map/world_admin1.json": "external:natural-earth:admin1",
                "data/world_map/regions.json": "external:natural-earth:admin1",
            }[relative]
            if isinstance(document, dict):
                apply_natural_earth_provenance(entry, document, source_id=source_id, evidence=relative)
            else:
                set_details(entry, category="map_or_geometry_data", kind="unknown", evidence=[relative])
        elif relative == "data/world_map/map_geometry_cache.json":
            set_details(
                entry,
                category="map_geometry_cache",
                kind="generated",
                generator=GENERATOR_UNKNOWN,
                confidence="low",
                evidence=[relative + ":generated_by"],
                notes=["The file declares res://tools/prototype_v2/build_map_performance_geometry.gd, but that generator is not present in the tracked repository; no source inputs are recorded."],
            )
            add_issue(entry, GENERATOR_UNKNOWN)
            add_issue(entry, SOURCE_MISSING)
        else:
            document = load_json(path) if relative.endswith(".json") else None
            handled = apply_historical_provenance(entry, document, root=root)
            if not handled:
                handled = apply_economy_provenance(
                    entry,
                    document,
                    root=root,
                    economy_sources=economy_sources,
                )
            if not handled:
                apply_generic_provenance(entry, document, root=root)
        finalize_entry(entry)
        entries.append(entry)

    hash_groups: dict[str, list[str]] = defaultdict(list)
    for entry in entries:
        hash_groups[entry["sha256"]].append(entry["path"])
    duplicate_groups = [
        sorted(paths)
        for paths in hash_groups.values()
        if len(paths) > 1
        and not all(Path(path).name == ".gitkeep" for path in paths)
    ]
    duplicate_groups.sort(key=lambda paths: (paths[0], len(paths)))

    edges: list[dict[str, Any]] = []
    for entry in entries:
        generators = entry["generator"]
        if isinstance(generators, str):
            generators = [generators]
        if not generators:
            generators = [GENERATOR_UNKNOWN]
        for source in entry["derived_from"]:
            edges.append({
                "source": source,
                "generator": generators,
                "output": entry["path"],
            })
    edges.sort(key=lambda edge: (edge["output"], edge["source"]))

    source_unknown = sum(entry["known_source"] == SOURCE_UNKNOWN for entry in entries)
    license_unknown = sum(
        entry["license"] in {LICENSE_UNKNOWN, "MIXED_EXPLICIT_AND_UNKNOWN"}
        for entry in entries
    )
    broken_issue_names = {
        SOURCE_MISSING,
        GENERATOR_UNKNOWN,
        "BROKEN_DERIVED_FROM",
        "CONTRADICTORY_PROVENANCE",
        "SOURCE_LOCATOR_MISSING",
    }
    summary = {
        "files_inventoried": len(entries),
        "source_known": len(entries) - source_unknown,
        "source_unknown": source_unknown,
        "license_known": len(entries) - license_unknown,
        "license_unknown": license_unknown,
        "generated_assets": sum(entry["kind"] == "generated" for entry in entries),
        "broken_provenance_chains": sum(bool(broken_issue_names.intersection(entry["issues"])) for entry in entries),
        "duplicate_hash_groups": len(duplicate_groups),
        "duplicate_hash_group_paths": duplicate_groups,
        "license_warning_entries": sum("LICENSE_UNKNOWN" in entry["issues"] for entry in entries),
        "generator_unknown_entries": sum(GENERATOR_UNKNOWN in entry["issues"] for entry in entries),
        "source_missing_entries": sum(SOURCE_MISSING in entry["issues"] for entry in entries),
        "provenance_incomplete_entries": sum(PROVENANCE_INCOMPLETE in entry["issues"] for entry in entries),
    }

    return {
        "schema_version": SCHEMA_VERSION,
        "manifest_kind": "wwo_data_asset_provenance",
        "audit_batch": "WWO DATA & ASSET PROVENANCE AUDIT — BATCH 1",
        "audit_base_revision": base_revision,
        "scope": {
            "included": ["data/**", "assets/**", "docs/**"],
            "tracked_files_only": True,
            "excluded": [MANIFEST_RELATIVE],
            "license_policy": "Record only explicitly documented licenses; use LICENSE_UNKNOWN otherwise.",
            "unknown_license_severity": "WARNING",
        },
        "schema": {
            "entry_required_fields": [
                "path", "file_type", "size_bytes", "sha256", "category", "kind",
                "known_source", "source_locator", "author_institution", "license",
                "derived_from", "generator", "confidence", "review_status",
            ],
            "kind_values": ["generated", "source", "unknown"],
            "derived_from_reference": "Repository-relative path or external_sources id.",
            "sentinels": {
                "source_unknown": SOURCE_UNKNOWN,
                "license_unknown": LICENSE_UNKNOWN,
                "generator_unknown": GENERATOR_UNKNOWN,
                "source_missing": SOURCE_MISSING,
                "provenance_incomplete": PROVENANCE_INCOMPLETE,
            },
        },
        "external_sources": _CATALOG.values(),
        "dependency_graph": {
            "shape": "source -> generator -> generated output",
            "edges": edges,
        },
        "summary": summary,
        "entries": entries,
    }


def write_manifest(manifest: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--base-revision", default="UNSPECIFIED")
    args = parser.parse_args()
    root = args.root.resolve()
    output = (args.output or (root / MANIFEST_RELATIVE)).resolve()
    manifest = build_manifest(root, args.base_revision)
    write_manifest(manifest, output)
    print(json.dumps(manifest["summary"], ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
