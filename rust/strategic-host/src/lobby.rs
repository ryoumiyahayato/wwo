use crate::{formal_ui::{self,Display,Slot,IVORY,MUTED},overlay::Mesh,ui::{Action,Hit},world::{Polity,World}};
use crate::migration_status::Status;
use serde::Deserialize;
use std::{collections::BTreeMap, sync::LazyLock, time::Instant};
use crate::{camera::Camera, politics::PoliticalVisuals};
use wwo_map_lab::formal_bootstrap::OpeningSite;

#[derive(Deserialize)]
pub struct Lobby {
    pub ready:bool,pub selection_ready:bool,pub busy:bool,pub status:String,
    #[serde(default)] pub loading:bool,
    #[serde(default)] pub native:bool,
    pub choices:Vec<Opening>,pub slots:Vec<Slot>,
}
#[derive(Deserialize)]
pub struct Opening {
    pub id: String,
    pub label: String,
    #[serde(default)] pub language: Option<wwo_character_core::Language>,
    #[serde(default)] pub sites: Vec<OpeningSite>,
    #[serde(default)] pub native: bool,
}

impl Lobby {
    pub fn can_open(&self, opening: &Opening) -> bool {
        !self.native || opening.sites.iter().any(|site| site.unavailable.is_none())
    }

    pub fn opening(&self, polity: &Polity) -> Option<&Opening> {
        self.choices.iter().find(|row| row.id.strip_prefix("state:") == Some(polity.id.as_str()))
    }
}

#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum Page {#[default] Home,Selection,Cloud,Prologue,Load,Settings,Themes,Migration(Status,usize)}
#[derive(Clone,Copy)]
pub enum Command {
    Page(Page), Country(usize), Back, Motion, Drawer, Brief, Area(usize, usize), Site(usize),
    Up, Search, ClearSearch, Enter, SkipCloud, PrologueChoice(usize), PrologueHealth(usize), PrologueNext, PrologueBack, Load(u8), Exit,
}

pub type Rect = [f32;4];

