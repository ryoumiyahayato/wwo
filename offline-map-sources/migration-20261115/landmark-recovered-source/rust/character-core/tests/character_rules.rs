use std::cell::Cell;
use std::collections::BTreeMap;
use wwo_character_core::*;

struct Host {
    funds: u64,
    permission: ConditionStatus,
    missing_day: Option<u32>,
    known: bool,
    reads: Cell<usize>,
}
impl Default for Host {
    fn default() -> Self {
        Self {
            funds: 10_000,
            permission: ConditionStatus::Met,
            missing_day: None,
            known: true,
            reads: Cell::new(0),
        }
    }
}
impl CharacterHost for Host {
    fn person_exists(&self, _: &str) -> bool {
        self.known
    }
    fn living_conditions(&self, _: &str, day: u32) -> Option<LivingConditions> {
        self.reads.set(self.reads.get() + 1);
        if self.missing_day == Some(day) {
            None
        } else {
            Some(LivingConditions {
                nutrition: 1000,
                medical_care: 1000,
                safety: 1000,
                rest: 1000,
            })
        }
    }
}
impl OpportunityHost for Host {
    fn condition(&self, _: &str, _: &str, requirement: &Requirement, _: u32) -> ConditionEvidence {
        let (status, explanation) = match requirement {
            Requirement::Funds { minor_units, .. } if self.funds < *minor_units => {
                (ConditionStatus::Missing, "资金不足，无法取得设备")
            }
            Requirement::Permission { .. } => (
                self.permission,
                if self.permission == ConditionStatus::Met {
                    "已获经营许可"
                } else {
                    "经营许可尚未取得或无法确认"
                },
            ),
            _ => (ConditionStatus::Met, "已有相关资源"),
        };
        ConditionEvidence {
            status,
            explanation: explanation.into(),
            source: "test host authoritative observation".into(),
        }
    }
}
fn rules() -> LifeRules {
    // Deterministic test fixture; do not change production defaults to force survival.
    LifeRules {
        mortality: vec![
            MortalityBand {
                from_age_years: 0,
                daily_risk_per_million: 0,
            },
            MortalityBand {
                from_age_years: 125,
                daily_risk_per_million: 1_000_000,
            },
        ],
        ..LifeRules::default()
    }
}
fn seed(id: &str, age: u32, knowledge: u16, practice: u16) -> PersonSeed {
    PersonSeed {
        id: format!("person:{id}"),
        name: id.into(),
        birth_day: -i64::from(age * DAYS_PER_YEAR),
        constitution: 500,
        capabilities: BTreeMap::from([(
            "management".into(),
            Capability {
                knowledge,
                practice,
                learning: 500,
            },
        )]),
        basis: "test fixture".into(),
    }
}
fn system() -> CharacterSystem {
    let mut s = CharacterSystem::new("test-world".into(), 0, 42, rules()).unwrap();
    s.register(seed("p", 32, 800, 800), &Host::default())
        .unwrap();
    s
}
fn action() -> ActionSpec {
    ActionSpec {
        id: "open-workshop".into(),
        domain: "management".into(),
        requirements: vec![
            Requirement::Funds {
                currency: "FRF".into(),
                minor_units: 5000,
            },
            Requirement::Permission {
                permission: "operate-workshop".into(),
            },
        ],
        knowledge_weight: 500,
        difficulty: 500,
        physical_demand: 1000,
    }
}

#[test]
fn high_ability_cannot_replace_money_or_permission() {
    let s = system();
    let poor = Host {
        funds: 0,
        ..Host::default()
    };
    let blocked = s.assess_action("person:p", &action(), &poor).unwrap();
    assert!(!blocked.ready);
    assert_eq!(blocked.performance, None);
    assert!(blocked.explanation.iter().any(|v| v.contains("资金不足")));
    assert!(
        s.assess_action("person:p", &action(), &Host::default())
            .unwrap()
            .ready
    );
    let no_permit = Host {
        permission: ConditionStatus::Missing,
        ..Host::default()
    };
    assert!(
        !s.assess_action("person:p", &action(), &no_permit)
            .unwrap()
            .ready
    );
    assert_eq!(poor.funds, 0); // assessment never creates/reserves money
}

