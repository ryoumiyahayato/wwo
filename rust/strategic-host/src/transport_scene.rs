use crate::{
    camera::{self, Camera, EARTH},
    formal_ui::Skin,
    landmarks::{
        ModelBounds, ModelKey, ModelPose, RegionalSource, VisibleModel, MISSISSIPPI, SHARDS,
    },
    overlay::Mesh,
    ui::Layers,
};
use glam::{DVec3, Vec2};
use serde::Deserialize;
use std::{collections::BTreeMap, io};
use wwo_map_lab::transport::{
    map_data::load_prototype_geometry,
    models::{ModelLod, TransportModel, TRACK_RAILHEAD_M},
    operations::ActiveVehicle,
    NodeKind, Route, TransportMode, TransportNetwork,
};

const MODEL_BUDGET: usize = 48;
const MARKER_BUDGET: usize = 48;
const PORT_INK: [u8; 4] = [138, 213, 222, 255];
const DARK: [u8; 4] = [23, 32, 39, 244];
const BLOCKED: [u8; 4] = [245, 110, 81, 250];
const RIVER: [u8; 4] = [76, 191, 155, 230];

pub struct TransportScene {
    /// Only the three schematic sea ways in the opening catalogue have waypoints.
    schematic: BTreeMap<String, Path>,
    regions: Vec<Region>,
    terminals: Vec<Terminal>,
    previous_view: Option<MapView>,
    previous_legs: Vec<String>,
    vehicle_segments: Vec<String>,
    overlay: Mesh,
    revision: u64,
    visible: Vec<(Vec2, usize)>,
    corridor_page: Option<(usize, usize)>,
}

struct Terminal {
    id: String,
    point: DVec3,
    corridors: Vec<String>,
    port: bool,
}

struct Region {
    source: &'static RegionalSource,
    loaded: Option<RegionalGeometry>,
}

struct RegionalGeometry {
    period: Period,
    routes: BTreeMap<String, Path>,
    stations: Vec<(DVec3, Period)>,
}

#[derive(PartialEq)]
struct MapView {
    projection: ([[f64; 3]; 3], [f64; 2]),
    size: [u32; 2],
    mpp: f64,
    pitch: f64,
    network: bool,
    date: String,
    availability: u64,
}

#[derive(Deserialize)]
struct Shard {
    metadata: Period,
    evidence_catalog: Catalogue,
}
#[derive(Deserialize)]
struct Period {
    valid_from: String,
    valid_to: String,
}
impl Period {
    fn contains(&self, date: &str) -> bool {
        self.valid_from.as_str() <= date && date < self.valid_to.as_str()
    }
}
#[derive(Deserialize)]
struct Catalogue {
    facts: Vec<Fact>,
}
#[derive(Deserialize)]
struct Fact {
    value: Reference,
}
#[derive(Deserialize)]
#[serde(tag = "kind")]
enum Reference {
    #[serde(rename = "rail")]
    Rail {
        places: Vec<String>,
        geometry: Line,
        geometry_status: String,
    },
    #[serde(rename = "corridor")]
    Corridor {
        segment_id: String,
        geometry: Line,
        geometry_status: String,
    },
    #[serde(rename = "geographic_region")]
    Place {
        #[serde(default)]
        display_kind: String,
        #[serde(default)]
        geometry: Option<serde_json::Value>,
        #[serde(flatten)]
        period: Period,
    },
    #[serde(other)]
    Other,
}
#[derive(Deserialize)]
struct Line {
    coordinates: Vec<[f64; 2]>,
}

