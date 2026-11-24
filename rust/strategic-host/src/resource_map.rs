use std::collections::HashMap;

use wwo_map_lab::resource_geography::{
    Bounds, Category, Development, Directory, EntityKind, Evidence, GridCell, LandGrid,
    Resource, ResourceType,
};

use crate::{
    camera::Camera,
    formal_ui::{Display, Menu, Page},
    overlay::Mesh,
    ui::{Action, Hit, Mode},
    world::World,
};

const INK: [u8; 4] = [241, 230, 206, 255];
const SUBTLE: [u8; 4] = [190, 185, 166, 255];
const GOLD: [u8; 4] = [183, 151, 95, 255];
const DARK: [u8; 4] = [13, 23, 31, 250];

#[derive(Clone, Copy)]
pub enum Command {
    Toggle,
    Categories,
    Category(Category),
    Kind(ResourceType),
    Site(&'static str),
}

#[derive(Default)]
pub struct State {
    pub open: bool,
    category: Option<Category>,
    kind: Option<ResourceType>,
    selected: Option<Selection>,
}

enum Selection {
    Site(&'static Resource, Option<usize>),
    Grid(GridCell, Option<usize>),
    Unknown,
}

impl State {
    pub fn command(&mut self, command: Command, polity: Option<usize>) {
        match command {
            Command::Toggle => self.open = !self.open,
            Command::Categories => {
                self.category = None;
                self.kind = None;
                self.selected = None;
            }
            Command::Category(category) => {
                self.category = Some(category);
                self.kind = None;
                self.selected = None;
            }
            Command::Kind(kind) => {
                self.kind = Some(kind);
                self.selected = None;
            }
            Command::Site(id) => {
                self.selected = Directory::opening().by_id(id).map(|record| Selection::Site(record, polity));
            }
        }
    }

    pub fn anchor(command: Command) -> Option<[f64; 2]> {
        let Command::Site(id) = command else { return None; };
        Some(Directory::opening().by_id(id)?.geometry.anchor())
    }

