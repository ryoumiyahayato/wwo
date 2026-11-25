// Landscape data follows the color QPK grid, including its four-sample border.
struct LandscapePage {
    texel: vec2f,
    slot: i32,
    regional_slot: i32,
    fade: f32,
};

fn landscape_page(ll: vec2f, level: u32, at_surface: bool) -> LandscapePage {
    let uv = natural_uv(ll);
    let rows = 1i << level;
    let position = uv * vec2f(f32(rows*2), f32(rows));
    let cell = vec2i(position);
    let index = textureLoad(terrain_index, cell+vec2i(0,rows-1), 0).r;
    let q = fract(position);
    var fade = f32(index >> 24u) / 255.;
    if at_surface && view.chart_origin.w <= .5 {
        // Instance preparation can see a decoded page early. At the surface,
        // both the color and relief must be visible at this point.
        let color_fade=f32((index>>16u)&255u)/255.;
        fade=page_coverage(cell,q,rows,24u,min(fade,color_fade));
    }
    return LandscapePage(q * 256. + 4., i32(index & 511u) - 1, i32((index >> 9u) & 127u) - 1, fade);
}

fn landscape_elevation(page: LandscapePage, offset: vec2f) -> f32 {
    let rg = textureSampleLevel(landscape_data, linear, (page.texel + offset) / 264., page.slot, 0.).rg;
    return dot(rg, vec2f(255., 65280.)) - 32768.;
}

