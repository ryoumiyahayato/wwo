struct View {
    east: vec4f,
    north: vec4f,
    forward: vec4f,
    viewport: vec4f, // dimensions, radians / pixel, regional chart flag
    chart_east: vec4f,
    chart_north: vec4f,
    chart_forward: vec4f,
    chart_origin: vec4f,
    settings: vec4f, // seasonal day, mode, politics available, theme
    selection: vec4f, // polity number, land changes, administrative index, France index
    map_style: vec4f, // terrain catalogue zoom (y), selected terrain zoom (z), military grid step (w)
    edits: array<LandEdit, 12>,
    natural_lod: array<vec4f, 2>, // opacity indexed by Z, or -1 for per-page blending
    close_sample: vec4f,
};
struct LandEdit { area: vec4f, state: vec4f };
struct Tile {
    extent: vec4f,
    core: vec4f,
    region: vec4f,
    options: vec4f, // opacity, material facts, city facts, is world
    edges: vec4f,
    edge_ready: vec4f,
};
@group(0) @binding(0) var<uniform> view: View;
@group(0) @binding(1) var linear: sampler;
@group(0) @binding(2) var world_sampler: sampler;
@group(0) @binding(3) var palette: texture_2d<f32>;
@group(0) @binding(4) var layouts: texture_2d_array<f32>;
@group(0) @binding(5) var flags: texture_2d<f32>;
@group(0) @binding(6) var flag_poses: texture_2d<f32>;
@group(0) @binding(7) var galactic_chart: texture_2d<f32>;
@group(0) @binding(8) var ocean_detail: texture_2d<f32>;
@group(0) @binding(9) var ocean_ice: texture_2d<f32>;
@group(0) @binding(10) var terrain_world: texture_2d_array<f32>;
@group(0) @binding(11) var terrain_detail: texture_2d_array<f32>;
@group(0) @binding(12) var terrain_index: texture_2d<u32>;
@group(3) @binding(0) var land_surface: texture_2d<f32>;
@group(3) @binding(1) var land_repeat: sampler;
@group(3) @binding(2) var landscape_data: texture_2d_array<f32>;
@group(2) @binding(0) var close_surface: texture_2d<f32>;
@group(2) @binding(1) var<uniform> close_extent: vec4f;
@group(1) @binding(0) var<uniform> tile: Tile;
@group(1) @binding(1) var terrain_data: texture_2d<f32>;
@group(1) @binding(2) var material_data: texture_2d<f32>;
@group(1) @binding(3) var city_data: texture_2d<f32>;
@group(1) @binding(4) var owners: texture_2d<u32>;

