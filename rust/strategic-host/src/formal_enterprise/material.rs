use super::*;
use crate::formal_clock::MINUTES_PER_DAY;

#[derive(Deserialize)]
pub(super) struct Mandate {
    firm_id: String,
    material_trade: TradeTerms,
}

#[derive(Deserialize)]
struct TradeTerms {
    operation: String,
    counterparty: String,
    good: String,
    price: i64,
    quantity_limit: i64,
    stock_floor: i64,
    enabled: bool,
}

#[derive(Deserialize)]
pub(super) struct SupplierNotice {
    actor: String,
    kind: String,
    candidate: String,
    delivery_day: i64,
}

#[derive(Clone, PartialEq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct MaterialOrder {
    pub buyer: String,
    pub seller: String,
    pub worker: String,
    pub quantity: i64,
    pub day: i64,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Delivery {
    order: MaterialOrder,
    quantity: i64,
    delivered_day: i64,
}

impl EnterpriseOpening {
    pub(crate) fn authorized_material_pair(&self, buyer: &str, seller: &str, day: i64) -> bool {
        self.supplier(buyer, day).is_some_and(|(terms, _, _, _)| terms.counterparty == seller)
    }
    fn site(&self, firm_id: &str) -> Option<&Site> {
        self.sites().find(|(firm, _)| firm.id == firm_id).map(|(_, site)| site)
    }

    fn terms(&self, firm: &str, operation: &str) -> Option<&TradeTerms> {
        let terms = &self.opening_organizations.iter().find(|row| row.firm_id == firm)?.material_trade;
        (terms.enabled && terms.operation == operation && terms.good == "grain").then_some(terms)
    }

    fn supplier(&self, buyer: &str, day: i64) -> Option<(&TradeTerms, &Site, &TradeTerms, &Site)> {
        let procurement = self.terms(buyer, "PROCURE")?;
        let buying_site = self.site(buyer)?;
        let sales = self.terms(&procurement.counterparty, "SELL")?;
        let selling_site = self.site(&procurement.counterparty)?;
        let key = format!("{}|grain|{}", procurement.counterparty, selling_site.id);
        (sales.counterparty == buyer && buying_site.place_id == selling_site.place_id
            && buying_site.enabled && selling_site.enabled && buying_site.suppliers.contains(&key)
            && sales.price > 0 && sales.price <= procurement.price
            && selling_site.prices.get("grain") == Some(&sales.price)
            && self.information.iter().any(|n| n.actor == buying_site.id && n.kind == "supplier"
                && n.candidate == key && n.delivery_day <= day))
            .then_some((procurement, buying_site, sales, selling_site))
    }
}

impl Enterprises {
    pub(super) fn valid_delivery_bounds(&self, opening: &EnterpriseOpening) -> bool {
        let limit: i64 = opening.opening_organizations.iter().filter(|org| org.material_trade.operation == "PROCURE")
            .map(|org| org.material_trade.quantity_limit).sum();
        self.deliveries.len() <= limit as usize && self.deliveries.iter().all(|delivery| {
            (1..=limit).contains(&delivery.quantity) && (1..=limit).contains(&delivery.order.quantity)
        })
    }

    pub(crate) fn established_supplier(&self, opening: &EnterpriseOpening, buyer: &str, seller: &str, day: i64) -> bool {
        !self.interrupted_supply.contains_key(buyer) && self.deliveries.iter().rev()
            .find(|delivery| delivery.order.buyer == buyer && delivery.order.seller == seller)
            .is_some_and(|delivery| day - delivery.delivered_day <= opening.stock_horizon)
    }

    pub(crate) fn interrupt_supply(&mut self, order: &MaterialOrder, day: i64) {
        if self.received_grain(&order.buyer) > 0 {
            self.interrupted_supply.insert(order.buyer.clone(), day);
        }
    }

    pub(crate) fn witnessed_delivery(&self, firm: &str, counterparty: &str, person: &str, wages: &WageClaims) -> bool {
        self.deliveries.iter().any(|delivery| {
            (delivery.order.buyer == firm && delivery.order.seller == counterparty && delivery.order.worker == person)
                || (delivery.order.seller == firm && delivery.order.buyer == counterparty
                    && wages.completed_firm_work(firm, delivery.delivered_day).iter().any(|work| work.worker == person))
        })
    }

    pub(crate) fn delivered_grain(&self, buyer: &str, seller: &str) -> (usize, i64) {
        self.deliveries.iter().filter(|delivery| delivery.order.buyer == buyer && delivery.order.seller == seller)
            .fold((0, 0), |(count, units), delivery| (count + 1, units + delivery.quantity))
    }

    pub(super) fn received_grain(&self, firm: &str) -> i64 {
        self.deliveries.iter().filter(|d| d.order.buyer == firm).map(|d| d.quantity).sum()
    }

    pub(super) fn shipped_grain(&self, firm: &str) -> i64 {
        self.deliveries.iter().filter(|d| d.order.seller == firm).map(|d| d.quantity).sum()
    }

