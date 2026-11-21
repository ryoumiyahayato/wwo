use crate::{
    formal_bootstrap::{Route, WorldSources},
    formal_clock::{GameClock, MINUTES_PER_DAY},
    formal_save::invalid,
    transport::{TransportMode, TransportNetwork, TransportSegment},
};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io};

#[derive(Clone, Debug, Eq, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Journey {
    pub route_id: String,
    pub origin: String,
    pub destination: String,
    pub departure_minute: i64,
    pub arrival_minute: i64,
}

pub struct TravelOption<'a> {
    pub route: &'a Route,
    pub destination: &'a str,
    pub departure_minute: i64,
    pub arrival_minute: i64,
    /// Remaining shared load for today's departures. One traveler uses one unit.
    pub remaining_departures: u32,
    pub daily_capacity: u32,
    /// Abstract cost from the prototype network.
    pub cost_units: u32,
    pub open: bool,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct TravelState {
    journeys: BTreeMap<String, Journey>,
    last_arrivals: BTreeMap<String, Journey>,
    departures: BTreeMap<String, Departures>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Departures {
    day: i64,
    /// Committed load in both directions on the same physical segment.
    count: u32,
}

impl TravelState {
    pub(crate) fn current_place<'a>(&'a self, person: &str, opening_place: &'a str) -> Option<&'a str> {
        if self.journey(person).is_some() {
            return None;
        }
        Some(self.last_arrival(person).map_or(opening_place, |leg| leg.destination.as_str()))
    }

    pub(crate) fn journey(&self, person: &str) -> Option<&Journey> {
        self.journeys.get(person)
    }

    pub(crate) fn last_arrival(&self, person: &str) -> Option<&Journey> {
        self.last_arrivals.get(person)
    }

    pub(crate) fn options<'a>(
        &self,
        sources: &'a WorldSources,
        network: &'a TransportNetwork,
        current_place: &str,
        clock: GameClock,
    ) -> Vec<TravelOption<'a>> {
        sources.routes().values().filter_map(|route| {
            self.option(sources, network, route, current_place, clock)
        }).collect()
    }

    pub(crate) fn depart(
        &mut self,
        sources: &WorldSources,
        network: &TransportNetwork,
        person: &str,
        opening_place: &str,
        route_id: &str,
        destination: &str,
        clock: GameClock,
    ) -> io::Result<()> {
        let current_place = self.current_place(person, opening_place)
            .ok_or_else(|| invalid("人物已在旅途中。"))?;
        let option = sources.routes().get(route_id)
            .and_then(|route| self.option(sources, network, route, current_place, clock))
            .filter(|option| option.destination == destination)
            .ok_or_else(|| invalid("该地点没有通往此目的地的模拟路线。"))?;
        if !option.open {
            return Err(invalid("该线路目前中断。"));
        }
        if option.remaining_departures == 0 {
            return Err(invalid("该线路今日的模拟运力已用完。"));
        }
        let journey = Journey {
            route_id: option.route.id.clone(),
            origin: current_place.to_owned(),
            destination: option.destination.to_owned(),
            departure_minute: option.departure_minute,
            arrival_minute: option.arrival_minute,
        };
        let day = clock.current_day();
        let count = self.used_capacity(route_id, day) + 1;
        self.departures.insert(route_id.to_owned(), Departures { day, count });
        self.journeys.insert(person.to_owned(), journey);
        Ok(())
    }

    pub(crate) fn next_arrival(&self) -> Option<i64> {
        self.journeys.values().map(|leg| leg.arrival_minute).min()
    }

    pub(crate) fn arrive(&mut self, clock: GameClock) {
        let minute = clock.snapshot().total_minutes;
        if self.next_arrival().is_none_or(|arrival| arrival > minute) {
            return;
        }
        for (person, leg) in std::mem::take(&mut self.journeys) {
            if leg.arrival_minute <= minute {
                self.last_arrivals.insert(person, leg);
            } else {
                self.journeys.insert(person, leg);
            }
        }
    }

    pub(crate) fn record_death(&mut self, person: &str) {
        self.journeys.remove(person);
        self.last_arrivals.remove(person);
    }

    pub(crate) fn validate<'a>(
        &self,
        sources: &WorldSources,
        network: &TransportNetwork,
        clock: GameClock,
        opening_place: impl Fn(&str) -> Option<&'a str>,
    ) -> bool {
        let minute = clock.snapshot().total_minutes;
        let mut known_departures = BTreeMap::new();
        let legs = self.last_arrivals.iter().map(|(person, leg)| (person, leg, false))
            .chain(self.journeys.iter().map(|(person, leg)| (person, leg, true)));
        for (person, leg, active) in legs {
            let Some(opening) = opening_place(person).filter(|place| sources.places().contains_key(*place)) else {
                return false;
            };
            if !valid_leg(sources, network, leg) || !(0..=minute).contains(&leg.departure_minute)
                || active != (leg.arrival_minute > minute)
            {
                return false;
            }
            if active {
                let (origin, earliest_departure) = self.last_arrival(person)
                    .map_or((opening, 0), |arrival| (arrival.destination.as_str(), arrival.arrival_minute));
                if leg.origin != origin || leg.departure_minute < earliest_departure {
                    return false;
                }
            }
            let day = leg.departure_minute / MINUTES_PER_DAY;
            let Some(usage) = self.departures.get(&leg.route_id).filter(|usage| usage.day >= day) else {
                return false;
            };
            if day == usage.day {
                *known_departures.entry(leg.route_id.as_str()).or_insert(0) += 1;
            }
        }
        self.departures.iter().all(|(route_id, usage)| {
            travel_segment(sources, network, route_id)
                .is_some_and(|segment| (0..=clock.current_day()).contains(&usage.day)
                    && (1..=segment.profile.capacity_units).contains(&usage.count)
                    && usage.count >= known_departures.get(route_id.as_str()).copied().unwrap_or(0))
        })
    }

    fn option<'a>(
        &self,
        sources: &WorldSources,
        network: &'a TransportNetwork,
        route: &'a Route,
        current_place: &str,
        clock: GameClock,
    ) -> Option<TravelOption<'a>> {
        let segment = travel_segment(sources, network, &route.id)?;
        let destination = other_end(segment, current_place)?;
        let availability = network.availability(&route.id)?;
        let departure_minute = clock.snapshot().total_minutes;
        let remaining_departures = if availability.open {
            availability.capacity_units.saturating_sub(self.used_capacity(&route.id, clock.current_day()))
        } else { 0 };
        Some(TravelOption {
            route,
            destination,
            departure_minute,
            arrival_minute: departure_minute.checked_add(i64::from(segment.profile.travel_minutes))?,
            remaining_departures,
            daily_capacity: segment.profile.capacity_units,
            cost_units: segment.profile.cost_units,
            open: availability.open,
        })
    }

    fn used_capacity(&self, segment: &str, day: i64) -> u32 {
        self.departures.get(segment).filter(|usage| usage.day == day).map_or(0, |usage| usage.count)
    }
}

