use crate::{
    formal_bootstrap::{Route, RouteMode, WorldSources},
    formal_clock::{GameClock, MINUTES_PER_DAY, MINUTES_PER_HOUR},
    formal_save::invalid,
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
    pub remaining_departures: u32,
    pub daily_capacity: u32,
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

    pub(crate) fn options<'a>(&self, sources: &'a WorldSources, current_place: &str, clock: GameClock) -> Vec<TravelOption<'a>> {
        sources.routes().values().filter_map(|route| {
            self.option(sources, route, current_place, clock)
        }).collect()
    }

    pub(crate) fn depart(
        &mut self,
        sources: &WorldSources,
        person: &str,
        opening_place: &str,
        route_id: &str,
        destination: &str,
        clock: GameClock,
    ) -> io::Result<()> {
        let current_place = self.current_place(person, opening_place)
            .ok_or_else(|| invalid("人物已在旅途中。"))?;
        let option = sources.routes().get(route_id)
            .and_then(|route| self.option(sources, route, current_place, clock))
            .filter(|option| option.destination == destination)
            .ok_or_else(|| invalid("该地点没有通往此目的地的模拟路线。"))?;
        if option.remaining_departures == 0 {
            return Err(invalid("该线路今日的模拟出发名额已用完。"));
        }
        let journey = Journey {
            route_id: option.route.id.clone(),
            origin: current_place.to_owned(),
            destination: option.destination.to_owned(),
            departure_minute: option.departure_minute,
            arrival_minute: option.arrival_minute,
        };
        let day = clock.current_day();
        let count = option.daily_capacity - option.remaining_departures + 1;
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
            if !valid_leg(sources, leg) || !(0..=minute).contains(&leg.departure_minute)
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
            sources.routes().get(route_id).and_then(|route| prototype_terms(sources, route))
                .is_some_and(|(_, limit)| (0..=clock.current_day()).contains(&usage.day)
                    && (1..=limit).contains(&usage.count)
                    && usage.count >= known_departures.get(route_id.as_str()).copied().unwrap_or(0))
        })
    }

    fn option<'a>(&self, sources: &'a WorldSources, route: &'a Route, current_place: &str, clock: GameClock) -> Option<TravelOption<'a>> {
        let destination = other_end(route, current_place)?;
        let (duration, daily_capacity) = prototype_terms(sources, route)?;
        let departure_minute = clock.snapshot().total_minutes;
        let used = self.departures.get(&route.id).filter(|usage| usage.day == clock.current_day());
        Some(TravelOption {
            route,
            destination,
            departure_minute,
            arrival_minute: departure_minute.checked_add(duration)?,
            remaining_departures: daily_capacity - used.map_or(0, |usage| usage.count),
            daily_capacity,
        })
    }
}

fn other_end<'a>(route: &'a Route, origin: &str) -> Option<&'a str> {
    if origin == route.from_place_id {
        Some(&route.to_place_id)
    } else if origin == route.to_place_id {
        Some(&route.from_place_id)
    } else {
        None
    }
}

fn valid_leg(sources: &WorldSources, leg: &Journey) -> bool {
    let Some(route) = sources.routes().get(&leg.route_id) else { return false };
    other_end(route, &leg.origin) == Some(leg.destination.as_str())
        && prototype_terms(sources, route).is_some_and(|(duration, _)| {
            leg.departure_minute.checked_add(duration) == Some(leg.arrival_minute)
        })
}

