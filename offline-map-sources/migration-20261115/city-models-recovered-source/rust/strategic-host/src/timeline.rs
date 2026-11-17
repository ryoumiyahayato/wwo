use crate::compact::REGIONS;
use serde::Deserialize;
use std::{collections::BTreeMap, fmt, io, path::Path};

pub const MAX_SITES: usize = 12;
const MAX_EVENTS: usize = 2048;
const UNDO_LIMIT: usize = 32;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd)]
#[serde(deny_unknown_fields)]
pub struct Date {
    pub year: i32,
    pub month: u32,
    pub day: u32,
}

impl Date {
    pub const fn new(year: i32, month: u32, day: u32) -> Self { Self { year, month, day } }

    fn month_length(self) -> u32 { wwo_map_lab::calendar::month_length(self.year, self.month) }

    pub fn valid(self) -> bool {
        (1..=9999).contains(&self.year) && (1..=self.month_length()).contains(&self.day)
    }

    pub fn ordinal(self) -> u32 {
        self.day + (1..self.month).map(|m| Self::new(self.year,m,1).month_length()).sum::<u32>()
    }

    pub fn season_day(self) -> f32 {
        (self.ordinal()-1) as f32 * 365.0 / Self::new(self.year,12,31).ordinal() as f32 + 1.0
    }

    pub fn offset(mut self, days: i32) -> Self {
        for _ in 0..days.unsigned_abs() {
            if days > 0 {
                if self.day < self.month_length() { self.day += 1; }
                else if self.month < 12 { self.month += 1; self.day = 1; }
                else if self.year < 9999 { self = Self::new(self.year+1,1,1); }
            } else if self.day > 1 {
                self.day -= 1;
            } else if self.month > 1 || self.year > 1 {
                if self.month > 1 { self.month -= 1; } else { self.year -= 1; self.month = 12; }
                self.day = self.month_length();
            }
        }
        self
    }
}

impl fmt::Display for Date {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f,"{:04}-{:02}-{:02}",self.year,self.month,self.day)
    }
}

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all="snake_case")]
pub enum Use {
    #[default]
    Forest,
    Construction,
    Urban,
}

impl Use {
    pub fn next(self) -> Self {
        match self { Self::Forest => Self::Construction, Self::Construction => Self::Urban, Self::Urban => Self::Forest }
    }
    pub fn previous(self) -> Self {
        match self { Self::Forest => Self::Urban, Self::Urban => Self::Construction, Self::Construction => Self::Forest }
    }
    pub fn label(self) -> &'static str {
        match self { Self::Forest => "Forest", Self::Construction => "Construction", Self::Urban => "Simulated district" }
    }
    pub fn code(self) -> f32 {
        match self { Self::Forest => 0., Self::Construction => 1., Self::Urban => 2. }
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Site {
    pub id: String,
    pub label: String,
    pub region: String,
    pub center_lon_lat: [f64;2],
    pub radius_m: [f32;2],
    pub layout: u8,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Change {
    pub object_id: String,
    pub effective: Date,
    pub land_use: Use,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    pub schema: u32,
    pub date: Date,
    pub region_id: String,
    pub changes: Vec<Change>,
}

pub struct Timeline {
    pub date: Date,
    pub sites: Vec<Site>,
    history: Vec<Vec<(Date,Use)>>,
    overrides: BTreeMap<usize,Vec<Use>>,
}

impl Timeline {
    pub fn load_sites(path: &Path, bounds: &[[f64;4]]) -> io::Result<Self> {
        let sites: Vec<Site> = read(path,64*1024)?;
        if sites.len()>MAX_SITES { return Err(invalid("too many land-use objects")); }
        for (i,site) in sites.iter().enumerate() {
            let region = region_index(&site.region)?;
            let [w,s,e,n] = bounds[region];
            let [x,y] = site.center_lon_lat;
            if site.id.is_empty() || site.label.is_empty() || sites[..i].iter().any(|s| s.id==site.id)
                || !(w<x && x<e && s<y && y<n) || site.layout>2
                || !site.radius_m.iter().all(|r| (20. ..=2500.).contains(r)) {
                return Err(invalid("invalid land-use object"));
            }
        }
        let history = vec![Vec::new();sites.len()];
        Ok(Self {date:Date::new(1900,7,20),sites,history,overrides:BTreeMap::new()})
    }

    pub fn apply(&mut self, input: Snapshot) -> io::Result<usize> {
        if input.schema!=1 || !input.date.valid() || input.changes.len()>MAX_EVENTS {
            return Err(invalid("invalid schema, date or event count"));
        }
        let region = region_index(&input.region_id)?;
        let mut history = vec![Vec::new();self.sites.len()];
        for event in input.changes {
            if !event.effective.valid() { return Err(invalid("invalid effective date")); }
            let object = self.sites.iter().position(|s| s.id==event.object_id)
                .ok_or_else(|| invalid(&format!("unknown object {}",event.object_id)))?;
            history[object].push((event.effective,event.land_use));
        }
        for events in &mut history {
            events.sort_unstable_by_key(|event| event.0);
            if events.windows(2).any(|pair| pair[0].0==pair[1].0) {
                return Err(invalid("duplicate effective date for an object"));
            }
        }
        self.history = history;
        self.date = input.date;
        self.overrides.clear();
        Ok(region)
    }

    pub fn at(&self, index: usize) -> Use {
        self.overrides.get(&index).and_then(|stack| stack.last().copied()).unwrap_or_else(|| {
            let events = &self.history[index];
            events[..events.partition_point(|(date,_)| *date<=self.date)].last()
                .map_or(Use::Forest,|(_,land_use)| *land_use)
        })
    }

    pub fn set_date(&mut self, date: Date) {
        self.date = date;
        self.overrides.clear();
    }

    pub fn edit(&mut self,index: usize, reverse: bool) {
        let current = self.at(index);
        let stack = self.overrides.entry(index).or_default();
        if stack.len()==UNDO_LIMIT { stack.remove(0); }
        stack.push(if reverse { current.previous() } else { current.next() });
    }

    pub fn undo(&mut self,index: usize) {
        if let Some(stack) = self.overrides.get_mut(&index) {
            stack.pop();
            if stack.is_empty() { self.overrides.remove(&index); }
        }
    }

    pub fn region_sites<'a>(&'a self, region: &'a str) -> impl Iterator<Item=(usize,&'a Site)>+'a {
        self.sites.iter().enumerate().filter(move |(_,site)| site.region==region)
    }
}

fn region_index(id: &str) -> io::Result<usize> {
    REGIONS.iter().position(|region| *region==id).ok_or_else(|| invalid("unknown region ID"))
}

fn invalid(detail: &str) -> io::Error { io::Error::new(io::ErrorKind::InvalidData,detail) }

pub fn read<T: serde::de::DeserializeOwned>(path: &Path, limit: usize) -> io::Result<T> {
    use std::io::Read;
    let file = std::fs::File::open(path)?;
    let mut data = Vec::new();
    file.take(limit as u64+1).read_to_end(&mut data)?;
    if data.len()>limit { return Err(invalid("state file too large")); }
    Ok(serde_json::from_slice(&data)?)
}
