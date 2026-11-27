use serde::Deserialize;

const ROWS: usize = 180;
const COLUMNS: usize = 360;

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
