use crate::formal_clock::{ClockSnapshot, GameClock};
use crate::formal_ledger::{Balance, Ledger};
use flate2::read::ZlibDecoder;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::BTreeMap, fs, io::{self, BufReader, Write}, path::Path, time::{SystemTime, UNIX_EPOCH}};

const TRANSFER_FORMAT: &str = "wwo_formal_transfer_v1";
const SOURCE_FORMAT: &str = "formal_world_exact_variant_v1";
const SNAPSHOT_SCHEMA: &str = "formal_world_simulation_v15";
const FRANCE_PLAYER: &str = "person:formal_generated_country_fra_0001";
const REQUIRED_DOMAINS: &[&str] = &[
    "historical_evidence", "runtime_politics", "markets", "economy", "spatial", "territory",
    "population", "persons", "player", "ledger", "personal_economy", "organization",
    "organization_composition", "organization_responsibilities", "military_state",
];

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Transfer {
    format: String,
    source_format: String,
    source_schema: String,
    snapshot: Value,
    metadata: Value,
}

pub struct SavedWorld {
    transfer: Transfer,
    clock: GameClock,
    player_id: String,
    ledger: Ledger,
    holdings: BTreeMap<String, i64>,
}

impl SavedWorld {
    pub fn read(path: &Path) -> io::Result<Self> {
        Self::validate(serde_json::from_reader(BufReader::new(fs::File::open(path)?))?)
    }

    pub fn create_france(opening: &Path) -> io::Result<Self> {
        let seed = ZlibDecoder::new(BufReader::new(fs::File::open(opening)?));
        let mut result = Self::validate(serde_json::from_reader(seed)?)?;
        if result.player_id != FRANCE_PLAYER || result.clock != GameClock::default() {
            return Err(invalid("French opening seed must contain the official player at minute zero"));
        }
        let nation = map(&result.transfer.snapshot)?;
        if lookup(nation, "economy_native").is_none() || lookup(nation, "person_travel").is_none() {
            return Err(invalid("French opening is missing its native economy or travel state"));
        }
        let now = SystemTime::now().duration_since(UNIX_EPOCH).map_err(io::Error::other)?.as_secs().to_string();
        let typed_time = serde_json::json!(["int", now]);
        let writer = serde_json::json!(["map", [["build_id", "wwo-rust-formal-state"],
            ["build_label", "WWO Rust native opening data"], ["application_version", env!("CARGO_PKG_VERSION")],
            ["build_sequence", ["int", "0"]]]]);
        let pairs = result.transfer.metadata[1].as_array_mut().unwrap();
        for pair in pairs {
            match pair[0].as_str().unwrap_or_default() {
                "created_game_version" | "last_saved_game_version" => pair[1] = writer.clone(),
                "created_at_unix" | "last_saved_at_unix" => pair[1] = typed_time.clone(),
                _ => {}
            }
        }
        Ok(result)
    }

    pub fn clock(&self) -> GameClock { self.clock }

    pub fn player_id(&self) -> &str { &self.player_id }

    pub fn player_balance(&self) -> Option<Balance<'_>> { self.ledger.default_account(&self.player_id) }

    pub fn player_holdings(&self) -> &BTreeMap<String, i64> { &self.holdings }

    pub fn buy_rouen_grain(&mut self, quantity: i64, request: &str) -> io::Result<String> {
        let mut candidate=self.transfer.clone();
        let order=crate::formal_purchase::buy(&mut candidate.snapshot,quantity,request)?;
        *self=Self::validate(candidate)?;
        Ok(order)
    }

    fn validate(transfer: Transfer) -> io::Result<Self> {
        if transfer.format != TRANSFER_FORMAT || transfer.source_format != SOURCE_FORMAT || transfer.source_schema != SNAPSHOT_SCHEMA {
            return Err(invalid("unsupported formal transfer format or snapshot schema"));
        }
        validate_value(&transfer.snapshot)?;
        validate_value(&transfer.metadata)?;
        map(&transfer.metadata)?;
        let snapshot = map(&transfer.snapshot)?;
        if field(snapshot, "schema_id")?.as_str() != Some(SNAPSHOT_SCHEMA) {
            return Err(invalid("formal snapshot schema conflicts with transfer header"));
        }
        for name in REQUIRED_DOMAINS {
            map(field(snapshot, name)?)?;
        }
        for optional in ["economy_native", "person_travel"] {
            if let Some(value) = lookup(snapshot, optional) { map(value)?; }
        }
        if snapshot.iter().any(|pair| {
            !pair[0].as_str().is_some_and(|name| REQUIRED_DOMAINS.contains(&name) || matches!(name,
                "schema_id" | "total_minutes" | "minute_remainder" | "economy_native" | "person_travel"))
        }) {
            return Err(invalid("unknown formal snapshot field"));
        }

        let clock = GameClock::restore(ClockSnapshot {
            total_minutes: integer(field(snapshot, "total_minutes")?)?,
            minute_remainder: integer(field(snapshot, "minute_remainder")?)?,
        })?;
        for (domain, time_field, expected) in [
            ("economy", "total_hour", clock.current_hour()),
            ("spatial", "current_hour", clock.current_hour()),
            ("economy_native", "day", clock.current_day()),
        ] {
            if let Some(value) = lookup(snapshot, domain) {
                if integer(field(map(value)?, time_field)?)? != expected {
                    return Err(invalid(format!("{domain} time conflicts with the formal clock")));
                }
            }
        }
        let player = map(field(snapshot, "player")?)?;
        if player.len() != 2 || field(player, "schema_id")?.as_str() != Some("vnext_player_state_v1") {
            return Err(invalid("invalid player snapshot"));
        }
        let player_id = field(player, "player_id")?.as_str().ok_or_else(|| invalid("missing player ID"))?;
        if !player_id.strip_prefix("person:").is_some_and(|id| {
            !id.is_empty() && id.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, b'_' | b'-'))
        }) {
            return Err(invalid("invalid player ID"));
        }
        let persons = map(field(snapshot, "persons")?)?;
        let members = tagged(field(persons, "persons")?, "array")?;
        let mut matched = false;
        for row in members {
            if field(map(row)?, "person_id")?.as_str() == Some(player_id) {
                if matched { return Err(invalid("duplicate player in person overlay")); }
                matched = true;
            }
        }
        if !matched { return Err(invalid("player is absent from the person overlay")); }
        let native = lookup(snapshot, "economy_native");
        let ledger = Ledger::restore(field(snapshot, "ledger")?, native.is_some())?;
        let holdings = match native {
            Some(economy) => crate::formal_stock::restore(map(economy)?, clock.snapshot().total_minutes, player_id)?,
            None => BTreeMap::new(),
        };
        Ok(Self { player_id: player_id.to_owned(), clock, transfer, ledger, holdings })
    }

    // Publish a new transfer without overwriting a game slot or an existing copy.
    pub fn write_new(&self, path: &Path) -> io::Result<()> {
        if path.exists() { return Err(io::Error::new(io::ErrorKind::AlreadyExists, "transfer destination exists")); }
        let mut name = path.as_os_str().to_os_string();
        name.push(".tmp");
        let temporary = Path::new(&name);
        let output = fs::OpenOptions::new().create_new(true).write(true).open(temporary)?;
        let result = (|| {
            let mut output = output;
            serde_json::to_writer(&mut output, &self.transfer)?;
            output.flush()?;
            output.sync_all()?;
            drop(output);
            if Self::read(temporary)?.transfer != self.transfer {
                return Err(invalid("formal transfer changed during write"));
            }
            #[cfg(windows)]
            { publish_windows(temporary,path) }
            #[cfg(not(windows))]
            { fs::hard_link(temporary,path) }
        })();
        // Publication already succeeded if the link was created. The temporary name is expendable.
        let _ = fs::remove_file(temporary);
        result
    }
}

