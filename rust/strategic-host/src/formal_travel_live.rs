use super::*;
use crate::{
    formal_ledger::TRANSPORT_ACCOUNT,
    transport::{operations::{ActiveVehicle, Plan, Traffic}, ModeSet, Route, TransportMode},
};

#[derive(Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
enum Purpose { Personal, Workbound, Homebound }

#[derive(Deserialize, Serialize)]
struct Passenger {
    id: u64,
    purpose: Purpose,
    #[serde(default)]
    legacy: bool,
}

#[derive(Deserialize, Serialize)]
struct Commute {
    base: String,
    next_departure: i64,
    return_after: Option<i64>,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct TravelState {
    place: Option<String>,
    passenger: Option<Passenger>,
    commute: Option<Commute>,
    notice: String,
    #[serde(default)]
    named: BTreeMap<String, Passenger>,
    #[serde(default)]
    stations: BTreeMap<String, String>,
}

impl InitialWorld {
    pub fn last_station(&self) -> &str {
        self.travel.place.as_deref().unwrap_or(&self.player().place_id)
    }

    pub fn residence(&self) -> &str { self.player_home() }
    pub(super) fn present_at<'a>(&'a self, person: &str, opening: &'a str) -> Option<&'a str> {
        self.travel.present_at(person, &self.player, opening)
    }

    /// Depart on a specific existing service when a named resident has chosen it.
    pub fn travel_person(&mut self, person: &str, segment: &str, destination: &str) -> io::Result<()> {
        let from = self.passenger_origin(person)?.to_owned();
        let plan = self.transport.quote_direct(segment, &from, destination)?;
        self.start_named_passenger(person, plan)
    }

    /// Depart on a connected itinerary chosen for a named resident.
    pub fn travel_person_to(&mut self, person: &str, destination: &str, modes: ModeSet) -> io::Result<()> {
        let from = self.passenger_origin(person)?.to_owned();
        let plan = self.transport.quote(&from, destination, modes, 1, self.clock.snapshot().total_minutes)?;
        self.start_named_passenger(person, plan)
    }

    fn passenger_origin(&self, person: &str) -> io::Result<&str> {
        if person == self.player { self.check_leisure()?; }
        if self.service.named_target(person).is_some()
            || self.work.booking(person).zip(self.work.contract(&self.work_opening, person))
                .is_some_and(|(start, job)| self.clock.snapshot().total_minutes < start + job.hours * MINUTES_PER_HOUR)
        {
            return Err(invalid("当前工作或服役安排不允许旅行。"));
        }
        self.current_place(person).ok_or_else(|| invalid("人物不在出发地。"))
    }

    fn start_named_passenger(&mut self, person: &str, plan: Plan) -> io::Result<()> {
        if person == self.player {
            return self.start_passenger(plan, Purpose::Personal);
        }
        let amount = plan.fare_centimes();
        let id = self.transport.reserve(plan)?;
        if let Err(error) = self.pay_passage(person, amount, id) {
            self.transport.finish(id);
            return Err(error);
        }
        self.travel.named.insert(person.to_owned(), Passenger { id, purpose: Purpose::Personal, legacy: false });
        Ok(())
    }

    pub(super) fn import_legacy_travel(&mut self, legacy: crate::formal_travel::LegacyTravel) -> io::Result<()> {
        if !legacy.validate(&self.sources, self.transport.network(), self.clock, |person| {
            self.population.unit_for_person(person)?;
            self.person(person).map(|row| row.place_id.as_str())
        }) {
            return Err(invalid("旧存档的客运无效。"));
        }
        for (person, journey) in legacy.last_arrivals {
            if person == self.player {
                self.travel.place = Some(journey.destination);
            } else {
                self.travel.stations.insert(person, journey.destination);
            }
        }
        for (person, journey) in legacy.journeys {
            let id = self.transport.import_journey(&journey.route_id, &journey.origin, &journey.destination,
                journey.departure_minute, journey.arrival_minute)?;
            let ticket = Passenger { id, purpose: Purpose::Personal, legacy: true };
            if person == self.player {
                self.travel.passenger = Some(ticket);
            } else {
                self.travel.named.insert(person, ticket);
            }
        }
        Ok(())
    }
    pub fn passenger_in_transit(&self) -> bool { self.travel.passenger.is_some() }
    pub fn travel_notice(&self) -> &str { &self.travel.notice }
    pub fn commute_base(&self) -> Option<&str> { self.travel.commute.as_ref().map(|c| c.base.as_str()) }
    pub fn commute_departure(&self) -> Option<i64> { self.travel.commute.as_ref().map(|c| c.next_departure) }

    pub fn travel_plan(&self) -> Option<&Plan> {
        self.travel.passenger.as_ref().and_then(|p| self.transport.plan(p.id))
    }

    pub fn passenger_moving(&self) -> bool {
        self.travel.passenger.as_ref().is_some_and(|p| self.transport.moving(p.id))
    }

