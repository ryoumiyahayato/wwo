#!/usr/bin/env python3
"""Build the 1900 political-unit registry from the CShapes snapshot.

Every active CShapes unit remains independently selectable. Relationships to a
controlling state are metadata, never a reason to merge modern polygons or to
invent a common imperial flag.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

SNAPSHOT_PATH = Path("data/world_map/historical/cshapes_1900_snapshot.json")
OUTPUT_PATH = Path("data/world_map/historical/political_units_1900.json")
TARGET_DATE = "1900-03-12"

CORE_IDS: dict[int, str] = {
    2: "united_states_1900", 20: "dominion_of_canada", 21: "colony_of_newfoundland",
    40: "cuba_occupation_1900", 41: "haiti_1900", 42: "dominican_republic_1900",
    70: "mexican_republic", 90: "guatemala_1900", 91: "honduras_1900",
    92: "el_salvador_1900", 93: "nicaragua_1900", 94: "costa_rica_1900",
    100: "republic_of_colombia_1900", 101: "venezuela_1900", 130: "ecuador_1900",
    135: "peru_1900", 140: "brazil_1900", 145: "bolivia_1900",
    150: "paraguay_1900", 155: "chile_1900", 160: "argentina_1900",
    165: "uruguay_1900", 200: "british_isles_1900", 210: "kingdom_of_netherlands",
    211: "kingdom_of_belgium", 212: "grand_duchy_of_luxembourg", 220: "country_fra",
    225: "swiss_confederation", 230: "kingdom_of_spain", 235: "kingdom_of_portugal",
    255: "german_empire", 300: "austria_hungary", 325: "kingdom_of_italy",
    340: "kingdom_of_serbia", 341: "principality_of_montenegro",
    350: "kingdom_of_greece", 355: "principality_of_bulgaria",
    360: "kingdom_of_romania", 365: "russian_empire", 380: "sweden_norway_union",
    390: "kingdom_of_denmark", 395: "iceland_under_denmark", 450: "republic_of_liberia",
    490: "congo_free_state", 511: "sultanate_of_zanzibar", 530: "ethiopian_empire",
    563: "south_african_republic", 564: "orange_free_state", 600: "moroccan_sultanate",
    616: "beylicate_of_tunis", 630: "persia_qajar", 640: "ottoman_empire",
    651: "khedivate_of_egypt", 696: "trucial_states", 698: "sultanate_of_muscat_oman",
    700: "emirate_of_afghanistan", 710: "qing_empire", 713: "taiwan_under_japan",
    730: "korean_empire", 740: "empire_of_japan", 760: "kingdom_of_bhutan",
    790: "kingdom_of_nepal", 800: "kingdom_of_siam", 835: "sultanate_of_brunei",
    7020: "emirate_of_bukhara", 7030: "khanate_of_khiva",
}

DISPLAY_NAME_ZH: dict[int, str] = {
    2:"美利坚合众国",3:"阿拉斯加领地",4:"夏威夷领地",6:"波多黎各",
    20:"加拿大自治领",21:"纽芬兰殖民地",31:"巴哈马",40:"古巴军事占领区",
    41:"海地共和国",42:"多米尼加共和国",51:"牙买加",52:"特立尼达和多巴哥",
    53:"巴巴多斯",65:"瓜德罗普",66:"马提尼克",70:"墨西哥合众国",80:"英属洪都拉斯",
    90:"危地马拉共和国",91:"洪都拉斯共和国",92:"萨尔瓦多共和国",93:"尼加拉瓜共和国",
    94:"哥斯达黎加共和国",100:"哥伦比亚共和国",101:"委内瑞拉合众国",110:"英属圭亚那",
    115:"荷属圭亚那",120:"法属圭亚那",130:"厄瓜多尔共和国",135:"秘鲁共和国",
    140:"巴西合众国",145:"玻利维亚共和国",150:"巴拉圭共和国",155:"智利共和国",
    160:"阿根廷共和国",165:"乌拉圭东岸共和国",200:"大不列颠及爱尔兰联合王国",
    210:"尼德兰王国",211:"比利时王国",212:"卢森堡大公国",220:"法兰西第三共和国",
    225:"瑞士联邦",230:"西班牙王国",235:"葡萄牙王国",255:"德意志帝国",
    300:"奥匈帝国",325:"意大利王国",338:"马耳他殖民地",340:"塞尔维亚王国",
    341:"黑山公国",350:"希腊王国",355:"保加利亚公国",360:"罗马尼亚王国",
    365:"俄罗斯帝国",380:"瑞典—挪威联合王国",390:"丹麦王国",395:"冰岛",
    402:"佛得角",404:"葡属几内亚",411:"西属几内亚",420:"冈比亚殖民地",
    430:"法属西非内陆领地",433:"塞内加尔",434:"达荷美",437:"象牙海岸",
    438:"法属几内亚",450:"利比里亚共和国",451:"塞拉利昂殖民地",452:"黄金海岸殖民地",
    460:"德属多哥兰",470:"德属喀麦隆",481:"加蓬",484:"法属刚果",
    490:"刚果自由邦",500:"乌干达保护国",501:"东非保护国",510:"德属东非",
    511:"桑给巴尔苏丹国",521:"英属索马里兰",522:"法属索马里海岸",530:"埃塞俄比亚帝国",
    531:"厄立特里亚殖民地",540:"葡属安哥拉",541:"葡属莫桑比克",552:"南罗得西亚",
    553:"尼亚萨兰",561:"开普殖民地",562:"纳塔尔殖民地",563:"南非共和国",
    564:"奥兰治自由邦",565:"德属西南非洲",570:"巴苏陀兰",571:"贝专纳兰",
    572:"斯威士兰",580:"法属马达加斯加",585:"留尼汪",590:"毛里求斯殖民地",
    600:"摩洛哥苏丹国",610:"西属西非",615:"法属阿尔及利亚",616:"突尼斯贝伊国",
    625:"英埃苏丹",630:"卡扎尔波斯",640:"奥斯曼帝国",651:"埃及赫迪夫国",
    696:"特鲁西尔诸酋长国",698:"马斯喀特和阿曼苏丹国",700:"阿富汗酋长国",
    710:"大清帝国",713:"日治台湾",730:"大韩帝国",740:"大日本帝国",
    750:"英属印度",760:"不丹王国",780:"英属锡兰",781:"马尔代夫苏丹国",
    790:"尼泊尔王国",800:"暹罗王国",811:"柬埔寨保护国",812:"老挝保护国",
    815:"法属印度支那越南诸保护地",821:"马来联邦",822:"马来属邦",823:"北婆罗洲",
    824:"砂拉越王国",827:"海峡殖民地",835:"文莱苏丹国",840:"菲律宾群岛",
    850:"荷属东印度",860:"葡属帝汶",901:"新南威尔士殖民地",902:"西澳大利亚殖民地",
    903:"南澳大利亚殖民地",904:"维多利亚殖民地",905:"昆士兰殖民地",906:"塔斯马尼亚殖民地",
    911:"英属新几内亚",912:"德属新几内亚",920:"新西兰殖民地",930:"法属新喀里多尼亚",
    940:"英属所罗门群岛",950:"斐济殖民地",3461:"波斯尼亚占领区",3462:"黑塞哥维那占领区",
    4781:"拉各斯殖民地",4783:"南尼日利亚保护国",4784:"北尼日利亚保护国",
    5200:"意属索马里兰",5518:"东北罗得西亚",5519:"西北罗得西亚",
    7020:"布哈拉酋长国",7030:"希瓦汗国",
}

CONTROLLER_GROUPS: dict[str, list[int]] = {
    "united_states_1900": [3,4,6,40,840],
    "british_isles_1900": [20,21,31,51,52,53,80,110,338,420,451,452,500,501,521,552,553,561,562,570,571,572,590,625,651,696,750,780,781,821,822,823,824,827,835,901,902,903,904,905,906,911,920,940,950,4781,4783,4784,5518,5519],
    "country_fra": [65,66,120,430,433,434,437,438,481,484,522,580,585,615,616,811,812,815,930],
    "kingdom_of_netherlands": [115,850],
    "kingdom_of_spain": [411,610],
    "kingdom_of_portugal": [402,404,540,541,860],
    "german_empire": [460,470,510,565,912],
    "kingdom_of_italy": [531,5200],
    "austria_hungary": [3461,3462],
    "russian_empire": [7020,7030],
    "empire_of_japan": [713],
}

LOCAL_FLAG_BY_GWCODE: dict[int, str] = {
    2:"us_1896_45_star",20:"canada_red_ensign_1892",21:"newfoundland_red_ensign_1900",
    41:"haiti_1859",42:"dominican_1865",70:"mexico_1893",90:"guatemala_1871",
    91:"honduras_1898",92:"el_salvador_1875",93:"nicaragua_1896",94:"costa_rica_1848",
    100:"colombia_1861",101:"venezuela_1863",130:"ecuador_1860",135:"peru_1884",
    140:"brazil_1889",145:"bolivia_1851",150:"paraguay_1842",155:"chile_1817",
    160:"argentina_1861",165:"uruguay_1830",200:"uk_union_1801",210:"netherlands_tricolour",
    211:"belgium_1831",212:"luxembourg_1845",220:"france_tricolour_1794",
    225:"switzerland_1889",230:"spain_1875",235:"portugal_1830",255:"german_empire_1867",
    300:"austria_hungary_civil_1869",325:"italy_1861",340:"serbia_1882",
    341:"montenegro_1876",350:"greece_1822",355:"bulgaria_1878",360:"romania_1867",
    365:"russia_1896",380:"sweden_norway_union_1844",390:"denmark_dannebrog",
    450:"liberia_1847",490:"congo_free_state_1885",511:"zanzibar_1896",530:"ethiopia_1897",
    563:"transvaal_vierkleur_1857",564:"orange_free_state_1857",600:"morocco_plain_red",
    616:"tunisia_1831",630:"qajar_persia_lion_sun",640:"ottoman_1844",651:"egypt_1882",
    698:"muscat_oman_plain_red",700:"afghanistan_1880",710:"qing_1889",730:"korea_taegeuk_1897",
    740:"japan_1870",790:"nepal_historical_pennants",800:"siam_white_elephant_1855",
    835:"brunei_yellow_pre1906",7020:"bukhara_1868",7030:"khiva_historical",
}

NO_SINGLE_STANDARD: dict[int, str] = {
    40:"美国军事占领与古巴独立运动并存，不以单一国旗代表主权状态。",
    572:"地方君主旗与外部控制关系并存，尚无足够证据指定单一标准国旗。",
    625:"英埃共管体制，不以英国或埃及单方旗帜冒充统一国旗。",
    696:"多个酋长国组成，1900年不存在统一的特鲁西尔国家旗。",
    760:"现有国旗形成于20世纪中叶，不向1900年倒推。",
    781:"地方苏丹旗资料尚未达到可复原标准。",
}


def controller_map() -> dict[int, str]:
    result: dict[int, str] = {}
    for controller_id, codes in CONTROLLER_GROUPS.items():
        for code in codes:
            if code in result:
                raise ValueError(f"duplicate controller mapping for {code}")
            result[code] = controller_id
    return result


def entity_id_for(code: int) -> str:
    return CORE_IDS.get(code, f"cshapes_gw_{code}")


def label_rank(area: float, status: str) -> int:
    if status == "sovereign" and area >= 2_000_000: return 1
    if area >= 500_000: return 2
    if area >= 100_000: return 3
    if area >= 20_000: return 4
    return 5


def main() -> int:
    snapshot = json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))
    if snapshot.get("snapshot_date") != TARGET_DATE:
        raise ValueError("unexpected CShapes snapshot date")
    controllers = controller_map()
    units: list[dict[str, Any]] = []
    for feature in snapshot.get("features", []):
        code = int(feature["gwcode"])
        controller_id = controllers.get(code, "")
        status = "sovereign"
        relation = "independent_state"
        if controller_id:
            status = "dependency"
            relation = "controlled_territory"
        if code == 20: status, relation = "dominion", "self_governing_dominion"
        if code == 21: status, relation = "colony", "crown_colony"
        if code == 40: status, relation = "occupied", "military_occupation"
        if code in (563,564): status, relation = "contested", "belligerent_state"
        if code in (616,521,522,500,501,570,571,696,811,812): status, relation = "protectorate", "protected_territory"
        if code == 625: status, relation = "condominium", "dual_control"
        if code in (3461,3462): status, relation = "occupied", "administered_territory"
        if code in (7020,7030): status, relation = "protectorate", "protected_state"
        flag_id = LOCAL_FLAG_BY_GWCODE.get(code, "")
        flag_mode = "local_historical_flag"
        if code in NO_SINGLE_STANDARD:
            flag_id = "no_single_standard_flag"
            flag_mode = "documented_absence"
        elif not flag_id and controller_id:
            controller_code = next((item for item, eid in CORE_IDS.items() if eid == controller_id), None)
            flag_id = LOCAL_FLAG_BY_GWCODE.get(controller_code or -1, "no_single_standard_flag")
            flag_mode = "controller_identification_flag"
        elif not flag_id:
            flag_id = "research_required"
            flag_mode = "not_rendered"
        units.append({
            "id": entity_id_for(code), "gwcode": code, "source_name": feature["source_name"],
            "name_zh": DISPLAY_NAME_ZH.get(code, feature["source_name"]),
            "short_name_zh": DISPLAY_NAME_ZH.get(code, feature["source_name"]),
            "valid_from": feature["valid_from"], "valid_to": feature["valid_to"],
            "status": status, "relationship": relation, "controller_id": controller_id,
            "flag_id": flag_id, "flag_mode": flag_mode,
            "flag_absence_reason": NO_SINGLE_STANDARD.get(code, ""),
            "label_rank": label_rank(float(feature.get("area_km2", 0.0)), status),
            "capital": feature.get("capital", {}), "area_km2": feature.get("area_km2", 0.0),
            "geometry_feature_id": feature["id"], "geometry_provider": "cshapes_2_0",
            "data_quality": "dated_historical_gis",
        })
    if len(units) != 151 or len({unit["gwcode"] for unit in units}) != 151:
        raise ValueError("political unit registry must cover exactly 151 CShapes units")
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    document = {
        "schema_version": 1, "snapshot_date": TARGET_DATE, "geometry_provider": "cshapes_2_0",
        "unit_count": len(units),
        "policy": {"modern_geometry_fallback_allowed": False,
                   "controller_flag_is_not_local_national_flag": True,
                   "unknown_or_composite_flags_render_neutral": True},
        "units": sorted(units, key=lambda unit: unit["gwcode"]),
    }
    OUTPUT_PATH.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT_PATH), "unit_count": len(units)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
