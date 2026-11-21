use crate::{
    formal_ui::{Skin, BRASS, IVORY, MUTED},
    overlay::Mesh,
    ui::{Ink, Layers},
};
use glam::{Mat4, Vec2, Vec3};
use winit::{event::ElementState, keyboard::{Key, NamedKey}};
use wwo_map_lab::{
    battlefield_terrain::{BattlefieldTerrain, REGION_BOUNDS},
    land_battle::{LandBattle, LandBattleControls, LandBattleOutcome, LandTeam},
    military_grid::MilitaryCell,
};

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Scale { Region, Sector, Vehicle }

pub struct Camera {
    pub center: Vec2,
    pub span: f32,
    pub view: Scale,
    height: f32,
}

impl Camera {
    fn new(cell: MilitaryCell, center: [f32; 2], terrain: &BattlefieldTerrain) -> Self {
        let mut camera = Self { center: Vec2::from_array(center), span: 120., view: Scale::Vehicle, height: 0. };
        camera.fit_grid(if cell.size_km==25 {Scale::Sector} else {Scale::Region}, terrain);
        camera
    }

    fn fit_grid(&mut self, scale: Scale, terrain: &BattlefieldTerrain) {
        self.view = scale;
        self.span = match scale { Scale::Region => 50_000., Scale::Sector => 25_000., Scale::Vehicle => 120. };
        let center=match scale {
            Scale::Region => Vec2::splat(2500.),
            Scale::Sector => {
                let midpoint=|value|if value<2500. {-10_000.}else{15_000.};
                Vec2::new(midpoint(self.center.x),midpoint(self.center.y))
            }
            Scale::Vehicle => self.center,
        };
        self.set_center(center, terrain);
    }

    fn set_scale(&mut self, scale: Scale, battle: &LandBattle, terrain: &BattlefieldTerrain) {
        if scale==Scale::Vehicle || self.view!=Scale::Sector {
            if let Some(unit)=battle.selected_unit().or_else(||battle.units.first()) {
                self.center=Vec2::from_array(unit.position);
            }
        }
        self.fit_grid(scale, terrain);
    }

    fn set_center(&mut self, center: Vec2, terrain: &BattlefieldTerrain) {
        let [west, south, east, north] = REGION_BOUNDS.map(|value| value as f32);
        let margin = if self.view == Scale::Vehicle { 0. } else { self.span * 0.5 };
        self.center = center.clamp(Vec2::new(west + margin, south + margin), Vec2::new(east - margin, north - margin));
        self.height = ground(terrain, self.center).unwrap_or(0.);
    }

    pub fn view_projection(&self, [width, height]: [u32; 2]) -> Mat4 {
        let aspect = width.max(1) as f32 / height.max(1) as f32;
        let target = Vec3::new(self.center.x, self.height, self.center.y);
        if self.view == Scale::Vehicle {
            let fov = 48_f32.to_radians();
            let distance = self.span / (2. * (fov * 0.5).tan());
            let offset = Vec3::new(0., 0.56, 0.83) * distance;
            return Mat4::perspective_rh(fov, aspect, 0.65, self.span * 8.)
                * Mat4::look_at_rh(target + offset, target, Vec3::Y);
        }
        let safe_height = (height as f32 - 176.).max(1.);
        let half = self.span * 0.51 * height as f32 / safe_height;
        let (x, y) = (half * aspect.max(1.), half / aspect.min(1.));
        let offset = Vec3::new(0., 1.2, 0.10) * self.span;
        Mat4::orthographic_rh(-x, x, -y, y, 1., self.span * 3.) * Mat4::look_at_rh(target + offset, target, Vec3::Y)
    }

