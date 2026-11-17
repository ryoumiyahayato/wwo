use super::*;
use crate::camera::geographic;
use std::{
    collections::{HashMap, HashSet},
    fs::File,
    io::Read,
    path::PathBuf,
    sync::mpsc::{channel, Receiver, Sender},
    thread,
    time::Instant,
};

const BASE: [u32; 2] = [2048, 1024];
const GRID: [u32; 2] = [64, 32];
const GRID_CELLS: usize = (GRID[0] * GRID[1]) as usize;
const PAGE: u32 = 264;
const SLOTS: u32 = 48;
const LAND_SIZE: [usize; 2] = [8192, 4096];
const LAND_BYTES: usize = LAND_SIZE[0] * LAND_SIZE[1] / 8;
const BORDER_GRID: [usize; 2] = [512, 256];
const BORDER_INDEX: usize = BORDER_GRID[0] * BORDER_GRID[1] * 2;
type Key = (u32, u32);
type PageResult = (Key, io::Result<Vec<u8>>);

pub(super) struct NativeMap {
    pipeline: wgpu::RenderPipeline,
    group: wgpu::BindGroup,
    detail: wgpu::Texture,
    table: wgpu::Texture,
    land: Vec<u8>,
    borders: Vec<u32>,
    resident: HashMap<Key, u32>,
    failed: HashSet<Key>,
    mapped: Vec<Key>,
    work: Sender<Key>,
    results: Receiver<PageResult>,
    pending: Option<Key>,
    rivers: Rivers,
    ready_since: Option<Instant>,
}

fn read_zlib(path: &Path, len: usize) -> io::Result<Vec<u8>> {
    let mut result = Vec::with_capacity(len);
    flate2::read::ZlibDecoder::new(File::open(path)?)
        .take(len as u64 + 1)
        .read_to_end(&mut result)?;
    if result.len() != len {
        return Err(io::Error::other(format!("invalid map data length in {}", path.display())));
    }
    Ok(result)
}

fn array_view(texture: &wgpu::Texture) -> wgpu::TextureView {
    texture.create_view(&wgpu::TextureViewDescriptor {
        dimension: Some(wgpu::TextureViewDimension::D2Array),
        ..Default::default()
    })
}

