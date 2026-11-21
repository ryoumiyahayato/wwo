"""Rebuild the dated observations from transcribed numerical cells."""
import csv
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
rows = []
with (HERE / "prefectures_otsu.csv").open(encoding="utf-8") as stream:
    for item in csv.DictReader(stream):
        national = item["label"] == "Japan"
        for date in ("1898-12-31", "1899-12-31", "1900-12-31", "1903-12-31"):
            survey = date[:4] in ("1898", "1903")
            page = int(item["page"])
            rows.append(dict(
                unit_id="japan_proper_otsu" if national else "jp_otsu_pref_" + item["label"].lower(),
                name=item["label"] + (" proper" if national else ""),
                source_name=item["printed_area"],
                parent_id="empire_of_japan" if national else "japan_proper_otsu",
                kind="territory" if national else "admin",
                population_value=int(item[date]), population_lower=None, population_upper=None, date=date,
                source_id="jp_cabinet_1909_resident_prefectures",
                locator=f"乙種道府縣現住人口, p. {page}, {item['printed_area']}, {date[:4]} (Meiji {int(date[:4])-1867}); https://dl.ndl.go.jp/pid/805921/1/{page//2+6}",
                definition="Resident Japanese population in Japan proper under the corrected household-registration series (乙種). Foreign residents outside the Japanese register are excluded. Counts published to hundreds.",
                method="Corrected survey-year register estimate (乙種)." if survey else "Cabinet Statistics Bureau intercensal register estimate (乙種).",
                mapping_status="partial_population_scope", quality="official_historical_estimate",
                region="Asia"))
for unit, label, value in (("total", "Japan proper (reporting areas)", 11561),
                            ("toyama", "Toyama", 0), ("okinawa", "Okinawa", 0)):
    row = dict(
        unit_id="jp_1899_foreign_" + unit, name=label + " (foreign residents)",
        parent_id="empire_of_japan" if unit == "total" else "jp_1899_foreign_total", kind="benchmark",
        population_value=value, population_lower=None, population_upper=None, date="1899-12-31",
        source_id="jp_cabinet_1900_yearbook_foreign", region="Asia",
        locator="Tables 28 and 29, printed pp. 79–81. " + (
            "Table 28, 總計, 男 8,419, 女 3,142, 合計 11,561, repeated in table 29." if unit == "total"
            else "Table 28 note, 富山縣及沖繩縣ニハ在留外國人ナシ."),
        definition="Reported foreign residents in Japan proper. No Kyoto prefectural return was available. Foreign legation and consulate personnel were excluded and tabulated separately.",
        method="published_year_end_administrative_return", quality="official_register",
        mapping_status="partial_population_scope")
    if unit == "total":
        row.update(male=8419, female=3142, missing_areas=["Kyoto"])
    rows.append(row)
with (HERE / "taiwan_register.csv").open(encoding="utf-8") as stream:
    for item in csv.DictReader(stream):
        national = item["label"] == "Taiwan"
        printed_page = 56 if national or item["label"] == "Penghu" else 55
        for year in (1898, 1899, 1900):
            date = f"{year}-12-31"
            exclusions = "Taitung's Hongtouyu (Orchid Island) was unsurveyed."
            if year == 1898:
                exclusions += " The published total also lacks the Donggang, Chaozhouzhuang and Ahou offices of Tainan and indigenous settlements in Yilan."
            rows.append(dict(
                unit_id="tw_register_total" if national else "tw_register_" + item["label"].lower(),
                name=item["label"] if national else item["label"] + " (colonial administrative district)",
                source_name=item["printed_area"],
                parent_id="empire_of_japan" if national else "tw_register_total",
                kind="territory" if national else "admin",
                population_value=int(item[date]), population_lower=None, population_upper=None, date=date,
                source_id="tw_governor_general_1900",
                locator=f"Table XVII, 現住戶口累年比較, printed p. {printed_page}, {item['printed_area']}, Meiji {year-1867}, 現住/人口/合計. Scope notes in table XVIII, p. 57.",
                definition="Reported registered residents in the colonial administration's 內地人 and 本島人 categories, both sexes. Troops stationed on Taiwan excluded. " + exclusions,
                method="published_year_end_administrative_return", mapping_status="partial_population_scope",
                quality="official_register", region="Asia"))
with (HERE / "taiwan_foreign.csv").open(encoding="utf-8") as stream:
    for item in csv.DictReader(stream):
        area = item["area"]
        rows.append(dict(
            unit_id="tw_foreign_" + area.lower(), name=area + " (foreign residents)",
            parent_id="empire_of_japan" if area == "Taiwan" else "tw_foreign_taiwan",
            corresponding_area="tw_register_total" if area == "Taiwan" else "tw_register_" + area.lower(),
            kind="benchmark", population_value=int(item["population"]), population_lower=None,
            population_upper=None, date=item["date"], source_id="tw_governor_general_1900",
            locator=f"Table XL, 本島在留外國人戶口, printed p. {item['printed_page']}, {item['printed_name']}, 人口合計. The note on p. 145 explicitly identifies the three zero districts.",
            definition="Foreign residents separately registered in Taiwan. Both sexes. Table XL is separate from the 內地人 and 本島人 classes in table XVII.",
            method="published_year_end_administrative_return", mapping_status="partial_population_scope",
            quality="official_register", region="Asia"))
with (HERE / "taiwan_urban.csv").open(encoding="utf-8") as stream:
    urban = list(csv.DictReader(stream))
for item in urban:
    district = item["area"] in ("Taipei Walled City", "Bangka", "Dadaocheng")
    rows.append(dict(
        unit_id="tw_urban_" + item["area"].lower().replace(" ", "_"), name=item["area"],
        parent_id="tw_urban_taipei_three_towns" if district else "tw_register_" + item["parent"].lower(),
        kind="admin" if district else "city", population_value=int(item["population"]),
        population_lower=None, population_upper=None, date="1900-12-31", source_id="tw_governor_general_1900",
        locator=f"Table XXXIV, printed p. {item['printed_page']}, {item['printed_name']}, 合計/現住人口/計.",
        definition="Selected named urban settlement in the register of 內地人 and 本島人. Distinct from the surrounding district and from later municipal limits. Stationed troops and separately tabulated foreign residents excluded.",
        method="published_year_end_administrative_return", mapping_status="historical_statistical_unit",
        quality="official_register", region="Asia"))
taipei = [o for o in rows if o["parent_id"] == "tw_urban_taipei_three_towns"]
rows.append(dict(
    unit_id="tw_urban_taipei_three_towns", name="Taipei (three historic urban settlements)",
    parent_id="tw_register_taipei", kind="city", population_value=sum(o["population_value"] for o in taipei),
    population_lower=None, population_upper=None, date="1900-12-31", source_id="tw_governor_general_1900",
    locator="Table XXXIV, p. 130, 臺北城內 + 艋舺 + 大稻埕, 合計/現住人口/計.",
    definition="Sum of the three separate historic urban settlements under the Taipei district office. Register classes 內地人 and 本島人. Stationed troops and separately tabulated foreign residents excluded.",
    method="sum_three_published_urban_counts", component_units=[o["unit_id"] for o in taipei],
    mapping_status="historical_statistical_unit", quality="derived_from_official_register", region="Asia"))
with (HERE / "observations.jsonl").open("w", encoding="utf-8", newline="\n") as output:
    for row in rows:
        print(json.dumps(row, ensure_ascii=False), file=output)