    pub fn selected_transport_route(&self) -> Option<&Route> {
        let now = self.clock.snapshot().total_minutes;
        self.travel_plan()
            .or_else(|| self.selected_freight.and_then(|id| self.transport.plan(id)))
            .or_else(|| self.travel_preview.as_ref().filter(|plan| plan.departure_minute() >= now))
            .or_else(|| self.freight_preview.as_ref().filter(|plan| plan.departure_minute() >= now))
            .map(Plan::route)
    }

    pub fn transport_vehicles_on<'a>(&'a self, segment: &str) -> impl Iterator<Item = ActiveVehicle<'a>> + 'a {
        self.transport.active_vehicles_on(segment)
    }

    pub fn travel_preview(&self) -> Option<&Plan> { self.travel_preview.as_ref() }
    pub fn clear_transport_preview(&mut self) {
        self.travel_preview = None;
        self.freight_preview = None;
        self.selected_freight = None;
    }

    pub fn show_freight_route(&mut self, plan: &Plan) {
        self.clear_transport_preview();
        self.freight_preview = Some(plan.clone());
    }

    pub fn select_freight_route(&mut self, reservation: Option<u64>) {
        self.clear_transport_preview();
        self.selected_freight = reservation;
    }

    pub fn freight_progress(&self, id: u64) -> (Option<&str>, Option<&Plan>) {
        if !self.transport.is_freight(id) { return (None, None); }
        (self.transport.location(id), self.transport.plan(id))
    }

    pub fn transport_destinations(&self) -> impl Iterator<Item = &str> {
        use crate::transport::NodeKind;
        let station = self.last_station();
        let network = self.transport.network();
        let local = self.transport.connections(station).filter_map(move |(id, _, _)| {
            network.node(id).is_some_and(|node| matches!(node.kind, NodeKind::City | NodeKind::Port)).then_some(id)
        }).collect::<BTreeSet<_>>();
        let nearby = local.iter().copied().collect::<Vec<_>>();
        nearby.into_iter().chain(network.nodes().filter_map(move |node| {
            (node.id != station && matches!(node.kind, NodeKind::City | NodeKind::Area)
                && !local.contains(node.id.as_str())).then_some(node.id.as_str())
        }))
    }

    pub fn can_select_transport_destination(&self, id: &str) -> bool {
        use crate::transport::NodeKind;
        let network = self.transport.network();
        network.routing_node(id).and_then(|key| network.node(key)).is_some_and(|node|
            matches!(node.kind, NodeKind::City | NodeKind::Area | NodeKind::Port))
    }

    pub fn transport_connections(&self, place: &str) -> Option<String> {
        let links: Vec<_> = self.transport.connections(place).take(4).map(|(to, mode, open)| {
            format!("{} {}{}", mode_name(mode), self.place_name(to), if open { "" } else { "（停运）" })
        }).collect();
        if !links.is_empty() { return Some(links.join(" · ")); }
        let network = self.transport.network();
        if let Some(note) = network.notes_at(place).next() { return Some(note.to_owned()); }
        use crate::transport::NodeCoverage;
        Some(match network.coverage(place) {
            NodeCoverage::Unknown => "该地尚缺交通资料。",
            NodeCoverage::Unrefined => "地点已登记，线路尚未细化。",
            NodeCoverage::Impassable => "该地已知通路均已中断。",
            NodeCoverage::Connected => "已接入地区交通。",
        }.to_owned())
    }

    pub fn place_name<'a>(&'a self, id: &'a str) -> &'a str {
        self.sources.places().get(id).map(|place| place.name.as_str())
            .or_else(|| self.transport.network().node_label(id)).unwrap_or(id)
    }

    pub fn place_coordinates(&self, id: &str) -> Option<[f64; 2]> {
        self.sources.places().get(id).and_then(|place| place.lon_lat)
            .or_else(|| self.transport.network().node_coordinates(id))
    }

    pub fn close_transport_segment(&mut self, segment: &str, closed: bool) -> io::Result<()> {
        self.transport.set_closed(segment, closed)
    }

    pub fn preview_travel(&mut self, to: &str, modes: ModeSet) -> io::Result<&Plan> {
        if !self.player_alive() { return Err(invalid("人物已无法旅行。")); }
        if self.passenger_in_transit() { return Err(invalid("请在到站后查询新的旅程。")); }
        let from = self.last_station().to_owned();
        self.clear_transport_preview();
        self.travel_preview = Some(self.transport.quote(&from, to, modes, 1, self.clock.snapshot().total_minutes)?);
        Ok(self.travel_preview.as_ref().unwrap())
    }

    pub fn preview_work_trip(&mut self) -> io::Result<&Plan> {
        let workplace = self.employment().ok_or_else(|| invalid("须先取得真实工作合同。"))?.0.place.clone();
        self.preview_travel(&workplace, ModeSet::ALL)
    }

    pub fn depart_player(&mut self) -> io::Result<()> {
        self.check_leisure()?;
        let plan = self.travel_preview.take().ok_or_else(|| invalid("请选择目的地并查询路线。"))?;
        if plan.route().from != self.last_station() { return Err(invalid("出发地已改变，请重新查询。")); }
        self.start_passenger(plan, Purpose::Personal)
    }

