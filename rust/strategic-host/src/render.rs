use crate::{camera::{Camera,EARTH},compact::{Raster,Vertex},overlay::Mesh,politics::FlagUniform,terrain::{self,Terrain},ui::Ink,world::{Pixels,Tile}};
use crate::landmarks::{self, ModelKey, ModelMesh, ModelVertex, VisibleModel};
use crate::city_models::{self, MODULES};
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
    pub road_layer:[u32;4],
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
        let city_style = if tile.city_ink_only {
            if tile.city_blocks { 5. } else if tile.city_streets { 4. }
            else if tile.city_area { 3. } else { 2. }
        } else {
            u8::from(tile.city) as f32
        };
        Self {extent:cast(tile.bounds),core:cast(tile.core),region:cast(tile.group),
              options:[opacity,f32::from(tile.printed+u8::from(tile.cover)),city_style,u8::from(tile.level==0) as f32],edges,edge_ready}
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

fn screen_vertex_layout() -> wgpu::VertexBufferLayout<'static> {
    const ATTRIBUTES:[wgpu::VertexAttribute;3]=wgpu::vertex_attr_array![0=>Float32x2,1=>Unorm8x4,2=>Float32x2];
    wgpu::VertexBufferLayout{array_stride:std::mem::size_of::<Vertex>() as u64,
        step_mode:wgpu::VertexStepMode::Vertex,attributes:&ATTRIBUTES}
}

fn map_shader(device:&wgpu::Device,globe:&str,scenery:&str) -> wgpu::ShaderModule {
    device.create_shader_module(wgpu::ShaderModuleDescriptor{
        label:Some("WWO globe and landscape"),
        source:wgpu::ShaderSource::Wgsl(format!("{globe}\n{scenery}\n{}",include_str!("city_material.wgsl")).into()),
    })
}

fn render_pipeline(device:&wgpu::Device,format:wgpu::TextureFormat,groups:&[&wgpu::BindGroupLayout],
    module:&wgpu::ShaderModule,vertex:&str,fragment:&str,buffers:&[wgpu::VertexBufferLayout]) -> wgpu::RenderPipeline {
    let layout=device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor{label:None,bind_group_layouts:groups,push_constant_ranges:&[]});
    device.create_render_pipeline(&wgpu::RenderPipelineDescriptor{
        label:Some(fragment),layout:Some(&layout),primitive:Default::default(),depth_stencil:None,
        multisample:Default::default(),multiview:None,cache:None,
        vertex:wgpu::VertexState{module,entry_point:Some(vertex),compilation_options:Default::default(),buffers},
        fragment:Some(wgpu::FragmentState{module,entry_point:Some(fragment),compilation_options:Default::default(),
            targets:&[Some(wgpu::ColorTargetState{format,blend:Some(wgpu::BlendState::ALPHA_BLENDING),write_mask:wgpu::ColorWrites::ALL})]}),
    })
}

