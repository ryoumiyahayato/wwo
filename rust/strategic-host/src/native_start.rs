use crate::{
    desktop_start::{lock_profile, TICK_INTERVAL},
    formal_ui::{OralWorkFeedback, Session, Slot},
    lobby::Lobby,
    state::{Request, State},
    timeline::Date,
};
use serde_json::{json, Value};
use std::{fs::{self, File}, io, path::PathBuf, time::Instant};
use wwo_map_lab::{
    battlefield_terrain::BattlefieldTerrain,
    formal_bootstrap::{freight::FreightState, mode_name, mode_set, InitialWorld, PersonalActivity, WorldBootstrap, OPENINGS},
    formal_clock::{GameClock, TimeControl, MINUTES_PER_DAY},
    formal_save::{native_slot_summary, read_native_slot, write_native_slot},
    land_battle::{self, LandBattleControls},
    military_grid::MilitaryCell,
    transport::operations::Plan,
};

pub struct NativeSession {
    bootstrap: WorldBootstrap,
    world: Option<InitialWorld>,
    pub revision: u64,
    save_dir: PathBuf,
    pub preferences: PathBuf,
    _lock: File,
    slots: Vec<Slot>,
    control: TimeControl,
    next_tick: Instant,
    clock_ack: u64,
    finance_page: usize,
    slot_open: bool,
    slot_error: String,
    lobby_status: String,
    departure: Option<bool>,
    pub exit: bool,
    market: Option<MarketPage>,
    market_serial: u64,
    relations: Option<String>,
    pending_job: Option<String>,
    selected_organization: String,
    property_feedback: String,
    transport: TransportPage,
    work_feedback: String,
    oral_work_feedback: Option<OralWorkFeedback>,
    work_revision: u64,
}

#[derive(Default)]
struct TransportPage {
    destination: String,
    mode: String,
    destination_page: usize,
    passenger_feedback: String,
    lot: Option<u64>,
    lot_page: usize,
    freight_quote: Option<(u64, Plan)>,
    sale_quote: Option<(u64, i64, i64)>,
    freight_feedback: String,
}

struct MarketPage {
    scope: &'static str,
    content: &'static str,
    unit: String,
    good: String,
    group: String,
    window: u64,
    chart: &'static str,
    quote: Option<Quote>,
    result: String,
}

struct Quote {
    token: u64,
    price: i64,
    quantity: i64,
    amount: Result<i64, String>,
}

impl NativeSession {
    pub fn active_world(&self) -> Option<&InitialWorld> {
        self.world.as_ref()
    }

    pub fn active_world_mut(&mut self) -> Option<&mut InitialWorld> {
        self.world.as_mut()
    }

    pub fn start() -> io::Result<Self> {
        let (profile, lock) = lock_profile()?;
        let preferences = profile.join("WWO_R68_Candidate/interface_settings.cfg");
        let save_dir = profile.join("formal-world");
        fs::create_dir_all(&save_dir)?;
        let mut session = Self {
            bootstrap: WorldBootstrap::load()?, world: None, revision: 0, save_dir, preferences, _lock: lock,
            slots: Vec::new(), control: TimeControl::default(), next_tick: Instant::now(),
            clock_ack: 0, finance_page: 0, slot_open: false, slot_error: String::new(),
            lobby_status: String::new(), departure: None, exit: false, market: None, market_serial: 0,
            relations: None, pending_job: None, selected_organization: String::new(), property_feedback: String::new(),
            transport: TransportPage::default(),
            work_feedback: String::new(),
            oral_work_feedback: None,
            work_revision: 0,
        };
        session.refresh_slots();
        Ok(session)
    }

    fn install(&mut self, world: InitialWorld) {
        self.world = Some(world);
        self.revision += 1;
        self.control = TimeControl::default();
        self.finance_page = 0;
        self.departure = None;
        self.slot_open = false;
        self.slot_error.clear();
        self.lobby_status.clear();
        self.market = None;
        self.relations = None;
        self.pending_job = None;
        self.selected_organization.clear();
        self.property_feedback.clear();
        self.transport = TransportPage::default();
        self.work_feedback.clear();
        self.oral_work_feedback = None;
        self.work_revision += 1;
    }

    fn slot_path(&self, slot: u8) -> PathBuf {
        let name = if slot == 0 { "formal_world_1900_auto.json".into() }
            else { format!("formal_world_1900_manual_{slot}.json") };
        self.save_dir.join(name)
    }

    fn refresh_slots(&mut self) {
        self.slots = (0..=4).map(|slot| {
            let name = if slot == 0 { "自动存档".into() } else { format!("手动存档 {slot}") };
            let (empty, can_read, description) = match native_slot_summary(&self.slot_path(slot)) {
                Ok(row) => {
                    let date = GameClock::restore(row.clock).expect("slot header was validated").current_date();
                    let country = &self.bootstrap.sources().polities()[&row.opening].name_zh;
                    let preview = if row.written_access == Some(false) {
                        "已保存".into()
                    } else {
                        format!("{country} · {}-{:02}-{:02} {:02}:{:02}", date.year, date.month, date.day, date.hour, date.minute)
                    };
                    (false, true, preview)
                }
                Err(error) if error.kind() == io::ErrorKind::NotFound => (true, false, "空".into()),
                Err(_) => (false, false, "存档文件不可读取".into()),
            };
            Slot { slot, name, empty, can_read, description }
        }).collect();
    }

    fn load(&mut self, slot: u8) -> io::Result<()> {
        let world = read_native_slot(&self.slot_path(slot), &self.bootstrap)?;
        self.install(world);
        Ok(())
    }

    fn save(&mut self, slot: u8) -> io::Result<()> {
        let world = self.world.as_ref().ok_or_else(|| io::Error::other("世界尚未创建。"))?;
        write_native_slot(&self.slot_path(slot), world)?;
        self.refresh_slots();
        Ok(())
    }

