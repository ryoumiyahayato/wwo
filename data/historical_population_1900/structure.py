"""Build nonadditive demographic observations retaining historical labels and scopes."""
import csv
import json
import re
from collections import defaultdict
from fractions import Fraction
from pathlib import Path

from opening import (
    AGRA_DISTRICT_SOURCE, DATE, EGYPT_COMPARABLE_PROVINCES, EGYPT_FAIYUM_SOURCES, ENGLAND_WALES_OCCUPATION_REMAINDER, ITALIAN_CIVIL_STATUS_SCOPE,
    BENGAL_DISTRICT_SOURCE, MADRAS_STATES_REMAINDER, SPANISH_CIVIL_STATUS_SCOPE,
    apportion, opening_fraction,
)

HERE=Path(__file__).resolve().parent/"collections"
AGE_SOURCES = HERE / "age_sex"
OPENING_METHOD = (
    "Hold the census age-by-sex shares at 1900-01-01. Apply the source ratios to "
    "the anonymous opening balance using integer largest remainders."
)
SEX_COUNTS = ("male", "female")
AGE_COUNTS = ("both", *SEX_COUNTS)
RUSSIAN_CENSUS_REGIONS = (
    ("1", "european_russia", 1, 50),
    ("2", "vistula_provinces", 51, 60),
    ("3", "caucasus", 61, 71),
    ("4", "siberia", 72, 80),
    ("5", "central_asia", 81, 89),
)

def read_csv(path):
    with path.open(encoding="utf8",newline="") as f:
        return list(csv.DictReader(f))

def austrian_age_panels():
    directory = HERE / "austrian_crown_1900"
    broad_bands = ((0, 14), (15, 60), (61, None))
    original_bands = ((0, 10), (11, 20), (21, 30), (31, 40), (41, 50), (51, 60),
                      (61, 70), (71, 80), (81, 90), (91, None))
    opening_bands = ((0, 10), (11, 14), (15, 20), *original_bands[2:])
    tables = []
    pages = {}
    for filename, expected_bands in (("age_sex.csv", broad_bands), ("age_sex_detail.csv", original_bands)):
        territories = {}
        for row in read_csv(directory / filename):
            place = (row["opening_unit_id"], row["source_row"], row["source_name"])
            bands = territories.setdefault(place, {})
            band = (int(row["age_min"]), int(row["age_max"]) if row["age_max"] else None)
            if band in bands:
                raise ValueError(f"Duplicate Austrian census age band: {place} {band}")
            bands[band] = {sex: int(row[sex]) for sex in SEX_COUNTS}
            if row.get("printed_page"):
                pages[place] = row["printed_page"]
        if any(set(bands) != set(expected_bands) for bands in territories.values()):
            raise ValueError(f"Missing Austrian census age band in {filename}")
        tables.append(territories)

    broad, detail = tables
    if len(broad) != 17 or broad.keys() != detail.keys():
        raise ValueError("Austrian age tables describe different territories")
    opening = {}
    for place, bands in detail.items():
        split = {band: bands[band] for band in opening_bands if band in bands}
        split[11, 14] = {}
        split[15, 20] = {}
        for sex in SEX_COUNTS:
            young = broad[place][0, 14][sex] - bands[0, 10][sex]
            older = bands[11, 20][sex] - young
            if young < 0 or older < 0:
                raise ValueError(f"Inconsistent Austrian ages below 21: {place} {sex}")
            split[11, 14][sex] = young
            split[15, 20][sex] = older
            for low, high in broad_bands:
                subtotal = sum(counts[sex] for (start, end), counts in split.items()
                               if start >= low and (high is None or end is not None and end <= high))
                if subtotal != broad[place][low, high][sex]:
                    raise ValueError(f"Austrian age tables do not close: {place} {sex} {(low, high)}")
        opening.setdefault(place[0], {})[place] = split

    for unit_id, territories in opening.items():
        rows = []
        for low, high in opening_bands:
            sex_counts = {sex: sum(counts[low, high][sex] for counts in territories.values()) for sex in SEX_COUNTS}
            label = f"Ages {low}–{high}" if high is not None else f"Ages {low} and over"
            rows.append(dict(label=label, role="band", age_min=low, age_max=high, both=sum(sex_counts.values()), **sex_counts))
        total = dict(label="Population present", role="total", age_min=None, age_max=None,
                     **{key: sum(row[key] for row in rows) for key in AGE_COUNTS})
        names = " + ".join(place[2] for place in territories)
        printed_pages = ", ".join(pages[place] for place in territories)
        yield dict(
            id=f"{unit_id}_1900_age_sex", observed_unit_id=unit_id, opening_unit_id=unit_id, opening_from_version=16,
            broad_observation=False, opening_match_population_endpoint=True,
            observed_date="1900-12-31", source_id="ah_cisleithania_census_1900_ages", published_scope=names,
            locator=f"Vol. 63, part 3, Table II pp. {printed_pages} and Table III p. 46; {names}",
            definition="Persons present. Table II age rows split at age 15 using the same territory and sex in Table III.",
            uncertainty="Year-end census age and sex shares are held on the opening date. Within-year demographic "
                        "change and reporting error are unquantified. The source rows used do not establish single ages.",
        ), [total, *rows]


def hungarian_crown_age_panels():
    by_territory = {}
    for row in read_csv(HERE / "austria_hungary" / "hungarian_crown_age_1900.csv"):
        male, female, civilians_male, civilians_female, civilians, population, military = (
            int(row[column]) for column in ("all_male", "all_female", "civilian_male", "civilian_female",
                                             "civilian_total", "civilian_and_military_total", "military_male")
        )
        if (male != civilians_male + military or female != civilians_female
                or civilians != civilians_male + civilians_female or population != civilians + military):
            raise ValueError(f"Hungarian census age row does not close: {row}")
        low = int(row["age_min"]) if row["age_min"] else None
        high = int(row["age_max"]) if row["age_max"] else None
        by_territory.setdefault(row["unit_id"], []).append(dict(
            label=row["source_age_label"], role="band", age_min=low, age_max=high,
            both=population, male=male, female=female,
        ))

    scopes = {"ah_hungary_including_fiume": ("Hungary including Fiume", 16_838_255),
              "ah_croatia_slavonia": ("Croatia-Slavonia", 2_416_304)}
    if by_territory.keys() != scopes.keys():
        raise ValueError("Hungarian census ages do not cover both territories")
    for unit_id, (name, expected_total) in scopes.items():
        rows = by_territory[unit_id]
        total = dict(role="total", label="Civilian and military population present",
                     age_min=None, age_max=None, **{key: sum(row[key] for row in rows) for key in AGE_COUNTS})
        bands = {(row["age_min"], row["age_max"]) for row in rows}
        if total["both"] != expected_total or len(rows) != 20 or len(bands) != len(rows):
            raise ValueError(f"Hungarian census age coverage differs for {unit_id}")
        yield dict(
            id=f"{unit_id}_1900_age_sex", observed_unit_id=unit_id, observed_date="1900-12-31",
            source_id="ksh_hungarian_statistical_yearbook_1908", published_scope=name,
            broad_observation=unit_id == "ah_hungary_including_fiume",
            locator=f"Section II.A, Table 7, p. 17; Table 5 sex controls, p. 16; {name}",
            definition="Census-night age of civilians and military. The difference between the civilian "
                       "and full age totals is assigned to men because Table 5 places all serving military in the male total.",
            uncertainty="Change between the January opening and the December census is unquantified.",
        ), [total, *rows]



def hungarian_regional_sex():
    controls = {}
    filename = HERE / "austria_hungary" / "hungarian_regional_sex_1890_1900.csv"
    for row in read_csv(filename):
        dates = controls.setdefault(row["unit_id"], {})
        census_date = row["census_date"]
        male, female, total = (int(row[key]) for key in ("all_male", "all_female", "all_total"))
        if (census_date in dates or male != int(row["civilian_male"]) + int(row["military_male"])
                or female != int(row["civilian_female"]) or male + female != total):
            raise ValueError(f"Hungarian regional sex control does not close: {row}")
        dates[census_date] = row | dict(male=male, female=female, both=total)
    return controls


def hungarian_opening_age_models(panels, opening_balances):
    units = {key: unit for key, unit in opening_balances.items()
             if unit.get("control_unit_id") == "ah_lands_of_st_stephen"}
    local = hungarian_regional_sex()
    if local.keys() != units.keys():
        raise ValueError("Hungarian regional sex controls do not cover the opening Crown lands")
    census_dates = ("1890-12-31", "1900-12-31")
    weight = opening_fraction(("1891-01-01", "1901-01-01"))
    for unit_id, unit in units.items():
        dated = local[unit_id]
        if (dated.keys() != set(census_dates)
                or [dated[date]["both"] for date in census_dates] != unit["endpoint_values"]):
            raise ValueError(f"Hungarian sex and population controls differ for {unit_id}")
        earlier, later = (dated[date] for date in census_dates)
        population = unit["population_value"]
        opening_sex = apportion({sex: earlier[sex] * (1 - weight) + later[sex] * weight for sex in SEX_COUNTS}, population)
        whole = "ah_hungary_including_fiume"
        territory = unit_id if unit_id == "ah_croatia_slavonia" else whole
        panel, (control, *bands) = panels[f"{territory}_1900_age_sex"]
        by_sex = {
            sex: apportion({i: Fraction(opening_sex[sex] * band[sex], control[sex])
                            for i, band in enumerate(bands)}, opening_sex[sex])
            for sex in SEX_COUNTS
        }
        allocated = [
            band | dict(male=by_sex["male"][i], female=by_sex["female"][i],
                        both=by_sex["male"][i] + by_sex["female"][i])
            for i, band in enumerate(bands)
        ]
        source_name, page = later["source_region"], later["source_print_page"]
        model = panel | dict(
            observed_date=DATE, observed_unit_id=unit_id,
            locator=f"{panel['locator']}; 1900 census Part X, Table 15, p. {page}, {source_name}",
            opening_method="Interpolate local male and female census totals from the 1890 and 1900 census nights. "
                           "For each sex, apply its age shares from the December 1900 source territory, "
                           "preserving the unknown age class. Round persons by largest remainders.",
            uncertainty=panel["uncertainty"] + (
                " Age shares below the Croatia-Slavonia reporting level are unobserved."
                if territory == unit_id else
                " The age shares are for Hungary including Fiume. Local age differences are unquantified."
            ),
        )
        yield opening_age_group(model, [control | dict(both=population, **opening_sex), *allocated],
                                unit_id, population)


