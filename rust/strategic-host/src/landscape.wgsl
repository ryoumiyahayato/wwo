// Z7 uses the same 256 core samples and four-sample border as the color QPK.
struct LandscapePage {
    texel: vec2f,
    slot: i32,
    fade: f32,
};

fn landscape_page(ll: vec2f) -> LandscapePage {
    let uv = vec2f(min(fract(ll.x / 360. + .5), .99999994), clamp(.5 - ll.y / 180., 0., .99999994));
    let cell = uv * vec2f(256., 128.);
    let at = vec2i(cell) + vec2i(0, 127);
    let index = textureLoad(terrain_index, at, 0).r;
    return LandscapePage(fract(cell) * 256. + 4., i32(index & 65535u) - 1, f32(index >> 24u) / 255.);
}

fn landscape_elevation(page: LandscapePage, offset: vec2f) -> f32 {
    let rg = textureSampleLevel(landscape_data, linear, (page.texel + offset) / 264., page.slot, 0.).rg;
    return dot(rg, vec2f(255., 65280.)) - 32768.;
}

fn landscape_coverage(page: LandscapePage) -> f32 {
    return textureSampleLevel(terrain_detail, linear, page.texel / 264., page.slot, 0.).a;
}

fn landscape_surface_weight() -> f32 {
    if view.map_style.z < 7. || view.settings.y >= .5 { return 0.; }
    return select(clamp(view.natural_lod[1].w, 0., 1.), 1., view.chart_origin.w > .5);
}

fn landscape_slope(page: LandscapePage, latitude: f32, radius: f32) -> vec2f {
    // Samples on both sides of the center use the shared QPK gutter.
    let east = landscape_elevation(page, vec2f(radius,0.));
    let west = landscape_elevation(page, vec2f(-radius,0.));
    let north = landscape_elevation(page, vec2f(0.,-radius));
    let south = landscape_elevation(page, vec2f(0.,radius));
    let metres = (PI * EARTH) / 32768.;
    return vec2f(east-west, north-south) / (2. * radius * metres * vec2f(max(.025, cos(radians(latitude))), 1.));
}

const LANDSCAPE_SUN: vec3f = vec3f(-.59, .54, .60);

fn landscape_grove(world: vec3f) -> f32 {
    let point = world * 1170.;
    let groves = noise(point.xz + point.y * vec2f(.91,-.61));
    let clearings = noise(point.zy * 2.1 - point.x * vec2f(.83,.72));
    return mix(groves, clearings, .30);
}

fn landscape_material(page: LandscapePage) -> vec2f {
    // Recover the area-weighted bare-ground and ice classes. Interpolating
    // category numbers directly would create other classes along their edges.
    let uv = page.texel / 264.;
    let classes = textureGather(3, landscape_data, linear, uv, page.slot) * (255. / 60.);
    let f = fract(page.texel - .5);
    let weights = vec4f((1.-f.x)*f.y, f.x*f.y, f.x*(1.-f.y), (1.-f.x)*(1.-f.y));
    let bare = dot(weights, select(vec4f(0.), vec4f(1.), abs(classes - 2.) < vec4f(.02)));
    let ice = dot(weights, select(vec4f(0.), vec4f(1.), abs(classes - 4.) < vec4f(.02)));
    return vec2f(bare, ice);
}

fn landscape_survey_mask(ll: vec2f, mpp: f32) -> f32 {
    if view.close_sample.z <= .5 || view.close_sample.x <= 0. { return 0.; }
    let survey = close_terrain(ll, mpp / max(.3, view.chart_origin.z), vec4f(0.,0.,0.,-1.));
    return clamp(1. + survey.a, 0., 1.);
}

