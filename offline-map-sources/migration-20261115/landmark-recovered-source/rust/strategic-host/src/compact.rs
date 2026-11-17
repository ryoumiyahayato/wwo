use bytemuck::{Pod, Zeroable};
use flate2::read::ZlibDecoder;
use serde::Deserialize;
use serde_json::Value;
use std::{
    collections::BTreeMap,
    fs::File,
    io::{self, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
};

pub const REGIONS: [&str; 3] = ["alps", "paris", "genoa"];
const LEGACY_SIGNATURE: &[u8; 8] = b"WWOCM2\0\0";

#[derive(Clone)]
pub struct Pack {
    path: PathBuf,
    start: u64,
    blocks: BTreeMap<String, Entry>,
}

#[derive(Deserialize)]
struct Header {
    blocks: BTreeMap<String, Entry>,
}

#[derive(Clone, Deserialize)]
struct Entry(u64, usize, #[allow(dead_code)] Value);

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct Vertex {
    pub position: [f32; 2],
    pub color: [u8; 4],
    pub uv: [f32; 2],
}

pub struct Raster {
    pub size: [u32; 2],
    pub pixels: Vec<u8>,
}

impl Pack {
    pub fn check_signature(path: &Path, expected: &[u8; 8]) -> io::Result<()> {
        let mut file = File::open(path).map_err(|e|{
            io::Error::new(e.kind(),format!("{} · {e}",path.display()))
        })?;
        Self::read_signature(&mut file, path, expected)
    }

    fn read_signature(file: &mut File, path: &Path, expected: &[u8; 8]) -> io::Result<()> {
        let mut signature = [0; 8];
        file.read_exact(&mut signature).map_err(|e|{
            io::Error::new(e.kind(),format!("{} · {e}",path.display()))
        })?;
        if &signature != expected {
            return Err(io::Error::new(io::ErrorKind::InvalidData, format!(
                "地图分片格式不匹配。{} 需要 {}，实际为 {}",
                path.display(),
                String::from_utf8_lossy(expected).trim_end_matches('\0'),
                String::from_utf8_lossy(&signature).trim_end_matches('\0'),
            )));
        }
        Ok(())
    }

    pub fn open_version(path: &Path, signature: Option<&[u8; 8]>) -> io::Result<Self> {
        let mut file = File::open(path)?;
        Self::read_signature(&mut file, path, signature.unwrap_or(LEGACY_SIGNATURE))?;
        let mut length = [0; 4];
        file.read_exact(&mut length)?;
        let length = u32::from_le_bytes(length);
        if length > 1024 * 1024 {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "WWOCM2 index length"));
        }
        let mut bytes = vec![0; length as usize];
        file.read_exact(&mut bytes)?;
        let header: Header = serde_json::from_slice(&bytes)?;
        Ok(Self {
            path: path.to_owned(),
            start: 12 + u64::from(length),
            blocks: header.blocks,
        })
    }

    pub fn block(&self, key: &str, expected: usize) -> io::Result<Vec<u8>> {
        let Entry(offset, length, _) = self.blocks.get(key)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, format!("missing {key}")))?;
        let mut file = File::open(&self.path)?;
        file.seek(SeekFrom::Start(self.start + offset))?;
        let mut result = Vec::with_capacity(expected);
        ZlibDecoder::new(file.take(*length as u64)).take(expected as u64 + 1).read_to_end(&mut result)?;
        if result.len() != expected {
            return Err(io::Error::new(io::ErrorKind::InvalidData, format!("invalid length for {key}")));
        }
        Ok(result)
    }

}