    fn leave(&mut self) {
        self.exit = self.departure.take() == Some(true);
        self.world = None;
        self.slot_error.clear();
    }

    pub fn dispatch(&mut self, request: Request<'_>) -> io::Result<()> {
        match request {
            Request::Lobby { verb, slot, .. } if self.world.is_none() => {
                self.lobby_status.clear();
                let result = match verb {
                    "load" if slot <= 4 => self.load(slot),
                    "slots" => { self.refresh_slots(); Ok(()) },
                    _ => Ok(()),
                };
                if let Err(error) = result { self.lobby_status = format!("无法进入世界：{error}"); }
            }
            Request::NewPlayer { polity, prologue } if self.world.is_none() => {
                match self.bootstrap.create_with_prologue(polity.strip_prefix("state:").unwrap_or(polity), prologue) {
                    Ok(world) => self.install(world),
                    Err(error) => self.lobby_status = format!("无法进入世界：{error}"),
                }
            }
            Request::PersonalActivity { activity } => {
                if let Some(world) = &mut self.world { world.schedule_personal_activity(activity)?; }
            }
            Request::Clock { speed, serial } if self.world.is_some() => {
                if speed == 0 { self.control.paused = true; }
                else { self.control.set_speed(i64::from(speed)); }
                self.clock_ack = serial;
                self.reset_world_tick();
            }
            Request::HostAction { action } if self.world.is_some() => self.host_action(action),
            Request::OpenSlots { .. } => { self.refresh_slots(); self.slot_open = true; self.slot_error.clear(); }
            Request::CloseSlots => { self.slot_open = false; self.slot_error.clear(); }
            Request::FinancePage { page } => self.finance_page = page.min(100_000),
            Request::Consume { id, quantity } => {
                if let Some(world) = &mut self.world {
                    self.property_feedback = match world.consume_purchased_stock(id, quantity) {
                        Ok(_) => "已消费，持有物已扣除。".into(),
                        Err(error) => error.to_string(),
                    };
                }
            }
            Request::Market { verb, id, site, quantity, token, .. } => self.market_action(verb, id, site, quantity, token)?,
            Request::SetMapMode { .. } => self.market = None,
            Request::Relations { verb, id } => self.relations_action(verb, id),
            Request::Transport { verb, id } => self.transport_action(verb, id),
            Request::Training { .. } => return Err(io::Error::other("3D 训练仍需从 R68 对照入口启动。")),
            _ => (),
        }
        Ok(())
    }

    fn host_action(&mut self, action: &str) {
        let update = match action {
            "system:quit" | "system:main_menu" => {
                self.departure = Some(action == "system:quit");
                self.slot_error.clear();
                return;
            }
            "departure:cancel" => { self.departure = None; self.slot_error.clear(); return; }
            "departure:discard" if self.departure.is_some() => { self.leave(); return; }
            "departure:save" if self.departure.is_some() => self.save(0).map(|_| self.leave()),
            _ => {
                let Some((verb, index)) = action.strip_prefix("slot:").and_then(|key| key.split_once(':')) else { return; };
                let Ok(slot) = index.parse::<u8>() else { return; };
                match (verb, slot) {
                    ("save", 1..=4) => self.save(slot),
                    ("load", 0..=4) => self.load(slot),
                    _ => return,
                }
            }
        };
        match update {
            Ok(()) => { self.slot_open = false; self.slot_error.clear(); }
            Err(error) => self.slot_error = error.to_string(),
        }
    }

    pub fn reset_world_tick(&mut self) {
        let battle = self.world.as_ref().is_some_and(InitialWorld::land_battle_in_progress);
        self.next_tick = Instant::now() + if battle { land_battle::TICK_INTERVAL } else { TICK_INTERVAL };
    }

    pub fn tick(
        &mut self, now: Instant, terrain: Option<(MilitaryCell, &BattlefieldTerrain)>, controls: LandBattleControls,
    ) -> io::Result<bool> {
        let Some(world) = self.world.as_mut() else { return Ok(false); };
        if self.departure.is_some() || self.slot_open || now < self.next_tick { return Ok(false); }
        let Some(minutes) = self.control.tick() else { return Ok(false); };
        let battle = world.land_battle_in_progress();
        let minutes = if battle { land_battle::WORLD_MINUTES_PER_STEP * self.control.speed } else { minutes };
        let was_traveling = world.passenger_in_transit();
        let previous_day = world.clock().current_day();
        let advanced = world.advance_live_minutes(minutes, terrain, controls);
        self.next_tick = if battle && world.land_battle_in_progress() {
            (self.next_tick + land_battle::TICK_INTERVAL).max(now)
        } else {
            now + TICK_INTERVAL
        };
        if let Err(error) = advanced {
            self.control.paused = true;
            return Err(error);
        }
        if let Some(place) = world.player_current_place().filter(|_| was_traveling) {
            self.work_feedback = format!("已抵达{}。", place_label(world, place));
        }
        if previous_day != world.clock().current_day() || was_traveling != world.passenger_in_transit() {
            self.work_revision += 1;
        }
        Ok(true)
    }

