use crate::{
    formal_character::{self, CharacterOutput, DayActivity},
    formal_clock::{ClockSnapshot, GameClock, MINUTES_PER_DAY, MINUTES_PER_HOUR},
    formal_ledger::{Balance, Ledger, CURRENCY, MAX_AMOUNT},
    formal_macro::{CountryInputs, MacroEconomy, MarketInputs, Shipment},
    formal_population::{Population, MAX_POPULATION},
    formal_save::{invalid, typed_map},
    formal_step::next_day_boundary,
    formal_stock::PersonalHolding,
    formal_wages::{Claim, WageClaims},
    formal_work::{Job, WorkOpening, WorkState},
};
pub use crate::formal_stock::ConsumptionAllocation;
pub use crate::formal_wages::CompletedFirmWork;
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::Value;
use wwo_character_core::{Language, Prologue, ASSUMPTION};

#[derive(Deserialize)]
struct OpeningActivities {
    basis: String,
    lesson_effort: u16,
    lesson_start_hour: i64,
    lesson_hours: i64,
    meal_milli_for_recovery: i64,
    work_injury_interval: u32,
    work_injury_damage: u16,
    work_injury_permanent_loss: u16,
    openings: BTreeMap<String, Language>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum PersonalActivity { Lesson, Rest, ReadNotice }

#[derive(Clone, Copy, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct ActivityBooking { kind: PersonalActivity, minute: i64 }

#[derive(Default, Deserialize, Serialize)]
#[serde(default, deny_unknown_fields)]
struct PlayerDay {
    booking: Option<ActivityBooking>,
    food_milli: i64,
    last_read_notice: Option<i64>,
}
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
    sync::Arc,
};

const START_DATE: &str = "1900-01-01";

// Player selection only chooses a place and identity. Every opening uses the
// same dated world sources, statistical bindings, and population totals.
pub const OPENINGS: &[(&str, &str)] = &[
    ("country_fra", "paris"),
    ("british_isles_1900", "london"),
    ("german_empire", "berlin"),
    ("russian_empire", "st_petersburg"),
    ("qing_empire", "beijing"),
    ("empire_of_japan", "tokyo"),
];

#[derive(Debug, Deserialize)]
pub struct Polity {
    pub id: String,
    pub name_zh: String,
    pub flag_id: String,
    pub valid_from: String,
    pub valid_to: String,
    pub controller_id: String,
    pub relationship: String,
}

