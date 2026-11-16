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
};
struct LandEdit { area: vec4f, state: vec4f };
struct Tile {
    extent: vec4f,
    core: vec4f,
    region: vec4f,
    options: vec4f, // opacity, material facts, city facts, is world
    edges: vec4f,
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
@group(1) @binding(0) var<uniform> tile: Tile;
@group(1) @binding(1) var terrain_data: texture_2d<f32>;
@group(1) @binding(2) var material_data: texture_2d<f32>;
@group(1) @binding(3) var city_data: texture_2d<f32>;
@group(1) @binding(4) var owners: texture_2d<u32>;

const PI: f32 = 3.14159265358979;
const EARTH: f32 = 6371008.8;
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
fn page_readiness(cell:vec2i, columns:i32, rows:i32) -> f32 {
    let x=(cell.x+columns)%columns;
    let y=clamp(cell.y,0,rows-1)+rows-1;
    return f32(textureLoad(terrain_index,vec2i(x,y),0).r>>16u)/255.;
}
fn page_surface(uv:vec2f, zoom:i32, exact:bool) -> NaturalPage {
    let rows=1i<<u32(zoom);
    let columns=rows*2;
    let offset=rows-1;
    let position=uv*vec2f(f32(columns),f32(rows));
    let cell=vec2i(floor(position));
    let at=vec2i(cell.x,cell.y+offset);
    let index=textureLoad(terrain_index,at,0).r;
    let slot=i32(index&65535u)-1;
    if slot<0 {return NaturalPage(vec4f(0.),0.);}
    let q=fract(position);
    let refined=textureSampleLevel(terrain_detail,linear,(q*256.+4.)/264.,slot,0.);
    if exact {return NaturalPage(refined,1.);}
    var fade=f32(index>>16u)/255.;
    // Every cell meeting at an edge or corner uses the same refinement weight.
    // The common parent supplies unready portions at identical coordinates.
    let rim=min(q,1.-q);
    let collar=.04;
    let dx=vec2i(select(-1,1,q.x>.5),0);
    let dy=vec2i(0,select(-1,1,q.y>.5));
    var edge_x=fade;
    var edge_y=fade;
    if rim.x<collar {
        edge_x=min(fade,page_readiness(cell+dx,columns,rows));
    }
    if rim.y<collar {
        edge_y=min(fade,page_readiness(cell+dy,columns,rows));
    }
    if min(rim.x,rim.y)<collar {
        var corner=min(edge_x,edge_y);
        if max(rim.x,rim.y)<collar {
            corner=min(corner,page_readiness(cell+dx+dy,columns,rows));
        }
        let t=smoothstep(vec2f(0.),vec2f(collar),rim);
        fade=mix(mix(corner,edge_y,t.x),mix(edge_x,fade,t.x),t.y);
    }
    return NaturalPage(refined,fade);
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
        let page=page_surface(uv,z,grouped);
        let weight=remaining*page.coverage*select(1.,opacity,grouped);
        color+=page.color*weight;
        remaining-=weight;
        if remaining<.0001 {return color;}
    }
    return color+natural_global(uv)*remaining;
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
        relief_light=clamp(.57+dot(color,vec3f(.30,.55,.15))*.68,.70,1.19);
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
    let a=select(asin(min(r,1.)),r,t>0.);
    let k=select(1.,sin(a)/max(r,.00000001),r>.00000001);
    let v=normalize(view.chart_east.xyz*(xy.x*k)+view.chart_north.xyz*(xy.y*k)+view.chart_forward.xyz*cos(a));
    let ll=degrees(vec2f(atan2(v.x,v.z),atan2(v.y,length(v.xz))));
    if !is_world && (ll.x<tile.core.x || ll.y<tile.core.y || ll.x>=tile.core.z || ll.y>=tile.core.w) {discard;}
    let uv=vec2f((ll.x-tile.extent.x)/(tile.extent.z-tile.extent.x),
                 (tile.extent.w-ll.y)/(tile.extent.w-tile.extent.y));
    let normal_view=vec3f(dot(v,view.east.xyz),dot(v,view.north.xyz),dot(v,view.forward.xyz));
    var color=shade_map(ll,uv,v,normal_view);
    if is_world {
        let edge=1.-smoothstep(0.,view.viewport.z*1.2,horizon-r);
        color=mix(color,sky(p.xy),edge*.47);
    }
    let edge_distance=min(min(ll.x-tile.region.x,tile.region.z-ll.x)*max(.08,cos(radians(ll.y))),
                          min(ll.y-tile.region.y,tile.region.w-ll.y))*111195.;
    let blend=select(smoothstep(0.,max(select(1400.,2400.,tile.options.z>.5),view.viewport.z*EARTH*30.),edge_distance),1.,is_world);
    let rim=vec4f(ll-tile.core.xy,tile.core.zw-ll);
    let feather=select(vec4f(1.),smoothstep(vec4f(0.),max(tile.edges,vec4f(.00001)),rim),tile.edges>vec4f(0.));
    let page_blend=select(blend,feather.x*feather.y*feather.z*feather.w,tile.options.y>=5.);
    return vec4f(color,tile.options.x*page_blend);
}
