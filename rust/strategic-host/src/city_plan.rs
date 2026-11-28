use crate::{
    camera::{self, Camera, EARTH},
    overlay::Mesh,
    HostEvent,
};
use serde::{de::DeserializeOwned, Deserialize};
use std::{
    collections::{HashMap, HashSet},
    fs::File,
    io::{self, Read},
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
};
use winit::event_loop::EventLoopProxy;

const PLAN_BYTES: usize = 32 * 1024 * 1024;
const MAX_RESIDENT: usize = 4;
const MAX_PENDING: usize = 2;
const MAX_BLOCK_VERTICES: usize = 1024;
const CELL_DEGREES: f64 = 0.005;
const MAX_FEATURE_CELLS: i64 = 64;
const PREFETCH_METRES: f64 = 1250.;
const METRES_PER_DEGREE: f64 = EARTH * std::f64::consts::PI / 180.0;
static MESH_REVISION: AtomicU64 = AtomicU64::new(0);

type Point = [f64; 2];
type Bounds = [f64; 4];
type Ring = Vec<Point>;
type Cell = (i32, i32);
type Quad = [Point; 4];

#[derive(Clone)]
pub(crate) struct PlanSource {
    city_id: String,
    file: String,
    extent: PlanExtent,
}

#[derive(Clone, Copy)]
enum PlanExtent {
    Geometry(Bounds),
    Buildings(Bounds),
}

impl PlanSource {
    pub(crate) fn new(
        city_id: Option<String>,
        file: String,
        plan_bounds: Option<Bounds>,
        building_bounds: impl Iterator<Item = Bounds>,
    ) -> io::Result<Self> {
        check_filename(&file)?;
        let city_id = city_id
            .filter(|id| !id.trim().is_empty())
            .ok_or_else(|| invalid(format!("Missing city ID for {file}")))?;
        let extent = match plan_bounds {
            Some([west, south, east, north])
                if valid_point([west, south]) && valid_point([east, north]) && south <= north =>
            {
                PlanExtent::Geometry([west, south, east, north])
            }
            Some(_) => return Err(invalid(format!("Invalid plan bounds for {city_id}"))),
            None => PlanExtent::Buildings(
                building_extent(building_bounds)
                    .ok_or_else(|| invalid(format!("Missing building coverage for {city_id}")))?,
            ),
        };
        Ok(Self {
            city_id,
            file,
            extent,
        })
    }

    fn distance_to_view(&self, view: Bounds, camera: &Camera, size: [u32; 2]) -> Option<f64> {
        match self.extent {
            PlanExtent::Geometry(bounds) if intersects_wgs84(view, bounds) => {
                let [west, south, east, north] = bounds;
                let center = [
                    west + longitude_width(west, east) * 0.5,
                    (south + north) * 0.5,
                ];
                let distance = camera
                    .project(center, size)
                    .map_or(f64::INFINITY, |[x, y]| {
                        (x - f64::from(size[0]) * 0.5).hypot(y - f64::from(size[1]) * 0.5)
                    });
                Some(distance)
            }
            PlanExtent::Geometry(_) => None,
            PlanExtent::Buildings(bounds) => {
                crate::city_models::distance_to_view(bounds, camera, size, PREFETCH_METRES)
            }
        }
    }
}

#[derive(Default)]
pub(crate) struct Plans {
    sources: Vec<PlanSource>,
    cache: HashMap<usize, Plan>,
    pending: HashSet<usize>,
    failed: HashSet<usize>,
    wanted: Vec<usize>,
    view: Option<PlanView>,
    mesh: Mesh,
    mesh_revision: u64,
}

#[derive(PartialEq)]
struct PlanView {
    projection: ([camera::V3; 3], Point),
    size: [u32; 2],
    mpp: f64,
    pitch: f64,
    blend: f64,
    geographic: bool,
    roads: bool,
}

impl Plans {
    pub(crate) fn new(sources: Vec<PlanSource>) -> io::Result<Self> {
        let mut ids = HashSet::new();
        let mut files = HashSet::new();
        for source in &sources {
            if !ids.insert(&source.city_id) || !files.insert(&source.file) {
                return Err(invalid(format!(
                    "Duplicate city plan {} / {}",
                    source.city_id, source.file
                )));
            }
        }
        Ok(Self {
            sources,
            ..Self::default()
        })
    }