impl Polity {
    pub fn runtime_id(&self) -> String {
        format!("state:{}", self.id)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthorityKind {
    Administration,
    Occupation,
    Protection,
    LegacyController,
}

#[derive(Debug, Deserialize)]
pub struct Place {
    pub id: String,
    pub name: String,
    pub parent_country_id: String,
    #[serde(default)]
    pub parent_region_id: String,
    pub lon_lat: Option<[f64; 2]>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RouteMode {
    Road,
    Rail,
    Shipping,
}

#[derive(Debug)]
pub struct Route {
    pub id: String,
    pub mode: RouteMode,
    pub from_place_id: String,
    pub to_place_id: String,
}

#[derive(Debug)]
pub struct OpeningPerson {
    pub id: String,
    pub claim_id: String,
    pub opening_source_id: String,
    pub polity_id: String,
    pub place_id: String,
    birth_year: u16,
}

pub struct WorldBootstrap {
    world: Arc<WorldSources>,
    populations: BTreeMap<String, u64>,
    markets: Arc<MarketInputs>,
    residents: BTreeMap<String, i64>,
    work: Arc<WorkOpening>,
    activities: Arc<OpeningActivities>,
}

pub struct WorldSources {
    polities: BTreeMap<String, Polity>,
    places: BTreeMap<String, Place>,
    routes: BTreeMap<String, Route>,
    place_population_units: BTreeMap<String, String>,
    people: BTreeMap<String, OpeningPerson>,
}

pub struct InitialWorld {
    sources: Arc<WorldSources>,
    player: String,
    identities: BTreeMap<String, formal_character::Identity>,
    clock: GameClock,
    population: Population,
    macro_economy: MacroEconomy,
    character: CharacterOutput,
    ledger: Ledger,
    holdings: BTreeMap<String, BTreeMap<String, PersonalHolding>>,
    next_living_record: u64,
    settled_purchase_requests: BTreeMap<String, BTreeSet<String>>,
    work_opening: Arc<WorkOpening>,
    work: WorkState,
    wages: WageClaims,
    activities: Arc<OpeningActivities>,
    player_day: PlayerDay,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorldSnapshot {
    opening: String,
    clock: ClockSnapshot,
    population: BTreeMap<String, u64>,
    markets: Value,
    #[serde(default)]
    last_arrivals: Vec<Shipment>,
    ledger: Value,
    character: String,
    holdings: BTreeMap<String, BTreeMap<String, PersonalHolding>>,
    next_living_record: u64,
    settled_purchase_requests: BTreeMap<String, BTreeSet<String>>,
    work: WorkState,
    wages: BTreeMap<String, Claim>,
    #[serde(default)]
    player_day: PlayerDay,
}

pub struct Consumption {
    pub record_id: String,
    pub effective_minute: i64,
    pub allocations: Vec<ConsumptionAllocation>,
}

impl InitialWorld {
    pub(crate) fn snapshot(&self) -> Value {
        serde_json::json!({
            "opening": self.player().opening_source_id,
            "clock": self.clock.snapshot(),
            "population": self.population.totals(),
            "markets": typed_map(self.macro_economy.persistent_fields(self.clock)),
            "last_arrivals": self.macro_economy.last_arrivals(),
            "ledger": self.ledger.snapshot(),
            "character": self.character.state,
            "holdings": self.holdings,
            "next_living_record": self.next_living_record,
            "settled_purchase_requests": self.settled_purchase_requests,
            "work": self.work,
            "wages": self.wages.claims(),
            "player_day": self.player_day,
        })
    }

    pub fn goods_held(&self) -> impl Iterator<Item = (&str, i64, bool)> {
        self.holdings.get(&self.player).into_iter().flatten().filter_map(|(good, holding)| {
            let available = holding.available();
            (available > 0).then_some((good.as_str(), available, self.macro_economy.is_consumable(good)))
        })
    }

    pub fn player_market_unit(&self) -> &str {
        self.population.unit_for_person(&self.player).expect("the selected identity has a population claim")
    }

    pub fn jobs(&self) -> impl Iterator<Item = (&Job, usize)> {
        self.work_opening.jobs(&self.player, self.clock.current_day()).filter(|_| self.player_alive()).map(|job| (job, self.work.vacancies(job)))
    }

    pub fn employment(&self) -> Option<(&Job, bool, &str)> {
        let job = self.work.contract(&self.work_opening, &self.player)?;
        Some((job, self.work.booking(&self.player).is_some(), self.work_opening.organization(&job.employer)?))
    }

    pub fn completed_firm_work(&self, firm: &str, day: i64) -> io::Result<Vec<CompletedFirmWork<'_>>> {
        if self.work_opening.organization(firm).is_none() || !(1..=self.clock.current_day()).contains(&day) {
            return Err(invalid("completed company work requires a known firm and completed day"));
        }
        Ok(self.wages.completed_firm_work(firm, day))
    }

    pub fn apply_for_work(&mut self, job: &str) -> io::Result<()> {
        if !self.character.able_to_work { return Err(invalid("当前人物健康状况不适合工作。")); }
        self.work.apply(&self.work_opening, &self.player, job, self.clock.current_day())
    }

    pub fn book_work(&mut self) -> io::Result<()> {
        if !self.character.able_to_work { return Err(invalid("当前人物健康状况不适合工作。")); }
        if self.player_day.booking.is_some() { return Err(invalid("今日已有个人安排。")); }
        self.work.book(&self.work_opening, &self.player, self.clock)
    }

    pub fn player_birth_year(&self) -> u16 {
        self.character.development.as_ref().map_or(self.player().birth_year, |player| player.birth_year())
    }

    pub fn player_alive(&self) -> bool { self.population.unit_for_person(&self.player).is_some() }

    pub fn can_read_opening_language(&self) -> bool {
        self.character.development.as_ref().is_none_or(|player| player.can_read(player.language()))
    }

    pub fn can_read_polity_record(&self, id: &str) -> bool {
        self.character.development.as_ref().is_none_or(|player| {
            self.activities.openings.get(id).is_some_and(|&language| player.can_read(language))
        })
    }

    pub fn can_read_place_record(&self, id: &str) -> bool {
        self.character.development.as_ref().is_none_or(|_| {
            self.sources.places.get(id).is_some_and(|place| {
                let polity = match (place.id.as_str(), place.parent_country_id.as_str()) {
                    ("london", "british_empire") => "british_isles_1900",
                    ("tokyo", "japanese_empire") => "empire_of_japan",
                    (_, polity) => polity,
                };
                self.can_read_polity_record(polity)
            })
        })
    }

    pub fn opening_language(&self) -> Option<Language> {
        self.character.development.as_ref().map(|player| player.language())
    }

    pub fn scheduled_activity(&self) -> Option<PersonalActivity> {
        self.player_day.booking.map(|booking| booking.kind)
    }

    pub fn last_read_notice(&self) -> Option<i64> { self.player_day.last_read_notice }

    pub fn schedule_personal_activity(&mut self, kind: PersonalActivity) -> io::Result<()> {
        let minute = self.clock.snapshot().total_minutes;
        if !self.can_schedule_personal_activity(kind) {
            return Err(invalid("当前无法安排这项活动。"));
        }
        self.player_day.booking = Some(ActivityBooking { kind, minute });
        Ok(())
    }

    pub fn can_schedule_personal_activity(&self, kind: PersonalActivity) -> bool {
        self.opening_language().is_some() && self.player_alive() && self.player_day.booking.is_none()
            && self.work.booking(&self.player).is_none()
            && self.activity_available(kind, self.clock.snapshot().total_minutes)
    }

    pub fn lesson_notice(&self) -> String {
        let start = self.activities.lesson_start_hour;
        let end = start + self.activities.lesson_hours;
        format!("本地识字课堂每日 {start:02}:00 至 {end:02}:00。")
    }

    fn activity_available(&self, kind: PersonalActivity, minute: i64) -> bool {
        let today = minute.rem_euclid(MINUTES_PER_DAY);
        match kind {
            PersonalActivity::Lesson | PersonalActivity::ReadNotice => {
                let reachable = self.activities.openings.contains_key(&self.player().opening_source_id)
                    && today <= self.activities.lesson_start_hour * MINUTES_PER_HOUR;
                reachable && !self.can_read_opening_language()
                    && (kind != PersonalActivity::ReadNotice || self.player_day.last_read_notice.is_none())
            }
            PersonalActivity::Rest => today <= 16 * MINUTES_PER_HOUR,
        }
    }

    pub fn sources(&self) -> &WorldSources {
        &self.sources
    }

    pub fn player(&self) -> &OpeningPerson {
        &self.sources.people[&self.player]
    }

    pub fn clock(&self) -> GameClock {
        self.clock
    }

    pub fn macro_economy(&self) -> &MacroEconomy {
        &self.macro_economy
    }

    pub fn character(&self) -> &wwo_character_core::PersonView {
        &self.character.profile
    }

    pub fn character_for_player(&self) -> wwo_character_core::PersonView {
        let mut profile = self.character.profile.clone();
        profile.social.nationality = self.sources.polities.get(&self.player().opening_source_id).map(|row| row.name_zh.clone());
        if let Some((job, _, organization)) = self.employment() {
            profile.social.occupation = Some(job.employer.clone());
            profile.social.relationships = Some(vec![organization.into()]);
        }
        profile.social.economic_situation = self.balance().map(|account| format!("现金 {}", account.cash));
        profile
    }

    pub fn ledger(&self) -> &Ledger {
        &self.ledger
    }

    pub fn balance(&self) -> Option<Balance<'_>> {
        self.ledger().default_account(&self.player)
    }

    pub fn holding_milli(&self, good: &str) -> i64 {
        self.person_holding_milli(&self.player, good)
    }

    pub fn person_holding_milli(&self, person: &str, good: &str) -> i64 {
        self.holdings.get(person).and_then(|stock| stock.get(good)).map_or(0, PersonalHolding::available)
    }

    /// Existing aggregate stock for residents outside the detailed business system.
    pub fn buy_local_stock(
        &mut self, market: &str, good: &str, quantity_milli: i64, quoted_unit_price: i64, request: &str,
    ) -> io::Result<i64> {
        self.buy_statistical_stock(&self.player.clone(), market, good, quantity_milli, quoted_unit_price, request)
    }

    pub fn buy_quoted_stock(&mut self, market: &str, good: &str, quantity_milli: i64, price: i64) -> io::Result<i64> {
        self.buy_local_stock(market, good, quantity_milli, price, &format!("desktop:{}", self.next_living_record))
    }

    pub fn buy_statistical_stock(
        &mut self, person: &str, market: &str, good: &str, quantity_milli: i64, quoted_unit_price: i64, request: &str,
    ) -> io::Result<i64> {
        if request.is_empty() || request.len() > 128 || !(1..=MAX_AMOUNT).contains(&quantity_milli) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid personal purchase request"));
        }
        if self.settled_purchase_requests.get(person).is_some_and(|requests| requests.contains(request)) {
            return Err(invalid("purchase request was already settled"));
        }
        if let Some(holding) = self.holdings.get(person).and_then(|goods| goods.get(good)) {
            holding.check_purchase(quantity_milli)?;
        }
        let available = self.ledger.default_account(person).ok_or_else(|| invalid("person lacks a cash account"))?.available;
        let resident_unit = self.population.unit_for_person(person)
            .ok_or_else(|| invalid("person has no formal population claim"))?;
        let day = u32::try_from(self.clock.current_day()).map_err(|_| invalid("unsupported formal character date"))?;
        let minute = self.clock.snapshot().total_minutes;
        let record_id = format!("personal_life:{}", self.next_living_record);
        let (amount, viewed_character) = self.macro_economy.sell_existing_stock(
            resident_unit, market, good, quantity_milli, quoted_unit_price, |amount| {
                let character = formal_character::assess_purchase(
                    person, &self.identities, day, &self.character.state, market, amount as u64, available as u64,
                ).map_err(io::Error::other)?;
                let player_view = if person == self.player { character } else {
                    formal_character::opening_profile(&self.player, &self.identities, day, &character.state)
                        .map_err(io::Error::other)?
                };
                self.ledger.buy_from_market(person, market, &record_id, amount, minute)?;
                Ok(player_view)
            },
        )?;
        self.character = viewed_character;
        self.holdings.entry(person.to_owned()).or_default().entry(good.to_owned()).or_default()
            .record_purchase(record_id, quantity_milli);
        self.next_living_record += 1;
        self.settled_purchase_requests.entry(person.to_owned()).or_default().insert(request.to_owned());
        Ok(amount)
    }

    /// Consume purchased statistical stock in purchase order and return the
    /// exact allocations needed by the personal living record.
    pub fn consume_purchased_stock(&mut self, good: &str, quantity_milli: i64) -> io::Result<Consumption> {
        self.consume_statistical_stock(&self.player.clone(), good, quantity_milli)
    }

    pub fn consume_statistical_stock(&mut self, person: &str, good: &str, quantity_milli: i64) -> io::Result<Consumption> {
        if !self.macro_economy.is_consumable(good) || self.population.unit_for_person(person).is_none() {
            return Err(invalid("person or commodity is not eligible for consumption"));
        }
        let food = person == self.player && self.opening_language().is_some() && self.macro_economy.is_food(good);
        let allocations = self.holdings.get_mut(person).and_then(|goods| goods.get_mut(good))
            .ok_or_else(|| invalid("person has no stock of this commodity"))?
            .consume(quantity_milli)?;
        let record_id = format!("personal_life:{}", self.next_living_record);
        self.next_living_record += 1;
        if food {
            self.player_day.food_milli = self.player_day.food_milli.saturating_add(quantity_milli)
                .min(self.activities.meal_milli_for_recovery);
        }
        Ok(Consumption { record_id, effective_minute: self.clock.snapshot().total_minutes, allocations })
    }

    /// Advance the migrated day settlements. The caller supplies the
    /// populations whose consumption belongs to the regional domain.
    pub fn advance_migrated_domains(
        &mut self,
        minutes: i64,
        managed_population: &BTreeMap<String, u64>,
    ) -> io::Result<()> {
        let mut target = self.clock;
        target.advance_minutes(minutes)?;
        u32::try_from(target.current_day()).map_err(|_| invalid("unsupported formal character date"))?;
        if target.current_day() != self.clock.current_day() {
            self.macro_economy.check_responsibility(self.population.totals(), managed_population)?;
        }
        let through = target.snapshot().total_minutes;
        while let Some(minute) = next_day_boundary(self.clock).filter(|&minute| minute <= through) {
            let mut boundary = self.clock;
            boundary.advance_minutes(minute - boundary.snapshot().total_minutes)?;
            let day = u32::try_from(boundary.current_day()).map_err(|_| invalid("unsupported formal character date"))?;
            let work = self.work.booked_workers().map(|person| {
                let job = self.work.contract(&self.work_opening, person).expect("booking has a live contract");
                (person.clone(), job.id.clone())
            }).collect::<BTreeMap<_, _>>();
            let period = self.activities.work_injury_interval;
            let injury = (self.opening_language().is_some() && work.contains_key(&self.player)
                && day.wrapping_mul(17).wrapping_add(9) % period == 0)
                .then_some((self.activities.work_injury_damage, self.activities.work_injury_permanent_loss));
            let booking = self.scheduled_activity();
            let lesson = if booking == Some(PersonalActivity::Lesson) {
                self.opening_language().map(|language| (language, self.activities.lesson_effort,
                    format!("reading-room:{}:{day}", self.player().place_id)))
            } else { None };
            let activity = DayActivity {
                work, lesson, injury,
                rest: booking == Some(PersonalActivity::Rest),
                nutrition: (self.player_day.food_milli >= self.activities.meal_milli_for_recovery).then_some(1000),
            };
            let character = formal_character::advance_opening_day(
                &self.player, &self.identities, day, &self.character.state, activity,
            ).map_err(io::Error::other)?;
            let mut population_after_deaths = None;
            if !character.deaths.is_empty() {
                let mut population = self.population.clone();
                for death in &character.deaths { population.record_death(&death.person_id)?; }
                self.macro_economy.check_responsibility(population.totals(), managed_population)?;
                population_after_deaths = Some(population);
            }
            for worker in self.work.booked_workers() {
                let job = self.work.contract(&self.work_opening, worker).expect("booking has a live contract");
                self.wages.record_shift(worker, job, i64::from(day), &self.ledger)?;
            }
            self.wages.settle_due(&mut self.ledger, boundary, |_| false)?;
            let population = population_after_deaths.as_ref().unwrap_or(&self.population);
            self.macro_economy.settle(boundary, population.totals(), managed_population)?;
            if let Some(population) = population_after_deaths { self.population = population; }
            for death in &character.deaths {
                self.identities.get_mut(&death.person_id).expect("known person").record_death();
                self.work.record_death(&death.person_id);
            }
            self.work.complete();
            self.character = character;
            if booking == Some(PersonalActivity::ReadNotice) && self.player_alive() {
                self.player_day.last_read_notice = Some(minute);
            }
            self.player_day.booking = None;
            self.player_day.food_milli = 0;
            self.clock = boundary;
            self.work.book_automatic(&self.work_opening, self.clock, |person| self.population.unit_for_person(person).is_some());
        }
        self.clock = target;
        Ok(())
    }

    pub fn population_units(&self) -> &BTreeMap<String, u64> {
        self.population.totals()
    }

    pub fn person(&self, person: &str) -> Option<&OpeningPerson> {
        self.sources.people.get(person)
    }

    pub fn person_profile(&self, person: &str) -> io::Result<wwo_character_core::PersonView> {
        formal_character::opening_profile(person, &self.identities, self.character.day, &self.character.state)
            .map(|character| character.profile).map_err(io::Error::other)
    }

    pub fn background_population(&self, unit: &str) -> Option<u64> {
        self.population.background(unit)
    }

    pub fn transfer_unmanaged_population(
        &mut self, source: &str, destination: &str, amount: u64, source_managed_background: u64,
    ) -> io::Result<()> {
        self.population.transfer_unmanaged(source, destination, amount, source_managed_background)
    }
}

impl WorldSources {
    pub fn polities(&self) -> &BTreeMap<String, Polity> {
        &self.polities
    }

