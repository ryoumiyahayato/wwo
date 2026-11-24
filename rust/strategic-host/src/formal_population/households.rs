use super::{Population, PopulationInspection, PopulationStructure};
use crate::{formal_bootstrap::InitialWorld, formal_clock::GameClock};
use serde::Serialize;

#[derive(Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum NeedPeriod {
    Day,
    Year,
    Occupancy,
}

#[derive(Serialize)]
pub struct HouseholdNeed {
    pub id: &'static str,
    pub commodity_id: Option<&'static str>,
    pub unit: String,
    pub period: NeedPeriod,
    pub quantity: f64,
    pub eligible_people: u64,
    pub unclassified_people: u64,
    pub basis: &'static str,
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
    /// Market units of the second staple per market unit of the first.
    pub second_per_first: f64,
    pub basis: &'static str,
}

#[derive(Serialize)]
pub struct HouseholdNeeds {
    pub residents: u64,
    pub needs: Vec<HouseholdNeed>,
    pub staples: &'static [StapleSubstitution],
}

#[derive(Clone, Copy)]
enum StapleProfile {
    Bread,
    Rice,
    Mixed,
}

fn staple_profile(root: &str) -> StapleProfile {
    match root {
        "country_fra" | "kingdom_of_belgium" => StapleProfile::Bread,
        "empire_of_japan" => StapleProfile::Rice,
        _ => StapleProfile::Mixed,
    }
}

