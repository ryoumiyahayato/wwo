use super::{Focus, Host};
use crate::{
    camera, formal_ui::{self, Command as HudCommand, Menu as HudMenu, Page as HudPage},
    interface, lobby, prologue_ui, state::Request, ui::{Action, Mode, Object},
};
use std::time::{Duration, Instant};

impl Host {
    fn save_interface(&mut self) {
        self.emit(Request::Interface{volume:f64::from(self.hud.volume)/100.,locale:if self.hud.english{"en"}else{"zh_CN"}});
        self.save_preferences();
    }
    pub(super) fn save_preferences(&mut self) {
        let (fixed,last)=self.menu_themes.preference();
        let preferences=interface::Preferences{
            fullscreen:self.hud.fullscreen,volume:self.hud.volume,english:self.hud.english,
            fixed_painting:fixed.map(str::to_owned),last_painting:last.map(str::to_owned),
        };
        if let Some(path)=&self.config.preferences {
            if let Err(error)=preferences.save(path) {
                self.feedback=format!("设置保存失败：{error}");
            }
        }
    }
    pub(super) fn volume_slider(&self)->Option<[f64;4]> {
        (self.in_lobby()&&self.lobby_page==lobby::Page::Settings).then(||{
            [(f64::from(self.size[0])-365.)*0.5+16.,(f64::from(self.size[1])-290.)*0.5+73.,333.,28.]
        })
    }
    pub(super) fn slide_volume(&mut self) {
        if let Some([x,_,width,_])=self.volume_slider(){
            let volume=((self.cursor[0]-x)/width*100.).round().clamp(0.,100.) as u8;
            if self.hud.volume!=volume {self.hud_action(HudCommand::Volume(volume));}
            self.dirty=true;
        }
    }

