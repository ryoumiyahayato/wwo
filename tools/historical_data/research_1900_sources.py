#!/usr/bin/env python3
"""Fetch reproducible source candidates for the 1900 historical layer.

This is a research probe, not a runtime data generator. It downloads the
official CShapes 2.0 GeoJSON distribution and queries Wikimedia Commons for
historical flag candidates. Selection remains manual and source-aware.
"""

from __future__ import annotations

import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

CSHAPES_PAGE = "https://icr.ethz.ch/data/cshapes/"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "wwo-1900-source-audit/1.1 (historical data research; contact via repository)"
COMMONS_REQUEST_INTERVAL_SECONDS = 0.65
COMMONS_MAX_RETRIES = 6

FLAG_QUERIES: dict[str, str] = {
    "france_1794": "Flag of France 1794 1815 1830 historical svg",
    "united_kingdom_1801": "Flag of the United Kingdom 1801 svg",
    "german_empire_1867": "Flag of the German Empire 1867 1918 svg",
    "austria_hungary_1869": "Austria Hungary civil ensign 1869 1918 svg",
    "russian_empire_1896": "Flag of Russia 1896 1917 svg",
    "ottoman_empire_1844": "Flag of the Ottoman Empire 1844 1922 svg",
    "qing_empire_1889": "Flag of China 1889 1912 Qing svg",
    "japan_1870": "Flag of Japan 1870 1999 svg",
    "korean_empire_1897": "Flag of Korea 1897 1910 historical svg",
    "united_states_45_star": "Flag of the United States 1896 1908 45 stars svg",
    "italy_1861": "Flag of Italy 1861 1946 Kingdom",
    "spain_1875": "Flag of Spain 1875 1931",
    "portugal_1830": "Flag of Portugal 1830 1910",
    "belgium_1831": "Flag of Belgium",
    "congo_free_state": "Flag of the Congo Free State",
    "netherlands": "Flag of the Netherlands",
    "sweden_norway_union": "Swedish Norwegian union flag 1844 1905",
    "denmark": "Flag of Denmark",
    "switzerland": "Flag of Switzerland",
    "romania_1867": "Flag of Romania 1867 1948",
    "serbia_1882": "Flag of the Kingdom of Serbia 1882 1918",
    "montenegro_1876": "Flag of Montenegro 1876 1905",
    "bulgaria_1878": "Flag of Bulgaria 1878 1946",
    "greece_1822": "Flag of Greece 1822 1978",
    "qajar_persia": "Flag Qajar Persia lion sun",
    "afghanistan_1880": "Flag of Afghanistan 1880 1901",
    "siam_1855": "Flag of Siam 1855 1916 white elephant",
    "nepal_historical": "Flag of Nepal historical before 1962",
    "ethiopia_1897": "Flag of Ethiopia 1897 1914",
    "liberia_1847": "Flag of Liberia 1847",
    "morocco_plain_red": "Flag of Morocco before 1915 plain red",
    "muscat_oman_red": "Flag of Muscat Oman historical red",
    "mexico_1893": "Flag of Mexico 1893 1916",
    "guatemala_1871": "Flag of Guatemala 1871 1968",
    "honduras_1866": "Flag of Honduras 1898 1949",
    "el_salvador_1875": "Flag of El Salvador 1875 1912",
    "nicaragua_1896": "Flag of Nicaragua 1896 1908",
    "costa_rica_1848": "Flag of Costa Rica 1848 1906",
    "colombia_1861": "Flag of Colombia 1861",
    "venezuela_1863": "Flag of Venezuela 1863 1905",
    "ecuador_1860": "Flag of Ecuador 1860 1900",
    "peru_1884": "Flag of Peru 1884 1950",
    "bolivia_1851": "Flag of Bolivia 1851",
    "chile_1817": "Flag of Chile 1817",
    "argentina_1861": "Flag of Argentina 1861",
    "paraguay_1842": "Flag of Paraguay 1842 historical",
    "uruguay_1830": "Flag of Uruguay 1830",
    "brazil_1889": "Flag of Brazil 1889 1960",
    "haiti_1859": "Flag of Haiti 1859 1964",
    "dominican_republic_1865": "Flag of Dominican Republic 1865 historical",
}


def fetch_bytes(url: str, retries: int = 1) -> bytes:
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            if exc.code != 429 or attempt + 1 >= retries:
                raise
            retry_after = exc.headers.get("Retry-After")
            delay = float(retry_after) if retry_after else min(20.0, 1.5 * (2**attempt))
            time.sleep(delay)
    raise RuntimeError("unreachable fetch retry state")


def discover_cshapes_links() -> list[str]:
    page = fetch_bytes(CSHAPES_PAGE).decode("utf-8", errors="replace")
    links: list[str] = []
    for raw_href in re.findall(r'href=["\']([^"\']+)["\']', page, flags=re.I):
        href = html.unescape(raw_href)
        absolute = urllib.parse.urljoin(CSHAPES_PAGE, href)
        lowered = absolute.lower()
        if "cshape" not in lowered:
            continue
        if not any(token in lowered for token in ("geojson", ".json", ".zip")):
            continue
        if "europe" in lowered:
            continue
        links.append(absolute)
    return list(dict.fromkeys(links))


