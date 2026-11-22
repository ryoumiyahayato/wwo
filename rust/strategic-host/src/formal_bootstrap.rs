use crate::{
    formal_character::{self, CharacterOutput, DayActivity},
    formal_clock::{ClockSnapshot, GameClock, MINUTES_PER_DAY, MINUTES_PER_HOUR},
    formal_enterprise::{BreadOffer, EnterpriseOpening, Enterprises},
    formal_household::{Household, HouseholdInvitation, Households},
    formal_ledger::{Balance, Ledger, CURRENCY, MAX_AMOUNT},
    formal_livelihood::{self, Livelihood},
    formal_macro::{CountryInputs, MacroEconomy, MarketInputs, Shipment},
    formal_population::{AgeRangeCoverage, CohortId, HistoricalOpening, Population, PopulationSnapshot, MAX_POPULATION},
    formal_save::{invalid, typed_map},
    formal_service::{ServiceRoster, ServiceSnapshot, ServiceTarget},
    formal_step::next_day_boundary,
    formal_stock::PersonalHolding,
    formal_travel::LegacyTravel,
    formal_wages::{Claim, WageClaims},
    formal_work::{Job, WorkOpening, WorkState},
    transport::{operations::{Operations, OperationsState, Plan}, SegmentAvailability, TransportNetwork},
};
#[path = "formal_travel_live.rs"]
mod travel_live;
#[path = "formal_freight.rs"]
pub mod freight;
#[path = "formal_economy_read.rs"]
pub mod economy_read;
#[path = "formal_migration.rs"]
mod migration;
#[path = "formal_battle.rs"]
mod battle;
pub use battle::WorldLandBattle;
#[path = "formal_organization_registration.rs"]
pub mod organization_registration;
#[path = "formal_organization_activity.rs"]
pub mod organization_activity;
#[path = "formal_counter.rs"]
pub mod counter;
use organization_registration::{OrganizationDirectory, OrganizationMembers};
use organization_activity::OrganizationActivity;
use counter::CounterBook;
pub use travel_live::{mode_name, mode_set};
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
    written_job_notices: BTreeMap<String, String>,
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
    written_job_notice: bool,
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

