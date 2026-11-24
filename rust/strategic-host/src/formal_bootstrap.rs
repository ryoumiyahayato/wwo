use crate::{
    formal_character::{self, CharacterOutput},
    formal_clock::{GameClock, MINUTES_PER_DAY, MINUTES_PER_HOUR},
    formal_enterprise::{BreadOffer, EnterpriseOpening, Enterprises},
    formal_household::{Household, HouseholdInvitation, Households},
    formal_ledger::{Balance, Ledger, MAX_AMOUNT},
    formal_livelihood::{self, Livelihood},
    formal_macro::{MacroEconomy, MarketInputs},
    formal_population::{AgeRangeCoverage, CohortId, HistoricalOpening, OpeningAssets, Population},
    formal_save::invalid,
    formal_service::{ServiceRoster, ServiceTarget},
    formal_stock::PersonalHolding,
    formal_wages::WageClaims,
    formal_work::{Job, WorkOpening, WorkState},
    transport::{operations::{Operations, OperationsState}, SegmentAvailability, TransportNetwork},
};
#[path = "formal_step.rs"]
mod step;
#[path = "formal_save_native.rs"]
mod save;
mod historical_places;
mod opening;
pub(crate) use save::WorldSnapshot;
#[cfg(test)]
use step::day_measurement;
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
use historical_places::historical_place_polity;
use wwo_character_core::{Language, ASSUMPTION};
#[cfg(test)]
use wwo_character_core::Prologue;

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

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct OpeningArea {
    pub id: String,
    pub label: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct OpeningSite {
    pub id: String,
    pub label: String,
    pub coordinates: [f64; 2],
    pub path: Vec<OpeningArea>,
    pub unavailable: Option<String>,
}

pub struct WorldBootstrap {
    organization_directory: Arc<OrganizationDirectory>,
    world: Arc<WorldSources>,
    population_assets: OpeningAssets,
    archived_population_worlds: BTreeMap<u32, std::sync::OnceLock<Arc<WorldSources>>>,
    populations: BTreeMap<String, u64>,
    market_opening_population: BTreeMap<String, u64>,
    historical_population: Arc<HistoricalOpening>,
    markets: Arc<MarketInputs>,
    residents: BTreeMap<String, i64>,
    opening_people: BTreeMap<String, Arc<OpeningPerson>>,
    opening_place_names: BTreeMap<String, String>,
    opening_sites: BTreeMap<String, Vec<OpeningSite>>,
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
    dated_place_jurisdictions: BTreeMap<String, String>,
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

pub struct Consumption {
    pub record_id: String,
    pub effective_minute: i64,
    pub allocations: Vec<ConsumptionAllocation>,
}

impl InitialWorld {
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
        let job = self.activities.written_job_notices.get(&self.player().opening_source_id)?;
        self.work_opening.jobs(&self.player, Some(&self.player().place_id), 0)
            .any(|row| row.id == *job).then_some(job.as_str())
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
        self.character.development.as_ref().is_none_or(|player| player.language().is_some_and(|language| player.can_read(language)))
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
        self.character.development.as_ref().and_then(|player| player.language())
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
                    && OPENINGS.iter().any(|&(source, place)| {
                        self.player().opening_source_id == source
                            && self.player().place_id.strip_prefix("place:") == Some(place)
                    })
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
    pub fn population_units(&self) -> &BTreeMap<String, u64> {
        self.population.totals()
    }

    pub fn population(&self) -> &Population { &self.population }

    pub fn inspect_population<'a>(&'a self, query: &'a str) -> io::Result<crate::formal_population::PopulationInspection<'a>> {
        self.inspect_population_view(query, true)
    }

    pub fn inspect_population_brief<'a>(&'a self, query: &'a str) -> io::Result<crate::formal_population::PopulationInspection<'a>> {
        self.inspect_population_view(query, false)
    }

    fn inspect_population_view<'a>(
        &'a self, query: &'a str, detailed: bool,
    ) -> io::Result<crate::formal_population::PopulationInspection<'a>> {
        let map_id = query.strip_prefix("state:").unwrap_or(query);
        let alias = self.sources.population_name_aliases.get(map_id).map(String::as_str);
        // A containing account locates the site. Only an exact alias can
        // expose an account's total as the population of a map point.
        let containing_account = if map_id.starts_with("place:") {
            [
                self.population.partition_at(map_id),
                self.sources.opening_parent_at(map_id),
                self.sources.dated_place_jurisdiction(map_id),
                self.transport.network().unit_at(map_id),
            ].into_iter().flatten().find(|account| self.population.population_total(account).is_some())
        } else {
            None
        };
        self.population.inspect_with_mapping(query, self.clock, alias, containing_account, detailed)
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

}

fn known_service_target(target: &ServiceTarget) -> bool {
    cfg!(test) && matches!(target, ServiceTarget::Strategic(id) if id == "fixture:paris_service")
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

fn read_list<T: DeserializeOwned>(bytes: &[u8], field: &str) -> io::Result<Vec<T>> {
    let mut document: Value = serde_json::from_slice(bytes)?;
    Ok(serde_json::from_value(document[field].take())?)
}

pub(crate) fn local_id(value: &str) -> bool {
    !value.is_empty() && value.bytes()
        .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'_' | b'-'))
}

#[cfg(test)]
mod tests;

#[cfg(test)]
#[path = "player_prologue_tests.rs"]
mod player_prologue_tests;
