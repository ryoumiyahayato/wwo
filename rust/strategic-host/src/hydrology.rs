use crate::{
    camera::{dot, frame, Camera, EARTH, V3},
    overlay::Mesh,
};
use std::{
    collections::{HashMap, HashSet},
    fs,
    io::{self, Read, Seek, SeekFrom},
    path::Path,
    sync::mpsc,
};

const WATER_COLUMNS: usize = 256;
const WATER_ROWS: usize = 128;
const WATER_PAGES: usize = WATER_COLUMNS * WATER_ROWS;
const WATER_WORDS: usize = 3 * 1024 * 1024;
pub const WATER_MPP: f64 = 4200.;
const WATER_PREFETCH: f64 = 280.;

struct WaterPage {
    index: usize,
    axis: V3,
    radius: f64,
    range: std::ops::Range<u64>,
}

type WaterBatch = Vec<(usize, io::Result<Vec<u32>>)>;

pub struct WaterPages {
    classes: Vec<u32>,
    pages: Vec<WaterPage>,
    desired: Vec<usize>,
    resident: HashMap<usize, Vec<u32>>,
    request: mpsc::Sender<Vec<(usize, std::ops::Range<u64>)>>,
    ready: mpsc::Receiver<WaterBatch>,
    unavailable: HashSet<usize>,
    inflight: bool,
    selection: Option<(V3, f64, f64)>,
    drawn: usize,
    revision: u64,
}

pub fn water_buffer(device: &wgpu::Device, enabled: bool) -> wgpu::Buffer {
    let words = if enabled { WATER_WORDS } else { 1 };
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("Viewport water geometry"),
        size: (words * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    })
}

fn valid_water_page(words: &[u32]) -> bool {
    const CELLS: usize = 64;
    const BAND_HEADER: usize = 10;
    words[..CELLS].iter().all(|&entry| {
        if entry <= 3 {
            return true;
        }
        let start = entry as usize - 4;
        let Some(header) = words.get(start..start + BAND_HEADER) else {
            return false;
        };
        start >= CELLS
            && header[1] == BAND_HEADER as u32
            && start + header[BAND_HEADER - 1] as usize <= words.len()
            && header[1..].windows(2).all(|offsets| {
                offsets[1]
                    .checked_sub(offsets[0])
                    .is_some_and(|size| size % 3 == 0)
            })
    })
}

impl WaterPages {
    pub fn open(path: &Path, queue: &wgpu::Queue, buffer: &wgpu::Buffer) -> io::Result<Self> {
        let mut file = fs::File::open(path)?;
        let length = file.metadata()?.len();
        let mut header = vec![0; 8 + (WATER_PAGES + 1) * 8];
        file.read_exact(&mut header)?;
        let mut classes = vec![0; WATER_PAGES];
        file.read_exact(&mut classes)?;
        let offsets: Vec<_> = header[8..]
            .chunks_exact(8)
            .map(|offset| u64::from_le_bytes(offset.try_into().unwrap()))
            .collect();
        if &header[..8] != b"WWOWAT01"
            || offsets[0] != (header.len() + classes.len()) as u64
            || offsets[WATER_PAGES] != length
            || classes.iter().enumerate().any(|(index, &class)| {
                let size = offsets[index + 1].checked_sub(offsets[index]);
                !matches!((class, size), (1..=3, Some(0)))
                    && !(class == 0
                        && size.is_some_and(|bytes| {
                            (256..=WATER_WORDS as u64).contains(&bytes) && bytes % 4 == 0
                        }))
            })
        {
            return Err(io::Error::other("无效的 WGS84 水域几何页表"));
        }
        let step = 360. / WATER_COLUMNS as f64;
        let pages = classes
            .iter()
            .enumerate()
            .filter_map(|(index, &class)| {
                if class != 0 {
                    return None;
                }
                let lon = (index % WATER_COLUMNS) as f64 * step - 180. + step * 0.5;
                let lat = 90. - ((index / WATER_COLUMNS) as f64 + 0.5) * step;
                let axis = frame([lon, lat])[2];
                let half = step * 0.5;
                let radius = [[-half, -half], [-half, half], [half, -half], [half, half]]
                    .into_iter()
                    .map(|[x, y]| {
                        dot(axis, frame([lon + x, lat + y])[2])
                            .clamp(-1., 1.)
                            .acos()
                    })
                    .fold(0., f64::max);
                Some(WaterPage {
                    index,
                    axis,
                    radius,
                    range: offsets[index]..offsets[index + 1],
                })
            })
            .collect();
        let classes: Vec<u32> = classes.into_iter().map(u32::from).collect();
        queue.write_buffer(buffer, 0, bytemuck::cast_slice(&classes));
        let (request, work) = mpsc::channel::<Vec<(usize, std::ops::Range<u64>)>>();
        let (done, ready) = mpsc::channel();
        std::thread::Builder::new()
            .name("WWO water pages".into())
            .spawn(move || {
                while let Ok(pages) = work.recv() {
                    let result = pages
                        .into_iter()
                        .map(|(index, range)| {
                            let result = (|| {
                                let mut words =
                                    vec![0u32; ((range.end - range.start) / 4) as usize];
                                file.seek(SeekFrom::Start(range.start))?;
                                file.read_exact(bytemuck::cast_slice_mut(&mut words))?;
                                words
                                    .iter_mut()
                                    .for_each(|word| *word = u32::from_le(*word));
                                if !valid_water_page(&words) {
                                    return Err(io::Error::other("无效的水域几何页"));
                                }
                                Ok(words)
                            })();
                            (index, result)
                        })
                        .collect();
                    if done.send(result).is_err() {
                        break;
                    }
                }
            })?;
        Ok(Self {
            classes,
            pages,
            desired: Vec::new(),
            resident: HashMap::new(),
            request,
            ready,
            unavailable: HashSet::new(),
            inflight: false,
            selection: None,
            drawn: 0,
            revision: 0,
        })
    }

