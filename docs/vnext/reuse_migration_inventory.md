# vNext reuse and migration inventory

## Audit boundary

- `FIXED_BASE`: `392519512def63caf07151cd741ddd82949aea7c`
- Audit branch: `docs/vnext-reuse-migration-map-20260807`
- vNext foundation checked at `FIXED_BASE`: `scripts/vnext/world_runtime.gd`, `tests/vnext/world_runtime_test.gd`, `docs/vnext/runtime_foundation.md`, `.github/workflows/vnext-runtime.yml`.
- Current product entry checked at `FIXED_BASE`: `project.godot` points to `res://scenes/formal/formal_world_menu.tscn`; `tests/formal/formal_world_integration_test.gd` and `tests/v2_3/v2_3_player_interface_test.gd` confirm the live product is the formal hemisphere backed by `FormalWorldApplication` and `FormalWorldSimulation`.
- This inventory classifies concrete components, data assets and retained tests. It does not classify whole Alpha, V2 or V2.3 directories.
- No migration is implemented by this document.

## Classification totals

| Classification | Count |
| --- | ---: |
| `REUSE_DIRECT` | 3 |
| `REUSE_WITH_ADAPTER` | 19 |
| `DATA_ONLY` | 3 |
| `TEST_ONLY` | 4 |
| `REFERENCE_ONLY` | 7 |
| `DELETE_AFTER_REPLACEMENT` | 4 |
| **Total inspected components / asset groups / test groups** | **40** |

## Component inventory

### 1. V2DateTime

- **component:** `V2DateTime` Gregorian conversion utility.
- **exact repository path:** `scripts/v2_2/v2_datetime.gd`.
- **current owner:** Stateless utility; it owns no simulation clock.
- **current product reachability:** Reachable indirectly from the formal time path and retained services; `tests/variable_state/formal_time_stable_contract_test.gd` exercises it against formal time.
- **classification:** `REUSE_DIRECT`.
- **reason:** The implementation is pure conversion logic. It neither advances time nor stores a second writable time source, so direct reuse does not violate `VNextWorldRuntime` time ownership.
- **reusable behavior:** Gregorian leap-year/month handling, hour-to-date/date-to-hour conversion, ISO/display conversion and stable calendar round-trips from the 1900 epoch.
- **state currently owned:** None.
- **dependency risks:** Callers may incorrectly treat converted `total_hour` values as a new clock or write them back into another time owner.
- **vNext integration condition:** All input hours/minutes must be derived from the single vNext runtime owner; the utility remains read-only/pure.
- **forbidden direct dependency:** No service may instantiate a second clock merely because it uses `V2DateTime`; `VNextWorldRuntime` must never depend on legacy `SimulationClock` ownership.
- **useful existing tests:** `tests/variable_state/formal_time_stable_contract_test.gd`, `tests/vnext/world_runtime_test.gd`.
- **deletion condition:** Not applicable; retained as shared stateless infrastructure.
- **code evidence:** `from_total_hour`, `to_total_hour`, `iso_from_total_hour` and related functions are static conversions and the file has no mutable clock member.

### 2. AtomicJsonFileStore

- **component:** `AtomicJsonFileStore`.
- **exact repository path:** `scripts/save/atomic_json_file_store.gd`.
- **current owner:** Generic file durability helper; it owns no business snapshot schema.
- **current product reachability:** Live formal saves call it through `FormalWorldSimulation`; Alpha save regression also exercises the same durability pattern.
- **classification:** `REUSE_DIRECT`.
- **reason:** Its contract is snapshot bytes plus a verifier callback; it does not own world state, IDs, time or player facts.
- **reusable behavior:** Verified temporary write, flush, backup rotation, atomic promotion and rollback/cleanup on verification or rename failure.
- **state currently owned:** Only temporary local variables and suffix constants `.tmp` / `.bak`; no persistent business state.
- **dependency risks:** Passing a verifier that mutates the live runtime would break the intended persistence boundary even though the store itself is generic.
- **vNext integration condition:** vNext persistence supplies a pure snapshot verifier and keeps `snapshot()` / `restore()` in the runtime boundary rather than moving disk logic into `scripts/vnext/world_runtime.gd`.
- **forbidden direct dependency:** Business services must not call the store to persist their private partial state independently of the vNext snapshot owner.
- **useful existing tests:** `tests/formal/formal_world_integration_test.gd`, `tests/alpha/alpha_save_and_migration_test.gd`, `tests/variable_state/formal_time_stable_contract_test.gd`.
- **deletion condition:** Not applicable; retained as generic durability infrastructure.
- **code evidence:** `write_verified()` writes a temporary file, invokes the supplied verifier, rotates the previous primary to backup and restores it when promotion fails.

### 3. SaveOperationResult

- **component:** `SaveOperationResult`.
- **exact repository path:** `scripts/save/save_operation_result.gd`.
- **current owner:** Generic persistence result value object.
- **current product reachability:** Returned by live formal save/load paths and used by retained Alpha save tests.
- **classification:** `REUSE_DIRECT`.
- **reason:** It is a small result DTO and does not contain a service locator, mutable context or hidden business authority.
- **reusable behavior:** Uniform success/failure reporting with error code, message, path and optional snapshot.
- **state currently owned:** Per-operation result fields only.
- **dependency risks:** The optional snapshot must remain a boundary payload, not become a shared mutable dictionary handed around as application context.
- **vNext integration condition:** Use it only at persistence/API boundaries; duplicate or treat snapshot payloads immutably at ownership boundaries.
- **forbidden direct dependency:** No vNext service may use `SaveOperationResult.snapshot` as a mutable global state bus.
- **useful existing tests:** `tests/formal/formal_world_integration_test.gd`, `tests/alpha/alpha_save_and_migration_test.gd`.
- **deletion condition:** Not applicable.
- **code evidence:** The class only exposes result fields plus static success/failure constructors; it has no singleton or service references.

### 4. FormalWorldSimulation

- **component:** Current formal world composition/time root.
- **exact repository path:** `scripts/formal/formal_world_simulation.gd`.
- **current owner:** Live formal product owner for `total_minutes`, minute remainder, formal economy instance and formal save schema.
- **current product reachability:** Directly live; `FormalWorldApplication` constructs it and formal product tests instantiate it.
- **classification:** `DELETE_AFTER_REPLACEMENT`.
- **reason:** It owns the exact second writable time authority that vNext foundation forbids. Keeping it as a dependency under `VNextWorldRuntime` would create two runtime roots.
- **reusable behavior:** Transactional state validation before commit, derived date-time queries, economy hour projection, atomic save/recovery behavior and compact composition-root query surface are useful design references.
- **state currently owned:** `total_minutes`, `_minute_remainder`, initialization state, `FormalWorldEconomyService`, formal persistent state and save path.
- **dependency risks:** Parallel time ownership, parallel snapshot schema, and accidental nesting of the legacy formal composition root inside vNext.
- **vNext integration condition:** Move needed behaviors behind vNext-owned time/snapshot/economy interfaces; no vNext service may retain the class as an authority.
- **forbidden direct dependency:** `VNextWorldRuntime -> FormalWorldSimulation` and any synchronization loop between their clocks.
- **useful existing tests:** `tests/formal/formal_world_integration_test.gd`, `tests/variable_state/formal_time_stable_contract_test.gd`.
- **deletion condition:** Delete after the vNext product composition root owns time, formal economy access, snapshot/restore and the product no longer instantiates `FormalWorldSimulation`.
- **code evidence:** The class mutates `total_minutes` in `advance_minutes()`, derives `_minute_remainder`, injects economy hour from its own time and implements its own formal save/restore schema.

### 5. FormalWorldEconomyService

- **component:** Formal 1900 world economy runtime.
- **exact repository path:** `scripts/formal/formal_world_economy_service.gd`.
- **current owner:** Live formal economy owner for country economic states, polity/economy crosswalks, routes, shipments and bounded history.
- **current product reachability:** Directly live through `FormalWorldSimulation.economy`.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** The service already accepts an injected authoritative hour source and has transactional restore, so the economic algorithm is worth retaining. Its API, dictionary schemas, Alpha historical-data loader and current owner are not yet vNext contracts.
- **reusable behavior:** 50-economy/151-polity mapping, daily settlement, non-negative inventory rules, sparse shipment settlement, source-gated calibration, deterministic polity queries and transactional restore validation.
- **state currently owned:** `country_states`, polity records and indexes, economy/polity crosswalks, routes, shipments, history and day-settlement bookkeeping.
- **dependency risks:** Legacy economy IDs differ from political map IDs; one economy can map to multiple polities; raw dictionaries can leak private state; current instance is owned by `FormalWorldSimulation`.
- **vNext integration condition:** Put the service behind a vNext economy port, inject time derived solely from `VNextWorldRuntime`, normalize IDs through the vNext catalog, and expose copies/query DTOs instead of private dictionaries.
- **forbidden direct dependency:** No vNext code may read/write `country_states`, shipment arrays or crosswalk dictionaries directly, and no adapter may depend on `FormalWorldSimulation` for time.
- **useful existing tests:** `tests/formal/formal_world_integration_test.gd`, `tests/alpha/alpha_historical_world_economy_data_test.gd`, `tests/variable_state/formal_time_stable_contract_test.gd`.
- **deletion condition:** Not applicable while used through an adapter; the adapter can later be removed only if a native vNext economy replaces the implementation.
- **code evidence:** The service exposes `set_authoritative_hour_source()`, derives `total_hour` from that callable, validates settlement against the injected hour, loads official polity/crosswalk data and commits restored state only after candidate validation.

