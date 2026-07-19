class_name AlphaUiBinding
extends RefCounted
## Read-only Alpha presentation plus commands routed to authoritative services.

signal view_changed

const OBJECT_KINDS: Array[String] = [
	"person",
	"location",
	"enterprise",
	"organization",
	"job",
	"contract",
	"lender",
	"good",
	"asset",
]

var simulation: AlphaSimulationService
var save_service := AlphaSaveService.new()
var migration := AlphaSaveMigration.new()
var developer_mode: bool = false
var last_result: Dictionary = {}
var _command_sequence: int = 1


func _init(
	target: AlphaSimulationService, enable_developer_mode: bool = false
) -> void:
	simulation = target
	developer_mode = enable_developer_mode
	if simulation != null and not simulation.state_changed.is_connected(
		_on_state_changed
	):
		simulation.state_changed.connect(_on_state_changed)


func world_header() -> Dictionary:
	if simulation == null:
		return {}
	var player: CharacterData = simulation.player_character()
	return {
		"datetime": V2DateTime.iso_from_total_hour(
			simulation.clock.total_hours
		),
		"paused": simulation.clock.is_paused,
		"speed": simulation.clock.speed_multiplier,
		"player_name": "" if player == null else player.name,
		"cash_centimes": (
			0 if player == null
			else simulation.economy.ledger.owner_cash(player.id)
		),
		"debt_centimes": (
			0 if player == null
			else simulation.economy.total_debt(player.id)
		),
		"region_id": "" if player == null else player.region_id,
		"intent": simulation.current_intent.duplicate(true),
		"counts": simulation.alpha_counts(),
	}


func object_list(kind: String, filter_text: String = "") -> Array[Dictionary]:
	if simulation == null or kind not in OBJECT_KINDS:
		return []
	var result: Array[Dictionary] = []
	match kind:
		"person":
			for person_id: String in simulation.roster.get_active_ids():
				var character: CharacterData = simulation.roster.get_active(person_id)
				result.append({
					"id": person_id,
					"label": character.name,
					"secondary": "%s · %s" % [
						character.occupation, character.region_id,
					],
				})
			for person_id: String in simulation.roster.get_background_ids():
				var background: BackgroundCharacterData = (
					simulation.roster.get_background(person_id)
				)
				result.append({
					"id": person_id,
					"label": background.name,
					"secondary": "%s · 背景" % background.region_id,
				})
		"location":
			for raw_location: Variant in simulation.world.locations.values():
				var location: Dictionary = raw_location as Dictionary
				result.append({
					"id": str(location.get("location_id", "")),
					"label": str(location.get("display_name", "")),
					"secondary": str(location.get("location_type", "")),
				})
		"enterprise":
			for raw_state: Variant in simulation.enterprise.enterprises.values():
				var state: Dictionary = raw_state as Dictionary
				result.append({
					"id": str(state.get("organization_id", "")),
					"label": str(state.get("name", "")),
					"secondary": "%s · 风险 %d" % [
						str(state.get("status", "")),
						int(state.get("distress", 0)),
					],
				})
		"organization":
			for organization_id: String in (
				simulation.organization_service.get_organization_ids()
			):
				var organization: OrganizationData = (
					simulation.organization_service.get_organization(
						organization_id
					)
				)
				result.append({
					"id": organization_id,
					"label": organization.name,
					"secondary": "%s · %s" % [
						organization.type, organization.region_id,
					],
				})
		"job":
			for raw_job: Variant in simulation.labor.jobs.values():
				var job: Dictionary = raw_job as Dictionary
				result.append({
					"id": str(job.get("job_id", "")),
					"label": str(job.get("name", "")),
					"secondary": "%d 生丁/周 · %s" % [
						int(job.get("wage", 0)),
						str(job.get("city_id", "")),
					],
				})
		"contract":
			for raw_contract: Variant in simulation.economy.contracts.contracts.values():
				var contract: Dictionary = raw_contract as Dictionary
				result.append({
					"id": str(contract.get("contract_id", "")),
					"label": "%s合同" % str(contract.get("contract_type", "")),
					"secondary": "%s · 余额 %d" % [
						str(contract.get("status", "")),
						simulation.economy.contracts.outstanding(
							str(contract.get("contract_id", ""))
						),
					],
				})
		"lender":
			for lender_id: String in AlphaEconomyService.CREDIT_LENDER_IDS:
				result.append({
					"id": lender_id,
					"label": lender_id.get_slice(":", 1),
					"secondary": "信贷对象",
				})
		"good":
			for raw_good: Variant in simulation.economy.goods.values():
				var good: Dictionary = raw_good as Dictionary
				result.append({
					"id": str(good.get("good_id", "")),
					"label": str(good.get("name", "")),
					"secondary": str(good.get("kind", "")),
				})
		"asset":
			for raw_asset: Variant in simulation.economy.assets.assets.values():
				var asset: Dictionary = raw_asset as Dictionary
				result.append({
					"id": str(asset.get("asset_id", "")),
					"label": "%s · %s" % [
						str(asset.get("asset_type", "")),
						str(asset.get("asset_id", "")),
					],
					"secondary": "价值 %d · 控制 %s" % [
						int(asset.get("value_centimes", 0)),
						str(asset.get("controller_id", "")),
					],
				})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	if not filter_text.is_empty():
		var filtered: Array[Dictionary] = []
		for item: Dictionary in result:
			if (
				filter_text.to_lower() in str(item.get("label", "")).to_lower()
				or filter_text.to_lower() in str(item.get("secondary", "")).to_lower()
			):
				filtered.append(item)
		return filtered
	return result


