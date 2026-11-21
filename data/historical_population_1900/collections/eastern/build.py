"""Rebuild the eastern population collections offline using Python 3.

Files in raw retain just the relevant numeric cells and row labels of the linked
Indian and Egyptian tables. Other short numeric transcriptions are next to their
source citations in this script. Run python build.py from any working directory.
"""

from pathlib import Path
import json, re

out = Path(__file__).resolve().parent
out.mkdir(exist_ok=True, parents=True)
raw = out / "raw"
obs = []
sources = []


def src(id, title, publisher, url, locator, rights, **kw):
    sources.append(
        dict(
            id=id,
            title=title,
            publisher=publisher,
            url=url,
            locator=locator,
            rights=rights,
            **kw,
        )
    )


def slug(s):
    return re.sub("[^a-z0-9]+", "_", s.lower()).strip("_")


def add(
    uid,
    name,
    parent,
    kind,
    val,
    date,
    s,
    loc,
    definition,
    method,
    reg,
    quality="historical_census",
    map="historical_unit_unlinked",
    wwo=None,
    **kw,
):
    r = dict(
        unit_id=uid,
        name=name,
        parent_id=parent,
        kind=kind,
        population_value=val,
        population_lower=None,
        population_upper=None,
        date=date,
        source_id=s,
        locator=loc,
        definition=definition,
        method=method,
        mapping_status=map,
        quality=quality,
        region=reg,
    )
    if wwo:
        r["wwo_id"] = wwo
    r.update(kw)
    obs.append(r)


base = "https://dsal.uchicago.edu/statistics/1894_excel/"
ds = "india_statistical_abstract_1905"
src(
    ds,
    "Statistical Abstract Relating to British India, 1894–95 to 1903–04, no. 39",
    "India Office / HMSO (London, 1905); Digital South Asia Library, University of Chicago",
    base + "index.html",
    "Tables 1, 2 and 6; separate table workbooks",
    "1905 statistical publication. Numeric facts transcribed; the digital workbooks are linked.",
    files={str(i): base + f"1894.{i:03}.XLS" for i in (1, 2, 6)},
)
emp = "british_empire_census_1901"
src(
    emp,
    "Census of the British Empire, 1901",
    "General Register Office / HMSO (London, 1906)",
    "https://wellcomecollection.org/works/mbq6vgjb",
    "Summary table 2 (pp. 2–6); census dates p. 71; individual colony tables as cited",
    "Wellcome Collection marks its digital copy Public Domain Mark 1.0.",
    manifest_url="https://iiif.wellcomecollection.org/presentation/v2/b32183173",
)


def sheet(i):
    return json.loads((raw / f"india_table_{i}.json").read_text(encoding="utf-8"))


p = sheet(2)


def stripno(s):
    return re.sub(r"^\d+\.\s*", "", s)


def ind(s):
    return "raj_" + slug(s)


names = {i: stripno(p[i][0]) for i in [*range(5, 25), *range(26, 44)]}
ids = {i: ind(n) for i, n in names.items()}
ids[43] = "raj_indian_empire"
india = ids[43]
children = {
    12: 11,
    13: 11,
    14: 11,
    22: 21,
    23: 21,
    31: 30,
    36: 35,
    37: 35,
    24: 43,
    42: 43,
}
for i in names:
    n = names[i]
    parent = None if i == 43 else ids[children.get(i, 24 if i < 24 else 42)]
    notes = {
        6: "1901 newly counts Andamanese and Nicobarese.",
        7: "1901 includes Manipur and all Lushai Hills. Manipur was missing in 1891.",
        8: "Some tracts imperfectly enumerated. Western Sinjrani excluded.",
        15: "Shan States, Chin Hills and Karenni added at the 1901 enumeration.",
        19: "Retrospective tabulation for the North-West Frontier Province formed later in 1901; coverage expanded.",
        20: "Punjab figure excludes the separately tabulated North-West Frontier Province.",
        21: "Historical combined Agra and Oudh census area, named retrospectively.",
        27: "Territory of the princely state.",
        28: "The earlier series added Sikkim in 1891.",
        26: "First included in 1901; partially estimated.",
        40: "Includes a rough Bhil estimate in 1891.",
        43: "Includes Burma, Aden and princely states. About 2.5 million persons in the 1901 count were in newly enumerated areas.",
    }.get(i, "")
    for col, dt in ((1, "1901-03-01"), (2, "1891"), (3, "1881")):
        value = p[i][col]
        if not isinstance(value, float):
            continue
        de = "Persons in the published historical census area. " + notes
        add(
            ids[i],
            n,
            parent,
            "benchmark" if i in (24, 42, 43) else "admin",
            int(value),
            dt,
            ds,
            f"Table 2, {n}, {dt[:4]} column (row {i + 1}); coverage notes in tables 1–2.",
            de.strip(),
            "published_census_return",
            "Asia",
            quality="mixed_or_changing_coverage"
            if i in (6, 7, 8, 15, 19, 26, 28, 40, 43)
            else "historical_census",
        )
s = sheet(6)
for i in range(3, len(s)):
    name, province, district, value, delta = s[i]
    name = stripno(name)
    if not province:
        province = "Bengal"
        district = "24 Parganas"
    parent_idx = {
        "Bengal": 9,
        "Bombay": 12,
        "Madras": 18,
        "Hyderabad": 33,
        "United Provinces": 21,
        "Burma": 15,
        "Punjab": 20,
        "Rajputana": 40,
        "Mysore": 38,
        "Central Provinces": 16,
        "Kashmir": 34,
        "Sind": 13,
        "Baroda": 27,
        "N. W. F. Province": 19,
        "Central India": 30,
        "Ajmer-Merwara": 5,
        "Assam": 7,
    }[province]
    parent_idx = {39: 31, 44: 41, 72: 37, 76: 29, 78: 29, 79: 29, 80: 39}.get(
        i, parent_idx
    )
    parent = ids[parent_idx]
    if i in range(4, 9):
        parent = "raj_city_bengal_calcutta_and_suburbs"
    uid = "raj_city_" + slug(province) + "_" + slug(name)
    desc = (
        "Persons in the listed town or aggregation, including the cantonment only where named. The Calcutta and Suburbs aggregate contains rows 5–9."
        if i <= 8
        else "Published town population; the name records whether a cantonment was included."
    )
    loc = f"Table 6, workbook row {i + 1}, {province}, {district}, {name}"
    add(
        uid,
        name,
        parent,
        "city",
        int(value),
        "1901-03-01",
        ds,
        loc + ", total 1901",
        desc,
        "published_census_return",
        "Asia",
        source_district=district,
    )
    if isinstance(delta, str) and delta.strip() not in ("-", ""):
        d = int(delta.replace(" ", "").replace(",", ""))
        add(
            uid,
            name,
            parent,
            "city",
            int(value) - d,
            "1891",
            ds,
            loc + ", 1901 total and signed change since 1891",
            desc,
            "1901_total_minus_published_signed_change",
            "Asia",
            source_district=district,
            signed_change_1891_to_1901=d,
        )

