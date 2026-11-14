use crate::{camera::{dot,frame,Camera,V3},compact::Pack};
use serde::Deserialize;
use std::{collections::{HashMap,HashSet},fs::File,io,path::{Path,PathBuf},sync::mpsc,time::Instant};
use winit::event_loop::EventLoopProxy;

#[derive(Clone, Deserialize)]
pub struct Tile {
    pub path: String,
    pub level:u32,
    pub core:[f64;4],
    pub bounds:[f64;4],
    pub group:[f64;4],
    pub source:String,
    pub size:[u32;2],
    pub cover:bool,
    #[serde(default)]
    pub printed:u8,
    pub city:bool,
    pub ids:bool,
    #[serde(default)]
    pub surface_span:u32,
    #[serde(default)]
    pub surface_max_mpp:f64,
    #[serde(default)]
    pub surface_fade_mpp:f64,
    #[serde(default)]
    pub surface_inset:f64,
}
impl Tile {
    pub fn anchor(&self)->(V3,f64) {
        let [w,s,e,n]=self.core;
        let center=frame([(w+e)*0.5,(s+n)*0.5])[2];
        let radius=[(w,s),(w,n),(e,s),(e,n)].into_iter()
            .map(|(x,y)|dot(center,frame([x,y])[2]).clamp(-1.,1.).acos())
            .fold(0.,f64::max);
        (center,radius+1e-6)
    }
    pub fn weight(&self,mpp:f64)->f32 {
        use crate::camera::smooth;
        if self.surface_span>0 {
            return (1.-smooth(self.surface_fade_mpp,self.surface_max_mpp,mpp)) as f32;
        }
        match self.level {
            1 => (1.-smooth(2900.,5900.,mpp)) as f32,
            3 if self.city => (1.-smooth(150.,380.,mpp)) as f32,
            2 if self.source.starts_with("Paris Basin") => (1.-smooth(500.,1350.,mpp)) as f32,
            2 => (1.-smooth(550.,1450.,mpp)) as f32,
            4 => (1.-smooth(78.,180.,mpp)) as f32,
            _ => 1.,
        }
    }

    pub fn cover_size(&self)->usize {
        let [mut width,mut height]=self.size;
        if !self.cover {return 0;}
        let mut size=(width*height*4) as usize;
        if self.surface_span==0 {return size;}
        while width>1||height>1 {
            width=(width/2).max(1);
            height=(height/2).max(1);
            size+=(width*height*4) as usize;
        }
        size
    }

    pub fn data_size(&self)->usize {
        self.size.iter().product::<u32>() as usize * (4+usize::from(self.city)*2+usize::from(self.ids)*2)
            + self.cover_size()
    }

    pub fn offset_of(&self,[lon,lat]:[f64;2])->usize {
        let [w,s,e,n]=self.bounds;
        let [x,y]=self.size;
        let u=(((lon-w)/(e-w))*f64::from(x)).floor().clamp(0.,f64::from(x-1)) as usize;
        let v=(((n-lat)/(n-s))*f64::from(y)).floor().clamp(0.,f64::from(y-1)) as usize;
        u+v*x as usize
    }
}

