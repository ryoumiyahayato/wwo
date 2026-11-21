//! Transport reservations use half-open GameClock intervals on physical segments.
use super::{map_data, ModeSet, Route, RouteError, RouteLeg, SegmentAvailability, TransportMode, TransportNetwork, TransportRequest};
use crate::formal_bootstrap::WorldSources;
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet}, io};

#[derive(Clone, Serialize, Deserialize)]
pub struct Plan {
    route: Route,
    load: u32,
    departure: i64,
    windows: Vec<Window>,
}

#[derive(Clone, Copy, Serialize, Deserialize)]
struct Window {
    starts: i64,
    ends: i64,
}

impl Plan {
    pub fn route(&self) -> &Route { &self.route }
    pub fn load_units(&self) -> u32 { self.load }
    pub fn departure_minute(&self) -> i64 { self.departure }
    pub fn first_departure_minute(&self) -> i64 {
        self.windows.first().map_or(self.departure, |window| window.starts)
    }
    pub fn arrival_minute(&self) -> i64 {
        self.windows.last().map_or(self.departure, |window| window.ends)
    }

    // A prototype cost unit is one centime per occupied capacity unit.
    pub fn fare_centimes(&self) -> i64 { self.route.cost_units as i64 * i64::from(self.load) }
}

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
enum Status { Scheduled, Moving, Held, Arrived }

#[derive(Serialize, Deserialize)]
struct Reservation {
    plan: Plan,
    freight: bool,
    leg: usize,
    status: Status,
    stop_at_next: bool,
}

impl Reservation {
    fn occupies(&self, index: usize) -> bool {
        matches!(self.status, Status::Scheduled | Status::Moving) && index >= self.leg
            && (!self.stop_at_next || index == self.leg)
    }

    fn station(&self) -> &str {
        self.plan.route.legs.get(self.leg).map_or(&self.plan.route.to, |leg| &leg.from)
    }
}

#[derive(Serialize, Deserialize)]
pub struct OperationsState {
    next_id: u64,
    closed: BTreeSet<String>,
    #[serde(default)]
    restrictions: BTreeMap<String, SegmentAvailability>,
    reservations: BTreeMap<u64, Reservation>,
}

impl Default for OperationsState {
    fn default() -> Self {
        Self { next_id: 1, closed: BTreeSet::new(), restrictions: BTreeMap::new(), reservations: BTreeMap::new() }
    }
}

pub struct ActiveVehicle<'a> {
    pub segment_id: &'a str,
    pub from: &'a str,
    pub to: &'a str,
    pub mode: TransportMode,
    pub progress: f32,
    pub freight: bool,
}

pub struct Operations {
    network: TransportNetwork,
    state: OperationsState,
    occupied: BTreeMap<String, Vec<(u64, usize)>>,
    now: i64,
}

impl Operations {
    pub fn restore(sources: &WorldSources, now: i64, state: OperationsState) -> io::Result<Self> {
        let network = map_data::load_prototype_map_network(sources, 64)?;
        let mut operations = Self { network, state, occupied: BTreeMap::new(), now };
        if operations.state.next_id == 0 {
            return Err(invalid("运输预约编号无效。"));
        }
        for segment in &operations.state.closed {
            let capacity = operations.network.segment(segment).ok_or_else(|| invalid("存档线路无效。"))?.profile.capacity_units;
            operations.network.set_availability(segment, false, capacity).map_err(io::Error::other)?;
        }
        for (id, access) in &operations.state.restrictions {
            operations.network.set_availability(id, access.open, access.capacity_units).map_err(io::Error::other)?;
        }
        for (&id, reservation) in &operations.state.reservations {
            operations.validate_plan(&reservation.plan)?;
            let count = reservation.plan.windows.len();
            let status_valid = match reservation.status {
                Status::Scheduled => reservation.plan.windows.get(reservation.leg).is_some_and(|w| w.starts > now),
                Status::Moving => reservation.plan.windows.get(reservation.leg).is_some_and(|w| w.starts <= now && now < w.ends),
                Status::Held => reservation.leg < count,
                Status::Arrived => reservation.leg == count && reservation.plan.arrival_minute() <= now,
            };
            if id == 0 || id >= operations.state.next_id || !status_valid
                || (reservation.stop_at_next && reservation.status != Status::Moving)
            {
                return Err(invalid("存档运输预约状态无效。"));
            }
            for (index, window) in reservation.plan.windows.iter().enumerate() {
                if reservation.occupies(index) {
                    let leg = &reservation.plan.route.legs[index];
                    if !operations.fits(&leg.segment_id, *window, reservation.plan.load, leg.profile.capacity_units) {
                        return Err(invalid("存档运输预约超出线路容量。"));
                    }
                    operations.occupied.entry(leg.segment_id.clone()).or_default().push((id, index));
                }
            }
        }
        Ok(operations)
    }

