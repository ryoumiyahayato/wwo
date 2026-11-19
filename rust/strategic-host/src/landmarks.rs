use crate::{camera::{self, Camera}, world::{Place, World}};
use bytemuck::{Pod, Zeroable};
use glam::{Mat3, Mat4, Vec3};
use serde::Deserialize;
use std::{collections::BTreeMap, io};

const R40_MODELS: &[u8] = include_bytes!("../../../assets/settlements/urban_landscape_r40.glb");
const R40_MODULES: &[&str] = &[
    "civic_hall", "london_gabled", "london_terrace", "paris_corner", "paris_mansard",
    "quay_platform", "sawtooth_workshop", "warehouse",
];

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
struct Shard {
    metadata: Metadata,
    evidence_catalog: EvidenceCatalog,
}
#[derive(Deserialize)]
struct EvidenceCatalog { facts: Vec<Evidence> }
#[derive(Deserialize)]
struct Evidence { value: serde_json::Value }
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

#[derive(Deserialize)]
struct Settlement {
    id: String,
    display_name: String,
    geometry: Point,
    valid_from: String,
    valid_to: String,
    miniature_layout: SettlementLayout,
}

#[derive(Deserialize)]
struct SettlementLayout {
    max_mpp: f64,
    scale_max: f64,
    target_height_px: f64,
    lod_switch_mpp: f64,
    placements: Vec<SettlementPlacement>,
}

#[derive(Deserialize)]
struct SettlementPlacement {
    module: String,
    offset_m: [f64; 2],
    reference_anchor_lon_lat: Option<[f64; 2]>,
    heading_degrees: f64,
    scale: [f64; 3],
}

struct CityModel {
    module: usize,
    anchor: [f64; 2],
    heading: f64,
    scale: [f64; 3],
}

struct CityLayout {
    center: [f64; 2],
    ground: [f32; 4],
    from: String,
    to: String,
    max_mpp: f64,
    max_scale: f64,
    target_height: f64,
    lod_mpp: f64,
    models: Vec<CityModel>,
}

pub struct Landmarks {
    landmarks: Vec<(usize, usize, Landmark)>,
    cities: BTreeMap<usize, CityLayout>,
    city_bounds: Vec<[ModelBounds; 2]>,
}

type ModelBounds = ([f64; 3], [f64; 3]);

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
enum Lod { Single, Far, Near }

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
enum ModelAsset { Landmark(usize), City(usize) }

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct ModelKey { asset: ModelAsset, lod: Lod }

impl ModelKey {
    pub fn model(self) -> &'static str {
        match self.asset {
            ModelAsset::Landmark(asset) => ASSETS[asset].name,
            ModelAsset::City(module) => R40_MODULES[module],
        }
    }

    pub fn lod(self) -> &'static str {
        match self.lod { Lod::Single => "Single", Lod::Far => "Far", Lod::Near => "Near" }
    }
}

pub struct VisibleModel {
    pub key: ModelKey,
    pub place: usize,
    pub screen_bounds: [f32; 4],
    pub clip_from_model: [[f32; 4]; 4],
    pub city_ground: Option<[f32; 4]>,
}

