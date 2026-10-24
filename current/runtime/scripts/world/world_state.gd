class_name WorldState
extends RefCounted
## Installed world component references only. Each referenced owner keeps its own facts.
## Static evidence/views describe this world; no UI, IO, scheduling or build metadata.

var game_clock: GameClock
var provenance: HistoricalProvenanceFoundation
var historical_evidence: HistoricalPoliticalEvidenceCatalog
var political_registry: RuntimePoliticalEntityRegistry
var historical_evidence_view: HistoricalPoliticalEvidenceView
var political_registry_view: RuntimePoliticalEntityView
var economic_evidence: FormalWorldEconomicEvidenceCatalog
var economic_static_view: FormalWorldEconomicStaticView
var population_input_view: FormalWorldPopulationInputView
var population_state: FormalWorldPopulationState
var market_registry: FormalWorldMarketRegistry
var market_registry_view: FormalWorldMarketView
var economy_state: FormalWorldEconomyState
var spatial_catalog: VNextSpatialCatalog
var spatial_world: VNextSpatialWorld
var territory_state: TerritoryState
var person_overlay: VNextNamedPersonOverlay
var person_travel: FormalPersonTravel
var player_state: VNextPlayerState
var ledger_state: FormalLedgerState
var personal_economy_state: FormalPersonalEconomyState
var economy_r1: EconomyR1Slice
var native_economy_error: String = ""
var organization_state: OrganizationState
var organization_evidence: FormalWorldOrganizationEvidenceCatalog
var organization_evidence_view: FormalWorldOrganizationEvidenceView
var organization_responsibility: FormalWorldOrganizationResponsibilityService
var authorization_check: AuthorizationCheck
var military_map: VNextMilitaryMapAdapter
var military_state: VNextMilitaryState
var military_service: VNextMilitaryService
