use crate::{camera::{self, Camera}, city_kit, landmarks::{FootprintModel, Landmarks, ModelBounds, ModelKey, ModelMesh, ModelPose, ModelVertex, VisibleModel}, HostEvent};
use crate::city_roads::{self, RoadPage, RoadTile};
use glam::{Vec3, Vec4};
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
pub(crate) const MODULES: usize = city_kit::ROLES.len();
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
pub(crate) const MAX_INSTANCE_RUNS:usize=6;

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
    kit: Option<String>,
    tiles: Vec<Tile>,
    #[serde(default)]
    road_pages: Vec<RoadTile>,
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
    #[serde(skip)]
    kit: Option<usize>,
}

impl Tile {
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
            Some(bytes) => read_tile(bytes, self.buildings, self.kit),
            None => read_tile(File::open(root.join(&self.file))?, self.buildings, self.kit),
        }?;
        check()?;
        CityPage::pack(rows, self.anchor(), self.kit, check)
    }

    fn cpu_reservation(&self) -> usize {
        // Include the capped decoder window, decode rows and the peak builder allocations.
        let per_building = if self.kit.is_some() { 32 * 1024 } else { 8192 };
        12 * 1024 * 1024 + self.buildings * per_building
    }
}

struct TileIndex {
    cells: HashMap<[i32; 2], Vec<usize>>,
    largest_apron_m: f64,
}

impl TileIndex {
    fn new(bounds: impl IntoIterator<Item=[f64;4]>) -> Self {
        let mut cells = HashMap::<_, Vec<_>>::new();
        let mut largest_apron_m: f64 = 0.;
        for (index, bounds) in bounds.into_iter().enumerate() {
            let [w, s, e, n] = bounds;
            let (lon, lat) = ((w+e)*0.5, (s+n)*0.5);
            let x = ((lon + 180.) * INDEX_CELLS_PER_DEGREE).floor() as i32;
            let y = ((lat + 90.) * INDEX_CELLS_PER_DEGREE).floor() as i32;
            let cell = [x.rem_euclid(LONGITUDE_CELLS), y.min(LATITUDE_CELLS - 1)];
            cells.entry(cell).or_default().push(index);
            largest_apron_m = largest_apron_m.max(view_apron(bounds, 250.));
        }
        Self { cells, largest_apron_m }
    }

    fn visible(&self, bounds: impl Fn(usize)->[f64;4], camera: &Camera, size: [u32; 2]) -> Vec<(usize, f64)> {
        if self.cells.is_empty() { return Vec::new(); }
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
                        distance_to_view(bounds(index),camera,size,250.).map(|distance| (index, distance))
                    }));
                }
            }
        }
        result.sort_unstable_by(|a, b| a.1.total_cmp(&b.1).then_with(|| a.0.cmp(&b.0)));
        result.truncate(MAX_RESIDENT);
        result
    }
}

struct ResidentRoad {
    page: RoadPage,
    last_needed: Instant,
}

struct Roads {
    tiles: Vec<(usize, RoadTile)>,
    index: TileIndex,
    wanted: Vec<usize>,
    pending: HashMap<usize, PageRequest>,
    cache: HashMap<usize, ResidentRoad>,
    failed: HashSet<usize>,
    overflow: usize,
}

#[derive(Clone, Copy)]
pub(crate) struct ReadyRoad<'a> {
    pub(crate) key: (u64, usize),
    pub(crate) bounds: [f64; 4],
    pub(crate) page: &'a RoadPage,
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
        tiles.push(Tile { file: format!("paris-fringe-{index}.wcb"), bounds, buildings, embedded: Some(payload), city: 0, kit: None });
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
    center: Vec3,
    half_extent: Vec3,
    instances: [Range<u32>;MODULES],
}

pub(crate) struct CityPage {
    blocks: Vec<Block>,
    mesh: Arc<CityGeometry>,
    mesh_bounds: ModelBounds,
    paris: bool,
    kit: Option<usize>,
}

pub(crate) struct CityGeometry {
    pub(crate) mesh: ModelMesh,
    pub(crate) instances: [Vec<FootprintModel>;MODULES],
}

pub(crate) struct CityBatch {
    pub(crate) instances: [Range<u32>;MAX_INSTANCE_RUNS],
    pub(crate) fit: [[f32;4];4],
    pub(crate) inverse_size: [f32;3],
}