    pub(crate) fn ready(&mut self, index: usize, result: io::Result<Plan>) -> io::Result<()> {
        self.pending.remove(&index);
        match result {
            Ok(plan) => {
                if self.wanted.contains(&index) {
                    self.cache.insert(index, plan);
                    self.view = None;
                }
                Ok(())
            }
            Err(error) => {
                self.failed.insert(index);
                Err(io::Error::other(format!(
                    "City plan {} · {error}",
                    self.sources[index].file
                )))
            }
        }
    }

    pub(crate) fn mesh(
        &mut self,
        root: &Path,
        catalogue_revision: u64,
        camera: &Camera,
        size: [u32; 2],
        geographic: bool,
        roads: bool,
        opacity: f32,
        events: &EventLoopProxy<HostEvent>,
    ) -> Option<(u64, &Mesh)> {
        if self.sources.is_empty() {
            return None;
        }
        let view = PlanView {
            projection: camera.projection(size),
            size,
            mpp: camera.mpp,
            pitch: camera.pitch(),
            blend: camera.blend(),
            geographic,
            roads,
        };
        if self.view.as_ref() != Some(&view) {
            self.view = Some(view);
            let prefetch = view_bounds(camera, size, 2. + PREFETCH_METRES / camera.mpp);
            let mut visible: Vec<_> = self
                .sources
                .iter()
                .enumerate()
                .filter_map(|(index, source)| {
                    source
                        .distance_to_view(prefetch, camera, size)
                        .map(|distance| (index, distance))
                })
                .collect();
            visible.sort_by(|a, b| a.1.total_cmp(&b.1));
            self.wanted = visible
                .into_iter()
                .take(MAX_RESIDENT)
                .map(|(index, _)| index)
                .collect();
            self.cache.retain(|index, _| self.wanted.contains(index));
            self.mesh.vertices.clear();
            self.mesh.indices.clear();
            let bounds = view_bounds(camera, size, 2.);
            for blocks in [true, false] {
                if !blocks && !roads {
                    continue;
                }
                for plan in self.wanted.iter().filter_map(|index| self.cache.get(index)) {
                    plan.append(
                        &mut self.mesh,
                        camera,
                        size,
                        bounds,
                        geographic,
                        opacity,
                        blocks,
                    );
                }
            }
            if !self.mesh.indices.is_empty() {
                self.mesh_revision = MESH_REVISION.fetch_add(1, Ordering::Relaxed);
            }
        }
        for &index in &self.wanted {
            if self.pending.len() >= MAX_PENDING {
                break;
            }
            if self.cache.contains_key(&index)
                || self.failed.contains(&index)
                || !self.pending.insert(index)
            {
                continue;
            }
            let source = self.sources[index].clone();
            let root = root.to_path_buf();
            let proxy = events.clone();
            if let Err(error) = std::thread::Builder::new()
                .name("WWO city plan".into())
                .spawn(move || {
                    let result = Plan::open(&root, &source.file, &source.city_id);
                    let _ =
                        proxy.send_event(HostEvent::CityPlan(catalogue_revision, index, result));
                })
            {
                let _ =
                    events.send_event(HostEvent::CityPlan(catalogue_revision, index, Err(error)));
            }
        }
        (!self.mesh.indices.is_empty()).then_some((self.mesh_revision, &self.mesh))
    }
}

#[derive(Deserialize)]
struct PlanFile {
    #[serde(rename = "type")]
    kind: CollectionType,
    crs: Option<serde_json::Value>,
    wwo: PlanIdentity,
    features: Vec<PlanFeature>,
}

#[derive(Deserialize)]
enum CollectionType {
    FeatureCollection,
}

#[derive(Deserialize)]
struct PlanIdentity {
    city_id: String,
    origin: Point,
}

#[derive(Deserialize)]
struct PlanFeature {
    #[serde(rename = "type")]
    kind: FeatureType,
    geometry: Geometry,
    properties: Properties,
}

#[derive(Deserialize)]
enum FeatureType {
    Feature,
}

