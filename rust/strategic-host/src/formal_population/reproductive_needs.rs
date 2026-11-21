//! Conditional energy increments for pregnancy and lactation.

use serde::Serialize;

use super::needs::NeedSource;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PregnancyTrimester {
    First,
    Second,
    Third,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PregnancyReferenceContext {
    /// FAO's healthy, well-nourished adult reference with adequate gestational gain.
    HealthyAdultAdequateGain,
    OutsidePublishedReference,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LactationPeriod {
    /// From birth until six completed months.
    FirstSixMonths,
    /// At least six and fewer than twelve completed months.
    SecondSixMonths,
    OutsideFirstYear,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum MilkProduction {
    /// FAO's first-six-month mean for exclusive breastfeeding.
    ExclusiveBreastfeedingReference,
    /// FAO's second-six-month scenario for partial breastfeeding.
    PartialBreastfeedingReference,
    /// Daily milk produced by the mother, in grams.
    DocumentedGramsPerDay(f64),
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum MaternalEnergyStores {
    /// FAO's early exclusive-breastfeeding scenario after adequate gestational gain.
    WellNourishedAdequateGainReference,
    /// The diet must cover the full milk cost, for example after insufficient gestational gain.
    NoDietaryCredit,
    /// Daily body energy allocated to the milk production cost.
    DocumentedContributionKcalPerDay(f64),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum UnknownReproductiveEnergy {
    MissingPregnancyTrimester,
    MissingPregnancyReferenceContext,
    OutsidePregnancyReference,
    MissingLactationPeriod,
    OutsideLactationReferencePeriod,
    MissingMilkProduction,
    MilkReferenceOutsideLactationPeriod,
    InvalidMilkProduction,
    MissingMaternalEnergyStores,
    MaternalEnergyStoresReferenceOutsideScenario,
    InvalidMaternalEnergyStores,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ReproductiveEnergyRequirement {
    Known {
        kcal_per_day: f64,
        source: NeedSource,
    },
    Unknown(UnknownReproductiveEnergy),
}

impl ReproductiveEnergyRequirement {
    fn fao_estimate(kcal_per_day: f64) -> Self {
        Self::Known {
            kcal_per_day,
            source: NeedSource::FaoWhoUnuEnergy2004,
        }
    }
}

/// Additional energy over the compatible pre-pregnancy baseline, FAO 2004 section 6.3.
pub fn pregnancy_energy_increment(
    trimester: Option<PregnancyTrimester>,
    context: Option<PregnancyReferenceContext>,
) -> ReproductiveEnergyRequirement {
    use ReproductiveEnergyRequirement::Unknown;
    use UnknownReproductiveEnergy::*;

    let Some(trimester) = trimester else {
        return Unknown(MissingPregnancyTrimester);
    };
    match context {
        Some(PregnancyReferenceContext::HealthyAdultAdequateGain) => {}
        Some(PregnancyReferenceContext::OutsidePublishedReference) => {
            return Unknown(OutsidePregnancyReference);
        }
        None => return Unknown(MissingPregnancyReferenceContext),
    }
    ReproductiveEnergyRequirement::fao_estimate(match trimester {
        PregnancyTrimester::First => 85.0,
        PregnancyTrimester::Second => 285.0,
        PregnancyTrimester::Third => 475.0,
    })
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct LactationEnergyRequirements {
    pub milk_produced_grams_per_day: Option<f64>,
    pub milk_production_cost: ReproductiveEnergyRequirement,
    pub additional_dietary_energy: ReproductiveEnergyRequirement,
}

impl LactationEnergyRequirements {
    fn unknown(reason: UnknownReproductiveEnergy) -> Self {
        Self {
            milk_produced_grams_per_day: None,
            milk_production_cost: ReproductiveEnergyRequirement::Unknown(reason),
            additional_dietary_energy: ReproductiveEnergyRequirement::Unknown(reason),
        }
    }
}

/// Report the gross production cost and the dietary increment after any supported
/// contribution from maternal energy stores, FAO 2004 sections 7.1 and 7.2.
pub fn lactation_energy_requirements(
    period: Option<LactationPeriod>,
    milk: Option<MilkProduction>,
    stores: Option<MaternalEnergyStores>,
) -> LactationEnergyRequirements {
    use UnknownReproductiveEnergy::*;

    let Some(period) = period else {
        return LactationEnergyRequirements::unknown(MissingLactationPeriod);
    };
    if period == LactationPeriod::OutsideFirstYear {
        return LactationEnergyRequirements::unknown(OutsideLactationReferencePeriod);
    }
    let Some(milk) = milk else {
        return LactationEnergyRequirements::unknown(MissingMilkProduction);
    };
    let (milk_grams, milk_cost_kcal) = match (period, milk) {
        (LactationPeriod::FirstSixMonths, MilkProduction::ExclusiveBreastfeedingReference) => {
            (807.0, 675.0)
        }
        (LactationPeriod::SecondSixMonths, MilkProduction::PartialBreastfeedingReference) => {
            (550.0, 460.0)
        }
        (_, MilkProduction::DocumentedGramsPerDay(grams)) if grams.is_finite() && grams >= 0.0 => {
            const PRODUCTION_KCAL_PER_GRAM: f64 = 2.8 / (0.80 * 4.184);
            (grams, grams * PRODUCTION_KCAL_PER_GRAM)
        }
        (_, MilkProduction::DocumentedGramsPerDay(_)) => {
            return LactationEnergyRequirements::unknown(InvalidMilkProduction);
        }
        _ => return LactationEnergyRequirements::unknown(MilkReferenceOutsideLactationPeriod),
    };
    LactationEnergyRequirements {
        milk_produced_grams_per_day: Some(milk_grams),
        milk_production_cost: ReproductiveEnergyRequirement::fao_estimate(milk_cost_kcal),
        additional_dietary_energy: match maternal_contribution(stores, milk, milk_cost_kcal) {
            Ok(contribution) => {
                ReproductiveEnergyRequirement::fao_estimate(milk_cost_kcal - contribution)
            }
            Err(reason) => ReproductiveEnergyRequirement::Unknown(reason),
        },
    }
}

fn maternal_contribution(
    stores: Option<MaternalEnergyStores>,
    milk: MilkProduction,
    milk_cost_kcal: f64,
) -> Result<f64, UnknownReproductiveEnergy> {
    use UnknownReproductiveEnergy::*;

    match stores {
        Some(MaternalEnergyStores::WellNourishedAdequateGainReference) => {
            if milk == MilkProduction::ExclusiveBreastfeedingReference {
                Ok(170.0)
            } else {
                Err(MaternalEnergyStoresReferenceOutsideScenario)
            }
        }
        Some(MaternalEnergyStores::NoDietaryCredit) => Ok(0.0),
        Some(MaternalEnergyStores::DocumentedContributionKcalPerDay(kcal)) => {
            if kcal.is_finite() && (0.0..=milk_cost_kcal).contains(&kcal) {
                Ok(kcal)
            } else {
                Err(InvalidMaternalEnergyStores)
            }
        }
        None => Err(MissingMaternalEnergyStores),
    }
}
