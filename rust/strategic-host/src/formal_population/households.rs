
use super::{profiles::Region, Population, PopulationInspection, PopulationStructure, SocialDistribution};
use crate::{formal_bootstrap::InitialWorld, formal_clock::GameClock};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum NeedPeriod { Day, Year, Occupancy }

#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum NeedTier { Survival, Ordinary, Improvement }

#[derive(Clone, Serialize)]
pub struct HouseholdNeed {
    pub id: &'static str,
    pub commodity_id: Option<&'static str>,
    pub unit: String,
    pub period: NeedPeriod,
    pub tier: NeedTier,
    pub quantity: f64,
    pub eligible_people: u64,
}

pub struct HouseholdCommodity<'a> {
    pub unit: &'a str,
    pub mass_kg: u32,
    pub daily_units_per_person: f64,
}

#[derive(Serialize)]
pub struct StapleSubstitution {
    pub first: &'static str,
    pub second: &'static str,
    pub second_per_first: f64,
    pub basis: &'static str,
}

#[derive(Serialize)]
pub struct ClassNeeds {
    pub class: String,
    pub residents: u64,
    pub needs: Vec<HouseholdNeed>,
}

#[derive(Serialize)]
pub struct HouseholdNeeds {
    pub residents: u64,
    pub needs: Vec<HouseholdNeed>,
    pub by_class: Vec<ClassNeeds>,
    pub unclassified_residents: u64,
    pub unclassified_needs: Vec<HouseholdNeed>,
    pub age_unclassified_residents: u64,
    pub basis: &'static str,
    pub staples: &'static [StapleSubstitution],
}

#[derive(Default)]
struct Residents {
    total: u64,
    age_dist: [f64; 6],
}

impl Residents {
    fn age_known(&self) -> f64 { self.age_dist.iter().sum() }
    fn adults_equivalent(&self) -> f64 {
        self.age_dist.iter().zip([0.49, 0.68, 0.86, 1.0, 1.05, 0.87])
            .map(|(count, factor)| count * factor).sum::<f64>() +
            (self.total as f64 - self.age_known()).max(0.0) * 0.89
    }
}

