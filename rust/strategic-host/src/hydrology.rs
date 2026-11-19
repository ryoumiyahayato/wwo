use crate::{
    camera::{dot, frame, Camera, EARTH, V3},
    overlay::Mesh,
};
use std::{fs, io, path::Path};

const CELL: f64 = 1.;
const COLUMNS: usize = 360;
const ROWS: usize = 180;
const START_MPP: f64 = 650.;
const END_MPP: f64 = 1450.;

type Segment = [[f32; 3]; 2];

struct ReachCell {
    normal: V3,
    segments: Vec<Segment>,
}

#[derive(Clone, Copy, PartialEq)]
struct RiverView {
    axes: [V3; 3],
    center: [f64; 2],
    size: [u32; 2],
    mpp: f64,
    pitch: f64,
    blend: f64,
}

pub struct Rivers {
    cells: Vec<ReachCell>,
    mesh: Mesh,
    previous: Option<RiverView>,
}

impl Rivers {
    pub fn open(path: &Path) -> io::Result<Self> {
        let data = fs::read(path)?;
        let geometry = data
            .strip_prefix(b"WWORIV01")
            .filter(|bytes| bytes.len() % 20 == 0)
            .ok_or_else(|| io::Error::other("河流中心线格式不匹配"))?;
        let mut cells = vec![Vec::new(); COLUMNS * ROWS];
        for bytes in geometry.chunks_exact(20) {
            let coordinate = |offset| {
                f64::from(f32::from_le_bytes(
                    bytes[offset..offset + 4].try_into().unwrap(),
                ))
            };
            let from = [coordinate(4), coordinate(8)];
            let to = [coordinate(12), coordinate(16)];
            if !from.into_iter().chain(to).all(f64::is_finite)
                || from[1].abs() > 90.
                || to[1].abs() > 90.
                || (from[0] - to[0]).abs().max((from[1] - to[1]).abs()) > 2.
            {
                return Err(io::Error::other("无效的 WGS84 河段"));
            }
            let lon = (from[0] + to[0]) * 0.5;
            let lat = (from[1] + to[1]) * 0.5;
            let x = ((lon + 180.).rem_euclid(360.) / CELL) as usize;
            let y = (((lat + 90.) / CELL) as usize).min(ROWS - 1);
            cells[y * COLUMNS + x]
                .push([from, to].map(|ll| frame(ll)[2].map(|component| component as f32)));
        }
        let cells = cells
            .into_iter()
            .enumerate()
            .filter(|(_, segments)| !segments.is_empty())
            .map(|(index, segments)| {
                let lon = (index % COLUMNS) as f64 * CELL - 180. + CELL * 0.5;
                let lat = (index / COLUMNS) as f64 * CELL - 90. + CELL * 0.5;
                ReachCell {
                    normal: frame([lon, lat])[2],
                    segments,
                }
            })
            .collect();
        Ok(Self {
            cells,
            mesh: Mesh::default(),
            previous: None,
        })
    }

    pub fn project(&mut self, camera: &Camera, size: [u32; 2], enabled: bool) -> Option<&Mesh> {
        if !enabled || camera.mpp >= END_MPP {
            self.previous = None;
            return None;
        }
        let (axes, center) = camera.projection(size);
        let view = RiverView {
            axes,
            center,
            size,
            mpp: camera.mpp,
            pitch: camera.pitch(),
            blend: camera.blend(),
        };
        if self.previous == Some(view) {
            return None;
        }
        self.previous = Some(view);
        self.mesh.vertices.clear();
        self.mesh.indices.clear();
        // The cell owns the segment midpoint. Include both its half-diagonal
        // and the maximum endpoint distance permitted by the sidecar format.
        let [w, h] = size.map(f64::from);
        let pitch = view.pitch.cos();
        let offset = (center[0] - w * 0.5).hypot((center[1] - h * 0.5) / pitch);
        let radius = camera.extent(size, 4. + offset) + (1.45 * (CELL + 2.) * 0.5).to_radians();
        let cosine = radius.cos();
        let t = ((camera.mpp - START_MPP) / (END_MPP - START_MPP)).clamp(0., 1.);
        let opacity = (1. - t * t * (3. - 2. * t)) * 0.82;
        let color = [58, 107, 124, (opacity * 255.).round() as u8];
        let scale = EARTH / camera.mpp;
        let project = |point| {
            let [x, y, z] = axes.map(|axis| dot(point, axis));
            if z <= 0. {
                return None;
            }
            let r = x.hypot(y);
            let k = if r > 1e-12 {
                1. - view.blend + view.blend * r.atan2(z) / r
            } else {
                1.
            };
            Some([center[0] + x * k * scale, center[1] - y * k * scale * pitch])
        };
        for cell in &self.cells {
            if dot(cell.normal, axes[2]) < cosine {
                continue;
            }
            for &[a, b] in &cell.segments {
                let (Some(a), Some(b)) = (project(a.map(f64::from)), project(b.map(f64::from)))
                else {
                    continue;
                };
                if a[0].min(b[0]) > w + 2.
                    || a[0].max(b[0]) < -2.
                    || a[1].min(b[1]) > h + 2.
                    || a[1].max(b[1]) < -2.
                {
                    continue;
                }
                let start = self.mesh.vertices.len();
                self.mesh
                    .line(a.map(|v| v as f32), b.map(|v| v as f32), 2.4, color);
                for (vertex, side) in self.mesh.vertices[start..]
                    .iter_mut()
                    .zip([1., 1., -1., -1.])
                {
                    vertex.uv = [side, 0.];
                }
            }
        }
        Some(&self.mesh)
    }

    pub fn visible(&self) -> bool {
        self.previous.is_some()
    }
}
