//! Decode and validate the one-leg travel snapshot written before shared reservations.
use crate::{
    formal_bootstrap::WorldSources,
    formal_clock::{GameClock, MINUTES_PER_DAY},
    transport::{TransportMode, TransportNetwork, TransportSegment},
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Eq, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Journey {
    pub route_id: String,
    pub origin: String,
    pub destination: String,
    pub departure_minute: i64,
    pub arrival_minute: i64,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct LegacyTravel {
    pub(crate) journeys: BTreeMap<String, Journey>,
    pub(crate) last_arrivals: BTreeMap<String, Journey>,
    departures: BTreeMap<String, Departures>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Departures {
    day: i64,
    /// Committed load in both directions on the same physical segment.
    count: u32,
}

impl LegacyTravel {
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
                let (origin, earliest_departure) = self.last_arrivals.get(person)
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
