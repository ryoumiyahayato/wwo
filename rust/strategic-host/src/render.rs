use crate::{camera::{Camera,EARTH},compact::{Raster,Vertex},overlay::Mesh,politics::FlagUniform,terrain::{self,Terrain},ui::Ink,world::{Pixels,Tile}};
use crate::landmarks::{self, ModelKey, ModelMesh, ModelVertex, VisibleModel};
use crate::terrain_detail;
use crate::landscape::{Landscape,LandscapeCounts};
use crate::hydrology::Rivers;
use bytemuck::{Pod,Zeroable};
use std::collections::{HashMap, HashSet};
use std::{fs::File,io,path::{Path,PathBuf},sync::Arc,time::{Duration,Instant}};
use wgpu::util::DeviceExt;
use winit::window::Window;

#[repr(C)]
#[derive(Clone,Copy,Pod,Zeroable)]
pub struct Edit {pub area:[f32;4],pub state:[f32;4]}
#[repr(C)]
#[derive(Clone,Copy,Pod,Zeroable)]
pub struct View {
    axes:[[f32;4];3],
    viewport:[f32;4],
    // East axis uses its fourth lane for surface animation time.
    projection_axes:[[f32;4];3],
    projection_origin:[f32;4],
    pub settings:[f32;4],
    pub selection:[f32;4],
    pub map_style:[f32;4],
    pub edits:[Edit;crate::timeline::MAX_SITES],
    pub natural_lod:[[f32;4];2],
    pub close_sample:[f32;3],
    water_clock:u32,
    pub military_cell:[f32;4],
}
impl View {
    pub fn new(camera:&Camera,size:[u32;2])->Self {
        let mut result=Self::zeroed();
        result.axes=camera.axes.map(|[x,y,z]|[x as f32,y as f32,z as f32,0.]);
        result.viewport=[size[0] as f32,size[1] as f32,(camera.mpp/EARTH) as f32,camera.blend() as f32];
        let (axes,[x,y])=camera.projection(size);
        result.projection_axes=axes.map(|[x,y,z]|[x as f32,y as f32,z as f32,0.]);
        result.projection_origin=[x as f32,y as f32,camera.pitch().cos() as f32,0.];
        result
    }

    pub fn set_terrain_exact(&mut self,exact:bool) {
        self.projection_origin[3]=if exact {1.} else {0.};
    }

}
#[repr(C)]
#[derive(Clone,Copy,Pod,Zeroable)]
struct TileState {extent:[f32;4],core:[f32;4],region:[f32;4],options:[f32;4],edges:[f32;4],edge_ready:[f32;4]}
impl TileState {
    fn new(tile:&Tile,opacity:f32,edges:[f32;4],edge_ready:[f32;4])->Self {
        let cast=|values:[f64;4]| values.map(|a|a as f32);
        Self {extent:cast(tile.bounds),core:cast(tile.core),region:cast(tile.group),
              options:[opacity,f32::from(tile.printed+u8::from(tile.cover)),u8::from(tile.city) as f32,u8::from(tile.level==0) as f32],edges,edge_ready}
    }
}
pub struct Page {
    group:wgpu::BindGroup,
    uniform:wgpu::Buffer,
    ids:Vec<u8>,
    water:Vec<u8>,
    pub bytes:usize,
}
impl Page {
    pub fn ids_at(&self,tile:&Tile, [lon,lat]:[f64;2])->[u8;2] {
        if self.ids.is_empty() {return [0,0];}
        let at=tile.offset_of([lon,lat])*2;
        if self.water[at/2]>=192 {[0,0]} else {[self.ids[at],self.ids[at+1]]}
    }
}

struct MeshBuffers {
    vertex:wgpu::Buffer,
    index:wgpu::Buffer,
    vertex_bytes:u64,
    index_bytes:u64,
    count:u32,
}
impl MeshBuffers {
    fn new(device:&wgpu::Device,vertex_bytes:u64,index_bytes:u64)->Self {
        let buffer=|size,usage|device.create_buffer(&wgpu::BufferDescriptor {
            label:Some("WWO interface geometry"),size,usage:usage|wgpu::BufferUsages::COPY_DST,mapped_at_creation:false
        });
        Self {vertex:buffer(vertex_bytes,wgpu::BufferUsages::VERTEX),index:buffer(index_bytes,wgpu::BufferUsages::INDEX),
              vertex_bytes,index_bytes,count:0}
    }
    fn upload(&mut self,device:&wgpu::Device,queue:&wgpu::Queue,mesh:&Mesh) {
        let vertices=bytemuck::cast_slice(&mesh.vertices);
        let indices=bytemuck::cast_slice(&mesh.indices);
        let v=vertices.len() as u64;
        let i=indices.len() as u64;
        if v>self.vertex_bytes || i>self.index_bytes {
            *self=Self::new(device,v.next_power_of_two().max(self.vertex_bytes),i.next_power_of_two().max(self.index_bytes));
        }
        self.count=mesh.indices.len() as u32;
        if self.count>0 {
            queue.write_buffer(&self.vertex,0,vertices);
            queue.write_buffer(&self.index,0,indices);
        }
    }
    fn draw(&self,pass:&mut wgpu::RenderPass<'_>) {
        if self.count==0{return;}
        pass.set_vertex_buffer(0,self.vertex.slice(..));
        pass.set_index_buffer(self.index.slice(..),wgpu::IndexFormat::Uint32);
        pass.draw_indexed(0..self.count,0,0..1);
    }
}

enum RenderTarget {
    Window(wgpu::Surface<'static>,wgpu::SurfaceConfiguration),
    Offscreen(wgpu::Texture),
}

struct RiverLayer {
    rivers: Option<Rivers>,
    pipeline: wgpu::RenderPipeline,
    mesh: MeshBuffers,
}

pub struct TransportOverlay<'a> {
    pub network: Option<(u64, &'a Mesh)>,
    pub vehicles: &'a Mesh,
}

pub struct Renderer {
    target:RenderTarget,
    device:wgpu::Device,
    queue:wgpu::Queue,
    pub gpu:String,
    models: ModelLayer,
    transport_network: Option<(u64, MeshBuffers)>,
    transport_vehicles: Option<MeshBuffers>,
    battle: Option<crate::battle_render::Scene>,
    landscape: Option<Landscape>,
    landscape_pipeline: Option<(wgpu::TextureFormat,wgpu::BindGroupLayout,wgpu::ShaderModule)>,
    surface: GroundSurface,
    view:wgpu::Buffer,
    globals:wgpu::BindGroup,
    pages:wgpu::BindGroupLayout,
    palette:wgpu::Texture,
    flag_poses:wgpu::Texture,
    fallback:[wgpu::TextureView;3],
    globe:wgpu::RenderPipeline,
    terrain:Option<Terrain>,
    rivers:Option<RiverLayer>,
    water_pages:Option<crate::hydrology::WaterPages>,
    close_extent:Option<[f64;4]>,
    close_layout:wgpu::BindGroupLayout,
    close_group:wgpu::BindGroup,
    detail:Option<terrain_detail::Stream>,
    solid:wgpu::RenderPipeline,
    text:wgpu::RenderPipeline,
    flag:wgpu::RenderPipeline,
    loading:wgpu::RenderPipeline,
    history_light:wgpu::RenderPipeline,
    clock_gears:wgpu::RenderPipeline,
    clock_face:wgpu::RenderPipeline,
    font:wgpu::BindGroup,
    flag_art:wgpu::BindGroup,
    hud_art:wgpu::BindGroup,
    hud_type:wgpu::BindGroup,
    menu_art:wgpu::BindGroup,
    instrument:wgpu::RenderPipeline,
    instrument_view:wgpu::BindGroup,
    screen:wgpu::BindGroup,
    screen_size:wgpu::Buffer,
    meshes:[MeshBuffers;26],
}

pub struct BattleFrame<'a> {
    pub view: &'a crate::battle_view::Camera,
    pub state: &'a wwo_map_lab::land_battle::LandBattle,
    pub terrain: &'a wwo_map_lab::battlefield_terrain::BattlefieldTerrain,
}

struct GroundSurface {
    layout:wgpu::BindGroupLayout,
    group:wgpu::BindGroup,
    repeat:wgpu::Sampler,
    height:Option<wgpu::TextureView>,
    art:wgpu::TextureView,
    water:wgpu::Buffer,
    water_pixels:wgpu::Buffer,
    water_raster:Option<WaterRaster>,
    loaded:bool,
}

struct WaterRaster {
    pipeline:wgpu::ComputePipeline,
    view:wgpu::BindGroup,
    gaps:[wgpu::BindGroup;2],
    buffers:Option<wgpu::BindGroup>,
    size:[u32;2],
    previous:Option<([[f32;4];3],[f32;4],[f32;4],u64)>,
}

