use crate::battlefield_terrain::REGION_BOUNDS;
use serde::{Deserialize, Serialize};
use std::f64::consts::{FRAC_PI_2, FRAC_PI_4};

// The military overlay uses the Paris seed's shifted Lambert-93 origin.
// Its square cells are independent of the clipped formal land polygons.
const GRID_ORIGIN: [f64; 2] = [648_000.0, 6_862_000.0];
const FALSE_ORIGIN: [f64; 2] = [700_000.0, 6_600_000.0];
const MERIDIAN_DEG: f64 = 3.0;
// RGF93 / GRS80: a=6378137, 1/f=298.257222101, lat0=46.5, parallels 49 and 44.
const ECCENTRICITY: f64 = 0.081_819_191_042_815_79;
const CONE: f64 = 0.725_607_765_053_268_8;
const PROJECTION_SCALE: f64 = 11_754_255.426_096_005;
const RADIUS_AT_ORIGIN: f64 = 6_055_612.049_875_990_5;
const ROUNDOFF_METRES: f64 = 1e-7;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct MilitaryCell {
    pub size_km: u8,
    pub east: i32,
    pub north: i32,
}

impl MilitaryCell {
    pub fn at(lon_lat: [f64; 2], size_km: u8) -> Option<Self> {
        if !matches!(size_km, 25 | 50) || !(lon_lat[1] > 41.0 && lon_lat[1] < 52.0) {
            return None;
        }
        let [easting, northing] = project(lon_lat)?;
        let step = f64::from(size_km) * 1_000.0;
        let cell = Self {
            size_km,
            east: ((easting - GRID_ORIGIN[0] + ROUNDOFF_METRES) / step).floor() as i32,
            north: ((northing - GRID_ORIGIN[1] + ROUNDOFF_METRES) / step).floor() as i32,
        };
        cell.is_valid().then_some(cell)
    }

    pub fn id(self) -> String {
        format!(
            "military:l93_s{}_x{}_y{}",
            self.size_km, self.east, self.north
        )
    }

    pub fn is_valid(self) -> bool {
        // Coarse bounds for validating stored coordinates. The map owner mask
        // separately controls which on-screen points expose the grid.
        if !matches!(self.size_km, 25 | 50) {
            return false;
        }
        let [lon, lat] = self.center_lon_lat();
        (-8.0..=12.0).contains(&lon) && (40.0..=53.0).contains(&lat)
    }

    pub fn region(self) -> Self {
        if self.size_km == 25 {
            Self {
                size_km: 50,
                east: self.east.div_euclid(2),
                north: self.north.div_euclid(2),
            }
        } else {
            self
        }
    }

    pub fn bounds_m(self) -> [f64; 4] {
        let step = self.step_m();
        let west = GRID_ORIGIN[0] + f64::from(self.east) * step;
        let south = GRID_ORIGIN[1] + f64::from(self.north) * step;
        [west, south, west + step, south + step]
    }

    pub fn center_lon_lat(self) -> [f64; 2] {
        let [west, south, east, north] = self.bounds_m();
        unproject([(west + east) * 0.5, (south + north) * 0.5])
    }

    /// Local X increases east and local Z increases south. The 50 km grid
    /// shares Ridgevale's existing metre frame, with its center at [2500, 2500].
    pub fn local_to_lon_lat(self, [x, z]: [f64; 2]) -> [f64; 2] {
        let [west, _, _, north] = self.bounds_m();
        let minimum = self.local_minimum();
        unproject([west + (x - minimum), north - (z - minimum)])
    }

    pub fn local_at(self, lon_lat: [f64; 2]) -> Option<[f32; 2]> {
        let [easting, northing] = project(lon_lat)?;
        let [west, _, _, north] = self.bounds_m();
        let minimum = self.local_minimum();
        let maximum = minimum + self.step_m();
        let local = [minimum + (easting - west), minimum + (north - northing)];
        let bounds = (minimum - ROUNDOFF_METRES)..=(maximum + ROUNDOFF_METRES);
        (self.is_valid() && local.iter().all(|coordinate| bounds.contains(coordinate)))
            .then(|| local.map(|coordinate| coordinate.clamp(minimum, maximum) as f32))
    }

    pub fn highlight(self) -> [f32; 4] {
        [
            self.east as f32,
            self.north as f32,
            self.step_m() as f32,
            1.0,
        ]
    }

    fn local_minimum(self) -> f64 {
        if self.size_km == 50 {
            REGION_BOUNDS[0]
        } else {
            -self.step_m() * 0.5
        }
    }

    fn step_m(self) -> f64 {
        f64::from(self.size_km) * 1_000.0
    }
}

fn latitude_factor(phi: f64) -> f64 {
    let e_sin = ECCENTRICITY * phi.sin();
    ((1.0 - e_sin) / (1.0 + e_sin)).powf(ECCENTRICITY * 0.5)
}

fn project([lon, lat]: [f64; 2]) -> Option<[f64; 2]> {
    if !(-180.0..=180.0).contains(&lon) || !(lat.abs() < 90.0) {
        return None;
    }
    let phi = lat.to_radians();
    let t = (FRAC_PI_4 - phi * 0.5).tan() / latitude_factor(phi);
    let rho = PROJECTION_SCALE * t.powf(CONE);
    let theta = CONE * (lon - MERIDIAN_DEG).to_radians();
    Some([
        FALSE_ORIGIN[0] + rho * theta.sin(),
        FALSE_ORIGIN[1] + RADIUS_AT_ORIGIN - rho * theta.cos(),
    ])
}

fn unproject([easting, northing]: [f64; 2]) -> [f64; 2] {
    let x = easting - FALSE_ORIGIN[0];
    let y = RADIUS_AT_ORIGIN - (northing - FALSE_ORIGIN[1]);
    let t = (x.hypot(y) / PROJECTION_SCALE).powf(CONE.recip());
    let mut phi = FRAC_PI_2 - 2.0 * t.atan();
    for _ in 0..10 {
        phi = FRAC_PI_2 - 2.0 * (t * latitude_factor(phi)).atan();
    }
    [
        MERIDIAN_DEG + (x.atan2(y) / CONE).to_degrees(),
        phi.to_degrees(),
    ]
}
