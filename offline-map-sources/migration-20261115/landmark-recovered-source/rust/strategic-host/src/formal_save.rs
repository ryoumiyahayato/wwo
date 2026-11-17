use crate::formal_bootstrap::{InitialWorld, WorldBootstrap, WorldSnapshot, OPENINGS};
use crate::formal_character::{self, Identity};
use crate::formal_clock::{ClockSnapshot, GameClock};
use crate::formal_ledger::{Balance, Ledger, CURRENCY};
use crate::formal_macro::MacroEconomy;
use crate::formal_population::Population;
use crate::formal_wages::WageClaims;
use crate::legacy_variant;
use flate2::read::ZlibDecoder;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{collections::{BTreeMap, BTreeSet}, fs, io::{self, BufReader, Write}, path::Path, time::{SystemTime, UNIX_EPOCH}};
use wwo_character_core::SocialFacts;

const TRANSFER_FORMAT: &str = "wwo_formal_transfer_v1";
const NATIVE_FORMAT: &str = "wwo_rust_formal_world_v1";
const SOURCE_FORMAT: &str = "formal_world_exact_variant_v1";
const SNAPSHOT_SCHEMA: &str = "formal_world_simulation_v15";
const FRANCE_PLAYER: &str = "person:formal_generated_country_fra_0001";
const REQUIRED_DOMAINS: &[&str] = &[
    "historical_evidence", "runtime_politics", "markets", "economy", "spatial", "territory",
    "population", "persons", "player", "ledger", "personal_economy", "organization",
    "organization_composition", "organization_responsibilities", "military_state",
];

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NativeSlotSummary {
    pub opening: String,
    pub clock: ClockSnapshot,
}

impl NativeSlotSummary {
    fn validate(&self) -> io::Result<GameClock> {
        if !OPENINGS.iter().any(|(source, _)| self.opening == *source) {
            return Err(invalid("unknown native save opening"));
        }
        GameClock::restore(self.clock)
    }
}

pub fn native_slot_summary(path: &Path) -> io::Result<NativeSlotSummary> {
    // The first line is the small slot header. The world follows as JSON.
    use std::io::{BufRead, Read};
    let file = fs::File::open(path)?;
    let mut line = String::new();
    BufReader::new(file).take(1024).read_line(&mut line)?;
    let (format, summary): (String, NativeSlotSummary) = serde_json::from_str(&line)?;
    if format != NATIVE_FORMAT || !line.ends_with('\n') {
        return Err(invalid("invalid native save header"));
    }
    summary.validate()?;
    Ok(summary)
}

pub fn read_native_slot(path: &Path, bootstrap: &WorldBootstrap) -> io::Result<InitialWorld> {
    use std::io::{BufRead, Read};
    let file = fs::File::open(path)?;
    if file.metadata()?.len() > 128 * 1024 * 1024 {
        return Err(invalid("native save is too large"));
    }
    let mut reader = BufReader::new(file);
    let mut header = String::new();
    (&mut reader).take(1024).read_line(&mut header)?;
    let (format, summary): (String, NativeSlotSummary) = serde_json::from_str(&header)?;
    if format != NATIVE_FORMAT || !header.ends_with('\n') {
        return Err(invalid("invalid native save header"));
    }
    let clock = summary.validate()?;
    let saved: WorldSnapshot = serde_json::from_reader(reader)?;
    let world = bootstrap.restore_native(saved)?;
    if world.clock() != clock || world.player().opening_source_id != summary.opening {
        return Err(invalid("native slot header and world do not match"));
    }
    Ok(world)
}

