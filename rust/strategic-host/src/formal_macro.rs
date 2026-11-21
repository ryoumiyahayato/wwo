use crate::{
    formal_bootstrap::{columns, local_id},
    formal_clock::{GameClock, MINUTES_PER_DAY, MINUTES_PER_HOUR},
    formal_ledger::{Ledger, PaymentLeg, TRANSPORT_ACCOUNT, MAX_AMOUNT},
    transport::{operations::{Operations, Traffic}, ModeSet},
    formal_save::{field, lookup, integer, invalid, map, number, tagged, typed_int, typed_map},
    legacy_variant::encode_number,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::BTreeMap, io, sync::Arc};

const HOURS_PER_DAY: i64 = MINUTES_PER_DAY / MINUTES_PER_HOUR;
const BASIS_POINTS: i64 = 10_000;
const QUANTITY_EPSILON: f64 = 0.0001;
const MAX_DAILY_SHIPMENTS: usize = 96;
const MAX_SUPPLIERS: usize = 4;
const MAX_SHORTAGES: usize = 10;

pub(crate) struct CountryInputs {
    pub income: u64,
    pub confidence: u64,
    pub agriculture: u64,
    pub industry: u64,
    pub minerals: [u64; 5],
}

#[derive(Deserialize)]
struct Commodity {
    commodity_id: String,
    name_zh: String,
    category: String,
    unit_name_zh: String,
    base_price_centimes: i64,
    base_daily_units_per_million: f64,
    income_elasticity_bp: i64,
    international_liquidity_units: u64,
    target_stock_days: f64,
}

struct TradeRoute {
    id: String,
    origin: String,
    destination: String,
    duration_hours: i64,
}

pub(crate) struct MarketInputs {
    countries: BTreeMap<String, CountryInputs>,
    commodities: Vec<Commodity>,
    routes: Vec<TradeRoute>,
}

pub struct MacroEconomy {
    inputs: Arc<MarketInputs>,
    markets: BTreeMap<String, Market>,
    shipments: Vec<Shipment>,
    last_arrivals: Vec<Shipment>,
    last_settlement_hour: i64,
    next_shipment: u64,
}

pub struct Market {
    pub id: String,
    pub commodities: BTreeMap<String, CommodityState>,
    pub gold_reserve_units: f64,
    pub trade_balance_centimes: i64,
    pub tariff_revenue_centimes: i64,
    daily_totals: Option<DailyTotals>,
}

#[derive(Default)]
struct DailyTotals {
    demanded: f64,
    produced: f64,
    consumed: f64,
    unmet: f64,
    fulfillment_bp: i64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize)]
pub struct CommodityState {
    pub inventory: f64,
    pub price_centimes: i64,
    pub demanded: f64,
    pub produced: f64,
    pub consumed: f64,
    pub unmet: f64,
    pub imports: f64,
    pub exports: f64,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Shipment {
    pub id: String,
    pub origin: String,
    pub destination: String,
    pub commodity: String,
    pub units: f64,
    pub value_centimes: i64,
    pub dispatch_hour: i64,
    pub arrival_hour: i64,
    pub route_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub carriage: Option<TradeCarriage>,
}

#[derive(Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TradeCarriage {
    pub reservation: u64,
    pub from: String,
    pub fare_centimes: i64,
    pub arrival_minute: i64,
    pub held: bool,
}

impl MacroEconomy {
    pub(crate) fn initialize(inputs: Arc<MarketInputs>, population: &BTreeMap<String, u64>) -> Self {
        let mut markets = BTreeMap::new();
        for (unit, country) in &inputs.countries {
            let population = population[unit];
            let commodities = inputs.commodities.iter().map(|commodity| {
                let demand = commodity.daily_demand(population, country.income);
                let factor = country.production_factor(commodity);
                let inventory = (demand * (8.0 + 22.0 * factor)).max(factor * 40.0);
                (commodity.commodity_id.clone(), CommodityState {
                    inventory, price_centimes: commodity.base_price_centimes, ..Default::default()
                })
            }).collect();
            let confidence = (country.confidence as f64 / BASIS_POINTS as f64).max(0.1);
            let gold_reserve_units = (population as f64 * country.income as f64 * confidence / 1_000_000.0).max(1.0);
            markets.insert(unit.clone(), Market {
                id: format!("market:legacy_aggregate:{unit}"),
                commodities,
                gold_reserve_units,
                trade_balance_centimes: 0,
                tariff_revenue_centimes: 0,
                daily_totals: None,
            });
        }
        Self { inputs, markets, shipments: Vec::new(), last_arrivals: Vec::new(), last_settlement_hour: 0, next_shipment: 1 }
    }

    pub fn markets(&self) -> &BTreeMap<String, Market> {
        &self.markets
    }

    pub fn shipments(&self) -> &[Shipment] {
        &self.shipments
    }

    pub fn last_arrivals(&self) -> &[Shipment] {
        &self.last_arrivals
    }

