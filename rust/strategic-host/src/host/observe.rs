use super::Host;
use crate::{
    camera::{self, Camera, Level}, hydrology, market_ui, pop_debug_ui, render::Renderer,
    timeline, ui::{self, Action, Object},
};
#[cfg(windows)]
use crate::desktop_start;
use serde::Deserialize;
use std::{fs, io, path::PathBuf, time::{Instant, SystemTime}};
use winit::{event_loop::ActiveEventLoop, keyboard::{Key, NamedKey}};

#[derive(Default)]
pub(super) struct Trial {
    pub(super) last:String,pub(super) timing:bool,pub(super) passive_timing:bool,pub(super) times:Vec<f64>,pub(super) previous:Option<Instant>,pub(super) captures:Vec<PathBuf>,pub(super) first:Option<f64>,pub(super) loads:Vec<(String,f64)>,
    pub(super) terrain_decodes:Vec<f64>,
    pub(super) profile_frames:bool,
    pub(super) frames:Vec<FrameTiming>,
    pub(super) load_frames:Vec<usize>,
    pub(super) battle_openings:Vec<BattleOpeningTiming>,
    pub(super) movement:Option<([f64;2],[f64;2],u32,u32)>,
    pub(super) window_position:Option<winit::dpi::PhysicalPosition<i32>>,
    pub(super) terrain_capture:Option<(String,PathBuf)>,
    pub(super) hide_landscape_models:bool,
    pub(super) road_layer:u32,
}

#[derive(serde::Serialize)]
pub(super) struct BattleOpeningTiming {
    pub(super) frame:usize,
    pub(super) terrain_cpu_ms:f64,
    pub(super) terrain_pages:Vec<[u32;3]>,
    pub(super) terrain_worker_ms:Option<f64>,
    pub(super) terrain_wait_ms:f64,
    pub(super) scene_cpu_ms:f64,
    pub(super) original_vehicle_model:bool,
    pub(super) deployment_cpu_ms:f64,
    pub(super) total_cpu_ms:f64,
}

#[derive(serde::Serialize)]
pub(super) struct FrameTiming {
    interval_ms:Option<f64>,
    draw_wall_ms:f64,
    surface_acquire_ms:f64,
    center:[f64;2],
    mpp:f64,
    terrain_view_level:u32,
    qwg_upload:Option<hydrology::WaterUpload>,
    battle:bool,
}

impl Trial {
    pub(super) fn timing_frame(&self, capture:bool)->Option<usize> {
        (self.timing && self.profile_frames && !capture).then_some(self.frames.len())
    }

    pub(super) fn record_frame(&mut self, started:Instant, presented:Instant, camera:&Camera, renderer:&Renderer, battle:bool) {
        let interval = self.previous.map(|previous| presented.duration_since(previous).as_secs_f64()*1000.);
        if let Some(interval) = interval { self.times.push(interval); }
        self.previous = Some(presented);
        if self.profile_frames {
            self.frames.push(FrameTiming {
                interval_ms:interval,
                draw_wall_ms:presented.duration_since(started).as_secs_f64()*1000.,
                surface_acquire_ms:renderer.frame_acquire_ms,
                center:camera.coordinates(),
                mpp:camera.mpp,
                terrain_view_level:renderer.terrain_view_level(),
                qwg_upload:if battle {None} else {renderer.water_upload()},
                battle,
            });
        }
    }
}
#[derive(Deserialize)]
pub(super) struct Observation {
    pub(super) id:String,action:String,
    #[serde(default)] x:f64, #[serde(default)] y:f64,
    #[serde(default)] to_x:f64, #[serde(default)] to_y:f64,
    #[serde(default)] steps:f64, #[serde(default)] frames:u32,
    #[serde(default)] label:String,
    #[serde(default)] lon:f64, #[serde(default)] lat:f64, #[serde(default)] mpp:f64,
    #[serde(default)] value:String,
}
impl Host {
    pub(super) fn inspect_population(&mut self, query: String) {
        self.update_population_debug(query, true);
    }

