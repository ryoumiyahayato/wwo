use super::{decode_rgba, font, hud_type_atlas, ms, Drag, Host, HostEvent, Resident, CACHE_TTL, VIEW_SIZE};
use crate::{
    battle_view, camera::{Camera, Level}, compact::Raster,
    formal_ui::{self, Command as HudCommand, Hud, Menu as HudMenu, Page as HudPage},
    lobby, map_release, politics::PoliticalVisuals, pop_debug_ui, render::{self, Renderer},
    terrain, terrain_detail, timeline::Date, ui::{Action, CountryAction, Mode}, world::Pixels,
};
#[cfg(windows)]
use crate::native_start;
use std::{fs::{self, File}, io::{self, Read}, sync::Arc, time::{Duration, Instant}};
use winit::{
    application::ApplicationHandler, dpi::{LogicalSize, PhysicalSize},
    event::{ElementState, MouseButton, MouseScrollDelta, WindowEvent},
    event_loop::{ActiveEventLoop, ControlFlow}, keyboard::{Key, NamedKey}, window::{Window, WindowId},
};

impl Host {
    pub(super) fn key(&mut self,key:Key) {
        self.country_click=None;
        if key==Key::Named(NamedKey::F8){self.hud.mechanical.hidden=!self.hud.mechanical.hidden;self.dirty=true;return;}
        if key==Key::Named(NamedKey::F12){self.queue_screenshot();return;}
        if key==Key::Named(NamedKey::F10){
            self.debug=!self.debug;self.perf_at=Instant::now();self.perf_frames=0;self.perf.rate=0.;self.dirty=true;return;
        }
        if self.debug && key==Key::Named(NamedKey::F11) {self.reload_debug_resources();return;}
        if self.battle_view.is_some() && key==Key::Named(NamedKey::F5) {
            self.hud_action(HudCommand::Clock(0));
            self.battle_command(battle_view::Command::Back);
            self.hud_action(HudCommand::Menu(HudMenu::Save));
            return;
        }
        if let (Some(view),Some((_,terrain)))=(&mut self.battle_view,&self.battle_terrain){
            let command=view.key(key.clone(),ElementState::Pressed,false,terrain);
            view.key(key,ElementState::Released,false,terrain);
            if let Some(command)=command {self.battle_command(command);}
            return;
        }
        if self.hud.clock_drag.is_some() && matches!(&key,Key::Named(NamedKey::Escape|NamedKey::Space)) {
            self.hud.clock_drag=None;
            if key==Key::Named(NamedKey::Space){let speed=self.state.session.as_ref().map_or(0,|s|if s.paused{s.speed}else{0});self.hud_action(HudCommand::Clock(speed));}
            self.dirty=true;return;
        }
        if self.loading(){return;}
        if key==Key::Named(NamedKey::F7) && !self.in_lobby() && self.written_world().is_some() && !self.hud.menu.modal() {
            if self.population_debug.take().is_none() {
                self.population_debug=Some(pop_debug_ui::Panel::default());
                if self.selected.is_some() {
                    self.population_location(self.selected);
                } else {
                    let id = self.written_world().map(|world| {
                        world.player_current_place().unwrap_or_else(|| world.last_station()).to_owned()
                    }).unwrap_or_else(|| "world".into());
                    self.inspect_population(id);
                }
            }
            self.dirty=true;
            return;
        }
        if let Some(panel)=&mut self.population_debug {
            match key {
                Key::Named(NamedKey::Escape)=>self.population_debug=None,
                Key::Named(NamedKey::Enter)=>{
                    let query=if panel.input.trim().is_empty() {panel.query.clone()} else {panel.input.trim().to_owned()};
                    if query != panel.query { panel.place_name = None; }
                    self.inspect_population(query);
                }
                Key::Named(NamedKey::Tab)=>{
                    let page = panel.next_page();
                    self.population_page(page);
                }
                Key::Named(NamedKey::Backspace)=>{panel.input.pop();}
                Key::Named(NamedKey::Delete)=>panel.input.clear(),
                Key::Named(NamedKey::ArrowUp)=>panel.scroll_by(-1),
                Key::Named(NamedKey::ArrowDown)=>panel.scroll_by(1),
                Key::Named(NamedKey::PageUp)=>panel.scroll_by(-12),
                Key::Named(NamedKey::PageDown)=>panel.scroll_by(12),
                Key::Named(NamedKey::Home)=>panel.scroll=0,
                Key::Named(NamedKey::Space)=>{
                    let speed=self.state.session.as_ref().map_or(0,|s|if s.paused{s.speed}else{0});
                    self.hud_action(HudCommand::Clock(speed));
                }
                Key::Character(value)=>{
                    for ch in value.chars().filter(|ch|ch.is_ascii_alphanumeric()||matches!(ch,'_'|':'|'-'|'.')) {
                        if panel.input.len()<160 {panel.input.push(ch);}
                    }
                }
                _=>{}
            }
            self.dirty=true;
            return;
        }
        if self.opening_transition_active() {return;}
        if self.in_lobby(){
            if self.country_directory.search_active {
                match key {
                    Key::Named(NamedKey::Escape|NamedKey::Enter)=>{
                        self.country_directory.search_active=false;
                        if let Some(window)=&self.window {window.set_ime_allowed(false);}
                        self.dirty=true;
                    }
                    Key::Named(NamedKey::Backspace)=>{
                        self.country_directory.query.pop();
                        self.opening_nav.offset = 0;
                        self.filter_countries();
                    }
                    Key::Named(NamedKey::Space)=>self.type_country_search(" "),
                    Key::Character(text)=>self.type_country_search(&text),
                    _=>(),
                }
                return;
            }
            if matches!(key,Key::Named(NamedKey::Escape|NamedKey::Backspace))&&!self.lobby_request{
                let command = match self.lobby_page {
                    lobby::Page::Prologue => lobby::Command::PrologueBack,
                    lobby::Page::Cloud => return,
                    lobby::Page::Selection => lobby::Command::Back,
                    _ => lobby::Command::Page(lobby::Page::Home),
                };
                self.lobby_action(command);
            } else if key==Key::Named(NamedKey::Enter)&&!self.lobby_request {
                if let Some(state)=&self.state.lobby{
                    if !state.busy {
                        match self.lobby_page {
                            lobby::Page::Home if state.ready=>self.lobby_action(lobby::Command::Page(lobby::Page::Selection)),
                            lobby::Page::Selection=>self.lobby_action(lobby::Command::Enter),
                            lobby::Page::Prologue=>self.lobby_action(lobby::Command::PrologueNext),
                            _=>(),
                        }
                    }
                }
            }
            return;
        }
        if key==Key::Named(NamedKey::Escape)&&self.hud.menu==HudMenu::Departure{
            self.hud_action(HudCommand::Departure("departure:cancel"));self.dirty=true;return;
        }
        if self.hud.quantity.is_some() {
            match &key {
                Key::Named(NamedKey::Escape)=>self.hud.quantity=None,
                Key::Named(NamedKey::Enter)=>self.market_command("requote",0),
                Key::Named(NamedKey::Backspace)=>{self.hud.quantity.as_mut().unwrap().pop();},
                Key::Character(value)=>{
                    let input=self.hud.quantity.as_mut().unwrap();
                    if input.len()<16&&value.bytes().all(|b|b.is_ascii_digit()||b==b'.'){input.push_str(value);}
                }
                _=>(),
            }
            self.dirty=true;return;
        }
        if let Some(query)=self.hud.market_search.as_mut() {
            match key {
                Key::Named(NamedKey::Escape)=>{
                    self.hud.market_search=None;
                    if let Some(window)=&self.window {window.set_ime_allowed(false);}
                },
                Key::Named(NamedKey::Backspace)=>{query.pop();self.hud.market_offset=0;}
                Key::Named(NamedKey::Space)=>self.type_market_search(" "),
                Key::Character(value)=>self.type_market_search(&value),
                _=>(),
            }
            self.dirty=true;
            return;
        }
        if self.hud.market_map && key==Key::Named(NamedKey::Escape) {
            self.market_command("market_back",0);
            self.dirty=true;
            return;
        }
        if self.hud.transport_directory.is_some() && !self.hud.menu.modal() {
            match key {
                Key::Named(NamedKey::Escape)=>{
                    self.hud.transport_directory=None;
                    if let Some(window)=&self.window {window.set_ime_allowed(false);}
                },
                Key::Named(NamedKey::Backspace)=>{
                    self.hud.transport_directory.as_mut().unwrap().pop();
                    self.transport_search();
                }
                Key::Named(NamedKey::Enter)=>self.transport_command("destination",0),
                Key::Named(NamedKey::Space)=>self.type_transport_search(" "),
                Key::Character(value)=>self.type_transport_search(&value),
                _=>(),
            }
            self.dirty=true;
            return;
        }
        if self.search.is_some() {
            match key {
                Key::Named(NamedKey::Escape)=>self.search=None,
                Key::Named(NamedKey::Backspace)=>{self.search.as_mut().unwrap().pop();}
                Key::Named(NamedKey::Enter)=>self.accept_search(),
                Key::Character(value) if self.search.as_ref().unwrap().len()<60=>self.search.as_mut().unwrap().push_str(&value),
                _=>(),
            }
            self.dirty=true;return;
        }
        if self.hud.menu.modal() && !matches!(&key,Key::Named(NamedKey::Escape)){return;}
        if key==Key::Named(NamedKey::Enter) && self.military_grid_active() && self.military_cell.is_some(){
            self.enter_selected_battle();return;
        }
        if key==Key::Named(NamedKey::Escape) && self.battle_enter_requested.take().is_some(){
            self.feedback.clear();
            self.dirty=true;
            return;
        }
        if matches!(&key, Key::Character(value) if value == "]")
            && self.debug && self.hud.page == HudPage::Map && self.hud.menu == HudMenu::None && self.country.is_none()
            && self.transport_scene.as_mut().is_some_and(|scene| scene.next_corridors(self.cursor)) {
            self.dirty = true;
            return;
        }
        if let Some(s)=self.state.session.as_ref(){
            let speed=match &key {
                Key::Character(v)=>match v.as_str(){
                    "0"=>Some(0),"1"=>Some(1),"2"=>Some(2),"3"=>Some(3),"4"=>Some(4),
                    "+"|"="=>Some(formal_ui::CLOCK_SPEEDS[(self.hud.mechanical.selected(formal_ui::clock_index(Some(s)))+1).min(formal_ui::CLOCK_SPEEDS.len()-1)]),
                    "-"=>{
                        let index=self.hud.mechanical.selected(formal_ui::clock_index(Some(s))).saturating_sub(1);
                        let speed=formal_ui::CLOCK_SPEEDS[index];
                        Some(if speed==3 && self.config.requests.is_some(){2}else{speed})
                    },_=>None,
                },_=>None,
            };
            if let Some(speed)=speed{self.action(Action::Hud(HudCommand::Clock(speed)));return;}
            if let Key::Named(NamedKey::F5|NamedKey::F9)=&key {
                self.action(Action::Hud(HudCommand::Menu(if key==Key::Named(NamedKey::F5){HudMenu::Save}else{HudMenu::Load})));return;
            }
            if matches!(&key,Key::Named(NamedKey::F1|NamedKey::F2|NamedKey::F3|NamedKey::F4|NamedKey::F6|NamedKey::F7)){return;}
        }
        // R68 keeps the formal clock shortcuts in the system menu; map actions stay out.
        if self.hud.menu!=HudMenu::None && !matches!(&key,Key::Named(NamedKey::Escape|NamedKey::Space)){return;}
        let year=self.state.date.year;
        match key {
            Key::Named(NamedKey::Home)=>self.action(Action::Home),
            Key::Named(NamedKey::Escape)=>if self.hud.clock_drag.take().is_some(){}else if self.hud.menu!=HudMenu::None{self.hud_action(HudCommand::Menu(HudMenu::None));}else if self.country.is_some(){self.country_action(CountryAction::Close);}else if self.hud.messages{self.hud.messages=false;}else if self.hud.page!=HudPage::Map{self.hud_action(HudCommand::Page(HudPage::Map));}else if self.details{self.details=false;}else if self.transport_selection.is_some(){self.select_transport(None);}else{self.hud.menu=HudMenu::System;},
            Key::Named(NamedKey::Backspace) if self.country.is_some()=>self.country_action(CountryAction::Back),
            Key::Named(NamedKey::Backspace) if self.hud.page==HudPage::Relations=>{
                let has_detail=self.state.session.as_ref().and_then(|s|s.relations.as_ref())
                    .is_some_and(|view|!view.selected.is_empty());
                self.hud_action(if has_detail{HudCommand::Relation(None)}else{HudCommand::Page(HudPage::Map)});
            }
            Key::Named(NamedKey::Backspace)=>self.action(Action::Back),
            Key::Named(NamedKey::F1)=>self.set_date(Date::new(year,1,20)),
            Key::Named(NamedKey::F2)=>self.set_date(Date::new(year,4,20)),
            Key::Named(NamedKey::F3)=>self.set_date(Date::new(year,7,20)),
            Key::Named(NamedKey::F4)=>self.set_date(Date::new(year,10,20)),
            Key::Named(NamedKey::F5)=>self.set_date(Date::new(1900,7,20)),
            Key::Named(NamedKey::F6)=>self.set_date(Date::new(1950,7,20)),
            Key::Named(NamedKey::F7)=>self.set_date(Date::new(2000,7,20)),
            Key::Named(NamedKey::Space)=>{
                self.hud.clock_drag=None;
                if self.state.session.is_some(){let speed=self.state.session.as_ref().map_or(0,|s|if s.paused{s.speed}else{0});self.hud_action(HudCommand::Clock(speed));}
                else if self.config.world.is_none(){self.animate=!self.animate;}
            }
            Key::Named(NamedKey::Tab)=>if let Some(test)=&self.state.timeline {self.site=(self.site+1)%test.sites.len();},
            Key::Character(value)=>match value.to_ascii_lowercase().as_str() {
                "g"=>self.action(Action::Mode(Mode::Geographic)),"p"=>self.action(Action::Mode(Mode::Political)),
                "e"=>self.action(Action::Mode(Mode::Economic)),"/"=>self.action(Action::Search),
                "t"=>self.theme=!self.theme,"n"=>self.labels=!self.labels,"["=>self.set_date(self.state.date.offset(-1)),"]"=>self.set_date(self.state.date.offset(1)),
                "v" if self.landmarks.is_some()&&self.hud.page==HudPage::Map=>{
                    self.focus=None;self.velocity=[0.;2];self.camera.toggle_oblique(self.size);
                }
                "r"=>{self.camera.north_up();},"1" if self.state.session.is_none()=>self.locate([11.12108,46.06787],260.),
                "2" if self.state.session.is_none()=>self.locate([2.3522,48.8566],33.),"3" if self.state.session.is_none()=>self.locate([8.94439,44.40478],125.),
                "l"=>if let Some(test)=&self.state.timeline {let q=test.sites[self.site].center_lon_lat;self.locate(q,12.);},
                "u"|"y"|"z"=>if let Some(test)=&mut self.state.timeline {
                    match value.to_ascii_lowercase().as_str() {"z"=>test.undo(self.site),"y"=>test.edit(self.site,true),_=>test.edit(self.site,false)}
                },
                _=>(),
            },
            _=>(),
        }
        self.dirty=true;
    }
    fn reload_debug_resources(&mut self) {
        let Some(renderer)=self.renderer.as_mut()else{return;};
        let data=&self.config.root;
        let overrides=data.join("debug-resources");
        let mut messages=Vec::new();
        let mut failures=Vec::new();
        let mut report=|name:&str,result:io::Result<bool>|match result {
            Ok(true)=>messages.push(name.to_owned()),
            Ok(false)=>{},
            Err(error)=>failures.push(format!("{name} · {error}")),
        };
        report("Shader",renderer.reload_map_shader(&overrides));
        report("地表贴图",renderer.reload_land_texture(&overrides));
        report("主题",self.menu_themes.reload(data).and_then(|value|{
            if let Some((themes,image))=value {
                renderer.reload_menu_painting(image)?;
                self.menu_themes=themes;
                Ok(true)
            } else {Ok(false)}
        }));
        let model=overrides.join("urban_landscape_r40.glb");
        if let Some(landmarks)=&mut self.landmarks {
            report("城市模型",match fs::read(&model) {
                Ok(bytes)=>landmarks.reload_city_models(&bytes).map(|()|{renderer.replace_city_models(bytes);true}),
                Err(error) if error.kind()==io::ErrorKind::NotFound=>Ok(false),
                Err(error)=>Err(error),
            });
        }
        let city_path=data.join("city-models");
        if city_path.join("catalogue.json").is_file() || self.city_models.is_some() {
            report("城市分片",crate::city_models::Catalogue::reload(city_path,self.city_models.as_ref(),&self.camera,self.size)
                .map(|candidate|{self.city_models=Some(candidate);true}));
        }
        self.resource_warnings.retain(|warning|!warning.starts_with("Reload · "));
        if !failures.is_empty() {
            self.resource_warnings.extend(failures.iter().map(|error|format!("Reload · {error}")));
            #[cfg(windows)] crate::desktop_start::write_runtime_log(&self.resource_warnings.join("\n"));
        }
        let status=if !failures.is_empty(){format!("热加载失败 · {} · F10",failures[0].lines().next().unwrap_or(""))}
            else if messages.is_empty(){"没有可热加载的资源".into()}
            else {format!("已热加载 · {}",messages.join("、"))};
        self.screenshot_status=Some((Instant::now(),status));
        self.dirty=true;
    }

