use crate::terrain;
#[cfg(windows)]
use crate::{desktop_start, native_start};
use std::{io, path::PathBuf};

pub(super) struct Config {
    pub(super) root: PathBuf,
    pub(super) world: Option<PathBuf>,
    pub(super) requests: Option<PathBuf>,
    pub(super) scenario: Option<PathBuf>,
    pub(super) observe: Option<PathBuf>,
    pub(super) managed: bool,
    pub(super) preferences: Option<PathBuf>,
    pub(super) terrain_candidate: Option<PathBuf>,
    pub(super) background: bool,
    pub(super) terrain_review: bool,
    pub(super) terrain_selection: terrain::LayerSelection,
    pub(super) terrain_layer_candidate: Option<PathBuf>,
    pub(super) terrain_close_sample: Option<PathBuf>,
    pub(super) terrain_detail: Option<PathBuf>,
    pub(super) battlefield_data: Option<PathBuf>,
    #[cfg(windows)]
    pub(super) native: Option<native_start::NativeSession>,
    #[cfg(windows)]
    pub(super) desktop: Option<desktop_start::DesktopSession>,
}

impl Config {
    pub(super) fn parse()->io::Result<Self> {
        let home=std::env::current_exe()?.parent().unwrap().to_owned();
        let mut result=Self{root:home.join("data"),world:None,requests:None,scenario:None,observe:None,managed:false,preferences:None,terrain_candidate:None,background:false,
            terrain_review:false,terrain_selection:terrain::LayerSelection::Auto,terrain_layer_candidate:None,
            terrain_close_sample:None,terrain_detail:None,battlefield_data:None,
            #[cfg(windows)] desktop:None,
            #[cfg(windows)] native:None};
        let mut args=std::env::args_os().skip(1).peekable();
        #[cfg(windows)]
        let mut start_game=false;
        #[cfg(windows)]
        let mut map_comparison=false;
        #[cfg(windows)]
        let mut r68_comparison=false;
        while let Some(arg)=args.next() {
            let path=|args:&mut std::iter::Peekable<std::iter::Skip<std::env::ArgsOs>>| args.next().map(PathBuf::from).ok_or_else(||io::Error::other("missing argument path"));
            match arg.to_str() {
                Some("--data")=>result.root=path(&mut args)?,
                Some("--world-state")=>result.world=Some(path(&mut args)?),
                Some("--requests")=>result.requests=Some(path(&mut args)?),
                Some("--observe")=>result.observe=Some(path(&mut args)?),
                Some("--background")=>result.background=true,
                Some("--preferences")=>result.preferences=Some(path(&mut args)?),
                Some("--terrain-candidate")=>result.terrain_candidate=Some(path(&mut args)?),
                Some("--terrain-review")=>result.terrain_review=true,
                Some("--terrain-layer-candidate")=>result.terrain_layer_candidate=Some(path(&mut args)?),
                Some("--terrain-close-sample")=>result.terrain_close_sample=Some(path(&mut args)?),
                Some("--terrain-detail")=>result.terrain_detail=Some(path(&mut args)?),
                Some("--battlefield-data")=>result.battlefield_data=Some(path(&mut args)?),
                Some(flag @ ("--terrain-level"|"--terrain-max-level"))=>{
                    if !matches!(result.terrain_selection,terrain::LayerSelection::Auto){
                        return Err(io::Error::other("choose one terrain layer option"));
                    }
                    let z=args.next().and_then(|v|v.to_str()?.parse::<u32>().ok()).filter(|&z|z<=7)
                        .ok_or_else(||io::Error::other("terrain level must be an integer from 0 to 7"))?;
                    result.terrain_selection=if flag=="--terrain-level" {terrain::LayerSelection::Exact(z)} else {terrain::LayerSelection::Maximum(z)};
                }
                Some("--land-test")=>result.scenario=Some(home.join("scenario-land-test.json")),
                Some("--formal-menu")=>result.managed=true,
                #[cfg(windows)]
                Some("--play")=>start_game=true,
                #[cfg(windows)]
                Some("--map-comparison")=>map_comparison=true,
                #[cfg(windows)]
                Some("--r68")=>{start_game=true;r68_comparison=true;},
                _=>return Err(io::Error::other(format!("unknown argument {arg:?}"))),
            }
        }
        if result.terrain_review {
            #[cfg(windows)]
            if start_game||map_comparison {return Err(io::Error::other("--terrain-review has its own map entry point"));}
            if result.world.is_some()||result.requests.is_some()||result.scenario.is_some()||result.managed||result.preferences.is_some() {
                return Err(io::Error::other("--terrain-review cannot load world sessions or preferences"));
            }
            if result.observe.is_none(){return Err(io::Error::other("--terrain-review requires --observe"));}
            if result.terrain_detail.is_some() && (result.terrain_close_sample.is_some()
                || !matches!(result.terrain_selection,terrain::LayerSelection::Auto)) {
                return Err(io::Error::other("--terrain-detail uses automatic terrain selection"));
            }
            result.background=true;
            if result.terrain_candidate.is_none(){result.terrain_candidate=Some(result.root.join(terrain::COMPACT_VERSION));}
            return Ok(result);
        }
        if !matches!(result.terrain_selection,terrain::LayerSelection::Auto)||result.terrain_layer_candidate.is_some()
            ||result.terrain_close_sample.is_some() {
            return Err(io::Error::other("terrain layer options require --terrain-review"));
        }
        #[cfg(windows)]
        let standalone=map_comparison||result.world.is_some()||result.requests.is_some()||result.scenario.is_some()||result.managed;
        #[cfg(windows)]
        if start_game||!standalone {
            if standalone{return Err(io::Error::other("--play and --r68 manage their own world; standalone map options cannot be combined with them"));}
            result.managed=true;
            if r68_comparison {
                let desktop=desktop_start::DesktopSession::start(&home)?;
                result.world=Some(desktop.state.clone());result.requests=Some(desktop.requests.clone());
                result.preferences=Some(desktop.preferences.clone());
                result.desktop=Some(desktop);
            } else {
                let native=native_start::NativeSession::start(&result.root)?;
                if result.preferences.is_none(){result.preferences=Some(native.preferences.clone());}
                result.native=Some(native);
                return Ok(result);
            }
        }
        if result.world.is_some() && result.scenario.is_some(){return Err(io::Error::other("world input and isolated land test are exclusive"));}
        if result.managed&&(result.world.is_none()||result.requests.is_none()){return Err(io::Error::other("formal menu requires bridge snapshot and requests paths"));}
        Ok(result)
    }

    pub(super) fn terrain_root(&self) -> (PathBuf, bool) {
        if let Some(path)=&self.terrain_candidate {return (path.clone(),true);}
        let hydrology=self.root.join(terrain::HYDROLOGY_DIRECTORY);
        if terrain::compact_files_present(&hydrology)
            && ["water-geometry.qwg","hydrology-color.qhw","river-centrelines.qhl"]
                .iter().all(|name|hydrology.join(name).is_file()) {return (hydrology,true);}
        let compact=self.root.join(terrain::COMPACT_VERSION);
        if terrain::compact_files_present(&compact) {return (compact,true);}
        (self.root.join(terrain::VERSION),false)
    }
}
