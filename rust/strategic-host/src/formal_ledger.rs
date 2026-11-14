use serde::Serialize;
use serde_json::Value;
use std::{collections::{BTreeMap, BTreeSet}, io};
use crate::formal_save::{field, integer, invalid, lookup, map, tagged};

const CURRENCY: &str = "denomination:formal_simulation_minor_v1";
const SOURCE: &str = "account:scenario_livelihood_r1";
const SOURCE_OWNER: &str = "scenario:livelihood_r1";
const MAX_AMOUNT: i64 = 9_007_199_254_740_991;

struct Account {
    owner: String,
    denomination: String,
    balance: i64,
    reserved: i64,
}

pub struct Ledger {
    accounts: BTreeMap<String, Account>,
}

#[derive(Serialize)]
pub struct Balance<'a> {
    pub account_id: &'a str,
    pub denomination: &'a str,
    pub cash: i64,
    pub available: i64,
    pub reserved: i64,
}

struct Batch<'a> {
    ids: Vec<&'a str>,
    minute: i64,
}

struct Receipt<'a> {
    id: &'a str,
    from: &'a str,
    to: &'a str,
    currency: &'a str,
    amount: i64,
    minute: i64,
}

impl Ledger {
    pub(crate) fn restore(value: &Value, native: bool) -> io::Result<Self> {
        let header = map(value)?;
        let reservations = lookup(header, "r1_reservations");
        let budgets = lookup(header, "currency_budgets");
        let batches = lookup(header, "payment_batches");
        if string(header, "schema_id")? != "formal_ledger_state_v1" || string(header, "denomination")? != CURRENCY
            || reservations.is_some() != native || (!native && (budgets.is_some() || batches.is_some()))
            || header.len() != 5 + usize::from(native) + usize::from(budgets.is_some()) + usize::from(batches.is_some())
        {
            return Err(invalid("invalid ledger snapshot header"));
        }
        let mut sources = BTreeMap::from([(CURRENCY, (SOURCE.to_owned(), amount(field(header, "scenario_budget")?)?))]);
        for pair in optional_map(budgets)? {
            let currency = pair[0].as_str().filter(|id| id.starts_with("denomination:") && id.len() > 13)
                .ok_or_else(|| invalid("invalid foreign currency ID"))?;
            if sources.insert(currency, (format!("account:scenario_currency:{currency}"), amount(&pair[1])?)).is_some() {
                return Err(invalid("duplicate currency in ledger"));
            }
        }
        let mut accounts = BTreeMap::new();
        let mut saved_balances = BTreeMap::new();
        let mut owners = BTreeSet::new();
        for row in tagged(field(header, "accounts")?, "array")? {
            let row = map(row)?;
            let id = string(row, "account_id")?;
            let owner = string(row, "owner_id")?;
            let currency = string(row, "denomination")?;
            let role = string(row, "role")?;
            let saved = amount(field(row, "balance")?)?;
            let (source, budget) = sources.get(currency).ok_or_else(|| invalid("unknown ledger denomination"))?;
            if row.len() != 5 || !id.starts_with("account:") || id.len() <= 8
                || !owners.insert((owner, currency)) || saved_balances.insert(id, saved).is_some()
            {
                return Err(invalid("invalid or duplicate account"));
            }
            let balance = if id == source {
                if owner != SOURCE_OWNER || role != "opening_source" { return Err(invalid("invalid scenario source account")); }
                *budget
            } else {
                if !(matches!(role, "personal_cash" | "background_payer" | "market_receipts")
                    || native && matches!(role, "r1_firm" | "r1_cohort" | "r1_carrier"))
                {
                    return Err(invalid("unknown ledger account role"));
                }
                0
            };
            accounts.insert(id.to_owned(), Account { owner: owner.to_owned(), denomination: currency.to_owned(), balance, reserved: 0 });
        }
        if sources.values().any(|(id, _)| !accounts.contains_key(id)) { return Err(invalid("missing scenario source account")); }

        let mut ledger = Self { accounts };
        let mut batch_by_receipt = BTreeMap::new();
        let mut remaining_batches = BTreeMap::new();
        for pair in optional_map(batches)? {
            let id = pair[0].as_str().filter(|s| !s.is_empty()).ok_or_else(|| invalid("invalid ledger batch ID"))?;
            let row = map(&pair[1])?;
            let ids = tagged(field(row, "transactions")?, "array")?.iter().map(|value| {
                let tx = value.as_str().ok_or_else(|| invalid("invalid batch receipt ID"))?;
                if batch_by_receipt.insert(tx, id).is_some() { return Err(invalid("duplicate batch receipt ID")); }
                Ok(tx)
            }).collect::<io::Result<Vec<_>>>()?;
            let releases = map(field(row, "releases")?)?;
            let minute = amount(field(row, "minute")?)?;
            if row.len() != 3 || ids.len() > 512 || ids.is_empty() && !releases.is_empty() {
                return Err(invalid("invalid ledger batch fields"));
            }
            for release in releases {
                if !release[0].is_string() || amount(&release[1])? == 0 {
                    return Err(invalid("invalid batch reservation release"));
                }
            }
            if !ids.is_empty() { remaining_batches.insert(id, Batch { ids, minute }); }
        }
        let mut seen = BTreeSet::new();
        let mut previous_minute = 0;
        let receipts = tagged(field(header, "transactions")?, "array")?.iter().map(|row| {
            let receipt = Receipt::read(row, native)?;
            if !seen.insert(receipt.id) || previous_minute > receipt.minute {
                return Err(invalid("duplicate or out-of-order ledger receipt"));
            }
            previous_minute = receipt.minute;
            Ok(receipt)
        }).collect::<io::Result<Vec<_>>>()?;
        let mut index = 0;
        while let Some(receipt) = receipts.get(index) {
            let count = if let Some(id) = batch_by_receipt.get(receipt.id) {
                let batch = remaining_batches.remove(id).ok_or_else(|| invalid("repeated payment batch"))?;
                let same = receipts.get(index..index + batch.ids.len()).is_some_and(|rows| {
                    rows.iter().zip(&batch.ids).all(|(row, id)| row.id == *id && row.minute == batch.minute)
                });
                if !same { return Err(invalid("noncontiguous or missing atomic payment legs")); }
                batch.ids.len()
            } else { 1 };
            ledger.apply_receipts(&receipts[index..index + count])?;
            index += count;
        }
        if !remaining_batches.is_empty() { return Err(invalid("missing atomic payment")); }
        for pair in optional_map(reservations)? {
            let row = map(&pair[1])?;
            if !pair[0].as_str().is_some_and(|key| !key.is_empty()) || row.len() != 2 { return Err(invalid("invalid reservation")); }
            let id = string(row, "account_id")?;
            let reserved = amount(field(row, "amount")?)?;
            let account = ledger.accounts.get_mut(id).ok_or_else(|| invalid("unknown reserved account"))?;
            if reserved == 0 || reserved > account.balance - account.reserved { return Err(invalid("reservation exceeds available funds")); }
            account.reserved += reserved;
        }
        if saved_balances.into_iter().any(|(id, saved)| ledger.accounts[id].balance != saved) {
            return Err(invalid("balances do not match recorded transactions"));
        }
        Ok(ledger)
    }

