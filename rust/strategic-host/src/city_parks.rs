use crate::{
    camera::{self, Camera},
    landmarks::{ModelKey, ModelMesh, ModelPose, ModelVertex, VisibleModel},
};
use glam::{Quat, Vec3};
use std::sync::OnceLock;

static PARKS: OnceLock<Vec<u8>> = OnceLock::new();

pub fn data() -> &'static [u8] {
    PARKS.get_or_init(|| {
        zstd::stream::decode_all(&include_bytes!("city-parks.bin.zst")[..])
            .expect("embedded city park layouts")
    })
}

fn word(index: usize) -> u32 {
    let start = 4 * index;
    u32::from_le_bytes(data()[start..start + 4].try_into().unwrap())
}

fn value(index: usize) -> f32 {
    f32::from_bits(word(index))
}

pub(crate) fn visible(camera: &Camera, size: [u32; 2]) -> impl Iterator<Item = VisibleModel> + '_ {
    let opacity = (1. - camera::smooth(3., 7.2, camera.mpp)) as f32;
    (0..word(0) as usize).filter_map(move |site| {
        if opacity <= 0. { return None; }
        let header = 1 + site * 8;
        let anchor = [value(header) as f64, value(header + 1) as f64];
        let pose = ModelPose {
            key: ModelKey::park(site),
            anchor,
            heading: 0.,
            datum: 0.,
            dimensions: [1.; 3],
            bounds: ([-512., 0., -512.], [512., 22., 512.]),
        };
        let mut model = pose.project(None, camera, camera.pitch(), size)?;
        model.lod_range = [0., opacity];
        Some(model)
    })
}

pub(crate) fn mesh(site: usize) -> ModelMesh {
    let header = 1 + site * 8;
    let start = word(header + 6) as usize;
    let count = word(header + 7) as usize;
    let (tree, triangles) = crate::landscape_models::park_tree();
    let mut mesh = ModelMesh {
        vertices: Vec::with_capacity(count * tree.len()),
        indices: Vec::with_capacity(count * triangles.len()),
        facade_lod: None,
    };
    for i in (start..start + count * 5).step_by(5) {
        let [east, north, radius, height, phase] = std::array::from_fn(|offset| value(i + offset));
        let turn = Quat::from_rotation_y(std::f32::consts::TAU * phase);
        let reach = Vec3::new(radius, height, radius);
        let origin = Vec3::new(east, 0., -north);
        let foliage = Vec3::new(0.152, 0.230, 0.072)
            .lerp(Vec3::new(0.241, 0.324, 0.129), phase);
        let bark = Vec3::new(0.143, 0.103, 0.063);
        let base = mesh.vertices.len() as u32;
        mesh.vertices.extend(tree.iter().map(|&(position, normal, tone)| {
            let color = if tone < 0. { bark } else { foliage * tone };
            ModelVertex {
                position: (origin + turn * (Vec3::from_array(position) * reach)).to_array(),
                normal: (turn * (Vec3::from_array(normal) / reach).normalize()).to_array(),
                color: color.extend(1.).to_array(),
            }
        }));
        mesh.indices.extend(triangles.iter().map(|&index| base + u32::from(index)));
    }
    mesh
}