### 6. Authoritative 1900 political map dataset

- **component:** Source-backed 1900 political units, CShapes geometry and explicit major-economy crosswalk.
- **exact repository path:** `data/world_map/historical/political_units_1900.json`; `data/world_map/historical/cshapes_1900_snapshot.json`; `data/world_map/historical/major_economy_polity_crosswalk_1900.json`.
- **current owner:** Repository data assets; currently consumed by formal economy and formal hemisphere UI layers.
- **current product reachability:** Directly live in the formal hemisphere and formal economy mapping.
- **classification:** `DATA_ONLY`.
- **reason:** The historical records should survive, but the current UI/runtime loaders should not define vNext ownership. The data has explicit snapshot date, geometry provider and crosswalk policy.
- **reusable behavior:** Not applicable as executable behavior; retain political unit IDs, controller/status records, dated geometry references, capital metadata and explicit one-to-many economy mapping exceptions.
- **state currently owned:** Static source data only; `political_units_1900.json` declares 151 units and the CShapes snapshot declares 151 geometry features.
- **dependency risks:** `cshapes_1900_snapshot.json` records CShapes 2.0 as `CC BY-NC-SA 4.0` with `commercial_use_allowed: false`; licensing must be resolved before commercial distribution. Economy IDs are not identical to polity IDs.
- **vNext integration condition:** Load through a vNext static catalog/data boundary, preserve dated provenance and explicit crosswalks, and complete licensing review before any commercial release decision.
- **forbidden direct dependency:** UI code must not become the owner of political identity or mutate these records into business truth; no array index may replace stable polity IDs.
- **useful existing tests:** `tests/formal/formal_world_integration_test.gd`, `tests/v2_3/v2_3_player_interface_test.gd`.
- **deletion condition:** Not applicable; retained data subject to licensing and provenance requirements.
- **code evidence:** The political-unit file declares `unit_count: 151`; the CShapes snapshot declares `feature_count: 151` and source/license metadata; the crosswalk explicitly states that economy count is not polity count and permits one economy to cover multiple map units.

### 7. Prototype modern-polygon 1900 aggregation

- **component:** Earlier approximate historical political entity mapping.
- **exact repository path:** `data/world_map/historical_political_entities_1900.json`.
- **current owner:** Legacy holographic prototype data layer.
- **current product reachability:** Superseded by the source-backed CShapes historical evidence layer for the formal product; retained in the repository for older UI history code.
- **classification:** `REFERENCE_ONLY`.
- **reason:** The file explicitly marks itself `prototype_only: true` and states that it aggregates modern Natural Earth polygons into approximate 1900 entities rather than providing point-verified 1900 boundaries.
- **reusable behavior:** Historical naming/relationship ideas can be consulted when comparing old UI behavior, but the records must not be imported as vNext political truth.
- **state currently owned:** Static approximate mappings and display metadata.
- **dependency risks:** Modern geometry can be mistaken for historical GIS; fallback provisional entities can silently become false 1900 truth.
- **vNext integration condition:** None as a runtime dependency. Any useful labels must be independently reconciled against the authoritative dated catalog before use.
- **forbidden direct dependency:** vNext catalog, economy, map or UI must not read this file as authoritative political geometry or identity.
- **useful existing tests:** `tests/v2_3/v2_3_player_interface_test.gd` indirectly guards the current source-backed formal product rather than this prototype dataset.
- **deletion condition:** Not applicable to this inventory; it may be removed separately once no historical comparison/regression path needs it.
- **code evidence:** Its own `approximation_notice` says modern polygons are aggregated to approximate 1900 entities and that complex borders/colonies require later historical GIS replacement.

### 8. 1900 historical economy calibration data

- **component:** Source-gated world economy, household budget, transport and coverage calibration data.
- **exact repository path:** `data/alpha/historical_world_economy_1900.json`; `data/alpha/historical_world_economy_1900/countries_compact.json`; `data/alpha/historical_household_budgets_1900.json`; `data/alpha/historical_transport_network_1900.json`; `data/alpha/historical_economy_coverage_1900.json`.
- **current owner:** Repository calibration assets loaded by `AlphaHistoricalWorldEconomyData` and consumed by the live formal economy.
- **current product reachability:** Directly live through `FormalWorldEconomyService`.
- **classification:** `DATA_ONLY`.
- **reason:** The source/estimate records are reusable assets, while vNext should not inherit Alpha as the service owner. The files already distinguish observations, bounded estimates, coverage gaps and formal-admission flags.
- **reusable behavior:** Not executable behavior; retain 50-economy calibration rows, confidence intervals, ports/infrastructure, household templates, sparse transport topology and explicit data-coverage policy.
- **state currently owned:** Static 1900 calibration records and provenance/coverage metadata.
- **dependency risks:** Some dimensions are bounded estimates or `source_required`; transport data explicitly is not exact track geometry; IDs require reconciliation with the stable polity catalog.
- **vNext integration condition:** Import through a vNext catalog/calibration reader that preserves confidence/provenance/status fields and rejects records disallowed for formal simulation.
- **forbidden direct dependency:** No vNext business service may treat a missing numeric dimension as zero/default or use Alpha service state as the canonical data store.
- **useful existing tests:** `tests/alpha/alpha_historical_world_economy_data_test.gd`, `tests/formal/formal_world_integration_test.gd`.
- **deletion condition:** Not applicable; retained as data.
- **code evidence:** The compact table includes `formal_simulation_allowed`; the coverage file says numeric defaults are forbidden and unverified records must not enter formal simulation; transport declares `not_exact_track_geometry: true`.

### 9. 1900 commodity catalog

- **component:** Commodity-market calibration catalog.
- **exact repository path:** `data/alpha/commodity_market_1900.json`.
- **current owner:** Repository data asset; live formal economy reads the commodity definitions.
- **current product reachability:** Directly live; formal integration checks the full commodity catalog is present.
- **classification:** `DATA_ONLY`.
- **reason:** Commodity identities, calibration policies and source notes are useful data; the Alpha commodity service implementation is not required to retain the catalog.
- **reusable behavior:** Not executable behavior; retain commodity IDs, units, baseline prices, spoilage/stock/liquidity parameters and historical/source notes.
- **state currently owned:** Static commodity definitions and calibration policies.
- **dependency risks:** Values are game calibrations constrained by historical sources, not universal historical truth; stable commodity IDs must be registered rather than inferred from array order/display names.
- **vNext integration condition:** Load into the vNext static catalog with schema validation and provenance preserved.
- **forbidden direct dependency:** UI or economy code must not use commodity array indexes or Chinese display names as persistent IDs.
- **useful existing tests:** `tests/formal/formal_world_integration_test.gd`, `tests/alpha/alpha_historical_world_economy_data_test.gd`.
- **deletion condition:** Not applicable.
- **code evidence:** The file declares `schema_id: alpha_commodity_market_1900_v1`, `calibration_year: 1900`, a calibration-notice field, source groups and stable `commodity_id` records.

### 10. SpatialLocationService

