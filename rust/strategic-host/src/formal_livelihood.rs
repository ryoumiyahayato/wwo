use crate::{
    formal_bootstrap::{Consumption, InitialWorld},
    formal_ledger::{Balance, MAX_AMOUNT},
    formal_population::needs::{recorded_food_energy, FoodEnergyEstimate, QuantityRange},
    formal_stock::ConsumptionAllocation,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

// The catalogue uses tonnes. A milli-unit of these staples is one kilogram.
// Staple weight is a provisional need measure used by the opening simulation.
pub(crate) const STAPLES: [&str; 7] = [
    "bread",
    "potatoes",
    "rice",
    "maize",
    "pulses",
    "rye",
    "preserved_food",
];

pub(crate) fn counts_as_food(good: &str) -> bool {
    STAPLES.contains(&good)
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FoodShortfall {
    PlayerChoice,
    NoCashAccount,
    NoReachableMarket,
    InsufficientCash,
    InsufficientStock,
    TransactionUnavailable,
}

impl FoodShortfall {
    pub fn label(self) -> &'static str {
        match self {
            Self::PlayerChoice => "缺少已购买的主食",
            Self::NoCashAccount => "缺少个人账户",
            Self::NoReachableMarket => "所在地无可达市场",
            Self::InsufficientCash => "可用现金不足",
            Self::InsufficientStock => "市场主食库存不足",
            Self::TransactionUnavailable => "交易或库存消耗未完成",
        }
    }
}

#[derive(Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct DailyLivelihood {
    pub day: u32,
    pub food_required_milli: i64,
    pub food_received_milli: i64,
    pub automatic_food_expense: i64,
    pub food_shortfall: Option<FoodShortfall>,
    pub consecutive_shortfall_days: u32,
}

impl DailyLivelihood {
    fn nutrition(&self) -> u16 {
        (i128::from(self.food_received_milli) * 1000 / i128::from(self.food_required_milli)) as u16
    }
}

#[derive(Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FoodPortion {
    pub commodity: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub donor: Option<String>,
    pub allocations: Vec<ConsumptionAllocation>,
}

#[derive(Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct FoodIntake {
    pub day: u32,
    pub portions: Vec<FoodPortion>,
}

#[derive(Serialize)]
pub struct RecordedIntakeEnergy {
    pub converted_kg: i64,
    pub unconverted_kg: i64,
    pub energy: Option<FoodEnergyEstimate>,
}

impl FoodIntake {
    /// Estimate energy only for consumed portions with a documented conversion.
    /// The original stock allocations remain the intake authority.
    pub fn recorded_energy(&self) -> RecordedIntakeEnergy {
        let mut result = RecordedIntakeEnergy { converted_kg: 0, unconverted_kg: 0, energy: None };
        for portion in &self.portions {
            let mass_kg: i64 = portion.allocations.iter().map(|lot| lot.quantity_milli).sum();
            match recorded_food_energy(&portion.commodity, mass_kg as f64) {
                Some(estimate) => {
                    result.converted_kg += mass_kg;
                    let total = result.energy.get_or_insert(FoodEnergyEstimate {
                        kcal: QuantityRange { lower: 0.0, upper: 0.0 },
                        source: estimate.source,
                    });
                    total.kcal.lower += estimate.kcal.lower;
                    total.kcal.upper += estimate.kcal.upper;
                }
                None => result.unconverted_kg += mass_kg,
            }
        }
        result
    }
}

pub struct PersonLivelihood<'a> {
    pub budget: Option<Balance<'a>>,
    pub food_held_milli: i64,
    pub food_received_today_milli: i64,
    pub last_day: Option<&'a DailyLivelihood>,
    pub last_food_intake: Option<&'a FoodIntake>,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Livelihood {
    people: BTreeMap<String, PersonNeeds>,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PersonNeeds {
    today: Vec<FoodPortion>,
    last_day: Option<DailyLivelihood>,
    last_intake: Option<FoodIntake>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    retail_shortfalls: BTreeMap<String, i64>,
}

impl Livelihood {
    pub(crate) fn retail_shortfall(&self, person: &str, good: &str) -> i64 {
        self.people.get(person).and_then(|needs| needs.retail_shortfalls.get(good)).copied().unwrap_or(0)
    }