#[test]
fn unknown_conditions_block_and_family_text_does_not_grant_resources() {
    let s = system();
    let host = Host {
        permission: ConditionStatus::Unknown,
        ..Host::default()
    };
    let before = s.snapshot();
    let _ = s
        .view(
            "person:p",
            SocialFacts {
                family_background: Some("富裕商人家庭".into()),
                ..SocialFacts::default()
            },
        )
        .unwrap();
    assert!(!s.assess_action("person:p", &action(), &host).unwrap().ready);
    assert_eq!(s.snapshot(), before);
}

#[test]
fn knowledge_and_practice_have_contextual_advantages() {
    let host = Host::default();
    let mut s = system();
    s.register(seed("scholar", 30, 950, 100), &host).unwrap();
    s.register(seed("worker", 50, 100, 950), &host).unwrap();
    let mut spec = action();
    spec.knowledge_weight = 1000;
    assert_eq!(
        s.assess_action("person:scholar", &spec, &host)
            .unwrap()
            .performance,
        Some(Performance::Proficient)
    );
    assert_eq!(
        s.assess_action("person:worker", &spec, &host)
            .unwrap()
            .performance,
        Some(Performance::Difficult)
    );
    spec.knowledge_weight = 0;
    assert_eq!(
        s.assess_action("person:worker", &spec, &host)
            .unwrap()
            .performance,
        Some(Performance::Proficient)
    );
    assert_eq!(
        s.assess_action("person:scholar", &spec, &host)
            .unwrap()
            .performance,
        Some(Performance::Difficult)
    );
}

#[test]
fn public_view_hides_backend_scores_and_preserves_unknown_facts() {
    let s = system();
    let view = s.view("person:p", SocialFacts::default()).unwrap();
    assert_eq!(view.social.family_background, None);
    assert_eq!(view.social.assets, None);
    assert_eq!(view.social.relationships, None);
    assert_eq!(view.social.positions, None);
    let json = serde_json::to_string(&view).unwrap();
    for hidden in [
        "constitution",
        "knowledge",
        "practice",
        "learning",
        "recovery_ceiling",
        "permanent_loss",
        "efficiency_delta",
        "mortality",
        "seed",
    ] {
        assert!(!json.contains(hidden), "leaked {hidden}");
    }
    assert!(json.contains("良好"));
}

#[test]
fn injury_limits_recovery_and_performance_without_erasing_knowledge() {
    let mut s = system();
    let host = Host::default();
    s.apply_event(
        "person:p",
        1,
        LifeEvent::Injury {
            label: "左腿旧伤".into(),
            damage: 650,
            permanent_loss: 300,
        },
    )
    .unwrap();
    assert_eq!(
        s.assess_action("person:p", &action(), &host)
            .unwrap()
            .performance,
        Some(Performance::Difficult)
    );
    s.advance_to(100, &host).unwrap();
    let p = &s.snapshot().people[0];
    assert_eq!(p.health.current, 700);
    assert_eq!(p.health.recovery_ceiling, 700);
    assert_eq!(p.identity.capabilities["management"].knowledge, 800);
    assert!(s
        .view("person:p", SocialFacts::default())
        .unwrap()
        .traits
        .contains(&"左腿旧伤".into()));
}

#[test]
fn child_does_not_age_like_an_older_adult() {
    let mut s = system();
    let host = Host::default();
    s.register(seed("child", 5, 0, 0), &host).unwrap();
    s.register(seed("older", 70, 800, 800), &host).unwrap();
    let before = s.snapshot();
    s.advance_to(365, &host).unwrap();
    let after = s.snapshot();
    assert_eq!(
        after
            .people
            .iter()
            .find(|p| p.identity.id == "person:child")
            .unwrap()
            .health
            .recovery_ceiling,
        1000
    );
    let old_before = before
        .people
        .iter()
        .find(|p| p.identity.id == "person:older")
        .unwrap();
    let old_after = after
        .people
        .iter()
        .find(|p| p.identity.id == "person:older")
        .unwrap();
    assert_eq!(
        old_before.health.recovery_ceiling - old_after.health.recovery_ceiling,
        6
    );
}