#[derive(Deserialize)]
pub struct Place {
    pub id:String,
    pub name:String,
    #[serde(default)] pub name_zh:String,
    #[serde(default)] pub symbol:String,
    #[serde(default)] pub reference:bool,
    #[serde(default)] pub display_symbol:bool,
    #[serde(default="selectable_place")] pub selectable:bool,
    pub coordinates:[f64;2],
    pub rank:u32,
    pub max_mpp:f64,
    pub from_date:String,
    pub to_date:String,
}
fn selectable_place()->bool {true}
#[derive(Deserialize)]
pub struct Polity {
    pub id:String,
    pub name:String,
    #[serde(default)]
    pub name_zh:String,
    pub capital:String,
    pub coordinates:[f64;2],
    pub capital_coordinates:[f64;2],
    pub status:String,
    pub controller_id:String,
    pub from_date:String,
    pub to_date:String,
    pub rank:u32,
    #[serde(default)]
    pub display_only:bool,
    #[serde(default)]
    pub geometry_feature_id:String,
    #[serde(default)]
    pub authority_id:String,
    #[serde(default)]
    pub boundary_kind:String,
    #[serde(default)]
    pub authority_note:String,
    #[serde(default)]
    pub source_geometry_date:String,
}
impl Polity {
    pub fn map_id(&self) -> String {
        if self.display_only {self.id.clone()} else {format!("state:{}",self.id)}
    }
    pub fn active(&self,date:&str) -> bool {
        World::active_politics(date) && crate::ui::active(date,&self.from_date,&self.to_date)
    }
}
#[derive(Deserialize)]
pub struct Admin {pub id:String,pub name:String,pub bounds:[f64;4],pub outlines:Vec<Vec<[f64;2]>>}
#[derive(Deserialize)]
pub struct World {
    pub tiles:Vec<Tile>,
    pub places:Vec<Place>,
    pub polities:Vec<Polity>,
    pub admin:Vec<Admin>,
}
pub struct Pixels {
    pub terrain:Vec<u8>,
    pub cover:Vec<u8>,
    pub city:Vec<u8>,
    pub ids:Vec<u8>,
}
impl Pixels {
    pub fn read(root:&Path,tile:&Tile)->io::Result<Self> {
        let pack=Pack::open(&root.join(&tile.path))?;
        let len=(tile.size[0]*tile.size[1]) as usize;
        let optional=|enabled,key,size| if enabled {pack.block(key,size)} else {Ok(Vec::new())};
        Ok(Self {
            terrain:pack.block("render/terrain",len*4)?,
            cover:optional(tile.cover,"render/cover",tile.cover_size())?,
            city:optional(tile.city,"render/city",len*2)?,
            ids:optional(tile.ids,"render/polity",len*2)?,
        })
    }
}
impl World {
    pub fn open(path:&Path)->io::Result<Self> {Ok(serde_json::from_reader(File::open(path)?)?)}
    pub fn active_politics(date:&str)->bool { ("1900-01-01".."1901-01-01").contains(&date) }
}
pub struct Index {
    cells:HashMap<(i32,i32),Vec<usize>>,
    anchors:Vec<(V3,f64)>,
}
impl Index {
    pub fn new(tiles:&[Tile])->Self {
        let mut cells=HashMap::<_,Vec<_>>::new();
        let anchors=tiles.iter().map(Tile::anchor).collect();
        for (id,tile) in tiles.iter().enumerate().skip(1) {
            let [w,s,e,n]=tile.core.map(|a|(a/5.).floor() as i32);
            for y in s..=n { for x in w..=e {cells.entry((x,y)).or_default().push(id);} }
        }
        Self {cells,anchors}
    }
    pub fn visible(&self,world:&World,camera:&Camera,size:[u32;2],prefetch:bool)->Vec<usize> {
        let extra=if prefetch {165.} else {0.};
        let angle=camera.extent(size,extra);
        let center=camera.axes[2];
        let [lon,lat]=camera.coordinates();
        let deg=angle.to_degrees();
        let polar=lat.abs()+deg>=90.;
        let dx=if polar {180.} else {(angle.sin()/lat.to_radians().cos()).clamp(0.,1.).asin().to_degrees()};
        let mut candidates=HashSet::new();
        let west=((lon-dx)/5.).floor() as i32;
        let east=((lon+dx)/5.).floor() as i32;
        for y in (((lat-deg).max(-90.))/5.).floor() as i32..=(((lat+deg).min(90.))/5.).floor() as i32 {
            for x in west..=east {
                let x=(x+36).rem_euclid(72)-36;
                if let Some(ids)=self.cells.get(&(x,y)) {candidates.extend(ids.iter().copied());}
            }
        }
        let mut result:Vec<_>=candidates.into_iter().filter_map(|id| {
            let tile=&world.tiles[id];
            let (axis,radius)=self.anchors[id];
            let max=if tile.surface_span>0 {tile.surface_max_mpp} else {
                match tile.level {1=>if prefetch {8500.} else {5900.},3 if tile.city=>if prefetch {650.} else {380.},4=>if prefetch {240.} else {180.},_=>if prefetch {1900.} else {1450.}}
            };
            let proximity=dot(axis,center);
            (camera.mpp<max && proximity>=(radius+angle).min(std::f64::consts::PI).cos()).then_some((id,proximity,tile.level))
        }).collect();
        result.sort_by(|a,b| a.2.cmp(&b.2).then_with(||b.1.total_cmp(&a.1)).then(a.0.cmp(&b.0)));
        let surface=self.region_pages(world,camera,size,&result);
        result.retain(|row|world.tiles[row.0].surface_span==0||surface.contains(&row.0));
        result.into_iter().map(|r|r.0).collect()
    }