func object_detail(kind: String, object_id: String) -> Dictionary:
	match kind:
		"person":
			var active: CharacterData = simulation.roster.get_active(object_id)
			if active != null:
				var view: Dictionary = simulation.character_service.public_character_view(
					active, developer_mode
				)
				view["cash_centimes"] = simulation.economy.ledger.owner_cash(
					active.id
				)
				view["debt_centimes"] = simulation.economy.total_debt(active.id)
				view["known_information_scope"] = "本人公开与已知状态"
				return view
			var background: BackgroundCharacterData = (
				simulation.roster.get_background(object_id)
			)
			if background != null:
				return background.to_dict()
		"location":
			return (
				simulation.world.locations.get(object_id, {}) as Dictionary
			).duplicate(true)
		"enterprise":
			var state: Dictionary = (
				simulation.enterprise.enterprises.get(object_id, {}) as Dictionary
			).duplicate(true)
			state["cash_centimes"] = simulation.economy.ledger.owner_cash(object_id)
			state["debt_centimes"] = simulation.economy.total_debt(object_id)
			return state
		"organization":
			var organization: OrganizationData = (
				simulation.organization_service.get_organization(object_id)
			)
			if organization != null:
				var detail: Dictionary = organization.to_dict()
				detail["alpha_state"] = (
					simulation.politics.organization_states.get(
						object_id, {}
					) as Dictionary
				).duplicate(true)
				return detail
		"job":
			return (
				simulation.labor.jobs.get(object_id, {}) as Dictionary
			).duplicate(true)
		"contract":
			return (
				simulation.economy.contracts.contracts.get(
					object_id, {}
				) as Dictionary
			).duplicate(true)
		"lender":
			return (
				simulation.economy.entity_profiles.get(
					object_id, {}
				) as Dictionary
			).duplicate(true)
		"good":
			var good: Dictionary = (
				simulation.economy.goods.get(object_id, {}) as Dictionary
			).duplicate(true)
			var prices: Dictionary = {}
			for raw_region_id: Variant in simulation.economy.markets:
				var region_id: String = str(raw_region_id)
				prices[region_id] = simulation.economy.market_price(
					region_id, object_id
				)
			good["regional_prices"] = prices
			return good
		"asset":
			return (
				simulation.economy.assets.assets.get(object_id, {}) as Dictionary
			).duplicate(true)
	return {}


func available_actions(kind: String, object_id: String) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	match kind:
		"person":
			actions.append(_action("person.contact", "接触并提高精度"))
			if object_id == simulation.roster.player_character_id:
				actions.append(_action("person.develop", "安排个人发展"))
		"location":
			actions.append(_action("location.travel", "前往此地点"))
		"enterprise":
			actions.append(_action("enterprise.inspect", "设为详细结算"))
			actions.append(_action("enterprise.buy", "购买企业权益"))
			actions.append(_action("enterprise.create", "在当前地区建立企业"))
		"organization":
			actions.append(_action("organization.join", "加入组织"))
			actions.append(_action("organization.leave", "退出组织"))
			actions.append(_action("organization.contest", "争取负责人职位"))
			actions.append(_action("organization.policy", "提出并执行政策"))
			actions.append(_action("organization.corrupt", "进行利益输送"))
		"job":
			actions.append(_action("job.apply", "申请此工作"))
			actions.append(_action("job.resign", "辞去当前工作"))
		"contract":
			actions.append(_action("contract.repay", "偿还债务"))
			actions.append(_action("contract.restructure", "请求债务重组"))
		"lender":
			actions.append(_action("lender.borrow", "申请个人借款"))
		"good":
			actions.append(_action("good.trade", "购买并运输一单位"))
		"asset":
			actions.append(_action("asset.sell", "出售本人权益"))
	return actions