    pub(crate) fn restore_arrivals(&mut self, arrivals: Vec<Shipment>, now: i64) -> io::Result<()> {
        let mut ids = self.shipments.iter().map(|row| &row.id).collect::<std::collections::BTreeSet<_>>();
        for row in &arrivals {
            let sequence = row.id.strip_prefix("formal_shipment:").and_then(|id| id.parse::<u64>().ok());
            let route = self.inputs.routes.iter().find(|route| route.id == row.route_id);
            if !ids.insert(&row.id) || !sequence.is_some_and(|id| (1..self.next_shipment).contains(&id))
                || row.dispatch_hour < 0 || row.dispatch_hour >= row.arrival_hour
                || row.arrival_hour < self.last_settlement_hour - HOURS_PER_DAY + 1
                || row.carriage.as_ref().map_or(row.arrival_hour > self.last_settlement_hour, |c| c.held || c.arrival_minute < 0 || c.arrival_minute > now || c.arrival_minute.checked_add(59).map(|n| n / 60) != Some(row.arrival_hour))
                || !row.units.is_finite() || row.units <= 0.0 || row.value_centimes <= 0
                || row.origin == row.destination || !self.markets.contains_key(&row.origin)
                || !self.markets.get(&row.destination).is_some_and(|market| market.commodities.contains_key(&row.commodity))
                || row.carriage.is_none() && !route.is_some_and(|route| row.dispatch_hour.checked_add(route.duration_hours) == Some(row.arrival_hour)
                    && ((route.origin == row.origin && route.destination == row.destination)
                        || (route.origin == row.destination && route.destination == row.origin)))
            {
                return Err(invalid("invalid completed macro shipment"));
            }
        }
        self.last_arrivals = arrivals;
        Ok(())
    }

    pub fn last_settlement_hour(&self) -> i64 {
        self.last_settlement_hour
    }

    pub fn commodity_info(&self, good: &str) -> Option<(&str, &str, &str)> {
        let info = self.inputs.commodities.iter().find(|item| item.commodity_id == good)?;
        Some((&info.name_zh, &info.category, &info.unit_name_zh))
    }

    pub fn purchasable(&self, good: &str) -> bool {
        self.commodity_info(good).is_some_and(|(_, category, unit)| category != "local_service" && !unit.is_empty())
    }

    pub fn quote(&self, unit: &str, good: &str, quantity_milli: i64) -> io::Result<i64> {
        let state = self.markets.get(unit).and_then(|market| market.commodities.get(good))
            .filter(|_| self.purchasable(good)).ok_or_else(|| invalid("该商品不可购买。"))?;
        state.quote(quantity_milli)
    }

    pub(crate) fn is_consumable(&self, good: &str) -> bool {
        self.inputs.commodities.iter().any(|commodity| {
            commodity.commodity_id == good && matches!(commodity.category.as_str(),
                "agricultural_food" | "processed_food" | "colonial_consumable" | "household_consumable")
        })
    }

    /// Match a purchase against existing stock in the resident's aggregate market.
    /// Prices are whole minor units, quantities are thousandths of a catalogue unit.
    pub(crate) fn sell_existing_stock<T>(
        &mut self,
        resident_unit: &str,
        market_id: &str,
        commodity_id: &str,
        quantity_milli: i64,
        expected_price: i64,
        pay: impl FnOnce(i64) -> io::Result<T>,
    ) -> io::Result<(i64, T)> {
        use crate::formal_ledger::MAX_AMOUNT;
        let market = self.markets.get_mut(resident_unit).filter(|market| market.id == market_id)
            .ok_or_else(|| invalid("person cannot access this statistical market"))?;
        let sale_supported = self.inputs.commodities.iter().any(|commodity| commodity.commodity_id == commodity_id
            && commodity.category != "local_service" && !commodity.unit_name_zh.is_empty());
        if !sale_supported || !(1..=MAX_AMOUNT).contains(&quantity_milli) {
            return Err(invalid("commodity or quantity is not eligible for personal purchase"));
        }
        let state = market.commodities.get_mut(commodity_id)
            .ok_or_else(|| invalid("commodity is absent from the market"))?;
        if expected_price <= 0 || state.price_centimes != expected_price {
            return Err(invalid("purchase quote price has changed"));
        }
        let amount = state.quote(quantity_milli)?;
        let paid = pay(amount)?;
        state.inventory -= quantity_milli as f64 / 1000.0;
        Ok((amount, paid))
    }

    /// A consigned lot enters inventory at the destination's current statistical
    /// price. Round buyer payouts down to a whole minor unit.
    pub(crate) fn freight_bid(&self, unit: &str, good: &str, quantity_milli: i64) -> io::Result<(i64, i64)> {
        let state = self.markets.get(unit).and_then(|market| market.commodities.get(good))
            .filter(|_| self.purchasable(good))
            .ok_or_else(|| invalid("目的地没有接收此货物的市场。"))?;
        if quantity_milli <= 0 || state.price_centimes <= 0 {
            return Err(invalid("货量或买价无效。"));
        }
        let value = i128::from(quantity_milli) * i128::from(state.price_centimes) / 1000;
        let amount = i64::try_from(value).ok().filter(|amount| (1..=crate::formal_ledger::MAX_AMOUNT).contains(amount))
            .ok_or_else(|| invalid("货批金额超出可结算范围。"))?;
        Ok((state.price_centimes, amount))
    }

    pub(crate) fn bid_budget(&self, unit: &str, good: &str, ledger: &Ledger) -> i64 {
        let market = &self.markets[unit];
        let state = market.commodities[good];
        let restocking = self.inputs.commodities.iter().find(|c| c.commodity_id == good)
            .is_some_and(|c| state.unmet > 0.0 || state.inventory < state.demanded * c.target_stock_days);
        if restocking { market.trade_budget(ledger) } else { ledger.market_cash(&market.id) }
    }

