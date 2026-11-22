//! Country statistics describe aggregate access. Only named corridors supply international edges.
use super::{
    NodeKind, SegmentProfile, TransportMode, TransportNetwork, TransportNode, TransportSegment,
};
use crate::formal_bootstrap::WorldSources;
use serde::{de::DeserializeOwned, Deserialize};
use serde_json::Value;
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
};

const COMPACT: &[u8] = include_bytes!(
    "../../../../data/alpha/historical_transport_network_1900/transport_compact.json"
);
const POSITIONS: &[u8] = include_bytes!(
    "../../../../data/alpha/historical_transport_network_1900/gateway_positions.json"
);
const RIVER_BINDINGS: &[u8] = include_bytes!(
    "../../../../data/alpha/historical_transport_network_1900/river_hub_bindings.json"
);
const MAP_IDENTITIES: &[u8] =
    include_bytes!("../../../../data/alpha/historical_transport_network_1900/map_identities.json");
const BASELINE: &str = "1900-01-01";
const RAIL: &[u8] = include_bytes!(
    "../../../../data/alpha/historical_transport_network_1900/international_rail.json"
);

type PlaceRow = (
    String,
    String,
    String,
    [f64; 2],
    MapIdentityKind,
    String,
    String,
    Option<String>,
);

#[derive(Deserialize)]
struct MapRows {
    places: Vec<PlaceRow>,
    polities: Vec<(String, String, MapIdentityKind, String, String)>,
}

pub(crate) fn opening_place_jurisdictions() -> io::Result<BTreeMap<String, String>> {
    let rows: MapRows = serde_json::from_slice(MAP_IDENTITIES)?;
    Ok(rows.places.into_iter().filter_map(|(id, _, _, _, kind, from, to, polity)| {
        (kind == MapIdentityKind::Place && from.as_str() <= BASELINE && BASELINE < to.as_str())
            .then_some(polity).flatten().map(|polity| (id, polity))
    }).collect())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetworkLayer {
    Detailed,
    Domestic,
    Maritime,
    River,
    Transfer,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeCoverage {
    Unknown,
    Unrefined,
    Connected,
    Impassable,
}

#[derive(Debug, Clone)]
pub struct SegmentEvidence {
    pub layer: NetworkLayer,
    pub source: String,
    /// Opening calibration. A missing retirement date continues with the world's operating state.
    pub as_of: &'static str,
    pub opened_on: Option<String>,
    pub confidence_bp: Option<u32>,
}
impl SegmentEvidence {
    pub fn applies_on(&self, iso_date: &str) -> bool {
        iso_date >= self.opened_on.as_deref().unwrap_or(self.as_of)
    }
}

#[derive(Debug, Deserialize)]
pub struct DomesticStatistics {
    pub entity_id: String,
    pub rail_route_km: u32,
    pub rail_lower_km: u32,
    pub rail_upper_km: u32,
    pub waterway_km: u32,
    pub port_capacity_index: u32,
    pub merchant_shipping_index: u32,
    pub network_class: String,
    pub confidence_bp: u32,
    pub gateway_ports: Vec<String>,
}
#[derive(Deserialize)]
struct Maritime {
    corridor_id: String,
    origin_port: String,
    destination_port: String,
    origin_entity_id: String,
    destination_entity_id: String,
    duration_days: u32,
    capacity_index: u32,
    mode: String,
    confidence_bp: u32,
}
#[derive(Deserialize)]
struct River {
    corridor_id: String,
    entity_ids: Vec<String>,
    hubs: Vec<String>,
    capacity_index: u32,
    seasonality_bp: u32,
}
#[derive(Deserialize)]
struct Table {
    schema_id: String,
    domestic_field_order: Vec<String>,
    domestic_rows: Vec<Vec<Value>>,
    maritime_field_order: Vec<String>,
    maritime_rows: Vec<Vec<Value>>,
    river_field_order: Vec<String>,
    river_rows: Vec<Vec<Value>>,
}
fn records<T: DeserializeOwned>(fields: Vec<String>, rows: Vec<Vec<Value>>) -> io::Result<Vec<T>> {
    if fields.iter().collect::<BTreeSet<_>>().len() != fields.len() {
        return Err(invalid("duplicate transport column"));
    }
    rows.into_iter()
        .map(|row| {
            if row.len() != fields.len() {
                return Err(invalid("incomplete transport record"));
            }
            let object = fields.iter().cloned().zip(row).collect();
            Ok(serde_json::from_value(Value::Object(object))?)
        })
        .collect()
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MapIdentityKind {
    Place,
    Reference,
    Polity,
    DisplayPolity,
}

pub struct MapIdentity {
    pub kind: MapIdentityKind,
    pub from_date: String,
    pub to_date_exclusive: String,
}
impl MapIdentity {
    pub fn applies_on(&self, date: &str) -> bool {
        self.from_date.as_str() <= date && date < self.to_date_exclusive.as_str()
    }
}

#[derive(Default)]
pub(super) struct Catalogue {
    nodes: BTreeMap<String, NodeRecord>,
    map_identities: BTreeMap<String, MapIdentity>,
    map_targets: BTreeMap<String, String>,
    no_transport_evidence: BTreeSet<String>,
    notes: BTreeMap<String, Vec<String>>,
    river_gaps: BTreeMap<(String, String), (NodeCoverage, String)>,
    population_nodes: BTreeSet<String>,
    population_parents: BTreeMap<String, String>,
    population_at: BTreeMap<String, String>,
    areas: BTreeMap<String, String>,
    capitals: BTreeMap<String, String>,
    domestic: BTreeMap<String, DomesticStatistics>,
    evidence: BTreeMap<String, SegmentEvidence>,
    pub(super) former_profiles: BTreeMap<String, (SegmentProfile, bool)>,
}
struct NodeRecord {
    label: String,
    unit: Option<String>,
    point: Option<[f64; 2]>,
}
impl Catalogue {
    pub(super) fn known(&self, id: &str) -> bool {
        self.nodes.contains_key(id)
    }
}

impl TransportNetwork {
    pub fn area_node(&self, unit: &str) -> Option<&str> {
        self.catalogue.areas.get(unit).map(String::as_str)
    }
    /// Stable identity for a formal root or partition. Coverage reports whether it can be routed.
    pub fn population_node(&self, unit: &str) -> Option<&str> {
        self.catalogue
            .population_nodes
            .get(unit)
            .map(String::as_str)
            .or_else(|| self.area_node(unit))
    }
    pub fn population_parent<'a>(&'a self, unit: &str) -> Option<&'a str> {
        self.catalogue
            .population_parents
            .get(unit)
            .map(String::as_str)
            .or_else(|| {
                self.catalogue
                    .areas
                    .get_key_value(unit)
                    .map(|(key, _)| key.as_str())
            })
    }
    pub fn population_at(&self, id: &str) -> Option<&str> {
        self.catalogue
            .population_at
            .get(id)
            .or_else(|| {
                self.routing_node(id)
                    .and_then(|key| self.catalogue.population_at.get(key))
            })
            .map(String::as_str)
            .or_else(|| self.unit_at(id))
    }
    pub fn capital_node(&self, polity: &str) -> Option<&str> {
        self.catalogue.capitals.get(polity).map(String::as_str)
    }
    pub fn map_identities(&self) -> impl Iterator<Item = (&str, &MapIdentity)> {
        self.catalogue
            .map_identities
            .iter()
            .map(|(k, v)| (k.as_str(), v))
    }
    pub fn notes_at<'a>(&'a self, id: &str) -> impl Iterator<Item = &'a str> {
        let target = self.routing_node(id).filter(|&key| key != id);
        self.catalogue
            .notes
            .get(id)
            .into_iter()
            .chain(target.and_then(|key| self.catalogue.notes.get(key)))
            .flatten()
            .map(String::as_str)
    }
    /// Named river reaches with a documented obstacle or an unidentified endpoint.
    pub fn river_gap(&self, a: &str, b: &str) -> Option<(NodeCoverage, &str)> {
        let a = self.routing_node(a)?;
        let b = self.routing_node(b)?;
        self.catalogue
            .river_gaps
            .get(&(a.min(b).into(), a.max(b).into()))
            .map(|(s, n)| (*s, n.as_str()))
    }
    pub fn routing_node(&self, id: &str) -> Option<&str> {
        if let Some(hub) = self.catalogue.map_targets.get(id) {
            return Some(hub);
        }
        if let Some(capital) = id.strip_prefix("state:").and_then(|p| self.capital_node(p)) {
            return Some(capital);
        }
        self.node(id).map(|n| n.id.as_str())
    }
    pub fn unit_at(&self, node: &str) -> Option<&str> {
        self.catalogue
            .nodes
            .get(self.routing_node(node)?)?
            .unit
            .as_deref()
    }
    pub fn node_label(&self, node: &str) -> Option<&str> {
        Some(&self.catalogue.nodes.get(&self.node(node)?.id)?.label)
    }
    pub fn node_coordinates(&self, node: &str) -> Option<[f64; 2]> {
        self.catalogue
            .nodes
            .get(node)
            .and_then(|n| n.point)
            .or_else(|| {
                self.catalogue
                    .nodes
                    .get(self.routing_node(node)?)
                    .and_then(|n| n.point)
            })
    }
    pub fn evidence(&self, segment: &str) -> Option<&SegmentEvidence> {
        self.catalogue.evidence.get(&self.segment(segment)?.id)
    }
    pub fn domestic_statistics(&self, unit: &str) -> Option<&DomesticStatistics> {
        self.catalogue.domestic.get(unit)
    }
    pub fn coverage(&self, id: &str) -> NodeCoverage {
        let Some(&index) = self.routing_node(id).and_then(|key| self.node_ids.get(key)) else {
            return NodeCoverage::Unknown;
        };
        if self.catalogue.no_transport_evidence.contains(id) {
            return NodeCoverage::Unknown;
        }
        let arcs = &self.outgoing[index];
        if arcs.is_empty() {
            NodeCoverage::Unrefined
        } else if arcs
            .iter()
            .any(|arc| self.availability[arc.segment].supports(1))
        {
            NodeCoverage::Connected
        } else {
            NodeCoverage::Impassable
        }
    }
}