func execute_action(
	action_id: String, object_id: String, parameters: Dictionary = {}
) -> Dictionary:
	if simulation == null or simulation.player_character() == null:
		return _finish(_failure("simulation_unavailable", "Alpha 世界不可用"))
	var player: CharacterData = simulation.player_character()
	var key: String = "ui:%d:%s" % [_command_sequence, action_id]
	_command_sequence += 1
	var hour: int = simulation.clock.total_hours
	var result: Dictionary
	match action_id:
		"person.contact":
			result = _boolean_result(
				simulation.promote_for_contact(object_id, "玩家直接接触"),
				"人物已进入高精度层",
				"人物无法提高精度"
			)
		"person.develop":
			result = simulation.character_service.schedule_development(
				key,
				player,
				str(parameters.get("skill_id", "finance")),
				str(parameters.get("method", "independent_study")),
				hour + 1,
				int(parameters.get("hours", 24)),
				int(parameters.get("cost_centimes", 0)),
				str(player.current_status.get(
					"home_location_id", "location:dawnharbor:home"
				)),
				AlphaEnterpriseService.AGGREGATE_MARKET_ID,
				"",
				50,
				35
			)
		"location.travel":
			result = _v2_result(simulation.request_travel(
				player.id, object_id, "fastest"
			))
		"enterprise.inspect":
			result = _boolean_result(
				simulation.mark_enterprise_detailed(object_id, true),
				"企业进入详细结算",
				"企业不存在"
			)
		"enterprise.create":
			var cash: int = simulation.economy.ledger.owner_cash(player.id)
			result = simulation.enterprise.create_enterprise(
				key,
				player.id,
				str(parameters.get("name", "新设地区商社")),
				str(parameters.get("structure", "retail_trade")),
				player.region_id,
				str(player.current_status.get("city_id", "city:dawnharbor")),
				str(parameters.get("product_id", "household_goods")),
				str(parameters.get("input_id", "grain")),
				mini(int(parameters.get("capital_centimes", 1200)), cash),
				hour
			)
		"enterprise.buy":
			result = _buy_enterprise(key, object_id, player.id, hour)
		"organization.join":
			result = simulation.politics.join_organization(
				key, player, object_id, hour
			)
		"organization.leave":
			result = simulation.politics.leave_organization(
				key, player, object_id, hour
			)
		"organization.contest":
			result = _contest_leader(key, player, object_id, hour)
		"organization.policy":
			result = _start_first_policy(key, player, object_id, hour)
		"organization.corrupt":
			result = simulation.politics.perform_corruption(
				key,
				"corruption:accept_benefit",
				player,
				object_id,
				AlphaEnterpriseService.AGGREGATE_MARKET_ID,
				100,
				hour,
				[simulation.roster.get_active_ids(false)[0]]
			)
		"job.apply":
			result = _apply_job(key, player, object_id, hour)
		"job.resign":
			result = _resign_current_job(key, player.id, hour)
		"contract.repay":
			result = simulation.economy.repay_loan(
				key,
				object_id,
				hour,
				int(parameters.get("amount_centimes", 500))
			)
		"contract.restructure":
			result = simulation.economy.restructure_loan(
				key, object_id, hour, 60, 1700
			)
		"lender.borrow":
			result = _apply_credit(key, player, object_id, hour)
		"good.trade":
			result = _trade_good(key, player, object_id, hour)
		"asset.sell":
			result = _sell_asset(key, player.id, object_id, hour)
		_:
			result = _failure("unknown_action", "未知行为入口")
	return _finish(result)


func set_pause(paused: bool) -> void:
	simulation.clock.set_paused(paused)
	view_changed.emit()


func set_speed(multiplier: int) -> bool:
	var changed: bool = simulation.clock.set_speed(multiplier)
	view_changed.emit()
	return changed


func advance_hours(hours: int) -> void:
	simulation.advance_hours(maxi(0, hours))
	view_changed.emit()


func save_review() -> Dictionary:
	var saved: SaveOperationResult = save_service.save(simulation)
	return _finish(
		_success("进度已保存：%s" % saved.path)
		if saved.success
		else _failure(saved.error_code, saved.message)
	)


