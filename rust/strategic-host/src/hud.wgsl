struct Camera {
    view: vec2<f32>,
    center: vec2<f32>,
    zoom: f32,
    seconds: f32,
    padding_1: f32,
    padding_2: f32,
};
@group(0) @binding(0) var<uniform> camera: Camera;
@group(1) @binding(0) var atlas: texture_2d<f32>;
@group(1) @binding(1) var atlas_sampler: sampler;
struct MapView {east:vec4f,north:vec4f,forward:vec4f,viewport:vec4f};
@group(2) @binding(0) var<uniform> map_view:MapView;

struct Input {
    @location(0) pos: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) uv: vec2<f32>,
};
struct Output {
    @builtin(position) pos: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec2<f32>,
};
fn output(p: vec2<f32>, v: Input) -> Output {
    var o: Output;
    o.pos = vec4<f32>(p * vec2<f32>(2.0, -2.0) / camera.view + vec2<f32>(-1.0, 1.0), 0.0, 1.0);
    o.color = v.color;
    o.uv = v.uv;
    return o;
}
@vertex fn map_vertex(v: Input) -> Output {
    return output((v.pos - camera.center) * camera.zoom + camera.view * 0.5, v);
}
@vertex fn screen_vertex(v: Input) -> Output {
    return output(v.pos, v);
}
@fragment fn solid(o: Output) -> @location(0) vec4<f32> {
    // Constant UV tags on clock quads; ordinary solid geometry keeps UV=(0,0).
    if o.uv.y == -2. {return clock_menu_wheel(o);}
    if o.uv.y == -3. {return clock_original_hand(o);}
    return o.color;
}
@fragment fn image(o: Output) -> @location(0) vec4<f32> {
    return textureSample(atlas, atlas_sampler, o.uv) * o.color;
}
@fragment fn flag(o: Output) -> @location(0) vec4f {
    let cell=floor(o.uv*16.);
    let local=(fract(o.uv*16.)-0.005)/0.99;
    let phase=local.x*7.5-camera.seconds*2.1;
    let wave=sin(phase)*0.065*local.x;
    let v=(local.y-0.1)/0.8-wave;
    // Helper pixels beyond the mesh can cross an atlas cell, where fract wraps.
    let atlas_cloth_height=0.99*0.8/16.;
    let edge=max(fwidth(o.uv.y)*0.5/atlas_cloth_height,0.001);
    let cloth=smoothstep(-edge,edge,v)*(1.-smoothstep(1.-edge,1.+edge,v));
    let span=vec2f(textureDimensions(atlas))/16.;
    let uv=(cell+(vec2f(0.5)+clamp(vec2f(local.x,v),vec2f(0.),vec2f(1.))*(span-1.))/span)/16.;
    let sample=textureSampleLevel(atlas,atlas_sampler,uv,0.);
    let neutral=dot(sample.rgb,vec3f(0.2126,0.7152,0.0722));
    let tone=mix(vec3f(neutral),sample.rgb,0.83)*(.94+cos(phase)*.055*local.x);
    return vec4f(tone,sample.a*cloth*o.color.a);
}
@fragment fn loading(o: Output) -> @location(0) vec4f {
    let sweep=fract(camera.seconds*0.24)*1.45-0.25;
    let light=smoothstep(sweep-0.20,sweep,o.uv.x)*(1.-smoothstep(sweep,sweep+0.20,o.uv.x));
    return vec4f(mix(vec3f(.21,.24,.21),vec3f(.72,.61,.38),light),.82*o.color.a);
}
fn halo(r: f32) -> f32 {
    if r<.22 {return mix(1.,.68,r/.22);}
    if r<.50 {return mix(.68,.30,(r-.22)/.28);}
    if r<.76 {return mix(.30,.065,(r-.50)/.26);}
    return mix(.065,0.,clamp((r-.76)/.24,0.,1.));
}
@fragment fn history_light(o: Output) -> @location(0) vec4f {
    let p=o.uv;
    let source=p-vec2f(.5+.06/1.24,-6./116.);
    let wide=.17*halo(length(source*vec2f(2.*1.24/1.12,232./196.)));
    let shaft=.09*halo(length(source*vec2f(2.*1.24/.38,232./244.)));
    let start=.12/1.24;
    let end=1.-start;
    let t=clamp((p.x-start)/(end-start),0.,1.);
    let arc=(24.+20.*4.*t*(1.-t))/116.;
    let dist=abs(p.y-arc)*116.;
    let edge=step(start,p.x)*step(p.x,end);
    let tail=smoothstep(0.04,1.,t);
    let strand=mix(.08,.52,tail)*(1.-smoothstep(mix(.12,1.55,pow(t,1.4)),mix(.72,2.15,pow(t,1.4)),dist));
    let mist=mix(.025,.12,tail)*(1.-smoothstep(mix(.12,4.6,pow(t,1.4)),mix(.72,5.2,pow(t,1.4)),dist));
    let head=length((p-vec2f(end,24./116.))*vec2f(694.4,116.));
    let trail=edge*(strand+mist)+.15*(1.-smoothstep(3.,4.,head))+.65*(1.-smoothstep(1.3,2.3,head));
    let light=(wide+shaft)*o.color.a;
    let rgb=vec3f(.93,.89,.79)*trail+(wide*vec3f(.93,.73,.49)+shaft*vec3f(1.,.94,.78))*o.color.a;
    return vec4f(rgb/max(trail+light,.0001),clamp(trail+light,0.,1.));
}
@fragment fn instrument(o:Output)->@location(0) vec4f {
    let size=map_view.viewport.xy;
    let radius=clamp(size.x*.056,52.,78.);
    let q=(o.pos.xy-vec2f(size.x*.5,size.y))/radius;
    let r=length(q);
    if r>.985 || q.y>0. {discard;}
    let view=vec3f(q.x,-q.y,sqrt(max(0.,1.-dot(q,q))));
    let earth=normalize(map_view.east.xyz*view.x+map_view.north.xyz*view.y+map_view.forward.xyz*view.z);
    let lon=atan2(earth.x,earth.z);
    let lat=asin(clamp(earth.y,-1.,1.));
    let u=fract(lon/6.2831853+.5);
    let v=clamp(.5-lat/3.14159265,0.,1.);
    let sample=textureSampleLevel(atlas,atlas_sampler,vec2f((.5+u*1023.)/1024.,(400.5+v*511.)/1024.),0.).r;
    let light=.56+.44*max(0.,dot(view,normalize(vec3f(-.30,.65,1.))));
    var color=mix(vec3f(.065,.155,.165),vec3f(.43,.48,.32),sample)*light;
    color*=1.-.24*smoothstep(.65,.985,r);
    let angle=vec2f(lon,lat)/.5235987756;
    let edge=abs(fract(angle+.5)-.5);
    let width=max(fwidth(angle)*.65,vec2f(.00001));
    let grid=max(1.-smoothstep(width.x,2.*width.x,edge.x),1.-smoothstep(width.y,2.*width.y,edge.y));
    color=mix(color,vec3f(.63,.70,.59),grid*.27*smoothstep(.10,.30,length(earth.xz)));
    return vec4f(color,1.);
}



