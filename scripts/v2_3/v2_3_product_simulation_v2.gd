class_name V23ProductSimulationV2
extends V23ProductSimulation
## Product composition using the completed social-sandbox coordinator.


func initialize(simulation_clock: SimulationClock = null) -> bool:
	social_sandbox = V23SocialSandboxServiceV2.new()
	(social_sandbox as V23SocialSandboxServiceV2).attach_product(self)
	return super.initialize(simulation_clock)
