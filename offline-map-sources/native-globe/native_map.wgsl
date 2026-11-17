struct View {
    east: vec4f,
    north: vec4f,
    forward: vec4f,
    viewport: vec4f,
    chart_east: vec4f,
    chart_north: vec4f,
    chart_forward: vec4f,
    chart_origin: vec4f,
    settings: vec4f,
    selection: vec4f,
    map_style: vec4f,
};
@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var linear: sampler;
@group(0) @binding(2) var global: texture_2d<f32>;
@group(0) @binding(3) var detail: texture_2d_array<f32>;
@group(0) @binding(4) var pages: texture_2d<u32>;
@group(0) @binding(5) var palette: texture_2d<f32>;
@group(0) @binding(6) var<storage, read> boundaries: array<u32>;

const PI: f32 = 3.14159265358979;
const EARTH: f32 = 6371008.8;

@vertex fn triangle(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
    let points = array<vec2f, 3>(vec2f(-1., -1.), vec2f(3., -1.), vec2f(-1., 3.));
    return vec4f(points[i], 0., 1.);
}

fn geographic(uv: vec2f) -> vec2f {
    return vec2f(fract(uv.x), clamp(uv.y, 0., .99999994));
}

fn surface(uv: vec2f, lod: f32) -> vec4f {
    let coarse = textureSampleLevel(global, linear, uv, lod);
    let weight = view.map_style.y;
    if weight <= 0. { return coarse; }
    let grid = geographic(uv) * vec2f(64., 32.);
    let layer = textureLoad(pages, vec2i(grid), 0).r;
    if layer == 0u { return coarse; }
    let local = (fract(grid) * 256. + 4.) / 264.;
    let fine = textureSampleLevel(detail, linear, local, i32(layer - 1u), 0.);
    return mix(coarse, fine, weight);
}

fn valid(owner: u32) -> bool {
    return owner != 0u && textureLoad(palette, vec2i(i32(owner), 0), 0).a > 0.;
}

fn owner_at(point: vec2f) -> u32 {
    let uv = geographic(point);
    let grid = uv * vec2f(512., 256.);
    let cell = vec2u(grid);
    let index = (cell.y * 512u + cell.x) * 2u;
    let start = boundaries[index];
    let end = boundaries[index + 1u] + 262144u;
    if start + 262144u == end {
        return select(0u, start, valid(start));
    }
    let p = vec2f(fract(grid.x), 1. - fract(grid.y));
    var i = start + 262144u;
    while i < end {
        let owner = boundaries[i];
        let limit = i + 2u + 4u * boundaries[i + 1u];
        if valid(owner) {
            var inside = false;
            for (var j = i + 2u; j < limit; j += 4u) {
                let a = vec2f(bitcast<f32>(boundaries[j]), bitcast<f32>(boundaries[j + 1u]));
                let b = vec2f(bitcast<f32>(boundaries[j + 2u]), bitcast<f32>(boundaries[j + 3u]));
                if (a.y > p.y) != (b.y > p.y) && p.x < a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y) {
                    inside = !inside;
                }
            }
            if inside { return owner; }
        }
        i = limit;
    }
    return 0u;
}

fn elevation(cell: vec4f) -> f32 {
    return dot(cell.rg, vec2f(127.5, 32640.)) - 16384.;
}

