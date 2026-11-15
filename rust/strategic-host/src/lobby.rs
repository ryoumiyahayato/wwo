use crate::{formal_ui::{self,Display,Slot,IVORY,MUTED},overlay::Mesh,ui::{Action,Hit},world::{Polity,World}};
use crate::migration_status::Status;
use serde::Deserialize;
use std::sync::LazyLock;

#[derive(Deserialize)]
pub struct Lobby {
    pub ready:bool,pub selection_ready:bool,pub busy:bool,pub status:String,
    #[serde(default)] pub loading:bool,
    #[serde(default)] pub native:bool,
    pub choices:Vec<Opening>,pub slots:Vec<Slot>,
}
#[derive(Deserialize)]
pub struct Opening {pub id:String,label:String,place:String}

impl Lobby {
    pub fn opening(&self, polity: &Polity) -> Option<&Opening> {
        self.choices.iter().find(|row| row.id.strip_prefix("state:") == Some(polity.id.as_str()))
    }
}

#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum Page {#[default] Home,Selection,Load,Settings,Themes,Migration(Status,usize)}
#[derive(Clone,Copy)]
pub enum Command {Page(Page),Country(usize),Search,ClearSearch,Enter,Load(u8),Exit}

pub type Rect = [f32;4];

pub fn contains([x,y,w,h]: Rect, [px,py]: [f64;2]) -> bool {
    (f64::from(x)..=f64::from(x+w)).contains(&px)
        && (f64::from(y)..=f64::from(y+h)).contains(&py)
}

pub struct SelectionLayout {
    profile: Rect,
    traits: Rect,
    pub directory: Rect,
    primary: Rect,
    back: Rect,
}

impl SelectionLayout {
    pub fn new(size: [u32;2]) -> Self {
        let [w, h] = size.map(|n| n as f32);
        let width = Self::column_width(w);
        let left = Self::margin(w);
        let right = w - left - width;
        let top = (h * 0.115).clamp(60., 104.);
        let profile_height = (h * 0.315).clamp(188., 226.);
        let directory_top = top + profile_height + 12.;
        let action_top = h - 66.;
        let action_width = 118.;
        Self {
            profile: [right, top, width, profile_height],
            traits: [left, top, width, action_top - top + 30.],
            directory: [right, directory_top, width, action_top - directory_top - 10.],
            primary: [right + width - action_width, action_top, action_width, 30.],
            back: [left, 18., 36., 34.],
        }
    }

    pub fn contains(&self, point: [f64;2]) -> bool {
        [self.profile, self.traits, self.directory, self.primary, self.back]
            .into_iter().any(|area| contains(area, point))
    }

    pub fn globe_mpp(size: [u32;2]) -> f64 {
        let width = size[0] as f32;
        let center_width = width - (Self::margin(width) + Self::column_width(width)) * 2.;
        let diameter = (size[1] as f32 * 0.61).min(center_width - 24.).max(1.);
        2. * crate::camera::EARTH / f64::from(diameter)
    }

    fn column_width(width: f32) -> f32 { (width * 0.28).min(350.) }

    fn margin(width: f32) -> f32 { (width * 0.024).clamp(20., 32.) }
}

#[derive(Deserialize)]
struct HistoricalProfile {
    entity_id: String,
    #[serde(default)]
    opening_brief_zh: String,
    #[serde(default)]
    brief_zh: String,
}

static COUNTRY_PROFILES: LazyLock<Vec<HistoricalProfile>> = LazyLock::new(|| {
    #[derive(Deserialize)]
    struct Profiles { profiles: Vec<HistoricalProfile> }
    let data = include_str!("../../../data/world_map/historical/major_state_profiles_1900.json");
    serde_json::from_str::<Profiles>(data)
        .expect("invalid 1900 historical state profiles").profiles
});

fn polity_label<'a>(p: &'a Polity, opening: Option<&'a Opening>, english: bool) -> &'a str {
    if english || p.name_zh.is_empty() {
        &p.name
    } else {
        opening.map_or(&p.name_zh, |row| &row.label)
    }
}

#[derive(Default)]
pub struct Directory {
    pub search_active: bool,
    pub query: String,
    pub drag: Option<f32>,
    offset: f32,
    entries: Vec<usize>,
}

