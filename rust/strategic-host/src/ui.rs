use crate::{camera::Camera,overlay::{Atlas,Mesh},world::{Place,World}};
use std::cmp::Ordering;
use std::collections::HashSet;
use crate::map_facilities::{self, Facility, PlaceFilter};
#[derive(Clone,Copy)]
pub enum Ink { HudArtGlass, ClockGears, Solid, Text, Flag, HudArt, HudText, Instrument, MenuArt, PrologueArt, ProloguePaper, OpeningCloud, Loading, HistoryLight }

const LIGHT:[u8;4]=[241,230,206,255];
const SUBTLE:[u8;4]=[199,191,168,255];
const GOLD:[u8;4]=[183,151,95,255];
const PANEL:[u8;4]=[15,25,34,245];
const LINE:[u8;4]=[92,94,84,230];

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Mode { Geographic, Political, Economic, Military }
impl Mode {
    pub fn index(self)->u8 {self as u8}
}
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum Object {Place(usize),Polity(usize),Administration(usize)}
#[derive(Clone,Copy)]
pub enum CountryView {Summary,Record,Directory(usize),Region {page:usize,index:usize}}
#[derive(Clone,Copy)]
pub struct CountryPanel {pub polity:usize,pub view:CountryView}
impl CountryPanel {
    pub fn rect(self,[width,height]:[u32;2])->[f32;4] {
        if matches!(self.view,CountryView::Summary) {return [12.,83.,300.,222.];}
        let w=(width as f32-44.).min(550.);
        let h:f32=match self.view {CountryView::Directory(_)=>392.,_=>311.};
        [(width as f32-w)*0.5,103.,w,h.min(height as f32-115.)]
    }
    pub fn rows(self,size:[u32;2])->usize {
        ((self.rect(size)[3]-116.)/29.).floor().max(1.) as usize
    }
}
#[derive(Clone,Copy)]
pub enum CountryAction {Close,Back,Record,Directory,Page(i32),Region(usize),Boundary(usize)}
#[derive(Clone,Copy)]
pub enum Action {
    Mode(Mode),Home,Back,Search,Close,Details,Locate,Select(Object),Country(CountryAction),
    PlaceFilter(PlaceFilter),
    Hud(crate::formal_ui::Command),
    Resources(crate::resource_map::Command),
}
#[derive(Clone,Copy)]
pub struct Hit {pub area:[f32;4],pub action:Action}
pub struct Label<'a> {pub object:Object,pub xy:[f32;2],pub name:&'a str,pub rank:u32}
pub struct Ui<'a> {
    pub mode:Mode,
    pub date:&'a str,
    pub camera:&'a Camera,
    pub size:[u32;2],
    pub selected:Option<Object>,
    pub admin:&'a str,
    pub details:bool,
    pub country:Option<CountryPanel>,
    pub search:Option<&'a str>,
    pub search_results:&'a [Object],
    pub econ_label:&'a str,
    pub econ_legend:&'a [(String,[u8;4])],
    pub resources: Option<&'a crate::resource_map::State>,
    pub year: i32,
    pub mouse:&'a str,
    pub labels:bool,
    pub transport_detail:Option<&'a crate::transport_ui::Detail>,
    pub formal:crate::formal_ui::Display<'a>,
}

pub fn can_read_object(world: &World, written: Option<&wwo_map_lab::formal_bootstrap::InitialWorld>, object: Object) -> bool {
    written.is_none_or(|written| match object {
        Object::Place(index) => written.can_read_place_record(&world.places[index].id),
        Object::Polity(index) => written.can_read_polity_record(&world.polities[index].id),
        Object::Administration(_) => written.can_read_polity_record("country_fra"),
    })
}

