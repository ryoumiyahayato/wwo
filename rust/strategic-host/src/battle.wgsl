struct View {
    clip: mat4x4f,
    camera_center: vec2f,
    span: f32,
    padding: f32,
}

@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var region_color: texture_2d<f32>;
@group(0) @binding(2) var ground_sampler: sampler;

struct Vertex {
    @builtin(position) clip: vec4f,
    @location(0) world: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec3f,
    @location(3) @interpolate(flat) kind: f32,
}

@vertex fn vertex_main(
    @location(0) position: vec3f, @location(1) normal: vec3f, @location(2) color: vec3f,
    @location(3) col0: vec4f, @location(4) col1: vec4f, @location(5) col2: vec4f,
    @location(6) col3: vec4f, @location(7) tint: vec4f, @location(8) kind: f32,
) -> Vertex {
    let world = mat4x4f(col0, col1, col2, col3) * vec4f(position, 1.);
    let normal_transform = mat3x3f(normalize(col0.xyz), normalize(col1.xyz), normalize(col2.xyz));
    return Vertex(view.clip * world, world.xyz, normal_transform * normal, mix(color, tint.rgb, tint.a), kind);
}

fn ground_seed(p: vec2f) -> f32 {
    let q = fract(vec3f(p.xyx) * .1031);
    let d = q + dot(q, q.yzx + 33.33);
    return fract((d.x + d.y) * d.z);
}

fn ground_grain(p: vec2f) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3. - 2. * f);
    return mix(mix(ground_seed(i), ground_seed(i + vec2f(1., 0.)), u.x),
               mix(ground_seed(i + vec2f(0., 1.)), ground_seed(i + 1.), u.x), u.y) - .5;
}

fn ground_color(p: vec2f, normal: vec3f, dx: vec2f, dy: vec2f, distance: f32) -> vec3f {
    let slope = 1. - smoothstep(.58, .94, normal.y);
    let fallback = mix(vec3f(.33, .41, .24), vec3f(.46, .42, .34), slope);
    let size = vec2f(textureDimensions(region_color));
    let frame = (size - 1.) / 50000.;
    let uv = ((p + 22500.) * frame + .5) / size;
    let reference = textureSampleGrad(region_color, ground_sampler, uv, dx * frame / size, dy * frame / size);
    let color = fallback * (1. - reference.a) + reference.rgb;
    let footprint = max(length(dx), length(dy));
    if footprint >= 2. || distance >= 220. {
        return color;
    }
    // Ground grain follows projected metres. Drop each band as it approaches pixel size.
    let land = 1. - smoothstep(0., .035, color.b - color.g);
    let fade = land * (1. - smoothstep(85., 220., distance));
    let mottling = ground_grain(p / 4.7) * .23 * (1. - smoothstep(.45, 2., footprint));
    let grit = ground_grain(vec2f(p.x + .53 * p.y, p.y - .53 * p.x) / .85)
        * .12 * (1. - smoothstep(.12, .48, footprint));
    return color * (1. + fade * (mottling + grit));
}

@fragment fn fragment_main(input: Vertex) -> @location(0) vec4f {
    let dx = dpdx(input.world.xz);
    let dy = dpdy(input.world.xz);
    let normal = normalize(input.normal);
    let light = .58 + .42 * max(0., dot(normal, normalize(vec3f(-.47, .83, .29))));
    if input.kind >= 2. {
        return vec4f(input.color, 1.);
    }
    let distance = length(input.world.xz - view.camera_center);
    var color = input.color;
    if input.kind < .5 {
        color = ground_color(input.world.xz, normal, dx, dy, distance);
    }
    let fog = smoothstep(view.span * .48, view.span * 1.4, distance) * .25;
    return vec4f(mix(color * light, vec3f(.65, .73, .78), fog), 1.);
}
