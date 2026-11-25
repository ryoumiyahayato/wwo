use crate::{
    camera::{frame, Camera},
    landscape_models::{self, Vertex},
    terrain::{Key, Terrain},
};
use std::{collections::{HashMap, HashSet}, f64::consts::PI};
use wgpu::util::DeviceExt;

const KINDS: u64 = 4;
const MODEL_LIMIT_MPP: f64 = 28.;
const CHUNK_SIDE: i32 = 16;
const LATITUDE_CELLS: i32 = 98_304;
const CAPACITY: u64 = 65_536;
const INSTANCE_BYTES: u64 = 20;
const DRAW_BYTES: u64 = 20;
const MAX_CHUNKS: usize = 1_728;
const CACHE_CHUNKS: usize = 2_560;
const BUILDS_PER_FRAME: usize = 32;
const KEEP_SITES: u32 = 1 << 31;
const INSTANCE_FADE_SECONDS: f32 = 0.18;
// End of the individual crown blend in landscape_vertex.
const STAND_ONLY_MPP: f64 = 18.;

type Chunk = [u32; 4];

#[derive(Default)]
pub struct LandscapeCounts {
    pub draw_calls: u32,
    pub by_mesh: [u32; KINDS as usize],
    pub vertex_invocations: Option<u64>,
    pub gpu_ms: Option<f64>,
}

#[derive(Clone, Copy, PartialEq)]
struct LandscapeView {
    projection: ([[f64; 3]; 3], [f64; 2]),
    size: [u32; 2],
    mpp: f64,
    pitch: f64,
    level: u32,
}

struct CachedChunk {
    slot: u32,
    used: u64,
    revision: u32,
    pages: Vec<bool>,
}

pub struct Landscape {
    build: wgpu::ComputePipeline,
    collect: wgpu::ComputePipeline,
    limit: wgpu::ComputePipeline,
    render: wgpu::RenderPipeline,
    bindings: wgpu::BindGroup,
    chunks: wgpu::Buffer,
    draws: wgpu::Buffer,
    vertices: wgpu::Buffer,
    indices: wgpu::Buffer,
    crown_indices: [u32; 3],
    stand_indices: u32,
    stand_only: bool,
    instances: wgpu::Buffer,
    depth: Option<([u32; 2], wgpu::TextureView)>,
    previous: Option<LandscapeView>,
    page_revision: u32,
    requested: Vec<Chunk>,
    active: Vec<Chunk>,
    cache: HashMap<Chunk, CachedChunk>,
    free: Vec<u32>,
    frame: u64,
    build_count: u32,
    built_total: u64,
    collect_needed: bool,
    pending: bool,
    fade_until: f32,
    awaiting_pages: HashSet<Key>,
    timestamps: Option<wgpu::QuerySet>,
    statistics: Option<wgpu::QuerySet>,
    profiled: bool,
}

