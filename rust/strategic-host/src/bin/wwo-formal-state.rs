use serde_json::json;
use std::{error::Error, io, path::Path};
use wwo_map_lab::battlefield_terrain::{BattlefieldTerrain, REGION_ID};
use wwo_map_lab::formal_population::historical_food::{historical_food_case, HISTORICAL_FOOD_CASES, TOKYO_SHINAMI_HOUSEHOLD};
use wwo_map_lab::{formal_bootstrap::WorldBootstrap, formal_clock::{ClockSnapshot, GameClock, TimeControl}, formal_population::{city_population_reference, population_archive}, formal_save::{read_native_slot, SavedWorld}};

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args_os().skip(1);
    let command = args.next();
    match command.as_deref().and_then(|arg| arg.to_str()) {
        Some("military-terrain") => {
            let root = args.next().ok_or_else(usage)?;
            let terrain = BattlefieldTerrain::open(Path::new(&root))?;
            while let Some(x) = args.next() {
                let z = args.next().ok_or_else(usage)?;
                let x: f64 = x.to_str().ok_or_else(usage)?.parse()?;
                let z: f64 = z.to_str().ok_or_else(usage)?.parse()?;
                if !x.is_finite() || !z.is_finite() { return Err(usage().into()); }
                println!("{}", json!({"region_id": REGION_ID, "x_m": x, "z_m": z, "sample": terrain.sample(x, z)}));
            }
        }
        Some("new-france") => {
            let opening = args.next().ok_or_else(usage)?;
            let destination = args.next().ok_or_else(usage)?;
            if args.next().is_some() { return Err(usage().into()); }
            let saved = SavedWorld::create_france(Path::new(&opening))?;
            saved.write_new(Path::new(&destination))?;
            show(&saved);
        }
        Some("buy-rouen-grain") => {
            let input=args.next().ok_or_else(usage)?;
            let quantity=args.next().ok_or_else(usage)?;
            let request=args.next().ok_or_else(usage)?;
            let output=args.next().ok_or_else(usage)?;
            if args.next().is_some(){return Err(usage().into());}
            let mut saved=SavedWorld::read(Path::new(&input))?;
            let order=saved.buy_rouen_grain(quantity.to_str().ok_or_else(usage)?.parse()?,request.to_str().ok_or_else(usage)?)?;
            saved.write_new(Path::new(&output))?;
            println!("{}",json!({"order":order,"balance":saved.player_balance()}));
        }
        Some("inspect") | Some("copy") => {
            let input = args.next().ok_or_else(usage)?;
            let destination = args.next();
            let copy = command.as_deref().and_then(|arg| arg.to_str()) == Some("copy");
            if args.next().is_some() || destination.is_some() != copy { return Err(usage().into()); }
            let saved = SavedWorld::read(Path::new(&input))?;
            if let Some(path) = destination { saved.write_new(Path::new(&path))?; }
            show(&saved);
        }
        Some("inspect-markets") => {
            let input = args.next().ok_or_else(usage)?;
            if args.next().is_some() { return Err(usage().into()); }
            let saved = SavedWorld::read(Path::new(&input))?;
            let bootstrap = WorldBootstrap::load()?;
            let economy = saved.restore_markets(&bootstrap)?;
            println!("{}", json!({
                "market_count": economy.markets().len(),
                "in_transit": economy.shipments().len(),
                "last_settled_hour": economy.last_settlement_hour(),
                "has_character_state": saved.character_state().is_some(),
                "regional_population": saved.restore_regional_population(&bootstrap)?,
            }));
        }
        Some("inspect-character") => {
            let input = args.next().ok_or_else(usage)?;
            if args.next().is_some() { return Err(usage().into()); }
            let saved = SavedWorld::read(Path::new(&input))?;
            println!("{}", serde_json::to_string(&saved.restore_character()?)?);
        }
        Some("inspect-population") => {
            let unit = args.next().ok_or_else(usage)?;
            let unit = unit.to_str().ok_or_else(usage)?;
            let input = args.next();
            if args.next().is_some() { return Err(usage().into()); }
            if let Some(city) = unit.strip_prefix("city:") {
                let reference = city_population_reference(city)?
                    .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "unknown historical city key"))?;
                println!("{}", json!({
                    "unit_id": unit,
                    "statistical_scope": "dated_city_reference",
                    "reference": reference,
                }));
                return Ok(());
            }
            if let Some(key) = unit.strip_prefix("history:") {
                let archive = population_archive(key)?
                    .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "unknown historical statistical unit"))?;
                println!("{}", json!({"unit_id": key, "statistical_scope": "dated_references", "references": archive}));
                return Ok(());
            }
            let bootstrap = WorldBootstrap::load()?;
            let world = match input {
                Some(path) => read_native_slot(Path::new(&path), &bootstrap)?,
                None => bootstrap.create("country_fra")?,
            };
            let population = world.population();
            if unit == "world" {
                println!("{}", json!({
                    "date": world.clock().current_date(),
                    "unit_id": unit,
                    "statistical_scope": "world",
                    "structure": population.structure(None, world.clock()),
                }));
                return Ok(());
            }
            let Some(total) = population.population_total(unit) else {
                let archive = population_archive(unit)?
                    .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "unknown statistical population unit"))?;
                println!("{}", json!({
                    "date": world.clock().current_date(), "unit_id": unit,
                    "statistical_scope": "no_standalone_opening_account", "population_total": null,
                    "references": archive,
                }));
                return Ok(());
            };
            let partitions = population.partitions(unit).map(|(id, name, count)| {
                json!({"unit_id": id, "name": name, "population_total": count})
            }).collect::<Vec<_>>();
            let admitted = population.admitted_opening(unit);
            let scope = if !partitions.is_empty() {
                match admitted {
                    Some(estimate) if estimate.research_unlocated_balance.is_some() => "partially_located_historical_aggregate",
                    Some(_) => "partitioned_aggregate",
                    None => "partially_located_legacy_aggregate",
                }
            } else if population.totals().contains_key(unit) {
                "national_market"
            } else if population.standalone_totals().contains_key(unit) {
                "standalone_territory"
            } else {
                "statistical_partition"
            };
            println!("{}", json!({
                "date": world.clock().current_date(),
                "unit_id": unit,
                "statistical_scope": scope,
                "opening_basis": if admitted.is_some() { "historical_source" } else { "legacy_economic_estimate" },
                "population_total": total,
                "direct_residents": population.resident_pool(unit),
                "background_population": population.background(unit),
                "admitted_opening": admitted,
                "legacy_estimate": population.opening_estimate(unit)?,
                "partitions": partitions,
                "structure": population.structure(Some(unit), world.clock()),
            }));
        }
        Some("inspect-age-range") => {
            let unit = args.next().ok_or_else(usage)?;
            let unit = unit.to_str().ok_or_else(usage)?;
            let youngest = args.next().ok_or_else(usage)?.to_str().ok_or_else(usage)?.parse()?;
            let oldest = args.next().ok_or_else(usage)?.to_str().ok_or_else(usage)?.parse()?;
            let input = args.next();
            if args.next().is_some() { return Err(usage().into()); }
            let bootstrap = WorldBootstrap::load()?;
            let world = match input {
                Some(path) => read_native_slot(Path::new(&path), &bootstrap)?,
                None => bootstrap.create("country_fra")?,
            };
            let scope = (unit != "world").then_some(unit);
            println!("{}", json!({
                "date": world.clock().current_date(),
                "unit_id": unit,
                "availability": world.resident_age_availability(scope, youngest, oldest)?,
            }));
        }
        Some("inspect-market-livelihood") => {
            let unit = args.next().ok_or_else(usage)?;
            let unit = unit.to_str().ok_or_else(usage)?;
            let input = args.next();
            if args.next().is_some() { return Err(usage().into()); }
            let bootstrap = WorldBootstrap::load()?;
            let world = match input {
                Some(path) => read_native_slot(Path::new(&path), &bootstrap)?,
                None => bootstrap.create("country_fra")?,
            };
            let structure = world.population().structure(Some(unit), world.clock())
                .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "unknown statistical population unit"))?;
            let flows = world.macro_economy().food_flows(unit).map(|rows| rows.collect::<Vec<_>>());
            println!("{}", json!({
                "date": world.clock().current_date(),
                "unit_id": unit,
                "population_total": structure.population_total,
                "physiological_energy_reference": structure.published_energy_reference,
                "physiological_protein_reference": structure.published_protein_reference,
                "physiological_adult_water_references": structure.published_adult_water_references,
                "physiological_efsa_water_reference": structure.published_efsa_water_reference,
                "domestic_water_service_reference": structure.published_domestic_water_service_reference,
                "parent_or_own_market_unit": world.market_unit_for_population(unit),
                "macro_food_flows": flows,
                "household_budget_coverage": "unknown_at_aggregate_scope",
                "household_purchase_coverage": "unknown_at_aggregate_scope",
                "household_intake_coverage": "unknown_at_aggregate_scope",
            }));
        }
        Some("inspect-intake") => {
            let path = args.next().ok_or_else(usage)?;
            let person = args.next().ok_or_else(usage)?;
            let person = person.to_str().ok_or_else(usage)?;
            if args.next().is_some() { return Err(usage().into()); }
            let world = read_native_slot(Path::new(&path), &WorldBootstrap::load()?)?;
            let livelihood = world.person_livelihood(person)
                .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "unknown formal resident"))?;
            println!("{}", json!({
                "person_id": person,
                "last_settled_day": livelihood.last_day,
                "last_recorded_intake": livelihood.last_food_intake,
                "last_recorded_energy": livelihood.last_food_intake.map(|intake| intake.recorded_energy()),
            }));
        }
        Some("inspect-food-history") => {
            let input = args.next();
            if args.next().is_some() { return Err(usage().into()); }
            if let Some(id) = input.as_deref() {
                let id = id.to_str().ok_or_else(usage)?;
                if id == TOKYO_SHINAMI_HOUSEHOLD.id {
                    println!("{}", serde_json::to_string(&TOKYO_SHINAMI_HOUSEHOLD)?);
                } else {
                    let case = historical_food_case(id)
                        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "unknown historical food account"))?;
                    println!("{}", serde_json::to_string(case)?);
                }
            } else {
                let mut cases = HISTORICAL_FOOD_CASES.iter().map(serde_json::to_value)
                    .collect::<Result<Vec<_>, _>>()?;
                cases.push(serde_json::to_value(&TOKYO_SHINAMI_HOUSEHOLD)?);
                println!("{}", serde_json::to_string(&cases)?);
            }
        }
        Some("inspect-wages") => {
            let input = args.next().ok_or_else(usage)?;
            if args.next().is_some() { return Err(usage().into()); }
            let saved = SavedWorld::read(Path::new(&input))?;
            let claims = saved.restore_regional_wages()?;
            println!("{}", json!({"open_regional_wages": claims.as_ref().map(|wages| wages.open_count())}));
        }
        Some("inspect-firm-work") => {
            let input = args.next().ok_or_else(usage)?;
            let firm = args.next().ok_or_else(usage)?;
            let firm = firm.to_str().ok_or_else(usage)?;
            let day = args.next().ok_or_else(usage)?;
            let day = day.to_str().ok_or_else(usage)?.parse()?;
            if args.next().is_some() { return Err(usage().into()); }
            let world = read_native_slot(Path::new(&input), &WorldBootstrap::load()?)?;
            println!("{}", json!({"firm": firm, "work_day": day, "completed_work": world.completed_firm_work(firm, day)?}));
        }
        Some("clock") => {
            let mut clock = GameClock::default();
            for input in args {
                let input = input.to_str().ok_or_else(usage)?;
                clock.advance_minutes(input.parse()?)?;
                clock = GameClock::restore(clock.snapshot())?;
                println!("{}", json!({"clock":clock.snapshot(), "date":clock.current_date()}));
            }
        }
        Some("clock-control") => {
            let mut control = TimeControl::default();
            let mut clock = GameClock::restore(ClockSnapshot::default())?;
            for input in args {
                match input.to_str().ok_or_else(usage)? {
                    "pause" => control.toggle_pause(),
                    "tick" => { if let Some(minutes) = control.tick() { clock.advance_minutes(minutes)?; } },
                    speed => control.set_speed(speed.parse()?),
                }
                println!("{}", json!({"clock":clock.snapshot(), "paused":control.paused, "speed":control.speed}));
            }
        }
        _ => return Err(usage().into()),
    }
    Ok(())
}

fn show(saved: &SavedWorld) {
    let clock = saved.clock();
    println!("{}", json!({"player_id":saved.player_id(), "clock":clock.snapshot(), "date":clock.current_date(),
        "balance":saved.player_balance(), "native_holdings":saved.player_holdings()}));
}

fn usage() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput,
        "use new-france, buy-rouen-grain <input> <quantity> <request-id> <output>, inspect, inspect-markets, inspect-character, inspect-population <world|unit-id|city:city-key|history:unit-id> [<native-save>], inspect-age-range <world|unit-id> <youngest> <oldest> [<native-save>], inspect-market-livelihood <unit-id> [<native-save>], inspect-intake <native-save> <person-id>, inspect-food-history [<case-id>], inspect-wages, inspect-firm-work <native-save> <firm-id> <day>, copy, clock, clock-control, or military-terrain <region-root> [<x-m> <z-m> ...]")
}
