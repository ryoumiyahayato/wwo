use crate::landmarks::{ModelMesh, ModelVertex};
use glam::{Quat, Vec3};

const STONE: [f32; 3] = [0.45, 0.44, 0.40];
const COURT: [f32; 3] = [0.24, 0.22, 0.19];
const BRICK: [f32; 3] = [0.31, 0.18, 0.14];
const LACQUER: [f32; 3] = [0.42, 0.11, 0.065];
const GOLD_TILE: [f32; 3] = [0.58, 0.33, 0.075];
const GRAY_TILE: [f32; 3] = [0.145, 0.15, 0.14];
const WALL_COPING: [f32; 3] = [0.25, 0.19, 0.13];
const WATER: [f32; 3] = [0.085, 0.19, 0.20];
const GARDEN: [f32; 3] = [0.24, 0.28, 0.17];

type Point = [f32; 3];

struct Architecture(ModelMesh);

impl Architecture {
    fn face(&mut self, points: &[Point], color: [f32; 3]) {
        let edge = |i| Vec3::from_array(points[i]) - Vec3::from_array(points[0]);
        let normal = edge(1).cross(edge(2)).normalize().to_array();
        let base = self.0.vertices.len() as u32;
        self.0
            .vertices
            .extend(points.iter().map(|&position| ModelVertex {
                position,
                normal,
                color: [color[0], color[1], color[2], 1.],
            }));
        for i in 1..points.len() as u32 - 1 {
            self.0.indices.extend([base, base + i, base + i + 1]);
        }
    }

    fn surface(&mut self, center: [f32; 2], size: [f32; 2], y: f32, color: [f32; 3]) {
        let [a, b, c, d] = rectangle(center, size, y, 0.);
        self.face(&[a, d, c, b], color);
    }

    fn block(&mut self, center: [f32; 2], size: [f32; 2], base: f32, height: f32, color: [f32; 3]) {
        let bottom = rectangle(center, size, base, 0.);
        let top = rectangle(center, size, base + height, 0.);
        self.band(bottom, top, color);
        self.face(&[top[0], top[3], top[2], top[1]], color);
    }

    fn band(&mut self, lower: [Point; 4], upper: [Point; 4], color: [f32; 3]) {
        for i in 0..4 {
            let next = (i + 1) % 4;
            self.face(&[lower[i], upper[i], upper[next]], color);
            self.face(&[lower[i], upper[next], lower[next]], color);
        }
    }

    // Curved eaves and a hip ridge in local metres. Used for halls, gates and pavilions.
    fn hip_roof(&mut self, center: [f32; 2], [w, d]: [f32; 2], y: f32, h: f32, color: [f32; 3]) {
        let along_z = d > w;
        let (w, d) = if along_z { (d, w) } else { (w, d) };
        let ring = |size, y, lift| {
            rectangle([0.; 2], size, y, lift).map(|[x, y, z]| {
                let [x, z] = if along_z { [z, -x] } else { [x, z] };
                [center[0] + x, y, center[1] + z]
            })
        };
        let eave = ring([w, d], y, h * 0.12);
        let lower_slope = ring([w * 0.92, d * 0.70], y + h * 0.18, 0.);
        let upper_slope = ring([w * 0.80, d * 0.32], y + h * 0.53, 0.);
        let ridge = ring([w * 0.61, d * 0.035], y + h, 0.);
        let lip = ring([w, d], y - 0.38, h * 0.12);
        self.band(lip, eave, color.map(|component| component * 0.62));
        self.band(eave, lower_slope, color);
        self.band(lower_slope, upper_slope, color);
        self.band(upper_slope, ridge, color);
        self.face(&[ridge[0], ridge[3], ridge[2], ridge[1]], color);
    }

