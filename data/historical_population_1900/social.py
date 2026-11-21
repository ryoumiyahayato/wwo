"""Allocate source-supported resident marginals to exclusive opening pools."""

import csv
import json
import re
from collections import Counter, defaultdict
from itertools import chain
from pathlib import Path

from social_us import united_states_structure


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


def russian_structure(pools):
    path = COLLECTIONS / "russia"
    provinces = {}
    for line in (path / "observations.jsonl").read_text(encoding="utf8").splitlines():
        row = json.loads(line)
        if row["source_id"] == "russia_first_census" and row.get("parent_id") == "ru_census_1897_ex_finland":
            provinces[province_name(row["name"])] = row
    yield from russian_literacy(pools, {row["unit_id"]: row for row in provinces.values()})
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
        if pool_id not in pools:
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


def opening_social(opening_groups):
    """Return independent person distributions on the opening's nonoverlapping leaf accounts."""
    pools = {
        unit["unit_id"]: unit
        for group in opening_groups for unit in (group["units"] or [group])
    }
    regions = {}
    marginals = chain(russian_structure(pools), india_structure(pools), india_occupation(pools), canada_structure(pools),
                      united_states_structure(pools, distribution), netherlands_structure(pools),
                      netherlands_occupation(pools))
    for pool_id, dimension, marginal in marginals:
        region = regions.setdefault(pool_id, dict(unit_id=pool_id, opening_total=pools[pool_id]["population_value"],
                                                   marginal_distributions={}))
        if dimension in region["marginal_distributions"]:
            raise ValueError(f"{pool_id}: duplicated {dimension} distribution")
        region["marginal_distributions"][dimension] = marginal
    return dict(version=1, regions=[regions[pool_id] for pool_id in sorted(regions)])
