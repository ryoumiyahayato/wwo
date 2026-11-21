use crate::{
    desktop_start::{lock_profile, TICK_INTERVAL},
    formal_ui::{Session, Slot},
    lobby::Lobby,
    state::{Request, State},
    timeline::Date,
};
use serde_json::{json, Value};
use std::{collections::BTreeMap, fs::{self, File}, io, path::PathBuf, time::Instant};
use wwo_map_lab::{
    formal_bootstrap::{InitialWorld, PersonalActivity, WorldBootstrap, OPENINGS},
    formal_clock::{GameClock, TimeControl, MINUTES_PER_DAY},
    formal_save::{native_slot_summary, read_native_slot, write_native_slot},
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
                self.next_tick = Instant::now() + TICK_INTERVAL;
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
            Request::Relations { verb, id } => self.relations_action(verb, id)?,
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

    pub fn tick(&mut self, now: Instant) -> io::Result<bool> {
        let Some(world) = self.world.as_mut() else { return Ok(false); };
        if self.departure.is_some() || self.slot_open || now < self.next_tick { return Ok(false); }
        let Some(minutes) = self.control.tick() else { return Ok(false); };
        self.next_tick = now + TICK_INTERVAL;
        if let Err(error) = world.advance_migrated_domains(minutes, &BTreeMap::new()) {
            self.control.paused = true;
            return Err(error);
        }
        Ok(true)
    }

    fn relations_action(&mut self, verb: &str, id: &str) -> io::Result<()> {
        let Some(world) = &mut self.world else { return Ok(()); };
        match verb {
            "open" => self.relations = Some("relations".into()),
            "close" => { self.relations = None; self.pending_job = None; self.selected_organization.clear(); }
            "drawer" if matches!(id, "relations" | "work") => {
                self.relations = Some(id.to_owned());
                self.pending_job = None;
            }
            "select" if world.employment().is_some_and(|(_, _, org)| org == id) => self.selected_organization = id.into(),
            "back" => self.selected_organization.clear(),
            "work_action" if self.relations.as_deref() == Some("work") => {
                if id == "native:work" { world.book_work()?; }
                if let Some(job) = id.strip_prefix("person:job_request:") {
                    if world.employment().is_none() && world.jobs().any(|(row, spots)| row.id == job && spots > 0) {
                        self.pending_job = Some(job.into());
                    }
                }
            }
            "work_confirm" => {
                if let Some(job) = self.pending_job.take() { world.apply_for_work(&job)?; }
            }
            "work_cancel" => self.pending_job = None,
            _ => (),
        }
        Ok(())
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
                page.content = match id { "goods" => "goods", "transport" => "transport", "activity" => "activity", _ => "quotes" };
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
                let amount = if page.unit == world.player_market_unit() {
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
        let place = &world.sources().places()[&player.place_id];
        let country = &world.sources().polities()[&player.opening_source_id].name_zh;
        let cash = world.balance().ok_or_else(|| io::Error::other("正式人物账号缺失。"))?;
        let mut receipts = world.ledger().personal_receipts(&player.id).skip(self.finance_page * 6);
        let rows: Vec<_> = receipts.by_ref().take(6).map(|receipt| {
            let kind = match receipt.kind { "opening_cash" => "开局现金", "purchase" => "购买", "wage" => "工资", kind => kind };
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
        let activities = world.opening_language().map(|language| json!({
            "language": language, "scheduled": world.scheduled_activity(),
            "lesson":world.can_schedule_personal_activity(PersonalActivity::Lesson),
            "rest":world.can_schedule_personal_activity(PersonalActivity::Rest),
            "read_notice":world.can_schedule_personal_activity(PersonalActivity::ReadNotice),
            "oral_notice":world.last_read_notice().map(|_| format!("课堂教师口述 · {}", world.lesson_notice())),
        }));
        let messages = world.opening_language().map(|_| json!([{
            "source":"本地识字课堂", "received_at":"", "text":world.lesson_notice(), "action":""
        }])).unwrap_or_else(|| json!([]));
        let session: Session = serde_json::from_value(json!({
            "player":player.id,"polity":player.polity_id,
            "coordinates":place.lon_lat.map(Vec::from).unwrap_or_default(),"place":player.place_id,
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
            "character":character,
            "departure":self.departure.map_or("", |quit| if quit {"quit"} else {"main_menu"})
        }))?;
        state.date = Date::new(i32::try_from(date.year).map_err(io::Error::other)?, date.month, date.day);
        state.lobby = None;
        state.session = Some(session);
        Ok(())
    }

    pub fn update_after_tick(&self, state: &mut State) -> io::Result<()> {
        let clock = self.world.as_ref().unwrap().clock();
        if let Some(view) = state.session.as_mut() {
            if view.total_minutes / MINUTES_PER_DAY as u64 == clock.current_day() as u64 {
                let date = clock.current_date();
                view.hour = date.hour as u32;
                view.minute = date.minute as u32;
                view.total_minutes = clock.snapshot().total_minutes as u64;
                if let (Some(world), Some(activities)) = (&self.world, &mut view.activities) {
                    activities.lesson = world.can_schedule_personal_activity(PersonalActivity::Lesson);
                    activities.rest = world.can_schedule_personal_activity(PersonalActivity::Rest);
                    activities.read_notice = world.can_schedule_personal_activity(PersonalActivity::ReadNotice);
                }
                if let Some(market) = view.market.as_mut() {
                    market.minute = view.total_minutes;
                }
                return Ok(());
            }
        }
        self.update_view(state)
    }

    fn work_view(&self, world: &InitialWorld, drawer: &str) -> Value {
        let mut work = Vec::new();
        let mut organizations = Vec::new();
        if let Some((job, booked, organization)) = world.employment() {
            organizations.push(json!({"id":organization,"label":employer_label(&job.employer),"role":"雇员",
                "kind":"劳动关系","place":job.place,"basis":"开局配置"}));
            work.push(json!({"label":employer_label(&job.employer),
                "details":[format!("每班 {} 小时 · 时薪 {} · {} 日后发薪",job.hours,job.wage_per_hour,job.wage_delay),
                           if booked {"已登记本日工作"} else {"劳动合同有效"}],
                "actions":[{"label":"工作","id":"native:work","enabled":!booked}]}));
        } else {
            for (job, vacancies) in world.jobs() {
                work.push(json!({"label":employer_label(&job.employer),
                    "details":[format!("空缺 {vacancies} · 每班 {} 小时 · 时薪 {}",job.hours,job.wage_per_hour)],
                    "actions":[{"label":"申请","id":format!("person:job_request:{}",job.id),"enabled":vacancies>0}]}));
            }
        }
        let confirmation = self.pending_job.as_ref().map(|_| json!({"title":"确认就业","body":"接受该岗位的工时和工资条件。"}));
        json!({"selected":self.selected_organization,"rows":organizations,"drawer":drawer,
            "has_work":!work.is_empty(),"work":work,"confirmation":confirmation})
    }
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
        let offers = market.commodities.get(&self.good).filter(|_| economy.purchasable(&self.good)).map(|row| {
            let (_, _, unit) = info.unwrap();
            json!([{"good":self.good,"commodity":self.good,"site":market.id,"place":world.player().place_id,
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
