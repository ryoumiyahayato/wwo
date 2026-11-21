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
    if at_surface && view.chart_origin.w <= .5 {
        // A decoded height page can seed build work before color is visible.
        if fade <= 1./255. {fade=0.;}
        else {fade=page_coverage(cell,q,rows,24u,fade);}
    }
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
    let longitude_scale = max(.025, cos(radians(latitude)));
    let polar = 1.-smoothstep(.12,.37,longitude_scale);
    // Narrow longitude texels magnify column-to-column DEM errors near the
    // poles. Expand the physical footprint within the shared QPK gutter.
    let east_radius = mix(radius,min(3.5,radius/longitude_scale),polar);
    let east = landscape_elevation(page, vec2f(east_radius,0.));
    let west = landscape_elevation(page, vec2f(-east_radius,0.));
    let north = landscape_elevation(page, vec2f(0.,-radius));
    let south = landscape_elevation(page, vec2f(0.,radius));
    let metres = (PI * EARTH) / f32(256u << level);
    let east_span = mix(east_radius*longitude_scale,radius,polar);
    return vec2f(east-west, north-south) / (2. * metres * vec2f(east_span,radius));
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
    damp: f32,
    crop: f32,
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
    let f = fract(page.texel - .5);
    let weights = vec4f((1.-f.x)*f.y, f.x*f.y, f.x*(1.-f.y), (1.-f.x)*(1.-f.y));
    return LandCover(
        class_fraction(classes,weights,1u)+class_fraction(classes,weights,10u),
        class_fraction(classes,weights,2u),
        class_fraction(classes,weights,3u),
        class_fraction(classes,weights,9u)+class_fraction(classes,weights,11u),
        class_fraction(classes,weights,4u),
        class_fraction(classes,weights,5u),
        class_fraction(classes,weights,6u),
        class_fraction(classes,weights,7u)
    );
}

fn geographic_ground_tint(ll: vec2f, fallback: vec3f) -> vec3f {
    if textureNumLayers(landscape_data)<=1u || view.map_style.z<6. {return fallback;}
    var page=landscape_page(ll,7u,true);
    if page.fade<.5 {
        page=landscape_page(ll,6u,true);
    }
    if page.fade<=0. {return fallback;}
    let land=landscape_material(page);
    return fallback
        + (vec3f(.255,.41,.31)-fallback)*land.forest
        + (vec3f(.47,.53,.33)-fallback)*(land.grass+land.shrub)
        + (vec3f(.41,.46,.34)-fallback)*land.damp
        + (vec3f(.61,.57,.36)-fallback)*land.crop
        + (vec3f(.73,.61,.44)-fallback)*land.bare
        + (vec3f(.89,.92,.91)-fallback)*land.snow;
}

fn landscape_survey_mask(ll: vec2f, mpp: f32) -> f32 {
    if view.close_sample.z <= .5 || view.close_sample.x <= 0. { return 0.; }
    let survey = close_terrain(ll, mpp / max(.3, view.chart_origin.z), vec4f(0.,0.,0.,-1.));
    return clamp(1. + survey.a, 0., 1.);
}

struct FieldPattern {
    spacing: vec2f,
    stagger: f32,
    curvature: f32,
};

fn parcel_ink(base: vec3f, mpp: f32, cell: vec2f, phase: vec2f, spacing: vec2f) -> vec3f {
    let row = bitcast<u32>(i32(cell.y))*24571u;
    let plant = landscape_random(bitcast<u32>(i32(cell.x))*116831u + row);
    // A second slower variation groups crop colours without repeating an image.
    let group = bitcast<u32>(i32(floor(cell.x*.25)))*1069u
        + bitcast<u32>(i32(floor(cell.y/3.)))*5233u;
    let growth = plant*.76 + landscape_random(group)*.24;
    let tint = mix(vec3f(.57,.49,.34),vec3f(.43,.54,.30),growth);
    let surface = mix(base,tint,.22)*(1.+(growth-.5)*.14);

    let sides = min(phase,1.-phase)*spacing;
    let boundary = 1.-smoothstep(2.,max(8.,mpp*.64),min(sides.x,sides.y));
    let headland = mix(surface,base*vec3f(.91,.94,.87),.44);
    let resolved = 1.-smoothstep(min(spacing.x,spacing.y)*.27,min(spacing.x,spacing.y)*.82,mpp);
    return mix(base,mix(surface,headland,boundary*min(1.,18./mpp)),resolved);
}