    pub(super) fn hud_action(&mut self,command:HudCommand) {
        match command {
            HudCommand::PlaceFilters => {
                self.hud.place_filters_open = !self.hud.place_filters_open;
                if self.hud.place_filters_open {
                    let (_, visible) = formal_ui::place_filter_drawer(self.size);
                    let active = formal_ui::PLACE_FILTERS.iter()
                        .position(|(filter, _, _)| *filter == self.hud.place_filter).unwrap_or_default();
                    self.hud.place_filter_offset = active.min(formal_ui::PLACE_FILTERS.len() - visible);
                }
            }
            HudCommand::PlaceFilterScroll(steps) => {
                let (_, visible) = formal_ui::place_filter_drawer(self.size);
                let max = formal_ui::PLACE_FILTERS.len() - visible;
                self.hud.place_filter_offset = self.hud.place_filter_offset.min(max)
                    .saturating_add_signed(steps as isize).min(max);
            }
            HudCommand::Page(page)=>{
                if page!=HudPage::Map { self.population_debug=None; }
                if let (true,Some(window))=(self.hud.market_search.is_some() || self.hud.transport_directory.is_some(),&self.window) {
                    window.set_ime_allowed(false);
                }
                if self.hud.page==HudPage::Market&&page!=HudPage::Market{self.market_command("close",0);}
                if self.hud.page==HudPage::Relations&&page!=HudPage::Relations{
                    self.emit(Request::Relations{verb:"close",id:""});
                }else if page==HudPage::Relations&&self.hud.page!=HudPage::Relations{
                    self.emit(Request::Relations{verb:"open",id:""});
                }
                self.hud.page=page;self.hud.menu=HudMenu::None;
                self.hud.market_map=false;
                self.hud.market_search=None;
                self.hud.transport_directory=None;
                self.hud.transport_lots_open=false;
                self.hud.market_offset=0;
                self.details=false;self.country=None;self.search=None;
            }
            HudCommand::PortraitAction(_,page)=>self.hud_action(HudCommand::Page(page)),
            HudCommand::RelationDrawer(id)=>{
                self.hud.market_offset=0;
                self.emit(Request::Relations{verb:"drawer",id});
            }
            HudCommand::WorkAction(row,index,revision)=>{
                let id=self.state.session.as_ref().and_then(|s|s.relations.as_ref())
                    .filter(|r|r.work_revision==revision)
                    .and_then(|r|r.work.get(row)).and_then(|r|r.actions.get(index))
                    .filter(|a|a.enabled).map(|a|a.id.clone());
                if id.as_deref()==Some("organization:freight_page"){
                    self.hud_action(HudCommand::Page(HudPage::Map));
                    self.action(Action::Mode(Mode::Economic));
                    self.market_command("open",0);
                    self.market_command("freight",0);
                } else if let Some(id)=id{self.emit(Request::Relations{verb:"work_action",id:&id});}
            }
            HudCommand::OralWorkAction(revision)=>{
                let id=self.state.session.as_ref().and_then(|s|s.activities.as_ref())
                    .and_then(|a|a.oral_work_action(revision)).map(str::to_owned);
                if let Some(id)=id{self.emit(Request::Relations{verb:"work_action",id:&id});}
            }
            HudCommand::OralReferral=>{
                let id=self.state.session.as_ref().and_then(|s|s.character.as_ref())
                    .and_then(|c|c.oral_referral.as_ref()).map(|office|office.id.clone());
                if let Some(id)=id {self.emit(Request::Relations{verb:"oral_referral",id:&id});}
            }
            HudCommand::WorkConfirm(confirmed)=>{
                self.emit(Request::Relations{verb:if confirmed{"work_confirm"}else{"work_cancel"},id:""});
            }
            HudCommand::Consume(index) => {
                let choice = self.state.session.as_ref().and_then(|s| s.property.get(index))
                    .and_then(|row| row.consume_quantity.map(|quantity| (row.id.clone(), quantity)));
                if let Some((id, quantity)) = choice {
                    self.emit(Request::Consume { id: &id, quantity });
                }
            }
            HudCommand::Relation(index)=>{
                self.hud.market_offset=0;
                let id=index.and_then(|i|self.state.session.as_ref()?.relations.as_ref()?.rows.get(i))
                    .map(|row|row.id.clone());
                match (index,id) {
                    (_,Some(id))=>self.emit(Request::Relations{verb:"select",id:&id}),
                    (None,_)=>self.emit(Request::Relations{verb:"back",id:""}),
                    _=>(),
                }
            }
            HudCommand::Menu(menu)=>{
                let previous=self.hud.menu;
                self.hud.menu=if previous==menu{HudMenu::None}else{menu};
                self.hud.waiting_slot=false;
                if menu==HudMenu::MapModes {
                    if self.hud.page==HudPage::Market{self.market_command("close",0);}
                    if self.hud.page==HudPage::Relations{self.emit(Request::Relations{verb:"close",id:""});}
                    if self.hud.page!=HudPage::Travel {self.hud.page=HudPage::Map;}
                }
                self.hud.messages=false;
                if matches!(self.hud.menu,HudMenu::Save|HudMenu::Load){
                    self.emit(Request::OpenSlots{mode:if menu==HudMenu::Save{"save"}else{"load"}});
                }else if matches!(previous,HudMenu::Save|HudMenu::Load|HudMenu::Overwrite(_)){
                    self.emit(Request::CloseSlots);
                }
            }
            HudCommand::Messages=>{
                self.hud.messages=!self.hud.messages;self.hud.menu=HudMenu::None;
            }
            HudCommand::MessageScroll(delta)=>{
                let max=self.state.session.as_ref().map_or(0,|s|s.messages.len().saturating_sub(1));
                self.hud.message_offset=self.hud.message_offset.saturating_add_signed(delta as isize).min(max);
            }
            HudCommand::Technology(tab)=>self.hud.tech=tab,
            HudCommand::Milestone(index)=>self.hud.milestone=index,
            HudCommand::FinancePage(page)=>self.emit(Request::FinancePage{page}),
            HudCommand::Clock(mut speed)=>{
                if self.state.session.is_some(){
                    // The archived comparison bridge only accepts the original four speeds.
                    if speed == 3 && self.config.requests.is_some() { speed = 4; }
                    let index=formal_ui::CLOCK_SPEEDS.iter().position(|v|*v==speed).unwrap_or(0);
                    let serial=self.hud.mechanical.request(index,self.hud.clock_drag.take());
                    self.emit(Request::Clock{speed,serial});
                }
            }
            HudCommand::Player=>{
                if self.state.session.as_ref().is_some_and(|s| s.character.is_some()) {
                    self.hud_action(HudCommand::Page(HudPage::Character));
                } else {
                    self.hud_action(HudCommand::LocatePlayer);
                }
            }
            HudCommand::LocatePlayer=>{
                let position=self.state.session.as_ref().and_then(|s|match s.coordinates.as_slice(){[lon,lat]=>Some(([*lon,*lat],s.place.clone())),_=>None});
                if let Some((p,id))=position{self.emit(Request::Locate{id:&id});self.locate(p,1400.);self.hud.page=HudPage::Map;}
                else{self.feedback="正式世界未连接".into();}
            }
            HudCommand::PlayerMarker=>{
                if self.hud.page==HudPage::Market {
                    let region=self.state.session.as_ref().and_then(|s|s.market.as_ref()
                        .and_then(|m|m.places.iter().position(|row|row.id==s.place)));
                    if let Some(index)=region {self.market_command("region",index);}
                } else {
                    self.hud_action(HudCommand::Page(HudPage::Property));
                }
            }
            HudCommand::PlayerCountry=>{
                if let Some(i)=self.player_polity(){self.open_country(i);}
            }
            HudCommand::Slot(slot)=>{
                let overwrite=self.state.session.as_ref().and_then(|s|s.slots.iter().find(|r|r.slot==slot)).is_some_and(|row|!row.empty);
                if self.hud.menu==HudMenu::Save && overwrite {self.hud.menu=HudMenu::Overwrite(slot);}
                else{self.request_slot(slot,self.hud.menu==HudMenu::Save);}
            }
            HudCommand::ConfirmSlot(slot)=>self.request_slot(slot,true),
            HudCommand::MessageLink(index)=>{
                let action=self.state.session.as_ref().and_then(|s|s.messages.get(index)).map(|m|m.action.clone());
                if let Some(action)=action {
                    if action=="person:accounts"{self.hud_action(HudCommand::Page(HudPage::Finance));}
                    else if action.starts_with("holding:select:")||action=="person:goods"{self.hud_action(HudCommand::Page(HudPage::Property));}
                    else if action.starts_with("technology:"){self.hud_action(HudCommand::Page(HudPage::Technology));}
                    else{self.feedback="此消息的后续操作尚未迁移".into();}
                }
            }
            HudCommand::Labels=>self.labels=!self.labels,
            HudCommand::MilitaryGrid=>{
                self.hud.military_grid=!self.hud.military_grid;
                self.feedback.clear();
            }
            HudCommand::Fullscreen=>{
                if let Some(window)=&self.window {
                    self.hud.fullscreen=!self.hud.fullscreen;
                    if !self.config.background {window.set_fullscreen(self.hud.fullscreen.then_some(winit::window::Fullscreen::Borderless(None)));}
                    self.save_interface();
                }
            }
            HudCommand::Volume(volume)=>{
                self.hud.volume=volume.min(100);
                self.save_interface();
            }
            HudCommand::Language(english)=>{
                self.hud.english=english;
                self.skin.set_english(english);
                self.save_interface();
            }
            HudCommand::Quit=>{
                if self.config.managed&&self.state.session.is_some(){self.hud_action(HudCommand::Departure("system:quit"));}
                else if self.state.session.is_some(){self.feedback="此兼容会话请关闭窗口退出。".into();}
                else{self.exit_requested=true;}
            }
            HudCommand::Departure(verb)=>{
                if verb=="system:quit" {self.departure_requested=true;}
                self.emit(Request::HostAction{action:verb});
                if verb=="departure:cancel"{self.hud.menu=HudMenu::None;self.departure_requested=false;}
            }
            HudCommand::Lobby(command)=>self.lobby_action(command),
            HudCommand::PersonalActivity(activity)=>self.emit(Request::PersonalActivity{activity}),
            HudCommand::Training(verb)=>{
                if self.state.session.is_some(){self.emit(Request::Training{verb});}
            }
            HudCommand::Market(verb,index)=>self.market_command(verb,index),
            HudCommand::Transport(verb,index)=>self.transport_command(verb,index),
            HudCommand::TransportDetail(index)=>self.transport_detail_action(index),
            HudCommand::ToggleTransportDetail=>self.hud.transport_detail_expanded^=true,
            HudCommand::TransportSteps=>self.hud.transport_steps^=true,
            HudCommand::TransportLots=>{
                self.hud.transport_lots_open^=true;
                self.hud.lot_offset=0;
            }
            HudCommand::TransportDirectory=>{
                self.hud_action(HudCommand::Page(HudPage::Travel));
                self.hud.transport_directory=Some(String::new());
                if let Some(window)=&self.window {window.set_ime_allowed(true);}
                self.hud.transport_category=0;
                self.transport_search();
            }
            HudCommand::TransportCategory(category)=>{
                self.hud.transport_category=category;
                self.transport_search();
            }
            HudCommand::CloseTransportDetail=>self.select_transport(None),
            HudCommand::MarketScroll(delta)=>{
                let count=self.state.session.as_ref().map_or(0,|s| {
                    if self.hud.page==HudPage::Travel || self.hud.market_chooser==Some("transport_lots")
                        || s.market.as_ref().is_some_and(|v|v.content=="freight") {
                        return s.transport.as_ref().map_or(0,|v|v.lots.len());
                    }
                    if self.hud.page==HudPage::Property{return s.property.len();}
                    if self.hud.page==HudPage::Character{return s.character.as_ref().map_or(0,|c|c.oral_contacts.len());}
                    if self.hud.page==HudPage::Relations{return s.relations.as_ref().map_or(0,|view|{
                        if view.drawer=="work" || !view.selected.is_empty(){view.work.len()}else{view.rows.len()}
                    });}
                    let Some(v)=&s.market else{return 0;};
                    if let Some(query)=self.hud.market_search.as_deref() {
                        return v.matching_sites(query).count();
                    }
                    match self.hud.market_chooser.unwrap_or(&v.content){
                        "places"=>v.places.len(),"countries"=>v.countries.len(),
                        "good"=>v.offers.iter().filter(|o|o.good==v.good).count(),
                        "goods"=>v.catalog.len(),
                        "activity"=>v.orders.len(),"transport"=>v.logistics_len(),
                        _=>v.book.len(),
                    }
                });
                if self.hud.transport_lots_open {
                    self.hud.lot_offset=self.hud.lot_offset.saturating_add_signed(delta as isize).min(count.saturating_sub(1));
                } else {
                    self.hud.market_offset=self.hud.market_offset.saturating_add_signed(delta as isize).min(count.saturating_sub(1));
                }
            },
        }
    }
    pub(super) fn in_lobby(&self)->bool {self.config.managed&&self.state.session.is_none()}
    pub(super) fn opening_transition_active(&self) -> bool {
        self.opening_nav.cloud.is_some() || self.opening_nav.departure_cloud.is_some()
            || self.opening_nav.arrival_cloud.is_some()
    }
    pub(super) fn loading(&self)->bool {
        self.config.managed && (self.lobby_request||self.state.lobby.as_ref().is_some_and(|s|s.loading||s.busy||
                self.lobby_page==lobby::Page::Selection&&!s.selection_ready&&self.feedback.is_empty()&&s.status.is_empty())
            || self.state.lobby.is_none()&&self.state.session.is_none()&&self.feedback.is_empty())
    }
    pub(super) fn animate_opening(&mut self, now: Instant) {
        use lobby::{Page, SelectionStage};
        if !self.in_lobby()
            || self.window.as_ref().is_some_and(|window| window.is_minimized() == Some(true)) { return; }
        let elapsed = now.saturating_duration_since(self.opening_nav.last_animation);
        if let Some((start, from, to)) = self.opening_nav.shift {
            let t = (now.saturating_duration_since(start).as_secs_f64() / 0.5).min(1.);
            self.camera.screen_offset_x = from + (to - from) * t * t * (3. - 2. * t);
            if t == 1. { self.opening_nav.shift = None; }
            self.dirty = true;
        }
        match self.lobby_page {
            Page::Cloud => {
                if self.opening_nav.cloud.is_some_and(|start| now.saturating_duration_since(start).as_secs_f32() >= lobby::CLOUD_SCENE_CUT) {
                    self.lobby_page = Page::Prologue;
                }
                self.dirty = true;
            }
            Page::Prologue if self.opening_nav.cloud.is_some() || self.opening_nav.departure_cloud.is_some() => {
                if self.opening_nav.cloud.is_some_and(|start| start.elapsed().as_secs_f32() >= lobby::CLOUD_OPEN_TIME) {
                    self.opening_nav.cloud = None;
                }
                if self.opening_nav.departure_cloud.is_some_and(|start| start.elapsed().as_secs_f32() >= lobby::CLOUD_DEPART_TIME) {
                    self.enter_prologue_world();
                }
                self.dirty = true;
            }
            Page::Selection if elapsed >= Duration::from_millis(125) => {
                self.opening_nav.last_animation = now;
                if self.opening_nav.stage == SelectionStage::Profile {
                    self.dirty = self.opening_choice().is_some() || self.dirty;
                } else if self.focus.is_none() && self.drag.is_none() && self.camera.blend() == 0.
                    && now.saturating_duration_since(self.opening_nav.last_input) >= Duration::from_secs(2)
                {
                    let [lon, lat] = self.camera.coordinates();
                    let lon = (lon + 180. + elapsed.as_secs_f64().min(0.25) * 0.7).rem_euclid(360.) - 180.;
                    self.camera.focus([lon, lat], self.camera.mpp, self.size);
                    self.dirty = true;
                }
            }
            Page::Prologue if self.prologue.as_ref().is_some_and(|draft| now.saturating_duration_since(draft.changed) < Duration::from_millis(340)) => {
                self.dirty = true;
            }
            _ => (),
        }
    }

