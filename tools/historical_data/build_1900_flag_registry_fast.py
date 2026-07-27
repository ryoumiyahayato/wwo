#!/usr/bin/env python3
"""Fast deterministic flag builder using Commons-rendered PNG thumbnails.

The source record still points to the original Commons file and its license.
The committed runtime asset is a normalized PNG derivative of Commons' render,
which avoids locally rasterizing complex SVG files in CI.
"""

from __future__ import annotations

import hashlib
import html
import io
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from PIL import Image

import build_1900_flag_registry as source_specs

COMMONS_API = source_specs.COMMONS_API
USER_AGENT = "wwo-1900-flag-registry/1.1 (deterministic Commons thumbnails)"
TARGET_DATE = source_specs.TARGET_DATE
UNITS_PATH = source_specs.UNITS_PATH
REGISTRY_PATH = source_specs.REGISTRY_PATH
ATTRIBUTION_PATH = source_specs.ATTRIBUTION_PATH
ASSET_DIR = source_specs.ASSET_DIR
CANVAS_SIZE = source_specs.CANVAS_SIZE
FLAG_SPECS = source_specs.FLAG_SPECS


def fetch_json(parameters: dict[str, str], retries: int = 6) -> dict[str, Any]:
    url = COMMONS_API + "?" + urllib.parse.urlencode(parameters)
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code != 429 or attempt + 1 >= retries:
                raise
            time.sleep(float(exc.headers.get("Retry-After", min(20, 2 ** (attempt + 1)))))
    raise RuntimeError("Commons metadata retry exhausted")


def fetch_bytes(url: str, retries: int = 5) -> bytes:
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            if exc.code != 429 or attempt + 1 >= retries:
                raise
            time.sleep(float(exc.headers.get("Retry-After", min(20, 2 ** (attempt + 1)))))
    raise RuntimeError("Commons thumbnail retry exhausted")


def strip_html(value: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(value))).strip()


