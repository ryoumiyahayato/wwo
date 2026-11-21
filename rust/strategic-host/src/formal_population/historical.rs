use super::MAX_POPULATION;
use crate::formal_save::invalid;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::{BTreeMap, BTreeSet}, io::{self, BufRead, BufReader}, sync::OnceLock};

const SOURCE: &[u8] = include_bytes!("../../../../data/alpha/historical_world_economy_1900/countries_compact.json");
const SCHEMA: &str = "historical_world_economy_1900_compact_country_table_v1";
// calibration_date in data/alpha/historical_world_economy_1900.json.
const CALIBRATION_DATE: &str = "1900-01-01";

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
pub struct HistoricalPopulationEstimate {
    pub value: u64,
    pub lower: u64,
    pub upper: u64,
    pub confidence_bp: u64,
    pub calibration_date: &'static str,
    pub source_table: &'static str,
    /// Common estimate method. The compact table has no per-unit primary source or census date.
    pub source_method: &'static str,
}

#[derive(Deserialize)]
struct SourceTable<'a> {
    schema_id: &'a str,
    field_order: Vec<&'a str>,
    #[serde(borrow)]
    common_methods: SourceMethods<'a>,
    rows: Vec<Vec<Value>>,
}

#[derive(Deserialize)]
struct SourceMethods<'a> {
    population: &'a str,
}

type Estimates = BTreeMap<String, HistoricalPopulationEstimate>;

pub(super) fn opening_estimate(unit: &str) -> io::Result<Option<HistoricalPopulationEstimate>> {
    static ESTIMATES: OnceLock<io::Result<Estimates>> = OnceLock::new();
    Ok(ESTIMATES.get_or_init(read_estimates).as_ref()
        .map_err(|error| invalid(error.to_string()))?.get(unit).copied())
}

/// Dated evidence from the historical catalogue, outside the live population
/// ledger. A city is already part of its parent population.
pub fn city_population_reference(city_key: &str) -> io::Result<Option<Value>> {
    let bytes = include_bytes!("../../../../data/historical_population_1900/cities_1900.jsonl.gz");
    for row in catalogue_rows(bytes) {
        let row = row?;
        if row["city_key"].as_str() == Some(city_key) {
            return Ok(Some(row));
        }
    }
    Ok(None)
}

#[derive(Default, Serialize)]
pub struct PopulationArchive {
    pub geographies: Vec<Value>,
    pub geography_children: Vec<Value>,
    pub dated_population: Vec<Value>,
    pub dated_structure: Vec<Value>,
    /// Research candidates can differ from the catalogue unit in scope or date.
    pub candidate_research_population: Vec<Value>,
    pub sources: Vec<Value>,
}

/// Coverage of dated historical panels. It does not allocate live residents.
pub fn structural_coverage_reference(unit: &str) -> io::Result<Option<Value>> {
    let bytes = include_bytes!("../../../../data/historical_population_1900/structure_coverage_1900.json");
    let catalogue: Value = serde_json::from_slice(bytes)?;
    let scope = if unit == "world" {
        &catalogue["world"]
    } else if unit == "region:unassigned" {
        &catalogue["no_unique_research_region"]
    } else if let Some(region) = unit.strip_prefix("region:") {
        &catalogue["research_regions"][region]
    } else {
        &catalogue["opening_roots"][unit]
    };
    let Some(dimensions) = scope["dimensions"].as_object() else { return Ok(None); };
    let panel_ids: BTreeSet<_> = dimensions.values().flat_map(|value| {
        ["reviewed_panels", "candidate_panels"].into_iter()
            .filter_map(|key| value[key].as_array()).flatten().filter_map(Value::as_str)
    }).collect();
    let panels: BTreeMap<_, _> = panel_ids.into_iter().map(|key| (key, &catalogue["panels"][key])).collect();
    Ok(Some(serde_json::json!({
        "scope": scope,
        "panels": panels,
        "opening_date": catalogue["opening_date"],
        "accounting_note": catalogue["accounting_note"],
    })))
}

pub(super) fn historical_source(id: &str) -> io::Result<Option<Value>> {
    Ok(sources()?.iter().find(|row| row["id"].as_str() == Some(id)).cloned())
}

fn sources() -> io::Result<&'static [Value]> {
    static SOURCES: OnceLock<Result<Vec<Value>, serde_json::Error>> = OnceLock::new();
    let bytes = include_bytes!("../../../../data/historical_population_1900/sources.json");
    SOURCES.get_or_init(|| serde_json::from_slice(bytes)).as_ref().map(Vec::as_slice)
        .map_err(|error| invalid(error.to_string()))
}

/// Historical evidence can be queried independently of whether a place has an
/// account in the current game. Matching rows can use overlapping scopes and dates.
pub fn population_archive(unit: &str) -> io::Result<Option<PopulationArchive>> {
    Ok(population_archive_scope(unit)?.0)
}