    pub(super) fn opening_choice(&self) -> Option<&lobby::Opening> {
        self.state.lobby.as_ref()?.opening(self.world.polities.get(self.lobby_country)?)
    }

    pub(super) fn opening_shift(&mut self, target: f64) {
        self.opening_nav.shift = Some((Instant::now(), self.camera.screen_offset_x, target));
    }

    fn opening_focus(&mut self, target: [f64; 2], mpp: f64) {
        self.velocity = [0.; 2];
        self.focus = Some(Focus { start: Instant::now(), camera: self.camera.clone(), target, mpp });
        self.dirty = true;
    }

    pub(super) fn opening_layout(&self) -> Option<lobby::ProfileLayout> {
        let polity = self.world.polities.get(self.lobby_country)?;
        Some(lobby::ProfileLayout::new(self.size, &self.world, &self.skin, polity,
            self.opening_choice(), &self.country_directory, &self.opening_nav))
    }

    fn opening_area(&mut self, path: Vec<String>) {
        self.opening_nav.map_area = path.iter().rev()
            .find_map(|id| self.world.admin.iter().position(|admin| &admin.id == id));
        if !self.opening_nav.site.and_then(|i| self.opening_choice()?.sites.get(i)).is_some_and(|site|
            site.path.iter().map(|area| &area.id).take(path.len()).eq(path.iter())) {
            self.opening_nav.site = None;
        }
        self.opening_nav.path = path;
        self.opening_nav.drawer = true;
        self.opening_nav.drawer_drag = None;
        self.opening_nav.offset = 0;
        self.country_directory.query.clear();
        self.country_directory.search_active = false;
        let focus = self.opening_nav.path.last().and_then(|id| {
            if let Some(admin) = self.opening_nav.map_area.and_then(|i| self.world.admin.get(i)).filter(|admin| &admin.id == id) {
                return camera::fit_bounds(admin.bounds, self.size);
            }
            let mut points = self.opening_choice()?.sites.iter()
                .filter(|site| site.path.iter().any(|area| &area.id == id)).map(|site| site.coordinates);
            let [lon, lat] = points.next()?;
            let bounds = points.fold([lon, lat, lon, lat], |[w, s, e, n], [x, y]| [w.min(x), s.min(y), e.max(x), n.max(y)]);
            camera::fit_bounds(bounds, self.size).or(Some(([lon, lat], self.camera.mpp.min(2200.))))
        }).or_else(|| {
            let polity = self.world.polities.get(self.lobby_country)?;
            self.visuals.record(self.lobby_country).focus(self.size).or(Some((polity.coordinates, 3000.)))
        });
        if let Some((point, mpp)) = focus { self.opening_focus(point, mpp); }
        self.dirty = true;
    }

