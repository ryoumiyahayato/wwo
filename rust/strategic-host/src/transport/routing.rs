use super::*;
use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashSet};

type Path = Vec<(usize, usize, usize)>; // (from, segment, to) in travel order
type Parents = HashMap<usize, (usize, usize)>; // destination -> (source, segment)

pub(super) struct CacheEntry {
    request: TransportRequest,
    traffic: Option<operations::Traffic>,
    result: Result<Route, RouteError>,
    dependencies: Dependencies,
}

enum Dependencies {
    Found {
        legs: HashSet<usize>,
        blocked: HashSet<usize>,
    },
    Insufficient {
        open_path: HashSet<usize>,
        blocked: HashSet<usize>,
    },
    Disrupted {
        closed_frontier: HashSet<usize>,
    },
    Unreachable,
}

impl CacheEntry {
    pub(super) fn affected(
        &self,
        index: usize,
        old: SegmentAvailability,
        new: SegmentAvailability,
    ) -> bool {
        let demand = self.request.capacity_units;
        let became_usable = !old.supports(demand) && new.supports(demand);
        match &self.dependencies {
            Dependencies::Found { legs, blocked } => {
                legs.contains(&index) || (became_usable && blocked.contains(&index))
            }
            Dependencies::Insufficient { open_path, blocked } => {
                (old.open && !new.open && open_path.contains(&index))
                    || (became_usable && blocked.contains(&index))
            }
            Dependencies::Disrupted { closed_frontier } => {
                !old.open && new.open && closed_frontier.contains(&index)
            }
            Dependencies::Unreachable => false,
        }
    }
}

fn trace(parents: &Parents, from: usize, mut to: usize) -> Path {
    let mut path = Vec::new();
    while to != from {
        let (previous, segment) = parents[&to];
        path.push((previous, segment, to));
        to = previous;
    }
    path.reverse();
    path
}

fn segment_indices(path: &Path) -> HashSet<usize> {
    path.iter().map(|&(_, segment, _)| segment).collect()
}

impl TransportNetwork {
    /// Selects minimum total travel minutes subject to modes and shared capacity.
    /// Equal-time candidates retain the first settled path (stable node and segment IDs).
    pub fn route(&mut self, request: &TransportRequest) -> Result<Route, RouteError> {
        self.route_for_service(request, None)
    }

    pub(super) fn route_for_service(&mut self, request: &TransportRequest, traffic: Option<operations::Traffic>) -> Result<Route, RouteError> {
        if request.capacity_units == 0 {
            return Err(RouteError::InvalidDemand);
        }
        let resolved;
        let from = self.routing_node(&request.from).ok_or_else(||RouteError::UnknownEndpoint(request.from.clone()))?;
        let to = self.routing_node(&request.to).ok_or_else(||RouteError::UnknownEndpoint(request.to.clone()))?;
        let request = if from != request.from || to != request.to {
            resolved = TransportRequest { from: from.into(), to: to.into(), ..request.clone() };
            &resolved
        } else { request };
        if let Some(entry) = self.cache.iter().find(|entry| &entry.request == request && entry.traffic == traffic) {
            return entry.result.clone();
        }
        let endpoint = |id: &str| {
            self.node_ids
                .get(id)
                .copied()
                .ok_or_else(|| RouteError::UnknownEndpoint(id.into()))
        };
        let from = endpoint(&request.from)?;
        let to = endpoint(&request.to)?;
        let gap = if request.allowed_modes.contains(TransportMode::InlandWaterway) {
            self.river_gap(&request.from, &request.to).map(|(s,n)| RouteError::RiverGap(s,n.into()))
        } else { None };
        if from != to {
            for (id, index) in [(&request.from, from), (&request.to, to)] {
                if self.outgoing[index].is_empty() && self.catalogue.known(id) {
                    return Err(gap.unwrap_or_else(||RouteError::UnrefinedEndpoint(id.clone())));
                }
            }
        }
        let (mut result, dependencies) = self.search(request, from, to, traffic);
        if matches!(result, Err(RouteError::Unreachable)) {
            if let Some(reason) = gap { result = Err(reason); }
        }
        if self.cache_limit != 0 {
            if self.cache.len() == self.cache_limit {
                self.cache.pop_front();
            }
            self.cache.push_back(CacheEntry {
                request: request.clone(),
                traffic,
                result: result.clone(),
                dependencies,
            });
        }
        result
    }