func load_review() -> Dictionary:
	var loaded: SaveOperationResult = save_service.load()
	if not loaded.success:
		return _finish(_failure(loaded.error_code, loaded.message))
	var restored: SaveOperationResult = save_service.restore(
		loaded.snapshot, simulation
	)
	return _finish(
		_success("Alpha 进度已载入")
		if restored.success
		else _failure(restored.error_code, restored.message)
	)


func migrate_v2_3_review() -> Dictionary:
	var migrated: SaveOperationResult = migration.migrate_v2_3_file()
	if not migrated.success:
		return _finish(_failure(migrated.error_code, migrated.message))
	return load_review()


func developer_command(command: String) -> Dictionary:
	if not developer_mode:
		return _finish(_failure("developer_mode_required", "开发模式未开启"))
	var player: CharacterData = simulation.player_character()
	var hour: int = simulation.clock.total_hours
	var key: String = "dev:%d:%s" % [_command_sequence, command]
	_command_sequence += 1
	var parts: PackedStringArray = command.strip_edges().split(" ", false)
	var verb: String = parts[0] if not parts.is_empty() else ""
	var result: Dictionary
	match verb:
		"hour":
			advance_hours(int(parts[1]) if parts.size() > 1 else 24)
			result = _success("时间已跳转")
		"cash":
			var amount: int = int(parts[1]) if parts.size() > 1 else 5000
			result = simulation.economy.ledger.post(
				key,
				hour,
				"developer_injection",
				"fact:%s" % key,
				[
					{
						"account_id": AlphaLedgerService.SYSTEM_OPENING_ACCOUNT,
						"delta_centimes": -amount,
					},
					{
						"account_id": simulation.economy.ledger.cash_account_id(
							player.id
						),
						"delta_centimes": amount,
					},
				],
				"开发模式资金注入"
			)
		"skill":
			var skill_id: String = parts[1] if parts.size() > 1 else "finance"
			var level: int = int(parts[2]) if parts.size() > 2 else 80
			player.skills[skill_id] = clampi(level, 0, 100)
			result = _success("技能已修改")
		"aptitude":
			var aptitude_id: String = parts[1] if parts.size() > 1 else "reasoning"
			var aptitude: int = int(parts[2]) if parts.size() > 2 else 80
			player.hidden_aptitudes[aptitude_id] = clampi(aptitude, 0, 100)
			result = _success("资质已修改")
		"debt":
			result = _apply_credit(
				key,
				player,
				"organization:loran_public_credit"
				if player.country_id == "country:loran_federation"
				else "organization:vesta_public_credit",
				hour
			)
		"enterprise":
			result = execute_action("enterprise.create", "", {
				"name": "开发模式企业",
				"capital_centimes": 1000,
			})
		"price":
			result = simulation.economy.apply_market_shock(
				key,
				player.region_id,
				parts[1] if parts.size() > 1 else "grain",
				int(parts[2]) if parts.size() > 2 else 1000,
				30,
				"开发模式外部事件",
				hour
			)
		"truth":
			result = _v2_result(simulation.set_truth_view(
				not simulation.truth_view
			))
		"preset":
			var preset_id: String = (
				parts[1]
				if parts.size() > 1
				else AlphaSimulationService.DEFAULT_REVIEW_STATE_ID
			)
			result = simulation.apply_review_state(preset_id)
		"takeover":
			result = simulation.apply_review_state(
				"enterprise_near_bankruptcy"
			)
		"order":
			result = _trigger_enterprise_order(key, player, hour)
		"wage":
			var wage_delta: int = int(parts[1]) if parts.size() > 1 else 5
			result = _apply_wage_change(wage_delta)
		"policy":
			result = simulation.apply_review_state("policy_changed_region")
		"corruption":
			result = _quick_corruption(key, player, hour)
		_:
			result = _failure(
				"unknown_developer_command",
				"可用命令：hour、cash、skill、aptitude、debt、enterprise、takeover、order、price、wage、policy、corruption、preset、truth"
			)
	return _finish(result)


