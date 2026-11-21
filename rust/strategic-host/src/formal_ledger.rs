use serde::Serialize;
use serde_json::{json, Value};
use std::{collections::{BTreeMap, BTreeSet}, io};
use crate::formal_save::{field, integer, invalid, lookup, map, tagged, typed_int, typed_map};

pub(crate) const CURRENCY: &str = "denomination:formal_simulation_minor_v1";
const SOURCE: &str = "account:scenario_livelihood_r1";
const SOURCE_OWNER: &str = "scenario:livelihood_r1";
pub(crate) const MAX_AMOUNT: i64 = 9_007_199_254_740_991;
const PERSONAL_ROLE: &str = "personal_cash";
const MARKET_ROLE: &str = "market_receipts";
pub(crate) const TRANSPORT_ACCOUNT: &str = "account:transport_receipts";
const TRANSPORT_OWNER: &str = "service:formal_transport";
const TRANSPORT_ROLE: &str = "transport_receipts";

struct Account {
    owner: String,
    denomination: String,
    role: String,
    balance: i64,
    reserved: i64,
}

pub struct Ledger {
    accounts: BTreeMap<String, Account>,
    transaction_indexes: BTreeMap<String, usize>,
    last_minute: i64,
    budget: i64,
    transactions: Vec<Value>,
    regional: Option<RegionalLedger>,
}

struct RegionalLedger {
    reservations: BTreeMap<String, Reservation>,
    currency_budgets: Option<Value>,
    payment_batches: BTreeMap<String, Value>,
}

struct Reservation {
    account_id: String,
    amount: i64,
}

#[derive(Serialize)]
pub struct Balance<'a> {
    pub account_id: &'a str,
    pub denomination: &'a str,
    pub cash: i64,
    pub available: i64,
    pub reserved: i64,
}

pub struct PaymentLeg<'a> {
    pub id: &'a str,
    pub from: &'a str,
    pub to: &'a str,
    pub amount: i64,
    pub kind: &'a str,
    pub reference: &'a str,
}

pub struct PersonalReceipt<'a> {
    pub id: &'a str,
    pub reference: &'a str,
    pub incoming: bool,
    pub kind: &'a str,
    pub minute: i64,
    pub amount: i64,
}

struct Batch<'a> {
    ids: Vec<&'a str>,
    minute: i64,
}

#[derive(PartialEq)]
struct Receipt<'a> {
    id: &'a str,
    from: &'a str,
    to: &'a str,
    currency: &'a str,
    amount: i64,
    minute: i64,
}

impl Ledger {
    pub(crate) fn open_person_cash(&mut self, owner: &str) -> io::Result<()> {
        let id = owner.strip_prefix("person:").filter(|id| !id.is_empty())
            .ok_or_else(|| invalid("invalid runtime personal account owner"))?;
        let account = format!("account:personal:{id}");
        if self.accounts.contains_key(&account) || self.default_account(owner).is_some() {
            return Err(invalid("personal account is already open"));
        }
        self.accounts.insert(account, Account::new(owner, PERSONAL_ROLE, 0));
        Ok(())
    }

    pub(crate) fn open_firm(&mut self, owner: &str, account: &str, cash: i64) -> io::Result<()> {
        if !owner.starts_with("firm:") || !account.starts_with("account:")
            || self.accounts.contains_key(account) || self.default_account(owner).is_some()
            || !(0..=MAX_AMOUNT - self.budget).contains(&cash) || (cash != 0 && self.last_minute != 0)
        {
            return Err(invalid("invalid opening firm account"));
        }
        self.regional.get_or_insert_with(|| RegionalLedger {
            reservations: BTreeMap::new(), currency_budgets: None, payment_batches: BTreeMap::new(),
        });
        self.accounts.insert(account.to_owned(), Account::new(owner, "r1_firm", 0));
        self.budget += cash;
        self.accounts.get_mut(SOURCE).unwrap().balance += cash;
        if cash > 0 {
            self.transfer(&format!("opening:{owner}"), SOURCE, account, cash, 0, "opening_cash", owner)?;
        }
        Ok(())
    }