pub fn active(date:&str,from:&str,to:&str)->bool {(from.is_empty() || date>=from) && (to.is_empty() || date<to)}
fn labels<'a>(world:&'a World,ui:&Ui<'a>)->Vec<Label<'a>> {
    let mut list=Vec::new();
    let threshold=ui.camera.mpp;
    if ui.mode==Mode::Political && World::active_politics(ui.date) && threshold>570. {
        for (i,p) in world.polities.iter().enumerate() {
            if p.rank>2 && threshold>6100. || !active(ui.date,&p.from_date,&p.to_date) {continue;}
            if let Some(xy)=ui.camera.project(p.coordinates,ui.size) {
                list.push(Label{object:Object::Polity(i),xy:xy.map(|v|v as f32),name:ui.formal.skin.country_name(p),rank:p.rank+1});
            }
        }
    }
    list.sort_by(|a,b| {
        if a.object==b.object {return Ordering::Equal;}
        if Some(a.object)==ui.selected {return Ordering::Less;}
        if Some(b.object)==ui.selected {return Ordering::Greater;}
        a.rank.cmp(&b.rank).then(a.name.cmp(b.name))
    });
    list
}
fn measure(a:&Atlas,variant:usize,s:&str)->f32 {s.chars().map(|c|a.glyph(variant,c)[2]).sum()}
fn panel(m:&mut Mesh,x:f32,y:f32,w:f32,h:f32) {
    m.rect(x,y,w,h,PANEL);m.rect(x,y,w,1.,GOLD);m.rect(x,y+h-1.,w,1.,LINE);
}
fn intersects([x,y,w,h]:[f32;4],[a,b,c,d]:[f32;4])->bool{x<a+c && x+w>a && y<b+d && y+h>b}

fn place_visible(ui:&Ui<'_>,place:&Place,kind:&str,facility:Option<Facility>)->bool {
    match ui.mode {
        Mode::Geographic=>true,
        Mode::Political=>ui.formal.hud.place_filter.visible(place,kind,facility),
        Mode::Economic=>matches!(kind,"capital"|"city"|"town"|"station"|"port")
            || matches!(facility,Some(Facility::Industrial|Facility::Mining)),
        Mode::Military=>place.military_facility_active ||
            matches!(kind,"capital"|"admin_primary"|"admin_secondary"|"city"|"bridge"|"station"|"port"),
    }
}