    pub(super) fn world_view_changed(&mut self, had_session:bool, loaded:bool, now:Instant) {
        self.last_palette=None;
        let connected=self.state.session.is_some();
        if self.config.managed&&(had_session!=connected||loaded){
            self.battle_view = None;
            self.population_debug=None;
            self.transport_scene = None;
            self.select_transport(None);
            self.military_cell=None;
            self.battle_enter_requested=None;
            self.battle_terrain_wanted=None;
            if let Some(region)=self.written_world().filter(|world|world.land_battle_in_progress()).and_then(|world|world.land_battle_region()) {
                if let Err(error)=self.request_battle_terrain(region){self.feedback=error.to_string();}
            } else {
                self.battle_terrain = None;
                self.battle_terrain_timing = None;
                if let Some(renderer) = &mut self.renderer { renderer.clear_battle(); }
            }
            if connected && self.lobby_page == lobby::Page::Prologue {
                self.opening_nav.departure_cloud = None;
                self.opening_nav.arrival_cloud = Some(now);
            } else if connected {
                self.loading_fade = Some(now);
                self.loading_status = "正在安装地图".into();
            }
            self.prologue = None;
            self.hud=Hud{fullscreen:self.hud.fullscreen,volume:self.hud.volume,english:self.hud.english,..Hud::default()};
            self.selected=None;self.details=false;self.country=None;self.country_click=None;
            self.search=None;self.history.clear();self.focus=None;self.velocity=[0.;2];self.hits.clear();
            self.mode=Mode::Political;
            self.camera.reset(self.size);
            self.camera.local_models=self.landmarks.is_some();
            if let Some(point)=self.state.session.as_ref().and_then(|s| <[f64;2]>::try_from(s.coordinates.as_slice()).ok()) {
                #[cfg(windows)]
                if self.config.native.is_some() {self.camera.focus(point,1400.,self.size);}
                #[cfg(not(windows))]
                let _=point;
            }
            self.lobby_page=lobby::Page::Home;self.lobby_request=false;
            self.country_directory=lobby::Directory::default();
            self.departure_requested=false;
        }
        if let Some(lobby)=&self.state.lobby{
            self.seen_lobby_busy|=lobby.busy;
            if self.lobby_request&&!lobby.busy&&(self.seen_lobby_busy||!lobby.status.is_empty()){self.lobby_request=false;}
        }
        if let Some(s)=&self.state.session{
            if !s.departure.is_empty(){self.hud.menu=HudMenu::Departure;}
            else if self.hud.menu==HudMenu::Departure{self.hud.menu=HudMenu::None;}
            if self.hud.waiting_slot {
                if !s.slot_open {self.hud.waiting_slot=false;self.hud.menu=HudMenu::None;}
                else if !s.slot_error.is_empty() {self.hud.waiting_slot=false;}
            }
        }
        if self.hud.page==HudPage::Market {
            self.hits.clear();
            if let Some(target)=self.state.session.as_ref().and_then(|s|s.market.as_ref()).and_then(|market|market.focus) {
                self.apply_market_focus(target);
            }
        }
        if self.selected.is_some_and(|o|!self.available(o)){self.selected=None;self.details=false;self.country=None;}
    }