    fn relations_action(&mut self, verb: &str, id: &str) {
        let Some(world) = &mut self.world else { return; };
        self.work_revision += 1;
        let work_panel = self.relations.as_deref() == Some("work");
        let oral_panel = self.relations.is_none();
        match verb {
            "open" => { self.relations = Some("relations".into()); self.pending_job = None; }
            "close" => { self.relations = None; self.pending_job = None; self.selected_organization.clear(); }
            "drawer" if matches!(id, "relations" | "work") => {
                self.relations = Some(id.to_owned());
                self.pending_job = None;
            }
            "select" if world.employment().is_some_and(|(_, _, org)| org == id) => self.selected_organization = id.into(),
            "back" => self.selected_organization.clear(),
            "work_action" if work_panel || oral_panel => {
                if let Some(job) = id.strip_prefix("person:job_request:") {
                    let available = if oral_panel {
                        world.oral_work_offer().is_some_and(|(row, spots)| row.id == job && spots > 0)
                    } else {
                        world.employment().is_none() && world.jobs().any(|(row, spots)| row.id == job && spots > 0)
                    };
                    if available {
                        self.pending_job = Some(job.into());
                        if oral_panel { self.oral_work_feedback = None; }
                        else { self.work_feedback.clear(); }
                    } else if oral_panel {
                        self.oral_work_feedback = Some(OralWorkFeedback::Unavailable);
                    } else {
                        self.work_feedback = "该岗位当前无法申请。".into();
                    }
                } else if oral_panel && id == "native:work" && world.oral_work_employment().is_some() {
                    let booked = world.can_book_work() && perform_work_action(world, id).is_ok();
                    self.oral_work_feedback = (!booked).then_some(OralWorkFeedback::Unavailable);
                } else if work_panel {
                    self.work_feedback = match perform_work_action(world, id) {
                        Ok(message) => message,
                        Err(error) => error.to_string(),
                    };
                }
            }
            "work_confirm" if work_panel || oral_panel => {
                if let Some(job) = self.pending_job.take() {
                    if oral_panel {
                        let available = world.oral_work_offer().is_some_and(|(row, spots)| row.id == job && spots > 0);
                        self.oral_work_feedback = Some(if available && world.apply_for_work(&job).is_ok() {
                            OralWorkFeedback::Signed
                        } else {
                            OralWorkFeedback::Unavailable
                        });
                    } else {
                        self.work_feedback = match world.apply_for_work(&job) {
                            Ok(()) => "劳动合同已签订。".into(),
                            Err(error) => error.to_string(),
                        };
                    }
                }
            }
            "work_cancel" => self.pending_job = None,
            _ => (),
        }
    }

    fn transport_action(&mut self, verb: &str, id: &str) {
        let Some(world) = &mut self.world else { return };
        let page = &mut self.transport;
        let result = match verb {
            "city" | "destination" if world.transport_connections(id).is_some() => {
                page.destination = id.into();
                page.freight_quote = None;
                page.passenger_feedback.clear();
                world.clear_transport_preview();
                if verb == "city" {
                    page.passenger_feedback = world.preview_travel(id, mode_set(&page.mode))
                        .err().map_or_else(String::new, |error| error.to_string());
                }
                return;
            }
            "cities_prev" => { page.destination_page = page.destination_page.saturating_sub(1); return; }
            "cities_next" => {
                if (page.destination_page + 1) * crate::transport_ui::PAGE_SIZE < world.transport_destinations().count() {
                    page.destination_page += 1;
                }
                return;
            }
            "mode" => {
                page.mode = id.into(); page.freight_quote = None; page.passenger_feedback.clear();
                world.clear_transport_preview(); return;
            }
            "preview" => world.preview_travel(&page.destination, mode_set(&page.mode)).map(|_| ()),
            "depart" => world.depart_player(),
            "stop" => world.stop_player(),
            "commute" => world.set_commute(world.commute_base().is_none()),
            "lot" => {
                page.lot = id.parse().ok(); page.freight_quote = None; page.sale_quote = None;
                let shipment = page.lot.and_then(|id| world.freight_lots().find(|lot| lot.id == id))
                    .and_then(|lot| match &lot.state {
                        FreightState::InTransit { reservation_id, .. } => Some(*reservation_id),
                        _ => None,
                    });
                world.select_freight_route(shipment);
                page.freight_feedback.clear(); return;
            }
            "lots_prev" => { page.lot_page = page.lot_page.saturating_sub(1); return; }
            "lots_next" => {
                if (page.lot_page + 1) * crate::transport_ui::LOT_PAGE_SIZE < world.freight_lots().count() {
                    page.lot_page += 1;
                }
                return;
            }
            "freight_quote" | "freight_dispatch" | "sale_quote" | "sale_confirm" => {
                page.freight_feedback = match page.act_on_freight(world, verb) {
                    Ok(text) => text, Err(error) => error.to_string(),
                };
                return;
            }
            _ => return,
        };
        page.passenger_feedback = result.err().map_or_else(String::new, |error| error.to_string());
    }