    pub fn update(
        &mut self,
        queue: &wgpu::Queue,
        buffer: &wgpu::Buffer,
        camera: &Camera,
        size: [u32; 2],
    ) {
        let active = camera.mpp < WATER_MPP;
        let mut changed = false;
        if let Ok(results) = self.ready.try_recv() {
            self.inflight = false;
            for (page, result) in results {
                match result {
                    Ok(data) if active => {
                        self.resident.insert(page, data);
                        changed = true;
                    }
                    Ok(_) => {}
                    Err(error) => {
                        self.unavailable.insert(page);
                        eprintln!("Water geometry page {page} fallback: {error}");
                    }
                }
            }
        }
        if !active {
            return;
        }
        let screen_center = size.map(|value| value as f64 * 0.5);
        let (axes, center) = camera.projection(size);
        let axis = camera.vector(screen_center, size).unwrap_or(axes[2]);
        let offset = (center[0] - screen_center[0])
            .hypot((center[1] - screen_center[1]) / camera.pitch().cos());
        let radius = camera.extent(size, WATER_PREFETCH + offset);
        let slack = (camera.mpp * 65. / EARTH).cos();
        if self.selection.is_none_or(|(previous, reach, mpp)| {
            dot(previous, axis) < slack
                || (radius - reach).abs() > camera.mpp * 40. / EARTH
                || (mpp / camera.mpp - 1.).abs() > 0.12
        }) {
            self.selection = Some((axis, radius, camera.mpp));
            let mut nearby: Vec<_> = self
                .pages
                .iter()
                .enumerate()
                .filter_map(|(index, page)| {
                    let alignment = dot(axis, page.axis);
                    (alignment >= (radius + page.radius).cos()).then_some((index, alignment))
                })
                .collect();
            nearby.sort_unstable_by(|(_, a), (_, b)| b.total_cmp(a));
            let mut budget = WATER_WORDS - WATER_PAGES;
            let mut desired = Vec::new();
            for (index, _) in nearby {
                let page = &self.pages[index];
                let words = ((page.range.end - page.range.start) / 4) as usize;
                if words > budget {
                    continue;
                }
                budget -= words;
                desired.push(index);
            }
            desired.sort_unstable();
            if self.desired != desired {
                self.desired = desired;
                changed = true;
            }
        }
        if changed {
            let mut words = self.classes.clone();
            self.drawn = 0;
            for &index in &self.desired {
                let key = self.pages[index].index;
                if let Some(data) = self.resident.get(&key) {
                    words[key] = words.len() as u32;
                    words.extend_from_slice(data);
                    self.drawn += 1;
                }
            }
            queue.write_buffer(buffer, 0, bytemuck::cast_slice(&words));
            self.revision += 1;
            // Keep the last surrounding pages for a short reversal within the same budget.
            let mut spare = WATER_WORDS - words.len();
            self.resident.retain(|&index, data| {
                if words[index] != 0 {
                    return true;
                }
                if data.len() > spare {
                    return false;
                }
                spare -= data.len();
                true
            });
        }
        if !self.inflight {
            let mut pending: Vec<_> = self
                .desired
                .iter()
                .filter_map(|&index| {
                    let page = &self.pages[index];
                    (!self.resident.contains_key(&page.index)
                        && !self.unavailable.contains(&page.index))
                    .then_some(page)
                })
                .collect();
            if !pending.is_empty() {
                pending.sort_unstable_by(|a, b| dot(axis, b.axis).total_cmp(&dot(axis, a.axis)));
                let pending = pending
                    .into_iter()
                    .take(96)
                    .map(|page| (page.index, page.range.clone()))
                    .collect();
                self.inflight = self.request.send(pending).is_ok();
            }
        }
    }

    pub fn inflight(&self) -> bool {
        self.inflight
    }

    pub fn status(&self) -> (usize, usize) {
        (self.drawn, self.desired.len())
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }
}

const CELL: f64 = 1.;
const COLUMNS: usize = 360;
const ROWS: usize = 180;
const START_MPP: f64 = 650.;
const END_MPP: f64 = 1450.;

type Segment = [[f32; 3]; 2];

struct ReachCell {
    normal: V3,
    segments: Vec<Segment>,
}

