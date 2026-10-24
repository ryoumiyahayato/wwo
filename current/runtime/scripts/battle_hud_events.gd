extends RefCounted
## Two fixed channels. Repeated events merge; no queue/backlog, no raw enemy damage data.
const LIFETIME_MS := 3200
var channels: Dictionary = {}
func clear() -> void: channels.clear()
func push(channel: String, text: String, now: int) -> void:
	var previous: Dictionary = channels.get(channel, {})
	var count := int(previous.get("count",0))+1 if str(previous.get("text",""))==text and now<int(previous.get("until",0)) else 1
	channels[channel] = {"text":text,"count":count,"until":now+LIFETIME_MS}
func lines(now: int) -> Array[String]:
	var result: Array[String] = []
	for key in ["incoming","shot"]:
		var item: Dictionary = channels.get(key,{})
		if now>=int(item.get("until",0)): continue
		result.append(str(item.text)+( " ×%d"%int(item.count) if int(item.count)>1 else ""))
	return result
static func shot_text(kind: String, visible_contact: bool) -> String:
	var label: String = {"mg":"机枪已射击","smoke":"烟弹已发射","rocket":"火箭已发射","mortar":"迫击炮已发射","infantry":"单兵武器已射击"}.get(kind,"主炮已射击")
	return label+(" · 可见弹着" if visible_contact and kind!="smoke" else "")

static func impact_side(entry: String) -> String:
	# Only the struck surface on the player's own vehicle; never the hidden shooter.
	return {"front":"前部受击","rear":"后部受击","left":"左侧受击","right":"右侧受击","track_left":"左履带受击","track_right":"右履带受击","turret_front":"炮塔前部受击","turret_rear":"炮塔后部受击","turret_left":"炮塔左侧受击","turret_right":"炮塔右侧受击","top":"顶部受击","turret_top":"炮塔顶部受击"}.get(entry,"车体受击")
