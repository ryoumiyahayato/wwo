use super::{invalid, InitialWorld};
use crate::{
    battlefield_terrain::BattlefieldTerrain,
    formal_clock::{ClockSnapshot, GameClock, MINUTES_PER_HOUR},
    land_battle::{LandBattle, LandBattleControls},
    military_grid::MilitaryCell,
};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io};

#[derive(Deserialize, Serialize)]
struct BattleTiming {
    clock: ClockSnapshot,
    elapsed_steps: u64,
}

/// Fictional formations belong to one exercise. A unit's persistent identity
/// is the exercise ID paired with the unit ID in its roster.
#[derive(Deserialize, Serialize)]
pub struct WorldLandBattle {
    #[serde(default)]
    pub id: u64,
    pub region: MilitaryCell,
    #[serde(default)]
    deployment_cell: Option<MilitaryCell>,
    #[serde(default)]
    pub started_minute: Option<i64>,
    #[serde(default)]
    pub ended_minute: Option<i64>,
    #[serde(default)]
    pub ended_subminute_millis: u16,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    timing: Option<BattleTiming>,
    #[serde(default)]
    pending_minutes: i64,
    pub battle: LandBattle,
}

impl WorldLandBattle {
    pub fn cell(&self) -> MilitaryCell { self.deployment_cell.unwrap_or(self.region) }

    fn record_end(&mut self, clock: GameClock) {
        let end = clock.snapshot();
        self.ended_minute = Some(end.total_minutes);
        self.ended_subminute_millis = end.subminute_millis;
    }

    fn restore(&mut self, expected_id: u64, clock: GameClock) -> bool {
        if self.id == 0 && self.started_minute.is_none() { self.id = expected_id; }
        if self.id != expected_id || !self.region.is_valid() || self.region != self.region.region()
            || !self.cell().is_valid() || self.cell().region() != self.region || !self.battle.restore_elapsed_steps()
        {
            return false;
        }
        let through = if let Some(end) = self.ended_minute {
            let Ok(ended) = GameClock::restore(ClockSnapshot {
                total_minutes: end, minute_remainder: end % MINUTES_PER_HOUR,
                subminute_millis: self.ended_subminute_millis,
            }) else { return false; };
            if self.battle.outcome.is_none() || clock.fixed_steps_since(ended) < 0 { return false; }
            ended
        } else {
            if self.ended_subminute_millis != 0 { return false; }
            clock
        };
        let steps = self.battle.elapsed_steps();
        if let Some(timing) = &self.timing {
            let Ok(anchor) = GameClock::restore(timing.clock) else { return false; };
            return self.pending_minutes == 0
                && self.started_minute.is_none_or(|start| (0..=timing.clock.total_minutes).contains(&start))
                && self.battle.outcome.is_some() == self.ended_minute.is_some()
                && steps.checked_sub(timing.elapsed_steps).map(i128::from) == Some(through.fixed_steps_since(anchor));
        }

        // Preserve the date and combat state of earlier Rust saves. Only new steps use real-time pacing.
        const LEGACY_MINUTES_PER_STEP: i64 = 3;
        if !(0..LEGACY_MINUTES_PER_STEP).contains(&self.pending_minutes) || self.ended_subminute_millis != 0
            || self.started_minute.is_some_and(|start| {
                let old_duration = i64::try_from(steps).ok().and_then(|steps| {
                        steps.checked_mul(LEGACY_MINUTES_PER_STEP)?.checked_add(self.pending_minutes)
                });
                start < 0 || self.battle.outcome.is_some() != self.ended_minute.is_some()
                    || old_duration.is_none() || through.snapshot().total_minutes.checked_sub(start) != old_duration
            })
        {
            return false;
        }
        if self.battle.outcome.is_none() {
            self.timing = Some(BattleTiming { clock: clock.snapshot(), elapsed_steps: steps });
            self.pending_minutes = 0;
        }
        true
    }
}

impl InitialWorld {
    pub fn land_battle_record(&self) -> Option<&WorldLandBattle> { self.land_battle.as_ref() }

    pub fn land_battle(&self) -> Option<&LandBattle> { self.land_battle_record().map(|state| &state.battle) }

    pub fn land_battle_mut(&mut self) -> Option<&mut LandBattle> {
        self.land_battle.as_mut().map(|state| &mut state.battle)
    }

