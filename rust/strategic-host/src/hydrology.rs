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
    time::{Duration, Instant},
};

const WATER_COLUMNS: usize = 256;
const WATER_ROWS: usize = 128;
const WATER_PAGES: usize = WATER_COLUMNS * WATER_ROWS;
const WATER_WORDS: usize = 3 * 1024 * 1024;
pub const WATER_MPP: f64 = 4200.;
const WATER_PREFETCH_MPP: f64 = 5000.;
const WATER_PREFETCH: f64 = 320.;
const HANDOFF: Duration = Duration::from_millis(80);
const HANDOFF_TICK_LIMIT: u32 = 1 << 30;
const WATER_BATCH: usize = 32;

struct WaterPage {
    index: usize,
    axis: V3,
    radius: f64,
    range: std::ops::Range<u64>,
}

type WaterBatch = Vec<(usize, io::Result<Vec<u32>>)>;

struct ResidentWaterPage {
    words: Vec<u32>,
    last_needed: u64,
}

pub struct WaterPages {
    classes: Vec<u32>,
    table: Vec<u32>,
    pages: Vec<WaterPage>,
    desired: Vec<(usize, bool)>,
    resident: HashMap<usize, ResidentWaterPage>,
    used_words: usize,
    request: mpsc::Sender<Vec<(usize, std::ops::Range<u64>)>>,
    ready: mpsc::Receiver<WaterBatch>,
    unavailable: HashSet<usize>,
    inflight: bool,
    selection: Option<(V3, V3, f64, f64)>,
    previous_view: Option<(V3, Instant)>,
    selection_number: u64,
    epoch: Instant,
    handoff_until: Instant,
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
                                    vec![0u32; 1 + ((range.end - range.start) / 4) as usize];
                                file.seek(SeekFrom::Start(range.start))?;
                                file.read_exact(bytemuck::cast_slice_mut(&mut words[1..]))?;
                                words
                                    .iter_mut()
                                    .for_each(|word| *word = u32::from_le(*word));
                                if !valid_water_page(&words[1..]) {
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
        let epoch = Instant::now();
        Ok(Self {
            table: classes.clone(),
            classes,
            pages,
            desired: Vec::new(),
            resident: HashMap::new(),
            used_words: WATER_PAGES,
            request,
            ready,
            unavailable: HashSet::new(),
            inflight: false,
            selection: None,
            previous_view: None,
            selection_number: 0,
            epoch,
            handoff_until: epoch,
            revision: 0,
        })
    }

    pub fn update(
        &mut self,
        queue: &wgpu::Queue,
        buffer: &wgpu::Buffer,
        camera: &Camera,
        size: [u32; 2],
        now: Instant,
    ) {
        if camera.mpp < WATER_PREFETCH_MPP {
            self.select(camera, size, now);
        } else {
            self.selection = None;
            self.previous_view = None;
            self.desired.clear();
        }

        if let Ok(results) = self.ready.try_recv() {
            self.inflight = false;
            let stamp = self.tick(now);
            let mut touches_view = false;
            let arrivals: Vec<_> = results
                .into_iter()
                .filter_map(|(key, result)| match result {
                    Ok(mut words) => {
                        let visible = self
                            .desired
                            .iter()
                            .any(|&(i, visible)| visible && self.pages[i].index == key);
                        touches_view |= visible;
                        // A page prefetched off screen is authoritative on its first appearance.
                        // Keep completed reads even if the player reversed direction meanwhile.
                        words[0] = if visible { stamp } else { 0 };
                        Some((key, words))
                    }
                    Err(error) => {
                        self.unavailable.insert(key);
                        eprintln!("Water geometry page {key} fallback: {error}");
                        None
                    }
                })
                .collect();
            if !arrivals.is_empty() {
                self.publish(queue, buffer, arrivals);
                if touches_view {
                    self.revision += 1;
                    self.handoff_until = now + HANDOFF;
                }
            }
        }
        if !self.inflight {
            let pending: Vec<_> = self
                .desired
                .iter()
                .map(|&(i, _)| &self.pages[i])
                .filter(|page| {
                    !self.resident.contains_key(&page.index)
                        && !self.unavailable.contains(&page.index)
                })
                .take(WATER_BATCH)
                .map(|page| (page.index, page.range.clone()))
                .collect();
            self.inflight = !pending.is_empty() && self.request.send(pending).is_ok();
        }
    }