qy = "china_year_book_1919"
src(
    qy,
    "The China Year Book, 1919–20",
    "H. G. W. Woodhead and H. T. Montague Bell (editors), Tientsin: The Tientsin Press",
    "https://www.bnasie.eu/Asset/Source/bnBook_ID-2751_No-01.pdf",
    "Chapter I, pp. 1–3; PDF leaves 27–29. Population table p. 3 is printed sideways.",
    "1919 publication. Numeric facts transcribed directly from the scan.",
)
cq = "cao_qing_provincial_reconstruction"
src(
    cq,
    "Population Expansion and Demographic Pressure in Qing China (1644–1911)",
    "Tsinghua University Press; data credited to Cao Shuji, Population History, vol. 4 pp. 451–452 and vol. 5 pp. 703–704",
    "https://www.tup.tsinghua.edu.cn/upload/books/yz/096340-01.pdf",
    "Chapter 1, Table 1.1, printed pp. 17–18 (PDF pp. 31–32), 1880 and 1910 columns.",
    "Numeric facts with attribution; no publisher text, figures or scans redistributed.",
)
# Numbers in the first two columns and in the last three columns are in thousands.
china = """Jiangsu|Kiangsu|29491|32355|21300|17300|23980
Zhejiang|Chekiang|16029|18490|11700|17000|11800
Jiangxi|Kiangsi|13316|14961|24500|14500|24534
Anhui|Anhui|21392|25197|20600|17300|36000
Shandong|Shantung|38978|43881|36500|29600|38000
Henan|Honan|26218|31087|22100|25600|-
Zhili|Chihli|31587|37328|17900|32571|29400
Hubei|Hupeh|18966|22077|33600|24900|34000
Hunan|Hunan|22512|26320|21000|23600|22000
Shanxi|Shansi|8827|11867|10800|10000|-
Sichuan|Szechuan|36461|45633|71000|23000|78711
Guangdong|Kuangtung|26447|29461|29700|27700|32000
Fujian|Fukien|14167|15471|23500|13100|20000
Guangxi|Kuangsi|12592|14535|5100|6500|8000
Yunnan|Yunnan|11645|13468|11700|8500|8000
Guizhou|Kueichow|10254|12047|7700|11300|-
Shaanxi|Shensi|7075|9545|3300|8800|-
Gansu|Kansu|4955|7161|5400|5000|-
Liaoning|-|4090|10696|-|-|-
Jilin|-|2569|5477|-|-|-
Heilongjiang|-|775|1663|-|-|-
Mongolia|-|3052|3497|-|-|-
Qinghai|-|329|344|-|-|-
Xinjiang|Sinkiang|1392|2169|-|2491|-
Tibet|Tibet|1270|1312|-|6500|-
Qing reconstruction total|-|364389|436042|-|-|-"""
for line in china.splitlines():
    n, orig, a, b, c, d, e = line.split("|")
    total = n.startswith("Qing reconstruction")
    uid = "qing_cao_total" if total else "qing_hist_" + slug(n)
    # Clear the province/benchmark distinction for retrospective regions and categories.
    kind = "benchmark" if total or n in ("Mongolia", "Tibet", "Qinghai") else "admin"
    for dt, value in [("1880", a), ("1910", b)]:
        add(
            uid,
            n,
            None if total else "qing_cao_total",
            kind,
            int(value) * 1000,
            dt,
            cq,
            f"Table 1.1, pp. 17–18, {n if not total else 'Total'}, {dt}",
            "Retrospective regional estimate. Provincial labels can precede formal creation. Cao includes Taiwan in Fujian, includes Inner Mongolia and excludes Outer Mongolia (Federico–Tena, China workbook, Sources note 11).",
            "historical_demographic_reconstruction",
            "Asia",
            quality="rounded_reconstruction",
        )
    for dt, series, v in [
        ("1885", "census_1885", c),
        ("1910", "minchengpu", d),
        ("1910", "maritime_customs", e),
    ]:
        if v == "-":
            continue
        # A shared regional name does not prove identical spatial scope across series.
        u = "qing_yearbook_" + slug(n)
        de = {
            "census_1885": "Yearbook column labelled 1885 census; counting procedure and completeness unspecified.",
            "minchengpu": "Minchengpu household inquiry converted mainly with 5.5 persons per household; capital district and Manchuria have separate arrangements (pp. 1–2).",
            "maritime_customs": "The 1910 Customs estimate as printed, independent of the Minchengpu household estimate.",
        }[series]
        if n == "Sichuan" and series == "minchengpu":
            de += " Only five sevenths returned 16.4 million; published extrapolation 23 million."
        if n == "Sichuan" and series == "maritime_customs":
            de += " The footnote supplies a separate estimate of 45 million for 1904; the yearbook notes high uncertainty."
        if n == "Tibet":
            de = "Separate Chinese estimate added by the yearbook; not a household return."
        add(
            u,
            n,
            None,
            kind,
            int(v) * 1000,
            dt,
            qy,
            f"Chapter I, p. 3, row {orig}, {series} column or supplemental row",
            de,
            series,
            "Asia",
            quality="historical_estimate_uncertain",
        )
for dt, n, v, de in [
    (
        "1885",
        "Eighteen provinces excluding Manchuria",
        377636000,
        "Published total of the 1885 census column; does not represent the whole Qing Empire.",
    ),
    (
        "1910",
        "Minchengpu provincial subtotal",
        331188000,
        "Minchengpu column total above the supplementary categories; includes extrapolated Sichuan.",
    ),
    (
        "1910",
        "Yearbook composite Qing total",
        342639000,
        "Minchengpu subtotal plus Sinkiang, Manchu military organization, dependencies and a Chinese estimate of Tibet; contemporary alternative computations appear on p. 2.",
    ),
    (
        "1910",
        "Customs provincial subtotal",
        428425000,
        "Printed Customs total. The thirteen individual entries, five-province estimate of 55 million and Manchuria's 17 million sum to 438,425,000, exceeding the printed total by 10 million.",
    ),
]:
    add(
        "qing_yearbook_" + slug(n),
        n,
        None,
        "benchmark",
        v,
        dt,
        qy,
        "Chapter I, p. 3, totals of population table",
        de,
        "published_estimate",
        "Asia",
        quality="historical_estimate_uncertain",
    )
for name, value, column, explanation in [
    ("Manchuria", 14917000, "minchengpu", "Shengking, Kirin and Heilungkiang combined. The Fengtien household multiplier differs from the national default."),
    ("Manchuria", 17000000, "maritime_customs", "Shengking, Kirin and Heilungkiang combined."),
    ("Henan, Gansu, Guizhou, Shanxi and Shaanxi", 55000000, "maritime_customs", "Joint estimate for the five dagger-marked provinces; no within-group breakdown."),
    ("Manchu military organization", 1700000, "minchengpu", "Separate administrative category below provincial subtotal."),
    ("Dependencies", 760000, "minchengpu", "Separate administrative category below provincial subtotal. Tibet is tabulated separately."),
]:
    add("qing_yearbook_" + slug(name), name, None, "benchmark", value, "1910", qy,
        f"Chapter I, pp. 2–3, {name}, {column}", explanation, column, "Asia",
        quality="historical_estimate_uncertain")
xu = "xu_leeuwen_zanden_qing_1893"
src(
    xu, "Urbanization in China, ca. 1100–1900", "Yi Xu, Bas van Leeuwen and Jan Luiten van Zanden, Frontiers of Economics in China 13(3), 2018",
    "https://pure.knaw.nl/ws/portalfiles/portal/8633887/Urbanization_in_China_ca._1100_C1900.pdf",
    "Section 2.2 and Table 1, pp. 329–331. The 1893 column draws on Cao Shuji.",
    "Numerical facts with attribution. No full table image or article text redistributed.",
)
for label, tens_of_thousands in {
    "Hebei including Rehe, Beijing, Tianjin and Baoding": 3396, "Shaanxi": 806,
    "Shanxi": 1004, "Shandong": 4100, "Henan": 2823, "Jiangsu including Shanghai": 3100,
    "Zhejiang": 1705, "Fujian excluding Taiwan": 1190, "Jiangxi": 1400, "Huguang (Hunan and Hubei)": 4435,
    "Guangdong": 2771, "Sichuan": 4018, "Anhui": 2297, "Guangxi": 1340, "Guizhou": 1100,
    "Yunnan": 1240, "Gansu": 581, "Inner China": 37306, "Yangtze Delta": 1567,
    "Xinjiang and Qinghai": 218, "Mongolia and northeast": 1847, "Tibet": 114,
    "Taiwan": 282, "China in Qing territory": 39766,
}.items():
    add(
        "qing_xu_1893_" + slug(label), label, None, "benchmark",
        tens_of_thousands * 10000, "1893", xu, f"Table 1, pp. 330–331, {label}, 1893",
        "Historical population reconstruction on the published table geography. Regional subtotals and the Yangtze Delta overlap provincial rows.",
        "historical_demographic_reconstruction", "Asia", quality="rounded_reconstruction",
    )
