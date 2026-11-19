// Landscape data follows the color QPK grid, including its four-sample border.
struct LandscapePage {
    texel: vec2f,
    slot: i32,
    fade: f32,
};

fn landscape_page(ll: vec2f, level: u32, at_surface: bool) -> LandscapePage {
    let uv = vec2f(min(fract(ll.x / 360. + .5), .99999994), clamp(.5 - ll.y / 180., 0., .99999994));
    let rows = 1i << level;
    let position = uv * vec2f(f32(rows*2), f32(rows));
    let cell = vec2i(position);
    let index = textureLoad(terrain_index, cell+vec2i(0,rows-1), 0).r;
    let q = fract(position);
    var fade = f32(index >> 24u) / 255.;
    if at_surface && view.chart_origin.w <= .5 { fade=page_coverage(cell,q,rows,24u,fade); }
    return LandscapePage(q * 256. + 4., i32(index & 65535u) - 1, fade);
}

fn landscape_elevation(page: LandscapePage, offset: vec2f) -> f32 {
    let rg = textureSampleLevel(landscape_data, linear, (page.texel + offset) / 264., page.slot, 0.).rg;
    return dot(rg, vec2f(255., 65280.)) - 32768.;
}

fn landscape_coverage(page: LandscapePage) -> f32 {
    return textureSampleLevel(terrain_detail, linear, page.texel / 264., page.slot, 0.).a;
}

fn landscape_surface_weight(level: u32) -> f32 {
    if view.map_style.z < f32(level) || view.settings.y >= .5 { return 0.; }
    if view.chart_origin.w > .5 { return select(0.,1.,view.map_style.z == f32(level)); }
    return clamp(view.natural_lod[1][level-4u], 0., 1.);
}

fn landscape_slope(page: LandscapePage, latitude: f32, radius: f32, level: u32) -> vec2f {
    // Samples on both sides of the center use the shared QPK gutter.
    let east = landscape_elevation(page, vec2f(radius,0.));
    let west = landscape_elevation(page, vec2f(-radius,0.));
    let north = landscape_elevation(page, vec2f(0.,-radius));
    let south = landscape_elevation(page, vec2f(0.,radius));
    let metres = (PI * EARTH) / f32(256u << level);
    return vec2f(east-west, north-south) / (2. * radius * metres * vec2f(max(.025, cos(radians(latitude))), 1.));
}

const LANDSCAPE_SUN: vec3f = vec3f(-.59, .54, .60);

fn landscape_grove(world: vec3f) -> f32 {
    let point = world * 1170.;
    let groves = noise(point.xz + point.y * vec2f(.91,-.61));
    let clearings = noise(point.zy * 2.1 - point.x * vec2f(.83,.72));
    return mix(groves, clearings, .30);
}

struct LandCover {
    forest: f32,
    shrub: f32,
    grass: f32,
    soil: f32,
    urban: f32,
    bare: f32,
    snow: f32,
};

fn class_fraction(classes: vec4u, weights: vec4f, code: u32) -> f32 {
    return dot(weights, select(vec4f(0.), vec4f(1.), classes == vec4u(code)));
}

fn landscape_material(page: LandscapePage) -> LandCover {
    // Interpolate category weights instead of category numbers.
    let uv = page.texel / 264.;
    let classes = vec4u(round(textureGather(3, landscape_data, linear, uv, page.slot) * 15.));
    let f = smoothstep(vec2f(0.), vec2f(1.), fract(page.texel - .5));
    let weights = vec4f((1.-f.x)*f.y, f.x*f.y, f.x*(1.-f.y), (1.-f.x)*(1.-f.y));
    return LandCover(
        class_fraction(classes,weights,1u)+class_fraction(classes,weights,10u),
        class_fraction(classes,weights,2u),
        class_fraction(classes,weights,3u)+class_fraction(classes,weights,9u)+class_fraction(classes,weights,11u),
        class_fraction(classes,weights,4u),
        class_fraction(classes,weights,5u),
        class_fraction(classes,weights,6u),
        class_fraction(classes,weights,7u)
    );
}

