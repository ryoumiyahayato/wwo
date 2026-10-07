extends RefCounted
## One concrete person. Requests cannot supply their own actor/rank/scope.
var _service: RefCounted
var _person_id: String

func configure(service: RefCounted, person_id: String) -> bool:
	if _service != null or not service._people.has(person_id):
		return false
	_service = service
	_person_id = person_id
	return true

func apply(request: Dictionary) -> Dictionary:
	if _service == null:
		return {"ok": false, "error": "not_configured"}
	return _service.submit(_person_id, request)
