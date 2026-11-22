"""Allocate source-supported resident marginals to exclusive opening pools."""

import csv
import json
import re
from collections import Counter, defaultdict
from itertools import chain
from pathlib import Path

from opening import ENGLAND_WALES_OCCUPATION_REMAINDER
from social_russia_marital import russian_marital_status
from social_us import united_states_structure
from social_india_princely import india_princely_residence, madras_states_religion, travancore_language


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


def india_structure(pools):
    tables = json.loads((COLLECTIONS / "india_social_1901" / "census.json").read_text(encoding="utf8"))
    for table, rows in tables.items():
        dimension, classification, source, labels, definition = INDIA_TABLES[table]
        for row in rows:
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


def india_occupation(pools):
    path = COLLECTIONS / "india_occupation_1901" / "occupation_orders.json"
    for row in json.loads(path.read_text(encoding="utf8")):
        pool_id = row["unit_id"]
        pool = pools[pool_id]
        total = row["observed_total"]
        if pool["endpoint_values"][-1] != total:
            raise ValueError(f"{pool_id}: the occupation and opening population controls use different census scopes")
        source, = row["source_ids"]
        yield pool_id, "occupation", distribution(
            pool["population_value"], classification=row["classification_id"], source=source,
            date=row["observed_date"], observed_unit=row["observed_unit_id"], scope=row["observed_scope"],
            locator=row["locator"], total=total, observed_counts=row["observed_counts"],
            unknown=row["observed_unknown"], definition=row["definition"],
        )


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


def opening_social(opening_groups, *, version):
    """Return independent person distributions at each source's published scope."""
    pools = {
        unit["unit_id"]: unit
        for group in opening_groups
        for unit in [*(group["units"] or [group]), *group.get("statistical_aggregates", [])]
    }
    regions = {}
    marginals = chain(russian_structure(pools), india_structure(pools), india_occupation(pools),
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
    for pool_id, dimension, marginal in marginals:
        region = regions.setdefault(pool_id, dict(unit_id=pool_id, opening_total=pools[pool_id]["population_value"],
                                                   marginal_distributions={}))
        if dimension in region["marginal_distributions"]:
            raise ValueError(f"{pool_id}: duplicated {dimension} distribution")
        region["marginal_distributions"][dimension] = marginal
    return dict(version=1, regions=[regions[pool_id] for pool_id in sorted(regions)])