pub fn contains([x,y,w,h]: Rect, [px,py]: [f64;2]) -> bool {
    (f64::from(x)..=f64::from(x+w)).contains(&px)
        && (f64::from(y)..=f64::from(y+h)).contains(&py)
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum SelectionStage {
    #[default]
    Globe,
    Directory,
    Profile,
}

pub struct Selection {
    pub stage: SelectionStage,
    pub drawer: bool,
    pub brief: bool,
    pub brief_scroll: usize,
    pub path: Vec<String>,
    pub site: Option<usize>,
    pub offset: usize,
    pub motion: bool,
    pub last_input: Instant,
    pub last_animation: Instant,
    pub shift: Option<(Instant, f64, f64)>,
    pub cloud: Option<Instant>,
    pub arrival_cloud: Option<Instant>,
    pub previous_country: Option<(usize, Instant)>,
}

impl Default for Selection {
    fn default() -> Self {
        let now = Instant::now();
        Self {
            stage: SelectionStage::Globe, drawer: false, brief: false, brief_scroll: 0, path: Vec::new(),
            site: None, offset: 0, motion: true, last_input: now, last_animation: now,
            shift: None, cloud: None, arrival_cloud: None, previous_country: None,
        }
    }
}

impl Selection {
    fn rects(&self, size: [u32; 2]) -> (Rect, Rect) {
        let [w, h] = size.map(|value| value as f32);
        let compact = w < 790. || h < 540.;
        let width = (w * 0.36).clamp(290., 410.).min((w - 24.).max(160.));
        let card_height: f32 = if self.brief { 339. } else { 236. };
        let right = w - width - 12.;
        let card = [right, 14., width, card_height.min((h - 72.).max(162.))];
        let drawer = if compact || card[3] + 230. > h {
            let width = (w - 24.).min(530.);
            let available = h - card[1] - card[3] - 20.;
            let height = (h * 0.49).min(available).max(100.);
            [(w - width) * 0.5, h - height - 10., width, height]
        } else {
            [right, card[1] + card[3] + 9., width, (h - card[3] - 35.).min(348.)]
        };
        (card, drawer)
    }

    pub fn drawer_rect(&self, size: [u32; 2]) -> Rect { self.rects(size).1 }

    pub fn brief_rect(&self, size: [u32; 2]) -> Rect {
        let [x, y, w, h] = self.rects(size).0;
        [x + 17., y + 112., w - 34., (h - 209.).max(19.)]
    }

    pub fn contains(&self, size: [u32; 2], point: [f64; 2]) -> bool {
        match self.stage {
            SelectionStage::Globe => false,
            SelectionStage::Directory => contains(directory_rect(size), point),
            SelectionStage::Profile => {
                let (card, drawer) = self.rects(size);
                contains(card, point) || self.drawer && contains(drawer, point)
            }
        }
    }

    pub fn reset_place(&mut self) {
        self.drawer = false;
        self.brief = false;
        self.brief_scroll = 0;
        self.path.clear();
        self.site = None;
        self.offset = 0;
    }

    pub fn path_label(&self, opening: &Opening) -> String {
        let mut names = vec![opening.label.as_str()];
        if let Some(site) = self.site.and_then(|index| opening.sites.get(index)) {
            names.extend(site.path.iter().map(|area| area.label.as_str()));
            names.push(&site.label);
        }
        names.join(" / ")
    }

    pub fn max_scroll(&self, opening: &Opening, query: &str, size: [u32; 2]) -> usize {
        let visible = ((self.drawer_rect(size)[3] - 91.) / 30.).max(1.) as usize;
        self.rows(opening, query).len().saturating_sub(visible)
    }

    fn rows<'a>(&self, opening: &'a Opening, query: &str) -> Vec<(usize, Option<usize>, &'a str)> {
        let query = query.trim().to_lowercase();
        let mut areas = BTreeMap::new();
        let mut sites = Vec::new();
        for (index, site) in opening.sites.iter().enumerate() {
            if !site.path.iter().map(|area| &area.id).take(self.path.len()).eq(self.path.iter()) { continue; }
            if query.is_empty() {
                if let Some(area) = site.path.get(self.path.len()) {
                    areas.entry(&area.label).or_insert((index, Some(self.path.len()), area.label.as_str()));
                    continue;
                }
            } else if !site.label.to_lowercase().contains(&query) && !site.id.contains(&query) {
                for (depth, area) in site.path.iter().enumerate().skip(self.path.len()) {
                    if area.label.to_lowercase().contains(&query) {
                        areas.entry(&area.label).or_insert((index, Some(depth), area.label.as_str()));
                    }
                }
                continue;
            }
            sites.push((index, None, site.label.as_str()));
        }
        areas.into_values().chain(sites).collect()
    }
}

pub fn directory_rect([width, height]: [u32; 2]) -> Rect {
    let (w, h) = (width as f32, height as f32);
    let width = (w * 0.245).clamp(216., 378.).min(w - 24.);
    [w - width - 12., 14., width, (h - 29.).max(85.)]
}

pub fn globe_mpp(size: [u32; 2]) -> f64 { Camera::overview(size) }

pub struct SelectionView<'a> {
    pub navigation: &'a Selection,
    pub camera: &'a Camera,
    pub visuals: &'a PoliticalVisuals,
}

