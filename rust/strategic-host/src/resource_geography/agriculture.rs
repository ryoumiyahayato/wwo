//! HYDE 3.2.1 physical land-use estimates for 1900, in hectares.
use std::{fmt, sync::OnceLock};

use super::{Bounds, Evidence};

const COLS: usize = 4320;
const ROWS: usize = 2160;
const STEP: f64 = 1. / 12.;
const NO_DATA: f32 = -1.;

macro_rules! fields {
    ($($name:ident, $file:literal, $zh:literal, $en:literal;)*) => {
        #[derive(Clone, Copy, Debug, Eq, PartialEq)]
        pub enum Field { $($name),* }

        impl Field {
            pub fn name(self) -> [&'static str; 2] {
                match self { $(Self::$name => [$zh, $en]),* }
            }

            fn band(self) -> &'static Band {
                match self {
                    $(Self::$name => {
                        static BAND: OnceLock<Band> = OnceLock::new();
                        BAND.get_or_init(|| Band::load(include_bytes!(concat!(
                            "../../../../data/resource-geography/hyde-1900/", $file, ".f32.zst"
                        ))))
                    }),*
                }
            }
        }
    };
}

fields! {
    Land, "land_area", "陆地", "Land";
    Cropland, "cropland", "耕地", "Cropland";
    Grazing, "grazing", "放牧用地", "Grazing land";
    Pasture, "pasture", "牧场", "Pasture";
    Rangeland, "rangeland", "天然放牧地", "Natural rangeland";
    ConvertedRangeland, "conv_rangeland", "已转化放牧地", "Converted rangeland";
    Irrigated, "tot_irri", "灌溉农业", "Irrigated cropland";
    Rainfed, "tot_rainfed", "雨养农业", "Rainfed cropland";
    Rice, "tot_rice", "历史水稻", "Historical rice";
    IrrigatedRice, "ir_rice", "灌溉水稻", "Irrigated rice";
    RainfedRice, "rf_rice", "雨养水稻", "Rainfed rice";
}

impl Field {
    /// The crop identifier is shared with the commodity directory.
    pub fn commodity_id(self) -> Option<&'static str> {
        match self {
            Self::Rice | Self::IrrigatedRice | Self::RainfedRice => Some("rice"),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub struct CellId {
    row: u16,
    col: u16,
}

impl fmt::Display for CellId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "agri:wgs84-5m:{}:{}", self.row, self.col)
    }
}

impl CellId {
    pub fn at([lon, lat]: [f64; 2]) -> Option<Self> {
        if !lon.is_finite() || !(-90. ..=90.).contains(&lat) { return None; }
        let row = ((90. - lat) * 12.).floor() as usize;
        let col = ((lon + 180.).rem_euclid(360.) * 12.).floor() as usize;
        Some(Self { row: row.min(ROWS - 1) as u16, col: col.min(COLS - 1) as u16 })
    }

    pub fn by_id(id: &str) -> Option<Self> {
        let (row, col) = id.strip_prefix("agri:wgs84-5m:")?.split_once(':')?;
        let (row, col): (u16, u16) = (row.parse().ok()?, col.parse().ok()?);
        (usize::from(row) < ROWS && usize::from(col) < COLS).then_some(Self { row, col })
    }

    pub fn bounds(self) -> Bounds { self.block_bounds(1) }

    fn block_bounds(self, steps: usize) -> Bounds {
        let west = f64::from(self.col) * STEP - 180.;
        let north = 90. - f64::from(self.row) * STEP;
        let span = steps as f64 * STEP;
        Bounds { west, south: north - span, east: west + span, north }
    }

    pub fn area_ha(self) -> f64 { row_areas()[usize::from(self.row)] }

    pub fn hectares(self, field: Field) -> Option<f32> {
        let data = &field.band().hectares;
        let value = data[usize::from(self.row) * COLS + usize::from(self.col)];
        (value != NO_DATA).then_some(value)
    }

    pub fn evidence(self, field: Field) -> Evidence {
        if self.hectares(field).is_some() { Evidence::Estimated } else { Evidence::Unknown }
    }
}

