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
mod landmarks;
mod map_release;
mod migration_status;
mod interface;
mod overlay;
mod politics;
mod render;
mod state;
mod terrain;
mod terrain_detail;
mod landscape;
mod landscape_cover;
mod landscape_models;
mod timeline;
mod ui;
mod world;

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

enum HostEvent {
    Map(Completion),
    Terrain(terrain::Completion),
    TerrainDetail(usize,io::Result<Vec<u8>>),
    Model(landmarks::ModelKey, io::Result<landmarks::ModelMesh>),
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
    #[cfg(windows)] native:Option<native_start::NativeSession>,
    #[cfg(windows)] desktop:Option<desktop_start::DesktopSession>}
impl Config {
    fn parse()->io::Result<Self> {
        let home=std::env::current_exe()?.parent().unwrap().to_owned();
        let mut result=Self{root:home.join("data"),world:None,requests:None,scenario:None,observe:None,managed:false,preferences:None,terrain_candidate:None,background:false,
            terrain_review:false,terrain_selection:terrain::LayerSelection::Auto,terrain_layer_candidate:None,
            terrain_close_sample:None,terrain_detail:None,
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
                let native=native_start::NativeSession::start()?;
                if result.preferences.is_none(){result.preferences=Some(native.preferences.clone());}
                result.native=Some(native);
                return Ok(result);
            }
        }
        if result.world.is_some() && result.scenario.is_some(){return Err(io::Error::other("world input and isolated land test are exclusive"));}
        if result.managed&&(result.world.is_none()||result.requests.is_none()){return Err(io::Error::other("formal menu requires bridge snapshot and requests paths"));}
        Ok(result)
    }
}
struct Resident {page:Page,ready:Instant,used:Instant}
struct Drag {at:[f64;2],origin:[f64;2],last:Instant,bearing:bool,moved:bool}
struct Pose {camera:Camera,object:Option<Object>}
struct Focus {start:Instant, camera:Camera, target:[f64;2], mpp:f64}
struct CountryClick {polity:usize,point:[f64;2],deadline:Instant}
#[derive(Default)]
struct Trial {
    last:String,timing:bool,times:Vec<f64>,previous:Option<Instant>,captures:Vec<PathBuf>,first:Option<f64>,loads:Vec<(String,f64)>,
    terrain_decodes:Vec<f64>,
    movement:Option<([f64;2],[f64;2],u32,u32)>,
    window_position:Option<winit::dpi::PhysicalPosition<i32>>,
    terrain_capture:Option<(String,PathBuf)>,
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
    lobby_page:lobby::Page,lobby_country:usize,lobby_request:bool,country_directory:lobby::Directory,
    bridge_wait:Instant,seen_lobby_busy:bool,departure_requested:bool,
    loading_fade:Option<Instant>,loading_status:String,
    debug:bool,perf_at:Instant,perf_frames:u32,perf:Diagnostics,
    screenshot:Option<PathBuf>,screenshot_status:Option<(Instant,String)>,
    grid_step:f32,last_present:Instant,employment:state::EmploymentReference,market_focus_serial:u64,
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
            let packed=config.terrain_candidate.is_some();
            let natural_root=config.terrain_candidate.clone().unwrap_or_else(||config.root.join(terrain::VERSION));
            Some((terrain::Catalogue::open(&natural_root,packed,config.terrain_selection,config.terrain_layer_candidate.clone())?,events.create_proxy()))
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
        let connected=state.session.is_some();
        let labels=!connected&&!config.managed&&!config.terrain_review;
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
        Ok(Self {natural,events:events.create_proxy(),landmarks,config,map_root,map_signature,fatal_error:None,world,visuals,index,reader,state,camera,atlas,started,base:None,window:None,renderer:None,
            cached:HashMap::new(),failed:HashSet::new(),candidate:Vec::new(),visible:Vec::new(),
            size:VIEW_SIZE,mode,theme:false,labels,selected:None,details:false,country:None,country_click:None,search:None,history:Vec::new(),focus:None,site:0,
            hits:Vec::new(),shown_markers:HashSet::new(),cursor:[640.,360.],drag:None,velocity:[0.;2],moved_at:Instant::now(),
            animate:false,next_date:Instant::now(),feedback:String::new(),dirty:true,last_input_check:Instant::now(),
            version:None,last_palette:None,trial:Trial{last:observation_id,..Trial::default()},hud:Hud{fullscreen:preferences.fullscreen,volume:preferences.volume,english:preferences.english,..Hud::default()},skin,exit_requested:false,
            lobby_page:lobby::Page::Home,lobby_country,lobby_request:false,country_directory:lobby::Directory::default(),
            bridge_wait:Instant::now(),seen_lobby_busy:false,departure_requested:false,
            loading_fade:None,loading_status:String::new(),debug:false,perf_at:Instant::now(),perf_frames:0,
            perf:Diagnostics{rate:0.,cpu_ms:0.,tiles:0,visible:0,mib:0.,streaming:false},
            screenshot:None,screenshot_status:None,grid_step:50000.,last_present:started,employment,market_focus_serial:0})
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
            let had_session=self.state.session.is_some();
            let revision=native.revision;
            self.feedback.clear();
            let dispatched=native.dispatch(request);
            let updated=native.update_view(&mut self.state);
            self.exit_requested|=native.exit;
            let loaded=native.revision!=revision;
            match updated {
                Ok(())=>self.world_view_changed(had_session, loaded, Instant::now()),
                Err(error)=>self.feedback=error.to_string(),
            }
            if let Err(error)=dispatched {self.feedback=error.to_string();}
            self.dirty=true;
            return;
        }
        if let Err(e)=request.output(self.config.requests.as_deref()) {self.feedback=format!("Host request: {e}");}
    }
    fn select(&mut self,object:Option<Object>) {
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
        self.focus=None;self.save_pose();self.camera.focus(target,mpp);
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
                self.mode=mode;self.hud.page=HudPage::Map;self.hud.menu=HudMenu::None;
                self.emit(Request::SetMapMode{mode:mode.key()});
            }
            Action::Home=>{
                self.focus=None;self.save_pose();self.camera.mpp=Camera::overview(self.size);self.camera.update_level();
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
                if self.hud.page==HudPage::Market&&page!=HudPage::Market{self.market_command("close",0);}
                if self.hud.page==HudPage::Relations&&page!=HudPage::Relations{
                    self.emit(Request::Relations{verb:"close",id:""});
                }else if page==HudPage::Relations&&self.hud.page!=HudPage::Relations{
                    self.emit(Request::Relations{verb:"open",id:""});
                }
                self.hud.page=page;self.hud.menu=HudMenu::None;
                self.hud.market_offset=0;
                self.details=false;self.country=None;self.search=None;
            }
            HudCommand::PortraitAction(_,page)=>self.hud_action(HudCommand::Page(page)),
            HudCommand::RelationDrawer(id)=>{
                self.hud.market_offset=0;
                self.emit(Request::Relations{verb:"drawer",id});
            }
            HudCommand::WorkAction(row,index)=>{
                let id=self.state.session.as_ref().and_then(|s|s.relations.as_ref())
                    .and_then(|r|r.work.get(row)).and_then(|r|r.actions.get(index))
                    .filter(|a|a.enabled).map(|a|a.id.clone());
                if let Some(id)=id{self.emit(Request::Relations{verb:"work_action",id:&id});}
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
                    self.hud.page=HudPage::Map;
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
            HudCommand::MilitaryGrid=>self.hud.military_grid=!self.hud.military_grid,
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
            HudCommand::Training(verb)=>{
                if self.state.session.is_some(){self.emit(Request::Training{verb});}
            }
            HudCommand::Market(verb,index)=>self.market_command(verb,index),
            HudCommand::MarketScroll(delta)=>{
                let count=self.state.session.as_ref().map_or(0,|s| {
                    if self.hud.page==HudPage::Property{return s.property.len();}
                    if self.hud.page==HudPage::Relations{return s.relations.as_ref().map_or(0,|view|{
                        if view.drawer=="work"{view.work.len()}else{view.rows.len()}
                    });}
                    let Some(v)=&s.market else{return 0;};
                    match self.hud.market_chooser.unwrap_or(&v.content){
                        "places"=>v.places.len(),"countries"=>v.countries.len(),
                        "good"=>v.offers.iter().filter(|o|o.good==v.good).count(),
                        "goods"=>v.catalog.len(),
                        "activity"=>v.orders.len(),"transport"=>v.logistics_len(),
                        _=>v.book.len(),
                    }
                });
                self.hud.market_offset=self.hud.market_offset.saturating_add_signed(delta as isize).min(count.saturating_sub(1));
            },
        }
    }
    fn in_lobby(&self)->bool {self.config.managed&&self.state.session.is_none()}
    fn loading(&self)->bool {
        self.config.managed && (self.lobby_request||self.state.lobby.as_ref().is_some_and(|s|s.loading||s.busy||
                self.lobby_page==lobby::Page::Selection&&!s.selection_ready&&self.feedback.is_empty()&&s.status.is_empty())
            || self.state.lobby.is_none()&&self.state.session.is_none()&&self.feedback.is_empty())
    }
    fn lobby_action(&mut self,command:lobby::Command){
        use lobby::{Command,Page};
        if !self.in_lobby(){return;}
        match command{
            Command::Page(page)=>{
                self.lobby_page=page;
                self.country_directory.search_active=false;
                self.country_directory.drag=None;
                self.lobby_request=false;self.seen_lobby_busy=false;
                match page{
                    Page::Selection=>{
                        self.country_directory=lobby::Directory::default();
                        self.mode=Mode::Political;
                        self.camera.mpp=lobby::SelectionLayout::globe_mpp(self.size);self.camera.update_level();
                        if let Some(lobby)=&mut self.state.lobby {lobby.selection_ready=false;}
                        self.emit(Request::Lobby{verb:"select",polity:"",slot:0});
                        self.filter_countries();
                        self.country_directory.reveal(self.size,self.lobby_country);
                    },
                    Page::Load=>self.emit(Request::Lobby{verb:"slots",polity:"",slot:0}),
                    Page::Home=>self.emit(Request::Lobby{verb:"home",polity:"",slot:0}),
                    _=>(),
                }
            }
            Command::Country(index)=>{
                if let Some(p)=self.world.polities.get(index){
                    self.country_directory.search_active=false;
                    self.lobby_country=index;self.camera.focus(p.coordinates,self.camera.mpp);
                    self.country_directory.reveal(self.size,index);
                }
            }
            Command::Search=>{
                self.country_directory.search_active=true;
                if let Some(window)=&self.window {window.set_ime_allowed(true);}
            }
            Command::ClearSearch=>{
                self.country_directory.query.clear();
                self.country_directory.search_active=false;
                self.filter_countries();
                self.country_directory.reveal(self.size,self.lobby_country);
            }
            Command::Enter=>{
                if self.lobby_page!=Page::Selection || self.lobby_request {return;}
                if let Some(id)=self.world.polities.get(self.lobby_country).and_then(|p|
                    self.state.lobby.as_ref().filter(|s|s.selection_ready&&!s.busy).and_then(|s|s.opening(p))
                ).map(|opening|opening.id.clone()){
                    self.lobby_request=true;self.bridge_wait=Instant::now();self.seen_lobby_busy=false;
                    self.emit(Request::Lobby{verb:"new",polity:&id,slot:0});
                }
            }
            Command::Load(slot)=>{
                self.lobby_request=true;self.bridge_wait=Instant::now();self.seen_lobby_busy=false;
                self.emit(Request::Lobby{verb:"load",polity:"",slot});
            }
            Command::Exit=>self.exit_requested=true,
        }
        if !self.country_directory.search_active {
            if let Some(window)=&self.window {window.set_ime_allowed(false);}
        }
        self.dirty=true;
    }
    fn filter_countries(&mut self) {
        self.country_directory.filter(&self.world,self.state.lobby.as_ref(),&self.state.date.to_string(),self.hud.english);
        self.dirty=true;
    }
    fn scroll_countries(&mut self,point:[f64;2],steps:f64)->bool {
        if self.in_lobby() && self.lobby_page==lobby::Page::Selection
            && lobby::contains(lobby::SelectionLayout::new(self.size).directory,point)
        {
            self.country_directory.scroll(self.size,steps as f32);
            self.dirty=true;
            return true;
        }
        false
    }
    fn market_command(&mut self,verb:&'static str,index:usize){
        if self.state.session.is_none(){self.feedback="正式世界未连接".into();return;}
        if verb=="open"{
            if self.mode!=Mode::Economic || self.hud.page==HudPage::Market{return;}
            let selected=self.selected.filter(|o|matches!(o,Object::Polity(i) if !self.world.polities[*i].display_only));
            let id=selected.map(|o|self.id(o)).unwrap_or_default();
            self.hud.page=HudPage::Market;self.hud.menu=HudMenu::None;self.hud.market_chooser=None;
            self.hud.market_offset=0;self.details=false;self.country=None;self.search=None;
            self.emit(Request::Market{verb,id:&id,site:"",quantity:0,token:0,viewport:self.size});return;
        }
        if verb=="close"{
            self.hud.page=HudPage::Map;self.hud.market_chooser=None;self.hud.quantity=None;
            self.focus=None;self.velocity=[0.;2];
            self.emit(Request::Market{verb,id:"",site:"",quantity:0,token:0,viewport:self.size});return;
        }
        let Some(session)=self.state.session.as_ref() else{return;};
        let Some(v)=session.market.as_ref() else{return;};
        let mut id=String::new();let mut site=String::new();let mut quantity=0;let mut token=0;
        let actual=match verb {
            "places"|"countries"=>{
                self.hud.market_chooser=if self.hud.market_chooser==Some(verb){None}else{Some(verb)};
                self.hud.market_offset=0;return;
            }
            "regional" if v.region.is_empty()||!v.places.iter().any(|row|row.id==v.region)=>{
                let Some(row)=v.places.iter().find(|row|row.id==session.place).or_else(||v.places.first()) else{return;};
                id=row.id.clone();"region"
            }
            "international"|"domestic"|"regional"=>{id=verb.into();"scope"}
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
            "buy"=>{
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
        self.hud.quantity=None;self.hud.market_offset=0;self.hud.market_chooser=None;
        self.emit(Request::Market{verb:actual,id:&id,site:&site,quantity,token,viewport:self.size});
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
    fn search_results(&self)->Vec<Object> {
        let q=self.search.as_deref().unwrap_or("").trim().to_ascii_lowercase();
        if q.is_empty(){return Vec::new();}
        let items=self.world.places.iter().enumerate().map(|(i,p)|(Object::Place(i),p.rank,&p.name,&p.id))
            .chain(self.world.polities.iter().enumerate().map(|(i,p)|(Object::Polity(i),p.rank,&p.name,&p.id)));
        let mut rows:Vec<_>=items.filter_map(|(o,rank,name,id)| {
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
        if self.loading(){return;}
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
                &&(!in_country||in_menu||matches!(h.action,Action::Country(_)))
                &&(!self.details||!matches!(h.action,Action::Select(_))||self.search.is_some())
        }) {
            let action=hit.action;
            match action {
                Action::Hud(HudCommand::PlayerCountry) if self.search.is_none()&&self.hud.menu==HudMenu::None
                    && p[0]<=104. && p[1]<=76.=>{
                    if let Some(i)=self.player_polity(){self.click_country(i,p);}
                }
                Action::Select(Object::Polity(i)) if self.search.is_none()&&self.hud.menu==HudMenu::None&&self.hud.page==HudPage::Map=>{
                    self.click_country(i,p);
                }
                _=>self.action(action),
            }
            return;
        }
        if self.is_panel(p){return;}
        let hit=self.camera.vector(p,self.size).map(camera::geographic).map(|q|self.object_at(q)[0]);
        if self.in_lobby(){
            if self.lobby_page!=lobby::Page::Selection {return;}
            if let Some(index)=hit.and_then(|v|v.checked_sub(1)).map(usize::from)
                .filter(|&i|self.available(Object::Polity(i))){
                self.lobby_country=index;
                self.country_directory.search_active=false;
                if !self.country_directory.query.is_empty() {
                    self.country_directory.query.clear();
                    self.filter_countries();
                }
                self.country_directory.reveal(self.size,index);
                if let Some(window)=&self.window {window.set_ime_allowed(false);}
                self.dirty=true;
            }
            return;
        }
        let polity=hit.and_then(|v|v.checked_sub(1)).map(usize::from);
        if self.hud.page==HudPage::Map {
            if let Some(i)=polity.filter(|_|self.hud.menu==HudMenu::None){self.click_country(i,p);return;}
        }
        self.country_click=None;
        self.select(polity.map(Object::Polity));
    }
    fn is_panel(&self,p:[f64;2])->bool {
        if self.loading(){return true;}
        let [x,y]=p;
        let contains=|[a,b,w,h]:[f32;4]| x>=f64::from(a)&&x<=f64::from(a+w)&&y>=f64::from(b)&&y<=f64::from(b+h);
        let [w,h]=self.size.map(|v|v as f32);
        if self.in_lobby(){
            return self.lobby_request||match self.lobby_page {
                lobby::Page::Selection=>lobby::SelectionLayout::new(self.size).contains(p),
                _=>true,
            };
        }
        let radius=(w*0.056).clamp(52.,78.);
        let modal=self.hud.menu.modal();
        modal||self.search.is_some()||self.details||
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
        if self.hud.clock_drag.is_some() && matches!(&key,Key::Named(NamedKey::Escape|NamedKey::Space)) {
            self.hud.clock_drag=None;
            if key==Key::Named(NamedKey::Space){let speed=self.state.session.as_ref().map_or(0,|s|if s.paused{s.speed}else{0});self.hud_action(HudCommand::Clock(speed));}
            self.dirty=true;return;
        }
        if self.loading(){return;}
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
                        self.filter_countries();
                    }
                    Key::Named(NamedKey::Space)=>self.type_country_search(" "),
                    Key::Character(text)=>self.type_country_search(&text),
                    _=>(),
                }
                return;
            }
            if matches!(key,Key::Named(NamedKey::Escape|NamedKey::Backspace))&&!self.lobby_request{
                self.lobby_action(lobby::Command::Page(lobby::Page::Home));
            } else if key==Key::Named(NamedKey::Enter)&&!self.lobby_request {
                if let Some(state)=&self.state.lobby{
                    if !state.busy {
                        match self.lobby_page {
                            lobby::Page::Home if state.ready=>self.lobby_action(lobby::Command::Page(lobby::Page::Selection)),
                            lobby::Page::Selection=>self.lobby_action(lobby::Command::Enter),
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
            Key::Named(NamedKey::Escape)=>if self.hud.clock_drag.take().is_some(){}else if self.hud.menu!=HudMenu::None{self.hud_action(HudCommand::Menu(HudMenu::None));}else if self.country.is_some(){self.country_action(CountryAction::Close);}else if self.hud.messages{self.hud.messages=false;}else if self.hud.page!=HudPage::Map{self.hud_action(HudCommand::Page(HudPage::Map));}else if self.details{self.details=false;}else{self.hud.menu=HudMenu::System;},
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
        self.filter_countries();
    }
    fn rotate(&mut self,from:[f64;2],to:[f64;2],bearing:bool) {
        self.focus=None;
        if bearing{self.camera.bearing_drag(from,to,self.size);}else{self.camera.drag(from,to,self.size);}
        self.camera.update_level();self.dirty=true;
    }
    fn zoom(&mut self,p:[f64;2],steps:f64) {
        self.focus=None;self.velocity=[0.;2];self.camera.zoom(p,1.22f64.powf(-steps.clamp(-60.,60.)),self.size);self.dirty=true;
    }
    fn refresh_tiles(&mut self,now:Instant) {
        self.candidate=self.index.visible(&self.world,&self.camera,self.size,true);
        self.visible=self.index.visible(&self.world,&self.camera,self.size,false);
        for id in &self.candidate {if let Some(p)=self.cached.get_mut(id){p.used=now;}}
        self.cached.retain(|_,p|now.duration_since(p.used)<=CACHE_TTL);
        if self.reader.inflight.is_some(){return;}
        let Some(i)=self.visible.iter().chain(self.candidate.iter()).copied().find(|i|!self.cached.contains_key(i)&&!self.failed.contains(i))else{return;};
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
        let formal=formal_ui::Display{skin:&self.skin,hud:&self.hud,session:self.state.session.as_ref(),date:self.state.date,country,
            camera:&self.camera,size:self.size,mode:self.mode,flags,cursor:self.cursor,source:&source,feedback:&self.feedback,labels:self.labels,managed:self.config.managed,
            modern_terrain:view.map_style[1]>0.,
            surveyed_terrain:view.close_sample[0]>0. && view.close_sample[2]>0.5,
            debug:self.debug.then_some(&self.perf)};
        let seconds=self.started.elapsed().as_secs_f32();
        let loading=self.loading();
        let (mut meshes,hits)=if loading {
            let status=self.state.lobby.as_ref().map(|s|s.status.as_str()).filter(|s|!s.is_empty())
                .unwrap_or(if self.lobby_request{"正在进入世界"}else{"正在读取地图资料"});
            (formal.loading(status,seconds),Vec::new())
        }else if self.in_lobby(){
            formal.lobby(&self.world,self.state.lobby.as_ref(),self.lobby_page,self.lobby_country,self.lobby_request,&self.country_directory)
        }else{ui::compose(&self.world,&self.atlas,Ui{
            mode:self.mode,date:&date,camera:&self.camera,size:self.size,selected:self.selected,admin:&admin,details:self.details,country:self.country,
            search:self.search.as_deref(),search_results:&search,econ_label:&econ_label,econ_legend:&econ_legend,
            mouse:&mouse,labels:self.labels,formal,
        },&mut self.shown_markers)};
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
        let paris_ready=self.visible.iter().filter(|&&id|self.world.tiles[id].city).all(|id|self.cached.contains_key(id));
        let needs_overlay=matches!(self.mode,Mode::Political|Mode::Economic)
            ||self.mode==Mode::Military&&view.map_style[3]>0.;
        let pages:Vec<_>=self.visible.iter().filter_map(|&id| {
            let tile=&self.world.tiles[id];
            if view.map_style[1]>0.&&!needs_overlay&&!tile.city&&view.selection[1]<0.5{return None;}
            if tile.city&&!paris_ready{return None;}
            let p=self.cached.get(&id)?;
            let opacity=(now.duration_since(p.ready).as_secs_f32()/0.16).clamp(0.,1.)*tile.weight(self.camera.mpp);
            let scissor=self.index.scissor(id,&self.camera,self.size)?;
            (opacity>0.).then_some((&p.page,tile,scissor,opacity))
        }).collect();
        let models=if loading||self.in_lobby() {Vec::new()} else {
            self.landmarks.as_ref().map_or_else(Vec::new,|catalogue|catalogue.visible(&date,&self.camera,self.size))
        };
        let renderer=self.renderer.as_mut().unwrap();
        self.hits=models.iter().filter(|model|renderer.has_model(model.key)).map(|model|Hit {
            area:model.screen_bounds,action:Action::Select(Object::Place(model.place)),
        }).chain(hits).collect();
        renderer.update_terrain(&self.camera,self.size,now)?;
        view.map_style[2]=renderer.terrain_view_level() as f32;
        view.natural_lod=renderer.terrain_viewport_mix();
        view.set_terrain_exact(renderer.terrain_exact());
        let landscape_enabled=!loading&&(!self.config.managed||self.state.session.is_some())&&self.mode==Mode::Geographic;
        if landscape_enabled && view.map_style[2]>=6. {view.set_city_grounds(&models);}
        renderer.prepare_landscape(&self.camera,self.size,landscape_enabled);
        if self.last_palette!=Some(self.state.date) {
            renderer.set_politics(&self.state.palette(&self.world,&date,&self.visuals,&self.employment),&self.visuals.uniforms(&date));self.last_palette=Some(self.state.date);
        }
        let player_capture=self.screenshot.is_some();
        let capture=self.screenshot.as_ref().or_else(||self.trial.captures.first())
            .or_else(||self.trial.terrain_capture.as_ref().map(|(_,path)|path)).map(PathBuf::as_path);
        let mut redraw=false;
        if let Some(result)=renderer.render(&view,self.base.as_ref().unwrap(),&pages,&meshes,fade.as_ref(),seconds,!loading,capture,&models)? {
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
                    let extra=serde_json::json!({"png":png,"terrain_samples":samples});
                    self.write_observation(&id,extra)?;
                } else {self.trial.captures.remove(0);}
            }
            else if self.trial.timing {
                if let Some(prev)=self.trial.previous {self.trial.times.push(presented.duration_since(prev).as_secs_f64()*1000.);}
                self.trial.previous=Some(presented);
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
    fn status(&self)->serde_json::Value {
        let session=self.state.session.as_ref().map(|s|{
            let market=s.market.as_ref().map(market_ui::Market::status);
            serde_json::json!({"player":s.player,"time":[s.hour,s.minute],"total_minutes":s.total_minutes,"paused":s.paused,"speed":s.speed,
                "finance":s.finance.summary,"message_count":s.messages.len(),"slots":s.slots.len(),"market":market,"training":s.training,
                "character":s.character,
                "property":s.property.iter().map(|r|(&r.id,r.quantity)).collect::<Vec<_>>(),"departure":s.departure })
        });
        let lobby=self.state.lobby.as_ref().map(|s|serde_json::json!({"page":format!("{:?}",self.lobby_page),"ready":s.ready,
            "selection_ready":s.selection_ready,"busy":s.busy,"status":s.status,
            "slots":s.slots.iter().map(|s|(s.slot,s.can_read)).collect::<Vec<_>>()}));
        serde_json::json!({
            "level":match self.camera.level{Level::World=>"WORLD",Level::Region=>"REGION",Level::Local=>"LOCAL"},
            "mode":self.mode.key(),"center":self.camera.coordinates(),"mpp":self.camera.mpp,"orientation":self.camera.axes,
            "viewport":self.size,"projection":if self.camera.blend()>0. {"azimuthal_equidistant"} else {"orthographic"},
            "pitch_degrees":self.camera.pitch().to_degrees(),
            "landmarks":self.renderer.as_ref().map(Renderer::resident_models),
            "model_instances":self.renderer.as_ref().map(Renderer::model_instances),
            "selection":self.selected.map_or(String::new(),|o|self.id(o)),"date":self.state.date.to_string(),
            "cache_bytes":self.cached.values().map(|p|p.page.bytes).sum::<usize>(),
            "base_bytes":self.base.as_ref().map_or(0,|p|p.bytes),"resident":self.cached.len(),
            "wanted":self.visible.len(),"ready":self.visible.iter().filter(|i|self.cached.contains_key(i)).count(),
            "inflight":self.reader.inflight.is_some(),"first_frame_ms":self.trial.first,
            "gpu":self.renderer.as_ref().map(|r|&r.gpu),"feedback":self.feedback,
            "terrain":self.renderer.as_ref().and_then(Renderer::terrain_status),
            "terrain_detail":self.renderer.as_ref().and_then(Renderer::close_terrain_status),
            "workspace":format!("{:?}",self.hud.page),"menu":format!("{:?}",self.hud.menu),"messages":self.hud.messages,
            "session":session,"lobby":lobby,
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
            "click"=>self.click([input.x,input.y]),
            "wheel"=>{
                let point=[input.x,input.y];
                if !self.scroll_countries(point,input.steps){self.zoom(point,input.steps);}
            }
            "drag"=>{
                self.velocity=[0.;2];
                self.trial.movement=Some(([input.x,input.y],[input.to_x,input.to_y],input.frames.clamp(1,180),0));
            }
            "key"=>self.key(match input.value.as_str() {"Escape"=>Key::Named(NamedKey::Escape),"Space"|"space"=>Key::Named(NamedKey::Space),"Enter"=>Key::Named(NamedKey::Enter),"Home"=>Key::Named(NamedKey::Home),"F1"=>Key::Named(NamedKey::F1),"F2"=>Key::Named(NamedKey::F2),"F3"=>Key::Named(NamedKey::F3),"F4"=>Key::Named(NamedKey::F4),"F5"=>Key::Named(NamedKey::F5),"F6"=>Key::Named(NamedKey::F6),"F7"=>Key::Named(NamedKey::F7),"F8"=>Key::Named(NamedKey::F8),_=>Key::Character(input.value.into())}),
            "home"=>self.action(Action::Home),
            "north"=>{self.camera.north_up();self.dirty=true;}
            "capture" if !input.label.is_empty() && input.label.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-')=>{
                let screenshot=path.with_file_name(format!("{}.png",input.label));
                if self.config.terrain_review {
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
                        Ok((draw_calls,counts))=>serde_json::json!({
                            "draw_calls":draw_calls,
                            "instances":counts.iter().sum::<u32>(),
                            "by_mesh":counts,
                        }),
                        Err(error)=>serde_json::json!({"error":error.to_string()}),
                    };
                }
            }
            "timing"=>{
                self.trial.timing=!self.trial.timing;self.trial.previous=None;
                if self.trial.timing{
                    self.trial.times.clear();
                    self.trial.loads.clear();
                    self.trial.terrain_decodes.clear();
                } else {
                    extra=serde_json::json!({"interval_ms":self.trial.times,"tile_load_ms":self.trial.loads,
                        "terrain_decode_ms":self.trial.terrain_decodes});
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
            if connected {self.loading_fade=Some(now);self.loading_status="正在安装地图".into();}
            self.hud=Hud{fullscreen:self.hud.fullscreen,volume:self.hud.volume,english:self.hud.english,..Hud::default()};
            self.selected=None;self.details=false;self.country=None;self.country_click=None;
            self.search=None;self.history.clear();self.focus=None;self.velocity=[0.;2];self.hits.clear();
            self.mode=Mode::Political;self.labels=false;
            self.camera=Camera::new(self.size);
            self.camera.local_models=self.landmarks.is_some();
            if let Some(point)=self.state.session.as_ref().and_then(|s| <[f64;2]>::try_from(s.coordinates.as_slice()).ok()) {
                #[cfg(windows)]
                if self.config.native.is_some() {self.camera.focus(point, 1400.);}
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
            self.camera=focus.camera.clone();
            self.camera.level=level;
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
            let result=native.tick(now).and_then(|changed| {
                if changed {native.update_after_tick(&mut self.state)?;}
                Ok(changed)
            });
            match result {
                Ok(changed)=>self.dirty|=changed,
                Err(error)=>{self.feedback=format!("游戏时钟推进失败：{error}");self.dirty=true;}
            }
        }
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
                let mut attributes=Window::default_attributes().with_title("WWO | 1900 - Rust strategic host")
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
            let hud=[font(&self.config.root.join("hud-art.png"))?,font(&self.config.root.join("hud-type.png"))?,
                if self.config.managed{font(&self.config.root.join("menu-painting.png"))?}else{Raster{size:[1,1],pixels:vec![0;4]}}];
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
            let globe_art=[art("galactic-chart.png")?,art("ocean-detail-r68.png")?,art("ocean-ice-r68.png")?];
            let atlas=font(&self.config.root.join("type.png"))?;
            let detail=if self.natural.is_some() && self.config.terrain_close_sample.is_none()
                && matches!(self.config.terrain_selection,terrain::LayerSelection::Auto) {
                let default_dir=self.config.terrain_candidate.clone().unwrap_or_else(||self.config.root.join(terrain::VERSION));
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
            let renderer=if let Some(window)=&window {
                pollster::block_on(Renderer::new(window.clone(),atlas,flags,hud,globe_art,&layouts,self.natural.take(),detail,self.events.clone()))?
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
            HostEvent::Model(key,mesh)=>{
                if let Some(renderer)=&mut self.renderer {
                    if let Err(error)=renderer.model_ready(key,mesh) {
                        self.feedback=format!("R68 GLB · {error}");
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
        };
        self.reader.inflight=None;
        match event.result {
            Ok(pixels)=>{
                if self.candidate.contains(&event.id) {
                    let tile=&self.world.tiles[event.id];
                    let page=self.renderer.as_ref().unwrap().upload(tile,pixels);
                    let now=Instant::now();
                    self.cached.insert(event.id,Resident{page,ready:now,used:now});
                    if self.trial.timing {self.trial.loads.push((tile.path.clone(),ms(event.requested)));}
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
                if self.config.managed&&self.state.session.is_some(){self.hud_action(HudCommand::Departure("system:quit"));self.dirty=true;}
                else{event_loop.exit();}
            }
            WindowEvent::Resized(s) if s.width>0&&s.height>0=>{
                if self.in_lobby() && self.lobby_page == lobby::Page::Selection && self.camera.level == Level::World {
                    let previous = lobby::SelectionLayout::globe_mpp(self.size);
                    let resized = lobby::SelectionLayout::globe_mpp(s.into());
                    self.camera.mpp *= resized / previous;
                }
                self.size=s.into();self.camera.constrain_region(self.size);
                if let Some(r)=self.renderer.as_mut(){r.resize(self.size);}self.dirty=true;
            }
            WindowEvent::RedrawRequested if self.renderer.is_some()=>{
                if let Err(e)=self.draw(){self.fatal_error=Some(e.to_string());event_loop.exit();}
            }
            WindowEvent::CursorMoved{position,..}=>{
                let next:[f64;2]=position.into();self.cursor=next;
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
                if state==ElementState::Pressed {
                    self.focus=None;self.velocity=[0.;2];
                    if button==MouseButton::Left&&self.in_lobby()&&self.lobby_page==lobby::Page::Selection
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
                if self.scroll_countries(self.cursor,steps) {return;}
                let [w,h]=self.size.map(|n|n as f32);
                let [x,y,width,height]=formal_ui::message_rect([w,h],((h+16.)*0.5).max(190.));
                if self.hud.messages && (f64::from(x)..=f64::from(x+width)).contains(&self.cursor[0]) && (f64::from(y)..=f64::from(y+height)).contains(&self.cursor[1]){
                    self.action(Action::Hud(HudCommand::MessageScroll(-(steps.signum() as i32))));
                }else if matches!(self.hud.page,HudPage::Market|HudPage::Property|HudPage::Relations) &&
                    formal_ui::page_rect(&self.hud,self.size).is_some_and(|[x,y,w,h]| (f64::from(x)..=f64::from(x+w)).contains(&self.cursor[0])&&(f64::from(y)..=f64::from(y+h)).contains(&self.cursor[1])) {
                    self.action(Action::Hud(HudCommand::MarketScroll(-(steps.signum() as i32)*3)));
                }else if !self.is_panel(self.cursor) {self.zoom(self.cursor,steps);}
            }
            WindowEvent::Ime(winit::event::Ime::Commit(text)) if self.country_directory.search_active=>self.type_country_search(&text),
            WindowEvent::KeyboardInput{event,..} if event.state==ElementState::Pressed && !event.repeat=>self.key(event.logical_key),
            WindowEvent::Focused(false)=>{self.drag=None;self.country_click=None;self.hud.volume_drag=false;self.dirty|=self.hud.clock_drag.take().is_some();
                self.dirty|=self.country_directory.drag.take().is_some();self.velocity=[0.;2];}
            _=>(),
        }
    }
    fn about_to_wait(&mut self,event_loop:&ActiveEventLoop) {
        let now=Instant::now();self.poll(event_loop,now);
        if self.hud.menu!=HudMenu::None {self.hud.clock_drag=None;}
        if let Some(s)=self.state.session.as_ref(){self.hud.mechanical.update(now,formal_ui::clock_index(Some(s)),s.clock_ack,self.hud.clock_drag,if s.paused{0}else{s.speed});}
        if self.screenshot_status.as_ref().is_some_and(|(at,_)|at.elapsed()>Duration::from_secs(7)){
            self.screenshot_status=None;self.dirty=true;
            if let Some(window)=&self.window{window.set_title("WWO | 1900 - Rust strategic host");}
        }
        let fading=self.renderer.as_ref().is_some_and(Renderer::terrain_fading)||self.cached.values().any(|p|now.saturating_duration_since(p.ready)<Duration::from_millis(180));
        let expiry=self.cached.values().any(|p|now.saturating_duration_since(p.used)>CACHE_TTL);
        let animated=self.loading()||self.state.session.is_some()
            ||self.in_lobby()&&self.lobby_page==lobby::Page::Selection
            || self.selected.is_some_and(|o|matches!(o,Object::Polity(_)));
        let transitioning=self.loading_fade.is_some_and(|t|t.elapsed()<Duration::from_millis(320));
        if let Some(window)=&self.window {
            let periodic=(animated||transitioning||fading)&&now.saturating_duration_since(self.last_present)>=Duration::from_millis(if fading||transitioning{16}else{32});
            if self.dirty||expiry||periodic||self.trial.timing||!self.trial.captures.is_empty()||self.screenshot.is_some(){window.request_redraw();}
        } else if self.config.terrain_review && self.renderer.is_some() {
            let pending=self.dirty||fading||self.trial.timing;
            let due=now.saturating_duration_since(self.last_present)>=Duration::from_millis(33);
            if (pending&&due)||self.trial.terrain_capture.is_some() {
                if let Err(error)=self.draw(){self.fatal_error=Some(error.to_string());event_loop.exit();}
            }
        }
        let fast=self.focus.is_some()||self.animate||self.trial.timing||self.trial.movement.is_some()||self.velocity[0].hypot(self.velocity[1])>9.||fading;
        let frame=now+Duration::from_millis(if fast||transitioning{16}else if animated{33}else{135});
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