- **component:** V2.3 person spatial location service.
- **exact repository path:** `scripts/v2_3/spatial_location_service.gd`.
- **current owner:** Retained V2.3 owner for person positions plus known-location indexes.
- **current product reachability:** Not in the formal main composition; explicitly retained and executed by `tools/run_validation.ps1`.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** The transit state machine and location authority are useful, but the service mixes actual position with cognition, uses V2.3 dictionaries/IDs/time strings and is owned by the retired V2.3 composition root.
- **reusable behavior:** At-location/in-transit/waiting transitions, route-segment arrival boundaries, interruption recovery, stable position queries and location visibility filtering.
- **state currently owned:** Location catalog/indexes, person positions and known-location IDs.
- **dependency risks:** Position truth and knowledge truth can become coupled; legacy location IDs may not satisfy the vNext catalog; callers can force-set positions.
- **vNext integration condition:** Make vNext spatial authority explicit, map all location/person IDs through stable catalogs, pass vNext-derived time, and separate knowledge grants from physical position mutations.
- **forbidden direct dependency:** No vNext caller may directly mutate `person_positions`/known-location dictionaries or use `force_set_at_location()` as normal gameplay authority.
- **useful existing tests:** `tests/v2_3/v2_3_location_test.gd`, `tests/v2_3/v2_3_travel_execution_test.gd`, `tests/v2_3/v2_3_schedule_integration_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** The service owns both `person_positions` and `known_location_ids` and exposes explicit begin-transit/wait/complete/interrupt transitions with persistent-state restore.

### 11. RoutePlannerService

- **component:** V2.3 route planner.
- **exact repository path:** `scripts/v2_3/route_planner_service.gd`.
- **current owner:** Retained V2.3 route-query/cache owner.
- **current product reachability:** Not in formal main; retained runner executes its regression.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Deterministic cognition-limited route search is reusable, but it directly depends on legacy travel graph/location APIs and includes person/time/cash/fatigue in legacy cache keys.
- **reusable behavior:** Fastest/cheapest search, stable tie-breaking, cognition-limited graph traversal, affordability/fatigue filtering, cache reuse and explainable alternatives on failure.
- **state currently owned:** Route cache and hit/miss counters; route graph/location references are dependencies.
- **dependency risks:** Cache validity depends on authoritative knowledge, position, money and time; using stale cache input can expose omniscient or unaffordable routes.
- **vNext integration condition:** Supply read-only vNext route graph, knowledge, spatial and economic query ports; cache keys must use stable IDs and an explicit revision/time contract.
- **forbidden direct dependency:** Planner must not read mutable internal dictionaries from location/knowledge/economy services.
- **useful existing tests:** `tests/v2_3/v2_3_route_planner_test.gd`, `tests/v2_3/v2_3_location_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** Route tests prove known-destination gating, deterministic repeated `path_key`, cache hits, fastest/cheapest divergence and explicit `unknown_location` / `no_affordable_route` failures.

### 12. TravelExecutionService

- **component:** V2.3 travel execution and settlement service.
- **exact repository path:** `scripts/v2_3/travel_execution_service.gd`.
- **current owner:** Retained V2.3 owner of travel plans, plan sequencing and travel-settlement idempotency.
- **current product reachability:** Not in formal main; retained runner executes it.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Segment-boundary and idempotent settlement logic are valuable, but the implementation calls legacy schedule, household, ledger, condition and spatial services and generates V2.3-specific IDs.
- **reusable behavior:** Plan creation, wait/travel block scheduling, per-segment completion, one-time fare settlement, arrival-boundary position mutation and idempotent repeated settlement.
- **state currently owned:** Travel plans, sequence counters and processed-settlement keys.
- **dependency risks:** Cross-service writes can partially commit; `travel_plan:v2_3:*` IDs are not vNext catalog IDs; household cash and location ownership are external authorities.
- **vNext integration condition:** Wrap settlement in a vNext command/transaction boundary, allocate stable IDs through the vNext ID contract and invoke schedule/economy/spatial owners only through public ports.
- **forbidden direct dependency:** No direct access to household/ledger/location internal members and no direct use of legacy clock or V2.3 plan-ID generation.
- **useful existing tests:** `tests/v2_3/v2_3_travel_execution_test.gd`, `tests/v2_3/v2_3_schedule_integration_test.gd`, `tests/v2_3/v2_3_route_planner_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** The travel regression proves actual position changes only at segment arrival, transport cash is posted exactly once and a repeated settlement remains idempotent.

### 13. V2ScheduleService

- **component:** Retained schedule owner.
- **exact repository path:** `scripts/v2_2/v2_schedule_service.gd`.
- **current owner:** V2/V2.3 primary activity-by-person/hour schedule authority.
- **current product reachability:** Not in formal main; retained V2.3 composition and regressions still execute it.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Single primary activity and conflict/reservation behavior are reusable, but schedule generation is tied to old people/employment/time and V2DateTime assumptions.
- **reusable behavior:** Person schedule indexing, source priority, activity conflict checks, bounded completed history, cancellation and deterministic reservation semantics.
- **state currently owned:** Schedules, recent completed activities, generation/source-priority state.
- **dependency risks:** Schedule can be mistaken for actual location/attendance truth; old fixed-commute assumptions still exist in migration history.
- **vNext integration condition:** Time comes from vNext only; activities use stable person/location/action IDs; actual attendance remains validated against spatial authority rather than schedule text.
- **forbidden direct dependency:** No UI or service may treat a scheduled activity as proof that a person is physically present or that an economic action settled.
- **useful existing tests:** `tests/v2_3/v2_3_schedule_integration_test.gd`, `tests/v2_3/v2_3_appointment_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** Schedule integration verifies formal route blocks replace fixed future commutes, travel metadata retains stable associations and actual location—not schedule alone—determines work attendance.

### 14. CommunicationService

- **component:** V2.3 delayed communication service.
- **exact repository path:** `scripts/v2_3/communication_service.gd`.
- **current owner:** Retained owner for messages, inbox/outbox indexes, delivery queue/notices and communication idempotency.
- **current product reachability:** Not in formal main; retained runner executes it.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Delivery/read separation and knowledge transfer are reusable, but sending/replying is coupled to legacy spatial, relationship, knowledge, household and ledger services.
- **reusable behavior:** Delayed delivery boundary, unread-after-delivery state, explicit read, reply linkage, postage charging, per-message idempotency and knowledge transfer on read.
- **state currently owned:** Message records, inbox/outbox, delivery queue, notices, channel/people config and processed keys.
- **dependency risks:** Reading a message mutates knowledge; sending may mutate cash; old message IDs/time strings and direct service calls can create partial cross-owner commits.
- **vNext integration condition:** Use vNext stable IDs and time, route economic charges/knowledge effects through transaction/command ports, and keep message payloads immutable after settlement except controlled status transitions.
- **forbidden direct dependency:** Communication must not mutate knowledge/ledger/household internal dictionaries or use UI-read state as world truth.
- **useful existing tests:** `tests/v2_3/v2_3_communication_test.gd`, `tests/v2_3/v2_3_appointment_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** The communication regression proves delivery occurs exactly at the expected hour, delivered messages remain unread, facts enter recipient knowledge only after read and repeated delivery does not duplicate the original message.

### 15. KnowledgeService

- **component:** V2.3 person-scoped knowledge service.
- **exact repository path:** `scripts/v2_3/knowledge_service.gd`.
- **current owner:** Retained owner for knowledge records, person/subject indexes, contradictions, expiry and idempotency.
- **current product reachability:** Not in formal main; retained runner executes it.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Provenance/confidence/contradiction semantics are strong and should survive, but record IDs, time representation and dictionary API need vNext contracts.
- **reusable behavior:** Person-isolated facts, provenance/source metadata, confidence, contradiction linking, expiry/freshness, subject queries and idempotent recording.
- **state currently owned:** Knowledge records and indexes, processed keys, sequence/rules.
- **dependency risks:** Knowledge IDs and subject IDs must share stable domains; callers can accidentally expose omniscient records by bypassing person-scoped queries.
- **vNext integration condition:** Use stable person/subject/event IDs, vNext-derived timestamps and read-only query DTOs; objective event truth remains a separate owner.
- **forbidden direct dependency:** UI/AI must not read the raw global records dictionary to bypass per-person knowledge visibility.
- **useful existing tests:** `tests/v2_3/v2_3_knowledge_test.gd`, `tests/v2_3/v2_3_communication_test.gd`, `tests/v2_3/v2_3_social_sandbox_test_base.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** The knowledge regression proves provenance/confidence storage, idempotent duplicate rejection, bidirectional contradiction state and time-bound expiry while retaining old facts.

### 16. V23RelationshipService

