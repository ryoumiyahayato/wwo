struct View {
    east: vec4f,
    north: vec4f,
    forward: vec4f,
    viewport: vec4f, // dimensions, radians / pixel, regional chart flag
    chart_east: vec4f, // axis and elapsed real seconds
    chart_north: vec4f,
    chart_forward: vec4f,
    chart_origin: vec4f,
    settings: vec4f, // seasonal day, mode, politics available, theme
    selection: vec4f, // polity number, land changes, administrative index, France index
    map_style: vec4f, // terrain catalogue zoom (y), selected terrain zoom (z), military grid step (w)
    edits: array<LandEdit, 12>,
    natural_lod: array<vec4f, 2>, // opacity indexed by Z, or -1 for per-page blending
    close_sample: vec3f, // detail weight, streamed, historical survey
    water_clock: u32,
    military_cell: vec4f, // easting index, northing index, step metres, active
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
@group(0) @binding(3) var<uniform> palette: array<vec4u,128>;
@group(0) @binding(4) var layouts: texture_2d_array<f32>;
@group(0) @binding(5) var flags: texture_2d<f32>;
@group(0) @binding(6) var flag_poses: texture_2d<f32>;
@group(0) @binding(7) var galactic_chart: texture_2d<f32>;
@group(0) @binding(8) var ocean_material: texture_2d<f32>;
@group(0) @binding(10) var terrain_world: texture_2d_array<f32>;
@group(0) @binding(11) var terrain_detail: texture_2d_array<f32>;
@group(0) @binding(12) var terrain_index: texture_2d<u32>;
@group(3) @binding(0) var land_surface: texture_2d<f32>;
@group(3) @binding(1) var land_repeat: sampler;
@group(3) @binding(2) var landscape_data: texture_2d_array<f32>;
@group(3) @binding(3) var<storage,read> water_geometry: array<u32>;
@group(3) @binding(4) var<storage,read> water_pixels: array<u32>;
@group(3) @binding(5) var<storage,read_write> water_output: array<u32>;
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
const LAND_MATERIAL_MPP: f32 = 2220.;
const CITY_INK_MPP: f32 = 180.;
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
    let detail=textureSampleLevel(ocean_material,world_sampler,uv,0.).r;
    let variation=clamp((detail-.28)*2.2,-.18,.18)*(1.-smoothstep(.86,.98,abs(earth.y)));
    var base=mix(vec3f(.12,.20,.23),vec3f(.055,.20,.29),.75)*(1.+variation);
    base+=vec3f(-.010,.012,.020)*variation;
    let polar=select(smoothstep(.91355,.97815,-earth.y)*.46,smoothstep(.95106,.99452,earth.y)*.82,earth.y>0.);
    let floe=textureSampleLevel(ocean_material,world_sampler,fract(earth.xz*2.2+.5),0.).a;
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
fn administrative_edge(a:vec2u,b:vec2u) -> bool {
    return a.x!=0u && a.x==u32(view.selection.w) && a.x==b.x && a.y!=0u && b.y!=0u && a.y!=b.y;
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
struct NaturalPage { texel:vec2f, slot:i32, coverage:f32 }
fn natural_uv(ll:vec2f) -> vec2f {
    // A rounded longitude at the antimeridian must stay in the last column.
    return vec2f(min(fract(ll.x/360.+.5),.99999994),clamp(.5-ll.y/180.,0.,.99999994));
}
fn natural_lod_weight(zoom:u32) -> f32 {
    if f32(zoom)>view.map_style.z {return 0.;}
    if view.chart_origin.w>.5 {return select(0.,1.,f32(zoom)==view.map_style.z);}
    let opacity=view.natural_lod[zoom/4u][zoom%4u];
    return select(opacity,1.,opacity<0.);
}
fn page_readiness(cell:vec2i, columns:i32, rows:i32, shift:u32) -> f32 {
    let x=(cell.x+columns)%columns;
    let y=clamp(cell.y,0,rows-1)+rows-1;
    let index=textureLoad(terrain_index,vec2i(x,y),0).r;
    let fade=(index>>shift)&255u;
    // A landscape page can be decoded before its color is visible.
    return f32(select(fade,min(fade,(index>>16u)&255u),shift==24u))/255.;
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
fn natural_page(uv:vec2f, zoom:u32, exact:bool) -> NaturalPage {
    let rows=1i<<zoom;
    let position=uv*vec2f(f32(rows*2),f32(rows));
    let cell=vec2i(position);
    let index=textureLoad(terrain_index,cell+vec2i(0,rows-1),0).r;
    let slot=i32(index&65535u)-1;
    let q=fract(position);
    let texel=q*256.+4.;
    if slot<0 {return NaturalPage(texel,slot,0.);}
    if exact {return NaturalPage(texel,slot,1.);}
    let fade=f32((index>>16u)&255u)/255.;
    return NaturalPage(texel,slot,page_coverage(cell,q,rows,16u,fade));
}
fn natural_page_sample(page:NaturalPage, offset:vec2f) -> vec4f {
    return textureSampleLevel(terrain_detail,linear,(page.texel+offset)/264.,page.slot,0.);
}
fn natural_surface(ll:vec2f) -> vec4f {
    let uv=natural_uv(ll);
    if view.chart_origin.w>.5 && view.map_style.z>0. {
        let page=natural_page(uv,u32(view.map_style.z),true);
        if page.coverage<=0. {return vec4f(1.,0.,1.,0.);}
        return natural_page_sample(page,vec2f(0.));
    }
    var color=vec4f(0.);
    var remaining=1.;
    for(var z=u32(view.map_style.z);z>0u;z-=1u) {
        let opacity=natural_lod_weight(z);
        if opacity<=0. {continue;}
        let page=natural_page(uv,z,false);
        let weight=remaining*page.coverage*opacity;
        if weight<=0. {continue;}
        color+=natural_page_sample(page,vec2f(0.))*weight;
        remaining-=weight;
        if remaining<.0001 {return color;}
    }
    return color+natural_global(uv)*remaining;
}

fn water_page_area(page:u32, q:vec2f) -> u32 {
    let cell=vec2u(q*8.);
    let start=water_geometry[page+cell.y*8u+cell.x];
    if start<=3u {return start;}
    let at=page+start-4u;
    let y_band=u32(q.y*64.)%8u;
    let end=at+water_geometry[at+y_band+2u];
    var bits=water_geometry[at];
    let p=q*65472.;
    for (var edge=at+water_geometry[at+y_band+1u];edge<end;edge+=3u) {
        let a=water_geometry[edge];
        let b=water_geometry[edge+1u];
        let ay=f32(a>>16u);
        let by=f32(b>>16u);
        if p.y<ay || p.y>=by {continue;}
        let ax=f32(a&65535u);
        let bx=f32(b&65535u);
        if p.x < mix(ax,bx,(p.y-ay)/(by-ay)) {
            bits=bits^water_geometry[edge+2u];
        }
    }
    if (bits>>4u)!=0u {return select(2u,3u,(bits&1u)!=0u);}
    if (bits&8u)!=0u {return 3u;}
    if (bits&4u)!=0u {return 1u;}
    if (bits&2u)!=0u {return 3u;}
    return select(2u,1u,(bits&1u)!=0u);
}

// The raster carries the area and its age origin. A parked camera can reuse it
// through the handoff without rerunning the polygon tests each frame.
fn water_area(ll:vec2f) -> u32 {
    let tile_uv=min(vec2f(fract(ll.x/360.+.5),clamp(.5-ll.y/180.,0.,1.)),vec2f(.99999994));
    let grid=tile_uv*vec2f(256.,128.);
    let tile_cell=vec2u(grid);
    let page=water_geometry[tile_cell.y*256u+tile_cell.x];
    if page<=3u {return page;}
    let q=vec2f(fract(grid.x),min(1.-fract(grid.y),.99999994));
    return (water_geometry[page]<<2u)|water_page_area(page+1u,q);
}

fn geographic_water_weight() -> f32 {
    return 1.-smoothstep(2600.,4200.,view.viewport.z*EARTH);
}

fn screen_water(pixel:vec2f) -> u32 {
    if view.chart_origin.w>.5 || view.viewport.z*EARTH>=4200.
        || any(pixel<vec2f(0.)) || any(pixel>=view.viewport.xy) {return 0u;}
    let at=vec2u(pixel);
    let columns=u32(view.viewport.x);
    let index=at.y*columns+at.x;
    if arrayLength(&water_pixels)<columns*u32(view.viewport.y) {return 0u;}
    return water_pixels[index];
}

fn water_weight(sample:u32) -> f32 {
    if sample==0u {return 0.;}
    let stamp=sample>>2u;
    if stamp==0u {return geographic_water_weight();}
    // 20 four-millisecond ticks. Only pixels whose coverage or basin
    // differs from the fallback change while this local handoff runs.
    return smoothstep(0.,20.,f32(max(view.water_clock,stamp)-stamp))*geographic_water_weight();
}

fn water_coverage(sample:u32, fallback:f32) -> f32 {
    return mix(fallback,select(0.,1.,(sample&3u)>1u),water_weight(sample));
}

fn exposed_page_ground(page:NaturalPage) -> vec4f {
    // Use the shared gutters and samples where the base map observes land.
    let center=natural_page_sample(page,vec2f(0.));
    if center.a<=0. {return vec4f(center.rgb,1.);}
    let offsets=array<vec2f,4>(vec2f(-1.,0.),vec2f(1.,0.),vec2f(0.,-1.),vec2f(0.,1.));
    var sum=vec3f(0.);
    var total=0.;
    for (var ring=0u;ring<2u;ring++) {
        let distance=select(1.35,3.4,ring==1u);
        let reach=select(1.,1.-smoothstep(.35,.80,total),ring==1u);
        if reach<=0. {break;}
        for (var i=0u;i<4u;i++) {
            let sample=natural_page_sample(page,offsets[i]*distance);
            let dry=(1.-smoothstep(.015,.15,sample.a))*reach;
            sum+=sample.rgb*dry;
            total+=dry;
        }
    }
    return vec4f(sum/max(.001,total),smoothstep(.02,1.3,total));
}

fn exposed_ground(ll:vec2f, fallback:vec3f) -> vec3f {
    let uv=natural_uv(ll);
    var ground=vec3f(0.);
    var remaining=1.;
    var observed=0.;
    for(var z=u32(view.map_style.z);z>0u;z-=1u) {
        let opacity=natural_lod_weight(z);
        if opacity<=0. {continue;}
        let page=natural_page(uv,z,false);
        let visible=remaining*page.coverage*opacity;
        if visible<=0. {continue;}
        let dry=exposed_page_ground(page);
        let weight=visible*dry.a;
        ground+=dry.rgb*weight;
        observed+=weight;
        remaining-=visible;
        if remaining<.0001 {break;}
    }
    if observed>=.9999 {return ground;}
    return ground+geographic_ground_tint(ll,fallback)*(1.-observed);
}

fn water_surface(ll:vec2f, sample:u32, base:vec4f, ground:vec3f, depth:f32) -> vec4f {
    if view.water_clock==0u || view.chart_origin.w>.5 {return base;}
    let zoom=geographic_water_weight();
    if zoom<=0. {return base;}
    let area=sample&3u;
    let w=water_weight(sample);
    if area<=1u && base.a<.005 {return base;}
    let sea=mix(vec3f(.18,.37,.43),vec3f(.095,.25,.34),smoothstep(9.,240.,depth));
    let river=vec3f(.20,.38,.45);
    let preserve=smoothstep(640.,2450.,view.viewport.z*EARTH)*smoothstep(.88,.995,base.a);
    let ice=smoothstep(52.,68.,abs(ll.y))
        *smoothstep(.46,.68,min(base.r,base.g))*smoothstep(.80,.98,base.a);
    // The Antarctic QPK paints SCAR ADD shelves into marine samples while
    // keeping their water alpha. Nearby bright ground and lakes do not carry
    // that shelf pigment. Retain the generic ice tint only in raster fallback.
    let shelf_color=vec3f(215.,226.,229.)/255.;
    let shelf=select(0.,(1.-smoothstep(.03,.14,distance(base.rgb,shelf_color)))
        *smoothstep(.93,.995,base.a),ll.y<-60. && area==2u);
    let ink=mix(select(sea,river,area==3u),base.rgb,max(shelf,preserve));
    if w>=.999 {
        if area>1u {return vec4f(ink,1.);}
        let ground_color=mix(base.rgb,exposed_ground(ll,ground),smoothstep(.005,.18,base.a));
        return vec4f(ground_color,0.);
    }
    let lake=vec3f(.15,.29,.36);
    let basin=max(1.-smoothstep(.012,.040,distance(base.rgb,river)),
                  (1.-smoothstep(.009,.027,distance(base.rgb,lake)))*(1.-smoothstep(5.,38.,depth)));
    // Render agreed water with the same pigments while geometry is in flight.
    // The QPK samples still define fallback coverage and large-scale bathymetry.
    let fallback=mix(base.rgb,mix(mix(sea,river,basin),base.rgb,max(ice,preserve)),
                     zoom*smoothstep(.15,.92,base.a));
    if w<=0. {return vec4f(fallback,base.a);}
    if area==1u {
        let exposed=mix(base.rgb,exposed_ground(ll,ground),smoothstep(.005,.18,base.a));
        return vec4f(mix(fallback,exposed,w),base.a*(1.-w));
    }
    return vec4f(mix(fallback,ink,w),mix(base.a,1.,w));
}
fn land_material_band(earth:vec3f, planes:vec3f, footprint:f32, period:f32) -> vec4f {
    let world=earth*(EARTH/period);
    // Change the phase over a few repeats, in the same coordinates for every LOD.
    let phase=ground_field(world*vec3f(.33,.28,.36)+vec3f(1.7,4.1,7.3));
    let cross_phase=ground_field(world*vec3f(.54,.39,.47)+vec3f(7.8,2.3,11.1));
    let p=world+phase*vec3f(1.12,-.83,.71)+cross_phase*vec3f(-.40,.72,.91);
    let turn=mat2x2f(vec2f(.8660254,.5),vec2f(-.5,.8660254));
    // Include the warp in the footprint to suppress grain aliasing during movement.
    let mip=log2(max(1.,1.18*footprint*f32(textureDimensions(land_surface).x)/period));
    return textureSampleLevel(land_surface,land_repeat,p.yz,mip)*planes.x
        +textureSampleLevel(land_surface,land_repeat,turn*p.xz+vec2f(.21,.43),mip)*planes.y
        +textureSampleLevel(land_surface,land_repeat,p.yx*turn+vec2f(.67,.29),mip)*planes.z;
}

fn landscape_random(seed: u32) -> f32 {
    let state = seed * 747796405u + 2891336453u;
    let word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return f32(((word >> 22u) ^ word) >> 8u) / 16777216.;
}

fn ground_gradient(key: u32, offset: vec3f) -> f32 {
    let code = u32(landscape_random(key)*16.);
    let u = select(offset.y,offset.x,code<8u);
    let v = select(select(offset.z,offset.x,code==12u || code==14u),offset.y,code<4u);
    return select(-u,u,(code&1u)==0u) + select(-v,v,(code&2u)==0u);
}

fn ground_field(point: vec3f) -> f32 {
    let cell = bitcast<vec3u>(vec3i(floor(point)));
    let f = fract(point);
    let t = f*f*f*(f*(6.*f-15.)+10.);
    let dx = 116831u;
    let dy = 24571u;
    let dz = 141937u;
    let key = cell.x*dx + cell.y*dy + cell.z*dz;
    let a = mix(ground_gradient(key,f),ground_gradient(key+dx,f-vec3f(1.,0.,0.)),t.x);
    let b = mix(ground_gradient(key+dy,f-vec3f(0.,1.,0.)),ground_gradient(key+dx+dy,f-vec3f(1.,1.,0.)),t.x);
    let c = mix(ground_gradient(key+dz,f-vec3f(0.,0.,1.)),ground_gradient(key+dx+dz,f-vec3f(1.,0.,1.)),t.x);
    let d = mix(ground_gradient(key+dy+dz,f-vec3f(0.,1.,1.)),ground_gradient(key+dx+dy+dz,f-vec3f(1.,1.,1.)),t.x);
    return mix(mix(a,b,t.y),mix(c,d,t.y),t.z);
}

fn sediment_structure(earth:vec3f, footprint:f32) -> vec2f {
    // Broad soil and vegetation patches remain visible at Z5. The finer
    // deposits use the same world coordinates and fade before they alias.
    let p=earth*(EARTH/11600.);
    let drift=ground_field(p*vec3f(.94,1.25,.80));
    var grain=0.;
    if footprint<130. {
        let local=p*vec3f(36.,46.,17.)+vec3f(3.7,12.1,6.3)+drift*.91;
        grain=ground_field(local)*(1.-smoothstep(44.,130.,footprint));
    }
    return vec2f(drift*(1.-smoothstep(1250.,LAND_MATERIAL_MPP,footprint)),grain);
}
fn land_chroma(rgb:vec3f) -> vec2f {
    return vec2f(rgb.g-rgb.r,rgb.r+rgb.g-2.*rgb.b)/max(.001,rgb.r+rgb.g+rgb.b);
}
fn land_palette_weight(chroma:vec2f, reference:vec3f, radius:f32) -> f32 {
    return 1.-smoothstep(.008,radius,distance(chroma,land_chroma(reference)));
}
fn ground_material_weight(water: f32, mpp: f32) -> f32 {
    return (1.-smoothstep(880.,LAND_MATERIAL_MPP,mpp)) * (1.-smoothstep(.04,.65,water));
}
fn natural_land_material(terrain:vec4f, earth:vec3f, footprint:f32) -> vec3f {
    let base=terrain.rgb;
    let land=1.-smoothstep(.02,.42,terrain.a);
    let brightest=max(base.r,max(base.g,base.b));
    let darkest=min(base.r,min(base.g,base.b));
    let snow=smoothstep(.58,.82,darkest)*(1.-smoothstep(.06,.17,brightest-darkest));
    if land<.001 || footprint>=LAND_MATERIAL_MPP || all(base==vec3f(1.,0.,1.)) {return base;}

    // Use the baked palette as a cue for artistic motifs. Normalize away
    // multiplicative relief lighting before comparing Z6/Z7 or shaded slopes.
    let chroma=land_chroma(base);
    let woods=max(land_palette_weight(chroma,vec3f(.255,.41,.31),.106),
                  land_palette_weight(chroma,vec3f(.25,.41,.33),.106));
    let sward=land_palette_weight(chroma,vec3f(.47,.53,.33),.078)*(1.-woods*.75);
    let soil=max(land_palette_weight(chroma,vec3f(.61,.57,.36),.060),sward);
    let rock=land_palette_weight(chroma,vec3f(.51,.47,.41),.105);
    let sand=land_palette_weight(chroma,vec3f(.775,.632,.433),.051);
    let motifs=vec4f(woods,soil,rock,sand);
    let total=dot(motifs,vec4f(1.));
    let materials=motifs/max(1.,total)+vec4f(0.,0.,.12,.88)*(1.-min(1.,total));

    let facing=abs(earth)*abs(earth);
    let planes=facing*facing/dot(facing,facing);
    let broad=land_material_band(earth,planes,footprint,14500.)-.5;
    // Broad forest and sand grain stays weaker than exposed rock. The baked
    // geographic albedo and shading remain legible on flat, uniform surfaces.
    let solid=mix(materials,vec4f(0.,0.,.12,.30),snow);
    var relief=dot(broad,solid*vec4f(.19,.095,.28,0.))*(1.-smoothstep(210.,LAND_MATERIAL_MPP,footprint));
    if solid.w+solid.y>.01 {
        let sediment=sediment_structure(earth,footprint);
        relief+=dot(sediment,vec2f(.20,.13))*(solid.w+solid.y*.68);
    }
    if footprint<102. {
        let fine=land_material_band(earth,planes,footprint,2150.)-.5;
        relief+=dot(fine,solid*vec4f(.18,.075,.28,.12))*(1.-smoothstep(38.,102.,footprint));
    }
    return clamp(base*(1.+relief*land),vec3f(0.),vec3f(1.));
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
        let crop_ink=vec3f(.57,.54,.36);
        var crop_surface=crop_ink;
        if base.a>=0. && occupied.b>.12 && footprint<180. {
            let crop=occupied.b*(1.-smoothstep(.04,.26,occupied.r));
            crop_surface=cultivated_fields(crop_ink,ll,landscape_world(ll),footprint,crop);
        }
        let surface=other*vec3f(.43,.51,.33)
            +occupied.r*vec3f(.20,.38,.45)
            +occupied.g*vec3f(.255,.41,.31)
            +occupied.b*crop_surface;
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

fn water_packets(point:vec3f, planes:vec3f, footprint:f32, period:f32, channel:u32) -> f32 {
    let p=point/period;
    let mip=log2(max(1.,footprint*f32(textureDimensions(ocean_material).x)/period));
    let turn=mat2x2f(vec2f(.8,.6),vec2f(-.6,.8));
    let x=textureSampleLevel(ocean_material,land_repeat,p.zy+vec2f(.16,.39),mip);
    let y=textureSampleLevel(ocean_material,land_repeat,turn*p.zx+vec2f(.82,.33),mip);
    let z=textureSampleLevel(ocean_material,land_repeat,p.yx*turn+vec2f(.37,.68),mip);
    return dot(vec3f(x[channel],y[channel],z[channel])-.5,planes);
}

fn natural_water_color(color:vec3f, world:vec3f, depth:f32, coverage:f32, mpp:f32, area:u32) -> vec3f {
    if coverage <= .04 || mpp > 18000. { return color; }
    let ice = smoothstep(.47,.68,min(color.r,color.g));
    let surface = smoothstep(.28,.88,coverage)*(1.-ice)*(1.-smoothstep(6400.,18000.,mpp));
    let shelf = smoothstep(2.,22.,depth)*(1.-smoothstep(80.,640.,depth));
    let off_shore = smoothstep(105.,2400.,depth);
    let open = max(shelf,off_shore);
    var wave = 0.;
    let basin=area&3u;
    let marine=mix(open,select(0.,1.,basin==2u),water_weight(area));
    if view.map_style.z>=5. && mpp<2200. && surface>.001 && (marine>.01 || (basin==3u && mpp<270.)) {
        // Advect independently seeded crests, with a world-space warp across repeats.
        let time = view.chart_east.w;
        let point=world*EARTH;
        let warp=ground_field(point/47500.+vec3f(.6,2.9,6.3));
        let facing=world*world;
        let planes=facing*facing/dot(facing,facing);
        if marine>.01 {
            let swells=point+warp*vec3f(47000.,-26000.,71000.)-time*vec3f(2.3,.4,1.3);
            wave=water_packets(swells,planes,mpp,106000.,1u)
                *marine*mix(1.42,2.05,off_shore)*(1.-smoothstep(720.,2200.,mpp));
        }
        if mpp<270. {
            let chop=point+warp*vec3f(-7200.,9600.,4400.)+time*vec3f(.38,-.22,.64);
            wave+=water_packets(chop,planes,mpp,15800.,2u)
                * max(marine*1.20,select(0.,.36,basin==3u))*(1.-smoothstep(68.,270.,mpp));
        }
        wave*=smoothstep(.82,1.,coverage);
    }
    let pigment = vec3f(.018,.062,.059)*shelf*open
        + mix(vec3f(.010,.019,.023),vec3f(.009,.017,.024),open)*wave;
    return clamp(color+pigment*surface,vec3f(0.),vec3f(1.));
}

fn shade_map(ll:vec2f, uv:vec2f, normal_world:vec3f, normal_view:vec3f, area:u32) -> vec3f {
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
        terrain=water_surface(ll,area,natural_surface(ll),color,max(0.,-z)*data.a);
        color=terrain.rgb;
        if view.settings.y<.5 && view.map_style.z>=6. && base_mpp<LAND_DETAIL_MPP {
            let foreshortening=mix(max(.25,dot(normal_world,view.chart_forward.xyz)),1.,view.viewport.w);
            let detail_footprint=base_mpp/(foreshortening*max(.3,view.chart_origin.z));
            terrain=close_terrain(ll,detail_footprint,terrain);
            color=terrain.rgb;
        }
        color=landscape_relief(color,ll,normal_world,terrain.a,base_mpp);
        if view.chart_origin.w <= .5 {
            color=natural_water_color(color,normal_world,max(0.,-z)*data.a,terrain.a,base_mpp,area);
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
        let index=(u32(view.settings.y)-1u)*256u+id.x;
        let datum=unpack4x8unorm(palette[index/4u][index%4u]);
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
            let admin=administrative_edge(id,x) || administrative_edge(id,y)
                || administrative_edge(id,l) || administrative_edge(id,b);
            if national || (admin && view.settings.y<1.5 && base_mpp<2400.) {
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
    if view.settings.z>.5 && view.selection.z>0. {
        let dims=vec2i(textureDimensions(owners));
        let at=vec2i(floor(uv*vec2f(dims)));
        let id=ids(at,dims);
        if id.x==u32(view.selection.w) && id.y==u32(view.selection.z) {
            let edge=any(ids(at+vec2i(1,0),dims)!=id) || any(ids(at+vec2i(0,1),dims)!=id)
                || any(ids(at-vec2i(1,0),dims)!=id) || any(ids(at-vec2i(0,1),dims)!=id);
            let opacity=select(.08,.88*clamp(base_mpp/max(dx,dy),.12,1.),edge);
            color=mix(color,vec3f(.97,.77,.34),opacity*(1.-terrain.a));
        }
    }
    if view.settings.y>2.5 && view.map_style.w>0. {
        // R68's Lambert-93 origin and 50/25 km spacing. This is a display grid;
        // its France mask does not claim the original topology's cell membership.
        let phi=radians(clamp(ll.y,-85.,85.));
        let e=.08181919*sin(phi);
        let ts=tan(PI*.25-phi*.5)/pow((1.-e)/(1.+e),.040909595);
        let rho=11754255.426*pow(ts,.725607765);
        let theta=.725607765*radians(ll.x-3.);
        let shifted=vec2f(52000.,-262000.)+vec2f(rho*sin(theta),6055612.05-rho*cos(theta));
        let cell=shifted/view.map_style.w;
        let pixel_span=max(fwidth(cell),vec2f(.00001));
        let gap=abs(fract(cell+vec2f(.5))-.5)/pixel_span;
        let stroke=(1.-smoothstep(.22,.95,min(gap.x,gap.y)))*(1.-smoothstep(2200.,5000.,base_mpp));
        let selected=shifted/max(1.,view.military_cell.z)-view.military_cell.xy;
        let selected_span=max(fwidth(selected),vec2f(.00001));
        let edge=min(selected,vec2f(1.)-selected)/selected_span;
        let distance=min(edge.x,edge.y);
        let inside=smoothstep(-1.,0.,distance)*view.military_cell.w;
        let rim=inside*(1.-smoothstep(1.,2.4,distance));
        let grid_dims=vec2i(textureDimensions(owners));
        let grid_id=ids(vec2i(floor(uv*vec2f(grid_dims))),grid_dims);
        if view.settings.z>.5 && grid_id.x!=0u && grid_id.x==u32(view.selection.w) && ll.y>41. && ll.y<52. {
            color=mix(color,vec3f(.72,.81,.63),stroke*(1.-data.b)*.65);
            color=mix(color,vec3f(.93,.72,.38),(.12*inside+.73*rim)*(1.-data.b));
        }
    }
    return color;
}
// Geographic city pages carry feature coverage. Let the QPK pass own the
// continuous ground so loading a local page only reveals buildings and bridges.
fn geographic_city_ink(ll:vec2f,uv:vec2f,mpp:f32,edge_distance:f32,area:u32) -> vec4f {
    let historical=tile.options.z>1.5;
    let detail=1.-smoothstep(16.,CITY_INK_MPP,mpp);
    if !historical && detail<=0. {return vec4f(0.);}
    let du=1./vec2f(textureDimensions(city_data));
    let pixel_metres=(tile.extent.zw-tile.extent.xy)*du*111195.*vec2f(max(.08,cos(radians(ll.y))),1.);
    let mip=max(0.,log2(mpp/max(1.,min(pixel_metres.x,pixel_metres.y))));
    let buildings=textureSampleLevel(city_data,linear,uv,mip).rg;
    let edge=textureSampleLevel(city_data,linear,uv-du*.82,mip).r;
    let shadow=max(0.,edge-buildings.r)*detail*.49;
    // Aggregate the surveyed footprints over the screen footprint. At
    // overview scales the raster represents built density, not lot boundaries.
    let block_mip=select(3.,clamp(mip+.7,3.,6.),historical);
    let blocks=textureSampleLevel(city_data,linear,uv,block_mip).r;
    if max(max(buildings.r,buildings.g),max(shadow,blocks))<=.001 {return vec4f(0.);}
    let base=natural_surface(ll);
    var terrain=vec4f(base.rgb,water_coverage(area,base.a));
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
    let density=smoothstep(.018,.32,blocks);
    let built=density*select(mix(.75,1.,urban),1.,historical);
    // At the survey limit, attenuate the mapped features over a few source blocks.
    let support=smoothstep(0.,mix(320.,670.,built),edge_distance);
    let facade=mix(vec3f(.68,.56,.48),vec3f(.80,.71,.62),max(0.,buildings.r-edge));
    let footprint_weight=select(detail,1.-smoothstep(24.,134.,mpp),historical);
    let wall=buildings.r*footprint_weight*mix(.70,.96,built)*land;
    // Wide mapped strokes survive the screen-space filter at the fringe.
    let stroke=smoothstep(.13,.48,buildings.g);
    let local_road=mix(terrain.rgb,vec3f(.76,.70,.59),mix(.39,.75,stroke));
    let road_color=mix(local_road,vec3f(.81,.75,.65),built);
    let fringe=mix(mix(.54,.79,stroke),mix(.27,.51,stroke),woods);
    let road_weight=select(detail,1.-smoothstep(58.,300.,mpp),historical);
    let road=buildings.g*road_weight*mix(fringe,.88,built);
    let bridge=mix(road,buildings.g*road_weight*.88,terrain.a);
    let shading=shadow*land*mix(.45,1.,built);
    let ground=land*select(detail*smoothstep(.055,.36,blocks)*.57,density*.83,historical);
    let aggregate=mix(vec3f(.59,.51,.42),vec3f(.48,.38,.31),density);
    let paving=mix(terrain.rgb,select(vec3f(.58,.52,.44),aggregate,historical),.82);
    let color=((paving*ground*(1.-shading)+vec3f(.36,.32,.31)*shading)*(1.-wall)+facade*wall)*(1.-bridge)
        +mix(road_color,vec3f(.69,.67,.59),terrain.a)*bridge;
    let alpha=((ground*(1.-shading)+shading)*(1.-wall)+wall)*(1.-bridge)+bridge;
    return vec4f(color/max(.0001,alpha),alpha*support);
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

fn river_coordinates(xy:vec2f,r:f32) -> vec2f {
    var angle=r;
    if view.viewport.w<=0. {angle=asin(min(r,1.));}
    let scale=select(1.,sin(angle)/max(r,.00000001),r>.00000001);
    // Both angular coordinates are invariant under normalization.
    let v=view.chart_east.xyz*(xy.x*scale)+view.chart_north.xyz*(xy.y*scale)
        +view.chart_forward.xyz*cos(angle);
    return degrees(vec2f(atan2(v.x,v.z),atan2(v.y,length(v.xz))));
}

fn projected_water(pixel:vec2f) -> u32 {
    let xy=(pixel-view.chart_origin.xy)*view.viewport.z*vec2f(1.,-1./view.chart_origin.z);
    let r=length(xy);
    if r<1.+view.viewport.w*(PI*.5-1.) {
        return water_area(river_coordinates(xy,r));
    }
    return 0u;
}

@compute @workgroup_size(8,8)
fn raster_water(@builtin(global_invocation_id) id:vec3u) {
    let size=vec2u(view.viewport.xy);
    if any(id.xy>=size) {return;}
    water_output[id.y*size.x+id.x]=projected_water(vec2f(id.xy)+.5);
}

fn inland_water(pixel:vec2f) -> f32 {
    var sample:u32;
    if any(pixel<vec2f(0.)) || any(pixel>=view.viewport.xy) {
        // Reach overlap already has a classified on-screen pixel. Look up
        // off-screen neighbours in the same QWG table at their pixel centres.
        sample=projected_water(floor(pixel)+.5);
    } else {
        sample=screen_water(pixel);
    }
    if (sample&3u)!=3u {return 0.;}
    return water_weight(sample);
}

fn nearby_inland_water(pixel:vec2f, across:vec2f, adjacent:vec2f, narrow:f32) -> f32 {
    let center=inland_water(pixel);
    if center>=.999 {return center;}
    let lateral=max(center,max(inland_water(pixel+across),inland_water(pixel-across)));
    if lateral>=.999 || narrow<=0. {return lateral;}
    return max(lateral,narrow*max(inland_water(pixel+adjacent),inland_water(pixel-adjacent)));
}

fn parallel_water_area(pixel:vec2f, across:vec2f) -> f32 {
    let mpp=view.viewport.z*EARTH;
    let screen_per_metre=vec2f(1.,-view.chart_origin.z)/mpp;
    // A 15 arcsecond centerline can be several hundred metres away from
    // the measured channel. Keep the search in world metres when zooming.
    let across_step=across*screen_per_metre*70.;
    let tangent=vec2f(-across.y,across.x)*screen_per_metre;
    let along=tangent*max(160.,mpp*2.);
    // At this footprint a measured narrow river can miss a pixel centre.
    let narrow=smoothstep(24.,38.,mpp)*(1.-smoothstep(85.,130.,mpp));
    let adjacent=normalize(tangent);
    // Allow a short gap in the observed area. Both along-reach anchors still
    // need water, so a tributary meeting a mapped river keeps its own symbol.
    var coverage=0.;
    for (var i=0u;i<=select(8u,14u,narrow>0.);i++) {
        let offset=across_step*f32(i);
        for (var side=0u;side<select(2u,1u,i==0u);side++) {
            let p=pixel+select(offset,-offset,side==1u);
            let before=nearby_inland_water(p-along,across_step,adjacent,narrow);
            if before<=coverage {continue;}
            let after=nearby_inland_water(p+along,across_step,adjacent,narrow);
            var overlap=min(before,after);
            if i>8u && overlap>coverage {
                // Require continuous measured water on the more distant match.
                overlap=min(overlap,nearby_inland_water(p,across_step,adjacent,narrow))*narrow;
            }
            coverage=max(coverage,overlap);
            if coverage>=.999 {return 1.;}
        }
    }
    return coverage;
}

@fragment fn river_ink(stroke:RiverStroke) -> @location(0) vec4f {
    let direction=vec2f(dpdx(stroke.side),-dpdy(stroke.side)*view.chart_origin.z);
    let xy=(stroke.clip.xy-view.chart_origin.xy)*view.viewport.z*vec2f(1.,-1./view.chart_origin.z);
    let r=length(xy);
    if r>=1.+view.viewport.w*(PI*.5-1.) {discard;}
    let sample=screen_water(stroke.clip.xy);
    let area=sample&3u;
    let exact=water_weight(sample)>=.999;
    if area>1u && exact {discard;}
    var water=0.;
    if !exact {water=water_coverage(sample,natural_surface(river_coordinates(xy,r)).a);}
    if water>=.57 {discard;}
    var distinct=1.;
    // At smaller map scales the displacement is comparable to a stroke pixel.
    // The coverage above already masks the visible overlap.
    let near=1.-smoothstep(290.,440.,view.viewport.z*EARTH);
    if area!=0u && near>0. && dot(direction,direction)>0. {
        distinct=1.-near*parallel_water_area(stroke.clip.xy,normalize(direction));
    }
    if distinct<=.001 {discard;}
    var surveyed=0.;
    if view.close_sample.z>.5 {
        let mpp=view.viewport.z*EARTH/max(.3,view.chart_origin.z);
        // A negative sentinel lets the same survey coverage mask protect
        // surveyed ground and water while using only its valid footprint.
        surveyed=clamp(1.+close_terrain(river_coordinates(xy,r),mpp,vec4f(0.,0.,0.,-1.)).a,0.,1.);
    }
    let alpha=stroke.ink.a*(1.-smoothstep(.20,.95,abs(stroke.side)))
        *(1.-smoothstep(.14,.57,water))*(1.-surveyed)*distinct;
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
    if !is_world && view.map_style.y>.5 && (view.settings.y<.5 || view.settings.y>2.5 && view.map_style.w<=0.) && tile.options.z<.5 && view.selection.y<.5 && view.selection.z<.5 {discard;}
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
        if tile.options.z<1.5 && view.viewport.z*EARTH>=CITY_INK_MPP {discard;}
        let ink=geographic_city_ink(ll,uv,view.viewport.z*EARTH,edge_distance,screen_water(p.xy));
        return vec4f(ink.rgb,ink.a*tile.options.x*coverage);
    }
    var color=shade_map(ll,uv,v,normal_view,screen_water(p.xy));
    if is_world {
        let edge=1.-smoothstep(0.,view.viewport.z*1.2,horizon-r);
        color=mix(color,sky(p.xy),edge*.47);
    }
    let page_blend=select(blend,coverage,tile.options.y>=5.);
    return vec4f(color,tile.options.x*page_blend);
}
