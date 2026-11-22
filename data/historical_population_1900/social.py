"""Allocate source-supported resident marginals to exclusive opening pools."""

import csv
import json
import re
from collections import Counter, defaultdict
from itertools import chain
from pathlib import Path

from opening import AGRA_DISTRICT_BALANCE, AGRA_DISTRICT_SOURCE, BENGAL_DISTRICT_SOURCE, ENGLAND_WALES_OCCUPATION_REMAINDER, ITALIAN_CIVIL_STATUS_SCOPE, JAVA_MADOERA, OTTOMAN_REGISTRATION_SOURCE, SPANISH_CIVIL_STATUS_SCOPE
from opening import ROMANIA_CENSUS_SOURCE, apportion, egypt_age_sex_controls, opening_fraction, romanian_county_controls
from social_russia_marital import russian_marital_status
from social_us import united_states_structure
from social_india_princely import cochin_language, india_princely_residence, madras_states_religion, travancore_language


COLLECTIONS = Path(__file__).resolve().parent / "collections"
SHARE_METHOD = "Hold the observed territorial shares at opening and allocate persons by integer largest remainders."
RUSSIA_DATE = "1897-02-09"
PROVINCE_ALIASES = {
    "бессарабская": "бесарабская",
    "донского войска": "область войска донского",
    "оренбургская": "оренбургcкая",
    "калецкая": "келецкая",
    "карсская": "карская",
    "о-в сахалин": "остров сахалин",
    "cемипалатинская": "семипалатинская",
    "сырь-дарьинская": "сырдарьинская",
}
INDIA_DATE = "1901-03-01"
INDIA_TABLES = {
    "1": ("residence", "india_1901_census_towns_and_rural", "india_statistical_abstract_1905",
          ("Urban", "Rural"), "The census assigns residents to towns and rural areas using its contemporary definitions."),
    "7": ("religion", "india_1901_reported_religion", "india_1901_abstract_religion",
          ("Hindus", "Sikhs", "Jains", "Buddhists", "Parsis", "Muhammadans", "Christians", "Jews", "Animistic"),
          "Census religion, using historical source labels. The combined column for minor religions and religions not returned is unassigned."),
    "11": ("marital_status", "india_1901_reported_civil_condition", "india_1901_abstract_civil_condition",
           ("Unmarried", "Married", "Widowed"), "Census civil condition for persons of both sexes and all ages."),
    "16": ("literacy", "india_1901_reported_literacy", "india_1901_abstract_literacy",
           ("Illiterate", "Literate"), "All-age census literacy status. The English and vernacular detail is outside this partition."),
}
CANADA_DATE = "1901-03-31"
CANADA_TABLES = {
    "residence": ("canada_1901_incorporated_places", "ca_fourth_census_table_iv_residence",
                  "Urban residents are persons in incorporated villages, towns and cities, under the 1901 census classification."),
    "religion": ("canada_1901_five_principal_denominations", "ca_fourth_census_table_viii_religion",
                 "The five principal denominations are assigned. The balance includes other denominations, no religion, and religion unspecified."),
}


def distribution(opening, *, classification, source, date, observed_unit, scope,
                 locator, total, observed_counts, unknown, definition, method=SHARE_METHOD):
    if total <= 0 or unknown < 0 or any(count < 0 for count in observed_counts.values()):
        raise ValueError(f"{observed_unit}: invalid {classification} counts")
    if sum(observed_counts.values()) + unknown != total:
        raise ValueError(f"{observed_unit}: {classification} does not close to {total}")

    # A tagged key keeps unknown distinct from every source label during apportionment.
    source_cells = [((False, name), count) for name, count in observed_counts.items()]
    source_cells.append(((True, ""), unknown))
    floors = []
    for key, count in source_cells:
        floor, remainder = divmod(opening * count, total)
        floors.append((-remainder, key, floor))
    unallocated = opening - sum(floor for _, _, floor in floors)
    allocated = {
        key: floor + (rank < unallocated)
        for rank, (_, key, floor) in enumerate(sorted(floors))
    }
    return dict(
        classification_id=classification, source_ids=[source], observed_date=date,
        observed_unit_id=observed_unit, observed_scope=scope, locator=locator,
        observed_total=total, observed_unknown=unknown, method=method,
        definition=definition,
        counts={name: count for (is_unknown, name), count in sorted(allocated.items())
                if not is_unknown and count},
        unknown=allocated[(True, "")],
    )


def province_name(value):
    return re.sub(r"\s+(губерния|область|обл\.?)$", "", value.casefold().strip())


def russian_district_residence(path, districts, provinces):
    if not districts:
        return
    tables = defaultdict(list)
    for unit in districts:
        _, table, row = unit["source_unit_ids"][0].split("_")
        tables[table].append((int(row[1:]), unit))
    facts = defaultdict(dict)
    with (path / "census_facts.csv").open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            if row["table"] in tables:
                facts[row["table"]][int(row["row"])] = row
    columns = ("both", "male", "female")
    for table, units in tables.items():
        rows = facts[table]
        ordered = sorted(units)
        next_rows = [number for number, _ in ordered[1:]] + [max(rows) + 1]
        sums = {name: Counter() for name in ("city", "outside")}
        for (start, unit), end in zip(ordered, next_rows, strict=True):
            total, outside = rows[start], rows[end - 1]
            cities = [rows[number] for number in range(start + 1, end - 1)]
            if (not outside["label"].endswith(("без города", "без городов")) or not cities
                    or any(" - г." not in city["label"] for city in cities)):
                raise ValueError(f"Unexpected census residence rows for {unit['unit_id']}")
            for key in columns:
                urban = sum(int(city[key]) for city in cities)
                rural = int(outside[key])
                if urban + rural != int(total[key]) or (key == "both" and int(total[key]) != unit["observed_value"]):
                    raise ValueError(f"Non-closing census residence rows for {unit['unit_id']}")
                sums["city"][key] += urban
                sums["outside"][key] += rural
            province = provinces[f"ru1897_{table}"]
            yield unit["unit_id"], "residence", distribution(
                unit["population_value"], classification="russia_1897_administrative_residence",
                source="russia_first_census", date=RUSSIA_DATE, observed_unit=unit["source_unit_ids"][0],
                scope=f"{province['name']}, {unit['name']}",
                locator=f"rus_gub_97.php?reg={table}, rows {start}–{end - 1}",
                total=int(total["both"]), unknown=0,
                observed_counts={"Census cities": int(total["both"]) - int(outside["both"]),
                                 "Outside census cities": int(outside["both"])},
                definition="Persons in census cities and persons outside those cities, under the 1897 administrative classification.",
            )
        if any(sums[name][key] != int(rows[number][key]) for name, number in (("city", 4), ("outside", 5))
               for key in columns):
            raise ValueError(f"Russian district residence totals differ from province table {table}")


def russian_structure(pools):
    path = COLLECTIONS / "russia"
    provinces = {}
    for line in (path / "observations.jsonl").read_text(encoding="utf8").splitlines():
        row = json.loads(line)
        if row["source_id"] == "russia_first_census" and row.get("parent_id") == "ru_census_1897_ex_finland":
            provinces[province_name(row["name"])] = row
    provinces_by_id = {row["unit_id"]: row for row in provinces.values()}
    yield from russian_literacy(pools, provinces_by_id)
    yield from russian_marital_status(pools, provinces_by_id, distribution)
    districts = [unit for unit in pools.values() if "district_boundary_source" in unit]
    district_parents = {unit["statistical_parent"] for unit in districts}
    yield from russian_district_residence(path, districts, provinces_by_id)
    blocks = defaultdict(list)
    with (path / "structure.csv").open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            table = row["source_table"]
            parameter = row["region_parameter"]
            if table != "rus_age_97" and int(parameter) >= 24:
                blocks[table, parameter, row["published_scope"]].append(row)

    for (table, parameter, scope), rows in blocks.items():
        key = province_name(scope)
        province = provinces.get(PROVINCE_ALIASES.get(key, key))
        if province is None:
            continue  # Regional table headers are aggregates, outside the provincial pools.
        pool_id = province.get("wwo_id") or province["unit_id"]
        if pool_id not in pools:
            continue
        categories, unknown, dimension, classification, definition = russian_cells(table, rows)
        total = int(rows[-1]["both"])
        if total != province["population_value"]:
            raise ValueError(f"{pool_id}: {table} does not match the provincial census total")
        yield pool_id, dimension, distribution(
            pools[pool_id]["population_value"], classification=classification, source=table,
            date=RUSSIA_DATE, observed_unit=province["unit_id"], scope=scope,
            locator=f"{table}.php?reg={parameter}, rows {rows[0]['row']}–{rows[-1]['row']}",
            total=total, observed_counts=categories, unknown=unknown, definition=definition,
        )

    for province in provinces.values():
        pool_id = province.get("wwo_id") or province["unit_id"]
        if pool_id not in pools or pool_id in district_parents:
            continue
        (city_label, city_count), (other_label, other_count) = province["published_components"]
        if province["unit_id"] == "ru1897_77":
            continue  # Sakhalin distinguishes settlements and posts from other residents.
        locator = f"{province['locator']}; {city_label}; {other_label}"
        if province["unit_id"] == "ru1897_26":
            # The digitization repeats the all-province label on the city and rural rows.
            with (path / "census_facts.csv").open(encoding="utf8", newline="") as stream:
                cities = [row for row in csv.DictReader(stream)
                          if row["table"] == "26" and " - г. " in row["label"]]
            if not cities or sum(int(row["both"]) for row in cities) != city_count:
                raise ValueError("Novgorod city detail does not match its aggregate cell")
            locator = f"{province['locator']}; rows 4–5, city count cross-checked against the individual city rows"
        elif (city_count and other_count and
              ("город" not in city_label.casefold().split(" - ")[-1] or
               "город" not in other_label.casefold().split(" - ")[-1])):
            continue
        yield pool_id, "residence", distribution(
            pools[pool_id]["population_value"], classification="russia_1897_administrative_residence",
            source="russia_first_census", date=RUSSIA_DATE, observed_unit=province["unit_id"],
            scope=province["name"], locator=locator,
            total=province["population_value"], unknown=0,
            observed_counts={"Census cities": city_count, "Outside census cities": other_count},
            definition="Persons in census cities and persons outside those cities, under the 1897 administrative classification.",
        )


def russian_literacy(pools, provinces):
    path = COLLECTIONS / "russia_literacy_1897" / "literacy.csv"
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            province = provinces[row["unit_id"]]
            pool_id = province.get("wwo_id") or province["unit_id"]
            if pool_id not in pools:
                continue
            total_by_sex = {sex: int(row[f"population_{sex}"]) for sex in ("male", "female")}
            if total_by_sex != province["sex"]:
                raise ValueError(f"{pool_id}: the literacy and provincial census totals differ")
            literate_by_sex = {sex: int(row[f"literate_{sex}"]) for sex in total_by_sex}
            if any(not 0 <= literate_by_sex[sex] <= total_by_sex[sex] for sex in total_by_sex):
                raise ValueError(f"{pool_id}: a literacy count is outside its census total")
            total = sum(total_by_sex.values())
            literate = sum(literate_by_sex.values())
            yield pool_id, "literacy", distribution(
                pools[pool_id]["population_value"], classification="russia_1897_reported_reading",
                source=row["source_id"], date=RUSSIA_DATE, observed_unit=province["unit_id"],
                scope=province["name"], locator=row["locator"], total=total,
                observed_counts={"Able to read": literate, "Not recorded as able to read": total - literate},
                unknown=0,
                definition=("All-age reading ability in the 1897 census, including children and persons of unknown age. "
                            "The table enumerates readers within the population and gives no separate count of unanswered literacy questions."),
            )


def russian_cells(table, rows):
    if table == "rus_rel_97":
        if rows[-1]["category"] != "ИТОГО":
            raise ValueError("Russian religion table is missing its total")
        return ({row["category"]: int(row["both"]) for row in rows[:-1]}, 0,
                "religion", "russia_1897_reported_confession", "Confession reported in the census.")
    if table == "rus_lan_97":
        if [row["category"] for row in rows[-2:]] != ["Лица, не указавшие родного языка", "ИТОГО"]:
            raise ValueError("Russian mother-tongue table is missing its controls")
        counts = {
            " / ".join(row[key] for key in ("category", "subcategory", "dialect") if row[key]): int(row["both"])
            for row in rows[:-2] if row["subcategory"] != "Итого"
        }
        return (counts, int(rows[-2]["both"]), "language", "russia_1897_reported_mother_tongue",
                "Reported mother tongue. Nested census labels are retained and the overlapping Russian subtotal is omitted.")
    if table == "rus_sos_97":
        tail = ["Лица, не указавшие сословия", "ИТОГО русских подданных",
                "Иностранные подданные", "ВСЕГО русских и иностранных подданных"]
        if [row["category"] for row in rows[-4:]] != tail:
            raise ValueError("Russian legal estate table is missing its controls")
        counts = {row["category"]: int(row["both"]) for row in rows[:-4]}
        unreported = int(rows[-4]["both"])
        if sum(counts.values()) + unreported != int(rows[-3]["both"]):
            raise ValueError("Russian legal estates do not close to the Russian-subject subtotal")
        unknown = unreported + int(rows[-2]["both"])
        return (counts, unknown, "legal_estate", "russia_1897_reported_legal_estate",
                "Legal estates of Russian subjects. Unknown includes subjects without a stated estate and foreign subjects outside the estate universe.")
    raise ValueError(f"Unrecognized Russian social table: {table}")


def india_structure(pools, version):
    tables = json.loads((COLLECTIONS / "india_social_1901" / "census.json").read_text(encoding="utf8"))
    for table, rows in tables.items():
        dimension, classification, source, labels, definition = INDIA_TABLES[table]
        for row in rows:
            if version < row.get("opening_from_version", 1):
                continue
            pool_id = row["unit_id"]
            if table == "1" and pool_id == "raj_central_india_agency" and "raj_gwalior_state" in pools:
                continue
            if table == "7" and pool_id == "raj_madras_states" and "raj_travancore_state" in pools:
                continue
            pool = pools.get(pool_id)
            if not pool or pool.get("endpoint_values", [None])[-1] != row["total"]:
                continue
            locator = f"Table {table}, workbook rows {', '.join(map(str, row['sheet_rows']))}"
            yield pool_id, dimension, distribution(
                pool["population_value"], classification=classification, source=source,
                date=INDIA_DATE, observed_unit=pool_id, scope=row["scope"], locator=locator,
                total=row["total"], observed_counts=dict(zip(labels, row["counts"], strict=True)),
                unknown=row["unknown"], definition=definition,
            )