struct Builder {
    kinds: BTreeMap<String, NodeKind>,
    catalogue: Catalogue,
    segments: Vec<TransportSegment>,
    // Physical city and waterside identities must resolve independently for transfers.
    cities: BTreeMap<(String, String), String>,
    piers: BTreeMap<String, String>,
    positions: BTreeMap<String, [f64; 2]>,
    aliases: BTreeMap<String, String>,
    river_bindings: BTreeMap<(String, String), String>,
}
fn invalid(msg: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, msg.into())
}
fn key(name: &str) -> String {
    let slug = name
        .to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .collect::<Vec<_>>()
        .join("_");
    match slug.as_str() {
        "saint_petersburg_petrograd" | "saint_petersburg" => "st_petersburg".into(),
        "constantinople" => "istanbul".into(),
        "calcutta" => "kolkata".into(),
        "canton" => "guangzhou".into(),
        "nanking" => "nanjing".into(),
        "hankow" => "hankou".into(),
        "christiania" => "oslo".into(),
        "saint_louis" => "st_louis".into(),
        _ => slug,
    }
}
fn evidence(layer: NetworkLayer, source: String, confidence_bp: Option<u32>) -> SegmentEvidence {
    SegmentEvidence {
        layer,
        source,
        as_of: BASELINE,
        opened_on: None,
        confidence_bp,
    }
}
impl Builder {
    fn register(
        &mut self,
        id: &str,
        kind: NodeKind,
        label: &str,
        unit: Option<&str>,
        point: Option<[f64; 2]>,
    ) {
        self.kinds.entry(id.into()).or_insert(kind);
        let record = self
            .catalogue
            .nodes
            .entry(id.into())
            .or_insert_with(|| NodeRecord {
                label: label.into(),
                unit: unit.map(str::to_owned),
                point,
            });
        if record.point.is_none() {
            record.point = point;
        }
    }
    fn city(
        &mut self,
        scope: &str,
        unit: Option<&str>,
        name: &str,
        point: Option<[f64; 2]>,
    ) -> String {
        let slug = key(name);
        let id = self
            .cities
            .entry((scope.into(), slug.clone()))
            .or_insert_with(|| format!("hub:{scope}:{slug}"))
            .clone();
        let point = point.or_else(|| self.positions.get(&slug).copied());
        self.register(&id, NodeKind::City, name, unit, point);
        id
    }
    fn add(
        &mut self,
        id: String,
        from: &str,
        to: &str,
        mode: TransportMode,
        profile: SegmentProfile,
        origin: SegmentEvidence,
    ) {
        self.catalogue.evidence.insert(id.clone(), origin);
        self.segments.push(TransportSegment {
            id,
            from: from.into(),
            to: to.into(),
            mode,
            profile,
            bidirectional: true,
            prototype_only: false,
        });
    }
    fn pier(
        &mut self,
        city: &str,
        river: bool,
        capacity: u32,
        source: &str,
        confidence: Option<u32>,
    ) -> String {
        if !river {
            if let Some(id) = self.piers.get(city) {
                return id.clone();
            }
        }
        let prefix = if river { "landing" } else { "water" };
        let base = city
            .strip_prefix("hub:")
            .or_else(|| city.strip_prefix("place:"))
            .unwrap_or(city);
        let id = format!("{prefix}:{base}");
        if !self.kinds.contains_key(&id) {
            let rec = &self.catalogue.nodes[city];
            let (label, unit, point) = (rec.label.clone(), rec.unit.clone(), rec.point);
            // For a port serving several sea corridors, handling cannot depend on row order.
            let (capacity, source, confidence) =
                match unit.as_ref().and_then(|u| self.catalogue.domestic.get(u)) {
                    Some(stats) if !river => (
                        stats.port_capacity_index.max(1),
                        format!(
                            "transport_compact.json/domestic_rows/{} (port handling estimate)",
                            stats.entity_id
                        ),
                        Some(stats.confidence_bp),
                    ),
                    _ => (capacity, source.to_owned(), confidence),
                };
            self.register(&id, NodeKind::Port, &label, unit.as_deref(), point);
            self.add(
                format!("transfer:{id}"),
                city,
                &id,
                TransportMode::PortTransfer,
                SegmentProfile {
                    travel_minutes: 90,
                    cost_units: 4,
                    capacity_units: capacity.max(1),
                    risk_points: 1,
                },
                evidence(NetworkLayer::Transfer, source, confidence),
            );
        }
        id
    }
    fn attach_domestic(&mut self, unit: &str, city: &str, external: bool) {
        let stats = &self.catalogue.domestic[unit];
        // A national total supports a coarse access leg, never a station or a new rail alignment.
        let (hours, land_capacity) = match stats.network_class.as_str() {
            "continental_dense" => (18, 120),
            "national_dense" => (24, 90),
            "developing_trunk" => (36, 60),
            _ => (60, 24),
        };
        let capacity = (land_capacity + stats.port_capacity_index) / 2;
        let hours = if external { hours * 2 } else { hours };
        let source = format!(
            "transport_compact.json/domestic_rows/{unit} ({})",
            stats.network_class
        );
        let origin = evidence(NetworkLayer::Domestic, source, Some(stats.confidence_bp));
        self.add(
            format!("access:{unit}:{city}"),
            &format!("area:{unit}"),
            city,
            TransportMode::Domestic,
            SegmentProfile {
                travel_minutes: hours * 60,
                cost_units: hours / 3 + 1,
                capacity_units: capacity.max(1),
                risk_points: 3,
            },
            origin,
        );
    }
}