def download_cshapes(output_dir: Path) -> dict[str, Any]:
    links = discover_cshapes_links()
    (output_dir / "cshapes_discovered_links.json").write_text(
        json.dumps(links, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    if not links:
        raise RuntimeError("No CShapes GeoJSON/ZIP link discovered on official page")
    errors: list[str] = []
    for index, url in enumerate(links):
        try:
            payload = fetch_bytes(url)
            candidate_path = output_dir / f"cshapes_candidate_{index}"
            if payload[:2] == b"PK" or url.lower().endswith(".zip"):
                archive_path = candidate_path.with_suffix(".zip")
                archive_path.write_bytes(payload)
                with zipfile.ZipFile(archive_path) as archive:
                    json_members = [
                        name for name in archive.namelist()
                        if name.lower().endswith((".geojson", ".json"))
                        and "europe" not in name.lower()
                    ]
                    if not json_members:
                        raise RuntimeError("ZIP contains no global GeoJSON")
                    selected = max(json_members, key=lambda name: archive.getinfo(name).file_size)
                    geojson_path = output_dir / "cshapes_2_0.geojson"
                    geojson_path.write_bytes(archive.read(selected))
                    return inspect_geojson(geojson_path, url, selected)
            else:
                geojson_path = output_dir / "cshapes_2_0.geojson"
                geojson_path.write_bytes(payload)
                return inspect_geojson(geojson_path, url, "")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{url}: {exc}")
    raise RuntimeError("Unable to download CShapes data:\n" + "\n".join(errors))


def inspect_geojson(path: Path, source_url: str, member: str) -> dict[str, Any]:
    document = json.loads(path.read_text(encoding="utf-8"))
    features = document.get("features", [])
    property_keys: set[str] = set()
    sample_properties: list[dict[str, Any]] = []
    for feature in features[:10]:
        properties = feature.get("properties", {})
        property_keys.update(str(key) for key in properties.keys())
        sample_properties.append(properties)
    result = {
        "source_url": source_url,
        "archive_member": member,
        "feature_count": len(features),
        "property_keys": sorted(property_keys),
        "sample_properties": sample_properties,
        "bytes": path.stat().st_size,
    }
    path.with_name("cshapes_schema_probe.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return result


def commons_candidates(query: str) -> list[dict[str, Any]]:
    parameters = {
        "action": "query",
        "generator": "search",
        "gsrsearch": query,
        "gsrnamespace": "6",
        "gsrlimit": "10",
        "prop": "imageinfo",
        "iiprop": "url|mime|size|extmetadata",
        "format": "json",
        "formatversion": "2",
        "origin": "*",
        "maxlag": "5",
    }
    url = COMMONS_API + "?" + urllib.parse.urlencode(parameters)
    document = json.loads(fetch_bytes(url, COMMONS_MAX_RETRIES).decode("utf-8"))
    pages = document.get("query", {}).get("pages", [])
    candidates: list[dict[str, Any]] = []
    for page in pages:
        image_info = (page.get("imageinfo") or [{}])[0]
        metadata = image_info.get("extmetadata", {})
        candidates.append({
            "title": page.get("title", ""),
            "page_id": page.get("pageid"),
            "description_url": image_info.get("descriptionurl", ""),
            "original_url": image_info.get("url", ""),
            "mime": image_info.get("mime", ""),
            "width": image_info.get("width", 0),
            "height": image_info.get("height", 0),
            "license": (metadata.get("LicenseShortName") or {}).get("value", ""),
            "usage_terms": (metadata.get("UsageTerms") or {}).get("value", ""),
            "date_time_original": (metadata.get("DateTimeOriginal") or {}).get("value", ""),
            "image_description": (metadata.get("ImageDescription") or {}).get("value", ""),
            "credit": (metadata.get("Credit") or {}).get("value", ""),
            "artist": (metadata.get("Artist") or {}).get("value", ""),
        })
    return candidates


def research_flags(output_dir: Path) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for index, (key, query) in enumerate(FLAG_QUERIES.items()):
        if index:
            time.sleep(COMMONS_REQUEST_INTERVAL_SECONDS)
        try:
            candidates = commons_candidates(query)
            results[key] = {"query": query, "candidates": candidates}
        except Exception as exc:  # noqa: BLE001
            results[key] = {"query": query, "error": str(exc), "candidates": []}
    (output_dir / "commons_flag_candidates_1900.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return results


def main() -> int:
    output_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "artifacts/historical_1900_research")
    output_dir.mkdir(parents=True, exist_ok=True)
    report: dict[str, Any] = {
        "snapshot_date": "1900-03-12",
        "cshapes_license": "CC BY-NC-SA 4.0",
        "cshapes_citation": (
            "Schvitz et al. (2022), Mapping the International System, "
            "1886-2019: The CShapes 2.0 Dataset"
        ),
        "flag_policy": (
            "Candidates only. A flag is accepted only after date range, flag type, "
            "source description and reusable license are checked."
        ),
    }
    try:
        report["cshapes"] = download_cshapes(output_dir)
    except Exception as exc:  # noqa: BLE001
        report["cshapes_error"] = str(exc)
    flag_results = research_flags(output_dir)
    report["flag_subject_count"] = len(flag_results)
    report["flag_query_error_count"] = sum(
        1 for result in flag_results.values() if result.get("error")
    )
    report["flag_query_empty_count"] = sum(
        1 for result in flag_results.values() if not result.get("candidates")
    )
    (output_dir / "research_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if "cshapes" in report and report["flag_query_error_count"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
