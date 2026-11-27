use crate::{camera::{self, Camera}, landmarks::{FootprintModel, Landmarks, ModelBounds, ModelKey, ModelMesh, ModelPose, ModelVertex, VisibleModel}, HostEvent};
use serde::Deserialize;
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    fs::File,
    io::{self, Read},
    ops::Range,
    path::{Path, PathBuf},
    sync::{atomic::{AtomicBool, Ordering}, Arc},
    time::{Duration, Instant},
};
use winit::event_loop::EventLoopProxy;

const COVERAGE_MPP: f64 = 24.;
const MAX_MPP: f64 = 155.;
pub(crate) const MAX_RESIDENT: usize = 192;
pub(crate) const MODULES: usize=4;
const MAX_PENDING: usize = 6;
const RECORD: usize = 18;
const MAX_BUILDINGS: usize = 12000;
const CPU_PAGE_BUDGET: usize = (1024 - 32) * 1024 * 1024;
const PAGE_RETENTION: Duration = Duration::from_secs(2);
const INDEX_CELLS_PER_DEGREE: f64 = 4.;
const LONGITUDE_CELLS: i32 = 1440;
const LATITUDE_CELLS: i32 = 720;
const PARIS_FRINGE: &[u8] = include_bytes!("paris-fringe.bin");
const METRES_PER_DEGREE:f64=camera::EARTH*std::f64::consts::PI/180.;
const BLOCK_METRES:f64=96.;

#[derive(Deserialize)]
struct Header {
    version: String,
    cities: Vec<City>,
}

#[derive(Deserialize)]
struct City {
    #[serde(default)]
    id: String,
    name: String,
    source: String,
    attribution: String,
    tiles: Vec<Tile>,
}

#[derive(Clone, Deserialize)]
struct Tile {
    file: String,
    bounds: [f64; 4],
    buildings: usize,
    #[serde(skip)]
    embedded: Option<&'static [u8]>,
    #[serde(skip)]
    city: usize,
}

impl Tile {
    fn distance_to_view(&self, camera: &Camera, [width, height]: [u32; 2]) -> Option<f64> {
        distance_to_view(self.bounds,camera,[width,height],250.)
    }

    fn anchor(&self)->[f64;2] {
        let [w,s,e,n]=self.bounds;
        [(w+e)*0.5,(s+n)*0.5]
    }

    fn load(&self, root: &Path) -> io::Result<CityPage> {
        self.load_for_view(root, &AtomicBool::new(false))
    }

    fn load_for_view(&self, root: &Path, cancelled: &AtomicBool) -> io::Result<CityPage> {
        let check = || if cancelled.load(Ordering::Relaxed) {
            Err(io::Error::new(io::ErrorKind::Interrupted, "City page no longer requested"))
        } else { Ok(()) };
        check()?;
        let rows = match self.embedded {
            Some(bytes) => read_tile(bytes, self.buildings),
            None => read_tile(File::open(root.join(&self.file))?, self.buildings),
        }?;
        check()?;
        Ok(CityPage::pack(rows, self.anchor()))
    }

    fn cpu_reservation(&self) -> usize {
        // Include the capped decoder window, decode rows and the peak builder allocations.
        12 * 1024 * 1024 + self.buildings * 8192
    }
}

struct TileIndex {
    cells: HashMap<[i32; 2], Vec<usize>>,
    largest_apron_m: f64,
}

impl TileIndex {
    fn new(tiles: &[Tile]) -> Self {
        let mut cells = HashMap::<_, Vec<_>>::new();
        let mut largest_apron_m: f64 = 0.;
        for (index, tile) in tiles.iter().enumerate() {
            let [lon, lat] = tile.anchor();
            let x = ((lon + 180.) * INDEX_CELLS_PER_DEGREE).floor() as i32;
            let y = ((lat + 90.) * INDEX_CELLS_PER_DEGREE).floor() as i32;
            let cell = [x.rem_euclid(LONGITUDE_CELLS), y.min(LATITUDE_CELLS - 1)];
            cells.entry(cell).or_default().push(index);
            largest_apron_m = largest_apron_m.max(view_apron(tile.bounds, 250.));
        }
        Self { cells, largest_apron_m }
    }