const PI: f32 = 3.14159265358979;
const EARTH: f32 = 6371008.8;
const LAND_DETAIL_MPP: f32 = 760.;
const CHART_SUN_VIEW: vec3f = vec3f(.100,.970,.222);
@vertex fn triangle(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
    let p = array<vec2f,3>(vec2f(-1.,-1.),vec2f(3.,-1.),vec2f(-1.,3.));
    return vec4f(p[i],0.,1.);
}
fn hash(p: vec2f) -> f32 {
    let q=fract(vec3f(p.xyx)*0.1031);
    let d=q+dot(q,q.yzx+33.33);
    return fract((d.x+d.y)*d.z);
}
fn noise(p: vec2f) -> f32 {
    let i=floor(p);
    let f=fract(p);
    let u=f*f*(3.-2.*f);
    return mix(mix(hash(i),hash(i+vec2f(1.,0.)),u.x),
               mix(hash(i+vec2f(0.,1.)),hash(i+1.),u.x),u.y);
}
fn solar_ground(ink:vec3f, normal:vec3f)->vec3f {
    let incidence=dot(normal,CHART_SUN_VIEW);
    let day=smoothstep(-.16,.21,incidence);
    let fill=mix(vec3f(.33,.42,.54),vec3f(1.07,1.035,.985),day);
    return ink*fill*(1.+.26*max(incidence,0.));
}
fn chart_ocean(ll:vec2f,earth:vec3f,normal:vec3f)->vec3f {
    let uv=vec2f(ll.x/360.+.5,clamp(.5-ll.y/180.,.03125,.96875));
    let detail=textureSampleLevel(ocean_detail,world_sampler,uv,0.).b;
    let variation=clamp((detail-.28)*2.2,-.18,.18)*(1.-smoothstep(.86,.98,abs(earth.y)));
    var base=mix(vec3f(.12,.20,.23),vec3f(.055,.20,.29),.75)*(1.+variation);
    base+=vec3f(-.010,.012,.020)*variation;
    let polar=select(smoothstep(.91355,.97815,-earth.y)*.46,smoothstep(.95106,.99452,earth.y)*.82,earth.y>0.);
    let floe=textureSampleLevel(ocean_ice,world_sampler,fract(earth.xz*2.2+.5),0.).b;
    let ice=polar*mix(.93,1.,floe);
    base=mix(base,vec3f(.61,.73,.78),ice);
    let half_vector=normalize(CHART_SUN_VIEW+vec3f(0.,0.,1.));
    let incidence=max(dot(normal,CHART_SUN_VIEW),0.);
    let glint=pow(max(dot(normal,half_vector),0.),384.)*incidence*(1.-.85*ice);
    let grazing=1.-clamp(normal.z,0.,1.);
    let rim=pow(grazing,4.5)*mix(.25,1.,smoothstep(0.,.6,incidence));
    return solar_ground(base,normal)*mix(.94,1.06,grazing)+vec3f(.15,.19,.18)*glint
        +vec3f(.035,.080,.110)*rim*(1.-ice*.6);
}
fn moon_noise(p:vec2f)->f32 {
    var q=fract(p*vec2f(123.34,456.21));
    q+=dot(q,q+45.32);
    return fract(q.x*q.y);
}
fn moon_fbm(uv:vec2f)->f32 {
    var p=uv;
    var value=0.;
    var amplitude=.58;
    for (var i=0;i<4;i++) {
        let cell=floor(p);
        let f=fract(p);
        let u=f*f*(3.-2.*f);
        value+=mix(mix(moon_noise(cell),moon_noise(cell+vec2f(1.,0.)),u.x),
            mix(moon_noise(cell+vec2f(0.,1.)),moon_noise(cell+1.),u.x),u.y)*amplitude;
        p=p*2.07+vec2f(5.1,8.7);
        amplitude*=.46;
    }
    return value;
}
fn sky(p: vec2f) -> vec3f {
    let size=vec2f(textureDimensions(galactic_chart));
    let fit=max(view.viewport.x/size.x,view.viewport.y/size.y);
    let base=textureSampleLevel(galactic_chart,linear,(p-view.viewport.xy*.5)/(size*fit)+.5,0.).rgb;
    let radius=1./view.viewport.z;
    if radius>view.viewport.y*1.10/2.55 {return base;}
    let center=view.viewport.xy*.5+vec2f(1.18,-.53)*radius;
    let q=(p-center)/(.145*radius);
    let r=dot(q,q);
    if r>=1. { return base; }
    let n=vec3f(q.x,-q.y,sqrt(1.-r));
    let tilted=vec3f(n.x,.996802*n.y-.079915*n.z,.079915*n.y+.996802*n.z);
    let local=vec3f(.971338*tilted.x-.237703*tilted.z,tilted.y,.237703*tilted.x+.971338*tilted.z);
    let uv=vec2f(fract(atan2(local.x,local.z)/(2.*PI)+.5),acos(clamp(local.y,-1.,1.))/PI);
    let lit=smoothstep(-.18,.82,dot(n,CHART_SUN_VIEW));
    let limb=pow(1.-n.z,2.4);
    let broad=moon_fbm(uv*vec2f(8.,4.));
    let crater=smoothstep(.62,.84,moon_fbm(uv*vec2f(23.,11.)+vec2f(4.7,1.9)));
    let surface=mix(vec3f(.10,.13,.15),mix(vec3f(.54,.56,.54),vec3f(.78,.78,.70),lit),lit)
        *mix(.78,1.08,broad)*mix(1.,.64,crater*.42)+vec3f(.78,.78,.70)*limb*.045;
    return mix(surface*1.14,base,smoothstep(.97,1.,r));
}
fn raw(uv: vec2f) -> vec4f {
    if tile.options.w>.5 { return textureSampleLevel(terrain_data,world_sampler,uv,0.); }
    return textureSampleLevel(terrain_data,linear,uv,0.);
}
fn height(p: vec4f) -> f32 { return p.r*255.+p.g*65280.-32768.; }
fn ids(p: vec2i, size: vec2i) -> vec2u {
    var x=clamp(p.x,0,size.x-1);
    if tile.options.w>.5 {x=((p.x%size.x)+size.x)%size.x;}
    return textureLoad(owners,vec2i(x,clamp(p.y,0,size.y-1)),0).rg;
}
fn flag_weight(mpp: f32) -> f32 {
    if mpp <= 300. { return 0.; }
    let scale=log(mpp);
    if mpp <= 650. { return .18*smoothstep(log(300.),log(650.),scale); }
    if mpp <= 1200. { return mix(.18,.52,smoothstep(log(650.),log(1200.),scale)); }
    if mpp <= 3000. { return mix(.52,.92,smoothstep(log(1200.),log(3000.),scale)); }
    return mix(.92,1.,smoothstep(log(3000.),log(5500.),scale));
}
fn political_flag_uv(id: u32, ll: vec2f, regional:f32) -> vec2f {
    let row=i32(id);
    let rotation=textureLoad(flag_poses,vec2i(2,row),0);
    let bounds=textureLoad(flag_poses,vec2i(0,row),0);
    let transform=textureLoad(flag_poses,vec2i(1,row),0);
    let middle=(bounds.x+bounds.z)*.5;
    let lon=ll.x+360.*round((middle-ll.x)/360.);
    var uv=vec2f((lon-bounds.x)/max(bounds.z-bounds.x,.000001),
                 (bounds.w-ll.y)/max(bounds.w-bounds.y,.000001));
    var regional_uv=uv;
    if regional>0. {
        for (var i=0;i<i32(rotation.w);i++) {
            let frame=textureLoad(flag_poses,vec2i(3+i,row),0);
            let center=(frame.x+frame.z)*.5;
            let point=vec2f(ll.x+360.*round((center-ll.x)/360.),ll.y);
            if all(point>=frame.xy)&&all(point<=frame.zw) {
                regional_uv=vec2f((point.x-frame.x)/(frame.z-frame.x),(frame.w-point.y)/(frame.w-frame.y));
                break;
            }
        }
    }
    uv=(uv-.5)*transform.xy;
    let c=rotation.x;
    let s=rotation.y;
    let global_uv=vec2f(uv.x*c-uv.y*s,uv.x*s+uv.y*c)+.5+transform.zw;
    return mix(global_uv,regional_uv,regional);
}
fn political_flag(slot:u32, uv:vec2f) -> vec4f {
    if slot==0u { return vec4f(0.); }
    let size=vec2f(textureDimensions(flags));
    let span=size/16.;
    let cell=vec2f(f32(slot%16u),f32(slot/16u))*span;
    let sample_uv=(cell+vec2f(.5)+clamp(uv,vec2f(0.),vec2f(1.))*(span-1.))/size;
    return textureSampleLevel(flags,linear,sample_uv,0.);
}
fn natural_global(uv:vec2f) -> vec4f {
    let half=i32(floor(uv.x*2.));
    let local=vec2f(fract(uv.x*2.),uv.y);
    return textureSampleLevel(terrain_world,linear,(local*256.+4.)/264.,half,0.);
}
struct NaturalPage { color:vec4f, coverage:f32 }
fn page_readiness(cell:vec2i, columns:i32, rows:i32, shift:u32) -> f32 {
    let x=(cell.x+columns)%columns;
    let y=clamp(cell.y,0,rows-1)+rows-1;
    return f32((textureLoad(terrain_index,vec2i(x,y),0).r>>shift)&255u)/255.;
}
fn page_coverage(cell:vec2i, q:vec2f, rows:i32, shift:u32, fade:f32) -> f32 {
    if fade<=0. {return 0.;}
    // Colour and relief share the same fallback at edges and corners.
    let rim=min(q,1.-q);
    let collar=.04;
    if min(rim.x,rim.y)>=collar {return fade;}
    let dx=vec2i(select(-1,1,q.x>.5),0);
    let dy=vec2i(0,select(-1,1,q.y>.5));
    let edge_x=select(fade,min(fade,page_readiness(cell+dx,rows*2,rows,shift)),rim.x<collar);
    let edge_y=select(fade,min(fade,page_readiness(cell+dy,rows*2,rows,shift)),rim.y<collar);
    var corner=min(edge_x,edge_y);
    if max(rim.x,rim.y)<collar {
        corner=min(corner,page_readiness(cell+dx+dy,rows*2,rows,shift));
    }
    let t=smoothstep(vec2f(0.),vec2f(collar),rim);
    return mix(mix(corner,edge_y,t.x),mix(edge_x,fade,t.x),t.y);
}
fn page_surface(uv:vec2f, zoom:i32, exact:bool) -> NaturalPage {
    let rows=1i<<u32(zoom);
    let position=uv*vec2f(f32(rows*2),f32(rows));
    let cell=vec2i(position);
    let index=textureLoad(terrain_index,cell+vec2i(0,rows-1),0).r;
    let slot=i32(index&65535u)-1;
    if slot<0 {return NaturalPage(vec4f(0.),0.);}
    let q=fract(position);
    let fade=f32((index>>16u)&255u)/255.;
    if fade<=0. && !exact {return NaturalPage(vec4f(0.),0.);}
    let refined=textureSampleLevel(terrain_detail,linear,(q*256.+4.)/264.,slot,0.);
    if exact {return NaturalPage(refined,1.);}
    return NaturalPage(refined,page_coverage(cell,q,rows,16u,fade));
}
fn natural_surface(ll:vec2f) -> vec4f {
    // Keep a rounded-up longitude fraction inside the last column at the antimeridian.
    let u=min(fract(ll.x/360.+.5),.99999994);
    let uv=vec2f(u,clamp(.5-ll.y/180.,0.,.99999994));
    if view.chart_origin.w>.5 && view.map_style.z>0. {
        let page=page_surface(uv,i32(view.map_style.z),true);
        return mix(vec4f(1.,0.,1.,0.),page.color,page.coverage);
    }
    var color=vec4f(0.);
    var remaining=1.;
    for(var z=i32(view.map_style.z);z>0;z-=1) {
        let opacity=view.natural_lod[u32(z)/4u][u32(z)%4u];
        let grouped=opacity>=0.;
        if opacity==0. {continue;}
        let page=page_surface(uv,z,false);
        let weight=remaining*page.coverage*select(1.,opacity,grouped);
        color+=page.color*weight;
        remaining-=weight;
        if remaining<.0001 {return color;}
    }
    return color+natural_global(uv)*remaining;
}
fn land_material_band(earth:vec3f, planes:vec3f, footprint:f32, period:f32) -> vec4f {
    let world=earth*(EARTH/period);
    let p=world+sin(world.zxy*.19+vec3f(.4,1.7,2.8))*.46;
    let mip=log2(max(1.,footprint*f32(textureDimensions(land_surface).x)/period));
    return textureSampleLevel(land_surface,land_repeat,p.yz,mip)*planes.x
        +textureSampleLevel(land_surface,land_repeat,p.xz+vec2f(.21,.43),mip)*planes.y
        +textureSampleLevel(land_surface,land_repeat,p.xy+vec2f(.67,.29),mip)*planes.z;
}
fn land_chroma(rgb:vec3f) -> vec2f {
    return vec2f(rgb.g-rgb.r,rgb.r+rgb.g-2.*rgb.b)/max(.001,rgb.r+rgb.g+rgb.b);
}
fn land_palette_weight(chroma:vec2f, reference:vec3f, radius:f32) -> f32 {
    return 1.-smoothstep(.008,radius,distance(chroma,land_chroma(reference)));
}
fn natural_land_material(terrain:vec4f, earth:vec3f, footprint:f32) -> vec3f {
    let base=terrain.rgb;
    let land=1.-smoothstep(.02,.42,terrain.a);
    let brightest=max(base.r,max(base.g,base.b));
    let darkest=min(base.r,min(base.g,base.b));
    let snow=smoothstep(.58,.82,darkest)*(1.-smoothstep(.06,.17,brightest-darkest));
    if land*(1.-snow)<.001 || footprint>=LAND_DETAIL_MPP || all(base==vec3f(1.,0.,1.)) {return base;}

    // Use the baked palette as a cue for artistic motifs. Normalize away
    // multiplicative relief lighting before comparing Z6/Z7 or shaded slopes.
    let chroma=land_chroma(base);
    let woods=max(land_palette_weight(chroma,vec3f(.255,.41,.31),.106),
                  land_palette_weight(chroma,vec3f(.25,.41,.33),.106));
    let soil=max(land_palette_weight(chroma,vec3f(.61,.57,.36),.060),
                 .60*land_palette_weight(chroma,vec3f(.47,.53,.33),.100));
    let rock=land_palette_weight(chroma,vec3f(.51,.47,.41),.105);
    let sand=land_palette_weight(chroma,vec3f(.775,.632,.433),.051);
    let motifs=vec4f(woods,soil,rock,sand);
    let materials=motifs/max(1.,dot(motifs,vec4f(1.)));

    let facing=abs(earth)*abs(earth);
    let planes=facing*facing/dot(facing,facing);
    let broad=land_material_band(earth,planes,footprint,14500.)-.5;
    // Broad forest and sand grain stays weaker than exposed rock. The baked
    // geographic albedo and shading remain legible on flat, uniform surfaces.
    var relief=dot(broad,materials*vec4f(.16,.18,.33,.17))*(1.-smoothstep(210.,LAND_DETAIL_MPP,footprint));
    if footprint<102. {
        let fine=land_material_band(earth,planes,footprint,2900.)-.5;
        relief+=dot(fine,materials*vec4f(.13,.12,.20,.12))*(1.-smoothstep(38.,102.,footprint));
    }
    return clamp(base*(1.+relief*land*(1.-snow)),vec3f(0.),vec3f(1.));
}