ft_china = "federico_tena_china_country_workbook_v3"
src(
    ft_china, "Federico-Tena World Population Historical Database: China (V3)",
    "Giovanni Federico and Antonio Tena-Junguito, e-cienciaDatos",
    "https://doi.org/10.21950/K1SRL4",
    "china_1800-1938_FTWPHD_2025_v01.xlsx, China and Sources; country readme, p. 1.",
    "Numeric facts and short original descriptions with attribution.", workbook="https://edatos.consorciomadrono.es/api/access/datafile/33992",
)
for yr, val, loc in [(1880, 2664000, "Cao"), (1905, 3123000, "Ho"), (1910, 3253000, "Cao")]:
    add("taiwan_ft_" + loc.lower(), "Taiwan", None, "benchmark", val, str(yr), ft_china,
        f"Sources, note 12, {loc}, {yr}",
        "Historical Taiwan population benchmark as cited. Exact observation day and offshore-island breakdown unspecified.",
        "published_historical_benchmark", "Asia", quality="rounded_reconstruction")
add("outer_mongolia_ft_1918", "Outer Mongolia", None, "benchmark", 648000, "1918", ft_china,
    "Sources, note 12, first enumeration", "First enumeration as cited in the workbook; territorial scope within Outer Mongolia is unitemized.",
    "reported_enumeration", "Asia", quality="rounded_historical_enumeration")
mongolia = "shagdar_mongolia_nso_population"
src(mongolia, "Mongolia's Pre-1990 Economy: An Extended Overview", "Enkhbayar Shagdar, ERINA Discussion Paper 2002 (2020)",
    "https://www.unii.ac.jp/erina-unp/archive/en/wp-content/uploads/2020/03/DP2002.pdf",
    "Pp. 4–5, Table 2.1.1, compiled from the Mongolian NSO.", "Numerical facts with attribution.")
for yr, value in [(1900, 636700), (1918, 647500)]:
    add("mongolia_nso_historical", "Mongolia", None, "benchmark", value, str(yr), mongolia,
        f"Section 2.1, pp. 4–5, Table 2.1.1, {yr}",
        "Population of Mongolia in the retrospective NSO series. The first historical enumeration is 1918. The paper gives no boundary crosswalk for Uriankhai.",
        "historical_demographic_reconstruction" if yr == 1900 else "reported_enumeration",
        "Asia", quality="historical_benchmark_uncertain_territory")
nz = "nz_official_yearbook_1900"
src(
    nz,
    "New Zealand Official Year-Book, 1900",
    "Registrar-General of New Zealand; Government Printer",
    "https://www3.stats.govt.nz/New_Zealand_Official_Yearbooks/1900/NZOYB_1900.html",
    "Section I: Population; opening table and Estimated Populations of Provincial Districts.",
    "1900 official statistical publication; numeric facts transcribed.",
)
add(
    "nz_colony",
    "New Zealand",
    None,
    "territory",
    796359,
    "1899-12-31",
    nz,
    "Section I, Population, opening table, final row",
    "Government estimate for the colony including Māori. It combines 756,505 updated non-Māori and 39,854 Māori carried forward from the 1896 count.",
    "official_year_end_estimate",
    "Oceania",
    quality="estimate_with_carried_forward_component",
    map="matched_historical_territory",
    wwo="cshapes_gw_920",
)
for n, v in [
    ("Auckland", 165793),
    ("Taranaki", 34486),
    ("Hawke’s Bay", 37139),
    ("Wellington", 132420),
    ("Marlborough", 13499),
    ("Nelson", 38142),
    ("Westland", 15042),
    ("Canterbury", 145058),
    ("Otago", 174664),
    ("Chatham Islands", 255),
    ("Kermadec Islands", 7),
]:
    add(
        "nz_reporting_" + slug(n),
        n,
        "nz_colony",
        "admin",
        v,
        "1899-12-31",
        nz,
        "Section I, Estimated Populations of Provincial Districts, " + n,
        "District estimate excluding Māori. Natural increase was added, but external migration was proportionally distributed and internal migration unmeasured.",
        "official_year_end_estimate",
        "Oceania",
        quality="partial_population_scope",
    )
au = "abs_historical_population_2021"
src(
    au,
    "Historical population, 2021: Population size and growth",
    "Australian Bureau of Statistics, released 16 July 2024",
    "https://www.abs.gov.au/statistics/people/population/historical-population/2021/HPDC1.xlsx",
    "Table 1, persons rows 24–32, dated 31 December; footnotes (a) and (b).",
    "Australian Bureau of Statistics, numeric facts attributed; workbook linked.",
)
for state, code, vals in [
    ("New South Wales", 901, [1317445, 1339214, 1360305, 1375455]),
    ("Victoria", 904, [1182281, 1188541, 1196213, 1209900]),
    ("Queensland", 905, [474861, 486315, 493847, 506721]),
    ("South Australia", 903, [354813, 359298, 362107, 364003]),
    ("Western Australia", 902, [166878, 170258, 179967, 193601]),
    ("Tasmania", 906, [168437, 172362, 172900, 175233]),
    ("Australia", None, [3664715, 3715988, 3765339, 3824913]),
]:
    for y, v in zip(range(1898, 1902), vals):
        add(
            "abs_" + slug(state),
            state,
            None,
            "benchmark" if code is None else "territory",
            v,
            f"{y}-12-31",
            au,
            f"Table 1, Person, {state}, {y}",
            "Persons present, historical ABS series. Full estimates of the Aboriginal and Torres Strait Islander population are included only from 1961. Historical series cannot supply an all-resident total.",
            "official_year_end_estimate",
            "Oceania",
            quality="partial_population_scope",
            map="partial_population_scope",
            wwo=f"cshapes_gw_{code}" if code else None,
        )
jp = "japan_statistical_yearbook_72"
src(
    jp,
    "Japan Statistical Yearbook, 72nd edition",
    "Statistics Bureau, Ministry of Internal Affairs and Communications",
    "https://www.stat.go.jp/data/nenkan/72nenkan/zenbun/jp72/book/book.pdf",
    "Chapter 2, table 2-1, Total Population, pre-census series and footnote.",
    "Statistical facts attributed to the Statistics Bureau; original linked.",
)
for y, v in [(1898, 42886), (1899, 43404), (1900, 43847), (1901, 44359)]:
    add(
        "japan_proper_japanese",
        "Japanese population in Japan proper",
        None,
        "benchmark",
        v * 1000,
        f"{y}-01-01",
        jp,
        f"Table 2-1, total in thousands, {y}",
        "Cabinet Bureau of Statistics January 1 estimate of the Japanese population in Japan proper. Excludes foreign nationals and overseas possessions. Unit is 1,000 people.",
        "official_population_estimate",
        "Asia",
        quality="rounded_partial_population_scope",
        map="partial_population_scope",
        wwo="empire_of_japan",
    )


def facts(
    reg,
    table,
    parent,
    kind,
    dt,
    definition,
    method,
    text,
    quality="historical_census",
    prefix=None,
):
    for l in text.strip().splitlines():
        n, *vs = l.split("|")
        key = (prefix or parent or "imperial") + "_" + slug(n)
        for date, v in zip(dt, vs):
            if v == "-":
                continue
            add(
                key,
                n,
                parent,
                kind,
                int(v),
                date,
                emp,
                table + ", " + n,
                definition,
                method,
                reg,
                quality=quality,
            )