impl Region {
    fn load(&self, network: &TransportNetwork) -> io::Result<RegionalGeometry> {
        let shard: Shard = serde_json::from_slice(self.source.bytes)?;
        let mut geometry = RegionalGeometry {
            period: shard.metadata,
            routes: BTreeMap::new(),
            stations: Vec::new(),
        };
        for fact in shard.evidence_catalog.facts {
            match fact.value {
                Reference::Rail {
                    places,
                    geometry: line,
                    geometry_status,
                } if geometry_status == "BOUNDED_HISTORICAL_CORRIDOR_REFERENCE" => {
                    for edge in network.segments().filter(|e| e.mode == TransportMode::Rail) {
                        let (Some(a), Some(b)) = (
                            network.node_coordinates(&edge.from),
                            network.node_coordinates(&edge.to),
                        ) else {
                            continue;
                        };
                        if let Some(path) = slice_reference(
                            &places,
                            &line.coordinates,
                            [&edge.from, &edge.to],
                            [a, b],
                        ) {
                            geometry.routes.entry(edge.id.clone()).or_insert(path);
                        }
                    }
                }
                Reference::Corridor {
                    segment_id,
                    geometry: line,
                    geometry_status,
                } if geometry_status == "BOUNDED_HISTORICAL_CORRIDOR_REFERENCE" => {
                    if network.segment(&segment_id).is_none() {
                        return Err(io::Error::other(format!(
                            "regional geometry has unknown segment {segment_id}"
                        )));
                    }
                    geometry
                        .routes
                        .insert(segment_id, Path::new(line.coordinates));
                }
                Reference::Place {
                    display_kind,
                    geometry: Some(point),
                    period,
                } if display_kind == "transport_node" => {
                    if let Some(coords) = point
                        .get("coordinates")
                        .and_then(|xy| serde_json::from_value::<[f64; 2]>(xy.clone()).ok())
                    {
                        geometry.stations.push((radial(coords), period));
                    }
                }
                _ => {}
            }
        }
        Ok(geometry)
    }
}

struct Path {
    spans: Vec<Span>,
    length: f64,
    center: DVec3,
    radius: f64,
}

struct Span {
    start: DVec3,
    forward: DVec3,
    start_m: f64,
    end_m: f64,
}

impl Span {
    fn end(&self) -> DVec3 { self.at(self.end_m).0 }

    fn at(&self, distance: f64) -> (DVec3, DVec3) {
        let (sin, cos) = ((distance - self.start_m) / EARTH).sin_cos();
        (
            self.start * cos + self.forward * sin,
            self.forward * cos - self.start * sin,
        )
    }
}

fn radial(point: [f64; 2]) -> DVec3 {
    DVec3::from_array(camera::frame(point)[2])
}

impl Path {
    fn new(points: impl IntoIterator<Item = [f64; 2]>) -> Self {
        let mut spans = Vec::new();
        let mut length = 0.0;
        let mut points = points.into_iter().map(radial);
        if let Some(mut start) = points.next() {
            for end in points {
                let normal = start.cross(end);
                let angle = normal.length().atan2(start.dot(end));
                if angle > 1e-10 && angle < std::f64::consts::PI - 1e-10 {
                    let end_m = length + angle * EARTH;
                    spans.push(Span {
                        start,
                        forward: normal.cross(start).normalize(),
                        start_m: length,
                        end_m,
                    });
                    length = end_m;
                }
                start = end;
            }
        }
        let center = spans.iter().map(|s| s.start + s.end()).sum::<DVec3>().try_normalize().unwrap_or(DVec3::X);
        let radius = spans.iter().map(|s| {
            let middle = s.at((s.start_m + s.end_m) * 0.5).0;
            center.angle_between(middle) * EARTH + (s.end_m - s.start_m) * 0.5
        }).fold(0., f64::max);
        Self { spans, length, center, radius }
    }

    fn at(&self, distance: f64) -> Option<(DVec3, DVec3)> {
        let distance = distance.clamp(0.0, self.length);
        let index = self.spans.partition_point(|span| span.end_m < distance);
        self.spans.get(index).map(|span| span.at(distance))
    }
}

fn slice_reference(
    places: &[String],
    points: &[[f64; 2]],
    ids: [&str; 2],
    endpoints: [[f64; 2]; 2],
) -> Option<Path> {
    let last = points.len().checked_sub(1)?;
    let nearest = |id: &str, point| {
        let place = places.iter().position(|place| place == id)?;
        if place == 0 {
            return Some(0);
        }
        if place + 1 == places.len() {
            return Some(last);
        }
        let target = radial(point);
        points
            .iter()
            .enumerate()
            .min_by(|(_, a), (_, b)| {
                radial(**a)
                    .distance_squared(target)
                    .total_cmp(&radial(**b).distance_squared(target))
            })
            .map(|(index, _)| index)
    };
    let first = nearest(ids[0], endpoints[0])?;
    let last = nearest(ids[1], endpoints[1])?;
    let path = if first < last {
        Path::new(points[first..=last].iter().copied())
    } else {
        Path::new(points[last..=first].iter().rev().copied())
    };
    (path.length > 0.0).then_some(path)
}

