use crate::{formal_ui::{self,Display,Slot,IVORY,MUTED},overlay::Mesh,ui::{Action,Hit},world::{Polity,World}};
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
    #[serde(skip)] pub map_bound: bool,
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
    pub(crate) fn bind_map_areas(&mut self, world: &World) {
        if self.map_bound || !self.native { return; }
        // The installed administrative outlines currently cover 1900 metropolitan France.
        if let Some(france) = self.choices.iter_mut().find(|opening| opening.id == "state:country_fra") {
            for site in &mut france.sites {
                if let Some(depth) = site.path.iter().position(|area| world.admin.iter().any(|admin| admin.id == area.id)) {
                    let area = site.path.remove(depth);
                    site.path.insert(0, area);
                    continue;
                }
                let Some(admin) = world.admin.iter().find(|admin| admin.contains(site.coordinates)) else { continue; };
                site.path.insert(0, wwo_map_lab::formal_bootstrap::OpeningArea {
                    id: admin.id.clone(), label: admin.name.clone(),
                });
            }
        }
        self.map_bound = true;
    }

    pub fn can_open(&self, opening: &Opening) -> bool {
        !self.native || opening.sites.iter().any(|site| site.unavailable.is_none())
    }

    pub fn opening(&self, polity: &Polity) -> Option<&Opening> {
        self.choices.iter().find(|row| row.id.strip_prefix("state:") == Some(polity.id.as_str()))
    }
}

#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum Page {#[default] Home,Selection,Cloud,Prologue,Load,Settings,Themes}
#[derive(Clone,Copy)]
pub enum Command {
    Page(Page), Country(usize), Back, Drawer, Area(usize, usize), MapArea(usize), Site(usize),
    Up, Search, ClearSearch, ChangePainting, FixPainting(bool), Enter, PrologueChoice(usize),
    PrologueNext, PrologueBack, ToggleOpeningMotion, Load(u8), Exit,
}

struct BirthplaceRow<'a> {
    command: Command,
    label: &'a str,
    status: &'a str,
}

pub type Rect = [f32;4];
pub const SETTINGS_HEIGHT: f32 = 332.;

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
    pub profile_scroll: usize,
    pub map_area: Option<usize>,
    pub path: Vec<String>,
    pub site: Option<usize>,
    pub offset: usize,
    pub drawer_rows: usize,
    pub drawer_drag: Option<DrawerDrag>,
    pub last_input: Instant,
    pub last_animation: Instant,
    pub shift: Option<(Instant, f64, f64)>,
    pub cloud: Option<Instant>,
    pub departure_cloud: Option<Instant>,
    pub arrival_cloud: Option<Instant>,
    pub previous_country: Option<(usize, Instant)>,
}

impl Default for Selection {
    fn default() -> Self {
        let now = Instant::now();
        Self {
            stage: SelectionStage::Globe, drawer: false, profile_scroll: 0, map_area: None, path: Vec::new(),
            site: None, offset: 0, drawer_rows: 5, drawer_drag: None, last_input: now, last_animation: now,
            shift: None, cloud: None, departure_cloud: None, arrival_cloud: None, previous_country: None,
        }
    }
}

impl Selection {
    pub fn reset_place(&mut self) {
        self.drawer = false;
        self.profile_scroll = 0;
        self.map_area = None;
        self.path.clear();
        self.site = None;
        self.offset = 0;
        self.drawer_drag = None;
    }

    pub fn path_label(&self, opening: &Opening, world: &World, skin: &formal_ui::Skin) -> Option<String> {
        let site = opening.sites.get(self.site?)?;
        Some(site.path.iter().map(|area| skin.opening_name(world, &area.id, &area.label))
            .chain(std::iter::once(skin.opening_name(world, &site.id, &site.label)))
            .collect::<Vec<_>>().join(" / "))
    }

