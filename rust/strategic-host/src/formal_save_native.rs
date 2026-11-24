//! Native slot payload and restoration of cross-domain references.
use super::*;
use crate::{
    formal_clock::ClockSnapshot,
    formal_macro::Shipment,
    formal_population::PopulationSnapshot,
    formal_save::typed_map,
    formal_service::ServiceSnapshot,
    formal_travel::LegacyTravel,
    formal_wages::Claim,
};

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
}

impl WorldBootstrap {
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