    pub fn stop_player(&mut self) -> io::Result<()> {
        let id = self.travel.passenger.as_ref().ok_or_else(|| invalid("没有已预约的旅程。"))?.id;
        self.transport.stop(id)?;
        self.travel.notice = "将在下一站下车或离船，并退还未使用路段的费用。".into();
        self.settle_passenger()
    }

    pub fn set_commute(&mut self, enabled: bool) -> io::Result<()> {
        if !enabled { self.travel.commute = None; return Ok(()); }
        if !self.player_alive() || self.passenger_in_transit() {
            return Err(invalid("请在车站或城市停留后再设置通勤。"));
        }
        let (job, _, _) = self.employment().ok_or_else(|| invalid("须先取得真实工作合同。"))?;
        let base = self.last_station().to_owned();
        let workplace = job.place.clone();
        let duration = job.hours * MINUTES_PER_HOUR;
        let now = self.clock.snapshot().total_minutes;
        let first = next_morning(now);
        if base != workplace {
            let plan = self.transport.quote(&base, &workplace, ModeSet::ALL, 1, first)?;
            if plan.arrival_minute() > first - first % MINUTES_PER_DAY + MINUTES_PER_DAY - duration {
                return Err(invalid("从本站出发当天来不及完成工作。"));
            }
        }
        self.travel.commute = Some(Commute { base, next_departure: first, return_after: None });
        self.travel.notice = "已安排每日 06:00 从通勤起点出发，到岗后登记。".into();
        Ok(())
    }

    pub(super) fn check_leisure(&self) -> io::Result<()> {
        let now = self.clock.snapshot().total_minutes;
        let working = self.work.booking(&self.player).zip(self.employment())
            .is_some_and(|(start, (job, _, _))| now < start + job.hours * MINUTES_PER_HOUR);
        if !self.player_alive() || self.player_service().is_some() || self.passenger_in_transit() || working || self.player_day.booking.is_some() {
            return Err(invalid("人物在途中、工作中，或已有个人时间安排。"));
        }
        Ok(())
    }

    fn start_passenger(&mut self, plan: Plan, purpose: Purpose) -> io::Result<()> {
        let amount = plan.fare_centimes();
        let id = self.transport.reserve(plan)?;
        if let Err(error) = self.pay_transport(amount, id) {
            self.transport.finish(id);
            return Err(error);
        }
        self.travel.passenger = Some(Passenger { id, purpose, legacy: false });
        self.travel.notice = format!("已支付 {amount} 生丁并预留运力。");
        Ok(())
    }

    pub(super) fn pay_transport(&mut self, amount: i64, id: u64) -> io::Result<()> {
        self.pay_passage(&self.player.clone(), amount, id)
    }

    fn pay_passage(&mut self, person: &str, amount: i64, id: u64) -> io::Result<()> {
        let payer = self.ledger.default_account(person).ok_or_else(|| invalid("人物账户缺失。"))?.account_id.to_owned();
        self.ledger.transfer(&format!("transport:fare:{id}"), &payer, TRANSPORT_ACCOUNT, amount,
            self.clock.snapshot().total_minutes, "transport_fare", &format!("transport:{id}"))
    }

    pub(super) fn refund_transport(&mut self, amount: i64, id: u64) -> io::Result<()> {
        self.refund_passage(&self.player.clone(), amount, id)
    }

    fn refund_passage(&mut self, person: &str, amount: i64, id: u64) -> io::Result<()> {
        if amount == 0 { return Ok(()); }
        let payer = self.ledger.default_account(person).ok_or_else(|| invalid("人物账户缺失。"))?.account_id.to_owned();
        self.ledger.transfer(&format!("transport:refund:{id}"), TRANSPORT_ACCOUNT, &payer, amount,
            self.clock.snapshot().total_minutes, "transport_refund", &format!("transport:{id}"))
    }

    fn settle_passenger(&mut self) -> io::Result<()> {
        let Some(passenger) = self.travel.passenger.as_ref() else { return Ok(()); };
        let (id, purpose) = (passenger.id, passenger.purpose);
        self.travel.place = self.transport.location(id).map(str::to_owned);
        if self.transport.held(id).is_some() {
            let amount = if passenger.legacy { 0 } else { self.transport.unused_fare(id).expect("held ticket has a remaining fare") };
            self.refund_transport(amount, id)?;
            self.transport.finish(id);
            self.travel.passenger = None;
            self.travel.notice = format!("行程在本站停止，已退还 {amount} 生丁。现在可重新查询路线。");
        } else if self.transport.completed(id).is_some() {
            self.transport.finish(id);
            self.travel.passenger = None;
            self.travel.notice = "已抵达。".into();
            if purpose == Purpose::Workbound && self.travel.commute.is_some() {
                self.attend_commute();
            }
        }
        Ok(())
    }

