class_name WorldDataPerformanceBaseline
extends SceneTree
## Standalone, read-only world/map data benchmark.
##
## This tool deliberately measures existing loaders and map services without
## changing their runtime behavior. Synthetic records are created in memory
## only and are never written to the repository as world data.

const BENCHMARK_ID: String = "wwo_world_data_performance_baseline_batch_1"
const SCHEMA_VERSION: int = 1
const ITERATIONS: int = 7
const MAP_ITERATIONS: int = 5
const LOOKUP_ITERATIONS: int = 1000
const SYNTHETIC_ITERATIONS: int = 5
const SYNTHETIC_BASE_RECORDS: int = 1000
const SYNTHETIC_LOOKUPS: int = 1000
const BENCHMARK_SEMANTICS: String = "Timing values are machine-specific observational baselines; they are not universal CI pass/fail thresholds."
const SOURCE_BASELINE_MASTER: String = "83e4f305b52529625f4d86ad928bce451ea34b9f"

const RUNTIME_LOADER_FILES: Dictionary = {
	"world_coastlines": "res://data/world_map/world_coastlines.json",
	"countries": "res://data/world_map/countries.json",
	"regions": "res://data/world_map/regions.json",
	"cities": "res://data/world_map/cities.json",
	"ports": "res://data/world_map/ports.json",
	"rail_segments": "res://data/world_map/rail_segments.json",
	"road_segments": "res://data/world_map/road_segments.json",
	"shipping_routes": "res://data/world_map/shipping_routes.json",
	"characters": "res://data/world_map/characters.json",
	"name_pool_fr": "res://data/world_map/name_pool_fr.json",
	"relationships": "res://data/world_map/relationships.json",
	"organizations": "res://data/world_map/organizations.json",
	"institutions": "res://data/world_map/institutions.json",
	"activity": "res://data/world_map/world_activity.json",
	"map_modes": "res://data/world_map/map_modes.json",
	"map_geometry_cache": "res://data/world_map/map_geometry_cache.json",
}

const RUNTIME_SUPPORTING_FILES: Dictionary = {
	"country_flag_palettes": "res://data/world_map/country_flag_palettes.json",
	"strategic_military_overlay": "res://data/world_map/strategic_military_overlay.json",
}

const RUNTIME_FILES: Dictionary = {
	"world_coastlines": "res://data/world_map/world_coastlines.json",
	"countries": "res://data/world_map/countries.json",
	"regions": "res://data/world_map/regions.json",
	"cities": "res://data/world_map/cities.json",
	"ports": "res://data/world_map/ports.json",
	"rail_segments": "res://data/world_map/rail_segments.json",
	"road_segments": "res://data/world_map/road_segments.json",
	"shipping_routes": "res://data/world_map/shipping_routes.json",
	"characters": "res://data/world_map/characters.json",
	"name_pool_fr": "res://data/world_map/name_pool_fr.json",
	"relationships": "res://data/world_map/relationships.json",
	"organizations": "res://data/world_map/organizations.json",
	"institutions": "res://data/world_map/institutions.json",
	"activity": "res://data/world_map/world_activity.json",
	"map_modes": "res://data/world_map/map_modes.json",
	"map_geometry_cache": "res://data/world_map/map_geometry_cache.json",
	"country_flag_palettes": "res://data/world_map/country_flag_palettes.json",
	"strategic_military_overlay": "res://data/world_map/strategic_military_overlay.json",
}

const PROFILE_GROUPS: Dictionary = {
	"countries": ["res://data/world_map/countries.json"],
	"regions": ["res://data/world_map/regions.json"],
	"cities": ["res://data/world_map/cities.json"],
	"ports": ["res://data/world_map/ports.json"],
	"roads": ["res://data/world_map/road_segments.json"],
	"rail": ["res://data/world_map/rail_segments.json"],
	"shipping": ["res://data/world_map/shipping_routes.json"],
	"geometry_cache": [
		"res://data/world_map/world_coastlines.json",
		"res://data/world_map/map_geometry_cache.json",
	],
	"historical_data": [
		"res://data/world_map/world_admin1.json",
		"res://data/world_map/historical_political_entities_1900.json",
		"res://data/world_map/historical/political_units_1900.json",
		"res://data/world_map/historical/major_state_profiles_1900.json",
		"res://data/world_map/historical/major_economy_polity_crosswalk_1900.json",
		"res://data/world_map/historical/historical_admin1_1900.json",
		"res://data/world_map/historical/flags_1900.json",
		"res://data/world_map/historical/cshapes_1900_snapshot.json",
	],
	"organizations": ["res://data/world_map/organizations.json"],
	"characters": ["res://data/world_map/characters.json"],
	"institutions": ["res://data/world_map/institutions.json"],
	"supporting_runtime_data": [
		"res://data/world_map/name_pool_fr.json",
		"res://data/world_map/relationships.json",
		"res://data/world_map/world_activity.json",
		"res://data/world_map/map_modes.json",
		"res://data/world_map/country_flag_palettes.json",
		"res://data/world_map/strategic_military_overlay.json",
	],
}

const RECORD_ARRAY_KEYS: PackedStringArray = [
	"countries", "regions", "administrative_units", "cities", "ports",
	"segments", "routes", "features", "institutions", "catalog",
	"characters", "organizations", "relationships", "shards", "flags",
	"units", "records", "political_entities", "region_profiles",
]

const GEOMETRY_ARRAY_KEYS: PackedStringArray = [
	"polygons", "holes", "outer", "points", "coordinates", "graticule",
	"triangles", "lods",
]

const REQUIRED_TOP_LEVEL_KEYS: PackedStringArray = [
	"schema_version", "benchmark_id", "workload", "runtime_source_inventory", "runtime", "dataset_profile",
	"load_benchmark", "map_benchmark", "synthetic_scaling", "limitations",
]

