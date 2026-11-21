use super::{invalid, InitialWorld};
use crate::{
    battlefield_terrain::BattlefieldTerrain,
    land_battle::{LandBattle, LandBattleControls, WORLD_MINUTES_PER_STEP},
    military_grid::MilitaryCell,
};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io};

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
    pending_minutes: i64,
    pub battle: LandBattle,
}

impl WorldLandBattle {
    pub fn cell(&self) -> MilitaryCell { self.deployment_cell.unwrap_or(self.region) }

    fn advance(&mut self, from: i64, minutes: i64, terrain: &BattlefieldTerrain, controls: LandBattleControls) {
        let previous_steps = self.battle.elapsed_steps();
        let previous_remainder = self.pending_minutes;
        let aligned_minutes = minutes + previous_remainder;
        self.pending_minutes = aligned_minutes % WORLD_MINUTES_PER_STEP;
        self.battle.advance_steps((aligned_minutes / WORLD_MINUTES_PER_STEP) as u64, terrain, controls);
        if self.battle.outcome.is_some() {
            let steps = (self.battle.elapsed_steps() - previous_steps) as i64;
            self.ended_minute = Some(from + steps * WORLD_MINUTES_PER_STEP - previous_remainder);
            self.pending_minutes = 0;
        }
    }

    fn restore(&mut self, expected_id: u64, minute: i64) -> bool {
        if self.id == 0 && self.started_minute.is_none() { self.id = expected_id; }
        self.id == expected_id
            && self.region.is_valid() && self.region == self.region.region()
            && self.cell().is_valid() && self.cell().region() == self.region
            && (0..WORLD_MINUTES_PER_STEP).contains(&self.pending_minutes)
            && self.battle.restore_elapsed_steps()
            && self.ended_minute.is_none_or(|end| (0..=minute).contains(&end) && self.battle.outcome.is_some())
            && self.started_minute.is_none_or(|start| {
                let through = self.ended_minute.unwrap_or(minute);
                (0..=through).contains(&start)
                    && self.battle.outcome.is_some() == self.ended_minute.is_some()
                    && (through - start) / WORLD_MINUTES_PER_STEP == self.battle.elapsed_steps() as i64
                    && (through - start) % WORLD_MINUTES_PER_STEP == self.pending_minutes
            })
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
            pending_minutes: 0,
            battle,
        });
        Ok(())
    }

    pub fn finish_land_battle(&mut self) {
        if let Some(state) = &mut self.land_battle {
            if state.battle.outcome.is_none() {
                state.battle.conclude();
                state.ended_minute = Some(self.clock.snapshot().total_minutes);
            }
        }
    }

    pub fn advance_live_minutes(
        &mut self, minutes: i64, terrain: Option<(MilitaryCell, &BattlefieldTerrain)>, controls: LandBattleControls,
    ) -> io::Result<()> {
        let terrain = if self.land_battle_in_progress() {
            let region = self.land_battle_region().unwrap();
            Some(terrain.filter(|(cell, _)| *cell == region).map(|(_, terrain)| terrain)
                .ok_or_else(|| io::Error::other("active land exercise terrain unavailable"))?)
        } else { None };
        let from = self.clock.snapshot().total_minutes;
        let result = self.advance_migrated_domains(minutes, &BTreeMap::new());
        let advanced = self.clock.snapshot().total_minutes - from;
        if let (Some(state), Some(terrain)) = (&mut self.land_battle, terrain) {
            // Settlement may fail after reaching a travel or calendar boundary.
            // Tactical time consumes only the minutes the world actually reached.
            state.advance(from, advanced, terrain, controls);
        }
        result
    }

    pub(super) fn restore_land_battles(
        &mut self, mut current: Option<WorldLandBattle>, mut history: Vec<WorldLandBattle>,
    ) -> io::Result<()> {
        let minute = self.clock.snapshot().total_minutes;
        for (index, battle) in history.iter_mut().chain(current.iter_mut()).enumerate() {
            if !battle.restore(index as u64 + 1, minute) { return Err(invalid("invalid saved land battle")); }
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

    #[test]
    fn world_minutes_preserve_battle_state_across_batches_and_restore() {
        let cell = MilitaryCell::at([4.074, 48.297], 50).unwrap();
        let terrain = BattlefieldTerrain::from_geographic_heights(50_000, vec![0.; 4], vec![4; 4]).unwrap();
        let controls = LandBattleControls::default();
        let initial = WorldLandBattle {
            id: 1,
            region: cell,
            deployment_cell: Some(cell),
            started_minute: Some(0),
            ended_minute: None,
            pending_minutes: 0,
            battle: LandBattle::new([0., 0.]),
        };
        let snapshot = |record: &WorldLandBattle| serde_json::to_vec(record).unwrap();
        let mut continuous: WorldLandBattle = serde_json::from_slice(&snapshot(&initial)).unwrap();
        continuous.advance(0, 2_701, &terrain, controls);
        let mut resumed = initial;
        resumed.advance(0, 202, &terrain, controls);
        resumed = serde_json::from_slice(&snapshot(&resumed)).unwrap();
        assert!(resumed.restore(1, 202));
        let mut minute = 202;
        for duration in [5, 803, 1_691] {
            if resumed.battle.outcome.is_none() {
                resumed.advance(minute, duration, &terrain, controls);
            }
            minute += duration;
        }
        assert!(continuous.battle.outcome.is_some());
        assert!(resumed.restore(1, minute));
        assert_eq!(snapshot(&continuous), snapshot(&resumed));
    }
}
