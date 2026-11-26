use crate::{camera::{dot,frame,geographic,Camera},landscape_cover::{CoverPack, RegionalCover, RegionalFrame, REGIONAL_BANKS, REGIONAL_SLOTS},render::write_texture_layer,terrain_detail};
use flate2::read::ZlibDecoder;
use serde::Deserialize;
use std::{collections::{HashMap,HashSet},fs,io::{self,Read,Seek,SeekFrom},path::{Path,PathBuf},sync::{mpsc,Arc},time::{Duration,Instant}};
use winit::event_loop::EventLoopProxy;
use wwo_map_lab::{battlefield_terrain::{BattlefieldTerrain, REGION_BOUNDS}, military_grid::MilitaryCell};

pub const VERSION: &str = "worldcrs84quad-z4-v3";
pub const PACK_VERSION: &str = "worldcrs84quad-15s-v1";
pub const COMPACT_VERSION: &str = "worldcrs84quad-15s-v2";
pub const HYDROLOGY_DIRECTORY: &str = "worldcrs84quad-15s-v2-hydrology";
const PACK_MAGIC: &[u8;8] = b"WWOQ4PK1";
const COMPACT_MAGIC: &[u8;8] = b"WWOQ4PK2";
const RECORD_HEADER: usize = 16;
const COLOR_MAGIC: &[u8;8] = b"WWOQ3BC7";
const HEIGHT_MAGIC: &[u8;8] = b"WWOQ3I16";
const HEADER_LEN: usize = 20;
const RIVER_REACHES: u64 = 8_477_883;
const TILE_SIZE: u32 = 256;
const GUTTER: u32 = 4;
const PAGE_SIZE: u32 = TILE_SIZE+2*GUTTER;
const MAX_LEVEL: u32 = 7;
const MAX_PAGES: u32 = 160;
const MAX_PACK_PAGES: u32 = 256;
const FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Bc7RgbaUnorm;
const LOD_HYSTERESIS: f64 = 0.12;
const PAGE_BLEND_COLLAR: f64 = 0.04;
const PAGE_FADE_SECONDS: f32 = 0.22;
const GROUPED_LOD_START: u32 = 1;
const GROUPED_LOD_COUNT: usize = (MAX_LEVEL-GROUPED_LOD_START+1) as usize;
const GROUPED_LOADS_PER_FRAME: u32 = 3;
const COARSE_CACHE_LEVEL: u32 = 3;
// Request ahead of the 625 m/px blend in landscape.wgsl.
const REGIONAL_PREFETCH_MPP: f64 = 750.;

pub fn compact_files_present(root: &Path) -> bool {
    root.join("index.json").is_file()
        && root.join("river-topology.u32").is_file()
        && (0..=MAX_LEVEL).all(|z| root.join(format!("{z}.qpk")).is_file())
}

fn grouped_lod(level:u32)->Option<usize> {
    level.checked_sub(GROUPED_LOD_START).map(|index|index as usize).filter(|index|*index<GROUPED_LOD_COUNT)
}

#[derive(Clone,Copy,Debug,PartialEq,Eq,Hash,Deserialize,serde::Serialize)]
pub struct Key(pub u32,pub u32,pub u32);

#[derive(Clone,Copy,Default,serde::Serialize)]
#[serde(rename_all="snake_case")]
pub enum LayerSelection {
    #[default]
    Auto,
    Maximum(u32),
    Exact(u32),
}

impl LayerSelection {
    pub fn limit(self)->u32 {
        match self {Self::Auto=>MAX_LEVEL, Self::Maximum(z)|Self::Exact(z)=>z}
    }

    pub fn exact(self)->bool {matches!(self,Self::Exact(_))}
}

impl Key {
    fn path(self, root:&Path) -> PathBuf {
        let Self(z,x,y)=self;
        root.join(z.to_string()).join(x.to_string()).join(format!("{y}.bc7"))
    }

    fn bounds(self) -> [f64;4] {
        let Self(z,x,y)=self;
        let step=360.0/f64::from(2<<z);
        let west=-180.0+f64::from(x)*step;
        let north=90.0-f64::from(y)*step;
        [west,north-step,west+step,north]
    }

    fn intersects_viewport_cap(self, longitude: f64, [sin_lat, cos_lat]: [f64; 2], min_dot: f64) -> bool {
        let [west, south, east, north] = self.bounds();
        let half_span = (east - west) * 0.5;
        // Include pages needed by the four-percent blend in page_coverage.
        let padding = 2. * half_span * PAGE_BLEND_COLLAR;
        let longitude_offset = (longitude - (west + half_span) + 180.).rem_euclid(360.) - 180.;
        let delta = (longitude_offset.abs() - half_span - padding).max(0.).to_radians();
        let along_longitude = cos_lat * delta.cos();
        let south = (south - padding).max(-90.).to_radians();
        let north = (north + padding).min(90.).to_radians();

        // The nearest longitude maximizes the dot product at every latitude.
        // Its latitude maximum is either stationary or at an endpoint.
        let closest_latitude = sin_lat.atan2(along_longitude);
        let closest = if (south..=north).contains(&closest_latitude) {
            along_longitude.hypot(sin_lat)
        } else {
            let at = |latitude: f64| {
                let (sin, cos) = latitude.sin_cos();
                along_longitude * cos + sin_lat * sin
            };
            at(south).max(at(north))
        };
        closest >= min_dot - 1e-12
    }

    fn texel(self) -> wgpu::Origin3d {
        wgpu::Origin3d {
            x:self.1,
            y:self.2+(1<<self.0)-1,
            z:0,
        }
    }
}

pub struct Catalogue {pages:Vec<Key>, source:Source, max_level:u32, version:&'static str,
    selection:LayerSelection, layer_candidate:Option<PathBuf>, cover_root:Option<PathBuf>,
    river_lines:Option<PathBuf>, water_geometry:Option<PathBuf>}

#[derive(Deserialize)]
struct Manifest {
    version:String,
    tile_matrix_set:String,
    axes:String,
    origin:[i32;2],
    tile_size:u32,
    gutter:u32,
    levels:Vec<Level>,
    river_topology:RiverTopology,
}

#[derive(Deserialize)]
struct Level {z:u32,width:u32,height:u32,tiles:u32,bytes:u64}

#[derive(Deserialize)]
struct RiverTopology {file:String,reaches:u64,unresolved_downstream_ids:u64}