def imperial(
    uid,
    n,
    g,
    a,
    b,
    dt,
    pg,
    de,
    m="published_census_return",
    q="historical_census",
    parent=None,
    kind="territory",
    wwo=None,
):
    for date, val in [("1891", a), (dt, b)]:
        if val is not None:
            add(
                uid,
                n,
                parent,
                kind,
                val,
                date,
                emp,
                pg + ", " + n,
                de,
                m,
                g,
                quality=q,
                map="historical_territory_candidate"
                if wwo
                else "historical_unit_unlinked",
                wwo=wwo,
            )


mar = "1901-03-01"
apr = "1901-04-01"
sa = "1904-04-18"
asi = "Asia"
afr = "Africa"
oc = "Oceania"
ce = "ceylon_colony"
imperial(
    ce,
    "Ceylon",
    asi,
    3012224,
    3578333,
    mar,
    "Ceylon table 2 p. 110; 1901 table 1",
    "Island total including military and shipping. 1901 includes 4,914 prisoners of war. Maldives are separate.",
    wwo="cshapes_gw_780",
)
for y, v in [(1898, 3395519), (1899, 3429745), (1900, 3520574)]:
    add(
        ce,
        "Ceylon",
        None,
        "territory",
        v,
        str(y),
        emp,
        f"Ceylon table 4, p. 111, {y}, Estimated Population",
        "Official middle-of-year island estimate; publication supplies no day. Maldives excluded.",
        "official_midyear_estimate",
        asi,
        quality="historical_admin_estimate",
        map="historical_territory_candidate",
        wwo="cshapes_gw_780",
        reference_period="middle_of_year",
    )
facts(
    asi,
    "Ceylon table 3, p. 111",
    ce,
    "city",
    [mar],
    "Civil population of the named municipality, local board or town, excluding military, shipping and prisoners of war.",
    "published_census_return",
    """Colombo Municipality|154691
Negombo Local Board|19819
Kalutara Local Board|11500
Kandy Municipality|26386
Matale Local Board|4951
Nuwara Eliya Local Board|5026
Jaffna Town|33879
Galle Municipality|37165
Matara Local Board|11848
Hambantota Town|2843
Batticaloa Local Board|9969
Trincomalee Local Board|11295
Kureenegala Local Board|6483
Puttalam Local Board|5115
Chilaw Local Board|4168
Anuradhapura Town|3672
Badulla Local Board|5924
Ratnapura Local Board|4084
Kegalla Local Board|2340""",
)
est = "period_administrative_estimate"
qe = "historical_admin_estimate"
straits = "straits_settlements"
fms = "federated_malay_states"
imperial(
    straits,
    "Straits Settlements",
    asi,
    512905,
    573598,
    mar,
    "Summary table 2 p. 3",
    "Colony including Singapore, Malacca, the Penang settlement, Christmas and Cocos Islands.",
)
facts(
    asi,
    "Straits Settlements, detailed table 1 p. 121",
    straits,
    "admin",
    ["1891", mar],
    "Population in the component settlement or island.",
    "published_census_return",
    """Penang Island|123886|128830
Province Wellesley|108117|115264
Dindings|3615|4113
Malacca|92170|95487
Singapore|184554|228555
Christmas Island|9|704
Cocos Islands|554|645""",
)
imperial(
    fms,
    "Federated Malay States",
    asi,
    418509,
    678595,
    mar,
    "Summary table 2 p. 3",
    "Four-state area. 1891 retrospective grouping predates federation; Pahang enumeration unreliable.",
    q="mixed_or_changing_coverage",
    wwo="cshapes_gw_821",
)
facts(
    asi,
    "Summary table 2 p. 3",
    fms,
    "admin",
    ["1891", mar],
    "Persons reported in the named Malay state.",
    "published_census_return",
    """Perak|214254|329665
Selangor|81592|168789
Negri Sembilan|65219|96028""",
)
imperial(
    "federated_malay_states_pahang",
    "Pahang",
    asi,
    57444,
    84113,
    mar,
    "Summary table 2 p. 3, note j",
    "1891 return is considered unreliable; report suggests actual population exceeded 70,000. 1901 house returns do not distinguish uninhabited houses.",
    q="mixed_or_changing_coverage",
    parent=fms,
    kind="admin",
)
for uid, n, a, b, dt, pg, de, m, q in [
    (
        "johore_state",
        "Johore",
        None,
        200000,
        "1901",
        4,
        "Statesman’s Year-Book estimate. No census.",
        est,
        qe,
    ),
    (
        "north_borneo",
        "State of North Borneo",
        114147,
        104527,
        "1901",
        4,
        "State of North Borneo, as counted in the returns.",
        "published_census_return",
        "historical_census",
    ),
    (
        "brunei_state",
        "Brunei",
        None,
        10000,
        "1901",
        4,
        "Statesman’s Year-Book estimate. No census.",
        est,
        qe,
    ),
    (
        "sarawak_state",
        "Sarawak",
        350000,
        500000,
        "1901",
        4,
        "Period estimates; no census in 1901.",
        est,
        qe,
    ),
    (
        "labuan_colony",
        "Labuan",
        5853,
        8411,
        "1901",
        4,
        "Labuan colony as published.",
        "published_census_return",
        "historical_census",
    ),
    (
        "hong_kong_old_colony",
        "Hong Kong including British Kowloon",
        221441,
        297212,
        "1901-01-21",
        4,
        "Original colony including British Kowloon. New Territory appears in its own row.",
        "published_census_return",
        "historical_census",
    ),
    (
        "hong_kong_new_territory",
        "Hong Kong New Territory",
        None,
        102254,
        "1901-01-21",
        4,
        "New Territory tabulated separately from Hong Kong and British Kowloon.",
        "published_census_return",
        "historical_census",
    ),
    (
        "wei_hai_wei",
        "Wei-Hai-Wei",
        None,
        130792,
        apr,
        4,
        "Population of the leased territory in the imperial return.",
        "published_census_return",
        "historical_census",
    ),
    (
        "maldives",
        "Maldive Archipelago",
        None,
        30000,
        "1901",
        3,
        "Colonial Office estimate reported separately from Ceylon.",
        est,
        qe,
    ),
]:
    imperial(uid, n, asi, a, b, dt, "Summary table 2, p. " + str(pg), de, m, q)
imperial(
    "nz_colony",
    "New Zealand",
    oc,
    670150,
    816214,
    apr,
    "Summary table 2, p. 6 and note f p. 7",
    "New Zealand and listed adjacent islands; includes Māori and naval population. Cook Islands and other dependencies are separate.",
    wwo="cshapes_gw_920",
)
imperial(
    "fiji_rotuma",
    "Fiji Islands and Rotuma",
    oc,
    121180,
    120124,
    apr,
    "Summary table 2, p. 6",
    "1891 published combined total. 1901 sum of two separately published nonoverlapping components (117,866 and 2,258).",
    m="published_total_or_component_sum",
)
for n, v in [("Fiji Islands", 117866), ("Rotuma", 2258)]:
    imperial(
        "fiji_rotuma_" + slug(n),
        n,
        oc,
        None,
        v,
        apr,
        "Summary table 2, p. 6",
        "Component of Fiji and Rotuma.",
        parent="fiji_rotuma",
        kind="admin",
    )