    pub(crate) fn receive_player_freight(
        &mut self, unit: &str, good: &str, quantity_milli: i64, expected_price: i64,
        ledger: &mut Ledger, seller: &str, reference: &str, now: i64,
    ) -> io::Result<i64> {
        let (price, amount) = self.freight_bid(unit, good, quantity_milli)?;
        if expected_price != price {
            return Err(invalid("目的地收购报价已变动。"));
        }
        let market = self.markets.get_mut(unit).expect("quoted market");
        let state = market.commodities.get(good).expect("quoted commodity");
        let inventory = state.inventory + quantity_milli as f64 / 1000.0;
        if !inventory.is_finite() || inventory <= state.inventory {
            return Err(invalid("目的地无法登记这批库存。"));
        }
        market.fund_order(ledger, amount, reference, now)?;
        ledger.pay_market_bid(&market.id, seller, reference, amount, now)?;
        market.commodities.get_mut(good).unwrap().inventory = inventory;
        Ok(amount)
    }

    pub(crate) fn restore(
        inputs: Arc<MarketInputs>,
        population: &BTreeMap<String, u64>,
        value: &Value,
        clock: GameClock,
    ) -> io::Result<Self> {
        let state = map(value)?;
        let last_day = integer(field(state, "last_day_index")?)?;
        let expected_day = if clock.current_day() == 0 { -1 } else { clock.current_day() };
        if field(state, "schema_id")?.as_str() != Some("formal_world_economy_state_v6")
            || integer(field(state, "total_hour")?)? != clock.current_hour()
            || last_day != expected_day
        {
            return Err(invalid("saved macro economy does not match its formal clock"));
        }
        let mut economy = Self::initialize(inputs, population);
        economy.last_settlement_hour = last_day.max(0) * HOURS_PER_DAY;
        let markets = map(field(state, "market_states")?)?;
        if markets.len() != economy.markets.len() {
            return Err(invalid("saved market roster differs from the formal world"));
        }
        for pair in markets {
            let row = map(&pair[1])?;
            let unit = text(row, "source_economic_aggregate_id")?;
            let market = economy.markets.get_mut(unit)
                .ok_or_else(|| invalid("unknown market in saved macro economy"))?;
            if pair[0].as_str() != Some(market.id.as_str())
                || text(row, "market_id")? != market.id
                || integer(field(row, "last_settlement_hour")?)? != economy.last_settlement_hour
            {
                return Err(invalid("saved market identity or settlement hour mismatch"));
            }
            market.restore(row)?;
        }
        economy.next_shipment = u64::try_from(integer(field(state, "next_shipment_sequence")?)?)
            .ok().filter(|&sequence| sequence > 0).ok_or_else(|| invalid("invalid shipment sequence"))?;
        let mut ids = std::collections::BTreeSet::new();
        for row in tagged(field(state, "shipments")?, "array")? {
            let shipment = Shipment::restore(map(row)?)?;
            let sequence = shipment.id.strip_prefix("formal_shipment:").and_then(|suffix| suffix.parse::<u64>().ok())
                .filter(|&sequence| sequence > 0 && sequence < economy.next_shipment);
            let valid_route = economy.inputs.routes.iter().any(|route| route.id == shipment.route_id &&
                ((route.origin == shipment.origin && route.destination == shipment.destination)
                || (route.destination == shipment.origin && route.origin == shipment.destination)));
            if !sequence.is_some_and(|id| ids.insert(id))
                || shipment.dispatch_hour < 0 || shipment.dispatch_hour > economy.last_settlement_hour
                || (shipment.carriage.is_none() && shipment.arrival_hour <= economy.last_settlement_hour) || shipment.arrival_hour <= shipment.dispatch_hour
                || shipment.units <= 0.0 || shipment.value_centimes <= 0
                || shipment.origin == shipment.destination || !economy.markets.contains_key(&shipment.origin)
                || shipment.carriage.is_none() && !valid_route
                || !economy.markets.get(&shipment.destination).is_some_and(|m| m.commodities.contains_key(&shipment.commodity))
            {
                return Err(invalid("invalid saved macro shipment"));
            }
            economy.shipments.push(shipment);
        }
        Ok(economy)
    }

