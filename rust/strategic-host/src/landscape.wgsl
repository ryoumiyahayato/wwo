// Landscape data follows the color QPK grid, including its four-sample border.
struct LandscapePage {
    texel: vec2f,
    slot: i32,
    regional_slot: i32,
    fade: f32,
    regional_near_only: bool,
};

fn landscape_page(ll: vec2f, level: u32, at_surface: bool) -> LandscapePage {
    let uv = natural_uv(ll);
    let rows = 1i << level;
    let position = uv * vec2f(f32(rows*2), f32(rows));
    let cell = vec2i(position);
    let entry = textureLoad(terrain_index, cell+vec2i(0,rows-1), 0);
    let index = entry.r;
    let q = fract(position);
    var fade = f32(index >> 24u) / 255.;
    if at_surface && view.chart_origin.w <= .5 {
        // Instance preparation can see a decoded page early. At the surface,
        // both the color and relief must be visible at this point.
        let color_fade=f32((index>>16u)&255u)/255.;
        fade=page_coverage(cell,q,rows,24u,min(fade,color_fade));
    }
    return LandscapePage(q * 256. + 4., i32(index & 511u) - 1, i32((index >> 9u) & 127u) - 1, fade, entry.g != 0u);
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

fn cover_spline(t: f32) -> vec4f {
    let t2 = t*t;
    let t3 = t2*t;
    let u = 1.-t;
    return vec4f(u*u*u,4.-6.*t2+3.*t3,1.+3.*t+3.*t2-3.*t3,t3)/6.;
}

fn cover_axis(t: f32) -> vec4f {
    // Use a narrow symmetric transition at the reconstructed edge; the
    // wider spline still carries the area of small patches at the fringe.
    let edge=smoothstep(.28,.72,t);
    return mix(vec4f(0.,1.-edge,edge,0.),cover_spline(t),.46);
}

struct CoverStencil {
    classes: array<vec4u,4>,
    weights: array<vec4f,4>,
};

fn cover_stencil(slot: i32, sample: vec2f, wx: vec4f, wy: vec4f) -> CoverStencil {
    let a = vec4u(round(textureGather(3,landscape_data,linear,(sample+vec2f(-1.,-1.))/264.,slot)*15.));
    let b = vec4u(round(textureGather(3,landscape_data,linear,(sample+vec2f(1.,-1.))/264.,slot)*15.));
    let c = vec4u(round(textureGather(3,landscape_data,linear,(sample+vec2f(-1.,1.))/264.,slot)*15.));
    let d = vec4u(round(textureGather(3,landscape_data,linear,(sample+vec2f(1.,1.))/264.,slot)*15.));
    return CoverStencil(array(a,b,c,d),array(wx.xyyx*wy.yyxx,wx.zwwz*wy.yyxx,wx.xyyx*wy.wwzz,wx.zwwz*wy.wwzz));
}

fn stencil_fraction(stencil: CoverStencil, code: u32) -> f32 {
    return class_fraction(stencil.classes[0],stencil.weights[0],code)
        +class_fraction(stencil.classes[1],stencil.weights[1],code)
        +class_fraction(stencil.classes[2],stencil.weights[2],code)
        +class_fraction(stencil.classes[3],stencil.weights[3],code);
}

fn legacy_landscape_material(page: LandscapePage, smooth_snow: bool) -> LandCover {
    // Shear along each axis in turn. The artwork rounds source corners on a
    // sub-texel scale while preserving area. The phase matches across gutters.
    let cycle = (2.*PI)/256.;
    let x = page.texel.x+.28*sin(cycle*67.*page.texel.y)+.13*sin(cycle*29.*page.texel.y);
    let y = page.texel.y+.28*sin(cycle*53.*x)+.13*sin(cycle*23.*x);
    let sample = vec2f(x,y);
    let f = fract(sample-.5);
    let stencil = cover_stencil(page.slot,sample,cover_axis(f.x),cover_axis(f.y));

    var fraction = array<f32,12>();
    for (var code=1u; code<12u; code+=1u) {
        fraction[code] = stencil_fraction(stencil,code);
    }
    let snow = fraction[7];
    if smooth_snow && snow > .01 && snow < .99 {
        let total = 1.-stencil_fraction(stencil,0u);
        let exposed = total-snow;
        let edge = smoothstep(.01,.16,min(snow,exposed));
        if edge > .001 {
            // Interpolate the snow mask on the source grid. The shear used by
            // the other materials makes conspicuous teeth at snow edges.
            let phase = fract(page.texel-.5);
            let unwarped = cover_stencil(page.slot,page.texel,cover_spline(phase.x),cover_spline(phase.y));
            let snow_mix = mix(snow,min(total,stencil_fraction(unwarped,7u)),edge);
            let exposed_scale = (total-snow_mix)/exposed;
            for (var code=1u; code<12u; code+=1u) {
                fraction[code] *= exposed_scale;
            }
            fraction[7] = snow_mix;
        }
    }
    return LandCover(fraction[1]+fraction[10],fraction[2],fraction[3],
        fraction[9]+fraction[11],fraction[4],fraction[5],fraction[6],fraction[7],0.);
}

fn forest_child(texel: vec2i, slot: i32) -> f32 {
    let bank = textureLoad(regional_cover,texel/2,slot,0);
    return bank[u32((texel.y & 1)*2 + (texel.x & 1))];
}

fn reconstructed_forest(page: LandscapePage, offset: vec2f) -> f32 {
    let texel = (page.texel+offset)*2.-.5;
    let cell = vec2i(texel);
    let t = fract(texel);
    let a = mix(forest_child(cell,page.regional_slot),forest_child(cell+vec2i(1,0),page.regional_slot),t.x);
    let b = mix(forest_child(cell+vec2i(0,1),page.regional_slot),
                forest_child(cell+vec2i(1,1),page.regional_slot),t.x);
    return mix(a,b,t.y);
}

fn forest_contour(page: LandscapePage) -> f32 {
    // A quadratic reconstruction rounds the axis changes of the sampled
    // cover field. Its weights sum to one and it stays within the source
    // neighbourhood, including across a page gutter.
    let texel = page.texel*2.-.5;
    let centre = vec2i(floor(texel+.5));
    let phase = texel-vec2f(centre);
    let low = .5*(vec2f(.5)-phase)*(vec2f(.5)-phase);
    let high = .5*(vec2f(.5)+phase)*(vec2f(.5)+phase);
    let mid = vec2f(1.)-low-high;
    let wx = vec3f(low.x,mid.x,high.x);
    let wy = vec3f(low.y,mid.y,high.y);
    var cover = 0.;
    for (var y=0;y<3;y++) {
        let row = centre+vec2i(0,y-1);
        let samples = vec3f(forest_child(row+vec2i(-1,0),page.regional_slot),
            forest_child(row,page.regional_slot),forest_child(row+vec2i(1,0),page.regional_slot));
        cover += dot(samples,wx)*wy[y];
    }
    return cover;
}

fn landscape_material(page: LandscapePage, scale_weight: f32, forest_detail: f32, near_weight: f32, smooth_snow: bool) -> LandCover {
    let regional_weight = scale_weight*select(1.,near_weight,page.regional_near_only);
    if page.regional_slot < 0 || regional_weight <= .001 {
        return legacy_landscape_material(page,smooth_snow);
    }
    let uv = page.texel / vec2f(792.,264.);
    let b = textureSampleLevel(regional_cover,linear,uv+vec2f(2./3.,0.),page.regional_slot,0.);
    if b.a*regional_weight <= .001 { return legacy_landscape_material(page,smooth_snow); }
    let a = textureSampleLevel(regional_cover,linear,uv+vec2f(1./3.,0.),page.regional_slot,0.);
    let broad = dot(textureSampleLevel(regional_cover,linear,uv,page.regional_slot,0.),vec4f(.25));
    let open = dot(a.rgb+b.rgb,vec3f(1.));
    let observed = smoothstep(.01,.50,broad+open+a.a);
    let weight = b.a * regional_weight * observed;
    if weight <= .001 { return legacy_landscape_material(page,smooth_snow); }
    var forest = broad;
    var rest = 1.;
    if forest_detail > .001 {
        // Keep water, town and unknown acreage fixed as the forest edge resolves.
        let edge = reconstructed_forest(page,vec2f(0.));
        let shape = smoothstep(.08,.22,edge)*(1.-smoothstep(.75,.92,edge));
        var resolved = edge;
        // Keep finer copses or gaps that are absent from the parent mean.
        let retained = 1.-smoothstep(.07,.21,abs(edge-broad));
        if shape*retained>.001 { resolved = mix(edge,forest_contour(page),shape*retained*.78); }
        forest = min(broad+open,mix(broad,resolved,forest_detail));
        rest = (open+broad-forest)/max(.0001,open);
        if open <= .0001 { forest = broad; }
    }
    let land = LandCover(forest,a.r*rest,a.g*rest,b.b*rest,a.b*rest,a.a,b.r*rest,b.g*rest,1.);
    if weight >= .999 { return land; }
    return mix_cover(legacy_landscape_material(page,smooth_snow),land,weight);
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

// The ground and cached stands share one continuous, world-space structure.
// Its variations describe canopy closure inside the recorded woodland.
fn woodland_structure(world: vec3f) -> f32 {
    let point = world*(EARTH/830.);
    let cell = bitcast<vec3u>(vec3i(floor(point)));
    let f = fract(point);
    let weights = f*f*(3.-2.*f);
    let seed = cell.x*116831u+cell.y*24571u+cell.z*72139u;
    let south = mix(landscape_random(seed),landscape_random(seed+116831u),weights.x);
    let north = mix(landscape_random(seed+24571u),landscape_random(seed+141402u),weights.x);
    let upper_south = mix(landscape_random(seed+72139u),landscape_random(seed+188970u),weights.x);
    let upper_north = mix(landscape_random(seed+96710u),landscape_random(seed+213541u),weights.x);
    return mix(mix(south,north,weights.y),mix(upper_south,upper_north,weights.y),weights.z);
}

fn landscape_conifers(latitude: f32, height: f32) -> f32 {
    return smoothstep(34.,67.,abs(latitude)+smoothstep(400.,1950.,height)*20.);
}

fn woodland_palette(conifers: f32) -> vec3f {
    return FOREST_GROUND+mix(vec3f(.022,.027,.010),vec3f(-.022,-.010,-.008),conifers);
}

struct LandscapeLayer {
    page: LandscapePage,
    weight: f32,
};

fn landscape_layers(ll: vec2f) -> array<LandscapeLayer,2> {
    var fine = LandscapeLayer(LandscapePage(vec2f(0.),-1,-1,0.,false),0.);
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
    // Supplemental near cover takes over between the 10 km and 5 km ruler marks.
    let near_weight = 1.-smoothstep(80.,125.,mpp);
    if layers[0].weight <= .001 { return landscape_material(layers[1].page,regional,forest_detail,near_weight,true); }
    let a = landscape_material(layers[0].page,regional,forest_detail,near_weight,true);
    if layers[1].weight <= .001 { return a; }
    return mix_cover(a,landscape_material(layers[1].page,regional,forest_detail,near_weight,true),layers[1].weight/weight);
}

fn rural_cover(land: LandCover, grade: f32, height: f32, detail: f32) -> LandCover {
    var result = land;
    // Legacy pages only store one land class per sample. Do not give their
    // inferred outlines the same authority as an area-covered regional page.
    let confidence = mix(.47,1.,land.regional);
    let open = land.grass+land.crop+land.shrub;
    let mosaic = open+land.forest;
    if mosaic > .001 && open > .001 {
        // Resolve the same boundary in the ground and in the model cache.
        // Preserve total natural cover and leave water, settlement and unknown intact.
        let forest = land.forest/mosaic;
        // Keep the shoulders of smaller mixed stands. Close to an
        // established contact, most pixels belong to one side of the edge.
        let edge = smoothstep(.474,.526,forest);
        let core = smoothstep(.12,.28,forest)*(1.-smoothstep(.75,.92,forest));
        result.forest = mosaic*mix(forest,edge,detail*confidence*(.55+core*.45));
        let remainder = (mosaic-result.forest)/open;
        result.grass *= remainder;
        result.crop *= remainder;
        result.shrub *= remainder;
    }
    let open_fields = result.grass+result.crop;
    if open_fields > .001 {
        let crop = result.crop/open_fields;
        let boundary = smoothstep(.455,.545,crop);
        // Fractional open agricultural ground can contain both crops and
        // grazing. Keep the mix in broad, gently sloping field country;
        // otherwise the sampling grid becomes the edge of every meadow.
        let open_country = smoothstep(.66,.91,open_fields)*(1.-smoothstep(.025,.11,grade));
        result.crop = open_fields*mix(crop,boundary,detail*confidence*mix(.91,.24,open_country));
        result.grass = open_fields-result.crop;
    }
    // At exposed woodland margins an existing grass share can carry
    // scrub. This transfers within open ground and never creates cropland.
    let rim = smoothstep(.10,.36,land.forest)*(1.-smoothstep(.44,.60,land.forest));
    let upland = smoothstep(275.,570.,height)*smoothstep(.027,.105,grade);
    let margin = result.grass*min(.66,rim*.89+upland*.82)*detail;
    result.grass -= margin;
    result.shrub += margin;
    return result;
}

fn rural_contact_sample(page: LandscapePage, offset: vec2f) -> vec2f {
    let point = page.texel+offset;
    let water = textureSampleLevel(terrain_detail,linear,point/264.,page.slot,0.).a;
    let uv = point/vec2f(792.,264.);
    let a = textureSampleLevel(regional_cover,linear,uv+vec2f(1./3.,0.),page.regional_slot,0.);
    let forest = dot(textureSampleLevel(regional_cover,linear,uv,page.regional_slot,0.),vec4f(.25));
    return vec2f(a.b*.44 - a.g*.26 - forest*.69 - a.a - water*1.6, a.b-a.g);
}

struct RuralContact {
    shift: vec2f,
    shared_edge: f32,
};

fn rural_contact(page: LandscapePage, latitude: f32, enclosure: f32, mpp: f32) -> RuralContact {
    let dx = vec2f(.72,0.);
    let dy = dx.yx;
    if page.regional_slot < 0 {
        let east = textureSampleLevel(terrain_detail,linear,(page.texel+dx)/264.,page.slot,0.).a;
        let west = textureSampleLevel(terrain_detail,linear,(page.texel-dx)/264.,page.slot,0.).a;
        let north = textureSampleLevel(terrain_detail,linear,(page.texel-dy)/264.,page.slot,0.).a;
        let south = textureSampleLevel(terrain_detail,linear,(page.texel+dy)/264.,page.slot,0.).a;
        return RuralContact(vec2f(west-east,south-north)*200.,0.);
    }
    let east = rural_contact_sample(page,dx)-rural_contact_sample(page,-dx);
    let north = rural_contact_sample(page,-dy)-rural_contact_sample(page,dy);
    var edge = 0.;
    if enclosure>.001 && mpp<42. {
        let local = textureSampleLevel(regional_cover,linear,
            page.texel/vec2f(792.,264.)+vec2f(1./3.,0.),page.regional_slot,0.);
        let span = (PI*EARTH)/f32(256u<<7u);
        let gradient = vec2f(east.y/max(.12,cos(radians(latitude))),north.y)/(1.44*span);
        // Where the data actually distinguishes adjoining arable and
        // grazing land, use its dividing curve as a common boundary.
        let rate = length(gradient);
        let distance = abs(local.b-local.g)/max(.00001,rate);
        edge = field_margin(distance,2.,mpp)*smoothstep(.00027,.00068,rate)
            *smoothstep(.51,.78,local.b+local.g)*(1.-smoothstep(14.,42.,mpp));
    }
    return RuralContact(clamp(vec2f(east.x,north.x),vec2f(-1.),vec2f(1.))*120.,edge);
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
    let surface = mix(base,tint,.58)*(1.+(growth-.5)*.20);

    let sides = min(phase,1.-phase)*spacing;
    let boundary = 1.-smoothstep(2.,max(7.,mpp*.70),min(sides.x,sides.y));
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

fn interval_edge(field: FieldInterval, span: f32) -> f32 {
    return min(field.phase,1.-field.phase)*field.width*span;
}

fn field_margin(distance: f32, width: f32, mpp: f32) -> f32 {
    return (1.-smoothstep(width,width+max(.65,mpp*.64),distance))
        * min(1.,2.*width/max(1.,mpp));
}

const OPEN_FIELDS: u32 = 0u;
const ENCLOSED_FIELDS: u32 = 1u;
const TERRACED_FIELDS: u32 = 2u;

struct FarmRegion {
    holding: vec2f,
    subdivisions: vec2f,
    enclosure: f32,
    organization: u32,
}

struct FarmContact {
    shift: vec2f,
    divide: vec2f,
    exposed: f32,
    settled: f32,
    pasture: f32,
    page: LandscapePage,
}

fn farm_ground_sample(page: LandscapePage, offset: vec2f) -> vec2f {
    let point = page.texel+offset;
    if any(point<vec2f(.5)) || any(point>vec2f(263.5)) { return vec2f(0.); }
    let uv = point/vec2f(792.,264.);
    let crop_grass = textureSampleLevel(regional_cover,linear,uv+vec2f(1./3.,0.),page.regional_slot,0.).bg;
    let known = textureSampleLevel(regional_cover,linear,uv+vec2f(2./3.,0.),page.regional_slot,0.).a;
    return crop_grass*known;
}

fn farm_use(cover: vec2f, parcel_key: f32, fallback: f32) -> f32 {
    let open = cover.x+cover.y;
    let cultivated = cover.x/max(.001,open);
    // The stable parcel threshold allocates the observed share to crops
    // or pasture across neighbouring holdings.
    let arable = smoothstep(parcel_key-.12,parcel_key+.12,cultivated);
    return mix(fallback,arable,smoothstep(.24,.73,open));
}

fn enclosure_fields(point: vec2f, span: vec2f, key: u32, shared_edge: f32,
                    pasture: bool, mpp: f32) -> vec2f {
    // One cross fence divides the holding. Only the side with enough room
    // can split again, and its fence ends at the first one.
    let entry = landscape_random(key+1283u);
    let reverse = entry>.5;
    let local = select(point,vec2f(point.y,1.-point.x),reverse);
    let size = select(span,span.yx,reverse);
    let bend = (landscape_random(key+791u)-.5)*.39;
    let split = .26+landscape_random(key+1723u)*.48+bend*(local.y-.5);
    let near_side = local.x<split;
    let division = abs(local.x-split)*size.x;
    let wider = near_side==(split>.5);
    let cross = .24+landscape_random(key+2729u)*.52
        +(local.x-split)*(landscape_random(key+1171u)-.5)*.48;
    let cross_fence = wider && !pasture && size.y>260.;
    let edge = min(division,select(1e6,abs(local.y-cross)*size.y,cross_fence));
    let pen = select(0u,98u,near_side)+select(0u,137u,cross_fence && local.y>cross);
    let relative_size = .47*min(span.x,span.y);
    let detail = 1.-smoothstep(relative_size*.026,relative_size*.12,mpp);
    let hedge = field_margin(edge,select(1.25,2.15,pasture),mpp)
        * (1.-smoothstep(13.,38.,mpp))*smoothstep(1.,9.,shared_edge);
    return vec2f((landscape_random(key+pen+3187u)-.5)*detail,hedge);
}

// The reach ends at a transverse divide. Approaches on opposing sides
// of that divide belong to different holdings and need not meet end to end.
fn farm_holding(base: vec3f, axis: vec2f, mpp: f32, region: FarmRegion, site: FarmContact,
                texels: mat2x2<f32>) -> vec3f {
    let reach = field_interval(axis.y/(region.holding.y*2.),.67,1277u);
    let reach_key = bitcast<u32>(i32(reach.index))*28571u;
    let enclosed = region.organization==ENCLOSED_FIELDS;
    let terraced = region.organization==TERRACED_FIELDS;
    let approach = (landscape_random(reach_key+4513u)-.5)*1.45;
    let facing = select(approach*.40,approach,enclosed || terraced);
    let bend = (reach.phase-.5)*facing*region.holding.x;
    let u = field_interval((axis.x+bend)/region.holding.x,.67,reach_key+9143u);
    let row = bitcast<u32>(i32(u.index))*19681u;
    let lane_position = landscape_random(row+reach_key+751u);
    let stagger = select(mix(.34,.66,lane_position),mix(.17,.82,lane_position),enclosed);
    // Each approach splits one reach into a facing pair. Cross-lanes are
    // bounded by the approach and the reach, which also own their headlands.
    let back = reach.phase >= stagger;
    let fraction = select(stagger,1.-stagger,back);
    let phase = (reach.phase-select(0.,stagger,back))/fraction;
    let v = FieldInterval(select(0.,1.,back),phase,reach.width*2.*fraction);
    let key = row+reach_key+select(0u,42221u,back);
    let rotation = landscape_random(key+1483u);
    let span = vec2f(u.width,v.width)*region.holding;
    let shear = facing*region.holding.x/(reach.width*2.*region.holding.y);
    var holding_use = rotation;
    if enclosed && site.page.regional_slot>=0 {
        let centre = (vec2f(.5)-vec2f(u.phase,v.phase))*span;
        let sampled = farm_ground_sample(site.page,texels*vec2f(centre.x-shear*centre.y,centre.y));
        holding_use = farm_use(sampled,rotation,rotation);
    }
    let farm = landscape_random(key+6981u);
    let soil = mix(vec3f(.569,.524,.369),vec3f(.608,.558,.407),farm);
    let summer = mix(vec3f(.474,.510,.342),vec3f(.533,.553,.378),farm);
    let rotated_use = mix(summer,soil,smoothstep(.29,.84,holding_use));
    // Choose the interior fence layout from the observed holding use.
    // Grazing keeps one shared paddock divide. Arable holdings can split again.
    let pasture = enclosed && holding_use<.46;
    let grazing = select(0.,1.-smoothstep(.25,.52,holding_use),enclosed);
    let group = mix(rotated_use,mix(vec3f(.433,.496,.332),vec3f(.503,.542,.377),farm),grazing);
    let grouping = 1.-smoothstep(70.,123.,mpp);
    let open_ground = 1.-smoothstep(.19,.55,site.exposed);
    // The two holdings approached from one corridor remain legible as a
    // pair before either one's internal fences can be resolved.
    let approach_color = landscape_random(row+reach_key+5041u);
    let corridor = mix(summer,soil,smoothstep(.12,.88,approach_color));
    let grouped = mix(corridor,group,select(1.-smoothstep(16.,47.,mpp),.72,enclosed));
    let farm_color = mix(base,grouped,
        mix(.37,1.,open_ground));
    var color = mix(base,farm_color,grouping*.91);

    var within = vec2f(u.phase,v.phase);
    if terraced {
        // A water or slope contact steers the interior embankments.
        // A row terminates at its holding's shared headland.
        let bank = clamp(site.divide.y*1.35,-.27,.27);
        within.x += bank*(within.y-.5);
        within.y += clamp(site.divide.x,-.18,.18)*(within.x-.5);
    }
    // A holding keeps its common approach and headland while different
    // strips subdivide it towards the interior.
    let end = interval_edge(v,region.holding.y);
    let side = interval_edge(u,region.holding.x);
    let edge = min(side,end);
    let interior = smoothstep(3.,15.,edge);
    if enclosed {
        let pens = enclosure_fields(within,span,key,edge,pasture,mpp);
        color *= 1.+pens.x*interior*select(.12,.055,pasture);
        color = mix(color,vec3f(.368,.448,.307),pens.y*.78);
    } else {
        let chart = field_interval(within.x*region.subdivisions.x,.44,key+5501u);
        let strip = bitcast<u32>(i32(chart.index))*15217u;
        let lengths = field_interval(within.y*region.subdivisions.y,.55,key+strip+9221u);
        let strip_span = span/region.subdivisions;
        let inner = min(interval_edge(chart,strip_span.x),interval_edge(lengths,strip_span.y));
        let field = landscape_random(key+strip+bitcast<u32>(i32(lengths.index))*8941u);
        let texture_scale = min(strip_span.x*chart.width,strip_span.y*lengths.width);
        let detail = (1.-smoothstep(texture_scale*.05,texture_scale*.16,mpp))*grouping;
        var field_use = clamp(holding_use+(field-.5)*.45,0.,1.);
        if !terraced && site.page.regional_slot>=0 && detail>.001 {
            // Allocate mixed crop and grazing to the strip that owns it.
            // Sample its interior in Z7 space and keep nearby water and
            // woodland contacts at their source locations.
            let across = (.5-chart.phase)*chart.width*strip_span.x;
            let along = (.5-lengths.phase)*lengths.width*strip_span.y;
            let centre = vec2f(across-shear*along,along);
            let cover = farm_ground_sample(site.page,texels*centre);
            field_use = farm_use(cover,field,field_use)*mix(.72,1.,farm);
        }
        color = mix(color,mix(summer,soil,field_use),
            detail*interior*.63);
        let inside = field_margin(inner,1.1,mpp)*(1.-smoothstep(6.,18.,mpp))*interior;
        color = mix(color,vec3f(.462,.503,.338),inside*.40);
        if terraced && mpp<20. {
            let berm = field_margin(inner,2.35,mpp)*interior*(1.-smoothstep(8.,20.,mpp));
            let valley = 1.-smoothstep(.025,.140,site.exposed);
            let bed = mix(vec3f(.514,.521,.347),vec3f(.415,.505,.352),valley*field);
            let reveal = (1.-smoothstep(3.5,15.,mpp))*interior;
            color = mix(color,bed,reveal*.74);
            color = mix(color,mix(vec3f(.384,.448,.308),vec3f(.470,.485,.344),valley),berm*.81);
        }
    }

    // A lane on selected shared longitudinal sides, with other sides
    // left as a verge or hedge. No roads cross the inside of a holding.
    let merge = landscape_random(row+select(0u,19681u,u.phase>.5)+337u);
    // An approach that serves a neighbour must meet its holding. A lane
    // cannot run through steep ground or carry on into unmanaged pasture.
    let access = 1.-smoothstep(.085,.24,site.exposed);
    let lane = merge>.65 && access>.45;
    let hedge = !lane && merge<region.enclosure;
    let at_divide = !back && v.phase<.5 || back && v.phase>.5;
    let cross_key = select(row+reach_key+221u,
        select(reach_key,reach_key+28571u,back)+221u,at_divide);
    let cross_use = landscape_random(cross_key);
    let cross_lane = end<side && cross_use<(.12+site.settled*.43)*access;
    let headland = end<side && !cross_lane && cross_use<region.enclosure*.78;
    let boundary = field_margin(edge,select(1.7,4.4,hedge||headland),mpp);
    let dividing_hedge = select(hedge,headland,end<side);
    let verge = select(vec3f(.443,.477,.331),vec3f(.340,.426,.285),dividing_hedge);
    color = mix(color,verge,boundary*(1.-smoothstep(23.,53.,mpp))*select(.23,.78,dividing_hedge));
    if lane || cross_lane {
        let distance = select(side,edge,cross_lane);
        let track = field_margin(distance,3.2,mpp)*(1.-smoothstep(14.,42.,mpp));
        color = mix(color,vec3f(.569,.528,.435),track*.83);
    }
    return color;
}

fn farm_axis(metres: vec2f, terrain: vec2f) -> vec2f {
    // Continuous, low-curvature corridors are steered by landform and
    // geographic contacts. Their local width never depends on the camera.
    let cross = metres.y*.00031+metres.x*.00011;
    let along = metres.x*.00021-metres.y*.00016;
    return metres+vec2f(520.*sin(cross),490.*sin(along))+terrain;
}

fn field_texel_basis(east: vec2f, north: vec2f, sample_size: vec2f) -> mat2x2<f32> {
    // Convert offsets on the dominant world chart back to the QSC grid.
    let determinant = east.x*north.y-east.y*north.x;
    return mat2x2<f32>(vec2f(north.y,east.y)/sample_size,
        -vec2f(north.x,east.x)/sample_size)*(1./determinant);
}

fn world_field_parcels(base: vec3f, ll: vec2f, world: vec3f, mpp: f32, height: f32,
                       site: FarmContact) -> vec3f {
    let maritime = field_region(ll,vec2f(-5.,54.),vec2f(13.,7.));
    let eastern = field_region(ll,vec2f(120.,34.),vec2f(36.,20.));
    let open = FarmRegion(vec2f(1860.,1440.),vec2f(5.,2.),.16,OPEN_FIELDS);
    let enclosed = FarmRegion(vec2f(800.,920.),vec2f(1.),.75,ENCLOSED_FIELDS);
    let east = FarmRegion(vec2f(730.,690.),vec2f(8.,5.),.22,TERRACED_FIELDS);
    let bent = vec2f(1.3,-1.4)*height+site.shift;
    var ink = base;
    let empty_basis = mat2x2<f32>(vec2f(0.),vec2f(0.));
    let latitude_scale = max(.16,cos(radians(ll.y)));
    let sample_size = (PI*EARTH)/f32(256u<<7u)*vec2f(latitude_scale,1.);
    if maritime < 1. && eastern < 1. {
        let rotation = transpose(mat3x3<f32>(vec3f(.80,.60,0.),vec3f(-.36,.48,.80),vec3f(.48,-.64,.60)));
        let rotated = rotation*world;
        let metres = rotated*EARTH;
        let facing = abs(rotated);
        let strongest = max(facing.x,max(facing.y,facing.z));
        let weights = smoothstep(vec3f(strongest-.009),vec3f(strongest),facing);
        ink = vec3f(0.);
        let angle = radians(ll);
        let east = vec3f(cos(angle.x),0.,-sin(angle.x));
        let e = rotation*east;
        let n = rotation*cross(world,east);
        if weights.x > 0. {
            let basis = field_texel_basis(e.yz,n.yz,sample_size);
            ink += farm_holding(base,farm_axis(metres.yz,bent),mpp,open,site,basis)*weights.x;
        }
        if weights.y > 0. {
            let basis = field_texel_basis(e.zx,n.zx,sample_size);
            ink += farm_holding(base,farm_axis(metres.zx,bent),mpp,open,site,basis)*weights.y;
        }
        if weights.z > 0. {
            let basis = field_texel_basis(e.xy,n.xy,sample_size);
            ink += farm_holding(base,farm_axis(metres.xy,bent),mpp,open,site,basis)*weights.z;
        }
        ink /= dot(weights,vec3f(1.));
    }
    if maritime > 0. {
        let local = field_metres(ll,vec2f(-5.,54.));
        let oblique = vec2f(dot(local,vec2f(.94,.342)),dot(local,vec2f(-.342,.94)));
        // Enclosure follows the local topographic surface rather than
        // a single bearing across the region. Woodland and settlement
        // contacts turn the same shared boundaries on neighbouring plots.
        let relief = vec2f(-3.4,3.0)*height+site.shift*1.8;
        let scale = cos(radians(54.))/latitude_scale;
        let basis = field_texel_basis(vec2f(.94,-.342)*scale,vec2f(.342,.94),sample_size);
        ink = mix(ink,farm_holding(base,farm_axis(oblique,relief),mpp,enclosed,site,basis),maritime);
    }
    if eastern > 0. {
        let local = field_metres(ll,vec2f(120.,34.));
        let lowlands = 1.-smoothstep(40.,360.,height);
        let steered = vec2f(-2.1,1.5)*height+site.shift*(1.+lowlands*.44);
        ink = mix(ink,farm_holding(base,farm_axis(local,steered),mpp,east,site,empty_basis),eastern);
    }
    return ink;
}

fn midwest_fields(base: vec3f, metres: vec2f, mpp: f32, site: FarmContact) -> vec3f {
    let section_metres = 1609.34;
    let sections = metres/section_metres;
    let township = vec2i(floor(sections/6.));
    let township_id = bitcast<u32>(township.x)*20809u+bitcast<u32>(township.y)*61001u;
    // The two-section approaches are the primary structure. Keep the
    // section scale for farm entrances and allow adjoining parcels to share
    // a headland when a section boundary has no access road.
    let district = floor(sections*.5);
    let district_id = bitcast<u32>(i32(district.x))*1511u+bitcast<u32>(i32(district.y))*6101u;
    let block = fract(sections*.5)*2.;
    let across = landscape_random(district_id+3187u)<.50;
    let point = select(block,vec2f(block.y,2.-block.x),across);
    let district_tone = mix(landscape_random(township_id+1267u),landscape_random(district_id+139u),.48);
    let seasonal = vec3f(.489,.524,.353);
    let stubble = vec3f(.580,.550,.382);
    let area = mix(seasonal,stubble,district_tone);
    var paint = mix(base,area,.76);
    if mpp>=25. { return paint; }

    let upland = smoothstep(.008,.10,length(site.divide));
    let grade = select(site.divide.y,-site.divide.x,across);
    let street = min(min(point.x,2.-point.x),min(point.y,2.-point.y))*section_metres;
    let headland = abs(point.y-1.)*section_metres;
    let far = point.x>=1.;
    let side = select(point.x,2.-point.x,far);
    let holding_id = district_id+select(1087u,1463u,far);
    // Frontages are shared by several fields and work back from a common
    // survey access. Cross-lanes terminate at that access or a headland.
    let frontage = field_interval(point.y*1.4,.58,holding_id+419u);
    let width = frontage.width*section_metres/1.4;
    let entrance_id = holding_id+bitcast<u32>(i32(frontage.index))*1277u;
    let backing = .40+landscape_random(entrance_id+2527u)*.40;
    let offset = clamp(grade*1.8,-.16,.16)*sin(PI*frontage.phase);
    let divide = backing+offset;
    let back = side>=divide;
    let rear_id = select(0u,823u,back);
    let cross = .31+landscape_random(entrance_id+rear_id+877u)*.38;
    let split = width>780. && landscape_random(entrance_id+rear_id+1933u)<.60;
    let divided = split && frontage.phase>=cross;
    let crop_id = entrance_id+rear_id+select(0u,631u,divided);
    let crop = landscape_random(crop_id);
    let near = 1.-smoothstep(7.,25.,mpp);
    let colour = mix(area,mix(seasonal,stubble,crop),select(.70,.42,back));
    paint = mix(paint,colour,near*.74);

    let frontage_edge = interval_edge(frontage,section_metres/1.4);
    let fence = abs(side-divide)*section_metres;
    let strip = select(1e6,abs(frontage.phase-cross)*width,split);
    let verge = field_margin(min(frontage_edge,min(fence,strip)),2.3,mpp)*near;
    paint = mix(paint,vec3f(.437,.483,.329),verge*.58);
    // The turning strip and access verge are part of the field surface.
    // They only resolve when they span several pixels.
    let near_ground = 1.-smoothstep(2.3,5.4,mpp);
    let turn_distance = min(side*section_metres,fence);
    let turning_strip = field_margin(turn_distance,7.5,mpp)*near_ground;
    let turning_soil = mix(area,stubble,.51);
    paint = mix(paint,turning_soil,turning_strip*.65);
    let shoulder = field_margin(max(0.,street-3.),5.,mpp)*near_ground;
    paint = mix(paint,vec3f(.437,.483,.329),shoulder*.69);
    // Preserve the connected survey roads with less frequent lateral
    // approaches. On steep land the same corridor remains a vegetated verge.
    let approach = min(street,select(1e6,headland,landscape_random(district_id+991u)<.42));
    let track = field_margin(approach,3.5,mpp)*(1.-smoothstep(11.,25.,mpp));
    let track_ink = mix(vec3f(.565,.526,.431),vec3f(.437,.483,.329),upland);
    return mix(paint,track_ink,track*.77);
}
fn cultivated_fields(base: vec3f, ll: vec2f, world: vec3f, mpp: f32, height: f32,
                     site: FarmContact) -> vec3f {
    let visible = 1.-smoothstep(74.,124.,mpp);
    if visible <= .001 { return base; }

    var region = field_region(ll,vec2f(-93.,42.),vec2f(10.8,5.5));
    var ink = base;
    if region > 0. {
        ink = midwest_fields(base,field_metres(ll,vec2f(-94.,42.)),mpp,site);
    } else {
        region = field_region(ll,vec2f(31.06,30.91),vec2f(1.27,.79));
        if region > 0. {
            // Rosetta and Damietta tangents from the existing Natural Earth source.
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
                    // HydroRIVERS 20510450 and 20509223 guide the lower Reno plain.
                    let axis = vec2f(.629,.777);
                    let metres = field_metres(ll,vec2f(11.30,44.71));
                    let aligned = vec2f(dot(metres,axis),dot(metres,vec2f(-axis.y,axis.x)));
                    ink = mix(ink,field_parcels(base,aligned,mpp,pattern),reno);
                }
            }
        }
    }
    if region < 1. { ink = mix(world_field_parcels(base,ll,world,mpp,height,site),ink,region); }
    return mix(base,ink,visible);
}

fn material_grain(world: vec3f, mpp: f32, layer: i32, span: f32, fade: f32) -> f32 {
    if mpp >= fade { return 0.; }
    let average = textureLoad(surface_art,vec2i(0),layer,i32(textureNumLevels(surface_art))-1).rgb;
    let paint = painted_material(world,mpp,layer,span);
    let light = vec3f(.24,.65,.11);
    return dot(paint-average,light)/max(.18,dot(average,light))*(1.-smoothstep(fade*.45,fade,mpp));
}

fn woodland_ground(world: vec3f, latitude: f32, height: f32, mpp: f32, original: vec3f) -> vec3f {
    let detail = 1.-smoothstep(34.,103.,mpp);
    if detail <= .001 { return original; }
    let closure = woodland_structure(world);
    let needles = landscape_conifers(latitude,height);
    let palette = woodland_palette(needles)-FOREST_GROUND;
    return (original+palette*(detail*.67))*(1.+(.5-closure)*detail*.079);
}

fn rock_share(land: LandCover, grade: f32, height: f32) -> vec2f {
    let bare = land.bare*max(smoothstep(.13,.48,grade),smoothstep(1550.,3550.,height)*.70);
    return vec2f(bare,smoothstep(.43,.95,grade)*.47);
}

fn frontage_weight(road: FieldRoad, mpp: f32) -> f32 {
    return (1.-smoothstep(27.,49.,road.clearance))*(1.-smoothstep(14.,36.,mpp));
}

fn field_frontage(road: FieldRoad, mpp: f32, pasture: f32) -> vec3f {
    // Use a mapped approach as the first boundary. Each side has its own
    // holding entrance and cross divisions with no change to the road network.
    let side = select(19u,43u,road.side>=0.);
    let entrance = field_interval(road.station/370.,.53,side+2551u);
    let key = side+bitcast<u32>(i32(entrance.index))*17159u;
    let front = field_interval(entrance.phase*3.,.48,key+8753u);
    let field = landscape_random(key+bitcast<u32>(i32(front.index)));
    let color = mix(vec3f(.461,.509,.346),vec3f(.564,.532,.379),field*(1.-pasture*.63));
    let boundary = field_margin(interval_edge(front,entrance.width*370./3.),1.45,mpp);
    return mix(color,vec3f(.404,.468,.326),boundary*.74);
}

fn ground_motif(base: vec3f, ll: vec2f, world: vec3f, land: LandCover,
                slope: vec2f, height: f32, fine: LandscapeLayer, water: f32, mpp: f32,
                unrecorded: f32) -> vec3f {
    if view.road_layer.x==4u {return vec3f(land.urban,land.grass+land.crop,land.forest);}
    let share = rock_share(land,length(slope),height);
    let rock = share.x+(land.grass+land.shrub)*share.y;
    let sand = land_palette_weight(land_chroma(base),vec3f(.775,.632,.433),.074);
    var forest = FOREST_GROUND;
    if land.forest > .001 {
        // The same continuous canopy remains below the individual crowns.
        let crowns = material_grain(world,mpp,WOODLAND,mix(1320.,410.,land.regional),mix(84.,55.,land.regional));
        let leaves = material_grain(world,mpp,WOODLAND,315.,16.);
        forest *= 1.+(crowns*mix(1.32,.60,land.regional)+leaves*.48)*(landscape_wood(land).x/max(.001,land.forest));
        forest = woodland_ground(world,ll.y,height,mpp,forest);
    }
    let exposure = clamp(slope.y*.19+height*.00007,-.08,.15);
    var grass = GRASS_GROUND+vec3f(-.09,-.012,.09)*exposure;
    if land.grass > .001 && mpp<66. {
        let close = 1.-smoothstep(38.,66.,mpp);
        var local = slope;
        var shelter = dot(local,vec2f(-.56,.83));
        var shoulder = 0.;
        if fine.weight>.001 && mpp<28. {
            let relief = landscape_slope(fine.page,ll.y,.48,7u);
            local = mix(slope,relief,.8*fine.weight);
            let relief_span = vec2f(.82,1.14);
            let shoulder_mean = (landscape_elevation(fine.page,relief_span)
                +landscape_elevation(fine.page,-relief_span))*.5;
            shoulder = clamp((height-shoulder_mean)*.10,-1.,1.);
            shelter = dot(local,vec2f(-.56,.83))-shoulder*.084;
        }
        let upland = smoothstep(235.,555.,height);
        let uphill = max(smoothstep(.012,.105,length(local)),abs(shoulder)*.48)*mix(.31,1.,upland);
        let pasture = mix(vec3f(.539,.536,.366),vec3f(.377,.468,.333),
            smoothstep(-.085,.098,shelter));
        // Moist woodland margins and slopes shade the open ground itself.
        let margin = smoothstep(.08,.32,land.forest)*(1.-smoothstep(.46,.67,land.forest));
        grass = mix(grass,pasture,uphill*close*.86);
        grass = mix(grass,vec3f(.374,.461,.323),margin*close*.78);
        // Exposed slopes have thin grass over their shoulders. At the
        // foot of the same slope and along woods the ground is sheltered.
        let ridge = smoothstep(.10,.64,shoulder)*smoothstep(.031,.098,length(local))*upland;
        let foot = smoothstep(.08,.53,-shoulder)*smoothstep(.023,.071,length(local));
        let face = clamp(dot(local,vec2f(.52,.70))*3.1+shoulder*.28,-.34,.24);
        grass = mix(grass,vec3f(.518,.529,.401),ridge*close*.51);
        grass = mix(grass,vec3f(.390,.471,.342),foot*close*.31);
        grass *= 1.+face*upland*close;
        grass *= 1.+material_grain(world,mpp,GRASS,104.,11.)*(.25+upland*.53)
            +material_grain(world,mpp,GRASS,29.,4.2)*.52;
        if ridge>.04 {
            let stone = material_grain(world,mpp,ROCK,48.,6.);
            grass *= 1.+stone*ridge*.51;
        }
    }
    // Keep partial land-cover mixtures. The field ink resolves in observed
    // arable ground and cannot claim woods, water or settled land.
    let exposed = max(max(land.urban,land.forest),max(land.snow,land.damp));
    let agriculture = land.crop/max(.001,land.crop+land.grass+land.shrub+land.forest);
    let crop = smoothstep(.22,.63,land.crop)*smoothstep(.36,.65,agriculture);
    let enclosure = field_region(ll,vec2f(-5.,54.),vec2f(13.,7.));
    let enclosed_pasture = smoothstep(.037,.19,agriculture)*smoothstep(.24,.69,land.grass);
    let open_pasture = smoothstep(.097,.32,agriculture)*smoothstep(.12,.58,land.grass)
        *(1.-smoothstep(.027,.10,length(slope)))*.65;
    let pasture = mix(open_pasture,enclosed_pasture,enclosure);
    let mosaic_slope = mix(vec2f(.044,.15),vec2f(.075,.23),enclosure);
    let mosaic = smoothstep(.035,.16,agriculture)*smoothstep(.50,.80,land.grass+land.crop)
        *(1.-smoothstep(mosaic_slope.x,mosaic_slope.y,length(slope)))*land.regional;
    let owned = (1.-smoothstep(.18,.47,exposed))*(1.-smoothstep(.19,.47,length(slope)))
        *(1.-smoothstep(.02,.24,water));
    var cultivation = CROP_GROUND;
    if max(max(crop,pasture),mosaic)*owned > .012 && mpp<120. && fine.weight>.001 {
        // Terrain and mapped edges steer the holding before its strips
        // are generated. Only Z7 defines the layout at every zoom.
        let elevation = landscape_elevation(fine.page,vec2f(0.));
        let road = field_road(ll,49.);
        let contact = rural_contact(fine.page,ll.y,enclosure,mpp);
        let shore = contact.shift*1.55;
        let divide = slope+shore*.0037;
        let site = FarmContact(shore,divide,length(slope)+land.forest*.52,land.urban,
            land.grass+land.damp*.7,fine.page);
        // The road-facing holding and its verge take the land first.
        // Generate the wider field hierarchy beyond that shared headland.
        let front = frontage_weight(road,mpp);
        var surface = CROP_GROUND;
        if front<.999 { surface = cultivated_fields(CROP_GROUND,ll,world,mpp,elevation,site); }
        if front>.001 { surface = mix(surface,field_frontage(road,mpp,site.pasture),front); }
        if enclosure>.001 && road.clearance<25. && mpp<28. {
            let verge = verge_habitat(land,road)*(1.-smoothstep(12.,28.,mpp));
            let hedge = field_margin(abs(road.clearance-8.5),1.8,mpp);
            surface = mix(surface,vec3f(.372,.444,.302),hedge*verge*enclosure);
        }
        let grain = material_grain(world,mpp,FIELD,44.,6.3);
        let road_edge = smoothstep(-.8,5.5,road.clearance);
        let verge = mix(GRASS_GROUND,surface,road_edge);
        cultivation = mix(CROP_GROUND,verge*(1.+grain*.51),crop*owned*fine.weight);
        // A holding can also include grazing and enclosed meadows.
        grass = mix(grass,mix(grass,verge,.58),pasture*owned*fine.weight);
        // Both sides of observed agricultural ground use the same holding
        // surface. The land-cover channels retain their original shares.
        let held = mosaic*owned*fine.weight*(1.-smoothstep(53.,114.,mpp));
        let held_surface = verge*(1.+grain*.37);
        cultivation = mix(cultivation,held_surface,held*.93);
        grass = mix(grass,held_surface,held*.93);
        let perimeter = contact.shared_edge*enclosure*owned*fine.weight*road_edge;
        let hedge = vec3f(.366,.442,.302);
        cultivation = mix(cultivation,hedge,perimeter*.72);
        grass = mix(grass,hedge,perimeter*.72);
    }
    var earth = mix(SOIL_GROUND,SAND_GROUND,sand);
    if land.bare-share.x > .001 {
        let soil = material_grain(world,mpp,SOIL,32.,5.);
        let sand_grain = material_grain(world,mpp,SAND,32.,5.);
        earth *= 1.+mix(soil,sand_grain,sand)*.66;
    }
    var scrub = SHRUB_GROUND;
    if land.shrub>.001 {
        scrub *= 1.+material_grain(world,mpp,WOODLAND,122.,21.)*.64
            +material_grain(world,mpp,GRASS,39.,6.)*.47;
    }
    let unsettled = unrecorded*(1.-smoothstep(5.,24.,mpp));
    let disturbed = mix(BUILT_GROUND,vec3f(.511,.519,.412),unsettled)
        *(1.+material_grain(world,mpp,SOIL,39.,6.)*.34*unsettled);
    var stone = ROCK_GROUND;
    if rock > .001 { stone *= 1.+material_grain(world,mpp,ROCK,88.,12.)*.66; }
    var snow = SNOW_GROUND;
    if land.snow > .001 { snow *= 1.+material_grain(world,mpp,SNOW,65.,9.)*.49; }

    // Transfer only the exposed share of open ground to rock.
    let tint = (forest-base)*land.forest + (grass-base)*land.grass*(1.-share.y)
        + (scrub-base)*land.shrub*(1.-share.y) + (DAMP_GROUND-base)*land.damp
        + (cultivation-base)*land.crop + (disturbed-base)*land.urban*mix(.23,.89,unsettled)
        + (earth-base)*(land.bare-share.x) + (stone-base)*rock + (snow-base)*land.snow;
    let normal = normalize(vec3f(-slope*1.32,1.));
    let light = clamp((dot(normal,LANDSCAPE_SUN)-LANDSCAPE_SUN.z)*.57,-.34,.22);
    let ground_detail = 1.-smoothstep(66.,124.,mpp);
    let paint = mix((1.-smoothstep(90.,430.,mpp))*.81,.87,land.regional);
    // In the close view the resolved cover owns its portion of the ground.
    // Leave the original raster visible through the unclassified share only.
    let resolved = mix(paint,1.,ground_detail*max(land.regional,.46));
    let relief = mix(1.,.65,land.regional);
    return clamp((base+tint*resolved)*(1.+light*relief*(1.-land.snow*.5)),vec3f(0.),vec3f(1.));
}

fn natural_relief(base: vec3f, ll: vec2f, world: vec3f, water: f32, mpp: f32,
                  unrecorded: f32) -> vec3f {
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
    let regional_detail = 1.-smoothstep(74.,124.,mpp);
    let cover = rural_cover(land,length(slope)/weight,height/weight,regional_detail);
    let ground = ground_motif(base,ll,world,cover,slope/weight,height/weight,layers[0],water,mpp,unrecorded);
    return mix(fallback,ground,strength*modern*weight);
}

struct HistoricSurfacePage {
    uv: vec2f,
    metres: vec2f,
    side: u32,
    first: u32,
    weight: f32,
    paris: bool,
}

fn historic_surface_page(ll:vec2f,mpp:f32) -> HistoricSurfacePage {
    let empty=HistoricSurfacePage(vec2f(0.),vec2f(0.),0u,0u,0.,false);
    if mpp>=115. || view.map_style.y<=.5 || view.selection.y>.5 {return empty;}
    let base=city_water[arrayLength(&city_water)-3u];
    for (var site=0u;site<city_water[base];site+=1u) {
        let header=base+1u+6u*site;
        let low=vec2f(bitcast<f32>(city_water[header]),bitcast<f32>(city_water[header+1u]));
        let high=vec2f(bitcast<f32>(city_water[header+2u]),bitcast<f32>(city_water[header+3u]));
        if any(ll<low) || any(ll>=high) {continue;}
        let span=high-low;
        let uv=vec2f(ll.x-low.x,high.y-ll.y)/span;
        let metres=span*111195.*vec2f(cos(radians((low.y+high.y)*.5)),1.);
        let border=min(uv,1.-uv)*metres;
        // LOD handoff to the existing overview. The short margin only
        // handles the rectangular limit of this source, not settlement edges.
        let weight=(1.-smoothstep(77.,115.,mpp))*smoothstep(0.,680.,min(border.x,border.y));
        return HistoricSurfacePage(uv,metres,city_water[header+4u],base+city_water[header+5u],weight,site==1u);
    }
    return empty;
}

struct HistoricUse {
    built: vec3f, // roofs, courtyards, work yards
    open: vec3f, // grass / open plots, woods, street footprint
    garden: f32, // garden use inferred from the recorded landscape
}

fn historic_surface_texel(at:u32) -> HistoricUse {
    let word=city_water[at];
    let shifts=vec3u(0u,5u,10u);
    return HistoricUse(vec3f((vec3u(word)>>shifts)&vec3u(31u))/31.,
        vec3f((vec3u(word)>>(shifts+15u))&vec3u(31u))/31.,f32(word>>30u)/3.);
}

fn interpolate_use(a:HistoricUse,b:HistoricUse,t:f32) -> HistoricUse {
    return HistoricUse(mix(a.built,b.built,t),mix(a.open,b.open,t),mix(a.garden,b.garden,t));
}

fn historic_surface_level(page:HistoricSurfacePage,level:u32) -> HistoricUse {
    let width=page.side>>level;
    let first=page.first+4u*(page.side*page.side-width*width)/3u;
    let point=clamp(page.uv*f32(width)-.5,vec2f(0.),vec2f(f32(width-1u)));
    let low=vec2u(point);
    let high=min(low+1u,vec2u(width-1u));
    let a=interpolate_use(historic_surface_texel(first+low.y*width+low.x),
        historic_surface_texel(first+low.y*width+high.x),fract(point.x));
    let b=interpolate_use(historic_surface_texel(first+high.y*width+low.x),
        historic_surface_texel(first+high.y*width+high.x),fract(point.x));
    return interpolate_use(a,b,fract(point.y));
}

fn historic_surface_use(page:HistoricSurfacePage,mpp:f32) -> HistoricUse {
    let spacing=min(page.metres.x,page.metres.y)/f32(page.side);
    let mip=clamp(log2(mpp/spacing),0.,log2(f32(page.side)));
    let level=u32(mip);
    let land=historic_surface_level(page,level);
    if fract(mip)<=.001 {return land;}
    return interpolate_use(land,historic_surface_level(page,level+1u),fract(mip));
}

fn historic_street_weight(mpp:f32,paris:bool) -> f32 {
    return select(smoothstep(9.,18.,mpp),smoothstep(5.,13.,mpp),paris);
}

fn paris_core_weight(ll: vec2f) -> f32 {
    // Extent of the detailed PTM street and block survey (STREETS_GROUP).
    let border = min(ll-vec2f(2.251,48.815),vec2f(2.417,48.903)-ll);
    return smoothstep(0.,.0025,min(border.x,border.y));
}

fn market_garden(ll: vec2f, world: vec3f, mpp: f32) -> vec3f {
    let road = field_road(ll,49.);
    let front = frontage_weight(road,mpp);
    let verge = smoothstep(-1.,5.5,road.clearance);
    let grain = 1.+material_grain(world,mpp,FIELD,29.,5.4)*.51;
    if front>=.999 {
        return mix(GRASS_GROUND,field_frontage(road,mpp,.37)*grain,verge);
    }
    let metres = field_metres(ll,vec2f(2.385,48.922));
    let strip = vec2f(.63,.777);
    let axis = vec2f(dot(metres,vec2f(strip.y,-strip.x)),dot(metres,strip));
    // The local archive describes this axis and the strip areas. The
    // reconstructed garden encloses groups of adjacent beds with common
    // headlands. The individual beds only resolve at street scale.
    let headland = field_interval(axis.y/194.,.58,5581u);
    let key = bitcast<u32>(i32(headland.index))*17737u;
    let block = field_interval(axis.x/116.,.58,key+7433u);
    let strip_key = key+bitcast<u32>(i32(block.index))*21169u;
    let across = field_interval(block.phase*4.,.48,strip_key+9071u);
    let group = landscape_random(strip_key);
    let growth = mix(group,landscape_random(strip_key+bitcast<u32>(i32(across.index))),
        (1.-smoothstep(3.5,9.5,mpp))*.48);
    let ink = mix(vec3f(.479,.522,.352),vec3f(.559,.539,.382),growth);
    let cross = field_margin(interval_edge(headland,194.),2.6,mpp);
    let edge = field_margin(interval_edge(block,116.),1.65,mpp);
    let row = field_margin(interval_edge(across,block.width*29.),.9,mpp);
    let parcel = mix(ink,vec3f(.451,.477,.326),max(cross,edge)*.59+row*(1.-max(cross,edge))*.35);
    var surface = parcel;
    if front>.001 { surface = mix(parcel,field_frontage(road,mpp,.37),front); }
    return mix(GRASS_GROUND,surface*grain,verge);
}

fn landscape_relief(base:vec3f,ll:vec2f,world:vec3f,water:f32,mpp:f32) -> vec3f {
    let page=historic_surface_page(ll,mpp);
    if page.weight<=.001 || water>=.65 || all(base==vec3f(1.,0.,1.)) {
        return natural_relief(base,ll,world,water,mpp,0.);
    }
    let land=historic_surface_use(page,mpp);
    let park=park_layout(ll,mpp);
    let support=page.weight*(1.-smoothstep(.04,.65,water));
    // The surveyed park plan takes its area first. All other paints receive
    // disjoint shares of the dry ground; unclassified area keeps the QPK.
    let share=support*(1.-park.a)/max(1.,dot(land.built+land.open,vec3f(1.)));
    let built=land.built*share;
    let open=land.open*share;
    let surveyed_street=open.z*historic_street_weight(mpp,page.paris);
    var legacy_street=0.;
    var street_ground=0.;
    if surveyed_street>.001 {
        let fallback=road_raster_fraction(ll);
        legacy_street=surveyed_street*fallback;
        // A mineral bed belongs only to streets inside the adjoining
        // built fabric. Rural centrelines must leave no painted footprint.
        let fabric=historic_surface_use(page,max(32.,mpp));
        street_ground=surveyed_street*(1.-fallback)*smoothstep(.17,.48,fabric.built.x+fabric.built.y);
    }
    let street=legacy_street+street_ground;
    let unassigned=max(0.,1.-dot(built+vec3f(open.xy,street),vec3f(1.))-park.a*support);
    let garden=min(unassigned,land.garden*share);
    let natural=unassigned-garden;
    var color=vec3f(0.);
    let fringe=select(0.,1.-paris_core_weight(ll),page.paris);
    if natural>.001 {color=natural_relief(base,ll,world,water,mpp,fringe)*natural;}
    if park.a>.001 {color+=park_pigment(park,world,mpp)*support;}
    if garden>.001 {color+=market_garden(ll,world,mpp)*garden;}
    if built.x+built.y>.001 {
        let court=select(vec3f(.554,.523,.468),vec3f(.625,.610,.568),page.paris)
            *(1.+material_grain(world,mpp,SETTS,21.,10.)*.36);
        // Mesh roofs take over at street scale. Their footprint remains
        // urban ground even when the detailed roof is drawn in the model pass.
        let roof_detail=select(smoothstep(3.6,9.,mpp),smoothstep(5.,19.,mpp),page.paris);
        let roof=mix(court,city_roof(page.paris),roof_detail);
        // Outside mapped built blocks the street-scale model already
        // supplies the opaque roof. Do not enlarge it with a light patch
        // from the filtered ground texel.
        let surveyed_court=smoothstep(.06,.36,land.built.y);
        let near_roof=mix(1.,mix(surveyed_court,1.,smoothstep(4.,15.,mpp)),fringe);
        let lot=vec3f(.490,.522,.361)*(1.+material_grain(world,mpp,GRASS,23.,6.)*.36);
        color+=mix(lot,roof,near_roof)*built.x+court*built.y;
    }
    if built.z>.001 {
        let ballast=select(vec3f(.507,.475,.423),vec3f(.533,.521,.481),page.paris);
        let yard=ballast*(1.+material_grain(world,mpp,GRAVEL,34.,12.)*.5);
        color+=yard*built.z;
    }
    if open.x>.001 {
        let meadow=vec3f(.490,.522,.361)*(1.+material_grain(world,mpp,GRASS,23.,6.)*.36);
        color+=meadow*open.x;
    }
    if open.y>.001 {
        let crown=material_grain(world,mpp,WOODLAND,485.,97.);
        color+=woodland_ground(world,ll.y,0.,mpp,FOREST_GROUND*(1.+crown*.64))*open.y;
    }
    if street>.001 {
        let mineral=select(vec3f(.554,.523,.468),vec3f(.625,.610,.568),page.paris);
        let legacy=mix(city_road(page.paris,.2),vec3f(.682,.661,.615),smoothstep(6.,18.,mpp));
        color+=(mineral*street_ground+legacy*legacy_street)*(1.+material_grain(world,mpp,SETTS,9.,7.)*.39);
    }
    return color;
}

const LANDSCAPE_INSTANCES: u32 = 65536u;
const LANDSCAPE_VISIBLE: u32 = 1728u;
const LANDSCAPE_INSTANCE_FADE_SECONDS: f32 = 0.18;

struct LandscapeInstance {
    cell_x: u32,
    cell_y: u32,
    style: u32,    // longitude count, mesh kind, field-edge bearing, cover weight
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
@group(1) @binding(7) var<storage, read_write> landscape_draws: array<LandscapeDraw, 5>;
@group(1) @binding(8) var<storage, read_write> landscape_cache: array<LandscapeInstance>;

fn landscape_seed(cell: vec2u) -> u32 {
    return cell.x * 116831u + cell.y * 24571u;
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
    return 1.-smoothstep(12.,23.5,footprint);
}

fn landscape_local_index(id: vec3u, chunk: vec4u) -> u32 {
    return ((chunk.w & 0x7fffffffu) >> 6u)*256u + id.y*16u + id.x;
}

fn farm_ground(cover: LandCover) -> f32 {
    // Sparse settled patches inside cultivated country can support an
    // inferred farmyard. Unclassified land and continuous towns cannot.
    return smoothstep(.34,.52,cover.crop)*smoothstep(.065,.14,cover.urban)
        *(1.-smoothstep(.25,.37,cover.urban))*(1.-smoothstep(.13,.26,cover.forest));
}

struct LandscapeHabitat {
    wood: vec2f,
    unassigned: f32,
}

fn landscape_habitat(cover: LandCover, historic: HistoricSurfacePage) -> LandscapeHabitat {
    let wood = vec2f(cover.forest,cover.shrub);
    if historic.weight <= .001 { return LandscapeHabitat(wood,1.); }
    let land = historic_surface_use(historic,0.);
    let assigned = min(1.,dot(land.built+land.open,vec3f(1.))+land.garden);
    let unassigned = 1.-assigned*historic.weight;
    return LandscapeHabitat(wood*unassigned+vec2f(land.open.y*historic.weight,0.),unassigned);
}

fn verge_habitat(cover: LandCover, road: FieldRoad) -> f32 {
    let farmland = smoothstep(.39,.72,cover.crop+cover.grass)*smoothstep(.11,.29,cover.crop);
    let boundary = smoothstep(3.,10.,road.clearance)*(1.-smoothstep(12.,25.,road.clearance));
    return farmland*boundary*(1.-smoothstep(.08,.27,cover.urban))
        *(1.-smoothstep(.13,.39,cover.forest));
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
    let height = landscape_elevation(page,vec2f(0.));
    let slope = landscape_slope(page,ll.y,.83,7u);
    let cover = rural_cover(landscape_material(page,1.,1.,1.,false),length(slope),height,1.);
    let historic = historic_surface_page(ll,0.);
    let habitat = landscape_habitat(cover,historic);
    let closure = woodland_structure(landscape_world(ll));
    let wood = habitat.wood*vec2f(mix(.80,1.03,closure),mix(.31,.45,closure));
    let share = rock_share(cover,length(slope),height);
    let rock = (share.x+(cover.grass+cover.shrub)*share.y)*.78*habitat.unassigned;
    let seed = landscape_seed(cell);
    let choice = landscape_random(seed+1951u);
    let density = wood.x+wood.y+rock;
    var verge = 0.;
    var road = FieldRoad(26.,0.,0.,vec2f(0.));
    if choice>=density && cover.crop>.11 && cover.urban<.27 && length(slope)<.19 {
        road = field_road(ll,26.);
        verge = verge_habitat(cover,road)*habitat.unassigned;
    }
    let planted = verge*(.35+closure*.65) > .24;
    let farm = choice>=density && landscape_random(seed+3739u)<farm_ground(cover)*.22*habitat.unassigned
        && !planted && length(slope)<.17 && cover.regional>.5 && abs(ll.y)<65.;
    if choice >= density && !farm && !planted { return; }

    // Adjacent cells share a habitat. The stable site seed keeps some mixing
    // where both crown forms are plausible.
    let conifers = clamp(landscape_conifers(ll.y,height)+(closure-.5)*.36,0.,1.);
    let tree = select(0u,1u,landscape_random(seed+691u)<conifers);
    let species = select(select(2u,3u,choice<wood.x+wood.y),tree,choice<wood.x);
    let kind = select(select(species,3u,planted),4u,farm);
    var hedgerow = 0u;
    if planted {
        hedgerow = u32(round(fract(atan2(road.along.y,road.along.x)/PI)*7.))%7u+1u;
    } else if kind < 4u && kind != 2u && cover.regional > .5 && cover.crop > .22 && cover.forest < .65 {
        // Align planting at field margins with the reconstructed cover edge.
        let west = reconstructed_forest(page,vec2f(-.7,0.));
        let east = reconstructed_forest(page,vec2f(.7,0.));
        let south = reconstructed_forest(page,vec2f(0.,.7));
        let north = reconstructed_forest(page,vec2f(0.,-.7));
        let gradient = vec2f(east-west,north-south);
        if length(gradient) > .14 {
            let turns = atan2(gradient.x,-gradient.y)/PI;
            hedgerow = u32(round(fract(turns)*7.))%7u+1u;
        }
    }

    let packed_slope = vec2u(round(clamp(slope,-vec2f(1.),vec2f(1.))*127.+128.));
    let packed_height = u32(clamp(round(height)+32768.,0.,65535.));
    let packed_terrain = packed_height | (packed_slope.x<<16u) | (packed_slope.y<<24u);
    let shrub = max(habitat.wood.y,verge*select(0.,.80,planted));
    let local_cover = select(select(select(habitat.wood.x,shrub,kind==3u),rock,kind==2u),1.,farm);
    let strength = u32(round(clamp(local_cover,0.,1.)*127.));
    let packed_style = columns | (kind<<18u) | (hedgerow<<21u) | (strength<<24u);
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
    @location(4) @interpolate(flat) lod: f32,
    @location(5) @interpolate(flat) tree: u32,
    @location(6) ground_offset: f32,
    @location(7) @interpolate(flat) grade: f32,
};

@vertex
fn landscape_vertex(
    @location(0) offset: vec3f, @location(1) normal: vec3f, @location(2) tone: f32, @location(3) edge: f32,
    @location(4) crown: f32, @location(5) item: vec4u, @location(6) appeared: f32,
) -> LandscapeVertex {
    let columns = item.z & 262143u;
    let kind = (item.z>>18u)&7u;
    let hedgerow = (item.z>>21u)&7u;
    let density = f32((item.z>>24u)&127u)/127.;
    let mpp = view.viewport.z*EARTH;
    let tree = crown > 0.;
    let understory = crown == -1.;
    let grove = crown <= -2.;
    let trunk = tone < 0.;
    let stand = kind == 0u || kind == 1u || kind == 3u;
    let stand_mix = smoothstep(5.5,15.5,mpp);
    let core = smoothstep(.35,.86,density);
    let undergrowth = mix(core*.26,.28,stand_mix)*smoothstep(2.7,7.5,mpp);
    let structure = select(stand_mix*mix(.29,.48,core),undergrowth,understory);
    let arrival = smoothstep(0.,LANDSCAPE_INSTANCE_FADE_SECONDS,view.chart_east.w-appeared);
    let trunk_visibility = select(1.,1.-smoothstep(2.8,6.0,mpp),trunk);
    let farm = kind==4u;
    let farm_visibility = select(1.,1.-smoothstep(5.,10.,mpp),farm);
    let representation = select(1.,select(structure,1.-stand_mix,tree),stand)*arrival*trunk_visibility*farm_visibility;
    if representation <= .012 {
        return LandscapeVertex(vec4f(2.,2.,0.,1.),vec3f(0.),vec4f(0.),0.,kind,0.,0u,0.,0.);
    }
    let ll = landscape_coordinates(item.xy,columns);
    let height = f32(item.w&65535u)-32768.;
    let grade = (vec2f(f32((item.w>>16u)&255u),f32(item.w>>24u))-128.)/127.;
    let seed = landscape_seed(item.xy);
    let index = u32(max(crown-1.,0.));
    let grove_index = select(u32(max(-crown-2.,0.)),index/4u,tree);
    let variation = seed+u32(abs(crown))*8461u;
    let site_shape = landscape_random(seed+6371u);
    let site_hue = landscape_random(seed+8733u);
    let hue = landscape_random(variation+8733u);
    let shape = landscape_random(variation+6371u);
    let group_seed = seed+grove_index*2917u;
    let closure = landscape_random(group_seed+2183u);
    if (grove || tree) && closure>mix(.67,.98,core) && grove_index!=3u {
        return LandscapeVertex(vec4f(2.,2.,0.,1.),vec3f(0.),vec4f(0.),0.,kind,0.,0u,0.,0.);
    }
    var bearing = landscape_random(seed+3191u)*(2.*PI);
    var radius = mix(91.,154.,site_shape)*mix(.84,1.16,density);
    var form = vec3f(radius,radius*mix(.77,1.11,site_hue),mix(11.,24.,site_shape));
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
    } else if farm {
        form = vec3f(mix(11.,18.,shape),mix(10.,15.,shape),mix(4.7,7.8,hue));
        bearing = select(bearing,atan2(grade.y,grade.x)+PI*.5,length(grade)>.012);
    }
    if hedgerow != 0u {
        bearing = f32(hedgerow-1u)*PI/7.;
        form *= vec3f(select(vec2f(.83,.24),vec2f(.32,.095),kind==3u),1.);
    }
    if grove || tree {
        let anchors = array<vec2f,7>(vec2f(-.70,.14),vec2f(-.35,-.56),vec2f(-.37,.58),
            vec2f(.08,.17),vec2f(.50,-.48),vec2f(.66,.16),vec2f(.37,.62));
        let drift = vec2f(landscape_random(group_seed+613u),landscape_random(group_seed+1009u))-.5;
        tree_center = (anchors[grove_index]*(.64+.45*closure)+drift*.49)*form.xy;
        if grove {
            form *= vec3f(mix(.55,1.14,closure),mix(.59,1.25,shape),mix(.63,1.18,closure));
        }
    }
    if tree {
        let azimuth = (f32(index%4u)+landscape_random(group_seed+691u))*(PI*.5);
        let spread = mix(9.,31.,landscape_random(variation+399u))*form.x/124.;
        tree_center += vec2f(cos(azimuth),sin(azimuth)*select(1.,.42,hedgerow!=0u))*spread;
        let r = mix(3.8,14.4,shape)*mix(.75,1.16,closure);
        form = vec3f(r,r*mix(.68,1.16,hue),mix(7.5,27.,shape)*(1.+tropical*.17));
        if kind == 1u { form *= vec3f(.78,.78,1.17); }
        if kind == 3u { form *= vec3f(.52,.52,.29); }
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
    let bases = array<vec3f,5>(woodland_palette(0.),woodland_palette(1.),
        ROCK_GROUND,SHRUB_GROUND-vec3f(.065,.047,.037),vec3f(0.));
    let foliage = bases[kind]+vec3f(-.017,.008,-.010)*tropical*select(1.,0.,kind==2u);
    let pigment = vec3f(.086,.092,.061)*(hue-.5);
    let flat = rotate*(normal.xy/form.xy);
    let vertical = normal.z/form.z;
    let facing = normalize(vec3f(flat-ground_grade*vertical,vertical));
    let sunlight = max(0.,dot(facing,LANDSCAPE_SUN));
    let light = select(.85+.30*sunlight,.88+.26*sunlight,kind==2u);
    let canopy_light = select(vec3f(0.),vec3f(.012,.018,.009),tree);
    let bark = vec3f(.184,.154,.111)+vec3f(.047)*(hue-.5);
    var color = clamp(select((foliage+pigment+canopy_light)*mix(1.,tone,.70),bark,trunk)*light,
        vec3f(0.),vec3f(1.));
    if farm {
        let slate = field_region(ll,vec2f(-5.,54.),vec2f(13.,7.));
        let roof = mix(vec3f(.438,.334,.270),vec3f(.310,.342,.345),slate)+pigment;
        color = select(vec3f(.593,.542,.443)+pigment,roof,tone>.9)*light;
    }
    let flags = select(0u,1u,tree) | select(0u,2u,kind==3u && hedgerow!=0u);
    return LandscapeVertex(clip,vec3f(site,z),vec4f(color,visibility),edge,kind,lod,flags,ground_offset,length(grade));
}

fn landscape_object_mask(page: LandscapePage, historic: HistoricSurfacePage, input: LandscapeVertex,
        sample: u32, road: FieldRoad) -> f32 {
    var land = 1.;
    if water_weight(sample)<.999 {
        land = 1.-smoothstep(.10,.44,water_coverage(sample,landscape_coverage(page)));
    }
    let height = landscape_elevation(page,vec2f(0.));
    let clearance = input.site.z-height;
    let cover = rural_cover(landscape_material(page,1.,1.,1.,false),input.grade,height,1.);
    let habitat = landscape_habitat(cover,historic);
    if input.kind==4u {
        return land*habitat.unassigned*farm_ground(cover)*smoothstep(-4.,0.,clearance);
    }
    var vegetation = select(habitat.wood.x,habitat.wood.y,input.kind==3u);
    if (input.tree&2u)!=0u {
        vegetation = max(vegetation,verge_habitat(cover,road)*habitat.unassigned*.68);
    }
    let exposed = (cover.bare+cover.shrub+cover.grass)*habitat.unassigned;
    return land*smoothstep(-4.,0.,clearance)*select(vegetation,exposed,input.kind==2u);
}

@fragment
fn landscape_fragment(input: LandscapeVertex) -> @location(0) vec4f {
    let rim = fwidth(input.edge)*select(.59,.68,input.kind==2u);
    // A subpixel crown spans several short triangles. Keep the rim filter
    // inside those triangles; the vertex shader already filters projected area.
    let edge = smoothstep(0.,max(select(rim,min(rim,.55),(input.tree&1u)!=0u),.001),input.edge);
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
    let historic = historic_surface_page(input.site.xy,0.);
    let road = field_road(input.site.xy,select(12.,26.,(input.tree&2u)!=0u));
    let verge = smoothstep(.5,3.5,road.clearance);
    let strength = fine*input.lod*landscape_object_mask(page,historic,input,sample,road)*verge;
    if strength <= .001 { discard; }
    let modern = 1.-landscape_survey_mask(input.site.xy,mpp);
    var occupancy=park_coverage(input.site.xy,mpp).a;
    if historic.weight>.001 {
        let planned=park_layout(input.site.xy,mpp).a;
        occupancy=mix(occupancy,planned,historic.weight);
    }
    let opacity = input.color.a*edge*modern*strength*(1.-occupancy);
    if opacity <= .012 { discard; }
    return vec4f(input.color.rgb,opacity);
}
