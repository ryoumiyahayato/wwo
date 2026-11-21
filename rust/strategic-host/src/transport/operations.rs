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
    #[serde(default)]
    congestion_tariff: bool,
    #[serde(default)]
    service_limits: bool,
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

    fn leg_fare(&self, index: usize) -> i64 {
        let leg = &self.route.legs[index];
        let base = i64::from(leg.profile.cost_units) * i64::from(self.load);
        let ready = if index == 0 { self.departure } else { self.windows[index - 1].ends };
        let duration = i64::from(leg.profile.travel_minutes);
        let wait = (self.windows[index].starts - ready).clamp(0, duration);
        // Queueing increases the booking quote up to 25% of that leg's base rate.
        let supplement = if self.congestion_tariff && duration > 0 {
            (i128::from(base) * i128::from(wait) / (4 * i128::from(duration))) as i64
        } else { 0 };
        base.saturating_add(supplement)
    }

    pub fn fare_centimes(&self) -> i64 {
        (0..self.route.legs.len()).map(|i| self.leg_fare(i)).fold(0, i64::saturating_add)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
enum Status { Scheduled, Moving, Held, Arrived }

/// One physical limit covers both directions. A directional mixed service
/// provides seats for half its nominal slots (development assumption).
#[derive(Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum Traffic {
    #[default]
    Passenger,
    PlayerFreight,
    Migration,
    Trade,
    PriorityFreight,
}

impl Traffic {
    fn seats(self) -> bool { matches!(self, Self::Passenger | Self::Migration) }
    fn visible(self) -> bool { matches!(self, Self::Passenger | Self::PlayerFreight) }
}

/// With no historical fleet roster, each directional service can take three quarters
/// of the nominal line slots, with up to two thirds for cargo and one half for seats.
#[derive(Clone, Copy, Debug)]
pub struct ServiceCapacity {
    pub line_limit: u32,
    pub service_limit: u32,
    pub cargo_limit: u32,
    pub seat_limit: u32,
    pub line_used: u32,
    pub service_used: u32,
    pub cargo_used: u32,
    pub seats_used: u32,
}

impl ServiceCapacity {
    pub(super) fn nominal(n: u32) -> Self {
        Self { line_limit: n, service_limit: n - n / 4, cargo_limit: n - n / 3, seat_limit: n.div_ceil(2),
            line_used: 0, service_used: 0, cargo_used: 0, seats_used: 0 }
    }

    pub(super) fn class_limit(&self, traffic: Traffic) -> u32 {
        if traffic.seats() { self.seat_limit } else { self.cargo_limit }
    }

    fn admits(&self, load: u32, traffic: Traffic, service_limits: bool) -> bool {
        let class_used = if traffic.seats() { self.seats_used } else { self.cargo_used };
        load <= self.line_limit.saturating_sub(self.line_used) && (!service_limits ||
            load <= self.service_limit.saturating_sub(self.service_used) && load <= self.class_limit(traffic).saturating_sub(class_used))
    }
}

#[derive(Serialize, Deserialize)]
struct Reservation {
    plan: Plan,
    freight: bool,
    #[serde(default)]
    traffic: Traffic,
    leg: usize,
    status: Status,
    stop_at_next: bool,
}

impl Reservation {
    fn next_event(&self) -> Option<i64> {
        let window = self.plan.windows.get(self.leg)?;
        match self.status {
            Status::Scheduled => Some(window.starts),
            Status::Moving => Some(window.ends),
            _ => None,
        }
    }

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
    /// Port handling immediately before or after a booked sea leg.
    pub alongside_seaport: Option<&'a str>,
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
    incoming: Vec<Vec<(usize, usize)>>,
    trade_event: bool,
    visible: BTreeSet<u64>,
    events: BTreeSet<(i64, u64)>,
    now: i64,
}

