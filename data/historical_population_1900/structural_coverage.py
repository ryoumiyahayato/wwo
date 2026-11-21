"""Index reviewed dated population-structure panels without allocating opening residents."""

from collections import defaultdict


DIMENSIONS = ("residence", "households", "housing", "literacy", "occupation", "religion",
              "education", "labor_force", "health", "military_eligibility", "language", "social_status")
RUSSIA = "ru_census_1897_ex_finland"
US = "us_twelfth_census_entire_enumeration"


def _panel(panel_id, dimension, row, research_units, opening_links, classification,
           universe, measure_unit="persons", denominator=None, categories=(), closure="none",
           locator=None, status="reviewed"):
    categories = list(categories)
    classified = None
    if closure in ("complete_partition", "reported_subset"):
        if not categories or not all(type(cell["count"]) is int and cell["count"] >= 0 for cell in categories):
            status = "candidate"
        elif type(denominator) is int and denominator > 0:
            subtotal = sum(cell["count"] for cell in categories)
            if subtotal == denominator or closure == "reported_subset" and subtotal < denominator:
                classified = subtotal
            else:
                status = "candidate"
        else:
            status = "candidate"
    return dict(
        panel_id=panel_id, dimension=dimension, status=status, observed_unit_id=row["unit_id"],
        observed_date=row["date"], source_id=row["source_id"], locator=locator or row["locator"],
        classification_id=classification, eligible_universe=universe, measure_unit=measure_unit,
        eligible_denominator=denominator, directly_classified_count=classified,
        category_relationship=closure, categories=categories, research_unit_ids=research_units,
        opening_links=[dict(unit_id=key, scope_relation=relation) for key, relation in opening_links],
    )


def _cell(label, count, row, role="category"):
    return dict(label=label, count=count, locator=row["locator"], role=role)


def _residence_panel(panel_id, row, research_unit, root, universe):
    counts = row["breakdowns"]["residence"]
    locator = row["breakdown_locator"]
    cells = [_cell(label, counts[label], {"locator": locator}) for label in ("urban", "rural")]
    return _panel(panel_id, "residence", row, [research_unit], [(root, "unresolved")], panel_id,
                  universe, denominator=row["population_value"], categories=cells,
                  closure="complete_partition", locator=locator)