    fn enter_prologue_world(&mut self) {
        let Some(polity) = self.opening_choice().map(|opening| opening.id.clone()) else { return; };
        let Some(draft) = self.prologue.as_ref().filter(|draft| draft.confirm()) else { return; };
        let place = draft.place.clone();
        let prologue = draft.opening;
        let health = draft.health;
        self.lobby_request = true;
        self.bridge_wait = Instant::now();
        self.seen_lobby_busy = false;
        self.emit(Request::NewPlayer { polity: &polity, place: &place, prologue, health });
        if self.state.session.is_none() {
            self.lobby_request = false;
            self.opening_nav.departure_cloud = None;
            self.opening_nav.arrival_cloud = Some(Instant::now());
        }
    }

    pub(super) fn lobby_action(&mut self, command: lobby::Command) {
        use lobby::{Command, Page, SelectionStage};
        if !self.in_lobby() { return; }
        self.opening_nav.last_input = Instant::now();
        match command {
            Command::Page(page) => {
                self.lobby_page = page;
                self.country_directory.search_active = false;
                self.country_directory.drag = None;
                self.lobby_request = false;
                self.seen_lobby_busy = false;
                match page {
                    Page::Selection => {
                        self.country_directory = lobby::Directory::default();
                        self.opening_nav = lobby::Selection::default();
                        self.prologue = None;
                        self.mode = Mode::Political;
                        self.focus = None;
                        self.velocity = [0.; 2];
                        self.camera.screen_offset_x = 0.;
                        self.camera.set_scale(lobby::globe_mpp(self.size));
                        if let Some(lobby) = &mut self.state.lobby { lobby.selection_ready = false; }
                        self.emit(Request::Lobby { verb: "select", polity: "", slot: 0 });
                        self.filter_countries();
                    }
                    Page::Load => self.emit(Request::Lobby { verb: "slots", polity: "", slot: 0 }),
                    Page::Home => {
                        self.focus = None;
                        self.opening_nav.shift = None;
                        self.camera.screen_offset_x = 0.;
                        self.emit(Request::Lobby { verb: "home", polity: "", slot: 0 });
                    }
                    _ => (),
                }
            }
            Command::Back => {
                if self.opening_nav.drawer {
                    self.opening_nav.drawer = false;
                    self.country_directory.search_active = false;
                } else {
                    match self.opening_nav.stage {
                        SelectionStage::Globe => self.lobby_action(Command::Page(Page::Home)),
                        SelectionStage::Directory => {
                            self.opening_nav.stage = SelectionStage::Globe;
                            self.opening_shift(0.);
                            self.opening_focus(self.camera.coordinates(), lobby::globe_mpp(self.size));
                            self.country_directory.search_active = false;
                        }
                        SelectionStage::Profile => {
                            self.opening_nav.stage = SelectionStage::Directory;
                            self.opening_nav.reset_place();
                            self.country_directory.query.clear();
                            self.filter_countries();
                            self.country_directory.reveal(self.size, self.lobby_country);
                            self.opening_focus(self.camera.coordinates(), lobby::globe_mpp(self.size));
                        }
                    }
                }
            }
            Command::Country(index) if self.lobby_page == Page::Selection => {
                if self.opening_nav.stage == SelectionStage::Globe { return; }
                if self.world.polities.get(index).is_some() && self.available(Object::Polity(index)) {
                    self.country_directory.search_active = false;
                    self.country_directory.query.clear();
                    self.country_directory.drag = None;
                    self.opening_nav.previous_country = (self.lobby_country != index)
                        .then_some((self.lobby_country, Instant::now()));
                    self.opening_nav.reset_place();
                    self.lobby_country = index;
                    self.opening_nav.stage = SelectionStage::Profile;
                    self.prologue = None;
                    let polity = &self.world.polities[index];
                    let (target, mpp) = self.visuals.record(index).focus(self.size).unwrap_or((polity.coordinates, 3000.));
                    self.opening_focus(target, mpp);
                }
            }
            Command::Drawer => {
                self.opening_nav.drawer = !self.opening_nav.drawer;
                self.opening_nav.drawer_drag = None;
                self.country_directory.search_active = false;
                self.country_directory.query.clear();
                self.opening_nav.offset = 0;
            }
            Command::Up => {
                let mut path = self.opening_nav.path.clone();
                path.pop();
                self.opening_area(path);
            }
            Command::Area(index, depth) => {
                if let Some(site) = self.opening_choice().and_then(|opening| opening.sites.get(index)) {
                    let path = site.path.iter().take(depth + 1).map(|area| area.id.clone()).collect();
                    self.opening_area(path);
                }
            }
            Command::MapArea(index) => {
                if let Some(admin) = self.world.admin.get(index) {
                    self.opening_area(vec![admin.id.clone()]);
                }
            }
            Command::Site(index) => {
                if let Some(site) = self.opening_choice().and_then(|opening| opening.sites.get(index))
                    .filter(|site| site.unavailable.is_none())
                {
                    let point = site.coordinates;
                    let path: Vec<_> = site.path.iter().map(|area| area.id.clone()).collect();
                    self.opening_nav.site = Some(index);
                    self.opening_nav.map_area = path.iter().rev().find_map(|id|
                        self.world.admin.iter().position(|area| &area.id == id));
                    self.opening_nav.path = path;
                    self.opening_nav.drawer = false;
                    self.country_directory.search_active = false;
                    self.country_directory.query.clear();
                    self.opening_focus(point, self.camera.mpp.min(800.));
                }
            }
            Command::Search => {
                self.country_directory.search_active = true;
                if let Some(window) = &self.window { window.set_ime_allowed(true); }
            }
            Command::ClearSearch => {
                self.country_directory.query.clear();
                self.country_directory.search_active = false;
                self.opening_nav.offset = 0;
                self.filter_countries();
            }
            Command::ChangePainting=>{
                if let Some(image)=self.menu_themes.change(&self.config.root) {
                    if let Some(renderer)=&mut self.renderer {renderer.replace_menu_painting(image);}
                    self.save_preferences();
                }
            }
            Command::FixPainting(fixed)=>{
                self.menu_themes.set_fixed(fixed);
                self.save_preferences();
            }
            Command::Enter => {
                if self.lobby_page != Page::Selection || self.lobby_request || self.opening_nav.stage != SelectionStage::Profile
                    || self.state.lobby.as_ref().is_none_or(|state| !state.selection_ready || state.busy) { return; }
                if let Some(opening) = self.opening_choice() {
                    if opening.native {
                        if let Some(site) = self.opening_nav.site.and_then(|index| opening.sites.get(index))
                            .filter(|site| site.unavailable.is_none())
                        {
                            let point = site.coordinates;
                            self.prologue = Some(prologue_ui::Draft::new(self.lobby_country, site.id.clone(), opening.language));
                            self.opening_nav.cloud = Some(Instant::now());
                            self.lobby_page = Page::Cloud;
                            self.opening_shift(0.);
                            self.opening_focus(point, self.camera.mpp.min(125.));
                        }
                    } else {
                        let id = opening.id.clone();
                        self.lobby_request = true;
                        self.bridge_wait = Instant::now();
                        self.seen_lobby_busy = false;
                        self.emit(Request::Lobby { verb: "new", polity: &id, slot: 0 });
                    }
                }
            }
            Command::PrologueChoice(index) if self.lobby_page == Page::Prologue => {
                if let Some(draft) = &mut self.prologue { draft.choose(index); }
            }
            Command::PrologueBack if self.lobby_page == Page::Prologue => {
                if let Some(draft) = &mut self.prologue {
                    if draft.stage == 0 {
                        self.lobby_page = Page::Selection;
                        self.camera.screen_offset_x = -0.11;
                        if let Some(point) = self.opening_choice().and_then(|opening| self.opening_nav.site.and_then(|i| opening.sites.get(i))).map(|site| site.coordinates) {
                            self.opening_focus(point, 800.);
                        }
                    } else {
                        draft.stage -= 1;
                        draft.changed = Instant::now();
                    }
                }
            }
            Command::PrologueNext if self.lobby_page == Page::Prologue && !self.lobby_request => {
                if let Some(draft) = &mut self.prologue {
                    if !draft.confirm() { draft.advance(); }
                    else { self.opening_nav.departure_cloud = Some(Instant::now()); }
                }
            }
            Command::Load(slot) => {
                self.lobby_request = true;
                self.bridge_wait = Instant::now();
                self.seen_lobby_busy = false;
                self.emit(Request::Lobby { verb: "load", polity: "", slot });
            }
            Command::Exit => self.exit_requested = true,
            _ => ()
        }
        if !self.country_directory.search_active {
            if let Some(window) = &self.window { window.set_ime_allowed(false); }
        }
        self.dirty = true;
    }