pub(crate) struct CityDraw {
    pub(crate) geometry: Arc<CityGeometry>,
    pub(crate) preload: bool,
    pub(crate) paris: bool,
    pub(crate) kit: Option<usize>,
    pub(crate) batches: [Option<CityBatch>;MODULES],
}

impl CityPage {
    fn bytes(&self) -> usize {
        size_of::<CityGeometry>() + self.blocks.capacity() * size_of::<Block>()
            + self.mesh.mesh.vertices.capacity() * size_of::<ModelVertex>()
            + self.mesh.mesh.indices.capacity() * size_of::<u32>()
            + self.mesh.instances.iter().map(|rows| rows.capacity() * size_of::<FootprintModel>()).sum::<usize>()
    }

    fn pack(rows:Vec<Building>,anchor:[f64;2],kit:Option<usize>,check:impl Fn()->io::Result<()>)->io::Result<Self> {
        let paris=kit.is_none() && rows.first().is_some_and(|row|row.module>2);
        let mut modules: [Option<ModelMesh>; MODULES] = Default::default();
        let mut counts = [0; MODULES];
        let mut mesh=ModelMesh {vertices:Vec::new(),indices:Vec::new()};
        if let Some(kit) = kit {
            for row in &rows { counts[row.module-1] += 1; }
            let mut vertices = 0;
            let mut indices = 0;
            for (role, count) in counts.into_iter().enumerate().filter(|(_, count)| *count != 0) {
                let module = city_kit::build(kit, role, false);
                vertices += module.vertices.len() * count;
                indices += module.indices.len() * count;
                modules[role] = Some(module);
            }
            mesh.vertices.reserve_exact(vertices);
            mesh.indices.reserve_exact(indices);
        }
        let longitude_metres=METRES_PER_DEGREE*anchor[1].to_radians().cos().max(0.01);
        let offset=|point:[f64;2]| [(point[0]-anchor[0])*longitude_metres,(anchor[1]-point[1])*METRES_PER_DEGREE];
        let mut grouped=BTreeMap::<[i32;2],Vec<_>>::new();
        for mut row in rows {
            row.offset=offset(row.anchor());
            let cell=row.offset.map(|metres|(metres/BLOCK_METRES).floor() as i32);
            grouped.entry(cell).or_default().push(row);
        }
        let mut blocks=Vec::with_capacity(grouped.len());
        let mut instances = counts.map(Vec::with_capacity);
        for buildings in grouped.into_values() {
            check()?;
            let mut min=Vec3::splat(f32::INFINITY);
            let mut max=Vec3::splat(f32::NEG_INFINITY);
            let starts=instances.each_ref().map(|rows|rows.len() as u32);
            for row in buildings {
                let [east,south]=row.offset.map(|value|value as f32);
                let [width,height,depth]=row.dimensions.map(|value|value as f32);
                // The extra margin includes the kit window faces.
                let radius=width.hypot(depth)*0.502;
                min=min.min(Vec3::new(east-radius,0.,south-radius));
                max=max.max(Vec3::new(east+radius,height,south+radius));
                if let Some(module) = &modules[row.module-1] {
                    row.place(module, &mut mesh);
                } else {
                    row.extrude(row.offset,&mut mesh);
                }
                instances[row.module-1].push(FootprintModel::new(row.offset,row.heading,row.dimensions));
            }
            let ranges=std::array::from_fn(|module|starts[module]..instances[module].len() as u32);
            blocks.push(Block {center:(min+max)*0.5,half_extent:(max-min)*0.5,instances:ranges});
        }
        let mut mesh_bounds=([f64::INFINITY;3],[f64::NEG_INFINITY;3]);
        for vertex in &mesh.vertices {
            for (axis,coordinate) in vertex.position.into_iter().map(f64::from).enumerate() {
                mesh_bounds.0[axis]=mesh_bounds.0[axis].min(coordinate);
                mesh_bounds.1[axis]=mesh_bounds.1[axis].max(coordinate);
            }
        }
        Ok(Self{blocks,mesh:Arc::new(CityGeometry{mesh,instances}),mesh_bounds,paris,kit})
    }

