extends RefCounted
## Presentation only. Source identities, evidence and world snapshots stay unchanged.
const MESSAGES_PATH := "res://data/presentation/localization/messages_en.json"
const NAMES_PATH := "res://data/presentation/localization/names.json"
static var _loaded: bool = false
static var _messages: Dictionary = {}
static var _names: Dictionary = {}
static var _fragments: Array[String] = []
static var _cache: Dictionary = {}
static var _aliases: Dictionary = {}

static func _load() -> void:
	if _loaded: return
	var messages: Variant=JSON.parse_string(FileAccess.get_file_as_string(MESSAGES_PATH))
	var names: Variant=JSON.parse_string(FileAccess.get_file_as_string(NAMES_PATH))
	if not messages is Dictionary or not names is Dictionary:
		push_error("Invalid UI localization resources")
		return
	_messages=messages
	_names=names
	for entry: Dictionary in _names.values():
		for field: String in ["name","capital"]:
			var zh := str(entry.get("zh",{}).get(field,""))
			var en := str(entry.get("en",{}).get(field,""))
			if not zh.is_empty() and not en.is_empty(): _messages[zh]=en
			if not zh.is_empty() and not en.is_empty(): _aliases[en]={"zh":zh,"en":en}
	var english := Translation.new()
	english.locale="en"
	var chinese := Translation.new()
	chinese.locale="zh_CN"
	for key: String in _messages:
		english.add_message(key,str(_messages[key]))
		chinese.add_message(key,key)
		if not key.is_empty() and not key.contains("%") and key.strip_edges().length()>=2: _fragments.append(key)
	_fragments.sort_custom(func(a: String,b: String)->bool:return a.length()>b.length())
	TranslationServer.add_translation(english)
	TranslationServer.add_translation(chinese)
	_loaded=true

static func apply(locale: String) -> void:
	_load()
	var target := "en" if locale.begins_with("en") else "zh_CN"
	if TranslationServer.get_locale()!=target:
		_cache.clear()
		TranslationServer.set_locale(target)

static func english() -> bool:
	return TranslationServer.get_locale().begins_with("en")

static func text(value: String) -> String:
	_load()
	if not english() or value.is_empty(): return value
	if _messages.has(value): return str(_messages[value])
	var han := false
	for index: int in value.length():
		if value.unicode_at(index)>=0x3400 and value.unicode_at(index)<=0x9fff:
			han=true
			break
	if not han: return value
	if OS.get_thread_caller_id()!=OS.get_main_thread_id(): return str(TranslationServer.translate(value))
	if _cache.has(value): return str(_cache[value])
	# Composed labels still use the same catalog, never an online translator.
	var result := value
	for fragment: String in _fragments:
		if result.contains(fragment): result=result.replace(fragment,str(_messages[fragment]))
	result=result.replace("：",": ").replace("；","; ").replace("，",", ").replace("、",", ").replace("。",".").replace("（"," (").replace("）",")").replace("／"," / ")
	if _cache.size()>=512: _cache.clear()
	_cache[value]=result
	return result

static func name(row: Dictionary, field: String = "name") -> String:
	_load()
	var locale := "en" if english() else "zh"
	var entry := _names.get(str(row.get("id",row.get("place_id",""))),{}) as Dictionary
	var localized := str(entry.get(locale,{}).get("capital" if field=="capital_name" else "name",""))
	if not localized.is_empty(): return localized
	var value := str(row.get(field+"_"+locale,row.get(field+"_zh",row.get(field,""))))
	if english():
		var known := text(value)
		if known!=value: return known.split(" · ")[0]
		return str(row.get(field+"_en",row.get("historical_name",value))) if field=="name" else known
	if _aliases.has(value): return str(_aliases[value].get("zh",value))
	for part: String in value.split(" · "):
		for character: int in part.length():
			var code := part.unicode_at(character)
			if code>=0x3400 and code<=0x9fff: return part
	# A missing translation is not a fabricated historical name.
	return "名称待译" if not value.is_empty() else "名称未记录"

static func map_name_available(row: Dictionary) -> bool:
	var value := name(row.merged({"name":row.get("display_name",row.get("name",row.get("historical_name","")))},true)).strip_edges()
	return not value.is_empty() and value not in ["名称待译","名称未记录","名称未收录","未知","Name pending translation","Name not recorded","Unknown"]

static func field(row: Dictionary, key: String, fallback: String = "") -> String:
	var locale := "en" if english() else "zh"
	var value := str(row.get(key+"_"+locale,row.get(key+"_zh",row.get(key,fallback))))
	if not english() and key=="unit_type_name":
		for part: String in value.split(" · "):
			for index: int in part.length():
				if part.unicode_at(index)>=0x3400 and part.unicode_at(index)<=0x9fff: return part
	return text(value)
