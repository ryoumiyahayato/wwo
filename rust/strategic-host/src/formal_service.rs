use crate::{formal_population::{CohortId, Population}, formal_save::invalid};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io};

const VERSION: u32 = 1;

/// Reference to a unit owned by the military domain.
#[derive(Clone, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(tag = "kind", content = "id", rename_all = "snake_case", deny_unknown_fields)]
pub enum ServiceTarget {
    Strategic(String),
    Tactical(String),
}

impl ServiceTarget {
    fn validate(&self) -> io::Result<()> {
        let id = match self { Self::Strategic(id) | Self::Tactical(id) => id };
        if id.is_empty() || id.trim() != id || id.chars().any(char::is_control) {
            return Err(invalid("invalid service unit reference"));
        }
        Ok(())
    }
}

type CohortAssignments = BTreeMap<ServiceTarget, u64>;

#[derive(Default)]
pub struct ServiceRoster {
    named: BTreeMap<String, ServiceTarget>,
    cohorts: BTreeMap<String, BTreeMap<CohortId, CohortAssignments>>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ServiceSnapshot {
    version: u32,
    named: Vec<NamedAssignment>,
    cohorts: Vec<CohortAssignment>,
}

impl Default for ServiceSnapshot {
    fn default() -> Self { Self { version: VERSION, named: Vec::new(), cohorts: Vec::new() } }
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct NamedAssignment { person: String, target: ServiceTarget }

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct CohortAssignment {
    unit: String,
    cohort: CohortId,
    target: ServiceTarget,
    members: u64,
}

impl ServiceRoster {
    pub fn named_target(&self, person: &str) -> Option<&ServiceTarget> {
        self.named.get(person)
    }

    pub fn cohort_serving(&self, unit: &str, cohort: &CohortId) -> u64 {
        self.cohorts.get(unit).and_then(|cohorts| cohorts.get(cohort))
            .map_or(0, |assignments| assignments.values().sum())
    }

    /// Quantity available from an externally established employable group.
    pub fn civilian_available(&self, population: &Population, unit: &str, cohort: &CohortId,
        employable: u64, civilian_committed: u64,
    ) -> io::Result<u64> {
        let membership = cohort_membership(population, unit, cohort)?;
        if employable > membership { return Err(invalid("employable group exceeds its population cohort")); }
        employable.checked_sub(self.cohort_serving(unit, cohort))
            .and_then(|available| available.checked_sub(civilian_committed))
            .ok_or_else(|| invalid("civilian and service commitments exceed the employable group"))
    }

    /// The caller supplies a voluntary decision and authorization from the active service policy.
    pub(crate) fn enlist_named(&mut self, population: &Population, person: &str, target: ServiceTarget,
        volunteered: bool, authorized: bool,
    ) -> io::Result<()> {
        if !volunteered || !authorized { return Err(invalid("voluntary service is not authorized")); }
        self.assign_named(population, person.to_owned(), target)
    }

    fn assign_named(&mut self, population: &Population, person: String, target: ServiceTarget) -> io::Result<()> {
        target.validate()?;
        if population.unit_for_person(&person).is_none() || self.named.contains_key(&person) {
            return Err(invalid("service requires an unassigned living resident"));
        }
        self.named.insert(person, target);
        Ok(())
    }

    pub(crate) fn release_named(&mut self, person: &str) -> Option<ServiceTarget> {
        self.named.remove(person)
    }

    /// Authorization and civilian commitments come from their owning domains.
    pub(crate) fn enlist_cohort(&mut self, population: &Population, unit: &str, cohort: &CohortId,
        target: ServiceTarget, members: u64, civilian_committed: u64, authorized: bool,
    ) -> io::Result<()> {
        if !authorized { return Err(invalid("cohort service is not authorized")); }
        self.assign_cohort(population, CohortAssignment {
            unit: unit.to_owned(), cohort: cohort.clone(), target, members,
        }, civilian_committed)
    }