const HOT_PATH_FINDINGS: Array[Dictionary] = [
	{
		"id": "HP01",
		"location": "scripts/world_map/internal/world_map_data_impl.gd::PrototypeV2Data._load_document",
		"finding": "每次 load_all 都重新读取并完整 JSON.parse_string 一个文档；当前没有 parsed-document cache。",
		"complexity": "O(total JSON bytes) per load",
	},
	{
		"id": "HP02",
		"location": "scripts/world_map/internal/world_map_canvas_impl.gd::setup",
		"finding": "setup 会重新提取数组、建立 ID 索引、转换 geometry cache、建立空间索引并重建 transport tie cache。",
		"complexity": "O(records + geometry vertices + index cell coverage)",
	},
	{
		"id": "HP03",
		"location": "scripts/world_map/internal/world_map_canvas_impl.gd::_refresh_visible_scene",
		"finding": "每次受控视图刷新会查询国家、行政区、宏区、城市、港口、机构、组织和三类运输索引。",
		"complexity": "O(number of queried buckets + candidates)",
	},
	{
		"id": "HP04",
		"location": "scripts/world_map/internal/world_map_canvas_impl.gd::_rail_segments_for_level",
		"finding": "运输显示层会过滤候选铁路并重新排序；高频重复调用时存在可缓存的排序成本。",
		"complexity": "O(rail records + rail records log rail records)",
	},
	{
		"id": "HP05",
		"location": "scripts/world_map/world_city_shard_catalog.gd::query",
		"finding": "城市分片查询会扫描全部 shard_metadata，再对相交分片排序并按缓存上限载入。",
		"complexity": "O(shards + intersecting shards log intersecting shards)",
	},
	{
		"id": "HP06",
		"location": "scripts/world_map/world_city_shard_catalog.gd::_thin_by_screen_spacing",
		"finding": "屏幕间距 thinning 对已接受点逐一比较；候选数增长时可能出现明显的二次项。",
		"complexity": "O(candidate records × accepted records)",
	},
]

const CANDIDATE_OPTIMIZATIONS: Array[Dictionary] = [
	{
		"id": "OPT01",
		"proposal": "为稳定输入增加带 schema/version 指纹的 parsed metadata 或 derived cache。",
		"boundary": "在 world-map JSON 总量达到约 10 MB，或启动/重载每次都发生多次完整解析时评估。",
	},
	{
		"id": "OPT02",
		"proposal": "将 geometry cache 的 PackedVector2/triangle 派生结果预构建为版本化二进制或紧凑缓存。",
		"boundary": "当 geometry vertex 总量达到约 1,000,000，或 setup 的 geometry conversion 超过 50 ms 中位数时评估。",
	},
	{
		"id": "OPT03",
		"proposal": "为 shard bounds 增加 tile/R-tree 级元数据索引，避免每个 viewport 扫描全部分片。",
		"boundary": "当 city-detail shard 数超过 1,000，或 viewport query 中位数超过 2 ms 时评估。",
	},
	{
		"id": "OPT04",
		"proposal": "缓存按 zoom level 的铁路排序候选与 label candidate 顺序。",
		"boundary": "当 rail records 超过 10,000，或 transport/label 刷新成为可见热点时评估。",
	},
	{
		"id": "OPT05",
		"proposal": "对城市 detail thinning 使用空间网格或固定屏幕桶，保留当前 node/label budget。",
		"boundary": "当单个 viewport 候选城市超过 2,000，或 thinning 成为 O(N²) 热点时评估。",
	},
]

const TOP_RISKS: Array[Dictionary] = [
	{"rank": 1, "risk": "启动或重载重复完整 JSON parse", "trigger": "world-map JSON 总量 > 10 MB，或同一会话重复 load > 1 次"},
	{"rank": 2, "risk": "geometry cache 一次性解码占用", "trigger": "geometry vertices > 1,000,000，或 decoded estimate > 64 MB"},
	{"rank": 3, "risk": "country LOD polygon 转换与空间索引初始化", "trigger": "国家特征 > 500，或单个 LOD vertices > 500,000"},
	{"rank": 4, "risk": "行政区 LOD 首次懒加载暂停", "trigger": "单个行政区 LOD records > 10,000"},
	{"rank": 5, "risk": "宏区空间索引的 bounds 多单元覆盖", "trigger": "宏区 records > 1,000，或平均单记录覆盖 > 100 cells"},
	{"rank": 6, "risk": "数组遍历建立 ID 索引", "trigger": "单类实体 > 100,000"},
	{"rank": 7, "risk": "大 bounds 记录插入 uniform-grid 产生桶膨胀", "trigger": "单条运输/几何记录覆盖 > 10,000 cells"},
	{"rank": 8, "risk": "每次 camera refresh 查询多个空间索引", "trigger": "刷新频率 > 60/s，或单次候选总量 > 50,000"},
	{"rank": 9, "risk": "可见铁路过滤与排序重复执行", "trigger": "rail records > 10,000，或 transport layer 高频重绘"},
	{"rank": 10, "risk": "可见标签候选排序与碰撞筛选", "trigger": "label candidates > 5,000"},
	{"rank": 11, "risk": "几何转换产生重复 Dictionary/PackedArray 结构", "trigger": "setup decoded estimate > 128 MB"},
	{"rank": 12, "risk": "city shard metadata 每次 viewport 全扫描", "trigger": "shards > 1,000，或 query > 2 ms median"},
	{"rank": 13, "risk": "city shard cache 反复驱逐造成 thrash", "trigger": "一次 viewport 相交 shards > cache limit，且相邻视图来回切换"},
	{"rank": 14, "risk": "城市 detail 候选 thinning 二次比较", "trigger": "单视口候选 > 2,000，或 accepted 接近 node budget"},
	{"rank": 15, "risk": "城市 detail 命中检测线性扫描 visible records", "trigger": "visible city detail records > 1,600"},
	{"rank": 16, "risk": "transport bounds/points 派生缓存增长", "trigger": "rail + road + shipping records > 100,000"},
	{"rank": 17, "risk": "长运输线跨大量网格桶", "trigger": "单条长线覆盖 > 10,000 cells"},
	{"rank": 18, "risk": "字符串 ID 转换与 key 构造重复", "trigger": "每帧处理记录 > 100,000，或 profile 显示字符串成本成为前 5 热点"},
	{"rank": 19, "risk": "历史/现代参考数据边界扩大后混入常规 load", "trigger": "非运行时历史文件被加入启动路径，或历史 records > 1,000,000"},
	{"rank": 20, "risk": "基准分布未转化为回归阈值", "trigger": "连续三次 baseline 后仍无 median/p95 分布记录"},
]

var _json_output_path: String = "artifacts/world-data-performance-baseline-20260812.json"
var _markdown_output_path: String = "artifacts/world-data-performance-baseline-20260812.md"
var _last_runtime_data: PrototypeV2Data


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_parse_arguments()
	var payload: Dictionary = _build_payload()
	var schema_errors: Array[String] = validate_result_schema(payload)
	payload["validation"] = {
		"result_schema_valid": schema_errors.is_empty(),
		"schema_errors": schema_errors,
	}
	var json_ok: bool = _write_text(_json_output_path, JSON.stringify(payload, "\t", true))
	var markdown_ok: bool = _write_text(_markdown_output_path, _render_markdown(payload))
	_print_summary(payload)
	if not json_ok or not markdown_ok or not schema_errors.is_empty():
		quit(1)
		return
	quit(0)