fn close_terrain(ll:vec2f,footprint:f32,base:vec4f) -> vec4f {
    let weight=view.close_sample.x;
    if weight<=0. || all(base.rgb==vec3f(1.,0.,1.)) {return base;}
    let span=close_extent.zw-close_extent.xy;
    let middle=(close_extent.x+close_extent.z)*.5;
    let delta=ll.x-middle;
    let lon=middle+delta-360.*floor((delta+180.)/360.);
    let uv=vec2f(lon-close_extent.x,close_extent.w-ll.y)/span;
    let streamed=view.close_sample.y>.5;
    let survey=view.close_sample.z>.5;
    let distance=min(uv,1.-uv);
    if streamed && min(distance.x,distance.y)<=0. {return base;}
    let latitude_scale=cos(radians((close_extent.y+close_extent.w)*.5));
    let span_metres=span*111195.*vec2f(latitude_scale,1.);
    let source_spacing=span_metres/vec2f(textureDimensions(close_surface));
    let lod=log2(max(1.,footprint/min(source_spacing.x,source_spacing.y)));
    let sample=textureSampleLevel(close_surface,linear,uv,lod);
    if survey {
        // RGB stores surveyed water, forest and cropland area, premultiplied
        // by the valid survey coverage. Outside the mapped area use the QPK.
        let surveyed=clamp((sample.a-.02)/.98,0.,1.);
        let fractions=clamp(sample.rgb/max(sample.a,.02),vec3f(0.),vec3f(1.));
        let occupied=fractions/max(1.,dot(fractions,vec3f(1.)));
        let other=max(0.,1.-dot(occupied,vec3f(1.)));
        let surface=other*vec3f(.43,.51,.33)
            +occupied.r*vec3f(.20,.38,.45)
            +occupied.g*vec3f(.255,.41,.31)
            +occupied.b*vec3f(.57,.54,.36);
        // Give explicitly cropped packages a short edge fade too. The survey
        // raster already feathers the actual mapped boundary in metres.
        let edge=distance*span_metres;
        let crop=smoothstep(0.,400.,min(edge.x,edge.y));
        return mix(base,vec4f(surface,occupied.r),surveyed*weight*crop);
    }
    if streamed {
        // Keep the global albedo and the authoritative water coverage. The
        // native-source residual adds only local contrast inside valid land.
        let reference=textureSampleLevel(close_surface,linear,uv,3.);
        let land=1.-smoothstep(.02,.50,max(max(base.a,sample.a),reference.a));
        let detail=clamp(sample.rgb-reference.rgb,vec3f(-.13),vec3f(.13));
        let coverage=smoothstep(0.,.14,distance.x)*smoothstep(0.,.14,distance.y);
        return vec4f(clamp(base.rgb+detail*(weight*coverage*land),vec3f(0.),vec3f(1.)),base.a);
    }
    return mix(base,sample,weight);
}