pub(super) fn population_archive_scope(unit: &str) -> io::Result<(Option<PopulationArchive>, Option<Value>)> {
    let geography = include_bytes!("../../../../data/historical_population_1900/geography_1900.jsonl.gz");
    let population = include_bytes!("../../../../data/historical_population_1900/population_1900.jsonl.gz");
    let structure = include_bytes!("../../../../data/historical_population_1900/demography_1900.jsonl.gz");
    let mut archive = PopulationArchive::default();
    for row in catalogue_rows(geography) {
        let row = row?;
        if row["id"].as_str() == Some(unit) {
            archive.geographies.push(row);
        } else if row["parent"].as_str() == Some(unit) || contains_text(&row["parent_ids"], unit) {
            archive.geography_children.push(row);
        }
    }
    let dated_units = linked_units(&archive.geographies, "historical_observation_ids");
    let research_units = linked_units(&archive.geographies, "study_candidates");
    let city_key = unit.strip_prefix("city:").or_else(|| {
        if unit.starts_with("place:") && dated_units.len() == 1 { dated_units.first().copied() } else { None }
    });
    let city_reference = city_key.map(city_population_reference).transpose()?.flatten();
    for row in catalogue_rows(population) {
        let row = row?;
        let Some(source_unit) = row["unit_id"].as_str() else { continue; };
        if source_unit == unit || row["wwo_id"].as_str() == Some(unit) || dated_units.contains(source_unit)
            || city_reference.as_ref().is_some_and(|city| row["city_key"] == city["city_key"])
        {
            archive.dated_population.push(row);
        } else if research_units.contains(source_unit) {
            archive.candidate_research_population.push(row);
        }
    }
    for row in catalogue_rows(structure) {
        let row = row?;
        if row["unit_id"].as_str().is_some_and(|source_unit| source_unit == unit || dated_units.contains(source_unit))
            || contains_text(&row["opening_reference_ids"], unit)
        {
            archive.dated_structure.push(row);
        }
    }
    let source_ids: BTreeSet<_> = archive.dated_population.iter()
        .chain(&archive.dated_structure).chain(&archive.candidate_research_population)
        .filter_map(|row| row["source_id"].as_str()).collect();
    archive.sources = sources()?.iter().filter(|row| row["id"].as_str().is_some_and(|id| source_ids.contains(id))).cloned().collect();
    Ok(((!archive.geographies.is_empty() || !archive.geography_children.is_empty() || !archive.dated_population.is_empty()
        || !archive.dated_structure.is_empty()).then_some(archive), city_reference))
}

pub(super) fn traits_for_scope(unit: &str) -> io::Result<(Vec<Value>, Vec<Value>)> {
    static TRAITS: OnceLock<io::Result<(Vec<Value>, Vec<Value>)>> = OnceLock::new();
    let (rows, sources) = TRAITS.get_or_init(|| {
        let raw = include_str!("../../../../data/historical_population_1900/collections/pop_traits/traits.jsonl");
        let sources = include_bytes!("../../../../data/historical_population_1900/collections/pop_traits/sources.json");
        Ok((raw.lines().map(serde_json::from_str).collect::<Result<_, _>>()?, serde_json::from_slice(sources)?))
    }).as_ref().map_err(|error| invalid(error.to_string()))?;
    let matched: Vec<_> = rows.iter().filter(|row| {
        unit == "world" || row["place_id"].as_str() == Some(unit) || row["observed_unit_id"].as_str() == Some(unit)
            || unit.strip_prefix("trait:").is_some_and(|id| row["id"].as_str() == Some(id))
            || unit.strip_prefix("region:").is_some_and(|region| row["region"].as_str() == Some(region))
            || row["opening_links"].as_array().into_iter().flatten().any(|link| link["unit_id"].as_str() == Some(unit))
    }).cloned().collect();
    let ids: BTreeSet<_> = matched.iter().filter_map(|row| row["source_id"].as_str()).collect();
    let matched_sources = sources.iter().filter(|row| row["id"].as_str().is_some_and(|id| ids.contains(id))).cloned().collect();
    Ok((matched, matched_sources))
}

fn contains_text(items: &Value, text: &str) -> bool {
    items.as_array().into_iter().flatten().any(|item| item.as_str() == Some(text))
}

fn linked_units<'a>(geographies: &'a [Value], field: &str) -> BTreeSet<&'a str> {
    geographies.iter().filter_map(|row| row[field].as_array()).flatten()
        .filter_map(Value::as_str).collect()
}

fn catalogue_rows(bytes: &[u8]) -> impl Iterator<Item = io::Result<Value>> + '_ {
    BufReader::new(flate2::read::GzDecoder::new(bytes)).lines()
        .map(|line| Ok(serde_json::from_str(&line?)?))
}

fn read_estimates() -> io::Result<Estimates> {
    let table: SourceTable<'static> = serde_json::from_slice(SOURCE)?;
    if table.schema_id != SCHEMA || table.common_methods.population.is_empty() {
        return Err(invalid("invalid opening population estimate metadata"));
    }
    let column = |field| table.field_order.iter().position(|&key| key == field)
        .ok_or_else(|| invalid(format!("missing opening population estimate column {field}")));
    let unit = column("entity_id")?;
    let lower = column("population_lower")?;
    let value = column("population_value")?;
    let upper = column("population_upper")?;
    let confidence = column("population_confidence_bp")?;
    let mut estimates = BTreeMap::new();
    for row in table.rows {
        if row.len() != table.field_order.len() { return Err(invalid("invalid opening population estimate row")); }
        let id = row[unit].as_str().filter(|id| !id.is_empty())
            .ok_or_else(|| invalid("missing opening population estimate entity"))?;
        let number = |index: usize| row[index].as_u64().ok_or_else(|| invalid("invalid opening population estimate number"));
        let estimate = HistoricalPopulationEstimate {
            value: number(value)?, lower: number(lower)?, upper: number(upper)?, confidence_bp: number(confidence)?,
            calibration_date: CALIBRATION_DATE, source_table: SCHEMA, source_method: table.common_methods.population,
        };
        if estimate.lower > estimate.value || estimate.value > estimate.upper || estimate.upper > MAX_POPULATION
            || estimate.confidence_bp > 10_000 || estimates.insert(id.to_owned(), estimate).is_some()
        {
            return Err(invalid("inconsistent opening population estimate"));
        }
    }
    Ok(estimates)
}
