use super::MAX_POPULATION;
use crate::formal_save::invalid;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::BTreeMap, io, sync::OnceLock};

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