def _reviewed_panels(population, structural):
    dated = {(row["source_id"], row["unit_id"], row["date"]): row for row in population
             if "residence" in row.get("breakdowns", {})}
    structural_by_source_unit = defaultdict(list)
    for row in structural:
        structural_by_source_unit[row["source_id"], row["unit_id"]].append(row)

    russia_research = ["ft_russia_empire_ussr"]
    russia_opening = [("russian_empire", "subset")]
    russian_universe = ("Residents in the published 1897 enumeration of the Russian Empire excluding "
                        "Finland, Khiva, Bukhara and the table's separate extra-territorial and at-sea return.")
    religion = [row for row in structural_by_source_unit["rus_rel_97", RUSSIA]
                if row["locator"].startswith("rus_rel_97.php?reg=0, row ")]
    religion_total = next((row for row in religion if row["category"] == "ИТОГО"), None)
    if religion_total:
        yield _panel("russia_1897_religion", "religion", religion_total, russia_research, russia_opening,
                     "russian_1897_reported_confession", russian_universe,
                     denominator=religion_total["values"]["both"],
                     categories=[_cell(row["category"], row["values"]["both"], row) for row in religion
                                 if 2 <= int(row["locator"].rsplit(" ", 1)[-1]) <= 17],
                     closure="complete_partition", locator="rus_rel_97.php?reg=0, rows 2–18")
    language = {int(row["locator"].rsplit(" ", 1)[-1]): row
                for row in structural_by_source_unit["rus_lan_97", RUSSIA]
                if row["locator"].startswith("rus_lan_97.php?reg=0, row ")}
    if all(index in language for index in range(2, 110)):
        # Row 5 repeats rows 2–4 as a subtotal. Row 108 has no recorded mother tongue.
        cells = [_cell(language[index]["category"], language[index]["values"]["both"], language[index])
                 for index in range(2, 108) if index != 5]
        total, unreported = language[109]["values"]["both"], language[108]["values"]["both"]
        if sum(cell["count"] for cell in cells) + unreported == total:
            panel = _panel("russia_1897_mother_tongue", "language", language[109], russia_research, russia_opening,
                           "russian_1897_reported_mother_tongue", russian_universe,
                           denominator=total, categories=cells, closure="reported_subset",
                           locator="Table XIII; rus_lan_97.php?reg=0, rows 2–109")
            panel["unreported_count"] = unreported
            yield panel
    legal_estates = {int(row["locator"].rsplit(" ", 1)[-1]): row
                     for row in structural_by_source_unit["rus_sos_97", RUSSIA]
                     if row["locator"].startswith("rus_sos_97.php?reg=0, row ")}
    if all(index in legal_estates for index in range(2, 17)):
        russian_subjects = legal_estates[14]["values"]["both"]
        foreign_subjects = legal_estates[15]["values"]["both"]
        all_subjects = legal_estates[16]["values"]["both"]
        unreported = legal_estates[13]["values"]["both"]
        cells = [_cell(legal_estates[index]["category"], legal_estates[index]["values"]["both"],
                       legal_estates[index], "published_residual" if index in (11, 12) else "category")
                 for index in range(2, 13)]
        if sum(cell["count"] for cell in cells) + unreported == russian_subjects and (
            russian_subjects + foreign_subjects == all_subjects
        ):
            panel = _panel("russia_1897_legal_estates", "social_status", legal_estates[14],
                           russia_research, russia_opening, "russian_1897_reported_legal_estate",
                           "Russian subjects in the empire-wide Table VIII return. Published residual "
                           "categories include Finnish natives without estate distinction and persons "
                           "outside the listed estates. Foreign subjects are outside this denominator.",
                           denominator=russian_subjects, categories=cells, closure="reported_subset",
                           locator="Table VIII; rus_sos_97.php?reg=0, rows 2–16")
            panel["unreported_count"] = unreported
            panel["foreign_subjects_outside_denominator"] = foreign_subjects
            panel["table_total_all_subjects"] = all_subjects
            yield panel
    jp_legal = structural_by_source_unit["jp_cabinet_population_1898_original", "japan_proper_honseki_1898"]
    jp_total = next((row for row in jp_legal if row["row_role"] == "total"), None)
    if jp_total:
        yield _panel("japan_1898_register_legal_status", "social_status", jp_total, ["ft_japan"],
                     [("empire_of_japan", "different_population_universe")], "japan_1898_registered_legal_status",
                     jp_total["definition"], denominator=jp_total["values"]["both"],
                     categories=[_cell(row["category"], row["values"]["both"], row) for row in jp_legal
                                 if row["row_role"] == "band"], closure="complete_partition")
    tokyo = structural_by_source_unit["jp_cabinet_local_occupations_1913_tokyo", "tokyo_city_1900_occupational_persons"]
    tokyo_total = next((row for row in tokyo if row["row_role"] == "total"), None)
    if tokyo_total:
        yield _panel(tokyo_total["panel_id"], "occupation", tokyo_total, ["ft_japan"],
                     [("empire_of_japan", "subset_with_distinct_definition")], "tokyo_1900_three_reported_occupations",
                     tokyo_total["definition"], denominator=tokyo_total["values"]["both"],
                     categories=[_cell(row["category"], row["values"]["both"], row) for row in tokyo
                                 if row["row_role"] == "band"], closure="complete_partition")
    literacy = next((row for row in structural_by_source_unit["rus_age_97", RUSSIA]
                     if row["row_role"] == "total"), None)
    if literacy:
        yield _panel("russia_1897_literacy", "literacy", literacy, russia_research, russia_opening,
                     "russian_1897_recorded_literacy_all_ages", russian_universe + " All ages.",
                     denominator=literacy["values"]["both"],
                     categories=[_cell("recorded_literate", literacy["values"]["literate_both"], literacy)],
                     closure="reported_subset")
        residence = []
        for parameter, label in ((7, "cities"), (13, "uyezds")):
            totals = structural_by_source_unit["rus_age_97", f"rus_age_97:reg:{parameter}"]
            component = next((row for row in totals if row["category"] == "ИТОГО"), None)
            if component:
                residence.append(_cell(label, component["values"]["both"], component))
        yield _panel("russia_1897_residence", "residence", literacy, russia_research, russia_opening,
                     "russian_1897_administrative_city_and_uyezd",
                     russian_universe + " Uyezds follow the census's administrative definition.",
                     denominator=literacy["values"]["both"], categories=residence,
                     closure="complete_partition", locator="rus_age_97.php, reg=0, 7 and 13; row 126 each")

    for row in structural_by_source_unit["england_wales_census_1901_general_report", "uk_england_wales"]:
        if row["date"] != "1901-03-31" or row["dimension"] != "housing_and_urban_rural":
            continue
        values = row["values"]
        research_units = ["ft_united_kingdom"]
        opening_links = [("british_isles_1900", "subset")]
        yield _panel("england_wales_1901_residence", "residence", row, research_units,
                     opening_links, "england_wales_1901_statutory_district",
                     "Census-night persons in statutory districts of England and Wales. Separate housing "
                     "occupations, room categories and overcrowding observations are outside this partition.",
                     denominator=values["total_population"], closure="complete_partition",
                     categories=[_cell(label, values["districts"][label]["population"], row)
                                 for label in ("urban", "rural")])
        occupants_panel_id = "england_wales_1901_occupants_by_tenement_rooms"
        tenements_panel_id = "england_wales_1901_tenements_by_rooms"
        by_rooms = values["by_rooms_in_tenement"]
        room_locator = "General Report, section III, Tenement Statistics (England and Wales) in 1891 and 1901."
        room_row = {**row, "locator": room_locator}
        yield _panel(occupants_panel_id, "housing", room_row, research_units, opening_links,
                     "england_wales_1901_rooms_per_tenement",
                     "Census-night persons classified by rooms in their tenement in England and Wales.",
                     denominator=values["total_population"], closure="complete_partition",
                     categories=[_cell(label, counts["occupants"], room_row) for label, counts in by_rooms.items()])
        yield _panel(tenements_panel_id, "housing", room_row, research_units, opening_links,
                     "england_wales_1901_rooms_per_tenement",
                     "Tenements or separate occupations in England and Wales, classified by rooms.",
                     measure_unit="tenements", denominator=values["separate_occupations"],
                     closure="complete_partition",
                     categories=[_cell(label, counts["tenements"], room_row) for label, counts in by_rooms.items()])
        housing = _panel("england_wales_1901_crowded_small_tenements", "housing", row, research_units,
                         opening_links, "england_wales_1901_more_than_two_occupants_per_room",
                         row["definition"], denominator=values["total_population"], closure="reported_subset",
                         categories=[_cell(label, values["districts"][label]["occupants_of_these_tenements"], row)
                                     for label in ("urban", "rural")])
        housing["count_of_reported_tenements"] = values["overcrowded_tenements_1_to_4_rooms"]
        housing["by_rooms_in_reported_tenement"] = values["by_rooms_in_overcrowded_tenement"]
        housing["subset_of_panel_id"] = occupants_panel_id
        housing["tenement_subset_of_panel_id"] = tenements_panel_id
        yield housing

    for panel_id, source, unit, date, research, root, universe in (
        ("india_1901_residence", "india_statistical_abstract_1905", "raj_indian_empire", "1901-03-01",
         "ft_india", "cshapes_gw_750", "Persons in the published Indian Empire census area, including Burma, "
         "Aden and princely states. About 2.5 million people were in newly enumerated areas. The opening "
         "common-area census basis omits Aden, and the retained legacy frontier extent is unresolved."),
        ("cape_1904_residence", "british_empire_census_1901", "cape_colony", "1904-04-18",
         "ft_south_africa", "cshapes_gw_561", "Persons in the Cape Colony as tabulated in the 1904 postwar "
         "return. Urban and rural follow its printed categories. Comparison with the 1899 estimate's "
         "universe cannot isolate displacement or establish identical coverage."),
    ):
        row = dated.get((source, unit, date))
        if row:
            yield _residence_panel(panel_id, row, research, root, universe)

    for row in structural_by_source_unit["swiss_federal_census_comparison_1911", "swiss_confederation"]:
        if row["date"] != "1900-12-01" or row["category"] != "households and persons":
            continue
        counts = row["values"]
        panel = _panel("switzerland_1900_households", "households", row, ["ft_switzerland"],
                       [("swiss_confederation", "same_extent")], "swiss_1900_published_household_count",
                       row["definition"], measure_unit="households",
                       categories=[_cell("published_households", counts["households"], row, "published_count")])
        panel["comparison_population"] = {key: counts[key] for key in ("ordinary_residents", "persons_present")}
        yield panel

    occupation = [row for row in structural_by_source_unit["us_occupation_special_report", US]
                  if row["date"] == "1900-06-01"]
    eligible = next((row for row in occupation if row["category"] == "Population age 10 and over"), None)
    control = next((row for row in occupation if row["category"] == "All occupations"), None)
    if eligible and control:
        labels = ("Agricultural pursuits", "Professional service", "Domestic and personal service",
                  "Trade and transportation", "Manufacturing and mechanical pursuits")
        rows = {row["category"]: row for row in occupation if row["category"] in labels}
        cells = [_cell(label, rows[label]["values"]["total"], rows[label]) for label in labels if label in rows]
        partition_closes = len(cells) == len(labels) and sum(cell["count"] for cell in cells) == control["values"]["total"]
        yield _panel("us_1900_gainful_occupations", "occupation", eligible, ["ft_united_states", "ft_hawai"],
                     [(key, "wider") for key in ("united_states_1900", "cshapes_gw_3", "cshapes_gw_4")],
                     "us_1900_gainful_occupation_classes_age_10_and_over", eligible["definition"],
                     denominator=eligible["values"]["total"], categories=cells,
                     closure="reported_subset" if partition_closes else "none",
                     locator="General Tables no. 1, pp. 7–8", status="reviewed" if partition_closes else "candidate")


