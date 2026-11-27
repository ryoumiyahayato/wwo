use serde::Deserialize;
use std::{fs::File, io::{self, Read}, path::Path};

const ROWS: usize = 180;
const COLUMNS: usize = 360;
pub(crate) const PAGE_BYTES: usize = 1024 * 1024;
pub(crate) const PAGE_SLOTS: usize = 16;
const CELL_METRES: [f32; 4] = [64., 128., 256., 384.];
const DESCRIPTOR_WORDS: usize = 22;
pub(crate) const PAGE_DESCRIPTOR_WORDS: usize = DESCRIPTOR_WORDS + 1;
const WATER_BANDS: usize = 4096 / 32;

#[derive(Clone, Deserialize)]
pub(crate) struct RoadTile {
    pub(crate) file: String,
    pub(crate) bounds: [f64; 4],
    pub(crate) bytes: usize,
    pub(crate) features: usize,
    #[serde(default)]
    pub(crate) water_features: usize,
    pub(crate) years: [u16; 2],
}

impl RoadTile {
    pub(crate) fn valid(&self) -> bool {
        let [w, s, e, n] = self.bounds;
        self.file.ends_with(".wcr") && self.file.bytes().all(|c| c.is_ascii_alphanumeric() || b"-.".contains(&c))
            && -180. <= w && w < e && e <= 180. && -90. <= s && s < n && n <= 90.
            && (48..=PAGE_BYTES).contains(&self.bytes) && self.bytes % 4 == 0
            && ((self.features != 0) != (self.water_features != 0))
            && (1..self.years[1]).contains(&self.years[0]) && self.years[1] <= 9999
    }

    pub(crate) fn read(&self, root: &Path) -> io::Result<RoadPage> {
        let invalid = || io::Error::other("Invalid city road page");
        let mut file = File::open(root.join(&self.file))?;
        let mut header = [0; 12];
        file.read_exact(&mut header)?;
        let water = self.water_features != 0;
        let expected = if water { b"WWOCRD02" } else { b"WWOCRD01" };
        if &header[..8] != expected || u32::from_le_bytes(header[8..].try_into().unwrap()) as usize != self.bytes {
            return Err(invalid());
        }
        let mut decoder = zstd::stream::read::Decoder::new(file)?;
        decoder.window_log_max(20)?;
        let mut data = Vec::with_capacity(self.bytes);
        decoder.take((self.bytes + 1) as u64).read_to_end(&mut data)?;
        if data.len() != self.bytes { return Err(invalid()); }
        let len = data.len() / 4;
        let word = |offset: usize| u32::from_le_bytes(data[offset * 4..offset * 4 + 4].try_into().unwrap());
        let header = std::array::from_fn::<_, 8, _>(|i| f32::from_bits(word(i)));
        let [lon, lat, xs, ys, w, s, e, n] = header;
        if header.iter().any(|v| !v.is_finite()) || !(100. ..=120_000.).contains(&xs)
            || !(100_000. ..=120_000.).contains(&ys) || e - w != 4096. || n - s != 4096. {
            return Err(invalid());
        }
        let projected = [lon + w / xs, lat + s / ys, lon + e / xs, lat + n / ys];
        if projected.into_iter().zip(self.bounds).any(|(a, b)| (f64::from(a) - b).abs() > 0.00004) {
            return Err(invalid());
        }
        let offsets = std::array::from_fn::<_, 4, _>(|i| word(8 + i));
        let water_offset = if water {
            if len < 13 { return Err(invalid()); }
            let offset = word(12) as usize;
            if offset != 13 || offsets != [0; 4] || offset + 2 * WATER_BANDS > len {
                return Err(invalid());
            }
            let first_edge = offset + 2 * WATER_BANDS;
            for band in (offset..first_edge).step_by(2) {
                let (a, b) = (word(band) as usize, word(band + 1) as usize);
                if a < first_edge || a > b || b > len || (b - a) % 5 != 0 || b - a > 5 * 192 {
                    return Err(invalid());
                }
                for edge in (a..b).step_by(5) {
                    let [ax, ay, bx, by] = std::array::from_fn(|i| f32::from_bits(word(edge + i)));
                    if ![ax, ay, bx, by].iter().all(|v| v.is_finite()) || ay >= by
                        || !matches!(word(edge + 4), 1 | 2 | 4) { return Err(invalid()); }
                }
            }
            Some(offset as u32)
        } else { None };
        for (level, cells) in CELL_METRES.into_iter().enumerate().filter(|_| !water) {
            let first = offsets[level] as usize;
            let last = offsets.get(level + 1).map_or(len, |&end| end as usize);
            let side = (4096. / cells).ceil() as usize;
            if first < 12 || first >= last || last > len { return Err(invalid()); }
            let start = first + 2 + 2 * side * side;
            if start > last || word(first) as usize != side || word(first + 1) as usize != side {
                return Err(invalid());
            }
            for cell in (first + 2..start).step_by(2) {
                let (a, b) = (word(cell) as usize, word(cell + 1) as usize);
                if (a, b) != (0, 0) && (a < start || a >= b || b > last || (b - a) % 6 != 0 || b - a > 6 * 512) {
                    return Err(invalid());
                }
            }
            if (last - start) % 6 != 0 { return Err(invalid()); }
            for segment in (start..last).step_by(6) {
                if (segment..segment + 5).any(|i| !f32::from_bits(word(i)).is_finite())
                    || !(0.5..=40.).contains(&f32::from_bits(word(segment + 4)))
                    || (word(segment + 5) & 3) > 2 || word(segment + 5) > 30 {
                    return Err(invalid());
                }
            }
        }
        Ok(RoadPage { data, offsets, scale: [xs, ys], water_offset })
    }
}