    fn point_at(&self, pixel: [f64; 2], size: [u32; 2], terrain: &BattlefieldTerrain) -> Option<[f32; 2]> {
        let [x, y] = pixel.map(|value| value as f32);
        let ndc = Vec2::new(2. * x / size[0] as f32 - 1., 1. - 2. * y / size[1] as f32);
        let inverse = self.view_projection(size).inverse();
        let top = inverse.project_point3(ndc.extend(0.));
        let bottom = inverse.project_point3(ndc.extend(1.));
        let mut previous = 0.;
        for step in 0..=64 {
            let progress = step as f32 / 64.;
            let point = top.lerp(bottom, progress);
            if ground(terrain, Vec2::new(point.x, point.z)).is_some_and(|height| point.y <= height) {
                let mut low = previous;
                let mut high = progress;
                for _ in 0..8 {
                    let middle = (low + high) * 0.5;
                    let point = top.lerp(bottom, middle);
                    if ground(terrain, Vec2::new(point.x, point.z)).is_some_and(|height| point.y <= height) {
                        high = middle;
                    } else {
                        low = middle;
                    }
                }
                let hit = top.lerp(bottom, high);
                return Some([hit.x, hit.z]);
            }
            previous = progress;
        }
        None
    }
}

fn ground(terrain: &BattlefieldTerrain, point: Vec2) -> Option<f32> {
    terrain.sample(f64::from(point.x), f64::from(point.y)).map(|sample| sample.height_m as f32)
}

#[derive(Clone, Copy)]
pub enum Command { View(Scale), Back, End, Next }

#[derive(Default)]
struct Held {
    forward: bool,
    reverse: bool,
    left: bool,
    right: bool,
    gun_left: bool,
    gun_right: bool,
    fire: bool,
}

pub struct View {
    pub camera: Camera,
    region: MilitaryCell,
    held: Held,
    aim: Option<[f32; 2]>,
    pointer_fire: bool,
    queued_fire: bool,
}

impl View {
    pub fn new(terrain: &BattlefieldTerrain, cell: MilitaryCell, center: [f32; 2]) -> Self {
        Self { camera: Camera::new(cell, center, terrain), region: cell.region(), held: Held::default(), aim: None, pointer_fire: false, queued_fire: false }
    }

    pub fn clear_controls(&mut self) {
        self.held = Held::default();
        self.pointer_fire = false;
        self.queued_fire = false;
        self.aim = None;
    }

    fn controls(&self) -> LandBattleControls {
        let axis = |positive, negative| f32::from(u8::from(positive)) - f32::from(u8::from(negative));
        LandBattleControls {
            manual: true,
            throttle: axis(self.held.forward, self.held.reverse),
            turn: axis(self.held.right, self.held.left),
            turret: axis(self.held.gun_right, self.held.gun_left),
            aim: self.aim,
            fire: self.pointer_fire || self.held.fire || self.queued_fire,
        }
    }

    pub fn advance(&mut self, battle: &mut LandBattle, elapsed: f32, terrain: &BattlefieldTerrain) {
        let before = battle.selected_unit().map(|unit| (unit.id, unit.ammo));
        battle.advance(elapsed, terrain, self.controls());
        let after = battle.selected_unit().map(|unit| (unit.id, unit.ammo));
        if before != after || after.is_none_or(|(_, ammo)| ammo == 0) {
            self.queued_fire = false;
        }
        self.follow(battle, terrain);
    }

    fn follow(&mut self, battle: &LandBattle, terrain: &BattlefieldTerrain) {
        if self.camera.view == Scale::Vehicle {
            if let Some(unit) = battle.selected_unit() {
                self.camera.set_center(Vec2::from_array(unit.position), terrain);
            }
        }
    }

    pub fn zoom(&mut self, steps: f64) {
        if self.camera.view == Scale::Vehicle {
            self.camera.span = (self.camera.span * 0.82_f32.powf(steps as f32)).clamp(45., 1800.);
        }
    }

