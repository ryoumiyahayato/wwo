use bytemuck::{Pod, Zeroable};
use glam::Vec3;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct Vertex {
    offset: [f32; 3],
    normal: [f32; 3],
    tone: f32,
    edge: f32,
    crown: f32,
}

#[derive(Clone, Default)]
pub struct Mesh {
    pub vertices: Vec<Vertex>,
    pub indices: Vec<u16>,
}

fn face(mesh: &mut Mesh, points: [Vec3; 3], edge: [f32; 3], tone: f32) {
    let normal = (points[1] - points[0])
        .cross(points[2] - points[0])
        .normalize();
    let first = mesh.vertices.len() as u16;
    mesh.indices.extend([first, first + 1, first + 2]);
    mesh.vertices
        .extend(points.into_iter().zip(edge).map(|(point, edge)| Vertex {
            offset: point.to_array(),
            normal: normal.to_array(),
            tone,
            edge,
            crown: 0.,
        }));
}

const GROVES: usize = 7;
const TREES_PER_GROVE: usize = 4;
const BROADLEAF: [(f32, f32); 10] = [
    (1., 0.),
    (0.64, 0.34),
    (0.39, 0.95),
    (-0.25, 0.85),
    (-0.81, 0.63),
    (-0.9, 0.02),
    (-0.87, -0.64),
    (-0.24, -0.78),
    (0.37, -0.93),
    (0.60, -0.45),
];

pub(crate) fn park_tree() -> (Vec<([f32; 3], [f32; 3], f32)>, Vec<u16>) {
    let mut mesh = Mesh::default();
    volume(&mut mesh, &BROADLEAF, 1., false, true);
    trunk(&mut mesh, 1.);
    let vertices = mesh.vertices.into_iter().map(|v| {
        let [x, y, z] = v.offset;
        let [nx, ny, nz] = v.normal;
        ([x, z, -y], [nx, nz, -ny], v.tone)
    }).collect();
    (vertices, mesh.indices)
}

fn stand(outline: &[(f32, f32)], group: &Mesh, conifer: bool) -> Mesh {
    // Keep the stand first so the indirect draw can omit subpixel crowns.
    let mut mesh = group.clone();
    for tree in 1..=GROVES * TREES_PER_GROVE {
        let layer = tree as f32;
        let anchor = tree % TREES_PER_GROVE == 1;
        volume(&mut mesh, outline, layer, conifer, anchor);
        if anchor {
            trunk(&mut mesh, layer);
        }
    }
    mesh
}

fn volume(mesh: &mut Mesh, outline: &[(f32, f32)], layer: f32, conifer: bool, anchor: bool) {
    let first = mesh.vertices.len() as u16;
    let rings: &[(f32, f32, f32)] = if conifer {
        &[(0.61, 0.27, 0.87), (0.97, 0.45, 0.97), (0.46, 0.73, 1.06)]
    } else {
        &[(0.60, 0.33, 0.86), (1., 0.54, 0.98), (0.73, 0.78, 1.07)]
    };
    // Keep the flanks on the larger tree. The smaller crowns have a
    // corrugated skirt below the apex to break the silhouette in oblique view.
    let rings = if anchor { rings } else { &rings[1..2] };
    for &(r, z, tone) in rings {
        for (i, &(x, y)) in outline.iter().enumerate() {
            let z = z - if anchor { 0. } else { (i % 2) as f32 * 0.16 };
            mesh.vertices.push(Vertex {
                offset: [x * r + z * 0.09, y * r - z * 0.06, z],
                normal: Vec3::new(x, y, (z - 0.52) * 1.6).normalize().to_array(),
                tone,
                edge: 1.,
                crown: layer,
            });
        }
    }
    let corners = outline.len() as u16;
    let top = first + rings.len() as u16 * corners;
    mesh.vertices.push(Vertex {
        offset: [0.12, -0.07, 1.],
        normal: Vec3::Z.to_array(),
        tone: 1.08,
        edge: 1.,
        crown: layer,
    });
    for i in 0..corners {
        let j = (i + 1) % corners;
        for ring in 0..rings.len() as u16 - 1 {
            let row = first + ring * corners;
            mesh.indices.extend([
                row + i,
                row + j,
                row + corners + i,
                row + j,
                row + corners + j,
                row + corners + i,
            ]);
        }
        mesh.indices
            .extend([top - corners + i, top - corners + j, top]);
    }
}

fn trunk(mesh: &mut Mesh, layer: f32) {
    let first = mesh.vertices.len() as u16;
    let corners = [(1., 0.), (-0.5, 0.866), (-0.5, -0.866)];
    for (radius, z) in [(0.068, 0.), (0.031, 0.49)] {
        for (x, y) in corners {
            mesh.vertices.push(Vertex {
                offset: [radius * x + z * 0.082, radius * y, z],
                normal: [x, y, 0.],
                tone: -1.,
                edge: 1.,
                crown: layer,
            });
        }
    }
    for i in 0..3 {
        let j = (i + 1) % 3;
        mesh.indices.extend([
            first + i,
            first + j,
            first + 3 + i,
            first + j,
            first + 3 + j,
            first + 3 + i,
        ]);
    }
}

fn crown(
    mesh: &mut Mesh,
    outline: &[(f32, f32)],
    center: Vec3,
    radius: [f32; 2],
    peak: Vec3,
    tone: f32,
    layer: f32,
) {
    let apex = mesh.vertices.len() as u16;
    mesh.vertices.push(Vertex {
        offset: peak.to_array(),
        normal: Vec3::Z.to_array(),
        tone: tone * 1.04,
        edge: 1.,
        crown: layer,
    });
    for (i, &(x, y)) in outline.iter().enumerate() {
        let rim = Vec3::new(x * radius[0], y * radius[1], 0.);
        let normal = Vec3::new(x * 6.2, y * 6.2, 1.).normalize();
        mesh.vertices.push(Vertex {
            offset: (center + rim).to_array(),
            normal: normal.to_array(),
            tone,
            edge: 0.,
            crown: layer,
        });
        let next = (i + 1) % outline.len();
        mesh.indices
            .extend([apex + 1 + i as u16, apex + 1 + next as u16, apex]);
    }
}