#[derive(Deserialize)]
struct Properties {
    kind: FeatureKind,
    width_m: Option<f64>,
    role: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum FeatureKind {
    Road,
    Block,
    #[serde(other)]
    Other,
}

#[derive(Deserialize)]
#[serde(tag = "type")]
enum Geometry {
    LineString {
        coordinates: Vec<Point>,
    },
    Polygon {
        coordinates: Vec<Ring>,
    },
    MultiPolygon {
        coordinates: Vec<Vec<Ring>>,
    },
    #[serde(other)]
    Other,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RoadRole {
    LayoutAxis,
    District,
    Local,
    TransportApproach,
}

struct Road {
    role: RoadRole,
    quads: Vec<Quad>,
}

enum Feature {
    Road(Road),
    Block(Vec<Quad>),
}

struct IndexedFeature {
    bounds: Bounds,
    feature: Feature,
}

pub(crate) struct Plan {
    longitude: f64,
    bounds: Option<Bounds>,
    features: Vec<IndexedFeature>,
    cells: HashMap<Cell, Vec<usize>>,
    wide: Vec<usize>,
}

impl Plan {
    fn open(root: &Path, file: &str, city_id: &str) -> io::Result<Self> {
        let PlanFile {
            kind: CollectionType::FeatureCollection,
            crs,
            wwo,
            features,
        } = read_json(&root.join(file), PLAN_BYTES)?;
        if crs.is_some() || wwo.city_id != city_id || !valid_point(wwo.origin) {
            return Err(invalid(format!(
                "Invalid city plan identity or coordinates in {file}"
            )));
        }

        let mut plan = Self {
            longitude: wwo.origin[0],
            bounds: None,
            features: Vec::new(),
            cells: HashMap::new(),
            wide: Vec::new(),
        };
        for (index, row) in features.into_iter().enumerate() {
            let PlanFeature {
                kind: FeatureType::Feature,
                geometry,
                properties,
            } = row;
            let invalid_feature =
                |error: io::Error| invalid(format!("{file}, feature {index}: {error}"));
            match (properties.kind, geometry) {
                (FeatureKind::Road, Geometry::LineString { coordinates }) => {
                    let road =
                        Road::new(coordinates, properties.width_m, properties.role.as_deref())
                            .map_err(invalid_feature)?;
                    let bounds = plan.envelope(road.quads.iter().flatten().copied());
                    plan.insert(bounds, Feature::Road(road));
                }
                (FeatureKind::Block, Geometry::Polygon { coordinates }) => {
                    plan.insert_block(coordinates).map_err(invalid_feature)?;
                }
                (FeatureKind::Block, Geometry::MultiPolygon { coordinates })
                    if !coordinates.is_empty() =>
                {
                    for polygon in coordinates {
                        plan.insert_block(polygon).map_err(invalid_feature)?;
                    }
                }
                (FeatureKind::Other, _) => {}
                _ => return Err(invalid_feature(invalid("Wrong geometry for city feature"))),
            }
        }
        Ok(plan)
    }

    /// Returns features whose envelopes intersect a WGS84 viewport. West greater
    /// than east denotes a viewport crossing the antimeridian.
    fn visible(&self, [west, south, east, north]: Bounds) -> impl Iterator<Item = &Feature> {
        let mut ids = Vec::new();
        if valid_point([west, south]) && valid_point([east, north]) && south <= north {
            let start = relative_longitude(west, self.longitude);
            let width = longitude_width(west, east);
            for offset in [-360., 0., 360.] {
                let view = [start + offset, south, start + offset + width, north];
                if self.bounds.is_some_and(|bounds| intersects(view, bounds)) {
                    self.collect_visible(view, &mut ids);
                }
            }
        }
        ids.sort_unstable();
        ids.dedup();
        ids.into_iter().map(|id| &self.features[id].feature)
    }

