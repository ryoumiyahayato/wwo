use std::{fs,io,path::Path};

#[derive(Clone,Copy)]
pub struct Preferences {
    pub fullscreen:bool,
    pub volume:u8,
    pub english:bool,
}

impl Default for Preferences {
    fn default()->Self {Self{fullscreen:false,volume:80,english:false}}
}

impl Preferences {
    pub fn load(path:&Path)->Self {
        let mut value=Self::default();
        let Ok(contents)=fs::read_to_string(path) else{return value;};
        let mut section="";
        for line in contents.lines().map(str::trim) {
            if line.starts_with('[') {section=line;continue;}
            let Some((key,raw))=line.split_once('=') else{continue;};
            let raw=raw.trim();
            match (section,key.trim()) {
                ("[display]","fullscreen")=>value.fullscreen=raw=="true",
                ("[display]","locale")=>value.english=raw.trim_matches('"').starts_with("en"),
                ("[audio]","volume")=>{
                    if let Some(n)=raw.parse::<f64>().ok().filter(|n|n.is_finite()) {
                        value.volume=(n.clamp(0.,1.)*100.).round() as u8;
                    }
                }
                _=>{}
            }
        }
        value
    }

    pub fn locale(self)->&'static str {
        if self.english {"en"} else {"zh_CN"}
    }

    pub fn save(self,path:&Path)->io::Result<()> {
        let mut text=match fs::read_to_string(path) {
            Ok(value)=>value,
            Err(error) if error.kind()==io::ErrorKind::NotFound=>String::new(),
            Err(error)=>return Err(error),
        };
        set(&mut text,"[display]","fullscreen",&self.fullscreen.to_string());
        set(&mut text,"[display]","locale",&format!("\"{}\"",self.locale()));
        set(&mut text,"[audio]","volume",&format!("{:.2}",f64::from(self.volume)/100.));
        let temporary=path.with_extension("cfg.rust-tmp");
        fs::write(&temporary,text)?;
        fs::rename(temporary,path)
    }
}

fn set(text:&mut String,section:&str,key:&str,value:&str) {
    let mut lines:Vec<_>=text.lines().collect();
    let line=format!("{key}={value}");
    if let Some(start)=lines.iter().position(|n|n.trim()==section) {
        let end=lines[start+1..].iter().position(|n|n.trim_start().starts_with('['))
            .map_or(lines.len(),|offset|start+1+offset);
        let existing=lines[start+1..end].iter().position(|line|line.split_once('=')
            .is_some_and(|(name,_)|name.trim()==key));
        if let Some(offset)=existing {lines[start+1+offset]=&line;}
        else {lines.insert(start+1,&line);}
    } else {
        if !lines.is_empty(){lines.push("");}
        lines.extend([section,&line]);
    }
    *text=lines.join("\n")+"\n";
}