    pub fn authority(&self, subject: &str) -> Option<(&Polity, AuthorityKind)> {
        let subject = self.polities.get(subject)?;
        let controller = self.polities.get(&subject.controller_id)?;
        let kind = match subject.relationship.as_str() {
            "administered_territory" => AuthorityKind::Administration,
            "military_occupation" => AuthorityKind::Occupation,
            "protected_state" | "protected_territory" => AuthorityKind::Protection,
            _ => AuthorityKind::LegacyController,
        };
        Some((controller, kind))
    }

    pub fn places(&self) -> &BTreeMap<String, Place> {
        &self.places
    }

    pub fn routes(&self) -> &BTreeMap<String, Route> {
        &self.routes
    }

    pub fn population_unit_at(&self, place_id: &str) -> Option<&str> {
        self.place_population_units.get(place_id).map(String::as_str)
    }
}

impl WorldBootstrap {
    pub fn sources(&self) -> &WorldSources {
        &self.world
    }

    pub(crate) fn restore_markets(
        &self,
        state: &Value,
        clock: GameClock,
        population: &BTreeMap<String, u64>,
    ) -> io::Result<MacroEconomy> {
        if population.keys().ne(self.populations.keys())
            || population.values().sum::<u64>() != self.populations.values().sum::<u64>()
        {
            return Err(invalid("saved population roster or total differs from the formal world"));
        }
        MacroEconomy::restore(Arc::clone(&self.markets), population, state, clock)
    }