fn landscape_survey_mask(ll: vec2f, mpp: f32) -> f32 {
    if view.close_sample.z <= .5 || view.close_sample.x <= 0. { return 0.; }
    let survey = close_terrain(ll, mpp / max(.3, view.chart_origin.z), vec4f(0.,0.,0.,-1.));
    return clamp(1. + survey.a, 0., 1.);
}

fn ground_motif(base: vec3f, ll: vec2f, world: vec3f, page: LandscapePage, level: u32, mpp: f32) -> vec3f {
    let near = 1. - smoothstep(90., 430., mpp);
    let slope = landscape_slope(page,ll.y,mix(1.18,.49,near),level);
    let height = landscape_elevation(page, vec2f(0.));
    let latitude_scale = max(.025, cos(radians(ll.y)));
    let toward_sun = vec2f(-1.26, -1.03 * latitude_scale);
    let shoulder = landscape_elevation(page, toward_sun);
    let ridge = landscape_elevation(page, toward_sun * 2.);
    let horizon = max(shoulder-height,(ridge-height)*.5) / (f32(1u << (7u-level))*870.*latitude_scale);
    let gradient = length(slope);
    let normal = normalize(vec3f(-slope * 1.42, 1.));
    let sunlight = max(0., dot(normal, LANDSCAPE_SUN));
    let exposure = 1. - smoothstep(.44, 1.19, horizon) * .45;
    let steep = smoothstep(.23, .87, gradient);
    let crest = clamp((shoulder*2.-ridge-height)/235.,-.12,.13)*steep;
    let relief = clamp((sunlight*exposure-.60)*(.43+.22*near)+crest,-.44,.34);
    let land = landscape_material(page);
    let facing = abs(world)*abs(world);
    let planes = facing*facing/dot(facing,facing);
    let motif = land_material_band(world,planes,mpp,25300.) - .5;
    let grove = landscape_grove(world);
    let canopy = smoothstep(.13,.54,grove);
    let alpine = smoothstep(1700.,3850.,height);
    let forest = mix(base,mix(vec3f(.28,.35,.221),vec3f(.243,.328,.218),canopy),.49*near)
        * (1. + motif.r*.09 + (canopy-.55)*(.09+.09*(1.-near)));
    let vegetation = mix(base,mix(vec3f(.428,.482,.259),vec3f(.389,.435,.256),alpine),near*.49)
        * (1. + motif.g*.076);
    let earth = mix(base,vec3f(.53,.435,.297),near*.59) * (1. + motif.a*.39);
    let snow = mix(base,mix(vec3f(.72,.79,.82),vec3f(.82,.87,.88),.5+motif.a),near*.73);
    let stone = max(steep*.88,land.bare*mix(.37,.94,alpine));
    let exposed = (1.-land.forest*.89)*(1.-land.snow)*(1.-land.urban) * stone;
    let scree = land.bare * smoothstep(.10,.36,gradient) * (1.-smoothstep(.46,.88,gradient));
    let mineral = mix(vec3f(.42,.377,.318),vec3f(.49,.446,.383),scree+(.5+motif.a)*.18);
    var color = base
        + (forest-base)*land.forest + (vegetation-base)*(land.grass+land.shrub)
        + (earth-base)*(land.soil+land.bare) + (snow-base)*land.snow;
    color = mix(color,mix(base,mineral,near*.87),exposed);
    if near > .001 {
        let relief_world = world*(1.+height/EARTH)+vec3f(motif.a,motif.g,motif.b)*.00027;
        let grains = land_material_band(relief_world,planes,mpp,3670.) - .5;
        let texture = grains.r*(land.forest*.34+land.shrub*.22)
            + grains.g*land.grass*.43 + grains.a*(land.soil*.49+land.bare*.29+scree*.25)
            + grains.b*(exposed*.91+scree*.37) + grains.a*(land.snow*.08+land.urban*.13)
            + motif.b*exposed*.17;
        color *= 1. + texture*near;
    }
    let icelight = clamp(relief,-.32,.075);
    return clamp(color * (1.+mix(relief,icelight,land.snow*near)),vec3f(0.),vec3f(1.));
}

