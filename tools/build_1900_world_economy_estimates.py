#!/usr/bin/env python3
"""Build bounded 1900 world-economy, household-budget and transport data.

The output is a gameplay calibration dataset, not a claim that one unified
historical census exists. Every numeric estimate carries a range, confidence
and method. Modern infrastructure data may only be used as a location check.
"""
from __future__ import annotations

import json
from pathlib import Path

OUT = Path("data/alpha")

# entity|iso|population_m|gdp_pc_2011_intl|urban_bp|rail_km|waterway_km|port_idx|shipping_idx|steel_mt|energy_mtce|ports
BASE = """
united_states_1900|USA|76.3|5000|4000|310000|41000|100|92|10.4|320|New York;Boston;Philadelphia;Baltimore;New Orleans;San Francisco
british_isles_1900|GBR|41.5|4600|6200|35000|5800|100|100|5.0|230|London;Liverpool;Glasgow;Southampton;Belfast
german_empire|DEU|56.4|3300|4300|51000|7500|88|78|6.3|145|Hamburg;Bremen;Kiel;Stettin
russian_empire|RUS|136.0|1200|1300|53000|65000|63|52|2.2|75|Saint Petersburg;Odessa;Riga;Vladivostok;Batumi
qing_empire|CHN|400.0|700|650|500|110000|72|38|0.03|25|Shanghai;Tianjin;Guangzhou;Hankou;Fuzhou
country_fra|FRA|40.7|3400|4100|40000|8500|85|70|1.6|55|Marseille;Le Havre;Bordeaux;Dunkirk;Nantes
austria_hungary|AUT|46.7|2400|2400|37000|9000|56|35|1.1|42|Trieste;Fiume
empire_of_japan|JPN|43.8|1200|1400|6000|26000|75|48|0.1|12|Yokohama;Kobe;Nagasaki;Osaka
kingdom_of_italy|ITA|32.4|1800|2600|16000|4200|72|45|0.12|11|Genoa;Naples;Venice;Palermo
ottoman_empire|TUR|24.0|900|1700|8000|12000|64|30|0.05|5|Constantinople;Smyrna;Salonica;Beirut
kingdom_of_spain|ESP|18.6|1800|3200|13000|5200|68|42|0.2|11|Barcelona;Bilbao;Valencia;Cadiz
dominion_of_canada|CAN|5.4|4000|3700|28000|35000|72|48|0.08|9|Montreal;Halifax;Quebec;Vancouver
cshapes_gw_750|IND|294.0|850|1000|40000|62000|78|40|0.05|14|Calcutta;Bombay;Madras;Karachi;Rangoon
brazil_1900|BRA|17.4|1100|1700|15000|42000|68|38|0.01|3|Rio de Janeiro;Santos;Recife;Salvador
mexican_republic|MEX|13.6|1400|2000|15000|9800|58|25|0.06|6|Veracruz;Tampico;Progreso;Acapulco
kingdom_of_netherlands|NLD|5.1|3800|4900|3000|6100|96|92|0.1|7|Rotterdam;Amsterdam
kingdom_of_belgium|BEL|6.7|3600|5600|4600|1500|90|65|1.0|32|Antwerp;Ostend
sweden_norway_union|SWE|7.4|2800|2500|11000|17000|72|65|0.3|11|Gothenburg;Stockholm;Christiania;Bergen
kingdom_of_portugal|PRT|5.4|1400|2200|2400|1200|58|40|0.02|1.5|Lisbon;Porto
australia_colonies_1900|AUS|3.77|4500|5200|22000|6500|76|55|0.05|7|Sydney;Melbourne;Adelaide;Brisbane;Fremantle
kingdom_of_romania|ROU|5.9|1200|1600|3200|2800|42|18|0.05|3|Constanta;Galati
kingdom_of_greece|GRC|2.5|1600|2600|1000|900|55|55|0.01|0.8|Piraeus;Patras
kingdom_of_serbia|SRB|2.5|1100|1200|600|1600|18|5|0.01|0.6|Belgrade
principality_of_bulgaria|BGR|3.7|1100|1500|1500|2200|38|15|0.01|0.8|Varna;Burgas;Ruse
kingdom_of_denmark|DNK|2.45|3200|3800|2700|900|70|68|0.05|3|Copenhagen;Aarhus
swiss_confederation|CHE|3.3|4000|3900|3500|1200|15|15|0.08|5|Basel
persia_qajar|IRN|10.0|800|900|0|6800|38|12|0|0.4|Bushehr;Bandar Abbas;Anzali
korean_empire|KOR|17.0|850|700|100|7200|38|12|0|0.5|Incheon;Busan;Wonsan
kingdom_of_siam|THA|10.0|900|900|400|12000|42|18|0|0.5|Bangkok
argentina_1900|ARG|4.7|3800|4500|16500|11000|75|58|0.03|3|Buenos Aires;Rosario
chile_1900|CHL|3.1|2400|3300|4500|1800|68|45|0.03|2|Valparaiso;Iquique
south_african_republic|ZAR|1.4|3000|1800|3000|400|18|6|0.02|2|Lourenco Marques (external gateway)
orange_free_state|OFS|0.39|1800|900|1200|250|8|2|0|0.4|Port Elizabeth (external gateway)
ethiopian_empire|ETH|11.0|600|400|0|7200|12|3|0|0.2|Djibouti (external gateway);Massawa (external gateway)
moroccan_sultanate|MAR|5.0|750|1000|100|1200|48|25|0|0.4|Tangier;Casablanca;Mogador
khedivate_of_egypt|EGY|10.0|1100|1900|5000|3500|82|50|0.01|1.5|Alexandria;Port Said;Suez
congo_free_state|CFS|15.0|500|300|400|13000|32|12|0|0.2|Matadi;Boma
republic_of_colombia_1900|COL|4.0|1200|1300|700|9800|46|20|0|0.7|Cartagena;Barranquilla;Buenaventura
venezuela_1900|VEN|2.4|1200|1200|900|7200|45|18|0|0.6|La Guaira;Maracaibo
peru_1900|PER|3.8|1300|1600|1800|4300|48|22|0.01|0.9|Callao;Mollendo
bolivia_1900|BOL|1.7|1100|1000|1000|3600|8|3|0|0.5|Antofagasta (external gateway);Arica (external gateway)
emirate_of_afghanistan|AFG|5.0|650|500|0|3000|5|1|0|0.2|Karachi (external gateway);Peshawar (external gateway)
kingdom_of_nepal|NPL|5.6|600|300|0|5000|4|1|0|0.15|Calcutta (external gateway)
sultanate_of_zanzibar|ZAN|0.2|900|1800|50|50|48|45|0|0.1|Zanzibar
republic_of_liberia|LBR|1.0|600|500|0|2500|20|8|0|0.1|Monrovia
paraguay_1900|PRY|0.64|900|1000|400|3200|8|2|0|0.2|Asuncion
uruguay_1900|URY|0.94|3000|4500|1800|800|62|48|0.01|0.7|Montevideo
cshapes_gw_920|NZL|0.82|4500|4500|3500|1200|65|50|0.01|0.8|Auckland;Wellington;Lyttelton;Dunedin
cuba_occupation_1900|CUB|1.57|1800|2800|2000|400|64|35|0.02|1.0|Havana;Santiago de Cuba
kingdom_of_luxembourg|LUX|0.24|3500|3600|500|120|5|2|0.1|2|Antwerp (external gateway);Rotterdam (external gateway)
""".strip()