pub struct TransportOverlay<'a> {
    pub network: Option<(u64, &'a Mesh)>,
    pub economy: Option<(u64, &'a Mesh)>,
    pub vehicles: &'a Mesh,
}

fn road_scissor(camera: &Camera, size: [u32; 2], [w,s,e,n]: [f64; 4]) -> Option<[u32; 4]> {
    let mut low=[f64::INFINITY;2];
    let mut high=[f64::NEG_INFINITY;2];
    for point in [[w,s],[w,n],[e,s],[e,n]] {
        let projected=camera.project(point,size)?;
        for i in 0..2 {
            low[i]=low[i].min(projected[i]);
            high[i]=high[i].max(projected[i]);
        }
    }
    // The projective bounds cover the small chart curvature between corners.
    let pad=2.+180./camera.mpp;
    let low: [u32;2]=std::array::from_fn(|i| (low[i]-pad).floor().clamp(0.,f64::from(size[i])) as u32);
    let high: [u32;2]=std::array::from_fn(|i| (high[i]+pad).ceil().clamp(0.,f64::from(size[i])) as u32);
    (high[0]>low[0] && high[1]>low[1]).then(|| [low[0],low[1],high[0]-low[0],high[1]-low[1]])
}

pub struct Renderer {
    target:RenderTarget,
    device:wgpu::Device,
    queue:wgpu::Queue,
    pub gpu:String,
    frame_timer:Option<FrameTimer>,
    pub frame_acquire_ms:f64,
    models: ModelLayer,
    transport_network: Option<(u64, MeshBuffers)>,
    transport_economy: Option<(u64, MeshBuffers)>,
    transport_vehicles: Option<MeshBuffers>,
    battle: Option<crate::battle_render::Scene>,
    landscape: Option<Landscape>,
    map_layout: wgpu::BindGroupLayout,
    landscape_shader: wgpu::ShaderModule,
    surface: GroundSurface,
    roads: wgpu::RenderPipeline,
    view:wgpu::Buffer,
    globals:wgpu::BindGroup,
    pages:wgpu::BindGroupLayout,
    palette:wgpu::Buffer,
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
    prologue_art:wgpu::BindGroup,
    prologue_texture:wgpu::Texture,
    prologue_scene:Option<usize>,
    prologue_paper:wgpu::BindGroup,
    opening_cloud:wgpu::BindGroup,
    menu_layout:wgpu::BindGroupLayout,
    menu_sampler:wgpu::Sampler,
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
    landscape:[wgpu::TextureView;2],
    art:wgpu::TextureView,
    materials:wgpu::TextureView,
    material_bytes:u64,
    water:wgpu::Buffer,
    city_water:wgpu::Buffer,
    city_roads:crate::city_roads::RoadSources,
    road_store:RoadStore,
    water_pixels:wgpu::Buffer,
    water_raster:Option<WaterRaster>,
    loaded:bool,
    custom_art:bool,
}

#[derive(Clone, Copy)]
struct RoadSlot {
    key:(u64,usize),
    bounds:[f64;4],
    bytes:usize,
    written:usize,
    active:bool,
    water:bool,
    ground:bool,
    road_coverage:Option<&'static str>,
}

struct RoadStore {
    base:u32,
    capacity:usize,
    registry:[u32;crate::city_roads::PAGE_SLOTS+1],
    slots:[Option<RoadSlot>;crate::city_roads::PAGE_SLOTS],
    uploading:bool,
    water_revision:u64,
}

impl RoadStore {
    fn allocate(storage:&mut Vec<u8>, limit:u64) -> Self {
        use crate::city_roads::{PAGE_BYTES,PAGE_DESCRIPTOR_WORDS,PAGE_SLOTS};
        let base=(storage.len()/4) as u32;
        let total=storage.len()+4*((PAGE_SLOTS+1)+PAGE_DESCRIPTOR_WORDS*PAGE_SLOTS+5)+PAGE_BYTES*PAGE_SLOTS;
        let capacity=if total as u64<=limit {PAGE_SLOTS} else {0};
        let bytes=if capacity>0 {total-20} else {storage.len()+4};
        storage.resize(bytes,0);
        Self{base,capacity,registry:[0;PAGE_SLOTS+1],slots:[None;PAGE_SLOTS],uploading:false,water_revision:0}
    }

    fn update(&mut self, queue:&wgpu::Queue, buffer:&wgpu::Buffer,
              wanted:&[crate::city_models::ReadyRoad<'_>], uploads:&mut CityUploads) {
        use crate::city_roads::{PAGE_BYTES,PAGE_DESCRIPTOR_WORDS,PAGE_SLOTS};
        let stride=PAGE_DESCRIPTOR_WORDS as u32;
        let descriptors=self.base+1+PAGE_SLOTS as u32;
        let start=descriptors+stride*PAGE_SLOTS as u32;
        if self.capacity==0 || (wanted.is_empty() && self.registry[0]==0 && !self.uploading) {return;}
        // Reserve the registry transfer so a removed slot cannot remain visible after reuse.
        let registry_bytes=std::mem::size_of_val(&self.registry) as u64;
        uploads.remaining-=registry_bytes;
        uploads.used+=registry_bytes;
        let mut water_changed=false;
        for entry in &mut self.slots {
            if let Some(slot)=entry.filter(|slot| !wanted.iter().any(|road|road.key==slot.key)) {
                water_changed|=slot.active && slot.water;
                *entry=None;
            }
        }
        self.uploading=false;
        for road in wanted {
            let Some(index)=self.slots.iter().position(|slot|slot.is_some_and(|slot|slot.key==road.key))
                .or_else(||self.slots.iter().position(Option::is_none)) else {break;};
            let slot=self.slots[index].get_or_insert(RoadSlot{key:road.key,bounds:road.bounds,
                bytes:road.page.data.len(),written:0,active:false,water:road.page.water_offset.is_some(),
                ground:road.page.ground_material.is_some(),road_coverage:road.page.coverage_offset
                    .map(|_|if road.page.has_vector {"mapped_or_empty"} else {"confirmed_empty"})});
            if slot.active {continue;}
            let contents=start+(PAGE_BYTES/4*index) as u32;
            uploads.write(queue,buffer,u64::from(contents)*4,&road.page.data,&mut slot.written);
            let descriptor=road.page.descriptor(contents,road.bounds);
            let data=bytemuck::cast_slice(&descriptor);
            let mut written=0;
            if slot.written==slot.bytes && uploads.remaining>=data.len() as u64 && uploads.can_allocate(data.len() as u64) {
                uploads.write(queue,buffer,u64::from(descriptors+stride*index as u32)*4,data,&mut written);
            }
            slot.active=written==data.len();
            water_changed|=slot.active && slot.water;
            self.uploading|=!slot.active;
        }
        let mut registry=[0;PAGE_SLOTS+1];
        let mut count=0;
        for (index,slot) in self.slots.iter().enumerate() {
            if slot.is_some_and(|slot|slot.active) {
                count+=1;
                registry[count]=descriptors+stride*index as u32;
            }
        }
        registry[0]=count as u32;
        if registry!=self.registry {
            let data=bytemuck::cast_slice(&registry);
            queue.write_buffer(buffer,u64::from(self.base)*4,data);
            uploads.written+=registry_bytes;
            self.registry=registry;
        } else {
            uploads.remaining+=registry_bytes;
            uploads.used-=registry_bytes;
        }
        if water_changed {self.water_revision+=1;}
    }

    fn active(&self) -> impl Iterator<Item=RoadSlot> + '_ {
        self.slots.iter().filter_map(|&slot|slot.filter(|slot|slot.active))
    }
}

struct WaterRaster {
    pipeline:wgpu::ComputePipeline,
    view:wgpu::BindGroup,
    gaps:[wgpu::BindGroup;2],
    buffers:Option<wgpu::BindGroup>,
    size:[u32;2],
    previous:Option<([[f32;4];3],[f32;4],[f32;4],u64,u64)>,
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
    fn new(device:&wgpu::Device, (materials,material_bytes):(wgpu::TextureView,u64), water_available:bool)->Self {
        let entries=[sampled(0),sampler_entry(1),wgpu::BindGroupLayoutEntry{
                visibility:wgpu::ShaderStages::FRAGMENT|wgpu::ShaderStages::COMPUTE,
                ..texture_entry(2,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array)
            },water_storage(3,wgpu::ShaderStages::FRAGMENT,true),water_storage(4,wgpu::ShaderStages::FRAGMENT,true),
            texture_entry(6,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array),
            water_storage(7,wgpu::ShaderStages::FRAGMENT|wgpu::ShaderStages::COMPUTE,true),wgpu::BindGroupLayoutEntry{
                visibility:wgpu::ShaderStages::FRAGMENT|wgpu::ShaderStages::COMPUTE,
                ..texture_entry(8,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array)
            }];
        let placeholder=create_texture(device,[1,1,1],wgpu::TextureFormat::Rgba8Unorm);
        let landscape=std::array::from_fn(|_|placeholder.create_view(&wgpu::TextureViewDescriptor{
            dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()}));
        let layout=layout(device,&entries);
        let repeat=device.create_sampler(&wgpu::SamplerDescriptor{
            address_mode_u:wgpu::AddressMode::Repeat,address_mode_v:wgpu::AddressMode::Repeat,
            mag_filter:wgpu::FilterMode::Linear,min_filter:wgpu::FilterMode::Linear,
            mipmap_filter:wgpu::FilterMode::Linear,..Default::default()
        });
        let art=create_texture(device,[1,1,1],wgpu::TextureFormat::Rgba8Unorm).create_view(&Default::default());
        let water=crate::hydrology::water_buffer(device,water_available);
        let mut city_geometry=zstd::stream::decode_all(&include_bytes!("city-geometry.bin.zst")[..])
            .expect("embedded city geometry");
        let park_offset=(city_geometry.len()/4) as u32;
        city_geometry.extend_from_slice(crate::city_parks::data());
        let fringe_offset=(city_geometry.len()/4) as u32;
        city_geometry.extend_from_slice(&zstd::stream::decode_all(&include_bytes!("paris-fringe-roads.bin.zst")[..])
            .expect("embedded Paris fringe roads"));
        let historic_surface_offset=(city_geometry.len()/4) as u32;
        city_geometry.extend_from_slice(&zstd::stream::decode_all(&include_bytes!("historical-city-surface.bin.zst")[..])
            .expect("embedded historical city surface"));
        let (city_roads, road_sources_offset)=crate::city_roads::RoadSources::append(&mut city_geometry,fringe_offset);
        let road_store=RoadStore::allocate(&mut city_geometry,u64::from(device.limits().max_storage_buffer_binding_size));
        city_geometry.extend_from_slice(&road_store.base.to_le_bytes());
        city_geometry.extend_from_slice(&road_sources_offset.to_le_bytes());
        city_geometry.extend_from_slice(&historic_surface_offset.to_le_bytes());
        city_geometry.extend_from_slice(&fringe_offset.to_le_bytes());
        city_geometry.extend_from_slice(&park_offset.to_le_bytes());
        let city_water=device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label:Some("Near-map city banks, streets, parks, and ground coverage"),
            contents:&city_geometry,
            usage:wgpu::BufferUsages::STORAGE|wgpu::BufferUsages::COPY_DST,
        });
        let water_pixels=water_pixels(device,4);
        let group=Self::bind(device,&layout,&repeat,&art,&landscape,&materials,&water,&water_pixels,&city_water);
        Self{layout,group,repeat,landscape,art,materials,material_bytes,water,city_water,city_roads,road_store,water_pixels,
            water_raster:None,loaded:false,custom_art:false}
    }

    fn bind(device:&wgpu::Device, layout:&wgpu::BindGroupLayout, repeat:&wgpu::Sampler,
            art:&wgpu::TextureView, landscape:&[wgpu::TextureView;2], materials:&wgpu::TextureView,
            water:&wgpu::Buffer, pixels:&wgpu::Buffer, city_water:&wgpu::Buffer)->wgpu::BindGroup {
        let entries=[tex_resource(0,art),sampler_resource(1,repeat),tex_resource(2,&landscape[0]),
            buf_resource(3,water),buf_resource(4,pixels),tex_resource(6,materials),buf_resource(7,city_water),
            tex_resource(8,&landscape[1])];
        bind(device,layout,&entries)
    }

    fn load(&mut self, device:&wgpu::Device, queue:&wgpu::Queue, landscape:Option<[wgpu::TextureView;2]>)->io::Result<()> {
        if self.loaded {return Ok(());}
        if let Some(landscape)=landscape {self.landscape=landscape;}
        if !self.custom_art {
            let art=crate::decode_rgba(&include_bytes!("land-material.png")[..])?;
            self.art=material_texture(device,queue,art);
        }
        self.group=Self::bind(device,&self.layout,&self.repeat,&self.art,&self.landscape,
            &self.materials,&self.water,&self.water_pixels,&self.city_water);
        self.loaded=true;
        Ok(())
    }

    fn create_water_raster(device:&wgpu::Device,shader:&wgpu::ShaderModule,view:&wgpu::Buffer) -> WaterRaster {
        let pipeline=device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor{
            label:Some("Project visible water boundaries"),layout:None,module:shader,
            entry_point:Some("raster_water"),compilation_options:Default::default(),cache:None,
        });
        let view=bind(device,&pipeline.get_bind_group_layout(0),&[buf_resource(0,view)]);
        let gaps=[1,2].map(|i|bind(device,&pipeline.get_bind_group_layout(i),&[]));
        WaterRaster{pipeline,view,gaps,buffers:None,size:[0,0],previous:None}
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
                &[buf_resource(3,&self.water),buf_resource(5,&self.water_pixels),buf_resource(7,&self.city_water)]));
            self.group=Self::bind(device,&self.layout,&self.repeat,&self.art,&self.landscape,
                &self.materials,&self.water,&self.water_pixels,&self.city_water);
            raster.previous=None;
        }
        let Some(buffers)=&raster.buffers else {return;};
        let key=(view.projection_axes,view.projection_origin,view.viewport,revision,self.road_store.water_revision);
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
    style:[f32;4],
    scale_and_mpp:[f32;4],
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct CityBatchUniform {
    clip_from_page: [[f32;4];4],
    fit: [[f32;4];4],
    inverse_size_and_opacity: [f32;4],
    // Align each dynamic uniform to the WebGPU 256-byte offset alignment.
    material: [f32;4],
    padding: [u32;24],
}

struct CityBatchDraw {
    page: ModelKey,
    kit: ModelKey,
    module: usize,
    opaque: bool,
    instances: [std::ops::Range<u32>;city_models::MAX_INSTANCE_RUNS],
}

struct ResidentModel {
    vertices: wgpu::Buffer,
    indices: wgpu::Buffer,
    count: u32,
    instance_buffer: wgpu::Buffer,
    transforms: Vec<ModelInstance>,
    city_instances: Option<[Option<wgpu::Buffer>;MODULES]>,
    last_drawn: Instant,
    mesh_uploaded: [usize; 2],
    instances_uploaded: [usize; MODULES],
}

impl ResidentModel {
    fn gpu_bytes(&self) -> u64 {
        self.vertices.size() + self.indices.size() + self.instance_buffer.size()
            + self.city_instances.iter().flatten().flatten().map(wgpu::Buffer::size).sum::<u64>()
    }

    fn mesh_ready(&self) -> bool {
        self.mesh_uploaded == [self.vertices.size() as usize, self.indices.size() as usize]
    }

    fn detail_ready(&self) -> bool {
        self.city_instances.as_ref().is_some_and(|buffers| buffers.iter().zip(self.instances_uploaded)
            .all(|(buffer, uploaded)| buffer.as_ref().is_none_or(|buffer| buffer.size() == uploaded as u64)))
    }
}

struct CityUploads {
    started: Instant,
    used: u64,
    remaining: u64,
    written: u64,
}

