use crate::{camera::{Camera,EARTH},compact::{Raster,Vertex},overlay::Mesh,politics::FlagUniform,terrain::{self,Terrain},ui::Ink,world::{Pixels,Tile}};
use crate::landmarks::{self, ModelKey, ModelMesh, ModelVertex, VisibleModel};
use bytemuck::{Pod,Zeroable};
use std::collections::{HashMap, HashSet};
use std::{io,path::Path,sync::Arc,time::Instant};
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
    projection_axes:[[f32;4];3],
    projection_origin:[f32;4],
    pub settings:[f32;4],
    pub selection:[f32;4],
    pub map_style:[f32;4],
    pub edits:[Edit;crate::timeline::MAX_SITES],
    pub natural_lod:[[f32;4];2],
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
struct TileState {extent:[f32;4],core:[f32;4],region:[f32;4],options:[f32;4],edges:[f32;4]}
impl TileState {
    fn new(tile:&Tile,opacity:f32,edges:[f32;4])->Self {
        let cast=|values:[f64;4]| values.map(|a|a as f32);
        Self {extent:cast(tile.bounds),core:cast(tile.core),region:cast(tile.group),
              options:[opacity,f32::from(tile.printed+u8::from(tile.cover)),u8::from(tile.city) as f32,u8::from(tile.level==0) as f32],edges}
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

pub struct Renderer {
    target:RenderTarget,
    device:wgpu::Device,
    queue:wgpu::Queue,
    pub gpu:String,
    models: ModelLayer,
    view:wgpu::Buffer,
    globals:wgpu::BindGroup,
    pages:wgpu::BindGroupLayout,
    palette:wgpu::Texture,
    flag_poses:wgpu::Texture,
    fallback:[wgpu::TextureView;3],
    globe:wgpu::RenderPipeline,
    terrain:Option<Terrain>,
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

struct ResidentModel {
    vertices: wgpu::Buffer,
    indices: wgpu::Buffer,
    count: u32,
    instance_buffer: wgpu::Buffer,
    transforms: Vec<[[f32; 4]; 4]>,
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
                    array_stride: 64,
                    step_mode: wgpu::VertexStepMode::Instance,
                    attributes: &wgpu::vertex_attr_array![3=>Float32x4, 4=>Float32x4, 5=>Float32x4, 6=>Float32x4],
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
        self.visible.clear();
        self.visible.extend(models.iter().map(|model| model.key));
        self.residents.retain(|key, _| self.visible.contains(key));
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
        for resident in self.residents.values_mut() {
            resident.transforms.clear();
        }
        for model in models {
            let key = model.key;
            if let Some(resident) = self.residents.get_mut(&key) {
                resident.transforms.push(model.clip_from_model);
            } else if !self.failed.contains(&key) && self.pending.insert(key) {
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
        for resident in self.residents.values_mut() {
            let transforms = bytemuck::cast_slice(&resident.transforms);
            if transforms.len() as u64 > resident.instance_buffer.size() {
                resident.instance_buffer = Self::instance_buffer(device, transforms.len().next_power_of_two() as u64);
            }
            queue.write_buffer(&resident.instance_buffer, 0, transforms);
        }
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
            count: model.indices.len() as u32, instance_buffer: Self::instance_buffer(device, 64),
            transforms: Vec::new(),
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
        for model in self.residents.values() {
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

pub(crate) fn write_texture_layer(queue:&wgpu::Queue,texture:&wgpu::Texture,level:u32,layer:u32,
                                  size:u32,bytes:&[u8]) {
    queue.write_texture(wgpu::TexelCopyTextureInfo {
        texture,mip_level:level,origin:wgpu::Origin3d{x:0,y:0,z:layer},aspect:wgpu::TextureAspect::All,
    },bytes,wgpu::TexelCopyBufferLayout{offset:0,bytes_per_row:Some(size*4),rows_per_image:None},
    extent([size,size,1]));
}

impl Renderer {
    pub async fn new(window:Arc<Window>, atlas:Raster, flags:Raster, hud:[Raster;3], globe_art:[Raster;3], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>)->Result<Self,String> {
        let size=window.inner_size().into();
        Self::with_target(Some(window),size,atlas,flags,hud,globe_art,layout_bytes,natural,events).await
    }

    pub async fn new_offscreen(size:[u32;2], atlas:Raster, flags:Raster, hud:[Raster;3], globe_art:[Raster;3], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>)->Result<Self,String> {
        Self::with_target(None,size,atlas,flags,hud,globe_art,layout_bytes,natural,events).await
    }

    async fn with_target(window:Option<Arc<Window>>, size:[u32;2], atlas:Raster, flags:Raster, hud:[Raster;3], globe_art:[Raster;3], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>)->Result<Self,String> {
        let instance=wgpu::Instance::new(&wgpu::InstanceDescriptor {backends:wgpu::Backends::VULKAN,..Default::default()});
        let surface=window.map(|window|instance.create_surface(window)).transpose().map_err(|e|e.to_string())?;
        let adapter=instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference:wgpu::PowerPreference::HighPerformance,compatible_surface:surface.as_ref(),force_fallback_adapter:false
        }).await.ok_or(if surface.is_some(){"A Vulkan adapter with window presentation is required"}else{"A Vulkan adapter is required"})?;
        let info=adapter.get_info();
        let features=if natural.is_some() {wgpu::Features::TEXTURE_COMPRESSION_BC}else{wgpu::Features::empty()};
        if !adapter.features().contains(features) {return Err("自然地貌需要支持 BC7 纹理的 Vulkan 显卡。".into());}
        let (device,queue)=adapter.request_device(&wgpu::DeviceDescriptor {
            label:Some("WWO strategic map host"),required_features:features,
            required_limits:wgpu::Limits {max_texture_dimension_2d:4096,..wgpu::Limits::downlevel_defaults()},
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
        let glob=layout(&device,&[uniform(0,fragment),sampler_entry(1),sampler_entry(2),sampled(3),
            texture_entry(4,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array),sampled(5),
            texture_entry(6,wgpu::TextureSampleType::Float{filterable:false},wgpu::TextureViewDimension::D2),sampled(7),sampled(8),sampled(9),
            texture_entry(10,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array),
            texture_entry(11,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array),
            texture_entry(12,wgpu::TextureSampleType::Uint,wgpu::TextureViewDimension::D2),
            sampled(13),sampler_entry(14)]);
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
        let land_repeat=device.create_sampler(&wgpu::SamplerDescriptor {
            address_mode_u:wgpu::AddressMode::Repeat,address_mode_v:wgpu::AddressMode::Repeat,
            mag_filter:wgpu::FilterMode::Linear,min_filter:wgpu::FilterMode::Linear,
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
        let [galactic_chart,ocean_detail,ocean_ice]=globe_art.map(|image|{
            let [w,h]=image.size;
            let texture=create_texture(&device,[w,h,1],wgpu::TextureFormat::Rgba8Unorm);
            write_texture(&queue,&texture,[w,h,1],4,&image.pixels);
            texture.create_view(&Default::default())
        });
        let terrain=natural.map(|(catalogue,proxy)|Terrain::new(&device,&queue,catalogue,proxy))
            .transpose().map_err(|error|error.to_string())?;
        let [terrain_world,terrain_detail,terrain_index]=if let Some(terrain)=&terrain {
            terrain.views()
        }else{
            let empty=||create_texture(&device,[1,1,1],wgpu::TextureFormat::Rgba8Unorm)
                .create_view(&wgpu::TextureViewDescriptor{dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()});
            [empty(),empty(),create_texture(&device,[1,1,1],wgpu::TextureFormat::R32Uint).create_view(&Default::default())]
        };
        let land_art=crate::decode_rgba(&include_bytes!("land-material.png")[..])
            .map_err(|error|error.to_string())?;
        let [material_w,material_h]=land_art.size;
        let levels=material_w.ilog2()+1;
        let land_surface=create_texture_mips(&device,[material_w,material_h,1],wgpu::TextureFormat::Rgba8Unorm,levels);
        let mut pixels=land_art.pixels;
        for level in 0..levels {
            let [w,h]=[material_w>>level,material_h>>level];
            write_texture_mip(&queue,&land_surface,[w,h,1],4,&pixels,level);
            if w==1 { break; }
            let mut reduced=Vec::with_capacity(pixels.len()/4);
            for y in (0..h).step_by(2) {
                for x in (0..w).step_by(2) {
                    let row=(y*w+x) as usize*4;
                    let next=row+w as usize*4;
                    for c in 0..4 {
                        let sum=u16::from(pixels[row+c])+u16::from(pixels[row+c+4])
                            +u16::from(pixels[next+c])+u16::from(pixels[next+c+4]);
                        reduced.push(((sum+2)/4) as u8);
                    }
                }
            }
            pixels=reduced;
        }
        let land_surface=land_surface.create_view(&Default::default());
        let globals=bind(&device,&glob,&[buf_resource(0,&view),sampler_resource(1,&linear),sampler_resource(2,&wrap),
            tex_resource(3,&palette_view),tex_resource(4,&scenario),tex_resource(5,&flags),tex_resource(6,&flag_pose_view),
            tex_resource(7,&galactic_chart),tex_resource(8,&ocean_detail),tex_resource(9,&ocean_ice),
            tex_resource(10,&terrain_world),tex_resource(11,&terrain_detail),tex_resource(12,&terrain_index),
            tex_resource(13,&land_surface),sampler_resource(14,&land_repeat)]);
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
        let globe_shader=device.create_shader_module(wgpu::include_wgsl!("globe.wgsl"));
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
        let globe=pipeline(&[&glob,&pages],&globe_shader,"triangle","map",&[]);
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
        Ok(Self{target,device,queue,gpu:format!("{} {:?}",info.name,info.backend),view,globals,pages,palette,flag_poses,fallback,
                globe,terrain,solid,text,flag,loading,history_light,clock_gears,clock_face,font,flag_art,hud_art,hud_type,menu_art,instrument,instrument_view,screen,screen_size,meshes,models})
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
            .map(|(key, model)| (key.model(), model.transforms.len())).collect();
        models.sort_unstable();
        models
    }

    pub fn has_model(&self, key: ModelKey) -> bool { self.models.residents.contains_key(&key) }
    pub fn update_terrain(&mut self,camera:&Camera,size:[u32;2],now:Instant) {
        if let Some(terrain)=&mut self.terrain {terrain.update(&self.queue,camera,size,now);}
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
        self.terrain.as_ref().map(Terrain::status)
    }

    pub fn terrain_frame_samples(&self,camera:&Camera,size:[u32;2])->Option<serde_json::Value> {
        self.terrain.as_ref().map(|terrain|terrain.frame_samples(camera,size))
    }

    pub fn terrain_fading(&self)->bool {
        self.terrain.as_ref().is_some_and(Terrain::fading)
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
            contents:bytemuck::bytes_of(&TileState::new(tile,1.,[0.;4])),usage:wgpu::BufferUsages::UNIFORM|wgpu::BufferUsages::COPY_DST});
        let [w,h]=tile.size;
        let textures=[
            (wgpu::TextureFormat::Rgba8Unorm,pixels.terrain.as_slice()),
            (wgpu::TextureFormat::Rgba8Unorm,pixels.cover.as_slice()),
            (wgpu::TextureFormat::Rg8Unorm,pixels.city.as_slice()),
            (wgpu::TextureFormat::Rg8Uint,pixels.ids.as_slice()),
        ].into_iter().enumerate().map(|(index,(format,data))|{
            if data.is_empty(){return None;}
            let levels=if index==1&&tile.surface_span>0 {w.max(h).ilog2()+1} else {1};
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
    pub fn render(&mut self, view:&View,base:&Page,pages:&[(&Page,&Tile,[u32;4],f32)],
                  meshes:&crate::ui::Layers,fade:Option<&crate::ui::Layers>,seconds:f32,show_map:bool,capture:Option<&Path>,models:&[VisibleModel])->io::Result<Option<io::Result<()>>> {
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
        let (texture,copy_src)=match &self.target {
            RenderTarget::Window(_,config)=>(&frame.as_ref().unwrap().texture,config.usage.contains(wgpu::TextureUsages::COPY_SRC)),
            RenderTarget::Offscreen(texture)=>(texture,true),
        };
        let [w,h]=[texture.width(),texture.height()];
        let format=texture.format();
        self.models.prepare(&self.device,&self.queue,[w,h],models);
        self.queue.write_buffer(&self.view,0,bytemuck::bytes_of(view));
        self.queue.write_buffer(&self.screen_size,0,bytemuck::cast_slice(&[w as f32,h as f32,0.,0.,1.,seconds,0.,0.]));
        for (page,tile,_,opacity) in pages {
            let mut edges=[tile.surface_inset as f32;4];
            if tile.surface_span>0 {
                let [west,south,east,north]=tile.core;
                for (_,neighbor,_,_) in pages.iter().filter(|(_,neighbor,_,_)|neighbor.surface_span==tile.surface_span) {
                    let [w,s,e,n]=neighbor.core;
                    if s==south&&n==north {
                        if e==west {edges[0]=0.;}
                        if w==east {edges[2]=0.;}
                    }
                    if w==west&&e==east {
                        if n==south {edges[1]=0.;}
                        if s==north {edges[3]=0.;}
                    }
                }
            }
            self.queue.write_buffer(&page.uniform,0,bytemuck::bytes_of(&TileState::new(tile,*opacity,edges)));
        }
        let layers=||meshes.iter().chain(fade.into_iter().flatten());
        for ((mesh,_),draw) in layers().zip(self.meshes.iter_mut()) {draw.upload(&self.device,&self.queue,mesh);}
        let image=texture.create_view(&Default::default());
        let mut encoder=self.device.create_command_encoder(&Default::default());
        {
            let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label:Some("WWO map"),color_attachments:&[Some(wgpu::RenderPassColorAttachment{
                    view:&image,resolve_target:None,ops:wgpu::Operations {load:wgpu::LoadOp::Clear(wgpu::Color::BLACK),store:wgpu::StoreOp::Store}
                })],depth_stencil_attachment:None,occlusion_query_set:None,timestamp_writes:None
            });
            if show_map {
                pass.set_pipeline(&self.globe);
                pass.set_bind_group(0,&self.globals,&[]);
                pass.set_bind_group(1,&base.group,&[]);
                pass.draw(0..3,0..1);
                for (page,_,[x,y,w,h],_) in pages {
                    pass.set_scissor_rect(*x,*y,*w,*h);
                    pass.set_bind_group(1,&page.group,&[]);
                    pass.draw(0..3,0..1);
                }
            }
        }
        self.models.draw(&mut encoder, &image);
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
