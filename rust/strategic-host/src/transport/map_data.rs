//! Opt-in adapter for the prototype map catalogue already loaded by the formal host.

use super::{
    NodeKind, SegmentProfile, TransportMode, TransportNetwork, TransportNode, TransportSegment,
};
use crate::formal_bootstrap::{RouteMode, WorldSources};
use serde::Deserialize;
use std::{collections::BTreeMap, io};

const CITIES: &[u8] = include_bytes!("../../../../data/world_map/cities.json");
const PORTS: &[u8] = include_bytes!("../../../../data/world_map/ports.json");
const ROAD: &[u8] = include_bytes!("../../../../data/world_map/road_segments.json");
const RAIL: &[u8] = include_bytes!("../../../../data/world_map/rail_segments.json");
const SHIPPING: &[u8] = include_bytes!("../../../../data/world_map/shipping_routes.json");

#[derive(Deserialize)]
struct Source {
    schema_version: u32,
    prototype_only: bool,
}

impl Source {
    fn require_prototype(&self, version: u32, file: &str) -> io::Result<()> {
        if self.schema_version != version || !self.prototype_only {
            return Err(invalid(format!("unexpected prototype source: {file}")));
        }
        Ok(())
    }
}

#[derive(Deserialize)]
struct CityCatalogue {
    #[serde(flatten)]
    source: Source,
    cities: Vec<City>,
}

#[derive(Deserialize)]
struct City {
    id: String,
}

#[derive(Deserialize)]
struct PortCatalogue {
    #[serde(flatten)]
    source: Source,
    ports: Vec<Port>,
}

#[derive(Deserialize)]
struct Port {
    id: String,
    city_id: String,
}

#[derive(Deserialize)]
struct ShippingCatalogue {
    #[serde(flatten)]
    source: Source,
    routes: Vec<ShippingGeometry>,
}

#[derive(Deserialize)]
struct ShippingGeometry {
    id: String,
    waypoints_lon_lat: Vec<[f64; 2]>,
}

/// Prototype port links and shipping display geometry. IDs use the formal place namespace.
pub struct PrototypeGeometry {
    pub port_connections: Vec<(String, String)>,
    pub shipping_waypoints: BTreeMap<String, Vec<[f64; 2]>>,
}

pub fn load_prototype_geometry() -> io::Result<PrototypeGeometry> {
    let ports: PortCatalogue = serde_json::from_slice(PORTS)?;
    ports.source.require_prototype(2, "ports.json")?;
    let shipping: ShippingCatalogue = serde_json::from_slice(SHIPPING)?;
    shipping
        .source
        .require_prototype(2, "shipping_routes.json")?;
    let mut shipping_waypoints = BTreeMap::new();
    for route in shipping.routes {
        if route.waypoints_lon_lat.len() < 2
            || !route.waypoints_lon_lat.iter().copied().all(valid_point)
            || shipping_waypoints
                .insert(route.id.clone(), route.waypoints_lon_lat)
                .is_some()
        {
            return Err(invalid(format!("invalid shipping geometry: {}", route.id)));
        }
    }
    Ok(PrototypeGeometry {
        port_connections: ports
            .ports
            .into_iter()
            .map(|port| {
                (
                    format!("place:{}", port.id),
                    format!("place:{}", port.city_id),
                )
            })
            .collect(),
        shipping_waypoints,
    })
}

/// Builds a routing index over formal `place:*` and map route IDs. Each leg is
/// marked prototype-only. Operating values are explicit development assumptions.
pub fn load_prototype_map_network(
    sources: &WorldSources,
    cache_limit: usize,
) -> io::Result<TransportNetwork> {
    let (nodes, segments) = detailed_map(sources)?;
    TransportNetwork::new(nodes, segments, cache_limit).map_err(invalid)
}

pub fn load_world_network(sources: &WorldSources, cache_limit: usize) -> io::Result<TransportNetwork> {
    let (nodes, segments) = detailed_map(sources)?;
    super::historical::load(sources, nodes, segments, cache_limit)
}

