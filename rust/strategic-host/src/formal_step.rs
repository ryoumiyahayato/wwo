//! The active world's time boundaries and cross-domain settlement order.
use super::{formal_character, invalid, GameClock, InitialWorld, PersonalActivity, MINUTES_PER_DAY};
use crate::formal_character::DayActivity;
use std::{collections::BTreeMap, io};

fn next_day_boundary(clock: GameClock) -> Option<i64> {
    (clock.current_day() + 1).checked_mul(MINUTES_PER_DAY)
}

impl InitialWorld {
    pub fn advance_migrated_domains(
        &mut self,
        minutes: i64,
        managed_population: &BTreeMap<String, u64>,
    ) -> io::Result<()> {
        let mut target = self.clock;
        target.advance_minutes(minutes)?;
        self.advance_migrated_domains_to(target, managed_population)
    }

    pub(super) fn advance_migrated_domains_to(
        &mut self,
        target: GameClock,
        managed_population: &BTreeMap<String, u64>,
    ) -> io::Result<()> {
        u32::try_from(target.current_day()).map_err(|_| invalid("unsupported formal character date"))?;
        if target.current_day() != self.clock.current_day() {
            self.macro_economy.check_responsibility(self.population.totals(), &self.managed_residents(managed_population)?)?;
        }
        let through = target.snapshot().total_minutes;
        while self.clock.snapshot().total_minutes != through {
            let day_boundary = next_day_boundary(self.clock);
            let minute = self.next_travel_event().into_iter().chain(day_boundary)
                .min().map_or(through, |event| event.min(through));
            let mut boundary = self.clock;
            boundary.advance_minutes(minute - boundary.snapshot().total_minutes)?;
            if minute != self.clock.snapshot().total_minutes {
                boundary = boundary.minute_boundary();
            }
            if Some(minute) != day_boundary {
                self.clock = boundary;
                self.transport.advance(minute);
                self.settle_transport_arrivals(minute)?;
                self.advance_commute(minute);
                continue;
            }
            self.settle_day(boundary, managed_population)?;
        }
        self.clock = target;
        Ok(())
    }

