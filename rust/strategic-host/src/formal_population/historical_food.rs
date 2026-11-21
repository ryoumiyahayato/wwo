//! Household food accounts and historical composition references.

use serde::Serialize;

use super::needs::QuantityRange;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoricalFoodCurrency {
    BelgianFranc,
    FrenchFranc,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoricalFoodMassBasis {
    /// The weight of finished bread.
    FinishedBread,
    /// The commodity as entered in the household account. Preparation and edible yield are unspecified.
    CommodityAsAccounted,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum HistoricalFoodSupply {
    Cash { expenditure_centimes: u32 },
    OwnProduction { in_kind_valuation_centimes: u32 },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct HistoricalFoodRow {
    pub commodity_id: &'static str,
    /// The annual household budget column headed “Poids consommé,” in kilograms.
    pub household_accounted_kg: u32,
    pub mass_basis: HistoricalFoodMassBasis,
    pub local_centimes_per_kg: u32,
    pub supply: HistoricalFoodSupply,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct HistoricalFoodCase {
    pub id: &'static str,
    pub locality: &'static str,
    pub fieldwork_first_year: u16,
    pub fieldwork_last_year: u16,
    pub covered_people: u8,
    /// Day count when specified in the annual account.
    pub period_days: Option<u16>,
    pub currency: HistoricalFoodCurrency,
    pub source_url: &'static str,
    pub printed_page: u16,
    pub foods: &'static [HistoricalFoodRow],
}

pub const HISTORICAL_FOOD_CASES: &[HistoricalFoodCase] = &[
    HistoricalFoodCase {
        id: "borinage_miner_1900",
        locality: "Commune D., western Borinage, Belgium",
        fieldwork_first_year: 1900,
        fieldwork_last_year: 1900,
        covered_people: 4,
        period_days: Some(365),
        currency: HistoricalFoodCurrency::BelgianFranc,
        source_url: "https://ouvriersdeuxmondes.huma-num.fr/monographie/mineur-bassin-houiller-couchant-mons-95#part_02_05_15",
        printed_page: 234,
        foods: &[
            HistoricalFoodRow {
                commodity_id: "bread",
                household_accounted_kg: 520,
                mass_basis: HistoricalFoodMassBasis::FinishedBread,
                local_centimes_per_kg: 21,
                supply: HistoricalFoodSupply::Cash {
                    expenditure_centimes: 10_920,
                },
            },
            HistoricalFoodRow {
                commodity_id: "potatoes",
                household_accounted_kg: 1_000,
                mass_basis: HistoricalFoodMassBasis::CommodityAsAccounted,
                local_centimes_per_kg: 5,
                supply: HistoricalFoodSupply::OwnProduction {
                    in_kind_valuation_centimes: 5_000,
                },
            },
            HistoricalFoodRow {
                commodity_id: "rice",
                household_accounted_kg: 4,
                mass_basis: HistoricalFoodMassBasis::CommodityAsAccounted,
                local_centimes_per_kg: 40,
                supply: HistoricalFoodSupply::Cash {
                    expenditure_centimes: 160,
                },
            },
        ],
    },
    HistoricalFoodCase {
        id: "paris_railway_worker_1901_1902",
        locality: "Paris, France",
        fieldwork_first_year: 1901,
        fieldwork_last_year: 1902,
        covered_people: 4,
        period_days: None,
        currency: HistoricalFoodCurrency::FrenchFranc,
        source_url: "https://ouvriersdeuxmondes.huma-num.fr/monographie/cantonnier-poseur-voie-chemin-fer-nord-paris-99#part_02_05_15",
        printed_page: 460,
        foods: &[
            HistoricalFoodRow {
                commodity_id: "bread",
                household_accounted_kg: 480,
                mass_basis: HistoricalFoodMassBasis::FinishedBread,
                local_centimes_per_kg: 35,
                supply: HistoricalFoodSupply::Cash {
                    expenditure_centimes: 16_800,
                },
            },
            HistoricalFoodRow {
                commodity_id: "potatoes",
                household_accounted_kg: 120,
                mass_basis: HistoricalFoodMassBasis::CommodityAsAccounted,
                local_centimes_per_kg: 10,
                supply: HistoricalFoodSupply::Cash {
                    expenditure_centimes: 1_200,
                },
            },
        ],
    },
];

pub fn historical_food_case(id: &str) -> Option<&'static HistoricalFoodCase> {
    HISTORICAL_FOOD_CASES.iter().find(|case| case.id == id)
}

#[derive(Serialize)]
pub struct HistoricalSpendingCase {
    pub id: &'static str,
    pub locality: &'static str,
    pub publication_year: u16,
    pub observation_date: Option<&'static str>,
    pub covered_people: u8,
    pub period_days: u8,
    pub source_url: &'static str,
    pub printed_pages: [u8; 2],
    pub rice_volume_go: u8,
    pub expenditure_rin: &'static [(&'static str, u16)],
    pub total_expenditure_rin: u16,
    pub scope: &'static str,
}

pub const TOKYO_SHINAMI_HOUSEHOLD: HistoricalSpendingCase = HistoricalSpendingCase {
    id: "tokyo_shinami_household_1899_publication",
    locality: "Shin'ami, Tokyo, Japan",
    publication_year: 1899,
    observation_date: None,
    covered_people: 3,
    period_days: 1,
    source_url: "https://dl.ndl.go.jp/pid/798849/1/30",
    printed_pages: [32, 33],
    rice_volume_go: 12,
    expenditure_rin: &[
        ("rice", 170), ("unspecified_side_dish", 40), ("sake", 30), ("wood_and_charcoal", 20),
        ("kerosene", 5), ("tobacco", 7), ("child_allowance", 10), ("bedding_rent", 26), ("room_rent", 25),
    ],
    total_expenditure_rin: 333,
    scope: "Reported daily budget of a performer, spouse and their child. Rice uses original volume units (1 shō equals 10 gō). Food preparation, edible yield and intake are unspecified. Leftovers and household side work are discussed separately without quantities.",
};

#[derive(Serialize)]
pub struct HistoricalMerchantLedger {
    pub id: &'static str,
    pub locality: &'static str,
    pub observation_month: &'static str,
    pub reported_family_members: u8,
    pub covered_boarders: u8,
    pub wage_income_us_cents: u16,
    pub expenses_us_cents: &'static [(&'static str, u16)],
    pub recorded_total_expenses_us_cents: u16,
    pub source_url: &'static str,
    pub printed_pages: [u8; 2],
    pub scope: &'static str,
}

