use crate::{Error, Result, SCALE, require, valid_text};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::LazyLock,
};

pub const ASSUMPTION: &str = "GENERATED_SIMULATION_ASSUMPTION";
const EPOCH_YEAR: u16 = 1900;

#[derive(Deserialize)]
struct Catalog {
    attributes: Vec<AttributeRule>,
    traits: Vec<TraitRule>,
}

#[derive(Deserialize)]
struct AttributeRule {
    id: String,
    baseline: u16,
    modifier: Modifier,
}

#[derive(Deserialize)]
struct Modifier {
    trigger: String,
    operation: String,
    value: i32,
}

#[derive(Deserialize)]
struct TraitRule {
    id: String,
    label_zh: String,
    min_age: u8,
    exclusive_group: Option<String>,
    effects: Vec<Modifier>,
}

static CATALOG: LazyLock<Catalog> = LazyLock::new(|| {
    let catalog: Catalog = serde_json::from_str(include_str!(
        "../../../data/character/player_traits_v0_2.json"
    ))
    .expect("revised player trait data");
    assert_eq!(catalog.attributes.len(), 8);
    assert_eq!(catalog.traits.len(), 22);
    catalog
});

fn trait_rule(id: &str) -> Option<&'static TraitRule> {
    CATALOG.traits.iter().find(|rule| rule.id == id)
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Family {
    Poor,
    Ordinary,
    Wealthy,
}

