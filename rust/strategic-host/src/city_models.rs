use crate::{camera::Camera, landmarks::{Landmarks, VisibleModel}, HostEvent};
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    fs::File,
    io::{self, Read},
    path::{Path, PathBuf},
};
use winit::event_loop::EventLoopProxy;

const MAX_MPP: f64 = 155.;
const MAX_RESIDENT: usize = 192;
const MAX_PENDING: usize = 6;
const RECORD: usize = 18;
const MAX_BUILDINGS: usize = 12000;
const MAX_INSTANCES: usize = 16000;

#[derive(Deserialize)]
struct Header {
    version: String,
    cities: Vec<City>,
}

#[derive(Deserialize)]
struct City {
    name: String,
    source: String,
    attribution: String,
    tiles: Vec<Tile>,
}

#[derive(Deserialize)]
struct Tile {
    file: String,
    bounds: [f64; 4],
    buildings: usize,
}

impl Tile {
    fn distance_to_view(&self, camera: &Camera, [width, height]: [u32; 2]) -> Option<f64> {
        let [west, south, east, north] = self.bounds;
        let center = [(west + east) * 0.5, (south + north) * 0.5];
        let [x, y] = camera.project(center, [width,height])?;
        let longitude = (east-west)*center[1].to_radians().cos();
        let latitude = north-south;
        let margin = (longitude.hypot(latitude)*56_000. + 150.)/camera.mpp;
        let [w,h] = [f64::from(width),f64::from(height)];
        (x >= -margin && x <= w+margin && y >= -margin && y <= h+margin)
            .then_some((x-w*0.5).hypot(y-h*0.5))
    }
}

pub(crate) struct Building {
    coordinates: [i32; 2],
    heading: f64,
    dimensions: [f64; 3],
    module: usize,
}

impl Building {
    fn anchor(&self) -> [f64; 2] {
        self.coordinates.map(|part|f64::from(part)/1_000_000.)
    }
}

pub(crate) struct Catalogue {
    root: PathBuf,
    tiles: Vec<Tile>,
    pub(crate) sources: Vec<String>,
    cache: HashMap<usize, Vec<Building>>,
    pending: HashSet<usize>,
    failed: HashSet<usize>,
    revision: u64,
}

impl Catalogue {
    pub(crate) fn open(root: PathBuf) -> io::Result<Self> {
        let path = root.join("catalogue.json");
        let file = File::open(&path).map_err(|e| io::Error::other(format!("{} · {e}",path.display())))?;
        let catalog: Header = serde_json::from_reader(file.take(4*1024*1024))?;
        if catalog.version != "wwo-city-models-v1" || catalog.cities.is_empty() {
            return Err(io::Error::other("Unsupported city model catalogue"));
        }
        let mut tiles = Vec::new();
        let mut sources = Vec::new();
        let mut files = HashSet::new();
        for city in catalog.cities {
            sources.push(format!("{} · {} {}", city.name, city.source, city.attribution));
            for tile in city.tiles {
                let [w,s,e,n] = tile.bounds;
                if !tile.file.ends_with(".wcb") || !tile.file.bytes().all(|c|c.is_ascii_alphanumeric()||b"-.".contains(&c))
                    || !files.insert(tile.file.clone()) || !(1..=MAX_BUILDINGS).contains(&tile.buildings)
                    || !(-180. ..=e).contains(&w) || e>180. || !(-90. ..=n).contains(&s) || n>90. {
                    return Err(io::Error::other(format!("Invalid city model tile {}",tile.file)));
                }
                tiles.push(tile);
            }
        }
        if tiles.is_empty() {return Err(io::Error::other("City model catalogue has no tiles"));}
        Ok(Self { root, tiles, sources, cache:HashMap::new(),pending:HashSet::new(),failed:HashSet::new(),revision:0 })
    }

    pub(crate) fn reload(root: PathBuf, previous: Option<&Self>, camera:&Camera, size:[u32;2]) -> io::Result<Self> {
        let mut candidate=Self::open(root)?;
        candidate.revision=previous.map_or(1,|current|current.revision+1);
        if camera.mpp<=MAX_MPP {
            let mut visible:Vec<_>=candidate.tiles.iter().enumerate().filter_map(|(index,tile)|
                tile.distance_to_view(camera,size).map(|distance|(index,distance))).collect();
            visible.sort_by(|a,b|a.1.total_cmp(&b.1));
            for (index,_) in visible.into_iter().take(MAX_RESIDENT) {
                let tile=&candidate.tiles[index];
                let path=candidate.root.join(&tile.file);
                let buildings=read_tile(&path,tile.buildings).map_err(|error|io::Error::other(format!("{} · {error}",path.display())))?;
                candidate.cache.insert(index,buildings);
            }
        }
        Ok(candidate)
    }