    fn visible_batches(&self,clip_from_page:[[f32;4];4],landmarks:&Landmarks)->[Option<CityBatch>;MODULES] {
        // The kit volumes and fitted legacy models lie within the footprint
        // dimensions. Project their block bounds with the same affine map as the shader.
        let planes:[Vec4;2]=std::array::from_fn(|axis|
            Vec4::from_array(clip_from_page.map(|column|column[axis])));
        let absolute=planes.map(|plane|plane.truncate().abs());
        let intersects_screen=|block:&Block| {
            (0..2).all(|axis| {
                let center=planes[axis].dot(block.center.extend(1.));
                let radius=absolute[axis].dot(block.half_extent);
                center.abs()<=1.001+radius
            })
        };
        let mut visible:[[Range<u32>;MAX_INSTANCE_RUNS];MODULES]=Default::default();
        let mut current=[0;MODULES];
        for block in self.blocks.iter().filter(|block|intersects_screen(block)) {
            for (module,block_rows) in block.instances.iter().enumerate().filter(|(_,rows)|!rows.is_empty()) {
                let runs=&mut visible[module];
                let slot=&mut current[module];
                let last=&mut runs[*slot];
                if last.start == last.end {
                    *last=block_rows.clone();
                } else if block_rows.start.saturating_sub(last.end)<=8 || *slot+1==MAX_INSTANCE_RUNS {
                    last.end=block_rows.end;
                } else {
                    *slot+=1;
                    runs[*slot]=block_rows.clone();
                }
            }
        }
        // Keep one binding per kit and page, with a fixed limit on draw runs.
        let mut module=0;
        visible.map(|instances| {
            module+=1;
            (!instances[0].is_empty()).then(|| {
                let (fit,inverse_size) = if self.kit.is_some() {
                    (glam::Mat4::IDENTITY.to_cols_array_2d(), [1.;3])
                } else {
                    landmarks.footprint_fit(module)
                };
                CityBatch{instances,fit,inverse_size}
            })
        })
    }
}

impl Building {
    fn anchor(&self) -> [f64; 2] {
        self.coordinates.map(|part|f64::from(part)/1_000_000.)
    }