func _trigger_enterprise_order(
	key: String, player: CharacterData, hour: int
) -> Dictionary:
	var enterprise_id: String = ""
	for raw_id: Variant in simulation.detailed_enterprise_ids:
		var candidate_id: String = str(raw_id)
		var state: Dictionary = simulation.enterprise.enterprises.get(
			candidate_id, {}
		) as Dictionary
		if str(state.get("controller_id", "")) == player.id:
			enterprise_id = candidate_id
			break
	if enterprise_id.is_empty():
		return _failure(
			"controlled_enterprise_missing",
			"需要先创建或接管企业"
		)
	return simulation.enterprise.accept_order(
		key,
		enterprise_id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		2,
		player.region_id,
		hour,
		1
	)


func _apply_wage_change(delta: int) -> Dictionary:
	var player: CharacterData = simulation.player_character()
	var region: Dictionary = simulation.world.regions.get(
		player.region_id, {}
	) as Dictionary
	if region.is_empty():
		return _failure("region_missing", "当前地区不存在")
	region["wage_index"] = maxi(
		1, int(region.get("wage_index", 0)) + delta
	)
	simulation.world.regions[player.region_id] = region
	return _success("地区工资指数已改变", {
		"wage_index": region["wage_index"],
	})


func _quick_corruption(
	key: String, player: CharacterData, hour: int
) -> Dictionary:
	var prepared: Dictionary = simulation.apply_review_state("local_official")
	if not bool(prepared.get("success", false)):
		return prepared
	var witness_ids: Array[String] = simulation.roster.get_active_ids(false)
	if witness_ids.is_empty():
		return _failure("witness_missing", "腐败场景需要知情者")
	return simulation.politics.perform_corruption(
		key,
		"corruption:steer_contract",
		player,
		"organization:loran_commerce_registry",
		"organization:loran_dawnbay_trade",
		600,
		hour,
		[witness_ids[0]]
	)