fn natural(uv: vec2f, surface_value: vec4f, lod: f32, mpp: f32, latitude: f32) -> vec3f {
    let h = elevation(surface_value);
    let lowland = vec3f(.43, .54, .40);
    let upland = vec3f(.60, .53, .38);
    let rock = vec3f(.70, .65, .59);
    let snow = vec3f(.83, .88, .91);
    var ground = mix(lowland, upland, smoothstep(50., 1400., h));
    ground = mix(ground, rock, smoothstep(1150., 4600., h));
    ground = mix(ground, snow, smoothstep(.58, .96, surface_value.a));
    let scale = max(mix(19500., 2700., view.map_style.y), mpp);
    let delta = vec2f(scale / (2. * PI * EARTH * max(.05, cos(latitude))), scale / (PI * EARTH));
    let east = elevation(surface(uv + vec2f(delta.x, 0.), lod));
    let west = elevation(surface(uv - vec2f(delta.x, 0.), lod));
    let north = elevation(surface(uv - vec2f(0., delta.y), lod));
    let south = elevation(surface(uv + vec2f(0., delta.y), lod));
    let slope = clamp((west - east + north - south) / scale * 2.2, -.37, .32);
    ground *= 1. + slope;
    let river = smoothstep(380., 1150., mpp) * (1. - smoothstep(.12, .50, surface_value.a));
    ground = mix(ground, vec3f(.17, .35, .42), river * .70);
    let water = mix(vec3f(.12, .26, .35), vec3f(.28, .50, .53), 1. - smoothstep(0., 3800., -h));
    return mix(ground, water, smoothstep(.19, .82, surface_value.b));
}

@fragment fn map(@builtin(position) p: vec4f) -> @location(0) vec4f {
    let t = view.viewport.w;
    let xy = (p.xy - view.chart_origin.xy) * view.viewport.z * vec2f(1., -1.);
    let r = length(xy);
    let horizon = mix(1., PI * .5, t);
    let space = vec3f(.036, .053, .071);
    if r >= horizon { return vec4f(space, 1.); }
    let a = select(asin(min(r, 1.)), r, t > 0.);
    let k = select(1., sin(a) / max(r, .00000001), r > .00000001);
    let normal = normalize(view.chart_east.xyz * (xy.x * k) + view.chart_north.xyz * (xy.y * k) + view.chart_forward.xyz * cos(a));
    let ll = vec2f(atan2(normal.x, normal.z), atan2(normal.y, length(normal.xz)));
    let uv = geographic(vec2f(ll.x / (2. * PI) + .5, .5 - ll.y / PI));
    let mpp = view.viewport.z * EARTH;
    let lod = clamp(log2(max(1., mpp / (19546. * max(.05, cos(ll.y))))), 0., 11.);
    let data = surface(uv, lod);
    var color = natural(uv, data, lod, mpp, ll.y);
    if view.settings.y > .5 && view.settings.z > .5 {
        let owner = owner_at(uv);
        if owner != 0u {
            let political = textureLoad(palette, vec2i(i32(owner), 0), 0).rgb;
            let economy = textureLoad(palette, vec2i(i32(owner), 1), 0);
            let economic = view.settings.y > 1.5 && view.settings.y < 2.5;
            let muted = political * .46 + vec3f(.24);
            let ink = select(muted, mix(vec3f(.55), economy.rgb, economy.a), economic);
            let weight = select(.75, .89, economic);
            let land = 1. - smoothstep(.19, .82, data.b);
            color = mix(color, ink, weight * land);
            let dx = mpp / (2. * PI * EARTH * max(.05, cos(ll.y)));
            let dy = mpp / (PI * EARTH);
            let east = owner_at(uv + vec2f(dx, 0.));
            let south = owner_at(uv + vec2f(0., dy));
            let edge = (east != 0u && east != owner) || (south != 0u && south != owner);
            if edge { color *= mix(1., select(.60, 1.20, owner == u32(view.selection.x)), land); }
        }
    }
    if view.settings.y > 2.5 && view.map_style.w > 0. {
        let spacing = view.map_style.w;
        let grid = ll * EARTH / spacing;
        let distance = abs(fract(grid + .5) - .5) * spacing;
        let line_distance = min(distance.x * max(.05, cos(ll.y)), distance.y);
        color = mix(color, vec3f(.75, .76, .61), (1. - smoothstep(0., mpp * 1.5, line_distance)) * .3);
    }
    let shade = .82 + .18 * max(0., dot(normal, normalize(view.forward.xyz + view.north.xyz * .25)));
    return vec4f(mix(space, color * shade, smoothstep(0., view.viewport.z * 1.6, horizon - r)), 1.);
}
