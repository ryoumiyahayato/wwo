//! Display state only. World time remains owned by R68.
use std::time::Instant;
pub const ANGLES:[f32;4]=[174.,148.,122.,96.];
#[derive(Default)]
pub struct Mechanical {
 pub angle:Option<f32>, pub phase:f64, pub hidden:bool, pub serial:u64,
 pending:Option<(u64,f32)>, target:f32, from:f32, elapsed:f32, last:Option<Instant>,
}
impl Mechanical {
 pub fn moving(&self)->bool {self.elapsed<0.09 && self.from!=self.target || self.pending.is_some()}
 pub fn selected(&self,confirmed:usize)->usize {if self.pending.is_some(){ANGLES.iter().position(|a|*a==self.target).unwrap_or(confirmed)}else{confirmed}}
 pub fn request(&mut self,index:usize,drag:Option<f32>)->u64 {
  if let Some(a)=drag {self.angle=Some(a);}
  self.serial+=1;self.aim(ANGLES[index]);self.pending=Some((self.serial,0.));self.serial
 }
 fn aim(&mut self,target:f32){
  if self.angle.is_none(){self.angle=Some(target);}
  self.from=self.angle.unwrap();self.target=target;self.elapsed=0.;
 }
 pub fn update(&mut self,now:Instant,index:usize,ack:u64,drag:Option<f32>,speed:u32){
  let dt=self.last.replace(now).map_or(0.,|t|now.duration_since(t).as_secs_f32().min(0.1));
  self.serial=self.serial.max(ack);
  self.phase+=f64::from(dt)*f64::from(speed)*0.075;
  if self.angle.is_none(){self.aim(ANGLES[index]);}
  if let Some((id,age))=self.pending {
   if ack>=id || age>2. {self.pending=None;} else {self.pending=Some((id,age+dt));}
  }
  if let Some(a)=drag {self.angle=Some(a);self.from=a;self.elapsed=0.;return;}
  if self.pending.is_none() && self.target!=ANGLES[index]{self.aim(ANGLES[index]);}
  self.elapsed=(self.elapsed+dt).min(0.09);let t=self.elapsed/0.09;
  self.angle=Some(self.from+(self.target-self.from)*t*t*(3.-2.*t));
 }
}
#[cfg(test)] mod tests {
 use super::*;
 #[test] fn aligned_release_and_repeated_confirmation_never_move_the_hand(){
  let mut m=Mechanical::default();let t=Instant::now();m.update(t,0,0,None,0);
  m.update(t+std::time::Duration::from_millis(10),0,0,Some(148.),0);
  let id=m.request(1,Some(148.));
  for (ms,index,ack) in [(20,0,0),(60,0,0),(120,1,id),(200,1,id),(300,1,id)] {
   m.update(t+std::time::Duration::from_millis(ms),index,ack,None,1);
   assert_eq!(m.angle,Some(148.));
  }
 }
 #[test] fn release_stale_ack_pause(){
  let mut m=Mechanical::default();let t=Instant::now();
  m.update(t,0,0,None,0);let id=m.request(3,Some(98.));
  m.update(t+std::time::Duration::from_millis(30),0,0,None,0);
  assert!(m.angle.unwrap()<98. && m.angle.unwrap()>96.);
  m.update(t+std::time::Duration::from_millis(100),3,id,None,4);assert_eq!(m.angle,Some(96.));
  let p=m.phase;m.update(t+std::time::Duration::from_millis(150),0,id,None,0);assert_eq!(m.phase,p);
 }
 #[test] fn drag_and_rejection(){
  let mut m=Mechanical::default();let t=Instant::now();
  m.update(t,0,0,Some(110.),1);assert_eq!(m.angle,Some(110.));let id=m.request(3,Some(110.));
  m.update(t+std::time::Duration::from_millis(100),0,id,None,0);assert_eq!(m.angle,Some(174.));
 }
 #[test] fn newest_request_wins_during_rapid_changes(){
  let mut m=Mechanical::default();let t=Instant::now();m.update(t,0,0,None,0);
  let old=m.request(1,None);let newest=m.request(3,None);
  m.update(t+std::time::Duration::from_millis(90),1,old,None,1);
  assert_eq!(m.angle,Some(96.));assert_eq!(m.selected(1),3);
  m.update(t+std::time::Duration::from_millis(100),3,newest,None,4);
  assert_eq!(m.angle,Some(96.));
 }
 #[test] fn cancel_drag_and_lost_request_restore_confirmed(){
  let mut m=Mechanical::default();let t=Instant::now();m.update(t,0,0,None,0);
  m.update(t+std::time::Duration::from_millis(10),0,0,Some(120.),0);
  m.update(t+std::time::Duration::from_millis(100),0,0,None,0);assert_eq!(m.angle,Some(174.));
  m.request(3,None);
  for i in 2..=25 {m.update(t+std::time::Duration::from_millis(i*100),0,0,None,0);}
  assert_eq!(m.angle,Some(174.));
 }
 #[test] fn phase_speed_ratios_and_pause_resume(){
  let t=Instant::now();let mut m=Mechanical::default();m.update(t,0,0,None,0);
  m.update(t+std::time::Duration::from_millis(100),1,0,None,1);let one=m.phase;
  m.update(t+std::time::Duration::from_millis(200),2,0,None,2);assert!((m.phase-one*3.).abs()<1e-8);
  m.update(t+std::time::Duration::from_millis(300),3,0,None,4);assert!((m.phase-one*7.).abs()<1e-8);
  m.update(t+std::time::Duration::from_millis(400),0,0,None,0);assert!((m.phase-one*7.).abs()<1e-8);
  m.update(t+std::time::Duration::from_millis(500),1,0,None,1);assert!((m.phase-one*8.).abs()<1e-8);
 }

}