def province_key(name):
    return re.sub(r"\s+(губерния|область|обл\.?)$","",name.strip().casefold())

def dimensions(population):
    age_panels = age_sex_panels()
    russian_ages = {
        (panel.get("russian_region_parameter", "0"), row["label"]): (panel["id"], row)
        for panel, rows in age_panels if panel["source_id"] == "rus_age_97"
        for row in rows
    }
    provinces={province_key(r["name"]): r for r in population if r.get("source_id")=="russia_first_census"
               and r.get("parent_id")=="ru_census_1897_ex_finland"}
    result=[]
    for raw in read_csv(HERE/"russia"/"structure.csv"):
        tab=raw["source_table"]
        param=raw["region_parameter"]
        name=raw["published_scope"]
        province=provinces.get(province_key(name))
        scope=(province["unit_id"] if province else "ru_census_1897_ex_finland" if param=="0" else f"{tab}:reg:{param}")
        cells={k:int(raw[k]) if raw[k].isdigit() else raw[k] or None for k in ["male","female","both","literate_male","literate_female","literate_both"]}
        observation = dict(unit_id=scope,published_scope=name,date="1897-02-09",source_id=tab,
            locator=f"{tab}.php?reg={param}, row {raw['row']}",category=raw["category"],subcategory=raw["subcategory"] or None,
            dialect=raw["dialect"] or None,measure="published persons",values=cells,
            definition={"rus_lan_97":"Reported mother tongue; overlapping headings, languages and dialects.",
                        "rus_rel_97":"Religious denomination reported by the original census.",
                        "rus_sos_97":"Legal estate (soslovie) reported by the original census.",
                        "rus_age_97":"Age, sex and literacy. Printed subtotals overlap single-year ages."}[tab])
        age_row = russian_ages.get((param, raw["category"])) if tab == "rus_age_97" else None
        if age_row is not None:
            panel_id, row = age_row
            observation.update(
                dimension="age_by_sex", panel_id=panel_id, row_role=row["role"],
                age_min=row["age_min"], age_max=row["age_max"],
            )
        result.append(observation)
    occupations=read_csv(HERE/"demography"/"occupation.csv")
    for field in ["male","female","total"]:
        if sum(int(r[field]) for r in occupations[2:])!=int(occupations[1][field]):
            raise ValueError("US occupation groups do not close")
    for r in occupations:
        result.append(dict(unit_id="us_twelfth_census_entire_enumeration",date="1900-06-01",source_id="us_occupation_special_report",
            locator="General Tables no. 1, pp. 7–8, "+r["category"],category=r["category"],measure="persons",
            values={k:int(r[k]) for k in ("total","male","female")},definition="Age 10+. Includes continental US, Alaska, Hawaii, and US military/naval service abroad including employees. Distinct from continental state controls."))
    for date,residents,present,households in [("1888-12-01",2917754,2933334,637835),("1900-12-01",3315443,3325023,728920)]:
        result.append(dict(unit_id="swiss_confederation",date=date,source_id="swiss_federal_census_comparison_1911",
            locator="I, printed p. 104, Switzerland annual rows, cols. 9–10",
            category="households and persons",values=dict(households=households,ordinary_residents=residents,persons_present=present),
            definition="Published household count, usual residents and de facto population are distinct. Population in private households is not identified separately; household size is unknown."))
    for panel, rows in age_panels:
        if panel["source_id"] == "rus_age_97" or "component_panels" in panel:
            continue
        for row in rows:
            result.append(dict(
                unit_id=panel["observed_unit_id"], published_scope=panel["published_scope"],
                date=panel["observed_date"], source_id=panel["source_id"],
                locator=f"{panel['locator']}, {row['label']}", category=row["label"],
                measure=panel.get("measure", "published persons"),
                values={key: row[key] for key in ("both", "male", "female")},
                definition=panel["definition"], dimension=panel.get("dimension", "age_by_sex"),
                panel_id=panel["id"], row_role=row["role"],
                age_min=row["age_min"], age_max=row["age_max"],
            ))
    for unit_id, dates in hungarian_regional_sex().items():
        for census_date, row in dates.items():
            result.append(dict(
                unit_id=unit_id, published_scope=row["source_region"], date=census_date,
                source_id="ah_hungarian_census_1900_part10",
                locator=f"Census Part X, Table 15, printed p. {row['source_print_page']}",
                dimension="sex", category="Civilian and military persons present",
                values={key: row[key] for key in AGE_COUNTS},
                definition="Male and female census controls. Military persons are included in the male total.",
            ))
    # The family register and the estimated present population have different
    # denominators. Link the published panels for inspection only.
    for collection, relation in (
        ("japan_population_structure", "different_register_and_residence_universes"),
        ("tokyo_occupation_1900", "local_subset_at_other_date_and_population_universe"),
    ):
        path = HERE / collection / "structure.jsonl"
        for line in path.read_text(encoding="utf8").splitlines():
            row = json.loads(line)
            links = ["empire_of_japan"]
            if row["unit_id"] == "tokyo_city_1900_occupational_persons":
                links.append("place:tokyo")
            row.update(opening_reference_ids=links, opening_scope_relation=relation)
            result.append(row)
    return result


def regroup_age_rows(rows, target):
    for band in target:
        selected = [
            row
            for row in rows
            if row["role"] == band["role"] and (
                band["age_min"] is None and row["age_min"] is None
                or band["age_min"] is not None and row["age_min"] is not None
                and row["age_min"] >= band["age_min"]
                and (band["age_max"] is None
                     or row["age_max"] is not None and row["age_max"] <= band["age_max"])
            )
        ]
        yield band | {field: sum(row[field] for row in selected) for field in AGE_COUNTS}


def mexican_age_panels():
    directory = HERE / "mexico_census_1900"
    regional = {}
    for row in read_csv(directory / "regional_age_sex.csv"):
        regional.setdefault(row["unit_id"], []).append(row)
    national = read_csv(directory / "national_age_sex.csv")
    bands = ("age_min", "age_max", "role", "source_age_label")
    if len(regional) != 30 or len(national) != 10:
        raise ValueError("Unexpected Mexican age table coverage")
    band_totals = {tuple(row[key] for key in bands): {sex: int(row[sex]) for sex in AGE_COUNTS}
                   for row in national}
    for unit_id, raw in regional.items():
        if len(raw) != len(band_totals) or {tuple(row[key] for key in bands) for row in raw} != band_totals.keys():
            raise ValueError(f"Unexpected Mexican age groups for {unit_id}")
        for row in raw:
            for sex in AGE_COUNTS:
                band_totals[tuple(row[key] for key in bands)][sex] -= int(row[sex])
    if any(any(counts.values()) for counts in band_totals.values()):
        raise ValueError("Mexican regional age tables do not close to national controls by age and sex")
    for unit_id, raw in [*regional.items(), ("mexican_republic", national)]:
        first = raw[0]
        rows = [dict(
            label=row["source_age_label"], role=row["role"],
            age_min=int(row["age_min"]) if row["age_min"] else None,
            age_max=int(row["age_max"]) if row["age_max"] else None,
            **{sex: int(row[sex]) for sex in AGE_COUNTS},
        ) for row in raw]
        totals = {sex: sum(row[sex] for row in rows) for sex in AGE_COUNTS}
        if (totals["both"] != int(first["observed_total"])
                or any(row["both"] != row["male"] + row["female"] for row in rows)):
            raise ValueError(f"Mexican age table counts differ for {unit_id}")
        panel = dict(
            id=f"{unit_id}_1900_age_sex", observed_unit_id=unit_id,
            observed_date=first["observed_date"], source_id=first["source_id"], published_scope=first["observed_name"],
            locator="Cuadro 8, printed pp. 29–33; Cuadro 7, p. 27",
            definition="Census population by published age intervals and sex. Both districts of Baja California are combined.",
            broad_observation=False, opening_band_roles=["band", "unknown"],
            opening_method=OPENING_METHOD,
            uncertainty="Changes in local age and sex between January and the October census are unquantified.",
        )
        if unit_id in regional:
            panel.update(opening_unit_id=unit_id, opening_from_version=21,
                         opening_match_population_endpoint=True)
            if unit_id == "mx_durango":
                panel.update(opening_population_endpoint_difference=13,
                             uncertainty=panel["uncertainty"] + " The revised Durango population endpoint exceeds "
                                         "the original census control by 13 persons.")
        yield panel, [dict(label="Census total", role="total", age_min=None, age_max=None, **totals), *rows]


