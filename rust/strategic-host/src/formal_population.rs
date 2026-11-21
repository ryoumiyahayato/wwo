mod demography;
mod historical;
pub mod historical_food;
mod inspection;
pub mod living_conditions;
mod native;
mod opening;
pub mod needs;
pub mod reproductive_needs;
mod social;
#[cfg(test)]
mod tests;

pub use demography::{AgeRangeCoverage, EnergyReferenceCoverage, PopulationStructure, ResidentCohort};
pub use historical::{city_population_reference, population_archive, structural_coverage_reference, HistoricalPopulationEstimate, PopulationArchive};
pub use inspection::{PopulationChange, PopulationChild, PopulationInspection};
pub(crate) use native::PopulationSnapshot;
pub(crate) use opening::{HistoricalOpening, CURRENT_VERSION};
pub use opening::OpeningPopulationEstimate;
pub use social::{OpeningSocialDistribution, SocialDimension, SocialDistribution};

use crate::formal_clock::GameClock;
use crate::formal_save::{field, integer, invalid, lookup, map, tagged};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::BTreeMap, io, sync::Arc};

pub(crate) const MAX_POPULATION: u64 = 9_007_199_254_740_991;

/// Statistical residence and named population claims. Map control and physical
/// travel have separate owners and do not change these totals.
#[derive(Clone)]
pub struct Population {
    // Market totals retain their existing national/coextensive statistical scope.
    totals: BTreeMap<String, u64>,
    standalone: BTreeMap<String, u64>,
    // Each resident belongs to exactly one pool. The pool at a partitioned
    // parent holds residents whose finer statistical residence is unavailable.
    pools: BTreeMap<String, u64>,
    global_total: u64,
    opening: Option<Arc<HistoricalOpening>>,
    named: BTreeMap<String, String>,
    named_cohorts: BTreeMap<String, CohortId>,
    named_counts: BTreeMap<String, u64>,
    pool_named_counts: BTreeMap<String, u64>,
    deceased: BTreeMap<String, Option<i64>>,
    cohort_definitions: BTreeMap<CohortId, CohortDefinition>,
    cohort_sources: BTreeMap<CohortId, demography::SourceCell>,
    cohorts: BTreeMap<String, BTreeMap<CohortId, u64>>,
    history: native::History,
}

/// Identifies a source record independently of where its residents now live.
#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CohortId {
    source: String,
    record: String,
}

impl CohortId {
    pub fn new(source: impl Into<String>, record: impl Into<String>) -> io::Result<Self> {
        let id = Self { source: source.into(), record: record.into() };
        if !id.valid() { return Err(invalid("invalid population cohort source or record")); }
        Ok(id)
    }

    pub fn source(&self) -> &str { &self.source }
    pub fn record(&self) -> &str { &self.record }