fn landscape_relief(base: vec3f, ll: vec2f, world: vec3f, water: f32, mpp: f32) -> vec3f {
    let detail = landscape_surface_weight() * (1. - smoothstep(120., 520., mpp));
    if detail <= .001 || water > .65 { return base; }
    let page = landscape_page(ll);
    if page.fade <= 0. { return base; }
    let strength = detail * page.fade * (1. - smoothstep(.04, .65, water));
    let near = 1. - smoothstep(29., 155., mpp);
    let broad_slope = landscape_slope(page, ll.y, 1.25);
    var slope = broad_slope;
    if near > .001 {
        slope = mix(broad_slope, landscape_slope(page, ll.y, .48), near * .75);
    }
    let height = landscape_elevation(page, vec2f(0.));
    let latitude_scale = max(.025, cos(radians(ll.y)));
    let toward_sun = vec2f(-1.2, -1.10 * latitude_scale);
    let shoulder = landscape_elevation(page, toward_sun);
    let ridge = landscape_elevation(page, toward_sun * 2.);
    let horizon = max((shoulder-height), (ridge-height)*.5) / (995. * latitude_scale);
    let gradient = length(slope);
    let normal = normalize(vec3f(-slope * 1.66, 1.));
    let sunlight = max(0., dot(normal, LANDSCAPE_SUN));
    let exposure = 1. - smoothstep(.46, 1.12, horizon) * .52;
    let steep = smoothstep(.23, .88, gradient);
    let crest = shoulder*2. - ridge - height;
    let ridge_light = clamp(crest / 210., -.11, .13) * steep;
    let modern = 1. - landscape_survey_mask(ll, mpp);
    let forest = textureSampleLevel(landscape_data, linear, page.texel / 264., page.slot, 0.).b * modern;
    let land = landscape_material(page) * modern;
    let rock = (1.-forest) * (1.-land.y)
        * max(land.x * smoothstep(.12, .52, gradient) * .85, steep * .86);
    let shading = clamp((sunlight*exposure - .60) * (.72 + .15*near) + ridge_light, -.52, .35);
    var color = base * (1. + shading);
    if near > .001 {
        // Sub-grid detail is color only. Ridge and valley relief comes from the DEM.
        let axis = normalize(slope + vec2f(.00001, 0.));
        let grains = noise(world.xz * 30100. + world.y * vec2f(21000.,-15800.));
        let bands = sin(height * .064 + grains * 4.) * .07;
        let chips = noise(world.xy * 48000. + world.z * vec2f(36300.,-25800.)) - .5;
        let bedrock = mix(base, vec3f(.51,.47,.40), .30)
            + vec3f((bands + chips * .14) * (.7 + .3*abs(axis.x)));
        let snow = mix(base, vec3f(.76,.82,.85), .73)
            + vec3f(chips * .035 + min(0., bands) * steep * .22);
        let cold_relief = snow * (.73 + .34 * sunlight * exposure + ridge_light);
        color = mix(color, bedrock * (1. + shading), rock * near * modern * .91);
        color = mix(color, cold_relief, land.y * near * .92);
    }
    let grove = landscape_grove(world);
    let forest_tone = mix(.91, 1.038, smoothstep(.18,.74,grove));
    color *= mix(1., forest_tone, forest);
    return clamp(mix(base, color, strength), vec3f(0.), vec3f(1.));
}

const LANDSCAPE_INSTANCES: u32 = 131072u;
struct LandscapeInstance {
    site: vec4f,    // WGS84 degrees, metres above sea level, yaw
    form: vec4f,    // xy extent, height, opacity
    surface: vec4f, // ground grade east/north, color variation, mesh kind
};

struct LandscapeDraw {
    vertices: u32,
    count: atomic<u32>,
    first_vertex: u32,
    first_instance: u32,
};

@group(1) @binding(5) var<storage, read> landscape_chunks: array<vec4u>;
@group(1) @binding(6) var<storage, read_write> landscape_instances: array<LandscapeInstance>;
@group(1) @binding(7) var<storage, read_write> landscape_draws: array<LandscapeDraw, 3>;

fn landscape_random(seed: u32) -> f32 {
    let state = seed * 747796405u + 2891336453u;
    let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return f32(((word >> 22u) ^ word) >> 8u) / 16777216.;
}