    fn search(
        &self,
        request: &TransportRequest,
        from: usize,
        to: usize,
        traffic: Option<operations::Traffic>,
    ) -> (Result<Route, RouteError>, Dependencies) {
        let mut distances = HashMap::from([(from, 0_u64)]);
        let mut parents = Parents::new();
        let mut queue = BinaryHeap::from([Reverse((0_u64, from))]);
        // Earliest possible arrival across a blocked arc bounds which reopenings could improve this answer.
        let mut blocked: HashMap<usize, u64> = HashMap::new();
        while let Some(Reverse((minutes, node))) = queue.pop() {
            if distances[&node] != minutes {
                continue;
            }
            if node == to {
                let path = trace(&parents, from, to);
                let legs = segment_indices(&path);
                let blocked = blocked
                    .into_iter()
                    .filter_map(|(edge, arrival)| (arrival <= minutes).then_some(edge))
                    .collect();
                return (
                    Ok(self.describe(request, &path)),
                    Dependencies::Found { legs, blocked },
                );
            }
            for &arc in &self.outgoing[node] {
                let segment = &self.segments[arc.segment];
                if !request.allowed_modes.contains(segment.mode) {
                    continue;
                }
                let next = minutes + u64::from(segment.profile.travel_minutes);
                if !self.availability[arc.segment].supports(request.capacity_units)
                    || traffic.is_some_and(|class| operations::ServiceCapacity::nominal(segment.profile.capacity_units).class_limit(class) < request.capacity_units) {
                    blocked
                        .entry(arc.segment)
                        .and_modify(|best| *best = (*best).min(next))
                        .or_insert(next);
                    continue;
                }
                if distances.get(&arc.to).is_none_or(|&best| next < best) {
                    distances.insert(arc.to, next);
                    parents.insert(arc.to, (node, arc.segment));
                    queue.push(Reverse((next, arc.to)));
                }
            }
        }

        // Diagnose a failed query only on demand. An open but undersized path takes precedence.
        let closed_frontier = match self.reachable(from, to, request.allowed_modes, true) {
            Ok(path) => {
                let deps = Dependencies::Insufficient {
                    open_path: segment_indices(&path),
                    blocked: blocked.into_keys().collect(),
                };
                return (
                    Err(RouteError::InsufficientCapacity {
                        required_units: request.capacity_units,
                    }),
                    deps,
                );
            }
            Err(closed_frontier) => closed_frontier,
        };
        if !closed_frontier.is_empty()
            && self
                .reachable(from, to, request.allowed_modes, false)
                .is_ok()
        {
            (
                Err(RouteError::Disrupted),
                Dependencies::Disrupted { closed_frontier },
            )
        } else {
            (Err(RouteError::Unreachable), Dependencies::Unreachable)
        }
    }

    /// Finds a directed witness path, or the closed boundary of the reachable nodes.
    fn reachable(
        &self,
        from: usize,
        to: usize,
        modes: ModeSet,
        open_only: bool,
    ) -> Result<Path, HashSet<usize>> {
        let mut queue = VecDeque::from([from]);
        let mut parents = Parents::from([(from, (from, usize::MAX))]);
        let mut closed_frontier = HashSet::new();
        while let Some(node) = queue.pop_front() {
            for &arc in &self.outgoing[node] {
                if parents.contains_key(&arc.to) || !modes.contains(self.segments[arc.segment].mode)
                {
                    continue;
                }
                if open_only && !self.availability[arc.segment].open {
                    closed_frontier.insert(arc.segment);
                    continue;
                }
                parents.insert(arc.to, (node, arc.segment));
                if arc.to == to {
                    return Ok(trace(&parents, from, to));
                }
                queue.push_back(arc.to);
            }
        }
        Err(closed_frontier)
    }

    fn describe(&self, request: &TransportRequest, path: &Path) -> Route {
        let mut route = Route {
            from: request.from.clone(),
            to: request.to.clone(),
            legs: Vec::with_capacity(path.len()),
            travel_minutes: 0,
            cost_units: 0,
            capacity_units: None,
            risk_points: 0,
        };
        for &(from, index, to) in path {
            let segment = &self.segments[index];
            let available = self.availability[index].capacity_units;
            let profile = SegmentProfile {
                capacity_units: available,
                ..segment.profile
            };
            route.travel_minutes += u64::from(profile.travel_minutes);
            route.cost_units += u64::from(profile.cost_units);
            route.risk_points += u64::from(profile.risk_points);
            route.capacity_units = Some(
                route
                    .capacity_units
                    .map_or(available, |previous| previous.min(available)),
            );
            route.legs.push(RouteLeg {
                segment_id: segment.id.clone(),
                from: self.nodes[from].id.clone(),
                to: self.nodes[to].id.clone(),
                mode: segment.mode,
                profile,
                prototype_only: segment.prototype_only,
            });
        }
        route
    }
}