/// Read the actual map elevations for the selected cell's 50 km parent and project
/// them into the shared battlefield coordinate system. The lattice interpolates Z7
/// samples, whose latitude spacing is about 610 m.
pub fn battlefield(root: &Path, cell: MilitaryCell) -> io::Result<(BattlefieldTerrain, Vec<[u32; 3]>)> {
    const SPACING_M: u32 = 250;
    let manifest: Manifest = serde_json::from_reader(fs::File::open(root.join("index.json"))?)?;
    let width = 2 << MAX_LEVEL;
    let height = 1 << MAX_LEVEL;
    let level = manifest.levels.into_iter().find(|level| level.z == MAX_LEVEL)
        .filter(|level| (level.width, level.height, level.tiles) == (width, height, width * height));
    let Some(level) = level.filter(|_| manifest.version == COMPACT_VERSION
        && manifest.tile_matrix_set == "WorldCRS84Quad" && manifest.axes == "longitude,latitude"
        && manifest.origin == [-180, 90] && manifest.tile_size == TILE_SIZE && manifest.gutter == GUTTER
        && cell.is_valid()) else {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "军事格需要有效的 Z7 全球高程资源"));
    };
    let mut pack = LevelPack::open(&root.join(format!("{MAX_LEVEL}.qpk")), level, COMPACT_VERSION)?;
    let mut land_cover = CoverPack::FILE_NAMES.iter().map(|name| root.join(name))
        .find(|path| path.is_file()).map(|path| CoverPack::open(&path, PAGE_SIZE)).transpose()?;
    let mut pages = HashMap::new();
    let region = cell.region();
    let [min_x, min_z, max_x, max_z] = REGION_BOUNDS;
    let spacing = f64::from(SPACING_M);
    let columns = ((max_x - min_x) / spacing) as usize + 1;
    let rows = ((max_z - min_z) / spacing) as usize + 1;
    let mut heights = Vec::with_capacity(columns * rows);
    let mut cover = Vec::with_capacity(columns * rows);
    let texels_per_degree = f64::from(width * TILE_SIZE) / 360.;
    let tile_size = f64::from(TILE_SIZE);
    for row in 0..rows {
        for col in 0..columns {
            let [lon, lat] = region.local_to_lon_lat([min_x + col as f64 * spacing, min_z + row as f64 * spacing]);
            let u = (lon + 180.) * texels_per_degree;
            let v = (90. - lat) * texels_per_degree;
            let x = (u / tile_size).floor() as u32;
            let y = (v / tile_size).floor() as u32;
            let key = Key(MAX_LEVEL, x, y);
            let page = match pages.entry(key) {
                std::collections::hash_map::Entry::Occupied(entry) => entry.into_mut(),
                std::collections::hash_map::Entry::Vacant(entry) => {
                    let elevations = pack.heights(key)?;
                    let cover = land_cover.as_mut().map(|pack| {
                        pack.read(MAX_LEVEL, x, y, (PAGE_SIZE * PAGE_SIZE) as usize)
                    }).transpose()?;
                    entry.insert((elevations, cover))
                }
            };
            // Source coordinates are pixel centers. Gutters contain adjoining samples.
            let local_u = u - f64::from(x * TILE_SIZE) + f64::from(GUTTER) - 0.5;
            let local_v = v - f64::from(y * TILE_SIZE) + f64::from(GUTTER) - 0.5;
            let page_width = PAGE_SIZE as usize;
            let at = local_v as usize * page_width + local_u as usize;
            let [a, b, c, d] = [at, at + 1, at + page_width, at + page_width + 1]
                .map(|index| f64::from(page.0[index]));
            let north = a + (b - a) * local_u.fract();
            let south = c + (d - c) * local_u.fract();
            let elevation = north + (south - north) * local_v.fract();
            let nearest = local_v.round() as usize * page_width + local_u.round() as usize;
            let class = page.1.as_ref().map_or(0, |classes| classes[nearest]);
            let class = if class == 0 && elevation < 0. { 8 } else { class };
            let elevation = if class == 8 { elevation.max(0.) } else { elevation };
            heights.push(elevation as f32);
            cover.push(class);
        }
    }
    let mut keys: Vec<_> = pages.keys().map(|key| [key.0, key.1, key.2]).collect();
    keys.sort_unstable();
    Ok((BattlefieldTerrain::from_geographic_heights(SPACING_M, heights, cover)?, keys))
}

impl Catalogue {
    pub fn open(root:&Path,packed:bool,selection:LayerSelection,layer_candidate:Option<PathBuf>) -> io::Result<Self> {
        let path=root.join("index.json");
        let open=|| {
            let data:Manifest=serde_json::from_reader(fs::File::open(&path)?)?;
            let version=match (packed,data.version.as_str()) {
                (false,VERSION)=>VERSION,
                (true,PACK_VERSION)=>PACK_VERSION,
                (true,COMPACT_VERSION)=>COMPACT_VERSION,
                _=>return Err(io::Error::other("自然地貌底图库版本不匹配")),
            };
            let levels=data.levels.len();
            let valid_levels=match version {
                COMPACT_VERSION=>levels==MAX_LEVEL as usize+1,
                PACK_VERSION=>(6..=MAX_LEVEL as usize+1).contains(&levels),
                _=>levels==5,
            };
            if data.tile_matrix_set!="WorldCRS84Quad" || data.axes!="longitude,latitude"
                || data.origin!=[-180,90]
                || data.tile_size!=TILE_SIZE || data.gutter!=GUTTER || !valid_levels {
                return Err(io::Error::other("自然地貌底图库版本或坐标不匹配"));
            }
            if !matches!(selection,LayerSelection::Auto) && selection.limit()>=levels as u32 {
                return Err(io::Error::other("指定地貌层级超出资源范围"));
            }
            if layer_candidate.is_some() && (!selection.exact() || !packed) {
                return Err(io::Error::other("单层候选 QPK 需要指定层级及 QPK 底图库"));
            }
            let mut pages=Vec::new();
            let mut packs=Vec::new();
            let mut lengths=[0;MAX_LEVEL as usize+1];
            for (z,mut level) in (0..).zip(data.levels) {
                lengths[z as usize]=level.bytes;
                let [width,height]=[2<<z,1<<z];
                if (z,width,height,width*height)!=(level.z,level.width,level.height,level.tiles) {
                    return Err(io::Error::other(format!("Z{z} 全球分片清单不完整")));
                }
                if packed {
                    let replacement=layer_candidate.as_ref().filter(|_|z==selection.limit());
                    let pack=if selection.exact() && z!=selection.limit() {None} else {
                        let path=replacement.cloned().unwrap_or_else(||root.join(format!("{z}.qpk")));
                        if replacement.is_some() {level.bytes=fs::metadata(&path)?.len();}
                        Some(LevelPack::open(&path,level,version)?)
                    };
                    packs.push(pack);
                }
                if z>selection.limit() || selection.exact() && z!=selection.limit() {continue;}
                for y in 0..height {
                    for x in 0..width {
                        let key=Key(z,x,y);
                        if !packed {
                            let path=key.path(root);
                            open_tile(&path,key,COLOR_MAGIC,1)?;
                            open_tile(&path.with_extension("i16"),key,HEIGHT_MAGIC,2)?;
                        }
                        if z>0 {pages.push(key);}
                    }
                }
            }
            let river=data.river_topology;
            if river.file!="river-topology.u32" || river.reaches!=RIVER_REACHES || river.unresolved_downstream_ids!=0
                || fs::metadata(root.join(&river.file))?.len()!=RIVER_REACHES*8 {
                return Err(io::Error::other("全球河网的拓扑资料不完整"));
            }
            let water_path=root.join("hydrology-color.qhw");
            let river_path=root.join("river-centrelines.qhl");
            let geometry_path=root.join("water-geometry.qwg");
            let use_water=layer_candidate.is_none();
            let water=if use_water && water_path.is_file() {
                if version!=COMPACT_VERSION || !river_path.is_file() {
                    return Err(io::Error::other("水文修订需要匹配的 QPK 和河流中心线"));
                }
                Some(WaterColors::open(&water_path,lengths)?)
            } else {None};
            let river_lines=(use_water&&!selection.exact()&&selection.limit()>=4&&river_path.is_file()).then_some(river_path);
            let water_geometry=(use_water&&!selection.exact()&&selection.limit()>=4
                && version==COMPACT_VERSION&&geometry_path.is_file()).then_some(geometry_path);
            let source=if packed {Source::Packs(packs,water)} else {Source::Files(root.to_owned())};
            let cover_root=(version==COMPACT_VERSION && selection.limit()>=6).then(||root.to_owned());
            Ok(Self{pages,source,max_level:levels as u32-1,version,selection,layer_candidate,cover_root,river_lines,water_geometry})
        };
        open().map_err(|error|io::Error::other(format!("无法读取自然地貌底图库。{} · {error}",path.display())))
    }

    pub fn river_lines(&self)->Option<&Path> {self.river_lines.as_deref()}
    pub fn water_geometry(&self)->Option<&Path> {self.water_geometry.as_deref()}
}

