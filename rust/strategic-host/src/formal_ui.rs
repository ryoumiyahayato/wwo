use crate::{overlay::Mesh, ui::{Action,CountryAction,CountryPanel,CountryView,Hit,Mode}, camera::Camera,
    world::{Admin,Polity,World}};
use serde::Deserialize;
use wwo_map_lab::formal_bootstrap::PersonalActivity;
use std::{collections::HashMap, fs::File, io, path::Path};

#[derive(Deserialize)]
pub struct Session {
    pub player:String, pub polity:String, pub coordinates:Vec<f64>, pub place:String,
    #[serde(default)] pub clock_ack:u64,
    pub hour:u32, pub minute:u32, pub paused:bool, pub speed:u32,
    #[serde(default)] pub total_minutes:u64,
    #[serde(default)] pub rust_clock: Option<RustClock>,
    pub finance:Finance, pub technology:Technology, pub messages:Vec<Message>,
    #[serde(default = "written_access_default")] pub written_access: bool,
    #[serde(default)] pub activities: Option<Activities>,
    pub slots:Vec<Slot>, pub slot_open:bool, pub slot_error:String,
    #[serde(default)] pub market:Option<crate::market_ui::Market>,
    #[serde(default)] pub property:Vec<crate::market_ui::Holding>,
    #[serde(default)] pub property_feedback: String,
    #[serde(default)] pub relations:Option<Relations>,
    #[serde(default)] pub transport:Option<crate::transport_ui::TransportView>,
    #[serde(default)] pub character:Option<Character>,
    #[serde(default)] pub training:String,
    #[serde(default)] pub departure:String,
    #[serde(default)] pub saving:bool,
}
fn written_access_default() -> bool { true }

#[derive(Deserialize)]
pub struct Activities {
    language: wwo_character_core::Language,
    scheduled: Option<PersonalActivity>,
    pub lesson: bool,
    pub rest: bool,
    pub read_notice: bool,
    oral_notice: Option<String>,
    #[serde(default)] oral_work: Option<OralWork>,
    #[serde(default)] oral_work_feedback: Option<OralWorkFeedback>,
}

#[derive(Deserialize)]
struct OralWork {
    employer: String,
    employer_english: String,
    #[serde(default)] referred: bool,
    hours: i64,
    wage_per_hour: i64,
    wage_delay: i64,
    action: String,
    revision: u64,
    state: OralWorkState,
}

#[derive(Clone, Copy, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum OralWorkState {
    Offer { vacancies: usize, confirming: bool },
    Contract { booked: bool, present: bool, can_book: bool },
}

#[derive(Clone, Copy, Deserialize, serde::Serialize)]
pub(crate) enum OralWorkFeedback {
    Signed,
    Unavailable,
}

impl Activities {
    pub fn oral_work_action(&self, revision: u64) -> Option<&str> {
        let work = self.oral_work.as_ref()?;
        let enabled = match work.state {
            OralWorkState::Offer { vacancies, confirming } => vacancies > 0 && !confirming,
            OralWorkState::Contract { booked, present, can_book } => !booked && present && can_book,
        };
        (work.revision == revision && enabled).then_some(work.action.as_str())
    }

    pub(crate) fn refresh_oral_work_booking(&mut self, eligible: impl FnOnce() -> bool) {
        if let Some(OralWork { state: OralWorkState::Contract { can_book, .. }, .. }) = self.oral_work.as_mut() {
            *can_book = eligible();
        }
    }
}