#[derive(Deserialize)]
struct HistoricalProfile {
    entity_id: String,
    #[serde(default)] aliases: Vec<String>,
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
    if english {
        match p.id.as_str() {
            "country_fra" => "French Third Republic",
            "british_isles_1900" => "United Kingdom of Great Britain and Ireland",
            "german_empire" => "German Empire",
            "russian_empire" => "Russian Empire",
            "qing_empire" => "Great Qing",
            "empire_of_japan" => "Empire of Japan",
            _ if p.name_zh.is_empty() => &p.name,
            _ => opening.map_or(&p.name_zh, |row| &row.label),
        }
    } else {
        opening.map_or(if p.name_zh.is_empty() { &p.name } else { &p.name_zh }, |row| &row.label)
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
            let aliases = COUNTRY_PROFILES.iter().find(|profile| profile.entity_id == polity.id);
            let short = match polity.id.as_str() {
                "country_fra" => "法国 france",
                "british_isles_1900" => "英国 england britain uk",
                "german_empire" => "德国 germany",
                "russian_empire" => "俄国 俄罗斯 russia",
                "qing_empire" => "中国 清朝 china",
                "empire_of_japan" => "日本 japan",
                _ => "",
            };
            let matched = [label.as_str(), &polity.name.to_lowercase(), &polity.name_zh, short]
                .iter().any(|name| name.contains(&query))
                || aliases.is_some_and(|profile| profile.aliases.iter().any(|alias| alias.to_lowercase().contains(&query)));
            let available = opening.is_some_and(|row| lobby.is_some_and(|state| state.can_open(row)));
            matched.then_some((!available, label, index))
        }).collect();
        items.sort_unstable();
        self.entries = items.into_iter().map(|(_,_,index)| index).collect();
        self.offset = 0.;
    }

    pub fn list(&self, size: [u32;2]) -> Rect {
        let [x,y,w,h] = directory_rect(size);
        let top = if size[1] < 560 { 62. } else { 78. };
        let row = Self::row_height(size);
        let height = ((h - top - 8.).max(0.) / row).floor() * row;
        [x+12.,y+top,w-24.,height]
    }

    fn row_height(_size: [u32;2]) -> f32 { 53. }

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

    pub fn lobby(&self,world:&World,state:Option<&Lobby>,page:Page,selection:usize,waiting:bool,directory:&Directory,draft:Option<&crate::prologue_ui::Draft>, view: SelectionView<'_>)
        -> (crate::ui::Layers,Vec<Hit>)
    {
        use crate::ui::Ink;
        let [w,h]=self.size.map(|n|n as f32);
        let mut background=Mesh::default();
        let mut panels=Mesh::default();
        let art=Mesh::default();
        let mut scenes=Mesh::default();
        let mut text=Mesh::default();
        let mut flags=Mesh::default();
        let mut hits=Vec::new();
        if !matches!(page, Page::Selection | Page::Cloud | Page::Prologue) {
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
            Page::Selection => {
                let navigation = view.navigation;
                let back = [12., 14., 67., 30.];
                self.row(&mut panels, &mut text, &mut hits, back, self.skin.choose("返回", "Back"),
                    (!busy).then_some(action(Command::Back)), false);
                let motion = self.skin.choose(
                    if navigation.motion { "减少动效" } else { "恢复动效" },
                    if navigation.motion { "Reduce motion" } else { "Enable motion" },
                );
                self.row(&mut panels, &mut text, &mut hits, [12., h - 44., 124., 30.], motion,
                    Some(action(Command::Motion)), !navigation.motion);
                match navigation.stage {
                    SelectionStage::Globe => {
                        let hint = self.skin.choose("点击地球，选择国家", "Click the globe to choose a country");
                        let width = self.skin.width(hint, 0);
                        self.skin.text(&mut text, hint, 0, [(w - width) * 0.5, h - 48.], width + 2., IVORY);
                    }
                    SelectionStage::Directory => self.country_directory(&mut panels, &mut text, &mut flags,
                        &mut hits, world, state, directory, view.visuals, busy),
                    SelectionStage::Profile => {
                        if let Some(p) = world.polities.get(selection) {
                            self.opening_card(&mut panels, &mut text, &mut flags, &mut hits,
                                p, state.and_then(|s| s.opening(p)), directory, &view, busy);
                        }
                    }
                }
            }
            Page::Cloud => {
                let phase = view.navigation.cloud.map_or(1., |at| (at.elapsed().as_secs_f32() / 1.8).min(1.));
                cloud_cover(&mut panels, self.size, phase);
                self.row(&mut panels, &mut text, &mut hits, [w - 135., h - 55., 112., 31.],
                    self.skin.choose("跳过", "Skip"), Some(action(Command::SkipCloud)), false);
            }
            Page::Prologue => {
                if let Some((draft, opening)) = draft.and_then(|draft| {
                    world.polities.get(draft.country).and_then(|polity| state?.opening(polity)).map(|opening| (draft, opening))
                }) {
                    self.draw_prologue(&mut scenes, &mut panels, &mut text, &mut hits, draft, opening, view.navigation);
                }
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
          (background,Ink::MenuArt),(panels,Ink::Solid),(scenes,Ink::PrologueArt),(flags,Ink::Flag),(art,Ink::HudArt),(Mesh::default(),Ink::Solid),(text,Ink::HudText)],hits)
    }

    fn opening_card(
        &self, panels: &mut Mesh, text: &mut Mesh, flags: &mut Mesh, hits: &mut Vec<Hit>,
        polity: &Polity, opening: Option<&Opening>, directory: &Directory, view: &SelectionView<'_>, busy: bool,
    ) {
        let nav = view.navigation;
        let (card, drawer) = nav.rects(self.size);
        let [x, y, w, h] = card;
        if let Some(opening) = opening {
            let drawer_open = nav.drawer;
            let mark_limit = view.camera.mpp * 9.;
            if mark_limit < 100_000. {
                let mut painted = Vec::<[f64; 2]>::new();
                for (i, site) in opening.sites.iter().enumerate() {
                    if !site.path.iter().map(|area| &area.id).take(nav.path.len()).eq(nav.path.iter()) { continue; }
                    let Some(point) = view.camera.project(site.coordinates, self.size) else { continue; };
                    if nav.contains(self.size, point) || point[0] < 0. || point[1] < 0.
                        || point[0] >= f64::from(self.size[0]) || point[1] >= f64::from(self.size[1]) { continue; }
                    if nav.site != Some(i) && painted.iter().any(|prior| (point[0] - prior[0]).hypot(point[1] - prior[1]) < 12.) { continue; }
                    painted.push(point);
                    let [px, py] = point.map(|value| value as f32);
                    let area = [px - 6., py - 6., 12., 12.];
                    let enabled = site.unavailable.is_none();
                    let color = if nav.site == Some(i) { IVORY } else if enabled { formal_ui::BRASS } else { MUTED };
                    panels.shape(&[[px, py - 4.], [px + 4., py], [px, py + 4.], [px - 4., py]], color);
                    if enabled && !busy { hits.push(Hit { area, action: action(Command::Site(i)) }); }
                    if contains(area, self.cursor) || nav.site == Some(i) {
                        self.skin.text(text, &site.label, 0, [px + 9., py - 12.], 160., IVORY);
                    }
                }
            }
            if drawer_open {
                formal_ui::panel(panels, drawer, [12, 22, 33, 253]);
                self.birthplace_drawer(panels, text, hits, opening, directory, nav, drawer, busy);
            }
        }
        formal_ui::panel(panels, card, [9, 19, 30, 251]);
        if let Some(slot) = self.flags {
            let elapsed = if nav.motion { nav.last_animation.saturating_duration_since(nav.last_input).as_secs_f32() } else { 0. };
            let flag_area = [x + 17., y + 15., 62., 33.];
            let fade = nav.previous_country.map_or(1., |(_, at)| (at.elapsed().as_secs_f32() / 0.3).clamp(0., 1.));
            if let Some((index, _)) = nav.previous_country.filter(|_| fade < 1.) {
                flags.flag_wave(flag_area, view.visuals.record(index).flag, 0., (1. - fade) * 255.);
            }
            flags.flag_wave(flag_area, slot, elapsed, fade * 255.);
        }
        let title = polity_label(polity, opening, self.skin.english());
        self.skin.paragraph(text, title, 1, [x + 17., y + 57., w - 34., 58.], IVORY, 0.93);
        let profile = COUNTRY_PROFILES.iter().find(|row| row.entity_id == polity.id);
        let summary = profile.map(|row| if row.opening_brief_zh.is_empty() { &row.brief_zh } else { &row.opening_brief_zh });
        let brief = if nav.brief {
            profile.map(|row| [&row.opening_brief_zh, &row.brief_zh].into_iter()
                .filter(|content| !content.is_empty()).map(String::as_str).collect::<Vec<_>>().join("  "))
        } else { summary.cloned() };
        if let Some(brief) = brief.filter(|value| !value.is_empty()) {
            let [left, top, width, height] = nav.brief_rect(self.size);
            let mut lines = Vec::new();
            let mut line = String::new();
            let mut used = 0.;
            for ch in brief.chars() {
                let mut encoded = [0; 4];
                let advance = self.skin.width(ch.encode_utf8(&mut encoded), 0) * 0.88;
                if used + advance > width && !line.is_empty() {
                    lines.push(std::mem::take(&mut line));
                    used = 0.;
                }
                line.push(ch);
                used += advance;
            }
            if !line.is_empty() { lines.push(line); }
            let visible = (height / 20.).floor().max(1.) as usize;
            let offset = if nav.brief { nav.brief_scroll.min(lines.len().saturating_sub(visible)) } else { 0 };
            for (i, line) in lines.iter().skip(offset).take(visible).enumerate() {
                self.skin.paragraph(text, line, 0, [left, top + i as f32 * 20., width, 21.], MUTED, 0.88);
            }
            let label = if nav.brief { self.skin.choose("收起简介", "Show less") } else { self.skin.choose("展开简介", "Read profile") };
            self.row(panels, text, hits, [x + 14., y + h - 93., 115., 23.], label, Some(action(Command::Brief)), false);
        }
        let has_sites = opening.is_some_and(|row| !row.sites.is_empty());
        let legacy = opening.is_some_and(|row| !row.native);
        let label = self.skin.choose("出生地选择", "Choose birthplace");
        self.row(panels, text, hits, [x + 14., y + h - 64., w - 28., 27.], label,
            (has_sites && !busy).then_some(action(Command::Drawer)), nav.drawer);
        let label = opening.filter(|_| nav.site.is_some()).map(|opening| nav.path_label(opening));
        if let Some(label) = label {
            self.skin.paragraph(text, &label, 0, [x + 18., y + h - 33., w - 125., 32.], IVORY, 0.75);
        } else {
            self.skin.text(text, if has_sites { self.skin.choose("请选择地点", "Select a place") }
                else { self.skin.choose("没有已登记的地点", "No registered places") }, 0,
                [x + 18., y + h - 30.], w - 130., MUTED);
        }
        let can_enter = !busy && (nav.site.is_some() || legacy);
        self.row(panels, text, hits, [x + w - 106., y + h - 33., 92., 25.],
            self.skin.choose("确认", "Confirm"), can_enter.then_some(action(Command::Enter)), can_enter);
    }

    fn birthplace_drawer(&self, panels: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>,
        opening: &Opening, directory: &Directory, nav: &Selection, [x, y, w, h]: Rect, busy: bool,
    ) {
        let rows = nav.rows(opening, &directory.query);
        let visible = ((h - 91.) / 30.).max(1.) as usize;
        let start = nav.offset.min(rows.len().saturating_sub(visible));
        let path = nav.path.last().and_then(|id| opening.sites.iter().flat_map(|site| &site.path).find(|area| &area.id == id))
            .map_or(opening.label.as_str(), |area| area.label.as_str());
        self.skin.paragraph(text, path, 0, [x + 13., y + 9., w - 90., 36.], IVORY, 0.9);
        self.row(panels, text, hits, [x + w - 76., y + 7., 64., 25.], self.skin.choose("上一级", "Up"),
            (!nav.path.is_empty()).then_some(action(Command::Up)), false);
        self.row(panels, text, hits, [x + 12., y + 43., w - 74., 27.],
            if directory.query.is_empty() { self.skin.choose("搜索地点或行政区", "Search places or areas") } else { &directory.query },
            Some(action(Command::Search)), directory.search_active);
        self.row(panels, text, hits, [x + w - 55., y + 43., 43., 27.], self.skin.choose("清除", "Clear"),
            (!directory.query.is_empty()).then_some(action(Command::ClearSearch)), false);
        for (row, &(index, area, label)) in rows.iter().skip(start).take(visible).enumerate() {
            let site = &opening.sites[index];
            let enabled = !busy && (area.is_some() || site.unavailable.is_none());
            let top = y + 77. + row as f32 * 30.;
            let command = area.map_or(Command::Site(index), |depth| Command::Area(index, depth));
            self.row(panels, text, hits, [x + 12., top, w - 24., 26.], "",
                enabled.then_some(action(command)), nav.site == Some(index) && area.is_none());
            let status = if area.is_some() { "›" } else { site.unavailable.as_deref().unwrap_or("") };
            let status_width = self.skin.width(status, 0).min(w * 0.52);
            self.skin.text(text, label, 0, [x + 20., top + 2.], w - 48. - status_width, if enabled { IVORY } else { MUTED });
            self.skin.text(text, status, 0, [x + w - status_width - 17., top + 2.], status_width + 2., MUTED);
        }
        if rows.is_empty() {
            self.skin.text(text, self.skin.choose("没有匹配地点", "No matching places"), 0, [x + 15., y + 79.], w - 30., MUTED);
        }
    }

    fn country_directory(&self, panels: &mut Mesh, text: &mut Mesh, flags: &mut Mesh, hits: &mut Vec<Hit>, world: &World,
        state: Option<&Lobby>, directory: &Directory, visuals: &PoliticalVisuals, busy: bool,
    ) {
        let area = directory_rect(self.size);
        let [x,y,w,_] = area;
        let compact = self.size[1] < 560;
        let (heading_font, search_top, search_height) = if compact { (0, 28., 28.) } else { (1, 40., 30.) };
        formal_ui::panel(panels,area,[12,22,31,249]);
        self.skin.text(text,self.skin.choose("国家目录", "Countries"),heading_font,[x+18.,y+6.],w-36.,IVORY);
        let hint=if directory.query.is_empty() { self.skin.choose("搜索国家或地区", "Search countries") } else { &directory.query };
        let search_width=if directory.query.is_empty(){w-24.}else{w-74.};
        self.row(panels,text,hits,[x+12.,y+search_top,search_width,search_height],hint,
            (!busy).then_some(action(Command::Search)),directory.search_active);
        if !directory.query.is_empty(){
            self.row(panels,text,hits,[x+w-56.,y+search_top,44.,search_height],self.skin.choose("清除", "Clear"),
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
            self.row(panels,text,hits,[left,row_y,width-16.,row_height-3.],"",
                (!busy).then_some(action(Command::Country(index))),false);
            flags.flag([left + 8., row_y + 16., 23., 13.], visuals.record(index).flag);
            let eligible = opening.is_some_and(|row| state.is_some_and(|state| state.can_open(row)));
            self.skin.paragraph(text, title, 0, [left + 39., row_y + 6., width - 62., row_height - 11.],
                if eligible { IVORY } else { MUTED }, 0.94);
        }
        if directory.entries.is_empty() {
            self.skin.text(text,self.skin.choose("没有匹配的国家", "No matching countries"),0,[left+9.,top+7.],width-18.,MUTED);
        }
        if let Some((track,thumb))=directory.scrollbar(self.size) {
            panels.rect(track[0]+5.,track[1],3.,track[3],[85,75,53,255]);
            panels.rect(thumb[0]+3.,thumb[1],7.,thumb[3],
                if directory.drag.is_some() {[230,202,147,255]} else {[174,146,100,255]});
        }
    }
}

pub fn cloud_cover(mesh: &mut Mesh, size: [u32; 2], phase: f32) {
    let [w, h] = size.map(|value| value as f32);
    let opacity = phase.sin().max(0.);
    mesh.rect(0., 0., w, h, [171, 179, 182, (opacity * 246.).min(255.) as u8]);
    for index in 0..9 {
        let f = index as f32;
        let center = [(f * 0.286 + phase * 0.37).fract() * w, (f * 0.41).fract() * h];
        let points: Vec<_> = (0..20).map(|step| {
            let a = step as f32 / 20. * std::f32::consts::TAU;
            [center[0] + a.cos() * w * 0.29, center[1] + a.sin() * h * 0.11]
        }).collect();
        mesh.shape(&points, [217, 222, 219, (opacity * 32.) as u8]);
    }
}

pub(crate) fn action(command:Command)->Action {Action::Hud(formal_ui::Command::Lobby(command))}