    fn hall(
        &mut self,
        center: [f32; 2],
        [w, d]: [f32; 2],
        y: f32,
        h: f32,
        roof: [f32; 3],
        double_eaves: bool,
    ) {
        let wall_top = y + h * 0.56;
        self.block(center, [w * 0.86, d * 0.75], y, h * 0.56, LACQUER);
        if w >= 22. {
            for bay in -4..=4 {
                let x = center[0] + bay as f32 * w * 0.105;
                let column = (w * 0.023).clamp(0.5, 1.6);
                for side in [-1., 1.] {
                    self.block(
                        [x, center[1] + side * d * 0.40],
                        [column; 2],
                        y,
                        h * 0.56,
                        BRICK,
                    );
                }
            }
        }
        if double_eaves {
            self.hip_roof(center, [w, d], wall_top, h * 0.32, roof);
            self.block(center, [w * 0.68, d * 0.52], wall_top, h * 0.23, LACQUER);
            self.hip_roof(center, [w * 0.82, d * 0.68], y + h * 0.79, h * 0.44, roof);
        } else {
            self.hip_roof(center, [w, d], wall_top, h * 0.44, roof);
        }
    }

    fn gate(&mut self, [x, z]: [f32; 2], width: f32, depth: f32, east_west: bool) {
        let rotation = Quat::from_rotation_y(if east_west {
            std::f32::consts::FRAC_PI_2
        } else {
            0.
        });
        let start = self.0.vertices.len();
        for side in [-1., 1.] {
            self.block(
                [side * width * 0.32, 0.],
                [width * 0.36, depth],
                0.,
                10.,
                BRICK,
            );
        }
        self.block([0., 0.], [width, depth], 7.3, 2.7, BRICK);
        self.hall(
            [0., 0.],
            [width * 0.87, depth * 1.32],
            10.,
            10.,
            GOLD_TILE,
            true,
        );
        for vertex in &mut self.0.vertices[start..] {
            vertex.position =
                (rotation * Vec3::from_array(vertex.position) + Vec3::new(x, 0., z)).to_array();
            vertex.normal = (rotation * Vec3::from_array(vertex.normal)).to_array();
        }
    }

    fn courtyard(&mut self, [x, z]: [f32; 2], [width, depth]: [f32; 2], roof: [f32; 3]) {
        self.surface([x, z], [width, depth], 0.44, COURT.map(|c| c * 1.19));
        self.hall(
            [x, z - depth * 0.37],
            [width * 0.91, 12.],
            0.6,
            7.,
            roof,
            false,
        );
        for side in [-1., 1.] {
            let edge = x + side * width * 0.40;
            self.block([edge, z], [6., depth * 0.57], 0.6, 4.8, BRICK);
            self.hip_roof([edge, z], [7.4, depth * 0.60], 5.4, 2.2, roof);
        }
        let gate_width = 8.;
        let wall_len = (width - gate_width) * 0.5;
        for end in [-1., 1.] {
            let wall_x = x + end * (wall_len + gate_width) * 0.5;
            self.block([wall_x, z + depth * 0.48], [wall_len, 2.5], 0.4, 3.4, BRICK);
        }
    }

    fn trees(&mut self, placements: impl IntoIterator<Item = [f32; 6]>) {
        let (tree, triangles) = crate::landscape_models::park_tree();
        for [x, y, z, radius, height, tone_offset] in placements {
            let origin = Vec3::new(x, y, z);
            let scale = Vec3::new(radius, height, radius);
            let turn = Quat::from_rotation_y(tone_offset * std::f32::consts::TAU);
            let base = self.0.vertices.len() as u32;
            self.0
                .vertices
                .extend(tree.iter().map(|&(position, normal, tone)| {
                    let color = if tone < 0. {
                        [0.12, 0.09, 0.053]
                    } else {
                        [0.11, 0.19, 0.08].map(|c| c * tone * (0.84 + 0.34 * tone_offset))
                    };
                    ModelVertex {
                        position: (origin + turn * (Vec3::from_array(position) * scale)).to_array(),
                        normal: (turn * (Vec3::from_array(normal) / scale).normalize()).to_array(),
                        color: [color[0], color[1], color[2], 1.],
                    }
                }));
            self.0
                .indices
                .extend(triangles.iter().map(|&i| base + u32::from(i)));
        }
    }
}

fn rectangle([x, z]: [f32; 2], [w, d]: [f32; 2], y: f32, lift: f32) -> [Point; 4] {
    [
        [x - w * 0.5, y + lift, z - d * 0.5],
        [x + w * 0.5, y + lift, z - d * 0.5],
        [x + w * 0.5, y + lift, z + d * 0.5],
        [x - w * 0.5, y + lift, z + d * 0.5],
    ]
}

