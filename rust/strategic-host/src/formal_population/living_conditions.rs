//! Published living-condition references for inspection.
//!
//! Each quantity belongs to its stated modern setting. Opening populations have
//! no assigned exposure, service access, or household inventory from these sources.

use serde::Serialize;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LivingConditionCategory {
    IndoorTemperature,
    ShelterSpace,
    Clothing,
    Bedding,
    Hygiene,
    HeatingFuel,
    HouseholdConditions,
    Care,
    Education,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LivingConditionContext {
    ColdSeasonInTemperateOrColderClimate,
    EmergencyShelterInWarmClimate,
    EmergencyShelterInExtendedColdWeather,
    HumanitarianEmergency,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum LivingConditionQuantity {
    ProposedTarget {
        value: f64,
    },
    MinimumProvision {
        value: f64,
    },
    /// The applicable minimum varies with the circumstances of the shelter.
    ContextualMinimumProvision {
        lower: f64,
        upper: f64,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LivingConditionUnit {
    DegreesCelsius,
    SquareMetresPerPerson,
    CompleteClothingSetsPerPerson,
    BlanketsPerPerson,
    GramsPerPersonPerMonth,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct LivingConditionSource {
    pub title: &'static str,
    pub locator: &'static str,
    pub url: &'static str,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct LivingConditionReference {
    pub id: &'static str,
    pub category: LivingConditionCategory,
    pub context: LivingConditionContext,
    pub quantity: LivingConditionQuantity,
    pub unit: LivingConditionUnit,
    pub conditions: &'static str,
    pub source: LivingConditionSource,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoricalActualCoverage {
    Unknown,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct HistoricalLivingConditionGap {
    pub category: LivingConditionCategory,
    pub missing_inputs: &'static str,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct LivingConditionsReferences {
    pub references: &'static [LivingConditionReference],
    pub historical_actual_coverage: HistoricalActualCoverage,
    pub historical_quantity_gaps: &'static [HistoricalLivingConditionGap],
}

const WHO_INDOOR_COLD: LivingConditionSource = LivingConditionSource {
    title: "WHO Housing and Health Guidelines (2018)",
    locator: "Section 4.1, guideline recommendations for low indoor temperatures and insulation",
    url: "https://www.ncbi.nlm.nih.gov/books/NBK535294/table/ch4.tab1/",
};

const UNHCR_EMERGENCY_SHELTER: LivingConditionSource = LivingConditionSource {
    title: "UNHCR Emergency Handbook: Emergency Shelter Solutions and Standards",
    locator: "Emergency shelter considerations in warm climates and in cold climates",
    url: "https://emergency.unhcr.org/emergency-assistance/settlement-and-shelter/guidance-shelter/emergency-shelter-solutions-and-standards",
};

const SPHERE_HOUSEHOLD_ITEMS: LivingConditionSource = LivingConditionSource {
    title: "The Sphere Handbook (2018)",
    locator: "Shelter and settlement standard 4: Household items, key indicators",
    url: "https://spherestandards.org/the-sphere-handbook-2018/",
};

const SPHERE_HYGIENE_ITEMS: LivingConditionSource = LivingConditionSource {
    title: "The Sphere Handbook (2018)",
    locator: "WASH hygiene promotion standard 1.2: Identification, access to and use of hygiene items, key indicators, p. 100",
    url: "https://spherestandards.org/the-sphere-handbook-2018/",
};

const REFERENCES: &[LivingConditionReference] = &[
    LivingConditionReference {
        id: "who_2018_cold_season_indoor_temperature",
        category: LivingConditionCategory::IndoorTemperature,
        context: LivingConditionContext::ColdSeasonInTemperateOrColderClimate,
        quantity: LivingConditionQuantity::ProposedTarget { value: 18.0 },
        unit: LivingConditionUnit::DegreesCelsius,
        conditions: "Health-protective indoor housing temperature proposed for the general population during cold seasons. Some vulnerable groups may need a higher temperature.",
        source: WHO_INDOOR_COLD,
    },
    LivingConditionReference {
        id: "unhcr_warm_climate_emergency_shelter_space",
        category: LivingConditionCategory::ShelterSpace,
        context: LivingConditionContext::EmergencyShelterInWarmClimate,
        quantity: LivingConditionQuantity::MinimumProvision { value: 3.5 },
        unit: LivingConditionUnit::SquareMetresPerPerson,
        conditions: "Covered living space in emergency shelters in tropical or warm climates, excluding cooking facilities or a kitchen.",
        source: UNHCR_EMERGENCY_SHELTER,
    },
    LivingConditionReference {
        id: "unhcr_extended_cold_emergency_shelter_space",
        category: LivingConditionCategory::ShelterSpace,
        context: LivingConditionContext::EmergencyShelterInExtendedColdWeather,
        quantity: LivingConditionQuantity::ContextualMinimumProvision {
            lower: 4.5,
            upper: 5.5,
        },
        unit: LivingConditionUnit::SquareMetresPerPerson,
        conditions: "Indoor living space in emergency shelters where cold weather with wind, rain and snow prevails for three to five months. Cooking and other daily activities may take place indoors.",
        source: UNHCR_EMERGENCY_SHELTER,
    },
    LivingConditionReference {
        id: "sphere_2018_emergency_clothing",
        category: LivingConditionCategory::Clothing,
        context: LivingConditionContext::HumanitarianEmergency,
        quantity: LivingConditionQuantity::MinimumProvision { value: 2.0 },
        unit: LivingConditionUnit::CompleteClothingSetsPerPerson,
        conditions: "Complete sets of the right size and suited to the person's needs, culture, season and climate.",
        source: SPHERE_HOUSEHOLD_ITEMS,
    },
    LivingConditionReference {
        id: "sphere_2018_emergency_blankets_and_bedding",
        category: LivingConditionCategory::Bedding,
        context: LivingConditionContext::HumanitarianEmergency,
        quantity: LivingConditionQuantity::MinimumProvision { value: 1.0 },
        unit: LivingConditionUnit::BlanketsPerPerson,
        conditions: "Provide bedding as well as the blanket. Cold climates require additional blankets or insulation from the ground.",
        source: SPHERE_HOUSEHOLD_ITEMS,
    },
    LivingConditionReference {
        id: "sphere_2018_emergency_bathing_soap",
        category: LivingConditionCategory::Hygiene,
        context: LivingConditionContext::HumanitarianEmergency,
        quantity: LivingConditionQuantity::MinimumProvision { value: 250.0 },
        unit: LivingConditionUnit::GramsPerPersonPerMonth,
        conditions: "Soap for bathing for people in affected households. The guidance calls for adjustment to local circumstances and specific needs.",
        source: SPHERE_HYGIENE_ITEMS,
    },
    LivingConditionReference {
        id: "sphere_2018_emergency_laundry_soap",
        category: LivingConditionCategory::Hygiene,
        context: LivingConditionContext::HumanitarianEmergency,
        quantity: LivingConditionQuantity::MinimumProvision { value: 200.0 },
        unit: LivingConditionUnit::GramsPerPersonPerMonth,
        conditions: "Soap for laundry for people in affected households. The guidance calls for adjustment to local circumstances and specific needs.",
        source: SPHERE_HYGIENE_ITEMS,
    },
];

const HISTORICAL_QUANTITY_GAPS: &[HistoricalLivingConditionGap] = &[
    HistoricalLivingConditionGap {
        category: LivingConditionCategory::HeatingFuel,
        missing_inputs: "Fuel quantity depends on local weather, occupied space, building heat loss, heating equipment and fuel.",
    },
    HistoricalLivingConditionGap {
        category: LivingConditionCategory::HouseholdConditions,
        missing_inputs: "Opening household occupancy, dwelling size, indoor temperature, and access to clothing, bedding and hygiene supplies require local evidence.",
    },
    HistoricalLivingConditionGap {
        category: LivingConditionCategory::Care,
        missing_inputs: "A common opening care quantity is unknown. Care depends on household and individual circumstances, local services and access.",
    },
    HistoricalLivingConditionGap {
        category: LivingConditionCategory::Education,
        missing_inputs: "A common opening education quantity is unknown. Eligibility, attendance, term lengths and local provision require evidence.",
    },
];

/// Modern health guidance and emergency provision quantities, with the limits
/// of their historical application. This query reads no world state.
pub fn living_conditions_references() -> LivingConditionsReferences {
    LivingConditionsReferences {
        references: REFERENCES,
        historical_actual_coverage: HistoricalActualCoverage::Unknown,
        historical_quantity_gaps: HISTORICAL_QUANTITY_GAPS,
    }
}