enum Source {Files(PathBuf),Packs(Vec<Option<LevelPack>>,Option<WaterColors>)}

impl Source {
    fn read(&mut self,key:Key,cover:Option<&mut CoverPack>,landscape:bool)->io::Result<DecodedTile> {
        match self {
            Self::Files(root)=>{
                let mut file=open_tile(&key.path(root),key,COLOR_MAGIC,1)?;
                let mut bytes=vec![0;(PAGE_SIZE*PAGE_SIZE) as usize];
                file.read_exact(&mut bytes)?;
                Ok(DecodedTile{pixels:bytes,landscape:None,classified:false,decode_time:Duration::ZERO})
            }
            Self::Packs(packs,water)=>{
                let override_frame=water.as_mut().map(|colors|colors.frame(key)).transpose()?.flatten();
                packs[key.0 as usize].as_mut().ok_or_else(||io::Error::other("地貌层级未打开"))?
                    .read(key,cover,landscape,override_frame)
            }
        }
    }
}

struct WaterColors {file:fs::File, offsets:Vec<u64>}

impl WaterColors {
    fn open(path:&Path,lengths:[u64;8])->io::Result<Self> {
        let mut file=fs::File::open(path)?;
        let mut header=[0;72];
        file.read_exact(&mut header)?;
        if &header[..8]!=b"WWOHYD01" || header[8..].chunks_exact(8).zip(lengths)
            .any(|(bytes,len)|bytes!=len.to_le_bytes()) {
            return Err(io::Error::other("水文颜色与此 QPK 版本不匹配"));
        }
        let pages=(0..=MAX_LEVEL).map(|z|2<<(2*z)).sum::<usize>();
        let mut raw=vec![0;(pages+1)*8];
        file.read_exact(&mut raw)?;
        let offsets:Vec<_>=raw.chunks_exact(8).map(|bytes|u64::from_le_bytes(bytes.try_into().unwrap())).collect();
        if offsets[0]!=(header.len()+raw.len()) as u64 || offsets.last()!=Some(&file.metadata()?.len())
            || offsets.windows(2).any(|range|range[1].checked_sub(range[0])
                .is_none_or(|len|len>u64::from(PAGE_SIZE*PAGE_SIZE+1024))) {
            return Err(io::Error::other("水文颜色页索引无效"));
        }
        Ok(Self{file,offsets})
    }

    fn frame(&mut self,Key(z,x,y):Key)->io::Result<Option<Vec<u8>>> {
        let preceding=(0..z).map(|level|2<<(2*level)).sum::<u32>();
        let index=(preceding+y*(2<<z)+x) as usize;
        let offset=self.offsets[index];
        let len=self.offsets[index+1]-offset;
        if len==0 {return Ok(None);}
        let mut frame=vec![0;len as usize];
        self.file.seek(SeekFrom::Start(offset))?;
        self.file.read_exact(&mut frame)?;
        Ok(Some(frame))
    }
}

enum ColorDecoder {
    Deflate,
    Zstandard(zstd::bulk::Decompressor<'static>),
}

struct LevelPack {file:fs::File,width:u32,offsets:Vec<u64>,decoder:ColorDecoder}

impl LevelPack {
    fn open(path:&Path,level:Level,version:&str)->io::Result<Self> {
        let mut file=fs::File::open(path)?;
        let mut header=[0;HEADER_LEN];
        file.read_exact(&mut header)?;
        let magic=if version==COMPACT_VERSION {COMPACT_MAGIC} else {PACK_MAGIC};
        if &header[..8]!=magic || header[8..12]!=level.z.to_le_bytes()
            || header[12..16]!=level.width.to_le_bytes() || header[16..20]!=level.height.to_le_bytes()
            || file.metadata()?.len()!=level.bytes {
            return Err(io::Error::other(format!("Z{} 地貌包版本、尺寸或层级无效",level.z)));
        }
        let mut raw=vec![0;(level.tiles as usize+1)*8];
        file.read_exact(&mut raw)?;
        let offsets:Vec<_>=raw.chunks_exact(8).map(|b|u64::from_le_bytes(b.try_into().unwrap())).collect();
        if offsets[0]!=(HEADER_LEN+raw.len()) as u64 || offsets.last()!=Some(&level.bytes)
            || offsets.windows(2).any(|p|p[1].checked_sub(p[0]).is_none_or(|n|!(17..=220_000).contains(&n))) {
            return Err(io::Error::other(format!("Z{} 地貌包索引无效",level.z)));
        }
        let decoder=if version==COMPACT_VERSION {
            ColorDecoder::Zstandard(zstd::bulk::Decompressor::new()?)
        } else {ColorDecoder::Deflate};
        Ok(Self{file,width:level.width,offsets,decoder})
    }

    fn record(&mut self, key: Key) -> io::Result<(u32, usize)> {
        let Key(z,x,y)=key;
        if x>=self.width || y>=self.width/2 {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "地貌分片超出范围"));
        }
        let i=(y*self.width+x) as usize;
        let offset=self.offsets[i];
        let mut header=[0;RECORD_HEADER];
        self.file.seek(SeekFrom::Start(offset))?;
        self.file.read_exact(&mut header)?;
        let count=u32::from_le_bytes(header[12..16].try_into().unwrap());
        if header[..4]!=z.to_le_bytes() || header[4..8]!=x.to_le_bytes() || header[8..12]!=y.to_le_bytes()
            || count==0 || offset+RECORD_HEADER as u64+u64::from(count)>=self.offsets[i+1] {
            return Err(io::Error::other(format!("地貌包分片坐标或大小无效 · Z{z}/{x}/{y}")));
        }
        let height_len=(self.offsets[i+1]-offset-RECORD_HEADER as u64-u64::from(count)) as usize;
        Ok((count, height_len))
    }

    fn heights(&mut self, key: Key) -> io::Result<Vec<i16>> {
        let (color_len, height_len) = self.record(key)?;
        let ColorDecoder::Zstandard(decoder) = &mut self.decoder else {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "军事格需要 compact QPK 高程"));
        };
        self.file.seek(SeekFrom::Current(i64::from(color_len)))?;
        let mut frame = vec![0; height_len];
        self.file.read_exact(&mut frame)?;
        let size = (PAGE_SIZE * PAGE_SIZE) as usize;
        let residual = decoder.decompress(&frame, size * 2)?;
        let mut heights = Vec::with_capacity(size);
        unpack_heights(&residual, |_, height| heights.push(height as i16))?;
        Ok(heights)
    }

    fn read(&mut self,key:Key,cover:Option<&mut CoverPack>,landscape:bool,override_frame:Option<Vec<u8>>)->io::Result<DecodedTile> {
        let Key(z,x,y)=key;
        let (count,height_len)=self.record(key)?;
        let size=(PAGE_SIZE*PAGE_SIZE) as usize;
        let mut frame=if let Some(frame)=override_frame {
            self.file.seek(SeekFrom::Current(i64::from(count)))?;
            frame
        } else {
            let mut frame=vec![0;count as usize];
            self.file.read_exact(&mut frame)?;
            frame
        };
        let started=Instant::now();
        let pixels=match &mut self.decoder {
            ColorDecoder::Deflate=>{
                let mut pixels=Vec::with_capacity(size);
                ZlibDecoder::new(frame.as_slice()).take(size as u64+1).read_to_end(&mut pixels)?;
                pixels
            }
            ColorDecoder::Zstandard(decoder)=>decoder.decompress(&frame,size)?,
        };
        if pixels.len()!=size {
            return Err(io::Error::other(format!("地貌包颜色数据大小无效 · Z{z}/{x}/{y}")));
        }
        let (landscape,classified)=match &mut self.decoder {
            ColorDecoder::Zstandard(decoder) if z>=6&&landscape=>{
                frame.resize(height_len,0);
                self.file.read_exact(&mut frame)?;
                let residual=decoder.decompress(&frame,size*2)?;
                let classes=cover.and_then(|cover|match cover.read(z,x,y,size) {
                    Ok(classes)=>Some(classes),
                    Err(error)=>{
                        eprintln!("Landscape cover unavailable at {z}/{x}/{y}: {error}");
                        None
                    }
                });
                let classified=classes.as_ref().is_some_and(|cells|cells.iter().any(|&class|class!=0));
                (Some(landscape_pixels(&residual,classes.as_deref())?),classified)
            }
            _=>(None,false),
        };
        Ok(DecodedTile{pixels,landscape,classified,decode_time:started.elapsed()})
    }
}