def age_sex_panels():
    panels = json.loads((AGE_SOURCES / "panels.json").read_text(encoding="utf8"))
    panels.extend(json.loads((AGE_SOURCES / "us_census_1900_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "uk_county_age_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "france_census_1901_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "germany_census_1900_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "india_census_1901_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "india_census_1891_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "cape_1904_panels.json").read_text(encoding="utf8")))
    panels.extend(json.loads((AGE_SOURCES / "opening_1900_regional_panels.json").read_text(encoding="utf8")))
    regional_sources = (
        HERE / "netherlands_census_1899", HERE / "nordic_population_1900", HERE / "swiss_census_ages",
        HERE / "andaman_census_demography", HERE / "india_princely_age", HERE / "india_statistical_abstract_ages",
        HERE / "prussia_census_1900", HERE / "saxony_census_1900", HERE / "wuerttemberg_census_1900",
        HERE / "us_territorial_ages_1900", HERE / "baden_census_1900", HERE / "italy_census_1901",
        HERE / "brazil_census_1900_age", HERE / "spain_census_1900", HERE / "india_remaining_princely_demography",
    )
    for source in regional_sources:
        panels.extend(json.loads((source / "panels.json").read_text(encoding="utf8")))
    by_panel = {panel["id"]: [] for panel in panels}
    filenames = (
        "age_sex.csv", "us_census_1900.csv", "uk_county_age.csv", "france_census_1901.csv",
        "germany_census_1900.csv", "india_census_1901.csv", "india_census_1891.csv", "cape_1904.csv",
        "opening_1900_regional_ages.csv",
    )
    italian_regions = HERE / "italy_census_1901" / "regional_age_sex.csv"
    spanish_regions = HERE / "spain_census_1900" / "provincial_age_sex_1900.csv"
    agra_oudh_regions = HERE / "india_local_areas_1901" / "agra_oudh_age_vii_b_1901.csv"
    belgian_regions = HERE / "belgium_provinces_1900" / "age_sex.csv"
    portuguese_regions = HERE / "portugal_census_1900" / "age_sex.csv"
    for year in (1890, 1900):
        for scope, page in (("kingdom", 2), ("lisboa", 28), ("porto", 32)):
            key = f"pt_census_{year}_{scope}"
            panels.append(dict(
                id=key, published_scope=f"{scope.title()}, population present",
                source_id=f"pt_census_{year}", observed_unit_id=key, observed_date=f"{year}-12-01",
                locator=f"Vol. II, printed p. {page}", opening_band_roles=["band", "unknown"],
                definition="Completed ages by sex. 1890 ages 15–24 are grouped to the intervals reported in 1900.",
                broad_observation=False, uncertainty="Census coverage and age reporting errors are unquantified.",
            ))
            by_panel[key] = []
    for row in read_csv(belgian_regions):
        if row["role"] != "total":
            continue
        unit = row["panel"]
        panels.append(dict(
            id=unit, published_scope="Usual residents of the 1900 census territory",
            source_id="be_census_1900_age_and_spoken_languages", observed_unit_id=unit,
            observed_date="1900-12-31", locator="Tome I(c), printed p. 628",
            definition="The three reported census age intervals. The original table has no independent unknown-age column.",
            broad_observation=False, uncertainty="Shift the province's age-by-sex shares to January 1900. "
            "Change over the year and ages within each broad band are unquantified.",
            **({} if unit == "be_census_kingdom" else dict(
                opening_unit_id=unit, opening_from_version=25, opening_match_population_endpoint=True,
            )),
        ))
        by_panel[unit] = []
    for panel_id, scope in (
        ("raj_agra_oudh", "Agra and Oudh combined"),
        ("raj_agra_oudh_agra_remainder", "Agra"),
        ("raj_agra_oudh_oudh", "Oudh"),
    ):
        panels.append(dict(
            id=panel_id, published_scope=scope, source_id="india_oudh_census_1901_districts",
            observed_unit_id=panel_id, observed_date="1901-03-01", locator="Provincial Table VII(B), printed pp. 50–51",
            definition="People present, grouped by completed age and sex.", broad_observation=False,
            uncertainty="Enumeration error and the shift to January 1900 are unquantified.",
        ))
        by_panel[panel_id] = []
    for source in read_csv(HERE / "spain_census_1900" / "provincial_age_sources_1900.csv"):
        panel_id = source["panel"]
        panels.append(dict(
            id=panel_id, published_scope=f"{source['province']} province, population present",
            source_id="es_census_1900_age_marital", observed_unit_id=panel_id, observed_date=source["date"],
            locator=f"Vol. III, printed pp. {source['printed_pages']}; {source['method']}",
            definition="Province census population present by sex and age.", broad_observation=False,
            opening_band_roles=["band", "unknown"],
        ))
        by_panel[panel_id] = []
    for path in [*(AGE_SOURCES / name for name in filenames), *(source / "age_sex.csv" for source in regional_sources),
                 italian_regions, spanish_regions, agra_oudh_regions, belgian_regions, portuguese_regions]:
        for row in read_csv(path):
            for key in ("age_min", "age_max", "both", "male", "female"):
                row[key] = int(row[key]) if row[key] else None
            by_panel[row["panel"]].append(row)

    russian = {"0": by_panel["russia_empire_1897"]}
    regional_panels = {}
    for parameter, region, _, _ in RUSSIAN_CENSUS_REGIONS:
        panel_id = f"russia_{region}_1897"
        russian[parameter] = []
        by_panel[panel_id] = russian[parameter]
        regional_panels[parameter] = dict(
            id=panel_id, observed_unit_id=f"rus_age_97:reg:{parameter}",
            source_id="rus_age_97", observed_date="1897-02-09",
            locator=f"rus_age_97.php?reg={parameter}, rows 3–126",
            definition="De facto regional census population, single years, upper age interval and age not stated.",
            russian_region_parameter=parameter, broad_observation=False,
        )
        panels.append(regional_panels[parameter])
    for row in read_csv(HERE / "russia" / "structure.csv"):
        parameter = row["region_parameter"]
        if row["source_table"] != "rus_age_97" or parameter not in russian:
            continue
        if parameter in regional_panels:
            regional_panels[parameter]["published_scope"] = row["published_scope"]
        label = row["category"]
        if label == "Дети моложе 1 года":
            age_min = age_max = 0
        elif label.isdecimal():
            age_min = age_max = int(label)
        elif label == "110 и более":
            age_min, age_max = 110, None
        else:
            age_min = age_max = None
        russian[parameter].append(dict(
            label=label, age_min=age_min, age_max=age_max,
            role="total" if label == "ИТОГО" else "subtotal" if "-" in label else "band",
            **{key: int(row[key]) for key in AGE_COUNTS},
        ))
    for panel in panels:
        if "component_panels" not in panel:
            continue
        components = []
        for panel_id in panel["component_panels"]:
            rows = by_panel[panel_id]
            adjustments = panel.get("component_count_corrections", {}).get(panel_id, {})
            if adjustments:
                rows = [row | adjustments.get(row["label"], {}) for row in rows]
            if "regroup_to" in panel and panel_id != panel["regroup_to"]:
                rows = regroup_age_rows(rows, by_panel[panel["regroup_to"]])
            components.append(rows)
        for matched_rows in zip(*components, strict=True):
            row = matched_rows[0].copy()
            if any(
                component[key] != row[key]
                for component in matched_rows[1:]
                for key in ("label", "role", "age_min", "age_max")
            ):
                raise ValueError(f"{panel['id']}: component age groups do not match")
            for key in AGE_COUNTS:
                row[key] = sum(component[key] for component in matched_rows)
            by_panel[panel["id"]].append(row)
    return ([(panel, by_panel[panel["id"]]) for panel in panels]
            + list(austrian_age_panels()) + list(hungarian_crown_age_panels()) + list(mexican_age_panels()))


def opening_age_group(panel, rows, unit_id, opening_total):
    totals = [row for row in rows if row["role"] == "total"]
    band_roles = panel.get("opening_band_roles", ["band"])
    bands = [
        {key: row[key] for key in ("label", "age_min", "age_max", "male", "female")}
        for row in rows if row["role"] in band_roles
    ]
    if len(totals) != 1:
        raise ValueError(f"{panel['id']}: expected one age table control")
    total = totals[0]
    if "opening_residual_label" in panel:
        bands.append(dict(
            label=panel["opening_residual_label"], age_min=None, age_max=None,
            **{sex: total[sex] - sum(band[sex] for band in bands) for sex in SEX_COUNTS},
        ))
    for sex in SEX_COUNTS:
        if any(band[sex] < 0 for band in bands) or sum(band[sex] for band in bands) != total[sex]:
            raise ValueError(f"{panel['id']}: {sex} age rows do not sum to the table control")
    if total["male"] + total["female"] != total["both"]:
        raise ValueError(f"{panel['id']}: sex totals do not sum to the table population")
    for band in bands:
        low, high = band["age_min"], band["age_max"]
        band["id"] = "unknown" if low is None else f"age_{low}_{high if high is not None else 'plus'}"
    return dict(
        unit_id=unit_id, opening_total=opening_total, observed_total=total["both"],
        method=panel.get("opening_method", OPENING_METHOD), bands=bands,
        **{key: panel[key] for key in ("source_id", "observed_unit_id", "observed_date", "locator", "uncertainty")},
    )