    pub fn personal_receipts(&self, owner: &str) -> impl Iterator<Item = PersonalReceipt<'_>> {
        let account = self.default_account(owner).map(|balance| balance.account_id);
        self.transactions.iter().rev().filter_map(move |row| {
            let receipt = Receipt::read(row, self.regional.is_some()).ok()?;
            let incoming = Some(receipt.to) == account;
            if !incoming && Some(receipt.from) != account { return None; }
            Some(PersonalReceipt {
                id: receipt.id, reference: string(map(row).ok()?, "reference_id").ok()?,
                incoming, kind: string(map(row).ok()?, "kind").ok()?, minute: receipt.minute, amount: receipt.amount,
            })
        })
    }

    pub(crate) fn last_minute(&self) -> i64 { self.last_minute }

    pub(crate) fn has_purchase(&self, owner: &str, record: &str) -> bool {
        let account = self.default_account(owner).map(|balance| balance.account_id);
        self.transaction_indexes.get(&format!("purchase:{record}"))
            .and_then(|index| Receipt::read(&self.transactions[*index], self.regional.is_some()).ok())
            .is_some_and(|receipt| Some(receipt.from) == account)
    }

    pub(crate) fn initialize_people<'a>(endowments: impl IntoIterator<Item = (&'a str, i64)>) -> io::Result<Self> {
        let mut ledger = Self {
            accounts: BTreeMap::from([
                (SOURCE.to_owned(), Account::new(SOURCE_OWNER, "opening_source", 0)),
            ]),
            transaction_indexes: BTreeMap::new(),
            last_minute: 0,
            budget: 0,
            transactions: Vec::new(),
            regional: None,
        };
        let mut people = Vec::new();
        for (person, cash) in endowments {
            let person_key = person.strip_prefix("person:").filter(|key| !key.is_empty())
                .ok_or_else(|| invalid("invalid opening person ID"))?;
            let account_id = format!("account:personal:{person_key}");
            if !(0..=MAX_AMOUNT - ledger.budget).contains(&cash)
                || ledger.accounts.insert(account_id.clone(), Account::new(person, PERSONAL_ROLE, 0)).is_some()
            {
                return Err(invalid("invalid endowment or repeated opening person"));
            }
            ledger.budget += cash;
            people.push((person, account_id, cash));
        }
        ledger.accounts.get_mut(SOURCE).unwrap().balance = ledger.budget;
        for (person, account_id, cash) in people {
            if cash > 0 {
                let id = format!("opening:{person}");
                ledger.transfer(&id, SOURCE, &account_id, cash, 0, "opening_cash", person)?;
            }
        }
        Ok(ledger)
    }

    pub(crate) fn buy_from_market(
        &mut self, buyer: &str, market: &str, reference: &str, amount: i64, minute: i64,
    ) -> io::Result<()> {
        let account = self.default_account(buyer).ok_or_else(|| invalid("missing personal cash account"))?;
        let from = account.account_id.to_owned();
        if !matches!(self.accounts[&from].role.as_str(), PERSONAL_ROLE | "r1_firm") {
            return Err(invalid("buyer lacks a spending account"));
        }
        let (to, created) = self.market_receipts_account(market)?;
        let id = format!("purchase:{reference}");
        let result = self.transfer(&id, &from, &to, amount, minute, "purchase", reference);
        if result.is_err() && created {
            self.accounts.remove(&to);
        }
        result
    }

    fn market_receipts_account(&mut self, market: &str) -> io::Result<(String, bool)> {
        let to = format!("account:market_receipts:{market}");
        let created = !self.accounts.contains_key(&to);
        if created {
            if self.default_account(market).is_some() {
                return Err(invalid("market already has a different account"));
            }
            self.accounts.insert(to.clone(), Account::new(market, MARKET_ROLE, 0));
        } else {
            let seller = &self.accounts[&to];
            if seller.role != MARKET_ROLE || seller.owner != market {
                return Err(invalid("invalid market receipt account"));
            }
        }
        Ok((to, created))
    }

    pub(crate) fn counter_holds(&self) -> impl Iterator<Item = (&str, &str, i64)> {
        self.regional.iter().flat_map(|r| r.reservations.range("counter:".to_owned()..))
            .take_while(|(id, _)| id.starts_with("counter:"))
            .map(|(id, row)| (id.as_str(), row.account_id.as_str(), row.amount))
    }

    /// Release the entire order hold and settle both the market's goods and the shop's labor.
    pub(crate) fn settle_counter_purchase(
        &mut self, person: &str, market: &str, firm: &str, hold: &str, reference: &str,
        goods: i64, fee: i64, minute: i64,
    ) -> io::Result<()> {
        let payer = self.default_account(person).ok_or_else(|| invalid("缺少订货人账户。"))?.account_id.to_owned();
        let merchant = self.default_account(firm).ok_or_else(|| invalid("缺少商号账户。"))?.account_id.to_owned();
        let reserved = self.regional.as_ref().and_then(|r| r.reservations.get(hold))
            .filter(|r| r.account_id == payer && goods.checked_add(fee).is_some_and(|cost| cost <= r.amount))
            .ok_or_else(|| invalid("订货准备金不足。"))?.amount;
        let (seller, created) = self.market_receipts_account(market)?;
        let result = self.batch_payment(hold, &[
            PaymentLeg { id: &format!("purchase:{reference}"), from: &payer, to: &seller, amount: goods, kind: "purchase", reference },
            PaymentLeg { id: &format!("service:{hold}"), from: &payer, to: &merchant, amount: fee, kind: "service_fee", reference: hold },
        ], minute, &BTreeMap::from([(hold, reserved)]));
        if result.is_err() && created { self.accounts.remove(&seller); }
        result
    }

    pub(crate) fn ensure_transport_account(&mut self) -> io::Result<()> {
        if let Some(account) = self.accounts.get(TRANSPORT_ACCOUNT) {
            return if account.owner == TRANSPORT_OWNER && account.role == TRANSPORT_ROLE && account.denomination == CURRENCY {
                Ok(())
            } else {
                Err(invalid("运输收款账户身份不符。"))
            };
        }
        if self.default_account(TRANSPORT_OWNER).is_some() {
            return Err(invalid("运输收款方已绑定其他账户。"));
        }
        self.accounts.insert(TRANSPORT_ACCOUNT.to_owned(), Account::new(TRANSPORT_OWNER, TRANSPORT_ROLE, 0));
        Ok(())
    }

    pub(crate) fn has_payment(&self, id: &str, from: &str, to: &str, amount: i64, kind: &str, reference: &str) -> bool {
        let Some(row) = self.transaction_indexes.get(id).and_then(|&i| self.transactions.get(i)) else {
            return false;
        };
        Receipt::read(row, self.regional.is_some()).is_ok_and(|r| r.from == from && r.to == to && r.amount == amount && r.currency == CURRENCY)
            && map(row).is_ok_and(|fields| string(fields, "kind").ok() == Some(kind)
                && string(fields, "reference_id").ok() == Some(reference))
    }

    pub(crate) fn material_receipt_count(&self) -> usize {
        self.transaction_indexes.range("material:".to_owned()..)
            .take_while(|(id, _)| id.starts_with("material:")).count()
    }

    pub(crate) fn payment_minute(&self, id: &str) -> Option<i64> {
        let row = &self.transactions[*self.transaction_indexes.get(id)?];
        Receipt::read(row, self.regional.is_some()).ok().map(|r| r.minute)
    }

    pub(crate) fn freight_transaction_counts(&self) -> (usize, usize) {
        let count = |prefix: &str| self.transaction_indexes.range(prefix.to_owned()..)
            .take_while(|(id, _)| id.starts_with(prefix)).count();
        (count("purchase:freight-lot:"), count("sale:freight-lot:"))
    }

    pub(crate) fn pay_market_bid(&mut self, market: &str, seller: &str, reference: &str, amount: i64, minute: i64) -> io::Result<()> {
        let from = format!("account:market_receipts:{market}");
        let market_account = self.accounts.get(&from).filter(|a| a.role == MARKET_ROLE && a.owner == market && a.denomination == CURRENCY)
            .ok_or_else(|| invalid("目的地市场尚无实收资金。"))?;
        if amount > market_account.balance - market_account.reserved {
            return Err(invalid("目的地市场的可用实收资金不足。"));
        }
        let to = self.default_account(seller).map(|balance| balance.account_id.to_owned())
            .filter(|id| matches!(self.accounts[id].role.as_str(), PERSONAL_ROLE | "r1_firm"))
            .ok_or_else(|| invalid("货主缺少个人现金账户。"))?;
        self.transfer(&format!("sale:{reference}"), &from, &to, amount, minute, "freight_sale", reference)
    }

    fn post(&mut self, receipt: Receipt<'_>, kind: &str, reference: &str) -> io::Result<()> {
        if let Some(&index) = self.transaction_indexes.get(receipt.id) {
            let old = &self.transactions[index];
            let fields = map(old)?;
            if Receipt::read(old, self.regional.is_some())? == receipt
                && string(fields, "kind")? == kind
                && string(fields, "reference_id")? == reference
            {
                return Ok(());
            }
            return Err(invalid("formal transaction ID conflicts with a recorded payment"));
        }
        if receipt.id.is_empty() || reference.is_empty() || !valid_kind(kind, self.regional.is_some())
            || receipt.minute < self.last_minute || !(1..=MAX_AMOUNT).contains(&receipt.amount)
        {
            return Err(invalid("invalid or out-of-order formal transaction"));
        }
        self.apply_receipts(std::slice::from_ref(&receipt), &BTreeMap::new())?;
        self.append_receipt(receipt, kind, reference);
        Ok(())
    }

    fn append_receipt(&mut self, receipt: Receipt<'_>, kind: &str, reference: &str) {
        self.transaction_indexes.insert(receipt.id.to_owned(), self.transactions.len());
        self.last_minute = receipt.minute;
        self.transactions.push(receipt.snapshot(kind, reference));
    }

    pub fn transfer(
        &mut self, id: &str, from: &str, to: &str, amount: i64, minute: i64, kind: &str, reference: &str,
    ) -> io::Result<()> {
        let currency = self.accounts.get(from).ok_or_else(|| invalid("missing source account"))?.denomination.clone();
        self.post(Receipt { id, from, to, amount, minute, currency: &currency }, kind, reference)
    }

    pub fn reserve(&mut self, id: &str, account_id: &str, amount: i64) -> io::Result<()> {
        let regional = self.regional.as_mut().ok_or_else(|| invalid("regional ledger support is unavailable"))?;
        if id.is_empty() || !(1..=MAX_AMOUNT).contains(&amount) {
            return Err(invalid("invalid reservation"));
        }
        if let Some(existing) = regional.reservations.get(id) {
            return if existing.account_id == account_id && existing.amount == amount {
                Ok(())
            } else {
                Err(invalid("reservation ID conflicts with an existing hold"))
            };
        }
        let account = self.accounts.get_mut(account_id).ok_or_else(|| invalid("unknown reserved account"))?;
        if amount > account.balance - account.reserved {
            return Err(invalid("reservation exceeds available funds"));
        }
        account.reserved += amount;
        regional.reservations.insert(id.to_owned(), Reservation { account_id: account_id.to_owned(), amount });
        Ok(())
    }

    pub fn release(&mut self, id: &str, amount: i64) -> io::Result<()> {
        let regional = self.regional.as_mut().ok_or_else(|| invalid("regional ledger support is unavailable"))?;
        let reservation = regional.reservations.get_mut(id).ok_or_else(|| invalid("unknown reservation"))?;
        if !(1..=reservation.amount).contains(&amount) {
            return Err(invalid("invalid reservation release"));
        }
        self.accounts.get_mut(&reservation.account_id).unwrap().reserved -= amount;
        reservation.amount -= amount;
        if reservation.amount == 0 {
            regional.reservations.remove(id);
        }
        Ok(())
    }

    /// Commit all debits, credits and releases together. Incoming funds cannot
    /// cover a debit in the same settlement.
    pub fn batch_payment(
        &mut self, id: &str, legs: &[PaymentLeg<'_>], minute: i64, releases: &BTreeMap<&str, i64>,
    ) -> io::Result<()> {
        let regional = self.regional.as_ref().ok_or_else(|| invalid("regional ledger support is unavailable"))?;
        if id.is_empty() || regional.payment_batches.contains_key(id) || legs.len() > 512
            || (legs.is_empty() && !releases.is_empty()) || !(self.last_minute..=MAX_AMOUNT).contains(&minute)
        {
            return Err(invalid("invalid or repeated regional payment batch"));
        }
        let mut released_by_account = BTreeMap::new();
        for (&key, &amount) in releases {
            let reservation = regional.reservations.get(key).ok_or_else(|| invalid("unknown reservation"))?;
            if !(1..=reservation.amount).contains(&amount) {
                return Err(invalid("invalid payment reservation release"));
            }
            *released_by_account.entry(reservation.account_id.clone()).or_insert(0) += amount;
        }
        let mut ids = BTreeSet::new();
        let receipts = legs.iter().map(|leg| {
            if leg.id.is_empty() || !ids.insert(leg.id) || self.transaction_indexes.contains_key(leg.id)
                || leg.reference.is_empty() || !valid_kind(leg.kind, true) || !(1..=MAX_AMOUNT).contains(&leg.amount)
            {
                return Err(invalid("invalid or repeated regional payment leg"));
            }
            let source = self.accounts.get(leg.from).ok_or_else(|| invalid("missing source account"))?;
            Ok((leg, source.denomination.clone()))
        }).collect::<io::Result<Vec<_>>>()?;
        let receipts = receipts.iter().map(|(leg, currency)| Receipt {
            id: leg.id, from: leg.from, to: leg.to, amount: leg.amount, minute, currency,
        }).collect::<Vec<_>>();
        self.apply_receipts(&receipts, &released_by_account)?;
        for (&key, &amount) in releases {
            self.release(key, amount).expect("payment preparation checked all releases");
        }
        let regional = self.regional.as_mut().unwrap();
        regional.payment_batches.insert(id.to_owned(), typed_map([
            ("transactions", json!(["array", legs.iter().map(|leg| leg.id).collect::<Vec<_>>()])),
            ("releases", typed_map(releases.iter().map(|(id, amount)| (id, typed_int(*amount))))),
            ("minute", typed_int(minute)),
        ]));
        for (receipt, leg) in receipts.into_iter().zip(legs) {
            self.append_receipt(receipt, leg.kind, leg.reference);
        }
        Ok(())
    }

    pub fn snapshot(&self) -> Value {
        let accounts = self.accounts.iter().map(|(id, account)| typed_map([
            ("account_id", json!(id)),
            ("owner_id", json!(account.owner)),
            ("denomination", json!(account.denomination)),
            ("role", json!(account.role)),
            ("balance", typed_int(account.balance)),
        ])).collect::<Vec<_>>();
        let mut fields = vec![
            ("schema_id", json!("formal_ledger_state_v1")),
            ("denomination", json!(CURRENCY)),
            ("scenario_budget", typed_int(self.budget)),
            ("accounts", json!(["array", accounts])),
            ("transactions", json!(["array", self.transactions])),
        ];
        if let Some(regional) = &self.regional {
            let reservations = regional.reservations.iter().map(|(id, reservation)| {
                (id, typed_map([
                    ("account_id", json!(reservation.account_id)),
                    ("amount", typed_int(reservation.amount)),
                ]))
            });
            fields.push(("r1_reservations", typed_map(reservations)));
            if let Some(budgets) = &regional.currency_budgets {
                fields.push(("currency_budgets", budgets.clone()));
            }
            if !regional.payment_batches.is_empty() {
                fields.push(("payment_batches", typed_map(regional.payment_batches.iter()
                    .map(|(id, row)| (id, row.clone())))));
            }
        }
        typed_map(fields)
    }

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
                    || role == TRANSPORT_ROLE && id == TRANSPORT_ACCOUNT && owner == TRANSPORT_OWNER && currency == CURRENCY
                    || native && matches!(role, "r1_firm" | "r1_cohort" | "r1_carrier"))
                {
                    return Err(invalid("unknown ledger account role"));
                }
                0
            };
            accounts.insert(id.to_owned(), Account {
                owner: owner.to_owned(), denomination: currency.to_owned(), role: role.to_owned(), balance, reserved: 0,
            });
        }
        if sources.values().any(|(id, _)| !accounts.contains_key(id)) { return Err(invalid("missing scenario source account")); }

        let mut ledger = Self {
            accounts,
            transaction_indexes: BTreeMap::new(),
            last_minute: 0,
            budget: sources[CURRENCY].1,
            transactions: Vec::new(),
            regional: native.then(|| RegionalLedger {
                reservations: BTreeMap::new(),
                currency_budgets: budgets.cloned(),
                payment_batches: BTreeMap::new(),
            }),
        };
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
            if ledger.regional.as_mut().unwrap().payment_batches.insert(id.to_owned(), pair[1].clone()).is_some() {
                return Err(invalid("duplicate ledger batch ID"));
            }
        }
        let mut previous_minute = 0;
        let transactions = tagged(field(header, "transactions")?, "array")?;
        let receipts = transactions.iter().enumerate().map(|(index, row)| {
            let receipt = Receipt::read(row, native)?;
            if ledger.transaction_indexes.insert(receipt.id.to_owned(), index).is_some() || previous_minute > receipt.minute {
                return Err(invalid("duplicate or out-of-order ledger receipt"));
            }
            previous_minute = receipt.minute;
            Ok(receipt)
        }).collect::<io::Result<Vec<_>>>()?;
        let mut index = 0;
        let no_releases = BTreeMap::new();
        while let Some(receipt) = receipts.get(index) {
            let count = if let Some(id) = batch_by_receipt.get(receipt.id) {
                let batch = remaining_batches.remove(id).ok_or_else(|| invalid("repeated payment batch"))?;
                let same = receipts.get(index..index + batch.ids.len()).is_some_and(|rows| {
                    rows.iter().zip(&batch.ids).all(|(row, id)| row.id == *id && row.minute == batch.minute)
                });
                if !same { return Err(invalid("noncontiguous or missing atomic payment legs")); }
                batch.ids.len()
            } else { 1 };
            ledger.apply_receipts(&receipts[index..index + count], &no_releases)?;
            index += count;
        }
        if !remaining_batches.is_empty() { return Err(invalid("missing atomic payment")); }
        for pair in optional_map(reservations)? {
            let key = pair[0].as_str().filter(|key| !key.is_empty()).ok_or_else(|| invalid("invalid reservation ID"))?;
            let row = map(&pair[1])?;
            if row.len() != 2 { return Err(invalid("invalid reservation")); }
            let id = string(row, "account_id")?;
            let reserved = amount(field(row, "amount")?)?;
            ledger.reserve(key, id, reserved)?;
        }
        if saved_balances.into_iter().any(|(id, saved)| ledger.accounts[id].balance != saved) {
            return Err(invalid("balances do not match recorded transactions"));
        }
        ledger.last_minute = previous_minute;
        ledger.transactions = transactions.to_vec();
        Ok(ledger)
    }

    pub fn default_account(&self, owner: &str) -> Option<Balance<'_>> {
        self.account_for(owner, CURRENCY)
    }

    pub fn account_for(&self, owner: &str, denomination: &str) -> Option<Balance<'_>> {
        let (id, account) = self.accounts.iter().find(|(_, item)| item.owner == owner && item.denomination == denomination)?;
        Some(Balance { account_id: id, denomination: &account.denomination, cash: account.balance,
            reserved: account.reserved, available: account.balance - account.reserved })
    }

    pub(crate) fn validate_wage_history<'a>(
        &self, claims: impl Iterator<Item = (&'a str, &'a str, &'a str, i64, i64)>, through: i64,
    ) -> io::Result<()> {
        let mut claims: BTreeMap<_, _> = claims.map(|(id, from, to, maturity, paid)| {
            (id, (from, to, maturity, paid))
        }).collect();
        for value in &self.transactions {
            let row = map(value)?;
            let id = string(row, "reference_id")?;
            if string(row, "kind")? != "wage" || !id.starts_with("work:") {
                continue;
            }
            let (from, to, maturity, unpaid) = claims.get_mut(id)
                .ok_or_else(|| invalid("wage payment has no completed work"))?;
            let receipt = Receipt::read(value, self.regional.is_some())?;
            if receipt.from != *from || receipt.to != *to || receipt.minute < *maturity
                || receipt.minute > through || receipt.amount > *unpaid
            {
                return Err(invalid("wage payment differs from its claim"));
            }
            *unpaid -= receipt.amount;
        }
        if claims.values().any(|(_, _, _, remaining)| *remaining != 0) {
            return Err(invalid("recorded wage payment is absent from the ledger"));
        }
        Ok(())
    }

    fn apply_receipts(&mut self, rows: &[Receipt<'_>], releases: &BTreeMap<String, i64>) -> io::Result<()> {
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
            let account = &self.accounts[id];
            let freed = releases.get(id).copied().unwrap_or(0);
            if debit > account.balance - account.reserved + freed || credit > MAX_AMOUNT
                || account.balance - debit > MAX_AMOUNT - credit
            {
                return Err(invalid("insufficient funds or payment bounds exceeded"));
            }
        }
        for (id, (debit, credit)) in totals {
            self.accounts.get_mut(id).unwrap().balance += credit - debit;
        }
        Ok(())
    }
}

