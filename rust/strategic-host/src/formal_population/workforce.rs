use super::SocialDistribution;
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;

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
