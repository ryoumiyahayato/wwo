use serde::{Deserialize, Serialize};
use std::{fs, io::{self, Read}, path::Path};

pub const REGION_ID: &str = "training:cedar-rivergate-ridgevale:50km";
const REGION_BOUNDS: [f64; 4] = [-22_500., -22_500., 27_500., 27_500.];
const RIDGEVALE_BOUNDS: [f64; 4] = [-2_500., -2_500., 2_500., 2_500.];

#[derive(Deserialize)]
struct RegionManifest {
    schema: String,
    training_only: bool,
    bounds: [f64; 4],
    native_ridgevale_bounds: [f64; 4],
}

pub struct BattlefieldTerrain {
    region: HeightGrid,
    ridgevale: Option<HeightGrid>,
}

struct HeightGrid {
    width: usize,
    origin_m: f64,
    spacing_m: u32,
    heights: Vec<f32>,
}

#[derive(Debug, PartialEq, Serialize)]
pub struct HeightSample {
    pub height_m: f64,
    pub spacing_m: u32,
}

impl BattlefieldTerrain {
    pub fn open(root: &Path) -> io::Result<Self> {
        let region_root = root.join("continuous/assets");
        let manifest: RegionManifest = serde_json::from_reader(fs::File::open(region_root.join("region.json"))?)?;
        if manifest.schema != "continuous-training-region-v1" || !manifest.training_only
            || manifest.bounds != REGION_BOUNDS || manifest.native_ridgevale_bounds != RIDGEVALE_BOUNDS
        {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "unsupported training terrain manifest"));
        }
        let region = HeightGrid::open(&region_root.join("height_50m.f32"), 1001, REGION_BOUNDS[0], 50)?;
        let ridgevale_path = root.join("ridgevale/assets/height_4m.f32");
        let ridgevale = match HeightGrid::open(&ridgevale_path, 1251, RIDGEVALE_BOUNDS[0], 4) {
            Ok(grid) => Some(grid),
            Err(error) if error.kind() == io::ErrorKind::NotFound => None,
            Err(error) => return Err(error),
        };
        Ok(Self { region, ridgevale })
    }

    pub fn sample(&self, x_m: f64, z_m: f64) -> Option<HeightSample> {
        self.ridgevale.as_ref().and_then(|grid| grid.sample(x_m, z_m))
            .or_else(|| self.region.sample(x_m, z_m))
    }
}

impl HeightGrid {
    fn open(path: &Path, width: usize, origin_m: f64, spacing_m: u32) -> io::Result<Self> {
        let expected = width * width * size_of::<f32>();
        let mut bytes = Vec::with_capacity(expected);
        fs::File::open(path)?.take(expected as u64 + 1).read_to_end(&mut bytes)?;
        let invalid = || io::Error::new(io::ErrorKind::InvalidData, format!("invalid height grid: {}", path.display()));
        if bytes.len() != expected {
            return Err(invalid());
        }
        let heights: Vec<_> = bytes.chunks_exact(4).map(|sample| f32::from_le_bytes(sample.try_into().unwrap())).collect();
        if heights.iter().any(|height| !height.is_finite()) {
            return Err(invalid());
        }
        Ok(Self { width, origin_m, spacing_m, heights })
    }

    fn sample(&self, x_m: f64, z_m: f64) -> Option<HeightSample> {
        let spacing = f64::from(self.spacing_m);
        let last = self.width - 1;
        let edge_m = self.origin_m + last as f64 * spacing;
        if ![x_m, z_m].into_iter().all(|value| (self.origin_m..=edge_m).contains(&value)) {
            return None;
        }
        let fx = (x_m - self.origin_m) / spacing;
        let fz = (z_m - self.origin_m) / spacing;
        let x = (fx.floor() as usize).min(last - 1);
        let z = (fz.floor() as usize).min(last - 1);
        let tx = fx - x as f64;
        let tz = fz - z as f64;
        let index = z * self.width + x;
        let a = f64::from(self.heights[index]);
        let b = f64::from(self.heights[index + 1]);
        let c = f64::from(self.heights[index + self.width]);
        let d = f64::from(self.heights[index + self.width + 1]);
        // Preserve the b–c triangle diagonal used by the original mesh and collider.
        let height_m = if tx + tz <= 1. {
            a + (b - a) * tx + (c - a) * tz
        } else {
            d + (c - d) * (1. - tx) + (b - d) * (1. - tz)
        };
        Some(HeightSample { height_m, spacing_m: self.spacing_m })
    }
}