pub(super) fn load(
    sources: &WorldSources,
    nodes: Vec<TransportNode>,
    detailed: Vec<TransportSegment>,
    cache_limit: usize,
) -> io::Result<TransportNetwork> {
    let table: Table = serde_json::from_slice(COMPACT)?;
    if table.schema_id != "historical_transport_network_1900_compact_tables_v1" {
        return Err(invalid("unknown historical transport table"));
    }
    let domestic: Vec<DomesticStatistics> =
        records(table.domestic_field_order, table.domestic_rows)?;
    let maritime: Vec<Maritime> = records(table.maritime_field_order, table.maritime_rows)?;
    let rivers: Vec<River> = records(table.river_field_order, table.river_rows)?;
    #[derive(Deserialize)]
    struct Positions {
        positions: Vec<(String, String, [f64; 2])>,
    }
    let positions: Positions = serde_json::from_slice(POSITIONS)?;
    #[derive(Deserialize)]
    struct Bindings {
        bindings: Vec<(String, String, String, String)>,
        sources: BTreeMap<String, String>,
    }
    let bindings: Bindings = serde_json::from_slice(RIVER_BINDINGS)?;
    let mut river_bindings = BTreeMap::new();
    for (corridor, hub, unit, source) in bindings.bindings {
        if !bindings.sources.contains_key(&source)
            || river_bindings.insert((corridor, hub), unit).is_some()
        {
            return Err(invalid("invalid river hub binding"));
        }
    }
    let mut b = Builder {
        kinds: nodes.into_iter().map(|n| (n.id, n.kind)).collect(),
        catalogue: Catalogue::default(),
        segments: detailed,
        cities: BTreeMap::new(),
        piers: BTreeMap::new(),
        positions: positions
            .positions
            .into_iter()
            .map(|(name, _, p)| (key(&name), p))
            .collect(),
        aliases: BTreeMap::new(),
        river_bindings,
    };
    for seg in &b.segments {
        if seg.mode == TransportMode::PortTransfer {
            b.piers.insert(seg.from.clone(), seg.to.clone());
        }
        b.catalogue.evidence.insert(
            seg.id.clone(),
            evidence(
                NetworkLayer::Detailed,
                format!(
                    "world_map/{}:{}",
                    match seg.mode {
                        TransportMode::Road => "road_segments.json",
                        TransportMode::Rail => "rail_segments.json",
                        TransportMode::Shipping => "shipping_routes.json",
                        _ => "ports.json",
                    },
                    seg.id
                ),
                None,
            ),
        );
    }
    for (id, place) in sources.places() {
        let unit = sources.population_unit_at(id);
        let kind = b.kinds.get(id).copied().unwrap_or(NodeKind::Identity);
        b.register(id, kind, &place.name, unit, place.lon_lat);
        if let (NodeKind::City, Some(unit)) = (kind, unit) {
            b.cities.insert((unit.into(), key(&place.id)), id.clone());
        }
    }
    for unit in sources.population_units() {
        let id = format!("area:{unit}");
        let label = sources
            .polities()
            .get(unit)
            .map(|p| p.name_zh.as_str())
            .unwrap_or(unit);
        b.register(&id, NodeKind::Area, label, Some(unit), None);
        b.catalogue.areas.insert(unit.into(), id);
    }
    for (id, polity) in sources.polities() {
        let unit = sources
            .polity_population_bindings()
            .get(id)
            .map(String::as_str);
        b.register(
            &polity.runtime_id(),
            NodeKind::Identity,
            &polity.name_zh,
            unit,
            None,
        );
        if let Some(capital) = &polity.capital {
            let hub = b.city(
                unit.unwrap_or(id),
                unit,
                &capital.name,
                Some([capital.lon, capital.lat]),
            );
            b.catalogue.capitals.insert(id.clone(), hub);
        }
    }
    let mut external = Vec::new();
    for stats in domestic {
        let unit = stats.entity_id.clone();
        if !b.catalogue.areas.contains_key(&unit)
            || stats.rail_lower_km > stats.rail_route_km
            || stats.rail_route_km > stats.rail_upper_km
            || stats.confidence_bp > 10000
            || b.catalogue.domestic.contains_key(&unit)
        {
            return Err(invalid(format!("invalid domestic statistics {unit}")));
        }
        for name in &stats.gateway_ports {
            if let Some(name) = name.strip_suffix(" (external gateway)") {
                external.push((unit.clone(), name.to_owned()));
            } else {
                b.city(&unit, Some(&unit), name, None);
            }
        }
        b.catalogue.domestic.insert(unit, stats);
    }
    for route in maritime {
        b.import_sea(route)?;
    }
    for river in rivers {
        b.import_river(river)?;
    }
    b.import_international_rail()?;
    if !b.river_bindings.is_empty() {
        return Err(invalid("unmatched river hub binding"));
    }
    b.bind_domestic();
    for (unit, name) in external {
        // The source explicitly labels the external gateway. Unknown host jurisdiction stays unknown.
        let slug = key(&name);
        let mut matches = b
            .cities
            .iter()
            .filter(|((_, n), _)| *n == slug)
            .map(|(_, id)| id.clone());
        let first = matches.next();
        let hub = if let Some(id) = first.filter(|_| matches.next().is_none()) {
            id
        } else {
            b.city("external", None, &name, None)
        };
        b.attach_domestic(&unit, &hub, true);
    }
    b.allocate_national_capacity();
    b.import_map_identities(sources)?;
    b.bind_population(sources)?;
    let nodes = b
        .kinds
        .into_iter()
        .map(|(id, kind)| TransportNode { id, kind })
        .collect();
    let mut network = TransportNetwork::new(nodes, b.segments, cache_limit).map_err(invalid)?;
    for (unit, id) in &b.catalogue.areas {
        for alias in [unit.clone(), format!("market:legacy_aggregate:{unit}")] {
            network.node_ids.insert(alias, network.node_ids[id]);
        }
    }
    for (alias, id) in b.aliases {
        let index = network.segment_ids[&id];
        if network.segment_ids.insert(alias, index).is_some() {
            return Err(invalid("duplicate historical corridor alias"));
        }
    }
    network.catalogue = b.catalogue;
    Ok(network)
}
impl Builder {
    fn bind_population(&mut self, sources: &WorldSources) -> io::Result<()> {
        let opening = sources
            .historical_population
            .as_deref()
            .ok_or_else(|| invalid("missing historical population opening"))?;
        let mut places_by_leaf: BTreeMap<&str, Vec<String>> = BTreeMap::new();
        for (place, leaf) in opening.residence_places() {
            let physical = self
                .catalogue
                .map_targets
                .get(place)
                .map_or(place, String::as_str);
            if !self.kinds.contains_key(physical) {
                return Err(invalid(format!(
                    "unknown population residence point {place}"
                )));
            }
            self.catalogue
                .population_at
                .insert(physical.to_owned(), leaf.to_owned());
            places_by_leaf.entry(leaf).or_default().push(place.into());
        }
        #[derive(Deserialize)]
        struct SiteList {
            sites: Vec<(String, String, String)>,
            #[serde(default)]
            partition_successors: BTreeMap<String, String>,
        }
        let sites: SiteList = serde_json::from_slice(include_bytes!(
            "../../../../data/alpha/historical_transport_network_1900/residence_sites.json"
        ))?;
        let parents: BTreeMap<_, _> = opening
            .partition_identities()
            .map(|(leaf, parent, _)| (leaf, parent))
            .collect();
        for (archived_leaf, city, source) in &sites.sites {
            let leaf = if parents.contains_key(archived_leaf.as_str()) {
                archived_leaf
            } else {
                sites.partition_successors.get(archived_leaf).unwrap_or(archived_leaf)
            };
            let parent = parents
                .get(leaf.as_str())
                .ok_or_else(|| invalid(format!("unknown census partition {leaf}")))?;
            let hub = self
                .cities
                .get(&(parent.to_string(), key(city)))
                .ok_or_else(|| {
                    invalid(format!(
                        "unknown historical settlement {city} ({parent}, {source})"
                    ))
                })?;
            if self
                .catalogue
                .population_at
                .insert(hub.clone(), leaf.clone())
                .is_some_and(|before| before != *leaf)
            {
                return Err(invalid(format!("conflicting census partition for {hub}")));
            }
            places_by_leaf.entry(leaf).or_default().push(hub.clone());
        }
        for root in opening.standalone_ids() {
            let label = opening.collective_scope_name(root).unwrap_or_else(|| &sources.polities()[root].name_zh);
            self.register(root, NodeKind::Identity, label, None, None);
            self.catalogue.population_nodes.insert(root.into());
            self.catalogue
                .population_parents
                .insert(root.into(), root.into());
            self.catalogue
                .population_at
                .insert(root.into(), root.into());
            if let Some(capital) = self.catalogue.capitals.get(root) {
                self.catalogue
                    .map_targets
                    .insert(root.into(), capital.clone());
                self.catalogue
                    .population_at
                    .entry(capital.clone())
                    .or_insert_with(|| root.into());
            }
            self.catalogue
                .notes
                .entry(root.into())
                .or_default()
                .push("独立人口统计组。开局资料没有为这组人口设置市场。".into());
        }
        // A handling segment joins the city to its own terminal. It cannot establish
        // residence across a shipping, rail or river corridor.
        for seg in self
            .segments
            .iter()
            .filter(|s| s.mode == TransportMode::PortTransfer)
        {
            let from = self.catalogue.population_at.get(&seg.from);
            let to = self.catalogue.population_at.get(&seg.to);
            let missing = match (from, to) {
                (Some(a), Some(b)) if a != b => {
                    return Err(invalid("contradictory port residence binding"))
                }
                (Some(leaf), None) => Some((&seg.to, leaf.clone())),
                (None, Some(leaf)) => Some((&seg.from, leaf.clone())),
                _ => None,
            };
            if let Some((id, leaf)) = missing {
                self.catalogue.population_at.insert(id.clone(), leaf);
            }
        }
        let operational: BTreeSet<_> = self
            .segments
            .iter()
            .flat_map(|s| [s.from.clone(), s.to.clone()])
            .collect();
        // Keep existing provincial routes when a census partition gains district accounts.
        // Only the districts bind residents to the physical stops.
        for (id, _, _, members) in opening.statistical_scopes() {
            let places: Vec<_> = members.iter()
                .filter_map(|child| places_by_leaf.get(child.as_str()))
                .flatten()
                .cloned()
                .collect();
            places_by_leaf.insert(id, places);
        }
        let identities = opening.partition_identities()
            .chain(opening.statistical_scopes().map(|(id, parent, label, _)| (id, parent, label)));
        for (id, parent, label) in identities {
            let market = self.catalogue.areas.contains_key(parent).then_some(parent);
            self.register(id, NodeKind::Identity, label, market, None);
            self.catalogue.population_nodes.insert(id.into());
            self.catalogue
                .population_parents
                .insert(id.into(), parent.into());
            self.catalogue.population_at.insert(id.into(), id.into());
            // Several independently documented places can belong to one census division.
            // Resolve its default stop to one existing city; retain each physical place's account.
            let target = places_by_leaf
                .get(id)
                .into_iter()
                .flatten()
                .map(|p| self.catalogue.map_targets.get(p).unwrap_or(p).as_str())
                .min_by_key(|p| {
                    (
                        !operational.contains(*p),
                        self.kinds[*p] != NodeKind::City,
                        *p,
                    )
                })
                .map(str::to_owned);
            if let Some(place) = target {
                self.catalogue.map_targets.insert(id.into(), place);
            } else {
                self.catalogue
                    .notes
                    .entry(id.into())
                    .or_default()
                    .push(format!(
                        "开局人口分区，归属 {parent}。现有资料未绑定具体运营接入点。"
                    ));
            }
        }
        for (alias, target) in &self.catalogue.map_targets {
            if let Some(leaf) = self.catalogue.population_at.get(target).cloned() {
                self.catalogue
                    .population_at
                    .entry(alias.clone())
                    .or_insert(leaf);
            }
        }
        opening.bind_operating_places(&self.catalogue.population_at);
        Ok(())
    }