    /// Values owned by the daily market simulation, in the original save schema.
    /// The composition root supplies the evidence references and seller accounts.
    pub fn persistent_fields(&self, clock: GameClock) -> [(&'static str, Value); 6] {
        let markets = self.markets.iter().map(|(unit, market)| {
            (market.id.as_str(), market.snapshot(unit, self.last_settlement_hour))
        });
        let shipments = self.shipments.iter().map(Shipment::snapshot).collect::<Vec<_>>();
        let last_day = if self.last_settlement_hour == 0 { -1 } else { self.last_settlement_hour / HOURS_PER_DAY };
        [
            ("schema_id", json!("formal_world_economy_state_v6")),
            ("total_hour", typed_int(clock.current_hour())),
            ("market_states", typed_map(markets)),
            ("shipments", json!(["array", shipments])),
            ("next_shipment_sequence", typed_int(self.next_shipment as i64)),
            ("last_day_index", typed_int(last_day)),
        ]
    }

    pub(crate) fn check_responsibility(
        &self, population: &BTreeMap<String, u64>, managed_population: &BTreeMap<String, u64>,
    ) -> io::Result<()> {
        if population.len() != self.markets.len() || self.markets.keys().any(|id| !population.contains_key(id))
            || managed_population.iter().any(|(id, managed)| population.get(id).is_none_or(|total| managed > total))
        {
            return Err(invalid("invalid macro population responsibility"));
        }
        Ok(())
    }

    // The simulation owner calls this with the formal clock and current
    // population responsibility at each day boundary.
    pub(crate) fn settle(
        &mut self,
        clock: GameClock,
        population: &BTreeMap<String, u64>,
        managed_population: &BTreeMap<String, u64>,
        transport: &mut Operations,
        ledger: &mut Ledger,
    ) -> io::Result<()> {
        if self.last_settlement_hour.checked_add(HOURS_PER_DAY) != Some(clock.current_hour())
            || clock.snapshot().total_minutes % MINUTES_PER_DAY != 0
        {
            return Err(invalid("macro settlement requires the next daily boundary"));
        }
        self.check_responsibility(population, managed_population)?;
        let hour = clock.current_hour();
        for market in self.markets.values_mut() {
            for state in market.commodities.values_mut() {
                state.imports = 0.0;
            }
        }
        let minute = clock.snapshot().total_minutes;
        self.last_arrivals.retain(|row| row.arrival_hour > hour - HOURS_PER_DAY);
        self.deliver_legacy_shipments(hour);
        self.settle_transport(transport, ledger, minute)?;
        self.retry_held(transport, ledger, minute)?;
        for (unit, market) in &mut self.markets {
            let country = &self.inputs.countries[unit];
            let population = population[unit] - managed_population.get(unit).copied().unwrap_or(0);
            let mut totals = DailyTotals::default();
            for commodity in &self.inputs.commodities {
                let state = market.commodities.get_mut(&commodity.commodity_id).unwrap();
                let demand = commodity.daily_demand(population, country.income);
                let produced = demand * country.production_factor(commodity);
                let consumed = demand.min(state.inventory + produced);
                let unmet = demand - consumed;
                let shortage_bp = if demand > 0.0 { (unmet / demand * 5500.0).round() as i64 } else { 0 };
                let stock = (state.inventory + produced - consumed).max(0.0);
                let target_stock = demand * commodity.target_stock_days;
                let pressure = if target_stock > 0.0 {
                    ((1.0 - stock / target_stock).clamp(-1.0, 1.0) * 3500.0).round() as i64
                } else { 0 };
                let target = (commodity.base_price_centimes * (BASIS_POINTS + shortage_bp + pressure) / BASIS_POINTS).max(1);
                let previous = state.price_centimes.max(1);
                *state = CommodityState {
                    inventory: (state.inventory + produced - consumed).max(0.0),
                    price_centimes: ((previous * 3 + target + 2) / 4)
                        .clamp((previous * 82 / 100).max(1), (previous * 118 / 100).max(1)),
                    demanded: demand, produced, consumed, unmet, imports: state.imports, exports: 0.0,
                };
                totals.demanded += demand;
                totals.produced += produced;
                totals.consumed += consumed;
                totals.unmet += unmet;
            }
            totals.fulfillment_bp = if totals.demanded == 0.0 { BASIS_POINTS }
                else { (totals.consumed / totals.demanded * BASIS_POINTS as f64).round() as i64 };
            market.daily_totals = Some(totals);
        }
        self.dispatch_shortages(hour, transport, ledger)?;
        self.last_settlement_hour = hour;
        Ok(())
    }

    fn deliver_legacy_shipments(&mut self, hour: i64) {
        let arrived: Vec<_> = self.shipments.extract_if(.., |row| row.carriage.is_none() && row.arrival_hour <= hour).collect();
        for shipment in arrived { self.deliver(shipment); }
    }

    fn deliver(&mut self, shipment: Shipment) {
        let market = self.markets.get_mut(&shipment.destination).expect("known destination");
        let good = market.commodities.get_mut(&shipment.commodity).expect("known good");
        good.inventory += shipment.units;
        good.imports += shipment.units;
        market.trade_balance_centimes -= shipment.value_centimes;
        self.markets.get_mut(&shipment.origin).unwrap().trade_balance_centimes += shipment.value_centimes;
        self.last_arrivals.push(shipment);
    }

    pub(crate) fn reservation_ids(&self) -> impl Iterator<Item = u64> + '_ {
        self.shipments.iter().filter_map(|s| s.carriage.as_ref().map(|c| c.reservation))
    }

    pub(crate) fn validate_transport(&self, transport: &Operations, ledger: &Ledger) -> io::Result<()> {
        for shipment in self.shipments.iter().chain(&self.last_arrivals) {
            let Some(c) = &shipment.carriage else { continue };
            let buyer = format!("account:market_receipts:{}", self.markets[&shipment.destination].id);
            let seller = format!("account:market_receipts:{}", self.markets[&shipment.origin].id);
            if !ledger.has_payment(&format!("goods:{}", shipment.id), &buyer, &seller, shipment.value_centimes, "goods", &shipment.id)
                || !ledger.has_payment(&format!("carriage:{}", c.reservation), &buyer, TRANSPORT_ACCOUNT, c.fare_centimes, "freight", &shipment.id)
                || transport.network().segment(&shipment.route_id).is_none()
                || c.arrival_minute.checked_add(59).map(|m| m / 60) != Some(shipment.arrival_hour)
            { return Err(invalid("macro shipment conflicts with recorded goods or freight payment")); }
        }
        for shipment in &self.shipments {
            let Some(c) = &shipment.carriage else { continue };
            let plan = transport.plan(c.reservation).ok_or_else(|| invalid("macro freight reservation missing"))?;
            let buyer = format!("account:market_receipts:{}", self.markets[&shipment.destination].id);
            let refund = transport.unused_fare(c.reservation).unwrap_or(0);
            if transport.traffic(c.reservation) != Some(Traffic::Trade)
                || carriage_corridor(plan) != shipment.route_id || plan.route().from != c.from
                || transport.network().area_node(&shipment.destination) != Some(plan.route().to.as_str())
                || plan.load_units() != shipment.units.ceil() as u32 || c.fare_centimes != plan.fare_centimes()
                || plan.arrival_minute() != c.arrival_minute || c.held != transport.held(c.reservation).is_some()
                || refund > 0 && !ledger.has_payment(&format!("held-refund:{}", c.reservation), TRANSPORT_ACCOUNT, &buyer, refund, "cargo_refund", &shipment.id)
            { return Err(invalid("macro shipment conflicts with reservation or payment")); }
        }
        Ok(())
    }

