extends RefCounted
## The caller cannot select or impersonate another person in a command payload.
var _service: RefCounted
var _person: String = ""

func configure(service: RefCounted, person: String) -> bool:
	if _service != null or not service._structure._people.has(person):
		return false
	_service = service
	_person = person
	return true

func submit(command: Dictionary) -> Dictionary:
	return _service.submit(_person, command) if _service != null else {"ok": false, "error": "unbound_person"}