    pub(crate) fn set_retail_shortfall(&mut self, person: &str, good: &str, amount: i64) {
        if amount > 0 {
            self.people.entry(person.into()).or_default().retail_shortfalls.insert(good.into(), amount);
        } else if let Some(needs) = self.people.get_mut(person) {
            needs.retail_shortfalls.remove(good);
        }
    }

    pub(crate) fn record_food(
        &mut self,
        person: &str,
        good: &str,
        consumption: &Consumption,
        cap: i64,
    ) {
        if counts_as_food(good) {
            let today = &mut self.people.entry(person.to_owned()).or_default().today;
            record_food(
                today,
                good,
                consumption,
                cap - food_quantity(today).unwrap(),
            );
        }
    }
}

impl InitialWorld {
    pub(crate) fn settle_retail_need(&mut self, person: &str, good: &str, accrued: i64) -> std::io::Result<i64> {
        let due = self.livelihood.retail_shortfall(person, good).checked_add(accrued)
            .filter(|amount| (0..=MAX_AMOUNT).contains(amount))
            .ok_or_else(|| crate::formal_save::invalid("累计家庭需求超出范围。"))?;
        let mut remaining = due;
        if let Some(holding) = self.holdings.get_mut(person).and_then(|stock| stock.get_mut(good)) {
            let used = holding.available().min(due);
            if used > 0 {
                holding.consume(used)?;
                remaining -= used;
            }
        }
        self.livelihood.set_retail_shortfall(person, good, remaining);
        Ok(remaining)
    }