fn field_parcels(base: vec3f, metres: vec2f, mpp: f32, pattern: FieldPattern) -> vec3f {
    let grid = metres/pattern.spacing;
    let rows = grid.y + pattern.curvature*sin(grid.x*.38);
    let row = bitcast<u32>(i32(floor(rows)))*24571u;
    let parcels = vec2f(grid.x + pattern.stagger*landscape_random(row) + pattern.curvature*sin(rows*.63), rows);
    return parcel_ink(base,mpp,floor(parcels),fract(parcels),pattern.spacing);
}

struct FieldInterval {
    index: f32,
    phase: f32,
    width: f32,
};

fn field_interval(position: f32, variation: f32, seed: u32) -> FieldInterval {
    let nominal = floor(position);
    let stride = 116831u;
    let key = bitcast<u32>(i32(nominal))*stride + seed;
    // Each shared boundary stays inside its nominal interval, so neighbours meet in order.
    let split = nominal + landscape_random(key)*variation;
    if position < split {
        let start = nominal-1. + landscape_random(key-stride)*variation;
        let width = split-start;
        return FieldInterval(nominal-1.,(position-start)/width,width);
    }
    let end = nominal+1. + landscape_random(key+stride)*variation;
    let width = end-split;
    return FieldInterval(nominal,(position-split)/width,width);
}

fn variable_field_parcels(base: vec3f, metres: vec2f, mpp: f32, seed: u32) -> vec3f {
    let spacing = vec2f(345.,245.);
    let grid = metres/spacing;
    let rows = field_interval(grid.y+.085*sin(grid.x*.38),.46,seed);
    let row_seed = bitcast<u32>(i32(rows.index))*24571u + seed;
    let columns = field_interval(grid.x+.62*landscape_random(row_seed)+.085*sin(grid.y*.63),.54,row_seed);
    return parcel_ink(base,mpp,vec2f(columns.index,rows.index),vec2f(columns.phase,rows.phase),
                      spacing*vec2f(columns.width,rows.width));
}

fn nile_field_parcels(base: vec3f, fan: vec2f, mpp: f32) -> vec3f {
    let spacing = vec2f(112.,520.);
    let grid = fan/spacing;
    let strips = field_interval(grid.x+.025*sin(grid.y*.63),.24,7211u);
    // Each strip places its own cross boundaries along the fan.
    let strip_seed = bitcast<u32>(i32(strips.index))*24571u + 5563u;
    let lengths = field_interval(grid.y+.82*landscape_random(strip_seed),.67,strip_seed+1181u);
    return parcel_ink(base,mpp,vec2f(strips.index,lengths.index),vec2f(strips.phase,lengths.phase),
                      spacing*vec2f(strips.width,lengths.width));
}

fn field_region(ll: vec2f, centre: vec2f, half_extent: vec2f) -> f32 {
    let delta = abs(ll-centre)/half_extent;
    return 1.-smoothstep(.72,1.,max(delta.x,delta.y));
}

fn field_metres(ll: vec2f, origin: vec2f) -> vec2f {
    return (ll-origin)*111195.*vec2f(cos(radians(origin.y)),1.);
}