impl NativeMap {
    pub(super) fn open(host: &Renderer, root: &Path, polities: &[crate::world::Polity]) -> io::Result<Self> {
        let ids: Vec<String> = serde_json::from_reader(File::open(root.join("polities.json"))?)?;
        if !ids.iter().map(String::as_str).eq(polities.iter().map(|p| p.id.as_str())) {
            return Err(io::Error::other("native map polity index does not match the world"));
        }

        let levels: Vec<_> = (0..BASE[0].ilog2() + 1)
            .map(|lod| [(BASE[0] >> lod).max(1), (BASE[1] >> lod).max(1), 1])
            .collect();
        let surface_bytes = levels.iter().map(|v| (v[0] * v[1] * 4) as usize).sum();
        let surface = host.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Global geographic samples"),
            size: extent([BASE[0], BASE[1], 1]),
            mip_level_count: levels.len() as u32,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let pixels = read_zlib(&root.join("surface.z"), surface_bytes)?;
        let mut offset = 0;
        for (lod, size) in levels.into_iter().enumerate() {
            let end = offset + (size[0] * size[1] * 4) as usize;
            write_texture_mip(&host.queue, &surface, size, 4, &pixels[offset..end], lod as u32);
            offset = end;
        }
        drop(pixels);
        let land = read_zlib(&root.join("land.z"), LAND_BYTES)?;
        let borders = read_borders(&root.join("borders.z"))?;
        let boundary_buffer = host.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Historical source polygons"),
            contents: bytemuck::cast_slice(&borders),
            usage: wgpu::BufferUsages::STORAGE,
        });
        let detail = create_texture(&host.device, [PAGE, PAGE, SLOTS], wgpu::TextureFormat::Rgba8Unorm);
        let table = create_texture(&host.device, [GRID[0], GRID[1], 1], wgpu::TextureFormat::R8Uint);
        write_texture(&host.queue, &table, [GRID[0], GRID[1], 1], 1, &[0; GRID_CELLS]);
        let rivers = Rivers::open(&root.join("rivers.z"))?;
        let sampler = host.device.create_sampler(&wgpu::SamplerDescriptor {
            address_mode_u: wgpu::AddressMode::Repeat,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });
        let array = wgpu::TextureViewDimension::D2Array;
        let uint = wgpu::TextureSampleType::Uint;
        let layout = layout(&host.device, &[
            uniform(0, wgpu::ShaderStages::FRAGMENT), sampler_entry(1), sampled(2),
            texture_entry(3, wgpu::TextureSampleType::Float { filterable: true }, array),
            texture_entry(4, uint, wgpu::TextureViewDimension::D2),
            sampled(5),
            entry(6, wgpu::ShaderStages::FRAGMENT, wgpu::BindingType::Buffer {
                ty: wgpu::BufferBindingType::Storage { read_only: true },
                has_dynamic_offset: false, min_binding_size: None,
            }),
        ]);
        let group = bind(&host.device, &layout, &[
            buf_resource(0, &host.view), sampler_resource(1, &sampler),
            tex_resource(2, &surface.create_view(&Default::default())),
            tex_resource(3, &array_view(&detail)), tex_resource(4, &table.create_view(&Default::default())),
            tex_resource(5, &host.palette.create_view(&Default::default())), buf_resource(6, &boundary_buffer),
        ]);
        let shader = host.device.create_shader_module(wgpu::include_wgsl!("native_map.wgsl"));
        let pipeline_layout = host.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None, bind_group_layouts: &[&layout], push_constant_ranges: &[],
        });
        let pipeline = host.device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Native globe"), layout: Some(&pipeline_layout), primitive: Default::default(),
            depth_stencil: None, multisample: Default::default(), multiview: None, cache: None,
            vertex: wgpu::VertexState {
                module: &shader, entry_point: Some("triangle"), compilation_options: Default::default(), buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader, entry_point: Some("map"), compilation_options: Default::default(),
                targets: &[Some(host.config.format.into())],
            }),
        });
        let (work, incoming) = channel::<Key>();
        let (outgoing, results) = channel();
        let detail_root: PathBuf = root.join("detail");
        thread::Builder::new().name("native globe data".into()).spawn(move || {
            while let Ok((x, y)) = incoming.recv() {
                let bytes = read_zlib(&detail_root.join(format!("{x}-{y}.z")), (PAGE * PAGE * 4) as usize);
                if outgoing.send(((x, y), bytes)).is_err() { break; }
            }
        })?;
        Ok(Self { pipeline, group, detail, table, land, borders, resident: HashMap::new(),
            failed: HashSet::new(), mapped: Vec::new(), work, results, pending: None, rivers, ready_since: None })
    }

    pub(super) fn owner(&self, [lon, lat]: [f64; 2], active: impl Fn(u8) -> bool) -> u8 {
        let u = (lon + 180.).rem_euclid(360.) / 360.;
        let v = ((90. - lat) / 180.).clamp(0., 1. - f64::EPSILON);
        let x = (u * LAND_SIZE[0] as f64) as usize;
        let y = (v * LAND_SIZE[1] as f64) as usize;
        let bit = y * LAND_SIZE[0] + x;
        if self.land[bit / 8] & (128 >> (bit % 8)) == 0 { return 0; }
        let gx = u * BORDER_GRID[0] as f64;
        let gy = v * BORDER_GRID[1] as f64;
        let index = (gy as usize * BORDER_GRID[0] + gx as usize) * 2;
        let [start, end] = [self.borders[index], self.borders[index + 1]].map(|i| BORDER_INDEX + i as usize);
        if start != end {
            let [x, y] = [gx.fract(), 1. - gy.fract()];
            let mut i = start;
            while i < end {
                let owner = self.borders[i] as u8;
                let limit = i + 2 + self.borders[i + 1] as usize * 4;
                if active(owner) {
                    let mut inside = false;
                    for edge in self.borders[i + 2..limit].chunks_exact(4) {
                        let [a, b, c, d] = std::array::from_fn(|j| f64::from(f32::from_bits(edge[j])));
                        if (b > y) != (d > y) && x < a + (y - b) * (c - a) / (d - b) {
                            inside = !inside;
                        }
                    }
                    if inside { return owner; }
                }
                i = limit;
            }
            return 0;
        }
        let owner = self.borders[index] as u8;
        if active(owner) { owner } else { 0 }
    }

    pub(super) fn update(&mut self, queue: &wgpu::Queue, camera: &Camera, size: [u32; 2]) -> f32 {
        let visible = visible_detail(camera, size, 24.);
        let margin = visible_detail(camera, size, 120.);
        let wanted = if visible.is_empty() || margin.is_empty() { &visible } else { &margin };
        if let Ok((key, result)) = self.results.try_recv() {
            self.pending = None;
            match result {
                Ok(bytes) if wanted.contains(&key) => {
                    let slot = if self.resident.len() < SLOTS as usize {
                        self.resident.len() as u32
                    } else {
                        let old = *self.resident.keys().find(|old| !wanted.contains(old)).unwrap();
                        self.resident.remove(&old).unwrap()
                    };
                    queue.write_texture(
                        wgpu::TexelCopyTextureInfo {
                            texture: &self.detail, mip_level: 0,
                            origin: wgpu::Origin3d { x: 0, y: 0, z: slot }, aspect: wgpu::TextureAspect::All,
                        },
                        &bytes, wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(PAGE * 4), rows_per_image: Some(PAGE) },
                        extent([PAGE, PAGE, 1]),
                    );
                    self.resident.insert(key, slot);
                }
                Err(_) => { self.failed.insert(key); }
                _ => {}
            }
        }
        let ready = !visible.is_empty() && visible.iter().all(|key| self.resident.contains_key(key));
        let next: Vec<_> = wanted.iter().copied().filter(|key| self.resident.contains_key(key)).collect();
        if next != self.mapped {
            let mut indices = [0; GRID_CELLS];
            for &(x, y) in &next {
                indices[(y * GRID[0] + x) as usize] = (self.resident[&(x, y)] + 1) as u8;
            }
            write_texture(queue, &self.table, [GRID[0], GRID[1], 1], 1, &indices);
            self.mapped = next;
        }
        if self.pending.is_none() {
            if let Some(&key) = visible.iter().chain(wanted).find(|key| !self.resident.contains_key(key) && !self.failed.contains(key)) {
                if self.work.send(key).is_ok() { self.pending = Some(key); }
            }
        }
        if !ready {
            self.ready_since = None;
            return 0.;
        }
        let ready_for = self.ready_since.get_or_insert_with(Instant::now).elapsed().as_secs_f64();
        ((1. - crate::camera::smooth(850., 2400., camera.mpp)) * crate::camera::smooth(0., 0.18, ready_for)) as f32
    }

    pub(super) fn usage(&self) -> (usize, usize, f64, bool) {
        let bytes = self.borders.len() * 4 + (BASE[0] * BASE[1] * 4 * 4 / 3 + PAGE * PAGE * SLOTS * 4) as usize;
        let streaming = self.pending.is_some() || self.ready_since.is_some_and(|time| time.elapsed().as_secs_f64() < 0.18);
        (self.resident.len(), self.mapped.len(), bytes as f64 / 1048576., streaming)
    }

    pub(super) fn draw<'a>(&'a self, pass: &mut wgpu::RenderPass<'a>) {
        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &self.group, &[]);
        pass.draw(0..3, 0..1);
    }

    pub(super) fn rivers(&self, camera: &Camera, size: [u32; 2], mesh: &mut Mesh) {
        self.rivers.draw(camera, size, mesh);
    }
}