fn other_end<'a>(segment: &'a TransportSegment, origin: &str) -> Option<&'a str> {
    if origin == segment.from {
        Some(&segment.to)
    } else if segment.bidirectional && origin == segment.to {
        Some(&segment.from)
    } else {
        None
    }
}

fn valid_leg(sources: &WorldSources, network: &TransportNetwork, leg: &Journey) -> bool {
    travel_segment(sources, network, &leg.route_id).is_some_and(|segment| {
        other_end(segment, &leg.origin) == Some(leg.destination.as_str())
            && leg.departure_minute.checked_add(i64::from(segment.profile.travel_minutes)) == Some(leg.arrival_minute)
    })
}

fn travel_segment<'a>(sources: &WorldSources, network: &'a TransportNetwork, id: &str) -> Option<&'a TransportSegment> {
    let segment = network.segment(id)?;
    let domestic_land = matches!(segment.mode, TransportMode::Road | TransportMode::Rail)
        && [&segment.from, &segment.to].into_iter().all(|id| {
            sources.places().get(id).is_some_and(|place| place.parent_country_id == "country_fra")
        });
    (domestic_land && segment.profile.travel_minutes > 0).then_some(segment)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{formal_bootstrap::WorldBootstrap, transport::map_data::load_prototype_map_network};

    const PARIS: &str = "place:paris";
    const ROUEN: &str = "place:rouen";
    const RAIL: &str = "rail_paris_rouen";
    const ROAD: &str = "road_rouen_paris";
    const PERSON: &str = "person:test";

    #[test]
    fn saved_journey_excludes_presence_until_arrival_and_allows_return() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let sources = bootstrap.sources();
        let world = bootstrap.create("country_fra").unwrap();
        let network = world.transport();
        let mut clock = GameClock::default();
        let mut travel = TravelState::default();
        assert_eq!(travel.current_place(PERSON, PARIS), Some(PARIS));
        assert!(travel.depart(sources, network, PERSON, PARIS, RAIL, "place:le_havre", clock).is_err());
        travel.depart(sources, network, PERSON, PARIS, RAIL, ROUEN, clock).unwrap();
        assert_eq!(travel.current_place(PERSON, PARIS), None);
        assert!(travel.depart(sources, network, PERSON, PARIS, RAIL, ROUEN, clock).is_err());

        let saved = serde_json::to_string(&travel).unwrap();
        let mut restored: TravelState = serde_json::from_str(&saved).unwrap();
        let opening = |person: &str| (person == PERSON).then_some(PARIS);
        assert!(restored.validate(sources, network, clock, opening));
        let eta = restored.next_arrival().unwrap();
        clock.advance_minutes(eta - 1).unwrap();
        restored.arrive(clock);
        assert_eq!(restored.current_place(PERSON, PARIS), None);
        clock.advance_minutes(1).unwrap();
        assert!(!restored.validate(sources, network, clock, opening));
        restored.arrive(clock);
        assert_eq!(restored.current_place(PERSON, PARIS), Some(ROUEN));
        assert_eq!(restored.next_arrival(), None);
        assert!(restored.validate(sources, network, clock, opening));
        restored.depart(sources, network, PERSON, PARIS, RAIL, PARIS, clock).unwrap();
        assert!(restored.validate(sources, network, clock, opening));
        assert_eq!(restored.journey(PERSON).unwrap().origin, ROUEN);
    }

    #[test]
    fn departure_capacity_is_shared_by_direction_and_survives_restore() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let sources = bootstrap.sources();
        let world = bootstrap.create("country_fra").unwrap();
        let network = world.transport();
        let capacity = network.segment(ROAD).unwrap().profile.capacity_units;
        let mut clock = GameClock::default();
        let mut travel = TravelState::default();
        for index in 0..capacity {
            let (origin, destination) = if index % 2 == 0 { (PARIS, ROUEN) } else { (ROUEN, PARIS) };
            travel.depart(sources, network, &format!("person:{index}"), origin, ROAD, destination, clock).unwrap();
        }
        let saved = serde_json::to_string(&travel).unwrap();
        let mut restored: TravelState = serde_json::from_str(&saved).unwrap();
        let opening = |person: &str| {
            let index: u32 = person.strip_prefix("person:")?.parse().ok()?;
            (index < capacity).then_some(if index % 2 == 0 { PARIS } else { ROUEN })
        };
        assert!(restored.validate(sources, network, clock, opening));
        assert!(restored.depart(sources, network, PERSON, PARIS, ROAD, ROUEN, clock).is_err());
        clock.advance_minutes(MINUTES_PER_DAY).unwrap();
        restored.arrive(clock);
        restored.depart(sources, network, PERSON, PARIS, ROAD, ROUEN, clock).unwrap();
        assert!(restored.validate(sources, network, clock, |person| opening(person).or_else(|| (person == PERSON).then_some(PARIS))));
    }

    #[test]
    fn prototype_options_use_network_terms_on_domestic_routes_only() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let sources = bootstrap.sources();
        let world = bootstrap.create("country_fra").unwrap();
        let network = world.transport();
        let clock = GameClock::default();
        let travel = TravelState::default();
        let options = travel.options(sources, network, PARIS, clock);
        let road = options.iter().find(|option| option.route.id == ROAD).unwrap();
        let rail = options.iter().find(|option| option.route.id == RAIL).unwrap();
        let profile = network.segment(ROAD).unwrap().profile;
        assert_eq!(road.arrival_minute - road.departure_minute, i64::from(profile.travel_minutes));
        assert_eq!(road.cost_units, profile.cost_units);
        assert_eq!(road.daily_capacity, profile.capacity_units);
        assert!(rail.arrival_minute < road.arrival_minute);
        assert_eq!(road.destination, ROUEN);
        assert_eq!(rail.destination, ROUEN);
        assert!(travel.options(sources, network, "place:port_le_havre", clock).is_empty());
        assert!(travel.options(sources, network, "place:strasbourg", clock).is_empty());
    }

    #[test]
    fn network_closure_blocks_departure_and_preserves_the_departed_journey() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let sources = bootstrap.sources();
        let mut network = load_prototype_map_network(sources, 0).unwrap();
        let clock = GameClock::default();
        let mut travel = TravelState::default();
        travel.depart(sources, &network, PERSON, PARIS, ROAD, ROUEN, clock).unwrap();

        network.set_availability(ROAD, false, 1).unwrap();
        let options = travel.options(sources, &network, ROUEN, clock);
        let road = options.iter().find(|option| option.route.id == ROAD).unwrap();
        assert!(!road.open);
        assert_eq!(road.remaining_departures, 0);
        let blocked = travel.depart(sources, &network, "person:return", ROUEN, ROAD, PARIS, clock).unwrap_err();
        assert_eq!(blocked.to_string(), "该线路目前中断。");
        assert!(travel.validate(sources, &network, clock, |_| Some(PARIS)));

        network.set_availability(ROAD, true, 1).unwrap();
        assert!(travel.depart(sources, &network, "person:return", ROUEN, ROAD, PARIS, clock).is_err());
        network.set_availability(ROAD, true, 2).unwrap();
        travel.depart(sources, &network, "person:return", ROUEN, ROAD, PARIS, clock).unwrap();
        assert_eq!(travel.used_capacity(ROAD, clock.current_day()), 2);
    }
}