RESOURCE = {
    "united_states_1900": (89,100,56,93,73), "british_isles_1900": (100,67,19,7,33),
    "german_empire": (89,96,28,4,37), "russian_empire": (54,75,22,100,90),
    "qing_empire": (46,46,31,7,53), "country_fra": (46,71,16,4,33),
    "austria_hungary": (54,67,16,7,47), "empire_of_japan": (36,25,22,4,53),
    "kingdom_of_belgium": (71,38,13,1,10), "sweden_norway_union": (11,100,44,4,97),
    "mexican_republic": (25,42,47,21,30), "chile_1900": (7,21,88,4,17),
    "south_african_republic": (46,42,100,4,17), "peru_1900": (11,29,53,7,17),
    "bolivia_1900": (7,21,75,4,13), "congo_free_state": (4,17,44,1,73),
}

SOURCES = [
    {"source_id":"maddison_2023","title":"Maddison Project Database 2023","coverage":"population and GDP per capita, 169 countries","license":"CC BY 4.0","role":"population and GDP anchors"},
    {"source_id":"cow_nmc_v7","title":"Correlates of War National Material Capabilities v7","coverage":"1816-2022 population, urban population, steel and energy","role":"urban, steel and energy anchors; quality varies by state-year"},
    {"source_id":"cepii_tradhist","title":"CEPII TRADHIST","coverage":"1827-2014 bilateral trade, tariffs, GDP and exchange rates","license":"Etalab 2.0","role":"trade and corridor calibration"},
    {"source_id":"bls_1901_family_budget","title":"US Commissioner of Labor 1901 family budgets","coverage":"2,567 detailed and 25,440 broader working-family records","role":"working-family expenditure anchor"},
    {"source_id":"wfp_global_ports","title":"WFP Global Ports","coverage":"modern global port points","role":"location cross-check only, never direct 1900 capacity"},
    {"source_id":"world_bank_rail_modern","title":"World Bank/UIC rail route kilometres","coverage":"1995-2021","role":"definition and plausibility check only"},
]