func _apply_job(
	key: String, player: CharacterData, job_id: String, hour: int
) -> Dictionary:
	var applied: Dictionary = simulation.labor.apply_for_job(
		"%s:apply" % key, player.id, job_id, hour
	)
	if not bool(applied.get("success", false)):
		return applied
	var application_id: String = str(
		((applied.get("data", {}) as Dictionary).get(
			"application", {}
		) as Dictionary).get("application_id", "")
	)
	var decided: Dictionary = simulation.labor.employer_decide(
		"%s:decide" % key, application_id, hour, 60
	)
	if not bool(decided.get("success", false)):
		return decided
	var application: Dictionary = (
		decided.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	if str(application.get("status", "")) == "rejected":
		return decided
	return simulation.labor.accept_job_offer(
		"%s:accept" % key, application_id, hour
	)


func _resign_current_job(
	key: String, person_id: String, hour: int
) -> Dictionary:
	var profile: Dictionary = simulation.labor.person_profiles.get(
		person_id, {}
	) as Dictionary
	for raw_id: Variant in profile.get("employment_contract_ids", []) as Array:
		var contract_id: String = str(raw_id)
		var state: Dictionary = simulation.labor.employment_states.get(
			contract_id, {}
		) as Dictionary
		if str(state.get("status", "")) in AlphaLaborService.ACTIVE_EMPLOYMENT_STATUSES:
			return simulation.labor.resign(key, contract_id, hour)
	return _failure("no_active_employment", "当前没有可辞去的工作")


func _apply_credit(
	key: String, player: CharacterData, lender_id: String, hour: int
) -> Dictionary:
	var applied: Dictionary = simulation.economy.apply_for_loan(
		"%s:apply" % key,
		player.id,
		lender_id,
		"credit:personal_unsecured",
		2500,
		hour,
		[],
		[],
		{
			"existing_debt_centimes": simulation.economy.total_debt(player.id),
		}
	)
	if not bool(applied.get("success", false)):
		return applied
	var application_id: String = str(
		((applied.get("data", {}) as Dictionary).get(
			"application", {}
		) as Dictionary).get("application_id", "")
	)
	var reviewed: Dictionary = simulation.economy.review_application(
		"%s:review" % key, application_id, hour
	)
	if not bool(reviewed.get("success", false)):
		return reviewed
	var application: Dictionary = (
		reviewed.get("data", {}) as Dictionary
	).get("application", {}) as Dictionary
	if str(application.get("status", "")) != "offered":
		return reviewed
	return simulation.economy.accept_loan_offer(
		"%s:accept" % key, application_id, hour
	)


func _buy_enterprise(
	key: String, organization_id: String, buyer_id: String, hour: int
) -> Dictionary:
	var state: Dictionary = simulation.enterprise.enterprises.get(
		organization_id, {}
	) as Dictionary
	var equity_id: String = str(state.get("equity_asset_id", ""))
	var asset: Dictionary = simulation.economy.assets.assets.get(
		equity_id, {}
	) as Dictionary
	var shares: Dictionary = asset.get("owner_shares_bp", {}) as Dictionary
	var seller_id: String = ""
	for raw_owner_id: Variant in shares:
		if int(shares[raw_owner_id]) >= 5100:
			seller_id = str(raw_owner_id)
			break
	if seller_id.is_empty() or seller_id == buyer_id:
		return _failure("enterprise_share_unavailable", "没有可购买的控制性权益")
	var price: int = maxi(1, int(asset.get("value_centimes", 0)) * 51 / 100)
	return simulation.enterprise.purchase_enterprise_share(
		key, organization_id, seller_id, buyer_id, 5100, price, hour
	)


func _contest_leader(
	key: String,
	player: CharacterData,
	organization_id: String,
	hour: int
) -> Dictionary:
	var organization: OrganizationData = (
		simulation.organization_service.get_organization(organization_id)
	)
	if organization == null:
		return _failure("organization_missing", "组织不存在")
	return simulation.politics.contest_position(
		key,
		player,
		organization_id,
		str(organization.position_structure.get("leader_position", "")),
		hour
	)


func _start_first_policy(
	key: String,
	player: CharacterData,
	organization_id: String,
	hour: int
) -> Dictionary:
	var organization: OrganizationData = (
		simulation.organization_service.get_organization(organization_id)
	)
	if organization == null:
		return _failure("organization_missing", "组织不存在")
	for raw_policy: Variant in simulation.politics.policies.values():
		var policy: Dictionary = raw_policy as Dictionary
		if str(policy.get("country_id", "")) != organization.country_id:
			continue
		var proposed: Dictionary = simulation.politics.propose_policy(
			"%s:propose" % key,
			player,
			organization_id,
			str(policy.get("policy_id", "")),
			[organization.region_id],
			hour
		)
		if not bool(proposed.get("success", false)):
			return proposed
		var implementation_id: String = str(
			((proposed.get("data", {}) as Dictionary).get(
				"implementation", {}
			) as Dictionary).get("implementation_id", "")
		)
		return simulation.politics.fund_and_start_policy(
			"%s:fund" % key, implementation_id, hour
		)
	return _failure("policy_missing", "该国没有可实施政策")


func _trade_good(
	key: String, player: CharacterData, good_id: String, hour: int
) -> Dictionary:
	var trade: Dictionary = simulation.economy.create_trade(
		"%s:create" % key,
		player.id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		good_id,
		1,
		player.region_id,
		player.region_id,
		hour,
		0
	)
	if not bool(trade.get("success", false)):
		return trade
	var contract_id: String = str(
		((trade.get("data", {}) as Dictionary).get(
			"contract", {}
		) as Dictionary).get("contract_id", "")
	)
	return simulation.economy.settle_trade(
		"%s:settle" % key, contract_id, hour
	)


func _sell_asset(
	key: String, player_id: String, asset_id: String, hour: int
) -> Dictionary:
	var share_bp: int = simulation.economy.assets.owner_share(
		asset_id, player_id
	)
	if share_bp <= 0:
		return _failure("asset_not_owned", "本人不拥有该资产权益")
	var price: int = simulation.economy.assets.value(asset_id) * share_bp / 10000
	return simulation.economy.assets.sell(
		key,
		hour,
		asset_id,
		player_id,
		AlphaEnterpriseService.AGGREGATE_MARKET_ID,
		price,
		share_bp
	)


func _finish(result: Dictionary) -> Dictionary:
	last_result = result.duplicate(true)
	view_changed.emit()
	return result


func _on_state_changed(_change_set: Dictionary) -> void:
	view_changed.emit()


static func _action(action_id: String, label: String) -> Dictionary:
	return {"action_id": action_id, "label": label}


static func _success(message: String, data: Dictionary = {}) -> Dictionary:
	return {"success": true, "code": "ok", "message": message, "data": data}


static func _failure(code: String, message: String) -> Dictionary:
	return {"success": false, "code": code, "message": message, "data": {}}


static func _boolean_result(
	success: bool, success_message: String, failure_message: String
) -> Dictionary:
	return (
		_success(success_message)
		if success else _failure("action_failed", failure_message)
	)


static func _v2_result(result: V2LifeLoopResult) -> Dictionary:
	return {
		"success": result.success,
		"code": result.error_code if not result.success else "ok",
		"message": result.user_message,
		"data": result.data.duplicate(true),
	}