def regroup_single_years(rows):
    target = [row for row in rows if row["role"] == "total"
              or row["role"] == "band" and (row["age_min"] is None or row["age_min"] < 5
                                            or row["age_max"] is None)]
    first, *_, last = [row["age_min"] for row in rows
                       if row["role"] == "band" and row["age_min"] is not None
                       and row["age_max"] == row["age_min"] and row["age_min"] >= 5]
    for low in range(first, last + 1, 5):
        high = min(low + 4, last)
        target.append(dict(label=f"Ages {low}–{high}", role="band", age_min=low, age_max=high))
    target.sort(key=lambda row: (row["role"] != "total", row["age_min"] is None, row["age_min"]))
    return list(regroup_age_rows(rows, target))


def england_wales_remaining_ages(panels):
    national_panel, national_rows = panels["england_wales_1901"]
    target = [row for row in national_rows if row["role"] in {"total", "band"}]
    excluded = (
        "uk_county_age_anglesey_1901", "uk_county_age_carmarthenshire_1901",
        "uk_county_age_glamorganshire_1901", "uk_county_age_montgomeryshire_1901",
        "uk_county_age_radnorshire_1901",
    )
    counties = [regroup_age_rows(panels[key][1], target) for key in excluded]
    rows = [national | {field: national[field] - sum(row[field] for row in deductions) for field in AGE_COUNTS}
            for national, *deductions in zip(target, *counties, strict=True)]
    panel = national_panel | dict(
        id="england_wales_other_counties_1901",
        observed_unit_id="uk_england_wales_excluding_five_tabulated_ancient_counties",
        locator=national_panel["locator"] + "; Census of England and Wales, Table XXVI, pp. 156–159, "
        "Anglesey, Carmarthenshire, Glamorganshire (with Cardiff and Swansea), Montgomeryshire and Radnorshire",
        opening_method="Subtract the five separately modeled ancient counties from the England and Wales "
        "census by age and sex. Use the remainder's shares in the other ancient county balances with integer largest remainders.",
        uncertainty="The residual is calculated from census-night counts. Each other opening county "
        "uses the same residual shares; actual differences between counties and from January 1900 are unquantified.",
    )
    return panel, rows


def russian_regional_age_models(panels, observations, district_pools):
    provinces = [row for row in observations if row["source_id"] == "russia_first_census"
                 and row.get("parent_id") == "ru_census_1897_ex_finland"]
    result = {}
    for _, region, first, last in RUSSIAN_CENSUS_REGIONS:
        panel, rows = panels[f"russia_{region}_1897"]
        control = next(row for row in rows if row["role"] == "total")
        ids = {f"ru1897_{number}" for number in range(first, last + 1)}
        subset = [row for row in provinces if row["unit_id"] in ids]
        for sex in SEX_COUNTS:
            if sum(row["sex"][sex] for row in subset) != control[sex]:
                raise ValueError(f"{region}: province sex totals differ from the regional census")
        model = panel | dict(
            opening_method="Preserve each province's published 1897 male and female totals in its census-date age model. "
            "Within each sex, distribute ages using the corresponding regional age shares and integer largest remainders. "
            "Use the resulting shares in the separately reconstructed opening balance.",
            uncertainty="The sex controls are observed at provincial scale in February 1897. Age within each sex "
            "uses the containing census region's shares, with single ages combined from age five. "
            "Provincial age differences, migration, enumeration error and changes to January 1900 are unquantified.",
        )
        bands = [row for row in regroup_single_years(rows) if row["role"] == "band"]
        districts = (row for row in observations if row.get("wwo_id") in district_pools
                     and row["source_id"] == "russia_first_census" and row["parent_id"] in ids)
        for row in [*subset, *districts]:
            sex_totals = row["sex"]
            population = row["population_value"]
            if sum(sex_totals[sex] for sex in SEX_COUNTS) != population:
                raise ValueError(f"{row['unit_id']}: province sex totals differ from the published population")
            by_sex = {
                sex: apportion({i: Fraction(sex_totals[sex] * band[sex], control[sex])
                                for i, band in enumerate(bands)}, sex_totals[sex])
                for sex in SEX_COUNTS
            }
            province_bands = []
            for i, band in enumerate(bands):
                male, female = (by_sex[sex][i] for sex in SEX_COUNTS)
                province_bands.append(band | dict(male=male, female=female, both=male + female))
            province_total = control | sex_totals | dict(both=population)
            is_district = row["wwo_id"] in district_pools
            level = "district" if is_district else "province"
            local_model = model | dict(
                observed_unit_id=row["unit_id"],
                locator=f"{panel['locator']}; {row['source_id']}, {row['locator']} ({level} sex totals)",
            )
            if is_district:
                local_model["opening_method"] = model["opening_method"].replace("province's", "district's")
                local_model["uncertainty"] = model["uncertainty"].replace("provincial", "district").replace("Provincial", "District")
            result[row["wwo_id"] or row["unit_id"]] = (local_model, [province_total, *province_bands])
    return result


def swiss_opening_age_model(panels, group):
    first_panel, first_rows = panels["switzerland_1888"]
    last_panel, last_rows = panels["switzerland_1900"]
    dates = [first_panel["observed_date"], last_panel["observed_date"]]
    if dates != group["endpoint_dates"]:
        raise ValueError("Swiss age tables and canton controls use different census dates")
    first = opening_age_group(first_panel, first_rows, group["unit_id"], group["country_endpoint_values"][0])
    last = opening_age_group(last_panel, last_rows, group["unit_id"], group["country_endpoint_values"][1])
    if [first["observed_total"], last["observed_total"]] != group["country_endpoint_values"]:
        raise ValueError("Swiss age tables and canton controls use different census populations")
    fraction = opening_fraction(dates)
    quotas = {
        (early["id"], sex): early[sex] * (1 - fraction) + late[sex] * fraction
        for early, late in zip(first["bands"], last["bands"], strict=True)
        for sex in SEX_COUNTS
    }
    allocated = apportion(quotas, group["population_value"])
    male = sum(count for (_, sex), count in allocated.items() if sex == "male")
    bands = [
        band | {sex: allocated[band["id"], sex] for sex in SEX_COUNTS} | dict(
            role="band", both=sum(allocated[band["id"], sex] for sex in SEX_COUNTS),
        ) for band in first["bands"]
    ]
    control = dict(role="total", both=group["population_value"], male=male, female=group["population_value"] - male)
    model = last_panel | dict(
        id="switzerland_opening_model",
        observed_date=DATE,
        locator=f"{last_panel['locator']} Census columns {dates[0]} and {dates[1]}.",
        opening_method="Interpolate each national age and sex count between both censuses at 1900-01-01. "
        "Use largest remainders to close to the national resident total and apply the resulting shares to each canton.",
        uncertainty="Canton differences and intercensal changes are unquantified. The opening-age distribution "
        "is a national model based on both censuses.",
    )
    return model, [control, *bands]


def port_blair_opening_sex_model(panels, unit):
    earlier_panel, (earlier,) = panels["port_blair_1891_sex"]
    later_panel, (later,) = panels["port_blair_1901_sex"]
    dates = [earlier_panel["observed_date"], later_panel["observed_date"]]
    if dates != unit["source_dates"] or [earlier["both"], later["both"]] != unit["endpoint_values"]:
        raise ValueError("Port Blair sex tables and opening controls use different census populations")
    for row in (earlier, later):
        if row["male"] + row["female"] != row["both"]:
            raise ValueError("Port Blair sex totals do not sum to the census population")
    fraction = opening_fraction(dates)
    total = unit["population_value"]
    allocated = apportion({sex: earlier[sex] * (1 - fraction) + later[sex] * fraction for sex in SEX_COUNTS}, total)
    return dict(
        unit_id=unit["unit_id"], opening_total=total, observed_total=total,
        source_id=later_panel["source_id"], observed_unit_id=later_panel["observed_unit_id"], observed_date=DATE,
        locator=f"{later_panel['locator']} Census columns {dates[0]} and {dates[1]}.",
        method="Interpolate both published sex counts to 1900-01-01 and reconcile integer people to the opening control.",
        uncertainty="The common census extent is the Port Blair Penal Settlement. It excludes the separate Indigenous "
        "Andamanese and Nicobars returns. No interval is known for the timing of population change. Ages are unknown.",
        sex_only=True,
        bands=[dict(id="unknown", label="Modeled sex totals; age unknown", age_min=None, age_max=None, **allocated)],
    )