    fn update_population_debug(&mut self, query: String, clear_input: bool) {
        let Some(mut panel)=self.population_debug.take() else{return;};
        if let Some(world) = self.written_world() {
            let population = world.population();
            let clock = world.clock();
            panel.revision = Some((clock.current_day(), population.journal_revision()));
            match world.inspect_population_brief(&query) {
                Ok(report) => {
                    let social = (report.population_total.is_some() && matches!(panel.page,
                        pop_debug_ui::Page::Structure | pop_debug_ui::Page::Needs))
                        .then(|| population.social_distribution(report.account_id)).flatten();
                    let needs = (panel.page == pop_debug_ui::Page::Needs)
                        .then(|| world.population_household_needs_with_social(&report, social.as_ref())).flatten();
                    let labour = (panel.page == pop_debug_ui::Page::Structure).then(|| {
                        report.structure.as_ref().map(|structure| {
                            population.labor_supply(report.account_id, structure, social.as_ref())
                        })
                    }).flatten();
                    let days = if panel.page == pop_debug_ui::Page::Changes && report.population_total.is_some() {
                        population.recorded_population_days(report.account_id, clock, 14)
                    } else {
                        Vec::new()
                    };
                    panel.set_report(&report, social.as_ref(), needs.as_ref(), labour.as_ref(), world.macro_economy(), days);
                }
                Err(_) => panel.set_error(),
            }
        } else {
            panel.set_error();
        }
        if panel.query != query { panel.reset_location(); }
        panel.query=query;
        if clear_input { panel.input.clear(); }
        self.population_debug=Some(panel);
        self.dirty=true;
    }

    pub(super) fn refresh_population_debug(&mut self) {
        let Some(panel) = &self.population_debug else { return; };
        let Some(world) = self.written_world() else { return; };
        let revision = (world.clock().current_day(), world.population().journal_revision());
        if panel.revision != Some(revision) {
            self.update_population_debug(panel.query.clone(), false);
        }
    }

    pub(super) fn population_page(&mut self, page: pop_debug_ui::Page) {
        let Some(panel) = self.population_debug.as_mut().filter(|panel| panel.page != page) else { return; };
        panel.page = page;
        panel.scroll = 0;
        let query = panel.query.clone();
        self.inspect_population(query);
    }

    pub(super) fn population_location(&mut self, object: Option<Object>) {
        let (query, name) = object.map(|object| {
            let name = ui::object_name(&self.world, &self.skin, object);
            (self.id(object), Some(name.to_owned()))
        }).unwrap_or_else(|| ("unmapped".into(), None));
        if let Some(panel) = &mut self.population_debug {
            panel.place_name = name;
            panel.reset_location();
        }
        self.inspect_population(query.strip_prefix("state:").unwrap_or(&query).to_owned());
    }

    pub(super) fn population_polity_at(&mut self, point: [f64; 2]) {
        let polity = self.camera.vector(point, self.size)
            .and_then(|v| self.object_at(camera::geographic(v))[0].checked_sub(1))
            .map(|index| Object::Polity(usize::from(index)))
            .filter(|&object| self.available(object));
        self.population_location(polity);
    }

    pub(super) fn scroll_population_debug(&mut self, point:[f64;2], steps:f64)->bool {
        let Some(panel)=self.population_debug.as_mut().filter(|panel|panel.contains(self.size,point)) else{return false;};
        panel.scroll_by(-(steps.signum() as isize)*3);
        self.dirty=true;
        true
    }

