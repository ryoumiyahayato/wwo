//! Player-owned merchandise stays in one lot from market purchase through delivery and sale.
use super::InitialWorld;
use crate::{
    formal_character,
    formal_ledger::{MAX_AMOUNT, TRANSPORT_ACCOUNT},
    formal_save::invalid,
    transport::{operations::{Plan, Traffic}, ModeSet},
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
};

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct FreightBook {
    lots: BTreeMap<u64, FreightLot>,
    #[serde(skip)]
    moving: BTreeMap<u64, u64>, // reservation -> lot; rebuilt on restore
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FreightLot {
    pub id: u64,
    pub good: String,
    pub quantity_milli: i64,
    pub origin: String,
    pub purchase_centimes: i64,
    pub freight_centimes: i64,
    pub state: FreightState,
    owner: String,
    purchase_unit_price: i64,
    dispatches: Vec<Dispatch>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Dispatch {
    reservation_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    mass_slots: Option<u32>,
    from: String,
    to: String,
    fare_centimes: i64,
    refund_centimes: i64,
    landed: Option<String>,
}

#[derive(Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub enum FreightState {
    Purchased,
    InTransit {
        reservation_id: u64,
        destination: String,
    },
    Interrupted {
        place: String,
    },
    Delivered {
        destination: String,
    },
    Sold {
        destination: String,
        revenue_centimes: i64,
        net_centimes: i64,
    },
}

impl FreightLot {
    fn dispatch_origin(&self) -> io::Result<&str> {
        match &self.state {
            FreightState::Purchased => Ok(&self.origin),
            FreightState::Interrupted { place } => Ok(place),
            FreightState::Delivered { destination } => Ok(destination),
            _ => Err(invalid("在途或已出售的货批不能发运。")),
        }
    }

    fn delivery(&self) -> io::Result<&str> {
        match &self.state {
            FreightState::Delivered { destination } => Ok(destination),
            _ => Err(invalid("货批尚未交割或已出售。")),
        }
    }

    fn purchase_reference(&self) -> String {
        format!(
            "freight-lot:{}:{}:{}:{}:{}",
            self.id, self.origin, self.good, self.quantity_milli, self.purchase_unit_price
        )
    }
}

impl InitialWorld {
    pub fn freight_lots(&self) -> impl DoubleEndedIterator<Item = &FreightLot> {
        self.freight.lots.values()
    }

    fn owned_lot(&self, id: u64) -> io::Result<&FreightLot> {
        self.freight
            .lots
            .get(&id)
            .filter(|lot| lot.owner == self.player && self.player_alive())
            .ok_or_else(|| invalid("货批不存在或当前人物无权处置。"))
    }

    pub fn buy_freight(
        &mut self,
        good: &str,
        quantity_milli: i64,
        quoted_unit_price: i64,
    ) -> io::Result<u64> {
        if !self.player_alive() || self.passenger_in_transit() {
            return Err(invalid("人物当前无法在场办理购货。"));
        }
        self.macro_economy.freight_mass(good)?.slots_milli(quantity_milli)?;
        let origin = self.last_station().to_owned();
        let unit = self.population_unit_at(&origin)
            .ok_or_else(|| invalid("当前地点没有正式统计市场。"))?.to_owned();
        let market = self
            .macro_economy
            .markets()
            .get(&unit)
            .ok_or_else(|| invalid("当前统计市场不存在。"))?
            .id
            .clone();
        let id = self
            .freight
            .lots
            .last_key_value()
            .map_or(0, |(&key, _)| key)
            .checked_add(1)
            .ok_or_else(|| invalid("货批编号耗尽。"))?;
        let mut lot = FreightLot {
            id,
            origin,
            owner: self.player.clone(),
            good: good.into(),
            quantity_milli,
            purchase_unit_price: quoted_unit_price,
            purchase_centimes: 0,
            freight_centimes: 0,
            state: FreightState::Purchased,
            dispatches: Vec::new(),
        };
        let reference = lot.purchase_reference();
        let available = self
            .balance()
            .ok_or_else(|| invalid("缺少货主现金账户。"))?
            .available;
        let day =
            u32::try_from(self.clock.current_day()).map_err(|_| invalid("正式日期超出范围。"))?;
        let minute = self.clock.snapshot().total_minutes;
        let (paid, character) = self.macro_economy.sell_existing_stock(
            &unit,
            &market,
            good,
            quantity_milli,
            quoted_unit_price,
            |amount| {
                let character = formal_character::assess_purchase(
                    &self.player,
                    &self.identities,
                    day,
                    &self.character.state,
                    &market,
                    amount as u64,
                    available as u64,
                )
                .map_err(io::Error::other)?;
                self.ledger
                    .buy_from_market(&self.player, &market, &reference, amount, minute)?;
                Ok(character)
            },
        )?;
        self.character = character;
        lot.purchase_centimes = paid;
        self.freight.lots.insert(id, lot);
        Ok(id)
    }

    fn freight_departure(&self, id: u64) -> io::Result<(&str, u32)> {
        let lot = self.owned_lot(id)?;
        let from = lot.dispatch_origin()?;
        if matches!(lot.state, FreightState::Purchased)
            && (self.passenger_in_transit() || self.last_station() != from)
        {
            return Err(invalid("首次发运须在购货地交货。"));
        }
        Ok((from, self.macro_economy.freight_mass(&lot.good)?.slots_milli(lot.quantity_milli)?))
    }

    pub fn quote_freight(&mut self, id: u64, to: &str, modes: ModeSet) -> io::Result<Plan> {
        let (from, units) = self.freight_departure(id)?;
        if from == to {
            return Err(invalid("货运目的地须不同于出发地。"));
        }
        let from = from.to_owned();
        self.transport
            .quote_service(&from, to, modes, units, self.clock.snapshot().total_minutes, Traffic::PlayerFreight)
    }

    pub fn dispatch_freight(&mut self, id: u64, to: &str, modes: ModeSet) -> io::Result<u64> {
        let plan = self.quote_freight(id, to, modes)?;
        self.dispatch_quoted_freight(id, plan)
    }

    pub fn dispatch_quoted_freight(&mut self, id: u64, plan: Plan) -> io::Result<u64> {
        let (location, units) = self.freight_departure(id)?;
        if location != plan.route().from || units != plan.load_units() {
            return Err(invalid("运输报价与本批货物的所在地或载荷不符。"));
        }
        let from = plan.route().from.clone();
        let to = plan.route().to.clone();
        let fare = plan.fare_centimes();
        let total = self.freight.lots[&id]
            .freight_centimes
            .checked_add(fare)
            .filter(|n| *n <= MAX_AMOUNT)
            .ok_or_else(|| invalid("累计托运费超出正式范围。"))?;
        let reservation_id = self.transport.reserve_freight(plan)?;
        if let Err(error) = self.pay_transport(fare, reservation_id) {
            self.transport.finish(reservation_id);
            return Err(error);
        }
        let lot = self.freight.lots.get_mut(&id).expect("quoted owned lot");
        lot.dispatches.push(Dispatch {
            reservation_id,
            mass_slots: Some(units),
            from,
            to: to.clone(),
            fare_centimes: fare,
            refund_centimes: 0,
            landed: None,
        });
        lot.freight_centimes = total;
        lot.state = FreightState::InTransit {
            reservation_id,
            destination: to,
        };
        self.freight.moving.insert(reservation_id, id);
        Ok(reservation_id)
    }

    pub(crate) fn settle_freight(&mut self) -> io::Result<()> {
        let stopped: Vec<_> = self
            .freight
            .moving
            .iter()
            .filter_map(|(&reservation, &lot)| {
                self.transport
                    .completed(reservation)
                    .map(|place| (reservation, lot, place.to_owned(), None))
                    .or_else(|| {
                        self.transport.held(reservation).map(|place| {
                            (
                                reservation,
                                lot,
                                place.to_owned(),
                                self.transport.unused_fare(reservation),
                            )
                        })
                    })
            })
            .collect();
        for (reservation_id, id, place, refund) in stopped {
            let next = if let Some(amount) = refund {
                if amount > 0 {
                    self.refund_transport(amount, reservation_id)?;
                }
                FreightState::Interrupted {
                    place: place.clone(),
                }
            } else {
                FreightState::Delivered {
                    destination: place.clone(),
                }
            };
            let lot = self.freight.lots.get_mut(&id).expect("indexed freight lot");
            let leg = lot.dispatches.last_mut().expect("dispatched freight lot");
            leg.refund_centimes = refund.unwrap_or(0);
            leg.landed = Some(place);
            lot.freight_centimes -= leg.refund_centimes;
            lot.state = next;
            self.freight.moving.remove(&reservation_id);
            self.transport.finish(reservation_id);
        }
        Ok(())
    }

    /// A market can draw on its finite reserve for goods it needs to restock.
    pub fn freight_sale_quote(&self, id: u64) -> io::Result<(i64, i64)> {
        let lot = self.owned_lot(id)?;
        let unit = self.population_unit_at(lot.delivery()?)
            .ok_or_else(|| invalid("交割地没有统计市场。"))?;
        let bid = self
            .macro_economy
            .freight_bid(unit, &lot.good, lot.quantity_milli)?;
        if self.macro_economy.bid_budget(unit, &lot.good, &self.ledger) < bid.1 {
            return Err(invalid("交割市场的实收资金和可用补货预算不足。"));
        }
        Ok(bid)
    }

    pub fn sell_freight(&mut self, id: u64, quoted_unit_price: i64) -> io::Result<i64> {
        self.freight_sale_quote(id)?;
        let lot = &self.freight.lots[&id];
        let destination = lot.delivery()?.to_owned();
        let unit = self.population_unit_at(&destination)
            .expect("quoted destination market").to_owned();
        let reference = format!("freight-lot:{id}:{destination}");
        let revenue = self.macro_economy.receive_player_freight(
            &unit,
            &lot.good,
            lot.quantity_milli,
            quoted_unit_price,
            &mut self.ledger, &self.player, &reference, self.clock.snapshot().total_minutes,
        )?;
        let net = revenue - lot.purchase_centimes - lot.freight_centimes;
        self.freight.lots.get_mut(&id).unwrap().state = FreightState::Sold {
            destination,
            revenue_centimes: revenue,
            net_centimes: net,
        };
        Ok(net)
    }

    pub(crate) fn freight_reservation_ids(&self) -> impl Iterator<Item = u64> + '_ {
        self.freight.moving.keys().copied()
    }

    pub(crate) fn validate_freight(&mut self) -> io::Result<()> {
        let mut used = BTreeSet::new();
        let mut moving = BTreeMap::new();
        let mut sales = 0;
        let account = self
            .balance()
            .ok_or_else(|| invalid("货主账户缺失。"))?
            .account_id;
        for (index, (&id, lot)) in self.freight.lots.iter().enumerate() {
            let mass = self.macro_economy.freight_mass(&lot.good)?;
            if !(1..=MAX_AMOUNT).contains(&lot.quantity_milli) { return Err(invalid("invalid saved freight quantity")); }
            let unit = self.population_unit_at(&lot.origin)
                .ok_or_else(|| invalid("存档购货地不存在。"))?;
            let market = self
                .macro_economy
                .markets()
                .get(unit)
                .ok_or_else(|| invalid("存档供货市场不存在。"))?;
            let reference = lot.purchase_reference();
            let purchase_value =
                i128::from(lot.quantity_milli) * i128::from(lot.purchase_unit_price);
            if id != index as u64 + 1
                || lot.id != id
                || lot.owner != self.player
                || !self.macro_economy.purchasable(&lot.good)
                || lot.purchase_unit_price <= 0
                || !(1..=MAX_AMOUNT).contains(&lot.purchase_centimes)
                || i128::from(lot.purchase_centimes) != (purchase_value + 999) / 1000
                || !self.ledger.has_payment(
                    &format!("purchase:{reference}"),
                    account,
                    &format!("account:market_receipts:{}", market.id),
                    lot.purchase_centimes,
                    "purchase",
                    &reference,
                )
            {
                return Err(invalid("货批与正式购货凭证不符。"));
            }
            let mut place = Some(lot.origin.as_str());
            let mut total = 0_i64;
            for dispatch in &lot.dispatches {
                let reservation = dispatch.reservation_id;
                let payment_ref = format!("transport:{reservation}");
                if dispatch.mass_slots.is_some_and(|slots| mass.slots_milli(lot.quantity_milli).ok() != Some(slots))
                    || reservation == 0
                    || !used.insert(reservation)
                    || place != Some(dispatch.from.as_str())
                    || dispatch.from == dispatch.to
                    || !self.transport.contains_node(&dispatch.to)
                    || dispatch
                        .landed
                        .as_ref()
                        .is_some_and(|p| !self.transport.contains_node(p))
                    || !(1..=MAX_AMOUNT).contains(&dispatch.fare_centimes)
                    || !(0..=dispatch.fare_centimes).contains(&dispatch.refund_centimes)
                    || !self.ledger.has_payment(
                        &format!("transport:fare:{reservation}"),
                        account,
                        TRANSPORT_ACCOUNT,
                        dispatch.fare_centimes,
                        "transport_fare",
                        &payment_ref,
                    )
                    || dispatch.refund_centimes > 0
                        && !self.ledger.has_payment(
                            &format!("transport:refund:{reservation}"),
                            TRANSPORT_ACCOUNT,
                            account,
                            dispatch.refund_centimes,
                            "transport_refund",
                            &payment_ref,
                        )
                    || dispatch.landed.is_none() && dispatch.refund_centimes != 0
                    || dispatch.landed.as_deref() == Some(dispatch.to.as_str())
                        && dispatch.refund_centimes != 0
                {
                    return Err(invalid("货批行程或运费凭证不符。"));
                }
                total = total
                    .checked_add(dispatch.fare_centimes - dispatch.refund_centimes)
                    .filter(|n| *n <= MAX_AMOUNT)
                    .ok_or_else(|| invalid("货批累计费用超限。"))?;
                place = dispatch.landed.as_deref();
            }
            let last = lot.dispatches.last();
            let valid = match &lot.state {
                FreightState::Purchased => last.is_none(),
                FreightState::InTransit {
                    reservation_id,
                    destination,
                } => {
                    let plan = self.transport.plan(*reservation_id);
                    moving.insert(*reservation_id, id);
                    place.is_none()
                        && self.transport.traffic(*reservation_id) == Some(Traffic::PlayerFreight)
                        && last.zip(plan).is_some_and(|(dispatch, plan)| {
                            *reservation_id == dispatch.reservation_id
                                && destination == &dispatch.to
                                && plan.route().from == dispatch.from
                                && plan.route().to == *destination
                                && plan.fare_centimes() == dispatch.fare_centimes
                                && i64::from(plan.load_units()) == dispatch.mass_slots.map_or((lot.quantity_milli + 999) / 1000, i64::from)
                        })
                }
                FreightState::Interrupted { place: held } => {
                    place == Some(held.as_str()) && last.is_some_and(|d| d.to != *held)
                }
                FreightState::Delivered { destination } => {
                    place == Some(destination.as_str())
                        && last.is_some_and(|d| d.to == *destination)
                }
                FreightState::Sold {
                    destination,
                    revenue_centimes,
                    net_centimes,
                } => {
                    sales += 1;
                    let buyer = self.population_unit_at(destination)
                        .and_then(|unit| self.macro_economy.markets().get(unit));
                    let sale_ref = format!("freight-lot:{id}:{destination}");
                    place == Some(destination.as_str())
                        && last.is_some_and(|d| d.to == *destination)
                        && (1..=MAX_AMOUNT).contains(revenue_centimes)
                        && *net_centimes == *revenue_centimes - lot.purchase_centimes - total
                        && buyer.is_some_and(|market| {
                            self.ledger.has_payment(
                                &format!("sale:{sale_ref}"),
                                &format!("account:market_receipts:{}", market.id),
                                account,
                                *revenue_centimes,
                                "freight_sale",
                                &sale_ref,
                            )
                        })
                }
            };
            if !valid || lot.freight_centimes != total {
                return Err(invalid("货批库存、状态或结算金额不符。"));
            }
        }
        if self.ledger.freight_transaction_counts() != (self.freight.lots.len(), sales) {
            return Err(invalid("账载购销笔数与货批数量不符。"));
        }
        self.freight.moving = moving;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{formal_bootstrap::WorldBootstrap, transport::TransportMode};

    const GOOD: &str = "potatoes";
    const FRANCE: &str = "country_fra";

    fn restore(bootstrap: &WorldBootstrap, world: &InitialWorld) -> InitialWorld {
        bootstrap
            .restore_native(serde_json::from_value(world.snapshot()).unwrap())
            .unwrap()
    }

    #[test]
    fn transport_freight_prices_light_and_heavy_cargo_by_mass_and_honors_a_signed_old_fare() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create(FRANCE).unwrap();
        let rail = ModeSet::only(TransportMode::Rail);
        let from = "place:paris";
        let to = "place:rouen";
        let quote = |world: &mut InitialWorld, good| {
            let price = world.macro_economy.markets()[FRANCE].commodities[good].price_centimes;
            let lot = world.buy_freight(good, 200, price).unwrap();
            (lot, world.quote_freight(lot, to, rail).unwrap())
        };
        let (_, light) = quote(&mut world, "silk_goods");
        let (heavy, plan) = quote(&mut world, "railway_equipment");
        assert_eq!((light.load_units(), plan.load_units()), (1, 4));
        assert_eq!(light.fare_centimes() * 4, plan.fare_centimes());
        let mass = world.macro_economy.freight_mass("railway_equipment").unwrap();
        assert_eq!(mass.slots(0.2).unwrap(), plan.load_units());
        assert_eq!(mass.slots_milli(200).unwrap(), plan.load_units());

        let old = world.transport.quote_service(from, to, rail, 1, 0, Traffic::PlayerFreight).unwrap();
        let fare = old.fare_centimes();
        let arrival = old.arrival_minute();
        let reservation = world.transport.reserve_freight(old).unwrap();
        world.pay_transport(fare, reservation).unwrap();
        let lot = world.freight.lots.get_mut(&heavy).unwrap();
        lot.dispatches.push(Dispatch { reservation_id: reservation, from: from.into(), to: to.into(),
            fare_centimes: fare, refund_centimes: 0, landed: None, mass_slots: None });
        lot.freight_centimes = fare;
        lot.state = FreightState::InTransit { reservation_id: reservation, destination: to.into() };
        let mut world = restore(&bootstrap, &world);
        assert_eq!(world.transport.plan(reservation).unwrap().load_units(), 1);
        world.advance_migrated_domains(arrival, &BTreeMap::new()).unwrap();
        assert_eq!(world.freight.lots[&heavy].delivery().unwrap(), to);
        assert_eq!(world.quote_freight(heavy, from, rail).unwrap().load_units(), 4);
    }

    #[test]
    fn transport_freight_purchase_delivery_and_sale_conserve_cash_and_goods_after_restore() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create(FRANCE).unwrap();
        let before = world.macro_economy.markets()[FRANCE].commodities[GOOD];
        let cash = world.balance().unwrap().cash;
        let id = world
            .buy_freight(GOOD, 1000, before.price_centimes)
            .unwrap();
        assert_eq!(
            world.macro_economy.markets()[FRANCE].commodities[GOOD].inventory,
            before.inventory - 1.0
        );
        assert_eq!(world.holding_milli(GOOD), 0);
        assert!(world.consume_purchased_stock(GOOD, 1000).is_err());
        let plan = world
            .quote_freight(id, "place:rouen", ModeSet::ALL)
            .unwrap();
        let fare = plan.fare_centimes();
        world
            .dispatch_freight(id, "place:rouen", ModeSet::ALL)
            .unwrap();
        assert!(world.sell_freight(id, before.price_centimes).is_err());
        assert!(world
            .dispatch_freight(id, "place:rouen", ModeSet::ALL)
            .is_err());
        let mut world = restore(&bootstrap, &world);
        world
            .advance_migrated_domains(plan.arrival_minute(), &BTreeMap::new())
            .unwrap();
        assert_eq!(world.player_current_place(), Some("place:paris"));
        assert_eq!(
            world.freight_sale_quote(id).unwrap(),
            (before.price_centimes, before.price_centimes)
        );
        assert!(world.sell_freight(id, before.price_centimes + 1).is_err());
        assert_eq!(
            world.sell_freight(id, before.price_centimes).unwrap(),
            -fare
        );
        let mut world = restore(&bootstrap, &world);
        assert!(world.sell_freight(id, before.price_centimes).is_err());
        assert_eq!(world.balance().unwrap().cash, cash - fare);
        assert_eq!(
            world.macro_economy.markets()[FRANCE].commodities[GOOD].inventory,
            before.inventory
        );
        assert_eq!(
            world
                .ledger
                .default_account("service:formal_transport")
                .unwrap()
                .cash,
            fare
        );
    }

    #[test]
    fn transport_freight_interruption_returns_untraveled_fare_and_one_lot_resumes_at_the_stop() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create(FRANCE).unwrap();
        let price = world.macro_economy.markets()[FRANCE].commodities[GOOD].price_centimes;
        let id = world.buy_freight(GOOD, 1000, price).unwrap();
        let rail = ModeSet::only(TransportMode::Rail);
        let plan = world.quote_freight(id, "place:le_havre", rail).unwrap();
        let first = plan.route().legs[0].profile;
        world.dispatch_freight(id, "place:le_havre", rail).unwrap();
        world
            .transport
            .set_closed("rail_rouen_le_havre", true)
            .unwrap();
        world
            .advance_migrated_domains(i64::from(first.travel_minutes), &BTreeMap::new())
            .unwrap();
        let mut world = restore(&bootstrap, &world);
        let lot = &world.freight.lots[&id];
        assert_eq!(
            lot.state,
            FreightState::Interrupted {
                place: "place:rouen".into()
            }
        );
        assert_eq!(lot.freight_centimes, i64::from(first.cost_units));
        assert!(world.quote_freight(id, "place:le_havre", rail).is_err());
        world
            .transport
            .set_closed("rail_rouen_le_havre", false)
            .unwrap();
        let onward = world.quote_freight(id, "place:le_havre", rail).unwrap();
        assert_eq!(onward.route().from, "place:rouen");
        world.dispatch_freight(id, "place:le_havre", rail).unwrap();
        world
            .advance_migrated_domains(
                onward.arrival_minute() - world.clock.snapshot().total_minutes,
                &BTreeMap::new(),
            )
            .unwrap();
        let world = restore(&bootstrap, &world);
        assert_eq!(world.freight_lots().count(), 1);
        assert_eq!(
            world.freight.lots[&id].state,
            FreightState::Delivered {
                destination: "place:le_havre".into()
            }
        );
        assert_eq!(
            world.freight.lots[&id].freight_centimes,
            plan.fare_centimes()
        );
    }

    #[test]
    fn transport_freight_japanese_tea_clears_at_the_qing_market_bid() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("empire_of_japan").unwrap();
        let managed = BTreeMap::new();
        world.advance_migrated_domains(2 * crate::formal_clock::MINUTES_PER_DAY, &managed).unwrap();
        let good = "tea";
        let source = "empire_of_japan";
        let destination = "qing_empire";
        let seller = world.macro_economy.markets()[source].id.clone();
        let buyer = world.macro_economy.markets()[destination].id.clone();
        let from_stock = world.macro_economy.markets()[source].commodities[good];
        let seller_cash = world.ledger.market_cash(&seller);
        let player_cash = world.balance().unwrap().cash;
        let lot = world.buy_freight(good, 1000, from_stock.price_centimes).unwrap();
        assert_eq!(world.macro_economy.markets()[source].commodities[good].inventory, from_stock.inventory - 1.0);
        assert_eq!(world.ledger.market_cash(&seller), seller_cash + from_stock.price_centimes);
        let plan = world.quote_freight(lot, "area:qing_empire", ModeSet::ALL).unwrap();
        let arrival = plan.arrival_minute();
        let fee = plan.fare_centimes();
        assert!(plan.route().legs.iter().any(|leg| leg.mode == TransportMode::Shipping));
        world.dispatch_quoted_freight(lot, plan).unwrap();
        assert_eq!(world.balance().unwrap().cash, player_cash - from_stock.price_centimes - fee);
        let mut world = restore(&bootstrap, &world);
        world.advance_migrated_domains(arrival - world.clock.snapshot().total_minutes, &managed).unwrap();
        let stock_at_delivery = world.macro_economy.markets()[destination].commodities[good].inventory;
        let reserve = world.macro_economy.markets()[destination].gold_reserve_units;
        let local_cash = world.ledger.market_cash(&buyer);
        let cash_at_delivery = world.balance().unwrap().cash;
        let (price, amount) = world.freight_sale_quote(lot).unwrap();
        let net = world.sell_freight(lot, price).unwrap();
        assert_eq!(world.balance().unwrap().cash, cash_at_delivery + amount);
        assert_eq!(world.macro_economy.markets()[destination].commodities[good].inventory, stock_at_delivery + 1.0);
        let redeemed = reserve - world.macro_economy.markets()[destination].gold_reserve_units;
        assert_eq!(redeemed, (amount - local_cash).max(0) as f64);
        assert_eq!(world.ledger.market_cash(&buyer), local_cash + redeemed as i64 - amount);
        assert_eq!(net, amount - from_stock.price_centimes - fee);
        let mut world = restore(&bootstrap, &world);
        assert!(world.sell_freight(lot, price).is_err());
        println!("Japanese tea: source {:.3} -> {:.3}; Qing {:.3} -> {:.3}; buy {}, sale {amount}, freight {fee}, net {net}, reserve redeemed {redeemed}",
            from_stock.inventory, from_stock.inventory - 1.0, stock_at_delivery, stock_at_delivery + 1.0, from_stock.price_centimes);
    }

    #[test]
    fn transport_freight_unfunded_destination_preserves_ownership_and_can_forward_the_lot() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create(FRANCE).unwrap();
        let price = world.macro_economy.markets()[FRANCE].commodities[GOOD].price_centimes;
        let id = world.buy_freight(GOOD, 1000, price).unwrap();
        let plan = world
            .quote_freight(id, "place:london", ModeSet::ALL)
            .unwrap();
        let arrival = plan.arrival_minute();
        world.dispatch_quoted_freight(id, plan).unwrap();
        world
            .advance_migrated_domains(arrival, &BTreeMap::new())
            .unwrap();
        let cash = world.balance().unwrap().cash;
        assert!(world.freight_sale_quote(id).is_err());
        assert!(world.sell_freight(id, price).is_err());
        assert_eq!(world.balance().unwrap().cash, cash);
        assert_eq!(
            world.freight.lots[&id].state,
            FreightState::Delivered {
                destination: "place:london".into()
            }
        );
        let onward = world
            .quote_freight(id, "place:le_havre", ModeSet::ALL)
            .unwrap();
        assert_eq!(onward.route().from, "place:london");
    }
}
