use crate::battlefield_terrain::REGION_BOUNDS;
use serde::{Deserialize, Serialize};
use std::f64::consts::{FRAC_PI_2, FRAC_PI_4};

// The original Paris seed's shifted Lambert-93 origin is stored implicitly
// in older saves. Keep that frame so saved metre positions retain their meaning.
const LEGACY_ORIGIN: [f64; 2] = [648_000.0, 6_862_000.0];
const FALSE_ORIGIN: [f64; 2] = [700_000.0, 6_600_000.0];
const MERIDIAN_DEG: f64 = 3.0;
// RGF93 / GRS80: a=6378137, 1/f=298.257222101, lat0=46.5, parallels 49 and 44.
const ECCENTRICITY: f64 = 0.081_819_191_042_815_79;
const CONE: f64 = 0.725_607_765_053_268_8;
const PROJECTION_SCALE: f64 = 11_754_255.426_096_005;
const RADIUS_AT_ORIGIN: f64 = 6_055_612.049_875_990_5;
const ROUNDOFF_METRES: f64 = 1e-7;

pub const GRID_EARTH_RADIUS_M: f64 = 6_371_008.8;
pub const BAND_LONGITUDE_DEGREES: f64 = 6.0;
pub const BAND_COUNT: u8 = 60;
pub const MAX_GRID_LATITUDE_DEGREES: f64 = 80.0;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MilitaryBand {
    longitude: u8,
}

impl MilitaryBand {
    pub fn at([lon, lat]: [f64; 2]) -> Option<Self> {
        if !(-180.0..=180.0).contains(&lon)
            || !(-MAX_GRID_LATITUDE_DEGREES..=MAX_GRID_LATITUDE_DEGREES).contains(&lat)
        {
            return None;
        }
        let lon = if lon == 180.0 { -180.0 } else { lon };
        let longitude =
            (((lon + 180.0) / BAND_LONGITUDE_DEGREES).floor() as u8).min(BAND_COUNT - 1);
        // Adding 180 can round a point west of a seam onto the seam itself.
        let longitude = if longitude > 0 && lon < band_edge(longitude) {
            longitude - 1
        } else {
            longitude
        };
        Some(Self { longitude })
    }

    pub fn index(self) -> u8 {
        self.longitude
    }

    /// The west edge is inclusive. The east edge belongs to the next band.
    pub fn geographic_bounds(self) -> Option<[f64; 4]> {
        (self.longitude < BAND_COUNT).then(|| {
            [
                band_edge(self.longitude),
                -MAX_GRID_LATITUDE_DEGREES,
                band_edge(self.longitude + 1),
                MAX_GRID_LATITUDE_DEGREES,
            ]
        })
    }

    fn central_meridian(self) -> Option<f64> {
        let [west, _, east, _] = self.geographic_bounds()?;
        Some((west + east) * 0.5)
    }

    // Spherical transverse equidistant coordinates. X measures the normal
    // arc to the central meridian, Y the arc along it. The northing scale
    // differs from ground distance by at most sec(3 degrees) within a band.
    pub fn project(self, [lon, lat]: [f64; 2]) -> Option<[f64; 2]> {
        if !(-180.0..=180.0).contains(&lon) || !(-90.0..=90.0).contains(&lat) {
            return None;
        }
        let (sin_lat, cos_lat) = lat.to_radians().sin_cos();
        let delta = wrap_longitude(lon - self.central_meridian()?).to_radians();
        Some([
            GRID_EARTH_RADIUS_M * (cos_lat * delta.sin()).asin(),
            GRID_EARTH_RADIUS_M * sin_lat.atan2(cos_lat * delta.cos()),
        ])
    }

