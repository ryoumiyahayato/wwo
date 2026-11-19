use crate::{
    camera::{frame, Camera},
    landscape_models::{self, Vertex},
};
use std::f64::consts::PI;
use wgpu::util::DeviceExt;

const KINDS: u64 = 3;
const CHUNK_SIDE: i32 = 16;
const LATITUDE_CELLS: i32 = 98_304;
const CAPACITY: u64 = 131_072;
const INSTANCE_BYTES: u64 = 48;
const COMMAND_BYTES: u64 = 16;
const MAX_CHUNKS: usize = 2_400;

type ViewKey = ([[f64; 3]; 3], [f64; 2], f64, f64, [u32; 2], u64);

pub struct Landscape {
    compute: wgpu::ComputePipeline,
    limit: wgpu::ComputePipeline,
    render: wgpu::RenderPipeline,
    bindings: wgpu::BindGroup,
    chunks: wgpu::Buffer,
    draws: wgpu::Buffer,
    vertices: wgpu::Buffer,
    instances: wgpu::Buffer,
    depth: Option<([u32; 2], wgpu::TextureView)>,
    previous: Option<ViewKey>,
    visible: u32,
    regenerate: bool,
}

impl Landscape {
    pub fn new(
        device: &wgpu::Device,
        format: wgpu::TextureFormat,
        view_layouts: [&wgpu::BindGroupLayout; 3],
        shader: &wgpu::ShaderModule,
    ) -> Self {
        use wgpu::BufferUsages as Usage;
        let vertices = landscape_models::meshes();
        let mut first = 0;
        let commands: Vec<[u32; 4]> = vertices
            .iter()
            .map(|vertices| {
                let len = vertices.len() as u32;
                let command = [len, 0, first, 0];
                first += len;
                command
            })
            .collect();
        let vertices = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Z7 landscape shared meshes"),
            contents: bytemuck::cast_slice(&vertices.into_iter().flatten().collect::<Vec<_>>()),
            usage: Usage::VERTEX,
        });
        let draws = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Z7 landscape draw commands"),
            contents: bytemuck::cast_slice(&commands),
            usage: Usage::INDIRECT | Usage::STORAGE | Usage::COPY_DST,
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
            "Z7 visible chunks",
            (16 * MAX_CHUNKS) as u64,
            Usage::STORAGE | Usage::COPY_DST,
        );
        let instances = buffer(
            "Z7 visible instances",
            KINDS * CAPACITY * INSTANCE_BYTES,
            Usage::STORAGE | Usage::VERTEX,
        );
        let storage = [true, false, false].map(|read_only| wgpu::BindingType::Buffer {
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
            entries: &[&chunks, &instances, &draws]
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
            bind_group_layouts: &[view_layouts[0], &layout],
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
        let generate = compute("landscape_generate");
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
                        attributes: &wgpu::vertex_attr_array![4=>Float32x4,5=>Float32x4,6=>Float32x4],
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
            compute: generate,
            limit,
            render,
            bindings,
            chunks,
            draws,
            vertices,
            instances,
            depth: None,
            previous: None,
            visible: 0,
            regenerate: false,
        }
    }

    pub fn prepare(
        &mut self,
        queue: &wgpu::Queue,
        camera: &Camera,
        size: [u32; 2],
        revision: u64,
        enabled: bool,
    ) {
        let scale = (f64::from(size[0]) * f64::from(size[1]) / 2_073_600.)
            .sqrt()
            .max(1.);
        if !enabled || camera.mpp * scale >= 70. {
            self.visible = 0;
            self.previous = None;
            self.regenerate = false;
            return;
        }
        let (axes, center) = camera.projection(size);
        let key = (axes, center, camera.mpp, camera.pitch(), size, revision);
        if self.previous == Some(key) {
            return;
        }
        self.previous = Some(key);
        let chunks = visible_chunks(camera, size);
        self.visible = chunks.len() as u32;
        self.regenerate = !chunks.is_empty();
        if self.regenerate {
            queue.write_buffer(&self.chunks, 0, bytemuck::cast_slice(&chunks));
        }
    }

    pub fn visible_chunks(&self) -> u32 {
        self.visible
    }

    pub fn draw(
        &mut self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        image: &wgpu::TextureView,
        view_groups: [&wgpu::BindGroup; 3],
        size: [u32; 2],
    ) {
        if self.visible == 0 {
            return;
        }
        if self.regenerate {
            for kind in 0..KINDS {
                encoder.clear_buffer(&self.draws, kind * COMMAND_BYTES + 4, Some(4));
            }
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("Place Z7 forest and rock instances"),
                    timestamp_writes: None,
                });
                pass.set_bind_group(0, view_groups[0], &[]);
                pass.set_bind_group(1, &self.bindings, &[]);
                pass.set_pipeline(&self.compute);
                pass.dispatch_workgroups(2, 2, self.visible);
            }
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("Bound Z7 instance draws"),
                    timestamp_writes: None,
                });
                pass.set_bind_group(0, view_groups[0], &[]);
                pass.set_bind_group(1, &self.bindings, &[]);
                pass.set_pipeline(&self.limit);
                pass.dispatch_workgroups(1, 1, 1);
            }
            self.regenerate = false;
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

fn visible_chunks(camera: &Camera, size: [u32; 2]) -> Vec<[u32; 4]> {
    // Use a latitude band of about 3.3 km and a wrapped longitude lattice
    // spaced at about 204 m. Neither the viewport nor QPK page IDs seed it.
    let [lon, lat] = camera.coordinates().map(f64::to_radians);
    let radius = camera.extent(size, 30.);
    let stride = PI * f64::from(CHUNK_SIDE) / f64::from(LATITUDE_CELLS);
    let rows = LATITUDE_CELLS / CHUNK_SIDE;
    let start = ((PI / 2. - lat - radius) / stride).floor().max(0.) as i32;
    let end = ((PI / 2. - lat + radius) / stride)
        .floor()
        .min(f64::from(rows - 1)) as i32;
    let mut chunks = Vec::new();
    let mpp = camera.mpp;
    // This also bounds viewport overlap for the supported pitched city view.
    let padding = 5_400. / mpp + 12.;
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
                chunks.push([
                    (column * CHUNK_SIDE) as u32,
                    (row * CHUNK_SIDE) as u32,
                    (columns * CHUNK_SIDE) as u32,
                    0,
                ]);
            }
        }
    }
    chunks.truncate(MAX_CHUNKS);
    chunks
}