    pub(super) fn poll(&mut self,event_loop:&ActiveEventLoop,now:Instant) {
        #[cfg(windows)]
        if let Some(desktop)=&mut self.config.desktop {desktop.poll();}
        if self.exit_requested {event_loop.exit();return;}
        if self.country_click.as_ref().is_some_and(|click|now>=click.deadline) {
            let click=self.country_click.take().unwrap();
            self.open_country(click.polity);
        }
        if let Some(focus)=self.focus.take() {
            let progress=(now.saturating_duration_since(focus.start).as_secs_f64()/0.85).min(1.);
            let t=if progress<0.5 {4.*progress.powi(3)} else {1.-4.*(1.-progress).powi(3)};
            let level=self.camera.level;
            let screen_offset = self.camera.screen_offset_x;
            self.camera=focus.camera.clone();
            self.camera.level=level;
            self.camera.screen_offset_x = screen_offset;
            self.camera.focus_toward(focus.target,t,focus.mpp);
            self.dirty=true;
            if progress<1. {self.focus=Some(focus);}
        }
        if self.trial.timing&&self.trial.times.len()>=36_000 {self.trial.timing=false;}
        if let Some((from,to,steps,mut i))=self.trial.movement.take() {
            let lerp=|t:f64|[from[0]+(to[0]-from[0])*t,from[1]+(to[1]-from[1])*t];
            let a=lerp(f64::from(i)/f64::from(steps));let b=lerp(f64::from(i+1)/f64::from(steps));self.rotate(a,b,false);
            i+=1;if i<steps{self.trial.movement=Some((from,to,steps,i));}
        }
        if self.drag.is_none() && self.velocity[0].hypot(self.velocity[1])>9. {
            let dt=now.duration_since(self.moved_at).as_secs_f64().min(0.035);
            let center=self.size.map(|x|f64::from(x)/2.);
            let end=[center[0]+self.velocity[0]*dt,center[1]+self.velocity[1]*dt];
            self.rotate(center,end,false);
            self.velocity=self.velocity.map(|v|v*(-dt*7.8).exp());self.moved_at=now;
        }
        if self.animate&&now>=self.next_date {
            self.next_date=now+Duration::from_millis(85);self.set_date(self.state.date.offset(1));
        }
        if now.duration_since(self.last_input_check)>=Duration::from_millis(120) {
            self.last_input_check=now;
            if let Some(path)=&self.config.world {
                if self.config.managed&&path.with_file_name("bridge-exited").exists(){
                    if self.departure_requested{event_loop.exit();return;}
                    self.state.session=None;self.state.lobby=None;self.lobby_page=lobby::Page::Home;
                    self.feedback="R68 兼容进程已退出。".into();self.dirty=true;
                }
                let version=if self.config.managed&&path.with_file_name("bridge-exited").exists(){None}
                    else{fs::metadata(path).and_then(|m|m.modified()).ok()};
                if version.is_some()&&version!=self.version {
                    let had_session=self.state.session.is_some();
                    match self.state.input(path,&self.world){
                        Ok(())=>{
                            self.version=version;self.feedback.clear();
                            self.world_view_changed(had_session,false,now);
                        }
                        Err(e)=>self.feedback=format!("World snapshot: {e}"),
                    }
                    self.dirty=true;
                }
            }
            if self.lobby_request&&now.duration_since(self.bridge_wait)>Duration::from_secs(90){
                self.lobby_request=false;self.feedback="正在等待 R68，检查兼容进程日志。".into();self.dirty=true;
            }
            self.observe(event_loop);
        }
        #[cfg(windows)]
        if let Some(native)=&mut self.config.native {
            let terrain=self.battle_terrain.as_ref().map(|(cell,terrain)|(*cell,terrain));
            let controls=self.battle_view.as_ref().map(battle_view::View::controls).unwrap_or_default();
            let before=self.battle_view.as_ref().and_then(|_|native.active_world()?.land_battle())
                .map(|battle|(battle.elapsed_steps(),battle.selected_ammunition()));
            let result=native.tick(now,terrain,controls).and_then(|changed| {
                if changed {native.update_after_tick(&mut self.state)?;}
                Ok(changed)
            });
            if let (Some((steps,ammunition)),Some(view),Some((_,terrain)),Some(battle))=(before,&mut self.battle_view,terrain,
                native.active_world().and_then(|world|world.land_battle()))
            {
                if steps!=battle.elapsed_steps() {view.after_step(battle,terrain,ammunition);}
            }
            match result {
                Ok(changed)=>self.dirty|=changed,
                Err(error)=>{
                    let _=native.update_view(&mut self.state);
                    self.feedback=format!("游戏时钟推进失败：{error}");self.dirty=true;
                }
            }
        }
        self.refresh_population_debug();
        #[cfg(windows)]
        if let Some(desktop) = &mut self.config.desktop {
            if let Err(error) = desktop.tick_clock(self.state.session.as_ref(), now) {
                self.feedback = format!("游戏时钟推进请求失败：{error}");
                self.dirty = true;
            }
        }
    }
}

