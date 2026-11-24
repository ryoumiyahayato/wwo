use super::{
    column, columns, counter::CounterBook, freight,
    historical_places::{historical_place_polity, load_map, load_polities, load_population_bindings, load_regimental_opening_stations},
    local_id, migration, organization_activity::OrganizationActivity,
    organization_registration::{OrganizationDirectory, OrganizationMembers}, read_list, travel_live,
    InitialWorld, OpeningActivities, OpeningArea, OpeningPerson, OpeningSite, PlayerDay,
    WorldBootstrap, WorldSources, OPENINGS,
};
use crate::{
    formal_character, formal_clock::GameClock, formal_enterprise::{EnterpriseOpening, Enterprises},
    formal_household::Households, formal_ledger::{Ledger, CURRENCY, MAX_AMOUNT}, formal_livelihood::Livelihood,
    formal_macro::{CountryInputs, MacroEconomy, MarketInputs},
    formal_population::{HistoricalOpening, OpeningAssets, Population, MAX_POPULATION},
    formal_save::invalid, formal_service::ServiceRoster, formal_wages::WageClaims,
    formal_work::{WorkOpening, WorkState}, transport::operations::{Operations, OperationsState},
};
use serde::Deserialize;
use serde_json::Value;
use std::{collections::{BTreeMap, BTreeSet}, io, sync::Arc};
use wwo_character_core::{Language, Prologue, ASSUMPTION};

impl WorldBootstrap {
    pub fn load() -> io::Result<Self> {
        Self::load_from(&crate::formal_population::default_data_directory()?)
    }

