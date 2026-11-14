use serde_json::json;
use std::{error::Error, io, path::Path};
use wwo_map_lab::{formal_clock::{ClockSnapshot, GameClock, TimeControl}, formal_save::SavedWorld};

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args_os().skip(1);
    let command = args.next();
    match command.as_deref().and_then(|arg| arg.to_str()) {
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
        "use new-france, buy-rouen-grain <input> <quantity> <request-id> <output>, inspect, copy, clock or clock-control")
}
