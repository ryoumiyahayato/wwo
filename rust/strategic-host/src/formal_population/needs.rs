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
    FaoWhoUnuReferenceBodyWeight2004,
    WhoFaoUnuProtein2007,
    WhoWater2020,
    WhoDomesticWaterService2020,
    EfsaWater2010,
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

#[derive(Serialize)]
pub struct DomesticWaterServiceReference {
    pub source: NeedSource,
    pub scenario_population: u64,
    pub basic_access_litres_per_day: f64,
    pub intermediate_access_litres_per_day: f64,
}

/// Alternative household water-use volumes at two hypothetical access levels.
pub(super) fn published_domestic_water_service_reference(
    population: u64,
) -> DomesticWaterServiceReference {
    // WHO (2020), tables S1 and 11, typical use in litres per person per day.
    DomesticWaterServiceReference {
        source: NeedSource::WhoDomesticWaterService2020,
        scenario_population: population,
        basic_access_litres_per_day: 20.0 * population as f64,
        intermediate_access_litres_per_day: 50.0 * population as f64,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FoodEnergySource {
    UsdaBulletin28WheatBreadReference,
    UsdaBulletin28FreshPotatoWithTwentyPercentRefuse,
    UsdaBulletin28DryEdibleRice,
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
    if good != "bread" {
        return None;
    }

    // USDA Bulletin 28 (1906 revision), p. 61, as-purchased sample averages:
    // whole wheat bread and white bread (all analyses), in kcal per pound.
    food_energy_for_mass(consumed_kg, 1_140.0, 1_215.0,
        FoodEnergySource::UsdaBulletin28WheatBreadReference)
}

/// A component of the removed agricultural mass may be edible. The reference
/// applies only under the product and preparation conditions indicated by its
/// source. Household intake cannot be inferred from a stock debit.
pub(crate) fn conditional_market_food_energy(good: &str, raw_kg: f64) -> Option<FoodEnergyEstimate> {
    if raw_kg <= 0.0 {
        return None;
    }
    match good {
        "potatoes" => {
            use super::historical_food::{potato_energy_for_mass_grams, PotatoMassBasis};

            // Bulletin 28, p. 68. The fresh as-purchased row has 20% refuse.
            let kcal = potato_energy_for_mass_grams(raw_kg * 800.0, PotatoMassBasis::FreshEdiblePortion)?
                .observed_sample_range_kcal?;
            Some(FoodEnergyEstimate { kcal, source: FoodEnergySource::UsdaBulletin28FreshPotatoWithTwentyPercentRefuse })
        }
        // Bulletin 28, p. 57. Use the dry rice series only if the entire mass
        // is dry edible grain. The ledger's rice can represent other forms.
        "rice" => food_energy_for_mass(raw_kg, 1_600.0, 1_690.0,
            FoodEnergySource::UsdaBulletin28DryEdibleRice),
        _ => None,
    }
}

fn food_energy_for_mass(
    mass_kg: f64, lower_per_pound: f64, upper_per_pound: f64, source: FoodEnergySource,
) -> Option<FoodEnergyEstimate> {
    if !mass_kg.is_finite() || mass_kg <= 0.0 {
        return None;
    }
    let pounds = mass_kg / 0.453_592_37;
    let kcal = QuantityRange {
        lower: lower_per_pound * pounds,
        upper: upper_per_pound * pounds,
    };
    kcal.is_valid().then_some(FoodEnergyEstimate { kcal, source })
}

pub fn physiological_requirements(input: PhysiologicalInputs) -> PhysiologicalRequirements {
    PhysiologicalRequirements {
        energy_kcal_per_day: requirement(energy(input, false), NeedSource::FaoWhoUnuEnergy2004),
        protein_grams_per_day: requirement(protein(input, false), NeedSource::WhoFaoUnuProtein2007),
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

/// Average dietary protein requirements under the energy reference weights.
pub(super) fn published_protein_reference(
    age_years: Option<AgeYears>,
    sex: Option<CohortSex>,
) -> Requirement {
    let input = PhysiologicalInputs {
        age_years,
        sex,
        ..PhysiologicalInputs::default()
    };
    requirement(protein(input, true), NeedSource::WhoFaoUnuProtein2007)
}

pub(super) fn adult_water_references(
    age_years: Option<AgeYears>, sex: Option<CohortSex>,
) -> Option<(QuantityRange, QuantityRange)> {
    let input = PhysiologicalInputs {
        age_years,
        sex,
        water_conditions: Some(WaterConditions::Temperate),
        ..PhysiologicalInputs::default()
    };
    let temperate = water(input).ok()?;
    let warm_work = water(PhysiologicalInputs {
        water_conditions: Some(WaterConditions::ModerateWorkInWarmClimate),
        ..input
    }).ok()?;
    Some((temperate, warm_work))
}

/// EFSA adequate intake from food and beverages in a moderate environment
/// and at PAL 1.6. The full age range must be supported.
pub(super) fn published_efsa_water_reference(
    age_years: Option<AgeYears>,
    sex: Option<CohortSex>,
) -> Requirement {
    requirement(efsa_water(age_years, sex), NeedSource::EfsaWater2010)
}

fn efsa_water(
    age_years: Option<AgeYears>,
    sex: Option<CohortSex>,
) -> Result<QuantityRange, UnknownNeed> {
    let ages = age_classes(age_years, 14)?;
    if *ages.start() == 0 {
        return Err(UnknownNeed::InfantAgeInMonthsAndFeedingRequired);
    }

    // EFSA (2010), sections 6.5 and 6.6, litres per person per day.
    let mut result: Option<QuantityRange> = None;
    for &sex in sexes(sex) {
        for age in ages.clone() {
            let intake = match (age, sex) {
                (1, _) => QuantityRange { lower: 1.1, upper: 1.2 },
                (2..=3, _) => QuantityRange::point(1.3),
                (4..=8, _) => QuantityRange::point(1.6),
                (9..=13, CohortSex::Female) => QuantityRange::point(1.9),
                (9..=13, CohortSex::Male) => QuantityRange::point(2.1),
                (_, CohortSex::Female) => QuantityRange::point(2.0),
                (_, CohortSex::Male) => QuantityRange::point(2.5),
            };
            result = Some(result.map_or(intake, |range| range.envelope(intake)));
        }
    }
    Ok(result.expect("validated age range and sex profiles are nonempty"))
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

fn reference_body_weight(age: u16, sex: CohortSex) -> QuantityRange {
    // FAO (2004): midpoint weights in tables 4.2 and 4.3, and the selected
    // adult scenario weights from tables 5.4–5.9.
    let girls = [
        10.8, 13.0, 15.1, 16.8, 18.6, 20.6, 23.3, 26.6, 30.5, 34.7, 39.2, 43.8, 48.3, 52.1,
        55.0, 56.4, 56.7,
    ];
    let boys = [
        11.5, 13.5, 15.7, 17.7, 19.7, 21.7, 24.0, 26.7, 29.7, 33.3, 37.5, 42.3, 47.8, 53.8,
        59.5, 64.4, 67.8,
    ];
    QuantityRange::point(match (age, sex) {
        (1..=17, CohortSex::Female) => girls[usize::from(age - 1)],
        (1..=17, CohortSex::Male) => boys[usize::from(age - 1)],
        (_, CohortSex::Female) => 55.0,
        (_, CohortSex::Male) => 60.0,
    })
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
                let body_weight = supplied_weight.unwrap_or_else(|| reference_body_weight(age, sex));
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

fn protein(
    input: PhysiologicalInputs,
    published_reference: bool,
) -> Result<QuantityRange, UnknownNeed> {
    let ages = age_classes(input.age_years, 19)?;
    if *ages.start() == 0 {
        return Err(UnknownNeed::InfantAgeInMonthsAndFeedingRequired);
    }
    let supplied_weight = if published_reference {
        None
    } else {
        Some(weight(input)?)
    };
    // Mean grams per kilogram per day, WHO TRS 935, section 7 and tables 33a–b.
    let children = [
        0.95_f64, 0.79, 0.73, 0.69, 0.69, 0.72, 0.74, 0.75, 0.75, 0.75,
    ];
    let girls = [0.73_f64, 0.72, 0.71, 0.70, 0.69, 0.68, 0.67, 0.66];
    let boys = [0.75_f64, 0.74, 0.73, 0.72, 0.72, 0.71, 0.70, 0.69];
    let mut result: Option<QuantityRange> = None;
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
            let rate = QuantityRange {
                lower,
                upper: value,
            };
            let body_weight = supplied_weight.unwrap_or_else(|| reference_body_weight(age, sex));
            let estimate = body_weight.scaled(rate);
            result = Some(result.map_or(estimate, |range| range.envelope(estimate)));
        }
    }
    let estimate = result.expect("validated age range and sex profiles are nonempty");
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