def indian_abstract_opening_age_model(panels, unit, dates, area):
    first_panel, first_rows = panels[f"india_abstract_{area}_1891"]
    last_panel, last_rows = panels[f"india_abstract_{area}_1901"]
    if [first_panel["observed_date"], last_panel["observed_date"]] != dates:
        raise ValueError(f"{area}: abstract age tables and opening controls use different dates")
    target = [dict(label="Total Population", role="total", age_min=None, age_max=None)]
    target.extend(dict(label=label, role="band", age_min=low, age_max=high) for label, low, high in (
        ("Ages 0–4", 0, 4), ("Ages 5–14", 5, 14), ("Ages 15–24", 15, 24),
        ("Ages 25–44", 25, 44), ("Ages 45 and over", 45, None), ("Unspecified", None, None),
    ))
    first, last = [
        opening_age_group(panel, list(regroup_age_rows(rows, target)), unit["unit_id"], endpoint)
        for panel, rows, endpoint in zip(
            (first_panel, last_panel), (first_rows, last_rows), unit["endpoint_values"], strict=True,
        )
    ]
    if [first["observed_total"], last["observed_total"]] != unit["endpoint_values"]:
        raise ValueError(f"{area}: abstract age tables and opening controls use different census populations")

    fraction = opening_fraction(dates)
    quotas = {
        sex: {early["id"]: early[sex] * (1 - fraction) + late[sex] * fraction
              for early, late in zip(first["bands"], last["bands"], strict=True)}
        for sex in SEX_COUNTS
    }
    total = unit["population_value"]
    sex_totals = apportion({sex: sum(quotas[sex].values()) for sex in SEX_COUNTS}, total)
    allocations = {sex: apportion(quotas[sex], sex_totals[sex]) for sex in SEX_COUNTS}
    rows = [dict(role="total", both=total, **sex_totals)]
    rows.extend(band | dict(role="band", **{sex: allocations[sex][band["id"]] for sex in SEX_COUNTS})
                for band in last["bands"])
    model = last_panel | dict(
        id=f"{area}_opening_age_model", observed_date=DATE,
        locator=f"{first_panel['locator']}; {last_panel['locator']}; {last_panel['population_control_locator']}.",
        opening_method="Interpolate both censuses on a shared set of age bands to 1900-01-01. "
        "Reconcile integer ages within each modeled sex total. Keep unspecified ages unknown.",
        uncertainty="The 1891 abstract has inconsistent labels above age 44. Both censuses are grouped to 45 and over. "
        "Census age reporting and intercensal change have no quantified error interval.",
    )
    return opening_age_group(model, rows, unit["unit_id"], total)


def age_profile_at_interpolated_sex_totals(panel, rows, unit, controls, *, method, uncertainty, locator):
    dates = [row["date"] for row in controls]
    opening_dates = unit.get("source_dates") or ["1891-02-26", "1901-03-01"]
    if (dates != opening_dates or panel["observed_date"] != dates[-1]
            or [int(row["persons"]) for row in controls] != unit["endpoint_values"]
            or any(sum(int(row[sex]) for sex in SEX_COUNTS) != int(row["persons"]) for row in controls)):
        raise ValueError(f"{unit['unit_id']}: census sex and opening population controls differ")
    population = unit["population_value"]
    fraction = opening_fraction(dates)
    earlier, later = controls
    sex_totals = apportion({sex: int(earlier[sex]) * (1 - fraction) + int(later[sex]) * fraction
                            for sex in SEX_COUNTS}, population)
    model = opening_age_group(panel, rows, unit["unit_id"], population)
    observed, = (row for row in rows if row["role"] == "total")
    for sex in SEX_COUNTS:
        counts = apportion({band["id"]: Fraction(sex_totals[sex] * band[sex], observed[sex])
                            for band in model["bands"]}, sex_totals[sex])
        for band in model["bands"]:
            band[sex] = counts[band["id"]]
    return model | dict(observed_total=population, observed_date=DATE, method=method,
                        uncertainty=uncertainty, locator=locator)


def remaining_indian_states_age_models(panels, balances, observations):
    collection = HERE / "india_remaining_princely_demography"
    model_method = "Interpolate the comparable 1891 and 1901 sex totals to the opening date. "
    madras_rows = defaultdict(list)
    for row in observations:
        if row["parent_id"] == MADRAS_STATES_REMAINDER:
            madras_rows[row["unit_id"]].append(row)
    for unit_id, endpoints in madras_rows.items():
        early, late = sorted(endpoints, key=lambda row: row["date"])
        panel, rows = panels[f"india_census_madras_states_ex_cochin_travancore_1901_{unit_id.removeprefix('raj_madras_')}"]
        observed, = (row for row in rows if row["role"] == "total")
        if any(late["sex"][sex] != observed[sex] for sex in SEX_COUNTS):
            raise ValueError(f"{unit_id}: original Madras age and sex counts differ")
        yield age_profile_at_interpolated_sex_totals(
            panel, rows, balances[unit_id],
            [dict(date=row["date"], persons=row["population_value"], **row["sex"]) for row in (early, late)],
            method=model_method + "Hold the state's own 1901 age shares within each sex.",
            uncertainty="Intercensal change and enumeration error are unquantified. The historical bands do not resolve single ages.",
            locator=f"{panel['locator']}; Madras 1941, Vol. II, Table II, p. 18 (comparison sex counts)",
        )
    early, comparable, full = read_csv(collection / "bombay_states_sex_controls.csv")
    panel, rows = panels["india_abstract_bombay_states_1901"]
    observed, = (row for row in rows if row["role"] == "total")
    if any(observed[sex] != int(full[sex]) for sex in SEX_COUNTS):
        raise ValueError("Bombay States full-scope age and sex returns differ")
    yield age_profile_at_interpolated_sex_totals(
        panel, rows, balances["raj_bombay_states"], [early, comparable],
        method=model_method + "Hold the wider 1901 Bombay States age shares within each sex. Keep unspecified ages unknown.",
        uncertainty="The age return includes 8,645 males and 14,164 females beyond the comparable 1901 area. "
                    "Their age composition is unknown. The 1899–1900 famine may have affected ages and timing of change. "
                    "These are modeled opening ages; there is no quantified opening error interval.",
        locator=f"{panel['locator']}; Census of India 1901, Vol. I-A, Table II-A, p. 10, row 15 (comparable sex)",
    )


def central_provinces_states_opening_age_model(panels, unit, dates):
    early_panel, early_rows = panels["india_abstract_central_provinces_states_1891"]
    late_panel, late_rows = panels["india_census_cp_states_1901"]
    early_total, = (row for row in early_rows if row["role"] == "total")
    late_total, = (row for row in late_rows if row["role"] == "total")
    total = unit["population_value"]
    observed = opening_age_group(late_panel, late_rows, unit["unit_id"], total)
    if [early_panel["observed_date"], late_panel["observed_date"]] != dates or (
        [early_total["both"], observed["observed_total"]] != unit["endpoint_values"]
        or early_total["male"] + early_total["female"] != early_total["both"]
    ):
        raise ValueError("Central Provinces States age and sex tables use different census controls")

    fraction = opening_fraction(dates)
    sex_totals = apportion({sex: early_total[sex] * (1 - fraction) + late_total[sex] * fraction
                            for sex in SEX_COUNTS}, total)
    allocations = {
        sex: apportion({band["id"]: Fraction(band[sex] * sex_totals[sex], late_total[sex])
                        for band in observed["bands"]}, sex_totals[sex])
        for sex in SEX_COUNTS
    }
    rows = [dict(role="total", both=total, **sex_totals)]
    rows.extend(band | dict(role="band", **{sex: allocations[sex][band["id"]] for sex in SEX_COUNTS})
                for band in observed["bands"])
    model = late_panel | dict(
        id="central_provinces_states_opening_age_model", observed_date=DATE,
        locator=f"{late_panel['locator']}; {late_panel['population_control_locator']} for both sex totals.",
        opening_method="Interpolate the comparable 1891 and 1901 sex counts to 1900-01-01. "
        "Hold the 1901 provincial census age distribution within each modeled sex total.",
        uncertainty="The provincial tables supply seven age bands. Age changes before 1901 "
        "and census reporting errors have no quantified interval.",
    )
    return opening_age_group(model, rows, unit["unit_id"], total)


def princely_state_opening_age_model(panels, unit, state):
    earlier, earlier_rows = panels[f"{state}_1891_age_rates"]
    later, later_rows = panels[f"{state}_1901_age_rates"]
    dates = [earlier["observed_date"], later["observed_date"]]
    endpoints = [sum(panel["population_by_sex"].values()) for panel in (earlier, later)]
    if dates != unit["source_dates"] or endpoints != unit["endpoint_values"]:
        raise ValueError(f"{state}: age tables and opening controls use different census populations")
    bands = [[row for row in rows if row["role"] == "band"] for rows in (earlier_rows, later_rows)]
    rate_sums = [{sex: sum(row[sex] for row in rows) for sex in SEX_COUNTS} for rows in bands]
    for panel, rows, rates in zip((earlier, later), bands, rate_sums, strict=True):
        for sex in SEX_COUNTS:
            if 2 * abs(rates[sex] - panel["rate_denominator"]) > len(rows):
                raise ValueError(f"{panel['id']}: {sex} age rates do not reconcile with the published denominator")
    fraction = opening_fraction(dates)
    quotas = {}
    for index, (early, late) in enumerate(zip(*bands, strict=True)):
        if (early["age_min"], early["age_max"]) != (late["age_min"], late["age_max"]):
            raise ValueError(f"{state}: age boundaries differ by census year")
        for sex in SEX_COUNTS:
            old = Fraction(early[sex] * earlier["population_by_sex"][sex], rate_sums[0][sex])
            new = Fraction(late[sex] * later["population_by_sex"][sex], rate_sums[1][sex])
            quotas[index, sex] = old * (1 - fraction) + new * fraction
    total = unit["population_value"]
    allocated = apportion(quotas, total)
    rows = [row | {sex: allocated[index, sex] for sex in SEX_COUNTS}
            for index, row in enumerate(bands[1])]
    control = dict(role="total", both=total, **{sex: sum(row[sex] for row in rows) for sex in SEX_COUNTS})
    model = later | dict(
        id=f"{state}_opening_age_model", observed_date=DATE,
        locator=f"{later['locator']}. Sex totals: {later['sex_control_locator']}.",
        opening_method="Reconstruct both census age tables from the published age rates and sex totals. "
        "Interpolate counts to 1900-01-01 on the national comparable census dates and reconcile integer people to the opening control.",
        uncertainty="The age rates are rounded in print. Enumeration quality and intercensal population change "
        "have no quantified error interval." + later.get("opening_source_uncertainty", ""),
    )
    return opening_age_group(model, [control, *rows], unit["unit_id"], total)


