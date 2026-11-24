#![cfg_attr(not(debug_assertions),windows_subsystem="windows")]
mod mechanical;
mod camera;
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
    if let Err(e)=host::run(){
        #[cfg(windows)]
        if std::env::args_os().any(|arg|arg=="--terrain-review"||arg=="--background") {eprintln!("{e}");}
        else {desktop_start::show_error(&e.to_string());}
        #[cfg(not(windows))]
        eprintln!("{e}");
        std::process::exit(1);
    }
}
