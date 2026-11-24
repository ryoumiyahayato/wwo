#![cfg_attr(not(debug_assertions),windows_subsystem="windows")]
mod mechanical;
mod camera;
#[cfg(windows)]
mod desktop_start;
#[cfg(windows)]
mod native_start;
mod compact;
mod formal_ui;
mod market_ui;
mod lobby;
mod prologue_ui;
mod landmarks;
mod map_release;
mod migration_status;
mod interface;
mod overlay;
mod pop_debug_ui;
mod politics;
mod render;
mod state;
mod terrain;
mod terrain_detail;
mod transport_scene;
mod transport_ui;
mod hydrology;
mod landscape;
mod landscape_cover;
mod landscape_models;
mod timeline;
mod ui;
mod world;
mod battle_render;
mod battle_view;

use camera::{Camera,Level};
use compact::Raster;
use formal_ui::{Command as HudCommand,Hud,Menu as HudMenu,Page as HudPage,Skin};
use politics::PoliticalVisuals;
use render::{Edit,Page,Renderer,View};
use serde::Deserialize;
use state::{Request,State};
use std::{collections::{HashMap,HashSet},fs::{self,File},io::{self,Read},path::{Path,PathBuf},
          sync::Arc,time::{Duration,Instant,SystemTime}};
use timeline::Date;
use ui::{Action,CountryAction,CountryPanel,CountryView,Hit,Mode,Object,Ui};
use winit::{application::ApplicationHandler,dpi::{LogicalSize,PhysicalSize},event::{ElementState,MouseButton,MouseScrollDelta,WindowEvent},
            event_loop::{ActiveEventLoop,ControlFlow,EventLoop},keyboard::{Key,NamedKey},window::{Window,WindowId}};
use world::{Completion,Index,Pixels,Reader,World};
use wwo_map_lab::{battlefield_terrain::BattlefieldTerrain, military_grid::MilitaryCell};

enum HostEvent {
    Map(Completion),
    Terrain(terrain::Completion),
    TerrainDetail(usize,io::Result<Vec<u8>>),
    Rivers(io::Result<hydrology::Rivers>),
    Model(landmarks::ModelKey, io::Result<landmarks::ModelMesh>),
    BattleTerrain(MilitaryCell, io::Result<PreparedBattleTerrain>),
}

const CACHE_BUDGET:usize=112*1024*1024;
const CACHE_TTL:Duration=Duration::from_secs(2);
const VIEW_SIZE:[u32;2]=[1280,720];
const COUNTRY_DOUBLE_CLICK:Duration=Duration::from_millis(380);

struct Diagnostics {rate:f64,cpu_ms:f64,tiles:usize,visible:usize,mib:f64,streaming:bool}

struct Config {root:PathBuf,world:Option<PathBuf>,requests:Option<PathBuf>,scenario:Option<PathBuf>,observe:Option<PathBuf>,managed:bool,
    preferences:Option<PathBuf>,terrain_candidate:Option<PathBuf>,background:bool,
    terrain_review:bool,terrain_selection:terrain::LayerSelection,terrain_layer_candidate:Option<PathBuf>,
    terrain_close_sample:Option<PathBuf>,
    terrain_detail:Option<PathBuf>,
    battlefield_data:Option<PathBuf>,
    #[cfg(windows)] native:Option<native_start::NativeSession>,
    #[cfg(windows)] desktop:Option<desktop_start::DesktopSession>}
impl Config {
    fn parse()->io::Result<Self> {
        let home=std::env::current_exe()?.parent().unwrap().to_owned();
        let mut result=Self{root:home.join("data"),world:None,requests:None,scenario:None,observe:None,managed:false,preferences:None,terrain_candidate:None,background:false,
            terrain_review:false,terrain_selection:terrain::LayerSelection::Auto,terrain_layer_candidate:None,
            terrain_close_sample:None,terrain_detail:None,battlefield_data:None,
            #[cfg(windows)] desktop:None,
            #[cfg(windows)] native:None};
        let mut args=std::env::args_os().skip(1).peekable();
        #[cfg(windows)]
        let mut start_game=false;
        #[cfg(windows)]
        let mut map_comparison=false;
        #[cfg(windows)]
        let mut r68_comparison=false;
        while let Some(arg)=args.next() {
            let path=|args:&mut std::iter::Peekable<std::iter::Skip<std::env::ArgsOs>>| args.next().map(PathBuf::from).ok_or_else(||io::Error::other("missing argument path"));
            match arg.to_str() {
                Some("--data")=>result.root=path(&mut args)?,
                Some("--world-state")=>result.world=Some(path(&mut args)?),
                Some("--requests")=>result.requests=Some(path(&mut args)?),
                Some("--observe")=>result.observe=Some(path(&mut args)?),
                Some("--background")=>result.background=true,
                Some("--preferences")=>result.preferences=Some(path(&mut args)?),
                Some("--terrain-candidate")=>result.terrain_candidate=Some(path(&mut args)?),
                Some("--terrain-review")=>result.terrain_review=true,
                Some("--terrain-layer-candidate")=>result.terrain_layer_candidate=Some(path(&mut args)?),
                Some("--terrain-close-sample")=>result.terrain_close_sample=Some(path(&mut args)?),
                Some("--terrain-detail")=>result.terrain_detail=Some(path(&mut args)?),
                Some("--battlefield-data")=>result.battlefield_data=Some(path(&mut args)?),
                Some(flag @ ("--terrain-level"|"--terrain-max-level"))=>{
                    if !matches!(result.terrain_selection,terrain::LayerSelection::Auto){
                        return Err(io::Error::other("choose one terrain layer option"));
                    }
                    let z=args.next().and_then(|v|v.to_str()?.parse::<u32>().ok()).filter(|&z|z<=7)
                        .ok_or_else(||io::Error::other("terrain level must be an integer from 0 to 7"))?;
                    result.terrain_selection=if flag=="--terrain-level" {terrain::LayerSelection::Exact(z)} else {terrain::LayerSelection::Maximum(z)};
                }
                Some("--land-test")=>result.scenario=Some(home.join("scenario-land-test.json")),
                Some("--formal-menu")=>result.managed=true,
                #[cfg(windows)]
                Some("--play")=>start_game=true,
                #[cfg(windows)]
                Some("--map-comparison")=>map_comparison=true,
                #[cfg(windows)]
                Some("--r68")=>{start_game=true;r68_comparison=true;},
                _=>return Err(io::Error::other(format!("unknown argument {arg:?}"))),
            }
        }
        if result.terrain_review {
            #[cfg(windows)]
            if start_game||map_comparison {return Err(io::Error::other("--terrain-review has its own map entry point"));}
            if result.world.is_some()||result.requests.is_some()||result.scenario.is_some()||result.managed||result.preferences.is_some() {
                return Err(io::Error::other("--terrain-review cannot load world sessions or preferences"));
            }
            if result.observe.is_none(){return Err(io::Error::other("--terrain-review requires --observe"));}
            if result.terrain_detail.is_some() && (result.terrain_close_sample.is_some()
                || !matches!(result.terrain_selection,terrain::LayerSelection::Auto)) {
                return Err(io::Error::other("--terrain-detail uses automatic terrain selection"));
            }
            result.background=true;
            if result.terrain_candidate.is_none(){result.terrain_candidate=Some(result.root.join(terrain::COMPACT_VERSION));}
            return Ok(result);
        }
        if !matches!(result.terrain_selection,terrain::LayerSelection::Auto)||result.terrain_layer_candidate.is_some()
            ||result.terrain_close_sample.is_some() {
            return Err(io::Error::other("terrain layer options require --terrain-review"));
        }
        #[cfg(windows)]
        let standalone=map_comparison||result.world.is_some()||result.requests.is_some()||result.scenario.is_some()||result.managed;
        #[cfg(windows)]
        if start_game||!standalone {
            if standalone{return Err(io::Error::other("--play and --r68 manage their own world; standalone map options cannot be combined with them"));}
            result.managed=true;
            if r68_comparison {
                let desktop=desktop_start::DesktopSession::start(&home)?;
                result.world=Some(desktop.state.clone());result.requests=Some(desktop.requests.clone());
                result.preferences=Some(desktop.preferences.clone());
                result.desktop=Some(desktop);
            } else {
                let native=native_start::NativeSession::start(&result.root)?;
                if result.preferences.is_none(){result.preferences=Some(native.preferences.clone());}
                result.native=Some(native);
                return Ok(result);
            }
        }
        if result.world.is_some() && result.scenario.is_some(){return Err(io::Error::other("world input and isolated land test are exclusive"));}
        if result.managed&&(result.world.is_none()||result.requests.is_none()){return Err(io::Error::other("formal menu requires bridge snapshot and requests paths"));}
        Ok(result)
    }

    fn terrain_root(&self) -> (PathBuf, bool) {
        if let Some(path)=&self.terrain_candidate {return (path.clone(),true);}
        let hydrology=self.root.join(terrain::HYDROLOGY_DIRECTORY);
        if terrain::compact_files_present(&hydrology)
            && ["water-geometry.qwg","hydrology-color.qhw","river-centrelines.qhl"]
                .iter().all(|name|hydrology.join(name).is_file()) {return (hydrology,true);}
        let compact=self.root.join(terrain::COMPACT_VERSION);
        if terrain::compact_files_present(&compact) {return (compact,true);}
        (self.root.join(terrain::VERSION),false)
    }
}
struct Resident {page:Page,ready:Instant,used:Instant}
struct Drag {at:[f64;2],origin:[f64;2],last:Instant,bearing:bool,moved:bool}
struct Pose {camera:Camera,object:Option<Object>}
#[derive(Clone, Copy)]
struct SelectedMilitaryCell { cell: MilitaryCell, coordinates: [f64; 2] }
struct PreparedBattleTerrain {
    terrain: BattlefieldTerrain,
    pages: Vec<[u32; 3]>,
    worker_ms: f64,
}
struct Focus {start:Instant, camera:Camera, target:[f64;2], mpp:f64}
struct CountryClick {polity:usize,point:[f64;2],deadline:Instant}
#[derive(Default)]
struct Trial {
    last:String,timing:bool,passive_timing:bool,times:Vec<f64>,previous:Option<Instant>,captures:Vec<PathBuf>,first:Option<f64>,loads:Vec<(String,f64)>,
    terrain_decodes:Vec<f64>,
    profile_frames:bool,
    frames:Vec<FrameTiming>,
    load_frames:Vec<usize>,
    battle_openings:Vec<BattleOpeningTiming>,
    movement:Option<([f64;2],[f64;2],u32,u32)>,
    window_position:Option<winit::dpi::PhysicalPosition<i32>>,
    terrain_capture:Option<(String,PathBuf)>,
    hide_landscape_models:bool,
}

#[derive(serde::Serialize)]
struct BattleOpeningTiming {
    frame:usize,
    terrain_cpu_ms:f64,
    terrain_pages:Vec<[u32;3]>,
    terrain_worker_ms:Option<f64>,
    terrain_wait_ms:f64,
    scene_cpu_ms:f64,
    original_vehicle_model:bool,
    deployment_cpu_ms:f64,
    total_cpu_ms:f64,
}

#[derive(serde::Serialize)]
struct FrameTiming {
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
    fn timing_frame(&self, capture:bool)->Option<usize> {
        (self.timing && self.profile_frames && !capture).then_some(self.frames.len())
    }