fn world_field_parcels(base: vec3f, world: vec3f, mpp: f32) -> vec3f {
    // Keep the world projection continuous where the planes meet.
    let rotated = vec3f(dot(world,vec3f(.80,.60,0.)),
        dot(world,vec3f(-.36,.48,.80)),dot(world,vec3f(.48,-.64,.60)));
    let metres = rotated*EARTH;
    let facing = abs(rotated);
    let strongest = max(facing.x,max(facing.y,facing.z));
    let weights = smoothstep(vec3f(strongest-.006),vec3f(strongest),facing);
    var ink = vec3f(0.);
    if weights.x > 0. { ink += variable_field_parcels(base,metres.yz,mpp,1013u)*weights.x; }
    if weights.y > 0. { ink += variable_field_parcels(base,metres.zx,mpp,4793u)*weights.y; }
    if weights.z > 0. { ink += variable_field_parcels(base,metres.xy,mpp,8779u)*weights.z; }
    return ink/dot(weights,vec3f(1.));
}

fn cultivated_fields(base: vec3f, ll: vec2f, world: vec3f, mpp: f32, cover: f32) -> vec3f {
    let visible = smoothstep(.12,.72,cover)*(1. - smoothstep(64.,180.,mpp));
    if visible <= .001 { return base; }

    var region = field_region(ll,vec2f(-93.,42.),vec2f(10.8,5.5));
    var ink = base;
    if region > 0. {
        // A nominal quarter-quarter section is about 400 metres on a side.
        ink = field_parcels(base,field_metres(ll,vec2f(-94.,42.)),mpp,FieldPattern(vec2f(402.,402.),.14,.0));
    } else {
        region = field_region(ll,vec2f(31.06,30.91),vec2f(1.27,.79));
        if region > 0. {
            // Rosetta and Damietta tangents from the existing Natural Earth
            // river source guide the fan. The field lines are visual estimates.
            let rosetta = 30.79347 - (ll.y-30.69444)*(.01620/.24463);
            let damietta = 31.24814 + (ll.y-30.85041)*(.11686/.20325);
            let fan = vec2f((ll.x-rosetta)*45500./max(.32,damietta-rosetta),(ll.y-30.87)*111195.);
            ink = nile_field_parcels(base,fan,mpp);
        } else {
            region = field_region(ll,vec2f(10.97,44.99),vec2f(3.3,1.08));
            if region > 0. {
                let pattern = FieldPattern(vec2f(440.,205.),.78,.044);
                let reno = field_region(ll,vec2f(11.30,44.71),vec2f(.54,.24));
                if reno < 1. {
                    ink = field_parcels(base,field_metres(ll,vec2f(11.,45.)),mpp,pattern);
                }
                if reno > 0. {
                    // HydroRIVERS segments 20510450 and 20509223 run through
                    // the lower Reno plain, about 39 degrees east of north.
                    let axis = vec2f(.629,.777);
                    let metres = field_metres(ll,vec2f(11.30,44.71));
                    let aligned = vec2f(dot(metres,axis),dot(metres,vec2f(-axis.y,axis.x)));
                    ink = mix(ink,field_parcels(base,aligned,mpp,pattern),reno);
                }
            }
        }
    }
    if region < 1. { ink = mix(world_field_parcels(base,world,mpp),ink,region); }
    return mix(base,ink,visible);
}