fn water_storage(binding:u32, visibility:wgpu::ShaderStages, read_only:bool)->wgpu::BindGroupLayoutEntry {
    entry(binding,visibility,wgpu::BindingType::Buffer {
        ty:wgpu::BufferBindingType::Storage {read_only},has_dynamic_offset:false,min_binding_size:None,
    })
}

fn water_pixels(device:&wgpu::Device, bytes:u64)->wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label:Some("Water surface viewport classification"),size:bytes,
        usage:wgpu::BufferUsages::STORAGE,mapped_at_creation:false,
    })
}

impl GroundSurface {
    fn new(device:&wgpu::Device, supported:bool, water_available:bool)->Self {
        let mut entries=vec![sampled(0),sampler_entry(1)];
        let height=supported.then(||{
            entries.push(wgpu::BindGroupLayoutEntry{
                visibility:wgpu::ShaderStages::FRAGMENT|wgpu::ShaderStages::COMPUTE,
                ..texture_entry(2,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array)
            });
            create_texture(device,[1,1,1],wgpu::TextureFormat::Rgba8Unorm)
                .create_view(&wgpu::TextureViewDescriptor{dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()})
        });
        entries.push(water_storage(3,wgpu::ShaderStages::FRAGMENT,true));
        entries.push(water_storage(4,wgpu::ShaderStages::FRAGMENT,true));
        let layout=layout(device,&entries);
        let repeat=device.create_sampler(&wgpu::SamplerDescriptor{
            address_mode_u:wgpu::AddressMode::Repeat,address_mode_v:wgpu::AddressMode::Repeat,
            mag_filter:wgpu::FilterMode::Linear,min_filter:wgpu::FilterMode::Linear,
            mipmap_filter:wgpu::FilterMode::Linear,..Default::default()
        });
        let art=create_texture(device,[1,1,1],wgpu::TextureFormat::Rgba8Unorm).create_view(&Default::default());
        let water=crate::hydrology::water_buffer(device,water_available);
        let water_pixels=water_pixels(device,4);
        let group=Self::bind(device,&layout,&repeat,&art,height.as_ref(),&water,&water_pixels);
        Self{layout,group,repeat,height,art,water,water_pixels,water_raster:None,loaded:false}
    }

    fn bind(device:&wgpu::Device, layout:&wgpu::BindGroupLayout, repeat:&wgpu::Sampler,
            art:&wgpu::TextureView, height:Option<&wgpu::TextureView>,
            water:&wgpu::Buffer, pixels:&wgpu::Buffer)->wgpu::BindGroup {
        let mut entries=vec![tex_resource(0,art),sampler_resource(1,repeat),
            buf_resource(3,water),buf_resource(4,pixels)];
        if let Some(height)=height {entries.push(tex_resource(2,height));}
        bind(device,layout,&entries)
    }

    fn load(&mut self, device:&wgpu::Device, queue:&wgpu::Queue, height:Option<wgpu::TextureView>)->io::Result<()> {
        if self.loaded {return Ok(());}
        let art=crate::decode_rgba(&include_bytes!("land-material.png")[..])?;
        let [width,height_px]=art.size;
        let levels=width.ilog2()+1;
        let texture=create_texture_mips(device,[width,height_px,1],wgpu::TextureFormat::Rgba8Unorm,levels);
        let mut pixels=art.pixels;
        for level in 0..levels {
            let [w,h]=[width>>level,height_px>>level];
            write_texture_mip(queue,&texture,[w,h,1],4,&pixels,level);
            if w==1 {break;}
            pixels=downsample_rgba(&pixels,w,h);
        }
        if height.is_some() {self.height=height;}
        self.art=texture.create_view(&Default::default());
        self.group=Self::bind(device,&self.layout,&self.repeat,&self.art,self.height.as_ref(),
            &self.water,&self.water_pixels);
        self.loaded=true;
        Ok(())
    }

    fn init_water_raster(&mut self,device:&wgpu::Device,shader:&wgpu::ShaderModule,view:&wgpu::Buffer) {
        let pipeline=device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor{
            label:Some("Project visible water boundaries"),layout:None,module:shader,
            entry_point:Some("raster_water"),compilation_options:Default::default(),cache:None,
        });
        let view=bind(device,&pipeline.get_bind_group_layout(0),&[buf_resource(0,view)]);
        let gaps=[1,2].map(|i|bind(device,&pipeline.get_bind_group_layout(i),&[]));
        self.water_raster=Some(WaterRaster{pipeline,view,gaps,buffers:None,size:[0,0],previous:None});
    }

    fn project_water(&mut self,device:&wgpu::Device,encoder:&mut wgpu::CommandEncoder,
                     size:[u32;2],view:&View,revision:u64) {
        if view.viewport[2]*EARTH as f32>=crate::hydrology::WATER_MPP as f32
            || view.projection_origin[3]>0.5 {return;}
        let Some(raster)=&mut self.water_raster else {return;};
        if raster.size!=size {
            raster.size=size;
            let bytes=u64::from(size[0])*u64::from(size[1])*4;
            let fits=bytes<=u64::from(device.limits().max_storage_buffer_binding_size);
            self.water_pixels=water_pixels(device,if fits {bytes} else {4});
            raster.buffers=fits.then(||bind(device,&raster.pipeline.get_bind_group_layout(3),
                &[buf_resource(3,&self.water),buf_resource(5,&self.water_pixels)]));
            self.group=Self::bind(device,&self.layout,&self.repeat,&self.art,self.height.as_ref(),
                &self.water,&self.water_pixels);
            raster.previous=None;
        }
        let Some(buffers)=&raster.buffers else {return;};
        let key=(view.projection_axes,view.projection_origin,view.viewport,revision);
        if raster.previous==Some(key) {return;}
        raster.previous=Some(key);
        let mut pass=encoder.begin_compute_pass(&wgpu::ComputePassDescriptor{
            label:Some("Project visible water boundaries"),timestamp_writes:None,
        });
        pass.set_pipeline(&raster.pipeline);
        pass.set_bind_group(0,&raster.view,&[]);
        pass.set_bind_group(1,&raster.gaps[0],&[]);
        pass.set_bind_group(2,&raster.gaps[1],&[]);
        pass.set_bind_group(3,buffers,&[]);
        pass.dispatch_workgroups(size[0].div_ceil(8),size[1].div_ceil(8),1);
    }
}

#[repr(C)]
#[derive(Clone,Copy,Pod,Zeroable)]
struct ModelInstance {
    clip_from_model:[[f32;4];4],
    style:[f32;3],
}

struct ResidentModel {
    vertices: wgpu::Buffer,
    indices: wgpu::Buffer,
    count: u32,
    instance_buffer: wgpu::Buffer,
    transforms: Vec<ModelInstance>,
    last_drawn: Instant,
}

struct ModelLayer {
    pipeline: wgpu::RenderPipeline,
    depth: Option<([u32; 2], wgpu::TextureView)>,
    residents: HashMap<ModelKey, ResidentModel>,
    visible: HashSet<ModelKey>,
    pending: HashSet<ModelKey>,
    failed: HashSet<ModelKey>,
    events: winit::event_loop::EventLoopProxy<crate::HostEvent>,
}

impl ModelLayer {
    const DEPTH: wgpu::TextureFormat = wgpu::TextureFormat::Depth32Float;
    const CITY_LOD_CACHE_TIME: Duration = Duration::from_secs(2);