    /// The domestic table supplies one estimate per country, with no port-by-port shares.
    fn allocate_national_capacity(&mut self) {
        #[derive(Clone, Copy, Eq, Ord, PartialEq, PartialOrd)]
        enum Pool { Access, Port }
        let mut pools = BTreeMap::<(String, Pool), Vec<usize>>::new();
        for (index, segment) in self.segments.iter().enumerate() {
            let (unit, pool) = match segment.mode {
                TransportMode::Domestic => (segment.from.strip_prefix("area:"), Pool::Access),
                TransportMode::PortTransfer if segment.to.starts_with("water:") || segment.prototype_only => {
                    (self.catalogue.nodes.get(&segment.from).and_then(|n| n.unit.as_deref()), Pool::Port)
                }
                _ => continue,
            };
            if let Some(unit) = unit.filter(|u| self.catalogue.domestic.contains_key(*u)) {
                pools.entry((unit.to_owned(), pool)).or_default().push(index);
            }
        }
        for ((unit, pool), mut indices) in pools {
            indices.sort_unstable_by(|&a, &b| self.segments[a].id.cmp(&self.segments[b].id));
            let total = match pool {
                Pool::Access => self.segments[indices[0]].profile.capacity_units,
                Pool::Port => self.catalogue.domestic[&unit].port_capacity_index,
            };
            let count = indices.len() as u32;
            for (rank, index) in indices.into_iter().enumerate() {
                let segment = &mut self.segments[index];
                let share = total / count + u32::from((rank as u32) < total % count);
                if share != segment.profile.capacity_units {
                    self.catalogue.former_profiles.insert(segment.id.clone(), (segment.profile, segment.prototype_only));
                    segment.profile.capacity_units = share;
                }
                let note = self.catalogue.evidence.get_mut(&segment.id).expect("catalogued capacity source");
                note.source.push_str(&format!("; domestic_rows/{unit}: national estimate {total} shared by {count} links, this link {share} (equal shares; remainders by segment ID)"));
            }
        }
    }