    pub(crate) fn site_goods(&self, opening: &EnterpriseOpening, firm: &str) -> Option<(i64, i64)> {
        let site = opening.site(firm)?;
        let stock = self.sites.get(&site.id)?;
        let recipe = &site.activities[0];
        let grain = quantity(&site.stock, "grain") + self.received_grain(firm) - self.shipped_grain(firm)
            - stock.batches * quantity(&recipe.materials, "grain");
        let bread = quantity(&site.stock, "bread") + stock.batches * quantity(&recipe.outputs, "bread") - stock.sold;
        Some((grain, bread))
    }

    pub(crate) fn material_requests(&self, opening: &EnterpriseOpening, wages: &WageClaims, day: i64) -> Vec<MaterialOrder> {
        let mut orders = Vec::new();
        for (firm, site) in opening.sites() {
            let Some((buy, _, sell, _)) = opening.supplier(&firm.id, day) else { continue };
            let work = wages.completed_firm_work(&firm.id, day);
            let Some(worker) = work.first() else { continue };
            let hours: i64 = work.iter().map(|w| w.hours).sum();
            let retail = opening.retail(&firm.id, &site.id).expect("registered retail site");
            let recipe = &site.activities[0];
            if !opening.production_enabled || !site.production_enabled || !recipe.enabled { continue; }
            let staffed_batches = ((hours - retail.hours_per_day).max(0) / recipe.hours).min(recipe.capacity_units);
            let planned = staffed_batches * quantity(&recipe.materials, "grain") * opening.stock_horizon;
            let stock = self.site_goods(opening, &firm.id).expect("registered site").0;
            let amount = (planned - stock).min(buy.quantity_limit - self.received_grain(&firm.id))
                .min(sell.quantity_limit - self.shipped_grain(&buy.counterparty));
            if amount > 0 {
                orders.push(MaterialOrder { buyer: firm.id.clone(), seller: buy.counterparty.clone(),
                    worker: worker.worker.to_owned(), quantity: amount, day });
            }
        }
        orders
    }

    pub(crate) fn deliver_material(&mut self, opening: &EnterpriseOpening, ledger: &mut Ledger,
        order: &MaterialOrder, day: i64) -> io::Result<(i64, i64)> {
        if self.deliveries.iter().any(|d| d.order.day == order.day && d.order.buyer == order.buyer && d.order.seller == order.seller) {
            return Err(invalid("这笔原料订单已经交割"));
        }
        let (buy, buyer_site, sell, seller_site) = opening.supplier(&order.buyer, day)
            .filter(|(buy, _, _, _)| buy.counterparty == order.seller && (order.day + 1 == day
                || (order.day == day && self.established_supplier(opening, &order.buyer, &order.seller, day))))
            .ok_or_else(|| invalid("供货授权或当地供应商消息失效"))?;
        let (remaining, _) = self.site_goods(opening, &order.seller).ok_or_else(|| invalid("供货站点缺失"))?;
        let preserve = sell.stock_floor.max(quantity(&seller_site.activities[0].materials, "grain") * seller_site.activities[0].capacity_units);
        let available = ledger.default_account(&order.buyer).ok_or_else(|| invalid("采购方缺少账户"))?;
        let quantity = order.quantity.min(remaining - preserve).min(buy.quantity_limit - self.received_grain(&order.buyer))
            .min(sell.quantity_limit - self.shipped_grain(&order.seller))
            .min(self.sites[&seller_site.id].retail_remaining).min(self.sites[&buyer_site.id].retail_remaining);
        if quantity <= 0 { return Err(invalid("可交粮或双方在岗交接能力不足")); }
        let quantity = quantity.min(available.available / sell.price);
        if quantity == 0 { return Err(invalid("采购方可用资金不足")); }
        let from = available.account_id.to_owned();
        let to = ledger.default_account(&order.seller).ok_or_else(|| invalid("供货方缺少账户"))?.account_id.to_owned();
        let reference = order.reference();
        let amount = quantity * sell.price;
        ledger.transfer(&reference, &from, &to, amount, day * MINUTES_PER_DAY, "goods", &reference)?;
        self.sites.get_mut(&buyer_site.id).unwrap().retail_remaining -= quantity;
        self.sites.get_mut(&seller_site.id).unwrap().retail_remaining -= quantity;
        self.interrupted_supply.remove(&order.buyer);
        self.deliveries.push(Delivery { order: order.clone(), quantity, delivered_day: day });
        Ok((quantity, amount))
    }