fn ground_motif(base: vec3f, ll: vec2f, world: vec3f, page: LandscapePage, level: u32, water: f32, mpp: f32) -> vec3f {
    let near = 1. - smoothstep(90., 430., mpp);
    // Match the physical lighting footprint at both levels. Keep the coarse
    // footprint wide enough to sample independent DEM texels in fallback.
    let step = f32(1u << (7u-level));
    let radius = max(.58,mix(1.70,.68,near)/step);
    let slope = landscape_slope(page,ll.y,radius,level);
    let height = landscape_elevation(page, vec2f(0.));
    let latitude_scale = max(.025, cos(radians(ll.y)));
    // Once the gutter limits the longitudinal reach, give the horizon
    // estimate more north-south support instead of dividing by a tiny span.
    let horizon_scale = max(.32,latitude_scale);
    let toward_sun = vec2f(-1.26, -1.03 * horizon_scale)/step;
    let shoulder = landscape_elevation(page, toward_sun);
    let ridge = landscape_elevation(page, toward_sun * 2.);
    let horizon = max(shoulder-height,(ridge-height)*.5) / (870.*horizon_scale);
    let gradient = length(slope);
    let normal = normalize(vec3f(-slope * 1.42, 1.));
    let sunlight = max(0., dot(normal, LANDSCAPE_SUN));
    let exposure = 1. - smoothstep(.44, 1.19, horizon) * .45;
    let steep = smoothstep(.23, .87, gradient);
    let crest = clamp((shoulder*2.-ridge-height)/235.,-.12,.13)*steep;
    let relief = clamp((sunlight*exposure-.60)*(.43+.22*near)+crest,-.44,.34);
    let land = landscape_material(page);
    let neutral = max(0.,1.-(land.forest+land.shrub+land.grass+land.damp
        +land.crop+land.urban+land.bare+land.snow));
    let facing = abs(world)*abs(world);
    let planes = facing*facing/dot(facing,facing);
    let motif = land_material_band(world,planes,mpp,25300.) - .5;
    let grove = landscape_grove(world);
    let canopy = smoothstep(.13,.54,grove);
    let alpine = smoothstep(1700.,3850.,height);
    let forest = mix(base,mix(vec3f(.32,.331,.224),vec3f(.243,.328,.218),canopy),.49*near)
        * (1. + motif.r*.16 + (canopy-.55)*(.09+.09*(1.-near)));
    let open = land.grass+land.shrub+land.crop;
    var sediment=vec2f(0.);
    if land.bare+neutral+open>.005 {
        sediment=sediment_structure(world,mpp);
    }
    let curvature = clamp((2.*height-shoulder-ridge)/160.,-.17,.19);
    let drainage = .21*(sunlight-.48)+.13*steep+curvature;
    let sward = .5+sediment.x*.55+sediment.y*.14;
    let dry = smoothstep(.17,.87,sward+drainage);
    let meadow = .21*(1.-smoothstep(650.,1570.,mpp))+.39*near;
    let grass = mix(base,mix(vec3f(.411,.481,.308),vec3f(.577,.539,.355),dry),meadow)
        * (1. + sediment.x*.075 + sediment.y*mix(.035,.105,dry));
    let shrub = mix(base,mix(vec3f(.397,.442,.287),vec3f(.531,.488,.328),dry),meadow*.9)
        * (1. + sediment.x*.065);
    let moss = mix(base,vec3f(.376,.435,.313),near*.38) * (1. + motif.g*.076);
    let sandy = land_palette_weight(land_chroma(base),vec3f(.775,.632,.433),.082);
    let deposits = clamp(sandy+sediment.x*.19+curvature,0.,1.);
    let earth = mix(base,mix(vec3f(.54,.468,.355),vec3f(.71,.573,.388),deposits),near*.29)
        * (1. + sediment.x*mix(.13,.17,sandy)
            + sediment.y*mix(.105,.065,sandy)*mix(.46,1.,deposits));
    let tilled = mix(base,mix(vec3f(.49,.41,.30),vec3f(.52,.52,.32),smoothstep(.21,.72,sward)),near*.42)
        * (1. + motif.a*.10 + motif.g*.055);
    let snow = mix(base,mix(vec3f(.72,.79,.82),vec3f(.82,.87,.88),.5+motif.a),near*.73);
    let stone = max(steep*.88,land.bare*alpine*smoothstep(.07,.39,gradient)*.86);
    let exposed = (1.-land.forest*.89)*(1.-land.snow)*(1.-land.urban) * stone;
    let scree = land.bare * smoothstep(.10,.36,gradient) * (1.-smoothstep(.46,.88,gradient));
    let mineral = mix(vec3f(.42,.377,.318),vec3f(.49,.446,.383),scree+(.5+motif.a)*.18);
    var color = base
        + (forest-base)*land.forest + (grass-base)*land.grass + (shrub-base)*land.shrub
        + (moss-base)*land.damp
        + (tilled-base)*land.crop + (earth-base)*land.bare + (snow-base)*land.snow
        + base*((sediment.x*.085+sediment.y*.05)*neutral+motif.a*land.urban*.19);
    let dry_crop = land.crop*(1.-steep)*(1.-smoothstep(.04,.26,max(land.damp,water)));
    color = cultivated_fields(color,ll,world,mpp,dry_crop);
    color = mix(color,mix(base,mineral,near*.87),exposed);
    if near > .001 {
        // A shared geographic coordinate keeps the grain phase stable across DEM levels.
        let grains = land_material_band(world,planes,mpp,2630.) - .5;
        let grit = mix(grains.g,grains.a,.5+sediment.x*.45);
        let texture = grains.r*(land.forest*.40+land.shrub*.19)
            + grains.g*(land.grass*.10+land.damp*.31+land.crop*.08)
            + grains.a*(land.crop*.10+scree*.25)
            + grit*(land.bare*.09+neutral*.13+land.grass*.04)
            + grains.b*(exposed*.91+scree*.37+land.urban*.20)
            + grains.a*(land.snow*.11+land.urban*.24)
            + motif.b*exposed*.17;
        color *= 1. + texture*near;
    }
    let icelight = clamp(relief,-.32,.075);
    return clamp(color * (1.+mix(relief,icelight,land.snow*near)),vec3f(0.),vec3f(1.));
}