fn open_tile(path:&Path,key:Key,magic:&[u8;8],bytes_per_pixel:u32) -> io::Result<fs::File> {
    let size=u64::from(PAGE_SIZE*PAGE_SIZE*bytes_per_pixel)+HEADER_LEN as u64;
    let mut file=fs::File::open(path)?;
    if file.metadata()?.len()!=size {
        return Err(io::Error::other(format!("地貌资源大小无效 · {}",path.display())));
    }
    let mut header=[0;HEADER_LEN];
    file.read_exact(&mut header)?;
    if &header[..8]!=magic || header[8..12]!=key.0.to_le_bytes()
        || header[12..16]!=key.1.to_le_bytes() || header[16..20]!=key.2.to_le_bytes() {
        return Err(io::Error::other(format!("地貌资源版本或分片坐标不匹配 · {}",path.display())));
    }
    Ok(file)
}

fn unpack_heights(residual: &[u8], mut sample: impl FnMut(usize, u16)) -> io::Result<()> {
    let width=PAGE_SIZE as usize;
    let size=width*width;
    if residual.len()!=size*2 {
        return Err(io::Error::other("近景地貌高程数据大小无效"));
    }
    let mut above=[0u16;PAGE_SIZE as usize];
    for y in 0..width {
        let mut height=0u16;
        for (x,column) in above.iter_mut().enumerate() {
            let i=y*width+x;
            let zigzag=u16::from_le_bytes([residual[i],residual[i+size]]);
            let delta=(zigzag>>1)^0u16.wrapping_sub(zigzag&1);
            *column=column.wrapping_add(delta);
            height=height.wrapping_add(*column);
            sample(i, height);
        }
    }
    Ok(())
}

fn landscape_pixels(residual:&[u8],classes:Option<&[u8]>)->io::Result<Vec<u8>> {
    let mut pixels=Vec::with_capacity((PAGE_SIZE*PAGE_SIZE*4) as usize);
    unpack_heights(residual, |i, height| {
        let [low,high]=(height^0x8000).to_le_bytes();
        let class=classes.map_or(0,|cells|cells[i]);
        pixels.extend([low,high,if matches!(class,1|10) {255}else{0},class*17]);
    })?;
    Ok(pixels)
}

pub struct DecodedTile {
    pixels:Vec<u8>,
    landscape:Option<Vec<u8>>,
    classified:bool,
    pub decode_time:Duration,
}
pub struct Completion {pub key:Key,pub requested:Instant,pub result:io::Result<DecodedTile>}

enum DecodeRequest {
    Page(Key, Instant),
    Regional(Key),
    Detail(usize, Arc<terrain_detail::Catalogue>),
}

struct Page {
    slot:u32,
    regional_slot:Option<u32>,
    regional_near_only:bool,
    ready:Option<Instant>,
    used:Instant,
    fade:u8,
    landscape_fade:Option<u8>,
    classified:bool,
}

impl Page {
    fn index(&self)->u64 {
        // Nine bits for the QPK slot, seven for the regional cover slot.
        let slots=(u32::from(self.landscape_fade.unwrap_or(0))<<24)
            | (u32::from(self.fade)<<16) | (self.regional_slot.map_or(0,|slot|slot+1)<<9) | (self.slot+1);
        u64::from(slots) | (u64::from(self.regional_near_only && self.regional_slot.is_some())<<32)
    }
}

struct Visible {key:Key,axis:[f64;3],radius:f64}

#[derive(Default)]
struct ViewportTransition {
    visible:Vec<Key>,
    missing:usize,
    mix:f32,
    goal:f32,
    previous:Option<Instant>,
}

impl ViewportTransition {
    fn update(&mut self,pages:&HashMap<Key,Page>,level:u32,target:bool,lod:f64,now:Instant) {
        let seconds=self.previous.replace(now).map_or(0.,|then|now.saturating_duration_since(then).as_secs_f32());
        self.missing=self.visible.iter().filter(|key|!pages.contains_key(key)).count();
        // Detail appears at the same scale in both directions. Selection can
        // keep pages inside the hysteresis interval without displaying them.
        let midpoint=f64::from(level)-0.5;
        let (start,span)=if level<=4 {(midpoint-LOD_HYSTERESIS,0.05)}
            else {(midpoint+LOD_HYSTERESIS,0.37)};
        let t=((lod-start)/span).clamp(0.,1.) as f32;
        self.goal=if target {t*t*(3.-2.*t)} else {0.};
        let step=seconds.min(1./30.)/PAGE_FADE_SECONDS;
        self.mix+=(self.goal-self.mix).clamp(-step,step);
    }
}

pub struct Terrain {
    base:wgpu::Texture,
    atlas:wgpu::Texture,
    table:wgpu::Texture,
    landscape:Option<wgpu::Texture>,
    regional:Option<wgpu::Texture>,
    regional_slots:Vec<u32>,
    regional_path:Option<PathBuf>,
    regional_index:Option<Arc<HashMap<Key,RegionalFrame>>>,
    regional_wanted:HashSet<Key>,
    regional_failed:HashSet<Key>,
    height_enabled:bool,
    landscape_cover_path:Option<PathBuf>,
    water_colors:bool,
    landscape_revision:u32,
    keys:Vec<Visible>,
    sender:mpsc::Sender<DecodeRequest>,
    inflight:Option<Key>,
    requests_this_frame:u32,
    pages:HashMap<Key,Page>,
    slots:Vec<u32>,
    selected:Vec<Key>,
    view:Option<([[f64;3];3],[f64;2],f64,f64,f64,[u32;2],[f64;3])>,
    max_level:u32,
    view_max:u32,
    target_level:Option<u32>,
    projected_lod:f64,
    version:&'static str,
    selection:LayerSelection,
    layer_candidate:Option<PathBuf>,
    required_pages:usize,
    viewport_pages:usize,
    transitions:[ViewportTransition;GROUPED_LOD_COUNT],
}