    fn visible(&self, tiles: &[Tile], camera: &Camera, size: [u32; 2]) -> Vec<(usize, f64)> {
        let (axes, [x, y]) = camera.projection(size);
        let [width, height] = size.map(f64::from);
        let apron = self.largest_apron_m / camera.mpp;
        let dx = x.abs().max((width - x).abs()) + apron;
        let dy = (y.abs().max((height - y).abs()) + apron) / camera.pitch().cos();
        let radius = dx.hypot(dy) * camera.mpp / camera::EARTH;
        let angle = if camera.blend() > 0. { radius.min(std::f64::consts::FRAC_PI_2) }
            else { radius.min(1.).asin() };
        let [lon, lat] = camera::geographic(axes[2]);
        let height_deg = angle.to_degrees();
        let width_deg = if lat.abs() + height_deg >= 90. { 180. }
            else { (angle.sin() / lat.to_radians().cos()).clamp(0., 1.).asin().to_degrees() };
        let x_cell = |value: f64| ((value + 180.) * INDEX_CELLS_PER_DEGREE).floor() as i32;
        let y_cell = |value: f64| (((value + 90.) * INDEX_CELLS_PER_DEGREE).floor() as i32)
            .clamp(0, LATITUDE_CELLS - 1);
        let west = x_cell(lon - width_deg);
        let east = x_cell(lon + width_deg).min(west + LONGITUDE_CELLS - 1);
        let mut result = Vec::new();
        for y in y_cell(lat - height_deg)..=y_cell(lat + height_deg) {
            for x in west..=east {
                if let Some(indices) = self.cells.get(&[x.rem_euclid(LONGITUDE_CELLS), y]) {
                    result.extend(indices.iter().filter_map(|&index| {
                        tiles[index].distance_to_view(camera, size).map(|distance| (index, distance))
                    }));
                }
            }
        }
        result.sort_unstable_by(|a, b| a.1.total_cmp(&b.1).then_with(|| a.0.cmp(&b.0)));
        result.truncate(MAX_RESIDENT);
        result
    }
}

fn paris_fringe() -> io::Result<Vec<Tile>> {
    let invalid = || io::Error::other("Invalid Paris fringe building pack");
    let mut bytes = PARIS_FRINGE.strip_prefix(b"WWOFRNG1").ok_or_else(invalid)?;
    let take_u32 = |bytes: &mut &'static [u8]| {
        let (number, rest) = bytes.split_first_chunk::<4>().ok_or_else(invalid)?;
        *bytes = rest;
        Ok::<_, io::Error>(u32::from_le_bytes(*number))
    };
    let count = take_u32(&mut bytes)? as usize;
    if count == 0 || count > 2048 { return Err(invalid()); }
    let mut tiles = Vec::with_capacity(count);
    for index in 0..count {
        let mut bounds = [0.; 4];
        for coordinate in &mut bounds {
            *coordinate = f64::from(take_u32(&mut bytes)? as i32) / 1_000_000.;
        }
        let buildings = take_u32(&mut bytes)? as usize;
        let length = take_u32(&mut bytes)? as usize;
        let (payload, rest) = bytes.split_at_checked(length).ok_or_else(invalid)?;
        let [w,s,e,n] = bounds;
        if !(1..=MAX_BUILDINGS).contains(&buildings) || !(-180. ..=e).contains(&w)
            || e > 180. || !(-90. ..=n).contains(&s) || n > 90. {
            return Err(invalid());
        }
        bytes = rest;
        tiles.push(Tile { file: format!("paris-fringe-{index}.wcb"), bounds, buildings, embedded: Some(payload), city: 0 });
    }
    if !bytes.is_empty() { return Err(invalid()); }
    Ok(tiles)
}

fn distance_to_view(bounds:[f64;4],camera:&Camera,[width,height]:[u32;2],apron:f64)->Option<f64> {
    let [west, south, east, north] = bounds;
    let center = [(west + east) * 0.5, (south + north) * 0.5];
    let [x, y] = camera.project(center, [width,height])?;
    let margin = view_apron(bounds, apron) / camera.mpp;
    let [w,h] = [f64::from(width),f64::from(height)];
    (x >= -margin && x <= w+margin && y >= -margin && y <= h+margin)
        .then_some((x-w*0.5).hypot(y-h*0.5))
}