impl Population {
    pub fn household_needs<'a>(
        &self, unit: Option<&str>, clock: GameClock,
        catalog_rate: impl Fn(&str) -> Option<HouseholdCommodity<'a>>,
    ) -> Option<HouseholdNeeds> {
        Some(self.household_needs_for(unit, &self.structure(unit, clock)?,
            self.social_distribution(unit).as_ref(), catalog_rate))
    }

    pub(crate) fn household_needs_for<'a>(
        &self, unit: Option<&str>, structure: &PopulationStructure<'_>,
        social: Option<&SocialDistribution<'_>>,
        catalog_rate: impl Fn(&str) -> Option<HouseholdCommodity<'a>>,
    ) -> HouseholdNeeds {
        let mut segments = BTreeMap::<_, Residents>::new();
        for (pool, &people) in &self.pools {
            if people > 0 && unit.is_none_or(|scope| self.pool_in_scope(pool, scope)) {
                segments.entry(self.household_profile(pool)).or_default().total += people;
            }
        }
        for cohort in &structure.cohorts {
            let Some(age) = cohort.age_years else { continue; };
            let Some(segment) = segments.get_mut(&self.household_profile(cohort.unit_id)) else { continue; };
            for ((first, last), members) in [(0, 4), (5, 12), (13, 17), (18, 34), (35, 64), (65, 150)]
                .into_iter().zip(&mut segment.age_dist)
            {
                *members += age_share(age.youngest, age.oldest, first, last) * cohort.members as f64;
            }
        }
        let total = structure.population_total;
        let restrictive_share = marginal_share(social, "religion", |label| {
            let name = label.to_ascii_lowercase();
            ["muslim", "moslem", "islam", "mohammed", "jewish", "judaism", "hebrew"]
                .iter().any(|part| name.contains(part))
        });
        let heavy_work = marginal_share(social, "occupation", |label| {
            let name = label.to_ascii_lowercase();
            ["agric", "mining", "fishing", "manufactur", "industrie", "industria"]
                .iter().any(|part| name.contains(part))
        });
        // A marginal affiliation permits a sensitivity adjustment, with partial observance.
        let food_adjustments = (1. + 0.16 * heavy_work, 0.65 * restrictive_share);
        let mut base = BTreeMap::<_, HouseholdNeed>::new();
        for ((region, urban), people) in &segments {
            for row in regional_basket(*region, *urban, people, food_adjustments, &catalog_rate) {
                base.entry(row.id).and_modify(|total| {
                    total.quantity += row.quantity;
                    total.eligible_people += row.eligible_people;
                }).or_insert(row);
            }
        }
        let mut needs: Vec<_> = base.into_values().collect();
        needs.sort_by_key(|need| (need.tier as u8, need.id));
        let mut classes = BTreeMap::<&str, u64>::new();
        if let Some(dimension) = social.and_then(|social| social.dimensions.get("class")) {
            for (&classification, rows) in &dimension.by_classification {
                // Industrial position and property declaration alone do not establish household means.
                if classification != "opening_household_class_scenario_v44" { continue; }
                for (&class, &count) in rows {
                    *classes.entry(class).or_default() += count;
                }
            }
        }
        let unclassified_residents = total - classes.values().sum::<u64>();
        let mut by_class: Vec<_> = classes.into_iter().map(|(class, residents)| ClassNeeds {
            class: class.into(), residents, needs: Vec::with_capacity(needs.len()),
        }).collect();
        let mut unclassified_needs = Vec::with_capacity(needs.len());
        for need in &mut needs {
            let mut total_quantity = 0.;
            for class in &mut by_class {
                let share = class.residents as f64 / total as f64;
                let mut row = need.clone();
                row.quantity *= share * household_class_factor(&class.class, row.tier);
                row.eligible_people = (row.eligible_people as f64 * share).round() as u64;
                total_quantity += row.quantity;
                class.needs.push(row);
            }
            let unknown_share = unclassified_residents as f64 / total.max(1) as f64;
            let mut unclassified = need.clone();
            unclassified.quantity *= unknown_share;
            unclassified.eligible_people = (unclassified.eligible_people as f64 * unknown_share).round() as u64;
            total_quantity += unclassified.quantity;
            unclassified_needs.push(unclassified);
            need.quantity = total_quantity;
        }
        HouseholdNeeds {
            residents: total, needs, by_class, unclassified_residents, unclassified_needs,
            age_unclassified_residents: total.saturating_sub(segments.values().map(Residents::age_known).sum::<f64>().round() as u64),
            basis: "regional_household_budget_v44; age distribution and social marginals adjusted independently; class assumes scope age mix; no effective demand or recorded use",
            staples: &[
                StapleSubstitution { first: "bread", second: "rice", second_per_first: 0.72, basis: "equal_staple_energy" },
                StapleSubstitution { first: "bread", second: "potatoes", second_per_first: 3.34, basis: "equal_staple_energy" },
                StapleSubstitution { first: "flour", second: "maize", second_per_first: 1.0, basis: "equal_staple_energy" },
            ],
        }
    }
}

fn marginal_share(social: Option<&SocialDistribution<'_>>, key: &str, applies: impl Fn(&str) -> bool) -> f64 {
    let Some(social) = social else { return 0.; };
    let count: u64 = social.dimensions.get(key).into_iter().flat_map(|dimension| dimension.by_classification.values())
        .flat_map(|rows| rows.iter()).filter(|(label, _)| applies(label)).map(|(_, &count)| count).sum();
    count as f64 / social.population_total.max(1) as f64
}