impl Terrain {
    pub fn new(device:&wgpu::Device,queue:&wgpu::Queue,data:Catalogue,
               proxy:EventLoopProxy<crate::HostEvent>) -> io::Result<Self> {
        let Catalogue{pages,mut source,max_level,version,selection,layer_candidate,cover_root,..}=data;
        let water_colors=matches!(&source,Source::Packs(_,Some(_)));
        let texture=|label,width,height,layers,mips,format| device.create_texture(&wgpu::TextureDescriptor{
            label:Some(label),
            size:wgpu::Extent3d{width,height,depth_or_array_layers:layers},
            mip_level_count:mips,sample_count:1,dimension:wgpu::TextureDimension::D2,
            format,usage:wgpu::TextureUsages::TEXTURE_BINDING|wgpu::TextureUsages::COPY_DST,
            view_formats:&[],
        });
        let base=texture("Global natural terrain Z0",PAGE_SIZE,PAGE_SIZE,2,1,FORMAT);
        if !selection.exact() || selection.limit()==0 {
            for x in 0..2 {
                let tile=source.read(Key(0,x,0),None,false)?;
                write_texture_layer(queue,&base,0,x,PAGE_SIZE,&tile.pixels);
            }
        }
        let capacity=if version!=VERSION {MAX_PACK_PAGES.min(device.limits().max_texture_array_layers)} else {MAX_PAGES};
        let atlas=texture("Natural terrain page cache",PAGE_SIZE,PAGE_SIZE,capacity,1,FORMAT);
        let height_enabled=version==COMPACT_VERSION&&selection.limit()>=6;
        let (regional_path,mut regional_cover)=cover_root.as_ref().filter(|_|height_enabled)
            .and_then(|root|{
                let path=root.join(RegionalCover::FILE_NAME);
                match RegionalCover::open(&path,PAGE_SIZE) {
                    Ok(cover)=>Some((path,cover)),
                    Err(error) if error.kind()==io::ErrorKind::NotFound=>None,
                    Err(error)=>{eprintln!("Regional landscape unavailable at {}: {error}",path.display());None}
                }
            }).unzip();
        let regional_index=regional_cover.as_ref().map(RegionalCover::index);
        let (landscape_cover_path,mut cover)=cover_root.filter(|_|height_enabled).and_then(|root|{
            CoverPack::FILE_NAMES.into_iter().find_map(|name|{
                let path=root.join(name);
                match CoverPack::open(&path,PAGE_SIZE) {
                    Ok(cover)=>Some((path,cover)),
                    Err(error) if error.kind()==io::ErrorKind::NotFound=>None,
                    Err(error)=>{eprintln!("Landscape cover unavailable at {}: {error}",path.display());None}
                }
            })
        }).map_or((None,None),|(path,cover)|(Some(path),Some(cover)));
        let [width,height]=[2<<max_level,(2<<max_level)-1];
        let table=texture("Natural terrain page indices",width,height,1,1,wgpu::TextureFormat::Rg32Uint);
        let keys=pages.into_iter().map(|key|{
            let [w,s,e,n]=key.bounds();
            let axis=frame([(w+e)*0.5,(s+n)*0.5])[2];
            let radius=[(w,s),(w,n),(e,s),(e,n)].into_iter().map(|(x,y)|
                dot(axis,frame([x,y])[2]).clamp(-1.,1.).acos()).fold(0.,f64::max);
            Visible {key,axis,radius}
        }).collect();
        let (sender,receiver)=mpsc::channel();
        std::thread::Builder::new().name("WWO natural terrain".into()).spawn(move||{
            while let Ok(request)=receiver.recv() {
                let event=match request {
                    DecodeRequest::Page(key,requested)=>{
                        let result=source.read(key,cover.as_mut(),height_enabled);
                        crate::HostEvent::Terrain(Completion{key,requested,result})
                    }
                    DecodeRequest::Regional(key)=>{
                        let result=regional_cover.as_mut().ok_or(io::ErrorKind::NotFound.into())
                            .and_then(|cover|cover.read(key,PAGE_SIZE as usize));
                        crate::HostEvent::TerrainRegional(key,result)
                    }
                    DecodeRequest::Detail(index,catalogue)=>crate::HostEvent::TerrainDetail(index,catalogue.read(index)),
                };
                if proxy.send_event(event).is_err(){break;}
            }
        })?;
        Ok(Self{base,atlas,table,landscape:None,regional:None,regional_slots:(0..REGIONAL_SLOTS).rev().collect(),
            regional_path,regional_index,regional_wanted:HashSet::new(),regional_failed:HashSet::new(),
            height_enabled,landscape_cover_path,water_colors,landscape_revision:0,keys,sender,inflight:None,requests_this_frame:0,pages:HashMap::new(),
            slots:(0..capacity).rev().collect(),selected:Vec::new(),view:None,max_level,view_max:0,
            target_level:None,projected_lod:0.,version,selection,layer_candidate,required_pages:0,viewport_pages:0,
            transitions:Default::default()})
    }

    pub fn request_detail(&self, index:usize, catalogue:Arc<terrain_detail::Catalogue>) -> bool {
        self.sender.send(DecodeRequest::Detail(index,catalogue)).is_ok()
    }

    pub fn views(&self)->[wgpu::TextureView;3] {
        [self.base.create_view(&Default::default()),self.atlas.create_view(&Default::default()),
            self.table.create_view(&Default::default())]
    }

    pub fn enable_landscape(&mut self, device:&wgpu::Device)->Option<[wgpu::TextureView;2]> {
        if !self.height_enabled || self.landscape.is_some() {return None;}
        let create=|label,width,layers| device.create_texture(&wgpu::TextureDescriptor{
            label:Some(label),
            size:wgpu::Extent3d{width,height:PAGE_SIZE,depth_or_array_layers:layers},
            mip_level_count:1,sample_count:1,dimension:wgpu::TextureDimension::D2,
            format:wgpu::TextureFormat::Rgba8Unorm,usage:wgpu::TextureUsages::TEXTURE_BINDING|wgpu::TextureUsages::COPY_DST,
            view_formats:&[],
        });
        let landscape=create("Z6/Z7 elevation and landscape cover",PAGE_SIZE,self.atlas.depth_or_array_layers());
        let slots=if self.regional_index.is_some(){REGIONAL_SLOTS}else{1};
        let regional=create("Reconstructed regional landscape cover",PAGE_SIZE*REGIONAL_BANKS,slots);
        let views=[&landscape,&regional].map(|texture|texture.create_view(&wgpu::TextureViewDescriptor{
            dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()}));
        self.landscape=Some(landscape);
        self.regional=Some(regional);
        Some(views)
    }

    pub fn landscape_cover(&self)->bool {self.landscape_cover_path.is_some()}

    pub fn landscape_revision(&self)->u32 {self.landscape_revision}

    pub fn landscape_dependencies(&self, [x,y,columns,step]:[u32;4], output:&mut Vec<(Key,bool)>) {
        let size=16*step;
        // Representative sites can move by one fine longitude cell.
        let margin=f64::from(step)/f64::from(columns);
        let left=f64::from(x)/f64::from(columns)-margin;
        let right=f64::from(x+size)/f64::from(columns)+margin;
        let top=f64::from(y)/98_304.;
        let bottom=f64::from(y+size)/98_304.;
        output.clear();
        let first=if step==1 && !self.exact() {7}else{6};
        for z in first..=if step==1 || self.exact() {7}else{6} {
            let rows=1i32<<z;
            let cols=2*rows;
            let first_row=((top*f64::from(rows)).floor() as i32).clamp(0,rows-1);
            let last_row=((bottom*f64::from(rows)).floor() as i32).clamp(0,rows-1);
            let first_col=(left*f64::from(cols)).floor() as i32;
            let last_col=(right*f64::from(cols)).floor() as i32;
            for row in first_row..=last_row {
                for col in first_col..=last_col.min(first_col+cols-1) {
                    let key=Key(z,col.rem_euclid(cols) as u32,row as u32);
                    output.push((key,self.pages.get(&key).is_some_and(|page|page.landscape_fade.is_some())));
                }
            }
        }
    }

    pub fn reveal_pages(&mut self,pending:&HashSet<Key>,now:Instant) {
        // Build commands for the other pages are in the current frame. Both
        // channels of their page-table fade start on the following frame.
        for (key,page) in &mut self.pages {
            if page.ready.is_none() && !pending.contains(key) {page.ready=Some(now);}
        }
    }