def _candidates(population):
    for row in population:
        if (row["source_id"], row["unit_id"], row["date"]) == (
            "us_census_puerto_rico_1899", "cshapes_gw_6", "1887",
        ):
            yield _panel("puerto_rico_1887_literacy", "literacy", row, ["ft_puerto_rico"],
                         [("cshapes_gw_6", "unresolved")], None, row["definition"], status="candidate")
        elif (row["source_id"], row["unit_id"], row["date"]) == (
            "tw_governor_general_1900", "tw_urban_taipei_three_towns", "1900-12-31",
        ):
            yield _panel("taiwan_1900_residence", "residence", row, ["ft_formosa_taiwan"],
                         [("taiwan_under_japan", "subset")], None, row["definition"], status="candidate")


def _coverage(roots, panels):
    dimensions = {}
    people = sum(roots.values())
    for dimension in DIMENSIONS:
        rows = [panel for panel in panels if panel["dimension"] == dimension]
        same_extent = sorted({link["unit_id"] for panel in rows if panel["status"] == "reviewed"
                              for link in panel["opening_links"]
                              if link["scope_relation"] == "same_extent" and link["unit_id"] in roots})
        dimensions[dimension] = dict(
            reviewed_panels=[row["panel_id"] for row in rows if row["status"] == "reviewed"],
            candidate_panels=[row["panel_id"] for row in rows if row["status"] == "candidate"],
            opening_roots_with_same_extent_dated_panel=same_extent,
            opening_known_people=None, opening_unknown_people=people, opening_status="unknown",
        )
    return dimensions


