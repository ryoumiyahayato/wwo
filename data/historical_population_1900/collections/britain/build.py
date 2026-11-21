from pathlib import Path
from fractions import Fraction
from datetime import date
import json

HERE = Path(__file__).resolve().parent
SRC = "uk_general_census_report_1901"
DATES = ["1891-04-05", "1901-03-31"]
OPEN = date(1900, 1, 1)
PARENT = "british_isles_1900"
loc = "General Report, section The United Kingdom, population table by division, 1891 and 1901"
source = dict(
    id=SRC,
    title="Census of England and Wales, 1901. General Report with Appendices",
    publisher="General Register Office / HMSO (London, 1904)",
    url="https://www.visionofbritain.org.uk/census/EW1901GEN/14",
    locator=loc,
    rights="Historical census numbers transcribed; digital report is linked.",
    companion_table="https://wellcomecollection.org/works/mbq6vgjb",
    dates_reference="https://www.nationalarchives.gov.uk/help-with-your-research/research-guides/census-records/",
)
# Published census divisions. Ireland covers the whole island. The Isle of Man,
# the Channel Islands, and personnel overseas are outside this table.
divisions = [
    ("uk_england_wales", "England and Wales", 29002525, 32527843),
    ("uk_scotland", "Scotland", 4025647, 4472103),
    ("uk_ireland", "Ireland", 4704750, 4458775),
]


def emit(name, data):
    (HERE / name).write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def observed(uid, name, parent, kind, val, dt, source_id, locator, definition):
    return dict(
        unit_id=uid,
        name=name,
        parent_id=parent,
        kind=kind,
        population_value=val,
        population_lower=None,
        population_upper=None,
        date=dt,
        source_id=source_id,
        locator=locator,
        definition=definition,
        method="published_census_return",
        mapping_status="matched_historical_division"
        if source_id == SRC
        else "historical_unit_unlinked",
        quality="historical_census",
        region="Europe",
    )


definition = "Persons enumerated in the named division on census night. Ireland includes the whole island. Overseas forces, the Channel Islands and the Isle of Man are outside the United Kingdom total in this table."
totals = [37732922, 41458721]
obs = [
    observed(
        "uk_census_territory",
        "United Kingdom of Great Britain and Ireland",
        None,
        "country",
        x,
        dt,
        SRC,
        loc + ", United Kingdom",
        definition,
    )
    for dt, x in zip(DATES, totals)
]
for r in obs:
    r["wwo_id"] = PARENT
fraction = Fraction(
    (OPEN - date.fromisoformat(DATES[0])).days,
    (date.fromisoformat(DATES[1]) - date.fromisoformat(DATES[0])).days,
)
units = []
expected = {}
for uid, name, a, b in divisions:
    for dt, v in zip(DATES, [a, b]):
        obs.append(
            observed(
                uid,
                name,
                "uk_census_territory",
                "admin",
                v,
                dt,
                SRC,
                loc + ", " + name,
                definition,
            )
        )
    expected[uid] = a + (b - a) * fraction
    units.append(
        dict(
            unit_id=uid,
            name=name,
            endpoint_values=[a, b],
            population_value=int(expected[uid]),
            place_ids=["place:london", "place:dover"]
            if uid == "uk_england_wales"
            else [],
            locator=loc + ", " + name,
        )
    )
target = round(totals[0] + (totals[1] - totals[0]) * fraction)
for u in sorted(
    units, key=lambda u: expected[u["unit_id"]] - u["population_value"], reverse=True
)[: target - sum(u["population_value"] for u in units)]:
    u["population_value"] += 1
emit(
    "uk_opening.json",
    dict(
        unit_id=PARENT,
        date=OPEN.isoformat(),
        source_id=SRC,
        locator=loc,
        endpoint_dates=DATES,
        country_endpoint_values=totals,
        method=f"Linear interpolation over {fraction.numerator}/{fraction.denominator} elapsed days in the three census divisions. Integer counts apportioned by largest remainders to the interpolated United Kingdom total.",
        population_value=target,
        units=units,
    ),
)
sources = [source]

sid = "ireland_general_census_1911"
sources.append(
    dict(
        id=sid,
        title="Census of Ireland, 1911. General Report, with Tables and Appendix",
        publisher="Census of Ireland; HMSO (Dublin, 1913); digitized by Central Statistics Office",
        url="https://www.cso.ie/en/media/csoie/releasespublications/documents/ep/storiesfromcensus1911/census1911originalreports/459-General_report%2C_Ireland%2C_1911.pdf",
        locator="Tables 43 (p. 62), 48 and 48A (p. 65), PDF leaves 128 and 131.",
        rights="Historical census counts transcribed; the digitized original is linked.",
    )
)
provinces = [
    ("Leinster", 1187760, 1152829),
    ("Munster", 1172402, 1076188),
    ("Ulster", 1619814, 1582826),
    ("Connaught", 724774, 646932),
]
import re


