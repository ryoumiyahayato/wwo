//! Conditional physiological estimates and food energy references.

use serde::Serialize;

use super::CohortSex;

/// Complete years, with inclusive endpoints. An absent upper endpoint is open.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct AgeYears {
    pub youngest: u16,
    pub oldest: Option<u16>,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct QuantityRange {
    pub lower: f64,
    pub upper: f64,
}

impl QuantityRange {
    fn point(value: f64) -> Self {
        Self {
            lower: value,
            upper: value,
        }
    }

    fn is_valid(self) -> bool {
        self.lower.is_finite()
            && self.upper.is_finite()
            && 0.0 < self.lower
            && self.lower <= self.upper
    }

    fn envelope(self, other: Self) -> Self {
        Self {
            lower: self.lower.min(other.lower),
            upper: self.upper.max(other.upper),
        }
    }

    fn scaled(self, other: Self) -> Self {
        Self {
            lower: self.lower * other.lower,
            upper: self.upper * other.upper,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ActivityLevel {
    Light,
    Moderate,
    Vigorous,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WaterConditions {
    /// Sedentary in a temperate climate.
    Temperate,
    /// Moderate work for a typical 6.5 hours at 28–32 °C.
    ModerateWorkInWarmClimate,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct PhysiologicalInputs {
    pub age_years: Option<AgeYears>,
    pub sex: Option<CohortSex>,
    /// Group mean body weight, or evidenced bounds on that mean.
    pub weight_kg: Option<QuantityRange>,
    pub activity: Option<ActivityLevel>,
    pub water_conditions: Option<WaterConditions>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum NeedSource {
    FaoWhoUnuEnergy2004,
    FaoWhoUnuEnergyReference2004,
    WhoFaoUnuProtein2007,
    WhoWater2020,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum UnknownNeed {
    MissingAge,
    InvalidAgeRange,
    InfantAgeInMonthsAndFeedingRequired,
    MissingWeight,
    InvalidWeightRange,
    WeightOutsideModel,
    MissingActivity,
    UnsupportedActivityForAge,
    MissingWaterConditions,
    UnsupportedWaterAge,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Requirement {
    Known {
        range: QuantityRange,
        source: NeedSource,
    },
    Unknown(UnknownNeed),
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct PhysiologicalRequirements {
    /// Healthy baseline for a population group. Pregnancy and lactation adjustments are separate.
    pub energy_kcal_per_day: Requirement,
    /// Average dietary protein requirement for a healthy baseline group.
    pub protein_grams_per_day: Requirement,
    /// Water ingested from food and beverages combined.
    pub total_ingested_water_litres_per_day: Requirement,
}

/// WHO (2020) safe drinking-water access target in litres per person per day.
pub const WHO_SAFE_WATER_ACCESS_LITRES_PER_DAY: f64 = 5.3;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FoodEnergySource {
    UsdaBulletin28WheatBreadReference,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct FoodEnergyEstimate {
    /// Total food energy for the recorded mass.
    pub kcal: QuantityRange,
    pub source: FoodEnergySource,
}

/// Energy reference for food recorded as consumed. An unspecified product or
/// preparation has no estimate.
pub fn recorded_food_energy(good: &str, consumed_kg: f64) -> Option<FoodEnergyEstimate> {
    if good != "bread" || !consumed_kg.is_finite() || consumed_kg <= 0.0 {
        return None;
    }

    // USDA Bulletin 28 (1906 revision), p. 61, as-purchased sample averages:
    // whole wheat bread and white bread (all analyses), in kcal per pound.
    let consumed_pounds = consumed_kg / 0.453_592_37;
    let kcal = QuantityRange {
        lower: 1_140.0 * consumed_pounds,
        upper: 1_215.0 * consumed_pounds,
    };
    kcal.is_valid().then_some(FoodEnergyEstimate {
        kcal,
        source: FoodEnergySource::UsdaBulletin28WheatBreadReference,
    })
}

pub fn physiological_requirements(input: PhysiologicalInputs) -> PhysiologicalRequirements {
    PhysiologicalRequirements {
        energy_kcal_per_day: requirement(energy(input, false), NeedSource::FaoWhoUnuEnergy2004),
        protein_grams_per_day: requirement(protein(input), NeedSource::WhoFaoUnuProtein2007),
        total_ingested_water_litres_per_day: requirement(water(input), NeedSource::WhoWater2020),
    }
}

/// Published healthy reference scenario for the supplied age bounds. The result
/// spans supported activity classes and uses published comparison weights.
pub fn published_energy_reference(
    age_years: Option<AgeYears>,
    sex: Option<CohortSex>,
) -> Requirement {
    let input = PhysiologicalInputs {
        age_years,
        sex,
        ..PhysiologicalInputs::default()
    };
    requirement(
        energy(input, true),
        NeedSource::FaoWhoUnuEnergyReference2004,
    )
}

fn requirement(range: Result<QuantityRange, UnknownNeed>, source: NeedSource) -> Requirement {
    match range {
        Ok(range) => Requirement::Known { range, source },
        Err(reason) => Requirement::Unknown(reason),
    }
}

fn age_classes(
    age: Option<AgeYears>,
    last_class: u16,
) -> Result<std::ops::RangeInclusive<u16>, UnknownNeed> {
    let age = age.ok_or(UnknownNeed::MissingAge)?;
    let oldest = age.oldest.unwrap_or(u16::MAX);
    if oldest < age.youngest {
        return Err(UnknownNeed::InvalidAgeRange);
    }
    Ok(age.youngest.min(last_class)..=oldest.min(last_class))
}

fn weight(input: PhysiologicalInputs) -> Result<QuantityRange, UnknownNeed> {
    let weight = input.weight_kg.ok_or(UnknownNeed::MissingWeight)?;
    if !weight.is_valid() {
        return Err(UnknownNeed::InvalidWeightRange);
    }
    Ok(weight)
}

fn sexes(sex: Option<CohortSex>) -> &'static [CohortSex] {
    match sex {
        Some(CohortSex::Female) => &[CohortSex::Female],
        Some(CohortSex::Male) => &[CohortSex::Male],
        None => &[CohortSex::Female, CohortSex::Male],
    }
}

fn energy(
    input: PhysiologicalInputs,
    published_reference: bool,
) -> Result<QuantityRange, UnknownNeed> {
    let ages = age_classes(input.age_years, 60)?;
    if *ages.start() == 0 {
        return Err(UnknownNeed::InfantAgeInMonthsAndFeedingRequired);
    }
    let supplied_weight = if published_reference {
        None
    } else {
        Some(weight(input)?)
    };
    let mut result: Option<QuantityRange> = None;
    for &sex in sexes(input.sex) {
        for age in ages.clone() {
            let estimate = if age < 18 {
                child_energy(age, sex, input.activity, supplied_weight)?
            } else {
                let body_weight = supplied_weight.unwrap_or_else(|| {
                    QuantityRange::point(match sex {
                        CohortSex::Female => 55.0,
                        CohortSex::Male => 60.0,
                    })
                });
                adult_energy(age, sex, body_weight, input.activity, published_reference)?
            };
            if !estimate.is_valid() {
                return Err(UnknownNeed::WeightOutsideModel);
            }
            result = Some(result.map_or(estimate, |range| range.envelope(estimate)));
        }
    }
    Ok(result.expect("validated age range and sex profiles are nonempty"))
}

fn child_energy(
    age: u16,
    sex: CohortSex,
    activity: Option<ActivityLevel>,
    body_weight: Option<QuantityRange>,
) -> Result<QuantityRange, UnknownNeed> {
    // FAO (2004), tables 4.2 and 4.3. Rows cover ages 1–2 through 17–18.
    let (reference, growth, (base, linear, square)) = match sex {
        CohortSex::Female => (
            [
                865, 1047, 1156, 1241, 1330, 1428, 1554, 1698, 1854, 2006, 2149, 2276, 2379, 2449,
                2491, 2503, 2503,
            ],
            [
                14, 12, 11, 10, 10, 13, 17, 21, 23, 25, 25, 26, 24, 19, 12, 5, 0,
            ],
            (263.4, 65.3, 0.454),
        ),
        CohortSex::Male => (
            [
                948, 1129, 1252, 1360, 1467, 1573, 1692, 1830, 1978, 2150, 2341, 2548, 2770, 2990,
                3178, 3322, 3410,
            ],
            [
                14, 11, 12, 11, 11, 12, 14, 16, 18, 22, 25, 29, 33, 33, 30, 24, 15,
            ],
            (310.2, 63.3, 0.263),
        ),
    };
    let row = usize::from(age - 1);
    let energy = if let Some(body_weight) = body_weight {
        // The fitted curve is only used on its increasing branch.
        if body_weight.upper > linear / (2.0 * square) {
            return Err(UnknownNeed::WeightOutsideModel);
        }
        let estimate = |kg| {
            let expenditure = base + linear * kg - square * kg * kg;
            let age_adjustment = if age == 1 { 0.93 } else { 1.0 };
            expenditure * age_adjustment + f64::from(growth[row])
        };
        QuantityRange {
            lower: estimate(body_weight.lower),
            upper: estimate(body_weight.upper),
        }
    } else {
        QuantityRange::point(f64::from(reference[row]))
    };
    let activity_factor = match (age, activity, body_weight.is_none()) {
        (1..=5, Some(ActivityLevel::Light | ActivityLevel::Vigorous), _) => {
            return Err(UnknownNeed::UnsupportedActivityForAge);
        }
        (1..=5, _, _) | (_, Some(ActivityLevel::Moderate), _) => QuantityRange::point(1.0),
        (_, Some(ActivityLevel::Light), _) => QuantityRange::point(0.85),
        (_, Some(ActivityLevel::Vigorous), _) => QuantityRange::point(1.15),
        (_, None, true) => QuantityRange {
            lower: 0.85,
            upper: 1.15,
        },
        (_, None, false) => return Err(UnknownNeed::MissingActivity),
    };
    Ok(energy.scaled(activity_factor))
}

fn adult_energy(
    age: u16,
    sex: CohortSex,
    body_weight: QuantityRange,
    activity: Option<ActivityLevel>,
    published_reference: bool,
) -> Result<QuantityRange, UnknownNeed> {
    // Schofield equations and activity ranges retained by FAO (2004), tables 5.2 and 5.3.
    let (slope, intercept) = match (sex, age) {
        (CohortSex::Female, 18..=29) => (14.818, 486.6),
        (CohortSex::Female, 30..=59) => (8.126, 845.6),
        (CohortSex::Female, _) => (9.082, 658.5),
        (CohortSex::Male, 18..=29) => (15.057, 692.2),
        (CohortSex::Male, 30..=59) => (11.472, 873.1),
        (CohortSex::Male, _) => (11.711, 587.7),
    };
    let bmr = QuantityRange {
        lower: slope * body_weight.lower + intercept,
        upper: slope * body_weight.upper + intercept,
    };
    let activity = match activity {
        Some(ActivityLevel::Light) => QuantityRange {
            lower: 1.40,
            upper: 1.69,
        },
        Some(ActivityLevel::Moderate) => QuantityRange {
            lower: 1.70,
            upper: 1.99,
        },
        Some(ActivityLevel::Vigorous) => QuantityRange {
            lower: 2.00,
            upper: 2.40,
        },
        None if published_reference => QuantityRange {
            lower: 1.40,
            upper: 2.40,
        },
        None => return Err(UnknownNeed::MissingActivity),
    };
    Ok(bmr.scaled(activity))
}

fn protein(input: PhysiologicalInputs) -> Result<QuantityRange, UnknownNeed> {
    let ages = age_classes(input.age_years, 19)?;
    if *ages.start() == 0 {
        return Err(UnknownNeed::InfantAgeInMonthsAndFeedingRequired);
    }
    let body_weight = weight(input)?;
    // Mean grams per kilogram per day, WHO TRS 935, section 7 and tables 33a–b.
    let children = [
        0.95_f64, 0.79, 0.73, 0.69, 0.69, 0.72, 0.74, 0.75, 0.75, 0.75,
    ];
    let girls = [0.73_f64, 0.72, 0.71, 0.70, 0.69, 0.68, 0.67, 0.66];
    let boys = [0.75_f64, 0.74, 0.73, 0.72, 0.72, 0.71, 0.70, 0.69];
    let mut rate = QuantityRange {
        lower: f64::INFINITY,
        upper: 0.0,
    };
    for &sex in sexes(input.sex) {
        for age in ages.clone() {
            let value = match (sex, age) {
                (_, 1..=10) => children[usize::from(age - 1)],
                (CohortSex::Female, 11..=18) => girls[usize::from(age - 11)],
                (CohortSex::Male, 11..=18) => boys[usize::from(age - 11)],
                _ => 0.66,
            };
            // The 1.5-year reference is between the age 1 and age 2 values.
            let lower = if age == 1 { 0.79 } else { value };
            rate = rate.envelope(QuantityRange {
                lower,
                upper: value,
            });
        }
    }
    let estimate = body_weight.scaled(rate);
    if !estimate.is_valid() {
        return Err(UnknownNeed::WeightOutsideModel);
    }
    Ok(estimate)
}

fn water(input: PhysiologicalInputs) -> Result<QuantityRange, UnknownNeed> {
    if *age_classes(input.age_years, 18)?.start() < 18 {
        return Err(UnknownNeed::UnsupportedWaterAge);
    }
    // WHO (2020), table 7. The warm-work estimate is the published scenario median.
    match input
        .water_conditions
        .ok_or(UnknownNeed::MissingWaterConditions)?
    {
        WaterConditions::Temperate => Ok(match input.sex {
            Some(CohortSex::Female) => QuantityRange::point(2.7),
            Some(CohortSex::Male) => QuantityRange::point(3.2),
            None => QuantityRange {
                lower: 2.7,
                upper: 3.2,
            },
        }),
        WaterConditions::ModerateWorkInWarmClimate => Ok(QuantityRange::point(4.6)),
    }
}
