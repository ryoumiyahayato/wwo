use super::{
    needs::{
        adult_water_references, published_domestic_water_service_reference,
        published_efsa_water_reference, published_energy_reference, published_protein_reference,
        AgeYears, DomesticWaterServiceReference, NeedSource, QuantityRange, Requirement,
    },
    CohortBirthYears, CohortDefinition, CohortId, CohortProvenance, CohortSex, Population,
};
use crate::{formal_clock::GameClock, formal_save::invalid};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, io, sync::Arc};

const OPENING_YEAR: i64 = 1900;

#[derive(Default)]
pub(super) struct OpeningDemography {
    groups: Vec<Arc<SourceGroup>>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    version: u32,
    groups: Vec<SourceGroup>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SourceGroup {
    unit_id: String,
    source_id: String,
    observed_unit_id: String,
    observed_date: String,
    locator: String,
    observed_total: u64,
    opening_total: u64,
    method: String,
    uncertainty: String,
    #[serde(default)]
    sex_only: bool,
    #[serde(default)]
    unclassified_opening_residents: u64,
    bands: Vec<Band>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Band {
    id: String,
    label: String,
    age_min: Option<u16>,
    age_max: Option<u16>,
    male: u64,
    female: u64,
}

#[derive(Clone)]
pub(super) struct SourceCell {
    group: Arc<SourceGroup>,
    band_index: usize,
    observed_members: u64,
}

impl SourceCell {
    fn band(&self) -> &Band {
        &self.group.bands[self.band_index]
    }

    fn ages_at(&self, clock: GameClock) -> Option<AgeYears> {
        let band = self.band();
        let date = clock.current_date();
        let years = date.year - OPENING_YEAR;
        let extra = i64::from(date.month != 1 || date.day != 1);
        let youngest = u16::try_from(years + i64::from(band.age_min?)).ok()?;
        let oldest = band.age_max.map(|age| u16::try_from(years + extra + i64::from(age))).transpose().ok()?;
        Some(AgeYears { youngest, oldest })
    }

    fn describes_birth_year(&self, year: i64) -> bool {
        let band = self.band();
        band.age_min.is_none_or(|age| year <= OPENING_YEAR - i64::from(age))
            && band.age_max.is_none_or(|age| year >= OPENING_YEAR - 1 - i64::from(age))
    }

    fn evidence(&self) -> CohortEvidence<'_> {
        CohortEvidence {
            opening_unit: &self.group.unit_id,
            source_id: &self.group.source_id,
            observed_unit: &self.group.observed_unit_id,
            observed_date: &self.group.observed_date,
            locator: &self.group.locator,
            original_age_label: &self.band().label,
            observed_members: self.observed_members,
            observed_total: self.group.observed_total,
            opening_total: self.group.opening_total,
            method: &self.group.method,
            uncertainty: &self.group.uncertainty,
        }
    }
}

impl OpeningDemography {
    pub(super) fn load(opening: &super::HistoricalOpening, bytes: &[u8]) -> io::Result<Self> {
        let manifest: Manifest = serde_json::from_slice(bytes)?;
        if manifest.version != 1 {
            return Err(invalid("unsupported historical opening demography"));
        }
        let mut pools = BTreeSet::new();
        for group in &manifest.groups {
            let unit = &group.unit_id;
            let covered = opening.statistical_aggregates.get(unit)
                .map_or(std::slice::from_ref(unit), |scope| scope.members.as_slice());
            if covered.iter().any(|pool| !pools.insert(pool))
                || opening.estimate(unit).map(|row| row.population_value) != Some(group.opening_total)
                || group.unclassified_opening_residents >= group.opening_total
                || opening.partitions.values().any(|part| part.parent == *unit)
                || [&group.source_id, &group.observed_unit_id, &group.observed_date,
                    &group.locator, &group.method, &group.uncertainty].iter().any(|text| text.trim().is_empty())
            {
                return Err(invalid(format!("invalid historical demography source for {unit}")));
            }
            validate_bands(group)?;
        }
        Ok(Self { groups: manifest.groups.into_iter().map(Arc::new).collect() })
    }
}

fn validate_bands(group: &SourceGroup) -> io::Result<()> {
    let error = || invalid(format!("invalid or overlapping historical age bands for {}", group.unit_id));
    let mut ids = BTreeSet::new();
    let mut known_ages = [false; 151];
    let mut unknown_age = false;
    let mut source_total = 0u64;
    for band in &group.bands {
        if !ids.insert(&band.id) || band.id.trim().is_empty() || band.label.trim().is_empty() {
            return Err(error());
        }
        match (band.age_min, band.age_max) {
            (None, None) if !unknown_age => unknown_age = true,
            (Some(first), last) => {
                let last = last.unwrap_or(150);
                if first > last || last > 150 { return Err(error()); }
                for covered in &mut known_ages[usize::from(first)..=usize::from(last)] {
                    if *covered { return Err(error()); }
                    *covered = true;
                }
            }
            _ => return Err(error()),
        }
        source_total = source_total.checked_add(band.male)
            .and_then(|total| total.checked_add(band.female)).ok_or_else(error)?;
    }
    let valid_age_basis = if group.sex_only { unknown_age && group.bands.len() == 1 } else { known_ages[0] };
    if source_total == 0 || source_total != group.observed_total || !valid_age_basis {
        return Err(error());
    }
    Ok(())
}

#[derive(Serialize)]
pub struct CohortEvidence<'a> {
    pub opening_unit: &'a str,
    pub source_id: &'a str,
    pub observed_unit: &'a str,
    pub observed_date: &'a str,
    pub locator: &'a str,
    pub original_age_label: &'a str,
    pub observed_members: u64,
    pub observed_total: u64,
    pub opening_total: u64,
    pub method: &'a str,
    pub uncertainty: &'a str,
}

