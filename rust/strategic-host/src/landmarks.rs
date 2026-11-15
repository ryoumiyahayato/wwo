use crate::{camera::{self, Camera}, world::{Place, World}};
use bytemuck::{Pod, Zeroable};
use glam::{Mat3, Mat4, Vec3};
use serde::Deserialize;
use std::io;

const SHARDS: &[&[u8]] = &[
    include_bytes!("../../../data/local/paris_northern_france_1900.json"),
    include_bytes!("../../../data/local/london_westminster_1900.json"),
    include_bytes!("../../../data/local/berlin_transport_1900.json"),
    include_bytes!("../../../data/local/giza_pyramids_1900.json"),
];

macro_rules! model {
    ($name:literal, $file:literal, $symbol:literal) => {
        Asset {
            name: $name, symbol: $symbol,
            path: concat!("res://assets/landmarks/", $file),
            bytes: include_bytes!(concat!("../../../assets/landmarks/", $file)),
        }
    };
}

static ASSETS: &[Asset] = &[
    model!("Eiffel Tower", "eiffel_tower_1900.glb", "eiffel"),
    model!("Gare du Nord", "gare_du_nord_r41.glb", "station"),
    model!("Pont d’Iéna", "pont_iena_r41.glb", "bridge"),
    model!("Westminster Clock Tower", "westminster_clock_tower_1900.glb", "clock_tower"),
    model!("Westminster Bridge", "westminster_bridge_r41.glb", "bridge"),
    model!("Friedrichstraße station", "friedrichstrasse_1882_r41.glb", "station"),
    model!("Giza pyramids", "giza_pyramids_1900.glb", "pyramids"),
];

struct Asset {
    name: &'static str,
    symbol: &'static str,
    path: &'static str,
    bytes: &'static [u8],
}

#[derive(Deserialize)]
struct Shard { metadata: Metadata }
#[derive(Deserialize)]
struct Metadata { landmark_visuals: Vec<Landmark> }
#[derive(Deserialize)]
struct Point { coordinates: [f64; 2] }

#[derive(Deserialize)]
struct Landmark {
    id: String,
    display_name: String,
    geometry: Point,
    valid_from: String,
    valid_to: String,
    model_path: String,
    model_height_m: f64,
    model_base_width_m: f64,
    model_footprint_m: Option<[f64; 2]>,
    model_heading_degrees: f64,
    model_max_mpp: f64,
    model_admission_mpp: Option<f64>,
    model_lod_switch_mpp: Option<f64>,
    display_lon_lat: Option<[f64; 2]>,
    #[serde(default)]
    model_ground_datum_m: f64,
    symbol_max_mpp: f64,
    rank: u32,
}

pub struct Landmarks(Vec<(usize, usize, Landmark)>);

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
enum Lod { Single, Far, Near }

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct ModelKey { asset: usize, lod: Lod }

impl ModelKey {
    pub fn model(self) -> &'static str { ASSETS[self.asset].name }

    pub fn lod(self) -> &'static str {
        match self.lod { Lod::Single => "Single", Lod::Far => "Far", Lod::Near => "Near" }
    }
}

pub struct VisibleModel {
    pub key: ModelKey,
    pub place: usize,
    pub screen_bounds: [f32; 4],
    pub clip_from_model: [[f32; 4]; 4],
}

impl Landmarks {
    pub fn install(world: &mut World) -> io::Result<Self> {
        let mut models = Vec::new();
        for source in SHARDS {
            let shard: Shard = serde_json::from_slice(source)?;
            for landmark in shard.metadata.landmark_visuals {
                let Some(asset) = ASSETS.iter().position(|asset| asset.path == landmark.model_path)
                    else { continue };
                let model = &ASSETS[asset];
                let index = world.places.iter().position(|place| place.id == landmark.id);
                let place = Place {
                    id: landmark.id.clone(), name: model.name.into(),
                    name_zh: landmark.display_name.clone(), symbol: model.symbol.into(),
                    reference: true, display_symbol: true, selectable: true,
                    coordinates: landmark.geometry.coordinates, rank: landmark.rank,
                    max_mpp: landmark.symbol_max_mpp, from_date: landmark.valid_from.clone(),
                    to_date: landmark.valid_to.clone(),
                };
                let index = match index {
                    Some(index) => {
                        world.places[index] = place;
                        index
                    }
                    None => {
                        world.places.push(place);
                        world.places.len() - 1
                    }
                };
                models.push((index, asset, landmark));
            }
        }
        if models.len() != ASSETS.len() {
            return Err(io::Error::other("R68 landmark catalogue and models differ"));
        }
        Ok(Self(models))
    }