fn natural_water_color(color:vec3f, world:vec3f, depth:f32, coverage:f32, mpp:f32) -> vec3f {
    if coverage <= .04 || mpp > 18000. { return color; }
    let ice = smoothstep(.47,.68,min(color.r,color.g));
    let surface = smoothstep(.28,.88,coverage)*(1.-ice)*(1.-smoothstep(6400.,18000.,mpp));
    let shelf = smoothstep(2.,22.,depth)*(1.-smoothstep(80.,640.,depth));
    let off_shore = smoothstep(105.,2400.,depth);
    // Relief controls the marine shelf. Inland water retains the mapped basin color.
    let p = world*(EARTH/530.);
    let bend = sin(dot(p,vec3f(.13,-.41,.25))) + sin(dot(p,vec3f(-.32,.12,.17)));
    let swell = sin(dot(p,vec3f(.91,.61,-.73))+3.6*bend)*.33
        + sin(dot(p,vec3f(-.18,.67,.48))-3.1*bend)*.27;
    let wave = swell*(1.-smoothstep(160.,630.,mpp));
    let inland = vec3f(.010,.019,.023)*wave;
    let marine = vec3f(.018,.062,.059)*shelf+vec3f(.010,.019,.026)*wave;
    return clamp(color+mix(inland,marine,max(shelf,off_shore))*surface,vec3f(0.),vec3f(1.));
}