static func validate_result_schema(payload: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key: String in REQUIRED_TOP_LEVEL_KEYS:
		if not payload.has(key):
			errors.append("missing top-level key: %s" % key)
	if int(payload.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("schema_version must be %d" % SCHEMA_VERSION)
	if str(payload.get("benchmark_id", "")) != BENCHMARK_ID:
		errors.append("benchmark_id mismatch")
	var workload: Variant = payload.get("workload", {})
	if not workload is Dictionary:
		errors.append("workload must be a Dictionary")
	else:
		for key: String in ["iterations", "map_iterations", "lookup_iterations", "synthetic_scales"]:
			if not (workload as Dictionary).has(key):
				errors.append("workload missing %s" % key)
	var scaling: Variant = payload.get("synthetic_scaling", [])
	if not scaling is Array or (scaling as Array).size() != 4:
		errors.append("synthetic_scaling must contain four fixed scales")
	var limitations: Variant = payload.get("limitations", [])
	if not limitations is Array or not (limitations as Array).has(BENCHMARK_SEMANTICS):
		errors.append("limitations must identify machine-specific observational semantics")
	return errors


static func schema_probe() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"benchmark_id": BENCHMARK_ID,
		"workload": {
			"iterations": ITERATIONS,
			"map_iterations": MAP_ITERATIONS,
			"lookup_iterations": LOOKUP_ITERATIONS,
			"synthetic_scales": [1, 2, 5, 10],
		},
		"runtime_source_inventory": {
			"loader_file_count": RUNTIME_LOADER_FILES.size(),
			"loader_paths": RUNTIME_LOADER_FILES.values(),
			"supporting_file_count": RUNTIME_SUPPORTING_FILES.size(),
			"supporting_paths": RUNTIME_SUPPORTING_FILES.values(),
			"source_inventory_file_count": RUNTIME_FILES.size(),
		},
		"runtime": {},
		"dataset_profile": {},
		"load_benchmark": {},
		"map_benchmark": {},
		"synthetic_scaling": [{"scale": 1}, {"scale": 2}, {"scale": 5}, {"scale": 10}],
		"limitations": [BENCHMARK_SEMANTICS],
	}


func _build_payload() -> Dictionary:
	var started_usec: int = Time.get_ticks_usec()
	var profile: Dictionary = _profile_all_groups()
	var load_results: Dictionary = _measure_loads()
	var map_results: Dictionary = _measure_map_benchmarks()
	var synthetic_results: Array[Dictionary] = _measure_synthetic_scaling()
	var runtime_source_inventory: Dictionary = _runtime_source_inventory()
	return {
		"schema_version": SCHEMA_VERSION,
		"benchmark_id": BENCHMARK_ID,
		"generated_at": Time.get_datetime_string_from_system(true),
		"workload": {
			"iterations": ITERATIONS,
			"map_iterations": MAP_ITERATIONS,
			"lookup_iterations": LOOKUP_ITERATIONS,
			"synthetic_iterations": SYNTHETIC_ITERATIONS,
			"synthetic_base_records": SYNTHETIC_BASE_RECORDS,
			"synthetic_scales": [1, 2, 5, 10],
			"input_policy": "fixed repository paths; synthetic records are generated deterministically in memory",
		},
		"runtime_source_inventory": runtime_source_inventory,
		"runtime": _runtime_metadata(),
		"dataset_profile": profile,
		"load_benchmark": load_results,
		"map_benchmark": map_results,
		"synthetic_scaling": synthetic_results,
		"hot_path_inventory": HOT_PATH_FINDINGS,
		"candidate_optimizations": CANDIDATE_OPTIMIZATIONS,
		"top_20_future_risks": TOP_RISKS,
		"limitations": [
			BENCHMARK_SEMANTICS,
			"真实 process RSS/heap 未可靠测量：NOT MEASURED；decoded_data_bytes_estimate 是递归估算，不是 allocator 计数。",
			"cold parse 是同一进程的 first-pass 样本，未重启进程，也未控制 OS 文件缓存。",
			"benchmark 未改变生产 runtime，也未把 synthetic 数据写入正式 world data。",
			"benchmark 使用固定的 repository-local 输入；live master fetch/push 状态属于交付环境，不影响测量结果。当前源清单基线 master SHA 为 %s；历史 timing 报告中的测量值未被回填或伪造。" % SOURCE_BASELINE_MASTER,
		],
		"benchmark_elapsed_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
	}


func _runtime_source_inventory() -> Dictionary:
	return {
		"loader_file_count": RUNTIME_LOADER_FILES.size(),
		"loader_paths": RUNTIME_LOADER_FILES.values(),
		"supporting_file_count": RUNTIME_SUPPORTING_FILES.size(),
		"supporting_paths": RUNTIME_SUPPORTING_FILES.values(),
		"source_inventory_file_count": RUNTIME_FILES.size(),
	}


func _runtime_metadata() -> Dictionary:
	var version_info: Dictionary = Engine.get_version_info()
	return {
		"godot_version": str(version_info.get("string", Engine.get_version_info().get("string", "unknown"))),
		"godot_hash": str(version_info.get("hash", "unknown")),
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"features": OS.get_processor_count(),
		"headless": DisplayServer.get_name() == "headless",
	}


func _parse_arguments() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	for user_argument: String in OS.get_cmdline_user_args():
		if not arguments.has(user_argument):
			arguments.append(user_argument)
	for argument: String in arguments:
		if argument.begins_with("--json-output="):
			_json_output_path = argument.trim_prefix("--json-output=")
		elif argument.begins_with("--markdown-output="):
			_markdown_output_path = argument.trim_prefix("--markdown-output=")


func _profile_all_groups() -> Dictionary:
	var groups: Dictionary = PROFILE_GROUPS.duplicate(true)
	var city_detail_paths: Array[String] = _collect_json_files("res://data/world_map/city_detail")
	var shard_paths: Array[String] = []
	for city_detail_path: String in city_detail_paths:
		if city_detail_path.ends_with("/index.json") or city_detail_path.ends_with("/LICENSE.json"):
			continue
		shard_paths.append(city_detail_path)
	groups["city_detail_shards"] = shard_paths
	groups["city_detail_index"] = ["res://data/world_map/city_detail/index.json"]
	var result: Dictionary = {}
	for group_name_variant: Variant in groups.keys():
		var group_name: String = str(group_name_variant)
		var paths: Array[String] = []
		for path_variant: Variant in groups[group_name_variant] as Array:
			paths.append(str(path_variant))
		result[group_name] = _profile_group(paths)
	return result


func _collect_json_files(path: String) -> Array[String]:
	var files: Array[String] = []
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return files
	for file_name: String in directory.get_files():
		if file_name.ends_with(".json"):
			files.append(path.path_join(file_name))
	for child_name: String in directory.get_directories():
		files.append_array(_collect_json_files(path.path_join(child_name)))
	return _unique_sorted_paths(files)


func _unique_sorted_paths(paths: Array[String]) -> Array[String]:
	var unique: Dictionary = {}
	for path: String in paths:
		unique[path] = true
	var result: Array[String] = []
	for path_variant: Variant in unique.keys():
		result.append(str(path_variant))
	result.sort()
	return result


func _profile_group(paths: Array[String]) -> Dictionary:
	var profiles: Array[Dictionary] = []
	var total: Dictionary = {
		"file_count": 0,
		"file_size_bytes": 0,
		"record_count": 0,
		"decoded_object_count": 0,
		"decoded_array_count": 0,
		"decoded_scalar_count": 0,
		"geometry_vertex_count": 0,
		"decoded_data_bytes_estimate": 0,
		"parse_errors": 0,
	}
	for path: String in paths:
		var profile: Dictionary = _profile_file(path)
		profiles.append(profile)
		for key: String in [
			"file_count", "file_size_bytes", "record_count", "decoded_object_count",
			"decoded_array_count", "decoded_scalar_count", "geometry_vertex_count",
			"decoded_data_bytes_estimate", "parse_errors",
		]:
			total[key] = int(total.get(key, 0)) + int(profile.get(key, 0))
	var largest_files: Array[Dictionary] = []
	var largest_arrays: Array[Dictionary] = []
	var largest_maps: Array[Dictionary] = []
	var largest_records: Array[Dictionary] = []
	for profile: Dictionary in profiles:
		largest_files.append({
			"path": profile.get("path", ""),
			"bytes": int(profile.get("file_size_bytes", 0)),
		})
		largest_arrays.append_array(profile.get("largest_arrays", []) as Array)
		largest_maps.append_array(profile.get("largest_maps", []) as Array)
		largest_records.append_array(profile.get("largest_records", []) as Array)
	total["largest_files"] = _top_by_number(largest_files, "bytes", 10)
	total["largest_arrays"] = _top_by_number(largest_arrays, "count", 10)
	total["largest_maps"] = _top_by_number(largest_maps, "count", 10)
	total["largest_records"] = _top_by_number(largest_records, "count", 10)
	total["files"] = profiles
	return total


func _profile_file(path: String) -> Dictionary:
	var result: Dictionary = {
		"path": path,
		"file_count": 1,
		"file_size_bytes": 0,
		"record_count": 0,
		"decoded_object_count": 0,
		"decoded_array_count": 0,
		"decoded_scalar_count": 0,
		"geometry_vertex_count": 0,
		"decoded_data_bytes_estimate": 0,
		"parse_errors": 0,
		"largest_arrays": [],
		"largest_maps": [],
		"largest_records": [],
	}
	if not FileAccess.file_exists(path):
		result["parse_errors"] = 1
		return result
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["parse_errors"] = 1
		return result
	result["file_size_bytes"] = file.get_length()
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		result["parse_errors"] = 1
		return result
	var arrays: Array[Dictionary] = []
	var maps: Array[Dictionary] = []
	var stats: Dictionary = {
		"decoded_object_count": 0,
		"decoded_array_count": 0,
		"decoded_scalar_count": 0,
		"geometry_vertex_count": 0,
		"record_count": 0,
	}
	_walk_value(parsed, "$", stats, arrays, maps)
	result["decoded_object_count"] = stats["decoded_object_count"]
	result["decoded_array_count"] = stats["decoded_array_count"]
	result["decoded_scalar_count"] = stats["decoded_scalar_count"]
	result["geometry_vertex_count"] = stats["geometry_vertex_count"]
	result["record_count"] = stats["record_count"]
	result["decoded_data_bytes_estimate"] = _estimate_decoded_bytes(parsed)
	result["largest_arrays"] = _top_by_number(arrays, "count", 10)
	result["largest_maps"] = _top_by_number(maps, "count", 10)
	var records: Array[Dictionary] = []
	for item: Dictionary in arrays:
		if bool(item.get("record_array", false)):
			records.append(item)
	result["largest_records"] = _top_by_number(records, "count", 10)
	return result


func _walk_value(
	value: Variant,
	path: String,
	stats: Dictionary,
	arrays: Array[Dictionary],
	maps: Array[Dictionary]
) -> void:
	if value is Dictionary:
		stats["decoded_object_count"] = int(stats["decoded_object_count"]) + 1
		var dictionary: Dictionary = value as Dictionary
		maps.append({"path": path, "count": dictionary.size()})
		if _looks_like_record_map(path, dictionary):
			stats["record_count"] = int(stats["record_count"]) + dictionary.size()
		for key_variant: Variant in dictionary.keys():
			var key: String = str(key_variant)
			_walk_value(dictionary[key_variant], "%s.%s" % [path, key], stats, arrays, maps)
		return
	if value is Array:
		stats["decoded_array_count"] = int(stats["decoded_array_count"]) + 1
		var array: Array = value as Array
		var record_array: bool = _looks_like_record_array(path, array)
		arrays.append({
			"path": path,
			"count": array.size(),
			"record_array": record_array,
			"geometry_array": _is_geometry_path(path),
		})
		if _is_numeric_pair(array):
			stats["geometry_vertex_count"] = int(stats["geometry_vertex_count"]) + 1
			return
		if record_array:
			stats["record_count"] = int(stats["record_count"]) + array.size()
		for index: int in range(array.size()):
			_walk_value(array[index], "%s[%d]" % [path, index], stats, arrays, maps)
		return
	stats["decoded_scalar_count"] = int(stats["decoded_scalar_count"]) + 1


func _looks_like_record_map(path: String, dictionary: Dictionary) -> bool:
	var key: String = path
	var last_dot: int = key.rfind(".")
	if last_dot >= 0:
		key = key.substr(last_dot + 1)
	return key in ["identities"] and not dictionary.is_empty()


func _looks_like_record_array(path: String, array: Array) -> bool:
	if array.is_empty() or not array[0] is Dictionary:
		return false
	var key: String = path
	var last_dot: int = key.rfind(".")
	if last_dot >= 0:
		key = key.substr(last_dot + 1)
	var first_bracket: int = key.find("[")
	if first_bracket >= 0:
		key = key.substr(0, first_bracket)
	if key in GEOMETRY_ARRAY_KEYS:
		return false
	if key in RECORD_ARRAY_KEYS:
		return true
	return key.ends_with("_records") or key.ends_with("_units")


func _is_geometry_path(path: String) -> bool:
	for key: String in GEOMETRY_ARRAY_KEYS:
		if path.ends_with("." + key) or path.contains("." + key + "["):
			return true
	return path.contains("geometry") or path.contains("polygons")


func _is_numeric_pair(value: Array) -> bool:
	if value.size() != 2:
		return false
	return _is_number(value[0]) and _is_number(value[1])


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func _estimate_decoded_bytes(value: Variant) -> int:
	if value is Dictionary:
		var total: int = 32
		var dictionary: Dictionary = value as Dictionary
		for key_variant: Variant in dictionary.keys():
			total += 24 + str(key_variant).length() * 2
			total += _estimate_decoded_bytes(dictionary[key_variant])
		return total
	if value is Array:
		var array_total: int = 24
		for item: Variant in value as Array:
			array_total += 8 + _estimate_decoded_bytes(item)
		return array_total
	if value is String:
		return 24 + (value as String).length() * 2
	if value is int or value is float:
		return 8
	return 4


func _top_by_number(values: Array, field: String, limit: int) -> Array[Dictionary]:
	var sorted: Array = values.duplicate()
	sorted.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_value: int = int(left.get(field, 0))
		var right_value: int = int(right.get(field, 0))
		if left_value != right_value:
			return left_value > right_value
		return str(left.get("path", "")) < str(right.get("path", ""))
	)
	if sorted.size() > limit:
		sorted.resize(limit)
	var result: Array[Dictionary] = []
	for item: Variant in sorted:
		result.append(item as Dictionary)
	return result