    fn new(device: &wgpu::Device, format: wgpu::TextureFormat, events: winit::event_loop::EventLoopProxy<crate::HostEvent>) -> Self {
        let stages = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("WWO static model"), bind_group_layouts: &[], push_constant_ranges: &[],
        });
        let shader = device.create_shader_module(wgpu::include_wgsl!("landmark.wgsl"));
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("WWO static models"), layout: Some(&stages), primitive: Default::default(),
            depth_stencil: Some(wgpu::DepthStencilState {
                format: Self::DEPTH, depth_write_enabled: true, depth_compare: wgpu::CompareFunction::Less,
                stencil: Default::default(), bias: Default::default(),
            }),
            multisample: Default::default(), multiview: None, cache: None,
            vertex: wgpu::VertexState {
                module: &shader, entry_point: Some("model_vertex"), compilation_options: Default::default(),
                buffers: &[wgpu::VertexBufferLayout {
                    array_stride: std::mem::size_of::<ModelVertex>() as u64,
                    step_mode: wgpu::VertexStepMode::Vertex,
                    attributes: &wgpu::vertex_attr_array![0 => Float32x3, 1 => Float32x3, 2 => Float32x4],
                }, wgpu::VertexBufferLayout {
                    array_stride: std::mem::size_of::<ModelInstance>() as u64,
                    step_mode: wgpu::VertexStepMode::Instance,
                    attributes: &wgpu::vertex_attr_array![3=>Float32x4, 4=>Float32x4, 5=>Float32x4, 6=>Float32x4, 7=>Float32x3],
                }],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader, entry_point: Some("model_fragment"), compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState { format, blend: None, write_mask: wgpu::ColorWrites::ALL })],
            }),
        });
        Self { pipeline, depth: None, residents: HashMap::new(), visible: HashSet::new(),
            pending: HashSet::new(), failed: HashSet::new(), events }
    }

    fn prepare(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, size: [u32; 2], models: &[VisibleModel]) {
        let now = Instant::now();
        self.visible.clear();
        self.visible.extend(models.iter().filter(|model| model.lod_range[0] < model.lod_range[1]).map(|model| model.key));
        self.residents.retain(|key, model| {
            self.visible.contains(key) || (key.is_city() && now.duration_since(model.last_drawn) < Self::CITY_LOD_CACHE_TIME)
        });
        for resident in self.residents.values_mut() { resident.transforms.clear(); }
        if models.is_empty() {
            self.depth = None;
            return;
        }
        if self.depth.as_ref().is_none_or(|(previous, _)| *previous != size) {
            let [width, height] = size;
            let texture = device.create_texture(&wgpu::TextureDescriptor {
                label: Some("WWO static model depth"), size: extent([width, height, 1]), mip_level_count: 1,
                sample_count: 1, dimension: wgpu::TextureDimension::D2, format: Self::DEPTH,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT, view_formats: &[],
            });
            self.depth = Some((size, texture.create_view(&Default::default())));
        }
        for model in models {
            let key = model.key;
            let lod_range=self.lod_range(model);
            if let Some(resident) = self.residents.get_mut(&key) {
                if lod_range[0]<lod_range[1] {
                    let [low,high]=lod_range;
                    let waterline=f32::from(u8::from(key.clips_at_waterline()));
                    resident.transforms.push(ModelInstance{clip_from_model:model.clip_from_model,style:[low,high,waterline]});
                    resident.last_drawn = now;
                }
            } else if self.visible.contains(&key) && !self.failed.contains(&key) && self.pending.insert(key) {
                let events = self.events.clone();
                let created = std::thread::Builder::new().name("WWO model loading".into()).spawn(move || {
                    let _ = events.send_event(crate::HostEvent::Model(key, landmarks::decode(key)));
                });
                if let Err(error) = created {
                    self.pending.remove(&key);
                    self.failed.insert(key);
                    let _ = self.events.send_event(crate::HostEvent::Model(key, Err(error)));
                }
            }
        }
        for resident in self.residents.values_mut().filter(|model|!model.transforms.is_empty()) {
            let transforms = bytemuck::cast_slice(&resident.transforms);
            if transforms.len() as u64 > resident.instance_buffer.size() {
                resident.instance_buffer = Self::instance_buffer(device, transforms.len().next_power_of_two() as u64);
            }
            queue.write_buffer(&resident.instance_buffer, 0, transforms);
        }
    }

    fn lod_range(&self,model:&VisibleModel)->[f32;2] {
        if let Some((key,opacity))=model.alternate {
            if !self.residents.contains_key(&key) {return [0.,opacity];}
        }
        model.lod_range
    }

    fn instance_buffer(device: &wgpu::Device, size: u64) -> wgpu::Buffer {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("WWO static model instances"), size,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false,
        })
    }

    fn complete(&mut self, device: &wgpu::Device, key: ModelKey, model: io::Result<ModelMesh>) -> io::Result<()> {
        self.pending.remove(&key);
        let model = model.inspect_err(|_| { self.failed.insert(key); })?;
        if !self.visible.contains(&key) { return Ok(()); }
        let upload = |contents, usage| device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("WWO static model"), contents, usage,
        });
        self.residents.insert(key, ResidentModel {
            vertices: upload(bytemuck::cast_slice(&model.vertices), wgpu::BufferUsages::VERTEX),
            indices: upload(bytemuck::cast_slice(&model.indices), wgpu::BufferUsages::INDEX),
            count: model.indices.len() as u32, instance_buffer: Self::instance_buffer(device, std::mem::size_of::<ModelInstance>() as u64),
            transforms: Vec::new(), last_drawn: Instant::now(),
        });
        Ok(())
    }

    fn draw(&self, encoder: &mut wgpu::CommandEncoder, image: &wgpu::TextureView) {
        let Some((_, depth)) = &self.depth else { return; };
        if self.residents.is_empty() { return; }
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("WWO static models"), color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: image, resolve_target: None,
                ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store },
            })],
            depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                view: depth, depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.), store: wgpu::StoreOp::Discard }),
                stencil_ops: None,
            }), occlusion_query_set: None, timestamp_writes: None,
        });
        pass.set_pipeline(&self.pipeline);
        for model in self.residents.values().filter(|model|!model.transforms.is_empty()) {
            pass.set_vertex_buffer(0, model.vertices.slice(..));
            pass.set_vertex_buffer(1, model.instance_buffer.slice(..));
            pass.set_index_buffer(model.indices.slice(..), wgpu::IndexFormat::Uint32);
            pass.draw_indexed(0..model.count, 0, 0..model.transforms.len() as u32);
        }
    }
}

fn layout(device:&wgpu::Device,entries:&[wgpu::BindGroupLayoutEntry])->wgpu::BindGroupLayout {
    device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor{label:None,entries})
}
fn entry(binding:u32,visibility:wgpu::ShaderStages,ty:wgpu::BindingType)->wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {binding,visibility,ty,count:None}
}
fn uniform(binding:u32,stage:wgpu::ShaderStages)->wgpu::BindGroupLayoutEntry {
    entry(binding,stage,wgpu::BindingType::Buffer {ty:wgpu::BufferBindingType::Uniform,
          has_dynamic_offset:false,min_binding_size:None})
}
fn texture_entry(binding:u32,kind:wgpu::TextureSampleType,dim:wgpu::TextureViewDimension)->wgpu::BindGroupLayoutEntry {
    entry(binding,wgpu::ShaderStages::FRAGMENT,wgpu::BindingType::Texture {sample_type:kind,view_dimension:dim,multisampled:false})
}
fn sampled(binding:u32)->wgpu::BindGroupLayoutEntry {
    texture_entry(binding,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2)
}
fn sampler_entry(binding:u32)->wgpu::BindGroupLayoutEntry {
    entry(binding,wgpu::ShaderStages::FRAGMENT,wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering))
}
fn tex_resource(binding:u32,texture:&wgpu::TextureView)->wgpu::BindGroupEntry<'_> {
    wgpu::BindGroupEntry{binding,resource:wgpu::BindingResource::TextureView(texture)}
}
fn sampler_resource(binding:u32,sampler:&wgpu::Sampler)->wgpu::BindGroupEntry<'_> {
    wgpu::BindGroupEntry{binding,resource:wgpu::BindingResource::Sampler(sampler)}
}
fn buf_resource(binding:u32,buffer:&wgpu::Buffer)->wgpu::BindGroupEntry<'_> {
    wgpu::BindGroupEntry{binding,resource:buffer.as_entire_binding()}
}
fn bind(device:&wgpu::Device,layout:&wgpu::BindGroupLayout,entries:&[wgpu::BindGroupEntry<'_>])->wgpu::BindGroup {
    device.create_bind_group(&wgpu::BindGroupDescriptor{label:None,layout,entries})
}
fn buffer(device:&wgpu::Device,size:usize)->wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor{label:None,size:size as u64,usage:wgpu::BufferUsages::UNIFORM|wgpu::BufferUsages::COPY_DST,mapped_at_creation:false})
}
fn create_texture(device:&wgpu::Device,size:[u32;3],format:wgpu::TextureFormat)->wgpu::Texture {
    create_texture_mips(device,size,format,1)
}
fn create_texture_mips(device:&wgpu::Device,size:[u32;3],format:wgpu::TextureFormat,levels:u32)->wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label:Some("WWO map inputs"),size:extent(size),mip_level_count:levels,sample_count:1,dimension:wgpu::TextureDimension::D2,
        format,usage:wgpu::TextureUsages::COPY_DST|wgpu::TextureUsages::TEXTURE_BINDING,view_formats:&[]
    })
}
fn extent([width,height,depth_or_array_layers]:[u32;3])->wgpu::Extent3d {wgpu::Extent3d{width,height,depth_or_array_layers}}