- **component:** V2.3 directed dynamic relationship service.
- **exact repository path:** `scripts/v2_3/relationship_service.gd`.
- **current owner:** Retained owner for directed relationship dimensions, histories, pair index and idempotency.
- **current product reachability:** Not in formal main; retained runner executes it.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Causal multi-dimensional relationship updates are useful, but cooldown/time and contact visibility depend on legacy time/knowledge APIs and V2.3 IDs.
- **reusable behavior:** Six-dimensional relationship state, causal interaction history, idempotent settlement, contact cooldown and knowledge-limited contact candidates.
- **state currently owned:** Directed relationship records, pair indexes, histories and processed interaction keys.
- **dependency risks:** Pair direction and identity domains must stay stable; contact availability depends on separate knowledge truth; raw histories can grow or be mutated by callers if leaked.
- **vNext integration condition:** Normalize person IDs, consume vNext time and knowledge query ports, and expose mutation only as relationship commands carrying cause event IDs.
- **forbidden direct dependency:** No caller may modify relationship dictionaries or synthesize relationship changes from UI state without a causal event/command.
- **useful existing tests:** `tests/v2_3/v2_3_relationship_test.gd`, `tests/v2_3/v2_3_appointment_test.gd`, `tests/v2_3/v2_3_social_sandbox_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** The relationship regression verifies all six dimensions, a causal interaction-history entry, idempotent duplicate settlement and relationship-time cooldown.

### 17. Legacy RelationshipService

- **component:** Older core sparse relationship service.
- **exact repository path:** `scripts/relationship/relationship_service.gd`.
- **current owner:** Legacy `SocietySimulationService` relationship owner.
- **current product reachability:** Not in the formal product composition; exercised by legacy `tests/test_runner.gd`.
- **classification:** `REFERENCE_ONLY`.
- **reason:** A newer retained V2.3 relationship service already has richer causal/idempotent behavior. The older implementation mutates relationship ID lists on character/background records, crossing the character owner boundary.
- **reusable behavior:** Sparse-pair indexing and legacy society relationship behavior can be consulted when preserving old regression intent.
- **state currently owned:** Legacy relationship records and sparse indexes; it also updates relationship references on character records.
- **dependency risks:** Direct mutation of `CharacterData` / background character relationship fields, legacy StableIdService semantics and duplicate relationship authority if used beside V23/vNext relationships.
- **vNext integration condition:** None as a dependency; only behavior that is not already covered by the selected vNext relationship contract should be re-specified independently.
- **forbidden direct dependency:** vNext relationship code must not depend on this service or maintain both legacy and V23 relationship authorities.
- **useful existing tests:** `tests/test_runner.gd`.
- **deletion condition:** Not applicable to this inventory; remove later only after retained legacy regressions no longer need it.
- **code evidence:** The service creates/updates sparse relationships through `StableIdService` and writes relationship IDs back into supplied character/background records rather than owning only its domain state.

### 18. V23SocialAppointmentService

- **component:** V2.3 appointment coordination service.
- **exact repository path:** `scripts/v2_3/social_appointment_service.gd`.
- **current owner:** Retained owner for invitations/appointments, response state, scheduled activity references and idempotency.
- **current product reachability:** Not in formal main; retained runner executes it.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Invitation/read/reservation/attendance semantics are reusable, but the implementation coordinates multiple legacy services directly and uses old time/ID formats.
- **reusable behavior:** Delayed invitation, explicit acceptance, two-party atomic schedule reservation, actual co-location attendance, missed appointment outcome and causal relationship effect.
- **state currently owned:** Appointment records, invitation message/activity references and processed keys.
- **dependency risks:** Schedule, communication, spatial and relationship changes must commit consistently; the appointment must not infer attendance from schedule alone.
- **vNext integration condition:** Use a vNext orchestration transaction/command boundary with stable appointment/message/activity IDs and vNext time; query actual spatial authority at settlement.
- **forbidden direct dependency:** No direct mutation of schedule/relationship/message internals and no UI acceptance flag as attendance truth.
- **useful existing tests:** `tests/v2_3/v2_3_appointment_test.gd`, `tests/v2_3/v2_3_communication_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** The appointment regression requires the invite to be delivered and read, reserves both schedules, marks attended only when both people are actually co-located, and lowers trust for a missed appointment.

### 19. SpatialNpcRoutineService

- **component:** Event-driven NPC spatial routine planner.
- **exact repository path:** `scripts/v2_3/spatial_npc_routine_service.gd`.
- **current owner:** Retained owner for NPC plans, planning triggers and queued-message consumption.
- **current product reachability:** Not in formal main; retained runner executes it.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Event-driven bounded planning is the desired shape, but planning is tied to legacy schedule/location/time and V2.3 person records.
- **reusable behavior:** Reason-gated replanning, day/event boundaries rather than per-frame scanning, deduplicated message queue and bounded plan state.
- **state currently owned:** NPC plans, planning counters/reasons, message queues and persistent planning metadata.
- **dependency risks:** A second NPC planner could duplicate schedule/location authority; unsupported reasons must not trigger broad scans.
- **vNext integration condition:** Feed explicit vNext events/time and read-only schedule/spatial queries; emit intents/commands rather than directly owning downstream facts.
- **forbidden direct dependency:** No `_process`/`_physics_process` world scans and no direct write into spatial/schedule dictionaries.
- **useful existing tests:** `tests/v2_3/v2_3_npc_test.gd`, `tests/alpha/alpha_fixture_retained_services_performance_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** The NPC regression shows unsupported reasons do not plan, duplicate messages are consumed once and 48 hours cause bounded event/day replanning rather than per-hour/per-frame full scans.

### 20. V2.3 social sandbox service stack

- **component:** Social sandbox V1/V2/V3 coordination layers.
- **exact repository path:** `scripts/v2_3/v2_3_social_sandbox_service.gd`; `scripts/v2_3/v2_3_social_sandbox_service_v2.gd`; `scripts/v2_3/v2_3_social_sandbox_service_v3.gd`.
- **current owner:** Retained social coordinator. V1 owns derived situations/goals/intents/tasks/event ledger/commitments/evidence/reactions; V2/V3 add product reservation and travel behavior.
- **current product reachability:** Not in the formal main product; retained social regressions execute the stack through V2.3 product fixtures.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** The prepare/conflict/commit, stable-goal, bounded-ledger and player/NPC common-task mechanics are valuable. The layers depend on V2/V2.3 service classes, `V2DateTime`, a retained product object and legacy player/travel authorization paths.
- **reusable behavior:** Derived situations with provenance, stable goals, unified player/NPC intents/tasks, declared conflict keys, per-action atomic rollback, bounded event/reaction state, commitments and explicit travel/schedule reservation.
- **state currently owned:** Social derived state, tasks/intents/events/commitments/evidence/reactions, sequence counters, last processed hour and controlled-person ID.
- **dependency risks:** V2 attaches `_product` and calls product travel APIs; V3 temporarily snapshots/restores travel reservations for preview; the coordinator knows many concrete legacy service types.
- **vNext integration condition:** Keep the coordinator domain but replace concrete services with vNext query/command ports, derive time only from vNext, use catalog IDs, and make atomic commit a real multi-owner transaction boundary.
- **forbidden direct dependency:** No dependency on `V23ProductSimulation`, V2 household/ledger/employment classes, legacy clock, or mutable downstream service dictionaries.
- **useful existing tests:** `tests/v2_3/v2_3_social_sandbox_test.gd`, `tests/v2_3/v2_3_social_sandbox_test_base.gd`, `tests/alpha/alpha_fixture_retained_services_performance_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** V1 explicitly says it does not own clock/cash/location/relationship/knowledge/schedule/org but stores derived social state; V2 attaches a product and performs route/reservation work; V3 routes preview and submit through the same travel reservation path and controls explicit player leave authorization.

### 21. V23LifeLoopSimulation

- **component:** Retained V2.3 composition root.
- **exact repository path:** `scripts/v2_3/v2_3_life_loop_simulation.gd`.
- **current owner:** Legacy/retained composition root combining V2.2 clock, schedule/economy and V2.3 spatial/cognition/travel/social services.
- **current product reachability:** Retained test fixture only; formal product tests explicitly use `FormalWorldApplication` rather than V2.3 product simulation.
- **classification:** `REFERENCE_ONLY`.
- **reason:** It extends the old life-loop simulation and owns/uses the legacy clock, so it cannot sit under vNext without recreating a second runtime root.
- **reusable behavior:** Composition order and old cross-service invariants are useful when identifying adapter dependencies and regression scenarios.
- **state currently owned:** Legacy clock-derived world state and references to all retained V2.3 services.
- **dependency risks:** Second time authority, old player/person constants, old schema, broad service reach and accidental restoration of retired product topology.
- **vNext integration condition:** None as a dependency; adapters are taken service-by-service instead.
- **forbidden direct dependency:** `VNextWorldRuntime` or any vNext composition root must not extend, wrap as authority, or synchronize with `V23LifeLoopSimulation`.
- **useful existing tests:** `tests/v2_3/v2_3_location_test.gd`, `tests/v2_3/v2_3_route_planner_test.gd`, `tests/v2_3/v2_3_travel_execution_test.gd`, `tests/v2_3/v2_3_schedule_integration_test.gd`.
- **deletion condition:** Not applicable to this inventory; retained until old fixtures are replaced or retired.
- **code evidence:** The class extends `V2LifeLoopSimulationPolish`, reuses its `clock` and schedule/economic authorities, and V2.3 requests read `clock.total_hours`.

### 22. OrganizationService

