#![cfg_attr(windows, windows_subsystem = "windows")]
mod mechanical;
mod build_identity;
mod camera;
mod capital_landmarks;
mod city_kit;
mod city_models;
mod city_parks;
#[cfg(windows)]
mod desktop_start;
#[cfg(windows)]
mod native_start;
mod compact;
mod formal_ui;
mod market_ui;
mod lobby;
mod prologue_ui;
mod landmarks;
mod map_facilities;
mod map_markers;
mod map_release;
mod menu_theme;
mod interface;
mod overlay;
mod pop_debug_ui;
mod politics;
mod render;
mod state;
mod terrain;
mod terrain_detail;
mod transport_scene;
mod transport_ui;
mod hydrology;
mod landscape;
mod landscape_cover;
mod landscape_models;
mod timeline;
mod ui;
mod resource_map;
mod world;
mod battle_render;
mod battle_view;
mod host;

use camera::Level;
use host::{decode_rgba, font, Diagnostics, HostEvent};

fn main() {
    let second = std::env::args_os().nth(1);
    #[cfg(windows)]
    if second.is_some() {
        desktop_start::attach_parent_console();
    }
    if second.is_some_and(|arg| arg == "--version") {
        println!("wwo-map-lab {}", build_identity::display());
        return;
    }
    let result = || -> Result<(), Box<dyn std::error::Error>> {
        #[cfg(windows)]
        if !std::env::args_os().any(|arg|arg=="--terrain-review"||arg=="--background") {
            build_identity::check()?;
        }
        host::run()
    };
    if let Err(e)=result(){
        #[cfg(windows)]
        {
            desktop_start::write_runtime_log(&e.to_string());
            desktop_start::notify_program_update(&format!("error: {e}"));
        }
        #[cfg(windows)]
        if std::env::args_os().any(|arg|arg=="--terrain-review"||arg=="--background") {eprintln!("{e}");}
        else {desktop_start::show_error(&e.to_string());}
        #[cfg(not(windows))]
        eprintln!("{e}");
        std::process::exit(1);
    }
}