#[derive(Clone, Debug, Deserialize)]
pub struct Polity {
    pub id: String,
    pub name_zh: String,
    pub flag_id: String,
    pub valid_from: String,
    pub valid_to: String,
    pub controller_id: String,
    pub relationship: String,
    #[serde(default)]
    pub capital: Option<PolityCapital>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct PolityCapital {
    pub name: String,
    pub lon: f64,
    pub lat: f64,
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

#[derive(Clone, Debug, Deserialize)]
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

#[derive(Clone, Debug)]
pub struct Route {
    pub id: String,
    pub mode: RouteMode,
    pub from_place_id: String,
    pub to_place_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct OpeningPerson {
    pub id: String,
    pub claim_id: String,
    pub opening_source_id: String,
    pub polity_id: String,
    pub place_id: String,
    birth_year: u16,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct RuntimePerson {
    origin: OpeningPerson,
    name: String,
    born_day: Option<u32>,
}

impl RuntimePerson {
    fn at(id: &str, name: String, place: &str, unit: &str, birth_year: u16, born_day: Option<u32>) -> Self {
        Self {
            origin: OpeningPerson {
                id: id.into(), claim_id: format!("formal_population_claim:{id}"),
                opening_source_id: unit.into(), polity_id: String::new(), place_id: place.into(), birth_year,
            },
            name, born_day,
        }
    }

    fn identity(&self) -> io::Result<formal_character::Identity> {
        match self.born_day {
            Some(day) => Ok(formal_character::Identity::native_birth(day, self.name.clone())),
            None => formal_character::Identity::new(
                i64::from(self.origin.birth_year), self.name.clone(), ASSUMPTION.into(), true,
            ).map_err(io::Error::other),
        }
    }
}

pub struct WorldBootstrap {
    organization_directory: Arc<OrganizationDirectory>,
    world: Arc<WorldSources>,
    archived_population_worlds: [std::sync::OnceLock<io::Result<Arc<WorldSources>>>; crate::formal_population::CURRENT_VERSION as usize - 1],
    populations: BTreeMap<String, u64>,
    market_opening_population: BTreeMap<String, u64>,
    historical_population: Arc<HistoricalOpening>,
    markets: Arc<MarketInputs>,
    residents: BTreeMap<String, i64>,
    opening_people: BTreeMap<String, Arc<OpeningPerson>>,
    opening_place_names: BTreeMap<String, String>,
    opening_cash: i64,
    work: Arc<WorkOpening>,
    enterprise_opening: Arc<EnterpriseOpening>,
    activities: Arc<OpeningActivities>,
}

#[derive(Clone)]
pub struct WorldSources {
    pub(crate) historical_population: Option<Arc<HistoricalOpening>>,
    polities: BTreeMap<String, Polity>,
    places: BTreeMap<String, Place>,
    routes: BTreeMap<String, Route>,
    place_population_units: BTreeMap<String, String>,
    polity_population_bindings: BTreeMap<String, String>,
    population_name_aliases: BTreeMap<String, String>,
    population_income: BTreeMap<String, u64>,
    people: BTreeMap<String, OpeningPerson>,
    regimental_opening_stations: BTreeMap<String, Vec<RegimentalOpeningStation>>,
}

/// The regiment's central station at the 1900 opening. Detached units can be elsewhere.
#[derive(Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RegimentalOpeningStation {
    pub regiment_id: String,
    pub name: String,
    pub name_zh: String,
    pub polity_id: String,
    pub place_id: String,
    pub source: String,
    pub source_url: String,
}

pub struct InitialWorld {
    organization_directory: Arc<OrganizationDirectory>,
    organization_members: OrganizationMembers,
    activity: OrganizationActivity,
    counters: CounterBook,
    sources: Arc<WorldSources>,
    pub(crate) player: String,
    player_origin: Arc<OpeningPerson>,
    identities: BTreeMap<String, formal_character::Identity>,
    runtime_people: BTreeMap<String, RuntimePerson>,
    clock: GameClock,
    pub(crate) population: Population,
    macro_economy: MacroEconomy,
    character: CharacterOutput,
    ledger: Ledger,
    pub(crate) holdings: BTreeMap<String, BTreeMap<String, PersonalHolding>>,
    next_living_record: u64,
    settled_purchase_requests: BTreeMap<String, BTreeSet<String>>,
    work_opening: Arc<WorkOpening>,
    work: WorkState,
    wages: WageClaims,
    enterprise_opening: Arc<EnterpriseOpening>,
    enterprises: Enterprises,
    pub(crate) livelihood: Livelihood,
    pub(crate) households: Households,
    homes: BTreeMap<String, String>,
    service: ServiceRoster,
    activities: Arc<OpeningActivities>,
    player_day: PlayerDay,
    transport: Operations,
    travel: travel_live::TravelState,
    migration: migration::MigrationState,
    travel_preview: Option<Plan>,
    freight_preview: Option<Plan>,
    selected_freight: Option<u64>,
    freight: freight::FreightBook,
    land_battle: Option<WorldLandBattle>,
    land_battle_history: Vec<WorldLandBattle>,
}

#[derive(Serialize)]
pub struct ResidentAgeAvailability {
    pub population_total: u64,
    pub youngest: u16,
    pub oldest: u16,
    pub anonymous: AgeRangeCoverage,
    pub anonymous_outside_active_service: AgeRangeCoverage,
    pub named_in_age_range: u64,
    pub named_in_age_range_eligible_for_civilian_work: u64,
    pub named_in_age_range_in_active_service: u64,
    pub named_in_active_service_all_ages: u64,
    pub anonymous_in_active_service_all_ages: u64,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct WorldSnapshot {
    #[serde(default)]
    organization_members: Option<OrganizationMembers>,
    #[serde(default)]
    activity: OrganizationActivity,
    #[serde(default)]
    counters: CounterBook,
    opening: String,
    #[serde(default)]
    opening_place: Option<String>,
    clock: ClockSnapshot,
    population: NativePopulation,
    markets: Value,
    #[serde(default)]
    last_arrivals: Vec<Shipment>,
    ledger: Value,
    character: String,
    #[serde(default)]
    runtime_people: BTreeMap<String, RuntimePerson>,
    holdings: BTreeMap<String, BTreeMap<String, PersonalHolding>>,
    next_living_record: u64,
    settled_purchase_requests: BTreeMap<String, BTreeSet<String>>,
    work: WorkState,
    wages: BTreeMap<String, Claim>,
    #[serde(default)]
    enterprises: Option<Enterprises>,
    #[serde(default)]
    livelihood: Livelihood,
    #[serde(default)]
    households: Households,
    #[serde(default)]
    travel: Option<TravelSnapshot>,
    #[serde(default)]
    migration: migration::MigrationState,
    #[serde(default)]
    transport_restrictions: BTreeMap<String, SegmentAvailability>,
    #[serde(default)]
    homes: BTreeMap<String, String>,
    #[serde(default)]
    service: ServiceSnapshot,
    #[serde(default)]
    player_day: PlayerDay,
    #[serde(default)]
    transport: OperationsState,
    #[serde(default)]
    freight: freight::FreightBook,
    #[serde(default)]
    land_battle: Option<WorldLandBattle>,
    #[serde(default)]
    land_battle_history: Vec<WorldLandBattle>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum TravelSnapshot {
    Current(travel_live::TravelState),
    Legacy(LegacyTravel),
}

#[derive(Deserialize)]
#[serde(untagged)]
enum NativePopulation {
    Versioned(PopulationSnapshot),
    Legacy(BTreeMap<String, u64>),
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
            "opening_place": self.player().place_id,
            "organization_members": self.organization_members,
            "activity": self.activity,
            "counters": self.counters,
            "clock": self.clock.snapshot(),
            "population": self.population.snapshot(),
            "markets": typed_map(self.macro_economy.persistent_fields(self.clock)),
            "last_arrivals": self.macro_economy.last_arrivals(),
            "ledger": self.ledger.snapshot(),
            "character": self.character.state,
            "runtime_people": self.runtime_people,
            "holdings": self.holdings,
            "next_living_record": self.next_living_record,
            "settled_purchase_requests": self.settled_purchase_requests,
            "work": self.work,
            "wages": self.wages.claims(),
            "enterprises": self.enterprises,
            "livelihood": self.livelihood,
            "households": self.households,
            "homes": self.homes,
            "service": self.service.snapshot(),
            "player_day": self.player_day,
            "transport": self.transport.state(),
            "travel": self.travel,
            "migration": self.migration,
            "freight": self.freight,
            "land_battle": self.land_battle,
            "land_battle_history": self.land_battle_history,
        })
    }

    pub fn goods_held(&self) -> impl Iterator<Item = (&str, i64, bool)> {
        self.holdings.get(&self.player).into_iter().flatten().filter_map(|(good, holding)| {
            let available = holding.available();
            (available > 0).then_some((good.as_str(), available, self.macro_economy.is_consumable(good)))
        })
    }

    pub fn player_market_unit(&self) -> &str {
        self.market_unit_for_person(&self.player).unwrap_or_else(|| {
            self.population_unit_at(&self.player().place_id).expect("opening has a formal market")
        })
    }

    pub(crate) fn named_people(&self) -> impl Iterator<Item = &str> {
        self.identities.keys().map(String::as_str).filter(|person| self.population.unit_for_person(person).is_some())
    }

    pub fn current_place(&self, person: &str) -> Option<&str> {
        self.population.unit_for_person(person)?;
        self.present_at(person, &self.person(person)?.place_id)
    }

    pub fn player_current_place(&self) -> Option<&str> { self.current_place(&self.player) }

    pub fn player_home(&self) -> &str {
        self.person_home(&self.player).unwrap_or(&self.player().place_id)
    }

    pub fn person_home(&self, person: &str) -> Option<&str> {
        self.population.unit_for_person(person)?;
        self.homes.get(person).map(String::as_str).or_else(|| self.person(person).map(|row| row.place_id.as_str()))
    }

    pub fn transport(&self) -> &TransportNetwork { self.transport.network() }

    pub fn transport_stop_for_reservation(&self, reservation: u64) -> Option<&str> { self.transport.held(reservation) }
    pub fn occupied_transport_units(&self, segment: &str) -> u32 { self.transport.occupied_units(segment) }

    pub fn transport_service_capacity(&self, segment: &str, from: &str) -> Option<crate::transport::operations::ServiceCapacity> {
        self.transport.service_capacity(segment, from)
    }

    /// Apply a route-availability event from the world. In-progress trips retain their committed arrival.
    pub fn set_segment_access(&mut self, route: &str, open: bool, capacity: u32) -> io::Result<()> {
        self.transport.set_access(route, open, capacity)
    }

    pub fn market_unit_for_person(&self, person: &str) -> Option<&str> {
        self.population_unit_at(self.current_place(person)?)
    }

    pub fn market_unit_for_population(&self, unit: &str) -> Option<&str> {
        let parent = self.population.parent_unit(unit)?;
        self.macro_economy.markets().contains_key(parent).then_some(parent)
    }

    pub(crate) fn market_unit_at(&self, place: &str) -> Option<&str> {
        self.population_unit_at(place)
    }

    pub fn population_unit_at(&self, place: &str) -> Option<&str> {
        let network = self.transport.network();
        let market = self.sources.population_unit_at(place)
            .or_else(|| network.unit_at(place))
            .or_else(|| self.population.parent_unit(self.population.partition_at(place)?))?;
        self.macro_economy.markets().get_key_value(market).map(|(id, _)| id.as_str())
    }

    /// An administrative parent can record a residence when its opening has an exclusive pool.
    pub fn residence_unit_at(&self, place: &str) -> Option<&str> {
        if let Some(partition) = self.population.partition_at(place) {
            return Some(partition);
        }
        let parent = self.sources.population_unit_at(place)
            .or_else(|| self.transport.network().unit_at(place))
            .or_else(|| self.sources.opening_parent_at(place))?;
        self.population.residence_parent(parent)
    }

    fn has_committed_player_day(&self) -> bool {
        self.player_day.booking.is_some() || self.work.booking(&self.player).is_some()
    }

    pub fn travel_player(&mut self, route: &str, destination: &str) -> io::Result<()> {
        self.travel_person(&self.player.clone(), route, destination)
    }

    pub fn can_move_player_home(&self) -> bool {
        self.player_current_place().is_some_and(|place| {
            place != self.player_home() && self.can_reside_at(place)
        })
    }

    pub fn move_player_home(&mut self) -> io::Result<()> {
        self.move_person_home(&self.player.clone())
    }

    pub fn move_person_home(&mut self, person: &str) -> io::Result<()> {
        let place = self.current_place(person).filter(|&place| self.person_home(person) != Some(place) && self.can_reside_at(place))
            .ok_or_else(|| invalid("当前位置无法登记迁居。"))?.to_owned();
        let unit = self.residence_unit_at(&place).ok_or_else(|| invalid("地点没有正式人口归属。"))?.to_owned();
        if self.population.unit_for_person(person) != Some(unit.as_str()) {
            self.population.move_person(person, &unit, self.clock.snapshot().total_minutes)?;
        }
        self.households.leave(person);
        self.homes.insert(person.to_owned(), place);
        if person == self.player { self.travel.disable_commute(); }
        Ok(())
    }

    fn can_reside_at(&self, place: &str) -> bool {
        self.residence_unit_at(place).is_some() && !place.starts_with("area:")
            && (self.sources.places.contains_key(place)
                || self.transport.network().node(place).is_some_and(|node| node.kind == crate::transport::NodeKind::City))
    }

    pub fn household_of(&self, person: &str) -> Option<(&str, &Household)> {
        self.households.household_of(person)
    }

    pub fn household_invitation_for(&self, person: &str) -> Option<&HouseholdInvitation> {
        self.households.invitation_for(person)
    }

    /// Execute the named resident's choice to offer a shared household.
    pub fn invite_to_household(&mut self, inviter: &str, invitee: &str) -> io::Result<()> {
        let home = self.household_meeting_place(inviter, invitee)?;
        self.households.invite(inviter, invitee, &home, self.clock.snapshot().total_minutes)
    }

    /// The invited resident must accept independently of the offer.
    pub fn accept_household(&mut self, invitee: &str, inviter: &str) -> io::Result<String> {
        let home = self.household_meeting_place(inviter, invitee)?;
        self.households.accept(invitee, inviter, &home, self.clock.snapshot().total_minutes)
    }

    pub fn decline_household(&mut self, invitee: &str, inviter: &str) -> bool {
        self.households.decline(invitee, inviter)
    }

    pub fn leave_household(&mut self, person: &str) -> bool {
        self.households.leave(person)
    }

    fn household_meeting_place(&self, host: &str, guest: &str) -> io::Result<String> {
        let host_home = self.person_home(host);
        let place = self.current_place(host)
            .filter(|&place| Some(place) == host_home && self.current_place(guest) == Some(place))
            .ok_or_else(|| invalid("共同生活的申请需要双方到场。"))?;
        if self.person_profile(host)?.age_years < 18 || self.person_profile(guest)?.age_years < 18 {
            return Err(invalid("共同生活协议需要成年当事人。"));
        }
        Ok(place.to_owned())
    }

    pub fn jobs(&self) -> impl Iterator<Item = (&Job, usize)> {
        self.work.local_jobs(&self.work_opening, &self.player, self.player_current_place(), self.clock.current_day())
            .filter(|job| self.can_access_player_job(&job.id))
            .map(|job| (job, if self.can_take_organization_job(&self.player, job) { self.work.vacancies(job) } else { 0 }))
    }

    fn player_written_job(&self) -> Option<&str> {
        if !self.player_day.written_job_notice { return None; }
        self.activities.written_job_notices.get(&self.player().opening_source_id).map(String::as_str)
    }

    fn can_access_player_job(&self, job: &str) -> bool {
        self.player_written_job() != Some(job) || self.can_read_opening_language()
            || self.work.has_referral(&self.player, job)
            || self.player_day.last_read_notice.is_some()
    }

    pub fn player_knows_job_by_referral(&self, job: &str) -> bool { self.work.has_referral(&self.player, job) }

    fn player_knows_job_orally(&self, job: &str) -> bool {
        self.player_knows_job_by_referral(job)
            || (self.player_day.last_read_notice.is_some() && self.player_written_job() == Some(job))
    }

    pub fn oral_work_offer(&self) -> Option<(&Job, usize)> {
        if self.work.has_contract(&self.player) || !self.eligible_for_civil_work(&self.player) { return None; }
        self.jobs().filter(|(job, _)| self.player_knows_job_orally(&job.id))
            .max_by_key(|(job, openings)| (*openings > 0, self.player_knows_job_by_referral(&job.id), job.wage_per_hour))
    }

    pub fn oral_work_employment(&self) -> Option<(&Job, bool)> {
        let (job, booked, _) = self.employment()?;
        self.player_knows_job_orally(&job.id).then_some((job, booked))
    }

    pub fn employment(&self) -> Option<(&Job, bool, &str)> {
        let job = self.work.contract(&self.work_opening, &self.player)?;
        Some((job, self.work.booking(&self.player).is_some(), self.work_opening.organization(&job.employer)?))
    }

    pub fn player_service(&self) -> Option<&ServiceTarget> { self.service.named_target(&self.player) }

    /// Called after the military owner resolves a specific assignment and the resident's decision.
    pub(crate) fn enlist_named_service(
        &mut self, person: &str, target: ServiceTarget, volunteered: bool,
    ) -> io::Result<()> {
        if !known_service_target(&target) || !self.eligible_for_civil_work(person)
            || self.person_profile(person)?.age_years < 18 || self.current_place(person).is_none()
            || (person == self.player && self.has_committed_player_day())
        {
            return Err(invalid("person or target is unavailable for formal service"));
        }
        self.service.enlist_named(&self.population, person, target, volunteered, true)?;
        self.work.remove_actor(person);
        Ok(())
    }

    pub(crate) fn discharge_named_service(&mut self, person: &str) -> io::Result<()> {
        self.service.release_named(person).map(|_| ()).ok_or_else(|| invalid("person has no formal service assignment"))
    }

    fn eligible_for_civil_work(&self, person: &str) -> bool {
        self.service.named_target(person).is_none() && self.character.work_eligible.contains(person)
    }

    pub fn completed_firm_work(&self, firm: &str, day: i64) -> io::Result<Vec<CompletedFirmWork<'_>>> {
        if self.work_opening.organization(firm).is_none() || !(1..=self.clock.current_day()).contains(&day) {
            return Err(invalid("completed company work requires a known firm and completed day"));
        }
        Ok(self.wages.completed_firm_work(firm, day))
    }

    pub fn apply_for_work(&mut self, job: &str) -> io::Result<()> {
        self.apply_for_work_as(&self.player.clone(), job)
    }

    pub fn can_consult_player_work(&self) -> bool {
        self.eligible_for_civil_work(&self.player) && self.character().age_years >= 18
            && !self.work.has_contract(&self.player) && self.player_current_place().is_some_and(|place| {
                self.work.has_unseen_entry_jobs(&self.work_opening, &self.player, place, self.clock.current_day())
            })
    }

    /// An adult can discover existing entry-level jobs by visiting the employer's town.
    pub fn consult_local_work(&mut self, person: &str) -> io::Result<()> {
        if !self.eligible_for_civil_work(person) || self.person_profile(person)?.age_years < 18 {
            return Err(invalid("当前人物无法咨询当地入门岗位。"));
        }
        let place = self.current_place(person).ok_or_else(|| invalid("人物不在当地。"))?.to_owned();
        self.work.consult_local_notices(&self.work_opening, person, &place);
        Ok(())
    }

    pub fn apply_for_work_as(&mut self, person: &str, job: &str) -> io::Result<()> {
        if !self.eligible_for_civil_work(person) { return Err(invalid("当前健康或服役状态不允许民间就业。")); }
        if !self.work_opening.job(job).is_some_and(|job| self.can_take_organization_job(person, job)) {
            return Err(invalid("这份工作当前没有可承办的业务。"));
        }
        if person == self.player && !self.can_access_player_job(job) {
            return Err(invalid("人物还未能读懂或听取这份招聘公告。"));
        }
        let place = self.current_place(person).map(str::to_owned);
        self.work.apply(&self.work_opening, person, job, place.as_deref(), self.clock.current_day())
    }

    pub fn can_book_work(&self) -> bool {
        self.eligible_for_civil_work(&self.player) && self.player_day.booking.is_none()
            && self.work.contract(&self.work_opening, &self.player).is_some_and(|job| self.can_take_organization_job(&self.player, job))
            && self.work.can_book(&self.work_opening, &self.player, self.player_current_place(), self.clock)
    }

    pub fn book_work(&mut self) -> io::Result<()> {
        self.book_work_as(&self.player.clone())
    }

    pub fn book_work_as(&mut self, person: &str) -> io::Result<()> {
        if !self.work.contract(&self.work_opening, person).is_some_and(|job| self.can_take_organization_job(person, job)) {
            return Err(invalid("当前没有可登记的经营班次。"));
        }
        if !self.eligible_for_civil_work(person) { return Err(invalid("当前健康或服役状态不允许民间就业。")); }
        if person == self.player && self.player_day.booking.is_some() { return Err(invalid("今日已有个人安排。")); }
        let place = self.current_place(person).map(str::to_owned);
        self.work.book(&self.work_opening, person, place.as_deref(), self.clock)
    }

    pub fn leave_employment(&mut self) -> io::Result<()> {
        self.work.release(&self.player)?;
        self.travel.disable_commute();
        Ok(())
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
            self.sources.places.get(id).is_some_and(|place| self.can_read_polity_record(historical_place_polity(place)))
                || self.population_unit_at(id).is_some_and(|unit| self.can_read_polity_record(unit))
        })
    }

    pub fn regimental_opening_stations(&self, place_id: &str) -> &[RegimentalOpeningStation] {
        if !self.can_read_place_record(place_id) {
            return &[];
        }
        self.sources.regimental_opening_stations.get(place_id).map_or(&[], Vec::as_slice)
    }

    pub fn opening_language(&self) -> Option<Language> {
        self.character.development.as_ref().map(|player| player.language())
    }

    pub fn scheduled_activity(&self) -> Option<PersonalActivity> {
        self.player_day.booking.map(|booking| booking.kind)
    }

    pub fn last_read_notice(&self) -> Option<i64> { self.player_day.last_read_notice }

    pub fn schedule_personal_activity(&mut self, kind: PersonalActivity) -> io::Result<()> {
        self.check_leisure()?;
        let minute = self.clock.snapshot().total_minutes;
        if !self.can_schedule_personal_activity(kind) {
            return Err(invalid("当前无法安排这项活动。"));
        }
        self.player_day.booking = Some(ActivityBooking { kind, minute });
        Ok(())
    }

    pub fn can_schedule_personal_activity(&self, kind: PersonalActivity) -> bool {
        if self.passenger_in_transit() { return false; }
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
                let reachable = self.player_current_place() == Some(self.player().place_id.as_str())
                    && self.activities.openings.contains_key(&self.player().opening_source_id)
                    && today <= self.activities.lesson_start_hour * MINUTES_PER_HOUR;
                reachable && !self.can_read_opening_language()
                    && (kind != PersonalActivity::ReadNotice || self.player_day.last_read_notice.is_none())
            }
            PersonalActivity::Rest => self.player_current_place().is_some() && today <= 16 * MINUTES_PER_HOUR,
        }
    }

    pub fn sources(&self) -> &WorldSources {
        &self.sources
    }

    pub fn player(&self) -> &OpeningPerson {
        &self.player_origin
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
        self.apply_organization_profile(&mut profile);
        profile.history.splice(..0, self.player_referral_contacts());
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
        if request.is_empty() || request.len() > 128 {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid personal purchase request"));
        }
        if self.settled_purchase_requests.get(person).is_some_and(|requests| requests.contains(request)) {
            return Err(invalid("purchase request was already settled"));
        }
        let amount = self.buy_livelihood_stock(person, market, good, quantity_milli, quoted_unit_price, self.clock.snapshot().total_minutes, true)?;
        self.settled_purchase_requests.entry(person.to_owned()).or_default().insert(request.to_owned());
        Ok(amount)
    }

    pub(crate) fn buy_livelihood_stock(
        &mut self, person: &str, market: &str, good: &str, quantity_milli: i64, quoted_unit_price: i64, minute: i64,
        explicit_action: bool,
    ) -> io::Result<i64> {
        if let Some(holding) = self.holdings.get(person).and_then(|goods| goods.get(good)) {
            holding.check_purchase(quantity_milli)?;
        }
        let available = self.ledger.default_account(person).ok_or_else(|| invalid("person lacks a cash account"))?.available;
        let local_unit = self.market_unit_for_person(person)
            .ok_or_else(|| invalid("person is not present at an accessible market"))?.to_owned();
        let day = self.character.day;
        let record_id = format!("personal_life:{}", self.next_living_record);
        let (amount, viewed_character) = self.macro_economy.sell_existing_stock(
            &local_unit, market, good, quantity_milli, quoted_unit_price, |amount| {
                let player_view = if explicit_action {
                    let character = formal_character::assess_purchase(
                        person, &self.identities, day, &self.character.state, market, amount as u64, available as u64,
                    ).map_err(io::Error::other)?;
                    Some(if person == self.player { character } else {
                        formal_character::opening_profile(&self.player, &self.identities, day, &character.state)
                            .map_err(io::Error::other)?
                    })
                } else { None };
                self.ledger.buy_from_market(person, market, &record_id, amount, minute)?;
                Ok(player_view)
            },
        )?;
        if let Some(view) = viewed_character { self.character = view; }
        self.holdings.entry(person.to_owned()).or_default().entry(good.to_owned()).or_default()
            .record_purchase(record_id, quantity_milli);
        self.next_living_record += 1;
        Ok(amount)
    }

    pub fn local_bread_offer(&self) -> Option<BreadOffer<'_>> {
        self.local_bread_offer_for(&self.player, 1)
    }

    pub(crate) fn local_bread_offer_for(&self, person: &str, qty: i64) -> Option<BreadOffer<'_>> {
        self.enterprises.bread_offer(&self.enterprise_opening, self.current_place(person)?, qty)
    }

    pub fn buy_local_bread(&mut self, qty: i64) -> io::Result<i64> {
        self.buy_local_firm_meal(&self.player.clone(), qty, self.clock.snapshot().total_minutes)?
            .ok_or_else(|| invalid("本地商铺当前无法交付所需面包。"))
    }

    pub(crate) fn buy_local_firm_meal(&mut self, person: &str, qty: i64, minute: i64) -> io::Result<Option<i64>> {
        if qty <= 0 { return Err(invalid("bread quantity must be positive")); }
        let Some(place) = self.current_place(person) else { return Ok(None); };
        let Some(offer) = self.enterprises.bread_offer(&self.enterprise_opening, place, qty) else { return Ok(None); };
        let record = format!("personal_life:{}", self.next_living_record);
        if let Some(holding) = self.holdings.get(person).and_then(|goods| goods.get("bread")) {
            holding.check_purchase(qty)?;
        }
        let available = self.ledger.default_account(person).ok_or_else(|| invalid("missing personal account"))?.available;
        let price = offer.price * qty;
        if available < price { return Ok(None); }
        let day = self.character.day;
        let viewed = if person == self.player {
            Some(formal_character::assess_purchase(
                person, &self.identities, day, &self.character.state, offer.site, price as u64, available as u64,
            ).map_err(io::Error::other)?)
        } else { None };
        let paid = self.enterprises.sell_bread(offer, &mut self.ledger, person, qty, &record, minute)?;
        if let Some(view) = viewed { self.character = view; }
        self.holdings.entry(person.to_owned()).or_default().entry("bread".into()).or_default().record_purchase(record, qty);
        self.next_living_record += 1;
        Ok(Some(paid))
    }

    /// Consume purchased statistical stock in purchase order and return the
    /// exact allocations needed by the personal living record.
    pub fn consume_purchased_stock(&mut self, good: &str, quantity_milli: i64) -> io::Result<Consumption> {
        self.consume_statistical_stock(&self.player.clone(), good, quantity_milli)
    }

    pub(crate) fn staple_weight_target(&self) -> i64 { self.activities.meal_milli_for_recovery }

    pub fn consume_statistical_stock(&mut self, person: &str, good: &str, quantity_milli: i64) -> io::Result<Consumption> {
        let food = formal_livelihood::counts_as_food(good);
        if food && !self.livelihood.can_record_today(person, quantity_milli) {
            return Err(invalid("daily food deductions exceed supported quantity"));
        }
        let result = self.consume_livelihood_stock(person, good, quantity_milli, self.clock.snapshot().total_minutes)?;
        if food {
            self.livelihood.record_food(person, good, &result);
        }
        Ok(result)
    }

    pub(crate) fn consume_livelihood_stock(&mut self, person: &str, good: &str, quantity_milli: i64, minute: i64) -> io::Result<Consumption> {
        if !self.macro_economy.is_consumable(good) || self.population.unit_for_person(person).is_none() {
            return Err(invalid("person or commodity is not eligible for consumption"));
        }
        let allocations = self.holdings.get_mut(person).and_then(|goods| goods.get_mut(good))
            .ok_or_else(|| invalid("person has no stock of this commodity"))?
            .consume(quantity_milli)?;
        let record_id = format!("personal_life:{}", self.next_living_record);
        self.next_living_record += 1;
        Ok(Consumption { record_id, effective_minute: minute, allocations })
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
        self.advance_migrated_domains_to(target, managed_population)
    }

    fn advance_migrated_domains_to(
        &mut self,
        target: GameClock,
        managed_population: &BTreeMap<String, u64>,
    ) -> io::Result<()> {
        u32::try_from(target.current_day()).map_err(|_| invalid("unsupported formal character date"))?;
        if target.current_day() != self.clock.current_day() {
            self.macro_economy.check_responsibility(self.population.totals(), &self.managed_residents(managed_population)?)?;
        }
        let through = target.snapshot().total_minutes;
        while self.clock.snapshot().total_minutes != through {
            let day_boundary = next_day_boundary(self.clock);
            let minute = self.next_travel_event().into_iter().chain(day_boundary)
                .min().map_or(through, |event| event.min(through));
            let mut boundary = self.clock;
            boundary.advance_minutes(minute - boundary.snapshot().total_minutes)?;
            if minute != self.clock.snapshot().total_minutes {
                boundary = boundary.minute_boundary();
            }
            if Some(minute) != day_boundary {
                self.clock = boundary;
                self.advance_transport()?;
                continue;
            }
            let day = u32::try_from(boundary.current_day()).map_err(|_| invalid("unsupported formal character date"))?;
            #[cfg(test)]
            let mut measure = day_measurement::start();
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
            for worker in self.work.booked_workers() {
                let job = self.work.contract(&self.work_opening, worker).expect("booking has a live contract");
                self.wages.record_shift(worker, job, i64::from(day), &self.ledger)?;
            }
            self.wages.settle_due(&mut self.ledger, boundary, |_| false)?;
            #[cfg(test)]
            day_measurement::mark(&mut measure, 0);
            self.enterprises.settle(&self.enterprise_opening, &self.wages, i64::from(day));
            self.settle_counter_orders(boundary)?;
            self.settle_organization_activity(boundary)?;
            #[cfg(test)]
            day_measurement::mark(&mut measure, 1);
            let (mut nutrition_by_person, settled_meal_purchases) =
                self.settle_named_livelihood(day, minute, self.activities.meal_milli_for_recovery);
            #[cfg(test)]
            day_measurement::mark(&mut measure, 2);
            if self.player_day.food_milli > 0 {
                nutrition_by_person.insert(self.player.clone(), 1000);
            }
            let activity = DayActivity {
                work, lesson, injury,
                rest: booking == Some(PersonalActivity::Rest),
                nutrition: None,
                nutrition_by_person,
                settled_meal_purchases,
            };
            let character = formal_character::advance_opening_day(
                &self.player, &self.identities, day, &self.character.state, activity,
            ).map_err(io::Error::other)?;
            for death in &character.deaths {
                self.population.record_death(&death.person_id, minute)?;
                self.identities.get_mut(&death.person_id).expect("known person").record_death();
                self.work.forget_actor(&death.person_id);
                self.stop_transport_on_death(&death.person_id);
                self.homes.remove(&death.person_id);
                self.households.leave(&death.person_id);
                self.service.release_named(&death.person_id);
            }
            #[cfg(test)]
            day_measurement::mark(&mut measure, 3);
            self.transport.advance(minute);
            self.settle_background_migrations(minute)?;
            let managed = self.managed_residents(managed_population)?;
            self.macro_economy.settle(boundary, self.population.totals(), &managed, &mut self.transport, &mut self.ledger)?;
            #[cfg(test)]
            day_measurement::mark(&mut measure, 4);
            self.work.complete();
            self.character = character;
            if booking == Some(PersonalActivity::ReadNotice) && self.player_alive() {
                self.player_day.last_read_notice = Some(minute);
            }
            self.player_day.booking = None;
            self.player_day.food_milli = 0;
            self.clock = boundary;
            self.advance_transport()?;
            self.review_background_migration(managed_population);
            self.plan_household_orders()?;
            self.settle_organization_employment()?;
        }
        self.clock = target;
        Ok(())
    }

    fn managed_residents(&self, external: &BTreeMap<String, u64>) -> io::Result<BTreeMap<String, u64>> {
        let mut managed = external.clone();
        for (unit, &named) in self.population.named_counts() {
            if !self.population.totals().contains_key(unit) { continue; }
            let count = managed.entry(unit.clone()).or_default();
            *count = count.checked_add(named).ok_or_else(|| invalid("invalid managed population"))?;
        }
        Ok(managed)
    }

    pub fn population_units(&self) -> &BTreeMap<String, u64> {
        self.population.totals()
    }

    pub fn population(&self) -> &Population { &self.population }

    /// Resolve exact historical name aliases and the residence binding that a
    /// settled move uses. A residence binding does not enumerate the site.
    pub fn inspect_population<'a>(&'a self, query: &'a str) -> io::Result<crate::formal_population::PopulationInspection<'a>> {
        let residence = query.starts_with("place:").then(|| self.residence_unit_at(query)).flatten();
        let map_id = query.strip_prefix("state:").unwrap_or(query);
        let alias = self.sources.population_name_aliases.get(map_id).map(String::as_str);
        self.population.inspect_with_mapping(query, self.clock, alias, residence)
    }

    pub fn person(&self, person: &str) -> Option<&OpeningPerson> {
        if person == self.player { return Some(self.player()); }
        self.sources.people.get(person).or_else(|| self.runtime_people.get(person).map(|row| &row.origin))
    }

    /// Register an important resident against an existing anonymous share.
    /// The caller owns the narrative decision to assign the generated identity.
    pub fn materialize_resident(
        &mut self, id: &str, name: String, place: &str, birth_year: u16, cohort: Option<&CohortId>,
    ) -> io::Result<()> {
        self.register_resident(id, name, place, birth_year, None, cohort)
    }

    /// Publish a completed birth from a simulation or authorized scenario.
    pub(crate) fn register_birth(&mut self, id: &str, name: String, place: &str) -> io::Result<()> {
        let year = u16::try_from(self.clock.current_date().year).map_err(io::Error::other)?;
        self.register_resident(id, name, place, year, Some(self.character.day), None)
    }

    fn materialization_cohort(
        &self, population: &Population, unit: &str, birth_year: u16,
    ) -> Option<Option<CohortId>> {
        if population.unclassified(unit)? > self.migration_reserved_at(unit) {
            return Some(None);
        }
        population.cohorts_in(unit)
            .filter(|(id, _, members)| *members > self.migration_reserved_cohort(unit, Some(id))
                && self.service.cohort_serving(unit, id) == 0
                && population.cohort_can_materialize(id, i64::from(birth_year)))
            .max_by_key(|(_, definition, members)| (definition.birth_years.is_some(), *members))
            .map(|(id, _, _)| Some(id.clone()))
    }

    fn register_resident(
        &mut self, id: &str, name: String, place: &str, birth_year: u16, born_day: Option<u32>, cohort: Option<&CohortId>,
    ) -> io::Result<()> {
        let unit = self.residence_unit_at(place).filter(|_| self.can_reside_at(place))
            .ok_or_else(|| invalid("unknown residence population binding"))?.to_owned();
        if !id.strip_prefix("person:").is_some_and(local_id) || name.trim().is_empty()
            || name.len() > 240 || self.identities.contains_key(id) || self.ledger.default_account(id).is_some()
            || i64::from(birth_year) > self.clock.current_date().year
        {
            return Err(invalid("invalid new formal resident"));
        }
        let selected = if born_day.is_none() && cohort.is_none() {
            self.materialization_cohort(&self.population, &unit, birth_year)
                .ok_or_else(|| invalid("没有可具名的未预约背景居民。"))?
        } else {
            None
        };
        let cohort = cohort.or(selected.as_ref());
        if let Some(cohort) = cohort {
            if self.population.cohort_members(&unit, cohort)
                .is_none_or(|members| members <= self.migration_reserved_cohort(&unit, Some(cohort)))
            {
                return Err(invalid("no demographic cohort at the resident's origin"));
            }
            if !self.population.cohort_can_materialize(cohort, i64::from(birth_year)) {
                return Err(invalid("birth year is outside the resident's cohort"));
            }
            if self.service.cohort_serving(&unit, cohort) != 0 {
                return Err(invalid("materialization requires identifying the resident's service status"));
            }
        }
        let row = RuntimePerson::at(id, name, place, &unit, birth_year, born_day);
        let mut people = self.identities.clone();
        people.insert(id.to_owned(), row.identity()?);
        let character = formal_character::register_native_person(&self.player, &people, id, self.character.day, &self.character.state)
            .map_err(io::Error::other)?;
        let minute = self.clock.snapshot().total_minutes;
        if born_day.is_some() {
            self.population.record_named_birth(id, &unit, minute)?;
        } else {
            self.population.materialize_person(id, &unit, cohort, minute)?;
        }
        self.ledger.open_person_cash(id)?;
        self.runtime_people.insert(id.to_owned(), row);
        self.identities = people;
        self.character = character;
        Ok(())
    }

    pub fn person_profile(&self, person: &str) -> io::Result<wwo_character_core::PersonView> {
        formal_character::opening_profile(person, &self.identities, self.character.day, &self.character.state)
            .map(|character| character.profile).map_err(io::Error::other)
    }

    /// Age-range bounds and actual service assignments for statistical residents.
    /// Eligibility for named civilian work is taken from the existing character state.
    pub fn resident_age_availability(
        &self, unit: Option<&str>, youngest: u16, oldest: u16,
    ) -> io::Result<ResidentAgeAvailability> {
        let structure = self.population.structure(unit, self.clock)
            .ok_or_else(|| invalid("unknown statistical population unit"))?;
        let anonymous = structure.count_ages(youngest, oldest)
            .ok_or_else(|| invalid("age range endpoints are inverted"))?;
        let anonymous_outside_active_service = structure.count_cohort_ages(youngest, oldest, |cohort| {
            cohort.members - self.service.cohort_serving(cohort.unit_id, cohort.id)
        }).expect("age range was validated");
        let mut result = ResidentAgeAvailability {
            population_total: structure.population_total, youngest, oldest,
            anonymous_in_active_service_all_ages: anonymous.population_total - anonymous_outside_active_service.population_total,
            anonymous, anonymous_outside_active_service, named_in_age_range: 0,
            named_in_age_range_eligible_for_civilian_work: 0, named_in_age_range_in_active_service: 0,
            named_in_active_service_all_ages: 0,
        };
        let range = u32::from(youngest)..=u32::from(oldest);
        for person in self.identities.keys() {
            let Some(pool) = self.population.unit_for_person(person) else { continue; };
            if unit.is_some_and(|unit| !self.population.pool_in_scope(pool, unit)) {
                continue;
            }
            let serving = self.service.named_target(person).is_some();
            result.named_in_active_service_all_ages += u64::from(serving);
            if range.contains(&self.person_profile(person)?.age_years) {
                result.named_in_age_range += 1;
                result.named_in_age_range_in_active_service += u64::from(serving);
                result.named_in_age_range_eligible_for_civilian_work +=
                    u64::from(self.eligible_for_civil_work(person));
            }
        }
        Ok(result)
    }

    pub fn background_population(&self, unit: &str) -> Option<u64> {
        self.population.background(unit)
    }

    pub fn transfer_unmanaged_population(
        &mut self, source: &str, destination: &str, amount: u64, source_managed_background: u64,
    ) -> io::Result<()> {
        let protected = source_managed_background.checked_add(self.migration_reserved_at(source))
            .ok_or_else(|| invalid("invalid managed population"))?;
        self.population.transfer_unmanaged(source, destination, amount, protected, self.clock.snapshot().total_minutes)
    }
}

#[cfg(test)]
mod day_measurement {
    use std::{cell::Cell, time::Instant};

    thread_local! {
        static TOTALS: Cell<Option<[u128; 5]>> = const { Cell::new(None) };
    }