    fn settle_named_passengers(&mut self) -> io::Result<()> {
        for (person, ticket) in &self.travel.named {
            if let Some(station) = self.transport.location(ticket.id) {
                let initial = self.runtime_people.get(person).map(|row| &row.origin)
                    .or_else(|| self.sources.people.get(person));
                if initial.is_some_and(|row| row.place_id == station) {
                    self.travel.stations.remove(person);
                } else if self.travel.stations.get(person).map(String::as_str) != Some(station) {
                    self.travel.stations.insert(person.clone(), station.to_owned());
                }
            }
        }
        let finished: Vec<_> = self.travel.named.iter().filter_map(|(person, ticket)| {
            let completed = self.transport.completed(ticket.id).or_else(|| self.transport.held(ticket.id))?;
            let refund = if ticket.legacy { 0 } else { self.transport.unused_fare(ticket.id).unwrap_or(0) };
            Some((person.clone(), ticket.id, completed.to_owned(), refund))
        }).collect();
        for (person, id, station, refund) in finished {
            self.refund_passage(&person, refund, id)?;
            self.transport.finish(id);
            self.travel.named.remove(&person);
            self.travel.stations.insert(person, station);
        }
        Ok(())
    }

    pub(super) fn next_travel_event(&self) -> Option<i64> {
        let next = self.transport.next_event();
        let commute = self.travel.commute.as_ref();
        next.into_iter().chain(commute.map(|c| c.next_departure)).chain(commute.and_then(|c| c.return_after)).min()
    }

    pub(super) fn advance_transport(&mut self) -> io::Result<()> {
        let now = self.clock.snapshot().total_minutes;
        self.transport.advance(now);
        self.settle_passenger()?;
        self.settle_named_passengers()?;
        self.settle_freight()?;
        self.macro_economy.settle_transport(&mut self.transport, &mut self.ledger, now)?;
        self.settle_background_migrations(now)?;
        let Some(commute) = self.travel.commute.as_mut() else { return Ok(()); };
        if commute.return_after == Some(now) {
            commute.return_after = None;
            let base = commute.base.clone();
            if let Err(error) = self.commute_trip(&base, Purpose::Homebound) {
                self.travel.notice = format!("返程未发车：{error}");
            }
        }
        if self.travel.commute.as_ref().is_some_and(|c| c.next_departure == now) {
            let commute = self.travel.commute.as_mut().unwrap();
            commute.next_departure = next_morning(now);
            let base = commute.base.clone();
            if let Err(error) = self.depart_for_work(&base) {
                self.travel.notice = format!("今日未登记出勤：{error}");
            }
        }
        Ok(())
    }

    fn depart_for_work(&mut self, base: &str) -> io::Result<()> {
        self.check_leisure()?;
        let (job, _, _) = self.employment().ok_or_else(|| invalid("没有工作合同。"))?;
        let workplace = job.place.clone();
        let duration = job.hours * MINUTES_PER_HOUR;
        if self.last_station() == workplace {
            self.attend_commute();
            return Ok(());
        }
        if self.last_station() != base { return Err(invalid("人物未在通勤起点。")); }
        let now = self.clock.snapshot().total_minutes;
        let plan = self.transport.quote(base, &workplace, ModeSet::ALL, 1, now)?;
        if plan.arrival_minute() + duration > (self.clock.current_day() + 1) * MINUTES_PER_DAY {
            return Err(invalid("当前班次无法及时到岗。"));
        }
        self.start_passenger(plan, Purpose::Workbound)
    }

    fn attend_commute(&mut self) {
        let result = self.book_work();
        match result {
            Ok(()) => {
                let now = self.clock.snapshot().total_minutes;
                let (job, _, _) = self.employment().expect("work booking has a contract");
                let end = now + job.hours * MINUTES_PER_HOUR;
                let work_place = job.place.clone();
                let commute = self.travel.commute.as_mut().expect("attendance is for active commute");
                commute.return_after = (commute.base != work_place).then_some(end);
                self.travel.notice = "已在工作地登记出勤，工作完成后自动安排返程。".into();
            }
            Err(error) => self.travel.notice = format!("今日未登记出勤：{error}"),
        }
    }

    fn commute_trip(&mut self, destination: &str, purpose: Purpose) -> io::Result<()> {
        if destination == self.last_station() { return Ok(()); }
        self.check_leisure()?;
        let from = self.last_station().to_owned();
        let plan = self.transport.quote(&from, destination, ModeSet::ALL, 1, self.clock.snapshot().total_minutes)?;
        self.start_passenger(plan, purpose)
    }