fn view_apron([west, south, east, north]: [f64; 4], metres: f64) -> f64 {
    let mid_latitude = (north + south) * 0.5;
    let longitude = (east - west) * mid_latitude.to_radians().cos();
    longitude.hypot(north - south) * 56_000. + metres
}

struct Building {
    coordinates: [i32; 2],
    offset: [f64; 2],
    heading: f64,
    dimensions: [f64; 3],
    module: usize,
}

struct Block {
    bounds: [f64;4],
    apron: f64,
    instances: [Range<u32>;MODULES],
}

pub(crate) struct CityPage {
    blocks: Vec<Block>,
    mesh: Arc<CityGeometry>,
    mesh_bounds: ModelBounds,
    paris: bool,
}

pub(crate) struct CityGeometry {
    pub(crate) mesh: ModelMesh,
    pub(crate) instances: [Vec<FootprintModel>;MODULES],
}

pub(crate) struct CityBatch {
    pub(crate) instances: Range<u32>,
    pub(crate) fit: [[f32;4];4],
    pub(crate) inverse_size: [f32;3],
}

pub(crate) struct CityDraw {
    pub(crate) geometry: Arc<CityGeometry>,
    pub(crate) preload: bool,
    pub(crate) paris: bool,
    pub(crate) batches: [Option<CityBatch>;MODULES],
}

impl CityPage {
    fn bytes(&self) -> usize {
        size_of::<CityGeometry>() + self.blocks.capacity() * size_of::<Block>()
            + self.mesh.mesh.vertices.capacity() * size_of::<ModelVertex>()
            + self.mesh.mesh.indices.capacity() * size_of::<u32>()
            + self.mesh.instances.iter().map(|rows| rows.capacity() * size_of::<FootprintModel>()).sum::<usize>()
    }

    fn pack(rows:Vec<Building>,anchor:[f64;2])->Self {
        let paris=rows.first().is_some_and(|row|row.module>2);
        let longitude_metres=METRES_PER_DEGREE*anchor[1].to_radians().cos().max(0.01);
        let offset=|point:[f64;2]| [(point[0]-anchor[0])*longitude_metres,(anchor[1]-point[1])*METRES_PER_DEGREE];
        let mut grouped=BTreeMap::<[i32;2],Vec<_>>::new();
        for mut row in rows {
            row.offset=offset(row.anchor());
            let cell=row.offset.map(|metres|(metres/BLOCK_METRES).floor() as i32);
            grouped.entry(cell).or_default().push(row);
        }
        let mut mesh=ModelMesh {vertices:Vec::new(),indices:Vec::new()};
        let mut blocks=Vec::with_capacity(grouped.len());
        let mut instances:[Vec<_>;MODULES]=std::array::from_fn(|_|Vec::new());
        for buildings in grouped.into_values() {
            let mut bounds=[180_f64,90.,-180.,-90.];
            let mut apron=0_f64;
            let starts=instances.each_ref().map(|rows|rows.len() as u32);
            for row in buildings {
                let [lon,lat]=row.anchor();
                bounds=[bounds[0].min(lon),bounds[1].min(lat),bounds[2].max(lon),bounds[3].max(lat)];
                apron=apron.max(row.dimensions[0].hypot(row.dimensions[2])*0.5+row.dimensions[1]);
                row.extrude(row.offset,&mut mesh);
                instances[row.module-1].push(FootprintModel::new(row.offset,row.heading,row.dimensions));
            }
            let ranges=std::array::from_fn(|module|starts[module]..instances[module].len() as u32);
            blocks.push(Block {bounds,apron,instances:ranges});
        }
        let mut mesh_bounds=([f64::INFINITY;3],[f64::NEG_INFINITY;3]);
        for vertex in &mesh.vertices {
            for (axis,coordinate) in vertex.position.into_iter().map(f64::from).enumerate() {
                mesh_bounds.0[axis]=mesh_bounds.0[axis].min(coordinate);
                mesh_bounds.1[axis]=mesh_bounds.1[axis].max(coordinate);
            }
        }
        Self{blocks,mesh:Arc::new(CityGeometry{mesh,instances}),mesh_bounds,paris}
    }