// The opening route geometries have no passenger service records. This model
// allows immediate, bidirectional movement on domestic French land links.
// Speed and daily departure budgets are simulation inputs. The route budget is
// shared across directions. Fares, timetables, and shared freight are unmodeled.
fn prototype_terms(sources: &WorldSources, route: &Route) -> Option<(i64, u32)> {
    let (speed_kmh, daily_capacity) = match route.mode {
        RouteMode::Road => (5.0, 4),
        RouteMode::Rail => (40.0, 12),
        RouteMode::Shipping => return None,
    };
    let origin = sources.places().get(&route.from_place_id)?;
    let destination = sources.places().get(&route.to_place_id)?;
    if origin.parent_country_id != "country_fra" || destination.parent_country_id != "country_fra" {
        return None;
    }
    let [lon, lat] = origin.lon_lat?.map(f64::to_radians);
    let [other_lon, other_lat] = destination.lon_lat?.map(f64::to_radians);
    let haversine = ((other_lat - lat) / 2.0).sin().powi(2)
        + lat.cos() * other_lat.cos() * ((other_lon - lon) / 2.0).sin().powi(2);
    let kilometers = 2.0 * 6371.0088 * haversine.clamp(0.0, 1.0).sqrt().asin();
    let minutes = (kilometers / speed_kmh * MINUTES_PER_HOUR as f64).ceil() as i64;
    (minutes > 0).then_some((minutes, daily_capacity))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::formal_bootstrap::WorldBootstrap;

    const PARIS: &str = "place:paris";
    const ROUEN: &str = "place:rouen";
    const RAIL: &str = "rail_paris_rouen";
    const ROAD: &str = "road_rouen_paris";
    const PERSON: &str = "person:test";

    #[test]
    fn saved_journey_excludes_presence_until_arrival_and_allows_return() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let sources = bootstrap.sources();
        let mut clock = GameClock::default();
        let mut travel = TravelState::default();
        assert_eq!(travel.current_place(PERSON, PARIS), Some(PARIS));
        assert!(travel.depart(sources, PERSON, PARIS, RAIL, "place:le_havre", clock).is_err());
        travel.depart(sources, PERSON, PARIS, RAIL, ROUEN, clock).unwrap();
        assert_eq!(travel.current_place(PERSON, PARIS), None);
        assert!(travel.depart(sources, PERSON, PARIS, RAIL, ROUEN, clock).is_err());

        let saved = serde_json::to_string(&travel).unwrap();
        let mut restored: TravelState = serde_json::from_str(&saved).unwrap();
        let opening = |person: &str| (person == PERSON).then_some(PARIS);
        assert!(restored.validate(sources, clock, opening));
        let eta = restored.next_arrival().unwrap();
        clock.advance_minutes(eta - 1).unwrap();
        restored.arrive(clock);
        assert_eq!(restored.current_place(PERSON, PARIS), None);
        clock.advance_minutes(1).unwrap();
        assert!(!restored.validate(sources, clock, opening));
        restored.arrive(clock);
        assert_eq!(restored.current_place(PERSON, PARIS), Some(ROUEN));
        assert_eq!(restored.next_arrival(), None);
        assert!(restored.validate(sources, clock, opening));
        restored.depart(sources, PERSON, PARIS, RAIL, PARIS, clock).unwrap();
        assert!(restored.validate(sources, clock, opening));
        assert_eq!(restored.journey(PERSON).unwrap().origin, ROUEN);
    }

    #[test]
    fn departure_capacity_is_shared_by_direction_and_survives_restore() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let sources = bootstrap.sources();
        let mut clock = GameClock::default();
        let mut travel = TravelState::default();
        for index in 0..4 {
            let (origin, destination) = if index % 2 == 0 { (PARIS, ROUEN) } else { (ROUEN, PARIS) };
            travel.depart(sources, &format!("person:{index}"), origin, ROAD, destination, clock).unwrap();
        }
        let saved = serde_json::to_string(&travel).unwrap();
        let mut restored: TravelState = serde_json::from_str(&saved).unwrap();
        let opening = |person: &str| match person {
            "person:0" | "person:2" => Some(PARIS),
            "person:1" | "person:3" => Some(ROUEN),
            _ => None,
        };
        assert!(restored.validate(sources, clock, opening));
        assert!(restored.depart(sources, PERSON, PARIS, ROAD, ROUEN, clock).is_err());
        clock.advance_minutes(MINUTES_PER_DAY).unwrap();
        restored.arrive(clock);
        restored.depart(sources, PERSON, PARIS, ROAD, ROUEN, clock).unwrap();
        assert!(restored.validate(sources, clock, |person| opening(person).or_else(|| (person == PERSON).then_some(PARIS))));
    }

    #[test]
    fn prototype_terms_use_domestic_routes_only() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let sources = bootstrap.sources();
        let clock = GameClock::default();
        let travel = TravelState::default();
        let options = travel.options(sources, PARIS, clock);
        let road = options.iter().find(|option| option.route.id == ROAD).unwrap();
        let rail = options.iter().find(|option| option.route.id == RAIL).unwrap();
        assert!(rail.arrival_minute < road.arrival_minute);
        assert_eq!(road.destination, ROUEN);
        assert_eq!(rail.destination, ROUEN);
        assert!(travel.options(sources, "place:port_le_havre", clock).is_empty());
        assert!(travel.options(sources, "place:strasbourg", clock).is_empty());
    }
}