impl CityUploads {
    const GPU_LIMIT: u64 = 512 * 1024 * 1024;
    const FRAME_LIMIT: u64 = 4 * 1024 * 1024;
    const CHUNK: usize = 256 * 1024;
    const TIME: Duration = Duration::from_millis(2);

    fn can_allocate(&self, bytes: u64) -> bool {
        self.started.elapsed() < Self::TIME && bytes <= Self::GPU_LIMIT.saturating_sub(self.used)
    }

    fn write(&mut self, queue: &wgpu::Queue, buffer: &wgpu::Buffer, offset:u64, bytes: &[u8], uploaded: &mut usize) {
        while *uploaded < bytes.len() && self.remaining > 0 && self.started.elapsed() < Self::TIME {
            let count = (bytes.len() - *uploaded).min(Self::CHUNK).min(self.remaining as usize)
                .min(Self::GPU_LIMIT.saturating_sub(self.used) as usize);
            if count == 0 { break; }
            queue.write_buffer(buffer, offset+*uploaded as u64, &bytes[*uploaded..*uploaded + count]);
            *uploaded += count;
            self.remaining -= count as u64;
            self.written += count as u64;
            self.used += count as u64;
        }
    }
}

struct ModelLayer {
    pipeline: wgpu::RenderPipeline,
    city_pipeline: wgpu::RenderPipeline,
    opaque_city_pipeline: wgpu::RenderPipeline,
    city_uniforms: wgpu::Buffer,
    city_bindings: wgpu::BindGroup,
    city_batches: Vec<CityBatchDraw>,
    city_batch_uniforms: Vec<CityBatchUniform>,
    materials: wgpu::BindGroup,
    depth: Option<([u32; 2], wgpu::TextureView)>,
    residents: HashMap<ModelKey, ResidentModel>,
    visible: HashSet<ModelKey>,
    pending: HashSet<ModelKey>,
    failed: HashSet<ModelKey>,
    events: winit::event_loop::EventLoopProxy<crate::HostEvent>,
    city_override: Option<std::sync::Arc<[u8]>>,
    city_revision: u64,
    city_fixed_bytes: u64,
    city_meshes: HashMap<ModelKey, ModelMesh>,
    city_upload_due: bool,
    city_transfer_bytes: u64,
    city_gpu_batches: Vec<(u64, Vec<ResidentModel>, std::sync::Arc<std::sync::atomic::AtomicBool>)>,
}

impl ModelLayer {
    const DEPTH: wgpu::TextureFormat = wgpu::TextureFormat::Depth32Float;
    const CITY_LOD_CACHE_TIME: Duration = Duration::from_secs(2);

    fn city_lod_boundary(opacity: f32) -> f32 {
        // model_fragment uses the centres of the 16 Bayer ranks. Preserve that
        // exact pixel set and skip the mesh when its interval covers no rank.
        (opacity * 16. - 0.5).ceil().clamp(0., 16.) / 16.
    }