    fn assign_cohort(&mut self, population: &Population, row: CohortAssignment, civilian_committed: u64) -> io::Result<()> {
        row.target.validate()?;
        let membership = cohort_membership(population, &row.unit, &row.cohort)?;
        let available = self.civilian_available(population, &row.unit, &row.cohort, membership, civilian_committed)?;
        if row.members == 0 || row.members > available {
            return Err(invalid("cohort service exceeds the available members"));
        }
        let assigned = self.cohorts.entry(row.unit).or_default().entry(row.cohort).or_default();
        *assigned.entry(row.target).or_default() += row.members;
        Ok(())
    }

    pub(crate) fn release_cohort(&mut self, unit: &str, cohort: &CohortId, target: &ServiceTarget,
        members: u64,
    ) -> io::Result<()> {
        self.check_assignment(unit, cohort, target, members)?;
        self.subtract_assignment(unit, cohort, target, members);
        Ok(())
    }

    /// Retire existing service members through the population authority.
    pub(crate) fn record_cohort_losses(&mut self, population: &mut Population, unit: &str, cohort: &CohortId,
        target: &ServiceTarget, members: u64, minute: i64,
    ) -> io::Result<()> {
        self.check_assignment(unit, cohort, target, members)?;
        let membership = cohort_membership(population, unit, cohort)?;
        if membership < self.cohort_serving(unit, cohort) {
            return Err(invalid("service cohort assignments exceed their living population"));
        }
        population.record_cohort_deaths(unit, cohort, members, minute)?;
        self.subtract_assignment(unit, cohort, target, members);
        Ok(())
    }

    fn check_assignment(&self, unit: &str, cohort: &CohortId, target: &ServiceTarget, members: u64) -> io::Result<()> {
        let assigned = self.cohorts.get(unit).and_then(|cohorts| cohorts.get(cohort))
            .and_then(|assignments| assignments.get(target)).copied().unwrap_or(0);
        if members == 0 || members > assigned {
            return Err(invalid("service change exceeds the assignment"));
        }
        Ok(())
    }

    fn subtract_assignment(&mut self, unit: &str, cohort: &CohortId, target: &ServiceTarget, members: u64) {
        let cohorts = self.cohorts.get_mut(unit).expect("validated service population unit");
        let assignments = cohorts.get_mut(cohort).expect("validated service cohort");
        let assigned = assignments.get_mut(target).expect("validated service assignment");
        *assigned -= members;
        if *assigned == 0 { assignments.remove(target); }
        if assignments.is_empty() { cohorts.remove(cohort); }
        if cohorts.is_empty() { self.cohorts.remove(unit); }
    }

    pub(crate) fn snapshot(&self) -> ServiceSnapshot {
        let named = self.named.iter().map(|(person, target)| NamedAssignment {
            person: person.clone(), target: target.clone(),
        }).collect();
        let mut cohorts = Vec::new();
        for (unit, assignments) in &self.cohorts {
            for (cohort, targets) in assignments {
                cohorts.extend(targets.iter().map(|(target, &members)| CohortAssignment {
                    unit: unit.clone(), cohort: cohort.clone(), target: target.clone(), members,
                }));
            }
        }
        ServiceSnapshot { version: VERSION, named, cohorts }
    }