    fn rows<'a>(&self, opening: &'a Opening, query: &str, world: &'a World, skin: &'a formal_ui::Skin)
        -> Vec<BirthplaceRow<'a>>
    {
        let query = query.trim().to_lowercase();
        let matches = |id: &str, original: &str| {
            id.contains(&query) || original.to_lowercase().contains(&query)
                || skin.opening_name(world, id, original).to_lowercase().contains(&query)
        };
        let matching = || opening.sites.iter().enumerate().filter(|(_, site)|
            site.path.iter().map(|area| &area.id).take(self.path.len()).eq(self.path.iter()));
        let flat = !self.path.is_empty() && (matching().filter(|(_, site)| site.unavailable.is_none()).count() <= 1
            || opening.id == "state:country_fra" && self.path.len() == 1);
        let mut areas = BTreeMap::new();
        let mut sites = Vec::new();
        if opening.id == "state:country_fra" && self.path.is_empty() {
            for (index, division) in world.admin.iter().enumerate() {
                if query.is_empty() || matches(&division.id, &division.name) {
                    areas.insert(division.id.as_str(), BirthplaceRow {
                        command: Command::MapArea(index), label: skin.division_name(division), status: "›",
                    });
                }
            }
        }
        for (index, site) in matching() {
            let label = skin.opening_name(world, &site.id, &site.label);
            let area_row = |area: &'a wwo_map_lab::formal_bootstrap::OpeningArea, depth| BirthplaceRow {
                command: Command::Area(index, depth),
                label: skin.opening_name(world, &area.id, &area.label),
                status: "›",
            };
            if query.is_empty() {
                if let Some(area) = site.path.get(self.path.len()).filter(|_| !flat) {
                    areas.entry(area.id.as_str()).or_insert_with(|| area_row(area, self.path.len()));
                    continue;
                }
            } else if !matches(&site.id, &site.label) {
                for (depth, area) in site.path.iter().enumerate().skip(self.path.len()) {
                    if matches(&area.id, &area.label) {
                        areas.entry(area.id.as_str()).or_insert_with(|| area_row(area, depth));
                    }
                }
                continue;
            }
            sites.push(BirthplaceRow {
                command: Command::Site(index), label, status: site.unavailable.as_deref().unwrap_or(""),
            });
        }
        let mut regions: Vec<_> = areas.into_values().collect();
        regions.sort_by_key(|row| row.label);
        regions.extend(sites);
        regions
    }
}

pub struct ProfileLayout {
    pub card: Rect,
    pub summary: Rect,
    pub field: Rect,
    pub drawer: Rect,
    pub visible: usize,
    pub rows: usize,
    pub summary_lines: usize,
    pub title: Rect,
}

#[derive(Clone, Copy)]
pub enum DrawerDrag {
    Resize { top: f64, rows: usize },
    Scroll { grab: f32 },
}

const DRAWER_HEADER: f32 = 73.;
const DRAWER_FOOTER: f32 = 23.;
const DRAWER_ROW: f32 = 30.;

impl ProfileLayout {
    pub fn new(size: [u32; 2], world: &World, skin: &formal_ui::Skin, p: &Polity, opening: Option<&Opening>,
        directory: &Directory, nav: &Selection) -> Self
    {
        let [width, height] = size.map(|value| value as f32);
        let w = (width * 0.34).clamp(305., 440.).min(width - 24.);
        let x = width - w - 12.;
        let y = 14.;
        let title = polity_label(p, opening, skin.english());
        let title_width = w - 108.;
        let title_height = skin.wrapped_lines(title, 1, title_width, 0.92).len().max(1) as f32 * 27.;
        let summary_y = y + (title_height + 24.).max(58.);
        let summary_width = w - 32.;
        let summary_lines = skin.wrapped_lines(opening_brief(p), 0, summary_width, 0.92).len();
        let field_label = opening.and_then(|o| nav.path_label(o, world, skin));
        let field_height = field_label.as_deref().map_or(30., |label|
            (skin.wrapped_lines(label, 0, w - 64., 0.9).len() as f32 * 20. + 10.).max(30.));
        let reserve = if nav.drawer && width < 790. { 147. } else { 15. };
        let visible_lines = ((height - summary_y - field_height - 82. - reserve) / 21.).floor().max(1.) as usize;
        let summary_height = summary_lines.min(visible_lines) as f32 * 21.;
        let field_y = summary_y + summary_height + if summary_lines > 0 { 10. } else { 0. };
        let card = [x, y, w, field_y - y + field_height + if nav.site.is_some() { 42. } else { 72. }];
        let rows = opening.filter(|_| nav.drawer).map_or_else(Vec::new, |o| nav.rows(o, &directory.query, world, skin));
        let below = height - card[1] - card[3] - 20.;
        let side = nav.drawer && below < 172. && width >= 790.;
        let drawer_width = if side { (width * 0.39).clamp(310., 500.) } else { w };
        let max_height = if side { height - 64. } else { below };
        let max_visible = ((max_height - DRAWER_HEADER - DRAWER_FOOTER) / DRAWER_ROW).floor().max(1.) as usize;
        let visible = rows.len().max(1).min(nav.drawer_rows).min(max_visible);
        let height = DRAWER_HEADER + DRAWER_FOOTER + visible as f32 * DRAWER_ROW;
        let drawer = if side { [12., 53., drawer_width, height] }
            else { [x, card[1] + card[3] + 8., drawer_width, height] };
        Self { card, summary: [x + 16., summary_y, summary_width, summary_height],
            field: [x + 14., field_y, w - 28., field_height], drawer, visible,
            rows: rows.len(), summary_lines, title: [x + 94., y + 11., title_width, title_height] }
    }

