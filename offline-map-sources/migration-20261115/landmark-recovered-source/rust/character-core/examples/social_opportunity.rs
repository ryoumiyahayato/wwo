//! Fictional fixture showing integration boundaries, not a running WWO world.
use std::collections::BTreeMap;
use wwo_character_core::*;

struct DemoWorld {
    available_cash: BTreeMap<String, u64>,
}
impl CharacterHost for DemoWorld {
    fn person_exists(&self, id: &str) -> bool {
        self.available_cash.contains_key(id)
    }
    fn living_conditions(&self, _: &str, _: u32) -> Option<LivingConditions> {
        Some(LivingConditions {
            nutrition: 800,
            medical_care: 400,
            safety: 900,
            rest: 750,
        })
    }
}
impl OpportunityHost for DemoWorld {
    fn condition(
        &self,
        person: &str,
        _: &str,
        requirement: &Requirement,
        _: u32,
    ) -> ConditionEvidence {
        let (status, explanation) = match requirement {
            Requirement::Funds {
                currency,
                minor_units,
            } if currency == "FRF" => {
                if self.available_cash.get(person).copied().unwrap_or(0) >= *minor_units {
                    (ConditionStatus::Met, "可用资金足以支付所需设备")
                } else {
                    (ConditionStatus::Missing, "积蓄不足，尚不能支付所需设备")
                }
            }
            Requirement::Introduction { .. } if person == "person:merchant_child" => {
                (ConditionStatus::Met, "家庭联系人已经提供引荐")
            }
            Requirement::Introduction { .. } => (ConditionStatus::Missing, "尚无担保人引荐"),
            _ => (ConditionStatus::Unknown, "现有资料无法确认这个条件"),
        };
        ConditionEvidence {
            status,
            explanation: explanation.into(),
            source: "fictional demo host; not historical evidence".into(),
        }
    }
}

fn main() -> std::result::Result<(), Box<dyn std::error::Error>> {
    let host = DemoWorld {
        available_cash: BTreeMap::from([
            ("person:worker_child".into(), 500),
            ("person:merchant_child".into(), 20_000),
        ]),
    };
    let mut people = CharacterSystem::new("fictional-demo".into(), 0, 1900, LifeRules::default())?;
    for (id, name) in [
        ("person:worker_child", "皮埃尔"),
        ("person:merchant_child", "保罗"),
    ] {
        people.register(
            PersonSeed {
                id: id.into(),
                name: name.into(),
                birth_day: -32 * 365,
                constitution: 750,
                capabilities: BTreeMap::from([(
                    "factory_management".into(),
                    Capability {
                        knowledge: 650,
                        practice: 800,
                        learning: 600,
                    },
                )]),
                basis: "虚构示例：相同能力，不同实际资源".into(),
            },
            &host,
        )?;
        people.apply_event(
            id,
            1,
            LifeEvent::Learning {
                domain: "factory_management".into(),
                study: 0,
                practice: 0,
                label: "熟悉工厂管理".into(),
            },
        )?;
    }
    let task = ActionSpec {
        id: "equipment_purchase_application".into(),
        domain: "factory_management".into(),
        requirements: vec![
            Requirement::Funds {
                currency: "FRF".into(),
                minor_units: 10_000,
            },
            Requirement::Introduction {
                contact: "equipment_supplier_guarantor".into(),
            },
        ],
        knowledge_weight: 400,
        difficulty: 500,
        physical_demand: 200,
    };
    for (id, family) in [
        ("person:worker_child", "城市工人家庭"),
        ("person:merchant_child", "商人家庭"),
    ] {
        let facts = SocialFacts {
            family_background: Some(family.into()),
            occupation: Some("工厂职员".into()),
            ..SocialFacts::default()
        };
        println!(
            "{}",
            serde_json::to_string_pretty(&people.view(id, facts)?)?
        );
        println!(
            "{}",
            serde_json::to_string_pretty(&people.assess_action(id, &task, &host)?)?
        );
    }
    people.apply_event(
        "person:worker_child",
        2,
        LifeEvent::Injury {
            label: "左腿旧伤".into(),
            damage: 250,
            permanent_loss: 150,
        },
    )?;
    let deaths = people.advance_to(30, &host)?;
    println!(
        "30日后：{}；死亡通知数量：{}",
        people
            .view("person:worker_child", SocialFacts::default())?
            .health_status,
        deaths.len()
    );
    let saved = people.to_json()?;
    let restored = CharacterSystem::from_json(&saved, "fictional-demo", 30, &host)?;
    assert_eq!(people, restored);
    println!("人物状态存档恢复一致；示例没有执行购置、转账或创建企业。");
    Ok(())
}
