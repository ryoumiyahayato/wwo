use crate::camera::{geographic, smooth, Camera};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    fs::File,
    io::{self, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    sync::Arc,
    time::Instant,
};

pub const FILE_NAME: &str = "terrain-detail-v1.qdt";
pub const MIPS: u32 = 4;
const FORMAT: &[u8; 8] = b"WWODTL01";
const MAX_INDEX: u32 = 131_072;
const MAX_MPP: f64 = 110.;

#[derive(Deserialize)]
struct Index {
    regions: Vec<Region>,
}

#[derive(Deserialize, Serialize)]
pub struct Region {
    id: String,
    pub extent: [f64; 4],
    pub size: [u32; 2],
    #[serde(skip_serializing)]
    offset: u64,
    #[serde(skip_serializing)]
    bytes: u32,
    sources: Vec<String>,
    modern_reference: bool,
}

pub fn mips([width, height]: [u32; 2]) -> impl Iterator<Item = (u32, [u32; 2], usize)> {
    (0..MIPS).map(move |level| {
        let size = [width >> level, height >> level];
        (level, size, (size[0] * size[1]) as usize)
    })
}

pub struct Catalogue {
    path: PathBuf,
    data_offset: u64,
    pub regions: Vec<Region>,
}

impl Catalogue {
    pub fn open(path: &Path) -> io::Result<Self> {
        let invalid = || io::Error::new(io::ErrorKind::InvalidData, "Invalid terrain detail catalogue");
        let mut file = File::open(path)?;
        let mut magic = [0; 8];
        let mut length = [0; 4];
        file.read_exact(&mut magic)?;
        file.read_exact(&mut length)?;
        let length = u32::from_le_bytes(length);
        if &magic != FORMAT || length == 0 || length > MAX_INDEX {
            return Err(invalid());
        }
        let mut index = vec![0; length as usize];
        file.read_exact(&mut index)?;
        let Index { regions } = serde_json::from_slice(&index)?;
        let data_offset = 12 + u64::from(length);
        let mut end = data_offset;
        if regions.is_empty() {
            return Err(invalid());
        }
        for (i, region) in regions.iter().enumerate() {
            let [west, south, east, north] = region.extent;
            if region.id.is_empty() || region.id.len() > 64
                || !region.id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
                || (i > 0 && regions[i - 1].id >= region.id)
                || !(-180. <= west && west < east && east <= 180.)
                || !(-90. <= south && south < north && north <= 90.)
                || region.size.iter().any(|&s| !(32..=2048).contains(&s) || s % 32 != 0)
                || region.sources.is_empty() || region.sources.iter().any(|source| source.is_empty())
                || region.offset != end - data_offset
                || !(1..=6 * 1024 * 1024).contains(&region.bytes)
            {
                return Err(invalid());
            }
            end += u64::from(region.bytes);
        }
        if file.metadata()?.len() != end {
            return Err(invalid());
        }
        Ok(Self { path: path.to_owned(), data_offset, regions })
    }

    pub fn read(&self, index: usize) -> io::Result<Vec<u8>> {
        let region = &self.regions[index];
        let mut file = File::open(&self.path)?;
        file.seek(SeekFrom::Start(self.data_offset + region.offset))?;
        let mut packed = vec![0; region.bytes as usize];
        file.read_exact(&mut packed)?;
        let bytes = mips(region.size).map(|(_, _, n)| n).sum();
        let blocks = zstd::bulk::decompress(&packed, bytes)?;
        if blocks.len() != bytes {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "Incorrect terrain detail mip size"));
        }
        Ok(blocks)
    }
}

fn margin([west, south, east, north]: [f64; 4], corners: [[f64; 2]; 4]) -> f64 {
    corners.into_iter().fold(1., |margin, [lon, lat]| {
        let x = (lon - west) / (east - west);
        let y = (lat - south) / (north - south);
        margin.min(x).min(y).min(1. - x).min(1. - y)
    })
}

