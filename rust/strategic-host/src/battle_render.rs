use crate::battle_view::{Camera, Scale};
use wwo_map_lab::{
    battlefield_terrain::{BattlefieldTerrain, REGION_BOUNDS},
    land_battle::{LandBattle, LandTeam},
};
use bytemuck::{Pod, Zeroable};
use glam::{Mat4, Quat, Vec2, Vec3};
use std::{collections::BTreeMap, fs, io, path::Path};
use wgpu::util::DeviceExt;

const DEPTH: wgpu::TextureFormat = wgpu::TextureFormat::Depth32Float;
const REGION_TILE: f32 = 5_000.;
const TILE_COLUMNS: usize = 10;
const GROUND_GRID: usize = 20;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Vertex {
    position: [f32; 3],
    normal: [f32; 3],
    color: [f32; 3],
}

impl Vertex {
    fn new(position: Vec3, normal: Vec3, color: [f32; 3]) -> Self {
        Self { position: position.to_array(), normal: normal.to_array(), color }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Instance {
    transform: [[f32; 4]; 4],
    tint: [f32; 4],
    kind: f32,
}

impl Instance {
    fn new(transform: Mat4, tint: [f32; 4], kind: f32) -> Self {
        Self { transform: transform.to_cols_array_2d(), tint, kind }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct View {
    clip: [[f32; 4]; 4],
    camera_center: [f32; 2],
    span: f32,
    padding: f32,
}

fn upload<T: Pod>(device: &wgpu::Device, label: &str, data: &[T], usage: wgpu::BufferUsages) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: bytemuck::cast_slice(data),
        usage,
    })
}

struct Indices {
    buffer: wgpu::Buffer,
    count: u32,
}

impl Indices {
    fn new(device: &wgpu::Device, indices: &[u32]) -> Self {
        let buffer = upload(device, "Battle indices", indices, wgpu::BufferUsages::INDEX);
        Self { buffer, count: indices.len() as u32 }
    }

    fn draw(&self, pass: &mut wgpu::RenderPass<'_>, vertices: &wgpu::Buffer, instances: std::ops::Range<u32>) {
        pass.set_vertex_buffer(0, vertices.slice(..));
        pass.set_index_buffer(self.buffer.slice(..), wgpu::IndexFormat::Uint32);
        pass.draw_indexed(0..self.count, 0, instances);
    }
}

#[derive(Default)]
struct Geometry {
    vertices: Vec<Vertex>,
    indices: Vec<u32>,
}

struct Mesh {
    vertices: wgpu::Buffer,
    indices: Indices,
}

impl Mesh {
    fn new(device: &wgpu::Device, geometry: Geometry) -> Self {
        Self {
            vertices: upload(device, "Battle model", &geometry.vertices, wgpu::BufferUsages::VERTEX),
            indices: Indices::new(device, &geometry.indices),
        }
    }

    fn draw(&self, pass: &mut wgpu::RenderPass<'_>, instances: std::ops::Range<u32>) {
        if !instances.is_empty() {
            self.indices.draw(pass, &self.vertices, instances);
        }
    }
}

#[derive(Clone, Copy)]
struct Tile {
    origin: Vec2,
    size: f32,
}

impl Tile {
    fn at(index: usize, origin: f32, size: f32) -> Self {
        let x = (index % TILE_COLUMNS) as f32 * size + origin;
        let z = (index / TILE_COLUMNS) as f32 * size + origin;
        Self { origin: Vec2::new(x, z), size }
    }

    fn distance(self, center: Vec2) -> f32 {
        let offset = (center - self.origin - self.size * 0.5).abs();
        (offset - self.size * 0.5).max(Vec2::ZERO).length()
    }

