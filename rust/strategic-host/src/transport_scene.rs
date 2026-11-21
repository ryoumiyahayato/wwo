use crate::{
    camera::{self, Camera, EARTH},
    formal_ui::Skin,
    landmarks::{
        ModelBounds, ModelKey, ModelPose, RegionalSource, VisibleModel, MISSISSIPPI, SHARDS,
    },
    overlay::Mesh,
    transport_ui::{MappedSite, ObjectId},
    ui::{Layers, Mode},
};
use glam::{DVec3, Vec2};
use serde::Deserialize;
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
    sync::atomic::{AtomicU64, Ordering},
};
use wwo_map_lab::{
    formal_bootstrap::InitialWorld,
    transport::{
        map_data::load_prototype_geometry,
        models::{ModelLod, TransportModel, TRACK_RAILHEAD_M},
        NetworkLayer, NodeKind, TransportMode, TransportNetwork,
    },
};

const MODEL_BUDGET: usize = 48;
const MARKER_BUDGET: usize = 48;
const PORT_INK: [u8; 4] = [138, 213, 222, 255];
const DARK: [u8; 4] = [23, 32, 39, 244];
const BLOCKED: [u8; 4] = [245, 110, 81, 250];
const RESTRICTED: [u8; 4] = [249, 171, 102, 244];
const RIVER: [u8; 4] = [76, 191, 155, 230];
const SELECTED: [u8; 4] = [255, 219, 131, 252];
const FLOW: [u8; 4] = [255, 191, 88, 254];
const CELL_COUNT: usize = 12;
static DRAW_REVISION: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GeometryEvidence {
    HistoricalCorridor,
    Schematic,
    Unmapped,
}

pub struct TransportScene {
    schematic: BTreeMap<String, Path>,
    regions: Vec<Region>,
    rail_pairs: BTreeMap<(String, String), Vec<String>>,
    incident: BTreeMap<String, Vec<String>>,
    terminals: Vec<Terminal>,
    terminal_cells: Vec<Vec<usize>>,
    previous_view: Option<MapView>,
    previous_legs: Vec<String>,
    previous_selection: Option<ObjectId>,
    vehicle_segments: Vec<String>,
    vehicle_hits: Vec<VehicleHit>,
    overlay: Mesh,
    revision: u64,
    visible: Vec<VisibleNode>,
    paths: Vec<VisiblePath>,
    flow_by_segment: BTreeMap<String, [u32; 2]>,
    flow_by_terminal: BTreeMap<String, [u32; 2]>,
    flow_nodes: BTreeSet<String>,
    flow_overlay: Mesh,
    flow_movement_revision: Option<u64>,
    flow_view: Option<u64>,
    flow_revision: u64,
    corridor_page: Option<(usize, usize)>,
}

struct Terminal {
    id: String,
    point: DVec3,
    kind: NodeKind,
}

struct VisibleNode {
    position: Vec2,
    id: String,
    terminal: Option<usize>,
    radius: f32,
    port: bool,
    drawn: bool,
}

struct VisiblePath {
    id: String,
    fragments: Vec<(Vec2, Vec2)>,
    dash_strokes: Option<Vec<(Vec2, Vec2)>>,
}

impl VisiblePath {
    fn strokes(&self) -> &[(Vec2, Vec2)] {
        self.dash_strokes.as_deref().unwrap_or(&self.fragments)
    }
}

struct VehicleHit {
    area: [f32; 4],
    id: ObjectId,
}

struct Region {
    source: &'static RegionalSource,
    loaded: Option<RegionalGeometry>,
}

struct RegionalGeometry {
    period: Period,
    routes: BTreeMap<String, Path>,
    references: Vec<RegionalPoint>,
}

struct RegionalPoint {
    id: String,
    name: String,
    kind: String,
    source: String,
    note: String,
    coordinates: [f64; 2],
    period: Period,
}