fn landscape_coverage(page: LandscapePage) -> f32 {
    return textureSampleLevel(terrain_detail, linear, page.texel / 264., page.slot, 0.).a;
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

struct LandCover {
    forest: f32,
    shrub: f32,
    grass: f32,
    damp: f32,
    crop: f32,
    urban: f32,
    bare: f32,
    snow: f32,
    regional: f32,
};

fn mix_cover(a: LandCover, b: LandCover, t: f32) -> LandCover {
    return LandCover(mix(a.forest,b.forest,t),mix(a.shrub,b.shrub,t),mix(a.grass,b.grass,t),
        mix(a.damp,b.damp,t),mix(a.crop,b.crop,t),mix(a.urban,b.urban,t),mix(a.bare,b.bare,t),
        mix(a.snow,b.snow,t),mix(a.regional,b.regional,t));
}

fn regional_scale(mpp: f32) -> f32 {
    // The 50 km ruler starts at 625 m/px (50,000 m / 80 pixels).
    return 1.-smoothstep(435.,625.,mpp);
}

fn class_fraction(classes: vec4u, weights: vec4f, code: u32) -> f32 {
    return dot(weights, select(vec4f(0.), vec4f(1.), classes == vec4u(code)));
}

fn cover_axis(t: f32) -> vec4f {
    let t2 = t*t;
    let t3 = t2*t;
    let u = 1.-t;
    let spline = vec4f(u*u*u,4.-6.*t2+3.*t3,1.+3.*t+3.*t2-3.*t3,t3)/6.;
    // Use a narrow symmetric transition at the reconstructed edge; the
    // wider spline still carries the area of small patches at the fringe.
    let edge=smoothstep(.28,.72,t);
    return mix(vec4f(0.,1.-edge,edge,0.),spline,.46);
}

fn legacy_landscape_material(page: LandscapePage) -> LandCover {
    // Shear along each axis in turn. The artwork rounds source corners on a
    // sub-texel scale while preserving area. The phase matches across gutters.
    let cycle = (2.*PI)/256.;
    let x = page.texel.x+.28*sin(cycle*67.*page.texel.y)+.13*sin(cycle*29.*page.texel.y);
    let y = page.texel.y+.28*sin(cycle*53.*x)+.13*sin(cycle*23.*x);
    let sample = vec2f(x,y);
    let f = fract(sample-.5);
    let wx = cover_axis(f.x);
    let wy = cover_axis(f.y);

    let a = vec4u(round(textureGather(3,landscape_data,linear,(sample+vec2f(-1.,-1.))/264.,page.slot)*15.));
    let b = vec4u(round(textureGather(3,landscape_data,linear,(sample+vec2f(1.,-1.))/264.,page.slot)*15.));
    let c = vec4u(round(textureGather(3,landscape_data,linear,(sample+vec2f(-1.,1.))/264.,page.slot)*15.));
    let d = vec4u(round(textureGather(3,landscape_data,linear,(sample+vec2f(1.,1.))/264.,page.slot)*15.));
    let wa = wx.xyyx*wy.yyxx;
    let wb = wx.zwwz*wy.yyxx;
    let wc = wx.xyyx*wy.wwzz;
    let wd = wx.zwwz*wy.wwzz;

    var fraction = array<f32,12>();
    for (var code=1u; code<12u; code+=1u) {
        fraction[code] = class_fraction(a,wa,code)+class_fraction(b,wb,code)
            +class_fraction(c,wc,code)+class_fraction(d,wd,code);
    }
    return LandCover(fraction[1]+fraction[10],fraction[2],fraction[3],
        fraction[9]+fraction[11],fraction[4],fraction[5],fraction[6],fraction[7],0.);
}

fn forest_child(texel: vec2i, slot: i32) -> f32 {
    let bank = textureLoad(regional_cover,texel/2,slot,0);
    return bank[u32((texel.y & 1)*2 + (texel.x & 1))];
}

fn reconstructed_forest(page: LandscapePage) -> f32 {
    let texel = page.texel*2.-.5;
    let cell = vec2i(texel);
    let t = fract(texel);
    let a = mix(forest_child(cell,page.regional_slot),forest_child(cell+vec2i(1,0),page.regional_slot),t.x);
    let b = mix(forest_child(cell+vec2i(0,1),page.regional_slot),
                forest_child(cell+vec2i(1,1),page.regional_slot),t.x);
    return mix(a,b,t.y);
}

fn landscape_material(page: LandscapePage, regional_weight: f32, forest_detail: f32) -> LandCover {
    if page.regional_slot < 0 || regional_weight <= .001 {
        return legacy_landscape_material(page);
    }
    let uv = page.texel / vec2f(792.,264.);
    let b = textureSampleLevel(regional_cover,linear,uv+vec2f(2./3.,0.),page.regional_slot,0.);
    if b.a*regional_weight <= .001 { return legacy_landscape_material(page); }
    let a = textureSampleLevel(regional_cover,linear,uv+vec2f(1./3.,0.),page.regional_slot,0.);
    let broad = dot(textureSampleLevel(regional_cover,linear,uv,page.regional_slot,0.),vec4f(.25));
    let open = dot(a.rgb+b.rgb,vec3f(1.));
    let observed = smoothstep(.01,.50,broad+open+a.a);
    let weight = b.a * regional_weight * observed;
    if weight <= .001 { return legacy_landscape_material(page); }
    var forest = broad;
    var rest = 1.;
    if forest_detail > .001 {
        // Keep water, town and unknown acreage fixed as the forest edge resolves.
        forest = min(broad+open,mix(broad,reconstructed_forest(page),forest_detail));
        rest = (open+broad-forest)/max(.0001,open);
        if open <= .0001 { forest = broad; }
    }
    let land = LandCover(forest,a.r*rest,a.g*rest,b.b*rest,a.b*rest,a.a,b.r*rest,b.g*rest,1.);
    if weight >= .999 { return land; }
    return mix_cover(legacy_landscape_material(page),land,weight);
}

const FOREST_GROUND: vec3f = vec3f(.318,.391,.277);
const SHRUB_GROUND: vec3f = vec3f(.445,.468,.332);
const GRASS_GROUND: vec3f = vec3f(.466,.512,.353);
const DAMP_GROUND: vec3f = vec3f(.365,.440,.338);
const CROP_GROUND: vec3f = vec3f(.537,.535,.369);
const BUILT_GROUND: vec3f = vec3f(.508,.502,.455);
const SOIL_GROUND: vec3f = vec3f(.574,.500,.412);
const SAND_GROUND: vec3f = vec3f(.711,.602,.448);
const ROCK_GROUND: vec3f = vec3f(.497,.496,.466);
const SNOW_GROUND: vec3f = vec3f(.839,.881,.899);

fn landscape_wood(cover: LandCover) -> vec2f {
    return vec2f(cover.forest*.94,cover.shrub*.38);
}

struct LandscapeLayer {
    page: LandscapePage,
    weight: f32,
};

fn landscape_layers(ll: vec2f) -> array<LandscapeLayer,2> {
    var fine = LandscapeLayer(LandscapePage(vec2f(0.),-1,-1,0.),0.);
    var regional = fine;
    let fine_zoom = natural_lod_weight(7u);
    let regional_zoom = natural_lod_weight(6u);
    if fine_zoom > .001 {
        fine.page = landscape_page(ll,7u,true);
        fine.weight = fine.page.fade*fine_zoom;
    }
    if (1.-fine.weight)*regional_zoom > .001 {
        regional.page = landscape_page(ll,6u,true);
        regional.weight = regional.page.fade*regional_zoom*(1.-fine.weight);
    }
    return array<LandscapeLayer,2>(fine,regional);
}

fn blended_landcover(layers: array<LandscapeLayer,2>, weight: f32, mpp: f32) -> LandCover {
    let regional = regional_scale(mpp);
    let forest_detail = 1.-smoothstep(95.,230.,mpp);
    if layers[0].weight <= .001 { return landscape_material(layers[1].page,regional,forest_detail); }
    let a = landscape_material(layers[0].page,regional,forest_detail);
    if layers[1].weight <= .001 { return a; }
    return mix_cover(a,landscape_material(layers[1].page,regional,forest_detail),layers[1].weight/weight);
}

fn geographic_ground_tint(ll: vec2f, fallback: vec3f) -> vec3f {
    if textureNumLayers(landscape_data) <= 1u { return fallback; }
    let layers = landscape_layers(ll);
    let weight = layers[0].weight+layers[1].weight;
    if weight <= .001 { return fallback; }
    let land = blended_landcover(layers,weight,view.viewport.z*EARTH);
    let tint = (FOREST_GROUND-fallback)*land.forest+(SHRUB_GROUND-fallback)*land.shrub
        +(GRASS_GROUND-fallback)*land.grass+(DAMP_GROUND-fallback)*land.damp
        +(CROP_GROUND-fallback)*land.crop+(BUILT_GROUND-fallback)*land.urban*.23
        +(SOIL_GROUND-fallback)*land.bare+(SNOW_GROUND-fallback)*land.snow;
    return fallback+tint*weight;
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
    // Bend the axes over several adjoining fields. Neighbours still share edges.
    let curved = metres+vec2f(147.*sin(metres.y/695.),182.*sin(metres.x/844.));
    let grid = curved/spacing;
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

fn cultivated_fields(base: vec3f, ll: vec2f, world: vec3f, mpp: f32) -> vec3f {
    let visible = 1.-smoothstep(64.,180.,mpp);
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

fn material_grain(world: vec3f, mpp: f32, layer: i32, span: f32, fade: f32) -> f32 {
    if mpp >= fade { return 0.; }
    let average = textureLoad(surface_art,vec2i(0),layer,i32(textureNumLevels(surface_art))-1).rgb;
    let paint = painted_material(world,mpp,layer,span);
    let light = vec3f(.24,.65,.11);
    return dot(paint-average,light)/max(.18,dot(average,light))*(1.-smoothstep(fade*.45,fade,mpp));
}

fn rock_share(land: LandCover, grade: f32, height: f32) -> vec2f {
    let bare = land.bare*max(smoothstep(.13,.48,grade),smoothstep(1550.,3550.,height)*.70);
    return vec2f(bare,smoothstep(.43,.95,grade)*.47);
}

fn ground_motif(base: vec3f, ll: vec2f, world: vec3f, land: LandCover,
                slope: vec2f, height: f32, mpp: f32) -> vec3f {
    let share = rock_share(land,length(slope),height);
    let rock = share.x+(land.grass+land.shrub)*share.y;
    let sand = land_palette_weight(land_chroma(base),vec3f(.775,.632,.433),.074);
    var forest = FOREST_GROUND;
    if land.forest > .001 {
        // The same continuous canopy remains below the individual crowns.
        let crowns = material_grain(world,mpp,WOODLAND,mix(1320.,240.,land.regional),mix(84.,35.,land.regional));
        let leaves = material_grain(world,mpp,WOODLAND,315.,16.);
        forest *= 1.+(crowns*mix(1.32,.60,land.regional)+leaves*.48)*(landscape_wood(land).x/max(.001,land.forest));
    }
    let exposure = clamp(slope.y*.19+height*.00007,-.08,.15);
    var grass = GRASS_GROUND+vec3f(-.09,-.012,.09)*exposure;
    if land.grass > .001 { grass *= 1.+material_grain(world,mpp,GRASS,17.,2.2)*.54; }
    var crop = CROP_GROUND;
    if land.crop > .001 {
        crop = cultivated_fields(crop,ll,world,mpp);
        crop *= 1.+material_grain(world,mpp,FIELD,38.,5.5)*.48;
    }
    var earth = mix(SOIL_GROUND,SAND_GROUND,sand);
    if land.bare-share.x > .001 {
        let soil = material_grain(world,mpp,SOIL,32.,5.);
        let sand_grain = material_grain(world,mpp,SAND,32.,5.);
        earth *= 1.+mix(soil,sand_grain,sand)*.66;
    }
    var stone = ROCK_GROUND;
    if rock > .001 { stone *= 1.+material_grain(world,mpp,ROCK,88.,12.)*.66; }
    var snow = SNOW_GROUND;
    if land.snow > .001 { snow *= 1.+material_grain(world,mpp,SNOW,65.,9.)*.49; }

    // Transfer only the exposed share of open ground to rock.
    let tint = (forest-base)*land.forest + (grass-base)*land.grass*(1.-share.y)
        + (SHRUB_GROUND-base)*land.shrub*(1.-share.y) + (DAMP_GROUND-base)*land.damp
        + (crop-base)*land.crop + (BUILT_GROUND-base)*land.urban*.23
        + (earth-base)*(land.bare-share.x) + (stone-base)*rock + (snow-base)*land.snow;
    let normal = normalize(vec3f(-slope*1.32,1.));
    let light = clamp((dot(normal,LANDSCAPE_SUN)-LANDSCAPE_SUN.z)*.57,-.34,.22);
    let paint = mix((1.-smoothstep(90.,430.,mpp))*.81,.87,land.regional);
    let relief = mix(1.,.65,land.regional);
    return clamp((base+tint*paint)*(1.+light*relief*(1.-land.snow*.5)),vec3f(0.),vec3f(1.));
}

fn landscape_relief(base: vec3f, ll: vec2f, world: vec3f, water: f32, mpp: f32) -> vec3f {
    if water > .65 || mpp >= LAND_MATERIAL_MPP || all(base==vec3f(1.,0.,1.)) { return base; }
    let strength = ground_material_weight(water,mpp);
    if strength <= .001 { return base; }
    let layers = landscape_layers(ll);
    let weight = layers[0].weight+layers[1].weight;
    let modern = 1.-landscape_survey_mask(ll,mpp);
    let overview = smoothstep(110.,320.,mpp)*natural_lod_weight(5u);
    var fallback = base;
    if overview > .001 && weight*modern < .999 {
        fallback = mix(base,natural_land_material(vec4f(base,water),world,mpp),strength*overview);
    }
    if weight*modern <= .001 { return fallback; }
    let land = blended_landcover(layers,weight,mpp);
    var slope = vec2f(0.);
    var height = 0.;
    for (var i=0u; i<2u; i+=1u) {
        let layer = layers[i];
        if layer.weight <= .001 { continue; }
        let radius = max(.60,mix(.74,1.68,smoothstep(55.,290.,mpp))/f32(1u<<i));
        slope += landscape_slope(layer.page,ll.y,radius,7u-i)*layer.weight;
        height += landscape_elevation(layer.page,vec2f(0.))*layer.weight;
    }
    // Blend survey coverage and relief before evaluating the material.
    let ground = ground_motif(base,ll,world,land,slope/weight,height/weight,mpp);
    return mix(fallback,ground,strength*modern*weight);
}

const LANDSCAPE_INSTANCES: u32 = 65536u;
const LANDSCAPE_VISIBLE: u32 = 1728u;
const LANDSCAPE_INSTANCE_FADE_SECONDS: f32 = 0.18;

struct LandscapeInstance {
    cell_x: u32,
    cell_y: u32,
    style: u32,    // longitude count, mesh kind, cover weight
    terrain: u32,  // signed metres and two quantized surface gradients
    appeared: f32, // elapsed real seconds when the site was first built
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
@group(1) @binding(7) var<storage, read_write> landscape_draws: array<LandscapeDraw, 4>;
@group(1) @binding(8) var<storage, read_write> landscape_cache: array<LandscapeInstance>;

fn landscape_seed(cell: vec2u) -> u32 {
    return cell.x * 116831u + cell.y * 24571u;
}

fn landscape_conifers(latitude: f32, height: f32) -> f32 {
    return smoothstep(30.,66.,abs(latitude)+smoothstep(550.,2150.,height)*18.);
}

fn landscape_coordinates(cell: vec2u, columns: u32) -> vec2f {
    let seed = landscape_seed(cell);
    let jitter = .32 + .36 * vec2f(landscape_random(seed),landscape_random(seed+5221u));
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

fn landscape_model_weight(footprint: f32) -> f32 {
    return 1.-smoothstep(12.,28.,footprint);
}

fn landscape_local_index(id: vec3u, chunk: vec4u) -> u32 {
    return ((chunk.w & 0x7fffffffu) >> 6u)*256u + id.y*16u + id.x;
}

@compute @workgroup_size(8,8,1)
fn landscape_build(@builtin(global_invocation_id) id: vec3u) {
    let chunk = landscape_chunks[LANDSCAPE_VISIBLE+id.z];
    let cache_index = landscape_local_index(id,chunk);
    let cell = chunk.xy+id.xy;
    let columns = chunk.z;
    let ll = landscape_coordinates(cell,columns);
    let page = landscape_page(ll,7u,false);
    let keep_sites = (chunk.w & 0x80000000u) != 0u;
    if page.fade <= 0. {
        if !keep_sites {landscape_cache[cache_index].style = 0u;}
        return;
    }
    let previous = landscape_cache[cache_index];
    landscape_cache[cache_index].style = 0u;
    if landscape_coverage(page) >= .20 { return; }
    let cover = landscape_material(page,1.,1.);
    let wood = landscape_wood(cover);
    let height = landscape_elevation(page,vec2f(0.));
    let slope = landscape_slope(page,ll.y,.83,7u);
    let share = rock_share(cover,length(slope),height);
    let rock = (share.x+(cover.grass+cover.shrub)*share.y)*.78;
    let seed = landscape_seed(cell);
    let choice = landscape_random(seed+1951u);
    let density = wood.x+wood.y+rock;
    if choice >= density { return; }

    let conifers = landscape_conifers(ll.y,height);
    let tree = select(0u,1u,landscape_random(seed+691u)<conifers);
    let kind = select(select(2u,3u,choice<wood.x+wood.y),tree,choice<wood.x);

    let packed_slope = vec2u(round(clamp(slope,-vec2f(1.),vec2f(1.))*127.+128.));
    let packed_height = u32(clamp(round(height)+32768.,0.,65535.));
    let packed_terrain = packed_height | (packed_slope.x<<16u) | (packed_slope.y<<24u);
    let strength = u32(round(clamp(density,0.,1.)*127.));
    let packed_style = columns | (kind<<18u) | (strength<<24u);
    // Another page can rebuild this chunk without changing its existing sites.
    let appeared = select(view.chart_east.w,previous.appeared,keep_sites && previous.style != 0u);
    landscape_cache[cache_index] = LandscapeInstance(cell.x,cell.y,packed_style,packed_terrain,appeared);
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

@compute @workgroup_size(4)
fn landscape_limit_draws(@builtin(local_invocation_index) kind: u32) {
    atomicMin(&landscape_draws[kind].count,LANDSCAPE_INSTANCES);
}

struct LandscapeVertex {
    @builtin(position) clip: vec4f,
    @location(0) site: vec3f,
    @location(1) color: vec4f,
    @location(2) edge: f32,
    @location(3) @interpolate(flat) kind: u32,
    @location(4) @interpolate(flat) lod: f32,
    @location(5) @interpolate(flat) tree: u32,
    @location(6) ground_offset: f32,
};

@vertex
fn landscape_vertex(
    @location(0) offset: vec3f, @location(1) normal: vec3f, @location(2) tone: f32, @location(3) edge: f32,
    @location(4) crown: f32, @location(5) item: vec4u, @location(6) appeared: f32,
) -> LandscapeVertex {
    let columns = item.z & 262143u;
    let kind = (item.z>>18u)&7u;
    let density = f32((item.z>>24u)&127u)/127.;
    let mpp = view.viewport.z*EARTH;
    let tree = crown > 0.;
    let understory = crown < 0.;
    let stand = kind == 0u || kind == 1u || kind == 3u;
    let stand_mix = smoothstep(7.,18.,mpp);
    let low_foliage = smoothstep(.36,.82,density)*.22;
    let structure = select(stand_mix*.26,mix(low_foliage,.31,stand_mix),understory);
    let arrival = smoothstep(0.,LANDSCAPE_INSTANCE_FADE_SECONDS,view.chart_east.w-appeared);
    let representation = select(1.,select(structure,1.-stand_mix,tree),stand)*arrival;
    if representation <= .012 {
        return LandscapeVertex(vec4f(2.,2.,0.,1.),vec3f(0.),vec4f(0.),0.,kind,0.,0u,0.);
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
    }
    if tree {
        let i = u32(crown)-1u;
        let tile = vec2f(f32(i%7u),f32(i/7u))-3.;
        let jitter = vec2f(landscape_random(variation+399u),landscape_random(variation+791u))-.5;
        let spacing = mix(23.,27.,smoothstep(.36,.85,density));
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
    let lod = landscape_model_weight(footprint);
    let visibility = representation*select(smoothstep(2.,4.5,apparent),1./(filter_width*filter_width),tree);
    let ground_offset=altitude*pitch/mpp;
    pixels.y -= ground_offset;
    let z = height+ground+altitude;
    let depth = clamp(.56-(z+(pixels.y-view.viewport.y*.5)*mpp*pitch)/440000.,.002,.998);
    let clip = vec4f(pixels/view.viewport.xy*vec2f(2.,-2.)+vec2f(-1.,1.),depth,1.);
    let bases = array<vec3f,4>(FOREST_GROUND+vec3f(.052,.056,.031),
        FOREST_GROUND+vec3f(.021,.036,.020),ROCK_GROUND,SHRUB_GROUND-vec3f(.035,.032,.025));
    let foliage = bases[kind]+vec3f(-.017,.008,-.010)*tropical*select(1.,0.,kind==2u);
    let pigment = vec3f(.086,.092,.061)*(hue-.5);
    let flat = rotate*(normal.xy/form.xy);
    let vertical = normal.z/form.z;
    let facing = normalize(vec3f(flat-ground_grade*vertical,vertical));
    let sunlight = max(0.,dot(facing,LANDSCAPE_SUN));
    let light = select(.85+.30*sunlight,.88+.26*sunlight,kind==2u);
    let canopy_light = select(vec3f(0.),vec3f(.024,.030,.016),tree);
    let color = clamp((foliage+pigment+canopy_light)*light*mix(1.,tone,.70),vec3f(0.),vec3f(1.));
    return LandscapeVertex(clip,vec3f(site,z),vec4f(color,visibility),edge,kind,lod,select(0u,1u,tree),ground_offset);
}

fn landscape_object_mask(page: LandscapePage, input: LandscapeVertex, sample: u32) -> f32 {
    var land = 1.;
    if water_weight(sample)<.999 {
        land = 1.-smoothstep(.10,.44,water_coverage(sample,landscape_coverage(page)));
    }
    let cover = landscape_material(page,1.,1.);
    let clearance = input.site.z-landscape_elevation(page,vec2f(0.));
    let vegetation = select(cover.forest,cover.shrub,input.kind==3u);
    let exposed = cover.bare+cover.shrub+cover.grass;
    return land*smoothstep(-4.,0.,clearance)*select(vegetation,exposed,input.kind==2u);
}

@fragment
fn landscape_fragment(input: LandscapeVertex) -> @location(0) vec4f {
    let rim = fwidth(input.edge)*select(.59,.68,input.kind==2u);
    // A subpixel crown spans several short triangles. Keep the rim filter
    // inside those triangles; the vertex shader already filters projected area.
    let edge = smoothstep(0.,max(select(rim,min(rim,.55),input.tree!=0u),.001),input.edge);
    if input.color.a*input.lod <= .012 { discard; }
    let ground_pixel=input.clip.xy+vec2f(0.,input.ground_offset);
    var sample=screen_water(ground_pixel);
    if any(ground_pixel<vec2f(0.)) || any(ground_pixel>=view.viewport.xy) {
        sample=water_area(input.site.xy);
    }
    if (sample&3u)>1u && water_weight(sample)>=.999 { discard; }
    let mpp = view.viewport.z*EARTH;
    let page = landscape_page(input.site.xy,7u,true);
    let fine = natural_lod_weight(7u)*page.fade;
    if fine <= .001 { discard; }
    let strength = fine*input.lod*landscape_object_mask(page,input,sample);
    if strength <= .001 { discard; }
    let modern = 1.-landscape_survey_mask(input.site.xy,mpp);
    let opacity = input.color.a*edge*modern*strength;
    if opacity <= .012 { discard; }
    return vec4f(input.color.rgb,opacity);
}