fn validate_value(value: &Value) -> io::Result<()> {
    match value {
        Value::Null | Value::Bool(_) | Value::String(_) => Ok(()),
        Value::Array(fields) => match fields.first().and_then(Value::as_str) {
            Some("int") => integer(value).map(|_| ()),
            Some("array") => tagged(value, "array")?.iter().try_for_each(validate_value),
            Some("map") => {
                let pairs = map(value)?;
                let mut keys = std::collections::HashSet::with_capacity(pairs.len());
                for pair in pairs {
                    let pair = pair.as_array().filter(|pair| pair.len() == 2).ok_or_else(|| invalid("invalid transfer map pair"))?;
                    validate_value(&pair[0])?;
                    validate_value(&pair[1])?;
                    if !keys.insert(&pair[0]) { return Err(invalid("duplicate transfer map key")); }
                }
                Ok(())
            }
            // The original exporter validated Godot's opaque Variant values. Keep the byte representation verbatim.
            Some("variant_bytes") if fields.len() == 3 && fields[1].as_u64().is_some_and(|tag| tag > 0 && tag < 39)
                && fields[2].as_str().is_some_and(|bytes| !bytes.is_empty() && bytes.len() % 4 == 0) => Ok(()),
            _ => Err(invalid("unsupported typed transfer value")),
        },
        _ => Err(invalid("untyped transfer value")),
    }
}

pub(crate) fn tagged<'a>(value: &'a Value, kind: &str) -> io::Result<&'a [Value]> {
    let fields = value.as_array().filter(|fields| fields.len() == 2 && fields[0].as_str() == Some(kind))
        .ok_or_else(|| invalid(format!("expected transfer {kind}")))?;
    fields[1].as_array().map(Vec::as_slice).ok_or_else(|| invalid(format!("invalid transfer {kind} payload")))
}

pub(crate) fn map(value: &Value) -> io::Result<&[Value]> { tagged(value, "map") }

pub(crate) fn lookup<'a>(pairs: &'a [Value], key: &str) -> Option<&'a Value> {
    pairs.iter().find(|pair| pair[0].as_str() == Some(key)).map(|pair| &pair[1])
}

pub(crate) fn field<'a>(pairs: &'a [Value], key: &str) -> io::Result<&'a Value> {
    lookup(pairs, key).ok_or_else(|| invalid(format!("missing formal transfer field {key}")))
}

pub(crate) fn integer(value: &Value) -> io::Result<i64> {
    if let Some(fields) = value.as_array().filter(|fields| fields.len() == 2 && fields[0].as_str() == Some("int")) {
        if let Some(text) = fields[1].as_str() {
            if let Ok(value) = text.parse::<i64>() {
                if text == value.to_string() { return Ok(value); }
            }
        }
    }
    Err(invalid("invalid transfer integer"))
}

pub(crate) fn invalid(message: impl Into<String>) -> io::Error { io::Error::new(io::ErrorKind::InvalidData, message.into()) }

#[cfg(windows)]
fn publish_windows(from:&Path,to:&Path)->io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name="kernel32")]
    unsafe extern "system" {fn MoveFileExW(from:*const u16,to:*const u16,flags:u32)->i32;}
    let source:Vec<_>=from.as_os_str().encode_wide().chain([0]).collect();
    let target:Vec<_>=to.as_os_str().encode_wide().chain([0]).collect();
    // The temporary file is created beside the destination. Without REPLACE_EXISTING the destination is protected.
    if unsafe {MoveFileExW(source.as_ptr(),target.as_ptr(),8)}==0 {Err(io::Error::last_os_error())}else{Ok(())}
}