    fn vertices(self, device: &wgpu::Device, cells: usize, height: impl Fn(Vec2) -> f32) -> wgpu::Buffer {
        let stride = cells + 1;
        let sample_stride = cells + 3;
        let step = self.size / cells as f32;
        let mut samples = Vec::with_capacity(sample_stride * sample_stride);
        for z in 0..sample_stride {
            for x in 0..sample_stride {
                let point = self.origin + (Vec2::new(x as f32, z as f32) - Vec2::ONE) * step;
                samples.push(height(point));
            }
        }
        let mut vertices = Vec::with_capacity(stride * stride + stride * 4);
        for z in 0..stride {
            for x in 0..stride {
                let at = (z + 1) * sample_stride + x + 1;
                let normal = Vec3::new(
                    samples[at - 1] - samples[at + 1],
                    step * 2.,
                    samples[at - sample_stride] - samples[at + sample_stride],
                ).normalize();
                let point = self.origin + Vec2::new(x as f32, z as f32) * step;
                vertices.push(Vertex::new(Vec3::new(point.x, samples[at], point.y), normal, [0.; 3]));
            }
        }
        for side in 0..4 {
            for along in 0..stride {
                let mut vertex = vertices[edge(cells, side, along)];
                vertex.position[1] -= step.max(10.) * 1.5;
                vertices.push(vertex);
            }
        }
        upload(device, "Battle ground tile", &vertices, wgpu::BufferUsages::VERTEX)
    }
}

fn edge(cells: usize, side: usize, along: usize) -> usize {
    let stride = cells + 1;
    match side {
        0 => along,
        1 => along * stride + cells,
        2 => cells * stride + cells - along,
        _ => (cells - along) * stride,
    }
}

fn tile_indices(device: &wgpu::Device, cells: usize) -> Indices {
    let stride = cells + 1;
    let mut indices = Vec::with_capacity(6 * (cells * cells + 4 * cells));
    for z in 0..cells {
        for x in 0..cells {
            let a = (z * stride + x) as u32;
            let b = a + 1;
            let c = a + stride as u32;
            let d = c + 1;
            indices.extend([a, c, b, b, c, d]);
        }
    }
    // Skirts close the battlefield boundary below the ground surface.
    for side in 0..4 {
        for along in 0..cells {
            let top = edge(cells, side, along) as u32;
            let next = edge(cells, side, along + 1) as u32;
            let bottom = (stride * (stride + side) + along) as u32;
            indices.extend([top, next, bottom, bottom, next, bottom + 1]);
        }
    }
    Indices::new(device, &indices)
}

fn ground_height(terrain: &BattlefieldTerrain, point: Vec2) -> f32 {
    let [min_x, min_z, max_x, max_z] = REGION_BOUNDS;
    let x = f64::from(point.x).clamp(min_x, max_x);
    let z = f64::from(point.y).clamp(min_z, max_z);
    terrain.sample_region(x, z).map_or(0., |height| height.height_m as f32)
}

struct Ground {
    vertices: Vec<wgpu::Buffer>,
    indices: Indices,
}

impl Ground {
    fn new(device: &wgpu::Device, terrain: &BattlefieldTerrain) -> Self {
        let vertices = (0..TILE_COLUMNS * TILE_COLUMNS)
            .map(|index| Tile::at(index, REGION_BOUNDS[0] as f32, REGION_TILE)
                .vertices(device, GROUND_GRID, |point| ground_height(terrain, point)))
            .collect();
        Self { vertices, indices: tile_indices(device, GROUND_GRID) }
    }

