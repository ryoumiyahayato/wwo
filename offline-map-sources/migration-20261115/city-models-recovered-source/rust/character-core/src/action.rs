use crate::{require, valid_text, CharacterSystem, Result, SCALE};
use serde::Serialize;

/// The host reads its existing ledger/assets/organization/information systems.
/// Neither a family label nor a capability score satisfies these requirements.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Requirement {
    Funds { currency: String, minor_units: u64 },
    AssetAccess { asset: String, quantity: u32 },
    Labor { role: String, count: u32 },
    MarketAccess { market: String },
    OrganizationAccess { organization: String },
    Permission { permission: String },
    Introduction { contact: String },
    Information { topic: String },
}
impl Requirement {
    fn valid(&self) -> bool {
        match self {
            Self::Funds {
                currency,
                minor_units,
            } => valid_text(currency) && *minor_units > 0,
            Self::AssetAccess { asset, quantity } => valid_text(asset) && *quantity > 0,
            Self::Labor { role, count } => valid_text(role) && *count > 0,
            Self::MarketAccess { market } => valid_text(market),
            Self::OrganizationAccess { organization } => valid_text(organization),
            Self::Permission { permission } => valid_text(permission),
            Self::Introduction { contact } => valid_text(contact),
            Self::Information { topic } => valid_text(topic),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum ConditionStatus {
    Met,
    Missing,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ConditionEvidence {
    pub status: ConditionStatus,
    /// Viewer-safe explanation, e.g. "缺少担保人，无法申请经营资格".
    pub explanation: String,
    pub source: String,
}

pub trait OpportunityHost {
    /// Evaluate against the current authoritative world, including any reserved
    /// funds and jointly required assets. Unknown is fail-closed, not free access.
    fn condition(
        &self,
        person: &str,
        action: &str,
        requirement: &Requirement,
        day: u32,
    ) -> ConditionEvidence;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionSpec {
    pub id: String,
    pub domain: String,
    pub requirements: Vec<Requirement>,
    pub knowledge_weight: u16,
    pub difficulty: u16,
    pub physical_demand: u16,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum Performance {
    Difficult,
    Manageable,
    Proficient,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ActionAssessment {
    pub ready: bool,
    /// None whenever a necessary condition is missing/unknown.
    pub performance: Option<Performance>,
    pub explanation: Vec<String>,
    pub conditions: Vec<ConditionEvidence>,
}

impl CharacterSystem {
    /// Read-only feasibility + contextual competence, NOT an authorization token,
    /// resource reservation, success roll or economic execution command.
    pub fn assess_action(
        &self,
        id: &str,
        spec: &ActionSpec,
        host: &impl OpportunityHost,
    ) -> Result<ActionAssessment> {
        require(
            valid_text(&spec.id)
                && valid_text(&spec.domain)
                && spec.requirements.len() <= 32
                && spec.requirements.iter().all(Requirement::valid)
                && [spec.knowledge_weight, spec.difficulty, spec.physical_demand]
                    .iter()
                    .all(|v| *v <= SCALE),
            "invalid action specification",
        )?;
        let person = self.record(id)?;
        if person.health.death.is_some() {
            return Ok(ActionAssessment {
                ready: false,
                performance: None,
                explanation: vec!["人物已去世，无法采取行动".into()],
                conditions: Vec::new(),
            });
        }
        let conditions: Vec<_> = spec
            .requirements
            .iter()
            .map(|r| host.condition(id, &spec.id, r, self.day()))
            .collect();
        require(
            conditions
                .iter()
                .all(|c| valid_text(&c.explanation) && valid_text(&c.source)),
            "condition evidence requires explanation and source",
        )?;
        let missing: Vec<_> = conditions
            .iter()
            .filter(|c| c.status != ConditionStatus::Met)
            .map(|c| c.explanation.clone())
            .collect();
        if !missing.is_empty() {
            return Ok(ActionAssessment {
                ready: false,
                performance: None,
                explanation: missing,
                conditions,
            });
        }
        let (knowledge, practice) = person
            .identity
            .capabilities
            .get(&spec.domain)
            .map_or((0, 0), |c| (i32::from(c.knowledge), i32::from(c.practice)));
        let weight = i32::from(spec.knowledge_weight);
        let capability = (knowledge * weight + practice * (1000 - weight)) / 1000;
        let modifier: i32 = person
            .experiences
            .values()
            .filter(|e| e.domain == spec.domain && e.expires_day.map_or(true, |d| d > self.day()))
            .map(|e| i32::from(e.efficiency_delta))
            .sum::<i32>()
            .clamp(-500, 500);
        // Knowledge stays intact while injury/illness can impair its application.
        let health_penalty = i32::from(1000 - person.health.current)
            * (250 + i32::from(spec.physical_demand) * 3 / 4)
            / 1000;
        let efficiency = (1000 + modifier - health_penalty).clamp(0, 1500);
        let effective = (capability * efficiency / 1000).clamp(0, 1000);
        let difficulty = i32::from(spec.difficulty);
        let performance = if effective < difficulty {
            Performance::Difficult
        } else if effective < difficulty + 150 {
            Performance::Manageable
        } else {
            Performance::Proficient
        };
        let mut explanation = vec!["必要条件已具备；执行时仍须由原领域复核并办理资源与权限".into()];
        explanation.push(
            match performance {
                Performance::Difficult => "相关知识或实践尚不足以稳妥处理这项任务",
                Performance::Manageable => "已有经验可以应对，但任务仍有难度",
                Performance::Proficient => "已有知识与实践较适合这项任务",
            }
            .into(),
        );
        if health_penalty > 0 {
            explanation.push("身体状况限制了当前能力发挥".into());
        }
        for experience in person
            .experiences
            .values()
            .filter(|e| e.domain == spec.domain && e.expires_day.map_or(true, |d| d > self.day()))
        {
            explanation.push(experience.label.clone());
        }
        Ok(ActionAssessment {
            ready: true,
            performance: Some(performance),
            explanation,
            conditions,
        })
    }
}