def egypt_provincial_sex_models(opening_balances, observations):
    sources = EGYPT_FAIYUM_SOURCES | {EGYPT_COMPARABLE_PROVINCES}
    records = {row["record_id"]: row for row in observations if row["source_id"] in sources}
    for unit in opening_balances.values():
        if unit.get("source_id") not in sources:
            continue
        dates = unit["source_dates"]
        first, last = [records[record_id] for record_id in unit["source_observations"]]
        for row in (first, last):
            if sum(row["breakdowns"]["sex"].values()) != row["population_value"]:
                raise ValueError(f"{unit['unit_id']}: sex totals do not sum to the census population")
        fraction = opening_fraction(dates)
        total = unit["population_value"]
        allocated = apportion({
            sex: first["breakdowns"]["sex"][sex] * (1 - fraction) + last["breakdowns"]["sex"][sex] * fraction
            for sex in SEX_COUNTS
        }, total)
        yield dict(
            unit_id=unit["unit_id"], opening_total=total, observed_total=total, source_id=unit["source_id"],
            observed_unit_id=unit["unit_id"], observed_date=DATE, locator=unit["locator"],
            method="Interpolate the two published sex counts to 1900-01-01 and reconcile integer people "
                   "to the opening control.",
            uncertainty=unit["uncertainty_kind"] + " Ages are unknown.",
            sex_only=True,
            bands=[dict(id="unknown", label="Modeled sex totals; age unknown", age_min=None, age_max=None, **allocated)],
        )


def check_italian_age_controls(panels, observations):
    dated_returns = {
        row["unit_id"]: row for row in observations
        if row["source_id"] == "it_1901_census_v5_age_and_marital" and row["date"] == "1901-01-01"
    }
    for unit_id, observed in dated_returns.items():
        if unit_id == "kingdom_of_italy":
            continue
        _, rows = panels[unit_id]
        control = next(row for row in rows if row["role"] == "total")
        if control["both"] != observed["population_value"] or any(
            control[sex] != observed["sex"][sex] for sex in SEX_COUNTS
        ):
            raise ValueError(f"{unit_id}: age rows differ from the Italian January 1901 population control")
    verify_national_age_totals(
        panels["kingdom_of_italy"][1],
        (panels[unit_id][1] for unit_id in dated_returns if unit_id != "kingdom_of_italy"),
        "kingdom_of_italy",
    )


def verify_national_age_totals(national_rows, regional_rows, unit_id):
    by_band = {row["label"]: {sex: 0 for sex in SEX_COUNTS} for row in national_rows}
    for rows in regional_rows:
        for row, national in zip(rows, national_rows, strict=True):
            if any(row[key] != national[key] for key in ("label", "role", "age_min", "age_max")):
                raise ValueError(f"{unit_id}: regional and national age bands differ")
            for sex in SEX_COUNTS:
                by_band[row["label"]][sex] += row[sex]
    if any(by_band[row["label"]][sex] != row[sex] for row in national_rows for sex in SEX_COUNTS):
        raise ValueError(f"{unit_id}: regional age and sex counts do not close to the national return")


def apportion_local_ages(bands, local_sex):
    sex_totals = {sex: sum(band[sex] for band in bands) for sex in SEX_COUNTS}
    allocations = {
        sex: apportion({band["id"]: Fraction(local_sex[sex] * band[sex], sex_totals[sex])
                        for band in bands}, local_sex[sex])
        for sex in SEX_COUNTS
    }
    return [band | {sex: allocations[sex][band["id"]] for sex in SEX_COUNTS} for band in bands]


def united_provinces_state_age_models(panels, observations, aggregate, local_balances):
    dates = aggregate["endpoint_dates"]
    regional = indian_abstract_opening_age_model(panels, aggregate, dates, "united_provinces_states")
    for unit_id, balance in local_balances.items():
        if balance.get("statistical_parent") != aggregate["unit_id"]:
            continue
        endpoints = {row["date"]: row for row in observations
                     if row["unit_id"] == unit_id and row["source_id"] == balance["source_id"]}
        fraction = opening_fraction(dates)
        persons = balance["population_value"]
        earlier, later = (endpoints[d] for d in dates)
        if any(sum(row["sex"].values()) != row["population_value"] for row in (earlier, later)):
            raise ValueError(f"{unit_id}: published sex totals do not close")
        local_sex = apportion({sex: earlier["sex"][sex] * (1 - fraction) + later["sex"][sex] * fraction
                               for sex in SEX_COUNTS}, persons)
        yield regional | dict(
            unit_id=unit_id, observed_unit_id=unit_id, opening_total=persons, observed_total=persons,
            source_id=balance["source_id"], locator=f"{balance['locator']}; {regional['locator']}",
            method="Interpolate local male and female totals. Divide each modeled sex total among ages using "
                   "the interpolated age profile for that sex across both United Provinces princely states.",
            uncertainty="Local age variation is unknown. Census error and change caused by migration or famine "
                        "have no quantified interval.",
            bands=apportion_local_ages(regional["bands"], local_sex),
        )


def mysore_local_age_models(panels, observations, local_balances):
    root = "raj_mysore_state"
    panel, rows = panels["india_census_1901_table_vii_mysore"]
    regional = opening_age_group(panel, rows, root, 0)
    observed = {
        (row["unit_id"], row["date"]): row for row in observations
        if row["parent_id"] == root and "sex" in row
    }
    leaves = [balance for balance in local_balances.values() if balance.get("statistical_parent") == root]
    late = panel["observed_date"]
    published = [observed[leaf["unit_id"], late] for leaf in leaves]
    for sex in SEX_COUNTS:
        if sum(row["sex"][sex] for row in published) != sum(band[sex] for band in regional["bands"]):
            raise ValueError("Mysore local sex totals do not close to the state age return")
    for balance, current in zip(leaves, published, strict=True):
        unit_id = balance["unit_id"]
        persons = balance["population_value"]
        early, _ = balance["source_dates"]
        previous = observed.get((unit_id, early))
        if any(sum(row["sex"].values()) != row["population_value"]
               for row in (current, previous) if row is not None):
            raise ValueError(f"{unit_id}: published sex counts do not close")
        if previous is None:
            sex_quotas = {sex: Fraction(persons * current["sex"][sex], current["population_value"])
                          for sex in SEX_COUNTS}
            method = "Hold the local 1901 census sex shares at opening."
        else:
            fraction = opening_fraction(balance["source_dates"])
            sex_quotas = {sex: previous["sex"][sex] * (1 - fraction) + current["sex"][sex] * fraction
                          for sex in SEX_COUNTS}
            method = "Interpolate both local census sex counts to 1900-01-01."
        yield regional | dict(
            unit_id=unit_id, observed_unit_id=unit_id, opening_total=persons, observed_total=persons,
            observed_date=DATE, source_id=current["source_id"], locator=f"{current['locator']}; {panel['locator']}",
            method=f"{method} Apply the state census age profile within each sex. Round by largest remainders.",
            uncertainty="Local age variation is unknown. Census error and intercensal change have no quantified interval.",
            bands=apportion_local_ages(regional["bands"], apportion(sex_quotas, persons)),
        )


def spanish_provincial_age_models(panels, observations, local_balances):
    panel, rows = panels["es_census_1900_peninsula_islas"]
    national = opening_age_group(panel, rows, "kingdom_of_spain", 0)
    leaves = {row["unit_id"]: row for row in observations if row["source_id"] == "es_census_1900_provincial_population"
              and row["parent_id"] == "kingdom_of_spain"}
    remaining = {band["id"]: band.copy() for band in national["bands"]}
    direct = {}
    for unit, observed in leaves.items():
        if unit not in panels:
            continue
        local_panel, local_rows = panels[unit]
        direct[unit] = model = opening_age_group(local_panel | dict(uncertainty=national["uncertainty"]),
                                                local_rows, unit, local_balances[unit]["population_value"])
        if model["observed_total"] != observed["population_value"]:
            raise ValueError(f"{unit}: local age observation does not close to the census population")
        for sex in SEX_COUNTS:
            if sum(band[sex] for band in model["bands"]) != observed["sex"][sex]:
                raise ValueError(f"{unit}: local age and sex observations disagree")
            for band in model["bands"]:
                remaining[band["id"]][sex] -= band[sex]
    for sex in SEX_COUNTS:
        if (any(band[sex] < 0 for band in remaining.values())
                or sum(band[sex] for band in remaining.values())
                != sum(row["sex"][sex] for unit, row in leaves.items() if unit not in direct)):
            raise ValueError("Spanish residual age bands do not close to the remaining provincial sex counts")
    yield from direct.values()
    for unit, observed in leaves.items():
        if unit in direct:
            continue
        yield national | dict(
            unit_id=unit, observed_unit_id=unit, observed_total=observed["population_value"],
            opening_total=local_balances[unit]["population_value"], source_id=observed["source_id"],
            locator=f"{observed['locator']}; {national['locator']}; subtract nine independently assigned provinces",
            method="Apply the province's own census sex ratio. Within each sex, use the age distribution for "
                   "the remaining provinces after subtracting the nine directly assigned census returns.",
            uncertainty=national["uncertainty"] + " Differences among the remaining provinces are unquantified.",
            bands=apportion_local_ages(remaining.values(), observed["sex"]),
        )