    fn valid(&self) -> bool {
        [&self.source, &self.record].into_iter().all(|value| {
            !value.is_empty() && value.trim() == value && !value.chars().any(char::is_control)
        })
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CohortProvenance {
    Observed,
    ModelAllocation,
    Simulation,
    Fixture,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum CohortSex {
    Female,
    Male,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CohortBirthYears {
    pub earliest: i64,
    pub latest: i64,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CohortDefinition {
    pub provenance: CohortProvenance,
    pub sex: Option<CohortSex>,
    pub birth_years: Option<CohortBirthYears>,
}

impl CohortDefinition {
    /// Inclusive bounds in complete years. Birth dates within a year are unknown.
    pub fn age_bounds(&self, clock: GameClock) -> Option<(i64, i64)> {
        let years = self.birth_years?;
        let date = clock.current_date();
        if years.earliest <= 0 || years.earliest > years.latest || years.latest > date.year {
            return None;
        }
        let birthday_uncertain = i64::from(date.month != 12 || date.day != 31);
        let youngest = (date.year - years.latest - birthday_uncertain).max(0);
        Some((youngest, date.year - years.earliest))
    }
}

impl Population {
    pub(crate) fn initialize(totals: BTreeMap<String, u64>) -> Self {
        Self {
            global_total: totals.values().sum(),
            pools: totals.clone(),
            totals,
            standalone: BTreeMap::new(),
            opening: None,
            named: BTreeMap::new(),
            named_cohorts: BTreeMap::new(),
            named_counts: BTreeMap::new(),
            pool_named_counts: BTreeMap::new(),
            deceased: BTreeMap::new(),
            cohort_definitions: BTreeMap::new(),
            cohort_sources: BTreeMap::new(),
            cohorts: BTreeMap::new(),
            history: native::History::default(),
        }
    }

    pub(crate) fn initialize_historical(legacy: &BTreeMap<String, u64>, opening: Arc<HistoricalOpening>) -> Self {
        let mut state = Self::initialize(opening.totals(legacy));
        state.standalone = opening.standalone.clone();
        state.global_total += state.standalone.values().sum::<u64>();
        state.pools.extend(state.standalone.clone());
        for (id, partition) in &opening.partitions {
            let count = opening.estimate(id).expect("partition opening estimate").population_value;
            *state.pools.get_mut(&partition.parent).expect("partition parent") -= count;
            state.pools.insert(id.clone(), count);
        }
        state.opening = Some(opening);
        state
    }

    pub fn totals(&self) -> &BTreeMap<String, u64> {
        &self.totals
    }

    pub fn standalone_totals(&self) -> &BTreeMap<String, u64> { &self.standalone }

    pub fn population_total(&self, unit: &str) -> Option<u64> {
        self.totals.get(unit).or_else(|| self.standalone.get(unit)).or_else(|| self.pools.get(unit)).copied()
            .or_else(|| Some(self.opening.as_ref()?.statistical_aggregates.get(unit)?.members.iter()
                .map(|member| self.pools[member]).sum()))
    }

    pub fn partitions<'a>(&'a self, parent: &'a str) -> impl Iterator<Item = (&'a str, &'a str, u64)> + 'a {
        self.opening.iter().flat_map(|opening| &opening.partitions).filter_map(move |(id, partition)| {
            (partition.parent == parent).then(|| (id.as_str(), partition.name.as_str(), self.pools[id]))
        })
    }

    /// Immediate geographical components, including nonexclusive subtotals.
    pub fn statistical_children<'a>(&'a self, parent: &'a str) -> impl Iterator<Item = (&'a str, &'a str, u64)> + 'a {
        let aggregates = self.opening.iter().flat_map(|opening| &opening.statistical_aggregates)
            .filter(move |(_, scope)| scope.parent == parent)
            .map(|(id, scope)| (id.as_str(), scope.name.as_str(), scope.members.iter().map(|member| self.pools[member]).sum()));
        let leaves = self.opening.iter().flat_map(|opening| &opening.partitions)
            .filter(move |(_, part)| part.statistical_parent.as_deref().unwrap_or(&part.parent) == parent)
            .map(|(id, part)| (id.as_str(), part.name.as_str(), self.pools[id]));
        aggregates.chain(leaves)
    }

    fn statistical_parent(&self, unit: &str) -> Option<&str> {
        let opening = self.opening.as_ref()?;
        opening.partitions.get(unit).and_then(|part| part.statistical_parent.as_deref())
            .or_else(|| opening.statistical_aggregates.get(unit).map(|scope| scope.parent.as_str()))
    }

    pub(crate) fn pool_in_scope(&self, pool: &str, scope: &str) -> bool {
        pool == scope || self.parent_unit(pool) == Some(scope) || self.statistical_parent(pool) == Some(scope)
    }

    /// Residents directly assigned to this unit, excluding all nested shares.
    pub fn resident_pool(&self, unit: &str) -> Option<u64> { self.pools.get(unit).copied() }

    pub fn admitted_opening(&self, unit: &str) -> Option<&OpeningPopulationEstimate> {
        self.opening.as_ref()?.estimate(unit)
    }

    pub(crate) fn opening_version(&self) -> Option<u32> {
        self.opening.as_ref().map(|opening| opening.version())
    }

    pub(crate) fn partition_at(&self, place: &str) -> Option<&str> {
        self.opening.as_ref()?.unit_at(place)
    }

    pub(crate) fn residence_parent(&self, unit: &str) -> Option<&str> {
        let (id, _) = self.totals.get_key_value(unit).or_else(|| self.standalone.get_key_value(unit))?;
        if self.opening.as_ref().is_some_and(|opening| opening.estimate(unit).is_some_and(|estimate| estimate.research_unlocated_balance.is_none())
            && opening.partitions.values().any(|part| part.parent == unit)) {
            return None;
        }
        Some(id)
    }

    pub(crate) fn parent_unit(&self, unit: &str) -> Option<&str> {
        if let Some(partition) = self.opening.as_ref().and_then(|opening| opening.partitions.get(unit)) {
            return Some(&partition.parent);
        }
        self.totals.get_key_value(unit).or_else(|| self.standalone.get_key_value(unit))
            .map(|(id, _)| id.as_str())
    }

    fn change_total(&mut self, pool: &str, members: u64, increase: bool) {
        let root = self.parent_unit(pool).expect("known population pool").to_owned();
        let total = self.totals.get_mut(&root).or_else(|| self.standalone.get_mut(&root)).expect("population parent");
        let count = self.pools.get_mut(pool).expect("population pool");
        if increase {
            *total += members;
            *count += members;
        } else {
            *total -= members;
            *count -= members;
            if self.opening.as_ref().is_some_and(|opening| opening.social.regions.contains_key(pool)) {
                let outflow = self.history.social_outflow.entry(pool.to_owned()).or_default();
                *outflow = outflow.saturating_add(members);
            }
        }
    }

    /// Historical opening estimate for this economic unit. Movement and vital
    /// events update current residents independently of the source estimates.
    pub fn opening_estimate(&self, unit: &str) -> io::Result<Option<HistoricalPopulationEstimate>> {
        if !self.totals.contains_key(unit) || self.admitted_opening(unit).is_some() { return Ok(None); }
        historical::opening_estimate(unit)
    }

    pub fn unit_for_person(&self, person: &str) -> Option<&str> {
        self.named.get(person).map(String::as_str)
    }

    pub fn sex_for_person(&self, person: &str) -> Option<CohortSex> {
        self.cohort_definitions.get(self.named_cohorts.get(person)?)?.sex
    }

    pub fn known_dead(&self, person: &str) -> bool {
        self.deceased.contains_key(person)
    }

    pub(crate) fn death_minute(&self, person: &str) -> Option<i64> {
        self.deceased.get(person).copied().flatten()
    }

    pub fn named_counts(&self) -> &BTreeMap<String, u64> {
        &self.named_counts
    }

    /// All residents without a named claim, including separately evidenced cohorts.
    pub fn background(&self, unit: &str) -> Option<u64> {
        self.population_total(unit).map(|total| {
            let named = if let Some(scope) = self.opening.as_ref().and_then(|opening| opening.statistical_aggregates.get(unit)) {
                scope.members.iter().map(|member| self.pool_named_counts.get(member).copied().unwrap_or(0)).sum()
            } else {
                let counts = if self.parent_unit(unit) == Some(unit) { &self.named_counts } else { &self.pool_named_counts };
                counts.get(unit).copied().unwrap_or(0)
            };
            total - named
        })
    }

    /// Residents of the exclusive pool without a named claim or demographic breakdown.
    pub fn unclassified(&self, unit: &str) -> Option<u64> {
        self.resident_pool(unit).map(|pool| {
            let classified: u64 = self.cohorts.get(unit).into_iter().flat_map(|rows| rows.values()).sum();
            pool - self.pool_named_counts.get(unit).copied().unwrap_or(0) - classified
        })
    }

    pub fn cohort_members(&self, unit: &str, id: &CohortId) -> Option<u64> {
        self.cohorts.get(unit)?.get(id).copied()
    }

    pub fn cohorts_in(&self, unit: &str) -> impl Iterator<Item = (&CohortId, &CohortDefinition, u64)> {
        self.cohorts.get(unit).into_iter().flatten().map(|(id, &members)| {
            (id, &self.cohort_definitions[id], members)
        })
    }

    pub(crate) fn named_len(&self) -> usize {
        self.named.len()
    }

    /// Recover which residents are already assigned to the regional economy.
    /// The statistical economy excludes those residents from its own demand.
    pub(crate) fn restore_regional_responsibility<'a>(
        &self, native: &Value, minute: i64, unit_at: impl Fn(&str) -> Option<&'a str>,
    ) -> io::Result<BTreeMap<String, u64>> {
        let state = map(native)?;
        let config = map(field(state, "config")?)?;
        let mut counts = BTreeMap::new();
        if field(config, "host_personal_accounts")?.as_bool() != Some(true) {
            return Err(invalid("regional economy has no formal population authority"));
        }
        if lookup(state, "management")
            .map(|value| Ok::<_, io::Error>(field(map(value)?, "status")?.as_str() == Some("ACTIVE")))
            .transpose()? == Some(false)
        {
            return Ok(counts);
        }
        let actors = map(field(state, "actors")?)?;
        let stock = map(field(state, "stock")?)?;
        let mut lifecycle = BTreeMap::<&str, (i64, bool)>::new();
        if let Some(rows) = lookup(state, "scope_requests") {
            for pair in map(rows)? {
                let event = map(&pair[1])?;
                let kind = field(event, "kind")?.as_str();
                if field(event, "status")?.as_str() != Some("APPLIED") || !matches!(kind, Some("EXIT" | "REENTER")) {
                    continue;
                }
                let effective = integer(field(event, "effective_minute")?)?;
                if !(0..=minute).contains(&effective) {
                    return Err(invalid("applied regional responsibility is outside the save clock"));
                }
                let subject = field(map(field(event, "payload")?)?, "subject_id")?.as_str()
                    .ok_or_else(|| invalid("regional responsibility is missing its subject"))?;
                let current = lifecycle.entry(subject).or_insert((-1, true));
                if current.0 == effective {
                    return Err(invalid("conflicting regional responsibility at the same minute"));
                }
                if effective > current.0 {
                    *current = (effective, kind == Some("REENTER"));
                }
            }
        }
        for value in tagged(field(config, "actors")?, "array")? {
            let row = map(value)?;
            let id = field(row, "id")?.as_str().ok_or_else(|| invalid("missing regional actor ID"))?;
            if field(row, "control")?.as_str() == Some("dormant")
                || lookup(actors, id).is_none()
                || lookup(stock, id).is_none()
            {
                continue;
            }
            match field(row, "kind")?.as_str() {
                Some("named") => {
                    if lifecycle.get(id).is_none_or(|(_, active)| *active) {
                        if let Some(unit) = self.unit_for_person(id).and_then(|unit| self.parent_unit(unit))
                            .filter(|unit| self.totals.contains_key(*unit)) {
                            *counts.entry(unit.to_owned()).or_insert(0) += 1;
                        }
                    }
                }
                Some("cohort") => {
                    let place = lookup(row, "place_id").and_then(Value::as_str).unwrap_or("place:paris");
                    let unit = unit_at(place).filter(|unit| self.totals.contains_key(*unit))
                        .ok_or_else(|| invalid("regional cohort has no population unit"))?;
                    let members = count(field(row, "members")?)?;
                    let subtotal = counts.entry(unit.to_owned()).or_insert(0_u64);
                    *subtotal = subtotal.checked_add(members).filter(|total| *total <= self.totals[unit])
                        .ok_or_else(|| invalid("regional population responsibility exceeds the population unit"))?;
                }
                _ => return Err(invalid("unsupported regional actor kind")),
            }
        }
        if counts.iter().any(|(unit, &quantity)| quantity > self.totals[unit]) {
            return Err(invalid("regional population responsibility exceeds the population unit"));
        }
        Ok(counts)
    }

    /// Register a claim from the opening data or legacy overlay.
    pub(crate) fn claim(&mut self, person: &str, unit: &str) -> io::Result<()> {
        self.check_new_claim(person)?;
        if self.unclassified(unit).unwrap_or(0) == 0 {
            return Err(invalid("named claim is repeated or exceeds its population unit"));
        }
        self.insert_claim(person, unit);
        Ok(())
    }

    fn check_new_claim(&self, person: &str) -> io::Result<()> {
        if !person.strip_prefix("person:").is_some_and(|id| !id.is_empty())
            || self.named.contains_key(person) || self.known_dead(person)
        {
            return Err(invalid("invalid or already known named population claim"));
        }
        Ok(())
    }

    fn insert_claim(&mut self, person: &str, unit: &str) {
        self.named.insert(person.to_owned(), unit.to_owned());
        self.add_named(unit);
    }

    fn add_named(&mut self, unit: &str) {
        let root = self.parent_unit(unit).expect("named population parent").to_owned();
        *self.named_counts.entry(root).or_default() += 1;
        *self.pool_named_counts.entry(unit.to_owned()).or_default() += 1;
    }

    fn retire_claim(&mut self, person: &str, minute: Option<i64>) -> io::Result<()> {
        let (person, unit) = self.named.remove_entry(person)
            .ok_or_else(|| invalid("deceased person has no active population claim"))?;
        self.change_total(&unit, 1, false);
        self.subtract_named(&unit);
        self.named_cohorts.remove(&person);
        self.global_total -= 1;
        self.deceased.insert(person, minute);
        Ok(())
    }

    fn subtract_named(&mut self, unit: &str) {
        let root = self.parent_unit(unit).expect("named population parent").to_owned();
        for (counts, id) in [(&mut self.named_counts, root.as_str()), (&mut self.pool_named_counts, unit)] {
            let count = counts.get_mut(id).expect("named population count");
            *count -= 1;
            if *count == 0 { counts.remove(id); }
        }
    }

    fn named_count(&self, unit: &str) -> u64 {
        self.named_counts.get(unit).copied().unwrap_or(0)
    }

    pub(crate) fn restore(value: &Value) -> io::Result<Self> {
        let snapshot = map(value)?;
        if field(snapshot, "schema_id")?.as_str() != Some("formal_world_population_state_v1") {
            return Err(invalid("unsupported formal population snapshot"));
        }
        let records = tagged(field(snapshot, "records")?, "array")?;
        let mut totals = BTreeMap::new();
        let mut global_total = 0;
        for record in records {
            let row = map(record)?;
            let id = unit_id(row)?;
            let total = count(field(row, "population_total")?)?;
            if field(row, "statistical_scope")?.as_str() != Some("major_economy_aggregate")
                || field(row, "economic_aggregate_id")?.as_str() != Some(id)
                || totals.insert(id.to_owned(), total).is_some()
                || total > MAX_POPULATION - global_total
            {
                return Err(invalid("invalid statistical population record"));
            }
            global_total += total;
        }
        if totals.is_empty() {
            return Err(invalid("no formal population records"));
        }
        let mut state = Self::initialize(totals);
        for entry in map(field(snapshot, "named_person_units")?)? {
            let person = entry[0].as_str().ok_or_else(|| invalid("invalid named population ID"))?;
            let unit = entry[1].as_str().ok_or_else(|| invalid("missing named population unit"))?;
            state.claim(person, unit)?;
        }
        for record in records {
            let row = map(record)?;
            let id = unit_id(row)?;
            if count(field(row, "named_person_count")?)? != state.named_count(id)
                || Some(count(field(row, "remaining_background_population")?)?) != state.background(id)
            {
                return Err(invalid("formal population counts conflict with named claims"));
            }
        }
        Ok(state)
    }
}

fn count(value: &Value) -> io::Result<u64> {
    u64::try_from(integer(value)?).ok().filter(|&count| count <= MAX_POPULATION)
        .ok_or_else(|| invalid("invalid formal population count"))
}

fn unit_id(row: &[Value]) -> io::Result<&str> {
    field(row, "population_unit_id")?.as_str().filter(|id| !id.is_empty())
        .ok_or_else(|| invalid("invalid population unit ID"))
}