imperial(
    "british_new_guinea",
    "British New Guinea",
    oc,
    300000,
    350000,
    "1901",
    "Summary table 2, p. 6",
    "No census. Colonial Office and Statesman’s Year-Book estimates in the summary.",
    est,
    qe,
)
imperial(
    "cook_group_dependencies",
    "Cook Islands and other dependencies",
    oc,
    None,
    12292,
    "1901",
    "Summary table 2, pp. 6–7, note g",
    "Listed islands only. No census; published grouping postdates the opening.",
    est,
    qe,
)
gc = "gold_coast_including_ashanti_north"
lc = "lagos_colony_protectorate"
sl = "sierra_leone_colony"
sp = "sierra_leone_protectorate"
gam = "gambia_colony_protectorate"
imperial(
    gam,
    "Gambia Colony and Protectorate",
    afr,
    None,
    90404,
    apr,
    "Summary table 2, p. 4",
    "Sum of separately reported colony (13,456) and protectorate (76,948).",
    m="sum_published_nonoverlapping_totals",
)
imperial(
    "gambia_colony",
    "Gambia Colony",
    afr,
    14266,
    13456,
    apr,
    "Summary table 2, p. 4",
    "Colony only, excluding the protectorate.",
    parent=gam,
)
imperial(
    "gambia_protectorate",
    "Gambia Protectorate",
    afr,
    None,
    76948,
    apr,
    "Summary table 2, p. 4",
    "Protectorate reported separately from colony.",
    parent=gam,
)
imperial(
    sl,
    "Sierra Leone Colony",
    afr,
    74835,
    76655,
    "1901",
    "Summary table 2, p. 4; Sierra Leone p. 142",
    "Colony only, historical boundary changed between enumerations.",
    q="mixed_or_changing_coverage",
)
imperial(
    sp,
    "Sierra Leone Protectorate",
    afr,
    None,
    949827,
    "1901",
    "Sierra Leone table 1, p. 142",
    "Administrative estimate of five protectorate districts. No census.",
    est,
    qe,
)
facts(
    afr,
    "Sierra Leone p. 142, protectorate district table",
    sp,
    "admin",
    ["1901"],
    "Administrative district estimate without enumeration.",
    "period_administrative_estimate",
    """Ronietta|400000
Karene|200000
Bandajuma|109584
Panguma|183857
Koinadugu|56386""",
    qe,
)
facts(
    afr,
    "Sierra Leone p. 142, colony district table",
    sl,
    "admin",
    ["1901"],
    "Enumeration of the named district of the colony; protectorate is separate.",
    "published_census_return",
    """Freetown|34463
Kissy|3947
Kissy (Regent)|2051
Wilberforce|5311
Hastings|2339
Mandonkia|6877
Songo|6250
York|2462
Kent|4082
Sherbro|5490
Isles de Los|1422
Tassoh|1079
Kikonkeh|882""",
)
imperial(
    gc,
    "Gold Coast including Ashanti and Northern Territories",
    afr,
    1473559,
    1486433,
    apr,
    "Gold Coast table 1, p. 144",
    "Published adjusted total: counted population plus an estimate of persons omitted. Territories and districts have different coverage in the two returns.",
    m="published_adjusted_census_total",
    q="mixed_or_changing_coverage",
)
for dt, v, cor in [("1891", 768559, 705000), (apr, 1338433, 148000)]:
    add(
        "gold_coast_enumerated",
        "Gold Coast, counted subtotal",
        gc,
        "benchmark",
        v,
        dt,
        emp,
        "Gold Coast table 1 p. 144, total before allowance",
        "Persons counted before published omission allowance. No uniform district allocation of the allowance.",
        "published_census_subtotal",
        afr,
        quality="partial_population_scope",
        published_omission_allowance=cor,
    )
facts(
    afr,
    "Gold Coast table 1, p. 144",
    gc,
    "admin",
    ["1891", apr],
    "Persons returned from the historical district before colony-wide adjustment for omissions. District counts reflect varying coverage.",
    "published_census_return",
    """Accra|91612|143141
Ada|46869|46487
Axim|39870|18130
Cape Coast and Elmina|87873|100282
Dixcove|10702|11725
Kwitta|36230|174224
Prampram|10908|13404
Saltpond|138818|57820
Sekondi|19151|22600
Volta River|128405|163997
Wassaw|73683|80603
Winneba|80064|62937
Ashanti|-|335651
Northern Territories|-|107432""",
    "mixed_or_changing_coverage",
)
facts(
    afr,
    "Gold Coast table 3, p. 145",
    gc,
    "city",
    [apr],
    "Persons in each chief town as returned, distinct from district of the same name.",
    "published_census_return",
    """Accra|14842
Aburi|10393
Ada|1776
Ajira|368
Akropong|9013
Akusi|1442
Anamabu|3296
Apam|4475
Atwabu|3500
Axim|2189
Begoro|3921
Beyin|3500
Cape Coast|28948
Chama|5022
Dixcove|2233
Elmina|3973
Half Asini|3000
Kwitta|3018
Kpong|3435
Prampram|2240
Saltpond|3694
Sekondi|4095
Tarkwa|471
Winneba|5575""",
    prefix="gold_coast_town",
)
imperial(
    lc,
    "Lagos Colony and Protectorate",
    afr,
    None,
    1388847,
    "1901",
    "Lagos table 1, p. 145",
    "Lagos Island, harbour and Ebute Metta counted; other districts estimated. Alternative estimate in note to imperial summary p. 5.",
    m="published_adjusted_census_total",
    q="mixed_or_changing_coverage",
)
imperial(
    "lagos_colony_1891",
    "Lagos Colony as constituted in 1891",
    afr,
    85607,
    None,
    "1901",
    "Lagos p. 145",
    "1891 colony area differs from 1901 colony plus protectorate.",
)
imperial(
    "lagos_island_harbour",
    "Lagos Island and Harbour",
    afr,
    32508,
    39354,
    apr,
    "Lagos table 1 and footnote, p. 145",
    "Island and harbour enumeration.",
    parent=lc,
    kind="city",
)
imperial(
    "ebute_metta",
    "Ebute Metta",
    afr,
    None,
    2493,
    apr,
    "Lagos table 1, p. 145",
    "Separately enumerated mainland town.",
    parent=lc,
    kind="city",
)
facts(
    afr,
    "Lagos table 1, p. 145",
    lc,
    "admin",
    ["1901"],
    "Estimated population of the stated Lagos district or province; no census.",
    "period_administrative_estimate",
    """Western District|60000
Eastern District|132000
Central District|30000
Ikorodu and Shagamu|65000
Province of Ibadan and Oyo|610000
Province of Ode Ondo|150000
Province of Ilesha|300000""",
    qe,
)
add(
    "northern_nigeria",
    "Northern Nigeria",
    None,
    "territory",
    20000000,
    "1901",
    emp,
    "Summary table 2, p. 4; Northern Nigeria p. 146",
    "No census. Period text gives 10 to 20 million; imperial summary prints the upper endpoint.",
    "summary_upper_endpoint_of_published_range",
    afr,
    quality=qe,
    map="historical_territory_candidate",
    wwo="cshapes_gw_4784",
    population_lower=10000000,
    population_upper=20000000,
)
imperial(
    "southern_nigeria",
    "Southern Nigeria",
    afr,
    None,
    5000000,
    "1901",
    "Southern Nigeria p. 146",
    "No census. Statesman’s Year-Book estimate as cited.",
    est,
    qe,
    wwo="cshapes_gw_4783",
)
for uid, n, a, b, de in [
    (
        "cape_colony",
        "Cape of Good Hope",
        1766040,
        2409804,
        "1891 includes an allowance for Pondoland.",
    ),
    ("basutoland", "Basutoland", 218902, 348848, "Basutoland as returned."),
    (
        "natal_zululand",
        "Natal and Zululand",
        689349,
        1108754,
        "Includes territories in the 1904 census area.",
    ),
    (
        "orange_river_colony",
        "Orange River Colony",
        207503,
        387315,
        "1891 Orange Free State. 1904 includes military personnel and households.",
    ),
    (
        "transvaal",
        "Transvaal",
        None,
        1268716,
        "Military personnel and households included in 1904.",
    ),
    ("swaziland", "Swaziland", None, 85484, "1904 preliminary census return."),
    (
        "bechuanaland_protectorate",
        "Bechuanaland Protectorate",
        None,
        120776,
        "1904 census return.",
    ),
    (
        "southern_rhodesia",
        "Southern Rhodesia",
        None,
        605764,
        "Mashonaland and Matabeleland. 1904 return.",
    ),
]:
    imperial(
        uid,
        n,
        afr,
        a,
        b,
        sa,
        "Summary table 2, pp. 4–5, note c; dates p. 71",
        de + " The 1904 figures follow the reports available at compilation.",
        q="historical_census",
        wwo="cshapes_gw_570" if uid == "basutoland" else None,
    )