    pub fn land_battle_region(&self) -> Option<MilitaryCell> { self.land_battle_record().map(|state| state.region) }

    pub fn land_battle_history(&self) -> &[WorldLandBattle] { &self.land_battle_history }

    pub fn land_battle_in_progress(&self) -> bool { self.land_battle().is_some_and(|state| state.outcome.is_none()) }

    pub fn needs_land_deployment(&self, cell: MilitaryCell) -> bool {
        self.land_battle_record().is_none_or(|state| state.battle.outcome.is_some() && state.cell() != cell)
    }

    pub fn start_land_battle(&mut self, cell: MilitaryCell, battle: LandBattle) -> io::Result<()> {
        if !cell.is_valid() || !cell.region().is_valid() || !self.needs_land_deployment(cell)
            || !battle.validate() || battle.elapsed_steps() != 0 || battle.outcome.is_some()
        {
            return Err(io::Error::other("invalid land exercise deployment"));
        }
        if let Some(previous) = self.land_battle.take() { self.land_battle_history.push(previous); }
        self.land_battle = Some(WorldLandBattle {
            id: self.land_battle_history.len() as u64 + 1,
            region: cell.region(),
            deployment_cell: Some(cell),
            started_minute: Some(self.clock.snapshot().total_minutes),
            ended_minute: None,
            ended_subminute_millis: 0,
            timing: Some(BattleTiming { clock: self.clock.snapshot(), elapsed_steps: 0 }),
            pending_minutes: 0,
            battle,
        });
        Ok(())
    }

    pub fn finish_land_battle(&mut self) {
        if let Some(state) = &mut self.land_battle {
            if state.battle.outcome.is_none() {
                state.battle.conclude();
                state.record_end(self.clock);
            }
        }
    }

    pub fn advance_active_land_battle(
        &mut self, steps: u64, terrain: Option<(MilitaryCell, &BattlefieldTerrain)>, mut controls: LandBattleControls,
    ) -> io::Result<()> {
        let Some(active) = self.land_battle.as_ref().filter(|state| state.battle.outcome.is_none()) else { return Ok(()); };
        let (_, terrain) = terrain.filter(|(cell, _)| *cell == active.region)
            .ok_or_else(|| io::Error::other("active land exercise terrain unavailable"))?;
        for _ in 0..steps {
            let previous = self.clock;
            let target = previous.after_fixed_steps(1)?;
            let result = if target.snapshot().total_minutes == previous.snapshot().total_minutes {
                self.clock = target;
                Ok(())
            } else {
                self.advance_migrated_domains_to(target, &BTreeMap::new())
            };
            if self.clock == target {
                let state = self.land_battle.as_mut().expect("active land exercise");
                controls = state.battle.advance_steps(1, terrain, controls);
                if state.battle.outcome.is_some() {
                    state.record_end(self.clock);
                    return result;
                }
            }
            result?;
        }
        Ok(())
    }