// R68 menu wheel: 32 teeth, outer/root radii 34/28.56. All four wheels use
// its pitch (31.28/32 per tooth), with centers separated by summed pitch radii.
const GEAR_PITCH:f32=31.28/32.;
const GEAR_DEPTH:f32=2.72;
fn tooth_radius(r:f32,n:f32,a:f32)->f32 {
 let u=fract(a*n/6.283185307+.375);
 return r-GEAR_DEPTH+2.*GEAR_DEPTH*clamp(min(4.*u,3.-4.*u),0.,1.);
}
fn driven_angle(a:f32,n:f32,next:f32,contact:f32)->f32 {
 return (1.+n/next)*contact+3.141592654-3.141592654/next-a*n/next;
}
fn train_angles(phase:f32)->vec4f {
 let mid=driven_angle(phase,44.,32.,-2.146754980);
 let small=driven_angle(mid,32.,18.,-.436332313);
 return vec4f(phase,mid,small,driven_angle(small,18.,32.,-.506145483));
}
fn brass_gear(p:vec2f,center:vec2f,r:f32,n:f32,angle:f32)->vec4f {
 let q=p-center; let d=length(q);let a=atan2(q.y,q.x)-angle;
 let boundary=tooth_radius(r,n,a);
 let aa=max(fwidth(d),.65);
 let rim=(1.-smoothstep(boundary-aa,boundary+aa,d))*smoothstep(r-4.-aa,r-4.+aa,d);
 let hub=1.-smoothstep(3.-aa,3.+aa,d);
 let spokes=(1.-smoothstep(.13,.22,abs(sin(a*3.))))*(1.-smoothstep(r-3.,r-2.,d));
 let mask=max(rim,max(hub,spokes*.7));
 let shade=.75+.25*cos(a-.8);
 return vec4f(vec3f(.70,.50,.24)*shade,mask*.72);
}
@fragment fn clock_gears(o:Output)->@location(0) vec4f {
 let radius=min(116.,camera.view.x*.22);let scale=radius/184.;
 let p=(o.pos.xy-vec2f(camera.view.x,0.))/scale;
 let angles=train_angles(o.uv.x);
 // Size reference: large lower wheel, medium left wheel, small upper wheel.
 // Shape stays regular; the three internal diameters are 44:32:18.
 let c2=vec2f(-.874619707,.484809620)*((32.+18.)*GEAR_PITCH);
 let c1=c2+vec2f(-.906307787,.422618262)*((18.+32.)*GEAR_PITCH);
 let c0=c1+vec2f(.544639035,.838670568)*((32.+44.)*GEAR_PITCH);
 let g0=brass_gear(p,c0,44.*GEAR_PITCH,44.,angles.x);
 let g1=brass_gear(p,c1,32.*GEAR_PITCH,32.,angles.y);
 let g2=brass_gear(p,c2,18.*GEAR_PITCH,18.,angles.z);
 if g0.a>=g1.a && g0.a>=g2.a {return g0;}
 if g1.a>=g2.a {return g1;}return g2;
}

