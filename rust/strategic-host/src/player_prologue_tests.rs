use super::*;
use crate::formal_save::{native_slot_summary, read_native_slot, write_native_slot};
use wwo_character_core::{Education, Family, Temperament, Youth};

fn prologue() -> Prologue {
    Prologue {
        age: 18,
        family: Family::Poor,
        education: Education::HomeWork,
        youth: Youth::Apprentice,
        temperament: Temperament::Practice,
    }
}

fn person_state(world: &InitialWorld) -> Value {
    let state: Value = serde_json::from_str(&world.character.state).unwrap();
    state["people"][&world.player].clone()
}

fn advance(world: &mut InitialWorld, days: i64) {
    world
        .advance_migrated_domains(days * MINUTES_PER_DAY, &BTreeMap::new())
        .unwrap();
}

#[test]
fn player_prologue_age_cash_npc_and_native_slots() {
    let bootstrap = WorldBootstrap::load().unwrap();
    for (index, &(country, _)) in OPENINGS.iter().enumerate() {
        let age = [18, 20, 25][index % 3];
        let family = [Family::Poor, Family::Ordinary, Family::Wealthy][index % 3];
        let opening = Prologue {
            age,
            family,
            ..prologue()
        };
        let mut world = bootstrap.create_with_prologue(country, opening).unwrap();
        assert_eq!(world.character().age_years, u32::from(age));
        assert_eq!(world.player_birth_year(), 1900 - u16::from(age));
        let apprenticeship = &world.character.development.as_ref().unwrap().history()[2];
        assert_eq!(apprenticeship.end_year - apprenticeship.start_year, 3);
        assert!(apprenticeship.end_year <= 1900);
        assert_eq!(world.balance().unwrap().cash, [500, 2500, 10000][index % 3]);
        assert!(!world.can_read_opening_language());
        assert!(world.player_alive());
        assert_eq!(world.clock(), GameClock::default());
        let state: Value = serde_json::from_str(&world.character.state).unwrap();
        assert_eq!(
            state["people"]
                .as_object()
                .unwrap()
                .values()
                .filter(|row| row.get("player").is_some())
                .count(),
            1
        );

        world
            .schedule_personal_activity(PersonalActivity::ReadNotice)
            .unwrap();
        let path =
            std::env::temp_dir().join(format!("wwo-prologue-{}-{index}.json", std::process::id()));
        write_native_slot(&path, &world).unwrap();
        assert_eq!(
            native_slot_summary(&path).unwrap().written_access,
            Some(false)
        );
        let restored = read_native_slot(&path, &bootstrap);
        std::fs::remove_file(&path).unwrap();
        let mut restored = restored.unwrap();
        assert_eq!(world.snapshot(), restored.snapshot());
        advance(&mut restored, 1);
        assert_eq!(restored.last_read_notice(), Some(MINUTES_PER_DAY));
        assert!(!restored.can_read_opening_language());
        assert_eq!(restored.oral_work_offer().is_some(), country == "country_fra");
    }
    assert!(
        bootstrap
            .create_with_prologue(
                "country_fra",
                Prologue {
                    youth: Youth::CommercialAssistant,
                    education: Education::ReadingLessons,
                    ..prologue()
                }
            )
            .is_err()
    );
    assert!(
        bootstrap
            .create_with_prologue(
                "country_fra",
                Prologue {
                    age: 25,
                    youth: Youth::AdvancedStudy,
                    ..prologue()
                }
            )
            .is_err()
    );

    let mut legacy = bootstrap.create("country_fra").unwrap().snapshot();
    legacy.as_object_mut().unwrap().remove("player_day");
    let restored = bootstrap
        .restore_native(serde_json::from_value(legacy).unwrap())
        .unwrap();
    assert!(restored.can_read_opening_language());
    assert_eq!(restored.character().age_years, 30);
    assert_eq!(restored.balance().unwrap().cash, 2500);

    let mut prior_opening = bootstrap.create_with_prologue("country_fra", prologue()).unwrap().snapshot();
    prior_opening["player_day"].as_object_mut().unwrap().remove("written_job_notice");
    let old = bootstrap.restore_native(serde_json::from_value(prior_opening).unwrap()).unwrap();
    assert!(old.jobs().any(|(job, _)| job.id == "job:opening_paris_workshop"));
}