    fn import_map_identities(&mut self, sources: &WorldSources) -> io::Result<()> {
        let rows: MapRows = serde_json::from_slice(MAP_IDENTITIES)?;
        for (id, name, label, point, kind, from_date, to_date_exclusive, polity) in rows.places {
            if !self.kinds.contains_key(&id) {
                let keys = [key(&name), key(id.strip_prefix("place:").unwrap_or(&id))];
                let unit = polity
                    .as_ref()
                    .and_then(|p| sources.polity_population_bindings().get(p));
                let mut matches = self
                    .cities
                    .iter()
                    .filter(|((_, city), node)| {
                        if kind != MapIdentityKind::Place || !keys.contains(city) {
                            return false;
                        }
                        let record = &self.catalogue.nodes[*node];
                        match record.point {
                            Some(p) => super::map_data::distance_km(point, p) <= 20.0,
                            None => unit.is_some() && record.unit.as_ref() == unit,
                        }
                    })
                    .map(|(_, id)| id.clone());
                let candidate = matches.next().filter(|_| matches.next().is_none());
                if let Some(target) = candidate {
                    let record = self.catalogue.nodes.get_mut(&target).unwrap();
                    record.point.get_or_insert(point);
                    self.catalogue.map_targets.insert(id.clone(), target);
                } else {
                    self.catalogue.no_transport_evidence.insert(id.clone());
                    let note = if kind == MapIdentityKind::Reference {
                        "地图参考地点。资料仅给出位置。"
                    } else {
                        "地图登记了该地点，现有交通来源未给出可运营连接。"
                    };
                    self.catalogue
                        .notes
                        .entry(id.clone())
                        .or_default()
                        .push(note.into());
                }
                self.register(&id, NodeKind::Identity, &label, None, Some(point));
            }
            self.catalogue.map_identities.insert(
                id,
                MapIdentity {
                    kind,
                    from_date,
                    to_date_exclusive,
                },
            );
        }
        for (id, label, kind, from_date, to_date_exclusive) in rows.polities {
            if !self.kinds.contains_key(&id) {
                self.register(&id, NodeKind::Identity, &label, None, None);
                self.catalogue.no_transport_evidence.insert(id.clone());
                self.catalogue
                    .notes
                    .entry(id.clone())
                    .or_default()
                    .push("地图登记的政治身份，现有交通来源未给出独立运营节点。".into());
            }
            self.catalogue.map_identities.insert(
                id,
                MapIdentity {
                    kind,
                    from_date,
                    to_date_exclusive,
                },
            );
        }
        Ok(())
    }
    fn import_international_rail(&mut self) -> io::Result<()> {
        #[derive(Deserialize)]
        struct Rail {
            id: String,
            origin_entity_id: String,
            origin_city: String,
            destination_entity_id: String,
            destination_city: String,
            station_pair: String,
            opened_on: String,
            source: String,
            profile_basis: String,
            profile: SegmentProfile,
        }
        for row in serde_json::from_slice::<Vec<Rail>>(RAIL)? {
            if row.opened_on.as_str() > BASELINE
                || row.profile.travel_minutes == 0
                || row.profile.capacity_units == 0
                || row.origin_entity_id == row.destination_entity_id
                || ![&row.origin_entity_id, &row.destination_entity_id]
                    .iter()
                    .all(|u| self.catalogue.areas.contains_key(*u))
            {
                return Err(invalid(format!(
                    "invalid international rail corridor {}",
                    row.id
                )));
            }
            let from = self.city(
                &row.origin_entity_id,
                Some(&row.origin_entity_id),
                &row.origin_city,
                None,
            );
            let to = self.city(
                &row.destination_entity_id,
                Some(&row.destination_entity_id),
                &row.destination_city,
                None,
            );
            let source = format!(
                "{}; {}. {}",
                row.station_pair, row.source, row.profile_basis
            );
            let mut origin = evidence(NetworkLayer::Detailed, source, None);
            origin.opened_on = Some(row.opened_on);
            self.add(row.id, &from, &to, TransportMode::Rail, row.profile, origin);
        }
        Ok(())
    }

    fn import_sea(&mut self, sea: Maritime) -> io::Result<()> {
        if sea.mode != "steamship"
            || sea.duration_days == 0
            || sea.capacity_index == 0
            || sea.confidence_bp > 10000
            || ![&sea.origin_entity_id, &sea.destination_entity_id]
                .iter()
                .all(|u| self.catalogue.areas.contains_key(*u))
        {
            return Err(invalid(format!(
                "invalid maritime record {}",
                sea.corridor_id
            )));
        }
        let source = format!(
            "transport_compact.json/maritime_rows/{} ({} days, capacity index {})",
            sea.corridor_id, sea.duration_days, sea.capacity_index
        );
        let origin = evidence(
            NetworkLayer::Maritime,
            source.clone(),
            Some(sea.confidence_bp),
        );
        let capacity = sea
            .capacity_index
            .checked_mul(3)
            .ok_or_else(|| invalid("invalid sea capacity"))?;
        let from = self.city(
            &sea.origin_entity_id,
            Some(&sea.origin_entity_id),
            &sea.origin_port,
            None,
        );
        let to = self.city(
            &sea.destination_entity_id,
            Some(&sea.destination_entity_id),
            &sea.destination_port,
            None,
        );
        let from = self.pier(&from, false, capacity, &source, Some(sea.confidence_bp));
        let to = self.pier(&to, false, capacity, &source, Some(sea.confidence_bp));
        let minutes = sea
            .duration_days
            .checked_mul(1440)
            .ok_or_else(|| invalid("invalid maritime duration"))?;
        let profile = SegmentProfile {
            travel_minutes: minutes,
            cost_units: sea.duration_days * 8,
            capacity_units: capacity,
            risk_points: 5,
        };
        if let Some(existing) = self.segments.iter_mut().find(|s| {
            s.mode == TransportMode::Shipping
                && ((s.from == from && s.to == to)
                    || (s.bidirectional && s.to == from && s.from == to))
        }) {
            // Keep pre-existing committed plan profiles and one physical capacity ledger.
            self.catalogue
                .former_profiles
                .insert(existing.id.clone(), (existing.profile, existing.prototype_only));
            existing.profile = profile;
            existing.prototype_only = false;
            self.aliases.insert(sea.corridor_id, existing.id.clone());
            let detailed = self.catalogue.evidence.get_mut(&existing.id).unwrap();
            detailed.source.push_str(" + ");
            detailed.source.push_str(&source);
            detailed.confidence_bp = origin.confidence_bp;
        } else {
            self.add(
                sea.corridor_id,
                &from,
                &to,
                TransportMode::Shipping,
                profile,
                origin,
            );
        }
        Ok(())
    }

    fn import_river(&mut self, river: River) -> io::Result<()> {
        if river.hubs.len() < 2
            || river.entity_ids.is_empty()
            || river.capacity_index == 0
            || river.seasonality_bp > 10000
            || !river
                .entity_ids
                .iter()
                .all(|u| self.catalogue.areas.contains_key(u))
        {
            return Err(invalid(format!(
                "invalid river record {}",
                river.corridor_id
            )));
        }
        let source=format!("transport_compact.json/river_rows/{} (capacity {}, seasonality {} bp; modeled duration)", river.corridor_id,river.capacity_index,river.seasonality_bp);
        let capacity = river
            .capacity_index
            .checked_mul(2)
            .ok_or_else(|| invalid("invalid river capacity"))?;
        let mut hubs = Vec::new();
        for name in &river.hubs {
            let slug = key(name);
            let explicit = self
                .river_bindings
                .remove(&(river.corridor_id.clone(), name.clone()));
            if explicit
                .as_ref()
                .is_some_and(|unit| !river.entity_ids.contains(unit))
            {
                return Err(invalid("river hub outside source roster"));
            }
            let bound = if explicit.is_some() {
                explicit
            } else if river.entity_ids.len() == 1 {
                Some(river.entity_ids[0].clone())
            } else {
                let mut candidates = river
                    .entity_ids
                    .iter()
                    .filter(|u| self.cities.contains_key(&((*u).clone(), slug.clone())));
                let first = candidates.next();
                first.filter(|_| candidates.next().is_none()).cloned()
            };
            // Some catalogue labels describe broad reaches or a frontier, rather than a port.
            if name.ends_with(" delta") || name.ends_with(" frontier") {
                let reach = format!("reach:{}:{slug}", river.corridor_id);
                self.register(&reach, NodeKind::Identity, name, bound.as_deref(), None);
                hubs.push(reach);
                continue;
            }
            let scope = bound.as_deref().unwrap_or(&river.corridor_id);
            let city = self.city(scope, bound.as_deref(), name, None);
            hubs.push(city);
        }
        for (index, pair) in hubs.windows(2).enumerate() {
            let (a, b) = (&pair[0], &pair[1]);
            let gap = if river.corridor_id == "river:congo" && river.hubs[index] == "Stanley Pool" {
                Some((NodeCoverage::Impassable, "刚果河斯坦利池至马塔迪有急流，轮船不能直通。来源：皇家中非博物馆刚果河地质资料。".to_owned()))
            } else if a.starts_with("reach:") || b.starts_with("reach:") {
                Some((
                    NodeCoverage::Unrefined,
                    format!(
                        "{} 至 {} 的资料仅给出边区或三角洲，缺少可定位的航段或换装点。",
                        river.hubs[index],
                        river.hubs[index + 1]
                    ),
                ))
            } else {
                None
            };
            if let Some((status, note)) = gap {
                for id in [a, b] {
                    self.catalogue
                        .notes
                        .entry(id.clone())
                        .or_default()
                        .push(note.clone());
                    let pier = format!(
                        "landing:{}",
                        id.strip_prefix("hub:")
                            .or_else(|| id.strip_prefix("place:"))
                            .unwrap_or(id)
                    );
                    self.catalogue
                        .notes
                        .entry(pier)
                        .or_default()
                        .push(note.clone());
                }
                self.catalogue
                    .river_gaps
                    .insert((a.min(b).clone(), a.max(b).clone()), (status, note));
                continue;
            }
            let from = self.pier(a, true, capacity, &source, None);
            let to = self.pier(b, true, capacity, &source, None);
            // For geolocated reaches, the chord is solely a lower bound on distance. No line
            // geometry is produced. Otherwise divide a modeled three-day corridor across reaches.
            let minutes = match (self.catalogue.nodes[a].point, self.catalogue.nodes[b].point) {
                (Some(p), Some(q)) => (super::map_data::distance_km(p, q) * 1.5 / 12.0 * 60.0)
                    .ceil()
                    .max(60.0) as u32,
                _ => (4320 / (river.hubs.len() - 1) as u32).max(60),
            };
            let profile = SegmentProfile {
                travel_minutes: minutes,
                cost_units: minutes.div_ceil(150) + 2,
                capacity_units: capacity,
                risk_points: 2 + river.seasonality_bp / 1000,
            };
            self.add(
                format!("{}:{index}", river.corridor_id),
                &from,
                &to,
                TransportMode::InlandWaterway,
                profile,
                evidence(NetworkLayer::River, source.clone(), None),
            );
        }
        Ok(())
    }