pub fn write_native_slot(path: &Path, world: &InitialWorld) -> io::Result<()> {
    let summary = NativeSlotSummary { opening: world.player().opening_source_id.clone(), clock: world.clock().snapshot() };
    let temporary = path.with_extension("json.rust-tmp");
    let result = (|| {
        let mut output = io::BufWriter::new(fs::File::create(&temporary)?);
        serde_json::to_writer(&mut output, &(NATIVE_FORMAT, summary))?;
        output.write_all(b"\n")?;
        serde_json::to_writer(&mut output, &world.snapshot())?;
        output.flush()?;
        output.get_ref().sync_all()?;
        drop(output);
        #[cfg(windows)]
        { publish_windows(&temporary, path, true) }
        #[cfg(not(windows))]
        { fs::rename(&temporary, path) }
    })();
    if result.is_err() { let _ = fs::remove_file(&temporary); }
    result
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Transfer {
    format: String,
    source_format: String,
    source_schema: String,
    snapshot: Value,
    metadata: Value,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum DiskSave {
    Transfer(Transfer),
    Legacy {
        persistence_format: String,
        snapshot_schema_id: String,
        payload_base64: String,
        save_metadata: Option<Value>,
        ui_summary: Option<Value>,
    },
}

pub struct SavedWorld {
    transfer: Transfer,
    clock: GameClock,
    player_id: String,
    population: Population,
    ledger: Ledger,
    holdings: BTreeMap<String, i64>,
}

impl SavedWorld {
    pub fn read(path: &Path) -> io::Result<Self> {
        let input = BufReader::new(fs::File::open(path)?);
        let transfer = match serde_json::from_reader(input)? {
            DiskSave::Transfer(transfer) => transfer,
            DiskSave::Legacy { persistence_format, snapshot_schema_id, payload_base64, save_metadata, ui_summary } => {
                if persistence_format != SOURCE_FORMAT || snapshot_schema_id != SNAPSHOT_SCHEMA {
                    return Err(invalid("unsupported original formal save format or snapshot schema"));
                }
                let metadata = match save_metadata {
                    Some(metadata) if metadata.get("schema_id").and_then(Value::as_str) == Some("formal_save_metadata_v1") => metadata,
                    Some(_) => return Err(invalid("unsupported original formal save metadata")),
                    None => old_metadata(ui_summary.as_ref()),
                };
                Transfer {
                    format: TRANSFER_FORMAT.to_owned(),
                    source_format: persistence_format,
                    source_schema: snapshot_schema_id,
                    snapshot: legacy_variant::decode_snapshot(&payload_base64)?,
                    metadata: encode_metadata(metadata),
                }
            }
        };
        Self::validate(transfer)
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

    pub fn character_state(&self) -> Option<&str> {
        lookup(map(&self.transfer.snapshot).ok()?, "rust_character").and_then(Value::as_str)
    }

    pub fn restore_markets(&self, bootstrap: &WorldBootstrap) -> io::Result<MacroEconomy> {
        let snapshot = map(&self.transfer.snapshot)?;
        bootstrap.restore_markets(field(snapshot, "economy")?, self.clock, self.population.totals())
    }

    pub fn population(&self) -> &Population {
        &self.population
    }

    pub fn restore_regional_wages(&self) -> io::Result<Option<WageClaims>> {
        let snapshot = map(&self.transfer.snapshot)?;
        lookup(snapshot, "economy_native").map(|native| WageClaims::restore(native, &self.ledger, self.clock)).transpose()
    }

    pub fn restore_regional_population(&self, bootstrap: &WorldBootstrap) -> io::Result<BTreeMap<String, u64>> {
        let snapshot = map(&self.transfer.snapshot)?;
        let Some(native) = lookup(snapshot, "economy_native") else { return Ok(BTreeMap::new()); };
        let population = map(field(snapshot, "population")?)?;
        let mut places = BTreeMap::new();
        if let Some(bindings) = lookup(population, "place_population_bindings") {
            for binding in tagged(bindings, "array")? {
                let row = map(binding)?;
                let place = field(row, "place_id")?.as_str().ok_or_else(|| invalid("missing saved population place"))?;
                let unit = field(row, "population_unit_id")?.as_str().ok_or_else(|| invalid("missing saved place population unit"))?;
                if !bootstrap.sources().places().contains_key(place)
                    || !self.population.totals().contains_key(unit)
                    || bootstrap.sources().population_unit_at(place).is_some_and(|original| original != unit)
                    || places.insert(place, unit).is_some()
                {
                    return Err(invalid("saved population place conflicts with the world"));
                }
            }
        }
        self.population.restore_regional_responsibility(native, self.clock.snapshot().total_minutes, |place| {
            places.get(place).copied().or_else(|| bootstrap.sources().population_unit_at(place))
        })
    }

    pub fn restore_character(&self) -> io::Result<wwo_character_core::PersonView> {
        let snapshot = map(&self.transfer.snapshot)?;
        let persons = map(field(snapshot, "persons")?)?;
        if field(persons, "schema_id")?.as_str() != Some("vnext_named_person_overlay_v1") {
            return Err(invalid("unsupported formal named person overlay"));
        }
        let mut opening = None;
        let mut people = BTreeMap::new();
        let mut claims = BTreeSet::new();
        let mut living = 0;
        for person in tagged(field(persons, "persons")?, "array")? {
            let row = map(person)?;
            let id = field(row, "person_id")?.as_str().ok_or_else(|| invalid("invalid formal person ID"))?;
            let demographic = map(field(row, "basic_demographic_identity")?)?;
            let name = ["name_zh", "name", "display_name"].into_iter().find_map(|key| lookup(row, key))
                .and_then(Value::as_str).unwrap_or("姓名未记录");
            let basis = lookup(demographic, "basis").and_then(Value::as_str).unwrap_or("opening_birth_year_assumption");
            let alive = field(row, "alive")?.as_bool().ok_or_else(|| invalid("invalid formal person life state"))?;
            let claim = field(row, "claim_id")?.as_str().filter(|id| !id.is_empty())
                .ok_or_else(|| invalid("missing formal person claim"))?;
            let unit = field(row, "population_territory_id")?.as_str().filter(|id| !id.is_empty())
                .ok_or_else(|| invalid("missing formal person population unit"))?;
            let expected = if alive { Some(unit) } else { None };
            if !claims.insert(claim) || self.population.unit_for_person(id) != expected {
                return Err(invalid("formal person claim or population binding conflicts with the save"));
            }
            living += usize::from(alive);
            let identity = Identity::new(integer(field(demographic, "birth_year")?)?, name.to_owned(), basis.to_owned(), alive)
                .map_err(io::Error::other)?;
            if people.insert(id.to_owned(), identity).is_some() {
                return Err(invalid("duplicate identity in formal person overlay"));
            }
            if id == self.player_id {
                let provenance = map(field(row, "provenance")?)?;
                opening = field(provenance, "opening_polity_source_id")?.as_str();
            }
        }
        if living != self.population.named_len() {
            return Err(invalid("population references people absent from the formal overlay"));
        }
        let day = u32::try_from(self.clock.current_day()).map_err(|_| invalid("unsupported formal character date"))?;
        let opening = opening.filter(|id| !id.is_empty()).ok_or_else(|| invalid("missing formal person opening scope"))?;
        let mut restored = formal_character::restore(opening, &self.player_id, people, day, self.character_state().unwrap_or_default())
            .map_err(io::Error::other)?;
        restored.profile.social = self.player_social(snapshot)?;
        Ok(restored.profile)
    }

    fn player_social(&self, snapshot: &[Value]) -> io::Result<SocialFacts> {
        let economic_situation = self.player_balance().map(|balance| {
            let denomination = match balance.denomination {
                CURRENCY => "模拟记账单位",
                "denomination:franc_1900_centime" => "生丁",
                other => other,
            };
            format!("现金 {} · 可用 {} {denomination}", balance.cash, balance.available)
        });
        let personal = map(field(snapshot, "personal_economy")?)?;
        let employment = map(field(personal, "employments")?)?;
        let contract = lookup(snapshot, "economy_native").map(|native| {
            Ok::<_, io::Error>(lookup(map(field(map(native)?, "contracts")?)?, &self.player_id))
        }).transpose()?.flatten();
        let occupation = match contract {
            Some(contract) => lookup(map(contract)?, "job").and_then(Value::as_str).map(str::to_owned),
            None => lookup(employment, &self.player_id).map(|_| "有正式工作记录".to_owned()),
        };
        let organizations = map(field(snapshot, "organization")?)?;
        let mut relationships = Vec::new();
        let mut positions = Vec::new();
        for row in tagged(field(organizations, "organizations")?, "array")? {
            let organization = map(row)?;
            let members = tagged(field(organization, "member_ids")?, "array")?;
            if members.iter().any(|id| id.as_str() == Some(&self.player_id)) {
                if let Some(id) = field(organization, "organization_id")?.as_str() {
                    relationships.push(id.to_owned());
                }
            }
            for row in tagged(field(organization, "appointments")?, "array")? {
                let appointment = map(row)?;
                if field(appointment, "person_id")?.as_str() == Some(&self.player_id) {
                    if let Some(position) = field(appointment, "position_id")?.as_str() {
                        positions.push(position.to_owned());
                    }
                }
            }
        }
        let mut assets = BTreeMap::new();
        if let Some(holdings) = lookup(personal, "holdings") {
            if let Some(person) = lookup(map(holdings)?, &self.player_id) {
                for entry in map(person)? {
                    let id = entry[0].as_str().ok_or_else(|| invalid("invalid personal commodity ID"))?;
                    let stock = map(&entry[1])?;
                    let quantity = integer(field(stock, "quantity_milli")?)?;
                    if quantity > 0 {
                        let name = lookup(stock, "name_zh").and_then(Value::as_str).unwrap_or(id);
                        let unit = lookup(stock, "unit_name_zh").and_then(Value::as_str).unwrap_or_default();
                        assets.insert(id.to_owned(), format!("{name} {} {unit}", quantity as f64 / 1000.0));
                    }
                }
            }
        }
        for (id, quantity) in self.holdings.iter().filter(|(_, quantity)| **quantity > 0) {
            assets.insert(format!("native:{id}"), format!("{id} {quantity}"));
        }
        Ok(SocialFacts {
            occupation, economic_situation, assets: Some(assets.into_values().take(8).collect()),
            relationships: Some(relationships), positions: Some(positions),
            ..SocialFacts::default()
        })
    }

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
        if let Some(value) = lookup(snapshot, "rust_character") {
            if !value.as_str().is_some_and(|state| !state.is_empty() && state.len() <= 32 * 1024 * 1024) {
                return Err(invalid("invalid Rust character extension"));
            }
        }
        if snapshot.iter().any(|pair| {
            !pair[0].as_str().is_some_and(|name| REQUIRED_DOMAINS.contains(&name) || matches!(name,
                "schema_id" | "total_minutes" | "minute_remainder" | "economy_native" | "person_travel" | "rust_character"))
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
        let population = Population::restore(field(snapshot, "population")?)?;
        let native = lookup(snapshot, "economy_native");
        let ledger = Ledger::restore(field(snapshot, "ledger")?, native.is_some())?;
        let holdings = match native {
            Some(economy) => crate::formal_stock::restore(map(economy)?, clock.snapshot().total_minutes, player_id)?,
            None => BTreeMap::new(),
        };
        Ok(Self { player_id: player_id.to_owned(), clock, transfer, population, ledger, holdings })
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
            { publish_windows(temporary,path,false) }
            #[cfg(not(windows))]
            { fs::hard_link(temporary,path) }
        })();
        // Publication already succeeded if the link was created. The temporary name is expendable.
        let _ = fs::remove_file(temporary);
        result
    }
}

fn old_metadata(summary: Option<&Value>) -> Value {
    let summary = summary.unwrap_or(&Value::Null);
    let version = summary["build_label"].as_str().filter(|label| !label.is_empty()).map(|label| {
        serde_json::json!({"build_label": label, "application_version": summary["application_version"].as_str().unwrap_or_default(),
            "build_id": "", "build_sequence": 0})
    });
    let saved_at = summary["saved_at_unix"].as_f64()
        .filter(|time| *time > 0.0 && time.floor() == *time);
    serde_json::json!({"schema_id": "formal_save_metadata_v1", "created_game_version": null, "created_at_unix": null,
        "last_saved_game_version": version, "last_saved_at_unix": saved_at, "original_persistence_format": SOURCE_FORMAT,
        "original_snapshot_schema_id": SNAPSHOT_SCHEMA, "migration_history": []})
}

fn encode_metadata(value: Value) -> Value {
    match value {
        Value::Object(fields) => {
            let entries: Vec<_> = fields.into_iter().map(|(key, value)| {
                Value::Array(vec![Value::String(key), encode_metadata(value)])
            }).collect();
            serde_json::json!(["map", entries])
        }
        Value::Array(values) => {
            let items: Vec<_> = values.into_iter().map(encode_metadata).collect();
            serde_json::json!(["array", items])
        }
        Value::Number(number) if number.is_i64() => serde_json::json!(["int", number.to_string()]),
        Value::Number(number) => legacy_variant::encode_number(number.as_f64().unwrap()),
        other => other,
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

pub(crate) fn typed_map<K: Serialize>(fields: impl IntoIterator<Item = (K, Value)>) -> Value {
    json!(["map", fields.into_iter().collect::<Vec<_>>()])
}

pub(crate) fn typed_int(value: i64) -> Value {
    json!(["int", value.to_string()])
}

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

pub(crate) fn number(value: &Value) -> io::Result<f64> {
    if let Ok(value) = integer(value) {
        return Ok(value as f64);
    }
    let bytes = value.as_array().filter(|row| row.len() == 3 && row[0] == "variant_bytes" && row[1].as_u64() == Some(3))
        .and_then(|row| row[2].as_str()).ok_or_else(|| invalid("missing formal transfer float"))?;
    let number = legacy_variant::decode_number(bytes)?;
    if !number.is_finite() {
        return Err(invalid("nonfinite formal transfer float"));
    }
    Ok(number)
}

pub(crate) fn invalid(message: impl Into<String>) -> io::Error { io::Error::new(io::ErrorKind::InvalidData, message.into()) }

#[cfg(windows)]
fn publish_windows(from:&Path,to:&Path,replace:bool)->io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name="kernel32")]
    unsafe extern "system" {fn MoveFileExW(from:*const u16,to:*const u16,flags:u32)->i32;}
    let source:Vec<_>=from.as_os_str().encode_wide().chain([0]).collect();
    let target:Vec<_>=to.as_os_str().encode_wide().chain([0]).collect();
    let flags = 8 | u32::from(replace);
    if unsafe {MoveFileExW(source.as_ptr(),target.as_ptr(),flags)}==0 {Err(io::Error::last_os_error())}else{Ok(())}
}