impl Account {
    fn new(owner: &str, role: &str, balance: i64) -> Self {
        Self { owner: owner.to_owned(), denomination: CURRENCY.to_owned(), role: role.to_owned(), balance, reserved: 0 }
    }
}

impl<'a> Receipt<'a> {
    fn snapshot(&self, kind: &str, reference: &str) -> Value {
        typed_map([
            ("transaction_id", json!(self.id)),
            ("from_account_id", json!(self.from)),
            ("to_account_id", json!(self.to)),
            ("denomination", json!(self.currency)),
            ("amount", typed_int(self.amount)),
            ("effective_minute", typed_int(self.minute)),
            ("kind", json!(kind)),
            ("reference_id", json!(reference)),
            ("basis", json!("GENERATED_SIMULATION_ASSUMPTION")),
        ])
    }

    fn read(value: &'a Value, native: bool) -> io::Result<Self> {
        let row = map(value)?;
        let kind = string(row, "kind")?;
        let amount = amount(field(row, "amount")?)?;
        let minute = integer(field(row, "effective_minute")?)?;
        if row.len() != 9 || string(row, "basis")? != "GENERATED_SIMULATION_ASSUMPTION" || !valid_kind(kind, native) || amount == 0 || minute < 0 {
            return Err(invalid("invalid ledger receipt"));
        }
        let id = string(row, "transaction_id")?;
        if id.is_empty() || string(row, "reference_id")?.is_empty() {
            return Err(invalid("missing ledger receipt identity"));
        }
        Ok(Self { id, from: string(row, "from_account_id")?,
            to: string(row, "to_account_id")?, currency: string(row, "denomination")?, amount, minute })
    }
}