    fn draw(&self, pass: &mut wgpu::RenderPass<'_>, camera: &Camera) {
        for (index, vertices) in self.vertices.iter().enumerate() {
            let tile = Tile::at(index, REGION_BOUNDS[0] as f32, REGION_TILE);
            if camera.view == Scale::Vehicle && tile.distance(camera.center) > (camera.span * 3.).max(6_000.) {
                continue;
            }
            self.indices.draw(pass, vertices, 0..1);
        }
    }
}

pub struct Scene {
    pipeline: wgpu::RenderPipeline,
    view: wgpu::Buffer,
    bind: wgpu::BindGroup,
    depth: Option<([u32; 2], wgpu::TextureView)>,
    ground: Ground,
    hull: Mesh,
    turret: Mesh,
    turret_pivot: Vec3,
    tracer: Mesh,
    instances: wgpu::Buffer,
    capacity: usize,
    visible: Vec<Instance>,
    turret_instances: Vec<Instance>,
    tracer_instances: Vec<Instance>,
    original_model: bool,
}

impl Scene {
    pub fn new(
        device: &wgpu::Device, queue: &wgpu::Queue, format: wgpu::TextureFormat, terrain: &BattlefieldTerrain, root: &Path,
    ) -> io::Result<Self> {
        let model = root.join("models/kestrel_scout.glb");
        let (hull, turret, turret_pivot, original_model) = match load_vehicle(&model) {
            Ok((hull, turret, pivot)) => (hull, turret, pivot, true),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                eprintln!("陆战车辆使用程序化模型。{error}");
                fallback_vehicle()
            }
            Err(error) => return Err(error),
        };
        let shader = device.create_shader_module(wgpu::include_wgsl!("battle.wgsl"));
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Rust armored battlefield"),
            layout: None,
            vertex: wgpu::VertexState {
                module: &shader, entry_point: Some("vertex_main"), compilation_options: Default::default(),
                buffers: &[
                    wgpu::VertexBufferLayout {
                        array_stride: size_of::<Vertex>() as u64, step_mode: wgpu::VertexStepMode::Vertex,
                        attributes: &wgpu::vertex_attr_array![0=>Float32x3, 1=>Float32x3, 2=>Float32x3],
                    },
                    wgpu::VertexBufferLayout {
                        array_stride: size_of::<Instance>() as u64, step_mode: wgpu::VertexStepMode::Instance,
                        attributes: &wgpu::vertex_attr_array![3=>Float32x4, 4=>Float32x4, 5=>Float32x4, 6=>Float32x4, 7=>Float32x4, 8=>Float32],
                    },
                ],
            },
            primitive: Default::default(),
            depth_stencil: Some(wgpu::DepthStencilState {
                format: DEPTH, depth_write_enabled: true, depth_compare: wgpu::CompareFunction::Less,
                stencil: Default::default(), bias: Default::default(),
            }),
            multisample: Default::default(),
            fragment: Some(wgpu::FragmentState {
                module: &shader, entry_point: Some("fragment_main"), compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState { format, blend: None, write_mask: wgpu::ColorWrites::ALL })],
            }),
            multiview: None, cache: None,
        });
        let view = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Battle viewpoint"), size: size_of::<View>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false,
        });
        let color_format = if format.is_srgb() { wgpu::TextureFormat::Rgba8UnormSrgb } else { wgpu::TextureFormat::Rgba8Unorm };
        let (width, cover) = terrain.geographic_cover()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "军事格地形缺少地理坐标"))?;
        let pixels = cover.iter().copied().flat_map(geographic_ground_color).collect();
        let region_color = upload_ground_color(device, queue, [width; 2], pixels, color_format);
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Battle ground map"), mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear, mipmap_filter: wgpu::FilterMode::Linear, ..Default::default()
        });
        let bind = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Battle viewpoint"), layout: &pipeline.get_bind_group_layout(0),
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: view.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&region_color) },
                wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::Sampler(&sampler) },
            ],
        });
        let mut tracer = Geometry::default();
        cuboid(&mut tracer, Vec3::new(-0.5, -0.5, 0.), Vec3::new(0.5, 0.5, 1.), [1.; 3]);
        let capacity = 64;
        Ok(Self {
            pipeline, view, bind, depth: None, ground: Ground::new(device, terrain),
            hull: Mesh::new(device, hull), turret: Mesh::new(device, turret), turret_pivot,
            tracer: Mesh::new(device, tracer), instances: instance_buffer(device, capacity), capacity,
            visible: Vec::with_capacity(capacity), turret_instances: Vec::new(), tracer_instances: Vec::new(), original_model,
        })
    }

    pub fn uses_original_model(&self) -> bool { self.original_model }

    pub fn draw(
        &mut self, device: &wgpu::Device, queue: &wgpu::Queue, encoder: &mut wgpu::CommandEncoder,
        image: &wgpu::TextureView, size: [u32; 2], camera: &Camera, battle: &LandBattle, terrain: &BattlefieldTerrain,
    ) {
        queue.write_buffer(&self.view, 0, bytemuck::bytes_of(&View {
            clip: camera.view_projection(size).to_cols_array_2d(),
            camera_center: camera.center.to_array(), span: camera.span, padding: 0.,
        }));
        self.visible.clear();
        self.visible.push(Instance::new(Mat4::IDENTITY, [0.; 4], 0.));
        for unit in battle.units.iter().filter(|_| camera.view == Scale::Vehicle) {
            let point = Vec2::from_array(unit.position);
            if point.distance(camera.center) > camera.span * 1.5 { continue; }
            let height = ground_height(terrain, point);
            let position = Vec3::new(point.x, height, point.y);
            let yaw = Quat::from_rotation_y(unit.heading);
            let tint = if unit.health == 0 {
                [0.18, 0.17, 0.15, 0.78]
            } else {
                let [r, g, b] = team_color(unit.team);
                [r, g, b, 0.26]
            };
            let heading = Vec2::new(unit.heading.sin(), unit.heading.cos());
            let forward = ground_height(terrain, point + heading * 2.);
            let backward = ground_height(terrain, point - heading * 2.);
            let cross = Vec2::new(heading.y, -heading.x);
            let right = ground_height(terrain, point + cross);
            let left = ground_height(terrain, point - cross);
            let tilt = Quat::from_rotation_x(-((forward - backward) / 4.).atan())
                * Quat::from_rotation_z(((right - left) / 2.).atan());
            let hull_orientation = yaw * tilt;
            self.visible.push(Instance::new(Mat4::from_rotation_translation(hull_orientation, position), tint, 1.));
            let turret_yaw = Quat::from_rotation_y(unit.turret_heading - unit.heading);
            let pivot = position + hull_orientation * self.turret_pivot;
            self.turret_instances.push(Instance::new(Mat4::from_rotation_translation(hull_orientation * turret_yaw, pivot), tint, 1.));
        }
        for shot in &battle.projectiles {
            let end = Vec3::from_array(shot.position);
            if Vec2::new(end.x, end.z).distance(camera.center) > camera.span * 1.5 { continue; }
            let traveled = end - Vec3::from_array(shot.previous_position);
            let Some(direction) = traveled.try_normalize() else { continue; };
            let length = traveled.length().clamp(1., 13.);
            let size = (camera.span / size[1].max(1) as f32).clamp(0.13, 9.);
            let transform = Mat4::from_scale_rotation_translation(
                Vec3::new(size, size, length), Quat::from_rotation_arc(Vec3::Z, direction), end - direction * length,
            );
            let color = team_color(shot.team);
            self.tracer_instances.push(Instance::new(transform, [color[0], color[1], color[2], 0.6], 2.));
        }
        let hulls = 1..self.visible.len() as u32;
        let turrets = append_instances(&mut self.visible, &mut self.turret_instances);
        let tracers = append_instances(&mut self.visible, &mut self.tracer_instances);
        if self.visible.len() > self.capacity {
            self.capacity = self.visible.len().next_power_of_two();
            self.instances = instance_buffer(device, self.capacity);
        }
        queue.write_buffer(&self.instances, 0, bytemuck::cast_slice(&self.visible));

        if self.depth.as_ref().is_none_or(|(current, _)| *current != size) {
            let depth = device.create_texture(&wgpu::TextureDescriptor {
                label: Some("Battlefield depth"),
                size: wgpu::Extent3d { width: size[0], height: size[1], depth_or_array_layers: 1 },
                mip_level_count: 1, sample_count: 1, dimension: wgpu::TextureDimension::D2,
                format: DEPTH, usage: wgpu::TextureUsages::RENDER_ATTACHMENT, view_formats: &[],
            }).create_view(&Default::default());
            self.depth = Some((size, depth));
        }
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Armored battlefield"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: image, resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color { r: 0.65, g: 0.73, b: 0.78, a: 1. }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: self.depth.as_ref().map(|(_, view)| wgpu::RenderPassDepthStencilAttachment {
                view, depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.), store: wgpu::StoreOp::Discard }),
                stencil_ops: None,
            }),
            occlusion_query_set: None, timestamp_writes: None,
        });
        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &self.bind, &[]);
        pass.set_vertex_buffer(1, self.instances.slice(..));
        self.ground.draw(&mut pass, camera);
        self.hull.draw(&mut pass, hulls);
        self.turret.draw(&mut pass, turrets);
        self.tracer.draw(&mut pass, tracers);
    }
}