    pub fn load() -> io::Result<Self> {
        let polities = load_polities()?;
        let (populations, countries) = load_countries()?;
        let polity_units = load_population_bindings(&polities, &populations)?;
        let markets = MarketInputs::load(countries)?;
        let opening_cash = load_opening_cash()?;
        let (places, routes) = load_map()?;
        let place_population_units = places.iter().filter_map(|(id, place)| {
            // Legacy catalogue parents describe map ownership. Only these
            // explicit capital bindings differ for population accounting.
            let source = match (place.id.as_str(), place.parent_country_id.as_str()) {
                ("london", "british_empire") => "british_isles_1900",
                ("tokyo", "japanese_empire") => "empire_of_japan",
                _ => &place.parent_country_id,
            };
            polity_units.get(source).map(|unit| (id.clone(), unit.clone()))
        }).collect();
        let mut world = WorldSources { polities, places, routes, place_population_units, people: BTreeMap::new() };
        let mut residents = BTreeMap::new();
        for &(source, place) in OPENINGS {
            let id = format!("person:formal_generated_{source}_0001");
            let claim = format!("formal_population_claim:{source}:0001");
            world.add_opening_person(source, format!("place:{place}"), id.clone(), claim)?;
            residents.insert(id, opening_cash);
        }
        for resident in load_regional_residents()? {
            world.add_opening_person("country_fra", resident.place_id, resident.person_id.clone(), resident.claim_id)?;
            residents.insert(resident.person_id, resident.opening_cash);
        }
        Ok(Self {
            world: Arc::new(world),
            populations,
            markets: Arc::new(markets),
            residents,
            work: Arc::new(WorkOpening::load()?),
            activities: Arc::new(load_opening_activities()?),
        })
    }

    pub fn opening_language(&self, source: &str) -> Option<Language> {
        self.activities.openings.get(source).copied()
    }

    pub fn opening_cash(&self, source: &str, family: wwo_character_core::Family) -> Option<i64> {
        self.residents.get(&format!("person:formal_generated_{source}_0001")).map(|&cash| family.opening_cash(cash))
    }

    pub fn create(&self, source_id: &str) -> io::Result<InitialWorld> {
        self.create_opening(source_id, None)
    }

    pub fn create_with_prologue(&self, source_id: &str, prologue: Prologue) -> io::Result<InitialWorld> {
        self.create_opening(source_id, Some(prologue))
    }

    fn create_opening(&self, source_id: &str, prologue: Option<Prologue>) -> io::Result<InitialWorld> {
        if !OPENINGS.iter().any(|(source, _)| *source == source_id) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "unknown formal opening"));
        }
        let player = format!("person:formal_generated_{source_id}_0001");
        let development = prologue.map(|opening| {
            opening.build(self.opening_language(source_id).expect("configured opening"))
        }).transpose().map_err(io::Error::other)?;
        let mut ledger = Ledger::initialize_people(self.residents.iter().map(|(person, cash)| {
            let cash = prologue.filter(|_| person == &player).map_or(*cash, |opening| opening.family.opening_cash(*cash));
            (person.as_str(), cash)
        }))?;
        self.work.open_accounts(&mut ledger)?;
        let mut population = Population::initialize(self.populations.clone());
        let mut identities = BTreeMap::new();
        for person in self.world.people.values() {
            population.claim(&person.id, &person.opening_source_id)?;
            let year = development.as_ref().filter(|_| person.id == player).map_or(person.birth_year, |player| player.birth_year());
            let identity = formal_character::opening_identity(year).map_err(io::Error::other)?;
            identities.insert(person.id.clone(), identity);
        }
        let character = match development {
            Some(development) => formal_character::opening_with_prologue(&player, &identities, development),
            None => formal_character::opening_profile(&player, &identities, 0, ""),
        }.map_err(io::Error::other)?;
        let mut work = WorkState::default();
        work.book_automatic(&self.work, GameClock::default(), |_| true);
        Ok(InitialWorld {
            sources: Arc::clone(&self.world),
            clock: GameClock::default(),
            player,
            identities,
            population,
            macro_economy: MacroEconomy::initialize(Arc::clone(&self.markets), &self.populations),
            character,
            ledger,
            holdings: BTreeMap::new(),
            next_living_record: 1,
            settled_purchase_requests: BTreeMap::new(),
            work_opening: Arc::clone(&self.work),
            work,
            wages: WageClaims::initialize(),
            activities: Arc::clone(&self.activities),
            player_day: PlayerDay::default(),
        })
    }

    pub(crate) fn restore_native(&self, saved: WorldSnapshot) -> io::Result<InitialWorld> {
        let mut world = self.create(&saved.opening)?;
        let clock = GameClock::restore(saved.clock)?;
        let day = u32::try_from(clock.current_day()).map_err(|_| invalid("unsupported formal date"))?;
        if saved.character.is_empty() || saved.next_living_record == 0 || saved.next_living_record > MAX_AMOUNT as u64
            || saved.population.values().any(|&total| total > MAX_POPULATION)
            || !saved.work.validate(&self.work, clock)
        { return Err(invalid("invalid formal save state")); }
        let deaths = formal_character::restore_native_identities(&world.player, &mut world.identities, day, &saved.character)
            .map_err(io::Error::other)?;
        let dead = deaths.iter().map(|notice| notice.person_id.as_str()).collect::<BTreeSet<_>>();
        if saved.population.keys().ne(self.populations.keys())
            || saved.population.values().sum::<u64>().checked_add(deaths.len() as u64)
                != Some(self.populations.values().sum::<u64>())
            || dead.iter().any(|id| saved.work.has_contract(id))
        { return Err(invalid("formal population or employment disagrees with mortality")); }
        world.macro_economy = MacroEconomy::restore(Arc::clone(&self.markets), &saved.population, &saved.markets, clock)?;
        world.macro_economy.restore_arrivals(saved.last_arrivals)?;
        world.population = Population::initialize(saved.population);
        for person in world.sources.people.values().filter(|person| !dead.contains(person.id.as_str())) {
            world.population.claim(&person.id, &person.opening_source_id)?;
        }
        let ledger = Ledger::restore(&saved.ledger, true)?;
        if ledger.last_minute() > saved.clock.total_minutes || world.identities.keys().any(|id| ledger.default_account(id).is_none()) {
            return Err(invalid("ledger and world timelines differ or personal accounts are missing"));
        }
        let mut lot_ids = BTreeSet::new();
        for (person, holdings) in &saved.holdings {
            if !world.identities.contains_key(person) || holdings.iter().any(|(good, holding)| {
                !world.macro_economy.purchasable(good) || !holding.validate(|record| {
                    record.strip_prefix("personal_life:").and_then(|id| id.parse::<u64>().ok())
                        .is_some_and(|id| id > 0 && id < saved.next_living_record && lot_ids.insert(id))
                        && ledger.has_purchase(person, record)
                })
            }) { return Err(invalid("invalid personal holdings or purchase lots")); }
        }
        if saved.settled_purchase_requests.iter().any(|(person, rows)| {
            !world.identities.contains_key(person) || rows.iter().any(|row| row.is_empty() || row.len() > 128)
        }) { return Err(invalid("invalid formal purchase requests")); }
        world.clock = clock;
        world.character = formal_character::opening_profile(&world.player, &world.identities, day, &saved.character)
            .map_err(io::Error::other)?;
        world.wages = WageClaims::restore_shifts(saved.wages, &self.work, &ledger, clock)?;
        world.ledger = ledger;
        world.holdings = saved.holdings;
        world.next_living_record = saved.next_living_record;
        world.settled_purchase_requests = saved.settled_purchase_requests;
        world.work = saved.work;
        world.player_day = saved.player_day;
        let minute = clock.snapshot().total_minutes;
        let invalid_booking = world.player_day.booking.is_some_and(|booking| {
            !world.player_alive() || world.work.booking(&world.player).is_some()
                || !(clock.current_day() * MINUTES_PER_DAY..=minute).contains(&booking.minute)
                || !world.activity_available(booking.kind, booking.minute)
        });
        if world.opening_language().is_some_and(|language| self.opening_language(&saved.opening) != Some(language))
            || !(0..=world.activities.meal_milli_for_recovery).contains(&world.player_day.food_milli)
            || invalid_booking
            || world.player_day.last_read_notice.is_some_and(|notice| {
                !(MINUTES_PER_DAY..=minute).contains(&notice) || notice % MINUTES_PER_DAY != 0
            })
            || world.opening_language().is_none() && (world.player_day.booking.is_some()
                || world.player_day.food_milli > 0 || world.player_day.last_read_notice.is_some())
        { return Err(invalid("invalid saved personal activity")); }
        Ok(world)
    }
}

