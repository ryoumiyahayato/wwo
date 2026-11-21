use crate::{formal_ledger::Ledger, formal_save::invalid, formal_wages::WageClaims};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, io};
mod material;
pub(crate) use material::MaterialOrder;

#[derive(Default, Deserialize)]
pub(crate) struct EnterpriseOpening {
    production_enabled: bool,
    firms: Vec<Firm>,
    retail_sites: Vec<Retail>,
    opening_organizations: Vec<material::Mandate>,
    information: Vec<material::SupplierNotice>,
    stock_horizon: i64,
}

#[derive(Deserialize)]
struct Firm { id: String, sites: Vec<Site> }

#[derive(Deserialize)]
struct Site {
    id: String,
    place_id: String,
    enabled: bool,
    production_enabled: bool,
    stock: BTreeMap<String, i64>,
    prices: BTreeMap<String, i64>,
    capacity: i64,
    activities: Vec<Recipe>,
    suppliers: Vec<String>,
}

#[derive(Deserialize)]
struct Recipe {
    enabled: bool,
    hours: i64,
    capacity_units: i64,
    outputs: BTreeMap<String, i64>,
    materials: BTreeMap<String, i64>,
}

#[derive(Deserialize)]
struct Retail {
    site_id: String,
    firm_id: String,
    daily_limit: i64,
    hours_per_day: i64,
    units_per_hour: i64,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Enterprises {
    settled_day: i64,
    sites: BTreeMap<String, SiteStock>,
    #[serde(default)]
    deliveries: Vec<material::Delivery>,
    #[serde(default)]
    interrupted_supply: BTreeMap<String, i64>,
    #[serde(default)]
    contested_sales: BTreeMap<String, BTreeMap<String, ContestedSale>>,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ContestedSale {
    buyer_account: String,
    pub record: String,
    pub amount: i64,
    pub minute: i64,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct SiteStock {
    batches: i64,
    sold: i64,
    retail_remaining: i64,
}

pub struct BreadOffer<'a> {
    pub site: &'a str,
    pub firm: &'a str,
    pub quantity: i64,
    pub price: i64,
    rival_firms: Vec<&'a str>,
}

impl EnterpriseOpening {
    pub(crate) fn load() -> io::Result<Self> {
        let opening: Self = serde_json::from_slice(include_bytes!(
            "../../../data/formal/paris_employment_opening_r1.json"
        ))?;
        let mut seen = std::collections::BTreeSet::new();
        for firm in &opening.firms {
            if firm.sites.len() != 1 { return Err(invalid("opening firm must have one site")); }
        }
        for (firm, site) in opening.sites() {
            let valid_recipe = site.activities.len() == 1 && site.activities.iter().all(|recipe| {
                (1..=24).contains(&recipe.hours)
                    && (1..=site.capacity).contains(&recipe.capacity_units)
                    && (1..=10_000).contains(&quantity(&recipe.materials, "grain"))
                    && (1..=10_000).contains(&quantity(&recipe.outputs, "bread"))
                    && recipe.materials.iter().all(|(id, &n)| id == "grain" || n == 0)
                    && recipe.outputs.iter().all(|(id, &n)| id == "bread" || n == 0)
            });
            let valid_retail = opening.retail(&firm.id, &site.id).is_some_and(|retail| {
                (1..=24).contains(&retail.hours_per_day)
                    && (1..=10_000).contains(&retail.units_per_hour)
                    && (1..=10_000).contains(&retail.daily_limit)
            });
            if !seen.insert(&site.id) || !valid_recipe || !valid_retail
                || site.stock.values().any(|&n| !(0..=10_000).contains(&n))
                || !(1..=10_000).contains(&quantity(&site.prices, "bread"))
            {
                return Err(invalid("invalid native bread production and retail configuration"));
            }
        }
        Ok(opening)
    }

    fn sites(&self) -> impl Iterator<Item = (&Firm, &Site)> {
        self.firms.iter().flat_map(|firm| firm.sites.iter().map(move |site| (firm, site)))
    }

    pub(crate) fn has_firm(&self, firm: &str) -> bool { self.firms.iter().any(|row| row.id == firm) }

    fn retail(&self, firm: &str, site: &str) -> Option<&Retail> {
        self.retail_sites.iter().find(|row| row.firm_id == firm && row.site_id == site)
    }
}

impl Enterprises {
    pub(crate) fn initialize(opening: &EnterpriseOpening, day: i64) -> Self {
        Self { settled_day: day, sites: opening.sites().map(|(_, site)| (site.id.clone(), SiteStock::default())).collect(),
            ..Self::default() }
    }

    pub(crate) fn validate(&self, opening: &EnterpriseOpening, day: i64) -> bool {
        self.settled_day == day
            && self.valid_delivery_bounds(opening)
            && self.sites.len() == opening.sites().count()
            && opening.sites().all(|(firm, site)| {
                let recipe = &site.activities[0];
                let retail = opening.retail(&firm.id, &site.id).expect("validated retail site");
                self.sites.get(&site.id).is_some_and(|stock| {
                    let total_grain = quantity(&site.stock, "grain") + self.received_grain(&firm.id) - self.shipped_grain(&firm.id);
                    let max_batches = total_grain / quantity(&recipe.materials, "grain");
                    (0..=max_batches.min(day.saturating_mul(recipe.capacity_units))).contains(&stock.batches)
                        && (0..=quantity(&site.stock, "bread") + stock.batches * quantity(&recipe.outputs, "bread")).contains(&stock.sold)
                        && (0..=if day == 0 { 0 } else { retail.daily_limit }).contains(&stock.retail_remaining)
                })
            })
    }

    pub(crate) fn settle(&mut self, opening: &EnterpriseOpening, wages: &WageClaims, day: i64) {
        debug_assert_eq!(self.settled_day + 1, day);
        self.settled_day = day;
        for (firm, site) in opening.sites() {
            let grain = self.site_goods(opening, &firm.id).expect("registered site").0;
            let stock = self.sites.get_mut(&site.id).expect("registered site");
            let recipe = &site.activities[0];
            let retail = opening.retail(&firm.id, &site.id).expect("validated retail site");
            let hours = wages.completed_firm_work(&firm.id, day).iter().map(|work| work.hours).sum::<i64>();
            let sales_hours = if site.enabled { hours.min(retail.hours_per_day) } else { 0 };
            stock.retail_remaining = (sales_hours * retail.units_per_hour).min(retail.daily_limit);
            if opening.production_enabled && site.enabled && site.production_enabled && recipe.enabled {
                let material_per_batch = quantity(&recipe.materials, "grain");
                stock.batches += ((hours - sales_hours) / recipe.hours).min(recipe.capacity_units).min(grain / material_per_batch);
            }
        }
    }

    pub(crate) fn bread_offer<'a>(&self, opening: &'a EnterpriseOpening, place: &str, amount: i64) -> Option<BreadOffer<'a>> {
        let mut offers = opening.sites().filter(|(_, site)| site.place_id == place).filter_map(|(firm, site)| {
            let stock = self.sites.get(&site.id)?;
            let available = (quantity(&site.stock, "bread") + stock.batches * quantity(&site.activities[0].outputs, "bread") - stock.sold)
                .min(stock.retail_remaining);
            (available >= amount).then(|| BreadOffer {
                site: &site.id, firm: &firm.id, quantity: available, price: site.prices["bread"], rival_firms: Vec::new(),
            })
        }).collect::<Vec<_>>();
        offers.sort_unstable_by_key(|offer| (offer.price, offer.site));
        let mut contenders = offers.into_iter();
        let mut chosen = contenders.next()?;
        chosen.rival_firms = contenders.map(|offer| offer.firm).collect();
        Some(chosen)
    }

