use crate::calendar::year_start_day;
use serde::{Deserialize, Serialize};
use std::{collections::{BTreeMap, BTreeSet}, fs, io, path::Path};
use wwo_character_core::{
    ActionSpec, CharacterHost, CharacterSystem, ConditionEvidence, ConditionStatus, Error,
    Capability, CharacterSnapshot, Experience, Health, LifeEvent, LifeRules, LivingConditions,
    ObservedConditions, OpportunityHost, PersonRecord, PersonSeed, PersonView, Requirement, Result, SocialFacts,
    SNAPSHOT_SCHEMA,
};

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct SavedPerson {
    registered_day: u32,
    health: Health,
    capabilities: BTreeMap<String, Capability>,
    experiences: BTreeMap<String, Experience>,
    event_sequence: u64,
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

pub(crate) fn advance_opening_day(
    player: &str, people: &BTreeMap<String, Identity>, day: u32, state: &str, work: BTreeSet<String>,
) -> Result<CharacterOutput> {
    let mut request = Request::initialize(SHARED_WORLD.to_owned(), player, people.clone(), day, state);
    request.operation = "day".into();
    request.work = work;
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
            nutrition: self.nutrition.get(id).copied(),
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
                health: saved.health, experiences: saved.experiences, event_sequence: saved.event_sequence,
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
    match input.operation.as_str() {
        "restore" if input.day == system.day() => {}
        "day" if system.day().checked_add(1) == Some(input.day) => {
            system.advance_without_mortality(input.day, &input)?;
            for person in &input.work {
                learning(&mut system, person, "employment", "完成正式工作", 35)?;
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
    let profile = system.view(&input.player, input.social)?;
    let snapshot = system.snapshot();
    let state = serde_json::to_string(&Save {
        schema: SAVE_SCHEMA.into(), world: snapshot.world_id, day: snapshot.day, rules: snapshot.rules,
        people: snapshot.people.into_iter().map(|record| (record.identity.id, SavedPerson {
            registered_day: record.registered_day, health: record.health,
            capabilities: record.identity.capabilities, experiences: record.experiences,
            event_sequence: record.event_sequence,
        })).collect(),
    }).map_err(|e| Error(e.to_string()))?;
    Ok(CharacterOutput { state, profile, day: input.day, assessment, able_to_work })
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
