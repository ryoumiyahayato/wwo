use crate::compact::Vertex;
use serde::Deserialize;
use std::{collections::HashMap, fs::File, io, path::Path};

#[derive(Deserialize)]
pub struct Atlas(HashMap<String, [f32; 3]>);

impl Atlas {
    pub fn open(path: &Path) -> io::Result<Self> {
        Ok(serde_json::from_reader(File::open(path)?)?)
    }

    pub fn glyph(&self, variant: usize, ch: char) -> [f32; 3] {
        self.0[&format!("{variant}:{}", if ch.is_ascii_graphic() || ch == ' ' { ch } else { '?' })]
    }
}

#[derive(Default)]
pub struct Mesh {
    pub vertices: Vec<Vertex>,
    pub indices: Vec<u32>,
}

impl Mesh {
    pub fn image(&mut self,[x,y,w,h]:[f32;4],[u,v,a,b]:[f32;4],color:[u8;4]) {
        self.polygon(&[[x,y],[x+w,y],[x+w,y+h],[x,y+h]],[[u,v],[a,v],[a,b],[u,b]],color);
    }
    pub fn shape(&mut self, points:&[[f32;2]], color:[u8;4]) {
        let start=self.vertices.len() as u32;
        self.vertices.extend(points.iter().map(|&position|Vertex{position,color,uv:[0.;2]}));
        for i in 2..points.len() as u32 {
            self.indices.extend([start,start+i-1,start+i]);
        }
    }
    fn polygon(&mut self, points: &[[f32; 2]], uv: [[f32; 2]; 4], color: [u8; 4]) {
        let start = self.vertices.len() as u32;
        self.vertices.extend(points.iter().zip(uv).map(|(&position, uv)| Vertex { position, color, uv }));
        for i in 2..points.len() as u32 {
            self.indices.extend([start, start + i - 1, start + i]);
        }
    }

    pub fn rect(&mut self, x: f32, y: f32, w: f32, h: f32, color: [u8; 4]) {
        self.polygon(&[[x, y], [x + w, y], [x + w, y + h], [x, y + h]], [[0.; 2]; 4], color);
    }

    pub fn line(&mut self, [x,y]:[f32;2], [a,b]:[f32;2], width:f32, color:[u8;4]) {
        let [dx,dy]=[a-x,b-y];
        let length=dx.hypot(dy);
        if length<0.02 {return;}
        let [u,v]=[-dy*width/(2.*length),dx*width/(2.*length)];
        self.polygon(&[[x+u,y+v],[a+u,b+v],[a-u,b-v],[x-u,y-v]],[[0.;2];4],color);
    }

    pub fn flag(&mut self, area: [f32; 4], slot: u8) {
        let [x,y,w,h]=area;
        let center=[f32::from(slot%16)+0.5,f32::from(slot/16)+0.5];
        let [l,t]=center.map(|c|(c-0.495)/16.);
        let [r,b]=center.map(|c|(c+0.495)/16.);
        self.polygon(&[[x,y-h*0.125],[x+w,y-h*0.125],[x+w,y+h*1.125],[x,y+h*1.125]],[[l,t],[r,t],[r,b],[l,b]],[255;4]);
    }
    pub fn flag_wave(&mut self, [x, y, w, h]: [f32; 4], slot: u8, seconds: f32, opacity: f32) {
        let center = [f32::from(slot % 16) + 0.5, f32::from(slot / 16) + 0.5];
        let [u, v] = center.map(|c| (c - 0.495) / 16.);
        let [r, b] = center.map(|c| (c + 0.495) / 16.);
        let wave = |fraction: f32| if seconds == 0. { 0. }
            else { (seconds * 2.4 - fraction * 5.4).sin() * fraction * 2.2 };
        for strip in 0..8 {
            let a = strip as f32 / 8.;
            let d = (strip + 1) as f32 / 8.;
            let [left, right] = [x + w * a, x + w * d];
            let [top_left, top_right] = [y - h * 0.125 + wave(a), y - h * 0.125 + wave(d)];
            let [ul, ur] = [u + (r - u) * a, u + (r - u) * d];
            self.polygon(&[[left, top_left], [right, top_right], [right, top_right + h * 1.25], [left, top_left + h * 1.25]],
                [[ul, v], [ur, v], [ur, b], [ul, b]], [255, 255, 255, opacity as u8]);
        }
    }
    pub fn text(&mut self, atlas: &Atlas, variant: usize, text: &str, [mut x, y]: [f32; 2], color: [u8; 4]) {
        let size = [17., 23., 35.][variant];
        for ch in text.chars() {
            let [u, v, advance] = atlas.glyph(variant, ch);
            if ch != ' ' {
                let w = advance.ceil() + 5.;
                let h = size + 8.;
                let left = (u + 3.) / 1024.;
                let top = (v + 3.) / 1024.;
                let right = left + w / 1024.;
                let bottom = top + h / 1024.;
                self.polygon(
                    &[[x, y], [x + w, y], [x + w, y + h], [x, y + h]],
                    [[left, top], [right, top], [right, bottom], [left, bottom]], color,
                );
            }
            x += advance;
        }
    }
}