fn place_symbols(world:&World,ui:&Ui<'_>,occupied:&mut Vec<[f32;4]>,previous:&mut HashSet<usize>,
    art:&mut Mesh,text:&mut Mesh,map:&mut Mesh,hits:&mut Vec<Hit>)
{
    use crate::formal_ui::{Command, IVORY};
    let [w,h]=ui.size.map(|n|n as f32);
    let skin=ui.formal.skin;
    let regional=ui.camera.level!=crate::camera::Level::World;
    let mut candidates=Vec::new();
    for (index,place) in world.places.iter().enumerate() {
        let kind=map_facilities::symbol(&place.symbol);
        let facility=Facility::for_place(place);
        if kind=="settlement" && facility.is_none() {continue;}
        if facility==Some(Facility::MilitaryBase) && !place.military_facility_active {continue;}
        let ordinary_marker=ui.labels && place.display_symbol && place_visible(ui,place,kind,facility);
        let population_marker=ui.formal.population_debug && place.selectable &&
            matches!(kind,"capital"|"admin_primary"|"admin_secondary"|"city"|"town"|"village");
        if !(ordinary_marker || population_marker) || !active(ui.date,&place.from_date,&place.to_date) {continue;}
        let chosen=ui.selected==Some(Object::Place(index));
        let generated=facility.map(Facility::symbol);
        let Some(spec)=generated.as_ref().or_else(||skin.map_symbols.get(kind)) else {continue;};
        let mut limit=if regional {spec.region_max_mpp} else {spec.world_max_mpp};
        if place.reference {
            if !regional {continue;}
            limit=limit.min(place.max_mpp);
        }
        let retained=previous.contains(&index);
        if !chosen && ((!regional&&!spec.world)||ui.camera.mpp>limit*if retained {1.12} else {1.}) {continue;}
        let Some(point)=ui.camera.project(place.coordinates,ui.size) else {continue;};
        let [x,y]=point.map(|n|n as f32);
        let px=spec.screen_px*if regional {1.} else {0.78};
        let area=[x-px/2.,y-px/2.,px,px];
        if area[0]<0.||area[1]<0.||area[0]+px>w||area[1]+px>h {continue;}
        candidates.push((index,place,kind,area,chosen,retained,spec.priority,facility));
    }
    candidates.sort_by(|a,b| b.4.cmp(&a.4).then(b.6.cmp(&a.6)).then(b.5.cmp(&a.5)).then(a.1.id.cmp(&b.1.id)));
    let mut placed=Vec::new();
    previous.clear();
    for (i,place,kind,[x,y,px,_],chosen,_,_,facility) in candidates {
        if placed.len()>=(if regional {160} else {24}) {break;}
        if !chosen&&occupied.iter().any(|&old|intersects([x-2.,y-2.,px+4.,px+4.],old)) {continue;}
        occupied.push([x-2.,y-2.,px+4.,px+4.]);
        let pick=[x-4.,y-4.,px+8.,px+8.];
        if let Some(facility)=facility {
            facility.draw(map,[x,y,px,px],place.selectable);
        } else {
            let asset=format!("map_{kind}");
            skin.tinted_sprite(art,&asset,[x-1.25,y-1.25,px+2.5,px+2.5],[25,38,36,217]);
            let color=if place.selectable {[255;4]} else {[184,184,184,153]};
            skin.tinted_sprite(art,&asset,[x,y,px,px],color);
        }
        if chosen {map.line([x+px/2.-4.,y+px+2.],[x+px/2.+4.,y+px+2.],1.5,GOLD);}
        if place.selectable {hits.push(Hit{area:pick,action:Action::Select(Object::Place(i))});}
        previous.insert(i);
        placed.push((i,place,[x+px+4.,y+px*0.5-7.],chosen));
    }
    for (i,place,[x,y],chosen) in placed {
        let name=if skin.english()||place.name_zh.is_empty(){&place.name}else{&place.name_zh};
        let readable = can_read_object(world, ui.formal.written_world, Object::Place(i));
        let width=if readable { skin.width(name,0) } else { 36. };
        let area=[x-2.,y-2.,width+4.,19.];
        if x+width>w||(!chosen&&occupied.iter().any(|&old|intersects(area,old))) {continue;}
        occupied.push(area);
        if !readable {
            ui.formal.ink_block(map,[x,y+6.,width,9.]);
            continue;
        }
        for [dx,dy] in [[-1.,0.],[1.,0.],[0.,-1.],[0.,1.]] {
            skin.text(text,name,0,[x+dx,y+dy],width+1.,[41,48,43,230]);
        }
        skin.text(text,name,0,[x,y],width+1.,IVORY);
        if place.selectable {
            hits.push(Hit { area, action: Action::Select(Object::Place(i)) });
        }
    }
    if let Some([lon,lat])=ui.formal.session.map(|s|s.coordinates.as_slice()) {
        if let Some([x,y])=ui.camera.project([*lon,*lat],ui.size).map(|p|p.map(|n|n as f32)) {
            if x>=0.&&x<w&&y>=0.&&y<h {
                let cy=y-17.;
                let blue=[67,143,227,255];
                let white=[255;4];
                map.shape(&[[x,y],[x-8.,cy+4.],[x+8.,cy+4.]],white);
                map.shape(&[[x,y-3.],[x-6.,cy+3.],[x+6.,cy+3.]],blue);
                let circle=|mesh:&mut Mesh,center:[f32;2],radius:f32,color| {
                    let points=std::array::from_fn::<_,24,_>(|i|{
                        let angle=i as f32*std::f32::consts::TAU/24.;
                        [center[0]+radius*angle.cos(),center[1]+radius*angle.sin()]
                    });
                    mesh.shape(&points,color);
                };
                circle(map,[x,cy],11.,white);
                circle(map,[x,cy],9.,blue);
                circle(map,[x,cy-3.],2.5,white);
                let mut prev=[x-4.5,cy+5.];
                for step in 1..=12 {
                    let angle=std::f32::consts::PI*(1.+step as f32/12.);
                    let next=[x+4.5*angle.cos(),cy+5.+4.5*angle.sin()];
                    map.line(prev,next,2.,white);
                    prev=next;
                }
                hits.push(Hit{area:[x-12.,cy-12.,24.,31.],action:Action::Hud(Command::PlayerMarker)});
            }
        }
    }
}

pub type Layers = [(Mesh,Ink);13];

