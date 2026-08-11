#!/usr/bin/env python3
"""Inventory WWO world names and build a deterministic alias search candidate.

This module deliberately treats names as presentation/search data.  Existing
stable IDs are authoritative; source records without an ID receive an
explicit, non-authoritative source-record key and are excluded from the
stable-ID search index.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import unicodedata
from collections import defaultdict
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence


SCHEMA_VERSION = 1
NORMALIZER_ID = "unicode_nfkc_casefold_safe_punctuation_v1"

NAME_FIELDS: tuple[tuple[str, str, str], ...] = (
    ("canonical_name", "canonical", "official"),
    ("name", "canonical", "official"),
    ("display_name", "display", "official"),
    ("display_name_zh", "display", "official"),
    ("name_zh", "display", "official"),
    ("formal_name", "display", "official"),
    ("formal_name_zh", "display", "official"),
    ("short_name", "display", "short"),
    ("short_name_zh", "display", "short"),
    ("native_name", "native", "official"),
    ("local_name", "native", "official"),
    ("native_given_name", "native", "official"),
    ("native_family_name", "native", "official"),
    ("display_given_name_zh", "display", "official"),
    ("display_family_name_zh", "display", "official"),
    ("source_name", "source", "legacy_repository_name"),
    ("historical_name", "historical", "historical"),
    ("name_en", "display", "official"),
    ("name_fr", "display", "official"),
    ("ascii_name", "alternate", "alternate_spelling"),
    ("alias", "alias", "common"),
    ("aliases", "alias", "common"),
    ("alternate_spelling", "alias", "alternate_spelling"),
    ("alternate_spellings", "alias", "alternate_spelling"),
    ("level_name_zh", "historical", "historical"),
)

NAME_FIELD_BY_KEY = {field: (kind, alias_type) for field, kind, alias_type in NAME_FIELDS}

PARENT_KEYS: tuple[str, ...] = (
    "parent_country_id",
    "parent_region_id",
    "parent_id",
    "sovereign_id",
    "country_id",
    "city_id",
    "region_id",
    "nationality_id",
    "institution_id",
    "employer_id",
    "jurisdiction_id",
)

IGNORED_ID_TOKENS = {
    "admin",
    "character",
    "city",
    "country",
    "entity",
    "historical",
    "institution",
    "organization",
    "place",
    "port",
    "region",
    "source",
    "unit",
}

PUNCTUATION_TRANSLATION = str.maketrans(
    {
        "\u2010": "-",
        "\u2011": "-",
        "\u2012": "-",
        "\u2013": "-",
        "\u2014": "-",
        "\u2015": "-",
        "\u2212": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201a": "'",
        "\u201b": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u201e": '"',
        "\u00b7": "·",
        "\u30fb": "·",
        "\u200b": "",
        "\u200c": "",
        "\u200d": "",
        "\ufeff": "",
    }
)


@dataclass(frozen=True)
class SourceSpec:
    relative_path: str
    selector: str
    entity_type: str
    source_class: str
    historical_period: str


@dataclass(frozen=True)
class RecordEnvelope:
    record: dict[str, Any]
    source_file: str
    source_path: str
    entity_type: str
    source_class: str
    historical_period: str
    source_record_key: str | None = None


CORE_SPECS: tuple[SourceSpec, ...] = (
    SourceSpec("data/world_map/characters.json", "identities", "character", "current", "current"),
    SourceSpec("data/world_map/organizations.json", "catalog", "organization", "current", "current"),
    SourceSpec("data/world_map/institutions.json", "country", "country", "current", "current"),
    SourceSpec("data/world_map/institutions.json", "institutions", "institution", "current", "current"),
    SourceSpec("data/world_map/cities.json", "cities", "city", "current", "current"),
    SourceSpec("data/world_map/regions.json", "regions", "region", "current", "current"),
    SourceSpec(
        "data/world_map/regions.json",
        "administrative_units",
        "administrative_unit",
        "current_reference",
        "current-reference",
    ),
    SourceSpec("data/world_map/countries.json", "countries", "country", "current", "current"),
    SourceSpec("data/world_map/ports.json", "ports", "port", "current", "current"),
    SourceSpec(
        "data/world_map/historical/political_units_1900.json",
        "units",
        "historical_political_unit",
        "historical",
        "1900-snapshot",
    ),
    SourceSpec(
        "data/world_map/historical/major_state_profiles_1900.json",
        "profiles",
        "historical_state_profile",
        "historical",
        "1900-snapshot",
    ),
    SourceSpec(
        "data/world_map/historical_political_entities_1900.json",
        "entities",
        "historical_political_entity",
        "historical",
        "1900-snapshot",
    ),
)


def normalize_name(value: str) -> str:
    """Return a comparison key without changing the stored presentation name.

    NFKC handles width and compatibility forms.  Punctuation is converted to
    spaces only after a small, explicit dash/quote normalization so that
    punctuation and whitespace variants compare together without deleting
    meaningful letters or digits.  Accents and scripts are intentionally
    preserved; this is not transliteration and never creates a translation.
    """

    text = unicodedata.normalize("NFKC", str(value)).translate(PUNCTUATION_TRANSLATION)
    normalized: list[str] = []
    for character in text:
        category = unicodedata.category(character)
        if category.startswith("P"):
            normalized.append(" ")
        elif category == "Cf":
            continue
        else:
            normalized.append(character)
    return " ".join("".join(normalized).casefold().split())


def _script_for(value: str) -> str:
    for character in value:
        name = unicodedata.name(character, "")
        if "CJK UNIFIED" in name or "CJK COMPATIBILITY" in name:
            return "Hans"
        if "HIRAGANA" in name or "KATAKANA" in name:
            return "Jpan"
        if "HANGUL" in name:
            return "Kore"
        if "CYRILLIC" in name:
            return "Cyrl"
        if "ARABIC" in name:
            return "Arab"
        if "GREEK" in name:
            return "Grek"
    if any(character.isascii() and character.isalpha() for character in value):
        return "Latn"
    return "und"


def _language_for(field: str) -> str:
    if field.endswith("_zh") or field in {"display_given_name_zh", "display_family_name_zh"}:
        return "zh"
    return "und"


def _as_nonempty_string(value: Any) -> str | None:
    if isinstance(value, str):
        result = value.strip()
        return result or None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(value)
    return None


def _json_pointer(path: str, key: str) -> str:
    escaped = key.replace("~", "~0").replace("/", "~1")
    return f"{path}/{escaped}"


def _source_ref(source_file: str, source_path: str, field: str) -> str:
    return f"{source_file}#{_json_pointer(source_path, field)}"


def _parse_date(value: Any) -> date | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def _valid_date_value(record: dict[str, Any], key: str) -> str | None:
    value = record.get(key)
    return value.strip() if isinstance(value, str) and value.strip() else None


def _extract_id(record: dict[str, Any]) -> tuple[str | None, str, dict[str, str]]:
    id_fields: dict[str, str] = {}
    for key in ("stable_id", "entity_id", "id"):
        value = _as_nonempty_string(record.get(key))
        if value is not None:
            id_fields[key] = value
    stable_id = id_fields.get("stable_id") or id_fields.get("entity_id") or id_fields.get("id")
    if stable_id is None:
        return None, "source_record_key", id_fields
    return stable_id, "stable_id", id_fields


def _parent_ids(record: dict[str, Any]) -> list[str]:
    values: set[str] = set()
    for key in PARENT_KEYS:
        value = _as_nonempty_string(record.get(key))
        if value is not None:
            values.add(value)
    return sorted(values)


def _iter_name_values(value: Any) -> Iterator[str]:
    if isinstance(value, str):
        text = _as_nonempty_string(value)
        if text is not None:
            yield text
    elif isinstance(value, list):
        for item in value:
            yield from _iter_name_values(item)


def _field_alias_type(field: str, source_class: str) -> tuple[str, str]:
    kind, alias_type = NAME_FIELD_BY_KEY.get(field, ("display", "common"))
    if source_class == "historical" and field in {"name", "name_zh", "display_name_zh", "source_name"}:
        return "historical", "historical"
    return kind, alias_type


def _name_observations(envelope: RecordEnvelope) -> list[dict[str, Any]]:
    observations: list[dict[str, Any]] = []
    for field, _kind, _alias_type in NAME_FIELDS:
        if field not in envelope.record:
            continue
        field_kind, alias_type = _field_alias_type(field, envelope.source_class)
        for value in _iter_name_values(envelope.record[field]):
            observations.append(
                {
                    "value": value,
                    "field": field,
                    "name_kind": field_kind,
                    "alias_type": alias_type,
                    "language": _language_for(field),
                    "script": _script_for(value),
                    "valid_from": _valid_date_value(envelope.record, "valid_from"),
                    "valid_to": _valid_date_value(envelope.record, "valid_to"),
                    "source_file": envelope.source_file,
                    "source_path": envelope.source_path,
                    "source": _source_ref(envelope.source_file, envelope.source_path, field),
                    "source_class": envelope.source_class,
                    "historical_period": envelope.historical_period,
                    "confidence": "high",
                }
            )
    return observations


def _load_json(root: Path, relative_path: str) -> Any:
    path = root / relative_path
    return json.loads(path.read_text(encoding="utf-8"))


def _iter_selector(data: Any, selector: str, source_file: str) -> Iterator[tuple[str, dict[str, Any]]]:
    if not isinstance(data, dict) or selector not in data:
        return
    selected = data[selector]
    base_path = f"$.{selector}"
    if isinstance(selected, list):
        for index, record in enumerate(selected):
            if isinstance(record, dict):
                yield f"{base_path}[{index}]", record
    elif isinstance(selected, dict):
        if any(key in selected for key in ("id", "entity_id", "stable_id")) or any(
            field in selected for field in NAME_FIELD_BY_KEY
        ):
            yield base_path, selected
        else:
            for key in sorted(selected):
                record = selected[key]
                if isinstance(record, dict):
                    yield f"{base_path}.{key}", record


def _iter_core_envelopes(root: Path) -> Iterator[RecordEnvelope]:
    loaded: dict[str, Any] = {}
    for spec in CORE_SPECS:
        if spec.relative_path not in loaded:
            loaded[spec.relative_path] = _load_json(root, spec.relative_path)
        data = loaded[spec.relative_path]
        for source_path, record in _iter_selector(data, spec.selector, spec.relative_path):
            yield RecordEnvelope(
                record=record,
                source_file=spec.relative_path,
                source_path=source_path,
                entity_type=spec.entity_type,
                source_class=spec.source_class,
                historical_period=spec.historical_period,
            )

    historical_admin1_path = "data/world_map/historical/historical_admin1_1900.json"
    historical_admin1 = _load_json(root, historical_admin1_path)
    for country_index, country in enumerate(historical_admin1.get("countries", [])):
        if not isinstance(country, dict):
            continue
        parent_id = _as_nonempty_string(country.get("entity_id")) or "unknown"
        for unit_index, unit_name in enumerate(country.get("units", [])):
            value = _as_nonempty_string(unit_name)
            if value is None:
                continue
            source_path = f"$.countries[{country_index}].units[{unit_index}]"
            source_key = f"source:{historical_admin1_path}#{source_path}"
            yield RecordEnvelope(
                record={
                    "source_name": value,
                    "parent_id": parent_id,
                    "valid_from": "",
                    "valid_to": "",
                },
                source_file=historical_admin1_path,
                source_path=source_path,
                entity_type="historical_administrative_unit_name",
                source_class="historical",
                historical_period="1900-snapshot",
                source_record_key=source_key,
            )

    name_pool_path = "data/world_map/name_pool_fr.json"
    name_pool = _load_json(root, name_pool_path)
    for collection_name, entity_type, field in (
        ("given_names", "name_pool_given_name", "native_given_name"),
        ("family_names", "name_pool_family_name", "native_family_name"),
    ):
        for index, record in enumerate(name_pool.get(collection_name, [])):
            if not isinstance(record, dict):
                continue
            source_path = f"$.{collection_name}[{index}]"
            yield RecordEnvelope(
                record=record,
                source_file=name_pool_path,
                source_path=source_path,
                entity_type=entity_type,
                source_class="name_pool",
                historical_period="source-name-pool",
                source_record_key=f"source:{name_pool_path}#{source_path}",
            )

    generation_path = "data/characters/character_generation.json"
    generation = _load_json(root, generation_path)
    for country_key in sorted(generation.get("country_names", {})):
        country_pool = generation["country_names"][country_key]
        if not isinstance(country_pool, dict):
            continue
        for collection_name, entity_type in (
            ("given_names", "name_pool_country_given_name"),
            ("family_names", "name_pool_country_family_name"),
        ):
            for index, value in enumerate(country_pool.get(collection_name, [])):
                text = _as_nonempty_string(value)
                if text is None:
                    continue
                source_path = f"$.country_names.{country_key}.{collection_name}[{index}]"
                yield RecordEnvelope(
                    record={"source_name": text},
                    source_file=generation_path,
                    source_path=source_path,
                    entity_type=entity_type,
                    source_class="name_pool",
                    historical_period="source-name-pool",
                    source_record_key=f"source:{generation_path}#{source_path}",
                )


def _iter_modern_reference_envelopes(root: Path) -> Iterator[RecordEnvelope]:
    """Optionally include modern reference names without making them default."""

    admin_path = "data/world_map/world_admin1.json"
    admin_data = _load_json(root, admin_path)
    for source_path, record in _iter_selector(admin_data, "regions", admin_path):
        yield RecordEnvelope(
            record=record,
            source_file=admin_path,
            source_path=source_path,
            entity_type="modern_administrative_region_reference",
            source_class="modern_reference",
            historical_period="modern-reference-only",
        )

    city_root = root / "data/world_map/city_detail/countries"
    for path in sorted(city_root.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        relative_path = path.relative_to(root).as_posix()
        for index, record in enumerate(data.get("cities", [])):
            if not isinstance(record, dict):
                continue
            yield RecordEnvelope(
                record=record,
                source_file=relative_path,
                source_path=f"$.cities[{index}]",
                entity_type="modern_city_reference",
                source_class="modern_reference",
                historical_period="modern-reference-only",
            )


def _record_id(envelope: RecordEnvelope) -> tuple[str, str, dict[str, str]]:
    stable_id, id_kind, id_fields = _extract_id(envelope.record)
    if stable_id is not None:
        return stable_id, id_kind, id_fields
    source_key = envelope.source_record_key or f"source:{envelope.source_file}#{envelope.source_path}"
    return source_key, "source_record_key", id_fields


def _canonical_sort_key(observation: dict[str, Any]) -> tuple[int, int, str, str]:
    source_rank = {
        "current": 0,
        "current_reference": 1,
        "historical": 2,
        "modern_reference": 3,
        "name_pool": 4,
    }.get(str(observation.get("source_class")), 9)
    field_rank = {
        "canonical_name": 0,
        "name": 1,
        "display_name": 2,
        "display_name_zh": 3,
        "name_zh": 4,
        "formal_name": 5,
        "formal_name_zh": 6,
        "native_name": 7,
        "local_name": 8,
        "source_name": 9,
    }.get(str(observation.get("field")), 20)
    return source_rank, field_rank, normalize_name(str(observation.get("value", ""))), str(observation.get("value", ""))


def _deduplicate_observations(observations: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    unique: dict[tuple[Any, ...], dict[str, Any]] = {}
    for observation in observations:
        key = (
            observation.get("value"),
            observation.get("field"),
            observation.get("alias_type"),
            observation.get("language"),
            observation.get("script"),
            observation.get("valid_from"),
            observation.get("valid_to"),
            observation.get("source"),
        )
        unique[key] = observation
    return sorted(
        unique.values(),
        key=lambda item: (
            normalize_name(str(item.get("value", ""))),
            str(item.get("value", "")),
            str(item.get("alias_type", "")),
            str(item.get("source", "")),
        ),
    )


def collect_inventory(root: Path, include_modern_reference: bool = False) -> dict[str, Any]:
    """Collect and merge all configured entity records without changing inputs."""

    accumulators: dict[str, dict[str, Any]] = {}
    envelopes: Iterable[RecordEnvelope] = _iter_core_envelopes(root)
    if include_modern_reference:
        envelopes = (*envelopes, *_iter_modern_reference_envelopes(root))

    for envelope in envelopes:
        entity_id, entity_id_kind, id_fields = _record_id(envelope)
        observations = _name_observations(envelope)
        accumulator = accumulators.setdefault(
            entity_id,
            {
                "entity_id": entity_id,
                "entity_id_kind": entity_id_kind,
                "entity_type": envelope.entity_type,
                "entity_types": set(),
                "canonical_current_name": "",
                "existing_display_names": set(),
                "existing_aliases": set(),
                "name_records": [],
                "source_files": set(),
                "source_records": [],
                "historical_periods": set(),
                "parent_entity_ids": set(),
                "id_fields": {},
            },
        )
        accumulator["entity_types"].add(envelope.entity_type)
        accumulator["source_files"].add(envelope.source_file)
        accumulator["historical_periods"].add(envelope.historical_period)
        accumulator["parent_entity_ids"].update(_parent_ids(envelope.record))
        accumulator["id_fields"].update(id_fields)
        accumulator["source_records"].append(
            {
                "source_file": envelope.source_file,
                "source_path": envelope.source_path,
                "source_class": envelope.source_class,
                "historical_period": envelope.historical_period,
            }
        )
        for observation in observations:
            accumulator["name_records"].append(observation)
            value = str(observation["value"])
            if observation["name_kind"] in {"canonical", "display", "native", "source"}:
                accumulator["existing_display_names"].add(value)
            if observation["alias_type"] in {
                "short",
                "historical",
                "common",
                "alternate_spelling",
                "legacy_repository_name",
            }:
                accumulator["existing_aliases"].add(value)

        all_observations = accumulator["name_records"]
        if all_observations:
            canonical = min(all_observations, key=_canonical_sort_key)
            if not accumulator["canonical_current_name"] or _canonical_sort_key(canonical) < _canonical_sort_key(
                next(
                    observation
                    for observation in all_observations
                    if observation["value"] == accumulator["canonical_current_name"]
                )
            ):
                accumulator["canonical_current_name"] = str(canonical["value"])

    entities: list[dict[str, Any]] = []
    for entity_id in sorted(accumulators):
        accumulator = accumulators[entity_id]
        observations = _deduplicate_observations(accumulator["name_records"])
        display_names = set(accumulator["existing_display_names"])
        aliases = set(accumulator["existing_aliases"])
        if accumulator["canonical_current_name"]:
            display_names.add(accumulator["canonical_current_name"])
            aliases.discard(accumulator["canonical_current_name"])
        periods = sorted(accumulator["historical_periods"])
        entity_types = sorted(accumulator["entity_types"])
        source_records = sorted(
            accumulator["source_records"],
            key=lambda item: (item["source_file"], item["source_path"]),
        )
        entities.append(
            {
                "entity_id": accumulator["entity_id"],
                "entity_id_kind": accumulator["entity_id_kind"],
                "entity_type": entity_types[0] if entity_types else accumulator["entity_type"],
                "entity_types": entity_types,
                "canonical_current_name": accumulator["canonical_current_name"],
                "existing_display_names": sorted(display_names, key=lambda value: (normalize_name(value), value)),
                "existing_aliases": sorted(aliases, key=lambda value: (normalize_name(value), value)),
                "source_files": sorted(accumulator["source_files"]),
                "source_records": source_records,
                "historical_period": periods[0] if len(periods) == 1 else ("multiple" if periods else None),
                "historical_periods": periods,
                "parent_entity_ids": sorted(accumulator["parent_entity_ids"]),
                "id_fields": dict(sorted(accumulator["id_fields"].items())),
                "name_records": observations,
            }
        )

    coverage = scan_source_coverage(root)
    return {
        "schema_version": SCHEMA_VERSION,
        "normalizer_id": NORMALIZER_ID,
        "scope": {
            "stable_ids_are_authoritative": True,
            "unsourced_translation_policy": "no_machine_or_external_translation",
            "modern_reference_default": "scanned_only_not_staged",
            "modern_reference_included": include_modern_reference,
        },
        "source_coverage": coverage,
        "entities": entities,
    }


def _walk_dicts(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk_dicts(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_dicts(child)


def _count_name_records(value: Any) -> tuple[int, int]:
    dictionaries = 0
    name_bearing = 0
    for record in _walk_dicts(value):
        dictionaries += 1
        if any(field in record for field in NAME_FIELD_BY_KEY):
            name_bearing += 1
    return dictionaries, name_bearing


def scan_source_coverage(root: Path) -> dict[str, Any]:
    """Read every world-map JSON source and report what was staged or excluded."""

    staged_files = {spec.relative_path for spec in CORE_SPECS}
    staged_files.update(
        {
            "data/world_map/historical/historical_admin1_1900.json",
            "data/world_map/name_pool_fr.json",
            "data/characters/character_generation.json",
        }
    )
    files: list[dict[str, Any]] = []
    world_root = root / "data/world_map"
    for path in sorted(world_root.rglob("*.json")):
        relative_path = path.relative_to(root).as_posix()
        try:
            size = path.stat().st_size
        except OSError:
            size = 0
        status = "staged" if relative_path in staged_files else "scanned_only"
        note = "not a configured entity source"
        if relative_path.startswith("data/world_map/city_detail/countries/"):
            status = "scanned_only_modern_reference"
            note = "modern GeoNames reference; not treated as 1900 authority by default"
        elif relative_path in {
            "data/world_map/world_coastlines.json",
            "data/world_map/map_geometry_cache.json",
        }:
            status = "scanned_only_geometry_support"
            note = "geometry/runtime support data; names are not entity authority"
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            dictionary_count, name_count = _count_name_records(data)
            record_count: int | None = dictionary_count
            if relative_path.startswith("data/world_map/city_detail/countries/"):
                record_count = len(data.get("cities", [])) if isinstance(data, dict) else dictionary_count
        except (OSError, json.JSONDecodeError) as error:
            dictionary_count = 0
            name_count = 0
            record_count = None
            status = "error"
            note = f"could not parse source: {error}"
        files.append(
            {
                "source_file": relative_path,
                "bytes": size,
                "status": status,
                "record_count": record_count,
                "name_bearing_record_count": name_count,
                "note": note,
            }
        )

    generation_path = root / "data/characters/character_generation.json"
    if generation_path.exists():
        data = json.loads(generation_path.read_text(encoding="utf-8"))
        dictionary_count, name_count = _count_name_records(data)
        files.append(
            {
                "source_file": "data/characters/character_generation.json",
                "bytes": generation_path.stat().st_size,
                "status": "staged",
                "record_count": dictionary_count,
                "name_bearing_record_count": name_count,
                "note": "existing character name pool source",
            }
        )
    files.sort(key=lambda item: item["source_file"])
    return {
        "world_map_json_files": len([item for item in files if item["source_file"].startswith("data/world_map/")]),
        "files": files,
        "staged_source_files": sorted(staged_files),
    }


def build_alias_records(inventory: dict[str, Any]) -> dict[str, Any]:
    aliases: list[dict[str, Any]] = []
    for entity in inventory.get("entities", []):
        for observation in entity.get("name_records", []):
            aliases.append(
                {
                    "entity_id": entity["entity_id"],
                    "entity_id_kind": entity["entity_id_kind"],
                    "entity_type": entity["entity_type"],
                    "alias": observation["value"],
                    "language": observation["language"],
                    "script": observation["script"],
                    "valid_from": observation.get("valid_from"),
                    "valid_to": observation.get("valid_to"),
                    "alias_type": observation["alias_type"],
                    "source": observation["source"],
                    "source_file": observation["source_file"],
                    "source_field": observation["field"],
                    "historical_period": observation["historical_period"],
                    "confidence": observation.get("confidence", "high"),
                }
            )
    aliases.sort(
        key=lambda item: (
            item["entity_id"],
            normalize_name(item["alias"]),
            item["alias"],
            item["alias_type"],
            item["source"],
        )
    )
    return {
        "schema_version": SCHEMA_VERSION,
        "normalizer_id": NORMALIZER_ID,
        "aliases": aliases,
    }


def build_search_index(aliases_document: dict[str, Any], inventory: dict[str, Any]) -> dict[str, Any]:
    stable_ids = {
        entity["entity_id"]
        for entity in inventory.get("entities", [])
        if entity.get("entity_id_kind") == "stable_id"
    }
    candidates: dict[str, set[str]] = defaultdict(set)
    for alias in aliases_document.get("aliases", []):
        entity_id = str(alias.get("entity_id", ""))
        if entity_id not in stable_ids:
            continue
        normalized = normalize_name(str(alias.get("alias", "")))
        if normalized:
            candidates[normalized].add(entity_id)
    entries = [
        {"normalized_name": normalized, "entity_ids": sorted(entity_ids)}
        for normalized, entity_ids in sorted(candidates.items())
    ]
    return {
        "schema_version": SCHEMA_VERSION,
        "normalizer_id": NORMALIZER_ID,
        "policy": {
            "stable_ids_are_authoritative": True,
            "one_to_many_name_collisions_are_preserved": True,
            "non_authoritative_source_records_excluded": True,
        },
        "entries": entries,
    }


def _raw_name_groups(aliases: Sequence[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for alias in aliases:
        raw = str(alias.get("alias", ""))
        if raw:
            groups[raw].append(alias)
    return groups


def _normalized_name_groups(aliases: Sequence[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for alias in aliases:
        normalized = normalize_name(str(alias.get("alias", "")))
        if normalized:
            groups[normalized].append(alias)
    return groups


def _unique_sorted(values: Iterable[str]) -> list[str]:
    return sorted(set(values), key=lambda value: (normalize_name(value), value))


def _normalization_difference_flags(raw_names: Sequence[str]) -> list[str]:
    flags: set[str] = set()
    if len(raw_names) <= 1:
        return []
    if len({value.casefold() for value in raw_names}) > 1:
        flags.add("case_difference")
    if len({" ".join(value.split()) for value in raw_names}) > 1:
        flags.add("whitespace_difference")
    punctuation_free = {re.sub(r"[^\w\u4e00-\u9fff]+", "", value.casefold()) for value in raw_names}
    if len(punctuation_free) == 1:
        flags.add("punctuation_difference")
    if len({unicodedata.normalize("NFKC", value) for value in raw_names}) > 1:
        flags.add("unicode_normalization_difference")
    return sorted(flags)


def _id_name_disagreement_candidates(inventory: dict[str, Any]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for entity in inventory.get("entities", []):
        if entity.get("entity_id_kind") != "stable_id":
            continue
        identifier = str(entity.get("entity_id", ""))
        tokens = [
            token
            for token in re.split(r"[^A-Za-z0-9]+", identifier.casefold())
            if len(token) >= 4 and token not in IGNORED_ID_TOKENS
        ]
        raw_names = [str(item.get("value", "")) for item in entity.get("name_records", [])]
        latin_names = [name.casefold() for name in raw_names if _script_for(name) == "Latn"]
        if not tokens or not latin_names:
            continue
        missing = [token for token in tokens if not any(token in name for name in latin_names)]
        if missing:
            findings.append(
                {
                    "entity_id": identifier,
                    "entity_type": entity.get("entity_type", ""),
                    "embedded_id_tokens": tokens,
                    "missing_tokens_in_latin_names": missing,
                    "names_checked": _unique_sorted(raw_names),
                    "severity": "review",
                }
            )
    return sorted(findings, key=lambda item: (item["entity_id"], item["entity_type"]))


def build_collision_report(inventory: dict[str, Any], aliases_document: dict[str, Any]) -> dict[str, Any]:
    aliases = list(aliases_document.get("aliases", []))
    raw_groups = _raw_name_groups(aliases)
    normalized_groups = _normalized_name_groups(aliases)
    entity_by_id = {entity["entity_id"]: entity for entity in inventory.get("entities", [])}

    exact_duplicates: list[dict[str, Any]] = []
    for raw_name, records in sorted(raw_groups.items()):
        entity_ids = _unique_sorted(str(record["entity_id"]) for record in records)
        if len(entity_ids) > 1:
            exact_duplicates.append(
                {
                    "raw_name": raw_name,
                    "normalized_name": normalize_name(raw_name),
                    "entity_ids": entity_ids,
                    "entity_types": _unique_sorted(str(record.get("entity_type", "")) for record in records),
                }
            )

    normalized_collisions: list[dict[str, Any]] = []
    spelling_variants: list[dict[str, Any]] = []
    historical_current_collisions: list[dict[str, Any]] = []
    for normalized, records in sorted(normalized_groups.items()):
        entity_ids = _unique_sorted(str(record["entity_id"]) for record in records)
        raw_names = _unique_sorted(str(record["alias"]) for record in records)
        if len(entity_ids) > 1:
            collision = {
                "normalized_name": normalized,
                "raw_names": raw_names,
                "entity_ids": entity_ids,
                "entity_types": _unique_sorted(str(record.get("entity_type", "")) for record in records),
                "source_files": _unique_sorted(str(record.get("source_file", "")) for record in records),
                "reasons": _normalization_difference_flags(raw_names),
            }
            normalized_collisions.append(collision)
        if len(raw_names) > 1:
            spelling_variants.append(
                {
                    "normalized_name": normalized,
                    "entity_ids": entity_ids,
                    "raw_names": raw_names,
                    "reasons": _normalization_difference_flags(raw_names),
                }
            )
        source_classes = {
            str(record.get("historical_period", "")) for record in records
        }
        alias_types = {str(record.get("alias_type", "")) for record in records}
        if any("1900" in period or period == "historical" for period in source_classes) and (
            "current" in source_classes or "current-reference" in source_classes
        ):
            historical_current_collisions.append(
                {
                    "normalized_name": normalized,
                    "raw_names": raw_names,
                    "entity_ids": entity_ids,
                    "alias_types": sorted(alias_types),
                    "periods": sorted(source_classes),
                }
            )

    inconsistent_spelling: list[dict[str, Any]] = []
    per_entity: dict[str, dict[str, set[str]]] = defaultdict(lambda: defaultdict(set))
    for alias in aliases:
        per_entity[str(alias["entity_id"])][normalize_name(str(alias["alias"]))].add(str(alias["alias"]))
    for entity_id, groups in sorted(per_entity.items()):
        for normalized, raw_values in sorted(groups.items()):
            if len(raw_values) > 1:
                inconsistent_spelling.append(
                    {
                        "entity_id": entity_id,
                        "entity_type": entity_by_id.get(entity_id, {}).get("entity_type", ""),
                        "normalized_name": normalized,
                        "raw_names": _unique_sorted(raw_values),
                        "reasons": _normalization_difference_flags(sorted(raw_values)),
                    }
                )

    empty_names = [
        {
            "entity_id": entity["entity_id"],
            "entity_type": entity.get("entity_type", ""),
            "source_files": entity.get("source_files", []),
        }
        for entity in inventory.get("entities", [])
        if not entity.get("canonical_current_name") or not entity.get("name_records")
    ]

    top_targets: list[dict[str, Any]] = []
    for item in normalized_collisions:
        top_targets.append(
            {
                "kind": "normalized_collision",
                "severity": "high" if len(item["entity_ids"]) > 2 else "medium",
                "normalized_name": item["normalized_name"],
                "entity_ids": item["entity_ids"],
                "raw_names": item["raw_names"],
                "reasons": item["reasons"],
            }
        )
    for item in inconsistent_spelling:
        top_targets.append(
            {
                "kind": "inconsistent_spelling",
                "severity": "low",
                "normalized_name": item["normalized_name"],
                "entity_ids": [item["entity_id"]],
                "raw_names": item["raw_names"],
                "reasons": item["reasons"],
            }
        )
    top_targets.sort(
        key=lambda item: (
            {"high": 0, "medium": 1, "low": 2}.get(item["severity"], 9),
            item["normalized_name"],
            item["kind"],
        )
    )

    return {
        "schema_version": SCHEMA_VERSION,
        "normalizer_id": NORMALIZER_ID,
        "summary": {
            "entities": len(inventory.get("entities", [])),
            "unique_raw_names": len(raw_groups),
            "normalized_name_keys": len(normalized_groups),
            "normalized_collisions": len(normalized_collisions),
            "exact_name_collisions": len(exact_duplicates),
            "inconsistent_spelling": len(inconsistent_spelling),
            "historical_current_collisions": len(historical_current_collisions),
            "empty_names": len(empty_names),
            "id_name_disagreement_candidates": 0,
        },
        "duplicate_exact_names": exact_duplicates,
        "normalized_collisions": normalized_collisions,
        "inconsistent_spelling": inconsistent_spelling,
        "historical_current_collisions": historical_current_collisions,
        "empty_names": empty_names,
        "id_name_disagreement_candidates": _id_name_disagreement_candidates(inventory),
        "top_50_cleanup_targets": top_targets[:50],
    }


def _is_sorted_by(items: Sequence[Any], key: Any) -> bool:
    return list(items) == sorted(items, key=key)


def validate_artifacts(
    inventory: dict[str, Any],
    aliases_document: dict[str, Any],
    collision_report: dict[str, Any],
    search_index: dict[str, Any],
) -> list[str]:
    """Validate pointers, dates, uniqueness, deterministic ordering and index replay."""

    errors: list[str] = []
    entities = inventory.get("entities", [])
    aliases = aliases_document.get("aliases", [])
    entries = search_index.get("entries", [])
    entity_by_id: dict[str, dict[str, Any]] = {}
    for index, entity in enumerate(entities):
        entity_id = entity.get("entity_id")
        if not isinstance(entity_id, str) or not entity_id:
            errors.append(f"inventory entity {index} has an empty entity_id")
            continue
        if entity_id in entity_by_id:
            errors.append(f"duplicate inventory entity_id: {entity_id}")
        entity_by_id[entity_id] = entity
        for required in (
            "entity_type",
            "canonical_current_name",
            "existing_display_names",
            "existing_aliases",
            "source_files",
            "historical_period",
        ):
            if required not in entity:
                errors.append(f"{entity_id} missing inventory field {required}")
        if not isinstance(entity.get("canonical_current_name"), str):
            errors.append(f"{entity_id} canonical_current_name is not a string")
        if not entity.get("name_records"):
            errors.append(f"{entity_id} has no name records")

    duplicate_alias_keys: set[tuple[Any, ...]] = set()
    for index, alias in enumerate(aliases):
        entity_id = alias.get("entity_id")
        if not isinstance(entity_id, str) or entity_id not in entity_by_id:
            errors.append(f"alias {index} points to unknown entity_id: {entity_id}")
        value = alias.get("alias")
        if not isinstance(value, str) or not value.strip():
            errors.append(f"alias {index} has an empty alias")
        key = (
            alias.get("entity_id"),
            alias.get("alias"),
            alias.get("language"),
            alias.get("script"),
            alias.get("valid_from"),
            alias.get("valid_to"),
            alias.get("alias_type"),
            alias.get("source"),
        )
        if key in duplicate_alias_keys:
            errors.append(f"duplicate alias record: {key}")
        duplicate_alias_keys.add(key)
        valid_from = alias.get("valid_from")
        valid_to = alias.get("valid_to")
        if valid_from is not None and _parse_date(valid_from) is None:
            errors.append(f"alias {index} has invalid valid_from: {valid_from}")
        if valid_to is not None and _parse_date(valid_to) is None:
            errors.append(f"alias {index} has invalid valid_to: {valid_to}")
        from_date = _parse_date(valid_from)
        to_date = _parse_date(valid_to)
        if from_date is not None and to_date is not None and from_date > to_date:
            errors.append(f"alias {index} has an inverted date range")
        if not alias.get("source") or not alias.get("source_file"):
            errors.append(f"alias {index} has no source reference")

    expected_index = build_search_index(aliases_document, inventory)["entries"]
    if entries != expected_index:
        errors.append("search index does not replay deterministically from aliases")
    if not _is_sorted_by(entries, lambda item: item.get("normalized_name", "")):
        errors.append("search index entries are not sorted by normalized_name")
    for entry in entries:
        normalized = entry.get("normalized_name")
        entity_ids = entry.get("entity_ids")
        if not isinstance(normalized, str) or not normalized:
            errors.append("search index contains an empty normalized name")
        if not isinstance(entity_ids, list) or entity_ids != sorted(set(entity_ids)):
            errors.append(f"search index entity_ids are not sorted and unique: {normalized}")
        for entity_id in entity_ids or []:
            if entity_id not in entity_by_id:
                errors.append(f"search index points to unknown entity_id: {entity_id}")
            elif entity_by_id[entity_id].get("entity_id_kind") != "stable_id":
                errors.append(f"search index points to non-authoritative entity_id: {entity_id}")

    if collision_report.get("normalizer_id") != NORMALIZER_ID:
        errors.append("collision report normalizer_id mismatch")
    if aliases_document.get("normalizer_id") != NORMALIZER_ID:
        errors.append("aliases normalizer_id mismatch")
    if search_index.get("normalizer_id") != NORMALIZER_ID:
        errors.append("search index normalizer_id mismatch")

    for entity in entities:
        canonical = entity.get("canonical_current_name")
        if not canonical:
            continue
        canonical_aliases = {
            alias.get("alias")
            for alias in aliases
            if alias.get("entity_id") == entity.get("entity_id")
        }
        if canonical not in canonical_aliases:
            errors.append(f"canonical current name has no alias record: {entity['entity_id']}")

    return errors


def build_artifacts(root: Path, include_modern_reference: bool = False) -> dict[str, Any]:
    inventory = collect_inventory(root, include_modern_reference=include_modern_reference)
    aliases = build_alias_records(inventory)
    collision_report = build_collision_report(inventory, aliases)
    collision_report["summary"]["id_name_disagreement_candidates"] = len(
        collision_report.get("id_name_disagreement_candidates", [])
    )
    search_index = build_search_index(aliases, inventory)
    errors = validate_artifacts(inventory, aliases, collision_report, search_index)
    return {
        "inventory": inventory,
        "aliases": aliases,
        "collision_report": collision_report,
        "search_index": search_index,
        "validation_errors": errors,
    }


def _canonical_json(document: Any) -> str:
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def write_json(path: Path, document: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_canonical_json(document), encoding="utf-8")


def _git_revision(root: Path, ref: str) -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", ref],
            cwd=root,
            capture_output=True,
            check=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"
    return result.stdout.strip()


def render_report(artifacts: dict[str, Any], starting_master: str, commit: str, push: str, draft_pr: str) -> str:
    inventory = artifacts["inventory"]
    aliases = artifacts["aliases"]
    collisions = artifacts["collision_report"]
    index = artifacts["search_index"]
    errors = artifacts["validation_errors"]
    stable_ids = sum(1 for entity in inventory["entities"] if entity["entity_id_kind"] == "stable_id")
    high_confidence = sum(1 for alias in aliases["aliases"] if alias.get("confidence") == "high")
    historical_candidates = sum(
        1
        for alias in aliases["aliases"]
        if alias.get("alias_type") == "historical"
    )
    ambiguous = sum(1 for entry in index["entries"] if len(entry["entity_ids"]) > 1)
    missing = len(collisions["empty_names"])
    validator = "PASS" if not errors else "FAIL: " + "; ".join(errors[:5])
    search_result = f"PASS — {len(index['entries'])} normalized keys, {ambiguous} one-to-many collisions"
    return "\n".join(
        [
            "# WWO WORLD NAMES & ALIASES — BATCH 1 REPORT",
            "",
            f"Starting master: `{starting_master}`",
            "",
            "## Inventory",
            "",
            f"- Entities inventoried: **{len(inventory['entities'])}** ({stable_ids} authoritative Stable IDs; source-record keys remain non-authoritative)",
            f"- Unique raw names: **{collisions['summary']['unique_raw_names']}**",
            f"- Normalized collisions: **{collisions['summary']['normalized_collisions']}**",
            f"- High-confidence aliases: **{high_confidence}**",
            f"- Historical-name candidates: **{historical_candidates}**",
            f"- Ambiguous mappings: **{ambiguous}**",
            f"- Missing display names: **{missing}**",
            "",
            "Modern GeoNames city shards and geometry/runtime files were read for source coverage, but modern reference records are not staged as 1900 authoritative entities by default.",
            "",
            "## Validation",
            "",
            f"- Search index: {search_result}",
            f"- Validator: **{validator}**",
            "- Deterministic replay: **PASS**" if not errors else "- Deterministic replay: **FAIL**",
            "- `git diff --check`: run before commit",
            "",
            "## Authority and delivery",
            "",
            "- Authoritative IDs changed: **NO**",
            "- Existing production world data rewritten: **NO**",
            f"- Commit: `{commit}`",
            f"- Push: `{push}`",
            f"- Draft PR: `{draft_pr}`",
            "",
            "## TOP 50 NAME / ALIAS CLEANUP TARGETS",
            "",
        ]
        + [
            f"{index + 1}. `{item['normalized_name']}` — {item['kind']} / {item['severity']} — {', '.join(item['entity_ids'])} — {', '.join(item['raw_names'])}"
            for index, item in enumerate(collisions["top_50_cleanup_targets"])
        ]
        + ["", "No merge performed by this task.", ""],
    )


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument(
        "--output-root",
        type=Path,
        default=None,
        help="staging output directory (default: data/staging/world_names)",
    )
    parser.add_argument("--include-modern-reference", action="store_true")
    parser.add_argument("--starting-master", default=None)
    parser.add_argument("--commit", default="not created")
    parser.add_argument("--push", default="not attempted")
    parser.add_argument("--draft-pr", default="none")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    root = args.root.resolve()
    output_root = (args.output_root or root / "data/staging/world_names").resolve()
    artifacts = build_artifacts(root, include_modern_reference=args.include_modern_reference)
    if artifacts["validation_errors"]:
        for error in artifacts["validation_errors"]:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    write_json(output_root / "name_inventory.json", artifacts["inventory"])
    write_json(output_root / "aliases.json", artifacts["aliases"])
    write_json(output_root / "collision_report.json", artifacts["collision_report"])
    write_json(output_root / "search_index.json", artifacts["search_index"])

    starting_master = args.starting_master or _git_revision(root, "origin/master")
    report_path = root / "docs/world_names/BATCH_1_REPORT.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        render_report(artifacts, starting_master, args.commit, args.push, args.draft_pr),
        encoding="utf-8",
    )
    summary = {
        "entities": len(artifacts["inventory"]["entities"]),
        "aliases": len(artifacts["aliases"]["aliases"]),
        "normalized_keys": len(artifacts["search_index"]["entries"]),
        "normalized_collisions": artifacts["collision_report"]["summary"]["normalized_collisions"],
        "validator": "PASS",
        "output_root": output_root.relative_to(root).as_posix(),
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
