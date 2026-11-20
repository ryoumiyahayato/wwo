use crate::{camera::{dot,frame,geographic,Camera},landscape_cover::CoverPack,render::write_texture_layer,terrain_detail};
use flate2::read::ZlibDecoder;
use serde::Deserialize;
use std::{collections::{HashMap,HashSet},fs,io::{self,Read,Seek,SeekFrom},path::{Path,PathBuf},sync::{mpsc,Arc},time::{Duration,Instant}};
use winit::event_loop::EventLoopProxy;

pub const VERSION: &str = "worldcrs84quad-z4-v3";
pub const PACK_VERSION: &str = "worldcrs84quad-15s-v1";
pub const COMPACT_VERSION: &str = "worldcrs84quad-15s-v2";
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
const PAGE_FADE_SECONDS: f32 = 0.22;
const GROUPED_LOD_START: u32 = 1;
const GROUPED_LOD_COUNT: usize = (MAX_LEVEL-GROUPED_LOD_START+1) as usize;
const GROUPED_LOADS_PER_FRAME: u32 = 3;
const COARSE_CACHE_LEVEL: u32 = 3;

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

    fn texel(self) -> wgpu::Origin3d {
        wgpu::Origin3d {
            x:self.1,
            y:self.2+(1<<self.0)-1,
            z:0,
        }
    }
}

pub struct Catalogue {pages:Vec<Key>, source:Source, max_level:u32, version:&'static str,
    selection:LayerSelection, layer_candidate:Option<PathBuf>, cover_root:Option<PathBuf>, river_lines:Option<PathBuf>}

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
            let use_water=layer_candidate.is_none();
            let water=if use_water && water_path.is_file() {
                if version!=COMPACT_VERSION || !river_path.is_file() {
                    return Err(io::Error::other("水文修订需要匹配的 QPK 和河流中心线"));
                }
                Some(WaterColors::open(&water_path,lengths)?)
            } else {None};
            let river_lines=(use_water&&!selection.exact()&&selection.limit()>=6&&river_path.is_file()).then_some(river_path);
            let source=if packed {Source::Packs(packs,water)} else {Source::Files(root.to_owned())};
            let cover_root=(version==COMPACT_VERSION && selection.limit()>=6
                && CoverPack::FILE_NAMES.iter().any(|name|root.join(name).is_file())).then(||root.to_owned());
            Ok(Self{pages,source,max_level:levels as u32-1,version,selection,layer_candidate,cover_root,river_lines})
        };
        open().map_err(|error|io::Error::other(format!("无法读取自然地貌底图库。{} · {error}",path.display())))
    }

    pub fn river_lines(&self)->Option<&Path> {self.river_lines.as_deref()}
}

enum Source {Files(PathBuf),Packs(Vec<Option<LevelPack>>,Option<WaterColors>)}