fn landscape_relief(base: vec3f, ll: vec2f, world: vec3f, water: f32, mpp: f32) -> vec3f {
    if water > .65 || mpp > 1720. || view.settings.y >= .5 || view.map_style.z < 6. { return base; }
    let modern = 1. - landscape_survey_mask(ll,mpp);
    let strength = (1.-smoothstep(880.,1720.,mpp)) * (1.-smoothstep(.04,.65,water)) * modern;
    if strength <= .001 { return base; }
    let child = landscape_page(ll,7u,true);
    let fine = landscape_surface_weight(7u)*child.fade;
    var surface = base;
    var regional = 0.;
    if fine < .999 {
        let parent = landscape_page(ll,6u,true);
        regional = landscape_surface_weight(6u)*parent.fade;
        if regional > .001 { surface = mix(base,ground_motif(base,ll,world,parent,6u,mpp),regional); }
    }
    if fine > .001 { surface = mix(surface,ground_motif(base,ll,world,child,7u,mpp),fine); }
    return mix(base,surface,strength);
}

const LANDSCAPE_INSTANCES: u32 = 65536u;
const LANDSCAPE_VISIBLE: u32 = 1728u;

struct LandscapeInstance {
    cell: vec2u,
    style: u32,    // longitude count, mesh kind, lattice step, cover weight
    terrain: u32,  // signed metres and two quantized surface gradients
};

struct LandscapeDraw {
    vertices: u32,
    count: atomic<u32>,
    first_vertex: u32,
    first_instance: u32,
};

@group(1) @binding(5) var<storage, read> landscape_chunks: array<vec4u>;
@group(1) @binding(6) var<storage, read_write> landscape_instances: array<LandscapeInstance>;
@group(1) @binding(7) var<storage, read_write> landscape_draws: array<LandscapeDraw, 5>;
@group(1) @binding(8) var<storage, read_write> landscape_cache: array<LandscapeInstance>;

fn landscape_random(seed: u32) -> f32 {
    let state = seed * 747796405u + 2891336453u;
    let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return f32(((word >> 22u) ^ word) >> 8u) / 16777216.;
}

fn landscape_seed(cell: vec2u) -> u32 {
    return cell.x * 116831u + cell.y * 24571u;
}

fn landscape_coordinates(cell: vec2u, columns: u32) -> vec2f {
    let seed = landscape_seed(cell);
    let jitter = .10 + .80 * vec2f(landscape_random(seed),landscape_random(seed+5221u));
    return (vec2f(cell)+jitter) / vec2f(f32(columns),98304.) * vec2f(360.,-180.) + vec2f(-180.,90.);
}

fn landscape_world(ll: vec2f) -> vec3f {
    let angle = radians(ll);
    let latitude = cos(angle.y);
    return vec3f(sin(angle.x)*latitude,sin(angle.y),cos(angle.x)*latitude);
}

fn landscape_pixels(world: vec3f) -> vec2f {
    let xy = vec2f(dot(world,view.chart_east.xyz),dot(world,view.chart_north.xyz));
    let z = dot(world,view.chart_forward.xyz);
    let radius = length(xy);
    let arc = atan2(radius,z);
    let scale = mix(1.,select(1.,arc/max(radius,.00000001),radius>.00000001),view.viewport.w);
    return view.chart_origin.xy + xy*scale/view.viewport.z*vec2f(1.,-view.chart_origin.z);
}

fn landscape_model_weight(step: u32, footprint: f32) -> f32 {
    if step == 1u { return 1.-smoothstep(36.,72.,footprint); }
    if step == 4u { return smoothstep(34.,69.,footprint)*(1.-smoothstep(145.,300.,footprint)); }
    if step == 16u { return smoothstep(143.,280.,footprint)*(1.-smoothstep(500.,650.,footprint)); }
    return smoothstep(500.,650.,footprint)*(1.-smoothstep(920.,1460.,footprint));
}

fn landscape_local_index(id: vec3u, chunk: vec4u) -> u32 {
    return (chunk.w >> 6u)*256u + id.y*16u + id.x;
}