    fn settle_day(&mut self, boundary: GameClock, managed_population: &BTreeMap<String, u64>) -> io::Result<()> {
        let minute = boundary.snapshot().total_minutes;
        let day = u32::try_from(boundary.current_day()).map_err(|_| invalid("unsupported formal character date"))?;
        #[cfg(test)]
        let mut measure = day_measurement::start();
        let work = self.work.booked_workers().map(|person| {
            let job = self.work.contract(&self.work_opening, person).expect("booking has a live contract");
            (person.clone(), job.id.clone())
        }).collect::<BTreeMap<_, _>>();
        let period = self.activities.work_injury_interval;
        let injury = (self.opening_language().is_some() && work.contains_key(&self.player)
            && day.wrapping_mul(17).wrapping_add(9) % period == 0)
            .then_some((self.activities.work_injury_damage, self.activities.work_injury_permanent_loss));
        let booking = self.scheduled_activity();
        let lesson = if booking == Some(PersonalActivity::Lesson) {
            self.opening_language().map(|language| (language, self.activities.lesson_effort,
                format!("reading-room:{}:{day}", self.player().place_id)))
        } else { None };
        for worker in self.work.booked_workers() {
            let job = self.work.contract(&self.work_opening, worker).expect("booking has a live contract");
            self.wages.record_shift(worker, job, i64::from(day), &self.ledger)?;
        }
        self.wages.settle_due(&mut self.ledger, boundary, |_| false)?;
        #[cfg(test)]
        day_measurement::mark(&mut measure, 0);
        self.enterprises.settle(&self.enterprise_opening, &self.wages, i64::from(day));
        self.settle_counter_orders(boundary)?;
        self.settle_organization_activity(boundary)?;
        #[cfg(test)]
        day_measurement::mark(&mut measure, 1);
        let (mut nutrition_by_person, settled_meal_purchases) =
            self.settle_named_livelihood(day, minute, self.activities.meal_milli_for_recovery);
        #[cfg(test)]
        day_measurement::mark(&mut measure, 2);
        if self.player_day.food_milli > 0 {
            nutrition_by_person.insert(self.player.clone(), 1000);
        }
        let activity = DayActivity {
            work, lesson, injury,
            rest: booking == Some(PersonalActivity::Rest),
            nutrition: None,
            nutrition_by_person,
            settled_meal_purchases,
        };
        let character = formal_character::advance_opening_day(
            &self.player, &self.identities, day, &self.character.state, activity,
        ).map_err(io::Error::other)?;
        for death in &character.deaths {
            self.population.record_death(&death.person_id, minute)?;
            self.identities.get_mut(&death.person_id).expect("known person").record_death();
            self.work.forget_actor(&death.person_id);
            self.stop_transport_on_death(&death.person_id);
            self.homes.remove(&death.person_id);
            self.households.leave(&death.person_id);
            self.service.release_named(&death.person_id);
        }
        #[cfg(test)]
        day_measurement::mark(&mut measure, 3);
        // Midnight migrations affect the new day's demand. The market closes
        // its previous import window before posting midnight cargo deliveries.
        self.transport.advance(minute);
        self.settle_background_migrations(minute)?;
        let managed = self.managed_residents(managed_population)?;
        self.macro_economy.settle(boundary, self.population.totals(), &managed, &mut self.transport, &mut self.ledger)?;
        #[cfg(test)]
        day_measurement::mark(&mut measure, 4);
        self.work.complete();
        self.character = character;
        if booking == Some(PersonalActivity::ReadNotice) && self.player_alive() {
            self.player_day.last_read_notice = Some(minute);
        }
        self.player_day.booking = None;
        self.player_day.food_milli = 0;
        self.clock = boundary;
        self.settle_transport_arrivals(minute)?;
        self.advance_commute(minute);
        self.review_background_migration(managed_population);
        self.plan_household_orders()?;
        self.settle_organization_employment()?;
        Ok(())
    }

    fn settle_transport_arrivals(&mut self, minute: i64) -> io::Result<()> {
        self.settle_passenger()?;
        self.settle_named_passengers()?;
        self.settle_freight()?;
        self.macro_economy.settle_transport(&mut self.transport, &mut self.ledger, minute)?;
        self.settle_background_migrations(minute)
    }

    fn managed_residents(&self, external: &BTreeMap<String, u64>) -> io::Result<BTreeMap<String, u64>> {
        let mut managed = external.clone();
        for (unit, &named) in self.population.named_counts() {
            if !self.population.totals().contains_key(unit) { continue; }
            let count = managed.entry(unit.clone()).or_default();
            *count = count.checked_add(named).ok_or_else(|| invalid("invalid managed population"))?;
        }
        Ok(managed)
    }
}

#[cfg(test)]
pub(super) mod day_measurement {
    use std::{cell::Cell, time::Instant};

    thread_local! {
        static TOTALS: Cell<Option<[u128; 5]>> = const { Cell::new(None) };
    }

    pub(in crate::formal_bootstrap) fn enable() { TOTALS.set(Some([0; 5])); }

    pub(super) fn start() -> Option<Instant> {
        TOTALS.get().map(|_| Instant::now())
    }

    pub(super) fn mark(measure: &mut Option<Instant>, stage: usize) {
        if let Some(previous) = measure {
            let now = Instant::now();
            let mut totals = TOTALS.get().expect("measurement is active");
            totals[stage] += now.duration_since(*previous).as_micros();
            TOTALS.set(Some(totals));
            *previous = now;
        }
    }

    pub(in crate::formal_bootstrap) fn take() -> [u128; 5] { TOTALS.take().expect("measurement is active") }
}