func _measure_loads() -> Dictionary:
	var runtime_paths: Array[String] = []
	for path_variant: Variant in RUNTIME_FILES.values():
		runtime_paths.append(str(path_variant))
	var per_file: Dictionary = {}
	for path: String in runtime_paths:
		per_file[path] = _measure_json_parse(path)
	var full_samples: Array = []
	var full_success: bool = true
	var loaded_document_count: int = 0
	for _index: int in range(ITERATIONS):
		var started_usec: int = Time.get_ticks_usec()
		var data := PrototypeV2Data.new()
		var success: bool = data.load_all()
		full_success = full_success and success
		loaded_document_count = data.records.size()
		full_samples.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
		_last_runtime_data = data
	var geometry_parse: Dictionary = _measure_json_parse(
		str(RUNTIME_FILES["map_geometry_cache"])
	)
	var city_index_parse: Dictionary = _measure_json_parse(
		"res://data/world_map/city_detail/index.json"
	)
	return {
		"runtime_file_parse": per_file,
		"full_world_data_load": _with_cold_warm(full_samples).merged({
			"success": full_success,
			"loaded_document_count": loaded_document_count,
			"scope": "PrototypeV2Data.load_all() runtime-set load",
		}),
		"geometry_cache_parse": geometry_parse.merged({
			"scope": "JSON parse of map_geometry_cache.json; conversion is measured below in canvas setup",
		}),
		"city_detail_index_parse": city_index_parse,
	}