impl Landmarks {
    pub fn install(world: &mut World) -> io::Result<Self> {
        let mut models = Vec::new();
        let mut cities = BTreeMap::new();
        for source in SHARDS {
            let shard: Shard = serde_json::from_slice(source)?;
            for fact in shard.evidence_catalog.facts {
                let Some(layout) = fact.value.get("miniature_layout") else { continue; };
                if layout.get("model_path").and_then(serde_json::Value::as_str)
                    != Some("res://assets/settlements/urban_landscape_r40.glb") {
                    continue;
                }
                let city: Settlement = serde_json::from_value(fact.value)?;
                let index = install_place(world, Place {
                    id: city.id, name: city.display_name.clone(), name_zh: city.display_name,
                    symbol: "city".into(), reference: true, display_symbol: false, selectable: true,
                    coordinates: city.geometry.coordinates, rank: 1, max_mpp: city.miniature_layout.max_mpp,
                    from_date: city.valid_from.clone(), to_date: city.valid_to.clone(),
                });
                cities.insert(index, CityLayout::from_source(city.geometry.coordinates, city.valid_from, city.valid_to, city.miniature_layout)?);
            }
            for landmark in shard.metadata.landmark_visuals {
                let Some(asset) = ASSETS.iter().position(|asset| asset.path == landmark.model_path)
                    else { continue };
                let model = &ASSETS[asset];
                let place = Place {
                    id: landmark.id.clone(), name: model.name.into(),
                    name_zh: landmark.display_name.clone(), symbol: model.symbol.into(),
                    reference: true, display_symbol: true, selectable: true,
                    coordinates: landmark.geometry.coordinates, rank: landmark.rank,
                    max_mpp: landmark.symbol_max_mpp, from_date: landmark.valid_from.clone(),
                    to_date: landmark.valid_to.clone(),
                };
                let index = install_place(world, place);
                models.push((index, asset, landmark));
            }
        }
        if models.len() != ASSETS.len() {
            return Err(io::Error::other("R68 landmark catalogue and models differ"));
        }
        let glb = gltf::Gltf::from_slice(R40_MODELS).map_err(io::Error::other)?;
        let city_bounds: Vec<_> = (0..R40_MODULES.len()).map(|module| {
            Ok([city_bounds(&glb, module, Lod::Near)?, city_bounds(&glb, module, Lod::Far)?])
        }).collect::<io::Result<_>>()?;
        for city in cities.values_mut() {
            let [lon,lat]=city.center;
            let metres=camera::EARTH*std::f64::consts::PI/180.;
            let mut radius=[80_f64;2];
            for model in &city.models {
                let delta=(model.anchor[0]-lon+180.).rem_euclid(360.)-180.;
                let offset=[delta*metres*lat.to_radians().cos(),(model.anchor[1]-lat)*metres];
                let (min,max)=city_bounds[model.module][0];
                let width=model.scale[0]*min[0].abs().max(max[0].abs());
                let depth=model.scale[2]*min[2].abs().max(max[2].abs());
                let reach=width.hypot(depth)+85.;
                for i in 0..2 {radius[i]=radius[i].max(offset[i].abs()+reach);}
            }
            city.ground=[lon as f32,lat as f32,radius[0] as f32,radius[1] as f32];
        }
        Ok(Self { landmarks: models, cities, city_bounds })
    }

    pub fn contains(&self, place: usize) -> bool {
        self.cities.contains_key(&place) || self.landmarks.iter().any(|(i, _, _)| *i == place)
    }

    pub fn visible(&self, date: &str, camera: &Camera, size: [u32; 2]) -> Vec<VisibleModel> {
        let pitch = camera.pitch();
        let mut visible: Vec<_> = self.landmarks.iter().filter_map(|(place, asset, row)| {
            row.project(*place, *asset, date, camera, pitch, size)
        }).collect();
        for (&place, city) in &self.cities {
            if camera.mpp >= city.max_mpp || !crate::ui::active(date, &city.from, &city.to) { continue; }
            let lod = if camera.mpp >= city.lod_mpp { Lod::Far } else { Lod::Near };
            let weight = 1. - camera::smooth(city.max_mpp * 0.75, city.max_mpp, camera.mpp);
            if weight <= 0.02 { continue; }
            visible.extend(city.models.iter().filter_map(|model| {
                let bounds = self.city_bounds[model.module][usize::from(lod == Lod::Far)];
                let height = (bounds.1[1] - bounds.0[1]) * model.scale[1] * pitch.sin();
                let scale = (city.target_height * camera.mpp / height.max(1.))
                    .clamp(1., city.max_scale) * weight;
                ModelPose {
                    key: ModelKey { asset: ModelAsset::City(model.module), lod },
                    anchor: model.anchor, heading: model.heading, datum: 0.,
                    dimensions: model.scale.map(|component| component * scale),
                    bounds,
                }.project(place, camera, pitch, size).map(|mut visible|{
                    visible.city_ground=Some(city.ground);
                    visible
                })
            }));
        }
        visible
    }