impl Directory {
    pub fn filter(&mut self, world: &World, lobby: Option<&Lobby>, date: &str, english: bool) {
        let query = self.query.trim().to_lowercase();
        let mut items: Vec<_> = world.polities.iter().enumerate().filter_map(|(index, polity)| {
            if !polity.active(date) { return None; }
            let opening = lobby.and_then(|state| state.opening(polity));
            let label = polity_label(polity, opening, english).to_lowercase();
            [label.as_str(), &polity.name.to_lowercase(), &polity.name_zh]
                .iter().any(|name|name.contains(&query))
                .then_some((opening.is_none(), label, index))
        }).collect();
        items.sort_unstable();
        self.entries = items.into_iter().map(|(_,_,index)| index).collect();
        self.offset = 0.;
    }

    pub fn list(&self, size: [u32;2]) -> Rect {
        let [x,y,w,h] = SelectionLayout::new(size).directory;
        let top = if size[1] < 560 { 62. } else { 78. };
        let row = Self::row_height(size);
        let height = ((h - top - 8.).max(0.) / row).floor() * row;
        [x+12.,y+top,w-24.,height]
    }

    fn row_height(size: [u32;2]) -> f32 { if size[1] < 560 { 26. } else { 30. } }

    fn visible(&self, size: [u32;2]) -> usize {
        (self.list(size)[3] / Self::row_height(size)) as usize
    }

    fn limit(&self, size: [u32;2]) -> f32 {
        self.entries.len().saturating_sub(self.visible(size)) as f32
    }

    pub fn reveal(&mut self, size: [u32;2], selected: usize) {
        let Some(index) = self.entries.iter().position(|&value|value == selected) else {return;};
        let visible = self.visible(size);
        let start = self.offset.floor() as usize;
        if index < start {
            self.offset = index as f32;
        } else if index >= start + visible {
            self.offset = (index + 1 - visible) as f32;
        }
        self.offset = self.offset.min(self.limit(size));
    }

    pub fn scroll(&mut self, size: [u32;2], steps: f32) {
        self.offset = (self.offset - steps * 3.).clamp(0., self.limit(size));
    }

    fn scrollbar(&self, size: [u32;2]) -> Option<(Rect, Rect)> {
        let limit = self.limit(size);
        if limit == 0. { return None; }
        let [x,y,w,h] = self.list(size);
        if h == 0. { return None; }
        let height = (h * self.visible(size) as f32 / self.entries.len() as f32).max(14.);
        let top = y + self.offset.min(limit) / limit * (h - height);
        Some(([x+w-13., y, 13.,h], [x+w-13.,top,13.,height]))
    }

    pub fn grab(&mut self, size: [u32;2], point: [f64;2]) -> bool {
        let Some((track,thumb)) = self.scrollbar(size) else { return false; };
        if !contains(track, point) { return false; }
        self.drag = Some(if contains(thumb, point) {point[1] as f32 - thumb[1]} else {thumb[3] * 0.5});
        self.slide(size, point[1]);
        true
    }

    pub fn slide(&mut self, size: [u32;2], y: f64) {
        if let (Some(grab), Some((track,thumb))) = (self.drag,self.scrollbar(size)) {
            let position = ((y as f32-grab-track[1]) / (track[3]-thumb[3])).clamp(0.,1.);
            self.offset = position * self.limit(size);
        }
    }
}

