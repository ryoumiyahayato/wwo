use crate::{
    require, valid_text, DeathRecord, PersonRecord, Result, DAYS_PER_YEAR, MAX_RECORDS, SCALE,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Disease {
    pub label: String,
    pub severity: u16,
    pub until_day: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Health {
    pub current: u16,
    pub permanent_loss: u16,
    pub recovery_ceiling: u16,
    pub injuries: Vec<String>,
    pub disease: Option<Disease>,
    pub death: Option<DeathRecord>,
}
impl Default for Health {
    fn default() -> Self {
        Self {
            current: SCALE,
            permanent_loss: 0,
            recovery_ceiling: SCALE,
            injuries: Vec::new(),
            disease: None,
            death: None,
        }
    }
}
impl Health {
    pub(crate) fn validate(&self, day: u32, registered: u32) -> Result<()> {
        require(
            self.current <= self.recovery_ceiling
                && self.recovery_ceiling <= SCALE.saturating_sub(self.permanent_loss)
                && self.permanent_loss <= SCALE
                && self.injuries.len() <= MAX_RECORDS
                && self.injuries.iter().all(|s| valid_text(s)),
            "invalid health limits",
        )?;
        require(
            self.current > 0 || self.death.is_some(),
            "zero health must be deceased",
        )?;
        if let Some(disease) = &self.disease {
            require(
                valid_text(&disease.label)
                    && (1..=SCALE).contains(&disease.severity)
                    && disease.until_day > day,
                "invalid disease",
            )?;
        }
        if let Some(death) = &self.death {
            require(
                death.day >= registered && death.day <= day && valid_text(&death.cause),
                "invalid death record",
            )?;
        }
        Ok(())
    }
    pub fn status(&self) -> &'static str {
        if self.death.is_some() {
            "已去世"
        } else if self.current < 250 {
            "危重"
        } else if self.disease.is_some() {
            "患病"
        } else if self.current < 650 {
            "身体虚弱"
        } else if self.permanent_loss > 0 {
            "有永久损伤，状况稳定"
        } else {
            "良好"
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LivingConditions {
    pub nutrition: u16,
    pub medical_care: u16,
    pub safety: u16,
    pub rest: u16,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ObservedConditions {
    pub nutrition: Option<u16>,
    pub medical_care: Option<u16>,
    pub safety: Option<u16>,
    pub rest: Option<u16>,
}

impl From<LivingConditions> for ObservedConditions {
    fn from(value: LivingConditions) -> Self {
        Self {
            nutrition: Some(value.nutrition),
            medical_care: Some(value.medical_care),
            safety: Some(value.safety),
            rest: Some(value.rest),
        }
    }
}
impl LivingConditions {
    pub(crate) fn validate(&self) -> Result<()> {
        require(
            [self.nutrition, self.medical_care, self.safety, self.rest]
                .iter()
                .all(|v| *v <= SCALE),
            "invalid living conditions",
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MortalityBand {
    pub from_age_years: u16,
    pub daily_risk_per_million: u32,
}

/// Development assumptions, NOT historical life tables or medical predictions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LifeRules {
    pub basis: String,
    pub ageing_start_years: u16,
    pub ceiling_loss_per_year: u16,
    pub recovery_per_day: u16,
    pub disease_damage_per_day: u16,
    pub mortality: Vec<MortalityBand>,
}
impl Default for LifeRules {
    fn default() -> Self {
        Self {
            basis: "GENERATED_SIMULATION_ASSUMPTION: provisional character rules v1".into(),
            ageing_start_years: 45,
            ceiling_loss_per_year: 6,
            recovery_per_day: 12,
            disease_damage_per_day: 35,
            mortality: [
                (0, 150),
                (5, 5),
                (18, 10),
                (50, 50),
                (65, 200),
                (80, 1000),
                (95, 5000),
                (110, 30000),
                (125, 1_000_000),
            ]
            .into_iter()
            .map(|(age, risk)| MortalityBand {
                from_age_years: age,
                daily_risk_per_million: risk,
            })
            .collect(),
        }
    }
}
impl LifeRules {
    pub(crate) fn validate(&self) -> Result<()> {
        require(
            valid_text(&self.basis)
                && (18..=100).contains(&self.ageing_start_years)
                && self.ceiling_loss_per_year <= 50
                && self.recovery_per_day <= SCALE
                && self.disease_damage_per_day <= SCALE
                && !self.mortality.is_empty()
                && self.mortality.len() <= 32,
            "invalid life rules",
        )?;
        require(
            self.mortality[0].from_age_years == 0
                && self
                    .mortality
                    .windows(2)
                    .all(|w| w[0].from_age_years < w[1].from_age_years)
                && self
                    .mortality
                    .iter()
                    .all(|b| b.daily_risk_per_million <= 1_000_000)
                && self.mortality.last().is_some_and(|b| {
                    b.daily_risk_per_million == 1_000_000 && b.from_age_years <= 150
                }),
            "mortality requires ordered ages and a finite terminal band",
        )
    }
    pub(crate) fn ceiling(&self, person: &PersonRecord, day: u32) -> u16 {
        let adult_days = person
            .age_days(day)
            .saturating_sub(u32::from(self.ageing_start_years) * DAYS_PER_YEAR);
        let ageing = (u64::from(adult_days) * u64::from(self.ceiling_loss_per_year)
            / u64::from(DAYS_PER_YEAR))
        .min(900) as u16;
        SCALE
            .saturating_sub(person.health.permanent_loss)
            .saturating_sub(ageing)
    }
    pub(crate) fn settle(
        &self,
        person: &mut PersonRecord,
        day: u32,
        conditions: &ObservedConditions,
        mortality_roll: Option<u32>,
    ) {
        if person.health.death.is_some() {
            if person
                .health
                .disease
                .as_ref()
                .is_some_and(|d| d.until_day <= day)
            {
                person.health.disease = None;
            }
            return;
        }
        person.health.recovery_ceiling = self.ceiling(person, day);
        let severity = person
            .health
            .disease
            .as_ref()
            .map_or(0, |d| u32::from(d.severity));
        let resistance = 500 + u32::from(person.identity.constitution);
        let recovery = match (conditions.nutrition, conditions.rest, conditions.medical_care) {
            (Some(nutrition), Some(rest), Some(care)) => {
                u32::from(self.recovery_per_day) * u32::from(nutrition) / 1000
                    * u32::from(rest) / 1000 * resistance / 1000 * (500 + u32::from(care)) / 1000
            }
            _ => 0,
        };
        let recovery = if recovery > 0 {
            (f64::from(recovery) * person.player.as_ref().map_or(1.0, |player| player.recovery_rate())).round() as u32
        } else { 0 };
        let illness = u32::from(self.disease_damage_per_day) * severity / resistance;
        let deprivation = conditions.nutrition.map_or(0, |food| u32::from(300u16.saturating_sub(food)) / 30);
        person.health.current = (u32::from(person.health.current) + recovery)
            .saturating_sub(illness + deprivation)
            .min(u32::from(person.health.recovery_ceiling)) as u16;
        let age = person.age_days(day) / DAYS_PER_YEAR;
        let baseline = self
            .mortality
            .iter()
            .rev()
            .find(|b| u32::from(b.from_age_years) <= age)
            .unwrap()
            .daily_risk_per_million;
        let risk = if baseline == 1_000_000 {
            baseline
        } else {
            ((u64::from(baseline) * 1000 / u64::from(resistance))
                + conditions.medical_care.map_or(0, |care| u64::from(severity) * u64::from(1000 - care) / 100)
                + conditions.safety.map_or(0, |safety| u64::from(1000 - safety) / 10))
                .min(1_000_000) as u32
        };
        if person.health.current == 0 || mortality_roll.is_some_and(|roll| roll < risk) {
            let cause = if person.health.disease.is_some() {
                "疾病"
            } else if person.health.current == 0 {
                "身体衰竭"
            } else if age >= 65 {
                "老年死亡风险"
            } else {
                "疾病或生活环境风险"
            };
            person.health.death = Some(DeathRecord {
                day,
                cause: cause.into(),
            });
        }
        if person
            .health
            .disease
            .as_ref()
            .is_some_and(|d| d.until_day <= day)
        {
            person.health.disease = None;
        }
    }
}

/// Stable per-person/day random stream; iteration order and batching do not matter.
pub(crate) fn mortality_roll(seed: u64, id: &str, day: u32) -> u32 {
    let mut value = seed ^ u64::from(day).wrapping_mul(0x9e3779b97f4a7c15);
    for byte in id.bytes() {
        value = (value ^ u64::from(byte)).wrapping_mul(0x100000001b3);
    }
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58476d1ce4e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d049bb133111eb);
    ((value ^ (value >> 31)) % 1_000_000) as u32
}
