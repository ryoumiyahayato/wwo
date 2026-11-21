use crate::battlefield_terrain::{BattlefieldTerrain, REGION_BOUNDS};
use glam::{Vec2, Vec3};
use serde::{Deserialize, Serialize};

// Fictional training rules. Distances and rates tune the game scenario.
const STEPS_PER_SECOND: u16 = 1000 / crate::formal_clock::FIXED_STEP_MILLIS as u16;
const STEP: f32 = 1.0 / STEPS_PER_SECOND as f32;
pub const TICK_INTERVAL: std::time::Duration = std::time::Duration::from_millis(crate::formal_clock::FIXED_STEP_MILLIS);
const VEHICLES_PER_FORMATION: usize = 5;
const FORMATION_COUNT: usize = 4;
const UNIT_COUNT: usize = FORMATION_COUNT * VEHICLES_PER_FORMATION;
const HEALTH: u8 = 100;
const AMMO: u8 = 12;
const HIT_DAMAGE: u8 = 30;
const FORWARD_SPEED: f32 = 13.0;
const REVERSE_SPEED: f32 = 5.0;
const BODY_TURN_RATE: f32 = 1.2;
const TURRET_TURN_RATE: f32 = 1.8;
const FIRE_INTERVAL: f32 = 2.2;
const SHOT_SPEED: f32 = 145.0;
const SHOT_DURATION: f32 = 4.0;
const ENGAGE_DISTANCE: f32 = 310.0;
const AIM_HEIGHT: f32 = 1.4;
const BODY_RADIUS: f32 = 2.25;
const IDLE_DISENGAGEMENT_STEPS: u16 = 120 * STEPS_PER_SECOND;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct UnitId(pub u32);

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum LandTeam {
    Friendly,
    Opposing,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct LandUnit {
    pub id: UnitId,
    pub team: LandTeam,
    pub formation: u8,
    pub position: [f32; 2],
    pub heading: f32,
    pub turret_heading: f32,
    pub speed: f32,
    pub health: u8,
    pub ammo: u8,
    reload: f32,
    hits: u8,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct LandProjectile {
    pub position: [f32; 3],
    pub previous_position: [f32; 3],
    pub team: LandTeam,
    source: UnitId,
    velocity: [f32; 3],
    remaining: f32,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum LandBattleOutcome {
    FriendlyVictory,
    OpposingVictory,
    Disengaged,
    Draw,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct LandBattle {
    pub units: Vec<LandUnit>,
    pub projectiles: Vec<LandProjectile>,
    #[serde(default)]
    elapsed_steps: u64,
    #[serde(default, rename = "elapsed_seconds", skip_serializing_if = "Option::is_none")]
    legacy_elapsed_seconds: Option<f32>,
    pub outcome: Option<LandBattleOutcome>,
    selected: UnitId,
    destinations: [Option<[f32; 2]>; FORMATION_COUNT],
    #[serde(default)]
    idle_steps: u16,
}

#[derive(Clone, Copy, Default)]
pub struct LandBattleControls {
    pub manual: bool,
    pub throttle: f32,
    pub turn: f32,
    pub turret: f32,
    pub aim: Option<[f32; 2]>,
    pub fire_held: bool,
    pub fire_once: bool,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct LandForceReport {
    pub operational: usize,
    pub destroyed: usize,
    pub ammunition: u32,
    pub shots: u32,
    pub hits: u32,
}

#[derive(Clone, Copy, Default)]
struct UnitOrder {
    throttle: f32,
    turn: f32,
    aim_heading: Option<f32>,
    aim: Option<Vec2>,
    fire: bool,
}

impl LandBattle {
    pub fn new(center: [f32; 2]) -> Self {
        // Leave room for each formation when deployment is near a cell edge.
        let [min_x, min_z, max_x, max_z] = REGION_BOUNDS.map(|edge| edge as f32);
        let center = Vec2::from_array(center);
        let deployment = if center.is_finite() {
            center
        } else {
            Vec2::ZERO
        }
        .clamp(
            Vec2::new(min_x + 300.0, min_z + 300.0),
            Vec2::new(max_x - 300.0, max_z - 300.0),
        );
        let mut units = Vec::with_capacity(UNIT_COUNT);
        for formation in 0..FORMATION_COUNT {
            let team = formation_team(formation);
            let friendly = team == LandTeam::Friendly;
            let heading = if friendly { 0.0 } else { std::f32::consts::PI };
            let center = Vec2::new(
                if formation % 2 == 0 { -105.0 } else { 105.0 },
                if friendly { -245.0 } else { 245.0 },
            );
            for slot in 0..VEHICLES_PER_FORMATION {
                let position = deployment + center + formation_offset(formation, slot);
                units.push(LandUnit {
                    id: UnitId((units.len() + 1) as u32),
                    team,
                    formation: formation as u8,
                    position: position.to_array(),
                    heading,
                    turret_heading: heading,
                    speed: 0.0,
                    health: HEALTH,
                    ammo: AMMO,
                    reload: slot as f32 * 0.2,
                    hits: 0,
                });
            }
        }
        Self {
            units,
            projectiles: Vec::new(),
            elapsed_steps: 0,
            legacy_elapsed_seconds: None,
            outcome: None,
            selected: UnitId(1),
            destinations: [None; FORMATION_COUNT],
            idle_steps: 0,
        }
    }

    pub fn selected_unit(&self) -> Option<&LandUnit> {
        self.units
            .iter()
            .find(|unit| unit.id == self.selected && unit.health > 0)
    }

    pub fn selected_ammunition(&self) -> Option<(UnitId, u8)> {
        self.selected_unit().and_then(|unit| (unit.ammo > 0).then_some((unit.id, unit.ammo)))
    }

    pub fn select_next(&mut self) {
        let available = |unit: &&LandUnit| unit.team == LandTeam::Friendly && unit.health > 0;
        let next = self
            .units
            .iter()
            .filter(available)
            .find(|unit| unit.id.0 > self.selected.0)
            .or_else(|| self.units.iter().find(available));
        if let Some(unit) = next {
            self.selected = unit.id;
        }
    }

    pub fn order_selected_formation(&mut self, at: [f32; 2]) {
        if self.outcome.is_some() || !in_region(at) {
            return;
        }
        if let Some(formation) = self.selected_unit().map(|unit| unit.formation as usize) {
            self.destinations[formation] = Some(at);
        }
    }

    pub fn elapsed_steps(&self) -> u64 { self.elapsed_steps }

    pub fn elapsed_seconds(&self) -> f64 { self.elapsed_steps as f64 / f64::from(STEPS_PER_SECOND) }

    pub(crate) fn restore_elapsed_steps(&mut self) -> bool {
        if let Some(seconds) = self.legacy_elapsed_seconds.take() {
            if !seconds.is_finite() || seconds < 0.0 || self.elapsed_steps != 0 { return false; }
            // Early native saves used a float timer. Keep at least the known idle steps.
            self.elapsed_steps = (f64::from(seconds) * f64::from(STEPS_PER_SECOND)).round() as u64;
            self.elapsed_steps = self.elapsed_steps.max(u64::from(self.idle_steps));
        }
        self.validate()
    }

    pub(crate) fn advance_steps(
        &mut self, steps: u64, terrain: &BattlefieldTerrain, mut controls: LandBattleControls,
    ) -> LandBattleControls {
        let fire_source = controls.fire_once.then(|| self.selected_ammunition()).flatten();
        for _ in 0..steps {
            if self.outcome.is_some() { break; }
            self.elapsed_steps += 1;
            self.step(terrain, controls);
            if controls.fire_once && (fire_source.is_none() || fire_source != self.selected_ammunition()) {
                controls.fire_once = false;
            }
        }
        controls
    }

    pub fn conclude(&mut self) {
        if self.outcome.is_none() {
            self.finish(LandBattleOutcome::Disengaged);
        }
    }

    pub fn report(&self, team: LandTeam) -> LandForceReport {
        let mut report = LandForceReport::default();
        for unit in self.units.iter().filter(|unit| unit.team == team) {
            if unit.health > 0 {
                report.operational += 1;
                report.ammunition += u32::from(unit.ammo);
            } else {
                report.destroyed += 1;
            }
            report.shots += u32::from(AMMO - unit.ammo);
            report.hits += u32::from(unit.hits);
        }
        report
    }

    pub fn validate(&self) -> bool {
        self.units.len() == UNIT_COUNT
            && (1..=UNIT_COUNT as u32 / 2).contains(&self.selected.0)
            && self.idle_steps <= IDLE_DISENGAGEMENT_STEPS
            && (self.idle_steps < IDLE_DISENGAGEMENT_STEPS || self.outcome.is_some())
            && u64::from(self.idle_steps) <= self.elapsed_steps
            && self.destinations.iter().flatten().copied().all(in_region)
            && self.units.iter().enumerate().all(|(index, unit)| {
                let formation = index / VEHICLES_PER_FORMATION;
                unit.id == UnitId((index + 1) as u32)
                    && unit.formation as usize == formation
                    && unit.team == formation_team(formation)
                    && in_region(unit.position)
                    && unit.heading.is_finite()
                    && unit.turret_heading.is_finite()
                    && (-REVERSE_SPEED..=FORWARD_SPEED).contains(&unit.speed)
                    && unit.health <= HEALTH
                    && unit.ammo <= AMMO
                    && unit.hits <= AMMO - unit.ammo
                    && (0.0..=FIRE_INTERVAL).contains(&unit.reload)
                    && (unit.health > 0 || unit.speed == 0.0)
            })
            && self.projectiles.len() <= UNIT_COUNT * usize::from(AMMO)
            && self.projectiles.iter().all(|shot| {
                self.units
                    .iter()
                    .any(|unit| unit.id == shot.source && unit.team == shot.team)
                    && in_region([shot.position[0], shot.position[2]])
                    && shot.position[1].is_finite()
                    && in_region([shot.previous_position[0], shot.previous_position[2]])
                    && shot.previous_position[1].is_finite()
                    && (SHOT_SPEED - 0.1..=SHOT_SPEED + 0.1)
                        .contains(&Vec3::from_array(shot.velocity).length())
                    && (0.0..=SHOT_DURATION).contains(&shot.remaining)
            })
            && self.outcome.is_none_or(|outcome| {
                let friendly = self.report(LandTeam::Friendly);
                let opposing = self.report(LandTeam::Opposing);
                self.projectiles.is_empty() && match outcome {
                        LandBattleOutcome::FriendlyVictory => {
                            friendly.operational > 0 && opposing.operational == 0
                        }
                        LandBattleOutcome::OpposingVictory => {
                            friendly.operational == 0 && opposing.operational > 0
                        }
                        LandBattleOutcome::Disengaged => true,
                        LandBattleOutcome::Draw => {
                            (friendly.operational == 0 && opposing.operational == 0)
                                || (friendly.ammunition == 0 && opposing.ammunition == 0)
                        }
                    }
            })
    }

    fn finish(&mut self, outcome: LandBattleOutcome) {
        self.outcome = Some(outcome);
        self.projectiles.clear();
        for unit in &mut self.units {
            unit.speed = 0.0;
        }
    }

    fn step(&mut self, terrain: &BattlefieldTerrain, controls: LandBattleControls) {
        let mut orders = [UnitOrder::default(); UNIT_COUNT];
        for (index, unit) in self
            .units
            .iter()
            .enumerate()
            .filter(|(_, unit)| unit.health > 0)
        {
            orders[index] = self.unit_order(index, unit, terrain, controls);
        }
        let mut moved = false;
        for (index, order) in orders.into_iter().enumerate() {
            if self.units[index].health == 0 {
                continue;
            }
            moved |= self.move_unit(index, order, terrain);
            self.fire(index, order, terrain);
        }
        self.idle_steps = if moved || !self.projectiles.is_empty() {
            0
        } else {
            self.idle_steps + 1
        };
        self.update_projectiles(terrain);
        if self.selected_unit().is_none() {
            self.select_next();
        }
        let friendly = self.report(LandTeam::Friendly);
        let opposing = self.report(LandTeam::Opposing);
        if self.projectiles.is_empty() {
            match (friendly.operational, opposing.operational) {
                (0, 0) => self.finish(LandBattleOutcome::Draw),
                (_, 0) => self.finish(LandBattleOutcome::FriendlyVictory),
                (0, _) => self.finish(LandBattleOutcome::OpposingVictory),
                _ if friendly.ammunition == 0 && opposing.ammunition == 0 => {
                    self.finish(LandBattleOutcome::Draw)
                }
                _ if self.idle_steps >= IDLE_DISENGAGEMENT_STEPS => {
                    self.finish(LandBattleOutcome::Disengaged)
                }
                _ => {}
            }
        }
    }

    fn unit_order(
        &self,
        index: usize,
        unit: &LandUnit,
        terrain: &BattlefieldTerrain,
        controls: LandBattleControls,
    ) -> UnitOrder {
        let position = Vec2::from_array(unit.position);
        let formation = unit.formation as usize;
        let offset = formation_offset(formation, index % VEHICLES_PER_FORMATION);
        let ordered = self.destinations[formation].map(|point| {
            let [west, south, east, north] = REGION_BOUNDS.map(|edge| edge as f32);
            (Vec2::from_array(point) + offset).clamp(Vec2::new(west, south), Vec2::new(east, north))
        });
        if controls.manual && unit.id == self.selected {
            let aim = controls
                .aim
                .filter(|point| in_region(*point))
                .map(Vec2::from_array);
            let aim_heading = aim
                .filter(|point| point.distance_squared(position) > 0.25)
                .map(|point| bearing(point - position))
                .or_else(|| {
                    Some(unit.turret_heading + axis(controls.turret) * TURRET_TURN_RATE * STEP)
                });
            let mut order = if axis(controls.throttle) != 0.0 || axis(controls.turn) != 0.0 {
                UnitOrder {
                    throttle: axis(controls.throttle),
                    turn: axis(controls.turn),
                    ..Default::default()
                }
            } else {
                ordered.map_or_else(UnitOrder::default, |point| drive_toward(unit, point))
            };
            order.aim_heading = aim_heading;
            order.aim = aim;
            order.fire = controls.fire_held || controls.fire_once;
            return order;
        }

        let target = self
            .units
            .iter()
            .filter(|other| other.team != unit.team && other.health > 0)
            .map(|other| Vec2::from_array(other.position))
            .min_by(|left, right| {
                left.distance_squared(position)
                    .total_cmp(&right.distance_squared(position))
            });
        let Some(target) = target else {
            return ordered.map_or_else(UnitOrder::default, |point| drive_toward(unit, point));
        };
        let visible = position.distance_squared(target) < ENGAGE_DISTANCE * ENGAGE_DISTANCE
            && clear_shot(terrain, position, target);
        let destination = ordered.or_else(|| (!visible).then_some(target + offset));
        let mut order =
            destination.map_or_else(UnitOrder::default, |point| drive_toward(unit, point));
        order.aim_heading = Some(bearing(target - position));
        order.aim = Some(target);
        order.fire = visible;
        order
    }

    fn move_unit(&mut self, index: usize, order: UnitOrder, terrain: &BattlefieldTerrain) -> bool {
        let unit = &self.units[index];
        let position = Vec2::from_array(unit.position);
        let heading = wrap(unit.heading + order.turn * BODY_TURN_RATE * STEP);
        let maximum = if order.throttle < 0.0 {
            REVERSE_SPEED
        } else {
            FORWARD_SPEED
        };
        let target_speed = order.throttle * maximum;
        let speed = approach(unit.speed, target_speed, 7.0 * STEP);
        let next = position + direction(heading) * speed * STEP;
        let ground_clear = terrain.ground_is_land(f64::from(next.x), f64::from(next.y))
            && height(terrain, position)
                .zip(height(terrain, next))
                .is_some_and(|(from, to)| {
                    (to - from).abs() <= (next - position).length() * 0.75 + 0.12
                });
        let body_clear = self.units.iter().enumerate().all(|(other_index, other)| {
            if other_index == index {
                return true;
            }
            let obstacle = Vec2::from_array(other.position);
            let distance = next.distance_squared(obstacle);
            distance >= (2.0 * BODY_RADIUS).powi(2)
                || distance >= position.distance_squared(obstacle)
        });
        let unit = &mut self.units[index];
        unit.heading = heading;
        unit.reload = (unit.reload - STEP).max(0.0);
        if ground_clear && body_clear {
            unit.position = next.to_array();
            unit.speed = speed;
        } else {
            unit.speed = 0.0;
        }
        if let Some(aim) = order.aim_heading {
            let turn = wrap(aim - unit.turret_heading)
                .clamp(-TURRET_TURN_RATE * STEP, TURRET_TURN_RATE * STEP);
            unit.turret_heading = wrap(unit.turret_heading + turn);
        }
        unit.position != position.to_array()
    }

    fn fire(&mut self, index: usize, order: UnitOrder, terrain: &BattlefieldTerrain) {
        let unit = &mut self.units[index];
        if !order.fire || unit.ammo == 0 || unit.reload > 0.0 {
            return;
        }
        if order
            .aim_heading
            .is_some_and(|aim| wrap(aim - unit.turret_heading).abs() > 0.025)
        {
            return;
        }
        let position = Vec2::from_array(unit.position);
        let Some(y) = height(terrain, position) else {
            return;
        };
        let horizontal = direction(unit.turret_heading);
        let slope = order
            .aim
            .and_then(|target| height(terrain, target).map(|target_y| (target, target_y)))
            .map_or(0.0, |(target, target_y)| {
                (target_y - y) / (target - position).length().max(3.0)
            });
        let velocity = Vec3::new(horizontal.x, slope, horizontal.y).normalize() * SHOT_SPEED;
        let origin = [position.x, y + AIM_HEIGHT, position.y];
        unit.ammo -= 1;
        unit.reload = FIRE_INTERVAL;
        self.projectiles.push(LandProjectile {
            position: origin,
            previous_position: origin,
            team: unit.team,
            source: unit.id,
            velocity: velocity.to_array(),
            remaining: SHOT_DURATION,
        });
    }

    fn update_projectiles(&mut self, terrain: &BattlefieldTerrain) {
        let units = &mut self.units;
        self.projectiles.retain_mut(|shot| {
            let from = Vec3::from_array(shot.position);
            let to = from + Vec3::from_array(shot.velocity) * STEP;
            let obstruction = terrain_intersection(terrain, from, to, 2.0).unwrap_or(1.1);
            let target = units
                .iter()
                .enumerate()
                .filter(|(_, unit)| unit.id != shot.source && unit.health > 0)
                .filter_map(|(index, unit)| {
                    let position = Vec2::from_array(unit.position);
                    let flat = Vec2::new(from.x, from.z);
                    if flat.distance_squared(position) > (SHOT_SPEED * STEP + BODY_RADIUS).powi(2) {
                        return None;
                    }
                    let y = height(terrain, position)? + AIM_HEIGHT;
                    let center = Vec3::new(position.x, y, position.y);
                    segment_body(from, to, center)
                        .filter(|hit| *hit < obstruction)
                        .map(|hit| (index, hit))
                })
                .min_by(|left, right| left.1.total_cmp(&right.1));
            if let Some((index, _)) = target {
                let target = &mut units[index];
                if target.team != shot.team {
                    target.health = target.health.saturating_sub(HIT_DAMAGE);
                    if target.health == 0 {
                        target.speed = 0.0;
                    }
                    units[shot.source.0 as usize - 1].hits += 1;
                }
                return false;
            }
            shot.previous_position = shot.position;
            shot.position = to.to_array();
            shot.remaining -= STEP;
            obstruction > 1.0 && shot.remaining > 0.0
        });
    }
}

fn formation_team(index: usize) -> LandTeam {
    if index < FORMATION_COUNT / 2 {
        LandTeam::Friendly
    } else {
        LandTeam::Opposing
    }
}

fn formation_offset(formation: usize, slot: usize) -> Vec2 {
    let flank = slot as i32 - (VEHICLES_PER_FORMATION / 2) as i32;
    let direction = if formation_team(formation) == LandTeam::Friendly {
        -1.0
    } else {
        1.0
    };
    Vec2::new(flank as f32 * 14.0, flank.abs() as f32 * 9.0 * direction)
}

fn drive_toward(unit: &LandUnit, target: Vec2) -> UnitOrder {
    let delta = target - Vec2::from_array(unit.position);
    let distance = delta.length();
    if distance < 3.0 {
        return UnitOrder::default();
    }
    let error = wrap(bearing(delta) - unit.heading);
    UnitOrder {
        throttle: error.cos().max(0.0) * (distance / 16.0).min(1.0),
        turn: (error * 1.7).clamp(-1.0, 1.0),
        ..Default::default()
    }
}

fn height(terrain: &BattlefieldTerrain, at: Vec2) -> Option<f32> {
    terrain
        .sample(f64::from(at.x), f64::from(at.y))
        .map(|sample| sample.height_m as f32)
}

fn clear_shot(terrain: &BattlefieldTerrain, from: Vec2, to: Vec2) -> bool {
    height(terrain, from)
        .zip(height(terrain, to))
        .is_some_and(|(a, b)| {
            terrain_intersection(
                terrain,
                Vec3::new(from.x, a + AIM_HEIGHT, from.y),
                Vec3::new(to.x, b + AIM_HEIGHT, to.y),
                7.0,
            )
            .is_none()
        })
}

fn terrain_intersection(
    terrain: &BattlefieldTerrain,
    from: Vec3,
    to: Vec3,
    spacing: f32,
) -> Option<f32> {
    let samples = ((to - from).length() / spacing).ceil().clamp(1.0, 128.0) as u32;
    (1..=samples).find_map(|sample| {
        let fraction = sample as f32 / samples as f32;
        let point = from.lerp(to, fraction);
        let ground = height(terrain, Vec2::new(point.x, point.z));
        ground
            .is_none_or(|elevation| point.y <= elevation)
            .then_some(fraction)
    })
}

fn segment_body(from: Vec3, to: Vec3, center: Vec3) -> Option<f32> {
    let scale = Vec3::new(BODY_RADIUS.recip(), 0.92, BODY_RADIUS.recip());
    let offset = (from - center) * scale;
    let delta = (to - from) * scale;
    let c = offset.length_squared() - 1.0;
    if c <= 0.0 {
        return Some(0.0);
    }
    let a = delta.length_squared();
    let b = offset.dot(delta);
    let discriminant = b * b - a * c;
    if discriminant < 0.0 || a <= 0.0 {
        return None;
    }
    let time = (-b - discriminant.sqrt()) / a;
    (0.0..=1.0).contains(&time).then_some(time)
}

fn in_region([x, z]: [f32; 2]) -> bool {
    let [west, south, east, north] = REGION_BOUNDS.map(|edge| edge as f32);
    (west..=east).contains(&x) && (south..=north).contains(&z)
}

fn bearing(delta: Vec2) -> f32 {
    delta.x.atan2(delta.y)
}

fn direction(heading: f32) -> Vec2 {
    Vec2::new(heading.sin(), heading.cos())
}

fn wrap(angle: f32) -> f32 {
    (angle + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU) - std::f32::consts::PI
}

fn axis(value: f32) -> f32 {
    if value.is_finite() {
        value.clamp(-1.0, 1.0)
    } else {
        0.0
    }
}

fn approach(value: f32, target: f32, step: f32) -> f32 {
    value + (target - value).clamp(-step, step)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn battle_with_projectile() -> (LandBattle, BattlefieldTerrain) {
        let terrain =
            BattlefieldTerrain::from_geographic_heights(50_000, vec![0.; 4], vec![4; 4]).unwrap();
        let mut battle = LandBattle::new([0., 0.]);
        battle.units[0].position = [0., 0.];
        battle.fire(0, UnitOrder { fire: true, ..Default::default() }, &terrain);
        assert_eq!(battle.projectiles.len(), 1);
        (battle, terrain)
    }

    #[test]
    fn projectile_hits_friendly_without_damage() {
        let (mut battle, terrain) = battle_with_projectile();
        battle.units[1].position = [0., 3.];

        battle.update_projectiles(&terrain);

        assert_eq!(battle.units[1].health, HEALTH);
        assert_eq!(battle.units[0].hits, 0);
        assert!(battle.projectiles.is_empty());
    }

    #[test]
    fn friendly_vehicle_shields_enemy_from_projectile() {
        let (mut battle, terrain) = battle_with_projectile();
        battle.units[1].position = [0., 3.];
        battle.units[UNIT_COUNT / 2].position = [0., 8.];

        battle.update_projectiles(&terrain);

        assert_eq!(battle.units[1].health, HEALTH);
        assert_eq!(battle.units[UNIT_COUNT / 2].health, HEALTH);
        assert_eq!(battle.units[0].hits, 0);
        assert!(battle.projectiles.is_empty());
    }

    #[test]
    fn projectile_damages_unshielded_enemy() {
        let (mut battle, terrain) = battle_with_projectile();
        battle.units[UNIT_COUNT / 2].position = [0., 8.];

        battle.update_projectiles(&terrain);

        assert_eq!(battle.units[UNIT_COUNT / 2].health, HEALTH - HIT_DAMAGE);
        assert_eq!(battle.units[0].hits, 1);
        assert!(battle.projectiles.is_empty());
    }

    #[test]
    fn single_fire_does_not_transfer_to_replacement_vehicle_in_a_batch() {
        let terrain = BattlefieldTerrain::from_geographic_heights(50_000, vec![0.; 4], vec![4; 4]).unwrap();
        let mut initial = LandBattle::new([0., 0.]);
        initial.units[0].health = HIT_DAMAGE;
        initial.units[1].reload = 0.;
        let source = &mut initial.units[UNIT_COUNT / 2];
        source.ammo -= 1;
        let source = source.id;
        let [x, z] = initial.units[0].position;
        let position = [x + 4., AIM_HEIGHT, z];
        initial.projectiles.push(LandProjectile {
            position,
            previous_position: position,
            team: LandTeam::Opposing,
            source,
            velocity: [-SHOT_SPEED, 0., 0.],
            remaining: SHOT_DURATION,
        });
        let idle = LandBattleControls { manual: true, ..Default::default() };
        let pulse = LandBattleControls { fire_once: true, ..idle };
        let snapshot = |battle: &LandBattle| serde_json::to_vec(battle).unwrap();
        for (reload, fired) in [(0., 1), (STEP * 2., 0)] {
            let mut batched = initial.clone();
            batched.units[0].reload = reload;
            let mut split = batched.clone();
            batched.advance_steps(4, &terrain, pulse);
            split.advance_steps(1, &terrain, pulse);
            split.advance_steps(3, &terrain, idle);
            assert_eq!(batched.units[0].health, 0);
            assert_eq!(batched.units[0].ammo, AMMO - fired);
            assert_eq!(batched.selected, batched.units[1].id);
            assert_eq!(batched.units[1].ammo, AMMO);
            assert_eq!(snapshot(&batched), snapshot(&split));
        }

        let mut reloading = LandBattle::new([0., 0.]);
        reloading.units[0].reload = STEP * 2.5;
        let mut split = reloading.clone();
        reloading.advance_steps(4, &terrain, pulse);
        split.advance_steps(2, &terrain, pulse);
        assert_eq!(split.units[0].ammo, AMMO);
        split.advance_steps(1, &terrain, pulse);
        split.advance_steps(1, &terrain, idle);
        assert_eq!(reloading.units[0].ammo, AMMO - 1);
        assert_eq!(snapshot(&reloading), snapshot(&split));

        initial.advance_steps(4, &terrain, LandBattleControls { fire_held: true, ..pulse });
        assert_eq!(initial.units[1].ammo, AMMO - 1);
    }
}