fn read_borders(path: &Path) -> io::Result<Vec<u32>> {
    const LIMIT: usize = 32 * 1024 * 1024;
    let mut bytes = Vec::new();
    flate2::read::ZlibDecoder::new(File::open(path)?).take(LIMIT as u64 + 1).read_to_end(&mut bytes)?;
    let error = || io::Error::other("invalid native historical geometry");
    if !(BORDER_INDEX * 4..=LIMIT).contains(&bytes.len()) || bytes.len() % 4 != 0 { return Err(error()); }
    let words: Vec<_> = bytes.chunks_exact(4).map(|v| u32::from_le_bytes(v.try_into().unwrap())).collect();
    let data = &words[BORDER_INDEX..];
    for interval in words[..BORDER_INDEX].chunks_exact(2) {
        let mut i = interval[0] as usize;
        let end = interval[1] as usize;
        if i == end {
            if i > 255 { return Err(error()); }
            continue;
        }
        if i > end || end > data.len() { return Err(error()); }
        while i < end {
            if i + 2 > end || data[i] == 0 || data[i] > 255 { return Err(error()); }
            i += 2 + 4 * data[i + 1] as usize;
            if i > end { return Err(error()); }
        }
    }
    Ok(words)
}

fn visible_detail(camera: &Camera, size: [u32; 2], margin: f64) -> Vec<Key> {
    if camera.mpp > 2400. { return Vec::new(); }
    let [left, right, top, bottom] = visible_cells(camera, size, margin);
    if (right - left + 1) * (bottom - top + 1) > SLOTS as i32 { return Vec::new(); }
    cells([left, right, top, bottom]).collect()
}