func _measure_json_parse(path: String) -> Dictionary:
	var samples: Array = []
	var parse_success: bool = true
	var decoded_size: int = 0
	for _index: int in range(ITERATIONS):
		var started_usec: int = Time.get_ticks_usec()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		parse_success = parse_success and parsed != null
		if parsed is Dictionary:
			decoded_size = (parsed as Dictionary).size()
		samples.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	var result: Dictionary = _with_cold_warm(samples)
	result["path"] = path
	result["success"] = parse_success
	result["decoded_top_level_size"] = decoded_size
	return result


func _with_cold_warm(samples: Array) -> Dictionary:
	var result: Dictionary = _stats(samples)
	result["cold_ms"] = float(samples[0]) if not samples.is_empty() else -1.0
	result["warm"] = _stats(samples.slice(1)) if samples.size() > 1 else _stats([])
	return result


func _stats(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {"iterations": 0, "min_ms": -1.0, "median_ms": -1.0, "max_ms": -1.0, "samples_ms": []}
	var ordered: Array = samples.duplicate()
	ordered.sort()
	var median: float
	if ordered.size() % 2 == 1:
		median = float(ordered[ordered.size() / 2])
	else:
		var middle: int = ordered.size() / 2
		median = (float(ordered[middle - 1]) + float(ordered[middle])) * 0.5
	return {
		"iterations": samples.size(),
		"min_ms": float(ordered[0]),
		"median_ms": median,
		"max_ms": float(ordered[ordered.size() - 1]),
		"samples_ms": samples,
	}


func _measure_map_benchmarks() -> Dictionary:
	if _last_runtime_data == null:
		return {"error": "PrototypeV2Data.load_all() runtime-set load failed"}
	var canvas := PrototypeV2MapCanvas.new()
	var setup_samples: Array = []
	for _index: int in range(MAP_ITERATIONS):
		var started_usec: int = Time.get_ticks_usec()
		canvas.setup(_last_runtime_data)
		setup_samples.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	var setup_result: Dictionary = _with_cold_warm(setup_samples)
	setup_result["scope"] = "PrototypeV2MapCanvas.setup: geometry conversion + ID indexes + spatial indexes + transport tie cache + first view query"
	setup_result["architecture"] = canvas.debug_architecture_state()
	var view_results: Dictionary = {}
	for view_id: String in ["world", "europe", "france", "player_location"]:
		view_results[view_id] = _measure_view(canvas, view_id)
	var lookup_result: Dictionary = _measure_representative_lookups(canvas)
	var city_detail_result: Dictionary = _measure_city_detail(canvas)
	return {
		"canvas_setup_geometry_and_index": setup_result,
		"representative_view_queries": view_results,
		"representative_lookup": lookup_result,
		"city_detail_lazy_load": city_detail_result,
		"route_query": {
			"status": "NOT AVAILABLE as a separate authoritative route service on this loader",
			"coverage": "transport visibility is included in representative_view_queries via rail/road/shipping spatial indexes",
		},
	}


func _measure_view(canvas: PrototypeV2MapCanvas, view_id: String) -> Dictionary:
	var samples: Array = []
	var checksum: int = 0
	var last_snapshot: Dictionary = {}
	for _index: int in range(MAP_ITERATIONS):
		var started_usec: int = Time.get_ticks_usec()
		match view_id:
			"world": canvas.reset_view()
			"europe": canvas.focus_europe()
			"france": canvas.focus_france()
			"player_location": canvas.focus_player_location()
		last_snapshot = canvas.debug_architecture_state()
		var counts: Dictionary = last_snapshot.get("visible_counts", {}) as Dictionary
		for value: Variant in counts.values():
			checksum += int(value)
		samples.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	return _with_cold_warm(samples).merged({
		"view_id": view_id,
		"checksum": checksum,
		"last_visible_counts": last_snapshot.get("visible_counts", {}),
		"last_lod": str(last_snapshot.get("lod", "")),
	})


func _measure_representative_lookups(canvas: PrototypeV2MapCanvas) -> Dictionary:
	var country_ids: Array[String] = _ids_from_document(_last_runtime_data.get_document("countries"), "countries")
	var region_ids: Array[String] = _ids_from_document(_last_runtime_data.get_document("regions"), "regions")
	var city_ids: Array[String] = _ids_from_document(_last_runtime_data.get_document("cities"), "cities")
	var port_ids: Array[String] = _ids_from_document(_last_runtime_data.get_document("ports"), "ports")
	var institution_ids: Array[String] = _ids_from_document(_last_runtime_data.get_document("institutions"), "institutions")
	var organization_ids: Array[String] = _ids_from_document(_last_runtime_data.get_document("organizations"), "catalog")
	var samples: Array = []
	var checksum: int = 0
	for _sample_index: int in range(MAP_ITERATIONS):
		var started_usec: int = Time.get_ticks_usec()
		for lookup_index: int in range(LOOKUP_ITERATIONS):
			if not country_ids.is_empty():
				checksum += canvas.get_country(country_ids[lookup_index % country_ids.size()]).size()
			if not region_ids.is_empty():
				checksum += canvas.get_region(region_ids[lookup_index % region_ids.size()]).size()
			if not city_ids.is_empty():
				checksum += canvas.get_city(city_ids[lookup_index % city_ids.size()]).size()
			if not institution_ids.is_empty():
				checksum += canvas.get_institution(institution_ids[lookup_index % institution_ids.size()]).size()
			if not organization_ids.is_empty():
				checksum += canvas.get_organization(organization_ids[lookup_index % organization_ids.size()]).size()
		samples.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	var result: Dictionary = _with_cold_warm(samples)
	result["operations_per_iteration"] = LOOKUP_ITERATIONS * 5
	result["checksum"] = checksum
	result["id_counts"] = {
		"countries": country_ids.size(),
		"regions": region_ids.size(),
		"cities": city_ids.size(),
		"ports": port_ids.size(),
		"institutions": institution_ids.size(),
		"organizations": organization_ids.size(),
	}
	var city_id: String = "lille" if city_ids.has("lille") else (city_ids[0] if not city_ids.is_empty() else "")
	var city: Dictionary = canvas.get_city(city_id)
	var city_lon_lat: Variant = city.get("lon_lat", [3.0573, 50.6292])
	canvas.focus_player_location()
	var screen_point: Vector2 = canvas.lon_lat_to_screen(city_lon_lat)
	var point_samples: Array = []
	var point_checksum: int = 0
	for _sample_index: int in range(MAP_ITERATIONS):
		var point_started_usec: int = Time.get_ticks_usec()
		for _lookup_index: int in range(LOOKUP_ITERATIONS):
			point_checksum += canvas.get_object_at(screen_point).size()
		point_samples.append(float(Time.get_ticks_usec() - point_started_usec) / 1000.0)
	result["representative_point_query"] = _with_cold_warm(point_samples).merged({
		"city_id": city_id,
		"point_checksum": point_checksum,
	})
	return result


func _ids_from_document(document: Dictionary, key: String) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in document.get(key, []) as Array:
		if value is Dictionary:
			var entity_id: String = str((value as Dictionary).get("id", ""))
			if not entity_id.is_empty():
				result.append(entity_id)
	return result


func _measure_city_detail(canvas: PrototypeV2MapCanvas) -> Dictionary:
	var catalog := WorldCityShardCatalog.new()
	var projector := Callable(canvas, "project_lon_lat")
	var configure_samples: Array = []
	var configured: bool = true
	for _index: int in range(MAP_ITERATIONS):
		var started_usec: int = Time.get_ticks_usec()
		var candidate := WorldCityShardCatalog.new()
		configured = configured and candidate.configure(projector)
		configure_samples.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
		catalog = candidate
	var west: Vector2 = canvas.project_lon_lat([-10.0, 35.0])
	var east: Vector2 = canvas.project_lon_lat([30.0, 60.0])
	var query_rect := Rect2(west.min(east), west.max(east) - west.min(east)).grow(8.0)
	var cold_samples: Array = []
	var warm_samples: Array = []
	var cold_changed: int = 0
	for _index: int in range(MAP_ITERATIONS):
		catalog.clear_cache()
		var cold_started_usec: int = Time.get_ticks_usec()
		cold_changed += 1 if catalog.query(query_rect, "regional", 18.0) else 0
		cold_samples.append(float(Time.get_ticks_usec() - cold_started_usec) / 1000.0)
		var warm_started_usec: int = Time.get_ticks_usec()
		catalog.query(query_rect, "regional", 18.0)
		warm_samples.append(float(Time.get_ticks_usec() - warm_started_usec) / 1000.0)
	return {
		"configure": _with_cold_warm(configure_samples).merged({
			"success": configured,
			"scope": "WorldCityShardCatalog.configure (index metadata only)",
		}),
		"cold_query": _with_cold_warm(cold_samples).merged({
			"query_rect": [query_rect.position.x, query_rect.position.y, query_rect.size.x, query_rect.size.y],
			"changed_count": cold_changed,
		}),
		"warm_query": _with_cold_warm(warm_samples),
		"last_snapshot": catalog.debug_snapshot(),
	}


func _measure_synthetic_scaling() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for scale: int in [1, 2, 5, 10]:
		var records: Array[Dictionary] = _make_synthetic_records(SYNTHETIC_BASE_RECORDS * scale)
		var serialized: String = JSON.stringify({"records": records}, "", true)
		var parse_samples: Array = []
		var parse_checksum: int = 0
		for _iteration: int in range(SYNTHETIC_ITERATIONS):
			var parse_started_usec: int = Time.get_ticks_usec()
			var parsed: Variant = JSON.parse_string(serialized)
			if parsed is Dictionary:
				parse_checksum += (parsed as Dictionary).size()
			parse_samples.append(float(Time.get_ticks_usec() - parse_started_usec) / 1000.0)
		var index_samples: Array = []
		for _iteration: int in range(SYNTHETIC_ITERATIONS):
			var spatial_index := PrototypeV2SpatialIndex.new()
			var index_started_usec: int = Time.get_ticks_usec()
			spatial_index.configure(Rect2(Vector2.ZERO, Vector2(1080.0, 540.0)), 8.0, records.size())
			for record_index: int in range(records.size()):
				spatial_index.insert(record_index, _array_to_rect(records[record_index]["bounds"] as Array))
			index_samples.append(float(Time.get_ticks_usec() - index_started_usec) / 1000.0)
		var lookup_index := PrototypeV2SpatialIndex.new()
		lookup_index.configure(Rect2(Vector2.ZERO, Vector2(1080.0, 540.0)), 8.0, records.size())
		for record_index: int in range(records.size()):
			lookup_index.insert(record_index, _array_to_rect(records[record_index]["bounds"] as Array))
		var lookup_samples: Array = []
		var lookup_checksum: int = 0
		var output: Array[int] = []
		for _iteration: int in range(SYNTHETIC_ITERATIONS):
			var lookup_started_usec: int = Time.get_ticks_usec()
			for query_index: int in range(SYNTHETIC_LOOKUPS):
				var point := Vector2(
					fmod(float(query_index * 37 + scale * 11), 1079.0),
					fmod(float(query_index * 53 + scale * 7), 539.0)
				)
				lookup_index.query_point(point, output)
				lookup_checksum += output.size()
			lookup_samples.append(float(Time.get_ticks_usec() - lookup_started_usec) / 1000.0)
		result.append({
			"scale": scale,
			"record_count": records.size(),
			"serialized_bytes": serialized.to_utf8_buffer().size(),
			"input_sha256": serialized.sha256_text(),
			"parse": _stats(parse_samples).merged({"checksum": parse_checksum}),
			"index_build": _stats(index_samples),
			"lookup": _stats(lookup_samples).merged({
				"queries_per_iteration": SYNTHETIC_LOOKUPS,
				"checksum": lookup_checksum,
			}),
		})
	return result


func _make_synthetic_records(count: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for index: int in range(count):
		var x: float = fmod(float(index * 37), 1060.0)
		var y: float = fmod(float(index * 53), 520.0)
		var width: float = 2.0 + float(index % 7)
		var height: float = 2.0 + float(index % 5)
		records.append({
			"id": "synthetic:%08d" % index,
			"bounds": [x, y, width, height],
			"value": index * 17 + 3,
		})
	return records


func _array_to_rect(value: Array) -> Rect2:
	if value.size() != 4:
		return Rect2()
	return Rect2(Vector2(float(value[0]), float(value[1])), Vector2(float(value[2]), float(value[3])))


func _render_markdown(payload: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("# WWO WORLD DATA PERFORMANCE BASELINE — BATCH 1")
	lines.append("")
	lines.append("Source-inventory baseline master: %s" % SOURCE_BASELINE_MASTER)
	lines.append("Branch: chore/world-data-performance-baseline-20260812")
	lines.append("")
	lines.append("This is a measurement report. Production gameplay, authoritative map data, and workflows were not modified.")
	lines.append("")
	lines.append("## Runtime and workload")
	lines.append("")
	lines.append("- Runtime: %s on %s (%s)" % [
		str((payload["runtime"] as Dictionary).get("godot_version", "")),
		str((payload["runtime"] as Dictionary).get("os", "")),
		str((payload["runtime"] as Dictionary).get("processor", "")),
	])
	lines.append("- Iterations: %d full samples, %d map samples, %d lookup operations per lookup sample." % [ITERATIONS, MAP_ITERATIONS, LOOKUP_ITERATIONS])
	lines.append("- Synthetic scales: 1x, 2x, 5x, 10x; base %d records; synthetic data remains memory-only." % SYNTHETIC_BASE_RECORDS)
	lines.append("- Benchmark semantics: MACHINE-SPECIFIC OBSERVATIONAL BASELINE; timings are not universal CI pass/fail thresholds.")
	var source_inventory: Dictionary = payload["runtime_source_inventory"] as Dictionary
	lines.append("- Runtime source inventory: %d loader files + %d supporting files = %d benchmark parse sources." % [
		int(source_inventory.get("loader_file_count", 0)),
		int(source_inventory.get("supporting_file_count", 0)),
		int(source_inventory.get("source_inventory_file_count", 0)),
	])
	lines.append("- Historical timing values are preserved; this reconciliation updates source inventory/provenance only.")
	lines.append("")
	lines.append("## Dataset sizes")
	lines.append("")
	lines.append("| Dataset | Files | Raw bytes | Records | Decoded objects | Geometry points | Decoded estimate |")
	lines.append("|---|---:|---:|---:|---:|---:|---:|")
	for group_name_variant: Variant in (payload["dataset_profile"] as Dictionary).keys():
		var group_name: String = str(group_name_variant)
		var group: Dictionary = (payload["dataset_profile"] as Dictionary)[group_name_variant] as Dictionary
		lines.append("| %s | %d | %s | %d | %d | %d | %s |" % [
			group_name,
			int(group.get("file_count", 0)),
			_format_bytes(int(group.get("file_size_bytes", 0))),
			int(group.get("record_count", 0)),
			int(group.get("decoded_object_count", 0)),
			int(group.get("geometry_vertex_count", 0)),
			_format_bytes(int(group.get("decoded_data_bytes_estimate", 0))),
		])
	lines.append("")
	lines.append("Largest files and high-cardinality structures are preserved in the machine-readable JSON artifact.")
	lines.append("")
	lines.append("## Load benchmark")
	lines.append("")
	var loads: Dictionary = payload["load_benchmark"] as Dictionary
	lines.append("- PrototypeV2Data.load_all() runtime-set load: %s" % _format_metric(loads.get("full_world_data_load", {}) as Dictionary))
	lines.append("- Geometry cache JSON parse: %s" % _format_metric(loads.get("geometry_cache_parse", {}) as Dictionary))
	lines.append("- City-detail index JSON parse: %s" % _format_metric(loads.get("city_detail_index_parse", {}) as Dictionary))
	lines.append("")
	lines.append("Per-file parse distributions are in runtime_file_parse in the JSON artifact.")
	lines.append("")
	lines.append("## Geometry, index, and map query benchmark")
	lines.append("")
	var maps: Dictionary = payload["map_benchmark"] as Dictionary
	lines.append("- Canvas setup (geometry conversion + ID indexes + spatial indexes + transport tie cache): %s" % _format_metric(maps.get("canvas_setup_geometry_and_index", {}) as Dictionary))
	var views: Dictionary = maps.get("representative_view_queries", {}) as Dictionary
	for view_id_variant: Variant in views.keys():
		var view: Dictionary = views[view_id_variant] as Dictionary
		lines.append("- View %s: %s; visible counts %s." % [str(view_id_variant), _format_metric(view), str(view.get("last_visible_counts", {}))])
	var lookup: Dictionary = maps.get("representative_lookup", {}) as Dictionary
	lines.append("- Representative ID lookups: %s (%d operations/sample)." % [_format_metric(lookup), int(lookup.get("operations_per_iteration", 0))])
	lines.append("- Representative map point query: %s" % _format_metric(lookup.get("representative_point_query", {}) as Dictionary))
	var city_detail: Dictionary = maps.get("city_detail_lazy_load", {}) as Dictionary
	lines.append("- City-detail index configure: %s" % _format_metric(city_detail.get("configure", {}) as Dictionary))
	lines.append("- City-detail cold viewport query: %s" % _format_metric(city_detail.get("cold_query", {}) as Dictionary))
	lines.append("- City-detail warm viewport query: %s" % _format_metric(city_detail.get("warm_query", {}) as Dictionary))
	lines.append("")
	lines.append("## Synthetic scaling")
	lines.append("")
	lines.append("| Scale | Records | JSON bytes | Parse median | Index median | Lookup median |")
	lines.append("|---:|---:|---:|---:|---:|---:|")
	for item: Dictionary in payload["synthetic_scaling"] as Array:
		lines.append("| %dx | %d | %s | %s | %s | %s |" % [
			int(item.get("scale", 0)),
			int(item.get("record_count", 0)),
			_format_bytes(int(item.get("serialized_bytes", 0))),
			_format_metric(item.get("parse", {}) as Dictionary),
			_format_metric(item.get("index_build", {}) as Dictionary),
			_format_metric(item.get("lookup", {}) as Dictionary),
		])
	lines.append("")
	lines.append("Interpretation is intentionally conservative: use the measured distribution to decide when a future optimization is justified; no CI gate is set here.")
	lines.append("")
	lines.append("## Likely complexity risks")
	lines.append("")
	for finding: Dictionary in HOT_PATH_FINDINGS:
		lines.append("- %s — %s (%s)." % [str(finding["id"]), str(finding["finding"]), str(finding["complexity"])])
	lines.append("")
	lines.append("## Candidate optimizations")
	lines.append("")
	for proposal: Dictionary in CANDIDATE_OPTIMIZATIONS:
		lines.append("- %s — %s Boundary: %s" % [str(proposal["id"]), str(proposal["proposal"]), str(proposal["boundary"])])
	lines.append("")
	lines.append("## TOP 20 FUTURE WORLD-DATA PERFORMANCE RISKS")
	lines.append("")
	lines.append("| # | Risk | Revisit when |")
	lines.append("|---:|---|---|")
	for risk: Dictionary in TOP_RISKS:
		lines.append("| %d | %s | %s |" % [int(risk["rank"]), str(risk["risk"]), str(risk["trigger"])])
	lines.append("")
	lines.append("## Measurement limits and handoff")
	lines.append("")
	for limitation: String in payload["limitations"] as Array:
		lines.append("- %s" % limitation)
	lines.append("")
	lines.append("Production code modified: NO")
	lines.append("Benchmark tooling is under tools/ and its harness test is under tests/; the JSON result is a local ignored artifact.")
	return "\n".join(lines) + "\n"

func _format_metric(metric: Dictionary) -> String:
	if metric.is_empty() or not metric.has("median_ms"):
		return "NOT MEASURED"
	return "median %.3f ms (min %.3f, max %.3f; n=%d)" % [
		float(metric.get("median_ms", -1.0)),
		float(metric.get("min_ms", -1.0)),
		float(metric.get("max_ms", -1.0)),
		int(metric.get("iterations", 0)),
	]


func _format_bytes(value: int) -> String:
	if value < 1024:
		return "%d B" % value
	if value < 1024 * 1024:
		return "%.1f KiB" % (float(value) / 1024.0)
	return "%.2f MiB" % (float(value) / 1048576.0)


func _print_summary(payload: Dictionary) -> void:
	print("WWO WORLD DATA PERFORMANCE BASELINE — BATCH 1")
	print("Benchmark JSON: %s" % _json_output_path)
	print("Benchmark Markdown: %s" % _markdown_output_path)
	var loads: Dictionary = payload.get("load_benchmark", {}) as Dictionary
	print("PrototypeV2Data.load_all() runtime-set load: %s" % _format_metric(loads.get("full_world_data_load", {}) as Dictionary))
	var maps: Dictionary = payload.get("map_benchmark", {}) as Dictionary
	print("Canvas geometry/index setup: %s" % _format_metric(maps.get("canvas_setup_geometry_and_index", {}) as Dictionary))
	var lookup: Dictionary = maps.get("representative_lookup", {}) as Dictionary
	print("Representative lookup: %s" % _format_metric(lookup))
	for item: Dictionary in payload.get("synthetic_scaling", []) as Array:
		print("Synthetic %dx: parse %s; index %s; lookup %s" % [
			int(item.get("scale", 0)),
			_format_metric(item.get("parse", {}) as Dictionary),
			_format_metric(item.get("index_build", {}) as Dictionary),
			_format_metric(item.get("lookup", {}) as Dictionary),
		])


func _write_text(path: String, content: String) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var parent: String = absolute_path.get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write benchmark output: %s" % path)
		return false
	file.store_string(content)
	file.close()
	return true