- **component:** Core organization membership/position/permission service.
- **exact repository path:** `scripts/organization/organization_service.gd`.
- **current owner:** Legacy core society owner for organization records and membership/position structure.
- **current product reachability:** Not in the formal product composition; used by core/Alpha fixtures and `tests/test_runner.gd`.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Vacancy, membership, position and permission logic are reusable, but join/leave/assignment mutate supplied character records and legacy organization IDs/data directly.
- **reusable behavior:** Organization lookup, entry vacancy, membership, position assignment, permissions, hierarchy capacity and exact legacy organization-state restoration rules.
- **state currently owned:** Organization records, member/position occupancy and organization relationship metadata.
- **dependency risks:** Direct mutation of `CharacterData.organization_ids` / public position crosses the person owner; legacy Loran/Vesta fixture IDs are not a vNext catalog.
- **vNext integration condition:** Organization service owns memberships/positions only, character/person owner receives derived query results or explicit events, and IDs come from the vNext catalog.
- **forbidden direct dependency:** No direct write to character/session internals and no use of display title/array position as organization or position ID.
- **useful existing tests:** `tests/test_runner.gd`, `tests/v2_3/v2_3_social_sandbox_test_base.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** Core tests cover organization type/capacity, join/leave/permission, position occupancy and exact legacy-record migration; source join/leave/assignment updates character membership/position fields.

### 23. ActionService

- **component:** Core long-running action service.
- **exact repository path:** `scripts/action/action_service.gd`.
- **current owner:** Legacy core action lifecycle owner.
- **current product reachability:** Not in the formal product composition; exercised by `tests/test_runner.gd`.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Event-driven action progression and deterministic effect calculation are useful, but `start_action()` accepts a broad mutable context dictionary and completion paths can mutate character/map state directly.
- **reusable behavior:** Action eligibility, duration/progress, pause/resume/cancel/interruption, deterministic thresholds and result/effect evaluation.
- **state currently owned:** Action instances/result state and action ID allocation dependencies.
- **dependency risks:** Universal-context behavior, direct cross-owner mutation, legacy StableIdService semantics and old session coupling.
- **vNext integration condition:** Replace generic context with typed command/query inputs, use vNext stable action IDs/time and return effects/events for authoritative owners to apply.
- **forbidden direct dependency:** No mutable catch-all `Context`, no `GameSessionService` access and no direct map/person mutation from the action domain.
- **useful existing tests:** `tests/test_runner.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** Core action tests cover definitions, start/progress/pause/cancel/result application; source accepts `input_context: Dictionary` and legacy result application paths can alter supplied domain objects.

### 24. GameSessionService

- **component:** Legacy process-global player/session service.
- **exact repository path:** `scripts/character/game_session_service.gd`.
- **current owner:** Static process-global holder for player/session/action/society/map/clock/autosave/developer state.
- **current product reachability:** Not used by the current formal hemisphere composition; still exercised by legacy core tests/UI fixtures.
- **classification:** `REFERENCE_ONLY`.
- **reason:** It is an implicit global mutable session authority and historically held player/action/time-adjacent facts. Direct reuse would violate vNext explicit ownership and single-player-fact rules.
- **reusable behavior:** Legacy session lifecycle and succession/UI expectations are useful as compatibility requirements only.
- **state currently owned:** Static player character, current action/history, ID service, society, world clock, map and other session/UI flags.
- **dependency risks:** Hidden singleton coupling, second player truth, global mutable state and test order sensitivity.
- **vNext integration condition:** None as a dependency; introduce an explicit vNext session/player owner with narrow interfaces instead.
- **forbidden direct dependency:** No vNext production code may read/write `GameSessionService` static members.
- **useful existing tests:** `tests/test_runner.gd`.
- **deletion condition:** Not applicable to this inventory; retain only while old UI/core regressions require it.
- **code evidence:** The service stores its major session members as static globals; `tests/test_runner.gd` directly sets/clears player, society, action and developer-mode state.

### 25. SocietySimulationService

- **component:** Legacy core society composition service.
- **exact repository path:** `scripts/simulation/society_simulation_service.gd`.
- **current owner:** Legacy owner/composer for roster, organizations, legacy relationships, actions and AI.
- **current product reachability:** Not part of formal main; exercised by `tests/test_runner.gd` and older UI/session flows.
- **classification:** `REFERENCE_ONLY`.
- **reason:** It composes multiple legacy authorities and reaches into `GameSessionService`/legacy ID state, so using it would recreate the old global composition rather than migrate services individually.
- **reusable behavior:** Population-tier, organization/society interaction, succession and sparse-AI test scenarios remain useful specifications.
- **state currently owned:** Legacy society composition references and society-level domain state.
- **dependency risks:** Global session access, duplicate relationship/organization/action owners, old clock attachment and fictional demo-world assumptions.
- **vNext integration condition:** None as a runtime dependency; re-express required behavior via selected vNext domain services.
- **forbidden direct dependency:** vNext must not install `SocietySimulationService` beside its own session/social owners.
- **useful existing tests:** `tests/test_runner.gd`.
- **deletion condition:** Not applicable to this inventory.
- **code evidence:** Initialization/composition uses legacy roster/org/relationship/action/AI services and source reaches `GameSessionService.action_id_service`; core tests set `GameSessionService.society_service` directly.

### 26. AlphaLedgerService

- **component:** Alpha double-entry cash ledger.
- **exact repository path:** `scripts/alpha/alpha_ledger_service.gd`.
- **current owner:** Quarantined Alpha authority for cash accounts, balanced transactions and ledger idempotency.
- **current product reachability:** Not part of the formal product; exercised by quarantined Alpha regressions in `tools/run_validation.ps1`.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Double-entry, non-negative and idempotent posting behavior is valuable, but account/transaction IDs, dictionary state and owner integration use Alpha-specific contracts.
- **reusable behavior:** Cash-account registration, balanced posting/transfer, opening balance tracking, negative-balance rejection, idempotent transaction keys and bounded history.
- **state currently owned:** Accounts, transactions, opening balances, processed-key index/order and transaction sequence.
- **dependency risks:** `transaction:alpha:*` sequencing is not the vNext stable ID contract; callers may treat ledger account as person/organization state owner rather than financial projection.
- **vNext integration condition:** Adapt IDs through the vNext catalog, make ledger the sole money-posting authority for its domain, and expose commands/queries rather than raw account dictionaries.
- **forbidden direct dependency:** No other vNext service may mutate ledger accounts/transactions directly or keep a parallel cash balance.
- **useful existing tests:** `tests/alpha/alpha_economy_lifecycle_test.gd`, `tests/alpha/alpha_economy_integration_phase2_test.gd`, `tests/alpha/alpha_save_and_migration_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** Source describes the ledger as the only Alpha cash mutation path and enforces balanced entries/idempotency; Alpha lifecycle tests verify one-time loan/life-cost postings and balance integrity.

### 27. AlphaEnterpriseService

- **component:** Alpha enterprise lifecycle service.
- **exact repository path:** `scripts/alpha/alpha_enterprise_service.gd`.
- **current owner:** Quarantined Alpha owner for enterprise operating records.
- **current product reachability:** Not in formal main; quarantined fixture tests only.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Enterprise lifecycle mechanics are useful, but the service directly coordinates Alpha economy/labor and legacy OrganizationService and contains fixture-oriented ID/bootstrap assumptions.
- **reusable behavior:** Enterprise creation, partnership, financing, orders, procurement, production, delivery, outsourcing, expansion, hiring, distress and bankruptcy lifecycle.
- **state currently owned:** Enterprise operating records, production/asset/job associations and processed operation keys.
- **dependency risks:** Direct cross-service mutation, `organization:player_enterprise_*` style IDs, legacy organization records and Alpha fixture geography/economy coupling.
- **vNext integration condition:** Use stable organization/enterprise IDs, explicit ledger/contract/labor/org command ports and transaction boundaries; enterprise state must not duplicate organization identity.
- **forbidden direct dependency:** No direct writes into Alpha economy/labor/organization internal dictionaries and no demo-world bootstrap assumptions.
- **useful existing tests:** `tests/alpha/alpha_labor_enterprise_test.gd`, `tests/alpha/alpha_ai_economy_stability_test.gd`, `tests/alpha/alpha_economy_integration_phase2_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** Alpha lifecycle tests create enterprises as organizations, establish partnership/loan/order/production/hiring paths and verify success/distress outcomes; source wires economy, labor and OrganizationService directly.

### 28. AlphaLaborService

