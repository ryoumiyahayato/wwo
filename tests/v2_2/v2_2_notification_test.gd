extends SceneTree
## Notification aggregation, read state and persistence regression.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var service := V2NotificationService.new()
	service.configure(16)

	var first: Dictionary = service.add(
		"personal",
		"notification",
		"食品不足",
		"皮埃尔住户食品不足",
		V2DateTime.total_hour_from_iso("1900-03-12T06:00:00"),
		"food_shortage:household_pierre",
		["character_pierre_lefevre"]
	)
	test.equal(service.notifications.size(), 1, "第一条通知写入历史")
	test.equal(service.unread_count(), 1, "新通知默认为未读")

	service.add(
		"personal",
		"notification",
		"食品不足",
		"皮埃尔住户食品仍然不足",
		V2DateTime.total_hour_from_iso("1900-03-12T08:00:00"),
		"food_shortage:household_pierre",
		["household:pierre"]
	)
	test.equal(service.notifications.size(), 1, "同日同聚合键不会刷出第二条通知")
	var aggregated: Dictionary = service.notifications[0]
	test.equal(int(aggregated.get("group_count", 0)), 2, "聚合计数增加")
	test.expect(
		(aggregated.get("affected_entity_ids", []) as Array).has("household:pierre"),
		"聚合通知合并新关联对象"
	)

	test.expect(
		service.mark_read(str(first.get("notification_id", ""))),
		"可以按通知 ID 标记已读"
	)
	test.equal(service.unread_count(), 0, "单条标记后未读归零")
	test.expect(
		not service.mark_read(str(first.get("notification_id", ""))),
		"重复标记已读不伪装成状态变化"
	)

	service.add(
		"organization",
		"event",
		"工会例会",
		"星期三晚间例会已安排",
		V2DateTime.total_hour_from_iso("1900-03-13T19:00:00"),
		"union_meeting:week_11",
		["union_metalworkers_nord"]
	)
	service.add(
		"personal",
		"event",
		"工资到账",
		"本周工资已到账",
		V2DateTime.total_hour_from_iso("1900-03-17T18:00:00"),
		"wage:week_11",
		["character_pierre_lefevre"]
	)
	test.equal(service.unread_count(), 2, "不同通知分别保持未读")
	test.equal(service.mark_all_read(), 2, "打开通知中心可以一次标记全部可见通知")
	test.equal(service.unread_count(), 0, "全部标记后未读归零")
	test.equal(service.mark_all_read(), 0, "无未读时不会产生虚假变更")

	var snapshot: Dictionary = service.get_persistent_state()
	var restored := V2NotificationService.new()
	test.expect(restored.restore_persistent_state(snapshot), "通知状态可以恢复")
	test.equal(restored.unread_count(), 0, "载入后保持已读状态")
	test.equal(restored.notifications.size(), service.notifications.size(), "载入后历史数量一致")

	var corrupt: Dictionary = snapshot.duplicate(true)
	(corrupt["notifications"] as Array)[0]["affected_entity_ids"] = "broken"
	var rejected := V2NotificationService.new()
	test.expect(not rejected.restore_persistent_state(corrupt), "损坏的关联对象列表会被拒绝")

	var bounded := V2NotificationService.new()
	bounded.configure(16)
	for index: int in range(24):
		bounded.add(
			"personal", "notification", "记录 %d" % index, "",
			V2DateTime.total_hour_from_iso("1900-03-12T00:00:00") + index * 24,
			"unique:%d" % index, []
		)
	test.equal(bounded.notifications.size(), 16, "通知历史遵守最小上限并裁剪旧记录")
	test.equal(
		str((bounded.notifications[0] as Dictionary).get("title", "")),
		"记录 8",
		"裁剪时保留最新记录"
	)

	test.finish(self, "V2.2 notification")