    pub(super) fn validate_travel(&self) -> io::Result<()> {
        let now = self.clock.snapshot().total_minutes;
        let known_place = |place: &str| self.sources.places().contains_key(place)
            || self.transport.contains_node(place);
        let valid_ticket = |person: &str, p: &Passenger, station: &str| {
            self.population.unit_for_person(person).is_some() && self.transport.traffic(p.id) == Some(Traffic::Passenger)
                && self.transport.location(p.id) == Some(station)
                && self.transport.held(p.id).is_none() && self.transport.completed(p.id).is_none()
                && self.transport.plan(p.id).zip(self.ledger.default_account(person)).is_some_and(|(plan, payer)| {
                    if p.legacy {
                        p.purpose == Purpose::Personal && plan.route().legs.len() == 1
                            && plan.first_departure_minute() <= now
                    } else {
                        self.ledger.has_payment(&format!("transport:fare:{}", p.id), payer.account_id, TRANSPORT_ACCOUNT,
                            plan.fare_centimes(), "transport_fare", &format!("transport:{}", p.id))
                    }
                })
        };
        let mut reservations = self.freight_reservation_ids().collect::<BTreeSet<_>>();
        let valid_player = self.travel.passenger.as_ref()
            .is_none_or(|ticket| reservations.insert(ticket.id) && valid_ticket(&self.player, ticket, self.last_station()));
        let valid_named = self.travel.named.iter().all(|(person, ticket)| {
            person != &self.player && ticket.purpose == Purpose::Personal && reservations.insert(ticket.id)
                && self.person(person).is_some_and(|row| {
                    let station = self.travel.stations.get(person).map_or(row.place_id.as_str(), String::as_str);
                    valid_ticket(person, ticket, station)
                })
        }) && self.travel.stations.iter().all(|(person, place)| {
            person != &self.player && self.population.unit_for_person(person).is_some() && known_place(place)
        });
        if !known_place(self.last_station()) || !valid_player || !valid_named
            || !self.macro_economy.reservation_ids().all(|id| reservations.insert(id))
            || !self.validate_migrations(&mut reservations)
            || !self.transport.reservation_ids().eq(reservations)
            || self.travel.commute.as_ref().is_some_and(|c| !self.player_alive() || self.employment().is_none()
                || !known_place(&c.base) || c.next_departure <= now || c.return_after.is_some_and(|minute| minute <= now))
        {
            return Err(invalid("原生存档中的人物旅程无效。"));
        }
        Ok(())
    }

    pub(super) fn stop_transport_on_death(&mut self, person: &str) {
        let ticket = if person == self.player {
            self.travel.commute = None;
            self.travel_preview = None;
            self.travel.passenger.take()
        } else {
            self.travel.stations.remove(person);
            self.travel.named.remove(person)
        };
        if let Some(passenger) = ticket {
            self.transport.finish(passenger.id);
        }
    }
}

impl TravelState {
    pub(super) fn present_at<'a>(&'a self, person: &str, player: &str, opening: &'a str) -> Option<&'a str> {
        if person == player {
            self.passenger.is_none().then(|| self.place.as_deref().unwrap_or(opening))
        } else {
            (!self.named.contains_key(person)).then(|| self.stations.get(person).map_or(opening, String::as_str))
        }
    }

    pub(super) fn disable_commute(&mut self) { self.commute = None; }
}

fn next_morning(now: i64) -> i64 {
    let today = now - now % MINUTES_PER_DAY + 6 * MINUTES_PER_HOUR;
    if today > now { today } else { today + MINUTES_PER_DAY }
}

pub fn mode_set(mode: &str) -> ModeSet {
    match mode {
        "rail" => ModeSet::only(TransportMode::Rail),
        "road" => ModeSet::only(TransportMode::Road),
        "shipping" => ModeSet::only(TransportMode::Shipping).with(TransportMode::PortTransfer).with(TransportMode::Domestic),
        "inland" => ModeSet::only(TransportMode::InlandWaterway).with(TransportMode::PortTransfer).with(TransportMode::Domestic),
        "domestic" => ModeSet::only(TransportMode::Domestic),
        _ => ModeSet::ALL,
    }
}

