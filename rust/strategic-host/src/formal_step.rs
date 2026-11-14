use crate::formal_clock::{GameClock, MINUTES_PER_DAY, MINUTES_PER_HOUR};
use std::io;

/// Application of an ordered boundary phase belongs to the domain that owns its state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Phase {
    SpatialToHour(i64),
    TravelArrivals,
    Wages,
    NativeAdvance,
    NativeSettleDay,
    NativeDispatch,
    TravelNotices,
    Consumption,
    MacroHours { from: i64, through: i64 },
    Livelihood,
    ProposeNativeResidences,
    Residence,
    NativeScopes,
    OrganizationReview(i64),
    CharacterDay,
}

#[derive(Default)]
pub struct Boundaries {
    pub consumption: Option<i64>,
    pub livelihood: Option<i64>,
    pub transport: Option<i64>,
    pub travel: Option<i64>,
}

#[derive(Clone, Copy)]
pub struct NativeDay {
    pub day: i64,
    pub processing: bool,
}

/// Implementations must own the effects of every phase. This adapter is kept apart from saved views.
pub trait WorldDomains {
    fn native_day(&self) -> Option<NativeDay>;
    fn has_travel(&self) -> bool;
    fn boundaries(&self) -> Boundaries;
    fn apply(&mut self, phase: Phase, clock: GameClock) -> io::Result<()>;
}

pub(crate) fn next_day_boundary(clock: GameClock) -> Option<i64> {
    (clock.current_day() + 1).checked_mul(MINUTES_PER_DAY)
}

pub fn advance(clock: &mut GameClock, domains: &mut impl WorldDomains, minutes: i64) -> io::Result<()> {
    let mut target = *clock;
    target.advance_minutes(minutes)?;
    if minutes == 0 { return Ok(()); }
    let native = domains.native_day();
    if native.is_some_and(|state| state.processing || state.day != clock.current_day()) {
        return Err(io::Error::other("native day does not match the formal clock"));
    }
    let travel = domains.has_travel();
    let mut settled_hour = clock.current_hour();
    let target = target.snapshot().total_minutes;

    loop {
        let next_day = next_day_boundary(*clock);
        let due = domains.boundaries();
        let next = [next_day, due.consumption, due.livelihood, due.transport, due.travel]
            .into_iter().flatten().min();
        let Some(boundary) = next.filter(|minute| *minute <= target) else { break; };
        let current = clock.snapshot().total_minutes;
        if boundary < current { return Err(io::Error::other("formal boundary precedes the clock")); }
        clock.advance_minutes(boundary - current)?;
        let hour = boundary / MINUTES_PER_HOUR;
        let day_changed = Some(boundary) == next_day;

        if hour > settled_hour { domains.apply(Phase::SpatialToHour(hour), *clock)?; }
        if travel { domains.apply(Phase::TravelArrivals, *clock)?; }
        domains.apply(Phase::Wages, *clock)?;
        if native.is_some() {
            domains.apply(Phase::NativeAdvance, *clock)?;
            if day_changed { domains.apply(Phase::NativeSettleDay, *clock)?; }
            if Some(boundary) == due.transport { domains.apply(Phase::NativeDispatch, *clock)?; }
        }
        if travel { domains.apply(Phase::TravelNotices, *clock)?; }
        domains.apply(Phase::Consumption, *clock)?;
        if hour > settled_hour { domains.apply(Phase::MacroHours { from: settled_hour, through: hour }, *clock)?; }
        domains.apply(Phase::Livelihood, *clock)?;
        if day_changed {
            if native.is_some() { domains.apply(Phase::ProposeNativeResidences, *clock)?; }
            domains.apply(Phase::Residence, *clock)?;
            if native.is_some() { domains.apply(Phase::NativeScopes, *clock)?; }
            domains.apply(Phase::OrganizationReview(hour), *clock)?;
            domains.apply(Phase::CharacterDay, *clock)?;
        }
        settled_hour = hour;
    }

    clock.advance_minutes(target - clock.snapshot().total_minutes)?;
    let hour = clock.current_hour();
    if hour > settled_hour {
        domains.apply(Phase::SpatialToHour(hour), *clock)?;
        domains.apply(Phase::MacroHours { from: settled_hour, through: hour }, *clock)?;
    }
    if native.is_some() { domains.apply(Phase::NativeAdvance, *clock)?; }
    domains.apply(Phase::Wages, *clock)
}

#[cfg(test)]
mod tests {
    use super::*;
    use Phase::*;

    #[derive(Default)]
    struct Recorded {
        day: i64,
        due: Option<i64>,
        phases: Vec<(Phase, i64)>,
    }

    impl WorldDomains for Recorded {
        fn native_day(&self) -> Option<NativeDay> { Some(NativeDay { day: self.day, processing: false }) }
        fn has_travel(&self) -> bool { true }
        fn boundaries(&self) -> Boundaries {
            Boundaries { consumption: self.due, livelihood: self.due, transport: self.due, travel: self.due }
        }
        fn apply(&mut self, phase: Phase, clock: GameClock) -> io::Result<()> {
            self.phases.push((phase, clock.snapshot().total_minutes));
            if phase == NativeSettleDay { self.day += 1; }
            if phase == Livelihood { self.due = None; }
            Ok(())
        }
    }

    #[test]
    fn simultaneous_day_and_domain_events_follow_r68_order() {
        let mut clock = GameClock::default();
        let mut domains = Recorded { due: Some(1440), ..Recorded::default() };
        advance(&mut clock, &mut domains, 1500).unwrap();
        assert_eq!(domains.phases, [
            (SpatialToHour(24), 1440), (TravelArrivals, 1440), (Wages, 1440),
            (NativeAdvance, 1440), (NativeSettleDay, 1440), (NativeDispatch, 1440),
            (TravelNotices, 1440), (Consumption, 1440), (MacroHours { from: 0, through: 24 }, 1440),
            (Livelihood, 1440), (ProposeNativeResidences, 1440), (Residence, 1440),
            (NativeScopes, 1440), (OrganizationReview(24), 1440), (CharacterDay, 1440),
            (SpatialToHour(25), 1500), (MacroHours { from: 24, through: 25 }, 1500),
            (NativeAdvance, 1500), (Wages, 1500),
        ]);
        assert_eq!(clock.snapshot().total_minutes, 1500);
    }

    #[test]
    fn rejects_a_mismatched_native_day_before_advancing() {
        let mut clock = GameClock::default();
        let mut domains = Recorded { day: 1, ..Recorded::default() };
        assert!(advance(&mut clock, &mut domains, 60).is_err());
        assert_eq!(clock, GameClock::default());
        assert!(domains.phases.is_empty());
    }
}