#[derive(Deserialize)]
pub struct RustClock {
    pub world: String,
    pub tick_ack: u64,
}
#[derive(Deserialize)]
pub struct Finance {pub summary:String,pub page:usize,pub more:bool,pub rows:Vec<Receipt>}
#[derive(Deserialize)]
pub struct Receipt {description:String,amount:String}
#[derive(Deserialize)]
pub struct Technology {
    country:String,foundation:Vec<Foundation>,public_country:String,public_foundation:Vec<Foundation>,
    project_active:bool,milestones:Vec<Milestone>,
}
#[derive(Deserialize)]
struct Foundation {title:String,description:String,kind:String}
#[derive(Deserialize)]
struct Milestone {title:String,kind:String,effect:String,date:String}
#[derive(Deserialize)]
pub struct Message {source:String,received_at:String,text:String,pub action:String}
#[derive(Clone, Deserialize, serde::Serialize)]
pub struct Slot {
    pub slot: u8,
    pub name: String,
    pub empty: bool,
    #[serde(default = "written_access_default")]
    pub can_read: bool,
    pub description: String,
}
#[derive(Deserialize)]
pub struct Relations {
    pub selected:String,pub rows:Vec<Relation>,
    #[serde(default)] pub drawer:String,
    #[serde(default)] has_work:bool,
    #[serde(default)] has_local:bool,
    #[serde(default)] work_title:String,
    #[serde(default)] work_feedback:String,
    #[serde(default)] pub work_revision:u64,
    #[serde(default)] pub work:Vec<WorkSummary>,
    #[serde(default)] pub confirmation:Option<WorkConfirmation>,
}
#[derive(Deserialize)]
pub struct Relation {pub id:String,label:String,role:String,kind:String,place:String,basis:String}
#[derive(Deserialize)]
pub struct WorkSummary {label:String,details:Vec<String>,#[serde(default)] pub actions:Vec<WorkAction>}
#[derive(Deserialize)]
pub struct WorkAction {label:String,pub id:String, pub enabled:bool}
#[derive(Deserialize)]
pub struct WorkConfirmation {title:String,body:String}
#[derive(Deserialize, serde::Serialize)]
pub struct Character {
    #[serde(flatten)] profile: wwo_character_core::PersonView,
    settled_day: u32,
    #[serde(default)] assessment: Option<Assessment>,
    #[serde(default)] pub oral_contacts: Vec<String>,
    #[serde(default)] pub oral_referral: Option<OralReferral>,
}
#[derive(Deserialize, serde::Serialize)]
pub struct OralReferral { pub id: String, label: String }
#[derive(Deserialize, serde::Serialize)]
struct Assessment { explanation: Vec<String> }

impl Session {
    pub fn valid(&self)->bool {
        self.player.starts_with("person:") && self.hour<24 && self.minute<60 && [1,2,4].contains(&self.speed)
            && (self.coordinates.is_empty() || (self.coordinates.len()==2 && self.coordinates[0].abs()<=180. && self.coordinates[1].abs()<=90.))
    }
}
pub(crate) const HUD_TYPE_WIDTH: u32 = 2048;
pub(crate) const HUD_TYPE_BASE_HEIGHT: u32 = 2048;
pub(crate) const HUD_TYPE_HEIGHT: u32 = HUD_TYPE_BASE_HEIGHT + 112;

pub struct Skin {
    art:HashMap<String,[f32;4]>,
    glyphs:HashMap<String,[f32;5]>,
    pub map_symbols:HashMap<String,MapSymbol>,
    english:bool,
    messages:HashMap<String,String>,
    fragments:Vec<(String,String)>,
    geography:GeographyNames,
}
#[derive(Default,Deserialize)]
struct GeographyNames {
    names:HashMap<String,LocalizedName>,
    directories:HashMap<String,Vec<String>>,
}
#[derive(Deserialize)]
struct LocalizedName {zh:String,en:String}
pub struct AdminRecord<'a> {pub name:&'a str,pub original:&'a str,pub boundary:Option<usize>}
#[derive(Deserialize)]
pub struct MapSymbol {
    pub screen_px:f32,
    pub priority:u32,
    pub region_max_mpp:f64,
    pub world:bool,
    pub world_max_mpp:f64,
}
impl Skin {
    pub fn open(root:&Path)->io::Result<Self>{
        let messages:HashMap<String,String>=match File::open(root.join("messages-en-r68.json")){
            Ok(file)=>serde_json::from_reader(file)?,
            Err(error) if error.kind()==io::ErrorKind::NotFound=>HashMap::new(),
            Err(error)=>return Err(error),
        };
        let mut fragments:Vec<_>=messages.iter().filter(|(key,_)|key.trim().chars().count()>=2&&!key.contains('%'))
            .map(|(key,value)|(key.clone(),value.clone())).collect();
        fragments.sort_by(|a,b|b.0.len().cmp(&a.0.len()).then(a.0.cmp(&b.0)));
        let mut glyphs: HashMap<String, [f32; 5]> = serde_json::from_reader(File::open(root.join("hud-type.json"))?)?;
        let supplemental: HashMap<String, [f32; 5]> = serde_json::from_str(
            include_str!("../../../data/character/hud-glyphs.json"))?;
        for (key, glyph) in supplemental { glyphs.entry(key).or_insert(glyph); }
        Ok(Self{art:serde_json::from_reader(File::open(root.join("hud-art.json"))?)?,
            glyphs,
            map_symbols:match File::open(root.join("map-symbols.json")){
                Ok(file)=>serde_json::from_reader(file)?,
                Err(error) if error.kind()==io::ErrorKind::NotFound=>HashMap::new(),
                Err(error)=>return Err(error),
            },geography:match File::open(root.join("hud-geography.json")){
                Ok(file)=>serde_json::from_reader(file)?,
                Err(error) if error.kind()==io::ErrorKind::NotFound=>GeographyNames::default(),
                Err(error)=>return Err(error),
            },english:false,messages,fragments})
    }
    pub fn set_english(&mut self,value:bool){self.english=value;}
    pub fn english(&self)->bool {self.english}
    pub fn choose<'a>(&self,zh:&'a str,en:&'a str)->&'a str {if self.english {en}else{zh}}
    pub(crate) fn geographic_name<'a>(&'a self,id:&str)->Option<&'a str>{
        let record=self.geography.names.get(id)?;
        Some(self.choose(&record.zh,&record.en)).filter(|name|!name.is_empty())
    }
    pub fn country_name<'a>(&'a self,p:&'a Polity)->&'a str{
        self.geographic_name(&p.map_id()).unwrap_or_else(||{
            if self.english||p.name_zh.is_empty(){&p.name}else{&p.name_zh}
        })
    }
    pub fn division_name<'a>(&'a self,admin:&'a Admin)->&'a str {
        self.geographic_name(&admin.id).unwrap_or(&admin.name)
    }
    pub fn admin_count(&self,world:&World,p:&Polity)->usize{
        if p.id=="country_fra" {world.admin.len()}
        else {self.geography.directories.get(&p.id).map_or(0,Vec::len)}
    }
    pub fn admin_record<'a>(&'a self,world:&'a World,p:&Polity,index:usize)->Option<AdminRecord<'a>>{
        if p.id=="country_fra" {
            let record=world.admin.get(index)?;
            return Some(AdminRecord{name:self.division_name(record),original:&record.name,boundary:Some(index)});
        }
        let id=self.geography.directories.get(&p.id)?.get(index)?;
        let original=&self.geography.names.get(id)?.en;
        Some(AdminRecord{name:self.geographic_name(id)?,original,boundary:None})
    }
    fn localized<'a>(&'a self,value:&'a str)->std::borrow::Cow<'a,str> {
        use std::borrow::Cow;
        if !self.english {return Cow::Borrowed(value);}
        if let Some(translated)=self.messages.get(value) {return Cow::Borrowed(translated);}
        if !value.chars().any(|c|('\u{3400}'..='\u{9fff}').contains(&c)){return Cow::Borrowed(value);}
        let mut result=value.to_owned();
        for (from,to) in &self.fragments {
            if result.contains(from){result=result.replace(from,to);}
        }
        Cow::Owned(result.replace('：',": ").replace('，',", ").replace('、',", ")
            .replace('。',".").replace('（'," (").replace('）',")").replace('／'," / "))
    }
    pub fn sprite(&self,mesh:&mut Mesh,name:&str,area:[f32;4]){
        self.tinted_sprite(mesh,name,area,[255;4]);
    }
    pub(crate) fn tinted_sprite(&self,mesh:&mut Mesh,name:&str,area:[f32;4],tint:[u8;4]){
        let [u,v,w,h]=self.art[name];
        mesh.image(area,[(u+0.5)/1024.,(v+0.5)/1024.,(u+w-0.5)/1024.,(v+h-0.5)/1024.],tint);
    }
    fn glyph(&self,font:usize,ch:char)->[f32;5]{
        let key=format!("{font}:{ch}");
        self.glyphs.get(&key).copied().unwrap_or_else(||self.glyphs[&format!("{}:?",font.min(2))])
    }
    pub(crate) fn width(&self,s:&str,font:usize)->f32 {self.localized(s).chars().map(|c|self.glyph(font,c)[4]).sum()}
    pub(crate) fn text(&self,mesh:&mut Mesh,s:&str,font:usize,[mut x,y]:[f32;2],limit:f32,color:[u8;4]){
        let end=x+limit;
        for ch in self.localized(s).chars() {
            let [u,v,w,h,advance]=self.glyph(font,ch);
            if x+advance>end {break;}
            mesh.image([x-2.,y,w,h],[u / HUD_TYPE_WIDTH as f32, v / HUD_TYPE_HEIGHT as f32,
                (u+w) / HUD_TYPE_WIDTH as f32, (v+h) / HUD_TYPE_HEIGHT as f32],color);
            x+=advance;
        }
    }

    pub(crate) fn paragraph(&self,mesh:&mut Mesh,s:&str,font:usize,[left,top,width,height]:[f32;4],color:[u8;4],scale:f32) {
        let localized = self.localized(s);
        let glyphs: Vec<_> = localized.chars().map(|ch| (ch, self.glyph(font,ch))).collect();
        let Some((_,[_,_,_,line_height,_])) = glyphs.first().copied() else { return; };
        let mut rest = glyphs.as_slice();
        let mut y = top;
        while !rest.is_empty() && y + line_height * scale <= top + height {
            let mut used = 0.;
            let mut count = 0;
            let mut word_end = 0;
            for (ch,[_,_,_,_,advance]) in rest {
                if ch.is_whitespace() { word_end = count; }
                if (used + advance) * scale > width { break; }
                used += advance;
                count += 1;
                if !ch.is_ascii() { word_end = count; }
            }
            if count == 0 { break; }
            if count < rest.len() && word_end > 0 { count = word_end; }
            let mut x = left;
            for (_,[u,v,w,h,advance]) in &rest[..count] {
                mesh.image([x-2.*scale,y,w*scale,h*scale],[u / HUD_TYPE_WIDTH as f32, v / HUD_TYPE_HEIGHT as f32,
                    (u+w) / HUD_TYPE_WIDTH as f32, (v+h) / HUD_TYPE_HEIGHT as f32],color);
                x += advance * scale;
            }
            rest = &rest[count..];
            while rest.first().is_some_and(|(ch,_)| ch.is_whitespace()) {
                rest = &rest[1..];
            }
            y += (line_height - 2.) * scale;
        }
    }
}
#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum Page {#[default] Map,Finance,Technology,Market,Property,Relations,Character,Travel}
#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum Menu {#[default] None,MapModes,System,Settings,Save,Load,Overwrite(u8),Departure}
impl Menu {
    pub fn modal(self)->bool {matches!(self,Self::Settings|Self::Save|Self::Load|Self::Overwrite(_)|Self::Departure)}
}
#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum Tech {#[default] Capacity,Chronicle,Public}
#[derive(Default)]
pub struct Hud {
    pub page:Page,pub menu:Menu,pub messages:bool,pub message_offset:usize,pub tech:Tech,pub milestone:usize,
    pub clock_origin:Option<[f64;2]>,
    pub mechanical:crate::mechanical::Mechanical,
    pub waiting_slot:bool,pub fullscreen:bool,pub clock_drag:Option<f32>,pub military_grid:bool,
    pub market_offset:usize,pub market_chooser:Option<&'static str>,pub quantity:Option<String>,pub purchase_token:Option<u64>,
    pub transport_detail_page:usize,
    pub volume:u8,pub english:bool,pub volume_drag:bool,
}
#[derive(Clone,Copy)]
pub enum Command {
    Page(Page),Menu(Menu),Messages,MessageScroll(i32),Technology(Tech),Milestone(usize),
    FinancePage(usize),Clock(u32),Player,LocatePlayer,PlayerCountry,Slot(u8),ConfirmSlot(u8),MessageLink(usize),
    Labels,Fullscreen,MilitaryGrid,Quit,PlayerMarker,Volume(u8),Language(bool),
    Market(&'static str,usize),MarketScroll(i32),
    Transport(&'static str,usize),
    TransportDetail(usize),TransportDetailPage(usize),CloseTransportDetail,
    Training(&'static str),
    PortraitAction(usize,Page),Relation(Option<usize>),RelationDrawer(&'static str),
    WorkAction(usize,usize,u64),OralWorkAction(u64),OralReferral,WorkConfirm(bool),
    Consume(usize),
    PersonalActivity(PersonalActivity),
    Lobby(crate::lobby::Command),Departure(&'static str),
}
pub const BRASS:[u8;4]=[167,137,81,255];
const RIM:[u8;4]=[89,64,34,255];
pub(crate) const IVORY:[u8;4]=[237,227,202,255];
pub(crate) const MUTED:[u8;4]=[166,186,183,255];
const FACE:[u8;4]=[33,33,36,220];

fn polity_status<'a>(skin:&Skin,p:&'a Polity)->&'a str {
    let (zh,en)=match p.status.as_str() {
        "sovereign"|"independent_state"=>("主权国家","Sovereign state"),
        "colony"=>("殖民地","Colony"),
        "protectorate"|"protected_territory"=>("保护地","Protectorate"),
        "dependency"=>("属地","Dependency"),
        "dominion"=>("自治领","Dominion"),
        "condominium"=>("共管领地","Condominium"),
        "contested"=>("争议地区","Disputed territory"),
        "occupied"=>("占领区","Occupied territory"),
        "COMPANY_ADMINISTRATION"=>("公司管理参考","Company administration"),
        "LOCAL_ADMINISTRATION"=>("地方行政参考","Local administration"),
        "LOCAL_DYNASTIC_ADMINISTRATION"=>("地方王朝行政参考","Local dynastic administration"),
        "MACRO_DISPLAY_AGGREGATE"=>("区域显示参考","Regional map reference"),
        "PROTECTED_LOCAL_AUTHORITIES"|"PROTECTED_LOCAL_AUTHORITY"=>("受保护地方政权","Protected local authority"),
        _=>("历史政治实体","Historical political entity"),
    };
    skin.choose(zh,en)
}

fn cornered([x,y,w,h]:[f32;4],c:f32)->[[f32;2];8] {
    [[x+c,y],[x+w-c,y],[x+w,y+c],[x+w,y+h-c],[x+w-c,y+h],[x+c,y+h],[x,y+h-c],[x,y+c]]
}
fn inset([x,y,w,h]:[f32;4],n:f32)->[f32;4] {[x+n,y+n,w-2.*n,h-2.*n]}
fn rim(m:&mut Mesh,area:[f32;4],r:f32,width:f32,color:[u8;4]){
    let points=cornered(area,r);
    for i in 0..8 {m.line(points[i],points[(i+1)%8],width,color);}
}
pub(crate) fn panel(m:&mut Mesh,area:[f32;4],fill:[u8;4]){
    m.shape(&cornered(area,13.),fill);
    rim(m,area,13.,5.,RIM);
    rim(m,area,13.,2.,BRASS);
    rim(m,inset(area,5.),10.,1.,BRASS);
}
fn arc(m:&mut Mesh,[x,y]:[f32;2],r:f32,a:f32,b:f32,width:f32,color:[u8;4]){
    let mut previous=[x+r*a.cos(),y+r*a.sin()];
    for i in 1..=40 {
        let t=a+(b-a)*i as f32/40.;
        let next=[x+r*t.cos(),y+r*t.sin()];
        m.line(previous,next,width,color);previous=next;
    }
}

#[derive(Clone,Copy)]
pub struct Display<'a> {
    pub skin:&'a Skin,pub hud:&'a Hud,pub session:Option<&'a Session>,pub date:crate::timeline::Date,
    pub camera:&'a Camera,pub size:[u32;2],pub mode:Mode,pub flags:Option<u8>,pub cursor:[f64;2],
    pub source:&'a str,pub feedback:&'a str,pub labels:bool,pub modern_terrain:bool,
    pub surveyed_terrain:bool,
    pub country:Option<(&'a World,CountryPanel,Option<u8>)>,
    pub written_world: Option<&'a wwo_map_lab::formal_bootstrap::InitialWorld>,
    pub managed:bool,
    pub debug:Option<&'a crate::Diagnostics>,
}
impl Display<'_> {
    pub(crate) fn can_read_world(&self) -> bool {
        self.session.is_none_or(|session| session.written_access)
    }

    pub(crate) fn ink_block(&self, mesh: &mut Mesh, [x,y,w,h]: [f32;4]) {
        mesh.rect(x,y,w,h,[0,0,0,255]);
    }

    fn history_rect(&self)->[f32;4] {
        let w=self.size[0] as f32;
        let left=148.;let right=(w-clock_radius(w)-36.).max(left+80.);
        let width=(right-left).min(560.);
        [(left+right-width)*0.5,24.,width,20.]
    }
    pub fn clock_gears(&self)->Mesh {
        let mut mesh=Mesh::default();
        if self.session.is_some() && !self.hud.mechanical.hidden {
            let w=self.size[0] as f32;let r=clock_radius(w);
            let phase=(self.hud.mechanical.phase % (std::f64::consts::TAU*72.)) as f32;
            mesh.image([w-r,0.,r,r],[phase,0.,phase,0.],[255;4]);
        }
        mesh
    }
    pub fn history_light(&self)->Mesh {
        let [x,_,width,_]=self.history_rect();
        let mut mesh=Mesh::default();
        let sunlight=crate::camera::smooth(2400.,7000.,self.camera.mpp) as f32;
        mesh.image([x-width*0.12,0.,width*1.24,116.],[0.,0.,1.,1.],[255,255,255,(sunlight*255.) as u8]);
        mesh
    }
    fn draw_clock(&self,art:&mut Mesh,clock:&mut Mesh,text:&mut Mesh,hits:&mut Vec<Hit>) {
        let w=self.size[0] as f32;
        let radius=clock_radius(w);
        let factor=radius/184.;
        let pivot=[w,0.];
        let seam=[3,5,6,245];
        let metal=[148,120,74,245];
        let highlight=[209,184,125,230];
        let ivory=[237,227,201,255];
        self.skin.sprite(art,"clock",[w-radius,0.,radius,radius]);
        let radial=|angle:f32,r:f32,t:f32|{
            let (dy,dx)=angle.to_radians().sin_cos();
            [w+dx*r-dy*t,dy*r+dx*t]
        };
        let outline=|mesh:&mut Mesh,points:&[[f32;2]],width:f32|{
            for (&a,&b) in points.iter().zip(points.iter().cycle().skip(1)){mesh.line(a,b,width,seam);}
        };
        for angle in CLOCK_ANGLES {
            let mark=[(0.775,-1.),(0.895,-1.6),(0.895,1.6),(0.775,1.)].map(|(r,t)|radial(angle,r*radius,t));
            clock.shape(&mark,if self.hud.clock_drag.is_some_and(|a|(a-angle).abs()<4.){highlight}else{metal});
            outline(clock,&mark,0.8);
        }
        let angle=self.hud.clock_drag.or(self.hud.mechanical.angle).unwrap_or(CLOCK_ANGLES[clock_index(self.session)]);
        if self.session.is_some() {
            let blend=if self.hud.clock_drag.is_some(){0.65}else if clock_at(angle)==0{0.25}else{0.4};
            let hand_color=std::array::from_fn(|i|if i==3{255}else{(f32::from(metal[i])*(1.-blend)+f32::from(highlight[i])*blend).round() as u8});
            // Same R68 silhouette with subpixel outline/highlight coverage in hud.wgsl.
            clock.image([w-radius,0.,radius,radius],[angle.to_radians(),-3.,angle.to_radians(),-3.],hand_color);
        }
        let gear_radius=34.*factor;
        let gear_active=matches!(self.hud.menu,Menu::System|Menu::Settings)||gear_hit(self.cursor,self.size[0]);
        if self.session.is_some() && !self.hud.mechanical.hidden {
            let phase=(self.hud.mechanical.phase % (std::f64::consts::TAU*72.)) as f32;
            clock.image([w-gear_radius-1.,0.,gear_radius+1.,gear_radius+1.],[phase,-2.,phase,-2.],if gear_active{highlight}else{metal});
        } else {
        let mut gear=vec![pivot];
        for i in 0..=32 {
            let angle=90.+90.*i as f32/32.;
            let reach=if matches!(i%4,1|2){1.}else{0.84};
            gear.push(radial(angle,gear_radius*reach,0.));
        }
        clock.shape(&gear,if gear_active{highlight}else{metal});
        arc(clock,pivot,gear_radius*0.59,std::f32::consts::FRAC_PI_2,std::f32::consts::PI,1.3,[59,46,28,245]);
        let circle=|mesh:&mut Mesh,center:[f32;2],r:f32|{
            let points: [[f32;2];16]=std::array::from_fn(|i|{
                let a=std::f32::consts::TAU*i as f32/16.;
                [center[0]+a.cos()*r,center[1]+a.sin()*r]
            });
            mesh.shape(&points,[6,11,16,240]);
        };
        circle(clock,pivot,gear_radius*0.26);
        for angle in [105.,135.,165.] {circle(clock,radial(angle,gear_radius*0.51,0.),gear_radius*0.055);}
        }
        if self.can_read_world() {
        if let Some(session)=self.session {
            let x=w-72.*factor;
            let time=format!("{:02}:{:02}",session.hour,session.minute);
            let day=if self.skin.english(){format!("{:02}/{:02}",self.date.month,self.date.day)}
                else{format!("{:02}月{:02}日",self.date.month,self.date.day)};
            for (value,font,baseline,ascent) in [(format!("{:04}",self.date.year),1,48.,20.),
                (day,4,72.,10.),(time,3,96.,13.)] {
                let y=baseline*factor-ascent-2.;
                for offset in [[-1.,0.],[1.,0.],[0.,-1.],[0.,1.]] {
                    self.center(text,&value,font,[x+offset[0],y+offset[1]],radius,[5,8,8,230]);
                }
                self.center(text,&value,font,[x,y],radius,ivory);
            }
        }
        } else {
            for (offset, baseline, width) in [(26., 48., 50.), (23., 72., 45.), (21., 96., 42.)] {
                self.ink_block(clock,[w-(72.+offset)*factor,(baseline-17.)*factor,width*factor,13.*factor]);
            }
        }
        Self::hit(hits,[w-gear_radius,0.,gear_radius,gear_radius],Command::Menu(Menu::System));
    }
    pub fn draw(&self, panels:&mut Mesh, art:&mut Mesh, text:&mut Mesh, clock:&mut Mesh, flags:&mut Mesh, instrument:&mut Mesh, hits:&mut Vec<Hit>){
        let [w,h]=self.size.map(|v|v as f32);
        let radius=(w*0.056).clamp(52.,78.);
        let cx=w*0.5;
        let s=self.session;
        let visual=self.skin;
        if let Some(slot)=self.flags {flags.flag([22.,19.,72.,50.],slot);}
        if s.is_some() {Self::hit(hits,[12.,12.,92.,64.],Command::PlayerCountry);}
        self.draw_clock(art,clock,text,hits);
        if self.hud.menu.modal(){self.menu(panels,text,hits,radius);return;}
        if self.hud.menu==Menu::None && clock_hit(self.cursor,self.size[0],self.session,self.hud.mechanical.angle) && self.hud.clock_drag.is_none() {
            let hint=visual.choose("拖动指针调节速度 · 顶端暂停，向下加快 · 空格开始或暂停",
                "Drag to set speed · Top to pause · Space to toggle");
            let width=visual.width(hint,0)+28.;
            let x=(w-clock_radius(w)-width-12.).max(12.);
            let y=(self.cursor[1] as f32+16.).min(h-48.);
            panel(panels,[x,y,width,34.],[8,14,21,249]);
            visual.text(text,hint,0,[x+14.,y+6.],width-28.,IVORY);
        }
        let [left,top,width,_]=self.history_rect();
        Self::hit(hits,[left-8.,top-17.,width+16.,51.],Command::Page(Page::Technology));
        if self.page_rect().is_none_or(|[_,y,_,height]| y+height<h-168. || self.hud.page!=Page::Market) {
          let tint=if self.cursor[0]>=34. && self.cursor[0]<=122. &&
              self.cursor[1]>=f64::from(h-168.) && self.cursor[1]<=f64::from(h-44.) {[255;4]}else{[242,236,224,255]};
          visual.tinted_sprite(art,"portrait",[34.,h-168.,88.,124.],tint);
          Self::hit(hits,[34.,h-168.,88.,124.],Command::Player);
          for (i,(key,label,page)) in [("accounts","财务",Page::Finance),("belongings","持有物",Page::Property),
              ("relations","关系与工作",Page::Relations)].into_iter().enumerate() {
            let [cx,cy]=portrait_action_center(i,h);
            let hover=portrait_action_hit(i,h,self.cursor);
            let tint=if hover {[255;4]} else {[231,222,206,255]};
            visual.tinted_sprite(art,key,[cx-19.,cy-21.,38.,42.],tint);
            Self::hit(hits,[cx-19.,cy-20.,38.,40.],Command::PortraitAction(i,page));
            if hover {
                let width=(visual.width(label,0)+28.).max(64.);
                panel(panels,[156.,cy-17.,width,34.],[8,14,21,249]);
                visual.text(text,label,0,[170.,cy-13.],width-22.,IVORY);
            }
          }
        }
        instrument.rect(cx-radius,h-radius,radius*2.,radius,[255;4]);
        for (r,width,color) in [(radius+14.,8.,RIM),(radius+14.,4.,BRASS),(radius+18.,1.3,IVORY),(radius+0.8,2.2,BRASS)] {
            arc(panels,[cx,h],r,std::f32::consts::PI,std::f32::consts::TAU,width,color);
        }
        for i in 0..21 {
            let a=std::f32::consts::PI*(1.+i as f32/20.);
            panels.line([cx+a.cos()*(radius+11.),h+a.sin()*(radius+11.)],[cx+a.cos()*(radius+17.),h+a.sin()*(radius+17.)],1.1,RIM);
        }
        Self::hit(hits,[cx-radius-20.,h-radius-20.,2.*radius+40.,radius+20.],Command::Menu(Menu::MapModes));
        let center=((116.+20.+h-120.)*0.5).max(190.);
        if !matches!(self.hud.menu,Menu::System|Menu::Settings|Menu::Save|Menu::Load|Menu::Overwrite(_)|Menu::Departure){
            visual.sprite(art,"messages",[w-36.,center-61.,36.,122.]);
            Self::hit(hits,[w-36.,center-61.,36.,122.],Command::Messages);
        }
        let target=self.camera.mpp*crate::camera::SCALE_TARGET_PIXELS;
        let magnitude=10_f64.powf(target.log10().floor());
        let metres=[5.,2.,1.].into_iter().map(|n|n*magnitude).find(|n|*n<=target).unwrap_or(magnitude);
        let length=(metres/self.camera.mpp) as f32;
        let start=w-160.;
        panels.line([start,h-14.],[start+length,h-14.],1.,BRASS);
        for x in [start,start+length]{panels.line([x,h-18.],[x,h-11.],1.,BRASS);}
        let scale=if metres>=1000.{format!("{} km",metres/1000.)}else{format!("{metres} m")};
        if self.can_read_world() {
            visual.text(text,&scale,0,[start+length+8.,h-25.],75.,MUTED);
        } else { self.ink_block(panels,[start+length+8.,h-19.,40.,8.]); }
        if self.modern_terrain && self.hud.page==Page::Map {
            let label=if self.surveyed_terrain {
                visual.choose("历史测绘与现代地表参照","Historical survey and modern terrain reference")
            } else {
                visual.choose("现代地表参照","Modern terrain reference")
            };
            let width=visual.width(label,0)+18.;
            let x=w-26.-width;
            panel(panels,[x,h-109.,width,23.],[8,14,21,214]);
            visual.text(text,label,0,[x+9.,h-108.],width-14.,MUTED);
        }
        if !self.feedback.is_empty() && self.hud.menu==Menu::None && self.can_read_world() {
            let width=(w-64.).min(680.);let x=(w-width)*0.5;
            panel(panels,[x,59.,width,32.],[8,13,20,249]);
            visual.text(text,self.feedback,0,[x+12.,66.],width-24.,IVORY);
        }
        if self.hud.page==Page::Map && self.hud.menu==Menu::None {
            let shortcut=match self.mode {
                Mode::Economic if s.is_some()=>Some(("打开市场",Command::Market("open",0),false)),
                Mode::Political if s.is_some()=>Some((visual.choose("国家概况","My country"),Command::PlayerCountry,false)),
                Mode::Military=>Some(("25 / 50 km 方格",Command::MilitaryGrid,self.hud.military_grid)),
                _=>None,
            };
            if let Some((label,command,active))=shortcut {
                self.row(panels,text,hits,[cx-radius-152.,h-40.,128.,28.],label,Some(Action::Hud(command)),active);
            }
        }
        if let Some(s)=self.session.filter(|_|self.written_world.is_none()&&self.debug.is_some()&&self.hud.page==Page::Map&&self.hud.menu==Menu::None){
            let caption=match s.training.as_str(){
                "paused"=>"恢复隔离训练（R68）",
                "active"|"preparing"=>"训练在 R68 窗口",
                _=>"隔离坦克训练（R68）",
            };
            self.row(panels,text,hits,[w-186.,h-114.,170.,25.],caption,
                (!matches!(s.training.as_str(),"active"|"preparing")).then_some(Action::Hud(Command::Training("open"))),false);
            if s.training=="paused" {
                self.row(panels,text,hits,[w-280.,h-114.,87.,25.],"结束训练",Some(Action::Hud(Command::Training("end"))),false);
            }
        }
        if !self.can_read_world() && !matches!(self.hud.page, Page::Map | Page::Character | Page::Travel) {
            if let Some(area) = self.page_rect() {
                self.folio(panels,art,text,hits,area,visual.choose("书面资料","Written record"));
                self.mask_record(panels,text,area);
            }
        } else {
        match self.hud.page {
            Page::Map=>(),
            Page::Finance=>self.finance(panels,art,text,hits),
            Page::Character=>self.character(panels,art,text,hits),
            Page::Travel=>self.travel_page(panels,art,text,hits),
            Page::Technology=>self.technology(panels,art,text,hits),
            Page::Market=>self.market(panels,art,text,hits),
            Page::Relations=>self.relations(panels,text,hits),
            Page::Property=>self.property(panels,art,text,hits),
        }
        }
        if let Some((world,country,flag))=self.country {
            if crate::ui::can_read_object(world, self.written_world, crate::ui::Object::Polity(country.polity)) {
                self.country(world,country,flag,panels,art,text,flags,hits);
            } else {
                let [x,y,w,h] = country.rect(self.size);
                panel(panels,[x,y,w,h],FACE);
                if let Some(slot) = flag { flags.flag([x+18.,y+14.,44.,30.],slot); }
                self.row(panels,text,hits,[x+w-45.,y+9.,28.,26.],"×",Some(Action::Country(CountryAction::Close)),false);
                self.mask_record(panels,text,[x,y,w,h]);
            }
        }
        if self.hud.messages {self.messages(panels,text,hits,center);}
        self.menu(panels,text,hits,radius);
    }

    pub(crate) fn diagnostics(&self,m:&mut Mesh,t:&mut Mesh,left:f32,right:f32){
        let Some(d)=self.debug else{return;};
        if self.hud.page!=Page::Map || self.hud.menu!=Menu::None{return;}
        let [w,h]=self.size.map(|v|v as f32);
        let width=(w*0.24).min(300.);
        let pos=self.camera.coordinates();
        let level=match self.camera.level{crate::Level::World=>"WORLD",crate::Level::Region=>"REGION",crate::Level::Local=>"LOCAL"};
        let state=self.session.map_or("Offline map".into(),|s|format!("R68 clock: {} min | {}",s.total_minutes,
            if s.paused{"paused".into()}else{format!("{}x",s.speed)}));
        let left_rows=["DEBUG / World and camera".into(),state,format!("{level} / {}",self.mode.key()),
            format!("Center: {:.4}, {:.4}",pos[0],pos[1]),format!("Scale: {:.1} m/px",self.camera.mpp)];
        let right_rows=["DEBUG / Rust renderer".into(),format!("Present: {:.0} fps | CPU: {:.1} ms",d.rate,d.cpu_ms),
            format!("Tiles: {} visible / {} cached",d.visible,d.tiles),format!("Tile data: {:.1} MiB | I/O: {}",d.mib,if d.streaming{"busy"}else{"idle"}),self.source.into()];
        for (x,y,bottom,rows) in [(12.,left,h-173.,left_rows),(w-width-43.,right,h-121.,right_rows)] {
            let count=(((bottom-y-12.)/17.).floor().max(0.) as usize).min(rows.len());
            if count<2 {continue;}
            m.rect(x,y,width,12.+count as f32*17.,[8,13,20,227]);
            for (i,row) in rows.iter().take(count).enumerate(){
                self.skin.text(t,row,0,[x+7.,y+5.+i as f32*17.],width-14.,if i==0{IVORY}else{MUTED});
            }
        }
    }

    fn hit(hits:&mut Vec<Hit>,area:[f32;4],command:Command){hits.push(Hit{area,action:Action::Hud(command)});}
    pub(crate) fn country(&self,world:&World,country:CountryPanel,flag:Option<u8>,
        m:&mut Mesh,art:&mut Mesh,t:&mut Mesh,flags:&mut Mesh,hits:&mut Vec<Hit>)
    {
        use CountryAction as Go;
        let skin=self.skin;
        let say=|zh,en|skin.choose(zh,en);
        let p=&world.polities[country.polity];
        let name=skin.country_name(p);
        let area=country.rect(self.size);
        let [x,y,w,h]=area;
        panel(m,area,[11,19,28,255]);
        let heading=match country.view {
            CountryView::Summary=>say("国家简卡","Country summary"),
            CountryView::Record=>say("国家资料","Country record"),
            CountryView::Directory(_)=>say("历史行政名录","Historical administrative directory"),
            CountryView::Region{..}=>say("历史行政区资料","Historical division record"),
        };
        skin.text(t,heading,0,[x+18.,y+12.],w-72.,BRASS);
        self.row(m,t,hits,[x+w-40.,y+9.,26.,25.],"×",Some(Action::Country(Go::Close)),false);
        let bottom=y+h-45.;
        match country.view {
            CountryView::Summary|CountryView::Record=>{
                let summary=matches!(country.view,CountryView::Summary);
                if !summary {skin.sprite(art,"country_crest",[x+w*0.5-103.,y-40.,206.,44.]);}
                skin.paragraph(t,name,1,[x+18.,y+38.,w-36.,54.],IVORY,1.);
                let status=polity_status(skin,p);
                let capital=skin.geographic_name(&format!("name:{}",p.capital))
                    .or_else(||world.places.iter().find(|place|place.name==p.capital &&
                        (place.coordinates[0]-p.capital_coordinates[0]).abs()<0.5 &&
                        (place.coordinates[1]-p.capital_coordinates[1]).abs()<0.5)
                        .and_then(|place|(!place.name_zh.is_empty()&&!skin.english()).then_some(place.name_zh.as_str())))
                    .unwrap_or(&p.capital);
                let width=w-if flag.is_some() && !summary {122.}else{36.};
                if let Some(slot)=flag {
                    let flag_y=if summary {bottom-15.}else{y+94.};
                    flags.flag([x+w-92.,flag_y,70.,44.],slot);
                }
                let mut rows=vec![if summary {status.into()}else{format!("{} · {status}",say("历史身份","Historical status"))}];
                if !capital.is_empty() {rows.push(format!("{} · {capital}",say("首都","Capital")));}
                if !summary {
                    rows.push(format!("{} · {} — {}",say("资料有效期","Record dates"),p.from_date,p.to_date));
                    if let Some(controller)=world.polities.iter().find(|state|state.id==p.controller_id) {
                        let text = if self.written_world.is_none_or(|world| world.can_read_polity_record(&controller.id)) {
                            skin.country_name(controller)
                        } else { "■■■■" };
                        rows.push(format!("{} · {text}",say("历史管辖","Historical authority")));
                    }
                    rows.push(format!("{} · {}",say("资料来源","Source"),if p.display_only && !p.authority_id.is_empty(){&p.authority_id}else{"WWO / CShapes 2.0"}));
                    if p.authority_note.is_empty(){
                        rows.push(p.map_id());
                    }
                }
                for (i,row) in rows.iter().enumerate(){
                    skin.text(t,row,0,[x+18.,y+96.+i as f32*23.],if i<2{width}else{w-36.},IVORY);
                }
                if summary {
                    self.row(m,t,hits,[x+18.,bottom,136.,29.],say("完整资料","Full record"),Some(Action::Country(Go::Record)),false);
                } else {
                    if p.display_only && !p.boundary_kind.is_empty() {
                        let boundary=if p.boundary_kind.starts_with("APPROXIMATE") {
                            say("近似历史边界","Approximate historical boundary")
                        }else{say("历史边界参考","Historical boundary reference")};
                        let source=format!("{boundary} · {}  {}",p.geometry_feature_id,p.source_geometry_date);
                        skin.text(t,&source,0,[x+18.,bottom-25.],w-36.,MUTED);
                    }
                    if !p.authority_note.is_empty() {
                        let note=format!("{} · {}",say("史料原文","Source note"),p.authority_note);
                        let top=y+96.+rows.len() as f32*23.;
                        skin.paragraph(t,&note,0,[x+18.,top,w-36.,(bottom-28.-top).max(0.)],MUTED,0.9);
                    }
                    if skin.admin_count(world,p)>0 {
                        self.row(m,t,hits,[x+18.,bottom,300.,29.],say("历史行政名录","Historical administrative directory"),Some(Action::Country(Go::Directory)),false);
                    }
                    if self.session.is_none_or(|s|s.polity!=p.map_id()) {
                        self.row(m,t,hits,[x+w-115.,bottom,98.,29.],say("返回","Back"),Some(Action::Country(Go::Back)),false);
                    }
                }
            }
            CountryView::Directory(page)=>{
                let limit=country.rows(self.size);
                let count=skin.admin_count(world,p);
                let page=page.min(count.saturating_sub(1)/limit);
                let subtitle=format!("{name} · {}",say("1900 年公开史料","Public records, 1900"));
                skin.text(t,&subtitle,0,[x+18.,y+39.],w-36.,MUTED);
                for (r,index) in (page*limit..count).take(limit).enumerate(){
                    if let Some(record)=skin.admin_record(world,p,index) {
                        self.row(m,t,hits,[x+18.,y+65.+r as f32*29.,w-36.,25.],record.name,
                            Some(Action::Country(Go::Region(index))),false);
                    }
                }
                if page>0 {
                    self.row(m,t,hits,[x+18.,bottom,110.,29.],say("上一页","Previous"),Some(Action::Country(Go::Page(-1))),false);
                }
                if (page+1)*limit<count {
                    self.row(m,t,hits,[x+138.,bottom,110.,29.],say("下一页","Next"),Some(Action::Country(Go::Page(1))),false);
                }
                self.row(m,t,hits,[x+w-115.,bottom,98.,29.],say("返回","Back"),Some(Action::Country(Go::Back)),false);
            }
            CountryView::Region{index,..}=>{
                let Some(record)=skin.admin_record(world,p,index) else{return;};
                skin.paragraph(t,record.name,1,[x+18.,y+39.,w-36.,53.],IVORY,1.);
                skin.text(t,&format!("{name} · {}",say("1900 年","1900")),0,[x+18.,y+99.],w-36.,IVORY);
                if record.name!=record.original {
                    skin.text(t,&format!("{} · {}",say("历史原名","Historical name"),record.original),0,[x+18.,y+125.],w-36.,MUTED);
                }
                let description=if record.boundary.is_some() {say("边界资料 · 法国历史地理重建（TRF-GIS）","Boundary source · French historical reconstruction (TRF-GIS)")}
                    else {say("本条目为公开历史名称资料。","This entry is a public historical name record.")};
                skin.paragraph(t,description,0,[x+18.,y+157.,w-36.,68.],MUTED,1.);
                if let Some(boundary)=record.boundary {
                    self.row(m,t,hits,[x+18.,bottom,174.,29.],say("查看地图边界","Show map boundary"),Some(Action::Country(Go::Boundary(boundary))),false);
                }
                self.row(m,t,hits,[x+w-115.,bottom,98.,29.],say("返回","Back"),Some(Action::Country(Go::Back)),false);
            }
        }
    }
    fn mask_record(&self, m: &mut Mesh, t: &mut Mesh, [x,y,w,h]: [f32;4]) {
        self.skin.text(t,self.skin.choose("无法阅读此语言。","You cannot read this language."),
            0,[x+22.,y+58.],w-44.,MUTED);
        for index in 0..((h-104.)/29.).clamp(0.,4.) as usize {
            self.ink_block(m,[x+22.,y+90.+29.*index as f32,(w-44.)*(0.8-0.11*index as f32),13.]);
        }
    }

    fn center(&self,t:&mut Mesh,label:&str,font:usize,[x,y]:[f32;2],limit:f32,color:[u8;4]){
        self.skin.text(t,label,font,[x-self.skin.width(label,font).min(limit)*0.5,y],limit,color);
    }
    pub(crate) fn row(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,a:[f32;4],label:&str,action:Option<Action>,active:bool){
        let [x,y,w,_]=a;
        m.shape(&cornered(a,5.),if active{[63,66,60,255]}else{[9,14,20,245]});
        rim(m,a,5.,1.,if active{BRASS}else{RIM});
        let tx=if w<40.{x+(w-self.skin.width(label,0))*0.5}else{x+9.};
        self.skin.text(t,label,0,[tx,y+4.],if w<40.{w}else{w-18.},if action.is_some(){IVORY}else{MUTED});
        if let Some(action)=action{hits.push(Hit{area:a,action});}
    }
    pub(crate) fn settings(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,[x,y,width,_]:[f32;4],back:Command,slider:bool){
        let half=(width-40.)*0.5;
        let caption=self.skin.localized("主音量 · %d%%").replace("%d",&self.hud.volume.to_string()).replace("%%","%");
        self.skin.text(t,&caption,5,[x+16.,y+46.],width-32.,IVORY);
        let row=|m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,a:[f32;4],label:&str,cmd:Command,selected:bool| {
            let [left,top,w,h]=a;
            let hover=self.cursor[0]>=f64::from(left)&&self.cursor[0]<f64::from(left+w)
                &&self.cursor[1]>=f64::from(top)&&self.cursor[1]<f64::from(top+h);
            m.shape(&cornered(a,5.),if selected{[99,145,143,184]}else if hover{[26,31,35,240]}else{[6,11,16,240]});
            rim(m,a,5.,0.9,if selected||hover{[209,184,125,230]}else{[59,46,28,245]});
            if selected{m.line([left+8.,top+h-3.],[left+w-8.,top+h-3.],1.,[209,184,125,230]);}
            self.skin.text(t,label,6,[left+9.,top+7.],w-18.,IVORY);
            hits.push(Hit{area:a,action:Action::Hud(cmd)});
        };
        if slider {
            let left=x+16.;let span=width-32.;
            m.rect(left,y+82.,span,3.,RIM);
            m.rect(left,y+82.,span*f32::from(self.hud.volume)/100.,3.,BRASS);
            m.rect(left+span*f32::from(self.hud.volume)/100.-4.,y+76.,8.,15.,IVORY);
        } else {
            row(m,t,hits,[x+16.,y+73.,half,28.],"− 10%",Command::Volume(self.hud.volume.saturating_sub(10)),false);
            row(m,t,hits,[x+24.+half,y+73.,half,28.],"＋ 10%",Command::Volume((self.hud.volume+10).min(100)),false);
        }
        row(m,t,hits,[x+16.,y+112.,width-32.,29.],if self.hud.fullscreen{"全屏"}else{"窗口"},Command::Fullscreen,self.hud.fullscreen);
        row(m,t,hits,[x+16.,y+154.,width-32.,28.],if self.labels{"地图名称 · 开启"}else{"地图名称 · 关闭"},Command::Labels,self.labels);
        self.skin.text(t,"语言",7,[x+16.,y+185.],width-32.,IVORY);
        row(m,t,hits,[x+16.,y+207.,half,29.],"简体中文",Command::Language(false),!self.hud.english);
        row(m,t,hits,[x+24.+half,y+207.,half,29.],"English",Command::Language(true),self.hud.english);
        row(m,t,hits,[x+16.,y+248.,width-32.,29.],"返回",back,false);
    }
    pub(crate) fn folio(&self,m:&mut Mesh,art:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,a:[f32;4],title:&str){
        self.decorated_folio(m,art,t,hits,a,title,"crest");
    }
    pub(crate) fn decorated_folio(&self,m:&mut Mesh,art:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,a:[f32;4],title:&str,crest:&str){
        let [x,y,w,h]=a;
        panel(m,a,FACE);
        self.skin.sprite(art,crest,[x+w*0.5-97.,y-49.,194.,55.]);
        rim(m,[x+15.,y+8.,w-30.,38.],10.,1.7,BRASS);
        m.line([x+13.,y+52.],[x+w-13.,y+52.],1.4,BRASS);
        arc(m,[x+w*0.5,y+h-5.],13.,3.142,6.283,5.,BRASS);
        self.center(t,title,1,[x+w*0.5,y+12.],w-65.,IVORY);
        self.row(m,t,hits,[x+w-39.,y-35.,28.,26.],"×",Some(Action::Hud(Command::Page(Page::Map))),false);
    }
    pub fn page_rect(&self)->Option<[f32;4]>{page_rect(self.hud,self.size)}
    fn relations(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>){
        let Some([x,y,w,max_height])=self.page_rect() else{return;};
        let say=|zh,en|self.skin.choose(zh,en);
        let view=self.session.and_then(|session|session.relations.as_ref());
        let selected=view.and_then(|view|view.rows.iter().find(|row|row.id==view.selected));
        let height=match view {
            Some(_) if selected.is_some()=>max_height,
            Some(view) if matches!(view.drawer.as_str(),"relations"|"local")=>max_height.min(202.+(view.rows.len() as f32*34.).max(24.)),
            Some(view) if view.drawer=="work"=>max_height,
            _=>190.,
        };
        panel(m,[x,y,w,height],FACE);
        arc(m,[x+w*0.5,y+height-5.],10.,3.142,6.283,4.,BRASS);
        self.skin.text(t,selected.map_or(say("组织与工作","Organisations and work"),|row|row.label.as_str()),1,[x+20.,y+14.],w-110.,IVORY);
        self.row(m,t,hits,[x+w-80.,y+12.,64.,26.],say("返回","Back"),Some(Action::Hud(
            if selected.is_some(){Command::Relation(None)}else{Command::Page(Page::Map)})),false);
        let Some(view)=view else {
            self.skin.text(t,say("正在读取组织关系","Loading relations"),0,[x+20.,y+72.],w-40.,MUTED);
            return;
        };
        if let Some(row)=selected.filter(|_|!view.has_local) {
            for (i,value) in [&row.kind,&row.role,&row.place,&row.basis].into_iter().filter(|v|!v.is_empty()).enumerate() {
                self.skin.text(t,value,0,[x+20.,y+74.+i as f32*29.],w-40.,IVORY);
            }
            return;
        }
        if !view.work_feedback.is_empty() {
            self.skin.text(t,&view.work_feedback,0,[x+20.,y+48.],w-40.,IVORY);
        }
        let work_title=if view.work_title.is_empty(){say("工作与经营","Work and business")}
            else{say(view.work_title.as_str(),"Livelihood, work and travel")};
        if selected.is_none() {
            let tabs = [("relations",say("我的组织","My organisations"),true),
                ("local",say("当地组织","Local organisations"),view.has_local),
                ("work",work_title,view.has_work)];
            let n=tabs.iter().filter(|(_,_,visible)|*visible).count() as f32;
            let tab_width=(w-40.-(n-1.)*6.)/n;
            for (index,(drawer,label,_)) in tabs.into_iter().filter(|(_,_,visible)|*visible).enumerate() {
                self.row(m,t,hits,[x+20.+index as f32*(tab_width+6.),y+78.,tab_width,29.],label,
                    Some(Action::Hud(Command::RelationDrawer(drawer))),view.drawer==drawer);
            }
        }
        if view.drawer=="work" || selected.is_some() {
            let start=if selected.is_some(){y+83.}else{y+125.};
            if let Some(confirmation)=&view.confirmation {
                self.skin.text(t,&confirmation.title,1,[x+20.,start],w-40.,IVORY);
                self.skin.text(t,&confirmation.body,0,[x+20.,start+35.],w-40.,MUTED);
                for (index,(label, confirmed)) in [(say("确认","Confirm"),true),(say("取消","Cancel"),false)].into_iter().enumerate() {
                    self.row(m,t,hits,[x+20.+index as f32*120.,start+71.,110.,26.],label,Some(Action::Hud(Command::WorkConfirm(confirmed))),false);
                }
                return;
            }
            let offset=self.hud.market_offset.min(view.work.len().saturating_sub(1));
            let mut next=offset;
            let mut top=start;
            for (index,row) in view.work.iter().enumerate().skip(offset) {
                let action_height=if row.actions.is_empty(){0.}else{29.};
                let detail_height=22.+row.details.len() as f32*18.;
                let row_height=detail_height+action_height;
                if top+row_height>y+height-41. {break;}
                self.skin.text(t,&row.label,1,[x+20.,top],w-40.,IVORY);
                for (i,line) in row.details.iter().enumerate() {
                    self.skin.text(t,line,0,[x+20.,top+22.+i as f32*18.],w-40.,MUTED);
                }
                for (action_index, action) in row.actions.iter().enumerate() {
                    self.row(m,t,hits,[x+20.+action_index as f32*166.,top+detail_height,156.,25.],&action.label,
                        action.enabled.then_some(Action::Hud(Command::WorkAction(index,action_index,view.work_revision))),false);
                }
                top+=row_height+7.;
                next=index+1;
            }
            if offset>0 || next<view.work.len() {
                for (index,(label, step, enabled)) in [(say("向上","Up"),-1,offset>0),
                    (say("向下","Down"),1,next<view.work.len())].into_iter().enumerate() {
                    self.row(m,t,hits,[x+w-164.+index as f32*74.,y+height-34.,70.,24.],label,
                        enabled.then_some(Action::Hud(Command::MarketScroll(step))),false);
                }
            }
            return;
        }
        if !matches!(view.drawer.as_str(),"relations"|"local") {return;}
        if view.rows.is_empty(){
            let label=if view.drawer=="local"{say("此地暂无已登记的组织。","No organisations registered here.")}
                else{say("暂无成员或任职记录。","No membership or position records.")};
            self.skin.text(t,label,0,[x+20.,y+127.],w-40.,MUTED);
        }
        let offset=self.hud.market_offset.min(view.rows.len().saturating_sub(1));
        let capacity=((height-166.)/34.).max(1.) as usize;
        for (i,row) in view.rows.iter().enumerate().skip(offset).take(capacity) {
            self.row(m,t,hits,[x+20.,y+126.+(i-offset) as f32*34.,w-40.,29.],
                &format!("{} · {} · {}",row.label,row.kind,row.role),Some(Action::Hud(Command::Relation(Some(i)))),false);
        }
        if offset>0 || offset+capacity<view.rows.len(){
            for (index,(label,step,enabled)) in [(say("向上","Up"),-1,offset>0),
                (say("向下","Down"),1,offset+capacity<view.rows.len())].into_iter().enumerate(){
                self.row(m,t,hits,[x+w-164.+index as f32*74.,y+height-34.,70.,24.],label,
                    enabled.then_some(Action::Hud(Command::MarketScroll(step))),false);
            }
        }
    }
    fn character(&self, m: &mut Mesh, art: &mut Mesh, t: &mut Mesh, hits: &mut Vec<Hit>) {
        let Some([x,y,w,h]) = self.page_rect() else { return; };
        let skin=self.skin;
        let say=|zh,en|skin.choose(zh,en);
        self.folio(m,art,t,hits,[x,y,w,h],say("人物资料","Character record"));
        if self.session.is_some_and(|session| session.transport.is_some()) {
            self.row(m,t,hits,[x+w-193.,y+16.,141.,27.],say("旅行与通勤","Travel & commute"),
                Some(Action::Hud(Command::Page(Page::Travel))),false);
        }
        let Some(character) = self.session.and_then(|s| s.character.as_ref()) else { return; };
        if !self.can_read_world() {
            let has_contacts=!character.oral_contacts.is_empty();
            let has_referral=character.oral_referral.is_some();
            self.mask_record(m,t,[x,y,w,if has_contacts || has_referral {90.} else {157.}]);
            if has_contacts {
                let offset=self.hud.market_offset.min(character.oral_contacts.len()-1);
                self.skin.paragraph(t,&character.oral_contacts[offset],0,[x+22.,y+87.,w-44.,53.],IVORY,1.);
                if character.oral_contacts.len()>1 {
                    for (i,(label,step,enabled)) in [
                        (say("向上","Up"),-1,offset>0),
                        (say("向下","Down"),1,offset+1<character.oral_contacts.len()),
                    ].into_iter().enumerate(){
                        self.row(m,t,hits,[x+22.+i as f32*74.,y+142.,70.,24.],label,
                            enabled.then_some(Action::Hud(Command::MarketScroll(step))),false);
                    }
                }
            }
            if let Some(office)=&character.oral_referral {
                let label=format!("{} · {}",office.label,say("请人介绍工作","Ask for a referral"));
                let top=if character.oral_contacts.len()>1 {174.} else if has_contacts {142.} else {92.};
                self.row(m,t,hits,[x+22.,y+top,(w-44.).min(410.),27.],&label,
                    Some(Action::Hud(Command::OralReferral)),false);
            }
            self.personal_activities(m,t,hits,[x,y+149.,w,h-149.]);
            return;
        }
        let profile = &character.profile;
        let social = &profile.social;
        let caption=if skin.english(){
            format!("{} · About {} years old · {}",skin.localized(&profile.name),profile.age_years,skin.localized(&profile.health_status))
        }else{format!("{} · 约 {} 岁 · {}",profile.name,profile.age_years,profile.health_status)};
        let absent=say("暂无记录","No record");
        let settled=if skin.english(){format!("Health and ageing are modelled · Game day {}",character.settled_day+1)}
            else{format!("健康与衰老模型采用开发假设 · 已结算游戏第 {} 日",character.settled_day+1)};
        let entries = [
            caption,
            settled,
            format!("{} · {}",say("工作","Work"),social.occupation.as_deref().unwrap_or(absent)),
            social.economic_situation.as_deref().unwrap_or(say("现金资料不可用","Cash record unavailable")).into(),
            format!("{} · {}",say("组织","Organisations"),social.relationships.as_deref().filter(|r|!r.is_empty()).map_or_else(||absent.into(),|r|r.join("、"))),
            format!("{} · {}",social.family_background.as_deref().unwrap_or(absent),social.education.as_deref().unwrap_or(absent)),
        ];
        for (index, entry) in entries.iter().enumerate() {
            skin.text(t, entry, 0, [x+22.,y+61.+index as f32*22.], w-44., IVORY);
        }
        let history = if profile.history.is_empty() { absent.to_owned() } else { profile.history.join("、") };
        let oral_work = self.session.and_then(|session| session.activities.as_ref())
            .is_some_and(|activities| activities.oral_work.is_some());
        let history_height = (h-333.).clamp(24.,85.);
        let history_height = if oral_work { history_height.min(h-336.) } else { history_height };
        if history_height >= 18. {
            skin.paragraph(t, &format!("{} · {history}", say("经历","History")),
                0, [x+22.,y+193.,w-44.,history_height], IVORY, 1.);
        }
        let conditions = profile.traits.iter().filter(|value| !profile.history.contains(value)).map(String::as_str).collect::<Vec<_>>();
        let traits_y = y + (h - 140.).clamp(221., 282.);
        if !conditions.is_empty() && (!oral_work || traits_y + 21. <= y+h-139.) {
            skin.text(t,&conditions.join("、"),0,[x+22.,traits_y],w-44.,IVORY);
        }
        if self.session.is_some_and(|session| session.activities.is_some()) {
            self.personal_activities(m,t,hits,[x,y+h-151.,w,151.]);
        } else if let Some(assessment) = &character.assessment {
            for (index, line) in assessment.explanation.iter().skip(1).take(2).enumerate() {
                skin.text(t,line,0,[x+22.,traits_y+25.+index as f32*22.],w-44.,MUTED);
            }
        }
        for (index, (label, action)) in [
            (say("定位人物","Find player"), Command::LocatePlayer),
            (say("关系与工作","Work & relations"), Command::Page(Page::Relations)),
            (say("持有物","Inventory"), Command::Page(Page::Property)),
        ].into_iter().enumerate() {
            let enabled=!matches!(action,Command::LocatePlayer) || self.session.is_some_and(|session|!session.coordinates.is_empty());
            self.row(m,t,hits,[x+22.+index as f32*166.,y+h-45.,155.,26.],label,enabled.then_some(Action::Hud(action)),false);
        }
    }
    fn personal_activities(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,[x,y,w,h]:[f32;4]) {
        let Some(activities) = self.session.and_then(|session| session.activities.as_ref()) else { return; };
        let say = |zh,en| self.skin.choose(zh,en);
        let rows = [
            (PersonalActivity::Lesson, say("学习识字", "Attend reading lesson"), activities.lesson),
            (PersonalActivity::ReadNotice, say("请教师代读", "Ask teacher to read the notice"), activities.read_notice),
            (PersonalActivity::Rest, say("安排休息", "Schedule rest"), activities.rest),
        ];
        let label = match activities.scheduled {
            Some(PersonalActivity::Lesson) => say("已安排课程，推进时间以完成。","Lesson scheduled. Advance time to attend.").to_owned(),
            Some(PersonalActivity::ReadNotice) => say("已约教师，推进时间以听取公告。","Teacher arranged. Advance time to hear the notice.").to_owned(),
            Some(PersonalActivity::Rest) => say("已安排休息。已食用的食物有助于恢复。","Rest scheduled. Food already eaten aids recovery.").to_owned(),
            None => activities.oral_notice.clone().unwrap_or_else(|| {
                if self.can_read_world() { say("休息与进食有助于恢复。","Rest and food aid recovery.").into() }
                else { format!("{} · {}", say("本地语言","Local language"), activities.language.label()) }
            }),
        };
        let offset = if self.can_read_world() { 48. } else { 0. };
        let top = y+h-91.-offset;
        if let Some(work) = &activities.oral_work {
            let employer = say(&work.employer, &work.employer_english);
            let terms = if self.skin.english() {
                format!("{} h/shift · {} per hour · Pay in {} days", work.hours, work.wage_per_hour, work.wage_delay)
            } else {
                format!("每班 {} 小时 · 时薪 {} · {} 日后发薪", work.hours, work.wage_per_hour, work.wage_delay)
            };
            let (title, details, confirming, button) = match work.state {
                OralWorkState::Offer { vacancies, confirming } => {
                    let title = if matches!(activities.oral_work_feedback, Some(OralWorkFeedback::Unavailable)) {
                        say("当前无法申请", "Application unavailable")
                    } else {
                        if work.referred {say("联络员口述","Coordinator’s referral")} else {say("教师口述", "Teacher's notice")}
                    };
                    let details = format!("{} {vacancies} · {terms}", say("空缺", "Openings"));
                    let button = if vacancies > 0 { say("申请","Apply") } else { say("暂无空缺","No openings") };
                    (title, details, confirming, button)
                }
                OralWorkState::Contract { booked, present, can_book } => {
                    let button = if booked { say("已登记","Shift booked") }
                        else if !present { say("不在工作地点","Away from work") }
                        else if can_book { say("登记工作","Book shift") }
                        else { say("今日无法登记","Unavailable today") };
                    (say("劳动合同", "Employment contract"), terms, false, button)
                }
            };
            let title = format!("{title} · {employer}");
            let actions_width = if confirming { 188. } else { 136. };
            self.skin.text(t,&title,0,[x+22.,top],w-52.-actions_width,IVORY);
            self.skin.text(t,&details,0,[x+22.,top+18.],w-52.-actions_width,MUTED);
            let button_x = x+w-22.-actions_width;
            if confirming {
                for (index,(label,confirm)) in [(say("确认申请","Confirm"),true),(say("取消","Cancel"),false)].into_iter().enumerate() {
                    self.row(m,t,hits,[button_x+index as f32*96.,top+3.,92.,29.],label,
                        Some(Action::Hud(Command::WorkConfirm(confirm))),false);
                }
            } else {
                let enabled = activities.oral_work_action(work.revision).is_some();
                self.row(m,t,hits,[button_x,top+3.,actions_width,29.],button,
                    enabled.then_some(Action::Hud(Command::OralWorkAction(work.revision))),false);
            }
        } else {
            let status = match activities.oral_work_feedback {
                Some(OralWorkFeedback::Signed) => say("劳动合同已签订。","Employment contract signed."),
                Some(OralWorkFeedback::Unavailable) => say("该岗位当前无法申请。","The job is no longer available."),
                None => &label,
            };
            self.skin.text(t,status,0,[x+22.,top+5.],w-44.,IVORY);
        }
        let button_width = (w-56.)/3.;
        for (index,(kind,label,enabled)) in rows.into_iter().enumerate() {
            self.row(m,t,hits,[x+22.+index as f32*(button_width+6.),y+h-52.-offset,button_width,29.],
                label,enabled.then_some(Action::Hud(Command::PersonalActivity(kind))),activities.scheduled==Some(kind));
        }
    }

    fn finance(&self,m:&mut Mesh,art:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>){
        let Some([x,y,w,h])=self.page_rect() else{return;};
        self.folio(m,art,t,hits,[x,y,w,h],"财务");
        let Some(s)=self.session else {
            self.skin.text(t,"正式世界未连接",0,[x+20.,y+69.],w-40.,MUTED);return;
        };
        self.skin.text(t,&s.finance.summary,0,[x+18.,y+68.],w-36.,IVORY);
        if s.finance.rows.is_empty(){self.skin.text(t,"暂无账务记录。",0,[x+18.,y+108.],w-36.,MUTED);}
        for (i,row) in s.finance.rows.iter().enumerate(){
            let top=y+110.+i as f32*28.;
            self.skin.text(t,&row.description,0,[x+18.,top],w*0.72,IVORY);
            let ink=if row.amount.starts_with('+'){[195,218,174,255]}else{[235,183,145,255]};
            self.skin.text(t,&row.amount,0,[x+w-18.-self.skin.width(&row.amount,0),top],120.,ink);
        }
        for (i,(label,page,enabled)) in [("较新记录",s.finance.page.saturating_sub(1),s.finance.page>0),("较早记录",s.finance.page.saturating_add(1),s.finance.more)].into_iter().enumerate(){
            if s.finance.more || s.finance.page>0 {
                self.row(m,t,hits,[x+18.+i as f32*96.,y+h-52.,86.,25.],label,enabled.then_some(Action::Hud(Command::FinancePage(page))),false);
            }
        }
    }
    fn technology(&self,m:&mut Mesh,art:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>){
        let Some([x,y,w,h])=self.page_rect() else{return;};
        let technology=self.session.map(|s|&s.technology);
        let title=technology.map(|p|format!("{} · 科技",p.country)).unwrap_or_else(||"科技".into());
        self.folio(m,art,t,hits,[x,y,w,h],&title);
        let Some(p)=technology else{self.skin.text(t,"正式世界未连接",0,[x+20.,y+69.],w-40.,MUTED);return;};
        for (i,(section,label)) in [(Tech::Capacity,"工程与能力"),(Tech::Chronicle,"发展纪事"),(Tech::Public,p.public_country.as_str())].into_iter().enumerate(){
            if label.is_empty(){continue;}
            self.row(m,t,hits,[x+22.+i as f32*132.,y+60.,122.,29.],label,Some(Action::Hud(Command::Technology(section))),self.hud.tech==section);
        }
        let start=y+103.;
        if self.hud.tech==Tech::Chronicle {
            if p.milestones.is_empty(){self.skin.text(t,"本局还没有科技里程碑。",0,[x+22.,start+12.],w-44.,MUTED);}
            for (i,row) in p.milestones.iter().enumerate().take(3){
                let top=start+i as f32*36.;
                self.skin.text(t,&row.date,0,[x+24.,top+3.],145.,MUTED);
                self.row(m,t,hits,[x+173.,top,w-199.,28.],&row.title,Some(Action::Hud(Command::Milestone(i))),self.hud.milestone==i);
            }
            if let Some(row)=p.milestones.get(self.hud.milestone).or_else(||p.milestones.last()){
                self.skin.text(t,&row.kind,0,[x+22.,y+h-79.],w-44.,MUTED);
                self.skin.text(t,&row.effect,0,[x+22.,y+h-54.],w-44.,IVORY);
            }
            return;
        }
        let public=self.hud.tech==Tech::Public;
        let heading=if public{"公开的开局能力"}else{"1900 年 · 开局技术底册"};
        self.skin.text(t,heading,0,[x+22.,start],w-44.,IVORY);
        let plates=if public{&p.public_foundation}else{&p.foundation};
        if plates.is_empty(){self.skin.text(t,"尚无该国的科技基础资料。",0,[x+22.,start+48.],w-44.,MUTED);}
        let width=(w-44.)/plates.len().max(1) as f32;
        for (i,entry) in plates.iter().enumerate(){
            let left=x+22.+i as f32*width;
            m.rect(left,start+28.,width,146.,[46,50,51,165]);
            for j in 0..(width/16.) as usize {m.rect(left+j as f32*16.,start+28.,0.7,146.,[112,125,124,90]);}
            for j in 0..10 {m.rect(left,start+28.+j as f32*16.,width,0.7,[112,125,124,90]);}
            Self::engraving(m,[left+width*0.5,start+73.],&entry.kind);
            self.skin.text(t,&entry.title,0,[left+9.,start+99.],width-18.,IVORY);
            self.skin.text(t,&entry.description,0,[left+9.,start+123.],width-18.,MUTED);
        }
        if !public {
            self.skin.text(t,if p.project_active{"工程项目操作尚未迁移。"}else{"本局暂无可查看的工程项目。"},0,[x+22.,y+h-48.],w-44.,MUTED);
        }
    }
    fn engraving(m:&mut Mesh,[x,y]:[f32;2],kind:&str){
        match kind {
            "rail"=>{
                for dx in [-10.,-5.,0.,5.,10.] {m.rect(x+dx,y-10.,1.5,20.,IVORY);}
                for dy in [-7.,7.] {m.rect(x-13.,y+dy,26.,1.7,IVORY);}
            },
            "rollers"=>for dy in [-8.,0.,8.] {
                m.rect(x-13.,y+dy,26.,1.7,IVORY);rim(m,[x-10.,y+dy-2.,20.,5.],1.,0.8,IVORY);
            },
            _=>{
                arc(m,[x,y],10.,0.,6.283,1.8,IVORY);arc(m,[x,y],5.,0.,6.283,1.2,IVORY);
                m.rect(x-14.,y,28.,1.5,IVORY);m.rect(x-9.,y+11.,18.,1.5,IVORY);
            }
        }
    }
    fn messages(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,center:f32){
        let [w,h]=self.size.map(|v|v as f32);
        let a=message_rect([w,h],center);let [x,y,width,height]=a;
        panel(m,a,FACE);
        self.skin.text(t,"消息记录",1,[x+14.,y+11.],width-54.,IVORY);
        self.skin.text(t,"当前会话 · 最近记录",0,[x+14.,y+43.],width-54.,MUTED);
        m.rect(x+14.,y+63.,width-47.,1.5,BRASS);
        let Some(s)=self.session else {self.skin.text(t,"正式世界未连接",0,[x+14.,y+69.],width-53.,MUTED);return;};
        if !self.can_read_world() {
            self.mask_record(m,t,[x,y+14.,width,height-14.]);
            return;
        }
        if s.messages.is_empty(){self.skin.text(t,"暂无消息。",0,[x+14.,y+69.],width-53.,MUTED);}
        let mut top=y+70.;
        for (i,msg) in s.messages.iter().enumerate().skip(self.hud.message_offset){
            if top>y+height-101. {break;}
            self.skin.text(t,&format!("{} · 接收于 {}",msg.source,msg.received_at),0,[x+14.,top],width-50.,MUTED);
            self.skin.text(t,&msg.text,0,[x+14.,top+20.],width-50.,IVORY);
            if !msg.action.is_empty(){
                self.row(m,t,hits,[x+14.,top+40.,65.,24.],"查看",Some(Action::Hud(Command::MessageLink(i))),false);
                top+=25.;
            }
            top+=55.;
        }
        self.row(m,t,hits,[x+14.,y+height-45.,width-49.,26.],"百科 / 帮助 · 未迁移",None,false);
    }
    fn menu(&self,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>,radius:f32){
        let [w,h]=self.size.map(|v|v as f32);
        let menu=self.hud.menu;
        if menu==Menu::None{return;}
        let dark=[8,13,20,if menu==Menu::MapModes{255}else{249}];
        let [x,y,width,height]=menu_rect(self.hud.menu,self.size,radius);
        if menu.modal(){
            m.rect(0.,0.,w,h,[0,0,0,130]);hits.clear();
        }
        if menu==Menu::Settings {
            m.shape(&cornered(inset([x,y,width,height],4.),12.),dark);
            rim(m,inset([x,y,width,height],4.),12.,4.,RIM);
            rim(m,inset([x,y,width,height],4.),12.,1.5,[189,152,88,255]);
            rim(m,inset([x,y,width,height],9.),9.,1.,[142,119,81,173]);
        } else {panel(m,[x,y,width,height],dark);}
        let title=match menu{Menu::MapModes=>"地图模式",Menu::System=>"系统菜单",Menu::Settings=>"设置",Menu::Save=>"保存",Menu::Load=>"加载",Menu::Overwrite(_)=>"覆盖已有存档？",Menu::Departure=>"保存当前游戏？",Menu::None=>unreachable!()};
        self.skin.text(t,title,if menu==Menu::Settings{0}else{1},[x+16.,y+7.],width-32.,IVORY);
        m.rect(x+13.,y+31.,width-26.,1.5,BRASS);
        let action=|command|Some(Action::Hud(command));
        match menu {
            Menu::MapModes=>{
                let rows=[("政治地图",Mode::Political),("经济地图",Mode::Economic),("军事地图",Mode::Military)];
                for (i,(label,mode)) in rows.into_iter().enumerate(){
                    let active=self.mode==mode;
                    let action=if active{Mode::Geographic}else{mode};
                    self.row(m,t,hits,[x+13.,y+37.+i as f32*32.,width-26.,27.],label,Some(Action::Mode(action)),active);
                }
                if self.mode!=Mode::Geographic {
                    self.skin.text(t,"再次点击当前模式可返回基础地貌",0,[x+15.,y+136.],width-30.,MUTED);
                }
            },
            Menu::System=>{
                let connected=self.session.is_some();
                let rows=[("保存",connected.then_some(Command::Menu(Menu::Save))),("加载",connected.then_some(Command::Menu(Menu::Load))),
                    ("设置",Some(Command::Menu(Menu::Settings))),("返回主菜单",self.managed.then_some(Command::Departure("system:main_menu"))),
                    ("退出",(!connected||self.managed).then_some(Command::Quit))];
                for (i,(label,cmd)) in rows.into_iter().enumerate(){self.row(m,t,hits,[x+14.,y+40.+i as f32*39.,width-28.,30.],label,cmd.map(Action::Hud),false);}
            },
            Menu::Settings=>{
                self.settings(m,t,hits,[x,y,width,height],Command::Menu(Menu::System),false);
            },
            Menu::Save|Menu::Load=>{
                if let Some(session)=self.session {
                    let mut top=y+40.;
                    for row in session.slots.iter().filter(|r|menu==Menu::Load||r.slot>0){
                        let enabled=!self.hud.waiting_slot&&(menu==Menu::Save||row.can_read);
                        self.row(m,t,hits,[x+14.,top,width-28.,28.],&row.name,enabled.then_some(Action::Hud(Command::Slot(row.slot))),false);
                        if self.can_read_world() || row.empty {
                            self.skin.text(t,&row.description,0,[x+18.,top+27.],width-36.,MUTED);
                        } else { self.ink_block(m,[x+18.,top+31.,88.,11.]); }
                        top+=55.;
                    }
                    let error = if self.can_read_world() || session.slot_error.is_empty() { &session.slot_error }
                        else { "存档操作失败" };
                    self.skin.text(t,error,0,[x+14.,y+height-50.],width-140.,IVORY);
                }else{self.skin.text(t,"正式世界未连接",0,[x+14.,y+46.],width-28.,MUTED);}
                self.row(m,t,hits,[x+width-100.,y+height-42.,85.,27.],"返回",action(Command::Menu(Menu::None)),false);
            },
            Menu::Overwrite(slot)=>{
                self.row(m,t,hits,[x+15.,y+65.,140.,28.],"返回",action(Command::Menu(Menu::Save)),false);
                self.row(m,t,hits,[x+width-156.,y+65.,140.,28.],"覆盖",action(Command::ConfirmSlot(slot)),false);
            },
            Menu::Departure=>{
                let pending=self.session.is_some_and(|s|s.saving);
                for (i,(label,verb)) in [("取消","departure:cancel"),("不保存","departure:discard"),("保存并离开","departure:save")].into_iter().enumerate(){
                    self.row(m,t,hits,[x+14.+i as f32*137.,y+67.,128.,29.],label,(!pending).then_some(Action::Hud(Command::Departure(verb))),false);
                }
                if let Some(s)=self.session {
                    let error = if self.can_read_world() || s.slot_error.is_empty() { &s.slot_error } else { "存档操作失败" };
                    self.skin.text(t,error,0,[x+16.,y+107.],width-32.,IVORY);
                }
            },
            Menu::None=>(),
        }
    }
}
const CLOCK_ANGLES:[f32;4]=crate::mechanical::ANGLES;
fn clock_radius(width:f32)->f32 {116_f32.min(width*0.22)}
pub const CLOCK_SPEEDS:[u32;4]=[0,1,2,4];
pub fn clock_index(session:Option<&Session>)->usize {
    session.filter(|s|!s.paused).and_then(|s|CLOCK_SPEEDS.iter().position(|v|*v==s.speed)).unwrap_or(0)
}
pub fn clock_angle([x,y]:[f64;2],width:u32)->f32 {
    (y as f32).atan2(x as f32-width as f32).to_degrees().rem_euclid(360.).clamp(96.,174.)
}
pub fn clock_at(angle:f32)->usize {
    (((174.-angle)/26.).round() as usize).min(3)
}
pub fn clock_hit([x,y]:[f64;2],width:u32,session:Option<&Session>,display:Option<f32>)->bool {
    if session.is_none(){return false;}
    let width=width as f32;
    let [x,y]=[x as f32-width,y as f32];
    let radius=clock_radius(width);
    let factor=radius/184.;
    let distance=x.hypot(y);
    if distance<=34.*factor {return false;}
    let angle=y.atan2(x).to_degrees().rem_euclid(360.);
    if (125.*factor..=radius+3.*factor).contains(&distance)&&(82. ..=188.).contains(&angle){return true;}
    let (dy,dx)=display.unwrap_or(CLOCK_ANGLES[clock_index(session)]).to_radians().sin_cos();
    let shaft=(x*dx+y*dy).clamp(32.*factor,143.*factor);
    (x-dx*shaft).hypot(y-dy*shaft)<=7.
}
pub fn gear_hit([x,y]:[f64;2],width:u32)->bool {
    (x-f64::from(width)).hypot(y)<=f64::from(clock_radius(width as f32)*34./184.)
}
fn portrait_action_center(index:usize,height:f32)->[f32;2] {
    [12.+[23.,66.,109.][index],height-168.+[127.,135.,127.][index]]
}
pub fn portrait_action_hit(index:usize,height:f32,[x,y]:[f64;2])->bool {
    let [cx,cy]=portrait_action_center(index,height);
    (x-f64::from(cx)).hypot(y-f64::from(cy))<=19.
}
pub fn page_rect(hud:&Hud,size:[u32;2])->Option<[f32;4]>{
    let [w,h]=size.map(|v|v as f32);
    match hud.page {
        Page::Map=>None,
        Page::Finance=>{let a=(w-155.).min(900.);Some([(w-a)*0.5,106.,a,(h-150.).min(420.)])}
        Page::Character=>{let a=(w-155.).min(820.);Some([(w-a)*0.5,106.,a,(h-142.).min(460.)])}
        Page::Travel=>Some([18.,86.,(w-36.).min(650.),(h-106.).min(470.)]),
        Page::Technology=>{
            let height=if hud.tech==Tech::Chronicle{318.}else{344.};
            Some([18.,((h-height)*0.48).min(h-168.-height-10.).max(84.),(w*0.58).min(615.),height])
        }
        Page::Property=>{let a=(w-155.).min(900.);Some([(w-a)*0.5,106.,a,(h-150.).min(420.)])}
        Page::Relations=>{
            let width=(w-clock_radius(w)-36.).min(900.);
            let right=((w+width)*0.5).min(w-clock_radius(w)-12.);
            Some([right-width,106.,width,(h-144.).min(560.)])
        }
        Page::Market=>{
            let height=(h-154.).min(535.);
            Some([18.,((h-height)*0.5).max(64.),(w*0.46).min(580.),height])
        }
    }
}
pub fn menu_rect(menu:Menu,size:[u32;2],radius:f32)->[f32;4]{
    let [w,h]=size.map(|v|v as f32);
    match menu {
        Menu::MapModes=>[w*0.5-165.,h-radius-202.,330.,166.],
        Menu::System=>[w-292.,145.,280.,252.],
        Menu::Settings=>[(w-340.)*0.5,(h-290.)*0.5,340.,290.],
        Menu::Save|Menu::Load=>[(w-500.)*0.5,(h-368.)*0.5,500.,368.],
        Menu::Overwrite(_)=>[(w-430.)*0.5,(h-130.)*0.5,430.,130.],
        Menu::Departure=>[(w-440.)*0.5,(h-150.)*0.5,440.,150.],
        Menu::None=>[0.;4],
    }
}
pub fn map_modes_rect(size:[u32;2])->[f32;4] {
    menu_rect(Menu::MapModes,size,(size[0] as f32*0.056).clamp(52.,78.))
}
pub fn message_rect([w,h]:[f32;2],center:f32)->[f32;4]{
    let width=(w*0.34).min(320.);
    let height=(h-256.).clamp(200.,430.);
    [w-width,center-height*0.5,width,height]
}