fn valid_kind(kind: &str, regional: bool) -> bool {
    matches!(kind, "opening_cash" | "employer_reserve" | "wage" | "purchase" | "transport_fare" | "transport_refund" | "freight_sale")
        || regional && matches!(kind, "goods" | "freight" | "cargo_refund" | "cargo_damages" | "cargo_extra_freight"
            | "loan_issue" | "loan_repayment" | "fx_principal" | "fx_target" | "fx_fee" | "asset_trade"
            | "dividend" | "equity_issue" | "person_travel" | "service_fee" | "lease_rent" | "capital_equipment")
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn restored_regional_ledger_uses_existing_reservations_and_atomic_payments() {
        const PERSON: &str = "person:formal_generated_country_fra_0001";
        const BUYER: &str = "account:personal:formal_generated_country_fra_0001";
        const FARM: &str = "cohort:opening:rouen_farm";
        const CARRIER: &str = "carrier:opening_french_rail";
        const SELLER_ACCOUNT: &str = "account:cohort:opening:rouen_farm";
        const FREIGHT_ACCOUNT: &str = "account:opening_french_rail";
        const FRANC: &str = "denomination:franc_1900_centime";
        const FRANC_SOURCE: &str = "account:scenario_currency:denomination:franc_1900_centime";
        let seed = Ledger::initialize_people([(PERSON, 2500)]).unwrap().snapshot();
        let mut fields = map(&seed).unwrap().to_vec();
        fields.push(json!(["r1_reservations", typed_map([
            ("order:1", typed_map([("account_id", json!(BUYER)), ("amount", typed_int(2000))])),
        ])]));
        fields.push(json!(["currency_budgets", typed_map([(FRANC, typed_int(75))])]));
        let accounts = fields.iter_mut().find(|row| row[0] == "accounts").unwrap()[1][1].as_array_mut().unwrap();
        for (id, owner, denomination, role, balance) in [
            (SELLER_ACCOUNT, FARM, CURRENCY, "r1_cohort", 0),
            (FREIGHT_ACCOUNT, CARRIER, CURRENCY, "r1_carrier", 0),
            (FRANC_SOURCE, SOURCE_OWNER, FRANC, "opening_source", 75),
            ("account:personal:francs", PERSON, FRANC, PERSONAL_ROLE, 0),
        ] {
            accounts.push(typed_map([
                ("account_id", json!(id)),
                ("owner_id", json!(owner)),
                ("denomination", json!(denomination)),
                ("role", json!(role)),
                ("balance", typed_int(balance)),
            ]));
        }
        let mut ledger = Ledger::restore(&json!(["map", fields]), true).unwrap();
        let goods = PaymentLeg {
            id: "r1:goods:1", from: BUYER, to: SELLER_ACCOUNT, amount: 1700, kind: "goods", reference: "order:1",
        };
        let freight = PaymentLeg {
            id: "r1:freight:1", from: BUYER, to: FREIGHT_ACCOUNT, amount: 300, kind: "freight", reference: "order:1",
        };
        let unsettled = ledger.snapshot();
        let legs = [goods, freight];
        let releases = BTreeMap::from([("order:1", 2000)]);
        assert!(ledger.batch_payment("delivery:1", &legs, 60, &BTreeMap::new()).is_err());
        assert_eq!(ledger.snapshot(), unsettled);
        ledger.batch_payment("delivery:1", &legs, 60, &releases).unwrap();
        assert!(ledger.batch_payment("delivery:1", &legs, 60, &releases).is_err());
        assert_eq!(ledger.default_account(PERSON).unwrap().available, 500);
        assert_eq!(ledger.default_account(PERSON).unwrap().reserved, 0);
        assert_eq!(ledger.default_account(FARM).unwrap().cash, 1700);
        assert_eq!(ledger.default_account(CARRIER).unwrap().cash, 300);
        ledger.transfer("wage:1", SELLER_ACCOUNT, BUYER, 100, 120, "wage", "work:1").unwrap();
        ledger.transfer("r1:opening:francs", FRANC_SOURCE, "account:personal:francs", 75, 120, "opening_cash", PERSON).unwrap();
        let snapshot = ledger.snapshot();
        let mut restored = Ledger::restore(&snapshot, true).unwrap();
        restored.transfer("wage:1", SELLER_ACCOUNT, BUYER, 100, 120, "wage", "work:1").unwrap();
        assert!(restored.transfer("wage:1", SELLER_ACCOUNT, BUYER, 200, 120, "wage", "work:1").is_err());
        assert_eq!(restored.default_account(PERSON).unwrap().cash, 600);
        assert_eq!(restored.account_for(PERSON, FRANC).unwrap().cash, 75);
        assert_eq!(restored.snapshot(), snapshot);
    }
}
