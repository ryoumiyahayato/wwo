# Reconstructed AI armor module

Recreated after the cloud reset from retained implementation context. Historical test results are not validation of this reconstructed source. Fresh engine validation is required.

## Main integration

- Instantiate armor_host.gd as a Node, add to tree, call setup(main).
- Call spawn(stage) after main.hero and terrain exist. This creates four blue AI and five red AI, in addition to the blue player.
- Call on_stage_reset() before stage clearing.
- Merge candidates() into infantry/minimap candidate lists. Fields: actor_id, team_id, actor_kind, position, alive, node, exclude.
- Route infantry actual hits through receive_hit(event), supporting nested hit dictionaries.
- Route player hits through handle_player_projectile(hit,kind,ammo_name,penetration); empty string means not an AI armor hit.
- main.vehicle_contacts must be the initialized shared swept-contact resolver. Both movement and turret/barrel aim call capture_pose/resolve_pose.
- main.align_vehicle_ground returns shared GroundSupport.fit results. The motor uses baseline/candidate transition_allowed, unloaded hold, and a safe pivot fallback. No old per-corner slope or absolute step veto remains.
- Main updates streamed terrain simulation anchors for live AI positions before set_focus. Armor does not duplicate that orchestration.

Each unit owns a canonical Combat instance, crew colliders and per-module integrity. No whole-vehicle HP pool exists. Driver/gunner loss affects the corresponding action. Rifle penetration9, cannonHE15, smoke0; stopped small arms do not chip armor. Actual cannon/MG models and their distinct muzzle nodes are used. Team panels are physical depth-tested geometry without HP bars.

Autonomous perception uses battle_ai_presets, at most eight candidate LOS tests per think, observer-local weather/smoke,12-second last-known observations, and team contact reports. Reports guide movement only; firing requires fresh visibility and an aligned actual muzzle. Shared weapon_range governs fire distance. MG segment and cannon blast suppression call infantry host APIs, separately from damage.

optimization_enabled toggles staggered thought versus per-frame thought for matched profiling. Models, colliders, movement, aim and damage remain active in both modes. Reverse avoidance backs straight for the first half-second, then turns, avoiding the earlier turn-before-retreat deadlock.

Rebuilt smoke test: tests/test_armor_units.gd. Main combined battle should be disabled for that isolated fixture; it spawns nine close-range units independently of production deployment. No engine was run before the reconstruction checkpoint.