    fn record_frame(&mut self, started:Instant, presented:Instant, camera:&Camera, renderer:&Renderer, battle:bool) {
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
struct Observation {
    id:String,action:String,
    #[serde(default)] x:f64, #[serde(default)] y:f64,
    #[serde(default)] to_x:f64, #[serde(default)] to_y:f64,
    #[serde(default)] steps:f64, #[serde(default)] frames:u32,
    #[serde(default)] label:String,
    #[serde(default)] lon:f64, #[serde(default)] lat:f64, #[serde(default)] mpp:f64,
    #[serde(default)] value:String,
}
struct Host {
    natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<HostEvent>)>,
    events:winit::event_loop::EventLoopProxy<HostEvent>,
    landmarks:Option<landmarks::Landmarks>,
    transport_scene:Option<transport_scene::TransportScene>,
    transport_selection:Option<transport_ui::ObjectId>,
    transport_detail:Option<(i64, transport_ui::Detail)>,
    config:Config,window:Option<Arc<Window>>,renderer:Option<Renderer>,
    map_root:PathBuf,map_signature:Option<&'static [u8;8]>,fatal_error:Option<String>,
    world:World,visuals:PoliticalVisuals,index:Index,base:Option<Page>,reader:Reader,cached:HashMap<usize,Resident>,
    failed:HashSet<usize>,candidate:Vec<usize>,visible:Vec<usize>,
    camera:Camera,size:[u32;2],mode:Mode,state:State,theme:bool,labels:bool,
    selected:Option<Object>,details:bool,country:Option<CountryPanel>,country_click:Option<CountryClick>,
    search:Option<String>,history:Vec<Pose>,focus:Option<Focus>,site:usize,
    hits:Vec<Hit>,shown_markers:HashSet<usize>,cursor:[f64;2],drag:Option<Drag>,velocity:[f64;2],moved_at:Instant,
    animate:bool,next_date:Instant,feedback:String,dirty:bool,
    last_input_check:Instant,version:Option<SystemTime>,last_palette:Option<Date>,
    atlas:overlay::Atlas,started:Instant,trial:Trial,
    hud:Hud,skin:Skin,exit_requested:bool,
    prologue: Option<prologue_ui::Draft>,
    opening_nav: lobby::Selection,
    lobby_page:lobby::Page,lobby_country:usize,lobby_request:bool,country_directory:lobby::Directory,
    bridge_wait:Instant,seen_lobby_busy:bool,departure_requested:bool,
    loading_fade:Option<Instant>,loading_status:String,
    debug:bool,perf_at:Instant,perf_frames:u32,perf:Diagnostics,
    population_debug:Option<pop_debug_ui::Panel>,
    screenshot:Option<PathBuf>,screenshot_status:Option<(Instant,String)>,
    grid_step:f32,last_present:Instant,employment:state::EmploymentReference,market_focus_serial:u64,
    military_cell:Option<SelectedMilitaryCell>,
    battle_terrain:Option<(MilitaryCell,BattlefieldTerrain)>,
    battle_terrain_timing:Option<(Vec<[u32;3]>,f64)>,
    battle_terrain_wanted:Option<MilitaryCell>,
    battle_terrain_loading:Option<MilitaryCell>,
    battle_enter_requested:Option<Instant>,
    battle_view:Option<battle_view::View>,
}
fn font(path:&Path)->io::Result<Raster> {
    decode_rgba(File::open(path)?)
}
fn decode_rgba(source:impl Read)->io::Result<Raster> {
    let mut reader=png::Decoder::new(source).read_info()?;
    let mut pixels=vec![0;reader.output_buffer_size()];
    let info=reader.next_frame(&mut pixels)?;
    if info.color_type!=png::ColorType::Rgba || info.bit_depth!=png::BitDepth::Eight {return Err(io::Error::other("invalid type atlas"));}
    pixels.truncate(info.buffer_size());
    Ok(Raster{size:[info.width,info.height],pixels})
}
fn hud_type_atlas(path: &Path) -> io::Result<Raster> {
    use formal_ui::{HUD_TYPE_BASE_HEIGHT, HUD_TYPE_HEIGHT, HUD_TYPE_WIDTH};
    let mut base = font(path)?;
    let supplemental = decode_rgba(&include_bytes!("../../../data/character/hud-glyphs.png")[..])?;
    if base.size != [HUD_TYPE_WIDTH, HUD_TYPE_BASE_HEIGHT]
        || supplemental.size != [HUD_TYPE_WIDTH, HUD_TYPE_HEIGHT - HUD_TYPE_BASE_HEIGHT]
    {
        return Err(io::Error::other("invalid HUD glyph atlas dimensions"));
    }
    base.pixels.extend(supplemental.pixels);
    base.size[1] = HUD_TYPE_HEIGHT;
    Ok(base)
}

fn ms(t:Instant)->f64 {t.elapsed().as_secs_f64()*1000.}

impl Host {
    fn new(config:Config,events:&EventLoop<HostEvent>,started:Instant)->io::Result<Self> {
        #[cfg(windows)]
        let formal_map=config.native.is_some()||config.terrain_review;
        #[cfg(not(windows))]
        let formal_map=config.terrain_review;
        let map_root=if formal_map {map_release::root(&config.root)} else {config.root.clone()};
        let map_signature=formal_map.then_some(map_release::TILE_SIGNATURE);
        let natural=if formal_map {
            let (natural_root,packed)=config.terrain_root();
            let catalogue=terrain::Catalogue::open(&natural_root,packed,config.terrain_selection,config.terrain_layer_candidate.clone())?;
            if config.observe.is_some() {eprintln!("Terrain catalogue · {}",natural_root.display());}
            Some((catalogue,events.create_proxy()))
        }else{
            if config.terrain_candidate.is_some() || config.terrain_detail.is_some() {
                return Err(io::Error::other("Terrain candidates require the native game"));
            }
            None
        };
        let mut world=if map_signature.is_some() {map_release::open(&map_root)?}
            else {World::open(&map_root.join("world.json"))?};
        let landmarks=if formal_map {Some(landmarks::Landmarks::install(&mut world)?)} else {None};
        let mut camera=Camera::new(VIEW_SIZE);
        camera.local_models=landmarks.is_some();
        if world.tiles.first().is_none_or(|t|t.level!=0) || world.polities.len()>255 || world.admin.len()>255 {return Err(io::Error::other("invalid world index"));}
        let atlas=overlay::Atlas::open(&config.root.join("type.json"))?;
        let mut skin=Skin::open(&config.root)?;
        let mut state=State::new();
        #[cfg(windows)]
        if let Some(native)=&config.native {native.update_view(&mut state)?;}
        if let Some(path)=&config.world {
            if !config.managed||path.exists(){state.input(path,&world)?;}
        }
        if let Some(path)=&config.scenario {
            let bounds=compact::REGIONS.map(|region|world.tiles.iter().find(|t|t.path.starts_with(&format!("tiles/{region}-"))).unwrap().group);
            let mut model=timeline::Timeline::load_sites(&config.root.join("land-objects.json"),&bounds)?;
            model.apply(timeline::read(path,512*1024)?)?;
            state.date=model.date;
            state.timeline=Some(model);
        }
        if let Some(lobby) = &mut state.lobby { lobby.bind_map_areas(&world); }
        let connected=state.session.is_some();
        let labels=(formal_map||!connected&&!config.managed)&&!config.terrain_review;
        let lobby_country=world.polities.iter().position(|p|p.id=="country_fra").unwrap_or(0);
        let mode=if config.terrain_review {Mode::Geographic} else {Mode::Political};
        let preferences=config.preferences.as_deref().map(interface::Preferences::load).unwrap_or_default();
        skin.set_english(preferences.english);
        let visuals=PoliticalVisuals::open(&map_root,&world)?;
        let employment=state::EmploymentReference::open(&config.root)?;
        let index=Index::new(&world.tiles);
        let legacy_cover=natural.is_none()||config.scenario.is_some();
        let reader=Reader::new(map_root.clone(),map_signature,legacy_cover,events.create_proxy());
        let observation_id=config.observe.as_ref().filter(|_|!config.terrain_review).and_then(|path|timeline::read::<Observation>(path,128*1024).ok())
            .map(|input|input.id).unwrap_or_default();
        Ok(Self {natural,events:events.create_proxy(),landmarks,transport_scene:None,transport_selection:None,transport_detail:None,config,map_root,map_signature,fatal_error:None,world,visuals,index,reader,state,camera,atlas,started,base:None,window:None,renderer:None,
            cached:HashMap::new(),failed:HashSet::new(),candidate:Vec::new(),visible:Vec::new(),
            size:VIEW_SIZE,mode,theme:false,labels,selected:None,details:false,country:None,country_click:None,search:None,history:Vec::new(),focus:None,site:0,
            hits:Vec::new(),shown_markers:HashSet::new(),cursor:[640.,360.],drag:None,velocity:[0.;2],moved_at:Instant::now(),
            animate:false,next_date:Instant::now(),feedback:String::new(),dirty:true,last_input_check:Instant::now(),
            version:None,last_palette:None,trial:Trial{last:observation_id,..Trial::default()},hud:Hud{fullscreen:preferences.fullscreen,volume:preferences.volume,english:preferences.english,..Hud::default()},skin,exit_requested:false,
            prologue: None,
            opening_nav: lobby::Selection::default(),
            lobby_page:lobby::Page::Home,lobby_country,lobby_request:false,country_directory:lobby::Directory::default(),
            bridge_wait:Instant::now(),seen_lobby_busy:false,departure_requested:false,
            loading_fade:None,loading_status:String::new(),debug:false,perf_at:Instant::now(),perf_frames:0,population_debug:None,
            perf:Diagnostics{rate:0.,cpu_ms:0.,tiles:0,visible:0,mib:0.,streaming:false},
            screenshot:None,screenshot_status:None,grid_step:50000.,last_present:started,employment,market_focus_serial:0,
            military_cell:None,battle_terrain:None,battle_terrain_timing:None,battle_view:None,
            battle_terrain_wanted:None,battle_terrain_loading:None,battle_enter_requested:None})
    }
    fn available(&self,object:Object)->bool {
        let day=self.state.date.to_string();
        match object {
            Object::Polity(i)=>self.world.polities.get(i).is_some_and(|p|p.active(&day)),
            Object::Place(i)=>self.world.places.get(i).is_some_and(|p|ui::active(&day,&p.from_date,&p.to_date)),
            Object::Administration(i)=>World::active_politics(&day)&&i<self.world.admin.len(),
        }
    }
    fn id(&self,object:Object)->String {
        match object {Object::Place(i)=>self.world.places[i].id.clone(),Object::Polity(i)=>self.world.polities[i].map_id(),Object::Administration(i)=>self.world.admin[i].id.clone()}
    }
    fn emit(&mut self,request:Request<'_>) {
        #[cfg(windows)]
        if let Some(native)=&mut self.config.native {
            self.transport_detail=None;
            let had_session=self.state.session.is_some();
            let revision=native.revision;
            self.feedback.clear();
            let dispatched=native.dispatch(request);
            let updated=native.update_view(&mut self.state);
            self.exit_requested|=native.exit;
            let loaded=native.revision!=revision;
            match updated {
                Ok(())=>{
                    if let Some(lobby) = &mut self.state.lobby { lobby.bind_map_areas(&self.world); }
                    self.world_view_changed(had_session, loaded, Instant::now());
                }
                Err(error)=>self.feedback=error.to_string(),
            }
            if let Err(error)=dispatched {self.feedback=error.to_string();}
            self.dirty=true;
            return;
        }
        if let Err(e)=request.output(self.config.requests.as_deref()) {self.feedback=format!("Host request: {e}");}
    }
    fn select(&mut self,object:Option<Object>) {
        self.select_transport(None);
        self.country=None;
        self.details=false;
        self.selected=object.filter(|o|self.available(*o));
        if let Some(object)=self.selected {
            let display_only=match object {
                Object::Polity(i)=>self.world.polities[i].display_only,
                Object::Place(i)=>self.landmarks.as_ref().is_some_and(|landmarks|landmarks.contains(i)),
                Object::Administration(_)=>false,
            };
            if !display_only {
                self.emit(Request::Inspect{id:&self.id(object)});
            }
        }
        self.dirty=true;
    }
    fn open_country(&mut self,polity:usize) {
        if !self.available(Object::Polity(polity)){return;}
        if self.country.is_some_and(|panel|panel.polity==polity){return;}
        self.select(Some(Object::Polity(polity)));
        let view=if self.player_polity()==Some(polity){CountryView::Record}else{CountryView::Summary};
        self.country=Some(CountryPanel{polity,view});
    }
    fn click_country(&mut self,polity:usize,point:[f64;2]) {
        let now=Instant::now();
        if self.country_click.take().is_some_and(|first|first.polity==polity && now<=first.deadline &&
            (point[0]-first.point[0]).hypot(point[1]-first.point[1])<=8.) {
            let object=Object::Polity(polity);
            self.country=None;
            self.details=false;
            self.selected=Some(object);
            let target=self.visuals.record(polity).focus(self.size).unwrap_or((self.world.polities[polity].coordinates,1800.));
            self.focus_on(object,target);
        }else{
            self.country_click=Some(CountryClick{polity,point,deadline:now+COUNTRY_DOUBLE_CLICK});
        }
    }
    fn country_action(&mut self,action:CountryAction) {
        use CountryAction as Go;
        let Some(mut panel)=self.country.take() else{return;};
        let count=self.skin.admin_count(&self.world,&self.world.polities[panel.polity]);
        panel.view=match (action,panel.view) {
            (Go::Close,_)=>{
                if self.selected==Some(Object::Polity(panel.polity)){self.selected=None;}
                return;
            }
            (Go::Back,CountryView::Directory(_))=>CountryView::Record,
            (Go::Back,CountryView::Region{page,..})=>CountryView::Directory(page),
            (Go::Back,CountryView::Record) if self.player_polity()!=Some(panel.polity)=>CountryView::Summary,
            (Go::Record,CountryView::Summary)=>CountryView::Record,
            (Go::Directory,CountryView::Record) if count>0=>CountryView::Directory(0),
            (Go::Page(step),CountryView::Directory(page))=>{
                let last=count.saturating_sub(1)/panel.rows(self.size);
                CountryView::Directory(page.saturating_add_signed(step as isize).min(last))
            }
            (Go::Region(index),CountryView::Directory(_)) if index<count=>CountryView::Region{page:index/panel.rows(self.size),index},
            (Go::Boundary(index),view @ CountryView::Region{..})=>{
                if let Some(target)=camera::fit_bounds(self.world.admin[index].bounds,self.size){
                    self.focus_on(Object::Administration(index),target);
                }
                view
            }
            (_,view)=>view,
        };
        self.country=Some(panel);
    }
    fn save_pose(&mut self) {
        if self.history.len()>=24 {self.history.remove(0);}
        self.history.push(Pose{camera:self.camera.clone(),object:self.selected});
    }
    fn locate(&mut self,target:[f64;2],mpp:f64) {
        self.focus=None;self.save_pose();self.camera.focus(target,mpp,self.size);
        self.velocity=[0.;2];self.details=false;self.search=None;self.dirty=true;
    }
    fn focus_on(&mut self,object:Object,(target,mpp):([f64;2],f64)) {
        if !matches!(object,Object::Polity(i) if self.world.polities[i].display_only) {
            self.emit(Request::Locate{id:&self.id(object)});
        }
        self.save_pose();
        self.focus=Some(Focus{start:Instant::now(),camera:self.camera.clone(),target,mpp});
        self.velocity=[0.;2];
        self.dirty=true;
    }
    fn locate_object(&mut self,object:Object) {
        let landmark=match object {
            Object::Place(index)=>self.landmarks.as_ref().and_then(|models|models.focus(index)),
            _=>None,
        };
        let (target,mpp)=match object {
            Object::Administration(i)=>{
                let Some(target)=camera::fit_bounds(self.world.admin[i].bounds,self.size) else{return;};
                target
            }
            Object::Place(i)=>landmark.unwrap_or_else(||(self.world.places[i].coordinates,if self.world.places[i].id=="place:paris" {36.}else{210.})),
            Object::Polity(i)=>self.visuals.record(i).focus(self.size).unwrap_or((self.world.polities[i].coordinates,1800.)),
        };
        if !matches!(object,Object::Place(_)) {
            self.focus_on(object,(target,mpp));
        } else {
            if landmark.is_none(){self.emit(Request::Locate{id:&self.id(object)});}
            self.locate(target,mpp);
        }
        self.search=None;
        if let Object::Polity(polity)=object{self.open_country(polity);}else{self.select(Some(object));}
    }
    fn action(&mut self,action:Action) {
        self.country_click=None;
        self.feedback.clear();
        match action {
            Action::Mode(mode)=>{
                if self.hud.page==HudPage::Market{self.market_command("close",0);}
                if mode==Mode::Military && self.mode!=Mode::Military && self.written_world().is_some(){self.hud.military_grid=true;}
                if self.mode!=mode {
                    self.hud.transport_detail_expanded=false;
                    self.transport_detail=None;
                }
                self.mode=mode;
                if self.hud.page!=HudPage::Travel {self.hud.page=HudPage::Map;}
                self.hud.menu=HudMenu::None;
                self.emit(Request::SetMapMode{mode:mode.key()});
            }
            Action::Home=>{
                self.focus=None;self.save_pose();self.camera.set_scale(Camera::overview(self.size));
                self.velocity=[0.;2];self.details=false;self.country=None;self.search=None;
            }
            Action::Back=>{
                self.focus=None;
                if let Some(p)=self.history.pop(){self.camera=p.camera;self.select(p.object);}
                self.velocity=[0.;2];self.details=false;self.country=None;self.search=None;
            }
            Action::Search=>{
                self.details=false;self.country=None;
                self.search=if self.search.is_some(){None}else{Some(String::new())};
                if self.search.is_some() { self.population_debug=None; }
            }
            Action::Close=>self.select(None),
            Action::Details=>self.details=!self.details,
            Action::Country(go)=>self.country_action(go),
            Action::Locate=>if let Some(o)=self.selected{self.locate_object(o);},
            Action::Select(o)=>if self.search.is_some(){self.locate_object(o);}else{
                self.select(Some(o));
                if let Object::Place(i)=o {
                    if self.hud.page==HudPage::Market {
                        let region=self.state.session.as_ref().and_then(|s|s.market.as_ref())
                            .and_then(|m|m.places.iter().position(|row|row.id==self.world.places[i].id));
                        if let Some(index)=region {self.market_command("region",index);}
                    }
                }
            },
            Action::Hud(command)=>self.hud_action(command),
        }
        self.dirty=true;
    }
    fn save_interface(&mut self) {
        let preferences=interface::Preferences{
            fullscreen:self.hud.fullscreen,volume:self.hud.volume,english:self.hud.english,
        };
        self.emit(Request::Interface{volume:f64::from(preferences.volume)/100.,locale:preferences.locale()});
        if let Some(path)=&self.config.preferences {
            if let Err(error)=preferences.save(path) {
                self.feedback=format!("设置保存失败：{error}");
            }
        }
    }
    fn volume_slider(&self)->Option<[f64;4]> {
        (self.in_lobby()&&self.lobby_page==lobby::Page::Settings).then(||{
            [(f64::from(self.size[0])-365.)*0.5+16.,(f64::from(self.size[1])-290.)*0.5+73.,333.,28.]
        })
    }
    fn slide_volume(&mut self) {
        if let Some([x,_,width,_])=self.volume_slider(){
            let volume=((self.cursor[0]-x)/width*100.).round().clamp(0.,100.) as u8;
            if self.hud.volume!=volume {self.hud_action(HudCommand::Volume(volume));}
            self.dirty=true;
        }
    }

