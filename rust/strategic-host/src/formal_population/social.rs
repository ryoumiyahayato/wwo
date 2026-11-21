use super::{HistoricalOpening, Population};
use crate::formal_save::invalid;
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet}, io};

const DIMENSIONS: &[&str] = &[
    "occupation", "class", "legal_estate", "language", "culture", "religion", "literacy",
    "residence", "marital_status", "housing",
];

#[derive(Default)]
pub(super) struct OpeningSocial {
    pub(super) regions: BTreeMap<String, OpeningSocialRegion>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    version: u32,
    regions: Vec<OpeningSocialRegion>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct OpeningSocialRegion {
    unit_id: String,
    opening_total: u64,
    marginal_distributions: BTreeMap<String, OpeningSocialDistribution>,
}

/// One opening allocation. Categories are exclusive within this distribution.
/// Separate distributions do not identify which residents share attributes.
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct OpeningSocialDistribution {
    pub classification_id: String,
    pub source_ids: Vec<String>,
    pub observed_date: String,
    pub observed_unit_id: String,
    pub observed_scope: String,
    pub locator: String,
    pub observed_total: u64,
    pub observed_unknown: u64,
    pub method: String,
    pub definition: String,
    pub counts: BTreeMap<String, u64>,
    pub unknown: u64,
}

impl OpeningSocial {
    pub(super) fn load(opening: &HistoricalOpening, bytes: &[u8]) -> io::Result<Self> {
        let manifest: Manifest = serde_json::from_slice(bytes)?;
        if manifest.version != 1 {
            return Err(invalid("unsupported historical social allocations"));
        }
        let mut regions = BTreeMap::new();
        for region in manifest.regions {
            let unit = &region.unit_id;
            let total = opening.estimate(unit).map(|row| row.population_value);
            if total != Some(region.opening_total)
                || opening.partitions.values().any(|part| part.parent == *unit)
                || region.marginal_distributions.is_empty()
            {
                return Err(invalid(format!("invalid historical social resident pool {unit}")));
            }
            for (dimension, row) in &region.marginal_distributions {
                let count = row.counts.values().try_fold(row.unknown, |sum, &count| sum.checked_add(count));
                if !DIMENSIONS.contains(&dimension.as_str())
                    || count != total
                    || row.unknown == region.opening_total
                    || row.counts.keys().any(|name| name.trim().is_empty())
                    || row.observed_total == 0
                    || row.observed_unknown > row.observed_total
                    || row.source_ids.is_empty()
                    || row.source_ids.iter().any(|id| id.trim().is_empty())
                    || [&row.classification_id, &row.observed_date, &row.observed_unit_id,
                        &row.observed_scope, &row.locator, &row.method, &row.definition].iter().any(|value| value.trim().is_empty())
                {
                    return Err(invalid(format!("invalid historical social distribution {dimension} for {unit}")));
                }
            }
            if regions.insert(unit.clone(), region).is_some() {
                return Err(invalid("repeated historical social resident pool"));
            }
        }
        Ok(Self { regions })
    }
}

#[derive(Default, Serialize)]
pub struct SocialDimension<'a> {
    pub assigned_residents: u64,
    pub unknown_residents: u64,
    pub by_classification: BTreeMap<&'a str, BTreeMap<&'a str, u64>>,
    pub source_ids: BTreeSet<&'a str>,
    pub direct_opening_distribution: Option<&'a OpeningSocialDistribution>,
}

#[derive(Serialize)]
pub struct SocialDistribution<'a> {
    pub population_total: u64,
    pub dimensions: BTreeMap<&'a str, SocialDimension<'a>>,
    pub residents_with_any_attribute_minimum: u64,
    pub residents_with_any_attribute_maximum: u64,
    /// Departures and deaths have no category information. Counts retain only
    /// the lower bound from opening assignments, and new residents are unknown.
    pub affected_resident_pools: u64,
}

impl Population {
    /// Independent population attributes for an account or the whole world.
    pub fn social_distribution(&self, unit: Option<&str>) -> Option<SocialDistribution<'_>> {
        let population_total = match unit {
            Some(unit) => self.population_total(unit)?,
            None => self.global_total(),
        };
        let mut dimensions: BTreeMap<_, SocialDimension<'_>> = DIMENSIONS.iter().map(|&key| {
            (key, SocialDimension { unknown_residents: population_total, ..SocialDimension::default() })
        }).collect();
        let mut minimum = 0;
        let mut maximum = 0;
        let mut affected_resident_pools = 0;
        for (id, region) in self.opening.iter().flat_map(|opening| &opening.social.regions) {
            if unit.is_some_and(|unit| unit != id && self.parent_unit(id) != Some(unit)) {
                continue;
            }
            let outflow = self.history.social_outflow.get(id).copied().unwrap_or(0);
            let current = self.pools[id];
            affected_resident_pools += u64::from(outflow != 0 || current != region.opening_total);
            let mut pool_minimum = 0;
            let mut pool_maximum = 0;
            for (key, distribution) in &region.marginal_distributions {
                let dimension = dimensions.get_mut(key.as_str()).expect("validated population dimension");
                dimension.source_ids.extend(distribution.source_ids.iter().map(String::as_str));
                if unit == Some(id) {
                    dimension.direct_opening_distribution = Some(distribution);
                }
                let classes = dimension.by_classification.entry(&distribution.classification_id).or_default();
                let mut assigned = 0;
                for (category, &opening_members) in &distribution.counts {
                    let retained = opening_members.saturating_sub(outflow);
                    if retained > 0 {
                        *classes.entry(category).or_default() += retained;
                        assigned += retained;
                    }
                }
                dimension.assigned_residents += assigned;
                dimension.unknown_residents -= assigned;
                pool_minimum = pool_minimum.max(assigned);
                pool_maximum += region.opening_total - distribution.unknown;
            }
            minimum += pool_minimum;
            maximum += pool_maximum.min(current);
        }
        Some(SocialDistribution {
            population_total, dimensions, residents_with_any_attribute_minimum: minimum,
            residents_with_any_attribute_maximum: maximum, affected_resident_pools,
        })
    }
}