fn landscape_relief(base: vec3f, ll: vec2f, world: vec3f, water: f32, mpp: f32) -> vec3f {
    if water > .65 || mpp >= LAND_MATERIAL_MPP || view.settings.y >= .5
        || view.map_style.z < 5. || all(base==vec3f(1.,0.,1.)) { return base; }
    let strength = ground_material_weight(water,mpp);
    if strength <= .001 { return base; }
    if view.map_style.z < 6. { return mix(base,natural_land_material(vec4f(base,water),world,mpp),strength); }
    let modern = 1. - landscape_survey_mask(ll,mpp);
    if modern <= .001 { return mix(base,natural_land_material(vec4f(base,water),world,mpp),strength); }
    let child = landscape_page(ll,7u,true);
    let fine = landscape_surface_weight(7u)*child.fade;
    var surface = vec3f(0.);
    var regional = 0.;
    if fine < .999 {
        let parent = landscape_page(ll,6u,true);
        regional = landscape_surface_weight(6u)*parent.fade;
        if regional > .001 { surface = ground_motif(base,ll,world,parent,6u,water,mpp)*regional; }
    }
    if fine > .001 { surface = surface*(1.-fine)+ground_motif(base,ll,world,child,7u,water,mpp)*fine; }
    surface *= modern;
    let uncovered = 1.-modern*(fine+regional*(1.-fine));
    if uncovered > .001 {
        surface += natural_land_material(vec4f(base,water),world,mpp)*uncovered;
    }
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
    indices: u32,
    count: atomic<u32>,
    first_index: u32,
    base_vertex: i32,
    first_instance: u32,
};

@group(1) @binding(5) var<storage, read> landscape_chunks: array<vec4u>;
@group(1) @binding(6) var<storage, read_write> landscape_instances: array<LandscapeInstance>;
@group(1) @binding(7) var<storage, read_write> landscape_draws: array<LandscapeDraw, 5>;
@group(1) @binding(8) var<storage, read_write> landscape_cache: array<LandscapeInstance>;

fn landscape_seed(cell: vec2u) -> u32 {
    return cell.x * 116831u + cell.y * 24571u;
}

fn landscape_conifers(latitude: f32, height: f32) -> f32 {
    return smoothstep(30.,66.,abs(latitude)+smoothstep(550.,2150.,height)*18.);
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
    return ((chunk.w & 0x7fffffffu) >> 6u)*256u + id.y*16u + id.x;
}