fn geographic_ground_color(class: u8) -> [u8; 4] {
    let [r, g, b] = match class {
        1 => [75, 108, 82],
        2 => [132, 139, 101],
        3 => [132, 150, 102],
        4 => [164, 153, 111],
        6 => [166, 146, 115],
        7 => [218, 225, 218],
        8 => [64, 106, 121],
        9..=11 => [96, 126, 99],
        // Unknown and built-up cells use neutral ground. The modern cover class
        // alone does not establish if the cell was developed in 1900.
        _ => return [0; 4],
    };
    [r, g, b, 255]
}

fn upload_ground_color(
    device: &wgpu::Device, queue: &wgpu::Queue, mut size: [u32; 2], mut rgba: Vec<u8>, format: wgpu::TextureFormat,
) -> wgpu::TextureView {
    let mip_count = u32::BITS - size[0].max(size[1]).leading_zeros();
    let texture = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("Battle ground color"), size: wgpu::Extent3d { width: size[0], height: size[1], depth_or_array_layers: 1 },
        mip_level_count: mip_count, sample_count: 1, dimension: wgpu::TextureDimension::D2, format,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST, view_formats: &[],
    });
    for level in 0..mip_count {
        queue.write_texture(
            wgpu::TexelCopyTextureInfo { texture: &texture, mip_level: level, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
            &rgba, wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(size[0] * 4), rows_per_image: None },
            wgpu::Extent3d { width: size[0], height: size[1], depth_or_array_layers: 1 },
        );
        if level + 1 < mip_count {
            let reduced = size.map(|dimension| (dimension / 2).max(1));
            rgba = reduce_ground_color(&rgba, size, reduced);
            size = reduced;
        }
    }
    texture.create_view(&Default::default())
}