#[test]
fn player_prologue_learning_and_work_apply_combined_modifiers() {
    let bootstrap = WorldBootstrap::load().unwrap();
    let mut reader = bootstrap
        .create_with_prologue("country_fra", prologue())
        .unwrap();
    let mut slower = bootstrap
        .create_with_prologue(
            "country_fra",
            Prologue {
                temperament: Temperament::Struggle,
                ..prologue()
            },
        )
        .unwrap();
    for world in [&mut reader, &mut slower] {
        for _ in 0..3 {
            world
                .schedule_personal_activity(PersonalActivity::Lesson)
                .unwrap();
            assert!(
                world
                    .schedule_personal_activity(PersonalActivity::Lesson)
                    .is_err()
            );
            advance(world, 1);
        }
    }
    assert!(reader.can_read_opening_language());
    assert!(reader.jobs().any(|(job, _)| job.id == "job:opening_paris_workshop"));
    assert!(reader.can_read_polity_record("country_fra"));
    assert!(reader.can_read_place_record("place:paris"));
    assert!(!reader.can_read_polity_record("empire_of_japan"));
    assert!(!reader.can_read_place_record("place:tokyo"));
    assert!(!slower.can_read_opening_language());
    assert!(!slower.jobs().any(|(job, _)| job.id == "job:opening_paris_workshop"));
    assert!(
        person_state(&reader)["capabilities"]["literacy"]["knowledge"].as_u64()
            > person_state(&slower)["capabilities"]["literacy"]["knowledge"].as_u64()
    );
    let state = person_state(&reader);
    let sources = state["player"]["sources"].as_array().unwrap();
    assert_eq!(
        sources
            .iter()
            .filter(|source| source.as_str().unwrap().starts_with("reading-room:"))
            .count(),
        3
    );
    assert_eq!(
        reader
            .character()
            .traits
            .iter()
            .filter(|label| *label == "识字")
            .count(),
        1
    );

    let work = |temperament| {
        let mut world = bootstrap
            .create_with_prologue(
                "country_fra",
                Prologue {
                    temperament,
                    ..prologue()
                },
            )
            .unwrap();
        let job = "job:opening_paris_workshop";
        assert!(world.oral_work_offer().is_none());
        assert!(world.apply_for_work(job).is_err());
        world.schedule_personal_activity(PersonalActivity::ReadNotice).unwrap();
        advance(&mut world, 1);
        assert_eq!(world.oral_work_offer().map(|(offer, _)| offer.id.as_str()), Some(job));
        world.apply_for_work(job).unwrap();
        assert!(world.oral_work_offer().is_none());
        world.book_work().unwrap();
        assert_eq!(world.oral_work_employment().map(|(row, booked)| (row.id.as_str(), booked)), Some((job, true)));
        assert!(world.book_work().is_err());
        advance(&mut world, 1);
        let record = person_state(&world);
        assert_eq!(
            record["player"]["sources"]
                .as_array()
                .unwrap()
                .iter()
                .filter(|source| source.as_str().unwrap().starts_with("shift:"))
                .count(),
            1
        );
        record["capabilities"]["employment"]["practice"]
            .as_u64()
            .unwrap()
    };
    assert_eq!(work(Temperament::Persist), 152); // 125 + floor(35 × .75 × .875 × 1.10 × 1.10)
    assert_eq!(work(Temperament::Leave), 147);
}

#[test]
fn player_prologue_real_injury_recovery_and_death_settle_with_population_and_work() {
    let bootstrap = WorldBootstrap::load().unwrap();
    let after_shift = |temperament| {
        let mut world = bootstrap
            .create_with_prologue(
                "country_fra",
                Prologue {
                    temperament,
                    youth: Youth::Labor,
                    education: Education::ReadingLessons,
                    ..prologue()
                },
            )
            .unwrap();
        let job = world.jobs().next().unwrap().0.id.clone();
        world.apply_for_work(&job).unwrap();
        advance(&mut world, 6);
        world.book_work().unwrap();
        advance(&mut world, 1);
        world
    };
    let mut robust = after_shift(Temperament::Endure);
    let ordinary = after_shift(Temperament::Practice);
    let before = person_state(&robust);
    assert_eq!(before["health"]["permanent_loss"], 31);
    assert_eq!(person_state(&ordinary)["health"]["permanent_loss"], 38);
    let market = "market:legacy_aggregate:country_fra";
    let price =
        robust.macro_economy().markets()["country_fra"].commodities["potatoes"].price_centimes;
    robust
        .buy_local_stock(market, "potatoes", 1000, price, "meal")
        .unwrap();
    robust.consume_purchased_stock("potatoes", 1000).unwrap();
    robust
        .schedule_personal_activity(PersonalActivity::Rest)
        .unwrap();
    advance(&mut robust, 1);
    let recovered = person_state(&robust);
    assert_eq!(recovered["health"]["permanent_loss"], 31);
    assert_eq!(
        recovered["health"]["current"].as_u64().unwrap()
            - before["health"]["current"].as_u64().unwrap(),
        7
    );

    // Existing disease state in a native slot can kill a patient at the next day boundary.
    let mut saved = robust.snapshot();
    let mut file: Value = serde_json::from_str(saved["character"].as_str().unwrap()).unwrap();
    let health = &mut file["people"][&robust.player]["health"];
    health["current"] = 1.into();
    health["disease"] = serde_json::json!({"label":"疾病","severity":1000,"until_day":10});
    saved["character"] = serde_json::to_string(&file).unwrap().into();
    let mut world = bootstrap
        .restore_native(serde_json::from_value(saved).unwrap())
        .unwrap();
    let before = world.population_units()["country_fra"];
    advance(&mut world, 1);
    assert!(!world.player_alive());
    assert_eq!(world.population_units()["country_fra"], before - 1);
    assert_eq!(person_state(&world)["health"]["current"], 0);
    assert_eq!(world.character().health_status, "已去世");
    assert!(world.employment().is_none());
    assert!(world.book_work().is_err());
    assert!(
        world
            .schedule_personal_activity(PersonalActivity::Lesson)
            .is_err()
    );
    let restored = bootstrap
        .restore_native(serde_json::from_value(world.snapshot()).unwrap())
        .unwrap();
    assert!(!restored.player_alive());
    assert_eq!(restored.population_units()["country_fra"], before - 1);
}