fn visible_cells(camera: &Camera, size: [u32; 2], margin: f64) -> [i32; 4] {
    let center = size.map(|n| f64::from(n) * 0.5);
    let center = camera.vector(center, size).unwrap_or(camera.axes[2]);
    let [lon, lat] = geographic(center);
    let radius = camera.extent(size, margin);
    let dy = radius.to_degrees();
    let dx = if lat.abs() + dy >= 90. { 180. }
        else { (radius.sin() / lat.to_radians().cos()).clamp(0., 1.).asin().to_degrees() };
    let (left, top) = cell([lon - dx, lat + dy]);
    let (right, bottom) = cell([lon + dx, lat - dy]);
    [left, right.min(left + GRID[0] as i32 - 1), top, bottom]
}

fn cell([x, y]: [f64; 2]) -> (i32, i32) {
    (((x + 180.) / 360. * f64::from(GRID[0])).floor() as i32,
     ((90. - y) / 180. * f64::from(GRID[1])).clamp(0., f64::from(GRID[1] - 1)) as i32)
}

fn cells([left, right, top, bottom]: [i32; 4]) -> impl Iterator<Item = Key> {
    (top..=bottom).flat_map(move |y| {
        (left..=right).map(move |x| (x.rem_euclid(GRID[0] as i32) as u32, y as u32))
    })
}

struct Rivers {
    segments: Vec<[[f64; 2]; 2]>,
    buckets: Vec<Vec<usize>>,
}

impl Rivers {
    fn open(path: &Path) -> io::Result<Self> {
        const MAX_BYTES: u64 = 16 * 1024 * 1024;
        let mut bytes = Vec::new();
        flate2::read::ZlibDecoder::new(File::open(path)?).take(MAX_BYTES + 1).read_to_end(&mut bytes)?;
        if bytes.len() % 16 != 0 || bytes.len() as u64 > MAX_BYTES {
            return Err(io::Error::other("invalid native river segments"));
        }
        let mut buckets = vec![Vec::new(); GRID_CELLS];
        let mut segments = Vec::with_capacity(bytes.len() / 16);
        for entry in bytes.chunks_exact(16) {
            let [x, y, a, b] = std::array::from_fn(|i| f64::from(f32::from_le_bytes(entry[4*i..4*i+4].try_into().unwrap())));
            if !(-180. ..=180.).contains(&x) || !(-180. ..=180.).contains(&a)
                || !(-90. ..=90.).contains(&y) || !(-90. ..=90.).contains(&b) || (x-a).abs() > 180. {
                return Err(io::Error::other("invalid native river coordinate"));
            }
            let (left, top) = cell([x.min(a), y.max(b)]);
            let (right, bottom) = cell([x.max(a), y.min(b)]);
            for (col, row) in cells([left, right, top, bottom]) {
                buckets[(row * GRID[0] + col) as usize].push(segments.len());
            }
            segments.push([[x, y], [a, b]]);
        }
        Ok(Self { segments, buckets })
    }

    fn draw(&self, camera: &Camera, size: [u32; 2], mesh: &mut Mesh) {
        if camera.mpp >= 1150. { return; }
        let opacity = 1. - crate::camera::smooth(380., 1150., camera.mpp);
        let [w, h] = size.map(f64::from);
        let mut drawn = HashSet::new();
        for (x, y) in cells(visible_cells(camera, size, 16.)) {
            for &i in &self.buckets[(y * GRID[0] + x) as usize] {
                if !drawn.insert(i) { continue; }
                let [a, b] = self.segments[i];
                let (Some(a), Some(b)) = (camera.project(a, size), camera.project(b, size)) else { continue; };
                if a[0].max(b[0]) < 0. || a[1].max(b[1]) < 0. || a[0].min(b[0]) > w || a[1].min(b[1]) > h { continue; }
                mesh.line(a.map(|v| v as f32), b.map(|v| v as f32), 1.4, [81, 139, 160, (210. * opacity) as u8]);
            }
        }
    }
}
