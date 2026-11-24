mod config;
mod events;
mod map;
mod menus;
mod observe;

use self::{config::Config, observe::{BattleOpeningTiming, Observation, Trial}};
use crate::{
    battle_view, camera::{self, Camera}, compact::{self, Raster},
    formal_ui::{self, Command as HudCommand, Hud, Menu as HudMenu, Page as HudPage, Skin},
    hydrology, interface, landmarks, lobby, map_release, market_ui, menu_theme, overlay,
    politics::PoliticalVisuals, pop_debug_ui, prologue_ui,
    render::{self, Edit, Page, Renderer, View}, state::{self, Request, State}, terrain,
    timeline::{self, Date}, transport_scene, transport_ui,
    ui::{self, Action, CountryPanel, Hit, Mode, Object, Ui}, world::{Completion, Index, Reader, World},
};
#[cfg(windows)]
use crate::native_start;
use std::{
    collections::{HashMap, HashSet},
    fs::{self, File}, io::{self, Read}, path::{Path, PathBuf},
    sync::Arc, time::{Duration, Instant, SystemTime},
};
use winit::{event_loop::EventLoop, window::Window};
use wwo_map_lab::{battlefield_terrain::BattlefieldTerrain, military_grid::MilitaryCell};

pub(crate) enum HostEvent {
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

pub(super) struct Diagnostics {
    pub(super) rate: f64,
    pub(super) cpu_ms: f64,
    pub(super) tiles: usize,
    pub(super) visible: usize,
    pub(super) mib: f64,
    pub(super) streaming: bool,
}

struct Resident {page:Page,ready:Instant,used:Instant}
struct Drag {at:[f64;2],origin:[f64;2],last:Instant,bearing:bool,moved:bool}
struct Pose {camera:Camera,object:Option<Object>}
#[derive(Clone, Copy)]
struct SelectedMilitaryCell { cell: MilitaryCell, coordinates: [f64; 2] }
pub(crate) struct PreparedBattleTerrain {
    terrain: BattlefieldTerrain,
    pages: Vec<[u32; 3]>,
    worker_ms: f64,
}
struct Focus {start:Instant, camera:Camera, target:[f64;2], mpp:f64}
struct CountryClick {polity:usize,point:[f64;2],deadline:Instant}
struct Host {
    natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<HostEvent>)>,
    events:winit::event_loop::EventLoopProxy<HostEvent>,
    landmarks:Option<landmarks::Landmarks>,
    transport_scene:Option<transport_scene::TransportScene>,
    transport_selection:Option<transport_ui::ObjectId>,
    transport_detail:Option<(i64, transport_ui::Detail)>,
    resources: crate::resource_map::State,
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
    menu_themes:menu_theme::Themes,
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
pub(super) fn font(path:&Path)->io::Result<Raster> {
    decode_rgba(File::open(path)?)
}
pub(super) fn decode_rgba(source:impl Read)->io::Result<Raster> {
    let mut reader=png::Decoder::new(source).read_info()?;
    let mut pixels=vec![0;reader.output_buffer_size()];
    let info=reader.next_frame(&mut pixels)?;
    if info.color_type!=png::ColorType::Rgba || info.bit_depth!=png::BitDepth::Eight {return Err(io::Error::other("invalid type atlas"));}
    pixels.truncate(info.buffer_size());
    Ok(Raster{size:[info.width,info.height],pixels})
}
fn hud_type_atlas(path: &Path) -> io::Result<Raster> {
    use crate::formal_ui::{HUD_TYPE_BASE_HEIGHT, HUD_TYPE_HEIGHT, HUD_TYPE_WIDTH};
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
        if formal_map {
            if let Err(error)=map_release::add_city_ground(&mut world,&config.root) {
                eprintln!("City ground catalogue: {error}");
            }
        }
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
        let menu_themes=menu_theme::Themes::open(&config.root,preferences.fixed_painting,preferences.last_painting);
        let visuals=PoliticalVisuals::open(&map_root,&world)?;
        let employment=state::EmploymentReference::open(&config.root)?;
        let index=Index::new(&world.tiles);
        let legacy_cover=natural.is_none()||config.scenario.is_some();
        let reader=Reader::new(map_root.clone(),map_signature,legacy_cover,events.create_proxy());
        let observation_id=config.observe.as_ref().filter(|_|!config.terrain_review).and_then(|path|timeline::read::<Observation>(path,128*1024).ok())
            .map(|input|input.id).unwrap_or_default();
        Ok(Self {natural,events:events.create_proxy(),landmarks,transport_scene:None,transport_selection:None,transport_detail:None,resources:Default::default(),config,map_root,map_signature,fatal_error:None,world,visuals,index,reader,state,camera,atlas,started,base:None,window:None,renderer:None,
            cached:HashMap::new(),failed:HashSet::new(),candidate:Vec::new(),visible:Vec::new(),
            size:VIEW_SIZE,mode,theme:false,labels,selected:None,details:false,country:None,country_click:None,search:None,history:Vec::new(),focus:None,site:0,
            hits:Vec::new(),shown_markers:HashSet::new(),cursor:[640.,360.],drag:None,velocity:[0.;2],moved_at:Instant::now(),
            animate:false,next_date:Instant::now(),feedback:String::new(),dirty:true,last_input_check:Instant::now(),
            version:None,last_palette:None,trial:Trial{last:observation_id,..Trial::default()},hud:Hud{fullscreen:preferences.fullscreen,volume:preferences.volume,english:preferences.english,..Hud::default()},skin,exit_requested:false,
            prologue: None,menu_themes,
            opening_nav: lobby::Selection::default(),
            lobby_page:lobby::Page::Home,lobby_country,lobby_request:false,country_directory:lobby::Directory::default(),
            bridge_wait:Instant::now(),seen_lobby_busy:false,departure_requested:false,
            loading_fade:None,loading_status:String::new(),debug:false,perf_at:Instant::now(),perf_frames:0,population_debug:None,
            perf:Diagnostics{rate:0.,cpu_ms:0.,tiles:0,visible:0,mib:0.,streaming:false},
            screenshot:None,screenshot_status:None,grid_step:50000.,last_present:started,employment,market_focus_serial:0,
            military_cell:None,battle_terrain:None,battle_terrain_timing:None,battle_view:None,
            battle_terrain_wanted:None,battle_terrain_loading:None,battle_enter_requested:None})
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
            .find(|i|(!self.world.tiles[*i].city_ink_only||city_first)
                &&!self.cached.contains_key(i)&&!self.failed.contains(i))else{return;};
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
            (formal.loading(status,seconds,self.menu_themes.aspect),Vec::new())
        }else if self.in_lobby(){
            formal.lobby(&self.world,self.state.lobby.as_ref(),self.lobby_page,self.lobby_country,self.lobby_request,&self.country_directory,self.prologue.as_ref(),
                lobby::SelectionView { navigation: &self.opening_nav, camera: &self.camera, visuals: &self.visuals, world: &self.world },
                &self.menu_themes)
        }else{ui::compose(&self.world,&self.atlas,Ui{
            mode:self.mode,date:&date,camera:&self.camera,size:self.size,selected:self.selected,admin:&admin,details:self.details,country:self.country,
            search:self.search.as_deref(),search_results:&search,econ_label:&econ_label,econ_legend:&econ_legend,
            resources:self.resources_available().then_some(&self.resources),year:self.state.date.year,
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
                let mut old=formal.loading(&self.loading_status,seconds,self.menu_themes.aspect);
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
            fade = Some(lobby::cloud_cover(self.size, opacity, travel));
        }
        let needs_overlay=matches!(self.mode,Mode::Political|Mode::Economic)
            ||self.mode==Mode::Military&&view.map_style[3]>0.;
        let pages:Vec<_>=self.visible.iter().filter_map(|&id| {
            let tile=&self.world.tiles[id];
            if tile.city_ink_only && (self.mode!=Mode::Geographic || view.map_style[1]<=0.) {return None;}
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
}

fn record_error(target:&Path,text:&str) {
    eprintln!("{text}");
    let _=fs::write(target,text);
}
pub(super) fn run() -> Result<(),Box<dyn std::error::Error>> {
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
