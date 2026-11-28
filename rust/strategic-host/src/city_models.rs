use crate::{camera::{self, Camera}, city_kit, landmarks::{FootprintModel, Landmarks, ModelBounds, ModelKey, ModelMesh, ModelPose, ModelVertex, VisibleModel}, HostEvent};
use crate::{city_plan::{Plan, PlanSource, Plans}, overlay::Mesh};
use serde::Deserialize;
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    f64::consts::FRAC_PI_2,
    fs::File,
    io::{self, Read},
    ops::Range,
    path::{Path, PathBuf},
    sync::Arc,
};
use winit::event_loop::EventLoopProxy;

const COVERAGE_MPP: f64 = 24.;
const MAX_MPP: f64 = 155.;
pub(crate) const MAX_RESIDENT: usize = 192;
pub(crate) const MODULES: usize = city_kit::ROLES.len();
const MAX_PENDING: usize = 6;
const RECORD: usize = 18;
const MAX_BUILDINGS: usize = 12000;
const TILE_APRON_METRES: f64 = 250.;
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
    id: Option<String>,
    plan: Option<String>,
    plan_bounds: Option<[f64; 4]>,
    name: String,
    source: String,
    attribution: String,
    kit: Option<String>,
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
    kit: Option<usize>,
}

impl Tile {
    fn distance_to_view(&self, camera: &Camera, size: [u32; 2]) -> Option<f64> {
        distance_to_view(self.bounds, camera, size, TILE_APRON_METRES)
    }

    fn anchor(&self)->[f64;2] {
        let [w,s,e,n]=self.bounds;
        [(w+e)*0.5,(s+n)*0.5]
    }

    fn load(&self, root: &Path) -> io::Result<CityPage> {
        let rows = match self.embedded {
            Some(bytes) => read_tile(bytes, self.buildings, self.kit),
            None => read_tile(File::open(root.join(&self.file))?, self.buildings, self.kit),
        }?;
        Ok(CityPage::pack(rows, self.anchor(), self.kit))
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
        tiles.push(Tile { file: format!("paris-fringe-{index}.wcb"), bounds, buildings, embedded: Some(payload), kit: None });
    }
    if !bytes.is_empty() { return Err(invalid()); }
    Ok(tiles)
}

fn view_margin_metres(bounds: [f64; 4], apron: f64) -> f64 {
    let [west, south, east, north] = bounds;
    let longitude = (east - west) * ((south + north) * 0.5).to_radians().cos();
    let latitude = north - south;
    longitude.hypot(latitude) * 56_000. + apron
}

pub(crate) fn distance_to_view(bounds:[f64;4],camera:&Camera,[width,height]:[u32;2],apron:f64)->Option<f64> {
    let [west, south, east, north] = bounds;
    let center = [(west + east) * 0.5, (south + north) * 0.5];
    let [x, y] = camera.project(center, [width,height])?;
    let margin = view_margin_metres(bounds, apron) / camera.mpp;
    let [w,h] = [f64::from(width),f64::from(height)];
    (x >= -margin && x <= w+margin && y >= -margin && y <= h+margin)
        .then_some((x-w*0.5).hypot(y-h*0.5))
}

type TileCells = HashMap<(i32, i32), Vec<usize>>;

struct TileIndex {
    cells_by_margin: BTreeMap<u32, TileCells>,
}

fn wrap_longitude_cell(cell: i32) -> i32 {
    (cell + 180).rem_euclid(360) - 180
}

impl TileIndex {
    fn new(tiles: &[Tile]) -> Self {
        let mut cells_by_margin = BTreeMap::<u32, TileCells>::new();
        for (index, tile) in tiles.iter().enumerate() {
            let [longitude, latitude] = tile.anchor().map(|degrees| degrees.floor() as i32);
            let cell = (wrap_longitude_cell(longitude), latitude);
            // Keep wide pages from inflating the search for ordinary one-kilometre pages.
            let margin = (view_margin_metres(tile.bounds, TILE_APRON_METRES).ceil() as u32)
                .next_power_of_two();
            cells_by_margin
                .entry(margin)
                .or_default()
                .entry(cell)
                .or_default()
                .push(index);
        }
        Self { cells_by_margin }
    }