    pub(crate) fn restore(snapshot: ServiceSnapshot, population: &Population,
        known_target: impl Fn(&ServiceTarget) -> bool,
    ) -> io::Result<Self> {
        if snapshot.version != VERSION { return Err(invalid("unsupported service roster version")); }
        let mut roster = Self::default();
        for row in snapshot.named {
            if !known_target(&row.target) { return Err(invalid("unknown named service target")); }
            roster.assign_named(population, row.person, row.target)?;
        }
        for row in snapshot.cohorts {
            if !known_target(&row.target) { return Err(invalid("unknown cohort service target")); }
            if roster.cohorts.get(&row.unit).and_then(|cohorts| cohorts.get(&row.cohort))
                .is_some_and(|assignments| assignments.contains_key(&row.target))
            {
                return Err(invalid("duplicate cohort service assignment"));
            }
            roster.assign_cohort(population, row, 0)?;
        }
        Ok(roster)
    }
}

fn cohort_membership(population: &Population, unit: &str, cohort: &CohortId) -> io::Result<u64> {
    population.cohort_members(unit, cohort).ok_or_else(|| invalid("unknown service population cohort"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::formal_population::{CohortBirthYears, CohortDefinition, CohortProvenance};

    #[test]
    fn service_reserves_population_and_releases_only_living_members() {
        let mut population = Population::initialize(BTreeMap::from([("fixture".to_owned(), 801)]));
        let cohort = CohortId::new("service-fixture", "eligible-adults").unwrap();
        let person = "person:service-fixture";
        let named_target = ServiceTarget::Strategic("fixture-formation".into());
        let target = ServiceTarget::Tactical("fixture-unit".into());
        population.claim(person, "fixture").unwrap();
        population.alloc_cohort("fixture", cohort.clone(), CohortDefinition {
            provenance: CohortProvenance::Fixture,
            sex: None,
            birth_years: Some(CohortBirthYears { earliest: 1865, latest: 1880 }),
        }, 800, 0).unwrap();

        let mut roster = ServiceRoster::default();
        assert!(roster.enlist_named(&population, person, named_target.clone(), false, true).is_err());
        roster.enlist_named(&population, person, named_target.clone(), true, true).unwrap();
        assert!(roster.enlist_named(&population, person, target.clone(), true, true).is_err());
        roster.enlist_cohort(&population, "fixture", &cohort, target.clone(), 160, 600, true).unwrap();
        assert!(roster.enlist_cohort(&population, "fixture", &cohort, named_target.clone(), 41, 600, true).is_err());
        assert_eq!(roster.civilian_available(&population, "fixture", &cohort, 800, 600).unwrap(), 40);

        roster.release_cohort("fixture", &cohort, &target, 20).unwrap();
        assert_eq!(population.cohort_members("fixture", &cohort), Some(800));
        assert!(roster.record_cohort_losses(&mut population, "fixture", &cohort, &target, 141, 1).is_err());
        roster.record_cohort_losses(&mut population, "fixture", &cohort, &target, 10, 1).unwrap();
        assert_eq!(population.cohort_members("fixture", &cohort), Some(790));
        assert_eq!(roster.cohort_serving("fixture", &cohort), 130);
        assert_eq!(roster.civilian_available(&population, "fixture", &cohort, 790, 600).unwrap(), 60);

        let saved = serde_json::to_value(roster.snapshot()).unwrap();
        let known_target = |known: &ServiceTarget| known == &named_target || known == &target;
        let restored = ServiceRoster::restore(serde_json::from_value(saved.clone()).unwrap(), &population, known_target).unwrap();
        assert_eq!(restored.named_target(person), Some(&named_target));
        assert_eq!(restored.cohort_serving("fixture", &cohort), 130);
        assert!(ServiceRoster::restore(serde_json::from_value(saved.clone()).unwrap(), &population, |_| false).is_err());

        let mut duplicate = saved.clone();
        let rows = duplicate["cohorts"].as_array_mut().unwrap();
        rows.push(rows[0].clone());
        assert!(ServiceRoster::restore(serde_json::from_value(duplicate).unwrap(), &population, known_target).is_err());
        let mut oversized = saved.clone();
        oversized["cohorts"][0]["members"] = 791.into();
        assert!(ServiceRoster::restore(serde_json::from_value(oversized).unwrap(), &population, known_target).is_err());

        population.record_death(person, 2).unwrap();
        assert!(ServiceRoster::restore(serde_json::from_value(saved).unwrap(), &population, known_target).is_err());
        assert_eq!(roster.release_named(person), Some(named_target));
        assert_eq!(roster.named_target(person), None);
    }
}