fn clock_menu_wheel(o:Output)->vec4f {
 let scale=min(116.,camera.view.x*.22)/184.;
 let p=(o.pos.xy-vec2f(camera.view.x,0.))/scale;
 let r=length(p);let a=atan2(p.y,p.x)-train_angles(o.uv.x).w;
 let aa=.65/scale;
 let alpha=1.-smoothstep(-aa,aa,r-tooth_radius(31.28,32.,a));
 var color=o.color.rgb;
 let ring=1.-smoothstep(.65/scale-aa,.65/scale+aa,abs(r-34.*.59));
 color=mix(color,vec3f(59.,46.,28.)/255.,ring);
 let hole_angle=round(a/(3.141592654/6.))*(3.141592654/6.);
 let hole=length(p-vec2f(cos(hole_angle+train_angles(o.uv.x).w),sin(hole_angle+train_angles(o.uv.x).w))*34.*.51);
 let body=max(1.-smoothstep(34.*.26-aa,34.*.26+aa,r),1.-smoothstep(34.*.055-aa,34.*.055+aa,hole));
 color=mix(color,vec3f(6.,11.,16.)/255.,body);
 return vec4f(color,alpha*o.color.a);
}

// Lancet outline extended to the outer end of the speed marks.
fn clock_original_hand(o:Output)->vec4f {
 let scale=min(116.,camera.view.x*.22)/184.;
 let q=(o.pos.xy-vec2f(camera.view.x,0.))/scale;
 let direction=vec2f(cos(o.uv.x),sin(o.uv.x));
 let p=vec2f(dot(q,direction),dot(q,vec2f(-direction.y,direction.x)));
 let tip=165.;
 var half_width=3.5;
 if p.x>110.11 {half_width=mix(1.5,0.,clamp((p.x-110.11)/(tip-110.11),0.,1.));}
 else if p.x>50.05 {half_width=mix(2.3,1.5,(p.x-50.05)/60.06);}
 else if p.x>31.46 {half_width=mix(3.5,2.3,(p.x-31.46)/18.59);}
 let sd=max(abs(p.y)-half_width,max(-p.x,p.x-tip));let aa=.65/scale;
 let edge=1.-smoothstep(1.4-aa,1.4+aa,sd);
 let fill=1.-smoothstep(-aa,aa,sd);
 var color=mix(vec3f(3.,5.,6.)/255.,o.color.rgb,fill);
 let line=length(p-vec2f(clamp(p.x,31.46,tip-14.3),0.));
 let light=(1.-smoothstep(max(.6/scale,1.)*.5-aa,max(.6/scale,1.)*.5+aa,line))*.9;
 color=mix(color,vec3f(209.,184.,125.)/255.,light);
 return vec4f(color,edge*.96);
}

// Original atlas and gold rim retained; only the interior glass transmits more light.
@fragment fn clock_face(o:Output)->@location(0) vec4f {
 var c=textureSample(atlas,atlas_sampler,o.uv)*o.color;
 let px=o.uv*1024.;
 if px.x<=232. && px.y<=232. {
  let r=length((px-vec2f(232.,0.))/232.);
  c.a*=mix(.62,1.,smoothstep(.68,.78,r));
 }
 return c;
}
