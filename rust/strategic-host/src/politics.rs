use crate::{compact::Raster, ui::active, world::World};
use bytemuck::{Pod, Zeroable};
use serde::Deserialize;
use std::{fs::File, io::{self, Read}, path::Path};

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct FlagUniform {
    bounds: [f32; 4],
    transform: [f32; 4],
    rotation: [f32; 4],
    regional_frames: [[f32;4];12],
}

#[derive(Deserialize)]
pub struct PoliticalVisual {
    pub id: String,
    pub color: String,
    pub flag: u8,
    #[serde(default)]
    pub bounds: [f64; 4],
    #[serde(default)]
    regional_frames: Vec<[f32;4]>,
    #[serde(default)]
    scale: [f32; 2],
    #[serde(default)]
    offset: [f32; 2],
    #[serde(default)]
    rotation: f32,
    #[serde(default)]
    valid_from: String,
    #[serde(default)]
    valid_to: String,
}
#[derive(Deserialize)]
pub struct PoliticalVisuals {
    #[serde(default)]
    map_release: String,
    polities: Vec<PoliticalVisual>,
}

impl PoliticalVisuals {
    pub fn open(root: &Path, world: &World) -> io::Result<Self> {
        let result: Self = serde_json::from_reader(File::open(root.join("political-flags.json"))?)?;
        if !world.map_release.is_empty() && result.map_release != world.map_release {
            return Err(io::Error::other(format!(
                "领土旗纹资源版本不匹配。需要 {}，实际为 {:?}",
                world.map_release, result.map_release,
            )));
        }
        if result.polities.len() != world.polities.len()
            || result.polities.iter().zip(&world.polities).any(|(v, p)| v.id != p.id)
        {
            return Err(io::Error::other("political visuals and map identities differ"));
        }
        Ok(result)
    }

    pub fn record(&self, polity: usize) -> &PoliticalVisual {
        &self.polities[polity]
    }

    pub fn uniforms(&self, date: &str) -> [FlagUniform; 256] {
        let mut result = [FlagUniform::zeroed(); 256];
        for (i, flag) in self.polities.iter().enumerate() {
            if !flag.active(date) {
                continue;
            }
            let [sx, sy] = flag.scale;
            let [ox, oy] = flag.offset;
            let (sine, cosine) = flag.rotation.to_radians().sin_cos();
            let mut frames=flag.regional_frames.clone();
            frames.sort_by(|a,b|{
                let area=|r:&[f32;4]|(r[2]-r[0])*(r[3]-r[1]);
                area(a).total_cmp(&area(b))
            });
            frames.truncate(12);
            result[i + 1] = FlagUniform {
                bounds: flag.bounds.map(|x| x as f32),
                transform: [sx, sy, ox, oy],
                rotation: [cosine, sine, f32::from(flag.flag), frames.len() as f32],
                regional_frames:std::array::from_fn(|i|frames.get(i).copied().unwrap_or([0.;4])),
            };
        }
        result
    }

    pub fn read_atlas(path: &Path) -> io::Result<Raster> {
        Self::decode_atlas(File::open(path)?)
    }

    pub fn decode_atlas(source: impl Read) -> io::Result<Raster> {
        let mut reader = png::Decoder::new(source).read_info()?;
        let mut pixels = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut pixels)?;
        if info.color_type != png::ColorType::Rgba || info.bit_depth != png::BitDepth::Eight
            || !matches!([info.width, info.height], [2048,1024]|[4096,2048])
        {
            return Err(io::Error::other("invalid political flag atlas"));
        }
        pixels.truncate(info.buffer_size());
        Ok(Raster { size: [info.width, info.height], pixels })
    }
}
impl PoliticalVisual {
    pub fn active(&self, date: &str) -> bool {
        self.flag != 0 && World::active_politics(date) && active(date, &self.valid_from, &self.valid_to)
    }

    pub fn fallback_color(&self) -> [u8; 4] {
        let rgb = self.color.strip_prefix('#').and_then(|s| u32::from_str_radix(s, 16).ok());
        let value = rgb.unwrap_or(0x6b8075).to_be_bytes();
        [value[1], value[2], value[3], 255]
    }

    pub fn focus(&self, size: [u32; 2]) -> Option<([f64; 2], f64)> {
        crate::camera::fit_bounds(self.bounds,size)
    }
}