impl ApplicationHandler<HostEvent> for Host {
    fn resumed(&mut self,event_loop:&ActiveEventLoop) {
        if self.renderer.is_some(){return;}
        let result=(|| -> Result<_,Box<dyn std::error::Error>>{
            let window=if self.config.terrain_review {None} else {
                let mut attributes=Window::default_attributes().with_title(crate::build_identity::window_title())
                    .with_inner_size(PhysicalSize::new(VIEW_SIZE[0],VIEW_SIZE[1])).with_min_inner_size(LogicalSize::new(800.,480.))
                    .with_fullscreen((self.hud.fullscreen&&!self.config.background).then_some(winit::window::Fullscreen::Borderless(None)));
                if self.config.background {attributes=attributes.with_active(false).with_position(winit::dpi::PhysicalPosition::new(10000,10000));}
                Some(Arc::new(event_loop.create_window(attributes)?))
            };
            if let Some(window)=&window {self.size=window.inner_size().into();}
            self.camera=Camera::new(self.size);
            self.camera.local_models=self.landmarks.is_some();
            let mut layouts=Vec::new();
            if self.state.timeline.is_some() {
                let file=File::open(self.config.root.join("land-layout.rgba.z"))?;
                flate2::read::ZlibDecoder::new(file).take(524289).read_to_end(&mut layouts)?;
                if layouts.len()!=524288{return Err(io::Error::other("invalid simulation layout").into());}
            }
            let blank = || Raster { size: [1, 1], pixels: vec![0; 4] };
            let painting=self.config.managed.then(||self.menu_themes.start(&self.config.root)).flatten();
            if painting.is_some(){self.save_preferences();}
            let opening_asset = |data: &[u8]| {
                if self.config.managed { decode_rgba(data) } else { Ok(blank()) }
            };
            let hud=[font(&self.config.root.join("hud-art.png"))?,hud_type_atlas(&self.config.root.join("hud-type.png"))?,
                painting.unwrap_or_else(blank),
                opening_asset(include_bytes!("../../../../data/character/prologue/parchment.png"))?,
                opening_asset(include_bytes!("../../../../data/character/prologue/cloud.png"))?];

            let art=|name| {
                if self.map_signature.is_some() {decode_rgba(map_release::open_art(&self.map_root,name)?)}
                else {font(&self.map_root.join(name))}
            };
            let flags=if self.map_signature.is_some() {
                PoliticalVisuals::decode_atlas(map_release::open_art(&self.map_root,"political-flags-hd.png")?)?
            } else {
                let hd=self.map_root.join("political-flags-hd.png");
                let path=if hd.is_file(){hd}else{self.map_root.join("political-flags.png")};
                PoliticalVisuals::read_atlas(&path)?
            };
            let globe_art=[art("galactic-chart.png")?,decode_rgba(&include_bytes!("../ocean-material.png")[..])?];
            let atlas=font(&self.config.root.join("type.png"))?;
            let detail=if self.natural.is_some() && self.config.terrain_close_sample.is_none()
                && matches!(self.config.terrain_selection,terrain::LayerSelection::Auto) {
                let (default_dir,_)=self.config.terrain_root();
                let default=default_dir.join(terrain_detail::FILE_NAME);
                if let Some(path)=&self.config.terrain_detail {
                    Some(terrain_detail::Catalogue::open(path)?)
                } else {
                    match terrain_detail::Catalogue::open(&default) {
                        Ok(catalogue)=>Some(catalogue),
                        Err(error)=>{
                            self.resource_warnings.push(format!("Terrain detail {} · {error}",default.display()));
                            None
                        }
                    }
                }
            }else{None};
            let renderer=if let Some(window)=&window {
                pollster::block_on(Renderer::new(window.clone(),atlas,flags,hud,globe_art,&layouts,self.natural.take(),detail,self.events.clone(),self.config.observe.is_some()))?
            } else {
                let sample=self.config.terrain_close_sample.as_deref().map(render::CloseSample::read).transpose()?;
                pollster::block_on(Renderer::new_offscreen(self.size,atlas,flags,hud,globe_art,&layouts,self.natural.take(),sample,detail,self.events.clone()))?
            };
            let pixels=Pixels::read_version(&self.map_root,&self.world.tiles[0],self.map_signature,self.reader.cover)?;
            #[cfg(windows)]
            if self.config.native.is_some() && !self.config.background {
                let exe=std::env::current_exe()?.display().to_string();
                crate::desktop_start::write_runtime_log(&format!(
                    "EXE: {exe}\nData: {}\nMap: {}\n{}",self.config.root.display(),
                    self.map_root.display(),self.resource_warnings.join("\n")
                ));
            }
            let base=renderer.upload(&self.world.tiles[0],pixels);
            Ok((window,renderer,base))
        })();
        match result {
            Ok((window,renderer,base))=>{
                self.window=window;self.renderer=Some(renderer);self.base=Some(base);
                if self.config.terrain_review {self.dirty=false;}
            }
            Err(e)=>{self.fatal_error=Some(e.to_string());event_loop.exit();}
        }
    }
    fn user_event(&mut self,event_loop:&ActiveEventLoop,event:HostEvent) {
        let event=match event {
            HostEvent::Map(event)=>event,
            HostEvent::BattleTerrain(region,result)=>{
                self.battle_terrain_ready(region,result);
                return;
            }
            HostEvent::Model(revision,key,mesh)=>{
                if let Some(renderer)=&mut self.renderer {
                    if let Err(error)=renderer.model_ready(revision,key,mesh) {
                        let source=if key.is_transport() {"交通 GLB"}else{"R68 GLB"};
                        self.feedback=format!("{source} · {error}");
                    }
                    self.dirty=true;
                }
                return;
            }
            HostEvent::CityTile(revision,index,result)=>{
                if let Some(catalogue)=&mut self.city_models {
                    if let Err(error)=catalogue.ready(revision,index,result) {
                        if self.resource_warnings.len()<24 { self.resource_warnings.push(error.to_string()); }
                    }
                    self.dirty=true;
                }
                return;
            }
            HostEvent::Terrain(event)=>{
                if let Some(renderer)=&mut self.renderer {
                    if self.trial.timing {
                        if let Ok(tile)=&event.result {
                            let terrain::Key(z,x,y)=event.key;
                            self.trial.loads.push((format!("terrain/{z}/{x}/{y}"),ms(event.requested)));
                            self.trial.terrain_decodes.push(tile.decode_time.as_secs_f64()*1000.);
                            if self.trial.profile_frames {self.trial.load_frames.push(self.trial.frames.len());}
                        }
                    }
                    if let Err(error)=renderer.terrain_ready(event) {
                        self.fatal_error=Some(error.to_string());event_loop.exit();return;
                    }
                    self.dirty=true;
                }
                return;
            }
            HostEvent::TerrainDetail(index,result)=>{
                if let Some(renderer)=&mut self.renderer {
                    renderer.close_terrain_ready(index,result);
                    self.dirty=true;
                }
                return;
            }
            HostEvent::Rivers(result)=>{
                if let Some(renderer)=&mut self.renderer {
                    renderer.rivers_ready(result);
                    self.dirty=true;
                }
                return;
            }
        };
        self.reader.inflight=None;
        match event.result {
            Ok(pixels)=>{
                if self.candidate.contains(&event.id) {
                    let tile=&self.world.tiles[event.id];
                    let page=self.renderer.as_ref().unwrap().upload(tile,pixels);
                    let now=Instant::now();
                    self.cached.insert(event.id,Resident{page,ready:now,used:now});
                    if self.trial.timing {
                        self.trial.loads.push((tile.path.clone(),ms(event.requested)));
                        if self.trial.profile_frames {self.trial.load_frames.push(self.trial.frames.len());}
                    }
                }
            }
            Err(e) if self.map_signature.is_some() && !self.world.tiles[event.id].city_ink_only=>{
                self.fatal_error=Some(format!("正式地图无法读取 {} · {e}",self.world.tiles[event.id].path));
                event_loop.exit();
            }
            Err(e)=>{
                self.failed.insert(event.id);
                if self.world.tiles[event.id].city_ink_only {
                    self.resource_warnings.push(format!("City ground {} · {e}",self.world.tiles[event.id].path));
                } else {
                    self.feedback=format!("Source tile unavailable: {e}");
                }
            }
        }
        self.dirty=true;
    }
    fn window_event(&mut self,event_loop:&ActiveEventLoop,_:WindowId,event:WindowEvent) {
        match event {
            WindowEvent::CloseRequested=>{
                if self.battle_view.is_some() { self.battle_command(battle_view::Command::Back); }
                if self.config.managed&&self.state.session.is_some(){self.hud_action(HudCommand::Departure("system:quit"));self.dirty=true;}
                else{event_loop.exit();}
            }
            WindowEvent::Resized(s) if s.width>0&&s.height>0=>{
                if self.in_lobby() && self.lobby_page == lobby::Page::Selection && self.camera.level == Level::World {
                    let previous = lobby::globe_mpp(self.size);
                    let resized = lobby::globe_mpp(s.into());
                    self.camera.set_scale(self.camera.mpp*resized/previous);
                }
                self.size=s.into();self.camera.constrain_region(self.size);
                if let Some(r)=self.renderer.as_mut(){r.resize(self.size);}self.dirty=true;
            }
            WindowEvent::RedrawRequested if self.renderer.is_some()=>{
                if let Err(e)=self.draw(){self.fatal_error=Some(e.to_string());event_loop.exit();}
            }
            WindowEvent::CursorMoved{position,..}=>{
                let next:[f64;2]=position.into();self.cursor=next;
                if let (Some(view), Some((_,terrain))) = (&mut self.battle_view, &self.battle_terrain) {
                    view.aim(next, self.size, terrain);
                    return;
                }
                if self.opening_nav.drawer_drag.is_some() {
                    if let Some(layout) = self.opening_layout() {
                        self.opening_nav.slide_drawer(&layout, next[1]);
                    }
                    self.dirty = true;
                    return;
                }
                if self.country_directory.drag.is_some(){
                    self.country_directory.slide(self.size,next[1]);self.dirty=true;return;
                }
                if self.hud.volume_drag {self.slide_volume();return;}
                if self.hud.clock_drag.is_some(){self.hud.clock_drag=Some(formal_ui::clock_angle(next,self.size[0]));self.dirty=true;return;}
                if let Some(mut d)=self.drag.take(){
                    if (next[0]-d.origin[0]).hypot(next[1]-d.origin[1])>3. {d.moved=true;self.country_click=None;}
                    if d.moved {
                        let now=Instant::now();let dt=now.duration_since(d.last).as_secs_f64().max(0.005);
                        if !d.bearing {
                            self.velocity=std::array::from_fn(|i|(0.55*self.velocity[i]+0.45*(next[i]-d.at[i])/dt).clamp(-2400.,2400.));
                        }
                        self.rotate(d.at,next,d.bearing);d.at=next;d.last=now;
                    }
                    self.drag=Some(d);
                }
                self.dirty=true;
            }
            WindowEvent::MouseInput{state,button,..} if matches!(button,MouseButton::Left|MouseButton::Right)=>{
                if self.opening_transition_active() {return;}
                if let (Some(view), Some((_,terrain))) = (&mut self.battle_view, &self.battle_terrain) {
                    let down = state == ElementState::Pressed;
                    if button == MouseButton::Left {
                        if let Some(command) = view.left_button(down, self.cursor, self.size, terrain) {
                            self.battle_command(command);
                        }
                    } else if down {
                        #[cfg(windows)]
                        if let Some(battle) = self.config.native.as_mut().and_then(native_start::NativeSession::active_world_mut)
                            .and_then(|world| world.land_battle_mut())
                        {
                            view.order(self.cursor, self.size, battle, terrain);
                        }
                    }
                    return;
                }
                if state==ElementState::Pressed {
                    if let Some(panel) = &self.population_debug {
                        self.focus = None;
                        self.velocity = [0.; 2];
                        self.drag = (!panel.contains(self.size, self.cursor)).then(|| Drag {
                            at: self.cursor, origin: self.cursor, last: Instant::now(),
                            bearing: button == MouseButton::Right, moved: false,
                        });
                        return;
                    }
                    if self.lobby_page != lobby::Page::Cloud { self.focus = None; }
                    self.opening_nav.last_input = Instant::now();
                    self.velocity=[0.;2];
                    if button == MouseButton::Left && self.in_lobby() && self.lobby_page == lobby::Page::Selection
                        && self.opening_nav.stage == lobby::SelectionStage::Profile && self.opening_nav.drawer && !self.loading()
                        && self.opening_layout().is_some_and(|layout| self.opening_nav.grab_drawer(&layout, self.cursor))
                    {
                        self.drag = None;
                        self.dirty = true;
                        return;
                    }
                    if button==MouseButton::Left&&self.in_lobby()&&self.lobby_page==lobby::Page::Selection
                        &&self.opening_nav.stage == lobby::SelectionStage::Directory
                        &&!self.loading()&&self.country_directory.grab(self.size,self.cursor)
                    {self.drag=None;self.dirty=true;return;}
                    if button==MouseButton::Left&&self.volume_slider().is_some_and(|[x,y,w,h]|{
                        self.cursor[0]>=x&&self.cursor[0]<=x+w&&self.cursor[1]>=y&&self.cursor[1]<=y+h
                    }) {self.hud.volume_drag=true;self.slide_volume();return;}
                    if button==MouseButton::Left&&self.hud.menu==HudMenu::None&&formal_ui::clock_hit(self.cursor,self.size[0],self.state.session.as_ref(),self.hud.mechanical.angle){
                        self.hud.clock_origin=Some(self.cursor);
                        self.hud.clock_drag=Some(self.hud.mechanical.angle.unwrap_or(formal_ui::clock_angle(self.cursor,self.size[0])));
                        self.dirty=true;return;
                    }
                    let clock_surface=formal_ui::clock_hit(self.cursor,self.size[0],self.state.session.as_ref(),self.hud.mechanical.angle);
                    self.drag=(!clock_surface&&!self.is_panel(self.cursor)).then(||Drag{
                        at:self.cursor,origin:self.cursor,last:Instant::now(),bearing:button==MouseButton::Right,moved:false});
                } else if self.population_debug.is_some() {
                    let drag = self.drag.take();
                    if drag.as_ref().is_some_and(|drag| drag.moved) {
                        self.moved_at = Instant::now();
                        self.velocity = [0.; 2];
                    } else if button == MouseButton::Left {
                        self.click(self.cursor);
                    } else if drag.is_some() {
                        self.population_polity_at(self.cursor);
                    }
                } else if button == MouseButton::Left && self.opening_nav.drawer_drag.take().is_some() {
                    self.dirty = true;
                } else if button==MouseButton::Left&&self.country_directory.drag.take().is_some() {
                    self.dirty=true;
                } else if button==MouseButton::Left&&self.hud.volume_drag {
                    self.slide_volume();self.hud.volume_drag=false;
                } else if button==MouseButton::Left&&self.hud.clock_drag.is_some() {
                    if self.hud.clock_origin.take().is_some_and(|p|(p[0]-self.cursor[0]).hypot(p[1]-self.cursor[1])<2.) {self.hud.clock_drag=None;}
                    if self.hud.menu==HudMenu::None {
                        let angle=formal_ui::clock_angle(self.cursor,self.size[0]);
                        self.action(Action::Hud(HudCommand::Clock(formal_ui::CLOCK_SPEEDS[formal_ui::clock_at(angle)])));
                    }
                } else if let Some(d)=self.drag.take() {
                    self.moved_at=Instant::now();
                    if d.last.elapsed()>Duration::from_millis(140)||!d.moved {self.velocity=[0.;2];}
                    if !d.moved&&!d.bearing{self.click(self.cursor);}
                } else if button==MouseButton::Left && !formal_ui::clock_hit(self.cursor,self.size[0],self.state.session.as_ref(),self.hud.mechanical.angle) {self.click(self.cursor);}
            }
            WindowEvent::MouseWheel{delta,..}=>{
                if self.opening_transition_active() {return;}
                self.country_click=None;
                let steps=match delta {MouseScrollDelta::LineDelta(_,y)=>f64::from(y),MouseScrollDelta::PixelDelta(p)=>p.y/96.};
                if let Some(view) = &mut self.battle_view { view.zoom(steps); self.dirty = true; return; }
                if self.scroll_population_debug(self.cursor,steps) {return;}
                if self.scroll_countries(self.cursor,steps) {return;}
                if self.scroll_place_filters(self.cursor,steps) {return;}
                let [w,h]=self.size.map(|n|n as f32);
                let [x,y,width,height]=formal_ui::message_rect([w,h],((h+16.)*0.5).max(190.));
                if self.hud.messages && (f64::from(x)..=f64::from(x+width)).contains(&self.cursor[0]) && (f64::from(y)..=f64::from(y+height)).contains(&self.cursor[1]){
                    self.action(Action::Hud(HudCommand::MessageScroll(-(steps.signum() as i32))));
                }else if (self.hud.transport_lots_open || matches!(self.hud.page,HudPage::Market|HudPage::Property|HudPage::Relations)) &&
                    formal_ui::page_rect(&self.hud,self.size).is_some_and(|[x,y,w,h]| (f64::from(x)..=f64::from(x+w)).contains(&self.cursor[0])&&(f64::from(y)..=f64::from(y+h)).contains(&self.cursor[1])) {
                    self.action(Action::Hud(HudCommand::MarketScroll(-(steps.signum() as i32)*3)));
                }else if !self.is_panel(self.cursor) {self.zoom(self.cursor,steps);}
            }
            WindowEvent::Ime(winit::event::Ime::Commit(text)) if self.hud.market_search.is_some()=>self.type_market_search(&text),
            WindowEvent::Ime(winit::event::Ime::Commit(text)) if self.hud.transport_directory.is_some()=>self.type_transport_search(&text),
            WindowEvent::Ime(winit::event::Ime::Commit(text)) if self.country_directory.search_active=>self.type_country_search(&text),
            WindowEvent::KeyboardInput {event, ..} if self.battle_view.is_some() => {
                if matches!(event.logical_key, Key::Named(NamedKey::F5 | NamedKey::F10 | NamedKey::F12)) {
                    if event.state == ElementState::Pressed && !event.repeat { self.key(event.logical_key); }
                } else if let (Some(view), Some((_,terrain))) = (&mut self.battle_view, &self.battle_terrain) {
                    if let Some(command) = view.key(event.logical_key, event.state, event.repeat, terrain) {
                        self.battle_command(command);
                    }
                }
            }
            WindowEvent::KeyboardInput{event,..} if event.state==ElementState::Pressed && !event.repeat=>self.key(event.logical_key),
            WindowEvent::Focused(false)=>{if let Some(view) = &mut self.battle_view {view.clear_controls();}
                self.drag=None;self.country_click=None;self.hud.volume_drag=false;self.dirty|=self.hud.clock_drag.take().is_some();
                self.dirty|=self.country_directory.drag.take().is_some();
                self.dirty |= self.opening_nav.drawer_drag.take().is_some();self.velocity=[0.;2];}
            _=>(),
        }
    }
    fn about_to_wait(&mut self,event_loop:&ActiveEventLoop) {
        let now=Instant::now();self.poll(event_loop,now);
        self.animate_opening(now);
        if self.hud.menu!=HudMenu::None {self.hud.clock_drag=None;}
        if let Some(s)=self.state.session.as_ref(){self.hud.mechanical.update(now,formal_ui::clock_index(Some(s)),s.clock_ack,self.hud.clock_drag,if s.paused{0}else{s.speed});}
        if self.screenshot_status.as_ref().is_some_and(|(at,_)|at.elapsed()>Duration::from_secs(7)){
            self.screenshot_status=None;self.dirty=true;
            if let Some(window)=&self.window{window.set_title(&crate::build_identity::window_title());}
        }
        if self.battle_view.is_some() {
            let next = self.last_present + Duration::from_millis(16);
            if self.dirty || now >= next {
                if let Some(window) = &self.window {window.request_redraw();}
            }
            event_loop.set_control_flow(ControlFlow::WaitUntil(next.max(now + Duration::from_millis(1))));
            return;
        }
        let fading=self.renderer.as_ref().is_some_and(Renderer::terrain_fading)||self.cached.values().any(|p|now.saturating_duration_since(p.ready)<Duration::from_millis(180));
        let expiry=self.cached.iter().any(|(id,p)|now.saturating_duration_since(p.used)>CACHE_TTL && !self.candidate.contains(id));
        let clock_animating=self.state.session.as_ref().is_some_and(|s|
            !self.hud.mechanical.hidden && (!s.paused || self.hud.mechanical.moving()));
        let animated=self.loading() || clock_animating;
        let transitioning = self.loading_fade.is_some_and(|t| t.elapsed() < Duration::from_millis(320))
            || self.opening_transition_active();
        if let Some(window)=&self.window {
            let periodic=(animated||transitioning||fading)&&now.saturating_duration_since(self.last_present)>=Duration::from_millis(if fading||transitioning{16}else{100});
            if self.dirty||expiry||periodic||(self.trial.timing&&!self.trial.passive_timing)||!self.trial.captures.is_empty()||self.screenshot.is_some(){window.request_redraw();}
        } else if self.config.terrain_review && self.renderer.is_some() {
            let pending=self.dirty||fading||(self.trial.timing&&!self.trial.passive_timing);
            let due=now.saturating_duration_since(self.last_present)>=Duration::from_millis(33);
            if (pending&&due)||self.trial.terrain_capture.is_some() {
                if let Err(error)=self.draw(){self.fatal_error=Some(error.to_string());event_loop.exit();}
            }
        }
        let opening_animation = self.in_lobby()
            && (self.opening_nav.shift.is_some() || self.lobby_page == lobby::Page::Cloud
                || self.lobby_page == lobby::Page::Prologue && self.prologue.as_ref().is_some_and(|draft| draft.changed.elapsed().as_millis() < 340));
        let fast=opening_animation||self.focus.is_some()||self.animate||(self.trial.timing&&!self.trial.passive_timing)||self.trial.movement.is_some()||self.velocity[0].hypot(self.velocity[1])>9.||fading;
        let frame=now+Duration::from_millis(if fast||transitioning{16}else if animated{50}else if self.state.session.as_ref().is_some_and(|s|!s.paused){50}else{120});
        let frame=if self.config.terrain_review && self.dirty {frame.min(self.last_present+Duration::from_millis(33))} else {frame};
        event_loop.set_control_flow(ControlFlow::WaitUntil(self.country_click.as_ref().map_or(frame,|click|frame.min(click.deadline))));
    }
}
