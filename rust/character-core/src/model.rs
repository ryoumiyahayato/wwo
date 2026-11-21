use crate::{require, valid_text, Health, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const SCALE: u16 = 1000;
pub const MAX_RECORDS: usize = 128;
pub const DAYS_PER_YEAR: u32 = 365;

/// Domain-specific backend parameters. No universal intelligence/charisma stat.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Capability {
    pub knowledge: u16,
    pub practice: u16,
    pub learning: u16,
}
impl Default for Capability {
    fn default() -> Self {
        Self {
            knowledge: 0,
            practice: 0,
            learning: 500,
        }
    }
}
impl Capability {
    pub(crate) fn validate(&self) -> Result<()> {
        require(
            [self.knowledge, self.practice, self.learning]
                .iter()
                .all(|v| *v <= SCALE),
            "capability outside 0..1000",
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Experience {
    /// Stable source ID. A completed experience cannot be applied twice.
    pub id: String,
    pub label: String,
    pub domain: String,
    pub efficiency_delta: i16,
    pub expires_day: Option<u32>,
}
impl Experience {
    pub(crate) fn validate(&self) -> Result<()> {
        require(
            valid_text(&self.id)
                && valid_text(&self.label)
                && valid_text(&self.domain)
                && (-500..=500).contains(&self.efficiency_delta),
            "invalid experience",
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PersonSeed {
    /// Reuse the host's stable person ID; registration never creates population.
    pub id: String,
    pub name: String,
    /// Days relative to the host epoch, so people born before 1900 are negative.
    pub birth_day: i64,
    pub constitution: u16,
    pub capabilities: BTreeMap<String, Capability>,
    /// Explicit provenance for generated assumptions or imported evidence.
    pub basis: String,
}
impl PersonSeed {
    pub(crate) fn validate(&self, day: u32) -> Result<()> {
        require(
            self.id.starts_with("person:")
                && valid_text(&self.id)
                && self.id.len() > 7
                && valid_text(&self.name)
                && valid_text(&self.basis),
            "invalid person identity or basis",
        )?;
        require(
            self.birth_day <= i64::from(day)
                && self.birth_day >= -1_000_000
                && i64::from(day) - self.birth_day <= 200 * i64::from(DAYS_PER_YEAR),
            "invalid birth day",
        )?;
        require(
            self.constitution <= SCALE && self.capabilities.len() <= MAX_RECORDS,
            "invalid person parameters",
        )?;
        for (domain, capability) in &self.capabilities {
            require(valid_text(domain), "invalid domain")?;
            capability.validate()?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PersonRecord {
    pub identity: PersonSeed,
    pub registered_day: u32,
    pub health: Health,
    pub experiences: BTreeMap<String, Experience>,
    /// Consecutive event sequence prevents duplicate injury/training application.
    pub event_sequence: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub player: Option<crate::PlayerDevelopment>,
}
impl PersonRecord {
    pub fn age_days(&self, day: u32) -> u32 {
        u32::try_from((i64::from(day) - self.identity.birth_day).max(0)).unwrap_or(u32::MAX)
    }
    pub(crate) fn validate(&self, day: u32) -> Result<()> {
        self.identity.validate(self.registered_day)?;
        require(
            self.registered_day <= day && self.experiences.len() <= MAX_RECORDS,
            "invalid person record",
        )?;
        self.health.validate(day, self.registered_day)?;
        if let Some(player) = &self.player {
            player.validate(self.identity.birth_day, day)?;
        }
        for (id, experience) in &self.experiences {
            experience.validate()?;
            require(
                id == &experience.id
                    && experience
                        .expires_day
                        .map_or(true, |d| d > self.registered_day),
                "invalid experience reference or expiry",
            )?;
            require(
                self.identity.capabilities.contains_key(&experience.domain),
                "unknown experience domain",
            )?;
        }
        Ok(())
    }
}

/// Host-provided, viewer-authorized facts. None means unknown, never zero/poor.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SocialFacts {
    pub nationality: Option<String>,
    pub family_background: Option<String>,
    pub education: Option<String>,
    pub occupation: Option<String>,
    pub economic_situation: Option<String>,
    pub assets: Option<Vec<String>>,
    pub relationships: Option<Vec<String>>,
    pub positions: Option<Vec<String>>,
}

/// Deliberate projection, never serialized from the full backend record.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PersonView {
    pub id: String,
    pub name: String,
    pub age_years: u32,
    pub health_status: String,
    pub traits: Vec<String>,
    pub history: Vec<String>,
    pub social: SocialFacts,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LifeEvent {
    /// Input from an actual education/work event, not from opening a page.
    Learning {
        domain: String,
        study: u16,
        practice: u16,
        label: String,
    },
    /// Signed changes may combine gains with losses. Bounded, not infinite buffs.
    Experience {
        experience: Experience,
        knowledge_delta: i16,
        practice_delta: i16,
    },
    Injury {
        label: String,
        damage: u16,
        permanent_loss: u16,
    },
    Disease {
        label: String,
        severity: u16,
        duration_days: u16,
    },
    Death {
        cause: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeathRecord {
    pub day: u32,
    pub cause: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeathNotice {
    pub person_id: String,
    pub death: DeathRecord,
}
