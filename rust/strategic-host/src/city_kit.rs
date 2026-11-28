use crate::landmarks::{ModelMesh, ModelVertex};
use glam::Vec3;
use serde::Deserialize;
use std::sync::LazyLock;

pub(crate) const ROLES: [&str; 8] = [
    "low_home",
    "street_row",
    "courtyard_home",
    "shop",
    "civic",
    "warehouse",
    "workshop",
    "transport_auxiliary",
];

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Roof {
    Flat,
    Gable,
    Hip,
    Mansard,
    Pavilion,
    Sawtooth,
}

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum Court {
    Side,
    Rear,
    Enclosed,
    Passage,
}

#[derive(Deserialize)]
struct Kit {
    id: String,
    roof: Roof,
    work_roof: Roof,
    court: Court,
    parapet: bool,
    arcade: bool,
    #[serde(default)]
    shop_airwell: Option<[f32; 2]>,
    eave: f32,
    wall: [f32; 3],
    tile: [f32; 3],
}

static KITS: LazyLock<Vec<Kit>> = LazyLock::new(|| {
    serde_json::from_slice(include_bytes!(
        "../../../assets/settlements/city-kits-1900.json"
    ))
    .expect("embedded city kit definitions")
});

pub(crate) fn index(id: &str) -> Option<usize> {
    KITS.iter().position(|kit| kit.id == id)
}

pub(crate) fn name(index: usize) -> &'static str {
    &KITS[index].id
}

pub(crate) fn build(index: usize, role: usize, detail: bool) -> ModelMesh {
    let kit = &KITS[index];
    let mut mesh = ModelMesh::default();
    let mut wing = |bounds, height, roof, public| {
        volume(&mut mesh, bounds, height, roof, kit, detail, public);
    };
    match role {
        0 => {
            wing([-0.5, -0.40, 0.5, 0.5], 1., kit.roof, false);
            wing([-0.27, -0.5, 0.27, -0.40], 0.57, Roof::Gable, false);
        }
        2 => {
            let front = match kit.court {
                Court::Rear => 0.,
                Court::Passage => -0.18,
                _ => -0.24,
            };
            if matches!(kit.court, Court::Passage) {
                wing([-0.5, -0.5, -0.08, front], 1., kit.roof, false);
                wing([0.08, -0.5, 0.5, front], 1., kit.roof, false);
            } else {
                wing([-0.5, -0.5, 0.5, front], 1., kit.roof, false);
            }
            wing([-0.5, front, -0.31, 0.5], 0.72, kit.roof, false);
            if !matches!(kit.court, Court::Side) {
                wing([0.31, front, 0.5, 0.5], 0.72, kit.roof, false);
            }
            if matches!(kit.court, Court::Enclosed | Court::Passage) {
                wing([-0.31, 0.28, 0.31, 0.5], 0.65, kit.roof, false);
            }
        }
        3 => {
            if let Some([front_end, rear_start]) = kit.shop_airwell {
                wing([-0.5, -0.5, 0.5, front_end], 1., kit.roof, true);
                wing([-0.5, rear_start, 0.5, 0.5], 0.62, kit.roof, false);
                wing([-0.5, front_end, -0.46, rear_start], 0.42, Roof::Flat, false);
                wing([0.46, front_end, 0.5, rear_start], 0.42, Roof::Flat, false);
            } else {
                wing([-0.5, -0.5, 0.5, 0.5], 1., kit.roof, true);
            }
        }
        4 => {
            wing([-0.5, -0.38, 0.5, 0.5], 0.75, kit.roof, false);
            wing([-0.26, -0.5, 0.26, -0.38], 1., kit.roof, true);
        }
        6 if matches!(kit.work_roof, Roof::Sawtooth) => {
            for panel in 0..3 {
                let x = -0.5 + panel as f32 / 3.;
                wing([x, -0.5, x + 1. / 3., 0.5], 1., kit.work_roof, false);
            }
        }
        5 | 6 => wing([-0.5, -0.5, 0.5, 0.5], 1., kit.work_roof, false),
        7 => {
            wing([-0.5, -0.5, 0.5, 0.23], 1., kit.work_roof, true);
            wing([-0.5, 0.23, 0.5, 0.5], 0.55, Roof::Flat, true);
        }
        _ => wing([-0.5, -0.5, 0.5, 0.5], 1., kit.roof, false),
    }
    debug_assert!(mesh.indices.len() / 3 <= if detail { 2_000 } else { 128 });
    mesh
}