@compute @workgroup_size(8,8,1)
fn landscape_build(@builtin(global_invocation_id) id: vec3u) {
    let chunk = landscape_chunks[LANDSCAPE_VISIBLE+id.z];
    let cache_index = landscape_local_index(id,chunk);
    landscape_cache[cache_index].style = 0u;
    let step = chunk.w & 63u;
    var cell = chunk.xy + id.xy*step + vec2u(step/2u);
    var columns = chunk.z;
    if step > 1u {
        // Representative group sites use the underlying fine lattice.
        let band = f32(cell.y/16u) + .5;
        let lat = PI * (.5-band/6144.);
        columns = u32(max(1.,round(12288.*cos(lat))))*16u;
        cell.x = min(columns-1u,u32(f32(cell.x)*f32(columns)/f32(chunk.z)));
    }
    let ll = landscape_coordinates(cell,columns);
    let world = landscape_world(ll);
    let level = select(6u,7u,step == 1u || (view.chart_origin.w > .5 && view.map_style.z == 7.));
    let page = landscape_page(ll,level,false);
    if page.fade <= 0. || landscape_coverage(page) >= .20 { return; }
    let cover = textureLoad(landscape_data,vec2i(page.texel),page.slot,0);
    let code = u32(round(cover.a*15.));
    if code == 0u || code == 5u || code == 7u || code == 8u { return; }
    let height = landscape_elevation(page,vec2f(0.));
    let slope = landscape_slope(page,ll.y,.83,level);
    let grade = length(slope);
    let seed = landscape_seed(cell);
    let choice = landscape_random(seed+1951u);
    let grove = landscape_grove(world);
    let wooded = code == 1u || code == 10u;
    let bush = code == 2u || code == 11u;
    var density = 0.;
    var kind = 2u;
    if wooded || bush {
        let cover_amount = select(.44,textureSampleLevel(landscape_data,linear,page.texel/264.,page.slot,0.).b,wooded);
        density = cover_amount * smoothstep(.13,.55,grove);
        let conifers = smoothstep(32.,67.,abs(ll.y)+smoothstep(550.,2150.,height)*18.+(grove-.5)*12.);
        kind = select(0u,1u,landscape_random(seed+691u)<conifers);
        if bush {kind = 3u;}
        if step > 1u {kind = 4u;}
        if grade > 1.24 { return; }
    } else if step == 1u {
        let exposed = select(smoothstep(.42,.94,grade)*.26,smoothstep(.14,.72,grade)*.79,code==6u);
        density = exposed * max(smoothstep(260.,1120.,height),smoothstep(.27,.79,grade));
    }
    if choice >= density { return; }

    let packed_slope = vec2u(round(clamp(slope,-vec2f(1.),vec2f(1.))*127.+128.));
    let packed_height = u32(clamp(round(height)+32768.,0.,65535.));
    let packed_terrain = packed_height | (packed_slope.x<<16u) | (packed_slope.y<<24u);
    let strength = u32(round(clamp(density,0.,1.)*127.));
    let packed_style = columns | (kind<<18u) | (u32(firstTrailingBit(step))<<21u) | (strength<<24u);
    landscape_cache[cache_index] = LandscapeInstance(cell,packed_style,packed_terrain);
}

@compute @workgroup_size(8,8,1)
fn landscape_collect(@builtin(global_invocation_id) id: vec3u) {
    let chunk = landscape_chunks[id.z];
    let item = landscape_cache[landscape_local_index(id,chunk)];
    if item.style == 0u { return; }
    let kind = (item.style>>18u)&7u;
    let instance = atomicAdd(&landscape_draws[kind].count,1u);
    if instance < LANDSCAPE_INSTANCES {
        landscape_instances[kind*LANDSCAPE_INSTANCES+instance] = item;
    }
}

@compute @workgroup_size(5)
fn landscape_limit_draws(@builtin(local_invocation_index) kind: u32) {
    atomicMin(&landscape_draws[kind].count,LANDSCAPE_INSTANCES);
}

