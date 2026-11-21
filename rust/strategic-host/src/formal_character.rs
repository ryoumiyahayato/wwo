use crate::calendar::year_start_day;
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet}, fs, io, path::Path};
use wwo_character_core::{
    ActionSpec, CharacterHost, CharacterSystem, ConditionEvidence, ConditionStatus, Error,
    Capability, CharacterSnapshot, Experience, Health, LifeEvent, LifeRules, LivingConditions,
    ObservedConditions, OpportunityHost, PersonRecord, PersonSeed, PersonView, Requirement, Result, SocialFacts,
    SNAPSHOT_SCHEMA, DeathNotice, Education, Language, PlayerDevelopment,
};

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedPerson {
    registered_day: u32,
    health: Health,
    capabilities: BTreeMap<String, Capability>,
    experiences: BTreeMap<String, Experience>,
    event_sequence: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    player: Option<PlayerDevelopment>,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Save {
    schema: String,
    world: String,
    day: u32,
    rules: LifeRules,
    people: BTreeMap<String, SavedPerson>,
}

const SAVE_SCHEMA: &str = "formal_character_state_v1";
const SHARED_WORLD: &str = "formal_world_1900";

#[derive(Clone, Deserialize)]
pub(crate) struct Identity {
    // The world owns these fields and supplies them on every restore.
    birth_day: i64,
    name: String,
    basis: String,
    alive: bool,
}

impl Identity {
    pub(crate) fn new(birth_year: i64, name: String, basis: String, alive: bool) -> Result<Self> {
        if !(1700..=9999).contains(&birth_year) {
            return Err(Error("formal person has no supported birth year".into()));
        }
        Ok(Self {
            birth_day: year_start_day(birth_year) - year_start_day(1900),
            name,
            basis,
            alive,
        })
    }

    pub(crate) fn record_death(&mut self) { self.alive = false; }

    fn seed(&self, id: &str, capabilities: BTreeMap<String, Capability>) -> PersonSeed {
        PersonSeed {
            id: id.into(), name: self.name.clone(), birth_day: self.birth_day,
            basis: self.basis.clone(), constitution: 500, capabilities,
        }
    }
}

pub(crate) fn opening_identity(year: u16) -> Result<Identity> {
    Identity::new(i64::from(year), "姓名未记录".into(), "generated_simulation_assumption".into(), true)
}

#[derive(Serialize)]
pub(crate) struct CharacterOutput {
    pub state: String,
    pub profile: PersonView,
    pub day: u32,
    assessment: Option<wwo_character_core::ActionAssessment>,
    pub able_to_work: bool,
    #[serde(skip)]
    pub development: Option<PlayerDevelopment>,
    #[serde(skip)]
    pub deaths: Vec<DeathNotice>,
}

pub(crate) fn restore(
    opening: &str,
    player: &str,
    people: BTreeMap<String, Identity>,
    day: u32,
    state: &str,
) -> Result<CharacterOutput> {
    run(Request::for_world(opening, player, people, day, state))
}

pub(crate) fn assess_purchase(
    player: &str, people: &BTreeMap<String, Identity>, day: u32, state: &str,
    market: &str, amount: u64, available: u64,
) -> Result<CharacterOutput> {
    let mut request = Request::initialize(SHARED_WORLD.to_owned(), player, people.clone(), day, state);
    request.operation = "purchase".into();
    request.quote = Some(Quote {
        currency: crate::formal_ledger::CURRENCY.into(), amount, available: Some(available),
        market: market.to_owned(), accessible: true,
    });
    let result = run(request)?;
    if !result.assessment.as_ref().is_some_and(|decision| decision.ready) {
        return Err(Error("当前人物状态不允许这笔购买".into()));
    }
    Ok(result)
}

pub(crate) fn opening_with_prologue(
    player: &str, people: &BTreeMap<String, Identity>, development: PlayerDevelopment,
) -> Result<CharacterOutput> {
    let mut input = Request::initialize(SHARED_WORLD.into(), player, people.clone(), 0, "");
    input.prologue = Some(development);
    run(input)
}

pub(crate) fn restore_native_identities(
    player: &str, people: &mut BTreeMap<String, Identity>, day: u32, state: &str,
) -> Result<Vec<DeathNotice>> {
    let save: Save = serde_json::from_str(state).map_err(|error| Error(error.to_string()))?;
    if save.schema != SAVE_SCHEMA || save.day != day || save.people.keys().ne(people.keys()) {
        return Err(Error("formal character dates or roster differ".into()));
    }
    let mut deaths = Vec::new();
    for (id, saved) in save.people {
        let identity = people.get_mut(&id).unwrap();
        if let Some(development) = saved.player {
            if id != player { return Err(Error("player profile belongs to a different identity".into())); }
            *identity = opening_identity(development.birth_year())?;
        }
        if let Some(death) = saved.health.death {
            identity.alive = false;
            deaths.push(DeathNotice { person_id: id, death });
        }
    }
    Ok(deaths)
}

#[derive(Default)]
pub(crate) struct DayActivity {
    pub work: BTreeMap<String, String>,
    pub lesson: Option<(Language, u16, String)>,
    pub rest: bool,
    pub nutrition: Option<u16>,
    pub injury: Option<(u16, u16)>,
}

pub(crate) fn advance_opening_day(
    player: &str, people: &BTreeMap<String, Identity>, day: u32, state: &str, activity: DayActivity,
) -> Result<CharacterOutput> {
    let mut request = Request::initialize(SHARED_WORLD.to_owned(), player, people.clone(), day, state);
    request.operation = "day".into();
    request.activity = Some(activity);
    request.settled_day = day.checked_sub(1).ok_or_else(|| Error("invalid character day".into()))?;
    run(request)
}

pub(crate) fn opening_profile(
    player: &str, people: &BTreeMap<String, Identity>, day: u32, state: &str,
) -> Result<CharacterOutput> {
    run(Request::initialize(SHARED_WORLD.to_owned(), player, people.clone(), day, state))
}

impl Request {
    fn for_world(
        opening: &str, player: &str, people: BTreeMap<String, Identity>, day: u32, state: &str,
    ) -> Self {
        Self::initialize(format!("{opening}|{player}"), player, people, day, state)
    }

    fn initialize(world: String, player: &str, people: BTreeMap<String, Identity>, day: u32, state: &str) -> Self {
        Self {
            operation: "restore".into(),
            world,
            day,
            settled_day: day,
            state: state.to_owned(),
            people,
            player: player.to_owned(),
            social: SocialFacts::default(),
            nutrition: BTreeMap::new(),
            work: BTreeSet::new(),
            activity: None,
            prologue: None,
            quote: None,
        }
    }
}

#[derive(Deserialize)]
struct Request {
    operation: String,
    world: String,
    day: u32,
    settled_day: u32,
    state: String,
    people: BTreeMap<String, Identity>,
    player: String,
    #[serde(default)]
    social: SocialFacts,
    #[serde(default)]
    nutrition: BTreeMap<String, u16>,
    #[serde(default)]
    work: BTreeSet<String>,
    quote: Option<Quote>,
    #[serde(skip)]
    activity: Option<DayActivity>,
    #[serde(skip)]
    prologue: Option<PlayerDevelopment>,
}

#[derive(Deserialize)]
struct Quote {
    currency: String,
    amount: u64,
    available: Option<u64>,
    market: String,
    accessible: bool,
}

impl CharacterHost for Request {
    fn person_exists(&self, id: &str) -> bool {
        self.people.contains_key(id)
    }

    fn living_conditions(&self, _id: &str, _day: u32) -> Option<LivingConditions> {
        None
    }

    fn observed_conditions(&self, id: &str, day: u32) -> Option<ObservedConditions> {
        (day == self.day && self.people.contains_key(id)).then(|| ObservedConditions {
            nutrition: self.activity.as_ref().filter(|_| id == self.player)
                .and_then(|activity| activity.nutrition).or_else(|| self.nutrition.get(id).copied()),
            rest: self.activity.as_ref().filter(|activity| id == self.player && activity.rest).map(|_| 1000),
            // A rest day records no treatment. Absence of a treatment is distinct from unknown care.
            medical_care: self.activity.as_ref().filter(|activity| id == self.player && activity.rest).map(|_| 0),
            ..ObservedConditions::default()
        })
    }
}

impl OpportunityHost for Quote {
    fn condition(&self, _person: &str, _action: &str, requirement: &Requirement, _day: u32) -> ConditionEvidence {
        let (status, explanation, source) = match requirement {
            Requirement::Funds { currency, minor_units } if *currency == self.currency => {
                let (status, label) = match self.available {
                    Some(value) if value >= *minor_units => (ConditionStatus::Met, "正式账户资金充足"),
                    Some(_) => (ConditionStatus::Missing, "正式账户可用资金不足"),
                    None => (ConditionStatus::Unknown, "缺少可用资金记录"),
                };
                (status, label, "formal_ledger")
            }
            Requirement::MarketAccess { market } if *market == self.market && self.accessible =>
                (ConditionStatus::Met, "当前报价可访问", "formal_market"),
            _ => (ConditionStatus::Missing, "当前报价不可访问", "formal_market"),
        };
        ConditionEvidence { status, explanation: explanation.into(), source: source.into() }
    }
}

fn learning(system: &mut CharacterSystem, person: &str, domain: &str, label: &str, practice: u16) -> Result<()> {
    system.apply_next_event(person, LifeEvent::Learning {
        domain: domain.into(), study: 0, practice, label: label.into(),
    })?;
    Ok(())
}

fn run(input: Request) -> Result<CharacterOutput> {
    if !input.people.contains_key(&input.player) {
        return Err(Error("selected player is missing from the formal world".into()));
    }
    let mut system = if input.state.is_empty() {
        if input.operation != "restore" || input.day != input.settled_day {
            return Err(Error("missing formal character state".into()));
        }
        CharacterSystem::new(input.world.clone(), input.day, 0, LifeRules::default())?
    } else {
        let save: Save = serde_json::from_str(&input.state).map_err(|e| Error(e.to_string()))?;
        if save.schema != SAVE_SCHEMA || save.people.len() != input.people.len() {
            return Err(Error("invalid schema or formal person coverage".into()));
        }
        let people = save.people.into_iter().map(|(id, saved)| {
            let person = input.people.get(&id).ok_or_else(|| Error(format!("unknown formal person {id}")))?;
            Ok(PersonRecord {
                identity: person.seed(&id, saved.capabilities), registered_day: saved.registered_day,
                health: saved.health, experiences: saved.experiences, event_sequence: saved.event_sequence, player: saved.player,
            })
        }).collect::<Result<Vec<_>>>()?;
        CharacterSystem::from_snapshot(CharacterSnapshot {
            schema: SNAPSHOT_SCHEMA.into(), world_id: save.world, day: save.day, seed: 0,
            rules: save.rules, people,
        }, &input.world, input.settled_day, &input)?
    };
    let mut ids = BTreeSet::new();
    for record in system.snapshot().people {
        let id = record.identity.id;
        let person = &input.people[&id];
        if record.health.death.is_none() != person.alive || record.identity.birth_day != person.birth_day {
            return Err(Error(format!("formal identity conflict for {id}")));
        }
        ids.insert(id);
    }
    for (id, identity) in &input.people {
        if ids.contains(id) { continue; }
        if !input.state.is_empty() || !identity.alive {
            return Err(Error(format!("formal person coverage mismatch for {id}")));
        }
        system.register(identity.seed(id, BTreeMap::new()), &input)?;
    }
    let mut assessment = None;
    let mut deaths = Vec::new();
    match input.operation.as_str() {
        "restore" if input.day == system.day() => {
            if let Some(development) = input.prologue.clone() {
                system.create_player(&input.player, development)?;
            }
        }
        "day" if system.day().checked_add(1) == Some(input.day) => {
            let active = system.player_development(&input.player).is_some();
            deaths = system.advance_observed(input.day, &input, active.then_some(input.player.as_str()))?;
            let survived = |person: &str| !deaths.iter().any(|death| death.person_id == person);
            if let Some(activity) = &input.activity {
                for (person, job) in &activity.work {
                    if !survived(person) { continue; }
                    if active && person == &input.player {
                        let source = format!("shift:{job}:{}", input.day);
                        let matches_apprenticeship = job == "job:opening_paris_workshop";
                        system.completed_player_work(person, &source, matches_apprenticeship)?;
                    } else {
                        learning(&mut system, person, "employment", "完成正式工作", 35)?;
                    }
                }
                if survived(&input.player) {
                    if let Some((language, effort, source)) = &activity.lesson {
                        system.completed_reading_lesson(&input.player, *language, *effort, source)?;
                    }
                    if let Some((damage, loss)) = activity.injury {
                        if let Some(death) = system.apply_next_event(&input.player, LifeEvent::Injury {
                            label: "班次中的工伤".into(), damage, permanent_loss: loss,
                        })? {
                            deaths.push(death);
                        }
                    }
                }
            } else {
                for person in input.work.iter().filter(|person| survived(person)) {
                    learning(&mut system, person, "employment", "完成正式工作", 35)?;
                }
            }
        }
        "purchase" if input.day == system.day() => {
            let quote = input.quote.as_ref().ok_or_else(|| Error("missing purchase quote".into()))?;
            let spec = ActionSpec {
                id: "purchase".into(), domain: "market_purchase".into(),
                requirements: vec![
                    Requirement::Funds { currency: quote.currency.clone(), minor_units: quote.amount },
                    Requirement::MarketAccess { market: quote.market.clone() },
                ],
                knowledge_weight: 500, difficulty: 25, physical_demand: 180,
            };
            let decision = system.assess_action(&input.player, &spec, quote)?;
            if decision.ready {
                learning(&mut system, &input.player, "market_purchase", "完成正式市场下单", 40)?;
            }
            assessment = Some(decision);
        }
        _ => return Err(Error("invalid operation or formal day mismatch".into())),
    }
    let able_to_work = system.can_do_physical_work(&input.player)?;
    let development = system.player_development(&input.player).cloned();
    let mut profile = system.view(&input.player, input.social)?;
    if let Some(player) = &development {
        let origin = player.opening();
        profile.age_years = formal_age(player.birth_year(), input.day, &system, &input.player);
        profile.social.family_background = Some(origin.family.label().into());
        profile.social.education = Some(if player.can_read(player.language()) {
            format!("识字 · {}", player.language().label())
        } else { Education::HomeWork.label().into() });
        profile.history.splice(0..0, player.history().iter().map(|past| {
            format!("{}-{} {}", past.start_year, past.end_year, past.label)
        }));
    }
    let snapshot = system.snapshot();
    let state = serde_json::to_string(&Save {
        schema: SAVE_SCHEMA.into(), world: snapshot.world_id, day: snapshot.day, rules: snapshot.rules,
        people: snapshot.people.into_iter().map(|record| (record.identity.id, SavedPerson {
            registered_day: record.registered_day, health: record.health,
            capabilities: record.identity.capabilities, experiences: record.experiences,
            event_sequence: record.event_sequence, player: record.player,
        })).collect(),
    }).map_err(|e| Error(e.to_string()))?;
    Ok(CharacterOutput { state, profile, day: input.day, assessment, able_to_work, development, deaths })
}

fn formal_age(birth_year: u16, day: u32, system: &CharacterSystem, id: &str) -> u32 {
    let day = system.death(id).map_or(day, |death| death.day);
    let mut clock = crate::formal_clock::GameClock::default();
    clock.advance_minutes(i64::from(day) * crate::formal_clock::MINUTES_PER_DAY).unwrap();
    (clock.current_date().year - i64::from(birth_year)) as u32
}

#[derive(Deserialize)]
struct Envelope { serial: u32, request: serde_json::Value }

pub fn poll(folder: &Path) -> io::Result<()> {
    let pending = folder.join("character-request.json");
    let active = folder.join("character-active.json");
    match fs::rename(pending, &active) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    }
    let request = fs::read(&active);
    let _ = fs::remove_file(&active);
    let message: Envelope = serde_json::from_slice(&request?)?;
    let outcome = serde_json::from_value(message.request)
        .map_err(|error| Error(error.to_string()))
        .and_then(run);
    let result = match outcome {
        Ok(payload) => serde_json::json!({"serial":message.serial, "ok":true, "payload":payload}),
        Err(error) => serde_json::json!({"serial":message.serial, "ok":false, "error":error.to_string()}),
    };
    let temp = folder.join("character-response.tmp");
    fs::write(&temp, serde_json::to_vec(&result)?)?;
    fs::rename(temp, folder.join("character-response.json"))?;
    Ok(())
}
