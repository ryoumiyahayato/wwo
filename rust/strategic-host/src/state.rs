use crate::{politics::PoliticalVisuals,timeline::{self,Date,Timeline},world::World};
use serde::{Deserialize,Serialize};
use std::{collections::BTreeMap,io,path::Path};

const ECON:[[u8;4];5]=[[221,232,188,255],[171,204,155,255],[113,166,131,255],[62,124,105,255],[35,86,84,255]];
const STRUCTURE:[[u8;4];5]=[[145,164,119,255],[178,126,89,255],[100,143,166,255],[155,128,167,255],[89,100,99,255]];
#[derive(Default,Deserialize)]
pub struct EmploymentReference {rows:BTreeMap<String,Employment>}
#[derive(Deserialize)]
struct Employment {agriculture:u16,industry:u16,services:u16}
impl EmploymentReference {
    pub fn open(root:&Path)->io::Result<Self> {
        let file=std::fs::File::open(root.join("economic-structure-r68.json"))?;
        Ok(serde_json::from_reader(file)?)
    }
    fn color(&self,id:&str)->[u8;4] {
        let Some(row)=self.rows.get(id) else{return STRUCTURE[4];};
        let mut shares=[(row.agriculture,0),(row.industry,1),(row.services,2)];
        if shares.iter().map(|(share,_)|u32::from(*share)).sum::<u32>()!=10000{return STRUCTURE[4];}
        shares.sort_unstable_by_key(|(share,_)|std::cmp::Reverse(*share));
        STRUCTURE[if shares[0].0-shares[1].0<500{3}else{shares[0].1}]
    }
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Economy {
    pub source:String,pub metric:String,pub unit:String,pub date:Date,
    pub thresholds:Vec<f64>,pub values:BTreeMap<String,f64>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Snapshot {schema:u32,date:Date,economy:Option<Economy>,session:Option<crate::formal_ui::Session>,lobby:Option<crate::lobby::Lobby>}
pub struct State {pub date:Date,pub economy:Option<Economy>,pub timeline:Option<Timeline>,pub session:Option<crate::formal_ui::Session>,pub lobby:Option<crate::lobby::Lobby>}
impl State {
    pub fn new()->Self {Self{date:Date::new(1900,1,1),economy:None,timeline:None,session:None,lobby:None}}
    pub fn input(&mut self,path:&Path,world:&World)->io::Result<()> {
        let file:Snapshot=timeline::read(path,2*1024*1024)?;
        if file.schema!=1 || !file.date.valid() {return Err(io::Error::other("invalid world state"));}
        if let Some(e)=&file.economy {
            if e.source.trim().is_empty() || e.metric.trim().is_empty() || e.unit.trim().is_empty() || !e.date.valid()
                || e.thresholds.len()>4 || e.thresholds.iter().any(|x|!x.is_finite())
                || e.thresholds.windows(2).any(|w|w[0]>=w[1])
                || e.values.iter().any(|(id,v)|!v.is_finite() || !world.polities.iter().any(|p|id.strip_prefix("state:")==Some(&p.id))) {
                return Err(io::Error::other("invalid economic source or entity ID"));
            }
        }
        if file.session.as_ref().is_some_and(|session|!session.valid()) {return Err(io::Error::other("invalid formal session view"));}
        self.date=file.date;self.economy=file.economy;self.session=file.session;self.lobby=file.lobby;Ok(())
    }
    pub fn palette(&self,world:&World,date:&str,visuals:&PoliticalVisuals,employment:&EmploymentReference)->Vec<u8> {
        let mut rgba=vec![0;2048];
        for (i,p) in world.polities.iter().enumerate() {
            if !p.active(date){continue;}
            let start=(i+1)*4;

            rgba[start..start+4].copy_from_slice(&visuals.record(i).fallback_color());
            if let Some(e)=self.economy.as_ref().filter(|e|e.date==self.date) {
                if let Some(v)=e.values.get(&format!("state:{}",p.id)) {
                    let start=start+1024;
                    rgba[start..start+4].copy_from_slice(&ECON[e.thresholds.partition_point(|n|v>=n)]);
                }
            }else {
                let start=start+1024;
                rgba[start..start+4].copy_from_slice(&employment.color(&p.id));
            }
        }
        rgba
    }
    pub fn legend(&self)->(String,Vec<(String,[u8;4])>) {
        let unknown=("No value".into(),[147,147,131,255]);
        let Some(e)=self.economy.as_ref().filter(|e|e.date==self.date) else {
            return ("Employment structure / circa 1900".into(),["Agriculture","Industry","Services","Mixed","No reference"]
                .into_iter().zip(STRUCTURE).map(|(name,color)|(name.to_owned(),color)).collect());
        };
        let mut entries=Vec::new();
        for (i,color) in ECON.iter().enumerate().take(e.thresholds.len()+1) {
            let label=match (i.checked_sub(1).map(|n|e.thresholds[n]),e.thresholds.get(i)) {
                (None,None)=>format!("Reported {}",e.unit),(None,Some(b))=>format!("< {b} {}",e.unit),
                (Some(a),None)=>format!(">= {a} {}",e.unit),(Some(a),Some(b))=>format!("{a} to < {b} {}",e.unit),
            };
            entries.push((label,*color));
        }
        entries.push(unknown);(format!("{} / {}",e.metric,e.source),entries)
    }
}
#[derive(Serialize)]
#[serde(tag="kind",rename_all="snake_case")]
pub enum Request<'a> {
    Inspect { id:&'a str }, Locate { id:&'a str }, SetMapMode { mode:&'static str },
    FinancePage {page:usize}, OpenSlots {mode:&'static str}, CloseSlots, Clock {speed:u32,serial:u64}, HostAction {action:&'a str},
    ClockTick { world: &'a str, serial: u64, expected_minute: u64, speed: u32, minutes: i64 },
    Interface {volume:f64,locale:&'static str},
    Market {verb:&'a str,id:&'a str,site:&'a str,quantity:u64,token:u64,viewport:[u32;2]},
    Training {verb:&'a str},
    Relations {verb:&'a str,id:&'a str},
    Lobby {verb:&'static str,polity:&'a str,slot:u8},
}
impl Request<'_> {
    pub fn output(&self,path:Option<&Path>)->io::Result<()> {
        if let Some(path)=path {
            use std::io::Write;
            let mut f=std::fs::OpenOptions::new().create(true).append(true).open(path)?;
            let mut record=serde_json::to_vec(self)?;record.push(b'\n');f.write_all(&record)?;
        }
        Ok(())
    }
}
impl crate::ui::Mode {
    pub fn key(self)->&'static str {match self{Self::Geographic=>"geographic",Self::Political=>"political",Self::Economic=>"economic",Self::Military=>"military"}}
}