fn detailed_map(sources: &WorldSources) -> io::Result<(Vec<TransportNode>, Vec<TransportSegment>)> {
    let cities: CityCatalogue = serde_json::from_slice(CITIES)?;
    let geometry = load_prototype_geometry()?;
    cities.source.require_prototype(3, "cities.json")?;
    serde_json::from_slice::<Source>(ROAD)?.require_prototype(2, "road_segments.json")?;
    serde_json::from_slice::<Source>(RAIL)?.require_prototype(2, "rail_segments.json")?;

    let mut nodes = Vec::with_capacity(cities.cities.len() + geometry.port_connections.len());
    let mut segments = Vec::with_capacity(sources.routes().len() + geometry.port_connections.len());
    for city in cities.cities {
        let id = format!("place:{}", city.id);
        require_point(sources, &id)?;
        nodes.push(TransportNode {
            id,
            kind: NodeKind::City,
        });
    }
    for (id, city) in geometry.port_connections {
        let distance = distance_km(require_point(sources, &city)?, require_point(sources, &id)?);
        segments.push(TransportSegment {
            id: format!("transfer:{}", id.trim_start_matches("place:")),
            from: city,
            to: id.clone(),
            mode: TransportMode::PortTransfer,
            bidirectional: true,
            profile: prototype_profile(TransportMode::PortTransfer, distance),
            prototype_only: true,
        });
        nodes.push(TransportNode {
            id,
            kind: NodeKind::Port,
        });
    }
    for route in sources.routes().values() {
        let from = require_point(sources, &route.from_place_id)?;
        let to = require_point(sources, &route.to_place_id)?;
        let (mode, distance) = match route.mode {
            RouteMode::Road => (TransportMode::Road, distance_km(from, to)),
            RouteMode::Rail => (TransportMode::Rail, distance_km(from, to)),
            RouteMode::Shipping => {
                let points = geometry
                    .shipping_waypoints
                    .get(&route.id)
                    .map(Vec::as_slice)
                    .ok_or_else(|| invalid(format!("invalid shipping geometry: {}", route.id)))?;
                let distance = distance_km(from, points[0])
                    + distance_km(points[points.len() - 1], to)
                    + points
                        .windows(2)
                        .map(|pair| distance_km(pair[0], pair[1]))
                        .sum::<f64>();
                (TransportMode::Shipping, distance)
            }
        };
        segments.push(TransportSegment {
            id: route.id.clone(),
            from: route.from_place_id.clone(),
            to: route.to_place_id.clone(),
            mode,
            bidirectional: true,
            profile: prototype_profile(mode, distance),
            prototype_only: true,
        });
    }
    Ok((nodes, segments))
}

fn require_point(sources: &WorldSources, id: &str) -> io::Result<[f64; 2]> {
    sources
        .places()
        .get(id)
        .and_then(|place| place.lon_lat)
        .filter(|&point| valid_point(point))
        .ok_or_else(|| invalid(format!("missing transport coordinates: {id}")))
}

fn valid_point([lon, lat]: [f64; 2]) -> bool {
    (-180.0..=180.0).contains(&lon) && (-90.0..=90.0).contains(&lat)
}

pub(super) fn distance_km([lon_a, lat_a]: [f64; 2], [lon_b, lat_b]: [f64; 2]) -> f64 {
    let half_latitude = (lat_b - lat_a).to_radians() * 0.5;
    let half_longitude = (lon_b - lon_a).to_radians() * 0.5;
    let haversine = half_latitude.sin().powi(2)
        + lat_a.to_radians().cos() * lat_b.to_radians().cos() * half_longitude.sin().powi(2);
    12_742.0 * haversine.clamp(0.0, 1.0).sqrt().asin()
}

struct Assumptions {
    speed_km_per_hour: f64,
    handling_minutes: u32,
    base_cost_units: u32,
    cost_units_per_km: f64,
    capacity_units: u32,
    risk_points: u32,
}

fn prototype_profile(mode: TransportMode, distance_km: f64) -> SegmentProfile {
    // Scenario values only. Cost is per leg in abstract units. Capacity is a shared
    // load allowance, and risk points are additive rather than probabilities.
    let assumptions = match mode {
        TransportMode::Road => Assumptions {
            speed_km_per_hour: 8.0,
            handling_minutes: 0,
            base_cost_units: 1,
            cost_units_per_km: 0.6,
            capacity_units: 16,
            risk_points: 3,
        },
        TransportMode::Rail => Assumptions {
            speed_km_per_hour: 40.0,
            handling_minutes: 0,
            base_cost_units: 2,
            cost_units_per_km: 0.4,
            capacity_units: 120,
            risk_points: 2,
        },
        TransportMode::Shipping => Assumptions {
            speed_km_per_hour: 20.0,
            handling_minutes: 0,
            base_cost_units: 3,
            cost_units_per_km: 0.2,
            capacity_units: 300,
            risk_points: 5,
        },
        TransportMode::Domestic | TransportMode::InlandWaterway => unreachable!("aggregate profiles come from the historical catalogue"),
        TransportMode::PortTransfer => Assumptions {
            speed_km_per_hour: 6.0,
            handling_minutes: 45,
            base_cost_units: 4,
            cost_units_per_km: 0.3,
            capacity_units: 80,
            risk_points: 1,
        },
    };
    SegmentProfile {
        travel_minutes: (distance_km * 60.0 / assumptions.speed_km_per_hour)
            .ceil()
            .max(1.0) as u32
            + assumptions.handling_minutes,
        cost_units: assumptions.base_cost_units
            + (distance_km * assumptions.cost_units_per_km).ceil() as u32,
        capacity_units: assumptions.capacity_units,
        risk_points: assumptions.risk_points,
    }
}

fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        formal_bootstrap::WorldBootstrap,
        formal_clock::GameClock,
        transport::{ModeSet, Route, RouteError, TransportRequest},
    };

    fn network() -> TransportNetwork {
        let world = WorldBootstrap::load().unwrap();
        load_prototype_map_network(world.sources(), 8).unwrap()
    }

    fn request(from: &str, to: &str, allowed_modes: ModeSet) -> TransportRequest {
        TransportRequest {
            from: format!("place:{from}"),
            to: format!("place:{to}"),
            allowed_modes,
            capacity_units: 1,
        }
    }

    fn ids(route: &Route) -> Vec<&str> {
        route
            .legs
            .iter()
            .map(|leg| leg.segment_id.as_str())
            .collect()
    }

    #[test]
    fn paris_rail_uses_existing_rouen_connections_and_formal_clock() {
        let mut network = network();
        let rail = ModeSet::only(TransportMode::Rail);
        let to_rouen = network.route(&request("paris", "rouen", rail)).unwrap();
        let to_havre = network.route(&request("paris", "le_havre", rail)).unwrap();
        assert_eq!(ids(&to_rouen), ["rail_paris_rouen"]);
        assert_eq!(ids(&to_havre), ["rail_paris_rouen", "rail_rouen_le_havre"]);
        assert_eq!(to_havre.legs[1].from, "place:rouen");
        assert!(to_havre.legs.iter().all(|leg| leg.prototype_only));
        assert_eq!(to_havre.capacity_units, Some(120));
        assert_eq!(to_havre.risk_points, 4);
        let mut clock = GameClock::default();
        clock.advance_minutes(23 * 60).unwrap();
        let arrival = to_havre.arrival_clock(clock).unwrap();
        assert_eq!(arrival.current_day(), 1);
        assert_eq!(
            arrival.snapshot().total_minutes,
            23 * 60 + to_havre.travel_minutes as i64
        );
    }

    #[test]
    fn disrupted_rail_uses_the_existing_road_and_reports_gaps() {
        let mut network = network();
        let request_to_rouen = request("paris", "rouen", ModeSet::ALL);
        let rail = network.route(&request_to_rouen).unwrap();
        network
            .set_availability("rail_paris_rouen", false, 0)
            .unwrap();
        let road = network.route(&request_to_rouen).unwrap();
        assert_eq!(ids(&road), ["road_rouen_paris"]);
        assert!(road.travel_minutes > rail.travel_minutes);
        assert!(road.cost_units > rail.cost_units);
        assert_eq!(road.capacity_units, Some(16));
        assert_eq!(road.risk_points, 3);

        let rail = ModeSet::only(TransportMode::Rail);
        assert_eq!(
            network.route(&request("paris", "rouen", rail)),
            Err(RouteError::Disrupted)
        );
        assert_eq!(
            network.route(&request(
                "paris",
                "le_havre",
                ModeSet::only(TransportMode::Road)
            )),
            Err(RouteError::Unreachable)
        );
    }

    #[test]
    fn city_to_city_shipping_requires_both_port_transfers() {
        let mut network = network();
        let full = request("paris", "london", ModeSet::ALL);
        let route = network.route(&full).unwrap();
        assert_eq!(
            ids(&route),
            [
                "rail_paris_rouen",
                "rail_rouen_le_havre",
                "transfer:port_le_havre",
                "shipping_channel",
                "transfer:port_london"
            ]
        );
        assert_eq!(route.legs[2].mode, TransportMode::PortTransfer);
        assert_eq!(route.legs[2].to, "place:port_le_havre");
        assert_eq!(route.legs[3].mode, TransportMode::Shipping);
        assert_eq!(route.legs[3].profile.capacity_units, 300);
        assert!(route.legs[2].profile.travel_minutes > 45);
        assert!(route.legs[2].profile.cost_units > 0);
        assert_eq!(route.capacity_units, Some(80));
        let mut too_large = full.clone();
        too_large.capacity_units = 81;
        assert_eq!(
            network.route(&too_large),
            Err(RouteError::InsufficientCapacity { required_units: 81 })
        );

        let no_transfer = ModeSet::only(TransportMode::Rail).with(TransportMode::Shipping);
        assert_eq!(
            network.route(&request("paris", "london", no_transfer)),
            Err(RouteError::Unreachable)
        );
        network
            .set_availability("transfer:port_london", false, 0)
            .unwrap();
        assert_eq!(network.route(&full), Err(RouteError::Disrupted));
    }
}