fn offscreen_texture(device:&wgpu::Device,[width,height]:[u32;2])->wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label:Some("WWO offscreen frame"),size:extent([width,height,1]),mip_level_count:1,
        sample_count:1,dimension:wgpu::TextureDimension::D2,format:wgpu::TextureFormat::Rgba8Unorm,
        usage:wgpu::TextureUsages::RENDER_ATTACHMENT|wgpu::TextureUsages::COPY_SRC,view_formats:&[],
    })
}
fn write_texture(queue:&wgpu::Queue,tex:&wgpu::Texture,[w,h,layers]:[u32;3],channels:u32,bytes:&[u8]) {
    write_texture_mip(queue,tex,[w,h,layers],channels,bytes,0);
}
fn write_texture_mip(queue:&wgpu::Queue,tex:&wgpu::Texture,[w,h,layers]:[u32;3],channels:u32,bytes:&[u8],level:u32) {
    queue.write_texture(wgpu::TexelCopyTextureInfo {texture:tex,mip_level:level,origin:wgpu::Origin3d::ZERO,aspect:wgpu::TextureAspect::All},
        bytes,wgpu::TexelCopyBufferLayout {offset:0,bytes_per_row:Some(w*channels),rows_per_image:Some(h)},extent([w,h,layers]));
}

pub struct CloseSample {
    extent:[f32;4],
    image:Raster,
}

impl CloseSample {
    pub fn read(manifest:&Path)->io::Result<Self> {
        #[derive(serde::Deserialize)]
        struct Manifest {extent:[f32;4],image:PathBuf}
        let Manifest{extent,image}=serde_json::from_reader(File::open(manifest)?)?;
        let [west,south,east,north]=extent;
        if !(-180.<=west && west<east && east<=180. && -90.<=south && south<north && north<=90.) {
            return Err(io::Error::other("Invalid close terrain sample extent"));
        }
        let image=crate::decode_rgba(File::open(manifest.with_file_name(image))?)?;
        if image.size.iter().any(|&side| !(8..=2048).contains(&side) || side%8!=0) {
            return Err(io::Error::other("Close terrain sample dimensions must be multiples of eight, up to 2048"));
        }
        Ok(Self{extent,image})
    }

    fn upload(sample:Option<Self>,device:&wgpu::Device,queue:&wgpu::Queue)->(wgpu::TextureView,wgpu::Buffer) {
        let bounds=buffer(device,std::mem::size_of::<[f32;4]>());
        let texture=if let Some(Self{extent,image})=sample {
            queue.write_buffer(&bounds,0,bytemuck::bytes_of(&extent));
            let [mut width,mut height]=image.size;
            let texture=create_texture_mips(device,[width,height,1],wgpu::TextureFormat::Rgba8Unorm,4);
            let mut pixels=image.pixels;
            for level in 0..4 {
                write_texture_mip(queue,&texture,[width,height,1],4,&pixels,level);
                if level==3 { break; }
                pixels=downsample_rgba(&pixels,width,height);
                width/=2;
                height/=2;
            }
            texture
        }else{
            create_texture(device,[1,1,1],wgpu::TextureFormat::Rgba8Unorm)
        };
        (texture.create_view(&Default::default()),bounds)
    }
}

fn downsample_rgba(pixels:&[u8],width:u32,height:u32)->Vec<u8> {
    let mut reduced=Vec::with_capacity(pixels.len()/4);
    for y in (0..height).step_by(2) {
        for x in (0..width).step_by(2) {
            let row=(y*width+x) as usize*4;
            let next=row+width as usize*4;
            for c in 0..4 {
                let sum=u16::from(pixels[row+c])+u16::from(pixels[row+c+4])
                    +u16::from(pixels[next+c])+u16::from(pixels[next+c+4]);
                reduced.push(((sum+2)/4) as u8);
            }
        }
    }
    reduced
}

pub(crate) fn write_texture_layer(queue:&wgpu::Queue,texture:&wgpu::Texture,level:u32,layer:u32,
                                  size:u32,bytes:&[u8]) {
    queue.write_texture(wgpu::TexelCopyTextureInfo {
        texture,mip_level:level,origin:wgpu::Origin3d{x:0,y:0,z:layer},aspect:wgpu::TextureAspect::All,
    },bytes,wgpu::TexelCopyBufferLayout{offset:0,bytes_per_row:Some(size*4),rows_per_image:None},
    extent([size,size,1]));
}

impl Renderer {
    pub async fn new(window:Arc<Window>, atlas:Raster, flags:Raster, hud:[Raster;3], globe_art:[Raster;2], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, detail:Option<terrain_detail::Catalogue>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>, observe:bool)->Result<Self,String> {
        let size=window.inner_size().into();
        Self::with_target(Some(window),size,atlas,flags,hud,globe_art,layout_bytes,natural,None,detail,events,observe).await
    }

    pub async fn new_offscreen(size:[u32;2], atlas:Raster, flags:Raster, hud:[Raster;3], globe_art:[Raster;2], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, close:Option<CloseSample>, detail:Option<terrain_detail::Catalogue>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>)->Result<Self,String> {
        Self::with_target(None,size,atlas,flags,hud,globe_art,layout_bytes,natural,close,detail,events,false).await
    }

