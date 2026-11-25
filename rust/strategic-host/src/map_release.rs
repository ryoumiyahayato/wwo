use crate::{compact::Pack, world::{Tile, World}};
use std::{
    collections::HashSet,
    fs::File,
    io::{self, BufReader, Read},
    path::{Path, PathBuf},
};

pub const VERSION: &str = "regional-2026-11-14";
pub const TILE_SIGNATURE: &[u8; 8] = b"WWORGN1\0";
const ART_FILES: [&str; 2] = [
    "political-flags-hd.png",
    "galactic-chart.png",
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
        }
        Pack::check_signature(&root.join(&world.tiles[0].path), TILE_SIGNATURE)?;
        for name in ART_FILES {
            open_art(root, name)?;
        }
        Ok(world)
    };
    check().map_err(|e| {
        io::Error::other(format!("正式地图需要 {VERSION}。{} · {e}", root.display()))
    })
}

pub fn add_city_ground(world: &mut World, data: &Path) -> io::Result<Vec<String>> {
    #[derive(serde::Deserialize)]
    struct Catalogue { tiles: Vec<Tile> }

    let folder = data.join("city-overlays");
    let path = folder.join("catalogue.json");
    let file = File::open(&path).map_err(|error|io::Error::other(format!("{} · {error}",path.display())))?;
    let mut catalogue: Catalogue = serde_json::from_reader(file)?;
    let mut seen = HashSet::new();
    let mut warnings = Vec::new();
    for tile in &mut catalogue.tiles {
        if !tile.city || tile.level != 3 || tile.cover || tile.ids
            || tile.size.iter().any(|size| !(2..=1024).contains(size))
            || !tile.path.ends_with(".wcm")
            || !tile.path.bytes().all(|byte| byte.is_ascii_alphanumeric() || b"-_.".contains(&byte))
            || !seen.insert(tile.path.clone())
        {
            return Err(io::Error::other(format!("无效的城市分片 {}", tile.path)));
        }
        let path = folder.join(&tile.path);
        if let Err(error) = Pack::check_signature(&path, TILE_SIGNATURE) {
            warnings.push(format!("City ground {} · {error}", path.display()));
            continue;
        }
        tile.path = path.canonicalize()?.to_string_lossy().into_owned();
        tile.city_ink_only = true;
    }
    world.tiles.extend(catalogue.tiles.into_iter().filter(|tile| tile.city_ink_only));
    Ok(warnings)
}