    fn visible_batches(&self,camera:&Camera,size:[u32;2],landmarks:&Landmarks)->[Option<CityBatch>;MODULES] {
        let mut visible:[Range<u32>;MODULES]=Default::default();
        for block in self.blocks.iter().filter(|block|distance_to_view(block.bounds,camera,size,block.apron).is_some()) {
            for (range,block_rows) in visible.iter_mut().zip(&block.instances) {
                if !block_rows.is_empty() {
                    range.start=if range.start==range.end {block_rows.start} else {range.start.min(block_rows.start)};
                    range.end=range.end.max(block_rows.end);
                }
            }
        }
        // Keep one draw per kit and page. Intermediate off-screen rows clip on the GPU.
        let mut module=0;
        visible.map(|instances| {
            module+=1;
            (!instances.is_empty()).then(|| {
                let (fit,inverse_size)=landmarks.footprint_fit(module);
                CityBatch{instances,fit,inverse_size}
            })
        })
    }
}

impl Building {
    fn anchor(&self) -> [f64; 2] {
        self.coordinates.map(|part|f64::from(part)/1_000_000.)
    }

    fn extrude(&self, [east,south]:[f64;2],mesh:&mut ModelMesh) {
        let [half_w,height,half_d]=[self.dimensions[0]*0.5,self.dimensions[1],self.dimensions[2]*0.5];
        let (sin,cos)=self.heading.to_radians().sin_cos();
        let position=|x:f64,y:f64,z:f64| [(east+x*cos+z*sin) as f32,y as f32,(south-x*sin+z*cos) as f32];
        let base=[[-half_w,-half_d],[half_w,-half_d],[half_w,half_d],[-half_w,half_d]];
        let eave=height*0.81;
        let london=self.module<=2;
        let roof_inset=if london {
            if half_w>half_d {[1.,0.]} else {[0.,1.]}
        } else {[0.69,0.69]};
        let lower=base.map(|[x,z]|position(x,0.,z));
        let wall=base.map(|[x,z]|position(x,eave,z));
        let crown=base.map(|[x,z]|position(x*roof_inset[0],height,z*roof_inset[1]));
        let shade=f64::from(self.coordinates[0].wrapping_add(self.coordinates[1]).rem_euclid(53)) as f32/53.;
        let wall_color=if london {[0.36,0.29,0.23,1.]} else {[0.54,0.46,0.37,1.]};
        let roof_color=if london {[0.23,0.19,0.17,1.]} else {[0.29,0.27,0.25,1.]};
        let mut quad=|points:[[f32;3];4],mut color:[f32;4]| {
            let p=points.map(glam::Vec3::from_array);
            let normal=(p[1]-p[0]).cross(p[2]-p[0]).normalize_or_zero();
            let normal=if normal.length_squared()>0.5 {normal} else {(p[2]-p[0]).cross(p[3]-p[0]).normalize_or_zero()};
            if normal.length_squared()<0.5 {return;}
            color[..3].iter_mut().for_each(|c|*c*=0.91+shade*0.18);
            let start=mesh.vertices.len() as u32;
            mesh.vertices.extend(points.map(|position|ModelVertex{position,normal:normal.to_array(),color}));
            mesh.indices.extend([start,start+1,start+2,start,start+2,start+3]);
        };
        for i in 0..4 {
            let next=(i+1)%4;
            quad([lower[i],wall[i],wall[next],lower[next]],wall_color);
            quad([wall[i],crown[i],crown[next],wall[next]],roof_color);
        }
        if !london {quad([crown[3],crown[2],crown[1],crown[0]],roof_color);}
    }
}

struct ResidentPage {
    page: CityPage,
    bytes: usize,
    last_needed: Instant,
}

struct PageRequest {
    reservation: usize,
    cancelled: Arc<AtomicBool>,
}