BUDGETS = [
    ("rural_subsistence","农村低收入家庭",[6000,800,900,900,400,150,250,100,150,150,200],4200),
    ("low_income_mixed","城乡低收入家庭",[5200,1200,700,950,450,250,300,150,250,250,300],4800),
    ("urban_working","城市工人家庭",[4250,1500,600,1300,400,300,300,150,300,400,500],6800),
    ("lower_middle","下层中产家庭",[3400,1600,450,1150,550,450,400,350,450,650,550],5200),
    ("industrial_middle","工业化地区中产家庭",[3000,1600,400,1000,600,600,450,450,500,750,650],4800),
    ("affluent_industrial","富裕工业社会家庭",[2200,1500,300,1000,700,800,500,600,700,1000,700],4200),
]
BUDGET_KEYS = ["food","housing","fuel_and_light","clothing","household_goods","transport","health","education","taxes_and_insurance","services_and_luxury","savings"]

SEA = [
    ("Liverpool","New York","british_isles_1900","united_states_1900",7,100),
    ("Le Havre","New York","country_fra","united_states_1900",8,78),
    ("Hamburg","New York","german_empire","united_states_1900",9,82),
    ("Rotterdam","London","kingdom_of_netherlands","british_isles_1900",2,80),
    ("Antwerp","London","kingdom_of_belgium","british_isles_1900",2,76),
    ("Marseille","Alexandria","country_fra","khedivate_of_egypt",5,72),
    ("Trieste","Alexandria","austria_hungary","khedivate_of_egypt",6,55),
    ("Genoa","Alexandria","kingdom_of_italy","khedivate_of_egypt",5,64),
    ("London","Calcutta","british_isles_1900","cshapes_gw_750",24,95),
    ("London","Bombay","british_isles_1900","cshapes_gw_750",20,98),
    ("London","Sydney","british_isles_1900","australia_colonies_1900",35,76),
    ("London","Montreal","british_isles_1900","dominion_of_canada",9,82),
    ("Odessa","Constantinople","russian_empire","ottoman_empire",3,64),
    ("Vladivostok","Yokohama","russian_empire","empire_of_japan",3,48),
    ("Yokohama","Shanghai","empire_of_japan","qing_empire",3,70),
    ("Kobe","Busan","empire_of_japan","korean_empire",2,55),
    ("Bombay","Zanzibar","cshapes_gw_750","sultanate_of_zanzibar",8,46),
    ("Alexandria","Bombay","khedivate_of_egypt","cshapes_gw_750",12,72),
    ("Lisbon","Rio de Janeiro","kingdom_of_portugal","brazil_1900",14,54),
    ("Liverpool","Buenos Aires","british_isles_1900","argentina_1900",17,80),
    ("New York","Havana","united_states_1900","cuba_occupation_1900",4,72),
    ("New York","Veracruz","united_states_1900","mexican_republic",5,62),
    ("San Francisco","Yokohama","united_states_1900","empire_of_japan",16,68),
    ("Valparaiso","San Francisco","chile_1900","united_states_1900",15,42),
    ("Buenos Aires","Montevideo","argentina_1900","uruguay_1900",1,76),
    ("Rio de Janeiro","Buenos Aires","brazil_1900","argentina_1900",5,58),
    ("Callao","Valparaiso","peru_1900","chile_1900",4,48),
    ("Cartagena","New York","republic_of_colombia_1900","united_states_1900",5,40),
    ("La Guaira","New York","venezuela_1900","united_states_1900",5,38),
    ("Shanghai","Guangzhou","qing_empire","qing_empire",2,84),
]