    pub fn person_livelihood(&self, person: &str) -> Option<PersonLivelihood<'_>> {
        self.person(person)?;
        let needs = self.livelihood.people.get(person);
        Some(PersonLivelihood {
            budget: self.ledger().default_account(person),
            food_held_milli: STAPLES.iter().fold(0i64, |sum, good| {
                sum.saturating_add(self.person_holding_milli(person, good))
            }),
            food_received_today_milli: needs
                .and_then(|needs| food_quantity(&needs.today))
                .unwrap_or(0),
            last_day: needs.and_then(|needs| needs.last_day.as_ref()),
            last_food_intake: needs.and_then(|needs| needs.last_intake.as_ref()),
        })
    }

    pub(crate) fn validate_livelihood(&self, current_day: u32, target: i64) -> bool {
        self.livelihood.people.iter().all(|(person, needs)| {
            let valid_portions = |portions: &[FoodPortion]| {
                food_quantity(portions).is_some_and(|amount| amount <= target)
                    && portions.iter().all(|portion| {
                        counts_as_food(&portion.commodity)
                            && !portion.allocations.is_empty()
                            && portion.donor.as_ref().is_none_or(|donor| donor != person && self.person(donor).is_some())
                            && portion.allocations.iter().all(|allocation| {
                                allocation.quantity_milli > 0
                                    && self
                                        .ledger()
                                        .has_purchase(portion.donor.as_deref().unwrap_or(person), &allocation.purchase_record_id)
                            })
                    })
            };
            self.person(person).is_some()
                && needs.retail_shortfalls.iter().all(|(good, amount)| !counts_as_food(good)
                    && self.macro_economy().purchasable(good) && (1..=MAX_AMOUNT).contains(amount))
                && valid_portions(&needs.today)
                && (needs.today.is_empty() || self.population.unit_for_person(person).is_some())
                && needs.last_day.as_ref().is_none_or(|last_day| {
                    (1..=current_day).contains(&last_day.day)
                        && last_day.food_required_milli == target
                        && (0..=target).contains(&last_day.food_received_milli)
                        && (0..=MAX_AMOUNT).contains(&last_day.automatic_food_expense)
                        && (last_day.food_received_milli < target)
                            == last_day.food_shortfall.is_some()
                        && (last_day.consecutive_shortfall_days > 0)
                            == last_day.food_shortfall.is_some()
                        && last_day.consecutive_shortfall_days <= last_day.day
                        && needs
                            .last_intake
                            .as_ref()
                            .filter(|intake| intake.day == last_day.day)
                            .map_or(Some(0), |intake| food_quantity(&intake.portions))
                            == Some(last_day.food_received_milli)
                })
                && needs.last_intake.as_ref().is_none_or(|intake| {
                    needs
                        .last_day
                        .as_ref()
                        .is_some_and(|last_day| (1..=last_day.day).contains(&intake.day))
                        && !intake.portions.is_empty()
                        && valid_portions(&intake.portions)
                })
        })
    }

    pub(crate) fn settle_named_livelihood(
        &mut self,
        day: u32,
        minute: i64,
        target: i64,
    ) -> (BTreeMap<String, u16>, BTreeSet<String>) {
        let people = self.named_people().map(str::to_owned).collect::<Vec<_>>();
        let mut nutrition = BTreeMap::new();
        let mut paid = BTreeSet::new();
        for person in people {
            let mut needs = self.livelihood.people.remove(&person).unwrap_or_default();
            if let Some(last_day) = needs.last_day.as_ref().filter(|record| record.day == day) {
                nutrition.insert(person.clone(), last_day.nutrition());
                self.livelihood.people.insert(person, needs);
                continue;
            }
            let mut portions = std::mem::take(&mut needs.today);
            let mut remaining = target - food_quantity(&portions).unwrap();
            let holdings_result =
                self.eat_held_staples(&person, minute, &mut remaining, &mut portions)
                    .and_then(|_| self.eat_shared_staples(&person, day, minute, &mut remaining, &mut portions));
            let mut expense = 0;
            let failure = if remaining == 0 {
                None
            } else if holdings_result.is_err() {
                Some(FoodShortfall::TransactionUnavailable)
            } else if person == self.player {
                Some(FoodShortfall::PlayerChoice)
            } else {
                self.obtain_staples(&person, minute, &mut remaining, &mut expense, &mut portions)
            };
            let consecutive_shortfall_days = failure.map_or(0, |_| {
                needs.last_day.as_ref().map_or(1, |last| {
                    if last.day.checked_add(1) == Some(day) {
                        last.consecutive_shortfall_days + 1
                    } else {
                        1
                    }
                })
            });
            let outcome = DailyLivelihood {
                day,
                food_required_milli: target,
                food_received_milli: target - remaining,
                automatic_food_expense: expense,
                food_shortfall: failure,
                consecutive_shortfall_days,
            };
            nutrition.insert(person.clone(), outcome.nutrition());
            if expense > 0 { paid.insert(person.clone()); }
            if !portions.is_empty() {
                needs.last_intake = Some(FoodIntake { day, portions });
            }
            needs.last_day = Some(outcome);
            self.livelihood.people.insert(person, needs);
        }
        (nutrition, paid)
    }

    fn eat_held_staples(
        &mut self,
        person: &str,
        minute: i64,
        remaining: &mut i64,
        portions: &mut Vec<FoodPortion>,
    ) -> std::io::Result<()> {
        for good in STAPLES {
            let quantity = (*remaining).min(self.person_holding_milli(person, good));
            if quantity > 0 {
                self.eat_staple(person, minute, good, quantity, remaining, portions)?;
            }
        }
        Ok(())
    }

    fn eat_shared_staples(
        &mut self,
        person: &str,
        day: u32,
        minute: i64,
        remaining: &mut i64,
        portions: &mut Vec<FoodPortion>,
    ) -> std::io::Result<()> {
        if *remaining == 0 { return Ok(()); }
        let donors = self.households.food_donors(person, |other| self.current_place(other))
            .into_iter().map(str::to_owned).collect::<Vec<_>>();
        let target = *remaining + food_quantity(portions).unwrap();
        for donor in donors {
            let needs = self.livelihood.people.get(&donor);
            let fed = needs.and_then(|needs| needs.last_day.as_ref().filter(|last| last.day == day))
                .map_or_else(|| needs.and_then(|needs| food_quantity(&needs.today)).unwrap_or(0), |last| last.food_received_milli);
            let stock = self.person_livelihood(&donor).map_or(0, |livelihood| livelihood.food_held_milli);
            let mut excess = stock.saturating_sub(target.saturating_sub(fed));
            for good in STAPLES {
                let quantity = (*remaining).min(excess).min(self.person_holding_milli(&donor, good));
                if quantity <= 0 { continue; }
                let shared = self.consume_livelihood_stock(&donor, good, quantity, minute)?;
                record_food(portions, good, &shared, quantity);
                portions.last_mut().expect("recorded positive intake").donor = Some(donor.clone());
                *remaining -= quantity;
                excess -= quantity;
            }
            if *remaining == 0 { break; }
        }
        Ok(())
    }

    fn obtain_staples(
        &mut self,
        person: &str,
        minute: i64,
        remaining: &mut i64,
        expense: &mut i64,
        portions: &mut Vec<FoodPortion>,
    ) -> Option<FoodShortfall> {
        let Some(account) = self.ledger().default_account(person) else {
            return Some(FoodShortfall::NoCashAccount);
        };
        let mut available = account.available;
        let mut cash_short = self
            .local_bread_offer_for(person, *remaining)
            .is_some_and(|offer| {
                i128::from(offer.price) * i128::from(*remaining) > i128::from(available)
            });

        let firm_unavailable = match self.buy_local_firm_meal(person, *remaining, minute) {
            Ok(Some(amount)) => {
                *expense += amount;
                let quantity = *remaining;
                return self
                    .eat_staple(person, minute, "bread", quantity, remaining, portions)
                    .err()
                    .map(|_| FoodShortfall::TransactionUnavailable);
            }
            Ok(None) => false,
            Err(_) => true,
        };
        let Some(market) = self
            .market_unit_for_person(person)
            .and_then(|unit| self.macro_economy().markets().get(unit))
        else {
            return Some(if firm_unavailable {
                FoodShortfall::TransactionUnavailable
            } else if cash_short {
                FoodShortfall::InsufficientCash
            } else {
                FoodShortfall::NoReachableMarket
            });
        };
        let market_id = market.id.clone();
        let mut offers = STAPLES
            .iter()
            .filter_map(|&good| {
                let state = market.commodities.get(good)?;
                let quantity = (state.inventory * 1000.0).floor() as i64;
                (quantity > 0 && state.price_centimes > 0).then_some((
                    state.price_centimes,
                    good,
                    quantity,
                ))
            })
            .collect::<Vec<_>>();
        offers.sort_unstable();

        let mut purchase_failed = firm_unavailable;
        for (price, good, stock) in offers {
            let needed_stock = (*remaining).min(stock);
            let affordable = (i128::from(available) * 1000 / i128::from(price))
                .min(i128::from(MAX_AMOUNT)) as i64;
            let quantity = needed_stock.min(affordable);
            cash_short |= quantity < needed_stock;
            if quantity == 0 {
                continue;
            }
            match self.buy_livelihood_stock(person, &market_id, good, quantity, price, minute, false) {
                Ok(amount) => {
                    available -= amount;
                    *expense += amount;
                    if self
                        .eat_staple(person, minute, good, quantity, remaining, portions)
                        .is_err()
                    {
                        return Some(FoodShortfall::TransactionUnavailable);
                    }
                    if *remaining == 0 {
                        return None;
                    }
                }
                Err(_) => purchase_failed = true,
            }
        }
        Some(if purchase_failed {
            FoodShortfall::TransactionUnavailable
        } else if cash_short {
            FoodShortfall::InsufficientCash
        } else {
            FoodShortfall::InsufficientStock
        })
    }

    fn eat_staple(
        &mut self,
        person: &str,
        minute: i64,
        good: &str,
        quantity: i64,
        remaining: &mut i64,
        portions: &mut Vec<FoodPortion>,
    ) -> std::io::Result<()> {
        let meal = self.consume_livelihood_stock(person, good, quantity, minute)?;
        record_food(portions, good, &meal, quantity);
        *remaining -= quantity;
        Ok(())
    }
}