    fn market_action(&mut self, verb: &str, id: &str, site: &str, quantity: u64, token: u64) -> io::Result<()> {
        let Some(world) = &mut self.world else { return Ok(()); };
        if verb == "close" { self.market = None; return Ok(()); }
        if verb == "open" {
            let unit = id.strip_prefix("state:").filter(|unit| world.macro_economy().markets().contains_key(*unit))
                .unwrap_or_else(|| world.player_market_unit());
            self.market = Some(MarketPage {
                scope: "domestic", content: "quotes", unit: unit.into(), good: String::new(),
                group: "all".into(), window: 7, chart: "price", quote: None, result: String::new(),
            });
        }
        let Some(page) = self.market.as_mut() else { return Ok(()); };
        let market = &world.macro_economy().markets()[&page.unit];
        match verb {
            "scope" => {
                page.scope = if id == "international" { "international" } else { "domestic" };
                page.quote = None;
                page.content = if page.scope == "international" { "transport" } else { "quotes" };
            }
            "view" => {
                page.content = match id { "goods" => "goods", "transport" => "transport", "activity" => "activity", "freight" => "freight", _ => "quotes" };
                page.quote = None;
            }
            "country" => {
                if let Some(unit) = id.strip_prefix("state:").filter(|unit| world.macro_economy().markets().contains_key(*unit)) {
                    page.unit = unit.into();
                    page.quote = None;
                    page.good.clear();
                    page.content = "quotes";
                    page.scope = "domestic";
                }
            }
            "region" => page.result = "地区商户和个人配送仍在 R68。".into(),
            "good" if market.commodities.contains_key(id) => {
                page.good = id.into();
                page.content = "good";
                page.quote = None;
            }
            "goods_group" => page.group = id.into(),
            "chart" => page.chart = if id == "supply" { "supply" } else { "price" },
            "window" => page.window = id.parse().ok().filter(|days| [7, 30, 90].contains(days)).unwrap_or(7),
            "offer" | "quantity" => {
                let is_offer = verb == "offer";
                if is_offer && (id != page.good || site != market.id) { return Ok(()); }
                if !is_offer && page.quote.is_none() { return Ok(()); }
                let Some(row) = market.commodities.get(&page.good) else { return Ok(()); };
                let quantity = if is_offer { 1000 } else { i64::try_from(quantity).unwrap_or(0) };
                let amount = if world.market_unit_for_person(&world.player().id) == Some(page.unit.as_str()) {
                    world.macro_economy().quote(&page.unit, &page.good, quantity).map_err(|error| error.to_string())
                        .and_then(|amount| {
                            world.balance().filter(|cash| cash.available >= amount).map(|_| amount)
                                .ok_or_else(|| "可用现金不足。".into())
                        })
                } else { Err("人物当前无法访问该市场。".into()) };
                self.market_serial += 1;
                page.quote = Some(Quote { token: self.market_serial, price: row.price_centimes, quantity, amount });
                page.result.clear();
            }
            "quote_back" => page.quote = None,
            "buy" => {
                if !page.quote.as_ref().is_some_and(|quote| quote.token == token && quote.amount.is_ok()) {
                    return Ok(());
                }
                let quote = page.quote.take().unwrap();
                let id = market.id.clone();
                page.result = match world.buy_quoted_stock(&id, &page.good, quote.quantity, quote.price) {
                    Ok(amount) => format!("现场交付。已支付 {amount}，货物已入个人持有物。"),
                    Err(error) => format!("下单失败：{error}"),
                };
            }
            "freight_buy" => {
                if world.market_unit_for_person(&world.player().id) != Some(page.unit.as_str())
                    || !page.quote.as_ref().is_some_and(|quote| quote.token == token && quote.amount.is_ok())
                { return Ok(()); }
                let quote = page.quote.take().unwrap();
                match world.buy_freight(&page.good, quote.quantity, quote.price) {
                    Ok(id) => {
                        page.content = "freight";
                        self.transport.lot = Some(id);
                        self.transport.lot_page = 0;
                        self.transport.freight_quote = None;
                        self.transport.sale_quote = None;
                        world.select_freight_route(None);
                        self.transport.freight_feedback = "已从当地市场采购。货批已交付给你，可安排运输。".into();
                    }
                    Err(error) => page.result = format!("采购失败：{error}"),
                }
            }
            _ => (),
        }
        Ok(())
    }

    pub fn update_view(&self, state: &mut State) -> io::Result<()> {
        let Some(world) = self.world.as_ref() else {
            state.date = Date::new(1900, 1, 1);
            state.session = None;
            let choices: Vec<_> = OPENINGS.iter().map(|&(id, place)| {
                let label = &self.bootstrap.sources().polities()[id].name_zh;
                let location = &self.bootstrap.sources().places()[&format!("place:{place}")].name;
                json!({"id":format!("state:{id}"),"label":label,"place":location,
                    "language":self.bootstrap.opening_language(id),
                    "cash":self.bootstrap.opening_cash(id, wwo_character_core::Family::Ordinary)})
            }).collect();
            state.lobby = Some(serde_json::from_value::<Lobby>(json!({
                "ready":true,"selection_ready":true,"busy":false,"native":true,"status":self.lobby_status,
                "choices":choices,"slots":self.slots
            }))?);
            return Ok(());
        };
        let clock = world.clock();
        let date = clock.current_date();
        let player = world.player();
        let place = world.player_current_place();
        let coordinates = place.and_then(|place| world.sources().places().get(place)?.lon_lat);
        let country = &world.sources().polities()[&player.opening_source_id].name_zh;
        let cash = world.balance().ok_or_else(|| io::Error::other("正式人物账号缺失。"))?;
        let mut receipts = world.ledger().personal_receipts(&player.id).skip(self.finance_page * 6);
        let rows: Vec<_> = receipts.by_ref().take(6).map(|receipt| {
            let kind = match receipt.kind {
                "opening_cash" => "开局现金", "purchase" => "购买", "wage" => "工资",
                "transport_fare" => "运输费用", "transport_refund" => "运输退款", "freight_sale" => "出售货批",
                kind => kind
            };
            json!({"description":format!("{} · {kind}", minute_text(receipt.minute)),
                   "amount":format!("{}{}", if receipt.incoming { "+" } else { "−" },receipt.amount)})
        }).collect();
        let property: Vec<_> = world.goods_held().filter_map(|(good, quantity, consumable)| {
            let (label, _, unit) = world.macro_economy().commodity_info(good)?;
            Some(json!({"id":good,"label":label,"quantity":quantity,"unit":unit,"scale":1000,
                        "consume_quantity":if consumable {Some(quantity.min(1000))} else {None}}))
        }).collect();
        let mut character = serde_json::to_value(world.character_for_player())?;
        character["settled_day"] = json!(clock.current_day());
        let oral_work = world.oral_work_employment().map(|(job, booked)| {
            (job, "native:work".to_owned(), json!({
                "kind":"contract", "booked":booked, "can_book":world.can_book_work(),
                "present":place == Some(job.place.as_str()),
            }))
        }).or_else(|| world.oral_work_offer().map(|(job, vacancies)| {
            (job, format!("person:job_request:{}",job.id), json!({
                "kind":"offer", "vacancies":vacancies,
                "confirming":self.relations.is_none() && self.pending_job.as_deref() == Some(job.id.as_str()),
            }))
        }));
        let oral_work = oral_work.map(|(job, action, state)| json!({
            "employer":employer_label(&job.employer),
            "employer_english":match job.employer.as_str() {
                "firm:opening_paris_workshop" => "Paris workshop",
                "firm:opening_paris_bakery" => "Paris bakery",
                id => employer_label(id),
            },
            "hours":job.hours,"wage_per_hour":job.wage_per_hour,"wage_delay":job.wage_delay,
            "action":action,"revision":self.work_revision,"state":state,
        }));
        let activities = world.opening_language().map(|language| json!({
            "language": language, "scheduled": world.scheduled_activity(),
            "lesson":world.can_schedule_personal_activity(PersonalActivity::Lesson),
            "rest":world.can_schedule_personal_activity(PersonalActivity::Rest),
            "read_notice":world.can_schedule_personal_activity(PersonalActivity::ReadNotice),
            "oral_notice":world.last_read_notice().map(|_| format!("课堂教师口述 · {}", world.lesson_notice())),
            "oral_work":oral_work,
            "oral_work_feedback":self.oral_work_feedback,
        }));
        let messages = world.opening_language().map(|_| json!([{
            "source":"本地识字课堂", "received_at":"", "text":world.lesson_notice(), "action":""
        }])).unwrap_or_else(|| json!([]));
        let session: Session = serde_json::from_value(json!({
            "player":player.id,"polity":player.polity_id,
            "coordinates":coordinates.map(Vec::from).unwrap_or_default(),"place":place.unwrap_or_default(),
            "clock_ack":self.clock_ack,"hour":date.hour,"minute":date.minute,"paused":self.control.paused,
            "speed":self.control.speed,"total_minutes":clock.snapshot().total_minutes,
            "finance":{"summary":format!("现金 {} · 可用 {} · 预留 {}", cash.cash, cash.available, cash.reserved),
                       "page":self.finance_page,"more":receipts.next().is_some(),"rows":rows},
            "technology":{"country":country,"public_country":"","foundation":[],
                          "public_foundation":[],"project_active":false,"milestones":[]},
            "messages":messages, "written_access":world.can_read_opening_language(), "activities":activities,
            "slots":self.slots,"slot_open":self.slot_open,"slot_error":self.slot_error,
            "property":property,"property_feedback":self.property_feedback,
            "market":self.market.as_ref().map(|page| page.view(world)),
            "relations":self.relations.as_ref().map(|drawer| self.work_view(world, drawer)),
            "transport":self.transport.view(world),
            "character":character,
            "departure":self.departure.map_or("", |quit| if quit {"quit"} else {"main_menu"})
        }))?;
        state.date = Date::new(i32::try_from(date.year).map_err(io::Error::other)?, date.month, date.day);
        state.lobby = None;
        state.session = Some(session);
        Ok(())
    }