fn landscape_world(ll: vec2f) -> vec3f {
    let angle = radians(ll);
    let latitude = cos(angle.y);
    return vec3f(sin(angle.x) * latitude, sin(angle.y), cos(angle.x) * latitude);
}

fn landscape_pixels(world: vec3f) -> vec2f {
    let xy = vec2f(dot(world, view.chart_east.xyz), dot(world, view.chart_north.xyz));
    let z = dot(world, view.chart_forward.xyz);
    let radius = length(xy);
    let arc = atan2(radius, z);
    let scale = mix(1., select(1., arc / max(radius, .00000001), radius > .00000001), view.viewport.w);
    return view.chart_origin.xy + xy * scale / view.viewport.z * vec2f(1., -view.chart_origin.z);
}

@compute @workgroup_size(8,8,1)
fn landscape_generate(@builtin(global_invocation_id) id: vec3u) {
    let chunk = landscape_chunks[id.z];
    let cell = chunk.xy + id.xy;
    let seed = cell.x * 116831u + cell.y * 24571u;
    let scale = max(1., sqrt(view.viewport.x * view.viewport.y / 2073600.));
    let footprint = view.viewport.z * EARTH * scale;
    let detail = 1. - smoothstep(33., 70., footprint);
    let lod = landscape_surface_weight();
    if detail * lod <= .001 { return; }

    let jitter = .10 + .80 * vec2f(landscape_random(seed), landscape_random(seed + 5221u));
    let ll = (vec2f(cell) + jitter) / vec2f(f32(chunk.z), 98304.) * vec2f(360., -180.) + vec2f(-180.,90.);
    let world = landscape_world(ll);
    let position = landscape_pixels(world);
    let padding = 16. + sqrt(max(0., 1.-view.chart_origin.z*view.chart_origin.z)) * 300. / (view.viewport.z * EARTH);
    if any(position < vec2f(-padding)) || any(position > view.viewport.xy + padding) { return; }

    let page = landscape_page(ll);
    if page.fade <= .001 || landscape_coverage(page) >= .20 { return; }
    let texel = vec2i(page.texel);
    let cover = textureLoad(landscape_data, texel, page.slot, 0);
    let land_class = u32(round(cover.a * (255. / 60.)));
    if land_class == 0u || land_class == 4u { return; }

    let height = landscape_elevation(page, vec2f(0.));
    let slope = landscape_slope(page, ll.y, .83);
    let grade = length(slope);
    let choice = landscape_random(seed + 1951u);
    let hue = landscape_random(seed + 8733u);
    let shape = landscape_random(seed + 6371u);
    let angle = landscape_random(seed + 3191u) * (2. * PI);
    var kind = 2u;
    var form = vec3f(0.);
    var bearing = angle;
    var ground_grade = clamp(slope, vec2f(-1.), vec2f(1.));
    if land_class == 1u {
        let forest = textureSampleLevel(landscape_data, linear, page.texel / 264., page.slot, 0.).b;
        let groves = landscape_grove(world);
        let density = forest * smoothstep(.05, .53, groves);
        if choice > density || grade > 1.24 { return; }
        let altitude = smoothstep(550., 2150., height);
        // Tree cover describes extent. Canopy form uses a visual climate proxy.
        let conifers = smoothstep(32., 66., abs(ll.y) + altitude * 19. + (groves - .5) * 12.);
        let is_conifer = landscape_random(seed + 691u) < conifers;
        kind = select(0u, 1u, is_conifer);
        let radius = mix(77.,174., shape) * mix(.76, 1.13, density) * select(1., .84, is_conifer);
        form = vec3f(radius, radius * mix(.80, 1.12, hue), mix(39., 76., shape));
        ground_grade *= .55;
    } else {
        let exposed = select(smoothstep(.42, .94, grade)*.29, smoothstep(.17, .71, grade)*.84, land_class==2u);
        let mountain = max(smoothstep(280., 1150., height), smoothstep(.29, .81, grade));
        if choice > exposed * mountain { return; }
        let size = mix(57., 193., shape) * mix(.72, 1.20, clamp(grade,0.,1.));
        form = vec3f(size, size * mix(.24, .61, hue), mix(13., 49., shape));
        // Spread the shelf across the slope and bury its base into the DEM.
        bearing = atan2(slope.y,slope.x) + PI*.5 + (hue-.5)*.7;
    }

    let instance = atomicAdd(&landscape_draws[kind].count, 1u);
    if instance >= LANDSCAPE_INSTANCES { return; }
    let opacity = min(page.fade, lod) * detail;
    landscape_instances[kind * LANDSCAPE_INSTANCES + instance] =
        LandscapeInstance(vec4f(ll, height, bearing), vec4f(form, opacity), vec4f(ground_grade, hue, f32(kind)));
}