    fn bind_domestic(&mut self) {
        // Attach each existing domestic land component once. Its detailed roads and rails
        // keep their capacity and disruptions instead of gaining an aggregate shortcut.
        let mut neighbours: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for seg in &self.segments {
            if matches!(seg.mode, TransportMode::Rail | TransportMode::Road)
                && self.catalogue.nodes[&seg.from].unit == self.catalogue.nodes[&seg.to].unit
            {
                neighbours
                    .entry(seg.from.clone())
                    .or_default()
                    .push(seg.to.clone());
                neighbours
                    .entry(seg.to.clone())
                    .or_default()
                    .push(seg.from.clone());
            }
        }
        let capitals: BTreeSet<_> = self.catalogue.capitals.values().cloned().collect();
        let mut cities: Vec<_> = self
            .cities
            .iter()
            .map(|((unit, _), id)| (unit.clone(), id.clone()))
            .collect();
        cities.sort_by_key(|(_, id)| (!capitals.contains(id), id.clone()));
        let mut seen = BTreeSet::new();
        for (unit, id) in cities {
            if !self.catalogue.domestic.contains_key(&unit) || !seen.insert(id.clone()) {
                continue;
            }
            self.attach_domestic(&unit, &id, false);
            let mut stack = vec![id];
            while let Some(hub) = stack.pop() {
                for next in neighbours.get(&hub).into_iter().flatten() {
                    if seen.insert(next.clone()) {
                        stack.push(next.clone());
                    }
                }
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        formal_bootstrap::WorldBootstrap,
        transport::{ModeSet, RouteError, TransportRequest},
    };

    fn query(from: &str, to: &str, allowed_modes: ModeSet) -> TransportRequest {
        TransportRequest {
            from: from.into(),
            to: to.into(),
            allowed_modes,
            capacity_units: 1,
        }
    }

    #[test]
    fn source_rosters_resolve_and_named_corridors_share_one_network() {
        let world = WorldBootstrap::load().unwrap();
        let sources = world.sources();
        let mut net = super::super::map_data::load_world_network(sources, 8).unwrap();
        let opening = sources.historical_population.as_ref().unwrap();
        let bucharest_partition = if opening.version() >= 36 {
            "ro_1899_county_ilfov"
        } else {
            "ro_1899_muntenia"
        };
        let bucharest = net.capital_node("kingdom_of_romania").unwrap();
        assert_eq!(opening.unit_at(bucharest), Some(bucharest_partition));
        assert_eq!(net.population_at(bucharest), Some(bucharest_partition));
        let table: Table = serde_json::from_slice(COMPACT).unwrap();
        for unit in sources.population_units() {
            let node = net.area_node(unit).unwrap();
            assert_eq!(net.unit_at(node), Some(unit));
            assert_eq!(
                net.routing_node(&format!("market:legacy_aggregate:{unit}")),
                Some(node)
            );
        }
        for polity in sources.polities().values() {
            assert!(net.node(&polity.runtime_id()).is_some());
        }
        for id in sources.places().keys() {
            assert!(net.node(id).is_some());
        }
        let domestic: Vec<DomesticStatistics> =
            records(table.domestic_field_order, table.domestic_rows).unwrap();
        let maritime: Vec<Maritime> =
            records(table.maritime_field_order, table.maritime_rows).unwrap();
        let river: Vec<River> = records(table.river_field_order, table.river_rows).unwrap();
        assert_eq!((domestic.len(), maritime.len(), river.len()), (50, 30, 13));
        for row in domestic {
            assert_eq!(
                net.domestic_statistics(&row.entity_id).unwrap().waterway_km,
                row.waterway_km
            );
        }
        for row in maritime {
            assert_eq!(
                net.segment(&row.corridor_id).unwrap().mode,
                TransportMode::Shipping
            );
            assert_eq!(
                net.segment(&row.corridor_id)
                    .unwrap()
                    .profile
                    .travel_minutes,
                row.duration_days * 1440
            );
        }
        for row in river {
            assert!(net
                .segments()
                .any(|s| s.mode == TransportMode::InlandWaterway
                    && s.id.starts_with(&format!("{}:", row.corridor_id))));
        }
        assert_eq!(net.segment("sea:002").unwrap().id, "shipping_atlantic");
        assert_eq!(net.segment("sea:006").unwrap().id, "shipping_mediterranean");
        net.set_availability("sea:002", false, 0).unwrap();
        assert!(!net.availability("shipping_atlantic").unwrap().open);
        let closed_revision = net.availability_revision();
        net.set_availability("shipping_atlantic", false, 0).unwrap();
        assert_eq!(net.availability_revision(), closed_revision);
    }

    #[test]
    fn released_map_identities_and_operating_coverage() {
        let world = WorldBootstrap::load().unwrap();
        let sources = world.sources();
        let mut net = super::super::map_data::load_world_network(sources, 0).unwrap();
        fn counts<'a>(net: &TransportNetwork, ids: impl Iterator<Item = &'a str>) -> [usize; 4] {
            let mut result = [0; 4];
            for id in ids {
                assert!(net.node(id).is_some(), "{id}");
                result[match net.coverage(id) {
                    NodeCoverage::Connected => 0,
                    NodeCoverage::Unrefined => 1,
                    NodeCoverage::Unknown => 2,
                    NodeCoverage::Impassable => 3,
                }] += 1;
            }
            result
        }
        let groups = [
            (MapIdentityKind::Place, 175),
            (MapIdentityKind::Reference, 6),
            (MapIdentityKind::Polity, 148),
            (MapIdentityKind::DisplayPolity, 15),
        ];
        for (kind, total) in groups {
            let c = counts(
                &net,
                net.map_identities()
                    .filter(|(_, m)| m.kind == kind)
                    .map(|(id, _)| id),
            );
            assert_eq!(c.iter().sum::<usize>(), total);
            println!("map {kind:?} {total}: connected/unrefined/unknown/impassable {c:?}");
        }
        for (id, meta) in net.map_identities() {
            assert!(meta.from_date < meta.to_date_exclusive);
            if matches!(
                meta.kind,
                MapIdentityKind::Reference | MapIdentityKind::DisplayPolity
            ) {
                assert_eq!(net.unit_at(id), None, "{id}");
                assert!(net.notes_at(id).next().is_some(), "{id}");
            }
        }
        let c = counts(&net, sources.population_units());
        let markets: Vec<_> = sources
            .population_units()
            .map(|u| format!("market:legacy_aggregate:{u}"))
            .collect();
        assert_eq!(counts(&net, markets.iter().map(String::as_str)), c);
        assert_eq!(c.iter().sum::<usize>(), 50);
        let opening = sources.historical_population.as_ref().unwrap();
        let leaf_counts = counts(&net, opening.partition_identities().map(|(id, _, _)| id));
        let root_counts = counts(&net, opening.standalone_ids());
        assert_eq!(leaf_counts.iter().sum::<usize>(), opening.partition_identities().count());
        let attached = opening.residence_places().count();
        for (place, leaf) in opening.residence_places() {
            assert_eq!(net.population_at(place), Some(leaf));
        }
        for (id, parent, _) in opening.partition_identities() {
            assert_eq!(net.population_node(id), Some(id));
            assert_eq!(net.population_parent(id), Some(parent));
            assert_eq!(net.population_at(id), Some(id));
            assert_eq!(net.unit_at(id), net.area_node(parent).map(|_| parent));
        }
        for root in opening.standalone_ids() {
            assert_eq!(net.population_parent(root), Some(root));
            assert_eq!(net.unit_at(root), None);
            assert!(net.area_node(root).is_none());
        }
        println!("population partitions {leaf_counts:?}; standalone {root_counts:?}; explicit places {attached}");
        let seine = "administrative_region:france_seine";
        let paris = "administrative_region:france_arrondissement_751";
        assert_eq!(net.population_at("place:paris"), Some(paris));
        assert_eq!(net.population_at(seine), Some(seine));
        let dest = "us_state_new_york";
        let to = net.routing_node(dest).unwrap().to_owned();
        let physical = net.route(&query("place:paris", &to, ModeSet::ALL)).unwrap();
        assert_eq!(
            net.route(&query(seine, dest, ModeSet::ALL)).unwrap(),
            physical
        );
        assert_eq!(net.route(&query(paris, dest, ModeSet::ALL)).unwrap(), physical);
        assert!(net
            .segments()
            .all(|s| !net.catalogue.population_nodes.contains(&s.from)
                && !net.catalogue.population_nodes.contains(&s.to)));
        assert_eq!(net.coverage("ch_canton_zh"), NodeCoverage::Unrefined);
        for (root, leaf) in [
            ("mexican_republic", "mx_distrito_federal"),
            ("brazil_1900", "br_federal_district_1900"),
            ("dominion_of_canada", "ca_ontario"),
            ("sweden_norway_union", "ft_sweden"),
            ("swiss_confederation", "ch_canton_be"),
            ("cshapes_gw_590", "mu_district_port_louis"),
        ] {
            let actual = net.capital_node(root).unwrap();
            assert_eq!(opening.unit_at(actual), Some(leaf), "{root}/{actual}");
            assert_eq!(net.population_at(actual), Some(leaf));
        }
        for (id, leaf) in [
            ("water:mexican_republic:veracruz", "mx_veracruz"),
            ("place:st_louis", "us_state_missouri"),
            ("landing:united_states_1900:st_louis", "us_state_missouri"),
        ] {
            assert_eq!(opening.unit_at(id), Some(leaf), "{id}");
        }
        assert_eq!(net.population_at("place:port_new_york"), Some(dest));
        let formal: Vec<_> = sources
            .polities()
            .values()
            .map(|p| p.runtime_id())
            .collect();
        let p = counts(&net, formal.iter().map(String::as_str));
        let src_places = counts(&net, sources.places().keys().map(String::as_str));
        for (political, unit) in sources.polity_population_bindings() {
            assert_eq!(
                net.unit_at(&format!("state:{political}")),
                Some(unit.as_str())
            );
        }
        println!("areas/markets {c:?}; formal polities {p:?} ({} bound); core places {src_places:?}; total nodes {} segments {}",
            sources.polity_population_bindings().len(),net.nodes().count(),net.segments().count());
        let river = ModeSet::only(TransportMode::InlandWaterway);
        let congo = query(
            "hub:congo_free_state:stanley_pool",
            "hub:congo_free_state:matadi",
            river,
        );
        assert!(matches!(
            net.route(&congo),
            Err(RouteError::RiverGap(NodeCoverage::Impassable, _))
        ));
        assert!(net.notes_at(&congo.to).any(|s| s.contains("急流")));
        let mekong = query(
            "hub:kingdom_of_siam:ayutthaya",
            "reach:river:chao_phraya_mekong:mekong_frontier",
            river,
        );
        assert!(matches!(
            net.route(&mekong),
            Err(RouteError::RiverGap(NodeCoverage::Unrefined, _))
        ));
        assert!(net.notes_at(&mekong.to).any(|s| s.contains("换装")));
        assert_eq!(
            net.coverage("map_reference:barbizon"),
            NodeCoverage::Unknown
        );
        assert_eq!(net.coverage("place:shanghai"), NodeCoverage::Connected);
        assert_eq!(net.unit_at("place:shanghai"), Some("qing_empire"));
        assert!(net
            .route(&query(
                "place:shanghai",
                "area:empire_of_japan",
                ModeSet::ALL
            ))
            .is_ok());
        let access = "access:congo_free_state:hub:congo_free_state:stanley_pool";
        net.set_availability(access, false, 0).unwrap();
        assert_eq!(net.coverage(&congo.from), NodeCoverage::Impassable);
    }

    #[test]
    fn national_estimates_are_divided_between_gateways_and_existing_bookings_keep_their_slot() {
        use super::super::operations::Operations;
        let world = WorldBootstrap::load().unwrap();
        let mut net = super::super::map_data::load_world_network(world.sources(), 0).unwrap();
        let areas = &net.catalogue.areas;
        for (unit, area) in areas {
            let stats = &net.catalogue.domestic[unit];
            let mut access = Vec::new();
            let mut port = Vec::new();
            for s in net.segments() {
                if s.mode == TransportMode::Domestic && s.from == *area { access.push(s.profile.capacity_units); }
                if s.mode == TransportMode::PortTransfer && (s.to.starts_with("water:") || s.prototype_only)
                    && net.unit_at(&s.from) == Some(unit.as_str()) { port.push(s.profile.capacity_units); }
            }
            let land = match stats.network_class.as_str() {
                "continental_dense" => 120, "national_dense" => 90, "developing_trunk" => 60, _ => 24,
            };
            for (shares, total) in [(access, (land + stats.port_capacity_index)/2), (port, stats.port_capacity_index)] {
                if shares.is_empty() { continue; }
                assert_eq!(shares.iter().sum::<u32>(), total, "{unit}");
                assert!(shares.iter().max().unwrap() - shares.iter().min().unwrap() <= 1);
            }
        }
        let japan = "empire_of_japan";
        let area = net.area_node(japan).unwrap().to_owned();
        let city = net.routing_node("place:yokohama").unwrap().to_owned();
        let mut old = net.route(&query(&area, &city, ModeSet::only(TransportMode::Domestic))).unwrap();
        let leg = &mut old.legs[0];
        let segment = leg.segment_id.clone();
        let current = leg.profile.capacity_units;
        let old_cap = net.catalogue.former_profiles[&segment].0.capacity_units;
        assert!(current < old_cap);
        leg.profile.capacity_units = old_cap;
        old.capacity_units = Some(old_cap);
        let ends = old.travel_minutes as i64;
        let saved = serde_json::json!({
            "next_id":2,"closed":[],"restrictions":{(segment.clone()):{"open":true,"capacity_units":old_cap}},
            "reservations":{"1":{"freight":true,"leg":0,"status":"Moving","stop_at_next":false,
                "plan":{"route":old,"load":old_cap,"departure":0,"windows":[{"starts":0,"ends":ends}]}}}
        });
        let mut ops = Operations::restore(world.sources(), 1, serde_json::from_value(saved).unwrap()).unwrap();
        assert_eq!(ops.plan(1).unwrap().load_units(), old_cap);
        assert_eq!(ops.network().availability(&segment).unwrap().capacity_units, current);
        let next = ops.quote(&area, &city, ModeSet::only(TransportMode::Domestic), 1, 1).unwrap();
        assert_eq!(next.first_departure_minute(), ends);
        ops.advance(ends);
        assert_eq!(ops.completed(1), Some(city.as_str()));
    }

    #[test]
    fn legacy_sea_passage_keeps_its_committed_window_on_the_same_physical_lane() {
        use crate::transport::operations::Operations;
        use serde_json::json;
        let world = WorldBootstrap::load().unwrap();
        let mut prototype =
            super::super::map_data::load_prototype_map_network(world.sources(), 0).unwrap();
        let old = prototype
            .route(&query(
                "place:port_le_havre",
                "place:port_new_york",
                ModeSet::only(TransportMode::Shipping),
            ))
            .unwrap();
        let ends = old.travel_minutes as i64;
        let saved = json!({
            "next_id":2,"closed":[],"restrictions":{"shipping_atlantic":{"open":true,"capacity_units":280}},
            "reservations":{"1":{"freight":false,"leg":0,"status":"Moving","stop_at_next":false,
                "plan":{"route":old,"load":1,"departure":0,"windows":[{"starts":0,"ends":ends}]}}}
        });
        let mut ops =
            Operations::restore(world.sources(), 1, serde_json::from_value(saved).unwrap())
                .unwrap();
        let old_plan = ops.plan(1).unwrap();
        assert_eq!(old_plan.arrival_minute(), ends);
        assert!(old_plan.route().legs[0].prototype_only);
        let fresh = ops
            .quote(
                "place:port_le_havre",
                "place:port_new_york",
                ModeSet::only(TransportMode::Shipping),
                1,
                1,
            )
            .unwrap();
        assert_eq!(fresh.route().travel_minutes, 8 * 1440);
        assert_eq!(fresh.route().legs[0].segment_id, "shipping_atlantic");
        assert!(!fresh.route().legs[0].prototype_only);
    }

    #[test]
    fn continental_trips_use_dated_access_transfers_and_water_bottlenecks() {
        let world = WorldBootstrap::load().unwrap();
        let mut net = super::super::map_data::load_world_network(world.sources(), 0).unwrap();
        let describe = |net: &TransportNetwork, route: &crate::transport::Route| {
            let main: Vec<_> = route
                .legs
                .iter()
                .filter(|leg| {
                    matches!(
                        leg.mode,
                        TransportMode::Shipping | TransportMode::InlandWaterway
                    ) || net.unit_at(&leg.from) != net.unit_at(&leg.to)
                })
                .map(|leg| {
                    format!(
                        "{}({}→{})",
                        leg.segment_id,
                        net.node_label(&leg.from).unwrap_or(&leg.from),
                        net.node_label(&leg.to).unwrap_or(&leg.to)
                    )
                })
                .collect();
            println!(
                "{} -> {} | {} | transfers {} capacity {} minutes {} cost {}",
                route.from,
                route.to,
                main.join(", "),
                route
                    .legs
                    .iter()
                    .filter(|l| l.mode == TransportMode::PortTransfer)
                    .count(),
                route.capacity_units.unwrap(),
                route.travel_minutes,
                route.cost_units
            );
        };
        for mode in [
            TransportMode::Road,
            TransportMode::Rail,
            TransportMode::Shipping,
            TransportMode::InlandWaterway,
            TransportMode::Domestic,
            TransportMode::PortTransfer,
        ] {
            println!(
                "{mode:?}: {}",
                net.segments().filter(|s| s.mode == mode).count()
            );
        }
        for status in [NodeCoverage::Impassable, NodeCoverage::Unrefined] {
            println!(
                "river gaps {status:?}: {}",
                net.catalogue
                    .river_gaps
                    .values()
                    .filter(|(s, _)| *s == status)
                    .count()
            );
        }
        for (from, to) in [
            ("place:new_york", "place:le_havre"),
            ("area:australia_colonies_1900", "area:united_states_1900"),
            ("area:empire_of_japan", "area:qing_empire"),
            ("area:khedivate_of_egypt", "area:cshapes_gw_750"),
            ("area:chile_1900", "area:mexican_republic"),
        ] {
            let route = net.route(&query(from, to, ModeSet::ALL)).unwrap();
            describe(&net, &route);
            assert!(route
                .legs
                .iter()
                .any(|leg| leg.mode == TransportMode::Shipping));
            assert!(route
                .legs
                .iter()
                .any(|leg| leg.mode == TransportMode::PortTransfer));
            assert!(route
                .legs
                .iter()
                .all(|leg| net.evidence(&leg.segment_id).unwrap().applies_on(BASELINE)));
        }
        let river = ModeSet::only(TransportMode::InlandWaterway);
        for (first, last) in [
            ("river:yangtze:0", "river:yangtze:2"),
            ("river:ganges_brahmaputra:0", "river:ganges_brahmaputra:1"),
            ("river:nile:0", "river:nile:0"),
        ] {
            let req = query(
                &net.segment(first).unwrap().from,
                &net.segment(last).unwrap().to,
                river,
            );
            let route = net.route(&req).unwrap();
            assert!(route
                .legs
                .iter()
                .all(|l| l.mode == TransportMode::InlandWaterway));
            describe(&net, &route);
        }
        let land = ModeSet::only(TransportMode::Domestic).with(TransportMode::Rail);
        let italy = query("area:swiss_confederation", "area:kingdom_of_italy", land);
        let crossing = "rail:chiasso_como_san_giovanni";
        let trip = net.route(&italy).unwrap();
        describe(&net, &trip);
        assert_eq!(trip.legs.len(), 3);
        assert_eq!(trip.legs[1].segment_id, crossing);
        assert!(!net.evidence(crossing).unwrap().applies_on("1876-09-27"));
        assert!(net.evidence(crossing).unwrap().applies_on("1876-09-28"));
        net.set_availability(crossing, false, 0).unwrap();
        assert_eq!(net.route(&italy), Err(RouteError::Disrupted));
        let amazon = query(
            "landing:peru_1900:iquitos",
            "landing:brazil_1900:belem",
            river,
        );
        let route = net.route(&amazon).unwrap();
        describe(&net, &route);
        assert_eq!(
            route
                .legs
                .iter()
                .map(|l| l.segment_id.as_str())
                .collect::<Vec<_>>(),
            ["river:amazon:0", "river:amazon:1"]
        );
        assert_eq!(net.unit_at(&route.legs[0].to), Some("brazil_1900"));
        net.set_availability("river:amazon:0", false, 0).unwrap();
        assert_eq!(
            net.coverage("landing:peru_1900:iquitos"),
            NodeCoverage::Connected
        ); // transfer still open
        assert_eq!(net.route(&amazon), Err(RouteError::Disrupted));
        assert!(net.segment("river:congo:0").is_none());
        assert!(net.segment("river:chao_phraya_mekong:1").is_none());
        assert_eq!(net.coverage("place:paris_basin"), NodeCoverage::Unrefined);
        assert_eq!(net.coverage("unregistered"), NodeCoverage::Unknown);
        let unknown = query("place:paris_basin", "place:paris", ModeSet::ALL);
        assert!(matches!(
            net.route(&unknown),
            Err(RouteError::UnrefinedEndpoint(_))
        ));
        assert_eq!(net.unit_at("hub:external:djibouti"), None);
        assert_eq!(
            net.domestic_statistics("ethiopian_empire")
                .unwrap()
                .rail_route_km,
            0
        );
        assert!(net
            .segments()
            .all(|s| !(s.id.starts_with("access:") && s.mode == TransportMode::Rail)));
    }
}