    pub(crate) fn settle_transport(&mut self, transport: &mut Operations, ledger: &mut Ledger, now: i64) -> io::Result<()> {
        if !transport.trade_event_pending() { return Ok(()); }
        let mut idx = 0;
        while idx < self.shipments.len() {
            let row = &mut self.shipments[idx];
            let Some(c) = &mut row.carriage else { idx += 1; continue };
            if transport.completed(c.reservation).is_some() {
                transport.finish(c.reservation);
                let row = self.shipments.remove(idx);
                self.deliver(row);
                continue;
            }
            if !c.held && transport.held(c.reservation).is_some() {
                let refund = transport.unused_fare(c.reservation).unwrap_or(0);
                if refund > 0 {
                    let account = format!("account:market_receipts:{}", self.markets[&row.destination].id);
                    ledger.transfer(&format!("held-refund:{}", c.reservation), TRANSPORT_ACCOUNT,
                        &account, refund, now, "cargo_refund", &row.id)?;
                }
                c.held = true;
            }
            idx += 1;
        }
        transport.clear_trade_event();
        Ok(())
    }

    fn retry_held(&mut self, transport: &mut Operations, ledger: &mut Ledger, now: i64) -> io::Result<()> {
        for row in &mut self.shipments {
            let Some(c) = row.carriage.as_mut().filter(|c| c.held) else { continue };
            let from = transport.held(c.reservation).expect("held cargo station").to_owned();
            let to = transport.network().area_node(&row.destination).expect("scheduled destination").to_owned();
            let Ok(plan) = transport.quote_service(&from, &to, ModeSet::ALL, row.units.ceil() as u32, now, Traffic::Trade) else { continue };
            let buyer = &self.markets[&row.destination].id;
            let fare = plan.fare_centimes();
            if self.markets[&row.destination].trade_budget(ledger) < fare { continue; }
            let arrival = plan.arrival_minute();
            let route_id = carriage_corridor(&plan).to_owned();
            let id = transport.reserve_trade(plan)?;
            let payer = format!("account:market_receipts:{buyer}");
            if let Err(error) = self.markets.get_mut(&row.destination).unwrap().fund_order(ledger, fare, &format!("carriage:{id}"), now) {
                transport.finish(id);
                return Err(error);
            }
            if let Err(error) = ledger.transfer(&format!("carriage:{id}"), &payer, TRANSPORT_ACCOUNT, fare, now, "freight", &row.id) {
                transport.finish(id);
                return Err(error);
            }
            transport.finish(c.reservation);
            *c = TradeCarriage { reservation: id, from, fare_centimes: fare, arrival_minute: arrival, held: false };
            row.route_id = route_id;
            row.arrival_hour = (arrival + 59) / 60;
        }
        Ok(())
    }