fn reduce_ground_color(pixels: &[u8], [width, height]: [u32; 2], [out_width, out_height]: [u32; 2]) -> Vec<u8> {
    let mut reduced = Vec::with_capacity((out_width * out_height * 4) as usize);
    for y in 0..out_height {
        for x in 0..out_width {
            let x = x * 2;
            let y = y * 2;
            let next_x = (x + 1).min(width - 1);
            let next_y = (y + 1).min(height - 1);
            let offsets = [[x, y], [next_x, y], [x, next_y], [next_x, next_y]].map(|[x, y]| ((y * width + x) * 4) as usize);
            for channel in 0..4 {
                let sum: u16 = offsets.iter().map(|offset| u16::from(pixels[offset + channel])).sum();
                reduced.push(((sum + 2) / 4) as u8);
            }
        }
    }
    reduced
}

fn append_instances(visible: &mut Vec<Instance>, batch: &mut Vec<Instance>) -> std::ops::Range<u32> {
    let start = visible.len() as u32;
    visible.append(batch);
    start..visible.len() as u32
}

fn instance_buffer(device: &wgpu::Device, capacity: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("Battle model instances"), size: (capacity * size_of::<Instance>()) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false,
    })
}

fn team_color(team: LandTeam) -> [f32; 3] {
    match team {
        LandTeam::Friendly => [0.34, 0.71, 0.95],
        LandTeam::Opposing => [0.94, 0.35, 0.23],
    }
}

