extends RefCounted
## One person's acquisition/decision port. No BattleState/snapshot interface.
var _service: RefCounted
var _person: String = ""

func configure(service: RefCounted, person: String) -> bool:
	if _service != null or not service._roles.has(person):
		return false
	_service = service
	_person = person
	return true

func knowledge(before: int = -1) -> Dictionary:
	return _service.knowledge(_person, "", "", "", 64, before)

func inbox() -> Dictionary:
	return _service.inbox(_person)

func outbox() -> Dictionary:
	return _service.outbox(_person)

func observe(request: Dictionary) -> Dictionary:
	return _service.observe(_person, request)

func send_report(request: Dictionary) -> Dictionary:
	return _service.send_report(_person, request)

func issue_command(request: Dictionary) -> Dictionary:
	return _service.issue_command(_person, request)