impl TransportScene {
    pub fn new(network: &TransportNetwork) -> io::Result<Self> {
        let catalogue = load_prototype_geometry()?;
        let schematic = catalogue
            .shipping_waypoints
            .into_iter()
            .filter_map(|(id, points)| {
                let edge = network.segment(&id)?;
                let start = network.node_coordinates(&edge.from)?;
                let end = network.node_coordinates(&edge.to)?;
                Some((
                    id,
                    Path::new([start].into_iter().chain(points).chain([end])),
                ))
            })
            .collect();
        let mut incident = BTreeMap::new();
        for edge in network.segments() {
            for id in [&edge.from, &edge.to] {
                incident
                    .entry(id.as_str())
                    .or_insert_with(Vec::new)
                    .push(edge.id.clone());
            }
        }
        let terminals = network
            .nodes()
            .filter_map(|node| {
                let point = radial(network.node_coordinates(&node.id)?);
                let mut corridors = incident.remove(node.id.as_str()).unwrap_or_default();
                corridors.sort_by_key(|id| match network.segment(id).map(|s| s.mode) {
                    Some(TransportMode::Shipping | TransportMode::InlandWaterway) => 0,
                    Some(TransportMode::Rail | TransportMode::Road) => 1,
                    Some(TransportMode::PortTransfer) => 2,
                    _ => 3,
                });
                Some(Terminal {
                    id: node.id.clone(),
                    point,
                    corridors,
                    port: node.kind == NodeKind::Port,
                })
            })
            .collect();
        Ok(Self {
            schematic,
            terminals,
            regions: SHARDS
                .iter()
                .chain([&MISSISSIPPI])
                .map(|source| Region {
                    source,
                    loaded: None,
                })
                .collect(),
            previous_view: None,
            previous_legs: Vec::new(),
            vehicle_segments: Vec::new(),
            overlay: Mesh::default(),
            revision: 0,
            visible: Vec::new(),
            corridor_page: None,
        })
    }

    pub fn update_map(
        &mut self,
        camera: &Camera,
        size: [u32; 2],
        date: &str,
        show_network: bool,
        network: &TransportNetwork,
        itinerary: Option<&Route>,
    ) -> io::Result<()> {
        let selected = || {
            itinerary
                .into_iter()
                .flat_map(|r| r.legs.iter().map(|l| l.segment_id.as_str()))
        };
        let view = MapView {
            projection: camera.projection(size),
            size,
            mpp: camera.mpp,
            pitch: camera.pitch(),
            network: show_network,
            date: date.to_owned(),
            availability: network.availability_revision(),
        };
        if self.previous_view.as_ref() == Some(&view)
            && self.previous_legs.iter().map(String::as_str).eq(selected())
        {
            return Ok(());
        }
        self.overlay.vertices.clear();
        self.overlay.indices.clear();
        self.visible.clear();
        self.vehicle_segments.clear();
        let center = radial(camera.coordinates());
        let reach = camera.mpp * f64::from(size[0]).hypot(f64::from(size[1]));
        for region in &mut self.regions {
            let distance = center.angle_between(radial(region.source.center)) * EARTH;
            if camera.mpp > 5500. || distance > reach + region.source.radius_km * 1000. {
                region.loaded = None;
            } else if region.loaded.is_none() {
                region.loaded = Some(region.load(network)?);
            }
        }
        let current = self
            .regions
            .iter()
            .filter_map(|r| r.loaded.as_ref())
            .filter(|r| r.period.contains(date));
        for (id, path) in self
            .schematic
            .iter()
            .chain(current.clone().flat_map(|r| &r.routes))
        {
            let Some(edge) = network.segment(id) else {
                continue;
            };
            if !network.evidence(id).is_some_and(|e| e.applies_on(date)) {
                continue;
            }
            if camera.mpp <= 1200. && center.angle_between(path.center) * EARTH <= reach + path.radius {
                self.vehicle_segments.push(edge.id.clone());
            }
            let highlight = selected().any(|s| s == id);
            if !(view.network || highlight) {
                continue;
            }
            let generalized = self.schematic.contains_key(id);
            if generalized && camera.mpp < 100. {
                continue;
            }
            let available = network.availability(id).unwrap();
            let ink = if !available.open || available.capacity_units == 0 {
                BLOCKED
            } else if highlight {
                [249, 205, 125, 254]
            } else {
                match edge.mode {
                    TransportMode::Shipping => PORT_INK,
                    TransportMode::InlandWaterway => RIVER,
                    _ => [179, 138, 95, 222],
                }
            };
            draw_path(
                &mut self.overlay,
                camera,
                size,
                path,
                if highlight { 3.8 } else { 1.6 },
                ink,
                generalized,
            );
        }
        if camera.mpp <= 40. {
            for &(port, basin) in DOCK_BASINS {
                if center.angle_between(radial(basin)) * EARTH <= reach {
                    if let Some(terminal) = self.terminals.iter().find(|t| t.id == port) {
                        self.vehicle_segments.extend(terminal.corridors.iter().filter(|id|
                            network.segment(id).is_some_and(|s| s.mode == TransportMode::PortTransfer)).cloned());
                    }
                }
            }
        }
        self.vehicle_segments.sort_unstable();
        self.vehicle_segments.dedup();
        if view.network {
            for (idx, terminal) in self.terminals.iter().enumerate() {
                let mut major = false;
                let mut blocked = false;
                let mut capacity = 0;
                let mut highlighted = false;
                for id in &terminal.corridors {
                    if !network.evidence(id).is_some_and(|e| e.applies_on(date)) {
                        continue;
                    }
                    let edge = network.segment(id).unwrap();
                    let access = network.availability(id).unwrap();
                    major |= matches!(
                        edge.mode,
                        TransportMode::Shipping | TransportMode::InlandWaterway
                    );
                    blocked |= !access.open || access.capacity_units < edge.profile.capacity_units;
                    if access.open {
                        capacity = capacity.max(access.capacity_units);
                    }
                    highlighted |= selected().any(|s| s == id);
                }
                if !major && !highlighted && (camera.mpp > 5500. || terminal.corridors.is_empty()) {
                    continue;
                }
                let Some(xy) =
                    project(camera, size, terminal.point).filter(|p| visible(*p, size, 8.))
                else {
                    continue;
                };
                self.visible.push((xy, idx));
                let tint = if blocked {
                    BLOCKED
                } else if highlighted {
                    [250, 210, 125, 255]
                } else if major {
                    PORT_INK
                } else {
                    [203, 174, 122, 240]
                };
                let radius = if major {
                    (2.5 + (capacity as f32 + 1.).log10() * 0.65).clamp(3., 7.)
                } else {
                    3.
                };
                terminal_marker(&mut self.overlay, xy, radius, tint, terminal.port);
            }
            if camera.mpp <= 1200. {
                for (station, period) in current.flat_map(|r| &r.stations) {
                    if let Some(xy) = project(camera, size, *station)
                        .filter(|p| period.contains(date) && visible(*p, size, 6.))
                    {
                        terminal_marker(&mut self.overlay, xy, 3., [228, 200, 141, 245], false);
                    }
                }
            }
        }
        self.previous_view = Some(view);
        self.previous_legs = selected().map(str::to_owned).collect();
        self.revision = self.revision.wrapping_add(1);
        Ok(())
    }