impl WorldSources {
    fn add_opening_person(&mut self, source: &str, place_id: String, id: String, claim_id: String) -> io::Result<()> {
        let polity = self.polities.get(source).ok_or_else(|| invalid("opening polity is inactive"))?;
        if self.population_unit_at(&place_id) != Some(source) {
            return Err(invalid("opening place has no residents in its formal polity"));
        }
        if self.people.contains_key(&id) || self.people.values().any(|person| person.claim_id == claim_id) {
            return Err(invalid("duplicate opening person or population claim"));
        }
        self.people.insert(id.clone(), OpeningPerson {
            id, claim_id, opening_source_id: source.to_owned(), polity_id: polity.runtime_id(), place_id,
            birth_year: 1870, // Generated assumption from the original opening.
        });
        Ok(())
    }
}

#[derive(Deserialize)]
struct RegionalResident {
    person_id: String,
    claim_id: String,
    place_id: String,
    opening_cash: i64,
}

fn load_regional_residents() -> io::Result<Vec<RegionalResident>> {
    read_list(include_bytes!("../../../data/formal/paris_employment_opening_r1.json"), "opening_residents")
}

fn load_opening_activities() -> io::Result<OpeningActivities> {
    let rules: OpeningActivities = serde_json::from_str(include_str!("../../../data/character/opening_activities.json"))?;
    if rules.basis != ASSUMPTION || !(1..=1000).contains(&rules.lesson_effort)
        || !(0..24).contains(&rules.lesson_start_hour) || !(1..=24 - rules.lesson_start_hour).contains(&rules.lesson_hours)
        || rules.work_injury_interval < 2 || rules.work_injury_damage > 1000 || rules.work_injury_permanent_loss > 1000
        || !(1..=MAX_AMOUNT).contains(&rules.meal_milli_for_recovery)
        || rules.openings.len() != OPENINGS.len() || OPENINGS.iter().any(|(id, _)| !rules.openings.contains_key(*id))
    { return Err(invalid("invalid opening personal activity configuration")); }
    Ok(rules)
}

fn load_opening_cash() -> io::Result<i64> {
    #[derive(Deserialize)]
    struct Policy {
        policy_id: String,
        basis: String,
        denomination: String,
        opening_cash: i64,
    }
    let policy: Policy = serde_json::from_slice(include_bytes!("../../../data/formal/player_livelihood_r1.json"))?;
    if policy.policy_id != "player_livelihood_r1" || policy.basis != "GENERATED_SIMULATION_ASSUMPTION"
        || policy.denomination != CURRENCY || !(1..=MAX_AMOUNT).contains(&policy.opening_cash)
    {
        return Err(invalid("invalid formal opening livelihood policy"));
    }
    Ok(policy.opening_cash)
}

fn load_polities() -> io::Result<BTreeMap<String, Polity>> {
    #[derive(Deserialize)]
    struct Evidence {
        schema_version: u32,
        unit_count: usize,
        units: Vec<Polity>,
    }
    let source: Evidence = serde_json::from_slice(include_bytes!(
        "../../../data/world_map/historical/political_units_1900.json"
    ))?;
    if source.schema_version != 1 || source.unit_count != source.units.len() {
        return Err(invalid("invalid historical political evidence header"));
    }
    let mut ids = BTreeSet::new();
    let mut polities = BTreeMap::new();
    for polity in source.units {
        if !local_id(&polity.id) || !ids.insert(polity.id.clone())
            || !date(&polity.valid_from) || !date(&polity.valid_to) || polity.valid_from > polity.valid_to
        {
            return Err(invalid(format!("invalid historical political identity {}", polity.id)));
        }
        if polity.valid_from.as_str() <= START_DATE && START_DATE <= polity.valid_to.as_str() {
            polities.insert(polity.id.clone(), polity);
        }
    }
    if polities.is_empty() || polities.values().any(|p| {
        !p.controller_id.is_empty() && !polities.contains_key(&p.controller_id)
    }) {
        return Err(invalid("missing historical authority at the formal opening date"));
    }
    Ok(polities)
}

type PopulationTotals = BTreeMap<String, u64>;
type CountryCatalog = BTreeMap<String, CountryInputs>;

fn load_countries() -> io::Result<(PopulationTotals, CountryCatalog)> {
    #[derive(Deserialize)]
    struct CountryTable {
        schema_id: String,
        field_order: Vec<String>,
        rows: Vec<Vec<Value>>,
    }
    let table: CountryTable = serde_json::from_slice(include_bytes!(
        "../../../data/alpha/historical_world_economy_1900/countries_compact.json"
    ))?;
    if table.schema_id != "historical_world_economy_1900_compact_country_table_v1" {
        return Err(invalid("invalid historical economic country table"));
    }
    let unit = column(&table.field_order, "entity_id")?;
    let population = columns(&table.field_order, ["population_lower", "population_value", "population_upper"])?;
    let production = columns(&table.field_order, [
        "gdp_pc_value", "overall_confidence_bp", "agriculture_capacity_index",
        "industrial_capacity_index", "coal_index", "iron_ore_index", "copper_index",
        "petroleum_index", "timber_index",
    ])?;
    let mut totals = BTreeMap::new();
    let mut countries = BTreeMap::new();
    let mut total = 0;
    for row in table.rows {
        if row.len() != table.field_order.len() {
            return Err(invalid("invalid country table row length"));
        }
        let id = row[unit].as_str().filter(|id| local_id(id))
            .ok_or_else(|| invalid("invalid population unit"))?;
        let [min, count, max] = unsigned_columns(&row, population)?;
        if min > count || count > max || max > MAX_POPULATION
            || count > MAX_POPULATION - total || totals.insert(id.to_owned(), count).is_some()
        {
            return Err(invalid(format!("invalid population record for {id}")));
        }
        total += count;
        let [income, confidence, agriculture, industry, coal, iron, copper, petroleum, timber] =
            unsigned_columns(&row, production)?;
        countries.insert(id.to_owned(), CountryInputs {
            income, confidence, agriculture, industry, minerals: [coal, iron, copper, petroleum, timber],
        });
    }
    if totals.is_empty() {
        return Err(invalid("no formal population units"));
    }
    Ok((totals, countries))
}