struct LandscapeVertex {
    @builtin(position) clip: vec4f,
    @location(0) site: vec3f,
    @location(1) color: vec4f,
    @location(2) edge: f32,
    @location(3) @interpolate(flat) kind: u32,
    @location(4) @interpolate(flat) lod: vec2f,
    @location(5) @interpolate(flat) tree: u32,
};

@vertex
fn landscape_vertex(
    @location(0) offset: vec3f, @location(1) normal: vec3f, @location(2) tone: f32, @location(3) edge: f32,
    @location(4) crown: f32, @location(5) item: vec4u,
) -> LandscapeVertex {
    let columns = item.z & 262143u;
    let kind = (item.z>>18u)&7u;
    let step = 1u << ((item.z>>21u)&7u);
    let density = f32(item.z>>24u)/127.;
    let mpp = view.viewport.z*EARTH;
    let tree = crown > 0.;
    let stand = kind == 0u || kind == 1u || kind == 3u;
    let stand_mix = smoothstep(9.,21.,mpp);
    let representation = select(1.,select(stand_mix,1.-stand_mix,tree),stand);
    if representation <= .012 {
        return LandscapeVertex(vec4f(2.,2.,0.,1.),vec3f(0.),vec4f(0.),0.,kind,vec2f(0.),0u);
    }
    let ll = landscape_coordinates(item.xy,columns);
    let height = f32(item.w&65535u)-32768.;
    let grade = (vec2f(f32((item.w>>16u)&255u),f32(item.w>>24u))-128.)/127.;
    let seed = landscape_seed(item.xy);
    let variation = seed+u32(crown)*8461u;
    let hue = landscape_random(variation+8733u);
    let shape = landscape_random(variation+6371u);
    var bearing = landscape_random(seed+3191u)*(2.*PI);
    var radius = mix(87.,158.,shape)*mix(.84,1.16,density);
    var form = vec3f(radius,radius*mix(.77,1.11,hue),mix(9.,21.,shape));
    var tree_center = vec2f(0.);
    var ground_grade = grade*.93;
    let climate = smoothstep(32.,64.,abs(ll.y)+smoothstep(550.,2200.,height)*16.);
    if kind == 1u {
        form *= vec3f(.85,.85,1.03);
    } else if kind == 2u {
        radius = mix(55.,164.,shape)*mix(.74,1.18,clamp(length(grade),0.,1.));
        form = vec3f(radius,radius*mix(.25,.60,hue),mix(12.,44.,shape));
        bearing = atan2(grade.y,grade.x)+PI*.5+(hue-.5)*.7;
        ground_grade = grade;
    } else if kind == 3u {
        form *= vec3f(.66,.73,.28);
    } else if kind == 4u {
        let spread = f32(step)*mix(1.,.75,smoothstep(16.,32.,f32(step)));
        form *= vec3f(spread*1.07,spread*.92,1.);
    }
    if tree {
        let i = u32(crown)-1u;
        let tile = vec2f(f32(i%7u),f32(i/7u))-3.;
        let jitter = vec2f(landscape_random(variation+399u),landscape_random(variation+791u))-.5;
        tree_center = (tile+jitter*.85)*20.;
        let r = mix(4.6,9.6,shape);
        form = vec3f(r,r*mix(.79,1.08,hue),mix(8.,21.,shape));
        if kind == 1u { form *= vec3f(.71,.71,1.15); }
        if kind == 3u { form *= vec3f(.54,.54,.29); }
    }
    let c = cos(bearing);
    let s = sin(bearing);
    let rotate = mat2x2f(c,s,-s,c);
    let apparent = min(form.x,form.y)*2./mpp;
    // Give subpixel crowns raster coverage while preserving their projected area.
    let filter_width = select(1.,max(1.,1.4/apparent),tree);
    let xy = rotate*(offset.xy*form.xy*filter_width+tree_center);
    let altitude = offset.z*form.z;
    let ground = dot(xy,ground_grade);
    let site = ll+degrees(xy/(EARTH*vec2f(max(.012,cos(radians(ll.y))),1.)));
    var pixels = landscape_pixels(landscape_world(site));
    let pitch = sqrt(max(0.,1.-view.chart_origin.z*view.chart_origin.z));
    let footprint = mpp*max(1.,sqrt(view.viewport.x*view.viewport.y/2073600.));
    let lod = vec2f(landscape_model_weight(step,footprint),landscape_model_weight(step,max(58.,footprint)));
    let visibility = representation*select(smoothstep(2.,4.5,apparent),1./(filter_width*filter_width),tree);
    pixels.y -= altitude*pitch/mpp;
    let z = height+ground+altitude;
    let depth = clamp(.56-(z+(pixels.y-view.viewport.y*.5)*mpp*pitch)/440000.,.002,.998);
    let clip = vec4f(pixels/view.viewport.xy*vec2f(2.,-2.)+vec2f(-1.,1.),depth,1.);
    let bases = array<vec3f,4>(vec3f(.363,.474,.271),vec3f(.324,.421,.285),vec3f(.50,.446,.374),vec3f(.395,.464,.273));
    let base = select(bases[min(kind,3u)],mix(bases[0],bases[1],climate),kind==4u);
    let pigment = vec3f(.128,.132,.079)*(hue-.5);
    let flat = rotate*(normal.xy/form.xy);
    let vertical = normal.z/form.z;
    let facing = normalize(vec3f(flat-ground_grade*vertical,vertical));
    let light = .88+.26*max(0.,dot(facing,LANDSCAPE_SUN));
    let canopy_light = select(vec3f(0.),vec3f(.050,.067,.027),tree);
    let color = clamp((base+pigment+canopy_light)*light*mix(1.,tone,.70),vec3f(0.),vec3f(1.));
    return LandscapeVertex(clip,vec3f(site,z),vec4f(color,visibility),edge,kind,lod,select(0u,1u,tree));
}