    fn nearest_terminal(&self, cursor: [f64; 2]) -> Option<usize> {
        let pointer = Vec2::new(cursor[0] as f32, cursor[1] as f32);
        self
            .visible
            .iter()
            .filter(|(p, _)| p.distance_squared(pointer) < 100.)
            .min_by(|(a, ia), (b, ib)| {
                a.distance_squared(pointer)
                    .total_cmp(&b.distance_squared(pointer))
                    .then_with(|| self.terminals[*ib].port.cmp(&self.terminals[*ia].port))
            }).map(|(_, index)| *index)
    }

    pub fn next_corridors(&mut self, cursor: [f64; 2]) -> bool {
        let Some(index) = self.nearest_terminal(cursor) else { return false; };
        let page = self.corridor_page.filter(|(i, _)| *i == index).map_or(0, |(_, p)| p);
        self.corridor_page = Some((index, page.wrapping_add(1)));
        true
    }

    pub fn caption(
        &self,
        skin: &Skin,
        cursor: [f64; 2],
        size: [u32; 2],
        world: &wwo_map_lab::formal_bootstrap::InitialWorld,
        meshes: &mut Layers,
    ) {
        let network = world.transport();
        if self.visible.is_empty() {
            return;
        }
        // Map panels use a solid surface; text uses the HUD glyph atlas.
        let [_, _, _, _, _, _, (panel, crate::ui::Ink::Solid), _, _, _, _, _, (text, crate::ui::Ink::HudText)] = meshes
            else { return; };
        let mut lines = Vec::new();
        let nearby = self.nearest_terminal(cursor);
        if let Some(idx) = nearby.filter(|&i| world.can_read_place_record(&self.terminals[i].id)) {
            let terminal = &self.terminals[idx];
            lines.push(format!(
                "{} · {}",
                network.node_label(&terminal.id).unwrap_or(&terminal.id),
                skin.choose("占用 / 可用上限", "occupied / operating limit")
            ));
            let date = &self.previous_view.as_ref().expect("visible map").date;
            let corridors: Vec<_> = terminal.corridors.iter().filter(|id|
                network.evidence(id).is_some_and(|e| e.applies_on(date))).collect();
            let pages = corridors.len().div_ceil(3).max(1);
            let page = self.corridor_page.filter(|(i, _)| *i == idx).map_or(0, |(_, p)| p % pages);
            if pages > 1 {
                lines.push(format!("{}/{}   ] {}", page + 1, pages, skin.choose("下页", "Next")));
            }
            for &id in corridors.iter().skip(page * 3).take(3) {
                let edge = network.segment(id).unwrap();
                let a = network.availability(id).unwrap();
                let other = if terminal.id == edge.from {
                    &edge.to
                } else {
                    &edge.from
                };
                // Highlight the counterpart of a documented relationship. Its course
                // can be unknown even when both terminals are located.
                if let Some((xy, _)) = self
                    .visible
                    .iter()
                    .find(|(_, idx)| &self.terminals[*idx].id == other)
                {
                    let r = 9.;
                    let c = if a.open && a.capacity_units > 0 {
                        [251, 214, 129, 245]
                    } else {
                        BLOCKED
                    };
                    for (dx, dy) in [(-1., -1.), (-1., 1.), (1., -1.), (1., 1.)] {
                        let at = [xy.x + dx * r, xy.y + dy * r];
                        panel.line(at, [at[0] - dx * 4., at[1]], 1.4, c);
                        panel.line(at, [at[0], at[1] - dy * 4.], 1.4, c);
                    }
                }
                let mode = match edge.mode {
                    TransportMode::Shipping => skin.choose("海运", "Sea"),
                    TransportMode::InlandWaterway => skin.choose("河运", "River"),
                    TransportMode::Rail => skin.choose("铁路", "Rail"),
                    TransportMode::Road => skin.choose("道路", "Road"),
                    TransportMode::PortTransfer => skin.choose("换装", "Transfer"),
                    _ => skin.choose("地区", "Regional"),
                };
                if let Some(c) = world.transport_service_capacity(id, &terminal.id) {
                    let status = if !a.open || a.capacity_units == 0 { skin.choose(" 停运", " closed") }
                        else if a.capacity_units < edge.profile.capacity_units { skin.choose(" 减容", " restricted") }
                        else { "" };
                    lines.push(format!("{}{} · {} · {} {}/{}", mode, status, network.node_label(other).unwrap_or(other),
                        skin.choose("线路","line"), c.line_used, c.line_limit));
                    lines.push(format!("  {} {}/{} · {} {}/{} · {} {}/{}",
                        skin.choose("班次","service"), c.service_used, c.service_limit,
                        skin.choose("货位","cargo"), c.cargo_used, c.cargo_limit,
                        skin.choose("客座","seats"), c.seats_used, c.seat_limit));
                }
            }
        } else if nearby.is_some() {
            lines.push(skin.choose("尚不能阅读当地交通记录", "Cannot read the local transport record").to_owned());
        } else {
            lines.push(
                skin.choose(
                    "交通节点 · 大小表示运力，红色表示受限",
                    "Transport nodes · size shows capacity, red shows restrictions",
                )
                .to_owned(),
            );
        }
        let width = 350_f32.min(size[0] as f32 - 24.);
        let height = lines.len() as f32 * 19. + 8.;
        let x = 12.;
        let y = (size[1] as f32 - height - 180.).max(4.);
        panel.rect(x, y, width, height, [14, 24, 30, 222]);
        for (i, line) in lines.iter().enumerate() {
            skin.text(
                text,
                line,
                0,
                [x + 7., y + 3. + i as f32 * 19.],
                width - 14.,
                [235, 226, 208, 255],
            );
        }
    }
    pub fn map_overlay(&self) -> Option<(u64, &Mesh)> {
        (!self.overlay.indices.is_empty()).then_some((self.revision, &self.overlay))
    }