pub const SANDY_SPRING_HOUSEHOLD: HistoricalMerchantLedger = HistoricalMerchantLedger {
    id: "sandy_spring_merchant_ledger_1899_01",
    locality: "Sandy Spring, Montgomery County, Maryland, United States",
    observation_month: "1899-01",
    reported_family_members: 9,
    covered_boarders: 7,
    wage_income_us_cents: 2_500,
    expenses_us_cents: &[
        ("food", 506), ("wood", 250), ("lighting_oil", 28), ("clothing_and_footwear", 230),
        ("rent", 250), ("pitcher", 50), ("soap", 10), ("matches", 2),
    ],
    recorded_total_expenses_us_cents: 1_326,
    source_url: "https://tile.loc.gov/storage-services/service/rbc/lcrbmrp/t8050/t8050.pdf#page=60",
    printed_pages: [94, 95],
    scope: "US Department of Labor Bulletin 32. Transcript of one household's monthly employer-store account. Two sons lived and worked away, with unknown remittances. Fuel quantity, use for cooking or heat, medical spending, and actual intake are unknown. The report's annual extrapolation is excluded.",
};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PotatoMassBasis {
    /// Fresh potatoes as purchased, including refuse.
    FreshAsPurchased,
    FreshEdiblePortion,
    /// Finished boiled potatoes on the bulletin's as-purchased basis.
    BoiledAsPrepared,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PotatoEnergySource {
    UsdaAtwaterBryantBulletin28RevisedPage68,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct PotatoEnergyEstimate {
    pub mass_basis: PotatoMassBasis,
    pub average_kcal: f64,
    /// Observed sample extremes for rows supplying both values.
    pub observed_sample_range_kcal: Option<QuantityRange>,
    pub source: PotatoEnergySource,
}

/// Calculate energy for a measured mass on the selected form's basis.
pub fn potato_energy_for_mass_grams(
    grams: f64,
    mass_basis: PotatoMassBasis,
) -> Option<PotatoEnergyEstimate> {
    if !grams.is_finite() || grams < 0.0 {
        return None;
    }

    const GRAMS_PER_POUND: f64 = 453.59237;
    let pounds = grams / GRAMS_PER_POUND;
    let (average_kcal_per_pound, sample_range_per_pound) = match mass_basis {
        PotatoMassBasis::FreshAsPurchased => (310.0, None),
        PotatoMassBasis::FreshEdiblePortion => (385.0, Some((285.0, 570.0))),
        PotatoMassBasis::BoiledAsPrepared => (440.0, Some((340.0, 545.0))),
    };
    let average_kcal = average_kcal_per_pound * pounds;
    let observed_sample_range_kcal = sample_range_per_pound.map(|(lower, upper)| QuantityRange {
        lower: lower * pounds,
        upper: upper * pounds,
    });
    if !average_kcal.is_finite()
        || observed_sample_range_kcal.is_some_and(|range| !range.upper.is_finite())
    {
        return None;
    }
    Some(PotatoEnergyEstimate {
        mass_basis,
        average_kcal,
        observed_sample_range_kcal,
        source: PotatoEnergySource::UsdaAtwaterBryantBulletin28RevisedPage68,
    })
}