impl Landscape {
    pub fn new(
        device: &wgpu::Device,
        format: wgpu::TextureFormat,
        view_layouts: [&wgpu::BindGroupLayout; 4],
        shader: &wgpu::ShaderModule,
    ) -> Self {
        use wgpu::BufferUsages as Usage;
        let (meshes, stand_indices) = landscape_models::meshes();
        let query = |feature, ty, count| device.features().contains(feature).then(|| {
            device.create_query_set(&wgpu::QuerySetDescriptor { label: Some("Landscape observation"), ty, count })
        });
        let timestamps = query(wgpu::Features::TIMESTAMP_QUERY, wgpu::QueryType::Timestamp, 2);
        let statistics = query(wgpu::Features::PIPELINE_STATISTICS_QUERY,
            wgpu::QueryType::PipelineStatistics(wgpu::PipelineStatisticsTypes::VERTEX_SHADER_INVOCATIONS), 1);
        let mut first_index = 0;
        let mut base_vertex = 0;
        let mesh_commands = meshes.each_ref().map(|mesh| {
            let count = mesh.indices.len() as u32;
            let command = [count, 0, first_index, base_vertex, 0];
            first_index += count;
            base_vertex += mesh.vertices.len() as u32;
            command
        });
        let commands = [mesh_commands[0], mesh_commands[1], mesh_commands[2], mesh_commands[0]];
        let crown_indices = [commands[0][0], commands[1][0], commands[3][0]];
        let vertices = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Landscape shared meshes"),
            contents: bytemuck::cast_slice(&meshes.iter().flat_map(|mesh|mesh.vertices.iter().copied()).collect::<Vec<_>>()),
            usage: Usage::VERTEX,
        });
        let indices = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Landscape shared mesh indices"),
            contents: bytemuck::cast_slice(&meshes.into_iter().flat_map(|mesh|mesh.indices).collect::<Vec<_>>()),
            usage: Usage::INDEX,
        });
        let draws = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Landscape draw commands"),
            contents: bytemuck::cast_slice(&commands),
            usage: Usage::INDIRECT | Usage::STORAGE | Usage::COPY_DST | Usage::COPY_SRC,
        });
        let buffer = |label, size, usage| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size,
                usage,
                mapped_at_creation: false,
            })
        };
        let chunks = buffer(
            "Visible and dirty landscape chunks",
            (size_of::<Chunk>() * (MAX_CHUNKS + BUILDS_PER_FRAME)) as u64,
            Usage::STORAGE | Usage::COPY_DST,
        );
        let instances = buffer(
            "Visible landscape instances",
            KINDS * CAPACITY * INSTANCE_BYTES,
            Usage::STORAGE | Usage::VERTEX,
        );
        let cache = buffer(
            "Landscape chunk cache",
            CACHE_CHUNKS as u64 * (CHUNK_SIDE * CHUNK_SIDE) as u64 * INSTANCE_BYTES,
            Usage::STORAGE,
        );
        let storage = [true, false, false, false].map(|read_only| wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Storage { read_only },
            has_dynamic_offset: false,
            min_binding_size: None,
        });
        let entries = storage
            .into_iter()
            .enumerate()
            .map(|(i, ty)| wgpu::BindGroupLayoutEntry {
                binding: 5 + i as u32,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty,
                count: None,
            })
            .collect::<Vec<_>>();
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Z7 landscape generation"),
            entries: &entries,
        });
        let bindings = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Z7 landscape generation"),
            layout: &layout,
            entries: &[&chunks, &instances, &draws, &cache]
                .into_iter()
                .enumerate()
                .map(|(i, buffer)| wgpu::BindGroupEntry {
                    binding: 5 + i as u32,
                    resource: buffer.as_entire_binding(),
                })
                .collect::<Vec<_>>(),
        });
        let compute_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Z7 landscape placement"),
            bind_group_layouts: &[view_layouts[0], &layout, view_layouts[2], view_layouts[3]],
            push_constant_ranges: &[],
        });
        let compute = |entry| {
            device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
                label: Some(entry),
                layout: Some(&compute_layout),
                module: shader,
                entry_point: Some(entry),
                compilation_options: Default::default(),
                cache: None,
            })
        };
        let build = compute("landscape_build");
        let collect = compute("landscape_collect");
        let limit = compute("landscape_limit_draws");
        let render_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Z7 landscape draw"),
            bind_group_layouts: &view_layouts,
            push_constant_ranges: &[],
        });
        let render = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Z7 landscape meshes"), layout: Some(&render_layout),
            vertex: wgpu::VertexState {
                module: shader, entry_point: Some("landscape_vertex"), compilation_options: Default::default(),
                buffers: &[
                    wgpu::VertexBufferLayout {
                        array_stride: std::mem::size_of::<Vertex>() as u64, step_mode: wgpu::VertexStepMode::Vertex,
                        attributes: &wgpu::vertex_attr_array![0=>Float32x3,1=>Float32x3,2=>Float32,3=>Float32,4=>Float32],
                    },
                    wgpu::VertexBufferLayout {
                        array_stride: INSTANCE_BYTES, step_mode: wgpu::VertexStepMode::Instance,
                        attributes: &wgpu::vertex_attr_array![5=>Uint32x4,6=>Float32],
                    },
                ],
            },
            fragment: Some(wgpu::FragmentState {
                module: shader, entry_point: Some("landscape_fragment"), compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format, blend: Some(wgpu::BlendState::ALPHA_BLENDING), write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState { cull_mode: Some(wgpu::Face::Back), ..Default::default() },
            depth_stencil: Some(wgpu::DepthStencilState {
                format: wgpu::TextureFormat::Depth32Float, depth_write_enabled: true,
                depth_compare: wgpu::CompareFunction::Less, stencil: Default::default(), bias: Default::default(),
            }),
            multisample: Default::default(), multiview: None, cache: None,
        });
        Self {
            build,
            collect,
            limit,
            render,
            bindings,
            chunks,
            draws,
            vertices,
            indices,
            crown_indices,
            stand_indices,
            stand_only: false,
            instances,
            depth: None,
            previous: None,
            page_revision: 0,
            requested: Vec::new(),
            active: Vec::new(),
            cache: HashMap::new(),
            free: (0..CACHE_CHUNKS as u32).rev().collect(),
            frame: 0,
            build_count: 0,
            built_total: 0,
            collect_needed: false,
            pending: false,
            fade_until: 0.,
            awaiting_pages: HashSet::new(),
            timestamps,
            statistics,
            profiled: false,
        }
    }

    pub fn prepare(
        &mut self,
        queue: &wgpu::Queue,
        camera: &Camera,
        size: [u32; 2],
        terrain: &Terrain,
        enabled: bool,
        seconds: f32,
    ) {
        let scale = (f64::from(size[0]) * f64::from(size[1]) / 2_073_600.)
            .sqrt()
            .max(1.);
        let footprint = camera.mpp * scale;
        self.awaiting_pages.clear();
        if !enabled || footprint >= MODEL_LIMIT_MPP {
            self.active.clear();
            self.requested.clear();
            self.previous = None;
            self.pending = false;
            return;
        }
        if seconds >= self.fade_until {
            self.fade_until = 0.;
        }
        let stand_only = camera.mpp >= STAND_ONLY_MPP;
        if stand_only != self.stand_only {
            for (kind, full) in [0, 1, 3].into_iter().zip(self.crown_indices) {
                let count = if stand_only { self.stand_indices } else { full };
                queue.write_buffer(&self.draws, kind * DRAW_BYTES, bytemuck::bytes_of(&count));
            }
            self.stand_only = stand_only;
        }
        let view = LandscapeView {
            projection: camera.projection(size), size, mpp: camera.mpp,
            pitch: camera.pitch(), level: terrain.view_max().max(terrain.view_demand()),
        };
        let revision = terrain.landscape_revision();
        let view_changed = self.previous != Some(view);
        if !view_changed && self.page_revision == revision && !self.pending {
            return;
        }
        self.previous = Some(view);
        self.page_revision = revision;
        if view_changed {
            self.requested.clear();
            if view.level >= 7 {
                visible_chunks(camera, size, &mut self.requested);
            }
            self.requested.truncate(MAX_CHUNKS);
        }
        self.frame += 1;
        self.pending = false;
        for chunk in &self.requested {
            if let Some(cached) = self.cache.get_mut(chunk) {cached.used = self.frame;}
        }
        let mut active = Vec::with_capacity(self.requested.len());
        let mut dirty = Vec::with_capacity(BUILDS_PER_FRAME);
        let mut pages = Vec::new();
        let mut evictable = None;
        for &chunk in &self.requested {
            let current = self.cache.get(&chunk).is_some_and(|cached|cached.revision==revision);
            let cached = self.cache.get(&chunk);
            if !current {terrain.landscape_dependencies(chunk,&mut pages);}
            if cached.is_none() && !pages.iter().any(|&(_,ready)|ready) {continue;}
            // Evicting a QPK page does not invalidate its deterministic sites.
            // Only a newly available dependency can add sites to this slot.
            let is_valid = current || cached.is_some_and(|cached|
                cached.pages.iter().zip(&pages).all(|(&built,&(_,ready))|built || !ready));
            let build = !is_valid && dirty.len() < BUILDS_PER_FRAME;
            let keep_sites = cached.is_some();
            if !is_valid && !build {
                self.awaiting_pages.extend(pages.iter().filter_map(|&(key,ready)|ready.then_some(key)));
            }
            self.pending |= !is_valid && !build;
            let slot = if let Some(cached) = self.cache.get_mut(&chunk) {
                if build {
                    for (built,&(_,ready)) in cached.pages.iter_mut().zip(&pages) {*built |= ready;}
                }
                if build || is_valid {cached.revision=revision;}
                cached.slot
            } else if build {
                let slot = self.free.pop().unwrap_or_else(|| {
                    let victims = evictable.get_or_insert_with(|| {
                        let mut entries:Vec<_> = self.cache.iter().filter(|(_,cached)|cached.used!=self.frame)
                            .map(|(&key,cached)|(cached.used,key)).collect();
                        entries.sort_unstable_by(|a,b|b.cmp(a));
                        entries
                    });
                    let (_,victim)=victims.pop().expect("landscape cache exceeds visible chunk capacity");
                    self.cache.remove(&victim).unwrap().slot
                });
                self.cache.insert(chunk,CachedChunk {
                    slot, used:self.frame, revision, pages:pages.iter().map(|&(_,ready)|ready).collect(),
                });
                slot
            } else {
                continue;
            };
            let [x,y,columns,step] = chunk;
            let command = [x,y,columns,(slot<<6)|step];
            if build {
                dirty.push([x,y,columns,command[3]|if keep_sites {KEEP_SITES}else{0}]);
            }
            active.push(command);
        }
        active.sort_unstable();
        self.build_count = dirty.len() as u32;
        self.collect_needed = active != self.active || !dirty.is_empty();
        if self.collect_needed && !active.is_empty() {
            queue.write_buffer(&self.chunks, 0, bytemuck::cast_slice(&active));
        }
        if !dirty.is_empty() {
            queue.write_buffer(&self.chunks, (size_of::<Chunk>()*MAX_CHUNKS) as u64, bytemuck::cast_slice(&dirty));
            // Keep drawing while new instances fade, including at a stationary camera.
            self.fade_until = seconds + INSTANCE_FADE_SECONDS;
        }
        self.active = active;
    }

    pub fn visible_chunks(&self) -> usize {self.active.len()}
    pub fn cached_chunks(&self) -> usize {self.cache.len()}
    pub fn built_chunks(&self) -> u64 {self.built_total}
    pub fn pending(&self) -> bool {self.pending}
    pub fn needs_redraw(&self) -> bool {self.pending || (!self.active.is_empty() && self.fade_until > 0.)}
    pub fn awaiting_pages(&self) -> &HashSet<Key> {&self.awaiting_pages}

    pub fn counts(&self, device:&wgpu::Device, queue:&wgpu::Queue) -> std::io::Result<LandscapeCounts> {
        if self.active.is_empty() {return Ok(LandscapeCounts::default());}
        let size=KINDS*DRAW_BYTES;
        let query_offset = u64::from(wgpu::QUERY_RESOLVE_BUFFER_ALIGNMENT);
        let timestamps = self.timestamps.as_ref().filter(|_| self.profiled);
        let statistics = self.statistics.as_ref().filter(|_| self.profiled);
        let data=device.create_buffer(&wgpu::BufferDescriptor {
            label:Some("Landscape draw count readback"), size:size+24,
            usage:wgpu::BufferUsages::COPY_DST|wgpu::BufferUsages::MAP_READ,
            mapped_at_creation:false,
        });
        let mut encoder=device.create_command_encoder(&Default::default());
        encoder.copy_buffer_to_buffer(&self.draws,0,&data,0,size);
        if timestamps.is_some() || statistics.is_some() {
            let queries = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("Landscape query resolve"),
                size: query_offset+8,
                usage: wgpu::BufferUsages::QUERY_RESOLVE|wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            });
            if let Some(set) = timestamps {
                encoder.resolve_query_set(set,0..2,&queries,0);
                encoder.copy_buffer_to_buffer(&queries,0,&data,size,16);
            }
            if let Some(set) = statistics {
                encoder.resolve_query_set(set,0..1,&queries,query_offset);
                encoder.copy_buffer_to_buffer(&queries,query_offset,&data,size+16,8);
            }
        }
        let submission=queue.submit([encoder.finish()]);
        let slice=data.slice(..);
        let (send,receive)=std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read,move |result| {let _=send.send(result);});
        let _=device.poll(wgpu::Maintain::WaitForSubmissionIndex(submission));
        receive.recv().map_err(std::io::Error::other)?.map_err(std::io::Error::other)?;
        let mapped=slice.get_mapped_range();
        let (draws,queries)=mapped.split_at(size as usize);
        let words:&[u32]=bytemuck::cast_slice(draws);
        let query_word=|index: usize| u64::from_ne_bytes(queries[index*8..(index+1)*8].try_into().unwrap());
        Ok(LandscapeCounts {
            draw_calls: KINDS as u32,
            by_mesh: std::array::from_fn(|kind|words[kind*(DRAW_BYTES as usize/4)+1]),
            vertex_invocations: statistics.map(|_|query_word(2)),
            gpu_ms: timestamps.map(|_|query_word(1).saturating_sub(query_word(0)) as f64
                * f64::from(queue.get_timestamp_period()) / 1_000_000.),
        })
    }

    pub fn draw(
        &mut self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        image: &wgpu::TextureView,
        view_groups: [&wgpu::BindGroup; 4],
        size: [u32; 2],
    ) {
        if self.active.is_empty() {
            return;
        }
        if self.collect_needed {
            for kind in 0..KINDS {
                encoder.clear_buffer(&self.draws, kind * DRAW_BYTES + 4, Some(4));
            }
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("Update landscape chunks and collect visible instances"),
                    timestamp_writes: None,
                });
                pass.set_bind_group(0, view_groups[0], &[]);
                pass.set_bind_group(1, &self.bindings, &[]);
                pass.set_bind_group(2, view_groups[2], &[]);
                pass.set_bind_group(3, view_groups[3], &[]);
                if self.build_count != 0 {
                    pass.set_pipeline(&self.build);
                    pass.dispatch_workgroups(2, 2, self.build_count);
                }
                pass.set_pipeline(&self.collect);
                pass.dispatch_workgroups(2, 2, self.active.len() as u32);
                pass.set_pipeline(&self.limit);
                pass.dispatch_workgroups(1, 1, 1);
            }
            self.built_total += u64::from(self.build_count);
            self.build_count = 0;
            self.collect_needed = false;
        }
        if self.depth.as_ref().is_none_or(|(old, _)| *old != size) {
            let depth = device.create_texture(&wgpu::TextureDescriptor {
                label: Some("Z7 landscape depth"),
                size: wgpu::Extent3d {
                    width: size[0],
                    height: size[1],
                    depth_or_array_layers: 1,
                },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Depth32Float,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
                view_formats: &[],
            });
            self.depth = Some((size, depth.create_view(&Default::default())));
        }
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Z7 forest and mountain geometry"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: image,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Load,
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment {
                view: &self.depth.as_ref().unwrap().1,
                depth_ops: Some(wgpu::Operations {
                    load: wgpu::LoadOp::Clear(1.),
                    store: wgpu::StoreOp::Discard,
                }),
                stencil_ops: None,
            }),
            occlusion_query_set: None,
            timestamp_writes: self.timestamps.as_ref().map(|query_set| wgpu::RenderPassTimestampWrites {
                query_set, beginning_of_pass_write_index: Some(0), end_of_pass_write_index: Some(1),
            }),
        });
        pass.set_pipeline(&self.render);
        for (slot, group) in view_groups.into_iter().enumerate() {
            pass.set_bind_group(slot as u32, group, &[]);
        }
        pass.set_vertex_buffer(0, self.vertices.slice(..));
        pass.set_index_buffer(self.indices.slice(..), wgpu::IndexFormat::Uint16);
        if let Some(set) = &self.statistics { pass.begin_pipeline_statistics_query(set,0); }
        for kind in 0..KINDS {
            let bytes = CAPACITY * INSTANCE_BYTES;
            pass.set_vertex_buffer(1, self.instances.slice(kind * bytes..(kind + 1) * bytes));
            pass.draw_indexed_indirect(&self.draws, kind * DRAW_BYTES);
        }
        if self.statistics.is_some() { pass.end_pipeline_statistics_query(); }
        self.profiled = true;
    }
}

