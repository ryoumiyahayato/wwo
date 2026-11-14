use crate::{camera::Camera,overlay::{Atlas,Mesh},world::{Place,Polity,World}};
use std::cmp::Ordering;
use std::collections::HashSet;
use crate::politics::PoliticalVisuals;
#[derive(Clone,Copy)]
pub enum Ink { HudArtGlass, ClockGears, Solid, Text, Flag, HudArt, HudText, Instrument, MenuArt, Loading, HistoryLight }

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
pub enum Action {
    Mode(Mode),Home,Back,Search,Close,Details,Locate,Capital,Select(Object),AdminPage(i32),
    Hud(crate::formal_ui::Command),
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
    pub admin_page:Option<usize>,
    pub search:Option<&'a str>,
    pub search_results:&'a [Object],
    pub econ_label:&'a str,
    pub econ_legend:&'a [(String,[u8;4])],
    pub mouse:&'a str,
    pub labels:bool,
    pub formal:crate::formal_ui::Display<'a>,
}

pub fn active(date:&str,from:&str,to:&str)->bool {(from.is_empty() || date>=from) && (to.is_empty() || date<to)}
pub fn name(world:&World,obj:Object)->&str {
    match obj {Object::Place(i)=>&world.places[i].name,Object::Polity(i)=>&world.polities[i].name,Object::Administration(i)=>&world.admin[i].name}
}
pub fn labels<'a>(world:&'a World,ui:&Ui<'_>)->Vec<Label<'a>> {
    let mut list=Vec::new();
    let threshold=ui.camera.mpp;
    if ui.mode==Mode::Political && World::active_politics(ui.date) && threshold>570. {
        for (i,p) in world.polities.iter().enumerate() {
            if p.rank>2 && threshold>6100. || !active(ui.date,&p.from_date,&p.to_date) {continue;}
            if let Some(xy)=ui.camera.project(p.coordinates,ui.size) {
                list.push(Label{object:Object::Polity(i),xy:xy.map(|v|v as f32),name:&p.name,rank:p.rank+1});
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
fn title(m:&mut Mesh,a:&Atlas,variant:usize,value:&str,x:f32,y:f32) {m.text(a,variant,value,[x,y],LIGHT);}
fn panel(m:&mut Mesh,x:f32,y:f32,w:f32,h:f32) {
    m.rect(x,y,w,h,PANEL);m.rect(x,y,w,1.,GOLD);m.rect(x,y+h-1.,w,1.,LINE);
}
fn button(m:&mut Mesh,t:&mut Mesh,a:&Atlas,hits:&mut Vec<Hit>,area:[f32;4],label:&str,action:Action,on:bool) {
    let [x,y,w,h]=area;
    m.rect(x,y,w,h,if on{[63,66,58,255]}else{[33,45,51,248]});
    if on{m.rect(x,y+h-2.,w,2.,GOLD);}
    let tx=x+(w-measure(a,0,label))*0.5;
    t.text(a,0,label,[tx,y+3.],LIGHT);
    hits.push(Hit{area,action});
}
fn intersects([x,y,w,h]:[f32;4],[a,b,c,d]:[f32;4])->bool{x<a+c && x+w>a && y<b+d && y+h>b}

fn place_symbols(world:&World,ui:&Ui<'_>,occupied:&mut Vec<[f32;4]>,previous:&mut HashSet<usize>,
    art:&mut Mesh,text:&mut Mesh,map:&mut Mesh,hits:&mut Vec<Hit>)
{
    use crate::formal_ui::{Command, Menu, IVORY};
    let [w,h]=ui.size.map(|n|n as f32);
    let skin=ui.formal.skin;
    let regional=ui.camera.level!=crate::camera::Level::World;
    let [mx,my]=ui.formal.cursor.map(|n|n as f32);
    let mut candidates=Vec::new();
    for (index,place) in world.places.iter().enumerate() {
        if !place.display_symbol || !active(ui.date,&place.from_date,&place.to_date) {continue;}
        let chosen=ui.selected==Some(Object::Place(index));
        let Some(spec)=skin.map_symbols.get(&place.symbol) else {continue;};
        let mut limit=if regional {spec.region_max_mpp} else {spec.world_max_mpp};
        if place.reference {
            if !regional {continue;}
            limit=limit.min(place.max_mpp);
        }
        let retained=previous.contains(&index);
        if !chosen && ((!regional&&!spec.world)||ui.camera.mpp>limit*if retained {1.12} else {1.}) {continue;}
        let Some(point)=ui.camera.project(place.coordinates,ui.size) else {continue;};
        let [x,y]=point.map(|n|n as f32);
        let kind=if regional&&ui.camera.mpp<=300.&&place.symbol=="settlement" {"town"} else {place.symbol.as_str()};
        let px=spec.screen_px*if regional {1.} else {0.78};
        let area=[x-px/2.,y-px/2.,px,px];
        if area[0]<0.||area[1]<0.||area[0]+px>w||area[1]+px>h {continue;}
        candidates.push((index,place,kind,area,chosen,retained,spec.priority));
    }
    candidates.sort_by(|a,b| b.4.cmp(&a.4).then(b.6.cmp(&a.6)).then(b.5.cmp(&a.5)).then(a.1.id.cmp(&b.1.id)));
    let mut placed=Vec::new();
    previous.clear();
    for (i,place,kind,[x,y,px,_],chosen,_,_) in candidates {
        if placed.len()>=(if regional {160} else {24}) {break;}
        if !chosen&&occupied.iter().any(|&old|intersects([x-2.,y-2.,px+4.,px+4.],old)) {continue;}
        occupied.push([x-2.,y-2.,px+4.,px+4.]);
        let pick=[x-4.,y-4.,px+8.,px+8.];
        let hover=ui.formal.hud.menu==Menu::None && place.selectable
            && mx>=pick[0] && mx<pick[0]+pick[2] && my>=pick[1] && my<pick[1]+pick[3];
        let asset=format!("map_{kind}");
        skin.tinted_sprite(art,&asset,[x-1.25,y-1.25,px+2.5,px+2.5],[25,38,36,217]);
        let color=if place.selectable {[255;4]} else {[184,184,184,153]};
        skin.tinted_sprite(art,&asset,[x,y,px,px],color);
        if chosen {map.line([x+px/2.-4.,y+px+2.],[x+px/2.+4.,y+px+2.],1.5,GOLD);}
        if place.selectable {hits.push(Hit{area:pick,action:Action::Select(Object::Place(i))});}
        previous.insert(i);
        placed.push((place,[x+px+4.,y+px*0.5-7.],chosen,hover));
    }
    for (place,[x,y],chosen,hover) in placed {
        if !ui.labels&&!place.reference&&!chosen&&!hover {continue;}
        let name=if skin.english()||place.name_zh.is_empty(){&place.name}else{&place.name_zh};
        let width=skin.width(name,0);
        let area=[x-2.,y-2.,width+4.,19.];
        if x+width>w||(!chosen&&occupied.iter().any(|&old|intersects(area,old))) {continue;}
        occupied.push(area);
        for [dx,dy] in [[-1.,0.],[1.,0.],[0.,-1.],[0.,1.]] {
            skin.text(text,name,0,[x+dx,y+dy],width+1.,[41,48,43,230]);
        }
        skin.text(text,name,0,[x,y],width+1.,IVORY);
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

pub fn compose(world:&World,a:&Atlas,visuals:&PoliticalVisuals,ui:Ui<'_>,markers:&mut HashSet<usize>)->([(Mesh,Ink);11],Vec<Hit>) {
    let [w,h]=ui.size.map(|x|x as f32);
    let mut map=Mesh::default();let mut labels_mesh=Mesh::default();
    let mut panels=Mesh::default();let mut text=Mesh::default();let mut flags=Mesh::default();
    let mut hud_art=Mesh::default();let mut hud_type=Mesh::default();let mut instrument=Mesh::default();let mut clock=Mesh::default();
    let mut hits=Vec::new();
    if ui.formal.hud.menu.modal() {
        ui.formal.draw(&mut panels,&mut hud_art,&mut hud_type,&mut clock,&mut flags,&mut instrument,&mut hits);
        return ([(map,Ink::Solid),(labels_mesh,Ink::Text),(instrument,Ink::Instrument),(Mesh::default(),Ink::HistoryLight),
            (panels,Ink::Solid),(text,Ink::Text),(flags,Ink::Flag),(ui.formal.clock_gears(),Ink::ClockGears),(hud_art,if ui.formal.hud.mechanical.hidden {Ink::HudArt}else{Ink::HudArtGlass}),(clock,Ink::Solid),(hud_type,Ink::HudText)],hits);
    }
    let mut occupied=vec![[0.,0.,w,55.],[0.,h-51.,w,51.]];
    if ui.selected.is_some(){occupied.push([12.,75.,308.,280.]);}
    if let Some(rect)=ui.formal.page_rect(){occupied.push(rect);}
    if ui.details {occupied.push([w/2.-255.,104.,510.,if ui.admin_page.is_some(){395.}else{302.}]);}
    if let Some(Object::Administration(i))=ui.selected.filter(|_|ui.mode==Mode::Political) {
        for ring in &world.admin[i].outlines {
            let mut previous:Option<[f32;2]>=None;
            for &point in ring {
                let next=ui.camera.project(point,ui.size).map(|p|p.map(|v|v as f32));
                if let (Some([x,y]),Some([a,b]))=(previous,next) {
                    if x.max(a)>=0. && x.min(a)<=w && y.max(b)>=0. && y.min(b)<=h {
                        map.line([x,y],[a,b],1.8,[247,197,86,255]);
                    }
                }
                previous=next;
            }
        }
    }
    for label in labels(world,&ui).into_iter().filter(|_|ui.labels) {
        if occupied.len()>95 {break;}
        let [x,y]=label.xy;
        let variant=usize::from(label.rank==0 && ui.camera.mpp<10000.);
        let length=measure(a,variant,label.name);
        let pad=-length*0.5;
        let area=[x+pad-4.,y-10.,length+10.,22.];
        if x<8. || x>w-8. || y<55. || y>h-51. || area[0]<4. || area[0]+area[2]>w-3.
            || occupied.iter().any(|old|intersects(area,*old)) {continue;}
        occupied.push(area);
        let selected=Some(label.object)==ui.selected;
        let top=y-13.;
        for [dx,dy] in [[-1.,0.],[1.,0.],[0.,-1.],[0.,1.]] {
            labels_mesh.text(a,variant,label.name,[x+pad+dx,top+dy],[16,28,30,230]);
        }
        labels_mesh.text(a,variant,label.name,[x+pad,top],if selected{[255,222,138,255]}else{LIGHT});
    }
    place_symbols(world,&ui,&mut occupied,markers,&mut hud_art,&mut hud_type,&mut map,&mut hits);
    if let Some(object)=ui.selected.filter(|o|ui.formal.hud.page==crate::formal_ui::Page::Map&&(!matches!(o,Object::Polity(_))||ui.admin_page.is_some())) {
        let x=17.;let y=73.;let width=300.;
        panel(&mut panels,x,y,width,213.);
        let (label,id,desc,extra)=match object {
            Object::Polity(i)=>{
                let p=&world.polities[i];
                let flag=visuals.record(i);
                if flag.active(ui.date) && !ui.details {flags.flag([x+211.,y+85.,71.,37.],flag.flag);}
                ("Political entity",format!("state:{}",p.id),p.status.replace('_'," "),if p.capital.is_empty(){String::new()}else{format!("Capital   {}",p.capital)})
            },
            Object::Place(i)=>{
                let p=&world.places[i];
                ("Place",p.id.clone(),format!("{:.4} / {:.4}",p.coordinates[0],p.coordinates[1]),ui.admin.into())
            },
            Object::Administration(i)=>{
                let region=&world.admin[i];
                ("Historical department",region.id.clone(),"France / 1900".into(),"Boundary reference / TRF-GIS".into())
            }
        };
        text.text(a,0,label,[x+15.,y+9.],GOLD);
        button(&mut panels,&mut text,a,&mut hits,[x+width-40.,y+9.,27.,25.],"x",Action::Close,false);
        title(&mut text,a,1,name(world,object),x+15.,y+35.);
        text.text(a,0,&id,[x+15.,y+67.],SUBTLE);
        text.text(a,0,&desc,[x+15.,y+93.],LIGHT);
        text.text(a,0,&extra,[x+15.,y+118.],LIGHT);

        button(&mut panels,&mut text,a,&mut hits,[x+15.,y+174.,123.,28.],"Map focus",Action::Locate,false);
        button(&mut panels,&mut text,a,&mut hits,[x+147.,y+174.,135.,28.],"Full record",Action::Details,false);
    }
    if ui.details && ui.admin_page.is_none() && !matches!(ui.selected,Some(Object::Polity(_))) {
        if let Some(object)=ui.selected {
            let x=w/2.-252.;let y=105.;
            panel(&mut panels,x,y,504.,294.);
            title(&mut text,a,2,name(world,object),x+22.,y+16.);
            button(&mut panels,&mut text,a,&mut hits,[x+454.,y+15.,29.,27.],"x",Action::Details,false);
            match object {
                Object::Polity(i)=>{
                    let flag=visuals.record(i);
                    if flag.active(ui.date) {flags.flag([x+390.,y+69.,89.,46.],flag.flag);}
                    polity_detail(world,&world.polities[i],x,y,a,&mut panels,&mut text,&mut hits);
                    if world.polities[i].id=="country_fra" {
                        button(&mut panels,&mut text,a,&mut hits,[x+255.,y+245.,224.,31.],"Historical departments",Action::AdminPage(0),false);
                    }
                }
                Object::Place(i)=>place_detail(&world.places[i],x,y,a,&mut text),
                Object::Administration(i)=>{
                    title(&mut text,a,0,&world.admin[i].id,x+22.,y+75.);
                    title(&mut text,a,0,"Historical geography   France, 1900 / TRF-GIS",x+22.,y+111.);
                    button(&mut panels,&mut text,a,&mut hits,[x+22.,y+245.,225.,31.],"Show boundary on map",Action::Locate,false);
                }
            }
        }
    }
    if let Some(page)=ui.admin_page {
        let x=w/2.-252.;let y=105.;
        let rows:Vec<_>=world.admin.iter().enumerate().skip(page*8).take(8).collect();
        panel(&mut panels,x,y,504.,393.);
        title(&mut text,a,1,"French historical departments / 1900",x+18.,y+11.);
        for (r,(index,record)) in rows.iter().enumerate() {
            button(&mut panels,&mut text,a,&mut hits,[x+20.,y+52.+r as f32*32.,464.,27.],
                &record.name,Action::Select(Object::Administration(*index)),false);
        }
        if page>0 {
            button(&mut panels,&mut text,a,&mut hits,[x+20.,y+330.,110.,29.],"Previous",Action::AdminPage(-1),false);
        }
        if (page+1)*8<world.admin.len() {
            button(&mut panels,&mut text,a,&mut hits,[x+137.,y+330.,110.,29.],"Next",Action::AdminPage(1),false);
        }
        button(&mut panels,&mut text,a,&mut hits,[x+371.,y+330.,110.,29.],"Back",Action::AdminPage(-2),false);
    }
    if let Some(query)=ui.search {
        let x=w/2.-226.;
        panel(&mut panels,x,61.,452.,78.+ui.search_results.len() as f32*30.);
        title(&mut text,a,0,"Locate a place, polity, or longitude latitude",x+15.,70.);
        title(&mut text,a,1,&format!("{query}_"),x+15.,94.);
        for (i,&object) in ui.search_results.iter().enumerate() {
            button(&mut panels,&mut text,a,&mut hits,[x+15.,132.+i as f32*30.,420.,27.],name(world,object),Action::Select(object),i==0);
        }
    }
    let mut debug_right=145.;
    if ui.mode==Mode::Economic && ui.formal.hud.page!=crate::formal_ui::Page::Market
        && ui.formal.hud.menu==crate::formal_ui::Menu::None {
        let width=(measure(a,0,ui.econ_label)+25.).clamp(219.,374.);
        let x=w-width-17.;
        let lines=ui.econ_legend.len();
        panel(&mut panels,x,121.,width,51.+lines as f32*20.);
        text.text(a,0,ui.econ_label,[x+12.,130.],LIGHT);
        for (i,(value,color)) in ui.econ_legend.iter().enumerate() {
            let y=158.+i as f32*20.;
            panels.rect(x+12.,y+6.,13.,10.,*color);
            text.text(a,0,value,[x+34.,y],SUBTLE);
        }
        debug_right=182.+lines as f32*20.;
    }
    if ui.formal.hud.page==crate::formal_ui::Page::Map {
        let y=h-45.;
        for (i,(label,action)) in [("Locate",Action::Search),("Back",Action::Back),("Globe",Action::Home)].into_iter().enumerate(){
            button(&mut panels,&mut text,a,&mut hits,[w-215.+i as f32*65.,y-35.,61.,25.],label,action,false);
        }
        text.text(a,0,ui.mouse,[w-215.,h-49.],SUBTLE);
    }
    if !ui.formal.hud.messages && ui.admin_page.is_none() && ui.search.is_none() && !ui.details {
        let left=match ui.selected{Some(Object::Polity(_))=>359.,Some(_)=>293.,None=>145.};
        ui.formal.diagnostics(&mut panels,&mut hud_type,left,debug_right);
    }
    let history_light=ui.formal.history_light();
    if ui.admin_page.is_some(){
        let mut formal=ui.formal;
        formal.selected_polity=None;
        formal.draw(&mut panels,&mut hud_art,&mut hud_type,&mut clock,&mut flags,&mut instrument,&mut hits);
    }else{
    ui.formal.draw(&mut panels,&mut hud_art,&mut hud_type,&mut clock,&mut flags,&mut instrument,&mut hits);
    }
    ([(map,Ink::Solid),(labels_mesh,Ink::Text),(instrument,Ink::Instrument),(history_light,Ink::HistoryLight),
      (panels,Ink::Solid),(text,Ink::Text),(flags,Ink::Flag),(ui.formal.clock_gears(),Ink::ClockGears),(hud_art,if ui.formal.hud.mechanical.hidden {Ink::HudArt}else{Ink::HudArtGlass}),(clock,Ink::Solid),(hud_type,Ink::HudText)],hits)
}

fn polity_detail(world:&World,p:&Polity,x:f32,y:f32,a:&Atlas,m:&mut Mesh,t:&mut Mesh,hits:&mut Vec<Hit>) {
    let authority=world.polities.iter().find(|v|v.id==p.controller_id).map(|v|v.name.as_str()).unwrap_or("No linked controller");
    let lines=[
        format!("WWO runtime ID   state:{}",p.id),format!("Historical source ID   {}",p.id),
        format!("Recorded validity   {}  to  {}",p.from_date,p.to_date),
        format!("Status   {}",p.status.replace('_'," ")),format!("Authority reference   {authority}"),
        "Boundary source   WWO / CShapes 2.0, 1900 snapshot".into(),
    ];
    for (i,value) in lines.iter().enumerate() {t.text(a,0,value,[x+23.,y+73.+i as f32*25.],LIGHT);}
    if !p.capital.is_empty() {
        button(m,t,a,hits,[x+22.,y+245.,225.,31.],&format!("Locate {}",p.capital),Action::Capital,false);
    }
}
fn place_detail(p:&Place,x:f32,y:f32,a:&Atlas,t:&mut Mesh) {
    for (i,s) in [p.id.clone(),format!("Longitude   {:.6}",p.coordinates[0]),format!("Latitude   {:.6}",p.coordinates[1]),
        format!("Strategic rank   {}",p.rank),"Source   WWO place catalogue".into()].into_iter().enumerate() {
        t.text(a,0,&s,[x+22.,y+75.+i as f32*28.],LIGHT);
    }
}
