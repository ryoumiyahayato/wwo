//! Historical resource geography shared by the map and simulation callers.
//! A record describes a place or land cover, with no inferred production or reserves.
use serde::Deserialize;
use std::{collections::HashMap, sync::OnceLock};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Category {
    Energy, Precious, BaseMetal, AlloyMetal, Chemical, Fertilizer, Construction, Gem, Renewable,
}

impl Category {
    pub const ALL: [Self; 9] = [
        Self::Energy, Self::Precious, Self::BaseMetal, Self::AlloyMetal, Self::Chemical,
        Self::Fertilizer, Self::Construction, Self::Gem, Self::Renewable,
    ];
    pub fn name(self) -> [&'static str; 2] {
        match self {
            Self::Energy => ["能源", "Energy"],
            Self::Precious => ["贵金属", "Precious metals"],
            Self::BaseMetal => ["基础金属", "Base metals"],
            Self::AlloyMetal => ["合金金属", "Alloy metals"],
            Self::Chemical => ["化工原料", "Chemical materials"],
            Self::Fertilizer => ["肥料原料", "Fertilizer materials"],
            Self::Construction => ["建筑原料", "Construction"],
            Self::Gem => ["宝石", "Gemstones"],
            Self::Renewable => ["可再生资源", "Renewables"],
        }
    }
}