#[derive(Clone, Copy, PartialEq)]
struct RiverView {
    axes: [V3; 3],
    center: [f64; 2],
    size: [u32; 2],
    mpp: f64,
    pitch: f64,
    blend: f64,
}

pub struct Rivers {
    cells: Vec<ReachCell>,
    mesh: Mesh,
    previous: Option<RiverView>,
}

impl Rivers {
    pub fn open(path: &Path) -> io::Result<Self> {
        let data = fs::read(path)?;
        let geometry = data
            .strip_prefix(b"WWORIV01")
            .filter(|bytes| bytes.len() % 20 == 0)
            .ok_or_else(|| io::Error::other("河流中心线格式不匹配"))?;
        let mut cells = vec![Vec::new(); COLUMNS * ROWS];
        for bytes in geometry.chunks_exact(20) {
            let coordinate = |offset| {
                f64::from(f32::from_le_bytes(
                    bytes[offset..offset + 4].try_into().unwrap(),
                ))
            };
            let from = [coordinate(4), coordinate(8)];
            let to = [coordinate(12), coordinate(16)];
            if !from.into_iter().chain(to).all(f64::is_finite)
                || from[1].abs() > 90.
                || to[1].abs() > 90.
                || (from[0] - to[0]).abs().max((from[1] - to[1]).abs()) > 2.
            {
                return Err(io::Error::other("无效的 WGS84 河段"));
            }
            let lon = (from[0] + to[0]) * 0.5;
            let lat = (from[1] + to[1]) * 0.5;
            let x = ((lon + 180.).rem_euclid(360.) / CELL) as usize;
            let y = (((lat + 90.) / CELL) as usize).min(ROWS - 1);
            cells[y * COLUMNS + x]
                .push([from, to].map(|ll| frame(ll)[2].map(|component| component as f32)));
        }
        let cells = cells
            .into_iter()
            .enumerate()
            .filter(|(_, segments)| !segments.is_empty())
            .map(|(index, segments)| {
                let lon = (index % COLUMNS) as f64 * CELL - 180. + CELL * 0.5;
                let lat = (index / COLUMNS) as f64 * CELL - 90. + CELL * 0.5;
                ReachCell {
                    normal: frame([lon, lat])[2],
                    segments,
                }
            })
            .collect();
        Ok(Self {
            cells,
            mesh: Mesh::default(),
            previous: None,
        })
    }

    pub fn project(&mut self, camera: &Camera, size: [u32; 2], enabled: bool) -> Option<&Mesh> {
        if !enabled || camera.mpp >= END_MPP {
            self.previous = None;
            return None;
        }
        let (axes, center) = camera.projection(size);
        let view = RiverView {
            axes,
            center,
            size,
            mpp: camera.mpp,
            pitch: camera.pitch(),
            blend: camera.blend(),
        };
        if self.previous == Some(view) {
            return None;
        }
        self.previous = Some(view);
        self.mesh.vertices.clear();
        self.mesh.indices.clear();
        // The cell owns the segment midpoint. Include both its half-diagonal
        // and the maximum endpoint distance permitted by the sidecar format.
        let [w, h] = size.map(f64::from);
        let pitch = view.pitch.cos();
        let offset = (center[0] - w * 0.5).hypot((center[1] - h * 0.5) / pitch);
        let radius = camera.extent(size, 4. + offset) + (1.45 * (CELL + 2.) * 0.5).to_radians();
        let cosine = radius.cos();
        let t = ((camera.mpp - START_MPP) / (END_MPP - START_MPP)).clamp(0., 1.);
        let opacity = (1. - t * t * (3. - 2. * t)) * 0.82;
        let color = [58, 107, 124, (opacity * 255.).round() as u8];
        let scale = EARTH / camera.mpp;
        let project = |point| {
            let [x, y, z] = axes.map(|axis| dot(point, axis));
            if z <= 0. {
                return None;
            }
            let r = x.hypot(y);
            let k = if r > 1e-12 {
                1. - view.blend + view.blend * r.atan2(z) / r
            } else {
                1.
            };
            Some([center[0] + x * k * scale, center[1] - y * k * scale * pitch])
        };
        for cell in &self.cells {
            if dot(cell.normal, axes[2]) < cosine {
                continue;
            }
            for &[a, b] in &cell.segments {
                let (Some(a), Some(b)) = (project(a.map(f64::from)), project(b.map(f64::from)))
                else {
                    continue;
                };
                if a[0].min(b[0]) > w + 2.
                    || a[0].max(b[0]) < -2.
                    || a[1].min(b[1]) > h + 2.
                    || a[1].max(b[1]) < -2.
                {
                    continue;
                }
                let start = self.mesh.vertices.len();
                self.mesh
                    .line(a.map(|v| v as f32), b.map(|v| v as f32), 1.5, color);
                for (vertex, side) in self.mesh.vertices[start..]
                    .iter_mut()
                    .zip([1., 1., -1., -1.])
                {
                    vertex.uv = [side, 0.];
                }
            }
        }
        Some(&self.mesh)
    }

    pub fn visible(&self) -> bool {
        self.previous.is_some()
    }
}