pub fn viewport(camera: &Camera, size: [u32; 2]) -> Option<[[f64; 2]; 4]> {
    let [w, h] = size.map(f64::from);
    Some([
        geographic(camera.vector([0., 0.], size)?),
        geographic(camera.vector([w, 0.], size)?),
        geographic(camera.vector([0., h], size)?),
        geographic(camera.vector([w, h], size)?),
    ])
}

pub fn extent_weight(extent: [f64; 4], corners: [[f64; 2]; 4]) -> f32 {
    smooth(0., 0.09, margin(extent, corners)) as f32
}

fn near_longitude(lon: f64, reference: f64) -> f64 {
    reference + (lon - reference + 180.).rem_euclid(360.) - 180.
}

fn view_extent(corners: [[f64; 2]; 4], center: f64) -> [f64; 4] {
    corners.into_iter().fold([f64::INFINITY, 90., f64::NEG_INFINITY, -90.],
        |[west, south, east, north], [lon, lat]| {
            let lon = near_longitude(lon, center);
            [west.min(lon), south.min(lat), east.max(lon), north.max(lat)]
        })
}

fn overlap([west, south, east, north]: [f64; 4], view: [f64; 4], center: f64) -> f64 {
    let midpoint = (west + east) * 0.5;
    let shift = near_longitude(midpoint, center) - midpoint;
    let width = (view[2].min(east + shift) - view[0].max(west + shift)).max(0.);
    let height = (view[3].min(north) - view[1].max(south)).max(0.);
    width * height
}

pub struct Stream {
    pub catalogue: Arc<Catalogue>,
    pub resident: Option<usize>,
    wanted: Option<usize>,
    inflight: Option<usize>,
    failed: HashSet<usize>,
    time: Option<Instant>,
    pub weight: f32,
    target_weight: f32,
}

impl Stream {
    pub fn new(catalogue: Catalogue) -> Self {
        Self { catalogue: Arc::new(catalogue), resident: None, wanted: None, inflight: None,
               failed: HashSet::new(), time: None, weight: 0., target_weight: 0. }
    }

    pub fn update(&mut self, camera: &Camera, size: [u32; 2], enabled: bool, now: Instant) -> Option<usize> {
        let corners = (enabled && camera.mpp < MAX_MPP).then(|| viewport(camera, size)).flatten();
        self.wanted = corners.and_then(|corners| {
            let center = camera.coordinates()[0];
            let view = view_extent(corners, center);
            self.catalogue.regions.iter().enumerate()
                .filter(|(index, _)| !self.failed.contains(index))
                .map(|(index, region)| (index, overlap(region.extent, view, center)))
                .filter(|&(_, area)| area > 0.)
                .max_by(|a, b| a.1.total_cmp(&b.1))
                .map(|(index, _)| index)
        });
        let scale = 1. - smooth(75., MAX_MPP, camera.mpp) as f32;
        self.target_weight = self.wanted.filter(|&index| self.resident == Some(index)).map_or(0., |_| scale);
        let step = self.time.replace(now).map_or(0., |previous| (now - previous).as_secs_f32().min(1./30.) / 0.18);
        // Coverage fades in the shader. A newly decoded region ramps up
        // together so rendering never exposes a half-uploaded detail layer.
        self.weight = (self.weight + step).min(self.target_weight);
        self.wanted.filter(|&id| self.resident != Some(id) && self.inflight.is_none())
    }

    pub fn requested(&mut self, id: usize) { self.inflight = Some(id); }

    pub fn completed(&mut self, id: usize, success: bool) -> bool {
        self.inflight = None;
        if !success {
            self.failed.insert(id);
            return false;
        }
        if self.wanted != Some(id) { return false; }
        self.resident = Some(id);
        self.weight = 0.;
        true
    }

    pub fn fading(&self) -> bool { self.weight < self.target_weight }

    pub fn status(&self) -> serde_json::Value {
        serde_json::json!({
            "available_regions":self.catalogue.regions.len(),
            "resident":self.resident.map(|i| &self.catalogue.regions[i]),
            "loading":self.inflight.is_some(),
            "failed_regions":self.failed.len(),
            "weight":self.weight,
            "texture_bytes":self.resident.map_or(0, |i| mips(self.catalogue.regions[i].size).map(|(_,_,n)| n).sum()),
        })
    }
}
