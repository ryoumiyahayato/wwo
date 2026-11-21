use crate::{
    camera::{self, Camera, EARTH},
    landmarks::{ModelBounds, ModelKey, ModelPose, VisibleModel, PARIS_SHARD},
    overlay::Mesh,
};
use glam::{DVec3, Vec2};
use serde::Deserialize;
use std::{collections::BTreeMap, io};
use wwo_map_lab::{
    formal_bootstrap::{RouteMode, WorldSources},
    transport::{
        map_data::load_prototype_geometry,
        models::{ModelLod, TransportModel, TRACK_RAILHEAD_M, TRACK_TILE_LENGTH_M},
        operations::ActiveVehicle,
        Route, TransportMode,
    },
};

const MODEL_BUDGET: usize = 48;
const MARKER_BUDGET: usize = 48;
const PORT_INK: [u8; 4] = [138, 213, 222, 255];
const DARK: [u8; 4] = [23, 32, 39, 244];

pub struct TransportScene {
    routes: BTreeMap<String, DisplayRoute>,
    ports: Vec<DVec3>,
    reference_period: (String, String),
    previous_view: Option<MapView>,
    previous_legs: Vec<String>,
    overlay: Mesh,
    revision: u64,
}

#[derive(PartialEq)]
struct MapView {
    projection: ([[f64; 3]; 3], [f64; 2]),
    size: [u32; 2],
    mpp: f64,
    pitch: f64,
    regional: bool,
    network: bool,
    references: bool,
}

#[derive(Deserialize)]
struct RailShard {
    metadata: ReferencePeriod,
    evidence_catalog: RailCatalogue,
}

#[derive(Deserialize)]
struct ReferencePeriod {
    valid_from: String,
    valid_to: String,
}

#[derive(Deserialize)]
struct RailCatalogue {
    facts: Vec<RailFact>,
}

#[derive(Deserialize)]
struct RailFact {
    value: Reference,
}

#[derive(Deserialize)]
#[serde(tag = "kind")]
enum Reference {
    #[serde(rename = "rail")]
    Rail {
        places: Vec<String>,
        geometry: RailLine,
        geometry_status: String,
    },
    #[serde(other)]
    Other,
}

#[derive(Deserialize)]
struct RailLine {
    coordinates: Vec<[f64; 2]>,
}

struct DisplayRoute {
    from: String,
    to: String,
    mode: TransportMode,
    ordinary: Path,
    reference: Option<Path>,
}

impl DisplayRoute {
    fn path(&self, references: bool) -> (&Path, bool) {
        if let Some(path) = self.reference.as_ref().filter(|_| references) {
            (path, true)
        } else {
            (&self.ordinary, false)
        }
    }
}

struct Path {
    spans: Vec<Span>,
    length: f64,
}

struct Span {
    start: DVec3,
    forward: DVec3,
    start_m: f64,
    end_m: f64,
}