#[derive(PartialEq)]
struct MapView {
    projection: ([[f64; 3]; 3], [f64; 2]),
    size: [u32; 2],
    mpp: f64,
    pitch: f64,
    mode: Mode,
    date: String,
    availability: u64,
    vehicle_segment: Option<String>,
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
        id: String,
        display_name: String,
        #[serde(default)]
        display_kind: String,
        #[serde(default)]
        transport_symbol: String,
        #[serde(default)]
        source_reference: String,
        #[serde(default)]
        note_zh: String,
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
    fn load(
        &self,
        network: &TransportNetwork,
        rail_pairs: &BTreeMap<(String, String), Vec<String>>,
    ) -> io::Result<RegionalGeometry> {
        let shard: Shard = serde_json::from_slice(self.source.bytes)?;
        let mut geometry = RegionalGeometry {
            period: shard.metadata,
            routes: BTreeMap::new(),
            references: Vec::new(),
        };
        for fact in shard.evidence_catalog.facts {
            match fact.value {
                Reference::Rail {
                    places,
                    geometry: line,
                    geometry_status,
                } if geometry_status == "BOUNDED_HISTORICAL_CORRIDOR_REFERENCE" => {
                    for (i, first) in places.iter().enumerate() {
                        for second in places.iter().skip(i + 1) {
                            let pair = (first.min(second).clone(), first.max(second).clone());
                            for id in rail_pairs.get(&pair).into_iter().flatten() {
                                let edge = network.segment(id).expect("indexed rail segment");
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
                    id,
                    display_name,
                    display_kind,
                    transport_symbol,
                    source_reference,
                    note_zh,
                    geometry: Some(point),
                    period,
                } if display_kind == "transport_node" => {
                    if let Some(coords) = point
                        .get("coordinates")
                        .and_then(|xy| serde_json::from_value::<[f64; 2]>(xy.clone()).ok())
                    {
                        geometry.references.push(RegionalPoint {
                            id,
                            name: display_name,
                            kind: transport_symbol,
                            source: source_reference,
                            note: note_zh,
                            coordinates: coords,
                            period,
                        });
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
    chunks: Vec<PathChunk>,
    length: f64,
    center: DVec3,
    radius: f64,
}

const SPANS_PER_CHUNK: usize = 32;

struct PathChunk {
    center: DVec3,
    radius: f64,
}

struct ViewReach {
    center: DVec3,
    radius: f64,
}

impl ViewReach {
    fn intersects(&self, center: DVec3, radius: f64) -> bool {
        let angle = (self.radius + radius) / EARTH;
        angle >= std::f64::consts::PI || self.center.dot(center) >= angle.cos()
    }
}

struct Span {
    start: DVec3,
    end: DVec3,
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
                        end,
                        forward: normal.cross(start).normalize(),
                        start_m: length,
                        end_m,
                    });
                    length = end_m;
                }
                start = end;
            }
        }
        let extent = |spans: &[Span], center: DVec3| spans.iter().map(|s| {
            let middle = s.at((s.start_m + s.end_m) * 0.5).0;
            center.angle_between(middle) * EARTH + (s.end_m - s.start_m) * 0.5
        }).fold(0., f64::max);
        let center = spans.iter().map(|s| s.start + s.end).sum::<DVec3>().try_normalize().unwrap_or(DVec3::X);
        let radius = extent(&spans, center);
        let chunks = spans.chunks(SPANS_PER_CHUNK).map(|spans| {
            let center = spans[0].start;
            PathChunk { center, radius: extent(spans, center) }
        }).collect();
        Self { spans, chunks, length, center, radius }
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
        let mut schematic: BTreeMap<_, _> = catalogue
            .shipping_waypoints
            .into_iter()
            .filter_map(|(id, points)| {
                let edge = network.segment(&id)?;
                let start = network.node_coordinates(&edge.from)?;
                let end = network.node_coordinates(&edge.to)?;
                Some((id, Path::new([start].into_iter().chain(points).chain([end]))))
            })
            .collect();
        let mut incident: BTreeMap<String, Vec<String>> = BTreeMap::new();
        let mut rail_pairs: BTreeMap<_, Vec<_>> = BTreeMap::new();
        for edge in network.segments() {
            for id in [&edge.from, &edge.to] {
                incident.entry(id.clone()).or_default().push(edge.id.clone());
            }
            if edge.mode == TransportMode::Rail {
                let pair = (edge.from.clone().min(edge.to.clone()), edge.from.clone().max(edge.to.clone()));
                rail_pairs.entry(pair).or_default().push(edge.id.clone());
            }
            let named_rail = edge.mode == TransportMode::Rail && !edge.prototype_only
                && network.evidence(&edge.id).is_some_and(|e| e.layer == NetworkLayer::Detailed && e.opened_on.is_some());
            if named_rail || edge.mode == TransportMode::Road && edge.prototype_only {
                if let (Some(from), Some(to)) = (
                    network.node_coordinates(&edge.from),
                    network.node_coordinates(&edge.to),
                ) {
                    schematic.insert(edge.id.clone(), Path::new([from, to]));
                }
            }
        }
        for edges in incident.values_mut() {
            edges.sort_by_key(|id| match network.segment(id).map(|s| s.mode) {
                Some(TransportMode::Shipping | TransportMode::InlandWaterway) => 0,
                Some(TransportMode::Rail | TransportMode::Road) => 1,
                Some(TransportMode::PortTransfer) => 2,
                _ => 3,
            });
        }
        let mut terminals = Vec::new();
        let mut terminal_cells = vec![Vec::new(); CELL_COUNT.pow(3)];
        for node in network.nodes() {
            if !incident.contains_key(&node.id) {
                continue;
            }
            let Some(coords) = network.node_coordinates(&node.id) else {
                continue;
            };
            let point = radial(coords);
            terminal_cells[cell_index(point.to_array().map(cell_axis))].push(terminals.len());
            terminals.push(Terminal { id: node.id.clone(), point, kind: node.kind });
        }
        Ok(Self {
            schematic,
            terminals,
            terminal_cells,
            incident,
            rail_pairs,
            regions: SHARDS
                .iter()
                .chain([&MISSISSIPPI])
                .map(|source| Region { source, loaded: None })
                .collect(),
            previous_view: None,
            previous_legs: Vec::new(),
            previous_selection: None,
            vehicle_segments: Vec::new(),
            vehicle_hits: Vec::new(),
            overlay: Mesh::default(),
            revision: 0,
            visible: Vec::new(),
            paths: Vec::new(),
            flow_by_segment: BTreeMap::new(),
            flow_by_terminal: BTreeMap::new(),
            flow_nodes: BTreeSet::new(),
            flow_overlay: Mesh::default(),
            flow_movement_revision: None,
            flow_view: None,
            flow_revision: 0,
            corridor_page: None,
        })
    }

    pub fn update_map(
        &mut self,
        camera: &Camera,
        size: [u32; 2],
        date: &str,
        mode: Mode,
        world: &InitialWorld,
        selection: Option<&ObjectId>,
    ) -> io::Result<()> {
        let network = world.transport();
        let selected_leg_ids = || {
            world.selected_transport_route().into_iter()
                .flat_map(|route| route.legs.iter().map(|leg| leg.segment_id.as_str()))
        };
        let vehicle = match selection {
            Some(ObjectId::Vehicle { reservation, .. }) => world.transport_vehicle(*reservation),
            _ => None,
        };
        let view = MapView {
            projection: camera.projection(size),
            size,
            mpp: camera.mpp,
            pitch: camera.pitch(),
            mode,
            date: date.to_owned(),
            availability: network.availability_revision(),
            vehicle_segment: vehicle.as_ref().map(|vehicle| vehicle.segment_id.to_owned()),
        };
        if self.previous_view.as_ref() == Some(&view)
            && self.previous_selection.as_ref() == selection
            && self.previous_legs.iter().map(String::as_str).eq(selected_leg_ids())
        {
            self.update_flows(world, mode);
            return Ok(());
        }

        let selected_segment = match selection {
            Some(ObjectId::Segment(id)) => Some(id.as_str()),
            Some(ObjectId::Vehicle { segment, .. }) =>
                Some(vehicle.as_ref().map_or(segment.as_str(), |vehicle| vehicle.segment_id)),
            _ => None,
        };
        let selected_node = match selection {
            Some(ObjectId::Node(id)) => Some(id.as_str()),
            _ => None,
        };
        let highlighted = |id: &str| selected_segment == Some(id) || selected_leg_ids().any(|leg| leg == id);
        let midpoint = size.map(|dimension| f64::from(dimension) * 0.5);
        let center = DVec3::from_array(camera.vector(midpoint, size).unwrap_or(view.projection.0[2]));
        let metres = camera.mpp * (f64::from(size[0])).hypot(f64::from(size[1]) / view.pitch.cos()) * 0.5;
        let reach = if camera.blend() > 0. {
            metres
        } else {
            (metres / EARTH).min(1.).asin() * EARTH
        } + camera.mpp * 24.;
        let view_reach = ViewReach { center, radius: reach };
        for region in &mut self.regions {
            let distance = center.angle_between(radial(region.source.center)) * EARTH;
            let in_view = camera.mpp <= camera::ENTER && distance <= reach + region.source.radius_km * 1000.;
            if in_view && region.loaded.is_none() {
                region.loaded = Some(region.load(network, &self.rail_pairs)?);
            } else if !in_view && region.loaded.as_ref().is_some_and(|geometry| {
                !selected_segment.is_some_and(|id| geometry.routes.contains_key(id))
                    && !selected_node.is_some_and(|id| geometry.references.iter().any(|site| site.id == id))
            }) {
                region.loaded = None;
            }
        }

        self.overlay.vertices.clear();
        self.overlay.indices.clear();
        self.visible.clear();
        self.paths.clear();
        self.vehicle_segments.clear();
        let current = self.regions.iter()
            .filter_map(|r| r.loaded.as_ref())
            .filter(|r| r.period.contains(date));
        let mut drawn = BTreeSet::new();
        for (id, path, schematic) in current.clone().flat_map(|r| r.routes.iter())
            .map(|(id, path)| (id, path, false))
            .chain(self.schematic.iter().map(|(id, path)| (id, path, true)))
        {
            if !view_reach.intersects(path.center, path.radius) {
                continue;
            }
            let Some(edge) = network.segment(id) else { continue; };
            if !network.evidence(id).is_some_and(|e| e.applies_on(date)) || !drawn.insert(id) {
                continue;
            }
            let availability = network.availability(id).expect("segment has availability");
            let closed = !availability.open || availability.capacity_units == 0;
            let restricted = availability.capacity_units < edge.profile.capacity_units;
            let highlight = highlighted(id);
            if mode != Mode::Military && camera.mpp <= 1200.
                && (!schematic || edge.mode == TransportMode::Shipping && camera.mpp >= 100.)
            {
                self.vehicle_segments.push(id.clone());
            }
            let status = if closed { Some(BLOCKED) } else if restricted { Some(RESTRICTED) } else { None };
            let color = if highlight { SELECTED } else { mode_ink(edge.mode) };
            let named_rail = schematic && edge.mode == TransportMode::Rail;
            let military_schematic = schematic && match edge.mode {
                TransportMode::Rail => (highlight || status.is_some())
                    && endpoints_cross_jurisdiction(world, &edge.from, &edge.to, date),
                TransportMode::Shipping => highlight,
                _ => false,
            };
            if named_rail && camera.mpp > 1200. {
                continue;
            }
            let (mut width, mut ink) = match mode {
                Mode::Geographic => (if edge.mode == TransportMode::Rail { 2.3 } else { 1.7 }, status.unwrap_or(color)),
                Mode::Political => (1.1, status.map_or([177, 202, 204, 140], |c| with_alpha(c, 180))),
                Mode::Economic => (1.3, status.map_or([161, 179, 175, 130], |c| with_alpha(c, 175))),
                Mode::Military => {
                    if schematic && !military_schematic { continue; }
                    let width = if military_schematic { 1.35 } else { capacity_radius(availability.capacity_units) * 0.52 };
                    (width, status.unwrap_or([181, 196, 143, 218]))
                }
            };
            if schematic && !named_rail && (camera.mpp < 100. || (edge.mode == TransportMode::Road
                && (camera.mpp < 1000. || camera.mpp > 5500.)))
            {
                continue;
            }
            if mode == Mode::Political && !highlight && status.is_none() {
                if !endpoints_cross_jurisdiction(world, &edge.from, &edge.to, date) {
                    continue;
                }
            }
            if highlight {
                width += if mode == Mode::Military && military_schematic { 0. }
                    else if mode == Mode::Political { 0.7 } else { 1.5 };
                ink = status.unwrap_or(SELECTED);
            }
            if mode == Mode::Military && military_schematic {
                ink = with_alpha(ink, 192);
            }
            let mut path_hits = VisiblePath { id: id.clone(), fragments: Vec::new(), dash_strokes: schematic.then(Vec::new) };
            draw_path(&mut self.overlay, camera, size, &view_reach, path, width, ink, &mut path_hits);
            if !path_hits.strokes().is_empty() {
                self.paths.push(path_hits);
            }
        }

        let chord = 2. * (reach.min(std::f64::consts::PI * EARTH) / (2. * EARTH)).sin();
        let low = (center - DVec3::splat(chord)).to_array().map(cell_axis);
        let high = (center + DVec3::splat(chord)).to_array().map(cell_axis);
        for x in low[0]..=high[0] {
            for y in low[1]..=high[1] {
                for z in low[2]..=high[2] {
                    for &index in &self.terminal_cells[cell_index([x, y, z])] {
                        let terminal = &self.terminals[index];
                        let Some(position) = project(camera, size, terminal.point).filter(|p| visible(*p, size, 12.))
                            else { continue; };
                        let mut open_capacity = 0;
                        let mut status = None;
                        let mut international = false;
                        let mut water = false;
                        let mut has_civil_capacity = false;
                        let mut has_direct_link = false;
                        let mut connected = false;
                        let mut highlighted_terminal = selected_node == Some(terminal.id.as_str());
                        for id in self.incident[&terminal.id].iter() {
                            let edge = network.segment(id).expect("indexed segment");
                            let evidence = network.evidence(id).filter(|e| e.applies_on(date));
                            let Some(evidence) = evidence else { continue; };
                            let access = network.availability(id).expect("segment has availability");
                            let other = if edge.from == terminal.id { &edge.to } else { &edge.from };
                            connected = true;
                            highlighted_terminal |= highlighted(id);
                            let physical_relation = evidence.layer != NetworkLayer::Domestic;
                            has_direct_link |= physical_relation;
                            if !physical_relation || mode == Mode::Military && edge.prototype_only
                                && !current.clone().any(|region| region.routes.contains_key(id)) {
                                continue;
                            }
                            water |= matches!(edge.mode, TransportMode::Shipping | TransportMode::InlandWaterway);
                            if mode == Mode::Political {
                                international |= endpoints_cross_jurisdiction(world, &terminal.id, other, date);
                            }
                            let closed = !access.open || access.capacity_units == 0;
                            if closed {
                                status = Some(BLOCKED);
                            } else {
                                open_capacity = open_capacity.max(access.capacity_units);
                                if status.is_none() && access.capacity_units < edge.profile.capacity_units {
                                    status = Some(RESTRICTED);
                                }
                            }
                            has_civil_capacity = true;
                        }
                        if !connected && !highlighted_terminal {
                            continue;
                        }
                        let port = terminal.kind == NodeKind::Port;
                        let context = match mode {
                            Mode::Geographic => water || camera.mpp <= camera::ENTER,
                            Mode::Political => international || status.is_some(),
                            Mode::Economic => water || camera.mpp <= camera::ENTER,
                            Mode::Military => has_civil_capacity && (water || camera.mpp <= camera::ENTER),
                        };
                        let radius = if mode == Mode::Military { capacity_radius(open_capacity) } else if port { 4. } else { 3. };
                        if context || highlighted_terminal {
                            let ink = status.unwrap_or_else(|| {
                                if highlighted_terminal { SELECTED } else if !has_direct_link { [170, 164, 147, 190] }
                                else if mode == Mode::Political { [202, 205, 187, 204] }
                                else if mode == Mode::Military { [181, 196, 143, 233] }
                                else if port { PORT_INK } else { [218, 185, 130, 240] }
                            });
                            if !has_direct_link {
                                hollow_marker(&mut self.overlay, position, radius, ink, false);
                            } else {
                                terminal_marker(&mut self.overlay, position, radius, ink, port);
                            }
                        }
                        if context || highlighted_terminal || mode == Mode::Economic {
                            self.visible.push(VisibleNode {
                                position, id: terminal.id.clone(), terminal: Some(index), radius: radius + 1., port,
                                drawn: context || highlighted_terminal,
                            });
                        }
                    }
                }
            }
        }

        if mode == Mode::Geographic && camera.mpp <= 1200. {
            for site in current.flat_map(|r| &r.references).filter(|site| site.period.contains(date)) {
                let Some(position) = project(camera, size, radial(site.coordinates)).filter(|p| visible(*p, size, 8.))
                    else { continue; };
                let ink = if selected_node == Some(&site.id) { SELECTED } else { [239, 211, 158, 232] };
                hollow_marker(&mut self.overlay, position, 4., ink, site.kind == "bridge");
                self.visible.push(VisibleNode {
                    position, id: site.id.clone(), terminal: None, radius: 5., port: false, drawn: true,
                });
            }
        }

        if mode != Mode::Military && camera.mpp <= 40. {
            for &(port, basin) in DOCK_BASINS {
                if center.angle_between(radial(basin)) * EARTH <= reach {
                    self.vehicle_segments.extend(self.incident.get(port).into_iter().flatten().filter(|id|
                        network.segment(id).is_some_and(|s| s.mode == TransportMode::PortTransfer)).cloned());
                }
            }
        }
        self.vehicle_segments.sort_unstable();
        self.vehicle_segments.dedup();
        self.previous_view = Some(view);
        self.previous_legs = selected_leg_ids().map(str::to_owned).collect();
        self.previous_selection = selection.cloned();
        self.revision = next_revision();
        self.update_flows(world, mode);
        Ok(())
    }

    pub fn segment_geometry(&self, id: &str) -> GeometryEvidence {
        if self.previous_view.as_ref().is_some_and(|view| self.reference_path(id, &view.date).is_some()) {
            GeometryEvidence::HistoricalCorridor
        } else if self.schematic.contains_key(id) {
            GeometryEvidence::Schematic
        } else {
            GeometryEvidence::Unmapped
        }
    }

    pub fn reference_site(&self, id: &str) -> Option<MappedSite<'_>> {
        let date = &self.previous_view.as_ref()?.date;
        let site = self.regions.iter().filter_map(|r| r.loaded.as_ref())
            .filter(|r| r.period.contains(date))
            .flat_map(|r| &r.references)
            .find(|site| site.id == id && site.period.contains(date))?;
        Some(MappedSite {
            name: &site.name,
            kind: &site.kind,
            source: &site.source,
            note: &site.note,
            coordinates: site.coordinates,
        })
    }

    pub fn node_corridors(&self, id: &str) -> &[String] {
        self.incident.get(id).map_or(&[], Vec::as_slice)
    }

    fn reference_path(&self, id: &str, date: &str) -> Option<&Path> {
        self.regions.iter().filter_map(|r| r.loaded.as_ref()).filter(|r| r.period.contains(date))
            .find_map(|r| r.routes.get(id))
    }

    pub fn pick(&self, cursor: [f64; 2]) -> Option<ObjectId> {
        let [x, y] = cursor.map(|coordinate| coordinate as f32);
        if let Some(hit) = self.vehicle_hits.iter().rev().find(|hit| {
            let [left, top, w, h] = hit.area;
            x >= left && x <= left + w && y >= top && y <= top + h
        }) {
            return Some(hit.id.clone());
        }
        let pointer = Vec2::new(x, y);
        if let Some(node) = self.nearest_node(pointer) {
            return Some(ObjectId::Node(node.id.clone()));
        }
        let subtle = self.previous_view.as_ref().is_some_and(|view| matches!(view.mode, Mode::Political | Mode::Military));
        let hit_radius: f32 = if subtle { 2.4 } else { 4. };
        self.paths.iter().filter_map(|path| {
            let distance = path.strokes().iter().map(|&(a, b)| distance_to_stroke(pointer, a, b))
                .min_by(f32::total_cmp)?;
            (distance <= hit_radius.powi(2)).then_some((distance, &path.id))
        }).min_by(|(a, _), (b, _)| a.total_cmp(b)).map(|(_, id)| ObjectId::Segment(id.clone()))
    }

    fn nearest_node(&self, pointer: Vec2) -> Option<&VisibleNode> {
        self.visible.iter().filter(|node| {
            (node.drawn || self.flow_nodes.contains(&node.id))
                && node.position.distance_squared(pointer) <= node.radius.powi(2)
        }).min_by(|a, b| {
            a.position.distance_squared(pointer).total_cmp(&b.position.distance_squared(pointer))
                .then_with(|| b.port.cmp(&a.port))
        })
    }

    fn nearest_terminal(&self, cursor: [f64; 2]) -> Option<usize> {
        self.nearest_node(Vec2::new(cursor[0] as f32, cursor[1] as f32))?.terminal
    }

    fn update_flows(&mut self, world: &InitialWorld, mode: Mode) {
        if mode != Mode::Economic {
            self.flow_nodes.clear();
            self.flow_overlay.vertices.clear();
            self.flow_overlay.indices.clear();
            return;
        }
        let movement = world.freight_movement_revision();
        let changed = self.flow_movement_revision != Some(movement) && self.update_freight(world, movement);
        if !changed && self.flow_view == Some(self.revision) {
            return;
        }
        self.flow_view = Some(self.revision);
        self.flow_nodes.clear();
        self.flow_overlay.vertices.clear();
        self.flow_overlay.indices.clear();
        if self.flow_by_segment.is_empty() {
            return;
        }
        for path in &self.paths {
            if let Some(&directed) = self.flow_by_segment.get(&path.id) {
                draw_flow(&mut self.flow_overlay, &path.fragments, directed);
            }
        }
        for node in &self.visible {
            if let Some(&[out, incoming]) = self.flow_by_terminal.get(&node.id) {
                self.flow_nodes.insert(node.id.clone());
                if !node.drawn {
                    hollow_marker(&mut self.flow_overlay, node.position, node.radius - 1., FLOW, false);
                }
                let r = 4.5 + node.radius;
                if out > 0 {
                    arrow(&mut self.flow_overlay, node.position + Vec2::new(r, -r), Vec2::X, flow_radius(out));
                }
                if incoming > 0 {
                    arrow(&mut self.flow_overlay, node.position + Vec2::new(-r, -r), Vec2::X, flow_radius(incoming));
                }
            }
        }
        if !self.flow_overlay.indices.is_empty() {
            self.flow_revision = next_revision();
        }
    }

    fn update_freight(&mut self, world: &InitialWorld, revision: u64) -> bool {
        self.flow_movement_revision = Some(revision);
        let mut segments = BTreeMap::new();
        let mut terminals = BTreeMap::<String, [u32; 2]>::new();
        for id in world.moving_transport_segments() {
            let Some(edge) = world.transport().segment(id) else { continue; };
            let mut directed = [0_u32; 2];
            for flow in world.economic_transport_on(id) {
                let direction = usize::from(edge.from != flow.from);
                directed[direction] = directed[direction].saturating_add(flow.load_units);
            }
            if directed != [0; 2] {
                segments.insert(id.to_owned(), directed);
                for (node, [out, incoming]) in [(&edge.from, directed), (&edge.to, [directed[1], directed[0]])] {
                    let totals = terminals.entry(node.clone()).or_default();
                    totals[0] = totals[0].saturating_add(out);
                    totals[1] = totals[1].saturating_add(incoming);
                }
            }
        }
        if self.flow_by_segment == segments {
            return false;
        }
        self.flow_by_segment = segments;
        self.flow_by_terminal = terminals;
        true
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
            let corridors: Vec<_> = self.node_corridors(&terminal.id).iter().filter(|id|
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
                if let Some(node) = self
                    .visible
                    .iter()
                    .find(|node| &node.id == other && node.drawn)
                {
                    let xy = node.position;
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
            return;
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

    pub fn economic_overlay(&self) -> Option<(u64, &Mesh)> {
        (!self.flow_overlay.indices.is_empty()).then_some((self.flow_revision, &self.flow_overlay))
    }

    pub fn draw_vehicles(
        &mut self,
        camera: &Camera,
        size: [u32; 2],
        world: &InitialWorld,
        models: &mut Vec<VisibleModel>,
        ready: impl Fn(&VisibleModel) -> bool,
    ) -> Mesh {
        self.vehicle_hits.clear();
        let mut hits = Vec::new();
        let network = world.transport();
        let mut markers = Mesh::default();
        let mut models_left = MODEL_BUDGET;
        let mut markers_left = MARKER_BUDGET;
        if camera.mpp > 1200. {
            return markers;
        }
        let Some(view) = &self.previous_view else {
            return markers;
        };
        let vehicles = self.vehicle_segments.iter().flat_map(|id| world.transport_vehicles_on(id));
        for vehicle in vehicles {
            if models_left == 0 && markers_left == 0 {
                break;
            }
            let selected = matches!(&self.previous_selection,
                Some(ObjectId::Vehicle { reservation, .. }) if *reservation == vehicle.reservation_id);
            if (view.mode == Mode::Political && !selected)
                || (view.mode == Mode::Economic && !vehicle.freight && !selected)
            {
                continue;
            }
            let object = || ObjectId::Vehicle {
                segment: vehicle.segment_id.to_owned(),
                reservation: vehicle.reservation_id,
            };
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
                                if ready(&model) {
                                    hits.push(VehicleHit { area: model.screen_bounds, id: object() });
                                } else if markers_left > 0 {
                                    vehicle_marker(&mut markers, position, Vec2::X, TransportMode::Shipping, vehicle.freight);
                                    hits.push(VehicleHit { area: marker_bounds(position), id: object() });
                                    markers_left -= 1;
                                }
                                if selected {
                                    selection_corners(&mut markers, position, 12.);
                                }
                                models.push(model);
                                models_left -= 1;
                            }
                        }
                    }
                }
                continue;
            }
            let reference = self.reference_path(vehicle.segment_id, &view.date);
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
            let first_hit = hits.len();
            for model in models[before..before + parts_added].iter().filter(|model| ready(model)) {
                hits.push(VehicleHit { area: model.screen_bounds, id: object() });
            }
            if first_hit == hits.len() && markers_left > 0 && visible(position, size, 10.) {
                vehicle_marker(&mut markers, position, heading, vehicle.mode, vehicle.freight);
                hits.push(VehicleHit { area: marker_bounds(position), id: object() });
                markers_left -= 1;
            }
            if selected && first_hit != hits.len() {
                selection_corners(&mut markers, position, 12.);
            }
        }
        self.vehicle_hits = hits;
        markers
    }
}

