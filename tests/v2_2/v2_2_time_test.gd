extends SceneTree
## Pause, speed and frame-chunk-independent fixed-hour time semantics.

var test := V2TestCase.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var first := V2LifeLoopSimulation.new()
	var second := V2LifeLoopSimulation.new()
	test.expect(first.initialize() and second.initialize(), "两条确定性时间路径可初始化")
	var initial_hour: int = first.clock.total_hours
	first.advance_real_seconds(8.0)
	test.equal(first.clock.total_hours, initial_hour, "暂停时现实时间不推进")
	first.clock.set_paused(false)
	first.clock.set_speed(1)
	test.equal(first.advance_real_seconds(0.5), 0, "不足1现实秒不结算小时")
	test.equal(first.advance_real_seconds(0.5), 1, "1×累计1现实秒推进1小时")
	first.clock.set_speed(2)
	test.equal(first.advance_real_seconds(1.0), 2, "2×每现实秒推进2小时")
	first.clock.set_speed(4)
	test.equal(first.advance_real_seconds(1.0), 4, "4×每现实秒推进4小时")
	first.clock.set_speed(8)
	test.equal(first.advance_real_seconds(1.0), 8, "8×每现实秒推进8小时")
	second.clock.set_paused(false)
	second.clock.set_speed(8)
	for _index: int in range(10):
		second.advance_real_seconds(0.125)
	var third := V2LifeLoopSimulation.new()
	third.initialize()
	third.clock.set_paused(false)
	third.clock.set_speed(8)
	third.advance_real_seconds(1.25)
	test.equal(second.clock.total_hours, third.clock.total_hours, "不同现实帧分块产生相同权威时间")
	test.equal(second.deterministic_digest(), third.deterministic_digest(), "不同帧分块逐小时结算结果相同")
	test.expect(second.processed_idempotency_keys.has("hour:%s" % V2DateTime.iso_from_total_hour(initial_hour + 9)), "多小时累计没有跳过中间小时")
	test.finish(self, "V2.2 time")