    pub(super) fn enable() { TOTALS.set(Some([0; 5])); }

    pub(super) fn start() -> Option<Instant> {
        TOTALS.get().map(|_| Instant::now())
    }

    pub(super) fn mark(measure: &mut Option<Instant>, stage: usize) {
        if let Some(previous) = measure {
            let now = Instant::now();
            let mut totals = TOTALS.get().expect("measurement is active");
            totals[stage] += now.duration_since(*previous).as_micros();
            TOTALS.set(Some(totals));
            *previous = now;
        }
    }

    pub(super) fn take() -> [u128; 5] { TOTALS.take().expect("measurement is active") }
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

    pub fn place_polity(&self, place: &str) -> Option<&Polity> {
        self.polities.get(historical_place_polity(self.places.get(place)?))
    }

    pub fn routes(&self) -> &BTreeMap<String, Route> {
        &self.routes
    }

    pub fn population_unit_at(&self, place_id: &str) -> Option<&str> {
        self.place_population_units.get(place_id).map(String::as_str)
    }

    pub fn polity_population_bindings(&self) -> &BTreeMap<String, String> {
        &self.polity_population_bindings
    }

    pub fn population_units(&self) -> impl Iterator<Item = &str> {
        self.population_income.keys().map(String::as_str)
    }

    fn opening_parent_at(&self, place_id: &str) -> Option<&str> {
        let place = self.places.get(place_id)?;
        self.population_unit_at(place_id).or_else(|| match (place.id.as_str(), place.parent_country_id.as_str()) {
            ("dover" | "port_london", "british_empire") => Some("british_isles_1900"),
            ("vienna", "austro_hungarian_empire") => Some("austria_hungary"),
            (_, "united_states") => Some("united_states_1900"),
            (_, id) => self.polities.contains_key(id).then_some(id),
        })
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
        let (polity_units, population_name_aliases) = load_population_bindings(&polities, &populations)?;
        let population_income = countries.iter().map(|(unit, inputs)| (unit.clone(), inputs.income)).collect();
        let markets = MarketInputs::load(countries)?;
        let opening_cash = load_opening_cash()?;
        let (places, routes, cities) = load_map()?;
        let regimental_opening_stations = load_regimental_opening_stations(&places, &polities)?;
        let place_population_units = places.iter().filter_map(|(id, place)| {
            let source = historical_place_polity(place);
            polity_units.get(source).map(|unit| (id.clone(), unit.clone()))
        }).collect();
        let mut world = WorldSources {
            polities, places, routes, place_population_units, polity_population_bindings: polity_units,
            population_name_aliases,
            population_income, historical_population: None, people: BTreeMap::new(), regimental_opening_stations,
        };
        let dated_jurisdictions = crate::transport::opening_place_jurisdictions()?;
        let load_opening = |version| {
            HistoricalOpening::load(version, &populations, |id| world.polities.contains_key(id), |place| {
                world.opening_parent_at(place).or_else(|| dated_jurisdictions.get(place).map(String::as_str))
            })
        };
        // Freeze the existing market asset calibration when the census ledger changes.
        let market_opening_population = load_opening(4)?.totals(&populations);
        let historical_population = Arc::new(load_opening(crate::formal_population::CURRENT_VERSION)?);
        world.historical_population = Some(Arc::clone(&historical_population));
        let mut residents = BTreeMap::new();
        let mut opening_people = BTreeMap::new();
        for &(source, place) in OPENINGS {
            let place = format!("place:{place}");
            if world.population_unit_at(&place).is_none() { continue; }
            let id = format!("person:formal_generated_{source}_0001");
            let claim = format!("formal_population_claim:{source}:0001");
            world.add_opening_person(source, place, id.clone(), claim)?;
            opening_people.insert(source.to_owned(), Arc::new(world.people[&id].clone()));
            residents.insert(id, opening_cash);
        }
        let has_paris = world.population_unit_at("place:paris") == Some("country_fra");
        let enterprise_opening = if has_paris {
            for resident in load_regional_residents()? {
                world.add_opening_person("country_fra", resident.place_id, resident.person_id.clone(), resident.claim_id)?;
                residents.insert(resident.person_id, resident.opening_cash);
            }
            EnterpriseOpening::load()?
        } else {
            EnterpriseOpening::default()
        };
        let network = crate::transport::map_data::load_world_network(&world, 0)?;
        let mut work = WorkOpening::load(|unit, place| {
            let node = network.routing_node(place)?;
            (network.unit_at(node) == Some(unit)).then(|| node.to_owned())
        })?;
        for (polity_id, unit) in &world.polity_population_bindings {
            if opening_people.contains_key(polity_id) || populations[unit] == 0 { continue; }
            let Some(place) = network.capital_node(polity_id) else { continue; };
            if network.node_coordinates(place).is_none() || network.unit_at(place) != Some(unit) { continue; }
            opening_people.insert(polity_id.clone(), Arc::new(OpeningPerson {
                id: format!("person:formal_generated_{polity_id}_0001"),
                claim_id: format!("formal_population_claim:{polity_id}:0001"),
                opening_source_id: polity_id.clone(),
                polity_id: world.polities[polity_id].runtime_id(),
                place_id: place.to_owned(),
                birth_year: 1870,
            }));
        }
        let opening_place_names = opening_people.values().map(|person| {
            let id = &person.place_id;
            let label = world.places.get(id).map(|place| place.name.as_str())
                .or_else(|| network.node_label(id)).unwrap_or(id);
            (person.opening_source_id.clone(), label.to_owned())
        }).collect();
        let organization_directory = OrganizationDirectory::load(&world, &cities, &populations, &markets)?;
        work.register_regional(organization_directory.opening())?;
        let mut activities = load_opening_activities()?;
        activities.written_job_notices.retain(|source, job| opening_people.contains_key(source) && work.entry_job(job).is_some());
        for (source, job) in &activities.written_job_notices {
            let actor = format!("person:formal_generated_{source}_0001");
            if !world.people.get(&actor).is_some_and(|person| {
                work.jobs(&actor, Some(&person.place_id), 0).any(|row| row.id == *job)
            }) { return Err(invalid("written employment notice has no accessible opening job")); }
        }
        Ok(Self {
            world: Arc::new(world),
            archived_population_worlds: Default::default(),
            organization_directory: Arc::new(organization_directory),
            populations,
            market_opening_population,
            historical_population,
            markets: Arc::new(markets),
            residents,
            opening_people,
            opening_place_names,
            opening_cash,
            work: Arc::new(work),
            enterprise_opening: Arc::new(enterprise_opening),
            activities: Arc::new(activities),
        })
    }

    pub fn opening_language(&self, source: &str) -> Option<Language> {
        self.activities.openings.get(source).copied()
    }

    pub fn opening_cash(&self, source: &str, family: wwo_character_core::Family) -> Option<i64> {
        self.opening_people.contains_key(source).then(|| family.opening_cash(self.opening_cash))
    }

    pub fn openings(&self) -> impl Iterator<Item = (&str, &str)> {
        self.opening_place_names.iter().map(|(source, place)| (source.as_str(), place.as_str()))
    }

    pub fn create(&self, source_id: &str) -> io::Result<InitialWorld> {
        self.create_opening(source_id, None, true)
    }

    pub fn create_with_prologue(&self, source_id: &str, prologue: Prologue) -> io::Result<InitialWorld> {
        self.create_opening(source_id, Some(prologue), true)
    }

    fn create_opening(&self, source_id: &str, prologue: Option<Prologue>, historical: bool) -> io::Result<InitialWorld> {
        let mut world = self.base_opening(source_id, prologue, historical)?;
        world.initialize_organization_members()?;
        world.plan_household_orders()?;
        world.settle_organization_employment()?;
        Ok(world)
    }

    fn base_opening(&self, source_id: &str, prologue: Option<Prologue>, historical: bool) -> io::Result<InitialWorld> {
        let version = historical.then(|| self.historical_population.version());
        self.base_opening_version(source_id, prologue, version)
    }

    fn base_opening_version(&self, source_id: &str, prologue: Option<Prologue>, version: Option<u32>) -> io::Result<InitialWorld> {
        let sources = match version {
            Some(version) if version == self.historical_population.version() => &self.world,
            archived if archived.is_none_or(|value| (1..self.historical_population.version()).contains(&value)) => {
                let archived_version = archived.unwrap_or(1);
                self.archived_population_worlds[(archived_version - 1) as usize].get_or_init(|| {
                    let dated_jurisdictions = crate::transport::opening_place_jurisdictions()?;
                    let opening = HistoricalOpening::load(archived_version, &self.populations,
                        |id| self.world.polities.contains_key(id), |place| {
                            self.world.opening_parent_at(place).or_else(|| dated_jurisdictions.get(place).map(String::as_str))
                        })?;
                    Ok(Arc::new(WorldSources { historical_population: Some(Arc::new(opening)), ..self.world.as_ref().clone() }))
                }).as_ref().map_err(|error| invalid(error.to_string()))?
            }
            _ => return Err(invalid("unsupported historical population opening version")),
        };
        let transport = Operations::restore(sources, 0, OperationsState::default())?;
        let player_origin = Arc::clone(self.opening_people.get(source_id)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "unknown formal opening"))?);
        let player = player_origin.id.clone();
        let development = prologue.map(|opening| {
            let language = self.opening_language(source_id).ok_or_else(|| invalid("opening has no configured prologue language"))?;
            opening.build(language).map_err(io::Error::other)
        }).transpose()?;
        let extra = (!self.world.people.contains_key(&player)).then_some(player_origin.as_ref());
        let mut ledger = Ledger::initialize_people(self.residents.iter().map(|(person, &cash)| (person.as_str(), cash))
            .chain(extra.into_iter().map(|person| (person.id.as_str(), self.opening_cash))).map(|(person, cash)| {
            let cash = prologue.filter(|_| person == player).map_or(cash, |opening| opening.family.opening_cash(cash));
            (person, cash)
        }))?;
        self.work.open_accounts(&mut ledger)?;
        ledger.ensure_transport_account()?;
        let mut population = if version.is_some() {
            Population::initialize_historical(&self.populations, Arc::clone(
                sources.historical_population.as_ref().expect("loaded historical opening"),
            ))
        } else {
            Population::initialize(self.populations.clone())
        };
        let mut identities = BTreeMap::new();
        for person in self.world.people.values().chain(extra) {
            let parent = &self.world.polity_population_bindings[&person.opening_source_id];
            let unit = population.partition_at(&person.place_id).unwrap_or(parent.as_str()).to_owned();
            population.claim(&person.id, &unit)?;
            let year = development.as_ref().filter(|_| person.id == player).map_or(person.birth_year, |player| player.birth_year());
            let identity = formal_character::opening_identity(year).map_err(io::Error::other)?;
            identities.insert(person.id.clone(), identity);
        }
        population.seed_opening_demography()?;
        let character = match development {
            Some(development) => formal_character::opening_with_prologue(&player, &identities, development),
            None => formal_character::opening_profile(&player, &identities, 0, ""),
        }.map_err(io::Error::other)?;
        let mut work = WorkState::default();
        work.book_automatic(&self.work, GameClock::default(), |person| {
            self.world.people.get(person).map(|row| row.place_id.as_str())
        });
        let fixed_market_supply = version.is_some_and(|version| version >= 5);
        let market_seed = if fixed_market_supply { &self.market_opening_population } else { population.totals() };
        let mut macro_economy = MacroEconomy::initialize(Arc::clone(&self.markets), market_seed);
        if fixed_market_supply { macro_economy.use_opening_supply(market_seed); }
        Ok(InitialWorld {
            organization_directory: Arc::clone(&self.organization_directory),
            organization_members: OrganizationMembers::default(),
            activity: OrganizationActivity::default(),
            counters: CounterBook::default(),
            sources: Arc::clone(sources),
            clock: GameClock::default(),
            player,
            player_origin,
            identities,
            runtime_people: BTreeMap::new(),
            population,
            macro_economy,
            character,
            ledger,
            holdings: BTreeMap::new(),
            next_living_record: 1,
            settled_purchase_requests: BTreeMap::new(),
            work_opening: Arc::clone(&self.work),
            work,
            wages: WageClaims::initialize(),
            enterprise_opening: Arc::clone(&self.enterprise_opening),
            enterprises: Enterprises::initialize(&self.enterprise_opening, 0),
            livelihood: Livelihood::default(),
            households: Households::default(),
            travel: travel_live::TravelState::default(),
            migration: migration::MigrationState::default(),
            transport,
            travel_preview: None,
            freight_preview: None,
            selected_freight: None,
            freight: freight::FreightBook::default(),
            homes: BTreeMap::new(),
            service: ServiceRoster::default(),
            activities: Arc::clone(&self.activities),
            player_day: PlayerDay {
                written_job_notice: prologue.is_some() && self.activities.written_job_notices.contains_key(source_id),
                ..PlayerDay::default()
            },
            land_battle: None,
            land_battle_history: Vec::new(),
        })
    }

    pub(crate) fn restore_native(&self, saved: WorldSnapshot) -> io::Result<InitialWorld> {
        let version = match &saved.population {
            NativePopulation::Versioned(snapshot) => snapshot.opening_version,
            NativePopulation::Legacy(_) => None,
        };
        let mut world = self.base_opening_version(&saved.opening, None, version)?;
        if saved.opening_place.as_deref().is_some_and(|place| place != world.player().place_id) {
            return Err(invalid("saved opening place differs from the formal opening"));
        }
        if let Some(members) = &saved.organization_members {
            world.restore_organization_jobs(members)?;
        }
        let clock = GameClock::restore(saved.clock)?;
        let day = u32::try_from(clock.current_day()).map_err(|_| invalid("unsupported formal date"))?;
        if saved.character.is_empty() || saved.next_living_record == 0 || saved.next_living_record > MAX_AMOUNT as u64
        { return Err(invalid("invalid formal save state")); }
        for (id, row) in &saved.runtime_people {
            if row.origin.id != *id || !id.strip_prefix("person:").is_some_and(local_id)
                || row.name.trim().is_empty() || row.name.len() > 240
                || row.origin.claim_id != format!("formal_population_claim:{id}")
                || !row.origin.polity_id.is_empty()
                || world.residence_unit_at(&row.origin.place_id) != Some(row.origin.opening_source_id.as_str())
                || !world.can_reside_at(&row.origin.place_id)
                || row.born_day.is_some_and(|birth| birth > day)
                || world.identities.insert(id.clone(), row.identity()?).is_some()
            {
                return Err(invalid("invalid runtime person seed"));
            }
        }
        world.runtime_people = saved.runtime_people;
        let deaths = formal_character::restore_native_identities(&world.player, &mut world.identities, day, &saved.character)
            .map_err(io::Error::other)?;
        let dead = deaths.iter().map(|notice| notice.person_id.as_str()).collect::<BTreeSet<_>>();
        if dead.iter().any(|id| saved.work.has_contract(id))
        { return Err(invalid("formal population or employment disagrees with mortality")); }
        world.population = match saved.population {
            NativePopulation::Versioned(snapshot) => world.population.restore_native(snapshot, saved.clock.total_minutes)?,
            NativePopulation::Legacy(totals) => world.population.migrate_native(totals, dead.iter().copied())?,
        };
        world.population.check_identities(world.identities.keys().map(|id| (id.as_str(), !dead.contains(id.as_str()))))?;
        world.population.check_runtime_origins(world.runtime_people.iter().map(|(id, row)| {
            (id.as_str(), row.origin.opening_source_id.as_str(), row.origin.birth_year, row.born_day)
        }))?;
        if deaths.iter().any(|notice| world.population.death_minute(&notice.person_id)
            .is_some_and(|minute| minute / MINUTES_PER_DAY != i64::from(notice.death.day)))
        {
            return Err(invalid("population and character death dates differ"));
        }
        world.macro_economy = MacroEconomy::restore(Arc::clone(&self.markets), world.population.totals(), &saved.markets, clock)?;
        if version.is_some_and(|version| version >= 5) {
            world.macro_economy.use_opening_supply(&self.market_opening_population);
        }
        world.macro_economy.restore_arrivals(saved.last_arrivals, clock.snapshot().total_minutes)?;
        let mut ledger = Ledger::restore(&saved.ledger, true)?;
        ledger.ensure_transport_account()?;
        self.work.ensure_market_accounts(&mut ledger)?;
        if saved.organization_members.is_none() { self.work.ensure_regional_accounts(&mut ledger)?; }
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
        world.wages = WageClaims::restore_shifts(saved.wages, &world.work_opening, &ledger, clock, |actor| world.identities.contains_key(actor))?;
        world.ledger = ledger;
        world.holdings = saved.holdings;
        world.next_living_record = saved.next_living_record;
        world.settled_purchase_requests = saved.settled_purchase_requests;
        world.work = saved.work;
        world.player_day = saved.player_day;
        world.enterprises = saved.enterprises.unwrap_or_else(|| Enterprises::initialize(&self.enterprise_opening, i64::from(day)));
        world.livelihood = saved.livelihood;
        world.households = saved.households;
        let minute = clock.snapshot().total_minutes;
        world.transport = Operations::restore(&world.sources, minute, saved.transport)?;
        for (route, availability) in saved.transport_restrictions {
            world.set_segment_access(&route, availability.open, availability.capacity_units)?;
        }
        match saved.travel {
            Some(TravelSnapshot::Current(travel)) => world.travel = travel,
            Some(TravelSnapshot::Legacy(travel)) => world.import_legacy_travel(travel)?,
            None => (),
        }
        world.freight = saved.freight;
        world.migration = saved.migration;
        let migrate_organizations = saved.organization_members.is_none();
        world.organization_members = saved.organization_members.unwrap_or_default();
        world.homes = saved.homes;
        world.validate_freight()?;
        world.macro_economy.validate_transport(&world.transport, &world.ledger)?;
        // Main has no admitted strategic or tactical unit roster. Scenario tests may
        // bind a unit to this domain without adding an order to a historical opening.
        world.service = ServiceRoster::restore(saved.service, &world.population, known_service_target)?;
        world.validate_travel()?;
        if !world.enterprises.validate(&self.enterprise_opening, i64::from(day))
            || !world.validate_livelihood(day, world.activities.meal_milli_for_recovery)
            || !world.households.validate(clock.snapshot().total_minutes,
                |person| world.population.unit_for_person(person).is_some(),
                |place| world.can_reside_at(place))
            || !world.work.validate(&world.work_opening, clock, |person| {
                if world.service.named_target(person).is_some() { return None; }
                world.current_place(person)
            }, |person| world.population.unit_for_person(person).is_some())
            || world.homes.iter().any(|(person, home)| {
                !world.can_reside_at(home) || world.population.unit_for_person(person)
                    .is_none_or(|unit| world.residence_unit_at(home) != Some(unit))
            })
            || world.named_people().any(|person| {
                world.person_home(person).and_then(|home| world.residence_unit_at(home))
                    != world.population.unit_for_person(person)
            })
        {
            return Err(invalid("invalid residence, travel, livelihood or enterprise state"));
        }
        world.restore_land_battles(saved.land_battle, saved.land_battle_history)?;
        let invalid_booking = world.player_day.booking.is_some_and(|booking| {
            !world.player_alive() || world.work.booking(&world.player).is_some()
                || !(clock.current_day() * MINUTES_PER_DAY..=minute).contains(&booking.minute)
                || !world.activity_available(booking.kind, booking.minute)
        });
        if world.opening_language().is_some_and(|language| self.opening_language(&saved.opening) != Some(language))
            || !(0..=1000).contains(&world.player_day.food_milli)
            || invalid_booking
            || world.player_day.written_job_notice && (world.opening_language().is_none() || world.player_written_job().is_none())
            || world.player_day.last_read_notice.is_some_and(|notice| {
                !(MINUTES_PER_DAY..=minute).contains(&notice) || notice % MINUTES_PER_DAY != 0
            })
            || world.opening_language().is_none() && (world.player_day.booking.is_some()
                || world.player_day.food_milli > 0 || world.player_day.last_read_notice.is_some())
        { return Err(invalid("invalid saved personal activity")); }
        world.activity = saved.activity;
        world.counters = saved.counters;
        if migrate_organizations { world.initialize_organization_members()?; }
        world.validate_organization_members()?;
        world.validate_organization_activity()?;
        world.validate_counters()?;
        Ok(world)
    }
}

