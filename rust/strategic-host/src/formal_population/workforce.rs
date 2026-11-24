use super::{households::age_share, profiles::Region, Population, PopulationStructure, SocialDistribution};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, sync::OnceLock};

#[derive(Deserialize, Serialize)]
pub struct RecipeOutput {
    pub commodity_id: String,
    pub units: f64,
}

#[derive(Deserialize, Serialize)]
pub struct WorkforceRecipe {
    pub recipe_id: String,
    pub inputs: Vec<RecipeOutput>,
    pub outputs: Vec<RecipeOutput>,
    pub workers_per_batch: u64,
}

#[derive(Serialize)]
pub struct WorkforceGroup<'a> {
    pub classification: &'a str,
    pub occupation: &'a str,
    pub residents: u64,
    pub sector: &'static str,
    pub skills: &'static str,
    /// Candidate recipes for the occupation. Mixed labels do not determine
    /// how much labour any single recipe can receive.
    pub recipes: Vec<&'static WorkforceRecipe>,
    pub own_use_possible: bool,
}

#[derive(Serialize)]
pub struct WorkforceReference<'a> {
    pub occupation_assigned: u64,
    pub occupation_unassigned: u64,
    pub mapped_occupation_residents: u64,
    pub groups: Vec<WorkforceGroup<'a>>,
}

#[derive(Deserialize)]
struct ProductionCatalogue {
    recipes: Vec<WorkforceRecipe>,
}

fn catalogue() -> &'static ProductionCatalogue {
    static CATALOGUE: OnceLock<ProductionCatalogue> = OnceLock::new();
    CATALOGUE.get_or_init(|| {
        serde_json::from_slice(include_bytes!("../../../../data/alpha/commodity_market_1900.json"))
            .expect("embedded formal production catalogue")
    })
}

pub fn production_recipe(id: &str) -> Option<&'static WorkforceRecipe> {
    catalogue().recipes.iter().find(|row| row.recipe_id == id)
}

#[derive(Serialize)]
pub struct HistoricalProductionReference<'a> {
    pub year: u16,
    pub steel_tonnes: u64,
    pub energy_tonnes_coal_equivalent: u64,
    pub confidence_basis_points: u64,
    pub method: &'a str,
}

pub fn historical_production_reference(id: &str) -> Option<HistoricalProductionReference<'static>> {
    #[derive(Deserialize)]
    struct Table {
        field_order: Vec<String>,
        common_methods: Method,
        rows: Vec<Vec<serde_json::Value>>,
    }
    #[derive(Deserialize)]
    struct Method {
        production: String,
    }
    static TABLE: OnceLock<Table> = OnceLock::new();
    let table = TABLE.get_or_init(|| {
        serde_json::from_slice(include_bytes!("../../../../data/alpha/historical_world_economy_1900/countries_compact.json"))
            .expect("embedded historical economy reference")
    });
    let column = |key| table.field_order.iter().position(|field| field == key);
    let identity = column("entity_id")?;
    let row = table.rows.iter().find(|row| row[identity].as_str() == Some(id))?;
    Some(HistoricalProductionReference {
        year: 1900,
        steel_tonnes: row[column("steel_output_tonnes")?].as_u64()?,
        energy_tonnes_coal_equivalent: row[column("energy_coal_equivalent_tonnes")?].as_u64()?,
        confidence_basis_points: row[column("production_confidence_bp")?].as_u64()?,
        method: &table.common_methods.production,
    })
}

pub fn workforce_reference<'a>(social: &SocialDistribution<'a>) -> Option<WorkforceReference<'a>> {
    let occupation = social.dimensions.get("occupation")?;
    let mut groups = Vec::new();
    for (&classification, rows) in &occupation.by_classification {
        for (&category, &residents) in rows {
            let Some((sector, skills, recipes, own_use_possible)) = occupation_link(category) else {
                continue;
            };
            groups.push(WorkforceGroup {
                classification,
                occupation: category,
                residents,
                sector,
                skills,
                recipes: recipes.iter().filter_map(|id| production_recipe(id)).collect(),
                own_use_possible,
            });
        }
    }
    Some(WorkforceReference {
        occupation_assigned: occupation.assigned_residents,
        occupation_unassigned: occupation.unknown_residents,
        mapped_occupation_residents: groups.iter().map(|group| group.residents).sum(),
        groups,
    })
}