fn row_areas() -> &'static [f64; ROWS] {
    static AREAS: OnceLock<[f64; ROWS]> = OnceLock::new();
    AREAS.get_or_init(|| {
        const A: f64 = 6_378_137.;
        const F: f64 = 1. / 298.257_223_563;
        let e2 = F * (2. - F);
        let e = e2.sqrt();
        let primitive = |row: usize| {
            let z = (90. - row as f64 * STEP).to_radians().sin();
            0.5 * (z / (1. - e2 * z * z) + (e * z).atanh() / e)
        };
        let factor = STEP.to_radians() * A * A * (1. - e2) / 10_000.;
        std::array::from_fn(|row| factor * (primitive(row) - primitive(row + 1)))
    })
}

struct Band {
    hectares: Vec<f32>,
    share: [OnceLock<Vec<f32>>; 2],
}

impl Band {
    fn load(bytes: &[u8]) -> Self {
        let raw = zstd::bulk::decompress(bytes, ROWS * COLS * 4).expect("embedded HYDE field");
        assert_eq!(raw.len(), ROWS * COLS * 4);
        let hectares = raw.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
        Self { hectares, share: Default::default() }
    }

    fn overview(&self, index: usize, steps: usize) -> &[f32] {
        self.share[index].get_or_init(|| {
            let mut shares = Vec::with_capacity(ROWS * COLS / (steps * steps));
            for row in (0..ROWS).step_by(steps) {
                for col in (0..COLS).step_by(steps) {
                    let mut total = 0.;
                    let mut covered = 0.;
                    for dy in 0..steps {
                        let source_row = row + dy;
                        let data = &self.hectares[source_row * COLS + col..source_row * COLS + col + steps];
                        let land = row_areas()[source_row];
                        for &value in data {
                            if value != NO_DATA {
                                total += f64::from(value);
                                covered += land;
                            }
                        }
                    }
                    shares.push(if covered > 0. { (total / covered) as f32 } else { NO_DATA });
                }
            }
            shares
        })
    }
}

/// Original cell boundaries at level 0. Overview blocks sum source areas
/// and divide by the physical area of cells with observations.
pub fn in_view(field: Field, bounds: Bounds, level: usize) -> impl Iterator<Item = (Bounds, f32)> {
    let level = level.min(2);
    let steps = [1, 12, 48][level];
    let span = STEP * steps as f64;
    let band = field.band();
    let overview = (level > 0).then(|| band.overview(level - 1, steps));
    let row_start = ((90. - bounds.north) / span).floor().clamp(0., (ROWS / steps) as f64) as usize;
    let row_end = ((90. - bounds.south) / span).ceil().clamp(0., (ROWS / steps) as f64) as usize;
    bounds.longitude_intervals().flat_map(move |[west, east]| {
        let col_start = ((west + 180.) / span).floor().clamp(0., (COLS / steps) as f64) as usize;
        let col_end = ((east + 180.) / span).ceil().clamp(0., (COLS / steps) as f64) as usize;
        (row_start..row_end).flat_map(move |row| {
            (col_start..col_end).filter_map(move |col| {
                let id = CellId { row: (row * steps) as u16, col: (col * steps) as u16 };
                let index = row * (COLS / steps) + col;
                let fraction = if let Some(overview) = overview {
                    overview[index]
                } else {
                    let hectares = band.hectares[index];
                    if hectares == NO_DATA { return None; }
                    hectares / id.area_ha() as f32
                };
                (fraction != NO_DATA).then(|| (id.block_bounds(steps), fraction.clamp(0., 1.)))
            })
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hyde_cells_keep_area_identity_and_unknown_distinct_from_zero() {
        let beauce = CellId::at([1.48, 48.36]).unwrap();
        assert_eq!(CellId::by_id(&beauce.to_string()), Some(beauce));
        assert!(beauce.area_ha() < CellId::at([0., 0.]).unwrap().area_ha());
        assert!(beauce.hectares(Field::Cropland).unwrap() > 0.);
        assert_eq!(beauce.hectares(Field::Rice), Some(0.));
        assert_eq!(CellId::at([-140., 0.]).unwrap().hectares(Field::Cropland), None);
    }
}