    fn dispatch_shortages(&mut self, hour: i64, transport: &mut Operations, ledger: &mut Ledger) -> io::Result<()> {
        let now = hour * MINUTES_PER_HOUR;
        let mut dispatched = 0;
        let mut inbound = BTreeMap::<String, BTreeMap<String, f64>>::new();
        for s in &self.shipments {
            *inbound.entry(s.destination.clone()).or_default().entry(s.commodity.clone()).or_default() += s.units;
        }
        for receiver in self.inputs.countries.keys() {
            let Some(to) = transport.network().area_node(receiver).map(str::to_owned) else { continue };
            let buyer = self.markets[receiver].id.clone();
            let mut shortages: Vec<_> = self.inputs.commodities.iter()
                .filter(|commodity| commodity.international_liquidity_units > 0)
                .filter_map(|commodity| {
                    let id = &commodity.commodity_id;
                    let due = inbound.get(receiver).and_then(|market| market.get(id)).copied().unwrap_or(0.0);
                    let local = self.markets[receiver].commodities[id];
                    // Buy for the next two settlements when local output cannot replenish the stock.
                    let unmet = local.unmet + (2.0 * (local.demanded - local.produced) - local.inventory).max(0.0) - due;
                    (unmet > QUANTITY_EPSILON).then_some((id, unmet))
                }).collect();
            if shortages.is_empty() || self.markets[receiver].trade_budget(ledger) == 0 { continue; }
            let rates = transport.supplier_rates(&to);
            shortages.sort_by(|a, b| b.1.total_cmp(&a.1));
            for (commodity, mut remaining) in shortages.into_iter().take(MAX_SHORTAGES) {
                let mut suppliers: Vec<_> = rates.iter().filter_map(|(origin, &rate)| {
                    let good = self.markets.get(origin)?.commodities[commodity];
                    (good.surplus() > QUANTITY_EPSILON).then_some((good.price_centimes as u64 + rate, origin))
                }).collect();
                suppliers.sort_unstable();
                for (_, origin) in suppliers.into_iter().take(MAX_SUPPLIERS) {
                    if remaining <= QUANTITY_EPSILON || self.markets[receiver].trade_budget(ledger) <= 0 { break; }
                    let Some(from) = transport.network().area_node(origin).map(str::to_owned) else { continue };
                    let Ok(sample) = transport.quote_service(&from, &to, ModeSet::ALL, 1, now, Traffic::Trade) else { continue };
                    let ceiling = sample.route().legs.iter().filter_map(|leg| transport.service_capacity(&leg.segment_id, &leg.from))
                        .map(|cap| cap.line_limit.min(cap.cargo_limit)).min().unwrap_or(0);
                    let budget = self.markets[receiver].trade_budget(ledger);
                    let good = self.markets[origin].commodities[commodity];
                    let units = remaining.min(good.surplus()).min(f64::from(ceiling))
                        .min((budget / (good.price_centimes + sample.fare_centimes()).max(1)) as f64);
                    if units <= QUANTITY_EPSILON { continue; }
                    let Ok(plan) = transport.quote_service(&from, &to, ModeSet::ALL, units.ceil() as u32, now, Traffic::Trade) else { continue };
                    if plan.first_departure_minute() >= now + MINUTES_PER_DAY { continue; }
                    let fare = plan.fare_centimes();
                    let value = ((units * good.price_centimes as f64).ceil() as i64).max(1);
                    let destination_value = (units * self.markets[receiver].commodities[commodity].price_centimes as f64).ceil() as i64;
                    if value > budget - fare || value > MAX_AMOUNT || value + fare > destination_value { continue; }
                    let arrival = plan.arrival_minute();
                    let route_id = carriage_corridor(&plan).to_owned();
                    let reservation = transport.reserve_trade(plan)?;
                    let id = format!("formal_shipment:{}", self.next_shipment);
                    let payer = format!("account:market_receipts:{buyer}");
                    let seller = format!("account:market_receipts:{}", self.markets[origin].id);
                    let goods_id = format!("goods:{id}");
                    let fare_id = format!("carriage:{reservation}");
                    ledger.ensure_market_seller(&self.markets[origin].id)?;
                    if let Err(error) = self.markets.get_mut(receiver).unwrap().fund_order(ledger, value + fare, &id, now) {
                        transport.finish(reservation);
                        return Err(error);
                    }
                    let legs = [
                        PaymentLeg { id: &goods_id, from: &payer, to: &seller, amount: value, kind: "goods", reference: &id },
                        PaymentLeg { id: &fare_id, from: &payer, to: TRANSPORT_ACCOUNT, amount: fare, kind: "freight", reference: &id },
                    ];
                    if let Err(error) = ledger.batch_payment(&id, &legs, now, &BTreeMap::new()) {
                        transport.finish(reservation);
                        return Err(error);
                    }
                    let good = self.markets.get_mut(origin).unwrap().commodities.get_mut(commodity).unwrap();
                    good.inventory -= units;
                    good.exports += units;
                    self.shipments.push(Shipment {
                        id, origin: origin.clone(), destination: receiver.clone(), commodity: commodity.clone(),
                        units, value_centimes: value, dispatch_hour: hour, arrival_hour: (arrival + 59) / 60,
                        route_id,
                        carriage: Some(TradeCarriage { reservation, from, fare_centimes: fare, arrival_minute: arrival, held: false }),
                    });
                    self.next_shipment += 1;
                    remaining -= units;
                    dispatched += 1;
                    if dispatched == MAX_DAILY_SHIPMENTS { return Ok(()); }
                }
            }
        }
        Ok(())
    }
}

fn carriage_corridor(plan: &crate::transport::operations::Plan) -> &str {
    let legs = &plan.route().legs;
    &legs.iter().max_by_key(|leg| leg.profile.travel_minutes).expect("nonempty carriage").segment_id
}

impl CommodityState {
    fn quote(self, quantity_milli: i64) -> io::Result<i64> {
        use crate::formal_ledger::MAX_AMOUNT;
        if quantity_milli <= 0 || quantity_milli as f64 / 1000.0 > self.inventory {
            return Err(invalid("市场现货不足或数量无效。"));
        }
        let amount = quantity_milli.checked_mul(self.price_centimes).filter(|total| *total <= MAX_AMOUNT - 999)
            .ok_or_else(|| invalid("purchase amount exceeds formal bounds"))?;
        Ok((amount + 999) / 1000)
    }
}

impl Market {
    fn trade_budget(&self, ledger: &Ledger) -> i64 {
        ledger.market_cash(&self.id).saturating_add(self.gold_reserve_units.floor() as i64).min(MAX_AMOUNT)
    }

    fn fund_order(&mut self, ledger: &mut Ledger, amount: i64, reference: &str, now: i64) -> io::Result<()> {
        let shortfall = (amount - ledger.market_cash(&self.id)).max(0);
        if shortfall == 0 { return Ok(()); }
        if shortfall > self.gold_reserve_units.floor() as i64 { return Err(invalid("market cannot fund the purchase")); }
        let realized = ledger.realize_market_reserve(&self.id, shortfall, reference, now)?;
        self.gold_reserve_units -= realized as f64;
        Ok(())
    }

