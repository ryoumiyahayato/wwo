use crate::formal_save::{field, integer, invalid, lookup, map, tagged};
use serde_json::Value;
use std::{collections::BTreeMap, io};

pub(crate) const MAX_POPULATION: u64 = 9_007_199_254_740_991;

/// Statistical residence and named population claims. Map control and physical
/// travel have separate owners and do not change these totals.
#[derive(Clone)]
pub struct Population {
    totals: BTreeMap<String, u64>,
    named: BTreeMap<String, String>,
    named_counts: BTreeMap<String, u64>,
}

impl Population {
    pub(crate) fn initialize(totals: BTreeMap<String, u64>) -> Self {
        Self { totals, named: BTreeMap::new(), named_counts: BTreeMap::new() }
    }

    pub fn totals(&self) -> &BTreeMap<String, u64> {
        &self.totals
    }

    pub fn unit_for_person(&self, person: &str) -> Option<&str> {
        self.named.get(person).map(String::as_str)
    }

    pub fn background(&self, unit: &str) -> Option<u64> {
        self.totals.get(unit).map(|total| total - self.named_count(unit))
    }

    /// Transfers anonymous residents. Cohorts with an assigned economic owner
    /// must first go through that owner's responsibility handover.
    pub(crate) fn transfer_unmanaged(
        &mut self, source: &str, destination: &str, amount: u64, source_managed_background: u64,
    ) -> io::Result<()> {
        let available = self.background(source).and_then(|total| total.checked_sub(source_managed_background))
            .ok_or_else(|| invalid("invalid anonymous source population"))?;
        let target = self.totals.get(destination).copied()
            .ok_or_else(|| invalid("unknown population destination"))?;
        if source == destination || amount == 0 || amount > available || amount > MAX_POPULATION - target {
            return Err(invalid("population transfer exceeds the available anonymous residents"));
        }
        *self.totals.get_mut(source).unwrap() -= amount;
        *self.totals.get_mut(destination).unwrap() += amount;
        Ok(())
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
                        if let Some(unit) = self.unit_for_person(id) {
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

    pub(crate) fn claim(&mut self, person: &str, unit: &str) -> io::Result<()> {
        if !person.strip_prefix("person:").is_some_and(|id| !id.is_empty())
            || self.named.contains_key(person)
            || self.background(unit).unwrap_or(0) == 0
        {
            return Err(invalid("named claim is repeated or exceeds its population unit"));
        }
        self.named.insert(person.to_owned(), unit.to_owned());
        *self.named_counts.entry(unit.to_owned()).or_default() += 1;
        Ok(())
    }

    pub(crate) fn record_death(&mut self, person: &str) -> io::Result<()> {
        let unit = self.named.remove(person).ok_or_else(|| invalid("deceased person has no active population claim"))?;
        *self.totals.get_mut(&unit).expect("named population unit") -= 1;
        *self.named_counts.get_mut(&unit).expect("named population count") -= 1;
        Ok(())
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