fn known_service_target(target: &ServiceTarget) -> bool {
    cfg!(test) && matches!(target, ServiceTarget::Strategic(id) if id == "fixture:paris_service")
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

fn historical_place_polity(place: &Place) -> &str {
    match (place.id.as_str(), place.parent_country_id.as_str()) {
        ("kolkata", "british_empire") => "cshapes_gw_750",
        ("alexandria" | "port_alexandria", "ottoman_empire") => "khedivate_of_egypt",
        (_, "british_empire") => "british_isles_1900",
        (_, "japanese_empire") => "empire_of_japan",
        (_, "united_states") => "united_states_1900",
        (_, "argentine_republic") => "argentina_1900",
        (_, "country_bel") => "kingdom_of_belgium",
        (_, "austro_hungarian_empire") => "austria_hungary",
        (_, parent) => parent,
    }
}

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

type PopulationBindings = BTreeMap<String, String>;

fn load_population_bindings(
    polities: &BTreeMap<String, Polity>,
    populations: &BTreeMap<String, u64>,
) -> io::Result<(PopulationBindings, PopulationBindings)> {
    #[derive(Deserialize)]
    struct Crosswalk {
        schema_id: String,
        records: Vec<Binding>,
    }
    #[derive(Deserialize)]
    struct Binding {
        economy_entity_id: String,
        polity_ids: Vec<String>,
        mapping_mode: String,
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
    let mut name_aliases = BTreeMap::new();
    for binding in crosswalk.records {
        if !populations.contains_key(&binding.economy_entity_id) {
            return Err(invalid("population crosswalk references an unknown statistical unit"));
        }
        let exact_alias = binding.mapping_mode == "historical_name_alias";
        if exact_alias && binding.polity_ids.len() != 1 {
            return Err(invalid("population name alias must reference one historical polity"));
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
            if exact_alias {
                name_aliases.insert(polity, binding.economy_entity_id.clone());
            }
        }
    }
    if populations.keys().any(|unit| !result.values().any(|bound| bound == unit)) {
        return Err(invalid("formal statistical unit has no political binding"));
    }
    Ok((result, name_aliases))
}

fn load_map() -> io::Result<(BTreeMap<String, Place>, BTreeMap<String, Route>, BTreeSet<String>)> {
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
    let city_keys = city_ids.into_iter().map(str::to_owned).collect();
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
    Ok((places, routes, city_keys))
}

fn load_regimental_opening_stations(
    places: &BTreeMap<String, Place>,
    polities: &BTreeMap<String, Polity>,
) -> io::Result<BTreeMap<String, Vec<RegimentalOpeningStation>>> {
    let stations = read_list::<RegimentalOpeningStation>(
        include_bytes!("../../../data/formal/regimental_opening_stations_1900.json"), "stations",
    )?;
    let mut regiments = BTreeSet::new();
    let mut by_place: BTreeMap<String, Vec<_>> = BTreeMap::new();
    for station in stations {
        if !local_id(&station.regiment_id) || !regiments.insert(station.regiment_id.clone())
            || !places.contains_key(&station.place_id) || !polities.contains_key(&station.polity_id)
            || station.name.trim().is_empty() || station.name_zh.trim().is_empty()
            || station.source.trim().is_empty() || !station.source_url.starts_with("https://")
        {
            return Err(invalid(format!("invalid regimental opening station {}", station.regiment_id)));
        }
        by_place.entry(station.place_id.clone()).or_default().push(station);
    }
    Ok(by_place)
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
    fn opening_regimental_station_uses_formal_lyon_place() {
        let world = WorldBootstrap::load().unwrap().create("country_fra").unwrap();
        let stations = world.regimental_opening_stations("place:lyon");
        let [station] = stations else { panic!("expected the Lyon opening station") };
        assert_eq!(station.regiment_id, "fra_157th_infantry");
        assert_eq!(station.polity_id, "country_fra");
        assert_eq!(station.place_id, "place:lyon");
        assert!(world.regimental_opening_stations("place:paris").is_empty());
        assert!(world.land_battle_record().is_none());
    }

    #[test]
    fn all_six_openings_select_a_person_in_the_same_world_sources() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let france = bootstrap.create("country_fra").unwrap();
        assert_eq!(france.sources.polities().len(), 146);
        assert_eq!(france.population_units().len(), 50);
        for (id, city, flag, population) in [
            ("country_fra", "paris", "france_tricolour_1794", 38_852_748),
            ("british_isles_1900", "london", "uk_union_1801", 41_500_000),
            ("german_empire", "berlin", "german_empire_1867", 55_619_152),
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
            let named = if id == "country_fra" { 6 } else { 4 };
            assert_eq!(world.population.named_counts()[id], named);
            let estimate = world.population.admitted_opening(id).map_or(population, |row| row.population_value);
            assert_eq!(world.background_population(id), Some(estimate - named));
            assert_eq!(world.population.named_counts(), france.population.named_counts());
            let opening_ledger = world.ledger().snapshot();
            let french_ledger = france.ledger().snapshot();
            for key in ["accounts", "transactions", "scenario_budget", "denomination"] {
                let field = |value| crate::formal_save::field(crate::formal_save::map(value).unwrap(), key).unwrap();
                assert_eq!(field(&opening_ledger), field(&french_ledger));
            }
            world.validate_counters().unwrap();
            assert_eq!(world.balance().unwrap().reserved, 0);
            let resident = "person:formal_generated_country_fra_0002";
            assert_eq!(world.person(resident).unwrap().place_id, "place:paris");
            assert_eq!(world.ledger().default_account(resident).unwrap().cash, 0);
            assert_eq!(world.person_profile(resident).unwrap().age_years, 30);
        }
        assert!(bootstrap.create("british_empire").is_err());
        assert!(bootstrap.create("japanese_empire").is_err());
    }

    #[test]
    fn historical_partition_changes_residence_and_replays_one_service_claim() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let national = "united_states_1900";
        let dc = "us_district_of_columbia";
        let ny = "us_state_new_york";
        let resident = "person:historical_partition_resident";
        let target = ServiceTarget::Strategic("fixture:paris_service".into());
        let parts = world.population().partitions(national).collect::<Vec<_>>();
        assert_eq!(parts.len(), 49);
        assert_eq!(parts.iter().map(|(_, _, count)| count).sum::<u64>(), 75_454_976);
        assert_eq!(world.population_units()[national], 75_454_976);
        assert_eq!(world.population().resident_pool(national), Some(0));
        assert!(!world.macro_economy().markets().contains_key(dc));
        assert!(world.transfer_unmanaged_population(national, ny, 1, 0).is_err());
        let (cohort, _, members) = world.population().cohorts_in(dc)
            .find(|(id, _, count)| *count > 10 && world.population().cohort_can_materialize(id, 1875))
            .unwrap();
        let cohort = cohort.clone();
        world.population.transfer_cohort(dc, ny, &cohort, 10, 0).unwrap();
        assert_eq!(world.population().cohort_members(ny, &cohort), Some(10));
        assert_eq!(world.population().population_total(dc), Some(276_709));
        assert_eq!(world.population().population_total(ny), Some(7_216_556));
        assert_eq!(world.population().admitted_opening(dc).unwrap().population_value, 276_719);
        assert_eq!(world.population_units()[national], 75_454_976);
        world.materialize_resident(resident, "Resident".into(), "place:washington", 1875, Some(&cohort)).unwrap();
        assert_eq!(world.population().cohort_members(dc, &cohort), Some(members - 11));
        assert_eq!(world.population().unit_for_person(resident), Some(dc));
        assert_eq!(world.market_unit_for_person(resident), Some(national));
        assert_eq!(world.population().background(dc), Some(276_708));
        assert_eq!(world.population().background(national), Some(75_454_975));
        world.enlist_named_service(resident, target.clone(), true).unwrap();
        assert!(world.enlist_named_service(resident, target.clone(), true).is_err());
        let saved = world.snapshot();
        assert_eq!(saved["population"]["opening_version"], crate::formal_population::CURRENT_VERSION);
        let restored = bootstrap.restore_native(serde_json::from_value(saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.service.named_target(resident), Some(&target));
        assert_eq!(restored.snapshot(), saved);
    }

    #[test]
    fn historical_partition_admits_only_manifest_overrides() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let population = world.population();
        assert!(world.population_units().keys().eq(bootstrap.populations.keys()));
        assert!(world.macro_economy().markets().keys().eq(bootstrap.populations.keys()));
        assert!(!population.standalone_totals().is_empty());
        let london = "uk_ancient_kent_middlesex_surrey";
        assert_eq!(world.residence_unit_at("place:london"), Some(london));
        assert_eq!(world.residence_unit_at("place:port_london"), Some(london));
        assert_eq!(population.admitted_opening(london).unwrap().source_id, "england_wales_summary_tables_1901");
        let india = "cshapes_gw_750";
        assert!(population.admitted_opening(india).is_none());
        assert_eq!(population.population_total(india), Some(294_000_000));
        assert_eq!(population.population_total("raj_mysore_state"), Some(5_470_284));
        assert!(population.resident_pool(india).is_some_and(|n| n > 0 && n < 294_000_000));
        let mut admitted = 0;
        let mut baseline_only = 0;
        let mut whole_roots = 0;
        let mut partitioned_roots = 0;
        for (root, &value) in world.population_units().iter().chain(population.standalone_totals()) {
            let mut partitions = population.partitions(root).peekable();
            if let Some(estimate) = population.admitted_opening(root) {
                assert_eq!(value, estimate.population_value);
                admitted += 1;
            } else {
                assert_eq!(value, bootstrap.populations[root]);
                baseline_only += 1;
            }
            if partitions.peek().is_none() {
                assert_eq!(population.resident_pool(root), Some(value));
                whole_roots += 1;
            } else {
                let unassigned = population.resident_pool(root).unwrap();
                assert_eq!(unassigned + partitions.map(|(_, _, count)| count).sum::<u64>(), value);
                if let Some(estimate) = population.admitted_opening(root) {
                    assert_eq!(unassigned, estimate.research_unlocated_balance.unwrap_or(0));
                }
                partitioned_roots += 1;
            }
        }
        assert!(admitted > 0 && baseline_only > 0 && whole_roots > 0 && partitioned_roots > 0);
        for person in world.sources.people.values() {
            let unit = population.unit_for_person(&person.id).unwrap();
            assert_eq!(world.residence_unit_at(&person.place_id), Some(unit));
            assert_eq!(population.parent_unit(unit), Some(person.opening_source_id.as_str()));
        }
    }

    #[test]
    fn historical_social_scopes_preserve_parent_counts_and_unknown_leaves() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let central_india = "raj_central_india_agency";
        let gwalior = "raj_gwalior_state";
        let rest = "raj_central_india_ex_gwalior";
        let before = world.population().social_distribution(Some(central_india)).unwrap();
        assert_eq!(before.population_total, 8_824_834);
        assert_eq!(before.dimensions["occupation"].assigned_residents, 4_585_285);
        assert_eq!(before.dimensions["residence"].assigned_residents, before.population_total);
        assert_eq!(before.residents_with_any_attribute_minimum, before.population_total);
        assert_eq!(before.residents_with_any_attribute_maximum, before.population_total);
        let gwalior_social = world.population().social_distribution(Some(gwalior)).unwrap();
        assert_eq!(gwalior_social.population_total, 2_984_713);
        assert_eq!(gwalior_social.dimensions["occupation"].unknown_residents, gwalior_social.population_total);
        assert_eq!(gwalior_social.dimensions["residence"].by_classification["india_1901_census_towns_and_rural"]["Urban"], 330_852);
        let glamorgan = world.population().social_distribution(Some("administrative_region:gb_historic_glamorgan")).unwrap();
        let housing = &glamorgan.dimensions["housing"];
        assert_eq!(housing.direct_opening_distribution.unwrap().observed_total, 859_931);
        assert_eq!(housing.assigned_residents, 838_431);
        assert_eq!(housing.unknown_residents, 0);

        let (cohort, _, _) = world.population().cohorts_in(gwalior).next().unwrap();
        let cohort = cohort.clone();
        world.population.transfer_cohort(gwalior, rest, &cohort, 1, 0).unwrap();
        let after = world.population().social_distribution(Some(central_india)).unwrap();
        assert_eq!(after.population_total, 8_824_834);
        assert_eq!(after.affected_resident_pools, 2);
        assert!(after.dimensions["occupation"].assigned_residents < 4_585_285);
        assert_eq!(after.dimensions["residence"].unknown_residents, 2);
        assert!(after.residents_with_any_attribute_minimum <= after.residents_with_any_attribute_maximum);
        assert_eq!(after.residents_with_any_attribute_maximum, after.population_total);
        let restored = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        let replayed = restored.population().social_distribution(Some(central_india)).unwrap();
        assert_eq!(serde_json::to_value(replayed).unwrap(), serde_json::to_value(after).unwrap());
    }

    #[test]
    fn historical_russian_districts_keep_province_totals_and_census_residence() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        for (province, district, count, province_total, district_total, urban) in [
            (40, 344, 12, 3_760_260, 572_067, 261_715),
            (43, 363, 15, 2_935_065, 258_726, 76_588),
            (57, 533, 12, 2_674_222, 289_298, 85_151),
            (79, 700, 7, 2_906_736, 428_925, 16_023),
        ] {
            let province = format!("administrative_region:ristat_province_{province}");
            let district = format!("administrative_region:ristat_district_{district}");
            let parent = world.inspect_population(&province).unwrap();
            assert_eq!(parent.children.len(), count);
            assert_eq!(parent.population_total, Some(province_total));
            assert_eq!(parent.children.iter().map(|child| child.population_total).sum::<u64>(), province_total);
            let child = world.inspect_population(&district).unwrap();
            assert_eq!(child.parent_id, Some(province.as_str()));
            assert_eq!(child.population_total, Some(district_total));
            let structure = child.structure.unwrap();
            assert_eq!(structure.cohort_residents, district_total);
            let social = child.social.unwrap();
            let residence = &social.dimensions["residence"];
            assert_eq!(residence.by_classification["russia_1897_administrative_residence"]["Census cities"], urban);
            assert_eq!(residence.unknown_residents, 0);
            assert_eq!(social.dimensions["religion"].unknown_residents, district_total);
        }
        let total = world.population().population_total("russian_empire");
        assert_eq!(total, Some(135_382_043));
    }

    #[test]
    fn historical_indian_age_tables_preserve_local_totals_and_unknown_ages() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        for (unit, total, unknown_age) in [
            ("raj_andaman_nicobar_comparable", 16_181, 0),
            ("raj_united_provinces_states", 800_983, 298),
            ("raj_central_provinces_states", 2_015_423, 0),
        ] {
            let structure = world.population().structure(Some(unit), world.clock()).unwrap();
            assert_eq!(structure.population_total, total);
            assert_eq!(structure.cohort_residents, total);
            assert_eq!(structure.residents_with_cohort_age_and_sex, total - unknown_age);
        }
    }

    #[test]
    fn historical_austrian_census_uses_matching_territories_and_retains_language_unknowns() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let unit = "ah_lower_austria";
        let report = world.inspect_population(unit).unwrap();
        assert_eq!(report.population_total, Some(3_056_648));
        let structure = report.structure.unwrap();
        assert_eq!(structure.residents_with_cohort_age_and_sex, 3_056_648);
        assert_eq!(structure.cohorts.len(), 22);
        let social = report.social.unwrap();
        let religion = &social.dimensions["religion"];
        assert_eq!(religion.direct_opening_distribution.unwrap().observed_total, 3_100_493);
        assert_eq!(religion.by_classification["austria_1900_reported_religion"]["Jewish"], 155_054);
        let jewish_norm = report.dietary_norms.iter()
            .find(|norm| norm.trait_id == "leviticus_11_7_12_food_restrictions").unwrap();
        assert_eq!(jewish_norm.residents_with_matching_religion, 155_054);
        assert!(jewish_norm.observed_adherents.is_none());
        assert_eq!(social.dimensions["marital_status"].unknown_residents, 0);
        let language = &social.dimensions["language"];
        assert_eq!(language.direct_opening_distribution.unwrap().observed_unknown, 243_792);
        assert!(language.unknown_residents > 0);
        assert_eq!(language.assigned_residents + language.unknown_residents, 3_056_648);
        assert_eq!(social.dimensions["literacy"].assigned_residents, 3_056_648);
        assert_eq!(social.dimensions["residence"].by_classification["austria_1900_locality_population_size"].len(), 6);
        assert_eq!(social.dimensions["culture"].assigned_residents, 0);
        assert_eq!(report.dietary_norms[0].residents_with_matching_religion, 878);
        assert_eq!(report.dietary_norms[0].observed_adherents, None);

        let old = bootstrap.base_opening_version("country_fra", None, Some(15)).unwrap();
        let previous = old.inspect_population(unit).unwrap();
        assert_eq!(previous.population_total, report.population_total);
        assert_eq!(previous.structure.unwrap().residents_with_cohort_age_and_sex, 0);
        assert_eq!(previous.social.unwrap().dimensions["religion"].assigned_residents, 0);
    }

    #[test]
    fn historical_argentine_and_australian_ages_preserve_coverage_gaps() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.base_opening_version("country_fra", None, Some(31)).unwrap();
        let old = bootstrap.base_opening_version("country_fra", None, Some(29)).unwrap();
        assert_eq!(world.population().global_total(), old.population().global_total());

        let argentina = world.inspect_population("argentina_1900").unwrap();
        assert_eq!(argentina.population_total, Some(4_624_686));
        let profile = argentina.structure.unwrap();
        assert_eq!(profile.residents_with_cohort_age_and_sex, 4_505_257);
        assert_eq!(profile.cohort_residents, 4_524_861);
        assert_eq!(profile.unclassified_residents, 99_825);
        assert_eq!(argentina.children.len(), 4);
        assert_eq!(argentina.children.iter().map(|child| child.population_total).sum::<u64>(), 4_624_686);
        let capital = world.inspect_population("place:buenos_aires").unwrap();
        assert_eq!(capital.account_id, Some("ar_capital_federal"));
        assert_eq!(capital.population_total, Some(772_173));
        assert_eq!(capital.structure.unwrap().residents_with_cohort_age_and_sex, 768_331);
        let religion = &capital.social.unwrap().dimensions["religion"];
        assert_eq!(religion.assigned_residents, 771_251);
        assert_eq!(religion.unknown_residents, 922);
        assert_eq!(capital.dietary_norms[0].residents_with_matching_religion, 876);
        assert_eq!(capital.dietary_norms[0].observed_adherents, None);
        let province = world.inspect_population("ar_buenos_aires_province").unwrap();
        assert_eq!(province.population_total, Some(1_072_742));
        assert_eq!(province.structure.unwrap().residents_with_cohort_age_and_sex, 1_069_246);
        let rosario = world.inspect_population("place:rosario").unwrap();
        assert_eq!(rosario.scope_relation, "residence_site_in_account");
        assert_eq!(rosario.population_total, None);

        let java = world.inspect_population("java_madoera_colonial_population").unwrap();
        assert_eq!(java.population_total, Some(28_092_332));
        let profile = java.structure.unwrap();
        assert_eq!(profile.cohort_residents, 27_798_112);
        assert_eq!(profile.residents_with_cohort_age_and_sex, 0);
        assert_eq!(profile.unclassified_residents, 294_220);
        let before = bootstrap.base_opening_version("country_fra", None, Some(30)).unwrap();
        assert_eq!(before.inspect_population("java_madoera_colonial_population").unwrap()
            .structure.unwrap().cohort_residents, 0);
        assert_eq!(before.inspect_population("place:buenos_aires").unwrap().population_total, None);

        let australia = world.inspect_population("australia_colonies_1900").unwrap();
        assert_eq!(australia.population_total, Some(3_837_578));
        let profile = australia.structure.unwrap();
        assert_eq!(profile.residents_with_cohort_age_and_sex, 3_703_086);
        assert_eq!(profile.cohort_residents, 3_716_123);
        assert_eq!(profile.unclassified_residents, 121_455);
        let south = world.inspect_population("abs_south_australia").unwrap();
        assert_eq!(south.population_total, Some(359_306));
        assert_eq!(south.structure.unwrap().residents_with_cohort_age_and_sex, 358_758);

        for unit in ["argentina_1900", "australia_colonies_1900"] {
            let before = old.inspect_population(unit).unwrap().structure.unwrap();
            assert_eq!(before.residents_with_cohort_age_and_sex, 0);
        }
        let cochin = world.inspect_population("raj_cochin_state").unwrap().social.unwrap();
        assert_eq!(cochin.dimensions["language"].assigned_residents, 801_687);
        assert_eq!(cochin.dimensions["language"].unknown_residents, 0);
        assert_eq!(cochin.dimensions["occupation"].assigned_residents, 368_764);
        let bengal = world.inspect_population("raj_bengal_province").unwrap().social.unwrap();
        assert_eq!(bengal.dimensions["occupation"].assigned_residents, 29_712_198);
        let agra_oudh = world.inspect_population("raj_agra_oudh").unwrap().social.unwrap();
        assert_eq!(agra_oudh.dimensions["occupation"].assigned_residents, 22_793_163);
        let central = world.inspect_population("raj_central_provinces").unwrap().social.unwrap();
        assert_eq!(central.dimensions["occupation"].assigned_residents, 6_626_834);
        let old_central = before.inspect_population("raj_central_provinces").unwrap().social.unwrap();
        assert_eq!(old_central.dimensions["occupation"].assigned_residents, 0);
        let old_bengal = old.inspect_population("raj_bengal_province").unwrap().social.unwrap();
        assert_eq!(old_bengal.dimensions["occupation"].assigned_residents, 0);

        let latest = bootstrap.create("country_fra").unwrap();
        let argentina = latest.inspect_population("argentina_1900").unwrap();
        assert_eq!(argentina.population_total, Some(4_624_686));
        let profile = argentina.structure.unwrap();
        assert_eq!(profile.residents_with_cohort_age_and_sex, 4_502_031);
        assert_eq!(profile.cohort_residents, 4_524_112);
        assert_eq!(profile.unclassified_residents, 100_574);
        let literacy = &argentina.social.unwrap().dimensions["literacy"];
        assert_eq!(literacy.assigned_residents, 3_713_957);
        assert_eq!(literacy.unknown_residents, 910_729);
        let chaco = latest.inspect_population("ar_central_chaco_comparable").unwrap();
        assert_eq!(chaco.structure.unwrap().residents_with_cohort_age_and_sex, 1_072_009);
        let puna = latest.inspect_population("ar_puna_1899_geography_unlocated").unwrap();
        assert_eq!(puna.structure.unwrap().unclassified_residents, 749);

        let java = latest.inspect_population("java_madoera_colonial_population").unwrap();
        assert_eq!(java.population_total, Some(28_092_332));
        let profile = java.structure.unwrap();
        assert_eq!(profile.cohort_residents, 27_798_112);
        assert_eq!(profile.residents_with_cohort_age_and_sex, 17_092_483);
        assert_eq!(profile.unclassified_residents, 294_220);
    }

    #[test]
    fn historical_sichuan_and_philippines_keep_separate_scope_balances() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let old = bootstrap.base_opening_version("country_fra", None, Some(28)).unwrap();
        let sichuan = world.inspect_population("qing_hist_sichuan").unwrap();
        assert_eq!(sichuan.population_total, old.inspect_population("qing_hist_sichuan").unwrap().population_total);
        assert_eq!(sichuan.population_total, Some(42_424_139));
        assert_eq!(sichuan.children.len(), 19);
        assert_eq!(sichuan.children.iter().map(|unit| unit.population_total).sum::<u64>(), 42_424_139);
        let west = world.inspect_population("qing_hist_sichuan_unlocated").unwrap();
        assert_eq!(west.population_total, Some(2_791_411));
        assert_eq!(west.structure.unwrap().residents_with_cohort_age_and_sex, 0);
        let islands = world.inspect_population("cshapes_gw_840").unwrap();
        assert_eq!(islands.population_total, Some(6_961_339));
        assert_eq!(islands.structure.unwrap().unclassified_residents, 6_961_339);
        assert!(islands.children.is_empty());
        assert!(old.inspect_population("cshapes_gw_840").unwrap().population_total.is_none());
        assert_eq!(world.population().global_total() - old.population().global_total(), 6_961_339);
        for unit in ["qing_empire", "united_states_1900", "kingdom_of_spain"] {
            assert_eq!(world.population().population_total(unit), old.population().population_total(unit));
        }
    }

    #[test]
    fn historical_shaangan_prefectures_preserve_provinces_and_unknown_attributes() {
        let world = WorldBootstrap::load().unwrap().create("country_fra").unwrap();
        for (unit, population, count) in [
            ("qing_hist_shaanxi", 8_680_861, 11),
            ("qing_hist_gansu", 6_389_222, 10),
        ] {
            let report = world.inspect_population(unit).unwrap();
            assert_eq!(report.population_total, Some(population));
            assert_eq!(report.direct_residents, None);
            assert_eq!(report.children.len(), count);
            assert_eq!(report.children.iter().map(|child| child.population_total).sum::<u64>(), population);
        }
        let scope = world.inspect_population("qing_hist_shaanxi_xian_hanzhong").unwrap();
        assert_eq!(scope.parent_id, Some("qing_hist_shaanxi"));
        assert_eq!(scope.population_total, Some(3_279_041));
        assert_eq!(scope.structure.unwrap().residents_with_cohort_age_and_sex, 0);
        assert_eq!(scope.social.unwrap().dimensions["occupation"].unknown_residents, 3_279_041);
        assert_eq!(world.population().population_total("qing_empire"), Some(400_000_000));
    }

    #[test]
    fn historical_german_civil_status_and_canadian_occupations_match_census_scopes() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let unit = "administrative_region:germany_sachsen";
        let world = bootstrap.create("country_fra").unwrap();
        let saxony = world.inspect_population(unit).unwrap();
        assert_eq!(saxony.population_total, Some(4_126_352));
        assert_eq!(saxony.structure.unwrap().residents_with_cohort_age_and_sex, 4_126_352);
        let social = saxony.social.unwrap();
        assert_eq!(social.dimensions["marital_status"].assigned_residents, 4_126_352);
        assert_eq!(social.dimensions["marital_status"].by_classification["saxony_1900_reported_marital_status"]["Married"], 1_537_122);
        let wuerttemberg = world.inspect_population("administrative_region:germany_wuerttemberg").unwrap();
        assert_eq!(wuerttemberg.population_total, Some(2_153_315));
        assert_eq!(wuerttemberg.structure.unwrap().residents_with_cohort_age_and_sex, 2_153_315);
        assert_eq!(wuerttemberg.social.unwrap().dimensions["marital_status"].assigned_residents, 2_153_315);

        let ledger = world.population();
        let quebec = ledger.social_distribution(Some("ca_quebec_and_unorganized_territories")).unwrap();
        let occupation = &quebec.dimensions["occupation"];
        assert_eq!((occupation.assigned_residents, occupation.unknown_residents), (520_818, 1_158_263));
        let source = occupation.direct_opening_distribution.unwrap();
        assert_eq!((source.observed_total, source.observed_unknown), (1_701_607, 1_173_802));
        let canada = ledger.social_distribution(Some("dominion_of_canada")).unwrap();
        assert_eq!(canada.dimensions["occupation"].assigned_residents, 1_774_092);
        let v19 = bootstrap.base_opening_version("country_fra", None, Some(19)).unwrap();
        assert_eq!(v19.population().social_distribution(None).unwrap().dimensions["occupation"].assigned_residents, 59_646_786);
        let previous = bootstrap.base_opening_version("country_fra", None, Some(18)).unwrap();
        assert_eq!(previous.inspect_population(unit).unwrap().structure.unwrap().residents_with_cohort_age_and_sex, 0);
        assert_eq!(previous.population().social_distribution(Some("dominion_of_canada")).unwrap().dimensions["occupation"].assigned_residents, 0);
    }

    #[test]
    fn historical_taiwan_register_has_a_separate_control_and_unlocated_residents() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let report = world.inspect_population("taiwan_under_japan").unwrap();
        assert_eq!(report.population_total, Some(2_796_343));
        assert_eq!(report.direct_residents, Some(38_182));
        assert_eq!(report.children.len(), 6);
        assert_eq!(report.children.iter().map(|child| child.population_total).sum::<u64>(), 2_758_161);
        let tainan = world.inspect_population("tw_register_tainan").unwrap();
        assert_eq!(tainan.parent_id, Some("taiwan_under_japan"));
        assert_eq!(tainan.population_total, Some(1_005_179));
        let tainan_structure = tainan.structure.unwrap();
        assert_eq!(tainan_structure.unclassified_residents, 2_381);
        assert_eq!(tainan_structure.cohort_residents, 1_002_798);
        let taiwan_structure = report.structure.unwrap();
        assert_eq!(taiwan_structure.residents_with_cohort_age_and_sex, 2_563_147);
        assert_eq!(taiwan_structure.unclassified_residents, 40_563);
        let yilan = world.inspect_population("tw_register_yilan").unwrap().structure.unwrap();
        assert_eq!(yilan.cohort_residents, 99_547);
        assert_eq!(yilan.residents_with_cohort_age_and_sex, 0);
        let old = bootstrap.base_opening_version("country_fra", None, Some(20)).unwrap();
        assert_eq!(old.population().population_total("taiwan_under_japan"), None);
        for scope in ["qing_empire", "empire_of_japan"] {
            assert_eq!(world.population().population_total(scope), old.population().population_total(scope));
        }
    }

    #[test]
    fn historical_italian_and_mexican_age_and_social_tables_preserve_census_scope() {
        let world = WorldBootstrap::load().unwrap().base_opening_version("country_fra", None, Some(21)).unwrap();
        for (scope, total, known_age) in [
            ("kingdom_of_italy", 32_296_914, 32_295_479),
            ("mexican_republic", 13_447_810, 13_423_676),
        ] {
            let report = world.inspect_population(scope).unwrap();
            assert_eq!(report.population_total, Some(total));
            let structure = report.structure.unwrap();
            assert_eq!(structure.cohort_residents, total);
            assert_eq!(structure.residents_with_cohort_age_and_sex, known_age);
        }
        let italy = world.inspect_population("kingdom_of_italy").unwrap().social.unwrap();
        let marriage = &italy.dimensions["marital_status"];
        assert_eq!(marriage.assigned_residents, 32_296_914);
        assert_eq!(marriage.direct_opening_distribution.as_ref().unwrap().observed_total, 32_475_253);
        let mexico = world.inspect_population("mexican_republic").unwrap().social.unwrap();
        assert_eq!(mexico.dimensions["occupation"].assigned_residents, 8_352_122);
        assert_eq!(mexico.dimensions["language"].assigned_residents, 13_447_810);
        assert_eq!(mexico.dimensions["religion"].unknown_residents, 1);
        let durango = world.inspect_population("mx_durango").unwrap().social.unwrap();
        assert_eq!(durango.dimensions["religion"].direct_opening_distribution.as_ref().unwrap().observed_total, 370_294);
        let coahuila = world.inspect_population("mx_coahuila").unwrap().social.unwrap();
        assert_eq!(coahuila.dimensions["occupation"].unknown_residents, 287_792);
        assert_eq!(coahuila.dimensions["religion"].assigned_residents, 287_792);
    }

    #[test]
    fn historical_local_italy_india_and_canadian_ancestry_preserve_their_sources() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let italy = world.inspect_population("kingdom_of_italy").unwrap();
        assert_eq!(italy.population_total, Some(32_296_914));
        assert_eq!(italy.social.unwrap().dimensions["marital_status"].assigned_residents, 32_296_914);
        let civil_status = world.inspect_population("it_1901_civil_status_scope").unwrap();
        assert_eq!(civil_status.children.len(), 17);
        assert_eq!(civil_status.children.iter().map(|child| child.population_total).sum::<u64>(), 32_296_914);
        let site = world.inspect_population("place:milan").unwrap();
        assert_eq!(site.account_id, Some("it_1901_lombardia"));
        assert_eq!(site.population_total, None);
        let lombardy = world.inspect_population("it_1901_lombardia").unwrap();
        assert_eq!(lombardy.population_total, Some(4_254_990));
        assert_eq!(lombardy.structure.unwrap().cohort_residents, 4_254_990);
        assert_eq!(lombardy.social.unwrap().dimensions["marital_status"].unknown_residents, 4_254_990);

        let mysore = world.inspect_population("raj_mysore_state").unwrap();
        assert_eq!(mysore.children.len(), 5);
        assert_eq!(mysore.children.iter().map(|child| child.population_total).sum::<u64>(), 5_470_284);
        let states = world.inspect_population("raj_united_provinces_states").unwrap();
        assert_eq!(states.children.len(), 2);
        assert_eq!(states.children.iter().map(|child| child.population_total).sum::<u64>(), 800_983);
        let rampur = world.inspect_population("raj_rampur_state").unwrap();
        assert_eq!(rampur.population_total, Some(535_305));
        let structure = rampur.structure.unwrap();
        assert_eq!(structure.residents_with_cohort_age_and_sex, 535_107);

        let canada = world.inspect_population("dominion_of_canada").unwrap();
        let ancestry = &canada.social.unwrap().dimensions["culture"];
        assert_eq!(ancestry.assigned_residents, 5_273_225);
        assert_eq!(ancestry.unknown_residents, 31_089);
        let before = bootstrap.base_opening_version("country_fra", None, Some(21)).unwrap();
        assert_eq!(before.population().population_total("it_1901_lombardia"), None);
        assert_eq!(before.population().population_total("raj_rampur_state"), None);
        assert_eq!(before.inspect_population("dominion_of_canada").unwrap().social.unwrap()
                   .dimensions["culture"].assigned_residents, 0);
    }

    #[test]
    fn historical_brazilian_local_ages_italian_residence_and_mysore_sex_close() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let brazil = world.inspect_population("brazil_1900").unwrap();
        assert_eq!(brazil.children.len(), 21);
        let structure = brazil.structure.unwrap();
        assert_eq!(structure.population_total, 17_021_073);
        assert_eq!(structure.residents_with_cohort_age_and_sex, 16_894_202);
        let capital = world.inspect_population("br_federal_district_1900").unwrap();
        assert_eq!(capital.population_total, Some(674_729));
        assert!(capital.structure.unwrap().cohorts.iter().filter_map(|cohort| cohort.evidence.as_ref())
            .all(|source| source.uncertainty.contains("enumeration was annulled")));

        let italy = world.inspect_population("kingdom_of_italy").unwrap().social.unwrap();
        let residence = &italy.dimensions["residence"];
        assert_eq!(residence.assigned_residents, 32_296_914);
        assert_eq!(residence.by_classification["italy_1901_settlement_pattern"].len(), 3);
        let station = world.inspect_population("raj_bangalore_civil_military_station").unwrap();
        let station_structure = station.structure.unwrap();
        assert_eq!(station_structure.population_total, 90_815);
        let men: u64 = station_structure.cohorts.iter()
            .filter(|cohort| cohort.sex == Some(crate::formal_population::CohortSex::Male))
            .map(|cohort| cohort.members).sum();
        assert_eq!(men, 45_710);

        let old = bootstrap.base_opening_version("country_fra", None, Some(22)).unwrap();
        let old_brazil = old.inspect_population("brazil_1900").unwrap();
        assert_eq!(old_brazil.population_total, Some(17_021_073));
        assert_eq!(old_brazil.structure.unwrap().residents_with_cohort_age_and_sex, 0);
        assert_eq!(old.inspect_population("kingdom_of_italy").unwrap().social.unwrap()
                   .dimensions["residence"].assigned_residents, 0);
    }

    #[test]
    fn historical_oudh_italy_egypt_and_spain_opening_counts_close() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.base_opening_version("country_fra", None, Some(24)).unwrap();
        let agra_oudh = world.inspect_population("raj_agra_oudh").unwrap();
        assert_eq!(agra_oudh.children.len(), 13);
        assert_eq!(agra_oudh.children.iter().map(|child| child.population_total).sum::<u64>(), 47_600_781);
        assert_eq!(agra_oudh.structure.unwrap().cohort_residents, 47_600_781);
        let lucknow = world.inspect_population("raj_oudh_lucknow").unwrap();
        assert_eq!(lucknow.population_total, Some(791_028));
        assert_eq!(lucknow.parent_id, Some("raj_agra_oudh"));
        assert_eq!(world.inspect_population("place:lucknow").unwrap().account_id, Some("raj_oudh_lucknow"));
        assert_eq!(lucknow.structure.as_ref().unwrap().cohort_residents, 791_028);
        let lucknow_religion = &lucknow.social.unwrap().dimensions["religion"];
        assert_eq!(lucknow_religion.assigned_residents, 791_028);
        assert!(lucknow_religion.by_classification["india_1901_reported_religion"].contains_key("Brahmos"));

        let lombardy = world.inspect_population("it_1901_lombardia").unwrap().social.unwrap();
        let occupation = &lombardy.dimensions["occupation"];
        let opening = occupation.direct_opening_distribution.as_ref().unwrap();
        assert_eq!(opening.observed_total, 4_282_728);
        assert_eq!(occupation.by_classification["italy_1901_reported_occupation"].len(), 6);
        assert_eq!(occupation.assigned_residents + occupation.unknown_residents, 4_254_990);
        assert_eq!(lombardy.dimensions["class"].assigned_residents, 0);
        let property = &lombardy.dimensions["property_declaration"];
        assert_eq!(property.assigned_residents, 4_254_990);
        assert_eq!(property.by_classification["italy_1901_registered_real_property"].len(), 4);
        assert_eq!(lombardy.dimensions["literacy"].assigned_residents, 4_254_990);
        let piemonte = world.inspect_population("it_1901_piemonte").unwrap().social.unwrap();
        let industrial_position = &piemonte.dimensions["class"];
        assert_eq!(industrial_position.by_classification["italy_1901_industrial_position"].len(), 4);
        assert_eq!(industrial_position.assigned_residents + industrial_position.unknown_residents, 3_308_662);

        let faiyum = world.inspect_population("egy_mudiriya_faiyum").unwrap();
        let religion = &faiyum.social.unwrap().dimensions["religion"];
        assert_eq!(religion.unknown_residents, 0);
        assert_eq!(religion.assigned_residents, faiyum.population_total.unwrap());
        let norm = &faiyum.dietary_norms[0];
        assert_eq!(norm.residents_with_matching_religion,
            religion.by_classification["egypt_1897_reported_religion"]["Muslim"]);
        assert_eq!(norm.observed_adherents, None);

        let spain = world.inspect_population("kingdom_of_spain").unwrap();
        assert_eq!(spain.population_total, Some(18_511_807));
        let spain_structure = spain.structure.unwrap();
        assert_eq!(spain_structure.cohort_residents, 18_511_807);
        assert!(spain_structure.cohorts.iter().any(|cohort| cohort.age_years.is_none()));
        let marriage = &spain.social.unwrap().dimensions["marital_status"];
        assert_eq!(marriage.assigned_residents + marriage.unknown_residents, 18_511_807);
        assert_eq!(marriage.unknown_residents, 5_997);

        let old = bootstrap.base_opening_version("country_fra", None, Some(23)).unwrap();
        assert_eq!(old.population().population_total("raj_oudh_lucknow"), None);
        assert_eq!(old.population().population_total("raj_agra_oudh"), Some(47_600_781));
        let old_italy = old.inspect_population("it_1901_lombardia").unwrap().social.unwrap();
        assert_eq!(old_italy.dimensions["occupation"].assigned_residents, 0);
        assert!(!old_italy.dimensions.contains_key("property_declaration"));
    }

    #[test]
    fn historical_spanish_belgian_faiyum_and_brazilian_opening_counts_close() {
        let world = WorldBootstrap::load().unwrap().create("country_fra").unwrap();
        let spain = world.inspect_population("kingdom_of_spain").unwrap();
        assert_eq!(spain.children.len(), 10);
        assert_eq!(spain.children.iter().map(|child| child.population_total).sum::<u64>(), 18_511_807);
        let barcelona = world.inspect_population("es_census_1900_province_08").unwrap();
        assert_eq!(barcelona.population_total, Some(1_052_534));
        assert!(barcelona.structure.unwrap().cohorts.iter().all(|cohort| {
            cohort.evidence.as_ref().is_some_and(|evidence| evidence.source_id == "es_census_1900_age_marital")
        }));
        let marriage = &barcelona.social.unwrap().dimensions["marital_status"];
        assert_eq!(marriage.direct_opening_distribution.as_ref().unwrap().observed_total, 1_054_541);
        assert_eq!(marriage.assigned_residents + marriage.unknown_residents, 1_052_534);
        let alava = world.inspect_population("es_census_1900_province_01").unwrap();
        assert_eq!(alava.population_total, Some(96_213));
        assert_eq!(alava.social.unwrap().dimensions["marital_status"].assigned_residents, 0);

        let belgium = world.inspect_population("kingdom_of_belgium").unwrap();
        assert_eq!(belgium.structure.unwrap().residents_with_cohort_age_and_sex, 6_631_330);
        let belgian_social = belgium.social.unwrap();
        assert_eq!(belgian_social.dimensions["language"].assigned_residents, 6_631_330);
        assert_eq!(belgian_social.dimensions["marital_status"].assigned_residents, 6_631_330);
        let antwerp = world.inspect_population("be_census_antwerp").unwrap().structure.unwrap();
        assert_eq!(antwerp.cohorts.len(), 6);
        assert_eq!(antwerp.residents_with_cohort_age_and_sex, 807_274);

        let faiyum = world.inspect_population("egy_mudiriya_faiyum").unwrap();
        assert_eq!(faiyum.children.len(), 3);
        assert_eq!(faiyum.children.iter().map(|child| child.population_total).sum::<u64>(), 389_421);
        let itsa = world.inspect_population("egy_markaz_itsa").unwrap();
        let structure = itsa.structure.unwrap();
        assert_eq!(structure.cohort_residents, 124_623);
        assert_eq!(structure.residents_with_cohort_age_and_sex, 0);
        let itsa_social = itsa.social.unwrap();
        assert_eq!(itsa_social.dimensions["religion"].assigned_residents, 124_623);
        assert_eq!(itsa_social.dimensions["literacy"].assigned_residents, 124_623);
        let district = world.inspect_population("egy_markaz_faiyum").unwrap().social.unwrap();
        assert_eq!(district.dimensions["occupation"].assigned_residents, 132_375);
        assert_eq!(district.dimensions["literacy"].unknown_residents, 132_375);

        let sao_paulo = world.inspect_population("br_sao_paulo").unwrap().social.unwrap();
        assert_eq!(sao_paulo.dimensions["marital_status"].assigned_residents, 2_192_821);
        assert_eq!(sao_paulo.dimensions["literacy"].assigned_residents, 2_192_821);
        let lucknow = world.inspect_population("raj_oudh_lucknow").unwrap().structure.unwrap();
        assert!(lucknow.cohorts.iter().all(|cohort| {
            cohort.evidence.as_ref().is_some_and(|evidence| evidence.locator.contains("Table VII(B)"))
        }));
    }

    #[test]
    fn historical_portuguese_and_agra_districts_close_without_allocating_unlocated_people() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let portugal = world.inspect_population("kingdom_of_portugal").unwrap();
        assert_eq!(portugal.children.len(), 21);
        assert_eq!(portugal.children.iter().map(|child| child.population_total).sum::<u64>(), 5_388_982);
        let lisboa = world.inspect_population("pt1900_lisboa").unwrap();
        assert_eq!(lisboa.population_total, Some(700_515));
        assert!(lisboa.structure.unwrap().cohorts.iter().all(|cohort| {
            cohort.evidence.as_ref().is_some_and(|evidence| evidence.method.contains("directly observed district"))
        }));
        let lisboa = lisboa.social.unwrap();
        assert_eq!(lisboa.dimensions["occupation"].assigned_residents, 680_949);
        assert_eq!(lisboa.dimensions["occupation"].unknown_residents, 19_566);
        assert_eq!(lisboa.dimensions["religion"].unknown_residents, 186);
        let aveiro = world.inspect_population("pt1900_aveiro").unwrap().structure.unwrap();
        assert!(aveiro.cohorts.iter().all(|cohort| {
            cohort.evidence.as_ref().is_some_and(|evidence| evidence.method.contains("deducting Lisboa and Porto"))
        }));

        let provinces = world.inspect_population("raj_agra_oudh").unwrap();
        assert_eq!(provinces.children.len(), 49);
        assert_eq!(provinces.children.iter().map(|child| child.population_total).sum::<u64>(), 47_600_781);
        let agra = world.inspect_population("raj_agra_agra").unwrap();
        assert_eq!(agra.population_total, Some(1_053_947));
        assert_eq!(agra.structure.unwrap().cohort_residents, 1_053_947);
        assert_eq!(agra.social.unwrap().dimensions["religion"].assigned_residents, 1_053_947);
        let balance = world.inspect_population("raj_agra_unlocated_table_ii_a").unwrap();
        assert_eq!(balance.population_total, Some(294));
        assert_eq!(balance.structure.unwrap().residents_with_cohort_age_and_sex, 0);
        assert_eq!(balance.social.unwrap().dimensions["religion"].unknown_residents, 294);

        let santa_catarina = world.inspect_population("br_santa_catarina").unwrap().social.unwrap();
        assert_eq!(santa_catarina.dimensions["religion"].assigned_residents, 301_906);
        assert_eq!(santa_catarina.dimensions["religion"].unknown_residents, 14_743);
        let peru = world.inspect_population("peru_1900").unwrap();
        assert_eq!(peru.population_total, Some(3_383_000));
        assert!(peru.children.is_empty());

        let old = bootstrap.base_opening_version("country_fra", None, Some(25)).unwrap();
        assert_eq!(old.inspect_population("raj_agra_remainder").unwrap().population_total, Some(34_788_845));
        assert_eq!(old.inspect_population("peru_1900").unwrap().population_total, Some(3_800_000));
    }

    #[test]
    fn historical_indian_princely_ages_and_uk_occupations_keep_census_scopes() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.base_opening_version("country_fra", None, Some(27)).unwrap();
        let old = bootstrap.base_opening_version("country_fra", None, Some(26)).unwrap();
        let bombay = world.inspect_population("raj_bombay_states").unwrap();
        assert_eq!(bombay.population_total, Some(7_021_967));
        assert_eq!(bombay.structure.unwrap().residents_with_cohort_age_and_sex, 7_016_635);
        assert_eq!(old.inspect_population("raj_bombay_states").unwrap()
            .structure.unwrap().residents_with_cohort_age_and_sex, 0);

        let state = world.inspect_population("raj_madras_banganapalle").unwrap();
        assert_eq!(state.population_total, Some(32_639));
        assert_eq!(state.structure.unwrap().residents_with_cohort_age_and_sex, 32_639);
        assert_eq!(state.social.unwrap().dimensions["religion"].unknown_residents, 96);
        let madras = world.inspect_population("raj_madras_states").unwrap();
        assert_eq!(madras.children.len(), 5);
        assert_eq!(madras.population_total, old.inspect_population("raj_madras_states").unwrap().population_total);

        for (unit, census_total, assigned, unknown, agriculture) in [
            ("administrative_region:uk_constituent_scotland", 4_472_103, 1_958_171, 2_458_355, 202_459),
            ("administrative_region:uk_constituent_ireland", 4_458_775, 1_962_996, 2_526_399, 865_428),
        ] {
            let report = world.inspect_population(unit).unwrap();
            assert!(report.children.len() > 30);
            let child = world.inspect_population(&report.children[0].unit_id).unwrap();
            assert_eq!(child.social.unwrap().dimensions["occupation"].assigned_residents, 0);
            let occupation = &report.social.as_ref().unwrap().dimensions["occupation"];
            assert_eq!((occupation.assigned_residents, occupation.unknown_residents), (assigned, unknown));
            assert_eq!(occupation.direct_opening_distribution.as_ref().unwrap().observed_total, census_total);
            assert_eq!(occupation.by_classification["uk_1901_general_report_occupation_orders"]["Agriculture"], agriculture);
        }

        let gharbiya = world.inspect_population("egy_mudiriya_gharbiya").unwrap().social.unwrap();
        assert_eq!(gharbiya.dimensions["occupation"]
            .by_classification["egypt_1897_reported_occupation_status"]["With occupation"], 450_890);
        let jirja = world.inspect_population("egy_mudiriya_jirja").unwrap().social.unwrap();
        assert_eq!(jirja.dimensions["literacy"]
            .by_classification["egypt_1897_reported_instruction"]["Read and write"], 16_745);
    }

    #[test]
    fn historical_bombay_common_jurisdiction_preserves_india_and_models_local_ages() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let old = bootstrap.base_opening_version("country_fra", None, Some(27)).unwrap();
        assert_eq!(world.population().population_total("cshapes_gw_750"),
                   old.population().population_total("cshapes_gw_750"));
        let presidency = world.inspect_population("raj_bombay_presidency").unwrap();
        assert_eq!(presidency.population_total, Some(18_552_552));
        assert_eq!(presidency.children.len(), 24);
        assert_eq!(presidency.children.iter().map(|child| child.population_total).sum::<u64>(), 18_552_552);
        let city = world.inspect_population("place:bombay").unwrap();
        assert_eq!(city.account_id, Some("raj_bombay_bombay_city"));
        assert_eq!(city.population_total, Some(781_314));
        assert_eq!(city.structure.unwrap().residents_with_cohort_age_and_sex, 781_295);
        assert!(world.inspect_population("place:karachi").unwrap().population_total.is_none());
        let states = world.inspect_population("raj_bombay_states").unwrap();
        assert_eq!(states.population_total, Some(7_044_776));
        assert_eq!(states.structure.unwrap().residents_with_cohort_age_and_sex, 7_039_427);
        assert_eq!(old.inspect_population("raj_bombay_states").unwrap().population_total, Some(7_021_967));
    }

    #[test]
    fn historical_bengal_districts_preserve_the_opening_balance_and_local_sex_profiles() {
        use crate::formal_population::CohortSex;
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let old = bootstrap.base_opening_version("country_fra", None, Some(26)).unwrap();
        assert_eq!(world.population().population_total("cshapes_gw_750"),
                   old.population().population_total("cshapes_gw_750"));
        let bengal = world.inspect_population("raj_bengal_province").unwrap();
        assert_eq!(bengal.children.len(), 48);
        assert_eq!(bengal.children.iter().map(|child| child.population_total).sum::<u64>(), 74_350_690);
        assert_eq!(bengal.population_total, Some(74_350_690));
        let bengal_social = bengal.social.unwrap();
        assert_eq!(bengal_social.dimensions["religion"].unknown_residents, 227);
        assert_eq!(bengal_social.dimensions["marital_status"].assigned_residents, 74_350_690);
        let language = &bengal_social.dimensions["language"];
        assert_eq!(language.assigned_residents, 74_350_690);
        assert_eq!(language.direct_opening_distribution.as_ref().unwrap().observed_total, 74_744_866);
        let united = world.inspect_population("raj_agra_oudh").unwrap().social.unwrap();
        let language = &united.dimensions["language"];
        assert!(language.unknown_residents > 294);
        assert_eq!(language.direct_opening_distribution.as_ref().unwrap().observed_unknown, 6_791);
        let balance = world.inspect_population("raj_bengal_unlocated_comparison").unwrap();
        assert_eq!(balance.population_total, Some(26));
        assert_eq!(balance.structure.unwrap().residents_with_cohort_age_and_sex, 0);

        let calcutta = world.inspect_population("place:kolkata").unwrap();
        assert_eq!(calcutta.account_id, Some("raj_bengal_calcutta"));
        let city = world.inspect_population("place:kolkata").unwrap();
        assert_eq!(city.account_id, Some("raj_bengal_calcutta"));
        assert_eq!(city.population_total, Some(828_598));
        let structure = city.structure.unwrap();
        assert_eq!(structure.residents_with_cohort_age_and_sex + structure.named_residents, 828_598);
        let male = structure.cohorts.iter().filter(|cohort| cohort.sex == Some(CohortSex::Male))
            .map(|cohort| cohort.members).sum::<u64>();
        assert!((549_850..549_862).contains(&male), "{male}");
        let city_social = city.social.unwrap();
        let literacy = &city_social.dimensions["literacy"];
        assert_eq!(literacy.assigned_residents, 828_598);
        assert_eq!(literacy.by_classification["india_1901_reported_literacy"]["Literate"], 205_678);
        assert_eq!(city_social.dimensions["religion"].unknown_residents, 828_598);
        assert_eq!(city_social.dimensions["language"].unknown_residents, 828_598);
        let dacca = world.inspect_population("raj_bengal_dacca").unwrap();
        assert_eq!(dacca.social.unwrap().dimensions["literacy"].assigned_residents, 2_620_046);
        assert_eq!(old.residence_unit_at("place:kolkata"), Some("raj_bengal_province"));
    }

    #[test]
    fn historical_baden_survey_adds_age_and_civil_status_without_changing_the_balance() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let unit = "administrative_region:germany_baden";
        let world = bootstrap.create("country_fra").unwrap();
        let report = world.inspect_population(unit).unwrap();
        assert_eq!(report.population_total, Some(1_841_868));
        assert_eq!(report.structure.unwrap().residents_with_cohort_age_and_sex, 1_841_868);
        assert_eq!(report.social.unwrap().dimensions["marital_status"].assigned_residents, 1_841_868);

        let wuerttemberg = "administrative_region:germany_wuerttemberg";
        let structure = world.inspect_population(wuerttemberg).unwrap().structure.unwrap();
        assert_eq!(structure.residents_with_cohort_age_and_sex, 2_153_315);
        assert!(structure.cohorts.iter().all(|cohort| {
            cohort.age_years.is_some_and(|age| age.oldest == Some(age.youngest))
        }));

        let previous = bootstrap.base_opening_version("country_fra", None, Some(19)).unwrap();
        let before = previous.inspect_population(unit).unwrap();
        assert_eq!(before.population_total, report.population_total);
        assert_eq!(before.structure.unwrap().residents_with_cohort_age_and_sex, 0);
        assert_eq!(before.social.unwrap().dimensions["marital_status"].assigned_residents, 0);
        let before_wuerttemberg = previous.inspect_population(wuerttemberg).unwrap().structure.unwrap();
        assert_eq!(before_wuerttemberg.residents_with_cohort_age_and_sex, 2_153_315);
        assert!(before_wuerttemberg.cohorts.iter().any(|cohort| {
            cohort.age_years.is_some_and(|age| age.oldest == Some(15) && age.youngest == 0)
        }));
    }

    #[test]
    fn historical_egypt_provinces_partition_the_control_with_known_sex_only() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.base_opening_version("country_fra", None, Some(24)).unwrap();
        let egypt = world.inspect_population("khedivate_of_egypt").unwrap();
        assert_eq!(egypt.population_total, Some(10_000_000));
        assert_eq!(egypt.direct_residents, Some(4_195_390));
        assert_eq!(egypt.children.iter().map(|child| child.population_total).sum::<u64>(), 5_804_610);
        for (unit, total) in [
            ("egy_mudiriya_asyut", 815_260),
            ("egy_mudiriya_faiyum", 389_421),
            ("egy_mudiriya_gharbiya", 1_346_489),
            ("egy_mudiriya_jirja", 716_693),
            ("egy_mudiriya_menufiya", 892_075),
            ("egy_mudiriya_qena", 729_563),
        ] {
            let report = world.inspect_population(unit).unwrap();
            assert_eq!(report.population_total, Some(total));
            let structure = report.structure.unwrap();
            assert_eq!(structure.residents_with_cohort_age_and_sex, 0);
            assert_eq!(structure.cohort_residents, total);
            assert_eq!(structure.cohorts.len(), 2);
            assert!(structure.cohorts.iter().all(|cohort| cohort.sex.is_some() && cohort.age_years.is_none()));
            assert_eq!(report.social.unwrap().dimensions["occupation"].unknown_residents, total);
        }

        let unit = "egy_mudiriya_faiyum";
        let report = world.inspect_population(unit).unwrap();
        let structure = report.structure.unwrap();
        assert!(structure.cohorts.iter().any(|cohort| cohort.members == 196_981));
        assert!(structure.cohorts.iter().any(|cohort| cohort.members == 192_440));
        let previous = bootstrap.base_opening_version("country_fra", None, Some(19)).unwrap();
        assert_eq!(previous.inspect_population(unit).unwrap().population_total, None);
        assert_eq!(previous.inspect_population("khedivate_of_egypt").unwrap().direct_residents, Some(9_084_891));
    }

    #[test]
    fn historical_hungarian_work_status_keeps_occupation_and_county_scope_separate() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        let unit = "ah_croatia_slavonia";
        let report = world.inspect_population(unit).unwrap();
        let social = report.social.unwrap();
        let class = &social.dimensions["class"];
        assert_eq!((class.assigned_residents, class.unknown_residents), (1_266_506, 1_128_372));
        assert_eq!(social.dimensions["occupation"].assigned_residents, 1_270_958);
        let tisza = world.inspect_population("ah_tisza_maros").unwrap().social.unwrap();
        assert_eq!(tisza.dimensions["class"].assigned_residents, 893_916);
        let global = world.population().social_distribution(None).unwrap();
        let crown = &global.dimensions["class"].by_classification["hungarian_crown_1900_work_status"];
        assert_eq!(crown.values().sum::<u64>(), 8_368_163);
        let county = world.inspect_population(report.children[0].unit_id).unwrap();
        assert_eq!(county.social.unwrap().dimensions["class"].assigned_residents, 0);
        let previous = bootstrap.base_opening_version("country_fra", None, Some(19)).unwrap();
        let old_social = previous.inspect_population(unit).unwrap().social.unwrap();
        assert_eq!(old_social.dimensions["class"].assigned_residents, 0);
        assert_eq!(old_social.dimensions["occupation"].assigned_residents, 1_270_958);
    }

    #[test]
    fn historical_alaska_and_hawaii_keep_own_age_tables_and_missing_ages() {
        let world = WorldBootstrap::load().unwrap().create("country_fra").unwrap();
        for (unit, total, with_age) in [("cshapes_gw_3", 62_288, 45_724), ("cshapes_gw_4", 151_193, 150_640)] {
            let report = world.inspect_population(unit).unwrap();
            assert_eq!(report.population_total, Some(total));
            let structure = report.structure.unwrap();
            assert_eq!(structure.cohort_residents, total);
            assert_eq!(structure.residents_with_cohort_age_and_sex, with_age);
        }
    }

    #[test]
    fn historical_hungarian_counties_preserve_parent_controls() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let world = bootstrap.create("country_fra").unwrap();
        for (unit, total, children, occupied, primary) in [
            ("ah_tisza_maros", 2_041_110, 9, 901_454, 660_774),
            ("ah_croatia_slavonia", 2_394_878, 12, 1_270_958, 1_081_677),
        ] {
            let report = world.inspect_population(unit).unwrap();
            assert_eq!(report.population_total, Some(total));
            assert_eq!(report.direct_residents, None);
            assert_eq!(report.children.len(), children);
            assert_eq!(report.children.iter().map(|child| child.population_total).sum::<u64>(), total);
            let structure = report.structure.unwrap();
            assert_eq!(structure.cohort_residents, total);
            assert!(structure.residents_with_cohort_age_and_sex >= total - 200);
            let social = report.social.unwrap();
            let religion = &social.dimensions["religion"];
            let language = &social.dimensions["language"];
            assert_eq!(religion.assigned_residents + religion.unknown_residents, total);
            assert!(religion.assigned_residents > total - 16_000);
            assert_eq!(language.assigned_residents + language.unknown_residents, total);
            assert!((language.assigned_residents as i64 - religion.assigned_residents as i64).abs() <= 1);
            let occupation = &social.dimensions["occupation"];
            assert_eq!(occupation.assigned_residents, occupied);
            assert_eq!(occupation.unknown_residents, total - occupied);
            assert_eq!(occupation.by_classification["hungarian_crown_1900_occupation"]["Primary production"], primary);
        }
        let municipality = world.inspect_population("ah_zagrab_city").unwrap();
        assert_eq!(municipality.population_total, Some(59_051));
        assert_eq!(municipality.parent_id, Some("ah_croatia_slavonia"));
        let social = municipality.social.unwrap();
        for dimension in ["occupation", "religion", "language"] {
            assert_eq!(social.dimensions[dimension].assigned_residents, 0);
            assert_eq!(social.dimensions[dimension].unknown_residents, 59_051);
        }
        assert_eq!(world.population().population_total("austria_hungary"), Some(45_000_882));
        let prior = bootstrap.base_opening_version("country_fra", None, Some(18)).unwrap();
        assert_eq!(prior.population().social_distribution(None).unwrap().dimensions["occupation"].assigned_residents, 57_872_694);
    }

    #[test]
    fn historical_england_wales_occupation_stays_at_the_census_scope() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let current = bootstrap.create("country_fra").unwrap();
        let scope = "uk_england_wales_except_anglesey";
        let county = "administrative_region:gb_historic_anglesey";
        let world = current.population();
        assert_eq!(world.population_total(scope), Some(32_038_448));
        assert_eq!(world.population_total(county), Some(50_543));
        let occupation = &world.social_distribution(Some(scope)).unwrap().dimensions["occupation"];
        assert_eq!(occupation.assigned_residents, 14_113_822);
        assert_eq!(occupation.assigned_residents + occupation.unknown_residents, 32_038_448);
        let original = occupation.direct_opening_distribution.unwrap();
        assert_eq!((original.observed_total, original.observed_unknown), (32_477_237, 18_170_116));
        assert_eq!(occupation.by_classification["england_wales_1901_occupation_orders"]["Agriculture"], 1_106_572);
        let local = &world.social_distribution(Some(county)).unwrap().dimensions["occupation"];
        assert_eq!(local.assigned_residents, 21_579);
        assert_eq!(local.by_classification["england_wales_1901_occupation_orders"]["Agriculture"], 6_868);
        let previous = bootstrap.base_opening_version("country_fra", None, Some(16)).unwrap();
        assert_eq!(world.population_total(county), previous.population().population_total(county));
        let county_structure = current.inspect_population(county).unwrap().structure.unwrap();
        let previous_structure = previous.inspect_population(county).unwrap().structure.unwrap();
        assert_eq!(county_structure.residents_with_cohort_age_and_sex, previous_structure.residents_with_cohort_age_and_sex);
        assert_eq!(previous.population().population_total(scope), None);
    }

    #[test]
    fn historical_population_structure_and_old_openings_restore() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let origin = world.residence_unit_at("place:moscow").unwrap().to_owned();
        let origin = origin.as_str();
        let destination = "country_fra";
        let clock = world.clock();
        let orne = "administrative_region:france_orne";
        let argentan = "administrative_region:france_arrondissement_612";
        let domfront = "administrative_region:france_arrondissement_613";
        assert_eq!(world.population().resident_pool(orne), None);
        assert_eq!(world.population().population_total(destination), Some(38_852_748));
        for (province, people, districts) in [
            ("ardeche", 356_005, 3),
            ("cher", 346_079, 3),
            ("vendee", 441_415, 3),
            ("vosges", 421_180, 5),
        ] {
            let unit = format!("administrative_region:france_{province}");
            let report = world.inspect_population(&unit).unwrap();
            assert_eq!(report.population_total, Some(people));
            assert_eq!(report.children.len(), districts);
            assert_eq!(report.children.iter().map(|district| district.population_total).sum::<u64>(), people);
        }
        let division = world.inspect_population(orne).unwrap();
        assert_eq!(division.population_total, Some(329_951));
        assert_eq!(division.children.len(), 4);
        assert_eq!(division.children.iter().map(|child| child.population_total).sum::<u64>(), 329_951);
        let county = world.inspect_population(argentan).unwrap();
        assert_eq!(county.population_total, Some(76_124));
        assert_eq!(county.parent_id, Some(orne));
        assert_eq!(world.residence_unit_at("place:rouen"), Some("administrative_region:france_arrondissement_763"));
        assert_eq!(world.market_unit_for_population(argentan), Some(destination));
        let (french_cohort, _, _) = world.population().cohorts_in(argentan).next().unwrap();
        let french_cohort = french_cohort.clone();
        world.population.transfer_cohort(argentan, domfront, &french_cohort, 1, 0).unwrap();
        let division = world.inspect_population(orne).unwrap();
        assert_eq!(division.population_total, Some(329_951));
        assert_eq!(division.recent_changes[0].unit_id, Some(argentan));
        let france_structure = division.structure.unwrap();
        assert_eq!(france_structure.cohort_residents, 329_951);
        let orne_with_age_and_sex = france_structure.residents_with_cohort_age_and_sex;
        for (unit, total) in [("ft_sweden", 5_097_402), ("ft_norway", 2_217_971)] {
            let structure = world.population().structure(Some(unit), clock).unwrap();
            assert_eq!(structure.population_total, total);
            assert_eq!(structure.residents_with_cohort_age_and_sex + structure.named_residents, total);
        }
        let belgium = world.inspect_population("kingdom_of_belgium").unwrap();
        assert_eq!(belgium.population_total, Some(6_631_330));
        assert_eq!(belgium.children.len(), 9);
        assert_eq!(belgium.children.iter().map(|child| child.population_total).sum::<u64>(), 6_631_330);

        let swiss = world.population().structure(Some("swiss_confederation"), clock).unwrap();
        assert_eq!(swiss.population_total, 3_285_131);
        assert_eq!(swiss.residents_with_cohort_age_and_sex + swiss.named_residents, 3_285_131);
        let netherlands = "kingdom_of_netherlands";
        assert_eq!(world.population().population_total(netherlands), Some(5_104_137));
        assert_eq!(world.population().resident_pool(netherlands), Some(158));
        assert_eq!(world.residence_unit_at("place:amsterdam"), Some("nl1899_pv2700"));
        let dutch_structure = world.population().structure(Some(netherlands), clock).unwrap();
        assert_eq!(dutch_structure.cohort_residents, 5_103_979);
        assert_eq!(dutch_structure.residents_with_cohort_age_and_sex, 5_103_872);
        let dutch_social = world.population().social_distribution(Some(netherlands)).unwrap();
        assert_eq!(dutch_social.dimensions["religion"].assigned_residents, 5_103_887);
        assert_eq!(dutch_social.dimensions["occupation"].assigned_residents, 1_923_577);
        assert_eq!(dutch_social.dimensions["marital_status"].assigned_residents, 5_103_913);
        for (unit, assigned) in [
            ("raj_central_india_agency", 4_585_285),
            ("raj_rajputana_agency", 5_875_312),
        ] {
            let social = world.population().social_distribution(Some(unit)).unwrap();
            assert_eq!(social.dimensions["occupation"].assigned_residents, assigned);
        }
        assert_eq!(world.residence_unit_at("place:cairo"), Some("egy_madina_cairo"));
        assert_eq!(world.residence_unit_at("place:alexandria"), Some("egy_madina_alexandria"));
        assert_eq!(world.population().population_total("egy_madina_cairo"), Some(592_087));
        assert_eq!(world.population().population_total("khedivate_of_egypt"), Some(10_000_000));
        assert_eq!(world.population().population_total("cshapes_gw_561"), Some(2_265_556));
        let cape = world.population().structure(Some("cshapes_gw_561"), clock).unwrap();
        assert_eq!(cape.cohort_residents, 2_265_556);
        assert_eq!(cape.residents_with_cohort_age_and_sex, 2_264_636);
        assert_eq!(cape.cohorts.iter().filter(|row| row.age_years.is_none()).map(|row| row.members).sum::<u64>(), 920);
        let cape_archive = crate::formal_population::population_archive("cape_colony").unwrap().unwrap();
        assert!(cape_archive.dated_structure.iter().any(|row| row["panel_id"] == "cape_1904" && row["values"]["both"] == 2_409_804));
        assert_eq!(world.population().population_total("cshapes_gw_850"), Some(44_363_679));
        assert_eq!(world.population().population_total("java_madoera_colonial_population"), Some(28_092_332));
        assert_eq!(world.population().resident_pool("cshapes_gw_850"), Some(16_271_347));
        assert_eq!(world.population().population_total("republic_of_colombia_1900"), Some(4_124_729));
        assert_eq!(world.population().population_total("ft_colombia"), Some(3_803_231));
        assert_eq!(world.population().population_total("ft_panama"), Some(321_498));
        assert_eq!(world.market_unit_for_population("ft_panama"), Some("republic_of_colombia_1900"));
        let bosnia = "statistical_area:bosnia_herzegovina_1900";
        assert_eq!(world.population().population_total(bosnia), Some(1_668_263));
        assert_eq!(world.population().population_total("austria_hungary"), Some(45_000_882));
        assert_eq!(world.population().population_total("cshapes_gw_3461"), None);
        assert_eq!(world.population().population_total("cshapes_gw_3462"), None);
        assert_eq!(world.market_unit_for_population(bosnia), None);
        let bosnia_structure = world.population().structure(Some(bosnia), clock).unwrap();
        assert_eq!(bosnia_structure.cohort_residents, 1_668_263);
        assert_eq!(bosnia_structure.residents_with_cohort_age_and_sex, 0);
        assert_eq!(bosnia_structure.cohorts.iter().map(|row| row.members).sum::<u64>(), 1_668_263);
        assert!(bosnia_structure.cohorts.iter().all(|row| row.sex.is_some() && row.age_years.is_none()));
        let member_archive = crate::formal_population::population_archive("cshapes_gw_3461").unwrap().unwrap();
        assert!(member_archive.dated_population.iter().any(|row| row["unit_id"] == bosnia && row["population_value"] == 1_568_092));
        assert_eq!(world.population().population_total("ecuador_1900"), None);
        let qing = world.population();
        assert_eq!(qing.population_total("qing_empire"), Some(400_000_000));
        for (label, unit) in [("qing_empire:label:7", "qing_hist_jiangxi"), ("qing_empire:label:8", "qing_hist_zhejiang"),
            ("qing_empire:label:18", "qing_hist_guizhou"), ("qing_empire:label:5", "qing_hist_jiangsu"),
            ("qing_empire:label:3", "qing_hist_shanxi"), ("qing_empire:label:16", "qing_hist_guangxi"),
            ("qing_empire:label:17", "qing_hist_yunnan")]
        {
            let archive = crate::formal_population::population_archive(label).unwrap().unwrap();
            assert!(archive.geographies.iter().any(|row| row["opening_id"] == unit));
            assert!(archive.dated_population.iter().any(|row| row["unit_id"] == unit && row["date"] == "1880"));
            assert!(qing.population_total(unit).is_some());
        }
        let coverage = crate::formal_population::structural_coverage_reference("russian_empire").unwrap().unwrap();
        assert_eq!(coverage["panels"]["russia_1897_religion"]["directly_classified_count"], 125_640_021);
        assert!(coverage["scope"]["dimensions"]["religion"]["opening_known_people"].is_null());
        assert_eq!(coverage["scope"]["dimensions"]["religion"]["opening_unknown_people"], 135_382_043);
        let mysore = world.population().structure(Some("raj_mysore_state"), clock).unwrap();
        assert_eq!(mysore.population_total, 5_470_284);
        assert_eq!(mysore.residents_with_cohort_age_and_sex, 5_470_284);
        let madras = world.population().structure(Some("raj_madras_presidency"), clock).unwrap();
        assert_eq!(madras.population_total, 37_910_258);
        assert_eq!(madras.residents_with_cohort_age_and_sex, 37_910_258);
        let coverage = crate::formal_population::structural_coverage_reference("british_isles_1900").unwrap().unwrap();
        let crowded = &coverage["panels"]["england_wales_1901_crowded_small_tenements"];
        assert_eq!(crowded["directly_classified_count"], 2_667_506);
        assert_eq!(crowded["count_of_reported_tenements"], 392_414);
        let occupants = &coverage["panels"]["england_wales_1901_occupants_by_tenement_rooms"];
        let tenements = &coverage["panels"]["england_wales_1901_tenements_by_rooms"];
        assert_eq!(occupants["directly_classified_count"], 32_527_843);
        assert_eq!(tenements["directly_classified_count"], 7_036_868);
        assert_eq!(tenements["measure_unit"], "tenements");
        let coverage = crate::formal_population::structural_coverage_reference("russian_empire").unwrap().unwrap();
        let language = &coverage["panels"]["russia_1897_mother_tongue"];
        assert_eq!(language["directly_classified_count"], 125_634_894);
        assert_eq!(language["unreported_count"], 5_127);
        let estates = &coverage["panels"]["russia_1897_legal_estates"];
        assert_eq!(estates["directly_classified_count"], 124_962_686);
        assert_eq!(estates["foreign_subjects_outside_denominator"], 605_500);
        let ecuador = crate::formal_population::population_archive("ecuador_1900").unwrap().unwrap();
        assert!(ecuador.candidate_research_population.iter().any(|row| {
            row["unit_id"] == "ft_ecuador" && row["date"] == "1900-01-01" && row["population_value"] == 1_100_787
        }));
        assert!(ecuador.sources.iter().any(|row| row["id"] == "ft_world_v5"));
        let us = world.population().structure(Some("united_states_1900"), clock).unwrap();
        assert_eq!(us.population_total, 75_454_976);
        assert_eq!(us.cohort_residents + us.named_residents, us.population_total);
        assert!(us.residents_with_cohort_age_and_sex > 75_000_000);
        let us_social = world.population().social_distribution(Some("united_states_1900")).unwrap();
        assert_eq!(us_social.dimensions["occupation"].assigned_residents, 28_866_450);
        assert_eq!(us_social.dimensions["residence"].unknown_residents, 0);
        assert_eq!(us_social.dimensions["literacy"].assigned_residents, 57_539_868);
        assert_eq!(us_social.dimensions["household"].assigned_residents, 72_890_961);
        assert_eq!(us_social.dimensions["culture"].unknown_residents, us.population_total);
        let prussia_id = "administrative_region:germany_preussen";
        let prussia = world.population().structure(Some(prussia_id), clock).unwrap();
        assert_eq!(prussia.population_total, 33_993_492);
        assert_eq!(prussia.cohort_residents + prussia.named_residents, prussia.population_total);
        assert_eq!(prussia.residents_with_cohort_age_and_sex, 33_986_841);
        let prussian_social = world.population().social_distribution(Some(prussia_id)).unwrap();
        assert_eq!(prussian_social.dimensions["marital_status"].assigned_residents, 33_993_492);
        let port_louis = world.transport().capital_node("cshapes_gw_590").unwrap();
        assert_eq!(world.residence_unit_at(port_louis), Some("mu_district_port_louis"));
        assert_eq!(world.population().population_total("qing_hist_shandong"), Some(42_165_666));
        let initial = world.population().structure(None, clock).unwrap();
        assert_eq!(initial.population_total,
            initial.named_residents + initial.unclassified_residents + initial.cohort_residents);
        assert!(initial.residents_with_cohort_age_and_sex > 0);
        let water = &initial.published_adult_water_references;
        assert_eq!(water.adults_with_reference + water.residents_outside_reference, initial.population_total);
        assert!(water.adults_with_reference > 0 && water.adults_with_reference < initial.residents_with_cohort_age_and_sex);
        assert!(water.temperate_sedentary_litres_per_day.unwrap().upper < water.warm_moderate_work_litres_per_day.unwrap().lower);
        let efsa = &initial.published_efsa_water_reference;
        assert_eq!(efsa.people_with_reference + efsa.people_without_reference, initial.population_total);
        assert!(efsa.people_with_reference > water.adults_with_reference);
        let moderate = efsa.moderate_environment_pal_1_6_total_ingested_litres_per_day.unwrap();
        assert!(moderate.lower > 0.0 && moderate.upper >= moderate.lower);
        let protein = &initial.published_protein_reference;
        assert_eq!(protein.people_with_reference + protein.people_without_reference, initial.population_total);
        assert_eq!(protein.people_with_reference, initial.published_energy_reference.people_with_reference);
        let grams = protein.conditional_grams_per_day.unwrap();
        assert!(grams.lower > 0.0 && grams.upper >= grams.lower);
        let service_water = &initial.published_domestic_water_service_reference;
        assert_eq!(service_water.scenario_population, initial.population_total);
        assert_eq!(service_water.basic_access_litres_per_day, initial.population_total as f64 * 20.0);
        assert_eq!(service_water.intermediate_access_litres_per_day, initial.population_total as f64 * 50.0);
        let (cohort, _, _) = world.population().cohorts_in(origin)
            .find(|(_, def, count)| def.sex.is_some() && *count >= 4)
            .unwrap();
        let cohort = cohort.clone();
        let members = world.population().cohort_members(origin, &cohort).unwrap();
        let global_total = world.population().global_total();
        let moscow_religion = world.population().social_distribution(Some(origin)).unwrap();
        let confession = &moscow_religion.dimensions["religion"];
        assert!(confession.direct_opening_distribution.is_some());
        assert_eq!(confession.assigned_residents, moscow_religion.population_total);
        assert_eq!(confession.unknown_residents, 0);
        let norm = &world.inspect_population(origin).unwrap().dietary_norms[0];
        assert_eq!(norm.residents_with_matching_religion,
            confession.by_classification["russia_1897_reported_confession"]["Магометане"]);
        assert!(norm.observed_adherents.is_none());
        world.population.transfer_cohort(origin, destination, &cohort, 2, 0).unwrap();
        world.population.record_cohort_deaths(destination, &cohort, 1, 0).unwrap();
        world.population.record_anonymous_births(destination, 3, 0).unwrap();
        let saved = world.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().cohort_members(origin, &cohort), Some(members - 2));
        assert_eq!(restored.population().cohort_members(destination, &cohort), Some(1));
        assert_eq!(restored.population().global_total(), global_total + 2);
        assert_eq!(restored.snapshot(), saved);
        let after = restored.population().social_distribution(Some(origin)).unwrap();
        assert_eq!(after.affected_resident_pools, 1);
        assert!(after.dimensions["religion"].unknown_residents > 0);
        assert_eq!(after.dimensions["religion"].assigned_residents + after.dimensions["religion"].unknown_residents, after.population_total);
        assert_eq!(serde_json::to_value(after).unwrap(), serde_json::to_value(world.population().social_distribution(Some(origin))).unwrap());

        let old = bootstrap.base_opening_version("country_fra", None, Some(1)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_455_178_503);
        assert_eq!(restored.population().structure(None, clock).unwrap().cohort_residents, 0);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(2)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        let structure = restored.population().structure(None, clock).unwrap();
        assert_eq!(structure.population_total, 1_457_759_052);
        assert_eq!(structure.residents_with_cohort_age_and_sex, 150_314_640);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(3)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_458_689_022);
        assert_eq!(restored.residence_unit_at("place:cairo"), Some("egy_madina_cairo"));
        assert_eq!(restored.population().population_total("java_madoera_colonial_population"), None);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(4)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_460_954_578);
        assert_eq!(restored.population().population_total("java_madoera_colonial_population"), Some(28_092_332));
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(5)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_463_599_198);
        assert_eq!(restored.population().population_total("ft_panama"), None);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(6)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_465_392_190);
        assert_eq!(restored.population().population_total("qing_hist_zhejiang"), None);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(7)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_465_392_190);
        assert_eq!(restored.population().population_total("qing_hist_guangxi"), None);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(8)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        let cape = restored.population().structure(Some("cshapes_gw_561"), restored.clock()).unwrap();
        assert_eq!(cape.population_total, 2_265_556);
        assert_eq!(cape.cohort_residents, 0);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(9)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_465_392_190);
        assert_eq!(restored.residence_unit_at("place:moscow"), Some("ft_russia_empire_ussr"));
        assert_eq!(restored.population().structure(None, clock).unwrap().residents_with_cohort_age_and_sex, 325_734_333);
        assert_eq!(restored.population().social_distribution(None).unwrap().residents_with_any_attribute_minimum, 0);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(10)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        let port_louis = restored.transport().capital_node("cshapes_gw_590").unwrap();
        assert_eq!(restored.residence_unit_at(port_louis), Some("mu_main_island"));
        assert_eq!(restored.population().global_total(), 1_465_392_190);
        assert_eq!(restored.population().population_total("qing_hist_shandong"), None);
        assert_eq!(restored.population().social_distribution(None).unwrap().residents_with_any_attribute_minimum, 309_272_209);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(11)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_465_392_189);
        assert_eq!(restored.population().population_total(netherlands), Some(5_141_915));
        assert_eq!(restored.population().population_total("nl1899_pv2700"), None);
        assert_eq!(restored.snapshot(), old_saved);

        let old = bootstrap.base_opening_version("country_fra", None, Some(12)).unwrap();
        let old_saved = old.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(old_saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.population().global_total(), 1_465_354_411);
        assert_eq!(restored.population().resident_pool(orne), Some(329_951));
        assert_eq!(restored.population().population_total(argentan), None);
        assert_eq!(restored.residence_unit_at("place:rouen"), Some("administrative_region:france_seine_inferieure"));
        let old_ages = restored.population().structure(Some(orne), clock).unwrap();
        assert_eq!(old_ages.residents_with_cohort_age_and_sex, orne_with_age_and_sex);
        assert_eq!(restored.snapshot(), old_saved);
    }

    #[test]
    fn historical_partition_restores_legacy_journal_and_flat_openings() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut opening = bootstrap.create_opening("country_fra", None, false).unwrap();
        let national = "united_states_1900";
        assert_eq!(opening.population_units(), &bootstrap.populations);
        assert!(opening.population().standalone_totals().is_empty());
        opening.transfer_unmanaged_population(national, "country_fra", 42, 0).unwrap();
        let saved = opening.snapshot();
        assert!(saved["population"].get("opening_version").is_none());
        let restored = bootstrap.restore_native(serde_json::from_value(saved.clone()).unwrap()).unwrap();
        assert_eq!(restored.snapshot(), saved);
        assert!(restored.population().standalone_totals().is_empty());

        // The aggregate-only slot predates runtime residents and their population journal.
        let mut old = bootstrap.base_opening("country_fra", None, false).unwrap();
        old.transfer_unmanaged_population(national, "country_fra", 42, 0).unwrap();
        let mut flat = old.snapshot();
        flat.as_object_mut().unwrap().remove("organization_members");
        flat["population"] = serde_json::to_value(old.population_units()).unwrap();
        let restored = bootstrap.restore_native(serde_json::from_value(flat).unwrap()).unwrap();
        assert_eq!(restored.population_units(), opening.population_units());
        assert!(restored.snapshot()["population"].get("opening_version").is_none());
        assert!(restored.population().standalone_totals().is_empty());
        for (root, &value) in restored.population_units() {
            assert_eq!(restored.population().partitions(root).count(), 0);
            assert_eq!(restored.population().resident_pool(root), Some(value));
            assert!(restored.population().admitted_opening(root).is_none());
        }
    }

    #[test]
    fn historic_authority_and_map_parents_are_independent_of_population_bindings() {
        let world = WorldBootstrap::load().unwrap().create("country_fra").unwrap();
        let sources = &world.sources;
        let (controller, _) = sources.authority("taiwan_under_japan").unwrap();
        assert_eq!(controller.id, "empire_of_japan");
        assert_eq!(sources.places()["place:london"].parent_country_id, "british_empire");
        assert_eq!(sources.population_unit_at("place:london"), Some("british_isles_1900"));
        assert_eq!(sources.population_unit_at("place:kolkata"), Some("cshapes_gw_750"));
        assert_eq!(world.residence_unit_at("place:kolkata"), Some("raj_bengal_calcutta"));
        assert_eq!(sources.places()["place:tokyo"].parent_country_id, "japanese_empire");
        assert_eq!(sources.population_unit_at("place:tokyo"), Some("empire_of_japan"));
        let tokyo = world.inspect_population("place:tokyo").unwrap();
        assert_eq!(tokyo.account_id, Some("jp_otsu_pref_tokyo"));
        assert_eq!(tokyo.population_total, None);
        let tokyo_archive = tokyo.archive.unwrap();
        assert!(tokyo_archive.dated_structure.iter().any(|row| row["unit_id"] == "tokyo_city_1900_occupational_persons"));
        assert!(!tokyo_archive.dated_structure.iter().any(|row| row["unit_id"] == "japan_proper_honseki_1898"));
        let luxembourg = world.inspect_population("state:grand_duchy_of_luxembourg").unwrap();
        assert_eq!(luxembourg.account_id, Some("kingdom_of_luxembourg"));
        assert_eq!(luxembourg.population_total, Some(231_321));
        assert_eq!(luxembourg.scope_relation, "historical_name_alias_of_account");
        assert!(world.sources.population_name_aliases.get("cshapes_gw_901").is_none());
        let australian_colony = world.inspect_population("state:cshapes_gw_901").unwrap();
        assert_ne!(australian_colony.account_id, Some("australia_colonies_1900"));
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
        let mut batch = bootstrap.create("country_fra").unwrap();
        let managed = BTreeMap::new();
        let grain_before = france.macro_economy().markets()["qing_empire"].commodities["potatoes"].inventory;
        france.advance_migrated_domains(MINUTES_PER_DAY - 1, &managed).unwrap();
        assert_eq!(france.macro_economy().last_settlement_hour(), 0);
        france.advance_migrated_domains(1, &managed).unwrap();
        assert_eq!(france.macro_economy().last_settlement_hour(), 24);
        assert_eq!(france.macro_economy().markets().len(), 50);
        assert!(france.macro_economy().markets().values().all(|market| market.commodities["potatoes"].demanded > 0.0));
        assert!(france.macro_economy().markets()["qing_empire"].commodities["potatoes"].inventory < grain_before);
        let mut flows = BTreeMap::<String, (f64, f64, f64, i64)>::new();
        let mut received_units = BTreeMap::<String, BTreeMap<String, f64>>::new();
        let mut tonnes = BTreeMap::<String, (f64, f64, f64)>::new();
        let mut first_dispatch = None;
        let mut first_australian_delivery = None;
        for day in 1..=90 {
            if day > 1 { france.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap(); }
            for s in france.macro_economy.shipments().iter().filter(|s| s.dispatch_hour == day * 24) {
                first_dispatch.get_or_insert_with(|| (day, s.origin.clone(), s.destination.clone(), s.arrival_hour));
                flows.entry(s.origin.clone()).or_default().0 += s.units;
                let buyer = flows.entry(s.destination.clone()).or_default();
                buyer.1 += s.units;
                buyer.3 += s.carriage.as_ref().unwrap().fare_centimes;
                let mass = france.macro_economy.freight_mass(&s.commodity).unwrap().tonnes(s.units);
                tonnes.entry(s.destination.clone()).or_default().0 += mass;
                tonnes.entry(s.origin.clone()).or_default().2 += mass;
            }
            for s in france.macro_economy.last_arrivals() {
                if s.destination == "australia_colonies_1900" {
                    first_australian_delivery.get_or_insert_with(|| (s.id.clone(), s.origin.clone(), s.commodity.clone(), s.units, s.dispatch_hour, s.arrival_hour));
                }
                flows.entry(s.destination.clone()).or_default().2 += s.units;
                tonnes.entry(s.destination.clone()).or_default().1 += france.macro_economy.freight_mass(&s.commodity).unwrap().tonnes(s.units);
                let scale = france.macro_economy.commodity_info(&s.commodity).unwrap().2;
                *received_units.entry(s.destination.clone()).or_default().entry(scale.into()).or_default() += s.units;
            }
        }
        assert!(first_australian_delivery.is_some(), "Australia must receive a natural overseas market delivery");
        println!("First natural shipment (day, seller, buyer, arrival hour): {first_dispatch:?}; first Australian receipt: {first_australian_delivery:?}");
        for (unit, market) in france.macro_economy.markets() {
            let (sold, bought, arrived, freight) = flows.get(unit).copied().unwrap_or_default();
            let unmet: f64 = market.commodities.values().map(|c| c.unmet).sum();
            let received = received_units.get(unit);
            let (ordered_t, arrived_t, sent_t) = tonnes.get(unit).copied().unwrap_or_default();
            println!("{unit}: shipped={sold:.3} ordered={bought:.3} received={arrived:.3} freight={freight} unmet_d90={unmet:.3} ordered_t={ordered_t:.6} arrived_t={arrived_t:.6} sent_t={sent_t:.6} received_units={received:?}");
        }
        batch.advance_migrated_domains(MINUTES_PER_DAY * 90, &managed).unwrap();
        assert_eq!(batch.character.day, 90);
        assert_eq!(france.character.state, batch.character.state);
        let all_markets = france.macro_economy().markets();
        assert_eq!(france.clock(), batch.clock());
        assert!(all_markets.iter().all(|(id, market)| market.commodities == batch.macro_economy().markets()[id].commodities));
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
            let restored = Ledger::restore(&saved_ledger, true).unwrap();
            assert_eq!(restored.default_account(&world.player().id).unwrap().cash, 2500 - cost);
            assert_eq!(restored.default_account(&market).unwrap().cash, cost);
            assert_eq!(restored.snapshot(), saved_ledger);
        }
    }

    #[test]
    fn anonymous_transfer_changes_market_demand_without_changing_supply() {
        let dry_rice = crate::formal_population::needs::conditional_market_food_energy("rice", 0.453_592_37).unwrap();
        assert_eq!((dry_rice.kcal.lower, dry_rice.kcal.upper), (1_600.0, 1_690.0));
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

        let staple = |world: &InitialWorld, country: &str| world.macro_economy().markets()[country].commodities["potatoes"];
        let mut earlier = bootstrap.base_opening_version("qing_empire", None, Some(4)).unwrap();
        earlier.initialize_organization_members().unwrap();
        earlier.plan_household_orders().unwrap();
        earlier.settle_organization_employment().unwrap();
        for country in [source, destination] {
            assert_eq!(staple(&world, country), staple(&earlier, country));
            assert_eq!(world.macro_economy().markets()[country].gold_reserve_units,
                earlier.macro_economy().markets()[country].gold_reserve_units);
        }
        let managed = BTreeMap::new();
        world.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        unchanged.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        earlier.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        assert!(staple(&world, source).demanded < staple(&unchanged, source).demanded);
        assert!(staple(&world, destination).demanded > staple(&unchanged, destination).demanded);
        for country in [source, destination] {
            assert_eq!(staple(&world, country).produced, staple(&unchanged, country).produced);
            assert_eq!(staple(&unchanged, country).produced, staple(&earlier, country).produced);
            let flows = world.macro_economy().food_flows(country).unwrap().collect::<Vec<_>>();
            let potatoes = flows.iter().find(|row| row.commodity == "potatoes").unwrap();
            let flow = potatoes.last_settlement.as_ref().unwrap();
            assert_eq!(flow.removed_from_macro_stock_units, staple(&world, country).consumed);
            assert!(flow.energy_in_removed_stock.is_none());
            let potato_energy = flow.conditional_energy_in_removed_stock.unwrap();
            let removed_pounds = flow.removed_from_macro_stock_units * f64::from(potatoes.market_unit_mass_kg) / 0.453_592_37;
            assert!((potato_energy.kcal.lower - 228.0 * removed_pounds).abs() < 0.01);
            assert!((potato_energy.kcal.upper - 456.0 * removed_pounds).abs() < 0.01);
            let rice = flows.iter().find(|row| row.commodity == "rice").unwrap();
            assert!(rice.last_settlement.as_ref().unwrap().energy_in_removed_stock.is_none());
        }
        let mut restored = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        for active in [&mut world, &mut restored] {
            active.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        }
        for country in [source, destination] {
            assert_eq!(staple(&world, country), staple(&restored, country));
        }
    }

    #[test]
    fn consumption_uses_purchased_lots_without_charging_again() {
        let mut world = WorldBootstrap::load().unwrap().create("russian_empire").unwrap();
        let market = "market:legacy_aggregate:russian_empire";
        let good = "potatoes";
        let price = world.macro_economy().markets()["russian_empire"].commodities[good].price_centimes;
        let first_record = world.next_living_record;
        world.buy_local_stock(market, good, 1000, price, "first").unwrap();
        world.buy_local_stock(market, good, 2000, price, "second").unwrap();
        let cash = world.balance().unwrap().cash;
        assert!(world.consume_purchased_stock(good, 4000).is_err());
        assert_eq!(world.holding_milli(good), 3000);
        let consumption = world.consume_purchased_stock(good, 1500).unwrap();
        assert_eq!(consumption.record_id, format!("personal_life:{}", first_record + 2));
        assert_eq!(consumption.effective_minute, 0);
        assert_eq!(consumption.allocations, [
            ConsumptionAllocation { purchase_record_id: format!("personal_life:{first_record}"), quantity_milli: 1000 },
            ConsumptionAllocation { purchase_record_id: format!("personal_life:{}", first_record + 1), quantity_milli: 500 },
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
    fn population_world_household_consumes_owned_surplus_and_restores() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let recipient = "person:formal_generated_country_fra_0002";
        let donor = world.player.clone();
        let good = "potatoes";
        let market = "market:legacy_aggregate:country_fra";
        let price = world.macro_economy().markets()["country_fra"].commodities[good].price_centimes;
        let opening_total = world.population_units()["country_fra"];
        world.buy_statistical_stock(&donor, market, good, 2, price, "fixture-family-meals").unwrap();
        world.invite_to_household(&donor, recipient).unwrap();
        assert!(world.household_of(recipient).is_none());
        world.accept_household(recipient, &donor).unwrap();
        let cash = world.ledger.default_account(recipient).unwrap().cash;
        world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        let meal = world.person_livelihood(recipient).unwrap();
        assert_eq!(meal.last_day.unwrap().food_received_milli, 1);
        assert_eq!(meal.last_food_intake.unwrap().portions[0].donor.as_deref(), Some(donor.as_str()));
        assert_eq!(world.person_holding_milli(&donor, good), 0);
        assert_eq!(world.ledger.default_account(recipient).unwrap().cash, cash);
        assert_eq!(world.population_units()["country_fra"], opening_total);
        let saved = world.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(saved.clone()).unwrap()).unwrap();
        assert!(restored.snapshot() == saved, "household and its food provenance changed after restore");
    }

    #[test]
    fn population_world_service_fixture_stops_civilian_shifts_until_discharge() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let mut civilian = bootstrap.create("country_fra").unwrap();
        let worker = "person:formal_generated_country_fra_0002";
        let firm = "firm:opening_paris_bakery";
        let service = ServiceTarget::Strategic("fixture:paris_service".into());
        let population = world.population_units().clone();
        assert!(world.enlist_named_service(worker, service.clone(), false).is_err());
        world.enlist_named_service(worker, service.clone(), true).unwrap();
        let mobilized = world.resident_age_availability(Some("country_fra"), 18, 80).unwrap();
        let available = civilian.resident_age_availability(Some("country_fra"), 18, 80).unwrap();
        assert_eq!(mobilized.population_total, available.population_total);
        assert_eq!(mobilized.named_in_age_range, available.named_in_age_range);
        assert_eq!(mobilized.named_in_age_range_in_active_service, 1);
        assert_eq!(mobilized.named_in_age_range_eligible_for_civilian_work + 1,
            available.named_in_age_range_eligible_for_civilian_work);
        let unit = world.residence_unit_at("place:moscow").unwrap().to_owned();
        let unit = unit.as_str();
        let origin = world.population.structure(Some(unit), world.clock()).unwrap();
        let cohort = origin.cohorts.iter()
            .find(|cohort| cohort.members >= 4 && cohort.age_years.is_some_and(|age| age.youngest == 25))
            .unwrap().id.clone();
        world.service.enlist_cohort(&world.population, unit, &cohort, service.clone(), 4, 0, true).unwrap();
        let availability = world.resident_age_availability(Some("russian_empire"), 25, 29).unwrap();
        assert_eq!(availability.anonymous_in_active_service_all_ages, 4);
        assert_eq!(availability.anonymous.definitely_in_range - availability.anonymous_outside_active_service.definitely_in_range, 4);
        let managed = BTreeMap::new();
        world.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        civilian.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        assert!(world.completed_firm_work(firm, 1).unwrap().is_empty());
        assert_eq!(civilian.completed_firm_work(firm, 1).unwrap().len(), 1);
        assert!(world.local_bread_offer().is_none());
        assert!(civilian.local_bread_offer().is_some());
        assert_eq!(world.population_units(), &population);
        let mut world = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        assert_eq!(world.service.named_target(worker), Some(&service));
        assert_eq!(world.resident_age_availability(Some(unit), 25, 29).unwrap().anonymous_in_active_service_all_ages, 4);
        world.discharge_named_service(worker).unwrap();
        world.advance_migrated_domains(MINUTES_PER_DAY * 2, &managed).unwrap();
        assert_eq!(world.completed_firm_work(firm, 3).unwrap().len(), 1);
    }

    #[test]
    fn population_world_materializes_residents_and_restores_one_identity() {
        let mut bootstrap = WorldBootstrap::load().unwrap();
        let opening = bootstrap.create("country_fra").unwrap();
        let unit = "country_fra";
        bootstrap.populations.insert(unit.into(), 2_000 + opening.population.named_counts()[unit]);
        let mut world = bootstrap.create_opening(unit, None, false).unwrap();
        let total_before = world.population_units()[unit];
        let worker = "person:fixture_worker";
        assert_eq!(world.background_population(unit), Some(2_000));
        world.materialize_resident(worker, "Fixture worker".into(), "place:paris", 1875, None).unwrap();
        assert_eq!(world.background_population(unit), Some(1_999));
        assert_eq!(world.population_units()[unit], total_before);
        assert_eq!(world.ledger.default_account(worker).unwrap().cash, 0);
        assert!(world.materialize_resident(worker, "Duplicate".into(), "place:paris", 1875, None).is_err());
        world.register_birth("person:fixture_child", "Fixture child".into(), "place:paris").unwrap();
        assert_eq!(world.population_units()[unit], total_before + 1);
        assert_eq!(world.background_population(unit), Some(1_999));
        let job = "job:opening_paris_workshop";
        assert!(world.apply_for_work_as(worker, job).is_err());
        world.consult_local_work(worker).unwrap();
        world.apply_for_work_as(worker, job).unwrap();
        world.book_work_as(worker).unwrap();
        world.advance_migrated_domains(MINUTES_PER_DAY * 2, &BTreeMap::new()).unwrap();
        let wages = world.completed_firm_work("firm:opening_paris_workshop", 1).unwrap();
        assert_eq!(wages[0].worker, worker);
        assert_eq!(wages[0].paid_wages, 6);
        let route = "rail_paris_lille";
        let duration = i64::from(world.transport().segment(route).unwrap().profile.travel_minutes);
        let fare = i64::from(world.transport().segment(route).unwrap().profile.cost_units);
        for _ in 0..30 {
            if world.ledger.default_account(worker).unwrap().available >= fare { break; }
            world.book_work_as(worker).unwrap();
            world.advance_migrated_domains(MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        }
        world.travel_person(worker, route, "place:lille").unwrap();
        assert_eq!(world.person_home(worker), Some("place:paris"));
        world.advance_migrated_domains(duration, &BTreeMap::new()).unwrap();
        world.move_person_home(worker).unwrap();
        assert!(world.book_work_as(worker).is_err());
        let saved = world.snapshot();
        let restored = bootstrap.restore_native(serde_json::from_value(saved.clone()).unwrap()).unwrap();
        assert!(restored.snapshot() == saved, "restoring duplicated or changed a resident");
        assert_eq!(restored.person_home(worker), Some("place:lille"));
        assert_eq!(restored.current_place(worker), Some("place:lille"));
    }

    #[test]
    fn population_world_travel_and_native_resume_use_the_single_clock() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let mut batch = bootstrap.create("country_fra").unwrap();
        let totals = world.population_units().clone();
        let route = "rail_paris_rouen";
        let destination = "place:rouen";
        let arrival = i64::from(world.transport().segment(route).unwrap().profile.travel_minutes);
        for world in [&mut world, &mut batch] {
            let nominal = world.transport().segment(route).unwrap().profile.capacity_units;
            world.set_segment_access(route, false, 0).unwrap();
            assert!(world.travel_player(route, destination).is_err());
            world.set_segment_access(route, true, nominal).unwrap();
            world.travel_player(route, destination).unwrap();
            world.set_segment_access(route, false, 0).unwrap();
            assert_eq!(world.player_current_place(), None);
            assert!(!world.can_book_work());
            assert!(world.local_bread_offer().is_none());
        }
        let managed = BTreeMap::new();
        world.advance_migrated_domains(arrival - 1, &managed).unwrap();
        assert_eq!(world.player_home(), "place:paris");
        let mut world = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        assert!(!world.transport.network().availability(route).unwrap().open);
        world.advance_migrated_domains(1, &managed).unwrap();
        assert_eq!(world.player_current_place(), Some(destination));
        assert_eq!(world.player_home(), "place:paris");
        batch.advance_migrated_domains(arrival, &managed).unwrap();
        world.move_player_home().unwrap();
        batch.move_player_home().unwrap();
        assert_eq!(world.player_home(), destination);
        assert_eq!(world.population_units(), &totals);
        for _ in 0..10 {
            world.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        }
        batch.advance_migrated_domains(MINUTES_PER_DAY * 10, &managed).unwrap();
        assert!(world.snapshot() == batch.snapshot(), "daily and batch native snapshots differ");
    }

    #[test]
    #[ignore = "measure the formal-world opening and one year of gameplay"]
    fn population_world_year_measurement() {
        measure_population_year(0);
        measure_population_year(100);
    }

    fn measure_population_year(groups_per_unit: u64) {
        use crate::formal_save::{read_native_slot, write_native_slot};
        use crate::formal_population::{CohortBirthYears, CohortDefinition, CohortProvenance};
        use std::time::{Instant, SystemTime, UNIX_EPOCH};
        let start = Instant::now();
        let bootstrap = WorldBootstrap::load().unwrap();
        let inputs = start.elapsed();
        let start = Instant::now();
        let mut world = bootstrap.create("country_fra").unwrap();
        let opening = start.elapsed();
        let start = Instant::now();
        let units: Vec<_> = world.population_units().keys().cloned().collect();
        let mut fixture_groups = 0;
        for unit in units.iter().filter(|_| groups_per_unit > 0) {
            let Some((pool, _)) = world.population.partitions(unit).map(|(id, _, _)| id)
                .chain(std::iter::once(unit.as_str()))
                .filter_map(|id| world.population.unclassified(id).map(|count| (id, count)))
                .max_by_key(|&(_, count)| count)
                .filter(|&(_, count)| count >= groups_per_unit * 2000)
            else { continue };
            let pool = pool.to_owned();
            for index in 0..groups_per_unit {
                let birth_year = 1801 + index as i64;
                world.population.alloc_cohort(
                    &pool, CohortId::new("fixture:annual_population", format!("{unit}:{index}")).unwrap(),
                    CohortDefinition { provenance: CohortProvenance::Fixture, sex: None,
                        birth_years: Some(CohortBirthYears { earliest: birth_year, latest: birth_year }) },
                    2000, 0,
                ).unwrap();
            }
            fixture_groups += groups_per_unit;
        }
        let cohort_setup = start.elapsed();
        day_measurement::enable();
        let start = Instant::now();
        world.advance_migrated_domains(365 * MINUTES_PER_DAY, &BTreeMap::new()).unwrap();
        let year = start.elapsed();
        let [work, enterprise, livelihood, health, market] = day_measurement::take().map(|sum| sum / 365);
        let suffix = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let path = std::env::temp_dir().join(format!("wwo-population-year-{}-{suffix}.json", std::process::id()));
        let measurement = (|| -> io::Result<_> {
            let start = Instant::now();
            write_native_slot(&path, &world)?;
            let save = start.elapsed();
            let bytes = std::fs::metadata(&path)?.len();
            let start = Instant::now();
            let loaded = read_native_slot(&path, &bootstrap)?;
            Ok((loaded, bytes, save, start.elapsed()))
        })();
        if path.is_file() { std::fs::remove_file(&path).unwrap(); }
        let (loaded, bytes, save, restore) = measurement.unwrap();
        assert_eq!(world.clock(), loaded.clock());
        assert_eq!(world.population_units(), loaded.population_units());
        assert!(world.snapshot() == loaded.snapshot(), "restored annual snapshot differs");
        println!("units={} residents={} named={} fixture_groups={} inputs_ms={} opening_ms={} cohort_setup_ms={} year_ms={} save_bytes={} save_ms={} restore_ms={}",
            units.len(), world.population().global_total(), world.identities.len(),
            fixture_groups, inputs.as_millis(), opening.as_millis(),
            cohort_setup.as_millis(), year.as_millis(), bytes, save.as_millis(), restore.as_millis());
        println!("average_day_us work_and_wages={work} enterprise={enterprise} livelihood={livelihood} character_and_population={health} market={market}");
    }

    #[test]
    fn macro_transport_cross_day_interruption_refunds_and_rebooks_one_paid_lot() {
        let bootstrap = WorldBootstrap::load().unwrap();
        let mut world = bootstrap.create("country_fra").unwrap();
        let responsibility = BTreeMap::new();
        let mut active = None;
        for _ in 0..90 {
            world.advance_migrated_domains(MINUTES_PER_DAY, &responsibility).unwrap();
            active = world.macro_economy.shipments().iter().find_map(|row| {
                let c = row.carriage.as_ref()?;
                let plan = world.transport.plan(c.reservation)?;
                let second = plan.route().legs.get(1)?;
                (world.transport.moving(c.reservation) && plan.departure_minute() == world.clock.snapshot().total_minutes)
                    .then(|| (row.id.clone(), row.origin.clone(), row.destination.clone(), row.commodity.clone(),
                        row.units, c.reservation, second.segment_id.clone(), plan.route().legs[0].profile.travel_minutes))
            });
            if active.is_some() { break; }
        }
        let (id, origin, destination, commodity, units, reservation, segment, first_minutes) = active.unwrap();
        println!("paid shipment {id}: {origin} -> {destination}, {commodity}, {units}");
        let nominal = world.transport.network().segment(&segment).unwrap().profile.capacity_units;
        world.set_segment_access(&segment, false, 0).unwrap();
        world.advance_migrated_domains(i64::from(first_minutes), &responsibility).unwrap();
        let row = world.macro_economy.shipments().iter().find(|r| r.id == id).unwrap();
        assert!(row.carriage.as_ref().unwrap().held);
        let station = world.transport.held(reservation).unwrap().to_owned();
        let refund = world.transport.unused_fare(reservation).unwrap();
        let buyer = format!("account:market_receipts:{}", world.macro_economy.markets()[&destination].id);
        assert!(world.ledger.has_payment(&format!("held-refund:{reservation}"), crate::formal_ledger::TRANSPORT_ACCOUNT,
            &buyer, refund, "cargo_refund", &id));
        let mut world = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        world.set_segment_access(&segment, true, nominal).unwrap();
        let next_day = MINUTES_PER_DAY - world.clock.snapshot().total_minutes % MINUTES_PER_DAY;
        world.advance_migrated_domains(next_day, &responsibility).unwrap();
        let c = world.macro_economy.shipments().iter().find(|r| r.id == id).unwrap().carriage.as_ref().unwrap();
        assert_ne!(c.reservation, reservation);
        assert_eq!(c.from, station);
        assert!(world.transport.plan(reservation).is_none());
        let arrival = c.arrival_minute;
        world.advance_migrated_domains(arrival - world.clock.snapshot().total_minutes - 1, &responsibility).unwrap();
        assert!(world.macro_economy.shipments().iter().any(|r| r.id == id));
        world.advance_migrated_domains(1, &responsibility).unwrap();
        assert!(world.macro_economy.shipments().iter().all(|r| r.id != id));
        assert_eq!(world.macro_economy.last_arrivals().iter().find(|r| r.id == id).unwrap().units, units);
        bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
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
        let loaded = MacroEconomy::restore(Arc::clone(&bootstrap.markets), world.population_units(), &snapshot, hour).unwrap();
        assert_eq!(loaded.shipments(), cargo);
        assert_eq!(typed_map(loaded.persistent_fields(hour)), snapshot);
        let mut loaded = bootstrap.restore_native(serde_json::from_value(world.snapshot()).unwrap()).unwrap();
        world.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        loaded.advance_migrated_domains(MINUTES_PER_DAY, &managed).unwrap();
        assert_eq!(
            typed_map(loaded.macro_economy().persistent_fields(world.clock())),
            typed_map(world.macro_economy().persistent_fields(world.clock())),
        );
    }
}

#[cfg(test)]
#[path = "player_prologue_tests.rs"]
mod player_prologue_tests;
