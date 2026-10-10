extends SceneTree
## Headless observation driver. All outcomes are projections of the shared kernel.
const Scenario = preload("res://experiments/war_resolver/gameplay/scenario.gd")
const F = preload("res://experiments/war_resolver/gameplay/fixtures.gd")

func _initialize() -> void:
	var args: Dictionary = {"scene": "S1", "seed": "71", "variant": "valid", "actor": "", "quota": "0", "seconds": "1800", "output": "", "inputs": ""}
	for value: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = value.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2 or not args.has(pair[0]):
			push_error("Expected --scene/seed/variant/actor/quota/seconds/output/inputs=value")
			quit(2)
			return
		args[pair[0]] = pair[1]
	if not str(args.seed).is_valid_int() or not str(args.quota).is_valid_int() or int(args.quota) not in [0, 1, 7, 31] or not str(args.seconds).is_valid_float() or float(args.seconds) < 0.0 or float(args.seconds) > 86400.0:
		push_error("Invalid seed, quota or seconds (0..86400)")
		quit(2)
		return
	var options: Dictionary = {"variant": args.variant}
	if not str(args.inputs).is_empty():
		var inputs: Variant = JSON.parse_string(FileAccess.get_file_as_string(args.inputs))
		if not inputs is Dictionary:
			push_error("Input file must map existing actor IDs to finite intent entries")
			quit(2)
			return
		options.inputs = inputs
	var scenario: Scenario = Scenario.new()
	if not scenario.configure(args.scene, int(args.seed), options):
		push_error("Scenario or input admission failed")
		quit(2)
		return
	var actor: String = str(args.actor) if not str(args.actor).is_empty() else ("soldier" if args.scene == "S3" else ("platoon" if args.scene == "S2" else "squad"))
	if not scenario.env.people.has(actor):
		push_error("Actor is not an existing person in this scene")
		scenario.dispose()
		quit(2)
		return
	var result: Dictionary = scenario.advance(float(args.seconds), int(args.quota))
	if not result.ok or not scenario.balanced():
		push_error("Scenario blocked or conservation failed: " + JSON.stringify(result))
		scenario.dispose()
		quit(1)
		return
	var world: Dictionary = scenario.physical()
	world.view = "DEBUG_TRUTH"
	var person: Dictionary = _timeline(scenario, actor)
	var truth: Dictionary = scenario.observation.truth()
	var summary: String = summary_zh(scenario, actor, person)
	var output_started: int = Time.get_ticks_usec()
	if not str(args.output).is_empty():
		var output: String = ProjectSettings.globalize_path(str(args.output))
		if DirAccess.make_dir_recursive_absolute(output) != OK:
			push_error("Output directory unavailable")
			quit(2)
			return
		_write(output.path_join("world_result.json"), JSON.stringify(world))
		_write(output.path_join("person_timeline.json"), JSON.stringify(person))
		_write(output.path_join("debug_truth.json"), JSON.stringify(truth))
		_write(output.path_join("summary_zh.txt"), summary)
	scenario.costs.output_ms = (Time.get_ticks_usec() - output_started) / 1000.0
	print(summary)
	print("GAMEPLAY_DEMO=" + JSON.stringify({"scene": args.scene, "seed": int(args.seed), "variant": args.variant, "actor": actor,
		"time": world.time, "quota": int(args.quota), "role": scenario.env.people[actor].role, "balanced": true, "costs": scenario.costs,
		"world_counters": world.world_counters, "gameplay_work": world.gameplay_work, "personal_work": world.personal_work,
		"visible_events": person.records.size(), "truth_events": truth.records.size(), "dropped": truth.dropped, "output": args.output}))
	scenario.dispose()
	quit(0)

static func _write(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(content + "\n")

static func _timeline(scenario: Scenario, actor: String) -> Dictionary:
	var result: Dictionary = scenario.observation.person(actor)
	var records: Array = result.records
	var offset: int = records.size()
	while offset < int(result.total):
		var page: Dictionary = scenario.observation.person(actor, offset)
		records.append_array(page.records)
		offset += page.records.size()
	result.records = records
	return result

static func summary_zh(scenario: Scenario, actor: String, person: Dictionary) -> String:
	var env: Dictionary = scenario.env
	var mission: Dictionary = F.current(env)
	var unit: Dictionary = env.state.units.unit_000
	var lines: Array[String] = ["场景%s；seed %d；推进%.3f游戏秒。" % [scenario.name, env.state.seed, env.state.time],
		"人物视图：%s（%s）。聚焦只读取该人物的已有知识与反馈。" % [actor, env.people[actor].role]]
	var knowledge: Dictionary = env.information.knowledge(actor)
	lines.append("已收到%d条信息；可见时间线%d条。" % [knowledge.total_matching, person.records.size()])
	for record: Dictionary in person.records:
		if record.kind == "person_intent" and record.detail.proposal.intent.kind != "keep":
			lines.append("%.3f秒提交%s；当时已有信息引用%s；权限结果%s。" % [record.effective_time, record.detail.proposal.intent.kind,
				JSON.stringify(record.detail.known_claim_refs), JSON.stringify(record.detail.result.get("creation_validation", {}))])
		elif record.kind == "command_feedback":
			lines.append("%.3f秒送达反馈：%s；原因%s。" % [record.effective_time, record.detail.status, JSON.stringify(record.detail.outcome)])
		elif record.kind == "personal_action_finished":
			lines.append("%.3f秒本人局部动作完成：%s。" % [record.effective_time, record.detail.state])
	lines.append("研究视图 DEBUG_TRUTH：下列数据不得传给玩家provider。")
	lines.append("主班位置%s；移动%.6fkm；任务%s。抵达=%s；局部目标条件=%s；有效敌方作用=%s。" % [JSON.stringify(env.space.xy(unit)),
		unit.distance_moved, mission.status, mission.goal_v1.route_complete, mission.goal_v1.local_condition, mission.goal_v1.effective_incoming_contact])
	lines.append("原班剩余能力%.6f；累计损失%.6f；弹药%.6f；耗弹%.6f。" % [unit.effective, unit.casualties, unit.ammunition, unit.ammo_spent])
	if env.gameplay.participants._units.has("soldier"):
		var member: Dictionary = env.gameplay.participants.view("soldier")
		lines.append("已有成员soldier：伤病能力余量%.6f；伤病量%.6f；可行动=%s；状态%s。该份额计入原班。" % [member.health, member.injury, member.actionable, member.state])
	lines.append("执行原因%s；终止原因%s；远处仍有%d个聚合表示；资源账守恒=%s。" % [str(mission.goal_v1.reason), str(mission.goal_v1.get("terminal_reason", "未终止")), env.lod._groups.size(), scenario.balanced()])
	return "\n".join(lines)