pub(crate) struct Catalogue {
    root: PathBuf,
    tiles: Vec<Tile>,
    index: TileIndex,
    pub(crate) sources: Vec<String>,
    city_ids: Vec<String>,
    cache: HashMap<usize, ResidentPage>,
    pending: HashMap<usize, PageRequest>,
    wanted: HashSet<usize>,
    failed: HashSet<usize>,
    revision: u64,
    discarded: u64,
    lookup: Duration,
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
        let mut city_ids = Vec::new();
        let mut files = HashSet::new();
        for city in catalog.cities {
            let id = if city.id.is_empty() { city.name.to_lowercase() } else { city.id };
            if id.trim().is_empty() || city_ids.contains(&id) {
                return Err(io::Error::other(format!("Duplicate or empty city identifier: {id}")));
            }
            sources.push(format!("{} · {} {}", city.name, city.source, city.attribution));
            for mut tile in city.tiles {
                let [w,s,e,n] = tile.bounds;
                if !tile.file.ends_with(".wcb") || !tile.file.bytes().all(|c|c.is_ascii_alphanumeric()||b"-.".contains(&c))
                    || !files.insert(tile.file.clone()) || !(1..=MAX_BUILDINGS).contains(&tile.buildings)
                    || !(-180. ..=e).contains(&w) || e>180. || !(-90. ..=n).contains(&s) || n>90. {
                    return Err(io::Error::other(format!("Invalid city model tile {}",tile.file)));
                }
                tile.city = city_ids.len();
                tiles.push(tile);
            }
            city_ids.push(id);
        }
        if tiles.is_empty() {return Err(io::Error::other("City model catalogue has no tiles"));}
        let paris = city_ids.iter().position(|id| id == "paris" || id == "fr-paris").unwrap_or_else(|| {
            city_ids.push("paris".into());
            city_ids.len() - 1
        });
        tiles.extend(paris_fringe()?.into_iter().map(|mut tile| { tile.city = paris; tile }));
        sources.push("Paris fringe · Institut Paris Region, c. 1900 land use and roads. Reconstructed building placements.".into());
        let index = TileIndex::new(&tiles);
        Ok(Self { root, tiles, index, sources, city_ids, cache: HashMap::new(), pending: HashMap::new(),
            wanted: HashSet::new(), failed: HashSet::new(), revision: 0, discarded: 0, lookup: Duration::ZERO })
    }

    pub(crate) fn reload_capacity(&self) -> Option<(u64, usize, usize)> {
        self.pending.is_empty().then(|| (
            self.revision + 1,
            MAX_RESIDENT.saturating_sub(self.cache.len()),
            CPU_PAGE_BUDGET.saturating_sub(self.cpu_page_bytes()),
        ))
    }

    pub(crate) fn reload(root: PathBuf, capacity: Option<(u64, usize, usize)>,
        camera: &Camera, size: [u32; 2]) -> io::Result<Self>
    {
        let (revision, max_pages, max_bytes) = capacity.unwrap_or((1, MAX_RESIDENT, CPU_PAGE_BUDGET));
        let mut candidate=Self::open(root)?;
        candidate.revision = revision;
        if camera.mpp<=MAX_MPP {
            for (index, _) in candidate.index.visible(&candidate.tiles, camera, size) {
                let tile=&candidate.tiles[index];
                if candidate.cache.len() >= max_pages
                    || candidate.cpu_page_bytes() + tile.cpu_reservation() > max_bytes
                {
                    return Err(io::Error::other("Insufficient city cache space for a replacement view"));
                }
                let buildings=tile.load(&candidate.root).map_err(|error|io::Error::other(format!("{} · {error}",tile.file)))?;
                candidate.wanted.insert(index);
                candidate.insert(index, buildings, Instant::now());
            }
        }
        Ok(candidate)
    }

    pub(crate) fn ready(&mut self, revision: u64, index: usize, result: io::Result<CityPage>) -> io::Result<()> {
        if revision != self.revision { return Ok(()); }
        let Some(request) = self.pending.remove(&index) else { return Ok(()); };
        if request.cancelled.load(Ordering::Relaxed) || !self.wanted.contains(&index) {
            self.discarded += 1;
            return Ok(());
        }
        match result {
            Ok(tile) => { self.insert(index, tile, Instant::now()); Ok(()) }
            Err(error) => {
                self.failed.insert(index);
                Err(io::Error::other(format!("City tile {} · {error}",self.tiles[index].file)))
            }
        }
    }

    fn insert(&mut self, index: usize, page: CityPage, now: Instant) {
        let bytes = page.bytes();
        self.cache.insert(index, ResidentPage { page, bytes, last_needed: now });
    }

    fn cpu_page_bytes(&self) -> usize {
        self.cache.values().map(|resident| resident.bytes).sum()
    }

    fn reserved_bytes(&self) -> usize {
        self.pending.values().map(|request| request.reservation).sum()
    }

    fn reserve(&mut self, bytes: usize) -> bool {
        while self.cache.len() + self.pending.len() >= MAX_RESIDENT
            || self.cpu_page_bytes() + self.reserved_bytes() + bytes > CPU_PAGE_BUDGET
        {
            let Some((&index, _)) = self.cache.iter().filter(|(index, _)| !self.wanted.contains(index))
                .min_by_key(|(index, page)| (page.last_needed, **index)) else { return false; };
            self.cache.remove(&index);
        }
        true
    }

    pub(crate) fn expire(&mut self, now: Instant) -> bool {
        let previous = self.cache.len();
        self.cache.retain(|index, resident| self.wanted.contains(index)
            || now.saturating_duration_since(resident.last_needed) < PAGE_RETENTION);
        self.cache.len() != previous
    }

    fn set_wanted(&mut self, wanted: HashSet<usize>, now: Instant) {
        self.wanted = wanted;
        for (index, request) in &self.pending {
            if !self.wanted.contains(index) { request.cancelled.store(true, Ordering::Relaxed); }
        }
        for index in &self.wanted {
            if let Some(resident) = self.cache.get_mut(index) { resident.last_needed = now; }
        }
        self.expire(now);
    }

    pub(crate) fn idle(&mut self, now: Instant) {
        self.lookup = Duration::ZERO;
        self.set_wanted(HashSet::new(), now);
    }

    pub(crate) fn status(&self, gpu:impl Fn(u64,usize)->&'static str) -> serde_json::Value {
        let mut wanted = self.wanted.iter().copied().collect::<Vec<_>>();
        wanted.sort_unstable();
        let pages = wanted.into_iter().map(|index| {
            let tile = &self.tiles[index];
            let state = if self.cache.contains_key(&index) { "ready" }
                else if self.failed.contains(&index) { "missing_or_invalid" }
                else if self.pending.contains_key(&index) { "loading" }
                else { "queued" };
            serde_json::json!({"city": self.city_ids[tile.city], "tile": tile.file, "cpu": state,
                "gpu": gpu(self.revision,index)})
        }).collect::<Vec<_>>();
        let metadata_bytes = std::mem::size_of::<Self>()
            + self.tiles.capacity() * std::mem::size_of::<Tile>()
            + self.tiles.iter().map(|tile| tile.file.capacity()).sum::<usize>()
            + self.root.capacity()
            + self.index.cells.capacity() * std::mem::size_of::<([i32; 2], Vec<usize>)>()
            + self.index.cells.values().map(|indices| indices.capacity() * std::mem::size_of::<usize>()).sum::<usize>()
            + [&self.sources, &self.city_ids].into_iter().map(|strings|
                strings.capacity() * std::mem::size_of::<String>()
                + strings.iter().map(String::capacity).sum::<usize>()).sum::<usize>();
        serde_json::json!({
            "catalogue_cities": self.city_ids.len(), "catalogue_tiles": self.tiles.len(),
            "wanted": pages, "cpu_resident": self.cache.len(), "cpu_page_bytes": self.cpu_page_bytes(),
            "cpu_metadata_bytes": metadata_bytes, "cpu_reserved_bytes": self.reserved_bytes(),
            "pending": self.pending.len(), "discarded": self.discarded,
            "lookup_ms": self.lookup.as_secs_f64() * 1000.
        })
    }

    pub(crate) fn covers(&self, [lon,lat]: [f64;2]) -> bool {
        self.cache.keys().filter(|&&index| self.tiles[index].embedded.is_none()).any(|&index| {
            let [w,s,e,n]=self.tiles[index].bounds;
            (w..=e).contains(&lon) && (s..=n).contains(&lat)
        })
    }

    pub(crate) fn visible(&mut self, date: &str, camera: &Camera, size: [u32;2],
        landmarks: &Landmarks, events: Option<&EventLoopProxy<HostEvent>>,
        footprint_coverage: impl Fn([f64;2]) -> f32) -> Vec<VisibleModel>
    {
        let now = Instant::now();
        if camera.mpp > MAX_MPP || !("1891-01-01".."1915-01-01").contains(&date) {
            self.idle(now);
            return Vec::new();
        }
        let visible = self.index.visible(&self.tiles, camera, size);
        self.lookup = now.elapsed();
        let mut models = Vec::new();
        let middle=camera::smooth(8.,COVERAGE_MPP,camera.mpp) as f32;
        let fallback=(1.-camera::smooth(115.,MAX_MPP,camera.mpp)) as f32;
        let details=(1.-camera::smooth(1.7,3.1,camera.mpp)) as f32;
        let visible: Vec<_> = visible.into_iter().filter_map(|(index, _)| {
            let tile=&self.tiles[index];
            let anchor=tile.anchor();
            // Keep the mesh while the matching footprint or block page streams in.
            let opacity=if tile.embedded.is_some() {
                // Regional areas give settlement bounds. The mesh carries individual roof coverage.
                (1.-camera::smooth(34.,92.,camera.mpp)) as f32
            } else {
                (1.-middle*footprint_coverage(anchor))*fallback
            };
            (opacity > 0.03).then_some((index, anchor, opacity))
        }).collect();
        self.set_wanted(visible.iter().map(|&(index, _, _)| index).collect(), now);
        for (index, anchor, opacity) in visible {
            let detail=details*opacity;
            if let Some(resident) = self.cache.get(&index) {
                let page = &resident.page;
                let key=ModelKey::city_page(self.revision,index);
                let pose=ModelPose{key,anchor,heading:0.,datum:0.,dimensions:[1.;3],bounds:page.mesh_bounds};
                let Some(mut block_model)=pose.project(None,camera,camera.pitch(),size) else {continue;};
                let batches=if detail>0. {page.visible_batches(camera,size,landmarks)} else {Default::default()};
                let has_details=batches.iter().any(Option::is_some);
                block_model.lod_range=[if has_details {detail} else {0.},opacity];
                block_model.city_page=Some(CityDraw{geometry:Arc::clone(&page.mesh),preload:camera.mpp<6.,paris:page.paris,batches});
                models.push(block_model);
            } else if let Some(events) = events.filter(|_| self.pending.len() < MAX_PENDING
                && !self.failed.contains(&index) && !self.pending.contains_key(&index)) {
                let reservation = self.tiles[index].cpu_reservation();
                if !self.reserve(reservation) {continue;}
                let root=self.root.clone();
                let tile=self.tiles[index].clone();
                let proxy=events.clone();
                let revision=self.revision;
                let cancelled = Arc::new(AtomicBool::new(false));
                self.pending.insert(index, PageRequest { reservation, cancelled: Arc::clone(&cancelled) });
                if let Err(error)=std::thread::Builder::new().name("WWO city tile".into()).spawn(move || {
                    let result = tile.load_for_view(&root, &cancelled);
                    let _=proxy.send_event(HostEvent::CityTile(revision,index,result));
                }) {
                    let _=events.send_event(HostEvent::CityTile(revision,index,Err(error)));
                }
            }
        }
        models
    }
}

fn read_tile(mut file: impl Read, count: usize) -> io::Result<Vec<Building>> {
    let mut header = [0;12];
    file.read_exact(&mut header)?;
    if &header[..8]!=b"WWOWCB01" || u32::from_le_bytes(header[8..].try_into().unwrap()) as usize != count {
        return Err(io::Error::other("Invalid building page header"));
    }
    let wanted=count*RECORD;
    let mut bytes=Vec::with_capacity(wanted);
    let mut decoder = zstd::stream::read::Decoder::new(file)?;
    decoder.window_log_max(23)?;
    decoder.take((wanted+1) as u64).read_to_end(&mut bytes)?;
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
        Ok(Building{coordinates,offset:[0.;2],heading,dimensions,module})
    }).collect()
}