for uid, n, val, pg, de in [
    (
        "north_eastern_rhodesia",
        "Northern Rhodesia excluding North-Western Rhodesia",
        339068,
        4,
        "No estimate available for the north-western territory.",
    ),
    (
        "british_central_africa",
        "British Central Africa",
        736724,
        4,
        "No census; reported estimate.",
    ),
    ("zanzibar_pemba", "Zanzibar and Pemba", 250000, 4, "Islands only; no census."),
    (
        "east_africa_protectorate",
        "East Africa Protectorate",
        4000000,
        4,
        "No census; estimate for the protectorate as reported.",
    ),
    (
        "uganda_protectorate",
        "Uganda Protectorate",
        1508118,
        5,
        "No census; compiled estimate from trade statistical tables.",
    ),
    (
        "somaliland_protectorate",
        "Somaliland Protectorate",
        153018,
        5,
        "No census; compiled estimate from trade statistical tables.",
    ),
    (
        "socotra",
        "Socotra",
        12000,
        5,
        "No census; Statesman’s Year-Book figure. Assigned to Africa by the original summary.",
    ),
]:
    imperial(
        uid,
        n,
        afr,
        None,
        val,
        "1901",
        f"Summary table 2, p. {pg}; dates p. 71",
        de,
        est,
        qe,
    )
for uid, n, a, b, dt, de in [
    ("ascension", "Ascension Island", 205, 410, apr, "Island return."),
    (
        "st_helena",
        "St. Helena",
        4116,
        5200,
        "1901-04-08",
        "1901 excludes prisoners of war from South Africa; military and shipping are included.",
    ),
    (
        "tristan_da_cunha",
        "Tristan da Cunha",
        None,
        74,
        "1901-11",
        "Island enumeration in November.",
    ),
    (
        "mauritius_dependencies",
        "Mauritius and Dependencies",
        374879,
        378195,
        apr,
        "Includes Rodrigues and other listed dependencies; the area figure covers only Mauritius and Rodrigues.",
    ),
    (
        "seychelles",
        "Seychelles Islands",
        16392,
        19258,
        "1901-05-31",
        "Seychelles Islands reported separately from Mauritius.",
    ),
]:
    imperial(uid, n, afr, a, b, dt, "Summary table 2, p. 5; dates p. 71", de)


ss = {s["id"]: s for s in sources}
ss[qy]["publisher"] = (
    "H. T. Montague Bell and H. G. W. Woodhead; George Routledge & Sons (London), E. P. Dutton & Co. (New York)"
)
ss[cq]["publisher"] = (
    "Ni Yuping, Tsinghua University Press (2023). Table credits Cao Shuji, Population History, vol. 4 pp. 451–452 and vol. 5 pp. 703–704."
)
for r in obs:
    if r["unit_id"] == "straits_settlements_malacca":
        r["locator"] = "Straits Settlements, detailed table 1 p. 121 and table 6 p. 123, Malacca, persons"
    if r["unit_id"] == "sierra_leone_protectorate":
        r["locator"] = "Sierra Leone table 2, p. 142, total"
    if r["unit_id"] == "orange_river_colony" and r["date"] == "1891":
        r["date"] = "1890"
        r["locator"] = "Orange River Colony table 1, p. 169, 1890 census entry"
        r["definition"] = (
            "Orange Free State, all persons returned in the 1890 census, shown under the general 1891 comparison heading in the imperial summary."
        )
    if r["unit_id"] == "basutoland" and r["date"] == sa:
        r.update(
            breakdowns={"sex": {"male": 163873, "female": 184975}},
            breakdown_locator="Basutoland table 1, p. 160",
        )
    if r["unit_id"] == "cape_colony" and r["date"] == sa:
        r.update(
            breakdowns={
                "sex": {"male": 1218940, "female": 1190864},
                "residence": {"urban": 630190, "rural": 1779614},
            },
            breakdown_locator="Cape table 3, p. 147",
        )
    if r["unit_id"] == "nz_colony" and r["date"] == "1899-12-31":
        r.update(breakdowns={"sex": {"male": 420352, "female": 376007}})
    if r["unit_id"] == "ceylon_colony" and r["date"] == mar:
        r.update(
            breakdowns={"sex": {"male": 1908273, "female": 1670060}},
            breakdown_locator="Ceylon table 1, p. 110",
        )
    if r["parent_id"] == "sierra_leone_protectorate" and r["name"] == "Ronietta":
        r.update(name="Ronietta", unit_id="sierra_leone_protectorate_ronietta")
t1 = sheet(1)
indx = dict(
    zip(
        [*range(4, 24), *range(25, 40)],
        [*range(5, 25), 26, 27, 28, 29, 30, 32, 33, 34, 35, 38, 39, 40, 41, 42, 43],
    )
)
for i, j in indx.items():
    n, m, f, total, u, v = t1[i][0], *t1[i][6:]
    row = next(
        (
            r
            for r in obs
            if r["unit_id"] == ids[j]
            and r["date"] == mar
            and r["population_value"] == total
        ),
        None,
    )
    if row is None:
        continue
    br = {}
    if all(isinstance(x, float) for x in (m, f)) and m + f == total:
        br["sex"] = {"male": int(m), "female": int(f)}
    if all(isinstance(x, float) for x in (u, v)) and u + v == total:
        br["residence"] = {"urban": int(u), "rural": int(v)}
    if br:
        row.update(
            breakdowns=br, breakdown_locator=f"Table 1, workbook row {i + 1}, {n}"
        )
for name, m, f in [
    ("Leribe", 37380, 44821),
    ("Berea", 18232, 22178),
    ("Maseru", 32602, 35807),
    ("Mafeteng", 27165, 30287),
    ("Mohaleshoek", 24782, 26468),
    ("Quthing", 14646, 15859),
    ("Quachas Nek", 8945, 9527),
    ("Gaols", 98, 6),
    ("Hospitals", 23, 22),
]:
    k = "benchmark" if name in ("Gaols", "Hospitals") else "admin"
    add(
        "basutoland_" + slug(name),
        name,
        "basutoland",
        k,
        m + f,
        sa,
        emp,
        "Basutoland table 3, p. 161, " + name,
        "Sum of the district’s separately printed male and female columns. Gaols and hospitals are separate institutions without a geographical allocation.",
        "sum_published_sex_counts",
        afr,
        breakdowns={"sex": {"male": m, "female": f}},
    )