fn next_revision() -> u64 {
    DRAW_REVISION.fetch_add(1, Ordering::Relaxed).wrapping_add(1)
}

fn cell_axis(axis: f64) -> usize {
    (((axis + 1.) * (CELL_COUNT as f64 / 2.)) as usize).min(CELL_COUNT - 1)
}

fn cell_index([x, y, z]: [usize; 3]) -> usize {
    (x * CELL_COUNT + y) * CELL_COUNT + z
}

fn endpoint_polity<'a>(world: &'a InitialWorld, id: &str, date: &str) -> Option<&'a str> {
    let sources = world.sources();
    let polity = sources.place_polity(id).or_else(|| {
        let unit = world.transport().unit_at(id)?;
        sources.polities().get(unit)
    })?;
    (polity.valid_from.as_str() <= date && date < polity.valid_to.as_str()).then_some(polity.id.as_str())
}

fn endpoints_cross_jurisdiction(world: &InitialWorld, from: &str, to: &str, date: &str) -> bool {
    endpoint_polity(world, from, date).zip(endpoint_polity(world, to, date)).is_some_and(|(a, b)| a != b)
}

fn distance_to_stroke(pointer: Vec2, start: Vec2, end: Vec2) -> f32 {
    let span = end - start;
    let t = ((pointer - start).dot(span) / span.length_squared()).clamp(0., 1.);
    (start + span * t).distance_squared(pointer)
}