pub fn mode_name(mode: TransportMode) -> &'static str {
    match mode {
        TransportMode::Rail => "铁路", TransportMode::Road => "道路",
        TransportMode::Shipping => "轮船", TransportMode::PortTransfer => "港口换装",
        TransportMode::InlandWaterway => "内河", TransportMode::Domestic => "国内集散",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PARIS: &str = "place:paris";
    const ROUEN: &str = "place:rouen";
    const RAIL: ModeSet = ModeSet::only(TransportMode::Rail);

    fn resume(bootstrap: &WorldBootstrap, world: &InitialWorld) -> InitialWorld {
        bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap()
    }

    #[test]
    fn transport_passenger_and_freight_share_timed_capacity_in_both_directions() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut operations = Operations::restore(bootstrap.sources(), 0, OperationsState::default()).unwrap();
        let limits = operations.service_capacity("rail_paris_rouen", PARIS).unwrap();
        let rider = operations.quote(PARIS, ROUEN, RAIL, limits.seat_limit, 0).unwrap();
        let capacity = limits.cargo_limit;
        let clears = rider.arrival_minute();
        let first = operations.reserve(rider).unwrap();
        let freight = operations.quote_service(ROUEN, PARIS, RAIL, capacity, 0, Traffic::PlayerFreight).unwrap();
        assert_eq!(freight.first_departure_minute(), clears);
        let second = operations.reserve_freight(freight).unwrap();
        assert!(!operations.moving(second));
        operations.advance(clears);
        assert_eq!(operations.completed(first), Some(ROUEN));
        assert!(operations.moving(second));
    }

    #[test]
    fn transport_stop_refund_and_commute_use_work_and_native_save() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        world.apply_for_work("job:opening_paris_workshop").unwrap();
        let initial_cash = world.balance().unwrap().cash;
        let plan = world.preview_travel("place:le_havre", RAIL).unwrap();
        let first = plan.route().legs[0].profile;
        let fare = i64::from(first.cost_units);
        let duration = i64::from(first.travel_minutes);
        world.depart_player().unwrap();
        world.stop_player().unwrap();
        // Earlier French slots had a contract and ticket but no Japanese payroll account.
        let mut slot = world.snapshot();
        let fields = slot["ledger"][1].as_array_mut().unwrap();
        let accounts = &mut fields.iter_mut().find(|field| field[0] == "accounts").unwrap()[1][1];
        let rows = accounts.as_array_mut().unwrap();
        let count = rows.len();
        rows.retain(|row| crate::formal_save::lookup(crate::formal_save::map(row).unwrap(), "owner_id")
            .and_then(serde_json::Value::as_str) != Some("market:legacy_aggregate:empire_of_japan"));
        assert_eq!(rows.len() + 1, count);
        let mut world = bootstrap.restore_native(serde_json::from_value(slot).unwrap()).unwrap();
        world.advance_migrated_domains(duration, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some(ROUEN));
        assert_eq!(world.player_home(), PARIS);
        assert_eq!(world.balance().unwrap().cash, initial_cash - fare);
        assert!(world.book_work().is_err());
        assert_eq!(world.jobs().count(), 0);
        world.set_commute(true).unwrap();
        let work_at = 360 + duration;
        world.advance_migrated_domains(work_at - duration, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some(PARIS));
        assert_eq!(world.work.booking(&world.player), Some(work_at));
        let shift_minutes = world.employment().unwrap().0.hours * MINUTES_PER_HOUR;
        world.advance_migrated_domains(shift_minutes + duration, &BTreeMap::new()).unwrap();
        let mut world = resume(&bootstrap, &world);
        assert_eq!(world.player_current_place(), Some(ROUEN));
        assert_eq!(world.balance().unwrap().cash, initial_cash - 3 * fare);
        world.move_player_home().unwrap();
        assert_eq!(resume(&bootstrap, &world).player_home(), ROUEN);
    }

    #[test]
    fn global_population_transport_traveler_keeps_residence_until_registered_move() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("british_isles_1900").unwrap();
        let player = world.player().id.clone();
        let home = world.player_home().to_owned();
        let visit = world.preview_travel(PARIS, ModeSet::ALL).unwrap().arrival_minute();
        world.depart_player().unwrap();
        assert_eq!(world.player_current_place(), None);
        assert_eq!(world.person_home(&player), Some(home.as_str()));
        let mut world = resume(&bootstrap, &world);
        world.advance_migrated_domains(visit, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some(PARIS));
        assert_eq!(world.market_unit_for_person(&player), Some("country_fra"));
        assert_eq!(world.population.unit_for_person(&player), Some("british_isles_1900"));
        world.consult_local_work(&player).unwrap();
        world.apply_for_work("job:opening_paris_workshop").unwrap();

        let arrival = world.preview_travel(ROUEN, RAIL).unwrap().arrival_minute();
        world.depart_player().unwrap();
        world.advance_migrated_domains(arrival - visit, &BTreeMap::new()).unwrap();
        assert!(world.book_work().is_err());
        assert_eq!(world.preview_work_trip().unwrap().route().to, PARIS);
        world.set_commute(true).unwrap();
        let first = world.commute_departure().unwrap();
        world.advance_migrated_domains(first - arrival, &BTreeMap::new()).unwrap();
        let work_arrival = world.travel_plan().unwrap().arrival_minute();
        world.advance_migrated_domains(work_arrival - first, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some(PARIS));
        assert!(world.employment().unwrap().1);
        let shift = world.employment().unwrap().0.hours * MINUTES_PER_HOUR;
        world.advance_migrated_domains(shift, &BTreeMap::new()).unwrap();
        let return_arrival = world.travel_plan().unwrap().arrival_minute();
        world.advance_migrated_domains(return_arrival - work_arrival - shift, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some(ROUEN));
        assert_eq!(world.player_home(), home);
        world.move_player_home().unwrap();
        let day = world.clock().current_day() + 1;
        world.advance_migrated_domains(day * MINUTES_PER_DAY - return_arrival, &BTreeMap::new()).unwrap();
        let restored = resume(&bootstrap, &world);
        assert_eq!(restored.player_home(), ROUEN);
        assert_eq!(restored.population.unit_for_person(&player), Some("country_fra"));
        assert_eq!(restored.employment().unwrap().0.place, PARIS);
        assert_eq!(restored.player().polity_id, "state:british_isles_1900");
        assert!(restored.completed_firm_work("firm:opening_paris_workshop", day).unwrap()
            .iter().any(|work| work.worker == player));
    }

    #[test]
    fn yokohama_port_work_pays_a_visiting_worker_after_a_round_trip_and_restore() {
        const JOB: &str = "job:yokohama_port_handling";
        const PORT: &str = "water:empire_of_japan:yokohama";
        const MARKET: &str = "market:legacy_aggregate:empire_of_japan";
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("qing_empire").unwrap();
        let player = world.player().id.clone();
        let origin = world.player_home().to_owned();
        let city = world.transport().routing_node("place:yokohama").unwrap().to_owned();
        let japan_only = crate::formal_work::WorkOpening::load(|unit, place| {
            (unit == "empire_of_japan").then(|| world.transport().routing_node(place)).flatten().map(str::to_owned)
        }).unwrap();
        assert!(japan_only.entry_job(JOB).is_some());
        assert!(japan_only.entry_job("job:opening_paris_workshop").is_none());
        assert!(world.apply_for_work(JOB).is_err());
        let travel_to = |world: &mut InitialWorld, to: &str| {
            let arrival = world.preview_travel(to, ModeSet::ALL).unwrap().arrival_minute();
            world.depart_player().unwrap();
            world.advance_migrated_domains(arrival - world.clock.snapshot().total_minutes, &BTreeMap::new()).unwrap();
        };
        travel_to(&mut world, &city);
        assert!(world.transport_destinations().any(|place| place == PORT));
        assert!(world.apply_for_work(JOB).is_err());
        travel_to(&mut world, PORT);
        let price = world.macro_economy.markets()["empire_of_japan"].commodities["tea"].price_centimes;
        let receipts = world.ledger.market_cash(MARKET);
        world.buy_freight("tea", 100, price).unwrap();
        assert_eq!(world.ledger.market_cash(MARKET), receipts + (price + 9) / 10);
        world.consult_local_work(&player).unwrap();
        assert!(world.jobs().any(|(job, free)| job.id == JOB && free == 2));
        world.apply_for_work(JOB).unwrap();
        travel_to(&mut world, &city);
        assert!(world.book_work().is_err());
        world.set_commute(true).unwrap();
        let start = world.commute_departure().unwrap();
        world.advance_migrated_domains(start - world.clock.snapshot().total_minutes, &BTreeMap::new()).unwrap();
        let arrival = world.travel_plan().unwrap().arrival_minute();
        let mut world = resume(&bootstrap, &world);
        world.advance_migrated_domains(arrival - start, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some(PORT));
        assert!(world.employment().unwrap().1);
        world.advance_migrated_domains(4 * MINUTES_PER_HOUR, &BTreeMap::new()).unwrap();
        let back = world.travel_plan().unwrap().arrival_minute();
        world.advance_migrated_domains(back - world.clock.snapshot().total_minutes, &BTreeMap::new()).unwrap();
        assert_eq!(world.player_current_place(), Some(city.as_str()));
        let day = world.clock.current_day() + 1;
        let cash_before_wages = world.balance().unwrap().cash;
        world.advance_migrated_domains(day * MINUTES_PER_DAY - back, &BTreeMap::new()).unwrap();
        let restored = resume(&bootstrap, &world);
        let shifts = restored.completed_firm_work(MARKET, day).unwrap();
        let shift = shifts.iter().find(|record| record.worker == player).unwrap();
        assert_eq!((shift.job, shift.hours, shift.accrued_wages, shift.paid_wages, shift.unpaid_wages), (JOB, 4, 24, 24, 0));
        assert_eq!(restored.balance().unwrap().cash, cash_before_wages + 24);
        assert_eq!(restored.player_home(), origin);
        assert_eq!(restored.commute_base(), Some(city.as_str()));
        assert_eq!(restored.employment().unwrap().0.place, PORT);
    }

    #[test]
    fn global_population_transport_background_flow_survives_native_slot_and_lands_once() {
        use crate::formal_save::{native_slot_summary, read_native_slot, write_native_slot};
        let bootstrap = WorldBootstrap::load().unwrap();
        for polity in ["cshapes_gw_901", "khedivate_of_egypt", "argentina_1900", "united_states_1900"] {
            let world = bootstrap.create(polity).unwrap();
            assert!(world.opening_language().is_none());
            assert!(world.place_coordinates(world.player_home()).is_some());
            assert!(world.macro_economy().markets().contains_key(world.player_market_unit()));
            assert_eq!(world.player().opening_source_id, polity);
        }
        let mut world = bootstrap.create("cshapes_gw_901").unwrap();
        let mut reachable_openings = 0;
        let mut reachable_units = BTreeSet::new();
        for opening in bootstrap.opening_people.values() {
            if world.transport().coverage(&opening.place_id) == crate::transport::NodeCoverage::Connected {
                reachable_openings += 1;
                reachable_units.extend(world.population_unit_at(&opening.place_id));
            }
        }
        println!("formal_openings={} connected_openings={reachable_openings} connected_opening_regions={} population_regions={}",
            bootstrap.opening_people.len(), reachable_units.len(), world.population_units().len());
        let source = "mexican_republic";
        let destination = "united_states_1900";
        let initial_source = world.population_units()[source];
        let initial_destination = world.population_units()[destination];
        let members = 3;
        let origin_node = world.transport().area_node(source).unwrap();
        let access: Vec<_> = world.transport().segments().filter(|segment| segment.from == origin_node || segment.to == origin_node)
            .map(|segment| segment.id.clone()).collect();
        assert!(!access.is_empty());
        for segment in &access { world.close_transport_segment(segment, true).unwrap(); }
        let blocked = world.dispatch_background_migration(source, destination, members, 0).unwrap_err();
        println!("blocked_migration {source} -> {destination}: {blocked}");
        assert_eq!(world.population_units()[source], initial_source);
        for segment in &access { world.close_transport_segment(segment, false).unwrap(); }
        world.dispatch_background_migration(source, destination, members, 0).unwrap();
        assert!(world.dispatch_background_migration(source, destination, members, 0).is_err());
        assert_eq!(world.population_units()[source], initial_source);
        let arrival = world.background_migration(source).unwrap().arrival_minute;
        assert!(arrival > MINUTES_PER_DAY);
        world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();

        let slot = std::env::temp_dir().join(format!("wwo-global-transport-{}.json", std::process::id()));
        write_native_slot(&slot, &world).unwrap();
        let summary = native_slot_summary(&slot);
        let restored = read_native_slot(&slot, &bootstrap);
        std::fs::remove_file(&slot).unwrap();
        assert_eq!(summary.unwrap().opening, "cshapes_gw_901");
        let mut world = restored.unwrap();
        assert_eq!(world.background_migration(source).unwrap().members, members);
        world.advance_migrated_domains(arrival - MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert!(world.background_migration(source).is_none());
        assert_eq!(world.population_units()[source], initial_source - u64::from(members));
        assert_eq!(world.population_units()[destination], initial_destination + u64::from(members));
        world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert_eq!(world.population_units()[source], initial_source - u64::from(members));

        let before = 29 * MINUTES_PER_DAY;
        world.advance_migrated_domains(before - world.clock().snapshot().total_minutes, &BTreeMap::new()).unwrap();
        assert!(world.population_units().keys().all(|unit| world.background_migration(unit).is_none()));
        let totals_before = world.population_units().clone();
        world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        let batches = world.population_units().keys().filter(|unit| world.background_migration(unit).is_some()).count();
        assert!(batches > 0);
        assert_eq!(world.population_units(), &totals_before);
        let first = world.population_units().keys().filter_map(|unit| world.background_migration(unit))
            .min_by_key(|batch| batch.arrival_minute).unwrap();
        println!("monthly_migration day=30 batches={batches} first={} -> {} members={} arrival_minute={}",
            first.source, first.destination, first.members, first.arrival_minute);
        let arrived_origin = first.source.to_owned();
        let arrival_minute = first.arrival_minute;
        world.advance_migrated_domains(arrival_minute - 30 * MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert!(world.background_migration(&arrived_origin).is_none());
        assert_eq!(world.population_units().values().sum::<u64>(), totals_before.values().sum::<u64>());
    }

    #[test]
    fn global_population_transport_named_opening_travels_across_north_america() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("united_states_1900").unwrap();
        let traveler = world.player().id.clone();
        let destination = world.transport().capital_node("mexican_republic").unwrap().to_owned();
        let plan = world.preview_travel(&destination, ModeSet::ALL).unwrap();
        let arrival = plan.arrival_minute();
        let first_stop = plan.route().legs[0].to.clone();
        let first_stop_minute = plan.first_departure_minute() + i64::from(plan.route().legs[0].profile.travel_minutes);
        assert!(arrival > MINUTES_PER_DAY);
        world.depart_player().unwrap();
        world.advance_migrated_domains(first_stop_minute, &BTreeMap::new()).unwrap();
        assert_eq!(world.last_station(), first_stop);
        assert_eq!(world.current_place(&traveler), None);
        let mut world = resume(&bootstrap, &world);
        assert_eq!(world.last_station(), first_stop);
        world.advance_migrated_domains(arrival - first_stop_minute, &BTreeMap::new()).unwrap();
        assert_eq!(world.current_place(&traveler), Some(destination.as_str()));
        assert_eq!(world.market_unit_for_person(&traveler), Some("mexican_republic"));
        assert_eq!(world.population.unit_for_person(&traveler), Some("united_states_1900"));
        world.move_player_home().unwrap();
        let world = resume(&bootstrap, &world);
        assert_eq!(world.person_home(&traveler), Some(destination.as_str()));
        assert_eq!(world.population.unit_for_person(&traveler), Some("mexican_republic"));
    }

    #[test]
    fn transport_legacy_native_ticket_arrives_without_new_charge() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let player = world.player().id.clone();
        let cash = world.balance().unwrap().cash;
        let rail = "rail_paris_rouen";
        let arrival = world.transport().segment(rail).unwrap().profile.travel_minutes;
        let mut save = world.snapshot();
        save.as_object_mut().unwrap().remove("transport");
        save["travel"] = serde_json::json!({
            "journeys": { player: {
                "route_id": rail, "origin": PARIS, "destination": ROUEN,
                "departure_minute": 0, "arrival_minute": arrival
            }},
            "last_arrivals": {},
            "departures": { rail: { "day": 0, "count": 1 } }
        });
        let restored = bootstrap.restore_native(serde_json::from_value(save).unwrap()).unwrap();
        assert!(restored.passenger_in_transit());
        let mut restored = resume(&bootstrap, &restored);
        restored.advance_migrated_domains(i64::from(arrival), &BTreeMap::new()).unwrap();
        assert_eq!(restored.player_current_place(), Some(ROUEN));
        assert_eq!(restored.balance().unwrap().cash, cash);
    }
}