@compute @workgroup_size(3)
fn landscape_limit_draws(@builtin(local_invocation_index) kind: u32) {
    atomicMin(&landscape_draws[kind].count, LANDSCAPE_INSTANCES);
}

struct LandscapeVertex {
    @builtin(position) clip: vec4f,
    @location(0) site: vec3f,
    @location(1) color: vec4f,
    @location(2) edge: f32,
};

@vertex
fn landscape_vertex(
    @location(0) offset: vec3f, @location(1) normal: vec3f, @location(2) tone: f32, @location(3) edge: f32,
    @location(4) site: vec4f, @location(5) form: vec4f, @location(6) surface: vec4f,
) -> LandscapeVertex {
    let c = cos(site.w);
    let s = sin(site.w);
    let rotate = mat2x2f(c,s,-s,c);
    let xy = rotate * (offset.xy * form.xy);
    let altitude = offset.z * form.z;
    let ground = dot(xy, surface.xy);
    let ll = site.xy + degrees(xy / (EARTH * vec2f(max(.012, cos(radians(site.y))),1.)));
    var pixels = landscape_pixels(landscape_world(ll));
    let pitch = sqrt(max(0., 1. - view.chart_origin.z * view.chart_origin.z));
    let metres_per_pixel = view.viewport.z * EARTH;
    pixels.y -= altitude * pitch / metres_per_pixel;
    let z = site.z + ground + altitude;
    let depth = clamp(.56 - (z + (pixels.y - view.viewport.y*.5)*metres_per_pixel*pitch) / 440000., .002,.998);
    let clip = vec4f(pixels / view.viewport.xy * vec2f(2.,-2.) + vec2f(-1.,1.), depth, 1.);
    let base = array<vec3f,3>(vec3f(.300,.453,.249), vec3f(.211,.345,.275), vec3f(.56,.51,.44));
    let hue = vec3f(.145,.155,.087) * (surface.z - .5);
    let flat = rotate * (normal.xy / form.xy);
    let vertical = normal.z / form.z;
    let facing = normalize(vec3f(flat - surface.xy * vertical, vertical));
    let light = .63 + .47 * max(0., dot(facing, LANDSCAPE_SUN));
    let color = clamp((base[u32(surface.w)] + hue) * light * tone, vec3f(0.), vec3f(1.));
    return LandscapeVertex(clip, vec3f(ll,z), vec4f(color,form.w), edge);
}

@fragment
fn landscape_fragment(input: LandscapeVertex) -> @location(0) vec4f {
    let edge = smoothstep(0., max(fwidth(input.edge) * .64, .001), input.edge);
    let page = landscape_page(input.site.xy);
    if page.fade <= 0. || input.site.z < landscape_elevation(page, vec2f(0.)) - 1.5 { discard; }
    let water = 1. - smoothstep(.12,.46, landscape_coverage(page));
    let modern = 1. - landscape_survey_mask(input.site.xy, view.viewport.z * EARTH);
    let opacity = input.color.a * edge * water * modern;
    if opacity <= .008 { discard; }
    return vec4f(input.color.rgb, opacity);
}