def refine_age_bands(coarse_bands, fine_bands):
    for coarse in coarse_bands:
        if coarse["age_min"] is None:
            yield coarse
            continue
        fine = [band for band in fine_bands if band["age_min"] is not None
                and coarse["age_min"] <= band["age_min"]
                and (coarse["age_max"] is None or (band["age_max"] is not None and band["age_max"] <= coarse["age_max"]))]
        yield from apportion_local_ages(fine, coarse)


def portuguese_age_models(panels, observations, local_balances):
    root = "kingdom_of_portugal"
    profiles = {}
    controls = defaultdict(dict)
    for row in observations:
        if row["source_id"] in ("pt_census_1890", "pt_census_1900") and (row["parent_id"] == root or row["unit_id"] == root):
            controls[row["date"]][row["unit_id"]] = row
    for day in ("1890-12-01", "1900-12-01"):
        source = f"pt_census_{day[:4]}"
        national_panel, national_rows = panels[f"{source}_kingdom"]
        national = opening_age_group(national_panel, national_rows, root, 0)
        remaining = {band["id"]: band.copy() for band in national["bands"]}
        local = {}
        for scope in ("lisboa", "porto"):
            unit = f"pt1900_{scope}"
            panel, rows = panels[f"{source}_{scope}"]
            local[unit] = opening_age_group(panel, rows, unit, 0)["bands"]
            for sex in SEX_COUNTS:
                if sum(band[sex] for band in local[unit]) != controls[day][unit]["sex"][sex]:
                    raise ValueError(f"{unit}: {day} district ages and sex counts do not close")
                for band in local[unit]:
                    remaining[band["id"]][sex] -= band[sex]
        for sex in SEX_COUNTS:
            residual = sum(row["sex"][sex] for unit, row in controls[day].items() if unit not in local and unit != root)
            if any(band[sex] < 0 for band in remaining.values()) or sum(band[sex] for band in remaining.values()) != residual:
                raise ValueError(f"Portugal {day}: remaining district age and sex counts do not close")
        profiles[day] = (local, tuple(remaining.values()))
    for unit, first in controls["1890-12-01"].items():
        if unit == root:
            continue
        balance = local_balances[unit]
        dates = balance["source_dates"]
        fraction = opening_fraction(dates)
        direct = unit in profiles[dates[0]][0]
        endpoint_bands = []
        for day in dates:
            local, remaining = profiles[day]
            endpoint_bands.append(local[unit] if direct else apportion_local_ages(remaining, controls[day][unit]["sex"]))
        early, late = ({band["id"]: band for band in bands} for bands in endpoint_bands)
        quotas = {(key, sex): band[sex] * (1 - fraction) + late[key][sex] * fraction
                  for key, band in early.items() for sex in SEX_COUNTS}
        total = balance["population_value"]
        members = apportion(quotas, total)
        yield dict(
            unit_id=unit, observed_unit_id=unit, opening_total=total, observed_total=total,
            observed_date=DATE, source_id="pt_census_1900", locator=f"{first['locator']}; both censuses, Vol. II pp. 2, 28, 32",
            method=("Interpolate both directly observed district age and sex profiles." if direct else
                    "At each census, use the district sex counts and the national age profile within each sex after "
                    "deducting Lisboa and Porto. Interpolate the resulting district cohorts to January 1900."),
            uncertainty="The interpolated cells are model counts. Census coverage, boundary transfers and local age "
                        "differences for the 19 indirectly modeled districts are unquantified.",
            bands=[band | {sex: members[key, sex] for sex in SEX_COUNTS} for key, band in early.items()],
        )


def agra_oudh_local_age_models(panels, observations, local_balances, version):
    root = "raj_agra_oudh"
    panel, rows = panels["india_census_1901_table_vii_agra_oudh_opening"]
    regional = opening_age_group(panel, rows, root, 0)
    local = {row["unit_id"]: row for row in observations
             if row["parent_id"] == root and row["date"] == panel["observed_date"] and "sex" in row}
    agra, = (row for row in observations if row["unit_id"] == "raj_agra_1901_provincial_return")
    local["raj_agra_remainder"] = agra
    if any(sum(row["sex"][sex] for row in local.values()) != sum(band[sex] for band in regional["bands"])
           for sex in SEX_COUNTS):
        raise ValueError("Agra and Oudh sex counts do not close to the combined age return")
    agra_districts = {row["unit_id"]: row for row in observations if row["source_id"] == AGRA_DISTRICT_SOURCE
                      and row["date"] == panel["observed_date"]}
    if version >= 26:
        if any(sum(row["sex"][sex] for row in agra_districts.values()) != agra["sex"][sex] for sex in SEX_COUNTS):
            raise ValueError("Agra district census sex counts do not close to the province")
        local.update(agra_districts)
    finer_agra, finer_oudh = None, None
    if version >= 25:
        agra_panel, agra_rows = panels["raj_agra_oudh_agra_remainder"]
        oudh_panel, oudh_rows = panels["raj_agra_oudh_oudh"]
        combined_panel, combined_rows = panels[root]
        verify_national_age_totals(combined_rows, (agra_rows, oudh_rows), root)
        fine = [band.copy() for band in regional["bands"]]
        # The provincial table independently resolves the 300-person female discrepancy in the all-India table.
        next(band for band in fine if band["age_min"] == 15)["female"] += 300
        next(band for band in fine if band["age_min"] is None)["female"] -= 300
        agra_coarse = opening_age_group(agra_panel, agra_rows, root, 0)["bands"]
        oudh_coarse = opening_age_group(oudh_panel, oudh_rows, root, 0)["bands"]
        combined = opening_age_group(combined_panel, combined_rows, root, 0)["bands"]
        if list(refine_age_bands(combined, fine)) != fine:
            raise ValueError("Joint fine age bands do not close to the provincial age bands")
        finer_agra = list(refine_age_bands(agra_coarse, fine))
        finer_oudh = list(refine_age_bands(oudh_coarse, fine))
    for balance in local_balances.values():
        if balance.get("statistical_parent") != root or balance.get("geographically_unlocated"):
            continue
        unit = balance["unit_id"]
        observed = local[unit]
        local_sex = observed["sex"]
        observed_total = observed["population_value"]
        difference = 294 if observed is agra else 0
        if sum(local_sex.values()) != observed_total or observed_total + difference != balance["endpoint_values"][-1]:
            raise ValueError(f"{unit}: census population and sex counts do not close")
        uncertainty = "The local return covers 294 fewer people than the comparative control. " if difference else ""
        age_bands = regional["bands"]
        method = "Apply observed local sex shares and the joint Agra–Oudh census age profile within each sex."
        age_locator = panel["locator"]
        if version >= 25:
            agra_scope = observed is agra or unit in agra_districts
            age_bands = finer_agra if agra_scope else finer_oudh
            age_locator = f"Provincial Table VII(B), printed pp. 50–51; {age_locator}"
            province = "Agra" if agra_scope else "Oudh"
            method = ("Use Agra's own age bands by sex." if observed is agra else
                      f"Use district sex counts and the {province} age bands within each sex.")
            method += " Divide the broad age bands by the joint Agra–Oudh age profile within each sex."
        yield regional | dict(
            unit_id=unit, observed_unit_id=observed["unit_id"], opening_total=balance["population_value"],
            observed_total=observed_total, source_id=observed["source_id"],
            locator=f"{observed.get('sex_locator', observed['locator'])}; {age_locator}",
            method=method,
            uncertainty=f"{uncertainty}Local age variation, census error and change to January 1900 are unquantified.",
            bands=apportion_local_ages(age_bands, local_sex),
        )


def bengal_district_age_models(panels, observations, balances):
    parent = "raj_bengal_province"
    panel, rows = panels["india_census_1901_table_vii_bengal"]
    provincial = opening_age_group(panel, rows, parent, 0)
    districts = [row for row in observations if row["source_id"] == BENGAL_DISTRICT_SOURCE
                 and row["parent_id"] == parent and row["date"] == panel["observed_date"]]
    if (len(districts) != 48 or any(sum(row["sex"][sex] for row in districts)
            != sum(band[sex] for band in provincial["bands"]) for sex in SEX_COUNTS)):
        raise ValueError("Bengal district census sex counts do not close to the provincial age return")
    for row in districts:
        unit_id = row["unit_id"]
        balance = balances[unit_id]
        observed = row["population_value"]
        if observed != sum(row["sex"].values()) or observed != balance["endpoint_values"][-1]:
            raise ValueError(f"{unit_id}: district population and sex counts do not close")
        yield provincial | dict(
            unit_id=unit_id, observed_unit_id=unit_id, opening_total=balance["population_value"],
            observed_total=observed, source_id=BENGAL_DISTRICT_SOURCE,
            locator=f"{row['sex_locator']}; all-India {panel['locator']}",
            method="Apply the district's 1901 census sex distribution and Bengal's provincial ages "
                   "within each sex to the district's opening population.",
            uncertainty="Age within each sex uses the provincial distribution. Local variation, migration "
                        "and changes from March 1901 have no quantified interval.",
            bands=apportion_local_ages(provincial["bands"], row["sex"]),
        )