    pub fn key(&mut self, key: Key, state: ElementState, repeat: bool, terrain: &BattlefieldTerrain) -> Option<Command> {
        let down = state == ElementState::Pressed;
        match key.as_ref() {
            Key::Character("w" | "W") => self.held.forward = down,
            Key::Character("s" | "S") => self.held.reverse = down,
            Key::Character("a" | "A") => self.held.left = down,
            Key::Character("d" | "D") => self.held.right = down,
            Key::Character("q" | "Q") => { self.aim = None; self.held.gun_left = down; }
            Key::Character("e" | "E") => { self.aim = None; self.held.gun_right = down; }
            Key::Named(NamedKey::Space) => { self.held.fire = down; self.queued_fire |= down; }
            Key::Named(NamedKey::ArrowLeft | NamedKey::ArrowRight | NamedKey::ArrowUp | NamedKey::ArrowDown) if down => {
                let direction = match key {
                    Key::Named(NamedKey::ArrowLeft) => Vec2::NEG_X,
                    Key::Named(NamedKey::ArrowRight) => Vec2::X,
                    Key::Named(NamedKey::ArrowUp) => Vec2::NEG_Y,
                    _ => Vec2::Y,
                };
                if self.camera.view == Scale::Sector {
                    self.camera.set_center(self.camera.center + direction * 25_000., terrain);
                }
            }
            _ if !down || repeat => (),
            Key::Named(NamedKey::Escape) => return Some(Command::Back),
            Key::Named(NamedKey::Tab) => return Some(Command::Next),
            Key::Character("1") => return Some(Command::View(Scale::Region)),
            Key::Character("2") => return Some(Command::View(Scale::Sector)),
            Key::Character("3") => return Some(Command::View(Scale::Vehicle)),
            _ => (),
        }
        None
    }

    pub fn command(&mut self, command: Command, battle: &mut LandBattle, terrain: &BattlefieldTerrain) {
        match command {
            Command::View(scale) => self.camera.set_scale(scale, battle, terrain),
            Command::Next => {
                battle.select_next();
                self.aim = None;
                self.queued_fire = false;
                self.follow(battle, terrain);
            }
            Command::End => battle.conclude(),
            Command::Back => (),
        }
    }

    pub fn left_button(&mut self, down: bool, pixel: [f64; 2], size: [u32; 2], terrain: &BattlefieldTerrain) -> Option<Command> {
        if !down {
            self.pointer_fire = false;
            return None;
        }
        let [x, y] = pixel.map(|value| value as f32);
        for ([left, top, width, height], _, command) in buttons(size) {
            if (left..=left + width).contains(&x) && (top..=top + height).contains(&y) {
                return Some(command);
            }
        }
        if y > 86. && y < size[1] as f32 - 74. && self.camera.view == Scale::Vehicle {
            self.aim = self.camera.point_at(pixel, size, terrain);
            self.pointer_fire = self.aim.is_some();
            self.queued_fire |= self.pointer_fire;
        }
        None
    }

    pub fn aim(&mut self, pixel: [f64; 2], size: [u32; 2], terrain: &BattlefieldTerrain) {
        if self.pointer_fire {
            self.aim = self.camera.point_at(pixel, size, terrain);
        }
    }

    pub fn order(&self, pixel: [f64; 2], size: [u32; 2], battle: &mut LandBattle, terrain: &BattlefieldTerrain) {
        if (86.0..size[1] as f64 - 74.).contains(&pixel[1]) {
            if let Some(point) = self.camera.point_at(pixel, size, terrain) {
                battle.order_selected_formation(point);
            }
        }
    }
}