impl Span {
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
        Self { spans, length }
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
    pub fn new(sources: &WorldSources) -> io::Result<Self> {
        let geometry = load_prototype_geometry()?;
        let shard: RailShard = serde_json::from_slice(PARIS_SHARD)?;
        let place = |id: &str| sources.places().get(id).and_then(|row| row.lon_lat);
        let mut ports = Vec::new();
        let mut routes = BTreeMap::new();
        for (port, city) in geometry.port_connections {
            let (Some(dock), Some(town)) = (place(&port), place(&city)) else {
                continue;
            };
            ports.push(radial(dock));
            routes.insert(
                format!("transfer:{}", port.trim_start_matches("place:")),
                DisplayRoute {
                    from: city,
                    to: port,
                    mode: TransportMode::PortTransfer,
                    ordinary: Path::new([town, dock]),
                    reference: None,
                },
            );
        }
        for source in sources.routes().values() {
            let from = &source.from_place_id;
            let to = &source.to_place_id;
            let (Some(start), Some(end)) = (place(from), place(to)) else {
                continue;
            };
            let (mode, ordinary, reference) = match source.mode {
                RouteMode::Road => (TransportMode::Road, Path::new([start, end]), None),
                RouteMode::Rail => {
                    let reference = shard.evidence_catalog.facts.iter().find_map(|fact| {
                        let Reference::Rail {
                            places,
                            geometry,
                            geometry_status,
                        } = &fact.value
                        else {
                            return None;
                        };
                        if geometry_status != "BOUNDED_HISTORICAL_CORRIDOR_REFERENCE" {
                            return None;
                        }
                        slice_reference(places, &geometry.coordinates, [from, to], [start, end])
                    });
                    (TransportMode::Rail, Path::new([start, end]), reference)
                }
                RouteMode::Shipping => {
                    let waypoints =
                        geometry.shipping_waypoints.get(&source.id).ok_or_else(|| {
                            io::Error::other(format!("missing transport waypoints: {}", source.id))
                        })?;
                    let points = [start]
                        .into_iter()
                        .chain(waypoints.iter().copied())
                        .chain([end]);
                    (TransportMode::Shipping, Path::new(points), None)
                }
            };
            routes.insert(
                source.id.clone(),
                DisplayRoute {
                    from: from.clone(),
                    to: to.clone(),
                    mode,
                    ordinary,
                    reference,
                },
            );
        }
        Ok(Self {
            routes,
            ports,
            reference_period: (shard.metadata.valid_from, shard.metadata.valid_to),
            previous_view: None,
            previous_legs: Vec::new(),
            overlay: Mesh::default(),
            revision: 0,
        })
    }

    pub fn update_map(
        &mut self,
        camera: &Camera,
        size: [u32; 2],
        date: &str,
        network: bool,
        itinerary: Option<&Route>,
    ) {
        let view = MapView {
            projection: camera.projection(size),
            size,
            mpp: camera.mpp,
            pitch: camera.pitch(),
            regional: camera.blend() != 0.0,
            network,
            references: date >= self.reference_period.0.as_str()
                && date < self.reference_period.1.as_str(),
        };
        let selected = || {
            itinerary
                .into_iter()
                .flat_map(|route| route.legs.iter())
                .map(|leg| leg.segment_id.as_str())
        };
        if self.previous_view.as_ref() == Some(&view)
            && self.previous_legs.iter().map(String::as_str).eq(selected())
        {
            return;
        }
        self.overlay.vertices.clear();
        self.overlay.indices.clear();
        if view.network {
            for route in self.routes.values() {
                let (path, reference) = route.path(view.references);
                match route.mode {
                    TransportMode::Rail if camera.mpp <= 5500.0 => {
                        draw_path(
                            &mut self.overlay,
                            camera,
                            size,
                            path,
                            1.5,
                            [179, 138, 95, 204],
                            !reference,
                        );
                    }
                    TransportMode::Shipping if camera.mpp <= 9500.0 => {
                        draw_path(
                            &mut self.overlay,
                            camera,
                            size,
                            path,
                            1.35,
                            [108, 176, 192, 212],
                            true,
                        );
                    }
                    _ => {}
                }
            }
        }
        for id in selected() {
            if let Some(route) = self.routes.get(id) {
                let (path, reference) = route.path(view.references);
                let dashed = !reference;
                let ink = match route.mode {
                    TransportMode::Shipping => [148, 229, 231, 254],
                    TransportMode::PortTransfer => [241, 238, 215, 254],
                    _ => [249, 205, 125, 254],
                };
                draw_path(
                    &mut self.overlay,
                    camera,
                    size,
                    path,
                    4.6,
                    [25, 34, 41, 226],
                    dashed,
                );
                draw_path(&mut self.overlay, camera, size, path, 2.6, ink, dashed);
            }
        }
        if view.network && camera.mpp <= 5500.0 {
            for &point in &self.ports {
                if let Some(position) =
                    project(camera, size, point).filter(|p| visible(*p, size, 8.0))
                {
                    port_marker(&mut self.overlay, position);
                }
            }
        }
        if self.overlay.indices.is_empty() {
            self.overlay = Mesh::default();
        }
        self.previous_view = Some(view);
        self.previous_legs = selected().map(str::to_owned).collect();
        self.revision = self.revision.wrapping_add(1);
    }

