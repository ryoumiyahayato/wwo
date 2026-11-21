use crate::formal_save::{field, integer, invalid, lookup, map, tagged};
use serde_json::Value;
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet, VecDeque}, io};

use crate::formal_ledger::MAX_AMOUNT;

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct PersonalHolding {
    available_milli: i64,
    consumed_milli: i64,
    lots: VecDeque<PurchaseLot>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PurchaseLot {
    record_id: String,
    remaining_milli: i64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ConsumptionAllocation {
    pub purchase_record_id: String,
    pub quantity_milli: i64,
}

impl PersonalHolding {
    pub(crate) fn validate(&self, mut valid_lot: impl FnMut(&str) -> bool) -> bool {
        (0..=MAX_AMOUNT).contains(&self.available_milli)
            && (0..=MAX_AMOUNT).contains(&self.consumed_milli)
            && self.lots.iter().try_fold(0i64, |sum, lot| {
                ((1..=MAX_AMOUNT).contains(&lot.remaining_milli) && valid_lot(&lot.record_id))
                    .then(|| sum.checked_add(lot.remaining_milli)).flatten()
            }) == Some(self.available_milli)
    }

    pub(crate) fn available(&self) -> i64 {
        self.available_milli
    }

    pub(crate) fn check_purchase(&self, quantity_milli: i64) -> io::Result<()> {
        if !(1..=MAX_AMOUNT - self.available_milli).contains(&quantity_milli) {
            return Err(invalid("personal holding would exceed formal bounds"));
        }
        Ok(())
    }

    pub(crate) fn record_purchase(&mut self, record_id: String, quantity_milli: i64) {
        self.available_milli += quantity_milli;
        self.lots.push_back(PurchaseLot { record_id, remaining_milli: quantity_milli });
    }

    pub(crate) fn consume(&mut self, quantity_milli: i64) -> io::Result<Vec<ConsumptionAllocation>> {
        if !(1..=self.available_milli.min(MAX_AMOUNT - self.consumed_milli)).contains(&quantity_milli) {
            return Err(invalid("personal stock or consumption bounds would be exceeded"));
        }
        let mut remaining = quantity_milli;
        let mut allocations = Vec::new();
        while remaining > 0 {
            let lot = self.lots.front_mut().expect("available stock is backed by purchase lots");
            let used = remaining.min(lot.remaining_milli);
            lot.remaining_milli -= used;
            remaining -= used;
            allocations.push(ConsumptionAllocation { purchase_record_id: lot.record_id.clone(), quantity_milli: used });
            if lot.remaining_milli == 0 {
                self.lots.pop_front();
            }
        }
        self.available_milli -= quantity_milli;
        self.consumed_milli += quantity_milli;
        Ok(allocations)
    }
}

struct Portion<'a> {
    source: &'a str,
    owner: &'a str,
    location: &'a str,
    index: i64,
    quantity: i64,
    remaining: i64,
    consumed: i64,
    lost: i64,
    moved: i64,
    opened: i64,
    parent: &'a str,
}

pub(crate) fn restore(economy: &[Value], minute: i64, player: &str) -> io::Result<BTreeMap<String, i64>> {
    let mut holdings = BTreeMap::new();
    let Some(raw) = lookup(economy, "stock_lots") else { return Ok(holdings); };
    let lots = map(raw)?;
    let next = number(lots, "next_id")?;
    if lots.len() != 4 || next == 0 { return Err(invalid("invalid stock lots header")); }
    let stock = map(field(economy, "stock")?)?;
    let actor_keys = keys(map(field(economy, "actors")?)?)?;
    let config = map(field(economy, "config")?)?;
    let firms = optional_array(lookup(config, "firms"))?.iter().map(|row| string(map(row)?, "id"))
        .collect::<io::Result<BTreeSet<_>>>()?;
    let mut units = BTreeMap::new();
    for good in optional_array(lookup(config, "goods"))? {
        let row = map(good)?;
        let id = string(row, "id")?;
        if let Some(unit) = lookup(row, "unit_id") {
            units.insert(id, unit.as_str().ok_or_else(|| invalid("invalid stock unit"))?);
        }
    }
    let mut source_rows = BTreeMap::new();
    for pair in map(field(lots, "sources")?)? {
        let row = map(&pair[1])?;
        let id = string(row, "id")?;
        let quantity = number(row, "quantity")?;
        let formed = integer(field(row, "formed_minute")?)?;
        if row.len() != 7 || pair[0].as_str() != Some(id) || quantity == 0 || !(-1..=minute).contains(&formed) || string(row, "basis")?.is_empty() {
            return Err(invalid("invalid stock lot source"));
        }
        let good = string(row, "good")?;
        let unit = string(row, "unit")?;
        if !units.get(good).map_or_else(|| unit.strip_prefix("native_unit:") == Some(good), |expected| unit == *expected) {
            return Err(invalid("stock source unit does not match the commodity"));
        }
        source_rows.insert(id, (good, unit, quantity, tagged(field(row, "inputs")?, "array")?));
    }
    let mut portions = BTreeMap::new();
    for pair in map(field(lots, "portions")?)? {
        let row = map(&pair[1])?;
        let id = string(row, "id")?;
        let p = Portion {
            source: string(row, "source_id")?, owner: string(row, "owner")?, location: string(row, "location")?,
            index: id.strip_prefix("portion:").and_then(|id| id.parse().ok()).ok_or_else(|| invalid("invalid portion ID"))?,
            quantity: number(row, "quantity")?, remaining: number(row, "remaining")?, consumed: number(row, "consumed")?,
            lost: number(row, "lost")?, moved: number(row, "moved")?, opened: integer(field(row, "opened_minute")?)?,
            parent: string(row, "parent_portion_id")?,
        };
        let (good, unit, _, _) = source_rows.get(p.source).ok_or_else(|| invalid("portion refers to an unknown source"))?;
        let closed = integer(field(row, "closed_minute")?)?;
        if row.len() != 18 || pair[0].as_str() != Some(id) || p.index >= next || p.quantity == 0
            || p.quantity != p.remaining + p.consumed + p.lost + p.moved || p.opened > minute || closed > minute
            || (p.remaining == 0) != (closed >= 0) || string(row, "good")? != *good || string(row, "unit")? != *unit
            || !(actor_keys.contains(p.owner) || firms.contains(p.owner))
        {
            return Err(invalid("invalid stock portion"));
        }
        for key in ["custodian", "place_id", "acquisition_id", "reserved_for"] { string(row, key)?; }
        portions.insert(id, p);
    }

    let mut moved = BTreeMap::new();
    let mut roots = BTreeMap::new();
    let mut totals = BTreeMap::new();
    let mut projected = BTreeMap::new();
    for p in portions.values() {
        add(&mut totals, p.source, p.remaining + p.consumed + p.lost)?;
        if p.parent.is_empty() {
            add(&mut roots, p.source, p.quantity)?;
        } else {
            let parent = portions.get(p.parent).ok_or_else(|| invalid("stock portion is missing its parent"))?;
            if parent.index >= p.index || parent.source != p.source || parent.opened > p.opened { return Err(invalid("invalid stock ancestry")); }
            add(&mut moved, p.parent, p.quantity)?;
        }
        let good = source_rows[p.source].0;
        let subject = if actor_keys.contains(p.owner) { Some(p.owner) } else { p.location.strip_prefix("SITE|") };
        if let Some(subject) = subject { add(&mut projected, (subject, good), p.remaining)?; }
    }
    for (&id, &(_, _, quantity, inputs)) in &source_rows {
        if totals.get(id).copied() != Some(quantity) || roots.get(id).copied() != Some(quantity) { return Err(invalid("stock source quantity does not balance")); }
        for entry in inputs {
            let row = map(entry)?;
            let input = portions.get(string(row, "portion_id")?).ok_or_else(|| invalid("unknown recipe input portion"))?;
            if string(row, "source_id")? != input.source || number(row, "quantity")? > input.consumed { return Err(invalid("invalid stock recipe input")); }
        }
    }
    let mut losses = BTreeMap::new();
    for pair in map(field(lots, "losses")?)? {
        let row = map(&pair[1])?;
        let entries = tagged(field(row, "portions")?, "array")?;
        if row.len() != 5 || pair[0].as_str() != Some(string(row, "id")?) || entries.is_empty()
            || string(row, "basis")?.is_empty() || string(row, "process")?.is_empty() || number(row, "minute")? > minute
        { return Err(invalid("invalid stock loss")); }
        for item in entries {
            let item = map(item)?;
            let id = string(item, "portion_id")?;
            let quantity = number(item, "quantity")?;
            if item.len() != 3 || quantity == 0 || portions.get(id).map(|p| p.source) != Some(string(item, "source_id")?) {
                return Err(invalid("invalid lost stock portion"));
            }
            add(&mut losses, id, quantity)?;
        }
    }
    for (&id, p) in &portions {
        if p.lost != losses.get(id).copied().unwrap_or(0) || p.moved != moved.get(id).copied().unwrap_or(0) {
            return Err(invalid("stock movement or loss does not balance"));
        }
    }
    for pair in stock {
        let subject = pair[0].as_str().ok_or_else(|| invalid("invalid stock subject"))?;
        for pair in map(&pair[1])? {
            let good = pair[0].as_str().ok_or_else(|| invalid("invalid stock commodity"))?;
            let quantity = integer(&pair[1])?;
            if projected.remove(&(subject, good)).unwrap_or(0) != quantity { return Err(invalid("saved stock disagrees with lot projection")); }
            if subject == player && quantity > 0 { holdings.insert(good.to_owned(), quantity); }
        }
    }
    if !projected.is_empty() { return Err(invalid("stock lot has no saved projection")); }
    Ok(holdings)
}

fn add<K: Ord>(totals: &mut BTreeMap<K, i64>, key: K, value: i64) -> io::Result<()> {
    let count = totals.entry(key).or_default();
    *count = count.checked_add(value).ok_or_else(|| invalid("stock quantity overflow"))?;
    Ok(())
}

fn string<'a>(row: &'a [Value], name: &str) -> io::Result<&'a str> {
    field(row, name)?.as_str().ok_or_else(|| invalid(format!("invalid stock {name}")))
}

fn number(row: &[Value], name: &str) -> io::Result<i64> {
    let value = integer(field(row, name)?)?;
    if (0..=9_007_199_254_740_991).contains(&value) { Ok(value) } else { Err(invalid(format!("invalid stock {name}"))) }
}

fn keys(rows: &[Value]) -> io::Result<BTreeSet<&str>> {
    rows.iter().map(|pair| pair[0].as_str().ok_or_else(|| invalid("invalid stock key"))).collect()
}

fn optional_array(value: Option<&Value>) -> io::Result<&[Value]> {
    value.map_or(Ok(&[]), |value| tagged(value, "array"))
}