fn buttons([width, _]: [u32; 2]) -> [([f32; 4], &'static str, Command); 6] {
    [
        ([16., 47., 102., 30.], "1  50 km", Command::View(Scale::Region)),
        ([124., 47., 102., 30.], "2  25 km", Command::View(Scale::Sector)),
        ([232., 47., 110., 30.], "3  Vehicle", Command::View(Scale::Vehicle)),
        ([348., 47., 114., 30.], "Tab  Next", Command::Next),
        ([width as f32 - 239., 47., 98., 30.], "End battle", Command::End),
        ([width as f32 - 135., 47., 119., 30.], "Esc  World", Command::Back),
    ]
}

pub fn hud(
    size: [u32; 2], skin: &Skin, view: &View, battle: &LandBattle, terrain: &BattlefieldTerrain,
    original_model: bool, fps: Option<f64>,
) -> Layers {
    let [width, height] = size.map(|value| value as f32);
    let mut layers = std::array::from_fn(|_| (Mesh::default(), Ink::Solid));
    layers[12].1 = Ink::HudText;
    let (solid, text) = layers.split_at_mut(12);
    let solid = &mut solid[6].0;
    let text = &mut text[0].0;
    let panel = [13, 21, 23, 239];
    solid.rect(0., 0., width, 87., panel);
    solid.rect(0., height - 74., width, 74., panel);
    let blue = battle.report(LandTeam::Friendly);
    let red = battle.report(LandTeam::Opposing);
    let headline = format!("{}   {:02}:{:02}   Blue {}   Red {}", view.region.id(),
        battle.elapsed_seconds as u32 / 60, battle.elapsed_seconds as u32 % 60,
        blue.operational, red.operational);
    let heading = if let Some(fps) = fps { format!("{headline}   {fps:.1} FPS") } else { headline };
    skin.text(text, &heading, 0, [16., 13.], width - 32., IVORY);
    for ([x, y, w, h], label, command) in buttons(size) {
        let color = if matches!(command, Command::View(scale) if scale == view.camera.view) { BRASS } else { [60, 74, 70, 255] };
        solid.rect(x, y, w, h, color);
        skin.text(text, label, 0, [x + 8., y + 5.], w - 12., IVORY);
    }
    let status = if let Some(outcome) = battle.outcome {
        match outcome {
            LandBattleOutcome::FriendlyVictory => "Blue victory",
            LandBattleOutcome::OpposingVictory => "Red victory",
            LandBattleOutcome::Disengaged => "Battle ended",
            LandBattleOutcome::Draw => "Draw",
        }.to_owned()
    } else if let Some(unit) = battle.selected_unit() {
        format!("Unit {}   Group {}   {:.0} km/h   Health {}   Ammo {}",
            unit.id.0, unit.formation, unit.speed * 3.6, unit.health, unit.ammo)
    } else {
        "No controllable vehicles".into()
    };
    skin.text(text, &status, 0, [16., height - 66.], width - 32., IVORY);
    let detail = if battle.outcome.is_some() {
        format!("Blue lost {} / ammo {} / hits {}   Red lost {} / ammo {} / hits {}",
            blue.destroyed, blue.ammunition, blue.hits, red.destroyed, red.ammunition, red.hits)
    } else {
        "WASD drive   Q/E turret   Space/left fire   Right order   Wheel zoom   Arrows pan 25 km".into()
    };
    skin.text(text, &detail, 0, [16., height - 44.], width - 32., MUTED);
    if !original_model {
        skin.text(text, "Vehicle asset unavailable", 0, [16., height - 22.], width - 32., MUTED);
    }
    let matrix = view.camera.view_projection(size);
    let current = battle.selected_unit().map(|unit| unit.id);
    for unit in &battle.units {
        if unit.health == 0 { continue; }
        let Some(y) = ground(terrain, Vec2::from_array(unit.position)) else { continue; };
        let ndc = matrix.project_point3(Vec3::new(unit.position[0], y + 4., unit.position[1]));
        let x = (ndc.x + 1.) * width * 0.5;
        let y = (1. - ndc.y) * height * 0.5;
        if !(0.0..=1.).contains(&ndc.z) || !(-1.0..=1.).contains(&ndc.x) || !(89.0..height - 76.).contains(&y) { continue; }
        let color = if unit.team == LandTeam::Friendly { [102, 181, 230, 255] } else { [221, 108, 84, 255] };
        if current == Some(unit.id) { solid.rect(x - 5., y - 6., 10., 8., IVORY); }
        solid.rect(x - 3., y - 4., 6., 4., color);
    }
    layers
}