    fn append(
        &self,
        mesh: &mut Mesh,
        camera: &Camera,
        size: [u32; 2],
        bounds: Bounds,
        geographic: bool,
        opacity: f32,
        blocks: bool,
    ) {
        for feature in self.visible(bounds) {
            let (quads, mut color) = match feature {
                Feature::Block(quads) if blocks => (
                    quads,
                    if geographic {
                        [133, 116, 98, 78]
                    } else {
                        [128, 118, 108, 38]
                    },
                ),
                Feature::Road(road) if !blocks => (
                    &road.quads,
                    match road.role {
                        RoadRole::LayoutAxis => [165, 141, 111, 164],
                        RoadRole::District => [158, 140, 119, 112],
                        RoadRole::Local | RoadRole::TransportApproach if geographic => {
                            [162, 147, 128, 90]
                        }
                        _ => continue,
                    },
                ),
                _ => continue,
            };
            color[3] = (f32::from(color[3]) * opacity).round() as u8;
            if color[3] == 0 {
                continue;
            }
            for quad in quads {
                let [Some(a), Some(b), Some(c), Some(d)] =
                    quad.map(|point| camera.project(point, size))
                else {
                    continue;
                };
                let projected = [a, b, c, d];
                if (0..2).any(|axis| {
                    projected.iter().all(|point| point[axis] < 0.)
                        || projected
                            .iter()
                            .all(|point| point[axis] > f64::from(size[axis]))
                }) {
                    continue;
                }
                mesh.shape(
                    &projected.map(|point| point.map(|value| value as f32)),
                    color,
                );
            }
        }
    }

    fn collect_visible(&self, view: Bounds, ids: &mut Vec<usize>) {
        let cells = cell_bounds(view);
        if cell_count(cells) >= self.cells.len() as i64 {
            ids.extend(
                self.features
                    .iter()
                    .enumerate()
                    .filter_map(|(id, row)| intersects(view, row.bounds).then_some(id)),
            );
            return;
        }
        let [west, south, east, north] = cells;
        let candidates = (south..=north)
            .flat_map(|y| (west..=east).filter_map(move |x| self.cells.get(&(x, y))))
            .flatten()
            .chain(&self.wide);
        ids.extend(
            candidates
                .copied()
                .filter(|&id| intersects(view, self.features[id].bounds)),
        );
    }

    fn insert_block(&mut self, coordinates: Vec<Ring>) -> io::Result<()> {
        let (shell, holes) = coordinates
            .split_first()
            .ok_or_else(|| invalid("Missing polygon shell"))?;
        if coordinates.iter().map(Vec::len).sum::<usize>() > MAX_BLOCK_VERTICES {
            return Err(invalid("Too many vertices in city block polygon"));
        }
        let bounds = self.ring_bounds(shell)?;
        for hole in holes {
            let inside = self.ring_bounds(hole)?;
            if union(bounds, inside) != bounds {
                return Err(invalid("Polygon hole lies outside its shell bounds"));
            }
        }
        let quads = block_quads(&coordinates, self.longitude)?;
        self.insert(bounds, Feature::Block(quads));
        Ok(())
    }

    fn ring_bounds(&self, ring: &[Point]) -> io::Result<Bounds> {
        if ring.len() < 4 || ring.first() != ring.last() || ring.iter().any(|&p| !valid_point(p)) {
            return Err(invalid("Expected a closed WGS84 polygon ring"));
        }
        let [x0, y0] = ring[0];
        let local = |[x, y]: Point| [relative_longitude(x, x0), y - y0];
        let area: f64 = ring
            .windows(2)
            .map(|pair| {
                let [ax, ay] = local(pair[0]);
                let [bx, by] = local(pair[1]);
                ax * by - bx * ay
            })
            .sum();
        if area == 0. {
            return Err(invalid("Polygon ring has zero signed area"));
        }
        Ok(self.envelope(ring.iter().copied()))
    }

    fn envelope(&self, points: impl Iterator<Item = Point>) -> Bounds {
        points
            .map(|[x, y]| {
                let x = relative_longitude(x, self.longitude);
                [x, y, x, y]
            })
            .reduce(union)
            .unwrap()
    }