    pub fn focus(&self, place: usize) -> Option<([f64; 2], f64)> {
        if let Some(city) = self.cities.get(&place) { return Some((city.center, 2.)); }
        let (_, _, row) = self.landmarks.iter().find(|(i, _, _)| *i == place)?;
        let size = row.model_height_m.max(row.model_base_width_m);
        Some((row.anchor(), (size / 120.).clamp(1.5, 8.)))
    }
}

fn install_place(world: &mut World, place: Place) -> usize {
    if let Some(index) = world.places.iter().position(|row| row.id == place.id) {
        world.places[index] = place;
        index
    } else {
        world.places.push(place);
        world.places.len() - 1
    }
}

impl CityLayout {
    fn from_source(center: [f64; 2], from: String, to: String, layout: SettlementLayout) -> io::Result<Self> {
        let models = layout.placements.into_iter().enumerate().map(|(index, row)| {
            let module = R40_MODULES.iter().position(|name| **name == row.module)
                .ok_or_else(|| io::Error::other("unknown R40 city module"))?;
            let index = index + 1;
            let variation = [
                0.90 + 0.03 * (index % 3) as f64,
                0.88 + 0.04 * (index % 4) as f64,
                0.92 + 0.025 * (index % 3) as f64,
            ];
            let reference = row.reference_anchor_lon_lat.unwrap_or(center);
            let [east_m, north_m] = row.offset_m;
            let radius = east_m.hypot(north_m);
            let [east, north, normal] = camera::frame(reference);
            let (sin, cos) = (radius / camera::EARTH).sin_cos();
            let per_meter = if radius > 0. { sin / radius } else { 0. };
            let anchor = camera::geographic(std::array::from_fn(|i| {
                normal[i] * cos + (east[i] * east_m + north[i] * north_m) * per_meter
            }));
            Ok(CityModel { module, anchor, heading: row.heading_degrees,
                scale: std::array::from_fn(|i| row.scale[i] * variation[i]) })
        }).collect::<io::Result<_>>()?;
        Ok(Self { center, ground:[0.;4], from, to, max_mpp: layout.max_mpp, max_scale: layout.scale_max,
            target_height: layout.target_height_px, lod_mpp: layout.lod_switch_mpp, models })
    }
}

impl Landmark {
    fn anchor(&self) -> [f64; 2] { self.display_lon_lat.unwrap_or(self.geometry.coordinates) }

    fn project(&self, place: usize, asset: usize, date: &str, camera: &Camera, pitch: f64, size: [u32; 2]) -> Option<VisibleModel> {
        if camera.mpp > self.model_admission_mpp.unwrap_or(self.model_max_mpp)
            || !crate::ui::active(date, &self.valid_from, &self.valid_to) {
            return None;
        }
        let [width, depth] = self.model_footprint_m.unwrap_or([self.model_base_width_m; 2]);
        let lod = match self.model_lod_switch_mpp {
            Some(limit) if camera.mpp <= limit => Lod::Near,
            Some(_) => Lod::Far,
            None => Lod::Single,
        };
        ModelPose {
            key: ModelKey { asset: ModelAsset::Landmark(asset), lod },
            anchor: self.anchor(), heading: self.model_heading_degrees, datum: self.model_ground_datum_m,
            dimensions: [1.; 3],
            bounds: ([-width * 0.5, 0., -depth * 0.5], [width * 0.5, self.model_height_m, depth * 0.5]),
        }.project(place, camera, pitch, size)
    }
}

struct ModelPose {
    key: ModelKey,
    anchor: [f64; 2],
    heading: f64,
    datum: f64,
    dimensions: [f64; 3],
    bounds: ModelBounds,
}