    pub(super) fn queue_screenshot(&mut self) {
        if self.screenshot.is_some(){return;}
        self.screenshot_status=None;
        let result=(|| -> io::Result<PathBuf> {
            let dir=std::env::var_os("LOCALAPPDATA").map(|p|PathBuf::from(p).join("WWO-Rust-Candidate"))
                .unwrap_or_else(||self.config.root.parent().unwrap_or(&self.config.root).to_path_buf()).join("screenshots");
            fs::create_dir_all(&dir)?;
            let stamp=SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).map_err(io::Error::other)?.as_millis();
            Ok(dir.join(format!("WWO-{stamp}-{}.png",std::process::id())))
        })();
        match result {
            Ok(path)=>self.screenshot=Some(path),
            Err(e)=>self.screenshot_status=Some((Instant::now(),format!("截图失败: {e}"))),
        }
        self.dirty=true;
    }
    fn status(&self)->serde_json::Value {
        let world = self.written_world();
        let session=self.state.session.as_ref().map(|s|{
            let market=s.market.as_ref().map(market_ui::Market::status);
            serde_json::json!({"player":s.player,"time":[s.hour,s.minute],"total_minutes":s.total_minutes,"paused":s.paused,"speed":s.speed,
                "subminute_millis":world.map(|world|world.clock().snapshot().subminute_millis),
                "finance":s.finance.summary,"message_count":s.messages.len(),"slots":s.slots.len(),"market":market,"training":s.training,
                "character":s.character,
                "property":s.property.iter().map(|r|(&r.id,r.quantity)).collect::<Vec<_>>(),"departure":s.departure })
        });
        let lobby=self.state.lobby.as_ref().map(|s|serde_json::json!({"page":format!("{:?}",self.lobby_page),"ready":s.ready,
            "selection_ready":s.selection_ready,"busy":s.busy,"status":s.status,
            "opening_stage": format!("{:?}", self.opening_nav.stage),
            "opening_polity": self.opening_choice().map(|row| &row.id),
            "birthplace_drawer": self.opening_nav.drawer,
            "opening_area": self.opening_nav.path.last(),
            "birthplace": self.opening_choice().and_then(|row| row.sites.get(self.opening_nav.site?)).map(|site| &site.id),
            "prologue_chapter": self.prologue.as_ref().map(|draft| draft.stage + 1),
            "globe_center": 0.5 + self.camera.screen_offset_x,
            "slots":s.slots.iter().map(|s|(s.slot,s.can_read)).collect::<Vec<_>>()}));
        let land_battle=world.and_then(|world|{
            use wwo_map_lab::land_battle::LandTeam;
            let fixture=world.land_battle_record()?;
            let battle=&fixture.battle;
            let report=|team| {
                let r=battle.report(team);
                serde_json::json!({"operational":r.operational,"destroyed":r.destroyed,"ammunition":r.ammunition,"shots":r.shots,"hits":r.hits})
            };
            let history=world.land_battle_history().iter().map(|row|serde_json::json!({
                "id":row.id,"cell":row.cell(),"outcome":row.battle.outcome,"ended_minute":row.ended_minute,
                "ended_subminute_millis":row.ended_subminute_millis
            })).collect::<Vec<_>>();
            Some(serde_json::json!({"kind":"training_fixture","id":fixture.id,"cell":fixture.cell(),"region":fixture.region,
                "steps":battle.elapsed_steps(),"seconds":battle.elapsed_seconds(),"started_minute":fixture.started_minute,
                "ended_minute":fixture.ended_minute,"ended_subminute_millis":fixture.ended_subminute_millis,"history":history,
                "outcome":battle.outcome,"selected_unit":battle.selected_unit(),"friendly":report(LandTeam::Friendly),"opposing":report(LandTeam::Opposing),
                "view":self.battle_view.as_ref().map(|view|view.camera.span),"fps":self.debug.then_some(self.perf.rate)}))
        });
        serde_json::json!({
            "level":match self.camera.level{Level::World=>"WORLD",Level::Region=>"REGION",Level::Local=>"LOCAL"},
            "mode":self.mode.key(),"center":self.camera.coordinates(),"mpp":self.camera.mpp,"orientation":self.camera.axes,
            "viewport":self.size,"projection":if self.camera.blend()>0. {"azimuthal_equidistant"} else {"orthographic"},
            "pitch_degrees":self.camera.pitch().to_degrees(),
            "landmarks":self.renderer.as_ref().map(Renderer::resident_models),
            "model_instances":self.renderer.as_ref().map(Renderer::model_instances),
            "selection":self.selected.map_or(String::new(),|o|self.id(o)),"date":self.state.date.to_string(),
            "transport_selection":self.transport_selection,
            "population_debug":self.population_debug.as_ref().map(pop_debug_ui::Panel::status),
            "cache_bytes":self.cached.values().map(|p|p.page.bytes).sum::<usize>(),
            "base_bytes":self.base.as_ref().map_or(0,|p|p.bytes),"resident":self.cached.len(),
            "wanted":self.visible.len(),"ready":self.visible.iter().filter(|i|self.cached.contains_key(i)).count(),
            "inflight":self.reader.inflight.is_some(),"first_frame_ms":self.trial.first,
            "gpu":self.renderer.as_ref().map(|r|&r.gpu),"feedback":self.feedback,
            "terrain":self.renderer.as_ref().and_then(Renderer::terrain_status),
            "terrain_detail":self.renderer.as_ref().and_then(Renderer::close_terrain_status),
            "workspace":format!("{:?}",self.hud.page),"menu":format!("{:?}",self.hud.menu),"messages":self.hud.messages,
            "session":session,"lobby":lobby,
            "military_grid":{"active":self.military_grid_active(),"step_m":self.grid_step,"selected":self.military_cell.map(|selection|selection.cell),
                "terrain_ready":self.military_cell.zip(self.battle_terrain.as_ref()).is_some_and(|(selected,(loaded,_))|selected.cell.region()==*loaded),
                "enter_pending":self.battle_enter_requested.is_some()},
            "land_battle":land_battle,
            "window":{"background":self.config.background,"offscreen":self.config.terrain_review,"focused":self.window.as_ref().is_some_and(|w|w.has_focus()),"visible":self.window.as_ref().and_then(|w|w.is_visible())}
        })
    }
    pub(super) fn observe(&mut self,event_loop:&ActiveEventLoop) {
        let Some(path)=self.config.observe.clone() else{return;};
        let Ok(input)=timeline::read::<Observation>(&path,128*1024) else{return;};
        if input.id==self.trial.last||input.id.is_empty(){return;}
        self.trial.last=input.id.clone();
        let mut extra=serde_json::Value::Null;
        match input.action.as_str() {
            "window" if matches!(input.value.as_str(),"background"|"visible"|"foreground")=>{
                if let Some(window)=&self.window {
                    if input.value=="background" {
                        if !self.config.background {
                            self.trial.window_position=window.outer_position().ok();
                            window.set_fullscreen(None);
                            window.set_outer_position(winit::dpi::PhysicalPosition::new(10000,10000));
                            #[cfg(windows)] desktop_start::debug_release_focus(window);
                        }
                        self.config.background=true;
                        self.drag=None;self.hud.clock_drag=None;self.hud.clock_origin=None;
                        self.hud.volume_drag=false;self.velocity=[0.;2];
                    } else {
                        if self.config.background {
                            window.set_outer_position(self.trial.window_position.unwrap_or(winit::dpi::PhysicalPosition::new(80,80)));
                        }
                        self.config.background=false;
                        // Visible is deliberately non-activating. Only an explicit foreground request takes focus.
                        if input.value=="foreground" {
                            window.set_minimized(false);
                            window.set_fullscreen(self.hud.fullscreen.then_some(winit::window::Fullscreen::Borderless(None)));
                            window.focus_window();
                        }
                    }
                    self.dirty=true;
                }
            }
            "focus" if (-180. ..=180.).contains(&input.lon)&&(-90. ..=90.).contains(&input.lat)&&(10. ..=90_000.).contains(&input.mpp)=>{
                self.country_click=None;
                self.locate([input.lon,input.lat],input.mpp); if input.value=="north" {self.camera.north_up();}
            }
            "hover"=>{self.cursor=[input.x,input.y];self.dirty=true;}
            "click"=>self.click([input.x,input.y]),
            "wheel"=>{
                let point=[input.x,input.y];
                if !self.scroll_population_debug(point,input.steps) && !self.scroll_countries(point,input.steps)
                    && !self.scroll_place_filters(point,input.steps) {self.zoom(point,input.steps);}
            }
            "drag"=>{
                self.velocity=[0.;2];
                self.trial.movement=Some(([input.x,input.y],[input.to_x,input.to_y],input.frames.clamp(1,180),0));
            }
            "key"=>self.key(match input.value.as_str() {"Escape"=>Key::Named(NamedKey::Escape),"Space"|"space"=>Key::Named(NamedKey::Space),"Enter"=>Key::Named(NamedKey::Enter),"Home"=>Key::Named(NamedKey::Home),"Delete"=>Key::Named(NamedKey::Delete),"Backspace"=>Key::Named(NamedKey::Backspace),"ArrowUp"=>Key::Named(NamedKey::ArrowUp),"ArrowDown"=>Key::Named(NamedKey::ArrowDown),"ArrowLeft"=>Key::Named(NamedKey::ArrowLeft),"ArrowRight"=>Key::Named(NamedKey::ArrowRight),"PageUp"=>Key::Named(NamedKey::PageUp),"PageDown"=>Key::Named(NamedKey::PageDown),"F1"=>Key::Named(NamedKey::F1),"F2"=>Key::Named(NamedKey::F2),"F3"=>Key::Named(NamedKey::F3),"F4"=>Key::Named(NamedKey::F4),"F5"=>Key::Named(NamedKey::F5),"F6"=>Key::Named(NamedKey::F6),"F7"=>Key::Named(NamedKey::F7),"F8"=>Key::Named(NamedKey::F8),"F9"=>Key::Named(NamedKey::F9),"F10"=>Key::Named(NamedKey::F10),"F11"=>Key::Named(NamedKey::F11),"Tab"=>Key::Named(NamedKey::Tab),_=>Key::Character(input.value.into())}),
            "home"=>self.action(Action::Home),
            "north"=>{self.camera.north_up();self.dirty=true;}
            "capture" if !input.label.is_empty() && input.label.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-')=>{
                let screenshot=path.with_file_name(format!("{}.png",input.label));
                if self.config.terrain_review || input.value=="terrain-samples" {
                    self.trial.terrain_capture=Some((input.id,screenshot));
                    self.dirty=true;
                    return;
                }
                self.trial.captures.push(screenshot.clone());
                extra=serde_json::json!({"png":screenshot});self.dirty=true;
            }
            "terrain-samples"=>{
                extra=self.renderer.as_ref().and_then(|r|r.terrain_frame_samples(&self.camera,self.size))
                    .unwrap_or(serde_json::Value::Null);
            }
            "landscape-counts"=>{
                if let Some(renderer)=&self.renderer {
                    extra=match renderer.landscape_counts() {
                        Ok(counts)=>serde_json::json!({
                            "draw_calls":counts.draw_calls,
                            "instances":counts.by_mesh.iter().sum::<u32>(),
                            "by_mesh":counts.by_mesh,
                            "vertex_invocations":counts.vertex_invocations,
                            "gpu_ms":counts.gpu_ms,
                        }),
                        Err(error)=>serde_json::json!({"error":error.to_string()}),
                    };
                }
            }
            "landscape-models" if matches!(input.value.as_str(),"show"|"hide")=>{
                self.trial.hide_landscape_models=input.value=="hide";
                self.dirty=true;
            }
            "road-layer" if matches!(input.value.as_str(),"composite"|"vector"|"fallback"|"ground"|"cover")=>{
                self.trial.road_layer=match input.value.as_str() {
                    "vector"=>1,
                    "fallback"=>2,
                    "ground"=>3,
                    "cover"=>4,
                    _=>0,
                };
                self.dirty=true;
            }
            "timing"=>{
                self.trial.timing=!self.trial.timing;self.trial.previous=None;
                if self.trial.timing{
                    self.trial.passive_timing=input.value=="passive";
                    self.trial.profile_frames=input.value=="profile";
                    self.trial.frames.clear();
                    self.trial.load_frames.clear();
                    self.trial.battle_openings.clear();
                    if self.trial.profile_frames {
                        if let Some(renderer)=&mut self.renderer {renderer.start_frame_timing();}
                    }
                    self.trial.times.clear();
                    self.trial.loads.clear();
                    self.trial.terrain_decodes.clear();
                } else {
                    let gpu=self.renderer.as_mut().and_then(Renderer::finish_frame_timing);
                    extra=serde_json::json!({"interval_ms":self.trial.times,"tile_load_ms":self.trial.loads,
                        "terrain_decode_ms":self.trial.terrain_decodes,"frames":self.trial.frames,
                        "gpu_frame_ms":gpu,"load_frame_indices":self.trial.load_frames,
                        "battle_openings":self.trial.battle_openings});
                }
            }
            "quit"=>event_loop.exit(),
            _=>(),
        }
        let _=self.write_observation(&input.id,extra);
    }

    pub(super) fn write_observation(&self,id:&str,extra:serde_json::Value)->io::Result<()> {
        let Some(path)=&self.config.observe else{return Ok(());};
        let response=serde_json::json!({"id":id,"state":self.status(),"extra":extra});
        fs::write(path.with_extension("response.json"),serde_json::to_vec(&response)?)
    }
}