    fn region_pages(&self,world:&World,camera:&Camera,size:[u32;2],candidates:&[(usize,f64,u32)])->Vec<usize> {
        if !candidates.iter().any(|row|world.tiles[row.0].surface_span>0) {return Vec::new();}
        let points:Vec<_>=(0..9).flat_map(|row|(0..9).filter_map(move |column|{
            let pixel=[f64::from(size[0])*column as f64/8.,f64::from(size[1])*row as f64/8.];
            camera.vector(pixel,size).map(crate::camera::geographic)
        })).collect();
        let mut best_coverage=0;
        let mut best=Vec::new();
        for span in [2,8,16] {
            let mut visible:Vec<_>=candidates.iter().filter_map(|&(id,_,_)|{
                let tile=&world.tiles[id];
                if tile.surface_span!=span || self.scissor(id,camera,size).is_none() {return None;}
                let covered=points.iter().filter(|&&point|crate::camera::inside(point,tile.core)).count();
                Some((id,covered))
            }).collect();
            visible.sort_by_key(|&(_,covered)|std::cmp::Reverse(covered));
            let count=visible.len();
            visible.truncate(6);
            let coverage=points.iter().filter(|&&point|visible.iter().any(|&(id,_)|
                crate::camera::inside(point,world.tiles[id].core))).count();
            // Keep an overview if cropped fine pages would appear as isolated patches.
            if coverage>best_coverage && (count<=6 || coverage*100>=points.len()*92) {
                best_coverage=coverage;
                best=visible.into_iter().map(|(id,_)|id).collect();
            }
            if best_coverage==points.len() {break;}
        }
        best
    }
    pub fn scissor(&self,id:usize,camera:&Camera,size:[u32;2])->Option<[u32;4]> {
        let (axis,radius)=self.anchors[id];
        let [x,y]=camera.project_vec(axis,size)?;
        let r=radius*crate::camera::EARTH/camera.mpp*1.18+3.;
        let x0=(x-r).floor().clamp(0.,f64::from(size[0])) as u32;
        let y0=(y-r).floor().clamp(0.,f64::from(size[1])) as u32;
        let x1=(x+r).ceil().clamp(0.,f64::from(size[0])) as u32;
        let y1=(y+r).ceil().clamp(0.,f64::from(size[1])) as u32;
        (x1>x0 && y1>y0).then(||[x0,y0,x1-x0,y1-y0])
    }
}

#[cfg(test)]
#[path = "../../../../tests/rust-map/historical_map_display.rs"]
mod tests;

pub struct Completion {
    pub id:usize,
    pub result:io::Result<Pixels>,
    pub requested:Instant,
}
pub struct Reader {
    sender:mpsc::Sender<(usize,Tile,Instant)>,
    pub inflight:Option<usize>,
}
impl Reader {
    pub fn new(root:PathBuf,proxy:EventLoopProxy<Completion>)->Self {
        let (sender,receiver)=mpsc::channel::<(usize,Tile,Instant)>();
        std::thread::Builder::new().name("WWO map streaming".into()).spawn(move || {
            while let Ok((id,tile,requested))=receiver.recv() {
                if proxy.send_event(Completion{id,result:Pixels::read(&root,&tile),requested}).is_err(){break;}
            }
        }).expect("map streaming thread");
        Self {sender,inflight:None}
    }
    pub fn request(&mut self,id:usize,tile:&Tile) {
        if self.inflight.is_none() && self.sender.send((id,tile.clone(),Instant::now())).is_ok() {
            self.inflight=Some(id);
        }
    }
}