impl Display<'_> {
    pub fn loading(&self, status:&str, seconds:f32) -> crate::ui::Layers {
        use crate::ui::Ink;
        let [w,h]=self.size.map(|n|n as f32);
        let mut painting=Mesh::default();let mut shade=Mesh::default();let mut label=Mesh::default();let mut strip=Mesh::default();
        let phase=seconds*std::f32::consts::TAU/36.;
        self.painting(&mut painting,0.964+0.014*phase.cos(),[0.0096*phase.sin(),0.00456*(2.*phase).sin()]);
        shade.rect(0.,0.,w,h,[3,5,5,153]);
        self.skin.text(&mut label,status,0,[48.,h-73.],w-96.,IVORY);
        strip.image([48.,h-39.,w-96.,3.],[0.,0.,1.,1.],[255;4]);
        [(Mesh::default(),Ink::Solid),(Mesh::default(),Ink::Text),(Mesh::default(),Ink::Instrument),(Mesh::default(),Ink::ClockGears),
         (Mesh::default(),Ink::HudArt),(Mesh::default(),Ink::HudText),
         (painting,Ink::MenuArt),(shade,Ink::Solid),(strip,Ink::Loading),(Mesh::default(),Ink::Flag),
         (Mesh::default(),Ink::HudArt),(Mesh::default(),Ink::Solid),(label,Ink::HudText)]
    }

    fn painting(&self, mesh:&mut Mesh, scale:f32, drift:[f32;2]) {
        let [w,h]=self.size.map(|n|n as f32);
        let span=if w/h>1.6 {[1.,1.6*h/w]} else {[w/h/1.6,1.]};
        let [u,v]=[0.5+drift[0],0.5+drift[1]];
        let [x,y]=span.map(|n|n*scale*0.5);
        mesh.image([0.,0.,w,h],[u-x,v-y,u+x,v+y],[255;4]);
    }

    pub fn lobby(&self,world:&World,state:Option<&Lobby>,page:Page,selection:usize,waiting:bool,directory:&Directory)
        -> (crate::ui::Layers,Vec<Hit>)
    {
        use crate::ui::Ink;
        let [w,h]=self.size.map(|n|n as f32);
        let mut background=Mesh::default();
        let mut panels=Mesh::default();
        let mut art=Mesh::default();
        let mut text=Mesh::default();
        let mut flags=Mesh::default();
        let mut hits=Vec::new();
        if page!=Page::Selection {
            self.painting(&mut background,1.,[0.;2]);
            panels.rect(0.,0.,w,h,[3,5,5,75]);
        }
        let row=|label,page| (label,Some(action(Command::Page(page))));
        let busy=waiting||state.is_some_and(|s|s.busy);
        let ready=state.is_some_and(|s|s.ready);
        match page {
            Page::Home=>{
                let x=48.;let y=(h-388.)*0.5;let width=350.;
                formal_ui::panel(&mut panels,[x,y,width,388.],[6,14,23,241]);
                self.skin.text(&mut text,"1900",2,[x+24.,y+27.],width-48.,IVORY);
                let rows=[("开始",ready.then_some(action(Command::Page(Page::Selection)))),("加载",ready.then_some(action(Command::Page(Page::Load)))),
                    row("主题管理",Page::Themes),row("设置",Page::Settings),
                    row("R68 迁移状态",Page::Migration(Status::Partial,0)),("退出",Some(action(Command::Exit)))];
                for (i,(label,command)) in rows.into_iter().enumerate(){
                    self.row(&mut panels,&mut text,&mut hits,[x+24.,y+79.+i as f32*40.,width-48.,32.],label,command,false);
                }
                let runtime=if state.is_some_and(|s|s.native) {"Rust 原生世界"} else {"R68 规则兼容 · Rust 候选"};
                self.skin.text(&mut text,runtime,0,[x+24.,y+342.],width-48.,MUTED);
            }
            Page::Selection=>{
                let layout = SelectionLayout::new(self.size);
                let [x,y,width,height] = layout.profile;
                formal_ui::panel(&mut panels,layout.profile,[12,22,31,249]);
                self.skin.sprite(&mut art,"crest",[x+width*0.5-80.,y-41.,160.,45.]);
                let heading=self.skin.choose("国家档案 / 1900","Country profile / 1900");
                self.skin.text(&mut text,heading,1,[x+18.,y+13.],width-36.,IVORY);
                let selected=world.polities.get(selection);
                let opening=state.and_then(|s|selected.and_then(|p|s.opening(p)));
                if let Some(p)=selected {
                    let label=polity_label(p, opening, self.skin.english());
                    let name_left=if self.flags.is_some(){82.}else{18.};
                    self.skin.paragraph(&mut text,label,1,[x+name_left,y+40.,width-name_left-18.,52.],IVORY,1.);
                    if let Some(slot)=self.flags{flags.flag([x+18.,y+46.,52.,35.],slot);}
                    let status = opening.map_or_else(|| "仅查看".to_owned(),
                        |row| format!("{} · 居民 · 未就业", row.place));
                    self.skin.text(&mut text,&status,0,[x+18.,y+91.],width-36.,MUTED);
                    let brief = COUNTRY_PROFILES.iter().find(|row| row.entity_id == p.id)
                        .map(|row| if row.opening_brief_zh.is_empty() { &row.brief_zh } else { &row.opening_brief_zh })
                        .map(String::as_str).filter(|brief| !brief.is_empty());
                    let scale = (width / 300.).clamp(0.8, 1.);
                    self.skin.paragraph(&mut text,brief.unwrap_or("暂无历史简介"),0,
                        [x+18.,y+112.,width-36.,height-122.],IVORY,scale);
                }
                let [traits_x, traits_y, traits_width, _] = layout.traits;
                formal_ui::panel(&mut panels,layout.traits,[12,22,31,249]);
                self.skin.text(&mut text,"人物特质",1,[traits_x+18.,traits_y+13.],traits_width-36.,IVORY);
                let can_enter=opening.is_some()&&state.is_some_and(|s|s.selection_ready)&&!busy;
                self.row(&mut panels,&mut text,&mut hits,layout.primary,"",
                    can_enter.then_some(action(Command::Enter)),can_enter);
                let [button_x,button_y,button_width,_]=layout.primary;
                let label=self.skin.choose("进入世界","Enter world");
                let label_width=self.skin.width(label,0);
                self.skin.text(&mut text,label,0,[button_x+(button_width-label_width)*0.5,button_y+5.],
                    button_width,if can_enter{IVORY}else{MUTED});
                self.row(&mut panels,&mut text,&mut hits,layout.back,"",
                    (!busy).then_some(action(Command::Page(Page::Home))),!busy&&contains(layout.back,self.cursor));
                let [back_x,back_y,_,_]=layout.back;
                let arrow=[back_x+10.,back_y+17.];
                let color=if busy{MUTED}else{IVORY};
                panels.line(arrow,[back_x+26.,back_y+17.],1.6,color);
                panels.line(arrow,[back_x+16.,back_y+11.],1.6,color);
                panels.line(arrow,[back_x+16.,back_y+23.],1.6,color);
                self.country_directory(&mut panels,&mut text,&mut hits,world,state,directory,selection,busy);
            }
            Page::Load=>{
                let width=500.;let x=(w-width)*0.5;let y=(h-400.)*0.5;
                formal_ui::panel(&mut panels,[x,y,width,400.],[6,14,23,247]);
                self.skin.text(&mut text,"加载",1,[x+22.,y+15.],width-44.,IVORY);
                if let Some(s)=state {
                    for (i,slot) in s.slots.iter().enumerate(){
                        let top=y+52.+i as f32*55.;
                        self.row(&mut panels,&mut text,&mut hits,[x+20.,top,width-40.,28.],&slot.name,
                            (slot.can_read&&!busy).then_some(action(Command::Load(slot.slot))),false);
                        self.skin.text(&mut text,&slot.description,0,[x+23.,top+29.],width-46.,MUTED);
                    }
                }
                self.row(&mut panels,&mut text,&mut hits,[x+width-110.,y+350.,90.,30.],"返回",
                    (!busy).then_some(action(Command::Page(Page::Home))),false);
            }
            Page::Settings|Page::Themes=>{
                let height=if page==Page::Settings{290.}else{218.};
                let width=365.;let x=(w-width)*0.5;let y=(h-height)*0.5;
                formal_ui::panel(&mut panels,[x,y,width,height],[6,14,23,247]);
                self.skin.text(&mut text,if page==Page::Settings{"设置"}else{"主题管理"},1,[x+22.,y+15.],width-44.,IVORY);
                if page==Page::Settings {
                    self.settings(&mut panels,&mut text,&mut hits,[x,y,width,height],formal_ui::Command::Lobby(Command::Page(Page::Home)),true);
                }else{
                    self.skin.text(&mut text,"1900 · 当前使用 R68 原主题",0,[x+24.,y+76.],width-48.,IVORY);
                    self.row(&mut panels,&mut text,&mut hits,[x+22.,y+158.,width-44.,31.],"返回",
                    Some(action(Command::Page(Page::Home))),false);
                }
            }
            Page::Migration(status,page)=>self.migration_status(&mut panels,&mut text,&mut hits,status,page,state.is_some_and(|s|s.native)),
        }
        if !matches!(page,Page::Migration(_, _)) {
            let status=state.map(|s|s.status.as_str()).filter(|s|!s.is_empty()).unwrap_or(if busy{"正在进入世界。"}else if !ready{"正在连接 R68 正式规则。"}else{""});
            let status=if self.feedback.is_empty(){status}else{self.feedback};
            if !status.is_empty(){
                formal_ui::panel(&mut panels,[(w-550.)*0.5,h-55.,550.,41.],[6,14,23,245]);
                self.skin.text(&mut text,status,0,[(w-515.)*0.5,h-45.],515.,IVORY);
            }
        }
        ([(Mesh::default(),Ink::Solid),(Mesh::default(),Ink::Text),(Mesh::default(),Ink::Instrument),(Mesh::default(),Ink::ClockGears),
          (Mesh::default(),Ink::HudArt),(Mesh::default(),Ink::HudText),
          (background,Ink::MenuArt),(panels,Ink::Solid),(Mesh::default(),Ink::Text),(flags,Ink::Flag),(art,Ink::HudArt),(Mesh::default(),Ink::Solid),(text,Ink::HudText)],hits)
    }

    fn country_directory(&self,panels:&mut Mesh,text:&mut Mesh,hits:&mut Vec<Hit>,world:&World,
        state:Option<&Lobby>,directory:&Directory,selection:usize,busy:bool)
    {
        let area = SelectionLayout::new(self.size).directory;
        let [x,y,w,_] = area;
        let compact = self.size[1] < 560;
        let (heading_font, search_top, search_height) = if compact { (0, 28., 28.) } else { (1, 40., 30.) };
        formal_ui::panel(panels,area,[12,22,31,249]);
        self.skin.text(text,"国家目录",heading_font,[x+18.,y+6.],w-36.,IVORY);
        let hint=if directory.query.is_empty() {"搜索国家或地区"} else { &directory.query };
        let search_width=if directory.query.is_empty(){w-24.}else{w-74.};
        self.row(panels,text,hits,[x+12.,y+search_top,search_width,search_height],hint,
            (!busy).then_some(action(Command::Search)),directory.search_active);
        if !directory.query.is_empty(){
            self.row(panels,text,hits,[x+w-56.,y+search_top,44.,search_height],"清除",
                (!busy).then_some(action(Command::ClearSearch)),false);
        }
        let [left,top,width,_]=directory.list(self.size);
        let start=directory.offset.min(directory.limit(self.size)).floor() as usize;
        let row_height = Directory::row_height(self.size);
        for (row,&index) in directory.entries.iter().skip(start).take(directory.visible(self.size)).enumerate() {
            let polity=&world.polities[index];
            let opening=state.and_then(|s|s.opening(polity));
            let title=polity_label(polity,opening,self.skin.english());
            let row_y=top+row as f32*row_height;
            let area=[left,row_y,width-19.,row_height-3.];
            self.row(panels,text,hits,area,"",(!busy).then_some(action(Command::Country(index))),index==selection);
            self.skin.text(text,title,0,[left+9.,row_y+3.],width-115.,IVORY);
            let badge=if opening.is_some() {"可开局"} else {"仅查看"};
            self.skin.text(text,badge,0,[left+width-94.,row_y+3.],54.,if opening.is_some(){IVORY}else{MUTED});
            if index==selection {
                let x=left+width-35.;
                panels.line([x,row_y+15.],[x+4.,row_y+19.],2.,[230,202,147,255]);
                panels.line([x+4.,row_y+19.],[x+12.,row_y+10.],2.,[230,202,147,255]);
            }
        }
        if directory.entries.is_empty() {
            self.skin.text(text,"没有匹配的国家",0,[left+9.,top+7.],width-18.,MUTED);
        }
        if let Some((track,thumb))=directory.scrollbar(self.size) {
            panels.rect(track[0]+5.,track[1],3.,track[3],[85,75,53,255]);
            panels.rect(thumb[0]+3.,thumb[1],7.,thumb[3],
                if directory.drag.is_some() {[230,202,147,255]} else {[174,146,100,255]});
        }
    }
}

pub(crate) fn action(command:Command)->Action {Action::Hud(formal_ui::Command::Lobby(command))}