def query_files(titles: list[str]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for start in range(0, len(titles), 25):
        batch = titles[start:start + 25]
        document = fetch_json({
            "action": "query",
            "titles": "|".join(batch),
            "redirects": "1",
            "prop": "imageinfo",
            "iiprop": "url|mime|size|sha1|extmetadata",
            "iiurlwidth": "576",
            "format": "json",
            "formatversion": "2",
            "origin": "*",
            "maxlag": "5",
        })
        query = document.get("query", {})
        normalized = {
            str(item.get("from", "")): str(item.get("to", ""))
            for item in query.get("normalized", [])
        }
        redirects = {
            str(item.get("from", "")): str(item.get("to", ""))
            for item in query.get("redirects", [])
        }
        pages = {
            str(page.get("title", "")): page
            for page in query.get("pages", [])
        }
        for original in batch:
            normalized_title = normalized.get(original, original)
            resolved = redirects.get(normalized_title, normalized_title)
            page = pages.get(resolved)
            if page is None or page.get("missing") is not None or not page.get("imageinfo"):
                raise ValueError(f"Commons source not resolved: {original} -> {resolved}")
            info = page["imageinfo"][0]
            if not info.get("thumburl"):
                raise ValueError(f"Commons thumbnail missing: {resolved}")
            result[original] = page
        time.sleep(0.4)
    return result


def normalize_png(payload: bytes) -> bytes:
    with Image.open(io.BytesIO(payload)) as source:
        image = source.convert("RGBA")
        image.thumbnail(CANVAS_SIZE, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
        canvas.alpha_composite(
            image,
            ((CANVAS_SIZE[0] - image.width) // 2, (CANVAS_SIZE[1] - image.height) // 2),
        )
        output = io.BytesIO()
        canvas.save(output, format="PNG", optimize=True)
        return output.getvalue()


def build_record(
    flag_id: str,
    spec: tuple[str, str, str, str, str, str, str],
    page: dict[str, Any],
) -> tuple[dict[str, Any], str]:
    title, valid_from, valid_to, ratio, flag_type, confidence, heraldic_zh = spec
    info = page["imageinfo"][0]
    metadata = info.get("extmetadata", {})
    thumbnail_url = str(info["thumburl"])
    normalized = normalize_png(fetch_bytes(thumbnail_url))
    asset_path = ASSET_DIR / f"{flag_id}.png"
    asset_path.write_bytes(normalized)
    license_name = str((metadata.get("LicenseShortName") or {}).get("value", ""))
    artist = strip_html(str((metadata.get("Artist") or {}).get("value", "")))
    record = {
        "id": flag_id,
        "snapshot_date": TARGET_DATE,
        "valid_from": valid_from,
        "valid_to": valid_to,
        "ratio": ratio,
        "flag_type": flag_type,
        "confidence": confidence,
        "heraldic_zh": heraldic_zh,
        "render_mode": "source_asset",
        "asset_path": "res://" + asset_path.as_posix(),
        "asset_sha256": hashlib.sha256(normalized).hexdigest(),
        "source_title": str(page.get("title", title)),
        "source_page": str(info.get("descriptionurl", "")),
        "source_asset": str(info.get("url", "")),
        "source_rendered_png": thumbnail_url,
        "source_sha1": str(info.get("sha1", "")),
        "source_mime": str(info.get("mime", "")),
        "source_width": int(info.get("width", 0)),
        "source_height": int(info.get("height", 0)),
        "source_license": license_name,
        "source_usage_terms": str((metadata.get("UsageTerms") or {}).get("value", "")),
        "source_artist": artist,
        "source_description": strip_html(
            str((metadata.get("ImageDescription") or {}).get("value", ""))
        ),
    }
    row = (
        f"| `{flag_id}` | [{record['source_title']}]({record['source_page']}) | "
        f"{license_name or 'see source page'} | {artist or 'see source page'} | "
        f"{valid_from}—{valid_to} | {flag_type} |"
    )
    return record, row


def main() -> int:
    units_document = json.loads(UNITS_PATH.read_text(encoding="utf-8"))
    source_specs._normalize_unit_flags(units_document)
    pages = query_files([spec[0] for spec in FLAG_SPECS.values()])
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    records: dict[str, dict[str, Any]] = {
        "no_single_standard_flag": {
            "id": "no_single_standard_flag",
            "asset_path": "",
            "render_mode": "neutral_hatch",
            "valid_from": "",
            "valid_to": "",
            "ratio": "",
            "flag_type": "documented_absence",
            "confidence": "high",
            "source_title": "",
            "source_page": "",
            "source_asset": "",
            "source_license": "",
            "source_artist": "",
            "heraldic_zh": "1900年不存在可诚实归结为单一标准国旗的旗面；界面显示中性斜线。",
        }
    }
    rows: list[str] = []
    for flag_id, flag_spec in sorted(FLAG_SPECS.items()):
        print(f"building {flag_id}", flush=True)
        record, row = build_record(flag_id, flag_spec, pages[flag_spec[0]])
        records[flag_id] = record
        rows.append(row)

    unresolved: list[str] = []
    mode_counts: dict[str, int] = {}
    for unit in units_document.get("units", []):
        flag_id = str(unit.get("flag_id", ""))
        mode = str(unit.get("flag_mode", ""))
        mode_counts[mode] = mode_counts.get(mode, 0) + 1
        if flag_id not in records:
            unresolved.append(f"{unit.get('id')}:{flag_id}")
    if unresolved:
        raise ValueError("Unresolved flag records: " + ", ".join(unresolved))
    if len(FLAG_SPECS) != 60:
        raise ValueError(f"Expected 60 source flag specs, found {len(FLAG_SPECS)}")

    UNITS_PATH.write_text(
        json.dumps(units_document, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    registry = {
        "schema_version": 1,
        "snapshot_date": TARGET_DATE,
        "policy": {
            "random_or_hash_flags_allowed": False,
            "controller_flag_is_explicitly_labeled": True,
            "documented_absence_uses_neutral_rendering": True,
            "source_asset_required_for_rendered_flag": True,
        },
        "record_count": len(records),
        "unit_flag_mode_counts": mode_counts,
        "records": records,
    }
    REGISTRY_PATH.write_text(
        json.dumps(registry, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    ATTRIBUTION_PATH.write_text(
        "# 1900 flag asset attribution\n\n"
        "All runtime PNGs are normalized derivatives of Wikimedia Commons renders of the cited original files. "
        "The original per-file license remains controlling. A controller flag is not claimed to be a local national flag.\n\n"
        "| Registry ID | Source file | License | Creator/attribution | Historical use | Type |\n"
        "|---|---|---|---|---|---|\n"
        + "\n".join(rows)
        + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "flags": len(records),
        "assets": len(FLAG_SPECS),
        "units": len(units_document.get("units", [])),
        "mode_counts": mode_counts,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