pub fn compose(world:&World,a:&Atlas,ui:Ui<'_>,markers:&mut HashSet<usize>)->(Layers,Vec<Hit>) {
    let [w,h]=ui.size.map(|x|x as f32);
    let mut map=Mesh::default();let labels_mesh=Mesh::default();
    let mut panels=Mesh::default();let mut text=Mesh::default();let mut flags=Mesh::default();
    let mut hud_art=Mesh::default();let mut hud_type=Mesh::default();let mut instrument=Mesh::default();let mut clock=Mesh::default();
    let mut marker_art=Mesh::default();
    let mut marker_type=Mesh::default();
    let mut hits=Vec::new();
    if ui.formal.hud.menu.modal() {
        ui.formal.draw(&mut panels,&mut hud_art,&mut hud_type,&mut clock,&mut flags,&mut instrument,&mut hits);
        return ([(map,Ink::Solid),(labels_mesh,Ink::Text),(instrument,Ink::Instrument),(Mesh::default(),Ink::HistoryLight),
            (marker_art,Ink::HudArt),(marker_type,Ink::HudText),(panels,Ink::Solid),(text,Ink::Text),(flags,Ink::Flag),(ui.formal.clock_gears(),Ink::ClockGears),(hud_art,if ui.formal.hud.mechanical.hidden {Ink::HudArt}else{Ink::HudArtGlass}),(clock,Ink::Solid),(hud_type,Ink::HudText)],hits);
    }
    let mut occupied=vec![[0.,0.,w,55.],[0.,h-51.,w,51.]];
    if ui.formal.population_debug {occupied.push(crate::pop_debug_ui::bounds(ui.size));}
    if matches!(ui.selected,Some(Object::Place(_)|Object::Administration(_))){occupied.push([17.,73.,300.,213.]);}
    if let Some(rect)=ui.formal.page_rect(){occupied.push(rect);}
    if let Some(resources)=ui.resources.filter(|resources| resources.open) {
        occupied.push(crate::resource_map::bounds(ui.size));
        crate::resource_map::draw_layer(resources,ui.camera,ui.size,ui.year,&mut map,&mut hits);
    }
    let opening_stations = match ui.selected {
        Some(Object::Place(index)) if ui.details && ui.mode == Mode::Military => ui.formal.written_world
            .map_or(&[][..], |host| host.regimental_opening_stations(&world.places[index].id)),
        _ => &[],
    };
    let detail_height = 294. + 56. * opening_stations.len().saturating_sub(1) as f32;
    if ui.details {occupied.push([w/2.-252.,105.,504.,detail_height]);}
    if let Some(country)=ui.country {occupied.push(country.rect(ui.size));}
    if let Some(detail)=ui.transport_detail {occupied.push(detail.rect(ui.size,ui.formal.hud.transport_detail_expanded));}
    let readable = ui.formal.can_read_world();
    for label in labels(world,&ui).into_iter().filter(|_|ui.labels) {
        let readable = can_read_object(world, ui.formal.written_world, label.object);
        if occupied.len()>95 {break;}
        let [x,y]=label.xy;
        let variant=usize::from(label.rank==0 && ui.camera.mpp<10000.);
        let length=if readable { ui.formal.skin.width(label.name,variant) } else { 42. };
        let pad=-length*0.5;
        let area=[x+pad-4.,y-10.,length+10.,22.];
        if x<8. || x>w-8. || y<55. || y>h-51. || area[0]<4. || area[0]+area[2]>w-3.
            || occupied.iter().any(|old|intersects(area,*old)) {continue;}
        occupied.push(area);
        let selected=Some(label.object)==ui.selected;
        let top=y-13.;
        if !readable {
            ui.formal.ink_block(&mut map,[x+pad,y-3.,length,10.]);
            hits.push(Hit{area,action:Action::Select(label.object)});
            continue;
        }
        for [dx,dy] in [[-1.,0.],[1.,0.],[0.,-1.],[0.,1.]] {
            ui.formal.skin.text(&mut marker_type,label.name,variant,[x+pad+dx,top+dy],length+1.,[16,28,30,230]);
        }
        ui.formal.skin.text(&mut marker_type,label.name,variant,[x+pad,top],length+1.,if selected{[255,222,138,255]}else{LIGHT});
        hits.push(Hit{area,action:Action::Select(label.object)});
    }
    place_symbols(world,&ui,&mut occupied,markers,&mut marker_art,&mut marker_type,&mut map,&mut hits);
    let skin=ui.formal.skin;
    if let Some(object)=ui.selected.filter(|o|ui.formal.hud.page==crate::formal_ui::Page::Map&&!matches!(o,Object::Polity(_))) {
        let x=17.;let y=73.;let width=300.;
        let transport = match object {
            Object::Place(i) => ui.formal.written_world.and_then(|host|
                (host.player_alive() && host.can_book_transport_to(&world.places[i].id)).then_some(i)),
            _ => None,
        };
        let has_debug=ui.formal.debug.is_some();
        let facilities=if let Object::Place(i)=object {
            let place=&world.places[i];
            Facility::for_place(place).map(Facility::mode).or(match map_facilities::symbol(&place.symbol) {
                "historic_site"|"castle"|"fort"|"monument"|"religious"|"eiffel"|"clock_tower"|"pyramids"=>Some(Mode::Geographic),
                "station"|"bridge"|"port"=>Some(Mode::Economic),
                _=>None,
            }).filter(|mode| *mode!=ui.mode)
        } else {None};
        let extra_row=if facilities.is_some() {32.} else {0.};
        panel(&mut panels,x,y,width,if has_debug {200.+extra_row} else {148.+extra_row});
        let (label,id,desc,extra)=match object {
            Object::Polity(_)=>unreachable!(),
            Object::Place(i)=>{
                let p=&world.places[i];
                (skin.choose("地点","Place"),p.id.clone(),format!("{:.4} / {:.4}",p.coordinates[0],p.coordinates[1]),ui.admin.into())
            },
            Object::Administration(i)=>{
                let region=&world.admin[i];
                (skin.choose("历史行政区","Historical department"),region.id.clone(),skin.choose("法国 · 1900 年","France · 1900").into(),"TRF-GIS".into())
            }
        };
        skin.text(&mut hud_type,label,0,[x+15.,y+9.],230.,GOLD);
        crate::formal_ui::close_button(&mut panels, &mut hits, [x + width - 15., y + 8.], Action::Close);
        if can_read_object(world, ui.formal.written_world, object) {
        skin.text(&mut hud_type,object_name(world,skin,object),1,[x+15.,y+35.],270.,LIGHT);
        let context=if ui.mode==Mode::Political { &extra } else { &desc };
        skin.text(&mut hud_type,context,0,[x+15.,y+68.],270.,SUBTLE);
        if has_debug { skin.text(&mut hud_type,&id,0,[x+15.,y+151.+extra_row],270.,SUBTLE); }
        } else {
            ui.formal.ink_block(&mut panels,[x+15.,y+42.,123.,12.]);
            ui.formal.ink_block(&mut panels,[x+15.,y+72.,217.,12.]);
        }
        if let Some(mode)=facilities {
            let label=match mode {
                Mode::Economic=>skin.choose("在经济地图显示","Show in economic map"),
                Mode::Military=>skin.choose("在军事地图显示","Show in military map"),
                Mode::Geographic=>skin.choose("在地理地图显示","Show in geographic map"),
                Mode::Political=>skin.choose("在政治地图显示","Show in political map"),
            };
            ui.formal.row(&mut panels,&mut hud_type,&mut hits,[x+15.,y+139.,267.,26.],label,Some(Action::Mode(mode)),false);
        }
        ui.formal.row(&mut panels,&mut hud_type,&mut hits,[x+15.,y+103.,123.,28.],skin.choose("定位地点","Focus location"),Some(Action::Locate),false);
        if let Some(i) = transport {
            ui.formal.row(&mut panels,&mut hud_type,&mut hits,[x+147.,y+103.,135.,28.],
                skin.choose("运往此处","Transport here"),
                Some(Action::Hud(crate::formal_ui::Command::Transport("city",i))),false);
        } else {
            ui.formal.row(&mut panels,&mut hud_type,&mut hits,[x+147.,y+103.,135.,28.],skin.choose("完整资料","Full record"),Some(Action::Details),false);
        }
    }
    if ui.details {
        if let Some(object)=ui.selected {
            let readable = can_read_object(world, ui.formal.written_world, object);
            let width=504.;let x=(w-width)*0.5;let y=105.;
            panel(&mut panels,x,y,width,detail_height);
            if readable { skin.text(&mut hud_type,object_name(world,skin,object),1,[x+22.,y+16.],420.,LIGHT); }
            else { ui.formal.ink_block(&mut panels,[x+22.,y+23.,174.,11.]); }
            crate::formal_ui::close_button(&mut panels, &mut hits, [x + width - 15., y + 8.], Action::Details);
            let mut lines=match object {
                Object::Polity(_)=>Vec::new(),
                Object::Place(i)=>{
                    let p=&world.places[i];
                    let mut details=vec![format!("{}  {:.6}",skin.choose("经度","Longitude"),p.coordinates[0]),
                        format!("{}  {:.6}",skin.choose("纬度","Latitude"),p.coordinates[1])];
                    if ui.formal.debug.is_some() {
                        details.push(p.id.clone());
                        details.push(format!("{}  {}",skin.choose("地图标注等级","Map label rank"),p.rank));
                    }
                    details
                }
                Object::Administration(i)=>{
                    let mut details=vec![skin.choose("法国 · 1900 年 · TRF-GIS","France · 1900 · TRF-GIS").into()];
                    if ui.formal.debug.is_some() { details.push(world.admin[i].id.clone()); }
                    details
                }
            };
            if !opening_stations.is_empty() {
                lines.push(skin.choose("团本部驻地 · 1900-01-01", "Regimental central station · 1900-01-01").into());
                for station in opening_stations {
                    lines.push(skin.choose(&station.name_zh, &station.name).into());
                    lines.push(station.source.clone());
                }
            }
            for (i,line) in lines.iter().enumerate(){
                if readable { skin.text(&mut hud_type,line,0,[x+22.,y+75.+i as f32*28.],460.,LIGHT); }
                else { ui.formal.ink_block(&mut panels,[x+22.,y+82.+i as f32*28.,195.,11.]); }
            }
        }
    }
    if let Some(query)=ui.search {
        let x=w/2.-226.;
        panel(&mut panels,x,61.,452.,78.+ui.search_results.len() as f32*30.);
        skin.text(&mut hud_type,skin.choose("搜索地点、国家或经纬度","Search for a place, country, or coordinates"),0,[x+15.,70.],420.,LIGHT);
        skin.text(&mut hud_type,&format!("{query}_"),1,[x+15.,94.],420.,LIGHT);
        for (i,&object) in ui.search_results.iter().enumerate() {
            ui.formal.row(&mut panels,&mut hud_type,&mut hits,[x+15.,132.+i as f32*30.,420.,27.],
                if readable { object_name(world,skin,object) } else { "" },Some(Action::Select(object)),i==0);
            if !readable { ui.formal.ink_block(&mut panels,[x+25.,140.+i as f32*30.,96.,11.]); }
        }
    }
    let mut debug_right=145.;
    if crate::resource_map::available(ui.mode,ui.formal.hud.page,ui.formal.hud.menu,ui.formal.hud.market_map,ui.transport_detail.is_some()) {
        let width=(measure(a,0,ui.econ_label)+25.).clamp(219.,374.);
        let x=w-width-17.;
        let lines=ui.econ_legend.len();
        let extra=if ui.resources.is_some(){28.}else{0.};
        panel(&mut panels,x,121.,width,51.+lines as f32*20.+extra);
        if readable { text.text(a,0,ui.econ_label,[x+12.,130.],LIGHT); }
        else { ui.formal.ink_block(&mut panels,[x+12.,136.,118.,11.]); }
        for (i,(value,color)) in ui.econ_legend.iter().enumerate() {
            let y=158.+i as f32*20.;
            panels.rect(x+12.,y+6.,13.,10.,*color);
            if readable { text.text(a,0,value,[x+34.,y],SUBTLE); }
            else { ui.formal.ink_block(&mut panels,[x+34.,y+6.,86.,11.]); }
        }
        if let Some(resources)=ui.resources {
            ui.formal.row(&mut panels,&mut hud_type,&mut hits,[x+12.,166.+lines as f32*20.,width-24.,25.],
                skin.choose("资源分布","Resources"),Some(Action::Resources(crate::resource_map::Command::Toggle)),resources.open);
            if resources.open {
                crate::resource_map::draw_panel(resources,world,&ui.formal,ui.size,ui.year,&mut panels,&mut hud_type,&mut hits);
            }
        }
        debug_right=182.+lines as f32*20.+extra;
    }
    if ui.formal.hud.market_map && ui.formal.hud.menu==crate::formal_ui::Menu::None {
        if let Some(market)=ui.formal.session.and_then(|s|s.market.as_ref()) {
            use crate::formal_ui::Command::Market;
            let left=(w-506.)/2.;
            panel(&mut panels,left,64.,506.,44.);
            skin.text(&mut hud_type,&format!("{} · 点击交易地点",market.good_label),1,[left+12.,74.],273.,LIGHT);
            ui.formal.row(&mut panels,&mut hud_type,&mut hits,[left+290.,72.,91.,27.],"搜索地点",
                Some(Action::Hud(Market("search_locations",0))),false);
            ui.formal.row(&mut panels,&mut hud_type,&mut hits,[left+389.,72.,105.,27.],"返回商品",
                Some(Action::Hud(Market("market_back",0))),false);
            let mut placed=Vec::new();
            for (index,site) in market.sites.iter().enumerate() {
                let Some([x,y])=ui.camera.project(site.point,ui.size).map(|p|p.map(|n|n as f32)) else{continue;};
                if x<16.||x>w-16.||y<113.||y>h-80. {continue;}
                let area=[x-12.,y-12.,24.,24.];
                if placed.iter().any(|old|intersects(area,*old)) {continue;}
                placed.push(area);
                map.shape(&[[x,y-9.],[x+9.,y],[x,y+9.],[x-9.,y]],[28,44,40,255]);
                let ink=if site.ask.is_some(){[242,206,115,255]}else{[126,214,183,255]};
                map.shape(&[[x,y-6.],[x+6.,y],[x,y+6.],[x-6.,y]],ink);
                let span=skin.width(&site.name,0).min(148.);
                let label=[x+12.,y-9.,span+4.,20.];
                if x+span+16.<w && !occupied.iter().any(|old|intersects(label,*old)) {
                    occupied.push(label);
                    map.rect(label[0],label[1],label[2],label[3],[27,42,39,225]);
                    skin.text(&mut marker_type,&site.name,0,[label[0]+2.,label[1]],span,LIGHT);
                    hits.push(Hit{area:label,action:Action::Hud(Market("location",index))});
                }
                hits.push(Hit{area,action:Action::Hud(Market("location",index))});
            }
            if market.sites.is_empty() {
                skin.text(&mut hud_type,"暂无已知交易地点",0,[left+12.,113.],260.,LIGHT);
            }
        }
    }
    if ui.formal.hud.page==crate::formal_ui::Page::Map {
        if readable {
            let width=skin.width(ui.mouse,0).min(234.);
            skin.text(&mut hud_type,ui.mouse,0,[w-width-18.,h-48.],width+1.,SUBTLE);
        }
    }
    if let Some(detail)=ui.transport_detail {
        ui.formal.transport_detail(detail,&mut panels,&mut hud_type,&mut hits);
    }
    if !ui.formal.population_debug && !ui.formal.hud.messages && ui.country.is_none() && ui.search.is_none() && !ui.details && ui.transport_detail.is_none() {
        let left=match ui.selected{Some(Object::Polity(_))=>359.,Some(_)=>293.,None=>145.};
        ui.formal.diagnostics(&mut panels,&mut hud_type,left,debug_right);
    }
    let history_light=ui.formal.history_light();
    ui.formal.draw(&mut panels,&mut hud_art,&mut hud_type,&mut clock,&mut flags,&mut instrument,&mut hits);
    ([(map,Ink::Solid),(labels_mesh,Ink::Text),(instrument,Ink::Instrument),(history_light,Ink::HistoryLight),
      (marker_art,Ink::HudArt),(marker_type,Ink::HudText),
      (panels,Ink::Solid),(text,Ink::Text),(flags,Ink::Flag),(ui.formal.clock_gears(),Ink::ClockGears),(hud_art,if ui.formal.hud.mechanical.hidden {Ink::HudArt}else{Ink::HudArtGlass}),(clock,Ink::Solid),(hud_type,Ink::HudText)],hits)
}

pub fn object_name<'a>(world:&'a World,skin:&'a crate::formal_ui::Skin,object:Object)->&'a str {
    match object {
        Object::Place(i)=>{let p=&world.places[i];if skin.english()||p.name_zh.is_empty(){&p.name}else{&p.name_zh}},
        Object::Polity(i)=>skin.country_name(&world.polities[i]),
        Object::Administration(i)=>skin.division_name(&world.admin[i]),
    }
}