    pub fn state(&self) -> &OperationsState { &self.state }
    pub fn network(&self) -> &TransportNetwork { &self.network }
    pub fn contains_node(&self, place: &str) -> bool { self.network.node(place).is_some() }

    pub fn destinations(&self) -> impl Iterator<Item = &str> {
        self.network.nodes.iter().filter(|node| node.kind == super::NodeKind::City).map(|node| node.id.as_str())
    }

    pub fn connections<'a>(&'a self, place: &str) -> impl Iterator<Item = (&'a str, TransportMode, bool)> + 'a {
        self.network.node_ids.get(place).into_iter().flat_map(|&index| &self.network.outgoing[index])
            .map(|arc| {
                let segment = &self.network.segments[arc.segment];
                (self.network.nodes[arc.to].id.as_str(), segment.mode, self.network.availability(&segment.id).is_some_and(|access| access.open))
            })
    }

    pub fn quote(&mut self, from: &str, to: &str, modes: ModeSet, load: u32, departure: i64) -> io::Result<Plan> {
        if from == to || departure < self.now { return Err(invalid("请选择不同的目的地和有效的出发时间。")); }
        let route = self.network.route(&TransportRequest {
            from: from.into(), to: to.into(), allowed_modes: modes, capacity_units: load,
        }).map_err(|error| invalid(match error {
            RouteError::Unreachable | RouteError::UnknownEndpoint(_) => "现有交通资料没有连接这两个地点。",
            RouteError::Disrupted => "线路中断，当前没有可通行的路线。",
            RouteError::InsufficientCapacity { .. } => "载荷超出可用线路容量。",
            RouteError::InvalidDemand => "运输载荷必须大于零。",
        }))?;
        self.schedule(route, load, departure)
    }

    fn direct_route(&self, segment_id: &str, from: &str, to: &str) -> io::Result<Route> {
        let segment = self.network.segment(segment_id).ok_or_else(|| invalid("线路不存在。"))?;
        let profile = segment.profile;
        let route = Route {
            from: from.into(), to: to.into(),
            legs: vec![RouteLeg { segment_id: segment_id.into(), from: from.into(), to: to.into(),
                mode: segment.mode, profile, prototype_only: segment.prototype_only }],
            travel_minutes: u64::from(profile.travel_minutes),
            cost_units: u64::from(profile.cost_units),
            risk_points: u64::from(profile.risk_points),
            capacity_units: Some(profile.capacity_units),
        };
        Ok(route)
    }

    pub(crate) fn quote_direct(&self, segment: &str, from: &str, to: &str) -> io::Result<Plan> {
        if !self.network.availability(segment).is_some_and(|access| access.supports(1)) {
            return Err(invalid("线路目前中断或没有运力。"));
        }
        self.schedule(self.direct_route(segment, from, to)?, 1, self.now)
    }

    pub(crate) fn import_journey(&mut self, segment: &str, from: &str, to: &str, starts: i64, ends: i64) -> io::Result<u64> {
        let route = self.direct_route(segment, from, to)?;
        let plan = Plan { route, load: 1, departure: starts, windows: vec![Window { starts, ends }] };
        self.validate_plan(&plan)?;
        if !(starts <= self.now && self.now < ends)
            || !self.fits(segment, plan.windows[0], 1, plan.route.legs[0].profile.capacity_units)
        {
            return Err(invalid("旧存档的在途预约无效。"));
        }
        self.insert(plan, false, Status::Moving)
    }

    fn schedule(&self, mut route: Route, load: u32, departure: i64) -> io::Result<Plan> {
        // Keep nominal profiles for persistent plans. Current restrictions are checked separately.
        let mut capacity = u32::MAX;
        for leg in &mut route.legs {
            leg.profile = self.network.segment(&leg.segment_id).expect("route leg is known").profile;
            capacity = capacity.min(leg.profile.capacity_units);
        }
        route.capacity_units = Some(capacity);
        let mut at = departure;
        let mut windows = Vec::with_capacity(route.legs.len());
        for leg in &route.legs {
            let duration = i64::from(leg.profile.travel_minutes);
            loop {
                let end = at.checked_add(duration).ok_or_else(|| invalid("运输时间超出世界时钟范围。"))?;
                let window = Window { starts: at, ends: end };
                if self.fits_current(&leg.segment_id, window, load) {
                    windows.push(window);
                    at = end;
                    break;
                }
                at = self.intervals(&leg.segment_id)
                    .filter_map(|(other, _)| (at < other.ends && other.starts < end).then_some(other.ends))
                    .min().ok_or_else(|| invalid("线路容量不足。"))?;
            }
        }
        let plan = Plan { route, load, departure, windows };
        self.validate_plan(&plan)?;
        Ok(plan)
    }

    pub fn reserve(&mut self, plan: Plan) -> io::Result<u64> { self.book(plan, false) }
    pub fn reserve_freight(&mut self, plan: Plan) -> io::Result<u64> { self.book(plan, true) }

    fn book(&mut self, plan: Plan, freight: bool) -> io::Result<u64> {
        self.validate_plan(&plan)?;
        if plan.departure < self.now { return Err(invalid("出发报价已过期。")); }
        for (leg, &window) in plan.route.legs.iter().zip(&plan.windows) {
            if !self.fits_current(&leg.segment_id, window, plan.load) {
                return Err(invalid("线路可用时间已改变，请重新查询。"));
            }
        }
        let status = if plan.windows[0].starts == self.now { Status::Moving } else { Status::Scheduled };
        self.insert(plan, freight, status)
    }

    fn insert(&mut self, plan: Plan, freight: bool, status: Status) -> io::Result<u64> {
        let id = self.state.next_id;
        self.state.next_id = id.checked_add(1).ok_or_else(|| invalid("运输预约编号已用尽。"))?;
        for (index, leg) in plan.route.legs.iter().enumerate() {
            self.occupied.entry(leg.segment_id.clone()).or_default().push((id, index));
        }
        self.state.reservations.insert(id, Reservation { plan, freight, leg: 0, status, stop_at_next: false });
        Ok(id)
    }

    pub fn plan(&self, id: u64) -> Option<&Plan> { Some(&self.state.reservations.get(&id)?.plan) }
    pub fn is_freight(&self, id: u64) -> bool { self.state.reservations.get(&id).is_some_and(|r| r.freight) }
    pub fn reservation_ids(&self) -> impl Iterator<Item = u64> + '_ { self.state.reservations.keys().copied() }
    pub fn location(&self, id: u64) -> Option<&str> { Some(self.state.reservations.get(&id)?.station()) }
    pub fn moving(&self, id: u64) -> bool { self.state.reservations.get(&id).is_some_and(|r| r.status == Status::Moving) }
    pub fn completed(&self, id: u64) -> Option<&str> { self.station_with_status(id, Status::Arrived) }
    pub fn held(&self, id: u64) -> Option<&str> { self.station_with_status(id, Status::Held) }

    fn station_with_status(&self, id: u64, status: Status) -> Option<&str> {
        let reservation = self.state.reservations.get(&id)?;
        (reservation.status == status).then(|| reservation.station())
    }

    pub fn unused_fare(&self, id: u64) -> Option<i64> {
        let reservation = self.state.reservations.get(&id)?;
        (reservation.status == Status::Held).then(|| reservation.plan.route.legs[reservation.leg..]
            .iter().map(|leg| i64::from(leg.profile.cost_units) * i64::from(reservation.plan.load)).sum())
    }

    /// Cancellation while physically aboard takes effect at the next stop.
    pub fn stop(&mut self, id: u64) -> io::Result<()> {
        let reservation = self.state.reservations.get_mut(&id).ok_or_else(|| invalid("运输预约不存在。"))?;
        match reservation.status {
            Status::Scheduled => reservation.status = Status::Held,
            Status::Moving => reservation.stop_at_next = true,
            Status::Held | Status::Arrived => return Ok(()),
        }
        self.release_unused(id);
        Ok(())
    }

    pub fn finish(&mut self, id: u64) {
        if let Some(reservation) = self.state.reservations.remove(&id) {
            for leg in reservation.plan.route.legs { self.release_edge(&leg.segment_id, id, None); }
        }
    }

    pub fn set_closed(&mut self, segment: &str, closed: bool) -> io::Result<()> {
        let capacity = self.network.segment(segment).ok_or_else(|| invalid("线路不存在。"))?.profile.capacity_units;
        self.set_access(segment, !closed, capacity)
    }

    pub(crate) fn set_access(&mut self, segment: &str, open: bool, capacity_units: u32) -> io::Result<()> {
        self.network.set_availability(segment, open, capacity_units).map_err(io::Error::other)?;
        self.state.closed.remove(segment);
        if open && self.network.segment(segment).is_some_and(|s| s.profile.capacity_units == capacity_units) {
            self.state.restrictions.remove(segment);
        } else {
            self.state.restrictions.insert(segment.into(), SegmentAvailability { open, capacity_units });
        }
        Ok(())
    }

    pub fn next_event(&self) -> Option<i64> {
        self.state.reservations.values().filter_map(|reservation| {
            let window = reservation.plan.windows.get(reservation.leg)?;
            match reservation.status {
                Status::Scheduled => Some(window.starts),
                Status::Moving => Some(window.ends),
                _ => None,
            }
        }).min()
    }

    pub fn advance(&mut self, now: i64) {
        while let Some(event) = self.next_event().filter(|&event| event <= now) {
            let mut changed = Vec::new();
            let mut ready = Vec::new();
            for (&id, reservation) in &mut self.state.reservations {
                let Some(window) = reservation.plan.windows.get(reservation.leg) else { continue };
                if reservation.status == Status::Moving && window.ends == event {
                    reservation.leg += 1;
                    reservation.status = if reservation.leg == reservation.plan.windows.len() {
                        Status::Arrived
                    } else if reservation.stop_at_next {
                        Status::Held
                    } else {
                        Status::Scheduled
                    };
                    reservation.stop_at_next = false;
                    changed.push(id);
                }
                if reservation.status == Status::Scheduled && reservation.plan.windows[reservation.leg].starts == event {
                    ready.push(id);
                }
            }
            for id in ready {
                let admitted = self.can_start(id);
                self.state.reservations.get_mut(&id).expect("scheduled reservation exists").status =
                    if admitted { Status::Moving } else { Status::Held };
                if !admitted { changed.push(id); }
            }
            for id in changed { self.release_unused(id); }
        }
        self.now = now;
    }

    fn can_start(&self, id: u64) -> bool {
        let reservation = &self.state.reservations[&id];
        let leg = &reservation.plan.route.legs[reservation.leg];
        let Some(access) = self.network.availability(&leg.segment_id).filter(|access| access.open) else { return false; };
        let active: u64 = self.occupied.get(&leg.segment_id).into_iter().flatten()
            .filter_map(|&(other, leg_index)| {
                let other = &self.state.reservations[&other];
                (other.status == Status::Moving && other.leg == leg_index).then_some(u64::from(other.plan.load))
            }).sum();
        active + u64::from(reservation.plan.load) <= u64::from(access.capacity_units)
    }

    pub fn active_vehicles(&self) -> impl Iterator<Item = ActiveVehicle<'_>> {
        self.state.reservations.values().filter_map(|reservation| {
            if reservation.status != Status::Moving { return None; }
            let leg = &reservation.plan.route.legs[reservation.leg];
            let window = reservation.plan.windows[reservation.leg];
            Some(ActiveVehicle {
                segment_id: &leg.segment_id, from: &leg.from, to: &leg.to, mode: leg.mode,
                progress: (self.now - window.starts) as f32 / (window.ends - window.starts) as f32,
                freight: reservation.freight,
            })
        })
    }

    fn release_unused(&mut self, id: u64) {
        let reservation = &self.state.reservations[&id];
        let edges = reservation.plan.route.legs.iter().enumerate()
            .filter(|(index, _)| !reservation.occupies(*index))
            .map(|(index, leg)| (index, leg.segment_id.clone())).collect::<Vec<_>>();
        for (index, edge) in edges { self.release_edge(&edge, id, Some(index)); }
    }

    fn release_edge(&mut self, edge: &str, id: u64, index: Option<usize>) {
        if let Some(entries) = self.occupied.get_mut(edge) {
            entries.retain(|&(other_id, leg)| other_id != id || index.is_some_and(|index| index != leg));
            if entries.is_empty() { self.occupied.remove(edge); }
        }
    }

    fn intervals<'a>(&'a self, segment: &str) -> impl Iterator<Item = (Window, u32)> + 'a {
        self.occupied.get(segment).into_iter().flatten().map(|&(id, index)| {
            let plan = &self.state.reservations[&id].plan;
            (plan.windows[index], plan.load)
        })
    }

    fn fits_current(&self, segment: &str, window: Window, load: u32) -> bool {
        self.network.availability(segment).is_some_and(|access| access.open && self.fits(segment, window, load, access.capacity_units))
    }

    fn fits(&self, segment: &str, window: Window, load: u32, capacity: u32) -> bool {
        let capacity = i64::from(capacity);
        if i64::from(load) > capacity { return false; }
        let mut changes = BTreeMap::new();
        for (other, used) in self.intervals(segment) {
            let starts = window.starts.max(other.starts);
            let ends = window.ends.min(other.ends);
            if starts < ends {
                *changes.entry(starts).or_insert(0_i64) += i64::from(used);
                *changes.entry(ends).or_insert(0_i64) -= i64::from(used);
            }
        }
        let mut demand = i64::from(load);
        changes.values().all(|change| { demand += change; demand <= capacity })
    }

    fn validate_plan(&self, plan: &Plan) -> io::Result<()> {
        let route = &plan.route;
        if plan.load == 0 || plan.departure < 0 || route.from == route.to || route.legs.is_empty()
            || route.legs.len() != plan.windows.len()
        {
            return Err(invalid("运输路线数据无效。"));
        }
        let mut from = route.from.as_str();
        let mut at = plan.departure;
        let mut totals = (0_u64, 0_u64, 0_u64, u32::MAX);
        for (leg, window) in route.legs.iter().zip(&plan.windows) {
            let segment = self.network.segment(&leg.segment_id).ok_or_else(|| invalid("运输路线的线路不存在。"))?;
            let direction = segment.from == leg.from && segment.to == leg.to
                || segment.bidirectional && segment.to == leg.from && segment.from == leg.to;
            if !direction || leg.from != from || leg.mode != segment.mode || leg.profile != segment.profile
                || leg.prototype_only != segment.prototype_only || window.starts < at
                || window.ends.checked_sub(window.starts) != Some(i64::from(segment.profile.travel_minutes))
                || plan.load > segment.profile.capacity_units
            {
                return Err(invalid("运输路线与线路数据不一致。"));
            }
            from = &leg.to;
            at = window.ends;
            totals.0 += u64::from(leg.profile.travel_minutes);
            totals.1 += u64::from(leg.profile.cost_units);
            totals.2 += u64::from(leg.profile.risk_points);
            totals.3 = totals.3.min(leg.profile.capacity_units);
        }
        if from != route.to || (route.travel_minutes, route.cost_units, route.risk_points, route.capacity_units)
            != (totals.0, totals.1, totals.2, Some(totals.3))
            || i64::try_from(totals.1).ok().and_then(|cost| cost.checked_mul(i64::from(plan.load))).is_none()
        {
            return Err(invalid("运输路线的费用或汇总无效。"));
        }
        Ok(())
    }
}

fn invalid(message: &str) -> io::Error { io::Error::new(io::ErrorKind::InvalidInput, message) }