fn visible_chunks(camera: &Camera, size: [u32; 2], output: &mut Vec<Chunk>) {
    // The wrapped WGS84 lattice is fixed in space at every model scale.
    let span=CHUNK_SIDE;
    let [lon, lat] = camera.coordinates().map(f64::to_radians);
    let padding = 2_500. / camera.mpp + 46.;
    let radius = camera.extent(size, padding);
    let stride = PI * f64::from(span) / f64::from(LATITUDE_CELLS);
    let rows = LATITUDE_CELLS / span;
    let start = ((PI / 2. - lat - radius) / stride).floor().max(0.) as i32;
    let end = ((PI / 2. - lat + radius) / stride)
        .floor()
        .min(f64::from(rows - 1)) as i32;
    let mut chunks = Vec::new();
    let midpoint = size.map(|dimension|f64::from(dimension)*0.5);
    for row in start..=end {
        let north = PI / 2. - f64::from(row) * stride;
        let middle = north - stride / 2.;
        let columns = (2. * f64::from(rows) * middle.cos()).round().max(1.) as i32;
        let step = 2. * PI / f64::from(columns);
        // At a pole the viewport can span every longitude.
        let range = if lat.abs() + radius + stride >= PI / 2. {
            columns
        } else {
            ((radius.sin() / lat.cos()).clamp(-1., 1.).asin() / step).ceil() as i32 + 1
        };
        let center = ((lon + PI) / step).floor() as i32;
        let count = (2 * range + 1).min(columns);
        for column in (center - range..center - range + count).map(|x| x.rem_euclid(columns)) {
            let east = -PI + (f64::from(column) + 0.5) * step;
            let direction = frame([east.to_degrees(), middle.to_degrees()])[2];
            let Some([x, y]) = camera.project_vec(direction, size) else {
                continue;
            };
            if x >= -padding
                && x <= f64::from(size[0]) + padding
                && y >= -padding
                && y <= f64::from(size[1]) + padding
            {
                let distance = (x-midpoint[0]).powi(2)+(y-midpoint[1]).powi(2);
                chunks.push((distance,[(column*span) as u32,(row*span) as u32,(columns*span) as u32,1]));
            }
        }
    }
    chunks.sort_unstable_by(|(a,left),(b,right)|a.total_cmp(b).then_with(||left.cmp(right)));
    output.extend(chunks.into_iter().map(|(_,chunk)|chunk));
}
