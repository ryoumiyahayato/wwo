use std::{f64::consts::{FRAC_PI_2, PI}, sync::Arc, time::{Duration, Instant}};

pub const EARTH: f64 = 6_371_008.8;
pub const ENTER: f64 = 5500.;
pub const EXIT: f64 = 7000.;
pub const CITY_ENTER: f64 = 200.;
pub const CITY_EXIT: f64 = 280.;
pub const SCALE_TARGET_PIXELS: f64 = 80.;
pub const CONTEXT_MPP: f64 = 2000. / SCALE_TARGET_PIXELS;
pub type V3 = [f64; 3];

pub fn dot(a: V3, b: V3) -> f64 { a[0]*b[0] + a[1]*b[1] + a[2]*b[2] }
fn cross(a: V3,b: V3) -> V3 {
    [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
}
fn norm(a: V3) -> f64 { dot(a,a).sqrt() }
fn scale(v: V3,k: f64) -> V3 { v.map(|x| x*k) }
fn add(a: V3,b: V3) -> V3 { std::array::from_fn(|i| a[i]+b[i]) }
fn unit(v: V3) -> V3 { scale(v, 1./norm(v)) }
pub fn frame([lon,lat]: [f64;2]) -> [V3;3] {
    let (sl,cl)=lon.to_radians().sin_cos();
    let (sp,cp)=lat.to_radians().sin_cos();
    [[cl,0.,-sl],[-sl*sp,cp,-cl*sp],[sl*cp,sp,cl*cp]]
}
pub fn geographic(v: V3) -> [f64;2] {
    [v[0].atan2(v[2]).to_degrees(),v[1].clamp(-1.,1.).asin().to_degrees()]
}
pub fn smooth(low:f64,high:f64,x:f64)->f64 {
    let t=((x-low)/(high-low)).clamp(0.,1.);
    t*t*(3.-2.*t)
}
fn rotation(v: V3,axis:V3,angle:f64)->V3 {
    let (s,c)=angle.sin_cos();
    add(add(scale(v,c),scale(cross(axis,v),s)),scale(axis,dot(axis,v)*(1.-c)))
}

#[derive(Clone,Copy,PartialEq)]
pub enum Level { World, Region, Local }

#[derive(Clone, Copy)]
pub struct DetailRegion { pub extent: [f64; 4], pub minimum: f64, pub city: bool }

impl DetailRegion {
    pub fn new(extent:[f64;4], bounds:[f64;4], size:[u32;2], city:bool)->Self {
        let [w,s,e,n]=bounds;
        let metres=EARTH*PI/180.;
        let dx=(e-w)*((s+n)*0.5).to_radians().cos()*metres/f64::from(size[0]);
        let dy=(n-s)*metres/f64::from(size[1]);
        Self {extent,minimum:(dx.max(dy)*1.60).clamp(1.5,CONTEXT_MPP),city}
    }

    fn floor(self,[lon,lat]:[f64;2],size:[u32;2],requested:f64)->f64 {
        let [w,s,e,n]=self.extent;
        let metre=EARTH*PI/180.;
        let lon_m=metre*lat.to_radians().cos();
        let eye=requested.max(self.minimum).min(CONTEXT_MPP);
        let x=(lon-w).min(e-lon)*lon_m-f64::from(size[0])*eye*0.28;
        let y=(lat-s).min(n-lat)*metre-f64::from(size[1])*eye*0.28;
        let range=(eye*145.).max(900.);
        CONTEXT_MPP+(self.minimum-CONTEXT_MPP)*smooth(0.,range,x.min(y))
    }
}

#[derive(Clone)]
pub struct Camera {
    pub axes: [V3;3],
    pub mpp:f64,
    pub level:Level,
    pub local_models: bool,
    pub oblique: bool,
    region: Option<Region>,
    detail: Option<Arc<[DetailRegion]>>,
    requested_mpp: f64,
    scale_step: Option<Instant>,
    last_widening: Option<Instant>,
}

#[derive(Clone)]
struct Region {
    axes: [V3;3],
    offset: [f64;2],
    bearing: f64,
}

impl Region {
    fn basis(&self) -> [V3;3] {
        let axis = self.axes[2];
        self.axes.map(|v| rotation(v, axis, -self.bearing))
    }
}

impl Camera {
    pub fn new(size:[u32;2]) -> Self {
        let mpp=Self::overview(size);
        Self { axes:frame([2.3522,48.8566]),mpp,level:Level::World,
            local_models:false,oblique:true,region:None,detail:None,requested_mpp:mpp,
            scale_step:None,last_widening:None }
    }
    pub fn overview([width,height]:[u32;2]) -> f64 {
        EARTH / ((f64::from(height)/2.55).min(f64::from(width)*0.49)*1.05)
    }
    pub fn blend(&self) -> f64 { if self.region.is_some() {1.} else {0.} }
    pub fn pitch(&self) -> f64 {
        if self.local_models && self.oblique && self.region.is_some() {
            0.84 * (1. - smooth(30., 150., self.mpp))
        } else { 0. }
    }
    pub fn coordinates(&self) -> [f64;2] { geographic(self.axes[2]) }
    pub fn projection(&self, size: [u32;2]) -> ([V3;3], [f64;2]) {
        let mut center = size.map(|n| f64::from(n)*0.5);
        let Some(region) = &self.region else {return (self.axes, center);};
        for (value, offset) in center.iter_mut().zip(region.offset) {*value += offset;}
        (region.basis(), center)
    }
    pub fn vector(&self, p:[f64;2], size:[u32;2]) -> Option<V3> {
        let (axes, center) = self.projection(size);
        let x=(p[0]-center[0])*self.mpp/EARTH;
        let y=(center[1]-p[1])*self.mpp/(EARTH*self.pitch().cos());
        let r=x.hypot(y);
        let t=self.blend();
        if r>1.+t*(FRAC_PI_2-1.) { return None; }
        if r<1e-12 { return Some(axes[2]); }
        let a=if self.region.is_some(){r}else{r.asin()};
        let k=a.sin()/r;
        Some(unit(add(add(scale(axes[0],x*k),scale(axes[1],y*k)),scale(axes[2],a.cos()))))
    }
    pub fn project_vec(&self,v:V3,size:[u32;2]) -> Option<[f64;2]> {
        let (axes, center) = self.projection(size);
        let [x,y,z]=axes.map(|axis|dot(v,axis));
        if z<0. {return None;}
        let r=x.hypot(y);
        let a=r.atan2(z);
        let t=self.blend();
        let k=if r>1e-12 { (1.-t)+t*a/r } else {1.};
        let scale=EARTH/self.mpp*k;
        Some([center[0]+x*scale,center[1]-y*scale*self.pitch().cos()])
    }
    pub fn project(&self,p:[f64;2],size:[u32;2])->Option<[f64;2]> { self.project_vec(frame(p)[2],size) }
    fn align(&mut self, before:V3,after:V3) {
        let axis=cross(after,before);
        let sine=norm(axis);
        if sine>1e-12 {
            let a=sine.atan2(dot(after,before));
            self.axes=self.axes.map(|v|rotation(v,scale(axis,1./sine),a));
            self.axes[2]=unit(self.axes[2]);
            self.axes[0]=unit(cross(self.axes[1],self.axes[2]));
            self.axes[1]=cross(self.axes[2],self.axes[0]);
        }
    }
    pub fn drag(&mut self, a:[f64;2],b:[f64;2],size:[u32;2]) {
        if let Some(region) = &mut self.region {
            for i in 0..2 {region.offset[i] += b[i]-a[i];}
            self.constrain_region(size);
            return;
        }
        if let (Some(first),Some(last))=(self.vector(a,size),self.vector(b,size)) {
            self.align(first,last);
        } else {
            let x=-(b[0]-a[0])*self.mpp/EARTH;
            let y=-(b[1]-a[1])*self.mpp/EARTH;
            self.axes=self.axes.map(|v|rotation(v,self.axes[1],x));
            self.axes=self.axes.map(|v|rotation(v,self.axes[0],y));
        }
    }
    pub fn set_detail(&mut self,detail:Vec<DetailRegion>) { self.detail=Some(detail.into()); }

    pub fn reset(&mut self,size:[u32;2]) {
        let detail=self.detail.take();
        *self=Self::new(size);
        self.detail=detail;
    }

    pub fn has_city_ground(&self,point:[f64;2])->bool {
        self.detail.as_ref().is_none_or(|regions|regions.iter().any(|r|r.city&&inside(point,r.extent)))
    }

    pub fn precision_enabled(&self)->bool {self.detail.is_some()}

    pub fn set_scale(&mut self,mpp:f64) {
        self.mpp=mpp;
        self.requested_mpp=mpp;
        self.update_level();
    }

    fn minimum_at(&self,point:[f64;2],size:[u32;2],requested:f64)->f64 {
        self.detail.as_ref().map_or_else(|| {
            if self.local_models&&local_city(point) {1.5}
            else if inside(point,PARIS_CITY) {8.} else {CONTEXT_MPP}
        },|regions|regions.iter().fold(CONTEXT_MPP,|floor,r|floor.min(r.floor(point,size,requested))))
    }

    pub fn track_scale(&mut self,size:[u32;2],motion:[f64;2],anchor:[f64;2],now:Instant)->bool {
        let dt=self.scale_step.replace(now).map_or(0.,|prev|now.saturating_duration_since(prev).as_secs_f64());
        if self.detail.is_none() || self.mpp.max(self.requested_mpp)>CONTEXT_MPP+0.001 {return false;}
        let center=size.map(|v|f64::from(v)*0.5);
        let next=std::array::from_fn(|i|center[i]-(motion[i]*0.25).clamp(-center[i]*0.60,center[i]*0.60));
        let minimum=self.minimum_at(self.coordinates(),size,self.requested_mpp);
        let ahead=self.vector(next,size).map_or(minimum,|v|self.minimum_at(geographic(v),size,self.requested_mpp));
        let target=self.requested_mpp.max(minimum).max(ahead);
        if target==self.mpp {return false;}
        if (target-self.mpp).abs()<=0.01 {
            self.scale_at(anchor,target,size);
            return true;
        }
        let widening=target>self.mpp;
        if widening {self.last_widening=Some(now);}
        if !widening&&self.last_widening.is_some_and(|t|now.saturating_duration_since(t)<Duration::from_millis(155)) {return true;}
        let weight=1.-(-dt.min(0.065)*if widening {16.} else {6.}).exp();
        self.scale_at(anchor,self.mpp+(target-self.mpp)*weight,size);
        true
    }
    pub fn bearing_drag(&mut self, a:[f64;2],b:[f64;2],size:[u32;2]) {
        let compression=self.pitch().cos();
        if let Some(region) = &mut self.region {
            let angle = (b[0]-a[0])*0.008;
            let (sine,cosine) = angle.sin_cos();
            let mid = size.map(|n|f64::from(n)*0.5);
            let [x,y] = [mid[0]+region.offset[0]-a[0],(mid[1]+region.offset[1]-a[1])/compression];
            region.offset = [a[0]-mid[0]+x*cosine-y*sine,a[1]-mid[1]+(x*sine+y*cosine)*compression];
            region.bearing += angle;
            self.constrain_region(size);
            return;
        }
        let x=f64::from(size[0])*0.5;
        let y=f64::from(size[1])*0.5;
        let angle=(a[1]-y).atan2(a[0]-x)-(b[1]-y).atan2(b[0]-x);
        self.axes=self.axes.map(|v|rotation(v,self.axes[2],angle));
    }
    pub fn zoom(&mut self, point:[f64;2],factor:f64,size:[u32;2]) {
        let from=if factor>1. {self.mpp}else{self.requested_mpp.min(self.mpp)};
        let requested=(from*factor).clamp(1.5,Self::overview(size)/0.74);
        let minimum=self.minimum_at(self.coordinates(),size,requested);
        // Turning the wheel at a constrained boundary keeps the previous choice.
        if factor<1. && minimum>=self.mpp-0.01 && self.requested_mpp<self.mpp-0.01 {return;}
        self.requested_mpp=requested.max(minimum);
        self.scale_at(point,self.requested_mpp,size);
    }

    fn scale_at(&mut self,point:[f64;2],mpp:f64,size:[u32;2]) {
        let before=self.vector(point,size);
        self.mpp=mpp;
        self.update_level();
        if let Some(before)=before {
            if let Some(region) = &mut self.region {
                region.offset=[0.;2];
                if let Some(projected)=self.project_vec(before,size) {
                    self.region.as_mut().unwrap().offset=std::array::from_fn(|i|point[i]-projected[i]);
                }
                self.constrain_region(size);
            } else if let Some(after)=self.vector(point,size) {self.align(before,after);}
            self.update_level();
        }
    }
    pub fn toggle_oblique(&mut self, size:[u32;2]) {
        let center=size.map(|n|f64::from(n)*0.5);
        let anchor=self.vector(center,size);
        self.oblique=!self.oblique;
        if let Some(projected)=anchor.and_then(|v|self.project_vec(v,size)) {
            self.drag(projected,center,size);
        }
    }
    pub fn focus(&mut self,point:[f64;2],mpp:f64,size:[u32;2]) {
        self.region=None;
        let wanted=frame(point)[2];
        if dot(wanted,self.axes[2])< -0.99999 {self.axes=frame(point);}
        else {self.align(wanted,self.axes[2]);}
        self.mpp=if self.detail.is_some() {mpp.max(self.minimum_at(point,size,mpp))} else {mpp};
        self.requested_mpp=self.mpp;
        self.last_widening=None;
        self.update_level();
    }
    pub fn focus_at(&mut self, point:[f64;2], mpp:f64, offset:[f64;2], size:[u32;2]) {
        let mpp=if self.detail.is_some() {mpp.max(self.minimum_at(point,size,mpp))}else{mpp};
        self.axes=frame(point);
        self.mpp=mpp;
        self.requested_mpp=mpp;
        self.region=(mpp<=ENTER).then_some(Region {axes:self.axes,offset,bearing:0.});
        if self.region.is_some() {
            self.constrain_region(size);
        } else {
            let mid=size.map(|n|f64::from(n)*0.5);
            self.drag(mid,[mid[0]+offset[0],mid[1]+offset[1]],size);
        }
        self.update_level();
    }
    pub fn focus_toward(&mut self, target: [f64; 2], t: f64, destination_scale: f64, size:[u32;2]) {
        self.region=None;
        let axis = frame(target)[2];
        let start = self.axes[2];
        let angle = dot(start, axis).clamp(-1., 1.).acos();
        let route = cross(start, axis);
        let route_axis = if norm(route) < 1e-9 { self.axes[1] } else { unit(route) };
        self.axes = self.axes.map(|v| rotation(v, route_axis, angle * t));
        if t == 1. {
            self.axes = frame(target);
        } else {
            let north = frame(self.coordinates())[1];
            let correction = dot(north, self.axes[0]).atan2(dot(north, self.axes[1]));
            self.axes = self.axes.map(|v| rotation(v, self.axes[2], -correction * t));
        }
        self.mpp = (self.mpp.ln() + (destination_scale.ln() - self.mpp.ln()) * t).exp();
        if self.detail.is_some() {self.mpp=self.mpp.max(self.minimum_at(self.coordinates(),size,self.mpp));}
        self.requested_mpp=self.mpp;
        self.update_level();
    }
    pub fn north_up(&mut self) {
        self.axes=frame(self.coordinates());
        if let Some(region)=&mut self.region {
            *region=Region {axes:self.axes,offset:[0.;2],bearing:0.};
        }
    }
    pub fn constrain_region(&mut self, size:[u32;2]) {
        let Some(region)=&mut self.region else {return;};
        let half_diagonal = f64::from(size[0]).hypot(f64::from(size[1]))*0.5;
        let limit = (9_000_000./self.mpp-half_diagonal).max(0.);
        let distance = region.offset[0].hypot(region.offset[1]);
        if distance>limit {region.offset=region.offset.map(|value|value*limit/distance);}
        let mid=size.map(|n|f64::from(n)*0.5);
        let anchor=region.axes[2];
        let basis=region.basis();
        if let Some(center)=self.vector(mid,size) {
            let path=cross(anchor,center);
            let sine=norm(path);
            self.axes=if sine>1e-12 {
                basis.map(|v| rotation(v,scale(path,1./sine),sine.atan2(dot(anchor,center))))
            } else {basis};
        }
    }
    pub fn update_level(&mut self) {
        if self.mpp>=EXIT {
            self.region=None;
        } else if self.region.is_none() && self.mpp<=ENTER {
            let axes=frame(self.coordinates());
            let bearing=-dot(axes[1],self.axes[0]).atan2(dot(axes[1],self.axes[1]));
            self.region=Some(Region {axes,offset:[0.;2],bearing});
        }
        let point=self.coordinates();
        let local=inside(point,PARIS_CITY)||(self.local_models&&local_city(point));
        self.level=match self.level {
            _ if self.mpp>=EXIT => Level::World,
            _ if self.region.is_none() => Level::World,
            Level::Local if local && self.mpp<CITY_EXIT => Level::Local,
            _ if local && self.mpp<=CITY_ENTER => Level::Local,
            _ => Level::Region,
        };
    }
    pub fn extent(&self,size:[u32;2],extra:f64) -> f64 {
        let height=f64::from(size[1])/self.pitch().cos();
        let r=(f64::from(size[0]).hypot(height)*0.5+extra)*self.mpp/EARTH;
        if self.blend()==1. {r.min(PI)} else {r.min(1.).asin()}
    }
}

pub fn fit_bounds(bounds:[f64;4],size:[u32;2])->Option<([f64;2],f64)> {
    let [west, south, east, north] = bounds;
    if east <= west || north <= south {
        return None;
    }
    let lon = (west + east) / 2.;
    let center = [(lon + 180.).rem_euclid(360.) - 180., (south + north) / 2.];
    let axes = frame(center);
    let mut extent = [0f64; 2];
    for i in 0..=12 {
        for j in 0..=12 {
            let unit = frame([west+(east-west)*f64::from(i)/12., south+(north-south)*f64::from(j)/12.])[2];
            let [x, y, z] = axes.map(|axis| dot(axis, unit));
            if z <= 0. {
                return Some((center, Camera::overview(size)));
            }
            let chord = x.hypot(y);
            let factor = if chord > 1e-10 { chord.atan2(z)/chord } else { 1. };
            extent[0] = extent[0].max(x.abs()*factor);
            extent[1] = extent[1].max(y.abs()*factor);
        }
    }
    let viewport = [(f64::from(size[0])-80.).max(180.), (f64::from(size[1])-180.).max(240.)];
    let scale = 2.32*EARTH*(extent[0]/viewport[0]).max(extent[1]/viewport[1]);
    Some((center, scale.clamp(8., Camera::overview(size)/0.74)))
}

pub const PARIS_CITY:[f64;4]=[2.255,48.815,2.420,48.957];
pub fn inside([x,y]:[f64;2],[w,s,e,n]:[f64;4])->bool { w<=x && x<=e && s<=y && y<=n }

fn local_city(point:[f64;2])->bool {
    [PARIS_CITY,[-0.20,51.46,-0.06,51.55],[13.32,52.47,13.46,52.57],[31.08,29.92,31.20,30.03]]
        .into_iter().any(|bounds|inside(point,bounds))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn projection_and_zoom_anchor() {
        let size=[1280,720];
        let p=[905.,278.];
        for start in [[2.35,48.86],[179.95,4.],[-170.,89.9],[0.,-89.8]] {
            let mut camera=Camera::new(size);
            camera.focus(start,7300.,size);
            let anchor=camera.vector(p,size).unwrap();
            for _ in 0..20 {
                camera.zoom(p,1./1.22,size);
                let result=camera.project_vec(anchor,size).unwrap();
                assert!((result[0]-p[0]).abs()<0.001 && (result[1]-p[1]).abs()<0.001);
            }
            for _ in 0..20 {camera.zoom(p,1.22,size);}
            let restored=camera.project_vec(anchor,size).unwrap();
            assert!((restored[0]-p[0]).abs()<0.001);
            assert!(camera.level==Level::World);
        }
    }
}