fn landscape_object_mask(page: LandscapePage, input: LandscapeVertex) -> f32 {
    let land = 1.-smoothstep(.10,.44,landscape_coverage(page));
    let cover = landscape_material(page);
    let open_ground=1.-smoothstep(.16,.69,cover.urban);
    if input.kind != 4u {
        let clearance = input.site.z-landscape_elevation(page,vec2f(0.));
        let wooded=cover.forest+cover.shrub*.65;
        let growth=select(smoothstep(.17,.68,wooded),smoothstep(.12,.56,wooded),input.tree!=0u);
        return land*open_ground*smoothstep(-4.,0.,clearance)*select(growth,1.,input.kind==2u);
    }
    let wooded=cover.forest+cover.shrub*.55;
    return land*open_ground*smoothstep(.17,.75,wooded);
}

@fragment
fn landscape_fragment(input: LandscapeVertex) -> @location(0) vec4f {
    let rim = fwidth(input.edge)*.68;
    // A subpixel crown spans several short triangles. Keep the rim filter
    // inside those triangles; the vertex shader already filters projected area.
    let edge = smoothstep(0.,max(select(rim,min(rim,.55),input.tree!=0u),.001),input.edge);
    if input.color.a*max(input.lod.x,input.lod.y) <= .012 { discard; }
    let mpp = view.viewport.z*EARTH;
    var fine = 0.;
    var strength = 0.;
    let zoom_fine = landscape_surface_weight(7u);
    if zoom_fine > .001 {
        let page = landscape_page(input.site.xy,7u,true);
        fine = zoom_fine*page.fade;
        if fine*input.lod.x > .001 {
            strength = fine*input.lod.x*landscape_object_mask(page,input);
        }
    }
    if input.kind == 4u && (1.-fine)*input.lod.y > .001 {
        let zoom_regional = landscape_surface_weight(6u);
        if zoom_regional > .001 {
            let page = landscape_page(input.site.xy,6u,true);
            let regional = zoom_regional*page.fade;
            if regional > .001 {
                strength += (1.-fine)*regional*input.lod.y*landscape_object_mask(page,input);
            }
        }
    }
    if strength <= .001 { discard; }
    let modern = 1.-landscape_survey_mask(input.site.xy,mpp);
    let opacity = input.color.a*edge*modern*strength;
    if opacity <= .012 { discard; }
    return vec4f(input.color.rgb,opacity);
}