RIVERS = [
    ("mississippi",["united_states_1900"],["St Louis","Memphis","New Orleans"],95,1200),
    ("great_lakes_st_lawrence",["united_states_1900","dominion_of_canada"],["Chicago","Detroit","Buffalo","Montreal"],88,2600),
    ("rhine",["german_empire","kingdom_of_netherlands","swiss_confederation"],["Basel","Mannheim","Cologne","Rotterdam"],92,900),
    ("danube",["german_empire","austria_hungary","kingdom_of_serbia","kingdom_of_romania","principality_of_bulgaria","ottoman_empire"],["Vienna","Budapest","Belgrade","Galati"],72,1700),
    ("volga_caspian",["russian_empire"],["Nizhny Novgorod","Kazan","Samara","Astrakhan"],74,3200),
    ("yangtze",["qing_empire"],["Shanghai","Nanjing","Hankou","Chongqing"],90,2200),
    ("ganges_brahmaputra",["cshapes_gw_750"],["Calcutta","Patna","Benares","Bengal delta"],92,3000),
    ("irrawaddy",["cshapes_gw_750"],["Rangoon","Prome","Mandalay"],74,2600),
    ("nile",["khedivate_of_egypt"],["Cairo","Aswan","Alexandria delta"],78,1400),
    ("parana_plata",["argentina_1900","paraguay_1900","uruguay_1900"],["Asuncion","Rosario","Buenos Aires","Montevideo"],83,1200),
    ("amazon",["brazil_1900","peru_1900"],["Iquitos","Manaus","Belem"],70,1800),
    ("congo",["congo_free_state"],["Stanley Pool","Matadi","Boma"],48,1700),
    ("chao_phraya_mekong",["kingdom_of_siam"],["Bangkok","Ayutthaya","Mekong frontier"],62,2600),
]

RESIDUALS = [
    ("dutch_east_indies",38000000,5500,"kingdom_of_netherlands"),
    ("philippines",7600000,6000,"united_states_1900"),
    ("french_indochina",17000000,5200,"country_fra"),
    ("british_africa_malaya",40000000,3500,"british_isles_1900"),
    ("french_colonial_residual",25000000,3300,"country_fra"),
    ("other_colonial_africa",65000000,2800,""),
    ("central_america_caribbean",10000000,3200,""),
    ("minor_europe_middle_east_pacific",35000000,2500,""),
]


