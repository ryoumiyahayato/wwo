use super::*;

const OPENING: &str = "person:opening";

fn opening() -> Population {
    let mut population = Population::initialize(BTreeMap::from([("a".to_owned(), 8), ("b".to_owned(), 3)]));
    population.claim(OPENING, "a").unwrap();
    population
}

#[test]
fn native_population_replays_sparse_cohorts_and_resident_changes() {
    let mut population = opening();
    let id = CohortId::new("population-fixture", "group-1").unwrap();
    let definition = CohortDefinition {
        provenance: CohortProvenance::Fixture,
        sex: Some(CohortSex::Female),
        birth_years: Some(CohortBirthYears { earliest: 1870, latest: 1880 }),
    };
    population.alloc_cohort("a", id.clone(), definition, 4, 0).unwrap();
    assert!(population.alloc_cohort("a", id.clone(), definition, 1, 0).is_err());
    assert!(population.transfer_unmanaged("a", "b", 3, 1, 1).is_err());
    population.transfer_unmanaged("a", "b", 2, 1, 1).unwrap();
    population.transfer_cohort("a", "b", &id, 2, 1).unwrap();
    population.materialize_person("person:materialized", "a", Some(&id), 2).unwrap();
    population.move_person("person:materialized", "b", 3).unwrap();
    population.arrive_person("person:arrival", "b", 4).unwrap();
    population.record_named_birth("person:child", "b", 4).unwrap();
    population.record_anonymous_births("a", 3, 5).unwrap();
    population.record_anonymous_deaths("a", 1, 6).unwrap();
    assert!(population.record_cohort_deaths("b", &id, 3, 7).is_err());
    population.record_cohort_deaths("b", &id, 1, 7).unwrap();
    population.record_death(OPENING, 8).unwrap();
    assert!(population.arrive_person(OPENING, "b", 9).is_err());

    let saved = serde_json::to_value(population.snapshot()).unwrap();
    let restored = opening().restore_native(serde_json::from_value(saved.clone()).unwrap(), 8).unwrap();
    assert_eq!(serde_json::to_value(restored.snapshot()).unwrap(), saved);
    assert_eq!(restored.totals(), &BTreeMap::from([("a".to_owned(), 4), ("b".to_owned(), 9)]));
    assert_eq!(restored.cohort_members("a", &id), Some(1));
    assert_eq!(restored.cohorts_in("b").collect::<Vec<_>>(), [(&id, &definition, 1)]);
    assert_eq!(restored.background("b"), Some(6));
    assert_eq!(restored.unclassified("b"), Some(5));
    assert_eq!(restored.unit_for_person("person:materialized"), Some("b"));
    assert_eq!(restored.death_minute(OPENING), Some(8));
    let mut clock = GameClock::default();
    clock.advance_minutes(8).unwrap();
    let source_report = restored.inspect("a", clock).unwrap();
    let destination_report = restored.inspect("b", clock).unwrap();
    assert_eq!(source_report.population_total, Some(4));
    for report in [&source_report, &destination_report] {
        let movement = report.recent_changes.iter().find(|event| event.kind == "move").unwrap();
        assert_eq!((movement.unit_id, movement.destination, movement.members), (Some("a"), Some("b"), Some(1)));
    }
    let death = source_report.recent_changes.first().unwrap();
    assert_eq!((death.kind, death.unit_id, death.minute), ("death", Some("a"), 8));
    assert_eq!(serde_json::to_value(restored.snapshot()).unwrap(), saved);
    assert!(restored.known_dead(OPENING));
    restored.check_identities([
        (OPENING, false), ("person:materialized", true), ("person:arrival", true), ("person:child", true),
    ]).unwrap();
    assert!(restored.check_identities([(OPENING, true)]).is_err());
    let origins = [
        ("person:materialized", "a", 1873, None),
        ("person:arrival", "b", 1880, None),
        ("person:child", "b", 1900, Some(0)),
    ];
    restored.check_runtime_origins(origins).unwrap();
    let mut invalid_origins = origins;
    invalid_origins[0].1 = "b";
    assert!(restored.check_runtime_origins(invalid_origins).is_err());
    invalid_origins = origins;
    invalid_origins[0].2 = 1883;
    assert!(restored.check_runtime_origins(invalid_origins).is_err());
    invalid_origins = origins;
    invalid_origins[2].3 = Some(1);
    assert!(restored.check_runtime_origins(invalid_origins).is_err());
}