    pub fn status(&self) -> serde_json::Value {
        let resident_by_level=(1..=self.max_level).map(|z|self.pages.keys().filter(|k|k.0==z).count()).collect::<Vec<_>>();
        let wanted_by_level=(1..=self.max_level).map(|z|self.selected.iter().filter(|k|k.0==z).count()).collect::<Vec<_>>();
        let mut status=serde_json::json!({
            "version": self.version,
            "selection": self.selection,
            "layer_candidate": self.layer_candidate,
            "max_level": self.max_level,
            "view_max_level": self.view_max,
            "draw_max_level": self.view_max(),
            "target_level": self.target_level,
            "projected_lod": self.projected_lod,
            "resident_by_level": resident_by_level,
            "wanted_by_level": wanted_by_level,
            "resident_detail_pages": self.pages.len(),
            "pages_waiting_for_landscape": self.pages.values().filter(|page|page.ready.is_none()).count(),
            "wanted_detail_pages": self.selected.len(),
            "required_detail_pages": self.required_pages,
            "viewport_detail_pages": self.viewport_pages,
            "exact_view_over_capacity": self.selection.exact() && self.required_pages>self.selected.len(),
            "selected_ready": self.selected.iter().all(|key|self.pages.get(key).is_some_and(|p|self.selection.exact()||p.fade==255))
                && self.transitions.iter().all(|transition|transition.mix==transition.goal),
            "detail_capacity": self.atlas.depth_or_array_layers(),
            "loading": self.inflight.is_some(),
            "hydrology_colors": self.water_colors,
            "landscape_cover": self.landscape_cover(),
            "landscape_cover_path": self.landscape_cover_path,
            "landscape_height_enabled": self.height_enabled,
            "landscape_cover_classified_pages": self.pages.values().filter(|p|p.classified).count(),
            "landscape_regional_path": self.regional_path,
            "landscape_regional_catalogue_pages": self.regional_index.as_ref().map_or(0,|index|index.len()),
            "landscape_regional_resident_pages": REGIONAL_SLOTS as usize-self.regional_slots.len(),
            "landscape_regional_wanted_pages": self.regional_wanted.len(),
            "landscape_regional_pages_by_level": ([6,7].map(|level|[self.selected.iter().filter(|key|key.0==level)
                .filter(|key|self.pages.get(key).is_some_and(|page|page.regional_slot.is_some())).count(),
                self.selected.iter().filter(|key|key.0==level).count()])),
            "landscape_regional_texture_bytes": self.regional.as_ref().map_or(0,|texture|
                texture.width()*texture.height()*texture.depth_or_array_layers()*4),
            "landscape_texture_bytes": self.landscape.as_ref().map_or(0,|texture|
                texture.width()*texture.height()*texture.depth_or_array_layers()*4),
            "texture_payload_bytes": PAGE_SIZE * PAGE_SIZE * (2 + self.atlas.depth_or_array_layers()) + 4 * self.table.width() * self.table.height(),
        });
        for (i,transition) in self.transitions.iter().enumerate() {
            let level=GROUPED_LOD_START+i as u32;
            let weight=if self.exact() && self.view_max==level {1.} else {transition.mix};
            status[format!("z{level}_view_weight")]=weight.into();
            status[format!("z{level}_view_pages")]=transition.visible.len().into();
            status[format!("z{level}_view_missing_pages")]=transition.missing.into();
        }
        status
    }

    pub fn max_level(&self)->u32 {self.max_level}
    pub fn view_max(&self)->u32 {
        if self.exact() {return self.view_max;}
        self.transitions.iter().rposition(|transition|transition.mix>0.)
            .map_or(self.view_max.min(GROUPED_LOD_START-1),|index|GROUPED_LOD_START+index as u32)
    }

    pub fn view_demand(&self)->u32 {self.view_max}
    pub fn viewport_mix(&self)->[[f32;4];2] {
        let mut weights=[[-1.;4];2];
        for (index,transition) in self.transitions.iter().enumerate() {
            let level=GROUPED_LOD_START as usize+index;
            weights[level/4][level%4]=transition.mix;
        }
        weights
    }
    pub fn packed(&self)->bool {self.version!=VERSION}
    pub fn exact(&self)->bool {self.selection.exact()}

    pub fn frame_samples(&self,camera:&Camera,size:[u32;2])->serde_json::Value {
        let [left,top]=[0.5,0.5];
        let [right,bottom]=size.map(|n|f64::from(n)-0.5);
        let [x,y]=size.map(|n|f64::from(n/2)+0.5);
        let points=[("center",[x,y]),("north",[x,top]),("east",[right,y]),("south",[x,bottom]),("west",[left,y]),
            ("northwest",[left,top]),("northeast",[right,top]),("southeast",[right,bottom]),("southwest",[left,bottom])];
        let samples=points.map(|(name,pixel)|{
            let sample=camera.vector(pixel,size).map(geographic).map(|ll|{
                let coordinates=ll.map(|n|n as f32);
                let lon=coordinates[0]/360.+0.5;
                let uv=[(lon-lon.floor()).min(0.99999994),(0.5-coordinates[1]/180.).clamp(0.,0.99999994)];
                let target=cell(uv,self.target_level.unwrap_or(0)).0;
                let mut remaining=1.;
                let mut contributors=Vec::new();
                let mut missing=false;
                for z in (1..=self.view_max()).rev() {
                    let (key,q)=cell(uv,z);
                    let coverage=if self.exact() {f32::from(self.pages.contains_key(&key) as u8)}
                        else if let Some(index)=grouped_lod(z) {
                            self.coverage(key,q)*self.transitions[index].mix
                        }
                        else {self.coverage(key,q)};
                    let weight=remaining*coverage;
                    if weight>0. {contributors.push((key,weight));}
                    remaining-=weight;
                    if self.exact() {missing=coverage==0.;break;}
                    if remaining<0.0001 {break;}
                }
                if !missing && remaining>=0.0001 {contributors.push((cell(uv,0).0,remaining));}
                serde_json::json!({"lon_lat":ll,"target":target,"contributors":contributors,"missing_exact_page":missing})
            });
            serde_json::json!({"name":name,"pixel":pixel,"terrain":sample})
        });
        serde_json::json!({"method":"cpu_projection_and_submitted_gpu_page_table","samples":samples})
    }

    fn coverage(&self,key:Key,q:[f32;2])->f32 {
        let Some(page)=self.pages.get(&key) else {return 0.;};
        let fade=f32::from(page.fade)/255.;
        let rim=q.map(|p|p.min(1.-p));
        let [x,y]=q.map(|p|if p>0.5 {1} else {-1});
        let Key(z,column,row)=key;
        let columns=2i32<<z;
        let rows=1i32<<z;
        let readiness=|dx:i32,dy:i32| {
            let column=(column as i32+dx).rem_euclid(columns) as u32;
            let row=(row as i32+dy).clamp(0,rows-1) as u32;
            self.pages.get(&Key(z,column,row)).map_or(0.,|p|f32::from(p.fade)/255.)
        };
        let collar=PAGE_BLEND_COLLAR as f32;
        let [edge_x,edge_y]=[
            if rim[0]<collar {fade.min(readiness(x,0))} else {fade},
            if rim[1]<collar {fade.min(readiness(0,y))} else {fade},
        ];
        let mut corner=edge_x.min(edge_y);
        if rim[0].max(rim[1])<collar {corner=corner.min(readiness(x,y));}
        let [tx,ty]=rim.map(|p|{let t=(p/collar).clamp(0.,1.);t*t*(3.-2.*t)});
        let mix=|a,b,t|a+(b-a)*t;
        mix(mix(corner,edge_y,tx),mix(edge_x,fade,tx),ty)
    }