pub(crate) fn column(fields: &[String], name: &str) -> io::Result<usize> {
    fields.iter().position(|key| key == name)
        .ok_or_else(|| invalid(format!("missing table column {name}")))
}

pub(crate) fn columns<const N: usize>(fields: &[String], names: [&str; N]) -> io::Result<[usize; N]> {
    let mut indexes = [0; N];
    for (index, name) in indexes.iter_mut().zip(names) {
        *index = column(fields, name)?;
    }
    Ok(indexes)
}

fn unsigned_columns<const N: usize>(row: &[Value], fields: [usize; N]) -> io::Result<[u64; N]> {
    let mut values = [0; N];
    for (value, index) in values.iter_mut().zip(fields) {
        *value = row[index].as_u64().ok_or_else(|| invalid("invalid unsigned country source number"))?;
    }
    Ok(values)
}

fn load_population_bindings(
    polities: &BTreeMap<String, Polity>,
    populations: &BTreeMap<String, u64>,
) -> io::Result<BTreeMap<String, String>> {
    #[derive(Deserialize)]
    struct Crosswalk {
        schema_id: String,
        records: Vec<Binding>,
    }
    #[derive(Deserialize)]
    struct Binding {
        economy_entity_id: String,
        polity_ids: Vec<String>,
    }
    let crosswalk: Crosswalk = serde_json::from_slice(include_bytes!(
        "../../../data/world_map/historical/major_economy_polity_crosswalk_1900.json"
    ))?;
    if crosswalk.schema_id != "major_economy_polity_crosswalk_1900_v1" {
        return Err(invalid("invalid historical population crosswalk"));
    }
    let mut result: BTreeMap<_, _> = populations.keys()
        .filter(|unit| polities.contains_key(*unit))
        .map(|unit| (unit.clone(), unit.clone()))
        .collect();
    for binding in crosswalk.records {
        if !populations.contains_key(&binding.economy_entity_id) {
            return Err(invalid("population crosswalk references an unknown statistical unit"));
        }
        for polity in binding.polity_ids {
            if !polities.contains_key(&polity) {
                return Err(invalid(format!("population crosswalk references inactive polity {polity}")));
            }
            if let Some(old) = result.insert(polity.clone(), binding.economy_entity_id.clone()) {
                if old != binding.economy_entity_id {
                    return Err(invalid(format!("ambiguous population crosswalk for {polity}")));
                }
            }
        }
    }
    if populations.keys().any(|unit| !result.values().any(|bound| bound == unit)) {
        return Err(invalid("formal statistical unit has no political binding"));
    }
    Ok(result)
}

fn load_map() -> io::Result<(BTreeMap<String, Place>, BTreeMap<String, Route>)> {
    #[derive(Deserialize)]
    struct Country { id: String }
    #[derive(Deserialize)]
    struct Port {
        #[serde(flatten)]
        place: Place,
        city_id: String,
    }
    let countries = read_list::<Country>(include_bytes!("../../../data/world_map/countries.json"), "countries")?;
    let countries: BTreeSet<_> = countries.into_iter().map(|country| country.id).collect();
    let regions = read_list::<Place>(include_bytes!("../../../data/world_map/regions.json"), "regions")?;
    let cities = read_list::<Place>(include_bytes!("../../../data/world_map/cities.json"), "cities")?;
    let ports = read_list::<Port>(include_bytes!("../../../data/world_map/ports.json"), "ports")?;
    let region_ids: BTreeSet<_> = regions.iter().map(|place| place.id.clone()).collect();
    let city_ids: BTreeSet<_> = cities.iter().map(|place| place.id.as_str()).collect();
    let port_ids: BTreeSet<_> = ports.iter().map(|port| port.place.id.as_str()).collect();
    if ports.iter().any(|port| !city_ids.contains(port.city_id.as_str())) {
        return Err(invalid("formal port references an unknown city"));
    }
    let mut routes = BTreeMap::new();
    for (mode, bytes, list, endpoints) in [
        (RouteMode::Road, &include_bytes!("../../../data/world_map/road_segments.json")[..], "segments", &city_ids),
        (RouteMode::Rail, &include_bytes!("../../../data/world_map/rail_segments.json")[..], "segments", &city_ids),
        (RouteMode::Shipping, &include_bytes!("../../../data/world_map/shipping_routes.json")[..], "routes", &port_ids),
    ] {
        load_routes(&mut routes, mode, bytes, list, endpoints)?;
    }
    let mut places = BTreeMap::new();
    for place in regions.into_iter().chain(cities).chain(ports.into_iter().map(|port| port.place)) {
        if !local_id(&place.id) || !countries.contains(&place.parent_country_id)
            || (!place.parent_region_id.is_empty() && !region_ids.contains(place.parent_region_id.as_str()))
            || place.lon_lat.is_some_and(|[lon, lat]| !(-180.0..=180.0).contains(&lon) || !(-90.0..=90.0).contains(&lat))
        {
            return Err(invalid(format!("invalid formal place {}", place.id)));
        }
        let id = format!("place:{}", place.id);
        if places.insert(id.clone(), place).is_some() {
            return Err(invalid(format!("duplicate formal place {id}")));
        }
    }
    Ok((places, routes))
}

fn load_routes(
    routes: &mut BTreeMap<String, Route>,
    mode: RouteMode,
    bytes: &[u8],
    list: &str,
    endpoints: &BTreeSet<&str>,
) -> io::Result<()> {
    #[derive(Deserialize)]
    struct Link {
        id: String,
        #[serde(rename = "type")]
        kind: String,
        #[serde(alias = "from_city_id", alias = "from_port_id")]
        from: String,
        #[serde(alias = "to_city_id", alias = "to_port_id")]
        to: String,
    }
    let kind = match mode {
        RouteMode::Road => "road",
        RouteMode::Rail => "rail",
        RouteMode::Shipping => "shipping",
    };
    for link in read_list::<Link>(bytes, list)? {
        if !local_id(&link.id) || link.kind != kind || link.from == link.to
            || !endpoints.contains(link.from.as_str()) || !endpoints.contains(link.to.as_str())
            || routes.contains_key(&link.id)
        {
            return Err(invalid(format!("invalid formal route {}", link.id)));
        }
        routes.insert(link.id.clone(), Route {
            id: link.id,
            mode,
            from_place_id: format!("place:{}", link.from),
            to_place_id: format!("place:{}", link.to),
        });
    }
    Ok(())
}