fn capacity_radius(units: u32) -> f32 {
    (2.8 + (units as f32 + 1.).log10() * 0.8).min(6.2)
}

fn flow_radius(units: u32) -> f32 {
    (3. + (units as f32 + 1.).log10()).min(7.)
}

fn with_alpha(mut color: [u8; 4], alpha: u8) -> [u8; 4] {
    color[3] = alpha;
    color
}

fn mode_ink(mode: TransportMode) -> [u8; 4] {
    match mode {
        TransportMode::Shipping => PORT_INK,
        TransportMode::InlandWaterway => RIVER,
        TransportMode::Rail => [229, 183, 120, 242],
        TransportMode::Road => [196, 179, 149, 194],
        _ => [200, 188, 151, 208],
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
    reach: &ViewReach,
    path: &Path,
    width: f32,
    ink: [u8; 4],
    projected: &mut VisiblePath,
) {
    let dashed = projected.dash_strokes.is_some();
    let mut phase: f32 = 0.0;
    let spans = path.chunks.iter().zip(path.spans.chunks(SPANS_PER_CHUNK))
        .filter(|(chunk, _)| dashed || reach.intersects(chunk.center, chunk.radius))
        .flat_map(|(_, spans)| spans);
    for span in spans {
        // Bounded angular interpolation keeps long shipping legs on the globe.
        let steps = ((span.end_m - span.start_m) / 240_000.0).ceil() as u32;
        let mut previous = project(camera, size, span.start);
        for step in 1..=steps {
            let point = if step == steps {
                span.end
            } else {
                let fraction = f64::from(step) / f64::from(steps);
                span.at(span.start_m + (span.end_m - span.start_m) * fraction).0
            };
            let next = project(camera, size, point);
            if let (Some(start), Some(end)) = (previous, next) {
                let delta = end - start;
                let length = delta.length();
                if let Some((first, last)) = clip_line(start, end, size).filter(|_| length > 0.02) {
                    let fragment = (start + delta * first, start + delta * last);
                    projected.fragments.push(fragment);
                    if let Some(strokes) = projected.dash_strokes.as_mut() {
                        let start = start + delta * first;
                        let end_m = (last - first) * length;
                        let unit = delta / length;
                        let mut at = -(phase + first * length).rem_euclid(14.0);
                        while at < end_m {
                            let begin = at.max(0.0);
                            let stop = (at + 8.0).min(end_m);
                            if begin < stop {
                                let first = start + unit * begin;
                                let last = start + unit * stop;
                                mesh.line(first.to_array(), last.to_array(), width, ink);
                                strokes.push((first, last));
                            }
                            at += 14.0;
                        }
                    } else {
                        mesh.line(fragment.0.to_array(), fragment.1.to_array(), width, ink);
                    }
                }
                if dashed {
                    phase = (phase + length).rem_euclid(14.0);
                }
            }
            previous = next;
        }
    }
}

fn draw_flow(mesh: &mut Mesh, fragments: &[(Vec2, Vec2)], directed: [u32; 2]) {
    if directed == [0; 2] {
        return;
    }
    let spacing = 86.;
    let length: f32 = fragments.iter().map(|(a, b)| a.distance(*b)).sum();
    if length < 12. {
        return;
    }
    let mut remaining = length.min(spacing) * 0.5;
    for &(a, b) in fragments {
        let delta = b - a;
        let length = delta.length();
        if length < 0.02 {
            continue;
        }
        let direction = delta / length;
        while remaining < length {
            let at = a + delta * (remaining / length);
            let sidestep = if directed.iter().all(|&load| load > 0) { 4. } else { 0. };
            for (sign, load) in [1., -1.].into_iter().zip(directed) {
                if load > 0 {
                    let forward = direction * sign;
                    arrow(mesh, at + forward.perp() * sidestep, forward, flow_radius(load));
                }
            }
            remaining += spacing;
        }
        remaining -= length;
    }
}

fn arrow(mesh: &mut Mesh, at: Vec2, direction: Vec2, radius: f32) {
    let side = direction.perp();
    let tip = at + direction * radius;
    let tail = at - direction * radius;
    mesh.line(tail.to_array(), tip.to_array(), 2.8, DARK);
    mesh.line(tail.to_array(), tip.to_array(), 1.3, FLOW);
    mesh.shape(&[
        tip.to_array(),
        (at + side * (radius * 0.58)).to_array(),
        (at - side * (radius * 0.58)).to_array(),
    ], FLOW);
}

fn marker_bounds(position: Vec2) -> [f32; 4] {
    [position.x - 8., position.y - 6., 16., 12.]
}

fn selection_corners(mesh: &mut Mesh, at: Vec2, r: f32) {
    for [dx, dy] in [[-1., -1.], [-1., 1.], [1., -1.], [1., 1.]] {
        let corner = [at.x + dx * r, at.y + dy * r];
        mesh.line(corner, [corner[0] - dx * 4., corner[1]], 1.4, SELECTED);
        mesh.line(corner, [corner[0], corner[1] - dy * 4.], 1.4, SELECTED);
    }
}

fn hollow_marker(mesh: &mut Mesh, point: Vec2, r: f32, ink: [u8; 4], bridge: bool) {
    let [x, y] = point.to_array();
    if bridge {
        mesh.line([x - r, y], [x + r, y], 3.5, DARK);
        mesh.line([x - r, y], [x + r, y], 1.7, ink);
        for dx in [-r, r] {
            mesh.line([x + dx, y - 2.5], [x + dx, y + 2.5], 1.6, ink);
        }
    } else {
        mesh.rect(x - r - 1., y - r - 1., 2. * r + 2., 2. * r + 2., DARK);
        mesh.rect(x - r, y - r, 2. * r, 2. * r, ink);
        mesh.rect(x - r + 1.4, y - r + 1.4, 2. * r - 2.8, 2. * r - 2.8, DARK);
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