fn shade_map(ll:vec2f, uv:vec2f, normal_world:vec3f, normal_view:vec3f) -> vec3f {
    let dims=vec2f(textureDimensions(terrain_data));
    let du=1./dims;
    let data=raw(uv);
    let z=height(data);
    let lat=radians(ll.y);
    let metres=(tile.extent.zw-tile.extent.xy)*111195.*vec2f(max(.035,cos(lat)),1.);
    let dx=max(1.,metres.x*du.x);
    let dy=max(1.,metres.y*du.y);
    let base_mpp=view.viewport.z*EARTH;
    let use_natural=view.map_style.y>.5;
    var grad=vec2f(0.);
    if !use_natural {
        grad=vec2f(
            height(raw(uv+vec2f(du.x,0.)))-height(raw(uv-vec2f(du.x,0.))),
            height(raw(uv+vec2f(0.,du.y)))-height(raw(uv-vec2f(0.,du.y)))
        )/(2.*vec2f(dx,dy));
    }
    let slope=length(grad);
    let south=select(0.,182.5,ll.y<0.);
    let day=(view.settings.x+south)%365.;
    let cold=.5+.5*cos((day-24.)*.0172142);
    let warm=1.-cold;
    let season_strength=smoothstep(13.,42.,abs(ll.y));
    let lag=max(z,0.)*.015+(abs(ll.y)-46.)*2.7;
    let leaves=smoothstep(79.,127.,day-lag);
    let fall=smoothstep(260.,308.,day+lag*.56);
    let dormant=max(1.-leaves,smoothstep(301.,338.,day+lag*.4));
    let green=mix(vec3f(.55,.64,.39),vec3f(.39,.53,.32),warm);
    let broad=mix(green,mix(vec3f(.65,.46,.26),vec3f(.48,.43,.33),dormant),max(fall,dormant)*season_strength);
    let pine=mix(vec3f(.31,.43,.36),vec3f(.35,.50,.36),warm);
    let crop=mix(vec3f(.66,.64,.48),vec3f(.76,.70,.50),warm);
    let meadow=vec3f(.61,.66,.47);
    let rock=mix(vec3f(.53,.54,.51),vec3f(.78,.74,.65),clamp(z/3900.,0.,1.));
    let log_height=log(1.+max(z,0.)/400.)/log(16.);
    var color=mix(mix(vec3f(.41,.45,.37),vec3f(.50,.48,.40),smoothstep(.08,.60,log_height)),
        vec3f(.60,.57,.50),smoothstep(.60,.98,log_height));
    var terrain=vec4f(0.);
    var forest=0.;
    var urban=0.;
    let has_cover=tile.options.y==1.;
    if has_cover && (!use_natural || view.selection.y>0.) {
        let cover_uv=uv;
        let footprint=du*clamp(base_mpp/min(dx,dy),0.,4.)*.45;
        let v=textureSampleLevel(material_data,linear,cover_uv,0.)*.40
            +(textureSampleLevel(material_data,linear,cover_uv+footprint,0.)+textureSampleLevel(material_data,linear,cover_uv-footprint,0.)
            +textureSampleLevel(material_data,linear,cover_uv+vec2f(footprint.x,-footprint.y),0.)
            +textureSampleLevel(material_data,linear,cover_uv+vec2f(-footprint.x,footprint.y),0.))*.15;
        forest=v.x;
        urban=v.z;
        let bare=(1.-smoothstep(.01,.12,v.x))*v.w;
        color=meadow*max(0.,1.-v.x-v.y-v.z)+mix(pine,broad,clamp(.35+v.w*.65,0.,1.))*v.x+
               crop*v.y+vec3f(.74,.65,.60)*v.z;
        color=mix(color,rock,bare*.75);
        color=mix(color,rock,smoothstep(.31,1.38,slope)*.48*(1.-urban));
    }
    let southward=grad.y/max(.13,slope);
    let snowline=mix(4150.,850.,cold*season_strength)-max(0.,abs(ll.y)-44.)*74.;
    let snow=smoothstep(snowline-190.,snowline+320.,z-160.*southward)*(1.-.53*forest);
    if !use_natural && has_cover {
        color=mix(color,vec3f(.90,.94,.93),snow*.91);
    }else if ll.y< -60. {
        color=mix(color,mix(vec3f(.70,.78,.81),vec3f(.84,.88,.89),smoothstep(.04,.82,log_height)),.80);
    }
    let sun=normalize(vec3f(-.69,-.72,1.));
    let normal=normalize(vec3f(-grad*1.5,1.));
    var relief_light=clamp(.92+.58*(dot(normal,sun)-sun.z),.48,1.12);
    color *= relief_light;
    if use_natural {
        terrain=natural_surface(ll);
        color=terrain.rgb;
        if view.settings.y<.5 && view.map_style.z>=6. && base_mpp<LAND_DETAIL_MPP {
            let foreshortening=mix(max(.25,dot(normal_world,view.chart_forward.xyz)),1.,view.viewport.w);
            let detail_footprint=base_mpp/(foreshortening*max(.3,view.chart_origin.z));
            terrain=close_terrain(ll,detail_footprint,terrain);
            color=terrain.rgb;
        }
        color=landscape_relief(color,ll,normal_world,terrain.a,base_mpp);
        if view.chart_origin.w <= .5 {
            color=natural_water_color(color,normal_world,max(0.,-z)*data.a,terrain.a,base_mpp);
        }
        relief_light=clamp(.57+dot(terrain.rgb,vec3f(.30,.55,.15))*.68,.70,1.19);
    } else if tile.options.y>=5. {
        let level = log2(max(1.,base_mpp/min(dx,dy)));
        let source = textureSampleLevel(material_data,linear,uv,level);
        let encoding = tile.options.y-5.;
        var coverage = source.a;
        var observed = source.rgb;
        var form = 1.;
        if encoding>=6. {
            coverage = smoothstep(.01,.075,source.a);
            form = source.a/.57;
        } else if encoding<5. {
            coverage = smoothstep(.01,.075,source.a);
            form = .4+source.a;
            observed *= form;
        }
        let relief = mix(1.,form,.78);
        color = mix(color,mix(vec3f(.60,.588,.512)*relief,observed,.75),coverage);
        relief_light = mix(relief_light,relief,coverage);
    } else if tile.options.y>1.5 {
        let print=textureSampleLevel(material_data,linear,uv,0.);
        if tile.options.y>2.5 {
            let form=mix(1.,print.a/.57,.78);
            let coverage=smoothstep(.01,.075,print.a);
            color=mix(color,mix(vec3f(.60,.588,.512)*form,print.rgb,.75),coverage);
            relief_light=mix(relief_light,form,coverage);
        }else{
            color=mix(color,mix(vec3f(.60,.588,.512),print.rgb,.75),print.a);
        }
    }
    if has_cover && base_mpp<150. && (!use_natural || view.selection.y>0.) {
        let m=ll*111195.*vec2f(cos(lat),1.);
        let detail=(noise(m/43.)-.5)*(1.-smoothstep(9.,43.,base_mpp));
        let grain=(noise(m/239.)-.5)*.022+detail*.039;
        if !use_natural {color+=grain;}
        for (var i=0u;i<u32(view.selection.y);i++) {
            let edit=view.edits[i];
            let d=(ll-edit.area.xy)*111195.*vec2f(cos(lat),1.)/edit.area.zw;
            if length(d)>1.22 { continue; }
            let a=(1.-smoothstep(.68,1.06,length(d)+.17*(noise(m/160.)-.5)))*forest;
            var ground=mix(vec3f(.63,.53,.43),vec3f(.73,.65,.53),noise(m/171.));
            if edit.state.x>1.5 { ground=mix(ground,vec3f(.72,.66,.57),.48); }
            if edit.state.y>0. {
                let scenario_ink=textureSampleLevel(layouts,linear,d/2.4+.5,i32(edit.state.y)-1,0.);
                let fade=1.-smoothstep(23.,62.,base_mpp);
                let source=max(scenario_ink.x,scenario_ink.y);
                if edit.state.x>1.5 {
                    ground=mix(ground,vec3f(.83,.79,.68),scenario_ink.z*fade*(1.-source));
                    ground=mix(ground,vec3f(.49,.35,.29),scenario_ink.w*fade*(1.-source));
                }
                ground=mix(ground,vec3f(.77,.74,.64),scenario_ink.x*fade);
                ground=mix(ground,vec3f(.54,.49,.43),scenario_ink.y*fade);
            }
            color=mix(color,ground,a);
        }
    }
    var bridges=0.;
    if tile.options.z>.5 {
        let buildings=textureSampleLevel(city_data,linear,uv,0.).rg;
        let detail=1.-smoothstep(16.,66.,base_mpp);
        let edge=textureSampleLevel(city_data,linear,uv-vec2f(du.x,du.y)*.82,0.).r;
        let shadow=max(0.,edge-buildings.r)*detail;
        color=mix(color,vec3f(.36,.32,.31),shadow*.49);
        color=mix(color,vec3f(.82,.76,.67),buildings.y*detail*.88);
        color=mix(color,mix(vec3f(.68,.56,.48),vec3f(.80,.71,.62),max(0.,buildings.r-edge)),buildings.r*detail*.91);
        bridges=buildings.y*detail;
    }
    if view.settings.w>.5 {
        let l=dot(color,vec3f(.30,.55,.15));
        let warm_form=select(smoothstep(150.,3350.,z),smoothstep(.43,.76,l),use_natural);
        color=mix(color,vec3f(l)*mix(vec3f(.85,.98,.90),vec3f(1.17,1.05,.91),warm_form),.68);
    }
    let regional=clamp(view.viewport.w,0.,1.);
    let lighting=1.-regional;
    color=mix(color,solar_ground(color,normal_view),lighting);
    let lit_terrain=color;
    if view.settings.y>.5 && view.settings.y<2.5 {
        let dims_id=vec2i(textureDimensions(owners));
        let at=vec2i(floor(uv*vec2f(dims_id)));
        let id=ids(at,dims_id);
        let datum=textureLoad(palette,vec2i(i32(id.x),i32(view.settings.y)-1),0);
        let ink=mix(vec3f(.58,.58,.52),datum.rgb,datum.a*view.settings.z);
        if view.settings.y<1.5 {
            let print_weight=mix(.12,.68,smoothstep(log(300.),log(6500.),log(max(base_mpp,1.))))
                *smoothstep(150.,450.,base_mpp);
            let fill=mix(.86,print_weight,regional)*select(0.,1.,id.x!=0u&&datum.a>0.);
            let rotation=textureLoad(flag_poses,vec2i(2,i32(id.x)),0);
            let emphasis=select(.18,1.,id.x==u32(view.map_style.x));
            let ink_form=mix(mix(1.,relief_light,.22),relief_light,regional);
            let ink_value=dot(ink,vec3f(.2126,.7152,.0722));
            let region_ink=mix(vec3f(ink_value),ink,mix(.26,.67,emphasis))*mix(.86,1.04,emphasis);
            color=mix(color,mix(ink,region_ink,regional)*ink_form,fill);
            if base_mpp>300. && view.settings.z>.5 && datum.a>0. {
                let flag_uv=political_flag_uv(id.x,ll,regional);
                let flag=political_flag(u32(rotation.z),flag_uv);
                let frame=textureLoad(flag_poses,vec2i(0,i32(id.x)),0);
                let span=min((frame.z-frame.x)*111195.*max(.035,cos(lat)),(frame.w-frame.y)*111195.)/base_mpp;
                let print_strength=mix(.62,.82,smoothstep(.60,.96,emphasis))
                    *smoothstep(12.,48.,span)*mix(1.,.68,smoothstep(120.,340.,span));
                let weight=mix(1.,flag_weight(base_mpp)*print_strength,regional)*flag.a*datum.a;
                let regional_tone=mix(vec3f(dot(flag.rgb,vec3f(.2126,.7152,.0722))),flag.rgb,mix(.76,.94,emphasis));
                let peak=max(regional_tone.r,max(regional_tone.g,regional_tone.b));
                let regional_print=regional_tone*(mix(.84,.98,emphasis)/(1.+.25*peak));
                color=mix(color,mix(flag.rgb,regional_print,regional)*ink_form,weight);
            }
            if id.x!=0u && datum.a>0. {
                let luminance=dot(color,vec3f(.2126,.7152,.0722));
                color=mix(color,vec3f(1.),max(.18-luminance,0.)/max(1.-luminance,.0001));
            }
        } else {
            let economic_weight=.92*smoothstep(log(250.),log(1200.),log(max(base_mpp,1.)));
            color=mix(color,ink,economic_weight*select(0.,1.,id.x!=0u&&view.settings.z>.5));
        }
        if view.settings.z>.5 {
            let x=ids(at+vec2i(1,0),dims_id);
            let y=ids(at+vec2i(0,1),dims_id);
            let l=ids(at-vec2i(1,0),dims_id);
            let b=ids(at-vec2i(0,1),dims_id);
            let national=(x.x!=id.x || y.x!=id.x || l.x!=id.x || b.x!=id.x) && id.x!=0u;
            let admin=(x.y!=id.y || y.y!=id.y || l.y!=id.y || b.y!=id.y) && id.y!=0u;
            if national || (admin && view.selection.z==0. && view.settings.y<1.5 && base_mpp<2400.) {
                let linewidth=clamp(base_mpp/max(dx,dy),.035,1.);
                let boundary=mix(vec3f(.22,.25,.22),vec3f(.71,.71,.62),regional);
                color=mix(color,boundary,linewidth*select(.34,.74,national));
            }
            if id.x!=0u && id.x==u32(view.selection.x) {
                color=mix(color,vec3f(1.,.78,.31),select(.24,.87,national));
            }
        }
    }
    if use_natural {
        color=mix(color,lit_terrain,terrain.a);
        color=mix(color,vec3f(.69,.67,.59),bridges*terrain.a*.82);
    } else {
        let sea=mix(chart_ocean(ll,normal_world,normal_view),vec3f(.12,.20,.23),regional);
        let lake=mix(vec3f(.23,.46,.54),solar_ground(vec3f(.23,.46,.54),normal_view),lighting);
        let water=mix(lake,sea,data.a);
        color=mix(color,water,data.b);
        color=mix(color,vec3f(.69,.67,.59),bridges*data.b*.82);
    }
    if view.settings.y>2.5 && view.map_style.w>0. {
        // R68's Lambert-93 origin and 50/25 km spacing. This is a display grid;
        // its France mask does not claim the original topology's cell membership.
        let phi=radians(clamp(ll.y,-85.,85.));
        let e=.08181919*sin(phi);
        let ts=tan(PI*.25-phi*.5)/pow((1.-e)/(1.+e),.040909595);
        let rho=11754255.426*pow(ts,.725607765);
        let theta=.725607765*radians(ll.x-3.);
        let cell=(vec2f(52000.,-262000.)+vec2f(rho*sin(theta),6055612.05-rho*cos(theta)))/view.map_style.w;
        let pixel_span=max(fwidth(cell),vec2f(.00001));
        let gap=abs(fract(cell+vec2f(.5))-.5)/pixel_span;
        let stroke=(1.-smoothstep(.22,.95,min(gap.x,gap.y)))*(1.-smoothstep(2200.,5000.,base_mpp));
        let grid_dims=vec2i(textureDimensions(owners));
        let grid_id=ids(vec2i(floor(uv*vec2f(grid_dims))),grid_dims);
        if view.settings.z>.5 && grid_id.x!=0u && grid_id.x==u32(view.selection.w) && ll.y>41. && ll.y<52. {
            color=mix(color,vec3f(.72,.81,.63),stroke*(1.-data.b)*.65);
        }
    }
    return color;
}
// Geographic city pages carry feature coverage. Let the QPK pass own the
// continuous ground so loading a local page only reveals buildings and bridges.
fn geographic_city_ink(ll:vec2f,uv:vec2f,mpp:f32,edge_distance:f32) -> vec4f {
    let detail=1.-smoothstep(16.,66.,mpp);
    if detail<=0. {return vec4f(0.);}
    let du=1./vec2f(textureDimensions(city_data));
    let pixel_metres=(tile.extent.zw-tile.extent.xy)*du*111195.*vec2f(max(.08,cos(radians(ll.y))),1.);
    let mip=max(0.,log2(mpp/max(1.,min(pixel_metres.x,pixel_metres.y))));
    let buildings=textureSampleLevel(city_data,linear,uv,mip).rg;
    let edge=textureSampleLevel(city_data,linear,uv-du*.82,mip).r;
    let shadow=max(0.,edge-buildings.r)*detail*.49;
    if max(max(buildings.r,buildings.g),shadow)<=.001 {return vec4f(0.);}
    var terrain=natural_surface(ll);
    if view.map_style.z>=6. {
        terrain=close_terrain(ll,mpp/max(.3,view.chart_origin.z),terrain);
    }
    // The source masks supply the footprints. Land cover controls their contrast.
    var cover=vec2f(0.);
    var ready=0.;
    let fine=landscape_page(ll,7u,true);
    let fine_weight=landscape_surface_weight(7u)*fine.fade;
    if fine_weight<.999 {
        let regional=landscape_page(ll,6u,true);
        let weight=landscape_surface_weight(6u)*regional.fade;
        if weight>.001 {
            let surface=landscape_material(regional);
            cover=vec2f(surface.urban,surface.forest+surface.shrub*.55)*weight;
            ready=weight;
        }
    }
    if fine_weight>.001 {
        let surface=landscape_material(fine);
        cover=mix(cover,vec2f(surface.urban,surface.forest+surface.shrub*.55),fine_weight);
        ready=mix(ready,1.,fine_weight);
    }
    let land=1.-terrain.a;
    let urban=clamp(cover.x/max(.01,ready),0.,1.);
    let woods=clamp(cover.y/max(.01,ready),0.,1.);
    let blocks=textureSampleLevel(city_data,linear,uv,3.).r;
    let built=urban*smoothstep(.02,.23,blocks);
    // At the survey limit, attenuate the mapped features over a few source blocks.
    let support=smoothstep(0.,mix(320.,670.,built),edge_distance);
    let facade=mix(vec3f(.68,.56,.48),vec3f(.80,.71,.62),max(0.,buildings.r-edge));
    let wall=buildings.r*detail*mix(.70,.91,built)*land;
    let road_color=mix(mix(terrain.rgb,vec3f(.69,.64,.54),.42),vec3f(.81,.75,.65),built);
    let road=buildings.g*detail*mix(mix(.58,.27,woods),.88,built);
    let bridge=mix(road,buildings.g*detail*.82,terrain.a);
    let shading=shadow*land*mix(.45,1.,built);
    let color=(vec3f(.36,.32,.31)*shading*(1.-wall)+facade*wall)*(1.-bridge)
        +mix(road_color,vec3f(.69,.67,.59),terrain.a)*bridge;
    let alpha=(shading*(1.-wall)+wall)*(1.-bridge)+bridge;
    let base_ready=select(1.,ready,textureNumLayers(landscape_data)>1u);
    return vec4f(color/max(.0001,alpha),alpha*support*base_ready);
}