fn occupation_link(label: &str) -> Option<(&'static str, &'static str, &'static [&'static str], bool)> {
    const FARM: &[&str] = &["farm_wheat", "farm_rye", "farm_maize", "farm_potatoes", "farm_livestock"];
    const PRIMARY: &[&str] = &["farm_wheat", "farm_rye", "farm_maize", "farm_potatoes", "farm_livestock", "fishery", "timber_camp"];
    const MINING: &[&str] = &["coal_mine", "iron_mine", "copper_mine"];
    const TEXTILE: &[&str] = &["cotton_mill", "wool_mill", "clothing_factory"];
    const MANUFACTURE: &[&str] = &["flour_mill", "sawmill", "cotton_mill", "wool_mill", "machine_works"];
    Some(match label {
        "Agriculture" | "Agricultural class" | "Agricultural pursuits" | "Agricultura" | "Trabalhos agricolas" =>
            ("agriculture", "cultivation_and_animal_husbandry", FARM, true),
        "Provision and Care of Animals" => ("livestock", "animal_husbandry", &["farm_livestock"], true),
        "Pêches, forêts et agriculture" | "agriculture_fishing_hunting" | "Primary production"
        | "Agriculture, forestry, hunting and fishing" | "Producción de la materia prima"
        | "Primary sector (agriculture, forestry and fishing)" =>
            ("mixed_primary_production", "cultivation_or_harvesting", PRIMARY, true),
        "Fishing" | "Fisheries and fishing class" | "Fishing and hunting" | "Pesca e caça" =>
            ("fishing", "fishing_or_hunting", &["fishery"], true),
        "Forestry and lumbering class" => ("forestry", "logging", &["timber_camp", "sawmill"], true),
        "Mining class" | "Minería" | "In and About, and Dealing in the Products of, Mines and Quarries" =>
            ("mining", "extraction_or_related_work", MINING, false),
        "Mining and metallurgy" => ("mining_and_metallurgy", "extraction_or_metallurgy",
            &["coal_mine", "iron_mine", "copper_mine", "steelworks", "copper_smelter"], false),
        "Industrie" | "Industrial occupations" | "Industry" | "industry" | "Industrias" | "Industria"
        | "Manufacturing and mechanical class" | "Manufacturing and mechanical pursuits" | "Producciones industriales" =>
            ("manufacturing", "craft_or_machine_work", MANUFACTURE, true),
        "Textile Fabrics" | "Textile Fabrics and Dress" | "Dress" =>
            ("textiles", "spinning_weaving_or_sewing", TEXTILE, true),
        "Secondary sector (including transport and utilities)" => ("mixed_secondary_production",
            "industry_transport_or_utility_work", &["machine_works", "freight_network", "thermal_power"], false),
        "Tertiary sector (commerce and services)" =>
            ("commerce_and_services", "commerce_or_service_work", &[], false),
        "Maestros de escuela" => ("education", "teaching", &[], false),
        "Building and Works of Construction" | "Buildings" => ("construction", "construction_work", &[], false),
        "Transport and Storage" | "Transport" | "Transportes" | "Conveyance of Men, Goods, and Messages" =>
            ("transport", "carriage_or_handling", &["freight_network"], false),
        "Trade and transportation class" | "Trade and transportation" | "Trade and transport" | "Trade, transport and insurance" =>
            ("trade_and_transport", "commerce_or_carriage", &["freight_network"], false),
        "Commerce" | "Comercio" | "Commercio" | "commerce" | "Commercial Occupations" | "Trade and credit" =>
            ("commerce", "commerce_and_bookkeeping", &[], false),
        "Professional service" | "Professional class" | "Professions libérales"
        | "Professions liberaes" | "Profissões liberaes" | "Profesiones Liberales" =>
            ("professions", "professional_training", &[], false),
        "Profesiones sanitarias" => ("healthcare", "care_or_medical_training", &[], false),
        _ => return None,
    })
}

#[derive(Serialize)]
pub struct LaborSupply {
    pub residents: u64,
    pub children: u64,
    pub students: u64,
    pub older: u64,
    pub caregivers: u64,
    pub potential_workers: u64,
    pub unresolved_activity: u64,
    pub unemployment: Option<u64>,
    pub annual_labor_hours: u64,
    pub sectors: Vec<LaborSector>,
    pub basis: &'static str,
}