impl Family {
    pub fn label(self) -> &'static str {
        match self {
            Self::Poor => "贫寒",
            Self::Ordinary => "普通",
            Self::Wealthy => "富裕",
        }
    }

    pub fn childhood_schooling(self) -> &'static str {
        match self {
            Self::Poor => "借书向邻里学读写",
            Self::Ordinary => "在本地学校学读写",
            Self::Wealthy => "随家庭教师学读写",
        }
    }

    /// Share of the existing opening ledger endowment. Generated balance parameters.
    pub fn opening_cash(self, standard: i64) -> i64 {
        match self {
            Self::Poor => standard / 5,
            Self::Ordinary => standard,
            Self::Wealthy => standard * 4,
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Education {
    HomeWork,
    ReadingLessons,
}

impl Education {
    pub fn label(self) -> &'static str {
        match self {
            Self::HomeWork => "在家帮工，未学读写",
            Self::ReadingLessons => "接受读写教育",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Youth {
    Labor,
    Apprentice,
    CommercialAssistant,
    AdvancedStudy,
}

impl Youth {
    pub fn label(self) -> &'static str {
        match self {
            Self::Labor => "从事体力劳动",
            Self::Apprentice => "担任工场学徒",
            Self::CommercialAssistant => "协助商号盘点与交货",
            Self::AdvancedStudy => "继续读书",
        }
    }

    pub fn eligible(self, age: u8, education: Education) -> bool {
        match self {
            Self::Labor | Self::Apprentice => age >= 18,
            Self::CommercialAssistant => age >= 20 && education == Education::ReadingLessons,
            Self::AdvancedStudy => age >= 20 && education == Education::ReadingLessons,
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Temperament {
    Practice,
    Persist,
    Endure,
    Recover,
    Struggle,
    Leave,
    Illness,
    Rescue,
}

impl Temperament {
    pub fn label(self) -> &'static str {
        match self {
            Self::Practice => "请教后领会很快，又反复练习",
            Self::Persist => "把活儿分段，逐项做完",
            Self::Endure => "照料身体，循序加练",
            Self::Recover => "休息了一季，旧伤仍在",
            Self::Struggle => "学得慢，但每天坚持练习",
            Self::Leave => "经常没做完就去干别的活",
            Self::Illness => "久病后复工，身体恢复很慢",
            Self::Rescue => "邻家失火时救人，腿上留下旧伤",
        }
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Prologue {
    pub age: u8,
    pub family: Family,
    pub education: Education,
    pub youth: Youth,
    pub temperament: Temperament,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
pub enum Language {
    French,
    English,
    German,
    Russian,
    WrittenChinese,
    Japanese,
}

impl Language {
    pub fn label(self) -> &'static str {
        match self {
            Self::French => "法语",
            Self::English => "英语",
            Self::German => "德语",
            Self::Russian => "俄语",
            Self::WrittenChinese => "汉文",
            Self::Japanese => "日语",
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Biography {
    pub source: String,
    pub label: String,
    pub start_year: u16,
    pub end_year: u16,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ServiceRecord {
    pub start_day: i64,
    pub end_day: i64,
    pub unit_or_organization: String,
    pub role: String,
    pub end_reason: String,
    pub source_event_id: String,
}

impl ServiceRecord {
    fn valid(&self, birth_year: u16, day: u32) -> bool {
        self.start_day >= year_start(birth_year + 18)
            && self.start_day < self.end_day
            && self.end_day <= i64::from(day)
            && [
                &self.unit_or_organization,
                &self.role,
                &self.end_reason,
                &self.source_event_id,
            ]
            .iter()
            .all(|value| valid_text(value))
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum OpeningHealth {
    Strong,
    OldInjury,
    ProlongedIllness,
}

impl OpeningHealth {
    fn event(self) -> Temperament {
        match self {
            Self::Strong => Temperament::Endure,
            Self::OldInjury => Temperament::Recover,
            Self::ProlongedIllness => Temperament::Illness,
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct PlayerDevelopment {
    opening: Prologue,
    birth_year: u16,
    language: Option<Language>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    opening_health: Option<OpeningHealth>,
    attributes: [u16; 8],
    traits: BTreeMap<String, String>,
    history: Vec<Biography>,
    service: Vec<ServiceRecord>,
    reading: BTreeMap<Language, u16>,
    sources: BTreeSet<String>,
}

#[derive(Clone, Copy)]
pub enum Check<'a> {
    Deception,
    Risk,
    UrgentExecution,
    SkippedUrgentReview,
    Persuasion,
    CommercialNegotiation,
    Coordination,
    Plan,
    MilitaryPlan { role: &'a str },
    ResistInterruption,
}

impl Prologue {
    pub fn build(self, language: Language) -> Result<PlayerDevelopment> {
        self.build_for_language(Some(language))
    }

    pub fn build_for_language(self, language: Option<Language>) -> Result<PlayerDevelopment> {
        self.build_with_health(language, None)
    }

    pub fn build_with_health(
        self,
        language: Option<Language>,
        health: Option<OpeningHealth>,
    ) -> Result<PlayerDevelopment> {
        require(
            health.is_none()
                || !matches!(
                    self.temperament,
                    Temperament::Endure | Temperament::Recover | Temperament::Illness
                ),
            "opening health already established through a legacy event",
        )?;
        require(
            self.temperament != Temperament::Rescue || health == Some(OpeningHealth::OldInjury),
            "the rescue episode requires the recorded injury",
        )?;
        require(matches!(self.age, 18 | 20 | 25), "unsupported opening age")?;
        require(
            self.youth.eligible(self.age, self.education),
            "ineligible youth experience",
        )?;
        let birth_year = EPOCH_YEAR - u16::from(self.age);
        let mut result = PlayerDevelopment {
            opening: self,
            birth_year,
            language,
            opening_health: health,
            attributes: std::array::from_fn(|index| CATALOG.attributes[index].baseline),
            traits: BTreeMap::new(),
            history: Vec::new(),
            service: Vec::new(),
            reading: BTreeMap::new(),
            sources: BTreeSet::new(),
        };
        result.biography("origin", self.family.label(), birth_year, birth_year + 7);
        let schooling = if self.education == Education::ReadingLessons {
            self.family.childhood_schooling()
        } else {
            self.education.label()
        };
        result.biography("school", schooling, birth_year + 7, birth_year + 14);
        if self.education == Education::ReadingLessons {
            let language = language
                .ok_or_else(|| Error("no supported reading language at the opening".into()))?;
            result.reading.insert(language, SCALE);
            result.grant("literacy", "prologue:school")?;
            let teaching = match self.family {
                Family::Poor => 25,
                Family::Ordinary => 45,
                Family::Wealthy => 65,
            };
            result.grow(0, teaching);
        } else {
            result.grow(6, 25);
        }
        let (youth_start, youth_end) = match self.youth {
            Youth::Labor => (birth_year + 15, EPOCH_YEAR),
            Youth::Apprentice => (birth_year + 15, birth_year + 18),
            Youth::CommercialAssistant | Youth::AdvancedStudy => {
                (birth_year + 18, EPOCH_YEAR.min(birth_year + 22))
            }
        };
        result.biography("youth", self.youth.label(), youth_start, youth_end);
        match self.youth {
            Youth::Labor => result.grow(7, 40),
            Youth::Apprentice => {
                result.grant("apprentice", "prologue:youth")?;
                result.grow(1, 30);
            }
            Youth::CommercialAssistant => {
                result.grow(2, 55);
                result.grow(3, 40);
            }
            Youth::AdvancedStudy => {
                result.grow(0, 55);
                result.grow(4, 25);
            }
        }
        result.biography(
            "temperament",
            self.temperament.label(),
            birth_year + 16,
            birth_year + 17,
        );
        result.apply_opening_event(self.temperament, "prologue:temperament")?;
        if let Some(health) = health {
            let event = health.event();
            result.biography("health", event.label(), birth_year + 17, birth_year + 18);
            result.apply_opening_event(event, "prologue:health")?;
        }
        Ok(result)
    }
}

impl PlayerDevelopment {
    fn apply_opening_event(&mut self, event: Temperament, source: &str) -> Result<()> {
        let traits: &[&str] = match event {
            Temperament::Practice => &["curious", "focused", "quick_study"],
            Temperament::Persist => &["hardworking", "focused"],
            Temperament::Endure => &["robust", "resilient"],
            Temperament::Recover => &["old_injury", "resilient"],
            Temperament::Struggle => &["slow_study", "hardworking"],
            Temperament::Leave => &["careless_work"],
            Temperament::Illness => &["frail", "slow_healing", "chronic_illness"],
            Temperament::Rescue => &[],
        };
        for id in traits {
            self.grant(id, source)?;
        }
        match event {
            Temperament::Practice => {
                self.grow(0, 45);
                self.grow(3, 25);
            }
            Temperament::Persist => {
                self.grow(5, 40);
                self.grow(6, 45);
            }
            Temperament::Endure => {
                self.grow(7, 60);
                self.grow(6, 25);
            }
            Temperament::Recover => {
                self.grow(1, 35);
                self.grow(6, 25);
            }
            Temperament::Struggle => self.grow(6, 40),
            Temperament::Leave => self.grow(2, 20),
            Temperament::Illness => {
                self.attributes[7] = 455;
                self.grow(6, 25);
            }
            Temperament::Rescue => (),
        }
        Ok(())
    }

    pub fn opening(&self) -> Prologue {
        self.opening
    }
    pub fn birth_year(&self) -> u16 {
        self.birth_year
    }
    pub(crate) fn birth_day(&self) -> i64 {
        year_start(self.birth_year)
    }
    pub fn language(&self) -> Option<Language> {
        self.language
    }
    pub fn can_read(&self, language: Language) -> bool {
        self.reading.get(&language) == Some(&SCALE)
    }
    pub fn trait_labels(&self) -> impl Iterator<Item = &'static str> + '_ {
        self.traits
            .keys()
            .filter_map(|id| trait_rule(id).map(|rule| rule.label_zh.as_str()))
    }
    pub fn history(&self) -> &[Biography] {
        &self.history
    }
    pub fn opening_injury(&self) -> u16 {
        (-self.effect("health.creation_ceiling", "add_scale")) as u16
    }

    fn biography(&mut self, source: &str, label: &str, start_year: u16, end_year: u16) {
        let source = format!("prologue:{source}");
        self.sources.insert(source.clone());
        self.history.push(Biography {
            source,
            label: label.into(),
            start_year,
            end_year,
        });
    }

    fn grant(&mut self, id: &str, source: &str) -> Result<()> {
        let rule = trait_rule(id).ok_or_else(|| Error("unknown trait".into()))?;
        require(self.sources.contains(source), "unrecorded trait source")?;
        if self.traits.contains_key(id) {
            return Ok(());
        }
        require(
            rule.exclusive_group.as_ref().is_none_or(|group| {
                self.traits
                    .keys()
                    .all(|other| trait_rule(other).unwrap().exclusive_group.as_ref() != Some(group))
            }),
            "conflicting player traits",
        )?;
        self.traits.insert(id.into(), source.into());
        Ok(())
    }

    pub(crate) fn validate(&self, birth_day: i64, day: u32) -> Result<()> {
        let opening = self
            .opening
            .build_with_health(self.language, self.opening_health)?;
        require(
            self.birth_year == opening.birth_year
                && birth_day == opening.birth_day()
                && self.history == opening.history
                && self.attributes.iter().all(|&value| value <= SCALE)
                && opening
                    .traits
                    .iter()
                    .all(|(id, source)| self.traits.get(id) == Some(source))
                && opening.sources.is_subset(&self.sources)
                && self.reading.values().all(|&value| value <= SCALE)
                && opening
                    .reading
                    .iter()
                    .all(|(language, value)| self.reading.get(language) >= Some(value))
                && self.sources.iter().all(|source| valid_text(source)),
            "invalid player development",
        )?;
        require(
            self.traits.iter().all(|(id, source)| {
                trait_rule(id).is_some_and(|rule| {
                    i64::from(day) >= year_start(self.birth_year + u16::from(rule.min_age))
                }) && self.sources.contains(source)
                    && (opening.traits.contains_key(id)
                        || matches!(id.as_str(), "literacy" | "veteran"))
            }),
            "invalid player trait or source",
        )?;
        let mut service_sources = BTreeSet::new();
        require(
            self.service.iter().enumerate().all(|(index, entry)| {
                entry.valid(self.birth_year, day)
                    && entry.end_day
                        >= year_start(
                            self.birth_year + u16::from(trait_rule("veteran").unwrap().min_age),
                        )
                    && self.sources.contains(&entry.source_event_id)
                    && service_sources.insert(&entry.source_event_id)
                    && self.service[..index].iter().all(|past| {
                        entry.start_day >= past.end_day || entry.end_day <= past.start_day
                    })
            }) && self.traits.get("veteran")
                == self.service.first().map(|entry| &entry.source_event_id)
                && self.traits.contains_key("literacy")
                    == self.reading.values().any(|&value| value == SCALE),
            "invalid service or reading provenance",
        )
    }

    pub(crate) fn record_service(&mut self, entry: ServiceRecord, day: u32) -> Result<()> {
        require(
            entry.valid(self.birth_year, day)
                && entry.end_day
                    >= year_start(
                        self.birth_year + u16::from(trait_rule("veteran").unwrap().min_age),
                    )
                && self
                    .service
                    .iter()
                    .all(|past| entry.start_day >= past.end_day || entry.end_day <= past.start_day),
            "invalid service term",
        )?;
        self.record_source(&entry.source_event_id)?;
        self.grant("veteran", &entry.source_event_id)?;
        self.service.push(entry);
        Ok(())
    }

    fn modifiers<'a>(
        &'a self,
        trigger: &'a str,
        operation: &'a str,
    ) -> impl Iterator<Item = i32> + 'a {
        self.traits
            .keys()
            .flat_map(|id| &trait_rule(id).unwrap().effects)
            .filter(move |effect| effect.trigger == trigger && effect.operation == operation)
            .map(|effect| effect.value)
    }

    fn effect(&self, trigger: &str, operation: &str) -> i32 {
        self.modifiers(trigger, operation).sum()
    }

    fn rate(&self, trigger: &str) -> f64 {
        self.modifiers(trigger, "mul_bps")
            .fold(1.0, |rate, value| rate * f64::from(value) / 10_000.0)
    }

    fn attribute_delta(&self, index: usize, relative: bool) -> f64 {
        let rule = &CATALOG.attributes[index];
        debug_assert!(!rule.id.is_empty());
        let steps = (f64::from(self.attributes[index]) - f64::from(rule.baseline)) / 100.0;
        let rate = f64::from(rule.modifier.value);
        if relative {
            (1.0 + rate / 10_000.0).powf(steps)
        } else {
            steps * rate * 10.0
        }
    }

    pub fn chance_bps(&self, check: Check<'_>, base: u16) -> u16 {
        let (attribute, trigger) = match check {
            Check::Deception => (Some(1), "information.fraud_detect"),
            Check::Risk => (Some(1), "decision.risk_detect"),
            Check::UrgentExecution => (Some(2), "decision.deadline"),
            Check::SkippedUrgentReview => (None, "decision.skipped_review_error_risk"),
            Check::Persuasion => (Some(3), "social.persuasion"),
            Check::CommercialNegotiation => (Some(3), "commerce.negotiation"),
            Check::Coordination => (Some(5), "organization.coordination"),
            Check::Plan => (Some(2), "plan.resolution"),
            Check::MilitaryPlan { role }
                if self.service.iter().any(|record| record.role == role) =>
            {
                (Some(2), "plan.military_relevant")
            }
            Check::MilitaryPlan { .. } => (Some(2), "plan.resolution"),
            Check::ResistInterruption => (Some(6), "stress.interruption"),
        };
        (f64::from(base)
            + attribute.map_or(0.0, |i| self.attribute_delta(i, false))
            + f64::from(self.effect(trigger, "add_pp_tenths")) * 10.0)
            .round()
            .clamp(0.0, 10_000.0) as u16
    }

    pub fn review_units(&self, base: u32) -> u32 {
        let factor = self
            .modifiers("decision.review_time", "mul_bps_ceil")
            .next()
            .unwrap_or(10_000);
        (u64::from(base) * factor as u64)
            .div_ceil(10_000)
            .min(u64::from(u32::MAX)) as u32
    }

    pub fn trust_growth(&self, growth: i32, first_contact: bool, reliable: bool) -> i32 {
        if growth <= 0 {
            return growth;
        }
        let context = if first_contact || !reliable {
            self.rate("relation.new_contact_trust_gain")
        } else {
            1.0
        };
        (f64::from(growth) * self.attribute_delta(4, true) * self.rate("relation.gain") * context)
            .round() as i32
    }

    pub(crate) fn study_rate(&self) -> f64 {
        self.attribute_delta(0, true) * self.rate("learning.any") * self.rate("learning.study")
    }

    pub(crate) fn work_rate(&self, matches_apprenticeship: bool) -> f64 {
        let trigger = "learning.work";
        self.traits
            .keys()
            .filter(|id| id.as_str() != "apprentice" || matches_apprenticeship)
            .flat_map(|id| &trait_rule(id).unwrap().effects)
            .filter(|effect| effect.trigger == trigger && effect.operation == "mul_bps")
            .fold(
                self.attribute_delta(0, true) * self.rate("learning.any"),
                |rate, effect| rate * f64::from(effect.value) / 10_000.0,
            )
    }

    pub(crate) fn initial_fatigue(&self) -> u16 {
        match self.opening.temperament {
            Temperament::Recover => 30,
            Temperament::Illness => 80,
            _ => 0,
        }
    }
    pub(crate) fn injury_rate(&self) -> f64 {
        self.attribute_delta(7, true) * self.rate("injury.permanent_loss")
    }
    pub(crate) fn recovery_rate(&self) -> f64 {
        self.rate("health.daily_recovery")
    }

    pub(crate) fn record_source(&mut self, source: &str) -> Result<()> {
        require(
            valid_text(source)
                && !source.starts_with("prologue:")
                && self.sources.insert(source.into()),
            "invalid or repeated player event source",
        )
    }

    pub(crate) fn grow(&mut self, attribute: usize, amount: u16) {
        self.attributes[attribute] = self.attributes[attribute].saturating_add(amount).min(SCALE);
    }

    pub(crate) fn reading_lesson(
        &mut self,
        language: Language,
        effort: u16,
        source: &str,
    ) -> Result<()> {
        self.record_source(source)?;
        let gain = (f64::from(effort) * self.study_rate()).round() as u16;
        let progress = self.reading.entry(language).or_default();
        *progress = progress.saturating_add(gain).min(SCALE);
        if *progress == SCALE {
            self.grant("literacy", source)?;
        }
        self.grow(0, 2);
        Ok(())
    }
}

fn year_start(year: u16) -> i64 {
    let days_in = |year: u16| {
        if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) {
            366
        } else {
            365
        }
    };
    if year >= EPOCH_YEAR {
        (EPOCH_YEAR..year).map(days_in).sum()
    } else {
        -(year..EPOCH_YEAR).map(days_in).sum::<i64>()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn adult() -> PlayerDevelopment {
        let mut player = Prologue {
            age: 25,
            family: Family::Ordinary,
            education: Education::HomeWork,
            youth: Youth::Labor,
            temperament: Temperament::Persist,
        }
        .build(Language::French)
        .unwrap();
        player.attributes = [500; 8];
        player
    }

    #[test]
    fn applies_percentage_points_and_contextual_costs() {
        let mut player = adult();
        player.record_source("event:test").unwrap();
        for id in ["suspicious", "prudent", "decisive"] {
            player.grant(id, "event:test").unwrap();
        }
        let count = player.traits.len();
        player.grant("suspicious", "event:test").unwrap();
        assert_eq!(player.traits.len(), count);
        assert_eq!(player.chance_bps(Check::Deception, 4000), 4500);
        assert_eq!(player.chance_bps(Check::Risk, 9900), 10_000);
        assert_eq!(player.chance_bps(Check::UrgentExecution, 4000), 4500);
        assert_eq!(player.chance_bps(Check::SkippedUrgentReview, 4000), 4400);
        assert_eq!(player.chance_bps(Check::Coordination, 4000), 4000);
        assert_eq!(player.review_units(1), 2);
        assert_eq!(player.review_units(5), 6);
        assert_eq!(player.trust_growth(50, true, true), 40);
        assert_eq!(player.trust_growth(50, false, false), 40);
        assert_eq!(player.trust_growth(50, false, true), 50);
        assert_eq!(player.trust_growth(-50, true, false), -50);
    }

    #[test]
    fn verifies_service_term_and_scope() {
        let mut player = adult();
        let term = ServiceRecord {
            start_day: year_start(1894),
            end_day: year_start(1898),
            unit_or_organization: "Test unit".into(),
            role: "supply".into(),
            end_reason: "Term ended".into(),
            source_event_id: "event:service".into(),
        };
        assert!(
            player
                .record_service(
                    ServiceRecord {
                        start_day: year_start(1893) - 1,
                        ..term.clone()
                    },
                    0
                )
                .is_err()
        );
        player.record_service(term.clone(), 0).unwrap();
        assert!(player.record_service(term, 0).is_err());
        assert_eq!(
            player.chance_bps(Check::MilitaryPlan { role: "supply" }, 4000),
            4400
        );
        assert_eq!(
            player.chance_bps(Check::MilitaryPlan { role: "command" }, 4000),
            4000
        );
        assert_eq!(player.opening_injury(), 0);
        player.validate(player.birth_day(), 0).unwrap();
    }

    #[test]
    fn apprentice_grows_faster_only_at_matching_work() {
        let player = Prologue {
            age: 18,
            family: Family::Ordinary,
            education: Education::HomeWork,
            youth: Youth::Apprentice,
            temperament: Temperament::Persist,
        }
        .build(Language::French)
        .unwrap();
        assert!((player.work_rate(true) / player.work_rate(false) - 1.10).abs() < 1e-10);
    }

    #[test]
    fn rejects_a_repeated_lesson_before_growing() {
        let mut player = adult();
        player
            .reading_lesson(Language::French, 500, "study:first")
            .unwrap();
        let after = player.clone();
        assert!(
            player
                .reading_lesson(Language::French, 500, "study:first")
                .is_err()
        );
        assert_eq!(player, after);
        assert!(!player.can_read(Language::English));
    }
}