fn read_list<T: DeserializeOwned>(bytes: &[u8], field: &str) -> io::Result<Vec<T>> {
    let mut document: Value = serde_json::from_slice(bytes)?;
    Ok(serde_json::from_value(document[field].take())?)
}

pub(crate) fn local_id(value: &str) -> bool {
    !value.is_empty() && value.bytes()
        .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'_' | b'-'))
}

fn date(value: &str) -> bool {
    let mut parts = value.split('-');
    let year = parts.next().filter(|s| s.len() == 4).and_then(|s| s.parse::<i32>().ok());
    let month = parts.next().filter(|s| s.len() == 2).and_then(|s| s.parse::<u32>().ok());
    let day = parts.next().filter(|s| s.len() == 2).and_then(|s| s.parse::<u32>().ok());
    matches!((year, month, day, parts.next()), (Some(y), Some(m), Some(d), None)
        if y > 0 && (1..=crate::calendar::month_length(y, m)).contains(&d))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::formal_clock::MINUTES_PER_DAY;

    #[test]
    fn all_six_openings_select_a_person_in_the_same_world_sources() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let france = bootstrap.create("country_fra").unwrap();
        assert_eq!(france.sources.polities().len(), 146);
        assert_eq!(france.population_units().len(), 50);
        assert_eq!(france.population_units().values().sum::<u64>(), 1_411_020_000);
        for (id, city, flag, population) in [
            ("country_fra", "paris", "france_tricolour_1794", 40_700_000),
            ("british_isles_1900", "london", "uk_union_1801", 41_500_000),
            ("german_empire", "berlin", "german_empire_1867", 56_400_000),
            ("russian_empire", "st_petersburg", "russia_1896", 136_000_000),
            ("qing_empire", "beijing", "qing_1889", 400_000_000),
            ("empire_of_japan", "tokyo", "japan_1870", 43_800_000),
        ] {
            let world = bootstrap.create(id).unwrap();
            let place = format!("place:{city}");
            assert_eq!(world.clock(), GameClock::default());
            assert!(Arc::ptr_eq(&france.sources, &world.sources));
            assert_eq!(world.population_units(), france.population_units());
            assert_eq!(world.player().id, format!("person:formal_generated_{id}_0001"));
            assert_eq!(world.player().claim_id, format!("formal_population_claim:{id}:0001"));
            assert_eq!(world.player().polity_id, format!("state:{id}"));
            assert_eq!(world.player().place_id, place);
            assert_eq!(world.character().id, world.player().id);
            assert_eq!(world.character().age_years, 30);
            assert!(world.sources.places()[&place].lon_lat.is_some());
            assert_eq!(world.sources.polities()[id].flag_id, flag);
            assert_eq!(world.background_population(id), Some(population - 1 - u64::from(id == "country_fra")));
            assert_eq!(world.ledger().snapshot(), france.ledger().snapshot());
            let resident = "person:formal_generated_country_fra_0002";
            assert_eq!(world.person(resident).unwrap().place_id, "place:paris");
            assert_eq!(world.ledger().default_account(resident).unwrap().cash, 0);
            assert_eq!(world.person_profile(resident).unwrap().age_years, 30);
        }
        assert!(bootstrap.create("british_empire").is_err());
        assert!(bootstrap.create("japanese_empire").is_err());
    }

    #[test]
    fn historic_authority_and_map_parents_are_independent_of_population_bindings() {
        let world = WorldBootstrap::load().unwrap().create("country_fra").unwrap();
        let sources = &world.sources;
        let (controller, _) = sources.authority("taiwan_under_japan").unwrap();
        assert_eq!(controller.id, "empire_of_japan");
        assert_eq!(sources.places()["place:london"].parent_country_id, "british_empire");
        assert_eq!(sources.population_unit_at("place:london"), Some("british_isles_1900"));
        assert_eq!(sources.population_unit_at("place:kolkata"), None);
        assert_eq!(sources.places()["place:tokyo"].parent_country_id, "japanese_empire");
        assert_eq!(sources.population_unit_at("place:tokyo"), Some("empire_of_japan"));
        for (id, mode) in [
            ("road_lyon_strasbourg", RouteMode::Road),
            ("rail_bordeaux_toulouse", RouteMode::Rail),
            ("shipping_mediterranean", RouteMode::Shipping),
        ] {
            let route = &sources.routes()[id];
            assert_eq!(route.mode, mode);
            assert!(sources.places().contains_key(&route.from_place_id));
            assert!(sources.places().contains_key(&route.to_place_id));
        }
    }

    #[test]
    fn macro_days_settle_other_countries_and_deliver_trade_using_the_same_clock() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut france = bootstrap.create("country_fra").unwrap();
        let mut japan = bootstrap.create("empire_of_japan").unwrap();
        let managed = BTreeMap::new();
        let grain_before = france.macro_economy().markets()["qing_empire"].commodities["potatoes"].inventory;
        france.advance_migrated_domains(MINUTES_PER_DAY - 1, &managed).unwrap();
        assert_eq!(france.macro_economy().last_settlement_hour(), 0);
        france.advance_migrated_domains(1, &managed).unwrap();
        assert_eq!(france.macro_economy().last_settlement_hour(), 24);
        assert_eq!(france.macro_economy().markets().len(), 50);
        assert!(france.macro_economy().markets().values().all(|market| market.commodities["potatoes"].demanded > 0.0));
        assert!(france.macro_economy().markets()["qing_empire"].commodities["potatoes"].inventory < grain_before);
        france.advance_migrated_domains(MINUTES_PER_DAY * 89, &managed).unwrap();
        japan.advance_migrated_domains(MINUTES_PER_DAY * 90, &managed).unwrap();
        assert_eq!(japan.character.day, 90);
        assert_eq!(france.character.state, japan.character.state);
        let all_markets = france.macro_economy().markets();
        assert_eq!(france.clock(), japan.clock());
        assert!(all_markets.iter().all(|(id, market)| market.commodities == japan.macro_economy().markets()[id].commodities));
        assert!(france.macro_economy().shipments().iter().all(|shipment| shipment.arrival_hour > 90 * 24));
        assert!(all_markets.values().any(|market| market.trade_balance_centimes > 0));
        assert_eq!(all_markets.values().map(|market| market.trade_balance_centimes).sum::<i64>(), 0);
    }

    #[test]
    fn each_opening_pays_for_aggregate_stock_and_learns_only_once() {
        let bootstrap = WorldBootstrap::load().unwrap();
        for &(source, _) in OPENINGS {
            let mut world = bootstrap.create(source).unwrap();
            let market = format!("market:legacy_aggregate:{source}");
            let good = "potatoes";
            let current = |world: &InitialWorld| world.macro_economy().markets()[source].commodities[good];
            let before = current(&world);
            assert_eq!(world.balance().unwrap().cash, 2500);
            assert!(world.buy_local_stock("market:legacy_aggregate:ottoman_empire", good, 1000, before.price_centimes, "buy-1").is_err());
            assert!(world.buy_local_stock(&market, good, 1000, before.price_centimes + 1, "buy-1").is_err());
            assert!(world.buy_local_stock(&market, "electricity_service", 1000, 75, "buy-1").is_err());
            assert!(world.buy_local_stock(&market, good, MAX_AMOUNT, before.price_centimes, "buy-1").is_err());
            assert_eq!(current(&world), before);
            assert!(world.character().history.is_empty());
            let cost = world.buy_local_stock(&market, good, 1000, before.price_centimes, "buy-1").unwrap();
            assert_eq!(cost, before.price_centimes);
            assert_eq!(world.holding_milli(good), 1000);
            assert_eq!(current(&world).inventory, before.inventory - 1.0);
            assert_eq!(world.balance().unwrap().available, 2500 - cost);
            assert_eq!(world.ledger.default_account(&market).unwrap().cash, cost);
            assert!(world.buy_local_stock(&market, good, 1000, before.price_centimes, "buy-1").is_err());
            assert_eq!(world.balance().unwrap().cash, 2500 - cost);
            world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
            assert_eq!(world.character().history, ["完成正式市场下单"]);
            assert_eq!(world.character.day, 1);
            let saved_ledger = world.ledger().snapshot();
            let restored = Ledger::restore(&saved_ledger, false).unwrap();
            assert_eq!(restored.default_account(&world.player().id).unwrap().cash, 2500 - cost);
            assert_eq!(restored.default_account(&market).unwrap().cash, cost);
            assert_eq!(restored.snapshot(), saved_ledger);
        }
    }

    #[test]
    fn anonymous_transfer_preserves_named_claims_and_changes_both_markets() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("qing_empire").unwrap();
        let mut unchanged = bootstrap.create("qing_empire").unwrap();
        let source = "qing_empire";
        let destination = "empire_of_japan";
        let total = world.population_units().values().sum::<u64>();
        let background = world.background_population(source).unwrap();
        assert!(world.transfer_unmanaged_population(source, destination, background, 1).is_err());
        assert_eq!(world.background_population(source), Some(background));
        world.transfer_unmanaged_population(source, destination, 10_000, 1).unwrap();
        assert_eq!(world.population_units().values().sum::<u64>(), total);
        assert_eq!(world.background_population(source), Some(background - 10_000));
        assert_eq!(world.population.unit_for_person(&world.player().id), Some(source));

        let demand = |world: &InitialWorld, country: &str| {
            world.macro_economy().markets()[country].commodities["potatoes"].demanded
        };
        let managed = BTreeMap::new();
        world.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        unchanged.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        assert!(demand(&world, source) < demand(&unchanged, source));
        assert!(demand(&world, destination) > demand(&unchanged, destination));
    }

    #[test]
    fn consumption_uses_purchased_lots_without_charging_again() {
        let mut world = WorldBootstrap::load().unwrap().create("russian_empire").unwrap();
        let market = "market:legacy_aggregate:russian_empire";
        let good = "potatoes";
        let price = world.macro_economy().markets()["russian_empire"].commodities[good].price_centimes;
        world.buy_local_stock(market, good, 1000, price, "first").unwrap();
        world.buy_local_stock(market, good, 2000, price, "second").unwrap();
        let cash = world.balance().unwrap().cash;
        assert!(world.consume_purchased_stock(good, 4000).is_err());
        assert_eq!(world.holding_milli(good), 3000);
        let consumption = world.consume_purchased_stock(good, 1500).unwrap();
        assert_eq!(consumption.record_id, "personal_life:3");
        assert_eq!(consumption.effective_minute, 0);
        assert_eq!(consumption.allocations, [
            ConsumptionAllocation { purchase_record_id: "personal_life:1".into(), quantity_milli: 1000 },
            ConsumptionAllocation { purchase_record_id: "personal_life:2".into(), quantity_milli: 500 },
        ]);
        assert_eq!(world.holding_milli(good), 1500);
        assert_eq!(world.balance().unwrap().cash, cash);
        assert_eq!(world.consume_purchased_stock(good, 1500).unwrap().allocations.len(), 1);
        assert_eq!(world.holding_milli(good), 0);
    }

    #[test]
    fn people_in_other_countries_can_transact_in_the_active_world() {
        let mut world = WorldBootstrap::load().unwrap().create("country_fra").unwrap();
        let qing = "person:formal_generated_qing_empire_0001";
        let market = "market:legacy_aggregate:qing_empire";
        let good = "potatoes";
        let price = world.macro_economy().markets()["qing_empire"].commodities[good].price_centimes;
        assert_eq!(world.buy_statistical_stock(qing, market, good, 1000, price, "first").unwrap(), price);
        assert_eq!(world.ledger().default_account(qing).unwrap().cash, 2500 - price);
        assert_eq!(world.balance().unwrap().cash, 2500);
        assert_eq!(world.holding_milli(good), 0);
        assert_eq!(world.person_holding_milli(qing, good), 1000);
        assert_eq!(world.person_profile(qing).unwrap().history, ["完成正式市场下单"]);
        assert!(world.character().history.is_empty());
        assert_eq!(world.consume_statistical_stock(qing, good, 1000).unwrap().allocations[0].quantity_milli, 1000);
        assert_eq!(world.person_holding_milli(qing, good), 0);
    }

    #[test]
    fn firm_work_cost_comes_from_completed_shifts_before_and_after_payment() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let firm = "firm:opening_paris_bakery";
        let workshop = "firm:opening_paris_workshop";
        let managed = BTreeMap::new();
        assert!(world.completed_firm_work(firm, 1).is_err());
        world.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        let work = world.completed_firm_work(firm, 1).unwrap();
        assert_eq!(work.len(), 1);
        assert_eq!((work[0].hours, work[0].accrued_wages, work[0].paid_wages, work[0].unpaid_wages), (2, 8, 0, 8));
        assert!(world.completed_firm_work(workshop, 1).unwrap().is_empty());
        assert!(world.completed_firm_work("firm:unknown", 1).is_err());
        let restored = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        assert_eq!(restored.completed_firm_work(firm, 1).unwrap(), work);
        let work_id = work[0].work_id.to_owned();
        world.advance_migrated_domains(2 * MINUTES_PER_DAY, &managed).unwrap();
        let paid = world.completed_firm_work(firm, 1).unwrap();
        assert_eq!(paid[0].work_id, work_id);
        assert_eq!((paid[0].accrued_wages, paid[0].paid_wages, paid[0].unpaid_wages), (8, 8, 0));
    }

    #[test]
    fn macro_save_fields_restore_in_transit_cargo_and_resume_settlement() {
        use crate::formal_save::typed_map;
        let bootstrap = WorldBootstrap::load().unwrap();
        let managed = BTreeMap::new();
        let mut world = bootstrap.create("german_empire").unwrap();
        while world.macro_economy().shipments().is_empty() && world.clock().current_day() < 90 {
            world.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        }
        let hour = world.clock();
        let cargo = world.macro_economy().shipments();
        assert!(!cargo.is_empty());
        let snapshot = typed_map(world.macro_economy().persistent_fields(hour));
        let mut loaded = bootstrap.restore_markets(&snapshot, hour, world.population_units()).unwrap();
        assert_eq!(loaded.shipments(), cargo);
        assert_eq!(typed_map(loaded.persistent_fields(hour)), snapshot);
        world.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        loaded.settle(world.clock(), world.population_units(), &managed).unwrap();
        assert_eq!(
            typed_map(loaded.persistent_fields(world.clock())),
            typed_map(world.macro_economy().persistent_fields(world.clock())),
        );
    }
}

#[cfg(test)]
#[path = "player_prologue_tests.rs"]
mod player_prologue_tests;