#[derive(Serialize)]
pub struct LaborSector {
    pub id: &'static str,
    pub workers: u64,
    pub annual_hours: u64,
    pub skills: &'static str,
    pub own_use_share: Option<f64>,
    pub alternatives: Vec<ConditionalOutput>,
}

#[derive(Serialize)]
pub struct ConditionalOutput {
    pub recipe: &'static WorkforceRecipe,
    /// One alternative at a time. Recipe catalogue specifies labour per batch,
    /// and has no elapsed-time unit for this estimate.
    pub parallel_batches: u64,
    pub output: Vec<RecipeOutput>,
    pub own_use: Vec<RecipeOutput>,
    pub historical_yield: Option<CropYield>,
}

#[derive(Serialize)]
pub struct CropYield {
    pub tonnes_per_hectare: f64,
    pub from_year: u16,
    pub to_year: u16,
    pub source: &'static str,
    pub assumed_hectares_per_worker: f64,
    pub conditional_tonnes_per_harvest: f64,
}

impl Population {
    pub fn labor_supply(
        &self, unit: Option<&str>, structure: &PopulationStructure<'_>, social: Option<&SocialDistribution<'_>>,
    ) -> LaborSupply {
        let mut regions = BTreeMap::<_, [f64; 3]>::new();
        for cohort in &structure.cohorts {
            let Some(age) = cohort.age_years else { continue; };
            let region = regions.entry(self.household_profile(cohort.unit_id)).or_default();
            for ((first, last), count) in [(0, 17), (18, 64), (65, 150)].into_iter().zip(region) {
                *count += age_share(age.youngest, age.oldest, first, last) * cohort.members as f64;
            }
        }
        let mut totals = [0.; 5];
        let mut scenario_sectors = [0.; 5];
        let mut year_hours = 0.;
        let mut farm_own_use = 0.;
        let mut sewing_own_use = 0.;
        for ((region, urban), [young, adult, older]) in regions {
            let western = matches!(region, Region::Atlantic | Region::Continental | Region::NorthAmerica);
            let students = young * if urban { 0.54 } else if western { 0.38 } else { 0.23 };
            let caregivers = adult * if urban { 0.22 } else { 0.28 };
            let potential = (adult - caregivers) * if urban { 0.92 } else { 0.94 };
            for (total, amount) in totals.iter_mut().zip([young - students, students, older, caregivers, potential]) {
                *total += amount;
            }
            let hours_per_worker = if western && urban { 2_800. } else if western { 2_530. } else { 2_350. };
            year_hours += potential * hours_per_worker;
            for (i, share) in region.sectors(urban).into_iter().enumerate() {
                scenario_sectors[i] += potential * share as f64 / 100.;
            }
            farm_own_use += potential * if urban { 0.12 } else if western { 0.39 } else { 0.64 };
            sewing_own_use += potential * if urban { 0.11 } else { 0.32 };
        }
        let mut unallocated = structure.population_total;
        let [children, students, older, caregivers, potential_workers] = totals.map(|value| {
            let assigned = (value.round() as u64).min(unallocated);
            unallocated -= assigned;
            assigned
        });
        let breakdown = social.and_then(workforce_reference);
        let mut historical = [0_u64; 5];
        if let Some(reference) = &breakdown {
            for group in &reference.groups {
                if group.classification == "opening_industry_participation_scenario_v44" { continue; }
                let index = match group.sector {
                    "agriculture" | "livestock" | "fishing" | "forestry" | "mixed_primary_production" => 0,
                    "mining" => 1,
                    "manufacturing" | "textiles" | "construction" => 2,
                    "transport" => 3,
                    "trade_and_transport" | "commerce" | "professions" | "education" | "healthcare" | "commerce_and_services" => 4,
                    _ => continue,
                };
                historical[index] += group.residents;
            }
        }
        let recorded: u64 = historical.iter().sum();
        // Some source occupational classes include dependants. Use the recorded
        // composition as a reference blend, with the age-based labour cap.
        let observed_weight = (recorded as f64 / potential_workers.max(1) as f64).min(0.80);
        let average_hours = year_hours / totals[4].max(1.);
        let us_reference = unit.is_some_and(|id| self.parent_unit(id) == Some("united_states_1900"));
        let mut assigned_workers = 0;
        let mut cumulative_share = 0.;
        let sector_workers: [u64; 5] = std::array::from_fn(|i| {
            cumulative_share += (1. - observed_weight) * scenario_sectors[i] / totals[4].max(1.)
                + observed_weight * historical[i] as f64 / recorded.max(1) as f64;
            let target = if i == 4 { potential_workers } else {
                (cumulative_share * potential_workers as f64).round() as u64
            }.clamp(assigned_workers, potential_workers);
            let workers = target - assigned_workers;
            assigned_workers = target;
            workers
        });
        // Within a reported composite category these are transparent scenario
        // shares, conserving the sector workforce instead of duplicating it.
        let sectors = [
            (0, 78, "cultivation", "cultivation", &["farm_wheat", "farm_rye", "farm_maize", "farm_potatoes"][..]),
            (0, 12, "livestock", "animal_husbandry", &["farm_livestock"][..]),
            (0, 5, "fisheries", "fishing", &["fishery"][..]),
            (0, 5, "forestry", "logging", &["timber_camp"][..]),
            (1, 100, "extraction", "mining", &["coal_mine", "iron_mine", "copper_mine"][..]),
            (2, 25, "textiles", "weaving_and_sewing", &["cotton_mill", "wool_mill", "clothing_factory"][..]),
            (2, 20, "construction", "construction", &[][..]),
            (2, 55, "manufacturing", "craft_and_machine_operation", &["flour_mill", "bakery", "sawmill", "machine_works"][..]),
            (3, 100, "transport", "transport_and_handling", &["freight_network"][..]),
            (4, 43, "commerce", "trade_and_bookkeeping", &[][..]),
            (4, 8, "education", "teaching", &[][..]),
            (4, 5, "healthcare", "medical_and_social_care", &[][..]),
            (4, 44, "services", "domestic_and_public_services", &[][..]),
        ];
        let mut used = [0; 5];
        let mut shares = [0; 5];
        let sectors = sectors.into_iter().map(|(i, share, id, skills, recipes)| {
            shares[i] += share;
            let allocated = sector_workers[i] * shares[i] / 100;
            let workers = allocated - used[i];
            used[i] = allocated;
            let own_use_share = match id {
                "cultivation" | "livestock" | "fisheries" => Some(farm_own_use / totals[4].max(1.)),
                "textiles" => Some(sewing_own_use / totals[4].max(1.)),
                _ => None,
            }.filter(|_| workers > 0);
            let alternatives = recipes.iter().filter_map(|id| {
                let recipe = production_recipe(id)?;
                let parallel_batches = workers.checked_div(recipe.workers_per_batch)?;
                let outputs = |fraction: f64| recipe.outputs.iter().map(|row| RecipeOutput {
                    commodity_id: row.commodity_id.clone(), units: row.units * parallel_batches as f64 * fraction,
                }).collect::<Vec<_>>();
                let own_use = if matches!(*id, "clothing_factory" | "farm_wheat" | "farm_rye" |
                    "farm_maize" | "farm_potatoes" | "farm_livestock" | "fishery") {
                    own_use_share.map_or_else(Vec::new, outputs)
                } else { Vec::new() };
                Some(ConditionalOutput {
                    recipe, parallel_batches, output: outputs(1.), own_use,
                    historical_yield: us_reference.then(|| us_crop_yield(id, workers)).flatten(),
                })
            }).collect();
            LaborSector { id, workers, annual_hours: (average_hours * workers as f64).round() as u64, skills,
                own_use_share, alternatives }
        }).collect();
        LaborSupply { residents: structure.population_total, children, students, older, caregivers, potential_workers,
            unresolved_activity: unallocated, unemployment: None,
            annual_labor_hours: (average_hours * potential_workers as f64).round() as u64, sectors,
            basis: "opening_labor_supply_scenario_v44; age-limited activity ratios and occupational composition; scheduled labor and production not implied" }
    }
}

fn us_crop_yield(recipe: &str, workers: u64) -> Option<CropYield> {
    let tonnes_per_hectare = match recipe {
        "farm_wheat" => 0.968, "farm_rye" => 0.835, "farm_maize" => 1.713,
        "farm_potatoes" => 6.315, _ => return None,
    };
    let assumed_hectares_per_worker = 4.;
    Some(CropYield { tonnes_per_hectare, from_year: 1900, to_year: 1909,
        source: "USDA Crops and Markets, US average bushels per acre, 1900–1909",
        assumed_hectares_per_worker, conditional_tonnes_per_harvest:
            tonnes_per_hectare * assumed_hectares_per_worker * workers as f64 })
}
