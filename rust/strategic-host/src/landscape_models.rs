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
    mesh.vertices.extend(points.into_iter().zip(edge).map(|(point, edge)| Vertex {
        offset: point.to_array(),
        normal: normal.to_array(),
        tone,
        edge,
        crown: 0.,
    }));
}

fn stand(outline: &[(f32, f32)], group: &Mesh) -> Mesh {
    // Keep the stand first so the indirect draw can omit subpixel crowns.
    let mut mesh = group.clone();
    for tree in 1..=49 {
        crown(&mut mesh, outline, Vec3::new(0.,0.,0.52), [1.,1.],
            Vec3::new(0.12,-0.10,1.), 1., tree as f32);
    }
    mesh
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
    let rise = if layer > 0. { 1.1 } else { 6.2 };
    for (i, &(x, y)) in outline.iter().enumerate() {
        let rim = Vec3::new(x*radius[0], y*radius[1], 0.);
        let normal = Vec3::new(x*rise,y*rise,1.).normalize();
        mesh.vertices.push(Vertex {
            offset: (center+rim).to_array(),
            normal: normal.to_array(),
            tone,
            edge: 0.,
            crown: layer,
        });
        let next = (i + 1) % outline.len();
        mesh.indices.extend([apex + 1 + i as u16, apex + 1 + next as u16, apex]);
    }
}

pub fn meshes() -> [Mesh; 4] {
    let lobed = [
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
    let outline = [(1., 0.05), (0.10, 0.97), (-0.81, 0.57), (-0.66, -0.58), (0.30, -0.88)];
    let mut group = Mesh::default();
    // Keep connected low foliage beneath overlapping crowns. No hidden bottom faces.
    crown(&mut group, &lobed, Vec3::new(0.,0.,0.15), [1.16,1.13],
        Vec3::new(-0.14,0.08,0.36), 0.76, -1.);
    for (x, y, r, h, tone) in [(-0.59, 0.12, 0.55, 0.72, 0.90),
        (-0.31, -0.47, 0.53, 1.02, 1.01), (-0.33, 0.49, 0.51, 0.66, 0.99),
        (0.18, 0.23, 0.56, 1.19, 1.07), (0.27, -0.41, 0.51, 0.74, 0.91),
        (0.62, -0.01, 0.53, 0.93, 1.03)] {
        crown(&mut group, &outline, Vec3::new(x, y, 0.30), [r, r * 0.92],
            Vec3::new(x - 0.04, y + 0.03, h), tone, 0.);
    }
    let broadleaf = stand(&[lobed[0],lobed[2],lobed[4],lobed[6],lobed[8]], &group);
    let conifer = stand(&[needles[0],needles[1],needles[2],needles[4],needles[6],needles[8]], &group);
    [broadleaf, conifer, rock, group]
}