    fn visible(&self, tiles: &[Tile], camera: &Camera, size: [u32; 2]) -> Vec<usize> {
        let (axes, center) = camera.projection(size);
        let [x, y, z] = axes[2];
        let lon = x.atan2(z).to_degrees();
        let lat = y.atan2(x.hypot(z)).to_degrees();
        let [width, height] = size.map(f64::from);
        let horizontal = center[0].abs().max((width - center[0]).abs());
        let vertical = center[1].abs().max((height - center[1]).abs());
        let pitch_scale = 1. / camera.pitch().cos();
        let local = camera.blend() == 1.;
        let mut visible = Vec::new();

        for (&margin, cells) in &self.cells_by_margin {
            // The farthest corner of the padded viewport bounds the projected anchor radius.
            let pad = f64::from(margin) / camera.mpp;
            let radius = (horizontal + pad).hypot((vertical + pad) * pitch_scale)
                * camera.mpp / camera::EARTH;
            let angle = if local { radius.min(FRAC_PI_2) } else { radius.min(1.).asin() };
            let angle = angle + 1e-10;
            let degrees = angle.to_degrees();
            let half_longitude = if lat.abs() + degrees >= 90. {
                180.
            } else {
                (angle.sin() / lat.to_radians().cos()).clamp(0., 1.).asin().to_degrees()
            };
            let west = (lon - half_longitude).floor() as i32;
            let east = (lon + half_longitude).floor() as i32;
            let south = (lat - degrees).max(-90.).floor() as i32;
            let north = (lat + degrees).min(90.).floor() as i32;
            let longitude_count = (east - west + 1).min(360);
            let mut include = |indices: &[usize]| {
                visible.extend(indices.iter().filter_map(|&index| {
                    tiles[index].distance_to_view(camera, size).map(|distance| (index, distance))
                }));
            };
            if ((north - south + 1) * longitude_count) as usize <= cells.len() {
                for x in west..west + longitude_count {
                    let longitude = wrap_longitude_cell(x);
                    for latitude in south..=north {
                        if let Some(indices) = cells.get(&(longitude, latitude)) {
                            include(indices);
                        }
                    }
                }
            } else {
                // A sparse band with a wide apron can span many empty cells.
                for (&(longitude, latitude), indices) in cells {
                    if (south..=north).contains(&latitude)
                        && (longitude - west).rem_euclid(360) < longitude_count
                    {
                        include(indices);
                    }
                }
            }
        }

        visible.sort_unstable_by(|a, b| a.1.total_cmp(&b.1).then_with(|| a.0.cmp(&b.0)));
        visible.truncate(MAX_RESIDENT);
        visible.into_iter().map(|(index, _)| index).collect()
    }
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
    kit: Option<usize>,
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
    pub(crate) kit: Option<usize>,
    pub(crate) batches: [Option<CityBatch>;MODULES],
}