pub(crate) fn hall_of_prayer() -> ModelMesh {
    const SEGMENTS: usize = 48;
    const MARBLE: [f32; 3] = [0.67, 0.65, 0.59];
    const BLUE_TILE: [f32; 3] = [0.035, 0.116, 0.305];
    const BLUE_TRIM: [f32; 3] = [0.053, 0.194, 0.281];
    let mut hall = Architecture(ModelMesh::default());
    let ring = |i: usize, r: f32, y: f32| {
        let (sin, cos) = (i as f32 * std::f32::consts::TAU / SEGMENTS as f32).sin_cos();
        [r * cos, y, r * sin]
    };
    let mut band = |lower: [f32; 2], upper: [f32; 2], color| {
        for i in 0..SEGMENTS {
            hall.face(&[
                ring(i, lower[0], lower[1]), ring(i, upper[0], upper[1]),
                ring(i + 1, upper[0], upper[1]), ring(i + 1, lower[0], lower[1]),
            ], color);
        }
    };
    for (radius, y, inner) in [(45.5, 0., 40.), (40., 1.9, 34.), (34., 3.75, 16.36)] {
        let summit = if y == 3.75 { 5.6 } else { y + 1.9 };
        band([radius, y], [radius, summit], MARBLE);
        band([radius, summit], [inner, summit], MARBLE);
    }
    band([13.8, 5.6], [13.8, 15.], LACQUER);
    for (eave, peak, radius, crown) in [
        (15., 21.4, 16.36, 10.5), (22.8, 27.6, 12.8, 7.6), (29.3, 36.2, 9.1, 0.95),
    ] {
        band([radius, eave - 0.55], [radius, eave], BLUE_TRIM);
        band([radius, eave], [radius * 0.82 + crown * 0.18, eave + 0.8], BLUE_TILE);
        band([radius * 0.82 + crown * 0.18, eave + 0.8], [crown, peak], BLUE_TILE);
        if crown > 1. {
            band([crown, peak], [crown, if eave < 20. { 22.8 } else { 29.3 }], LACQUER);
        }
    }
    band([0.95, 36.2], [0.85, 37.2], GOLD_TILE);
    band([0.85, 37.2], [0.27, 38.], GOLD_TILE);
    for i in 0..12 {
        let [x, _, z] = ring(i * 4, 14.15, 0.);
        hall.block([x, z], [0.72; 2], 5.6, 8.8, BRICK);
    }
    for angle in [0., std::f32::consts::FRAC_PI_2, std::f32::consts::PI, -std::f32::consts::FRAC_PI_2] {
        let first = hall.0.vertices.len();
        for (base, z, riser) in [(0., 44.8, 0.19), (1.9, 39.4, 0.185), (3.75, 33.4, 0.185)] {
            for step in 1..=10 {
                hall.block([0., z + 1.85 - step as f32 * 0.37], [6.8, 0.39], base, step as f32 * riser, MARBLE);
            }
        }
        let rotate = Quat::from_rotation_y(angle);
        for vertex in &mut hall.0.vertices[first..] {
            vertex.position = (rotate * Vec3::from_array(vertex.position)).to_array();
            vertex.normal = (rotate * Vec3::from_array(vertex.normal)).to_array();
        }
    }
    hall.0
}