    pub fn default_account(&self, owner: &str) -> Option<Balance<'_>> {
        let (id, account) = self.accounts.iter().find(|(_, item)| item.owner == owner && item.denomination == CURRENCY)?;
        Some(Balance { account_id: id, denomination: &account.denomination, cash: account.balance,
            reserved: account.reserved, available: account.balance - account.reserved })
    }

    fn apply_receipts(&mut self, rows: &[Receipt<'_>]) -> io::Result<()> {
        let mut totals = BTreeMap::<&str, (i64, i64)>::new();
        for row in rows {
            let source = self.accounts.get(row.from).ok_or_else(|| invalid("missing source account"))?;
            let target = self.accounts.get(row.to).ok_or_else(|| invalid("missing destination account"))?;
            if row.from == row.to || source.denomination != row.currency || target.denomination != row.currency {
                return Err(invalid("incompatible payment accounts"));
            }
            totals.entry(row.from).or_default().0 += row.amount;
            totals.entry(row.to).or_default().1 += row.amount;
        }
        for (&id, &(debit, credit)) in &totals {
            let old = self.accounts[id].balance;
            if debit > old || credit > MAX_AMOUNT || old - debit > MAX_AMOUNT - credit {
                return Err(invalid("insufficient funds or payment bounds exceeded"));
            }
        }
        for (id, (debit, credit)) in totals {
            self.accounts.get_mut(id).unwrap().balance += credit - debit;
        }
        Ok(())
    }
}

impl<'a> Receipt<'a> {
    fn read(value: &'a Value, native: bool) -> io::Result<Self> {
        let row = map(value)?;
        let kind = string(row, "kind")?;
        let valid = matches!(kind, "opening_cash" | "employer_reserve" | "wage" | "purchase")
            || native && matches!(kind, "goods" | "freight" | "cargo_refund" | "cargo_damages" | "cargo_extra_freight"
                | "loan_issue" | "loan_repayment" | "fx_principal" | "fx_target" | "fx_fee" | "asset_trade"
                | "dividend" | "equity_issue" | "person_travel" | "service_fee" | "lease_rent" | "capital_equipment");
        let amount = amount(field(row, "amount")?)?;
        let minute = integer(field(row, "effective_minute")?)?;
        if row.len() != 9 || string(row, "basis")? != "GENERATED_SIMULATION_ASSUMPTION" || !valid || amount == 0 || minute < 0 {
            return Err(invalid("invalid ledger receipt"));
        }
        string(row, "reference_id")?;
        Ok(Self { id: string(row, "transaction_id")?, from: string(row, "from_account_id")?,
            to: string(row, "to_account_id")?, currency: string(row, "denomination")?, amount, minute })
    }
}

fn amount(value: &Value) -> io::Result<i64> {
    let value = integer(value)?;
    if (0..=MAX_AMOUNT).contains(&value) { Ok(value) } else { Err(invalid("ledger amount outside bounds")) }
}

fn string<'a>(row: &'a [Value], name: &str) -> io::Result<&'a str> {
    field(row, name)?.as_str().filter(|value| !value.is_empty()).ok_or_else(|| invalid(format!("invalid ledger {name}")))
}

fn optional_map(value: Option<&Value>) -> io::Result<&[Value]> {
    value.map_or(Ok(&[]), map)
}