    pub fn load_from(data: &std::path::Path) -> io::Result<Self> {
        let population_assets = OpeningAssets::open(data)?;
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
            population_name_aliases, dated_place_jurisdictions: crate::transport::opening_place_jurisdictions()?,
            population_income, historical_population: None, people: BTreeMap::new(), regimental_opening_stations,
        };
        let load_opening = |version| {
            HistoricalOpening::load(&population_assets, version, &populations, |id| world.polities.contains_key(id), |place| {
                world.opening_parent_at(place).or_else(|| world.dated_place_jurisdiction(place))
            })
        };
        // Freeze the existing market asset calibration when the census ledger changes.
        let calibration_version = population_assets.market_calibration_version();
        let historical_population = Arc::new(load_opening(population_assets.current_version())?);
        let market_opening_population = if calibration_version == historical_population.version() {
            historical_population.totals(&populations)
        } else {
            load_opening(calibration_version)?.totals(&populations)
        };
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
        let opening_sites = opening_sites(&world, &network, &populations, &historical_population, &opening_people)?;
        for (polity, sites) in &opening_sites {
            let Some(site) = sites.iter().find(|site| site.unavailable.is_none()) else { continue; };
            opening_people.entry(polity.clone()).or_insert_with(|| Arc::new(OpeningPerson {
                id: format!("person:formal_generated_{polity}_0001"),
                claim_id: format!("formal_population_claim:{polity}:0001"),
                opening_source_id: polity.clone(),
                polity_id: world.polities[polity].runtime_id(),
                place_id: site.id.clone(),
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
        let archived_population_worlds = population_assets.versions()
            .filter(|&version| version != historical_population.version())
            .map(|version| (version, std::sync::OnceLock::new()))
            .collect();
        Ok(Self {
            world: Arc::new(world),
            population_assets,
            archived_population_worlds,
            organization_directory: Arc::new(organization_directory),
            populations,
            market_opening_population,
            historical_population,
            markets: Arc::new(markets),
            residents,
            opening_people,
            opening_place_names,
            opening_sites,
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

    pub fn opening_sites(&self, source: &str) -> &[OpeningSite] {
        self.opening_sites.get(source).map_or(&[], Vec::as_slice)
    }

    pub fn create_at_with_prologue(&self, source: &str, place: &str, prologue: Prologue, health: Option<wwo_character_core::OpeningHealth>) -> io::Result<InitialWorld> {
        if prologue.age != 20 || !self.opening_sites(source).iter().any(|site| site.id == place && site.unavailable.is_none()) {
            return Err(invalid("出生地当前不可开局，或人物年龄无效。"));
        }
        let world = self.base_opening_version_at(source, Some(place), Some(prologue), health, Some(self.historical_population.version()))?;
        Self::finish_opening(world)
    }

    pub fn create(&self, source_id: &str) -> io::Result<InitialWorld> {
        self.create_opening(source_id, None, true)
    }

    pub fn create_with_prologue(&self, source_id: &str, prologue: Prologue) -> io::Result<InitialWorld> {
        self.create_opening(source_id, Some(prologue), true)
    }

    pub(super) fn create_opening(&self, source_id: &str, prologue: Option<Prologue>, historical: bool) -> io::Result<InitialWorld> {
        let world = self.base_opening(source_id, prologue, historical)?;
        Self::finish_opening(world)
    }

    pub(super) fn finish_opening(mut world: InitialWorld) -> io::Result<InitialWorld> {
        world.initialize_organization_members()?;
        world.plan_household_orders()?;
        world.settle_organization_employment()?;
        Ok(world)
    }

    pub(super) fn base_opening(&self, source_id: &str, prologue: Option<Prologue>, historical: bool) -> io::Result<InitialWorld> {
        let version = historical.then(|| self.historical_population.version());
        self.base_opening_version(source_id, prologue, version)
    }

    pub(super) fn base_opening_version(&self, source_id: &str, prologue: Option<Prologue>, version: Option<u32>) -> io::Result<InitialWorld> {
        self.base_opening_version_at(source_id, None, prologue, None, version)
    }

    pub(super) fn base_opening_version_at(&self, source_id: &str, place: Option<&str>, prologue: Option<Prologue>,
        health: Option<wwo_character_core::OpeningHealth>, version: Option<u32>) -> io::Result<InitialWorld> {
        let requested = version.unwrap_or(1);
        let sources = if requested == self.historical_population.version() {
            &self.world
        } else {
            let archived = self.archived_population_worlds.get(&requested).ok_or_else(|| io::Error::new(
                io::ErrorKind::NotFound, format!("historical population version {requested} is absent from the runtime catalogue"),
            ))?;
            if let Some(sources) = archived.get() {
                sources
            } else {
                let opening = HistoricalOpening::load(&self.population_assets, requested, &self.populations,
                    |id| self.world.polities.contains_key(id), |place| {
                        self.world.opening_parent_at(place).or_else(|| self.world.dated_place_jurisdiction(place))
                    })?;
                archived.get_or_init(|| Arc::new(WorldSources {
                    historical_population: Some(Arc::new(opening)),
                    ..self.world.as_ref().clone()
                }))
            }
        };
        let transport = Operations::restore(sources, 0, OperationsState::default())?;
        let default_origin = self.opening_people.get(source_id)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "unknown formal opening"))?;
        let alternate = place.filter(|&place| place != default_origin.place_id);
        let mut player_origin = if let Some(place) = alternate {
            if !self.opening_sites(source_id).iter().any(|site| site.id == place) {
                return Err(invalid("开局地点不属于所选政治实体。"));
            }
            Arc::new(OpeningPerson { place_id: place.to_owned(), ..default_origin.as_ref().clone() })
        } else {
            Arc::clone(default_origin)
        };
        let player = player_origin.id.clone();
        let development = prologue.map(|opening| {
            opening.build_with_health(self.opening_language(source_id), health).map_err(io::Error::other)
        }).transpose()?;
        if let Some(development) = &development {
            Arc::make_mut(&mut player_origin).birth_year = development.birth_year();
        }
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
        let residents = self.world.people.values().filter(|person| person.id != player);
        for person in residents.chain(std::iter::once(player_origin.as_ref())) {
            let parent = &sources.polity_population_bindings[&person.opening_source_id];
            let unit = if person.id == player && alternate.is_some() {
                opening_residence(sources, transport.network(), &population, &person.place_id)
                    .filter(|unit| population.parent_unit(unit) == Some(parent))
                    .ok_or_else(|| invalid("出生地没有有效的正式人口归属。"))?
            } else {
                population.partition_at(&person.place_id).unwrap_or(parent.as_str())
            }.to_owned();
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
            if person == player { Some(player_origin.place_id.as_str()) }
            else { self.world.people.get(person).map(|row| row.place_id.as_str()) }
        });
        let written_job_notice = prologue.is_some() && self.activities.written_job_notices.get(source_id).is_some_and(|job| {
            self.work.jobs(&player, Some(&player_origin.place_id), 0).any(|row| row.id == *job)
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
            freight: freight::FreightBook::default(),
            homes: BTreeMap::new(),
            service: ServiceRoster::default(),
            activities: Arc::clone(&self.activities),
            player_day: PlayerDay {
                written_job_notice,
                ..PlayerDay::default()
            },
            land_battle: None,
            land_battle_history: Vec::new(),
        })
    }
}

fn opening_residence<'a>(
    sources: &'a WorldSources, network: &crate::transport::TransportNetwork, population: &'a Population, place: &str,
) -> Option<&'a str> {
    population.partition_at(place).or_else(|| {
        let parent = sources.population_unit_at(place).or_else(|| network.unit_at(place))
            .or_else(|| sources.opening_parent_at(place))?;
        population.residence_parent(parent)
    })
}

fn opening_sites(
    sources: &WorldSources, network: &crate::transport::TransportNetwork, totals: &BTreeMap<String, u64>,
    historical: &Arc<HistoricalOpening>, defaults: &BTreeMap<String, Arc<OpeningPerson>>,
) -> io::Result<BTreeMap<String, Vec<OpeningSite>>> {
    use crate::transport::NodeKind;
    let mut population = Population::initialize_historical(totals, Arc::clone(historical));
    for person in sources.people.values() {
        let root = &sources.polity_population_bindings[&person.opening_source_id];
        let unit = population.partition_at(&person.place_id).unwrap_or(root).to_owned();
        population.claim(&person.id, &unit)?;
    }
    let mut sites = BTreeMap::<String, Vec<OpeningSite>>::new();
    let capitals: BTreeMap<_, _> = sources.polities.keys().filter_map(|polity| Some((network.capital_node(polity)?, polity.as_str()))).collect();
    let ids: BTreeSet<_> = network.nodes().filter(|node| node.kind == NodeKind::City).map(|node| node.id.as_str())
        .chain(sources.places.keys().map(String::as_str).filter(|place| {
            !place.starts_with("place:port_") && network.node(place).is_none_or(|node| node.kind == NodeKind::City)
        }))
        .chain(sources.dated_place_jurisdictions.keys().map(String::as_str))
        .chain(defaults.values().map(|person| person.place_id.as_str())).collect();
    let default_owners: BTreeMap<_, _> = defaults.iter()
        .map(|(owner, person)| (person.place_id.as_str(), owner.as_str())).collect();
    let aliases: BTreeSet<_> = ids.iter().copied()
        .filter(|id| id.starts_with("place:"))
        .filter_map(|id| network.routing_node(id).filter(|node| *node != id))
        .filter(|node| !default_owners.contains_key(node)).collect();
    for id in ids.into_iter().filter(|id| !aliases.contains(id)) {
        let Some(owner) = default_owners.get(id).copied()
            .or_else(|| sources.dated_place_jurisdiction(id))
            .filter(|owner| sources.polities.contains_key(*owner))
            .or_else(|| sources.place_polity(id).map(|polity| polity.id.as_str()))
            .or_else(|| capitals.get(id).copied())
        else { continue; };
        let Some(coordinates) = sources.places.get(id).and_then(|place| place.lon_lat)
            .or_else(|| network.node_coordinates(id)) else { continue; };
        let root = sources.polity_population_bindings.get(owner);
        let pool = opening_residence(sources, network, &population, id);
        let default = defaults.get(owner);
        let unavailable = if default.is_some_and(|person| person.place_id == id) {
            None
        } else if root.is_none() {
            Some("无正式人口账户")
        } else if !pool.is_some_and(|unit| population.parent_unit(unit) == root.map(String::as_str)) {
            Some("缺少居住归属")
        } else if !pool.is_some_and(|unit| population.unclassified(unit).unwrap_or(0) > 0
            || default.is_some_and(|person| population.unit_for_person(&person.id) == Some(unit)))
        {
            Some("无可登记居民")
        } else {
            None
        }.map(str::to_owned);
        let label = network.node_label(id).or_else(|| sources.places.get(id).map(|place| place.name.as_str())).unwrap_or(id);
        let path = pool.into_iter().flat_map(|unit| population.opening_geography(unit))
            .filter(|(_, name)| *name != label)
            .map(|(id, label)| OpeningArea { id: id.into(), label: label.into() }).collect();
        sites.entry(owner.into()).or_default().push(OpeningSite { id: id.into(), label: label.into(), coordinates, path, unavailable });
    }
    for rows in sites.values_mut() {
        rows.sort_by(|a, b| a.unavailable.is_some().cmp(&b.unavailable.is_some()).then(a.label.cmp(&b.label)));
    }
    Ok(sites)
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
    read_list(include_bytes!("../../../../data/formal/paris_employment_opening_r1.json"), "opening_residents")
}

fn load_opening_activities() -> io::Result<OpeningActivities> {
    let rules: OpeningActivities = serde_json::from_str(include_str!("../../../../data/character/opening_activities.json"))?;
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
    let policy: Policy = serde_json::from_slice(include_bytes!("../../../../data/formal/player_livelihood_r1.json"))?;
    if policy.policy_id != "player_livelihood_r1" || policy.basis != "GENERATED_SIMULATION_ASSUMPTION"
        || policy.denomination != CURRENCY || !(1..=MAX_AMOUNT).contains(&policy.opening_cash)
    {
        return Err(invalid("invalid formal opening livelihood policy"));
    }
    Ok(policy.opening_cash)
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
        "../../../../data/alpha/historical_world_economy_1900/countries_compact.json"
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

fn unsigned_columns<const N: usize>(row: &[Value], fields: [usize; N]) -> io::Result<[u64; N]> {
    let mut values = [0; N];
    for (value, index) in values.iter_mut().zip(fields) {
        *value = row[index].as_u64().ok_or_else(|| invalid("invalid unsigned country source number"))?;
    }
    Ok(values)
}