    fn unproject(self, [east, north]: [f64; 2]) -> Option<[f64; 2]> {
        let (sin_cross, cos_cross) = (east / GRID_EARTH_RADIUS_M).sin_cos();
        let (sin_along, cos_along) = (north / GRID_EARTH_RADIUS_M).sin_cos();
        Some([
            wrap_longitude(
                self.central_meridian()? + sin_cross.atan2(cos_cross * cos_along).to_degrees(),
            ),
            (cos_cross * sin_along).asin().to_degrees(),
        ])
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct MilitaryCell {
    pub size_km: u8,
    pub east: i32,
    pub north: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub band: Option<MilitaryBand>,
}

impl MilitaryCell {
    pub fn at(lon_lat: [f64; 2], size_km: u8) -> Option<Self> {
        if !matches!(size_km, 1 | 5 | 25 | 50) {
            return None;
        }
        let band = MilitaryBand::at(lon_lat)?;
        let [east, north] = band.project(lon_lat)?;
        Some(Self::projected_cell([east, north], size_km, Some(band)))
    }

    pub fn legacy_at(lon_lat: [f64; 2], size_km: u8) -> Option<Self> {
        if !matches!(size_km, 25 | 50) {
            return None;
        }
        let [east, north] = legacy_project(lon_lat)?;
        let cell = Self::projected_cell(
            [east - LEGACY_ORIGIN[0], north - LEGACY_ORIGIN[1]],
            size_km,
            None,
        );
        cell.is_valid().then_some(cell)
    }

    fn projected_cell([east, north]: [f64; 2], size_km: u8, band: Option<MilitaryBand>) -> Self {
        let step = f64::from(size_km) * 1_000.0;
        Self {
            size_km,
            east: ((east + ROUNDOFF_METRES) / step).floor() as i32,
            north: ((north + ROUNDOFF_METRES) / step).floor() as i32,
            band,
        }
    }

    pub fn id(self) -> String {
        let chart = if let Some(band) = self.band {
            format!("teqd_z{}", band.index())
        } else {
            String::from("l93")
        };
        format!(
            "military:{chart}_s{}_x{}_y{}",
            self.size_km, self.east, self.north
        )
    }

    pub fn is_valid(self) -> bool {
        let Some(band) = self.band else {
            if !matches!(self.size_km, 25 | 50) {
                return false;
            }
            let [lon, lat] = self.center_lon_lat();
            return (-8.0..=12.0).contains(&lon) && (40.0..=53.0).contains(&lat);
        };
        if band.index() >= BAND_COUNT || !matches!(self.size_km, 1 | 5 | 25 | 50) {
            return false;
        }
        // At the nearest northing to the equator, the band is widest and the
        // latitude limit cuts the least. More distant rows cannot intersect
        // if this row misses the cell. Test the clipped cell, not its center.
        let [min_x, min_y, max_x, max_y] = self.bounds_m();
        let near_y = 0.0_f64.clamp(min_y, max_y).abs() / GRID_EARTH_RADIUS_M;
        if near_y >= FRAC_PI_2 {
            return false;
        }
        let near_x = 0.0_f64.clamp(min_x, max_x).abs();
        let far_x = min_x.abs().max(max_x.abs());
        let band_limit = GRID_EARTH_RADIUS_M
            * (near_y.cos() * (BAND_LONGITUDE_DEGREES * 0.5).to_radians().tan()).atan();
        let latitude_limit = GRID_EARTH_RADIUS_M
            * (MAX_GRID_LATITUDE_DEGREES.to_radians().sin() / near_y.sin())
                .min(1.0)
                .acos();
        near_x.max(latitude_limit) <= far_x.min(band_limit) + ROUNDOFF_METRES
    }

    pub fn parent(self) -> Option<Self> {
        let size_km = match self.size_km {
            1 if self.band.is_some() => 5,
            5 if self.band.is_some() => 25,
            25 => 50,
            _ => return None,
        };
        Some(self.containing_cell(size_km))
    }

    pub fn region(self) -> Self {
        if matches!((self.band, self.size_km), (_, 25) | (Some(_), 1 | 5)) {
            self.containing_cell(50)
        } else {
            self
        }
    }

    fn containing_cell(self, size_km: u8) -> Self {
        let ratio = i32::from(size_km / self.size_km);
        Self {
            size_km,
            east: self.east.div_euclid(ratio),
            north: self.north.div_euclid(ratio),
            band: self.band,
        }
    }

    pub fn bounds_m(self) -> [f64; 4] {
        let step = self.step_m();
        let [origin_x, origin_y] = if self.band.is_some() {
            [0.0; 2]
        } else {
            LEGACY_ORIGIN
        };
        let west = origin_x + f64::from(self.east) * step;
        let south = origin_y + f64::from(self.north) * step;
        [west, south, west + step, south + step]
    }

    pub fn center_lon_lat(self) -> [f64; 2] {
        let [west, south, east, north] = self.bounds_m();
        self.unproject([(west + east) * 0.5, (south + north) * 0.5])
    }

    /// Local X increases east and local Z increases south. The 50 km grid
    /// shares Ridgevale's existing metre frame, with its center at [2500, 2500].
    pub fn local_to_lon_lat(self, [x, z]: [f64; 2]) -> [f64; 2] {
        let [west, _, _, north] = self.bounds_m();
        let minimum = self.local_minimum();
        self.unproject([west + (x - minimum), north - (z - minimum)])
    }

    pub fn local_at(self, lon_lat: [f64; 2]) -> Option<[f32; 2]> {
        let [easting, northing] = if let Some(band) = self.band {
            if MilitaryBand::at(lon_lat) != Some(band) {
                return None;
            }
            band.project(lon_lat)?
        } else {
            legacy_project(lon_lat)?
        };
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

    pub fn step_m(self) -> f64 {
        f64::from(self.size_km) * 1_000.0
    }

    fn unproject(self, xy: [f64; 2]) -> [f64; 2] {
        if let Some(band) = self.band {
            band.unproject(xy).unwrap_or([f64::NAN; 2])
        } else {
            legacy_unproject(xy)
        }
    }
}

fn band_edge(index: u8) -> f64 {
    f64::from(index) * BAND_LONGITUDE_DEGREES - 180.0
}

fn wrap_longitude(lon: f64) -> f64 {
    (lon + 180.0).rem_euclid(360.0) - 180.0
}

fn latitude_factor(phi: f64) -> f64 {
    let e_sin = ECCENTRICITY * phi.sin();
    ((1.0 - e_sin) / (1.0 + e_sin)).powf(ECCENTRICITY * 0.5)
}

fn legacy_project([lon, lat]: [f64; 2]) -> Option<[f64; 2]> {
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

fn legacy_unproject([easting, northing]: [f64; 2]) -> [f64; 2] {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn global_grid_has_exact_metric_parents() {
        for coordinates in [
            [106.83, -6.15],
            [-58.42, -34.61],
            [179.999, -17.0],
            [-180.0, 80.0],
            [0.0, -80.0],
            [180.0, 79.99],
        ] {
            let mut cell = MilitaryCell::at(coordinates, 1).unwrap();
            let region = cell.region();
            for size in [1, 5, 25, 50] {
                assert!(cell.is_valid());
                assert_eq!(cell, MilitaryCell::at(coordinates, size).unwrap());
                assert_eq!(cell.region(), region);
                let [west, south, east, north] = cell.bounds_m();
                let step = 1000.0 * f64::from(size);
                assert_eq!([east - west, north - south], [step; 2]);

                let grid = cell.band.unwrap();
                let [x, y] = grid.project(coordinates).unwrap();
                assert!((west - ROUNDOFF_METRES..=east + ROUNDOFF_METRES).contains(&x));
                assert!((south - ROUNDOFF_METRES..=north + ROUNDOFF_METRES).contains(&y));

                if let Some(parent) = cell.parent() {
                    let [x0, y0, x1, y1] = parent.bounds_m();
                    assert!(x0 <= west && y0 <= south && x1 >= east && y1 >= north);
                    cell = parent;
                }
            }
            let local = region.local_at(coordinates).unwrap().map(f64::from);
            let recovered = region.local_to_lon_lat(local);
            let grid = region.band.unwrap();
            let [x0, y0] = grid.project(coordinates).unwrap();
            let [x1, y1] = grid.project(recovered).unwrap();
            assert!((x1 - x0).hypot(y1 - y0) < 0.003);
        }
    }

    #[test]
    fn geographic_edges_have_one_band() {
        for longitude in 0..BAND_COUNT {
            let band = MilitaryBand { longitude };
            let [west, south, east, north] = band.geographic_bounds().unwrap();
            for lat in [south, -34.61, 0.0, 49.0, north] {
                assert_eq!(MilitaryBand::at([west, lat]), Some(band));
                assert_eq!(MilitaryBand::at([east - 1e-12, lat]), Some(band));
                assert_eq!(
                    MilitaryBand::at([east, lat]).unwrap().index(),
                    (longitude + 1) % BAND_COUNT
                );
            }
        }
        assert_eq!(
            MilitaryCell::at([-180.0, 55.0], 1),
            MilitaryCell::at([180.0, 55.0], 1)
        );
        let left = MilitaryCell::at([-1e-9, 78.5], 50).unwrap();
        let right = MilitaryCell::at([0.0, 78.5], 50).unwrap();
        assert_ne!(left.id(), right.id());
        assert!(left.is_valid() && right.is_valid());
        assert!(left.local_at([0.0, 78.5]).is_none());
        assert!(right.local_at([-1e-9, 78.5]).is_none());
        assert!(!MilitaryCell { east: 2, ..right }.is_valid());
        assert!(MilitaryCell::at([-99.0, 80.001], 1).is_none());
        assert!(MilitaryCell::at([65.0, -80.001], 1).is_none());
        assert!(MilitaryCell::at([0.0, f64::NAN], 1).is_none());
        assert!(MilitaryCell::at([0.0, 0.0], 2).is_none());
    }

    #[test]
    fn legacy_json_retains_lambert_93_identity_and_local_metres() {
        let old: MilitaryCell =
            serde_json::from_str(r#"{"size_km":50,"east":1,"north":0}"#).unwrap();
        assert!(old.is_valid());
        assert_eq!(old.id(), "military:l93_s50_x1_y0");
        assert!(old.band.is_none());
        let center = old.local_to_lon_lat([2500.0, 2500.0]);
        assert_eq!(MilitaryCell::legacy_at(center, 50), Some(old));
        assert_eq!(old.local_at(center), Some([2500.0, 2500.0]));
        assert_eq!(
            serde_json::to_string(&old).unwrap(),
            r#"{"size_km":50,"east":1,"north":0}"#
        );
    }
}