    pub fn pick(&mut self, point: [f64; 2], polity: Option<usize>) -> bool {
        let Some(kind) = self.kind else { return false; };
        self.selected = Some(LandGrid::opening(kind).and_then(|grid| grid.at(point))
            .map_or(Selection::Unknown, |cell| Selection::Grid(cell, polity)));
        true
    }
}

pub fn available(mode: Mode, page: Page, menu: Menu, market_map: bool, transport: bool) -> bool {
    mode == Mode::Economic && page == Page::Map && menu == Menu::None && !market_map && !transport
}

pub fn bounds([width, height]: [u32; 2]) -> [f32; 4] {
    let width = (width as f32 - 30.).clamp(200., 306.);
    [15., 110., width, (height as f32 - 202.).clamp(260., 420.)]
}

fn view(camera: &Camera, size: [u32; 2]) -> Bounds {
    let angle = camera.extent(size, 24.);
    let [lon, lat] = camera.coordinates();
    let degrees = angle.to_degrees();
    let mut bounds = Bounds::WORLD;
    bounds.south = (lat - degrees).max(-90.);
    bounds.north = (lat + degrees).min(90.);
    if lat.abs() + degrees < 90. {
        let span = (angle.sin() / lat.to_radians().cos()).clamp(0., 1.).asin().to_degrees();
        bounds.west = (lon - span + 180.).rem_euclid(360.) - 180.;
        bounds.east = (lon + span + 180.).rem_euclid(360.) - 180.;
    }
    bounds
}

fn project(camera: &Camera, point: [f64; 2], size: [u32; 2]) -> Option<[f32; 2]> {
    camera.project(point, size).map(|point| point.map(|component| component as f32))
}

fn grid_color(kind: ResourceType) -> [u8; 4] {
    match kind {
        ResourceType::AgriculturalLand => [235, 192, 93, 255],
        ResourceType::Forest => [66, 181, 133, 255],
        ResourceType::Pasture => [184, 214, 113, 255],
        _ => GOLD,
    }
}

fn draw_grid(map: &mut Mesh, camera: &Camera, size: [u32; 2], grid: &LandGrid, kind: ResourceType) {
    let level = if camera.mpp > 8_000. { 2 } else if camera.mpp > 1_800. { 1 } else { 0 };
    for cell in grid.in_view(view(camera, size), level) {
        let Some(fraction) = cell.fraction_bp else { continue; };
        let Bounds { west, south, east, north } = cell.bounds();
        let corners = [[west, north], [east, north], [east, south], [west, south]];
        let [Some(a), Some(b), Some(c), Some(d)] = corners.map(|point| project(camera, point, size)) else { continue; };
        let mut ink = grid_color(kind);
        ink[3] = (28. + 165. * (f32::from(fraction) / 10_000.).sqrt()) as u8;
        if fraction == 0 { ink = [39, 55, 62, 85]; }
        map.shape(&[a, b, c, d], ink);
    }
}

fn symbol(record: &Resource) -> [u8; 4] {
    match record.development_status {
        Development::Working => [247, 201, 109, 255],
        Development::Discovered | Development::Former => [225, 169, 135, 255],
        Development::Geological | Development::Unknown => [142, 185, 202, 255],
    }
}

fn diamond([x, y]: [f32; 2], radius: f32) -> [[f32; 2]; 4] {
    [[x, y - radius], [x + radius, y], [x, y + radius], [x - radius, y]]
}

pub fn draw_layer(state: &State, camera: &Camera, size: [u32; 2], year: i32, map: &mut Mesh, hits: &mut Vec<Hit>) {
    let Some(kind) = state.kind else { return; };
    if let Some(grid) = LandGrid::opening(kind) {
        draw_grid(map, camera, size, grid, kind);
        if let Some(Selection::Grid(cell, _)) = state.selected {
            let Bounds { west, south, east, north } = cell.bounds();
            let corners = [[west, north], [east, north], [east, south], [west, south]];
            for (a, b) in corners.iter().zip(corners.iter().cycle().skip(1)) {
                if let (Some(a), Some(b)) = (project(camera, *a, size), project(camera, *b, size)) {
                    map.line(a, b, 2., INK);
                }
            }
        }
        return;
    }
    let span = if camera.mpp > 3_500. { 44. } else { 14. };
    let mut occupied = HashMap::<_, Vec<([f32; 2], &Resource)>>::new();
    let priority = |site: &Resource| (
        site.development_status == Development::Working,
        site.evidence_status == Evidence::Confirmed,
        site.kind == EntityKind::Working,
    );
    for record in Directory::opening().in_view(kind, view(camera, size), year) {
        let Some([x, y]) = project(camera, record.geometry.anchor(), size) else { continue; };
        if x < 0. || y < 56. || x > size[0] as f32 || y > size[1].saturating_sub(53) as f32 { continue; }
        let key = ((x / span) as i32, (y / span) as i32);
        occupied.entry(key).or_default().push(([x, y], record));
    }
    let mut symbols: Vec<_> = occupied.into_iter().collect();
    symbols.sort_unstable_by_key(|(key, _)| *key);
    for (_, mut group) in symbols {
        group.sort_by(|a, b| priority(b.1).cmp(&priority(a.1)).then_with(|| a.1.resource_id.cmp(&b.1.resource_id)));
        let selected = group.iter().position(|(_, record)| {
            matches!(state.selected, Some(Selection::Site(site, _)) if site.resource_id == record.resource_id)
        });
        let count = group.len();
        let ([x, y], record) = group[selected.unwrap_or(0)];
        let next = selected.map_or(0, |i| (i + 1) % count);
        let radius = if count > 1 { 9. } else { 6. };
        map.shape(&diamond([x, y], radius + 2.), if selected.is_some() { INK } else { DARK });
        map.shape(&diamond([x, y], radius), symbol(record));
        if count > 1 || record.kind != EntityKind::Working {
            map.shape(&diamond([x, y], radius * 0.47), DARK);
        }
        hits.push(Hit {
            area: [x - radius - 4., y - radius - 4., radius * 2. + 8., radius * 2. + 8.],
            action: Action::Resources(Command::Site(&group[next].1.resource_id)),
        });
    }
}

pub fn draw_panel(state: &State, world: &World, formal: &Display<'_>, size: [u32; 2],
    year: i32, panel: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>) {
    let [x, y, w, h] = bounds(size);
    panel.rect(x, y, w, h, DARK);
    panel.rect(x, y, w, 1., GOLD);
    panel.rect(x, y + h - 1., w, 1., GOLD);
    let skin = formal.skin;
    let title = |labels: [&str; 2]| skin.choose(labels[0], labels[1]).to_owned();
    let label = |text: &mut Mesh, value: &str, dy: f32, ink| skin.text(text, value, 0, [x + 12., y + dy], w - 24., ink);
    let command = |area, name: &str, action, active, panel: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>|
        formal.row(panel, text, hits, area, name, Some(Action::Resources(action)), active);
    label(text, skin.choose("资源分布", "Resources"), 8., INK);
    command([x + w - 74., y + 7., 62., 25.], skin.choose("关闭", "Close"), Command::Toggle, false, panel, text, hits);
    let Some(category) = state.category else {
        let column = (w - 29.) * 0.5;
        for (i, category) in Category::ALL.into_iter().enumerate() {
            command([x + 12. + (column + 5.) * (i % 2) as f32, y + 42. + (i / 2) as f32 * 29., column, 25.],
                &title(category.name()), Command::Category(category), false, panel, text, hits);
        }
        return;
    };
    command([x + 12., y + 41., 83., 25.], skin.choose("类别", "Categories"), Command::Categories, false, panel, text, hits);
    skin.text(text, &title(category.name()), 0, [x + 106., y + 43.], w - 117., INK);
    let column = (w - 29.) * 0.5;
    let mut count: usize = 0;
    for (i, kind) in ResourceType::ALL.iter().copied().filter(|kind| kind.category() == category).enumerate() {
        command([x + 12. + (column + 5.) * (i % 2) as f32, y + 73. + (i / 2) as f32 * 29., column, 25.],
            &title(kind.name()), Command::Kind(kind), state.kind == Some(kind), panel, text, hits);
        count += 1;
    }
    let Some(kind) = state.kind else { return; };
    let mut dy = 79. + count.div_ceil(2) as f32 * 29.;
    let grid = LandGrid::opening(kind);
    let mut lines = Vec::new();
    if grid.is_some() {
        lines.push(skin.choose("1900 年估算 · 原始网格 0.25°", "1900 estimate · 0.25° source cells").into());
        lines.push(skin.choose("深灰：0%　透明：无资料", "Gray: 0% · Clear: no data").into());
    } else if Directory::opening().in_view(kind, Bounds::WORLD, year).next().is_some() {
        lines.push(skin.choose("空心：矿区、矿床或汇集点", "Hollow: district, deposit or cluster").into());
        lines.push(skin.choose("金色：开采　棕色：已知　蓝色：待核实", "Gold: active · Brown: known · Blue: unverified").into());
        lines.push(skin.choose("空白：未核实", "Blank: unverified").into());
    } else {
        lines.push(skin.choose("此时期暂无已纳入的记录", "No mapped records for this period").into());
    }
    let mut owner = None;
    match &state.selected {
        Some(Selection::Site(site, polity)) if site.valid_from <= year && year < site.valid_to => {
            owner = *polity;
            lines.push(skin.choose(site.name_zh.as_deref().unwrap_or(&site.name), &site.name).into());
            let status = match site.development_status {
                Development::Working => ["开采中", "Active"],
                Development::Former => ["已停采", "Former working"],
                Development::Discovered => ["已发现", "Discovered"],
                Development::Geological => ["地质记录", "Geological occurrence"],
                Development::Unknown => ["开采状态未知", "Working status unknown"],
            };
            let evidence = match site.evidence_status {
                Evidence::Confirmed => ["有史料", "Documented"],
                Evidence::Estimated => ["估算", "Estimated"],
                Evidence::Unknown => ["待核实", "Unverified"],
            };
            lines.push(format!("{} · {}", title(status), title(evidence)));
            let precision = site.spatial_accuracy_m.map_or_else(
                || skin.choose("位置精度未知", "Position accuracy unknown").to_owned(),
                |m| format!("{} ±{:.1} km", skin.choose("位置精度", "Position accuracy"), f64::from(m) / 1000.),
            );
            lines.push(precision);
            if let Some(variant) = &site.variant { lines.push(variant.clone()); }
            if let Some(attributes) = &site.attributes { lines.push(attributes.clone()); }
        }
        Some(Selection::Grid(cell, polity)) => {
            owner = *polity;
            let b = cell.bounds();
            lines.push(format!("{:.2}° … {:.2}° / {:.2}° … {:.2}°", b.west, b.east, b.south, b.north));
            lines.push(cell.fraction_bp.map_or_else(
                || skin.choose("此网格无资料", "No data for this cell").to_owned(),
                |bp| format!("{} {:.2}%", skin.choose("网格覆盖", "Cell cover"), f64::from(bp) / 100.),
            ));
        }
        Some(Selection::Unknown) => lines.push(skin.choose("此处暂无已核实地点", "No verified site here").into()),
        _ => {}
    }
    if let Some(polity) = owner.and_then(|index| world.polities.get(index)) {
        lines.push(skin.country_name(polity).into());
    }
    for line in lines {
        if dy + 20. > h { break; }
        label(text, &line, dy, SUBTLE);
        dy += 22.;
    }
}