    fn insert(&mut self, bounds: Bounds, feature: Feature) {
        let id = self.features.len();
        self.bounds = Some(self.bounds.map_or(bounds, |extent| union(extent, bounds)));
        self.features.push(IndexedFeature { bounds, feature });
        let cells = cell_bounds(bounds);
        if cell_count(cells) > MAX_FEATURE_CELLS {
            self.wide.push(id);
            return;
        }
        let [west, south, east, north] = cells;
        for y in south..=north {
            for x in west..=east {
                self.cells.entry((x, y)).or_default().push(id);
            }
        }
    }
}

impl Road {
    fn new(centreline: Vec<Point>, width_m: Option<f64>, role: Option<&str>) -> io::Result<Self> {
        let width_m = width_m
            .filter(|width| width.is_finite() && *width > 0.)
            .ok_or_else(|| invalid("Expected a positive road width in metres"))?;
        let role = match role {
            Some("layout_axis") => RoadRole::LayoutAxis,
            Some("district") => RoadRole::District,
            Some("local") => RoadRole::Local,
            Some("transport_approach") => RoadRole::TransportApproach,
            _ => return Err(invalid("Unknown city road role")),
        };
        if centreline.len() < 2 || centreline.iter().any(|&point| !valid_point(point)) {
            return Err(invalid("Expected a WGS84 road line"));
        }
        let quads = centreline
            .windows(2)
            .map(|pair| road_quad(pair[0], pair[1], width_m))
            .collect::<io::Result<_>>()?;
        Ok(Self { role, quads })
    }
}

fn view_bounds(camera: &Camera, size: [u32; 2], padding_pixels: f64) -> Bounds {
    let center = size.map(|px| f64::from(px) * 0.5);
    let Some(center) = camera.vector(center, size) else {
        return [-180., -90., 180., 90.];
    };
    let [lon, lat] = camera::geographic(center);
    let radius = camera.extent(size, padding_pixels);
    let degrees = radius.to_degrees();
    let south = (lat - degrees).max(-90.);
    let north = (lat + degrees).min(90.);
    if south == -90. || north == 90. {
        return [-180., south, 180., north];
    }
    let width = (radius.sin() / lat.to_radians().cos())
        .clamp(-1., 1.)
        .asin()
        .to_degrees();
    [
        relative_longitude(lon - width, 0.),
        south,
        relative_longitude(lon + width, 0.),
        north,
    ]
}

fn block_quads(rings: &[Ring], longitude: f64) -> io::Result<Vec<Quad>> {
    let mut levels: Vec<_> = rings.iter().flatten().map(|point| point[1]).collect();
    levels.sort_by(f64::total_cmp);
    levels.dedup();
    let edges: Vec<_> = rings
        .iter()
        .flat_map(|ring| ring.windows(2))
        .filter(|edge| edge[0][1] != edge[1][1])
        .map(|edge| [edge[0], edge[1]].map(|[lon, lat]| [relative_longitude(lon, longitude), lat]))
        .collect();
    let mut quads = Vec::new();
    let mut crossings = Vec::new();
    for band in levels.windows(2) {
        let [south, north] = [band[0], band[1]];
        crossings.clear();
        // Crossing pairs fill the exterior and leave interior rings empty,
        // regardless of ring orientation.
        for &[[x0, y0], [x1, y1]] in &edges {
            if y0.min(y1) > south || y0.max(y1) < north {
                continue;
            }
            let x_at = |y| {
                if y == y0 {
                    x0
                } else if y == y1 {
                    x1
                } else {
                    x0 + (y - y0) * (x1 - x0) / (y1 - y0)
                }
            };
            crossings.push([x_at(south), x_at(north)]);
        }
        crossings.sort_unstable_by(|a, b| (a[0] + a[1]).total_cmp(&(b[0] + b[1])));
        if crossings.len() % 2 != 0 {
            return Err(invalid("Unpaired intersections in city block polygon"));
        }
        let wrap = |x| relative_longitude(x + longitude, 0.);
        for pair in crossings.chunks_exact(2) {
            let [[left_s, left_n], [right_s, right_n]] = [pair[0], pair[1]];
            if left_s > right_s || left_n > right_n {
                return Err(invalid("Crossing edges in city block polygon"));
            }
            quads.push([
                [wrap(left_s), south],
                [wrap(right_s), south],
                [wrap(right_n), north],
                [wrap(left_n), north],
            ]);
        }
    }
    Ok(quads)
}

fn road_quad(a: Point, b: Point, width_m: f64) -> io::Result<[Point; 4]> {
    let lon_metres = METRES_PER_DEGREE * ((a[1] + b[1]) * 0.5).to_radians().cos();
    let east = relative_longitude(b[0], a[0]) * lon_metres;
    let north = (b[1] - a[1]) * METRES_PER_DEGREE;
    let length = east.hypot(north);
    if lon_metres < 0.001 || length < 0.001 {
        return Err(invalid("Road segment is degenerate or lies at the pole"));
    }
    let half_width = width_m * 0.5;
    let offset = [
        -north / length * half_width / lon_metres,
        east / length * half_width / METRES_PER_DEGREE,
    ];
    let corner = |[lon, lat]: [f64; 2], sign: f64| {
        [
            relative_longitude(lon + sign * offset[0], 0.),
            lat + sign * offset[1],
        ]
    };
    let quad = [corner(a, 1.), corner(b, 1.), corner(b, -1.), corner(a, -1.)];
    if quad.iter().any(|&point| !valid_point(point)) || offset[0].abs() >= 180. {
        return Err(invalid("Road width extends outside WGS84 bounds"));
    }
    Ok(quad)
}

fn check_filename(file: &str) -> io::Result<()> {
    if !file.ends_with(".geojson")
        || !file
            .as_bytes()
            .first()
            .is_some_and(u8::is_ascii_alphanumeric)
        || !file
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c))
    {
        return Err(invalid(format!("Invalid city plan filename {file}")));
    }
    Ok(())
}

