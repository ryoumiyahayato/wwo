extends RefCounted
## Product identities for new French openings. No source, price or endowment.

enum Field { NAME, GROUP, UNIT, BULK }
const STAPLES := "谷物、薯类与干豆"
const INDUSTRIAL := "工业制品"
const RAW := "其他初级产品"
const UNITS := {
	"kg": ["development_kg", "千克"],
	"m": ["development_m", "米"],
	"m2": ["development_m2", "平方米"],
	"piece": ["development_piece", "件"],
}
const PRODUCTS := {
	"wheat": ["小麦", STAPLES, "kg", true],
	"rye": ["黑麦", STAPLES, "kg", true],
	"meslin": ["小麦黑麦混合粮", STAPLES, "kg", false],
	"barley": ["大麦", STAPLES, "kg", true],
	"oats": ["燕麦", STAPLES, "kg", true],
	"buckwheat": ["荞麦", STAPLES, "kg", false],
	"maize": ["玉米", STAPLES, "kg", true],
	"millet": ["小米", STAPLES, "kg", false],
	"rice": ["稻米", STAPLES, "kg", true],
	"potatoes": ["马铃薯", STAPLES, "kg", false],
	"dry_beans": ["干菜豆", STAPLES, "kg", false],
	"dry_peas": ["干豌豆", STAPLES, "kg", false],
	"lentils": ["扁豆", STAPLES, "kg", false],
	"broad_beans": ["干蚕豆", STAPLES, "kg", false],
	"chestnuts": ["栗子", STAPLES, "kg", false],
	"flour": ["面粉", INDUSTRIAL, "kg", true],
	"potato_starch": ["马铃薯淀粉", INDUSTRIAL, "kg", false],
	"refined_sugar": ["精制糖", INDUSTRIAL, "kg", true],
	"vegetable_oil": ["食用植物油", INDUSTRIAL, "kg", true],
	"butter": ["黄油", INDUSTRIAL, "kg", false],
	"cheese": ["奶酪", INDUSTRIAL, "kg", false],
	"canned_food": ["罐藏食品", INDUSTRIAL, "kg", false],
	"cotton_yarn": ["棉纱", INDUSTRIAL, "kg", true],
	"cotton_cloth": ["棉布", INDUSTRIAL, "m", true],
	"wool_cloth": ["毛呢", INDUSTRIAL, "m", true],
	"clothes": ["衣服", INDUSTRIAL, "piece", false],
	"leather": ["熟皮革", INDUSTRIAL, "kg", false],
	"soap": ["肥皂", INDUSTRIAL, "kg", false],
	"paper": ["纸张", INDUSTRIAL, "kg", true],
	"kerosene": ["照明煤油", INDUSTRIAL, "kg", true],
	"coke": ["焦炭", INDUSTRIAL, "kg", true],
	"pig_iron": ["生铁", INDUSTRIAL, "kg", true],
	"steel": ["钢材", INDUSTRIAL, "kg", true],
	"tools": ["工具", INDUSTRIAL, "piece", false],
	"cement": ["水泥", INDUSTRIAL, "kg", false],
	"flat_glass": ["平板玻璃", INDUSTRIAL, "m2", false],
	"sawn_timber": ["锯材", INDUSTRIAL, "kg", true],
	"rail": ["钢轨", INDUSTRIAL, "kg", true],
	"machine": ["机器", INDUSTRIAL, "piece", false],
	"raw_cotton": ["原棉", RAW, "kg", true],
	"raw_wool": ["原毛", RAW, "kg", true],
	"raw_hides": ["生皮", RAW, "kg", true],
	"coal": ["煤炭", RAW, "kg", true],
	"iron_ore": ["铁矿石", RAW, "kg", true],
	"limestone": ["石灰石", RAW, "kg", false],
	"sugar_beet": ["甜菜", RAW, "kg", false],
	"oilseed": ["油料作物", RAW, "kg", false],
}

static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in PRODUCTS:
		var unit: Array = UNITS[PRODUCTS[id][Field.UNIT]]
		result.append({"id": id, "needs": {}, "unit_id": unit[0], "unit_name_zh": unit[1]})
	return result

static func display_name(id: String, fallback: String) -> String:
	return PRODUCTS[id][Field.NAME] if PRODUCTS.has(id) else fallback

static func group(id: String) -> String:
	return PRODUCTS[id][Field.GROUP] if PRODUCTS.has(id) else ""

static func is_bulk(id: String) -> bool:
	return PRODUCTS.has(id) and PRODUCTS[id][Field.BULK]