    fn restore(&mut self, row: &[Value]) -> io::Result<()> {
        let inventory = map(field(row, "inventory")?)?;
        let prices = map(field(row, "prices")?)?;
        let metrics = map(field(row, "daily_metrics")?)?;
        if [inventory, prices, metrics].into_iter().any(|values| values.len() != self.commodities.len()) {
            return Err(invalid("saved market commodity roster differs from the formal world"));
        }
        for (id, commodity) in &mut self.commodities {
            let metric = map(field(metrics, id)?)?;
            *commodity = CommodityState {
                inventory: nonnegative(inventory, id)?,
                price_centimes: integer(field(prices, id)?)?,
                demanded: nonnegative(metric, "demand")?,
                produced: nonnegative(metric, "produced")?,
                consumed: nonnegative(metric, "consumed")?,
                unmet: nonnegative(metric, "unmet")?,
                imports: nonnegative(metric, "imports")?,
                exports: nonnegative(metric, "exports")?,
            };
            if !(0..=i32::MAX as i64).contains(&commodity.price_centimes) {
                return Err(invalid("saved market price is outside the simulation range"));
            }
        }
        self.gold_reserve_units = nonnegative(row, "gold_reserve_units")?;
        self.trade_balance_centimes = integer(field(row, "trade_balance_centimes")?)?;
        self.tariff_revenue_centimes = integer(field(row, "tariff_revenue_centimes")?)?;
        let totals = map(field(row, "daily_totals")?)?;
        self.daily_totals = if totals.is_empty() { None } else { Some(DailyTotals {
            demanded: nonnegative(totals, "demand_units")?,
            produced: nonnegative(totals, "produced_units")?,
            consumed: nonnegative(totals, "consumed_units")?,
            unmet: nonnegative(totals, "unmet_units")?,
            fulfillment_bp: integer(field(totals, "fulfillment_bp")?)?,
        }) };
        Ok(())
    }

    fn snapshot(&self, unit: &str, hour: i64) -> Value {
        let inventory = typed_map(self.commodities.iter().map(|(id, row)| (id, encode_number(row.inventory))));
        let prices = typed_map(self.commodities.iter().map(|(id, row)| (id, typed_int(row.price_centimes))));
        let metrics = typed_map(self.commodities.iter().map(|(id, row)| {
            (id, typed_map([
                ("demand", encode_number(row.demanded)),
                ("produced", encode_number(row.produced)),
                ("consumed", encode_number(row.consumed)),
                ("unmet", encode_number(row.unmet)),
                ("imports", encode_number(row.imports)),
                ("exports", encode_number(row.exports)),
            ]))
        }));
        let totals = self.daily_totals.as_ref().map_or_else(|| json!(["map", []]), |totals| typed_map([
            ("demand_units", encode_number(totals.demanded)),
            ("produced_units", encode_number(totals.produced)),
            ("consumed_units", encode_number(totals.consumed)),
            ("unmet_units", encode_number(totals.unmet)),
            ("fulfillment_bp", typed_int(totals.fulfillment_bp)),
        ]));
        typed_map([
            ("market_id", json!(self.id)),
            ("source_economic_aggregate_id", json!(unit)),
            ("inventory", inventory),
            ("prices", prices),
            ("daily_metrics", metrics),
            ("daily_totals", totals),
            ("gold_reserve_units", encode_number(self.gold_reserve_units)),
            ("trade_balance_centimes", typed_int(self.trade_balance_centimes)),
            ("tariff_revenue_centimes", typed_int(self.tariff_revenue_centimes)),
            ("last_settlement_hour", typed_int(hour)),
        ])
    }
}

impl Shipment {
    fn restore(row: &[Value]) -> io::Result<Self> {
        if text(row, "status")? != "in_transit" {
            return Err(invalid("expected an in-transit macro shipment"));
        }
        Ok(Self {
            id: text(row, "shipment_id")?.to_owned(),
            origin: text(row, "origin_entity_id")?.to_owned(),
            destination: text(row, "destination_entity_id")?.to_owned(),
            commodity: text(row, "commodity_id")?.to_owned(),
            units: number(field(row, "units")?)?,
            value_centimes: integer(field(row, "value_centimes")?)?,
            dispatch_hour: integer(field(row, "dispatch_hour")?)?,
            arrival_hour: integer(field(row, "arrival_hour")?)?,
            route_id: text(row, "route_id")?.to_owned(),
            carriage: lookup(row, "carriage").map(|value| -> io::Result<_> {
                let fields = map(value)?;
                Ok(TradeCarriage {
                    reservation: u64::try_from(integer(field(fields, "reservation")?)?).map_err(|_| invalid("invalid carriage ID"))?,
                    from: text(fields, "from")?.to_owned(),
                    fare_centimes: integer(field(fields, "fare")?)?,
                    arrival_minute: integer(field(fields, "arrival")?)?,
                    held: field(fields, "held")?.as_bool().ok_or_else(|| invalid("invalid cargo custody"))?,
                })
            }).transpose()?,
        })
    }

    fn snapshot(&self) -> Value {
        let mut fields = vec![
            ("shipment_id", json!(self.id)),
            ("origin_entity_id", json!(self.origin)),
            ("destination_entity_id", json!(self.destination)),
            ("commodity_id", json!(self.commodity)),
            ("units", encode_number(self.units)),
            ("value_centimes", typed_int(self.value_centimes)),
            ("dispatch_hour", typed_int(self.dispatch_hour)),
            ("arrival_hour", typed_int(self.arrival_hour)),
            ("route_id", json!(self.route_id)),
            ("status", json!("in_transit")),
        ];
        if let Some(c) = &self.carriage {
            fields.push(("carriage", typed_map([("reservation", typed_int(c.reservation as i64)), ("from", json!(c.from)),
                ("fare", typed_int(c.fare_centimes)), ("arrival", typed_int(c.arrival_minute)), ("held", json!(c.held))])));
        }
        typed_map(fields)
    }
}

fn text<'a>(row: &'a [Value], key: &str) -> io::Result<&'a str> {
    field(row, key)?.as_str().ok_or_else(|| invalid(format!("invalid saved macro text {key}")))
}