impl Source {
    fn read(&mut self,key:Key,cover:Option<&mut CoverPack>,landscape:bool)->io::Result<DecodedTile> {
        match self {
            Self::Files(root)=>{
                let mut file=open_tile(&key.path(root),key,COLOR_MAGIC,1)?;
                let mut bytes=vec![0;(PAGE_SIZE*PAGE_SIZE) as usize];
                file.read_exact(&mut bytes)?;
                Ok(DecodedTile{pixels:bytes,landscape:None,decode_time:Duration::ZERO})
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

    fn read(&mut self,key:Key,cover:Option<&mut CoverPack>,landscape:bool,override_frame:Option<Vec<u8>>)->io::Result<DecodedTile> {
        let Key(z,x,y)=key;
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
        let landscape=match &mut self.decoder {
            ColorDecoder::Zstandard(decoder) if z>=6&&landscape=>{
                let count=self.offsets[i+1]-offset-RECORD_HEADER as u64-u64::from(count);
                frame.resize(count as usize,0);
                self.file.read_exact(&mut frame)?;
                let residual=decoder.decompress(&frame,size*2)?;
                let classes=cover.and_then(|cover|match cover.read(z,x,y,size) {
                    Ok(classes)=>Some(classes),
                    Err(error)=>{
                        eprintln!("Landscape cover unavailable at {z}/{x}/{y}: {error}");
                        None
                    }
                });
                Some(landscape_pixels(&residual,classes.as_deref())?)
            }
            _=>None,
        };
        Ok(DecodedTile{pixels,landscape,decode_time:started.elapsed()})
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

fn landscape_pixels(residual:&[u8],classes:Option<&[u8]>)->io::Result<Vec<u8>> {
    let width=PAGE_SIZE as usize;
    let size=width*width;
    if residual.len()!=size*2 {
        return Err(io::Error::other("近景地貌高程数据大小无效"));
    }
    let mut pixels=Vec::with_capacity(size*4);
    let mut above=[0u16;PAGE_SIZE as usize];
    for y in 0..width {
        let mut height=0u16;
        for (x,column) in above.iter_mut().enumerate() {
            let i=y*width+x;
            let zigzag=u16::from_le_bytes([residual[i],residual[i+size]]);
            let delta=(zigzag>>1)^0u16.wrapping_sub(zigzag&1);
            *column=column.wrapping_add(delta);
            height=height.wrapping_add(*column);
            let [low,high]=(height^0x8000).to_le_bytes();
            let class=classes.map_or(0,|cells|cells[i]);
            pixels.extend([low,high,if matches!(class,1|10) {255}else{0},class*17]);
        }
    }
    Ok(pixels)
}

pub struct DecodedTile {pixels:Vec<u8>,landscape:Option<Vec<u8>>,pub decode_time:Duration}
pub struct Completion {pub key:Key,pub requested:Instant,pub result:io::Result<DecodedTile>}

enum DecodeRequest {
    Page(Key, Instant),
    Detail(usize, Arc<terrain_detail::Catalogue>),
}

struct Page {
    slot:u32,
    ready:Option<Instant>,
    used:Instant,
    fade:u8,
    landscape_fade:Option<u8>,
}

impl Page {
    fn index(&self)->u32 {
        (u32::from(self.landscape_fade.unwrap_or(0))<<24)
            | (u32::from(self.fade)<<16) | (self.slot+1)
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
        // Zoom determines layer opacity. Page readiness is applied at the sampled
        // location, so a missing neighbour cannot retire the whole layer.
        let exit=f64::from(level)-0.5-LOD_HYSTERESIS;
        let exit_span=if level<=4 {0.05} else {0.37};
        let t=((lod-exit)/exit_span).clamp(0.,1.) as f32;
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
    height_enabled:bool,
    landscape_cover:bool,
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
               proxy:EventLoopProxy<crate::HostEvent>,landscape_supported:bool) -> io::Result<Self> {
        let Catalogue{pages,mut source,max_level,version,selection,layer_candidate,mut cover_root,..}=data;
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
        let height_enabled=landscape_supported&&version==COMPACT_VERSION&&selection.limit()>=6;
        let landscape_cover=height_enabled&&cover_root.is_some();
        let [width,height]=[2<<max_level,(2<<max_level)-1];
        let table=texture("Natural terrain page indices",width,height,1,1,wgpu::TextureFormat::R32Uint);
        let keys=pages.into_iter().map(|key|{
            let [w,s,e,n]=key.bounds();
            let axis=frame([(w+e)*0.5,(s+n)*0.5])[2];
            let radius=[(w,s),(w,n),(e,s),(e,n)].into_iter().map(|(x,y)|
                dot(axis,frame([x,y])[2]).clamp(-1.,1.).acos()).fold(0.,f64::max);
            Visible {key,axis,radius}
        }).collect();
        let (sender,receiver)=mpsc::channel();
        std::thread::Builder::new().name("WWO natural terrain".into()).spawn(move||{
            let mut cover=None;
            while let Ok(request)=receiver.recv() {
                let event=match request {
                    DecodeRequest::Page(key,requested)=>{
                        if height_enabled && key.0>=6 {
                            if let Some(root)=cover_root.take() {
                                cover=CoverPack::FILE_NAMES.into_iter().find_map(|name| {
                                    match CoverPack::open(&root.join(name),PAGE_SIZE) {
                                        Ok(cover)=>Some(cover),
                                        Err(error) if error.kind()==io::ErrorKind::NotFound=>None,
                                        Err(error)=>{eprintln!("Landscape cover unavailable: {error}");None}
                                    }
                                });
                            }
                        }
                        crate::HostEvent::Terrain(Completion{key,requested,
                            result:source.read(key,cover.as_mut(),height_enabled)})
                    }
                    DecodeRequest::Detail(index,catalogue)=>crate::HostEvent::TerrainDetail(index,catalogue.read(index)),
                };
                if proxy.send_event(event).is_err(){break;}
            }
        })?;
        Ok(Self{base,atlas,table,landscape:None,height_enabled,landscape_cover,water_colors,landscape_revision:0,keys,sender,inflight:None,requests_this_frame:0,pages:HashMap::new(),
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

    pub fn enable_landscape(&mut self, device:&wgpu::Device)->Option<wgpu::TextureView> {
        if !self.height_enabled || self.landscape.is_some() {return None;}
        let texture=device.create_texture(&wgpu::TextureDescriptor{
            label:Some("Z6/Z7 elevation and landscape cover"),
            size:wgpu::Extent3d{width:PAGE_SIZE,height:PAGE_SIZE,depth_or_array_layers:self.atlas.depth_or_array_layers()},
            mip_level_count:1,sample_count:1,dimension:wgpu::TextureDimension::D2,
            format:wgpu::TextureFormat::Rgba8Unorm,usage:wgpu::TextureUsages::TEXTURE_BINDING|wgpu::TextureUsages::COPY_DST,
            view_formats:&[],
        });
        let view=texture.create_view(&wgpu::TextureViewDescriptor{
            dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()});
        self.landscape=Some(texture);
        Some(view)
    }

    pub fn landscape_cover(&self)->bool {self.landscape_cover}

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
            "landscape_cover": self.landscape_cover,
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
        let collar=0.04;
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
        if self.inflight.is_none() {
            if let Some(&key)=self.selected.iter().find(|key|!self.pages.contains_key(key)) {
                if self.sender.send(DecodeRequest::Page(key,now)).is_ok(){
                    self.inflight=Some(key);
                    self.requests_this_frame+=1;
                }
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
            if near_view || reserved || retreat_detail {
                let in_view=proximity>=(viewport+tile.radius).min(std::f64::consts::PI).cos();
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
                } else if in_view && self.pages.contains_key(&tile.key)
                    && grouped_lod(tile.key.0).is_some_and(|index|needed[index]) {
                    // Keep already visible pages through the outgoing zoom fade.
                    near.push((tile.key,proximity,4));
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
        for key in &self.selected {
            if let Some(page)=self.pages.get_mut(key){page.used=now;}
        }
    }

    fn write_index(table:&wgpu::Texture,queue:&wgpu::Queue,key:Key,value:u32) {
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
        let page=Page{slot,ready,used:now,fade,landscape_fade};
        Self::write_index(&self.table,queue,completion.key,page.index());
        self.pages.insert(completion.key,page);
        if !self.exact() && self.view_max>=GROUPED_LOD_START && self.requests_this_frame<GROUPED_LOADS_PER_FRAME {
            self.request_page(now);
        }
        Ok(())
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