macro_rules! resource_types {
    ($($kind:ident: $id:literal, $category:ident, $zh:literal, $en:literal, $commodity:expr;)*) => {
        #[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq, Hash)]
        pub enum ResourceType { $(#[serde(rename = $id)] $kind,)* }
        impl ResourceType {
            pub const ALL: &'static [Self] = &[$(Self::$kind,)*];
            pub fn id(self) -> &'static str { match self { $(Self::$kind => $id,)* } }
            pub fn category(self) -> Category { match self { $(Self::$kind => Category::$category,)* } }
            pub fn name(self) -> [&'static str; 2] { match self { $(Self::$kind => [$zh, $en],)* } }
            pub fn commodity_id(self) -> Option<&'static str> { match self { $(Self::$kind => $commodity,)* } }
        }
    }
}

resource_types! {
    Coal: "coal", Energy, "煤炭", "Coal", Some("coal");
    Oil: "oil", Energy, "石油", "Petroleum", Some("crude_petroleum");
    Gas: "natural_gas", Energy, "天然气", "Natural gas", None;
    Gold: "gold", Precious, "黄金", "Gold", None;
    Silver: "silver", Precious, "白银", "Silver", None;
    Platinum: "platinum", Precious, "铂金", "Platinum", None;
    Iron: "iron_ore", BaseMetal, "铁矿", "Iron ore", Some("iron_ore");
    Copper: "copper_ore", BaseMetal, "铜矿", "Copper ore", Some("copper_ore");
    Lead: "lead_ore", BaseMetal, "铅矿", "Lead ore", None;
    Zinc: "zinc_ore", BaseMetal, "锌矿", "Zinc ore", None;
    Tin: "tin_ore", BaseMetal, "锡矿", "Tin ore", None;
    Bauxite: "bauxite", BaseMetal, "铝土矿", "Bauxite", None;
    Manganese: "manganese_ore", AlloyMetal, "锰矿", "Manganese ore", None;
    Nickel: "nickel_ore", AlloyMetal, "镍矿", "Nickel ore", None;
    Chromium: "chromium_ore", AlloyMetal, "铬矿", "Chromium ore", None;
    Sulfur: "sulfur", Chemical, "硫磺", "Sulfur", Some("sulfur");
    Salt: "industrial_salt", Chemical, "工业盐", "Industrial salt", Some("salt");
    Phosphate: "phosphate_ore", Fertilizer, "磷矿", "Phosphate rock", None;
    Nitrate: "nitrate", Fertilizer, "硝石", "Nitrate", Some("nitrates");
    Potash: "potash", Fertilizer, "钾盐", "Potash", None;
    Stone: "stone", Construction, "石料", "Stone", None;
    Limestone: "limestone", Construction, "石灰石", "Limestone", Some("limestone");
    Aggregate: "aggregate", Construction, "砂石", "Sand and gravel", None;
    Clay: "clay", Construction, "黏土", "Clay", None;
    Diamond: "diamond", Gem, "钻石", "Diamond", None;
    Gemstone: "gemstone", Gem, "彩色宝石", "Colored gemstones", None;
    AgriculturalLand: "agricultural_land", Renewable, "农业土地", "Agricultural land", None;
    Forest: "forest", Renewable, "森林", "Forest", Some("timber");
    Pasture: "pasture", Renewable, "牧场", "Pasture", None;
    Fishery: "fishery", Renewable, "渔场", "Fishing grounds", Some("fish");
    FreshWater: "fresh_water", Renewable, "淡水", "Fresh water", None;
    Hydropower: "hydropower", Renewable, "水力", "Water power", None;
    Wildlife: "wildlife", Renewable, "野生生物", "Wildlife", None;
    SpecialPlants: "special_plants", Renewable, "特殊经济植物", "Specialty plants", None;
}

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum EntityKind { Occurrence, Deposit, Working, District }

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Development { Geological, Discovered, Working, Former, Unknown }

#[derive(Clone, Copy, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Evidence { Confirmed, Estimated, Unknown }

/// Coordinates are WGS84 longitude, latitude in degrees.
#[derive(Clone, Debug, Deserialize)]
#[serde(tag = "shape", content = "coordinates", rename_all = "snake_case")]
pub enum Geometry {
    Point([f64; 2]),
    /// Exterior ring followed by any interior rings.
    Polygon(Vec<Vec<[f64; 2]>>),
    Line(Vec<[f64; 2]>),
}

#[derive(Debug, Deserialize)]
pub struct Resource {
    pub resource_id: String,
    pub resource_type: ResourceType,
    pub kind: EntityKind,
    pub name: String,
    pub name_zh: Option<String>,
    pub variant: Option<String>,
    pub geometry: Geometry,
    pub spatial_accuracy_m: Option<u32>,
    pub valid_from: i32,
    /// Exclusive end year.
    pub valid_to: i32,
    pub discovered_on: Option<i32>,
    pub first_production_year: Option<i32>,
    pub last_production_year: Option<i32>,
    pub development_status: Development,
    pub place_id: Option<String>,
    pub region_id: Option<String>,
    pub deposit_id: Option<String>,
    pub attributes: Option<String>,
    pub evidence_status: Evidence,
    pub source: String,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Bounds {
    pub west: f64,
    pub south: f64,
    pub east: f64,
    pub north: f64,
}

impl Bounds {
    pub const WORLD: Self = Self { west: -180., south: -90., east: 180., north: 90. };

    fn longitude_intervals(self) -> impl Iterator<Item = [f64; 2]> {
        let intervals = if self.west <= self.east {
            [[self.west, self.east], [1., 0.]]
        } else {
            [[self.west, 180.], [-180., self.east]]
        };
        intervals.into_iter().filter(|[a, b]| a <= b)
    }

    fn intersects(self, other: Self) -> bool {
        self.south <= other.north && other.south <= self.north
            && self.longitude_intervals().any(|[w, e]| {
                other.longitude_intervals().any(|[a, b]| w <= b && a <= e)
            })
    }
}

impl Geometry {
    pub fn bounds(&self) -> Bounds {
        let mut result = Bounds { west: 180., south: 90., east: -180., north: -90. };
        let mut extend = |&[lon, lat]: &[f64; 2]| {
            result.west = result.west.min(lon);
            result.east = result.east.max(lon);
            result.south = result.south.min(lat);
            result.north = result.north.max(lat);
        };
        match self {
            Self::Point(point) => extend(point),
            Self::Polygon(rings) => rings.iter().flatten().for_each(extend),
            Self::Line(points) => points.iter().for_each(extend),
        }
        result
    }

    pub fn anchor(&self) -> [f64; 2] {
        match self {
            Self::Point(point) => *point,
            Self::Line(points) => points[points.len() / 2],
            Self::Polygon(_) => {
                let b = self.bounds();
                [(b.west + b.east) * 0.5, (b.south + b.north) * 0.5]
            }
        }
    }
}

pub struct Directory {
    records: Vec<Resource>,
    ids: HashMap<String, usize>,
    types: HashMap<ResourceType, Vec<usize>>,
    places: HashMap<String, Vec<usize>>,
    regions: HashMap<String, Vec<usize>>,
    bounds: Vec<Bounds>,
}

impl Directory {
    pub fn opening() -> &'static Self {
        static DIRECTORY: OnceLock<Directory> = OnceLock::new();
        DIRECTORY.get_or_init(|| {
            let records = [
                include_str!("../../../data/resource-geography/sites-1900.json"),
                include_str!("../../../data/resource-geography/mrds-1900.json"),
            ]
            .into_iter()
            .flat_map(|source| {
                serde_json::from_str::<Vec<Resource>>(source).expect("embedded opening resource sites")
            })
            .collect();
            let mut directory = Self {
                records, ids: HashMap::new(), types: HashMap::new(), places: HashMap::new(),
                regions: HashMap::new(), bounds: Vec::new(),
            };
            for (i, record) in directory.records.iter().enumerate() {
                assert!(directory.ids.insert(record.resource_id.clone(), i).is_none());
                directory.types.entry(record.resource_type).or_default().push(i);
                if let Some(place) = &record.place_id {
                    directory.places.entry(place.clone()).or_default().push(i);
                }
                if let Some(region) = &record.region_id {
                    directory.regions.entry(region.clone()).or_default().push(i);
                }
                directory.bounds.push(record.geometry.bounds());
            }
            directory
        })
    }

    pub fn by_id(&self, id: &str) -> Option<&Resource> {
        self.ids.get(id).map(|&i| &self.records[i])
    }

    pub fn by_place(&self, id: &str) -> impl Iterator<Item = &Resource> {
        self.places.get(id).into_iter().flatten().map(|&i| &self.records[i])
    }

    pub fn by_region(&self, id: &str) -> impl Iterator<Item = &Resource> {
        self.regions.get(id).into_iter().flatten().map(|&i| &self.records[i])
    }

    /// Returns records whose source bounds overlap the requested view, in stable order.
    pub fn in_view(&self, kind: ResourceType, bounds: Bounds, year: i32) -> impl Iterator<Item = &Resource> {
        self.types.get(&kind).into_iter().flatten().filter_map(move |&i| {
            let record = &self.records[i];
            (record.valid_from <= year && year < record.valid_to && self.bounds[i].intersects(bounds))
                .then_some(record)
        })
    }

    /// Nearby source anchors, in an angular window. Uncertainty stays on each record.
    pub fn near(&self, kind: ResourceType, [lon, lat]: [f64; 2], degrees: f64, year: i32) -> impl Iterator<Item = &Resource> {
        let degrees = degrees.clamp(0., 180.);
        let wrap = |x: f64| (x + 180.).rem_euclid(360.) - 180.;
        let (west, east) = if degrees == 180. { (-180., 180.) } else { (wrap(lon - degrees), wrap(lon + degrees)) };
        self.in_view(kind, Bounds { west, east, south: (lat - degrees).max(-90.), north: (lat + degrees).min(90.) }, year)
    }
}

const LAND_YEAR: i32 = 1900;
const STEP: f64 = 0.25;
const COLS: usize = 1440;
const ROWS: usize = 720;
const UNKNOWN: u16 = u16::MAX;
pub const LAND_SOURCE: &str = "https://luh.umd.edu/LUH2/LUH2_v2h_README.pdf";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GridCell {
    pub resource_type: ResourceType,
    pub col: u16,
    pub row: u16,
    pub steps: u16,
    /// Fractions in ten-thousandths of total grid-cell area. None means out of coverage.
    pub fraction_bp: Option<u16>,
}

impl GridCell {
    /// Coarser display aggregates keep their extent and have no independent identity.
    pub fn resource_id(self) -> Option<String> {
        (self.steps == 1).then(|| format!("grid:luh2-v2h-1900:{}:{}:{}", self.resource_type.id(), self.col, self.row))
    }

    pub fn bounds(self) -> Bounds {
        let west = f64::from(self.col) * STEP - 180.;
        let north = 90. - f64::from(self.row) * STEP;
        let span = f64::from(self.steps) * STEP;
        Bounds { west, south: north - span, east: west + span, north }
    }
}

pub struct LandGrid {
    kind: ResourceType,
    levels: [Vec<u16>; 3],
}

impl LandGrid {
    pub fn opening(kind: ResourceType) -> Option<&'static Self> {
        static CROPS: OnceLock<LandGrid> = OnceLock::new();
        static FOREST: OnceLock<LandGrid> = OnceLock::new();
        static PASTURE: OnceLock<LandGrid> = OnceLock::new();
        let (cell, bytes): (_, &[u8]) = match kind {
            ResourceType::AgriculturalLand => (&CROPS, include_bytes!("../../../data/resource-geography/agricultural_land.u16.zst")),
            ResourceType::Forest => (&FOREST, include_bytes!("../../../data/resource-geography/forest.u16.zst")),
            ResourceType::Pasture => (&PASTURE, include_bytes!("../../../data/resource-geography/pasture.u16.zst")),
            _ => return None,
        };
        Some(cell.get_or_init(|| {
            let raw = zstd::bulk::decompress(bytes, COLS * ROWS * 2).expect("embedded LUH2 grid");
            assert_eq!(raw.len(), COLS * ROWS * 2);
            let base: Vec<u16> = raw.chunks_exact(2).map(|b| u16::from_le_bytes([b[0], b[1]])).collect();
            let coarse = |steps| {
                let weight: Vec<f64> = (0..ROWS).map(|row| (90. - (row as f64 + 0.5) * STEP).to_radians().cos()).collect();
                let mut values = Vec::new();
                for row in (0..ROWS).step_by(steps) {
                    for col in (0..COLS).step_by(steps) {
                        let mut sum = 0.;
                        let mut area = 0.;
                        for yy in row..row + steps {
                            for &value in &base[yy * COLS + col..yy * COLS + col + steps] {
                                if value != UNKNOWN {
                                    sum += f64::from(value) * weight[yy];
                                    area += weight[yy];
                                }
                            }
                        }
                        values.push(if area > 0. { (sum / area).round() as u16 } else { UNKNOWN });
                    }
                }
                values
            };
            let one_degree = coarse(4);
            let four_degrees = coarse(16);
            Self { kind, levels: [base, one_degree, four_degrees] }
        }))
    }

    pub const fn year(&self) -> i32 { LAND_YEAR }

    pub fn by_id(id: &str) -> Option<GridCell> {
        let mut parts = id.strip_prefix("grid:luh2-v2h-1900:")?.split(':');
        let kind = ResourceType::ALL.iter().copied().find(|kind| Some(kind.id()) == parts.clone().next())?;
        parts.next();
        let (col, row) = (parts.next()?.parse().ok()?, parts.next()?.parse().ok()?);
        if parts.next().is_some() || col >= COLS || row >= ROWS { return None; }
        Some(Self::opening(kind)?.cell(col, row, 0))
    }

    pub fn at(&self, [lon, lat]: [f64; 2]) -> Option<GridCell> {
        if !lon.is_finite() || !(-90. ..=90.).contains(&lat) { return None; }
        let col = (((lon + 180.).rem_euclid(360.) / STEP) as usize).min(COLS - 1);
        let row = (((90. - lat) / STEP) as usize).min(ROWS - 1);
        Some(self.cell(col, row, 0))
    }

    fn cell(&self, col: usize, row: usize, level: usize) -> GridCell {
        let steps = [1, 4, 16][level];
        let value = self.levels[level][row / steps * (COLS / steps) + col / steps];
        GridCell { resource_type: self.kind, col: col as u16, row: row as u16, steps: steps as u16,
            fraction_bp: (value != UNKNOWN).then_some(value) }
    }

    /// Original cells at level 0, area-weighted overview at levels 1 and 2.
    pub fn in_view(&self, bounds: Bounds, level: usize) -> impl Iterator<Item = GridCell> + '_ {
        let level = level.min(2);
        let steps = [1, 4, 16][level];
        let span = STEP * steps as f64;
        let y0 = ((90. - bounds.north) / span).floor().clamp(0., (ROWS / steps) as f64) as usize;
        let y1 = ((90. - bounds.south) / span).ceil().clamp(0., (ROWS / steps) as f64) as usize;
        bounds.longitude_intervals().flat_map(move |[west, east]| {
            let x0 = ((west + 180.) / span).floor().clamp(0., (COLS / steps) as f64) as usize;
            let x1 = ((east + 180.) / span).ceil().clamp(0., (COLS / steps) as f64) as usize;
            (y0..y1).flat_map(move |row| (x0..x1).map(move |col| self.cell(col * steps, row * steps, level)))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opening_resource_ids_and_market_links_are_valid() {
        let commodities: serde_json::Value = serde_json::from_str(include_str!(
            "../../../data/alpha/commodity_market_1900.json"
        )).unwrap();
        for kind in ResourceType::ALL {
            if let Some(id) = kind.commodity_id() {
                assert!(commodities["commodities"].as_array().unwrap().iter()
                    .any(|commodity| commodity["commodity_id"] == id), "{id}");
            }
        }
        let directory = Directory::opening();
        let site = directory.by_id("history:miyanohara-shaft-1").unwrap();
        let deposit = directory.by_id(site.deposit_id.as_deref().unwrap()).unwrap();
        assert_eq!(site.kind, EntityKind::Working);
        assert_eq!(deposit.kind, EntityKind::Deposit);
        assert_eq!(deposit.resource_type, site.resource_type);
        let point = site.geometry.anchor();
        assert!(directory.near(ResourceType::Coal, point, 0.1, 1900).any(|other| other.resource_id == site.resource_id));
        assert!(directory.near(ResourceType::Coal, point, 0.1, 1901).next().is_none());
        assert!(directory.by_region("departement_fr_62")
            .any(|site| site.resource_id == "history:lens-pit-9-coal"));
        let older_working = directory.by_id("mrds:10073045:lead_ore").unwrap();
        assert_eq!(older_working.kind, EntityKind::Working);
        assert_eq!(older_working.first_production_year, Some(1885));
        assert_eq!(older_working.development_status, Development::Unknown);
        let later_working = directory.by_id("mrds:10073052:lead_ore").unwrap();
        assert_eq!(later_working.kind, EntityKind::Deposit);
        assert_eq!(later_working.development_status, Development::Discovered);
    }

    #[test]
    fn land_grid_keeps_zero_separate_from_missing() {
        let grid = LandGrid::opening(ResourceType::AgriculturalLand).unwrap();
        assert_eq!(grid.year(), 1900);
        let paris = grid.at([2.35, 48.86]).unwrap();
        assert!(paris.fraction_bp.unwrap() > 0);
        assert_eq!(LandGrid::by_id(&paris.resource_id().unwrap()), Some(paris));
        assert_eq!(grid.at([-140., 0.]).unwrap().fraction_bp, None);
        assert_eq!(grid.at([19., 24.]).unwrap().fraction_bp, Some(0));
    }
}