- **component:** Alpha labor/employment lifecycle service.
- **exact repository path:** `scripts/alpha/alpha_labor_service.gd`.
- **current owner:** Quarantined Alpha owner for jobs, applications, employment state, labor person profiles, unemployment and migration history.
- **current product reachability:** Not in formal main; quarantined Alpha fixtures only.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Job discovery/application/work/wage/employment lifecycle is valuable, but the service reads/writes Alpha economy contracts, ledger and entity profiles directly and duplicates person-locality/profile facts.
- **reusable behavior:** Job discovery, application/decision, employment contracts, shifts/experience/fatigue, wages, negotiation, promotion, resignation/dismissal and unemployment transitions.
- **state currently owned:** Jobs, applications, employment states, labor person profiles, unemployment, migration records and processed keys.
- **dependency risks:** Direct `_economy.contracts.contracts` mutation, direct `_economy.entity_profiles` mutation, duplicate person profile/location truth and Alpha-specific IDs.
- **vNext integration condition:** Split labor-owned facts from person/economy facts, use public contract/ledger/person commands, stable IDs and vNext-derived time.
- **forbidden direct dependency:** No access to contract/economy internal dictionaries and no labor-owned duplicate canonical person location/profile.
- **useful existing tests:** `tests/alpha/alpha_labor_enterprise_test.gd`, `tests/alpha/alpha_economy_lifecycle_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** `work_shift`, `pay_wage`, `negotiate_terms` and `promote` directly traverse economy contract/ledger/profile internals; persistence stores a separate `person_profiles` dictionary.

### 29. AlphaContractService

- **component:** Alpha generic contract lifecycle service.
- **exact repository path:** `scripts/alpha/alpha_contract_service.gd`.
- **current owner:** Quarantined Alpha owner for contracts/templates, payment/delivery evidence and contract idempotency.
- **current product reachability:** Not in formal main; quarantined Alpha fixtures only.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** The generic lifecycle is reusable across employment, sale, service, lease, loan, partnership and order contracts, but it is wired to Alpha ledger/assets and uses Alpha sequence IDs/time arguments.
- **reusable behavior:** Creation, activation, delivery/payment evidence, renegotiation, delay/default/termination, party queries, outstanding obligation tracking and idempotency.
- **state currently owned:** Contract records/templates, processed keys and contract sequence.
- **dependency risks:** `contract:alpha:*` IDs are not vNext IDs; ledger/asset evidence must reference stable entities; callers currently sometimes mutate contract dictionaries directly.
- **vNext integration condition:** Allocate contract IDs through vNext, accept explicit ledger/asset query/command ports, and make the contract service the only contract-state mutation authority.
- **forbidden direct dependency:** Labor/enterprise/economy must not write `contracts` dictionaries directly after adaptation.
- **useful existing tests:** `tests/alpha/alpha_economy_lifecycle_test.gd`, `tests/alpha/alpha_labor_enterprise_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** Source supports multiple contract templates/lifecycle transitions and Alpha lifecycle tests verify loan/trade/employment/partnership/order state, payment evidence and restoration integrity.

### 30. Alpha labor migration subflow

- **component:** Person economic migration implemented inside `AlphaLaborService.migrate()`.
- **exact repository path:** `scripts/alpha/alpha_labor_service.gd`.
- **current owner:** Alpha labor currently owns migration history while person/economy locality is spread across labor and economy profiles.
- **current product reachability:** Not in formal main; Alpha fixture subsystem only.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Pay-before-move and explicit from/to migration records are useful, but the implementation performs cross-owner double writes and generates array-sequence migration IDs.
- **reusable behavior:** Validate target, charge transport once, record origin/destination/time/cost, then move the person only after payment succeeds.
- **state currently owned:** `migrations` history and labor copy of person country/region/city.
- **dependency risks:** `migration:alpha:%d` is unstable across reconstruction; method writes both `person_profiles` and `_economy.entity_profiles`, creating two locality truths.
- **vNext integration condition:** A vNext migration command must use stable migration/person/place IDs, charge through ledger, then atomically update the single person/location authority and append an immutable migration event.
- **forbidden direct dependency:** No direct write to economy entity profiles or second person-location dictionary; array size must never be the persistent ID allocator.
- **useful existing tests:** No dedicated `labor.migrate()` regression was found among the exact retained/quarantined tests read for this inventory; `tests/alpha/alpha_labor_enterprise_test.gd` remains useful for surrounding labor/economy contract invariants.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** `migrate()` charges `_economy.ledger`, creates `migration:alpha:%d` from `migrations.size()`, updates labor `person_profiles`, then directly updates `_economy.entity_profiles` for the same person's region.

### 31. AlphaAiService

- **component:** Alpha bounded explainable economic/person AI service.
- **exact repository path:** `scripts/alpha/alpha_ai_service.gd`.
- **current owner:** Quarantined Alpha owner for bounded decision history and per-hour/day processed decision state.
- **current product reachability:** Not in formal main; quarantined AI economy regression only.
- **classification:** `REUSE_WITH_ADAPTER`.
- **reason:** Bounded candidate generation, deterministic ranking and explanation are useful. Execution is tightly coupled to Alpha labor/economy/enterprise/politics/organization/character/commodity services and a generic known-facts dictionary.
- **reusable behavior:** Candidate cap, known-fact-limited evaluation, deterministic tie-breaking, explicit reasons, bounded decision retention and economic action selection.
- **state currently owned:** AI decision history, processed periods/keys and configured service references.
- **dependency risks:** `_execute` can call many concrete services; generic `known` dictionaries can become a universal Context; old action/entity IDs and fixture economy assumptions are embedded.
- **vNext integration condition:** Split planning from execution: AI receives typed, person-visible query snapshots and emits vNext commands/intents; command handlers own actual mutations.
- **forbidden direct dependency:** AI must not receive raw service instances or mutate labor/economy/enterprise/politics internals; no omniscient global state dictionary.
- **useful existing tests:** `tests/alpha/alpha_ai_economy_stability_test.gd`, `tests/alpha/alpha_economy_integration_phase2_test.gd`.
- **deletion condition:** Not applicable while adapted.
- **code evidence:** The source caps candidates/decision history and records explanations, but its configured dependencies span the Alpha subsystem and execution invokes those services directly.

### 32. AlphaSimulationService

- **component:** Alpha composition root.
- **exact repository path:** `scripts/alpha/alpha_simulation_service.gd`.
- **current owner:** Quarantined Alpha composition owner for Alpha world/economy/commodity/labor/enterprise/character/politics/AI/dynamics on top of V2.3.
- **current product reachability:** Not the formal main product; used only by quarantined Alpha fixtures and diagnostics.
- **classification:** `REFERENCE_ONLY`.
- **reason:** It explicitly extends `V23LifeLoopSimulation` and retains the V2.3 clock/schedule/space/cognition, so adopting it would import the legacy runtime root and fictional demo-world coupling wholesale.
- **reusable behavior:** Composition dependencies, integrity checks, bounded high-detail population and long-run regression scenarios are useful migration references.
- **state currently owned:** Alpha composition service references, events/intents, detailed enterprise set, Alpha timing/performance counters and inherited V2.3 state.
- **dependency risks:** Second clock/runtime, `data/world/demo_world.json` fixture world, Loran/Vesta economy bootstraps and broad cross-service reach.
- **vNext integration condition:** None as dependency; only individual services with explicit adapters are eligible.
- **forbidden direct dependency:** vNext must not extend or embed `AlphaSimulationService` or restore its full snapshot as vNext state.
- **useful existing tests:** `tests/alpha/alpha_ai_economy_stability_test.gd`, `tests/alpha/alpha_economy_integration_phase2_test.gd`, `tests/alpha/alpha_save_and_migration_test.gd`.
- **deletion condition:** Not applicable to this inventory.
- **code evidence:** The class declaration extends `V23LifeLoopSimulation`; its comment says it retains the V2.3 clock/schedule/space/cognition and its `CORE_WORLD_PATH` is the fictional demo world.

### 33. V23SaveMigration runtime implementation

- **component:** V2.2-to-V2.3 save migration implementation.
- **exact repository path:** `scripts/v2_3/v2_3_save_migration.gd`.
- **current owner:** Legacy save compatibility utility for the retired V2.3 schema.
- **current product reachability:** Not used by the formal main product; exercised by retained migration tests.
- **classification:** `REFERENCE_ONLY`.
- **reason:** The migration policy is useful, but the implementation reconstructs the old V2.3 product simulation, sets legacy clock/debug state and directly manipulates old service state. It must not become a vNext dependency.
- **reusable behavior:** Non-destructive source handling, explicit source schema validation, deterministic transformation, removal/replacement of obsolete fixed commutes and fail-closed invalid-source behavior.
- **state currently owned:** No long-lived runtime state; it builds/transforms legacy snapshots.
- **dependency risks:** Direct dependence on V2.2/V2.3 runtime classes and private service state would drag retired ownership into vNext; schema names encode retired products.
- **vNext integration condition:** If legacy saves must be supported, re-express required transforms as isolated snapshot-to-snapshot adapters that output a validated vNext schema without instantiating the legacy runtime as an authority.
- **forbidden direct dependency:** vNext runtime/services must not call into or inherit this migration implementation during normal execution.
- **useful existing tests:** `tests/v2_3/v2_3_save_migration_test.gd`, `tests/alpha/alpha_save_and_migration_test.gd`.
- **deletion condition:** Not applicable to this inventory; retain as compatibility reference until legacy save support policy is finalized.
- **code evidence:** The implementation validates V2.2 snapshots, constructs V2.3 simulation state, uses old clock/debug setters and directly edits old schedule/idempotency/spatial/relationship state before producing the V2.3 schema.

### 34. FormalWorldApplication

