use crate::health::mortality_roll;
use crate::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const SNAPSHOT_SCHEMA: &str = "wwo_character_core_v1";
pub const MAX_NAMED_PERSONS: usize = 10_000;
pub const MAX_ADVANCE_DAYS: u32 = 366;
pub const MAX_SNAPSHOT_BYTES: usize = 32 * 1024 * 1024;

pub trait CharacterHost {
    /// Only register identities already materialized by the population owner.
    fn person_exists(&self, id: &str) -> bool;
    /// Conditions for the interval (day - 1, day], not today's conditions applied
    /// retroactively to a long advance. Missing facts abort the whole advance.
    fn living_conditions(&self, id: &str, day: u32) -> Option<LivingConditions>;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CharacterSnapshot {
    pub schema: String,
    pub world_id: String,
    pub day: u32,
    pub seed: u64,
    pub rules: LifeRules,
    pub people: Vec<PersonRecord>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CharacterSystem {
    world_id: String,
    day: u32,
    seed: u64,
    rules: LifeRules,
    people: BTreeMap<String, PersonRecord>,
}

impl CharacterSystem {
    pub fn new(world_id: String, day: u32, seed: u64, rules: LifeRules) -> Result<Self> {
        require(valid_text(&world_id), "invalid world ID")?;
        rules.validate()?;
        Ok(Self {
            world_id,
            day,
            seed,
            rules,
            people: BTreeMap::new(),
        })
    }
    /// Settlement cursor only; the host clock is the world-time authority.
    pub fn day(&self) -> u32 {
        self.day
    }
    pub fn person_count(&self) -> usize {
        self.people.len()
    }
    pub(crate) fn record(&self, id: &str) -> Result<&PersonRecord> {
        self.people
            .get(id)
            .ok_or_else(|| Error("unknown named person".into()))
    }
    pub fn register(&mut self, identity: PersonSeed, host: &impl CharacterHost) -> Result<()> {
        identity.validate(self.day)?;
        require(
            host.person_exists(&identity.id),
            "person must already exist in authoritative population",
        )?;
        require(
            !self.people.contains_key(&identity.id) && self.people.len() < MAX_NAMED_PERSONS,
            "duplicate person or named-person limit",
        )?;
        let mut person = PersonRecord {
            identity,
            registered_day: self.day,
            health: Health::default(),
            experiences: BTreeMap::new(),
            event_sequence: 0,
        };
        person.health.recovery_ceiling = self.rules.ceiling(&person, self.day);
        person.health.current = person.health.recovery_ceiling;
        self.people.insert(person.identity.id.clone(), person);
        Ok(())
    }

    /// Atomic on error; applies only at the current settled day. The caller must
    /// first settle earlier time under its original conditions.
    pub fn apply_event(
        &mut self,
        id: &str,
        sequence: u64,
        event: LifeEvent,
    ) -> Result<Option<DeathNotice>> {
        let mut person = self.record(id)?.clone();
        require(
            person.health.death.is_none(),
            "cannot change a deceased person",
        )?;
        require(
            person.event_sequence.checked_add(1) == Some(sequence),
            "event sequence must be next; duplicate or out-of-order event",
        )?;
        match event {
            LifeEvent::Learning {
                domain,
                study,
                practice,
                label,
            } => {
                require(
                    valid_text(&domain)
                        && valid_text(&label)
                        && study <= SCALE
                        && practice <= SCALE,
                    "invalid learning event",
                )?;
                require(
                    person.identity.capabilities.contains_key(&domain)
                        || person.identity.capabilities.len() < MAX_RECORDS,
                    "domain limit",
                )?;
                let capability = person
                    .identity
                    .capabilities
                    .entry(domain.clone())
                    .or_default();
                capability.knowledge = learn(capability.knowledge, study, capability.learning);
                capability.practice = learn(capability.practice, practice, capability.learning);
                let source = format!("learning:{domain}");
                require(
                    person.experiences.contains_key(&source)
                        || person.experiences.len() < MAX_RECORDS,
                    "experience limit",
                )?;
                person.experiences.insert(
                    source.clone(),
                    Experience {
                        id: source,
                        label,
                        domain,
                        efficiency_delta: 0,
                        expires_day: None,
                    },
                );
            }
            LifeEvent::Experience {
                experience,
                knowledge_delta,
                practice_delta,
            } => {
                experience.validate()?;
                require(
                    (-1000..=1000).contains(&knowledge_delta)
                        && (-1000..=1000).contains(&practice_delta)
                        && experience.expires_day.map_or(true, |d| d > self.day),
                    "invalid experience change",
                )?;
                require(
                    !person.experiences.contains_key(&experience.id)
                        && person.experiences.len() < MAX_RECORDS,
                    "duplicate experience source or limit",
                )?;
                let capability = person
                    .identity
                    .capabilities
                    .get_mut(&experience.domain)
                    .ok_or_else(|| Error("unknown experience domain".into()))?;
                capability.knowledge = (i32::from(capability.knowledge)
                    + i32::from(knowledge_delta))
                .clamp(0, 1000) as u16;
                capability.practice = (i32::from(capability.practice) + i32::from(practice_delta))
                    .clamp(0, 1000) as u16;
                person.experiences.insert(experience.id.clone(), experience);
            }
            LifeEvent::Injury {
                label,
                damage,
                permanent_loss,
            } => {
                require(
                    valid_text(&label) && damage <= SCALE && permanent_loss <= SCALE,
                    "invalid injury",
                )?;
                if permanent_loss > 0 && !person.health.injuries.contains(&label) {
                    require(
                        person.health.injuries.len() < MAX_RECORDS,
                        "injury history limit",
                    )?;
                    person.health.injuries.push(label);
                }
                // Constitution reduces the response to the incident, not the
                // host's asset/money/opportunity requirements.
                let resistance = 500 + u32::from(person.identity.constitution);
                let effective_damage = (u32::from(damage) * 1000 / resistance).min(1000) as u16;
                person.health.permanent_loss = person
                    .health
                    .permanent_loss
                    .saturating_add(permanent_loss)
                    .min(SCALE);
                person.health.recovery_ceiling = self.rules.ceiling(&person, self.day);
                person.health.current = person
                    .health
                    .current
                    .saturating_sub(effective_damage)
                    .min(person.health.recovery_ceiling);
                if person.health.current == 0 {
                    person.health.death = Some(DeathRecord {
                        day: self.day,
                        cause: "致命损伤".into(),
                    });
                }
            }
            LifeEvent::Disease {
                label,
                severity,
                duration_days,
            } => {
                require(
                    valid_text(&label) && (1..=SCALE).contains(&severity) && duration_days > 0,
                    "invalid disease event",
                )?;
                require(
                    person.health.disease.is_none(),
                    "active disease must finish before another episode",
                )?;
                let until_day = self
                    .day
                    .checked_add(u32::from(duration_days))
                    .ok_or_else(|| Error("disease date overflow".into()))?;
                person.health.disease = Some(Disease {
                    label,
                    severity,
                    until_day,
                });
            }
            LifeEvent::Death { cause } => {
                require(valid_text(&cause), "invalid death cause")?;
                person.health.death = Some(DeathRecord {
                    day: self.day,
                    cause,
                });
            }
        }
        person.event_sequence = sequence;
        person.validate(self.day)?;
        let notice = person.health.death.clone().map(|death| DeathNotice {
            person_id: id.into(),
            death,
        });
        self.people.insert(id.into(), person);
        Ok(notice)
    }

    /// No frame updates. Named people only, once per elapsed simulation day.
    /// Work per call is bounded; repeat in <=366-day chunks for larger advances.
    /// Returns deaths exactly once. Host must adopt them with population/identity
    /// changes in the same candidate-world transaction (see README).
    pub fn advance_to(&mut self, day: u32, host: &impl CharacterHost) -> Result<Vec<DeathNotice>> {
        require(
            day >= self.day && day - self.day <= MAX_ADVANCE_DAYS,
            "backwards or oversized time advance",
        )?;
        if day == self.day {
            return Ok(Vec::new());
        }
        let mut candidate = self.people.clone();
        let mut deaths = Vec::new();
        for current_day in self.day + 1..=day {
            for person in candidate.values_mut() {
                let was_alive = person.health.death.is_none();
                if was_alive {
                    require(
                        host.person_exists(&person.identity.id),
                        "host person disappeared",
                    )?;
                    let conditions = host
                        .living_conditions(&person.identity.id, current_day)
                        .ok_or_else(|| Error("missing historical living conditions".into()))?;
                    conditions.validate()?;
                    self.rules.settle(
                        person,
                        current_day,
                        &conditions,
                        mortality_roll(self.seed, &person.identity.id, current_day),
                    );
                } else {
                    if person
                        .health
                        .disease
                        .as_ref()
                        .is_some_and(|d| d.until_day <= current_day)
                    {
                        person.health.disease = None;
                    }
                }
                if was_alive {
                    if let Some(death) = &person.health.death {
                        deaths.push(DeathNotice {
                            person_id: person.identity.id.clone(),
                            death: death.clone(),
                        });
                    }
                }
            }
        }
        self.people = candidate;
        self.day = day;
        Ok(deaths)
    }

    pub fn view(&self, id: &str, social: SocialFacts) -> Result<PersonView> {
        let person = self.record(id)?;
        let mut traits: Vec<_> = person
            .experiences
            .values()
            .filter(|e| e.expires_day.map_or(true, |d| d > self.day))
            .map(|e| e.label.clone())
            .collect();
        if person.identity.constitution >= 800 {
            traits.push("体质强健".into());
        }
        traits.extend(person.health.injuries.clone());
        if let Some(disease) = &person.health.disease {
            traits.push(disease.label.clone());
        }
        traits.sort();
        traits.dedup();
        let age_day = person.health.death.as_ref().map_or(self.day, |d| d.day);
        Ok(PersonView {
            id: id.into(),
            name: person.identity.name.clone(),
            age_years: person.age_days(age_day) / DAYS_PER_YEAR,
            health_status: person.health.status().into(),
            traits,
            history: person
                .experiences
                .values()
                .map(|e| e.label.clone())
                .collect(),
            social,
        })
    }
    /// Full backend state: do not send to normal player UI.
    pub fn snapshot(&self) -> CharacterSnapshot {
        CharacterSnapshot {
            schema: SNAPSHOT_SCHEMA.into(),
            world_id: self.world_id.clone(),
            day: self.day,
            seed: self.seed,
            rules: self.rules.clone(),
            people: self.people.values().cloned().collect(),
        }
    }
    pub fn from_snapshot(
        snapshot: CharacterSnapshot,
        world_id: &str,
        host_day: u32,
        host: &impl CharacterHost,
    ) -> Result<Self> {
        require(
            snapshot.schema == SNAPSHOT_SCHEMA
                && snapshot.world_id == world_id
                && snapshot.day == host_day,
            "snapshot schema, world or clock mismatch",
        )?;
        require(
            snapshot.people.len() <= MAX_NAMED_PERSONS,
            "snapshot person limit",
        )?;
        let mut candidate = Self::new(
            snapshot.world_id,
            snapshot.day,
            snapshot.seed,
            snapshot.rules,
        )?;
        for person in snapshot.people {
            person.validate(host_day)?;
            require(
                host.person_exists(&person.identity.id)
                    && !candidate.people.contains_key(&person.identity.id),
                "snapshot has missing or duplicate person",
            )?;
            let ceiling_day = person.health.death.as_ref().map_or(host_day, |d| d.day);
            require(
                person.health.recovery_ceiling == candidate.rules.ceiling(&person, ceiling_day),
                "snapshot recovery ceiling disagrees with rules",
            )?;
            candidate.people.insert(person.identity.id.clone(), person);
        }
        Ok(candidate)
    }
    pub fn to_json(&self) -> Result<Vec<u8>> {
        let bytes = serde_json::to_vec(&self.snapshot()).map_err(|e| Error(e.to_string()))?;
        require(bytes.len() <= MAX_SNAPSHOT_BYTES, "snapshot byte limit")?;
        Ok(bytes)
    }
    /// Candidate restore; never changes an existing world on parse/validation failure.
    pub fn from_json(
        bytes: &[u8],
        world_id: &str,
        host_day: u32,
        host: &impl CharacterHost,
    ) -> Result<Self> {
        require(bytes.len() <= MAX_SNAPSHOT_BYTES, "snapshot byte limit")?;
        let snapshot = serde_json::from_slice(bytes).map_err(|e| Error(e.to_string()))?;
        Self::from_snapshot(snapshot, world_id, host_day, host)
    }
}

fn learn(current: u16, effort: u16, learning: u16) -> u16 {
    if effort == 0 || current == SCALE {
        return current;
    }
    let gain = (u64::from(effort) * u64::from(250 + learning) * u64::from(SCALE - current)
        / 1_000_000)
        .max(1);
    (u64::from(current) + gain).min(u64::from(SCALE)) as u16
}