    pub fn contains(&self, nav: &Selection, point: [f64; 2]) -> bool {
        contains(self.card, point) || nav.drawer && contains(self.drawer, point)
    }

    pub fn max_scroll(&self) -> usize { self.rows.saturating_sub(self.visible) }

    fn handle(&self) -> Rect {
        let [x, y, w, h] = self.drawer;
        [x + 12., y + h - DRAWER_FOOTER, w - 24., DRAWER_FOOTER - 4.]
    }

    fn scrollbar(&self, offset: usize) -> Option<(Rect, Rect)> {
        let [x, y, w, _] = self.drawer;
        let height = self.visible as f32 * DRAWER_ROW - 4.;
        formal_ui::drawer_scrollbar([x+8.,y+DRAWER_HEADER,w-16.,height],self.visible,self.rows,offset)
    }
}

impl Selection {
    pub fn grab_drawer(&mut self, layout: &ProfileLayout, point: [f64; 2]) -> bool {
        if !self.drawer { return false; }
        if layout.rows > 1 && contains(layout.handle(), point) {
            self.drawer_drag = Some(DrawerDrag::Resize { top: point[1], rows: layout.visible });
        } else if let Some((_, thumb)) = layout.scrollbar(self.offset).filter(|(track, _)| contains(*track, point)) {
            let grab = if contains(thumb, point) { point[1] as f32 - thumb[1] } else { thumb[3] * 0.5 };
            self.drawer_drag = Some(DrawerDrag::Scroll { grab });
            self.slide_drawer(layout, point[1]);
        } else { return false; }
        true
    }