#[test]
fn natural_death_does_not_require_zero_health_and_is_not_repeated() {
    let host = Host::default();
    let mut s = system();
    s.register(seed("old", 125, 900, 900), &host).unwrap();
    let deaths = s.advance_to(1, &host).unwrap();
    assert_eq!(deaths.len(), 1);
    assert_eq!(deaths[0].person_id, "person:old");
    assert!(
        s.snapshot()
            .people
            .iter()
            .find(|p| p.identity.id == "person:old")
            .unwrap()
            .health
            .current
            > 0
    );
    assert!(s.advance_to(10, &host).unwrap().is_empty());
    assert!(
        !s.assess_action("person:old", &action(), &host)
            .unwrap()
            .ready
    );
    assert!(s
        .apply_event(
            "person:old",
            1,
            LifeEvent::Learning {
                domain: "management".into(),
                study: 100,
                practice: 100,
                label: "培训".into()
            }
        )
        .is_err());
    let restored =
        CharacterSystem::from_json(&s.to_json().unwrap(), "test-world", 10, &host).unwrap();
    assert_eq!(s, restored);
}

#[test]
fn explicit_accident_death_and_fatal_injury_return_notifications() {
    let mut s = system();
    let death = s
        .apply_event(
            "person:p",
            1,
            LifeEvent::Death {
                cause: "事故".into(),
            },
        )
        .unwrap()
        .unwrap();
    assert_eq!(death.death.cause, "事故");
    let mut other = system();
    let death = other
        .apply_event(
            "person:p",
            1,
            LifeEvent::Injury {
                label: "重伤".into(),
                damage: 1000,
                permanent_loss: 0,
            },
        )
        .unwrap();
    assert!(death.is_some());
}

#[test]
fn illness_expiration_recovery_and_environment_affect_health() {
    let mut s = system();
    let host = Host::default();
    s.apply_event(
        "person:p",
        1,
        LifeEvent::Disease {
            label: "感染".into(),
            severity: 1000,
            duration_days: 3,
        },
    )
    .unwrap();
    s.advance_to(2, &host).unwrap();
    assert!(s.snapshot().people[0].health.current < 1000);
    assert_eq!(
        s.view("person:p", SocialFacts::default())
            .unwrap()
            .health_status,
        "患病"
    );
    s.advance_to(3, &host).unwrap();
    assert!(s.snapshot().people[0].health.disease.is_none());
    s.advance_to(20, &host).unwrap();
    assert_eq!(s.snapshot().people[0].health.current, 1000);
}

#[test]
fn failed_time_advance_is_atomic_and_same_day_does_no_work() {
    let mut s = system();
    let before = s.clone();
    let host = Host {
        missing_day: Some(3),
        ..Host::default()
    };
    assert!(s.advance_to(5, &host).is_err());
    assert_eq!(s, before);
    host.reads.set(0);
    assert!(s.advance_to(0, &host).unwrap().is_empty());
    assert_eq!(host.reads.get(), 0);
    assert!(s.advance_to(MAX_ADVANCE_DAYS + 1, &host).is_err());
    assert_eq!(s, before);
    s.advance_to(1, &host).unwrap();
    assert!(s.advance_to(0, &host).is_err());
}

#[test]
fn saved_replay_batching_and_registration_order_are_identical() {
    let host = Host::default();
    let mut a = CharacterSystem::new("test-world".into(), 0, 934, LifeRules::default()).unwrap();
    let mut b = a.clone();
    for id in ["a", "b"] {
        a.register(seed(id, 90, 700, 400), &host).unwrap();
    }
    for id in ["b", "a"] {
        b.register(seed(id, 90, 700, 400), &host).unwrap();
    }
    let a_deaths = a.advance_to(365, &host).unwrap();
    let mut b_deaths = b.advance_to(100, &host).unwrap();
    b = CharacterSystem::from_json(&b.to_json().unwrap(), "test-world", 100, &host).unwrap();
    for day in 101..=365 {
        b_deaths.extend(b.advance_to(day, &host).unwrap());
    }
    assert_eq!(a_deaths, b_deaths);
    assert_eq!(a, b);
}

#[test]
fn learning_is_bounded_and_sequence_rejects_duplicate_or_skipped_events() {
    let mut s = system();
    let event = LifeEvent::Learning {
        domain: "management".into(),
        study: 300,
        practice: 200,
        label: "工厂培训".into(),
    };
    s.apply_event("person:p", 1, event.clone()).unwrap();
    let before = s.clone();
    assert!(s.apply_event("person:p", 1, event.clone()).is_err());
    assert!(s.apply_event("person:p", 3, event.clone()).is_err());
    assert_eq!(s, before);
    for seq in 2..=100 {
        s.apply_event("person:p", seq, event.clone()).unwrap();
    }
    let p = &s.snapshot().people[0];
    assert_eq!(p.identity.capabilities["management"].knowledge, SCALE);
    assert_eq!(p.experiences.len(), 1);
}