    pub(crate) fn ready(&mut self, revision: u64, index: usize, result: io::Result<Vec<Building>>) -> io::Result<()> {
        if revision!=self.revision {return Ok(());}
        self.pending.remove(&index);
        match result {
            Ok(tile) => { self.cache.insert(index,tile); Ok(()) }
            Err(error) => {
                self.failed.insert(index);
                Err(io::Error::other(format!("City tile {} · {error}",self.tiles[index].file)))
            }
        }
    }

    pub(crate) fn covers(&self, [lon,lat]: [f64;2]) -> bool {
        self.cache.keys().any(|&index| {
            let [w,s,e,n]=self.tiles[index].bounds;
            (w..=e).contains(&lon) && (s..=n).contains(&lat)
        })
    }

    pub(crate) fn visible(&mut self, date: &str, camera: &Camera, size: [u32;2],
        landmarks: &Landmarks, events: &EventLoopProxy<HostEvent>) -> Vec<VisibleModel>
    {
        if camera.mpp > MAX_MPP || !("1891-01-01".."1915-01-01").contains(&date) {
            self.cache.clear();
            return Vec::new();
        }
        let mut visible: Vec<_> = self.tiles.iter().enumerate()
            .filter_map(|(index,tile)|tile.distance_to_view(camera,size).map(|distance|(index,distance))).collect();
        visible.sort_by(|a,b|a.1.total_cmp(&b.1));
        visible.truncate(MAX_RESIDENT);
        let wanted: HashSet<_> = visible.iter().map(|&(index,_)|index).collect();
        if self.cache.len() > MAX_RESIDENT || visible.is_empty() {
            self.cache.retain(|index,_|wanted.contains(index));
        }
        let mut models = Vec::new();
        let mut cells = HashSet::new();
        let [_,lat] = camera.coordinates();
        let step = [lat.to_radians().cos().max(0.05), 1.].map(|unit|
            (camera.mpp*2.6/(0.111_195*unit)).round().max(1.) as i32);
        let mut resident=visible.iter().filter(|(index,_)|self.cache.contains_key(index)).count();
        for (index,_) in visible {
            if let Some(rows) = self.cache.get(&index) {
                let remaining=MAX_INSTANCES-models.len();
                let budget=remaining.div_ceil(resident);
                resident-=1;
                if budget==0 {continue;}
                let stride=(rows.len()/budget).max(1);
                let until=models.len()+budget;
                for row in rows.iter().step_by(stride) {
                    if camera.mpp>5. {
                        let cell = [row.coordinates[0].div_euclid(step[0]),row.coordinates[1].div_euclid(step[1])];
                        if !cells.insert(cell) {continue;}
                    }
                    if let Some(model) = landmarks.footprint_model(row.module,row.anchor(),row.heading,row.dimensions,camera,size) {
                        models.push(model);
                        if models.len()==until {break;}
                    }
                }
            } else if self.pending.len()<MAX_PENDING && !self.failed.contains(&index) && self.pending.insert(index) {
                let path=self.root.join(&self.tiles[index].file);
                let count=self.tiles[index].buildings;
                let proxy=events.clone();
                let revision=self.revision;
                if let Err(error)=std::thread::Builder::new().name("WWO city tile".into()).spawn(move || {
                    let _=proxy.send_event(HostEvent::CityTile(revision,index,read_tile(&path,count)));
                }) {
                    let _=events.send_event(HostEvent::CityTile(revision,index,Err(error)));
                }
            }
        }
        models
    }
}

fn read_tile(path: &Path, count: usize) -> io::Result<Vec<Building>> {
    let mut file = File::open(path)?;
    let mut header = [0;12];
    file.read_exact(&mut header)?;
    if &header[..8]!=b"WWOWCB01" || u32::from_le_bytes(header[8..].try_into().unwrap()) as usize != count {
        return Err(io::Error::other("Invalid building page header"));
    }
    let wanted=count*RECORD;
    let mut bytes=Vec::with_capacity(wanted);
    zstd::stream::read::Decoder::new(file)?.take((wanted+1) as u64).read_to_end(&mut bytes)?;
    if bytes.len()!=wanted {return Err(io::Error::other("Invalid building page length"));}
    bytes.chunks_exact(RECORD).map(|part| {
        let signed=|at| i32::from_le_bytes(part[at..at+4].try_into().unwrap());
        let decimetres=|at| f64::from(u16::from_le_bytes(part[at..at+2].try_into().unwrap()))/10.;
        let coordinates=[signed(0),signed(4)];
        let module=usize::from(part[16]);
        let dimensions=[decimetres(10),decimetres(14),decimetres(12)];
        if !(-180_000_000..=180_000_000).contains(&coordinates[0])
            || !(-90_000_000..=90_000_000).contains(&coordinates[1])
            || dimensions.iter().any(|v|*v<=0.||*v>320.) || !matches!(module,1..=4) || part[17]!=0 {
            return Err(io::Error::other("Invalid building dimensions or location"));
        }
        let heading=f64::from(i16::from_le_bytes(part[8..10].try_into().unwrap()))/100.;
        Ok(Building{coordinates,heading,dimensions,module})
    }).collect()
}