    pub(crate) fn validate_orders(&self, opening: &EnterpriseOpening, ledger: &Ledger, wages: &WageClaims, day: i64) -> bool {
        let mut references = std::collections::BTreeSet::new();
        let mut prior = BTreeMap::new();
        self.deliveries.len() == ledger.material_receipt_count() && self.deliveries.iter().all(|delivery| {
            let order = &delivery.order;
            if !(1..=day).contains(&order.day) { return false; }
            let Some((buy, _, sell, _)) = opening.supplier(&order.buyer, order.day) else { return false };
            let Some(from) = ledger.default_account(&order.buyer) else { return false };
            let Some(to) = ledger.default_account(&order.seller) else { return false };
            let reference = order.reference();
            let pair = (&order.buyer, &order.seller);
            let schedule_valid = delivery.delivered_day == order.day + 1 ||
                (delivery.delivered_day == order.day && prior.get(&pair)
                    .is_some_and(|last| (0..=opening.stock_horizon).contains(&(delivery.delivered_day - last))));
            prior.insert(pair, delivery.delivered_day);
            delivery.delivered_day <= day && schedule_valid
                && buy.counterparty == order.seller && references.insert(reference.clone())
                && (1..=buy.quantity_limit.min(sell.quantity_limit)).contains(&order.quantity)
                && (1..=order.quantity).contains(&delivery.quantity)
                && wages.completed_firm_work(&order.buyer, order.day).iter().any(|w| w.worker == order.worker)
                && ledger.payment_minute(&reference) == Some(delivery.delivered_day * MINUTES_PER_DAY)
                && ledger.has_payment(&reference, from.account_id, to.account_id, delivery.quantity * sell.price, "goods", &reference)
        }) && self.interrupted_supply.iter().all(|(buyer, failed)| (1..=day).contains(failed)
            && self.deliveries.iter().any(|d| d.order.buyer == *buyer && d.delivered_day <= *failed)
            && self.deliveries.iter().all(|d| d.order.buyer != *buyer || d.delivered_day <= *failed))
            && opening.sites().all(|(firm, _)| {
            self.received_grain(&firm.id) <= opening.terms(&firm.id, "PROCURE").map_or(0, |terms| terms.quantity_limit)
                && self.shipped_grain(&firm.id) <= opening.terms(&firm.id, "SELL").map_or(0, |terms| terms.quantity_limit)
        })
    }
}

impl MaterialOrder {
    fn reference(&self) -> String {
        format!("material:{}:{}:{}", self.day, self.buyer, self.seller)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{formal_clock::GameClock, formal_work::WorkOpening};

    #[test]
    fn material_shortage_uses_paid_work_and_only_delivered_orders_change_stock_and_cash() {
        const BAKER: &str = "firm:opening_paris_bakery";
        const SUPPLIER: &str = "firm:opening_paris_workshop";
        let workers = ["person:formal_generated_country_fra_0001", "person:formal_generated_country_fra_0002"];
        let jobs = WorkOpening::load().unwrap();
        let opening = EnterpriseOpening::load().unwrap();
        let mut firms = Enterprises::initialize(&opening, 0);
        let mut ledger = Ledger::initialize_people(workers.map(|person| (person, 0))).unwrap();
        jobs.open_accounts(&mut ledger).unwrap();
        let mut wages = WageClaims::initialize();
        let mut clock = GameClock::default();
        let mut pending = None;
        for day in 1..=26 {
            clock.advance_minutes(MINUTES_PER_DAY).unwrap();
            wages.record_shift(workers[1], jobs.job("job:opening_paris_bakery").unwrap(), day, &ledger).unwrap();
            if day >= 25 {
                wages.record_shift(workers[0], jobs.job("job:opening_paris_workshop").unwrap(), day, &ledger).unwrap();
            }
            wages.settle_due(&mut ledger, clock, |_| false).unwrap();
            firms.settle(&opening, &wages, day);
            if let Some(order) = pending.take() {
                let cash = ledger.default_account(BAKER).unwrap().cash;
                let buyer = firms.site_goods(&opening, BAKER).unwrap().0;
                let seller = firms.site_goods(&opening, SUPPLIER).unwrap().0;
                let delivery = firms.deliver_material(&opening, &mut ledger, &order, day);
                if day == 24 {
                    assert!(delivery.is_err());
                    assert_eq!(firms.site_goods(&opening, BAKER).unwrap().0, buyer);
                    assert_eq!(ledger.default_account(BAKER).unwrap().cash, cash);
                } else {
                    let (units, paid) = delivery.unwrap();
                    assert_eq!(firms.site_goods(&opening, BAKER).unwrap().0, buyer + units);
                    assert_eq!(firms.site_goods(&opening, SUPPLIER).unwrap().0, seller - units);
                    assert_eq!(ledger.default_account(BAKER).unwrap().cash, cash - paid);
                    assert!(firms.deliver_material(&opening, &mut ledger, &order, day).is_err());
                    assert_eq!(firms.site_goods(&opening, BAKER).unwrap().0, buyer + units);
                }
            }
            let requests = firms.material_requests(&opening, &wages, day);
            if day < 23 { assert!(requests.is_empty()); }
            for order in requests {
                if firms.established_supplier(&opening, BAKER, SUPPLIER, day) {
                    firms.deliver_material(&opening, &mut ledger, &order, day).unwrap();
                } else { pending = Some(order); }
            }
        }
        assert!(firms.delivered_grain(BAKER, SUPPLIER).0 >= 2);
        assert!(firms.validate(&opening, 26));
        assert!(firms.validate_orders(&opening, &ledger, &wages, 26));
    }
}
