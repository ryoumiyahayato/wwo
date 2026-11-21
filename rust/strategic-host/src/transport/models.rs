//! Original steam-era transport meshes. Coordinates are in metres, +Y up
//! and +Z forward or along the track. Rail vehicles pivot at railhead height,
//! fixed structures at ground level, and vessels at the waterline.

use std::{borrow::Cow, io, sync::OnceLock};

use bytemuck::{Pod, Zeroable};

const KIT: &[u8] =
    include_bytes!("../../../../assets/civilian/transport/steam_1900/steam_1900.glb");

pub const TRACK_TILE_LENGTH_M: f32 = 12.0;
pub const TRACK_RAILHEAD_M: f32 = 0.24;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum TransportModel {
    SteamLocomotive,
    CoalTender,
    PassengerCoach,
    BoxWagon,
    StraightTrack,
    StationBuilding,
    StationPlatform,
    PassengerSteamship,
    CargoSteamship,
    CoastalPaddleSteamer,
}

impl TransportModel {
    pub const ALL: [Self; 10] = [
        Self::SteamLocomotive,
        Self::CoalTender,
        Self::PassengerCoach,
        Self::BoxWagon,
        Self::StraightTrack,
        Self::StationBuilding,
        Self::StationPlatform,
        Self::PassengerSteamship,
        Self::CargoSteamship,
        Self::CoastalPaddleSteamer,
    ];

    pub fn id(self) -> &'static str {
        match self {
            Self::SteamLocomotive => "steam_locomotive",
            Self::CoalTender => "coal_tender",
            Self::PassengerCoach => "passenger_coach",
            Self::BoxWagon => "box_wagon",
            Self::StraightTrack => "straight_track",
            Self::StationBuilding => "station_building",
            Self::StationPlatform => "station_platform",
            Self::PassengerSteamship => "passenger_steamship",
            Self::CargoSteamship => "cargo_steamship",
            Self::CoastalPaddleSteamer => "coastal_paddle_steamer",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum ModelLod {
    Near,
    Far,
}

impl ModelLod {
    /// Select by the longest projected extent in pixels. `None` lets the
    /// caller keep the map symbol or line without loading a model.
    pub fn for_screen_extent(pixels: f32) -> Option<Self> {
        if !pixels.is_finite() || pixels < 12.0 {
            None
        } else if pixels < 48.0 {
            Some(Self::Far)
        } else {
            Some(Self::Near)
        }
    }

    fn suffix(self) -> &'static str {
        match self {
            Self::Near => "near",
            Self::Far => "far",
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct ModelVertex {
    pub position: [f32; 3],
    pub normal: [f32; 3],
    pub color: [f32; 4],
}

#[derive(Debug)]
pub struct ModelMesh {
    pub vertices: Vec<ModelVertex>,
    pub indices: Vec<u32>,
    pub min: [f32; 3],
    pub max: [f32; 3],
}

struct Kit {
    document: gltf::Document,
    buffer: Cow<'static, [u8]>,
}

impl Kit {
    fn load() -> io::Result<Self> {
        let glb = gltf::binary::Glb::from_slice(KIT).map_err(io::Error::other)?;
        let buffer = glb
            .bin
            .ok_or_else(|| io::Error::other("transport GLB missing binary buffer"))?;
        let document = gltf::Gltf::from_slice(&glb.json)
            .map_err(io::Error::other)?
            .document;
        Ok(Self { document, buffer })
    }
}

static DOCUMENT: OnceLock<Result<Kit, String>> = OnceLock::new();

/// Decode the requested mesh on demand. Only the bundle metadata and
/// embedded binary buffer are shared between calls.
pub fn decode(model: TransportModel, lod: ModelLod) -> io::Result<ModelMesh> {
    let kit = DOCUMENT
        .get_or_init(|| Kit::load().map_err(|error| error.to_string()))
        .as_ref()
        .map_err(|error| io::Error::other(error.clone()))?;
    let name = format!("{}_{}", model.id(), lod.suffix());
    let mesh = kit
        .document
        .meshes()
        .find(|mesh| mesh.name() == Some(name.as_str()))
        .ok_or_else(|| io::Error::other(format!("transport mesh {name} missing")))?;
    let mut result = ModelMesh {
        vertices: Vec::new(),
        indices: Vec::new(),
        min: [f32::INFINITY; 3],
        max: [f32::NEG_INFINITY; 3],
    };
    for primitive in mesh.primitives() {
        let material = primitive.material().pbr_metallic_roughness();
        if primitive.mode() != gltf::mesh::Mode::Triangles
            || material.base_color_texture().is_some()
        {
            return Err(io::Error::other("expected untextured transport triangles"));
        }
        let reader = primitive.reader(|buffer| {
            (buffer.index() == 0 && matches!(buffer.source(), gltf::buffer::Source::Bin))
                .then_some(kit.buffer.as_ref())
        });
        let positions = reader
            .read_positions()
            .ok_or_else(|| io::Error::other("transport mesh missing positions"))?;
        let normals = reader
            .read_normals()
            .ok_or_else(|| io::Error::other("transport mesh missing normals"))?;
        let indices = reader
            .read_indices()
            .ok_or_else(|| io::Error::other("transport mesh missing indices"))?
            .into_u32();
        let vertex_count = positions.len();
        if vertex_count != normals.len() || indices.len() % 3 != 0 {
            return Err(io::Error::other("invalid transport mesh geometry counts"));
        }
        let base = result.vertices.len() as u32;
        let color = material.base_color_factor();
        for (position, normal) in positions.zip(normals) {
            for (axis, value) in position.into_iter().enumerate() {
                result.min[axis] = result.min[axis].min(value);
                result.max[axis] = result.max[axis].max(value);
            }
            result.vertices.push(ModelVertex {
                position,
                normal,
                color,
            });
        }
        for index in indices {
            if index as usize >= vertex_count {
                return Err(io::Error::other("transport mesh index out of range"));
            }
            result.indices.push(base + index);
        }
    }
    if result.indices.is_empty() {
        return Err(io::Error::other(format!("transport mesh {name} is empty")));
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_models_contain_both_detail_levels() {
        for model in TransportModel::ALL {
            let near = decode(model, ModelLod::Near).unwrap();
            let far = decode(model, ModelLod::Far).unwrap();
            assert!(near.indices.len() > far.indices.len(), "{model:?}");
            for mesh in [near, far] {
                assert!(
                    mesh.vertices.iter().all(|vertex| {
                        vertex.position.iter().all(|value| value.is_finite())
                            && (vertex.normal.iter().map(|n| n * n).sum::<f32>() - 1.0).abs() < 1e-5
                    }),
                    "{model:?}"
                );
                assert!(mesh.min[2] < 0.0 && mesh.max[2] > 0.0, "{model:?}");
                match model {
                    TransportModel::PassengerSteamship
                    | TransportModel::CargoSteamship
                    | TransportModel::CoastalPaddleSteamer => assert!(mesh.min[1] < 0.0),
                    _ => assert!(mesh.min[1].abs() < 1e-5, "{model:?}"),
                }
            }
        }
    }

    #[test]
    fn track_tile_keeps_its_length_and_railhead_across_detail_levels() {
        for lod in [ModelLod::Near, ModelLod::Far] {
            let track = decode(TransportModel::StraightTrack, lod).unwrap();
            assert_eq!(track.min[2], -TRACK_TILE_LENGTH_M / 2.0);
            assert_eq!(track.max[2], TRACK_TILE_LENGTH_M / 2.0);
            assert!((track.max[1] - TRACK_RAILHEAD_M).abs() < 1e-5);
        }
    }
}