    pub fn update(&mut self,queue:&wgpu::Queue,camera:&Camera,size:[u32;2],now:Instant) {
        let middle=size.map(|dimension|f64::from(dimension)*0.5);
        let center=camera.vector(middle,size).unwrap_or(camera.axes[2]);
        let (axes,origin)=camera.projection(size);
        let view=(axes,origin,camera.mpp,camera.blend(),camera.pitch(),size,center);
        if self.view!=Some(view) {
            let previous=self.view.as_ref().map(|(..,center)|*center);
            self.view=Some(view);
            self.select(camera,center,previous,size,now);
        }
        for (&key,page) in &mut self.pages {
            if page.fade==255 && page.landscape_fade.is_none_or(|fade|fade==255) {continue;}
            let Some(ready)=page.ready else {continue;};
            let progress=(now.saturating_duration_since(ready).as_secs_f32()/PAGE_FADE_SECONDS).clamp(0.,1.);
            let fade=(progress*255.).round() as u8;
            let before=page.index();
            page.fade=page.fade.max(fade);
            if let Some(previous)=&mut page.landscape_fade {*previous=(*previous).max(fade);}
            if before!=page.index() {
                Self::write_index(&self.table,queue,key,page.index());
            }
        }
        let exact=self.exact();
        for (index,transition) in self.transitions.iter_mut().enumerate() {
            let level=GROUPED_LOD_START+index as u32;
            transition.update(&self.pages,level,!exact && self.view_max>=level,self.projected_lod,now);
        }
        self.requests_this_frame=0;
        self.request_page(now);
    }

    fn request_page(&mut self,now:Instant) {
        if self.inflight.is_some(){return;}
        let next=self.selected.iter().find_map(|&key|match self.pages.get(&key) {
            None=>Some((key,DecodeRequest::Page(key,now))),
            Some(page) if page.landscape_fade.is_some() && page.regional_slot.is_none()
                && self.regional_wanted.contains(&key) && !self.regional_failed.contains(&key)
                =>Some((key,DecodeRequest::Regional(key))),
            _=>None,
        });
        if let Some((key,request))=next.filter(|_|self.requests_this_frame<GROUPED_LOADS_PER_FRAME) {
            if self.sender.send(request).is_ok(){
                self.inflight=Some(key);
                self.requests_this_frame+=1;
            }
        }
    }

    fn select(&mut self,camera:&Camera,center:[f64;3],previous:Option<[f64;3]>,size:[u32;2],now:Instant) {
        self.projected_lod=projected_lod(camera,center,size);
        let limit=self.max_level.min(self.selection.limit());
        let lod=self.projected_lod.clamp(0.,f64::from(limit));
        let threshold=0.5+LOD_HYSTERESIS;
        let low=(lod-threshold).ceil() as u32;
        let high=(lod+threshold).floor() as u32;
        let target=if self.selection.exact() {limit} else {self.target_level.unwrap_or(lod.round() as u32).clamp(low,high).min(limit)};
        self.target_level=Some(target);
        self.selected.clear();
        let viewport=camera.extent(size,0.);
        let prefetch=camera.extent(size,180.);
        let ahead=previous.map_or(center,|previous| {
            let movement=std::array::from_fn::<_,3,_>(|i|center[i]-previous[i]);
            let distance=dot(movement,movement).sqrt();
            let fraction=(prefetch-viewport).max(0.)/distance.max(1e-8);
            std::array::from_fn(|i|center[i]+movement[i]*fraction.min(3.))
        });
        let exact=self.selection.exact();
        let capacity=self.atlas.depth_or_array_layers() as usize;
        // Keep the coarse globe in spare slots while crossing the two adjacent transitions.
        let coarse_pages=((1usize..=COARSE_CACHE_LEVEL as usize).map(|level|2<<(2*level))).sum::<usize>();
        let reserve_coarse=!exact && (COARSE_CACHE_LEVEL..=COARSE_CACHE_LEVEL+1).contains(&target)
            && capacity>=coarse_pages;
        let half_diagonal=f64::from(size[0]).hypot(f64::from(size[1])/camera.pitch().cos())*0.5;
        // Keep a grouped parent ready for a rapid zoom-out. A mip
        // doubles the span, including the ordinary margin, without adding atlas slots.
        let parent_prefetch=if !exact && target>GROUPED_LOD_START {
            camera.extent(size,half_diagonal+360.)
        } else {0.};
        // Spare slots can retain detail through about three outward wheel steps.
        // Visible pages, the ordinary margin and the immediate parent have priority.
        let retreat_prefetch=if !exact && target==MAX_LEVEL {camera.extent(size,half_diagonal*0.85)}else{0.};
        let mut needed=[false;GROUPED_LOD_COUNT];
        let mut inspected=target;
        for (index,transition) in self.transitions.iter_mut().enumerate() {
            let level=GROUPED_LOD_START+index as u32;
            needed[index]=!exact && (target>=level || transition.mix>0.);
            if needed[index] {inspected=inspected.max(level);}
            transition.visible.clear();
        }
        // Near the poles a page is much narrower than its bounding cap.
        // Count the padded geographic bounds before applying the atlas budget.
        let polar_view = (!exact && inspected >= 5 && center[1].abs() >= 80_f64.to_radians().sin()).then(|| {
            let longitude = center[0].atan2(center[2]).to_degrees();
            let latitude = [center[1], center[0].hypot(center[2])];
            (longitude, latitude, viewport.cos())
        });
        let mut near=Vec::new();
        self.viewport_pages=0;
        for tile in self.keys.iter().take_while(|tile|tile.key.0<=inspected) {
            let proximity=dot(center,tile.axis);
            let near_view=proximity>=(prefetch+tile.radius).min(std::f64::consts::PI).cos();
            let reserved=(reserve_coarse && tile.key.0<=COARSE_CACHE_LEVEL)
                || (parent_prefetch>0. && tile.key.0<target
                    && proximity>=(parent_prefetch+tile.radius).min(std::f64::consts::PI).cos());
            let retreat_detail=retreat_prefetch>0. && tile.key.0==MAX_LEVEL
                && proximity>=(retreat_prefetch+tile.radius).min(std::f64::consts::PI).cos();
            let prefetch_page = near_view || reserved || retreat_detail;
            let in_view = if let Some((longitude, latitude, min_dot)) = polar_view {
                // A geographic collar adds at most this angular distance to the tile cap.
                let padding = std::f64::consts::PI / f64::from(1 << tile.key.0)
                    * PAGE_BLEND_COLLAR * std::f64::consts::SQRT_2;
                proximity >= (viewport + tile.radius + padding).min(std::f64::consts::PI).cos()
                    && tile.key.intersects_viewport_cap(longitude, latitude, min_dot)
            } else {
                prefetch_page && proximity >= (viewport + tile.radius).min(std::f64::consts::PI).cos()
            };
            if prefetch_page || in_view {
                if in_view {
                    if let Some(index)=grouped_lod(tile.key.0).filter(|&index|needed[index]) {
                        self.transitions[index].visible.push(tile.key);
                    }
                }
                if tile.key.0<=target {
                    self.viewport_pages+=usize::from(in_view);
                    let priority=if !exact && in_view {5} else if near_view {3}
                        else if target==MAX_LEVEL && tile.key.0+1==target {2}
                        else {u8::from(retreat_detail)};
                    let score=if in_view {proximity}else{dot(ahead,tile.axis)};
                    near.push((tile.key,score,priority));
                } else if (in_view || (near_view && tile.key.0>=5)) && self.pages.contains_key(&tile.key)
                    && grouped_lod(tile.key.0).is_some_and(|index|needed[index]) {
                    // The shared edge fade also samples resident neighbours.
                    near.push((tile.key,proximity,if in_view {4} else {3}));
                }
            }
        }
        // Keep the normal prefetch ring intact. Reserve the wider view in spare slots.
        near.sort_unstable_by(|(a,x,priority),(b,y,other_priority)|
            other_priority.cmp(priority).then_with(||a.0.cmp(&b.0)).then_with(||y.total_cmp(x)));
        self.view_max=target;
        self.required_pages=near.len();
        if let Some(&(Key(overflow,_,_),_,5))=near.get(capacity) {
            // Keep a complete visible level when the viewport itself exceeds the budget.
            self.view_max=overflow.saturating_sub(1);
            near.retain(|&(key,_,_)|key.0<=self.view_max);
        }
        self.selected.extend(near.iter().take(capacity).map(|&(key,_,_)|key));
        self.regional_wanted.clear();
        if let Some(index)=self.regional_index.as_ref().filter(|_|camera.mpp<=REGIONAL_PREFETCH_MPP || exact) {
            self.regional_wanted.extend(self.selected.iter().copied()
                .filter(|key|index.contains_key(key) && !self.regional_failed.contains(key))
                .take(REGIONAL_SLOTS as usize));
        }
        for key in &self.selected {
            if let Some(page)=self.pages.get_mut(key){page.used=now;}
        }
    }

