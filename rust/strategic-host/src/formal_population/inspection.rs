use super::{
    historical::{
        historical_source, population_archive_scope, structural_coverage_reference,
        traits_for_scope,
    },
    living_conditions::{living_conditions_references, LivingConditionsReferences},
    CohortId, HistoricalPopulationEstimate, OpeningPopulationEstimate, Population,
    PopulationArchive, PopulationStructure, SocialDistribution,
};
use crate::formal_clock::{CalendarTime, GameClock};
use serde::Serialize;
use serde_json::Value;
use std::{collections::BTreeSet, io};

#[derive(Serialize)]
pub struct PopulationChild<'a> {
    pub unit_id: &'a str,
    pub name: &'a str,
    pub population_total: u64,
}

#[derive(Serialize)]
pub struct PopulationChange<'a> {
    pub minute: i64,
    pub kind: &'static str,
    pub unit_id: Option<&'a str>,
    pub destination: Option<&'a str>,
    pub members: Option<u64>,
    pub cohort_id: Option<&'a CohortId>,
}

#[derive(Serialize)]
pub struct DietaryNormApplicability {
    pub trait_id: &'static str,
    pub residents_with_matching_religion: u64,
    pub residents_with_unassigned_religion: u64,
    pub observed_adherents: Option<u64>,
}

/// A captured view of this world. Dated references retain their own dates and
/// denominators. A map place can locate an account without enumerating the place.
#[derive(Serialize)]
pub struct PopulationInspection<'a> {
    pub query_id: &'a str,
    pub date: CalendarTime,
    pub minute: i64,
    pub scope_relation: &'static str,
    pub basis: &'static str,
    pub account_id: Option<&'a str>,
    pub parent_id: Option<&'a str>,
    pub children: Vec<PopulationChild<'a>>,
    pub map_place_ids: Vec<&'a str>,
    pub population_total: Option<u64>,
    pub direct_residents: Option<u64>,
    pub opening_version: Option<u32>,
    pub opening: Option<&'a OpeningPopulationEstimate>,
    pub legacy_estimate: Option<HistoricalPopulationEstimate>,
    pub structure: Option<PopulationStructure<'a>>,
    pub social: Option<SocialDistribution<'a>>,
    pub dietary_norms: Vec<DietaryNormApplicability>,
    pub archive: Option<PopulationArchive>,
    pub structural_coverage: Option<Value>,
    pub city_reference: Option<Value>,
    pub traits: Vec<Value>,
    pub living_conditions: LivingConditionsReferences,
    /// Up to 100 matching journal entries, newest first.
    pub recent_changes: Vec<PopulationChange<'a>>,
    pub archived_change_details_unknown: bool,
}

