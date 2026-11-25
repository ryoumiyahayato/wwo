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
    #[serde(default)]
    fills: Vec<Vec<[f32; 2]>>,
}

static GLYPHS: LazyLock<HashMap<String, Glyph>> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../map-marker-glyphs.json")).expect("invalid map marker artwork")
});

pub fn glyph(mesh: &mut Mesh, name: &str, [x, y]: [f32; 2], size: f32, ink: [u8; 4]) {
    let scale = size / 24.;
    let glyph = &GLYPHS[name];
    let project = |[u, v]: [f32; 2], offset: f32| [x + (u - 12.) * scale, y + (v - 12.) * scale + offset];
    let fade = |mut color: [u8; 4]| { color[3] = (u16::from(color[3]) * u16::from(ink[3]) / 255) as u8; color };
    let paint = |mesh: &mut Mesh, width, offset: f32, color| {
        for path in &glyph.paths {
            for segment in path.windows(2) {
                mesh.line(project(segment[0],offset), project(segment[1],offset), width * scale, color);
            }
        }
    };
    paint(mesh, 3.6, 0.85, fade(SHADOW));
    if glyph.fills.is_empty() {
        paint(mesh, 3.5, 0., fade(OUTLINE));
        paint(mesh, 1.9, 0., ink);
        return;
    }
    let center = [ink[0].saturating_sub(45), ink[1].saturating_sub(48), ink[2].saturating_sub(41), ink[3]];
    let fill = |mesh: &mut Mesh, offset, color| {
        for polygon in &glyph.fills {
            let points:Vec<_> = polygon.iter().map(|&point|project(point,offset)).collect();
            mesh.shape(&points,color);
        }
    };
    fill(mesh,0.85,fade(SHADOW));
    fill(mesh,0.,center);
    paint(mesh, 2.75, 0., fade(OUTLINE));
    paint(mesh, 1.35, 0., ink);
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