#[test]
fn native_population_migrates_flat_totals_and_known_deaths() {
    let totals = BTreeMap::from([("a".to_owned(), 6), ("b".to_owned(), 4)]);
    let mut migrated = opening().migrate_native(totals.clone(), [OPENING].into_iter()).unwrap();
    assert_eq!(migrated.totals(), &totals);
    assert!(migrated.known_dead(OPENING));
    assert_eq!(migrated.death_minute(OPENING), None);
    assert!(migrated.materialize_person(OPENING, "a", None, 5).is_err());
    assert!(opening().migrate_native(totals, ["person:unknown"].into_iter()).is_err());
    migrated.transfer_unmanaged("a", "b", 2, 0, 6).unwrap();

    let restored = opening().restore_native(migrated.snapshot(), 6).unwrap();
    assert_eq!(restored.background("a"), Some(4));
    assert_eq!(restored.background("b"), Some(6));
    assert!(restored.inspect("a", GameClock::default()).unwrap().archived_change_details_unknown);
    assert!(restored.known_dead(OPENING));
    assert!(restored.check_identities([]).is_err());
    restored.check_identities([(OPENING, false)]).unwrap();
}

#[test]
fn native_population_rejects_inconsistent_event_history() {
    let mut population = opening();
    population.transfer_unmanaged("a", "b", 2, 0, 10).unwrap();
    population.record_death(OPENING, 20).unwrap();
    assert!(population.record_anonymous_births("a", 1, 19).is_err());
    assert!(opening().restore_native(population.snapshot(), 19).is_err());
    assert!(population.clone().restore_native(population.snapshot(), 20).is_err());

    let saved = serde_json::to_value(population.snapshot()).unwrap();
    let mut unsupported = saved.clone();
    unsupported["version"] = 2.into();
    assert!(opening().restore_native(serde_json::from_value(unsupported).unwrap(), 20).is_err());
    let mut unordered = saved.clone();
    unordered["journal"].as_array_mut().unwrap().swap(0, 1);
    assert!(opening().restore_native(serde_json::from_value(unordered).unwrap(), 20).is_err());
    let mut overdrawn = saved;
    overdrawn["journal"][0]["change"]["members"] = 8.into();
    assert!(opening().restore_native(serde_json::from_value(overdrawn).unwrap(), 20).is_err());
}

#[test]
fn historical_estimate_keeps_its_source_range_after_resident_transfers() {
    let unit = "country_fra";
    let mut population = Population::initialize(BTreeMap::from([(unit.to_owned(), 40_700_000), ("b".to_owned(), 0)]));
    let estimate = population.opening_estimate(unit).unwrap().unwrap();
    assert_eq!((estimate.lower, estimate.value, estimate.upper), (38_258_000, 40_700_000, 43_142_000));
    assert_eq!(estimate.confidence_bp, 7500);
    assert_eq!(estimate.calibration_date, "1900-01-01");
    assert_eq!(estimate.source_method, "historical_series_or_census_anchor_with_border_crosswalk");
    assert_eq!(population.opening_estimate("b").unwrap(), None);
    population.transfer_unmanaged(unit, "b", 2, 0, 1).unwrap();
    assert_eq!(population.totals()[unit], 40_699_998);
    assert_eq!(population.opening_estimate(unit).unwrap(), Some(estimate));
}

#[test]
fn fixture_cohort_matures_and_keeps_its_identity_when_residence_changes() {
    use crate::formal_clock::MINUTES_PER_DAY;

    let mut population = opening();
    let id = CohortId::new("population-fixture", "1882").unwrap();
    let definition = CohortDefinition {
        provenance: CohortProvenance::Fixture,
        sex: None,
        birth_years: Some(CohortBirthYears { earliest: 1882, latest: 1882 }),
    };
    let unsupported = CohortDefinition { provenance: CohortProvenance::Observed, ..definition };
    assert!(population.alloc_cohort("a", id.clone(), unsupported, 3, 0).is_err());
    population.alloc_cohort("a", id.clone(), definition, 3, 0).unwrap();
    let mut clock = GameClock::default();
    assert_eq!(definition.age_bounds(clock), Some((17, 18)));

    clock.advance_minutes(364 * MINUTES_PER_DAY).unwrap();
    let minute = clock.snapshot().total_minutes;
    population.transfer_cohort("a", "b", &id, 3, minute).unwrap();
    let (target_id, target_definition, members) = population.cohorts_in("b").next().unwrap();
    assert_eq!((target_id, target_definition.age_bounds(clock), members), (&id, Some((18, 18)), 3));
    assert_eq!(population.cohort_members("a", &id), None);

    let restored = opening().restore_native(population.snapshot(), minute).unwrap();
    assert_eq!(restored.cohort_members("b", &id), Some(3));
    assert_eq!(restored.totals(), population.totals());
}