facts(
    afr,
    "Cape of Good Hope table 4, p. 147",
    "cape_colony",
    "city",
    ["1891", sa],
    "Persons in the named town at each census, all population groups. Town and its suburbs are separate rows.",
    "published_census_return",
    """Cape Town|51251|77668
Aliwal North|2057|5566
Beaufort West|2791|5478
Cradock|4389|7762
East London|6924|25220
Graaff Reinet|5946|10083
Graham’s Town|10498|13887
Kimberley|28718|34331
King William’s Town|7226|9506
Middelburg|1665|6137
Oudtshoorn|4386|8849
Paarl|7668|11293
Port Elizabeth|23266|32959
Queenstown|4094|9616
Somerset East|2894|5216
Uitenhage|5331|12193
Worcester|5404|7885""",
    prefix="cape_town_series",
)
facts(
    afr,
    "Cape of Good Hope table 4, p. 147",
    "cape_colony",
    "city",
    ["1891", sa],
    "Metropolitan aggregate and component towns. Municipal boundary changes affect comparability (table footnote).",
    "published_census_return",
    """Cape Town with Suburbs|78866|169641
Claremont|6252|14972
Green and Sea Point|2926|8839
Maitland|2035|5071
Mowbray|3098|9589
Rondebosch|3378|6035
Woodstock|4974|28990
Wynberg|4952|18477
Beaconsfield|10478|9378
Simon’s Town|3576|6643""",
    "mixed_or_changing_coverage",
    prefix="cape_town_series",
)
for r in obs:
    if r["unit_id"].startswith("cape_town_series_") and r["name"] in [
        "Cape Town",
        "Claremont",
        "Green and Sea Point",
        "Maitland",
        "Mowbray",
        "Rondebosch",
        "Woodstock",
        "Wynberg",
    ]:
        r["parent_id"] = "cape_town_series_cape_town_with_suburbs"

egybase = "https://www.ier.hit-u.ac.jp/COE/Japanese/discussionpapers/DP97.22/"
egy = "egypt_historical_census_primary_tables"
src(
    egy,
    "Demographic Change in Rural Egypt, 1882–1917: Primary census data",
    "Hirofumi Tanada, Waseda University; Hitotsubashi University Institute of Economic Research. Based on Gouvernement Égyptien (1898), Recensement général de l’Égypte, vols. I–III, and Ministry of Finance (1909), The Census of Egypt taken in 1907.",
    egybase + "97_22.html",
    "Appendices 2-1 and 3-1, Markaz and Madina tables; table 2 for census dates; table 4 for cities outside the markaz series.",
    "Factual values from the historical censuses via attributed research transcription; source HTML and study are linked.",
    files={
        f: egybase + f
        for f in (
            "ap2-1.htm",
            "ap2-1-2.htm",
            "ap3-1.htm",
            "ap3-1-2.htm",
            "table2.htm",
            "table4.htm",
        )
    },
    original_1907_scan="https://sites.dlib.nyu.edu/viewer/books/princeton_aco003741/display",
)
for y, d, dt in [(1897, 2, "1897-06-01"), (1907, 3, "1907-04-29")]:
    for town in [False, True]:
        file = f"ap{d}-1" + ("-2" if town else "") + ".htm"
        lab = "Madina" if town else "Markaz"
        rows = json.loads(
            (raw / file.replace(".htm", ".json")).read_text(encoding="utf-8")
        )
        for province, mark, city, *sexcells in rows:
            first = mark.upper()
            if first == "TOTAL":
                name = province
                uid = "egy_mudiriya_" + slug(province)
                pid = "egy_census_territory"
                kind = "admin"
                cat = "Mudiriya subtotal of the listed markaz."

            else:
                if not mark or (town and not city):
                    continue
                muid = "egy_markaz_" + slug(province) + "_" + slug(mark)
                name = city if town else mark
                uid = (
                    ("egy_madina_" + slug(province) + "_" + slug(city))
                    if town
                    else muid
                )
                pid = muid if town else "egy_mudiriya_" + slug(province)
                kind = "city" if town else "admin"
                cat = (
                    "Town serving as markaz seat."
                    if town
                    else "Markaz, including its seat and villages."
                )

            if any(not re.fullmatch(r"[0-9,]+", cell) for cell in sexcells):
                continue
            m, f, value = [int(cell.replace(",", "")) for cell in sexcells]
            detail = (
                {}
                if m + f != value
                else {"breakdowns": {"sex": {"male": m, "female": f}}}
            )
            if m + f != value:
                detail["source_note"] = (
                    f"Printed sex counts {m} and {f} do not reconcile to published total."
                )
            loc = (
                f"Appendix {d}-1 ({lab}), {file}, {province}, "
                + ("TOTAL" if first == "TOTAL" else f"{mark} / {city}")
                + ", Total Population"
            )
            add(
                uid,
                name,
                pid,
                kind,
                value,
                dt,
                egy,
                loc,
                cat
                + " Historical census return as transcribed; boundary changes across censuses were not harmonized. Urban governorates are outside the markaz tables.",
                "published_census_transcription",
                afr,
                quality="historical_census_transcription",
                **detail,
            )
for dt, vs in [
    ("1897-06-01", [9734405, 319766, 570062, 42095, 6886, 31515, 17173]),
    ("1907-04-29", [11189978, 332246, 654476, 49884, 10373, 29354, 18347]),
]:
    for i, (n, v) in enumerate(
        zip(
            [
                "Egypt",
                "Alexandria",
                "Cairo",
                "Port Said",
                "Ismailia",
                "Damietta",
                "Suez",
            ],
            vs,
        )
    ):
        if n == "Damietta" and dt.startswith("1907"):
            continue  # already a madina in this census
        add(
            "egy_census_territory" if i == 0 else "egy_madina_" + slug(n),
            n,
            None if i == 0 else "egy_census_territory",
            "benchmark" if i == 0 else "city",
            v,
            dt,
            egy,
            f"Table 4, {n if i else 'Total Population'}, {dt[:4]} column",
            "Original report figure as reproduced in the study. National total follows the historical census editions and their territorial treatment."
            if i == 0
            else "Town as defined in the census. Administrative governance could change between returns.",
            "published_census_transcription",
            afr,
            quality="historical_census_transcription",
        )