@compute @workgroup_size(8,8,1)
fn landscape_build(@builtin(global_invocation_id) id: vec3u) {
    let chunk = landscape_chunks[LANDSCAPE_VISIBLE+id.z];
    let cache_index = landscape_local_index(id,chunk);
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
    if page.fade <= 0. {
        if (chunk.w & 0x80000000u) == 0u {landscape_cache[cache_index].style = 0u;}
        return;
    }
    landscape_cache[cache_index].style = 0u;
    if landscape_coverage(page) >= .20 { return; }
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
    let bush = code == 2u;
    var density = 0.;
    var kind = 2u;
    if wooded || bush {
        let cover_amount = select(.36,textureSampleLevel(landscape_data,linear,page.texel/264.,page.slot,0.).b,wooded);
        let shelter = 1.-smoothstep(.38,1.16,grade);
        let openings = smoothstep(.14,.54,grove+mix(-.09,.025,shelter));
        density = cover_amount * openings;
        let climate = landscape_conifers(ll.y,height);
        let conifers = climate + (grove-.5)*.56*climate*(1.-climate);
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
    let packed_style = columns | (kind<<18u) | (u32(firstTrailingBit(step))<<21u)
        | (strength<<24u) | (select(0u,1u,bush)<<31u);
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
    @location(6) ground_offset: f32,
};

@vertex
fn landscape_vertex(
    @location(0) offset: vec3f, @location(1) normal: vec3f, @location(2) tone: f32, @location(3) edge: f32,
    @location(4) crown: f32, @location(5) item: vec4u,
) -> LandscapeVertex {
    let columns = item.z & 262143u;
    let kind = (item.z>>18u)&7u;
    let step = 1u << ((item.z>>21u)&7u);
    let density = f32((item.z>>24u)&127u)/127.;
    let shrub = (item.z>>31u) != 0u;
    let mpp = view.viewport.z*EARTH;
    let tree = crown > 0.;
    let understory = crown < 0.;
    let stand = kind == 0u || kind == 1u || kind == 3u;
    let stand_mix = smoothstep(9.,21.,mpp);
    let lower_cover = smoothstep(.36,.82,density)*.36;
    let structure = select(stand_mix,mix(lower_cover,1.,stand_mix),understory);
    let representation = select(1.,select(structure,1.-stand_mix,tree),stand);
    if representation <= .012 {
        return LandscapeVertex(vec4f(2.,2.,0.,1.),vec3f(0.),vec4f(0.),0.,kind,vec2f(0.),0u,0.);
    }
    let ll = landscape_coordinates(item.xy,columns);
    let height = f32(item.w&65535u)-32768.;
    let grade = (vec2f(f32((item.w>>16u)&255u),f32(item.w>>24u))-128.)/127.;
    let seed = landscape_seed(item.xy);
    let variation = seed+u32(max(crown,0.))*8461u;
    let hue = landscape_random(variation+8733u);
    let shape = landscape_random(variation+6371u);
    var bearing = landscape_random(seed+3191u)*(2.*PI);
    var radius = mix(87.,158.,shape)*mix(.84,1.16,density);
    var form = vec3f(radius,radius*mix(.77,1.11,hue),mix(11.,24.,shape));
    var tree_center = vec2f(0.);
    var ground_grade = grade*.93;
    let climate = landscape_conifers(ll.y,height);
    let tropical = (1.-smoothstep(14.,29.,abs(ll.y)))*(1.-smoothstep(600.,1700.,height));
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
        form *= vec3f(spread*mix(1.07,.89,climate),spread*.92,mix(1.,1.13,tropical));
        if shrub { form *= vec3f(.62,.72,.30); }
    }
    if tree {
        let i = u32(crown)-1u;
        let tile = vec2f(f32(i%7u),f32(i/7u))-3.;
        let jitter = vec2f(landscape_random(variation+399u),landscape_random(variation+791u))-.5;
        let spacing = mix(21.,17.,smoothstep(.36,.85,density));
        tree_center = (tile+jitter)*spacing;
        let r = mix(4.6,9.6,shape);
        form = vec3f(r,r*mix(.79,1.08,hue),mix(8.,21.,shape)*(1.+tropical*.17));
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
    let ground_offset=altitude*pitch/mpp;
    pixels.y -= ground_offset;
    let z = height+ground+altitude;
    let depth = clamp(.56-(z+(pixels.y-view.viewport.y*.5)*mpp*pitch)/440000.,.002,.998);
    let clip = vec4f(pixels/view.viewport.xy*vec2f(2.,-2.)+vec2f(-1.,1.),depth,1.);
    let bases = array<vec3f,4>(vec3f(.363,.474,.271),vec3f(.324,.421,.285),vec3f(.50,.446,.374),vec3f(.395,.464,.273));
    let base = select(bases[min(kind,3u)],mix(bases[0],bases[1],climate),kind==4u)
        + vec3f(-.022,.007,-.012)*tropical*select(1.,0.,kind==2u);
    let foliage = select(base,bases[3],shrub);
    let pigment = vec3f(.128,.132,.079)*(hue-.5);
    let flat = rotate*(normal.xy/form.xy);
    let vertical = normal.z/form.z;
    let facing = normalize(vec3f(flat-ground_grade*vertical,vertical));
    let sunlight = max(0.,dot(facing,LANDSCAPE_SUN));
    let light = select(.85+.30*sunlight,.88+.26*sunlight,kind==2u);
    let canopy_light = select(vec3f(0.),vec3f(.040,.052,.023),tree);
    let color = clamp((foliage+pigment+canopy_light)*light*mix(1.,tone,.70),vec3f(0.),vec3f(1.));
    return LandscapeVertex(clip,vec3f(site,z),vec4f(color,visibility),edge,kind,lod,select(0u,1u,tree),ground_offset);
}

fn landscape_object_mask(page: LandscapePage, input: LandscapeVertex, sample: u32) -> f32 {
    var land = 1.;
    if water_weight(sample)<.999 {
        land = 1.-smoothstep(.10,.44,water_coverage(sample,landscape_coverage(page)));
    }
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
    let rim = fwidth(input.edge)*select(.59,.68,input.kind==2u);
    // A subpixel crown spans several short triangles. Keep the rim filter
    // inside those triangles; the vertex shader already filters projected area.
    let edge = smoothstep(0.,max(select(rim,min(rim,.55),input.tree!=0u),.001),input.edge);
    if input.color.a*max(input.lod.x,input.lod.y) <= .012 { discard; }
    let ground_pixel=input.clip.xy+vec2f(0.,input.ground_offset);
    var sample=screen_water(ground_pixel);
    if any(ground_pixel<vec2f(0.)) || any(ground_pixel>=view.viewport.xy) {
        sample=water_area(input.site.xy);
    }
    if (sample&3u)>1u && water_weight(sample)>=.999 { discard; }
    let mpp = view.viewport.z*EARTH;
    var fine = 0.;
    var strength = 0.;
    let zoom_fine = landscape_surface_weight(7u);
    if zoom_fine > .001 {
        let page = landscape_page(input.site.xy,7u,true);
        fine = zoom_fine*page.fade;
        if fine*input.lod.x > .001 {
            strength = fine*input.lod.x*landscape_object_mask(page,input,sample);
        }
    }
    if input.kind == 4u && (1.-fine)*input.lod.y > .001 {
        let zoom_regional = landscape_surface_weight(6u);
        if zoom_regional > .001 {
            let page = landscape_page(input.site.xy,6u,true);
            let regional = zoom_regional*page.fade;
            if regional > .001 {
                strength += (1.-fine)*regional*input.lod.y*landscape_object_mask(page,input,sample);
            }
        }
    }
    if strength <= .001 { discard; }
    let modern = 1.-landscape_survey_mask(input.site.xy,mpp);
    let opacity = input.color.a*edge*modern*strength;
    if opacity <= .012 { discard; }
    return vec4f(input.color.rgb,opacity);
}