def india_language(pools):
    rows_by_pool = defaultdict(list)
    path = COLLECTIONS / "india_social_1901" / "india_province_language_1901.csv"
    with path.open(encoding="utf8", newline="") as source:
        for row in csv.DictReader(source):
            rows_by_pool[row["unit_id"]].append(row)
    for pool_id, rows in rows_by_pool.items():
        pool = pools[pool_id]
        row = rows[0]
        observed = int(row["observed_total"])
        endpoint = int(row["opening_endpoint_total"])
        mismatch = int(row["opening_endpoint_scope_unknown"])
        counts = {entry["language"]: int(entry["count"]) for entry in rows}
        if (len(counts) != len(rows) or sum(counts.values()) != int(row["returned_total"])
                or row["observed_date"] != INDIA_DATE or observed + mismatch != endpoint
                or endpoint != pool["endpoint_values"][-1]):
            raise ValueError(f"{pool_id}: language observations do not match the census scope")
        balance = 0
        method = SHARE_METHOD
        if mismatch:
            discrepancy = pools[AGRA_DISTRICT_BALANCE]
            if discrepancy["statistical_parent"] != pool_id or discrepancy["endpoint_values"][-1] != mismatch:
                raise ValueError(f"{pool_id}: unmatched geography in the language denominator")
            balance = discrepancy["population_value"]
            method += f" Keep the {balance} people of the separate boundary comparison unassigned."
        result = distribution(
            pool["population_value"] - balance, classification="india_1901_reported_usual_language",
            source="india_1901_abstract_language", date=INDIA_DATE, observed_unit=pool_id,
            scope=row["observed_scope"], locator=row["locator"], total=observed,
            observed_counts=counts, unknown=int(row["observed_unknown"]), method=method,
            definition="Language ordinarily used. The source's pooled Other category varies by territory.",
        )
        result["unknown"] += balance
        yield pool_id, "language", result


def india_occupation(pools, version):
    directory = COLLECTIONS / "india_occupation_1901"
    filename = "occupation_orders_complete.json" if version >= 30 else "occupation_orders.json"
    rows = json.loads((directory / filename).read_text(encoding="utf8"))
    if version >= 31:
        rows.extend(json.loads((directory / "occupation_orders_additional.json").read_text(encoding="utf8")))
    for row in rows:
        pool_id = row["unit_id"]
        pool = pools[pool_id]
        total = row["observed_total"]
        mismatch = row.get("opening_endpoint_scope_unknown", 0)
        if (pool["endpoint_values"][-1] != total + mismatch or row["observed_date"] != INDIA_DATE
                or pool.get("source_dates", [INDIA_DATE])[-1] != INDIA_DATE):
            raise ValueError(f"{pool_id}: the occupation and opening population controls use different census scopes")
        balance = 0
        method = SHARE_METHOD
        if mismatch:
            discrepancy = pools[AGRA_DISTRICT_BALANCE]
            if discrepancy["statistical_parent"] != pool_id or discrepancy["endpoint_values"][-1] != mismatch:
                raise ValueError(f"{pool_id}: unmatched geography in the occupation denominator")
            balance = discrepancy["population_value"]
            method += f" Keep the {balance} people of the separate boundary comparison unassigned."
        if "census_table_controls" in row:
            controls = row["census_table_controls"]
            workers = controls["actual_workers_column_total"]
            if (total != controls["total_supported"] or workers + controls["dependents"] != total
                    or sum(row["observed_counts"].values())
                    + controls["XXIII_Indefinite_and_Disreputable_Occupations"]
                    + controls["XXIV_Independent"] != workers):
                raise ValueError(f"{pool_id}: occupation orders, dependants and residents do not reconcile")
        source, = row["source_ids"]
        result = distribution(
            pool["population_value"] - balance, classification=row["classification_id"], source=source,
            date=row["observed_date"], observed_unit=row["observed_unit_id"], scope=row["observed_scope"],
            locator=row["locator"], total=total, observed_counts=row["observed_counts"],
            unknown=row["observed_unknown"], definition=row["definition"], method=method,
        )
        result["unknown"] += balance
        yield pool_id, "occupation", result


def canada_structure(pools):
    tables = json.loads((COLLECTIONS / "canada_social_1901" / "census.json").read_text(encoding="utf8"))
    for dimension, rows in tables.items():
        classification, source, definition = CANADA_TABLES[dimension]
        for row in rows:
            pool_id = row["unit_id"]
            pool = pools.get(pool_id)
            if not pool or pool.get("endpoint_values", [None])[-1] != row["total"]:
                continue
            yield pool_id, dimension, distribution(
                pool["population_value"], classification=classification, source=source, date=CANADA_DATE,
                observed_unit=pool_id, scope=row["scope"], locator=row["locator"], total=row["total"],
                observed_counts=row["counts"], unknown=row["unknown"], definition=definition,
            )


def canada_occupation(pools):
    path = COLLECTIONS / "canada_social_1901" / "occupation_1901_table_i.csv"
    with path.open(encoding="utf8", newline="") as stream:
        national, *rows = csv.DictReader(stream)
    classes = [label for label in national if label.endswith(" class")]
    excluded = "Non-productive class"
    for row in [national, *rows]:
        if sum(int(row[label]) for label in classes) != int(row["reported_total"]):
            raise ValueError(f"Canadian occupation classes do not close for {row['scope']}")
    if any(sum(int(row[label]) for row in rows) != int(national[label]) for label in classes):
        raise ValueError("Canadian occupation regions do not sum to Table I national counts")

    combined = "ca_quebec_and_unorganized_territories"
    source = "ca_fourth_census_1901_occupation_bulletin_xi"
    regions = defaultdict(list)
    for row in rows:
        scope = row["observed_unit_id"]
        regions[combined if scope in {"ca_quebec", "ca_yukon"} else scope].append(row)
    population_missing = int(national["observed_population"]) - sum(int(row["observed_population"]) for row in rows)
    if (population_missing < 0
            or sum(pools[scope]["endpoint_values"][-1] for scope in regions) != int(national["observed_population"])):
        raise ValueError("Canadian occupation scopes differ from the national opening census control")
    for scope, entries in regions.items():
        pool = pools[scope]
        total = sum(int(row["observed_population"]) for row in entries)
        definition = ("Recorded own occupation across the nine occupational classes. Residents without a recorded "
                      "occupation and residents in the chiefly retired Non-productive class remain unassigned.")
        if scope == combined:
            total += population_missing
            definition += " Quebec and Yukon are counted. The remaining unorganized territories are unassigned."
        if total != pool["endpoint_values"][-1]:
            raise ValueError(f"Canadian occupation and population controls differ for {scope}")
        counts = {label: sum(int(row[label]) for row in entries) for label in classes if label != excluded}
        pages = ", ".join(sorted({row["printed_page"] for row in entries}))
        margin = distribution(
            pool["population_value"], classification="canada_1901_recorded_occupation_classes",
            source=source, date=CANADA_DATE, observed_unit=scope, scope=pool["name"],
            locator=f"Bulletin XI, Table I, printed p. {pages}; Volume I, Table I for resident denominators.",
            total=total, observed_counts=counts, unknown=total - sum(counts.values()),
            definition=definition,
        )
        margin["source_ids"].append("ca_census_1901_vol1_table1")
        yield scope, "occupation", margin


def netherlands_structure(pools):
    census_date = "1900-01-01"
    method = "Use the census counts at the midnight opening without apportionment across territories."
    marital_source = "nl_cbs_census_1899_age_marital"
    marital_labels = {
        "Ongehuwd_2": "Unmarried",
        "TeZamenWonende_3": "Married and not legally separated",
        "GescheidenVanTafelEnBed_4": "Legally separated",
        "InWeduwenstaat_5": "Widowed",
        "GescheidenVanEcht_6": "Divorced",
    }
    with (COLLECTIONS / "netherlands_census_1899" / "cbs_7379vt.csv").open(encoding="utf8", newline="") as source:
        marital_rows = defaultdict(list)
        gelderland_women = []
        for row in csv.DictReader(source):
            age = row["Leeftijden"]
            if age == "LFTOTL" and row["Geslacht"] in {"GSLMAN", "GSLVRW"}:
                marital_rows[row["Gebieden"]].append(row)
            elif (row["Gebieden"] == "PV2500" and row["Geslacht"] == "GSLVRW"
                  and (age.startswith("LFJ") or age == "LFONBK")):
                gelderland_women.append(row)
    religion_labels = {
        "NederduitschHervormden_2": "Dutch Reformed",
        "WaalschHervormden_3": "Walloon Reformed",
        "Remonstranten_4": "Remonstrant",
        "ChristelijkGereformeerdenAfgesch_5": "Christian Reformed (Seceded)",
        "Doopsgezinden_6": "Mennonite",
        "EvangelischLutherschen_7": "Evangelical Lutheran",
        "HersteldLutherschen_8": "Restored Lutheran",
        "BehoorendeTotDeGereformeerdeKerken_9": "Reformed Churches in the Netherlands",
        "RoomschKatholieken_10": "Roman Catholic",
        "OudRoomschen_11": "Old Catholic",
        "NederlandscheIsraelieten_12": "Dutch Israelite",
        "PortugeescheIsraelieten_13": "Portuguese Israelite",
        "OverigeKerkelijkeGezindten_14": "Other denomination",
        "GeenKerkelijkeGezindte_15": "No denomination",
    }
    with (COLLECTIONS / "netherlands_religion_1899" / "religion.csv").open(encoding="utf8", newline="") as source:
        religion_rows = defaultdict(list)
        for row in csv.DictReader(source):
            religion_rows[row["Gebieden"]].append(row)

    for pool_id, pool in pools.items():
        if not pool_id.startswith("nl1899_pv"):
            continue
        area = pool_id.removeprefix("nl1899_").upper()
        total = pool["population_value"]
        civil = marital_rows[area]
        religion = religion_rows[area]
        if ({row["Geslacht"] for row in civil} != {"GSLMAN", "GSLVRW"}
                or len(civil) != 2 or sum(int(row["Totaal_1"]) for row in civil) != total
                or {row["Geslacht"] for row in religion} != {"GSLMAN", "GSLVRW"}
                or len(religion) != 2
                or sum(int(row["TotaleBevolking_1"]) for row in religion) != total):
            raise ValueError(f"{pool_id}: Dutch social census returns do not match the opening province")
        marital_counts = Counter()
        marital_unknown = 0
        civil_method = method
        for row in civil:
            counts = {label: int(row[key]) for key, label in marital_labels.items()}
            unknown = int(row["BurgerlijkeStaatOnbekend_7"])
            sex_total = int(row["Totaal_1"])
            if area == "PV2500" and row["Geslacht"] == "GSLVRW":
                keys = (*marital_labels, "BurgerlijkeStaatOnbekend_7")
                detail = {key: sum(int(band[key]) for band in gelderland_women) for key in keys}
                if (sum(detail.values()) != sex_total or int(row["TeZamenWonende_3"]) - detail["TeZamenWonende_3"] != 1
                        or any(int(row[key]) != detail[key] for key in keys if key != "TeZamenWonende_3")):
                    raise ValueError("Gelderland's civil condition discrepancy is not explained by the age detail")
                counts = {label: detail[key] for key, label in marital_labels.items()}
                civil_method += (" For Gelderland women, add the mutually exclusive single-year and unstated-age "
                                 "married counts, which close to the female population. The published all-age cell is one higher.")
            if sum(counts.values()) + unknown != sex_total:
                raise ValueError(f"{pool_id}: unreconciled civil condition values")
            marital_counts.update(counts)
            marital_unknown += unknown
        civil_pages = ", ".join(sorted({row["Pagina_8"] for row in civil}))
        yield pool_id, "marital_status", distribution(
            total, classification="netherlands_1899_civil_condition", source=marital_source, date=census_date,
            observed_unit=pool_id, scope=pool["name"], locator=f"CBS Table 7379vt, printed page {civil_pages}",
            total=total, observed_counts=marital_counts, unknown=marital_unknown,
            definition="Civil condition of usual residents. Legal separation was counted separately from divorce.",
            method=civil_method,
        )
        counts = Counter()
        for row in religion:
            counts.update({label: int(row[key]) for key, label in religion_labels.items()})
        pages = ", ".join(sorted({row["Pagina_17"] for row in religion}))
        yield pool_id, "religion", distribution(
            total, classification="netherlands_1899_census_denomination", source="nl_cbs_1899_religion",
            date=census_date, observed_unit=pool_id, scope=pool["name"], locator=f"CBS Table 7378vt, printed page {pages}",
            total=total, observed_counts=counts,
            unknown=sum(int(row["KerkelijkeGezindteOnbekend_16"]) for row in religion),
            definition="Usual residents by reported denomination. No denomination is a reported category.",
            method=method,
        )


def netherlands_occupation(pools):
    labels = {
        "39980000S": "Industrial occupations",
        "40980000S": "Agriculture",
        "41980000S": "Fishing and hunting",
        "42980000S": "Trade and transport",
        "43980000S": "Other occupations",
        "44980000S": "Casual labourers",
    }
    rows = defaultdict(dict)
    with (COLLECTIONS / "netherlands_occupation_1899" / "occupation.csv").open(encoding="utf8", newline="") as source:
        for row in csv.DictReader(source):
            code = row["Beroepen"]
            if code in labels:
                rows[row["Gebieden"], code][row["Geslacht"]] = row

    for pool_id, pool in pools.items():
        if not pool_id.startswith("nl1899_pv"):
            continue
        area = pool_id.removeprefix("nl1899_").upper()
        counts = {}
        pages = set()
        for code, label in labels.items():
            entries = rows[area, code]
            observed = {
                sex: int(entry["Ongehuwd_1"] or 0) + int(entry["Gehuwd_2"] or 0)
                for sex, entry in entries.items()
            }
            both = observed["GSLTOT"]
            sex_sum = observed["GSLMAN"] + observed["GSLVRW"]
            if both != sex_sum and (area, code, both - sex_sum) != ("PV2800", "42980000S", 1):
                raise ValueError(f"{pool_id}: inconsistent CBS occupation counts for {code}")
            counts[label] = sex_sum
            pages.update(entry["Pagina_33"] for entry in entries.values())
        total = pool["population_value"]
        marginal = distribution(
            total, classification="netherlands_1899_principal_occupation_groups", source="nl_cbs_1899_occupation",
            date="1900-01-01", observed_unit=pool_id, scope=pool["name"],
            locator=f"CBS Table 7381bt, printed pages {', '.join(sorted(pages))}",
            total=total, observed_counts=counts, unknown=total - sum(counts.values()),
            definition=("People reported under the six mutually exclusive occupation groups covering 1899 classes 1–33. "
                        "Pensioners, people without an occupation, and occupation not reported are in the unassigned remainder."),
            method=("Use each province's published occupation counts at the midnight opening. The denominator is the "
                    "matching general census province. Use the sum of the separately reported sexes for South Holland "
                    "trade and transport, where the combined cell is one higher. That person remains unassigned."),
        )
        marginal["source_ids"].append("nl_cbs_census_1899_age_marital")
        yield pool_id, "occupation", marginal