- **component:** Live formal hemisphere application/UI controller.
- **exact repository path:** `scripts/formal/formal_world_application.gd`.
- **current owner:** Current product UI/application shell; it owns a `FormalWorldSimulation` instance plus panel/status/selection presentation state inherited from the holographic UI chain.
- **current product reachability:** Directly live; `project.godot` launches the formal menu and product tests instantiate `FormalWorldApplication`.
- **classification:** `DELETE_AFTER_REPLACEMENT`.
- **reason:** It directly constructs the legacy formal runtime and performs time/save/load UI commands against it. vNext must have a new application boundary rather than place this controller above a second runtime.
- **reusable behavior:** Hemisphere interaction patterns, product-surface layout, polity/economy readout and thin UI command semantics are useful UI references.
- **state currently owned:** `formal_simulation`, economy-panel open flag, UI status/last summary and inherited UI selection/cache state.
- **dependency risks:** UI can become business owner; controller inheritance is deep; old runtime is embedded as a member.
- **vNext integration condition:** Build a vNext application/presenter that only issues commands/queries to the vNext composition root; transfer visual behavior without transferring runtime authority.
- **forbidden direct dependency:** vNext UI must not instantiate `FormalWorldSimulation` or read economy internals; UI selection cannot become persistent polity/player truth.
- **useful existing tests:** `tests/formal/formal_world_integration_test.gd`, `tests/v2_3/v2_3_player_interface_test.gd`.
- **deletion condition:** Delete when the default product scene uses the vNext application/presenter and equivalent formal hemisphere product-surface tests pass without this class.
- **code evidence:** `_ready()` initializes `formal_simulation`; time/save/load handlers call that instance; drawing code queries the formal composition root for polity/economy summaries.

### 35. Source-backed historical evidence UI runtime

- **component:** Current source-backed historical geometry/flag UI layer.
- **exact repository path:** `scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_evidence.gd`.
- **current owner:** Current formal hemisphere UI inheritance chain for dated geometry records, map render dictionaries and flag/evidence caches.
- **current product reachability:** Directly reachable as a superclass of the current formal application chain.
- **classification:** `DELETE_AFTER_REPLACEMENT`.
- **reason:** It correctly uses dated CShapes data, but it is a UI class that constructs and owns map-domain dictionaries (`_countries`, `_country_by_id`, geometry indexes) inside a deep presentation inheritance chain. The data should survive; this business/data ownership should not.
- **reusable behavior:** Geometry conversion to unit-sphere polygons, historical anchor calculation, source/flag validation and dated-data display notices can be extracted or reimplemented.
- **state currently owned:** Loaded historical documents, geometry/flag indexes, country/map render records and presentation caches inherited by UI.
- **dependency risks:** UI-held political/map truth, legacy navigation aliases and presentation-specific mapping can diverge from the vNext catalog.
- **vNext integration condition:** Move authoritative political/catalog loading to vNext data/domain services; the renderer receives read-only render/query models and can reuse geometry math without owning identities.
- **forbidden direct dependency:** vNext domain/economy must not depend on this UI class or its `_country_by_id` / `_countries` dictionaries.
- **useful existing tests:** `tests/formal/formal_world_integration_test.gd`, `tests/v2_3/v2_3_player_interface_test.gd`.
- **deletion condition:** Delete after a vNext map renderer consumes source-backed catalog/geometry through a non-UI authority and current formal hemisphere visual/product regressions are replaced.
- **code evidence:** `_rebuild_historical_political_world()` clears and reconstructs country/domain-looking dictionaries directly inside the UI class from CShapes/political-unit documents; constants explicitly prevent fallback to modern polygons.

### 36. Historical admin UI runtime

- **component:** Current historical first-level administration UI/runtime layer.
- **exact repository path:** `scripts/ui_spikes/holographic_workspace/holographic_workspace_historical_admin_runtime.gd`.
- **current owner:** Current formal UI chain for admin selection/page state, state-profile lookup and runtime admin display records.
- **current product reachability:** Directly reachable because `FormalWorldApplication` extends this inheritance chain.
- **classification:** `DELETE_AFTER_REPLACEMENT`.
- **reason:** It owns UI selection state and generates runtime admin IDs from array indexes, both incompatible with vNext stable-ID/domain ownership requirements.
- **reusable behavior:** Historical admin data presentation, paging and explicit unresolved-geometry notices are useful UI behavior references.
- **state currently owned:** `selected_admin_unit_id`, page index, profile/alias/admin dictionaries and generated `runtime_units`.
- **dependency risks:** IDs are generated as `%s_admin_%03d` from iteration order; lower-admin geometry is explicitly incomplete; UI selection can be confused with domain identity.
- **vNext integration condition:** Static admin units receive catalog-backed stable IDs before they enter vNext; UI stores only transient selection of already-stable IDs and queries a non-UI catalog.
- **forbidden direct dependency:** vNext must not persist generated array-index admin IDs or treat UI `selected_admin_unit_id` as canonical world state.
- **useful existing tests:** `tests/v2_3/v2_3_player_interface_test.gd`, `tests/formal/formal_world_integration_test.gd`.
- **deletion condition:** Delete after vNext catalog/rendering provides stable admin identity and the formal UI no longer inherits this runtime.
- **code evidence:** `_load_historical_admin_records()` creates IDs with `"%s_admin_%03d" % [entity_id, index]`; the class owns selection/page state and explicitly warns when historical geometry is unresolved.

### 37. Save and migration regression suite

- **component:** Retained legacy save/migration behavioral tests.
- **exact repository path:** `tests/v2_3/v2_3_save_migration_test.gd`; `tests/alpha/alpha_save_and_migration_test.gd`.
- **current owner:** Test-only regression specifications.
- **current product reachability:** Test/CI only; Alpha runner labels the latter a quarantined save-migration fixture.
- **classification:** `TEST_ONLY`.
- **reason:** The tests contain useful non-destructive/atomicity/backup/integrity requirements, while the legacy target schemas and composition roots are not vNext runtime dependencies.
- **reusable behavior:** Source snapshot immutability, fail-closed invalid schema, deterministic migration, backup recovery, digest rejection, failed-restore immutability and explicit migration-chain expectations.
- **state currently owned:** Test fixtures and temporary test save files only.
- **dependency risks:** Copying expected V2.3/Alpha schema names into vNext would preserve obsolete ownership; legacy exact snapshots should not become the vNext schema.
- **vNext integration condition:** Port the behavioral assertions to vNext persistence/migration tests while rewriting expected schemas/owners to the vNext contract.
- **forbidden direct dependency:** Production vNext code must never import test helpers or instantiate legacy runtime roots merely to satisfy these tests.
- **useful existing tests:** These two files are the retained test evidence themselves.
- **deletion condition:** Not applicable; keep until equivalent vNext regressions cover all retained invariants and legacy compatibility support is intentionally retired.
- **code evidence:** V2.3 test proves source snapshots are unchanged and invalid sources are rejected; Alpha test proves atomic save/backup recovery, tamper rejection without mutation and explicit V2.2→V2.3→Alpha migration chain behavior.

### 38. Formal time stable contract

- **component:** Long-term formal time behavioral contract.
- **exact repository path:** `tests/variable_state/formal_time_stable_contract_test.gd`.
- **current owner:** Test-only stable-contract specification.
- **current product reachability:** CI/test only, but it exercises the live formal product time/save path.
- **classification:** `TEST_ONLY`.
- **reason:** The assertions describe behavior to preserve while the current subject (`FormalWorldSimulation`) is scheduled for replacement.
- **reusable behavior:** Gregorian correctness, minute/hour invariant, pause/speed semantics, day-boundary settlement, save/load round-trip and failed-restore atomicity.
- **state currently owned:** Isolated test save/backup state only.
- **dependency risks:** Assertions that mention legacy private fields such as `_minute_remainder` or `economy.total_hour` must be rewritten around vNext public contracts rather than freezing old internals.
- **vNext integration condition:** Preserve semantic assertions and retarget them to `VNextWorldRuntime` plus the vNext economy/persistence boundary.
- **forbidden direct dependency:** Do not keep legacy private fields/services solely to make the old test compile.
- **useful existing tests:** This file plus `tests/vnext/world_runtime_test.gd`.
- **deletion condition:** Not applicable; evolve into vNext stable-contract coverage before retiring legacy-specific assertions.
- **code evidence:** It explicitly checks 1900/1904 Gregorian boundaries, `economy.total_hour == total_minutes / 60`, pause/speed ticks, one settlement per day boundary, production save/load and restore-failure immutability.

### 39. Retained V2.3 service behavior tests

