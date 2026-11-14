use crate::{formal_ui::{self,Display,Slot,IVORY,MUTED},overlay::Mesh,ui::{Action,Hit},world::{Polity,World}};
use crate::migration_status::Status;
use serde::Deserialize;

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

const ROW: f32 = 34.;
pub type Rect = [f32;4];

pub fn contains([x,y,w,h]: Rect, [px,py]: [f64;2]) -> bool {
    (f64::from(x)..=f64::from(x+w)).contains(&px)
        && (f64::from(y)..=f64::from(y+h)).contains(&py)
}

pub fn profile([w,h]:[u32;2]) -> Rect {
    let width=(w as f32*0.43).min(430.);
    [w as f32-width-32.,(h as f32*0.14).max(58.),width,174.]
}

pub fn primary(size:[u32;2]) -> Rect {
    let [x,_,w,_]=profile(size);
    [x,size[1] as f32*0.72,w,36.]
}

pub fn back([w,h]:[u32;2]) -> Rect {
    [w as f32-168.,h as f32-59.,136.,31.]
}

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

    pub fn panel([w,h]:[u32;2]) -> Rect {
        let max_height = (h as f32 - 78.).min(530.);
        let rows = ((max_height - 100.) / ROW).floor();
        let height = 100. + rows * ROW;
        let width=(w as f32 * 0.35).min(340.);
        [24., (h as f32 - height) * 0.5, width,height]
    }

    pub fn list(&self, size: [u32;2]) -> Rect {
        let [x,y,w,h] = Self::panel(size);
        [x+12.,y+86.,w-24.,h-100.]
    }

    fn visible(&self, size: [u32;2]) -> usize {
        (self.list(size)[3] / ROW) as usize
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
        let height = (h * self.visible(size) as f32 / self.entries.len() as f32).max(22.);
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
    pub fn loading(&self, status:&str, seconds:f32) -> [(Mesh,crate::ui::Ink);11] {
        use crate::ui::Ink;
        let [w,h]=self.size.map(|n|n as f32);
        let mut painting=Mesh::default();let mut shade=Mesh::default();let mut label=Mesh::default();let mut strip=Mesh::default();
        let phase=seconds*std::f32::consts::TAU/36.;
        self.painting(&mut painting,0.964+0.014*phase.cos(),[0.0096*phase.sin(),0.00456*(2.*phase).sin()]);
        shade.rect(0.,0.,w,h,[3,5,5,153]);
        self.skin.text(&mut label,status,0,[48.,h-73.],w-96.,IVORY);
        strip.image([48.,h-39.,w-96.,3.],[0.,0.,1.,1.],[255;4]);
        [(Mesh::default(),Ink::Solid),(Mesh::default(),Ink::Text),(Mesh::default(),Ink::Instrument),(Mesh::default(),Ink::ClockGears),
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
        -> ([(Mesh,crate::ui::Ink);11],Vec<Hit>)
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
                let [x,y,width,height]=profile(self.size);
                formal_ui::panel(&mut panels,[x,y,width,height],[12,22,31,241]);
                self.skin.sprite(&mut art,"crest",[x+width*0.5-97.,y-50.,194.,55.]);
                self.skin.text(&mut text,"国家档案  /  1900",1,[x+22.,y+15.],width-44.,IVORY);
                let selected=world.polities.get(selection);
                let opening=state.and_then(|s|selected.and_then(|p|s.opening(p)));
                if let Some(p)=selected {
                    let label=polity_label(p, opening, self.skin.english());
                    self.skin.text(&mut text,label,1,[x+103.,y+73.],width-125.,IVORY);
                    if let Some(slot)=self.flags{flags.flag([x+22.,y+63.,68.,45.],slot);}
                }
                if let Some(opening)=opening {
                    let identity=format!("{} · 居民 · 未就业",opening.place);
                    self.skin.text(&mut text,"开局身份",0,[x+22.,y+118.],width-44.,MUTED);
                    self.skin.text(&mut text,&identity,0,[x+22.,y+141.],width-44.,IVORY);
                } else {
                    self.skin.text(&mut text,"仅可查看历史资料",0,[x+22.,y+132.],width-44.,MUTED);
                }
                let can_enter=opening.is_some()&&state.is_some_and(|s|s.selection_ready)&&!busy;
                self.row(&mut panels,&mut text,&mut hits,primary(self.size),"进入世界",
                    can_enter.then_some(action(Command::Enter)),can_enter);
                self.row(&mut panels,&mut text,&mut hits,back(self.size),"返回主菜单",
                    (!busy).then_some(action(Command::Page(Page::Home))),false);
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
          (background,Ink::MenuArt),(panels,Ink::Solid),(Mesh::default(),Ink::Text),(flags,Ink::Flag),(art,Ink::HudArt),(Mesh::default(),Ink::Solid),(text,Ink::HudText)],hits)
    }

    fn country_directory(&self,panels:&mut Mesh,text:&mut Mesh,hits:&mut Vec<Hit>,world:&World,
        state:Option<&Lobby>,directory:&Directory,selection:usize,busy:bool)
    {
        let [x,y,w,h]=Directory::panel(self.size);
        formal_ui::panel(panels,[x,y,w,h],[12,22,31,249]);
        self.skin.text(text,"国家目录",1,[x+20.,y+12.],w-40.,IVORY);
        let hint=if directory.query.is_empty() {"搜索国家或地区"} else { &directory.query };
        let search_width=if directory.query.is_empty(){w-24.}else{w-74.};
        self.row(panels,text,hits,[x+12.,y+46.,search_width,30.],hint,
            (!busy).then_some(action(Command::Search)),directory.search_active);
        if !directory.query.is_empty(){
            self.row(panels,text,hits,[x+w-56.,y+46.,44.,30.],"清除",
                (!busy).then_some(action(Command::ClearSearch)),false);
        }
        let [left,top,width,_]=directory.list(self.size);
        let start=directory.offset.min(directory.limit(self.size)).floor() as usize;
        for (row,&index) in directory.entries.iter().skip(start).take(directory.visible(self.size)).enumerate() {
            let polity=&world.polities[index];
            let opening=state.and_then(|s|s.opening(polity));
            let title=polity_label(polity,opening,self.skin.english());
            let row_y=top+row as f32*ROW;
            let area=[left,row_y,width-19.,29.];
            self.row(panels,text,hits,area,"",(!busy).then_some(action(Command::Country(index))),index==selection);
            self.skin.text(text,title,0,[left+9.,row_y+6.],width-115.,IVORY);
            let badge=if opening.is_some() {"可开局"} else {"仅查看"};
            self.skin.text(text,badge,0,[left+width-94.,row_y+6.],54.,if opening.is_some(){IVORY}else{MUTED});
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