def opening(fn, uid, v, s, loc, method, **kw):
    (out / (fn + "_opening.json")).write_text(
        json.dumps(
            dict(
                unit_id=uid,
                date="1900-01-01",
                population_value=v,
                source_id=s,
                locator=loc,
                method=method,
                units=[],
                **kw,
            ),
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )


opening(
    "nz",
    "cshapes_gw_920",
    796359,
    nz,
    "Section I, Population, 31 December 1899, total estimated population of colony",
    "Carry the official 1899-12-31 year-end estimate across midnight. Includes 756,505 updated non-Māori residents and 39,854 Māori from the 1896 census.",
    endpoint_dates=["1899-12-31"],
    country_endpoint_values=[796359],
)

gz = "ceylon_gazette_5741_q1_1900"
src(
    gz,
    "Supplement to the Ceylon Government Gazette, no. 5,741: Report on the Vital Statistics of the Colony during the First Quarter of 1900",
    "Ceylon Registrar-General, Government Printer (Colombo); digitized by Noolaham",
    "https://noolaham.net/project/1023/102287/102287.pdf",
    "Section I, p. 1, and Table I, p. 9, first-quarter opening estimate by province and district",
    "Factual values transcribed from a 1900 official publication; the digitized original is linked.",
)
ql = "Section I, p. 1, island population at 31 March and increase during quarter"
de = "Island-wide population estimate including the reported increase from migration of Indian labourers."
dt = "1899-12-31"
add(
    ce,
    "Ceylon",
    None,
    "territory",
    3469224,
    dt,
    gz,
    ql,
    de,
    "quarter_end_minus_reported_increase",
    asi,
    quality="official_population_estimate",
    map="matched_historical_territory",
    wwo="cshapes_gw_780",
    quarter_end_value=3484035,
    quarter_reported_increase=14811,
)
add(
    ce,
    "Ceylon",
    None,
    "territory",
    3484035,
    "1900-03-31",
    gz,
    ql,
    de,
    "official_quarter_end_estimate",
    asi,
    quality="official_population_estimate",
    map="matched_historical_territory",
    wwo="cshapes_gw_780",
)
opening(
    "ceylon",
    "cshapes_gw_780",
    3469224,
    gz,
    ql,
    "Carry the 1899-12-31 close across midnight. Recover the previous quarter end by subtracting the published quarterly increase of 14,811 (9,484 natural increase plus 5,327 net immigrant Indian labourers) from the 31 March estimate of 3,484,035.",
    endpoint_dates=["1900-03-31"],
    country_endpoint_values=[3484035],
    quarter_reported_increase=14811,
)
localseries = "ceylon_natural_increase_series"
ld = "Census of 1891 updated with registered births and deaths. This table omits migration updates and has a different island total from Section I."
ll = "Table I, p. 9, estimated population at the beginning of the quarter"


def cl(uid, n, p, k, v):
    add(
        uid,
        n,
        p,
        k,
        v,
        "1900-01-01",
        gz,
        ll + ", " + n,
        ld,
        "official_natural_increase_series",
        asi,
        quality="migration_not_updated",
    )


cl(localseries, "Ceylon (natural increase series)", ce, "benchmark", 3196686)
provinces = """Western|838316|Colombo:479012,Negombo:154242,Kalutara:205062
Central|490461|Kandy:299547,Matale:76432,Nuwara Eliya:114482
Northern|339838|Jaffna:302552,Mannar:24275,Mullaittivu:13011
Southern|531509|Galle:242580,Matara:195511,Hambantota:93418
Eastern|167078|Batticaloa:141130,Trincomalee:25948
North-Western|319775|Kurunegala:225801,Puttalam:24968,Chilaw:69006
North-Central|74761|Anuradhapura:74761
Uva|166970|Badulla:166970
Sabaragamuwa|267978|Ratnapura:112325,Kegalla:155653"""
for line in provinces.splitlines():
    name, v, ds = line.split("|")
    pid = "ceylon_province_" + slug(name)
    cl(pid, name, localseries, "admin", int(v))
    for district in ds.split(","):
        district, vx = district.split(":")
        cl("ceylon_district_" + slug(district), district, pid, "admin", int(vx))
for r in obs:
    if r["unit_id"] == "egy_madina_daqahliya_damietta":
        r["unit_id"] = "egy_madina_damietta"

from fractions import Fraction
from datetime import date

mu = "mauritius_demographic_digest"
src(
    mu,
    "Digest of Demographic Statistics 2016",
    "Statistics Mauritius, Ministry of Finance and Economic Development",
    "https://statsmauritius.govmu.org/Documents/Statistics/Digests/Demography/Digest_Demo_Yr16.pdf",
    "Table 1.3, Population growth in intercensal periods, rows 6 March 1891 and 1 April 1901. Columns for Mauritius, Rodrigues and two-island total.",
    "Statistical facts transcribed and attributed to Statistics Mauritius.",
    companion_table="https://statsmauritius.govmu.org/Documents/Statistics/Digests/Annual_Digest/Annual_Digest_Statistics_Yr08.pdf",
)
mu_dates = ["1891-03-06", "1901-04-01"]
mu_l = "Table 1.3, p. 22, 1891 and 1901 census rows"
mu_rows = [
    ("mu_main_island", "Mauritius island", 370588, 371023),
    ("mu_rodrigues", "Rodrigues island", 2068, 3162),
]
mu_fraction = Fraction(
    (date(1900, 1, 1) - date.fromisoformat(mu_dates[0])).days,
    (date.fromisoformat(mu_dates[1]) - date.fromisoformat(mu_dates[0])).days,
)
mu_units = []
for uid, name, a, b in mu_rows:
    for dt, v in zip(mu_dates, [a, b]):
        add(
            uid,
            name,
            "mu_two_islands",
            "admin",
            v,
            dt,
            mu,
            mu_l + ", " + name,
            "Persons enumerated on the named island. The two-island series excludes other historical dependencies.",
            "published_census_return",
            afr,
            quality="historical_census",
            map="matched_historical_island",
        )
    mu_units.append(
        dict(
            unit_id=uid,
            name=name,
            endpoint_values=[a, b],
            population_value=round(a + (b - a) * mu_fraction),
            place_ids=[],
            locator=mu_l + ", " + name,
        )
    )
for dt, v in zip(mu_dates, [372656, 374185]):
    add(
        "mu_two_islands",
        "Mauritius and Rodrigues",
        None,
        "territory",
        v,
        dt,
        mu,
        mu_l + ", Republic column",
        "Sum of Mauritius and Rodrigues. The historical colony’s other dependencies and Seychelles are outside these two island observations.",
        "published_census_return",
        afr,
        quality="historical_census",
        map="matched_historical_territory",
        wwo="cshapes_gw_590",
    )
mu_v = sum(x["population_value"] for x in mu_units)
(out / "mauritius_opening.json").write_text(
    json.dumps(
        dict(
            unit_id="cshapes_gw_590",
            date="1900-01-01",
            source_id=mu,
            locator=mu_l,
            endpoint_dates=mu_dates,
            country_endpoint_values=[372656, 374185],
            method=f"Linear interpolation over {mu_fraction.numerator}/{mu_fraction.denominator} elapsed days in the two islands represented by gw_590. Each island rounded to a whole person.",
            population_value=mu_v,
            units=mu_units,
        ),
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
eg_rev = "egypt_world_population_conference_1954"
src(
    eg_rev,
    "Contributions to demography through new census enquiries (E/CONF.13/230)",
    "Hasan M. Husein, World Population Conference, United Nations (1954)",
    "https://digitallibrary.un.org/record/4028612/files/E_CONF.13_230-EN.pdf",
    "Table I, p. 1, census years 1897 and 1907.",
    "Census facts transcribed with attribution; original paper linked.",
)
egy_dt = ["1897-06-01", "1907-04-29"]
for dt, val in zip(egy_dt, [9714525, 11287359]):
    add(
        "egy_revised_census_territory",
        "Egypt, revised census series",
        None,
        "benchmark",
        val,
        dt,
        eg_rev,
        "Table I, p. 1, " + dt[:4],
        "Revised historical country series including the nomad population. The 1907 total includes a separate estimate of 97,381 desert nomads. Formal western-border equivalence is unverified.",
        "revised_census_series",
        afr,
        quality="revised_census_with_nomad_estimate",
        map="census_territory_differs_from_map",
    )
ep_fraction = Fraction(
    (date(1900, 1, 1) - date.fromisoformat(egy_dt[0])).days,
    (date.fromisoformat(egy_dt[1]) - date.fromisoformat(egy_dt[0])).days,
)
add(
    "egy_revised_census_territory",
    "Egypt, revised census series",
    None,
    "benchmark",
    round(9714525 + (11287359 - 9714525) * ep_fraction),
    "1900-01-01",
    eg_rev,
    "Table I, p. 1, 1897 and 1907 returns",
    "Estimate for the published census geography including reported nomads; no correspondence established for the inhabited Kufra oases inside gw_651.",
    "linear_interpolation_between_revised_censuses",
    afr,
    quality="census_geography_only",
    map="census_territory_differs_from_map",
    endpoint_dates=egy_dt,
    endpoint_values=[9714525, 11287359],
    elapsed_days=[ep_fraction.numerator, ep_fraction.denominator],
)
for r in obs:
    if r["unit_id"] == "egy_census_territory" and r["date"] == "1907-04-29":
        r["definition"] += " Excludes the 97,381 separately estimated desert nomads."

(out / "observations.jsonl").write_text(
    "".join(
        json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n"
        for r in sorted(
            obs, key=lambda v: (v["unit_id"], v["date"], v["source_id"], v["method"])
        )
    ),
    encoding="utf-8",
)
(out / "sources.json").write_text(
    json.dumps(sources, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print(len(obs), "observations", len(sources), "sources")