#[derive(Serialize)]
pub struct ResidentCohort<'a> {
    pub unit_id: &'a str,
    pub id: &'a CohortId,
    pub members: u64,
    pub sex: Option<CohortSex>,
    pub age_years: Option<AgeYears>,
    pub provenance: CohortProvenance,
    pub evidence: Option<CohortEvidence<'a>>,
}

#[derive(Serialize)]
pub struct PopulationStructure<'a> {
    pub population_total: u64,
    pub named_residents: u64,
    pub unclassified_residents: u64,
    pub cohort_residents: u64,
    pub residents_with_cohort_age_and_sex: u64,
    pub named_residents_with_cohort_sex: u64,
    pub cohorts: Vec<ResidentCohort<'a>>,
    pub published_energy_reference: EnergyReferenceCoverage,
    pub published_protein_reference: ProteinReferenceCoverage,
    pub published_adult_water_references: AdultWaterReferenceCoverage,
    pub published_efsa_water_reference: EfsaWaterReferenceCoverage,
    pub published_domestic_water_service_reference: DomesticWaterServiceReference,
}

#[derive(Default, Serialize)]
pub struct EnergyReferenceCoverage {
    pub people_with_reference: u64,
    pub people_without_reference: u64,
    pub conditional_kcal_per_day: Option<QuantityRange>,
}

#[derive(Serialize)]
pub struct ProteinReferenceCoverage {
    pub rate_source: NeedSource,
    pub weight_source: NeedSource,
    pub people_with_reference: u64,
    pub people_without_reference: u64,
    pub conditional_grams_per_day: Option<QuantityRange>,
}

#[derive(Default, Serialize)]
pub struct AdultWaterReferenceCoverage {
    pub adults_with_reference: u64,
    pub residents_outside_reference: u64,
    pub temperate_sedentary_litres_per_day: Option<QuantityRange>,
    pub warm_moderate_work_litres_per_day: Option<QuantityRange>,
}

#[derive(Serialize)]
pub struct EfsaWaterReferenceCoverage {
    pub source: NeedSource,
    pub people_with_reference: u64,
    pub people_without_reference: u64,
    pub moderate_environment_pal_1_6_total_ingested_litres_per_day: Option<QuantityRange>,
}

fn add_group_requirement(total: &mut Option<QuantityRange>, range: QuantityRange, members: u64) {
    let total = total.get_or_insert(QuantityRange { lower: 0.0, upper: 0.0 });
    total.lower += range.lower * members as f64;
    total.upper += range.upper * members as f64;
}

#[derive(Default, Serialize)]
pub struct AgeRangeCoverage {
    pub population_total: u64,
    pub definitely_in_range: u64,
    pub possibly_in_range_with_known_age: u64,
    pub age_unknown: u64,
}

