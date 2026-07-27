#!/usr/bin/env python3
"""Download, normalize and document the source-backed 1900 flag assets.

The registry distinguishes national/state flags, civil or maritime ensigns used
only for identification, controller flags, and documented absence of a single
standard flag. No random or hash-derived flag is allowed.
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

import cairosvg
from PIL import Image

COMMONS_API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "wwo-1900-flag-registry/1.0 (source-backed historical assets)"
TARGET_DATE = "1900-03-12"
UNITS_PATH = Path("data/world_map/historical/political_units_1900.json")
REGISTRY_PATH = Path("data/world_map/historical/flags_1900.json")
ATTRIBUTION_PATH = Path("data/world_map/historical/FLAG_ASSET_ATTRIBUTION.md")
ASSET_DIR = Path("assets/historical_flags/1900")
CANVAS_SIZE = (288, 192)

# id: (Commons title, valid from, valid to, ratio, flag type, confidence, description)
FLAG_SPECS: dict[str, tuple[str, str, str, str, str, str, str]] = {
    "afghanistan_1880": ("File:Flag of Afghanistan (1880–1901).svg", "1880-01-01", "1901-01-01", "2:3", "national_flag", "high", "黑底中央白色徽记；采用1880—1901阿富汗旗式。"),
    "argentina_1861": ("File:Flag of Argentina (1818–1819, 1820–1829, 1861–2010).svg", "1861-01-01", "2010-11-23", "9:14", "state_flag", "high", "浅蓝—白—浅蓝三横带，白带中央五月太阳。"),
    "austria_hungary_civil_1869": ("File:Civil ensign of Austria-Hungary (1869-1918).svg", "1869-01-01", "1918-11-11", "2:3", "civil_ensign_interface_identifier", "high", "奥地利红白红与匈牙利红白绿并列，含两部分国徽；仅作双元君主国识别，不称统一国旗。"),
    "belgium_1831": ("File:Flag of Belgium.svg", "1831-10-12", "9999-12-31", "13:15", "national_flag", "high", "黑、黄、红三道竖带。"),
    "bolivia_1851": ("File:Flag of Bolivia.svg", "1851-10-31", "9999-12-31", "15:22", "civil_flag", "high", "红、黄、绿三道横带。"),
    "brazil_1889": ("File:Flag of Brazil (1889–1960).svg", "1889-11-19", "1960-05-31", "7:10", "national_flag", "high", "绿地黄菱，蓝色天球内为1889年星位和秩序与进步绶带。"),
    "brunei_yellow_pre1906": ("File:Old Flag of Brunei.svg", "before-1906", "1906-01-01", "1:2", "sultanate_flag", "medium", "纯黄色苏丹旗；1906年前版本。"),
    "bukhara_1868": ("File:Flag of the Emirate of Bukhara.svg", "1868-01-01", "1920-09-02", "2:3", "emirate_flag_reconstruction", "medium", "浅绿底，边饰、阿拉伯文字、弯月与星；现代矢量据历史描述复原。"),
    "bulgaria_1878": ("File:Flag of Bulgaria (1879–1947).svg", "1879-04-16", "1947-12-06", "3:5", "national_flag", "high", "白、绿、红三道横带。"),
    "canada_red_ensign_1892": ("File:Flag of Canada (1868–1921).svg", "1868-01-01", "1921-01-01", "1:2", "unofficial_national_ensign", "medium", "英国红船旗，飞端盾徽汇集加拿大各省；1900年使用形态存在省徽排列变体。"),
    "chile_1817": ("File:Flag of Chile.svg", "1817-10-18", "9999-12-31", "2:3", "national_flag", "high", "白红两横带，左上蓝色方区内一颗白色五角星。"),
    "colombia_1861": ("File:Flag of Colombia.svg", "1861-11-26", "9999-12-31", "2:3", "national_flag", "high", "黄、蓝、红三道横带，黄色占旗高一半。"),
    "congo_free_state_1885": ("File:Flag of the Congo Free State.svg", "1885-07-01", "1908-11-15", "2:3", "state_flag", "high", "蓝地，靠旗杆上方一颗黄色五角星。"),
    "costa_rica_1848": ("File:Flag of Costa Rica (1848–1906).svg", "1848-11-27", "1906-01-01", "2:3", "state_flag", "high", "蓝白红白蓝五横带，红带加宽并置历史国徽。"),
    "denmark_dannebrog": ("File:Flag of Denmark.svg", "1625-01-01", "9999-12-31", "28:37", "national_flag", "high", "红地白色斯堪的纳维亚十字。"),
    "dominican_1865": ("File:Flag of the Dominican Republic.svg", "1865-01-01", "9999-12-31", "2:3", "state_flag_layout_reference", "medium", "白十字分隔蓝红四区；中央国徽细节在1900年版本上仍有变体，资产用于布局与基本纹章结构。"),
    "ecuador_1860": ("File:Ecuador (1860-1900).png", "1860-09-26", "1900-10-31", "5:9", "national_flag", "medium", "黄蓝红三横带，黄带加宽；使用1900年10月改制前版本。"),
    "egypt_1882": ("File:Flag of Egypt (1882–1922).svg", "1882-01-01", "1922-12-10", "1:2", "khedival_flag", "high", "红地，三组白色弯月与五角星。"),
    "el_salvador_1875": ("File:Flag of El Salvador (1875–1912).svg", "1875-04-28", "1912-09-17", "4:7", "national_flag", "high", "蓝白蓝横带，中央置历史国徽。"),
    "ethiopia_1897": ("File:Flag of Ethiopia (1897–1914).svg", "1897-10-06", "1914-01-01", "1:2", "national_flag", "high", "红黄绿三角长旗式，中央无现代徽章。"),
    "france_tricolour_1794": ("File:Flag of France.svg", "1794-02-15", "9999-12-31", "2:3", "national_flag", "high", "蓝、白、红等宽竖带。"),
    "german_empire_1867": ("File:Flag of Germany (1867–1918).svg", "1867-07-01", "1918-11-11", "2:3", "national_flag", "high", "黑、白、红三道横带。"),
    "greece_1822": ("File:Flag of Greece (1822-1978).svg", "1822-03-15", "1978-12-22", "2:3", "land_flag", "high", "蓝地白十字；1900年陆上国旗式。"),
    "guatemala_1871": ("File:Flag of Guatemala (1871–1968).svg", "1871-08-17", "1968-09-15", "2:3", "state_flag", "high", "浅蓝白浅蓝竖带，中央置1871年国徽。"),
    "haiti_1859": ("File:Flag of Haiti (1820–1849, 1859–1964).svg", "1859-01-15", "1964-06-21", "3:5", "state_flag", "high", "蓝红两横带，白色方区内置1859年共和国国徽。"),
    "honduras_1898": ("File:Flag of Honduras (1890s yellow star variant).svg", "1898-01-01", "1949-01-01", "1:2", "national_flag_variant", "medium", "蓝白蓝横带，白带五颗黄色星；对应1890年代至20世纪前期变体。"),
    "italy_1861": ("File:Flag of Italy (1861–1946).svg", "1861-03-17", "1946-06-18", "2:3", "state_flag", "high", "绿白红竖带，白带中央萨伏依王室盾徽。"),
    "japan_1870": ("File:Flag of Japan (1870–1999).svg", "1870-02-27", "1999-08-13", "7:10", "national_flag", "high", "白地中央红色日轮；采用1870年比例。"),
    "khiva_historical": ("File:Flag of the Khanate of Khiva.svg", "before-1920", "1920-02-02", "2:3", "khanate_flag_reconstruction", "low", "黑地蓝边，黄色弯月与星；现代矢量为历史重构，置信度较低。"),
    "korea_taegeuk_1897": ("File:Flag of Korea (1899).svg", "1899-01-01", "1905-01-01", "2:3", "national_flag_contemporary_source", "high", "白地，中央红蓝太极，四角八卦；依据1899年《Flags of Maritime Nations》同时代图版。"),
    "liberia_1847": ("File:Flag of Liberia.svg", "1847-08-24", "9999-12-31", "10:19", "national_flag", "high", "十一道红白横纹，蓝色方区内一颗白星。"),
    "luxembourg_1845": ("File:Flag of Luxembourg.svg", "1845-01-01", "9999-12-31", "3:5", "national_flag", "high", "红白浅蓝三道横带。"),
    "mexico_1893": ("File:Flag of Mexico (1893–1916).svg", "1893-01-01", "1916-09-20", "4:7", "state_flag", "high", "绿白红竖带，白带中央为1893年鹰蛇仙人掌国徽。"),
    "montenegro_1876": ("File:Flag of Montenegro (1860–1905).svg", "1860-01-01", "1905-01-01", "1:2", "princely_military_flag", "medium", "红地白边，中央双头鹰和王冠；资料所示为公国军政旗而非现代意义统一民用国旗。"),
    "morocco_plain_red": ("File:Flag of Morocco (1666–1915).svg", "1666-01-01", "1915-11-17", "2:3", "sultanate_flag", "high", "纯红旗面；绿色五芒星于1915年后加入。"),
    "muscat_oman_plain_red": ("File:Flag of Muscat.svg", "1650-01-01", "1970-01-01", "2:3", "sultanate_flag", "medium", "马斯喀特苏丹国纯红旗。"),
    "nepal_historical_pennants": ("File:Flag of Nepal (1856-c.1930).svg", "1856-01-01", "1930-01-01", "non_rectangular", "national_flag_reconstruction", "medium", "上下叠置双三角旗，深红底蓝边，日月具面部；现代矢量依据历史旗帜资料复原。"),
    "netherlands_tricolour": ("File:Flag of the Netherlands.svg", "before-1900", "9999-12-31", "2:3", "national_flag_continuous_design", "high", "红白蓝三道横带；此配色在1900年前已长期通行。"),
    "nicaragua_1896": ("File:Flag of Nicaragua (1896–1908).svg", "1896-09-05", "1908-08-27", "3:5", "national_flag", "high", "蓝白蓝横带，中央置大中美共和国时期国徽。"),
    "orange_free_state_1857": ("File:Flag of the Orange Free State.svg", "1856-02-28", "1902-05-31", "2:3", "national_flag", "high", "白橙相间七横带，左上荷兰三色旗方区。"),
    "ottoman_1844": ("File:Flag of the Ottoman Empire (1844–1922).svg", "1844-01-01", "1922-11-01", "2:3", "national_flag", "high", "红地白色新月与五角星。"),
    "paraguay_1842": ("File:Flag of Paraguay (1842–1954).svg", "1842-11-25", "1954-07-15", "2:3", "state_flag_obverse", "high", "红白蓝横带，正面中央共和国国徽；反面纹章另有不同。"),
    "peru_1884": ("File:Flag of Peru (1884–1950).svg", "1884-01-01", "1950-03-31", "2:3", "state_flag", "high", "红白红竖带，白带中央历史国徽。"),
    "portugal_1830": ("File:Flag of Portugal (1830–1910).svg", "1830-10-18", "1910-10-05", "2:3", "national_flag", "high", "蓝白竖分，中央王国盾徽与王冠。"),
    "qajar_persia_lion_sun": ("File:Tricolour Flag of Iran (1886).svg", "1886-01-01", "1907-08-05", "3:4", "state_flag_reported", "medium", "绿白红横带，白带中央持剑狮与太阳；依据1886年报告版本。"),
    "qing_1889": ("File:Flag of China (1889–1912).svg", "1889-01-01", "1912-02-12", "5:8", "national_flag", "high", "黄地青龙戏红珠，旗面采用长方形1889年定式。"),
    "romania_1867": ("File:Flag of Romania (1867–1948).svg", "1867-01-01", "1948-03-27", "2:3", "civil_flag", "high", "蓝黄红三道竖带；不含王室徽章的民用国旗式。"),
    "russia_1896": ("File:Flag of Russia (1896–1918).svg", "1896-05-07", "1918-04-13", "2:3", "national_flag", "high", "白蓝红三道横带。"),
    "serbia_1882": ("File:Flag of Serbia (1882–1918).svg", "1882-03-06", "1918-12-01", "2:3", "state_flag", "high", "红蓝白横带，靠旗杆侧置王室双头鹰国徽。"),
    "siam_white_elephant_1855": ("File:Flag of Siam (1855).svg", "1855-01-01", "1916-11-21", "2:3", "national_flag", "high", "红地中央白象面向旗杆。"),
    "spain_1875": ("File:Flag of Spain (1785–1873, 1875–1931).svg", "1875-01-01", "1931-04-14", "2:3", "national_flag", "high", "红黄红横带，黄带加宽，靠旗杆置王室国徽。"),
    "sweden_norway_union_1844": ("File:Swedish civil ensign (1844–1905).svg", "1844-06-20", "1905-11-01", "5:8", "union_component_civil_ensign", "high", "蓝地黄北欧十字，左上加瑞典—挪威联盟标；是瑞典侧民用旗，不代表两王国唯一共同国旗。"),
    "switzerland_1889": ("File:Flag of Switzerland.svg", "1889-12-12", "9999-12-31", "1:1", "national_flag", "high", "正方形红地，中央等臂白十字。"),
    "transvaal_vierkleur_1857": ("File:Flag of Transvaal.svg", "1857-01-06", "1902-05-31", "2:3", "national_flag", "high", "靠旗杆绿色竖带，余部红白蓝横带，称Vierkleur。"),
    "tunisia_1831": ("File:Flag of the Beylik of Tunis (1831–1881) and Tunisia (1881–1959).svg", "1831-01-01", "1959-06-30", "2:3", "national_flag", "high", "红地白圆盘，盘内红色新月和五角星。"),
    "uk_union_1801": ("File:Flag of the United Kingdom (3-5).svg", "1801-01-01", "9999-12-31", "3:5", "national_flag", "high", "圣乔治、圣安德鲁与圣帕特里克十字复合的联盟旗。"),
    "uruguay_1830": ("File:Flag of Uruguay.svg", "1830-07-11", "9999-12-31", "2:3", "national_flag", "high", "九道白蓝横纹，左上白色方区内五月太阳。"),
    "us_1896_45_star": ("File:Flag of the United States (1896–1908).svg", "1896-07-04", "1908-07-03", "10:19", "national_flag", "high", "十三道红白横纹，蓝色方区排列45颗白星。"),
    "venezuela_1863": ("File:Flag of Venezuela (1863–1905).svg", "1863-01-01", "1905-03-28", "2:3", "national_flag", "high", "黄蓝红横带，蓝带七颗白星呈圆弧排列。"),
    "zanzibar_1896": ("File:Flag of Zanzibar Under British Rule.svg", "1890-11-07", "1963-12-09", "2:3", "sultanate_flag", "medium", "英国保护时期苏丹国使用的纯红旗。"),
}


def _fetch_json(parameters: dict[str, str], retries: int = 6) -> dict[str, Any]:
    url = COMMONS_API + "?" + urllib.parse.urlencode(parameters)
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code != 429 or attempt + 1 >= retries:
                raise
            time.sleep(float(exc.headers.get("Retry-After", min(30, 2 ** (attempt + 1)))))
    raise RuntimeError("Commons API retry exhausted")


def _fetch_bytes(url: str, retries: int = 6) -> bytes:
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            if exc.code != 429 or attempt + 1 >= retries:
                raise
            time.sleep(float(exc.headers.get("Retry-After", min(30, 2 ** (attempt + 1)))))
    raise RuntimeError("asset download retry exhausted")


def _strip_html(value: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html.unescape(value))).strip()


def _query_files(titles: list[str]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for start in range(0, len(titles), 25):
        batch = titles[start:start + 25]
        document = _fetch_json({
            "action": "query", "titles": "|".join(batch), "redirects": "1",
            "prop": "imageinfo", "iiprop": "url|mime|size|sha1|extmetadata",
            "format": "json", "formatversion": "2", "origin": "*", "maxlag": "5",
        })
        normalized = {str(item.get("from", "")): str(item.get("to", "")) for item in document.get("query", {}).get("normalized", [])}
        redirects = {str(item.get("from", "")): str(item.get("to", "")) for item in document.get("query", {}).get("redirects", [])}
        pages = {str(page.get("title", "")): page for page in document.get("query", {}).get("pages", [])}
        for original in batch:
            resolved = redirects.get(normalized.get(original, original), normalized.get(original, original))
            page = pages.get(resolved)
            if page is None or page.get("missing") is not None or not page.get("imageinfo"):
                raise ValueError(f"Commons source not resolved: {original} -> {resolved}")
            result[original] = page
        time.sleep(0.4)
    return result


def _normalize_asset(payload: bytes, mime: str) -> bytes:
    if mime == "image/svg+xml":
        payload = cairosvg.svg2png(bytestring=payload, output_width=1152, output_height=768)
    with Image.open(io.BytesIO(payload)) as source:
        source.seek(0)
        image = source.convert("RGBA")
        image.thumbnail(CANVAS_SIZE, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
        canvas.alpha_composite(image, ((CANVAS_SIZE[0] - image.width) // 2, (CANVAS_SIZE[1] - image.height) // 2))
        output = io.BytesIO()
        canvas.save(output, format="PNG", optimize=True)
        return output.getvalue()


def _normalize_unit_flags(document: dict[str, Any]) -> None:
    for unit in document.get("units", []):
        code = int(unit.get("gwcode", -1))
        if code == 21:
            unit["flag_id"] = "uk_union_1801"
            unit["flag_mode"] = "controller_identification_flag"
            unit["flag_absence_reason"] = "纽芬兰殖民地1904年红船旗晚于快照日期；1900界面使用宗主国识别旗。"
        elif code == 395:
            unit["controller_id"] = "kingdom_of_denmark"
            unit["status"] = "dependency"
            unit["relationship"] = "controlled_territory"
            unit["flag_id"] = "denmark_dannebrog"
            unit["flag_mode"] = "controller_identification_flag"
            unit["flag_absence_reason"] = "冰岛本地旗帜在1900年尚未正式形成；使用丹麦宗主权识别旗。"
    document["policy"]["all_flag_records_source_backed_or_documented_absence"] = True


def _build_record(flag_id: str, spec: tuple[str, str, str, str, str, str, str], page: dict[str, Any]) -> tuple[dict[str, Any], str]:
    title, valid_from, valid_to, ratio, flag_type, confidence, heraldic_zh = spec
    info = page["imageinfo"][0]
    metadata = info.get("extmetadata", {})
    payload = _fetch_bytes(str(info["url"]))
    normalized = _normalize_asset(payload, str(info.get("mime", "")))
    asset_path = ASSET_DIR / f"{flag_id}.png"
    asset_path.write_bytes(normalized)
    license_name = str((metadata.get("LicenseShortName") or {}).get("value", ""))
    artist = _strip_html(str((metadata.get("Artist") or {}).get("value", "")))
    record = {
        "id": flag_id, "snapshot_date": TARGET_DATE, "valid_from": valid_from, "valid_to": valid_to,
        "ratio": ratio, "flag_type": flag_type, "confidence": confidence, "heraldic_zh": heraldic_zh,
        "render_mode": "source_asset", "asset_path": "res://" + asset_path.as_posix(),
        "asset_sha256": hashlib.sha256(normalized).hexdigest(), "source_title": str(page.get("title", title)),
        "source_page": str(info.get("descriptionurl", "")), "source_asset": str(info.get("url", "")),
        "source_mime": str(info.get("mime", "")), "source_width": int(info.get("width", 0)),
        "source_height": int(info.get("height", 0)), "source_license": license_name,
        "source_usage_terms": str((metadata.get("UsageTerms") or {}).get("value", "")),
        "source_artist": artist,
        "source_description": _strip_html(str((metadata.get("ImageDescription") or {}).get("value", ""))),
    }
    row = f"| `{flag_id}` | [{record['source_title']}]({record['source_page']}) | {license_name or 'see source page'} | {artist or 'see source page'} | {valid_from}—{valid_to} | {flag_type} |"
    return record, row


def main() -> int:
    units_document = json.loads(UNITS_PATH.read_text(encoding="utf-8"))
    _normalize_unit_flags(units_document)
    pages = _query_files([spec[0] for spec in FLAG_SPECS.values()])
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    records: dict[str, dict[str, Any]] = {
        "no_single_standard_flag": {
            "id": "no_single_standard_flag", "asset_path": "", "render_mode": "neutral_hatch",
            "valid_from": "", "valid_to": "", "ratio": "", "flag_type": "documented_absence",
            "confidence": "high", "source_title": "", "source_page": "", "source_asset": "",
            "source_license": "", "source_artist": "",
            "heraldic_zh": "该政治单元在1900年不存在可诚实归结为单一标准国旗的旗面；界面显示中性斜线而非伪旗。",
        }
    }
    rows: list[str] = []
    for flag_id, spec in sorted(FLAG_SPECS.items()):
        record, row = _build_record(flag_id, spec, pages[spec[0]])
        records[flag_id] = record
        rows.append(row)
        time.sleep(0.15)
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
    if any(str(unit.get("flag_id")) == "research_required" for unit in units_document.get("units", [])):
        raise ValueError("research_required flag remains")
    UNITS_PATH.write_text(json.dumps(units_document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    registry = {
        "schema_version": 1, "snapshot_date": TARGET_DATE,
        "policy": {"random_or_hash_flags_allowed": False, "controller_flag_is_explicitly_labeled": True,
                   "documented_absence_uses_neutral_rendering": True, "source_asset_required_for_rendered_flag": True},
        "record_count": len(records), "unit_flag_mode_counts": mode_counts, "records": records,
    }
    REGISTRY_PATH.write_text(json.dumps(registry, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    ATTRIBUTION_PATH.write_text(
        "# 1900 flag asset attribution\n\nAll assets below are normalized PNG derivatives of the cited Wikimedia Commons files. "
        "The original per-file license remains controlling. A controller flag is not claimed to be a local national flag.\n\n"
        "| Registry ID | Source file | License | Creator/attribution | Historical use | Type |\n|---|---|---|---|---|---|\n"
        + "\n".join(rows) + "\n", encoding="utf-8")
    print(json.dumps({"flags": len(records), "assets": len(FLAG_SPECS), "units": len(units_document.get("units", [])), "mode_counts": mode_counts}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