fn volume(
    mesh: &mut ModelMesh,
    [x0, z0, x1, z1]: [f32; 4],
    height: f32,
    roof: Roof,
    kit: &Kit,
    detail: bool,
    arcade: bool,
) {
    let cx = (x0 + x1) * 0.5;
    let cz = (z0 + z1) * 0.5;
    let is_flat = matches!(roof, Roof::Flat);
    let parapet = is_flat && kit.parapet && detail;
    let eave = height
        * if parapet {
            0.95
        } else if is_flat {
            1.
        } else {
            kit.eave
        };
    let ring = |y, x0, z0, x1, z1| [[x0, y, z0], [x1, y, z0], [x1, y, z1], [x0, y, z1]];
    let base = ring(0., x0, z0, x1, z1);
    let wall = ring(eave, x0, z0, x1, z1);
    let cap = match roof {
        Roof::Flat => ring(eave, x0, z0, x1, z1),
        Roof::Gable => ring(height, x0, cz, x1, cz),
        Roof::Hip => ring(height, x0 + (x1 - x0) * 0.22, cz, x1 - (x1 - x0) * 0.22, cz),
        Roof::Pavilion => ring(height, cx, cz, cx, cz),
        Roof::Mansard => ring(
            height * 0.91,
            x0 + (x1 - x0) * 0.12,
            z0 + (z1 - z0) * 0.12,
            x1 - (x1 - x0) * 0.12,
            z1 - (z1 - z0) * 0.12,
        ),
        Roof::Sawtooth => ring(height, x0, z0, x0, z1),
    };
    let arcade = arcade && kit.arcade;
    if arcade {
        let level = eave * 0.48;
        let retreat = z0 + (z1 - z0) * 0.20;
        surface(
            mesh,
            ring(0., x0, retreat, x1, z1),
            ring(level, x0, retreat, x1, z1),
            kit.wall,
        );
        surface(mesh, ring(level, x0, z0, x1, z1), wall, kit.wall);
        face(
            mesh,
            [
                [x0, level, z0],
                [x1, level, z0],
                [x1, level, retreat],
                [x0, level, retreat],
            ],
            kit.wall,
        );
        for fraction in [0., 0.46, 0.92] {
            let left = x0 + (x1 - x0) * fraction;
            let right = left + (x1 - x0) * 0.08;
            let back = z0 + (retreat - z0) * 0.28;
            surface(
                mesh,
                ring(0., left, z0, right, back),
                ring(level, left, z0, right, back),
                kit.wall,
            );
        }
    } else {
        surface(mesh, base, wall, kit.wall);
    }
    surface(mesh, wall, cap, kit.tile);
    if matches!(roof, Roof::Mansard) {
        let top = ring(
            height,
            x0 + (x1 - x0) * 0.24,
            z0 + (z1 - z0) * 0.24,
            x1 - (x1 - x0) * 0.24,
            z1 - (z1 - z0) * 0.24,
        );
        surface(mesh, cap, top, kit.tile);
        face(mesh, [top[3], top[2], top[1], top[0]], kit.tile);
    } else {
        face(mesh, [cap[3], cap[2], cap[1], cap[0]], kit.tile);
    }
    if parapet {
        let outer = ring(height, x0, z0, x1, z1);
        let dx = (x1 - x0) * 0.035;
        let dz = (z1 - z0) * 0.035;
        let inner_top = ring(height, x0 + dx, z0 + dz, x1 - dx, z1 - dz);
        let inner_base = ring(eave, x0 + dx, z0 + dz, x1 - dx, z1 - dz);
        surface(mesh, wall, outer, kit.wall);
        surface(mesh, inner_top, inner_base, kit.wall);
        surface(mesh, outer, inner_top, kit.wall);
    }
    if detail {
        let shade = kit.wall.map(|value| value * 0.38);
        let bays = if x1 - x0 > 0.38 { 3 } else { 1 };
        for i in 0..bays {
            let spacing = (x1 - x0) / bays as f32;
            let x = x0 + (i as f32 + 0.5) * spacing;
            for (bottom, top) in [(eave * 0.24, eave * 0.45), (eave * 0.65, eave * 0.83)] {
                if arcade && bottom < eave * 0.48 {
                    continue;
                }
                let w = spacing * 0.18;
                let facade = z0 - 0.001;
                face(
                    mesh,
                    [
                        [x - w, bottom, facade],
                        [x - w, top, facade],
                        [x + w, top, facade],
                        [x + w, bottom, facade],
                    ],
                    shade,
                );
            }
        }
    }
}

fn surface(mesh: &mut ModelMesh, lower: [[f32; 3]; 4], upper: [[f32; 3]; 4], color: [f32; 3]) {
    for i in 0..4 {
        let next = (i + 1) % 4;
        face(mesh, [lower[i], upper[i], upper[next], lower[next]], color);
    }
}

fn face(mesh: &mut ModelMesh, points: [[f32; 3]; 4], color: [f32; 3]) {
    let [r, g, b] = color;
    for ids in [[0, 1, 2], [0, 2, 3]] {
        let [a, edge, corner] = ids.map(|index| Vec3::from_array(points[index]));
        let normal = (edge - a).cross(corner - a).normalize_or_zero();
        if normal == Vec3::ZERO {
            continue;
        }
        let start = mesh.vertices.len() as u32;
        mesh.vertices.extend(ids.map(|index| ModelVertex {
            position: points[index],
            normal: normal.to_array(),
            color: [r, g, b, 1.],
        }));
        mesh.indices.extend([start, start + 1, start + 2]);
    }
}