impl ModelPose {
    fn project(&self, place: usize, camera: &Camera, pitch: f64, size: [u32; 2]) -> Option<VisibleModel> {
        let [x, y] = camera.project(self.anchor, size)?;
        let (min, max) = self.bounds;
        let margin = (0..3).map(|i| max[i].abs().max(min[i].abs()) * self.dimensions[i]).sum::<f64>() / camera.mpp;
        let [w, h] = size.map(f64::from);
        if x < -margin || x > w + margin || y < -margin || y > h + margin {
            return None;
        }

        // Meter axes on the same chart as the map and its selection markers.
        let (chart, _) = camera.projection(size);
        let [east, north, _] = camera::frame(self.anchor);
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
            - up * self.datum as f32;
        let chart_from_model = Mat4::from_cols(
            scale(east).extend(0.), up.extend(0.), scale(north.map(|n| -n)).extend(0.), origin.extend(1.),
        );
        let heading = Mat4::from_rotation_y(self.heading.to_radians() as f32);
        let scale = Mat4::from_scale(Vec3::from_array(self.dimensions.map(|n| n as f32)));
        let transform = chart_from_model * heading * scale;
        let [left, top, right, bottom] = [min[0], max[0]].into_iter().flat_map(|x| {
            [min[2], max[2]].into_iter().flat_map(move |z| {
                [min[1], max[1]].into_iter().map(move |y| {
                    let p = transform.transform_point3(Vec3::new(x as f32, y as f32, z as f32));
                    [(1. + p.x) * w as f32 * 0.5, (1. - p.y) * h as f32 * 0.5]
                })
            })
        }).fold([f32::INFINITY, f32::INFINITY, f32::NEG_INFINITY, f32::NEG_INFINITY], |[l, t, r, b], [x, y]| {
            [l.min(x), t.min(y), r.max(x), b.max(y)]
        });
        Some(VisibleModel {
            key: self.key, place,
            clip_from_model: transform.to_cols_array_2d(),
            screen_bounds: [left - 3., top - 3., right - left + 6., bottom - top + 6.],
            city_ground: None,
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
    let bytes = match key.asset {
        ModelAsset::Landmark(asset) => ASSETS[asset].bytes,
        ModelAsset::City(_) => R40_MODELS,
    };
    let glb = gltf::Gltf::from_slice(bytes).map_err(io::Error::other)?;
    let blob = glb.blob.as_deref().ok_or_else(|| io::Error::other("GLB has no mesh buffer"))?;
    let mut model = ModelMesh { vertices: Vec::new(), indices: Vec::new() };
    match key.asset {
        ModelAsset::Landmark(_) => {
            let scene = glb.default_scene().or_else(|| glb.scenes().next())
                .ok_or_else(|| io::Error::other("GLB has no scene"))?;
            for node in scene.nodes() {
                append(node, Mat4::IDENTITY, blob, key.lod, &mut model)?;
            }
        }
        ModelAsset::City(module) => {
            append(city_node(&glb, module, key.lod)?, Mat4::IDENTITY, blob, key.lod, &mut model)?;
        }
    }
    if model.indices.is_empty() {
        return Err(io::Error::other(format!("{} has no static triangles", key.model())));
    }
    Ok(model)
}

fn city_node(glb: &gltf::Gltf, module: usize, lod: Lod) -> io::Result<gltf::Node<'_>> {
    let name = R40_MODULES[module];
    let node_name = if lod == Lod::Far { format!("{name}_far") } else { name.to_owned() };
    glb.nodes().find(|node| node.name() == Some(&node_name))
        .ok_or_else(|| io::Error::other(format!("R40 city model {node_name} missing")))
}

fn city_bounds(glb: &gltf::Gltf, module: usize, lod: Lod) -> io::Result<ModelBounds> {
    let node = city_node(glb, module, lod)?;
    let mesh = node.mesh().ok_or_else(|| io::Error::other("R40 city model has no mesh"))?;
    let transform = Mat4::from_cols_array_2d(&node.transform().matrix());
    let mut min = Vec3::splat(f32::INFINITY);
    let mut max = Vec3::splat(f32::NEG_INFINITY);
    for primitive in mesh.primitives() {
        let bounds = primitive.bounding_box();
        for x in [bounds.min[0], bounds.max[0]] {
            for y in [bounds.min[1], bounds.max[1]] {
                for z in [bounds.min[2], bounds.max[2]] {
                    let vertex = transform.transform_point3(Vec3::new(x, y, z));
                    min = min.min(vertex);
                    max = max.max(vertex);
                }
            }
        }
    }
    Ok((min.to_array().map(f64::from), max.to_array().map(f64::from)))
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