impl PopulationStructure<'_> {
    /// Anonymous residents with age ranges. Named residents are reported
    /// separately and require the character roster for individual eligibility.
    pub fn count_ages(&self, youngest: u16, oldest: u16) -> Option<AgeRangeCoverage> {
        self.count_cohort_ages(youngest, oldest, |cohort| cohort.members)
    }

    pub(crate) fn count_cohort_ages(
        &self, youngest: u16, oldest: u16, members: impl Fn(&ResidentCohort<'_>) -> u64,
    ) -> Option<AgeRangeCoverage> {
        if youngest > oldest { return None; }
        let mut coverage = AgeRangeCoverage {
            population_total: self.unclassified_residents,
            age_unknown: self.unclassified_residents,
            ..AgeRangeCoverage::default()
        };
        for cohort in &self.cohorts {
            let count = members(cohort);
            coverage.population_total += count;
            let Some(ages) = cohort.age_years else {
                coverage.age_unknown += count;
                continue;
            };
            if ages.youngest <= oldest && ages.oldest.is_none_or(|max| max >= youngest) {
                coverage.possibly_in_range_with_known_age += count;
                if ages.youngest >= youngest && ages.oldest.is_some_and(|max| max <= oldest) {
                    coverage.definitely_in_range += count;
                }
            }
        }
        Some(coverage)
    }
}

impl Population {
    pub(crate) fn seed_opening_demography(&mut self) -> io::Result<()> {
        let Some(opening) = self.opening.clone() else { return Ok(()); };
        for group in &opening.demography.groups {
            let pools = opening.statistical_aggregates.get(&group.unit_id)
                .map_or(std::slice::from_ref(&group.unit_id), |scope| scope.members.as_slice());
            let mut pool_capacity = pools.iter().map(|unit| {
                let capacity = self.unclassified(unit).ok_or_else(|| invalid("missing demographic resident pool"))?;
                Ok((unit.as_str(), capacity))
            }).collect::<io::Result<Vec<_>>>()?;
            let available = pool_capacity.iter().map(|(_, count)| count).sum::<u64>();
            let classified = available.checked_sub(group.unclassified_opening_residents)
                .ok_or_else(|| invalid("historical unclassified population exceeds resident pool"))?;
            let denominator = u128::from(group.observed_total);
            let mut cells = Vec::new();
            for (index, band) in group.bands.iter().enumerate() {
                for (label, sex, observed) in [("f", CohortSex::Female, band.female), ("m", CohortSex::Male, band.male)] {
                    if observed == 0 { continue; }
                    let id = CohortId::new(&group.source_id, format!("{}:{}:{label}", group.unit_id, band.id))?;
                    let numerator = u128::from(observed) * u128::from(classified);
                    cells.push((numerator % denominator, id, index, sex, observed, (numerator / denominator) as u64));
                }
            }
            let remaining = classified - cells.iter().map(|cell| cell.5).sum::<u64>();
            cells.sort_unstable_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
            let mut capacity = available;
            for (rank, (_, id, index, sex, observed, rounded)) in cells.into_iter().enumerate() {
                let members = rounded + u64::from((rank as u64) < remaining);
                if members == 0 { continue; }
                let band = &group.bands[index];
                let birth_years = band.age_min.zip(band.age_max).map(|(min, max)| CohortBirthYears {
                    earliest: OPENING_YEAR - 1 - i64::from(max),
                    latest: OPENING_YEAR - i64::from(min),
                });
                let definition = CohortDefinition { provenance: CohortProvenance::ModelAllocation, sex: Some(sex), birth_years };
                self.cohort_definitions.insert(id.clone(), definition);
                self.cohort_sources.insert(id.clone(), SourceCell { group: Arc::clone(group), band_index: index, observed_members: observed });
                // Allocate each already-rounded cell across its remaining pool capacity.
                // Rounding cumulative shares preserves both cell totals and pool totals.
                let mut prefix = 0;
                let mut allocated = 0;
                for (unit, room) in &mut pool_capacity {
                    prefix += u128::from(*room);
                    let through = (prefix * u128::from(members) / u128::from(capacity)) as u64;
                    let assigned = through - allocated;
                    if assigned > 0 {
                        self.add_cohort_members(unit, &id, assigned);
                        *room -= assigned;
                    }
                    allocated = through;
                }
                capacity -= members;
            }
        }
        Ok(())
    }

    pub(super) fn cohort_describes_birth_year(&self, id: &CohortId, year: i64) -> bool {
        if let Some(source) = self.cohort_sources.get(id) {
            return source.describes_birth_year(year);
        }
        self.cohort_definitions.get(id).is_some_and(|definition| {
            definition.birth_years.is_none_or(|years| (years.earliest..=years.latest).contains(&year))
        })
    }

    pub(crate) fn cohort_can_materialize(&self, id: &CohortId, year: i64) -> bool {
        self.cohort_describes_birth_year(id, year)
    }

    pub fn global_total(&self) -> u64 {
        self.global_total
    }

