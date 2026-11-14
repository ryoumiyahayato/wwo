use crate::{compact::Pack, world::World};
use std::{
    collections::HashSet,
    fs::File,
    io::{self, BufReader, Read},
    path::{Path, PathBuf},
};

pub const VERSION: &str = "regional-2026-11-14";
pub const TILE_SIGNATURE: &[u8; 8] = b"WWORGN1\0";
const ART_FILES: [&str; 4] = [
    "political-flags-hd.png",
    "galactic-chart.png",
    "ocean-detail-r68.png",
    "ocean-ice-r68.png",
];

pub fn root(data: &Path) -> PathBuf {
    data.join("maps").join(VERSION)
}

pub fn open_art(root: &Path, name: &str) -> io::Result<BufReader<File>> {
    let path = root.join(format!("{name}.wwo"));
    let read = || {
        let mut file = File::open(&path)?;
        let mut version = [0; VERSION.len()];
        file.read_exact(&mut version)?;
        if version != VERSION.as_bytes() {
            return Err(io::Error::other("地图图像版本不匹配"));
        }
        Ok(BufReader::new(file))
    };
    read().map_err(|e| io::Error::other(format!("{} · {e}", path.display())))
}

pub fn open(root: &Path) -> io::Result<World> {
    let check = || {
        let world = World::open(&root.join("world.json"))?;
        if world.map_release != VERSION {
            return Err(io::Error::other(format!(
                "目录版本不匹配，实际为 {:?}",
                world.map_release,
            )));
        }
        if world.tiles.len() != 638
            || world.tiles[0].path != "world.wcm"
            || world.tiles.iter().filter(|t| t.path.starts_with("tiles/r68-surface-")).count() != 282
        {
            return Err(io::Error::other("地图分片目录不完整"));
        }
        let mut paths = HashSet::new();
        for (index, tile) in world.tiles.iter().enumerate() {
            let name = if index == 0 { &tile.path } else {
                tile.path.strip_prefix("tiles/").unwrap_or_default()
            };
            if !name.ends_with(".wcm")
                || !name.bytes().all(|c| c.is_ascii_alphanumeric() || b"-_+.".contains(&c))
                || !paths.insert(&tile.path)
            {
                return Err(io::Error::other(format!("无效的地图分片路径 {}", tile.path)));
            }
            let path = root.join(&tile.path);
            Pack::check_signature(&path, TILE_SIGNATURE)?;
        }
        for name in ART_FILES {
            open_art(root, name)?;
        }
        Ok(world)
    };
    check().map_err(|e| {
        io::Error::other(format!("正式地图需要 {VERSION}。{} · {e}", root.display()))
    })
}
