//! FAO–IIASA GAEZ v4 low-input suitability, using the 1961–1990 climate reference.
use std::{fs::File, io::{self, Read}, path::{Path, PathBuf}, sync::OnceLock};

use flate2::read::ZlibDecoder;
use serde::Deserialize;

use super::{blocks_in_view, row_areas, Bounds, CellId, COLS, ROWS};

#[derive(Debug, Deserialize)]
pub struct Crop {
    pub code: String,
    pub zh: String,
    pub en: String,
    pub commodity_id: Option<String>,
}

pub fn crops() -> &'static [Crop] {
    static CROPS: OnceLock<Vec<Crop>> = OnceLock::new();
    CROPS.get_or_init(|| {
        serde_json::from_str(include_str!("../../../../../data/resource-geography/gaez-crops.json"))
            .expect("embedded GAEZ crop catalogue")
    })
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Scenario {
    Rainfed,
    GravityIrrigation,
}

impl Scenario {
    fn source_code(self) -> char {
        match self {
            Self::Rainfed => 'r',
            Self::GravityIrrigation => 'g',
        }
    }
}

#[derive(Default)]
pub struct Directory {
    root: PathBuf,
    available: Vec<usize>,
}

impl Directory {
    pub fn open(runtime_data: &Path) -> Self {
        let mut directory = Self {
            root: runtime_data.join("resource-geography/gaez-v4"),
            available: Vec::new(),
        };
        directory.available = crops().iter().enumerate().filter_map(|(index, crop)| {
            directory.has(crop, Scenario::Rainfed).then_some(index)
        }).collect();
        directory
    }

    pub fn available(&self) -> &[usize] { &self.available }

    fn path(&self, crop: &Crop, scenario: Scenario) -> PathBuf {
        self.root.join(format!("{}-{}.u8.z", crop.code, scenario.source_code()))
    }

    pub fn has(&self, crop: &Crop, scenario: Scenario) -> bool {
        self.path(crop, scenario).is_file()
    }

    pub fn load(&self, index: usize, scenario: Scenario) -> io::Result<Band> {
        let crop = crops().get(index).ok_or_else(|| io::Error::other("unknown GAEZ crop"))?;
        let file = File::open(self.path(crop, scenario))?;
        let mut classes = Vec::with_capacity(ROWS * COLS);
        ZlibDecoder::new(file).take((ROWS * COLS + 1) as u64).read_to_end(&mut classes)?;
        if classes.len() != ROWS * COLS || classes.iter().any(|&class| class > 9) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "invalid GAEZ suitability band"));
        }
        Ok(Band { index, scenario, classes, overview: Default::default() })
    }
}

pub struct Band {
    pub index: usize,
    pub scenario: Scenario,
    classes: Vec<u8>,
    overview: [OnceLock<Vec<u8>>; 2],
}

impl Band {
    pub fn crop(&self) -> &'static Crop { &crops()[self.index] }

    /// GAEZ's original classes. 1 is highest, 8 unsuitable, 9 water.
    pub fn class_at(&self, cell: CellId) -> Option<u8> {
        let class = self.classes[usize::from(cell.row) * COLS + usize::from(cell.col)];
        (class != 0).then_some(class)
    }

    /// At wide scales show the area-dominant land class. Cell picks still use
    /// the original 5′ index. Unknown and water do not contribute to this class.
    pub fn in_view(&self, bounds: Bounds, level: usize) -> impl Iterator<Item = (Bounds, u8)> + '_ {
        let level = level.min(2);
        let steps = [1, 12, 48][level];
        let values = if level == 0 { &self.classes } else {
            self.overview[level - 1].get_or_init(|| self.aggregate(steps))
        };
        blocks_in_view(bounds, steps).filter_map(move |(cell, index)| {
            let class = values[index];
            (1..=8).contains(&class).then(|| (cell.block_bounds(steps), class))
        })
    }

    fn aggregate(&self, steps: usize) -> Vec<u8> {
        let mut result = Vec::with_capacity(ROWS * COLS / (steps * steps));
        for row in (0..ROWS).step_by(steps) {
            for col in (0..COLS).step_by(steps) {
                let mut area = [0.; 8];
                for dy in row..row + steps {
                    let start = dy * COLS + col;
                    let cell_area = row_areas()[dy];
                    for &class in &self.classes[start..start + steps] {
                        if (1..=8).contains(&class) { area[usize::from(class - 1)] += cell_area; }
                    }
                }
                let (class, area) = area.iter().enumerate()
                    .max_by(|(_, a), (_, b)| a.total_cmp(b)).expect("eight GAEZ classes");
                result.push(if *area > 0. { class as u8 + 1 } else { 0 });
            }
        }
        result
    }
}