def england_wales_occupation(pools):
    anglesey_id = "administrative_region:gb_historic_anglesey"
    remainder_id = ENGLAND_WALES_OCCUPATION_REMAINDER
    national_source = "england_wales_1901_occupation_orders"
    county_source = "anglesey_1901_occupation_orders"
    path = COLLECTIONS / "england_wales_occupation_1901" / "occupation.csv"
    with path.open(encoding="utf8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    classifications = {}
    unknowns = {}
    for key, control in (("england_wales", 14_328_727), ("anglesey", 21_606)):
        counts = {row["order_label"]: int(row[key]) for row in rows
                  if row["order_id"] not in ("XXIII", "UNKNOWN")}
        if len(counts) != 22 or sum(counts.values()) != control:
            raise ValueError(f"{key}: named occupation orders do not close to the census total")
        classifications[key] = counts
        unknowns[key] = sum(int(row[key]) for row in rows if row["order_id"] in ("XXIII", "UNKNOWN"))
    national = classifications["england_wales"]
    local = classifications["anglesey"]
    if sum(national.values()) + unknowns["england_wales"] != sum(
        pools[key]["endpoint_values"][-1] for key in (anglesey_id, remainder_id)
    ):
        raise ValueError("England and Wales occupation and opening controls cover different populations")
    remaining = {label: count - local[label] for label, count in national.items()}
    definition = ("The 22 named occupation orders cover persons aged ten and over, including the temporarily "
                  "unemployed who reported their usual occupation. Children under ten and persons without "
                  "a specified occupation or unoccupied are unassigned.")
    for unit_id, source, observed_unit, scope, locator, counts, unknown in (
        (anglesey_id, county_source, "uk_ancient_area_anglesey", "Ancient county of Anglesey",
         "County of Anglesey, Table XXXII, printed pp. 23–26", local, unknowns["anglesey"]),
        (remainder_id, national_source, "uk_england_wales", "England and Wales excluding Anglesey",
         "Summary Tables XXXV pp. 186–201 less Anglesey Table XXXII pp. 23–26",
         remaining, unknowns["england_wales"] - unknowns["anglesey"]),
    ):
        unit = pools[unit_id]
        margin = distribution(
            unit["population_value"], classification=national_source, source=source,
            date="1901-03-31", observed_unit=observed_unit, scope=scope, locator=locator,
            total=unit["endpoint_values"][-1], observed_counts=counts, unknown=unknown,
            definition=definition,
        )
        if unit_id == remainder_id:
            margin["source_ids"].append(county_source)
            margin["method"] = "Subtract the same-category Anglesey census counts from England and Wales. " + SHARE_METHOD
        yield unit_id, "occupation", margin


def england_wales_housing(pools):
    with (COLLECTIONS / "england_wales_habitations" / "overcrowding.csv").open(encoding="utf8", newline="") as table:
        for row in csv.DictReader(table):
            pool_id = "administrative_region:gb_historic_" + row["county"]
            pool = pools[pool_id]
            total = int(row["residents"])
            if row["administrative_acres"] != row["ancient_acres"] or pool["endpoint_values"][-1] != total:
                raise ValueError(f"{pool_id}: the housing and opening population controls use different county scopes")
            crowded = sum(int(row[column]) for column in ("crowded", "crowded_cardiff", "crowded_swansea"))
            margin = distribution(
                pool["population_value"], classification="england_wales_1901_small_tenement_overcrowding",
                source="england_wales_1901_county_overcrowding", date="1901-03-31",
                observed_unit=pool["source_unit_ids"][0], scope=pool["name"],
                locator=f"General Report table 42, p. {row['housing_page']}; Summary Tables table II, p. {row['population_page']}",
                total=total, observed_counts={"Over two persons per room in a one- to four-room tenement": crowded,
                                              "Outside the published overcrowding count": total - crowded},
                unknown=0,
                definition=("The published count covers one- to four-room tenements. The complement is all other "
                            "residents, including residents of larger dwellings with unknown crowding. For Glamorgan, "
                            "the county count includes the separate Cardiff and Swansea county borough rows."),
            )
            margin["source_ids"].append("england_wales_summary_tables_1901")
            yield pool_id, "housing", margin


AUSTRIAN_RELIGION_COLUMNS = {
    "roman_catholic": "Roman Catholic", "greek_united": "Greek United Catholic",
    "armenian_united": "Armenian United Catholic", "old_catholic": "Old Catholic",
    "greek_orthodox": "Greek Orthodox", "armenian_oriental": "Armenian Oriental",
    "evangelical_augsburg_confession": "Evangelical, Augsburg Confession",
    "evangelical_helvetic_confession": "Evangelical, Helvetic Confession",
    "moravian_brethren": "Moravian Brethren", "anglican": "Anglican", "mennonite": "Mennonite",
    "unitarian": "Unitarian", "lipovan": "Lipovan", "jewish": "Jewish", "muslim": "Muslim",
    "other_confession": "Other confession", "no_confession": "No confession",
}
AUSTRIAN_MARITAL_COLUMNS = {
    "never_married": "Never married", "married": "Married", "widowed": "Widowed",
    "divorced": "Divorced", "separated": "Separated",
}
AUSTRIAN_LANGUAGE_COLUMNS = {
    "german": "German", "bohemian_moravian_slovak": "Bohemian–Moravian–Slovak", "polish": "Polish",
    "ruthenian": "Ruthenian", "slovene": "Slovene", "serbo_croatian": "Serbo-Croatian",
    "italian_ladin": "Italian–Ladin", "romanian": "Romanian", "hungarian": "Hungarian",
}
AUSTRIAN_LITERACY_COLUMNS = {"read_and_write": "Read and write", "read_only": "Read only", "illiterate": "Illiterate"}
AUSTRIAN_LOCALITY_COLUMNS = {
    "population_at_most_500": "500 or fewer", "population_501_to_2000": "501–2,000",
    "population_2001_to_5000": "2,001–5,000", "population_5001_to_10000": "5,001–10,000",
    "population_10001_to_20000": "10,001–20,000", "population_over_20000": "Over 20,000",
}


def austrian_social_distribution(pools, filename, dimension, columns, source, locator, definition,
                                  *, unknown_column=None, classification=None):
    pools_of_crown = {unit_id: unit for unit_id, unit in pools.items() if unit.get("control_unit_id") == "ah_cisleithania"}
    counts, totals, unknowns = defaultdict(Counter), Counter(), Counter()
    territories = defaultdict(list)
    with (COLLECTIONS / "austrian_crown_1900" / filename).open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit_id = row["opening_unit_id"]
            local = {label: int(row[column]) for column, label in columns.items()}
            total = int(row["observed_total"])
            unknown = int(row[unknown_column]) if unknown_column else 0
            if sum(local.values()) + unknown != total:
                raise ValueError(f"Austrian census {dimension} source row does not close: {row['source_name']}")
            counts[unit_id].update(local)
            totals[unit_id] += total
            unknowns[unit_id] += unknown
            territories[unit_id].append(row["source_name"])
    if counts.keys() != pools_of_crown.keys():
        raise ValueError(f"Austrian census {dimension} does not cover the opening crown lands")
    for unit_id, unit in pools_of_crown.items():
        if totals[unit_id] != unit["endpoint_values"][-1]:
            raise ValueError(f"Austrian census {dimension} and population controls differ for {unit_id}")
        scope = " + ".join(territories[unit_id])
        yield unit_id, dimension, distribution(
            unit["population_value"], classification=classification or f"austria_1900_reported_{dimension}", source=source,
            date="1900-12-31", observed_unit=unit_id, scope=scope, locator=f"{locator}; {scope}",
            total=totals[unit_id], observed_counts=counts[unit_id], unknown=unknowns[unit_id], definition=definition,
        )



HUNGARIAN_RELIGION_COLUMNS = {
    "Római kath.": "Roman Catholic", "Görög kath.": "Greek Catholic",
    "Görög keleti": "Greek Orthodox", "Ágostai evang.": "Lutheran, Augsburg Confession",
    "Evang. reform.": "Reformed Protestant", "Unitárius": "Unitarian",
    "Izraelita": "Jewish", "Egyéb": "Other",
}


HUNGARIAN_LANGUAGE_COLUMNS = {
    "Magyar": "Hungarian", "Német": "German", "Tót": "Slovak", "Oláh": "Romanian",
    "Ruthén": "Ruthenian", "Horvát": "Croatian", "Szerb": "Serbian", "Egyéb": "Other",
}


HUNGARIAN_OCCUPATION_COLUMNS = {
    "primary_production_kereso": "Primary production",
    "mining_and_metallurgy_kereso": "Mining and metallurgy",
    "industry_kereso": "Industry",
    "trade_and_credit_kereso": "Trade and credit",
    "transport_kereso": "Transport",
    "public_service_and_professions_kereso": "Public service and liberal professions",
    "armed_forces_kereso": "Armed forces census category",
    "day_labour_unspecified_kereso": "Day labourers, activity unspecified",
    "domestic_servants_kereso": "Domestic servants",
}


def hungarian_crown_social(pools, dimension, columns, definition):
    path = COLLECTIONS / "austria_hungary" / f"hungarian_crown_{dimension}_1900.csv"
    with path.open(encoding="utf8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    crown_pools = {key for key, pool in pools.items() if pool.get("control_unit_id") == "ah_lands_of_st_stephen"}
    if len(rows) != len(crown_pools) or {row["unit_id"] for row in rows} != crown_pools:
        raise ValueError(f"Hungarian {dimension} table does not cover the opening Crown of St Stephen")
    for row in rows:
        unit_id = row["unit_id"]
        unit = pools[unit_id]
        total, observed = (int(row[key]) for key in ("census_total", "observed_total"))
        counts = {label: int(row[column]) for column, label in columns.items()}
        if dimension == "occupation":
            earners = sum(int(value) for key, value in row.items() if key.endswith("_kereso"))
            dependants = sum(int(value) for key, value in row.items() if key.endswith("_eltartott"))
            if (earners, dependants) != (int(row["kereso_total"]), int(row["eltartott_total"])) or earners + dependants != observed:
                raise ValueError(f"Hungarian occupation groups do not close for {unit_id}")
            observed = sum(counts.values())
            unknown = total - observed
        else:
            unknown = int(row["unknown"])
        if total != unit["endpoint_values"][-1] or observed + unknown != total:
            raise ValueError(f"Hungarian {dimension} and population controls differ for {unit_id}")
        yield unit_id, dimension, distribution(
            unit["population_value"], classification=f"hungarian_crown_1900_{dimension}",
            source=row["source_id"], date=row["observed_date"], observed_unit=unit_id,
            scope=row["observed_name"], locator=row["locator"], total=total, observed_counts=counts,
            unknown=unknown, definition=definition,
        )


def hungarian_crown_work_status(pools):
    path = COLLECTIONS / "austria_hungary" / "hungarian_crown_class_1900.csv"
    columns = {
        "independent": "Independent persons and proprietors",
        "employees": "Salaried employees",
        "other_auxiliaries": "Other auxiliary personnel",
    }
    with path.open(encoding="utf8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    crown_pools = {key for key, pool in pools.items() if pool.get("control_unit_id") == "ah_lands_of_st_stephen"}
    if len(rows) != len(crown_pools) or {row["unit_id"] for row in rows} != crown_pools:
        raise ValueError("Hungarian work-status table does not cover the opening Crown of St Stephen")
    for row in rows:
        unit_id = row["unit_id"]
        unit = pools[unit_id]
        total = int(row["census_total"])
        counts = {label: int(row[column]) for column, label in columns.items()}
        if total != unit["endpoint_values"][-1] or sum(counts.values()) != int(row["observed_total"]):
            raise ValueError(f"Hungarian work status and population controls differ for {unit_id}")
        yield unit_id, "class", distribution(
            unit["population_value"], classification="hungarian_crown_1900_work_status",
            source=row["source_id"], date=row["observed_date"], observed_unit=unit_id,
            scope=row["observed_name"], locator=row["locator"], total=total, observed_counts=counts,
            unknown=total - int(row["observed_total"]),
            definition="Census social position by the person's own livelihood. Its active population includes "
                       "the defence category, retirees and capital holders. Domestic servants and people outside "
                       "the published groups remain unassigned. The table gives neither labour participation "
                       "nor income or landholding.",
        )


def uk_constituent_occupation(pools):
    path = COLLECTIONS / "uk_constituent_occupation_1901" / "uk_1901_scotland_ireland_occupation_orders.csv"
    with path.open(encoding="utf8", newline="") as stream:
        rows = {row["order_id"]: row for row in csv.DictReader(stream)}
    occupied_orders = [row for order, row in rows.items()
                       if order not in ("XXIII", "table_total", "occupied_total",
                                        "outside_occupation_table", "all_ages_total")]
    if len(occupied_orders) != 22:
        raise ValueError("United Kingdom General Report must have 22 specified occupation orders")
    for constituent in ("scotland", "ireland"):
        unit_id = f"administrative_region:uk_constituent_{constituent}"
        pool = pools[unit_id]
        counts = {row["order_label"]: int(row[constituent]) for row in occupied_orders}
        occupied = int(rows["occupied_total"][constituent])
        table_total = int(rows["table_total"][constituent])
        unknown_in_table = int(rows["XXIII"][constituent])
        outside_table = int(rows["outside_occupation_table"][constituent])
        total = int(rows["all_ages_total"][constituent])
        if (sum(counts.values()) != occupied or occupied + unknown_in_table != table_total
                or table_total + outside_table != total or pool["endpoint_values"][-1] != total):
            raise ValueError(f"{unit_id}: occupational orders do not close to the constituent's population")
        yield unit_id, "occupation", distribution(
            pool["population_value"], classification="uk_1901_general_report_occupation_orders",
            source="uk_general_census_report_1901_occupation_orders", date="1901-03-31",
            observed_unit=unit_id, scope=pool["name"], locator="Appendix A, Table 35, pp. 270–281",
            total=total, observed_counts=counts, unknown=unknown_in_table + outside_table,
            definition="Specified occupational orders for persons aged 10 and older. Ireland also includes "
                       "occupied children below ten. Unoccupied or unspecified and people outside the return "
                       "remain unassigned. County occupations are unknown.",
        )


def prussian_marital_status(pools):
    unit_id = "administrative_region:germany_preussen"
    unit = pools[unit_id]
    path = COLLECTIONS / "prussia_census_1900" / "marital.csv"
    with path.open(encoding="utf8", newline="") as stream:
        counts = {row["status"]: int(row["male"]) + int(row["female"]) for row in csv.DictReader(stream)}
    yield unit_id, "marital_status", distribution(
        unit["population_value"], classification="prussia_1900_reported_marital_status",
        source="de_prussia_handbook_1903_census_ages", date="1900-12-01", observed_unit=unit_id,
        scope="Kingdom of Prussia, population present", locator="Part II.A, Table VIII, printed p. 99, Prussian state row",
        total=unit["endpoint_values"][-1], observed_counts=counts, unknown=0,
        definition="Census civil status of all persons present. Never married includes children.",
    )


def german_state_marital_status(pools, collection, *, classification, source, scope, locator):
    path = COLLECTIONS / collection / "marital.csv"
    with path.open(encoding="utf8", newline="") as stream:
        *rows, control = csv.DictReader(stream)
    unit_id = control["state_id"]
    unit = pools[unit_id]
    total = int(control["both"])
    if (total != unit["endpoint_values"][-1]
            or any(sum(int(row[sex]) for row in rows) != int(control[sex]) for sex in ("male", "female"))
            or any(int(row["male"]) + int(row["female"]) != int(row["both"]) for row in [control, *rows])):
        raise ValueError(f"Civil status and population controls differ for {unit_id}")
    labels = {"single": "Never married", "married": "Married", "widowed": "Widowed", "divorced": "Divorced"}
    yield unit_id, "marital_status", distribution(
        unit["population_value"], classification=classification,
        source=source, date=control["census_date"], observed_unit=unit_id, scope=scope, locator=locator,
        total=total, observed_counts={labels[row["marital_status"]]: int(row["both"]) for row in rows},
        unknown=0, definition="Civil status of all persons present. The never-married category includes children.",
    )


def italy_marital_status(pool):
    path = COLLECTIONS / "italy_census_1901" / "marital.csv"
    with path.open(encoding="utf8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    controls = {"male": 16_155_130, "female": 16_320_123}
    if any(sum(int(row[sex]) for row in rows) != total for sex, total in controls.items()):
        raise ValueError("Italian census civil status does not close")
    counts = {row["marital_status"]: int(row["male"]) + int(row["female"]) for row in rows}
    yield pool["unit_id"], "marital_status", distribution(
        pool["population_value"], classification="italy_1901_reported_marital_status",
        source="it_1901_census_v5_age_and_marital", date="1901-02-10", observed_unit="kingdom_of_italy",
        scope="Kingdom of Italy, population present", locator="Vol. V, printed pp. LXIV–LXV",
        total=sum(controls.values()), observed_counts=counts, unknown=0,
        definition="Civil status of all persons present. Legally separated persons are included with married persons.",
    )


def spain_marital_status(pools, observations, version):
    panel = "es_census_1900_peninsula_islas"
    collection = COLLECTIONS / "spain_census_1900"
    with (collection / "marital_status.csv").open(encoding="utf8", newline="") as stream:
        rows = [row for row in csv.DictReader(stream) if row["panel"] == panel]
    with (collection / "population_controls.csv").open(encoding="utf8", newline="") as stream:
        control, = (row for row in csv.DictReader(stream) if row["panel"] == panel)
    if (any(sum(int(row[sex]) for row in rows) != int(control[sex]) for sex in ("male", "female"))
            or any(int(row["male"]) + int(row["female"]) != int(row["both"]) for row in [*rows, control])):
        raise ValueError("Spanish census civil status does not close by sex")
    remaining = {row["category"]: int(row["both"]) for row in rows}
    labels = {row["category"]: row["label"] for row in rows}
    national_scope = "Population present in the peninsula, the Balearic Islands and the Canary Islands"
    allocations = []
    if version >= 25:
        local = defaultdict(list)
        with (collection / "provincial_marital_status_1900.csv").open(encoding="utf8", newline="") as stream:
            for row in csv.DictReader(stream):
                local[row["panel"]].append(row)
        with (collection / "provincial_age_sources_1900.csv").open(encoding="utf8", newline="") as stream:
            sources = {row["panel"]: row for row in csv.DictReader(stream)}
        sex_controls = {row["unit_id"]: row["sex"] for row in observations
                        if row["source_id"] == "es_census_1900_provincial_population" and row["unit_id"] in local}
        for unit, provincial_rows in local.items():
            source = sources[unit]
            if (any(sum(int(row[sex]) for row in provincial_rows) != sex_controls[unit][sex]
                    for sex in ("male", "female"))
                    or any(int(row["male"]) + int(row["female"]) != int(row["both"]) for row in provincial_rows)):
                raise ValueError(f"{unit}: civil status does not close to the provincial sex counts")
            counts = {row["category"]: int(row["both"]) for row in provincial_rows}
            for key, count in counts.items():
                remaining[key] -= count
            locator = f"Vol. III, printed pp. {source['printed_pages']}; {source['method']}"
            allocations.append((unit, unit, source["province"], locator, counts))
        allocations.append((SPANISH_CIVIL_STATUS_SCOPE, panel, f"{national_scope}, less the nine assigned provinces",
                            f"{control['printed_pages']}; subtract nine separately reported provinces", remaining))
    else:
        allocations.append(("kingdom_of_spain", panel, national_scope, control["printed_pages"], remaining))
    for unit, observed, scope, locator, counts in allocations:
        yield unit, "marital_status", distribution(
            pools[unit]["population_value"], classification="spain_1900_reported_marital_status",
            source="es_census_1900_age_marital", date=control["date"], observed_unit=observed,
            scope=scope, locator=locator, total=sum(counts.values()), unknown=counts["unknown"],
            observed_counts={labels[key]: value for key, value in counts.items() if key != "unknown"},
            definition="The census reports civil status for all ages. African possessions are removed by category.",
            method=f"{SHARE_METHOD} The year-end shares are used for January 1; intervening change is unquantified.",
        )


def bombay_city_social(pools, version):
    unit = "raj_bombay_bombay_city"
    pool = pools[unit]
    detailed = version >= 40
    filename = "bombay_city_religion_1901_detailed.csv" if detailed else "bombay_city_religion_1901.csv"
    path = COLLECTIONS / "india_bombay_districts_1901" / filename
    with path.open(encoding="utf8", newline="") as stream:
        row, = csv.DictReader(stream)
    total = int(row["population"])
    if row["unit_id"] != unit or total != pool["endpoint_values"][-1]:
        raise ValueError("Bombay City religion does not match its 1901 city census control")
    yield unit, "religion", distribution(
        pool["population_value"], classification="india_1901_reported_religion",
        source="india_bombay_city_1901_religion_detailed" if detailed else "india_bombay_city_1901_religion",
        date=INDIA_DATE, observed_unit=unit,
        scope="Bombay City and Island, all persons present on the census date",
        locator=("Census of 1901, Vol. I-A, Table V pp. 38–39; Gazetteer of Bombay City and Island, Vol. I, Ch. III."
                 if detailed else "Census of 1901, Vol. XI, Part V p. 24; Gazetteer of Bombay City and Island, Vol. I, Ch. III."),
        total=total, unknown=int(row["others"]),
        observed_counts={category: int(row[category]) for category in INDIA_TABLES["7"][3] if category in row},
        definition="Named census religions. The remaining other religions are kept unassigned. "
                   "The census did not include estimated evacuees.",
        method=f"{SHARE_METHOD} The effect of migration and plague on religious composition is unquantified.",
    )
    with path.with_name("bombay_city_sex_controls.csv").open(encoding="utf8", newline="") as stream:
        control, = (row for row in csv.DictReader(stream) if row["date"] == INDIA_DATE)
    for dimension, classification, locator, definition in (
        ("marital_status", "india_1901_reported_civil_condition", "Table VII p. 438, row 2, columns 5–13",
         "Census civil condition for both sexes and all ages. The opening uses a separate marginal."),
        ("literacy", "india_1901_reported_literacy", "Table VIII pp. 446–447, row 2, columns 2–10",
         "All-age census literacy. Literate residents can read and write in any language."),
    ):
        with path.with_name(f"bombay_city_{dimension}_1901.csv").open(encoding="utf8", newline="") as stream:
            rows = list(csv.DictReader(stream))
        for sex in ("male", "female"):
            if sum(int(row[sex]) for row in rows) != int(control[sex]):
                raise ValueError(f"Bombay City {dimension} does not match the 1901 {sex} control")
        yield unit, dimension, distribution(
            pool["population_value"], classification=classification,
            source=f"india_bombay_city_1901_{dimension}", date=INDIA_DATE, observed_unit=unit,
            scope="Bombay City and Island, all persons present on the census date",
            locator=f"Census of India 1901, Vol. I-A, {locator}.", total=total, unknown=0,
            observed_counts={row["status"]: int(row["male"]) + int(row["female"]) for row in rows},
            definition=definition,
            method=f"{SHARE_METHOD} The effect of migration and plague on the distribution is unquantified.",
        )
    with path.with_name("bombay_city_occupation_1901.csv").open(encoding="utf8", newline="") as stream:
        orders = list(csv.DictReader(stream))
    if ([int(row["order"]) for row in orders] != list(range(1, 25))
            or tuple(sum(int(row[field]) for row in orders) for field in ("male", "female", "dependents"))
            != (376_486, 69_205, 330_315)):
        raise ValueError("Bombay City occupation orders do not match the census worker and dependent controls")
    workers = {row["label"]: int(row["male"]) + int(row["female"]) for row in orders[:22]}
    yield unit, "occupation", distribution(
        pool["population_value"], classification="india_1901_principal_occupation_orders",
        source="india_bombay_city_1901_occupation", date=INDIA_DATE, observed_unit=unit,
        scope="Bombay City and Island, actual workers within the census population",
        locator="Census of India 1901, Vol. I-A, Table XV pp. 472–528, Bombay City, columns 5–7.",
        total=total, unknown=total - sum(workers.values()), observed_counts=workers,
        definition="Principal occupation of actual workers, orders I–XXII. Dependents and orders XXIII–XXIV are unassigned.",
        method=f"{SHARE_METHOD} The effect of migration and plague on the distribution is unquantified.",
    )


def agra_oudh_religion(pools, observations, version):
    categories = (
        ("hindu", "Hindus"), ("sikh", "Sikhs"), ("jain", "Jains"), ("buddhist", "Buddhists"),
        ("parsi", "Parsis"), ("muslim", "Muhammadans"), ("christian", "Christians"), ("jewish", "Jews"),
        ("arya", "Aryas"), ("brahmo", "Brahmos"), ("new_hindu_vedantist", "New Hindu Vedantists"),
    )
    files = [("india_local_areas_1901/oudh_religion.csv", "india_oudh_census_1901_districts")]
    if version >= 26:
        files.append(("india_agra_districts_1901/religion.csv", AGRA_DISTRICT_SOURCE))
    for filename, source in files:
        with (COLLECTIONS / filename).open(encoding="utf8", newline="") as stream:
            for row in csv.DictReader(stream):
                if row["row_role"] != "district":
                    continue
                unit = row["unit_id"]
                pool = pools[unit]
                total = int(row["population"])
                if pool["endpoint_values"][-1] != total:
                    raise ValueError(f"{unit}: religion and opening census controls differ")
                yield unit, "religion", distribution(
                    pool["population_value"], classification="india_1901_reported_religion",
                    source=source, date=INDIA_DATE, observed_unit=unit,
                    scope=f"{row['name']} census district, all persons present",
                    locator=f"Table VI, printed pp. 38–40, row {row['source_row']}", total=total, unknown=0,
                    observed_counts={label: int(row[column]) for column, label in categories if column in row},
                    definition="District census religion. The distinct published Arya and Brahmo categories are retained.",
                )
    if version >= 26:
        return
    unit = "raj_agra_remainder"
    agra, = (row for row in observations if row["unit_id"] == "raj_agra_1901_provincial_return")
    pool = pools[unit]
    total = pool["endpoint_values"][-1]
    unknown = total - agra["population_value"]
    if unknown != 294:
        raise ValueError("Agra religion and comparable-area controls do not reconcile")
    yield unit, "religion", distribution(
        pool["population_value"], classification="india_1901_reported_religion",
        source=agra["source_id"], date=agra["date"], observed_unit=agra["unit_id"], scope=agra["definition"],
        locator=agra["locator"], total=total, unknown=unknown, observed_counts=agra["religion"],
        definition="The religious categories include two New Hindu Vedantists reported in a footnote. "
                   "A further 294 people in the comparative-area control are not attributed to any religion.",
    )


MEXICO_SOCIAL_TABLES = {
    "language": ("castellano idiomas_indigenas idiomas_extranjeros",
                 ("Castellano", "Idiomas Indígenas", "Idiomas Extranjeros"),
                 "Language classification as published. Indigenous and foreign languages are grouped. "
                 "The census does not establish individual cultural identity or multilingual margins."),
    "religion": ("catolicos protestantes mahometanos mormones budistas israelitas griegos sin_culto",
                 ("Católicos", "Protestantes", "Mahometanos", "Mormones", "Budistas", "Israelitas", "Griegos", "Sin Culto"),
                 "Reported census religion. Sin Culto is a published category. The table does not report observance."),
    "literacy": ("saben_leer_y_escribir saben_solo_leer no_saben_leer_ni_escribir_12_and_over "
                 "no_saben_leer_ni_escribir_under_12",
                 ("Read and write", "Read only", "Neither read nor write, 12 and older", "Neither read nor write, under 12"),
                 "Published literacy classification, with persons below 12 separated on the neither category."),
    "marital_status": ("solteros casados viudos", ("Never married", "Married", "Widowed"),
                       "Marital status as classified in the original census. Minors are tabulated separately without civil status."),
    "occupation": ("agricultura mineria industrias transportes comercio fuerzas_publicas administracion_publica "
                   "profesiones_liberales propietarios_y_rentistas trabajos_domesticos diversas_ocupaciones",
                   ("Agricultura", "Minería", "Industrias", "Transportes", "Comercio", "Fuerzas Públicas",
                    "Administración Pública", "Profesiones Liberales", "Propietarios y Rentistas",
                    "Trabajos Domésticos", "Diversas Ocupaciones"),
                   "Census occupational categories, including domestic work and property or rent income as originally classified. "
                   "Domestic work does not imply paid employment. Persons in the unknown profession category remain unassigned."),
}


def mexico_census_social(pools):
    mexican = {key for key in pools if key.startswith("mx_")}
    for dimension, (columns, labels, definition) in MEXICO_SOCIAL_TABLES.items():
        path = COLLECTIONS / "mexico_census_1900" / f"{dimension}.csv"
        with path.open(encoding="utf8", newline="") as stream:
            rows = list(csv.DictReader(stream))
        expected = mexican - ({"mx_coahuila", "mx_queretaro"} if dimension == "occupation" else set())
        if {row["unit_id"] for row in rows} != expected or len(rows) != len(expected):
            raise ValueError(f"Unexpected Mexican census scopes for {dimension}")
        for row in rows:
            unit_id = row["unit_id"]
            unit = pools[unit_id]
            total = int(row["observed_total"])
            difference = 13 if unit_id == "mx_durango" else 0
            if unit["endpoint_values"][-1] != total + difference:
                raise ValueError(f"Mexican census controls differ for {unit_id}")
            observed_counts = {label: int(row[column]) for label, column in zip(labels, columns.split(), strict=True)}
            unknown = int(row["observed_unknown"]) + int(row.get("menores_de_edad", 0))
            yield unit_id, dimension, distribution(
                unit["population_value"], classification=f"mexico_1900_reported_{dimension}",
                source=row["source_id"], date=row["observed_date"], observed_unit=unit_id,
                scope=row["observed_name"], locator=row["locator"], total=total, observed_counts=observed_counts,
                unknown=unknown, definition=definition,
                method=SHARE_METHOD + " The change between January and the October census is unquantified."
                + (" Durango's original census control was 13 below the revised series endpoint." if difference else ""),
            )


def italian_settlement(pools):
    path = COLLECTIONS / "italy_census_1901" / "settlement.csv"
    columns = ("centers_at_least_500", "centers_under_500", "dispersed_countryside")
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit = row["unit_id"]
            pool = pools[unit]
            total = int(row["observed_total"])
            if pool["endpoint_values"][-1] != total:
                raise ValueError(f"{unit}: census settlement and opening endpoints differ")
            yield unit, "residence", distribution(
                pool["population_value"], classification="italy_1901_settlement_pattern",
                source="it_1901_census_v5_age_and_marital", date=row["observed_date"], observed_unit=unit,
                scope=f"{row['source_label']}, census population present",
                locator=row["locator"], total=total, unknown=int(row["unknown"]),
                observed_counts={key: int(row[key]) for key in columns},
                definition="Population in census centers of at least 500 residents, smaller centers, "
                           "or dispersed settlements. Commissioners identified centers using local conditions.",
            )


def italian_occupation(pools):
    categories = (
        "agriculture_fishing_hunting", "industry", "commerce", "domestic_and_street_services",
        "liberal_professions_and_arts", "no_occupation",
    )
    path = COLLECTIONS / "italy_census_1901" / "occupation.csv"
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit = row["unit_id"]
            pool = pools[unit]
            total = int(row["observed_total"])
            if pool["endpoint_values"][-1] != total:
                raise ValueError(f"{unit}: census occupation and opening endpoints differ")
            for sex in ("male", "female"):
                cells = [int(row[f"{category}_{sex}"]) for category in categories]
                if sum(cells) + int(row[f"eligible_occupation_unknown_{sex}"]) != int(row[f"eligible_{sex}"]):
                    raise ValueError(f"{unit}: {sex} occupational population does not close")
            yield unit, "occupation", distribution(
                pool["population_value"], classification="italy_1901_reported_occupation",
                source="it_1901_census_v4_occupation", date=row["observed_date"], observed_unit=unit,
                scope=f"{row['source_label']}, census population present",
                locator=row["locator"], total=total, unknown=int(row["unknown"]),
                observed_counts={category: int(row[f"{category}_male"]) + int(row[f"{category}_female"])
                                 for category in categories},
                definition="Own occupation or reported absence of an occupation, among people born through 1891. "
                           "The table's unreported occupations and people outside that birth-year scope remain unknown.",
            )


def italian_literacy(pools):
    path = COLLECTIONS / "italy_census_1901" / "literacy.csv"
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit = row["unit_id"]
            pool = pools[unit]
            total = int(row["observed_total"])
            if pool["endpoint_values"][-1] != total:
                raise ValueError(f"{unit}: census literacy and opening endpoints differ")
            yield unit, "literacy", distribution(
                pool["population_value"], classification="italy_1901_reported_reading",
                source="it_1901_census_v2_literacy", date=row["observed_date"], observed_unit=unit,
                scope=f"{row['source_label']}, census population present",
                locator=row["locator"], total=total, unknown=int(row["unknown"]),
                observed_counts={key: int(row[key]) for key in ("able_to_read", "unable_to_read")},
                definition="Reported ability to read at all recorded ages. The original table includes "
                           "the younger birth years. People omitted from the table for unknown age remain unassigned.",
            )


def italian_registered_property(pools):
    owners = ("registered_land_only", "registered_buildings_only", "registered_land_and_buildings")
    path = COLLECTIONS / "italy_census_1901" / "registered_property.csv"
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit = row["unit_id"]
            pool = pools[unit]
            total = int(row["observed_total"])
            if pool["endpoint_values"][-1] != total:
                raise ValueError(f"{unit}: census property and opening endpoints differ")
            counts = {key: int(row[key]) for key in owners}
            if sum(counts.values()) != int(row["declared_owners_total"]):
                raise ValueError(f"{unit}: declared individual owners do not close")
            remainder = int(row["no_registered_ownership_declaration"])
            yield unit, "property_declaration", distribution(
                pool["population_value"], classification="italy_1901_registered_real_property",
                source="it_1901_census_v4_occupation", date=row["observed_date"], observed_unit=unit,
                scope=f"{row['source_label']}, census population present",
                locator=row["locator"], total=total, unknown=0,
                observed_counts=counts | {"no_registered_ownership_declaration": remainder},
                definition="Registry ownership by individuals. The aggregate without an ownership declaration "
                           "includes negative and blank responses. Actual property holdings in that group remain unknown.",
            )


def italian_industrial_position(pools):
    categories = (
        "owners_directors_artisans", "home_textile_artisans",
        "clerks_shop_assistants_commercial_travelers", "foremen_workers_laborers",
    )
    collection = COLLECTIONS / "italy_census_1901"
    with (collection / "occupation.csv").open(encoding="utf8", newline="") as stream:
        occupation = {row["unit_id"]: row for row in csv.DictReader(stream)}
    with (collection / "industrial_position.csv").open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit = row["unit_id"]
            pool = pools[unit]
            total = int(row["observed_total"])
            if pool["endpoint_values"][-1] != total:
                raise ValueError(f"{unit}: census industrial position and opening endpoints differ")
            for sex in ("male", "female"):
                classified = sum(int(row[f"{category}_{sex}"]) for category in categories)
                if classified != int(row[f"industry_{sex}"]) or classified != int(occupation[unit][f"industry_{sex}"]):
                    raise ValueError(f"{unit}: {sex} industrial position does not close to the occupational control")
            yield unit, "class", distribution(
                pool["population_value"], classification="italy_1901_industrial_position",
                source="it_1901_census_v5_industrial_position", date=row["observed_date"], observed_unit=unit,
                scope=f"{row['source_label']}, own industry occupational group",
                locator=row["locator"], total=total, unknown=int(row["unknown"]),
                observed_counts={category: int(row[f"{category}_male"]) + int(row[f"{category}_female"])
                                 for category in categories},
                definition="Census position within the person's declared industrial occupation. Other occupations, "
                           "people outside the occupation table and compartments with conflicting counts remain unknown.",
            )


def egyptian_provincial_religion(pools, observations):
    source = "egypt_1897_markaz_religion"
    for row in observations:
        if row["source_id"] != source:
            continue
        unit = row["unit_id"]
        if unit == "egy_mudiriya_faiyum" and "egy_markaz_itsa" in pools:
            continue
        pool = pools[unit]
        total = row["population_value"]
        if pool["endpoint_values"][0] != total:
            raise ValueError(f"{unit}: provincial religion and opening endpoints differ")
        yield unit, "religion", distribution(
            pool["population_value"], classification="egypt_1897_reported_religion",
            source=source, date=row["date"], observed_unit=unit, scope=row["definition"],
            locator=row["locator"], total=total, unknown=0, observed_counts=row["religion"],
            definition="Published province subtotals by religion, including all reported Christian denominations together.",
            method=f"{SHARE_METHOD} Religious composition changes between June 1897 and January 1900 are unquantified.",
        )


def egyptian_faiyum_social(pools, observations):
    source = "egypt_faiyum_census_1897"
    for row in observations:
        if row["source_id"] != source:
            continue
        unit = row["unit_id"]
        pool = pools[unit]
        total = row["population_value"]
        if pool["endpoint_values"][0] != total:
            raise ValueError(f"{unit}: social and population census controls differ")
        breakdowns = row["breakdowns"]
        classifications = [
            ("religion", "egypt_1897_reported_religion", breakdowns["religion"],
             "Census religion. Christian denominations are combined."),
        ]
        for field, dimension, classification, labels, definition in [
            ("work", "occupation", "egypt_1897_reported_occupation_status", ("With occupation", "Without occupation"),
             "Census reports the presence of an occupation. Exact occupation, employment or wage status is unknown."),
            ("reading", "literacy", "egypt_1897_reported_instruction", ("Read and write", "Illiterate"),
             "Census instruction categories for the entire district population."),
        ]:
            male_yes, male_no, female_yes, female_no = breakdowns[field]
            sex = breakdowns["sex"]
            if male_yes + male_no != sex["male"] or female_yes + female_no != sex["female"]:
                continue
            counts = dict(zip(labels, (male_yes + female_yes, male_no + female_no), strict=True))
            classifications.append((dimension, classification, counts, definition))
        for dimension, classification, counts, definition in classifications:
            yield unit, dimension, distribution(
                pool["population_value"], classification=classification, source=source, date=row["date"],
                observed_unit=unit, scope=row["definition"], locator=row["locator"], total=total,
                observed_counts=counts, unknown=0, definition=definition,
            )


def egyptian_provincial_work_and_instruction(pools, observations):
    source = "egypt_1897_markaz_occupation_and_instruction"
    census = {row["unit_id"]: row for row in observations
              if row["source_id"] == "egypt_census_1907_comparable_provinces" and row["date"] == "1897-06-01"}
    path = COLLECTIONS / "egypt_comparable_provinces" / "egypt_1897_province_social.csv"
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit_id = row["unit_id"]
            pool = pools[unit_id]
            control = census[unit_id]
            total = int(row["observed_total"])
            cells = [(row[f"category_{key}"], int(row[f"category_{key}_male"]), int(row[f"category_{key}_female"]))
                     for key in ("a", "b")]
            for sex, amount in zip(("male", "female"), (sum(cell[1] for cell in cells), sum(cell[2] for cell in cells)),
                                   strict=True):
                if amount != int(row[f"{sex}_total"]) or amount != control["breakdowns"]["sex"][sex]:
                    raise ValueError(f"{unit_id}: 1897 social counts differ from the comparative sex control")
            if total != pool["endpoint_values"][0] or row["date"] != control["date"]:
                raise ValueError(f"{unit_id}: social census scope differs from the opening endpoint")
            if row["dimension"] == "occupation_status":
                dimension, classification = "occupation", "egypt_1897_reported_occupation_status"
                labels = {"with occupation": "With occupation", "without": "Without occupation"}
                definition = "Reported occupation status. The return gives no individual trade or work arrangement."
            else:
                dimension, classification = "literacy", "egypt_1897_reported_instruction"
                labels = {"READ&WRITE": "Read and write", "ILLITERATE": "Illiterate"}
                definition = "Census instruction categories for all ages."
            yield unit_id, dimension, distribution(
                pool["population_value"], classification=classification, source=source, date=row["date"],
                observed_unit=unit_id, scope=pool["name"], locator=row["locator"], total=total,
                observed_counts={labels[label]: male + female for label, male, female in cells},
                unknown=int(row["unknown"]), definition=definition,
            )


def brazilian_state_distribution(pools, filename, dimension, classification, source, columns, definition):
    path = COLLECTIONS / "brazil_census_1900_age" / filename
    with path.open(encoding="utf8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    if sum(int(row["observed_total"]) for row in rows) != 16_626_991:
        raise ValueError(f"Brazilian {dimension} does not close to the non-federal census total")
    for row in rows:
        unit = row["unit_id"]
        pool = pools[unit]
        total = int(row["observed_total"])
        if (pool["endpoint_values"][-1] != total
                or any(sum(int(row[f"{category}_{sex}"]) for category in columns) != int(row[f"observed_{sex}"])
                       for sex in ("male", "female"))):
            raise ValueError(f"{unit}: {dimension} and state population counts do not close")
        yield unit, dimension, distribution(
            pool["population_value"], classification=classification,
            source=source, date=row["observed_date"], observed_unit=unit,
            scope=f"{row['source_label']}, census state population", locator=row["locator"],
            total=total, unknown=int(row["unknown"]),
            observed_counts={label: int(row[f"{key}_male"]) + int(row[f"{key}_female"])
                             for key, label in columns.items()},
            definition=definition,
        )


def brazilian_state_religion(pools):
    path = COLLECTIONS / "brazil_census_1900_age" / "religion.csv"
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit = row["unit_id"]
            pool = pools[unit]
            total = int(row["observed_total"])
            if total != pool["endpoint_values"][-1]:
                raise ValueError(f"{unit}: religion and population counts do not close")
            source = "br_ibge_1960_sc_historical_religion" if unit == "br_santa_catarina" else "br_ibge_1958_1900_religion"
            yield unit, "religion", distribution(
                pool["population_value"], classification="brazil_1900_reported_religion",
                source=source, date=row["observed_date"], observed_unit=unit,
                scope=f"{row['source_label']}, census state population", locator=row["locator"],
                total=total, unknown=int(row["unknown"]),
                observed_counts={"Roman Catholic": int(row["roman_catholic"]), "Protestant": int(row["protestant"]),
                                 "Other reported religions": int(row["other_reported_religion"])},
                definition="Reported confessions include a grouped other category. Nonresponses remain unknown. "
                           "The cancelled 1900 Federal District count is outside this allocation.",
            )


def portuguese_district_social(pools):
    collection = COLLECTIONS / "portugal_census_1900"
    tables = (
        ("literacy", {"sabem_ler": "Read", "analfabetos": "Illiterate"}, None,
         "All ages. The census records reading and does not establish writing ability."),
        ("marital_status", {"solteiros": "Never married", "casados": "Married",
                            "separados_judicialmente": "Judicially separated", "viuvos": "Widowed"}, None,
         "All ages by published civil status. The never-married category includes children."),
        ("religion", {"catholicos": "Roman Catholic", "protestantes": "Protestant", "orthodoxos": "Orthodox",
                      "israelitas": "Jewish", "mahometanos": "Muslim", "sem_religiao": "No religion"},
         "de_religiao_ignorada", "Reported religion. No religion and religion unknown are distinct."),
    )
    with (collection / "district_population_sex_1890_1900.csv").open(encoding="utf8", newline="") as stream:
        controls = {row["unit_id"]: row for row in csv.DictReader(stream)}
    for dimension, labels, unknown_key, definition in tables:
        with (collection / f"{dimension}.csv").open(encoding="utf8", newline="") as stream:
            rows = {row["unit_id"]: row for row in csv.DictReader(stream)}
        if rows.keys() != controls.keys():
            raise ValueError(f"Portugal: incomplete district {dimension} coverage")
        keys = [*labels, unknown_key] if unknown_key else list(labels)
        for unit, row in rows.items():
            for sex in ("male", "female"):
                if sum(int(row[f"{key}_{sex}"]) for key in keys) != int(controls[unit][f"{sex}_1900"]):
                    raise ValueError(f"{unit}: {dimension} differs from the {sex} control")
            counts = {label: int(row[f"{key}_male"]) + int(row[f"{key}_female"]) for key, label in labels.items()}
            unknown = sum(int(row[f"{unknown_key}_{sex}"]) for sex in ("male", "female")) if unknown_key else 0
            yield unit, dimension, portuguese_distribution(pools[unit], row, dimension, counts, unknown, definition)

    with (collection / "occupation.csv").open(encoding="utf8", newline="") as stream:
        labels = {row["source_category"]: row["source_category_label"] for row in csv.DictReader(stream)
                  if row["category_definition"] in ("occupation", "income_without_recorded_occupation")}
    with (collection / "district_occupation.csv").open(encoding="utf8", newline="") as stream:
        rows = {row["unit_id"]: row for row in csv.DictReader(stream)}
    if rows.keys() != controls.keys():
        raise ValueError("Portugal: incomplete district occupation coverage")
    for unit, row in rows.items():
        counts = {label: int(row[f"occupation_{key}"]) for key, label in labels.items()}
        extra = ("family_under_14", "family_over_14", "domestic_servants")
        for sex in ("male", "female"):
            if int(row[f"occupation_table_{sex}"]) + sum(int(row[f"{key}_{sex}"]) for key in extra) != int(controls[unit][f"{sex}_1900"]):
                raise ValueError(f"{unit}: occupational statuses differ from the {sex} control")
        counts["Family members without a gainful occupation"] = sum(int(row[f"{key}_{sex}"])
            for key in extra[:2] for sex in ("male", "female"))
        counts["Domestic servants"] = int(row["domestic_servants_male"]) + int(row["domestic_servants_female"])
        yield unit, "occupation", portuguese_distribution(
            pools[unit], row, "occupation", counts, int(row["occupation_XII"]),
            "Own occupation or explicitly reported livelihood status. Domestic servants and non-earning family "
            "members are separate categories. The mixed nonproductive or occupation unknown column is unassigned.",
        )


def portuguese_distribution(pool, row, dimension, counts, unknown, definition):
    total = int(row["observed_total"])
    if total != pool["endpoint_values"][-1]:
        raise ValueError(f"{row['unit_id']}: social return differs from the population control")
    return distribution(
        pool["population_value"], classification=f"portugal_1900_reported_{dimension}",
        source="pt_census_1900", date=row["observed_date"], observed_unit=row["unit_id"],
        scope=f"{row['source_label']}, all persons present", locator=row["locator"], total=total,
        observed_counts=counts, unknown=unknown, definition=definition,
        method=f"{SHARE_METHOD} Uses December 1900 district shares. Intervening change is unquantified.",
    )


def belgian_provincial_distribution(pools, filename, dimension, classification, source, locator, definition):
    collection = COLLECTIONS / "belgium_provinces_1900"
    with (collection / filename).open(encoding="utf8", newline="") as stream:
        provincial = defaultdict(list)
        for row in csv.DictReader(stream):
            provincial[row["panel"]].append(row)
    national = {row["category"]: int(row["both"]) for row in provincial.pop("be_census_kingdom")}
    combined = Counter()
    with (collection / "provincial_sex_1890_1900.csv").open(encoding="utf8", newline="") as stream:
        controls = {row["unit_id"]: row for row in csv.DictReader(stream) if row["date"] == "1900-12-31"}
    for unit, rows in provincial.items():
        pool = pools[unit]
        total = pool["endpoint_values"][-1]
        if any(sum(int(row[sex]) for row in rows) != int(controls[unit][sex]) for sex in ("male", "female")):
            raise ValueError(f"{unit}: {dimension} counts do not match the resident sex controls")
        combined.update({row["category"]: int(row["both"]) for row in rows})
        yield unit, dimension, distribution(
            pool["population_value"], classification=classification,
            source=source, date="1900-12-31", observed_unit=unit,
            scope=f"{pool['name']}, usual residents", locator=locator, total=total,
            observed_counts={row["label"]: int(row["both"]) for row in rows}, unknown=0,
            definition=definition,
        )
    if dict(combined) != national:
        raise ValueError(f"Belgian provincial {dimension} categories do not close to the national totals")


CANADA_ORIGIN_COLUMNS = {
    "British": "british", "French": "french", "German": "german",
    "Indian and h. b.": "indigenous_and_mixed_indigenous",
    "Scandinavian": "scandinavian", "Other specified origins": "other_reported_origins",
}


def canada_reported_origin(pools):
    path = COLLECTIONS / "canada_origin_1901" / "origin_1901_opening_scopes.csv"
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit = row["unit_id"]
            pool = pools[unit]
            total = int(row["observed_total"])
            if pool["endpoint_values"][-1] != total:
                raise ValueError(f"{unit}: census origin and opening controls differ")
            yield unit, "culture", distribution(
                pool["population_value"], classification="canada_1901_reported_ancestral_or_tribal_origin",
                source=row["source_id"], date=row["observed_date"], observed_unit=unit,
                scope=f"{row['observed_name']}, population recorded in the 1901 de jure census",
                locator=row["locator"], total=total, unknown=int(row["observed_unknown"]),
                observed_counts={key: int(row[column]) for column, key in CANADA_ORIGIN_COLUMNS.items()},
                definition="Recorded ancestral or tribal origin under historical descent rules. This proxy measures "
                           "reported origin. Language, self-identification and cultural practices remain unknown. "
                           "Census omissions and change since January 1900 have no quantified interval.",
            )


def bengal_district_literacy(pools, observations, version):
    controls = {row["unit_id"]: row for row in observations
                if row["source_id"] == BENGAL_DISTRICT_SOURCE and row["date"] == INDIA_DATE}
    collection = COLLECTIONS / "india_bengal_districts_1901"
    paths = [collection / "bengal_literacy_1901.csv"]
    if version >= 28:
        paths.extend(collection / file for file in
                     ("bengal_district_literacy_1901.csv", "bengal_district_literacy_1901_batch2.csv",
                      "bengal_district_literacy_1901_batch3.csv", "bengal_district_literacy_1901_batch4.csv"))
    for path in paths:
        source_id = ("india_bengal_census_1901_literacy" if path == paths[0]
                     else "india_bengal_census_1901_district_literacy")
        with path.open(encoding="utf-8", newline="") as source:
            rows = list(csv.DictReader(source))
        for row in rows:
            unit_id = row["unit_id"]
            control = controls[unit_id]
            pool = pools[unit_id]
            observed_total = int(row["observed_total"])
            counts = {name.title(): int(row[name]) for name in ("literate", "illiterate")}
            if (row["observed_date"] != INDIA_DATE or observed_total != pool["endpoint_values"][-1]
                    or int(row["observed_unknown"]) != 0):
                raise ValueError(f"{unit_id}: incompatible Bengal literacy scope")
            for sex in ("male", "female"):
                if not (sum(int(row[f"{name}_{sex}"]) for name in ("literate", "illiterate"))
                        == int(row[f"observed_{sex}"]) == control["sex"][sex]):
                    raise ValueError(f"{unit_id}: Bengal literacy does not match the census {sex} population")
            for name, count in counts.items():
                if sum(int(row[f"{name.lower()}_{sex}"]) for sex in ("male", "female")) != count:
                    raise ValueError(f"{unit_id}: Bengal literacy category {name} does not close")
            yield unit_id, "literacy", distribution(
                pool["population_value"], classification=INDIA_TABLES["16"][1],
                source=source_id, date=INDIA_DATE, observed_unit=unit_id,
                scope=f"{pool['name']}, population on the March 1901 census jurisdiction",
                locator=row["locator"], total=observed_total, observed_counts=counts, unknown=0,
                definition="Ability to read and write a letter, all ages. English and vernacular subcolumns may overlap and are excluded. "
                           "Change between January 1900 and March 1901 has no quantified interval.",
            )


def argentine_local_distribution(pools, dimension, fields, unknown_field, *, source, locator, definition, method):
    directory = COLLECTIONS / "argentina_age_1895_1914"
    with (directory / f"{dimension}_1895.csv").open(encoding="utf8", newline="") as stream:
        source_rows = list(csv.DictReader(stream))
    rows = {row["source_unit_id"]: row for row in source_rows}
    with (directory / "census_geography.csv").open(encoding="utf8", newline="") as stream:
        controls = {row["unit_id"]: int(row["enumerated_1895_05_10"]) for row in csv.DictReader(stream)}
    if len(source_rows) != len(rows) or rows.keys() != controls.keys() or any(
        row["observed_date"] != "1895-05-10" or int(row["observed_total"]) != controls[key]
        or sum(int(row[field]) for field in (*fields, unknown_field)) != controls[key]
        for key, row in rows.items()
    ):
        raise ValueError(f"Argentina's {dimension} returns do not match the 1895 enumerated geography")
    if dimension == "literacy" and any(
        sum(int(row[field]) for field in fields) != int(row["population_6_and_over"]) for row in rows.values()
    ):
        raise ValueError("Argentina's adult and child literacy counts do not match the age-six-plus control")
    used = set()
    for pool_id, pool in pools.items():
        if pool.get("subdivision_of") != "argentina_1900" or pool.get("geographically_unlocated"):
            continue
        units = pool["source_unit_ids"]
        if used.intersection(units):
            raise ValueError(f"{pool_id}: overlapped Argentine {dimension} source rows")
        used.update(units)
        yield pool_id, dimension, distribution(
            pool["population_value"], classification=f"argentina_1895_reported_{dimension}",
            source=source, date="1895-05-10", observed_unit="|".join(units),
            scope="Persons individually enumerated in the matching census jurisdiction or combined area.",
            locator=locator,
            total=sum(controls[unit] for unit in units),
            observed_counts={label: sum(int(rows[unit][field]) for unit in units)
                             for field, label in fields.items()},
            unknown=sum(int(rows[unit][unknown_field]) for unit in units),
            definition=definition, method=method,
        )
    if used != rows.keys():
        raise ValueError(f"Argentina {dimension} allocation does not cover the disjoint source jurisdictions")


def argentine_occupation(pools, version):
    directory = COLLECTIONS / "argentina_age_1895_1914"
    fields = {
        "i_produccion_de_la_materia_prima": "Producción de la materia prima",
        "ii_producciones_industriales": "Producciones industriales",
        "iii_comercio": "Comercio",
        "iv_transportes": "Transportes",
        "vi_personal_de_servicio": "Personal de servicio",
        "vii_defensa_del_pais": "Defensa del país",
        "viii_administracion_publica": "Administración pública",
        "ix_cultos": "Cultos",
        "x_jurisprudencia": "Jurisprudencia",
        "xi_profesiones_sanitarias": "Profesiones sanitarias",
        "maestros_de_escuela_xii": "Maestros de escuela",
        "xiii_bellas_artes": "Bellas artes",
        "xiv_letras_y_ciencias": "Letras y ciencias",
        "xv_profesiones_ambulantes": "Profesiones ambulantes",
        "xvi_personal_de_fatiga_que_no_tienen_trabajo_fijo": "Personal de fatiga sin trabajo fijo",
    }
    admitted_fields = {
        "iii_comercio": "admitted_iii",
        "vi_personal_de_servicio": "admitted_vi",
        "xv_profesiones_ambulantes": "admitted_xv",
        "xvi_personal_de_fatiga_que_no_tienen_trabajo_fijo": "admitted_xvi",
    }
    with (directory / "census_geography.csv").open(encoding="utf8", newline="") as stream:
        controls = {row["unit_id"]: int(row["enumerated_1895_05_10"]) for row in csv.DictReader(stream)}
    with (directory / "occupation_1895.csv").open(encoding="utf8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    if version >= 34:
        with (directory / "occupation_1895_expansion.csv").open(encoding="utf8", newline="") as stream:
            rows.extend(csv.DictReader(stream))
    if version >= 35:
        for group in ("andes", "north", "tucuman_salta"):
            with (directory / f"occupation_1895_v35_{group}.csv").open(encoding="utf8", newline="") as stream:
                rows.extend(csv.DictReader(stream))
    by_source = {}
    consumed = set()
    for row in rows:
        unit_id = row["source_unit_id"]
        total = int(row["observed_total"])
        eligible = int(row["population_14_and_over"])
        if unit_id in by_source or total != controls[unit_id] or not row["locator"]:
            raise ValueError(f"{unit_id}: occupation scope differs from the individually enumerated region")
        admitted = {field: int(row.get(column, row[field])) for field, column in admitted_fields.items()}
        if (row["observed_date"] != "1895-05-10" or eligible + int(row["outside_tabulated_scope"]) != total
                or sum(int(value) for field, value in row.items()
                       if field.partition("_")[0] in {"i", "ii", "iii", "iv", "v", "vi", "vii", "viii",
                                                        "ix", "x", "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii"})
                + int(row["subtotal_shortfall"]) != eligible
                or int(row["maestros_de_escuela_xii"]) + int(row["estudiantes_xii"]) != int(row["xii_instruccion_y_educacion"])
                or any(not 0 <= value <= int(row[field]) for field, value in admitted.items())):
            raise ValueError(f"{unit_id}: original census professions and eligibility controls differ")
        owners = int(row["hacendados_i"])
        occupations = {label: admitted.get(field, int(row[field])) for field, label in fields.items()}
        occupations[fields["i_produccion_de_la_materia_prima"]] -= owners
        unknown = int(row["observed_unknown"])
        if sum(occupations.values()) + unknown != total or any(count < 0 for count in occupations.values()):
            raise ValueError(f"{unit_id}: admitted principal occupations do not close")
        by_source[unit_id] = dict(total=total, occupations=occupations, owners=owners, unknown=unknown,
                                  locator=row["locator"])
    for unit_id, scope in pools.items():
        members = scope.get("source_unit_ids", ())
        if not members or not any(member in by_source for member in members) or "endpoint_values" not in scope:
            continue
        if not all(member in by_source for member in members) or consumed.intersection(members):
            raise ValueError(f"{unit_id}: Argentine occupational data leave an unmatched or overlapping scope")
        consumed.update(members)
        source = [by_source[member] for member in members]
        total = sum(row["total"] for row in source)
        if total != scope["endpoint_values"][0]:
            raise ValueError(f"{unit_id}: combined occupation denominator differs from the 1895 opening endpoint")
        occupations = {label: sum(row["occupations"][label] for row in source) for label in fields.values()}
        owners = sum(row["owners"] for row in source)
        count = scope["population_value"]
        metadata = dict(
            source="ar_census_1895_principal_occupation", date="1895-05-10",
            observed_unit=unit_id, scope="Present persons aged 14 or older in the matched jurisdiction. "
                                         "The all-age census population is the denominator for opening shares.",
            locator=" / ".join(row["locator"] for row in source), total=total,
            method=SHARE_METHOD + " These are same-area 1895 proxies. Changes by January 1900 are unquantified.",
        )
        yield unit_id, "occupation", distribution(
            count, classification="argentina_1895_reported_principal_occupation",
            observed_counts=occupations, unknown=sum(row["unknown"] for row in source),
            definition="One enumerated principal earning activity per person. Under-14s, property "
                       "owners, rentiers, students, unpaid work without a reported occupation, "
                       "ambiguous categories and unresolved subtotal differences remain unassigned.",
            **metadata,
        )
        if owners:
            yield unit_id, "class", distribution(
                count, classification="argentina_1895_reported_estate_owners",
                observed_counts={"Hacendados": owners}, unknown=total - owners,
                definition="Residents enumerated in the Hacendados (rural estate owner) category. "
                           "Other forms of ownership and social status remain unassigned.",
                **metadata,
            )
    if consumed != by_source.keys():
        raise ValueError("Argentine occupation sources have no exclusive opening account")


def java_residency_registration(pools):
    labels = {
        "europeanen": "Europeans and legally assimilated",
        "chineezen": "Chinese registration",
        "arabieren": "Arab registration",
        "andere_vreemde_oosterlingen": "Other Foreign Oriental registration",
        "inlanders": "Indigenous registration",
    }
    for unit_id, unit in pools.items():
        if unit.get("statistical_parent") != JAVA_MADOERA:
            continue
        yield unit_id, "legal_estate", dict(
            classification_id="java_madoera_colonial_registration",
            source_ids=unit["source_ids"], observed_date=unit["source_dates"][-1],
            observed_unit_id=unit_id, observed_scope=unit["scope"], locator=unit["locator"],
            observed_total=unit["endpoint_values"][-1], observed_unknown=0, method=unit["method"],
            definition="Contemporary colonial legal registration. The labels do not establish language, "
                       "ethnic identity, religion, occupation or socioeconomic status.",
            counts={labels[key]: value for key, value in unit["registration_counts"].items() if value}, unknown=0,
        )


def egyptian_census_literacy(pools, version):
    source = "egypt_census_1907_age_and_literacy"
    units = {"egy_madina_cairo", "egy_madina_alexandria"}
    controls = egypt_age_sex_controls()
    if version >= 36:
        earlier_literacy = {"egy_markaz_itsa", "egy_markaz_sinuris", "egy_mudiriya_jirja"}
        units.update((controls.keys() & pools.keys()) - earlier_literacy)
    with (COLLECTIONS / "egypt_age_1907" / "table_xi_opening_age_sex.csv").open(encoding="utf8", newline="") as stream:
        table = defaultdict(list)
        for row in csv.DictReader(stream):
            table[row["unit_id"]].append(row)
    for unit_id in sorted(units):
        rows = table[unit_id]
        total, = (row for row in rows if row["age_label"] == "total")
        outside, = (row for row in rows if row["age_label"] == "0-4")
        eligible = [row for row in rows if row["age_label"] not in ("total", "0-4")]
        counts = {
            label: sum(int(row[f"{sex}_reported_{label.lower()}"]) for row in eligible for sex in ("male", "female"))
            for label in ("Literate", "Illiterate")
        }
        control = int(controls[unit_id]["table_5_person_count"])
        omitted = control - int(total["person_count"])
        pool = pools[unit_id]
        if control != pool["endpoint_values"][-1] or omitted != int(controls[unit_id]["omitted_person_count"]):
            raise ValueError(f"{unit_id}: the Egypt literacy and population controls differ")
        yield unit_id, "literacy", distribution(
            pool["population_value"], classification="egypt_1907_reported_literacy_age_five_and_older",
            source=source, date=total["observation_date"], observed_unit=unit_id, scope=pool["scope"],
            locator=f"1907 census, Table XI, printed p. {total['printed_page']}.",
            total=control, observed_counts=counts, unknown=int(outside["person_count"]) + omitted,
            definition=("Reported literacy of residents aged five and older. People under five and people omitted "
                        "from Table XI are unassigned. Shares use each area's same-scope all-age Table V denominator. "
                        "Changes between the opening date and the 1907 census are unquantified."),
        )


def ottoman_registered_religion(pools, observations):
    for row in observations:
        unit = row["unit_id"]
        if row["source_id"] != OTTOMAN_REGISTRATION_SOURCE or unit not in pools:
            continue
        total = row["population_value"]
        if total != pools[unit]["population_value"]:
            raise ValueError(f"{unit}: Ottoman religion counts require the original register population")
        yield unit, "religion", distribution(
            total, classification="ottoman_1897_reported_binary_religion", source=row["source_id"],
            date=row["date"], observed_unit=unit, scope=row["definition"], locator=row["locator"], total=total,
            observed_counts=row["registration_religion"], unknown=0,
            definition=("Muslim and non-Muslim are the two reported register classes. The non-Muslim class "
                        "combines multiple communities. The register omits residents and dates vary by locality."),
            method="Carry the two published registration counts at original scale to 1900-01-01.",
        )


def romanian_distribution(pools, filename, dimension, classification, columns, definition,
                          *, unknown_column=None, counties=None):
    path = COLLECTIONS / "romania" / "raw" / filename
    units = set()
    with path.open(encoding="utf8", newline="") as stream:
        for row in csv.DictReader(stream):
            unit = row["unit_id"]
            total = int(row["observed_total"])
            pool = pools[unit]
            if unit in units or row["observed_month"] != "1899-12" or total != pool["population_value"]:
                raise ValueError(f"{unit}: Romanian {dimension} differs from the stable population control")
            if counties is not None:
                control = counties[unit]
                if row["parent_id"] != control["parent_id"] or pool["statistical_parent"] != control["parent_id"]:
                    raise ValueError(f"{unit}: Romanian {dimension} differs from the census county scope")
            if "male_total" in row and total != int(row["male_total"]) + int(row["female_total"]):
                raise ValueError(f"{unit}: Romanian {dimension} differs from the census sex controls")
            units.add(unit)
            yield unit, dimension, distribution(
                total, classification=classification, source=ROMANIA_CENSUS_SOURCE,
                date=row["observed_month"], observed_unit=unit, scope=f"{row['source_name']}, stable population",
                locator=row["locator"], total=total,
                observed_counts={label: int(row[column]) for column, label in columns.items()},
                unknown=int(row[unknown_column]) if unknown_column else 0, definition=definition,
                method="Carry December census counts at original scale to January 1. Census dates varied locally.",
            )
    if counties is not None and units != counties.keys():
        raise ValueError(f"Romanian {dimension} does not cover the census counties")


def romanian_structure(pools, version):
    counties = romanian_county_controls() if version >= 36 else None
    religion_file = ("romania_1899_county_religion_table_iva.csv" if counties is not None
                     else "romania_1899_religion_table_iva.csv")
    yield from romanian_distribution(
        pools, religion_file, "religion", "romania_1899_reported_religion",
        {"ortodoxa": "Orthodox", "mozaica": "Jewish", "catolica": "Catholic", "protestanta": "Protestant",
         "mahometana": "Muslim", "armeana": "Armenian", "lipovana": "Lipovan"},
        "Seven named census religions. The joint other-or-unknown column remains unassigned.",
        unknown_column="alta_si_necunoscuta", counties=counties,
    )
    if counties is not None:
        yield from romanian_distribution(
            pools, "romania_1899_county_literacy_table_va.csv", "literacy", "romania_1899_reported_literacy_age_7_plus",
            {"read_and_write_7_and_over": "Can read and write",
             "neither_read_nor_write_7_and_over": "Can neither read nor write"},
            "Published literacy status of stable residents aged seven and over. People outside the table remain unassigned.",
            unknown_column="outside_tabulated_scope", counties=counties,
        )
        yield from romanian_distribution(
            pools, "romania_1899_county_residence_table_i.csv", "residence", "romania_1899_administrative_residence",
            {"urban": "Urban", "rural": "Rural"},
            "Stable residents of urban and rural communes, using the 1899 census administrative classification.",
            counties=counties,
        )
    if version >= 37:
        yield from romanian_distribution(
            pools, "romania_1899_county_marital_status_table_iii.csv", "marital_status", "romania_1899_reported_marital_status",
            {"single": "Children and never married", "married": "Married", "widowed": "Widowed", "divorced": "Divorced"},
            "Marital status of stable residents. Children and never-married adults share one source category.",
            unknown_column="unknown", counties=counties,
        )


def prussian_census_occupation(pools, version):
    path = COLLECTIONS / "cities_europe" / "prussia_1895_occupation.csv"
    with path.open(encoding="utf8", newline="") as stream:
        row, = csv.DictReader(stream)
    labels = {
        "a": "Agriculture, forestry, hunting and fishing",
        "b": "Mining, manufacturing and construction",
        "c": "Trade, transport and insurance",
        "d": "Domestic service and intermittent wage labour",
        "e": "Military, court, civil and religious service and liberal professions",
        "g": "Domestic servants living in the employer's household",
    }
    counts = {label: int(row[f"occupation_{code}"]) for code, label in labels.items()}
    unknown = int(row["unknown"])
    if (sum(counts.values()) != int(row["occupation_total"]) or
            unknown != int(row["without_stated_occupation_f"]) + int(row["dependents_without_primary_occupation_h"])):
        raise ValueError("Prussian occupational classes differ from the official census controls")
    unit = row["unit_id"]
    marginal = distribution(
        pools[unit]["population_value"], classification="prussia_1895_reported_principal_occupation",
        source=row["source_id"], date=row["date"], observed_unit=unit,
        scope="Kingdom of Prussia, all persons present", locator=row["source_table"],
        total=int(row["population"]), observed_counts=counts, unknown=unknown,
        definition=("Principal occupations and separately tabulated live-in domestic servants. The census category "
                    "without a stated occupation and non-working dependents remain unassigned. Changes since June 1895 "
                    "are unquantified."),
    )
    if version >= 38:
        industry = labels["b"]
        path = path.with_name("prussia_1895_industrial_employment_position.csv")
        detailed_labels = {
            "a": "Industry: independent operators and managers",
            "b1": "Industry: inspectors, engineers and chemists",
            "b2": "Industry: supervisors and foremen",
            "b3": "Industry: clerical and commercial staff",
            "c1": "Industry: participating family members",
            "c2": "Industry: trained workers and apprentices",
            "c3": "Industry: assistants, stokers, drivers and attendants",
        }
        with path.open(encoding="utf8", newline="") as stream:
            detail = list(csv.DictReader(stream))
        if (len(detail) != len(detailed_labels) or {cell["group_code"] for cell in detail} != detailed_labels.keys()
                or any(cell["unit_id"] != unit or cell["date"] != row["date"] or cell["source_id"] != row["source_id"]
                       or int(cell["male"]) + int(cell["female"]) != int(cell["persons"]) for cell in detail)):
            raise ValueError("Prussian industrial occupations have different dates, scopes or controls")
        industry_counts = {detailed_labels[cell["group_code"]]: int(cell["persons"]) for cell in detail}
        if sum(industry_counts.values()) != counts[industry]:
            raise ValueError("Prussian industrial occupations do not close to category B")
        industrial_opening = marginal["counts"].pop(industry)
        marginal["counts"].update(distribution(
            industrial_opening, classification=marginal["classification_id"], source=row["source_id"],
            date=row["date"], observed_unit=unit, scope=marginal["observed_scope"], locator=detail[0]["source_table"],
            total=counts[industry], observed_counts=industry_counts, unknown=0, definition=marginal["definition"],
        )["counts"])
        marginal["locator"] += f"; {detail[0]['source_table']}"
        marginal["method"] += " Divide the resulting industry category using its seven independently tabulated roles."
        marginal["definition"] += " Industrial managers and independent operators share one published role."
    yield unit, "occupation", marginal


def surigao_occupation(pool):
    with (COLLECTIONS / "philippines_surigao_opening" / "occupation.csv").open(encoding="utf8", newline="") as source:
        rows = list(csv.DictReader(source))
    counts = {row["label"]: int(row["male"]) + int(row["female"])
              for row in rows if row["role"] == "occupation"}
    unknown, = (int(row["male"]) + int(row["female"]) for row in rows if row["role"] == "unassigned")
    yield pool["unit_id"], "occupation", distribution(
        pool["population_value"], classification="ph_surigao_1903_gainful_occupation",
        source=pool["source_id"], date=pool["source_dates"][-1], observed_unit="ph_1903_surigao",
        scope=pool["scope"], locator="Vol. II, Table 53, printed p. 866, Surigao",
        total=pool["endpoint_values"][-1], observed_counts=counts, unknown=unknown,
        definition=("Five published groups of gainful occupations. The denominator is the all-age main "
                    "schedule. The census combines people without gainful occupations and unknown occupation "
                    "in one column. That column remains unassigned. Change from 1900 is unquantified."),
    )


def french_department_social(pools):
    folder = COLLECTIONS / "cities_europe"
    columns = ("Pêches, forêts et agriculture", "Industrie", "Commerce", "Service domestique", "Professions libérales")
    with (folder / "france_1901_department_occupation.csv").open(encoding="utf8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    with (folder / "france_1896_1901_department_residence.csv").open(encoding="utf8", newline="") as stream:
        residences = list(csv.DictReader(stream))
    residence_by_unit = {row["unit_id"]: row for row in residences}
    expected = {unit for unit in pools if unit.startswith("administrative_region:france_")
                and not unit.startswith("administrative_region:france_arrondissement_")}
    if (len(rows) != 87 or len(residences) != 87 or {row["unit_id"] for row in rows} != expected
            or residence_by_unit.keys() != expected):
        raise ValueError("The French returns must match all 87 historical departments")
    for row in rows:
        unit = row["unit_id"]
        pool = pools[unit]
        counts = {label: int(row[label]) for label in columns}
        total = int(row["legal_population_1901"])
        reported = sum(counts.values())
        endpoints = [int(row["legal_population_1896"]), total]
        active = reported + int(row["occupation_unspecified"]) + int(row["active_unreconciled"])
        if (pool["endpoint_values"] != endpoints or reported != int(row["occupation_total"])
                or active != int(row["active_population"]) or row["source_id"] != "insee_sgf_censuses"):
            raise ValueError(f"French occupational return differs from the local census control: {unit}")
        yield unit, "occupation", distribution(
            pool["population_value"], classification="france_1901_department_reported_occupation",
            source=row["source_id"], date=row["observed_date"], observed_unit=row["department_code"],
            scope=row["department"], locator=row["source_locator"], total=total, observed_counts=counts,
            unknown=int(row["unknown_legal_proxy"]),
            definition=("Five reported occupational groups, including people temporarily out of work with a recorded "
                        "sector. The liberal professions group includes public services. Dependants, occupation not "
                        "reported, and unreconciled active census cells remain unassigned."),
            method=SHARE_METHOD + " Use each department's legal population as the proxy denominator for its occupational "
                                  "counts. No allocation is made within split departments. Coverage and change since "
                                  "1 January 1900 are unquantified.",
        )
        residence = residence_by_unit[unit]
        dates = [residence["date_1896"], residence["date_1901"]]
        early = {label: int(residence[f"{label.lower()}_population_1896"]) for label in ("Urban", "Rural")}
        late = {label: int(residence[f"{label.lower()}_population_1901"]) for label in early}
        if ([sum(early.values()), sum(late.values())] != endpoints
                or [int(residence[f"legal_population_{year}"]) for year in (1896, 1901)] != endpoints
                or dates[1] != row["observed_date"] or residence["source_id"] != row["source_id"]):
            raise ValueError(f"French residence return differs from the local census control: {unit}")
        fraction = opening_fraction(dates)
        quotas = {label: early[label] * (1 - fraction) + late[label] * fraction for label in early}
        opening = pool["population_value"]
        modeled = apportion({label: value * opening / sum(quotas.values()) for label, value in quotas.items()}, opening)
        yield unit, "residence", dict(
            classification_id="france_1896_1901_department_census_residence", source_ids=[residence["source_id"]],
            observed_date=dates[1], observed_unit_id=residence["department_code"], observed_scope=residence["department"],
            locator=residence["source_locator"], observed_total=total, observed_unknown=0,
            method=f"Interpolate each department's urban and rural totals from {dates[0]} to {dates[1]}. "
                   "Use largest remainders within the opening department. Constituent districts are unassigned.",
            definition="The entire population of each commune is urban if its administrative seat has over 2,000 "
                       "people living in a concentrated settlement. Seine is entirely urban by the census exception.",
            counts={label: count for label, count in modeled.items() if count}, unknown=0,
        )


def opening_social(opening_groups, observations, *, version):
    """Return independent person distributions at each source's published scope."""
    pools = {
        unit["unit_id"]: unit
        for group in opening_groups
        for unit in [*(group["units"] or [group]), *group.get("statistical_aggregates", [])]
    }
    regions = {}
    marginals = chain(russian_structure(pools), india_structure(pools, version), india_occupation(pools, version),
                      india_princely_residence(pools, distribution), travancore_language(pools, distribution),
                      madras_states_religion(pools, distribution, INDIA_TABLES["7"]), canada_structure(pools),
                      united_states_structure(pools, distribution), netherlands_structure(pools),
                      netherlands_occupation(pools), england_wales_housing(pools))
    if version >= 16:
        marginals = chain(
            marginals,
            prussian_marital_status(pools),
            austrian_social_distribution(
                pools, "religion.csv", "religion", AUSTRIAN_RELIGION_COLUMNS,
                "ah_cisleithania_census_1900_religion", "Vol. 63, part 2, Table V, printed pp. 55–56",
                "Reported religious confession, including separate categories for other and no confession. All persons present.",
            ),
            austrian_social_distribution(
                pools, "marital.csv", "marital_status", AUSTRIAN_MARITAL_COLUMNS,
                "ah_cisleithania_census_1900_marital", "Vol. 63, part 2, Table VIII, printed p. 150",
                "Civil status of all persons present. The never-married category includes children.",
            ),
            austrian_social_distribution(
                pools, "usual_language.csv", "language", AUSTRIAN_LANGUAGE_COLUMNS,
                "ah_cisleithania_census_1900_language", "Vol. 63, part 2, Table VI, printed pp. 72–73",
                "Usual language of persons covered by the census language classification. "
                "Foreign subjects had no reported language. The classification does not establish cultural identity.",
                unknown_column="foreign_subjects_language_unknown", classification="austria_1900_usual_language",
            ),
            austrian_social_distribution(
                pools, "literacy.csv", "literacy", AUSTRIAN_LITERACY_COLUMNS,
                "ah_cisleithania_census_1900_literacy_locality", "Vol. 63, part 2, Table VII, printed pp. 130–133",
                "The original reading and writing categories cover all persons present, including children.",
            ),
            austrian_social_distribution(
                pools, "locality_population_size.csv", "residence", AUSTRIAN_LOCALITY_COLUMNS,
                "ah_cisleithania_census_1900_literacy_locality", "Vol. 63, part 2, Table VII, printed pp. 130–133",
                "Persons present by population size of their census locality. The bins do not designate an urban or rural legal status.",
                classification="austria_1900_locality_population_size",
            ),
        )
    if version >= 17:
        marginals = chain(marginals, england_wales_occupation(pools))
    if version >= 18:
        marginals = chain(
            marginals,
            hungarian_crown_social(pools, "religion", HUNGARIAN_RELIGION_COLUMNS,
                                  "Reported civilian confession. The local military balance is unassigned. "
                                  "The published other category remains a counted group."),
            hungarian_crown_social(pools, "language", HUNGARIAN_LANGUAGE_COLUMNS,
                                  "Reported civilian mother tongue. The local military balance is unassigned. "
                                  "The published other category remains a counted group."),
            hungarian_crown_social(pools, "occupation", HUNGARIAN_OCCUPATION_COLUMNS,
                                  "Reported own occupational group among people with an independent livelihood. "
                                  "Dependants, persons living from capital or pensions, and other or unknown occupations "
                                  "remain unassigned. The armed forces census category is not a military roster."),
        )
    if version >= 19:
        marginals = chain(
            marginals, canada_occupation(pools),
            german_state_marital_status(
                pools, "saxony_census_1900", classification="saxony_1900_reported_marital_status",
                source="de_saxony_1900_age_marital", scope="Kingdom of Saxony, population present",
                locator="Table 3, printed p. 160, all ages row",
            ),
            german_state_marital_status(
                pools, "wuerttemberg_census_1900", classification="wuerttemberg_1900_reported_marital_status",
                source="de_wuerttemberg_1900_age_marital", scope="Kingdom of Württemberg, population present",
                locator="Table D, printed p. 16, all ages, entire kingdom",
            ),
        )
    if version >= 20:
        marginals = chain(marginals, german_state_marital_status(
            pools, "baden_census_1900", classification="baden_1900_reported_marital_status",
            source="de_baden_1900_age_marital", scope="Grand Duchy of Baden, population present",
            locator="Table II.A.1d, printed p. 40, all ages",
        ), hungarian_crown_work_status(pools))
    if version >= 21:
        italian_marital_unit = ITALIAN_CIVIL_STATUS_SCOPE if version >= 22 else "kingdom_of_italy"
        marginals = chain(marginals, italy_marital_status(pools[italian_marital_unit]), mexico_census_social(pools))
    if version >= 22:
        marginals = chain(marginals, canada_reported_origin(pools))
    if version >= 23:
        marginals = chain(marginals, italian_settlement(pools))
    if version >= 24:
        marginals = chain(marginals, italian_occupation(pools), italian_literacy(pools),
                          italian_registered_property(pools), italian_industrial_position(pools),
                          egyptian_provincial_religion(pools, observations),
                          spain_marital_status(pools, observations, version), agra_oudh_religion(pools, observations, version))
    if version >= 25:
        marginals = chain(
            marginals, egyptian_faiyum_social(pools, observations),
            belgian_provincial_distribution(
                pools, "spoken_languages.csv", "language", "belgium_1900_reported_spoken_national_languages",
                "be_census_1900_age_and_spoken_languages", "Tome I(c), printed p. 629",
                "Eight mutually exclusive combinations of three national languages reported as spoken. "
                "The explicit none category does not establish mother tongue, other languages or nationality.",
            ), belgian_provincial_distribution(
                pools, "marital_status.csv", "marital_status", "belgium_1900_reported_marital_status",
                "be_census_1900_marital_and_citizenship", "Tome I(b), printed pp. 370–371",
                "All ages, with four separately reported civil status categories.",
            ), brazilian_state_distribution(
                pools, "marital_status.csv", "marital_status", "brazil_1900_reported_marital_status",
                "br_dge_1916_1900_marital", {"single": "Solteiros", "married": "Casados", "widowed": "Viuvos"},
                "Reported civil status. The Federal District is outside this allocation.",
            ), brazilian_state_distribution(
                pools, "literacy.csv", "literacy", "brazil_1900_reported_literacy",
                "br_dge_1929_1900_literacy", {"literate": "Sabem ler e escrever", "illiterate": "Não sabem ler nem escrever"},
                "All ages. The Federal District return in this publication is from 1906 and is outside this allocation.",
            ),
        )
    if version >= 26:
        marginals = chain(marginals, portuguese_district_social(pools), brazilian_state_religion(pools))
    if version >= 27:
        marginals = chain(marginals, uk_constituent_occupation(pools),
                          egyptian_provincial_work_and_instruction(pools, observations),
                          bengal_district_literacy(pools, observations, version))
    if version >= 29:
        marginals = chain(marginals, india_language(pools))
    if version >= 30:
        marginals = chain(marginals, cochin_language(pools, distribution))
    if version >= 31:
        marginals = chain(marginals, argentine_local_distribution(
            pools, "religion", {
                "catolicos": "Católicos",
                "protestantes_todas_las_confesiones": "Protestantes, todas las confesiones",
                "israelitas": "Israelitas",
            }, "otras_religiones",
            source="ar_census_1895_religion", locator="Tomo II, Cuadro XIX a/b, pp. CLXXVIII–CLXXIX.",
            definition="Published census religion. The original other column mixes other religions "
                       "and persons without a reported religion. It remains unassigned.",
            method=SHARE_METHOD + " The enumerator asked about religion only where the person "
                   "was thought to be non-Catholic. Bias from that rule and changes since the census are unquantified.",
        ))
    if version >= 32:
        marginals = chain(marginals, argentine_local_distribution(
            pools, "literacy", {
                "saben_leer_y_escribir": "Saben leer y escribir",
                "no_saben_leer_ni_escribir": "No saben leer ni escribir",
            }, "outside_tabulated_scope",
            source="ar_census_1895_literacy", locator="Tomo II, Cuadro XIII, printed p. CLXXIII.",
            definition="Two published literacy categories for residents aged six and over. "
                       "People outside the eligible age scope are unassigned.",
            method=SHARE_METHOD + " Changes in age composition and literacy from 1895 are unquantified.",
        ))
    if version >= 33:
        marginals = chain(marginals, argentine_occupation(pools, version), java_residency_registration(pools),
                          egyptian_census_literacy(pools, version))
    if version >= 35:
        marginals = chain(marginals, ottoman_registered_religion(pools, observations), romanian_structure(pools, version))
    if version >= 37:
        marginals = chain(marginals, prussian_census_occupation(pools, version), surigao_occupation(pools["ph_1900_surigao_main_population"]))
    if version >= 38:
        marginals = chain(marginals, french_department_social(pools))
    if version >= 39:
        marginals = chain(marginals, bombay_city_social(pools, version))
    for pool_id, dimension, marginal in marginals:
        region = regions.setdefault(pool_id, dict(unit_id=pool_id, opening_total=pools[pool_id]["population_value"],
                                                   marginal_distributions={}))
        if dimension in region["marginal_distributions"]:
            raise ValueError(f"{pool_id}: duplicated {dimension} distribution")
        region["marginal_distributions"][dimension] = marginal
    return dict(version=1, regions=[regions[pool_id] for pool_id in sorted(regions)])
