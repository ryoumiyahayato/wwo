use super::{CohortDefinition, CohortId, CohortProvenance, Population, MAX_POPULATION};
use crate::{formal_clock::{GameClock, MINUTES_PER_DAY}, formal_save::invalid};
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet}, io};

const VERSION: u32 = 1;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct PopulationSnapshot {
    version: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) opening_version: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    migrated: Option<MigratedPopulation>,
    journal: Vec<PopulationEvent>,
}

#[derive(Clone, Default)]
pub(super) struct History {
    migrated: Option<MigratedPopulation>,
    journal: Vec<PopulationEvent>,
}

/// Flat native saves recorded final counts and character deaths. Transfers
/// before migration have no source, destination, or time records of their own.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct MigratedPopulation {
    totals: BTreeMap<String, u64>,
    deceased: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PopulationEvent {
    minute: i64,
    change: Change,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
enum Change {
    AllocateCohort { unit: String, id: CohortId, definition: CohortDefinition, members: u64 },
    Transfer { source: String, destination: String, cohort: Option<CohortId>, members: u64 },
    Materialize { person: String, unit: String, cohort: Option<CohortId> },
    Arrival { person: String, unit: String },
    Move { person: String, destination: String },
    NamedBirth { person: String, unit: String },
    AnonymousBirths { unit: String, members: u64 },
    NamedDeath { person: String },
    AnonymousDeaths { unit: String, cohort: Option<CohortId>, members: u64 },
}

impl Population {
    pub(crate) fn snapshot(&self) -> PopulationSnapshot {
        PopulationSnapshot {
            version: VERSION,
            opening_version: self.opening_version(),
            migrated: self.history.migrated.clone(),
            journal: self.history.journal.clone(),
        }
    }

    pub(crate) fn migrate_native<'a>(
        mut self, totals: BTreeMap<String, u64>, dead: impl Iterator<Item = &'a str>,
    ) -> io::Result<Self> {
        if self.opening.is_some() || self.history.migrated.is_some() || !self.history.journal.is_empty() {
            return Err(invalid("population migration requires an unmodified opening"));
        }
        for person in dead { self.retire_claim(person, None)?; }
        let global = totals.values().try_fold(0u64, |sum, &total| {
            sum.checked_add(total).filter(|&sum| sum <= MAX_POPULATION)
        });
        if totals.keys().ne(self.totals.keys()) || global != Some(self.global_total)
            || self.named_counts.iter().any(|(unit, &named)| totals[unit] < named)
        {
            return Err(invalid("legacy native population disagrees with its opening or mortality"));
        }
        if totals != self.totals || !self.deceased.is_empty() {
            self.history.migrated = Some(MigratedPopulation {
                totals: totals.clone(),
                deceased: self.deceased.keys().cloned().collect(),
            });
        }
        self.pools = totals.clone();
        self.totals = totals;
        Ok(self)
    }

    pub(crate) fn restore_native(mut self, snapshot: PopulationSnapshot, minute: i64) -> io::Result<Self> {
        if snapshot.version != VERSION || snapshot.opening_version != self.opening_version() || minute < 0 {
            return Err(invalid("unsupported native population version or clock"));
        }
        if self.history.migrated.is_some() || !self.history.journal.is_empty() {
            return Err(invalid("native population restore requires an unmodified opening"));
        }
        if let Some(migrated) = snapshot.migrated {
            self = self.migrate_native(migrated.totals, migrated.deceased.iter().map(String::as_str))?;
        }
        for event in snapshot.journal {
            if event.minute > minute { return Err(invalid("population event is beyond the save clock")); }
            self.apply_event(event)?;
        }
        Ok(self)
    }

    pub(crate) fn check_identities<'a>(
        &self, people: impl IntoIterator<Item = (&'a str, bool)>,
    ) -> io::Result<()> {
        let mut seen = BTreeSet::new();
        for (person, alive) in people {
            let matched = if alive { self.named.contains_key(person) } else { self.known_dead(person) };
            if !matched || !seen.insert(person) {
                return Err(invalid("named population claim disagrees with the character roster"));
            }
        }
        if seen.len() != self.named.len() + self.deceased.len() {
            return Err(invalid("population references people absent from the character roster"));
        }
        Ok(())
    }

    /// Bind runtime identity origins to their population journal entries, including deceased identities.
    pub(crate) fn check_runtime_origins<'a>(
        &self, people: impl IntoIterator<Item = (&'a str, &'a str, u16, Option<u32>)>,
    ) -> io::Result<()> {
        let mut origins = BTreeMap::new();
        for (person, unit, birth_year, birth_day) in people {
            if origins.insert(person, (unit, i64::from(birth_year), birth_day)).is_some() {
                return Err(invalid("duplicate runtime population origin"));
            }
        }
        for event in &self.history.journal {
            let (person, unit, cohort, born_day) = match &event.change {
                Change::Materialize { person, unit, cohort } => (person, unit, cohort.as_ref(), None),
                Change::Arrival { person, unit } => (person, unit, None, None),
                Change::NamedBirth { person, unit } => (person, unit, None, Some(event.minute / MINUTES_PER_DAY)),
                _ => continue,
            };
            let (origin_unit, birth_year, birth_day) = origins.remove(person.as_str())
                .ok_or_else(|| invalid("population entry has no runtime identity origin"))?;
            let mut clock = GameClock::default();
            clock.advance_minutes(event.minute)?;
            let event_year = clock.current_date().year;
            if unit.as_str() != origin_unit || born_day != birth_day.map(i64::from) || !(1..=event_year).contains(&birth_year)
                || (born_day.is_some() && birth_year != event_year)
                || cohort.and_then(|key| self.cohort_definitions[key].birth_years)
                    .is_some_and(|years| !(years.earliest..=years.latest).contains(&birth_year))
            {
                return Err(invalid("runtime identity origin disagrees with its population entry"));
            }
        }
        if !origins.is_empty() {
            return Err(invalid("runtime identity origin has no population entry"));
        }
        Ok(())
    }

    /// Partition available aggregate residents using an explicitly identified source record.
    pub(crate) fn alloc_cohort(
        &mut self, unit: &str, id: CohortId, definition: CohortDefinition, members: u64, minute: i64,
    ) -> io::Result<()> {
        self.apply_event(PopulationEvent {
            minute, change: Change::AllocateCohort { unit: unit.to_owned(), id, definition, members },
        })
    }

    /// Regional responsibility reduces the available unclassified population.
    pub(crate) fn transfer_unmanaged(
        &mut self, source: &str, destination: &str, amount: u64, source_managed_background: u64, minute: i64,
    ) -> io::Result<()> {
        let available = self.unclassified(source)
            .and_then(|total| total.checked_sub(source_managed_background));
        if available.is_none_or(|count| amount > count) {
            return Err(invalid("population transfer exceeds the available unmanaged residents"));
        }
        self.transfer(source, destination, None, amount, minute)
    }

    /// The caller must first account for any obligations attached to the transferred residents.
    pub(crate) fn transfer_cohort(
        &mut self, source: &str, destination: &str, id: &CohortId, amount: u64, minute: i64,
    ) -> io::Result<()> {
        self.transfer(source, destination, Some(id.clone()), amount, minute)
    }

    fn transfer(&mut self, source: &str, destination: &str, cohort: Option<CohortId>, members: u64, minute: i64) -> io::Result<()> {
        self.apply_event(PopulationEvent { minute, change: Change::Transfer {
            source: source.to_owned(), destination: destination.to_owned(), cohort, members,
        } })
    }

    /// Claim a person already counted in the source group. Identity creation belongs to the caller.
    pub(crate) fn materialize_person(
        &mut self, person: &str, unit: &str, cohort: Option<&CohortId>, minute: i64,
    ) -> io::Result<()> {
        self.apply_event(PopulationEvent { minute, change: Change::Materialize {
            person: person.to_owned(), unit: unit.to_owned(), cohort: cohort.cloned(),
        } })
    }

    pub(crate) fn arrive_person(&mut self, person: &str, unit: &str, minute: i64) -> io::Result<()> {
        self.apply_event(PopulationEvent {
            minute, change: Change::Arrival { person: person.to_owned(), unit: unit.to_owned() },
        })
    }

    pub(crate) fn move_person(&mut self, person: &str, destination: &str, minute: i64) -> io::Result<()> {
        self.apply_event(PopulationEvent {
            minute, change: Change::Move { person: person.to_owned(), destination: destination.to_owned() },
        })
    }

    pub(crate) fn record_named_birth(&mut self, person: &str, unit: &str, minute: i64) -> io::Result<()> {
        self.apply_event(PopulationEvent {
            minute, change: Change::NamedBirth { person: person.to_owned(), unit: unit.to_owned() },
        })
    }

    pub(crate) fn record_anonymous_births(&mut self, unit: &str, members: u64, minute: i64) -> io::Result<()> {
        self.apply_event(PopulationEvent {
            minute, change: Change::AnonymousBirths { unit: unit.to_owned(), members },
        })
    }

    pub(crate) fn record_death(&mut self, person: &str, minute: i64) -> io::Result<()> {
        self.apply_event(PopulationEvent { minute, change: Change::NamedDeath { person: person.to_owned() } })
    }

    pub(crate) fn record_cohort_deaths(&mut self, unit: &str, id: &CohortId, members: u64, minute: i64) -> io::Result<()> {
        self.record_background_deaths(unit, Some(id.clone()), members, minute)
    }

    pub(crate) fn record_anonymous_deaths(&mut self, unit: &str, members: u64, minute: i64) -> io::Result<()> {
        self.record_background_deaths(unit, None, members, minute)
    }

    fn record_background_deaths(&mut self, unit: &str, cohort: Option<CohortId>, members: u64, minute: i64) -> io::Result<()> {
        self.apply_event(PopulationEvent {
            minute, change: Change::AnonymousDeaths { unit: unit.to_owned(), cohort, members },
        })
    }

    fn apply_event(&mut self, event: PopulationEvent) -> io::Result<()> {
        if event.minute < 0 || self.history.journal.last().is_some_and(|last| last.minute > event.minute) {
            return Err(invalid("population event precedes the recorded timeline"));
        }
        match &event.change {
            Change::AllocateCohort { unit, id, definition, members } => {
                if !id.valid() || self.cohort_definitions.contains_key(id) {
                    return Err(invalid("invalid or repeated population cohort source"));
                }
                // The shipped sources have no admitted subpopulation records.
                // A save's observed label cannot establish the admission on its own.
                if !cfg!(test) || definition.provenance != CohortProvenance::Fixture {
                    return Err(invalid("population cohort has no admitted source record"));
                }
                if let Some(years) = definition.birth_years {
                    let mut clock = GameClock::default();
                    clock.advance_minutes(event.minute)?;
                    if years.earliest <= 0 || years.earliest > years.latest || years.latest > clock.current_date().year {
                        return Err(invalid("population cohort has invalid birth years"));
                    }
                }
                self.check_background(unit, None, *members)?;
                self.cohort_definitions.insert(id.clone(), *definition);
                self.add_cohort_members(unit, id, *members);
            }
            Change::Transfer { source, destination, cohort, members } => {
                self.check_background(source, cohort.as_ref(), *members)?;
                self.check_destination(source, destination)?;
                self.shift_totals(source, destination, *members);
                if let Some(id) = cohort {
                    self.remove_cohort_members(source, id, *members);
                    self.add_cohort_members(destination, id, *members);
                }
            }
            Change::Materialize { person, unit, cohort } => {
                self.check_new_claim(person)?;
                self.check_background(unit, cohort.as_ref(), 1)?;
                if let Some(id) = cohort { self.remove_cohort_members(unit, id, 1); }
                self.insert_claim(person, unit);
            }
            Change::Move { person, destination } => {
                let source = self.unit_for_person(person).ok_or_else(|| invalid("moving person has no active claim"))?;
                self.check_destination(source, destination)?;
                let source = self.named.insert(person.clone(), destination.clone()).expect("active claim");
                self.shift_totals(&source, destination, 1);
                self.subtract_named(&source);
                self.add_named(destination);
            }
            Change::Arrival { person, unit } | Change::NamedBirth { person, unit } => {
                self.check_new_claim(person)?;
                self.add_population(unit, 1)?;
                self.insert_claim(person, unit);
            }
            Change::AnonymousBirths { unit, members } => self.add_population(unit, *members)?,
            Change::NamedDeath { person } => self.retire_claim(person, Some(event.minute))?,
            Change::AnonymousDeaths { unit, cohort, members } => {
                self.check_background(unit, cohort.as_ref(), *members)?;
                if let Some(id) = cohort { self.remove_cohort_members(unit, id, *members); }
                self.change_total(unit, *members, false);
                self.global_total -= *members;
            }
        }
        self.history.journal.push(event);
        Ok(())
    }

    fn check_background(&self, unit: &str, cohort: Option<&CohortId>, members: u64) -> io::Result<()> {
        let available = match cohort {
            Some(id) => self.cohort_members(unit, id),
            None => self.unclassified(unit),
        };
        if members == 0 || available.is_none_or(|count| members > count) {
            return Err(invalid("population change exceeds the available background residents"));
        }
        Ok(())
    }

    fn check_destination(&self, source: &str, destination: &str) -> io::Result<()> {
        if source == destination || !self.pools.contains_key(destination) {
            return Err(invalid("population transfer requires a distinct known destination"));
        }
        Ok(())
    }

    fn shift_totals(&mut self, source: &str, destination: &str, members: u64) {
        self.change_total(source, members, false);
        self.change_total(destination, members, true);
    }

    fn add_population(&mut self, unit: &str, members: u64) -> io::Result<()> {
        if members == 0 || members > MAX_POPULATION - self.global_total {
            return Err(invalid("population increase exceeds the supported range"));
        }
        if !self.pools.contains_key(unit) { return Err(invalid("unknown population unit")); }
        self.change_total(unit, members, true);
        self.global_total += members;
        Ok(())
    }

    fn add_cohort_members(&mut self, unit: &str, id: &CohortId, members: u64) {
        *self.cohorts.entry(unit.to_owned()).or_default().entry(id.clone()).or_default() += members;
    }

    fn remove_cohort_members(&mut self, unit: &str, id: &CohortId, members: u64) {
        let cohorts = self.cohorts.get_mut(unit).expect("validated cohort unit");
        let count = cohorts.get_mut(id).expect("validated cohort");
        *count -= members;
        if *count == 0 { cohorts.remove(id); }
        if cohorts.is_empty() { self.cohorts.remove(unit); }
    }
}
