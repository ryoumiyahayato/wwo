extends RefCounted
## Historical display reference only. No simulation, output or account mutation.
const PATH := "res://data/presentation/economic_structure_1900.json"
const COLORS := {"agriculture":Color("91a477"),"industry":Color("b27e59"),"services":Color("648fa6"),"mixed":Color("9b80a7"),"unknown":Color("596463")}
const NAMES := {"agriculture":"农业","industry":"工业","services":"服务业","mixed":"混合结构","unknown":"资料缺项"}
const OUTPUT_CHAINS := {
	"food": {"label":"食品链","goods":["wheat","rye","maize","rice","potatoes","pulses","flour","bread","meat","fish","milk","butter","preserved_food","sugar","vegetable_oil"]},
	"textiles": {"label":"纺织链","goods":["raw_cotton","wool","raw_silk","jute","cotton_cloth","wool_cloth","clothing","fine_clothing","silk_goods"]},
	"energy": {"label":"能源链","goods":["coal","coke","crude_petroleum","kerosene","electricity_service"]},
	"freight": {"label":"货运服务","goods":["freight_service"]},
	"structure": {"label":"1900 年产业结构","goods":[]},
}
const OUTPUT_LOW := Color("d2b65d")
const OUTPUT_HIGH := Color("398e65")

static func output_color(value: float, highest: float) -> Color:
	return OUTPUT_LOW.lerp(OUTPUT_HIGH,sqrt(clampf(value/maxf(highest,1.0),0.0,1.0)))
static var _loaded: bool=false
static var _rows: Dictionary={}

static func sector_shares(source_id: String) -> Dictionary:
	if not _loaded:
		_loaded=true
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		if parsed is Dictionary and parsed.get("schema_id")=="economic_structure_reference_v1":
			for id: String in parsed.get("rows",{}):
				var row: Dictionary=parsed.rows[id]
				var total: int=0
				var valid: bool=true
				for key: String in ["agriculture","industry","services"]:
					var value: Variant=row.get(key)
					if not (value is int or value is float) or float(value)<0 or float(value)>10000 or float(value)!=floor(float(value)): valid=false;break
					total+=int(value)
				if valid and total==10000: _rows[id]=row
	return _rows.get(source_id,{})

static func category(source_id: String) -> String:
	var row := sector_shares(source_id)
	if row.is_empty(): return "unknown"
	var keys: Array[String]=["agriculture","industry","services"]
	keys.sort_custom(func(a: String,b: String)->bool:return int(row[a])>int(row[b]))
	# A gap under five percentage points does not imply a single leading sector.
	return "mixed" if int(row[keys[0]])-int(row[keys[1]])<500 else keys[0]

static func color(source_id: String) -> Color:
	return COLORS[category(source_id)]

static func summary(source_id: String) -> String:
	var row := sector_shares(source_id)
	if row.is_empty():return "该地区暂无同口径资料"
	return "农业 %.1f%% · 工业 %.1f%% · 服务 %.1f%%"%[float(row.agriculture)/100.0,float(row.industry)/100.0,float(row.services)/100.0]