fn cuboid(mesh: &mut Geometry, min: Vec3, max: Vec3, color: [f32; 3]) {
    let a = Vec3::new(min.x, min.y, min.z);
    let b = Vec3::new(max.x, min.y, min.z);
    let c = Vec3::new(min.x, min.y, max.z);
    let d = Vec3::new(max.x, min.y, max.z);
    let e = Vec3::new(min.x, max.y, min.z);
    let f = Vec3::new(max.x, max.y, min.z);
    let g = Vec3::new(min.x, max.y, max.z);
    let h = Vec3::new(max.x, max.y, max.z);
    for (face, normal) in [
        ([a, b, c, d], Vec3::NEG_Y), ([e, g, f, h], Vec3::Y),
        ([a, e, b, f], Vec3::NEG_Z), ([c, d, g, h], Vec3::Z),
        ([a, c, e, g], Vec3::NEG_X), ([b, f, d, h], Vec3::X),
    ] {
        let start = mesh.vertices.len() as u32;
        mesh.vertices.extend(face.map(|position| Vertex::new(position, normal, color)));
        mesh.indices.extend([start, start + 1, start + 2, start + 2, start + 1, start + 3]);
    }
}

fn fallback_vehicle() -> (Geometry, Geometry, Vec3, bool) {
    let mut hull = Geometry::default();
    let mut turret = Geometry::default();
    cuboid(&mut hull, Vec3::new(-1.3, 0.39, -2.3), Vec3::new(1.3, 1.25, 2.3), [0.33, 0.36, 0.27]);
    for (left, right) in [(-1.50, -0.98), (0.98, 1.50)] {
        cuboid(&mut hull, Vec3::new(left, 0., -2.45), Vec3::new(right, 0.72, 2.45), [0.16, 0.17, 0.16]);
    }
    cuboid(&mut turret, Vec3::new(-0.80, 0., -0.83), Vec3::new(0.80, 0.61, 0.80), [0.39, 0.41, 0.29]);
    cuboid(&mut turret, Vec3::new(-0.09, 0.23, 0.64), Vec3::new(0.09, 0.42, 3.12), [0.27, 0.29, 0.22]);
    (hull, turret, Vec3::new(0., 1.25, 0.2), false)
}

fn load_vehicle(path: &Path) -> io::Result<(Geometry, Geometry, Vec3)> {
    let bytes = fs::read(path).map_err(|error| io::Error::new(error.kind(), format!("{}: {error}", path.display())))?;
    let asset = gltf::Gltf::from_slice(&bytes).map_err(io::Error::other)?;
    let blob = asset.blob.as_deref().ok_or_else(|| io::Error::other("车辆 GLB 缺少内嵌数据"))?;
    let scene = asset.default_scene().or_else(|| asset.scenes().next()).ok_or_else(|| io::Error::other("车辆 GLB 缺少场景"))?;
    let mut hull = Geometry::default();
    let mut turret = Geometry::default();
    let mut pivot = None;
    let mut palettes = BTreeMap::new();
    let facing = Mat4::from_rotation_y(std::f32::consts::PI);
    for node in scene.nodes() {
        read_node(node, facing, false, blob, &mut palettes, &mut hull, &mut turret, &mut pivot)?;
    }
    let pivot = pivot.filter(|_| !hull.indices.is_empty() && !turret.indices.is_empty())
        .ok_or_else(|| io::Error::other("车辆 GLB 缺少车体或炮塔几何"))?;
    Ok((hull, turret, pivot))
}