    fn hud_action(&mut self,command:HudCommand) {
        match command {
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
            HudCommand::Clock(speed)=>{
                if self.state.session.is_some(){
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
    fn in_lobby(&self)->bool {self.config.managed&&self.state.session.is_none()}
    fn loading(&self)->bool {
        self.config.managed && (self.lobby_request||self.state.lobby.as_ref().is_some_and(|s|s.loading||s.busy||
                self.lobby_page==lobby::Page::Selection&&!s.selection_ready&&self.feedback.is_empty()&&s.status.is_empty())
            || self.state.lobby.is_none()&&self.state.session.is_none()&&self.feedback.is_empty())
    }
    fn animate_opening(&mut self, now: Instant) {
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

    fn opening_choice(&self) -> Option<&lobby::Opening> {
        self.state.lobby.as_ref()?.opening(self.world.polities.get(self.lobby_country)?)
    }

    fn opening_shift(&mut self, target: f64) {
        self.opening_nav.shift = Some((Instant::now(), self.camera.screen_offset_x, target));
    }

    fn opening_focus(&mut self, target: [f64; 2], mpp: f64) {
        self.velocity = [0.; 2];
        self.focus = Some(Focus { start: Instant::now(), camera: self.camera.clone(), target, mpp });
        self.dirty = true;
    }

    fn opening_layout(&self) -> Option<lobby::ProfileLayout> {
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
        self.opening_nav.departure_cloud = None;
        self.lobby_request = true;
        self.emit(Request::NewPlayer { polity: &polity, place: &place, prologue, health });
    }

    fn skip_opening_transition(&mut self) -> bool {
        use lobby::Page;
        if self.opening_nav.cloud.take().is_some() {
            self.lobby_page = Page::Prologue;
            self.opening_nav.shift = None;
            self.focus = None;
            self.camera.screen_offset_x = -0.11;
        } else if self.opening_nav.departure_cloud.take().is_some() {
            self.enter_prologue_world();
            self.opening_nav.arrival_cloud = None;
        } else if self.opening_nav.arrival_cloud.take().is_none() {
            return false;
        }
        self.dirty = true;
        true
    }

    fn lobby_action(&mut self, command: lobby::Command) {
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
            Command::SkipCloud => { self.skip_opening_transition(); }
            Command::PrologueChoice(index) if self.lobby_page == Page::Prologue => {
                if let Some(draft) = &mut self.prologue { draft.choose(index); }
            }
            Command::PrologueHealth(index) if self.lobby_page == Page::Prologue => {
                if let Some(draft) = &mut self.prologue { draft.set_health(index); }
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

    fn filter_countries(&mut self) {
        if self.opening_nav.stage != lobby::SelectionStage::Profile {
            self.country_directory.filter(&self.world, self.state.lobby.as_ref(), &self.state.date.to_string(), self.hud.english);
        }
        self.dirty = true;
    }

    fn scroll_countries(&mut self, point: [f64; 2], steps: f64) -> bool {
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
    fn market_command(&mut self,verb:&'static str,index:usize){
        if self.state.session.is_none(){self.feedback="正式世界未连接".into();return;}
        if verb=="open"{
            if self.mode!=Mode::Economic || self.hud.page==HudPage::Market{return;}
            let selected=self.selected.filter(|o|matches!(o,Object::Polity(i) if !self.world.polities[*i].display_only));
            let id=selected.map(|o|self.id(o)).unwrap_or_default();
            self.open_market(&id);
            return;
        }
        if verb=="close"{
            self.hud.page=HudPage::Map;self.hud.market_chooser=None;self.hud.quantity=None;
            self.hud.market_map=false;self.hud.market_search=None;
            self.focus=None;self.velocity=[0.;2];
            self.emit(Request::Market{verb,id:"",site:"",quantity:0,token:0,viewport:self.size});return;
        }
        let Some(session)=self.state.session.as_ref() else{return;};
        let Some(v)=session.market.as_ref() else{return;};
        let mut id=String::new();let mut site=String::new();let mut quantity=0;let mut token=0;
        let actual=match verb {
            "map_locations" => {
                self.hud.page=HudPage::Map;
                self.hud.market_map=true;
                self.hud.market_search=None;
                self.select_transport(None);
                self.selected=None;self.country=None;self.details=false;self.search=None;
                return;
            }
            "market_back"|"search_locations" => {
                self.hud.page=HudPage::Market;
                self.hud.market_map=false;
                self.hud.market_offset=0;
                self.hud.market_search=(verb=="search_locations").then(String::new);
                if let Some(window)=&self.window {window.set_ime_allowed(self.hud.market_search.is_some());}
                return;
            }
            "location" => {
                let Some(row)=v.sites.get(index) else{return;};
                id=row.unit.clone();site=row.place.clone();
                self.hud.page=HudPage::Market;
                self.hud.market_map=false;
                verb
            }
            "carrier" => {
                let Some(place)=v.sites.get(index).map(|row|row.place.clone()) else{return;};
                self.choose_transport_destination(&place);
                return;
            }
            "local_bread"|"trend"|"back_good" => verb,
            "places"|"countries"=>{
                self.hud.market_chooser=if self.hud.market_chooser==Some(verb){None}else{Some(verb)};
                self.hud.market_search=None;
                self.hud.market_offset=0;return;
            }
            "regional" if v.region.is_empty()||!v.places.iter().any(|row|row.id==v.region)=>{
                let Some(row)=v.places.iter().find(|row|row.id==session.place).or_else(||v.places.first()) else{return;};
                id=row.id.clone();"region"
            }
            "international"|"domestic"|"regional"=>{id=verb.into();"scope"}
            "freight"=>{
                self.emit(Request::Transport{verb:"cargo",id:""});
                self.hud.page=HudPage::Travel;
                self.hud.market_search=None;
                return;
            }
            "quotes"|"goods"|"transport"|"activity"=>{id=verb.into();"view"}
            "goods_group"=>{
                let Some((group,_))=market_ui::GOODS_GROUPS.get(index) else{return;};
                id=(*group).into();
                verb
            }
            "trends"=>{
                let Some(row)=v.book.iter().find(|row|row.id==v.good).or_else(||v.book.first()) else{return;};
                id=row.id.clone();"good"
            }
            "price"|"supply"=>{id=verb.into();"chart"}
            "window"=>{id=index.to_string();verb}
            "country"|"region"=>{
                let list=if verb=="country"{&v.countries}else{&v.places};
                let Some(row)=list.get(index) else{return;};
                id=row.id.clone();
                verb
            }
            "good"|"catalog_good"=>{
                let rows=if verb=="catalog_good"{&v.catalog}else{&v.book};
                let Some(row)=rows.get(index) else{return;};
                id=row.id.clone();
                "good"
            }
            "offer"|"seller"=>{
                let Some(row)=v.offers.get(index) else{return;};
                id=if verb=="offer"{row.commodity.clone()}else{row.site.clone()};site=row.site.clone();verb
            }
            "edit"=>{if v.quote.is_some(){self.hud.quantity=Some(String::new());}return;}
            "requote"=>{
                let Some(quote)=&v.quote else{return;};
                let Some(value)=self.hud.quantity.as_deref().and_then(|s|market_ui::parse_quantity(s,quote.scale)) else{
                    self.feedback="请输入符合商品单位的数量。".into();return;
                };
                quantity=value;"quantity"
            }
            "buy"|"freight_buy"=>{
                let Some(quote)=v.quote.as_ref().filter(|q|q.accepted) else{return;};
                if self.hud.purchase_token==Some(quote.token)||self.hud.quantity.is_some(){return;}
                token=quote.token;self.hud.purchase_token=Some(token);verb
            }
            "quote_back"=>verb,
            "collect"=>{
                let Some(row)=v.collections.get(index) else{return;};
                id=row.shipment.clone();quantity=row.quantity;verb
            }
            _=>return,
        };
        self.hud.quantity=None;self.hud.market_offset=0;self.hud.market_chooser=None;self.hud.market_search=None;
        self.emit(Request::Market{verb:actual,id:&id,site:&site,quantity,token,viewport:self.size});
    }

    fn type_market_search(&mut self, text: &str) {
        if let Some(query)=self.hud.market_search.as_mut() {
            if query.len()+text.len()<=80 {
                query.push_str(text);
                self.hud.market_offset=0;
                self.dirty=true;
            }
        }
    }

    fn open_market(&mut self, id: &str) {
        self.hud_action(HudCommand::Page(HudPage::Market));
        self.hud.market_chooser=None;
        self.emit(Request::Market{verb:"open",id,site:"",quantity:0,token:0,viewport:self.size});
    }

    fn transport_detail_visible(&self) -> bool {
        self.transport_selection.is_some() && self.hud.page==HudPage::Map
            && self.hud.menu==HudMenu::None && self.country.is_none() && self.search.is_none() && !self.details
            && !self.hud.market_map
    }

    fn select_transport(&mut self, selection: Option<transport_ui::ObjectId>) {
        if self.transport_selection==selection {return;}
        if selection.is_some() {
            self.selected=None;
            self.details=false;
            self.country=None;
            self.country_click=None;
            self.feedback.clear();
        }
        self.transport_selection=selection;
        self.transport_detail=None;
        self.hud.transport_detail_expanded=false;
        self.dirty=true;
    }

    fn pick_transport(&mut self, point: [f64; 2]) -> bool {
        if self.hud.page!=HudPage::Map || self.hud.menu!=HudMenu::None
            || self.search.is_some() || self.details || self.in_lobby() || self.hud.market_map {return false;}
        let selection=self.transport_scene.as_ref().and_then(|scene|scene.pick(point));
        if selection.is_none() {return false;}
        self.select_transport(selection);
        true
    }

    fn planning_transport(&self) -> bool {
        let Some(session) = self.state.session.as_ref() else { return false; };
        let form_visible = self.hud.page == HudPage::Travel
            || (self.hud.page == HudPage::Market
                && session.market.as_ref().is_some_and(|market| market.content == "freight"));
        form_visible && self.hud.menu == HudMenu::None
            && self.hud.transport_directory.is_none() && self.search.is_none() && !self.details
            && session.transport.as_ref().is_some_and(transport_ui::TransportView::planning)
    }

    fn pick_transport_destination(&mut self, point: [f64; 2], place: Option<usize>) -> bool {
        if !self.planning_transport() || self.is_panel(point) { return false; }
        if let Some(index) = place {
            let id = self.world.places[index].id.clone();
            if self.choose_transport_destination(&id) { return true; }
        }
        let Some(world) = self.written_world() else { return false; };
        let destination = self.transport_scene.as_ref()
            .and_then(|scene| scene.pick_destination(point, world)).map(str::to_owned);
        destination.is_some_and(|id| self.choose_transport_destination(&id))
    }

    fn transport_detail_action(&mut self, index: usize) {
        use transport_ui::Link;
        if !self.transport_detail_visible() {return;}
        let Some(link)=self.transport_detail.as_ref().and_then(|(_, detail)|detail.links.get(index)).map(|(_,link)|link.clone()) else{return;};
        match link {
            Link::Object(id)=>self.select_transport(Some(id)),
            Link::Travel(id)=>{self.choose_transport_destination(&id);}
            Link::CurrentTravel=>{
                self.hud_action(HudCommand::Page(HudPage::Travel));
                self.emit(Request::Transport{verb:"passenger",id:""});
            }
            Link::Market(unit)=>self.open_market(&format!("state:{unit}")),
            Link::Freight(id)=>{
                self.hud_action(HudCommand::Page(HudPage::Travel));
                self.emit(Request::Transport{verb:"lot",id:&id.to_string()});
            }
        }
    }

    fn choose_transport_destination(&mut self, id: &str) -> bool {
        if !self.written_world().is_some_and(|world|world.can_book_transport_to(id)) {
            return false;
        }
        if self.hud.page != HudPage::Travel {
            self.hud_action(HudCommand::Page(HudPage::Travel));
        }
        self.emit(Request::Transport{verb:"destination",id});
        true
    }

    fn transport_search(&mut self) {
        let query=format!("{}|{}",self.hud.transport_category,self.hud.transport_directory.as_deref().unwrap_or(""));
        self.emit(Request::Transport{verb:"search",id:&query});
    }

    fn type_transport_search(&mut self, text: &str) {
        if let Some(query)=self.hud.transport_directory.as_mut() {
            if query.len()+text.len() <= 96 {
                query.push_str(text);
                self.transport_search();
            }
        }
    }

    fn transport_command(&mut self, verb: &'static str, index: usize) {
        let id = match verb {
            "city" => {
                let Some(place) = self.world.places.get(index) else { return };
                let id = place.id.clone();
                self.choose_transport_destination(&id);
                return;
            }
            "destination" => {
                let Some(place) = self.state.session.as_ref().and_then(|s| s.transport.as_ref())
                    .and_then(|transport| transport.destinations.get(index)) else { return };
                place.id.clone()
            }
            "lot" => {
                let Some(lot) = self.state.session.as_ref().and_then(|s| s.transport.as_ref())
                    .and_then(|transport| transport.lots.get(index)) else { return };
                lot.id.to_string()
            }
            _ => String::new(),
        };
        if verb=="destination" {
            self.hud.transport_directory=None;
            if let Some(window)=&self.window {window.set_ime_allowed(false);}
        }
        if verb=="lot" {self.hud.transport_lots_open=false;}
        self.emit(Request::Transport { verb, id: &id });
    }
    fn apply_market_focus(&mut self,target:market_ui::MarketFocus) {
        if target.serial==self.market_focus_serial || !target.point.into_iter().all(f64::is_finite)
            || !target.mpp.is_finite() || target.mpp<=0. || !target.shift.is_finite() {return;}
        self.market_focus_serial=target.serial;
        self.focus=None;
        self.velocity=[0.;2];
        self.camera.focus_at(target.point,target.mpp,[target.shift,0.],self.size);
    }

    fn request_slot(&mut self,slot:u8,save:bool){
        if self.state.session.is_none(){return;}
        let action=format!("slot:{}:{slot}",if save{"save"}else{"load"});
        self.hud.menu=if save{HudMenu::Save}else{HudMenu::Load};
        self.hud.waiting_slot=true;
        self.emit(Request::HostAction{action:&action});
    }
    fn player_polity(&self)->Option<usize>{
        let id=&self.state.session.as_ref()?.polity;
        let id=id.strip_prefix("state:").unwrap_or(id);
        self.world.polities.iter().position(|p|p.id==id)
    }
    fn written_world(&self) -> Option<&wwo_map_lab::formal_bootstrap::InitialWorld> {
        #[cfg(windows)]
        if let Some(native) = &self.config.native {
            return native.active_world();
        }
        None
    }

    fn inspect_population(&mut self, query: String) {
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
                        .then(|| world.population_household_needs(&report)).flatten();
                    let days = if panel.page == pop_debug_ui::Page::Changes && report.population_total.is_some() {
                        population.recorded_population_days(report.account_id, clock, 14)
                    } else {
                        Vec::new()
                    };
                    panel.set_report(&report, social.as_ref(), needs.as_ref(), world.macro_economy(), days);
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

    fn refresh_population_debug(&mut self) {
        let Some(panel) = &self.population_debug else { return; };
        let Some(world) = self.written_world() else { return; };
        let revision = (world.clock().current_day(), world.population().journal_revision());
        if panel.revision != Some(revision) {
            self.update_population_debug(panel.query.clone(), false);
        }
    }

    fn population_page(&mut self, page: pop_debug_ui::Page) {
        let Some(panel) = self.population_debug.as_mut().filter(|panel| panel.page != page) else { return; };
        panel.page = page;
        panel.scroll = 0;
        let query = panel.query.clone();
        self.inspect_population(query);
    }

    fn population_location(&mut self, object: Option<Object>) {
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

    fn population_polity_at(&mut self, point: [f64; 2]) {
        let polity = self.camera.vector(point, self.size)
            .and_then(|v| self.object_at(camera::geographic(v))[0].checked_sub(1))
            .map(|index| Object::Polity(usize::from(index)))
            .filter(|&object| self.available(object));
        self.population_location(polity);
    }

    fn scroll_population_debug(&mut self, point:[f64;2], steps:f64)->bool {
        let Some(panel)=self.population_debug.as_mut().filter(|panel|panel.contains(self.size,point)) else{return false;};
        panel.scroll_by(-(steps.signum() as isize)*3);
        self.dirty=true;
        true
    }

    fn battle_root(&self) -> PathBuf {
        self.config.battlefield_data.clone().unwrap_or_else(|| self.config.root.join("battlefield"))
    }

    fn request_battle_terrain(&mut self, region:MilitaryCell) -> io::Result<bool> {
        self.battle_terrain_wanted = Some(region);
        if self.battle_terrain.as_ref().is_some_and(|(loaded,_)| *loaded == region) {
            return Ok(true);
        }
        if self.battle_terrain_loading.is_none() {
            let (root,packed) = self.config.terrain_root();
            if !packed {return Err(io::Error::other("Compact terrain data is required"));}
            let events = self.events.clone();
            std::thread::Builder::new().name("battle-terrain".into()).spawn(move || {
                let started = Instant::now();
                let result = terrain::battlefield(&root,region).map(|(terrain,pages)| PreparedBattleTerrain {
                    terrain, pages, worker_ms:ms(started),
                });
                let _ = events.send_event(HostEvent::BattleTerrain(region,result));
            })?;
            self.battle_terrain_loading = Some(region);
        }
        Ok(false)
    }

    fn battle_terrain_ready(&mut self, region:MilitaryCell, result:io::Result<PreparedBattleTerrain>) {
        self.battle_terrain_loading = None;
        let Some(wanted) = self.battle_terrain_wanted else {return;};
        if wanted != region {
            if let Err(error) = self.request_battle_terrain(wanted) {
                self.battle_enter_requested = None;
                self.feedback = error.to_string();
                self.dirty = true;
            }
            return;
        }
        let entry = self.battle_enter_requested.take().zip(self.military_cell)
            .filter(|(_,selection)| self.military_grid_active() && selection.cell.region() == region);
        match result {
            Ok(prepared) => {
                if let Some(renderer) = &mut self.renderer {renderer.clear_battle();}
                self.battle_terrain = Some((region,prepared.terrain));
                self.battle_terrain_timing = Some((prepared.pages,prepared.worker_ms));
                if let Some((requested,selection)) = entry {
                    if let Err(error) = self.open_battle(selection,ms(requested)) {
                        self.feedback = error.to_string();
                    }
                }
            }
            Err(error) if entry.is_some() => self.feedback = error.to_string(),
            Err(_) => {}
        }
        self.dirty = true;
    }

    fn open_battle(&mut self, selection:SelectedMilitaryCell, terrain_wait_ms:f64) -> io::Result<()> {
        let Some(world)=self.written_world() else{return Ok(());};
        let timing=self.trial.timing_frame(false).map(|frame|(frame,Instant::now()));
        let region=selection.cell.region();
        let create=world.needs_land_deployment(selection.cell);
        if let Some(message)=self.battle_location_message(region){return Err(io::Error::other(message));}
        let Some((_,terrain))=self.battle_terrain.as_ref().filter(|(loaded,_)|*loaded==region) else {
            return Err(io::Error::other("Battlefield terrain is not ready"));
        };
        let terrain_done=timing.map(|_|Instant::now());
        let root = self.battle_root();
        let center=region.local_at(selection.coordinates).ok_or_else(||io::Error::other("Position outside battlefield"))?;
        let deployment=create.then(||wwo_map_lab::land_battle::LandBattle::new(center));
        if deployment.as_ref().is_some_and(|battle|battle.units.iter().any(|unit|{
            let [x,z]=unit.position.map(f64::from);
            !terrain.ground_is_land(x,z)
        })) {
            return Err(io::Error::other(self.skin.choose("该位置没有足够的陆地部署编队，请选择方格内陆位置。", "Select a position farther inland to deploy both formations.")));
        }
        let renderer=self.renderer.as_mut().ok_or_else(|| io::Error::other("Vulkan surface is not ready"))?;
        let scene_started=timing.map(|_|Instant::now());
        renderer.prepare_battle(terrain, &root)?;
        let scene_done=timing.map(|_|Instant::now());
        let original_vehicle_model=renderer.battle_uses_original_model();
        #[cfg(windows)]
        if let Some(native)=&mut self.config.native {
            if let (Some(world), Some(battle))=(native.active_world_mut(), deployment) {
                world.start_land_battle(selection.cell,battle)?;
                native.reset_world_tick();
            }
            self.battle_view=Some(battle_view::View::new(terrain,selection.cell,center));
            self.drag = None;
            self.focus = None;
            self.velocity = [0.; 2];
            self.feedback.clear();
            self.last_present = Instant::now();
            self.reset_battle_fps();
        }
        let terrain_timing=self.battle_terrain_timing.take();
        if let (Some((frame,started)),Some(terrain_done),Some(scene_started),Some(scene_done))=
            (timing,terrain_done,scene_started,scene_done) {
            let millis=|start:Instant,end:Instant| end.duration_since(start).as_secs_f64()*1000.;
            let done=Instant::now();
            let (terrain_pages,terrain_worker_ms)=terrain_timing
                .map(|(pages,worker_ms)|(pages,Some(worker_ms))).unwrap_or_default();
            self.trial.battle_openings.push(BattleOpeningTiming {
                frame, terrain_cpu_ms:millis(started,terrain_done), terrain_pages, terrain_worker_ms, terrain_wait_ms,
                scene_cpu_ms:millis(scene_started,scene_done), original_vehicle_model,
                deployment_cpu_ms:millis(scene_done,done), total_cpu_ms:millis(started,done),
            });
        }
        Ok(())
    }

    fn military_grid_active(&self)->bool {
        self.mode==Mode::Military && self.hud.military_grid && self.hud.page==HudPage::Map
            && self.hud.menu==HudMenu::None && self.camera.mpp<5000. && self.written_world().is_some()
    }

    fn click_military_cell(&mut self,coordinates:[f64;2],owner:Option<usize>)->bool {
        if !self.military_grid_active(){return false;}
        let selection=owner.filter(|&i|self.world.polities[i].id=="country_fra")
            .and_then(|_|MilitaryCell::at(coordinates,(self.grid_step/1000.) as u8))
            .map(|cell|SelectedMilitaryCell{cell,coordinates});
        if let Some(selection)=selection {
            let cell=selection.cell;
            let already_selected=self.military_cell.is_some_and(|old|old.cell==cell);
            self.military_cell=Some(selection);
            self.country_click=None;
            if already_selected {self.enter_selected_battle();}
            else {
                self.battle_enter_requested=None;
                self.battle_terrain_wanted=None;
                if let Some(message)=self.battle_location_message(cell.region()) {
                    self.feedback=message;
                } else {
                    let world=self.written_world().unwrap();
                    let instruction=if world.needs_land_deployment(cell) {
                        self.skin.choose("回车开始测试交战", "Enter to start training exercise")
                    } else if world.land_battle_in_progress() {
                        self.skin.choose("回车返回战场", "Enter to resume battle")
                    } else { self.skin.choose("回车查看战果", "Enter for battle results") };
                    self.feedback=format!("{}  {}",cell.id(),instruction);
                    if let Err(error)=self.request_battle_terrain(cell.region()) {
                        self.feedback=error.to_string();
                    }
                }
            }
            self.dirty=true;
            return true;
        }
        if self.military_cell.take().is_some(){
            self.battle_enter_requested=None;
            self.battle_terrain_wanted=None;
            self.feedback.clear();
            self.dirty=true;
        }
        false
    }

    fn enter_selected_battle(&mut self) {
        if let Some(selection)=self.military_cell {
            let region=selection.cell.region();
            if let Some(message)=self.battle_location_message(region) {
                self.feedback=message;
            } else {
                match self.request_battle_terrain(region) {
                    Ok(true) => {
                        self.battle_enter_requested=None;
                        if let Err(error)=self.open_battle(selection,0.){self.feedback=error.to_string();}
                    }
                    Ok(false) => {
                        self.battle_enter_requested.get_or_insert_with(Instant::now);
                        self.feedback=self.skin.choose("正在加载战场地貌", "Loading battlefield terrain").into();
                    }
                    Err(error) => self.feedback=error.to_string(),
                }
            }
            self.dirty=true;
        }
    }

    fn battle_location_message(&self,region:MilitaryCell)->Option<String> {
        let world=self.written_world()?;
        if !world.land_battle_in_progress() {return None;}
        let saved=world.land_battle_region().filter(|saved|*saved!=region)?;
        Some(format!("{} {}",self.skin.choose("此存档中的陆战位于", "This world's battle is in"),saved.id()))
    }

    fn reset_battle_fps(&mut self) {
        self.perf_at = Instant::now();
        self.perf_frames = 0;
        self.perf.rate = 0.;
    }

    fn battle_command(&mut self, command: battle_view::Command) {
        use battle_view::Command;
        match command {
            Command::Back => {
                self.battle_view = None;
                self.hits.clear();
            }
            Command::Pause | Command::SpeedUp | Command::SpeedDown => {
                if let Some(clock)=self.state.session.as_ref() {
                    let speed=match command {
                        Command::Pause => if clock.paused { clock.speed } else { 0 },
                        Command::SpeedUp => if clock.paused { 1 } else { (clock.speed * 2).min(4) },
                        _ => if clock.paused { 0 } else { clock.speed / 2 },
                    };
                    if speed==0 {if let Some(view)=&mut self.battle_view {view.clear_controls();}}
                    self.hud_action(HudCommand::Clock(speed));
                }
            }
            Command::End => {
                #[cfg(windows)]
                if let Some(native)=&mut self.config.native {
                    if let Some(world)=native.active_world_mut().filter(|world|world.land_battle_in_progress()) {
                        world.finish_land_battle();
                        native.reset_world_tick();
                    }
                }
            }
            _ => {
                #[cfg(windows)]
                if let (Some(view), Some(terrain), Some(battle)) = (
                    self.battle_view.as_mut(), self.battle_terrain.as_ref().map(|(_,terrain)|terrain),
                    self.config.native.as_mut().and_then(native_start::NativeSession::active_world_mut)
                        .and_then(|world| world.land_battle_mut()),
                ) {
                    view.command(command, battle, terrain);
                }
            }
        }
        self.dirty = true;
    }
    fn search_results(&self)->Vec<Object> {
        let q=self.search.as_deref().unwrap_or("").trim().to_ascii_lowercase();
        if q.is_empty(){return Vec::new();}
        let items=self.world.places.iter().enumerate().map(|(i,p)|(Object::Place(i),p.rank,&p.name,&p.id))
            .chain(self.world.polities.iter().enumerate().map(|(i,p)|(Object::Polity(i),p.rank,&p.name,&p.id)));
        let mut rows:Vec<_>=items.filter_map(|(o,rank,name,id)| {
            if !ui::can_read_object(&self.world, self.written_world(), o) { return None; }
            let name=name.to_ascii_lowercase();
            let localized=ui::object_name(&self.world,&self.skin,o).to_ascii_lowercase();
            ((name.contains(&q)||localized.contains(&q)||id.contains(&q)||q.strip_prefix("state:")==Some(id))&&self.available(o))
                .then(||(localized!=q&&name!=q,!localized.starts_with(&q)&&!name.starts_with(&q),rank,localized,o))
        }).collect();
        rows.sort_by(|a,b|(&a.0,&a.1,&a.2,&a.3).cmp(&(&b.0,&b.1,&b.2,&b.3)));
        rows.into_iter().take(6).map(|r|r.4).collect()
    }
    fn accept_search(&mut self) {
        if let Some(o)=self.search_results().first().copied(){self.locate_object(o);return;}
        if let Some(q)=self.search.as_ref() {
            let values:Result<Vec<f64>,_>=q.split(|c:char|c.is_whitespace()||c==',').filter(|s|!s.is_empty()).map(str::parse).collect();
            if let Ok(v)=values {
                if v.len()==2&&(-180. ..=180.).contains(&v[0])&&(-90. ..=90.).contains(&v[1]){
                    self.locate([v[0],v[1]],self.camera.mpp.min(1200.));return;
                }
            }
        }
        self.feedback=self.skin.choose("没有匹配的地点或国家","No matching place or country").into();
    }
    fn object_at(&self,q:[f64;2])->[u8;2] {
        let dated=|[owner,admin]:[u8;2]| {
            let owner=owner.checked_sub(1).filter(|i|self.available(Object::Polity(usize::from(*i))))
                .map_or(0,|i|i+1);
            [owner,admin]
        };
        for &i in self.visible.iter().rev() {
            let t=&self.world.tiles[i];
            if camera::inside(q,t.core) {
                if let Some(p)=self.cached.get(&i) {return dated(p.page.ids_at(t,q));}
            }
        }
        self.base.as_ref().map_or([0,0],|p|dated(p.ids_at(&self.world.tiles[0],q)))
    }
    fn click(&mut self,p:[f64;2]) {
        if self.opening_nav.cloud.is_some() || self.opening_nav.departure_cloud.is_some() || self.opening_nav.arrival_cloud.is_some() {
            if lobby::contains(lobby::cloud_skip_rect(self.size), p) { self.skip_opening_transition(); }
            return;
        }
        if let (Some(view),Some((_,terrain)))=(&mut self.battle_view,&self.battle_terrain){
            let command=view.left_button(true,p,self.size,terrain);
            view.left_button(false,p,self.size,terrain);
            if let Some(command)=command {self.battle_command(command);}
            return;
        }
        if self.loading(){return;}
        if let Some(panel)=self.population_debug.as_mut().filter(|_|p[1]<f64::from(self.size[1].saturating_sub(92))) {
            if panel.contains(self.size,p) {
                if let Some(page) = panel.page_at(self.size, p) { self.population_page(page); }
                else { panel.click_control(self.size, p); self.dirty=true; }
                return;
            }
            let [x,y]=p.map(|v|v as f32);
            let object=self.hits.iter().rev().find_map(|hit| {
                let [left,top,width,height]=hit.area;
                match hit.action {
                    Action::Select(object @ Object::Place(_)) if x>=left&&x<=left+width&&y>=top&&y<=top+height => Some(object),
                    _ => None,
                }
            }).or_else(|| {
                let q=camera::geographic(self.camera.vector(p,self.size)?);
                let [polity,admin]=self.object_at(q);
                admin.checked_sub(1).map(|i|Object::Administration(usize::from(i)))
                    .filter(|&object|self.available(object))
                    .or_else(||polity.checked_sub(1).map(|i|Object::Polity(usize::from(i))).filter(|&object|self.available(object)))
            });
            self.population_location(object);
            return;
        }
        let [x,y]=p.map(|v|v as f32);
        let contains=|[a,b,w,h]:[f32;4]| x>=a&&x<=a+w&&y>=b&&y<=b+h;
        if self.hud.menu==HudMenu::MapModes&&contains(formal_ui::map_modes_rect(self.size)) {
            if let Some(hit)=self.hits.iter().find(|hit|matches!(hit.action,Action::Mode(_))&&contains(hit.area)) {
                self.action(hit.action);
            }
            return;
        }
        let radius=(self.size[0] as f32*0.056).clamp(52.,78.);
        let in_menu=self.hud.menu!=HudMenu::None&&contains(formal_ui::menu_rect(self.hud.menu,self.size,radius));
        let in_country=!self.hud.menu.modal()&&self.country.is_some_and(|panel|contains(panel.rect(self.size)));
        if let Some(hit)=self.hits.iter().rev().find(|h|{
            let gear=matches!(h.action,Action::Hud(HudCommand::Menu(HudMenu::System)))&&h.area[1]==0.;
            let portrait=match h.action{Action::Hud(HudCommand::PortraitAction(i,_))=>formal_ui::portrait_action_hit(i,self.size[1] as f32,p),_=>true};
            contains(h.area)&&(!gear||formal_ui::gear_hit(p,self.size[0]))
                &&portrait
                &&(!in_menu||!matches!(h.action,Action::Country(_)|Action::Select(_)))
                &&(!self.transport_panel_at(p)||!matches!(h.action,Action::Select(_)))
                &&(!in_country||in_menu||matches!(h.action,Action::Country(_)))
                &&(!self.details||!matches!(h.action,Action::Select(_))||self.search.is_some())
        }) {
            let action=hit.action;
            match action {
                Action::Hud(HudCommand::PlayerCountry) if self.search.is_none()&&self.hud.menu==HudMenu::None
                    && p[0]<=104. && p[1]<=76.=>{
                    if let Some(i)=self.player_polity(){self.click_country(i,p);}
                }
                Action::Select(_) if self.hud.market_map=>{},
                Action::Select(object) if self.search.is_none()
                    && (self.hud.page == HudPage::Travel || self.planning_transport()) => {
                    let place = match object { Object::Place(index) => Some(index), _ => None };
                    self.pick_transport_destination(p, place);
                }
                Action::Select(Object::Polity(i)) if self.search.is_none()&&self.hud.menu==HudMenu::None&&self.hud.page==HudPage::Map=>{
                    self.click_country(i,p);
                }
                Action::Select(Object::Place(_)) if !in_country && self.pick_transport(p)=>{},
                _=>self.action(action),
            }
            return;
        }
        if self.is_panel(p){return;}
        if self.pick_transport_destination(p,None)||self.pick_transport(p)||self.hud.market_map{return;}
        let coordinates=self.camera.vector(p,self.size).map(camera::geographic);
        let map_hit = coordinates.map(|q| self.object_at(q));
        let hit = map_hit.map(|owner| owner[0]);
        if self.in_lobby(){
            use lobby::SelectionStage;
            if self.lobby_page != lobby::Page::Selection { return; }
            self.opening_nav.last_input = Instant::now();
            if self.opening_nav.stage == SelectionStage::Globe {
                if coordinates.is_some() {
                    self.opening_nav.stage = SelectionStage::Directory;
                    self.filter_countries();
                    self.opening_shift(-0.11);
                }
                return;
            }
            let index = hit.and_then(|value| value.checked_sub(1)).map(usize::from)
                .filter(|&i| self.available(Object::Polity(i)));
            if self.opening_nav.stage == SelectionStage::Directory {
                if let Some(index) = index { self.lobby_action(lobby::Command::Country(index)); }
                return;
            }
            if self.world.polities[self.lobby_country].id == "country_fra" {
                let admin = map_hit.and_then(|owner| {
                    (index == Some(self.lobby_country)).then_some(owner[1])?.checked_sub(1).map(usize::from)
                }).or_else(|| {
                    let point = coordinates?;
                    self.world.admin.iter().position(|admin| admin.contains(point))
                });
                if let Some(admin) = admin { self.lobby_action(lobby::Command::MapArea(admin)); }
            }
            return;
        }
        let polity=hit.and_then(|v|v.checked_sub(1)).map(usize::from);
        self.select_transport(None);
        if coordinates.is_some_and(|q|self.click_military_cell(q,polity)){return;}
        if self.hud.page==HudPage::Map {
            if let Some(i)=polity.filter(|_|self.hud.menu==HudMenu::None){self.click_country(i,p);return;}
        }
        self.country_click=None;
        self.select(polity.map(Object::Polity));
    }

    fn transport_panel_at(&self, p: [f64; 2]) -> bool {
        let Some((_, detail))=self.transport_detail.as_ref().filter(|_|self.transport_detail_visible()) else{return false;};
        let [x,y,w,h]=detail.rect(self.size,self.hud.transport_detail_expanded).map(f64::from);
        p[0]>=x && p[0]<=x+w && p[1]>=y && p[1]<=y+h
    }
    fn is_panel(&self,p:[f64;2])->bool {
        if self.loading(){return true;}
        let [x,y]=p;
        let contains=|[a,b,w,h]:[f32;4]| x>=f64::from(a)&&x<=f64::from(a+w)&&y>=f64::from(b)&&y<=f64::from(b+h);
        let [w,h]=self.size.map(|v|v as f32);
        if self.in_lobby(){
            return self.lobby_request||match self.lobby_page {
                lobby::Page::Selection => (match self.opening_nav.stage {
                    lobby::SelectionStage::Globe => false,
                    lobby::SelectionStage::Directory => lobby::contains(lobby::directory_rect(self.size), p),
                    lobby::SelectionStage::Profile => self.opening_layout().is_some_and(|layout| layout.contains(&self.opening_nav, p)),
                })
                    || lobby::contains([12., 14., 67., 30.], p)
                    || lobby::contains([12., h - 44., 124., 30.], p),
                _=>true,
            };
        }
        let radius=(w*0.056).clamp(52.,78.);
        let modal=self.hud.menu.modal();
        modal||self.search.is_some()||self.details||self.transport_panel_at(p)||
            self.country.is_some_and(|country|contains(country.rect(self.size)))||
            formal_ui::page_rect(&self.hud,self.size).is_some_and(contains)||
            (self.hud.menu!=HudMenu::None&&contains(formal_ui::menu_rect(self.hud.menu,self.size,radius)))||
            (self.hud.messages&&contains(formal_ui::message_rect([w,h],((h+16.)*0.5).max(190.))))||
            self.hits.iter().any(|hit|{
                let gear=matches!(hit.action,Action::Hud(HudCommand::Menu(HudMenu::System)))&&hit.area[1]==0.;
                !matches!(hit.action,Action::Select(_))&&contains(hit.area)&&(!gear||formal_ui::gear_hit(p,self.size[0]))
            })||
            (self.hud.page==HudPage::Map && match self.selected {
                Some(Object::Polity(_))=>false,
                Some(_)=>contains([17.,73.,300.,213.]),
                None=>false,
            })
    }
    fn set_date(&mut self,date:Date) {
        if self.config.managed||self.config.world.is_some(){self.feedback="日期由正式世界时钟决定。".into();self.dirty=true;return;}
        self.state.date=date;
        if let Some(model)=self.state.timeline.as_mut(){model.set_date(date);}
        if self.selected.is_some_and(|o|!self.available(o)){self.select(None);}
        self.dirty=true;
    }
    fn queue_screenshot(&mut self) {
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
    fn key(&mut self,key:Key) {
        self.country_click=None;
        if key==Key::Named(NamedKey::F8){self.hud.mechanical.hidden=!self.hud.mechanical.hidden;self.dirty=true;return;}
        if key==Key::Named(NamedKey::F12){self.queue_screenshot();return;}
        if key==Key::Named(NamedKey::F10){
            self.debug=!self.debug;self.perf_at=Instant::now();self.perf_frames=0;self.perf.rate=0.;self.dirty=true;return;
        }
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
        if self.opening_nav.cloud.is_some() || self.opening_nav.departure_cloud.is_some() || self.opening_nav.arrival_cloud.is_some() {
            if matches!(key, Key::Named(NamedKey::Escape | NamedKey::Enter | NamedKey::Space)) {
                self.skip_opening_transition();
            }
            return;
        }
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
                    lobby::Page::Cloud => lobby::Command::SkipCloud,
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
                            lobby::Page::Cloud=>self.lobby_action(lobby::Command::SkipCloud),
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
                    "0"=>Some(0),"1"=>Some(1),"2"=>Some(2),"4"=>Some(4),
                    "+"|"="=>Some(formal_ui::CLOCK_SPEEDS[(self.hud.mechanical.selected(formal_ui::clock_index(Some(s)))+1).min(3)]),
                    "-"=>Some(formal_ui::CLOCK_SPEEDS[self.hud.mechanical.selected(formal_ui::clock_index(Some(s))).saturating_sub(1)]),_=>None,
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
    fn type_country_search(&mut self,text:&str) {
        let query=&mut self.country_directory.query;
        let remaining=64_usize.saturating_sub(query.chars().count());
        query.extend(text.chars().filter(|c|!c.is_control()).take(remaining));
        self.opening_nav.offset = 0;
        self.filter_countries();
    }
    fn rotate(&mut self,from:[f64;2],to:[f64;2],bearing:bool) {
        self.focus=None;
        self.opening_nav.last_input = Instant::now();
        if bearing{self.camera.bearing_drag(from,to,self.size);}else{self.camera.drag(from,to,self.size);}
        self.camera.update_level();self.dirty=true;
    }
    fn zoom(&mut self,p:[f64;2],steps:f64) {
        self.opening_nav.last_input = Instant::now();
        self.focus=None;self.velocity=[0.;2];self.camera.zoom(p,1.22f64.powf(-steps.clamp(-60.,60.)),self.size);self.dirty=true;
    }
    fn refresh_tiles(&mut self,now:Instant) {
        self.candidate=self.index.visible(&self.world,&self.camera,self.size,true);
        self.visible=self.index.visible(&self.world,&self.camera,self.size,false);
        for id in &self.candidate {if let Some(p)=self.cached.get_mut(id){p.used=now;}}
        self.cached.retain(|_,p|now.duration_since(p.used)<=CACHE_TTL);
        if self.reader.inflight.is_some(){return;}
        let city_first=self.mode==Mode::Geographic && self.camera.mpp<camera::CITY_INK_MPP
            && self.renderer.as_ref().is_some_and(|r|r.terrain_max_level()>0);
        let city=self.visible.iter().filter(|&&id|city_first&&self.world.tiles[id].city
            && self.index.scissor(id,&self.camera,self.size).is_some());
        let Some(i)=city.chain(self.visible.iter()).chain(self.candidate.iter()).copied()
            .find(|i|!self.cached.contains_key(i)&&!self.failed.contains(i))else{return;};
        let tile=&self.world.tiles[i];
        let required=tile.data_size()-if self.reader.cover {0}else{tile.cover_size()};
        let mut occupied=self.cached.values().map(|p|p.page.bytes).sum::<usize>();
        if occupied+required>CACHE_BUDGET {
            let mut evict:Vec<_>=self.cached.iter().filter(|(id,_)|!self.visible.contains(id))
                .map(|(id,p)|(*id,p.used,p.page.bytes)).collect();
            evict.sort_by_key(|row|row.1);
            for (id,_,n) in evict {
                self.cached.remove(&id);occupied-=n;
                if occupied+required<=CACHE_BUDGET{break;}
            }
        }
        if occupied+required<=CACHE_BUDGET{self.reader.request(i,tile);}
    }
    fn draw(&mut self)->io::Result<()> {
        let now=Instant::now();
        if self.battle_view.is_some() {return self.draw_battle(now);}
        self.refresh_tiles(now);
        let date=self.state.date.to_string();
        let mut view=View::new(&self.camera,self.size);
        let active=World::active_politics(&date);
        if self.camera.mpp<700.{self.grid_step=25000.;}else if self.camera.mpp>900.{self.grid_step=50000.;}
        view.settings=[self.state.date.season_day(),self.mode.index() as f32,u8::from(active) as f32,u8::from(self.theme) as f32];
        view.map_style[1]=self.renderer.as_ref().unwrap().terrain_max_level() as f32;
        let land_detail=self.mode==Mode::Geographic && !self.in_lobby();
        view.close_sample=self.renderer.as_mut().unwrap().update_close_terrain(&self.camera,self.size,land_detail,now);
        view.map_style[3]=if self.hud.military_grid{self.grid_step}else{0.};
        if self.military_grid_active(){
            if let Some(selection)=self.military_cell {view.military_cell=selection.cell.highlight();}
        }
        view.selection[3]=self.world.polities.iter().position(|p|p.id=="country_fra").map_or(0.,|i|(i+1) as f32);
        view.map_style[0]=self.player_polity().map_or(0.,|i|(i+1) as f32);
        if let Some(Object::Polity(i))=self.selected{view.selection[0]=(i+1) as f32;}
        if let Some(Object::Administration(i))=self.selected{view.selection[2]=(i+1) as f32;}
        if let Some(model)=self.state.timeline.as_ref() {
            let mut count=0;
            for (i,s) in model.region_sites("paris") {
                let state=model.at(i).code();
                if state==0. {continue;}
                let [lon,lat]=s.center_lon_lat;
                view.edits[count]=Edit{area:[lon as f32,lat as f32,s.radius_m[0],s.radius_m[1]],state:[state,s.layout as f32,0.,0.]};
                count+=1;
            }
            view.selection[1]=count as f32;
        }
        let center=self.camera.coordinates();
        let coord=self.camera.vector(self.cursor,self.size).map(camera::geographic);
        let pointer=self.skin.choose("坐标","Coordinates");
        let mouse=coord.map_or_else(||self.skin.choose("坐标 · 太空","Coordinates · Space").into(),
            |p|format!("{pointer} · {:.4}, {:.4}",p[0],p[1]));
        let owner=coord.map_or([0,0],|p|self.object_at(p));
        let admin=if active {owner[1].checked_sub(1).and_then(|i|self.world.admin.get(i as usize))
            .map_or(String::new(),|p|self.skin.division_name(p).into())}else{String::new()};
        let mut source=if self.renderer.as_ref().unwrap().packed_terrain() {
            self.skin.choose("SRTM15+ V2.5.5 · ESA · HydroRIVERS（现代参照）","SRTM15+ V2.5.5 · ESA · HydroRIVERS (modern reference)").to_owned()
        } else if view.map_style[1]>0. {self.skin.choose("SRTM15+ · ESA · HydroRIVERS（现代参照）","SRTM15+ · ESA · HydroRIVERS (modern reference)").to_owned()}else{self.visible.iter().rev().find(|&&id|self.cached.contains_key(&id)&&camera::inside(center,self.world.tiles[id].core))
            .map_or("World / R68 ETOPO relief",|&id|self.world.tiles[id].source.as_str()).to_owned()};
        if source=="Paris" {source.push_str(" / APUR, IGN, (c) OpenStreetMap contributors / modern");}
        if self.mode!=Mode::Geographic && !active {source.push_str(" / historical boundaries unavailable");}
        if let Some(model)=&self.state.timeline {source=format!("SIMULATION   {} / {}",model.sites[self.site].label,model.at(self.site).label());}
        let (econ_label,econ_legend)=self.state.legend();
        let search=self.search_results();
        let flag_index=if self.in_lobby(){Some(self.lobby_country)}else{self.player_polity()};
        let flags=flag_index.map(|i|self.visuals.record(i)).filter(|v|v.active(&date)).map(|v|v.flag);
        let country=self.country.map(|panel|{
            let flag=self.visuals.record(panel.polity);
            (&self.world,panel,flag.active(&date).then_some(flag.flag))
        });
        self.perf.tiles=self.cached.len();self.perf.visible=self.visible.len();
        self.perf.mib=self.cached.values().map(|p|p.page.bytes).sum::<usize>() as f64 / 1048576.;
        self.perf.streaming=self.reader.inflight.is_some();
        #[cfg(windows)]
        let written_world = self.config.native.as_ref().and_then(native_start::NativeSession::active_world);
        #[cfg(not(windows))]
        let written_world = None;
        let loading=self.loading();
        let transport_world=written_world.filter(|_|!loading&&!self.in_lobby()&&!self.hud.menu.modal());
        let planning_transport = self.planning_transport();
        #[cfg(windows)]
        let transport_route = self.config.native.as_ref().and_then(native_start::NativeSession::selected_transport_route);
        #[cfg(not(windows))]
        let transport_route = None;
        if let Some(world)=transport_world {
            if self.transport_scene.is_none() {
                self.transport_scene=Some(transport_scene::TransportScene::new(world.transport())?);
            }
            self.transport_scene.as_mut().unwrap().update_map(&self.camera,self.size,&date,self.mode,world,
                self.transport_selection.as_ref(), transport_route, planning_transport)?;
        }
        let show_transport_detail=self.transport_detail_visible();
        if let (Some(world),Some(scene),Some(selected))=(transport_world,self.transport_scene.as_ref(),
            self.transport_selection.as_ref().filter(|_|show_transport_detail))
        {
            let minute=world.clock().snapshot().total_minutes;
            if self.transport_detail.as_ref().is_none_or(|(previous,_)|*previous!=minute) {
                let context=transport_ui::Context{skin:&self.skin,world,map:&self.world,mode:self.mode,date:&date,scene,debug:self.debug};
                self.transport_detail=transport_ui::Detail::build(&context,selected).map(|detail|(minute,detail));
            }
        }
        let formal=formal_ui::Display{skin:&self.skin,hud:&self.hud,session:self.state.session.as_ref(),date:self.state.date,country,
            camera:&self.camera,size:self.size,mode:self.mode,flags,cursor:self.cursor,source:&source,feedback:&self.feedback,labels:self.labels,managed:self.config.managed,
            written_world, modern_terrain:view.map_style[1]>0.,
            surveyed_terrain:view.close_sample[0]>0. && view.close_sample[2]>0.5,
            debug:self.debug.then_some(&self.perf),population_debug:self.population_debug.is_some()};
        let seconds=self.started.elapsed().as_secs_f32();
        let (mut meshes,hits)=if loading {
            let status=self.state.lobby.as_ref().map(|s|s.status.as_str()).filter(|s|!s.is_empty())
                .unwrap_or(if self.lobby_request{"正在进入世界"}else{"正在读取地图资料"});
            (formal.loading(status,seconds),Vec::new())
        }else if self.in_lobby(){
            formal.lobby(&self.world,self.state.lobby.as_ref(),self.lobby_page,self.lobby_country,self.lobby_request,&self.country_directory,self.prologue.as_ref(),
                lobby::SelectionView { navigation: &self.opening_nav, camera: &self.camera, visuals: &self.visuals, world: &self.world })
        }else{ui::compose(&self.world,&self.atlas,Ui{
            mode:self.mode,date:&date,camera:&self.camera,size:self.size,selected:self.selected,admin:&admin,details:self.details,country:self.country,
            search:self.search.as_deref(),search_results:&search,econ_label:&econ_label,econ_legend:&econ_legend,
            mouse:&mouse,labels:self.labels,formal,
            transport_detail:self.transport_detail.as_ref().filter(|_|show_transport_detail).map(|(_, detail)|detail),
            sea_relation_visible: transport_world.is_some() && self.transport_scene.as_ref()
                .is_some_and(transport_scene::TransportScene::sea_relation_visible),
        },&mut self.shown_markers)};
        if let Some(panel)=self.population_debug.as_ref().filter(|_|!loading&&!self.in_lobby()) {
            let (layers,text)=meshes.split_at_mut(12);
            panel.draw(self.size,&self.skin,&mut layers[11].0,&mut text[0].0);
        }
        if let Some((_,status))=&self.screenshot_status {
            let [w,h]=self.size.map(|n|n as f32);let width=(w-48.).min(940.);let x=(w-width)*0.5;
            let y=if loading||self.in_lobby(){h-98.}else{h-159.};
            meshes[4].0.rect(x,y,width,28.,[8,13,20,247]);
            self.skin.text(&mut meshes[9].0,status,0,[x+9.,y+4.],width-18.,formal_ui::IVORY);
        }
        let mut fade=None;
        if let Some(start)=self.loading_fade {
            let t=(start.elapsed().as_secs_f32()/0.32).clamp(0.,1.);
            if t<1. && !loading {
                let mut old=formal.loading(&self.loading_status,seconds);
                for (mesh,_) in &mut old {for point in &mut mesh.vertices {point.color[3]=(f32::from(point.color[3])*(1.-t)) as u8;}}
                fade=Some(old);
            }
        }
        let cloud = if let Some(start) = self.opening_nav.cloud {
            let time = start.elapsed().as_secs_f32();
            let opacity = lobby::ease_cloud(time / 0.74) *
                (1. - lobby::ease_cloud((time - 1.55) / (lobby::CLOUD_OPEN_TIME - 1.55)));
            Some((opacity, time / lobby::CLOUD_OPEN_TIME))
        } else if let Some(start) = self.opening_nav.departure_cloud {
            let time = start.elapsed().as_secs_f32();
            Some((lobby::ease_cloud(time / 0.70), time / lobby::CLOUD_DEPART_TIME * 0.45))
        } else if let Some(start) = self.opening_nav.arrival_cloud {
            let t = start.elapsed().as_secs_f32() / lobby::CLOUD_ARRIVE_TIME;
            if t < 1. { Some((1. - lobby::ease_cloud(t), 0.45 + 0.55 * t)) }
            else { self.opening_nav.arrival_cloud = None; None }
        } else { None };
        if let Some((opacity, travel)) = cloud {
            fade = Some(lobby::cloud_cover(self.size, opacity, travel, &self.skin));
        }
        let needs_overlay=matches!(self.mode,Mode::Political|Mode::Economic)
            ||self.mode==Mode::Military&&view.map_style[3]>0.;
        let pages:Vec<_>=self.visible.iter().filter_map(|&id| {
            let tile=&self.world.tiles[id];
            if view.map_style[1]>0.&&!needs_overlay&&!tile.city&&view.selection[1]<0.5{return None;}
            let p=self.cached.get(&id)?;
            let progress=(now.duration_since(p.ready).as_secs_f32()/0.16).clamp(0.,1.);
            let opacity=progress*progress*(3.-2.*progress)*tile.weight(self.camera.mpp);
            let scissor=self.index.scissor(id,&self.camera,self.size)?;
            (opacity>0.).then_some((&p.page,tile,scissor,opacity))
        }).collect();
        let mut models=if loading||self.in_lobby() {Vec::new()} else {
            self.landmarks.as_ref().map_or_else(Vec::new,|catalogue|catalogue.visible(&date,&self.camera,self.size))
        };
        let scene = self.prologue.as_ref().zip(self.opening_choice())
            .filter(|_| self.lobby_page == lobby::Page::Prologue)
            .map(|(draft, opening)| prologue_ui::scene_index(opening, &draft.place));
        let renderer=self.renderer.as_mut().unwrap();
        if let Some(index) = scene { renderer.show_prologue_scene(index)?; }
        self.hits=models.iter().filter_map(|model| {
            let place=model.place?;
            renderer.has_model(model).then_some(Hit {
                area:model.screen_bounds,action:Action::Select(Object::Place(place)),
            })
        }).chain(hits).collect();
        let vehicle_markers;
        let transport=if let (Some(world),Some(scene))=(transport_world,self.transport_scene.as_mut()) {
            if self.debug && !show_transport_detail && self.hud.page==HudPage::Map && self.hud.menu==HudMenu::None
                && !self.hud.market_map && self.country.is_none() && self.search.is_none() {
                scene.caption(&self.skin,self.cursor,self.size,world,&mut meshes);
            }
            vehicle_markers=scene.draw_vehicles(&self.camera,self.size,world,
                &mut models,|model|renderer.has_model(model));
            Some(render::TransportOverlay{network:scene.map_overlay(),economy:scene.economic_overlay(),vehicles:&vehicle_markers})
        } else {None};
        renderer.update_terrain(&self.camera,self.size,now)?;
        view.map_style[2]=renderer.terrain_view_level() as f32;
        view.natural_lod=renderer.terrain_viewport_mix();
        view.set_terrain_exact(renderer.terrain_exact());
        let landscape_enabled=!loading&&(!self.config.managed||self.state.session.is_some())&&self.mode==Mode::Geographic;
        renderer.prepare_rivers(&self.camera,self.size,landscape_enabled&&!renderer.terrain_exact());
        if self.last_palette!=Some(self.state.date) {
            renderer.set_politics(&self.state.palette(&self.world,&date,&self.visuals,&self.employment),&self.visuals.uniforms(&date));self.last_palette=Some(self.state.date);
        }
        let player_capture=self.screenshot.is_some();
        let capture=self.screenshot.as_ref().or_else(||self.trial.captures.first())
            .or_else(||self.trial.terrain_capture.as_ref().map(|(_,path)|path)).map(PathBuf::as_path);
        let mut redraw=false;
        let timing_frame=self.trial.timing_frame(capture.is_some());
        if let Some(result)=renderer.render(&view,self.base.as_ref().unwrap(),&pages,&meshes,fade.as_ref(),seconds,!loading,capture,&models,transport,
            (&self.camera,landscape_enabled&&!self.trial.hide_landscape_models,now),None,timing_frame)? {
            let presented=Instant::now();
            self.last_present=presented;
            if self.trial.first.is_none(){self.trial.first=Some(ms(self.started));}
            if player_capture {
                let path=self.screenshot.take().unwrap();
                let status=match result {Ok(())=>format!("F12  Saved: {}",path.display()),Err(e)=>format!("F12  Screenshot failed: {e}")};
                if let Some(window)=&self.window{window.set_title(&status);}
                self.screenshot_status=Some((presented,status));redraw=true;
            }
            else if capture.is_some(){
                result?;
                if let Some((id,png))=self.trial.terrain_capture.take() {
                    let samples=renderer.terrain_frame_samples(&self.camera,self.size);
                    let city_pages=pages.iter().filter(|(_,tile,_,_)|tile.city).map(|(_,tile,_,alpha)|
                        serde_json::json!({"path":tile.path,"core":tile.core,"opacity":alpha})).collect::<Vec<_>>();
                    let extra=serde_json::json!({"png":png,"terrain_samples":samples,"city_pages":city_pages});
                    self.write_observation(&id,extra)?;
                } else {self.trial.captures.remove(0);}
            }
            else if self.trial.timing {
                self.trial.record_frame(now,presented,&self.camera,renderer,false);
            }
            if self.debug {
                self.perf.cpu_ms=ms(now);
                self.perf_frames+=1;
                let dt=presented.duration_since(self.perf_at).as_secs_f64();
                if dt>=1.{self.perf.rate=f64::from(self.perf_frames)/dt;self.perf_frames=0;self.perf_at=presented;}
            }
        }
        self.dirty=redraw || self.screenshot.is_some() || !self.trial.captures.is_empty() || self.trial.terrain_capture.is_some();
        Ok(())
    }

    fn draw_battle(&mut self, now: Instant) -> io::Result<()> {
        #[cfg(windows)]
        let fixture = self.config.native.as_ref().and_then(native_start::NativeSession::active_world)
            .and_then(|world| world.land_battle_record());
        #[cfg(not(windows))]
        let fixture: Option<&wwo_map_lab::formal_bootstrap::WorldLandBattle> = None;
        let (Some(view), Some(terrain), Some(fixture)) = (
            self.battle_view.as_ref(), self.battle_terrain.as_ref().map(|(_,terrain)|terrain), fixture,
        ) else {
            self.battle_view = None;
            return Ok(());
        };
        let renderer = self.renderer.as_mut().unwrap();
        let meshes = battle_view::hud(self.size, &self.skin, view, fixture, terrain, renderer.battle_uses_original_model(),
            self.debug.then_some(self.perf.rate), self.state.session.as_ref());
        let map_view = View::new(&self.camera, self.size);
        let battle_frame = render::BattleFrame { view: &view.camera, state: &fixture.battle, terrain };
        let capture=self.screenshot.as_ref().or_else(||self.trial.captures.first()).map(PathBuf::as_path);
        let has_capture=capture.is_some();
        let timing_frame=self.trial.timing_frame(has_capture);
        if let Some(result) = renderer.render(&map_view, self.base.as_ref().unwrap(), &[], &meshes, None,
            self.started.elapsed().as_secs_f32(), false, capture, &[], None,
            (&self.camera, false, now), Some(battle_frame),timing_frame)?
        {
            let presented = Instant::now();
            self.last_present = presented;
            if self.trial.timing && !has_capture {
                self.trial.record_frame(now,presented,&self.camera,renderer,true);
            }
            if let Some(path) = self.screenshot.take() {
                let status = match result {
                    Ok(()) => format!("F12  Saved: {}", path.display()),
                    Err(error) => format!("F12  Screenshot failed: {error}"),
                };
                if let Some(window) = &self.window { window.set_title(&status); }
                self.screenshot_status = Some((presented, status));
            } else if has_capture {
                result?;
                self.trial.captures.remove(0);
            }
            if self.debug {
                self.perf.cpu_ms = ms(now);
                self.perf_frames += 1;
                let dt = presented.duration_since(self.perf_at).as_secs_f64();
                if dt >= 1. {
                    self.perf.rate = f64::from(self.perf_frames) / dt;
                    self.perf_frames = 0;
                    self.perf_at = presented;
                }
            }
        }
        self.dirty = self.screenshot.is_some()||!self.trial.captures.is_empty();
        Ok(())
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
    fn observe(&mut self,event_loop:&ActiveEventLoop) {
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
                if !self.scroll_population_debug(point,input.steps)&&!self.scroll_countries(point,input.steps){self.zoom(point,input.steps);}
            }
            "drag"=>{
                self.velocity=[0.;2];
                self.trial.movement=Some(([input.x,input.y],[input.to_x,input.to_y],input.frames.clamp(1,180),0));
            }
            "key"=>self.key(match input.value.as_str() {"Escape"=>Key::Named(NamedKey::Escape),"Space"|"space"=>Key::Named(NamedKey::Space),"Enter"=>Key::Named(NamedKey::Enter),"Home"=>Key::Named(NamedKey::Home),"Delete"=>Key::Named(NamedKey::Delete),"Backspace"=>Key::Named(NamedKey::Backspace),"ArrowUp"=>Key::Named(NamedKey::ArrowUp),"ArrowDown"=>Key::Named(NamedKey::ArrowDown),"ArrowLeft"=>Key::Named(NamedKey::ArrowLeft),"ArrowRight"=>Key::Named(NamedKey::ArrowRight),"PageUp"=>Key::Named(NamedKey::PageUp),"PageDown"=>Key::Named(NamedKey::PageDown),"F1"=>Key::Named(NamedKey::F1),"F2"=>Key::Named(NamedKey::F2),"F3"=>Key::Named(NamedKey::F3),"F4"=>Key::Named(NamedKey::F4),"F5"=>Key::Named(NamedKey::F5),"F6"=>Key::Named(NamedKey::F6),"F7"=>Key::Named(NamedKey::F7),"F8"=>Key::Named(NamedKey::F8),"F9"=>Key::Named(NamedKey::F9),"F10"=>Key::Named(NamedKey::F10),"Tab"=>Key::Named(NamedKey::Tab),_=>Key::Character(input.value.into())}),
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

    fn write_observation(&self,id:&str,extra:serde_json::Value)->io::Result<()> {
        let Some(path)=&self.config.observe else{return Ok(());};
        let response=serde_json::json!({"id":id,"state":self.status(),"extra":extra});
        fs::write(path.with_extension("response.json"),serde_json::to_vec(&response)?)
    }
    fn world_view_changed(&mut self, had_session:bool, loaded:bool, now:Instant) {
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

    fn poll(&mut self,event_loop:&ActiveEventLoop,now:Instant) {
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
            self.camera.focus_toward(focus.target,t,focus.mpp,self.size);
            self.dirty=true;
            if progress<1. {self.focus=Some(focus);}
        }
        if self.trial.timing&&self.trial.times.len()>=36_000 {self.trial.timing=false;}
        let scripted=self.trial.movement.map(|(a,b,steps,_)|
            std::array::from_fn(|i|(b[i]-a[i])/(f64::from(steps)*0.016)));
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
        let motion=scripted.unwrap_or_else(||match &self.drag {
            Some(d) if !d.bearing && now.saturating_duration_since(d.last)<Duration::from_millis(100)=>self.velocity,
            None=>self.velocity,
            _=>[0.;2],
        });
        let pointer=if self.drag.as_ref().is_some_and(|d|d.moved&&!d.bearing) {self.cursor}
            else {self.size.map(|n|f64::from(n)*0.5)};
        if self.focus.is_none() && self.camera.track_scale(self.size,motion,pointer,now) {self.dirty=true;}
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
                let mut attributes=Window::default_attributes().with_title("WWO | Rust strategic host")
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
            let opening_asset = |data: &[u8]| {
                if self.config.managed { decode_rgba(data) } else { Ok(blank()) }
            };
            let hud=[font(&self.config.root.join("hud-art.png"))?,hud_type_atlas(&self.config.root.join("hud-type.png"))?,
                if self.config.managed{font(&self.config.root.join("menu-painting.png"))?}else{blank()},
                opening_asset(include_bytes!("../../../data/character/prologue/parchment.png"))?,
                opening_asset(include_bytes!("../../../data/character/prologue/cloud.png"))?];

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
            let globe_art=[art("galactic-chart.png")?,decode_rgba(&include_bytes!("ocean-material.png")[..])?];
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
                        Err(error) if error.kind()==io::ErrorKind::NotFound=>None,
                        Err(error)=>{
                            eprintln!("Terrain detail {}: {error}",default.display());
                            None
                        }
                    }
                }
            }else{None};
            if self.map_signature.is_some()&&!self.config.terrain_review {
                let mut precision=self.world.city_detail(&self.map_root);
                if let Some(detail)=&detail {
                    precision.extend(detail.regions.iter().filter(|r|matches!(r.surface,terrain_detail::Surface::Survey))
                        .map(|r|camera::DetailRegion::new(r.extent,r.extent,r.size,false)));
                }
                self.camera.set_detail(precision);
            }
            let renderer=if let Some(window)=&window {
                pollster::block_on(Renderer::new(window.clone(),atlas,flags,hud,globe_art,&layouts,self.natural.take(),detail,self.events.clone(),self.config.observe.is_some()))?
            } else {
                let sample=self.config.terrain_close_sample.as_deref().map(render::CloseSample::read).transpose()?;
                pollster::block_on(Renderer::new_offscreen(self.size,atlas,flags,hud,globe_art,&layouts,self.natural.take(),sample,detail,self.events.clone()))?
            };
            let pixels=Pixels::read_version(&self.map_root,&self.world.tiles[0],self.map_signature,self.reader.cover)?;
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
            HostEvent::Model(key,mesh)=>{
                if let Some(renderer)=&mut self.renderer {
                    if let Err(error)=renderer.model_ready(key,mesh) {
                        let source=if key.is_transport() {"交通 GLB"}else{"R68 GLB"};
                        self.feedback=format!("{source} · {error}");
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
            Err(e) if self.map_signature.is_some()=>{
                self.fatal_error=Some(format!("正式地图无法读取 {} · {e}",self.world.tiles[event.id].path));
                event_loop.exit();
            }
            Err(e)=>{
                self.failed.insert(event.id);
                self.feedback=format!("Source tile unavailable: {e}");
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
                self.country_click=None;
                let steps=match delta {MouseScrollDelta::LineDelta(_,y)=>f64::from(y),MouseScrollDelta::PixelDelta(p)=>p.y/96.};
                if let Some(view) = &mut self.battle_view { view.zoom(steps); self.dirty = true; return; }
                if self.scroll_population_debug(self.cursor,steps) {return;}
                if self.scroll_countries(self.cursor,steps) {return;}
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
            if let Some(window)=&self.window{window.set_title("WWO | Rust strategic host");}
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
            || self.opening_nav.cloud.is_some() || self.opening_nav.departure_cloud.is_some() || self.opening_nav.arrival_cloud.is_some();
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

fn record_error(target:&Path,text:&str) {
    eprintln!("{text}");
    let _=fs::write(target,text);
}
fn main() {
    if let Err(e)=run(){
        #[cfg(windows)]
        if std::env::args_os().any(|arg|arg=="--terrain-review"||arg=="--background") {eprintln!("{e}");}
        else {desktop_start::show_error(&e.to_string());}
        #[cfg(not(windows))]
        eprintln!("{e}");
        std::process::exit(1);
    }
}
fn run() -> Result<(),Box<dyn std::error::Error>> {
    let started=Instant::now();
    let args=Config::parse()?;
    let error_log=args.observe.as_ref().filter(|_|args.background).map_or_else(
        ||args.root.parent().unwrap_or(&args.root).join("startup-error.txt"),
        |path|path.with_extension("error.txt"));
    let panic_log=error_log.clone();
    std::panic::set_hook(Box::new(move |e|record_error(&panic_log,&e.to_string())));
    let events=EventLoop::<HostEvent>::with_user_event().build()?;
    let mut app=match Host::new(args,&events,started) {
        Ok(app)=>app,Err(e)=>{record_error(&error_log,&e.to_string());return Err(e.into());}
    };
    events.run_app(&mut app)?;
    if let Some(error)=app.fatal_error {
        record_error(&error_log,&error);
        return Err(io::Error::other(error).into());
    }
    Ok(())
}