impl Population {
    /// Inspect a statistical ID, map ID, `city:<key>`, `trait:<id>` or `world`.
    /// The query borrows the ledger and is usable by downstream domains and Debug.
    pub fn inspect<'a>(
        &'a self,
        query_id: &'a str,
        clock: GameClock,
    ) -> io::Result<PopulationInspection<'a>> {
        self.inspect_with_mapping(query_id, clock, None, None)
    }

    pub(crate) fn inspect_with_mapping<'a>(
        &'a self,
        query_id: &'a str,
        clock: GameClock,
        name_alias: Option<&'a str>,
        residence_unit: Option<&'a str>,
    ) -> io::Result<PopulationInspection<'a>> {
        let map_id = query_id.strip_prefix("state:").unwrap_or(query_id);
        let unit = name_alias.unwrap_or(map_id);
        let world = unit == "world";
        let total = if world {
            Some(self.global_total())
        } else {
            self.population_total(unit)
        };
        let live = total.is_some() && !world;
        let site_account = if unit.starts_with("place:") {
            self.partition_at(unit)
                .or(residence_unit)
                .filter(|account| self.resident_pool(account).is_some())
        } else {
            None
        };
        let account_id = if live { Some(unit) } else { site_account };
        let parent_id = if live {
            self.statistical_parent(unit).or_else(|| self.parent_unit(unit))
                .map(|parent| if parent == unit { "world" } else { parent })
        } else {
            None
        };
        let (mut archive, city_reference) = if world || unit.starts_with("trait:") {
            (None, None)
        } else {
            population_archive_scope(map_id)?
        };
        let (mut traits, mut trait_sources) = traits_for_scope(unit)?;
        let opening = self.admitted_opening(unit);
        let scope = (!world).then_some(unit);
        let structure = (world || live).then(|| self.structure(scope, clock)).flatten();
        let social = (world || live).then(|| self.social_distribution(scope)).flatten();
        let mut dietary_norms = Vec::new();
        if let Some(religion) = social.as_ref().and_then(|report| report.dimensions.get("religion")) {
            let matching = [
                ("russia_1897_reported_confession", "Магометане"),
                ("india_1901_reported_religion", "Muhammadans"),
            ].iter().filter_map(|(classification, category)| {
                religion.by_classification.get(classification)?.get(category)
            }).sum();
            if matching > 0 {
                const TRAIT_ID: &str = "quran_al_maidah_5_3_food_restrictions";
                dietary_norms.push(DietaryNormApplicability {
                    trait_id: TRAIT_ID,
                    residents_with_matching_religion: matching,
                    residents_with_unassigned_religion: religion.unknown_residents,
                    observed_adherents: None,
                });
                if !traits.iter().any(|row| row["id"] == TRAIT_ID) {
                    let (rows, sources) = traits_for_scope("trait:quran_al_maidah_5_3_food_restrictions")?;
                    traits.extend(rows);
                    trait_sources.extend(sources);
                }
            }
        }
        let mut extra_sources = trait_sources;
        let source_ids: BTreeSet<_> = opening.into_iter().map(|row| row.source_id.as_str())
            .chain(structure.iter().flat_map(|report| &report.cohorts)
                .filter_map(|row| row.evidence.as_ref().map(|evidence| evidence.source_id)))
            .chain(social.iter().flat_map(|report| report.dimensions.values())
                .flat_map(|dimension| dimension.source_ids.iter().copied()))
            .collect();
        for source in source_ids {
            extra_sources.extend(historical_source(source)?);
        }
        if !extra_sources.is_empty() {
            let sources = &mut archive
                .get_or_insert_with(PopulationArchive::default)
                .sources;
            for source in extra_sources {
                if !sources.iter().any(|row| row["id"] == source["id"]) {
                    sources.push(source);
                }
            }
        }
        let (scope_relation, basis) = if world {
            ("world", "opening_and_runtime_ledger")
        } else if live {
            (
                if name_alias.is_some() {
                    "historical_name_alias_of_account"
                } else {
                    "statistical_account"
                },
                if opening.is_some() {
                    "admitted_historical_opening"
                } else {
                    "legacy_opening_estimate"
                },
            )
        } else if site_account.is_some() {
            ("residence_site_in_account", "site_total_unknown")
        } else if city_reference.is_some() {
            ("dated_city_reference", "dated_nonadditive_evidence")
        } else if archive
            .as_ref()
            .is_some_and(|row| !row.dated_population.is_empty() || !row.dated_structure.is_empty())
            || !traits.is_empty()
        {
            ("dated_evidence_only", "dated_nonadditive_evidence")
        } else {
            ("unknown", "no_coextensive_population_evidence")
        };
        let children = if world {
            self.totals()
                .iter()
                .chain(self.standalone_totals())
                .map(|(id, &count)| PopulationChild {
                    unit_id: id,
                    name: id,
                    population_total: count,
                })
                .collect()
        } else if live {
            self.statistical_children(unit)
                .map(|(id, name, count)| PopulationChild {
                    unit_id: id,
                    name,
                    population_total: count,
                })
                .collect()
        } else {
            Vec::new()
        };
        let map_place_ids = self
            .opening
            .iter()
            .flat_map(|opening| opening.residence_places())
            .filter(|&(place, account)| {
                if site_account.is_some() {
                    place == unit
                } else {
                    account_id.is_some_and(|id| account == id || self.statistical_parent(account) == Some(id))
                }
            })
            .map(|(place, _)| place)
            .collect();
        Ok(PopulationInspection {
            query_id,
            date: clock.current_date(),
            minute: clock.snapshot().total_minutes,
            scope_relation,
            basis,
            account_id,
            parent_id,
            children,
            map_place_ids,
            population_total: total,
            direct_residents: self.resident_pool(unit),
            opening_version: self.opening_version(),
            opening,
            legacy_estimate: self.opening_estimate(unit)?,
            structure,
            social,
            dietary_norms,
            archive,
            structural_coverage: structural_coverage_reference(unit)?,
            city_reference,
            traits,
            living_conditions: living_conditions_references(),
            recent_changes: if world || live {
                self.recent_changes((!world).then_some(unit))
            } else {
                Vec::new()
            },
            archived_change_details_unknown: (world || live)
                && self.has_migrated_population_baseline(),
        })
    }
}