fn chart_normal(xy:vec2f,r:f32,t:f32) -> vec3f {
    let a=select(asin(min(r,1.)),r,t>0.);
    let k=select(1.,sin(a)/max(r,.00000001),r>.00000001);
    return normalize(view.chart_east.xyz*(xy.x*k)+view.chart_north.xyz*(xy.y*k)+view.chart_forward.xyz*cos(a));
}

struct RiverStroke {
    @builtin(position) clip:vec4f,
    @location(0) ink:vec4f,
    @location(1) side:f32,
}

@vertex fn river_stroke(@location(0) pixel:vec2f,@location(1) ink:vec4f,@location(2) uv:vec2f) -> RiverStroke {
    let clip=pixel/view.viewport.xy*vec2f(2.,-2.)+vec2f(-1.,1.);
    return RiverStroke(vec4f(clip,0.,1.),ink,uv.x);
}

@fragment fn river_ink(stroke:RiverStroke) -> @location(0) vec4f {
    let xy=(stroke.clip.xy-view.chart_origin.xy)*view.viewport.z*vec2f(1.,-1./view.chart_origin.z);
    let r=length(xy);
    if r>=1.+view.viewport.w*(PI*.5-1.) {discard;}
    let v=chart_normal(xy,r,view.viewport.w);
    let ll=degrees(vec2f(atan2(v.x,v.z),atan2(v.y,length(v.xz))));
    let water=natural_surface(ll).a;
    var surveyed=0.;
    if view.close_sample.z>.5 {
        let mpp=view.viewport.z*EARTH/max(.3,view.chart_origin.z);
        // A negative sentinel lets the same survey coverage mask protect
        // surveyed ground and water while using only its valid footprint.
        surveyed=clamp(1.+close_terrain(ll,mpp,vec4f(0.,0.,0.,-1.)).a,0.,1.);
    }
    let alpha=stroke.ink.a*(1.-smoothstep(.20,.95,abs(stroke.side)))
        *(1.-smoothstep(.14,.57,water))*(1.-surveyed);
    return vec4f(stroke.ink.rgb,alpha);
}