def structural_coverage(population, structural, geography, selection, *, legacy=()):
    """Return date-scoped evidence and lookup summaries. Pass legacy audit for all formal roots."""
    panels = sorted([*_reviewed_panels(population, structural), *_candidates(population)],
                    key=lambda panel: panel["panel_id"])
    research = {row["id"]: row for row in geography if row["catalogue"] == "research_territory"}
    roots = {row["unit_id"]: row["population_value"] for row in legacy if row["status"] == "legacy_only"}
    roots.update({row["unit_id"]: row["population_value"] for row in selection})
    root_regions = defaultdict(set)
    for row in research.values():
        for root in row["opening_candidates"]:
            root_regions[root].add(row["region"])
    for panel in panels:
        panel["research_regions"] = sorted({research[key]["region"] for key in panel["research_unit_ids"]
                                             if key in research})
    regions = {}
    for region in sorted({row["region"] for row in research.values()}):
        # Cross-region panels remain discoverable, with their single unsplit observation in panels.
        region_roots = {key: people for key, people in roots.items() if root_regions[key] == {region}}
        regions[region] = dict(opening_root_count=len(region_roots), dimensions=_coverage(
            region_roots, [panel for panel in panels if region in panel["research_regions"]]))
    unassigned_roots = {key: people for key, people in roots.items() if len(root_regions[key]) != 1}
    return dict(
        version=1, opening_date="1900-01-01", panels={panel["panel_id"]: panel for panel in panels},
        world=dict(opening_root_count=len(roots), dimensions=_coverage(roots, panels)),
        research_regions=regions,
        no_unique_research_region=dict(opening_root_count=len(unassigned_roots),
                                       dimensions=_coverage(unassigned_roots, [])),
        opening_roots={key: dict(opening_people=roots[key], research_regions=sorted(root_regions[key]),
                                 dimensions=_coverage({key: roots[key]}, [panel for panel in panels
                                     if any(link["unit_id"] == key for link in panel["opening_links"])]))
                       for key in sorted(roots)},
        accounting_note=("Counts are dated within the stated eligible universe. Directly classified counts "
                         "apply only within one panel. Panel references across roots or regions repeat the "
                         "same observation. Opening and cross-panel totals are unknown."),
    )