    async fn with_target(window:Option<Arc<Window>>, size:[u32;2], atlas:Raster, flags:Raster, hud:[Raster;3], globe_art:[Raster;2], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, close:Option<CloseSample>, detail:Option<terrain_detail::Catalogue>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>, observe:bool)->Result<Self,String> {
        let instance=wgpu::Instance::new(&wgpu::InstanceDescriptor {backends:wgpu::Backends::VULKAN,..Default::default()});
        let surface=window.map(|window|instance.create_surface(window)).transpose().map_err(|e|e.to_string())?;
        let adapter=instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference:wgpu::PowerPreference::HighPerformance,compatible_surface:surface.as_ref(),force_fallback_adapter:false
        }).await.ok_or(if surface.is_some(){"A Vulkan adapter with window presentation is required"}else{"A Vulkan adapter is required"})?;
        let info=adapter.get_info();
        let landscape_supported=adapter.limits().max_sampled_textures_per_shader_stage>=17;
        let mut features=if natural.is_some() {wgpu::Features::TEXTURE_COMPRESSION_BC}else{wgpu::Features::empty()};
        if !adapter.features().contains(features) {return Err("自然地貌需要支持 BC7 纹理的 Vulkan 显卡。".into());}
        if observe && landscape_supported {
            features |= adapter.features() & (wgpu::Features::TIMESTAMP_QUERY|wgpu::Features::PIPELINE_STATISTICS_QUERY);
        }
        let (device,queue)=adapter.request_device(&wgpu::DeviceDescriptor {
            label:Some("WWO strategic map host"),required_features:features,
            required_limits:wgpu::Limits {max_texture_dimension_2d:4096,
                max_sampled_textures_per_shader_stage:if landscape_supported {17}else{16},
                ..wgpu::Limits::downlevel_defaults()},
            memory_hints:wgpu::MemoryHints::MemoryUsage
        },None).await.map_err(|e|e.to_string())?;
        let (target,format)=if let Some(surface)=surface {
            let caps=surface.get_capabilities(&adapter);
            let format=caps.formats.iter().copied().find(|f| matches!(f,wgpu::TextureFormat::Bgra8Unorm|wgpu::TextureFormat::Rgba8Unorm))
                .ok_or("An 8-bit UNORM surface is required")?;
            let config=wgpu::SurfaceConfiguration {
                usage:wgpu::TextureUsages::RENDER_ATTACHMENT|(caps.usages&wgpu::TextureUsages::COPY_SRC),
                format,width:size[0].max(1),height:size[1].max(1),present_mode:wgpu::PresentMode::Fifo,
                desired_maximum_frame_latency:2,alpha_mode:caps.alpha_modes[0],view_formats:Vec::new()
            };
            surface.configure(&device,&config);
            (RenderTarget::Window(surface,config),format)
        }else{
            if size.into_iter().any(|n|n==0||n>device.limits().max_texture_dimension_2d) {
                return Err("Invalid offscreen viewport size".into());
            }
            let image=offscreen_texture(&device,size);
            let format=image.format();
            (RenderTarget::Offscreen(image),format)
        };
        let fragment=wgpu::ShaderStages::FRAGMENT;
        let compute_fragment=fragment|wgpu::ShaderStages::COMPUTE;
        let global_entries=[uniform(0,compute_fragment|wgpu::ShaderStages::VERTEX),
            wgpu::BindGroupLayoutEntry{visibility:compute_fragment,..sampler_entry(1)},sampler_entry(2),sampled(3),
            texture_entry(4,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array),sampled(5),
            texture_entry(6,wgpu::TextureSampleType::Float{filterable:false},wgpu::TextureViewDimension::D2),sampled(7),sampled(8),
            texture_entry(10,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array),
            wgpu::BindGroupLayoutEntry{visibility:compute_fragment,..texture_entry(11,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array)},
            wgpu::BindGroupLayoutEntry{visibility:compute_fragment,..texture_entry(12,wgpu::TextureSampleType::Uint,wgpu::TextureViewDimension::D2)}];
        let glob=layout(&device,&global_entries);
        let close_layout=layout(&device,&[sampled(0),uniform(1,fragment)]);
        let pages=layout(&device,&[uniform(0,fragment),sampled(1),sampled(2),sampled(3),
            texture_entry(4,wgpu::TextureSampleType::Uint,wgpu::TextureViewDimension::D2)]);
        let screen_layout=layout(&device,&[uniform(0,wgpu::ShaderStages::VERTEX_FRAGMENT)]);
        let instrument_layout=layout(&device,&[uniform(0,fragment)]);
        let font_layout=layout(&device,&[sampled(0),sampler_entry(1)]);
        let linear=device.create_sampler(&wgpu::SamplerDescriptor {
            mag_filter:wgpu::FilterMode::Linear,min_filter:wgpu::FilterMode::Linear,
            mipmap_filter:wgpu::FilterMode::Linear,..Default::default()
        });
        let wrap=device.create_sampler(&wgpu::SamplerDescriptor {
            address_mode_u:wgpu::AddressMode::Repeat,mag_filter:wgpu::FilterMode::Linear,min_filter:wgpu::FilterMode::Linear,
            mipmap_filter:wgpu::FilterMode::Linear,..Default::default()
        });
        let view=buffer(&device,std::mem::size_of::<View>());
        let instrument_view=bind(&device,&instrument_layout,&[buf_resource(0,&view)]);
        let screen_size=buffer(&device,32);
        let screen=bind(&device,&screen_layout,&[buf_resource(0,&screen_size)]);
        let palette=create_texture(&device,[256,2,1],wgpu::TextureFormat::Rgba8Unorm);
        let palette_view=palette.create_view(&Default::default());
        let scenario_size=if layout_bytes.is_empty(){[1,1,2]}else{[256,256,2]};
        let scenario=create_texture(&device,scenario_size,wgpu::TextureFormat::Rgba8Unorm);
        write_texture(&queue,&scenario,scenario_size,4,if layout_bytes.is_empty(){&[0;8]}else{layout_bytes});
        let scenario=scenario.create_view(&wgpu::TextureViewDescriptor{dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()});
        let flag_poses=create_texture(&device,[15,256,1],wgpu::TextureFormat::Rgba32Float);
        let flag_pose_view=flag_poses.create_view(&Default::default());
        let flag_texture=create_texture(&device,[flags.size[0],flags.size[1],1],wgpu::TextureFormat::Rgba8Unorm);
        write_texture(&queue,&flag_texture,[flags.size[0],flags.size[1],1],4,&flags.pixels);
        let flags=flag_texture.create_view(&Default::default());
        let [galactic_chart,ocean_material]=globe_art.map(|image|{
            let [w,h]=image.size;
            let texture=create_texture(&device,[w,h,1],wgpu::TextureFormat::Rgba8Unorm);
            write_texture(&queue,&texture,[w,h,1],4,&image.pixels);
            texture.create_view(&Default::default())
        });
        let river_source=natural.as_ref().and_then(|(catalogue,_)|catalogue.river_lines()).map(Path::to_owned);
        let water_source=natural.as_ref().and_then(|(catalogue,_)|catalogue.water_geometry()).map(Path::to_owned);
        let terrain=natural.map(|(catalogue,proxy)|Terrain::new(&device,&queue,catalogue,proxy,landscape_supported))
            .transpose().map_err(|error|error.to_string())?;
        let [terrain_world,terrain_detail,terrain_index]=if let Some(terrain)=&terrain {
            terrain.views()
        }else{
            let empty=||create_texture(&device,[1,1,1],wgpu::TextureFormat::Rgba8Unorm)
                .create_view(&wgpu::TextureViewDescriptor{dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()});
            [empty(),empty(),create_texture(&device,[1,1,1],wgpu::TextureFormat::R32Uint).create_view(&Default::default())]
        };
        let mut surface=GroundSurface::new(&device,landscape_supported,water_source.is_some());
        let water_pages=water_source.and_then(|source| {
            match crate::hydrology::WaterPages::open(&source,&queue,&surface.water) {
                Ok(pages)=>Some(pages),
                Err(error)=>{eprintln!("Water geometry fallback · {} · {error}",source.display());None}
            }
        });
        let close_extent=close.as_ref().map(|sample|sample.extent.map(f64::from));
        let (close_surface,close_bounds)=CloseSample::upload(close,&device,&queue);
        let close_group=bind(&device,&close_layout,&[tex_resource(0,&close_surface),buf_resource(1,&close_bounds)]);
        let global_resources=[buf_resource(0,&view),sampler_resource(1,&linear),sampler_resource(2,&wrap),
            tex_resource(3,&palette_view),tex_resource(4,&scenario),tex_resource(5,&flags),tex_resource(6,&flag_pose_view),
            tex_resource(7,&galactic_chart),tex_resource(8,&ocean_material),
            tex_resource(10,&terrain_world),tex_resource(11,&terrain_detail),tex_resource(12,&terrain_index)];
        let globals=bind(&device,&glob,&global_resources);
        let flag_art=bind(&device,&font_layout,&[tex_resource(0,&flags),sampler_resource(1,&linear)]);
        let [w,h]=atlas.size;
        let font=create_texture(&device,[w,h,1],wgpu::TextureFormat::Rgba8Unorm);
        write_texture(&queue,&font,[w,h,1],4,&atlas.pixels);
        let font=bind(&device,&font_layout,&[tex_resource(0,&font.create_view(&Default::default())),sampler_resource(1,&linear)]);
        let [hud_art,hud_type,menu_art]=hud.map(|image|{
            let [w,h]=image.size;
            let texture=create_texture(&device,[w,h,1],wgpu::TextureFormat::Rgba8Unorm);
            write_texture(&queue,&texture,[w,h,1],4,&image.pixels);
            bind(&device,&font_layout,&[tex_resource(0,&texture.create_view(&Default::default())),sampler_resource(1,&linear)])
        });
        let fallback=[wgpu::TextureFormat::Rgba8Unorm,wgpu::TextureFormat::Rg8Unorm,wgpu::TextureFormat::Rg8Uint].map(|format|{
            let tex=create_texture(&device,[1,1,1],format);
            let n=format.block_copy_size(None).unwrap();
            write_texture(&queue,&tex,[1,1,1],n,&[0;4][..n as usize]);
            tex.create_view(&Default::default())
        });
        let globe_source=include_str!("globe.wgsl");
        let scenery_source=if landscape_supported {include_str!("landscape.wgsl")} else {
            "fn geographic_ground_tint(ll:vec2f, fallback:vec3f)->vec3f {return fallback;}
            fn landscape_relief(base:vec3f, ll:vec2f, world:vec3f, water:f32, mpp:f32)->vec3f {
                if view.settings.y>=.5 || view.map_style.z<5. {return base;}
                return mix(base,natural_land_material(vec4f(base,water),world,mpp),ground_material_weight(water,mpp));
            }"
        };
        let globe_shader=device.create_shader_module(wgpu::ShaderModuleDescriptor{
            label:Some("WWO globe and Z7 landscape"),
            source:wgpu::ShaderSource::Wgsl(format!("{globe_source}\n{scenery_source}").into()),
        });
        if water_pages.is_some() {surface.init_water_raster(&device,&globe_shader,&view);}
        let hud_shader=device.create_shader_module(wgpu::include_wgsl!("hud.wgsl"));
        let mesh_layout=[wgpu::VertexBufferLayout {array_stride:std::mem::size_of::<Vertex>() as u64,
            step_mode:wgpu::VertexStepMode::Vertex,attributes:&wgpu::vertex_attr_array![0=>Float32x2,1=>Unorm8x4,2=>Float32x2]}];
        let pipeline=|groups:&[&wgpu::BindGroupLayout],module:&wgpu::ShaderModule,v,f,buffers:&[wgpu::VertexBufferLayout]| {
            let layout=device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor{label:None,bind_group_layouts:groups,push_constant_ranges:&[]});
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label:Some(f),layout:Some(&layout),primitive:Default::default(),depth_stencil:None,
                multisample:Default::default(),multiview:None,cache:None,
                vertex:wgpu::VertexState{module,entry_point:Some(v),compilation_options:Default::default(),buffers},
                fragment:Some(wgpu::FragmentState {module,entry_point:Some(f),compilation_options:Default::default(),
                    targets:&[Some(wgpu::ColorTargetState{format,blend:Some(wgpu::BlendState::ALPHA_BLENDING),write_mask:wgpu::ColorWrites::ALL})]})
            })
        };
        let globe=pipeline(&[&glob,&pages,&close_layout,&surface.layout],&globe_shader,"triangle","map",&[]);
        let rivers=river_source.map(|source| {
            let proxy=events.clone();
            std::thread::spawn(move || {
                let result=Rivers::open(&source).map_err(|error|io::Error::other(format!("{} · {error}",source.display())));
                let _=proxy.send_event(crate::HostEvent::Rivers(result));
            });
            RiverLayer {
                rivers:None,
                pipeline:pipeline(&[&glob,&pages,&close_layout,&surface.layout],&globe_shader,"river_stroke","river_ink",&mesh_layout),
                mesh:MeshBuffers::new(&device,16384,4096),
            }
        });
        let solid=pipeline(&[&screen_layout],&hud_shader,"screen_vertex","solid",&mesh_layout);
        let text=pipeline(&[&screen_layout,&font_layout],&hud_shader,"screen_vertex","image",&mesh_layout);
        let flag=pipeline(&[&screen_layout,&font_layout],&hud_shader,"screen_vertex","flag",&mesh_layout);
        let loading=pipeline(&[&screen_layout],&hud_shader,"screen_vertex","loading",&mesh_layout);
        let clock_face=pipeline(&[&screen_layout,&font_layout],&hud_shader,"screen_vertex","clock_face",&mesh_layout);
        let clock_gears=pipeline(&[&screen_layout],&hud_shader,"screen_vertex","clock_gears",&mesh_layout);
        let history_light=pipeline(&[&screen_layout],&hud_shader,"screen_vertex","history_light",&mesh_layout);
        let instrument=pipeline(&[&screen_layout,&font_layout,&instrument_layout],&hud_shader,"screen_vertex","instrument",&mesh_layout);
        let meshes=std::array::from_fn(|_|MeshBuffers::new(&device,65536,32768));
        let models=ModelLayer::new(&device,format,events);
        let landscape_pipeline=landscape_supported.then_some((format,glob,globe_shader));
        Ok(Self{target,device,queue,gpu:format!("{} {:?}",info.name,info.backend),view,globals,pages,palette,flag_poses,fallback,
                globe,terrain,rivers,water_pages,close_extent,close_layout,close_group,detail:detail.map(terrain_detail::Stream::new),
                solid,text,flag,loading,history_light,clock_gears,clock_face,font,flag_art,hud_art,hud_type,menu_art,instrument,instrument_view,screen,screen_size,meshes,models,
                battle:None,landscape:None,landscape_pipeline,surface,transport_network:None,transport_vehicles:None})
    }

    pub fn prepare_battle(&mut self, terrain: &wwo_map_lab::battlefield_terrain::BattlefieldTerrain, root: &Path) -> io::Result<()> {
        if self.battle.is_none() {
            let format = match &self.target {
                RenderTarget::Window(_, config) => config.format,
                RenderTarget::Offscreen(texture) => texture.format(),
            };
            self.battle = Some(crate::battle_render::Scene::new(&self.device, &self.queue, format, terrain, root)?);
        }
        Ok(())
    }

    pub fn battle_uses_original_model(&self) -> bool {
        self.battle.as_ref().is_some_and(crate::battle_render::Scene::uses_original_model)
    }

    pub fn clear_battle(&mut self) {
        self.battle = None;
    }

    pub fn update_close_terrain(&mut self,camera:&Camera,size:[u32;2],enabled:bool,now:Instant)->[f32;3] {
        if let (Some(detail),Some(terrain))=(&mut self.detail,&self.terrain) {
            if let Some(index)=detail.update(camera,size,enabled,now) {
                if terrain.request_detail(index,detail.catalogue.clone()) {detail.requested(index);}
            }
            let survey=detail.resident.is_some_and(|index| {
                matches!(detail.catalogue.regions[index].surface,terrain_detail::Surface::Survey)
            });
            return [detail.weight,1.,if survey {1.} else {0.}];
        }
        let weight=self.close_extent.and_then(|extent|terrain_detail::viewport(camera,size)
            .map(|corners|terrain_detail::extent_weight(extent,corners))).unwrap_or(0.);
        [weight,0.,0.]
    }

    pub fn close_terrain_ready(&mut self,index:usize,result:io::Result<Vec<u8>>) {
        let Some(detail)=&mut self.detail else {return;};
        if !detail.completed(index,result.is_ok()) {return;}
        let Ok(blocks)=result else {return;};
        let region=&detail.catalogue.regions[index];
        let [w,h]=region.size;
        let texture=create_texture_mips(&self.device,[w,h,1],wgpu::TextureFormat::Bc7RgbaUnorm,terrain_detail::MIPS);
        let mut offset=0;
        for (level,[width,height],length) in terrain_detail::mips(region.size) {
            self.queue.write_texture(wgpu::TexelCopyTextureInfo {
                texture:&texture,mip_level:level,origin:wgpu::Origin3d::ZERO,aspect:wgpu::TextureAspect::All,
            },&blocks[offset..offset+length],wgpu::TexelCopyBufferLayout {
                offset:0,bytes_per_row:Some(width*4),rows_per_image:None,
            },extent([width,height,1]));
            offset+=length;
        }
        let view=texture.create_view(&Default::default());
        let bounds=buffer(&self.device,std::mem::size_of::<[f32;4]>());
        self.queue.write_buffer(&bounds,0,bytemuck::bytes_of(&region.extent.map(|d| d as f32)));
        self.close_group=bind(&self.device,&self.close_layout,&[tex_resource(0,&view),buf_resource(1,&bounds)]);
    }

    pub fn close_terrain_status(&self)->Option<serde_json::Value> {
        self.detail.as_ref().map(terrain_detail::Stream::status)
    }

    pub fn model_ready(&mut self, key: ModelKey, mesh: io::Result<ModelMesh>) -> io::Result<()> {
        self.models.complete(&self.device, key, mesh)
    }

    pub fn resident_models(&self) -> Vec<(&'static str, &'static str)> {
        let mut models:Vec<_>=self.models.residents.keys().map(|key|(key.model(),key.lod())).collect();
        models.sort_unstable();
        models
    }

    pub fn model_instances(&self) -> Vec<(&'static str, usize)> {
        let mut models: Vec<_> = self.models.residents.iter()
            .filter(|(_,model)|!model.transforms.is_empty())
            .map(|(key, model)| (key.model(), model.transforms.len())).collect();
        models.sort_unstable();
        models
    }

    pub fn has_model(&self, model:&VisibleModel) -> bool {
        let [low,high]=self.models.lod_range(model);
        low<high && self.models.residents.contains_key(&model.key)
    }
    pub fn update_terrain(&mut self,camera:&Camera,size:[u32;2],now:Instant)->io::Result<()> {
        if let Some(terrain)=&mut self.terrain {
            terrain.update(&self.queue,camera,size,now);
            if let Some(water)=&mut self.water_pages {
                water.update(&self.queue,&self.surface.water,camera,size,now);
            }
            if terrain.view_demand()>=6 && !self.surface.loaded {
                let height=terrain.enable_landscape(&self.device);
                self.surface.load(&self.device,&self.queue,height)?;
            }
        }
        Ok(())
    }

    fn prepare_landscape(&mut self,camera:&Camera,size:[u32;2],enabled:bool,now:Instant) {
        let Some(terrain)=&mut self.terrain else {return;};
        let enabled=enabled&&terrain.view_max().max(terrain.view_demand())>=6;
        if enabled && camera.mpp<1460. && terrain.landscape_cover() {
            if let Some((format,glob,shader))=self.landscape_pipeline.take() {
                self.landscape=Some(Landscape::new(&self.device,format,[&glob,&self.pages,&self.close_layout,&self.surface.layout],&shader));
            }
        }
        if let Some(layer)=&mut self.landscape {
            layer.prepare(&self.queue,camera,size,terrain,enabled);
            terrain.reveal_pages(layer.awaiting_pages(),now);
        } else {
            terrain.reveal_pages(&HashSet::new(),now);
        }
    }

    pub fn prepare_rivers(&mut self,camera:&Camera,size:[u32;2],enabled:bool) {
        let Some(layer)=&mut self.rivers else {return;};
        if let Some(mesh)=layer.rivers.as_mut().and_then(|rivers|rivers.project(camera,size,enabled)) {
            layer.mesh.upload(&self.device,&self.queue,mesh);
        }
    }

    pub fn rivers_ready(&mut self,result:io::Result<Rivers>) {
        if let Some(layer)=&mut self.rivers {
            match result {
                Ok(rivers)=>layer.rivers=Some(rivers),
                Err(error)=>{
                    eprintln!("无法打开河流中心线 · {error}");
                    self.rivers=None;
                }
            }
        }
    }

    pub fn terrain_ready(&mut self,completion:terrain::Completion)->io::Result<()> {
        if let Some(terrain)=&mut self.terrain {terrain.complete(&self.queue,completion)?;}
        Ok(())
    }

    pub fn terrain_max_level(&self)->u32 {self.terrain.as_ref().map_or(0,Terrain::max_level)}

    pub fn terrain_view_level(&self)->u32 {self.terrain.as_ref().map_or(0,Terrain::view_max)}
    pub fn terrain_viewport_mix(&self)->[[f32;4];2] {self.terrain.as_ref().map_or([[-1.;4];2],Terrain::viewport_mix)}

    pub fn terrain_exact(&self)->bool {self.terrain.as_ref().is_some_and(Terrain::exact)}

    pub fn packed_terrain(&self)->bool {self.terrain.as_ref().is_some_and(Terrain::packed)}

    pub fn terrain_status(&self) -> Option<serde_json::Value> {
        self.terrain.as_ref().map(|terrain|{
            let mut status=terrain.status();
            status["landscape_chunks"]=self.landscape.as_ref().map_or(0,Landscape::visible_chunks).into();
            status["landscape_cached_chunks"]=self.landscape.as_ref().map_or(0,Landscape::cached_chunks).into();
            status["landscape_built_chunks"]=self.landscape.as_ref().map_or(0,Landscape::built_chunks).into();
            status["landscape_pending"]=self.landscape.as_ref().is_some_and(Landscape::pending).into();
            status["surface_material_loaded"]=self.surface.loaded.into();
            status["river_centrelines_ready"]=self.rivers.as_ref().is_some_and(|layer|layer.rivers.is_some()).into();
            if let Some(water)=&self.water_pages {
                let (resident, wanted)=water.status();
                status["water_geometry_resident"]=resident[0].into();
                status["water_geometry_wanted"]=wanted[0].into();
                status["water_geometry_view_resident"]=resident[1].into();
                status["water_geometry_view_wanted"]=wanted[1].into();
                status["water_geometry_view_missing_outside_budget"]=water.missing_view_pages_outside_budget().into();
                status["water_geometry_buffer_bytes"]=self.surface.water.size().into();
                status["water_geometry_handoff_active"]=water.handoff_active().into();
                status["water_viewport_buffer_bytes"]=self.surface.water_pixels.size().into();
            }
            status
        })
    }

    pub fn terrain_frame_samples(&self,camera:&Camera,size:[u32;2])->Option<serde_json::Value> {
        self.terrain.as_ref().map(|terrain|terrain.frame_samples(camera,size))
    }

    pub fn terrain_fading(&self)->bool {
        self.terrain.as_ref().is_some_and(Terrain::fading)
            || self.detail.as_ref().is_some_and(terrain_detail::Stream::fading)
            || self.landscape.as_ref().is_some_and(Landscape::pending)
            || self.water_pages.as_ref().is_some_and(crate::hydrology::WaterPages::pending)
    }

    pub fn landscape_counts(&self)->io::Result<LandscapeCounts> {
        self.landscape.as_ref().map_or(Ok(LandscapeCounts::default()),|layer|layer.counts(&self.device,&self.queue))
    }

    pub fn resize(&mut self,[w,h]:[u32;2]) {
        if let RenderTarget::Window(surface,config)=&mut self.target {
            config.width=w;config.height=h;
            surface.configure(&self.device,config);
        }
    }
    pub fn set_politics(&self,bytes:&[u8],flags:&[FlagUniform;256]) {
        write_texture(&self.queue,&self.palette,[256,2,1],4,bytes);
        write_texture(&self.queue,&self.flag_poses,[15,256,1],16,bytemuck::cast_slice(flags));
    }
    pub fn upload(&self,tile:&Tile,pixels:Pixels)->Page {
        let uniform=self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor{label:None,
            contents:bytemuck::bytes_of(&TileState::new(tile,1.,[0.;4],[0.;4])),usage:wgpu::BufferUsages::UNIFORM|wgpu::BufferUsages::COPY_DST});
        let [w,h]=tile.size;
        let textures=[
            (wgpu::TextureFormat::Rgba8Unorm,pixels.terrain.as_slice()),
            (wgpu::TextureFormat::Rgba8Unorm,pixels.cover.as_slice()),
            (wgpu::TextureFormat::Rg8Unorm,pixels.city.as_slice()),
            (wgpu::TextureFormat::Rg8Uint,pixels.ids.as_slice()),
        ].into_iter().enumerate().map(|(index,(format,data))|{
            if data.is_empty(){return None;}
            let levels=match index {
                1 if tile.surface_span>0 => w.max(h).ilog2()+1,
                2 => tile.city_levels(),
                _ => 1,
            };
            let tex=create_texture_mips(&self.device,[w,h,1],format,levels);
            let channels=format.block_copy_size(None).unwrap();
            let mut start=0;
            for level in 0..levels {
                let size=[(w>>level).max(1),(h>>level).max(1),1];
                let end=start+(size.into_iter().product::<u32>()*channels) as usize;
                write_texture_mip(&self.queue,&tex,size,channels,&data[start..end],level);
                start=end;
            }
            Some(tex.create_view(&Default::default()))
        }).collect::<Vec<_>>();
        let layer=|index:usize| textures[index].as_ref().unwrap_or_else(||&self.fallback[index-1]);
        let group=bind(&self.device,&self.pages,&[buf_resource(0,&uniform),tex_resource(1,layer(0)),
            tex_resource(2,layer(1)),tex_resource(3,layer(2)),tex_resource(4,layer(3))]);
        let bytes=pixels.terrain.len()+pixels.cover.len()+pixels.city.len()+pixels.ids.len();
        let water=pixels.terrain.chunks_exact(4).map(|p|p[2]).collect();
        Page {group,uniform,ids:pixels.ids,water,bytes}
    }
    fn prepare_transport(&mut self, overlay: Option<TransportOverlay<'_>>) {
        let network=overlay.as_ref().and_then(|overlay|overlay.network);
        if let Some((revision,mesh))=network {
            if self.transport_network.as_ref().is_none_or(|(previous,_)|*previous!=revision) {
                let (previous,buffers)=self.transport_network.get_or_insert_with(|| {
                    (revision,MeshBuffers::new(&self.device,4096,2048))
                });
                buffers.upload(&self.device,&self.queue,mesh);
                *previous=revision;
            }
        } else {
            self.transport_network=None;
        }
        if let Some(mesh)=overlay.map(|overlay|overlay.vehicles).filter(|mesh|!mesh.indices.is_empty()) {
            let buffers=self.transport_vehicles.get_or_insert_with(||MeshBuffers::new(&self.device,4096,2048));
            buffers.upload(&self.device,&self.queue,mesh);
        } else {
            self.transport_vehicles=None;
        }
    }

    pub fn render(&mut self, view:&View,base:&Page,pages:&[(&Page,&Tile,[u32;4],f32)],
                  meshes:&crate::ui::Layers,fade:Option<&crate::ui::Layers>,seconds:f32,show_map:bool,capture:Option<&Path>,models:&[VisibleModel],
                  transport:Option<TransportOverlay<'_>>,
                  (camera,landscape_enabled,now):(&Camera,bool,Instant),
                  battle:Option<BattleFrame<'_>>)->io::Result<Option<io::Result<()>>> {
        let frame=if let RenderTarget::Window(surface,config)=&self.target {
            match surface.get_current_texture() {
                Ok(frame)=>Some(frame),
                Err(wgpu::SurfaceError::Outdated|wgpu::SurfaceError::Lost)=>{
                    surface.configure(&self.device,config);return Ok(None);
                }
                Err(wgpu::SurfaceError::Timeout)=>return Ok(None),
                Err(e)=>return Err(io::Error::other(e))
            }
        }else{None};
        let size=match &self.target {
            RenderTarget::Window(_,config)=>[config.width,config.height],
            RenderTarget::Offscreen(texture)=>[texture.width(),texture.height()],
        };
        if battle.is_none() {self.prepare_landscape(camera,size,landscape_enabled,now);}
        self.prepare_transport(transport.filter(|_|show_map && battle.is_none()));
        let (texture,copy_src)=match &self.target {
            RenderTarget::Window(_,config)=>(&frame.as_ref().unwrap().texture,config.usage.contains(wgpu::TextureUsages::COPY_SRC)),
            RenderTarget::Offscreen(texture)=>(texture,true),
        };
        let [w,h]=[texture.width(),texture.height()];
        let format=texture.format();
        if battle.is_none() {
            self.models.prepare(&self.device,&self.queue,[w,h],models);
            let mut frame_view=*view;
            frame_view.projection_axes[0][3]=seconds;
            if let Some(water)=&self.water_pages {
                frame_view.water_clock=water.shader_clock(now);
            }
            self.queue.write_buffer(&self.view,0,bytemuck::bytes_of(&frame_view));
        }
        self.queue.write_buffer(&self.screen_size,0,bytemuck::cast_slice(&[w as f32,h as f32,0.,0.,1.,seconds,0.,0.]));
        for (page,tile,_,opacity) in pages {
            let edges=if tile.city {
                let [w,s,e,n]=tile.bounds;
                [((e-w)*5./f64::from(tile.size[0])) as f32,((n-s)*5./f64::from(tile.size[1])) as f32,
                 ((e-w)*5./f64::from(tile.size[0])) as f32,((n-s)*5./f64::from(tile.size[1])) as f32]
            } else {[tile.surface_inset as f32;4]};
            let mut edge_ready=[0.;4];
            if tile.surface_span>0 || tile.city {
                let [west,south,east,north]=tile.core;
                for (_,neighbor,_,alpha) in pages.iter().filter(|(_,neighbor,_,_)| {
                    if tile.city {neighbor.city&&neighbor.group==tile.group}
                    else {neighbor.surface_span==tile.surface_span}
                }) {
                    let [w,s,e,n]=neighbor.core;
                    let shared=(*alpha/opacity.max(0.001)).min(1.);
                    if s==south&&n==north {
                        if e==west {edge_ready[0]=shared;}
                        if w==east {edge_ready[2]=shared;}
                    }
                    if w==west&&e==east {
                        if n==south {edge_ready[1]=shared;}
                        if s==north {edge_ready[3]=shared;}
                    }
                }
            }
            self.queue.write_buffer(&page.uniform,0,bytemuck::bytes_of(&TileState::new(tile,*opacity,edges,edge_ready)));
        }
        let layers=||meshes.iter().chain(fade.into_iter().flatten());
        for ((mesh,_),draw) in layers().zip(self.meshes.iter_mut()) {draw.upload(&self.device,&self.queue,mesh);}
        let image=texture.create_view(&Default::default());
        let mut encoder=self.device.create_command_encoder(&Default::default());
        if show_map {
            if let Some(water)=&self.water_pages {
                self.surface.project_water(&self.device,&mut encoder,[w,h],view,water.revision());
            }
        }
        if let Some(battle) = battle {
            let scene = self.battle.as_mut().ok_or_else(|| io::Error::other("battle renderer not initialized"))?;
            scene.draw(&self.device, &self.queue, &mut encoder, &image, size, battle.view, battle.state, battle.terrain);
        } else {
            let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label:Some("WWO map"),color_attachments:&[Some(wgpu::RenderPassColorAttachment{
                    view:&image,resolve_target:None,ops:wgpu::Operations {load:wgpu::LoadOp::Clear(wgpu::Color::BLACK),store:wgpu::StoreOp::Store}
                })],depth_stencil_attachment:None,occlusion_query_set:None,timestamp_writes:None
            });
            if show_map {
                pass.set_pipeline(&self.globe);
                pass.set_bind_group(0,&self.globals,&[]);
                pass.set_bind_group(1,&base.group,&[]);
                pass.set_bind_group(2,&self.close_group,&[]);
                pass.set_bind_group(3,&self.surface.group,&[]);
                pass.draw(0..3,0..1);
                if let Some(layer)=self.rivers.as_ref().filter(|layer|layer.rivers.as_ref().is_some_and(Rivers::visible)) {
                    pass.set_pipeline(&layer.pipeline);
                    layer.mesh.draw(&mut pass);
                    pass.set_pipeline(&self.globe);
                }
                for (page,_,[x,y,w,h],_) in pages {
                    pass.set_scissor_rect(*x,*y,*w,*h);
                    pass.set_bind_group(1,&page.group,&[]);
                    pass.draw(0..3,0..1);
                }
            }
            drop(pass);
            if let Some(layer)=&mut self.landscape {
                layer.draw(&self.device,&mut encoder,&image,[&self.globals,&base.group,&self.close_group,&self.surface.group],[w,h]);
            }
            if self.transport_network.is_some()||self.transport_vehicles.is_some() {
                let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label:Some("WWO transport map"),
                    color_attachments:&[Some(wgpu::RenderPassColorAttachment {
                        view:&image,resolve_target:None,
                        ops:wgpu::Operations{load:wgpu::LoadOp::Load,store:wgpu::StoreOp::Store},
                    })],
                    depth_stencil_attachment:None,occlusion_query_set:None,timestamp_writes:None,
                });
                pass.set_pipeline(&self.solid);
                pass.set_bind_group(0,&self.screen,&[]);
                if let Some((_,network))=&self.transport_network {network.draw(&mut pass);}
                if let Some(vehicles)=&self.transport_vehicles {vehicles.draw(&mut pass);}
            }
            self.models.draw(&mut encoder, &image);
        }
        {
            let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label:Some("WWO HUD"),color_attachments:&[Some(wgpu::RenderPassColorAttachment{
                    view:&image,resolve_target:None,ops:wgpu::Operations {load:wgpu::LoadOp::Load,store:wgpu::StoreOp::Store}
                })],depth_stencil_attachment:None,occlusion_query_set:None,timestamp_writes:None
            });
            for ((_,ink),draw) in layers().zip(self.meshes.iter()) {
                match ink {
                    Ink::ClockGears=>pass.set_pipeline(&self.clock_gears),
                    Ink::Solid=>pass.set_pipeline(&self.solid),
                    Ink::Loading=>pass.set_pipeline(&self.loading),
                    Ink::HistoryLight=>pass.set_pipeline(&self.history_light),
                    Ink::Instrument=>{
                        pass.set_pipeline(&self.instrument);
                        pass.set_bind_group(1,&self.hud_art,&[]);
                        pass.set_bind_group(2,&self.instrument_view,&[]);
                    }
                    Ink::Text|Ink::Flag|Ink::HudArtGlass|Ink::HudArt|Ink::HudText|Ink::MenuArt=>{
                        pass.set_pipeline(if matches!(ink,Ink::Flag){&self.flag}else if matches!(ink,Ink::HudArtGlass){&self.clock_face}else{&self.text});
                        let texture=match ink{Ink::Flag=>&self.flag_art,Ink::HudArt|Ink::HudArtGlass=>&self.hud_art,Ink::HudText=>&self.hud_type,Ink::MenuArt=>&self.menu_art,_=>&self.font};
                        pass.set_bind_group(1,texture,&[]);
                    }
                }
                pass.set_bind_group(0,&self.screen,&[]);
                draw.draw(&mut pass);
            }
        }
        let padded=(w*4).div_ceil(256)*256;
        let readback=capture.filter(|_|copy_src).map(|_|{
            let data=self.device.create_buffer(&wgpu::BufferDescriptor {label:Some("WWO capture"),size:u64::from(padded)*u64::from(h),
                usage:wgpu::BufferUsages::COPY_DST|wgpu::BufferUsages::MAP_READ,mapped_at_creation:false});
            encoder.copy_texture_to_buffer(wgpu::TexelCopyTextureInfo {texture,mip_level:0,origin:wgpu::Origin3d::ZERO,aspect:wgpu::TextureAspect::All},
                wgpu::TexelCopyBufferInfo {buffer:&data,layout:wgpu::TexelCopyBufferLayout{offset:0,bytes_per_row:Some(padded),rows_per_image:Some(h)}},
                extent([w,h,1]));
            data
        });
        self.queue.submit([encoder.finish()]);
        if let Some(frame)=frame {frame.present();}
        let saved=(|| -> io::Result<()> {
            let Some(path)=capture else{return Ok(());};
            let data=readback.ok_or_else(||io::Error::other("Vulkan surface does not support screenshot readback"))?;
            let slice=data.slice(..);
            let (send,receive)=std::sync::mpsc::channel();
            slice.map_async(wgpu::MapMode::Read,move |result|{let _=send.send(result);});
            let _=self.device.poll(wgpu::Maintain::Wait);
            receive.recv().map_err(io::Error::other)?.map_err(io::Error::other)?;
            let raw=slice.get_mapped_range();
            let mut rgba=Vec::with_capacity((w*h*4) as usize);
            for row in raw.chunks_exact(padded as usize) {rgba.extend_from_slice(&row[..(w*4) as usize]);}
            if format==wgpu::TextureFormat::Bgra8Unorm {
                for pixel in rgba.chunks_exact_mut(4) {pixel.swap(0,2);}
            }
            let mut png=png::Encoder::new(std::fs::File::options().write(true).create_new(true).open(path)?,w,h);
            png.set_color(png::ColorType::Rgba);
            png.set_depth(png::BitDepth::Eight);
            let mut writer=png.write_header()?;
            writer.write_image_data(&rgba)?;
            writer.finish()?;
            Ok(())
        })();
        Ok(Some(saved))
    }
}