fn farm_building(mesh: &mut Mesh, center: [f32; 2], half_size: [f32; 2], eave: f32, ridge: f32) {
    let [x, y] = center;
    let [w, d] = half_size;
    let corners = [[x-w, y-d], [x+w, y-d], [x+w, y+d], [x-w, y+d]];
    let bottom = corners.map(|[x, y]| Vec3::new(x, y, -0.15));
    let top = corners.map(|[x, y]| Vec3::new(x, y, eave));
    let west = Vec3::new(x-w, y, ridge);
    let east = Vec3::new(x+w, y, ridge);
    for (i, j) in [(0, 1), (1, 2), (2, 3), (3, 0)] {
        face(mesh, [bottom[i], bottom[j], top[j]], [1.; 3], 0.72);
        face(mesh, [bottom[i], top[j], top[i]], [1.; 3], 0.72);
    }
    face(mesh, [top[0], top[1], east], [1.; 3], 1.);
    face(mesh, [top[0], east, west], [1.; 3], 1.);
    face(mesh, [west, east, top[2]], [1.; 3], 1.);
    face(mesh, [west, top[2], top[3]], [1.; 3], 1.);
    face(mesh, [top[1], top[2], east], [1.; 3], 0.72);
    face(mesh, [top[3], top[0], west], [1.; 3], 0.72);
}

fn farmstead() -> Mesh {
    let mut mesh = Mesh::default();
    farm_building(&mut mesh, [-0.26, -0.23], [0.53, 0.18], 0.68, 0.96);
    farm_building(&mut mesh, [0.38, 0.31], [0.26, 0.15], 0.53, 0.80);
    mesh
}

pub fn meshes() -> ([Mesh; 4], u32) {
    let lobed = BROADLEAF;
    let needles = [
        (1., 0.),
        (0.43, 0.32),
        (0.35, 0.97),
        (-0.16, 0.48),
        (-0.83, 0.60),
        (-0.52, 0.),
        (-1., -0.66),
        (-0.15, -0.51),
        (0.31, -0.92),
        (0.48, -0.32),
    ];
    let mut rock = Mesh::default();
    let base = [
        Vec3::new(1., -0.17, -0.24),
        Vec3::new(0.66, 0.74, -0.24),
        Vec3::new(-0.48, 0.89, -0.24),
        Vec3::new(-1., 0.17, -0.24),
        Vec3::new(-0.64, -0.84, -0.24),
        Vec3::new(0.34, -0.79, -0.24),
    ];
    let ledge = [
        Vec3::new(0.68, -0.16, 0.56),
        Vec3::new(0.36, 0.49, 0.73),
        Vec3::new(-0.41, 0.54, 0.56),
        Vec3::new(-0.67, 0.17, 0.53),
        Vec3::new(-0.37, -0.49, 0.83),
        Vec3::new(0.16, -0.44, 0.68),
    ];
    for i in 0..base.len() {
        let j = (i + 1) % base.len();
        let band = if i % 2 == 0 { 1. } else { 0.85 };
        face(&mut rock, [base[i], base[j], ledge[i]], [0., 0., 1.], band);
        face(
            &mut rock,
            [base[j], ledge[j], ledge[i]],
            [0., 1., 1.],
            band * 0.93,
        );
        face(
            &mut rock,
            [ledge[i], ledge[j], Vec3::new(-0.14, -0.07, 1.)],
            [1.; 3],
            band * 1.10,
        );
    }
    let outline = [
        (1., 0.05),
        (0.10, 0.97),
        (-0.81, 0.57),
        (-0.66, -0.58),
        (0.30, -0.88),
    ];
    let mut group = Mesh::default();
    // Keep connected low foliage beneath overlapping crowns. No hidden bottom faces.
    crown(
        &mut group,
        &lobed,
        Vec3::new(0., 0., 0.15),
        [1.16, 1.13],
        Vec3::new(-0.14, 0.08, 0.36),
        0.76,
        -1.,
    );
    for (i, (r, h, tone)) in [
        (0.32, 0.72, 0.90),
        (0.39, 1.02, 1.01),
        (0.28, 0.66, 0.99),
        (0.43, 1.19, 1.07),
        (0.34, 0.74, 0.91),
        (0.40, 0.93, 1.03),
        (0.31, 0.57, 0.93),
    ]
    .into_iter()
    .enumerate()
    {
        let layer = -(i as f32) - 2.;
        crown(
            &mut group,
            &outline,
            Vec3::new(-0.09, 0.02, 0.32),
            [r, r * 0.92],
            Vec3::new(-0.04, 0.03, h),
            tone,
            layer,
        );
        if i % 2 == 1 {
            crown(
                &mut group,
                &outline,
                Vec3::new(0.15, 0.07, 0.26),
                [r * 0.68, r * 0.77],
                Vec3::new(0.16, 0.07, h * 0.78),
                tone * 0.94,
                layer,
            );
        }
    }
    let broadleaf = stand(
        &[lobed[0], lobed[2], lobed[4], lobed[6], lobed[8]],
        &group,
        false,
    );
    let conifer = stand(
        &[
            needles[0], needles[1], needles[2], needles[4], needles[6], needles[8],
        ],
        &group,
        true,
    );
    ([broadleaf, conifer, rock, farmstead()], group.indices.len() as u32)
}