    pub(super) fn restore_land_battles(
        &mut self, mut current: Option<WorldLandBattle>, mut history: Vec<WorldLandBattle>,
    ) -> io::Result<()> {
        for (index, battle) in history.iter_mut().chain(current.iter_mut()).enumerate() {
            if !battle.restore(index as u64 + 1, self.clock) { return Err(invalid("invalid saved land battle")); }
        }
        if history.iter().any(|state| state.battle.outcome.is_none()) || (current.is_none() && !history.is_empty()) {
            return Err(invalid("inconsistent land battle history"));
        }
        self.land_battle = current;
        self.land_battle_history = history;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{formal_bootstrap::WorldBootstrap, formal_clock::MINUTES_PER_DAY};

    #[test]
    fn realtime_battle_steps_cross_midnight_once_and_resume_exactly() {
        let cell = MilitaryCell::at([4.074, 48.297], 50).unwrap();
        let terrain = BattlefieldTerrain::from_geographic_heights(50_000, vec![0.; 4], vec![4; 4]).unwrap();
        let bootstrap = WorldBootstrap::load().unwrap();
        let open = || {
            let mut world = bootstrap.create("country_fra").unwrap();
            world.advance_migrated_domains(MINUTES_PER_DAY - 1, &BTreeMap::new()).unwrap();
            world.clock = world.clock.after_fixed_steps(1_181).unwrap();
            world.start_land_battle(cell, LandBattle::new([0., 0.])).unwrap();
            world
        };
        let controls = LandBattleControls::default();
        let snapshot = |world: &InitialWorld| serde_json::to_vec(world.land_battle_record().unwrap()).unwrap();
        let mut continuous = open();
        continuous.advance_active_land_battle(24, Some((cell, &terrain)), controls).unwrap();
        let mut resumed = open();
        for steps in [1, 2, 4, 4, 4, 3] {
            resumed.advance_active_land_battle(steps, Some((cell, &terrain)), controls).unwrap();
        }
        assert_eq!(resumed.clock.snapshot().subminute_millis, 59_950);
        assert_eq!(resumed.macro_economy().last_settlement_hour(), 0);
        let clock_json = serde_json::to_vec(&resumed.clock.snapshot()).unwrap();
        resumed.clock = GameClock::restore(serde_json::from_slice(&clock_json).unwrap()).unwrap();
        let battle = serde_json::from_slice(&snapshot(&resumed)).unwrap();
        resumed.restore_land_battles(Some(battle), Vec::new()).unwrap();
        resumed.advance_active_land_battle(1, Some((cell, &terrain)), controls).unwrap();
        assert_eq!(resumed.clock.snapshot().total_minutes, MINUTES_PER_DAY);
        assert_eq!(resumed.clock.snapshot().subminute_millis, 0);
        assert_eq!(resumed.macro_economy().last_settlement_hour(), 24);
        let market = |world: &InitialWorld| {
            world.macro_economy().markets()["qing_empire"].commodities["potatoes"].inventory
        };
        let inventory = market(&resumed);
        for steps in [4, 1] {
            resumed.advance_active_land_battle(steps, Some((cell, &terrain)), controls).unwrap();
        }
        assert_eq!(market(&resumed), inventory);
        assert_eq!(market(&continuous), inventory);
        assert_eq!(resumed.clock, continuous.clock);
        assert_eq!(resumed.clock.snapshot().subminute_millis, 250);
        assert_eq!(resumed.land_battle().unwrap().elapsed_steps(), 24);
        assert_eq!(snapshot(&resumed), snapshot(&continuous));
        resumed.finish_land_battle();
        let mut ended: WorldLandBattle = serde_json::from_slice(&snapshot(&resumed)).unwrap();
        assert_eq!(ended.ended_subminute_millis, 250);
        resumed.advance_migrated_domains(15, &BTreeMap::new()).unwrap();
        assert_eq!(resumed.clock.snapshot().subminute_millis, 250);
        assert!(ended.restore(1, resumed.clock));
    }

    #[test]
    fn previous_rust_battle_keeps_elapsed_steps_and_uses_realtime_after_load() {
        let cell = MilitaryCell::at([4.074, 48.297], 50).unwrap();
        let terrain = BattlefieldTerrain::from_geographic_heights(50_000, vec![0.; 4], vec![4; 4]).unwrap();
        let controls = LandBattleControls::default();
        let mut legacy = WorldLandBattle {
            id: 1,
            region: cell,
            deployment_cell: Some(cell),
            started_minute: Some(0),
            ended_minute: None,
            ended_subminute_millis: 0,
            timing: None,
            pending_minutes: 2,
            battle: LandBattle::new([0., 0.]),
        };
        legacy.battle.advance_steps(20, &terrain, controls);
        let mut old = serde_json::to_value(&legacy).unwrap();
        old.as_object_mut().unwrap().remove("ended_subminute_millis");
        let mut world = WorldBootstrap::load().unwrap().create("country_fra").unwrap();
        world.advance_migrated_domains(62, &BTreeMap::new()).unwrap();
        world.restore_land_battles(Some(serde_json::from_value(old).unwrap()), vec![]).unwrap();
        world.advance_active_land_battle(4, Some((cell, &terrain)), controls).unwrap();
        assert_eq!(world.clock.snapshot().total_minutes, 62);
        assert_eq!(world.clock.snapshot().subminute_millis, 200);
        assert_eq!(world.land_battle().unwrap().elapsed_steps(), 24);
        let mut resumed: WorldLandBattle = serde_json::from_value(serde_json::to_value(world.land_battle_record()).unwrap()).unwrap();
        assert!(resumed.restore(1, world.clock));
    }
}