pub(crate) fn forbidden_city() -> ModelMesh {
    let mut mesh = Architecture(ModelMesh::default());
    let (half_w, half_d, moat) = (376.5, 480.5, 52.);
    let width = 2. * half_w;
    let depth = 2. * half_d;
    mesh.surface([0., 0.], [width, depth], 0.26, COURT);
    for side in [-1., 1.] {
        mesh.surface(
            [0., side * (half_d + moat * 0.5)],
            [width + 2. * moat, moat],
            0.18,
            WATER,
        );
        mesh.surface(
            [side * (half_w + moat * 0.5), 0.],
            [moat, depth],
            0.18,
            WATER,
        );
        mesh.surface([0., side * (half_d + moat * 0.5)], [16., moat], 1., STONE);
        mesh.surface([side * (half_w + moat * 0.5), 51.], [moat, 12.], 1., STONE);

        // Leave gate openings in the perimeter. Meridian Gate's wings sit inside the wall.
        let north_south_gate = if side > 0. { 62. } else { 40. };
        for end in [-1., 1.] {
            let span = half_w - north_south_gate * 0.5;
            let center = end * (half_w - span * 0.5);
            mesh.block([center, side * half_d], [span, 8.], 0., 9.8, BRICK);
            mesh.block([center, side * half_d], [span, 8.3], 9.8, 0.6, WALL_COPING);
            mesh.block([end * half_w, side * half_d], [18., 18.], 0., 9.8, BRICK);
            mesh.hall(
                [end * half_w, side * half_d],
                [21., 20.],
                9.8,
                8.,
                GOLD_TILE,
                true,
            );
        }
        let side_gate_z = 51.;
        let open_half = 18.;
        for [start, end] in [
            [-half_d, side_gate_z - open_half],
            [side_gate_z + open_half, half_d],
        ] {
            let center = [side * half_w, (start + end) * 0.5];
            mesh.block(center, [8., end - start], 0., 9.8, BRICK);
            mesh.block(center, [8.3, end - start], 9.8, 0.6, WALL_COPING);
        }
        mesh.gate([side * half_w, side_gate_z], 36., 12., true);
        mesh.block([side * 34.5, 451.], [13., 57.], 0., 10., BRICK);
        mesh.hall([side * 34.5, 445.], [16., 42.], 10., 8., GOLD_TILE, true);
    }
    mesh.gate([0., 478.], 62., 17., false);
    mesh.gate([0., -477.], 40., 15., false);

    // The ceremonial axis preserves the order and relative scale of the principal halls.
    for [z, w, d] in [
        [362., 188., 126.],
        [185., 211., 169.],
        [-154., 83., 164.],
        [-358., 100., 88.],
    ] {
        mesh.surface([0., z], [w, d], 0.42, STONE);
    }
    mesh.surface([0., 0.], [12., 940.], 0.55, STONE);
    mesh.surface([0., 363.], [188., 13.], 0.68, WATER);
    for x in [-34., -17., 0., 17., 34.] {
        mesh.block([x, 363.], [8., 19.], 0.60, 1.2, STONE);
    }
    mesh.hall([0., 293.], [58., 27.], 1., 16., GOLD_TILE, true);
    // The three-tier marble platform widens at each end of the central terrace.
    for [inset, base] in [[0., 0.6], [4., 3.1], [8., 5.6]] {
        for [z, w, d] in [[121., 120., 62.], [71., 89., 38.], [24., 117., 56.]] {
            mesh.block([0., z], [w - inset, d], base, 2.5, STONE);
        }
    }
    for (z, w, d, y, h, double_eaves) in [
        (125., 64., 37., 8.1, 28., true),
        (69., 25., 23., 8.1, 14., false),
        (24., 50., 31., 8.1, 20., true),
        (-107., 48., 28., 1.6, 21., true),
        (-157., 23., 22., 1.6, 14., false),
        (-199., 47., 23., 1.6, 16., true),
    ] {
        mesh.hall([0., z], [w, d], y, h, GOLD_TILE, double_eaves);
    }

    // Enclosed side courts use smaller halls with grey service roofs and glazed formal roofs.
    for side in [-1., 1.] {
        for [x, z, depth] in [[101., 358., 103.], [109., 195., 150.], [117., 73., 72.]] {
            mesh.block([side * x, z], [7., depth], 0.4, 6., BRICK);
            mesh.hip_roof([side * x, z], [9., depth + 2.], 6.4, 2.4, GOLD_TILE);
        }
        for (x, z, w, d, gold) in [
            (144., 325., 50., 71., false),
            (206., 331., 56., 77., false),
            (282., 315., 66., 81., false),
            (273., 222., 70., 68., false),
            (163., 205., 62., 112., false),
            (227., 96., 68., 110., true),
            (227., 14., 68., 47., true),
            (150., 23., 52., 61., false),
            (81., -113., 37., 54., true),
            (127., -113., 37., 56., true),
            (81., -182., 37., 56., true),
            (127., -185., 37., 59., true),
            (81., -251., 37., 58., true),
            (127., -256., 37., 58., true),
            (174., -90., 46., 57., false),
            (176., -160., 45., 61., true),
            (181., -233., 43., 63., true),
            (174., -310., 45., 54., true),
            (248., -123., 65., 71., true),
            (252., -206., 64., 68., true),
            (254., -286., 59., 67., true),
            (270., -368., 61., 70., false),
        ] {
            mesh.courtyard(
                [x * side, z],
                [w, d],
                if gold { GOLD_TILE } else { GRAY_TILE },
            );
        }
        mesh.surface([side * 47., -366.], [68., 93.], 0.62, GARDEN);
        mesh.surface([side * 47., -367.], [68., 6.], 0.74, STONE);
        mesh.surface([side * 47., -366.], [6., 93.], 0.75, STONE);
        mesh.hall([side * 55., -351.], [16., 15.], 0.8, 8., GOLD_TILE, true);
        mesh.trees(
            [
                [28., -328., 5.7, 11.],
                [67., -334., 5.4, 12.],
                [34., -351., 4.8, 9.],
                [68., -382., 6.1, 14.],
                [29., -389., 5.1, 12.],
                [57., -402., 5.4, 10.],
            ]
            .map(|[x, z, r, h]| [x * side, 0.63, z, r, h, (x / 72.) % 1.]),
        );
    }
    mesh.hall([0., -392.], [27., 20.], 0.7, 13., GOLD_TILE, true);
    jingshan(&mut mesh);
    mesh.0
}

