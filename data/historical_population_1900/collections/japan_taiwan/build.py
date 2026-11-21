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
with (HERE / "observations.jsonl").open("w", encoding="utf-8", newline="\n") as output:
    for row in rows:
        print(json.dumps(row, ensure_ascii=False), file=output)