fn read_node(
    node: gltf::Node<'_>, parent: Mat4, mut rotating: bool, blob: &[u8],
    palettes: &mut BTreeMap<usize, Palette>, hull: &mut Geometry, turret: &mut Geometry, pivot: &mut Option<Vec3>,
) -> io::Result<()> {
    let transform = parent * Mat4::from_cols_array_2d(&node.transform().matrix());
    if node.name() == Some("Turret") {
        *pivot = Some(transform.transform_point3(Vec3::ZERO));
        rotating = true;
    }
    if let Some(mesh) = node.mesh() {
        let target = if rotating { &mut *turret } else { &mut *hull };
        let offset = if rotating { pivot.unwrap_or(Vec3::ZERO) } else { Vec3::ZERO };
        let normal_transform = transform.inverse().transpose();
        for primitive in mesh.primitives() {
            if primitive.mode() != gltf::mesh::Mode::Triangles { continue; }
            let first = target.vertices.len() as u32;
            let reader = primitive.reader(|buffer| matches!(buffer.source(), gltf::buffer::Source::Bin).then_some(blob));
            let positions = reader.read_positions().ok_or_else(|| io::Error::other("车辆 GLB 缺少顶点"))?;
            let normals = reader.read_normals().ok_or_else(|| io::Error::other("车辆 GLB 缺少法线"))?;
            let material = primitive.material().pbr_metallic_roughness();
            let [red, green, blue, _] = material.base_color_factor();
            let texture = material.base_color_texture().map(|info| {
                let image = info.texture().source();
                let index = image.index();
                if let std::collections::btree_map::Entry::Vacant(entry) = palettes.entry(index) {
                    entry.insert(Palette::read(image, blob)?);
                }
                Ok::<_, io::Error>((index, info.tex_coord()))
            }).transpose()?;
            let mut coordinates = texture.and_then(|(_, channel)| reader.read_tex_coords(channel)).map(|coords| coords.into_f32());
            for (position, normal) in positions.zip(normals) {
                let rgb = texture.zip(coordinates.as_mut().and_then(Iterator::next))
                    .map_or([1.; 3], |((index, _), uv)| palettes[&index].at(uv));
                let position = transform.transform_point3(Vec3::from_array(position)) - offset;
                let normal = normal_transform.transform_vector3(Vec3::from_array(normal)).normalize_or_zero();
                target.vertices.push(Vertex::new(position, normal, [red * rgb[0], green * rgb[1], blue * rgb[2]]));
            }
            if let Some(indices) = reader.read_indices() {
                target.indices.extend(indices.into_u32().map(|index| first + index));
            } else {
                target.indices.extend(first..target.vertices.len() as u32);
            }
        }
    }
    for child in node.children() {
        read_node(child, transform, rotating, blob, palettes, hull, turret, pivot)?;
    }
    Ok(())
}

struct Palette {
    size: [u32; 2],
    channels: usize,
    pixels: Vec<u8>,
}

impl Palette {
    fn read(image: gltf::Image<'_>, blob: &[u8]) -> io::Result<Self> {
        let gltf::image::Source::View { view, mime_type: "image/png" } = image.source() else {
            return Err(io::Error::other("车辆材质需要 GLB 内嵌 PNG"));
        };
        let bytes = blob.get(view.offset()..view.offset() + view.length())
            .ok_or_else(|| io::Error::other("车辆材质超出 GLB 数据范围"))?;
        Self::from_png(bytes)
    }

    fn from_png(bytes: &[u8]) -> io::Result<Self> {
        let mut decoder = png::Decoder::new(bytes);
        decoder.set_transformations(png::Transformations::EXPAND | png::Transformations::STRIP_16);
        let mut reader = decoder.read_info().map_err(io::Error::other)?;
        let mut pixels = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut pixels).map_err(io::Error::other)?;
        let channels = match info.color_type {
            png::ColorType::Rgb => 3,
            png::ColorType::Rgba => 4,
            _ => return Err(io::Error::other("陆战材质需要 RGB 或 RGBA PNG")),
        };
        pixels.truncate(info.buffer_size());
        Ok(Self { size: [info.width, info.height], channels, pixels })
    }

    fn at(&self, uv: [f32; 2]) -> [f32; 3] {
        let [x, y] = std::array::from_fn(|axis| {
            ((uv[axis].clamp(0., 1.) * self.size[axis] as f32) as u32).min(self.size[axis] - 1)
        });
        let index = (y * self.size[0] + x) as usize * self.channels;
        std::array::from_fn(|channel| f32::from(self.pixels[index + channel]) / 255.)
    }
}
