use std::{
    fs::File,
    hash::{BuildHasher, RandomState},
    path::{Path, PathBuf},
};

use serde::Deserialize;

use crate::{compact::Raster, font};

const ORIGINAL: &str = "paris-rain";

pub struct Themes {
    works: Vec<Work>,
    current: Option<usize>,
    fixed: Option<String>,
    last: Option<String>,
    pub aspect: f32,
}

#[derive(Deserialize)]
struct Work {
    id: String,
    title_zh: String,
    title: String,
}

impl Themes {
    pub fn open(root: &Path, fixed: Option<String>, last: Option<String>) -> Self {
        let catalogue = root.join("menu-themes/catalogue.json");
        let mut works: Vec<Work> = match File::open(&catalogue) {
            Ok(file) => serde_json::from_reader(file).unwrap_or_else(|error| {
                eprintln!("Menu themes {}: {error}", catalogue.display());
                Vec::new()
            }),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Vec::new(),
            Err(error) => {
                eprintln!("Menu themes {}: {error}", catalogue.display());
                Vec::new()
            }
        };
        works.retain(|work| {
            !work.id.is_empty()
                && work.id.bytes().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
                && Self::path(root, &work.id).is_file()
        });
        if !works.iter().any(|work| work.id == ORIGINAL) && Self::path(root, ORIGINAL).is_file() {
            works.insert(0, Work {
                id: ORIGINAL.into(), title_zh: "巴黎街道·雨天".into(), title: "Paris Street; Rainy Day".into(),
            });
        }
        let fixed = fixed.filter(|id| works.iter().any(|work| &work.id == id));
        Self { works, current: None, fixed, last, aspect: 1. }
    }

    fn path(root: &Path, id: &str) -> PathBuf {
        if id == ORIGINAL { root.join("menu-painting.png") }
        else { root.join("menu-themes").join(format!("{id}.png")) }
    }

    fn select(&mut self, root: &Path, index: usize) -> Option<Raster> {
        let work = self.works.get(index)?;
        let path = Self::path(root, &work.id);
        match font(&path) {
            Ok(image) => {
                self.current = Some(index);
                self.last = Some(work.id.clone());
                self.aspect = image.size[0] as f32 / image.size[1] as f32;
                Some(image)
            }
            Err(error) => {
                eprintln!("Menu painting {}: {error}", path.display());
                None
            }
        }
    }

    pub fn start(&mut self, root: &Path) -> Option<Raster> {
        if let Some(index) = self.works.iter().position(|work| Some(&work.id) == self.fixed.as_ref()) {
            if let Some(image) = self.select(root, index) {
                return Some(image);
            }
            self.fixed = None;
        }
        let indices: Vec<_> = (0..self.works.len())
            .filter(|&index| Some(&self.works[index].id) != self.last.as_ref()).collect();
        if !indices.is_empty() {
            let start = RandomState::new().hash_one("menu painting") as usize % indices.len();
            for position in 0..indices.len() {
                if let Some(image) = self.select(root, indices[(start + position) % indices.len()]) {
                    return Some(image);
                }
            }
        }
        let last = self.works.iter().position(|work| Some(&work.id) == self.last.as_ref())?;
        self.select(root, last)
    }

    pub fn change(&mut self, root: &Path) -> Option<Raster> {
        let current = self.current?;
        for offset in 1..self.works.len() {
            let index = (current + offset) % self.works.len();
            if let Some(image) = self.select(root, index) {
                if self.fixed.is_some() {
                    self.fixed = self.last.clone();
                }
                return Some(image);
            }
        }
        None
    }

    pub fn set_fixed(&mut self, fixed: bool) {
        self.fixed = if fixed { self.last.clone() } else { None };
    }

    pub fn preference(&self) -> (Option<&str>, Option<&str>) {
        (self.fixed.as_deref(), self.last.as_deref())
    }

    pub fn reload(&self, root: &Path) -> std::io::Result<Option<(Self,Raster)>> {
        let catalogue=root.join("menu-themes/catalogue.json");
        let file=match File::open(&catalogue) {
            Ok(file)=>file,
            Err(error) if error.kind()==std::io::ErrorKind::NotFound && !Self::path(root,ORIGINAL).is_file()=>return Ok(None),
            Err(error) if error.kind()==std::io::ErrorKind::NotFound=>{
                let mut themes=Self::open(root,self.fixed.clone(),self.last.clone());
                let image=themes.start(root).ok_or_else(||std::io::Error::other("Cannot read the menu painting"))?;
                return Ok(Some((themes,image)));
            }
            Err(error)=>return Err(error),
        };
        let _:Vec<Work>=serde_json::from_reader(file)?;
        let mut themes=Self::open(root,self.fixed.clone(),self.last.clone());
        let image=match self.last.as_deref() {
            Some(previous)=>themes.works.iter().position(|work|work.id==previous)
                .and_then(|index|themes.select(root,index)),
            None=>themes.start(root),
        }.ok_or_else(||std::io::Error::other("Cannot read the current menu painting or catalogue"))?;
        Ok(Some((themes,image)))
    }

    pub fn can_change(&self) -> bool {
        self.works.len() > 1 && self.current.is_some()
    }

    pub fn title(&self, english: bool) -> Option<&str> {
        let work = self.works.get(self.current?)?;
        Some(if english { &work.title } else { &work.title_zh })
    }
}