    pub fn update_after_tick(&self, state: &mut State) -> io::Result<()> {
        let world = self.world.as_ref().unwrap();
        let clock = world.clock();
        if let Some(view) = state.session.as_mut() {
            let transport = serde_json::from_value(self.transport.view(world))?;
            if view.total_minutes / MINUTES_PER_DAY as u64 == clock.current_day() as u64
                && view.place == world.player_current_place().unwrap_or_default()
                && view.transport == Some(transport) {
                let date = clock.current_date();
                view.hour = date.hour as u32;
                view.minute = date.minute as u32;
                view.total_minutes = clock.snapshot().total_minutes as u64;
                if let Some(activities) = &mut view.activities {
                    activities.lesson = world.can_schedule_personal_activity(PersonalActivity::Lesson);
                    activities.rest = world.can_schedule_personal_activity(PersonalActivity::Rest);
                    activities.read_notice = world.can_schedule_personal_activity(PersonalActivity::ReadNotice);
                    activities.refresh_oral_work_booking(|| world.can_book_work());
                }
                if let Some(market) = view.market.as_mut() {
                    market.minute = view.total_minutes;
                }
                if let Some(relations) = view.relations.as_mut().filter(|relations| relations.drawer == "work") {
                    *relations = serde_json::from_value(self.work_view(world, "work"))?;
                }
                return Ok(());
            }
        }
        self.update_view(state)
    }