fn household_class_factor(class: &str, tier: NeedTier) -> f64 {
    let (ordinary, improvement) = match class {
        "Manual and service households" => (0.81, 0.23),
        "Smallholder and self-employed households" => (0.90, 0.40),
        "Salaried and professional households" => (1.20, 1.52),
        "Proprietor and rentier households" => (1.52, 3.80),
        _ => (1.0, 1.0),
    };
    match tier { NeedTier::Survival => 1.0, NeedTier::Ordinary => ordinary, NeedTier::Improvement => improvement }
}

fn regional_basket<'a>(
    region: Region, urban: bool, people: &Residents, (work, restricted): (f64, f64),
    catalogue: &impl Fn(&str) -> Option<HouseholdCommodity<'a>>,
) -> Vec<HouseholdNeed> {
    use NeedPeriod::*;
    use NeedTier::*;
    let total = people.total as f64;
    let food = people.adults_equivalent();
    let (cold, marketed_fuel) = region.fuel();
    let urban_factor = if urban { 1.25 } else { 0.85 };
    let seafood = match region {
        Region::EastAsia | Region::TropicalAsia => 2.1,
        Region::NorthChina | Region::Continental | Region::SouthAsia => 0.55,
        _ => 1.0,
    };
    let dairy = match region {
        Region::EastAsia | Region::TropicalAsia | Region::SouthChina => 0.24,
        Region::Atlantic | Region::Continental | Region::NorthAmerica => 1.35,
        _ => 0.8,
    };
    let tea = match region {
        Region::EastAsia | Region::NorthChina | Region::SouthChina | Region::SouthAsia => 1.9,
        Region::LatinAmerica | Region::Mediterranean => 0.40,
        _ => 0.85,
    };
    let mut rows = Vec::new();
    let mut commodity = |id, period, tier, physical, mass| {
        if let Some(good) = catalogue(id) {
            let quantity = if mass {
                if good.mass_kg == 0 { return; }
                physical / f64::from(good.mass_kg)
            } else { physical };
            if quantity > 0. {
                rows.push(HouseholdNeed { id, commodity_id: Some(id), unit: good.unit.into(),
                    period, tier, quantity, eligible_people: people.total });
            }
        }
    };
    let mut staples = region.staples();
    // Home baking uses flour energy transferred from finished bread; there is one staple budget.
    if !urban {
        let home_baking = staples[0] * 0.15;
        staples[0] -= home_baking;
        staples[1] += home_baking;
    }
    for ((id, kcal_per_kg), share) in [("bread", 2570.), ("flour", 3640.), ("rice", 3560.),
        ("maize", 3640.), ("potatoes", 770.), ("rye", 3380.)].into_iter().zip(staples)
    {
        commodity(id, Day, Survival, 1480. * food * work * share / kcal_per_kg, true);
    }
    for (id, kg, tier) in [
        ("pulses", 0.050 * (1. + restricted * 0.26), Survival),
        ("meat", 0.067 * urban_factor * (1. - restricted * 0.21), Ordinary),
        ("fish", 0.027 * seafood * (1. + restricted * 0.22), Ordinary),
        ("milk", 0.135 * dairy, Ordinary), ("butter", 0.009 * dairy, Ordinary),
        ("vegetable_oil", 0.023 * (1.1 - dairy * 0.18), Survival),
        ("salt", 0.010, Survival), ("sugar", 0.029 * urban_factor, Ordinary),
        ("preserved_food", 0.012 * urban_factor, Ordinary),
        ("tea", 0.0032 * tea, Ordinary), ("coffee", 0.006 * (1.5 - tea * 0.44), Ordinary),
        ("cocoa", 0.0011 * urban_factor, Improvement),
        ("tobacco", 0.002 * urban_factor, Improvement),
        ("fine_wine_spirits", 0.012 * urban_factor * (1. - restricted * 0.61), Improvement),
        ("coal", (0.24 + cold * 0.42) * (marketed_fuel * urban_factor).min(0.92), Survival),
        ("kerosene", 0.016 * (1. - marketed_fuel * 0.40), Ordinary),
        ("candles_matches", 0.0025, Ordinary),
        ("soap", 0.0085 * urban_factor, Ordinary), ("paper", 0.0066 * urban_factor, Ordinary),
    ] {
        commodity(id, Day, tier, kg * food, true);
    }
    for (id, rate, items_per_unit, tier) in [
        ("clothing", 1.55 + cold * 0.55, 1000., Ordinary), ("leather_goods", 0.55 + cold * 0.10, 1000., Ordinary),
        ("fine_clothing", 0.12 * urban_factor, 100., Improvement), ("silk_goods", 0.025 * urban_factor, 100., Improvement),
        ("jewelry_watches", 0.022, 100., Improvement), ("porcelain_fine_glass", 0.14, 100., Improvement),
        ("perfume_cosmetics", 0.092, 100., Improvement), ("cigars", 0.62 * urban_factor, 1_000_000., Improvement),
    ] {
        commodity(id, Year, tier, rate * total / items_per_unit, false);
    }
    if urban && matches!(region, Region::Atlantic | Region::Continental | Region::NorthAmerica) {
        commodity("electricity_service", Year, Improvement, 0.002 * total, false);
    }
    let school_age = people.age_dist[1];
    let adults = people.age_dist[3] + people.age_dist[4];
    let household_size = if urban { 4.7 } else { 5.6 };
    let mut service = |id, unit: &str, period, tier, quantity, eligible| {
        rows.push(HouseholdNeed { id, commodity_id: None, unit: unit.into(), period, tier, quantity,
            eligible_people: eligible });
    };
    service("domestic_water", "L", Day, Survival, (10. + urban_factor * 4.) * total, people.total);
    service("vegetables", "kg", Day, Survival, 0.12 * food, people.total);
    service("wood_fuel", "kg", Day, Survival, (0.48 + cold * 0.9) * (1. - (marketed_fuel * urban_factor).min(0.92)) * total, people.total);
    service("occupied_housing_space", "m²", Occupancy, Ordinary, (7. + 2.1 * urban_factor) * total, people.total);
    service("occupied_dwellings", "dwellings", Occupancy, Survival, total / household_size, people.total);
    service("basic_care", "visits", Year, Ordinary, 0.72 * total + 0.6 * (people.age_dist[0] + people.age_dist[5]), people.total);
    service("primary_school_places", "places", Occupancy, Ordinary, school_age * if urban { 0.73 } else { 0.52 }, school_age.round() as u64);
    service("local_passenger_trips", "trips", Year, Ordinary, adults * if urban { 51. } else { 14. }, adults.round() as u64);
    service("household_furnishings", "items", Year, Improvement, total / household_size * 0.6, people.total);
    rows
}

/// Uniform age only within a source band. For open ranges use 100 as a working upper
/// bound, or the source minimum when it is already above 100.
pub(super) fn age_share(youngest: u16, oldest: Option<u16>, first: u16, last: u16) -> f64 {
    let oldest = oldest.unwrap_or(youngest.max(100));
    let overlap = oldest.min(last).saturating_add(1).saturating_sub(youngest.max(first));
    f64::from(overlap) / (f64::from(oldest - youngest) + 1.)
}

impl InitialWorld {
    pub fn population_household_needs(&self, report: &PopulationInspection<'_>) -> Option<HouseholdNeeds> {
        self.population_household_needs_with_social(report, self.population().social_distribution(report.account_id).as_ref())
    }

    pub fn population_household_needs_with_social(
        &self, report: &PopulationInspection<'_>, social: Option<&SocialDistribution<'_>>,
    ) -> Option<HouseholdNeeds> {
        let structure = report.structure.as_ref()?;
        Some(self.population().household_needs_for(report.account_id, structure, social,
            |good| self.macro_economy().household_catalogue_rate(good)))
    }
}