    fn place(&self, module: &ModelMesh, page: &mut ModelMesh) {
        use glam::Quat;
        let [east, south] = self.offset.map(|value| value as f32);
        let shift = Vec3::new(east, 0., south);
        let rotation = Quat::from_rotation_y(self.heading.to_radians() as f32);
        let size = Vec3::from_array(self.dimensions.map(|value| value as f32));
        let start = page.vertices.len() as u32;
        page.vertices.extend(module.vertices.iter().map(|vertex| ModelVertex {
            position: (shift + rotation * (size * Vec3::from_array(vertex.position))).to_array(),
            normal: (rotation * (Vec3::from_array(vertex.normal) / size)).normalize_or_zero().to_array(),
            color: vertex.color,
        }));
        page.indices.extend(module.indices.iter().map(|&index| start + index));
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
    draw_wanted: HashMap<usize, &'static str>,
    failed: HashSet<usize>,
    revision: u64,
    discarded: u64,
    lookup: Duration,
    roads: Roads,
}

impl Catalogue {
    pub(crate) fn open(root: PathBuf) -> io::Result<Self> {
        let path = root.join("catalogue.json");
        let file = File::open(&path).map_err(|e| io::Error::other(format!("{} · {e}",path.display())))?;
        let catalog: Header = serde_json::from_reader(file.take(4*1024*1024))?;
        if !matches!(catalog.version.as_str(), "wwo-city-models-v1" | "wwo-city-models-v2") || catalog.cities.is_empty() {
            return Err(io::Error::other("Unsupported city model catalogue"));
        }
        let mut tiles = Vec::new();
        let mut sources = Vec::new();
        let mut city_ids = Vec::new();
        let mut files = HashSet::new();
        let mut road_tiles = Vec::new();
        for city in catalog.cities {
            let id = if city.id.is_empty() { city.name.to_lowercase() } else { city.id };
            if id.trim().is_empty() || city_ids.contains(&id) {
                return Err(io::Error::other(format!("Duplicate or empty city identifier: {id}")));
            }
            let kit = city.kit.as_deref().map(|kit| city_kit::index(kit)
                .ok_or_else(|| io::Error::other(format!("Unknown city kit {kit} for {id}")))).transpose()?;
            sources.push(format!("{} · {} {}", city.name, city.source, city.attribution));
            for tile in city.road_pages {
                if !tile.valid() || !files.insert(tile.file.clone()) {
                    return Err(io::Error::other(format!("Invalid city road tile {}", tile.file)));
                }
                road_tiles.push((city_ids.len(), tile));
            }
            for mut tile in city.tiles {
                let [w,s,e,n] = tile.bounds;
                if !tile.file.ends_with(".wcb") || !tile.file.bytes().all(|c|c.is_ascii_alphanumeric()||b"-.".contains(&c))
                    || !files.insert(tile.file.clone()) || !(1..=MAX_BUILDINGS).contains(&tile.buildings)
                    || !(-180. ..=e).contains(&w) || e>180. || !(-90. ..=n).contains(&s) || n>90. {
                    return Err(io::Error::other(format!("Invalid city model tile {}",tile.file)));
                }
                tile.city = city_ids.len();
                tile.kit = kit;
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
        let index = TileIndex::new(tiles.iter().map(|tile| tile.bounds));
        let roads = Roads { index: TileIndex::new(road_tiles.iter().map(|(_,tile)| tile.bounds)), tiles: road_tiles,
            wanted: Vec::new(), pending: HashMap::new(), cache: HashMap::new(), failed: HashSet::new(), overflow: 0 };
        Ok(Self { root, tiles, index, sources, city_ids, cache: HashMap::new(), pending: HashMap::new(),
            wanted: HashSet::new(), draw_wanted: HashMap::new(), failed: HashSet::new(), revision: 0,
            discarded: 0, lookup: Duration::ZERO, roads })
    }

    pub(crate) fn reload_capacity(&self) -> Option<(u64, usize, usize)> {
        (self.pending.is_empty() && self.roads.pending.is_empty()).then(|| (
            self.revision + 1,
            MAX_RESIDENT.saturating_sub(self.cache.len() + self.roads.cache.len()),
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
            for (index, _) in candidate.index.visible(|i|candidate.tiles[i].bounds, camera, size) {
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
        self.cache.values().map(|resident| resident.bytes).sum::<usize>()
            + self.roads.cache.values().map(|resident| resident.page.data.capacity()).sum::<usize>()
    }

    fn reserved_bytes(&self) -> usize {
        self.pending.values().chain(self.roads.pending.values()).map(|request| request.reservation).sum()
    }

    fn reserve(&mut self, bytes: usize) -> bool {
        while self.cache.len() + self.pending.len() + self.roads.cache.len() + self.roads.pending.len() >= MAX_RESIDENT
            || self.cpu_page_bytes() + self.reserved_bytes() + bytes > CPU_PAGE_BUDGET
        {
            let Some((&index, _)) = self.cache.iter().filter(|(index, _)| !self.wanted.contains(index))
                .min_by_key(|(index, page)| (page.last_needed, **index)) else { return false; };
            self.cache.remove(&index);
        }
        true
    }

    pub(crate) fn expire(&mut self, now: Instant) -> bool {
        let previous = self.cache.len() + self.roads.cache.len();
        self.cache.retain(|index, resident| self.wanted.contains(index)
            || now.saturating_duration_since(resident.last_needed) < PAGE_RETENTION);
        self.roads.cache.retain(|index, resident| self.roads.wanted.contains(index)
            || now.saturating_duration_since(resident.last_needed) < PAGE_RETENTION);
        self.cache.len() + self.roads.cache.len() != previous
    }

    fn set_wanted(&mut self, wanted: HashSet<usize>, now: Instant) {
        self.wanted = wanted;
        self.draw_wanted.clear();
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
        self.roads.overflow = 0;
        self.set_road_wanted(Vec::new(), now);
        self.set_wanted(HashSet::new(), now);
    }

    fn set_road_wanted(&mut self, wanted: Vec<usize>, now: Instant) {
        self.roads.wanted = wanted;
        for (index, request) in &self.roads.pending {
            if !self.roads.wanted.contains(index) { request.cancelled.store(true, Ordering::Relaxed); }
        }
        for index in &self.roads.wanted {
            if let Some(resident) = self.roads.cache.get_mut(index) { resident.last_needed = now; }
        }
    }

    pub(crate) fn ready_road(&mut self, revision: u64, index: usize, result: io::Result<RoadPage>) -> io::Result<()> {
        if revision != self.revision { return Ok(()); }
        let Some(request) = self.roads.pending.remove(&index) else { return Ok(()); };
        if request.cancelled.load(Ordering::Relaxed) || !self.roads.wanted.contains(&index) {
            self.discarded += 1;
            return Ok(());
        }
        match result {
            Ok(page) => { self.roads.cache.insert(index, ResidentRoad { page, last_needed: Instant::now() }); Ok(()) }
            Err(error) => {
                self.roads.failed.insert(index);
                Err(io::Error::other(format!("City road {} · {error}", self.roads.tiles[index].1.file)))
            }
        }
    }

    pub(crate) fn ready_roads(&self) -> Vec<ReadyRoad<'_>> {
        self.roads.wanted.iter().filter_map(|&index| self.roads.cache.get(&index).map(|resident| ReadyRoad {
            key: (self.revision,index), bounds: self.roads.tiles[index].1.bounds, page: &resident.page,
        })).collect()
    }

    fn update_roads(&mut self, date: &str, camera: &Camera, size: [u32;2], now: Instant,
        events: Option<&EventLoopProxy<HostEvent>>)
    {
        if camera.mpp >= 300. || self.roads.tiles.is_empty() {
            self.roads.overflow = 0;
            self.set_road_wanted(Vec::new(), now);
            return;
        }
        let started = Instant::now();
        let year = date.get(..4).and_then(|date| date.parse::<u16>().ok()).unwrap_or(0);
        let tiles = self.roads.index.visible(|i|self.roads.tiles[i].1.bounds, camera, size);
        let mut wanted = tiles.into_iter().map(|(i,_)| i).filter(|&i| {
            let tile = &self.roads.tiles[i].1;
            let [start,end] = tile.years;
            (start..end).contains(&year)
                && (tile.water_features == 0 || camera.mpp < 21.)
                && (tile.ground_features == 0 || camera.mpp < 115.)
        }).collect::<Vec<_>>();
        let available = wanted.len();
        let mut remaining = city_roads::PAGE_STORAGE_BYTES;
        wanted.retain(|&index| {
            let bytes = self.roads.tiles[index].1.bytes;
            if bytes > remaining { return false; }
            remaining -= bytes;
            true
        });
        wanted.truncate(city_roads::PAGE_SLOTS);
        self.roads.overflow = available - wanted.len();
        self.lookup += started.elapsed();
        self.set_road_wanted(wanted, now);
        let Some(events) = events else { return; };
        for index in self.roads.wanted.clone() {
            if self.roads.pending.len() >= 2 || self.pending.len() + self.roads.pending.len() >= MAX_PENDING { break; }
            if self.roads.cache.contains_key(&index) || self.roads.pending.contains_key(&index)
                || self.roads.failed.contains(&index) { continue; }
            while self.roads.cache.len() + self.roads.pending.len() >= city_roads::PAGE_SLOTS {
                let Some((&stale,_)) = self.roads.cache.iter().filter(|(i,_)| !self.roads.wanted.contains(i))
                    .min_by_key(|(i,page)| (page.last_needed,**i)) else { break; };
                self.roads.cache.remove(&stale);
            }
            if self.roads.cache.len() + self.roads.pending.len() >= city_roads::PAGE_SLOTS { break; }
            let reservation = city_roads::PAGE_BYTES * 3;
            if !self.reserve(reservation) { break; }
            let root = self.root.clone();
            let tile = self.roads.tiles[index].1.clone();
            let proxy = events.clone();
            let revision = self.revision;
            let cancelled = Arc::new(AtomicBool::new(false));
            self.roads.pending.insert(index, PageRequest { reservation, cancelled: Arc::clone(&cancelled) });
            if let Err(error) = std::thread::Builder::new().name("WWO city road tile".into()).spawn(move || {
                let result = if cancelled.load(Ordering::Relaxed) {
                    Err(io::Error::new(io::ErrorKind::Interrupted, "Road page no longer requested"))
                } else { tile.read(&root) };
                let _ = proxy.send_event(HostEvent::CityRoad(revision,index,result));
            }) {
                let _ = events.send_event(HostEvent::CityRoad(revision,index,Err(error)));
            }
        }
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
            let draw_target = self.draw_wanted.get(&index).copied().unwrap_or(
                if state == "ready" { "prefetch" } else { "pending_projection" }
            );
            serde_json::json!({"city": self.city_ids[tile.city], "tile": tile.file, "cpu": state,
                "kit": tile.kit.map(city_kit::name),
                "draw_target": draw_target,
                "gpu": gpu(self.revision,index)})
        }).collect::<Vec<_>>();
        let metadata_bytes = std::mem::size_of::<Self>()
            + self.tiles.capacity() * std::mem::size_of::<Tile>()
            + self.tiles.iter().map(|tile| tile.file.capacity()).sum::<usize>()
            + self.root.capacity()
            + self.index.cells.capacity() * std::mem::size_of::<([i32; 2], Vec<usize>)>()
            + self.index.cells.values().map(|indices| indices.capacity() * std::mem::size_of::<usize>()).sum::<usize>()
            + self.roads.tiles.capacity() * std::mem::size_of::<(usize,RoadTile)>()
            + self.roads.tiles.iter().map(|(_,tile)| tile.file.capacity()).sum::<usize>()
            + self.roads.index.cells.capacity() * std::mem::size_of::<([i32;2],Vec<usize>)>()
            + self.roads.index.cells.values().map(|indices| indices.capacity() * std::mem::size_of::<usize>()).sum::<usize>()
            + [&self.sources, &self.city_ids].into_iter().map(|strings|
                strings.capacity() * std::mem::size_of::<String>()
                + strings.iter().map(String::capacity).sum::<usize>()).sum::<usize>();
        let roads = self.roads.wanted.iter().map(|&index| {
            let (city,tile) = &self.roads.tiles[index];
            let state = if self.roads.cache.contains_key(&index) { "ready" }
                else if self.roads.failed.contains(&index) { "missing_or_invalid" }
                else if self.roads.pending.contains_key(&index) { "loading" }
                else { "queued" };
            serde_json::json!({"city":self.city_ids[*city],"tile":tile.file,"index":index,"cpu":state,
                "coverage":if tile.coverage_features == 0 {"uncovered"} else if tile.features == 0 {"confirmed_empty"} else {"mapped_or_empty"},
                "road_features":tile.features,"water_features":tile.water_features,
                "ground_features":tile.ground_features,"coverage_features":tile.coverage_features})
        }).collect::<Vec<_>>();
        serde_json::json!({
            "roads":{"wanted":roads,"pending":self.roads.pending.len(),"resident":self.roads.cache.len(),
                "outside_slot_budget":self.roads.overflow},
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
            self.lookup = Duration::ZERO;
            self.set_wanted(HashSet::new(),now);
            self.update_roads(date,camera,size,now,events);
            return Vec::new();
        }
        let visible = self.index.visible(|i|self.tiles[i].bounds, camera, size);
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
        self.update_roads(date,camera,size,now,events);
        for (index, anchor, opacity) in visible {
            let detail=details*opacity;
            if let Some(resident) = self.cache.get(&index) {
                let page = &resident.page;
                let key=ModelKey::city_page(self.revision,index);
                let pose=ModelPose{key,anchor,heading:0.,datum:0.,dimensions:[1.;3],bounds:page.mesh_bounds};
                let Some(mut block_model)=pose.project(None,camera,camera.pitch(),size) else {continue;};
                let batches=if detail>0. {page.visible_batches(block_model.clip_from_model,landmarks)} else {Default::default()};
                let has_details=batches.iter().any(Option::is_some);
                self.draw_wanted.insert(index, if has_details { "detail" } else { "overview" });
                block_model.lod_range=[if has_details {detail} else {0.},opacity];
                block_model.city_page=Some(CityDraw{geometry:Arc::clone(&page.mesh),preload:camera.mpp<6.,
                    paris:page.paris,kit:page.kit,batches});
                models.push(block_model);
            } else if let Some(events) = events.filter(|_| self.pending.len() + self.roads.pending.len() < MAX_PENDING
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

fn read_tile(mut file: impl Read, count: usize, kit: Option<usize>) -> io::Result<Vec<Building>> {
    let mut header = [0;12];
    file.read_exact(&mut header)?;
    let (magic, module_count) = if kit.is_some() { (b"WWOWCB02", MODULES) } else { (b"WWOWCB01", 4) };
    if &header[..8]!=magic || u32::from_le_bytes(header[8..].try_into().unwrap()) as usize != count {
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
            || dimensions.iter().any(|v|*v<=0.||*v>320.) || !(1..=module_count).contains(&module) || part[17]!=0 {
            return Err(io::Error::other("Invalid building dimensions or location"));
        }
        let heading=f64::from(i16::from_le_bytes(part[8..10].try_into().unwrap()))/100.;
        Ok(Building{coordinates,offset:[0.;2],heading,dimensions,module})
    }).collect()
}