fn jingshan(mesh: &mut Architecture) {
    // The historic garden lies just across the moat from the north gate.
    let depth_center = -799.;
    let hill = |x: f32, z: f32| {
        let east_west = x / 225.;
        let north_south = (z - depth_center) / 117.;
        45.7 * (1. - east_west * east_west - north_south * north_south)
            .max(0.)
            .powf(1.25)
    };
    let ground = |x, z| [x, 0.47 + hill(x, z), z];
    mesh.surface([0., -789.], [582., 395.], 0.43, GARDEN);
    mesh.surface([0., -610.], [20., 156.], 0.54, STONE);
    for x in [-289., 289.] {
        mesh.block([x, -789.], [3.4, 395.], 0.43, 3.1, BRICK);
    }
    mesh.block([0., -985.], [582., 3.4], 0.43, 3.1, BRICK);
    for x in [-151., 151.] {
        mesh.block([x, -592.], [278., 3.4], 0.43, 3.1, BRICK);
    }
    for column in -12..12 {
        for row in -6..6 {
            let x = column as f32 * 20.;
            let z = depth_center + row as f32 * 20.;
            let a = ground(x, z);
            let b = ground(x, z + 20.);
            let c = ground(x + 20., z + 20.);
            let d = ground(x + 20., z);
            let green = (0.71 + (a[1] + c[1]) * 0.003).min(0.95);
            let color = GARDEN.map(|value| value * green);
            mesh.face(&[a, b, c], color);
            mesh.face(&[a, c, d], color);
        }
    }
    // Five Qing pavilions span the crest, with the central one highest on the axis.
    for x in [-170_f32, -83., 0., 83., 170.] {
        let width = if x == 0. { 21. } else { 12. };
        let y = hill(x, depth_center);
        mesh.block([x, depth_center], [width + 6.; 2], y - 2., 4., STONE);
        mesh.hall(
            [x, depth_center],
            [width; 2],
            y + 2.,
            9.,
            if x == 0. { GOLD_TILE } else { GRAY_TILE },
            true,
        );
    }
    mesh.hall([0., -619.], [34., 17.], 0.9, 14., GRAY_TILE, true);
    mesh.courtyard([0., -946.], [123., 77.], GOLD_TILE);
    mesh.trees((-8_i32..=8).flat_map(|column| {
        (-3_i32..=3).filter_map(move |row| {
            let shift = (column * 31 + row * 13).rem_euclid(17) as f32;
            let x = column as f32 * 26. + shift - 8.;
            let z = depth_center + row as f32 * 27. + shift * 0.65;
            (row != 0 && hill(x, z) > 3.).then(|| {
                [
                    x,
                    hill(x, z) + 0.22,
                    z,
                    6.2 + shift * 0.21,
                    11. + shift * 0.34,
                    shift / 17.,
                ]
            })
        })
    }));
}
