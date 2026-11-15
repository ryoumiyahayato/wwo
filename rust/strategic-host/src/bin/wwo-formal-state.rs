use serde_json::json;
use std::{error::Error, io, path::Path};
use wwo_map_lab::battlefield_terrain::{BattlefieldTerrain, REGION_ID};
use wwo_map_lab::{formal_bootstrap::WorldBootstrap, formal_clock::{ClockSnapshot, GameClock, TimeControl}, formal_save::{read_native_slot, SavedWorld}};

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
        "use new-france, buy-rouen-grain <input> <quantity> <request-id> <output>, inspect, inspect-markets, inspect-character, inspect-wages, inspect-firm-work <native-save> <firm-id> <day>, copy, clock, clock-control, or military-terrain <region-root> [<x-m> <z-m> ...]")
}
