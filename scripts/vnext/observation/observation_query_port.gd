class_name VNextObservationQueryPort
extends RefCounted

const CONTRACT = preload("res://scripts/vnext/observation/observation_contract.gd")
const REQUEST = preload("res://scripts/vnext/observation/observation_request.gd")
const RESPONSE = preload("res://scripts/vnext/observation/observation_response.gd")


## Consumers depend on this port rather than on a world owner. Implementations
## must return a detached response or an explicit fail-closed status.
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