    fn write_index(table:&wgpu::Texture,queue:&wgpu::Queue,key:Key,value:u64) {
        queue.write_texture(wgpu::TexelCopyTextureInfo{texture:table,mip_level:0,
            origin:key.texel(),aspect:wgpu::TextureAspect::All},&value.to_le_bytes(),
            wgpu::TexelCopyBufferLayout{offset:0,bytes_per_row:None,rows_per_image:None},
            wgpu::Extent3d{width:1,height:1,depth_or_array_layers:1});
    }

    pub fn complete(&mut self,queue:&wgpu::Queue,completion:Completion) -> io::Result<()> {
        self.inflight=None;
        if !self.selected.contains(&completion.key){return Ok(());}
        let tile=completion.result?;
        let slot=if let Some(slot)=self.slots.pop(){slot}else {
            let Some((&key,_))=self.pages.iter().filter(|(key,_)|!self.selected.contains(key))
                .min_by_key(|(_,page)|page.used) else {return Ok(());};
            let page=self.pages.remove(&key).unwrap();
            if let Some(slot)=page.regional_slot {self.regional_slots.push(slot);}
            if page.landscape_fade.is_some() {self.landscape_revision=self.landscape_revision.wrapping_add(1);}
            Self::write_index(&self.table,queue,key,0);
            page.slot
        };
        write_texture_layer(queue,&self.atlas,0,slot,PAGE_SIZE,&tile.pixels);
        let landscape_fade=tile.landscape.zip(self.landscape.as_ref()).map(|(pixels,texture)|{
            self.landscape_revision=self.landscape_revision.wrapping_add(1);
            queue.write_texture(
                wgpu::TexelCopyTextureInfo{texture,mip_level:0,
                    origin:wgpu::Origin3d{x:0,y:0,z:slot},aspect:wgpu::TextureAspect::All},
                &pixels,wgpu::TexelCopyBufferLayout{offset:0,bytes_per_row:Some(4*PAGE_SIZE),rows_per_image:None},
                wgpu::Extent3d{width:PAGE_SIZE,height:PAGE_SIZE,depth_or_array_layers:1},
            );
            1 // Available to instance builds while the surface fade is still zero.
        });
        let now=Instant::now();
        let fade=if self.exact() {255} else {0};
        let ready=(landscape_fade.is_none() || self.exact()).then_some(now);
        let page=Page{slot,regional_slot:None,regional_near_only:false,ready,used:now,fade,landscape_fade,classified:tile.classified};
        Self::write_index(&self.table,queue,completion.key,page.index());
        self.pages.insert(completion.key,page);
        if !self.exact() && self.view_max>=GROUPED_LOD_START && self.requests_this_frame<GROUPED_LOADS_PER_FRAME {
            self.request_page(now);
        }
        Ok(())
    }

    pub fn complete_regional(&mut self,queue:&wgpu::Queue,key:Key,result:io::Result<Vec<u8>>) -> io::Result<()> {
        self.inflight=None;
        match result {
            Ok(pixels) if self.regional_wanted.contains(&key)=>self.upload_regional(queue,key,&pixels),
            Ok(_)=>{},
            Err(error)=>{
                self.regional_failed.insert(key);
                self.regional_wanted.remove(&key);
                self.view=None;
                return Err(error);
            }
        }
        if !self.exact(){self.request_page(Instant::now());}
        Ok(())
    }

    fn upload_regional(&mut self,queue:&wgpu::Queue,key:Key,pixels:&[u8]) {
        let Some(texture)=&self.regional else {return;};
        if !self.pages.contains_key(&key){return;}
        let slot=if let Some(slot)=self.regional_slots.pop(){slot}else{
            // A regional page can retire while its terrain page remains resident.
            let Some((&old,_))=self.pages.iter().filter(|(key,page)|
                page.regional_slot.is_some() && !self.regional_wanted.contains(key))
                .min_by_key(|(key,page)|(page.used,key.0,key.1,key.2)) else {return;};
            let page=self.pages.get_mut(&old).unwrap();
            let slot=page.regional_slot.take().unwrap();
            Self::write_index(&self.table,queue,old,page.index());
            slot
        };
        let width=PAGE_SIZE*REGIONAL_BANKS;
        queue.write_texture(wgpu::TexelCopyTextureInfo{texture,mip_level:0,
            origin:wgpu::Origin3d{x:0,y:0,z:slot},aspect:wgpu::TextureAspect::All},
            pixels,wgpu::TexelCopyBufferLayout{offset:0,bytes_per_row:Some(4*width),rows_per_image:None},
            wgpu::Extent3d{width,height:PAGE_SIZE,depth_or_array_layers:1});
        let page=self.pages.get_mut(&key).unwrap();
        page.regional_slot=Some(slot);
        page.regional_near_only=self.regional_index.as_ref().and_then(|index|index.get(&key))
            .is_some_and(|frame|frame.near_only);
        Self::write_index(&self.table,queue,key,page.index());
        self.landscape_revision=self.landscape_revision.wrapping_add(1);
    }

    pub fn fading(&self)->bool {
        self.transitions.iter().any(|transition|transition.mix!=transition.goal)
            || self.pages.values().any(|page|page.fade<255 || page.landscape_fade.is_some_and(|fade|fade<255))
    }
}

fn cell(uv:[f32;2],z:u32)->(Key,[f32;2]) {
    let [x,y]=[uv[0]*(2u32<<z) as f32,uv[1]*(1u32<<z) as f32];
    (Key(z,x as u32,y as u32),[x.fract(),y.fract()])
}

fn projected_lod(camera:&Camera,center:[f64;3],size:[u32;2])->f64 {
    let ll=geographic(center);
    let [east,north,_]=frame(ll);
    let pixel=camera.project_vec(center,size).unwrap_or(size.map(|n|f64::from(n)*0.5));
    let span=1e-5_f64;
    let (sin,cos)=span.sin_cos();
    let projected=|axis:[f64;3]| {
        let point=std::array::from_fn(|i|center[i]*cos+axis[i]*sin);
        camera.project_vec(point,size).map_or(0.,|p|(p[0]-pixel[0]).hypot(p[1]-pixel[1])/span)
    };
    // Longitude spacing shrinks at high latitudes. Use the RMS projection of
    // the two sample axes so north–south detail still counts at the poles.
    let angular_step=std::f64::consts::TAU/f64::from(2*TILE_SIZE);
    let east=projected(east)*ll[1].to_radians().cos();
    let north=projected(north);
    (east.hypot(north)*angular_step/std::f64::consts::SQRT_2).max(f64::MIN_POSITIVE).log2()
}