    pub(super) fn filter_countries(&mut self) {
        if self.opening_nav.stage != lobby::SelectionStage::Profile {
            self.country_directory.filter(&self.world, self.state.lobby.as_ref(), &self.state.date.to_string(), self.hud.english);
        }
        self.dirty = true;
    }

    pub(super) fn scroll_place_filters(&mut self, point: [f64; 2], steps: f64) -> bool {
        if self.resources_available() && self.resources.scroll_categories(self.size,point,steps) {
            self.dirty = true;
            return true;
        }
        if self.hud.menu != HudMenu::MapModes || self.mode != Mode::Political || !self.hud.place_filters_open {
            return false;
        }
        let (drawer, _) = formal_ui::place_filter_drawer(self.size);
        if !lobby::contains(drawer, point) { return false; }
        self.action(Action::Hud(HudCommand::PlaceFilterScroll(-(steps.signum() as i32))));
        true
    }

    pub(super) fn scroll_countries(&mut self, point: [f64; 2], steps: f64) -> bool {
        use lobby::SelectionStage;
        if !self.in_lobby() || self.lobby_page != lobby::Page::Selection { return false; }
        let moved = match self.opening_nav.stage {
            SelectionStage::Directory if lobby::contains(lobby::directory_rect(self.size), point) => {
                self.country_directory.scroll(self.size, steps as f32);
                true
            }
            SelectionStage::Profile => self.opening_layout().is_some_and(|layout| {
                if self.opening_nav.drawer && lobby::contains(layout.drawer, point) {
                    let max = layout.max_scroll();
                    self.opening_nav.offset = self.opening_nav.offset.min(max)
                        .saturating_add_signed((-steps * 3.).round() as isize).min(max);
                    return true;
                }
                let max = layout.summary_lines.saturating_sub((layout.summary[3] / 21.).floor() as usize);
                if max > 0 && lobby::contains(layout.summary, point) {
                    self.opening_nav.profile_scroll = self.opening_nav.profile_scroll.min(max)
                        .saturating_add_signed((-steps).round() as isize).min(max);
                    return true;
                }
                false
            }),
            _ => false,
        };
        self.dirty |= moved;
        moved
    }
    pub(super) fn type_country_search(&mut self,text:&str) {
        let query=&mut self.country_directory.query;
        let remaining=64_usize.saturating_sub(query.chars().count());
        query.extend(text.chars().filter(|c|!c.is_control()).take(remaining));
        self.opening_nav.offset = 0;
        self.filter_countries();
    }
}