def key(n):
    return re.sub("[^a-z0-9]+", "_", n.lower()).strip("_")


for n, a, b in provinces:
    for dt, v in zip(DATES, [a, b]):
        obs.append(
            observed(
                "irish_province_" + key(n),
                n,
                "uk_ireland",
                "admin",
                v,
                dt,
                sid,
                "Table 43 p. 62, Persons, " + n,
                "Persons in the province at the time of each census, historical provincial boundaries.",
            )
        )
counties = """Leinster|Dublin|157568|172394
Leinster|Kildare|63566|66627
Connaught|Leitrim|69343|63582
Connaught|Roscommon|101791|93956
Munster|Clare|112334|104232
Ulster|Cavan|97541|91173
Munster|Waterford|60418|56502
Leinster|Longford|46672|43820
Connaught|Sligo|84083|79045
Leinster|King's|60187|56832
Ulster|Fermanagh|65430|61836
Connaught|Galway|192549|182224
Leinster|Kilkenny|79159|74962
Ulster|Tyrone|150567|142665
Munster|Tipperary (North and South Ridings)|160232|152433
Leinster|Queen's|57417|54629
Ulster|Londonderry|104512|99845
Ulster|Monaghan|74611|71455
Ulster|Armagh|125392|120291
Munster|Cork|328489|315431
Leinster|Carlow|37748|36252
Munster|Kerry|165726|159691
Leinster|Meath|67497|65091
Connaught|Mayo|199166|192177
Leinster|Louth|65820|63665
Munster|Limerick|107947|104551
Ulster|Donegal|173722|168537
Leinster|Westmeath|61629|59986
Leinster|Wexford|104104|102273
Ulster|Antrim|196090|193864
Ulster|Down|205889|204303
Leinster|Wicklow|60824|60711"""
boroughs = """Ulster|Belfast|349180|386947
Leinster|Dublin|290638|304802
Munster|Waterford|26769|27464
Ulster|Londonderry|39892|40780
Munster|Limerick|38151|38518
Munster|Cork|76122|76673"""
for cat, rows, tab in [("county", counties, "48"), ("county_borough", boroughs, "48A")]:
    for ln in rows.splitlines():
        province, n, v, y = ln.split("|")
        for dt, num in [("1901-03-31", v), ("1911-04-02", y)]:
            obs.append(
                observed(
                    "irish_" + cat + "_" + key(n),
                    n + (" County Borough" if cat == "county_borough" else " County"),
                    "irish_province_" + key(province),
                    "city" if cat == "county_borough" else "admin",
                    int(num),
                    dt,
                    sid,
                    "Table " + tab + ", p. 65, " + n,
                    "Persons enumerated in the comparison area reported in 1911. County boroughs are separate from administrative counties. Tipperary’s ridings are reported jointly.",
                )
            )

county_sid = "england_wales_summary_tables_1901"
sources.append(
    dict(
        id=county_sid,
        title="Census of England and Wales, 1901. Summary Tables",
        publisher="General Register Office / HMSO, London; Wellcome Collection",
        url="https://wellcomecollection.org/works/ka7g6w5z/items?manifest=6&canvas=16",
        locator="Table III, printed p. 6, Ancient Counties, Persons 1891 and 1901.",
        rights="Historical census facts transcribed. Wellcome Collection marks the digitized volume Public Domain Mark.",
        manifest_url="https://iiif.wellcomecollection.org/presentation/v2/b32183161_0006",
        page_image="https://iiif.wellcomecollection.org/image/b32183161_0006_0016.jp2/full/2100,/0/default.jpg",
    )
)
table3 = (HERE / "ancient_counties_1901.txt").read_text(encoding="utf-8").splitlines()
part = "England"
for i, line in enumerate(table3):
    name, old, new = line.split("|")
    if name == "Anglesey":
        part = "Wales"
    is_total = name in ("England", "Wales")
    parent = "uk_england_wales" if is_total else "uk_ancient_area_" + key(part)
    k = "benchmark" if is_total else "admin"
    de = "Persons in the ancient county geography as presented in the 1901 summary. Its England column includes Monmouthshire. London is distributed among Middlesex, Kent and Surrey. The parliamentary borough of York is reported separately from the three Ridings."
    for dt, n in zip(DATES, [old, new]):
        obs.append(
            observed(
                "uk_ancient_area_" + key(name),
                name,
                parent,
                k,
                int(n),
                dt,
                county_sid,
                "Table III, p. 6, " + name + ", Persons " + dt[:4],
                de,
            )
        )

emit("sources.json", sources)
(HERE / "observations.jsonl").write_text(
    "".join(
        json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n"
        for r in sorted(obs, key=lambda r: (r["unit_id"], r["date"], r["source_id"]))
    ),
    encoding="utf-8",
)