impl Population {
    /// Project household requirements from current residents and an existing
    /// market catalogue. The catalogue callback returns units per person/day.
    pub fn household_needs<'catalogue>(
        &self,
        unit: Option<&str>,
        clock: GameClock,
        catalog_rate: impl Fn(&str) -> Option<HouseholdCommodity<'catalogue>>,
    ) -> Option<HouseholdNeeds> {
        let structure = self.structure(unit, clock)?;
        Some(self.household_needs_for(unit, &structure, catalog_rate))
    }

    pub(crate) fn household_needs_for<'catalogue>(
        &self,
        unit: Option<&str>,
        structure: &PopulationStructure<'_>,
        catalog_rate: impl Fn(&str) -> Option<HouseholdCommodity<'catalogue>>,
    ) -> HouseholdNeeds {
        let mut people = [0_u64; 3];
        match unit {
            Some(unit) => {
                let root = self.parent_unit(unit).or_else(|| {
                    let first = self.opening.as_ref()?.statistical_aggregates.get(unit)?.members.first()?;
                    self.parent_unit(first)
                }).unwrap_or(unit);
                people[staple_profile(root) as usize] = structure.population_total;
            }
            None => {
                for (root, &population) in self.totals().iter().chain(self.standalone_totals()) {
                    people[staple_profile(root) as usize] += population;
                }
            }
        }
        let total = structure.population_total;
        let mut child_food_factor = [0.0; 3];
        let mut food_age_unknown = structure.named_residents + structure.unclassified_residents;
        for cohort in &structure.cohorts {
            if let Some(age) = cohort.age_years {
                // These are adult-equivalent scenario weights. Wide source
                // bands straddling a threshold retain the default factor.
                let factor = match age.oldest {
                    Some(0..=4) => 0.5,
                    Some(5..=14) => 0.75,
                    _ => 1.0,
                };
                let profile = staple_profile(self.parent_unit(cohort.unit_id).unwrap_or(cohort.unit_id));
                child_food_factor[profile as usize] += (1.0 - factor) * cohort.members as f64;
                if (age.youngest <= 4 && age.oldest.is_none_or(|max| max > 4))
                    || (age.youngest <= 14 && age.oldest.is_none_or(|max| max > 14))
                {
                    food_age_unknown += cohort.members;
                }
            } else {
                food_age_unknown += cohort.members;
            }
        }
        let adult_equivalent = std::array::from_fn::<_, 3, _>(|i| {
            (people[i] as f64 - child_food_factor[i]).max(0.0)
        });
        let mut needs = Vec::new();
        let mut commodity = |id, unit: &str, period, quantity, basis, unclassified_people| {
            needs.push(HouseholdNeed {
                id, commodity_id: Some(id), unit: unit.into(), period, quantity,
                eligible_people: total, unclassified_people, basis,
            });
        };
        // Finished staples only. Milling and baking inputs belong to production.
        // Values are kg per adult equivalent/day and converted to market tonnes.
        const STAPLES: &[(&str, [f64; 3])] = &[
            ("bread", [0.36, 0.015, 0.22]),
            ("rice", [0.015, 0.36, 0.095]),
            ("maize", [0.015, 0.025, 0.085]),
            ("potatoes", [0.24, 0.10, 0.15]),
        ];
        for &(id, rates) in STAPLES {
            if let Some(good) = catalog_rate(id).filter(|good| good.mass_kg > 0) {
                let kg = rates.iter().zip(adult_equivalent).map(|(rate, people)| rate * people).sum::<f64>();
                commodity(id, good.unit, NeedPeriod::Day, kg / f64::from(good.mass_kg),
                    "staple_scenarios_1900", food_age_unknown);
            }
        }
        for id in ["pulses", "meat", "fish", "milk", "butter", "vegetable_oil", "sugar", "salt",
            "preserved_food", "coffee", "tea", "cocoa", "tobacco", "fine_wine_spirits",
            "coal", "kerosene", "candles_matches", "soap", "paper"] {
            if let Some(good) = catalog_rate(id) {
                let food = matches!(id,
                    "pulses" | "meat" | "fish" | "milk" | "butter" | "vegetable_oil"
                    | "sugar" | "salt" | "preserved_food");
                let people = if food { adult_equivalent.iter().sum() } else { total as f64 };
                commodity(id, good.unit, NeedPeriod::Day, good.daily_units_per_person * people, "market_catalogue_reference_1900",
                    if food { food_age_unknown } else { 0 });
            }
        }
        for id in ["clothing", "leather_goods", "fine_clothing", "silk_goods",
            "jewelry_watches", "porcelain_fine_glass", "perfume_cosmetics"] {
            if let Some(good) = catalog_rate(id) {
                commodity(id, good.unit, NeedPeriod::Year, good.daily_units_per_person * total as f64 * 365.0,
                    "market_catalogue_reference_1900", 0);
            }
        }
        let mut service = |id, unit: &str, period, quantity, eligible_people, unclassified_people| {
            needs.push(HouseholdNeed { id, commodity_id: None, unit: unit.into(), period, quantity,
                eligible_people, unclassified_people, basis: "household_planning_scenario" });
        };
        service("domestic_water", "L", NeedPeriod::Day, 12.0 * total as f64, total, 0);
        service("occupied_housing_space", "m²", NeedPeriod::Occupancy, 8.0 * total as f64, total, 0);
        service("occupied_dwellings", "dwellings", NeedPeriod::Occupancy, (total as f64 / 5.0).ceil(), total, 0);
        service("basic_care", "visits", NeedPeriod::Year, total as f64, total, 0);
        let (school, age_unknown) = age_scenario(structure, 6, 12);
        service("primary_school_places", "places", NeedPeriod::Occupancy, school as f64, school, age_unknown);
        let (working, age_unknown) = age_scenario(structure, 15, 64);
        service("local_passenger_trips", "trips", NeedPeriod::Year, 12.0 * working as f64, working, age_unknown);
        HouseholdNeeds {
            residents: total,
            needs,
            staples: &[
                StapleSubstitution { first: "bread", second: "rice", second_per_first: 0.72, basis: "food_energy_reference" },
                StapleSubstitution { first: "bread", second: "potatoes", second_per_first: 3.55, basis: "food_energy_reference" },
            ],
        }
    }
}

fn age_scenario(structure: &PopulationStructure<'_>, min: u16, max: u16) -> (u64, u64) {
    let mut eligible = 0.0;
    let mut unclassified = structure.unclassified_residents + structure.named_residents;
    for cohort in &structure.cohorts {
        match cohort.age_years.map(|age| (age.youngest, age.oldest)) {
            Some((youngest, _)) if youngest > max => {}
            Some((youngest, Some(oldest))) => {
                let first = min.max(youngest);
                let last = max.min(oldest);
                if first <= last {
                    let ratio = (f64::from(last - first) + 1.0)
                        / (f64::from(oldest - youngest) + 1.0);
                    eligible += cohort.members as f64 * ratio;
                }
            }
            _ => unclassified += cohort.members,
        }
    }
    (eligible.round() as u64, unclassified)
}

impl InitialWorld {
    pub fn population_household_needs(&self, report: &PopulationInspection<'_>) -> Option<HouseholdNeeds> {
        let structure = report.structure.as_ref()?;
        Some(self.population().household_needs_for(report.account_id, structure,
            |good| self.macro_economy().household_catalogue_rate(good)))
    }
}