    fn work_view(&self, world: &InitialWorld, drawer: &str) -> Value {
        let mut work = Vec::new();
        let mut organizations = Vec::new();
        let current = world.player_current_place();
        let home = place_label(world, world.player_home());
        let location = if let Some(plan) = world.travel_plan() {
            format!("在途 · {} → {} · 预计 {} 到达", place_label(world, &plan.route().from),
                place_label(world, &plan.route().to), minute_text(plan.arrival_minute()))
        } else {
            current.map_or_else(|| "无活动地点".into(), |place| format!("当前 · {}", place_label(world, place)))
        };
        work.push(json!({"label":"所在地与常住地", "details":[location, format!("常住 · {home}")],
            "actions":if world.can_move_player_home() {
                vec![work_action("在此登记迁居", "native:move_home", true)]
            } else { Vec::new() }}));

        if let Some(livelihood) = world.person_livelihood(&world.player().id) {
            let available = livelihood.budget.map_or_else(|| "—".into(), |budget| budget.available.to_string());
            let today = format!("可用现金 {available} · 主食持有 {} 千克 · 今日已食用 {} 千克",
                livelihood.food_held_milli, livelihood.food_received_today_milli);
            let last = livelihood.last_day.map_or_else(|| "暂无已结算日".into(), |day| {
                let outcome = day.food_shortfall.map_or("需求已满足", |reason| reason.label());
                format!("上次结算 {}/{} 千克 · {outcome}", day.food_received_milli, day.food_required_milli)
            });
            work.push(json!({"label":"每日生计", "details":[today,last]}));
        }

        if let Some((_, household)) = world.household_of(&world.player().id) {
            let detail = format!("{} · {} 人 · 同住时共享余粮", place_label(world, &household.home), household.members.len());
            work.push(json!({"label":"共同住户", "details":[detail],
                "actions":[work_action("退出住户", "native:leave_household", true)]}));
        }

        if let Some(offer) = world.local_bread_offer() {
            let affordable = world.balance().is_some_and(|cash| cash.available >= offer.price);
            let detail = format!("{} · 可交付 {} 千克 · {} / 千克", employer_label(offer.firm), offer.quantity, offer.price);
            let label = if affordable { "买 1 千克" } else { "现金不足" };
            work.push(json!({"label":"本地面包", "details":[detail],
                "actions":[work_action(label, &format!("native:buy_bread|{}|{}", offer.site, offer.price), affordable)]}));
        } else if current.is_some() {
            work.push(json!({"label":"本地面包", "details":["当前没有可交付的本地报价"]}));
        }

        if let Some((job, booked, organization)) = world.employment() {
            organizations.push(json!({"id":organization,"label":employer_label(&job.employer),"role":"雇员",
                "kind":"劳动关系","place":job.place,"basis":"开局配置"}));
            let can_book = world.can_book_work();
            let status = if booked { "已登记本日工作" }
                else if current != Some(job.place.as_str()) { "劳动合同有效 · 当前不在工作地点" }
                else if can_book { "可登记本日工作" }
                else { "劳动合同有效 · 本日无法登记" };
            work.push(json!({"label":employer_label(&job.employer),
                "details":[format!("每班 {} 小时 · 时薪 {} · {} 日后发薪",job.hours,job.wage_per_hour,job.wage_delay),
                           status],
                "actions":[work_action("登记工作", "native:work", can_book),
                           work_action("离职", "native:leave_employment", !booked)]}));
        } else {
            let mut jobs = world.jobs().peekable();
            if current.is_some() && jobs.peek().is_none() {
                work.push(json!({"label":"工作", "details":["当前地点没有可申请的已知岗位"]}));
            }
            for (job, vacancies) in jobs {
                work.push(json!({"label":employer_label(&job.employer),
                    "details":[format!("空缺 {vacancies} · 每班 {} 小时 · 时薪 {}",job.hours,job.wage_per_hour)],
                    "actions":[work_action("申请", &format!("person:job_request:{}",job.id), vacancies > 0)]}));
            }
        }

        let confirmation = self.pending_job.as_ref().map(|_| json!({"title":"确认就业","body":"接受该岗位的工时和工资条件。"}));
        json!({"selected":self.selected_organization,"rows":organizations,"drawer":drawer,"has_work":true,
            "work_title":"生计、工作与旅行","work_revision":self.work_revision,"work_feedback":self.work_feedback,
            "work":work,"confirmation":confirmation})
    }
}

fn work_action(label: &str, id: &str, enabled: bool) -> Value {
    json!({"label":label,"id":id,"enabled":enabled})
}

fn perform_work_action(world: &mut InitialWorld, action: &str) -> io::Result<String> {
    match action {
        "native:work" => { world.book_work()?; Ok("已登记今日工作。".into()) }
        "native:leave_employment" => { world.leave_employment()?; Ok("已离职。".into()) }
        "native:move_home" => { world.move_player_home()?; Ok("迁居已登记。".into()) }
        "native:leave_household" => {
            if !world.leave_household(&world.player().id.clone()) {
                return Err(io::Error::other("当前没有共同住户。"));
            }
            Ok("已退出共同住户。".into())
        }
        _ => match action.split_once('|').and_then(|(kind, rest)| {
            let (subject, detail) = rest.split_once('|')?;
            Some((kind, subject, detail))
        }) {
            Some(("native:buy_bread", site, price)) => {
                let price = price.parse::<i64>().ok();
                if !world.local_bread_offer().is_some_and(|offer| offer.site == site && Some(offer.price) == price) {
                    return Err(io::Error::other("当地报价已变动，请查看当前报价。"));
                }
                let paid = world.buy_local_bread(1)?;
                Ok(format!("已支付 {paid}，面包已入持有物。"))
            }
            _ => Err(io::Error::other("无法识别该操作。")),
        },
    }
}

fn place_label<'a>(world: &'a InitialWorld, place: &'a str) -> &'a str {
    world.sources().places().get(place).map_or(place, |entry| entry.name.as_str())
}

fn employer_label(id: &str) -> &str {
    match id {
        "firm:opening_paris_workshop" => "巴黎工坊",
        "firm:opening_paris_bakery" => "巴黎面包坊",
        _ => id,
    }
}

fn minute_text(minute: i64) -> String {
    let mut clock = GameClock::default();
    let _ = clock.advance_minutes(minute);
    let date = clock.current_date();
    format!("{}-{:02}-{:02} {:02}:{:02}", date.year,date.month,date.day,date.hour,date.minute)
}

impl TransportPage {
    fn act_on_freight(&mut self, world: &mut InitialWorld, verb: &str) -> io::Result<String> {
        let id = self.lot.ok_or_else(|| io::Error::other("请选择货批。"))?;
        match verb {
            "freight_quote" => {
                self.freight_quote = None;
                let plan = world.quote_freight(id, &self.destination, mode_set(&self.mode))?;
                world.show_freight_route(&plan);
                self.freight_quote = Some((id, plan));
                Ok(String::new())
            }
            "freight_dispatch" => {
                let (_, plan) = self.freight_quote.take().filter(|(lot, _)| *lot == id)
                    .ok_or_else(|| io::Error::other("请查询运输报价。"))?;
                world.select_freight_route(None);
                let reservation = world.dispatch_quoted_freight(id, plan)?;
                world.select_freight_route(Some(reservation));
                Ok("运费已支付。货批保留原货权，按预约分段运输。".into())
            }
            "sale_quote" => {
                self.sale_quote = None;
                let (unit, total) = world.freight_sale_quote(id)?;
                self.sale_quote = Some((id, unit, total));
                Ok(format!("交割地市场从实收账户付款。全批收入 {total} 生丁。"))
            }
            "sale_confirm" => {
                let (_, unit, _) = self.sale_quote.take().filter(|(lot, _, _)| *lot == id)
                    .ok_or_else(|| io::Error::other("请获取交割地市场报价。"))?;
                let net = world.sell_freight(id, unit)?;
                Ok(format!("已委托出售，货款到账。净收益 {net:+} 生丁。"))
            }
            _ => Err(io::Error::other("未知货运操作。")),
        }
    }