    fn new(device: &wgpu::Device, format: wgpu::TextureFormat, surface: &GroundSurface,
           events: winit::event_loop::EventLoopProxy<crate::HostEvent>) -> Self {
        let material_layout=layout(device,&[
            texture_entry(0,wgpu::TextureSampleType::Float{filterable:true},wgpu::TextureViewDimension::D2Array),
            sampler_entry(1),
        ]);
        let materials=bind(device,&material_layout,&[tex_resource(0,&surface.materials),sampler_resource(1,&surface.repeat)]);
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label:Some("WWO landmarks and city materials"),
            source:wgpu::ShaderSource::Wgsl(format!("{}\n{}",include_str!("landmark.wgsl"),
                include_str!("city_material.wgsl")).into()),
        });
        let city_layout=layout(device,&[entry(0,wgpu::ShaderStages::VERTEX,wgpu::BindingType::Buffer {
            ty:wgpu::BufferBindingType::Uniform, has_dynamic_offset:true, min_binding_size:None,
        })]);
        let batch_bytes=std::mem::size_of::<CityBatchUniform>() as u64;
        let city_uniforms=device.create_buffer(&wgpu::BufferDescriptor {
            label:Some("WWO city batch transforms"), size:batch_bytes*(city_models::MAX_RESIDENT*MODULES) as u64,
            usage:wgpu::BufferUsages::UNIFORM|wgpu::BufferUsages::COPY_DST,mapped_at_creation:false,
        });
        let city_bindings=bind(device,&city_layout,&[wgpu::BindGroupEntry{binding:0,
            resource:wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer:&city_uniforms,offset:0,size:std::num::NonZeroU64::new(batch_bytes),
        })}]);
        let pipeline=|vertex_entry,fragment_entry,instance_bytes,attributes:&[wgpu::VertexAttribute],groups:&[&wgpu::BindGroupLayout]| {
            let stages=device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label:Some("WWO static model"),bind_group_layouts:groups,push_constant_ranges:&[],
            });
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("WWO static models"), layout: Some(&stages), primitive: Default::default(),
                depth_stencil: Some(wgpu::DepthStencilState {
                    format: Self::DEPTH, depth_write_enabled: true, depth_compare: wgpu::CompareFunction::Less,
                    stencil: Default::default(), bias: Default::default(),
                }),
                multisample: Default::default(), multiview: None, cache: None,
                vertex: wgpu::VertexState {
                    module: &shader, entry_point: Some(vertex_entry), compilation_options: Default::default(),
                    buffers: &[wgpu::VertexBufferLayout {
                        array_stride: std::mem::size_of::<ModelVertex>() as u64,
                        step_mode: wgpu::VertexStepMode::Vertex,
                        attributes: &wgpu::vertex_attr_array![0 => Float32x3, 1 => Float32x3, 2 => Float32x4],
                    }, wgpu::VertexBufferLayout {
                        array_stride: instance_bytes,
                        step_mode: wgpu::VertexStepMode::Instance,
                        attributes,
                    }],
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader, entry_point: Some(fragment_entry), compilation_options: Default::default(),
                    targets: &[Some(wgpu::ColorTargetState { format, blend: None, write_mask: wgpu::ColorWrites::ALL })],
                }),
            })
        };
        let city_attributes=wgpu::vertex_attr_array![3=>Float32x4,4=>Float32x2,5=>Float32x3];
        let city_groups=[&material_layout,&city_layout];
        let city_stride=std::mem::size_of::<landmarks::FootprintModel>() as u64;
        let city_pipeline=pipeline("city_vertex","model_fragment",city_stride,&city_attributes,&city_groups);
        let opaque_city_pipeline=pipeline("city_vertex","opaque_city_fragment",city_stride,&city_attributes,&city_groups);
        let pipeline=pipeline("model_vertex","model_fragment",std::mem::size_of::<ModelInstance>() as u64,
            &wgpu::vertex_attr_array![3=>Float32x4,4=>Float32x4,5=>Float32x4,6=>Float32x4,7=>Float32x4,8=>Float32x4],
            &[&material_layout]);
        Self { pipeline, city_pipeline, opaque_city_pipeline, city_uniforms, city_bindings, city_batches:Vec::new(),city_batch_uniforms:Vec::new(),
            materials, depth: None, residents: HashMap::new(), visible: HashSet::new(),
            pending: HashSet::new(), failed: HashSet::new(), events, city_override:None,city_revision:0,
            city_fixed_bytes:surface.city_water.size()+surface.material_bytes+batch_bytes*(city_models::MAX_RESIDENT*MODULES) as u64,
            city_meshes:HashMap::new(),city_upload_due:false,city_transfer_bytes:0,city_gpu_batches:Vec::new() }
    }

    fn city_usage(&self) -> (u64,u64) {
        let resident = self.residents.iter().filter(|(key, _)| key.is_city())
            .map(|(_, model)| model.gpu_bytes()).sum::<u64>();
        let submitted = self.city_gpu_batches.iter().map(|(bytes, _, _)| bytes).sum::<u64>();
        (resident, submitted)
    }

    fn retire_city_gpu(&mut self, queue: &wgpu::Queue, evicted: Vec<ResidentModel>, staging: u64) {
        if evicted.is_empty() && staging == 0 { return; }
        let bytes = staging + evicted.iter().map(ResidentModel::gpu_bytes).sum::<u64>();
        let done = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let complete = done.clone();
        queue.on_submitted_work_done(move || complete.store(true, std::sync::atomic::Ordering::Release));
        self.city_gpu_batches.push((bytes, evicted, done));
    }

    fn maintain_city_gpu(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, now: Instant) {
        if !self.city_gpu_batches.is_empty() {
            let _ = device.poll(wgpu::Maintain::Poll);
            self.city_gpu_batches.retain(|(_, _, done)| !done.load(std::sync::atomic::Ordering::Acquire));
        }
        let expired = self.residents.iter().filter(|(key, model)|
            key.is_city() && !self.visible.contains(key)
                && now.saturating_duration_since(model.last_drawn) >= Self::CITY_LOD_CACHE_TIME)
            .map(|(&key, _)| key).collect::<Vec<_>>();
        let evicted = expired.into_iter().filter_map(|key| self.residents.remove(&key)).collect();
        self.retire_city_gpu(queue, evicted, 0);
    }

    fn prepare(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, size: [u32; 2], models: &[VisibleModel], mpp:f32,
               uploads:&mut CityUploads) {
        let now = Instant::now();
        self.city_batches.clear();
        self.city_batch_uniforms.clear();
        self.visible.clear();
        self.visible.extend(models.iter().filter(|model| model.lod_range[0] < model.lod_range[1]
            || model.city_page.is_some()).map(|model| model.key));
        for city in models.iter().filter_map(|model|model.city_page.as_ref()).filter(|city|city.preload) {
            self.visible.extend(city.geometry.instances.iter().enumerate().filter(|(_,rows)|!rows.is_empty())
                .map(|(module,_)|ModelKey::city_detail(city.kit,module)));
        }
        self.residents.retain(|key, _| self.visible.contains(key) || key.is_city());
        self.city_meshes.retain(|key, _| self.visible.contains(key));
        self.maintain_city_gpu(device, queue, now);
        self.city_upload_due = false;
        for resident in self.residents.values_mut() { resident.transforms.clear(); }
        if models.is_empty() {
            self.depth = None;
            self.city_transfer_bytes=uploads.written;
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
        let mut kits = self.city_meshes.keys().copied().collect::<Vec<_>>();
        kits.sort_unstable_by_key(|key| key.model());
        for key in kits {
            let mesh = self.city_meshes.remove(&key).unwrap();
            if !self.stage_city_mesh(device, queue, key, &mesh, uploads, now) {
                self.city_meshes.insert(key, mesh);
                self.city_upload_due = true;
            }
        }
        for model in models {
            let key = model.key;
            if let Some(city)=&model.city_page {
                if !self.stage_city_mesh(device, queue, key, &city.geometry.mesh, uploads, now) {
                    self.city_upload_due = true;
                    continue;
                }
                if city.preload && !self.stage_city_instances(device, queue, key, &city.geometry.instances, uploads) {
                    self.city_upload_due = true;
                }
            }
            let mut lod_range=self.lod_range(model);
            if model.city_page.is_some() {
                lod_range=lod_range.map(Self::city_lod_boundary);
            }
            if let Some(resident) = self.residents.get_mut(&key).filter(|resident| resident.mesh_ready()) {
                let city_material = model.city_page.as_ref().filter(|city|city.kit.is_none()).map_or(0., |city|
                    if city.paris {2.} else {1.});
                if let Some(city)=model.city_page.as_ref().filter(|city|city.preload) {
                    if lod_range[0]>0. {
                        for (module,batch) in city.batches.iter().enumerate().filter_map(|(i,b)|b.as_ref().map(|b|(i,b))) {
                            let [x,y,z]=batch.inverse_size;
                            self.city_batch_uniforms.push(CityBatchUniform {
                                clip_from_page:model.clip_from_model,fit:batch.fit,
                                inverse_size_and_opacity:[x,y,z,lod_range[0]],
                                material:[city_material,mpp,0.,0.],padding:[0;24],
                            });
                            self.city_batches.push(CityBatchDraw {page:key,kit:ModelKey::city_detail(city.kit,module),
                                module,opaque:lod_range[0] == 1.,instances:batch.instances.clone()});
                        }
                        resident.last_drawn=now;
                    }
                }
                if lod_range[0]<lod_range[1] {
                    let [low,high]=lod_range;
                    let waterline=f32::from(u8::from(key.clips_at_waterline()));
                    let [x,y,z]=model.model_scale;
                    resident.transforms.push(ModelInstance{clip_from_model:model.clip_from_model,
                        style:[low,high,waterline,city_material],scale_and_mpp:[x,y,z,mpp]});
                    resident.last_drawn = now;
                }
            }
        }
        self.city_transfer_bytes = uploads.written;
        if !self.city_batch_uniforms.is_empty() {
            let uniforms=bytemuck::cast_slice::<_,u8>(&self.city_batch_uniforms);
            queue.write_buffer(&self.city_uniforms,0,uniforms);
            self.city_transfer_bytes+=uniforms.len() as u64;
        }
        let mut city_jobs = self.pending.iter().filter(|key| key.is_city()).count()
            + self.city_meshes.len();
        for &key in &self.visible {
            if key.city_page_id().is_some() || self.residents.contains_key(&key) || self.city_meshes.contains_key(&key)
                || (key.is_city() && city_jobs >= 6)
                || self.failed.contains(&key) || !self.pending.insert(key) {continue;}
            city_jobs += usize::from(key.is_city());
            let events = self.events.clone();
            let revision=if key.is_city() {self.city_revision}else{0};
            let bytes=self.city_override.clone().filter(|_|key.is_city());
            let created = std::thread::Builder::new().name("WWO model loading".into()).spawn(move || {
                let _ = events.send_event(crate::HostEvent::Model(revision,key,landmarks::decode(key,bytes.as_deref())));
            });
            if let Err(error) = created {
                self.pending.remove(&key);
                self.failed.insert(key);
                let _ = self.events.send_event(crate::HostEvent::Model(revision,key,Err(error)));
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
        if let Some(city)=&model.city_page {
            if !self.residents.get(&model.key).is_some_and(ResidentModel::detail_ready)
                || city.batches.iter().enumerate().any(|(i,batch)|batch.is_some()
                    && !self.residents.get(&ModelKey::city_detail(city.kit,i)).is_some_and(ResidentModel::mesh_ready)) {
                return [0.,model.lod_range[1]];
            }
        }
        if let Some((key,opacity))=model.alternate {
            if !self.residents.get(&key).is_some_and(ResidentModel::mesh_ready) {return [0.,opacity];}
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
        if key.is_city() { self.city_meshes.insert(key, model); }
        else { self.upload(device,key,&model); }
        Ok(())
    }

    fn upload(&mut self, device:&wgpu::Device, key:ModelKey, model:&ModelMesh) {
        let upload = |contents, usage| device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("WWO static model"), contents, usage,
        });
        self.residents.insert(key, ResidentModel {
            vertices: upload(bytemuck::cast_slice(&model.vertices), wgpu::BufferUsages::VERTEX),
            indices: upload(bytemuck::cast_slice(&model.indices), wgpu::BufferUsages::INDEX),
            count: model.indices.len() as u32, instance_buffer: Self::instance_buffer(device, std::mem::size_of::<ModelInstance>() as u64),
            transforms: Vec::new(), city_instances:None,last_drawn: Instant::now(),
            mesh_uploaded:[bytemuck::cast_slice::<_, u8>(&model.vertices).len(), bytemuck::cast_slice::<_, u8>(&model.indices).len()],
            instances_uploaded:[0;MODULES],
        });
    }

    fn stage_city_mesh(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, key: ModelKey,
        mesh: &ModelMesh, uploads: &mut CityUploads, now: Instant) -> bool
    {
        let vertices = bytemuck::cast_slice::<_, u8>(&mesh.vertices);
        let indices = bytemuck::cast_slice::<_, u8>(&mesh.indices);
        let instance_bytes = std::mem::size_of::<ModelInstance>() as u64;
        if !self.residents.contains_key(&key) {
            let bytes = (vertices.len()+indices.len()) as u64 + instance_bytes;
            if !uploads.can_allocate(bytes) { return false; }
            uploads.used += bytes;
            let buffer = |size, usage| device.create_buffer(&wgpu::BufferDescriptor {
                label:Some("WWO streamed city mesh"),size,usage:usage|wgpu::BufferUsages::COPY_DST,mapped_at_creation:false,
            });
            self.residents.insert(key,ResidentModel {
                vertices:buffer(vertices.len() as u64,wgpu::BufferUsages::VERTEX),
                indices:buffer(indices.len() as u64,wgpu::BufferUsages::INDEX),
                count:mesh.indices.len() as u32,instance_buffer:Self::instance_buffer(device,instance_bytes),
                transforms:Vec::new(),city_instances:None,last_drawn:now,mesh_uploaded:[0;2],instances_uploaded:[0;MODULES],
            });
        }
        let resident = self.residents.get_mut(&key).unwrap();
        resident.last_drawn = now;
        uploads.write(queue, &resident.vertices, 0, vertices, &mut resident.mesh_uploaded[0]);
        uploads.write(queue, &resident.indices, 0, indices, &mut resident.mesh_uploaded[1]);
        resident.mesh_ready()
    }

    fn stage_city_instances(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, key: ModelKey,
        instances: &[Vec<landmarks::FootprintModel>;MODULES], uploads: &mut CityUploads) -> bool
    {
        let resident = self.residents.get_mut(&key).unwrap();
        if resident.city_instances.is_none() {
            let bytes = instances.each_ref().map(|rows| std::mem::size_of_val(rows.as_slice()) as u64);
            let total = bytes.iter().sum();
            if !uploads.can_allocate(total) { return false; }
            uploads.used += total;
            resident.city_instances = Some(bytes.map(|size| (size>0).then(|| Self::instance_buffer(device,size))));
        }
        for (module, buffer) in resident.city_instances.iter().flatten().enumerate() {
            if let Some(buffer) = buffer {
                uploads.write(queue, buffer, 0, bytemuck::cast_slice(&instances[module]), &mut resident.instances_uploaded[module]);
            }
        }
        resident.detail_ready()
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
        pass.set_bind_group(0,&self.materials,&[]);
        for model in self.residents.values().filter(|model|!model.transforms.is_empty()) {
            pass.set_vertex_buffer(0, model.vertices.slice(..));
            pass.set_vertex_buffer(1, model.instance_buffer.slice(..));
            pass.set_index_buffer(model.indices.slice(..), wgpu::IndexFormat::Uint32);
            pass.draw_indexed(0..model.count, 0, 0..model.transforms.len() as u32);
        }
        if !self.city_batches.is_empty() {
            pass.set_pipeline(&self.city_pipeline);
            let mut opaque=false;
            for (slot,batch) in self.city_batches.iter().enumerate() {
                // Fully opaque instances can use early depth testing. Keep the
                // draw order so an equal-depth overlap produces the same colour.
                if opaque != batch.opaque {
                    opaque=batch.opaque;
                    pass.set_pipeline(if opaque {&self.opaque_city_pipeline} else {&self.city_pipeline});
                }
                let kit=&self.residents[&batch.kit];
                let page=&self.residents[&batch.page];
                let instances=page.city_instances.as_ref().unwrap()[batch.module].as_ref().unwrap();
                pass.set_bind_group(1,&self.city_bindings,&[(slot*std::mem::size_of::<CityBatchUniform>()) as u32]);
                pass.set_vertex_buffer(0,kit.vertices.slice(..));
                pass.set_vertex_buffer(1,instances.slice(..));
                pass.set_index_buffer(kit.indices.slice(..),wgpu::IndexFormat::Uint32);
                for rows in batch.instances.iter().take_while(|rows|!rows.is_empty()) {
                    pass.draw_indexed(0..kit.count,0,rows.clone());
                }
            }
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
fn material_texture(device:&wgpu::Device,queue:&wgpu::Queue,art:Raster)->wgpu::TextureView {
    let [width,height]=art.size;
    let levels=width.min(height).ilog2()+1;
    let texture=create_texture_mips(device,[width,height,1],wgpu::TextureFormat::Rgba8Unorm,levels);
    let mut pixels=art.pixels;
    for level in 0..levels {
        let [w,h]=[width>>level,height>>level];
        write_texture_mip(queue,&texture,[w,h,1],4,&pixels,level);
        if level+1<levels {pixels=downsample_rgba(&pixels,w,h);}
    }
    texture.create_view(&Default::default())
}

fn surface_materials(device:&wgpu::Device,queue:&wgpu::Queue)->io::Result<(wgpu::TextureView,u64)> {
    const LAYERS:u32=12;
    let art=crate::decode_rgba(&include_bytes!("surface-materials.png")[..])?;
    let [side,height]=art.size;
    if !side.is_power_of_two() || height!=side*LAYERS {
        return Err(io::Error::other("Invalid WWO surface material layers"));
    }
    let levels=side.ilog2()+1;
    let texture=create_texture_mips(device,[side,side,LAYERS],wgpu::TextureFormat::Rgba8Unorm,levels);
    let mut pixels=art.pixels;
    let mut bytes=0;
    for level in 0..levels {
        let width=side>>level;
        bytes+=u64::from(width).pow(2)*u64::from(LAYERS)*4;
        write_texture_mip(queue,&texture,[width,width,LAYERS],4,&pixels,level);
        if level+1<levels {
            // Filter each material independently so the smallest mip cannot mix layers.
            pixels=pixels.chunks_exact((width*width*4) as usize)
                .flat_map(|layer|downsample_rgba(layer,width,width)).collect();
        }
    }
    Ok((texture.create_view(&wgpu::TextureViewDescriptor{dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()}),bytes))
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

const FRAME_TIMESTAMP_FEATURES: wgpu::Features = wgpu::Features::TIMESTAMP_QUERY
    .union(wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS);

struct TimestampSlot {
    buffer: wgpu::Buffer,
    pending: Option<(usize, std::sync::mpsc::Receiver<Result<(), wgpu::BufferAsyncError>>)>,
}

struct FrameTimer {
    queries: wgpu::QuerySet,
    resolved: wgpu::Buffer,
    slots: Vec<TimestampSlot>,
    query_count: u32,
    samples: FrameGpuTiming,
}

#[derive(Default)]
pub struct FrameGpuTiming {
    pub frames: Vec<(usize, f64)>,
    // Water projection, base scene, vegetation, overlays, models, HUD.
    pub stages: Option<Vec<(usize, [f64; 6])>>,
}

impl FrameTimer {
    fn new(device: &wgpu::Device, stages: bool) -> Self {
        let query_count = if stages { 7 } else { 2 };
        let buffer = |usage| device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Game frame timestamps"), size: u64::from(query_count) * 8,
            usage, mapped_at_creation: false,
        });
        Self {
            queries: device.create_query_set(&wgpu::QuerySetDescriptor {
                label: Some("Game frame timestamps"), ty: wgpu::QueryType::Timestamp, count: query_count,
            }),
            resolved: buffer(wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC),
            slots: (0..8).map(|_| TimestampSlot {
                buffer: buffer(wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST),
                pending: None,
            }).collect(),
            query_count,
            samples: FrameGpuTiming { frames: Vec::new(), stages: stages.then(Vec::new) },
        }
    }

    fn collect(&mut self, device: &wgpu::Device, queue: &wgpu::Queue, final_read: bool) {
        let _ = device.poll(if final_read { wgpu::Maintain::Wait } else { wgpu::Maintain::Poll });
        for slot in &mut self.slots {
            let Some((frame, ready)) = &slot.pending else { continue; };
            match ready.try_recv() {
                Ok(Ok(())) => {
                    let values = slot.buffer.slice(..).get_mapped_range();
                    let timestamp = |index: usize| {
                        u64::from_le_bytes(values[index * 8..(index + 1) * 8].try_into().unwrap())
                    };
                    let period_ms = f64::from(queue.get_timestamp_period()) / 1_000_000.;
                    let elapsed = |first, last| timestamp(last).saturating_sub(timestamp(first)) as f64 * period_ms;
                    self.samples.frames.push((*frame, elapsed(0, self.query_count as usize - 1)));
                    if let Some(stages) = &mut self.samples.stages {
                        stages.push((*frame, std::array::from_fn(|index| elapsed(index, index + 1))));
                    }
                    drop(values);
                    slot.buffer.unmap();
                    slot.pending = None;
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => {}
                _ => slot.pending = None,
            }
        }
    }
}

impl Renderer {
    pub fn start_frame_timing(&mut self, stages: bool) {
        self.frame_timer = self.device.features().contains(FRAME_TIMESTAMP_FEATURES)
            .then(|| FrameTimer::new(&self.device, stages));
    }

    pub fn finish_frame_timing(&mut self) -> Option<FrameGpuTiming> {
        let mut timer = self.frame_timer.take()?;
        timer.collect(&self.device, &self.queue, true);
        Some(timer.samples)
    }

    pub fn water_upload(&self) -> Option<crate::hydrology::WaterUpload> {
        self.water_pages.as_ref().map(|pages| pages.upload)
    }

    pub(crate) fn show_prologue_scene(&mut self, index: usize) -> std::io::Result<()> {
        if self.prologue_scene == Some(index) { return Ok(()); }
        let raster = crate::prologue_ui::scene_raster(index)?;
        let [width, height] = raster.size;
        if raster.size != crate::prologue_ui::SCENE_SIZE {
            return Err(std::io::Error::other("invalid opening scene size"));
        }
        write_texture(&self.queue, &self.prologue_texture, [width, height, 1], 4, &raster.pixels);
        self.prologue_scene = Some(index);
        Ok(())
    }

    pub async fn new(window:Arc<Window>, atlas:Raster, flags:Raster, hud:[Raster;5], globe_art:[Raster;2], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, detail:Option<terrain_detail::Catalogue>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>, observe:bool)->Result<Self,String> {
        let size=window.inner_size().into();
        Self::with_target(Some(window),size,atlas,flags,hud,globe_art,layout_bytes,natural,None,detail,events,observe).await
    }

    pub async fn new_offscreen(size:[u32;2], atlas:Raster, flags:Raster, hud:[Raster;5], globe_art:[Raster;2], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, close:Option<CloseSample>, detail:Option<terrain_detail::Catalogue>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>)->Result<Self,String> {
        Self::with_target(None,size,atlas,flags,hud,globe_art,layout_bytes,natural,close,detail,events,false).await
    }

    async fn with_target(window:Option<Arc<Window>>, size:[u32;2], atlas:Raster, flags:Raster, hud:[Raster;5], globe_art:[Raster;2], layout_bytes:&[u8], natural:Option<(terrain::Catalogue,winit::event_loop::EventLoopProxy<crate::HostEvent>)>, close:Option<CloseSample>, detail:Option<terrain_detail::Catalogue>, events:winit::event_loop::EventLoopProxy<crate::HostEvent>, observe:bool)->Result<Self,String> {
        let instance=wgpu::Instance::new(&wgpu::InstanceDescriptor {backends:wgpu::Backends::VULKAN,..Default::default()});
        let surface=window.map(|window|instance.create_surface(window)).transpose().map_err(|e|e.to_string())?;
        let adapter=instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference:wgpu::PowerPreference::HighPerformance,compatible_surface:surface.as_ref(),force_fallback_adapter:false
        }).await.ok_or(if surface.is_some(){"A Vulkan adapter with window presentation is required"}else{"A Vulkan adapter is required"})?;
        let info=adapter.get_info();
        let mut features=if natural.is_some() {wgpu::Features::TEXTURE_COMPRESSION_BC}else{wgpu::Features::empty()};
        if !adapter.features().contains(features) {
            return Err(format!("Vulkan 显卡 {} 缺少 BC7 纹理支持。", info.name));
        }
        if observe {
            features |= adapter.features() & (wgpu::Features::TIMESTAMP_QUERY|wgpu::Features::PIPELINE_STATISTICS_QUERY);
        }
        if observe && adapter.features().contains(FRAME_TIMESTAMP_FEATURES) {
            features |= FRAME_TIMESTAMP_FEATURES;
        }
        let (device,queue)=adapter.request_device(&wgpu::DeviceDescriptor {
            label:Some("WWO strategic map host"),required_features:features,
            required_limits:wgpu::Limits {max_texture_dimension_2d:4096,
                max_sampled_textures_per_shader_stage:16,
                ..wgpu::Limits::downlevel_defaults()},
            memory_hints:wgpu::MemoryHints::MemoryUsage
        },None).await.map_err(|e|format!("无法初始化 Vulkan 显卡 {} · {e}", info.name))?;
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
            wgpu::BindGroupLayoutEntry{visibility:compute_fragment,..sampler_entry(1)},sampler_entry(2),uniform(3,fragment),
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
        let palette=device.create_buffer(&wgpu::BufferDescriptor{
            label:Some("Map palette"),size:256*2*4,usage:wgpu::BufferUsages::UNIFORM|wgpu::BufferUsages::COPY_DST,mapped_at_creation:false,
        });
        let scenario_size=if layout_bytes.is_empty(){[1,1,2]}else{[256,256,2]};
        let scenario=create_texture(&device,scenario_size,wgpu::TextureFormat::Rgba8Unorm);
        write_texture(&queue,&scenario,scenario_size,4,if layout_bytes.is_empty(){&[0;8]}else{layout_bytes});
        let scenario=scenario.create_view(&wgpu::TextureViewDescriptor{dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()});
        let flag_poses=create_texture(&device,[15,256,1],wgpu::TextureFormat::Rgba32Float);
        let flag_pose_view=flag_poses.create_view(&Default::default());
        let flag_texture=create_texture(&device,[flags.size[0],flags.size[1],1],wgpu::TextureFormat::Rgba8Unorm);
        write_texture(&queue,&flag_texture,[flags.size[0],flags.size[1],1],4,&flags.pixels);
        let flags=flag_texture.create_view(&Default::default());
        let [chart,ocean]=globe_art;
        let [w,h]=chart.size;
        let texture=create_texture(&device,[w,h,1],wgpu::TextureFormat::Rgba8Unorm);
        write_texture(&queue,&texture,[w,h,1],4,&chart.pixels);
        let galactic_chart=texture.create_view(&Default::default());
        let ocean_material=material_texture(&device,&queue,ocean);
        let river_source=natural.as_ref().and_then(|(catalogue,_)|catalogue.river_lines()).map(Path::to_owned);
        let water_source=natural.as_ref().and_then(|(catalogue,_)|catalogue.water_geometry()).map(Path::to_owned);
        let terrain=natural.map(|(catalogue,proxy)|Terrain::new(&device,&queue,catalogue,proxy))
            .transpose().map_err(|error|error.to_string())?;
        let [terrain_world,terrain_detail,terrain_index]=if let Some(terrain)=&terrain {
            terrain.views()
        }else{
            let empty=||create_texture(&device,[1,1,1],wgpu::TextureFormat::Rgba8Unorm)
                .create_view(&wgpu::TextureViewDescriptor{dimension:Some(wgpu::TextureViewDimension::D2Array),..Default::default()});
            [empty(),empty(),create_texture(&device,[1,1,1],wgpu::TextureFormat::R32Uint).create_view(&Default::default())]
        };
        let materials=surface_materials(&device,&queue).map_err(|error|error.to_string())?;
        let mut surface=GroundSurface::new(&device,materials,water_source.is_some());
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
            buf_resource(3,&palette),tex_resource(4,&scenario),tex_resource(5,&flags),tex_resource(6,&flag_pose_view),
            tex_resource(7,&galactic_chart),tex_resource(8,&ocean_material),
            tex_resource(10,&terrain_world),tex_resource(11,&terrain_detail),tex_resource(12,&terrain_index)];
        let globals=bind(&device,&glob,&global_resources);
        let flag_art=bind(&device,&font_layout,&[tex_resource(0,&flags),sampler_resource(1,&linear)]);
        let [w,h]=atlas.size;
        let font=create_texture(&device,[w,h,1],wgpu::TextureFormat::Rgba8Unorm);
        write_texture(&queue,&font,[w,h,1],4,&atlas.pixels);
        let font=bind(&device,&font_layout,&[tex_resource(0,&font.create_view(&Default::default())),sampler_resource(1,&linear)]);
        let [hud_art,hud_type,menu_art,prologue_paper,opening_cloud]=hud.map(|image|{
            let [w,h]=image.size;
            let texture=create_texture(&device,[w,h,1],wgpu::TextureFormat::Rgba8Unorm);
            write_texture(&queue,&texture,[w,h,1],4,&image.pixels);
            bind(&device,&font_layout,&[tex_resource(0,&texture.create_view(&Default::default())),sampler_resource(1,&linear)])
        });
        let [width, height] = crate::prologue_ui::SCENE_SIZE;
        let prologue_texture = create_texture(&device, [width, height, 1], wgpu::TextureFormat::Rgba8Unorm);
        let prologue_art = bind(&device, &font_layout, &[
            tex_resource(0, &prologue_texture.create_view(&Default::default())), sampler_resource(1, &linear)
        ]);
        let fallback=[wgpu::TextureFormat::Rgba8Unorm,wgpu::TextureFormat::Rg8Unorm,wgpu::TextureFormat::Rg8Uint].map(|format|{
            let tex=create_texture(&device,[1,1,1],format);
            let n=format.block_copy_size(None).unwrap();
            write_texture(&queue,&tex,[1,1,1],n,&[0;4][..n as usize]);
            tex.create_view(&Default::default())
        });
        let globe_shader=map_shader(&device,include_str!("globe.wgsl"),include_str!("landscape.wgsl"));
        if water_pages.is_some() {surface.water_raster=Some(GroundSurface::create_water_raster(&device,&globe_shader,&view));}
        let hud_shader=device.create_shader_module(wgpu::include_wgsl!("hud.wgsl"));
        let mesh_layout=[screen_vertex_layout()];
        let pipeline=|groups:&[&wgpu::BindGroupLayout],module:&wgpu::ShaderModule,v,f,buffers:&[wgpu::VertexBufferLayout]| {
            render_pipeline(&device,format,groups,module,v,f,buffers)
        };
        let map_groups=[&glob,&pages,&close_layout,&surface.layout];
        let globe=pipeline(&map_groups,&globe_shader,"triangle","map",&[]);
        let roads=pipeline(&map_groups,&globe_shader,"triangle","map_roads",&[]);
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
        let models=ModelLayer::new(&device,format,&surface,events);
        Ok(Self{target,device,queue,gpu:format!("{} {:?}",info.name,info.backend),
                frame_timer:None,frame_acquire_ms:0.,view,globals,pages,palette,flag_poses,fallback,
                globe,roads,terrain,rivers,water_pages,close_extent,close_layout,close_group,detail:detail.map(terrain_detail::Stream::new),
                solid,text,flag,loading,history_light,clock_gears,clock_face,font,flag_art,hud_art,hud_type,menu_art,
                prologue_art,prologue_texture,prologue_scene:None,prologue_paper,opening_cloud,
                menu_layout:font_layout,menu_sampler:linear,instrument,instrument_view,screen,screen_size,meshes,models,
                battle:None,landscape:None,map_layout:glob,landscape_shader:globe_shader,surface,transport_network:None,
                transport_economy:None,transport_vehicles:None})
    }

    pub fn reload_map_shader(&mut self, root: &Path) -> io::Result<bool> {
        let read = |name| match std::fs::read_to_string(root.join(name)) {
            Ok(value) => Ok(Some(value)),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error),
        };
        let globe=read("globe.wgsl")?;
        let scenery=read("landscape.wgsl")?;
        if globe.is_none() && scenery.is_none() {return Ok(false);}
        let format=match &self.target {
            RenderTarget::Window(_, config)=>config.format,
            RenderTarget::Offscreen(texture)=>texture.format(),
        };
        let device=&self.device;
        let groups=[&self.map_layout,&self.pages,&self.close_layout,&self.surface.layout];
        device.push_error_scope(wgpu::ErrorFilter::Validation);
        let shader=map_shader(device,globe.as_deref().unwrap_or(include_str!("globe.wgsl")),
            scenery.as_deref().unwrap_or(include_str!("landscape.wgsl")));
        let map=render_pipeline(device,format,&groups,&shader,"triangle","map",&[]);
        let roads=render_pipeline(device,format,&groups,&shader,"triangle","map_roads",&[]);
        let rivers=self.rivers.as_ref().map(|_|render_pipeline(device,format,&groups,&shader,
            "river_stroke","river_ink",&[screen_vertex_layout()]));
        let water=self.water_pages.as_ref().map(|_|GroundSurface::create_water_raster(device,&shader,&self.view));
        let landscape=Landscape::new(device,format,groups,&shader);
        if let Some(error)=pollster::block_on(device.pop_error_scope()) {
            return Err(io::Error::other(format!("{error}")));
        }
        self.globe=map;
        self.roads=roads;
        if let (Some(layer),Some(pipeline))=(&mut self.rivers,rivers) {layer.pipeline=pipeline;}
        self.surface.water_raster=water;
        self.landscape_shader=shader;
        self.landscape=Some(landscape);
        Ok(true)
    }

    pub fn reload_land_texture(&mut self, root: &Path) -> io::Result<bool> {
        let path=root.join("land-material.png");
        let bytes=match std::fs::read(path) {
            Ok(bytes)=>bytes,
            Err(error) if error.kind()==io::ErrorKind::NotFound=>return Ok(false),
            Err(error)=>return Err(error),
        };
        let image=crate::decode_rgba(bytes.as_slice())?;
        let limit=self.device.limits().max_texture_dimension_2d;
        if image.size.into_iter().any(|dimension| dimension==0||dimension>limit) {
            return Err(io::Error::other(format!("Landscape texture dimensions exceed {limit} pixels")));
        }
        let art=material_texture(&self.device,&self.queue,image);
        let surface=&mut self.surface;
        surface.group=GroundSurface::bind(&self.device,&surface.layout,&surface.repeat,&art,&surface.landscape,
            &surface.materials,&surface.water,&surface.water_pixels,&surface.city_water);
        surface.art=art;
        surface.custom_art=true;
        Ok(true)
    }

    pub fn replace_menu_painting(&mut self,image:Raster) {
        let [w,h]=image.size;
        let texture=create_texture(&self.device,[w,h,1],wgpu::TextureFormat::Rgba8Unorm);
        write_texture(&self.queue,&texture,[w,h,1],4,&image.pixels);
        self.menu_art=bind(&self.device,&self.menu_layout,&[
            tex_resource(0,&texture.create_view(&Default::default())),sampler_resource(1,&self.menu_sampler),
        ]);
    }

    pub fn reload_menu_painting(&mut self,image:Raster) -> io::Result<()> {
        let limit=self.device.limits().max_texture_dimension_2d;
        if image.size.into_iter().any(|dimension|dimension==0||dimension>limit) {
            return Err(io::Error::other(format!("Theme texture dimensions exceed {limit} pixels")));
        }
        self.replace_menu_painting(image);
        Ok(())
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

    pub fn replace_city_models(&mut self, bytes:Vec<u8>) {
        let layer=&mut self.models;
        layer.city_revision+=1;
        layer.city_override=Some(bytes.into());
        let keys = layer.residents.keys().filter(|key| key.is_city()).copied().collect::<Vec<_>>();
        let evicted = keys.into_iter().filter_map(|key| layer.residents.remove(&key)).collect();
        layer.retire_city_gpu(&self.queue, evicted, 0);
        layer.city_meshes.clear();
        layer.pending.retain(|key|!key.is_city());
        layer.failed.retain(|key|!key.is_city());
    }

    pub fn model_ready(&mut self, revision:u64,key: ModelKey, mesh: io::Result<ModelMesh>) -> io::Result<()> {
        if key.is_city() && self.models.city_revision!=revision {return Ok(());}
        self.models.complete(&self.device, key, mesh)
    }

    pub fn resident_models(&self) -> Vec<(&'static str, &'static str)> {
        let mut models:Vec<_>=self.models.residents.iter().filter(|(_,model)| model.mesh_ready())
            .map(|(key,_)|(key.model(),key.lod())).collect();
        models.sort_unstable();
        models
    }

    pub fn model_instances(&self) -> Vec<(&'static str, usize)> {
        let mut counts:HashMap<_,_>=self.models.residents.iter()
            .map(|(key,model)|(*key,model.transforms.len())).collect();
        for batch in &self.models.city_batches {
            *counts.entry(batch.kit).or_default()+=batch.instances.iter().map(|rows|rows.len()).sum::<usize>();
        }
        let mut models:Vec<_>=counts.into_iter().filter(|&(_,count)|count>0)
            .map(|(key,count)|(key.model(),count)).collect();
        models.sort_unstable();
        models
    }

    pub fn has_model(&self, model:&VisibleModel) -> bool {
        let [low,high]=self.models.lod_range(model);
        low<high && self.models.residents.get(&model.key).is_some_and(ResidentModel::mesh_ready)
    }

    pub(crate) fn maintain_city_gpu(&mut self, now: Instant) -> bool {
        self.models.maintain_city_gpu(&self.device, &self.queue, now);
        self.models.city_upload_due || self.surface.road_store.uploading
    }

    pub(crate) fn city_gpu_status(&self) -> serde_json::Value {
        let (resident, submitted) = self.models.city_usage();
        let roads=&self.surface.road_store;
        serde_json::json!({
            "fixed_bytes": self.models.city_fixed_bytes, "resident_bytes":resident,
            "submitted_and_retiring_bytes":submitted,
            "page_mesh_ready":self.models.residents.iter()
                .filter(|(key,model)| key.city_page_id().is_some() && model.mesh_ready()).count(),
            "detail_buffers_ready":self.models.residents.iter()
                .filter(|(key,model)| key.city_page_id().is_some() && model.detail_ready()).count(),
            "upload_pending":self.models.city_upload_due || roads.uploading,
            "road_slot_capacity":roads.capacity,
            "road_reserved_bytes":roads.capacity*crate::city_roads::PAGE_BYTES,
            "road_active":roads.active().map(|slot|serde_json::json!({"revision":slot.key.0,"index":slot.key.1,
                "payload_bytes":slot.bytes,"water":slot.water,"ground":slot.ground,
                "active_coverage":slot.road_coverage})).collect::<Vec<_>>(),
            "decoded_kit_cpu_bytes":self.models.city_meshes.values().map(|mesh| {
                mesh.vertices.capacity()*std::mem::size_of::<ModelVertex>()
                    + mesh.indices.capacity()*std::mem::size_of::<u32>()
            }).sum::<usize>() + self.models.city_override.as_ref().map_or(0, |bytes| bytes.len()),
        })
    }

    pub(crate) fn city_page_gpu(&self, revision:u64, index:usize) -> &'static str {
        match self.models.residents.get(&ModelKey::city_page(revision,index)) {
            Some(page) if page.detail_ready() => "detail_buffers",
            Some(page) if page.mesh_ready() => "overview",
            Some(_) => "uploading",
            None => "absent",
        }
    }
    pub fn update_terrain(&mut self,camera:&Camera,size:[u32;2],now:Instant)->io::Result<()> {
        if let Some(terrain)=&mut self.terrain {
            terrain.update(&self.queue,camera,size,now);
            if let Some(water)=&mut self.water_pages {
                water.update(&self.queue,&self.surface.water,camera,size,now);
            }
            if terrain.view_demand()>=6 && !self.surface.loaded {
                let landscape=terrain.enable_landscape(&self.device);
                self.surface.load(&self.device,&self.queue,landscape)?;
            }
        }
        Ok(())
    }

    fn prepare_landscape(&mut self,camera:&Camera,size:[u32;2],enabled:bool,now:Instant,seconds:f32) {
        let Some(terrain)=&mut self.terrain else {return;};
        let enabled=enabled&&terrain.view_max().max(terrain.view_demand())>=6;
        if enabled && camera.mpp<1460. && terrain.landscape_cover() {
            if self.landscape.is_none() {
                let format=match &self.target {
                    RenderTarget::Window(_, config)=>config.format,
                    RenderTarget::Offscreen(texture)=>texture.format(),
                };
                self.landscape=Some(Landscape::new(&self.device,format,
                    [&self.map_layout,&self.pages,&self.close_layout,&self.surface.layout],&self.landscape_shader));
            }
        }
        if let Some(layer)=&mut self.landscape {
            layer.prepare(&self.queue,camera,size,terrain,enabled,seconds);
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

    pub fn terrain_regional_ready(&mut self,key:terrain::Key,result:io::Result<Vec<u8>>)->io::Result<()> {
        if let Some(terrain)=&mut self.terrain {terrain.complete_regional(&self.queue,key,result)?;}
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
            || self.landscape.as_ref().is_some_and(Landscape::needs_redraw)
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
        self.queue.write_buffer(&self.palette,0,bytes);
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
    fn prepare_transport(&mut self, overlay: Option<TransportOverlay<'_>>) -> [bool;3] {
        let Some(overlay)=overlay else {return [false;3];};
        for (draw,cache) in [(overlay.network,&mut self.transport_network),(overlay.economy,&mut self.transport_economy)] {
            if let Some((revision,mesh))=draw {
                if cache.as_ref().is_none_or(|(previous,_)|*previous!=revision) {
                    let (previous,buffers)=cache.get_or_insert_with(|| {
                        (revision,MeshBuffers::new(&self.device,4096,2048))
                    });
                    buffers.upload(&self.device,&self.queue,mesh);
                    *previous=revision;
                }
            }
        }
        let vehicles=!overlay.vehicles.indices.is_empty();
        if vehicles {
            let buffers=self.transport_vehicles.get_or_insert_with(||MeshBuffers::new(&self.device,4096,2048));
            buffers.upload(&self.device,&self.queue,overlay.vehicles);
        }
        [overlay.network.is_some(),overlay.economy.is_some(),vehicles]
    }

    pub fn render(&mut self, view:&View,base:&Page,pages:&[(&Page,&Tile,[u32;4],f32)],
                  meshes:&crate::ui::Layers,fade:Option<&crate::ui::Layers>,seconds:f32,show_map:bool,capture:Option<&Path>,
                  (models,roads):(&[VisibleModel],&[crate::city_models::ReadyRoad<'_>]),
                  transport:Option<TransportOverlay<'_>>,
                  (camera,landscape_enabled,now):(&Camera,bool,Instant),
                  battle:Option<BattleFrame<'_>>,timing_frame:Option<usize>)->io::Result<Option<io::Result<()>>> {
        let acquire_start = timing_frame.map(|_| Instant::now());
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
        if let Some(start) = acquire_start {
            self.frame_acquire_ms = start.elapsed().as_secs_f64() * 1000.;
        }
        let size=match &self.target {
            RenderTarget::Window(_,config)=>[config.width,config.height],
            RenderTarget::Offscreen(texture)=>[texture.width(),texture.height()],
        };
        if battle.is_none() {self.prepare_landscape(camera,size,landscape_enabled,now,seconds);}
        let [draw_network,draw_economy,draw_vehicles]=self.prepare_transport(transport.filter(|_|show_map && battle.is_none() && view.road_layer[0]==0));
        let (texture,copy_src)=match &self.target {
            RenderTarget::Window(_,config)=>(&frame.as_ref().unwrap().texture,config.usage.contains(wgpu::TextureUsages::COPY_SRC)),
            RenderTarget::Offscreen(texture)=>(texture,true),
        };
        let [w,h]=[texture.width(),texture.height()];
        let format=texture.format();
        if battle.is_none() {
            let (resident_bytes, submitted_bytes)=self.models.city_usage();
            let mut uploads=CityUploads { started:Instant::now(),written:0,remaining:CityUploads::FRAME_LIMIT,
                used:self.models.city_fixed_bytes+resident_bytes+submitted_bytes+self.models.city_uniforms.size() };
            self.surface.road_store.update(&self.queue,&self.surface.city_water,roads,&mut uploads);
            self.models.prepare(&self.device,&self.queue,[w,h],models,camera.mpp as f32,&mut uploads);
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
        let gpu_slot = timing_frame.and_then(|frame| {
            let timer = self.frame_timer.as_mut()?;
            timer.collect(&self.device, &self.queue, false);
            let slot = timer.slots.iter().position(|slot| slot.pending.is_none())?;
            encoder.write_timestamp(&timer.queries, 0);
            Some((frame, slot))
        });
        let stage_queries = gpu_slot.and(self.frame_timer.as_ref())
            .filter(|timer| timer.query_count > 2).map(|timer| &timer.queries);
        let mark_stage = |encoder: &mut wgpu::CommandEncoder, index| {
            if let Some(queries) = stage_queries { encoder.write_timestamp(queries, index); }
        };
        if show_map {
            if let Some(water)=&self.water_pages {
                self.surface.project_water(&self.device,&mut encoder,[w,h],view,water.revision());
            }
        }
        mark_stage(&mut encoder, 1);
        if let Some(battle) = battle {
            let scene = self.battle.as_mut().ok_or_else(|| io::Error::other("battle renderer not initialized"))?;
            scene.draw(&self.device, &self.queue, &mut encoder, &image, size, battle.view, battle.state, battle.terrain);
            for stage in 2..=5 { mark_stage(&mut encoder, stage); }
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
                for (page,_,[x,y,w,h],_) in pages.iter().filter(|(_,tile,_,_)|!tile.city_ink_only) {
                    pass.set_scissor_rect(*x,*y,*w,*h);
                    pass.set_bind_group(1,&page.group,&[]);
                    pass.draw(0..3,0..1);
                }
                if let Some(layer)=self.rivers.as_ref().filter(|layer|layer.rivers.as_ref().is_some_and(Rivers::visible)) {
                    pass.set_scissor_rect(0,0,w,h);
                    pass.set_pipeline(&layer.pipeline);
                    layer.mesh.draw(&mut pass);
                }
            }
            drop(pass);
            mark_stage(&mut encoder, 2);
            if let Some(layer)=&mut self.landscape {
                layer.draw(&self.device,&mut encoder,&image,[&self.globals,&base.group,&self.close_group,&self.surface.group],[w,h]);
            }
            mark_stage(&mut encoder, 3);
            let draw_city=show_map&&pages.iter().any(|(_,tile,_,_)|tile.city_ink_only);
            let road_area=if show_map && camera.mpp<300. && view.road_layer[0]<2 {
                self.surface.city_roads.vector_bounds().chain(self.surface.road_store.active().map(|slot|slot.bounds))
                    .filter_map(|bounds| road_scissor(camera,size,bounds))
                    .reduce(|[ax,ay,aw,ah],[bx,by,bw,bh]| {
                        let x=ax.min(bx);
                        let y=ay.min(by);
                        [x,y,(ax+aw).max(bx+bw)-x,(ay+ah).max(by+bh)-y]
                    })
            } else {None};
            let draw_roads=road_area.is_some();
            if draw_city||draw_roads||draw_network||draw_economy||draw_vehicles {
                let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                    label:Some("WWO map overlays"),
                    color_attachments:&[Some(wgpu::RenderPassColorAttachment {
                        view:&image,resolve_target:None,
                        ops:wgpu::Operations{load:wgpu::LoadOp::Load,store:wgpu::StoreOp::Store},
                    })],
                    depth_stencil_attachment:None,occlusion_query_set:None,timestamp_writes:None,
                });
                if draw_city {
                    pass.set_pipeline(&self.globe);
                    pass.set_bind_group(0,&self.globals,&[]);
                    pass.set_bind_group(2,&self.close_group,&[]);
                    pass.set_bind_group(3,&self.surface.group,&[]);
                    for (blocks,streets) in [(false,false),(true,false),(false,true)] {
                        for (page,_,[x,y,w,h],_) in pages.iter()
                            .filter(|(_,tile,_,_)|tile.city_ink_only && tile.city_blocks==blocks && tile.city_streets==streets) {
                            pass.set_scissor_rect(*x,*y,*w,*h);
                            pass.set_bind_group(1,&page.group,&[]);
                            pass.draw(0..3,0..1);
                        }
                    }
                    pass.set_scissor_rect(0,0,w,h);
                }
                if let Some([x,y,width,height])=road_area {
                    pass.set_pipeline(&self.roads);
                    pass.set_bind_group(0,&self.globals,&[]);
                    pass.set_bind_group(1,&base.group,&[]);
                    pass.set_bind_group(2,&self.close_group,&[]);
                    pass.set_bind_group(3,&self.surface.group,&[]);
                    pass.set_scissor_rect(x,y,width,height);
                    pass.draw(0..3,0..1);
                    pass.set_scissor_rect(0,0,w,h);
                }
                pass.set_pipeline(&self.solid);
                pass.set_bind_group(0,&self.screen,&[]);
                if draw_network {self.transport_network.as_ref().unwrap().1.draw(&mut pass);}
                if draw_economy {self.transport_economy.as_ref().unwrap().1.draw(&mut pass);}
                if draw_vehicles {self.transport_vehicles.as_ref().unwrap().draw(&mut pass);}
            }
            mark_stage(&mut encoder, 4);
            self.models.draw(&mut encoder, &image);
            mark_stage(&mut encoder, 5);
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
                    Ink::Text|Ink::Flag|Ink::HudArtGlass|Ink::HudArt|Ink::HudText|Ink::MenuArt|Ink::PrologueArt|Ink::ProloguePaper|Ink::OpeningCloud=>{
                        pass.set_pipeline(if matches!(ink,Ink::Flag){&self.flag}else if matches!(ink,Ink::HudArtGlass){&self.clock_face}else{&self.text});
                        let texture=match ink{Ink::Flag=>&self.flag_art,Ink::HudArt|Ink::HudArtGlass=>&self.hud_art,Ink::HudText=>&self.hud_type,Ink::MenuArt=>&self.menu_art,Ink::PrologueArt=>&self.prologue_art,Ink::ProloguePaper=>&self.prologue_paper,Ink::OpeningCloud=>&self.opening_cloud,_=>&self.font};
                        pass.set_bind_group(1,texture,&[]);
                    }
                }
                pass.set_bind_group(0,&self.screen,&[]);
                draw.draw(&mut pass);
            }
        }
        let padded=(w*4).div_ceil(256)*256;
        if let Some((_, slot)) = gpu_slot {
            let timer = self.frame_timer.as_ref().unwrap();
            encoder.write_timestamp(&timer.queries, timer.query_count - 1);
            encoder.resolve_query_set(&timer.queries, 0..timer.query_count, &timer.resolved, 0);
            encoder.copy_buffer_to_buffer(&timer.resolved, 0, &timer.slots[slot].buffer, 0, u64::from(timer.query_count) * 8);
        }
        let readback=capture.filter(|_|copy_src).map(|_|{
            let data=self.device.create_buffer(&wgpu::BufferDescriptor {label:Some("WWO capture"),size:u64::from(padded)*u64::from(h),
                usage:wgpu::BufferUsages::COPY_DST|wgpu::BufferUsages::MAP_READ,mapped_at_creation:false});
            encoder.copy_texture_to_buffer(wgpu::TexelCopyTextureInfo {texture,mip_level:0,origin:wgpu::Origin3d::ZERO,aspect:wgpu::TextureAspect::All},
                wgpu::TexelCopyBufferInfo {buffer:&data,layout:wgpu::TexelCopyBufferLayout{offset:0,bytes_per_row:Some(padded),rows_per_image:Some(h)}},
                extent([w,h,1]));
            data
        });
        self.queue.submit([encoder.finish()]);
        let city_staging = std::mem::take(&mut self.models.city_transfer_bytes);
        self.models.retire_city_gpu(&self.queue, Vec::new(), city_staging);
        if let Some((frame, slot)) = gpu_slot {
            let slot = &mut self.frame_timer.as_mut().unwrap().slots[slot];
            let (send, ready) = std::sync::mpsc::channel();
            slot.buffer.slice(..).map_async(wgpu::MapMode::Read, move |result| {
                let _ = send.send(result);
            });
            slot.pending = Some((frame, ready));
        }
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