    pub fn contains(&self, place: usize) -> bool {
        self.0.iter().any(|(i, _, _)| *i == place)
    }

    pub fn visible(&self, date: &str, camera: &Camera, size: [u32; 2]) -> Vec<VisibleModel> {
        let pitch = camera.pitch();
        self.0.iter().filter_map(|(place, asset, row)| {
            row.project(*place, *asset, date, camera, pitch, size)
        }).collect()
    }

    pub fn focus(&self, place: usize) -> Option<([f64; 2], f64)> {
        let (_, _, row) = self.0.iter().find(|(i, _, _)| *i == place)?;
        let size = row.model_height_m.max(row.model_base_width_m);
        Some((row.anchor(), (size / 120.).clamp(1.5, 8.)))
    }
}

impl Landmark {
    fn anchor(&self) -> [f64; 2] { self.display_lon_lat.unwrap_or(self.geometry.coordinates) }

    fn project(&self, place: usize, asset: usize, date: &str, camera: &Camera, pitch: f64, size: [u32; 2]) -> Option<VisibleModel> {
        if camera.mpp > self.model_admission_mpp.unwrap_or(self.model_max_mpp)
            || !crate::ui::active(date, &self.valid_from, &self.valid_to) {
            return None;
        }
        let anchor = self.anchor();
        let [x, y] = camera.project(anchor, size)?;
        let [width, depth] = self.model_footprint_m.unwrap_or([self.model_base_width_m; 2]);
        let margin = (width.hypot(depth) + self.model_height_m) / camera.mpp;
        let [w, h] = size.map(f64::from);
        if x < -margin || x > w + margin || y < -margin || y > h + margin {
            return None;
        }

        // Meter axes on the same chart as the map and its selection markers.
        let (chart, _) = camera.projection(size);
        let [east, north, _] = camera::frame(anchor);
        let (sin, cos) = pitch.sin_cos();
        let screen_depth = h * camera.mpp;
        let scale = |axis| Vec3::new(
            (camera::dot(axis, chart[0]) * 2. / (w * camera.mpp)) as f32,
            (camera::dot(axis, chart[1]) * cos * 2. / screen_depth) as f32,
            (camera::dot(axis, chart[1]) * sin / (screen_depth * 4.)) as f32,
        );
        let up = Vec3::new(0., (sin * 2. / screen_depth) as f32, (-cos / (screen_depth * 4.)) as f32);
        let ground_depth = 0.5 + ((h * 0.5 - y) / h) * pitch.tan() / 4.;
        let origin = Vec3::new((x / w * 2. - 1.) as f32, (1. - y / h * 2.) as f32, ground_depth as f32)
            - up * self.model_ground_datum_m as f32;
        let chart_from_model = Mat4::from_cols(
            scale(east).extend(0.), up.extend(0.), scale(north.map(|n| -n)).extend(0.), origin.extend(1.),
        );
        let heading = Mat4::from_rotation_y(self.model_heading_degrees.to_radians() as f32);
        let transform = chart_from_model * heading;
        let [left, top, right, bottom] = [-0.5, 0.5].into_iter().flat_map(|x| {
            [-0.5, 0.5].into_iter().flat_map(move |z| {
                [0., self.model_height_m].into_iter().map(move |y| {
                    let p = transform.transform_point3(Vec3::new((x * width) as f32, y as f32, (z * depth) as f32));
                    [(1. + p.x) * w as f32 * 0.5, (1. - p.y) * h as f32 * 0.5]
                })
            })
        }).fold([f32::INFINITY, f32::INFINITY, f32::NEG_INFINITY, f32::NEG_INFINITY], |[l, t, r, b], [x, y]| {
            [l.min(x), t.min(y), r.max(x), b.max(y)]
        });
        let lod = match self.model_lod_switch_mpp {
            Some(limit) if camera.mpp <= limit => Lod::Near,
            Some(_) => Lod::Far,
            None => Lod::Single,
        };
        Some(VisibleModel {
            key: ModelKey { asset, lod }, place,
            clip_from_model: transform.to_cols_array_2d(),
            screen_bounds: [left - 3., top - 3., right - left + 6., bottom - top + 6.],
        })
    }
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct ModelVertex {
    position: [f32; 3],
    normal: [f32; 3],
    color: [f32; 4],
}

pub struct ModelMesh {
    pub vertices: Vec<ModelVertex>,
    pub indices: Vec<u32>,
}

pub fn decode(key: ModelKey) -> io::Result<ModelMesh> {
    let asset = &ASSETS[key.asset];
    let glb = gltf::Gltf::from_slice(asset.bytes).map_err(io::Error::other)?;
    let blob = glb.blob.as_deref().ok_or_else(|| io::Error::other("GLB has no mesh buffer"))?;
    let scene = glb.default_scene().or_else(|| glb.scenes().next())
        .ok_or_else(|| io::Error::other("GLB has no scene"))?;
    let mut model = ModelMesh { vertices: Vec::new(), indices: Vec::new() };
    for node in scene.nodes() {
        append(node, Mat4::IDENTITY, blob, key.lod, &mut model)?;
    }
    if model.indices.is_empty() {
        return Err(io::Error::other(format!("{} has no static triangles", asset.name)));
    }
    Ok(model)
}

fn append(node: gltf::Node<'_>, parent: Mat4, blob: &[u8], lod: Lod, model: &mut ModelMesh) -> io::Result<()> {
    if matches!((node.name(), lod), (Some("Near"), Lod::Far) | (Some("Far"), Lod::Near)) {
        return Ok(());
    }
    let transform = parent * Mat4::from_cols_array_2d(&node.transform().matrix());
    let normal_transform = Mat3::from_mat4(transform).inverse().transpose();
    if let Some(mesh) = node.mesh() {
        for primitive in mesh.primitives() {
            let reader = primitive.reader(|buffer| matches!(buffer.source(), gltf::buffer::Source::Bin).then_some(blob));
            let material = primitive.material().pbr_metallic_roughness();
            if primitive.mode() != gltf::mesh::Mode::Triangles || material.base_color_texture().is_some() {
                return Err(io::Error::other("expected the R68 static vertex-color material"));
            }
            let factor = material.base_color_factor();
            let positions = reader.read_positions().ok_or_else(|| io::Error::other("missing GLB positions"))?;
            let normals = reader.read_normals().ok_or_else(|| io::Error::other("missing GLB normals"))?;
            let mut colors = reader.read_colors(0).map(|c| c.into_rgba_f32());
            let count = positions.len() as u32;
            let base = model.vertices.len() as u32;
            for (position, normal) in positions.zip(normals) {
                let tint = colors.as_mut().and_then(Iterator::next).unwrap_or([1.; 4]);
                model.vertices.push(ModelVertex {
                    position: transform.transform_point3(position.into()).to_array(),
                    normal: (normal_transform * Vec3::from(normal)).normalize_or_zero().to_array(),
                    color: std::array::from_fn(|i| factor[i] * tint[i]),
                });
            }
            if let Some(indices) = reader.read_indices() {
                for index in indices.into_u32() {
                    if index >= count { return Err(io::Error::other("GLB index exceeds its primitive")); }
                    model.indices.push(base + index);
                }
            } else {
                model.indices.extend(base..base + count);
            }
        }
    }
    for child in node.children() {
        append(child, transform, blob, lod, model)?;
    }
    Ok(())
}
