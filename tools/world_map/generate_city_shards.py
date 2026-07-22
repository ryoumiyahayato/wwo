#!/usr/bin/env python3
"""Generate lazy-loadable modern city/municipality shards for the formal map.

Input data is downloaded separately so generation is deterministic and testable.
The runtime artifacts intentionally contain only fields needed by the map.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import sys
import unicodedata
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, Mapping, Sequence

GEONAMES_COLUMNS = (
    "geonameid", "name", "asciiname", "alternatenames", "latitude",
    "longitude", "feature_class", "feature_code", "country_code", "cc2",
    "admin1_code", "admin2_code", "admin3_code", "admin4_code",
    "population", "elevation", "dem", "timezone", "modification_date",
)

TARGET_CONTINENTS = {"EU", "AS", "NA"}
CAPITAL_CODES = {"PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4"}
GENERAL_MIN_POPULATION = 5_000
FRANCE_MIN_MUNICIPALITY_COUNT = 25_000
SCHEMA_VERSION = 1
SOURCE_URL = "https://download.geonames.org/export/dump/"
LICENSE_NAME = "Creative Commons Attribution 4.0"
LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/"


@dataclass(frozen=True)
class CountryInfo:
    iso2: str
    name: str
    continent: str


@dataclass(frozen=True)
class GeoRecord:
    geonameid: str
    name: str
    asciiname: str
    latitude: float
    longitude: float
    feature_class: str
    feature_code: str
    country_code: str
    admin1_code: str
    admin2_code: str
    admin3_code: str
    admin4_code: str
    population: int
    timezone: str
    modification_date: str

    @property
    def stable_id(self) -> str:
        return f"geonames:{self.geonameid}"


class GenerationError(RuntimeError):
    pass


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cities-zip", type=Path)
    parser.add_argument("--france-zip", type=Path)
    parser.add_argument("--country-info", type=Path)
    parser.add_argument("--countries", type=Path)
    parser.add_argument("--curated-cities", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--generated-at", default="")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate-output", type=Path)
    return parser.parse_args(argv)


def normalize_name(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value)
    ascii_value = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]+", "", ascii_value.casefold())


def safe_int(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def safe_float(value: str) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise GenerationError(f"invalid coordinate: {value!r}") from exc
    if not math.isfinite(result):
        raise GenerationError(f"non-finite coordinate: {value!r}")
    return result


def iter_country_info(path: Path) -> Iterator[CountryInfo]:
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            if not raw_line or raw_line.startswith("#"):
                continue
            parts = raw_line.rstrip("\n").split("\t")
            if len(parts) < 9:
                continue
            iso2 = parts[0].strip().upper()
            if len(iso2) == 2:
                yield CountryInfo(iso2=iso2, name=parts[4].strip(), continent=parts[8].strip())


def _open_geonames_text(zip_path: Path):
    archive = zipfile.ZipFile(zip_path)
    names = [name for name in archive.namelist() if not name.endswith("/") and name.lower().endswith(".txt")]
    if not names:
        archive.close()
        raise GenerationError(f"no .txt member in {zip_path}")
    preferred = zip_path.stem.lower() + ".txt"
    member = next((name for name in names if Path(name).name.lower() == preferred), names[0])
    binary = archive.open(member, "r")
    import io
    return archive, io.TextIOWrapper(binary, encoding="utf-8", newline="")


def iter_geonames_zip(zip_path: Path) -> Iterator[GeoRecord]:
    archive, handle = _open_geonames_text(zip_path)
    try:
        for line_number, raw_line in enumerate(handle, 1):
            parts = raw_line.rstrip("\n").split("\t")
            if len(parts) < len(GEONAMES_COLUMNS):
                raise GenerationError(
                    f"{zip_path}:{line_number}: expected {len(GEONAMES_COLUMNS)} fields, got {len(parts)}"
                )
            values = dict(zip(GEONAMES_COLUMNS, parts))
            record = GeoRecord(
                geonameid=values["geonameid"],
                name=values["name"].strip(),
                asciiname=values["asciiname"].strip(),
                latitude=safe_float(values["latitude"]),
                longitude=safe_float(values["longitude"]),
                feature_class=values["feature_class"].strip(),
                feature_code=values["feature_code"].strip(),
                country_code=values["country_code"].strip().upper(),
                admin1_code=values["admin1_code"].strip(),
                admin2_code=values["admin2_code"].strip(),
                admin3_code=values["admin3_code"].strip(),
                admin4_code=values["admin4_code"].strip(),
                population=safe_int(values["population"]),
                timezone=values["timezone"].strip(),
                modification_date=values["modification_date"].strip(),
            )
            if record.name and record.country_code and -90 <= record.latitude <= 90 and -180 <= record.longitude <= 180:
                yield record
    finally:
        handle.close()
        archive.close()


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise GenerationError(f"expected object in {path}")
    return value


def country_id_to_iso(countries_path: Path) -> dict[str, str]:
    document = load_json(countries_path)
    result: dict[str, str] = {}
    for raw in document.get("countries", []):
        if not isinstance(raw, dict):
            continue
        country_id = str(raw.get("id", ""))
        iso2 = str(raw.get("iso_a2", raw.get("iso2", ""))).upper()
        if country_id and len(iso2) == 2:
            result[country_id] = iso2
    return result


def curated_overrides(countries_path: Path, cities_path: Path) -> dict[tuple[str, str], dict]:
    country_map = country_id_to_iso(countries_path)
    document = load_json(cities_path)
    result: dict[tuple[str, str], dict] = {}
    for raw in document.get("cities", []):
        if not isinstance(raw, dict):
            continue
        iso2 = country_map.get(str(raw.get("parent_country_id", "")), "")
        name = str(raw.get("native_name", raw.get("id", raw.get("name", ""))))
        key = (iso2, normalize_name(name))
        if iso2 and key[1]:
            result[key] = {
                "display_name_zh": str(raw.get("name", "")),
                "curated_city_id": str(raw.get("id", "")),
                "label_priority_override": safe_int(str(raw.get("label_priority", 0))),
                "historical_theme_override": True,
            }
    return result


def record_priority(record: GeoRecord, record_type: str) -> int:
    if record.feature_code == "PPLC":
        return 100
    if record.feature_code == "PPLA":
        return 94
    if record.feature_code in {"PPLA2", "PPLA3", "PPLA4"}:
        return 84
    if record_type == "municipality":
        return 34
    population = max(0, record.population)
    if population >= 10_000_000:
        return 96
    if population >= 1_000_000:
        return 88
    if population >= 250_000:
        return 76
    if population >= 50_000:
        return 62
    if population >= 10_000:
        return 48
    return 38


def record_to_runtime(
    record: GeoRecord,
    country: CountryInfo,
    record_type: str,
    overrides: Mapping[tuple[str, str], Mapping[str, object]],
) -> dict:
    key_candidates = [
        (record.country_code, normalize_name(record.name)),
        (record.country_code, normalize_name(record.asciiname)),
    ]
    override: Mapping[str, object] = {}
    for key in key_candidates:
        if key in overrides:
            override = overrides[key]
            break
    priority = max(record_priority(record, record_type), int(override.get("label_priority_override", 0)))
    return {
        "id": record.stable_id,
        "name": str(override.get("display_name_zh", "")) or record.name,
        "native_name": record.name,
        "ascii_name": record.asciiname,
        "country_code": record.country_code,
        "continent": country.continent,
        "lon_lat": [round(record.longitude, 6), round(record.latitude, 6)],
        "population": record.population,
        "feature_code": record.feature_code,
        "record_type": record_type,
        "admin1_code": record.admin1_code,
        "admin2_code": record.admin2_code,
        "admin3_code": record.admin3_code,
        "admin4_code": record.admin4_code,
        "timezone": record.timezone,
        "label_priority": priority,
        "major": priority >= 76,
        "modern_geography": True,
        "curated_city_id": str(override.get("curated_city_id", "")),
        "historical_theme_override": bool(override.get("historical_theme_override", False)),
    }


def bounds_for(records: Sequence[dict]) -> list[float]:
    if not records:
        return [0.0, 0.0, 0.0, 0.0]
    lons = [float(record["lon_lat"][0]) for record in records]
    lats = [float(record["lon_lat"][1]) for record in records]
    return [round(min(lons), 6), round(min(lats), 6), round(max(lons), 6), round(max(lats), 6)]


def json_dump(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(",", ":"), sort_keys=False)
        handle.write("\n")


def general_records(
    cities_zip: Path,
    countries: Mapping[str, CountryInfo],
    overrides: Mapping[tuple[str, str], Mapping[str, object]],
) -> dict[str, dict[str, dict]]:
    grouped: dict[str, dict[str, dict]] = defaultdict(dict)
    for record in iter_geonames_zip(cities_zip):
        country = countries.get(record.country_code)
        if country is None or country.continent not in TARGET_CONTINENTS:
            continue
        if record.feature_class != "P":
            continue
        if record.population < GENERAL_MIN_POPULATION and record.feature_code not in CAPITAL_CODES:
            continue
        grouped[record.country_code][record.stable_id] = record_to_runtime(record, country, "city", overrides)
    return grouped


def france_records(
    france_zip: Path,
    country: CountryInfo,
    overrides: Mapping[tuple[str, str], Mapping[str, object]],
    existing: Mapping[str, dict],
) -> tuple[dict[str, dict[str, dict]], int]:
    by_admin1: dict[str, dict[str, dict]] = defaultdict(dict)
    municipality_count = 0
    municipality_names: set[tuple[str, str, str]] = set()
    records = list(iter_geonames_zip(france_zip))

    for record in records:
        if record.country_code != "FR" or not (record.feature_class == "A" and record.feature_code == "ADM4"):
            continue
        admin1 = record.admin1_code or "00"
        by_admin1[admin1][record.stable_id] = record_to_runtime(record, country, "municipality", overrides)
        municipality_count += 1
        municipality_names.add((admin1, record.admin2_code, normalize_name(record.name)))

    for record in records:
        if record.country_code != "FR" or record.feature_class != "P":
            continue
        if record.population < GENERAL_MIN_POPULATION and record.feature_code not in CAPITAL_CODES:
            continue
        admin1 = record.admin1_code or "00"
        municipality_key = (admin1, record.admin2_code, normalize_name(record.name))
        if municipality_key in municipality_names and record.feature_code not in CAPITAL_CODES:
            continue
        by_admin1[admin1][record.stable_id] = record_to_runtime(record, country, "city", overrides)

    for record_id, runtime in existing.items():
        admin1 = str(runtime.get("admin1_code", "")) or "00"
        by_admin1[admin1][record_id] = runtime
    return by_admin1, municipality_count


def shard_document(country: CountryInfo, records: Sequence[dict], shard_id: str, generated_at: str) -> dict:
    return {
        "schema_version": SCHEMA_VERSION,
        "dataset": "modern_city_detail",
        "generated_at": generated_at,
        "source": "GeoNames",
        "license": LICENSE_NAME,
        "country_code": country.iso2,
        "country_name": country.name,
        "continent": country.continent,
        "shard_id": shard_id,
        "bounds": bounds_for(records),
        "count": len(records),
        "cities": records,
    }


def generate(args: argparse.Namespace) -> dict:
    required = [args.cities_zip, args.france_zip, args.country_info, args.countries, args.curated_cities, args.output]
    if any(path is None for path in required):
        raise GenerationError("generation requires all input and output arguments")
    for path in required[:-1]:
        if not path.is_file():
            raise GenerationError(f"missing input: {path}")

    generated_at = args.generated_at.strip() or datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    countries = {
        item.iso2: item
        for item in iter_country_info(args.country_info)
        if item.continent in TARGET_CONTINENTS
    }
    if "FR" not in countries:
        raise GenerationError("countryInfo.txt did not contain France")
    overrides = curated_overrides(args.countries, args.curated_cities)
    grouped = general_records(args.cities_zip, countries, overrides)
    france_existing = grouped.pop("FR", {})
    france_by_admin1, municipality_count = france_records(
        args.france_zip, countries["FR"], overrides, france_existing
    )
    if municipality_count < FRANCE_MIN_MUNICIPALITY_COUNT:
        raise GenerationError(
            f"France ADM4 coverage too small: {municipality_count} < {FRANCE_MIN_MUNICIPALITY_COUNT}"
        )

    output = args.output
    if output.exists():
        shutil.rmtree(output)
    (output / "countries").mkdir(parents=True, exist_ok=True)
    (output / "france").mkdir(parents=True, exist_ok=True)

    country_entries: list[dict] = []
    total_records = 0
    total_shards = 0
    for iso2 in sorted(grouped):
        country = countries[iso2]
        records = sorted(
            grouped[iso2].values(),
            key=lambda item: (-int(item["label_priority"]), -int(item["population"]), str(item["id"])),
        )
        if not records:
            continue
        relative = f"countries/{iso2}.json"
        json_dump(output / relative, shard_document(country, records, iso2, generated_at))
        shard_bounds = bounds_for(records)
        country_entries.append({
            "country_code": iso2,
            "country_name": country.name,
            "continent": country.continent,
            "count": len(records),
            "bounds": shard_bounds,
            "shards": [{"id": iso2, "path": relative, "count": len(records), "bounds": shard_bounds}],
        })
        total_records += len(records)
        total_shards += 1

    france_shards: list[dict] = []
    france_all: list[dict] = []
    for admin1 in sorted(france_by_admin1):
        records = sorted(
            france_by_admin1[admin1].values(),
            key=lambda item: (-int(item["label_priority"]), -int(item["population"]), str(item["id"])),
        )
        if not records:
            continue
        shard_id = f"FR-{admin1}"
        relative = f"france/{shard_id}.json"
        document = shard_document(countries["FR"], records, shard_id, generated_at)
        document["admin1_code"] = admin1
        document["municipality_detail"] = True
        json_dump(output / relative, document)
        shard_bounds = bounds_for(records)
        france_shards.append({
            "id": shard_id,
            "path": relative,
            "admin1_code": admin1,
            "count": len(records),
            "bounds": shard_bounds,
        })
        france_all.extend(records)
        total_records += len(records)
        total_shards += 1

    country_entries.append({
        "country_code": "FR",
        "country_name": countries["FR"].name,
        "continent": countries["FR"].continent,
        "count": len(france_all),
        "municipality_count": municipality_count,
        "municipality_detail": True,
        "bounds": bounds_for(france_all),
        "shards": france_shards,
    })
    country_entries.sort(key=lambda item: str(item["country_code"]))

    index = {
        "schema_version": SCHEMA_VERSION,
        "dataset": "modern_city_detail",
        "generated_at": generated_at,
        "source": {
            "name": "GeoNames",
            "download_root": SOURCE_URL,
            "inputs": ["cities5000.zip", "FR.zip", "countryInfo.txt"],
            "license": LICENSE_NAME,
            "license_url": LICENSE_URL,
        },
        "geographic_scope": ["Europe", "Asia", "North America"],
        "historical_status": "modern_reference_only",
        "runtime_policy": {
            "load_mode": "viewport_intersecting_shards",
            "country_cache_limit": 12,
            "visible_node_budget": 1600,
            "visible_label_budget": 180,
        },
        "totals": {
            "countries": len(country_entries),
            "shards": total_shards,
            "records": total_records,
            "france_municipalities": municipality_count,
        },
        "countries": country_entries,
    }
    json_dump(output / "index.json", index)
    json_dump(output / "LICENSE.json", {
        "dataset": "modern_city_detail",
        "source": "GeoNames",
        "license": LICENSE_NAME,
        "license_url": LICENSE_URL,
        "attribution": "Contains GeoNames geographical data, licensed under CC BY 4.0.",
    })
    validate_output(output)
    return index


def validate_output(output: Path) -> dict:
    index_path = output / "index.json"
    if not index_path.is_file():
        raise GenerationError(f"missing generated index: {index_path}")
    index = load_json(index_path)
    if int(index.get("schema_version", 0)) != SCHEMA_VERSION:
        raise GenerationError("generated index schema mismatch")
    if index.get("historical_status") != "modern_reference_only":
        raise GenerationError("generated data must be explicitly marked modern")
    countries = index.get("countries", [])
    if not isinstance(countries, list) or not countries:
        raise GenerationError("generated index has no countries")
    total = 0
    france_municipalities = 0
    seen_paths: set[str] = set()
    for country in countries:
        if not isinstance(country, dict):
            raise GenerationError("invalid country index entry")
        if country.get("continent") not in TARGET_CONTINENTS:
            raise GenerationError(f"unexpected continent: {country.get('continent')}")
        if country.get("country_code") == "FR":
            france_municipalities = int(country.get("municipality_count", 0))
        for shard in country.get("shards", []):
            relative = str(shard.get("path", ""))
            if not relative or relative in seen_paths:
                raise GenerationError(f"invalid or duplicate shard path: {relative!r}")
            seen_paths.add(relative)
            shard_path = output / relative
            document = load_json(shard_path)
            records = document.get("cities", [])
            if not isinstance(records, list):
                raise GenerationError(f"invalid city array in {shard_path}")
            if len(records) != int(shard.get("count", -1)):
                raise GenerationError(f"count mismatch in {shard_path}")
            for record in records:
                lon_lat = record.get("lon_lat", [])
                if not isinstance(lon_lat, list) or len(lon_lat) != 2:
                    raise GenerationError(f"invalid coordinate in {shard_path}")
                if not bool(record.get("modern_geography", False)):
                    raise GenerationError(f"missing modern marker in {shard_path}")
            total += len(records)
    if france_municipalities < FRANCE_MIN_MUNICIPALITY_COUNT:
        raise GenerationError("France municipality coverage below required floor")
    if total != int(index.get("totals", {}).get("records", -1)):
        raise GenerationError("index total record count mismatch")
    return {
        "countries": len(countries),
        "shards": len(seen_paths),
        "records": total,
        "france_municipalities": france_municipalities,
    }


def self_test() -> None:
    assert normalize_name("Köln") == "koln"
    assert normalize_name("Saint-Étienne") == "saintetienne"
    sample = GeoRecord(
        geonameid="1", name="Paris", asciiname="Paris", latitude=48.8566,
        longitude=2.3522, feature_class="P", feature_code="PPLC",
        country_code="FR", admin1_code="11", admin2_code="75",
        admin3_code="", admin4_code="", population=2_000_000,
        timezone="Europe/Paris", modification_date="2026-01-01",
    )
    runtime = record_to_runtime(
        sample,
        CountryInfo("FR", "France", "EU"),
        "city",
        {("FR", "paris"): {"display_name_zh": "巴黎", "curated_city_id": "paris"}},
    )
    assert runtime["name"] == "巴黎"
    assert runtime["label_priority"] == 100
    assert bounds_for([runtime]) == [2.3522, 48.8566, 2.3522, 48.8566]
    print("city shard generator self-test passed")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.self_test:
            self_test()
            return 0
        if args.validate_output is not None:
            print(json.dumps(validate_output(args.validate_output), ensure_ascii=False, sort_keys=True))
            return 0
        index = generate(args)
        print(json.dumps(index["totals"], ensure_ascii=False, sort_keys=True))
        return 0
    except (GenerationError, OSError, ValueError, zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