@fragment fn map(@builtin(position) p:vec4f) -> @location(0) vec4f {
    let t=view.viewport.w;
    let xy=(p.xy-view.chart_origin.xy)*view.viewport.z*vec2f(1.,-1./view.chart_origin.z);
    let r=length(xy);
    let horizon=1.+t*(PI*.5-1.);
    let is_world=tile.options.w>.5;
    if r>=horizon {
        if !is_world {discard;}
        return vec4f(sky(p.xy),1.);
    }
    if !is_world && view.map_style.y>.5 && (view.settings.y<.5 || view.settings.y>2.5 && view.map_style.w<=0.) && tile.options.z<.5 && view.selection.y<.5 {discard;}
    let v=chart_normal(xy,r,t);
    let ll=degrees(vec2f(atan2(v.x,v.z),atan2(v.y,length(v.xz))));
    if !is_world && (ll.x<tile.core.x || ll.y<tile.core.y || ll.x>=tile.core.z || ll.y>=tile.core.w) {discard;}
    let uv=vec2f((ll.x-tile.extent.x)/(tile.extent.z-tile.extent.x),
                 (tile.extent.w-ll.y)/(tile.extent.w-tile.extent.y));
    let normal_view=vec3f(dot(v,view.east.xyz),dot(v,view.north.xyz),dot(v,view.forward.xyz));
    let edge_distance=min(min(ll.x-tile.region.x,tile.region.z-ll.x)*max(.08,cos(radians(ll.y))),
                          min(ll.y-tile.region.y,tile.region.w-ll.y))*111195.;
    let blend=select(smoothstep(0.,max(select(1400.,2400.,tile.options.z>.5),view.viewport.z*EARTH*30.),edge_distance),1.,is_world);
    let rim=vec4f(ll-tile.core.xy,tile.core.zw-ll);
    let edge_fade=smoothstep(vec4f(0.),max(tile.edges,vec4f(.00001)),rim);
    let feather=select(vec4f(1.),mix(tile.edge_ready,vec4f(1.),edge_fade),tile.edges>vec4f(0.));
    let coverage=feather.x*feather.y*feather.z*feather.w;
    if tile.options.z>.5 && view.map_style.y>.5 && view.settings.y<.5 && view.selection.y<.5 {
        if view.viewport.z*EARTH>=66. {discard;}
        let ink=geographic_city_ink(ll,uv,view.viewport.z*EARTH,edge_distance);
        return vec4f(ink.rgb,ink.a*tile.options.x*coverage);
    }
    var color=shade_map(ll,uv,v,normal_view);
    if is_world {
        let edge=1.-smoothstep(0.,view.viewport.z*1.2,horizon-r);
        color=mix(color,sky(p.xy),edge*.47);
    }
    let page_blend=select(blend,coverage,tile.options.y>=5.);
    return vec4f(color,tile.options.x*page_blend);
}