fn valid_point([lon, lat]: Point) -> bool {
    (-180. ..=180.).contains(&lon) && (-90. ..=90.).contains(&lat)
}

fn relative_longitude(lon: f64, origin: f64) -> f64 {
    (lon - origin + 180.).rem_euclid(360.) - 180.
}

fn longitude_width(west: f64, east: f64) -> f64 {
    if west <= east {
        east - west
    } else {
        360. + east - west
    }
}

fn building_extent(building_bounds: impl Iterator<Item = Bounds>) -> Option<Bounds> {
    // WCB pages are local. Their sorted endpoints can span 360° at the antimeridian.
    let mut pages = building_bounds.map(|[west, south, east, north]| {
        if east - west > 180. {
            [east, south, west, north]
        } else {
            [west, south, east, north]
        }
    });
    let first = pages.next()?;
    let origin = first[0] + longitude_width(first[0], first[2]) * 0.5;
    let unwrap = |[west, south, east, north]| {
        let start = origin + relative_longitude(west, origin);
        [start, south, start + longitude_width(west, east), north]
    };
    Some(pages.map(unwrap).fold(unwrap(first), union))
}

fn intersects_wgs84(a: Bounds, b: Bounds) -> bool {
    a[1] <= b[3]
        && b[1] <= a[3]
        && ((b[0] - a[0]).rem_euclid(360.) <= longitude_width(a[0], a[2])
            || (a[0] - b[0]).rem_euclid(360.) <= longitude_width(b[0], b[2]))
}

fn union(a: Bounds, b: Bounds) -> Bounds {
    [
        a[0].min(b[0]),
        a[1].min(b[1]),
        a[2].max(b[2]),
        a[3].max(b[3]),
    ]
}

fn intersects(a: Bounds, b: Bounds) -> bool {
    a[0] <= b[2] && b[0] <= a[2] && a[1] <= b[3] && b[1] <= a[3]
}

fn cell_bounds(bounds: Bounds) -> [i32; 4] {
    bounds.map(|degree| (degree / CELL_DEGREES).floor() as i32)
}

fn cell_count([west, south, east, north]: [i32; 4]) -> i64 {
    i64::from(east - west + 1) * i64::from(north - south + 1)
}

fn read_json<T: DeserializeOwned>(path: &Path, limit: usize) -> io::Result<T> {
    let file = File::open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() || metadata.len() > limit as u64 {
        return Err(invalid(format!(
            "Expected a file of at most {limit} bytes at {}",
            path.display()
        )));
    }
    let mut bytes = Vec::new();
    file.take((limit + 1) as u64).read_to_end(&mut bytes)?;
    if bytes.len() > limit {
        return Err(invalid(format!("{} exceeds {limit} bytes", path.display())));
    }
    serde_json::from_slice(&bytes).map_err(|error| invalid(format!("{}: {error}", path.display())))
}

fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}