    pub fn vehicle_segments(&self) -> impl Iterator<Item = &str> {
        self.vehicle_segments.iter().map(String::as_str)
    }

    pub fn draw_vehicles<'a>(
        &self,
        camera: &Camera,
        size: [u32; 2],
        network: &TransportNetwork,
        vehicles: impl IntoIterator<Item = ActiveVehicle<'a>>,
        models: &mut Vec<VisibleModel>,
        ready: impl Fn(&VisibleModel) -> bool,
    ) -> Mesh {
        let mut markers = Mesh::default();
        let mut models_left = MODEL_BUDGET;
        let mut markers_left = MARKER_BUDGET;
        if camera.mpp > 1200. {
            return markers;
        }
        let Some(view) = &self.previous_view else {
            return markers;
        };
        for vehicle in vehicles {
            if models_left == 0 && markers_left == 0 {
                break;
            }
            let Some(edge) = network.segment(vehicle.segment_id) else {
                continue;
            };
            let direction = if edge.from == vehicle.from && edge.to == vehicle.to {
                1.0
            } else if edge.from == vehicle.to && edge.to == vehicle.from {
                -1.0
            } else {
                continue;
            };
            if edge.mode != vehicle.mode || !vehicle.progress.is_finite() {
                continue;
            }
            if let Some(port) = vehicle.alongside_seaport {
                if camera.mpp <= 40. && models_left > 0 && view.date.as_str() >= "1900-01-01" && view.date.as_str() < "1901-01-01" {
                    if let Some((_, centre)) = DOCK_BASINS.iter().find(|(id, _)| *id == port) {
                        let point = radial(*centre);
                        if let Some(position) = project(camera, size, point).filter(|p| visible(*p, size, 48.)) {
                            let part = if vehicle.freight { FREIGHTER } else { LINER };
                            let east = DVec3::from_array(camera::frame(*centre)[0]);
                            let scale = (40. * camera.mpp / part.length()).clamp(1., 4.);
                            if let Some(model) = ModelLod::for_screen_extent((part.length() * scale / camera.mpp) as f32)
                                .and_then(|lod| part.project(camera, size, lod, scale, point, east, 0.)) {
                                if !ready(&model) && markers_left > 0 {
                                    vehicle_marker(&mut markers, position, Vec2::X, TransportMode::Shipping, vehicle.freight);
                                    markers_left -= 1;
                                }
                                models.push(model);
                                models_left -= 1;
                            }
                        }
                    }
                }
                continue;
            }
            let reference = self
                .regions
                .iter()
                .filter_map(|r| r.loaded.as_ref())
                .filter(|r| r.period.contains(&view.date))
                .find_map(|r| r.routes.get(vehicle.segment_id));
            let Some(path) = reference.or_else(|| self.schematic.get(vehicle.segment_id)) else {
                continue;
            };
            let progress = f64::from(vehicle.progress.clamp(0.0, 1.0));
            let distance = if direction > 0.0 {
                progress
            } else {
                1.0 - progress
            } * path.length;
            let Some((point, tangent)) = path.at(distance) else {
                continue;
            };
            let Some(position) = project(camera, size, point).filter(|p| visible(*p, size, 48.0))
            else {
                continue;
            };
            let tangent = tangent * direction;
            let heading = marker_heading(camera, size, point, tangent, position);
            // A schematic sea waypoint gives a regional symbol, never a local ship pose.
            let family = reference
                .filter(|_| camera.mpp <= 40.)
                .and_then(|_| VehicleGeometry::for_vehicle(vehicle.mode, vehicle.freight));
            let before = models.len();
            let parts_added =
                if let Some(family) = family.filter(|family| family.parts.len() <= models_left) {
                    family.draw(camera, size, path, distance, direction, heading, models)
                } else {
                    0
                };
            models_left -= models.len() - before;
            if markers_left > 0 && !models[before..before + parts_added].iter().any(&ready) {
                if visible(position, size, 10.0) {
                    vehicle_marker(
                        &mut markers,
                        position,
                        heading,
                        vehicle.mode,
                        vehicle.freight,
                    );
                    markers_left -= 1;
                }
            }
        }
        markers
    }
}

