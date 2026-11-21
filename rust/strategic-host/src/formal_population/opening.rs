use super::MAX_POPULATION;
use crate::formal_save::invalid;
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io};

const VERSION: u32 = 1;

#[derive(Debug, Serialize)]
pub struct OpeningPopulationEstimate {
    pub population_value: u64,
    pub source_id: String,
    pub locator: String,
    pub method: String,
}

pub(crate) struct HistoricalOpening {
    estimates: BTreeMap<String, OpeningPopulationEstimate>,
    pub(super) partitions: BTreeMap<String, Partition>,
    pub(super) standalone: BTreeMap<String, u64>,
    places: BTreeMap<String, String>,
}

pub(super) struct Partition {
    pub(super) parent: String,
    pub(super) name: String,
}

#[derive(Deserialize)]
struct Manifest {
    version: u32,
    groups: Vec<Group>,
}

#[derive(Deserialize)]
struct Group {
    unit_id: String,
    population_value: u64,
    source_id: String,
    locator: String,
    method: String,
    units: Vec<Unit>,
    legacy_unlocated_balance: Option<u64>,
}

#[derive(Deserialize)]
struct Unit {
    unit_id: String,
    name: String,
    population_value: u64,
    source_id: Option<String>,
    locator: Option<String>,
    #[serde(default)]
    place_ids: Vec<String>,
}

impl HistoricalOpening {
    pub(crate) fn load<'a>(
        legacy: &BTreeMap<String, u64>,
        known_polity: impl Fn(&str) -> bool,
        market_at: impl Fn(&str) -> Option<&'a str>,
    ) -> io::Result<Self> {
        let manifest: Manifest = serde_json::from_slice(include_bytes!(
            "../../../../data/historical_population_1900/opening.json"
        ))?;
        if manifest.version != VERSION || manifest.groups.is_empty() {
            return Err(invalid("unsupported historical population opening"));
        }
        let mut opening = Self {
            estimates: BTreeMap::new(), partitions: BTreeMap::new(), standalone: BTreeMap::new(),
            places: BTreeMap::new(),
        };
        for group in manifest.groups {
            let root = group.unit_id;
            if (!legacy.contains_key(&root) && !known_polity(&root))
                || group.population_value == 0 || group.population_value > MAX_POPULATION
                || [&group.source_id, &group.locator, &group.method].iter().any(|text| text.trim().is_empty())
            {
                return Err(invalid(format!("invalid historical population group {root}")));
            }
            if !legacy.contains_key(&root) {
                opening.standalone.insert(root.clone(), group.population_value);
            }
            let mut remaining = group.population_value;
            let partitioned = !group.units.is_empty();
            for leaf in group.units {
                let id = leaf.unit_id;
                if id.trim().is_empty() || leaf.name.trim().is_empty() || legacy.contains_key(&id) || known_polity(&id)
                    || opening.partitions.contains_key(&id) || leaf.population_value == 0
                {
                    return Err(invalid(format!("invalid historical population partition {id}")));
                }
                remaining = remaining.checked_sub(leaf.population_value)
                    .ok_or_else(|| invalid(format!("historical population partitions exceed {root}")))?;
                for place in leaf.place_ids {
                    if market_at(&place) != Some(root.as_str())
                        || opening.places.insert(place.clone(), id.clone()).is_some()
                    {
                        return Err(invalid(format!("invalid or repeated historical residence binding {place} in {id}")));
                    }
                }
                opening.estimates.insert(id.clone(), OpeningPopulationEstimate {
                    population_value: leaf.population_value, source_id: leaf.source_id.unwrap_or_else(|| group.source_id.clone()),
                    locator: leaf.locator.unwrap_or_else(|| group.locator.clone()), method: group.method.clone(),
                });
                opening.partitions.insert(id, Partition { parent: root.clone(), name: leaf.name });
            }
            if let Some(residual) = group.legacy_unlocated_balance {
                if !partitioned || remaining != residual || legacy.get(&root) != Some(&group.population_value) {
                    return Err(invalid(format!("unlocated balance differs from the legacy control for {root}")));
                }
                // The verified leaves already debit this pool. Its control retains its
                // original provenance and must not be exposed as a historical observation.
                continue;
            }
            if partitioned && remaining != 0 {
                return Err(invalid(format!("historical population partitions do not sum to {root}")));
            }
            if opening.estimates.insert(root.clone(), OpeningPopulationEstimate {
                population_value: group.population_value, source_id: group.source_id,
                locator: group.locator, method: group.method,
            }).is_some() {
                return Err(invalid(format!("repeated historical population group {root}")));
            }
        }
        let totals = opening.totals(legacy);
        if totals.values().chain(opening.standalone.values()).try_fold(0u64, |sum, &value| {
            sum.checked_add(value).filter(|&sum| sum <= MAX_POPULATION)
        }).is_none() {
            return Err(invalid("historical opening exceeds the supported population"));
        }
        Ok(opening)
    }

    pub(crate) fn version(&self) -> u32 { VERSION }

    pub(super) fn estimate(&self, unit: &str) -> Option<&OpeningPopulationEstimate> {
        self.estimates.get(unit)
    }

    pub(crate) fn unit_at(&self, place: &str) -> Option<&str> {
        self.places.get(place).map(String::as_str)
    }

    pub(crate) fn totals(&self, legacy: &BTreeMap<String, u64>) -> BTreeMap<String, u64> {
        legacy.iter().map(|(unit, &legacy_total)| {
            (unit.clone(), self.estimate(unit).map_or(legacy_total, |row| row.population_value))
        }).collect()
    }
}
