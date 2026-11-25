use crate::overlay::Mesh;
use serde::Deserialize;
use std::{collections::HashMap, sync::LazyLock};

pub const GOLD: [u8; 4] = [240, 208, 149, 255];
pub const BLUE: [u8; 4] = [138, 213, 222, 255];
pub const PLACE_SIZE: f32 = 21.;
pub const DIAMOND_RADIUS: f32 = 6.15;
const OUTLINE: [u8; 4] = [25, 38, 36, 226];
const SHADOW: [u8; 4] = [15, 23, 27, 112];

#[derive(Deserialize)]
struct Glyph {
    paths: Vec<Vec<[f32; 2]>>,
}

static GLYPHS: LazyLock<HashMap<String, Glyph>> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../map-marker-glyphs.json")).expect("invalid map marker artwork")
});

pub fn glyph(mesh: &mut Mesh, name: &str, [x, y]: [f32; 2], size: f32, ink: [u8; 4]) {
    let scale = size / 24.;
    let paint = |mesh: &mut Mesh, width, offset: f32, color| {
        let project = |[u, v]: [f32; 2]| [x + (u - 12.) * scale, y + (v - 12.) * scale + offset];
        for path in &GLYPHS[name].paths {
            for segment in path.windows(2) {
                mesh.line(project(segment[0]), project(segment[1]), width * scale, color);
            }
        }
    };
    let fade = |mut color: [u8; 4]| { color[3] = (u16::from(color[3]) * u16::from(ink[3]) / 255) as u8; color };
    paint(mesh, 3.6, 0.85, fade(SHADOW));
    paint(mesh, 3.5, 0., fade(OUTLINE));
    paint(mesh, 1.9, 0., ink);
}

pub fn diamond(mesh: &mut Mesh, [x, y]: [f32; 2], r: f32, ink: [u8; 4], filled: bool) {
    let vertices = |radius, y| [[x, y - radius], [x + radius, y], [x, y + radius], [x - radius, y]];
    let ring = |mesh: &mut Mesh, outer: f32, inner: f32, y, color| {
        let outside = vertices(outer, y);
        let inside = vertices(inner.max(0.), y);
        for i in 0..4 {
            let next = (i + 1) % 4;
            mesh.shape(&[outside[i], outside[next], inside[next], inside[i]], color);
        }
    };
    if filled {
        mesh.shape(&vertices(r + 1.6, y + 0.85), SHADOW);
        mesh.shape(&vertices(r + 1.55, y), OUTLINE);
        mesh.shape(&vertices(r, y), ink);
    } else {
        ring(mesh, r + 1.6, r - 2.3, y + 0.85, SHADOW);
        ring(mesh, r + 1.55, r - 2.2, y, OUTLINE);
        ring(mesh, r + 0.48, r - 1.15, y, ink);
    }
}