fn project(camera: &Camera, size: [u32; 2], point: DVec3) -> Option<Vec2> {
    camera
        .project_vec(point.to_array(), size)
        .map(|p| Vec2::new(p[0] as f32, p[1] as f32))
}

fn visible(point: Vec2, size: [u32; 2], margin: f32) -> bool {
    point.x >= -margin
        && point.x <= size[0] as f32 + margin
        && point.y >= -margin
        && point.y <= size[1] as f32 + margin
}

fn clip_line(start: Vec2, end: Vec2, size: [u32; 2]) -> Option<(f32, f32)> {
    let mut low: f32 = 0.0;
    let mut high: f32 = 1.0;
    let delta = end - start;
    for (start, step, limit) in [(start.x, delta.x, size[0]), (start.y, delta.y, size[1])] {
        if step.abs() < 1e-4 {
            if start < -4.0 || start > limit as f32 + 4.0 {
                return None;
            }
        } else {
            let a = (-4.0 - start) / step;
            let b = (limit as f32 + 4.0 - start) / step;
            low = low.max(a.min(b));
            high = high.min(a.max(b));
        }
    }
    (low < high).then_some((low, high))
}

fn draw_path(
    mesh: &mut Mesh,
    camera: &Camera,
    size: [u32; 2],
    path: &Path,
    width: f32,
    ink: [u8; 4],
    dashed: bool,
) {
    let mut phase: f32 = 0.0;
    for span in &path.spans {
        // Bounded angular interpolation keeps long shipping legs on the globe.
        let steps = ((span.end_m - span.start_m) / 240_000.0).ceil() as u32;
        let mut previous = project(camera, size, span.start);
        for step in 1..=steps {
            let fraction = f64::from(step) / f64::from(steps);
            let (point, _) = span.at(span.start_m + (span.end_m - span.start_m) * fraction);
            let next = project(camera, size, point);
            if let (Some(start), Some(end)) = (previous, next) {
                let delta = end - start;
                let length = delta.length();
                if let Some((first, last)) = clip_line(start, end, size) {
                    if length > 0.02 && dashed {
                        let start = start + delta * first;
                        let end_m = (last - first) * length;
                        let unit = delta / length;
                        let mut at = -(phase + first * length).rem_euclid(14.0);
                        while at < end_m {
                            let begin = at.max(0.0);
                            let stop = (at + 8.0).min(end_m);
                            if begin < stop {
                                mesh.line(
                                    (start + unit * begin).to_array(),
                                    (start + unit * stop).to_array(),
                                    width,
                                    ink,
                                );
                            }
                            at += 14.0;
                        }
                    } else {
                        mesh.line(
                            (start + delta * first).to_array(),
                            (start + delta * last).to_array(),
                            width,
                            ink,
                        );
                    }
                }
                phase = (phase + length).rem_euclid(14.0);
            }
            previous = next;
        }
    }
}

