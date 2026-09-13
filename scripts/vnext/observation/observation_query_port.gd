class_name VNextObservationQueryPort
extends RefCounted

const CONTRACT = preload("res://scripts/vnext/observation/observation_contract.gd")


## Consumers depend on this port rather than on an owner. The base port is
## deliberately non-functional and returns an explicit fail-closed result.
func query(request: VNextObservationRequest) -> VNextObservationResponse:
	var observer_actor_id: String = ""
	if request != null:
		observer_actor_id = request.observer_actor_id()
	return VNextObservationResponse.failure(
		CONTRACT.STATUS_QUERY_UNAVAILABLE,
		observer_actor_id,
		CONTRACT.UNSPECIFIED_WORLD_REVISION,
		0,
		"query_port_not_implemented",
		true
	)