    fn view(&self, world: &InitialWorld) -> Value {
        let now = world.clock().snapshot().total_minutes;
        let places: Vec<_> = world.transport_destinations().collect();
        let page_size = crate::transport_ui::PAGE_SIZE;
        let mut ordered: Vec<_> = ["place:paris","place:rouen","place:le_havre","place:london","place:lille","place:brussels"]
            .into_iter().filter(|id| places.contains(id)).collect();
        ordered.extend(places.iter().copied().filter(|id|
            !matches!(*id, "place:paris"|"place:rouen"|"place:le_havre"|"place:london"|"place:lille"|"place:brussels")));
        let destinations: Vec<_> = ordered.into_iter().skip(self.destination_page*page_size).take(page_size)
            .map(|id| json!({"id":id,"label":world.place_name(id)})).collect();
        let preview = world.travel_preview().filter(|plan| plan.departure_minute() >= now);
        let mut passenger_lines = Vec::new();
        if let Some(plan) = world.travel_plan().or(preview) {
            let status = if world.passenger_moving() { "在途" } else if world.passenger_in_transit() { "等候发车或换乘" } else { "报价" };
            passenger_lines.push(format!("{status} · {}", world.place_name(&plan.route().to)));
            passenger_lines.extend(describe_plan(world, plan));
        }
        let commute = world.commute_base().zip(world.commute_departure())
            .map(|(base, at)| format!("通勤起点 {} · {} 发车", world.place_name(base), minute_text(at)))
            .unwrap_or_else(|| "未启用通勤".into());
        let lot_page_size = crate::transport_ui::LOT_PAGE_SIZE;
        let lots: Vec<_> = world.freight_lots().rev().skip(self.lot_page*lot_page_size).take(lot_page_size).map(|lot| {
            let name = world.macro_economy().commodity_info(&lot.good).map_or(lot.good.as_str(), |term| term.0);
            let status = match lot.state {
                FreightState::Purchased => "待发运", FreightState::InTransit {..} => "在途",
                FreightState::Interrupted {..} => "中断", FreightState::Delivered {..} => "已交割",
                FreightState::Sold {..} => "已出售",
            };
            json!({"id":lot.id,"label":format!("#{} · {name} · {status}",lot.id),"selected":self.lot==Some(lot.id)})
        }).collect();
        let mut freight_lines = Vec::new();
        let mut freight_actions = Vec::new();
        if let Some(lot) = self.lot.and_then(|id| world.freight_lots().find(|lot| lot.id == id)) {
            freight_lines.push(format!("数量 {:.3} · 货款 {} · 已付运费 {}", lot.quantity_milli as f64/1000., lot.purchase_centimes, lot.freight_centimes));
            match &lot.state {
                FreightState::InTransit {reservation_id, destination} => {
                    let (at, plan) = world.freight_progress(*reservation_id);
                    freight_lines.push(format!("上一站 {} · 目的地 {}", world.place_name(at.unwrap_or(&lot.origin)), world.place_name(destination)));
                    if let Some(plan) = plan { freight_lines.extend(describe_plan(world, plan)); }
                }
                FreightState::Sold { destination, revenue_centimes, net_centimes } => {
                    freight_lines.push(format!("{} · 售价合计 {revenue_centimes} · 净收益 {net_centimes:+}",world.place_name(destination)));
                }
                state => {
                    let (place, delivery) = match state {
                        FreightState::Purchased => (lot.origin.as_str(), false),
                        FreightState::Interrupted {place} => (place.as_str(), false),
                        FreightState::Delivered {destination} => (destination.as_str(), true),
                        _ => unreachable!(),
                    };
                    freight_lines.push(format!("货批存放于 {}", world.place_name(place)));
                    if !self.destination.is_empty() && self.destination != place {
                        freight_actions.push(json!({"id":"freight_quote","label":"查询运费"}));
                    }
                    if let Some((_, plan)) = self.freight_quote.as_ref().filter(|(id, plan)| *id == lot.id && plan.departure_minute() >= now) {
                        freight_lines.extend(describe_plan(world, plan));
                        freight_actions.push(json!({"id":"freight_dispatch","label":"确认发运"}));
                    }
                    if delivery {
                        freight_actions.push(json!({"id":"sale_quote","label":"委托销售报价"}));
                        if let Some((_, _, revenue)) = self.sale_quote.filter(|(id, _, _)| *id == lot.id) {
                            freight_lines.push(format!("报价收入 {revenue} · 预计净收益 {:+}", revenue-lot.purchase_centimes-lot.freight_centimes));
                            freight_actions.push(json!({"id":"sale_confirm","label":"确认出售"}));
                        }
                    }
                }
            }
        }
        json!({
            "destinations":destinations, "destination_page":self.destination_page, "destination":self.destination,
            "destinations_next":(self.destination_page+1)*page_size < places.len(),
            "destination_is_current":self.destination == world.last_station(),
            "location":world.place_name(world.last_station()), "moving":world.passenger_moving(),
            "residence":world.place_name(world.residence()),
            "workplace":world.employment().map_or("无合同", |(job, _, _)| world.place_name(&job.place)),
            "commute":commute, "mode":if self.mode.is_empty() {"all"}else{&self.mode}, "active":world.passenger_in_transit(),
            "passenger_lines":passenger_lines, "passenger_notice":if self.passenger_feedback.is_empty() {world.travel_notice()}else{&self.passenger_feedback},
            "travel_confirm":preview.is_some() && !world.passenger_in_transit(),
            "lots":lots, "lot_page":self.lot_page, "lots_next":(self.lot_page+1)*lot_page_size < world.freight_lots().count(),
            "freight_lines":freight_lines, "freight_notice":self.freight_feedback,
            "freight_actions":freight_actions
        })
    }
}

