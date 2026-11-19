use crate::{
    camera::{frame, Camera},
    landscape_models::{self, Vertex},
    terrain::Terrain,
};
use std::{collections::HashMap, f64::consts::PI};
use wgpu::util::DeviceExt;

const KINDS: u64 = 5;
const CHUNK_SIDE: i32 = 16;
const LATITUDE_CELLS: i32 = 98_304;
const CAPACITY: u64 = 65_536;
const INSTANCE_BYTES: u64 = 16;
const COMMAND_BYTES: u64 = 16;
const MAX_CHUNKS: usize = 1_728;
const CACHE_CHUNKS: usize = 2_560;
const BUILDS_PER_FRAME: usize = 32;

type Chunk = [u32; 4];

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
}

impl Landscape {
    pub fn new(
        device: &wgpu::Device,
        format: wgpu::TextureFormat,
        view_layouts: [&wgpu::BindGroupLayout; 4],
        shader: &wgpu::ShaderModule,
    ) -> Self {
        use wgpu::BufferUsages as Usage;
        let vertices = landscape_models::meshes();
        let mut first = 0;
        let mesh_commands = vertices.each_ref().map(|vertices| {
                let len = vertices.len() as u32;
                let command = [len, 0, first, 0];
                first += len;
                command
            });
        let commands = [mesh_commands[0], mesh_commands[1], mesh_commands[2], mesh_commands[0], mesh_commands[3]];
        let vertices = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Landscape shared meshes"),
            contents: bytemuck::cast_slice(&vertices.into_iter().flatten().collect::<Vec<_>>()),
            usage: Usage::VERTEX,
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
            COMMAND_BYTES * (MAX_CHUNKS + BUILDS_PER_FRAME) as u64,
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
                        attributes: &wgpu::vertex_attr_array![0=>Float32x3,1=>Float32x3,2=>Float32,3=>Float32],
                    },
                    wgpu::VertexBufferLayout {
                        array_stride: INSTANCE_BYTES, step_mode: wgpu::VertexStepMode::Instance,
                        attributes: &wgpu::vertex_attr_array![4=>Uint32x4],
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
        }
    }

    pub fn prepare(
        &mut self,
        queue: &wgpu::Queue,
        camera: &Camera,
        size: [u32; 2],
        terrain: &Terrain,
        enabled: bool,
    ) {
        let scale = (f64::from(size[0]) * f64::from(size[1]) / 2_073_600.)
            .sqrt()
            .max(1.);
        let footprint = camera.mpp * scale;
        if !enabled || footprint >= 1460. {
            self.active.clear();
            self.requested.clear();
            self.previous = None;
            self.pending = false;
            return;
        }
        let view = LandscapeView {
            projection: camera.projection(size), size, mpp: camera.mpp,
            pitch: camera.pitch(), level: terrain.view_max(),
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
            // Keep adjacent densities until their shader opacity reaches zero.
            if view.level >= 7 && footprint < 72. {
                visible_chunks(camera, size, 1, &mut self.requested);
            }
            if footprint < 300. {
                visible_chunks(camera, size, 4, &mut self.requested);
            }
            if footprint > 143. && footprint < 650. {
                visible_chunks(camera, size, 16, &mut self.requested);
            }
            if footprint > 500. {
                visible_chunks(camera, size, 32, &mut self.requested);
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
            if !current && !terrain.landscape_dependencies(chunk,&mut pages) {continue;}
            let is_valid = current || self.cache.get(&chunk).is_some_and(|cached|cached.pages==pages);
            let build = !is_valid && dirty.len() < BUILDS_PER_FRAME;
            self.pending |= !is_valid && !build;
            let slot = if let Some(cached) = self.cache.get_mut(&chunk) {
                if build {cached.pages.clone_from(&pages);}
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
                self.cache.insert(chunk,CachedChunk{slot,used:self.frame,revision,pages:pages.clone()});
                slot
            } else {
                continue;
            };
            let [x,y,columns,step] = chunk;
            let command = [x,y,columns,(slot<<6)|step];
            if build {dirty.push(command);}
            active.push(command);
        }
        active.sort_unstable();
        self.build_count = dirty.len() as u32;
        self.collect_needed = active != self.active || !dirty.is_empty();
        if self.collect_needed && !active.is_empty() {
            queue.write_buffer(&self.chunks, 0, bytemuck::cast_slice(&active));
        }
        if !dirty.is_empty() {
            queue.write_buffer(&self.chunks, COMMAND_BYTES*MAX_CHUNKS as u64, bytemuck::cast_slice(&dirty));
        }
        self.active = active;
    }

    pub fn visible_chunks(&self) -> usize {self.active.len()}
    pub fn cached_chunks(&self) -> usize {self.cache.len()}
    pub fn built_chunks(&self) -> u64 {self.built_total}
    pub fn pending(&self) -> bool {self.pending}

    pub fn counts(&self, device:&wgpu::Device, queue:&wgpu::Queue) -> std::io::Result<(u32,[u32;5])> {
        if self.active.is_empty() {return Ok((0,[0;5]));}
        let size=KINDS*COMMAND_BYTES;
        let data=device.create_buffer(&wgpu::BufferDescriptor {
            label:Some("Landscape draw count readback"), size,
            usage:wgpu::BufferUsages::COPY_DST|wgpu::BufferUsages::MAP_READ,
            mapped_at_creation:false,
        });
        let mut encoder=device.create_command_encoder(&Default::default());
        encoder.copy_buffer_to_buffer(&self.draws,0,&data,0,size);
        let submission=queue.submit([encoder.finish()]);
        let slice=data.slice(..);
        let (send,receive)=std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read,move |result| {let _=send.send(result);});
        let _=device.poll(wgpu::Maintain::WaitForSubmissionIndex(submission));
        receive.recv().map_err(std::io::Error::other)?.map_err(std::io::Error::other)?;
        let mapped=slice.get_mapped_range();
        let words:&[u32]=bytemuck::cast_slice(&mapped);
        Ok((KINDS as u32,std::array::from_fn(|kind|words[kind*4+1])))
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
                encoder.clear_buffer(&self.draws, kind * COMMAND_BYTES + 4, Some(4));
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
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.render);
        for (slot, group) in view_groups.into_iter().enumerate() {
            pass.set_bind_group(slot as u32, group, &[]);
        }
        pass.set_vertex_buffer(0, self.vertices.slice(..));
        for kind in 0..KINDS {
            let bytes = CAPACITY * INSTANCE_BYTES;
            pass.set_vertex_buffer(1, self.instances.slice(kind * bytes..(kind + 1) * bytes));
            pass.draw_indirect(&self.draws, kind * COMMAND_BYTES);
        }
    }
}

fn visible_chunks(camera: &Camera, size: [u32; 2], spacing: i32, output: &mut Vec<Chunk>) {
    // Use the same wrapped WGS84 lattice at all three display densities.
    let span=CHUNK_SIDE*spacing;
    let [lon, lat] = camera.coordinates().map(f64::to_radians);
    let padding = f64::from(spacing)*2_500. / camera.mpp + 46.;
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
                chunks.push((distance,[(column*span) as u32,(row*span) as u32,(columns*span) as u32,spacing as u32]));
            }
        }
    }
    chunks.sort_unstable_by(|(a,left),(b,right)|a.total_cmp(b).then_with(||left.cmp(right)));
    output.extend(chunks.into_iter().map(|(_,chunk)|chunk));
}