fn nonnegative(row: &[Value], key: &str) -> io::Result<f64> {
    let value = number(field(row, key)?)?;
    if value < 0.0 {
        return Err(invalid(format!("negative saved macro field {key}")));
    }
    Ok(value)
}

impl CommodityState {
    fn surplus(&self) -> f64 {
        (self.inventory - self.demanded * 10.0).max(0.0)
    }
}

impl CountryInputs {
    fn production_factor(&self, commodity: &Commodity) -> f64 {
        const MINERALS: &[&str] = &["coal", "iron_ore", "copper", "petroleum", "timber"];
        if let Some(index) = MINERALS.iter().position(|id| *id == commodity.commodity_id) {
            return (self.minerals[index] as f64 / 70.0).clamp(0.0, 2.5);
        }
        let agriculture = self.agriculture as f64 / 100.0;
        let industry = self.industry as f64 / 100.0;
        match commodity.category.as_str() {
            "agricultural_food" | "agricultural_input" => agriculture.clamp(0.05, 2.2),
            "industrial_material" | "capital_good" | "manufactured_good" | "processed_food" | "textile" =>
                industry.clamp(0.03, 2.4),
            _ => ((agriculture + industry) * 0.5).clamp(0.05, 1.8),
        }
    }
}

impl Commodity {
    fn daily_demand(&self, population: u64, income: u64) -> f64 {
        let income = (income as f64 / 2200.0).clamp(0.25, 3.0);
        let elasticity = self.income_elasticity_bp as f64 / BASIS_POINTS as f64;
        let factor = (1.0 + (income - 1.0) * elasticity).clamp(0.3, 3.5);
        self.base_daily_units_per_million * population as f64 / 1_000_000.0 * factor
    }
}

impl MarketInputs {
    pub(crate) fn load(countries: BTreeMap<String, CountryInputs>) -> io::Result<Self> {
        #[derive(Deserialize)]
        struct Goods {
            schema_id: String,
            commodities: Vec<Commodity>,
        }
        let goods: Goods = serde_json::from_slice(include_bytes!("../../../data/alpha/commodity_market_1900.json"))?;
        if goods.schema_id != "alpha_commodity_market_1900_v1" || goods.commodities.is_empty() {
            return Err(invalid("invalid formal commodity catalog"));
        }
        let mut ids = std::collections::BTreeSet::new();
        for commodity in &goods.commodities {
            if !local_id(&commodity.commodity_id)
                || !ids.insert(&commodity.commodity_id)
                || !(1..=i32::MAX as i64).contains(&commodity.base_price_centimes)
                || commodity.base_daily_units_per_million < 0.0
            {
                return Err(invalid("invalid macro commodity source record"));
            }
        }
        let routes = load_routes(&countries)?;
        Ok(Self { countries, commodities: goods.commodities, routes })
    }
}

fn load_routes(countries: &BTreeMap<String, CountryInputs>) -> io::Result<Vec<TradeRoute>> {
    #[derive(Deserialize)]
    struct Transport {
        schema_id: String,
        maritime_field_order: Vec<String>,
        maritime_rows: Vec<Vec<Value>>,
        river_field_order: Vec<String>,
        river_rows: Vec<Vec<Value>>,
    }
    let table: Transport = serde_json::from_slice(include_bytes!(
        "../../../data/alpha/historical_transport_network_1900/transport_compact.json"
    ))?;
    if table.schema_id != "historical_transport_network_1900_compact_tables_v1" {
        return Err(invalid("invalid macro transport source table"));
    }
    let mut routes = Vec::new();
    let [id, origin, destination, days, capacity] = columns(&table.maritime_field_order, [
        "corridor_id", "origin_entity_id", "destination_entity_id", "duration_days", "capacity_index",
    ])?;
    for row in table.maritime_rows {
        if row.len() != table.maritime_field_order.len() {
            return Err(invalid("invalid maritime route row"));
        }
        let [id, origin, destination] = [id, origin, destination].map(|index| row[index].as_str());
        let (Some(id), Some(origin), Some(destination), Some(days), Some(_capacity)) =
            (id, origin, destination, row[days].as_u64(), row[capacity].as_u64())
        else {
            return Err(invalid("invalid maritime route fields"));
        };
        if origin == destination || !countries.contains_key(origin) || !countries.contains_key(destination) {
            continue;
        }
        let duration_hours = i64::try_from(days.max(1)).ok().and_then(|value| value.checked_mul(HOURS_PER_DAY))
            .ok_or_else(|| invalid("invalid maritime route duration"))?;
        routes.push(TradeRoute { id: id.to_owned(), origin: origin.to_owned(),
            destination: destination.to_owned(), duration_hours });
    }
    let [id, units, capacity] = columns(&table.river_field_order, ["corridor_id", "entity_ids", "capacity_index"])?;
    for row in table.river_rows {
        if row.len() != table.river_field_order.len() {
            return Err(invalid("invalid river route row"));
        }
        let (Some(id), Some(units), Some(_capacity)) = (row[id].as_str(), row[units].as_array(), row[capacity].as_u64())
        else {
            return Err(invalid("invalid river route fields"));
        };
        for (index, pair) in units.windows(2).enumerate() {
            let (Some(origin), Some(destination)) = (pair[0].as_str(), pair[1].as_str()) else {
                return Err(invalid("invalid river route economy"));
            };
            if origin == destination || !countries.contains_key(origin) || !countries.contains_key(destination) {
                continue;
            }
            routes.push(TradeRoute { id: format!("{id}:{index}"), origin: origin.to_owned(),
                destination: destination.to_owned(), duration_hours: 3 * HOURS_PER_DAY });
        }
    }
    Ok(routes)
}