fn describe_plan(world: &InitialWorld, plan: &Plan) -> Vec<String> {
    let route = plan.route();
    let mut lines = vec![
        format!("{} 生丁 · {} 分钟（含等候）· 风险 {} 点 · 名义运力 {}",
            plan.fare_centimes(), plan.arrival_minute()-plan.departure_minute(), route.risk_points,
            route.capacity_units.unwrap_or(0)),
        format!("原型数据 · 预计 {} 抵达", minute_text(plan.arrival_minute())),
    ];
    if plan.first_departure_minute() > plan.departure_minute() {
        lines.push(format!("预计 {} 发车", minute_text(plan.first_departure_minute())));
    }
    if world.sources().population_unit_at(&route.from) != world.sources().population_unit_at(&route.to) {
        lines.push("跨境手续待接入。".into());
    }
    for leg in &route.legs {
        lines.push(format!("{} · {} → {}",mode_name(leg.mode),world.place_name(&leg.from),world.place_name(&leg.to)));
    }
    lines
}

impl MarketPage {
    fn view(&self, world: &InitialWorld) -> Value {
        let economy = world.macro_economy();
        let market = &economy.markets()[&self.unit];
        let label = |unit: &str| world.sources().polities().get(unit).map(|polity| polity.name_zh.clone()).unwrap_or_else(|| unit.into());
        let country = label(&self.unit);
        let minute = world.clock().snapshot().total_minutes;
        let mut book = Vec::new();
        let mut catalog = Vec::new();
        for (id, goods) in &market.commodities {
            let (name, category, unit) = economy.commodity_info(id).unwrap();
            let item = json!({"id":id,"label":name,"price":goods.price_centimes.to_string(),
                              "supply":format!("{:.3}",goods.inventory),"quantity":format!("{:.3} {unit}",goods.inventory)});
            if economy.purchasable(id) && goods.inventory > 0.0 { book.push(item.clone()); }
            let matches_group = match self.group.as_str() {
                "谷物、薯类与干豆" => category == "agricultural_food",
                "工业制品" => category.starts_with("industrial"),
                "其他初级产品" => category != "agricultural_food" && !category.starts_with("industrial"),
                _ => true,
            };
            if matches_group { catalog.push(item); }
        }
        let info = economy.commodity_info(&self.good);
        let local = world.market_unit_for_person(&world.player().id) == Some(self.unit.as_str());
        let place = world.player_current_place().filter(|_| local).unwrap_or_default();
        let offers = market.commodities.get(&self.good).filter(|_| economy.purchasable(&self.good)).map(|row| {
            let (_, _, unit) = info.unwrap();
            json!([{"good":self.good,"commodity":self.good,"site":market.id,"place":place,
                    "seller":"统计市场","location":country,"price":row.price_centimes.to_string(),
                    "currency":"模拟货币","unit":unit,"available":(row.inventory*1000.).floor() as i64}])
        }).unwrap_or_else(|| json!([]));
        let quote = self.quote.as_ref().map(|row| json!({
            "token":row.token,"accepted":row.amount.is_ok(),"commodity":self.good,"site":market.id,
            "name":info.map_or("", |(name, _, _)| name),"quantity":row.quantity,"scale":1000,"quoted_quantity":row.quantity,
            "amount":row.amount.as_ref().ok(),"goods_amount":row.amount.as_ref().ok(),"freight_amount":0,
            "currency":"formal_simulation_minor_v1","currency_name":"模拟货币",
            "error":row.amount.as_ref().err().map(String::as_str).unwrap_or(""),"onsite":true
        }));
        let countries: Vec<_> = economy.markets().keys().map(|unit| json!({"id":format!("state:{unit}"),"label":label(unit)})).collect();
        let logistics: Vec<_> = economy.last_arrivals().iter().map(|shipment| (shipment, true))
            .chain(economy.shipments().iter().map(|shipment| (shipment, false))).filter(|(shipment, _)| {
            self.scope == "international" || shipment.origin == self.unit || shipment.destination == self.unit
        }).map(|(shipment, arrived)| json!({
            "name":format!("{} → {} · {}",label(&shipment.origin),label(&shipment.destination),
                economy.commodity_info(&shipment.commodity).map_or(shipment.commodity.as_str(), |(name,_,_)| name)),
            "details":format!("{:.3} · {} {}",shipment.units,if arrived {"已交付"} else {"预计到达"},
                              minute_text(shipment.arrival_hour * 60))
        })).collect();
        let chart = market.commodities.get(&self.good).map(|row| json!([{"minute":minute,
            "value":if self.chart == "supply" {row.inventory} else {row.price_centimes as f64}}])).unwrap_or_else(|| json!([]));
        json!({"scope":self.scope,"content":self.content,"polity":format!("state:{}",self.unit),"country":country,
            "market_id":market.id,"region":"","good":self.good,"site":market.id,"window_days":self.window,
            "chart_kind":self.chart,"minute":minute,"book":book,"offers":offers,"places":[],"countries":countries,
            "quote":quote,"orders":[],"logistics":logistics,"chart":chart,"result":self.result,"collections":[],"focus":null,
            "catalog":catalog,"goods_group":self.group,"good_label":info.map_or("", |(name,_,_)| name)})
    }
}