fn food_quantity(portions: &[FoodPortion]) -> Option<i64> {
    portions
        .iter()
        .flat_map(|portion| &portion.allocations)
        .try_fold(0i64, |quantity, allocation| {
            quantity.checked_add(allocation.quantity_milli)
        })
}

fn record_food(portions: &mut Vec<FoodPortion>, good: &str, consumption: &Consumption, cap: i64) {
    let mut remaining = cap;
    let mut allocations = Vec::new();
    for allocation in &consumption.allocations {
        if remaining <= 0 {
            break;
        }
        let quantity_milli = allocation.quantity_milli.min(remaining);
        remaining -= quantity_milli;
        allocations.push(ConsumptionAllocation {
            purchase_record_id: allocation.purchase_record_id.clone(),
            quantity_milli,
        });
    }
    if !allocations.is_empty() {
        portions.push(FoodPortion {
            commodity: good.to_owned(),
            donor: None,
            allocations,
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{formal_bootstrap::WorldBootstrap, formal_clock::MINUTES_PER_DAY};

    const PLAYER: &str = "person:formal_generated_country_fra_0001";
    const WORKER: &str = "person:formal_generated_country_fra_0002";
    const LONDON_NPC: &str = "person:formal_generated_british_isles_1900_0001";

    #[test]
    fn named_meals_use_paid_food_and_shortages_reach_health() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let market = &world.macro_economy().markets()["country_fra"];
        let price = market.commodities["potatoes"].price_centimes;
        let local_market = market.id.clone();
        world
            .buy_local_stock(&local_market, "potatoes", 1, price, "player-meal")
            .unwrap();
        let cash_after_manual_purchase = world.balance().unwrap().cash;
        let npc_cash_before = world.ledger().default_account(LONDON_NPC).unwrap().cash;

        world
            .advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new())
            .unwrap();

        let player = world.person_livelihood(PLAYER).unwrap();
        assert_eq!(player.budget.unwrap().cash, cash_after_manual_purchase);
        assert_eq!(player.food_held_milli, 0);
        let player_day = player.last_day.unwrap();
        assert_eq!(player_day.food_received_milli, 1);
        assert_eq!(player_day.automatic_food_expense, 0);
        assert_eq!(player_day.food_shortfall, None);
        assert_eq!(
            player.last_food_intake.unwrap().portions[0].commodity,
            "potatoes"
        );

        let npc = world.person_livelihood(LONDON_NPC).unwrap();
        assert_eq!(npc.last_day.unwrap().food_received_milli, 1);
        let paid = npc.last_day.unwrap().automatic_food_expense;
        assert!(paid > 0);
        assert_eq!(npc.budget.unwrap().cash, npc_cash_before - paid);
        let intake = npc.last_food_intake.unwrap();
        let allocation = &intake.portions[0].allocations[0];
        assert_eq!(allocation.quantity_milli, 1);
        assert!(world
            .ledger()
            .has_purchase(LONDON_NPC, &allocation.purchase_record_id));

        let poor_npc = world.person_livelihood(WORKER).unwrap();
        assert_eq!(
            poor_npc.last_day.unwrap().food_shortfall,
            Some(FoodShortfall::InsufficientCash)
        );
        assert_eq!(poor_npc.last_day.unwrap().consecutive_shortfall_days, 1);
        assert!(poor_npc.last_food_intake.is_none());
        let snapshot = world.snapshot();
        let health: serde_json::Value =
            serde_json::from_str(snapshot["character"].as_str().unwrap()).unwrap();
        assert_eq!(health["people"][WORKER]["health"]["current"], 990);
        assert_eq!(health["people"][LONDON_NPC]["health"]["current"], 1000);

        let mut restored = bootstrap
            .restore_native(serde_json::from_value(snapshot).unwrap())
            .unwrap();
        let restored_npc = restored.person_livelihood(LONDON_NPC).unwrap();
        assert_eq!(restored_npc.last_day, npc.last_day);
        assert_eq!(restored_npc.last_food_intake, npc.last_food_intake);

        restored
            .advance_migrated_domains(2 * MINUTES_PER_DAY, &BTreeMap::new())
            .unwrap();
        let worker = restored.person_livelihood(WORKER).unwrap();
        let worker_day = worker.last_day.unwrap();
        assert_eq!(worker_day.food_shortfall, None);
        assert_eq!(worker_day.consecutive_shortfall_days, 0);
        assert!(worker_day.automatic_food_expense > 0);
        let wage = restored
            .ledger()
            .personal_receipts(WORKER)
            .find(|receipt| receipt.incoming && receipt.kind == "wage")
            .unwrap();
        assert_eq!(wage.minute, 3 * MINUTES_PER_DAY);
        assert_eq!(
            worker.budget.unwrap().cash,
            wage.amount - worker_day.automatic_food_expense
        );
    }
}
