//! On-demand transport queries. The caller owns the source IDs and supplies segment profiles.
use crate::formal_clock::GameClock;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::io;

pub mod map_data;
pub mod models;
mod routing;
#[cfg(test)]
mod tests;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NodeKind {
    City,
    Port,
    Junction,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransportNode {
    pub id: String,
    pub kind: NodeKind,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum TransportMode {
    Road,
    Rail,
    Shipping,
    PortTransfer,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ModeSet(u8);

impl ModeSet {
    pub const ALL: Self = Self::only(TransportMode::Road)
        .with(TransportMode::Rail)
        .with(TransportMode::Shipping)
        .with(TransportMode::PortTransfer);

    pub const fn only(mode: TransportMode) -> Self {
        Self(1 << mode as u8)
    }

    pub const fn with(self, mode: TransportMode) -> Self {
        Self(self.0 | Self::only(mode).0)
    }

    pub const fn contains(self, mode: TransportMode) -> bool {
        self.0 & Self::only(mode).0 != 0
    }
}

/// Minutes and cost per traversal, shared carrying capacity, and additive risk points.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SegmentProfile {
    pub travel_minutes: u32,
    pub cost_units: u32,
    pub capacity_units: u32,
    pub risk_points: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransportSegment {
    pub id: String,
    pub from: String,
    pub to: String,
    pub mode: TransportMode,
    pub bidirectional: bool,
    pub profile: SegmentProfile,
    pub prototype_only: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransportRequest {
    pub from: String,
    pub to: String,
    pub allowed_modes: ModeSet,
    /// Passenger and freight callers express their load in the same capacity units.
    pub capacity_units: u32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RouteLeg {
    pub segment_id: String,
    pub from: String,
    pub to: String,
    pub mode: TransportMode,
    /// The capacity in a returned profile is the availability at query time.
    pub profile: SegmentProfile,
    pub prototype_only: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Route {
    pub from: String,
    pub to: String,
    pub legs: Vec<RouteLeg>,
    pub travel_minutes: u64,
    pub cost_units: u64,
    /// The minimum available capacity across the legs. A zero-leg trip has no bottleneck.
    pub capacity_units: Option<u32>,
    pub risk_points: u64,
}

impl Route {
    pub fn arrival_clock(&self, mut start: GameClock) -> io::Result<GameClock> {
        let minutes = i64::try_from(self.travel_minutes).map_err(|_| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "transport duration exceeds clock range",
            )
        })?;
        start.advance_minutes(minutes)?;
        Ok(start)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RouteError {
    UnknownEndpoint(String),
    InvalidDemand,
    /// No directed path exists using the requested modes.
    Unreachable,
    /// Every such path crosses a closed segment.
    Disrupted,
    /// An open path exists, but each open path has a bottleneck below the demand.
    InsufficientCapacity {
        required_units: u32,
    },
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SegmentAvailability {
    pub open: bool,
    pub capacity_units: u32,
}

impl SegmentAvailability {
    fn supports(self, demand: u32) -> bool {
        self.open && self.capacity_units >= demand
    }
}

#[derive(Clone, Copy)]
struct Arc {
    segment: usize,
    to: usize,
}

pub struct TransportNetwork {
    nodes: Vec<TransportNode>,
    node_ids: HashMap<String, usize>,
    segments: Vec<TransportSegment>,
    segment_ids: HashMap<String, usize>,
    outgoing: Vec<Vec<Arc>>,
    availability: Vec<SegmentAvailability>,
    cache: VecDeque<routing::CacheEntry>,
    cache_limit: usize,
}

impl TransportNetwork {
    /// Builds a fixed topology. Input order cannot change route tie-breaking.
    pub fn new(
        mut nodes: Vec<TransportNode>,
        mut segments: Vec<TransportSegment>,
        cache_limit: usize,
    ) -> Result<Self, String> {
        nodes.sort_unstable_by(|a, b| a.id.cmp(&b.id));
        segments.sort_unstable_by(|a, b| a.id.cmp(&b.id));
        let mut node_ids = HashMap::new();
        for (index, node) in nodes.iter().enumerate() {
            if node.id.is_empty() || node_ids.insert(node.id.clone(), index).is_some() {
                return Err(format!(
                    "empty or duplicate transport node ID {:?}",
                    node.id
                ));
            }
        }
        let mut segment_ids = HashMap::new();
        let mut outgoing = vec![Vec::new(); nodes.len()];
        let mut junction_modes = vec![None; nodes.len()];
        let mut availability = Vec::with_capacity(segments.len());
        for (index, segment) in segments.iter().enumerate() {
            if segment.id.is_empty() || segment_ids.insert(segment.id.clone(), index).is_some() {
                return Err(format!(
                    "empty or duplicate transport segment ID {:?}",
                    segment.id
                ));
            }
            let endpoint = |id: &str| {
                node_ids
                    .get(id)
                    .copied()
                    .ok_or_else(|| format!("unknown endpoint {id} on {}", segment.id))
            };
            let from = endpoint(&segment.from)?;
            let to = endpoint(&segment.to)?;
            if from == to {
                return Err(format!(
                    "transport segment {} has identical endpoints",
                    segment.id
                ));
            }
            let kinds = (nodes[from].kind, nodes[to].kind);
            let valid = match segment.mode {
                TransportMode::PortTransfer => matches!(
                    kinds,
                    (NodeKind::City, NodeKind::Port) | (NodeKind::Port, NodeKind::City)
                ),
                TransportMode::Shipping => kinds.0 != NodeKind::City && kinds.1 != NodeKind::City,
                TransportMode::Road | TransportMode::Rail => {
                    kinds.0 != NodeKind::Port && kinds.1 != NodeKind::Port
                }
            };
            if !valid {
                return Err(format!(
                    "invalid {:?} endpoints on {}",
                    segment.mode, segment.id
                ));
            }
            for node in [from, to] {
                if nodes[node].kind == NodeKind::Junction {
                    let mode = junction_modes[node].get_or_insert(segment.mode);
                    if *mode != segment.mode {
                        return Err(format!(
                            "implicit mode change at junction {}",
                            nodes[node].id
                        ));
                    }
                }
            }
            outgoing[from].push(Arc { segment: index, to });
            if segment.bidirectional {
                outgoing[to].push(Arc {
                    segment: index,
                    to: from,
                });
            }
            availability.push(SegmentAvailability {
                open: true,
                capacity_units: segment.profile.capacity_units,
            });
        }
        Ok(Self {
            nodes,
            node_ids,
            segments,
            segment_ids,
            outgoing,
            availability,
            cache_limit,
            cache: VecDeque::new(),
        })
    }

    pub fn node(&self, id: &str) -> Option<&TransportNode> {
        self.node_ids.get(id).map(|&index| &self.nodes[index])
    }

    pub fn segment(&self, id: &str) -> Option<&TransportSegment> {
        self.segment_ids.get(id).map(|&index| &self.segments[index])
    }

    pub fn availability(&self, id: &str) -> Option<SegmentAvailability> {
        self.segment_ids
            .get(id)
            .map(|&index| self.availability[index])
    }

    pub fn restrictions(&self) -> impl Iterator<Item = (&str, SegmentAvailability)> {
        self.segments.iter().zip(&self.availability).filter_map(|(segment, &available)| {
            (!available.open || available.capacity_units != segment.profile.capacity_units)
                .then_some((segment.id.as_str(), available))
        })
    }

    /// The availability belongs to one physical segment, including both travel directions.
    pub fn set_availability(
        &mut self,
        id: &str,
        open: bool,
        capacity_units: u32,
    ) -> Result<(), String> {
        let &index = self
            .segment_ids
            .get(id)
            .ok_or_else(|| format!("unknown transport segment {id}"))?;
        if capacity_units > self.segments[index].profile.capacity_units {
            return Err(format!("availability exceeds nominal capacity on {id}"));
        }
        let previous = self.availability[index];
        let current = SegmentAvailability {
            open,
            capacity_units,
        };
        if previous != current {
            self.availability[index] = current;
            self.cache
                .retain(|entry| !entry.affected(index, previous, current));
        }
        Ok(())
    }
}