    fn select(&mut self, camera: &Camera, size: [u32; 2], now: Instant) {
        let center = size.map(|value| f64::from(value) * 0.5);
        let (axes, origin) = camera.projection(size);
        let axis = camera.vector(center, size).unwrap_or(axes[2]);
        let mut ahead = axis;
        if let Some((previous, time)) = self.previous_view.replace((axis, now)) {
            let elapsed = now.saturating_duration_since(time).as_secs_f64();
            if let Some(point) = camera.project_vec(previous, size) {
                let dx = center[0] - point[0];
                let dy = center[1] - point[1];
                let distance = dx.hypot(dy);
                if elapsed > 0. && elapsed < 0.25 && distance > 0.1 && distance < 170. {
                    let lead = (0.14 / elapsed).min(490. / distance);
                    ahead = camera
                        .vector([center[0] + dx * lead, center[1] + dy * lead], size)
                        .unwrap_or(axis);
                }
            }
        }
        let offset = (origin[0] - center[0]).hypot((origin[1] - center[1]) / camera.pitch().cos());
        // Include selection slack so prefetch-only uploads cannot alter the current raster.
        let view_radius = camera.extent(size, offset + 96.);
        let radius = camera.extent(size, offset + WATER_PREFETCH);
        let slack = (camera.mpp * 48. / EARTH).cos();
        let ahead_slack = (camera.mpp * 110. / EARTH).cos();
        if self.selection.is_some_and(|(previous, lead, reach, mpp)| {
            dot(previous, axis) >= slack
                && dot(lead, ahead) >= ahead_slack
                && (radius - reach).abs() <= camera.mpp * 40. / EARTH
                && (mpp / camera.mpp - 1.).abs() <= 0.10
        }) {
            return;
        }
        self.selection = Some((axis, ahead, radius, camera.mpp));
        self.selection_number += 1;
        let mut nearby: Vec<_> = self
            .pages
            .iter()
            .enumerate()
            .filter_map(|(i, page)| {
                let center = dot(axis, page.axis);
                let lead = dot(ahead, page.axis);
                (center.max(lead) >= (radius + page.radius).cos()).then(|| {
                    let visible = center >= (view_radius + page.radius).cos();
                    (i, visible, if visible { center } else { lead.max(center) })
                })
            })
            .collect();
        nearby.sort_unstable_by(|a, b| b.1.cmp(&a.1).then_with(|| b.2.total_cmp(&a.2)));
        self.desired.clear();
        let mut budget = WATER_WORDS - WATER_PAGES;
        for (i, visible, _) in nearby {
            let page = &self.pages[i];
            let words = 1 + ((page.range.end - page.range.start) / 4) as usize;
            if words <= budget {
                budget -= words;
                self.desired.push((i, visible));
                if let Some(resident) = self.resident.get_mut(&page.index) {
                    resident.last_needed = self.selection_number;
                }
            }
        }
    }

    fn publish(
        &mut self,
        queue: &wgpu::Queue,
        buffer: &wgpu::Buffer,
        arrivals: Vec<(usize, Vec<u32>)>,
    ) {
        let added: usize = arrivals.iter().map(|(_, words)| words.len()).sum();
        if self.used_words + added <= WATER_WORDS {
            for (key, words) in arrivals {
                let offset = self.used_words;
                self.table[key] = offset as u32;
                queue.write_buffer(buffer, (offset * 4) as u64, bytemuck::cast_slice(&words));
                self.used_words += words.len();
                self.resident.insert(
                    key,
                    ResidentWaterPage {
                        words,
                        last_needed: self.selection_number,
                    },
                );
            }
            queue.write_buffer(buffer, 0, bytemuck::cast_slice(&self.table));
        } else {
            // Compact only under pressure. Keep the selected footprint first,
            // then recently used pages for reversals and zooming back in.
            for (key, words) in arrivals {
                self.resident.insert(
                    key,
                    ResidentWaterPage {
                        words,
                        last_needed: self.selection_number,
                    },
                );
            }
            self.table.copy_from_slice(&self.classes);
            let mut order: Vec<_> = self
                .desired
                .iter()
                .map(|&(i, _)| self.pages[i].index)
                .collect();
            let selected: HashSet<_> = order.iter().copied().collect();
            let mut previous: Vec<_> = self
                .resident
                .iter()
                .filter(|(key, _)| !selected.contains(key))
                .map(|(&key, page)| (key, page.last_needed))
                .collect();
            previous.sort_unstable_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
            order.extend(previous.into_iter().map(|(key, _)| key));
            let mut words = self.classes.clone();
            for key in order {
                if let Some(page) = self.resident.get(&key) {
                    if words.len() + page.words.len() <= WATER_WORDS {
                        self.table[key] = words.len() as u32;
                        words.extend_from_slice(&page.words);
                    }
                }
            }
            self.resident.retain(|&key, _| self.table[key] != 0);
            self.used_words = words.len();
            words[..WATER_PAGES].copy_from_slice(&self.table);
            queue.write_buffer(buffer, 0, bytemuck::cast_slice(&words));
        }
    }

    fn tick(&self, now: Instant) -> u32 {
        let elapsed = now.saturating_duration_since(self.epoch).as_millis() / 4 + 1;
        if elapsed < u128::from(HANDOFF_TICK_LIMIT) {
            elapsed as u32
        } else {
            0
        }
    }

    pub fn shader_clock(&self, now: Instant) -> u32 {
        let tick = self.tick(now);
        if tick == 0 { HANDOFF_TICK_LIMIT } else { tick }
    }

    pub fn pending(&self) -> bool {
        self.inflight || Instant::now() < self.handoff_until
    }

    pub fn status(&self) -> ([usize; 2], [usize; 2]) {
        let mut loaded = [0; 2];
        let mut wanted = [0; 2];
        for &(index, visible) in &self.desired {
            let ready = usize::from(self.resident.contains_key(&self.pages[index].index));
            wanted[0] += 1;
            loaded[0] += ready;
            if visible {
                wanted[1] += 1;
                loaded[1] += ready;
            }
        }
        (loaded, wanted)
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