def opening_structure(opening_groups, observations, *, version=6):
    district_pools = {unit["unit_id"]: unit for group in opening_groups for unit in group["units"]
                      if "district_boundary_source" in unit}
    leaf_age_scopes = {unit["statistical_parent"] for unit in district_pools.values()} | {
        ENGLAND_WALES_OCCUPATION_REMAINDER, ITALIAN_CIVIL_STATUS_SCOPE, "raj_united_provinces_states",
    }
    if version >= 23:
        leaf_age_scopes.add("raj_mysore_state")
    if version >= 24:
        leaf_age_scopes.add("raj_agra_oudh")
    if version >= 25:
        leaf_age_scopes.update((SPANISH_CIVIL_STATUS_SCOPE, "egy_mudiriya_faiyum"))
    if version >= 27:
        leaf_age_scopes.update(("raj_madras_states", "raj_bengal_province", "administrative_region:uk_constituent_scotland",
                                "administrative_region:uk_constituent_ireland"))
    statistical_aggregates = {
        unit["unit_id"]: unit
        for group in opening_groups
        for unit in group.get("statistical_aggregates", ())
    }
    opening_balances = {
        unit["unit_id"]: unit
        for group in opening_groups
        for unit in (group["units"] or [group])
        if "statistical_parent" not in unit or unit["statistical_parent"] in leaf_age_scopes
    } | {key: unit for key, unit in statistical_aggregates.items() if key not in leaf_age_scopes}
    opening_totals = {unit_id: unit["population_value"] for unit_id, unit in opening_balances.items()}
    groups = []
    panels = {panel["id"]: (panel, rows) for panel, rows in age_sex_panels()}
    for panel, rows in panels.values():
        unit_id = panel.get("opening_unit_id")
        if unit_id is None or not (
            panel.get("opening_from_version", 1) <= version <= panel.get("opening_through_version", version)
        ):
            continue
        if version >= 10 and unit_id in (
            "ft_russia_empire_ussr", "administrative_region:uk_constituent_scotland",
            "administrative_region:uk_constituent_ireland",
        ) and unit_id not in opening_totals:
            continue
        if version >= 27 and unit_id == "raj_bengal_province":
            continue
        model = opening_age_group(panel, rows, unit_id, opening_totals[unit_id])
        if panel.get("opening_match_population_endpoint"):
            balance = opening_balances[unit_id]
            endpoints = balance.get("endpoint_values") or balance["country_endpoint_values"]
            if endpoints[-1] != model["observed_total"] + panel.get("opening_population_endpoint_difference", 0):
                raise ValueError(f"Census age and population controls differ for {unit_id}")
        groups.append(model)
    if version >= 24:
        groups.extend(agra_oudh_local_age_models(panels, observations, opening_balances, version))
    if version >= 25:
        groups.extend(spanish_provincial_age_models(panels, observations, opening_balances))
        verify_national_age_totals(
            panels["be_census_kingdom"][1],
            (rows for panel, rows in panels.values()
             if panel["source_id"] == "be_census_1900_age_and_spoken_languages" and "opening_unit_id" in panel),
            "kingdom_of_belgium",
        )
    if version >= 26:
        groups.extend(portuguese_age_models(panels, observations, opening_balances))
    if version >= 27:
        groups.extend(remaining_indian_states_age_models(panels, opening_balances, observations))
        groups.extend(bengal_district_age_models(panels, observations, opening_balances))
    if version >= 23:
        groups.extend(mysore_local_age_models(panels, observations, opening_balances))
        verify_national_age_totals(
            panels["brazil_1900_dge_1900_ages"][1],
            (rows for panel, rows in panels.values()
             if panel["source_id"] == "br_dge_1916_1900_age_sex" and "opening_unit_id" in panel),
            "brazil_1900",
        )
    if version >= 22:
        check_italian_age_controls(panels, observations)
        groups.extend(united_provinces_state_age_models(
            panels, observations, statistical_aggregates["raj_united_provinces_states"], opening_balances,
        ))
    if version >= 20:
        groups.extend(egypt_provincial_sex_models(opening_balances, observations))
    if version >= 18:
        groups.extend(hungarian_opening_age_models(panels, opening_balances))
    if version >= 13:
        for group in opening_groups:
            if group["unit_id"] == "swiss_confederation":
                swiss = swiss_opening_age_model(panels, group)
                groups.extend(
                    opening_age_group(*swiss, unit["unit_id"], unit["population_value"])
                    for unit in group["units"]
                )
    port_blair = "raj_andaman_nicobar_comparable"
    if version == 14 and port_blair in opening_balances:
        groups.append(port_blair_opening_sex_model(panels, opening_balances[port_blair]))
    if version >= 15:
        abstract_areas = {port_blair: "port_blair", "raj_united_provinces_states": "united_provinces_states"}
        for group in opening_groups:
            for unit in group["units"]:
                unit_id = unit["unit_id"]
                if area := abstract_areas.get(unit_id):
                    dates = unit.get("source_dates") or group["endpoint_dates"]
                    groups.append(indian_abstract_opening_age_model(panels, unit, dates, area))
                elif unit_id == "raj_central_provinces_states":
                    groups.append(central_provinces_states_opening_age_model(panels, unit, group["endpoint_dates"]))
    if version >= 14:
        princely_states = {"raj_travancore_state": "travancore", "raj_cochin_state": "cochin"}
        for group in opening_groups:
            for unit in group["units"]:
                state = princely_states.get(unit["unit_id"])
                if state is not None:
                    groups.append(princely_state_opening_age_model(panels, unit, state))
    if version >= 10:
        models = russian_regional_age_models(panels, observations, district_pools)
        remaining_uk = england_wales_remaining_ages(panels)
        scotland_panel, scotland_rows = panels["scotland_1901"]
        scotland = scotland_panel | dict(
            opening_method="Hold Scotland's 1901 census age and sex shares in each civil county's "
            "January 1900 balance, using integer largest remainders.",
            uncertainty="The census shares are for Scotland as a whole. County differences, the "
            "effect of civil versus other county boundaries, and change from January 1900 are unquantified.",
        ), scotland_rows
        ireland_panel, ireland_rows = panels["ireland_1901"]
        ireland = ireland_panel | dict(
            opening_method="Hold Ireland's 1901 census age and sex shares in each administrative "
            "county and county borough balance at January 1900, using integer largest remainders.",
            uncertainty="The age and sex shares are for Ireland as a whole. Regional differences, "
            "the effect of administrative boundaries, and change from January 1900 are unquantified.",
        ), ireland_rows
        japan_panel, japan_rows = panels["japan_1899_resident_reconstruction"]
        japan = japan_panel, regroup_single_years(japan_rows)
        france_panel, france_rows = panels["france_1901"]
        france = france_panel | dict(
            opening_band_roles=["band", "mixed_age_band"],
            opening_method="Hold the 1901 metropolitan present-population shares in the January 1900 "
            "legal-population balance of each historical département and use integer largest remainders.",
            uncertainty="The national table covers residents present with sex known. It excludes "
            "16,136 residents whose sex was undetermined. The last published age band combines the "
            "oldest residents and unreported ages, so it is assigned unknown age. Provincial differences, "
            "the legal versus present population, and change between January 1900 and March 1901 are unquantified.",
        )
        france_aggregate = france | dict(
            opening_method=france["opening_method"] + " Province-rounded cells are allocated across qualifying "
            "arrondissements in proportion to their remaining anonymous capacity, with cumulative integer rounding.",
        )
        used = {group["unit_id"] for group in groups}
        for unit_id, unit in opening_balances.items():
            if unit_id in used:
                continue
            model = models.get(unit_id)
            parent = unit.get("subdivision_of")
            if unit_id.startswith("administrative_region:gb_historic_") or unit_id == "uk_ancient_kent_middlesex_surrey":
                model = remaining_uk
            elif parent == "administrative_region:uk_constituent_scotland":
                model = scotland
            elif parent == "administrative_region:uk_constituent_ireland":
                model = ireland
            elif unit_id.startswith("administrative_region:france_"):
                model = (france_aggregate if unit_id in statistical_aggregates else france), france_rows
            elif unit_id == "empire_of_japan" or unit_id.startswith("jp_otsu_pref_"):
                model = japan
            if model is not None:
                groups.append(opening_age_group(*model, unit_id, unit["population_value"]))
    unit = "statistical_area:bosnia_herzegovina_1900"
    if unit in opening_totals:
        row = next(r for r in observations if r["unit_id"] == unit and r["date"] == "1895-04-22"
                   and r["source_id"] == "bosnia_herzegovina_demography_2024")
        if sum(row["sex"].values()) != row["population_value"]:
            raise ValueError(f"{unit}: published sex totals do not sum to the population")
        groups.append(dict(
            unit_id=unit, opening_total=opening_totals[unit], observed_total=row["population_value"],
            source_id=row["source_id"], observed_unit_id=unit, observed_date=row["date"], locator=row["locator"],
            method="Hold the nearer 1895 civilian census sex shares at opening and use integer largest remainders. Ages are unknown.",
            uncertainty="The sex ratio may have changed. Both dated census controls remain available. No opening error interval is known.",
            sex_only=True,
            bands=[dict(id="unknown", label="Published sex totals; ages unavailable", age_min=None, age_max=None, **row["sex"])],
        ))
    return dict(version=1, groups=sorted(groups, key=lambda group: group["unit_id"]))
