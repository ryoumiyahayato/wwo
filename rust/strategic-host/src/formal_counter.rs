//! Local commission shops book a customer's order against the customer's own money.
//! Goods stay in the market until handover. One completed counter hour handles one order.
use super::{GameClock, InitialWorld, MINUTES_PER_DAY};
use crate::{formal_livelihood::counts_as_food, formal_save::invalid};
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet}, io};

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct CounterBook {
    closed: BTreeSet<String>,
    orders: BTreeMap<u64, Order>,
    recent: BTreeMap<String, BTreeMap<String, Outcome>>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{formal_bootstrap::WorldBootstrap, transport::ModeSet};

    const LONDON: &str = "british_isles_1900";
    const SHOP: &str = "organization:opening_london_merchant";
    const FIRM: &str = "firm:opening_london_merchant";

    fn resume(bootstrap: &WorldBootstrap, world: &InitialWorld) -> InitialWorld {
        bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap()
    }

    #[test]
    fn counter_order_survives_resume_then_customer_receives_goods_and_staff_earn_wages() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create(LONDON).unwrap();
        let offer = world.organization_counter_offer(SHOP, "coal").unwrap();
        let total = offer.goods_centimes + offer.service_centimes;
        let cash = world.balance().unwrap().cash;
        let before = world.macro_economy.markets()[LONDON].commodities["coal"].inventory;
        assert!(world.order_at_counter(SHOP, "coal", total + 1).is_err());
        assert!(!world.organization_can_manage(SHOP, &world.player));
        world.order_at_counter(SHOP, "coal", total).unwrap();
        assert_eq!(world.balance().unwrap().reserved, total);
        assert_eq!(world.macro_economy.markets()[LONDON].commodities["coal"].inventory, before);
        assert!(world.order_at_counter(SHOP, "coal", total).is_err());
        assert!(world.set_counter_open(SHOP, false).is_err());
        let mut world = resume(&bootstrap, &world);
        world.advance_migrated_domains(2 * MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert_eq!(world.holding_milli("coal"), offer.quantity_milli);
        assert_eq!(world.balance().unwrap().cash, cash - total);
        assert_eq!(world.balance().unwrap().reserved, 0);
        assert!(world.ledger.personal_receipts(FIRM).any(|r| r.incoming && r.kind == "service_fee" && r.amount == offer.service_centimes));
        let work = world.completed_firm_work(FIRM, 2).unwrap();
        assert!(!work.is_empty());
        let worker = work[0].worker.to_owned();
        world.advance_migrated_domains(2 * MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert!(world.ledger.personal_receipts(&worker).any(|r| r.incoming && r.kind == "wage"));
        assert_eq!(resume(&bootstrap, &world).holding_milli("coal"), offer.quantity_milli);
    }

    #[test]
    fn counter_order_after_shift_start_expires_without_borrowing_elapsed_work() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create(LONDON).unwrap();
        let offer = world.organization_counter_offer(SHOP, "coal").unwrap();
        world.order_at_counter(SHOP, "coal", offer.goods_centimes + offer.service_centimes).unwrap();
        let job = world.request_job_referral("organization:opening_london_association").unwrap();
        world.apply_for_work(&job).unwrap();
        world.book_work().unwrap();
        world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        let quantity = world.holding_milli("coal");
        assert_eq!(quantity, offer.quantity_milli);

        // Isolate handover from demand-based scheduling: place the existing worker on
        // a one-hour shift with no queued orders, then take the only new order halfway through.
        assert!(world.counters.orders.values().all(|order| order.shop != SHOP));
        let worker = world.player.clone();
        let place = world.current_place(&worker).unwrap().to_owned();
        world.work.book(&world.work_opening, &worker, Some(&place), world.clock()).unwrap();
        world.advance_migrated_domains(30, &BTreeMap::new()).unwrap();
        let late = world.organization_counter_offer(SHOP, "coal").unwrap();
        let total = late.goods_centimes + late.service_centimes;
        let id = world.next_living_record;
        world.order_at_counter(SHOP, "coal", total).unwrap();
        world.advance_migrated_domains(MINUTES_PER_DAY - 30, &BTreeMap::new()).unwrap();
        assert_eq!(world.completed_firm_work(FIRM, 2).unwrap()[0].hours, 1);
        assert!(world.counters.orders.contains_key(&id));
        assert_eq!(world.holding_milli("coal"), quantity);
        let cash = world.balance().unwrap().cash;
        assert_eq!(world.balance().unwrap().reserved, total);

        // The employee keeps the contract but does not book the following day.
        world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        assert!(world.completed_firm_work(FIRM, 3).unwrap().is_empty());
        let world = resume(&bootstrap, &world);
        assert!(!world.counters.orders.contains_key(&id));
        let failed = &world.counters.recent[SHOP][&worker];
        assert_eq!(failed.order_id, id);
        assert_eq!(failed.placed, MINUTES_PER_DAY + 30);
        assert_eq!(failed.minute, 3 * MINUTES_PER_DAY);
        assert!(matches!(&failed.settlement, CounterSettlement::Released { reason } if reason.contains("工时")));
        assert_eq!(world.holding_milli("coal"), quantity);
        assert_eq!((world.balance().unwrap().reserved, world.balance().unwrap().available), (0, cash));
        assert!(world.ledger.payment_minute(&format!("purchase:personal_life:{id}")).is_none());
        assert!(world.ledger.payment_minute(&format!("service:counter:{id}")).is_none());
    }

    #[test]
    fn counter_manager_freight_debits_the_business_and_resumes_the_same_lot() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create(LONDON).unwrap();
        assert!(world.organization_freight_offer(SHOP, "coal", None).is_none());
        world.accept_organization_partnership(SHOP).unwrap();
        let cash = world.balance().unwrap().cash;
        world.set_counter_open(SHOP, false).unwrap();
        assert!(world.organization_counter_offer(SHOP, "coal").is_none());
        let (qty, price, cost) = world.organization_freight_offer(SHOP, "kerosene", None).unwrap();
        let company_cash = world.ledger.default_account(FIRM).unwrap().cash;
        let before = world.macro_economy.markets()[LONDON].commodities["kerosene"].inventory;
        let lot = world.buy_organization_freight(SHOP, "kerosene", qty, price).unwrap();
        assert_eq!(world.ledger.default_account(FIRM).unwrap().cash, company_cash - cost);
        assert_eq!(world.macro_economy.markets()[LONDON].commodities["kerosene"].inventory, before - qty as f64 / 1000.0);
        assert_eq!(world.balance().unwrap().cash, cash);
        let mut world = resume(&bootstrap, &world);
        let plan = world.quote_freight(lot, "place:paris", ModeSet::ALL).unwrap();
        let arrival = plan.arrival_minute();
        let remaining = world.ledger.default_account(FIRM).unwrap().available;
        let fare = plan.fare_centimes();
        let contribution = (fare - remaining).max(0);
        if contribution > 0 {
            assert!(world.dispatch_quoted_freight(lot, plan).is_err());
            assert_eq!(world.ledger.default_account(FIRM).unwrap().available, remaining);
            world.contribute_to_business(SHOP, contribution).unwrap();
        }
        world.dispatch_freight(lot, "place:paris", ModeSet::ALL).unwrap();
        assert_eq!(world.ledger.default_account(FIRM).unwrap().available, remaining + contribution - fare);
        let mut world = resume(&bootstrap, &world);
        // The destination only has cash actually received from a local customer's purchase.
        let market = world.macro_economy.markets()["country_fra"].id.clone();
        let price = world.macro_economy.markets()["country_fra"].commodities["potatoes"].price_centimes;
        world.buy_statistical_stock("person:formal_generated_country_fra_0001", &market, "potatoes", 100, price, "paris-household").unwrap();
        world.advance_migrated_domains(arrival, &BTreeMap::new()).unwrap();
        let (bid, revenue) = world.freight_sale_quote(lot).unwrap();
        let available = world.ledger.default_account(FIRM).unwrap().cash;
        let stock = world.macro_economy.markets()["country_fra"].commodities["kerosene"].inventory;
        world.sell_freight(lot, bid).unwrap();
        assert_eq!(world.ledger.default_account(FIRM).unwrap().cash, available + revenue);
        assert_eq!(world.macro_economy.markets()["country_fra"].commodities["kerosene"].inventory, stock + qty as f64 / 1000.0);
        let world = resume(&bootstrap, &world);
        assert_eq!(world.balance().unwrap().cash, cash - contribution);
        assert_eq!(world.freight_lots().find(|l| l.id == lot).unwrap().owner(), FIRM);
    }
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Order {
    shop: String,
    customer: String,
    good: String,
    quantity_milli: i64,
    maximum_goods: i64,
    service_fee: i64,
    placed: i64,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Outcome {
    order_id: u64,
    placed: i64,
    minute: i64,
    good: String,
    maximum_goods: i64,
    service_fee: i64,
    settlement: CounterSettlement,
}

#[derive(Deserialize, Serialize)]
#[serde(tag = "status", rename_all = "snake_case", deny_unknown_fields)]
enum CounterSettlement {
    Delivered { goods_paid: i64 },
    Released { reason: String },
}

pub struct CounterOffer {
    pub good: String,
    pub quantity_milli: i64,
    pub goods_centimes: i64,
    pub service_centimes: i64,
}

impl InitialWorld {
    pub fn counter_open(&self, shop: &str) -> bool {
        self.organization(shop).is_some_and(|org| org.is_merchant()) && !self.counters.closed.contains(shop)
    }

    pub fn set_counter_open(&mut self, shop: &str, open: bool) -> io::Result<()> {
        let org = self.organization(shop).filter(|org| org.is_merchant())
            .ok_or_else(|| invalid("没有该门市。"))?;
        if !self.organization_can_manage(shop, &self.player) || self.player_current_place() != Some(&org.place) {
            return Err(invalid("须由在场经营人调整接单。"));
        }
        if open { self.counters.closed.remove(shop); } else { self.counters.closed.insert(shop.into()); }
        Ok(())
    }

    pub(crate) fn merchant_needs_worker(&self, firm: &str) -> bool {
        self.work_opening.organization(firm).is_some_and(|shop| self.counters.orders.values().any(|o| o.shop == shop))
    }

    fn counter_quote(&self, shop: &str, person: &str, good: &str) -> Option<CounterOffer> {
        let org = self.organization(shop)?;
        if !org.is_merchant() || !self.counter_open(shop) || self.current_place(person)? != org.place
            || !org.goods.iter().any(|id| id == good) || self.counters.orders.values().any(|o| o.customer == person) {
            return None;
        }
        let job = self.work_opening.entry_job(org.jobs.first()?)?;
        // A counter handles one smallest transferable household lot (one thousandth of a catalogue unit).
        let quantity_milli = 1;
        let goods_centimes = self.macro_economy.quote(&org.unit, good, quantity_milli).ok()?;
        Some(CounterOffer { good: good.into(), quantity_milli, goods_centimes, service_centimes: job.wage_per_hour })
    }

    pub fn organization_counter_offer(&self, shop: &str, good: &str) -> Option<CounterOffer> {
        let offer = self.counter_quote(shop, &self.player, good)?;
        (self.balance()?.available >= offer.goods_centimes + offer.service_centimes).then_some(offer)
    }

    pub fn order_at_counter(&mut self, shop: &str, good: &str, expected_total: i64) -> io::Result<i64> {
        self.place_counter_order(shop, &self.player.clone(), good, expected_total)
    }

    fn place_counter_order(&mut self, shop: &str, person: &str, good: &str, expected_total: i64) -> io::Result<i64> {
        let offer = self.counter_quote(shop, person, good).ok_or_else(|| invalid("当前无法承接这份现场订单。"))?;
        let total = offer.goods_centimes + offer.service_centimes;
        if total != expected_total { return Err(invalid("货款或代办费已变动。")); }
        let id = self.next_living_record;
        if id >= crate::formal_ledger::MAX_AMOUNT as u64 { return Err(invalid("订货编号已耗尽。")); }
        let account = self.ledger.default_account(person).ok_or_else(|| invalid("订货人缺少账户。"))?.account_id.to_owned();
        self.ledger.reserve(&format!("counter:{id}"), &account, total)?;
        self.next_living_record += 1;
        self.counters.orders.insert(id, Order { shop: shop.into(), customer: person.into(), good: good.into(),
            quantity_milli: offer.quantity_milli, maximum_goods: offer.goods_centimes,
            service_fee: offer.service_centimes, placed: self.clock.snapshot().total_minutes });
        Ok(total)
    }

    pub fn counter_status(&self, shop: &str) -> Option<String> {
        let org = self.organization(shop).filter(|org| org.is_merchant())?;
        let insider = self.player_organization_role(shop).is_some();
        if !insider && self.player_current_place() != Some(&org.place) { return None; }
        let open = if self.counter_open(shop) { "接单中" } else { "暂停新订单" };
        let waiting = self.counters.orders.values().filter(|o| o.shop == shop && (insider || o.customer == self.player)).count();
        let mut status = format!("{open} · 待交付 {waiting}");
        if let Some(order) = self.counters.orders.values().find(|o| o.shop == shop && o.customer == self.player) {
            let good = self.macro_economy.commodity_info(&order.good)?.0;
            status.push_str(&format!(" · 已订{good}，预留 {}，第 {} 天前交付", order.maximum_goods + order.service_fee,
                order.placed / MINUTES_PER_DAY + 2));
        }
        let recent = self.counters.recent.get(shop);
        let last = recent.and_then(|outcomes| if insider { outcomes.values().max_by_key(|r| r.minute) } else { outcomes.get(&self.player) });
        if let Some(last) = last {
            let good = self.macro_economy.commodity_info(&last.good).map_or(last.good.as_str(), |g| g.0);
            let result = match &last.settlement {
                CounterSettlement::Delivered { goods_paid } => format!("已交货，货款 {goods_paid}，代办费 {}", last.service_fee),
                CounterSettlement::Released { reason } => format!("未交货，已解除 {} 准备金。{reason}", last.maximum_goods + last.service_fee),
            };
            status.push_str(&format!(" · 第 {} 天，订单 {}，{good}。{result}", last.minute / MINUTES_PER_DAY, last.order_id));
        }
        Some(status)
    }

    fn hand_over(&mut self, id: u64, order: &Order, minute: i64) -> io::Result<i64> {
        let org = self.organization(&order.shop).ok_or_else(|| invalid("商号不存在。"))?;
        if self.current_place(&order.customer) != Some(&org.place) { return Err(invalid("订货人未在交货地。")); }
        let firm = org.firm.clone().ok_or_else(|| invalid("缺少结算企业。"))?;
        let unit = org.unit.clone();
        let market = &self.macro_economy.markets()[&unit];
        let price = market.commodities[&order.good].price_centimes;
        let market_id = market.id.clone();
        if self.macro_economy.quote(&unit, &order.good, order.quantity_milli)? > order.maximum_goods {
            return Err(invalid("现价高于订单限价。"));
        }
        if let Some(holding) = self.holdings.get(&order.customer).and_then(|goods| goods.get(&order.good)) {
            holding.check_purchase(order.quantity_milli)?;
        }
        let record = format!("personal_life:{id}");
        let hold = format!("counter:{id}");
        let (goods_cost, ()) = self.macro_economy.sell_existing_stock(&unit, &market_id, &order.good, order.quantity_milli, price,
            |amount| self.ledger.settle_counter_purchase(&order.customer, &market_id, &firm, &hold, &record, amount, order.service_fee, minute))?;
        self.holdings.entry(order.customer.clone()).or_default().entry(order.good.clone()).or_default()
            .record_purchase(record, order.quantity_milli);
        Ok(goods_cost)
    }

    pub(crate) fn settle_counter_orders(&mut self, boundary: GameClock) -> io::Result<()> {
        let day = boundary.current_day();
        let minute = boundary.snapshot().total_minutes;
        let mut hours = BTreeMap::new();
        for (id, order) in std::mem::take(&mut self.counters.orders) {
            let shifts = hours.entry(order.shop.clone()).or_insert_with(|| {
                let firm = self.organization(&order.shop).and_then(|org| org.firm.as_deref()).expect("registered merchant");
                let mut shifts: Vec<_> = self.wages.completed_firm_work(firm, day).into_iter().filter_map(|work| {
                    let start = self.work.booking(work.worker)?;
                    Some((start, start + work.hours * 60))
                }).collect();
                shifts.sort_by_key(|&(_, end)| end);
                shifts
            });
            let available = shifts.iter_mut().find(|(start, end)| order.placed.max(*start) + 60 <= *end);
            if available.is_none() && day <= order.placed / MINUTES_PER_DAY + 1 {
                self.counters.orders.insert(id, order);
                continue;
            }
            let result = if let Some((start, _)) = available {
                *start = order.placed.max(*start) + 60;
                self.hand_over(id, &order, minute)
            } else { Err(invalid("两日内缺少交付工时。")) };
            let settlement = match result {
                Ok(goods_paid) => CounterSettlement::Delivered { goods_paid },
                Err(err) => {
                    self.ledger.release(&format!("counter:{id}"), order.maximum_goods + order.service_fee)?;
                    CounterSettlement::Released { reason: err.to_string() }
                }
            };
            self.counters.recent.entry(order.shop).or_default().insert(order.customer, Outcome {
                order_id: id, placed: order.placed, minute, good: order.good,
                maximum_goods: order.maximum_goods, service_fee: order.service_fee, settlement,
            });
        }
        Ok(())
    }

    pub(crate) fn plan_household_orders(&mut self) -> io::Result<()> {
        let day = self.clock.current_day();
        let minute = self.clock.snapshot().total_minutes;
        let mut local = BTreeMap::new();
        for shop in self.organizations().filter(|org| org.is_merchant()) {
            let (_, goods) = local.entry(shop.place.clone())
                .or_insert_with(|| (shop.unit.clone(), BTreeMap::<String, Vec<String>>::new()));
            for good in &shop.goods {
                goods.entry(good.clone()).or_default().push(shop.id.clone());
            }
        }
        let customers = self.named_people().filter(|&id| id != self.player).map(str::to_owned).collect::<Vec<_>>();
        for person in customers {
            let Some((unit, goods)) = self.current_place(&person).and_then(|p| local.get(p)) else { continue };
            let needs = self.person_livelihood(&person).expect("named resident");
            let available = needs.budget.map_or(0, |account| account.available);
            let meal = (self.activities.meal_milli_for_recovery - needs.food_held_milli - needs.food_received_today_milli).max(0);
            // A delivery can take two days. Preserve the budget for the next immediate meal.
            let meal_budget = if meal == 0 { Some(0) } else {
                crate::formal_livelihood::STAPLES.iter().filter_map(|good| self.macro_economy.quote(unit, good, meal).ok()).min()
            };
            let mut choices = Vec::new();
            for (good, shops) in goods {
                let food = counts_as_food(good);
                let due = if food { meal } else {
                    let rate = self.macro_economy.resident_daily_milli(unit, good);
                    let increment = if day == 0 { 0 } else {
                        ((day as f64 * rate).floor() - ((day - 1) as f64 * rate).floor()) as i64
                    };
                    let due = self.livelihood.retail_shortfall(&person, good).saturating_add(increment);
                    let used = self.person_holding_milli(&person, good).min(due);
                    if used > 0 {
                        self.holdings.get_mut(&person).unwrap().get_mut(good).unwrap().consume(used)?;
                    }
                    self.livelihood.set_retail_shortfall(&person, good, due - used);
                    due - used
                };
                if due <= 0 || meal_budget.is_none() { continue; }
                let can_shop_direct = self.holdings.get(&person).is_some_and(|stock| stock.contains_key(good))
                    && self.work.booking(&person).is_none();
                if can_shop_direct {
                    // The livelihood settlement already buys and consumes familiar staples.
                    if !food {
                        if let Ok(price) = self.macro_economy.quote(unit, good, 1) {
                            choices.push((!food, price, good.as_str(), None));
                        }
                    }
                } else {
                    for shop in shops {
                        if let Some(offer) = self.counter_quote(shop, &person, good) {
                            choices.push((!food, offer.goods_centimes + offer.service_centimes, good, Some(shop)));
                        }
                    }
                }
            }
            if self.counters.orders.values().any(|o| o.customer == person) { continue; }
            choices.sort_unstable();
            if let Some((_, price, good, shop)) = choices.into_iter()
                .find(|(_, price, _, _)| meal_budget.is_some_and(|meal| *price <= available - meal)) {
                if let Some(shop) = shop {
                    self.place_counter_order(shop, &person, good, price)?;
                } else {
                    let market = &self.macro_economy.markets()[unit];
                    let unit_price = market.commodities[good].price_centimes;
                    let market = market.id.clone();
                    self.buy_livelihood_stock(&person, &market, good, 1, unit_price, minute, false)?;
                    self.holdings.get_mut(&person).unwrap().get_mut(good).unwrap().consume(1)?;
                    let remaining = self.livelihood.retail_shortfall(&person, good) - 1;
                    self.livelihood.set_retail_shortfall(&person, good, remaining);
                }
            }
        }
        Ok(())
    }

    pub(crate) fn validate_counters(&self) -> io::Result<()> {
        let mut holds: BTreeMap<_, _> = self.ledger.counter_holds().map(|(id, payer, amount)| (id, (payer, amount))).collect();
        let mut customers = BTreeSet::new();
        let minute = self.clock.snapshot().total_minutes;
        for (&id, order) in &self.counters.orders {
            let org = self.organization(&order.shop).filter(|org| org.is_merchant() && org.goods.contains(&order.good))
                .ok_or_else(|| invalid("柜台订单缺少商号或经营商品。"))?;
            let account = self.ledger.default_account(&order.customer).ok_or_else(|| invalid("柜台订单缺少付款账户。"))?;
            let job = self.work_opening.entry_job(&org.jobs[0]).ok_or_else(|| invalid("柜台岗位不存在。"))?;
            let amount = order.maximum_goods.checked_add(order.service_fee).ok_or_else(|| invalid("柜台订单金额超限。"))?;
            if id == 0 || id >= self.next_living_record || self.person(&order.customer).is_none() || !customers.insert(&order.customer)
                || order.maximum_goods <= 0 || order.quantity_milli != 1 || order.service_fee != job.wage_per_hour
                || !(0..=minute).contains(&order.placed) || self.clock.current_day() - order.placed / MINUTES_PER_DAY > 1
                || self.ledger.has_purchase(&order.customer, &format!("personal_life:{id}"))
                || holds.remove(format!("counter:{id}").as_str()) != Some((account.account_id, amount)) {
                return Err(invalid("柜台订单与客户准备金或授权不符。"));
            }
        }
        if !holds.is_empty() || self.counters.closed.iter().any(|id| !self.organization(id).is_some_and(|org| org.is_merchant())) {
            return Err(invalid("柜台接单状态、结果与账本不符。"));
        }
        let mut settled_ids = BTreeSet::new();
        for (shop, outcomes) in &self.counters.recent {
            let org = self.organization(shop).filter(|org| org.is_merchant() && !outcomes.is_empty())
                .ok_or_else(|| invalid("柜台结果缺少经营主体或客户。"))?;
            let terms = self.work_opening.entry_job(&org.jobs[0]).ok_or_else(|| invalid("柜台结果缺少服务岗位。"))?;
            let merchant = self.ledger.default_account(&terms.employer).ok_or_else(|| invalid("柜台结果缺少商号账户。"))?;
            let market = self.macro_economy.markets().get(&org.unit).ok_or_else(|| invalid("柜台结果缺少市场。"))?;
            for (customer, result) in outcomes {
                let id = result.order_id;
                let held = result.maximum_goods.checked_add(result.service_fee);
                if id == 0 || id >= self.next_living_record || self.counters.orders.contains_key(&id) || !settled_ids.insert(id)
                    || !org.goods.contains(&result.good) || self.person(customer).is_none()
                    || !(0..=minute).contains(&result.minute) || result.minute % MINUTES_PER_DAY != 0
                    || !(0..result.minute).contains(&result.placed)
                    || !(1..=2).contains(&(result.minute / MINUTES_PER_DAY - result.placed / MINUTES_PER_DAY))
                    || result.maximum_goods <= 0 || result.service_fee != terms.wage_per_hour
                    || !held.is_some_and(|n| n <= crate::formal_ledger::MAX_AMOUNT) {
                    return Err(invalid("已结柜台订单的编号、条款或日期不符。"));
                }
                let hold = format!("counter:{id}");
                let record = format!("personal_life:{id}");
                let purchase = format!("purchase:{record}");
                let service = format!("service:{hold}");
                let goods_minute = self.ledger.payment_minute(&purchase);
                let fee_minute = self.ledger.payment_minute(&service);
                match &result.settlement {
                    CounterSettlement::Delivered { goods_paid } => {
                        let payer = self.ledger.default_account(customer).ok_or_else(|| invalid("交货记录缺少客户账户。"))?;
                        let seller = self.ledger.default_account(&market.id).ok_or_else(|| invalid("交货记录缺少市场实收账户。"))?;
                        if !(1..=result.maximum_goods).contains(goods_paid) || goods_minute != Some(result.minute)
                            || fee_minute != Some(result.minute)
                            || !self.ledger.has_payment(&purchase, payer.account_id, seller.account_id, *goods_paid, "purchase", &record)
                            || !self.ledger.has_payment(&service, payer.account_id, merchant.account_id, result.service_fee, "service_fee", &hold)
                            || self.wages.completed_firm_work(&terms.employer, result.minute / MINUTES_PER_DAY).is_empty() {
                            return Err(invalid("柜台交货与已完成班次、货款或代办费收据不符。"));
                        }
                    }
                    CounterSettlement::Released { reason } => {
                        if goods_minute.is_some() || fee_minute.is_some() || reason.trim().is_empty() || reason.len() > 512 {
                            return Err(invalid("未交货订单存在扣款或缺少失败原因。"));
                        }
                    }
                }
            }
        }
        Ok(())
    }
}