    pub fn slide_drawer(&mut self, layout: &ProfileLayout, y: f64) {
        match self.drawer_drag {
            Some(DrawerDrag::Resize { top, rows }) => {
                let change = ((y - top) / f64::from(DRAWER_ROW)).round() as isize;
                self.drawer_rows = rows.saturating_add_signed(change).clamp(1, layout.rows.max(1));
            }
            Some(DrawerDrag::Scroll { grab }) => {
                if let Some((track, thumb)) = layout.scrollbar(self.offset) {
                    let position = ((y as f32 - track[1] - grab) / (track[3] - thumb[3])).clamp(0., 1.);
                    self.offset = (position * layout.max_scroll() as f32).round() as usize;
                }
            }
            None => {}
        }
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
    pub world: &'a World,
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

fn opening_brief(polity: &Polity) -> &str {
    COUNTRY_PROFILES.iter().find(|row| row.entity_id == polity.id)
        .map_or("", |row| if row.opening_brief_zh.is_empty() { &row.brief_zh } else { &row.opening_brief_zh })
}

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
    pub fn loading(&self, status:&str, seconds:f32, aspect:f32) -> crate::ui::Layers {
        use crate::ui::Ink;
        let [w,h]=self.size.map(|n|n as f32);
        let mut painting=Mesh::default();let mut shade=Mesh::default();let mut label=Mesh::default();let mut strip=Mesh::default();
        let phase=seconds*std::f32::consts::TAU/36.;
        self.painting(&mut painting,aspect,0.964+0.014*phase.cos(),[0.0096*phase.sin(),0.00456*(2.*phase).sin()]);
        shade.rect(0.,0.,w,h,[3,5,5,153]);
        self.skin.text(&mut label,status,0,[48.,h-73.],w-96.,IVORY);
        strip.image([48.,h-39.,w-96.,3.],[0.,0.,1.,1.],[255;4]);
        [(Mesh::default(),Ink::Solid),(Mesh::default(),Ink::Text),(Mesh::default(),Ink::Instrument),(Mesh::default(),Ink::ClockGears),
         (Mesh::default(),Ink::HudArt),(Mesh::default(),Ink::HudText),
         (painting,Ink::MenuArt),(shade,Ink::Solid),(strip,Ink::Loading),(Mesh::default(),Ink::Flag),
         (Mesh::default(),Ink::HudArt),(Mesh::default(),Ink::Solid),(label,Ink::HudText)]
    }

    fn painting(&self, mesh:&mut Mesh, aspect:f32, scale:f32, drift:[f32;2]) {
        let [w,h]=self.size.map(|n|n as f32);
        let span=if w/h>aspect {[1.,aspect*h/w]} else {[w/h/aspect,1.]};
        let [u,v]=[0.5+drift[0],0.5+drift[1]];
        let [x,y]=span.map(|n|n*scale*0.5);
        mesh.image([0.,0.,w,h],[u-x,v-y,u+x,v+y],[255;4]);
    }

    pub fn lobby(&self,world:&World,state:Option<&Lobby>,page:Page,selection:usize,waiting:bool,directory:&Directory,
        draft:Option<&crate::prologue_ui::Draft>,view:SelectionView<'_>,themes:&crate::menu_theme::Themes)
        -> (crate::ui::Layers,Vec<Hit>)
    {
        use crate::ui::Ink;
        let [w,h]=self.size.map(|n|n as f32);
        let mut background=Mesh::default();
        let mut panels=Mesh::default();
        let art=Mesh::default();
        let mut scenes=Mesh::default();
        let mut paper=Mesh::default();
        let mut text=Mesh::default();
        let mut flags=Mesh::default();
        let mut hits=Vec::new();
        if !matches!(page, Page::Selection | Page::Cloud | Page::Prologue) {
            self.painting(&mut background,themes.aspect,1.,[0.;2]);
            panels.rect(0.,0.,w,h,[3,5,5,75]);
        }
        let row=|label,page| (label,Some(action(Command::Page(page))));
        let busy=waiting||state.is_some_and(|s|s.busy);
        let ready=state.is_some_and(|s|s.ready);
        match page {
            Page::Home=>{
                let x=48.;let y=(h-326.)*0.5;let width=350.;
                formal_ui::panel(&mut panels,[x,y,width,326.],[6,14,23,241]);
                self.skin.text(&mut text,"1900",2,[x+24.,y+27.],width-48.,IVORY);
                let rows=[("开始",ready.then_some(action(Command::Page(Page::Selection)))),("加载",ready.then_some(action(Command::Page(Page::Load)))),
                    row("主题管理",Page::Themes),row("设置",Page::Settings),
                    ("退出",Some(action(Command::Exit)))];
                for (i,(label,command)) in rows.into_iter().enumerate(){
                    self.row(&mut panels,&mut text,&mut hits,[x+24.,y+79.+i as f32*40.,width-48.,32.],label,command,false);
                }
                self.skin.text(&mut text,crate::build_identity::display(),0,[x+24.,y+285.],width-48.,MUTED);
                if let Some(status)=state.map(|state|state.status.as_str()).filter(|status|!status.is_empty()) {
                    let lines=self.skin.wrapped_lines(status,0,width-36.,1.);
                    let height=18.+lines.len() as f32*17.;
                    formal_ui::panel(&mut panels,[x,y+334.,width,height],[6,14,23,241]);
                    for (i,line) in lines.iter().enumerate(){
                        self.skin.text(&mut text,line,0,[x+18.,y+341.+i as f32*17.],width-36.,IVORY);
                    }
                }
            }
            Page::Selection => {
                let navigation = view.navigation;
                let back = [12., 14., 67., 30.];
                self.row(&mut panels, &mut text, &mut hits, back, self.skin.choose("返回", "Back"),
                    (!busy).then_some(action(Command::Back)), false);
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
            Page::Cloud => (),
            Page::Prologue => {
                if let Some((draft, opening)) = draft.and_then(|draft| {
                    world.polities.get(draft.country).and_then(|polity| state?.opening(polity)).map(|opening| (draft, opening))
                }) {
                    self.draw_prologue(&mut scenes, &mut paper, &mut panels, &mut text, &mut hits, draft, opening, world);
                    if !self.hud.reduce_opening_motion {
                        let opacity = 0.65 + 0.35 * ease_cloud(draft.changed.elapsed().as_secs_f32() / 0.34);
                        for mesh in [&mut paper, &mut panels, &mut text] {
                            for vertex in &mut mesh.vertices {
                                vertex.color[3] = (f32::from(vertex.color[3]) * opacity).round() as u8;
                            }
                        }
                    }
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
                let height=if page==Page::Settings{SETTINGS_HEIGHT}else{228.};
                let width=365.;let x=(w-width)*0.5;let y=(h-height)*0.5;
                formal_ui::panel(&mut panels,[x,y,width,height],[6,14,23,247]);
                self.skin.text(&mut text,if page==Page::Settings{"设置"}else{"主题管理"},1,[x+22.,y+15.],width-44.,IVORY);
                if page==Page::Settings {
                    self.settings(&mut panels,&mut text,&mut hits,[x,y,width,height],formal_ui::Command::Lobby(Command::Page(Page::Home)),true);
                }else{
                    let say=|zh,en|self.skin.choose(zh,en);
                    if let Some(title)=themes.title(self.skin.english()) {
                        self.skin.paragraph(&mut text,title,0,[x+24.,y+48.,width-48.,40.],IVORY,1.);
                    }
                    let fixed=themes.preference().0.is_some();
                    let button=(width-52.)*0.5;
                    self.row(&mut panels,&mut text,&mut hits,[x+22.,y+93.,button,31.],say("随机轮换","Shuffle on startup"),
                        Some(action(Command::FixPainting(false))),!fixed);
                    self.row(&mut panels,&mut text,&mut hits,[x+30.+button,y+93.,button,31.],say("固定当前","Keep this painting"),
                        themes.title(false).is_some().then_some(action(Command::FixPainting(true))),fixed);
                    self.row(&mut panels,&mut text,&mut hits,[x+22.,y+134.,width-44.,31.],say("更换画作","Next painting"),
                        themes.can_change().then_some(action(Command::ChangePainting)),false);
                    self.row(&mut panels,&mut text,&mut hits,[x+22.,y+175.,width-44.,31.],say("返回","Back"),
                        Some(action(Command::Page(Page::Home))),false);
                }
            }
        }
        if page != Page::Cloud && view.navigation.departure_cloud.is_none() {
            let status=state.map(|s|s.status.as_str()).filter(|s|!s.is_empty()).unwrap_or(if busy{"正在进入世界。"}else if !ready{"正在读取地图资料。"}else{""});
            let status=if self.feedback.is_empty(){status}else{self.feedback};
            if !status.is_empty(){
                formal_ui::panel(&mut panels,[(w-550.)*0.5,h-55.,550.,41.],[6,14,23,245]);
                self.skin.text(&mut text,status,0,[(w-515.)*0.5,h-45.],515.,IVORY);
            }
        }
        let panel_layers = if page == Page::Prologue {
            [(paper, Ink::ProloguePaper), (panels, Ink::Solid), (flags, Ink::Flag)]
        } else {
            [(panels, Ink::Solid), (flags, Ink::Flag), (paper, Ink::ProloguePaper)]
        };
        let [panel_base, panel_content, panel_finish] = panel_layers;
        ([(Mesh::default(),Ink::Solid),(Mesh::default(),Ink::Text),(Mesh::default(),Ink::Instrument),(Mesh::default(),Ink::ClockGears),
          (Mesh::default(),Ink::HudArt),(Mesh::default(),Ink::HudText),
          (background,Ink::MenuArt),(scenes,Ink::PrologueArt),panel_base,panel_content,panel_finish,(art,Ink::HudArt),(text,Ink::HudText)],hits)
    }

    fn opening_card(
        &self, panels: &mut Mesh, text: &mut Mesh, flags: &mut Mesh, hits: &mut Vec<Hit>,
        polity: &Polity, opening: Option<&Opening>, directory: &Directory, view: &SelectionView<'_>, busy: bool,
    ) {
        let nav = view.navigation;
        let layout = ProfileLayout::new(self.size, view.world, self.skin, polity, opening, directory, nav);
        let [x, y, w, h] = layout.card;
        if let Some(opening) = opening {
            if view.camera.mpp < 11_000. {
                let mut painted = Vec::<[f64; 2]>::new();
                for (i, site) in opening.sites.iter().enumerate() {
                    if !site.path.iter().map(|area| &area.id).take(nav.path.len()).eq(nav.path.iter()) { continue; }
                    let Some(point) = view.camera.project(site.coordinates, self.size) else { continue; };
                    if layout.contains(nav, point) || point[0] < 0. || point[1] < 0.
                        || point[0] >= f64::from(self.size[0]) || point[1] >= f64::from(self.size[1]) { continue; }
                    if nav.site != Some(i) && painted.iter().any(|prior| (point[0] - prior[0]).hypot(point[1] - prior[1]) < 12.) { continue; }
                    painted.push(point);
                    let [px, py] = point.map(|value| value as f32);
                    let area = [px - 6., py - 6., 12., 12.];
                    let enabled = site.unavailable.is_none();
                    let color = if nav.site == Some(i) { IVORY } else if enabled { formal_ui::BRASS } else { MUTED };
                    panels.shape(&[[px, py - 4.], [px + 4., py], [px, py + 4.], [px - 4., py]], color);
                    if enabled && !busy { hits.push(Hit { area, action: action(Command::Site(i)) }); }
                    if contains(area, self.cursor) || nav.site == Some(i) || enabled && nav.map_area.is_some() {
                        let label = self.skin.opening_name(view.world, &site.id, &site.label);
                        self.skin.text(text, label, 0, [px + 9., py - 12.], 184., IVORY);
                    }
                }
            }
            if nav.drawer {
                formal_ui::panel(panels, layout.drawer, [12, 22, 33, 252]);
                self.birthplace_drawer(panels, text, hits, opening, directory, view, &layout, busy);
            }
        }
        formal_ui::panel(panels, layout.card, [9, 19, 30, 251]);
        if let Some(slot) = self.flags {
            let flag_area = [x + 16., y + 13., 60., 33.];
            if self.hud.reduce_opening_motion {
                flags.flag(flag_area, slot);
            } else {
                let elapsed = nav.last_animation.saturating_duration_since(nav.last_input).as_secs_f32();
                let fade = nav.previous_country.map_or(1., |(_, at)| (at.elapsed().as_secs_f32() / 0.3).clamp(0., 1.));
                if let Some((index, _)) = nav.previous_country.filter(|_| fade < 1.) {
                    flags.flag_wave(flag_area, view.visuals.record(index).flag, elapsed, (1. - fade) * 255.);
                }
                flags.flag_wave(flag_area, slot, elapsed, fade * 255.);
            }
        }
        let say = |zh, en| self.skin.choose(zh, en);
        let title = polity_label(polity, opening, self.skin.english());
        self.skin.paragraph(text, title, 1, layout.title, IVORY, 0.92);
        let [left, top, width, height] = layout.summary;
        let lines = self.skin.wrapped_lines(opening_brief(polity), 0, width, 0.92);
        let visible = (height / 21.).floor() as usize;
        let offset = nav.profile_scroll.min(lines.len().saturating_sub(visible));
        for (i, line) in lines.iter().skip(offset).take(visible).enumerate() {
            self.skin.paragraph(text, line, 0, [left, top + i as f32 * 21., width, 22.], IVORY, 0.92);
        }
        let has_sites = opening.is_some_and(|row| !row.sites.is_empty());
        let legacy = opening.is_some_and(|row| !row.native);
        let field = opening.and_then(|o| nav.path_label(o, view.world, self.skin));
        self.row(panels, text, hits, layout.field, "",
            (has_sites && !busy).then_some(action(Command::Drawer)), nav.drawer);
        let [fx, fy, fw, fh] = layout.field;
        let field_text = field.as_deref().unwrap_or(say("出生地：点击地图或选择行政区", "Birthplace: click the map or choose a district"));
        self.skin.paragraph(text, field_text, 0, [fx + 8., fy + 4., fw - 36., fh - 4.], IVORY, 0.9);
        if has_sites { self.skin.text(text, if nav.drawer { "−" } else { "+" }, 0, [fx + fw - 19., fy + 4.], 14., MUTED); }
        let can_enter = !busy && (nav.site.is_some() || legacy);
        let begin = if legacy {
            say("开始", "Start")
        } else {
            say("开始人生序章", "Begin prologue")
        };
        let button_width = self.skin.width(begin, 0) + 30.;
        self.row(panels, text, hits, [x + w - 14. - button_width, y + h - 40., button_width, 29.],
            begin, can_enter.then_some(action(Command::Enter)), can_enter);
        if !can_enter {
            let status = if !has_sites { say("没有已登记的地点", "No places in the opening directory") }
                else if opening.is_some_and(|row| row.sites.iter().all(|site| site.unavailable.is_some())) {
                    say("尚无符合居住条件的地点", "No place has eligible residents")
                } else { say("请选择可登记居民的城镇", "Choose a town with eligible residents") };
            self.skin.text(text, status, 0, [x + 17., y + h - 64.], w - 34., MUTED);
        }
    }

    fn birthplace_drawer(&self, panels: &mut Mesh, text: &mut Mesh, hits: &mut Vec<Hit>,
        opening: &Opening, directory: &Directory, view: &SelectionView<'_>, layout: &ProfileLayout, busy: bool,
    ) {
        let [x, y, w, _] = layout.drawer;
        let nav = view.navigation;
        let rows = nav.rows(opening, &directory.query, view.world, self.skin);
        let start = nav.offset.min(layout.max_scroll());
        let path = nav.path.last().and_then(|id| {
            if let Some(admin) = nav.map_area.and_then(|i| view.world.admin.get(i)).filter(|a| a.id == *id) {
                return Some(self.skin.division_name(admin));
            }
            opening.sites.iter().flat_map(|site| &site.path).find(|area| area.id == *id)
                .map(|area| self.skin.opening_name(view.world, &area.id, &area.label))
        }).unwrap_or(&opening.label);
        self.skin.paragraph(text, path, 0, [x + 13., y + 7., w - 90., 35.], IVORY, 0.9);
        self.row(panels, text, hits, [x + w - 76., y + 7., 64., 25.], self.skin.choose("上一级", "Up"),
            (!nav.path.is_empty()).then_some(action(Command::Up)), false);
        self.row(panels, text, hits, [x + 12., y + 38., w - 90., 27.],
            if directory.query.is_empty() { self.skin.choose("搜索地点或行政区", "Search places or areas") } else { &directory.query },
            Some(action(Command::Search)), directory.search_active);
        self.row(panels, text, hits, [x + w - 71., y + 38., 59., 27.], self.skin.choose("清除", "Clear"),
            (!directory.query.is_empty()).then_some(action(Command::ClearSearch)), false);
        let row_width = w - if layout.max_scroll() > 0 { 38. } else { 24. };
        for (row, entry) in rows.iter().skip(start).take(layout.visible).enumerate() {
            let is_location = matches!(entry.command, Command::Site(_));
            let enabled = !busy && (!is_location || entry.status.is_empty());
            let selected = matches!(entry.command, Command::Site(index) if nav.site == Some(index));
            let left = x + 12.;
            let top = y + DRAWER_HEADER + row as f32 * DRAWER_ROW;
            let area = [left, top, row_width, DRAWER_ROW];
            if selected || enabled && contains(area, self.cursor) {
                panels.rect(left, top, row_width, DRAWER_ROW - 1., [51, 59, 60, 255]);
            }
            panels.rect(left, top + DRAWER_ROW - 1., row_width, 1., [55, 66, 70, 255]);
            if enabled { hits.push(Hit { area, action: action(entry.command) }); }
            let status_width = self.skin.width(entry.status, 0).min(row_width * 0.48);
            self.skin.text(text, entry.label, 0, [left + 8., top + 4.], row_width - 22. - status_width, if enabled { IVORY } else { MUTED });
            self.skin.text(text, entry.status, 0, [left + row_width - status_width - 9., top + 4.], status_width + 2., MUTED);
        }
        if let Some((track, thumb)) = layout.scrollbar(nav.offset) {
            panels.rect(track[0] + 5., track[1], 4., track[3], [47, 61, 73, 255]);
            panels.rect(thumb[0] + 4., thumb[1], 6., thumb[3], formal_ui::BRASS);
        }
        if rows.len() > 1 {
            let [gx, gy, gw, gh] = layout.handle();
            let color = if contains(layout.handle(), self.cursor) { IVORY } else { MUTED };
            panels.rect(gx + gw / 2. - 14., gy + gh / 2. - 2., 28., 2., color);
            panels.rect(gx + gw / 2. - 14., gy + gh / 2. + 2., 28., 2., color);
        }
        if rows.is_empty() {
            let label = if directory.query.is_empty() && !nav.path.is_empty() {
                self.skin.choose("该行政区暂无已登记的开局城镇", "No opening town is registered in this district")
            } else { self.skin.choose("没有匹配地点", "No matching places") };
            self.skin.paragraph(text, label, 0, [x + 15., y + 74., w - 30., 33.], MUTED, 0.9);
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

pub const CLOUD_OPEN_TIME: f32 = 2.75;
pub const CLOUD_SCENE_CUT: f32 = 1.16;
pub const CLOUD_DEPART_TIME: f32 = 0.81;
pub const CLOUD_ARRIVE_TIME: f32 = 1.24;

pub fn ease_cloud(t: f32) -> f32 {
    let t = t.clamp(0., 1.);
    t * t * (3. - 2. * t)
}

pub fn cloud_skip_rect(size: [u32; 2]) -> Rect {
    [size[0] as f32 - 191., size[1] as f32 - 58., 172., 35.]
}

pub fn cloud_cover(size: [u32; 2], coverage: f32, travel: f32, skin: &crate::formal_ui::Skin) -> crate::ui::Layers {
    use crate::ui::Ink;
    let mut layers = std::array::from_fn(|_| (Mesh::default(), Ink::Solid));
    let [w, h] = size.map(|value| value as f32);
    layers[0].0.rect(0., 0., w, h, [174, 182, 188, (255. * coverage.powi(3)).round() as u8]);
    layers[1].1 = Ink::OpeningCloud;
    for (index, (scale, velocity, drift, tint, strength)) in [
        (1.42, -0.23, 0.05, [228, 237, 250], 0.85),
        (1.58, 0.47, -0.14, [242, 241, 235], 0.95),
        (1.91, -0.88, 0.29, [255, 251, 243], 0.95),
    ].into_iter().enumerate() {
        let span = (w.max(h * 1.5) * scale, h.max(w / 1.5) * scale);
        let x = (w - span.0) * 0.5 + w * (travel - 0.48) * velocity;
        let y = (h - span.1) * 0.5 + h * (travel - 0.48) * drift;
        let uv = if index == 1 { [1., 0., 0., 1.] } else { [0., 0., 1., 1.] };
        let alpha = (coverage.powf(1. + index as f32 * 0.35) * 255. * strength) as u8;
        layers[1].0.image([x, y, span.0, span.1], uv, [tint[0], tint[1], tint[2], alpha]);
    }
    let rect = cloud_skip_rect(size);
    let [x, y, width, _] = rect;
    formal_ui::panel(&mut layers[2].0, rect, [6, 14, 23, 247]);
    layers[3].1 = Ink::Text;
    skin.text(&mut layers[3].0, skin.choose("跳过过场 · Esc", "Skip transition · Esc"), 0,
        [x + 11., y + 8.], width - 22., IVORY);
    layers
}

pub(crate) fn action(command:Command)->Action {Action::Hud(formal_ui::Command::Lobby(command))}