    pub fn structure(&self, unit: Option<&str>, clock: GameClock) -> Option<PopulationStructure<'_>> {
        let population_total = match unit {
            Some(unit) => self.population_total(unit)?,
            None => self.global_total(),
        };
        let mut summary = PopulationStructure {
            population_total,
            named_residents: 0,
            unclassified_residents: 0,
            cohort_residents: 0,
            residents_with_cohort_age_and_sex: 0,
            named_residents_with_cohort_sex: self.named_cohorts.keys().filter(|person| {
                self.sex_for_person(person).is_some() && self.unit_for_person(person).is_some_and(|pool| {
                    unit.is_none_or(|unit| self.pool_in_scope(pool, unit))
                })
            }).count() as u64,
            cohorts: Vec::new(),
            published_energy_reference: EnergyReferenceCoverage::default(),
            published_protein_reference: ProteinReferenceCoverage {
                rate_source: NeedSource::WhoFaoUnuProtein2007,
                weight_source: NeedSource::FaoWhoUnuReferenceBodyWeight2004,
                people_with_reference: 0,
                people_without_reference: 0,
                conditional_grams_per_day: None,
            },
            published_adult_water_references: AdultWaterReferenceCoverage::default(),
            published_efsa_water_reference: EfsaWaterReferenceCoverage {
                source: NeedSource::EfsaWater2010,
                people_with_reference: 0,
                people_without_reference: 0,
                moderate_environment_pal_1_6_total_ingested_litres_per_day: None,
            },
            published_domestic_water_service_reference: published_domestic_water_service_reference(
                population_total,
            ),
        };
        for id in self.pools.keys().filter(|id| {
            unit.is_none_or(|unit| self.pool_in_scope(id, unit))
        }) {
            summary.named_residents += self.pool_named_counts.get(id).copied().unwrap_or(0);
            summary.unclassified_residents += self.unclassified(id).expect("known residence pool");
            for (cohort, definition, members) in self.cohorts_in(id) {
                let source = self.cohort_sources.get(cohort);
                let age_years = match source {
                    Some(source) => source.ages_at(clock),
                    None => definition.age_bounds(clock).and_then(|(min, max)| Some(AgeYears {
                        youngest: u16::try_from(min).ok()?,
                        oldest: Some(u16::try_from(max).ok()?),
                    })),
                };
                summary.cohort_residents += members;
                if age_years.is_some() && definition.sex.is_some() {
                    summary.residents_with_cohort_age_and_sex += members;
                }
                if let Requirement::Known { range, .. } = published_energy_reference(age_years, definition.sex) {
                    let energy = &mut summary.published_energy_reference;
                    add_group_requirement(&mut energy.conditional_kcal_per_day, range, members);
                    energy.people_with_reference += members;
                }
                if let Requirement::Known { range, .. } =
                    published_protein_reference(age_years, definition.sex)
                {
                    let protein = &mut summary.published_protein_reference;
                    add_group_requirement(&mut protein.conditional_grams_per_day, range, members);
                    protein.people_with_reference += members;
                }
                if let Some((temperate, warm_work)) = adult_water_references(age_years, definition.sex) {
                    let water = &mut summary.published_adult_water_references;
                    add_group_requirement(&mut water.temperate_sedentary_litres_per_day, temperate, members);
                    add_group_requirement(&mut water.warm_moderate_work_litres_per_day, warm_work, members);
                    water.adults_with_reference += members;
                }
                if let Requirement::Known { range, .. } =
                    published_efsa_water_reference(age_years, definition.sex)
                {
                    let water = &mut summary.published_efsa_water_reference;
                    add_group_requirement(
                        &mut water.moderate_environment_pal_1_6_total_ingested_litres_per_day,
                        range,
                        members,
                    );
                    water.people_with_reference += members;
                }
                summary.cohorts.push(ResidentCohort {
                    unit_id: id,
                    id: cohort,
                    members,
                    sex: definition.sex,
                    age_years,
                    provenance: definition.provenance,
                    evidence: source.map(SourceCell::evidence),
                });
            }
        }
        summary.published_energy_reference.people_without_reference =
            population_total - summary.published_energy_reference.people_with_reference;
        summary.published_protein_reference.people_without_reference =
            population_total - summary.published_protein_reference.people_with_reference;
        summary.published_adult_water_references.residents_outside_reference =
            population_total - summary.published_adult_water_references.adults_with_reference;
        summary.published_efsa_water_reference.people_without_reference =
            population_total - summary.published_efsa_water_reference.people_with_reference;
        Some(summary)
    }
}