fn terminal_marker(mesh: &mut Mesh, point: Vec2, r: f32, ink: [u8; 4], port: bool) {
    let [x, y] = point.to_array();
    if port {
        mesh.shape(
            &[
                [x, y - r - 1.],
                [x + r + 1., y],
                [x, y + r + 1.],
                [x - r - 1., y],
            ],
            DARK,
        );
        mesh.shape(&[[x, y - r], [x + r, y], [x, y + r], [x - r, y]], ink);
    } else {
        mesh.rect(x - r - 1., y - r - 1., 2. * r + 2., 2. * r + 2., DARK);
        mesh.rect(x - r, y - r, 2. * r, 2. * r, ink);
    }
}
fn marker_heading(
    camera: &Camera,
    size: [u32; 2],
    point: DVec3,
    tangent: DVec3,
    position: Vec2,
) -> Vec2 {
    let next = (point + tangent * (camera.mpp * 16.0 / EARTH).min(0.002)).normalize();
    project(camera, size, next)
        .and_then(|next| (next - position).try_normalize())
        .unwrap_or(Vec2::NEG_Y)
}

fn vehicle_marker(
    mesh: &mut Mesh,
    position: Vec2,
    forward: Vec2,
    mode: TransportMode,
    freight: bool,
) {
    let side = forward.perp();
    let ink = if freight {
        [250, 172, 102, 255]
    } else {
        [242, 229, 172, 255]
    };
    let path = match mode {
        TransportMode::Rail => [[8.0, 0.], [2., 4.], [-7., 4.], [-7., -4.], [2., -4.]],
        TransportMode::Shipping => [[9.0, 0.], [2., 5.], [-7., 3.], [-7., -3.], [2., -5.]],
        _ => [[6.0, 0.], [0., 4.], [-5., 1.], [-5., -1.], [0., -4.]],
    };
    for (scale, color) in [(1.25, DARK), (1.0, ink)] {
        let points = path.map(|[a, b]| (position + (a * forward + b * side) * scale).to_array());
        mesh.shape(&points, color);
    }
}

#[derive(Clone, Copy)]
struct Piece {
    model: TransportModel,
    bounds: ModelBounds,
}

impl Piece {
    const fn centered(
        model: TransportModel,
        length: f64,
        width: f64,
        bottom: f64,
        top: f64,
    ) -> Self {
        Self {
            model,
            bounds: (
                [-width / 2.0, bottom, -length / 2.0],
                [width / 2.0, top, length / 2.0],
            ),
        }
    }