impl CityPage {
    fn pack(rows: Vec<Building>, anchor: [f64; 2], kit: Option<usize>) -> Self {
        let paris = kit.is_none() && rows.first().is_some_and(|row| row.module > 2);
        let mut modules: [Option<ModelMesh>; MODULES] = Default::default();
        let mut counts = [0; MODULES];
        let mut mesh = ModelMesh::default();
        if let Some(kit) = kit {
            for row in &rows {
                counts[row.module - 1] += 1;
            }
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
            let mut bounds=[180_f64,90.,-180.,-90.];
            let mut apron=0_f64;
            let starts=instances.each_ref().map(|rows|rows.len() as u32);
            for row in buildings {
                let [lon,lat]=row.anchor();
                bounds=[bounds[0].min(lon),bounds[1].min(lat),bounds[2].max(lon),bounds[3].max(lat)];
                apron=apron.max(row.dimensions[0].hypot(row.dimensions[2])*0.5+row.dimensions[1]);
                if let Some(module) = &modules[row.module - 1] {
                    row.place(module, &mut mesh);
                } else {
                    row.extrude(row.offset, &mut mesh);
                }
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
        Self{blocks,mesh:Arc::new(CityGeometry{mesh,instances}),mesh_bounds,paris,kit}
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
                let (fit, inverse_size) = if self.kit.is_some() {
                    (glam::Mat4::IDENTITY.to_cols_array_2d(), [1.; 3])
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
        use glam::{Quat, Vec3};
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

pub(crate) struct Catalogue {
    root: PathBuf,
    tiles: Vec<Tile>,
    index: TileIndex,
    pub(crate) sources: Vec<String>,
    cache: HashMap<usize, CityPage>,
    pending: HashSet<usize>,
    failed: HashSet<usize>,
    plans: Plans,
    revision: u64,
}

impl Catalogue {
    pub(crate) fn open(root: PathBuf) -> io::Result<Self> {
        let path = root.join("catalogue.json");
        let file = File::open(&path).map_err(|e| io::Error::other(format!("{} · {e}",path.display())))?;
        let catalog: Header = serde_json::from_reader(io::BufReader::new(file))?;
        if !matches!(catalog.version.as_str(), "wwo-city-models-v1" | "wwo-city-models-v2") || catalog.cities.is_empty() {
            return Err(io::Error::other("Unsupported city model catalogue"));
        }
        let mut tiles = Vec::new();
        let mut sources = Vec::new();
        let mut files = HashSet::new();
        let mut plans = Vec::new();
        for city in catalog.cities {
            let kit = city.kit.as_deref().map(|kit| city_kit::index(kit)
                .ok_or_else(|| io::Error::other(format!("Unknown city kit {kit} for {}", city.name)))).transpose()?;
            sources.push(format!("{} · {} {}", city.name, city.source, city.attribution));
            let first = tiles.len();
            for mut tile in city.tiles {
                let [w,s,e,n] = tile.bounds;
                if !tile.file.ends_with(".wcb") || !tile.file.bytes().all(|c|c.is_ascii_alphanumeric()||b"-_.".contains(&c))
                    || !files.insert(tile.file.clone()) || !(1..=MAX_BUILDINGS).contains(&tile.buildings)
                    || !(-180. ..=e).contains(&w) || e>180. || !(-90. ..=n).contains(&s) || n>90. {
                    return Err(io::Error::other(format!("Invalid city model tile {}",tile.file)));
                }
                tile.kit = kit;
                tiles.push(tile);
            }
            if let Some(file) = city.plan {
                plans.push(PlanSource::new(city.id, file, city.plan_bounds,
                    tiles[first..].iter().map(|tile| tile.bounds))?);
            }
        }
        if tiles.is_empty() {return Err(io::Error::other("City model catalogue has no tiles"));}
        tiles.extend(paris_fringe()?);
        sources.push("Paris fringe · Institut Paris Region, c. 1900 land use and roads. Reconstructed building placements.".into());
        let index = TileIndex::new(&tiles);
        Ok(Self { root, tiles, index, sources, cache:HashMap::new(),pending:HashSet::new(),failed:HashSet::new(),
            plans:Plans::new(plans)?,revision:0 })
    }

    pub(crate) fn reload(root: PathBuf, previous: Option<&Self>, camera:&Camera, size:[u32;2]) -> io::Result<Self> {
        let mut candidate=Self::open(root)?;
        candidate.revision=previous.map_or(1,|current|current.revision+1);
        if camera.mpp<=MAX_MPP {
            for index in candidate.index.visible(&candidate.tiles, camera, size) {
                let tile=&candidate.tiles[index];
                let buildings=tile.load(&candidate.root).map_err(|error|io::Error::other(format!("{} · {error}",tile.file)))?;
                candidate.cache.insert(index,buildings);
            }
        }
        Ok(candidate)
    }

    pub(crate) fn ready(&mut self, revision: u64, index: usize, result: io::Result<CityPage>) -> io::Result<()> {
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

    pub(crate) fn plan_ready(&mut self, revision: u64, index: usize, result: io::Result<Plan>) -> io::Result<()> {
        if revision != self.revision { return Ok(()); }
        self.plans.ready(index, result)
    }

    pub(crate) fn plan_mesh(&mut self, date:&str, camera:&Camera, size:[u32;2], geographic:bool, roads:bool,
        events:&EventLoopProxy<HostEvent>) -> Option<(u64,&Mesh)>
    {
        if camera.mpp >= MAX_MPP || !("1891-01-01".."1915-01-01").contains(&date) {
            return None;
        }
        let opacity = (1. - camera::smooth(115., MAX_MPP, camera.mpp)) as f32;
        self.plans.mesh(&self.root, self.revision, camera, size, geographic, roads, opacity, events)
    }

    pub(crate) fn covers(&self, [lon,lat]: [f64;2]) -> bool {
        self.cache.keys().filter(|&&index| self.tiles[index].embedded.is_none()).any(|&index| {
            let [w,s,e,n]=self.tiles[index].bounds;
            (w..=e).contains(&lon) && (s..=n).contains(&lat)
        })
    }

    pub(crate) fn visible(&mut self, date: &str, camera: &Camera, size: [u32;2],
        landmarks: &Landmarks, events: &EventLoopProxy<HostEvent>,
        footprint_coverage: impl Fn([f64;2]) -> f32) -> Vec<VisibleModel>
    {
        if camera.mpp > MAX_MPP || !("1891-01-01".."1915-01-01").contains(&date) {
            return Vec::new();
        }
        let visible = self.index.visible(&self.tiles, camera, size);
        if self.cache.len() > MAX_RESIDENT {
            let wanted: HashSet<_> = visible.iter().copied().collect();
            self.cache.retain(|index,_|wanted.contains(index));
        }
        let mut models = Vec::new();
        let middle=camera::smooth(8.,COVERAGE_MPP,camera.mpp) as f32;
        let fallback=(1.-camera::smooth(115.,MAX_MPP,camera.mpp)) as f32;
        let details=(1.-camera::smooth(1.7,3.1,camera.mpp)) as f32;
        for index in visible {
            let tile=&self.tiles[index];
            let anchor=tile.anchor();
            // Keep the mesh while the matching footprint or block page streams in.
            let opacity=if tile.embedded.is_some() {
                // Regional areas give settlement bounds. The mesh carries individual roof coverage.
                (1.-camera::smooth(34.,92.,camera.mpp)) as f32
            } else {
                (1.-middle*footprint_coverage(anchor))*fallback
            };
            if opacity<=0.03 {continue;}
            let detail=details*opacity;
            if let Some(page) = self.cache.get(&index) {
                let key=ModelKey::city_page(self.revision,index);
                let pose=ModelPose{key,anchor,heading:0.,datum:0.,dimensions:[1.;3],bounds:page.mesh_bounds};
                let Some(mut block_model)=pose.project(None,camera,camera.pitch(),size) else {continue;};
                let batches=if detail>0. {page.visible_batches(camera,size,landmarks)} else {Default::default()};
                let has_details=batches.iter().any(Option::is_some);
                block_model.lod_range=[if has_details {detail} else {0.},opacity];
                block_model.city_page=Some(CityDraw{geometry:Arc::clone(&page.mesh),preload:camera.mpp<6.,
                    paris:page.paris,kit:page.kit,batches});
                models.push(block_model);
            } else if self.pending.len()<MAX_PENDING && !self.failed.contains(&index) && self.pending.insert(index) {
                let root=self.root.clone();
                let tile=tile.clone();
                let proxy=events.clone();
                let revision=self.revision;
                if let Err(error)=std::thread::Builder::new().name("WWO city tile".into()).spawn(move || {
                    let _=proxy.send_event(HostEvent::CityTile(revision,index,tile.load(&root)));
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
            || dimensions.iter().any(|v|*v<=0.||*v>320.) || !(1..=module_count).contains(&module) || part[17]!=0 {
            return Err(io::Error::other("Invalid building dimensions or location"));
        }
        let heading=f64::from(i16::from_le_bytes(part[8..10].try_into().unwrap()))/100.;
        Ok(Building{coordinates,offset:[0.;2],heading,dimensions,module})
    }).collect()
}
