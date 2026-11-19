use std::{
    fs::File,
    io::{self, Read, Seek, SeekFrom},
    path::Path,
};

const WIDTH: u32 = 256;
const HEIGHT: u32 = 128;
const PARENT_COUNT: u32 = WIDTH * HEIGHT / 4;

pub struct CoverPack {
    file: File,
    offsets: Vec<u64>,
    decoder: zstd::bulk::Decompressor<'static>,
    legacy: bool,
}

impl CoverPack {
    pub const FILE_NAMES: [&'static str; 2] = ["landscape-cover-v2.qsc", "landscape-cover-v1.qsc"];

    pub fn open(path: &Path, page: u32) -> io::Result<Self> {
        let mut file = File::open(path)?;
        let mut header = [0; 20];
        file.read_exact(&mut header)?;
        let legacy = &header[..8] == b"WWOZ7LC1";
        let parent_count = if legacy { 0 } else { PARENT_COUNT };
        let mut raw = vec![0; ((WIDTH * HEIGHT + parent_count + 1) * 8) as usize];
        file.read_exact(&mut raw)?;
        let offsets: Vec<_> = raw
            .chunks_exact(8)
            .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        if (!legacy && &header[..8] != b"WWOZ7LC2")
            || header[8..12] != WIDTH.to_le_bytes()
            || header[12..16] != HEIGHT.to_le_bytes()
            || header[16..20] != page.to_le_bytes()
            || offsets[0] != (raw.len() + header.len()) as u64
            || offsets.last() != Some(&file.metadata()?.len())
            || offsets.windows(2).any(|pair| {
                pair[1]
                    .checked_sub(pair[0])
                    .is_none_or(|size| size > u64::from(page * page) + 256)
            })
        {
            return Err(io::Error::other(format!(
                "Invalid landscape cover pack: {}",
                path.display()
            )));
        }
        Ok(Self {
            file,
            offsets,
            decoder: zstd::bulk::Decompressor::new()?,
            legacy,
        })
    }

    pub fn read(&mut self, level: u32, x: u32, y: u32, size: usize) -> io::Result<Vec<u8>> {
        let index = match level {
            6 if !self.legacy => y * (WIDTH / 2) + x,
            7 => y * WIDTH + x + if self.legacy { 0 } else { PARENT_COUNT },
            _ => return Ok(vec![0; size]),
        } as usize;
        let start = self.offsets[index];
        let count = (self.offsets[index + 1] - start) as usize;
        if count == 0 {
            return Ok(vec![0; size]);
        }
        let mut compressed = vec![0; count];
        self.file.seek(SeekFrom::Start(start))?;
        self.file.read_exact(&mut compressed)?;
        let mut cover = self.decoder.decompress(&compressed, size)?;
        let max_class = if self.legacy { 4 } else { 11 };
        if cover.len() != size || cover.iter().any(|&class| class > max_class) {
            return Err(io::Error::other(format!(
                "Invalid landscape cover page: {level}/{x}/{y}"
            )));
        }
        if self.legacy {
            for class in &mut cover {
                *class = [0, 1, 6, 3, 7][usize::from(*class)];
            }
        }
        Ok(cover)
    }
}