impl Operations {
    pub fn restore(sources: &WorldSources, now: i64, state: OperationsState) -> io::Result<Self> {
        let network = map_data::load_world_network(sources, 64)?;
        let mut incoming = vec![Vec::new(); network.nodes.len()];
        for (from, arcs) in network.outgoing.iter().enumerate() {
            for arc in arcs { incoming[arc.to].push((from, arc.segment)); }
        }
        let mut operations = Self { network, state, incoming, trade_event: false, occupied: BTreeMap::new(), visible: BTreeSet::new(), events: BTreeSet::new(), now };
        if operations.state.next_id == 0 {
            return Err(invalid("运输预约编号无效。"));
        }
        for segment in &operations.state.closed {
            let capacity = operations.network.segment(segment).ok_or_else(|| invalid("存档线路无效。"))?.profile.capacity_units;
            operations.network.set_availability(segment, false, capacity).map_err(io::Error::other)?;
        }
        for (id, access) in &mut operations.state.restrictions {
            // Preserve a former restriction up to the revised nominal limit.
            if let Some((former, _)) = operations.network.catalogue.former_profiles.get(id) {
                if access.capacity_units <= former.capacity_units {
                    access.capacity_units = access.capacity_units.min(operations.network.segment(id).unwrap().profile.capacity_units);
                }
            }
            operations.network.set_availability(id, access.open, access.capacity_units).map_err(io::Error::other)?;
        }
        for reservation in operations.state.reservations.values_mut() {
            if reservation.freight && reservation.traffic == Traffic::Passenger { reservation.traffic = Traffic::PlayerFreight; }
            if reservation.freight == reservation.traffic.seats() { return Err(invalid("存档运输服务与载荷种类不符。")); }
        }
        for (&id, reservation) in &operations.state.reservations {
            if reservation.traffic.visible() { operations.visible.insert(id); }
            operations.validate_plan_profiles(&reservation.plan, true)?;
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
            if let Some(event) = reservation.next_event() { operations.events.insert((event, id)); }
            for (index, window) in reservation.plan.windows.iter().enumerate() {
                if reservation.occupies(index) {
                    let leg = &reservation.plan.route.legs[index];
                    if !operations.fits(&leg.segment_id, *window, reservation.plan.load, leg.profile.capacity_units, reservation.traffic, &leg.from, reservation.plan.service_limits) {
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
        self.network.routing_node(place).and_then(|id|self.network.node_ids.get(id)).into_iter().flat_map(|&index| &self.network.outgoing[index])
            .map(|arc| {
                let segment = &self.network.segments[arc.segment];
                (self.network.nodes[arc.to].id.as_str(), segment.mode, self.network.availability(&segment.id).is_some_and(|access| access.open))
            })
    }

    pub fn quote(&mut self, from: &str, to: &str, modes: ModeSet, load: u32, departure: i64) -> io::Result<Plan> {
        self.quote_service(from, to, modes, load, departure, Traffic::Passenger)
    }

    pub fn quote_service(&mut self, from: &str, to: &str, modes: ModeSet, load: u32, departure: i64, traffic: Traffic) -> io::Result<Plan> {
        if from == to || departure < self.now { return Err(invalid("请选择不同的目的地和有效的出发时间。")); }
        let route = self.network.route_for_service(&TransportRequest {
            from: from.into(), to: to.into(), allowed_modes: modes, capacity_units: load,
        }, Some(traffic)).map_err(|error| invalid(match &error {
            RouteError::RiverGap(_, reason) => reason.as_str(),
            RouteError::UnknownEndpoint(_) => "未知交通地点。",
            RouteError::UnrefinedEndpoint(_) => "地点已登记，交通连接尚未细化。",
            RouteError::Unreachable => "所选方式没有可用的已知通路。",
            RouteError::Disrupted => "线路中断，当前没有可通行的路线。",
            RouteError::InsufficientCapacity { .. } => "载荷超出可用线路容量。",
            RouteError::InvalidDemand => "运输载荷必须大于零。",
        }))?;
        if route.legs.is_empty() { return Err(invalid("出发地和目的地指向同一交通节点。")); }
        self.schedule(route, load, departure, traffic)
    }

    fn direct_route(&self, segment_id: &str, from: &str, to: &str) -> io::Result<Route> {
        let segment = self.network.segment(segment_id).ok_or_else(|| invalid("线路不存在。"))?;
        let profile = segment.profile;
        let route = Route {
            from: from.into(), to: to.into(),
            legs: vec![RouteLeg { segment_id: segment.id.clone(), from: from.into(), to: to.into(),
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
        self.schedule(self.direct_route(segment, from, to)?, 1, self.now, Traffic::Passenger)
    }

    pub(crate) fn import_journey(&mut self, segment: &str, from: &str, to: &str, starts: i64, ends: i64) -> io::Result<u64> {
        let route = self.direct_route(segment, from, to)?;
        let plan = Plan { route, load: 1, departure: starts, windows: vec![Window { starts, ends }], congestion_tariff: false, service_limits: false };
        self.validate_plan(&plan)?;
        if !(starts <= self.now && self.now < ends)
            || !self.fits(segment, plan.windows[0], 1, plan.route.legs[0].profile.capacity_units, Traffic::Passenger, from, false)
        {
            return Err(invalid("旧存档的在途预约无效。"));
        }
        self.insert(plan, Traffic::Passenger, Status::Moving)
    }

    fn schedule(&self, mut route: Route, load: u32, departure: i64, traffic: Traffic) -> io::Result<Plan> {
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
                if self.fits_current(leg, window, load, traffic) {
                    windows.push(window);
                    at = end;
                    break;
                }
                at = self.intervals(&leg.segment_id)
                    .filter_map(|(other, _)| (at < other.ends && other.starts < end).then_some(other.ends))
                    .min().ok_or_else(|| invalid("线路容量不足。"))?;
            }
        }
        let plan = Plan { route, load, departure, windows, congestion_tariff: true, service_limits: true };
        self.validate_plan(&plan)?;
        Ok(plan)
    }

    pub fn reserve(&mut self, plan: Plan) -> io::Result<u64> { self.book(plan, Traffic::Passenger) }
    pub fn reserve_freight(&mut self, plan: Plan) -> io::Result<u64> { self.book(plan, Traffic::PlayerFreight) }

    pub fn reserve_migration(&mut self, plan: Plan) -> io::Result<u64> { self.book(plan, Traffic::Migration) }
    pub(crate) fn reserve_trade(&mut self, plan: Plan) -> io::Result<u64> { self.book(plan, Traffic::Trade) }
    pub fn reserve_priority_freight(&mut self, plan: Plan) -> io::Result<u64> { self.book(plan, Traffic::PriorityFreight) }

    fn book(&mut self, plan: Plan, traffic: Traffic) -> io::Result<u64> {
        self.validate_plan(&plan)?;
        if plan.departure < self.now { return Err(invalid("出发报价已过期。")); }
        for (leg, &window) in plan.route.legs.iter().zip(&plan.windows) {
            if !self.fits_current(leg, window, plan.load, traffic) {
                return Err(invalid("线路可用时间已改变，请重新查询。"));
            }
        }
        let status = if plan.windows[0].starts == self.now { Status::Moving } else { Status::Scheduled };
        self.insert(plan, traffic, status)
    }

    fn insert(&mut self, plan: Plan, traffic: Traffic, status: Status) -> io::Result<u64> {
        let id = self.state.next_id;
        self.state.next_id = id.checked_add(1).ok_or_else(|| invalid("运输预约编号已用尽。"))?;
        for (index, leg) in plan.route.legs.iter().enumerate() {
            self.occupied.entry(leg.segment_id.clone()).or_default().push((id, index));
        }
        if traffic.visible() { self.visible.insert(id); }
        let reservation = Reservation { plan, freight: !traffic.seats(), traffic, leg: 0, status, stop_at_next: false };
        if let Some(event) = reservation.next_event() { self.events.insert((event, id)); }
        self.state.reservations.insert(id, reservation);
        Ok(id)
    }

    pub fn plan(&self, id: u64) -> Option<&Plan> { Some(&self.state.reservations.get(&id)?.plan) }
    pub fn traffic(&self, id: u64) -> Option<Traffic> { Some(self.state.reservations.get(&id)?.traffic) }
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
        (reservation.status == Status::Held).then(|| (reservation.leg..reservation.plan.route.legs.len())
            .map(|i| reservation.plan.leg_fare(i)).sum())
    }

    /// Cancellation while physically aboard takes effect at the next stop.
    pub fn stop(&mut self, id: u64) -> io::Result<()> {
        let reservation = self.state.reservations.get_mut(&id).ok_or_else(|| invalid("运输预约不存在。"))?;
        match reservation.status {
            Status::Scheduled => {
                self.events.remove(&(reservation.next_event().expect("scheduled departure"), id));
                reservation.status = Status::Held;
                if reservation.traffic == Traffic::Trade { self.trade_event = true; }
            }
            Status::Moving => reservation.stop_at_next = true,
            Status::Held | Status::Arrived => return Ok(()),
        }
        self.release_unused(id);
        Ok(())
    }

    pub fn finish(&mut self, id: u64) {
        self.visible.remove(&id);
        if let Some(reservation) = self.state.reservations.remove(&id) {
            if let Some(event) = reservation.next_event() { self.events.remove(&(event, id)); }
            for leg in reservation.plan.route.legs { self.release_edge(&leg.segment_id, id, None); }
        }
    }

    pub fn set_closed(&mut self, segment: &str, closed: bool) -> io::Result<()> {
        let capacity = self.network.segment(segment).ok_or_else(|| invalid("线路不存在。"))?.profile.capacity_units;
        self.set_access(segment, !closed, capacity)
    }

    pub(crate) fn set_access(&mut self, segment: &str, open: bool, capacity_units: u32) -> io::Result<()> {
        self.network.set_availability(segment, open, capacity_units).map_err(io::Error::other)?;
        let segment = self.network.segment(segment).expect("known segment").id.as_str();
        self.state.closed.remove(segment);
        if open && self.network.segment(segment).is_some_and(|s| s.profile.capacity_units == capacity_units) {
            self.state.restrictions.remove(segment);
        } else {
            self.state.restrictions.insert(segment.into(), SegmentAvailability { open, capacity_units });
        }
        Ok(())
    }

    pub fn next_event(&self) -> Option<i64> { self.events.first().map(|&(at, _)| at) }

    pub fn advance(&mut self, now: i64) {
        while let Some(at) = self.next_event().filter(|&at| at <= now) {
            let mut ready = Vec::new();
            while let Some((_, id)) = self.events.first().copied().filter(|&(event, _)| event == at) {
                self.events.pop_first();
                let r = self.state.reservations.get_mut(&id).expect("indexed trip");
                if r.status == Status::Moving {
                    r.leg += 1;
                    r.status = if r.leg == r.plan.windows.len() { Status::Arrived }
                        else if r.stop_at_next { Status::Held } else { Status::Scheduled };
                    r.stop_at_next = false;
                    if r.traffic == Traffic::Trade && matches!(r.status, Status::Held | Status::Arrived) { self.trade_event = true; }
                    self.release_unused(id);
                }
                let r = &self.state.reservations[&id];
                if let Some(event) = r.next_event() {
                    if event == at { ready.push(id); } else { self.events.insert((event, id)); }
                }
            }
            // Moving loads keep their place. Requisitioned freight boards first
            // only when access cuts prevent fulfilling simultaneous reservations.
            ready.sort_by_key(|id| (self.state.reservations[id].traffic != Traffic::PriorityFreight, *id));
            for id in ready {
                if self.can_start(id) {
                    let r = self.state.reservations.get_mut(&id).unwrap();
                    r.status = Status::Moving;
                    self.events.insert((r.next_event().expect("arrival event"), id));
                } else {
                    let r = self.state.reservations.get_mut(&id).unwrap();
                    r.status = Status::Held;
                    if r.traffic == Traffic::Trade { self.trade_event = true; }
                    self.release_unused(id);
                }
            }
        }
        self.now = now;
    }

    pub(crate) fn trade_event_pending(&self) -> bool { self.trade_event }
    pub(crate) fn clear_trade_event(&mut self) { self.trade_event = false; }

    /// One reverse search gives delivered-cost estimates for the connected suppliers
    /// of a single shortage market. Only the shortlisted orders need time-window quotes.
    pub(crate) fn supplier_rates(&self, destination: &str) -> BTreeMap<String, u64> {
        use std::{cmp::Reverse, collections::BinaryHeap};
        let Some(&end) = self.network.node_ids.get(destination) else { return BTreeMap::new() };
        let mut queue = BinaryHeap::from([Reverse((0_u64, 0_u64, end))]);
        let mut best = vec![(u64::MAX, u64::MAX); self.incoming.len()];
        best[end] = (0, 0);
        let mut rates = BTreeMap::new();
        while let Some(Reverse((minutes, fare, node))) = queue.pop() {
            if best[node] != (minutes, fare) { continue; }
            let id = &self.network.nodes[node].id;
            if node != end && self.network.nodes[node].kind == super::NodeKind::Area {
                if let Some(unit) = self.network.unit_at(id) { rates.insert(unit.to_owned(), fare); }
            }
            for &(from, segment) in &self.incoming[node] {
                if !self.network.availability[segment].supports(1) { continue; }
                let profile = self.network.segments[segment].profile;
                let next = (minutes + u64::from(profile.travel_minutes), fare + u64::from(profile.cost_units));
                if next < best[from] {
                    best[from] = next;
                    queue.push(Reverse((next.0, next.1, from)));
                }
            }
        }
        rates
    }

    pub fn occupied_units(&self, segment: &str) -> u32 {
        let Some(segment) = self.network.segment(segment) else { return 0 };
        self.occupied.get(&segment.id).into_iter().flatten().filter_map(|&(id, index)| {
            let r = &self.state.reservations[&id];
            (r.leg == index && r.status == Status::Moving).then_some(r.plan.load)
        }).sum()
    }

    pub fn service_capacity(&self, segment: &str, from: &str) -> Option<ServiceCapacity> {
        let segment = self.network.segment(segment)?;
        if segment.from != from && !(segment.bidirectional && segment.to == from) { return None; }
        let access = self.network.availability(&segment.id)?;
        let mut limits = ServiceCapacity::nominal(segment.profile.capacity_units);
        limits.line_limit = if access.open { access.capacity_units } else { 0 };
        for &(id, index) in self.occupied.get(&segment.id).into_iter().flatten() {
            let trip = &self.state.reservations[&id];
            if trip.leg != index || trip.status != Status::Moving { continue; }
            let load = trip.plan.load;
            limits.line_used += load;
            if trip.plan.route.legs[index].from == from {
                limits.service_used += load;
                if trip.traffic.seats() { limits.seats_used += load; } else { limits.cargo_used += load; }
            }
        }
        Some(limits)
    }

    fn can_start(&self, id: u64) -> bool {
        let r = &self.state.reservations[&id];
        let leg = &r.plan.route.legs[r.leg];
        self.service_capacity(&leg.segment_id, &leg.from).is_some_and(|capacity| capacity.admits(r.plan.load, r.traffic, r.plan.service_limits))
    }

    pub fn active_vehicles(&self) -> impl Iterator<Item = ActiveVehicle<'_>> {
        self.visible.iter().filter_map(|id| self.active_vehicle(*id))
    }

    pub fn active_vehicles_on<'a>(&'a self, segment: &str) -> impl Iterator<Item = ActiveVehicle<'a>> + 'a {
        self.occupied.get(segment).into_iter().flatten().filter_map(|&(id, index)| {
            let r = &self.state.reservations[&id];
            (r.traffic.visible() && r.leg == index).then(|| self.active_vehicle(id)).flatten()
        })
    }

    fn active_vehicle(&self, id: u64) -> Option<ActiveVehicle<'_>> {
        let reservation = self.state.reservations.get(&id)?;
        if reservation.status != Status::Moving { return None; }
        let leg = &reservation.plan.route.legs[reservation.leg];
        let window = reservation.plan.windows[reservation.leg];
        let legs = &reservation.plan.route.legs;
        let alongside_seaport = if leg.mode != TransportMode::PortTransfer { None }
            else if legs.get(reservation.leg + 1).is_some_and(|next| next.mode == TransportMode::Shipping) { Some(leg.to.as_str()) }
            else if reservation.leg.checked_sub(1).and_then(|i| legs.get(i)).is_some_and(|previous| previous.mode == TransportMode::Shipping) { Some(leg.from.as_str()) }
            else { None };
        Some(ActiveVehicle {
            alongside_seaport,
            segment_id: &leg.segment_id, from: &leg.from, to: &leg.to, mode: leg.mode,
            progress: (self.now - window.starts) as f32 / (window.ends - window.starts) as f32,
            freight: reservation.freight,
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

    fn fits_current(&self, leg: &RouteLeg, window: Window, load: u32, traffic: Traffic) -> bool {
        self.network.availability(&leg.segment_id).is_some_and(|access| access.open && self.fits(&leg.segment_id, window, load, access.capacity_units, traffic, &leg.from, true))
    }

    fn fits(&self, segment: &str, window: Window, load: u32, capacity: u32, traffic: Traffic, from: &str, service_limits: bool) -> bool {
        let mut limits = ServiceCapacity::nominal(self.network.segment(segment).expect("indexed segment").profile.capacity_units);
        limits.line_limit = capacity;
        if !limits.admits(load, traffic, service_limits) { return false; }
        let mut changes = BTreeMap::<_, [i64; 3]>::new();
        for &(id, leg) in self.occupied.get(segment).into_iter().flatten() {
            let other = &self.state.reservations[&id];
            let interval = other.plan.windows[leg];
            let starts = window.starts.max(interval.starts);
            let ends = window.ends.min(interval.ends);
            if starts >= ends { continue; }
            let occupied = i64::from(other.plan.load);
            let service = if other.plan.route.legs[leg].from == from { occupied } else { 0 };
            let class = if other.traffic.seats() == traffic.seats() { service } else { 0 };
            for (i, used) in [occupied, service, class].into_iter().enumerate() {
                changes.entry(starts).or_default()[i] += used;
                changes.entry(ends).or_default()[i] -= used;
            }
        }
        let mut demand = [i64::from(load); 3];
        changes.values().all(|change| {
            for i in 0..3 { demand[i] += change[i]; }
            demand[0] <= i64::from(capacity) && (!service_limits || demand[1] <= i64::from(limits.service_limit)
                && demand[2] <= i64::from(limits.class_limit(traffic)))
        })
    }

    fn validate_plan(&self, plan: &Plan) -> io::Result<()> {
        self.validate_plan_profiles(plan, false)
    }

    fn validate_plan_profiles(&self, plan: &Plan, restoring: bool) -> io::Result<()> {
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
            let current = leg.profile == segment.profile && leg.prototype_only == segment.prototype_only;
            let former = restoring && self.network.catalogue.former_profiles.get(&segment.id)
                == Some(&(leg.profile, leg.prototype_only));
            if !direction || leg.from != from || leg.mode != segment.mode || !(current || former) || window.starts < at
                || window.ends.checked_sub(window.starts) != Some(i64::from(leg.profile.travel_minutes))
                || plan.load > leg.profile.capacity_units
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
            || plan.fare_centimes() > crate::formal_ledger::MAX_AMOUNT
        {
            return Err(invalid("运输路线的费用或汇总无效。"));
        }
        Ok(())
    }
}

fn invalid(message: &str) -> io::Error { io::Error::new(io::ErrorKind::InvalidInput, message) }

#[cfg(test)]
mod tests {
    use super::*;
    use crate::formal_bootstrap::WorldBootstrap;

    #[test]
    fn service_cargo_and_seat_limits_share_line_slots_and_restore_legacy_loads() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut ops = Operations::restore(bootstrap.sources(), 0, OperationsState::default()).unwrap();
        let rail = ModeSet::only(TransportMode::Rail);
        let edge = "rail_paris_rouen";
        let (from, to) = ("place:paris", "place:rouen");
        let cap = ops.service_capacity(edge, from).unwrap();
        let freight = ops.quote_service(from, to, rail, cap.cargo_limit, 0, Traffic::Trade).unwrap();
        let clears = freight.arrival_minute();
        let cargo = ops.reserve_trade(freight).unwrap();
        let next = ops.quote_service(from, to, rail, 1, 0, Traffic::PlayerFreight).unwrap();
        assert_eq!(next.first_departure_minute(), clears);
        let free = cap.service_limit - cap.cargo_limit;
        let riders = ops.quote(from, to, rail, free, 0).unwrap();
        assert_eq!(riders.first_departure_minute(), 0);
        let riders = ops.reserve_migration(riders).unwrap();
        assert_eq!(ops.quote(from, to, rail, 1, 0).unwrap().first_departure_minute(), clears);
        assert_eq!(ops.quote(to, from, rail, 1, 0).unwrap().first_departure_minute(), 0);
        let loaded = ops.service_capacity(edge, from).unwrap();
        assert_eq!((loaded.line_used, loaded.service_used, loaded.cargo_used, loaded.seats_used),
            (cap.service_limit, cap.service_limit, cap.cargo_limit, free));

        ops.finish(riders);
        let mut saved = serde_json::to_value(ops.state()).unwrap();
        let old = saved["reservations"][cargo.to_string()]["plan"].as_object_mut().unwrap();
        old.remove("service_limits");
        old.insert("load".into(), cap.line_limit.into());
        let mut ops = Operations::restore(bootstrap.sources(), 0, serde_json::from_value(saved).unwrap()).unwrap();
        assert_eq!(ops.occupied_units(edge), cap.line_limit);
        assert_eq!(ops.quote(to, from, rail, 1, 0).unwrap().first_departure_minute(), clears);
        ops.advance(clears);
        assert_eq!(ops.occupied_units(edge), 0);
    }

    #[test]
    fn reduced_service_prioritizes_pending_freight_and_keeps_boarded_load() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut ops = Operations::restore(bootstrap.sources(), 0, OperationsState::default()).unwrap();
        let rail = ModeSet::only(TransportMode::Rail);
        let edge = "rail_paris_rouen";
        let from = "place:paris";
        let to = "place:rouen";
        let aboard = ops.quote_service(from, to, rail, 3, 0, Traffic::Trade).unwrap();
        let arrival = aboard.arrival_minute();
        let moving = ops.reserve_trade(aboard).unwrap();
        let civilian = ops.quote(from, to, rail, 2, 1).unwrap();
        let civilian = ops.reserve_migration(civilian).unwrap();
        let priority = ops.quote_service(from, to, rail, 2, 1, Traffic::PriorityFreight).unwrap();
        let priority = ops.reserve_priority_freight(priority).unwrap();
        ops.set_access(edge, true, 5).unwrap();
        ops.advance(1);
        assert_eq!(ops.occupied_units(edge), 5);
        assert!(ops.moving(moving) && ops.moving(priority));
        assert_eq!(ops.held(civilian), Some(from));
        assert_eq!(ops.next_event(), Some(arrival));
        ops.advance(arrival);
        assert_eq!(ops.occupied_units(edge), 2);
        ops.advance(arrival + 1);
        assert_eq!(ops.occupied_units(edge), 0);
    }
}