    pub fn map_overlay(&self) -> Option<(u64, &Mesh)> {
        (!self.overlay.indices.is_empty()).then_some((self.revision, &self.overlay))
    }

    pub fn draw_vehicles<'a>(
        &self,
        camera: &Camera,
        size: [u32; 2],
        vehicles: impl IntoIterator<Item = ActiveVehicle<'a>>,
        models: &mut Vec<VisibleModel>,
        ready: impl Fn(&VisibleModel) -> bool,
    ) -> Mesh {
        let mut markers = Mesh::default();
        let mut models_left = MODEL_BUDGET;
        let mut markers_left = MARKER_BUDGET;
        let references = self
            .previous_view
            .as_ref()
            .is_some_and(|view| view.references);
        for vehicle in vehicles {
            if models_left == 0 && markers_left == 0 {
                break;
            }
            let Some(route) = self.routes.get(vehicle.segment_id) else {
                continue;
            };
            let direction = if route.from == vehicle.from && route.to == vehicle.to {
                1.0
            } else if route.to == vehicle.from && route.from == vehicle.to {
                -1.0
            } else {
                continue;
            };
            if route.mode != vehicle.mode || !vehicle.progress.is_finite() {
                continue;
            }
            let (path, reference) = route.path(references);
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
            let family = VehicleGeometry::for_vehicle(vehicle.mode, vehicle.freight);
            let before = models.len();
            let parts_added =
                if let Some(family) = family.filter(|family| family.parts.len() <= models_left) {
                    family.draw(
                        camera,
                        size,
                        path,
                        distance,
                        direction,
                        heading,
                        reference,
                        models,
                        models_left,
                    )
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

fn port_marker(mesh: &mut Mesh, point: Vec2) {
    let [x, y] = point.to_array();
    mesh.shape(&[[x, y - 7.], [x + 7., y], [x, y + 7.], [x - 7., y]], DARK);
    mesh.line([x, y - 4.], [x, y + 4.], 1.3, PORT_INK);
    mesh.line([x - 3.7, y - 1.5], [x + 3.7, y - 1.5], 1.3, PORT_INK);
    mesh.line([x - 3.3, y + 1.], [x, y + 4.], 1.3, PORT_INK);
    mesh.line([x, y + 4.], [x + 3.3, y + 1.], 1.3, PORT_INK);
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
const LINER: Piece = Piece::centered(TransportModel::PassengerSteamship, 150.0, 17.6, -5.6, 25.3);
const FREIGHTER: Piece = Piece::centered(TransportModel::CargoSteamship, 86.0, 12.0, -4.0, 16.5);
const TRACK: Piece = Piece::centered(
    TransportModel::StraightTrack,
    TRACK_TILE_LENGTH_M as f64,
    3.04,
    0.0,
    TRACK_RAILHEAD_M as f64,
);

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
        reference: bool,
        models: &mut Vec<VisibleModel>,
        budget: usize,
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
        if self.rail && reference && camera.mpp <= 12.0 {
            let track_len = TRACK.length() * scale;
            let tile = (distance / track_len).floor();
            let tiles = [-2., -1., 0., 1., 2.];
            for offset in tiles
                .into_iter()
                .take(budget.saturating_sub(self.parts.len()))
            {
                let at = (tile + offset + 0.5) * track_len;
                if at >= track_len / 2.0 && at <= path.length - track_len / 2.0 {
                    if let Some((point, tangent)) = path.at(at) {
                        models.extend(TRACK.project(camera, size, lod, scale, point, tangent, 0.0));
                    }
                }
            }
        }
        added
    }
}