#[test]
fn mixed_experience_changes_knowledge_and_efficiency_and_expires_without_replay() {
    let mut s = system();
    let host = Host::default();
    let event = LifeEvent::Experience {
        experience: Experience {
            id: "failed-investment:1".into(),
            label: "投资失败后更加谨慎，但精神疲惫".into(),
            domain: "management".into(),
            efficiency_delta: -500,
            expires_day: Some(5),
        },
        knowledge_delta: 100,
        practice_delta: -100,
    };
    s.apply_event("person:p", 1, event.clone()).unwrap();
    assert_eq!(
        s.assess_action("person:p", &action(), &host)
            .unwrap()
            .performance,
        Some(Performance::Difficult)
    );
    s.advance_to(5, &host).unwrap();
    assert_eq!(
        s.assess_action("person:p", &action(), &host)
            .unwrap()
            .performance,
        Some(Performance::Proficient)
    );
    let view = s.view("person:p", SocialFacts::default()).unwrap();
    assert!(view.traits.is_empty());
    assert_eq!(view.history.len(), 1);
    // Even with a new event sequence, the same experience source is not rewarded twice.
    let mut retry = match event {
        LifeEvent::Experience { experience, .. } => experience,
        _ => unreachable!(),
    };
    retry.expires_day = Some(10);
    assert!(s
        .apply_event(
            "person:p",
            2,
            LifeEvent::Experience {
                experience: retry,
                knowledge_delta: 100,
                practice_delta: 0
            }
        )
        .is_err());
    assert_eq!(
        s.snapshot().people[0].identity.capabilities["management"].knowledge,
        900
    );
}

#[test]
fn restore_rejects_invalid_health_identity_time_rules_and_schema() {
    let s = system();
    let host = Host::default();
    let valid = s.snapshot();
    let mut invalid = Vec::new();
    let mut v = valid.clone();
    v.schema = "future-version".into();
    invalid.push(v);
    let mut v = valid.clone();
    v.people[0].health.current = 1001;
    invalid.push(v);
    let mut v = valid.clone();
    v.people[0].health.recovery_ceiling = 900;
    v.people[0].health.current = 900;
    invalid.push(v);
    let mut v = valid.clone();
    v.people.push(v.people[0].clone());
    invalid.push(v);
    let mut v = valid.clone();
    v.rules.mortality.clear();
    invalid.push(v);
    let mut v = valid.clone();
    v.people[0]
        .identity
        .capabilities
        .get_mut("management")
        .unwrap()
        .learning = 1001;
    invalid.push(v);
    for snapshot in invalid {
        assert!(CharacterSystem::from_snapshot(snapshot, "test-world", 0, &host).is_err());
    }
    assert!(CharacterSystem::from_snapshot(valid.clone(), "another-world", 0, &host).is_err());
    assert!(CharacterSystem::from_snapshot(valid.clone(), "test-world", 1, &host).is_err());
    assert!(CharacterSystem::from_snapshot(
        valid,
        "test-world",
        0,
        &Host {
            known: false,
            ..Host::default()
        }
    )
    .is_err());
    assert!(CharacterSystem::from_json(b"{broken", "test-world", 0, &host).is_err());
    let mut json: serde_json::Value = serde_json::from_slice(&s.to_json().unwrap()).unwrap();
    json["unrecognized"] = true.into();
    assert!(CharacterSystem::from_json(
        &serde_json::to_vec(&json).unwrap(),
        "test-world",
        0,
        &host
    )
    .is_err());
}

#[test]
fn unknown_people_and_invalid_events_do_not_mutate_state() {
    let mut s = system();
    let before = s.clone();
    assert!(s
        .register(
            seed("outsider", 30, 500, 500),
            &Host {
                known: false,
                ..Host::default()
            }
        )
        .is_err());
    assert!(s
        .register(seed("p", 30, 500, 500), &Host::default())
        .is_err());
    assert!(s
        .apply_event(
            "person:p",
            1,
            LifeEvent::Injury {
                label: "".into(),
                damage: 100,
                permanent_loss: 100
            }
        )
        .is_err());
    assert!(s
        .apply_event(
            "person:missing",
            1,
            LifeEvent::Death {
                cause: "事故".into()
            }
        )
        .is_err());
    assert_eq!(s, before);
}