- **component:** Retained person/spatial/social service regression set.
- **exact repository path:** `tests/v2_3/v2_3_location_test.gd`; `tests/v2_3/v2_3_route_planner_test.gd`; `tests/v2_3/v2_3_travel_execution_test.gd`; `tests/v2_3/v2_3_schedule_integration_test.gd`; `tests/v2_3/v2_3_communication_test.gd`; `tests/v2_3/v2_3_knowledge_test.gd`; `tests/v2_3/v2_3_relationship_test.gd`; `tests/v2_3/v2_3_appointment_test.gd`; `tests/v2_3/v2_3_npc_test.gd`; `tests/v2_3/v2_3_social_sandbox_test.gd`; `tests/v2_3/v2_3_social_sandbox_test_base.gd`.
- **current owner:** Test-only retained-service specifications.
- **current product reachability:** CI/test only. `tools/run_validation.ps1` explicitly calls these retained person/social regressions and says they do not own a map or product entry.
- **classification:** `TEST_ONLY`.
- **reason:** Their fixtures depend on the V2.3 composition root, but the behavioral invariants are the strongest evidence for adapter acceptance.
- **reusable behavior:** Stable location IDs, cognition-limited routing, deterministic tie-breaks, idempotent travel, schedule/spatial truth separation, delayed communication, provenance knowledge, causal relationships, real appointment attendance, bounded NPC planning and atomic social actions.
- **state currently owned:** Test objects/fixtures only.
- **dependency risks:** Blindly copying fixtures would import Pierre/Jeanne/Lille and legacy clock/schema assumptions as product data.
- **vNext integration condition:** Recreate the same semantic tests against adapter ports and vNext stable IDs/time while replacing fixture-specific constants where needed.
- **forbidden direct dependency:** Production code must not depend on test fixture classes or use V2.3 composition solely to execute the adapters.
- **useful existing tests:** The listed files are the retained regression corpus.
- **deletion condition:** Not applicable; retire individual legacy tests only after equivalent vNext adapter/native tests exist.
- **code evidence:** The tests separately prove actual-position authority, route visibility, one-time fare settlement, knowledge-on-read, provenance/contradiction, causal relationship history, co-location appointment settlement, bounded event planning and social atomic rollback.

### 40. Retained/Alpha fixture performance and economy regression tests

- **component:** Retained-service performance and quarantined Alpha economy test evidence.
- **exact repository path:** `tests/alpha/alpha_fixture_retained_services_performance_test.gd`; `tests/alpha/alpha_economy_lifecycle_test.gd`; `tests/alpha/alpha_labor_enterprise_test.gd`; `tests/alpha/alpha_economy_integration_phase2_test.gd`; `tests/alpha/alpha_ai_economy_stability_test.gd`.
- **current owner:** Test-only performance/lifecycle fixtures.
- **current product reachability:** CI/test only. `tools/run_validation.ps1` explicitly labels the Alpha two-country/eight-region paths quarantined and not world/map/product/balance authority.
- **classification:** `TEST_ONLY`.
- **reason:** These tests provide useful performance, idempotency, lifecycle and integrity acceptance criteria, but their Loran/Vesta fixture topology must not enter vNext data or dependency graphs.
- **reusable behavior:** No per-frame world scans, bounded histories, long-run performance limits, balanced ledger, contract/enterprise/labor lifecycle, sparse logistics integrity, bounded AI decisions and save/restore equivalence.
- **state currently owned:** Test fixtures and generated simulation state only.
- **dependency risks:** Fixture IDs/data can be mistaken for current 1900 world authority; wall-clock thresholds may need runner-aware calibration while structural bounds remain invariant.
- **vNext integration condition:** Port structural/performance assertions to vNext adapters/native services using authoritative catalogs; keep fixture worlds explicitly quarantined.
- **forbidden direct dependency:** No production vNext service may load Loran/Vesta fixture data or Alpha composition root because a test currently uses it.
- **useful existing tests:** The listed files are the evidence set; `tools/run_validation.ps1` defines their retained/quarantined status.
- **deletion condition:** Not applicable; keep until equivalent vNext coverage supersedes each assertion.
- **code evidence:** Retained performance test forbids `_process`/`_physics_process` scans and bounds schedule/message/travel/social histories; Alpha tests cover ledger integrity, enterprise/labor/contract lifecycle, sparse logistics, three-year AI economy bounds and restore equivalence.

## A. Directly reusable infrastructure

The following may enter the vNext dependency graph directly, subject to the integration conditions above:

1. `V2DateTime` — pure Gregorian conversion only; it never owns or advances time.
2. `AtomicJsonFileStore` — generic verified atomic JSON durability boundary.
3. `SaveOperationResult` — generic persistence result value object.

The three `DATA_ONLY` groups are reusable assets, not infrastructure implementations. They should be loaded through vNext catalog/data boundaries rather than treated as direct service dependencies.

## B. Phase 3 implementations eligible through adapters

Recommended adapter candidates, without starting migration:

1. `FormalWorldEconomyService`.
2. `SpatialLocationService`.
3. `RoutePlannerService`.
4. `TravelExecutionService`.
5. `V2ScheduleService`.
6. `CommunicationService`.
7. `KnowledgeService`.
8. `V23RelationshipService`.
9. `V23SocialAppointmentService`.
10. `SpatialNpcRoutineService`.
11. V2.3 social sandbox V1/V2/V3 coordination stack.
12. `OrganizationService`.
13. `ActionService`.
14. `AlphaLedgerService`.
15. `AlphaContractService`.
16. `AlphaLaborService`.
17. Alpha labor migration subflow.
18. `AlphaEnterpriseService`.
19. `AlphaAiService`.

Adapter acceptance must remove legacy time/player/session ownership, normalize IDs through the vNext catalog, replace direct internal-member writes with explicit public commands/queries, and prevent broad mutable dictionaries from becoming universal context.

## C. Implementations that must not enter the vNext dependency graph

1. `FormalWorldSimulation` — current second runtime/time/snapshot root; keep only until vNext replacement is product-ready.
2. `FormalWorldApplication` — current UI directly owns the old formal runtime.
3. Source-backed historical evidence UI runtime — authoritative data survives, UI-held map/domain truth does not.
4. Historical admin UI runtime — generated array-index admin IDs and UI-owned selection are not vNext identity.
5. `V23LifeLoopSimulation` — retired V2.3 composition/clock root.
6. `GameSessionService` — global mutable player/session authority.
7. `SocietySimulationService` — legacy global/core composition root.
8. Legacy `RelationshipService` — duplicate relationship authority with direct character mutation.
9. `AlphaSimulationService` — Alpha-over-V2.3 composition root and demo-world authority.
10. `V23SaveMigration` implementation — legacy runtime-coupled migration code; only its transformation rules/tests are reference material.
11. `data/world_map/historical_political_entities_1900.json` — explicitly prototype-only modern-polygon approximation, not authoritative 1900 data.

The four `TEST_ONLY` groups also remain outside the production dependency graph; they are retained as validation specifications.

## Recommended migration order

1. Keep `VNextWorldRuntime` as the only writable runtime time owner. Complete the stable-ID/catalog and persistence-boundary prerequisites before importing stateful services.
2. Adopt the three `REUSE_DIRECT` infrastructure pieces. Bind atomic persistence around vNext snapshots, not around service-private saves.
3. Admit the `DATA_ONLY` political/economy/commodity assets through stable catalogs. Resolve CShapes commercial-license constraints before any commercial release decision.
4. Adapt `FormalWorldEconomyService` first among live systems, because it already supports an injected authoritative hour and gives vNext a real 1900 world/economy without retaining `FormalWorldSimulation` as owner.
5. Establish the person-level authority spine in this order: location -> knowledge -> relationship -> schedule. Each service must have one owner and stable IDs before dependent orchestration is attached.
6. Add route planning and travel execution, then communication and appointments, preserving actual-location, cognition and transaction boundaries from retained tests.
7. Adapt organization and action contracts, then ledger -> contract -> labor -> enterprise -> migration. Remove every direct cross-service dictionary write during this stage.
8. Attach social sandbox and NPC planning only after their downstream ports exist. Preserve bounded/event-driven planning and atomic social commit semantics.
9. Attach Alpha AI last among retained service adapters. AI receives typed visible facts and emits commands; it does not own or mutate authoritative service state.
10. Build the vNext hemisphere/application presenter against the vNext composition root. Once product-surface regressions pass, remove `FormalWorldSimulation`, `FormalWorldApplication` and the old historical UI ownership layers according to their deletion conditions.
11. Retarget `TEST_ONLY` behavior contracts incrementally to vNext, then retire legacy fixture/composition tests only when equivalent vNext coverage exists.

## Evidence sufficiency

No component in this inventory is classified from a filename alone. Every listed production/data path was opened at `FIXED_BASE`, and the listed behavioral tests were read or explicitly located in the retained validation runner. There are **no evidence-insufficient classification items** in this inventory. Where a dedicated behavior test was not found (`AlphaLaborService.migrate()`), the classification is still supported by direct source evidence showing its owner writes and ID generation; the document does not claim a missing migration regression exists.

## Non-goals confirmed

- No production code is changed.
- No JSON artifact is added.
- No scanner or second audit tool is added.
- No vNext migration or adapter implementation is started.