def budget_id(gdp: int) -> str:
    if gdp <= 800: return "rural_subsistence"
    if gdp <= 1300: return "low_income_mixed"
    if gdp <= 2200: return "urban_working"
    if gdp <= 3500: return "lower_middle"
    if gdp < 4300: return "industrial_middle"
    return "affluent_industrial"


def main() -> None:
    countries = []
    for rank, row in enumerate(BASE.splitlines(), 1):
        p = row.split("|")
        eid, iso = p[0], p[1]
        pop, gdp, urban, rail, water, port, ship = float(p[2]), int(p[3]), int(p[4]), int(p[5]), int(p[6]), int(p[7]), int(p[8])
        steel, energy, ports = float(p[9]), float(p[10]), p[11].split(";")
        pop_conf = 5000 if iso in {"ZAR","OFS","CFS","ZAN"} else 7500
        gdp_conf = 6500 if rank <= 31 and iso not in {"RUS","CHN","IND","TUR","IRN","KOR","THA","ETH","MAR","EGY","CFS"} else 4500
        infra_conf = 6500 if rail >= 2000 and eid not in {"qing_empire","ottoman_empire"} else 4000
        resource = RESOURCE.get(eid, (25,30,20,5,30))
        industry = min(100, round(gdp / 5000 * 45 + urban / 10000 * 25 + min(1.0, steel / 10.4) * 30))
        agriculture = min(100, round(pop / 400 * 45 + 34))
        overall = round((pop_conf + gdp_conf + infra_conf + 4500) / 4)
        countries.append({
            "rank":rank,"entity_id":eid,"primary_iso3":iso,
            "population":{"value":round(pop*1_000_000),"lower":round(pop*1_000_000*(.94 if pop_conf>=7000 else .85)),"upper":round(pop*1_000_000*(1.06 if pop_conf>=7000 else 1.15)),"confidence_bp":pop_conf,"method":"historical_series_or_census_anchor_with_border_crosswalk","source_ids":["maddison_2023","cow_nmc_v7","national_census_crosswalk"]},
            "gdp_per_capita_2011_intl_dollars":{"value":gdp,"lower":round(gdp*(.82 if gdp_conf>=6000 else .70)),"upper":round(gdp*(1.18 if gdp_conf>=6000 else 1.30)),"confidence_bp":gdp_conf,"method":"maddison_anchor_or_regional_analogue"},
            "urban_population_share_bp":{"value":urban,"lower":max(0,urban-600),"upper":min(10000,urban+600),"confidence_bp":5000},
            "production":{"agriculture_capacity_index":agriculture,"industrial_capacity_index":industry,"steel_output_tonnes":round(steel*1_000_000),"primary_energy_coal_equivalent_tonnes":round(energy*1_000_000),"mineral_capacity_index":{"coal":resource[0],"iron_ore":resource[1],"copper":resource[2],"petroleum":resource[3],"timber":resource[4]},"confidence_bp":5200 if steel>.05 else 3800,"method":"cow_nmc_where_available_else_scale_model_with_resource_overrides"},
            "infrastructure":{"rail_route_km":rail,"rail_route_km_lower":round(rail*.85),"rail_route_km_upper":round(rail*1.15),"navigable_waterway_km":water,"port_capacity_index":port,"merchant_shipping_index":ship,"major_ports":ports,"confidence_bp":infra_conf,"method":"historical_total_anchor_or_density_model; curated circa-1900 gateways"},
            "household_budget_template_id":budget_id(gdp),"overall_confidence_bp":overall,"formal_simulation_allowed":overall>=4500,
        })
    formal_pop = sum(x["population"]["value"] for x in countries)
    residual = [{"aggregate_id":"residual:"+x[0],"population_estimate":x[1],"confidence_bp":x[2],"controller_entity_id":x[3],"formal_simulation_allowed":False} for x in RESIDUALS]
    world = {
        "config_version":1,"schema_id":"historical_world_economy_1900_estimates_v1","calibration_date":"1900-01-01","scope":"50 gameplay entities plus global residual aggregates",
        "policy":{"estimated_values_allowed":True,"minimum_formal_confidence_bp":4500,"all_estimates_require_bounds":True,"silent_numeric_defaults_forbidden":True,"modern_data_requires_historical_crosswalk":True},
        "source_manifest":SOURCES,
        "methodology":{"population":"historical series/census anchors and circa-1900 border crosswalk","gdp":"Maddison anchors or bounded regional analogues","production":"COW steel/energy anchors or bounded capacity model","infrastructure":"historical totals where available; density model and curated gateways otherwise","households":"1901 working-family anchor plus median interpolation and Engel-law ordering"},
        "coverage_summary":{"formal_entity_count":50,"residual_aggregate_count":len(residual),"formal_entity_population":formal_pop,"residual_population":sum(x["population_estimate"] for x in residual),"estimated_world_population":formal_pop+sum(x["population_estimate"] for x in residual)},
        "countries":countries,"world_residual_aggregates":residual,
    }
    budgets = {"config_version":1,"schema_id":"historical_household_budgets_1900_v1","calibration_year":1900,"observed_anchor":{"source_id":"bls_1901_family_budget","sample_detailed_families":2567,"broader_sample_families":25440,"necessities_share_bp":7980,"food_share_bp":4254},"policy":{"shares_sum_to_bp":10000,"household_level_random_variation_bp":1200},"templates":[{"template_id":i,"label_zh":n,"basis":"observed anchor or bounded median/Engel extrapolation","shares_bp":dict(zip(BUDGET_KEYS,s)),"confidence_bp":c} for i,n,s,c in BUDGETS]}
    domestic = [{"entity_id":c["entity_id"],"rail_route_km":c["infrastructure"]["rail_route_km"],"rail_route_km_lower":c["infrastructure"]["rail_route_km_lower"],"rail_route_km_upper":c["infrastructure"]["rail_route_km_upper"],"navigable_waterway_km":c["infrastructure"]["navigable_waterway_km"],"port_capacity_index":c["infrastructure"]["port_capacity_index"],"merchant_shipping_index":c["infrastructure"]["merchant_shipping_index"],"gateway_ports":c["infrastructure"]["major_ports"],"network_class":"continental_dense" if c["infrastructure"]["rail_route_km"]>=30000 else "national_dense" if c["infrastructure"]["rail_route_km"]>=10000 else "developing_trunk" if c["infrastructure"]["rail_route_km"]>=1000 else "minimal_or_external","confidence_bp":c["infrastructure"]["confidence_bp"]} for c in countries]
    transport = {"config_version":1,"schema_id":"historical_transport_network_1900_estimates_v1","calibration_year":1900,"policy":{"topology_type":"country_and_gateway_graph","not_exact_track_geometry":True,"external_gateways_must_be_labelled":True},"domestic_networks":domestic,"international_maritime_corridors":[{"corridor_id":f"sea:{i+1:03d}","origin_port":a,"destination_port":b,"origin_entity_id":oa,"destination_entity_id":ob,"typical_duration_days":d,"capacity_index":cap,"mode":"steamship","confidence_bp":5200} for i,(a,b,oa,ob,d,cap) in enumerate(SEA)],"major_river_corridors":[{"corridor_id":"river:"+i,"entity_ids":e,"hubs":h,"capacity_index":c,"seasonality_bp":s} for i,e,h,c,s in RIVERS],"generation_note_zh":"国家与枢纽级稀疏运输骨架；不是每条铁轨、河道和港区的精确复原。"}
    OUT.mkdir(parents=True, exist_ok=True)
    for name, document in [("historical_world_economy_1900.json",world),("historical_household_budgets_1900.json",budgets),("historical_transport_network_1900.json",transport)]:
        target = OUT / name
        target.write_text(json.dumps(document,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print(target)

if __name__ == "__main__":
    main()