    pub(crate) fn sell_bread(
        &mut self, offer: BreadOffer<'_>, ledger: &mut Ledger, buyer: &str, requested: i64,
        record: &str, minute: i64,
    ) -> io::Result<i64> {
        if !(1..=offer.quantity).contains(&requested) { return Err(invalid("bread stock changed")); }
        let buyer = ledger.default_account(buyer).ok_or_else(|| invalid("buyer lacks a personal account"))?;
        let seller = ledger.default_account(offer.firm).ok_or_else(|| invalid("firm has no settlement account"))?;
        let from = buyer.account_id.to_owned();
        let to = seller.account_id.to_owned();
        let price = offer.price * requested;
        ledger.transfer(&format!("purchase:{record}"), &from, &to, price, minute, "purchase", record)?;
        let stock = self.sites.get_mut(offer.site).expect("quoted registered site");
        stock.sold += requested;
        stock.retail_remaining -= requested;
        for rival in offer.rival_firms {
            self.contested_sales.entry(offer.firm.into()).or_default().insert(rival.into(), ContestedSale {
                buyer_account: from.clone(), record: record.into(), amount: price, minute,
            });
        }
        Ok(price)
    }

    pub(crate) fn contested_sale(&self, winner: &str, rival: &str) -> Option<&ContestedSale> {
        self.contested_sales.get(winner)?.get(rival)
    }

    pub(crate) fn validate_sales(&self, opening: &EnterpriseOpening, ledger: &Ledger, minute: i64) -> bool {
        self.contested_sales.iter().all(|(winner, rivals)| {
            let Some(winning_site) = opening.sites().find_map(|(f,s)| (f.id == *winner).then_some(s)) else { return false };
            let Some(account) = ledger.default_account(winner) else { return false };
            !rivals.is_empty() && rivals.iter().all(|(rival, sale)| {
                rival != winner && opening.sites().any(|(f, s)| f.id == *rival && s.place_id == winning_site.place_id)
                    && (0..=minute).contains(&sale.minute) && sale.amount > 0
                    && sale.record.starts_with("personal_life:")
                    && ledger.payment_minute(&format!("purchase:{}", sale.record)) == Some(sale.minute)
                    && ledger.has_payment(&format!("purchase:{}", sale.record), &sale.buyer_account, account.account_id,
                        sale.amount, "purchase", &sale.record)
            })
        })
    }
}

fn quantity(stock: &BTreeMap<String, i64>, good: &str) -> i64 {
    stock.get(good).copied().unwrap_or_default()
}