pub(crate) struct RoadPage {
    pub(crate) data: Vec<u8>,
    offsets: [u32; 4],
    scale: [f32; 2],
    pub(crate) water_offset: Option<u32>,
}

impl RoadPage {
    pub(crate) fn descriptor(&self, base: u32, bounds: [f64; 4]) -> [u32; PAGE_DESCRIPTOR_WORDS] {
        let mut words = [0; PAGE_DESCRIPTOR_WORDS];
        words[..2].copy_from_slice(&[base, base]);
        words[2..6].copy_from_slice(&self.offsets.map(|offset| base + offset));
        words[6..10].copy_from_slice(&CELL_METRES.map(f32::to_bits));
        words[10..14].copy_from_slice(&bounds.map(|coordinate| (coordinate as f32).to_bits()));
        words[14..16].copy_from_slice(&self.scale.map(f32::to_bits));
        if self.water_offset.is_none() { words[20] = State::ReadyVector as u32; }
        words[22] = self.water_offset.map_or(0, |offset| base + offset);
        words
    }
}

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Pack {
    Core,
    Fringe,
}

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum State {
    Loading = 1,
    Missing = 2,
    ReadyVector = 3,
    ReadyEmpty = 4,
}

#[derive(Deserialize)]
struct Source {
    id: String,
    pack: Pack,
    state: State,
    // Decode references in the existing first-level and LOD packs.
    header_word: Option<usize>,
    road_word: usize,
    lod_words: usize,
    cells: [f32; 4],
    bounds: [f32; 4],
    metres_per_degree: [f32; 2],
    fade_m: f32,
    field_radius_m: f32,
    material: u32,
    raster_categories: u32,
    #[serde(default)]
    rings: Vec<Vec<[f32; 2]>>,
}

pub(crate) struct RoadSources(Vec<Source>);

impl RoadSources {
    pub(crate) fn append(storage: &mut Vec<u8>, fringe: u32) -> (Self, u32) {
        let sources: Vec<Source> = serde_json::from_slice(include_bytes!(
            "../../../data/world_map/historical/city_landscape_1900/road-sources.json"
        )).expect("embedded city road catalogue");
        // Precedence is defined by the order of the catalogue. Geometry keeps its native coordinates.
        let mut buckets = vec![Vec::<u32>::new(); ROWS * COLUMNS];
        let mut descriptors = Vec::new();
        for (index, source) in sources.iter().enumerate() {
            let base = match source.pack { Pack::Core => 0, Pack::Fringe => fringe };
            let word = |index| {
                let at = (base as usize + index) * 4;
                u32::from_le_bytes(storage[at..at + 4].try_into().expect("road pack header"))
            };
            let vector = matches!(source.state, State::ReadyVector);
            let header = if vector { source.header_word.map_or(base, |offset| base + word(offset)) } else { 0 };
            let mut roads = [0; 4];
            if vector {
                roads[0] = match source.pack { Pack::Core => word(source.road_word), Pack::Fringe => base + source.road_word as u32 };
                for (level, road) in roads.iter_mut().skip(1).enumerate() {
                    *road = base + word(source.lod_words + level);
                }
            }
            let mask = if source.rings.is_empty() { 0 } else {
                let offset = storage.len() as u32 / 4;
                append_words(storage, [source.rings.len() as u32]);
                for ring in &source.rings {
                    assert!(ring.len() >= 3, "short coverage ring in {}", source.id);
                    append_words(storage, [ring.len() as u32]);
                    append_words(storage, ring.iter().flatten().map(|coordinate| coordinate.to_bits()));
                }
                offset
            };
            let [west, south, east, north] = source.bounds;
            assert!(-180. <= west && west < east && east <= 180. && -90. <= south && south < north && north <= 90.,
                "invalid bounds in {}", source.id);
            let column = |longitude: f32| ((longitude + 180.).floor() as usize).min(COLUMNS - 1);
            let row = |latitude: f32| ((latitude + 90.).floor() as usize).min(ROWS - 1);
            for y in row(south)..=row(north) {
                for x in column(west)..=column(east) {
                    buckets[y * COLUMNS + x].push(index as u32);
                }
            }
            descriptors.extend([base, header]);
            descriptors.extend(roads);
            descriptors.extend(source.cells.map(f32::to_bits));
            descriptors.extend(source.bounds.map(f32::to_bits));
            descriptors.extend(source.metres_per_degree.map(f32::to_bits));
            descriptors.extend([source.fade_m.to_bits(), source.field_radius_m.to_bits(), source.material,
                source.raster_categories, source.state as u32, mask]);
        }
        let catalogue = storage.len() as u32 / 4;
        append_words(storage, descriptors);
        let offsets = storage.len() as u32 / 4;
        let mut end = storage.len() as u32 / 4 + (buckets.len() + 1) as u32;
        for records in &buckets {
            append_words(storage, [end]);
            end += records.len() as u32;
        }
        append_words(storage, [end]);
        append_words(storage, buckets.into_iter().flatten());
        let header = storage.len() as u32 / 4;
        append_words(storage, [catalogue, offsets]);
        (Self(sources), header)
    }

    pub(crate) fn vector_bounds(&self) -> impl Iterator<Item = [f64; 4]> + '_ {
        self.0.iter().filter(|source| matches!(source.state, State::ReadyVector))
            .map(|source| source.bounds.map(f64::from))
    }
}

fn append_words(storage: &mut Vec<u8>, words: impl IntoIterator<Item = u32>) {
    storage.extend(words.into_iter().flat_map(u32::to_le_bytes));
}