    fn length(self) -> f64 {
        self.bounds.1[2] - self.bounds.0[2]
    }

    fn project(
        self,
        camera: &Camera,
        size: [u32; 2],
        lod: ModelLod,
        scale: f64,
        point: DVec3,
        tangent: DVec3,
        rise: f64,
    ) -> Option<VisibleModel> {
        let anchor = camera::geographic(point.to_array());
        let [east, north, _] = camera::frame(anchor).map(DVec3::from_array);
        let bearing = tangent.dot(east).atan2(tangent.dot(north)).to_degrees();
        ModelPose {
            key: ModelKey::transport(self.model, lod),
            anchor,
            heading: 180.0 - bearing,
            datum: -rise * scale,
            dimensions: [scale; 3],
            bounds: self.bounds,
        }
        .project(None, camera, camera.pitch(), size)
        .filter(|model| {
            let [x, y, w, h] = model.screen_bounds;
            x + w >= 0.0 && y + h >= 0.0 && x <= size[0] as f32 && y <= size[1] as f32
        })
    }
}

const ENGINE: Piece = Piece::centered(TransportModel::SteamLocomotive, 12.8, 3.0, 0.0, 4.6);
const TENDER: Piece = Piece::centered(TransportModel::CoalTender, 7.0, 2.7, 0.0, 3.1);
const COACH: Piece = Piece::centered(TransportModel::PassengerCoach, 17.0, 3.0, 0.0, 3.5);
const WAGON: Piece = Piece::centered(TransportModel::BoxWagon, 8.0, 2.9, 0.0, 3.2);
// Estimated visual anchorage inside the east–west Royal Victoria Dock basin, opened in 1855.
// Source: Historic England, NHLE 1393528, and US Serial Set 7942, plan of the Royal Docks.
// Another port needs a documented basin before close-range port handling can show a ship.
const DOCK_BASINS: &[(&str, [f64; 2])] = &[("place:port_london", [0.0220, 51.5072])];
const LINER: Piece = Piece::centered(TransportModel::PassengerSteamship, 150.0, 17.6, -5.6, 25.3);
const FREIGHTER: Piece = Piece::centered(TransportModel::CargoSteamship, 86.0, 12.0, -4.0, 16.5);
struct VehicleGeometry {
    parts: &'static [Piece],
    max_scale: f64,
    rail: bool,
}

impl VehicleGeometry {
    fn for_vehicle(mode: TransportMode, freight: bool) -> Option<Self> {
        let (parts, max_scale, rail): (&[_], _, _) = match (mode, freight) {
            (TransportMode::Rail, false) => (&[ENGINE, TENDER, COACH], 12.0, true),
            (TransportMode::Rail, true) => (&[ENGINE, TENDER, WAGON, WAGON], 12.0, true),
            (TransportMode::Shipping, false) => (&[LINER], 6.0, false),
            (TransportMode::Shipping, true) => (&[FREIGHTER], 6.0, false),
            _ => return None,
        };
        Some(Self {
            parts,
            max_scale,
            rail,
        })
    }

    fn draw(
        &self,
        camera: &Camera,
        size: [u32; 2],
        path: &Path,
        distance: f64,
        direction: f64,
        heading: Vec2,
        models: &mut Vec<VisibleModel>,
    ) -> usize {
        let length: f64 = self.parts.iter().map(|part| part.length()).sum();
        let compression = f64::from(heading.x).hypot(f64::from(heading.y) * camera.pitch().cos());
        let scale = (54.0 * camera.mpp / (length * compression)).clamp(1.0, self.max_scale);
        let shown_length = length * scale;
        let Some(lod) =
            ModelLod::for_screen_extent((shown_length * compression / camera.mpp) as f32)
        else {
            return 0;
        };
        let half = (shown_length * 0.5).min(path.length * 0.5);
        let distance = distance.clamp(half, path.length - half);
        let mut front = half;
        let rise = if self.rail {
            f64::from(TRACK_RAILHEAD_M)
        } else {
            0.0
        };
        let before = models.len();
        for &part in self.parts {
            let space = part.length() * scale;
            if let Some((point, tangent)) = path.at(distance + (front - space * 0.5) * direction) {
                models.extend(part.project(
                    camera,
                    size,
                    lod,
                    scale,
                    point,
                    tangent * direction,
                    rise,
                ));
            }
            front -= space;
        }
        let added = models.len() - before;
        added
    }
}
