use crate::{formal_ui::{self,Display,Slot,IVORY,MUTED},overlay::Mesh,ui::{Action,Hit},world::World};
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

#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub enum Page {#[default] Home,Selection,Load,Settings,Themes,Migration(Status,usize)}
#[derive(Clone,Copy)]
pub enum Command {Page(Page),Country(usize),Enter,Load(u8),Exit}

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

    pub fn lobby(&self,world:&World,state:Option<&Lobby>,page:Page,selection:usize,waiting:bool)
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
                let width=(w*0.43).min(430.);
                let x=w-width-32.;let y=(h-400.)*0.5;
                formal_ui::panel(&mut panels,[x,y,width,400.],[12,22,31,241]);
                self.skin.sprite(&mut art,"crest",[x+width*0.5-97.,y-50.,194.,55.]);
                self.skin.text(&mut text,"国家档案  /  1900",1,[x+22.,y+15.],width-44.,IVORY);
                let selected=world.polities.get(selection);
                let opening=state.and_then(|s|selected.and_then(|p|s.choices.iter().find(|row|row.id.strip_prefix("state:")==Some(p.id.as_str()))));
                if let Some(p)=selected {
                    let label=opening.map(|o|o.label.as_str()).unwrap_or(&p.name_zh);
                    self.skin.text(&mut text,label,2,[x+103.,y+68.],width-120.,IVORY);
                    if let Some(slot)=self.flags{flags.flag([x+22.,y+63.,68.,45.],slot);}
                }
                let identity=opening.map(|o|format!("{} · 居民 · 未就业",o.place)).unwrap_or_else(||"该地区暂无可选人物。".into());
                self.skin.text(&mut text,"开局身份",0,[x+22.,y+118.],width-44.,MUTED);
                self.skin.text(&mut text,&identity,0,[x+22.,y+143.],width-44.,IVORY);
                if let Some(s)=state{
                    for (i,choice) in s.choices.iter().enumerate(){
                        if let Some(index)=world.polities.iter().position(|p|choice.id.strip_prefix("state:")==Some(p.id.as_str())){
                            let col=(i%2) as f32;let line=(i/2) as f32;let cell=(width-52.)*0.5;
                            self.row(&mut panels,&mut text,&mut hits,[x+22.+col*(cell+8.),y+187.+line*32.,cell,27.],
                                &choice.label,(!busy).then_some(action(Command::Country(index))),index==selection);
                        }
                    }
                }
                self.row(&mut panels,&mut text,&mut hits,[x+22.,y+287.,width-44.,32.],"进入世界",
                    (opening.is_some()&&state.is_some_and(|s|s.selection_ready)&&!busy).then_some(action(Command::Enter)),true);
                self.row(&mut panels,&mut text,&mut hits,[x+22.,y+330.,width-44.,30.],"返回主菜单",
                    (!busy).then_some(action(Command::Page(Page::Home))),false);
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
}

pub(crate) fn action(command:Command)->Action {Action::Hud(formal_ui::Command::Lobby(command))}
